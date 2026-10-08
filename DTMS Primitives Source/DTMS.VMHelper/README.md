# DTMS.VMHelper

VMHelper is located under `src\Utilities\DTMS.VMHelper` and can be imported
directly or through the sibling `DTMS.Utilities` umbrella module.

VMHelper is a runtime-adaptive module for controlled Hyper-V VM move staging
and selected configuration synchronization. Consumers can use either
PowerShell 7 or Windows PowerShell 5.1.

## Requirements

- Hyper-V PowerShell module on both hosts
- PowerShell remoting enabled on both hosts
- Administrative access to both hosts
- Local staging space on the management computer equal to the exported VM size
- Destination storage sized for the exported VM
- PowerShell 7 or Windows PowerShell 5.1 on the management computer

```powershell
Import-Module .\DTMS.VMHelper.psd1
```

Potentially blocking commands announce their intent immediately and use the
adaptive DTMS.Runway activity display. Set `DTMS_FEEDBACK_MODE` to `Adaptive`,
`Animated`, `Concise`, or `Quiet`; scheduled workers should use `Quiet`.

## Runtime detection

The module detects the importing process during module initialization:

- PowerShell 7 and newer use `PowerShell7` mode.
- Windows PowerShell 5.1 uses `WindowsPowerShell` compatibility mode.
- Versions older than 5.1 fail with an explicit unsupported-version error.

The public VM operations are identical in both modes. The implementation uses
syntax and remoting APIs supported by both engines. Remote Hyper-V commands run
inside the target Windows host's `Microsoft.PowerShell` endpoint, so callers do
not need to import the local Hyper-V module into a PowerShell 7 compatibility
session.

Inspect the active mode:

```powershell
Get-VMHelperRuntime
```

## Find a writable central transfer registry

Use `Test-VMTransferRegistryAccess.ps1` to discover the current domain's DFS
namespace roots and folder links and verify where the current identity can
create, write, and delete a transfer directory:

```powershell
.\Test-VMTransferRegistryAccess.ps1 -OnlyWritable |
    Format-Table Path,PathType,LatencyMilliseconds -AutoSize
```

Specify another domain when necessary:

```powershell
.\Test-VMTransferRegistryAccess.ps1 -Domain 'contoso.com'
```

If DFS discovery is unavailable from the current workstation, test known
candidate paths directly:

```powershell
.\Test-VMTransferRegistryAccess.ps1 `
    -Path '\\contoso.com\Operations\VMHelper','\\fileserver\VMHelper$'
```

The script writes a small random payload under a uniquely named temporary
directory and removes it before returning. Results distinguish reachability,
directory creation, file writing, deletion, access denial, missing paths, and
connectivity failures. It displays discovery status immediately and reports
overall and per-path progress during testing. Use `-Quiet` to suppress status
and progress without suppressing result objects or errors. Domain discovery
requires the Windows DFSN PowerShell module.

## Distributed DFS-R transfer registry

On import, VMHelper resolves registry settings in this order:

1. `VMHELPER_REGISTRY_*` process or machine environment variables.
2. The replicated `.env` file under the default namespace.
3. Defaults derived from the current AD DNS domain.

The default service path is:

```text
\\<domain>\Services\DTMS\VMM\Transfers
```

The replicated configuration file is:

```text
\\<domain>\Services\DTMS\VMM\Transfers\.env
```

If the namespace exists, imports use it automatically. Otherwise the default
`Notify` startup mode performs only read-only checks, warns that distributed
discovery is unavailable, and continues with target-local state. Imports never
change infrastructure unless setup is explicitly requested.

Use guided interactive setup:

```powershell
Import-Module .\DTMS.VMHelper.psd1 -ArgumentList 'Prompt'
```

The recommended centralized-discovery model does not require DFS permissions.
Configure independent pull indexes on every utility server:

```powershell
Initialize-VMResourceTransferFederation `
    -UtilityServerPattern '^(?:SN5|PHX23|PHX21)ISUTIL\d{2,3}$' `
    -TargetHostName 'BN1HV01','BN1CPSHV01' `
    -CollectorAccount 'USME\_is_dtms_util$' `
    -RetentionCount 90
