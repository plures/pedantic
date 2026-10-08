@{
    RootModule = 'DTMS.Runway.psm1'
    ModuleVersion = '2.0.0'
    GUID = '861c7c71-bd70-4e37-b06b-34c6221461ac'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Shared durable-operation execution, state, readiness, progress, and scheduled-worker infrastructure.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Add-DurableOperationEvent'
        'Complete-DTMSActivity'
        'Get-DurableOperation'
        'Get-DurableOperationReadiness'
        'Initialize-DurableOperationEnvironment'
        'New-DurableOperation'
        'New-DurableOperationDefinition'
        'New-DurableOperationReadinessResult'
        'Request-DurableOperationReboot'
        'Set-DurableOperationPhase'
        'Start-DurableOperation'
        'Start-DTMSActivity'
        'Suspend-DurableOperation'
        'Update-DTMSActivity'
        'Write-DurableOperationProgress'
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
            Tags = @('DurableOperations', 'ScheduledTasks', 'PowerShell7', 'WindowsPowerShell')
            ReleaseNotes = @'
2.0.0 - Added configuration-driven gMSA execution, generic suspension, reboot continuation, and recurring resume triggers.
1.1.0 - Added adaptive immediate activity announcements, animated progress, heartbeats, and completion feedback.
1.0.0 - Initial durable-operation engine and readiness contract.
'@
        }
    }
}
