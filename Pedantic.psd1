@{
  RootModule = 'Pedantic.psm1'
  ModuleVersion = '0.9.0'
  GUID = '2b6a3c27-1a4a-4d3f-9c9f-9b8b7d9d1234'
  Author = 'Pedantic Project'
  CompanyName = 'Pedantic'
  Copyright = '(c) Pedantic. All rights reserved.'
  Description = 'Pedantic DSC Helper Module. Provides user-friendly local DSC v3 operations with parameter autocomplete support. Requires DSC to be installed already; remote execution is not supported in this release.'
  PowerShellVersion = '7.2'
  CompatiblePSEditions = @('Core')
  # Export explicit public surface for performance and clarity
  FunctionsToExport = @(
    'Invoke-DscHelper',
    'Validate-DscConfiguration',
    'Set-DscConfiguration',
    'Test-DscConfiguration',
    'Export-DscConfiguration',
    'Get-DscInstallerCache',
    'Update-DscInstallerCache',
    'Remove-DscInstallerCache',
    'Get-DscInstallerPath',
    'Get-DscResourceCache',
    'Update-DscResourceCache',
    'Remove-DscResourceCache',
    'Install-DscResourceOffline',
    'Ensure-DscResourcesAvailable',
    'Get-Head',
    'Get-Tail',
    'New-SecureRemoteSession',
    'Repair-DscInstallation',
    'Get-DscResourcePath',
    'Get-MappedResourceInfo'
  )
  CmdletsToExport = @()
  VariablesToExport = '*'
  AliasesToExport = @('head','tail')
  # Pedantic module; no legacy nested modules
  NestedModules = @()
  PrivateData = @{ PSData = @{ Tags = @('DSC','Pedantic','DesiredStateConfiguration','Automation') } }
}
