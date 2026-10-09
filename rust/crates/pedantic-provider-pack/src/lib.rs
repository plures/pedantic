//! Production capability packs. PX authorizes these bounded effects; this
//! crate only reports readiness and sanitized observations.

#[cfg(windows)]
use base64::Engine as _;
#[cfg(windows)]
use std::collections::BTreeSet;
use pedantic_capability::{
    Capability, CapabilityActivity, CapabilityError, CapabilityRegistry, Reconciliation,
    validate_manifest, validate_readiness,
};
use pedantic_operation::hyperv_transfer_plan::{
    HostFailureCategory, HostQueryFailure, HyperVHardDrive, HyperVHostInventory,
    HyperVInventoryProvider, HyperVVmInventory,
};
use pedantic_operation::{
    CapabilityManifest, CapabilityReadiness, Idempotency, RedactionClass, RetryClass, RiskClass,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::Path;
#[cfg(windows)]
use std::path::PathBuf;
use std::process::Command;
#[cfg(windows)]
use std::process::Stdio;
use std::sync::Arc;
use std::time::Instant;
#[cfg(windows)]
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const MANIFEST_VERSION: &str = "pedantic.capability-manifest.v1";
const READINESS_VERSION: &str = "pedantic.capability-readiness.v1";
const WINGET_PROBE: &[&str] = &["--version"];
const DISM_PROBE: &[&str] = &["/English", "/?"];
const POWERSHELL_PROBE: &[&str] = &[
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    "$PSVersionTable.PSVersion.Major",
];
const HYPERV_PROBE: &[&str] = &[
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    "Get-Command Start-VM, Stop-VM, Checkpoint-VM -ErrorAction Stop | Out-Null",
];

pub trait ProviderBackend: Send + Sync {
    fn ready(&self) -> Result<(), CapabilityError>;
    fn execute(&self, input: &Value) -> Result<Value, CapabilityError>;

    fn reconcile(&self, _input: &Value) -> Result<Reconciliation, CapabilityError> {
        Err(CapabilityError::Execution(
            "provider does not support state reconciliation".into(),
        ))
    }

    fn execute_with_activity(
        &self,
        input: &Value,
        activity_sink: &mut dyn FnMut(CapabilityActivity) -> Result<(), CapabilityError>,
    ) -> Result<Value, CapabilityError> {
        activity_sink(CapabilityActivity {
            event: "step.progressed",
            detail: "provider effect is running".into(),
        })?;
        self.execute(input)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransferHostPreparationRequest {
    pub target_host: String,
    pub account: Option<String>,
    pub require_openssh: bool,
    pub require_bits: bool,
    pub require_transfer_keys: bool,
    pub transfer_key_paths: Vec<String>,
    pub required_directories: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransferHostPreparationResult {
    pub target_host: String,
    pub account: Option<String>,
    pub domain_controller: Option<String>,
    pub ready: bool,
    pub failure_category: Option<&'static str>,
    pub remediation: Option<String>,
    pub diagnostics: Vec<&'static str>,
}

impl TransferHostPreparationResult {
    fn into_value(self) -> Value {
        json!({
            "targetHost": self.target_host,
            "account": self.account,
            "domainController": self.domain_controller,
            "ready": self.ready,
            "failureCategory": self.failure_category,
            "remediation": self.remediation,
            "diagnostics": self.diagnostics,
        })
    }
}

/// Bounded target-local effects for transfer-host preparation. The caller
/// supplies every required feature and any PX-selected remediation identifier;
/// the backend reports observations without making readiness policy decisions.
pub trait TransferHostPreparationBackend: Send + Sync {
    fn available(&self) -> Result<(), CapabilityError>;

    fn prepare(
        &self,
        request: &TransferHostPreparationRequest,
        remediation: Option<&str>,
    ) -> Result<TransferHostPreparationResult, CapabilityError>;
}

pub struct TransferHostPreparation<B> {
    backend: B,
}

impl<B: TransferHostPreparationBackend> TransferHostPreparation<B> {
    pub fn new(backend: B) -> Self {
        Self { backend }
    }
}

impl<B: TransferHostPreparationBackend> ProviderBackend for TransferHostPreparation<B> {
    fn ready(&self) -> Result<(), CapabilityError> {
        self.backend.available()
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let request = TransferHostPreparationRequest {
            target_host: required_string(input, "targetHost")?.into(),
            account: input
                .get("account")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
                .map(Into::into),
            require_openssh: input
                .get("requireOpenSsh")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            require_bits: input
                .get("requireBits")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            require_transfer_keys: input
                .get("requireTransferKeys")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            transfer_key_paths: input
                .get("transferKeyPaths")
                .and_then(Value::as_array)
                .map(|values| string_array(values))
                .transpose()?
                .unwrap_or_default(),
            required_directories: input
                .get("requiredDirectories")
                .and_then(Value::as_array)
                .map(|values| string_array(values))
                .transpose()?
                .unwrap_or_default(),
        };
        let remediation = input.get("remediation").and_then(Value::as_str);
        Ok(self.backend.prepare(&request, remediation)?.into_value())
    }
}

pub struct WindowsTransferHostPreparation;

impl TransferHostPreparationBackend for WindowsTransferHostPreparation {
    fn available(&self) -> Result<(), CapabilityError> {
        #[cfg(windows)]
        {
            return command_ready("powershell.exe", POWERSHELL_PROBE);
        }
        #[cfg(not(windows))]
        {
            Err(CapabilityError::Execution(
                "Windows transfer-host preparation is unavailable on this platform".into(),
            ))
        }
    }

    fn prepare(
        &self,
        request: &TransferHostPreparationRequest,
        remediation: Option<&str>,
    ) -> Result<TransferHostPreparationResult, CapabilityError> {
        #[cfg(windows)]
        {
            return run_windows_transfer_preparation(request, remediation);
        }
        #[cfg(not(windows))]
        {
            let _ = (request, remediation);
            Err(CapabilityError::Execution(
                "Windows transfer-host preparation is unavailable on this platform".into(),
            ))
        }
    }
}

#[cfg(windows)]
struct TemporaryPreparationFiles {
    directory: PathBuf,
    task_name: String,
}

#[cfg(windows)]
impl TemporaryPreparationFiles {
    fn stop_task(&self) {
        let _ = Command::new("schtasks.exe")
            .args(["/End", "/TN", &self.task_name])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        loop {
            match preparation_task_state(&self.task_name) {
                Some(PreparationTaskState::Missing) => {
                    return;
                }
                Some(PreparationTaskState::Stopped) => {
                    let _ = Command::new("schtasks.exe")
                        .args(["/Delete", "/TN", &self.task_name, "/F"])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                    if matches!(
                        preparation_task_state(&self.task_name),
                        Some(PreparationTaskState::Missing)
                    ) {
                        return;
                    }
                }
                Some(PreparationTaskState::Running) | None => {
                    let _ = Command::new("schtasks.exe")
                        .args(["/End", "/TN", &self.task_name])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    }

    fn cleanup(&self) {
        self.stop_task();
        let _ = fs::remove_dir_all(&self.directory);
    }
}

#[cfg(windows)]
impl Drop for TemporaryPreparationFiles {
    fn drop(&mut self) {
        self.cleanup();
    }
}

#[cfg(windows)]
#[derive(Clone, Copy)]
enum PreparationTaskState {
    Missing,
    Running,
    Stopped,
}

#[cfg(windows)]
fn powershell_output(script: &str) -> Option<String> {
    let output = Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .stderr(Stdio::null())
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

#[cfg(windows)]
fn preparation_task_state(task_name: &str) -> Option<PreparationTaskState> {
    if !is_preparation_task_name(task_name) {
        return None;
    }
    let script = format!(
        "$task = Get-ScheduledTask -TaskName '{task_name}' -TaskPath '\\' -ErrorAction SilentlyContinue; \
         if ($null -eq $task) {{ 'Missing' }} else {{ [string]$task.State }}"
    );
    match powershell_output(&script)?.as_str() {
        "Missing" => Some(PreparationTaskState::Missing),
        "Running" | "Queued" | "Unknown" => Some(PreparationTaskState::Running),
        "Ready" | "Disabled" => Some(PreparationTaskState::Stopped),
        _ => None,
    }
}

#[cfg(windows)]
fn is_preparation_task_name(task_name: &str) -> bool {
    task_name
        .strip_prefix("PedanticTransferPreparation-")
        .is_some_and(|suffix| {
            !suffix.is_empty() && suffix.bytes().all(|byte| byte.is_ascii_digit())
        })
}

#[cfg(windows)]
fn scavenge_stale_preparation_tasks() -> Result<(), CapabilityError> {
    let task_names = loop {
        if let Some(output) = powershell_output(
            "Get-ScheduledTask -TaskPath '\\' | \
             Where-Object { $_.TaskName -like 'PedanticTransferPreparation-*' } | \
             ForEach-Object { $_.TaskName }",
        ) {
            break output;
        }
        std::thread::sleep(Duration::from_secs(1));
    };
    let mut stale_names: BTreeSet<String> = task_names
        .lines()
        .map(str::trim)
        .filter(|name| is_preparation_task_name(name))
        .map(str::to_owned)
        .collect();
    let temp_directory = std::env::temp_dir();
    let entries = fs::read_dir(&temp_directory).map_err(|_| {
        CapabilityError::Execution("preparation workspaces could not be inspected".into())
    })?;
    for entry in entries {
        let entry = entry.map_err(|_| {
            CapabilityError::Execution("preparation workspaces could not be inspected".into())
        })?;
        let file_name = entry.file_name();
        if let Some(name) = file_name.to_str()
            && is_preparation_task_name(name)
        {
            stale_names.insert(name.to_owned());
        }
    }
    for task_name in stale_names {
        TemporaryPreparationFiles {
            directory: temp_directory.join(&task_name),
            task_name,
        }
        .cleanup();
    }
    Ok(())
}

#[cfg(windows)]
fn run_windows_transfer_preparation(
    request: &TransferHostPreparationRequest,
    remediation: Option<&str>,
) -> Result<TransferHostPreparationResult, CapabilityError> {
    scavenge_stale_preparation_tasks()?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| CapabilityError::Execution("system clock is unavailable".into()))?
        .as_nanos();
    let task_name = format!("PedanticTransferPreparation-{nonce}");
    let directory = std::env::temp_dir().join(&task_name);
    fs::create_dir(&directory).map_err(|_| {
        CapabilityError::Execution("preparation workspace could not be created".into())
    })?;
    let temporary = TemporaryPreparationFiles {
        directory: directory.clone(),
        task_name: task_name.clone(),
    };
    let plan = json!({
        "targetHost": request.target_host,
        "account": request.account,
        "requireOpenSsh": request.require_openssh,
        "requireBits": request.require_bits,
        "requireTransferKeys": request.require_transfer_keys,
        "transferKeyPaths": request.transfer_key_paths,
        "requiredDirectories": request.required_directories,
        "remediation": remediation,
    });
    let encoded_plan = base64::engine::general_purpose::STANDARD
        .encode(serde_json::to_vec(&plan).expect("transfer preparation plan is serializable"));
    let script_path = temporary.directory.join("prepare.ps1");
    let result_path = temporary.directory.join("result.json");
    fs::write(&script_path, WINDOWS_TRANSFER_PREPARATION_SCRIPT).map_err(|_| {
        CapabilityError::Execution("preparation script could not be written".into())
    })?;
    let task_command = format!(
        "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{}\" -Plan \"{}\" -Result \"{}\"",
        script_path.display(),
        encoded_plan,
        result_path.display()
    );
    let created = Command::new("schtasks.exe")
        .args([
            "/Create",
            "/TN",
            &temporary.task_name,
            "/SC",
            "ONCE",
            "/ST",
            "00:00",
            "/RU",
            "SYSTEM",
            "/RL",
            "HIGHEST",
            "/Z",
            "/TR",
            &task_command,
            "/F",
        ])
        .status()
        .map_err(|_| {
            CapabilityError::Execution("target-local SYSTEM task could not be created".into())
        })?;
    if !created.success() {
        return Err(CapabilityError::Execution(
            "target-local SYSTEM task could not be created".into(),
        ));
    }
    let started = Command::new("schtasks.exe")
        .args(["/Run", "/TN", &temporary.task_name])
        .status()
        .map_err(|_| {
            CapabilityError::Execution("target-local SYSTEM task could not start".into())
        })?;
    if !started.success() {
        return Err(CapabilityError::Execution(
            "target-local SYSTEM task could not start".into(),
        ));
    }
    for _ in 0..120 {
        if result_path.exists() {
            break;
        }
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    if !result_path.exists() {
        temporary.cleanup();
        return Err(CapabilityError::Execution(
            "target-local SYSTEM task did not report a result".into(),
        ));
    }
    temporary.stop_task();
    let result_bytes = fs::read(&result_path).map_err(|_| {
        CapabilityError::Execution("target-local SYSTEM task did not report a result".into())
    })?;
    temporary.cleanup();
    let result: Value = serde_json::from_slice(&result_bytes)
        .map_err(|_| CapabilityError::Execution("target-local SYSTEM result was invalid".into()))?;
    let failure_category = result
        .get("failureCategory")
        .and_then(Value::as_str)
        .and_then(transfer_failure_category);
    Ok(TransferHostPreparationResult {
        target_host: result
            .get("targetHost")
            .and_then(Value::as_str)
            .unwrap_or(&request.target_host)
            .into(),
        account: result
            .get("account")
            .and_then(Value::as_str)
            .map(Into::into),
        domain_controller: result
            .get("domainController")
            .and_then(Value::as_str)
            .map(Into::into),
        ready: result
            .get("ready")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        failure_category,
        remediation: result
            .get("remediation")
            .and_then(Value::as_str)
            .map(Into::into),
        diagnostics: result
            .get("diagnostics")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .filter_map(transfer_diagnostic)
            .collect(),
    })
}

#[cfg(windows)]
fn transfer_failure_category(value: &str) -> Option<&'static str> {
    match value {
        "ad_tooling_missing" => Some("ad_tooling_missing"),
        "domain_connectivity_failed" => Some("domain_connectivity_failed"),
        "gmsa_authorization_denied" => Some("gmsa_authorization_denied"),
        "prerequisite_failed" => Some("prerequisite_failed"),
        _ => None,
    }
}

#[cfg(windows)]
fn transfer_diagnostic(value: &str) -> Option<&'static str> {
    match value {
        "openssh_ready"
        | "bits_ready"
        | "transfer_keys_ready"
        | "directories_ready"
        | "gmsa_ready"
        | "system_kerberos_refreshed" => Some(match value {
            "openssh_ready" => "openssh_ready",
            "bits_ready" => "bits_ready",
            "transfer_keys_ready" => "transfer_keys_ready",
            "directories_ready" => "directories_ready",
            "gmsa_ready" => "gmsa_ready",
            _ => "system_kerberos_refreshed",
        }),
        _ => None,
    }
}

#[cfg(windows)]
const WINDOWS_TRANSFER_PREPARATION_SCRIPT: &str = r#"
param([string]$Plan, [string]$Result)
$plan = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Plan)) | ConvertFrom-Json
$outcome = @{ targetHost = $plan.targetHost; account = $plan.account; domainController = $null; ready = $false; failureCategory = "prerequisite_failed"; remediation = $plan.remediation; diagnostics = @() }
try {
  foreach ($directory in @($plan.requiredDirectories)) { New-Item -ItemType Directory -Force -Path $directory -ErrorAction Stop | Out-Null }
  if (@($plan.requiredDirectories).Count -gt 0) { $outcome.diagnostics += "directories_ready" }
  if ($plan.requireOpenSsh) {
    foreach ($capability in "OpenSSH.Client~~~~0.0.1.0", "OpenSSH.Server~~~~0.0.1.0") {
      if ((Get-WindowsCapability -Online -Name $capability -ErrorAction Stop).State -ne "Installed") { Add-WindowsCapability -Online -Name $capability -ErrorAction Stop | Out-Null }
    }
    Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
    Start-Service -Name sshd -ErrorAction Stop
    Get-Command ssh, scp -ErrorAction Stop | Out-Null
    $outcome.diagnostics += "openssh_ready"
  }
  if ($plan.requireBits) { Set-Service -Name BITS -StartupType Automatic -ErrorAction Stop; Start-Service -Name BITS -ErrorAction Stop; $outcome.diagnostics += "bits_ready" }
  if ($plan.requireTransferKeys) {
    if (@($plan.transferKeyPaths).Count -eq 0) { throw "transfer key paths are required" }
    foreach ($path in @($plan.transferKeyPaths)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "transfer key is unavailable" } }
    $outcome.diagnostics += "transfer_keys_ready"
  }
  if ($plan.account) {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) { $outcome.failureCategory = "ad_tooling_missing"; throw "AD tooling unavailable" }
    Import-Module ActiveDirectory -ErrorAction Stop
    try { $outcome.domainController = (Get-ADDomainController -Discover -ErrorAction Stop).HostName } catch { $outcome.failureCategory = "domain_connectivity_failed"; throw }
    try { Install-ADServiceAccount -Identity $plan.account -ErrorAction Stop; if (-not (Test-ADServiceAccount -Identity $plan.account -ErrorAction Stop)) { throw "gMSA test failed" } } catch { $outcome.failureCategory = "gmsa_authorization_denied"; throw }
    & klist purge -li 0x3e7 | Out-Null
    $outcome.diagnostics += "gmsa_ready", "system_kerberos_refreshed"
  }
  $outcome.ready = $true
} catch {}
[IO.File]::WriteAllText($Result, ($outcome | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)
"#;

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
            findings: if ready {
                Vec::new()
            } else {
                vec![json!({
                    "code": "provider_unavailable",
                    "message": "The provider runtime is unavailable"
                })]
            },
            eligible_remediations: if ready {
                Vec::new()
            } else {
                self.remediation.clone()
            },
            diagnostics: if ready {
                Vec::new()
            } else {
                vec![json!({"code": "PROVIDER_UNAVAILABLE"})]
            },
        }
    }

    fn execute_unchecked(&self, input: &Value) -> Result<Value, CapabilityError> {
        self.backend.execute(input)
    }

    fn reconcile_unchecked(&self, input: &Value) -> Result<Reconciliation, CapabilityError> {
        self.backend.reconcile(input)
    }

    fn execute_unchecked_with_activity(
        &self,
        input: &Value,
        activity_sink: &mut dyn FnMut(CapabilityActivity) -> Result<(), CapabilityError>,
    ) -> Result<Value, CapabilityError> {
        self.backend.execute_with_activity(input, activity_sink)
    }
}

