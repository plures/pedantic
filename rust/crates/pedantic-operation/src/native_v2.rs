//! Opt-in contract verification only; no admission policy, storage or effects.

use crate::{OperationPlan, OperationStep, PlanError, RetryClass, RiskClass};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use jsonschema::{Draft, JSONSchema};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, sync::OnceLock};
use thiserror::Error;

pub const PLAN_VERSION: &str = "pedantic.resolved-plan.v2";
pub const AUTHORIZATION_VERSION: &str = "pedantic.effect-authorization.v2";
const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
const PLAN_SCHEMA: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../contracts/v2/resolved-plan.schema.json"
));
const AUTHORIZATION_SCHEMA: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../contracts/v2/effect-authorization.schema.json"
));

#[derive(Debug, Error)]
pub enum ContractError {
    #[error("unsupported native contract version; no automatic conversion is allowed")]
    UnsupportedVersion,
    #[error("native v2 value does not satisfy its closed contract")]
    InvalidContract,
    #[error("native v2 numbers must be finite and integer-valued numbers must be JavaScript-safe")]
    UnsupportedNumber,
    #[error("resolved plan dependency graph is invalid: {0}")]
    InvalidPlan(#[from] PlanError),
    #[error("authorization does not bind the accepted immutable resolved plan")]
    PlanBinding,
    #[error("authorization does not bind the current effect context")]
    EffectBinding,
    #[error("authorization is revoked, not yet valid or expired")]
    Inactive,
    #[error("authorization signature, signing key or payload digest is invalid")]
    InvalidSignature,
    #[error("canonical JSON encoding failed: {0}")]
    Canonicalization(#[source] serde_json::Error),
}

impl ContractError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::UnsupportedVersion => "unsupported_version",
            Self::InvalidContract => "invalid_contract",
            Self::UnsupportedNumber => "unsupported_number",
            Self::InvalidPlan(_) => "invalid_plan",
            Self::PlanBinding => "plan_binding",
            Self::EffectBinding => "effect_binding",
            Self::Inactive => "inactive",
            Self::InvalidSignature => "invalid_signature",
            Self::Canonicalization(_) => "canonicalization",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ExecutionMode {
    Agentless,
    EphemeralAgent,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "mode", rename_all = "kebab-case", deny_unknown_fields)]
pub enum ExecutionIdentity {
    Agentless {
        #[serde(rename = "executorId")]
        executor_id: String,
    },
    EphemeralAgent {
        #[serde(rename = "agentId")]
        agent_id: String,
        #[serde(rename = "agentInstanceId")]
        agent_instance_id: String,
        #[serde(rename = "leaseId")]
        lease_id: String,
    },
}

impl ExecutionIdentity {
    fn mode(&self) -> ExecutionMode {
        match self {
            Self::Agentless { .. } => ExecutionMode::Agentless,
            Self::EphemeralAgent { .. } => ExecutionMode::EphemeralAgent,
        }
    }
}

/// These facts and the accepted plan/key must come from trusted service/runtime
/// state, never by copying the untrusted grant being verified.
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EffectContext {
    pub authorization_id: String,
    pub issuer_id: String,
    pub actor_id: String,
    pub operation_id: String,
    pub profile_id: String,
    pub target_id: String,
    pub step_id: String,
    pub attempt_id: String,
    pub input_digest: String,
    pub idempotency_key: String,
    pub execution: ExecutionIdentity,
    pub fencing_token: u64,
    pub risk_class: RiskClass,
    pub requires_reboot: bool,
    pub now: u64,
    pub revoked: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResolvedPlan {
    plan_id: String,
    plan_revision: u64,
    operation_id: String,
    profile_id: String,
    target_id: String,
    execution_mode: ExecutionMode,
    steps: Vec<OperationStep>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Grant {
    authorization_id: String,
    issuer_id: String,
    actor_id: String,
    plan_id: String,
    plan_revision: u64,
    plan_digest: String,
    operation_id: String,
    profile_id: String,
    target_id: String,
    step_id: String,
    attempt_id: String,
    capability: String,
    input_digest: String,
    execution: ExecutionIdentity,
    idempotency_key: String,
    fencing_token: u64,
    issued_at: u64,
    expires_at: u64,
    retry_class: RetryClass,
    risk_class: RiskClass,
    reboot_permitted: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GrantSignature {
    key_id: String,
    payload_digest: String,
    value: String,
}

#[derive(Deserialize)]
struct SignedGrant {
    grant: Grant,
    signature: GrantSignature,
}

fn validator(source: &'static str, slot: &'static OnceLock<JSONSchema>) -> &'static JSONSchema {
    slot.get_or_init(|| {
        let schema = serde_json::from_str(source).expect("embedded v2 schema must parse");
        JSONSchema::options()
            .with_draft(Draft::Draft7)
            .compile(&schema)
            .expect("embedded v2 schema must compile")
    })
}

fn validate_contract(value: &Value, version: &str) -> Result<(), ContractError> {
    static PLAN: OnceLock<JSONSchema> = OnceLock::new();
    static AUTHORIZATION: OnceLock<JSONSchema> = OnceLock::new();
    if value.get("schemaVersion").and_then(Value::as_str) != Some(version) {
        return Err(ContractError::UnsupportedVersion);
    }
    validate_numbers(value)?;
    let schema = if version == PLAN_VERSION {
        validator(PLAN_SCHEMA, &PLAN)
    } else {
        validator(AUTHORIZATION_SCHEMA, &AUTHORIZATION)
    };
    if !schema.is_valid(value) {
        return Err(ContractError::InvalidContract);
    }
    Ok(())
}

fn validate_numbers(value: &Value) -> Result<(), ContractError> {
    match value {
        Value::Number(number) => {
            let number = number.as_f64().ok_or(ContractError::UnsupportedNumber)?;
            if !number.is_finite() || (number.fract() == 0.0 && number.abs() > MAX_SAFE_INTEGER) {
                return Err(ContractError::UnsupportedNumber);
            }
        }
        Value::Array(values) => {
            for value in values {
                validate_numbers(value)?;
            }
        }
        Value::Object(values) => {
            for value in values.values() {
                validate_numbers(value)?;
            }
        }
        _ => {}
    }
    Ok(())
}

pub fn canonical_bytes(value: &Value) -> Result<Vec<u8>, ContractError> {
    validate_numbers(value)?;
    serde_jcs::to_vec(value).map_err(ContractError::Canonicalization)
}

fn digest(bytes: &[u8]) -> String {
    format!("sha256:{:x}", Sha256::digest(bytes))
}

fn parse_plan(value: &Value) -> Result<ResolvedPlan, ContractError> {
    validate_contract(value, PLAN_VERSION)?;
    let plan: ResolvedPlan = serde_json::from_slice(&canonical_bytes(value)?)
        .map_err(|_| ContractError::InvalidContract)?;
    let existing_plan = OperationPlan {
        schema_version: crate::OPERATION_PLAN_SCHEMA_VERSION.into(),
        plan_id: plan.plan_id.clone(),
        operation_id: plan.operation_id.clone(),
        profile_id: plan.profile_id.clone(),
        target_id: plan.target_id.clone(),
        resolved_settings: BTreeMap::new(),
        steps: plan.steps.clone(),
    };
    existing_plan.stable_topological_order()?;
    Ok(plan)
}

pub fn resolved_plan_digest(plan: &Value) -> Result<String, ContractError> {
    parse_plan(plan)?;
    Ok(digest(&canonical_bytes(plan)?))
}

fn signing_payload(authorization: &Value) -> Result<Vec<u8>, ContractError> {
    canonical_bytes(&json!({
        "schemaVersion": authorization["schemaVersion"],
        "grant": authorization["grant"],
    }))
}

pub fn sign_authorization(
    grant: Value,
    key_id: &str,
    key: &SigningKey,
) -> Result<Value, ContractError> {
    let mut authorization = json!({
        "schemaVersion": AUTHORIZATION_VERSION,
        "grant": grant,
        "signature": {
            "algorithm": "Ed25519",
            "keyId": key_id,
            "payloadDigest": format!("sha256:{}", "0".repeat(64)),
            "value": URL_SAFE_NO_PAD.encode([0u8; 64]),
        },
    });
    validate_contract(&authorization, AUTHORIZATION_VERSION)?;
    let payload = signing_payload(&authorization)?;
    authorization["signature"]["payloadDigest"] = digest(&payload).into();
    authorization["signature"]["value"] =
        URL_SAFE_NO_PAD.encode(key.sign(&payload).to_bytes()).into();
    Ok(authorization)
}

/// Verify a v2 binding without executing effects or deciding PX admission.
pub fn verify_effect_authorization(
    accepted_plan: &Value,
    authorization: &Value,
    context: &EffectContext,
    trusted_key_id: &str,
    trusted_key: &VerifyingKey,
) -> Result<(), ContractError> {
    let plan = parse_plan(accepted_plan)?;
    validate_contract(authorization, AUTHORIZATION_VERSION)?;
    let signed: SignedGrant = serde_json::from_slice(&canonical_bytes(authorization)?)
        .map_err(|_| ContractError::InvalidContract)?;
    let grant = &signed.grant;
    if grant.plan_id != plan.plan_id
        || grant.plan_revision != plan.plan_revision
        || grant.plan_digest != digest(&canonical_bytes(accepted_plan)?)
        || grant.operation_id != plan.operation_id
        || grant.profile_id != plan.profile_id
        || grant.target_id != plan.target_id
        || grant.execution.mode() != plan.execution_mode
    {
        return Err(ContractError::PlanBinding);
    }
    let step = plan
        .steps
        .iter()
        .find(|step| step.step_id == grant.step_id)
        .ok_or(ContractError::PlanBinding)?;
    if grant.capability != step.capability
        || grant.input_digest != step.input_digest
        || grant.retry_class != step.retry_class
    {
        return Err(ContractError::PlanBinding);
    }
    if grant.authorization_id != context.authorization_id
        || grant.issuer_id != context.issuer_id
        || grant.actor_id != context.actor_id
        || grant.operation_id != context.operation_id
        || grant.profile_id != context.profile_id
        || grant.target_id != context.target_id
        || grant.step_id != context.step_id
        || grant.attempt_id != context.attempt_id
        || grant.input_digest != context.input_digest
        || grant.idempotency_key != context.idempotency_key
        || grant.execution != context.execution
        || grant.fencing_token != context.fencing_token
        || grant.risk_class != context.risk_class
        || (context.requires_reboot && !grant.reboot_permitted)
    {
        return Err(ContractError::EffectBinding);
    }
    if context.revoked
        || grant.issued_at > context.now
        || grant.expires_at <= context.now
        || grant.expires_at <= grant.issued_at
    {
        return Err(ContractError::Inactive);
    }
    let payload = signing_payload(authorization)?;
    if signed.signature.key_id != trusted_key_id
        || signed.signature.payload_digest != digest(&payload)
    {
        return Err(ContractError::InvalidSignature);
    }
    let signature = URL_SAFE_NO_PAD
        .decode(&signed.signature.value)
        .map_err(|_| ContractError::InvalidSignature)?;
    let signature =
        Signature::from_slice(&signature).map_err(|_| ContractError::InvalidSignature)?;
    trusted_key
        .verify_strict(&payload, &signature)
        .map_err(|_| ContractError::InvalidSignature)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Value {
        serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v2/fixtures/conformance.json"
        )))
        .unwrap()
    }

