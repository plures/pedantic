//! Capability metadata and bounded local adapters. PX supplies authorization
//! and retry decisions; adapters only validate and execute their declared work.

use jsonschema::{Draft, JSONSchema};
use pedantic_operation::{CapabilityManifest, CapabilityReadiness};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::Arc;
use thiserror::Error;

pub const CAPABILITY_MANIFEST_SCHEMA_VERSION: &str = "pedantic.capability-manifest.v1";
pub const CAPABILITY_READINESS_SCHEMA_VERSION: &str = "pedantic.capability-readiness.v1";

#[derive(Debug, Error)]
pub enum CapabilityError {
    #[error("manifest does not conform to the capability contract: {0}")]
    InvalidManifest(String),
    #[error("capability is already registered: {0}")]
    Duplicate(String),
    #[error("capability is not registered: {0}")]
    Missing(String),
    #[error("capability input is invalid: {0}")]
    InvalidInput(String),
    #[error("capability output is invalid: {0}")]
    InvalidOutput(String),
    #[error("bounded adapter failed: {0}")]
    Execution(String),
}

pub trait Capability: Send + Sync {
    fn manifest(&self) -> &CapabilityManifest;
    fn readiness(&self, target_id: &str, agent_id: &str, observed_at: u64) -> CapabilityReadiness;

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        validate_capability_value(self.manifest().input_schema.as_ref(), input)
            .map_err(CapabilityError::InvalidInput)?;
        let output = self.execute_unchecked(input)?;
        validate_capability_value(self.manifest().output_schema.as_ref(), &output)
            .map_err(CapabilityError::InvalidOutput)?;
        Ok(output)
    }

    fn execute_unchecked(&self, input: &Value) -> Result<Value, CapabilityError>;

    fn activity(&self, _input: &Value) -> Vec<CapabilityActivity> {
        Vec::new()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CapabilityActivity {
    pub event: &'static str,
    pub detail: String,
}

#[derive(Default)]
pub struct CapabilityRegistry {
    capabilities: BTreeMap<String, Arc<dyn Capability>>,
}

impl CapabilityRegistry {
    pub fn register(&mut self, capability: Arc<dyn Capability>) -> Result<(), CapabilityError> {
        validate_manifest(capability.manifest())?;
        let name = format!(
            "{}/{}",
            capability.manifest().capability,
            capability.manifest().version
        );
        if self.capabilities.insert(name.clone(), capability).is_some() {
            return Err(CapabilityError::Duplicate(name));
        }
        Ok(())
    }

    pub fn resolve(&self, name: &str) -> Result<Arc<dyn Capability>, CapabilityError> {
        self.capabilities
            .get(name)
            .cloned()
            .ok_or_else(|| CapabilityError::Missing(name.into()))
    }

    pub fn readiness(
        &self,
        target_id: &str,
        agent_id: &str,
        observed_at: u64,
    ) -> Vec<CapabilityReadiness> {
        self.capabilities
            .values()
            .map(|capability| capability.readiness(target_id, agent_id, observed_at))
            .collect()
    }
}

pub fn validate_manifest(manifest: &CapabilityManifest) -> Result<(), CapabilityError> {
    validate_against_schema(
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/capability-manifest.schema.json"
        )),
        manifest,
        "manifest",
    )?;
    for (name, schema) in [
        ("inputSchema", &manifest.input_schema),
        ("outputSchema", &manifest.output_schema),
    ] {
        if let Some(schema) = schema {
            JSONSchema::options()
                .with_draft(Draft::Draft7)
                .compile(schema)
                .map_err(|error| CapabilityError::InvalidManifest(format!("{name}: {error}")))?;
        }
    }
    Ok(())
}

pub fn validate_readiness(readiness: &CapabilityReadiness) -> Result<(), CapabilityError> {
    validate_against_schema(
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/capability-readiness.schema.json"
        )),
        readiness,
        "readiness",
    )
}

fn validate_against_schema<T: serde::Serialize>(
    schema: &str,
    value: &T,
    name: &str,
) -> Result<(), CapabilityError> {
    let schema: Value = serde_json::from_str(schema)
    .expect("embedded capability manifest schema parses");
    let compiled = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(&schema)
        .expect("embedded capability manifest schema compiles");
    let value = serde_json::to_value(value).expect("contract value is serializable");
    if let Err(errors) = compiled.validate(&value) {
        return Err(CapabilityError::InvalidManifest(format!(
            "{name}: {}",
            errors
                .map(|error| error.to_string())
                .collect::<Vec<_>>()
                .join("; "),
        )));
    }
    Ok(())
}

fn validate_capability_value(schema: Option<&Value>, value: &Value) -> Result<(), String> {
    let Some(schema) = schema else {
        return Ok(());
    };
    let compiled = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(schema)
        .map_err(|error| error.to_string())?;
    compiled.validate(value).map_err(|errors| {
        errors
            .map(|error| error.to_string())
            .collect::<Vec<_>>()
            .join("; ")
    })
}

