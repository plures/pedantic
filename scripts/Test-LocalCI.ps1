#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run pre-commit checks locally

.DESCRIPTION
    This script runs the same checks that will run in CI/CD:
    - PSScriptAnalyzer
    - Pester tests
    - Module manifest validation

.PARAMETER SkipTests
    Skip running Pester tests

.PARAMETER SkipLinter
    Skip running PSScriptAnalyzer

.EXAMPLE
    ./scripts/Test-LocalCI.ps1
    Runs all checks

.EXAMPLE
    ./scripts/Test-LocalCI.ps1 -SkipTests
    Only runs linter, skips tests

.NOTES
    This helps catch issues before pushing to GitHub.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipTests,
    
    [Parameter()]
    [switch]$SkipLinter
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Local CI/CD Checks ===" -ForegroundColor Cyan
Write-Host ""

# Change to repository root
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Track overall status
$allPassed = $true

# PSScriptAnalyzer
if (-not $SkipLinter) {
    Write-Host "Running PSScriptAnalyzer..." -ForegroundColor Yellow
    
    # Ensure PSScriptAnalyzer is installed
    if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
        Write-Host "Installing PSScriptAnalyzer..." -ForegroundColor Yellow
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
    }
    
    Import-Module PSScriptAnalyzer
    
    $settingsFile = "./PSScriptAnalyzerSettings.psd1"
    if (Test-Path $settingsFile) {
        Write-Host "Using settings file: $settingsFile" -ForegroundColor Gray
        $results = Invoke-ScriptAnalyzer -Path . -Recurse -Settings $settingsFile -ReportSummary
    } else {
        Write-Host "Using default PSScriptAnalyzer settings" -ForegroundColor Gray
        $results = Invoke-ScriptAnalyzer -Path . -Recurse -ReportSummary
    }
    
    # Filter to only show Warnings and Errors
    $issues = $results | Where-Object { $_.Severity -in @('Warning', 'Error') }
    
    if ($issues) {
        Write-Host ""
        $issues | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize
        
        $errorCount = ($issues | Where-Object { $_.Severity -eq 'Error' }).Count
        $warningCount = ($issues | Where-Object { $_.Severity -eq 'Warning' }).Count
        
        Write-Host "PSScriptAnalyzer Summary: $errorCount error(s), $warningCount warning(s)" -ForegroundColor Yellow
        
        if ($errorCount -gt 0) {
            Write-Host "❌ PSScriptAnalyzer found errors" -ForegroundColor Red
            $allPassed = $false
        } else {
            Write-Host "⚠️  PSScriptAnalyzer found warnings (won't block CI)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✅ PSScriptAnalyzer: No issues found" -ForegroundColor Green
    }
    Write-Host ""
}

# Pester Tests
if (-not $SkipTests) {
    Write-Host "Running Pester tests..." -ForegroundColor Yellow
    
    if (-not (Test-Path 'tests')) {
        Write-Host "⚠️  No tests directory found, skipping tests" -ForegroundColor Yellow
        Write-Host ""
    } else {
        # Ensure Pester 5.x is installed
        $pesterModule = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $pesterModule -or $pesterModule.Version.Major -lt 5) {
            Write-Host "Installing Pester 5.x..." -ForegroundColor Yellow
            Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
        }
        
        Import-Module Pester -MinimumVersion 5.0.0
        
        $config = New-PesterConfiguration
        $config.Run.Path = 'tests'
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Detailed'
        $config.CodeCoverage.Enabled = $false  # Disable for local runs
        $config.TestResult.Enabled = $false
        
        Write-Host ""
        $result = Invoke-Pester -Configuration $config
        
        Write-Host ""
        Write-Host "Test Summary:" -ForegroundColor Cyan
        Write-Host "  Passed:  $($result.PassedCount)" -ForegroundColor Green
        Write-Host "  Failed:  $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Gray' })
        Write-Host "  Skipped: $($result.SkippedCount)" -ForegroundColor Gray
        Write-Host "  Total:   $($result.TotalCount)"
        
        if ($result.FailedCount -gt 0) {
            Write-Host "❌ Tests failed" -ForegroundColor Red
            $allPassed = $false
        } else {
            Write-Host "✅ All tests passed" -ForegroundColor Green
        }
        Write-Host ""
    }
}

# Module Manifest Validation
Write-Host "Validating module manifests..." -ForegroundColor Yellow

$manifestFiles = Get-ChildItem -Path . -Filter *.psd1 -File | Where-Object { 
    $_.Name -ne 'PSScriptAnalyzerSettings.psd1' 
}

$manifestErrors = 0
foreach ($manifest in $manifestFiles) {
    Write-Host "  Checking $($manifest.Name)..." -NoNewline
    
    try {
        $null = Test-ModuleManifest -Path $manifest.FullName -ErrorAction Stop
        Write-Host " ✅" -ForegroundColor Green
    } catch {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        $manifestErrors++
        $allPassed = $false
    }
}

if ($manifestErrors -eq 0) {
    Write-Host "✅ All module manifests valid" -ForegroundColor Green
} else {
    Write-Host "❌ Found issues in $manifestErrors manifest(s)" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "=== Check Summary ===" -ForegroundColor Cyan

if ($allPassed) {
    Write-Host "✅ All checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your changes are ready to commit." -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Some checks failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the issues above before committing." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Tip: Run with -SkipTests or -SkipLinter to skip specific checks" -ForegroundColor Gray
    exit 1
}
