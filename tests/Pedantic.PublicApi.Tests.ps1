#requires -Version 7.2

Describe 'Pedantic Public API' {
  BeforeAll {
    # Import Pedantic module directly
    $modulePath = Join-Path $PSScriptRoot '..' 'Pedantic.psm1'
    if (Test-Path $modulePath) { Import-Module $modulePath -Force } else { Import-Module Pedantic -Force -ErrorAction Stop }
  }

  It 'exports expected commands' {
    $expected = 'Invoke-DscHelper','Set-DscConfiguration','Test-DscConfiguration','Validate-DscConfiguration','Export-DscConfiguration','New-SecureRemoteSession'
    foreach ($name in $expected) {
      (Get-Command $name -ErrorAction Stop).Name | Should -Be $name
    }
  }

  Context 'Invoke-DscHelper routing' {
    It 'returns inDesiredState when -ReturnInDesiredState is set' {
      InModuleScope 'Pedantic' {
        Mock -CommandName Test-DscExecutable {}
        Mock -CommandName Test-DscPaths {}
        Mock -CommandName Build-DscArguments { @('config','test','--file','x.yaml','--output-format','json') }
        Mock -CommandName Invoke-DscCommand { @{ ExitCode = 0; Output = '{"inDesiredState":true}' } }
        Mock -CommandName Convert-FromDscJson { param($Output) $Output | ConvertFrom-Json }

        $res = Invoke-DscHelper -DscPath $PSCommandPath -Operation Test -ReturnInDesiredState
        $res | Should -BeTrue
      }
    }
  }
}
