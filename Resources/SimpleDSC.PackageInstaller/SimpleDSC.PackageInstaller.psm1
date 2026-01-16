# SimpleDSC PackageInstaller DSC v3 Resource Implementation
# Handles simplified package management with JSON schema

class SimpleDSC.PackageInstaller {
    [string] $Name
    [string[]] $Packages  
    [string] $Method = 'auto'
    [string] $Ensure = 'Present'
    [bool] $AcceptLicense = $true
    [string] $Scope = 'machine'
    
    # Package mapping database
    hidden [hashtable] $PackageMap = @{
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
        'powershell' = @{
            winget = 'Microsoft.PowerShell'
            chocolatey = 'powershell-core'
            apt = 'powershell'
            yum = 'powershell'
        }
    }
    
    [SimpleDSC.PackageInstaller] Get() {
        $current = [SimpleDSC.PackageInstaller]::new()
        $current.Name = $this.Name
        $current.Packages = $this.Packages
        $current.Method = $this.Method
        $current.Ensure = $this.Ensure
        $current.AcceptLicense = $this.AcceptLicense
        $current.Scope = $this.Scope
        
        # Check current state of packages
        $installedPackages = @()
        foreach ($package in $this.Packages) {
            if ($this.IsPackageInstalled($package)) {
                $installedPackages += $package
            }
        }
        
        Write-Verbose "Found $($installedPackages.Count) of $($this.Packages.Count) packages installed"
        return $current
    }
    
    [bool] Test() {
        Write-Verbose "Testing package installation state for: $($this.Packages -join ', ')"
        
        foreach ($package in $this.Packages) {
            $isInstalled = $this.IsPackageInstalled($package)
            
            if ($this.Ensure -eq 'Present' -and -not $isInstalled) {
                Write-Verbose "Package '$package' is not installed but should be Present"
                return $false
            }
            elseif ($this.Ensure -eq 'Absent' -and $isInstalled) {
                Write-Verbose "Package '$package' is installed but should be Absent"
                return $false
            }
        }
        
        Write-Verbose "All packages are in the desired state"
        return $true
    }
    
    [void] Set() {
        Write-Verbose "Configuring packages: $($this.Packages -join ', ')"
        
        $installMethod = $this.DetermineInstallMethod()
        Write-Verbose "Using install method: $installMethod"
        
        foreach ($package in $this.Packages) {
            $isInstalled = $this.IsPackageInstalled($package)
            
            if ($this.Ensure -eq [Ensure]::Present -and -not $isInstalled) {
                Write-Verbose "Installing package: $package"
                $this.InstallPackage($package, $installMethod)
            }
            elseif ($this.Ensure -eq [Ensure]::Absent -and $isInstalled) {
                Write-Verbose "Uninstalling package: $package"
                $this.UninstallPackage($package, $installMethod)
            }
            else {
                Write-Verbose "Package '$package' is already in the desired state"
            }
        }
    }
    
