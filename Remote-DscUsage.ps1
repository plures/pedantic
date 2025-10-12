# Remote DSC Usage Guide with Autocomplete
<#
.SYNOPSIS
    Demonstrates different ways to use the StateSmith.DSC module on remote machines with autocomplete.
.DESCRIPTION
    This script shows various approaches for using the DSC module on remote computers
    while maintaining full parameter autocomplete support.
#>

Write-Host "=== Remote DSC Usage with Autocomplete ===" -ForegroundColor Green
Write-Host ""

Write-Host "## Method 1: Copy Module to Remote Machine (Recommended)" -ForegroundColor Yellow
Write-Host "This approach copies the module to the remote machine and enables full autocomplete." -ForegroundColor Gray
Write-Host ""

Write-Host "Step 1: Copy the module to the remote machine" -ForegroundColor Cyan
Write-Host "Copy-Item -Path 'C:\path\to\StateSmith.DSC.psm1' -Destination '\\SERVER01\C$\Temp\StateSmith.DSC.psm1'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 2: Connect to the remote machine" -ForegroundColor Cyan
Write-Host "Enter-PSSession -ComputerName 'SERVER01'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 3: Import the module on the remote machine" -ForegroundColor Cyan
Write-Host "Import-Module 'C:\Temp\StateSmith.DSC.psm1'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 4: Use with full autocomplete!" -ForegroundColor Cyan
Write-Host "Test-DscCompliance -DscPath 'C:\Configs\WebServer.yaml'  # Press TAB for autocomplete" -ForegroundColor Gray
Write-Host "Set-DscConfiguration -DscPath 'C:\Configs\Cluster.yaml' -WhatIf  # Press TAB for autocomplete" -ForegroundColor Gray
Write-Host ""

Write-Host "## Method 2: Use the Automated Script" -ForegroundColor Yellow
Write-Host "Use the Invoke-RemoteDscTest.ps1 script for automated remote execution." -ForegroundColor Gray
Write-Host ""

Write-Host ".\Invoke-RemoteDscTest.ps1 -ComputerName 'SERVER01' -DscPath 'C:\Configs\WebServer.yaml' -Operation 'Test'" -ForegroundColor Gray
Write-Host ""

Write-Host "## Method 3: Install Module on Remote Machine" -ForegroundColor Yellow
Write-Host "Install the module permanently on the remote machine for persistent autocomplete." -ForegroundColor Gray
Write-Host ""

Write-Host "Step 1: Create module directory on remote machine" -ForegroundColor Cyan
Write-Host "New-Item -Path '\\SERVER01\C$\Program Files\WindowsPowerShell\Modules\StateSmith.DSC' -ItemType Directory -Force" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 2: Copy module files" -ForegroundColor Cyan
Write-Host "Copy-Item -Path 'C:\path\to\StateSmith.DSC.psm1' -Destination '\\SERVER01\C$\Program Files\WindowsPowerShell\Modules\StateSmith.DSC\StateSmith.DSC.psm1'" -ForegroundColor Gray
Write-Host "Copy-Item -Path 'C:\path\to\StateSmith.DSC.psd1' -Destination '\\SERVER01\C$\Program Files\WindowsPowerShell\Modules\StateSmith.DSC\StateSmith.DSC.psd1'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 3: Connect and use (module auto-loads)" -ForegroundColor Cyan
Write-Host "Enter-PSSession -ComputerName 'SERVER01'" -ForegroundColor Gray
Write-Host "Test-DscCompliance -DscPath 'C:\Configs\WebServer.yaml'  # Full autocomplete!" -ForegroundColor Gray
Write-Host ""

Write-Host "## Method 4: Use Invoke-Command with Module Import" -ForegroundColor Yellow
Write-Host "Execute commands remotely while importing the module for autocomplete." -ForegroundColor Gray
Write-Host ""

