BeforeAll {
    $env:DTMS_RUNWAY_STARTUP_MODE = 'Quiet'
    Import-Module (Join-Path $PSScriptRoot 'DTMS.OSInstall.psd1') -Force
}

Describe 'DTMS.OSInstall contract' {
    It 'builds a Runway-backed scan plan with caller-context media staging' {
        $plan = New-WindowsServerInstallPlan `
            -MediaSource '\\files\images\WindowsServer' `
            -Operation Scan `
            -AcceptEula

        $plan.PSObject.TypeNames | Should -Contain 'DTMS.Forge.Plan'
        $plan.ExecutionAccount | Should -Be 'USME\_is_dtms_util$'
        @($plan.Steps | Where-Object Stage -eq Preparation) |
            Should -HaveCount 1
        @($plan.Steps | Where-Object Stage -eq Execution) |
            Should -HaveCount 2
    }

    It 'supports existing target-local media without a copy step' {
        $plan = New-WindowsServerInstallPlan `
            -MediaPath 'D:\Media' `
            -Operation Upgrade `
            -AcceptEula

        @($plan.Steps | Where-Object Kind -eq Copy) |
            Should -HaveCount 0
    }

    It 'requires an exact single-target confirmation for clean install' {
        {
            Start-WindowsServerInstall `
                -MediaPath 'D:\Media' `
                -ComputerName $env:COMPUTERNAME `
                -Operation CleanInstall `
                -AcceptEula `
                -CleanInstallConfirmation CLEAN `
                -WhatIf
        } | Should -Throw '*equal to its ComputerName*'
    }

    It 'uses generic Runway suspension for setup completion polling' {
        $text = Get-Content `
            (Join-Path $PSScriptRoot 'DTMS.OSInstall.psm1') -Raw

        $text | Should -Match 'Suspend-DurableOperation'
        $text | Should -Not -Match 'Register-ScheduledTask'
        $text | Should -Not -Match 'TaskForge'
    }
}
