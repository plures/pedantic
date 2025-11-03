#requires -Version 7.2

<#
.SYNOPSIS
    Verify ADP integration setup status.

.DESCRIPTION
    This script checks the status of ADP (Automated Development Process) integration
    in the StateSmith project and provides guidance on next steps.

.EXAMPLE
    .\Verify-AdpSetup.ps1
    Checks ADP integration status and displays findings.

.NOTES
    Part of the StateSmith ADP integration effort.
#>

[CmdletBinding()]
param()

function Test-AdpStatus {
    Write-Host "`n=== ADP Integration Status Check ===" -ForegroundColor Cyan
    Write-Host ""

    # Check for ADP submodule
    if (Test-Path '.adp') {
        Write-Host "[✓] ADP directory found at .adp" -ForegroundColor Green
        
        if (Test-Path '.adp/scripts/init.ps1') {
            Write-Host "[✓] ADP initialization script found" -ForegroundColor Green
            $adpVersion = "Unknown"
            if (Test-Path '.adp/version.txt') {
                $adpVersion = (Get-Content '.adp/version.txt' -Raw).Trim()
            }
            Write-Host "    ADP Version: $adpVersion" -ForegroundColor Gray
        } else {
            Write-Host "[!] ADP directory exists but initialization script not found" -ForegroundColor Yellow
            Write-Host "    Expected: .adp/scripts/init.ps1" -ForegroundColor Gray
        }
    } elseif (Test-Path '.adp-placeholder') {
        Write-Host "[!] ADP placeholder found - ADP not yet installed" -ForegroundColor Yellow
        Write-Host "    Action required: Install ADP submodule" -ForegroundColor Gray
    } else {
        Write-Host "[✗] No ADP directory or placeholder found" -ForegroundColor Red
    }

    # Check for configuration file
    if (Test-Path 'adp-config.json') {
        Write-Host "[✓] ADP configuration file found (adp-config.json)" -ForegroundColor Green
        try {
            $config = Get-Content 'adp-config.json' -Raw | ConvertFrom-Json
            Write-Host "    Project: $($config.project.name)" -ForegroundColor Gray
            Write-Host "    Components: $($config.components.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        } catch {
            Write-Host "    [!] Unable to parse configuration file" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[!] ADP configuration file not found" -ForegroundColor Yellow
    }

    # Check for integration documentation
    if (Test-Path 'ADP-INTEGRATION.md') {
        Write-Host "[✓] ADP integration documentation found" -ForegroundColor Green
    } else {
        Write-Host "[!] ADP integration documentation not found" -ForegroundColor Yellow
    }

    # Check for .gitmodules
    if (Test-Path '.gitmodules') {
        Write-Host "[✓] Git submodules configured" -ForegroundColor Green
        $submodules = git config --file .gitmodules --get-regexp path
        if ($submodules -match '\.adp') {
            Write-Host "    ADP submodule registered" -ForegroundColor Gray
        }
    } elseif (Test-Path '.gitmodules.template') {
        Write-Host "[!] .gitmodules template found - not yet activated" -ForegroundColor Yellow
        Write-Host "    Action required: Initialize ADP submodule" -ForegroundColor Gray
    } else {
        Write-Host "[!] No submodule configuration found" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== Next Steps ===" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path '.adp') -and (Test-Path '.adp-placeholder')) {
        Write-Host "To complete ADP integration:" -ForegroundColor White
        Write-Host "  1. Ensure you have access to https://github.com/plures/ADP.git" -ForegroundColor Gray
        Write-Host "  2. Run: git submodule add https://github.com/plures/ADP.git .adp" -ForegroundColor Gray
        Write-Host "  3. Run: git submodule update --init --recursive" -ForegroundColor Gray
        Write-Host "  4. Run: ./.adp/scripts/init.ps1" -ForegroundColor Gray
        Write-Host "  5. Remove placeholder: Remove-Item -Recurse .adp-placeholder" -ForegroundColor Gray
        Write-Host ""
        Write-Host "For detailed instructions, see: ADP-INTEGRATION.md" -ForegroundColor Yellow
    } elseif (Test-Path '.adp') {
        Write-Host "ADP appears to be installed. You can:" -ForegroundColor White
        Write-Host "  - Run ADP initialization: ./.adp/scripts/init.ps1" -ForegroundColor Gray
        Write-Host "  - Check ADP documentation: ./.adp/README.md" -ForegroundColor Gray
        Write-Host "  - Review configuration: adp-config.json" -ForegroundColor Gray
    }

    Write-Host ""
}

# Run the status check
Test-AdpStatus