```

Each utility server installs the same five-minute scheduled collector under
the gMSA, pulls every registered target host, retains all active transfers plus
the newest 90 terminal transfers, and stores an independent index under
`C:\ProgramData\DTMS\VMM\FederatedTransfers`. No SMB share, DFS namespace, or
DFS-R configuration is required. The gMSA must be usable on each utility
server and allowed to use PowerShell remoting to read target-host transfer
state.

The utility-server list is stored in the user environment as
`VMHELPER_FEDERATED_UTILITY_SERVERS`. Query all indexes and deduplicate by
transfer ID:

```powershell
Get-VMResourceTransferFederated
Get-VMResourceTransferHistory -UtilityServer PHX21ISUTIL01,PHX23ISUTIL01,SN5ISUTIL01
Get-VMResourceTransferPerformanceReport `
    -UtilityServer PHX21ISUTIL01,PHX23ISUTIL01,SN5ISUTIL01 `
    -Path .\federated-performance.csv
```

Start an immediate collection cycle with
`Sync-VMResourceTransferFederation`. Near-real-time monitoring continues to
query authoritative target hosts with `Watch-VMResourceTransfer`.

The older DFS-R registry remains available for environments with delegated
DFS administration. Use noninteractive DFS initialization only with complete,
explicit options:

```powershell
Import-Module .\DTMS.VMHelper.psd1 -ArgumentList @(
    'Initialize'
    @{
        UtilityServerPattern = '^(?:BN1|SN5|PHX23|PHX21)ISUTIL\d{2,3}$'
        WriterPrincipal = 'USME\VMHelper-Registry-Writers'
        ReaderPrincipal = 'USME\VMHelper-Registry-Readers'
    }
)
```

Use `Quiet` for scheduled workers, tests, or other hosts that intentionally
use only target-local state:

```powershell
Import-Module .\DTMS.VMHelper.psd1 -ArgumentList 'Quiet'
```

`VMHELPER_STARTUP_MODE` sets the same local policy when import arguments are
not practical. The older suppression setting remains supported:

```powershell
$env:VMHELPER_REGISTRY_NO_PROMPT = '1'
```

Initialize explicitly with utility-server names:

```powershell
Initialize-VMResourceTransferRegistry `
    -UtilityServer BN1ISUTIL01,SN5ISUTIL01,PHX21ISUTIL01,PHX23ISUTIL01 `
    -WriterPrincipal 'USME\VMHelper-Registry-Writers' `
    -ReaderPrincipal 'USME\VMHelper-Registry-Readers'
```

Or discover enabled AD computers with a bounded regular expression:

```powershell
Initialize-VMResourceTransferRegistry `
    -UtilityServerPattern '^(?:BN1|SN5|PHX23|PHX21)ISUTIL\d{2,3}$' `
    -WriterPrincipal 'USME\VMHelper-Registry-Writers' `
    -ReaderPrincipal 'USME\VMHelper-Registry-Readers'