    [InstallMethod] DetermineInstallMethod() {
        if ($this.Method -ne [InstallMethod]::auto) {
            return $this.Method
        }
        
        # Auto-detect based on platform
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                return [InstallMethod]::winget
            }
            elseif (Get-Command choco -ErrorAction SilentlyContinue) {
                return [InstallMethod]::chocolatey
            }
        }
        elseif ($IsLinux) {
            if (Get-Command apt -ErrorAction SilentlyContinue) {
                return [InstallMethod]::apt
            }
            elseif (Get-Command yum -ErrorAction SilentlyContinue) {
                return [InstallMethod]::yum
            }
        }
        
        # Fallback to winget on Windows
        return [InstallMethod]::winget
    }
    
    [string] ResolvePackageName([string] $packageName, [InstallMethod] $method) {
        if ($this.PackageMap.ContainsKey($packageName.ToLower())) {
            $mapping = $this.PackageMap[$packageName.ToLower()]
            $methodKey = $method.ToString()
            
            if ($mapping.ContainsKey($methodKey)) {
                return $mapping[$methodKey]
            }
        }
        
        # If no mapping found, use the package name as-is
        return $packageName
    }
    
    [bool] IsPackageInstalled([string] $packageName) {
        $method = $this.DetermineInstallMethod()
        $resolvedName = $this.ResolvePackageName($packageName, $method)
        
        switch ($method) {
            ([InstallMethod]::winget) {
                try {
                    $result = winget list --id $resolvedName --exact 2>&1 | Out-String
                    return $LASTEXITCODE -eq 0 -and $result -like "*$resolvedName*"
                }
                catch {
                    return $false
                }
            }
            ([InstallMethod]::chocolatey) {
                try {
                    $result = choco list --local-only $resolvedName --exact 2>&1 | Out-String
                    return $LASTEXITCODE -eq 0 -and $result -like "*$resolvedName*"
                }
                catch {
                    return $false
                }
            }
            ([InstallMethod]::apt) {
                try {
                    $result = dpkg -l $resolvedName 2>&1 | Out-String
                    return $LASTEXITCODE -eq 0
                }
                catch {
                    return $false
                }
            }
            default {
                Write-Warning "Package detection not implemented for method: $method"
                return $false
            }
        }
    }
    
    [void] InstallPackage([string] $packageName, [InstallMethod] $method) {
        $resolvedName = $this.ResolvePackageName($packageName, $method)
        Write-Verbose "Installing '$packageName' as '$resolvedName' using $method"
        
        switch ($method) {
            ([InstallMethod]::winget) {
                $args = @('install', '--id', $resolvedName, '--source', 'winget')
                if ($this.AcceptLicense) {
                    $args += @('--accept-package-agreements', '--accept-source-agreements')
                }
                if ($this.Scope -eq 'machine') {
                    $args += '--scope', 'machine'
                }
                
                $result = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    throw "Failed to install package '$packageName' using WinGet. Exit code: $($result.ExitCode)"
                }
            }
            ([InstallMethod]::chocolatey) {
                $args = @('install', $resolvedName, '-y')
                
                $result = Start-Process choco -ArgumentList $args -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    throw "Failed to install package '$packageName' using Chocolatey. Exit code: $($result.ExitCode)"
                }
            }
            ([InstallMethod]::apt) {
                $result = Start-Process sudo -ArgumentList @('apt', 'install', '-y', $resolvedName) -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    throw "Failed to install package '$packageName' using apt. Exit code: $($result.ExitCode)"
                }
            }
            default {
                throw "Installation method '$method' is not implemented"
            }
        }
        
        Write-Verbose "Successfully installed package: $packageName"
    }
    
    [void] UninstallPackage([string] $packageName, [InstallMethod] $method) {
        $resolvedName = $this.ResolvePackageName($packageName, $method)
        Write-Verbose "Uninstalling '$packageName' as '$resolvedName' using $method"
        
        switch ($method) {
            ([InstallMethod]::winget) {
                $args = @('uninstall', '--id', $resolvedName)
                
                $result = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    throw "Failed to uninstall package '$packageName' using WinGet. Exit code: $($result.ExitCode)"
                }
            }
            ([InstallMethod]::chocolatey) {
                $args = @('uninstall', $resolvedName, '-y')
                
                $result = Start-Process choco -ArgumentList $args -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    throw "Failed to uninstall package '$packageName' using Chocolatey. Exit code: $($result.ExitCode)"
                }
            }
            ([InstallMethod]::apt) {
                $result = Start-Process sudo -ArgumentList @('apt', 'remove', '-y', $resolvedName) -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    throw "Failed to uninstall package '$packageName' using apt. Exit code: $($result.ExitCode)"
                }
            }
            default {
                throw "Uninstallation method '$method' is not implemented"
            }
        }
        
        Write-Verbose "Successfully uninstalled package: $packageName"
    }
}
