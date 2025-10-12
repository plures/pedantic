# Simple autocomplete test
Write-Host "Testing StateSmith.DSC module autocomplete..." -ForegroundColor Green

# Import module
Remove-Module StateSmith.DSC -Force -ErrorAction SilentlyContinue
Import-Module ".\StateSmith.DSC.psm1" -Force
Write-Host "✓ Module imported" -ForegroundColor Green

# Test functions
$functions = @('Invoke-DscHelper', 'Test-DscCompliance', 'Set-DscConfiguration', 'Test-DscConfiguration')

foreach ($function in $functions) {
  $cmd = Get-Command $function -ErrorAction SilentlyContinue
  if ($cmd) {
    Write-Host "✓ $function is available" -ForegroundColor Green
    $paramCount = $cmd.Parameters.Count
    Write-Host "  Parameters: $paramCount" -ForegroundColor Gray
  } else {
    Write-Host "✗ $function not found" -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "=== AUTECOMPLETE TEST ===" -ForegroundColor Yellow
Write-Host "Now try typing these commands and press TAB:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Invoke-DscHelper -" -ForegroundColor Gray
Write-Host "2. Test-DscCompliance -" -ForegroundColor Gray
Write-Host "3. Set-DscConfiguration -" -ForegroundColor Gray
Write-Host "4. Test-DscConfiguration -" -ForegroundColor Gray
Write-Host ""
Write-Host "You should see parameter names appear!" -ForegroundColor Green 