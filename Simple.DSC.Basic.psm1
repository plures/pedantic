# Simple DSC Converter - Basic Version
# Converts simplified DSL to full DSC configurations

function ConvertFrom-SimpleDsc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SimpleDslPath,
        
        [Parameter()]
        [string] $OutputPath
    )
    
    try {
        # Read the simple DSL file
        $content = Get-Content $SimpleDslPath -Raw
        
        # Extract package list (basic parsing)
        $packages = @()
        if ($content -match 'packages:\s*\n((?:\s*-\s*.+\n?)*)') {
            $packageSection = $matches[1]
            $packages = $packageSection -split '\n' | ForEach-Object {
                if ($_ -match '^\s*-\s*(.+)$') {
                    $matches[1].Trim()
                }
            } | Where-Object { $_ }
        }
        
        # Build DSC configuration
        $dscConfig = @{
            '$schema' = 'https://aka.ms/dsc/schemas/v3/config/document.json'
            metadata = @{
                name = "Generated from Simple DSL: $(Split-Path $SimpleDslPath -Leaf)"
            }
            resources = @()
        }
        
        # Convert each package to a DSC resource
        foreach ($package in $packages) {
            $packageId = switch ($package) {
                'git' { 'Git.Git' }
                'nodejs' { 'OpenJS.NodeJS' }
                'docker' { 'Docker.DockerDesktop' }
                'golang' { 'GoLang.Go' }
                'vscode' { 'Microsoft.VisualStudioCode' }
                default { $package }
            }
            
            $resource = @{
                name = "install_$($package.Replace('.', '_').Replace('-', '_'))"
                type = 'Microsoft.DSC.Transitional/RunCommandOnSet'
                properties = @{
                    executable = 'winget'
                    arguments = @(
                        'install', 
                        '--id', $packageId,
                        '--source', 'winget',
                        '--accept-package-agreements',
                        '--accept-source-agreements'
                    )
                }
            }
            
            $dscConfig.resources += $resource
        }
        
        # Convert to YAML (basic implementation)
        $yamlOutput = ConvertTo-BasicYaml $dscConfig
        
        if ($OutputPath) {
            Set-Content -Path $OutputPath -Value $yamlOutput -Encoding UTF8
            Write-Host "Generated DSC configuration saved to: $OutputPath" -ForegroundColor Green
            return $OutputPath
        } else {
            return $yamlOutput
        }
        
    } catch {
        Write-Error "Failed to convert Simple DSL: $_"
        throw
    }
}

function ConvertTo-BasicYaml {
    param([hashtable] $InputObject)
    
    $result = @()
    
    # Schema
    $result += '$schema: "https://aka.ms/dsc/schemas/v3/config/document.json"'
    
    # Metadata
    $result += "metadata:"
    $result += "  name: `"$($InputObject.metadata.name)`""
    
    # Resources
    $result += "resources:"
    foreach ($resource in $InputObject.resources) {
        $result += "  - name: $($resource.name)"
        $result += "    type: $($resource.type)"
        $result += "    properties:"
        $result += "      executable: $($resource.properties.executable)"
        $result += "      arguments:"
        foreach ($arg in $resource.properties.arguments) {
            $result += "        - '$arg'"
        }
    }
    
    return $result -join "`n"
}

function Test-SimpleDsc {
    param([string] $SimpleDslPath)
    
    Write-Host "Testing Simple DSC conversion..." -ForegroundColor Cyan
    
    # Convert to DSC
    $outputPath = $SimpleDslPath -replace '\.yaml$', '.dsc.yaml'
    ConvertFrom-SimpleDsc -SimpleDslPath $SimpleDslPath -OutputPath $outputPath
    
    # Validate with existing DSC module
    if (Get-Command validate-DscConfiguration -ErrorAction SilentlyContinue) {
        Write-Host "Validating generated DSC configuration..." -ForegroundColor Cyan
        validate-DscConfiguration -DscPath $outputPath
    }
    
    return $outputPath
}

# Export functions
Export-ModuleMember -Function ConvertFrom-SimpleDsc, Test-SimpleDsc
