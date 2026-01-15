# Test script for DSC Reverse functionality
# Demonstrates cataloging, history tracking, diff analysis, and restoration capabilities

Import-Module .\Pedantic.Reverse.psm1 -Force

Write-Host "=== DSC Reverse Feature Test ===" -ForegroundColor Yellow
Write-Host "This script demonstrates the DSC Reverse functionality" -ForegroundColor Cyan

# Use localhost for testing instead of hardcoded production machine
$testComputerName = $env:COMPUTERNAME

# Test 1: Create a system catalog
Write-Host "`n=== Test 1: System Cataloging ===" -ForegroundColor Green
try {
  $catalogResult = New-DscSystemCatalog -ComputerName $testComputerName -CatalogName "TestCatalog" -IncludeResources @("Registry", "File", "Service")
    
  if ($catalogResult) {
    Write-Host "✓ Catalog created successfully" -ForegroundColor Green
    Write-Host "Catalog file: $($catalogResult.FilePath)" -ForegroundColor Cyan
    Write-Host "Resources cataloged: $($catalogResult.ResourceCount)" -ForegroundColor Cyan
  } else {
    Write-Host "✗ Catalog creation failed" -ForegroundColor Red
  }
} catch {
  Write-Host "✗ Catalog creation failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Create another catalog (for comparison)
Write-Host "`n=== Test 2: Second Catalog (for comparison) ===" -ForegroundColor Green
try {
  Start-Sleep -Seconds 2  # Small delay to ensure different timestamp
  $catalogResult2 = New-DscSystemCatalog -ComputerName $testComputerName -CatalogName "TestCatalog2" -IncludeResources @("Registry", "File", "Service")
    
  if ($catalogResult2) {
    Write-Host "✓ Second catalog created successfully" -ForegroundColor Green
    Write-Host "Catalog file: $($catalogResult2.FilePath)" -ForegroundColor Cyan
    Write-Host "Resources cataloged: $($catalogResult2.ResourceCount)" -ForegroundColor Cyan
  } else {
    Write-Host "✗ Second catalog creation failed" -ForegroundColor Red
  }
} catch {
  Write-Host "✗ Second catalog creation failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: View catalog history
Write-Host "`n=== Test 3: Catalog History ===" -ForegroundColor Green
try {
  $history = Get-DscCatalogHistory -ComputerName co1hcibldprd015 -Limit 5
    
  if ($history.Count -gt 0) {
    Write-Host "✓ Catalog history retrieved successfully" -ForegroundColor Green
    Write-Host "Found $($history.Count) catalog entries:" -ForegroundColor Cyan
        
    foreach ($entry in $history) {
      Write-Host "  - $($entry.catalogName) ($($entry.timestamp))" -ForegroundColor White
    }
  } else {
    Write-Host "No catalog history found" -ForegroundColor Yellow
  }
} catch {
  Write-Host "✗ History retrieval failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Compare catalogs (if we have two catalogs)
Write-Host "`n=== Test 4: Catalog Comparison ===" -ForegroundColor Green
if ($catalogResult -and $catalogResult2) {
  try {
    $diffResult = Compare-DscCatalogs -SourceCatalog $catalogResult.FilePath -TargetCatalog $catalogResult2.FilePath -OutputPath "diff-report.json"
        
    if ($diffResult) {
      Write-Host "✓ Catalog comparison completed successfully" -ForegroundColor Green
      Write-Host "Added: $($diffResult.summary.totalAdded)" -ForegroundColor Green
      Write-Host "Removed: $($diffResult.summary.totalRemoved)" -ForegroundColor Red
      Write-Host "Changed: $($diffResult.summary.totalChanged)" -ForegroundColor Yellow
      Write-Host "Unchanged: $($diffResult.summary.totalUnchanged)" -ForegroundColor Cyan
    } else {
      Write-Host "✗ Catalog comparison failed" -ForegroundColor Red
    }
  } catch {
    Write-Host "✗ Catalog comparison failed: $($_.Exception.Message)" -ForegroundColor Red
  }
} else {
  Write-Host "Skipping comparison test - need two catalogs" -ForegroundColor Yellow
}

# Test 5: Configuration restoration (WhatIf mode)
Write-Host "`n=== Test 5: Configuration Restoration (WhatIf) ===" -ForegroundColor Green
if ($catalogResult) {
  try {
    $restoreResult = Restore-DscSystemConfiguration -CatalogPath $catalogResult.FilePath -ComputerName co1hcibldprd015 -WhatIf
        
    if ($restoreResult) {
      Write-Host "✓ Configuration restoration test completed" -ForegroundColor Green
      Write-Host "WhatIf mode: No actual changes made" -ForegroundColor Cyan
      Write-Host "Would apply: $($restoreResult.TotalCount) resources" -ForegroundColor Cyan
    } else {
      Write-Host "✗ Configuration restoration test failed" -ForegroundColor Red
    }
  } catch {
    Write-Host "✗ Configuration restoration test failed: $($_.Exception.Message)" -ForegroundColor Red
  }
} else {
  Write-Host "Skipping restoration test - need a catalog" -ForegroundColor Yellow
}

Write-Host "`n=== DSC Reverse Test Completed ===" -ForegroundColor Yellow
Write-Host "Check the generated files in the Catalogs, History, and Diffs directories" -ForegroundColor Cyan 