# Test script to verify improved DSC resource detection
# This script tests the new resource detection logic that should correctly identify available resources

Import-Module Pedantic -Force

Write-Host "Testing improved DSC resource detection..." -ForegroundColor Yellow

# Test 1: Use the SkipResourceCheck parameter to bypass resource checking entirely
Write-Host "`nTest 1: Using SkipResourceCheck parameter" -ForegroundColor Cyan
try {
  $result = Invoke-DscHelper -DscPath .\Check-23H2.dsc.yaml -ComputerName co1hcibldprd015 -Operation Test -SkipResourceCheck
  Write-Host "✓ Test completed successfully with SkipResourceCheck" -ForegroundColor Green
  Write-Host "Result: $($result.inDesiredState)" -ForegroundColor Green
} catch {
  Write-Host "✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Test the improved resource detection logic
Write-Host "`nTest 2: Testing improved resource detection" -ForegroundColor Cyan
try {
  $result = Invoke-DscHelper -DscPath .\Check-23H2.dsc.yaml -ComputerName co1hcibldprd015 -Operation Test
  Write-Host "✓ Test completed successfully with improved resource detection" -ForegroundColor Green
  Write-Host "Result: $($result.inDesiredState)" -ForegroundColor Green
} catch {
  Write-Host "✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nResource detection test completed!" -ForegroundColor Yellow 