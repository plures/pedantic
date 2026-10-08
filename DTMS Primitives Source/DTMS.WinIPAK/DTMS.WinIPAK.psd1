@{
    RootModule = 'DTMS.WinIPAK.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a9718cb1-14d0-4f1f-bb49-505e06e742b8'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Reboot-safe WinIPAK validation cycles over DTMS.Forge and DTMS.Runway.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-WinIPAKOperation'
        'New-WinIPAKPlan'
        'Start-WinIPAKOperation'
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
            Tags = @('DTMS', 'WinIPAK', 'Reboot', 'Forge', 'Runway')
            ReleaseNotes = '1.0.0 - Rebuilt as a Forge plan provider using generic Runway suspension and reboot continuation.'
        }
    }
}