pub fn register_production_providers(
    registry: &mut CapabilityRegistry,
) -> Result<(), CapabilityError> {
    for provider in production_providers() {
        registry.register(provider)?;
    }
    Ok(())
}

pub fn production_registry() -> Result<CapabilityRegistry, CapabilityError> {
    let mut registry = CapabilityRegistry::default();
    register_production_providers(&mut registry)?;
    Ok(registry)
}

pub fn production_providers() -> Vec<Arc<dyn Capability>> {
    vec![
        Arc::new(Provider::new(
            transfer_manifest(),
            FilesystemTransfer,
            vec![],
        )),
        Arc::new(Provider::new(
            transfer_host_preparation_manifest(),
            TransferHostPreparation::new(WindowsTransferHostPreparation),
            vec![],
        )),
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
    Ok(())
}

pub struct FilesystemTransfer;

impl ProviderBackend for FilesystemTransfer {
    fn ready(&self) -> Result<(), CapabilityError> {
        Ok(())
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let mut activity_sink = |_| Ok(());
        self.execute_with_activity(input, &mut activity_sink)
    }

    fn reconcile(&self, input: &Value) -> Result<Reconciliation, CapabilityError> {
        let source = Path::new(required_string(input, "sourcePath")?);
        let destination = Path::new(required_string(input, "destinationPath")?);
        let source_metadata = fs::metadata(source)
            .map_err(|_| CapabilityError::Execution("transfer source is unavailable".into()))?;
        if !source_metadata.is_file() {
            return Err(CapabilityError::Execution(
                "transfer source is unavailable".into(),
            ));
        }
        let destination_metadata = match fs::metadata(destination) {
            Ok(metadata) if metadata.is_file() => metadata,
            Ok(_) => return Ok(Reconciliation::Unsafe),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Ok(Reconciliation::RetrySafe);
            }
            Err(_) => {
                return Err(CapabilityError::Execution(
                    "transfer destination is unavailable".into(),
                ));
            }
        };
        if destination_metadata.len() > source_metadata.len() {
            return Ok(Reconciliation::Unsafe);
        }

        let mut source_file = File::open(source)
            .map_err(|_| CapabilityError::Execution("transfer source is unavailable".into()))?;
        let mut destination_file = File::open(destination).map_err(|_| {
            CapabilityError::Execution("transfer destination is unavailable".into())
        })?;
        let mut source_buffer = [0; 64 * 1024];
        let mut destination_buffer = [0; 64 * 1024];
        let mut remaining = destination_metadata.len();
        while remaining > 0 {
            let count = remaining.min(source_buffer.len() as u64) as usize;
            source_file
                .read_exact(&mut source_buffer[..count])
                .map_err(|_| {
                    CapabilityError::Execution("transfer source could not be read".into())
                })?;
            destination_file
                .read_exact(&mut destination_buffer[..count])
                .map_err(|_| {
                    CapabilityError::Execution("transfer destination could not be read".into())
                })?;
            if source_buffer[..count] != destination_buffer[..count] {
                return Ok(Reconciliation::Unsafe);
            }
            remaining -= count as u64;
        }
        Ok(Reconciliation::RetrySafe)
    }

    fn execute_with_activity(
        &self,
        input: &Value,
        activity_sink: &mut dyn FnMut(CapabilityActivity) -> Result<(), CapabilityError>,
    ) -> Result<Value, CapabilityError> {
        let started_at = Instant::now();
        let source = required_string(input, "sourcePath")?;
        let destination = required_string(input, "destinationPath")?;
        let source_path = Path::new(source);
        if !source_path.is_file() {
            return Err(CapabilityError::Execution(
                "transfer source is unavailable".into(),
            ));
        }
        let bytes_total = fs::metadata(source_path)
            .map_err(|_| CapabilityError::Execution("transfer source is unavailable".into()))?
            .len();
        if Path::new(destination).is_file()
            && fs::metadata(destination)
                .map_err(|_| {
                    CapabilityError::Execution("transfer destination is unavailable".into())
                })?
                .len()
                == bytes_total
        {
            let source_digest = digest_file(source_path)?;
            let destination_digest = digest_file(Path::new(destination))?;
            if destination_digest == source_digest {
                return Ok(transfer_observation(
                    source_digest,
                    destination_digest,
                    TransferMetrics {
                        bytes_total,
                        bytes_transferred: 0,
                        retry_count: 0,
                        resume_count: 0,
                        current_throughput_bps: 0,
                        elapsed: started_at.elapsed(),
                    },
                ));
            }
        }
        let mut source_file = File::open(source_path)
            .map_err(|_| CapabilityError::Execution("transfer source is unavailable".into()))?;
        let mut retry_count = 0u64;
        let mut resume_count = 0u64;
        let mut source_hasher = Sha256::new();
        let mut resumed_bytes = 0u64;
        let mut destination_file;
        if Path::new(destination).is_file() {
            let destination_length = fs::metadata(destination)
                .map_err(|_| {
                    CapabilityError::Execution("transfer destination is unavailable".into())
                })?
                .len();
            if destination_length > 0 && destination_length < bytes_total {
                let mut partial_file = File::open(destination).map_err(|_| {
                    CapabilityError::Execution("transfer destination is unavailable".into())
                })?;
                let mut source_prefix = [0; 64 * 1024];
                let mut destination_prefix = [0; 64 * 1024];
                let mut matching_prefix = true;
                while resumed_bytes < destination_length {
                    let count = (destination_length - resumed_bytes).min(source_prefix.len() as u64)
                        as usize;
                    read_exact_with_retry(
                        &mut source_file,
                        &mut source_prefix[..count],
                        &mut retry_count,
                    )
                    .map_err(|_| {
                        CapabilityError::Execution("transfer source could not be read".into())
                    })?;
                    read_exact_with_retry(
                        &mut partial_file,
                        &mut destination_prefix[..count],
                        &mut retry_count,
                    )
                    .map_err(|_| {
                        CapabilityError::Execution("transfer destination could not be read".into())
                    })?;
                    if source_prefix[..count] != destination_prefix[..count] {
                        matching_prefix = false;
                        break;
                    }
                    source_hasher.update(&source_prefix[..count]);
                    resumed_bytes += count as u64;
                }
                if matching_prefix {
                    resume_count = 1;
                    destination_file =
                        OpenOptions::new()
                            .append(true)
                            .open(destination)
                            .map_err(|_| {
                                CapabilityError::Execution(
                                    "transfer destination is unavailable".into(),
                                )
                            })?;
                } else {
                    source_file.seek(SeekFrom::Start(0)).map_err(|_| {
                        CapabilityError::Execution("transfer source could not be read".into())
                    })?;
                    source_hasher = Sha256::new();
                    resumed_bytes = 0;
                    destination_file = File::create(destination).map_err(|_| {
                        CapabilityError::Execution("transfer destination is unavailable".into())
                    })?;
                }
            } else {
                destination_file = File::create(destination).map_err(|_| {
                    CapabilityError::Execution("transfer destination is unavailable".into())
                })?;
            }
        } else {
            destination_file = File::create(destination).map_err(|_| {
                CapabilityError::Execution("transfer destination is unavailable".into())
            })?;
        }
        let mut bytes_transferred = 0u64;
        let mut next_progress = (bytes_total / 10).max(1);
        let mut last_progress_bytes = 0;
        let mut last_progress_at = Instant::now();
        let mut current_throughput_bps = 0;
        let mut buffer = [0; 64 * 1024];
        loop {
            let bytes_read = read_with_retry(&mut source_file, &mut buffer, &mut retry_count)
                .map_err(|_| {
                    CapabilityError::Execution("transfer source could not be read".into())
                })?;
            if bytes_read == 0 {
                break;
            }
            write_all_with_retry(
                &mut destination_file,
                &buffer[..bytes_read],
                &mut retry_count,
            )
            .map_err(|_| CapabilityError::Execution("transfer could not complete".into()))?;
            source_hasher.update(&buffer[..bytes_read]);
            bytes_transferred = bytes_transferred.saturating_add(bytes_read as u64);
            let total_progress = resumed_bytes.saturating_add(bytes_transferred);
            if total_progress >= next_progress {
                activity_sink(CapabilityActivity {
                    event: "step.progressed",
                    detail: format!("transferred {total_progress} of {bytes_total} bytes"),
                })?;
                current_throughput_bps = throughput_bps(
                    bytes_transferred.saturating_sub(last_progress_bytes),
                    last_progress_at.elapsed(),
                );
                last_progress_bytes = bytes_transferred;
                last_progress_at = Instant::now();
                next_progress = total_progress.saturating_add((bytes_total / 10).max(1));
            }
        }
        if bytes_transferred > last_progress_bytes {
            current_throughput_bps = throughput_bps(
                bytes_transferred.saturating_sub(last_progress_bytes),
                last_progress_at.elapsed(),
            );
        }
        flush_with_retry(&mut destination_file, &mut retry_count)
            .map_err(|_| CapabilityError::Execution("transfer could not complete".into()))?;
        let source_digest = format!("sha256:{:x}", source_hasher.finalize());
        let destination_digest = digest_file(Path::new(destination))?;
        if destination_digest != source_digest {
            return Err(CapabilityError::Execution(
                "transfer verification failed".into(),
            ));
        }
        Ok(transfer_observation(
            source_digest,
            destination_digest,
            TransferMetrics {
                bytes_total,
                bytes_transferred,
                retry_count,
                resume_count,
                current_throughput_bps,
                elapsed: started_at.elapsed(),
            },
        ))
    }
}

