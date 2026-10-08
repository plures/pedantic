[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'StartupMode',
    Justification = 'Forwarded to child modules during umbrella initialization.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'ModuleStartupOptions',
    Justification = 'Forwarded to matching child modules during umbrella initialization.'
)]
param(
    [ValidateSet('Notify', 'Quiet', 'Prompt', 'Initialize')]
    [string]$StartupMode = 'Notify',

    [hashtable]$ModuleStartupOptions = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DTMSUtilityModules = @(
    [pscustomobject]@{
        Name = 'DTMS.Configuration'
        Manifest = Join-Path $PSScriptRoot `
            '..\DTMS.Configuration\DTMS.Configuration.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.Runway'
        Manifest = Join-Path $PSScriptRoot '..\DTMS.Runway\DTMS.Runway.psd1'
        SupportsStartup = $true
    }
    [pscustomobject]@{
        Name = 'DTMS.Runway.Federation'
        Manifest = Join-Path $PSScriptRoot `
            '..\DTMS.Runway.Federation\DTMS.Runway.Federation.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.Runway.Dfs'
        Manifest = Join-Path $PSScriptRoot '..\DTMS.Runway.Dfs\DTMS.Runway.Dfs.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.Transfer'
        Manifest = Join-Path $PSScriptRoot '..\DTMS.Transfer\DTMS.Transfer.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.OpenSSH'
        Manifest = Join-Path $PSScriptRoot '..\DTMS.OpenSSH\DTMS.OpenSSH.psd1'
        SupportsStartup = $true
    }
    [pscustomobject]@{
        Name = 'DTMS.Forge'
        Manifest = Join-Path $PSScriptRoot '..\DTMS.Forge\DTMS.Forge.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.OSInstall'
        Manifest = Join-Path $PSScriptRoot `
            '..\DTMS.OSInstall\DTMS.OSInstall.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.WinIPAK'
        Manifest = Join-Path $PSScriptRoot `
            '..\DTMS.WinIPAK\DTMS.WinIPAK.psd1'
        SupportsStartup = $false
    }
    [pscustomobject]@{
        Name = 'DTMS.VMHelper'
        Manifest = Join-Path $PSScriptRoot '..\DTMS.VMHelper\DTMS.VMHelper.psd1'
        SupportsStartup = $true
    }
)

foreach ($utilityModule in $script:DTMSUtilityModules) {
    if (-not (Test-Path -LiteralPath $utilityModule.Manifest -PathType Leaf)) {
        throw "DTMS utility module '$($utilityModule.Name)' was not found at '$($utilityModule.Manifest)'."
    }
    $importParameters = @{
        Name = $utilityModule.Manifest
        Global = $true
        Force = $true
        ErrorAction = 'Stop'
    }
    if ($utilityModule.SupportsStartup) {
        $startupOptions = if ($ModuleStartupOptions.ContainsKey($utilityModule.Name)) {
            $ModuleStartupOptions[$utilityModule.Name]
        } else {
            @{}
        }
        $importParameters.ArgumentList = @($StartupMode, $startupOptions)
    }
    Import-Module @importParameters
}

function Get-DTMSUtilitiesModule {
    <#
    .SYNOPSIS
    Reports modules loaded by the DTMS.Utilities umbrella.
    #>
    [CmdletBinding()]
    param()

    foreach ($utilityModule in $script:DTMSUtilityModules) {
        $loadedModule = Get-Module -Name $utilityModule.Name |
            Sort-Object Version -Descending |
            Select-Object -First 1
        [pscustomobject]@{
            PSTypeName = 'DTMS.Utilities.Module'
            Name = $utilityModule.Name
            Version = if ($loadedModule) { $loadedModule.Version } else { $null }
            Loaded = $null -ne $loadedModule
            ModuleBase = if ($loadedModule) { $loadedModule.ModuleBase } else { $null }
            Manifest = $utilityModule.Manifest
        }
    }
}

function Get-DTMSUtilitiesReadiness {
    <#
    .SYNOPSIS
    Aggregates readiness for all modules loaded by DTMS.Utilities.
    #>
    [CmdletBinding()]
    param()

    $results = @()
    if (Get-Command Get-DTMSConfiguration -ErrorAction SilentlyContinue) {
        $configuration = Get-DTMSConfiguration
        $configurationFilePresent = Test-Path `
            -LiteralPath $configuration.ConfigurationPath `
            -PathType Leaf
        $results += New-DurableOperationReadinessResult `
            -Module 'DTMS.Configuration' `
            -Capability 'CentralConfiguration' `
            -Status $(if ($configurationFilePresent) {
                'Ready'
            } else {
                'NotConfigured'
            }) `
            -Required $false `
            -Message $(if ($configurationFilePresent) {
                "Central configuration '$($configuration.ConfigurationPath)' is available."
            } else {
                'Built-in organization defaults are active; no central JSON file exists.'
            }) `
            -RemediationCommand $(if ($configurationFilePresent) {
                $null
            } else {
                'Initialize-DTMSConfiguration'
            })
        $federationConfigured = @(
            $configuration.Federation.UtilityServers
        ).Count -gt 0
        $results += New-DurableOperationReadinessResult `
            -Module 'DTMS.Runway.Federation' `
            -Capability 'FederatedOperationIndex' `
            -Status $(if ($federationConfigured) {
                'Ready'
            } else {
                'NotConfigured'
            }) `
            -Required $false `
            -Message $(if ($federationConfigured) {
                'Runway utility-server federation is configured.'
            } else {
                'No Runway federation utility servers are configured.'
            }) `
            -RemediationCommand $(if ($federationConfigured) {
                $null
            } else {
                'Initialize-DurableOperationFederation'
            })
    }
    if (Get-Command Get-DurableOperationReadiness -ErrorAction SilentlyContinue) {
        $results += @(Get-DurableOperationReadiness)
    }
    if (Get-Command Get-DurableTransferReadiness -ErrorAction SilentlyContinue) {
        $results += @(Get-DurableTransferReadiness)
    }
    if (Get-Command Get-SSHUtilitiesReadiness -ErrorAction SilentlyContinue) {
        $results += @(Get-SSHUtilitiesReadiness)
    }
    if (Get-Command Get-DurableOperationRegistryConfiguration -ErrorAction SilentlyContinue) {
        $registry = Get-DurableOperationRegistryConfiguration
        $results += New-DurableOperationReadinessResult `
            -Module 'DTMS.Runway.Dfs' `
            -Capability 'DistributedRegistry' `
            -Status $(if ($registry.Enabled) {
                'Ready'
            } elseif ($registry.ConfigurationPresent) {
                'Unavailable'
            } else {
                'NotConfigured'
            }) `
            -Required $false `
            -Message $(if ($registry.Enabled) {
                "Distributed registry '$($registry.NamespacePath)' is available."
            } elseif ($registry.ConfigurationPresent) {
                "Distributed registry '$($registry.NamespacePath)' is configured but unavailable."
            } else {
                'No shared Runway DFS registry is configured.'
            }) `
            -RemediationCommand $(if ($registry.Enabled) {
                $null
            } else {
                'Initialize-DurableOperationDfsRegistry'
            })
    }
    if (Get-Command Get-VMHelperRegistryConfiguration -ErrorAction SilentlyContinue) {
        $vmRegistry = Get-VMHelperRegistryConfiguration
        $results += New-DurableOperationReadinessResult `
            -Module 'DTMS.VMHelper' `
            -Capability 'DistributedTransferRegistry' `
            -Status $(if ($vmRegistry.Enabled) {
                'Ready'
            } elseif ($vmRegistry.ConfigurationPresent) {
                'Unavailable'
            } else {
                'NotConfigured'
            }) `
            -Required $false `
            -Message $(if ($vmRegistry.Enabled) {
                "VM transfer registry '$($vmRegistry.NamespacePath)' is available."
            } elseif ($vmRegistry.ConfigurationPresent) {
                "VM transfer registry '$($vmRegistry.NamespacePath)' is configured but unavailable."
            } else {
                'VMHelper is operating with target-local transfer state.'
            }) `
            -RemediationCommand $(if ($vmRegistry.Enabled) {
                $null
            } else {
                'Initialize-VMResourceTransferRegistry'
            })
    }
    $results |
        Group-Object Module, Capability |
        ForEach-Object { $_.Group | Select-Object -First 1 } |
        Sort-Object Module, Capability
}

Export-ModuleMember -Function @(
    'Get-DTMSUtilitiesModule'
    'Get-DTMSUtilitiesReadiness'
)
