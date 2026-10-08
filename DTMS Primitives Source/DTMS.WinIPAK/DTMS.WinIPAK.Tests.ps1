BeforeAll {
    $env:DTMS_RUNWAY_STARTUP_MODE = 'Quiet'
    Import-Module (Join-Path $PSScriptRoot 'DTMS.WinIPAK.psd1') -Force
}

Describe 'DTMS.WinIPAK contract' {
    It 'creates a staged reboot-safe Forge plan' {
        $plan = New-WinIPAKPlan `
            -WinIPAKSource '\\files\software\WinIPAK' `
            -RequiredOsBuild 26100

        $plan.ExecutionAccount | Should -Be 'USME\_is_dtms_util$'
        @($plan.Steps | Where-Object Stage -eq Preparation) |
            Should -HaveCount 1
        @($plan.Steps | Where-Object Stage -eq Execution) |
            Should -HaveCount 1
        $plan.PollIntervalMinutes | Should -Be 5
    }

    It 'supports an existing target-local executable' {
        $plan = New-WinIPAKPlan `
            -WinIPAKPath 'C:\Tools\winipak.exe'

        @($plan.Steps | Where-Object Kind -eq Copy) |
            Should -HaveCount 0
    }

    It 'rejects mutually exclusive build requirements' {
        {
            New-WinIPAKPlan `
                -WinIPAKPath 'C:\Tools\winipak.exe' `
                -RequiredOsBuild 26100 `
                -MinimumOsBuild 20348
        } | Should -Throw '*mutually exclusive*'
    }

    It 'uses Runway suspension and reboot continuation without a scheduler' {
        $text = Get-Content `
            (Join-Path $PSScriptRoot 'DTMS.WinIPAK.psm1') -Raw

        $text | Should -Match 'Suspend-DurableOperation'
        $text | Should -Match 'Request-DurableOperationReboot'
        $text | Should -Not -Match 'Register-ScheduledTask'
        $text | Should -Not -Match 'TaskForge'
    }
}