pub struct WindowsPackage;

impl ProviderBackend for WindowsPackage {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("winget", WINGET_PROBE)
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(input, "action", &["install", "upgrade", "remove"])?;
        let package = required_string(input, "packageId")?;
        let observation = run_command(
            "winget",
            &[
                action,
                "--id",
                package,
                "--exact",
                "--disable-interactivity",
            ],
        )?;
        Ok(effect_observation(&observation))
    }
}

pub struct WindowsFeature;

impl ProviderBackend for WindowsFeature {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("dism.exe", DISM_PROBE)
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(input, "action", &["enable", "disable"])?;
        let feature = required_string(input, "featureName")?;
        let mode = if action == "enable" {
            "/Enable-Feature"
        } else {
            "/Disable-Feature"
        };
        let observation = run_command(
            "dism.exe",
            &[
                "/Online",
                mode,
                &format!("/FeatureName:{feature}"),
                "/NoRestart",
            ],
        )?;
        Ok(json!({
            "outputDigest": effect_digest(&observation),
            "rebootRequired": observation.reboot_required
        }))
    }
}

pub struct WindowsOsSetup;

impl ProviderBackend for WindowsOsSetup {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("powershell.exe", POWERSHELL_PROBE)
    }

    fn execute(&self, input: &Value) -> Result<Value, CapabilityError> {
        let action = enum_value(
            input,
            "action",
            &["enable-remote-management", "enable-developer-mode"],
        )?;
        let script = match action {
            "enable-remote-management" => "Enable-PSRemoting -Force -SkipNetworkProfileCheck",
            "enable-developer-mode" => {
                "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force"
            }
            _ => unreachable!("validated setup action"),
        };
        let observation = run_command(
            "powershell.exe",
            &["-NoProfile", "-NonInteractive", "-Command", script],
        )?;
        Ok(effect_observation(&observation))
    }
}

