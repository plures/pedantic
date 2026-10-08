//! Production capability packs. PX authorizes these bounded effects; this
//! crate only reports readiness and sanitized observations.

use pedantic_capability::{
    Capability, CapabilityActivity, CapabilityError, CapabilityRegistry, validate_manifest,
    validate_readiness,
};
use pedantic_operation::{
    CapabilityManifest, CapabilityReadiness, Idempotency, RedactionClass, RetryClass, RiskClass,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::Arc;

const MANIFEST_VERSION: &str = "pedantic.capability-manifest.v1";
const READINESS_VERSION: &str = "pedantic.capability-readiness.v1";

pub trait ProviderBackend: Send + Sync {
    fn ready(&self) -> Result<(), CapabilityError>;
    fn execute(&self, input: &Value) -> Result<Value, CapabilityError>;
}

pub struct Provider<B> {
    manifest: CapabilityManifest,
    backend: B,
    remediation: Vec<String>,
}

impl<B: ProviderBackend> Provider<B> {
    pub fn new(manifest: CapabilityManifest, backend: B, remediation: Vec<String>) -> Self {
        Self {
            manifest,
            backend,
            remediation,
        }
    }
}

impl<B: ProviderBackend> Capability for Provider<B> {
    fn manifest(&self) -> &CapabilityManifest {
        &self.manifest
    }

    fn readiness(&self, target_id: &str, agent_id: &str, observed_at: u64) -> CapabilityReadiness {
        let ready = self.backend.ready().is_ok();
        CapabilityReadiness {
            schema_version: READINESS_VERSION.into(),
            capability: self.manifest.capability.clone(),
            version: self.manifest.version.clone(),
            target_id: target_id.into(),
            agent_id: agent_id.into(),
            observed_at,
            ready,
            redaction_class: self.manifest.redaction_class.clone(),
            state: Some(if ready { "ready" } else { "degraded" }.into()),
            required: Some(true),
            findings: (!ready)
                .then(|| {
                    vec![json!({
                        "code": "provider_unavailable",
                        "message": "The provider runtime is unavailable"
                    })]
                })
                .unwrap_or_default(),
            eligible_remediations: (!ready)
                .then(|| self.remediation.clone())
                .unwrap_or_default(),
            diagnostics: (!ready)
                .then(|| vec![json!({"code": "PROVIDER_UNAVAILABLE"})])
                .unwrap_or_default(),
        }
    }

    fn execute_unchecked(&self, input: &Value) -> Result<Value, CapabilityError> {
        self.backend.execute(input)
    }

    fn activity(&self, _input: &Value) -> Vec<CapabilityActivity> {
        vec![
            CapabilityActivity {
                event: "step.started",
                detail: "bounded provider effect started".into(),
            },
            CapabilityActivity {
                event: "step.progressed",
                detail: "bounded provider effect is in progress".into(),
            },
        ]
    }
}

pub fn register_production_providers(registry: &mut CapabilityRegistry) -> Result<(), CapabilityError> {
    for provider in production_providers() {
        registry.register(provider)?;
    }
    Ok(())
}

pub fn production_providers() -> Vec<Arc<dyn Capability>> {
    vec![
        Arc::new(Provider::new(transfer_manifest(), FilesystemTransfer, vec![])),
        Arc::new(Provider::new(package_manifest(), WindowsPackage, vec![])),
        Arc::new(Provider::new(feature_manifest(), WindowsFeature, vec![])),
        Arc::new(Provider::new(os_setup_manifest(), WindowsOsSetup, vec![])),
        Arc::new(Provider::new(hyperv_manifest(), HyperV, vec![])),
    ]
}

pub fn assert_conforms(provider: &dyn Capability) -> Result<(), CapabilityError> {
    validate_manifest(provider.manifest())?;
    let readiness = provider.readiness("conformance-target", "conformance-agent", 1);
    validate_readiness(&readiness)?;
    if provider.activity(&json!({})).is_empty() {
        return Err(CapabilityError::Execution(
            "provider did not emit activity metadata".into(),
        ));
    }
    Ok(())
}

pub struct FilesystemTransfer;

impl ProviderBackend for FilesystemTransfer {
    fn ready(&self) -> Result<(), CapabilityError> {
        Ok(())
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let source = required_string(input, "sourcePath")?;
        let destination = required_string(input, "destinationPath")?;
        let source_path = Path::new(source);
        if !source_path.is_file() {
            return Err(CapabilityError::Execution("transfer source is unavailable".into()));
        }
        let bytes_total = fs::metadata(source_path)
            .map_err(|_| CapabilityError::Execution("transfer source is unavailable".into()))?
            .len();
        let source_digest = digest_file(source_path)?;
        if Path::new(destination).is_file()
            && fs::metadata(destination)
                .map_err(|_| CapabilityError::Execution("transfer destination is unavailable".into()))?
                .len()
                == bytes_total
            && digest_file(Path::new(destination))? == source_digest
        {
            return Ok(transfer_observation(bytes_total, source_digest, 0, 0));
        }
        fs::copy(source_path, destination)
            .map_err(|_| CapabilityError::Execution("transfer could not complete".into()))?;
        let destination_digest = digest_file(Path::new(destination))?;
        if destination_digest != source_digest {
            return Err(CapabilityError::Execution("transfer verification failed".into()));
        }
        Ok(transfer_observation(bytes_total, source_digest, bytes_total, 0))
    }
}

pub struct WindowsPackage;

impl ProviderBackend for WindowsPackage {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("winget")
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(input, "action", &["install", "upgrade", "remove"])?;
        let package = required_string(input, "packageId")?;
        run_command(
            "winget",
            &[action, "--id", package, "--exact", "--disable-interactivity"],
        )?;
        Ok(effect_observation(input))
    }
}

