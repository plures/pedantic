BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot 'DTMS.Transfer.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'DTMS.Transfer provider contract' {
    It 'exports the supported transfer commands' {
        @(Get-Command -Module DTMS.Transfer) | Should -HaveCount 5
    }

    It 'reports Robocopy, SCP, and BITS capabilities' {
        $providers = @(Get-DurableTransferProvider)

        $providers.Name | Should -Be @('Robocopy', 'Scp', 'Bits')
        ($providers | Where-Object Name -eq 'Robocopy').Capabilities.Restartable |
            Should -BeTrue
        ($providers | Where-Object Name -eq 'Scp').Capabilities.Encrypted |
            Should -BeTrue
        ($providers | Where-Object Name -eq 'Bits').Capabilities.Restartable |
            Should -BeTrue
    }

    It 'creates versioned declarative requests' {
        $request = New-DurableTransferRequest `
            -Source '\\server\share\disk.vhdx' `
            -Destination 'D:\VMs\disk.vhdx' `
            -RequireResume `
            -PreserveAcl

        $request.SchemaVersion | Should -Be 1
        $request.RequireResume | Should -BeTrue
        $request.PreserveAcl | Should -BeTrue
        $request.ExpectedBytes | Should -BeNullOrEmpty

        $emptyFileRequest = New-DurableTransferRequest `
            -Source '\\server\share\empty.vhdx' `
            -Destination 'D:\VMs\empty.vhdx' `
            -ExpectedBytes 0

        $emptyFileRequest.ExpectedBytes | Should -Be 0

        $unspecifiedSizeRequest = New-DurableTransferRequest `
            -Source '\\server\share\unknown-size.vhdx' `
            -Destination 'D:\VMs\unknown-size.vhdx' `
            -ExpectedBytes $null

        $unspecifiedSizeRequest.ExpectedBytes | Should -BeNullOrEmpty
    }
}

Describe 'DTMS.Transfer selection policy' {
    It 'selects Robocopy for restartable Windows path transfers' {
        InModuleScope DTMS.Transfer {
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Robocopy'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $true
                            PreservesAcl = $true
                            Encrypted = $false
                            Ssh = $false
                            TargetInitiated = $false
                            ChecksumVerification = $true
                        }
                    }
                    [pscustomobject]@{
                        Name = 'Scp'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $false
                            PreservesAcl = $false
                            Encrypted = $true
                            Ssh = $true
                            TargetInitiated = $true
                            ChecksumVerification = $true
                        }
                    }

                )
            }
            $request = New-DurableTransferRequest `
                -Source '\\server\share\disk.vhdx' `
                -Destination 'D:\VMs\disk.vhdx' `
                -RequireResume

            (Select-DurableTransferProvider $request).Provider.Name |
                Should -Be 'Robocopy'
        }
    }

    It 'selects SCP for SSH endpoint transfers without resume requirements' {
        InModuleScope DTMS.Transfer {
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Robocopy'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $true
                            PreservesAcl = $true
                            Encrypted = $false
                            Ssh = $false
                            TargetInitiated = $false
                            ChecksumVerification = $true
                        }
                    }
                    [pscustomobject]@{
                        Name = 'Scp'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $false
                            PreservesAcl = $false
                            Encrypted = $true
                            Ssh = $true
                            TargetInitiated = $true
                            ChecksumVerification = $true
                        }
                    }
                )
            }
            $keyPath = Join-Path $TestDrive 'transfer-key'
            Set-Content -LiteralPath $keyPath -Value 'key'
            $request = New-DurableTransferRequest `
                -Source 'user@server:D:/VMs/disk.vhdx' `
                -Destination 'D:\VMs\disk.vhdx' `
                -SshKeyPath $keyPath

            (Select-DurableTransferProvider $request).Provider.Name |
                Should -Be 'Scp'
        }
    }

    It 'rejects SCP candidates that cannot execute the requested direction or key placement' {
        InModuleScope DTMS.Transfer {
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Scp'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $false
                            PreservesAcl = $false
                            Encrypted = $true
                            Ssh = $true
                            TargetInitiated = $true
                            ChecksumVerification = $true
                        }
                    }
                )
            }
            $keyPath = Join-Path $TestDrive 'transfer-key'
            Set-Content -LiteralPath $keyPath -Value 'key'

            foreach ($case in @(
                @{
                    Source = 'D:\VMs\disk.vhdx'
                    Destination = 'D:\VMs\disk.vhdx'
                    KeyPath = $keyPath
                }
                @{
                    Source = 'user@server:D:/VMs/disk.vhdx'
                    Destination = 'user@target:D:/VMs/disk.vhdx'
                    KeyPath = $keyPath
                }
                @{
                    Source = 'user@server:D:/VMs/disk.vhdx'
                    Destination = 'D:\VMs\disk.vhdx'
                    KeyPath = $null
                }
            )) {
                $request = New-DurableTransferRequest `
                    -Source $case.Source `
                    -Destination $case.Destination `
                    -Transport Scp `
                    -SshKeyPath $case.KeyPath

                { Select-DurableTransferProvider $request } |
                    Should -Throw '*No available transfer provider satisfies*'
            }
        }
    }

    It 'rejects explicit providers that lack required capabilities' {
        $request = New-DurableTransferRequest `
            -Source 'user@server:D:/VMs/disk.vhdx' `
            -Destination 'D:\VMs\disk.vhdx' `
            -Transport Scp `
            -RequireResume

        { Select-DurableTransferProvider $request } |
            Should -Throw '*No available transfer provider satisfies*'
    }

    It 'selects BITS explicitly for restartable SMB transfers' {
        InModuleScope DTMS.Transfer {
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Bits'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $true
                            PreservesAcl = $false
                            Encrypted = $false
                            Ssh = $false
                            TargetInitiated = $false
                            ChecksumVerification = $true
                        }
                    }
                )
            }
            $request = New-DurableTransferRequest `
                -Source '\\server\share\disk.vhdx' `
                -Destination 'D:\VMs\disk.vhdx' `
                -Transport Bits `
                -RequireResume

            (Select-DurableTransferProvider $request).Provider.Name |
                Should -Be 'Bits'
        }
    }

    It 'defines normalized telemetry for every provider' {
        $command = Get-Command Invoke-DurableTransfer
        $text = Get-Content (Join-Path $PSScriptRoot 'DTMS.Transfer.psm1') -Raw

        $command.Parameters.Keys | Should -Contain 'MetricsPath'
        $command.Parameters.Keys | Should -Contain 'SampleIntervalSeconds'
        $text | Should -Match 'bytesTransferred'
        $text | Should -Match 'instantaneousMbps'
        $text | Should -Match 'averageMbps'
        $text | Should -Match 'Start-BitsTransfer'
        $text | Should -Match 'Complete-BitsTransfer'
    }

    It 'rejects a resolved SSH key located on a UNC path' {
        InModuleScope DTMS.Transfer {
            Mock Get-Item {
                [pscustomobject]@{
                    PSProvider = [pscustomobject]@{ Name = 'FileSystem' }
                    PSIsContainer = $false
                    FullName = '\\server\share\transfer-key'
                }
            }

            Test-DurableTransferLocalKeyPath '\\server\share\transfer-key' |
                Should -BeFalse
        }
    }
}

