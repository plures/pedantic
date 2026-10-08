//! Typed durable-operation contracts and deterministic, side-effect-free
//! projection primitives. Policy decisions are deliberately represented as
//! inputs from PX rather than reimplemented here.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use thiserror::Error;

pub const OPERATION_PLAN_SCHEMA_VERSION: &str = "pedantic.operation-plan.v1";
pub const OPERATION_EVENT_SCHEMA_VERSION: &str = "pedantic.operation-event.v1";
pub const OPERATION_PROJECTION_SCHEMA_VERSION: &str = "pedantic.operation-projection.v1";
pub const TRANSFER_REGISTRY_SCHEMA_VERSION: &str = "pedantic.transfer-registry.v1";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum StepStage {
    Preparation,
    Execution,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum RetryClass {
    Never,
    Safe,
    SafeAfterObservation,
    RequiresFreshAuthorization,
    RequiresOperatorReview,
    CompensateThenRetry,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RiskClass {
    Low,
    Moderate,
    High,
    Dangerous,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Idempotency {
    Idempotent,
    ObservationRequired,
    NonIdempotent,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum RedactionClass {
    MetadataOnly,
    NormalizedFindings,
    ProtectedArtifactReference,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityManifest {
    pub schema_version: String,
    pub capability: String,
    pub version: String,
    pub risk_class: RiskClass,
    pub retry_class: RetryClass,
    pub idempotency: Idempotency,
    pub redaction_class: RedactionClass,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requires_approval: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requires_checkpoint: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_schema: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_schema: Option<serde_json::Value>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityReadiness {
    pub schema_version: String,
    pub capability: String,
    pub version: String,
    pub target_id: String,
    pub agent_id: String,
    pub observed_at: u64,
    pub ready: bool,
    pub redaction_class: RedactionClass,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub required: Option<bool>,
    #[serde(default)]
    pub findings: Vec<serde_json::Value>,
    #[serde(default)]
    pub eligible_remediations: Vec<String>,
    #[serde(default)]
    pub diagnostics: Vec<serde_json::Value>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Signature {
    pub algorithm: String,
    pub key_id: String,
    pub payload_digest: String,
    pub value: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EffectAuthorization {
    pub schema_version: String,
    pub authorization_id: String,
    pub issuer_id: String,
    pub actor_id: String,
    pub profile_id: String,
    pub operation_id: String,
    pub step_id: String,
    pub attempt_id: String,
    pub target_id: String,
    pub agent_id: String,
    pub capability: String,
    pub input_digest: String,
    pub idempotency_key: String,
    pub fencing_token: u64,
    pub retry_class: RetryClass,
    pub risk_class: RiskClass,
    pub reboot_permitted: bool,
    pub issued_at: u64,
    pub expires_at: u64,
    pub revoked_at: u64,
    pub signature: Signature,
}

impl EffectAuthorization {
    pub fn signing_payload(&self) -> Vec<u8> {
        let mut authorization = self.clone();
        authorization.signature.value.clear();
        authorization.signature.payload_digest.clear();
        serde_json::to_vec(&authorization).expect("effect authorization is serializable")
    }

    pub fn digest(&self) -> String {
        format!("sha256:{:x}", Sha256::digest(self.signing_payload()))
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationStep {
    pub step_id: String,
    pub stage: StepStage,
    pub capability: String,
    pub depends_on: Vec<String>,
    pub retry_class: RetryClass,
    pub input_digest: String,
    #[serde(default)]
    pub secret_references: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationPlan {
    pub schema_version: String,
    pub plan_id: String,
    pub operation_id: String,
    pub profile_id: String,
    pub target_id: String,
    pub steps: Vec<OperationStep>,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum PlanError {
    #[error("unsupported operation-plan schema version: {0}")]
    UnsupportedSchemaVersion(String),
    #[error("plan identifiers must not be empty")]
    MissingIdentifier,
    #[error("operation plan must contain at least one step")]
    EmptyPlan,
    #[error("step identifiers must be unique: {0}")]
    DuplicateStepId(String),
    #[error("step {step_id} depends on an unknown step: {dependency}")]
    UnknownDependency { step_id: String, dependency: String },
    #[error("preparation step {step_id} cannot depend on execution step {dependency}")]
    PreparationDependsOnExecution { step_id: String, dependency: String },
    #[error("operation plan contains a dependency cycle")]
    Cycle,
}

impl OperationPlan {
    /// Validates structural invariants only. Capability admission, identity,
    /// authorization, and retry decisions remain PX responsibilities.
    pub fn stable_topological_order(&self) -> Result<Vec<&OperationStep>, PlanError> {
        if self.schema_version != OPERATION_PLAN_SCHEMA_VERSION {
            return Err(PlanError::UnsupportedSchemaVersion(
                self.schema_version.clone(),
            ));
        }
        if self.plan_id.is_empty()
            || self.operation_id.is_empty()
            || self.profile_id.is_empty()
            || self.target_id.is_empty()
        {
            return Err(PlanError::MissingIdentifier);
        }
        if self.steps.is_empty() {
            return Err(PlanError::EmptyPlan);
        }

        let steps = self
            .steps
            .iter()
            .map(|step| (step.step_id.as_str(), step))
            .collect::<BTreeMap<_, _>>();
        if steps.len() != self.steps.len() {
            let mut seen = BTreeSet::new();
            let duplicate = self
                .steps
                .iter()
                .find(|step| !seen.insert(step.step_id.as_str()))
                .expect("length mismatch guarantees a duplicate");
            return Err(PlanError::DuplicateStepId(duplicate.step_id.clone()));
        }

        let mut prerequisites = BTreeMap::new();
        let mut dependents: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
        for step in &self.steps {
            if step.step_id.is_empty() || step.capability.is_empty() || step.input_digest.is_empty()
            {
                return Err(PlanError::MissingIdentifier);
            }
            let mut dependencies = BTreeSet::new();
            for dependency in &step.depends_on {
                let Some(dependency_step) = steps.get(dependency.as_str()) else {
                    return Err(PlanError::UnknownDependency {
                        step_id: step.step_id.clone(),
                        dependency: dependency.clone(),
                    });
                };
                if step.stage == StepStage::Preparation
                    && dependency_step.stage == StepStage::Execution
                {
                    return Err(PlanError::PreparationDependsOnExecution {
                        step_id: step.step_id.clone(),
                        dependency: dependency.clone(),
                    });
                }
                dependencies.insert(dependency.as_str());
                dependents
                    .entry(dependency.as_str())
                    .or_default()
                    .insert(step.step_id.as_str());
            }
            prerequisites.insert(step.step_id.as_str(), dependencies);
        }

        let mut ready = prerequisites
            .iter()
            .filter_map(|(id, dependencies)| {
                dependencies
                    .is_empty()
                    .then_some((stage_order(&steps[id].stage), *id))
            })
            .collect::<BTreeSet<_>>();
        let mut ordered = Vec::with_capacity(self.steps.len());
        while let Some((_, step_id)) = ready.pop_first() {
            ordered.push(steps[step_id]);
            if let Some(children) = dependents.get(step_id) {
                for child in children {
                    let dependencies = prerequisites
                        .get_mut(child)
                        .expect("dependent is always a declared step");
                    dependencies.remove(step_id);
                    if dependencies.is_empty() {
                        ready.insert((stage_order(&steps[child].stage), child));
                    }
                }
            }
        }
        if ordered.len() != self.steps.len() {
            return Err(PlanError::Cycle);
        }
        Ok(ordered)
    }
}

fn stage_order(stage: &StepStage) -> u8 {
    match stage {
        StepStage::Preparation => 0,
        StepStage::Execution => 1,
    }
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "PascalCase")]
pub enum OperationState {
    Requested,
    Admitted,
    Authorized,
    Preparing,
    Prepared,
    Queued,
    Running,
    Waiting,
    AwaitingReboot,
    NeedsReview,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationEvent {
    pub schema_version: String,
    pub event_id: String,
    pub event_type: String,
    pub resulting_state: OperationState,
    pub operation_id: String,
    pub plan_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub step_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attempt_id: Option<String>,
    pub profile_id: String,
    pub actor_id: String,
    pub target_id: String,
    pub agent_id: String,
    pub causation_id: String,
    pub correlation_id: String,
    pub sequence: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub occurred_at: Option<u64>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationProjection {
    pub schema_version: String,
    pub operation_id: String,
    pub profile_id: String,
    pub state: OperationState,
    pub last_sequence: u64,
    pub event_ids: BTreeSet<String>,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum ProjectionError {
    #[error("unsupported operation-event schema version: {0}")]
    UnsupportedSchemaVersion(String),
    #[error("unsupported operation-projection schema version: {0}")]
    UnsupportedProjectionSchemaVersion(String),
    #[error("event identities and causal identifiers must not be empty")]
    MissingIdentifier,
    #[error("event sequence gap: expected {expected}, got {actual}")]
    SequenceGap { expected: u64, actual: u64 },
    #[error("event does not belong to the projection")]
    WrongOperation,
}

impl OperationProjection {
    pub fn requested(operation_id: String, profile_id: String) -> Self {
        Self {
            schema_version: OPERATION_PROJECTION_SCHEMA_VERSION.into(),
            operation_id,
            profile_id,
            state: OperationState::Requested,
            last_sequence: 0,
            event_ids: BTreeSet::new(),
        }
    }
}

/// Safe, provider-neutral measurements retained as durable transfer evidence.
/// Paths, credentials, tool output, and infrastructure addresses are excluded
/// deliberately; callers must not project them into this type.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferObservation {
    pub provider: String,
    pub bytes_transferred: u64,
    pub elapsed_millis: u64,
    pub throughput_bps: u64,
    pub retry_count: u64,
    pub resume_count: u64,
    pub verification_state: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure_category: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferEvent {
    pub schema_version: String,
    pub operation: OperationEvent,
    pub source_vm: String,
    pub target_vm: String,
    pub target_host: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub observation: Option<TransferObservation>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferQuery {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub operation_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_vm: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_vm: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_host: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReconciliationFinding {
    pub operation_id: String,
    pub code: String,
    pub detail: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferOperation {
    pub operation_id: String,
    pub source_vm: String,
    pub target_vm: String,
    pub target_host: String,
    pub state: OperationState,
    pub active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latest_result: Option<TransferObservation>,
    pub findings: Vec<ReconciliationFinding>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum TransferReportState {
    Incomplete,
    Succeeded,
    Failed,
    Cancelled,
    Conflicted,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferReport {
    pub operation_id: String,
    pub state: TransferReportState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bytes_transferred: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub elapsed_millis: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub throughput_bps: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_count: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resume_count: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verification_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure_category: Option<String>,
    pub findings: Vec<ReconciliationFinding>,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct FederatedTransferRegistry {
    events: BTreeMap<String, TransferEvent>,
}

impl FederatedTransferRegistry {
    /// Merges immutable events from a local or federated replica. Event IDs are
    /// idempotency keys, so a duplicate cannot overwrite prior evidence.
    pub fn ingest(&mut self, event: TransferEvent) -> bool {
        if event.schema_version != TRANSFER_REGISTRY_SCHEMA_VERSION
            || event.operation.event_id.is_empty()
            || event.operation.operation_id.is_empty()
            || event.source_vm.is_empty()
            || event.target_vm.is_empty()
            || event.target_host.is_empty()
        {
            return false;
        }
        self.events
            .entry(event.operation.event_id.clone())
            .or_insert(event);
        true
    }

    pub fn merge(&mut self, replica: &Self) {
        for event in replica.events.values().cloned() {
            self.ingest(event);
        }
    }

    pub fn event(&self, event_id: &str) -> Option<&TransferEvent> {
        self.events.get(event_id)
    }

    pub fn query(&self, query: &TransferQuery) -> Vec<TransferOperation> {
        let mut operations = self.operations();
        operations.retain(|operation| {
            query
                .operation_id
                .as_ref()
                .is_none_or(|value| value == &operation.operation_id)
                && query
                    .source_vm
                    .as_ref()
                    .is_none_or(|value| value == &operation.source_vm)
                && query
                    .target_vm
                    .as_ref()
                    .is_none_or(|value| value == &operation.target_vm)
                && query
                    .target_host
                    .as_ref()
                    .is_none_or(|value| value == &operation.target_host)
                && query.active.is_none_or(|value| value == operation.active)
        });
        operations
    }

    pub fn report(&self, operation_id: &str) -> Option<TransferReport> {
        let operation = self
            .operations()
            .into_iter()
            .find(|operation| operation.operation_id == operation_id)?;
        let observation = operation.latest_result;
        let state = if !operation.findings.is_empty() {
            TransferReportState::Conflicted
        } else {
            match operation.state {
                OperationState::Succeeded if observation.is_some() => {
                    TransferReportState::Succeeded
                }
                OperationState::Failed => TransferReportState::Failed,
                OperationState::Cancelled => TransferReportState::Cancelled,
                _ => TransferReportState::Incomplete,
            }
        };
        Some(TransferReport {
            operation_id: operation.operation_id,
            state,
            provider: observation.as_ref().map(|value| value.provider.clone()),
            bytes_transferred: observation.as_ref().map(|value| value.bytes_transferred),
            elapsed_millis: observation.as_ref().map(|value| value.elapsed_millis),
            throughput_bps: observation.as_ref().map(|value| value.throughput_bps),
            retry_count: observation.as_ref().map(|value| value.retry_count),
            resume_count: observation.as_ref().map(|value| value.resume_count),
            verification_state: observation
                .as_ref()
                .map(|value| value.verification_state.clone()),
            failure_category: observation.and_then(|value| value.failure_category),
            findings: operation.findings,
        })
    }

    /// Terminal history may be pruned after `retain_after`, while active event
    /// history remains immutable and discoverable.
    pub fn retain_terminal_after(&mut self, retain_after: u64) {
        let terminal_operations = self
            .operations()
            .into_iter()
            .filter(|operation| !operation.active)
            .map(|operation| operation.operation_id)
            .collect::<BTreeSet<_>>();
        self.events.retain(|_, event| {
            !terminal_operations.contains(&event.operation.operation_id)
                || event
                    .operation
                    .occurred_at
                    .is_none_or(|at| at >= retain_after)
        });
    }

    fn operations(&self) -> Vec<TransferOperation> {
        let mut grouped = BTreeMap::<String, Vec<&TransferEvent>>::new();
        for event in self.events.values() {
            grouped
                .entry(event.operation.operation_id.clone())
                .or_default()
                .push(event);
        }
        grouped
            .into_values()
            .filter_map(|events| operation_from_events(events))
            .collect()
    }
}

fn operation_from_events(mut events: Vec<&TransferEvent>) -> Option<TransferOperation> {
    events.sort_by_key(|event| (event.operation.sequence, event.operation.event_id.clone()));
    let first = events.first()?;
    let mut findings = Vec::new();
    if events.iter().any(|event| {
        event.source_vm != first.source_vm
            || event.target_vm != first.target_vm
            || event.target_host != first.target_host
    }) {
        findings.push(finding(
            first,
            "replica-identity-conflict",
            "replicas disagree on transfer identity",
        ));
    }
    let mut projection = OperationProjection::requested(
        first.operation.operation_id.clone(),
        first.operation.profile_id.clone(),
    );
    for event in &events {
        if let Err(error) = projection.apply(&event.operation) {
            findings.push(finding(
                first,
                "event-history-incomplete",
                &error.to_string(),
            ));
            break;
        }
    }
    let terminal_states = events
        .iter()
        .filter(|event| is_terminal(&event.operation.resulting_state))
        .map(|event| event.operation.resulting_state.clone())
        .collect::<BTreeSet<_>>();
    if terminal_states.len() > 1 {
        findings.push(finding(
            first,
            "terminal-state-conflict",
            "replicas contain conflicting terminal states",
        ));
    }
    let latest_result = events
        .iter()
        .rev()
        .find_map(|event| event.observation.clone());
    let state = if findings
        .iter()
        .any(|finding| finding.code == "event-history-incomplete")
    {
        events
            .iter()
            .find(|event| event.operation.sequence == 1)
            .map(|event| event.operation.resulting_state.clone())
            .unwrap_or(OperationState::Requested)
    } else {
        projection.state
    };
    Some(TransferOperation {
        operation_id: first.operation.operation_id.clone(),
        source_vm: first.source_vm.clone(),
        target_vm: first.target_vm.clone(),
        target_host: first.target_host.clone(),
        active: !is_terminal(&state),
        state,
        latest_result,
        findings,
    })
}

fn finding(event: &TransferEvent, code: &str, detail: &str) -> ReconciliationFinding {
    ReconciliationFinding {
        operation_id: event.operation.operation_id.clone(),
        code: code.into(),
        detail: detail.into(),
    }
}

fn is_terminal(state: &OperationState) -> bool {
    matches!(
        state,
        OperationState::Succeeded | OperationState::Failed | OperationState::Cancelled
    )
}
impl OperationProjection {
    /// Reduces immutable events in sequence order. An already-seen event ID is
    /// an idempotent delivery and therefore changes nothing.
    pub fn apply(&mut self, event: &OperationEvent) -> Result<(), ProjectionError> {
        if event.schema_version != OPERATION_EVENT_SCHEMA_VERSION {
            return Err(ProjectionError::UnsupportedSchemaVersion(
                event.schema_version.clone(),
            ));
        }
        if self.schema_version != OPERATION_PROJECTION_SCHEMA_VERSION {
            return Err(ProjectionError::UnsupportedProjectionSchemaVersion(
                self.schema_version.clone(),
            ));
        }
        if event.event_id.is_empty()
            || event.operation_id.is_empty()
            || event.plan_id.is_empty()
            || event.profile_id.is_empty()
            || event.actor_id.is_empty()
            || event.target_id.is_empty()
            || event.agent_id.is_empty()
            || event.causation_id.is_empty()
            || event.correlation_id.is_empty()
        {
            return Err(ProjectionError::MissingIdentifier);
        }
        if event.operation_id != self.operation_id || event.profile_id != self.profile_id {
            return Err(ProjectionError::WrongOperation);
        }
        if self.event_ids.contains(&event.event_id) {
            return Ok(());
        }
        let expected = self.last_sequence + 1;
        if event.sequence != expected {
            return Err(ProjectionError::SequenceGap {
                expected,
                actual: event.sequence,
            });
        }
        self.state = event.resulting_state.clone();
        self.last_sequence = event.sequence;
        self.event_ids.insert(event.event_id.clone());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jsonschema::{Draft, JSONSchema};
    use serde_json::Value;

    const CONTRACT_SCHEMA_SOURCES: [&str; 11] = [
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/operation-plan.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/operation-definition.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/operation-event.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/operation-projection.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/effect-authorization.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/effect-request.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/effect-observation.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/capability-manifest.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/capability-readiness.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/agent-enrollment.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/agent-observation-batch.schema.json"
        )),
    ];

    fn compiled_schema(schema_source: &str) -> JSONSchema {
        let schema: Value = serde_json::from_str(schema_source).expect("schema parses");
        let mut options = JSONSchema::options();
        options.with_draft(Draft::Draft7);
        for source in CONTRACT_SCHEMA_SOURCES {
            let document: Value = serde_json::from_str(source).expect("contract schema parses");
            options.with_document(
                document["$id"].as_str().expect("schema ID").to_owned(),
                document,
            );
        }
        options.compile(&schema).expect("schema compiles")
    }

    fn schema_accepts(schema_source: &str, instance_source: &str) -> bool {
        let instance: Value = serde_json::from_str(instance_source).expect("fixture parses");
        compiled_schema(schema_source).is_valid(&instance)
    }

    fn plan(steps: Vec<OperationStep>) -> OperationPlan {
        OperationPlan {
            schema_version: OPERATION_PLAN_SCHEMA_VERSION.into(),
            plan_id: "plan".into(),
            operation_id: "operation".into(),
            profile_id: "profile".into(),
            target_id: "target".into(),
            steps,
        }
    }

    fn step(id: &str, stage: StepStage, depends_on: &[&str]) -> OperationStep {
        OperationStep {
            step_id: id.into(),
            stage,
            capability: "dsc.config.test/v1".into(),
            depends_on: depends_on.iter().map(ToString::to_string).collect(),
            retry_class: RetryClass::Safe,
            input_digest: "sha256:input".into(),
            secret_references: Vec::new(),
        }
    }

    #[test]
    fn orders_independent_steps_stably() {
        let plan = plan(vec![
            step("a", StepStage::Execution, &[]),
            step("b", StepStage::Preparation, &[]),
            step("z", StepStage::Preparation, &[]),
        ]);
        assert_eq!(
            plan.stable_topological_order()
                .expect("valid plan")
                .into_iter()
                .map(|step| step.step_id.as_str())
                .collect::<Vec<_>>(),
            ["b", "z", "a"]
        );
    }

    #[test]
    fn rejects_empty_plans() {
        assert_eq!(
            plan(Vec::new())
                .stable_topological_order()
                .expect_err("empty plan"),
            PlanError::EmptyPlan
        );
    }

    #[test]
    fn secret_references_round_trip_from_the_plan_contract() {
        let source = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/operation-plan.valid.json"
        ));
        let plan: OperationPlan = serde_json::from_str(source).expect("valid plan fixture");
        assert_eq!(
            serde_json::from_str::<OperationPlan>(
                &serde_json::to_string(&plan).expect("serialize plan")
            )
            .expect("deserialize serialized plan"),
            plan
        );
        assert_eq!(plan.steps[0].secret_references, ["secret/db-password"]);
    }

    #[test]
    fn rejects_cycles_and_execution_dependencies_for_preparation() {
        assert_eq!(
            plan(vec![
                step("a", StepStage::Execution, &["b"]),
                step("b", StepStage::Execution, &["a"]),
            ])
            .stable_topological_order()
            .expect_err("cycle"),
            PlanError::Cycle
        );
        assert!(matches!(
            plan(vec![
                step("execute", StepStage::Execution, &[]),
                step("prepare", StepStage::Preparation, &["execute"]),
            ])
            .stable_topological_order(),
            Err(PlanError::PreparationDependsOnExecution { .. })
        ));
    }

    #[test]
    fn projection_rejects_gaps_and_deduplicates_events() {
        let mut projection = OperationProjection::requested("operation".into(), "profile".into());
        let admitted = OperationEvent {
            schema_version: OPERATION_EVENT_SCHEMA_VERSION.into(),
            event_id: "event-1".into(),
            event_type: "operation.admitted".into(),
            resulting_state: OperationState::Admitted,
            operation_id: "operation".into(),
            plan_id: "plan".into(),
            step_id: None,
            attempt_id: None,
            profile_id: "profile".into(),
            actor_id: "actor".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            causation_id: "cause".into(),
            correlation_id: "correlation".into(),
            sequence: 1,
            occurred_at: None,
        };
        projection.apply(&admitted).expect("first delivery");
        projection.apply(&admitted).expect("duplicate delivery");
        assert_eq!(projection.last_sequence, 1);
        assert_eq!(projection.state, OperationState::Admitted);
        let mut gap = admitted;
        gap.event_id = "event-3".into();
        gap.sequence = 3;
        assert_eq!(
            projection.apply(&gap).expect_err("gap"),
            ProjectionError::SequenceGap {
                expected: 2,
                actual: 3
            }
        );
    }

    #[test]
    fn step_completion_does_not_mark_the_operation_succeeded() {
        let mut projection = OperationProjection {
            schema_version: OPERATION_PROJECTION_SCHEMA_VERSION.into(),
            operation_id: "operation".into(),
            profile_id: "profile".into(),
            state: OperationState::Running,
            last_sequence: 0,
            event_ids: BTreeSet::new(),
        };
        let completed_step = OperationEvent {
            event_type: "step.completed".into(),
            resulting_state: OperationState::Running,
            ..event("event-1", 1)
        };
        projection.apply(&completed_step).expect("step completed");
        assert_eq!(projection.state, OperationState::Running);

        let succeeded = OperationEvent {
            event_type: "operation.succeeded".into(),
            resulting_state: OperationState::Succeeded,
            ..event("event-2", 2)
        };
        projection
            .apply(&succeeded)
            .expect("coordinator confirmed all steps");
        assert_eq!(projection.state, OperationState::Succeeded);
    }

    fn event(event_id: &str, sequence: u64) -> OperationEvent {
        OperationEvent {
            schema_version: OPERATION_EVENT_SCHEMA_VERSION.into(),
            event_id: event_id.into(),
            event_type: "operation.admitted".into(),
            resulting_state: OperationState::Admitted,
            operation_id: "operation".into(),
            plan_id: "plan".into(),
            step_id: None,
            attempt_id: None,
            profile_id: "profile".into(),
            actor_id: "actor".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            causation_id: "cause".into(),
            correlation_id: "correlation".into(),
            sequence,
            occurred_at: None,
        }
    }

    fn transfer_event(
        event_id: &str,
        sequence: u64,
        state: OperationState,
        occurred_at: u64,
        observation: Option<TransferObservation>,
    ) -> TransferEvent {
        TransferEvent {
            schema_version: TRANSFER_REGISTRY_SCHEMA_VERSION.into(),
            operation: OperationEvent {
                resulting_state: state,
                occurred_at: Some(occurred_at),
                ..event(event_id, sequence)
            },
            source_vm: "source-vm".into(),
            target_vm: "target-vm".into(),
            target_host: "target-host".into(),
            observation,
        }
    }

    fn observation() -> TransferObservation {
        TransferObservation {
            provider: "filesystem".into(),
            bytes_transferred: 1024,
            elapsed_millis: 50,
            throughput_bps: 20_480,
            retry_count: 1,
            resume_count: 1,
            verification_state: "verified".into(),
            failure_category: None,
        }
    }

    #[test]
    fn federated_registry_reconciles_delayed_replication_and_duplicate_events() {
        let mut source = FederatedTransferRegistry::default();
        let mut target = FederatedTransferRegistry::default();
        let started = transfer_event("started", 1, OperationState::Running, 10, None);
        let completed = transfer_event(
            "completed",
            2,
            OperationState::Succeeded,
            20,
            Some(observation()),
        );

        assert!(source.ingest(started.clone()));
        assert!(target.ingest(completed));
        assert!(source.ingest(started));
        source.merge(&target);
        target.merge(&source);

        let operations = target.query(&TransferQuery {
            operation_id: Some("operation".into()),
            source_vm: Some("source-vm".into()),
            target_vm: Some("target-vm".into()),
            target_host: Some("target-host".into()),
            active: Some(false),
        });
        assert_eq!(operations.len(), 1);
        assert_eq!(operations[0].state, OperationState::Succeeded);
        assert!(operations[0].findings.is_empty());
        assert_eq!(
            target.report("operation").expect("report").state,
            TransferReportState::Succeeded
        );
    }

    #[test]
    fn terminal_before_history_is_incomplete_not_a_success_report() {
        let mut registry = FederatedTransferRegistry::default();
        registry.ingest(transfer_event(
            "completed",
            2,
            OperationState::Succeeded,
            20,
            Some(observation()),
        ));

        let report = registry.report("operation").expect("report");
        assert_eq!(report.state, TransferReportState::Conflicted);
        assert!(
            report
                .findings
                .iter()
                .any(|finding| finding.code == "event-history-incomplete")
        );
    }

    #[test]
    fn stale_terminal_replicas_remain_visible_and_active_history_survives_retention() {
        let mut first = FederatedTransferRegistry::default();
        let mut stale = FederatedTransferRegistry::default();
        first.ingest(transfer_event(
            "started",
            1,
            OperationState::Running,
            100,
            None,
        ));
        first.ingest(transfer_event(
            "succeeded",
            2,
            OperationState::Succeeded,
            110,
            Some(observation()),
        ));
        stale.ingest(transfer_event(
            "started",
            1,
            OperationState::Running,
            100,
            None,
        ));
        stale.ingest(transfer_event(
            "failed",
            2,
            OperationState::Failed,
            111,
            Some(TransferObservation {
                failure_category: Some("provider-unavailable".into()),
                ..observation()
            }),
        ));

        first.merge(&stale);
        assert_eq!(
            first.report("operation").expect("report").state,
            TransferReportState::Conflicted
        );
        first.retain_terminal_after(105);
        assert_eq!(
            first
                .query(&TransferQuery {
                    operation_id: Some("operation".into()),
                    source_vm: None,
                    target_vm: None,
                    target_host: None,
                    active: None,
                })
                .len(),
            1
        );
    }

    #[test]
    fn every_public_contract_accepts_its_fixture_and_rejects_invalid_instances() {
        let contracts = [
            (
                "operation-plan",
                CONTRACT_SCHEMA_SOURCES[0],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/operation-plan.valid.json"
                )),
            ),
            (
                "operation-definition",
                CONTRACT_SCHEMA_SOURCES[1],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/operation-definition.valid.json"
                )),
            ),
            (
                "operation-event",
                CONTRACT_SCHEMA_SOURCES[2],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/operation-event.valid.json"
                )),
            ),
            (
                "operation-projection",
                CONTRACT_SCHEMA_SOURCES[3],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/operation-projection.valid.json"
                )),
            ),
            (
                "effect-authorization",
                CONTRACT_SCHEMA_SOURCES[4],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/effect-authorization.valid.json"
                )),
            ),
            (
                "effect-request",
                CONTRACT_SCHEMA_SOURCES[5],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/effect-request.valid.json"
                )),
            ),
            (
                "effect-observation",
                CONTRACT_SCHEMA_SOURCES[6],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/effect-observation.valid.json"
                )),
            ),
            (
                "capability-manifest",
                CONTRACT_SCHEMA_SOURCES[7],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/capability-manifest.valid.json"
                )),
            ),
            (
                "capability-readiness",
                CONTRACT_SCHEMA_SOURCES[8],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/capability-readiness.valid.json"
                )),
            ),
            (
                "agent-enrollment",
                CONTRACT_SCHEMA_SOURCES[9],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/agent-enrollment.valid.json"
                )),
            ),
            (
                "agent-observation-batch",
                CONTRACT_SCHEMA_SOURCES[10],
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/agent-observation-batch.valid.json"
                )),
            ),
        ];

        for (name, schema_source, fixture_source) in contracts {
            let schema: Value = serde_json::from_str(schema_source).expect("schema parses");
            let fixture: Value = serde_json::from_str(fixture_source).expect("fixture parses");
            let compiled = compiled_schema(schema_source);
            assert!(compiled.is_valid(&fixture), "{name} fixture must be valid");

            for required in schema["required"].as_array().expect("required fields") {
                let key = required.as_str().expect("required field name");
                let mut invalid = fixture.clone();
                invalid.as_object_mut().expect("object fixture").remove(key);
                assert!(
                    !compiled.is_valid(&invalid),
                    "{name} must reject missing required field {key}"
                );
            }

            let mut unknown = fixture;
            unknown
                .as_object_mut()
                .expect("object fixture")
                .insert("unexpected".into(), Value::Bool(true));
            assert!(
                !compiled.is_valid(&unknown),
                "{name} must reject unknown fields"
            );

            if name == "operation-plan" {
                let invalid_fixture = include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/operation-plan.invalid-unknown-property.json"
                ));
                let invalid: Value =
                    serde_json::from_str(invalid_fixture).expect("invalid fixture parses");
                assert!(
                    !compiled.is_valid(&invalid),
                    "unknown-property fixture must be rejected"
                );
            }
        }
    }

    #[test]
    fn security_contracts_reject_free_form_diagnostics_and_incomplete_signatures() {
        for (index, fixture_source) in [
            (
                4,
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/effect-authorization.valid.json"
                )),
            ),
            (
                6,
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/effect-observation.valid.json"
                )),
            ),
            (
                8,
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/capability-readiness.valid.json"
                )),
            ),
            (
                10,
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/agent-observation-batch.valid.json"
                )),
            ),
        ] {
            let compiled = compiled_schema(CONTRACT_SCHEMA_SOURCES[index]);
            let mut invalid: Value =
                serde_json::from_str(fixture_source).expect("security fixture parses");
            let diagnostics = if index == 4 {
                None
            } else if index == 10 {
                Some(&mut invalid["observations"][0]["diagnostics"])
            } else {
                Some(&mut invalid["diagnostics"])
            };
            if let Some(diagnostics) = diagnostics {
                *diagnostics = serde_json::json!(["plaintext credential"]);
                assert!(
                    !compiled.is_valid(&invalid),
                    "free-form diagnostics must be rejected"
                );
            } else {
                invalid["signature"]
                    .as_object_mut()
                    .expect("signature object")
                    .remove("payloadDigest");
                assert!(
                    !compiled.is_valid(&invalid),
                    "signature without a payload digest must be rejected"
                );
            }
        }

        let authorization = compiled_schema(CONTRACT_SCHEMA_SOURCES[4]);
        let mut missing_reboot_permission: Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/effect-authorization.valid.json"
        )))
        .expect("authorization fixture parses");
        missing_reboot_permission
            .as_object_mut()
            .expect("authorization object")
            .remove("rebootPermitted");
        assert!(!authorization.is_valid(&missing_reboot_permission));
    }

    #[test]
    fn rust_event_and_projection_serialize_to_their_contracts() {
        let event: OperationEvent = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/operation-event.valid.json"
        )))
        .expect("valid operation event fixture");
        assert!(schema_accepts(
            CONTRACT_SCHEMA_SOURCES[2],
            &serde_json::to_string(&event).expect("serialize operation event")
        ));

        let projection = OperationProjection::requested("operation-1".into(), "default".into());
        assert!(schema_accepts(
            CONTRACT_SCHEMA_SOURCES[3],
            &serde_json::to_string(&projection).expect("serialize operation projection")
        ));

        let mut missing_identity = event;
        missing_identity.actor_id.clear();
        let mut projection = OperationProjection::requested("operation-1".into(), "default".into());
        assert_eq!(
            projection
                .apply(&missing_identity)
                .expect_err("missing event identity"),
            ProjectionError::MissingIdentifier
        );
    }
}
