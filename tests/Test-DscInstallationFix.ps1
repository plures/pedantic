# Test script to verify DSC installation fix
# This script tests that Invoke-DscHelper no longer installs DSC every time

param(
  [string]$ComputerName = $env:COMPUTERNAME,
  [string]$DscPath = "test-config.yaml",
  [switch]$Quiet
)

# Create a simple test DSC configuration
$testConfig = @"
resources:
  - name: TestFile
    type: Microsoft.DSC.FileResource
    properties:
      path: C:\Temp\test.txt
      content: "Test content"
"@

$testConfig | Set-Content -Path $DscPath -Force

Write-Host "Testing DSC installation fix..." -ForegroundColor Yellow
Write-Host "Target computer: $ComputerName" -ForegroundColor Cyan
Write-Host "DSC config: $DscPath" -ForegroundColor Cyan
Write-Host ""

# Test 1: First run (should install DSC if not present)
Write-Host "=== Test 1: First run ===" -ForegroundColor Green
try {
  $result1 = Invoke-DscHelper -DscPath $DscPath -Operation "Validate" -ComputerName $ComputerName -Quiet:$Quiet
  Write-Host "✓ First run completed successfully" -ForegroundColor Green
} catch {
  Write-Host "✗ First run failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Second run (should NOT install DSC again)
Write-Host "=== Test 2: Second run (should skip installation) ===" -ForegroundColor Green
try {
  $result2 = Invoke-DscHelper -DscPath $DscPath -Operation "Validate" -ComputerName $ComputerName -Quiet:$Quiet
  Write-Host "✓ Second run completed successfully" -ForegroundColor Green
} catch {
  Write-Host "✗ Second run failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 3: Third run (should NOT install DSC again)
Write-Host "=== Test 3: Third run (should skip installation) ===" -ForegroundColor Green
try {
  $result3 = Invoke-DscHelper -DscPath $DscPath -Operation "Validate" -ComputerName $ComputerName -Quiet:$Quiet
  Write-Host "✓ Third run completed successfully" -ForegroundColor Green
} catch {
  Write-Host "✗ Third run failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test completed. If you see 'DSC v3 is already available' messages for runs 2 and 3," -ForegroundColor Yellow
Write-Host "then the fix is working correctly!" -ForegroundColor Yellow

# Cleanup
if (Test-Path $DscPath) {
  Remove-Item $DscPath -Force
} 