    fn fixture_key(fixture: &Value) -> VerifyingKey {
        let bytes: [u8; 32] = URL_SAFE_NO_PAD
            .decode(fixture["publicKey"].as_str().unwrap())
            .unwrap()
            .try_into()
            .unwrap();
        VerifyingKey::from_bytes(&bytes).unwrap()
    }

    fn patch(value: &mut Value, path: &str, replacement: Value) {
        let (parent, key) = path.rsplit_once('/').unwrap();
        let parent = value.pointer_mut(parent).unwrap();
        match parent {
            Value::Object(object) => {
                object.insert(key.into(), replacement);
            }
            Value::Array(array) => array[key.parse::<usize>().unwrap()] = replacement,
            _ => panic!("fixture patch parent must be a container"),
        }
    }

    #[test]
    fn verifies_the_independent_node_signature_and_canonical_digest() {
        let f = fixture();
        let context: EffectContext = serde_json::from_value(f["context"].clone()).unwrap();
        let key_id = f["keyId"].as_str().unwrap();
        assert_eq!(
            resolved_plan_digest(&f["plan"]).unwrap(),
            f["authorization"]["grant"]["planDigest"]
        );
        verify_effect_authorization(
            &f["plan"],
            &f["authorization"],
            &context,
            key_id,
            &fixture_key(&f),
        )
        .unwrap();
        let synthetic_key = SigningKey::from_bytes(&[42; 32]);
        assert_eq!(
            sign_authorization(f["authorization"]["grant"].clone(), key_id, &synthetic_key)
                .unwrap(),
            f["authorization"]
        );
    }

