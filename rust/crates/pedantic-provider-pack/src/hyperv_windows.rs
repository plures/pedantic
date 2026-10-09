use crate::hyperv_resource_transfer::{
    HyperVCopyFailure, HyperVCopyObservation, HyperVMacConfiguration, HyperVMacObservation,
    HyperVPreflightObservation, HyperVResource, HyperVResourceTransferBackend,
    HyperVResourceTransferRequest, HyperVRollbackObservation, HyperVVerificationObservation,
};
use pedantic_capability::CapabilityError;
use serde::Serialize;
#[cfg(windows)]
use serde::de::DeserializeOwned;
#[cfg(windows)]
use serde_json::{Value, json};
#[cfg(windows)]
use std::fs::{File, OpenOptions};
#[cfg(windows)]
use std::io::{self, Write};
#[cfg(windows)]
use std::path::Path;
#[cfg(windows)]
use std::process::{Command, Stdio};

const PREFLIGHT_SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
$diagnostics = @()
$ready = $true
try {
    Import-Module Hyper-V -ErrorAction Stop
    Get-VM -Name $request.destinationVmName -ErrorAction Stop | Out-Null
} catch {
    $ready = $false
    $diagnostics += 'destination-vm-unavailable'
}
foreach ($resource in $request.resources) {
    if (-not (Test-Path -LiteralPath $resource.sourcePath -PathType Leaf)) {
        $ready = $false
        $diagnostics += 'source-resource-unavailable'
    }
    if (Test-Path -LiteralPath $resource.destinationPath) {
        $ready = $false
        $diagnostics += 'destination-resource-already-exists'
    }
    $parent = Split-Path -Parent $resource.destinationPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $ready = $false
        $diagnostics += 'destination-directory-unavailable'
    }
}
[pscustomobject]@{ ready = $ready; diagnostics = @($diagnostics) } | ConvertTo-Json -Compress
"#;

const CONFIGURE_MAC_SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
$vm = Get-VM -Name $request.destinationVmName -ErrorAction Stop
$adapters = @(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop | Where-Object { $_.Name -ceq $request.adapterName })
if ($adapters.Count -ne 1) { throw 'network adapter identity is not unique' }
$before = [string]$adapters[0].MacAddress
Set-VMNetworkAdapter -VMNetworkAdapter $adapters[0] -StaticMacAddress $request.effectiveMacAddress -ErrorAction Stop
$after = [string](Get-VMNetworkAdapter -VM $vm -ErrorAction Stop | Where-Object { $_.Name -ceq $request.adapterName }).MacAddress
[pscustomobject]@{ adapterName = $request.adapterName; beforeMacAddress = $before; afterMacAddress = $after } | ConvertTo-Json -Compress
"#;

#[cfg(windows)]
const VERIFY_SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
$diagnostics = @()
try {
    $vm = Get-VM -Name $request.destinationVmName -ErrorAction Stop
    $drives = @(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop)
    foreach ($resource in $request.resources) {
        $drive = $drives | Where-Object { $_.Path -ieq $resource.destinationPath } | Select-Object -First 1
        if ($null -eq $drive) {
            $diagnostics += 'resource-not-attached'
            continue
        }
        $chain = @()
        $vhd = Get-VHD -Path $drive.Path -ErrorAction Stop
        while ($vhd.VhdType -eq 'Differencing' -and $vhd.ParentPath) {
            $chain += $vhd.ParentPath
            $vhd = Get-VHD -Path $vhd.ParentPath -ErrorAction Stop
        }
        $expectedChain = @($resource.destinationDifferencingChain)
        if ($chain.Count -ne $expectedChain.Count) {
            $diagnostics += 'differencing-chain-mismatch'
        } else {
            for ($index = 0; $index -lt $chain.Count; $index++) {
                if ($chain[$index] -ine $expectedChain[$index]) {
                    $diagnostics += 'differencing-chain-mismatch'
                    break
                }
            }
        }
    }
    foreach ($configuration in $request.macConfigurations | Where-Object { $_.freezeDynamic }) {
        $adapter = Get-VMNetworkAdapter -VM $vm -ErrorAction Stop | Where-Object { $_.Name -ceq $configuration.adapterName } | Select-Object -First 1
        if ($null -eq $adapter -or $adapter.MacAddress -ine $configuration.effectiveMacAddress) {
            $diagnostics += 'network-adapter-mismatch'
        }
    }
} catch {
    $diagnostics += 'hyperv-verification-failed'
}
[pscustomobject]@{ verified = ($diagnostics.Count -eq 0); diagnostics = @($diagnostics) } | ConvertTo-Json -Compress
"#;

