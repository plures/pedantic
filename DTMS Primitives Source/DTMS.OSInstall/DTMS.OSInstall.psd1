@{
    RootModule = 'DTMS.OSInstall.psm1'
    ModuleVersion = '1.0.0'
    GUID = '1bd29ce7-81f8-4712-8541-f3f98de6431e'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Declarative Windows Server compatibility scan, in-place upgrade, and guarded clean-install workflows over DTMS.Forge and DTMS.Runway.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-WindowsServerInstall'
        'New-WindowsServerInstallPlan'
        'Start-WindowsServerInstall'
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
            Tags = @('DTMS', 'WindowsServer', 'Setup', 'Upgrade', 'Forge')
            ReleaseNotes = '1.0.0 - Rebuilt as a Forge plan provider with Runway state and guarded clean installation.'
        }
    }
}
