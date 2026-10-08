BeforeAll {
  $script:modulePath = Join-Path $PSScriptRoot 'DTMS.OpenSSH.psd1'
  $script:moduleFile = Join-Path $PSScriptRoot 'DTMS.OpenSSH.psm1'
  $script:originalStartupMode = $env:SSHUTILITIES_STARTUP_MODE
  $env:SSHUTILITIES_STARTUP_MODE = 'Quiet'
  Import-Module $script:modulePath -Force
}

AfterAll {
  $env:SSHUTILITIES_STARTUP_MODE = $script:originalStartupMode
}

Describe 'SSHUtilities startup contract' {
  It 'exports structured readiness without installing dependencies' {
    $command = Get-Command Get-SSHUtilitiesReadiness
    $readiness = @(Get-SSHUtilitiesReadiness)

    $command.ModuleName | Should -Be 'DTMS.OpenSSH'
    $readiness.Count | Should -BeGreaterOrEqual 4
    $readiness.Capability | Should -Contain 'OpenSSHClient'
    $readiness.Capability | Should -Contain 'SecureCopyTransport'
    $readiness.Capability | Should -Contain 'PsExec'
    $readiness.Capability | Should -Contain 'PoshSSH'
    $readiness.Capability | Should -Contain 'DurableExecution'
    $readiness.Capability | Should -Contain 'ScpTransport'
    @($readiness | Where-Object Status -notin @('Ready', 'NotConfigured')) |
      Should -HaveCount 0
  }

  It 'supports all approved startup modes' {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
      $script:moduleFile,
      [ref]$tokens,
      [ref]$errors
    )
    $startupParameter = $ast.ParamBlock.Parameters |
      Where-Object { $_.Name.VariablePath.UserPath -eq 'StartupMode' }
    $validateSet = $startupParameter.Attributes |
      Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
    $validValues = @($validateSet.PositionalArguments.Value)

    $validValues |
      Should -Be @('Notify', 'Quiet', 'Prompt', 'Initialize')
  }

  It 'does not invoke dependency installation unconditionally during import' {
    $text = Get-Content -LiteralPath $script:moduleFile -Raw

    $text | Should -Not -Match 'Initialize-SSHUtilitiesModule\s+-AutoInstallDependencies:\$true'
    $text | Should -Match "effectiveStartupMode -eq 'Initialize'"
    $text | Should -Match "effectiveStartupMode -eq 'Notify'"
  }

  It 'supports import arguments through the module manifest' {
    Remove-Module DTMS.OpenSSH -ErrorAction SilentlyContinue
    $env:SSHUTILITIES_STARTUP_MODE = $null

    {
      Import-Module $script:modulePath -ArgumentList 'Quiet' -Force -ErrorAction Stop
    } | Should -Not -Throw

    (Get-Module DTMS.OpenSSH).Version | Should -Be ([version]'3.0.0')
  }

  It 'offers only noninteractive operations through the durable adapter' {
    $command = Get-Command Start-SSHUtilitiesOperation
    $validateSet = @($command.Parameters.Operation.Attributes |
      Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })

    $validateSet[0].ValidValues |
      Should -Be @('InstallOpenSSHClient', 'InstallOpenSSHServer', 'SetAdminAuthKeys')
    $validateSet[0].ValidValues | Should -Not -Contain 'StartRDProxy'
  }

  It 'exports guarded transfer-host preparation' {
    $command = Get-Command Initialize-SSHTransferHost

    $command.ModuleName | Should -Be 'DTMS.OpenSSH'
    $command.Parameters.Keys | Should -Contain 'WhatIf'
    $command.Parameters.Keys | Should -Contain 'AuthorizedKey'
    $command.Parameters.Keys | Should -Contain 'PrivateKeyContent'
    $command.Parameters.Keys | Should -Contain 'TransferAccount'
    $command.Parameters.Keys | Should -Contain 'OpenSSHServerCabPath'
    $command.Parameters.OpenSSHServerCabPath.Attributes |
      Where-Object { $_ -is [Management.Automation.ParameterAttribute] } |
      Should -Not -BeNullOrEmpty
    $text = Get-Content -LiteralPath $script:moduleFile -Raw
    $text | Should -Match ([regex]::Escape(
      'C:\temp\OpenSSH-Server-Package~31bf3856ad364e35~amd64~~.cab'
    ))
    $text | Should -Match '(?s)Add-WindowsCapability.+-Name \$capabilityName.+-Source'
    $text | Should -Match '-LimitAccess'
  }

  It 'exports named controller and WinRM tunnel transports' {
    (Get-Command New-DTMSControllerSession).ModuleName |
      Should -Be 'DTMS.OpenSSH'
    (Get-Command Start-DTMSWinRMTunnel).ModuleName |
      Should -Be 'DTMS.OpenSSH'
    (Get-Command Start-DTMSWinRMTunnel).Parameters.Keys |
      Should -Contain 'ProfileName'
  }

  It 'announces long-running OpenSSH work before execution' {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
      $script:moduleFile,
      [ref]$tokens,
      [ref]$errors
    )

    foreach ($functionName in @(
      'Install-OpenSSHClient'
      'Install-OpenSSHServer'
      'Install-OpenSSH'
      'Install-ModuleDependencies'
      'Start-SSHUtilitiesOperation'
      'Initialize-SSHTransferHost'
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
