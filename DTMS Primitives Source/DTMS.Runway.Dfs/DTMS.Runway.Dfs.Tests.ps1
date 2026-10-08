BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot 'DTMS.Runway.Dfs.psd1'
    Import-Module $script:modulePath -Force
}

Describe 'DTMS.Runway.Dfs contract' {
    It 'exports registry provider commands' {
        @(Get-Command -Module DTMS.Runway.Dfs) | Should -HaveCount 5
    }

    It 'publishes and reduces append-only operation events' {
        $operationRoot = Join-Path $TestDrive 'operation'
        $outbox = Join-Path $operationRoot 'Outbox'
        $registry = Join-Path $TestDrive 'registry'
        New-Item $outbox, $registry -ItemType Directory -Force | Out-Null
        @{
            SchemaVersion = 1; OperationId = 'operation-1'
            Status = 'Running'; CurrentPhase = 'Working'
            EventSequence = 2
        } | ConvertTo-Json | Set-Content (Join-Path $operationRoot 'State.json')
        @(
            @{ sequence = 1; eventId = 'event-1'; operationId = 'operation-1'
                operationType = 'Example'; eventType = 'PhaseChanged'
                status = 'Running'; phase = 'Working'
                recordedUtc = '2026-10-05T00:00:00Z'; progressPercent = 50 }
            @{ sequence = 2; eventId = 'event-2'; operationId = 'operation-1'
                operationType = 'Example'; eventType = 'OperationCompleted'
                status = 'Succeeded'; phase = 'Completed'
                recordedUtc = '2026-10-05T01:00:00Z'; progressPercent = 100 }
        ) | ForEach-Object {
            $_ | ConvertTo-Json | Set-Content (
                Join-Path $outbox ('{0:D8}-{1}.json' -f $_.sequence, $_.eventId)
            )
        }

        $sync = Sync-DurableOperationRegistry `
            -OperationRoot $operationRoot `
            -NamespacePath $registry
        $result = Get-DurableOperationRegistry -NamespacePath $registry

        $sync.Synchronized | Should -BeTrue
        $result.OperationId | Should -Be 'operation-1'
        $result.Status | Should -Be 'Succeeded'
        $result.ProgressPercent | Should -Be 100
        $result.RegistryHistoryComplete | Should -BeTrue
    }

    It 'uses terminal events even when earlier events have not replicated' {
        $registry = Join-Path $TestDrive 'terminal-registry'
        $events = Join-Path $registry 'operation-2\Events'
        New-Item $events -ItemType Directory -Force | Out-Null
        @{
            sequence = 8; eventId = 'event-8'; operationId = 'operation-2'
            eventType = 'OperationCompleted'; status = 'Succeeded'
            phase = 'Completed'; recordedUtc = '2026-10-05T01:00:00Z'
            progressPercent = 100
        } | ConvertTo-Json | Set-Content (Join-Path $events '00000008-event-8.json')

        $result = Get-DurableOperationRegistry -NamespacePath $registry

        $result.Status | Should -Be 'Succeeded'
        $result.RegistryHistoryComplete | Should -BeFalse
    }

    It 'defines the DFS-R provisioning contract' {
        $command = Get-Command Initialize-DurableOperationDfsRegistry
        $text = Get-Content (Join-Path $PSScriptRoot 'DTMS.Runway.Dfs.psm1') -Raw

        $command.Parameters.Keys | Should -Contain 'UtilityServer'
        $command.Parameters.Keys | Should -Contain 'WriterPrincipal'
        $command.Parameters.Keys | Should -Contain 'Credential'
        $text | Should -Match 'Registry provisioning preflight failed on'
        $text | Should -Match 'WindowsBuiltInRole\]::Administrator'
        $text | Should -Match 'New-DfsnFolder'
        $text | Should -Match 'Add-DfsrConnection'
        $text | Should -Match '\*\.partial'
        $text | Should -Match 'Start-DTMSActivity'
        $text | Should -Match 'Update-DTMSActivity'
        $text | Should -Match 'Complete-DTMSActivity'
    }

    It 'requires immediate feedback in long-running registry commands' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot 'DTMS.Runway.Dfs.psm1'),
            [ref]$tokens,
            [ref]$errors
        )
        foreach ($functionName in @(
            'Sync-DurableOperationRegistry'
            'Invoke-DurableOperationRegistryRetention'
            'Initialize-DurableOperationDfsRegistry'
        )) {
            $functionAst = $ast.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
            }, $true)
            $functionAst.Body.Extent.Text | Should -Match 'Start-DTMSActivity'
        }
    }
}
