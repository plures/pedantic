#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Invoke-Command values are declared in param() and supplied through ArgumentList.'
)]

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$ConfigurationPath =
        'C:\ProgramData\DTMS\VMM\FederatedTransfers\Configuration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Information `
    -MessageData '[DTMS] START Federated transfer collection - pull authoritative target-host state into the local utility index.' `
    -Tags 'DTMS', 'Activity', 'Start' `
    -InformationAction Continue

if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
    throw "Federated collector configuration '$ConfigurationPath' was not found."
}
$configuration = Get-Content -LiteralPath $ConfigurationPath -Raw |
    ConvertFrom-Json
$indexRoot = [string]$configuration.IndexRoot
$durableTransferRoot = [string]$configuration.DurableTransferRoot
$retentionCount = [int]$configuration.RetentionCount
$targetHosts = @($configuration.TargetHostName |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique)

if (-not $indexRoot -or $retentionCount -lt 1 -or $targetHosts.Count -eq 0) {
    throw "Federated collector configuration '$ConfigurationPath' is incomplete."
}
New-Item -Path $indexRoot -ItemType Directory -Force | Out-Null

$failures = [Collections.Generic.List[string]]::new()
$targetIndex = 0
foreach ($targetHost in $targetHosts) {
    $targetIndex++
    Write-Progress `
        -Id 1701 `
        -Activity 'Federated transfer collection' `
        -Status "[$targetIndex/$($targetHosts.Count)] Pulling $targetHost" `
        -PercentComplete (($targetIndex / $targetHosts.Count) * 100)
    try {
        $snapshots = @(Invoke-Command `
            -ComputerName $targetHost `
            -ArgumentList $durableTransferRoot `
            -ErrorAction Stop `
            -ScriptBlock {
                param($TransferRoot)

                if (-not (Test-Path -LiteralPath $TransferRoot -PathType Container)) {
                    return
                }
                foreach ($directory in @(Get-ChildItem `
                    -LiteralPath $TransferRoot `
                    -Directory `
                    -ErrorAction Stop)) {
                    $statePath = Join-Path $directory.FullName 'State.json'
                    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
                        continue
                    }
                    $state = Get-Content -LiteralPath $statePath -Raw |
                        ConvertFrom-Json
                    $metricsPath = Join-Path $directory.FullName 'TransferMetrics.jsonl'
                    $latestMetric = @(
                        if (Test-Path -LiteralPath $metricsPath -PathType Leaf) {
                            Get-Content -LiteralPath $metricsPath -Tail 20 |
                                ForEach-Object {
                                    try { $_ | ConvertFrom-Json } catch { $null }
                                } |
                                Where-Object { $null -ne $_ } |
                                Select-Object -Last 1
                        }
                    )
                    [pscustomobject]@{
                        SchemaVersion = 1
                        CollectedUtc = [DateTime]::UtcNow.ToString('o')
                        CollectorUtilityServer = $null
                        TransferId = [string]$state.TransferId
                        Status = [string]$state.Status
                        CurrentPhase = [string]$state.CurrentPhase
                        SourceVMName = [string]$state.SourceVMName
                        TargetVMName = [string]$state.TargetVMName
                        SourceHostName = [string]$state.SourceHostName
                        TargetHostName = [string]$state.TargetHostName
                        ExecutionAccount = [string]$state.ExecutionAccount
                        AttemptCount = [int]$state.AttemptCount
                        CreatedUtc = [string]$state.CreatedUtc
                        StartedUtc = [string]$state.StartedUtc
                        UpdatedUtc = [string]$state.UpdatedUtc
                        CompletedUtc = [string]$state.CompletedUtc
                        Message = [string]$state.Message
                        TransferProvider = if ($latestMetric.Count) {
                            [string]$latestMetric[0].provider
                        } else {
                            $null
                        }
                        ProgressPercent = if ($latestMetric.Count) {
                            $latestMetric[0].operationPercentComplete
                        } else {
                            $null
                        }
                        BytesTransferred = if ($latestMetric.Count) {
                            $latestMetric[0].operationBytesTransferred
                        } else {
                            $null
                        }
                        BytesTotal = if ($latestMetric.Count) {
                            $latestMetric[0].operationBytesTotal
                        } else {
                            $null
                        }
                        InstantaneousMbps = if ($latestMetric.Count) {
                            $latestMetric[0].instantaneousMbps
                        } else {
                            $null
                        }
                        AverageMbps = if ($latestMetric.Count) {
                            $latestMetric[0].averageMbps
                        } else {
                            $null
                        }
                        EstimatedRemainingSeconds = if ($latestMetric.Count) {
                            $latestMetric[0].estimatedRemainingSeconds
                        } else {
                            $null
                        }
                    }
                }
            })

        foreach ($snapshot in $snapshots) {
            if (-not $snapshot.TransferId) {
                continue
            }
            $snapshot.CollectorUtilityServer = $env:COMPUTERNAME
            $transferRoot = Join-Path $indexRoot $snapshot.TransferId
            $snapshotsRoot = Join-Path $transferRoot 'Snapshots'
            New-Item -Path $snapshotsRoot -ItemType Directory -Force | Out-Null
            $currentPath = Join-Path $transferRoot 'Current.json'
            $writeSnapshot = $true
            if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
                $current = Get-Content -LiteralPath $currentPath -Raw |
                    ConvertFrom-Json
                $writeSnapshot = $current.UpdatedUtc -ne $snapshot.UpdatedUtc -or
                    $current.Status -ne $snapshot.Status -or
                    $current.ProgressPercent -ne $snapshot.ProgressPercent
            }
            if ($writeSnapshot) {
                $snapshotName = '{0}-{1}.json' -f
                    ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')),
                    ([guid]::NewGuid().ToString('N'))
                $snapshot | ConvertTo-Json -Depth 10 |
                    Set-Content `
                        -LiteralPath (Join-Path $snapshotsRoot $snapshotName) `
                        -Encoding UTF8
            }
            $temporaryPath = "$currentPath.tmp"
            $snapshot | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $temporaryPath -Encoding UTF8
            Move-Item -LiteralPath $temporaryPath -Destination $currentPath -Force
        }
    } catch {
        $failures.Add("$targetHost`: $($_.Exception.Message)")
    }
}

$terminalTransfers = @(Get-ChildItem -LiteralPath $indexRoot -Directory |
    ForEach-Object {
        $currentPath = Join-Path $_.FullName 'Current.json'
        if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
            try {
                $current = Get-Content -LiteralPath $currentPath -Raw |
                    ConvertFrom-Json
                if ($current.Status -in @('Completed', 'Failed')) {
                    [pscustomobject]@{
                        Directory = $_
                        UpdatedUtc = [datetime]$current.UpdatedUtc
                    }
                }
            } catch {
                Write-Warning "Ignoring invalid federated index '$currentPath': $($_.Exception.Message)"
            }
        }
    } |
    Sort-Object UpdatedUtc -Descending)
foreach ($expired in @($terminalTransfers | Select-Object -Skip $retentionCount)) {
    Remove-Item -LiteralPath $expired.Directory.FullName -Recurse -Force
}

if ($failures.Count -gt 0) {
    Write-Progress -Id 1701 -Activity 'Federated transfer collection' -Completed
    throw "Federated collection failed for $($failures.Count) target host(s): $($failures -join '; ')"
}

Write-Progress -Id 1701 -Activity 'Federated transfer collection' -Completed
Write-Information `
    -MessageData "[DTMS] DONE Federated transfer collection - indexed $(@(Get-ChildItem -LiteralPath $indexRoot -Directory).Count) transfer(s)." `
    -Tags 'DTMS', 'Activity', 'Done' `
    -InformationAction Continue
[pscustomobject]@{
    UtilityServer = $env:COMPUTERNAME
    TargetHostCount = $targetHosts.Count
    TransferCount = @(Get-ChildItem -LiteralPath $indexRoot -Directory).Count
    RetentionCount = $retentionCount
    CollectedUtc = [DateTime]::UtcNow.ToString('o')
}
