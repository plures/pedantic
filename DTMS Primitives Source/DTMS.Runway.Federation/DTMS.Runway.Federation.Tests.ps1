BeforeAll {
    $env:DTMS_RUNWAY_STARTUP_MODE = 'Quiet'
    Import-Module (
        Join-Path $PSScriptRoot 'DTMS.Runway.Federation.psd1'
    ) -Force
}

Describe 'DTMS.Runway.Federation contract' {
    It 'exports setup, synchronization, and query commands' {
        $commands = @(Get-Command -Module DTMS.Runway.Federation |
            Select-Object -ExpandProperty Name)

        $commands | Should -Be @(
            'Get-DurableOperationFederated'
            'Initialize-DurableOperationFederation'
            'Sync-DurableOperationFederation'
        )
    }

    It 'uses target-local state and independent pull indexes without DFS' {
        $moduleText = Get-Content `
            (Join-Path $PSScriptRoot 'DTMS.Runway.Federation.psm1') -Raw
        $collectorText = Get-Content `
            (Join-Path $PSScriptRoot `
                'Invoke-DurableOperationFederatedCollector.ps1') -Raw

        $moduleText | Should -Match 'TargetComputerName'
        $collectorText | Should -Match 'State\.json'
        $collectorText | Should -Match 'Current\.json'
        $moduleText | Should -Not -Match 'Dfsr|Dfsn'
        $collectorText | Should -Not -Match 'Dfsr|Dfsn'
    }

    It 'defaults collection to the configured gMSA' {
        $command = Get-Command Initialize-DurableOperationFederation

        $command.Parameters.Keys | Should -Contain 'CollectorAccount'
        $command.Parameters.Keys | Should -Contain 'Credential'
        $command.Parameters.Keys | Should -Contain 'WhatIf'
    }
}
