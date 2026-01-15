# Simple test script for StateSmith.DSC module import
<#
.SYNOPSIS
  Simple test to verify StateSmith.DSC module import and autocomplete.
#>

Write-Host "Testing StateSmith.DSC module import..." -ForegroundColor Green

# Remove any existing module
Remove-Module StateSmith.DSC -Force -ErrorAction SilentlyContinue

# Try importing the meta-module (this should work)
try {
  Import-Module StateSmith.DSC -Force
  Write-Host "✓ Successfully imported StateSmith.DSC" -ForegroundColor Green
    
  # Check if functions are available
  $functions = Get-Command -Module StateSmith.DSC
  Write-Host "Available functions: $($functions.Name -join ', ')" -ForegroundColor Cyan
    
  # Test if Invoke-DscHelper is available
  $dscHelper = Get-Command Invoke-DscHelper -ErrorAction SilentlyContinue
  if ($dscHelper) {
    Write-Host "✓ Invoke-DscHelper is available" -ForegroundColor Green
    Write-Host "Parameters: $($dscHelper.Parameters.Keys -join ', ')" -ForegroundColor Gray
        
    Write-Host ""
    Write-Host "=== AUTECOMPLETE TEST ===" -ForegroundColor Yellow
    Write-Host "Now try typing 'Invoke-DscHelper -' and press TAB" -ForegroundColor Cyan
    Write-Host "You should see parameter names appear!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Also try:" -ForegroundColor Gray
  Write-Host "  Test-DscCompliance -" -ForegroundColor Gray
    Write-Host "  Set-DscConfiguration -" -ForegroundColor Gray
    Write-Host "  Test-DscConfiguration -" -ForegroundColor Gray
  } else {
    Write-Host "✗ Invoke-DscHelper not found" -ForegroundColor Red
  }
    
} catch {
  Write-Host "✗ Error importing module: $($_.Exception.Message)" -ForegroundColor Red
} 