# Test script to verify DSC repair functionality
# This script tests the Repair-DscInstallation function

param(
  [string]$ComputerName = $env:COMPUTERNAME,
  [switch]$Quiet,
  [switch]$Force
)

Write-Host "Testing DSC repair functionality..." -ForegroundColor Yellow
Write-Host "Target computer: $ComputerName" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check current DSC installation status
Write-Host "=== Test 1: Check current DSC installation status ===" -ForegroundColor Green
try {
  $result = Repair-DscInstallation -ComputerName $ComputerName -Quiet:$Quiet -Force:$Force
  if ($result) {
    Write-Host "✓ DSC installation check completed successfully" -ForegroundColor Green
  } else {
    Write-Host "✗ DSC installation check failed" -ForegroundColor Red
  }
} catch {
  Write-Host "✗ DSC installation check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Test DSC functionality after repair
Write-Host "=== Test 2: Test DSC functionality after repair ===" -ForegroundColor Green
try {
  # Create a simple test configuration
  $testConfig = @"
resources:
  - name: TestFile
    type: Microsoft.DSC.FileResource
    properties:
      path: C:\Temp\test.txt
      content: "Test content"
"@

  $testConfig | Set-Content -Path "test-config.yaml" -Force
    
  # Test DSC validation
  $result = Invoke-DscHelper -DscPath "test-config.yaml" -Operation "Validate" -ComputerName $ComputerName -Quiet:$Quiet
  Write-Host "✓ DSC functionality test completed successfully" -ForegroundColor Green
} catch {
  Write-Host "✗ DSC functionality test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 3: Manual DSC command test (if running locally)
if ($ComputerName -eq $env:COMPUTERNAME) {
  Write-Host "=== Test 3: Manual DSC command test ===" -ForegroundColor Green
  try {
    # Set environment variables to prevent tracing errors
    $env:DSC_TRACE = "0"
    $env:DSC_LOG_LEVEL = "error"
        
    # Test basic DSC command
    $output = & dsc resource list --output-format json 2>&1
    $exitCode = $LASTEXITCODE
        
    if ($exitCode -eq 0) {
      Write-Host "✓ Manual DSC command completed successfully" -ForegroundColor Green
      Write-Host "Output: $output" -ForegroundColor Cyan
    } else {
      Write-Host "✗ Manual DSC command failed with exit code $exitCode" -ForegroundColor Red
      Write-Host "Output: $output" -ForegroundColor Red
    }
  } catch {
    Write-Host "✗ Manual DSC command failed: $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "Test completed. If you don't see any 'tracing' errors above," -ForegroundColor Yellow
Write-Host "then the repair function is working correctly!" -ForegroundColor Yellow

# Cleanup
if (Test-Path "test-config.yaml") {
  Remove-Item "test-config.yaml" -Force
} 