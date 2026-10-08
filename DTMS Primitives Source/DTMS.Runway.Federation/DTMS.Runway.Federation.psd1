@{
    RootModule = 'DTMS.Runway.Federation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'cde78829-372c-49a0-bf43-fb712ef20294'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'No-DFS federated pull indexes for target-local DTMS.Runway operation state.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-DurableOperationFederated'
        'Initialize-DurableOperationFederation'
        'Sync-DurableOperationFederation'
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
            Tags = @('DTMS', 'Runway', 'Federation', 'ScheduledTasks')
            ReleaseNotes = '1.0.0 - Added independent utility-server pull indexes for all Runway operations.'
        }
    }
}