```

Setup displays the selected hosts and requires high-impact confirmation. It
creates:

- `C:\ProgramData\DTMS\VMM\Transfers` on each utility server by default.
- The hidden `DTMSVMMTransfers$` SMB share.
- A multi-target DFS namespace folder.
- A fully connected `DTMS-VMM-Transfers` DFS-R group.
- DFS-R exclusions for temporary and partial files.
- The replicated `.env` file.

Inspect resolved settings:

```powershell
Get-VMHelperRegistryConfiguration
```

Supported settings are:

```dotenv
VMHELPER_REGISTRY_NAMESPACE=\\USME.GBL\Services\DTMS\VMM\Transfers
VMHELPER_REGISTRY_SERVERS=BN1ISUTIL01,SN5ISUTIL01,PHX21ISUTIL01,PHX23ISUTIL01
VMHELPER_REGISTRY_WRITER_PRINCIPAL=USME\VMHelper-Registry-Writers
VMHELPER_REGISTRY_READER_PRINCIPAL=USME\VMHelper-Registry-Readers
VMHELPER_REGISTRY_RETENTION_COUNT=90
VMHELPER_REGISTRY_SHARE_NAME=DTMSVMMTransfers$
VMHELPER_REGISTRY_LOCAL_PATH=C:\ProgramData\DTMS\VMM\Transfers
VMHELPER_REGISTRY_REPLICATION_GROUP=DTMS-VMM-Transfers
VMHELPER_REGISTRY_PROGRESS_PERCENT=5
VMHELPER_REGISTRY_PROGRESS_MINUTES=15
```

No credentials are stored in `.env`.

Each transfer owns a folder containing immutable JSON events. The worker
reserves sequence numbers in target-local state and publishes through the DFS
namespace. It does not pin a direct DFS target. Out-of-order replication is
safe because readers reduce events by sequence, and an observed
`TransferCompleted` event is authoritative even when earlier history has not
arrived.

Registry publication is never part of the VM transaction commit. Events are
first written to the target-local `RegistryOutbox`; failures produce warnings
and remain queued. Retry manually when needed:

```powershell
Sync-VMResourceTransferRegistry `
    -TransactionRoot 'C:\ProgramData\VMHelper\Transfers\<TransferId>'
```

Progress events are emitted at configured percentage or heartbeat intervals.
All active records are retained. Among terminal transfers, the newest 90 are
retained globally by default; older terminal folders are removed through DFS
so DFS-R propagates deletion.

With the registry available, no target host or saved launch result is needed:

```powershell
Get-VMResourceTransfer
Get-VMResourceTransfer -Active
Get-VMResourceTransfer -TargetVMName 'BN1USME*' -Latest
```

Use `-TargetHostName` to bypass the registry and query authoritative local
state on a specific Hyper-V host.

Example output includes the version, edition, process path, runtime mode, and
whether compatibility mode is active. Operation result objects also identify
the runtime mode used.

## Find a VM's Hyper-V host

`Find-VMHost` queries candidate hosts concurrently with a bounded runspace pool.
The same parallel implementation works in PowerShell 7 and Windows PowerShell
5.1.

For a known host list, Active Directory is bypassed:

```powershell
Find-VMHost -VMName 'SQL01' -ComputerName 'hv01','hv02','hv03'
```

Computer names accept wildcards. Wildcards are expanded in AD before remote
probing, which can substantially reduce the search space when VM and host
naming conventions share a location prefix:

```powershell
Find-VMHost -VMName 'BN1USMEPRXYXGW01' -ComputerName 'BN1*'
```

Literal names in a mixed list bypass AD; only wildcard entries are expanded:

```powershell
Find-VMHost -VMName 'BN1USMEPRXYXGW01' `
    -ComputerName 'known-hv01.contoso.com','BN1*'
```

For automatic discovery, omit `ComputerName`. No search base or candidate list
is required:

```powershell
Find-VMHost -VMName 'SQL01'
```

Automatic discovery uses a tiered strategy:

1. Select the user's current AD domain and default naming context.
2. Search recursively for enabled non-DC computers publishing the Hyper-V
   virtual-system migration SPN.
3. If no SPN candidates are found, enumerate enabled non-DC Windows Server
   objects and derive their distinct parent OUs.
4. Probe fallback candidates concurrently for DNS, remoting access, physical
   hardware, server role, and the Hyper-V management service.
5. Exclude virtualized servers by default, non-Hyper-V systems, domain
   controllers, unreachable systems, and systems the caller cannot access.

Search bases fail closed: one candidate returning `AccessDenied` or
`Authentication` eliminates every candidate in that parent OU. Otherwise
successful hosts from that OU are returned as `SearchBaseAccessDenied`
diagnostics rather than queried for VMs.

Narrow discovery to an OU or search for a wildcard VM name:

```powershell
Find-VMHost `
    -VMName 'web*' `
    -SearchBase 'OU=HyperV,OU=Servers,DC=contoso,DC=com'