    #[test]
    fn shared_negative_cases_fail_with_the_expected_code() {
        let fixture = fixture();
        let key = fixture_key(&fixture);
        let key_id = fixture["keyId"].as_str().unwrap();
        for case in fixture["negativeCases"].as_array().unwrap() {
            let mut f = fixture.clone();
            patch(
                &mut f[case["input"].as_str().unwrap()],
                case["path"].as_str().unwrap(),
                case["value"].clone(),
            );
            if case["resign"] == true {
                f["authorization"] = sign_authorization(
                    f["authorization"]["grant"].clone(),
                    key_id,
                    &SigningKey::from_bytes(&[42; 32]),
                )
                .unwrap();
            }
            let context: EffectContext = serde_json::from_value(f["context"].clone()).unwrap();
            let error = verify_effect_authorization(
                &f["plan"],
                &f["authorization"],
                &context,
                key_id,
                &key,
            )
            .unwrap_err();
            assert_eq!(error.code(), case["expectedCode"], "{}", case["name"]);
        }
    }

    #[test]
    fn canonical_vectors_match_utf16_order_and_ecmascript_numbers() {
        let f = fixture();
        for vector in f["canonicalVectors"].as_array().unwrap() {
            assert_eq!(
                String::from_utf8(canonical_bytes(&vector["value"]).unwrap()).unwrap(),
                vector["canonical"],
                "{}",
                vector["name"]
            );
        }
        for value in [
            json!(9007199254740992u64),
            json!(-9007199254740992i64),
            json!(1e20),
        ] {
            assert!(matches!(
                canonical_bytes(&value),
                Err(ContractError::UnsupportedNumber)
            ));
        }
        let mut normalized = f.clone();
        normalized["plan"]["planRevision"] = json!(1.0);
        normalized["authorization"]["grant"]["issuedAt"] = json!(10.0);
        let context: EffectContext = serde_json::from_value(f["context"].clone()).unwrap();
        verify_effect_authorization(
            &normalized["plan"],
            &normalized["authorization"],
            &context,
            f["keyId"].as_str().unwrap(),
            &fixture_key(&f),
        )
        .unwrap();
    }

