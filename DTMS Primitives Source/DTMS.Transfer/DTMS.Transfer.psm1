Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runwayManifest = Join-Path $PSScriptRoot '..\DTMS.Runway\DTMS.Runway.psd1'
if (-not (Get-Module -Name DTMS.Runway) -and
    (Test-Path -LiteralPath $runwayManifest -PathType Leaf)) {
    Import-Module $runwayManifest -ArgumentList Quiet -Force -ErrorAction Stop
}

function Get-DurableTransferProvider {
    <#
    .SYNOPSIS
    Lists installed and supported durable file-transfer providers.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'Robocopy', 'Scp', 'Bits')]
        [string]$Name = 'Auto'
    )

    $providers = @(
        [pscustomobject]@{
            PSTypeName = 'DTMS.Transfer.Provider'
            Name = 'Robocopy'
            Available = $null -ne (Get-Command robocopy.exe -ErrorAction SilentlyContinue)
            Executable = 'robocopy.exe'
            Capabilities = [pscustomobject]@{
                Restartable = $true
                ReportsProgress = $true
                PreservesAcl = $true
                PreservesTimestamps = $true
                DirectoryTransfer = $true
                Encrypted = $false
                Smb = $true
                Ssh = $false
                TargetInitiated = $false
                ChecksumVerification = $true
            }
        }
        [pscustomobject]@{
            PSTypeName = 'DTMS.Transfer.Provider'
            Name = 'Scp'
            Available = $null -ne (Get-Command scp.exe -ErrorAction SilentlyContinue)
            Executable = 'scp.exe'
            Capabilities = [pscustomobject]@{
                Restartable = $false
                ReportsProgress = $true
                PreservesAcl = $false
                PreservesTimestamps = $true
                DirectoryTransfer = $true
                Encrypted = $true
                Smb = $false
                Ssh = $true
                TargetInitiated = $true
                ChecksumVerification = $true
            }
        }
        [pscustomobject]@{
            PSTypeName = 'DTMS.Transfer.Provider'
            Name = 'Bits'
            Available = $null -ne (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)
            Executable = 'Background Intelligent Transfer Service'
            Capabilities = [pscustomobject]@{
                Restartable = $true
                ReportsProgress = $true
                PreservesAcl = $false
                PreservesTimestamps = $false
                DirectoryTransfer = $false
                Encrypted = $false
                Smb = $true
                Ssh = $false
                TargetInitiated = $false
                ChecksumVerification = $true
            }
        }
    )
    if ($Name -eq 'Auto') {
        return $providers
    }
    $providers | Where-Object Name -eq $Name
}

function Get-DurableTransferReadiness {
    <#
    .SYNOPSIS
    Reports availability and capabilities of transfer providers.
    #>
    [CmdletBinding()]
    param()

    foreach ($provider in @(Get-DurableTransferProvider)) {
        [pscustomobject]@{
            PSTypeName = 'DTMS.Transfer.Readiness'
            Module = 'DTMS.Transfer'
            Capability = "$($provider.Name)Transport"
            Status = if ($provider.Available) { 'Ready' } else { 'NotConfigured' }
            Required = $false
            Message = if ($provider.Available) {
                "$($provider.Executable) is available."
            } else {
                "$($provider.Executable) was not found."
            }
            RemediationCommand = if ($provider.Available) {
                $null
            } elseif ($provider.Name -eq 'Scp') {
                'Install the Windows OpenSSH client.'
            } elseif ($provider.Name -eq 'Bits') {
                'Enable and start the Background Intelligent Transfer Service.'
            } else {
                'Enable the Windows Robocopy component.'
            }
        }
    }
}

function New-DurableTransferRequest {
    <#
    .SYNOPSIS
    Creates a declarative transfer request with required capabilities.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates an in-memory transfer request without changing system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [ValidateSet('Auto', 'Robocopy', 'Scp', 'Bits')][string]$Transport = 'Auto',
        [switch]$RequireResume,
        [switch]$PreserveAcl,
        [switch]$RequireEncryption,
        [switch]$Recurse,
        [ValidateRange(0, [long]::MaxValue)]
        [long]$CompletedBytesBefore = 0,
        [ValidateRange(0, [long]::MaxValue)]
        [long]$OperationBytesTotal = 0,
        [ValidateSet('Never', 'Safe', 'SafeAfterObservation')]
        [string]$FallbackSafety = 'Never',
        [string]$SshKeyPath,
        [string]$ExpectedSha256,
        [ValidateRange(0, [long]::MaxValue)]
        [long]$ExpectedBytes = 0
    )

    [pscustomobject]@{
        PSTypeName = 'DTMS.Transfer.Request'
        SchemaVersion = 1
        Source = $Source
        Destination = $Destination
        Transport = $Transport
        RequireResume = $RequireResume.IsPresent
        PreserveAcl = $PreserveAcl.IsPresent
        RequireEncryption = $RequireEncryption.IsPresent
        Recurse = $Recurse.IsPresent
        CompletedBytesBefore = $CompletedBytesBefore
        OperationBytesTotal = $OperationBytesTotal
        FallbackSafety = $FallbackSafety
        SshKeyPath = $SshKeyPath
        ExpectedSha256 = $ExpectedSha256
        ExpectedBytes = $ExpectedBytes
    }
}

