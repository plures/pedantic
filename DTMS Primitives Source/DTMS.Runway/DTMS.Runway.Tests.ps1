BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot 'DTMS.Runway.psd1'
    $script:originalStartupMode = $env:DTMS_RUNWAY_STARTUP_MODE
    $env:DTMS_RUNWAY_STARTUP_MODE = 'Quiet'
    Import-Module $script:modulePath -Force
}

AfterAll {
    $env:DTMS_RUNWAY_STARTUP_MODE = $script:originalStartupMode
}

Describe 'DTMS.Runway contract' {
    It 'exports the supported durable-operation commands' {
        $commands = @(Get-Command -Module DTMS.Runway | Select-Object -ExpandProperty Name)

        $commands | Should -HaveCount 15
        $commands | Should -Contain 'Start-DurableOperation'
        $commands | Should -Contain 'Start-DTMSActivity'
        $commands | Should -Contain 'Update-DTMSActivity'
        $commands | Should -Contain 'Complete-DTMSActivity'
        $commands | Should -Contain 'Get-DurableOperationReadiness'
        $commands | Should -Contain 'Set-DurableOperationPhase'
        $commands | Should -Contain 'Suspend-DurableOperation'
        $commands | Should -Contain 'Request-DurableOperationReboot'
    }

    It 'announces intent immediately and supports concise progress' {
        $originalMode = $env:DTMS_FEEDBACK_MODE
        try {
            $env:DTMS_FEEDBACK_MODE = 'Concise'
            $notices = @()
            $activity = Start-DTMSActivity `
                -Name 'Example activity' `
                -Intent 'Demonstrate immediate feedback' `
                -InformationVariable notices

            $activity.Animated | Should -BeFalse
            $notices.MessageData | Should -Match '\[DTMS\] START Example activity'
            Complete-DTMSActivity -Activity $activity
        } finally {
            $env:DTMS_FEEDBACK_MODE = $originalMode
        }
    }

    It 'supports PowerShell 7 and Windows PowerShell 5.1' {
        $manifest = Test-ModuleManifest $script:modulePath

        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
    }

    It 'creates standard readiness results' {
        $result = New-DurableOperationReadinessResult `
            -Module Example `
            -Capability ExampleCapability `
            -Status Ready `
            -Required $false `
            -Message 'Ready'

        $result.PSObject.TypeNames | Should -Contain 'DTMS.Runway.Readiness'
        $result.Status | Should -Be 'Ready'
    }
}

Describe 'Durable operation state' {
    BeforeEach {
        $script:operationRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:operationRoot -ItemType Directory | Out-Null
        $script:handlerPath = Join-Path $TestDrive 'ExampleHandler.psm1'
        'function Invoke-ExampleOperation { param($OperationRoot, $Payload) }' |
            Set-Content -LiteralPath $script:handlerPath
        $script:definition = New-DurableOperationDefinition `
            -OperationType 'Example.Operation' `
            -HandlerModulePath $script:handlerPath `
            -HandlerCommand 'Invoke-ExampleOperation' `
            -Payload @{ Value = 42 } `
            -Metadata @{ Name = 'Example' }
    }

    It 'persists a versioned definition, state, and immutable queued event' {
        $operation = New-DurableOperation `
            -Definition $script:definition `
            -OperationRoot $script:operationRoot `
            -Confirm:$false

        $definition = Get-Content `
            -LiteralPath (Join-Path $operation.OperationRoot 'Definition.json') `
            -Raw | ConvertFrom-Json
        $state = Get-Content `
            -LiteralPath (Join-Path $operation.OperationRoot 'State.json') `
            -Raw | ConvertFrom-Json
        $events = @(Get-ChildItem (Join-Path $operation.OperationRoot 'Outbox') -File)

        $definition.SchemaVersion | Should -Be 1
        $definition.OperationType | Should -Be 'Example.Operation'
        $state.Status | Should -Be 'Queued'
        $state.ExecutionAccount | Should -Be 'USME\_is_dtms_util$'
        $state.EventSequence | Should -Be 1
        $events | Should -HaveCount 1
    }

    It 'checkpoints phases without duplicating repeated phase history' {
        $operation = New-DurableOperation `
            -Definition $script:definition `
            -OperationRoot $script:operationRoot `
            -Confirm:$false

        Set-DurableOperationPhase `
            -OperationRoot $operation.OperationRoot `
            -Phase Working `
            -Message 'First' | Out-Null
        Set-DurableOperationPhase `
            -OperationRoot $operation.OperationRoot `
            -Phase Working `
            -Message 'Progress' `
            -ProgressPercent 50 | Out-Null
        $state = Get-Content `
            -LiteralPath (Join-Path $operation.OperationRoot 'State.json') `
            -Raw | ConvertFrom-Json

        @($state.PhaseHistory).Phase | Should -Be @('Queued', 'Working')
        $state.ProgressPercent | Should -Be 50
        $state.EventSequence | Should -Be 3
    }

    It 'lists active and latest operations from local state' {
        $first = New-DurableOperation `
            -Definition $script:definition `
            -OperationRoot $script:operationRoot `
            -Confirm:$false
        Start-Sleep -Milliseconds 20
        $second = New-DurableOperation `
            -Definition $script:definition `
            -OperationRoot $script:operationRoot `
            -Confirm:$false
        Set-DurableOperationPhase `
            -OperationRoot $first.OperationRoot `
            -Phase Completed `
            -Status Succeeded | Out-Null

        @(Get-DurableOperation -OperationRoot $script:operationRoot -Active) |
            Should -HaveCount 1
        (Get-DurableOperation -OperationRoot $script:operationRoot -Latest).OperationId |
            Should -Be $first.OperationId
        $second.OperationId | Should -Not -BeNullOrEmpty
    }

    It 'checkpoints a waiting operation without completing it' {
        $operation = New-DurableOperation `
            -Definition $script:definition `
            -OperationRoot $script:operationRoot `
            -Confirm:$false
        $resumeAfter = [DateTime]::UtcNow.AddMinutes(10)

        $result = Suspend-DurableOperation `
            -OperationRoot $operation.OperationRoot `
            -Reason 'Waiting for maintenance.' `
            -ResumeAfterUtc $resumeAfter
        $state = Get-Content `
            -LiteralPath (Join-Path $operation.OperationRoot 'State.json') `
            -Raw | ConvertFrom-Json

        $result.PSObject.TypeNames |
            Should -Contain 'DTMS.Runway.Suspension'
        $state.Status | Should -Be 'Waiting'
        $state.CompletedUtc | Should -BeNullOrEmpty
        @(Get-DurableOperation -OperationRoot $script:operationRoot -Active) |
            Should -HaveCount 1
    }

    It 'records the boot session before requesting reboot continuation' {
        Mock -ModuleName DTMS.Runway Get-CimInstance {
            [pscustomobject]@{
                LastBootUpTime = [DateTime]::UtcNow.AddHours(-2)
            }
        }
        $operation = New-DurableOperation `
            -Definition $script:definition `
            -OperationRoot $script:operationRoot `
            -Confirm:$false

        $result = Request-DurableOperationReboot `
            -OperationRoot $operation.OperationRoot
        $state = Get-Content `
            -LiteralPath (Join-Path $operation.OperationRoot 'State.json') `
            -Raw | ConvertFrom-Json

        $result.Status | Should -Be 'AwaitingReboot'
        $state.RebootBootUtc | Should -Not -BeNullOrEmpty
        $state.Status | Should -Be 'AwaitingReboot'
    }
}