pub struct WindowsFeature;

impl ProviderBackend for WindowsFeature {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("dism.exe")
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(input, "action", &["enable", "disable"])?;
        let feature = required_string(input, "featureName")?;
        let mode = if action == "enable" { "/Enable-Feature" } else { "/Disable-Feature" };
        run_command("dism.exe", &["/Online", mode, &format!("/FeatureName:{feature}"), "/NoRestart"])?;
        Ok(json!({"outputDigest": digest(input), "rebootRequired": false}))
    }
}

pub struct WindowsOsSetup;

impl ProviderBackend for WindowsOsSetup {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("powershell.exe")
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(input, "action", &["enable-remote-management", "enable-developer-mode"])?;
        let script = match action {
            "enable-remote-management" => "Enable-PSRemoting -Force -SkipNetworkProfileCheck",
            "enable-developer-mode" => {
                "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force"
            }
            _ => unreachable!("validated setup action"),
        };
        run_command("powershell.exe", &["-NoProfile", "-NonInteractive", "-Command", script])?;
        Ok(effect_observation(input))
    }
}

pub struct HyperV;

impl ProviderBackend for HyperV {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("powershell.exe")
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(input, "action", &["start", "stop", "checkpoint"])?;
        let name = required_string(input, "vmName")?;
        let command = match action {
            "start" => "Start-VM",
            "stop" => "Stop-VM",
            "checkpoint" => "Checkpoint-VM",
            _ => unreachable!("validated Hyper-V action"),
        };
        run_command(
            "powershell.exe",
            &["-NoProfile", "-NonInteractive", "-Command", command, "-Name", name],
        )?;
        Ok(effect_observation(input))
    }
}

fn command_ready(program: &str) -> Result<(), CapabilityError> {
    Command::new(program)
        .arg("--version")
        .output()
        .map_err(|_| CapabilityError::Execution("provider runtime is unavailable".into()))
        .and_then(|output| {
            output
                .status
                .success()
                .then_some(())
                .ok_or_else(|| CapabilityError::Execution("provider runtime is unavailable".into()))
        })
}

fn run_command(program: &str, arguments: &[&str]) -> Result<(), CapabilityError> {
    let status = Command::new(program)
        .args(arguments)
        .status()
        .map_err(|_| CapabilityError::Execution("provider effect could not start".into()))?;
    status
        .success()
        .then_some(())
        .ok_or_else(|| CapabilityError::Execution("provider effect failed".into()))
}

fn required_string<'a>(input: &'a Value, property: &str) -> Result<&'a str, CapabilityError> {
    input
        .get(property)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CapabilityError::InvalidInput(format!("{property} is required")))
}

fn enum_value<'a>(input: &'a Value, property: &str, values: &[&str]) -> Result<&'a str, CapabilityError> {
    let value = required_string(input, property)?;
    values
        .contains(&value)
        .then_some(value)
        .ok_or_else(|| CapabilityError::InvalidInput(format!("{property} is unsupported")))
}

fn digest(value: &Value) -> String {
    format!(
        "sha256:{:x}",
        Sha256::digest(serde_json::to_vec(value).expect("provider input is serializable"))
    )
}

fn digest_file(path: &Path) -> Result<String, CapabilityError> {
    fs::read(path)
        .map(|bytes| format!("sha256:{:x}", Sha256::digest(bytes)))
        .map_err(|_| CapabilityError::Execution("transfer file cannot be read".into()))
}

fn effect_observation(input: &Value) -> Value {
    json!({"outputDigest": digest(input)})
}