Describe 'DTMS.Transfer execution behavior' {
    It 'distinguishes verification failures from transport failures in metrics' {
        InModuleScope DTMS.Transfer -Parameters @{
            Root = $TestDrive
        } {
            param($Root)

            $keyPath = Join-Path $Root 'transfer-key'
            $destinationPath = Join-Path $Root 'transfer-destination'
            $verificationMetricsPath = Join-Path $Root 'verification-metrics.jsonl'
            $hashMetricsPath = Join-Path $Root 'hash-metrics.jsonl'
            $transportMetricsPath = Join-Path $Root 'transport-metrics.jsonl'
            Set-Content -LiteralPath $keyPath -Value 'key'
            function Start-DTMSActivity {
                [CmdletBinding(SupportsShouldProcess)]
                param([string]$Name, [string]$Intent, [string]$Target)
                @($Name, $Intent, $Target) | Out-Null
                $PSCmdlet.ShouldProcess($Target, $Intent) | Out-Null
            }
            function Update-DTMSActivity {
                [CmdletBinding(SupportsShouldProcess)]
                param(
                    $Activity,
                    [string]$Status,
                    [switch]$ForceHeartbeat,
                    [double]$PercentComplete,
                    [switch]$Failed
                )
                @($Activity, $Status, $ForceHeartbeat, $PercentComplete, $Failed) |
                    Out-Null
                $PSCmdlet.ShouldProcess($Status, 'Update activity') | Out-Null
            }
            function Complete-DTMSActivity {}
            $script:mockScpExitCode = 0
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Scp'
                        Available = $true
                        Executable = 'scp.exe'
                        Capabilities = [pscustomobject]@{
                            Restartable = $false
                            PreservesAcl = $false
                            Encrypted = $true
                            Ssh = $true
                            TargetInitiated = $true
                        }
                    }
                )
            }
            Mock Start-DTMSActivity { [pscustomobject]@{ Id = 'transfer' } }
            Mock Update-DTMSActivity {}
            Mock Complete-DTMSActivity {}
            Mock Start-Process {
                param($ArgumentList)
                if ($script:mockScpExitCode -eq 0) {
                    Set-Content -LiteralPath $ArgumentList[-1] -Value 'data'
                }
                [pscustomobject]@{
                    HasExited = $true
                    ExitCode = $script:mockScpExitCode
                }
            }

            $verificationRequest = New-DurableTransferRequest `
                -Source 'user@server:/data' `
                -Destination $destinationPath `
                -Transport Scp `
                -SshKeyPath $keyPath `
                -ExpectedBytes 99
            {
                Invoke-DurableTransfer `
                    -Request $verificationRequest `
                    -MetricsPath $verificationMetricsPath `
                    -Confirm:$false
            } | Should -Throw '*Transfer verification failed*'
            $verificationMetric = Get-Content -LiteralPath $verificationMetricsPath |
                ForEach-Object { ConvertFrom-Json $_ } |
                Select-Object -Last 1
            $verificationMetric.status | Should -Be 'Failed'
            $verificationMetric.verificationState | Should -Be 'failed'

            $hashRequest = New-DurableTransferRequest `
                -Source 'user@server:/data' `
                -Destination $destinationPath `
                -Transport Scp `
                -SshKeyPath $keyPath `
                -ExpectedSha256 ('0' * 64)
            {
                Invoke-DurableTransfer `
                    -Request $hashRequest `
                    -MetricsPath $hashMetricsPath `
                    -Confirm:$false
            } | Should -Throw '*Transfer verification failed*'
            $hashMetric = Get-Content -LiteralPath $hashMetricsPath |
                ForEach-Object { ConvertFrom-Json $_ } |
                Select-Object -Last 1
            $hashMetric.verificationState | Should -Be 'failed'

            Remove-Item -LiteralPath $destinationPath -Force
            $script:mockScpExitCode = 1
            $transportRequest = New-DurableTransferRequest `
                -Source 'user@server:/data' `
                -Destination $destinationPath `
                -Transport Scp `
                -SshKeyPath $keyPath
            {
                Invoke-DurableTransfer `
                    -Request $transportRequest `
                    -MetricsPath $transportMetricsPath `
                    -Confirm:$false
            } | Should -Throw '*SCP failed with exit code 1*'
            $transportMetric = Get-Content -LiteralPath $transportMetricsPath |
                ForEach-Object { ConvertFrom-Json $_ } |
                Select-Object -Last 1
            $transportMetric.status | Should -Be 'Failed'
            $transportMetric.verificationState | Should -Be 'not-requested'
        }
    }

    It 'reports Robocopy retry and restart observations from its log' {
        InModuleScope DTMS.Transfer -Parameters @{
            Root = $TestDrive
        } {
            param($Root)

            $sourcePath = Join-Path $Root 'robocopy-source.txt'
            $destinationPath = Join-Path $Root 'robocopy-destination'
            $metricsPath = Join-Path $Root 'robocopy-metrics.jsonl'
            Set-Content -LiteralPath $sourcePath -Value 'data'
            function Start-DTMSActivity {
                [CmdletBinding(SupportsShouldProcess)]
                param([string]$Name, [string]$Intent, [string]$Target)
                @($Name, $Intent, $Target) | Out-Null
                $PSCmdlet.ShouldProcess($Target, $Intent) | Out-Null
            }
            function Update-DTMSActivity {
                [CmdletBinding(SupportsShouldProcess)]
                param(
                    $Activity,
                    [string]$Status,
                    [switch]$ForceHeartbeat,
                    [double]$PercentComplete,
                    [switch]$Failed
                )
                @($Activity, $Status, $ForceHeartbeat, $PercentComplete, $Failed) |
                    Out-Null
                $PSCmdlet.ShouldProcess($Status, 'Update activity') | Out-Null
            }
            function Complete-DTMSActivity {}
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Robocopy'
                        Available = $true
                        Executable = 'robocopy.exe'
                        Capabilities = [pscustomobject]@{
                            Restartable = $true
                            PreservesAcl = $true
                            Encrypted = $false
                            Ssh = $false
                            TargetInitiated = $false
                            ChecksumVerification = $true
                        }
                    }
                )
            }
            Mock Start-DTMSActivity { [pscustomobject]@{ Id = 'transfer' } }
            Mock Update-DTMSActivity {}
            Mock Complete-DTMSActivity {}
            Mock Start-Process {
                param($ArgumentList)
                $robocopyLog = $ArgumentList |
                    Where-Object { $_ -like '/LOG+:*' } |
                    ForEach-Object { $_.Substring(6) }
                @('Retrying...', 'Restarting...') |
                    Set-Content -LiteralPath $robocopyLog
                [pscustomobject]@{ HasExited = $true; ExitCode = 1 }
            }
            $request = New-DurableTransferRequest `
                -Source $sourcePath `
                -Destination $destinationPath `
                -Transport Robocopy `
                -RequireResume

            $result = Invoke-DurableTransfer `
                -Request $request `
                -MetricsPath $metricsPath `
                -Confirm:$false

            $result.RetryCount | Should -Be 1
            $result.ResumeCount | Should -Be 1
            $terminalMetric = Get-Content -LiteralPath $metricsPath |
                ForEach-Object { ConvertFrom-Json $_ } |
                Select-Object -Last 1
            $terminalMetric.retryCount | Should -Be 1
            $terminalMetric.resumeCount | Should -Be 1
        }
    }

    It 'handles a repeated BITS transient error only once until it changes' {
        InModuleScope DTMS.Transfer -Parameters @{
            Root = $TestDrive
        } {
            param($Root)

            function Start-BitsTransfer {
                [CmdletBinding(SupportsShouldProcess)]
                param(
                    [string]$Source,
                    [string]$Destination,
                    [string]$DisplayName,
                    [string]$Description,
                    [string]$Priority,
                    [switch]$Asynchronous
                )
                @(
                    $Source,
                    $Destination,
                    $DisplayName,
                    $Description,
                    $Priority,
                    $Asynchronous
                ) | Out-Null
                $PSCmdlet.ShouldProcess($Destination, 'Start BITS transfer') |
                    Out-Null
            }
            function Resume-BitsTransfer {
                [CmdletBinding()]
                param($BitsJob, [switch]$Asynchronous)
                @($BitsJob, $Asynchronous) | Out-Null
            }
            function Get-BitsTransfer {
                [CmdletBinding()]
                param([string]$JobId)
                $JobId | Out-Null
            }
            function Complete-BitsTransfer {
                [CmdletBinding()]
                param($BitsJob)
                $BitsJob | Out-Null
            }
            function Start-DTMSActivity {
                [CmdletBinding(SupportsShouldProcess)]
                param([string]$Name, [string]$Intent, [string]$Target)
                @($Name, $Intent, $Target) | Out-Null
                $PSCmdlet.ShouldProcess($Target, $Intent) | Out-Null
            }
            function Update-DTMSActivity {
                [CmdletBinding(SupportsShouldProcess)]
                param(
                    $Activity,
                    [string]$Status,
                    [switch]$ForceHeartbeat,
                    [double]$PercentComplete,
                    [switch]$Failed
                )
                @($Activity, $Status, $ForceHeartbeat, $PercentComplete, $Failed) |
                    Out-Null
                $PSCmdlet.ShouldProcess($Status, 'Update activity') | Out-Null
            }
            function Complete-DTMSActivity {}
            $script:bitsPollCount = 0
            Mock Get-DurableTransferProvider {
                @(
                    [pscustomobject]@{
                        Name = 'Bits'
                        Available = $true
                        Executable = 'Background Intelligent Transfer Service'
                        Capabilities = [pscustomobject]@{
                            Restartable = $true
                            PreservesAcl = $false
                            Encrypted = $false
                            Ssh = $false
                            TargetInitiated = $false
                            ChecksumVerification = $true
                        }
                    }
                )
            }
            Mock Start-DTMSActivity { [pscustomobject]@{ Id = 'transfer' } }
            Mock Update-DTMSActivity {}
            Mock Complete-DTMSActivity {}
            Mock Import-Module {}
            Mock Start-BitsTransfer {
                [pscustomobject]@{
                    JobId = 'job'
                    JobState = 'TransientError'
                    ErrorCode = 10
                    ErrorDescription = 'temporary network interruption'
                    BytesTransferred = 0
                    BytesTotal = 1
                }
            }
            Mock Resume-BitsTransfer {}
            Mock Start-Sleep {}
            Mock Get-BitsTransfer {
                $script:bitsPollCount++
                if ($script:bitsPollCount -eq 1) {
                    [pscustomobject]@{
                        JobId = 'job'
                        JobState = 'TransientError'
                        ErrorCode = 10
                        ErrorDescription = 'temporary network interruption'
                        BytesTransferred = 0
                        BytesTotal = 1
                    }
                } else {
                    [pscustomobject]@{
                        JobId = 'job'
                        JobState = 'Transferred'
                        ErrorCode = 0
                        ErrorDescription = $null
                        BytesTransferred = 1
                        BytesTotal = 1
                    }
                }
            }
            Mock Complete-BitsTransfer {}
            $request = New-DurableTransferRequest `
                -Source '\\server\share\source' `
                -Destination (Join-Path $Root 'bits-destination') `
                -Transport Bits `
                -RequireResume

            $result = Invoke-DurableTransfer -Request $request -Confirm:$false

            $result.RetryCount | Should -Be 1
            $result.ResumeCount | Should -Be 1
            Should -Invoke Resume-BitsTransfer -Exactly -Times 1
        }
    }
}
