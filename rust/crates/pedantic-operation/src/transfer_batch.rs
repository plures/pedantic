//! Deterministic, durable orchestration state for sequential VM transfers.

use crate::TransferObservation;
use crate::hyperv_transfer_plan::HyperVTransferPlan;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

pub const TRANSFER_BATCH_SCHEMA_VERSION: &str = "pedantic.transfer-batch.v1";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchTransfer {
    pub number: u64,
    pub operation_id: String,
    pub source_vm: String,
    pub target_vm: String,
    pub provider: String,
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
pub struct ExternalAuthorization {
    pub authorization_id: String,
    pub plan_digest: String,
    pub operation_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalRecord {
    pub approval_id: String,
    pub transfer_number: u64,
    pub plan_digest: String,
    pub operation_id: String,
    pub authorization_id: String,
    pub approved: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchTransferProgress {
    pub transfer: BatchTransfer,
    pub state: BatchTransferState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval: Option<ApprovalRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub observation: Option<TransferObservation>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferBatchProgress {
    pub schema_version: String,
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
    #[error("approval must be an external authorization bound to this plan and operation")]
    InvalidAuthorization,
    #[error("approval has not been recorded for transfer {0}")]
    ApprovalRequired(u64),
    #[error("no transfer is active")]
    NoActiveTransfer,
}

impl TransferBatchProgress {
    pub fn new(plan: TransferBatchPlan) -> Result<Self, BatchError> {
        plan.validate()?;
        Ok(Self {
            schema_version: TRANSFER_BATCH_SCHEMA_VERSION.into(),
            transfers: plan
                .transfers
                .iter()
                .cloned()
                .map(|transfer| BatchTransferProgress {
                    transfer,
                    state: BatchTransferState::Pending,
                    approval: None,
                    observation: None,
                })
                .collect(),
            plan,
        })
    }

    pub fn select(&self, number: Option<u64>, source_vm: Option<&str>) -> Result<u64, BatchError> {
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
        authorization: ExternalAuthorization,
    ) -> Result<(), BatchError> {
        self.ensure_next(number)?;
        let plan_digest = self.plan.plan_digest.clone();
        let transfer = self.transfer_mut(number)?;
        if approval_id.is_empty()
            || authorization.authorization_id.is_empty()
            || authorization.plan_digest != plan_digest
            || authorization.operation_id != transfer.transfer.operation_id
        {
            return Err(BatchError::InvalidAuthorization);
        }
        transfer.approval = Some(ApprovalRecord {
            approval_id,
            transfer_number: number,
            plan_digest,
            operation_id: transfer.transfer.operation_id.clone(),
            authorization_id: authorization.authorization_id,
            approved: true,
        });
        Ok(())
    }

    pub fn deny(&mut self, number: u64, approval_id: String) -> Result<(), BatchError> {
        self.ensure_next(number)?;
        if approval_id.is_empty() {
            return Err(BatchError::InvalidAuthorization);
        }
        let plan_digest = self.plan.plan_digest.clone();
        let transfer = self.transfer_mut(number)?;
        transfer.approval = Some(ApprovalRecord {
            approval_id,
            transfer_number: number,
            plan_digest,
            operation_id: transfer.transfer.operation_id.clone(),
            authorization_id: String::new(),
            approved: false,
        });
        transfer.state = BatchTransferState::NeedsReview;
        Ok(())
    }

    pub fn start(&mut self, number: u64) -> Result<(), BatchError> {
        if self.plan.preview {
            return Err(BatchError::PreviewOnly);
        }
        self.ensure_next(number)?;
        let transfer = self.transfer_mut(number)?;
        if !transfer
            .approval
            .as_ref()
            .is_some_and(|approval| approval.approved)
        {
            return Err(BatchError::ApprovalRequired(number));
        }
        transfer.state = BatchTransferState::Running;
        Ok(())
    }

    pub fn finish(
        &mut self,
        number: u64,
        state: BatchTransferState,
        observation: Option<TransferObservation>,
    ) -> Result<(), BatchError> {
        if !state.terminal()
            || (state == BatchTransferState::Succeeded && observation.is_none())
        {
            return Err(BatchError::InvalidPlan);
        }
        let transfer = self.transfer_mut(number)?;
        if transfer.state != BatchTransferState::Running {
            return Err(self.active_error().unwrap_or(BatchError::NoActiveTransfer));
        }
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
                    next_action: next_action(transfer, self.plan.preview),
                })
                .collect(),
        }
    }

    fn ensure_next(&self, number: u64) -> Result<(), BatchError> {
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
}

fn next_action(transfer: &BatchTransferProgress, preview: bool) -> String {
    match transfer.state {
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
                })
                .collect(),
        }
    }

    fn authorization(progress: &TransferBatchProgress, number: u64) -> ExternalAuthorization {
        ExternalAuthorization {
            authorization_id: format!("authorization-{number}"),
            plan_digest: progress.plan.plan_digest.clone(),
            operation_id: format!("operation-{number}"),
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
            progress
                .approve(
                    number,
                    format!("approval-{number}"),
                    authorization(&progress, number),
                )
                .unwrap();
            progress.start(number).unwrap();
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
        assert_eq!(progress.start(1), Err(BatchError::ApprovalRequired(1)));
        assert_eq!(
            progress.select(None, Some("source-1")),
            Ok(1),
            "exact source name is selectable"
        );
        assert_eq!(
            progress.select(None, None),
            Err(BatchError::AmbiguousSelection)
        );
        progress
            .approve(1, "approval-1".into(), authorization(&progress, 1))
            .unwrap();
        progress.start(1).unwrap();
        assert_eq!(progress.start(2), Err(BatchError::ActiveTransfer(1)));
    }

    #[test]
    fn denial_failure_cancellation_and_restart_remain_visible() {
        let mut progress = TransferBatchProgress::new(plan(false)).unwrap();
        progress.deny(1, "denied-1".into()).unwrap();
        progress
            .approve(2, "approval-2".into(), authorization(&progress, 2))
            .unwrap();
        progress.start(2).unwrap();
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
        progress
            .approve(3, "approval-3".into(), authorization(&progress, 3))
            .unwrap();
        progress.start(3).unwrap();
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
        progress
            .approve(1, "approval-1".into(), authorization(&progress, 1))
            .unwrap();
        assert_eq!(progress.start(1), Err(BatchError::PreviewOnly));
        assert_eq!(progress.report().transfers[0].next_action, "preview-only");
    }
}