pub struct HyperV;

impl ProviderBackend for HyperV {
    fn ready(&self) -> Result<(), CapabilityError> {
        command_ready("powershell.exe", HYPERV_PROBE)
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
        let observation = run_command(
            "powershell.exe",
            &[
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                command,
                "-Name",
                name,
            ],
        )?;
        Ok(effect_observation(&observation))
    }
}

/// Read-only Hyper-V inventory adapter used by transfer planning. It reports
/// raw host observations and leaves all planning and policy decisions to PX.
pub struct HyperVInventory;

impl HyperVInventoryProvider for HyperVInventory {
    fn query_host(&self, host_name: &str) -> Result<HyperVHostInventory, HostQueryFailure> {
        const INVENTORY_SCRIPT: &str = r#"
Invoke-Command -ComputerName $env:PEDANTIC_HYPERV_HOST -ScriptBlock {
    function Get-DifferencingChain([string]$Path) {
        $chain = @()
        $vhd = Get-VHD -Path $Path -ErrorAction Stop
        while ($vhd.VhdType -eq 'Differencing' -and $vhd.ParentPath) {
            $chain += $vhd.ParentPath
            $vhd = Get-VHD -Path $vhd.ParentPath -ErrorAction Stop
        }
        return $chain
    }
    ConvertTo-Json -InputObject @(
        Get-VM -ErrorAction Stop | ForEach-Object {
            $vm = $_
            [pscustomobject]@{
                name = $vm.Name
                vmId = $vm.Id.Guid
                effectiveMacAddresses = @(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop | ForEach-Object { $_.MacAddress })
                hardDrives = @(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        path = $_.Path
                        differencingChain = @(Get-DifferencingChain $_.Path)
                    }
                })
            }
        }
    ) -Compress -Depth 8
}
"#;
        let output = Command::new("powershell.exe")
            .env("PEDANTIC_HYPERV_HOST", host_name)
            .args([
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                INVENTORY_SCRIPT,
            ])
            .output()
            .map_err(|error| {
                classified_host_failure(
                    host_name,
                    error.to_string(),
                    HostFailureCategory::HyperVUnavailable,
                    false,
                )
            })?;
        if !output.status.success() {
            return Err(classify_hyperv_failure(
                host_name,
                &String::from_utf8_lossy(&output.stderr),
            ));
        }
        parse_hyperv_inventory(host_name, &output.stdout)
    }
}

