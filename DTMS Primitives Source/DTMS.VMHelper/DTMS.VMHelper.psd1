@{
    RootModule = 'DTMS.VMHelper.psm1'
    ModuleVersion = '3.3.0'
    GUID = 'b25312ab-e213-40d3-ae4f-94d049fae79a'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Runtime-adaptive Hyper-V host discovery, identity-preserving VM move staging, remote transfer, and configuration synchronization for PowerShell 7 and Windows PowerShell 5.1.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Copy-RemoteItem'
        'Copy-VMResource'
        'Find-VMHost'
        'Get-VMHelperRegistryConfiguration'
        'Get-VMHelperRuntime'
        'Get-VMResourceTransfer'
        'Get-VMResourceTransferFederated'
        'Get-VMResourceTransferHistory'
        'Get-VMResourceTransferPerformanceReport'
        'Initialize-VMResourceTransferRegistry'
        'Initialize-VMResourceTransferFederation'
        'Move-VMToHost'
        'Sync-VMResourceTransferRegistry'
        'Sync-VMResourceTransferFederation'
        'Sync-VMConfiguration'
        'Watch-VMResourceTransfer'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        DTMSRuntime = @{
            PreferredPSEdition = 'Core'
            PreferredPowerShellVersion = '7.0'
            MinimumPowerShellVersion = '5.1'
        }
        PSData = @{
            Tags = @('Hyper-V', 'VirtualMachine', 'Migration', 'PowerShell7', 'Remoting')
            ReleaseNotes = @'
3.3.0
- Added immediate adaptive activity feedback for discovery, transfer, synchronization, monitoring, and registry operations.
- Added explicit VM-to-Hyper-V-host mappings for benchmark orchestration.

3.2.0
- Added non-DFS federated pull collectors with independent utility-server indexes.
- Added gMSA scheduled collection, 90-record retention, fan-out, and deduplication.
- Added federated history and performance-report query modes.

3.1.1
- Added utility-server administrator preflight and optional provisioning credentials.
- Rejects regular expressions passed to the literal UtilityServer parameter.

3.1.0
- Added BITS as a durable VM disk transfer mechanism.
- Added normalized byte, throughput, percent, and ETA telemetry.
- Added transfer history, near-real-time watch, and performance report commands.

3.0.0
- Renamed the module and folder to DTMS.VMHelper for consistent utility naming.
- Public command names remain unchanged.

2.7.1
- Moved VMHelper under src/Utilities for unified utility-module loading.

2.7.0
- Delegated DFS publication, retention, and provisioning to DTMS.Runway.Dfs.
- Added Robocopy, SCP, and Auto durable disk transport selection through DTMS.Transfer.
- Durable workers now package shared provider modules with the VM operation.

2.6.0
- Module import now performs read-only readiness notification by default.
- Added Quiet, Prompt, and explicitly requested Initialize startup modes.

2.5.0
- Added an append-only DFS-R transfer event registry with local outbox retry.
- Added environment and replicated .env configuration plus one-time setup.
- Added global transfer discovery and newest-90 terminal record retention.

2.4.0
- Cross-host disk copies now run durably on the target host.
- Added direct restartable, unbuffered SMB transfer with Robocopy.
- Added domain credential and gMSA execution plus Get-VMResourceTransfer status.
- Added phase checkpoints, persistent rollback baselines, verification, and retry history.
- Get-VMResourceTransfer now lists transfers with filters and copy progress.

2.3.0
- Added selective same-host and cross-host resource copying with Copy-VMResource.
- Supports HardDrives and MacAddress without changing other VM configuration.
- Leaves the source stopped and restores the target's original running state.

2.2.1
- Added AD-backed wildcard expansion for Find-VMHost -ComputerName.
- Literal host names still bypass Active Directory and can be mixed with wildcard patterns.

2.2.0
- Integrated parallel Hyper-V host discovery as Find-VMHost.
- Added explicit-host and intelligent Active Directory discovery modes.
- Added bounded cross-version parallelism, query timeouts, and structured diagnostics.

2.1.2
- Renamed private remoting lifecycle helpers to Open-RemoteSession and Close-RemoteSession.

2.1.1
- Renamed the generic remote-item relay command to Copy-RemoteItem.

2.1.0
- Detects PowerShell 7 or Windows PowerShell 5.1 at module load.
- Exposes Get-VMHelperRuntime for runtime diagnostics.
- Uses the same supported public operations in both runtime modes.

2.0.0
- Replaced incomplete pseudocode with tested production commands.
- Added identity-preserving export, relay, and register workflow.
- Added selected configuration synchronization.
- Added PowerShell 7-first and Windows PowerShell 5.1-compatible support.
'@
        }
    }
}
