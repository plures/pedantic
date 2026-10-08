BeforeAll {
    $script:manifest = Join-Path $PSScriptRoot 'DTMS.Configuration.psd1'
    Import-Module $script:manifest -Force
}

Describe 'DTMS.Configuration' {
    It 'declares PowerShell 7 as primary and 5.1 as the compatibility floor' {
        $manifest = Test-ModuleManifest -Path $script:manifest
        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
        $manifest.CompatiblePSEditions[0] | Should -Be 'Core'
        $manifest.PrivateData.DTMSRuntime.PreferredPSEdition |
            Should -Be 'Core'
        $manifest.PrivateData.DTMSRuntime.PreferredPowerShellVersion |
            Should -Be '7.0'
        $manifest.PrivateData.DTMSRuntime.MinimumPowerShellVersion |
            Should -Be '5.1'
    }

    It 'uses the organization gMSA and PowerShell 7-preferred defaults' {
        $configuration = Get-DTMSConfiguration `
            -Path (Join-Path $TestDrive 'missing.json')

        $configuration.SchemaVersion | Should -Be 1
        $configuration.Execution.DefaultAccount |
            Should -Be 'USME\_is_dtms_util$'
        $configuration.Execution.PowerShellEngine | Should -Be 'Auto'
        $configuration.Execution.TaskPath | Should -Be '\DTMS\'
    }

    It 'merges file and per-operation overrides without losing defaults' {
        $path = Join-Path $TestDrive 'DTMS.Utilities.json'
        @{
            SchemaVersion = 1
            Execution = @{ PollIntervalMinutes = 12 }
        } | ConvertTo-Json -Depth 5 | Set-Content $path

        $configuration = Get-DTMSConfiguration `
            -Path $path `
            -Override @{ Runway = @{ RebootDelaySeconds = 90 } }

        $configuration.Execution.PollIntervalMinutes | Should -Be 12
        $configuration.Execution.DefaultAccount |
            Should -Be 'USME\_is_dtms_util$'
        $configuration.Runway.RebootDelaySeconds | Should -Be 90
    }

    It 'round trips validated configuration atomically' {
        $path = Join-Path $TestDrive 'Configuration\DTMS.Utilities.json'
        $result = Initialize-DTMSConfiguration -Path $path

        Test-Path $path | Should -BeTrue
        $result.ConfigurationPath | Should -Be $path
        @(Get-ChildItem (Split-Path $path) -Filter '*.tmp').Count |
            Should -Be 0
    }

    It 'validates named OpenSSH controller profiles' {
        $configuration = Get-DTMSConfiguration `
            -Path (Join-Path $TestDrive 'missing.json')
        $configuration.OpenSSH.ControllerProfiles = @{
            PHX23 = @{ HostName = 'PHX23ISUTIL01' }
        }

        (
            @(Test-DTMSConfiguration -Configuration $configuration) -join ' '
        ) | Should -Match 'PHX23.+UserName'
    }
}