fn classify_hyperv_failure(host_name: &str, error: &str) -> HostQueryFailure {
    let error = error.trim();
    let error_lower = error.to_ascii_lowercase();
    let (category, retryable) = if [
        "access is denied",
        "unauthorized",
        "authentication",
        "logon failure",
        "credential",
        "securityerror",
    ]
    .iter()
    .any(|marker| error_lower.contains(marker))
    {
        (HostFailureCategory::Authentication, false)
    } else if ["get-vm", "get-vhd", "hyper-v"]
        .iter()
        .any(|marker| error_lower.contains(marker))
        && [
            "not recognized",
            "not installed",
            "not available",
            "cannot find",
            "commandnotfound",
        ]
        .iter()
        .any(|marker| error_lower.contains(marker))
    {
        (HostFailureCategory::HyperVUnavailable, false)
    } else if [
        "cannot connect",
        "connection",
        "timed out",
        "timeout",
        "winrm",
        "wsman",
        "rpc server is unavailable",
        "network path",
        "name resolution",
        "unreachable",
        "host not found",
    ]
    .iter()
    .any(|marker| error_lower.contains(marker))
    {
        (HostFailureCategory::HostUnavailable, true)
    } else {
        (HostFailureCategory::HostUnavailable, false)
    };
    classified_host_failure(host_name, error.to_owned(), category, retryable)
}

fn classified_host_failure(
    host_name: &str,
    error: String,
    category: HostFailureCategory,
    retryable: bool,
) -> HostQueryFailure {
    HostQueryFailure {
        host_name: host_name.into(),
        category,
        error: if error.is_empty() {
            "Hyper-V inventory query failed".into()
        } else {
            error
        },
        retryable,
    }
}

fn parse_hyperv_inventory(
    host_name: &str,
    output: &[u8],
) -> Result<HyperVHostInventory, HostQueryFailure> {
    let value: Value = serde_json::from_slice(output).map_err(|error| HostQueryFailure {
        host_name: host_name.into(),
        category: HostFailureCategory::InvalidResponse,
        error: format!("Hyper-V inventory response was not valid JSON: {error}"),
        retryable: false,
    })?;
    let vms = match value {
        Value::Null => Vec::new(),
        Value::Array(vms) => vms,
        vm => vec![vm],
    };
    let virtual_machines = vms
        .into_iter()
        .map(|vm| parse_hyperv_vm(host_name, vm))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(HyperVHostInventory {
        host_name: host_name.into(),
        virtual_machines,
    })
}

