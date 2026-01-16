# Simple test script for Pedantic module import
<#
.SYNOPSIS
  Simple test to verify Pedantic module import and autocomplete.
#>

Write-Host "Testing Pedantic module import..." -ForegroundColor Green

# Remove any existing module
Remove-Module Pedantic -Force -ErrorAction SilentlyContinue

# Try importing the module from parent directory
$modulePath = Join-Path $PSScriptRoot ".." "Pedantic.psd1"
if (-not (Test-Path $modulePath)) {
  Write-Host "✗ Module manifest not found: $modulePath" -ForegroundColor Red
  exit 1
}

try {
  Import-Module $modulePath -Force
  Write-Host "✓ Successfully imported Pedantic" -ForegroundColor Green
    
  # Check if functions are available
  $functions = Get-Command -Module Pedantic
  Write-Host "Available functions: $($functions.Name -join ', ')" -ForegroundColor Cyan
    
  # Test if Invoke-DscHelper is available
  $dscHelper = Get-Command Invoke-DscHelper -ErrorAction SilentlyContinue
  if ($dscHelper) {
    Write-Host "✓ Invoke-DscHelper is available" -ForegroundColor Green
    Write-Host "Parameters: $($dscHelper.Parameters.Keys -join ', ')" -ForegroundColor Gray
        
    Write-Host ""
    Write-Host "=== AUTOCOMPLETE TEST ===" -ForegroundColor Yellow
    Write-Host "Now try typing 'Invoke-DscHelper -' and press TAB" -ForegroundColor Cyan
    Write-Host "You should see parameter names appear!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Also try:" -ForegroundColor Gray
  Write-Host "  Test-DscConfiguration -" -ForegroundColor Gray
    Write-Host "  Set-DscConfiguration -" -ForegroundColor Gray
    Write-Host "  Validate-DscConfiguration -" -ForegroundColor Gray
  } else {
    Write-Host "✗ Invoke-DscHelper not found" -ForegroundColor Red
  }
    
} catch {
  Write-Host "✗ Error importing module: $($_.Exception.Message)" -ForegroundColor Red
}