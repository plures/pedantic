#requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'The remoting script block declares OperationRoot and receives it through ArgumentList.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigurationPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$configuration = Get-Content -LiteralPath $ConfigurationPath -Raw |
    ConvertFrom-Json
$indexRoot = Join-Path $configuration.LocalPath 'Index'
New-Item -Path $indexRoot -ItemType Directory -Force | Out-Null

foreach ($target in @($configuration.TargetComputerName)) {
    Write-Information `
        -MessageData "[DTMS] ACTIVE Runway federation collector - Pulling $target." `
        -InformationAction Continue
    try {
        $states = @(Invoke-Command `
            -ComputerName $target `
            -ArgumentList $configuration.OperationRoot `
            -ScriptBlock {
                param($OperationRoot)
                if (-not (Test-Path -LiteralPath $OperationRoot)) {
                    return
                }
                Get-ChildItem -LiteralPath $OperationRoot -Directory |
                    ForEach-Object {
                        $statePath = Join-Path $_.FullName 'State.json'
                        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
                            Get-Content -LiteralPath $statePath -Raw |
                                ConvertFrom-Json
                        }
                    }
            })
        foreach ($state in $states) {
            $operationPath = Join-Path (
                Join-Path $indexRoot $target
            ) $state.OperationId
            New-Item -Path $operationPath -ItemType Directory -Force |
                Out-Null
            $record = [ordered]@{
                SchemaVersion = 1
                ComputerName = $target
                OperationId = $state.OperationId
                OperationType = $state.OperationType
                Status = $state.Status
                CurrentPhase = $state.CurrentPhase
                ExecutionAccount = $state.ExecutionAccount
                ProgressPercent = $state.ProgressPercent
                CreatedUtc = $state.CreatedUtc
                UpdatedUtc = $state.UpdatedUtc
                StartedUtc = $state.StartedUtc
                CompletedUtc = $state.CompletedUtc
                Message = $state.Message
                Metadata = $state.Metadata
                CollectedUtc = [DateTime]::UtcNow.ToString('o')
                CollectorComputerName = $env:COMPUTERNAME
            }
            $currentPath = Join-Path $operationPath 'Current.json'
            $temporaryPath = "$currentPath.tmp"
            $record | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $temporaryPath -Encoding UTF8
            Move-Item -LiteralPath $temporaryPath `
                -Destination $currentPath -Force
        }
    } catch {
        Write-Warning "Runway federation pull failed for '$target': $($_.Exception.Message)"
    }
}

$terminal = @(Get-ChildItem -LiteralPath $indexRoot `
    -Filter Current.json -File -Recurse |
    ForEach-Object {
        [pscustomobject]@{
            Path = $_.Directory.FullName
            Record = Get-Content -LiteralPath $_.FullName -Raw |
                ConvertFrom-Json
        }
    } |
    Where-Object {
        $_.Record.Status -in @(
            'Succeeded', 'Failed', 'NeedsReview', 'Cancelled',
            'RolledBack', 'RollbackFailed'
        )
    } |
    Sort-Object { [datetime]$_.Record.UpdatedUtc } -Descending)
foreach ($expired in @($terminal |
    Select-Object -Skip ([int]$configuration.RetentionCount))) {
    Remove-Item -LiteralPath $expired.Path -Recurse -Force
}