#[derive(Clone, Copy, Debug)]
pub enum DscAction {
    Validate,
    Test,
    Set,
}

pub trait DscProcess: Send + Sync {
    fn ready(&self) -> Result<(), CapabilityError>;
    fn run(&self, action: DscAction, document: &str) -> Result<Value, CapabilityError>;
}

pub struct DscCapability<P> {
    manifest: CapabilityManifest,
    process: P,
    action: DscAction,
}

impl<P: DscProcess> DscCapability<P> {
    pub fn new(manifest: CapabilityManifest, process: P, action: DscAction) -> Self {
        Self {
            manifest,
            process,
            action,
        }
    }
}

impl<P: DscProcess> Capability for DscCapability<P> {
    fn manifest(&self) -> &CapabilityManifest {
        &self.manifest
    }

    fn readiness(&self, target_id: &str, agent_id: &str, observed_at: u64) -> CapabilityReadiness {
        let ready = self.process.ready().is_ok();
        CapabilityReadiness {
            schema_version: CAPABILITY_READINESS_SCHEMA_VERSION.into(),
            capability: self.manifest.capability.clone(),
            version: self.manifest.version.clone(),
            target_id: target_id.into(),
            agent_id: agent_id.into(),
            observed_at,
            ready,
            redaction_class: self.manifest.redaction_class.clone(),
            state: Some(if ready { "ready" } else { "degraded" }.into()),
            required: Some(true),
            findings: if ready {
                Vec::new()
            } else {
                vec![json!({"code": "dsc_cli_missing", "message": "DSC runtime is unavailable"})]
            },
            eligible_remediations: if ready {
                Vec::new()
            } else {
                vec!["dsc.runtime.install/v1".into()]
            },
            diagnostics: if !ready {
                vec![json!({"code": "CAPABILITY_NOT_READY"})]
            } else {
                Vec::new()
            },
        }
    }

    fn execute_unchecked(&self, input: &Value) -> Result<Value, CapabilityError> {
        let document = input
            .get("document")
            .and_then(Value::as_str)
            .filter(|document| !document.is_empty())
            .ok_or_else(|| CapabilityError::InvalidInput("document is required".into()))?;
        let result = self.process.run(self.action, document)?;
        Ok(
            json!({"outputDigest": format!("sha256:{:x}", Sha256::digest(
                serde_json::to_vec(&result).expect("DSC output is serializable")
            ))}),
        )
    }
}

/// Thin local adapter around the DSC CLI. Its raw output is returned only to
/// the caller for immediate normalization and is never persisted by this crate.
pub struct LocalDscProcess;

impl DscProcess for LocalDscProcess {
    fn ready(&self) -> Result<(), CapabilityError> {
        Command::new("dsc")
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(|_| CapabilityError::Execution("DSC runtime is unavailable".into()))
            .and_then(|status| {
                status
                    .success()
                    .then_some(())
                    .ok_or_else(|| CapabilityError::Execution("DSC runtime is unavailable".into()))
            })
    }

