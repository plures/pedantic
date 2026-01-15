# Test script for StateSmith.DSC module with parameter autocomplete
<#
.SYNOPSIS
  Demonstrates the StateSmith.DSC module functionality with full parameter autocomplete support.
.DESCRIPTION
  This script shows how to import and use the StateSmith.DSC module, which provides
    full parameter autocomplete in PowerShell for DSC operations.
.EXAMPLE
    .\Test-DscModule.ps1 -Operation "Test" -DscPath "C:\Configs\WebServer.yaml"
.EXAMPLE
    .\Test-DscModule.ps1 -Operation "Set" -DscPath "C:\Configs\Cluster.yaml" -WhatIf
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, HelpMessage = 'DSC operation to demonstrate')]
  [ValidateSet('Set', 'Test', 'Validate', 'Export')]
  [string]$Operation,
    
  [Parameter(Mandatory = $true, HelpMessage = 'Path to DSC configuration file')]
  [string]$DscPath,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Path to parameters file')]
  [string]$ParametersPath,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Target computer for remote execution')]
  [string]$ComputerName,
    
  [Parameter(Mandatory = $false, HelpMessage = 'Show what-if scenario')]
  [switch]$WhatIf
)

Write-Host "=== StateSmith.DSC Module Test Script ===" -ForegroundColor Green
Write-Host "Operation: $Operation" -ForegroundColor Yellow
Write-Host "DSC Path: $DscPath" -ForegroundColor Yellow
if ($ParametersPath) { Write-Host "Parameters: $ParametersPath" -ForegroundColor Yellow }
if ($ComputerName) { Write-Host "Target: $ComputerName" -ForegroundColor Yellow }
if ($WhatIf) { Write-Host "WhatIf: Enabled" -ForegroundColor Yellow }
Write-Host ""

# Import the module
$modulePath = Join-Path $PSScriptRoot "StateSmith.DSC.psm1"
if (-not (Test-Path $modulePath)) {
  Write-Error "Module file not found: $modulePath"
  exit 1
}

try {
  Import-Module $modulePath -Force
  Write-Host "✓ StateSmith.DSC module imported successfully" -ForegroundColor Green
  Write-Host ""
    
  # Show available functions
  Write-Host "Available functions:" -ForegroundColor Cyan
  Get-Command -Module StateSmith.DSC | ForEach-Object {
    Write-Host "  $($_.Name)" -ForegroundColor Gray
  }
  Write-Host ""
    
  # Demonstrate parameter autocomplete by showing function signatures
  Write-Host "Function signatures (you'll get autocomplete for these):" -ForegroundColor Cyan
    
  Write-Host "`nInvoke-DscHelper:" -ForegroundColor Yellow
  (Get-Command Invoke-DscHelper).Parameters.Values | Where-Object { $_.ParameterType -ne [System.Management.Automation.SwitchParameter] } | ForEach-Object {
    $required = if ($_.Mandatory) { " [Required]" } else { " [Optional]" }
    Write-Host "  -$($_.Name)$required : $($_.ParameterType.Name)" -ForegroundColor Gray
  }
    
  Write-Host "`nTest-DscCompliance:" -ForegroundColor Yellow
  (Get-Command Test-DscCompliance).Parameters.Values | Where-Object { $_.ParameterType -ne [System.Management.Automation.SwitchParameter] } | ForEach-Object {
    $required = if ($_.Mandatory) { " [Required]" } else { " [Optional]" }
    Write-Host "  -$($_.Name)$required : $($_.ParameterType.Name)" -ForegroundColor Gray
  }
    
  Write-Host "`nSet-DscConfiguration:" -ForegroundColor Yellow
  (Get-Command Set-DscConfiguration).Parameters.Values | ForEach-Object {
    $required = if ($_.Mandatory) { " [Required]" } else { " [Optional]" }
    Write-Host "  -$($_.Name)$required : $($_.ParameterType.Name)" -ForegroundColor Gray
  }
    
  Write-Host ""
    
  # Execute the appropriate function based on operation
  Write-Host "=== Executing DSC Operation ===" -ForegroundColor Green
    
  switch ($Operation) {
    "Test" {
      Write-Host "Testing DSC compliance..." -ForegroundColor Cyan
      $result = Test-DscCompliance -DscPath $DscPath -ParametersPath $ParametersPath -ComputerName $ComputerName
      Write-Host "Compliance result: $result" -ForegroundColor $(if ($result) { 'Green' } else { 'Red' })
    }
    "Set" {
      Write-Host "Applying DSC configuration..." -ForegroundColor Cyan
      $result = Set-DscConfiguration -DscPath $DscPath -ParametersPath $ParametersPath -ComputerName $ComputerName -WhatIf:$WhatIf
      Write-Host "Configuration applied successfully" -ForegroundColor Green
    }
    "Validate" {
      Write-Host "Validating DSC configuration..." -ForegroundColor Cyan
      $result = Test-DscConfiguration -DscPath $DscPath
      Write-Host "Configuration validation completed" -ForegroundColor Green
    }
    "Export" {
      Write-Host "Exporting current state..." -ForegroundColor Cyan
      $result = Invoke-DscHelper -DscPath $DscPath -Operation "Export" -ParametersPath $ParametersPath -ComputerName $ComputerName
      Write-Host "State export completed" -ForegroundColor Green
    }
  }
    
  Write-Host ""
  Write-Host "=== Autocomplete Instructions ===" -ForegroundColor Green
  Write-Host "Now you can use these functions with full autocomplete:" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "1. Type 'Invoke-DscHelper -' and press TAB to cycle through parameters" -ForegroundColor Gray
  Write-Host "2. Type 'Invoke-DscHelper -Operation ' and press TAB to see valid values" -ForegroundColor Gray
  Write-Host "3. Type 'Test-DscCompliance -' for the simplified compliance test" -ForegroundColor Gray
  Write-Host "4. Type 'Set-DscConfiguration -' for the simplified configuration apply" -ForegroundColor Gray
  Write-Host ""
  Write-Host "Example commands you can now run:" -ForegroundColor Yellow
  Write-Host "  Test-DscCompliance -DscPath 'C:\Configs\WebServer.yaml'" -ForegroundColor Gray
  Write-Host "  Set-DscConfiguration -DscPath 'C:\Configs\Cluster.yaml' -WhatIf" -ForegroundColor Gray
  Write-Host "  Invoke-DscHelper -DscPath 'C:\Configs\Baseline.yaml' -Operation 'Test' -ReturnInDesiredState" -ForegroundColor Gray
    
} catch {
  Write-Host "=== Error ===" -ForegroundColor Red
  Write-Host "Module test failed: $($_.Exception.Message)" -ForegroundColor Red
} finally {
  # Clean up
  if (Get-Module StateSmith.DSC) {
    Remove-Module StateSmith.DSC -Force
    Write-Host "✓ Module unloaded" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Green 