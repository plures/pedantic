<#
.SYNOPSIS
  Builds a distributable package zip for the StateSmith DSC toolkit.

.DESCRIPTION
  Creates an output folder under ./dist, collects module files (StateSmith.DSC),
  resources (Resources/, Installers/), and docs, and zips them into a versioned artifact.
  Embeds a small metadata file with build time and commit info if available.

.PARAMETER Version
  Version tag for the artifact (default: read from StateSmith.DSC.psd1 ModuleVersion, or '0.0.0-local').

.PARAMETER OutputDir
  Output directory for artifacts (default: ./dist).

.PARAMETER IncludeTests
  Include tests/ in the artifact (off by default).

.EXAMPLE
  ./Build-Package.ps1 -Version 0.9.0

.EXAMPLE
  ./Build-Package.ps1
  # Uses module version if found
#>
[CmdletBinding()] param(
  [string]$Version,
  [string]$OutputDir = (Join-Path $PSScriptRoot 'dist'),
  [switch]$IncludeTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ModuleVersionFromManifest {
  $manifestPath = Join-Path $PSScriptRoot 'StateSmith.DSC.psd1'
  if (-not (Test-Path $manifestPath)) { return $null }
  try {
    $data = Import-PowerShellDataFile -Path $manifestPath
    return $data.ModuleVersion
  } catch { return $null }
}

function Get-CommitInfo {
  try {
    $sha = (git rev-parse --short HEAD 2>$null)
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($sha) { return @{ Sha = "$sha"; Branch = "$branch" } }
  } catch { }
  return @{ Sha = ''; Branch = '' }
}

function Copy-IfExists {
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [string]$Destination
  )
  if (Test-Path $Path) { Copy-Item -Path $Path -Destination $Destination -Recurse -Force }
}

# Resolve version
if (-not $Version) { $Version = Get-ModuleVersionFromManifest }
if (-not $Version) { $Version = '0.0.0-local' }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$commit = Get-CommitInfo

# Layout
$artifactName = "StateSmith.DSC-$Version-$timestamp.zip"
$stagingRoot  = Join-Path $env:TEMP ("statesmith_pkg_" + [Guid]::NewGuid())
$null = New-Item -ItemType Directory -Force -Path $stagingRoot

$contentRoot  = Join-Path $stagingRoot 'content'
$null = New-Item -ItemType Directory -Force -Path $contentRoot

# Create module folders akin to PSModule structure
$modulesRoot = Join-Path $contentRoot 'Modules'
$ssFolder    = Join-Path $modulesRoot 'StateSmith.DSC'
$null = New-Item -ItemType Directory -Force -Path $ssFolder

# Copy module files
Copy-Item -Path (Join-Path $PSScriptRoot 'StateSmith.DSC.psm1') -Destination $ssFolder -Force
Copy-Item -Path (Join-Path $PSScriptRoot 'StateSmith.DSC.psd1') -Destination $ssFolder -Force

# Copy Resources and Installers (if present)
Copy-IfExists -Path (Join-Path $PSScriptRoot 'Resources')  -Destination (Join-Path $contentRoot 'Resources')
Copy-IfExists -Path (Join-Path $PSScriptRoot 'Installers') -Destination (Join-Path $contentRoot 'Installers')

# Copy docs
$docs = @('README.md','Simple-DSC-README.md','REBRANDING.md','ROADMAP.md','LICENSE')
foreach ($d in $docs) { if (Test-Path (Join-Path $PSScriptRoot $d)) { Copy-Item (Join-Path $PSScriptRoot $d) -Destination $contentRoot -Force } }

# Include tests optionally
if ($IncludeTests) { Copy-IfExists -Path (Join-Path $PSScriptRoot 'tests') -Destination (Join-Path $contentRoot 'tests') }

# Build metadata
$meta = [pscustomobject]@{
  Name      = 'StateSmith.DSC'
  Version   = $Version
  Timestamp = $timestamp
  CommitSha = $commit.Sha
  Branch    = $commit.Branch
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $contentRoot 'package.meta.json') -Encoding UTF8

# Create output dir and zip
$null = New-Item -ItemType Directory -Force -Path $OutputDir
$zipPath = Join-Path $OutputDir $artifactName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($contentRoot, $zipPath)

Write-Host "Created package: $zipPath" -ForegroundColor Green
Write-Host "Contains: Modules/, Resources/, Installers/ (if present), docs, package.meta.json" -ForegroundColor DarkGray

# Cleanup staging
Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
