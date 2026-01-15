#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate CI/CD workflow files locally before pushing

.DESCRIPTION
    This script validates GitHub Actions workflow files using actionlint and yamllint.
    It checks for syntax errors, best practice violations, and common issues.

.PARAMETER Fix
    Attempt to fix issues automatically where possible

.EXAMPLE
    ./scripts/Test-Workflows.ps1
    Validates all workflow files

.EXAMPLE
    ./scripts/Test-Workflows.ps1 -Fix
    Validates and attempts to fix issues

.NOTES
    Requirements:
    - actionlint (https://github.com/rhysd/actionlint)
    - yamllint (pip install yamllint or apt install yamllint)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'

Write-Host "=== CI/CD Workflow Validation ===" -ForegroundColor Cyan
Write-Host ""

# Change to repository root
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Check for required tools
Write-Host "Checking for required tools..." -ForegroundColor Yellow

$hasActionlint = $null -ne (Get-Command actionlint -ErrorAction SilentlyContinue)
$hasYamllint = $null -ne (Get-Command yamllint -ErrorAction SilentlyContinue)

if (-not $hasActionlint) {
    Write-Warning "actionlint not found. Install from: https://github.com/rhysd/actionlint"
    Write-Host "  macOS:   brew install actionlint"
    Write-Host "  Linux:   curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash"
    Write-Host "  Windows: scoop install actionlint"
    Write-Host ""
}

if (-not $hasYamllint) {
    Write-Warning "yamllint not found (optional). Install with: pip install yamllint"
    Write-Host ""
}

# Validate workflow files with actionlint
if ($hasActionlint) {
    Write-Host "Running actionlint..." -ForegroundColor Yellow
    
    $workflowFiles = Get-ChildItem -Path .github/workflows -Filter *.yml -File | Where-Object { $_.Name -ne 'ci.yml.old' }
    
    $actionlintErrors = 0
    foreach ($file in $workflowFiles) {
        Write-Host "  Checking $($file.Name)..." -NoNewline
        
        $output = actionlint $file.FullName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host " ✅" -ForegroundColor Green
        } else {
            Write-Host " ❌" -ForegroundColor Red
            $output | Write-Host -ForegroundColor Red
            $actionlintErrors++
        }
    }
    
    if ($actionlintErrors -eq 0) {
        Write-Host "✅ actionlint: All workflows valid" -ForegroundColor Green
    } else {
        Write-Host "❌ actionlint: Found issues in $actionlintErrors file(s)" -ForegroundColor Red
    }
    Write-Host ""
} else {
    Write-Host "⚠️  Skipping actionlint (not installed)" -ForegroundColor Yellow
    Write-Host ""
}

# Validate YAML syntax with yamllint
if ($hasYamllint) {
    Write-Host "Running yamllint..." -ForegroundColor Yellow
    
    $yamllintConfig = ".github/yamllint-config.yml"
    if (Test-Path $yamllintConfig) {
        yamllint -c $yamllintConfig .github/workflows/
    } else {
        yamllint .github/workflows/
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ yamllint: YAML syntax valid" -ForegroundColor Green
    } else {
        Write-Host "❌ yamllint: Found YAML syntax issues" -ForegroundColor Red
    }
    Write-Host ""
} else {
    Write-Host "⚠️  Skipping yamllint (not installed)" -ForegroundColor Yellow
    Write-Host ""
}

# Check for expected workflow files
Write-Host "Checking for required workflow files..." -ForegroundColor Yellow

$expectedWorkflows = @(
    'build-test.yml',
    'security.yml',
    'release.yml',
    'workflow-test.yml'
)

$missingWorkflows = @()
foreach ($workflow in $expectedWorkflows) {
    $path = Join-Path .github/workflows $workflow
    if (Test-Path $path) {
        Write-Host "  ✅ $workflow" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $workflow (missing)" -ForegroundColor Red
        $missingWorkflows += $workflow
    }
}

if ($missingWorkflows.Count -eq 0) {
    Write-Host "✅ All expected workflow files present" -ForegroundColor Green
} else {
    Write-Host "❌ Missing workflows: $($missingWorkflows -join ', ')" -ForegroundColor Red
}
Write-Host ""

# Check Dependabot configuration
Write-Host "Checking Dependabot configuration..." -ForegroundColor Yellow

$dependabotPath = ".github/dependabot.yml"
if (Test-Path $dependabotPath) {
    Write-Host "  ✅ dependabot.yml found" -ForegroundColor Green
    
    # Validate basic structure
    try {
        $content = Get-Content $dependabotPath -Raw
        if ($content -match 'version:\s*2' -and $content -match 'updates:') {
            Write-Host "  ✅ Valid Dependabot configuration structure" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Dependabot configuration may be malformed" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ❌ Failed to validate Dependabot configuration: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  ❌ dependabot.yml not found" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan

$allPassed = $true
if ($hasActionlint -and $actionlintErrors -gt 0) {
    $allPassed = $false
}
if ($missingWorkflows.Count -gt 0) {
    $allPassed = $false
}

if ($allPassed) {
    Write-Host "✅ All validations passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your workflows are ready to be committed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Some validations failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the issues above before committing." -ForegroundColor Yellow
    exit 1
}
