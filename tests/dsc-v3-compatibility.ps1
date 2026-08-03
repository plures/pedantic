$ErrorActionPreference = 'Stop'

if (-not (Get-Command dsc -ErrorAction SilentlyContinue)) {
    throw 'DSC v3 CLI was not found on PATH.'
}

$dscVersion = (& dsc --version).Trim()
Write-Host "Testing custom resources with dsc $dscVersion"

# DSC v3 (3.1+) restricts BOTH manifest discovery and executable resolution to
# DSC_RESOURCE_PATH when it is set, so setting it to a resource's own directory
# (needed for manifest discovery) also breaks its ability to find `pwsh` on the
# system PATH. Fix: append pwsh's real directory to DSC_RESOURCE_PATH instead of
# replacing it, so both the manifest AND the pwsh executable are resolvable.
$pwshDirectory = Split-Path (Get-Command pwsh).Source -Parent

function Invoke-DscResourceCheck {
    param(
        [Parameter(Mandatory)] [string] $ResourceDirectory,
        [Parameter(Mandatory)] [string] $ResourceType,
        [Parameter(Mandatory)] [string] $ExpectedKind
    )

    $previousPath = $env:DSC_RESOURCE_PATH
    try {
        $env:DSC_RESOURCE_PATH = "$ResourceDirectory$([IO.Path]::PathSeparator)$pwshDirectory"
        Push-Location $ResourceDirectory

        $manifest = (& dsc resource list $ResourceType | ConvertFrom-Json)
        if ($manifest.type -ne $ResourceType) {
            throw "dsc did not discover $ResourceType."
        }
        if ($manifest.kind -ne $ExpectedKind) {
            throw "Expected $ResourceType to have kind '$ExpectedKind', got '$($manifest.kind)'."
        }
        if ($manifest.capabilities -notcontains 'export') {
            throw "dsc did not report export capability for $ResourceType."
        }

        Write-Host "DSC_DISCOVERED $ResourceType kind=$ExpectedKind export=true"
    }
    finally {
        Pop-Location
        $env:DSC_RESOURCE_PATH = $previousPath
    }
}

$root = Split-Path $PSScriptRoot -Parent
$simpleDirectory = Join-Path $root 'Resources/SimpleDSC.PackageInstaller'
$ansibleDirectory = Join-Path $root 'Resources/Pedantic.Ansible.Module'

Invoke-DscResourceCheck -ResourceDirectory $simpleDirectory -ResourceType 'SimpleDSC/PackageInstaller' -ExpectedKind 'resource'
Invoke-DscResourceCheck -ResourceDirectory $ansibleDirectory -ResourceType 'Pedantic.Ansible/Module' -ExpectedKind 'adapter'

$previousPath = $env:DSC_RESOURCE_PATH
try {
    $env:DSC_RESOURCE_PATH = "$simpleDirectory$([IO.Path]::PathSeparator)$pwshDirectory"
    Push-Location $simpleDirectory
    $desiredState = '{"name":"dsc-v3-ci","packages":["Git.Git"],"method":"winget","ensure":"Present"}'
    $result = & dsc resource get --resource SimpleDSC/PackageInstaller --input $desiredState | ConvertFrom-Json
    if ($null -eq $result.actualState) {
        throw 'dsc resource get did not return actualState for SimpleDSC/PackageInstaller.'
    }
    Write-Host 'DSC_RESOURCE_GET_OK SimpleDSC/PackageInstaller'
}
finally {
    Pop-Location
    $env:DSC_RESOURCE_PATH = $previousPath
}
