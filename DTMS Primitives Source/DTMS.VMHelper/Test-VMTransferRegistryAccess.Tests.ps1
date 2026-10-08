# Copyright (c) Microsoft Corporation. All rights reserved.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
param()

Describe 'Test-VMTransferRegistryAccess' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Test-VMTransferRegistryAccess.ps1'
    }

    It 'has PowerShell 5.1-compatible syntax' {
        $tokens = $null
        $errors = $null

        [Management.Automation.Language.Parser]::ParseFile(
            $scriptPath,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null

        $errors | Should -BeNullOrEmpty
    }

    It 'documents discovery and writable-only usage' {
        $help = Get-Help $scriptPath

        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description.Text | Should -Not -BeNullOrEmpty
        @($help.Examples.Example.Code) -join [Environment]::NewLine |
            Should -Match 'OnlyWritable'
    }

    It 'uses DFSN discovery and unique removable probes' {
        $text = Get-Content -LiteralPath $scriptPath -Raw

        $text | Should -Match 'Get-DfsnRoot\s+-Domain'
        $text | Should -Match 'Get-DfsnFolder\s+-Path'
        $text | Should -Match '\.vmhelper-write-test-'
        $text | Should -Match 'Remove-Item\s+-LiteralPath\s+\$testDirectory'
        $text | Should -Match 'CanCreateDirectory'
        $text | Should -Match 'CanWriteFile'
        $text | Should -Match 'CanDelete'
        $text | Should -Match 'AccessDenied'
        $text | Should -Match 'Connectivity'
        $text | Should -Match "ParameterSetName = 'Path'"
        $text | Should -Match 'Write-RegistryStatus'
        $text | Should -Match 'Write-RegistryProgress'
        $text | Should -Match 'Testing \$candidateNumber of'
        $text | Should -Match 'if \(\$canCreateDirectory -and -not \$canDelete\)'
        $text | Should -Not -Match 'if \(Test-Path -LiteralPath \$testDirectory\)'
    }
}
