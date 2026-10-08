@{
    RootModule = 'DTMS.Runway.Dfs.psm1'
    ModuleVersion = '1.2.0'
    GUID = '70e274d9-425d-43fb-8205-a0502d73a8f1'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Optional DFS-R event registry, synchronization, reduction, retention, and provisioning for DTMS.Runway.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-DurableOperationRegistry'
        'Get-DurableOperationRegistryConfiguration'
        'Initialize-DurableOperationDfsRegistry'
        'Invoke-DurableOperationRegistryRetention'
        'Sync-DurableOperationRegistry'
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
            Tags = @('DFS', 'DFSR', 'DurableOperations', 'EventSourcing')
            ReleaseNotes = @'
1.2.0 - Added immediate adaptive activity feedback for synchronization, retention, and provisioning.
1.1.0 - Added all-server administrator preflight and optional provisioning credentials.
1.0.0 - Initial generic DFS-R event registry provider.
'@
        }
    }
}
