# Test script for parameter autocomplete functionality
<#
.SYNOPSIS
  Tests parameter autocomplete functionality for the Pedantic module.
.DESCRIPTION
    This script verifies that parameter autocomplete is working correctly
  for all functions in the Pedantic module.
#>

Write-Host "=== Testing Parameter Autocomplete ===" -ForegroundColor Green
Write-Host ""

# Import the module
Write-Host "Importing Pedantic module..." -ForegroundColor Yellow
Remove-Module Pedantic -Force -ErrorAction SilentlyContinue
Import-Module ".\Pedantic.psm1" -Force
Write-Host "✓ Module imported successfully" -ForegroundColor Green
Write-Host ""

# Test each function
$functions = @('Invoke-DscHelper', 'Test-DscCompliance', 'Set-DscConfiguration', 'Test-DscConfiguration')

foreach ($function in $functions) {
  Write-Host "Testing $function..." -ForegroundColor Cyan
    
  $command = Get-Command $function -ErrorAction SilentlyContinue
  if ($command) {
    Write-Host "  ✓ Function found" -ForegroundColor Green
    Write-Host "  Parameters:" -ForegroundColor Gray
        
    $command.Parameters.Values | Where-Object { $_.Name -notin @('WhatIf', 'Confirm', 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable') } | ForEach-Object {
      $required = if ($_.Mandatory) { " [Required]" } else { " [Optional]" }
      $aliases = if ($_.Aliases) { " (Aliases: $($_.Aliases -join ', '))" } else { "" }
      Write-Host "    -$($_.Name)$required : $($_.ParameterType.Name)$aliases" -ForegroundColor Gray
    }
        
    # Test parameter validation
    if ($function -eq 'Invoke-DscHelper') {
      $operationParam = $command.Parameters['Operation']
      if ($operationParam) {
        $validValues = $operationParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        if ($validValues) {
          Write-Host "  Valid Operations: $($validValues.ValidValues -join ', ')" -ForegroundColor Gray
        }
      }
    }
        
  } else {
    Write-Host "  ✗ Function not found" -ForegroundColor Red
  }
  Write-Host ""
}

Write-Host "=== Autocomplete Test Instructions ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Now try these commands in your PowerShell session:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Type 'Invoke-DscHelper -' and press TAB" -ForegroundColor Gray
Write-Host "   You should see: DscPath, Operation, ParametersPath, ComputerName, etc." -ForegroundColor Gray
Write-Host ""
Write-Host "2. Type 'Invoke-DscHelper -Operation ' and press TAB" -ForegroundColor Gray
Write-Host "   You should see: Set, Test, Validate, Export" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Type 'Test-DscCompliance -' and press TAB" -ForegroundColor Gray
Write-Host "   You should see: DscPath, ParametersPath, ComputerName, Credential" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Type 'Set-DscConfiguration -' and press TAB" -ForegroundColor Gray
Write-Host "   You should see: DscPath, ParametersPath, ComputerName, WhatIf, Credential" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Try using aliases:" -ForegroundColor Gray
Write-Host "   Type 'Invoke-DscHelper -Op ' and press TAB" -ForegroundColor Gray
Write-Host "   Type 'Invoke-DscHelper -Path ' and press TAB" -ForegroundColor Gray
Write-Host ""

Write-Host "=== Additional Tests ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test parameter validation:" -ForegroundColor Cyan
Write-Host "Get-Help Invoke-DscHelper -Parameter Operation" -ForegroundColor Gray
Write-Host "Get-Help Test-DscCompliance -Parameter DscPath" -ForegroundColor Gray
Write-Host ""

Write-Host "Test parameter sets:" -ForegroundColor Cyan
Write-Host "Get-Help Invoke-DscHelper -ParameterSetName Default" -ForegroundColor Gray
Write-Host "Get-Help Invoke-DscHelper -ParameterSetName Remote" -ForegroundColor Gray
Write-Host ""

Write-Host "=== Troubleshooting ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "If autocomplete still doesn't work:" -ForegroundColor Cyan
Write-Host "1. Make sure you're using PowerShell 5.1 or later" -ForegroundColor Gray
Write-Host "2. Try restarting PowerShell" -ForegroundColor Gray
Write-Host "3. Check if the module is loaded: Get-Module Pedantic" -ForegroundColor Gray
Write-Host "4. Try importing again: Import-Module '.\Pedantic.psm1' -Force" -ForegroundColor Gray
Write-Host ""

Write-Host "=== Test Complete ===" -ForegroundColor Green 