@{
  RootModule = 'StateSmith.DSC.psm1'
  ModuleVersion = '0.9.0'
  GUID = '2b6a3c27-1a4a-4d3f-9c9f-9b8b7d9d1234'
  Author = 'StateSmith Project'
  CompanyName = 'StateSmith'
  Copyright = '(c) StateSmith. All rights reserved.'
  Description = 'StateSmith DSC Helper Module. Provides user-friendly DSC v3 operations with parameter autocomplete support and automatic remote execution.'
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
  # Standalone StateSmith module; no legacy nested modules
  NestedModules = @()
  PrivateData = @{ PSData = @{ Tags = @('DSC','StateSmith','DesiredStateConfiguration','Automation') } }
}
