@{
    RootModule = 'Pedantic.Ansible.Module.psm1'
    ModuleVersion = '1.0.0'
    GUID = '8a5f9c3e-1b2d-4e6f-9a8c-3d7e2f1b5a9c'
    Author = 'Pedantic Contributors'
    CompanyName = 'Plures'
    Copyright = '(c) 2024 Plures. All rights reserved.'
    Description = 'DSC v3 resource adapter for Ansible modules with Get/Test/Set semantics'
    PowerShellVersion = '7.0'

    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('DSC', 'Ansible', 'Configuration', 'Automation', 'CrossPlatform')
            LicenseUri = 'https://github.com/plures/pedantic/blob/main/LICENSE'
            ProjectUri = 'https://github.com/plures/pedantic'
            ReleaseNotes = @'
v1.0.0 - Initial release
- DSC v3 adapter for Ansible modules
- Support for Get/Test/Set operations
- Inventory and connection management
- Check mode and diff support
- Multiple idempotency modes
'@
        }
    }
}