```

Intelligent defaults include:

- Current AD domain naming context when `SearchBase` is omitted
- Hyper-V SPN filtering rather than querying every server
- Parallel throttle of four times the logical processor count, bounded 8–64
- 30-second remoting open and operation timeout per host
- Unique, case-insensitive host querying
- Structured match objects rather than formatted console output

Use `-IncludeAllWindowsServers` to skip the SPN shortcut and force the broader
parallel Windows Server probe. Use `-IncludeVirtualizedHosts` when nested
Hyper-V hosts are valid candidates.

Matches are returned by default. Add `-IncludeQueryErrors`, `-IncludeNotFound`,
or `-IncludeDiscoveryDiagnostics` for diagnostic records. Diagnostic results
distinguish:

- `NameResolution`
- `Connectivity`
- `Authentication`
- `AccessDenied`
- `SearchBaseAccessDenied`
- `DomainController`
- `VirtualizedServer`
- `NotHyperVHost`
- Other remote or probe infrastructure errors

PowerShell 7 first attempts to import the Active Directory module natively and
then uses Windows PowerShell compatibility when necessary. Windows PowerShell
5.1 imports the module directly. Explicit `ComputerName` searches do not
require the Active Directory module.

## Copy selected VM resources

`Copy-VMResource` copies only explicitly selected resource groups between two
existing VMs. It supports VMs on the same Hyper-V host or different hosts.

Copy hard drives and effective MAC addresses without copying other VM
configuration:

```powershell
$result = Copy-VMResource `
    -SourceVMName 'BN1USMEPRXYXGW01-Old' `
    -TargetVMName 'BN1USMEPRXYXGW01-New' `
    -SourceHostName 'BN1HV01.contoso.com' `
    -TargetHostName 'BN1HV02.contoso.com' `
    -Resource HardDrives,MacAddress `
    -TransferCredential (Get-Credential 'CONTOSO\vm-transfer') `
    -Confirm
```

The operation guarantees:

- The source VM is stopped and remains stopped.
- The target is stopped temporarily when necessary.
- A target that was running is started again afterward.
- Source disk attachments and source VHD files remain intact.
- Every VHD/VHDX differencing chain is copied and relinked at the destination.
- A target disk at the same controller location is detached and replaced.
- The detached target disk file is retained and never deleted.
- If target configuration rollback is required, copied destination disk files
  are retained for diagnosis and manual cleanup.
- Dynamic source MACs are frozen as static effective addresses.
- Target NICs are matched by name first, then ordinal position.
- No processor, memory, firmware, checkpoint, VLAN, switch, VM ID, or other
  configuration is copied.

Select only one resource group when appropriate:

```powershell
Copy-VMResource @commonParameters -Resource HardDrives
Copy-VMResource @commonParameters -Resource MacAddress
```

Copied disks default to a unique directory below the target VM's
`Virtual Hard Disks` directory. Override it with `DestinationVhdRoot`.

Cross-host hard-drive copies return immediately after starting a scheduled
task on the target Hyper-V host. The task runs independently of the launching
PowerShell or remoting session. It reads source disks directly over SMB and
uses the selected `DTMS.Transfer` provider rather than relaying disk contents
through the management computer.

Robocopy remains the compatibility-preserving default. BITS provides a
restartable SMB alternative, while SCP provides encryption when Windows
OpenSSH is configured on the source host:

```powershell
Copy-VMResource @parameters `
    -Resource HardDrives `
    -TransferCredential (Get-Credential 'CONTOSO\vm-transfer') `
    -TransferTransport Scp `
    -ScpSourceEndpoint 'vm-transfer@hv01.contoso.com' `
    -ScpIdentityFile 'C:\ProgramData\ssh\vm-transfer'

Copy-VMResource @parameters `
    -Resource HardDrives `
    -TransferAccount 'CONTOSO\vm-transfer$' `
    -TransferTransport Bits
```

`-TransferTransport Auto` prefers SCP when `ScpSourceEndpoint` is supplied and
SCP is available to the durable worker; otherwise it uses Robocopy. SCP is
encrypted but is not treated as restartable. Robocopy and BITS are restartable;
Robocopy additionally provides unbuffered I/O and Windows metadata preservation.
Shared `DTMS.Transfer` and `DTMS.Runway.Dfs` provider modules are packaged into
the transaction directory so an in-progress worker is insulated from later
module updates.

