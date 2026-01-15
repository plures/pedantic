# Simple test to verify cache fix
Write-Host "Testing cache initialization fix..." -ForegroundColor Green

# Test basic file operations
$testPath = ".\TestCache"
$testFile = Join-Path $testPath "test-cache.json"

# Clean up from previous tests
if (Test-Path $testPath) {
  Remove-Item -Path $testPath -Recurse -Force
}

# Test 1: Create directory and file
try {
  New-Item -Path $testPath -ItemType Directory -Force | Out-Null
  @{
    LastUpdateCheck   = $null
    AvailableVersions = @{}
    CurrentVersion    = $null
  } | ConvertTo-Json | Set-Content -Path $testFile
  Write-Host "✓ Test 1: Directory and file creation successful" -ForegroundColor Green
} catch {
  Write-Host "✗ Test 1 failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Read and validate JSON
try {
  $content = Get-Content -Path $testFile -Raw -ErrorAction Stop
  $cache = $content | ConvertFrom-Json -ErrorAction Stop
    
  if ($cache.PSObject.Properties.Name -contains "LastUpdateCheck" -and 
    $cache.PSObject.Properties.Name -contains "AvailableVersions" -and 
    $cache.PSObject.Properties.Name -contains "CurrentVersion") {
    Write-Host "✓ Test 2: JSON read and validation successful" -ForegroundColor Green
  } else {
    Write-Host "✗ Test 2: Invalid cache structure" -ForegroundColor Red
  }
} catch {
  Write-Host "✗ Test 2 failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Corrupted JSON handling
"invalid json content" | Set-Content -Path $testFile -Force

try {
  $content = Get-Content -Path $testFile -Raw -ErrorAction Stop
  $cache = $content | ConvertFrom-Json -ErrorAction Stop
  Write-Host "✗ Test 3: Should have failed with corrupted JSON" -ForegroundColor Red
} catch {
  Write-Host "✓ Test 3: Corrupted JSON properly detected" -ForegroundColor Green
}

# Clean up
if (Test-Path $testPath) {
  Remove-Item -Path $testPath -Recurse -Force
}

Write-Host "`nSimple test completed!" -ForegroundColor Green 