fn parse_hyperv_vm(host_name: &str, vm: Value) -> Result<HyperVVmInventory, HostQueryFailure> {
    let object = vm
        .as_object()
        .ok_or_else(|| invalid_inventory(host_name, "VM is not an object"))?;
    let name = json_string(object, "name", host_name)?;
    let vm_id = json_string(object, "vmId", host_name)?;
    let effective_mac_addresses = json_string_array(object, "effectiveMacAddresses", host_name)?;
    let hard_drives = object
        .get("hardDrives")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid_inventory(host_name, "VM hardDrives is not an array"))?
        .iter()
        .map(|drive| {
            let drive = drive
                .as_object()
                .ok_or_else(|| invalid_inventory(host_name, "hard drive is not an object"))?;
            Ok(HyperVHardDrive {
                path: json_string(drive, "path", host_name)?,
                differencing_chain: json_string_array(drive, "differencingChain", host_name)?,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(HyperVVmInventory {
        name,
        vm_id,
        effective_mac_addresses,
        hard_drives,
    })
}

fn json_string(
    object: &serde_json::Map<String, Value>,
    field: &str,
    host_name: &str,
) -> Result<String, HostQueryFailure> {
    object
        .get(field)
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .ok_or_else(|| invalid_inventory(host_name, &format!("{field} is not a string")))
}

fn json_string_array(
    object: &serde_json::Map<String, Value>,
    field: &str,
    host_name: &str,
) -> Result<Vec<String>, HostQueryFailure> {
    object
        .get(field)
        .and_then(Value::as_array)
        .ok_or_else(|| invalid_inventory(host_name, &format!("{field} is not an array")))?
        .iter()
        .map(|value| {
            value.as_str().map(ToString::to_string).ok_or_else(|| {
                invalid_inventory(host_name, &format!("{field} contains a non-string"))
            })
        })
        .collect()
}

fn invalid_inventory(host_name: &str, error: &str) -> HostQueryFailure {
    HostQueryFailure {
        host_name: host_name.into(),
        category: HostFailureCategory::InvalidResponse,
        error: format!("Hyper-V inventory response is invalid: {error}"),
        retryable: false,
    }
}

fn command_ready(program: &str, arguments: &[&str]) -> Result<(), CapabilityError> {
    Command::new(program)
        .args(arguments)
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

struct CommandObservation {
    output_digest: String,
    reboot_required: bool,
}

fn run_command(program: &str, arguments: &[&str]) -> Result<CommandObservation, CapabilityError> {
    let output = Command::new(program)
        .args(arguments)
        .output()
        .map_err(|_| CapabilityError::Execution("provider effect could not start".into()))?;
    let reboot_required = output
        .status
        .success()
        .then_some(false)
        .or_else(|| (output.status.code() == Some(3010)).then_some(true))
        .ok_or_else(|| CapabilityError::Execution("provider effect failed".into()))?;
    Ok(CommandObservation {
        output_digest: observed_output_digest(output.status.code(), &output.stdout, &output.stderr),
        reboot_required,
    })
}

fn required_string<'a>(input: &'a Value, property: &str) -> Result<&'a str, CapabilityError> {
    input
        .get(property)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CapabilityError::InvalidInput(format!("{property} is required")))
}

fn string_array(values: &[Value]) -> Result<Vec<String>, CapabilityError> {
    values
        .iter()
        .map(Value::as_str)
        .collect::<Option<Vec<_>>>()
        .ok_or_else(|| CapabilityError::InvalidInput("array values must be strings".into()))
        .map(|values| values.into_iter().map(Into::into).collect())
}

fn enum_value<'a>(
    input: &'a Value,
    property: &str,
    values: &[&str],
) -> Result<&'a str, CapabilityError> {
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
    let mut file = File::open(path)
        .map_err(|_| CapabilityError::Execution("transfer file cannot be read".into()))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        let bytes_read = file
            .read(&mut buffer)
            .map_err(|_| CapabilityError::Execution("transfer file cannot be read".into()))?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("sha256:{:x}", hasher.finalize()))
}

fn read_with_retry(
    reader: &mut impl Read,
    buffer: &mut [u8],
    retry_count: &mut u64,
) -> io::Result<usize> {
    loop {
        match reader.read(buffer) {
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {
                *retry_count = retry_count.saturating_add(1);
            }
            result => return result,
        }
    }
}

fn read_exact_with_retry(
    reader: &mut impl Read,
    buffer: &mut [u8],
    retry_count: &mut u64,
) -> io::Result<()> {
    let mut offset = 0;
    while offset < buffer.len() {
        match read_with_retry(reader, &mut buffer[offset..], retry_count)? {
            0 => return Err(io::ErrorKind::UnexpectedEof.into()),
            bytes_read => offset += bytes_read,
        }
    }
    Ok(())
}

fn write_all_with_retry(
    writer: &mut impl Write,
    buffer: &[u8],
    retry_count: &mut u64,
) -> io::Result<()> {
    let mut offset = 0;
    while offset < buffer.len() {
        match writer.write(&buffer[offset..]) {
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {
                *retry_count = retry_count.saturating_add(1);
            }
            Err(error) => return Err(error),
            Ok(0) => return Err(io::ErrorKind::WriteZero.into()),
            Ok(bytes_written) => offset += bytes_written,
        }
    }
    Ok(())
}

fn flush_with_retry(writer: &mut impl Write, retry_count: &mut u64) -> io::Result<()> {
    loop {
        match writer.flush() {
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {
                *retry_count = retry_count.saturating_add(1);
            }
            result => return result,
        }
    }
}

fn effect_observation(observation: &CommandObservation) -> Value {
    json!({"outputDigest": effect_digest(observation)})
}

fn effect_digest(observation: &CommandObservation) -> &str {
    &observation.output_digest
}

fn observed_output_digest(exit_code: Option<i32>, stdout: &[u8], stderr: &[u8]) -> String {
    let normalized = json!({
        "exitCode": exit_code,
        "stdout": normalize_command_output(stdout),
        "stderr": normalize_command_output(stderr),
    });
    digest(&normalized)
}

fn normalize_command_output(output: &[u8]) -> String {
    String::from_utf8_lossy(output)
        .replace("\r\n", "\n")
        .trim()
        .to_owned()
}

struct TransferMetrics {
    bytes_total: u64,
    bytes_transferred: u64,
    retry_count: u64,
    resume_count: u64,
    current_throughput_bps: u64,
    elapsed: std::time::Duration,
}

fn transfer_observation(
    source_digest: String,
    destination_digest: String,
    metrics: TransferMetrics,
) -> Value {
    let elapsed_ms = metrics.elapsed.as_millis().max(1).min(u64::MAX as u128) as u64;
    let average_throughput_bps = throughput_bps(metrics.bytes_transferred, metrics.elapsed);
    json!({
        "bytesTotal": metrics.bytes_total,
        "bytesTransferred": metrics.bytes_transferred,
        "elapsedMs": elapsed_ms,
        "currentThroughputBps": metrics.current_throughput_bps,
        "averageThroughputBps": average_throughput_bps,
        "resumeCount": metrics.resume_count,
        "retryCount": metrics.retry_count,
        "sourceDigest": source_digest,
        "destinationDigest": destination_digest,
        "verificationState": "verified"
    })
}

fn throughput_bps(bytes: u64, elapsed: std::time::Duration) -> u64 {
    let elapsed_ms = elapsed.as_millis().max(1);
    (bytes as u128)
        .saturating_mul(1000)
        .checked_div(elapsed_ms)
        .unwrap_or_default()
        .min(u64::MAX as u128) as u64
}

fn manifest(
    capability: &str,
    risk_class: RiskClass,
    retry_class: RetryClass,
    idempotency: Idempotency,
    input_schema: Value,
) -> CapabilityManifest {
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
    manifest(
        "transfer.filesystem",
        RiskClass::Moderate,
        RetryClass::SafeAfterObservation,
        Idempotency::ObservationRequired,
        json!({
            "type": "object", "additionalProperties": false, "required": ["sourcePath", "destinationPath"],
            "properties": {"sourcePath": {"type": "string", "minLength": 1}, "destinationPath": {"type": "string", "minLength": 1}}
        }),
    )
}

fn transfer_host_preparation_manifest() -> CapabilityManifest {
    manifest(
        "transfer.host-prepare",
        RiskClass::High,
        RetryClass::SafeAfterObservation,
        Idempotency::ObservationRequired,
        json!({
            "type": "object",
            "additionalProperties": false,
            "required": ["targetHost"],
            "properties": {
                "targetHost": {"type": "string", "minLength": 1},
                "account": {"type": "string", "minLength": 1},
                "requireOpenSsh": {"type": "boolean"},
                "requireBits": {"type": "boolean"},
                "requireTransferKeys": {"type": "boolean"},
                "transferKeyPaths": {"type": "array", "items": {"type": "string", "minLength": 1}},
                "requiredDirectories": {"type": "array", "items": {"type": "string", "minLength": 1}},
                "remediation": {"type": "string", "minLength": 1}
            }
        }),
    )
}

