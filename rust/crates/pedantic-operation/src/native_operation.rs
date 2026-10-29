use jsonschema::{Draft, JSONSchema};
use serde_json::Value;
use std::sync::OnceLock;
use thiserror::Error;

const SCHEMA_VERSION: &str = "pedantic.native-operation.v1";
const SCHEMA_SOURCE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../contracts/v1/native-operation.schema.json"
));

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum NativeOperationValidationError {
    #[error("unsupported native-operation schema version")]
    UnsupportedVersion,
    #[error("invalid native-operation contract")]
    InvalidContract,
    #[error("invalid native-operation identity binding")]
    InvalidIdentity,
}

fn validator() -> &'static JSONSchema {
    static SCHEMA: OnceLock<JSONSchema> = OnceLock::new();
    SCHEMA.get_or_init(|| {
        let schema = serde_json::from_str(SCHEMA_SOURCE).expect("native-operation schema parses");
        JSONSchema::options()
            .with_draft(Draft::Draft7)
            .compile(&schema)
            .expect("native-operation schema compiles")
    })
}

fn fields_match(left: &Value, right: &Value, fields: &[&str]) -> bool {
    fields
        .iter()
        .all(|field| left.get(field).is_some() && left.get(field) == right.get(field))
}

fn operation_identity_matches(operation: &Value, value: &Value) -> bool {
    fields_match(
        operation,
        value,
        &["operationId", "targetId", "correlationId"],
    )
}

fn plan_identity_matches(plan: &Value, value: &Value) -> bool {
    fields_match(
        plan,
        value,
        &[
            "operationId",
            "planId",
            "planRevision",
            "targetId",
            "correlationId",
        ],
    )
}

fn exactly_one_matching<'a>(
    values: &'a [Value],
    mut matches: impl FnMut(&'a Value) -> bool,
) -> Option<&'a Value> {
    let mut matching = values.iter().filter(|value| matches(value));
    let first = matching.next()?;
    matching.next().is_none().then_some(first)
}

fn identities_are_valid(document: &Value) -> bool {
    let operation = &document["operation"];
    let target = &document["target"];
    let sparse_plan = &document["sparsePlan"];
    let resolved_plan = &document["resolvedPlan"];

    if target["targetId"] != operation["targetId"]
        || !operation_identity_matches(operation, sparse_plan)
        || !operation_identity_matches(operation, resolved_plan)
        || sparse_plan["planRevision"] != resolved_plan["planRevision"]
        || sparse_plan["intentDigest"] != operation["intentDigest"]
        || resolved_plan["sparsePlanId"] != sparse_plan["planId"]
    {
        return false;
    }

    let steps = document["steps"]
        .as_array()
        .expect("schema validates steps");
    let attempts = document["attempts"]
        .as_array()
        .expect("schema validates attempts");
    let effects = document["effectRequests"]
        .as_array()
        .expect("schema validates effect requests");
    let approvals = document["approvals"]
        .as_array()
        .expect("schema validates approvals");
    let deployments = document["agentDeployments"]
        .as_array()
        .expect("schema validates deployments");
    let leases = document["agentLeases"]
        .as_array()
        .expect("schema validates leases");

    effects.iter().all(|effect| {
        if !plan_identity_matches(resolved_plan, effect)
            || effect["planDigest"] != resolved_plan["planDigest"]
        {
            return false;
        }

        let Some(approval) = exactly_one_matching(approvals, |approval| {
            approval["authorizationId"] == effect["authorizationId"]
        }) else {
            return false;
        };
        if approval["accepted"] != true
            || !plan_identity_matches(effect, approval)
            || approval["planDigest"] != effect["planDigest"]
        {
            return false;
        }

        let Some(step) = exactly_one_matching(steps, |step| step["stepId"] == effect["stepId"])
        else {
            return false;
        };
        if !plan_identity_matches(effect, step) {
            return false;
        }

        let Some(attempt) = exactly_one_matching(attempts, |attempt| {
            attempt["attemptId"] == effect["attemptId"]
        }) else {
            return false;
        };
        if !plan_identity_matches(effect, attempt) || attempt["stepId"] != step["stepId"] {
            return false;
        }

        let execution = &effect["execution"];
        if execution["mode"] == "ephemeral-agent" {
            let agent_instance_id = &execution["agentInstanceId"];
            let lease_id = &execution["leaseId"];
            deployments.iter().any(|deployment| {
                deployment["agentInstanceId"] == *agent_instance_id
                    && deployment["targetId"] == effect["targetId"]
            }) && exactly_one_matching(leases, |lease| lease["leaseId"] == *lease_id).is_some_and(
                |lease| {
                    lease["agentInstanceId"] == *agent_instance_id
                        && lease["operationId"] == effect["operationId"]
                },
            )
        } else {
            true
        }
    })
}

/// Validate a native-operation v1 document structurally and verify its
/// operation, plan, approval, step, attempt, and execution identity bindings.
pub fn validate_native_operation(document: &Value) -> Result<(), NativeOperationValidationError> {
    if document.get("schemaVersion").and_then(Value::as_str) != Some(SCHEMA_VERSION) {
        return Err(NativeOperationValidationError::UnsupportedVersion);
    }
    if !validator().is_valid(document) {
        return Err(NativeOperationValidationError::InvalidContract);
    }
    if !identities_are_valid(document) {
        return Err(NativeOperationValidationError::InvalidIdentity);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_invalid_fixtures_reject_identity_mismatches_for_every_effect() {
        let valid: Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/native-operation.valid.json"
        )))
        .expect("valid fixture parses");
        validate_native_operation(&valid).expect("valid fixture identities");

        for (field, mismatched_value) in [
            ("operationId", "op-other".into()),
            ("planId", "plan-other".into()),
            ("planRevision", 2.into()),
            ("targetId", "target-other".into()),
            ("correlationId", "corr-other".into()),
        ] {
            let mut invalid = valid.clone();
            invalid["effectRequests"][0][field] = mismatched_value;
            assert!(
                validator().is_valid(&invalid),
                "{field} mismatch must remain structurally valid"
            );
            assert_eq!(
                validate_native_operation(&invalid),
                Err(NativeOperationValidationError::InvalidIdentity),
                "{field} mismatch must be rejected"
            );
        }

        for (name, source) in [
            (
                "effect-plan-digest",
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/native-operation.invalid.effect-plan-digest.json"
                )),
            ),
            (
                "effect-identity",
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/native-operation.invalid.effect-identity.json"
                )),
            ),
            (
                "approval-identity",
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/native-operation.invalid.approval-identity.json"
                )),
            ),
            (
                "attempt-step",
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/native-operation.invalid.attempt-step.json"
                )),
            ),
            (
                "execution-reference",
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/native-operation.invalid.execution-reference.json"
                )),
            ),
            (
                "unauthorized-second-effect",
                include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../../contracts/v1/fixtures/native-operation.invalid.second-unauthorized-effect.json"
                )),
            ),
        ] {
            let invalid: Value =
                serde_json::from_str(source).unwrap_or_else(|_| panic!("{name} fixture parses"));
            assert!(
                validator().is_valid(&invalid),
                "{name} fixture must be structurally valid"
            );
            assert_eq!(
                validate_native_operation(&invalid),
                Err(NativeOperationValidationError::InvalidIdentity),
                "{name} fixture must be rejected"
            );
        }
    }
}
