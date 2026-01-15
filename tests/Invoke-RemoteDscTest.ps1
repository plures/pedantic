# Remote DSC Test with Autocomplete Support
<#
.SYNOPSIS
    Executes DSC tests on remote computers with full autocomplete support.
.DESCRIPTION
  This script demonstrates how to use the StateSmith.DSC module on remote computers
    with full parameter autocomplete support. It copies the module to the remote
    machine and executes DSC operations there.
.PARAMETER ComputerName
    Target computer name for remote execution.
.PARAMETER DscPath
    Path to the DSC configuration YAML file (local path).
.PARAMETER ParametersPath
    Optional path to parameters JSON/YAML file (local path).
.PARAMETER Operation
    DSC operation to perform: Test, Set, Validate, or Export.
.PARAMETER Credential
    Credential for remote connection.
.EXAMPLE
    .\Invoke-RemoteDscTest.ps1 -ComputerName "SERVER01" -DscPath "C:\Configs\WebServer.yaml" -Operation "Test"
.EXAMPLE
    .\Invoke-RemoteDscTest.ps1 -ComputerName "SERVER01" -DscPath "C:\Configs\Cluster.yaml" -Operation "Set" -WhatIf
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, HelpMessage = 'Target computer name')]
  [string]$ComputerName,
    
  [Parameter(Mandatory = $true, HelpMessage = 'Path to DSC configuration file (local)')]
  [string]$DscPath,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Path to parameters file (local)')]
  [string]$ParametersPath,
    
  [Parameter(Mandatory = $true, HelpMessage = 'DSC operation to perform')]
  [ValidateSet('Set', 'Test', 'Validate', 'Export')]
  [string]$Operation,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Credential for remote connection')]
  [PSCredential]$Credential,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Show what-if scenario')]
  [switch]$WhatIf
)

Write-Host "=== Remote DSC Test with Autocomplete ===" -ForegroundColor Green
Write-Host "Target: $ComputerName" -ForegroundColor Yellow
Write-Host "Operation: $Operation" -ForegroundColor Yellow
Write-Host "DSC Path: $DscPath" -ForegroundColor Yellow
if ($ParametersPath) { Write-Host "Parameters: $ParametersPath" -ForegroundColor Yellow }
if ($WhatIf) { Write-Host "WhatIf: Enabled" -ForegroundColor Yellow }
Write-Host ""

# Validate local files exist
if (-not (Test-Path $DscPath)) {
  throw "DSC configuration file not found: $DscPath"
}
if ($ParametersPath -and -not (Test-Path $ParametersPath)) {
  throw "Parameters file not found: $ParametersPath"
}

# Get module path (prefer StateSmith meta-module)
$modulePath = Join-Path $PSScriptRoot "StateSmith.DSC.psm1"
if (-not (Test-Path $modulePath)) {
  throw "Module file not found: $modulePath"
}

