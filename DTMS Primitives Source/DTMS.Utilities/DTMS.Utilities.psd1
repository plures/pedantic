@{
    RootModule = 'DTMS.Utilities.psm1'
    ModuleVersion = '2.0.0'
    GUID = '63e53585-f59e-4c42-977e-bf905535e22c'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Single-command loader and readiness aggregator for DTMS PowerShell utility modules.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-DTMSUtilitiesModule'
        'Get-DTMSUtilitiesReadiness'
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
            Tags = @('DTMS', 'Utilities', 'ModuleLoader', 'Readiness')
            ReleaseNotes = @'
2.0.0
- Added central configuration, Forge DAG authoring, generic Runway federation, OSInstall, and WinIPAK modules.
- Added OpenSSH remote-controller and WinRM-tunnel workstation transports.

1.1.0
- Updated all child module identities and folders to use the DTMS. prefix.

1.0.0
- Initial unified loader and readiness aggregation.
'@
        }
    }
}
