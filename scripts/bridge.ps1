#!/usr/bin/env pwsh
<#
.SYNOPSIS
    PowerShell bridge script for Pedantic VS Code extension
.DESCRIPTION
    This script provides a JSON-based interface for the VS Code extension to
    communicate with PowerShell DSC operations.
.PARAMETER Command
    The command to execute: generate, test, set, prereqs, resources, installResource
.PARAMETER DslPath
    Path to the DSL file to process (generate/test/set only)
.PARAMETER ResourceTypes
    Resource types to ensure/inspect (prereqs/resources)
.PARAMETER ResourceType
    Single resource type to install (installResource)
.PARAMETER OutputJson
    Output results as JSON for programmatic consumption
.PARAMETER WhatIf
    Perform a dry run without making changes
.PARAMETER VerboseOutput
    Enable verbose output
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('generate', 'test', 'set', 'prereqs', 'resources', 'installResource')]
    [string]$Command,

    [string]$DslPath,
    [string[]]$ResourceTypes,
    [string]$ResourceType,
    [string]$ProjectPath,

    [switch]$OutputJson,
    [switch]$WhatIf,
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$errors = @()
$warnings = @()
$result = $null
$data = $null

try {
    # Try to import the Pedantic module
    $modulePath = Join-Path $PSScriptRoot '..' 'Pedantic.psd1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -ErrorAction Stop
    } else {
        # Try to import from installed modules
        Import-Module Pedantic -ErrorAction Stop
    }

    # Validate DSL path for config operations
    if ($Command -in @('generate','test','set')) {
        if (-not $DslPath) { throw "DslPath is required for command '$Command'" }
        if (-not (Test-Path $DslPath)) { throw "DSL file not found: $DslPath" }
    }

    switch ($Command) {
        'generate' {
            Write-Host "Generating DSC configuration from $DslPath..."
            $result = @"
# Generated DSC Configuration
# Source: $DslPath
# Note: This is a placeholder implementation
# The actual generation logic needs to be implemented in the Pedantic module

`$schema: https://aka.ms/dsc/schemas/2024/04/config/document.json
resources: []
"@
        }
        'test' {
            Write-Host "Testing DSC configuration: $DslPath..."
            $result = "Test operation placeholder - DSC v3 test not yet implemented"
        }
        'set' {
            if ($WhatIf) {
                Write-Host "WhatIf: Would apply DSC configuration from $DslPath..."
                $result = "WhatIf: Set operation not executed"
            } else {
                Write-Host "Applying DSC configuration from $DslPath..."
                $result = "Set operation placeholder - DSC v3 set not yet implemented"
            }
        }
        'prereqs' {
            $dscInstalled = $false
            $dscVersion = $null
            $commonResources = if ($ResourceTypes -and $ResourceTypes.Count -gt 0) { $ResourceTypes } else { @(
                'Microsoft.DSC/Archive',
                'Microsoft.DSC/File',
                'Microsoft.DSC/Service',
                'Microsoft.Windows/Registry',
                'Microsoft.Windows/File',
                'Microsoft.Windows/Service'
            ) }

            try {
                $dscCmd = Get-Command 'dsc.exe' -ErrorAction Stop
                $dscInstalled = $true
                try { $dscVersion = (& $dscCmd.Source '--version' 2>$null).Trim() } catch { $warnings += "Could not read DSC version: $($_.Exception.Message)" }
            }
            catch {
                $dscInstalled = $false
                $warnings += $_.Exception.Message
            }

            if (-not $dscInstalled) {
                try {
                    Update-DscInstallerCache -Force -Quiet:$VerboseOutput.IsPresent | Out-Null
                    $null = Repair-DscInstallation -Quiet:$VerboseOutput.IsPresent -Force
                    $dscInstalled = (Get-Command 'dsc.exe' -ErrorAction SilentlyContinue) -ne $null
                }
                catch {
                    $errors += "DSC installation attempt failed: $($_.Exception.Message)"
                }
            }
            else {
                try { $null = Repair-DscInstallation -Quiet:$VerboseOutput.IsPresent } catch { $warnings += "DSC repair check failed: $($_.Exception.Message)" }
            }

            $resourceStatus = $null
            try {
                $resourceStatus = Test-DscResourceAvailability -ResourceTypes $commonResources -Force -Quiet:$VerboseOutput.IsPresent
            }
            catch {
                $errors += "Resource availability check failed: $($_.Exception.Message)"
            }

            $installedResources = @()
            try {
                $installedResources = (& dsc resource list --output-format json 2>$null | ConvertFrom-Json)
            }
            catch {
                $warnings += "Could not enumerate installed resources: $($_.Exception.Message)"
            }

            $data = @{
                dscInstalled    = $dscInstalled
                dscVersion      = $dscVersion
                commonResources = @{
                    requested = $commonResources
                    available = $resourceStatus?.AvailableResources
                    missing   = $resourceStatus?.MissingResources
                    success   = $resourceStatus?.Success
                }
                installedResources = $installedResources
            }
            $result = "Prerequisite check completed"
        }
        'resources' {
            $installedResources = @()
            try {
                $installedResources = (& dsc resource list --output-format json 2>$null | ConvertFrom-Json)
            }
            catch {
                $warnings += "Could not enumerate installed resources: $($_.Exception.Message)"
            }

            $cachedResources = @()
            try {
                $cache = Get-ResourceCache
                foreach ($name in $cache.AvailableResources.PSObject.Properties.Name) {
                    $item = $cache.AvailableResources.$name
                    $typeName = if ($item.PSObject.Properties.Name -contains 'Type' -and $item.Type) { $item.Type }
                               elseif ($item.PSObject.Properties.Name -contains 'Name' -and $item.Name) { $item.Name }
                               elseif ($item.PSObject.Properties.Name -contains 'OriginalType' -and $item.OriginalType) { $item.OriginalType }
                               else { $name }
                    $cachedResources += [pscustomobject]@{
                        Key     = $name
                        Type    = $typeName
                        Version = $item.Version
                        Source  = $item.Source
                        Path    = $item.LocalPath
                    }
                }
            }
            catch {
                $warnings += "Could not read resource cache: $($_.Exception.Message)"
            }

            $catalog = $null
            try {
                $catalog = Get-DscResourceCatalog -Quiet
            }
            catch {
                $warnings += "Could not retrieve resource catalog: $($_.Exception.Message)"
            }

            $data = @{
                installed = $installedResources
                cached    = $cachedResources
                catalog   = $catalog
            }
            $result = "Resource inventory collected"
        }
        'installResource' {
            if (-not $ResourceType) { throw "ResourceType is required for installResource" }
            $installSuccess = $false
            try {
                $installResult = Install-DscResourceOffline -ResourceType $ResourceType -Quiet
                $installSuccess = $installResult -ne $null
            }
            catch {
                $errors += "Resource install failed: $($_.Exception.Message)"
            }

            $data = @{
                resourceType = $ResourceType
                installed    = $installSuccess
            }
            $result = "Resource install attempted"
        }
    }

    $duration = ((Get-Date) - $startTime).TotalMilliseconds
    $response = @{
        success  = ($errors.Count -eq 0)
        output   = $result
        data     = $data
        errors   = $errors
        warnings = $warnings
        duration = $duration
    }
}
catch {
    $duration = ((Get-Date) - $startTime).TotalMilliseconds
    $response = @{
        success  = $false
        output   = $null
        data     = $data
        errors   = @($_.Exception.Message)
        warnings = $warnings
        duration = $duration
    }
}

if ($OutputJson) {
    $response | ConvertTo-Json -Depth 10 -Compress
} else {
    if ($response.success) {
        $response.output
    } else {
        Write-Error ($response.errors -join "`n")
    }
}
