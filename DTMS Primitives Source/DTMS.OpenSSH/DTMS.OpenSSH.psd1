@{
  # Script module or binary module file associated with this manifest.
  RootModule = 'DTMS.OpenSSH.psm1'

  # Version number of this module.
  ModuleVersion = '3.0.0'

  # Supported PSEditions
  CompatiblePSEditions = @('Core', 'Desktop')

  # ID used to uniquely identify this module
  GUID = 'a1b2c3d4-e5f6-7890-a1b2-c3d4e5f67890'

  # Author of this module
  Author = 'SSH Utilities Module'

  # Company or vendor of this module
  CompanyName = 'Microsoft Corporation'

  # Copyright statement for this module
  Copyright = '(c) 2025. All rights reserved.'

  # Description of the functionality provided by this module
  Description = 'PowerShell 7-first module for SSH utilities and OpenSSH management on Windows, with Windows PowerShell 5.1 compatibility.'

  # Minimum version of the PowerShell engine required by this module
  PowerShellVersion = '5.1'

  # Name of the PowerShell host required by this module
  # PowerShellHostName = ''

  # Minimum version of the PowerShell host required by this module
  # PowerShellHostVersion = ''

  # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
  # DotNetFrameworkVersion = ''

  # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
  # ClrVersion = ''

  # Processor architecture (None, X86, Amd64) required by this module
  # ProcessorArchitecture = ''

  # Modules that must be imported into the global environment prior to importing this module
  # RequiredModules = @()

  # Assemblies that must be loaded prior to importing this module
  # RequiredAssemblies = @()

  # Script files (.ps1) that are run in the caller's environment prior to importing this module.
  #ScriptsToProcess = @()

  # Type files (.ps1xml) to be loaded when importing this module
  # TypesToProcess = @()

  # Format files (.ps1xml) to be loaded when importing this module
  # FormatsToProcess = @()

  # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
  # NestedModules = @()

  # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
  FunctionsToExport = @(
    'New-SSHConfig',
    'Set-AdminAuthKeys', 
    'Start-RDProxy',
    'Install-PoshSSHModule',
    'Start-DynamicProxy',
    'New-DTMSControllerSession',
    'Start-DTMSWinRMTunnel',
    'Set-KeyPassphrase',
    'Get-OpenSSHInstallationInfo',
    'Install-OpenSSHClient',
    'Install-OpenSSHServer', 
    'Uninstall-OpenSSHClient',
    'Uninstall-OpenSSHServer',
    'Install-OpenSSH',
    'Install-PsExecDependency',
    'Test-PsExecAvailability',
    'Install-ModuleDependencies',
    'Initialize-SSHTransferHost',
    'Get-SSHUtilitiesReadiness',
    'Start-SSHUtilitiesOperation'
  )

  # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
  CmdletsToExport = @()

  # Variables to export from this module
  VariablesToExport = @()

  # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
  AliasesToExport = @()

  # DSC resources to export from this module
  # DscResourcesToExport = @()

  # List of all modules packaged with this module
  # ModuleList = @()

  # List of all files packaged with this module
  # FileList = @()

  # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
  PrivateData = @{
    DTMSRuntime = @{
      PreferredPSEdition = 'Core'
      PreferredPowerShellVersion = '7.0'
      MinimumPowerShellVersion = '5.1'
    }
    PSData = @{
      # Tags applied to this module. These help with module discovery in online galleries.
      Tags = @('SSH', 'OpenSSH', 'Windows', 'Remote', 'Proxy', 'RDP', 'Tunneling', 'Authentication', 'Keys')

      # A URL to the license for this module.
      # LicenseUri = ''

      # A URL to the main website for this project.
      # ProjectUri = ''

      # A URL to an icon representing this module.
      # IconUri = ''

      # ReleaseNotes of this module
      ReleaseNotes = @'
Version 3.0.0
- Added centrally configured per-user SSH controller sessions and WinRM tunnels for Forge workstation orchestration.

Version 2.2.0
- Added immediate adaptive activity feedback for installation, dependency setup, durable operations, and transfer-host preparation.

Version 2.1.1
- Automatically uses the local OpenSSH Server capability CAB in C:\temp when present.

Version 2.1.0
- Added guarded remote OpenSSH, BITS, authorized-key, and worker private-key preparation.

Version 2.0.0
- Renamed the module and folder to DTMS.OpenSSH for consistent utility naming.
- Public command names remain unchanged.

Version 1.2.0
- Integrated DTMS.Runway readiness and durable scheduled operations.
- Integrated DTMS.Transfer provider readiness for Robocopy and SCP.

Version 1.1.0
- Added read-only readiness reporting for optional capabilities.
- Module import now notifies by default instead of automatically installing dependencies.
- Added Quiet, Prompt, and explicitly requested Initialize startup modes.

Version 1.0.0
- Initial release combining SSH utilities and OpenSSH installation functionality
- SSH configuration management with New-SSHConfig
- SSH key management and authentication with Set-AdminAuthKeys and Set-KeyPassphrase  
- SSH tunneling and proxy functionality with Start-RDProxy and Start-DynamicProxy
- OpenSSH client/server installation and management
- Posh-SSH module installation support
- Support for Windows environments including SAW
'@

      # Prerelease string of this module
      # Prerelease = ''

      # Flag to indicate whether the module requires explicit user acceptance for install/update/save
      # RequireLicenseAcceptance = $false

      # External dependent modules of this module
      # ExternalModuleDependencies = @()
    } # End of PSData hashtable
  } # End of PrivateData hashtable

  # HelpInfo URI of this module
  # HelpInfoURI = ''

  # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
  # DefaultCommandPrefix = ''
}