try {
  # Create remote session
  $sessionParams = @{ ComputerName = $ComputerName }
  if ($Credential) { $sessionParams.Credential = $Credential }
    
  $session = New-PSSession @sessionParams -ErrorAction Stop
  Write-Host "✓ Connected to $ComputerName" -ForegroundColor Green
    
  # Copy files to remote machine
  Write-Host "Copying files to remote machine..." -ForegroundColor Cyan
    
  # Create remote directory for module
  $remoteModuleDir = "C:\Temp\StateSmith.DSC"
  Invoke-Command -Session $session -ScriptBlock {
    New-Item -Path $using:remoteModuleDir -ItemType Directory -Force | Out-Null
  }
    
  # Copy module to remote machine
  Copy-Item -Path $modulePath -Destination "$remoteModuleDir\StateSmith.DSC.psm1" -ToSession $session -Force
    
  # Copy DSC configuration file
  $dscFileName = Split-Path $DscPath -Leaf
  $remoteDscPath = "C:\Temp\$dscFileName"
  Copy-Item -Path $DscPath -Destination $remoteDscPath -ToSession $session -Force
    
  # Copy parameters file if specified
  $remoteParamsPath = $null
  if ($ParametersPath) {
    $paramsFileName = Split-Path $ParametersPath -Leaf
    $remoteParamsPath = "C:\Temp\$paramsFileName"
    Copy-Item -Path $ParametersPath -Destination $remoteParamsPath -ToSession $session -Force
  }
    
  Write-Host "✓ Files copied successfully" -ForegroundColor Green
    
  # Execute DSC operation on remote machine with autocomplete support
  Write-Host "Executing DSC operation on remote machine..." -ForegroundColor Cyan
    
  $remoteScript = {
    param($ModulePath, $DscPath, $ParametersPath, $Operation, $WhatIf)
        
    # Import the module (this enables autocomplete on the remote machine)
  Import-Module $ModulePath -Force
        
    # Build parameters for the appropriate function
    $params = @{
      DscPath = $DscPath
    }
        
    if ($ParametersPath) { $params.ParametersPath = $ParametersPath }
    if ($WhatIf) { $params.WhatIf = $true }
        
    # Execute based on operation
    switch ($Operation) {
      "Test" {
        Write-Host "Testing DSC compliance on $env:COMPUTERNAME..." -ForegroundColor Yellow
        $result = Test-DscCompliance @params
        Write-Host "Compliance result: $result" -ForegroundColor $(if ($result) { 'Green' } else { 'Red' })
        return $result
      }
      "Set" {
        Write-Host "Applying DSC configuration on $env:COMPUTERNAME..." -ForegroundColor Yellow
        $result = Set-DscConfiguration @params
        Write-Host "Configuration applied successfully" -ForegroundColor Green
        return $result
      }
      "Validate" {
        Write-Host "Validating DSC configuration on $env:COMPUTERNAME..." -ForegroundColor Yellow
        $result = Test-DscConfiguration @params
        Write-Host "Configuration validation completed" -ForegroundColor Green
        return $result
      }
      "Export" {
        Write-Host "Exporting current state on $env:COMPUTERNAME..." -ForegroundColor Yellow
        $result = Invoke-DscHelper -DscPath $DscPath -Operation "Export" -ParametersPath $ParametersPath
        Write-Host "State export completed" -ForegroundColor Green
        return $result
      }
    }
  }
    
  # Execute the remote script
  $result = Invoke-Command -Session $session -ArgumentList $remoteModuleDir, $remoteDscPath, $remoteParamsPath, $Operation, $WhatIf -ScriptBlock $remoteScript
    
  Write-Host ""
  Write-Host "=== Remote Execution Complete ===" -ForegroundColor Green
  Write-Host "Result: $result" -ForegroundColor Yellow
    
  # Show autocomplete instructions for future use
  Write-Host ""
  Write-Host "=== Future Remote Usage with Autocomplete ===" -ForegroundColor Green
  Write-Host "To use autocomplete on the remote machine in the future:" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "1. Connect to the remote machine:" -ForegroundColor Gray
  Write-Host "   Enter-PSSession -ComputerName '$ComputerName'" -ForegroundColor Gray
  Write-Host ""
  Write-Host "2. Import the module:" -ForegroundColor Gray
  Write-Host "   Import-Module '$remoteModuleDir\StateSmith.DSC.psm1'" -ForegroundColor Gray
  Write-Host ""
  Write-Host "3. Use with full autocomplete:" -ForegroundColor Gray
  Write-Host "   Test-DscCompliance -DscPath '$remoteDscPath'" -ForegroundColor Gray
  Write-Host "   Set-DscConfiguration -DscPath '$remoteDscPath' -WhatIf" -ForegroundColor Gray
  Write-Host "   Invoke-DscHelper -DscPath '$remoteDscPath' -Operation 'Test' -ReturnInDesiredState" -ForegroundColor Gray
    
} catch {
  Write-Host "=== Error ===" -ForegroundColor Red
  Write-Host "Remote DSC test failed: $($_.Exception.Message)" -ForegroundColor Red
} finally {
  # Clean up session
  if ($session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    Write-Host "✓ Remote session closed" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host "=== Script Complete ===" -ForegroundColor Green 