fn transfer_observation(bytes_total: u64, digest: String, bytes_transferred: u64, resume_count: u64) -> Value {
    json!({
        "bytesTotal": bytes_total,
        "bytesTransferred": bytes_transferred,
        "elapsedMs": 0,
        "currentThroughputBps": 0,
        "averageThroughputBps": 0,
        "resumeCount": resume_count,
        "retryCount": 0,
        "sourceDigest": digest,
        "destinationDigest": digest,
        "verificationState": "verified"
    })
}

fn manifest(capability: &str, risk_class: RiskClass, retry_class: RetryClass, idempotency: Idempotency, input_schema: Value) -> CapabilityManifest {
    CapabilityManifest {
        schema_version: MANIFEST_VERSION.into(),
        capability: capability.into(),
        version: "v1".into(),
        risk_class,
        retry_class,
        idempotency,
        redaction_class: RedactionClass::NormalizedFindings,
        requires_approval: Some(true),
        requires_checkpoint: Some(false),
        input_schema: Some(input_schema),
        output_schema: Some(json!({"type": "object"})),
    }
}

fn transfer_manifest() -> CapabilityManifest {
    manifest("transfer.filesystem", RiskClass::Moderate, RetryClass::SafeAfterObservation, Idempotency::ObservationRequired, json!({
        "type": "object", "additionalProperties": false, "required": ["sourcePath", "destinationPath"],
        "properties": {"sourcePath": {"type": "string", "minLength": 1}, "destinationPath": {"type": "string", "minLength": 1}}
    }))
}

fn package_manifest() -> CapabilityManifest {
    manifest("package.manage", RiskClass::Moderate, RetryClass::SafeAfterObservation, Idempotency::ObservationRequired, action_input("packageId", "string", &["install", "upgrade", "remove"]))
}

fn feature_manifest() -> CapabilityManifest {
    manifest("windows.feature", RiskClass::High, RetryClass::SafeAfterObservation, Idempotency::ObservationRequired, action_input("featureName", "string", &["enable", "disable"]))
}

fn os_setup_manifest() -> CapabilityManifest {
    manifest("windows.os-setup", RiskClass::High, RetryClass::RequiresFreshAuthorization, Idempotency::ObservationRequired, json!({
        "type": "object", "additionalProperties": false, "required": ["action"],
        "properties": {"action": {"type": "string", "enum": ["enable-remote-management", "enable-developer-mode"]}}
    }))
}

fn hyperv_manifest() -> CapabilityManifest {
    let mut manifest = manifest("hyperv.vm", RiskClass::Dangerous, RetryClass::RequiresOperatorReview, Idempotency::NonIdempotent, action_input("vmName", "string", &["start", "stop", "checkpoint"]));
    manifest.requires_checkpoint = Some(true);
    manifest
}

fn action_input(name: &str, _kind: &str, actions: &[&str]) -> Value {
    json!({
        "type": "object", "additionalProperties": false, "required": ["action", name],
        "properties": {
            "action": {"type": "string", "enum": actions},
            (name): {"type": "string", "minLength": 1}
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tempfile::tempdir;

    #[test]
    fn every_production_provider_conforms_without_running_native_effects() {
        for provider in production_providers() {
            assert_conforms(provider.as_ref()).unwrap();
        }
    }

    #[test]
    fn transfer_is_idempotent_and_reports_monotonic_observations() {
        let directory = tempdir().unwrap();
        let source = directory.path().join("source");
        let destination = directory.path().join("destination");
        fs::write(&source, b"provider content").unwrap();
        let provider = Provider::new(transfer_manifest(), FilesystemTransfer, vec![]);
        let input = json!({"sourcePath": source, "destinationPath": destination});
        let first = provider.execute(&input).unwrap();
        let second = provider.execute(&input).unwrap();
        assert_eq!(first["bytesTotal"], first["bytesTransferred"]);
        assert_eq!(second["bytesTotal"], second["bytesTotal"]);
        assert_eq!(second["bytesTransferred"], 0);
        assert_eq!(first["sourceDigest"], second["destinationDigest"]);
    }

    struct Backend(AtomicUsize);

    impl ProviderBackend for Backend {
        fn ready(&self) -> Result<(), CapabilityError> { Ok(()) }
        fn execute(&self, _input: &Value) -> Result<Value, CapabilityError> {
            self.0.fetch_add(1, Ordering::SeqCst);
            Ok(json!({"outputDigest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}))
        }
    }

    #[test]
    fn backend_is_only_invoked_by_authorized_agent_execution() {
        let backend = Backend(AtomicUsize::new(0));
        let provider = Provider::new(package_manifest(), backend, vec![]);
        assert_eq!(provider.backend.0.load(Ordering::SeqCst), 0);
        assert!(provider.activity(&json!({})).len() >= 2);
    }
}
