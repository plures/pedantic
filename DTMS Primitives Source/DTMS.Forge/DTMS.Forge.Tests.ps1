BeforeAll {
    $script:manifest = Join-Path $PSScriptRoot 'DTMS.Forge.psd1'
    $env:DTMS_RUNWAY_STARTUP_MODE = 'Quiet'
    Import-Module $script:manifest -Force
}

Describe 'DTMS.Forge plan contract' {
    It 'exports only the clean Runway-backed API' {
        $commands = @(Get-Command -Module DTMS.Forge |
            Select-Object -ExpandProperty Name)

        $commands | Should -HaveCount 6
        $commands | Should -Contain 'New-ForgePlan'
        $commands | Should -Contain 'Start-ForgePlan'
        $commands | Should -Not -Contain 'Start-TaskForge'
    }

    It 'defaults execution to the centrally configured gMSA' {
        $step = New-ForgeStep -Name work -ScriptBlock {
            param($Context)
            $Context.StepName
        }
        $plan = New-ForgePlan -Name test -Step $step

        $plan.ExecutionAccount | Should -Be 'USME\_is_dtms_util$'
        $plan.AccountType | Should -Be 'GroupManagedServiceAccount'
        $plan.HasNetworkAccess | Should -BeTrue
        $plan.Steps[0].Stage | Should -Be 'Execution'
    }

    It 'places copy work in caller-context preparation' {
        $step = New-ForgeCopyStep `
            -Name media `
            -Source '\\server\share\media' `
            -Destination Media

        $step.Stage | Should -Be 'Preparation'
        $step.RequiresNetwork | Should -BeTrue
        $step.Kind | Should -Be 'Copy'
    }

    It 'rejects preparation dependencies on durable execution' {
        $execution = New-ForgeStep -Name execute -ScriptBlock {
            param($Context)
            $Context.StepName
        }
        $preparation = New-ForgeStep `
            -Name prepare `
            -Stage Preparation `
            -DependsOn execute `
            -ScriptBlock { param($Context) $Context.StepName }

        {
            New-ForgePlan -Name invalid -Step @($execution, $preparation)
        } | Should -Throw '*cannot depend on execution step*'
    }

    It 'rejects dependency cycles' {
        $first = New-ForgeStep -Name first -DependsOn second `
            -ScriptBlock { param($Context) $Context.StepName }
        $second = New-ForgeStep -Name second -DependsOn first `
            -ScriptBlock { param($Context) $Context.StepName }

        {
            New-ForgePlan -Name cycle -Step @($first, $second)
        } | Should -Throw '*dependency cycle*'
    }

    It 'requires explicit credentials for normal domain execution accounts' {
        $step = New-ForgeStep -Name work -ScriptBlock {
            param($Context)
            $Context.StepName
        }
        $plan = New-ForgePlan `
            -Name user `
            -Step $step `
            -ExecutionAccount 'USME\operator'

        {
            Start-ForgePlan -Plan $plan -WhatIf
        } | Should -Throw '*ExecutionCredential is required*'
    }
}

Describe 'Invoke-ForgeWorkflow' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach ($directory in @('', 'Checkpoints', 'Outbox')) {
            New-Item -Path (Join-Path $script:root $directory) `
                -ItemType Directory -Force | Out-Null
        }
        @{
            SchemaVersion = 1
            OperationId = 'test-operation'
            OperationType = 'DTMS.Forge.Workflow'
            Status = 'Running'
            CurrentPhase = 'Starting'
            EventSequence = 0
            ProgressPercent = 0
            AttemptCount = 0
            ExecutionAccount = 'USME\_is_dtms_util$'
            CreatedUtc = [DateTime]::UtcNow.ToString('o')
            UpdatedUtc = [DateTime]::UtcNow.ToString('o')
            StartedUtc = $null
            CompletedUtc = $null
            Message = $null
            Metadata = @{}
            PhaseHistory = @()
        } | ConvertTo-Json -Depth 10 |
            Set-Content (Join-Path $script:root 'State.json')
    }

    It 'executes dependency-ordered steps and checkpoints completion' {
        $payload = @{
            Data = @{ Value = 'expected' }
            StagingRoot = $script:root
            Steps = @(
                @{
                    Name = 'first'
                    DependsOn = @()
                    Description = 'First'
                    RetryFailed = $false
                    RetryInterrupted = $false
                    Script = 'param($Context) Set-Content (Join-Path $Context.OperationRoot "first.txt") $Context.Data.Value'
                }
                @{
                    Name = 'second'
                    DependsOn = @('first')
                    Description = 'Second'
                    RetryFailed = $false
                    RetryInterrupted = $false
                    Script = 'param($Context) if (-not (Test-Path (Join-Path $Context.OperationRoot "first.txt"))) { throw "missing output" }'
                }
            )
        }

        Invoke-ForgeWorkflow `
            -OperationRoot $script:root `
            -Payload $payload
        $checkpoint = Get-Content `
            (Join-Path $script:root 'Checkpoints\ForgeSteps.json') `
            -Raw | ConvertFrom-Json

        @($checkpoint.Steps | Where-Object Status -eq Completed) |
            Should -HaveCount 2
        Get-Content (Join-Path $script:root 'first.txt') |
            Should -Be expected
    }
}