fn package_manifest() -> CapabilityManifest {
    manifest(
        "package.manage",
        RiskClass::Moderate,
        RetryClass::SafeAfterObservation,
        Idempotency::ObservationRequired,
        action_input("packageId", &["install", "upgrade", "remove"]),
    )
}

fn feature_manifest() -> CapabilityManifest {
    manifest(
        "windows.feature",
        RiskClass::High,
        RetryClass::SafeAfterObservation,
        Idempotency::ObservationRequired,
        action_input("featureName", &["enable", "disable"]),
    )
}

fn os_setup_manifest() -> CapabilityManifest {
    manifest(
        "windows.os-setup",
        RiskClass::High,
        RetryClass::RequiresFreshAuthorization,
        Idempotency::ObservationRequired,
        json!({
            "type": "object", "additionalProperties": false, "required": ["action"],
            "properties": {"action": {"type": "string", "enum": ["enable-remote-management", "enable-developer-mode"]}}
        }),
    )
}

fn hyperv_manifest() -> CapabilityManifest {
    let mut manifest = manifest(
        "hyperv.vm",
        RiskClass::Dangerous,
        RetryClass::RequiresOperatorReview,
        Idempotency::NonIdempotent,
        action_input("vmName", &["start", "stop", "checkpoint"]),
    );
    manifest.requires_checkpoint = Some(true);
    manifest
}

