# SimpleDSC Module Manifest
# Provides simplified package management through custom DSC resources
# Part of the Pedantic project

@{
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Pedantic Project'
    CompanyName = 'Pedantic'
    Copyright = '(c) 2025 Pedantic Project. All rights reserved.'
    Description = 'Simplified package management DSC resources'
    
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    
    # Nested modules to load
    NestedModules = @(
        'Resources\SimpleDSC.PackageInstaller\SimpleDSC.PackageInstaller.psm1'
    )
    
    # DSC Resources to export
    DscResourcesToExport = @('SimpleDSC_PackageInstaller')
    
    # Functions to export (none for DSC resources)
    FunctionsToExport = @()
    
    # Cmdlets to export (none)
    CmdletsToExport = @()
    
    # Variables to export (none)
    VariablesToExport = @()
    
    # Aliases to export (none)
    AliasesToExport = @()
    
    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('DSC', 'PackageManagement', 'WinGet', 'Chocolatey', 'Automation')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = 'Initial release of SimpleDSC package management resources'
        }
    }
}
