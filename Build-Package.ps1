<#
.SYNOPSIS
  Builds a distributable package zip for the Pedantic DSC toolkit.

.DESCRIPTION
  Creates an output folder under ./dist, collects module files (Pedantic),
  resources (Resources/, Installers/), and docs, and zips them into a versioned artifact.
  Embeds a small metadata file with build time and commit info if available.

.PARAMETER Version
  Version tag for the artifact (default: read from Pedantic.psd1 ModuleVersion, or '0.0.0-local').

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
  $manifestPath = Join-Path $PSScriptRoot 'Pedantic.psd1'
  if (-not (Test-Path $manifestPath)) { return $null }
  try {
    $data = Import-PowerShellDataFile -Path $manifestPath
    return $data.ModuleVersion
  } catch {
    Write-Warning "Failed to read module version from manifest: $($_.Exception.Message)"
    return $null
  }
}

function Get-CommitInfo {
  try {
    $sha = git rev-parse --short HEAD 2>&1 | Out-String
    $sha = $sha.Trim()
    $branch = git rev-parse --abbrev-ref HEAD 2>&1 | Out-String
    $branch = $branch.Trim()
    if ($sha -and -not $sha.Contains('fatal')) { 
      return @{ Sha = "$sha"; Branch = "$branch" } 
    }
  } catch {
    Write-Verbose "Git not available or not in a repository: $($_.Exception.Message)"
  }
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
$artifactName = "Pedantic-$Version-$timestamp.zip"
$tempDir = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
$stagingRoot  = Join-Path $tempDir ("pedantic_pkg_" + [Guid]::NewGuid())
$null = New-Item -ItemType Directory -Force -Path $stagingRoot

$contentRoot  = Join-Path $stagingRoot 'content'
$null = New-Item -ItemType Directory -Force -Path $contentRoot

# Create module folders akin to PSModule structure
$modulesRoot = Join-Path $contentRoot 'Modules'
$moduleFolder = Join-Path $modulesRoot 'Pedantic'
$null = New-Item -ItemType Directory -Force -Path $moduleFolder

# Copy module files
Copy-Item -Path (Join-Path $PSScriptRoot 'Pedantic.psm1') -Destination $moduleFolder -Force
Copy-Item -Path (Join-Path $PSScriptRoot 'Pedantic.psd1') -Destination $moduleFolder -Force

# Copy Resources and Installers (if present)
Copy-IfExists -Path (Join-Path $PSScriptRoot 'Resources')  -Destination (Join-Path $contentRoot 'Resources')
Copy-IfExists -Path (Join-Path $PSScriptRoot 'Installers') -Destination (Join-Path $contentRoot 'Installers')

# Copy README and docs folder
if (Test-Path (Join-Path $PSScriptRoot 'README.md')) { 
  Copy-Item (Join-Path $PSScriptRoot 'README.md') -Destination $contentRoot -Force 
}
Copy-IfExists -Path (Join-Path $PSScriptRoot 'docs') -Destination (Join-Path $contentRoot 'docs')

# Include tests optionally
if ($IncludeTests) { Copy-IfExists -Path (Join-Path $PSScriptRoot 'tests') -Destination (Join-Path $contentRoot 'tests') }

# Build metadata
$meta = [pscustomobject]@{
  Name      = 'Pedantic'
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
