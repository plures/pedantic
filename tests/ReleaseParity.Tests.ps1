#requires -Version 7.2

Describe 'Pedantic release parity' {
  BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '..'
    $installerWorkflow = Get-Content (Join-Path $repoRoot '.github/workflows/installers.yml') -Raw
    $releaseWorkflow = Get-Content (Join-Path $repoRoot '.github/workflows/release.yml') -Raw
    $wix = Get-Content (Join-Path $repoRoot 'installers/windows/pedantic.wxs') -Raw
  }

  It 'skips release generation when an open preparation PR already targets the base branch' {
    $releaseWorkflow | Should -Match 'release_pr_guard'
    $releaseWorkflow | Should -Match 'gh pr list'
    $releaseWorkflow | Should -Match '--base "\$BASE"'
    $releaseWorkflow | Should -Match '--state open'
    $releaseWorkflow | Should -Match "needs\.release_pr_guard\.outputs\.should_release == 'true'"
  }

  It 'builds and packages the Windows-local service with the CLI' {
    $installerWorkflow | Should -Match 'cargo build --release --package pedantic --package pedantic-service'
    $wix | Should -Match 'pedantic-service\.exe'
  }

  It 'synchronizes shipped and workspace-inherited package metadata with the release version' {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('pedantic-release-parity-' + [guid]::NewGuid())
    $fixtureFiles = @{
      'rust/Cargo.toml' = @'
[workspace.package]
version = "0.10.0"
'@
      'rust/Cargo.lock' = @'
version = 4

[[package]]
name = "pedantic-agent"
version = "0.10.0"
'@
      'rust/crates/pedantic-agent/Cargo.toml' = @'
[package]
name = "pedantic-agent"
version.workspace = true
'@
      'Pedantic.psd1' = @'
@{
  ModuleVersion = '0.10.0'
  PrivateData = @{ PSData = @{ Tags = @() } }
}
'@
      'extension/bridge/module/Pedantic.psd1' = @'
@{
  ModuleVersion = '0.10.0'
  PrivateData = @{ PSData = @{ Tags = @() } }
}
'@
      'extension/package-lock.json' = @'
{
  "name": "pedantic-dsc",
  "version": "0.10.0",
  "packages": {
    "": {
      "name": "pedantic-dsc",
      "version": "0.10.0"
    }
  }
}
'@
    }

    try {
      foreach ($relativePath in $fixtureFiles.Keys) {
        $path = Join-Path $fixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        Set-Content -Path $path -Value $fixtureFiles[$relativePath] -NoNewline
      }
      $scriptDirectory = Join-Path $fixtureRoot 'scripts'
      New-Item -ItemType Directory -Path $scriptDirectory -Force | Out-Null
      Copy-Item (Join-Path $repoRoot 'scripts/sync-release-version.mjs') $scriptDirectory

      Push-Location $fixtureRoot
      try {
        & node (Join-Path $scriptDirectory 'sync-release-version.mjs') '0.11.0'
        $LASTEXITCODE | Should -Be 0
      } finally {
        Pop-Location
      }

      foreach ($manifest in @('Pedantic.psd1', 'extension/bridge/module/Pedantic.psd1')) {
        (Get-Content (Join-Path $fixtureRoot $manifest) -Raw) | Should -Match "ModuleVersion = '0\.11\.0'"
      }
      (Get-Content (Join-Path $fixtureRoot 'rust/Cargo.toml') -Raw) | Should -Match 'version = "0\.11\.0"'
      (Get-Content (Join-Path $fixtureRoot 'rust/Cargo.lock') -Raw) | Should -Match 'name = "pedantic-agent"\r?\nversion = "0\.11\.0"'
      $npmLock = Get-Content (Join-Path $fixtureRoot 'extension/package-lock.json') -Raw | ConvertFrom-Json -AsHashtable
      $npmLock.version | Should -Be '0.11.0'
      $npmLock.packages[''].version | Should -Be '0.11.0'
    } finally {
      Remove-Item -Path $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
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
