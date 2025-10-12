# Simple DSC PowerShell Module
# Translates simplified DSL to full DSC configurations

# Module Manifest would be Simple.DSC.psd1
# For now, implementing as a single .psm1 file

using module .\StateSmith.DSC.psm1

class SimpleDscConfig {
    [hashtable] $Preferences
    [hashtable] $PackageMappings
    [string] $TargetOS
    
    SimpleDscConfig([string] $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Yaml
        $this.Preferences = $config.preferences
        $this.PackageMappings = $config.preferences.packages
        $this.TargetOS = $this.DetectOS()
    }
    
    [string] DetectOS() {
        if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'windows' }
        if ($IsLinux) { return 'linux' }
        if ($IsMacOS) { return 'macos' }
        return 'windows' # Default fallback
    }
    
    [array] GetInstallMethods() {
        return $this.Preferences[$this.TargetOS]
    }
    
    [hashtable] ResolvePackage([string] $packageName) {
        if ($this.PackageMappings.ContainsKey($packageName)) {
            return $this.PackageMappings[$packageName]
        }
        # If not found in mappings, assume it's a direct package ID
        return @{ winget = $packageName }
    }
}

function ConvertFrom-SimpleDsc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SimpleDslPath,
        
        [Parameter(Mandatory)]
        [string] $ConfigPath,
        
        [Parameter()]
        [string] $OutputPath
    )
    
    try {
        # Load configuration
        $config = [SimpleDscConfig]::new($ConfigPath)
        
        # Parse simple DSL
    $simpleDsl = Get-Content $SimpleDslPath | ConvertFrom-InternalSimpleYaml
        
        # Build DSC configuration
        $dscConfig = @{
            '$schema' = 'https://aka.ms/dsc/schemas/v3/config/document.json'
            metadata = @{
                name = "Generated from Simple DSL: $(Split-Path $SimpleDslPath -Leaf)"
            }
            resources = @()
        }
        
        if ($simpleDsl.'dsc.install' -and $simpleDsl.'dsc.install'.packages) {
            $packages = $simpleDsl.'dsc.install'.packages
            $installMethods = $config.GetInstallMethods()
            
            foreach ($package in $packages) {
                $resource = $null
                
                if ($package -is [string]) {
                    # Simple package name
                    $resource = ConvertTo-DscResource -PackageName $package -Config $config -InstallMethods $installMethods
                } elseif ($package -is [hashtable]) {
                    # Package with overrides
                    if ($package.ContainsKey('executable') -and $package.ContainsKey('path')) {
                        # Custom executable
                        $resource = @{
                            name = $package.name
                                # Standardized resource type name format
                                type = 'Microsoft/DSC/Transitional/RunCommandOnSet'
                            properties = @{
                                executable = $package.executable
                                arguments = @($package.path) + ($package.args -split ' ' | Where-Object { $_ })
                            }
                        }
                    } elseif ($package.ContainsKey('method')) {
                        # Method override
                        $resource = ConvertTo-DscResource -PackageName $package.name -Config $config -InstallMethods @($package.method)
                    } else {
                        # Standard package with name property
                        $resource = ConvertTo-DscResource -PackageName $package.name -Config $config -InstallMethods $installMethods
                    }
                }
                
                if ($resource) {
                    $dscConfig.resources += $resource
                }
            }
        }
        
        # Output the generated DSC configuration
    $output = $dscConfig | ConvertTo-InternalSimpleYaml
        
        if ($OutputPath) {
            Set-Content -Path $OutputPath -Value $output
            Write-Host "Generated DSC configuration saved to: $OutputPath"
        } else {
            return $output
        }
        
    } catch {
        Write-Error "Failed to convert Simple DSL: $_"
        throw
    }
}