    #[test]
    fn agentless_and_ephemeral_grants_share_the_same_verifier_without_mode_confusion() {
        let mut f = fixture();
        let key = fixture_key(&f);
        let key_id = f["keyId"].as_str().unwrap().to_owned();
        let synthetic_key = SigningKey::from_bytes(&[42; 32]);
        let execution = json!({"mode": "agentless", "executorId": "executor-1"});
        f["context"]["execution"] = execution.clone();
        f["authorization"]["grant"]["execution"] = execution;
        f["authorization"] =
            sign_authorization(f["authorization"]["grant"].clone(), &key_id, &synthetic_key)
                .unwrap();
        let context: EffectContext = serde_json::from_value(f["context"].clone()).unwrap();
        assert!(matches!(
            verify_effect_authorization(&f["plan"], &f["authorization"], &context, &key_id, &key),
            Err(ContractError::PlanBinding)
        ));
        f["plan"]["executionMode"] = "agentless".into();
        f["authorization"]["grant"]["planDigest"] =
            resolved_plan_digest(&f["plan"]).unwrap().into();
        f["authorization"] =
            sign_authorization(f["authorization"]["grant"].clone(), &key_id, &synthetic_key)
                .unwrap();
        verify_effect_authorization(&f["plan"], &f["authorization"], &context, &key_id, &key)
            .unwrap();
    }

    #[test]
    fn rejects_missing_contract_fields_and_malformed_identity_graphs() {
        let f = fixture();
        for (document, schema, version) in [
            (&f["plan"], PLAN_SCHEMA, PLAN_VERSION),
            (
                &f["authorization"],
                AUTHORIZATION_SCHEMA,
                AUTHORIZATION_VERSION,
            ),
        ] {
            let schema: Value = serde_json::from_str(schema).unwrap();
            for required in schema["required"].as_array().unwrap() {
                let mut missing = document.clone();
                missing
                    .as_object_mut()
                    .unwrap()
                    .remove(required.as_str().unwrap());
                assert!(validate_contract(&missing, version).is_err());
            }
        }
        for dependencies in [json!(["apply"]), json!(["missing"])] {
            let mut plan = f["plan"].clone();
            plan["steps"][1]["dependsOn"] = dependencies;
            assert!(matches!(
                resolved_plan_digest(&plan),
                Err(ContractError::InvalidPlan(_))
            ));
        }
        let mut plan = f["plan"].clone();
        plan["steps"][1]["stepId"] = "prepare".into();
        assert!(matches!(
            resolved_plan_digest(&plan),
            Err(ContractError::InvalidPlan(_))
        ));
    }

    #[test]
    fn never_uses_an_untrusted_signature_key() {
        let f = fixture();
        let context: EffectContext = serde_json::from_value(f["context"].clone()).unwrap();
        let wrong_key = SigningKey::from_bytes(&[43; 32]).verifying_key();
        assert!(matches!(
            verify_effect_authorization(
                &f["plan"],
                &f["authorization"],
                &context,
                f["keyId"].as_str().unwrap(),
                &wrong_key,
            ),
            Err(ContractError::InvalidSignature)
        ));
        let mut unsigned = f["authorization"]["grant"].clone();
        unsigned["issuerId"] = "".into();
        assert!(matches!(
            sign_authorization(
                unsigned,
                f["keyId"].as_str().unwrap(),
                &SigningKey::from_bytes(&[42; 32])
            ),
            Err(ContractError::InvalidContract)
        ));
    }
}
