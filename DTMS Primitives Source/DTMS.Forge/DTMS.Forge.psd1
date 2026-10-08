@{
    RootModule = 'DTMS.Forge.psm1'
    ModuleVersion = '2.0.0'
    GUID = '4f54fc95-d972-4c5a-a584-9158329b20d8'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Declarative DAG workflow authoring and caller-context preparation over DTMS.Runway durable execution.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Invoke-ForgeWorkflow'
        'New-ForgeCopyStep'
        'New-ForgePlan'
        'New-ForgeStep'
        'Start-ForgePlan'
        'Test-ForgePlan'
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
            Tags = @('PowerShell', 'ScheduledTask', 'Orchestration', 'LongRunning', 'Windows')
            ReleaseNotes = '2.0.0 - Clean Runway-backed DAG authoring API with direct, remote-controller, and SSH-tunnel launch modes.'
        }
    }
}