Write-Host '$remoteScript = {' -ForegroundColor Gray
Write-Host '    # Import module for autocomplete support' -ForegroundColor Gray
Write-Host '    Import-Module "C:\Temp\StateSmith.DSC.psm1"' -ForegroundColor Gray
Write-Host '    ' -ForegroundColor Gray
Write-Host '    # Now you can use autocomplete in your script' -ForegroundColor Gray
Write-Host '    Test-DscCompliance -DscPath "C:\Configs\WebServer.yaml"' -ForegroundColor Gray
Write-Host '}' -ForegroundColor Gray
Write-Host 'Invoke-Command -ComputerName "SERVER01" -ScriptBlock $remoteScript' -ForegroundColor Gray
Write-Host ""

Write-Host "## Method 5: Interactive Remote Session with Autocomplete" -ForegroundColor Yellow
Write-Host "For interactive work on remote machines with full autocomplete." -ForegroundColor Gray
Write-Host ""

Write-Host "Step 1: Start an interactive session" -ForegroundColor Cyan
Write-Host "Enter-PSSession -ComputerName 'SERVER01'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 2: Import the module" -ForegroundColor Cyan
Write-Host "Import-Module 'C:\Temp\StateSmith.DSC.psm1'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 3: Use with full autocomplete interactively" -ForegroundColor Cyan
Write-Host "Test-DscCompliance -<TAB>  # Cycles through parameters" -ForegroundColor Gray
Write-Host "Set-DscConfiguration -DscPath 'C:\Configs\Cluster.yaml' -<TAB>  # Shows available parameters" -ForegroundColor Gray
Write-Host ""

Write-Host "## Quick Test Commands" -ForegroundColor Yellow
Write-Host "Try these commands to test autocomplete on a remote machine:" -ForegroundColor Gray
Write-Host ""

Write-Host "# Test compliance" -ForegroundColor Cyan
Write-Host "Test-DscCompliance -DscPath 'C:\Configs\WebServer.yaml'" -ForegroundColor Gray
Write-Host ""

Write-Host "# Apply configuration with WhatIf" -ForegroundColor Cyan
Write-Host "Set-DscConfiguration -DscPath 'C:\Configs\Cluster.yaml' -WhatIf" -ForegroundColor Gray
Write-Host ""

Write-Host "# Validate configuration file" -ForegroundColor Cyan
Write-Host "Test-DscConfiguration -DscPath 'C:\Configs\Baseline.yaml'" -ForegroundColor Gray
Write-Host ""

Write-Host "# Full control with main function" -ForegroundColor Cyan
Write-Host "Invoke-DscHelper -DscPath 'C:\Configs\WebServer.yaml' -Operation 'Test' -ReturnInDesiredState" -ForegroundColor Gray
Write-Host ""

Write-Host "## Troubleshooting" -ForegroundColor Yellow
Write-Host ""

Write-Host "If autocomplete doesn't work:" -ForegroundColor Cyan
Write-Host "1. Verify the module is imported: Get-Module StateSmith.DSC" -ForegroundColor Gray
Write-Host "2. Check module path: Get-Module StateSmith.DSC | Select-Object Path" -ForegroundColor Gray
Write-Host "3. Re-import if needed: Import-Module 'C:\Temp\StateSmith.DSC.psm1' -Force" -ForegroundColor Gray
Write-Host ""

Write-Host "## Benefits of Using the Module on Remote Machines" -ForegroundColor Yellow
Write-Host "✓ Full parameter autocomplete support" -ForegroundColor Green
Write-Host "✓ IntelliSense and help system" -ForegroundColor Green
Write-Host "✓ Consistent interface across local and remote" -ForegroundColor Green
Write-Host "✓ Better error handling and validation" -ForegroundColor Green
Write-Host "✓ Simplified function names for common operations" -ForegroundColor Green
Write-Host ""

Write-Host "=== End of Remote Usage Guide ===" -ForegroundColor Green 