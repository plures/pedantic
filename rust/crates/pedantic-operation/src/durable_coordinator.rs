//! Deterministic, serializable state for a durable coordinator.
//!
//! Storage belongs to the service. This module defines the facts that must
//! survive coordinator replacement and the checks an ephemeral target agent
//! performs before executing an effect.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use thiserror::Error;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanAuthority {
    pub plan_id: String,
    pub operation_id: String,
    pub target_id: String,
    pub agent_id: String,
    pub expires_at: u64,
    pub revoked_at: u64,
    pub ownership_manifest: BTreeSet<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EffectLease {
    pub lease_id: String,
    pub plan_id: String,
    pub operation_id: String,
    pub step_id: String,
    pub attempt_id: String,
    pub target_id: String,
    pub agent_id: String,
    pub fencing_token: u64,
    pub expires_at: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum CoordinatorState {
    Active,
    Suspended,
    AwaitingApproval,
    Cancelled,
    TerminatedWithCleanupRequired,
    Terminated,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChildEffect {
    pub child_id: String,
    pub lease_id: String,
    pub cancelled: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupVerification {
    pub verifier_id: String,
    pub independent_of_agent: bool,
    pub ownership_manifest: BTreeSet<String>,
    pub removed_resources: BTreeSet<String>,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum CoordinatorError {
    #[error("plan authority is expired or revoked")]
    AuthorityInactive,
    #[error("plan authority does not bind this target-local effect")]
    AuthorityBinding,
    #[error("resource is not owned by the plan")]
    UnownedResource,
    #[error("lease is expired or stale")]
    LeaseInactive,
    #[error("lease does not bind this target-local effect")]
    LeaseBinding,
    #[error("coordinator is not accepting new effects")]
    NotActive,
    #[error("approval is required before effects may be offered")]
    ApprovalRequired,
    #[error("cleanup must be verified independently of the ephemeral agent")]
    CleanupNotIndependent,
    #[error("cleanup verification does not account for every owned resource")]
    CleanupIncomplete,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DurableCoordinator {
    pub state: CoordinatorState,
    pub authority: PlanAuthority,
    pub highest_fencing_tokens: BTreeMap<String, u64>,
    pub children: BTreeMap<String, ChildEffect>,
    approval_required: bool,
    pending_approval: Option<PendingApproval>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
struct PendingApproval {
    lease: EffectLease,
    approved: bool,
}

impl DurableCoordinator {
    pub fn new(authority: PlanAuthority, approval_required: bool) -> Self {
        Self {
            state: CoordinatorState::Active,
            authority,
            highest_fencing_tokens: BTreeMap::new(),
            children: BTreeMap::new(),
            approval_required,
            pending_approval: None,
        }
    }

    pub fn offer(&mut self, lease: EffectLease, now: u64) -> Result<(), CoordinatorError> {
        self.validate_authority(&lease, now)?;
        if self.state != CoordinatorState::Active
            && self.state != CoordinatorState::AwaitingApproval
        {
            return Err(CoordinatorError::NotActive);
        }
        let highest = self
            .highest_fencing_tokens
            .get(&lease.step_id)
            .copied()
            .unwrap_or_default();
        if lease.fencing_token <= highest || lease.expires_at <= now {
            return Err(CoordinatorError::LeaseInactive);
        }
        if self.approval_required {
            match self.pending_approval.as_ref() {
                Some(pending) if pending.lease != lease => {
                    return Err(CoordinatorError::ApprovalRequired);
                }
                Some(pending) if pending.approved => {
                    self.pending_approval = None;
                }
                Some(_) => {
                    self.state = CoordinatorState::AwaitingApproval;
                    return Err(CoordinatorError::ApprovalRequired);
                }
                None => {
                    self.pending_approval = Some(PendingApproval {
                        lease: lease.clone(),
                        approved: false,
                    });
                    self.state = CoordinatorState::AwaitingApproval;
                    return Err(CoordinatorError::ApprovalRequired);
                }
            }
        } else if self.state != CoordinatorState::Active {
            return Err(CoordinatorError::NotActive);
        }
        if self.state == CoordinatorState::AwaitingApproval {
            return Err(CoordinatorError::ApprovalRequired);
        }
        self.highest_fencing_tokens
            .insert(lease.step_id.clone(), lease.fencing_token);
        self.children.insert(
            lease.lease_id.clone(),
            ChildEffect {
                child_id: lease.attempt_id.clone(),
                lease_id: lease.lease_id,
                cancelled: false,
            },
        );
        Ok(())
    }

    pub fn approve(&mut self) {
        if self.state == CoordinatorState::AwaitingApproval
            && let Some(pending) = self.pending_approval.as_mut()
        {
            pending.approved = true;
            self.state = CoordinatorState::Active;
        }
    }

    pub fn cancel(&mut self) {
        self.state = CoordinatorState::Cancelled;
        for child in self.children.values_mut() {
            child.cancelled = true;
        }
    }

    pub fn require_cleanup(&mut self) {
        self.state = CoordinatorState::TerminatedWithCleanupRequired;
        for child in self.children.values_mut() {
            child.cancelled = true;
        }
    }

    pub fn verify_cleanup(
        &mut self,
        verification: &CleanupVerification,
    ) -> Result<(), CoordinatorError> {
        if !verification.independent_of_agent || verification.verifier_id.is_empty() {
            return Err(CoordinatorError::CleanupNotIndependent);
        }
        if verification.ownership_manifest != self.authority.ownership_manifest
            || verification.removed_resources != self.authority.ownership_manifest
        {
            return Err(CoordinatorError::CleanupIncomplete);
        }
        if self.state == CoordinatorState::TerminatedWithCleanupRequired {
            self.state = CoordinatorState::Terminated;
        }
        Ok(())
    }

    pub fn validate_agent_execution(
        &self,
        lease: &EffectLease,
        now: u64,
        resource: &str,
    ) -> Result<(), CoordinatorError> {
        self.validate_authority(lease, now)?;
        if self.state != CoordinatorState::Active {
            return Err(CoordinatorError::NotActive);
        }
        if self
            .highest_fencing_tokens
            .get(&lease.step_id)
            .is_none_or(|token| *token != lease.fencing_token)
            || lease.expires_at <= now
        {
            return Err(CoordinatorError::LeaseInactive);
        }
        if !self.authority.ownership_manifest.contains(resource) {
            return Err(CoordinatorError::UnownedResource);
        }
        Ok(())
    }

    fn validate_authority(&self, lease: &EffectLease, now: u64) -> Result<(), CoordinatorError> {
        if self.authority.expires_at <= now
            || (self.authority.revoked_at != 0 && self.authority.revoked_at <= now)
        {
            return Err(CoordinatorError::AuthorityInactive);
        }
        if self.authority.plan_id != lease.plan_id
            || self.authority.operation_id != lease.operation_id
            || self.authority.target_id != lease.target_id
            || self.authority.agent_id != lease.agent_id
        {
            return Err(CoordinatorError::AuthorityBinding);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn authority() -> PlanAuthority {
        PlanAuthority {
            plan_id: "plan".into(),
            operation_id: "operation".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            expires_at: 20,
            revoked_at: 0,
            ownership_manifest: BTreeSet::from(["resource".into()]),
        }
    }

    fn lease(token: u64) -> EffectLease {
        EffectLease {
            lease_id: format!("lease-{token}"),
            plan_id: "plan".into(),
            operation_id: "operation".into(),
            step_id: "step".into(),
            attempt_id: format!("attempt-{token}"),
            target_id: "target".into(),
            agent_id: "agent".into(),
            fencing_token: token,
            expires_at: 10,
        }
    }

    #[test]
    fn stale_lease_cannot_execute_after_a_new_offer() {
        let mut coordinator = DurableCoordinator::new(authority(), false);
        coordinator.offer(lease(1), 1).unwrap();
        coordinator.offer(lease(2), 2).unwrap();

        assert_eq!(
            coordinator.validate_agent_execution(&lease(1), 3, "resource"),
            Err(CoordinatorError::LeaseInactive)
        );
        assert!(
            coordinator
                .validate_agent_execution(&lease(2), 3, "resource")
                .is_ok()
        );
    }

    #[test]
    fn approval_is_bound_to_the_persisted_lease() {
        let mut coordinator = DurableCoordinator::new(authority(), true);
        let approved_lease = lease(1);
        assert_eq!(
            coordinator.offer(approved_lease.clone(), 1),
            Err(CoordinatorError::ApprovalRequired)
        );
        coordinator.approve();

        let mut recovered: DurableCoordinator =
            serde_json::from_slice(&serde_json::to_vec(&coordinator).unwrap()).unwrap();
        assert_eq!(
            recovered.offer(lease(2), 2),
            Err(CoordinatorError::ApprovalRequired)
        );
        assert!(recovered.offer(approved_lease, 2).is_ok());
    }

    #[test]
    fn cleanup_required_is_not_a_success_state() {
        let mut coordinator = DurableCoordinator::new(authority(), false);
        coordinator.require_cleanup();

        assert_eq!(
            coordinator.verify_cleanup(&CleanupVerification {
                verifier_id: "agent".into(),
                independent_of_agent: false,
                ownership_manifest: BTreeSet::from(["resource".into()]),
                removed_resources: BTreeSet::from(["resource".into()]),
            }),
            Err(CoordinatorError::CleanupNotIndependent)
        );
        assert_eq!(
            coordinator.state,
            CoordinatorState::TerminatedWithCleanupRequired
        );
    }

    #[test]
    fn independent_complete_cleanup_terminates_coordinator() {
        let mut coordinator = DurableCoordinator::new(authority(), false);
        coordinator.require_cleanup();
        coordinator
            .verify_cleanup(&CleanupVerification {
                verifier_id: "agentless-bootstrap".into(),
                independent_of_agent: true,
                ownership_manifest: BTreeSet::from(["resource".into()]),
                removed_resources: BTreeSet::from(["resource".into()]),
            })
            .unwrap();

        assert_eq!(coordinator.state, CoordinatorState::Terminated);
    }
}
