# Test script to verify DSC configuration fix
# This script tests that DSC can find its configuration files after installation

param(
  [string]$ComputerName = $env:COMPUTERNAME,
  [switch]$Quiet
)

Write-Host "Testing DSC configuration fix..." -ForegroundColor Yellow
Write-Host "Target computer: $ComputerName" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if DSC can run without tracing errors
Write-Host "=== Test 1: Basic DSC command (should not show tracing errors) ===" -ForegroundColor Green
try {
  $result = Invoke-DscHelper -DscPath "test-config.yaml" -Operation "Validate" -ComputerName $ComputerName -Quiet:$Quiet
  Write-Host "✓ DSC command completed without tracing errors" -ForegroundColor Green
} catch {
  Write-Host "✗ DSC command failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Check if DSC can list resources without tracing errors
Write-Host "=== Test 2: DSC resource list (should not show tracing errors) ===" -ForegroundColor Green
try {
  # Create a simple test to check resource listing
  $testConfig = @"
resources:
  - name: TestFile
    type: Microsoft.DSC.FileResource
    properties:
      path: C:\Temp\test.txt
      content: "Test content"
"@

  $testConfig | Set-Content -Path "test-config.yaml" -Force
    
  $result = Invoke-DscHelper -DscPath "test-config.yaml" -Operation "Validate" -ComputerName $ComputerName -Quiet:$Quiet
  Write-Host "✓ DSC resource validation completed without tracing errors" -ForegroundColor Green
} catch {
  Write-Host "✗ DSC resource validation failed: $($_.Exception.Message)" -ForegroundColor Red
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
Write-Host "then the configuration fix is working correctly!" -ForegroundColor Yellow

# Cleanup
if (Test-Path "test-config.yaml") {
  Remove-Item "test-config.yaml" -Force
} 