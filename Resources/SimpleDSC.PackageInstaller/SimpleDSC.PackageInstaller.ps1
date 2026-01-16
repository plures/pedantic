# SimpleDSC PackageInstaller - DSC v3 Script-based Resource
# Handles simplified package management

param(
    [Parameter(Mandatory)]
    [string] $Operation,  # 'get', 'set', or 'test'
    
    [Parameter()]
    [string] $InputJson
)

# Package mapping database
$PackageMap = @{
    'git' = @{
        winget = 'Git.Git'
        chocolatey = 'git'
        apt = 'git'
        yum = 'git'
    }
    'nodejs' = @{
        winget = 'OpenJS.NodeJS'
        chocolatey = 'nodejs'
        apt = 'nodejs'
        yum = 'nodejs'
    }
    'docker' = @{
        winget = 'Docker.DockerDesktop'
        chocolatey = 'docker-desktop'
        apt = 'docker.io'
        yum = 'docker'
    }
    'golang' = @{
        winget = 'GoLang.Go'
        chocolatey = 'golang'
        apt = 'golang-go'
        yum = 'golang'
    }
    'vscode' = @{
        winget = 'Microsoft.VisualStudioCode'
        chocolatey = 'vscode'
        apt = 'code'
        yum = 'code'
    }
    'python' = @{
        winget = 'Python.Python.3.12'
        chocolatey = 'python'
        apt = 'python3'
        yum = 'python3'
    }
}

function Get-InstallMethod {
    param([string] $PreferredMethod = 'auto')
    
    if ($PreferredMethod -ne 'auto') {
        return $PreferredMethod
    }
    
    # Auto-detect based on platform
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            return 'winget'
        }
        elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            return 'chocolatey'
        }
    }
    elseif ($IsLinux) {
        if (Get-Command apt -ErrorAction SilentlyContinue) {
            return 'apt'
        }
        elseif (Get-Command yum -ErrorAction SilentlyContinue) {
            return 'yum'
        }
    }
    
    return 'winget'  # Default fallback
}

function Resolve-PackageName {
    param(
        [string] $PackageName,
        [string] $Method
    )
    
    $packageKey = $PackageName.ToLower()
    if ($PackageMap.ContainsKey($packageKey)) {
        $mapping = $PackageMap[$packageKey]
        if ($mapping.ContainsKey($Method)) {
            return $mapping[$Method]
        }
    }
    
    return $PackageName
}

function Test-PackageInstalled {
    param(
        [string] $PackageName,
        [string] $Method
    )
    
    $resolvedName = Resolve-PackageName -PackageName $PackageName -Method $Method
    
    switch ($Method) {
        'winget' {
            try {
                $result = winget list --id $resolvedName --exact 2>&1 | Out-String
                return $LASTEXITCODE -eq 0 -and $result -like "*$resolvedName*"
            }
            catch {
                return $false
            }
        }
        'chocolatey' {
            try {
                $result = choco list --local-only $resolvedName --exact 2>&1 | Out-String
                return $LASTEXITCODE -eq 0 -and $result -like "*$resolvedName*"
            }
            catch {
                return $false
            }
        }
        'apt' {
            try {
                $result = dpkg -l $resolvedName 2>&1 | Out-String
                return $LASTEXITCODE -eq 0
            }
            catch {
                return $false
            }
        }
        default {
            Write-Warning "Package detection not implemented for method: $Method"
            return $false
        }
    }
}

function Install-Package {
    param(
        [string] $PackageName,
        [string] $Method,
        [bool] $AcceptLicense = $true,
        [string] $Scope = 'machine'
    )
    
    $resolvedName = Resolve-PackageName -PackageName $PackageName -Method $Method
    Write-Verbose "Installing '$PackageName' as '$resolvedName' using $Method"
    
    switch ($Method) {
        'winget' {
            $arguments = @('install', '--id', $resolvedName, '--source', 'winget')
            if ($AcceptLicense) {
                $arguments += @('--accept-package-agreements', '--accept-source-agreements')
            }
            if ($Scope -eq 'machine') {
                $arguments += '--scope', 'machine'
            }
            
            $result = Start-Process winget -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            if ($result.ExitCode -ne 0) {
                throw "Failed to install package '$PackageName' using WinGet. Exit code: $($result.ExitCode)"
            }
        }
        'chocolatey' {
            $arguments = @('install', $resolvedName, '-y')
            
            $result = Start-Process choco -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            if ($result.ExitCode -ne 0) {
                throw "Failed to install package '$PackageName' using Chocolatey. Exit code: $($result.ExitCode)"
            }
        }
        'apt' {
            $result = Start-Process sudo -ArgumentList @('apt', 'install', '-y', $resolvedName) -Wait -PassThru -NoNewWindow
            if ($result.ExitCode -ne 0) {
                throw "Failed to install package '$PackageName' using apt. Exit code: $($result.ExitCode)"
            }
        }
        default {
            throw "Installation method '$Method' is not implemented"
        }
    }
}

# Main script logic
try {
    if ($InputJson) {
        $config = $InputJson | ConvertFrom-Json
    } else {
        # Default configuration for testing
        $config = @{
            name = 'test-packages'
            packages = @('git', 'nodejs')
            method = 'auto'
            ensure = 'Present'
            acceptLicense = $true
            scope = 'machine'
        }
    }
    
    $installMethod = Get-InstallMethod -PreferredMethod $config.method
    
    switch ($Operation.ToLower()) {
        'get' {
            $result = @{
                name = $config.name
                packages = $config.packages
                method = $installMethod
                ensure = $config.ensure
                acceptLicense = $config.acceptLicense
                scope = $config.scope
                installedPackages = @()
            }
            
            foreach ($package in $config.packages) {
                if (Test-PackageInstalled -PackageName $package -Method $installMethod) {
                    $result.installedPackages += $package
                }
            }
            
            $result | ConvertTo-Json -Depth 10
        }
        'test' {
            $allInstalled = $true
            foreach ($package in $config.packages) {
                $isInstalled = Test-PackageInstalled -PackageName $package -Method $installMethod
                
                if ($config.ensure -eq 'Present' -and -not $isInstalled) {
                    $allInstalled = $false
                    break
                }
                elseif ($config.ensure -eq 'Absent' -and $isInstalled) {
                    $allInstalled = $false
                    break
                }
            }
            
            @{ inDesiredState = $allInstalled } | ConvertTo-Json
        }
        'set' {
            foreach ($package in $config.packages) {
                $isInstalled = Test-PackageInstalled -PackageName $package -Method $installMethod
                
                if ($config.ensure -eq 'Present' -and -not $isInstalled) {
                    Write-Output "Installing package: $package"
                    Install-Package -PackageName $package -Method $installMethod -AcceptLicense $config.acceptLicense -Scope $config.scope
                }
                elseif ($config.ensure -eq 'Absent' -and $isInstalled) {
                    Write-Output "Uninstalling package: $package"
                    # Uninstall logic would go here
                }
            }
            
            # Return current state after changes
            & $MyInvocation.MyCommand.Path -Operation 'get' -InputJson $InputJson
        }
        default {
            throw "Unknown operation: $Operation"
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