#[cfg(windows)]
const RESTORE_MAC_SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
$vm = Get-VM -Name $request.destinationVmName -ErrorAction Stop
foreach ($configuration in $request.changedMacConfigurations) {
    $adapters = @(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop | Where-Object { $_.Name -ceq $configuration.adapterName })
    if ($adapters.Count -ne 1) { throw 'network adapter identity is not unique' }
    Set-VMNetworkAdapter -VMNetworkAdapter $adapters[0] -StaticMacAddress $configuration.beforeMacAddress -ErrorAction Stop
}
'{"completed":true}'
"#;

#[derive(Default)]
pub struct WindowsHyperVResourceTransferBackend;

impl HyperVResourceTransferBackend for WindowsHyperVResourceTransferBackend {
    fn available(&self) -> Result<(), CapabilityError> {
        #[cfg(windows)]
        {
            return Command::new("powershell.exe")
                .args([
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    "Get-Command Get-VM, Get-VHD, Get-VMNetworkAdapter -ErrorAction Stop | Out-Null",
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map_err(|_| unavailable())?
                .success()
                .then_some(())
                .ok_or_else(unavailable);
        }
        #[cfg(not(windows))]
        {
            Err(unavailable())
        }
    }

    fn preflight(
        &self,
        request: &HyperVResourceTransferRequest,
    ) -> Result<HyperVPreflightObservation, CapabilityError> {
        powershell_json(PREFLIGHT_SCRIPT, request)
    }

    fn copy_resource(
        &self,
        resource: &HyperVResource,
    ) -> Result<HyperVCopyObservation, HyperVCopyFailure> {
        #[cfg(windows)]
        {
            let source = Path::new(&resource.source_path);
            let destination = Path::new(&resource.destination_path);
            let source_size = source.metadata().map_err(|_| copy_failure(false))?.len();
            let source_sha256 = digest_file(source).map_err(|_| copy_failure(false))?;
            let mut input = File::open(source).map_err(|_| copy_failure(false))?;
            let mut output = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(destination)
                .map_err(|_| copy_failure(false))?;
            let copied = io::copy(&mut input, &mut output).and_then(|_| output.flush());
            drop(output);
            let destination_size = destination
                .metadata()
                .map(|metadata| metadata.len())
                .unwrap_or(0);
            let destination_sha256 = digest_file(destination).unwrap_or_default();
            let current_source_sha256 = digest_file(source).unwrap_or_default();
            let complete = copied.is_ok()
                && destination_size == source_size
                && current_source_sha256 == source_sha256
                && destination_sha256 == source_sha256;
            Ok(HyperVCopyObservation {
                source_path: resource.source_path.clone(),
                destination_path: resource.destination_path.clone(),
                source_size,
                destination_size,
                source_sha256,
                destination_sha256,
                destination_created: true,
                complete,
            })
        }
        #[cfg(not(windows))]
        {
            let _ = resource;
            Err(copy_failure(false))
        }
    }

    fn configure_mac(
        &self,
        destination_vm_name: &str,
        configuration: &HyperVMacConfiguration,
    ) -> Result<HyperVMacObservation, CapabilityError> {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct ConfigureRequest<'a> {
            destination_vm_name: &'a str,
            adapter_name: &'a str,
            effective_mac_address: &'a str,
        }

        powershell_json(
            CONFIGURE_MAC_SCRIPT,
            &ConfigureRequest {
                destination_vm_name,
                adapter_name: &configuration.adapter_name,
                effective_mac_address: &configuration.effective_mac_address,
            },
        )
    }

    fn verify(
        &self,
        request: &HyperVResourceTransferRequest,
    ) -> Result<HyperVVerificationObservation, CapabilityError> {
        #[cfg(windows)]
        {
            let mut verification: HyperVVerificationObservation =
                powershell_json(VERIFY_SCRIPT, request)?;
            for resource in &request.resources {
                let expected_digest =
                    digest_file(Path::new(&resource.destination_path)).unwrap_or_default();
                let expected_size = Path::new(&resource.destination_path)
                    .metadata()
                    .map(|metadata| metadata.len())
                    .unwrap_or_default();
                if expected_size != resource.expected_size
                    || expected_digest != resource.expected_sha256
                {
                    verification.verified = false;
                    verification
                        .diagnostics
                        .push("resource-size-or-hash-mismatch".into());
                }
            }
            Ok(verification)
        }
        #[cfg(not(windows))]
        {
            let _ = request;
            Err(unavailable())
        }
    }

    fn rollback(
        &self,
        changes: &crate::hyperv_resource_transfer::HyperVAppliedChanges,
    ) -> Result<HyperVRollbackObservation, CapabilityError> {
        #[cfg(windows)]
        {
            let mut diagnostics = Vec::new();
            for destination in &changes.copied_destination_paths {
                match std::fs::remove_file(destination) {
                    Ok(()) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(_) => diagnostics.push("created-destination-could-not-be-removed".into()),
                }
            }
            if !changes.changed_mac_configurations.is_empty() {
                let request = json!({
                    "destinationVmName": changes.destination_vm_name,
                    "changedMacConfigurations": changes.changed_mac_configurations
                });
                if powershell_json::<_, Value>(RESTORE_MAC_SCRIPT, &request).is_err() {
                    diagnostics.push("network-adapter-mac-could-not-be-restored".into());
                }
            }
            let completed = diagnostics.is_empty();
            Ok(HyperVRollbackObservation {
                completed,
                recovery_action: if completed {
                    "none".into()
                } else {
                    "operator-review-required: inspect destination disks and restore adapter MAC addresses".into()
                },
                diagnostics,
            })
        }
        #[cfg(not(windows))]
        {
            let _ = changes;
            Err(unavailable())
        }
    }
}

#[cfg(windows)]
fn powershell_json<T: Serialize, R: DeserializeOwned>(
    script: &str,
    input: &T,
) -> Result<R, CapabilityError> {
    let mut child = Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| unavailable())?;
    let input = serde_json::to_vec(input)
        .map_err(|_| CapabilityError::InvalidInput("Hyper-V request is invalid".into()))?;
    child
        .stdin
        .take()
        .expect("PowerShell stdin was piped")
        .write_all(&input)
        .map_err(|_| unavailable())?;
    let output = child.wait_with_output().map_err(|_| unavailable())?;
    if !output.status.success() {
        return Err(unavailable());
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|_| CapabilityError::Execution("Hyper-V returned an invalid observation".into()))
}

#[cfg(not(windows))]
fn powershell_json<T, R>(_script: &str, _input: &T) -> Result<R, CapabilityError> {
    Err(unavailable())
}

#[cfg(windows)]
fn digest_file(path: &Path) -> Result<String, CapabilityError> {
    super::digest_file(path)
}

fn copy_failure(destination_created: bool) -> HyperVCopyFailure {
    HyperVCopyFailure {
        error: CapabilityError::Execution("transfer file could not be copied".into()),
        destination_created,
    }
}

fn unavailable() -> CapabilityError {
    CapabilityError::Execution("Windows Hyper-V transfer is unavailable".into())
}
