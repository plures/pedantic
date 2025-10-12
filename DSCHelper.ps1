# DSC Helper - Improved version with better parameter validation and user guidance
<#
.SYNOPSIS
    Executes DSC v3 commands with improved parameter validation and user guidance.
.DESCRIPTION
    Provides a user-friendly interface to DSC v3 operations with validated parameters,
    helpful error messages, and support for both local and remote execution.
.PARAMETER DscPath
    Path to the DSC configuration YAML file.
.PARAMETER Operation
    The DSC operation to perform. Valid values: 'Set', 'Test', 'Validate', 'Export'.
.PARAMETER ParametersPath
    Optional path to parameters JSON/YAML file for the configuration.
.PARAMETER ComputerName
    Target computer name for remote execution. Defaults to local machine.
.PARAMETER ReturnInDesiredState
    When specified, returns only the InDesiredState property from the result.
.PARAMETER Quiet
    Suppresses verbose output during execution.
.PARAMETER WhatIf
    Shows what would happen without making changes (only applies to 'Set' operation).
.EXAMPLE
    .\DSCHelper.ps1 -DscPath "C:\Configs\WebServer.yaml" -Operation "Test"
.EXAMPLE
    .\DSCHelper.ps1 -DscPath "C:\Configs\Cluster.yaml" -Operation "Set" -ParametersPath "C:\Configs\params.json" -ComputerName "SERVER01"
.EXAMPLE
    .\DSCHelper.ps1 -DscPath "C:\Configs\Baseline.yaml" -Operation "Set" -WhatIf
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, HelpMessage = 'Path to the DSC configuration YAML file')]
  [ValidateNotNullOrEmpty()]
  [string]$DscPath,
    
  [Parameter(Mandatory = $true, HelpMessage = 'DSC operation to perform')]
  [ValidateSet('Set', 'Test', 'Validate', 'Export', HelpMessage = 'Valid operations: Set (apply config), Test (check compliance), Validate (validate config), Export (export current state)')]
  [string]$Operation,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Path to parameters JSON/YAML file')]
  [ValidateNotNullOrEmpty()]
  [string]$ParametersPath,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Target computer name for remote execution')]
  [ValidateNotNullOrEmpty()]
  [string]$ComputerName = $env:COMPUTERNAME,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Return only the InDesiredState property')]
  [switch]$ReturnInDesiredState,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Suppress verbose output')]
  [switch]$Quiet,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Show what would happen without making changes (Set operation only)')]
  [switch]$WhatIf
)

# Validate DSC executable availability
function Test-DscExecutable {
  if (-not (Get-Command 'dsc.exe' -ErrorAction SilentlyContinue)) {
    throw "DSC executable (dsc.exe) not found in PATH. Please ensure DSC v3 is installed and available."
  }
}

# Validate file paths
function Test-DscPaths {
  if (-not (Test-Path -Path $DscPath -PathType Leaf)) {
    throw "DSC configuration file not found: $DscPath"
  }
    
  if ($ParametersPath -and -not (Test-Path -Path $ParametersPath -PathType Leaf)) {
    throw "Parameters file not found: $ParametersPath"
  }
}

# Build DSC command arguments
function Build-DscArguments {
  $args = @('config', $Operation.ToLower())
    
  # Add file parameter
  $args += '--file'
  $args += $DscPath
    
  # Add parameters file if specified
  if ($ParametersPath) {
    $args += '--parametersFile'
    $args += $ParametersPath
  }
    
  # Add WhatIf flag for Set operation
  if ($WhatIf -and $Operation -eq 'Set') {
    $args += '--whatif'
  }
    
  # Add output format for structured results
  $args += '--output-format'
  $args += 'json'
    
  return $args
}

# Execute DSC command
function Invoke-DscCommand {
  param([string[]]$Arguments, [string]$TargetComputer)
    
  $cmdLine = "dsc $($Arguments -join ' ')"
    
  if (-not $Quiet) {
    Write-Host "Executing: $cmdLine" -ForegroundColor Cyan
  }
    
  try {
    $output = & dsc @Arguments 2>&1
    $exitCode = $LASTEXITCODE
        
    if (-not $Quiet) {
      Write-Host "Exit Code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { 'Green' } else { 'Red' })
    }
        
    return @{
      ExitCode    = $exitCode
      Output      = $output
      CommandLine = $cmdLine
    }
  } catch {
    throw "Failed to execute DSC command: $($_.Exception.Message)"
  }
}

# Main execution logic
try {
  # Pre-flight checks
  Test-DscExecutable
  Test-DscPaths
    
  # Build arguments
  $dscArgs = Build-DscArguments
    
  if ($ComputerName -ne $env:COMPUTERNAME) {
    # Remote execution
    if (-not $Quiet) {
      Write-Host "Executing DSC command remotely on: $ComputerName" -ForegroundColor Yellow
    }
        
    $session = New-PSSession -ComputerName $ComputerName -ErrorAction Stop
    try {
      # Copy DSC file to remote machine
      $dscFile = Split-Path -Path $DscPath -Leaf
      $dscRemote = Join-Path $env:TEMP $dscFile
      Copy-Item -Path $DscPath -Destination $dscRemote -ToSession $session -Force
            
      # Copy parameters file if specified
      if ($ParametersPath) {
        $paramsFile = Split-Path -Path $ParametersPath -Leaf
        $paramsRemote = Join-Path $env:TEMP $paramsFile
        Copy-Item -Path $ParametersPath -Destination $paramsRemote -ToSession $session -Force
                
        # Update arguments to use remote paths
        $dscArgs = $dscArgs | ForEach-Object {
          if ($_ -eq $DscPath) { $dscRemote }
          elseif ($_ -eq $ParametersPath) { $paramsRemote }
          else { $_ }
        }
      } else {
        # Update file path in arguments
        $dscArgs = $dscArgs | ForEach-Object {
          if ($_ -eq $DscPath) { $dscRemote }
          else { $_ }
        }
      }
            
      # Execute on remote machine
      $jsonString = Invoke-Command -Session $session -ArgumentList $dscArgs -ScriptBlock {
        param($Arguments)
        $result = Invoke-DscCommand -Arguments $Arguments -TargetComputer $env:COMPUTERNAME
        if ($result.ExitCode -eq 0) {
          $result.Output
        } else {
          throw "DSC command failed with exit code $($result.ExitCode): $($result.Output)"
        }
      }
            
      $result = $jsonString | ConvertFrom-Json
    } finally {
      Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
  } else {
    # Local execution
    $dscResult = Invoke-DscCommand -Arguments $dscArgs -TargetComputer $env:COMPUTERNAME
        
    if ($dscResult.ExitCode -eq 0) {
      $result = $dscResult.Output | ConvertFrom-Json
    } else {
      throw "DSC command failed with exit code $($dscResult.ExitCode): $($dscResult.Output)"
    }
  }
    
  # Handle ReturnInDesiredState parameter
  if ($ReturnInDesiredState) {
    if ($null -ne $result.inDesiredState) { 
      return $result.inDesiredState 
    } elseif ($null -ne $result.InDesiredState) { 
      return $result.InDesiredState 
    } else {
      Write-Warning "InDesiredState property not found in DSC result"
      return $null
    }
  }
    
  return $result
} catch {
  Write-Error "DSC Helper failed: $($_.Exception.Message)"
  throw
}
