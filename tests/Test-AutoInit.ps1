# Test automatic cache initialization on module import
Write-Host "Testing automatic DSC cache initialization..." -ForegroundColor Green

# Remove module if already loaded
if (Get-Module -Name "StateSmith.DSC" -ErrorAction SilentlyContinue) {
    Remove-Module -Name "StateSmith.DSC" -Force
    Write-Host "Removed existing StateSmith.DSC module" -ForegroundColor Yellow
}

# Import module (this should trigger automatic initialization)
Write-Host "`nImporting StateSmith.DSC module..." -ForegroundColor Yellow
try {
    Import-Module "$PSScriptRoot\Pedantic.psm1" -Force
    Write-Host "✓ Module imported successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Module import failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test that caches are accessible
Write-Host "`nTesting cache accessibility..." -ForegroundColor Yellow

try {
    $installerCache = Get-DscInstallerCache
    Write-Host "✓ Installer cache accessible" -ForegroundColor Green
    Write-Host "  Available versions: $($installerCache.AvailableVersions.PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Installer cache test failed: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $resourceCache = Get-DscResourceCache
    Write-Host "✓ Resource cache accessible" -ForegroundColor Green
    Write-Host "  Available resources: $($resourceCache.AvailableResources.PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Resource cache test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test that we can get installer path (should work even if no installers are cached)
Write-Host "`nTesting installer path retrieval..." -ForegroundColor Yellow
try {
    $installerPath = Get-DscInstallerPath -Quiet
    if ($installerPath) {
        Write-Host "✓ Installer path found: $installerPath" -ForegroundColor Green
    } else {
        Write-Host "ℹ No cached installer found (this is normal for first run)" -ForegroundColor Yellow
        Write-Host "  Run 'Update-DscInstallerCache' to download installers" -ForegroundColor Cyan
    }
} catch {
    Write-Host "✗ Installer path test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nAutomatic initialization test completed!" -ForegroundColor Green 