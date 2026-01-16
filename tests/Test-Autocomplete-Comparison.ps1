# Test script to compare autocomplete behavior
Write-Host "=== Testing Autocomplete Comparison ===" -ForegroundColor Green
Write-Host ""

# Test 1: Load the simple test function
Write-Host "Test 1: Loading simple test function..." -ForegroundColor Yellow
. .\Test-SimpleFunction.ps1
Write-Host "✓ Test-SimpleDsc function loaded" -ForegroundColor Green

# Test 2: Load the simple module
Write-Host ""
Write-Host "Test 2: Loading simple module..." -ForegroundColor Yellow
Import-Module ".\Simple.DSC.psm1" -Force
Write-Host "✓ Simple.DSC module loaded" -ForegroundColor Green

# Test 3: Load the complex module
Write-Host ""
Write-Host "Test 3: Loading complex module..." -ForegroundColor Yellow
Import-Module ".\Pedantic.psm1" -Force
Write-Host "✓ Pedantic module loaded" -ForegroundColor Green

# Check all functions
Write-Host ""
Write-Host "=== Function Availability Check ===" -ForegroundColor Cyan
$functions = @(
    'Test-SimpleDsc',
    'Invoke-DscHelperSimple', 
    'Invoke-DscHelper',
    'Test-DscCompliance',
    'Set-DscConfiguration',
    'Test-DscConfiguration'
)

foreach ($function in $functions) {
    $cmd = Get-Command $function -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "✓ $function is available" -ForegroundColor Green
        $paramCount = $cmd.Parameters.Count
        Write-Host "  Parameters: $paramCount" -ForegroundColor Gray
    } else {
        Write-Host "✗ $function not found" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== AUTECOMPLETE TEST INSTRUCTIONS ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Now test these commands in your PowerShell session:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Test-SimpleDsc -" -ForegroundColor Gray
Write-Host "2. Invoke-DscHelperSimple -" -ForegroundColor Gray
Write-Host "3. Invoke-DscHelper -" -ForegroundColor Gray
Write-Host "4. Test-DscCompliance -" -ForegroundColor Gray
Write-Host "5. Set-DscConfiguration -" -ForegroundColor Gray
Write-Host "6. Test-DscConfiguration -" -ForegroundColor Gray
Write-Host ""
Write-Host "Which ones show parameter autocomplete?" -ForegroundColor Yellow
Write-Host "This will help us identify the root cause!" -ForegroundColor Yellow 