function Select-DurableTransferProvider {
    <#
    .SYNOPSIS
    Selects an available provider that satisfies a transfer request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$Request
    )

    process {
        $evaluations = @()
        $providers = @(Get-DurableTransferProvider)
        if ($Request.Transport -ne 'Auto') {
            $providers = @($providers | Where-Object Name -eq $Request.Transport)
        } elseif ($Request.Source -match '^[^\\/:]+@[^:]+:' -or
            $Request.Destination -match '^[^\\/:]+@[^:]+:') {
            $providers = @($providers | Sort-Object @{
                Expression = { if ($_.Name -eq 'Scp') { 0 } else { 1 } }
            })
        } else {
            $providers = @($providers | Sort-Object @{
                Expression = { if ($_.Name -eq 'Robocopy') { 0 } else { 1 } }
            })
        }
        foreach ($candidate in $providers) {
            $reasons = @()
            if (-not $candidate.Available) {
                $reasons += 'provider is unavailable'
            }
            if ($Request.RequireResume -and -not $candidate.Capabilities.Restartable) {
                $reasons += 'does not support restartable transfers'
            }
            if ($Request.PreserveAcl -and -not $candidate.Capabilities.PreservesAcl) {
                $reasons += 'does not preserve ACLs'
            }
            if ($Request.RequireEncryption -and -not $candidate.Capabilities.Encrypted) {
                $reasons += 'does not provide encrypted transport'
            }
            if (($Request.Source -match '^[^\\/:]+@[^:]+:' -or
                    $Request.Destination -match '^[^\\/:]+@[^:]+:') -and
                -not $candidate.Capabilities.Ssh) {
                $reasons += 'does not support SSH endpoints'
            }
            $evaluations += [pscustomobject]@{
                Provider = $candidate.Name
                Eligible = $reasons.Count -eq 0
                Reason = if ($reasons.Count -eq 0) {
                    'satisfies declared transfer requirements'
                } else {
                    $reasons -join '; '
                }
            }
        }
        $providers = @($providers | Where-Object {
            $candidate = $_
            ($evaluations | Where-Object {
                $_.Provider -eq $candidate.Name -and $_.Eligible
            }).Count -gt 0
        })
        if ($providers.Count -eq 0) {
            throw "No available transfer provider satisfies request '$($Request.Source)' -> '$($Request.Destination)'."
        }
        $selected = $providers[0]
        $fallback = if ($Request.FallbackSafety -in @('Safe', 'SafeAfterObservation')) {
            @($providers | Where-Object Name -ne $selected.Name)[0]
        } else {
            $null
        }
        [pscustomobject]@{
            PSTypeName = 'DTMS.Transfer.Selection'
            Provider = $selected
            Reason = if ($Request.Transport -ne 'Auto') {
                "Provider '$($selected.Name)' was explicitly requested."
            } else {
                "Provider '$($selected.Name)' is the highest-ranked available provider satisfying the required capabilities."
            }
            Evaluation = $evaluations
            Fallback = if ($fallback) {
                [pscustomobject]@{
                    Provider = $fallback
                    Reason = "Provider '$($fallback.Name)' is eligible only after the declared fallback safety contract permits it."
                }
            } else {
                $null
            }
        }
    }
}