function ConvertTo-DscResource {
    param(
        [string] $PackageName,
        [SimpleDscConfig] $Config,
        [array] $InstallMethods
    )
    
    $packageInfo = $Config.ResolvePackage($PackageName)
    
    # Try each install method in priority order
    foreach ($method in $InstallMethods) {
        switch ($method) {
            'winget' {
                if ($packageInfo.winget) {
                    return @{
                        name = "install_$($PackageName.Replace('.', '_'))"
                            type = 'Microsoft/DSC/Transitional/RunCommandOnSet'
                        properties = @{
                            executable = 'winget'
                            arguments = @(
                                'install', 
                                '--id', $packageInfo.winget,
                                '--source', ($Config.Preferences.winget.source ?? 'winget'),
                                '--accept-package-agreements',
                                '--accept-source-agreements'
                            )
                        }
                    }
                }
            }
            'chocolatey' {
                if ($packageInfo.chocolatey) {
                    return @{
                        name = "install_$($PackageName.Replace('.', '_'))"
                            type = 'Microsoft/DSC/Transitional/RunCommandOnSet'
                        properties = @{
                            executable = 'choco'
                            arguments = @('install', $packageInfo.chocolatey, '-y')
                        }
                    }
                }
            }
            'msi' {
                if ($packageInfo.msi) {
                    return @{
                        name = "install_$($PackageName.Replace('.', '_'))"
                            type = 'Microsoft/DSC/Transitional/RunCommandOnSet'
                        properties = @{
                            executable = 'msiexec'
                            arguments = @('/i', $packageInfo.msi, '/quiet', '/norestart')
                        }
                    }
                }
            }
        }
    }
    
    # Fallback: use package name as direct WinGet ID
    return @{
        name = "install_$($PackageName.Replace('.', '_'))"
            type = 'Microsoft/DSC/Transitional/RunCommandOnSet'
        properties = @{
            executable = 'winget'
            arguments = @(
                'install', 
                '--id', $PackageName,
                '--accept-package-agreements',
                '--accept-source-agreements'
            )
        }
    }
}

function ConvertFrom-InternalSimpleYaml {
    param([Parameter(ValueFromPipeline)] [string] $YamlContent)
    
    # Simple YAML parser - in production, use a proper YAML library
    # This is a basic implementation for the demo
    $lines = $YamlContent -split "`n"
    $result = @{}
    $currentSection = $null
    $currentArray = $null
    
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line -match '^#' -or [string]::IsNullOrEmpty($line)) { continue }
        
        if ($line -match '^(\w+(?:\\\.\w+)*):$') {
            $currentSection = $matches[1]
            if ($currentSection -eq 'packages') {
                $currentArray = @()
                $result[$currentSection] = $currentArray
            } else {
                $result[$currentSection] = @{}
            }
        } elseif ($line -match '^\s*-\s*(.+)$' -and $currentArray) {
            $currentArray += $matches[1].Trim()
        } elseif ($line -match '^\s*(\w+):\s*(.+)$' -and $currentSection) {
            $result[$currentSection][$matches[1]] = $matches[2].Trim()
        }
    }
    
    return $result
}

function ConvertTo-InternalSimpleYaml {
    param([Parameter(ValueFromPipeline)] [hashtable] $InputObject)
    
    # Simple YAML serializer - in production, use a proper YAML library
    function ConvertTo-YamlRecursive($obj, $indent = 0) {
        $spaces = '  ' * $indent
        $result = @()
        
        if ($obj -is [hashtable] -or $obj -is [PSCustomObject]) {
            foreach ($key in $obj.Keys) {
                $value = $obj[$key]
                if ($value -is [hashtable] -or $value -is [PSCustomObject]) {
                    $result += "$spaces$key:"
                    $result += ConvertTo-YamlRecursive $value ($indent + 1)
                } elseif ($value -is [array]) {
                    $result += "$spaces$key:"
                    foreach ($item in $value) {
                        if ($item -is [hashtable] -or $item -is [PSCustomObject]) {
                            $result += "$spaces- "
                            $itemYaml = ConvertTo-YamlRecursive $item ($indent + 1)
                            $result += $itemYaml -replace "^$('  ' * ($indent + 1))", "$spaces  "
                        } else {
                            $result += "$spaces- $item"
                        }
                    }
                } else {
                    $result += "$spaces$key" + ": $value"
                }
            }
        }
        
        return $result
    }
    
    return (ConvertTo-YamlRecursive $InputObject) -join "`n"
}

# Export functions
    Export-ModuleMember -Function ConvertFrom-SimpleDsc
