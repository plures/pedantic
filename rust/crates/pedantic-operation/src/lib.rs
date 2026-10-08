//! Typed durable-operation contracts and deterministic, side-effect-free
//! projection primitives. Policy decisions are deliberately represented as
//! inputs from PX rather than reimplemented here.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use thiserror::Error;

pub const OPERATION_PLAN_SCHEMA_VERSION: &str = "pedantic.operation-plan.v1";
pub const OPERATION_EVENT_SCHEMA_VERSION: &str = "pedantic.operation-event.v1";

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
#[serde(rename_all = "camelCase")]
pub struct OperationStep {
    pub step_id: String,
    pub stage: StepStage,
    pub capability: String,
    pub depends_on: Vec<String>,
    pub retry_class: RetryClass,
    pub input_digest: String,
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
            .filter_map(|(id, dependencies)| dependencies.is_empty().then_some(*id))
            .collect::<BTreeSet<_>>();
        let mut ordered = Vec::with_capacity(self.steps.len());
        while let Some(step_id) = ready.pop_first() {
            ordered.push(steps[step_id]);
            if let Some(children) = dependents.get(step_id) {
                for child in children {
                    let dependencies = prerequisites
                        .get_mut(child)
                        .expect("dependent is always a declared step");
                    dependencies.remove(step_id);
                    if dependencies.is_empty() {
                        ready.insert(child);
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

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationEvent {
    pub schema_version: String,
    pub event_id: String,
    pub event_type: String,
    pub operation_id: String,
    pub profile_id: String,
    pub causation_id: String,
    pub correlation_id: String,
    pub sequence: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationProjection {
    pub operation_id: String,
    pub profile_id: String,
    pub state: String,
    pub last_sequence: u64,
    pub event_ids: BTreeSet<String>,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum ProjectionError {
    #[error("unsupported operation-event schema version: {0}")]
    UnsupportedSchemaVersion(String),
    #[error("event identifiers and causal identifiers must not be empty")]
    MissingIdentifier,
    #[error("event sequence gap: expected {expected}, got {actual}")]
    SequenceGap { expected: u64, actual: u64 },
    #[error("event does not belong to the projection")]
    WrongOperation,
    #[error("event transition {event_type} is invalid from {state}")]
    InvalidTransition { state: String, event_type: String },
}

impl OperationProjection {
    pub fn requested(operation_id: String, profile_id: String) -> Self {
        Self {
            operation_id,
            profile_id,
            state: "Requested".into(),
            last_sequence: 0,
            event_ids: BTreeSet::new(),
        }
    }

    /// Reduces immutable events in sequence order. An already-seen event ID is
    /// an idempotent delivery and therefore changes nothing.
    pub fn apply(&mut self, event: &OperationEvent) -> Result<(), ProjectionError> {
        if event.schema_version != OPERATION_EVENT_SCHEMA_VERSION {
            return Err(ProjectionError::UnsupportedSchemaVersion(
                event.schema_version.clone(),
            ));
        }
        if event.event_id.is_empty()
            || event.operation_id.is_empty()
            || event.profile_id.is_empty()
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
        let state = next_state(&self.state, &event.event_type).ok_or_else(|| {
            ProjectionError::InvalidTransition {
                state: self.state.clone(),
                event_type: event.event_type.clone(),
            }
        })?;
        self.state = state.into();
        self.last_sequence = event.sequence;
        self.event_ids.insert(event.event_id.clone());
        Ok(())
    }
}

fn next_state(state: &str, event: &str) -> Option<&'static str> {
    match (state, event) {
        ("Requested", "operation.requested") => Some("Requested"),
        ("Requested", "operation.admitted") => Some("Admitted"),
        ("Requested", "operation.rejected") => Some("Failed"),
        ("Admitted", "operation.authorized") => Some("Authorized"),
        ("Authorized", "preparation.started") => Some("Preparing"),
        ("Preparing", "preparation.completed") => Some("Prepared"),
        ("Prepared", "step.offered") => Some("Queued"),
        ("Queued", "step.leased" | "step.started") => Some("Running"),
        ("Running", "step.progressed" | "step.heartbeat") => Some("Running"),
        ("Running", "step.suspended") => Some("Waiting"),
        ("Waiting", "step.resumed") => Some("Running"),
        ("Running", "step.reboot_requested") => Some("AwaitingReboot"),
        ("AwaitingReboot", "step.reboot_observed") => Some("Running"),
        ("Running", "step.needs_review") => Some("NeedsReview"),
        ("Running", "step.completed" | "operation.succeeded") => Some("Succeeded"),
        ("Running", "step.failed" | "operation.failed") => Some("Failed"),
        (_, "operation.cancelled") => Some("Cancelled"),
        ("Succeeded", "evidence.finalized") => Some("Succeeded"),
        ("Failed", "evidence.finalized") => Some("Failed"),
        ("Cancelled", "evidence.finalized") => Some("Cancelled"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jsonschema::{Draft, JSONSchema};
    use serde_json::Value;

    fn schema_accepts(schema_source: &str, instance_source: &str) -> bool {
        let schema: Value = serde_json::from_str(schema_source).expect("schema parses");
        let instance: Value = serde_json::from_str(instance_source).expect("fixture parses");
        JSONSchema::options()
            .with_draft(Draft::Draft7)
            .compile(&schema)
            .expect("schema compiles")
            .is_valid(&instance)
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
        }
    }

    #[test]
    fn orders_independent_steps_stably() {
        let plan = plan(vec![
            step("z", StepStage::Execution, &["a"]),
            step("b", StepStage::Preparation, &[]),
            step("a", StepStage::Preparation, &[]),
        ]);
        assert_eq!(
            plan.stable_topological_order()
                .expect("valid plan")
                .into_iter()
                .map(|step| step.step_id.as_str())
                .collect::<Vec<_>>(),
            ["a", "b", "z"]
        );
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
            operation_id: "operation".into(),
            profile_id: "profile".into(),
            causation_id: "cause".into(),
            correlation_id: "correlation".into(),
            sequence: 1,
        };
        projection.apply(&admitted).expect("first delivery");
        projection.apply(&admitted).expect("duplicate delivery");
        assert_eq!(projection.last_sequence, 1);
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
    fn operation_plan_contract_accepts_golden_fixture_and_rejects_unknown_properties() {
        assert!(schema_accepts(
            include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../../contracts/v1/operation-plan.schema.json"
            )),
            include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../../contracts/v1/fixtures/operation-plan.valid.json"
            ))
        ));
        assert!(!schema_accepts(
            include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../../contracts/v1/operation-plan.schema.json"
            )),
            include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../../contracts/v1/fixtures/operation-plan.invalid-unknown-property.json"
            ))
        ));
    }
}