Use either a normal domain credential:

```powershell
$transfer = Copy-VMResource @parameters `
    -Resource HardDrives,MacAddress `
    -TransferCredential (Get-Credential 'CONTOSO\vm-transfer')
```

Or a gMSA:

```powershell
$transfer = Copy-VMResource @parameters `
    -Resource HardDrives,MacAddress `
    -TransferAccount 'CONTOSO\vm-transfer$'
```

The execution account needs Hyper-V administration rights on both hosts and
read access to every source VHD. Local source paths are accessed through the
source host's administrative shares, so the account normally needs local
administrator access on the source host. UNC-backed VHD paths are used as-is.

Reconnect later and read persisted status:

```powershell
Get-VMResourceTransfer -TargetHostName 'BN1HV02.contoso.com'
```

This single command lists every transfer newest-first, so retaining the
original `Copy-VMResource` return value is optional. Its compact properties
include status, current phase, provider, normalized byte progress, throughput,
ETA, task state, VM names, attempt count, and update time.

Common filters:

```powershell
# Queued and running transfers
Get-VMResourceTransfer -TargetHostName 'BN1HV02.contoso.com' -Active

# Newest transfer for a VM naming pattern
Get-VMResourceTransfer `
    -TargetHostName 'BN1HV02.contoso.com' `
    -TargetVMName 'BN1USME*' `
    -Latest

# Exact transfer with complete details
Get-VMResourceTransfer `
    -TargetHostName 'BN1HV02.contoso.com' `
    -TransferId '20261005-120000-...'
```

Every provider appends normalized samples to `TransferMetrics.jsonl`. Monitor
active work and generate comparative history reports with:

```powershell
Watch-VMResourceTransfer `
    -TargetHostName 'BN1HV02.contoso.com' `
    -TransferId $transfer.TransferId

Get-VMResourceTransferHistory -TargetHostName 'BN1HV02.contoso.com'

Get-VMResourceTransferPerformanceReport `
    -TargetHostName 'BN1HV02.contoso.com' `
    -Path .\transfer-performance.csv
```

State, transcript, result, provider logs, and normalized metrics are retained under
`C:\ProgramData\VMHelper\Transfers\<TransferId>` on the target host. The task
also has an at-startup trigger; a restarted task reuses the same transfer
directory and Robocopy resumes partial files.

The guarded `Invoke-BN1VMTransferBenchmark.ps1` scenario discovers the five
approved BN1/BN1CPS VM pairs, prepares OpenSSH and BITS when explicitly
requested, launches the two-Robocopy/two-SCP/one-BITS allocation, monitors it,
and persists JSON and CSV reports. Run it without action switches for a
read-only discovery plan, then use `-PrepareInfrastructure -StartTransfers
-Watch` after reviewing the discovered hosts.

VMs are never queried from Active Directory. AD discovery supplies candidate
Hyper-V computer accounts, which are then queried with `Get-VM`. When broad
host probing is unavailable or undesirable, supply an authoritative map:

```powershell
$vmHostMap = @{
    BN1USMEPRXYXGW1 = 'BN1HV01'
    BN1CPSUSMEPRXYXGW1 = 'BN1CPSHV01'
}

.\Invoke-BN1VMTransferBenchmark.ps1 `
    -VMHostMap $vmHostMap `
    -PrepareInfrastructure `
    -WhatIf
```

For repeatable runs, use `-VMHostMapPath` with JSON:

```json
{
  "BN1USMEPRXYXGW1": "BN1HV01",
  "BN1CPSUSMEPRXYXGW1": "BN1CPSHV01"
}
```

CSV files use `VMName,HostName` columns. When all ten VMs are mapped, the
benchmark skips AD candidate-host discovery entirely.

The durable operation is checkpointed as one recoverable workflow:

1. `Preflight`
2. `StoppingVMs`
3. `CapturingConfiguration`
4. `CopyingDisks`
5. `RelinkingDisks`
6. `ApplyingTargetConfiguration`
7. `Verifying`
8. `RestoringTargetState`
9. `Completed`

