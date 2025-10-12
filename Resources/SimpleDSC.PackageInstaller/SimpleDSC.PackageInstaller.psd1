# Custom DSC Resource: SimpleDSC.PackageInstaller
# A native DSC resource that provides simplified package management

@{
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'SimpleDSC Team'
    Description = 'Simplified package management DSC resource'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    
    # DSC Resource Information
    DscResourcesToExport = @('SimpleDSC_PackageInstaller')
    
    # Required for DSC Resource
    ModuleList = @()
    FileList = @(
        'SimpleDSC.PackageInstaller.psm1',
        'SimpleDSC.PackageInstaller.schema.mof'
    )
}
