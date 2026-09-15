#requires -Version 7.2

Describe 'Pedantic release parity' {
  BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '..'
    $installerWorkflow = Get-Content (Join-Path $repoRoot '.github/workflows/installers.yml') -Raw
    $wix = Get-Content (Join-Path $repoRoot 'installers/windows/pedantic.wxs') -Raw
    $versionSync = Get-Content (Join-Path $repoRoot 'scripts/sync-release-version.mjs') -Raw
  }

  It 'builds and packages the Windows-local service with the CLI' {
    $installerWorkflow | Should -Match 'cargo build --release --package pedantic --package pedantic-service'
    $wix | Should -Match 'pedantic-service\.exe'
  }

  It 'synchronizes the shipped PowerShell manifest with the release version' {
    $versionSync | Should -Match "Pedantic\.psd1"
    $versionSync | Should -Match 'ModuleVersion'
  }

  It 'exports every cache command declared by the compatibility manifest' {
    Import-Module (Join-Path $repoRoot 'Pedantic.psd1') -Force
    $expected = @(
      'Get-DscInstallerCache', 'Update-DscInstallerCache', 'Remove-DscInstallerCache',
      'Get-DscResourceCache', 'Update-DscResourceCache', 'Remove-DscResourceCache'
    )
    foreach ($command in $expected) {
      (Get-Command $command -Module Pedantic -ErrorAction Stop).Name | Should -Be $command
    }
  }

  It 'keeps compatibility cache lookup offline by default' {
    InModuleScope Pedantic {
      Mock Update-DscInstallerCacheInternal {}
      Mock Update-DscResourceCacheInternal {}

      Get-DscInstallerPath -Quiet | Out-Null
      Get-DscResourcePath -ResourceType 'Microsoft.Windows/File' -Quiet | Out-Null

      Should -Invoke Update-DscInstallerCacheInternal -Exactly -Times 0
      Should -Invoke Update-DscResourceCacheInternal -Exactly -Times 0
    }
  }

  It 'honors WhatIf before refreshing a compatibility cache' {
    InModuleScope Pedantic {
      Mock Update-DscInstallerCacheInternal {}
      Mock Update-DscResourceCacheInternal {}

      Update-DscInstallerCache -WhatIf -Quiet | Out-Null
      Update-DscResourceCache -WhatIf -Quiet | Out-Null

      Should -Invoke Update-DscInstallerCacheInternal -Exactly -Times 0
      Should -Invoke Update-DscResourceCacheInternal -Exactly -Times 0
    }
  }
}
