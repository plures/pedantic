BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot 'DTMS.Utilities.psd1'
    Import-Module $script:modulePath -ArgumentList 'Quiet' -Force
}

Describe 'DTMS.Utilities umbrella contract' {
    It 'declares PowerShell 7 first with a 5.1 compatibility floor everywhere' {
        $manifestPaths = Get-ChildItem `
            -LiteralPath (Split-Path $PSScriptRoot) `
            -Recurse `
            -File `
            -Filter '*.psd1'

        $manifestPaths | Should -HaveCount 11
        foreach ($manifestPath in $manifestPaths) {
            $manifest = Test-ModuleManifest `
                -Path $manifestPath.FullName `
                -ErrorAction Stop

            $manifest.PowerShellVersion | Should -Be ([version]'5.1')
            $manifest.CompatiblePSEditions[0] | Should -Be 'Core'
            $manifest.PrivateData.DTMSRuntime.PreferredPSEdition |
                Should -Be 'Core'
            $manifest.PrivateData.DTMSRuntime.PreferredPowerShellVersion |
                Should -Be '7.0'
            $manifest.PrivateData.DTMSRuntime.MinimumPowerShellVersion |
                Should -Be '5.1'
        }
    }

    It 'loads every supported utility module with one import' {
        $modules = @(Get-DTMSUtilitiesModule)

        $modules | Should -HaveCount 10
        @($modules | Where-Object { -not $_.Loaded }) | Should -HaveCount 0
        $modules.Name | Should -Contain 'DTMS.VMHelper'
        $modules.Name | Should -Contain 'DTMS.OpenSSH'
        $modules.Name | Should -Contain 'DTMS.Runway'
        $modules.Name | Should -Contain 'DTMS.Runway.Federation'
        $modules.Name | Should -Contain 'DTMS.Runway.Dfs'
        $modules.Name | Should -Contain 'DTMS.Configuration'
        $modules.Name | Should -Contain 'DTMS.Forge'
        $modules.Name | Should -Contain 'DTMS.OSInstall'
        $modules.Name | Should -Contain 'DTMS.WinIPAK'
        $modules.Name | Should -Contain 'DTMS.Transfer'
    }

    It 'makes child-module commands available to the caller' {
        Get-Command Copy-VMResource -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.VMHelper'
        Get-Command Start-SSHUtilitiesOperation -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.OpenSSH'
        Get-Command Initialize-SSHTransferHost -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.OpenSSH'
        Get-Command Watch-VMResourceTransfer -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.VMHelper'
        Get-Command Get-VMResourceTransferPerformanceReport -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.VMHelper'
        Get-Command Start-DurableOperation -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.Runway'
        Get-Command Start-ForgePlan -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.Forge'
        Get-Command Start-WindowsServerInstall -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.OSInstall'
        Get-Command Start-WinIPAKOperation -ErrorAction Stop |
            Select-Object -ExpandProperty ModuleName |
            Should -Be 'DTMS.WinIPAK'
    }

    It 'aggregates structured readiness without duplicate capabilities' {
        $readiness = @(Get-DTMSUtilitiesReadiness)
        $keys = @($readiness | ForEach-Object { "$($_.Module):$($_.Capability)" })

        $readiness.Count | Should -BeGreaterThan 5
        @($keys | Sort-Object -Unique) | Should -HaveCount $keys.Count
        $readiness.Module | Should -Contain 'DTMS.VMHelper'
        $readiness.Module | Should -Contain 'DTMS.Runway.Dfs'
        $readiness.Module | Should -Contain 'DTMS.Configuration'
        $readiness.Module | Should -Contain 'DTMS.Runway.Federation'
    }

    It 'supports the shared startup modes' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot 'DTMS.Utilities.psm1'),
            [ref]$tokens,
            [ref]$errors
        )
        $startupParameter = $ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'StartupMode' }
        $validateSet = $startupParameter.Attributes |
            Where-Object { $_.TypeName.Name -eq 'ValidateSet' }

        @($validateSet.PositionalArguments.Value) |
            Should -Be @('Notify', 'Quiet', 'Prompt', 'Initialize')
    }
}
