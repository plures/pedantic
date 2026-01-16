# StateSmith.DSC.Reverse.psm1
# Reverse/catalog operations for DSC using StateSmith branding

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Prefer importing StateSmith.DSC for core helpers
try {
  if (-not (Get-Module -Name StateSmith.DSC)) {
    $modulePath = Join-Path $PSScriptRoot 'StateSmith.DSC.psm1'
    if (Test-Path $modulePath) { Import-Module $modulePath -Force -Global }
    else { Import-Module StateSmith.DSC -ErrorAction SilentlyContinue }
  }
}
catch {
  Write-Verbose "StateSmith.DSC not available yet: $($_.Exception.Message)"
}

$script:ReverseTempRoot = 'C:\Temp\StateSmithDscReverse'
if (-not (Test-Path $script:ReverseTempRoot)) { New-Item -Path $script:ReverseTempRoot -ItemType Directory -Force | Out-Null }

function New-DscSystemCatalog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$OutputPath,
    [string]$ComputerName = $env:COMPUTERNAME,
    [switch]$IncludeResources
  )

  $meta = [ordered]@{
    generatedBy     = 'StateSmith.DSC.Reverse'
    generatedAt     = (Get-Date).ToString('o')
    computer        = $ComputerName
    includeResources= [bool]$IncludeResources
  }

  $catalog = [ordered]@{ meta = $meta; resources = @(); configuration = @{} }

  try {
    # Collect basic system info
    $os = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $nics = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'}

    $catalog.configuration = [ordered]@{
      OS   = [ordered]@{
        Caption    = $os.Caption
        Version    = $os.Version
        BuildNumber= $os.BuildNumber
        InstallDate= $os.InstallDate
      }
      BIOS = [ordered]@{
        Manufacturer = $bios.Manufacturer
        SMBIOSBIOSVersion = $bios.SMBIOSBIOSVersion
        SerialNumber = $bios.SerialNumber
      }
      CPU  = [ordered]@{
        Name = $cpu.Name
        Cores = $cpu.NumberOfCores
        LogicalProcessors = $cpu.NumberOfLogicalProcessors
      }
      Network = $nics | ForEach-Object {
        [ordered]@{ Name=$_.Name; Mac=$_.MacAddress; LinkSpeed=$_.LinkSpeed }
      }
    }

    if ($IncludeResources) {
      try {
        $resources = & dsc resource list --output-format json 2>&1 | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($resources) {
          $catalog.resources = $resources | ForEach-Object {
            [ordered]@{ type=$_.type; version=$_.version; kind=$_.kind; description=$_.description }
          }
        }
      }
      catch { Write-Verbose "Failed to list DSC resources: $($_.Exception.Message)" }
    }

    $OutputDir = Split-Path -Parent $OutputPath
    if ($OutputDir -and -not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
    $catalog | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Verbose "Catalog written to $OutputPath"
    return Get-Item $OutputPath
  }
  catch {
    Write-Error "Failed to create DSC system catalog: $($_.Exception.Message)"
  }
}

function Get-DscCatalogHistory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Path,
    [int]$MaxItems = 20
  )

  try {
    $files = Get-ChildItem -Path $Path -Filter *.json -File | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxItems
    return $files
  }
  catch {
    Write-Error "Failed to read catalog history: $($_.Exception.Message)"
  }
}

function Compare-DscCatalogs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$OldCatalog,
    [Parameter(Mandatory)] [string]$NewCatalog
  )

  try {
    $old = Get-Content -Path $OldCatalog -Raw | ConvertFrom-Json
    $new = Get-Content -Path $NewCatalog -Raw | ConvertFrom-Json

    $diff = [ordered]@{}
    $keys = ($old.PSObject.Properties.Name + $new.PSObject.Properties.Name) | Sort-Object -Unique
    foreach ($k in $keys) {
      if (-not ($old.PSObject.Properties.Name -contains $k)) { $diff[$k] = [ordered]@{ change='added'; value=$new.$k }; continue }
      if (-not ($new.PSObject.Properties.Name -contains $k)) { $diff[$k] = [ordered]@{ change='removed'; value=$old.$k }; continue }
      if ($old.$k -ne $new.$k) { $diff[$k] = [ordered]@{ change='modified'; old=$old.$k; new=$new.$k } }
    }
    return $diff
  }
  catch {
    Write-Error "Failed to compare catalogs: $($_.Exception.Message)"
  }
}

function Restore-DscSystemConfiguration {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$CatalogPath,
    [switch]$WhatIf
  )

  try {
    $catalog = Get-Content -Path $CatalogPath -Raw | ConvertFrom-Json
    if (-not $catalog -or -not $catalog.configuration) { throw "Invalid catalog format" }

    Write-Host "StateSmith would restore the following settings:" -ForegroundColor Cyan
    $catalog.configuration.GetEnumerator() | ForEach-Object {
      Write-Host " - $($_.Key)" -ForegroundColor Yellow
    }
    if ($WhatIf) { return }
    # Implementation placeholder: map catalog to DSC config as needed
    Write-Host "Restore operation completed (placeholder)." -ForegroundColor Green
  }
  catch {
    Write-Error "Failed to restore system from catalog: $($_.Exception.Message)"
  }
}

Export-ModuleMember -Function 'New-DscSystemCatalog','Get-DscCatalogHistory','Compare-DscCatalogs','Restore-DscSystemConfiguration'