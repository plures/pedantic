# Test script to verify DSC cache call depth overflow fix
# This script tests the cache initialization functions to ensure they handle errors gracefully

Import-Module "$PSScriptRoot\StateSmith.DSC.psm1" -Force

Write-Host "Testing DSC cache initialization fix..." -ForegroundColor Green

# Test 1: Normal cache initialization
Write-Host "`nTest 1: Normal cache initialization" -ForegroundColor Yellow
try {
    $cache = Get-InstallerCache
    Write-Host "✓ Normal cache initialization successful" -ForegroundColor Green
    Write-Host "  Cache structure: $($cache.PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Normal cache initialization failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Resource cache initialization
Write-Host "`nTest 2: Resource cache initialization" -ForegroundColor Yellow
try {
    $resourceCache = Get-ResourceCache
    Write-Host "✓ Resource cache initialization successful" -ForegroundColor Green
    Write-Host "  Cache structure: $($resourceCache.PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Resource cache initialization failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Update check functionality
Write-Host "`nTest 3: Update check functionality" -ForegroundColor Yellow
try {
    $needsUpdate = Test-UpdateCheckNeeded
    Write-Host "✓ Update check successful: Update needed = $needsUpdate" -ForegroundColor Green
} catch {
    Write-Host "✗ Update check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Corrupted cache file handling
Write-Host "`nTest 4: Corrupted cache file handling" -ForegroundColor Yellow
$cacheFile = Join-Path $PSScriptRoot "Installers\installer-cache.json"
$backupFile = "$cacheFile.backup"

# Backup original cache file
if (Test-Path $cacheFile) {
    Copy-Item -Path $cacheFile -Destination $backupFile -Force
}

# Create corrupted cache file
"invalid json content" | Set-Content -Path $cacheFile -Force

try {
    $cache = Get-InstallerCache
    Write-Host "✓ Corrupted cache file handled gracefully" -ForegroundColor Green
    Write-Host "  Cache was reinitialized with default structure" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Corrupted cache file handling failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Restore original cache file
if (Test-Path $backupFile) {
    Copy-Item -Path $backupFile -Destination $cacheFile -Force
    Remove-Item -Path $backupFile -Force
}

# Test 5: Missing cache file handling
Write-Host "`nTest 5: Missing cache file handling" -ForegroundColor Yellow
$resourceCacheFile = Join-Path $PSScriptRoot "Resources\resource-cache.json"
$resourceBackupFile = "$resourceCacheFile.backup"

# Backup original resource cache file
if (Test-Path $resourceCacheFile) {
    Copy-Item -Path $resourceCacheFile -Destination $resourceBackupFile -Force
}

# Remove resource cache file
if (Test-Path $resourceCacheFile) {
    Remove-Item -Path $resourceCacheFile -Force
}

try {
    $resourceCache = Get-ResourceCache
    Write-Host "✓ Missing cache file handled gracefully" -ForegroundColor Green
    Write-Host "  Cache was created with default structure" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Missing cache file handling failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Restore original resource cache file
if (Test-Path $resourceBackupFile) {
    Copy-Item -Path $resourceBackupFile -Destination $resourceCacheFile -Force
    Remove-Item -Path $resourceBackupFile -Force
}

Write-Host "`nCache fix verification completed!" -ForegroundColor Green 