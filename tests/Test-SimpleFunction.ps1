# Test simple function with same parameters as Invoke-DscHelper
function Test-SimpleDsc {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, 
      Position = 0,
      HelpMessage = 'Path to the DSC configuration YAML file')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Alias('Path', 'ConfigPath')]
    [string]$DscPath,
        
    [Parameter(Mandatory = $true, 
      Position = 1,
      HelpMessage = 'DSC operation to perform')]
    [ValidateSet('Set', 'Test', 'Validate', 'Export', 
      IgnoreCase = $true,
      HelpMessage = 'Valid operations: Set (apply config), Test (check compliance), Validate (validate config), Export (export current state)')]
    [Alias('Op', 'Action')]
    [string]$Operation,
        
    [Parameter(Mandatory = $false, 
      HelpMessage = 'Path to parameters JSON/YAML file')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ -not $_ -or (Test-Path $_ -PathType Leaf) })]
    [Alias('Params', 'ParamFile')]
    [string]$ParametersPath,
        
    [Parameter(Mandatory = $false, 
      HelpMessage = 'Target computer name for remote execution. If not specified or matches current computer, runs locally.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Computer', 'Target', 'Server')]
    [string]$ComputerName = $env:COMPUTERNAME,
        
    [Parameter(Mandatory = $false, 
      HelpMessage = 'Return only the InDesiredState property')]
    [Alias('ReturnState', 'StateOnly')]
    [switch]$ReturnInDesiredState,
        
    [Parameter(Mandatory = $false, 
      HelpMessage = 'Suppress verbose output')]
    [Alias('Silent')]
    [switch]$Quiet,
        
    [Parameter(Mandatory = $false, 
      HelpMessage = 'Show what would happen without making changes (Set operation only)')]
    [Alias('Preview', 'DryRun')]
    [switch]$WhatIf,
        
    [Parameter(Mandatory = $false, 
      HelpMessage = 'Credential for remote connection (only needed for remote execution)')]
    [Alias('Cred')]
    [PSCredential]$Credential
  )
  
  Write-Host "Test function called with:" -ForegroundColor Green
  Write-Host "DscPath: $DscPath" -ForegroundColor Gray
  Write-Host "Operation: $Operation" -ForegroundColor Gray
  Write-Host "ComputerName: $ComputerName" -ForegroundColor Gray
}

Write-Host "Test-SimpleDsc function loaded. Try typing 'Test-SimpleDsc -' and press TAB" -ForegroundColor Yellow 