    fn run(&self, action: DscAction, document: &str) -> Result<Value, CapabilityError> {
        let action = match action {
            DscAction::Validate => "validate",
            DscAction::Test => "test",
            DscAction::Set => "set",
        };
        let mut child = Command::new("dsc")
            .args(["config", action, "--file", "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| CapabilityError::Execution("DSC execution could not start".into()))?;
        child
            .stdin
            .take()
            .expect("DSC stdin was piped")
            .write_all(document.as_bytes())
            .map_err(|_| CapabilityError::Execution("DSC input could not be written".into()))?;
        let output = child
            .wait_with_output()
            .map_err(|_| CapabilityError::Execution("DSC execution could not complete".into()))?;
        if !output.status.success() {
            return Err(CapabilityError::Execution("DSC execution failed".into()));
        }
        if output.stdout.is_empty() {
            return Ok(json!({}));
        }
        serde_json::from_slice(&output.stdout)
            .map_err(|_| CapabilityError::Execution("DSC output was not valid JSON".into()))
    }
}

pub struct DscRuntimeReadinessCapability<P> {
    manifest: CapabilityManifest,
    process: P,
}

impl<P: DscProcess> DscRuntimeReadinessCapability<P> {
    pub fn new(manifest: CapabilityManifest, process: P) -> Self {
        Self { manifest, process }
    }
}

impl<P: DscProcess> Capability for DscRuntimeReadinessCapability<P> {
    fn manifest(&self) -> &CapabilityManifest {
        &self.manifest
    }

    fn readiness(&self, target_id: &str, agent_id: &str, observed_at: u64) -> CapabilityReadiness {
        let ready = self.process.ready().is_ok();
        CapabilityReadiness {
            schema_version: CAPABILITY_READINESS_SCHEMA_VERSION.into(),
            capability: self.manifest.capability.clone(),
            version: self.manifest.version.clone(),
            target_id: target_id.into(),
            agent_id: agent_id.into(),
            observed_at,
            ready,
            redaction_class: self.manifest.redaction_class.clone(),
            state: Some(if ready { "ready" } else { "degraded" }.into()),
            required: Some(true),
            findings: if ready {
                Vec::new()
            } else {
                vec![json!({"code": "dsc_cli_missing", "message": "DSC runtime is unavailable"})]
            },
            eligible_remediations: if ready {
                Vec::new()
            } else {
                vec!["dsc.runtime.install/v1".into()]
            },
            diagnostics: if ready {
                Vec::new()
            } else {
                vec![json!({"code": "CAPABILITY_NOT_READY"})]
            },
        }
    }

    fn execute_unchecked(&self, _input: &Value) -> Result<Value, CapabilityError> {
        self.process.ready()?;
        Ok(json!({}))
    }
}

pub trait RebootProcess: Send + Sync {
    fn request_reboot(&self) -> Result<(), CapabilityError>;
}

pub struct RebootCapability<P> {
    manifest: CapabilityManifest,
    process: P,
}

impl<P: RebootProcess> RebootCapability<P> {
    pub fn new(manifest: CapabilityManifest, process: P) -> Self {
        Self { manifest, process }
    }
}

impl<P: RebootProcess> Capability for RebootCapability<P> {
    fn manifest(&self) -> &CapabilityManifest {
        &self.manifest
    }

    fn readiness(&self, target_id: &str, agent_id: &str, observed_at: u64) -> CapabilityReadiness {
        CapabilityReadiness {
            schema_version: CAPABILITY_READINESS_SCHEMA_VERSION.into(),
            capability: self.manifest.capability.clone(),
            version: self.manifest.version.clone(),
            target_id: target_id.into(),
            agent_id: agent_id.into(),
            observed_at,
            ready: true,
            redaction_class: self.manifest.redaction_class.clone(),
            state: Some("ready".into()),
            required: Some(true),
            findings: Vec::new(),
            eligible_remediations: Vec::new(),
            diagnostics: Vec::new(),
        }
    }

    fn execute_unchecked(&self, _input: &Value) -> Result<Value, CapabilityError> {
        self.process.request_reboot()?;
        Ok(json!({}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest() -> CapabilityManifest {
        serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/capability-manifest.valid.json"
        )))
        .unwrap()
    }

    #[test]
    fn golden_manifest_validates_against_contract() {
        validate_manifest(&manifest()).unwrap();
    }

    #[test]
    fn malformed_manifest_is_rejected() {
        let mut manifest = manifest();
        manifest.version = "one".into();
        assert!(matches!(
            validate_manifest(&manifest),
            Err(CapabilityError::InvalidManifest(_))
        ));
    }

    struct Process;

    impl DscProcess for Process {
        fn ready(&self) -> Result<(), CapabilityError> {
            Ok(())
        }

        fn run(&self, action: DscAction, document: &str) -> Result<Value, CapabilityError> {
            assert!(matches!(action, DscAction::Test));
            assert_eq!(document, "configuration");
            Ok(json!({"raw": "output"}))
        }
    }

    #[test]
    fn dsc_adapter_returns_only_an_output_digest() {
        let capability = DscCapability::new(manifest(), Process, DscAction::Test);
        let output = capability
            .execute(&json!({"document": "configuration"}))
            .unwrap();
        assert!(
            output["outputDigest"]
                .as_str()
                .unwrap()
                .starts_with("sha256:")
        );
        assert!(output.get("raw").is_none());
    }

    #[test]
    fn capability_enforces_declared_input_and_output_schemas() {
        let mut input_manifest = manifest();
        input_manifest.input_schema = Some(json!({
            "type": "object",
            "required": ["document"],
            "properties": { "document": { "type": "string" } }
        }));
        let input_capability = DscCapability::new(input_manifest, Process, DscAction::Test);
        assert!(matches!(
            input_capability.execute(&json!({"document": 42})),
            Err(CapabilityError::InvalidInput(_))
        ));

        let mut output_manifest = manifest();
        output_manifest.output_schema = Some(json!({
            "type": "object",
            "required": ["raw"]
        }));
        let output_capability = DscCapability::new(output_manifest, Process, DscAction::Test);
        assert!(matches!(
            output_capability.execute(&json!({"document": "configuration"})),
            Err(CapabilityError::InvalidOutput(_))
        ));
    }

    #[test]
    fn malformed_declared_schema_is_rejected_at_registration() {
        let mut manifest = manifest();
        manifest.input_schema = Some(json!({"type": "not-a-json-schema-type"}));
        assert!(matches!(
            validate_manifest(&manifest),
            Err(CapabilityError::InvalidManifest(_))
        ));
    }
}
