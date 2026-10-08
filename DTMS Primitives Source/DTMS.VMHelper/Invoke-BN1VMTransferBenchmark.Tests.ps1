BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot 'Invoke-BN1VMTransferBenchmark.ps1'
    $script:text = Get-Content -LiteralPath $script:scriptPath -Raw
    $tokens = $null
    $errors = $null
    $script:ast = [Management.Automation.Language.Parser]::ParseFile(
        $script:scriptPath,
        [ref]$tokens,
        [ref]$errors
    )
    $script:parseErrors = @($errors)
}

Describe 'BN1 VM transfer benchmark contract' {
    It 'parses without errors' {
        $script:parseErrors | Should -HaveCount 0
    }

    It 'contains the five approved source and target mappings' {
        1..5 | ForEach-Object {
            $script:text | Should -Match "BN1USMEPRXYXGW$_"
            $script:text | Should -Match "BN1CPSUSMEPRXYXGW$_"
        }
    }

    It 'allocates two Robocopy, two SCP, and one BITS transfer' {
        @([regex]::Matches($script:text, "Transport = 'Robocopy'")) |
            Should -HaveCount 2
        @([regex]::Matches($script:text, "Transport = 'Scp'")) |
            Should -HaveCount 2
        @([regex]::Matches($script:text, "Transport = 'Bits'")) |
            Should -HaveCount 1
    }

    It 'guards infrastructure and transfer mutations with ShouldProcess' {
        $script:text | Should -Match 'SupportsShouldProcess'
        $script:text | Should -Match 'ConfirmImpact\s*=\s*''High'''
        $script:text | Should -Match 'PrepareInfrastructure.+ShouldProcess'
        $script:text | Should -Match 'StartTransfers'
        $script:text | Should -Match 'PSCmdlet\.ShouldProcess'
    }

    It 'validates SSH before launching transfers and persists comparative reports' {
        $script:text | Should -Match 'Test-NetConnection'
        $script:text | Should -Match 'BatchMode=yes'
        $script:text | Should -Match 'Watch-VMResourceTransfer'
        $script:text | Should -Match 'Get-VMResourceTransferPerformanceReport'
        $script:text | Should -Match 'Performance\.csv'
        $script:text | Should -Match 'Performance\.json'
    }

    It 'configures all-target federated collectors during explicit preparation' {
        $script:text | Should -Match 'Initialize-VMResourceTransferFederation'
        $script:text | Should -Match 'FederatedUtilityServerPattern'
        $script:text | Should -Match '-TargetHostName \$targetHosts'
        $script:text | Should -Match '-CollectorAccount \$TransferAccount'
        $script:text | Should -Match '-RetentionCount 90'
        $script:text | Should -Match 'SkipFederatedRegistry'
    }

    It 'performs one wildcard discovery pass and safely filters diagnostic results' {
        @([regex]::Matches($script:text, 'Find-VMHost @discoveryParameters')) |
            Should -HaveCount 1
        $script:text | Should -Match 'IncludeQueryErrors'
        $script:text | Should -Match 'DiscoveryComputerName'
        $script:text | Should -Match "PSObject\.Properties\['HostName'\]"
        $script:text | Should -Match 'no accessible queried host'
    }

    It 'supports explicit VM-to-host mappings without AD candidate discovery' {
        $script:text | Should -Match '\[hashtable\]\$VMHostMap'
        $script:text | Should -Match '\[string\]\$VMHostMapPath'
        $script:text | Should -Match '\$HostMap\.ContainsKey\(\$VMName\)'
        $script:text | Should -Match '\$unmappedVMNames\.Count -gt 0'
        $script:text | Should -Match 'VMName and HostName values'
        $script:text | Should -Match 'VMs are not discovered'
    }

    It 'announces intent before discovery and uses the shared activity lifecycle' {
        $script:text | Should -Match '\[DTMS\] START BN1 VM transfer benchmark'
        $script:text | Should -Match 'Start-DTMSActivity'
        $script:text | Should -Match 'Update-DTMSActivity'
        $script:text | Should -Match 'Complete-DTMSActivity'
    }
}
