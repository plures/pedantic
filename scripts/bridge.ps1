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
    [ValidateSet('generate', 'test', 'set', 'prereqs', 'resources', 'installResource', 'cmdb')]
    [string]$Command,

    [string]$DslPath,
    [string[]]$ResourceTypes,
    [string]$ResourceType,
    [string]$ProjectPath,
    [string]$CatalogPath,

    [switch]$OutputJson,
    [switch]$WhatIf,
    [switch]$VerboseOutput,
    [switch]$IncludeResources
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
        'cmdb' {
            $catalogs = @()

            function Add-CatalogSource {
                param(
                    [Parameter(Mandatory)] [object]$Catalog,
                    [Parameter(Mandatory)] [string]$SourcePath
                )
                if ($Catalog.PSObject.Properties.Name -contains 'meta' -and $Catalog.meta) {
                    $Catalog.meta | Add-Member -NotePropertyName sourcePath -NotePropertyValue $SourcePath -Force
                }
                else {
                    $Catalog | Add-Member -NotePropertyName meta -NotePropertyValue ([ordered]@{ sourcePath = $SourcePath }) -Force
                }
            }

            function Read-CatalogFile {
                param([Parameter(Mandatory)] [string]$Path)
                try {
                    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
                    if (-not $raw) { return $null }
                    $catalog = $raw | ConvertFrom-Json -ErrorAction Stop
                    if ($catalog) {
                        Add-CatalogSource -Catalog $catalog -SourcePath $Path
                        return $catalog
                    }
                }
                catch {
                    $warnings += "Failed to read catalog '$Path': $($_.Exception.Message)"
                }
                return $null
            }

            function New-LocalCatalog {
                param([Parameter(Mandatory)] [string]$OutputPath)

                $meta = [ordered]@{
                    generatedBy      = 'Pedantic.Bridge'
                    generatedAt      = (Get-Date).ToString('o')
                    computer         = $env:COMPUTERNAME
                    includeResources = [bool]$IncludeResources
                }

                $catalog = [ordered]@{ meta = $meta; resources = @(); configuration = @{} }

                try {
                    $os = Get-CimInstance Win32_OperatingSystem
                    $bios = Get-CimInstance Win32_BIOS
                    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
                    $nics = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

                    $catalog.configuration = [ordered]@{
                        OS = [ordered]@{
                            Caption     = $os.Caption
                            Version     = $os.Version
                            BuildNumber = $os.BuildNumber
                            InstallDate = $os.InstallDate
                        }
                        BIOS = [ordered]@{
                            Manufacturer     = $bios.Manufacturer
                            SMBIOSBIOSVersion = $bios.SMBIOSBIOSVersion
                            SerialNumber     = $bios.SerialNumber
                        }
                        CPU = [ordered]@{
                            Name              = $cpu.Name
                            Cores             = $cpu.NumberOfCores
                            LogicalProcessors = $cpu.NumberOfLogicalProcessors
                        }
                        Network = $nics | ForEach-Object {
                            [ordered]@{ Name = $_.Name; Mac = $_.MacAddress; LinkSpeed = $_.LinkSpeed }
                        }
                    }
                }
                catch {
                    $warnings += "Failed to gather system info: $($_.Exception.Message)"
                }

                if ($IncludeResources) {
                    try {
                        $resources = & dsc resource list --output-format json 2>&1 | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($resources) {
                            $catalog.resources = $resources | ForEach-Object {
                                [ordered]@{ type = $_.type; version = $_.version; kind = $_.kind; description = $_.description }
                            }
                        }
                    }
                    catch {
                        $warnings += "Failed to list DSC resources: $($_.Exception.Message)"
                    }
                }

                $outputDir = Split-Path -Parent $OutputPath
                if ($outputDir -and -not (Test-Path $outputDir)) { New-Item -Path $outputDir -ItemType Directory -Force | Out-Null }
                $catalog | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding UTF8
                return Get-Item $OutputPath
            }

            if ($CatalogPath) {
                if (-not (Test-Path $CatalogPath)) {
                    $errors += "CatalogPath not found: $CatalogPath"
                }
                else {
                    $item = Get-Item $CatalogPath
                    if ($item.PSIsContainer) {
                        $files = Get-ChildItem -Path $CatalogPath -Filter *.json -File
                    }
                    else {
                        $files = @($item)
                    }
                    foreach ($file in $files) {
                        $cat = Read-CatalogFile -Path $file.FullName
                        if ($cat) { $catalogs += $cat }
                    }
                }
            }
            else {
                $tempPath = Join-Path $env:TEMP ("pedantic-cmdb-{0}.json" -f ([guid]::NewGuid().ToString('n')))
                $catalogItem = $null
                try {
                    $catalogItem = New-DscSystemCatalog -OutputPath $tempPath -IncludeResources:$IncludeResources -ErrorAction Stop
                }
                catch {
                    $warnings += "New-DscSystemCatalog unavailable or failed: $($_.Exception.Message). Falling back to local catalog generation."
                }

                if (-not $catalogItem) {
                    try { $catalogItem = New-LocalCatalog -OutputPath $tempPath } catch { $errors += "Failed to generate local catalog: $($_.Exception.Message)" }
                }

                if (Test-Path $tempPath) {
                    $cat = Read-CatalogFile -Path $tempPath
                    if ($cat) { $catalogs += $cat }
                }
            }

            $data = @{
                catalogs = $catalogs
            }
            $result = "CMDB catalog loaded"
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