function Invoke-DurableTransfer {
    <#
    .SYNOPSIS
    Executes a declarative transfer using the selected provider.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$Request,
        [string]$LogPath,
        [string]$MetricsPath,
        [ValidateRange(1, 300)][int]$SampleIntervalSeconds = 5
    )

    process {
        $activity = Start-DTMSActivity `
            -Name 'Durable file transfer' `
            -Intent "Select a provider and copy '$($Request.Source)'" `
            -Target $Request.Destination
        $selection = Select-DurableTransferProvider -Request $Request
        $provider = $selection.Provider
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Selected $($provider.Name); preparing transfer." `
            -ForceHeartbeat
        if (-not $PSCmdlet.ShouldProcess(
            $Request.Destination,
            "copy '$($Request.Source)' using $($provider.Name)"
        )) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'Transfer was not started.'
            return
        }
        $startedUtc = [DateTime]::UtcNow
        $totalBytes = if ($Request.Source -notmatch '^[^\\/:]+@[^:]+:') {
            try {
                [long](Get-Item -LiteralPath $Request.Source -ErrorAction Stop).Length
            } catch {
                [long]0
            }
        } else {
            [long]0
        }
        $metricState = @{
            LastBytes = [long]0
            LastSampleUtc = $startedUtc
        }
        $retryCount = [long]0
        $resumeCount = [long]0
        $writeMetric = {
            param(
                [long]$BytesTransferred,
                [long]$BytesTotal,
                [string]$Status,
                [string]$Message,
                [string]$VerificationState = 'not-requested'
            )
            if (-not $MetricsPath) {
                return
            }
            $sampleUtc = [DateTime]::UtcNow
            $elapsedSeconds = [math]::Max(
                0.001,
                ($sampleUtc - $startedUtc).TotalSeconds
            )
            $sampleSeconds = [math]::Max(
                0.001,
                ($sampleUtc - $metricState.LastSampleUtc).TotalSeconds
            )
            $sampleBytes = [math]::Max(
                0,
                $BytesTransferred - [long]$metricState.LastBytes
            )
            $instantaneousMbps = ($sampleBytes * 8 / 1000000) / $sampleSeconds
            $averageMbps = ($BytesTransferred * 8 / 1000000) / $elapsedSeconds
            $percentComplete = if ($BytesTotal -gt 0) {
                [math]::Min(100, ($BytesTransferred / $BytesTotal) * 100)
            } else {
                $null
            }
            $remainingSeconds = if ($BytesTotal -gt $BytesTransferred -and
                $averageMbps -gt 0) {
                (($BytesTotal - $BytesTransferred) * 8 / 1000000) / $averageMbps
            } else {
                $null
            }
            $operationBytesTransferred = [long]$Request.CompletedBytesBefore +
                $BytesTransferred
            $operationBytesTotal = if ([long]$Request.OperationBytesTotal -gt 0) {
                [long]$Request.OperationBytesTotal
            } else {
                $BytesTotal
            }
            $metric = [ordered]@{
                schemaVersion = 1
                recordedUtc = $sampleUtc.ToString('o')
                provider = $provider.Name
                status = $Status
                source = $Request.Source
                destination = $Request.Destination
                bytesTransferred = $BytesTransferred
                bytesTotal = $BytesTotal
                operationBytesTransferred = $operationBytesTransferred
                operationBytesTotal = $operationBytesTotal
                operationPercentComplete = if ($operationBytesTotal -gt 0) {
                    [math]::Round(
                        [math]::Min(
                            100,
                            ($operationBytesTransferred / $operationBytesTotal) * 100
                        ),
                        2
                    )
                } else {
                    $null
                }
                percentComplete = if ($null -eq $percentComplete) {
                    $null
                } else {
                    [math]::Round($percentComplete, 2)
                }
                elapsedSeconds = [math]::Round($elapsedSeconds, 3)
                instantaneousMbps = [math]::Round($instantaneousMbps, 3)
                averageMbps = [math]::Round($averageMbps, 3)
                retryCount = $retryCount
                resumeCount = $resumeCount
                verificationState = $VerificationState
                estimatedRemainingSeconds = if ($null -eq $remainingSeconds) {
                    $null
                } else {
                    [math]::Round($remainingSeconds, 1)
                }
                message = $Message
            }
            $parent = Split-Path $MetricsPath -Parent
            if ($parent -and -not (Test-Path $parent -PathType Container)) {
                New-Item $parent -ItemType Directory -Force | Out-Null
            }
            $metric | ConvertTo-Json -Compress |
                Add-Content -LiteralPath $MetricsPath -Encoding UTF8
            $metricState.LastBytes = $BytesTransferred
            $metricState.LastSampleUtc = $sampleUtc
        }
        try {
            & $writeMetric 0 $totalBytes 'Starting' 'Transfer provider started.'
            if ($provider.Name -eq 'Robocopy') {
            if ($Request.Source -match '^[^\\/:]+@[^:]+:' -or
                $Request.Destination -match '^[^\\/:]+@[^:]+:') {
                throw 'Robocopy does not accept SSH endpoint syntax.'
            }
            $sourceDirectory = Split-Path $Request.Source -Parent
            $sourceName = Split-Path $Request.Source -Leaf
            $destinationDirectory = if ([IO.Path]::HasExtension($Request.Destination)) {
                Split-Path $Request.Destination -Parent
            } else {
                $Request.Destination
            }
            $arguments = @(
                $sourceDirectory
                $destinationDirectory
                $sourceName
                '/Z'
                '/J'
                '/COPY:DAT'
                '/DCOPY:DAT'
                '/R:5'
                '/W:15'
                '/ETA'
            ) + @($Request.AdditionalArgument)
            if ($LogPath) {
                $arguments += "/LOG+:$LogPath"
            }
            $process = Start-Process `
                -FilePath $provider.Executable `
                -ArgumentList $arguments `
                -PassThru `
                -NoNewWindow
            while (-not $process.HasExited) {
                Start-Sleep -Seconds $SampleIntervalSeconds
                $process.Refresh()
                $currentBytes = if (Test-Path $Request.Destination -PathType Leaf) {
                    [long](Get-Item $Request.Destination).Length
                } else {
                    [long]0
                }
                & $writeMetric $currentBytes $totalBytes 'Running' 'Robocopy transfer is running.'
                Update-DTMSActivity `
                    -Activity $activity `
                    -Status 'Robocopy is transferring data.' `
                    -PercentComplete $(if ($totalBytes -gt 0) {
                        [math]::Min(100, ($currentBytes / $totalBytes) * 100)
                    } else {
                        -1
                    })
            }
            $exitCode = [int]$process.ExitCode
            if ($exitCode -gt 7) {
                throw "Robocopy failed with exit code $exitCode."
            }
            } elseif ($provider.Name -eq 'Scp') {
            if ($Request.Destination -match '^[^\\/:]+@[^:]+:') {
                throw 'SCP transfers must be initiated by the target and receive from a remote source.'
            }
            if ($Request.Source -notmatch '^[^\\/:]+@[^:]+:') {
                throw 'SCP source must be a remote SSH endpoint for target-initiated transfer.'
            }
            if (-not $Request.SshKeyPath -or
                -not (Test-Path -LiteralPath $Request.SshKeyPath -PathType Leaf)) {
                throw 'SCP requires a validated target-local SSH key path.'
            }
            $arguments = @('-B')
            if ($Request.Recurse) {
                $arguments += '-r'
            }
            $arguments += @('-i', $Request.SshKeyPath)
            $arguments += @($Request.Source, $Request.Destination)
            $processParameters = @{
                FilePath = $provider.Executable
                ArgumentList = $arguments
                PassThru = $true
                NoNewWindow = $true
            }
            if ($LogPath) {
                $processParameters.RedirectStandardOutput = $LogPath
                $processParameters.RedirectStandardError = "$LogPath.error"
            }
            $process = Start-Process @processParameters
            while (-not $process.HasExited) {
                Start-Sleep -Seconds $SampleIntervalSeconds
                $process.Refresh()
                $currentBytes = if (Test-Path $Request.Destination -PathType Leaf) {
                    [long](Get-Item $Request.Destination).Length
                    } else {
                    [long]0
                }
                & $writeMetric $currentBytes $totalBytes 'Running' 'SCP transfer is running.'
                Update-DTMSActivity `
                    -Activity $activity `
                    -Status 'SCP is transferring data.' `
                    -PercentComplete $(if ($totalBytes -gt 0) {
                        [math]::Min(100, ($currentBytes / $totalBytes) * 100)
                    } else {
                        -1
                    })
            }
            $exitCode = [int]$process.ExitCode
            if ($exitCode -ne 0) {
                throw "SCP failed with exit code $exitCode."
            }
        } else {
            Import-Module BitsTransfer -ErrorAction Stop
            $bitsJob = Start-BitsTransfer `
                -Source $Request.Source `
                -Destination $Request.Destination `
                -DisplayName "DTMS-$([guid]::NewGuid().ToString('N'))" `
                -Description 'DTMS durable file transfer' `
                -Priority Foreground `
                -Asynchronous `
                -ErrorAction Stop
            try {
                while ($bitsJob.JobState -in @(
                    'Queued', 'Connecting', 'Transferring', 'TransientError'
                )) {
                    if ($bitsJob.JobState -eq 'TransientError') {
                        $retryCount++
                        $resumeCount++
                        Resume-BitsTransfer -BitsJob $bitsJob -Asynchronous
                    }
                    Start-Sleep -Seconds $SampleIntervalSeconds
                    $bitsJob = Get-BitsTransfer -JobId $bitsJob.JobId -ErrorAction Stop
                    & $writeMetric `
                        ([long]$bitsJob.BytesTransferred) `
                        ([long]$bitsJob.BytesTotal) `
                        ([string]$bitsJob.JobState) `
                        'BITS transfer is running.'
                    Update-DTMSActivity `
                        -Activity $activity `
                        -Status "BITS state: $($bitsJob.JobState)." `
                        -PercentComplete $(if ($bitsJob.BytesTotal -gt 0) {
                            [math]::Min(
                                100,
                                ($bitsJob.BytesTransferred / $bitsJob.BytesTotal) * 100
                            )
                        } else {
                            -1
                        })
                }
                if ($bitsJob.JobState -ne 'Transferred') {
                    $bitsError = if ($bitsJob.ErrorDescription) {
                        $bitsJob.ErrorDescription
                    } else {
                        "BITS entered state '$($bitsJob.JobState)'."
                    }
                    throw $bitsError
                }
                Complete-BitsTransfer -BitsJob $bitsJob -ErrorAction Stop
                $exitCode = 0
            } catch {
                Remove-BitsTransfer -BitsJob $bitsJob -Confirm:$false -ErrorAction SilentlyContinue
                throw
            }
            }
            $finalBytes = if (Test-Path $Request.Destination -PathType Leaf) {
                [long](Get-Item $Request.Destination).Length
            } else {
                $totalBytes
            }
            $verificationState = 'not-requested'
            if ($Request.ExpectedBytes -gt 0 -and
                $finalBytes -ne [long]$Request.ExpectedBytes) {
                throw "Transfer verification failed: expected $($Request.ExpectedBytes) bytes, received $finalBytes."
            }
            if ($Request.ExpectedSha256) {
                $actualSha256 = (Get-FileHash `
                    -LiteralPath $Request.Destination `
                    -Algorithm SHA256 `
                    -ErrorAction Stop).Hash
                if ($actualSha256 -ne $Request.ExpectedSha256) {
                    throw 'Transfer verification failed: SHA-256 digest does not match.'
                }
                $verificationState = 'verified'
            } elseif ($Request.ExpectedBytes -gt 0) {
                $verificationState = 'verified'
            }
            & $writeMetric $finalBytes $(if ($totalBytes -gt 0) {
                $totalBytes
            } else {
                $finalBytes
            }) 'Succeeded' 'Transfer completed successfully.' $verificationState
            $completedUtc = [DateTime]::UtcNow
            $elapsedSeconds = [math]::Max(0.001, ($completedUtc - $startedUtc).TotalSeconds)
            [pscustomobject]@{
                PSTypeName = 'DTMS.Transfer.Result'
                Provider = $provider.Name
                Source = $Request.Source
                Destination = $Request.Destination
                Status = 'Succeeded'
                ExitCode = $exitCode
                StartedUtc = $startedUtc.ToString('o')
                CompletedUtc = $completedUtc.ToString('o')
                BytesTransferred = $finalBytes
                ElapsedSeconds = [math]::Round($elapsedSeconds, 3)
                AverageMbps = [math]::Round(
                    ($finalBytes * 8 / 1000000) / $elapsedSeconds,
                    3
                )
                RetryCount = $retryCount
                ResumeCount = $resumeCount
                VerificationState = $verificationState
                SelectionReason = $selection.Reason
                LogPath = $LogPath
                MetricsPath = $MetricsPath
            }
            Complete-DTMSActivity `
                -Activity $activity `
                -Status "$($provider.Name) transfer completed."
        } catch {
            $failedBytes = if (Test-Path $Request.Destination -PathType Leaf) {
                [long](Get-Item $Request.Destination).Length
            } else {
                [long]0
            }
            & $writeMetric `
                $failedBytes `
                $totalBytes `
                'Failed' `
                $_.Exception.Message
            Complete-DTMSActivity `
                -Activity $activity `
                -Status $_.Exception.Message `
                -Failed
            throw
        }
    }
}

Export-ModuleMember -Function @(
    'Get-DurableTransferProvider'
    'Get-DurableTransferReadiness'
    'Invoke-DurableTransfer'
    'New-DurableTransferRequest'
    'Select-DurableTransferProvider'
)
