//! Deterministic, durable orchestration state for sequential VM transfers.

use crate::hyperv_transfer_plan::HyperVTransferPlan;
use crate::{EffectAuthorization, TransferObservation};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

pub const TRANSFER_BATCH_SCHEMA_VERSION: &str = "pedantic.transfer-batch.v1";
const EFFECT_AUTHORIZATION_SCHEMA_VERSION: &str = "pedantic.effect-authorization.v1";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchTransfer {
    pub number: u64,
    pub operation_id: String,
    pub source_vm: String,
    pub target_vm: String,
    pub provider: String,
    pub input_digest: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferBatchPlan {
    pub schema_version: String,
    pub batch_id: String,
    pub plan_digest: String,
    pub preview: bool,
    pub transfers: Vec<BatchTransfer>,
}

impl TransferBatchPlan {
    pub fn from_hyperv_plan(
        batch_id: String,
        plan: &HyperVTransferPlan,
        provider: String,
        preview: bool,
    ) -> Result<Self, BatchError> {
        plan.validate().map_err(|_| BatchError::InvalidPlan)?;
        if batch_id.is_empty() || provider.is_empty() {
            return Err(BatchError::InvalidPlan);
        }
        let transfers = plan
            .pairs
            .iter()
            .enumerate()
            .map(|(index, pair)| BatchTransfer {
                number: index as u64 + 1,
                operation_id: format!("{}:{}", plan.plan_id, pair.pair_id),
                source_vm: pair.source.name.clone(),
                target_vm: pair.target.name.clone(),
                provider: provider.clone(),
                input_digest: digest(
                    &serde_json::to_value(pair).expect("transfer pair serializes"),
                ),
            })
            .collect::<Vec<_>>();
        Ok(Self {
            schema_version: TRANSFER_BATCH_SCHEMA_VERSION.into(),
            batch_id,
            plan_digest: digest(plan),
            preview,
            transfers,
        })
    }

    pub fn validate(&self) -> Result<(), BatchError> {
        if self.schema_version != TRANSFER_BATCH_SCHEMA_VERSION
            || self.batch_id.is_empty()
            || !is_sha256_digest(&self.plan_digest)
            || self.transfers.is_empty()
            || self.transfers.iter().enumerate().any(|(index, transfer)| {
                transfer.number != index as u64 + 1
                    || transfer.operation_id.is_empty()
                    || transfer.source_vm.is_empty()
                    || transfer.target_vm.is_empty()
                    || transfer.provider.is_empty()
                    || !is_sha256_digest(&transfer.input_digest)
            })
        {
            return Err(BatchError::InvalidPlan);
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum BatchTransferState {
    Pending,
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Skipped,
    Excluded,
    NeedsReview,
}

impl BatchTransferState {
    fn terminal(&self) -> bool {
        !matches!(self, Self::Pending | Self::Running)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalRecord {
    pub approval_id: String,
    pub transfer_number: u64,
    pub plan_digest: String,
    pub operation_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authorization_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authorization_digest: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authorization: Option<EffectAuthorization>,
    pub approved: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchPolicyDecision {
    pub accepted: bool,
    pub constraint_id: String,
    pub reason: String,
    pub outcome: BatchTransferState,
    pub continue_batch: bool,
}

pub struct BatchAuthorizationContext<'a> {
    pub key: &'a VerifyingKey,
    pub expected_key_id: &'a str,
    pub expected_fencing_token: u64,
    pub now: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchTransferProgress {
    pub transfer: BatchTransfer,
    pub state: BatchTransferState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval: Option<ApprovalRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub policy_decision: Option<BatchPolicyDecision>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub observation: Option<TransferObservation>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferBatchProgress {
    pub schema_version: String,
    #[serde(default)]
    pub revision: u64,
    #[serde(default = "default_continue_batch")]
    pub continue_batch: bool,
    pub plan: TransferBatchPlan,
    pub transfers: Vec<BatchTransferProgress>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchTransferReport {
    pub number: u64,
    pub operation_id: String,
    pub source_vm: String,
    pub state: BatchTransferState,
    pub provider: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub elapsed_millis: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bytes_transferred: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub throughput_bps: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_count: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verification_state: Option<String>,
    pub next_action: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchReport {
    pub batch_id: String,
    pub plan_digest: String,
    pub preview: bool,
    pub transfers: Vec<BatchTransferReport>,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum BatchError {
    #[error("transfer batch plan is invalid")]
    InvalidPlan,
    #[error("preview batches cannot start transfers")]
    PreviewOnly,
    #[error("transfer selection is ambiguous")]
    AmbiguousSelection,
    #[error("transfer selection does not exist")]
    UnknownSelection,
    #[error("transfer {0} has already completed")]
    AlreadyCompleted(u64),
    #[error("transfer {selected} is not the next eligible transfer; expected {expected}")]
    NotNext { selected: u64, expected: u64 },
    #[error("transfer {0} is active and must be resumed first")]
    ActiveTransfer(u64),
    #[error("approval must be a valid signed effect authorization bound to this transfer")]
    InvalidAuthorization,
    #[error("approval has not been recorded for transfer {0}")]
    ApprovalRequired(u64),
    #[error("no transfer is active")]
    NoActiveTransfer,
    #[error("PX policy rejected this transfer transition")]
    PolicyRejected,
    #[error("transfer batch revision counter is exhausted")]
    RevisionExhausted,
    #[error("PX policy stopped this transfer batch")]
    BatchStopped,
}

impl TransferBatchProgress {
    pub fn new(plan: TransferBatchPlan) -> Result<Self, BatchError> {
        plan.validate()?;
        Ok(Self {
            schema_version: TRANSFER_BATCH_SCHEMA_VERSION.into(),
            revision: 0,
            continue_batch: true,
            transfers: plan
                .transfers
                .iter()
                .cloned()
                .map(|transfer| BatchTransferProgress {
                    transfer,
                    state: BatchTransferState::Pending,
                    approval: None,
                    policy_decision: None,
                    observation: None,
                })
                .collect(),
            plan,
        })
    }

    pub fn select(&self, number: Option<u64>, source_vm: Option<&str>) -> Result<u64, BatchError> {
        if !self.continue_batch {
            return Err(BatchError::BatchStopped);
        }
        let matches = self
            .transfers
            .iter()
            .filter(|transfer| {
                number.is_none_or(|number| transfer.transfer.number == number)
                    && source_vm.is_none_or(|source_vm| transfer.transfer.source_vm == source_vm)
            })
            .collect::<Vec<_>>();
        let [transfer] = matches.as_slice() else {
            return if matches.is_empty() {
                Err(BatchError::UnknownSelection)
            } else {
                Err(BatchError::AmbiguousSelection)
            };
        };
        if let Some(error) = self.active_error()
            && transfer.state != BatchTransferState::Running
        {
            return Err(error);
        }
        if transfer.state.terminal() {
            return Err(BatchError::AlreadyCompleted(transfer.transfer.number));
        }
        Ok(transfer.transfer.number)
    }

    pub fn approve(
        &mut self,
        number: u64,
        approval_id: String,
        authorization: EffectAuthorization,
        context: &BatchAuthorizationContext<'_>,
    ) -> Result<(), BatchError> {
        self.ensure_next(number)?;
        let plan_digest = self.plan.plan_digest.clone();
        let transfer = self
            .transfers
            .iter()
            .find(|transfer| transfer.transfer.number == number)
            .ok_or(BatchError::UnknownSelection)?;
        if approval_id.is_empty()
            || validate_authorization(&authorization, &transfer.transfer, context).is_err()
        {
            return Err(BatchError::InvalidAuthorization);
        }
        let authorization_id = authorization.authorization_id.clone();
        let authorization_digest = authorization.digest();
        let operation_id = transfer.transfer.operation_id.clone();
        self.advance_revision()?;
        let transfer = self.transfer_mut(number)?;
        transfer.approval = Some(ApprovalRecord {
            approval_id,
            transfer_number: number,
            plan_digest,
            operation_id,
            authorization_id: Some(authorization_id),
            authorization_digest: Some(authorization_digest),
            authorization: Some(authorization),
            approved: true,
        });
        Ok(())
    }

    pub fn deny(
        &mut self,
        number: u64,
        approval_id: String,
        decision: BatchPolicyDecision,
    ) -> Result<(), BatchError> {
        validate_policy_decision(&decision)?;
        if !matches!(
            decision.outcome,
            BatchTransferState::NeedsReview
                | BatchTransferState::Skipped
                | BatchTransferState::Excluded
        ) {
            return Err(BatchError::PolicyRejected);
        }
        self.ensure_next(number)?;
        if approval_id.is_empty() {
            return Err(BatchError::InvalidAuthorization);
        }
        let plan_digest = self.plan.plan_digest.clone();
        self.advance_revision()?;
        let transfer = self.transfer_mut(number)?;
        transfer.approval = Some(ApprovalRecord {
            approval_id,
            transfer_number: number,
            plan_digest,
            operation_id: transfer.transfer.operation_id.clone(),
            authorization_id: None,
            authorization_digest: None,
            authorization: None,
            approved: false,
        });
        transfer.state = decision.outcome.clone();
        transfer.policy_decision = Some(decision);
        self.continue_batch = transfer
            .policy_decision
            .as_ref()
            .is_some_and(|decision| decision.continue_batch);
        Ok(())
    }

    pub fn transition_pending(
        &mut self,
        number: u64,
        decision: BatchPolicyDecision,
    ) -> Result<(), BatchError> {
        validate_policy_decision(&decision)?;
        if !matches!(
            decision.outcome,
            BatchTransferState::Skipped | BatchTransferState::Excluded
        ) {
            return Err(BatchError::PolicyRejected);
        }
        self.ensure_next(number)?;
        self.advance_revision()?;
        let transfer = self.transfer_mut(number)?;
        transfer.state = decision.outcome.clone();
        transfer.policy_decision = Some(decision);
        Ok(())
    }

    pub fn start(
        &mut self,
        number: u64,
        context: &BatchAuthorizationContext<'_>,
    ) -> Result<(), BatchError> {
        if self.plan.preview {
            return Err(BatchError::PreviewOnly);
        }
        self.ensure_next(number)?;
        let transfer = self
            .transfers
            .iter()
            .find(|transfer| transfer.transfer.number == number)
            .ok_or(BatchError::UnknownSelection)?;
        let authorization = transfer
            .approval
            .as_ref()
            .filter(|approval| approval.approved)
            .and_then(|approval| approval.authorization.as_ref())
            .ok_or(BatchError::ApprovalRequired(number))?;
        if transfer
            .approval
            .as_ref()
            .and_then(|approval| approval.authorization_digest.as_deref())
            != Some(authorization.digest().as_str())
            || validate_authorization(authorization, &transfer.transfer, context).is_err()
        {
            return Err(BatchError::InvalidAuthorization);
        }
        self.advance_revision()?;
        self.transfer_mut(number)?.state = BatchTransferState::Running;
        Ok(())
    }

    pub fn finish(
        &mut self,
        number: u64,
        state: BatchTransferState,
        observation: Option<TransferObservation>,
    ) -> Result<(), BatchError> {
        if !matches!(
            state,
            BatchTransferState::Succeeded
                | BatchTransferState::Failed
                | BatchTransferState::Cancelled
        ) || (state == BatchTransferState::Succeeded && observation.is_none())
        {
            return Err(BatchError::InvalidPlan);
        }
        if self
            .transfers
            .iter()
            .find(|transfer| transfer.transfer.number == number)
            .ok_or(BatchError::UnknownSelection)?
            .state
            != BatchTransferState::Running
        {
            return Err(self.active_error().unwrap_or(BatchError::NoActiveTransfer));
        }
        self.advance_revision()?;
        let transfer = self.transfer_mut(number)?;
        transfer.state = state;
        transfer.observation = observation;
        Ok(())
    }

    pub fn report(&self) -> BatchReport {
        BatchReport {
            batch_id: self.plan.batch_id.clone(),
            plan_digest: self.plan.plan_digest.clone(),
            preview: self.plan.preview,
            transfers: self
                .transfers
                .iter()
                .map(|transfer| BatchTransferReport {
                    number: transfer.transfer.number,
                    operation_id: transfer.transfer.operation_id.clone(),
                    source_vm: transfer.transfer.source_vm.clone(),
                    state: transfer.state.clone(),
                    provider: transfer.observation.as_ref().map_or_else(
                        || transfer.transfer.provider.clone(),
                        |observation| observation.provider.clone(),
                    ),
                    elapsed_millis: transfer
                        .observation
                        .as_ref()
                        .map(|observation| observation.elapsed_millis),
                    bytes_transferred: transfer
                        .observation
                        .as_ref()
                        .map(|observation| observation.bytes_transferred),
                    throughput_bps: transfer
                        .observation
                        .as_ref()
                        .map(|observation| observation.throughput_bps),
                    retry_count: transfer
                        .observation
                        .as_ref()
                        .map(|observation| observation.retry_count),
                    verification_state: transfer
                        .observation
                        .as_ref()
                        .map(|observation| observation.verification_state.clone()),
                    next_action: next_action(transfer, self.plan.preview, self.continue_batch),
                })
                .collect(),
        }
    }

    fn ensure_next(&self, number: u64) -> Result<(), BatchError> {
        if !self.continue_batch {
            return Err(BatchError::BatchStopped);
        }
        if let Some(error) = self.active_error() {
            return Err(error);
        }
        let next = self
            .transfers
            .iter()
            .find(|transfer| transfer.state == BatchTransferState::Pending)
            .map(|transfer| transfer.transfer.number)
            .ok_or(BatchError::UnknownSelection)?;
        if number != next {
            return Err(BatchError::NotNext {
                selected: number,
                expected: next,
            });
        }
        Ok(())
    }

    fn active_error(&self) -> Option<BatchError> {
        self.transfers
            .iter()
            .find(|transfer| transfer.state == BatchTransferState::Running)
            .map(|transfer| BatchError::ActiveTransfer(transfer.transfer.number))
    }

    fn transfer_mut(&mut self, number: u64) -> Result<&mut BatchTransferProgress, BatchError> {
        self.transfers
            .iter_mut()
            .find(|transfer| transfer.transfer.number == number)
            .ok_or(BatchError::UnknownSelection)
    }

    fn advance_revision(&mut self) -> Result<(), BatchError> {
        self.revision = self
            .revision
            .checked_add(1)
            .ok_or(BatchError::RevisionExhausted)?;
        Ok(())
    }
}

fn validate_policy_decision(decision: &BatchPolicyDecision) -> Result<(), BatchError> {
    if !decision.accepted || decision.constraint_id.is_empty() || decision.reason.is_empty() {
        return Err(BatchError::PolicyRejected);
    }
    Ok(())
}

fn default_continue_batch() -> bool {
    true
}

fn validate_authorization(
    authorization: &EffectAuthorization,
    transfer: &BatchTransfer,
    context: &BatchAuthorizationContext<'_>,
) -> Result<(), BatchError> {
    if authorization.schema_version != EFFECT_AUTHORIZATION_SCHEMA_VERSION
        || authorization.authorization_id.is_empty()
        || authorization.issuer_id.is_empty()
        || authorization.actor_id.is_empty()
        || authorization.profile_id.is_empty()
        || authorization.operation_id != transfer.operation_id
        || authorization.step_id.is_empty()
        || authorization.attempt_id.is_empty()
        || authorization.target_id != transfer.target_vm
        || authorization.agent_id.is_empty()
        || authorization.capability != transfer.provider
        || authorization.input_digest != transfer.input_digest
        || authorization.idempotency_key.is_empty()
        || authorization.fencing_token == 0
        || authorization.fencing_token != context.expected_fencing_token
        || authorization.issued_at > context.now
        || authorization.expires_at <= context.now
        || authorization.expires_at <= authorization.issued_at
        || authorization.revoked_at != 0
        || authorization.signature.algorithm != "Ed25519"
        || authorization.signature.key_id != context.expected_key_id
        || authorization.signature.payload_digest != authorization.digest()
    {
        return Err(BatchError::InvalidAuthorization);
    }
    let signature_bytes = URL_SAFE_NO_PAD
        .decode(&authorization.signature.value)
        .map_err(|_| BatchError::InvalidAuthorization)?;
    let signature =
        Signature::from_slice(&signature_bytes).map_err(|_| BatchError::InvalidAuthorization)?;
    context
        .key
        .verify(&authorization.signing_payload(), &signature)
        .map_err(|_| BatchError::InvalidAuthorization)
}

fn next_action(transfer: &BatchTransferProgress, preview: bool, continue_batch: bool) -> String {
    match transfer.state {
        BatchTransferState::Pending if !continue_batch => "policy-review".into(),
        BatchTransferState::Pending if preview => "preview-only".into(),
        BatchTransferState::Pending => "approval-required".into(),
        BatchTransferState::Running => "resume-active-transfer".into(),
        BatchTransferState::Succeeded => "complete".into(),
        BatchTransferState::Failed | BatchTransferState::Cancelled => "policy-review".into(),
        BatchTransferState::Skipped
        | BatchTransferState::Excluded
        | BatchTransferState::NeedsReview => "needs-review".into(),
    }
}

fn digest<T: Serialize>(value: &T) -> String {
    format!(
        "sha256:{:x}",
        Sha256::digest(serde_json::to_vec(value).expect("transfer plan serializes"))
    )
}

fn is_sha256_digest(value: &str) -> bool {
    value.len() == 71
        && value.starts_with("sha256:")
        && value[7..]
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan(preview: bool) -> TransferBatchPlan {
        TransferBatchPlan {
            schema_version: TRANSFER_BATCH_SCHEMA_VERSION.into(),
            batch_id: "batch-1".into(),
            plan_digest: format!("sha256:{}", "a".repeat(64)),
            preview,
            transfers: (1..=5)
                .map(|number| BatchTransfer {
                    number,
                    operation_id: format!("operation-{number}"),
                    source_vm: format!("source-{number}"),
                    target_vm: format!("target-{number}"),
                    provider: "filesystem".into(),
                    input_digest: format!("sha256:{}", "b".repeat(64)),
                })
                .collect(),
        }
    }

    fn approve(progress: &mut TransferBatchProgress, number: u64) {
        use ed25519_dalek::Signer;

        let key = test_signing_key();
        let mut authorization = EffectAuthorization {
            schema_version: EFFECT_AUTHORIZATION_SCHEMA_VERSION.into(),
            authorization_id: format!("authorization-{number}"),
            issuer_id: "px".into(),
            actor_id: "operator".into(),
            profile_id: "profile".into(),
            operation_id: format!("operation-{number}"),
            step_id: "transfer".into(),
            attempt_id: format!("attempt-{number}"),
            target_id: format!("target-{number}"),
            agent_id: "agent".into(),
            capability: "filesystem".into(),
            input_digest: progress.transfers[(number - 1) as usize]
                .transfer
                .input_digest
                .clone(),
            idempotency_key: format!("idempotency-{number}"),
            fencing_token: number,
            retry_class: crate::RetryClass::Safe,
            risk_class: crate::RiskClass::Moderate,
            reboot_permitted: false,
            issued_at: 1,
            expires_at: 200,
            revoked_at: 0,
            signature: crate::Signature {
                algorithm: "Ed25519".into(),
                key_id: format!(
                    "pedantic-service-sha256:{:x}",
                    Sha256::digest(key.verifying_key().as_bytes())
                ),
                payload_digest: String::new(),
                value: String::new(),
            },
        };
        authorization.signature.payload_digest = authorization.digest();
        authorization.signature.value =
            URL_SAFE_NO_PAD.encode(key.sign(&authorization.signing_payload()).to_bytes());
        let expected_key_id = authorization.signature.key_id.clone();
        let verifying_key = key.verifying_key();
        let context = BatchAuthorizationContext {
            key: &verifying_key,
            expected_key_id: &expected_key_id,
            expected_fencing_token: number,
            now: 100,
        };
        progress
            .approve(
                number,
                format!("approval-{number}"),
                authorization,
                &context,
            )
            .unwrap();
    }

    fn test_signing_key() -> ed25519_dalek::SigningKey {
        ed25519_dalek::SigningKey::from_bytes(&[11; 32])
    }

    fn start(progress: &mut TransferBatchProgress, number: u64) -> Result<(), BatchError> {
        let key = test_signing_key();
        let key_id = format!(
            "pedantic-service-sha256:{:x}",
            Sha256::digest(key.verifying_key().as_bytes())
        );
        let verifying_key = key.verifying_key();
        let context = BatchAuthorizationContext {
            key: &verifying_key,
            expected_key_id: &key_id,
            expected_fencing_token: number,
            now: 100,
        };
        progress.start(number, &context)
    }

    fn policy_decision(outcome: BatchTransferState) -> BatchPolicyDecision {
        BatchPolicyDecision {
            accepted: true,
            constraint_id: "transfer_batch_terminal_policy".into(),
            reason: "PX accepted the policy transition.".into(),
            outcome,
            continue_batch: true,
        }
    }

    fn observation() -> TransferObservation {
        TransferObservation {
            provider: "filesystem".into(),
            bytes_transferred: 1024,
            elapsed_millis: 20,
            throughput_bps: 51_200,
            retry_count: 1,
            resume_count: 0,
            verification_state: "verified".into(),
            failure_category: None,
        }
    }

    #[test]
    fn runs_five_transfers_sequentially_with_audited_external_approvals() {
        let mut progress = TransferBatchProgress::new(plan(false)).unwrap();
        for number in 1..=5 {
            approve(&mut progress, number);
            start(&mut progress, number).unwrap();
            assert_eq!(
                progress
                    .transfers
                    .iter()
                    .filter(|transfer| transfer.state == BatchTransferState::Running)
                    .count(),
                1
            );
            progress
                .finish(number, BatchTransferState::Succeeded, Some(observation()))
                .unwrap();
        }
        let report = progress.report();
        assert!(
            report
                .transfers
                .iter()
                .all(|transfer| transfer.state == BatchTransferState::Succeeded)
        );
        assert!(report.transfers.iter().all(|transfer| {
            transfer.bytes_transferred == Some(1024)
                && transfer.elapsed_millis == Some(20)
                && transfer.retry_count == Some(1)
                && transfer.verification_state.as_deref() == Some("verified")
        }));
    }

    #[test]
    fn rejects_bypass_ambiguous_selection_and_starting_a_second_transfer() {
        let mut progress = TransferBatchProgress::new(plan(false)).unwrap();
        assert_eq!(
            start(&mut progress, 1),
            Err(BatchError::ApprovalRequired(1))
        );
        assert_eq!(
            progress.select(None, Some("source-1")),
            Ok(1),
            "exact source name is selectable"
        );
        assert_eq!(
            progress.select(None, None),
            Err(BatchError::AmbiguousSelection)
        );
        approve(&mut progress, 1);
        start(&mut progress, 1).unwrap();
        assert_eq!(start(&mut progress, 2), Err(BatchError::ActiveTransfer(1)));
    }

    #[test]
    fn denial_failure_cancellation_and_restart_remain_visible() {
        let mut progress = TransferBatchProgress::new(plan(false)).unwrap();
        progress
            .deny(
                1,
                "denied-1".into(),
                policy_decision(BatchTransferState::NeedsReview),
            )
            .unwrap();
        approve(&mut progress, 2);
        start(&mut progress, 2).unwrap();
        let restored: TransferBatchProgress =
            serde_json::from_str(&serde_json::to_string(&progress).unwrap()).unwrap();
        assert_eq!(
            restored.report().transfers[1].next_action,
            "resume-active-transfer"
        );

        let mut progress = restored;
        progress
            .finish(2, BatchTransferState::Failed, Some(observation()))
            .unwrap();
        approve(&mut progress, 3);
        start(&mut progress, 3).unwrap();
        progress
            .finish(3, BatchTransferState::Cancelled, None)
            .unwrap();
        let report = progress.report();
        assert_eq!(report.transfers[0].state, BatchTransferState::NeedsReview);
        assert_eq!(report.transfers[1].next_action, "policy-review");
        assert_eq!(report.transfers[2].next_action, "policy-review");
    }

    #[test]
    fn preview_never_starts_a_transfer() {
        let mut progress = TransferBatchProgress::new(plan(true)).unwrap();
        approve(&mut progress, 1);
        assert_eq!(start(&mut progress, 1), Err(BatchError::PreviewOnly));
        assert_eq!(progress.report().transfers[0].next_action, "preview-only");
    }

    #[test]
    fn policy_transitions_skip_or_exclude_pending_transfers() {
        let mut progress = TransferBatchProgress::new(plan(false)).unwrap();
        progress
            .transition_pending(1, policy_decision(BatchTransferState::Skipped))
            .unwrap();
        progress
            .transition_pending(2, policy_decision(BatchTransferState::Excluded))
            .unwrap();
        assert_eq!(progress.revision, 2);
        assert_eq!(progress.transfers[0].state, BatchTransferState::Skipped);
        assert_eq!(
            progress.transfers[0].policy_decision,
            Some(policy_decision(BatchTransferState::Skipped))
        );
        assert_eq!(progress.transfers[1].state, BatchTransferState::Excluded);
        assert_eq!(
            progress.transition_pending(
                3,
                BatchPolicyDecision {
                    accepted: false,
                    constraint_id: "rejected".into(),
                    reason: "not allowed".into(),
                    outcome: BatchTransferState::Skipped,
                    continue_batch: true,
                },
            ),
            Err(BatchError::PolicyRejected)
        );

        let mut stopped = TransferBatchProgress::new(plan(false)).unwrap();
        let mut decision = policy_decision(BatchTransferState::NeedsReview);
        decision.continue_batch = false;
        stopped.deny(1, "denied-1".into(), decision).unwrap();
        assert!(!stopped.continue_batch);
        assert_eq!(start(&mut stopped, 2), Err(BatchError::BatchStopped));
        assert_eq!(stopped.report().transfers[1].next_action, "policy-review");
        assert_eq!(stopped.select(Some(2), None), Err(BatchError::BatchStopped));

        let mut running = TransferBatchProgress::new(plan(false)).unwrap();
        approve(&mut running, 1);
        start(&mut running, 1).unwrap();
        assert_eq!(
            running.finish(1, BatchTransferState::Skipped, None),
            Err(BatchError::InvalidPlan)
        );
        assert_eq!(running.transfers[0].state, BatchTransferState::Running);
    }
}
