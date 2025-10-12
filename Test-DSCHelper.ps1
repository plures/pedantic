# Test script for improved DSCHelper.ps1
<#
.SYNOPSIS
    Demonstrates the improved DSCHelper.ps1 functionality with various DSC operations.
.DESCRIPTION
    This script shows how to use the improved DSCHelper.ps1 with better parameter validation
    and user guidance. It includes examples for different DSC operations.
.EXAMPLE
    .\Test-DSCHelper.ps1 -Operation "Test" -DscPath "C:\Configs\WebServer.yaml"
.EXAMPLE
    .\Test-DSCHelper.ps1 -Operation "Set" -DscPath "C:\Configs\Cluster.yaml" -WhatIf
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

Write-Host "=== DSC Helper Test Script ===" -ForegroundColor Green
Write-Host "Operation: $Operation" -ForegroundColor Yellow
Write-Host "DSC Path: $DscPath" -ForegroundColor Yellow
if ($ParametersPath) { Write-Host "Parameters: $ParametersPath" -ForegroundColor Yellow }
if ($ComputerName) { Write-Host "Target: $ComputerName" -ForegroundColor Yellow }
if ($WhatIf) { Write-Host "WhatIf: Enabled" -ForegroundColor Yellow }
Write-Host ""

# Build parameter hashtable for DSCHelper
$dscParams = @{
  DscPath   = $DscPath
  Operation = $Operation
  Quiet     = $false
}

if ($ParametersPath) { $dscParams.ParametersPath = $ParametersPath }
if ($ComputerName) { $dscParams.ComputerName = $ComputerName }
if ($WhatIf) { $dscParams.WhatIf = $true }

try {
  Write-Host "Executing DSCHelper with parameters:" -ForegroundColor Cyan
  $dscParams.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
  }
  Write-Host ""
    
  # Execute DSCHelper
  $result = & "$PSScriptRoot\DSCHelper.ps1" @dscParams
    
  Write-Host "=== Result ===" -ForegroundColor Green
  if ($result) {
    Write-Host "Success! DSC operation completed." -ForegroundColor Green
    Write-Host "Result type: $($result.GetType().Name)" -ForegroundColor Gray
        
    # Display key properties if available
    if ($result.PSObject.Properties.Name -contains 'inDesiredState') {
      Write-Host "In Desired State: $($result.inDesiredState)" -ForegroundColor $(if ($result.inDesiredState) { 'Green' } else { 'Red' })
    }
    if ($result.PSObject.Properties.Name -contains 'InDesiredState') {
      Write-Host "In Desired State: $($result.InDesiredState)" -ForegroundColor $(if ($result.InDesiredState) { 'Green' } else { 'Red' })
    }
        
    # Show result object structure
    Write-Host "Result properties:" -ForegroundColor Gray
    $result.PSObject.Properties | ForEach-Object {
      Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor Gray
    }
  } else {
    Write-Host "No result returned from DSC operation." -ForegroundColor Yellow
  }
} catch {
  Write-Host "=== Error ===" -ForegroundColor Red
  Write-Host "DSC Helper failed: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Error details: $($_.Exception)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Green 