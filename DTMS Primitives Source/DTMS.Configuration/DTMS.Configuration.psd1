@{
    RootModule = 'DTMS.Configuration.psm1'
    ModuleVersion = '1.0.0'
    GUID = '6dd81309-305f-4e0d-9a57-2db004f7bf76'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'PowerShell 7-first organization, execution, federation, and controller-profile configuration with Windows PowerShell 5.1 compatibility.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-DTMSConfiguration'
        'Initialize-DTMSConfiguration'
        'Set-DTMSConfiguration'
        'Test-DTMSConfiguration'
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
            Tags = @('DTMS', 'Configuration', 'PowerShell7', 'WindowsPowerShell')
            ReleaseNotes = '1.0.0 - Added versioned central configuration with environment and per-operation overrides.'
        }
    }
}