`Get-VMResourceTransfer` reports the current phase, attempt count, and complete
phase history. Before changing target attachments or MAC addresses, the worker
atomically writes `Rollback.json` with the original target configuration.
Every retry reuses this original baseline, even if the previous worker stopped
after partially changing the target. Operation failures enter `RollingBack`
and finish as `RolledBack` or `RollbackFailed` after power-state restoration.
Failures before target configuration mutation finish as `Failed`. Copied disk
files remain in place so restartable transfers do not discard completed work.

Use `-TurnOff` only when graceful shutdown cannot stop a VM. Immediate
power-off can cause guest data loss.

## Identity-preserving move staging

`Move-VMToHost` is for a staged move, not for creating two concurrently usable
VMs. It performs these operations:

1. Rejects destination VM name, VM ID, and path collisions.
2. Stops the source VM and leaves it stopped.
3. Freezes each effective network-adapter MAC address as static.
4. Exports the complete VM.
5. Relays the export through the management computer.
6. Registers the copied VM in place with `Import-VM -Register`.
7. Verifies the destination VM ID and MAC addresses.

Registration preserves the VM ID, configuration, disks, and MAC addresses.
Dynamic source MAC assignments are intentionally converted to static addresses
after shutdown so a destination host cannot allocate a different address. The
source remains off with the same static addresses. The destination VM remains
off. The command never removes the source registration or original source
files.

```powershell
$result = Move-VMToHost `
    -VMName 'SQL01' `
    -SourceHostName 'hv01.contoso.com' `
    -DestinationHostName 'hv02.contoso.com' `
    -SourceExportRoot 'D:\VMTransfer\Exports' `
    -DestinationRoot 'E:\VMs' `
    -LocalStagingRoot 'F:\VMRelay' `
    -Confirm
```

The normal stop operation is used by default. `-TurnOff` performs an immediate
power-off and can cause guest data loss. It should be used only when the normal
operation cannot stop the VM.

Generated source-export and local-relay artifacts are removed after the
operation. Use `-RetainTransferArtifacts` for troubleshooting. Destination
files, source registration, and original source files are always retained.

If an error occurs after the source is stopped, the exception explicitly
reports that the source remains stopped.

## Remote item relay

PowerShell does not support copying directly from one PSSession to another.
`Copy-RemoteItem` therefore relays through a unique local directory:

```powershell
Copy-RemoteItem `
    -SourceComputerName 'hv01.contoso.com' `
    -DestinationComputerName 'hv02.contoso.com' `
    -SourcePath 'D:\Exports\SQL01' `
    -DestinationPath 'E:\Imports' `
    -StagingPath 'F:\VMRelay'
```

Existing destination content is rejected unless `-Force` is supplied.

## Selected configuration synchronization

`Sync-VMConfiguration` updates an existing destination VM. It does not copy
disks, checkpoints, firmware generation, VM ID, or guest data.

Supported property groups:

- `Processor`
- `Memory`
- `AutomaticActions`
- `Checkpoint`
- `NetworkAdapters`

```powershell
Sync-VMConfiguration `
    -SourceVMName 'Template01' `
    -DestinationVMName 'Application01' `
    -SourceHostName 'hv01.contoso.com' `
    -DestinationHostName 'hv02.contoso.com' `
    -Property Processor, Memory, AutomaticActions
```

Network adapters are matched by name. Static/dynamic MAC configuration and
VLAN configuration are copied. Add `-IncludeSwitchConnection` to connect each
adapter to an identically named destination switch.

## Credentials

By default, remoting uses the current caller. Different credentials can be
provided independently:

```powershell
Move-VMToHost @moveParameters `
    -SourceCredential (Get-Credential 'CONTOSO\source-admin') `
    -DestinationCredential (Get-Credential 'CONTOSO\destination-admin')
```

Credentials are passed directly to `New-PSSession` and are not persisted.

All state-changing public commands support `-WhatIf` and `-Confirm`.
