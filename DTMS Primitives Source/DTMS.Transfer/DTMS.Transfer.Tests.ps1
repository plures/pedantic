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
                        }
                    }
                    [pscustomobject]@{
                        Name = 'Scp'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $false
                            PreservesAcl = $false
                            Encrypted = $true
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
                        }
                    }
                    [pscustomobject]@{
                        Name = 'Scp'
                        Available = $true
                        Capabilities = [pscustomobject]@{
                            Restartable = $false
                            PreservesAcl = $false
                            Encrypted = $true
                        }
                    }
                )
            }
            $request = New-DurableTransferRequest `
                -Source 'user@server:D:/VMs/disk.vhdx' `
                -Destination 'D:\VMs\disk.vhdx'

            (Select-DurableTransferProvider $request).Provider.Name |
                Should -Be 'Scp'
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
        $request = New-DurableTransferRequest `
            -Source '\\server\share\disk.vhdx' `
            -Destination 'D:\VMs\disk.vhdx' `
            -Transport Bits `
            -RequireResume

        (Select-DurableTransferProvider $request).Provider.Name |
            Should -Be 'Bits'
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

    It 'uses only typed transfer inputs and validates target-initiated SCP keys' {
        $command = Get-Command New-DurableTransferRequest
        $text = Get-Content (Join-Path $PSScriptRoot 'DTMS.Transfer.psm1') -Raw

        $command.Parameters.Keys | Should -Not -Contain 'AdditionalArgument'
        $command.Parameters.Keys | Should -Contain 'SshKeyPath'
        $text | Should -Match 'SCP transfers must be initiated by the target'
        $text | Should -Match 'validated target-local SSH key path'
    }

    It 'records selection evaluation and verification telemetry' {
        $text = Get-Content (Join-Path $PSScriptRoot 'DTMS.Transfer.psm1') -Raw

        $text | Should -Match 'Evaluation = \$evaluations'
        $text | Should -Match 'retryCount'
        $text | Should -Match 'resumeCount'
        $text | Should -Match 'verificationState'
        $text | Should -Match 'Transfer verification failed'
    }
}

Describe 'DTMS.Transfer terminal telemetry contract' {
    It 'records both successful and failed terminal metric samples' {
        $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DTMS.Transfer.psm1') -Raw

        $text | Should -Match "'Succeeded' 'Transfer completed successfully\.'"
        $text | Should -Match "'Failed'"
        $text | Should -Match '\$_\.Exception\.Message'
    }

    It 'announces and updates long-running transfer activity' {
        $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DTMS.Transfer.psm1') -Raw

        $text | Should -Match 'Start-DTMSActivity'
        $text | Should -Match 'Update-DTMSActivity'
        $text | Should -Match 'Complete-DTMSActivity'
    }
}