fn action_input(name: &str, actions: &[&str]) -> Value {
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
    fn hyperv_inventory_parses_vm_evidence_without_policy() {
        let inventory = parse_hyperv_inventory(
            "hyperv-a",
            br#"[{
                "name":"vm-a",
                "vmId":"vm-id-a",
                "effectiveMacAddresses":["00155D000001"],
                "hardDrives":[{
                    "path":"D:\\VMs\\vm-a\\disk.avhdx",
                    "differencingChain":["D:\\VMs\\vm-a\\base.vhdx"]
                }]
            }]"#,
        )
        .expect("valid inventory");
        assert_eq!(inventory.host_name, "hyperv-a");
        assert_eq!(inventory.virtual_machines[0].vm_id, "vm-id-a");
        assert_eq!(
            inventory.virtual_machines[0].hard_drives[0].differencing_chain,
            ["D:\\VMs\\vm-a\\base.vhdx"]
        );
    }

    #[test]
    fn hyperv_query_failures_have_specific_categories_and_retryability() {
        let authentication = classify_hyperv_failure("host", "Access is denied.");
        assert_eq!(authentication.category, HostFailureCategory::Authentication);
        assert!(!authentication.retryable);

        let missing_hyperv = classify_hyperv_failure(
            "host",
            "Get-VM : The term 'Get-VM' is not recognized as a cmdlet.",
        );
        assert_eq!(
            missing_hyperv.category,
            HostFailureCategory::HyperVUnavailable
        );
        assert!(!missing_hyperv.retryable);

        let unavailable_host =
            classify_hyperv_failure("host", "The WinRM client cannot process the request.");
        assert_eq!(
            unavailable_host.category,
            HostFailureCategory::HostUnavailable
        );
        assert!(unavailable_host.retryable);

        let unknown_failure = classify_hyperv_failure("host", "Unexpected local failure.");
        assert_eq!(
            unknown_failure.category,
            HostFailureCategory::HostUnavailable
        );
        assert!(!unknown_failure.retryable);
    }

    #[test]
    fn transfer_is_idempotent_and_reports_monotonic_observations() {
        let directory = tempdir().unwrap();
        let source = directory.path().join("source");
        let destination = directory.path().join("destination");
        fs::write(&source, vec![b'x'; 1024 * 1024]).unwrap();
        let provider = Provider::new(transfer_manifest(), FilesystemTransfer, vec![]);
        let input = json!({"sourcePath": source, "destinationPath": destination});
        let mut activity = Vec::new();
        let first = provider
            .execute_with_activity(&input, &mut |event| {
                activity.push(event);
                Ok(())
            })
            .unwrap();
        let second = provider.execute(&input).unwrap();
        assert_eq!(first["bytesTotal"], first["bytesTransferred"]);
        assert_eq!(first["bytesTotal"], second["bytesTotal"]);
        assert_eq!(second["bytesTransferred"], 0);
        assert_eq!(first["sourceDigest"], second["destinationDigest"]);
        assert!(first["elapsedMs"].as_u64().unwrap() > 0);
        assert!(first["currentThroughputBps"].as_u64().unwrap() > 0);
        assert!(first["averageThroughputBps"].as_u64().unwrap() > 0);
        assert_eq!(second["retryCount"], 0);
        assert!(activity
            .iter()
            .any(|event| event.event == "step.progressed"));
    }

    #[test]
    fn transfer_resumes_only_from_a_matching_partial_destination() {
        let directory = tempdir().unwrap();
        let source = directory.path().join("source");
        let destination = directory.path().join("destination");
        let contents = (0..512 * 1024)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        let resumed_bytes = 111_111;
        fs::write(&source, &contents).unwrap();
        fs::write(&destination, &contents[..resumed_bytes]).unwrap();

        let provider = Provider::new(transfer_manifest(), FilesystemTransfer, vec![]);
        let observation = provider
            .execute(&json!({"sourcePath": source, "destinationPath": destination}))
            .unwrap();

        assert_eq!(observation["resumeCount"], 1);
        assert_eq!(
            observation["bytesTransferred"],
            (contents.len() - resumed_bytes) as u64
        );
        assert_eq!(fs::read(destination).unwrap(), contents);

        let invalid_source = directory.path().join("invalid-source");
        let invalid_destination = directory.path().join("invalid-destination");
        fs::write(&invalid_source, &contents).unwrap();
        fs::write(&invalid_destination, vec![b'z'; resumed_bytes]).unwrap();
        let observation = provider
            .execute(&json!({
                "sourcePath": invalid_source,
                "destinationPath": invalid_destination
            }))
            .unwrap();
        assert_eq!(observation["resumeCount"], 0);
        assert_eq!(fs::read(invalid_destination).unwrap(), contents);
    }

    #[test]
    fn transfer_reconciliation_only_allows_missing_or_matching_prefix_destinations() {
        let directory = tempdir().unwrap();
        let source = directory.path().join("source");
        let destination = directory.path().join("destination");
        let contents = b"verified transfer contents";
        fs::write(&source, contents).unwrap();
        let provider = Provider::new(transfer_manifest(), FilesystemTransfer, vec![]);
        let input = json!({"sourcePath": source, "destinationPath": destination});

        assert_eq!(
            provider.reconcile(&input).unwrap(),
            Reconciliation::RetrySafe
        );
        fs::write(&destination, &contents[..8]).unwrap();
        assert_eq!(
            provider.reconcile(&input).unwrap(),
            Reconciliation::RetrySafe
        );
        fs::write(&destination, contents).unwrap();
        assert_eq!(
            provider.reconcile(&input).unwrap(),
            Reconciliation::RetrySafe
        );
        fs::write(&destination, b"modified prefix").unwrap();
        assert_eq!(provider.reconcile(&input).unwrap(), Reconciliation::Unsafe);
    }

    #[test]
    fn interrupted_transfer_io_is_counted_as_a_retry() {
        struct InterruptedReader {
            first_read: bool,
        }

        impl std::io::Read for InterruptedReader {
            fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
                if self.first_read {
                    self.first_read = false;
                    return Err(std::io::ErrorKind::Interrupted.into());
                }
                buffer[0] = b'x';
                Ok(1)
            }
        }

        struct InterruptedWriter {
            first_write: bool,
            written: Vec<u8>,
        }

        impl std::io::Write for InterruptedWriter {
            fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
                if self.first_write {
                    self.first_write = false;
                    return Err(std::io::ErrorKind::Interrupted.into());
                }
                self.written.extend_from_slice(buffer);
                Ok(buffer.len())
            }

            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }

        let mut retries = 0;
        let mut reader = InterruptedReader { first_read: true };
        let mut buffer = [0];
        assert_eq!(
            read_with_retry(&mut reader, &mut buffer, &mut retries).unwrap(),
            1
        );

        let mut writer = InterruptedWriter {
            first_write: true,
            written: Vec::new(),
        };
        write_all_with_retry(&mut writer, &buffer, &mut retries).unwrap();
        assert_eq!(writer.written, b"x");
        assert_eq!(retries, 2);
    }

    struct Backend(AtomicUsize);

    impl ProviderBackend for Backend {
        fn ready(&self) -> Result<(), CapabilityError> {
            Ok(())
        }
        fn execute(&self, _input: &Value) -> Result<Value, CapabilityError> {
            self.0.fetch_add(1, Ordering::SeqCst);
            Ok(
                json!({"outputDigest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}),
            )
        }
    }

    #[test]
    fn conformance_checks_do_not_invoke_provider_effects() {
        let backend = Backend(AtomicUsize::new(0));
        let provider = Provider::new(package_manifest(), backend, vec![]);
        assert_conforms(&provider).unwrap();
        assert_eq!(provider.backend.0.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn readiness_probes_are_specific_to_each_windows_backend() {
        assert_eq!(WINGET_PROBE, &["--version"]);
        assert_eq!(DISM_PROBE, &["/English", "/?"]);
        assert!(POWERSHELL_PROBE.contains(&&"$PSVersionTable.PSVersion.Major"));
        assert!(HYPERV_PROBE
            .iter()
            .any(|argument| argument.contains("Get-Command Start-VM")));
        assert!(HYPERV_PROBE
            .iter()
            .any(|argument| argument.contains("Checkpoint-VM")));
    }

    #[test]
    fn command_observation_digest_tracks_normalized_observed_output() {
        let first = observed_output_digest(Some(0), b"completed\r\n", b"");
        let same_normalized_output = observed_output_digest(Some(0), b"completed\n", b"");
        let different_output = observed_output_digest(Some(0), b"no change\n", b"");
        assert_eq!(first, same_normalized_output);
        assert_ne!(first, different_output);
    }

    struct PreparationBackend {
        result: TransferHostPreparationResult,
        requests: std::sync::Mutex<Vec<TransferHostPreparationRequest>>,
    }

    impl TransferHostPreparationBackend for PreparationBackend {
        fn available(&self) -> Result<(), CapabilityError> {
            Ok(())
        }

        fn prepare(
            &self,
            request: &TransferHostPreparationRequest,
            remediation: Option<&str>,
        ) -> Result<TransferHostPreparationResult, CapabilityError> {
            self.requests.lock().unwrap().push(request.clone());
            let mut result = self.result.clone();
            result.remediation = remediation.map(Into::into);
            Ok(result)
        }
    }

    fn preparation_result(
        ready: bool,
        failure_category: Option<&'static str>,
    ) -> TransferHostPreparationResult {
        TransferHostPreparationResult {
            target_host: "target".into(),
            account: Some("TRANSFER$".into()),
            domain_controller: Some("dc.example.test".into()),
            ready,
            failure_category,
            remediation: None,
            diagnostics: vec!["gmsa_ready", "system_kerberos_refreshed"],
        }
    }

    #[test]
    fn preparation_reports_missing_ad_tooling_without_marking_the_target_ready() {
        let backend = PreparationBackend {
            result: preparation_result(false, Some("ad_tooling_missing")),
            requests: std::sync::Mutex::new(vec![]),
        };
        let provider = TransferHostPreparation::new(backend);

        let observation = provider
            .execute(&json!({"targetHost": "target", "account": "TRANSFER$"}))
            .unwrap();

        assert_eq!(observation["ready"], false);
        assert_eq!(observation["failureCategory"], "ad_tooling_missing");
        assert!(observation.get("rawOutput").is_none());
    }

    #[test]
    fn preparation_preserves_distinct_domain_and_authorization_failures() {
        for category in ["domain_connectivity_failed", "gmsa_authorization_denied"] {
            let backend = PreparationBackend {
                result: preparation_result(false, Some(category)),
                requests: std::sync::Mutex::new(vec![]),
            };
            let provider = TransferHostPreparation::new(backend);
            let observation = provider.execute(&json!({"targetHost": "target"})).unwrap();
            assert_eq!(observation["ready"], false);
            assert_eq!(observation["failureCategory"], category);
        }
    }

    #[test]
    fn preparation_runs_only_the_authorized_prerequisites_and_can_retry() {
        let backend = PreparationBackend {
            result: preparation_result(true, None),
            requests: std::sync::Mutex::new(vec![]),
        };
        let provider = TransferHostPreparation::new(backend);
        let input = json!({
            "targetHost": "target",
            "account": "TRANSFER$",
            "requireBits": true,
            "transferKeyPaths": ["C:\\ProgramData\\Pedantic\\transfer.key"],
            "requiredDirectories": ["C:\\ProgramData\\Pedantic"],
            "remediation": "transfer.host.retry/v1"
        });

        let first = provider.execute(&input).unwrap();
        let second = provider.execute(&input).unwrap();
        assert_eq!(first["ready"], true);
        assert_eq!(second["ready"], true);
        assert_eq!(first["remediation"], "transfer.host.retry/v1");
        let requests = provider.backend.requests.lock().unwrap();
        assert_eq!(requests.len(), 2);
        assert!(!requests[0].require_openssh);
        assert!(requests[0].require_bits);
        assert!(!requests[0].require_transfer_keys);
        assert_eq!(
            requests[0].transfer_key_paths,
            vec!["C:\\ProgramData\\Pedantic\\transfer.key"]
        );
        assert_eq!(
            requests[0].required_directories,
            vec!["C:\\ProgramData\\Pedantic"]
        );
    }

    #[test]
    fn preparation_contract_requires_a_target_and_preserves_redacted_diagnostics() {
        let backend = PreparationBackend {
            result: preparation_result(true, None),
            requests: std::sync::Mutex::new(vec![]),
        };
        let provider = TransferHostPreparation::new(backend);
        assert!(matches!(
            provider.execute(&json!({"requireBits": true})),
            Err(CapabilityError::InvalidInput(_))
        ));

        let observation = provider
            .execute(&json!({"targetHost": "target", "requireTransferKeys": true}))
            .unwrap();
        assert_eq!(observation["diagnostics"][0], "gmsa_ready");
        assert!(observation.as_object().unwrap().keys().all(|key| {
            !key.to_ascii_lowercase().contains("credential")
                && !key.to_ascii_lowercase().contains("output")
        }));
    }
}
