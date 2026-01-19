# Pedantic DSC Helper Module
# Provides user-friendly DSC v3 operations with parameter autocomplete support
# Automatically handles remote execution without manual setup on remote machines
# PowerShell 7 compatible version

# Module configuration
$script:ModuleConfig = @{
    InstallerCachePath  = Join-Path $PSScriptRoot "Installers"
    InstallerCacheFile  = Join-Path $PSScriptRoot "Installers\installer-cache.json"
    ResourceCachePath   = Join-Path $PSScriptRoot "Resources"
    ResourceCacheFile   = Join-Path $PSScriptRoot "Resources\resource-cache.json"
    UpdateCheckInterval = 1  # Days - check daily for updates
    LastUpdateCheckFile = Join-Path $PSScriptRoot "Installers\last-update-check.txt"
    MaxCachedVersions   = 3  # Maximum number of DSC versions to keep cached
    MaxCachedResources  = 50 # Maximum number of resource versions to keep cached
}

# Ensure $PSScriptRoot is set
if (-not $PSScriptRoot) {
    throw "PSScriptRoot is not defined. Please import this script as a module or run it in a context where PSScriptRoot is set."
}

# Resource mapping for classic DSC resources to PowerShell Gallery modules
$script:ResourceMapping = @{
    # Windows resources
    "Microsoft.Windows/Registry"                                = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Registry"
        GalleryName  = "PSDscResources"
        Description  = "Windows Registry configuration resource"
    }
    "Microsoft.Windows/File"                                    = @{
        ModuleName   = "PSDscResources"
        ResourceName = "File"
        GalleryName  = "PSDscResources"
        Description  = "Windows File system resource"
    }
    "Microsoft.Windows/Service"                                 = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Service"
        GalleryName  = "PSDscResources"
        Description  = "Windows Service management resource"
    }
    "Microsoft.Windows/User"                                    = @{
        ModuleName   = "PSDscResources"
        ResourceName = "User"
        GalleryName  = "PSDscResources"
        Description  = "Windows User management resource"
    }
    "Microsoft.Windows/Group"                                   = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Group"
        GalleryName  = "PSDscResources"
        Description  = "Windows Group management resource"
    }
    "Microsoft.Windows/WindowsFeature"                          = @{
        ModuleName   = "PSDscResources"
        ResourceName = "WindowsFeature"
        GalleryName  = "PSDscResources"
        Description  = "Windows Feature installation resource"
    }
    "Microsoft.Windows/WindowsOptionalFeature"                  = @{
        ModuleName   = "PSDscResources"
        ResourceName = "WindowsOptionalFeature"
        GalleryName  = "PSDscResources"
        Description  = "Windows Optional Feature resource"
    }
    "Microsoft.Windows/Process"                                 = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Process"
        GalleryName  = "PSDscResources"
        Description  = "Windows Process management resource"
    }
    "Microsoft.Windows/Log"                                     = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Log"
        GalleryName  = "PSDscResources"
        Description  = "Windows Log resource"
    }
    "Microsoft.Windows/Environment"                             = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Environment"
        GalleryName  = "PSDscResources"
        Description  = "Windows Environment variable resource"
    }
    "Microsoft.Windows/WMI"                                     = @{
        ModuleName   = "xWMI"
        ResourceName = "xWMI"
        GalleryName  = "xWMI"
        Description  = "Windows WMI configuration resource"
    }
    "Microsoft.Windows/WindowsPowerShell"                       = @{
        ModuleName   = "xPowerShellExecutionPolicy"
        ResourceName = "xPowerShellExecutionPolicy"
        GalleryName  = "xPowerShellExecutionPolicy"
        Description  = "Windows PowerShell execution policy resource"
    }
    "Microsoft.Windows/RebootPending"                           = @{
        ModuleName   = "xPendingReboot"
        ResourceName = "xPendingReboot"
        GalleryName  = "xPendingReboot"
        Description  = "Windows Reboot pending detection resource"
    }
  
    # Networking resources
    "Microsoft.Windows/NetAdapterBinding"                       = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterBinding"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter binding resource"
    }
    "Microsoft.Windows/DnsServerAddress"                        = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "DnsServerAddress"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows DNS server address resource"
    }
    "Microsoft.Windows/NetAdapterName"                          = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterName"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter name resource"
    }
    "Microsoft.Windows/NetAdapterLso"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterLso"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter LSO resource"
    }
    "Microsoft.Windows/NetAdapterRss"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterRss"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter RSS resource"
    }
    "Microsoft.Windows/NetAdapterAdvancedProperty"              = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterAdvancedProperty"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter advanced property resource"
    }
    "Microsoft.Windows/NetAdapterRdma"                          = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterRdma"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter RDMA resource"
    }
    "Microsoft.Windows/NetAdapterEncapsulatedPacketTaskOffload" = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterEncapsulatedPacketTaskOffload"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter encapsulated packet task offload resource"
    }
    "Microsoft.Windows/NetAdapterHardwareChecksumOffload"       = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterHardwareChecksumOffload"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter hardware checksum offload resource"
    }
    "Microsoft.Windows/NetAdapterIPsecOffload"                  = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterIPsecOffload"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter IPsec offload resource"
    }
    "Microsoft.Windows/NetAdapterPowerManagement"               = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterPowerManagement"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter power management resource"
    }
    "Microsoft.Windows/NetAdapterQos"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterQos"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter QoS resource"
    }
    "Microsoft.Windows/NetAdapterRsc"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterRsc"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter RSC resource"
    }
    "Microsoft.Windows/NetAdapterSriov"                         = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterSriov"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter SR-IOV resource"
    }
    "Microsoft.Windows/NetAdapterVmq"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetAdapterVmq"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network adapter VMQ resource"
    }
    "Microsoft.Windows/NetBios"                                 = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetBios"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows NetBIOS configuration resource"
    }
    "Microsoft.Windows/NetConnectionProfile"                    = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetConnectionProfile"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network connection profile resource"
    }
    "Microsoft.Windows/NetIPInterface"                          = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetIPInterface"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network IP interface resource"
    }
    "Microsoft.Windows/NetOffloadGlobalSetting"                 = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetOffloadGlobalSetting"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network offload global setting resource"
    }
    "Microsoft.Windows/NetRoute"                                = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetRoute"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network route resource"
    }
    "Microsoft.Windows/NetTCPSetting"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "NetTCPSetting"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Network TCP setting resource"
    }
    "Microsoft.Windows/ProxySettings"                           = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "ProxySettings"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Proxy settings resource"
    }
    "Microsoft.Windows/WaitForNetAdapter"                       = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "WaitForNetAdapter"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Wait for network adapter resource"
    }
    "Microsoft.Windows/WaitForNetworkTeam"                      = @{
        ModuleName   = "NetworkingDsc"
        ResourceName = "WaitForNetworkTeam"
        GalleryName  = "NetworkingDsc"
        Description  = "Windows Wait for network team resource"
    }
  
    # Computer Management resources
    "Microsoft.Windows/Computer"                                = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "Computer"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Computer management resource"
    }
    "Microsoft.Windows/TimeZone"                                = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "TimeZone"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Time zone configuration resource"
    }
    "Microsoft.Windows/PowerPlan"                               = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "PowerPlan"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Power plan configuration resource"
    }
    "Microsoft.Windows/OfflineDomainJoin"                       = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "OfflineDomainJoin"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Offline domain join resource"
    }
    "Microsoft.Windows/WindowsEventLog"                         = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "WindowsEventLog"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Event log configuration resource"
    }
    "Microsoft.Windows/VirtualMemory"                           = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "VirtualMemory"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Virtual memory configuration resource"
    }
    "Microsoft.Windows/SystemLocale"                            = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "SystemLocale"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows System locale configuration resource"
    }
    "Microsoft.Windows/UserAccountControl"                      = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "UserAccountControl"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows User account control configuration resource"
    }
    "Microsoft.Windows/IEEnhancedSecurityConfiguration"         = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "IEEnhancedSecurityConfiguration"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows IE enhanced security configuration resource"
    }
    "Microsoft.Windows/WindowsCapability"                       = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "WindowsCapability"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Capability installation resource"
    }
    "Microsoft.Windows/WindowsPackageCab"                       = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "WindowsPackageCab"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Package CAB installation resource"
    }
    "Microsoft.Windows/WindowsUpdateAgent"                      = @{
        ModuleName   = "ComputerManagementDsc"
        ResourceName = "WindowsUpdateAgent"
        GalleryName  = "ComputerManagementDsc"
        Description  = "Windows Update agent configuration resource"
    }
  
    # SQL Server resources
    "Microsoft.SqlServer/Database"                              = @{
        ModuleName   = "SqlServerDsc"
        ResourceName = "SqlDatabase"
        GalleryName  = "SqlServerDsc"
        Description  = "SQL Server Database resource"
    }
    "Microsoft.SqlServer/Login"                                 = @{
        ModuleName   = "SqlServerDsc"
        ResourceName = "SqlLogin"
        GalleryName  = "SqlServerDsc"
        Description  = "SQL Server Login resource"
    }
    "Microsoft.SqlServer/Server"                                = @{
        ModuleName   = "SqlServerDsc"
        ResourceName = "SqlServer"
        GalleryName  = "SqlServerDsc"
        Description  = "SQL Server installation resource"
    }
  
    # Active Directory resources
    "Microsoft.ActiveDirectory/User"                            = @{
        ModuleName   = "ActiveDirectoryDsc"
        ResourceName = "ADUser"
        GalleryName  = "ActiveDirectoryDsc"
        Description  = "Active Directory User resource"
    }
    "Microsoft.ActiveDirectory/Group"                           = @{
        ModuleName   = "ActiveDirectoryDsc"
        ResourceName = "ADGroup"
        GalleryName  = "ActiveDirectoryDsc"
        Description  = "Active Directory Group resource"
    }
    "Microsoft.ActiveDirectory/Computer"                        = @{
        ModuleName   = "ActiveDirectoryDsc"
        ResourceName = "ADComputer"
        GalleryName  = "ActiveDirectoryDsc"
        Description  = "Active Directory Computer resource"
    }
  
    # Generic Microsoft resources
    "Microsoft/OSInfo"                                          = @{
        ModuleName   = "PSDscResources"
        ResourceName = "OSInfo"
        GalleryName  = "PSDscResources"
        Description  = "Operating System information resource"
    }
    "Microsoft/DSC/Assertion"                                   = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Assertion"
        GalleryName  = "PSDscResources"
        Description  = "DSC Assertion resource"
    }
    "Microsoft/DSC/Group"                                       = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Group"
        GalleryName  = "PSDscResources"
        Description  = "DSC Group resource"
    }
    "Microsoft/DSC/Include"                                     = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Include"
        GalleryName  = "PSDscResources"
        Description  = "DSC Include resource"
    }
    "Microsoft/DSC/PowerShell"                                  = @{
        ModuleName   = "PSDscResources"
        ResourceName = "PowerShell"
        GalleryName  = "PSDscResources"
        Description  = "DSC PowerShell resource"
    }
    "Microsoft/DSC/Transitional/RunCommandOnSet"                = @{
        ModuleName   = "PSDscResources"
        ResourceName = "RunCommandOnSet"
        GalleryName  = "PSDscResources"
        Description  = "DSC Run command on set resource"
    }
    "Microsoft/DSC/Debug/Echo"                                  = @{
        ModuleName   = "PSDscResources"
        ResourceName = "Echo"
        GalleryName  = "PSDscResources"
        Description  = "DSC Debug echo resource"
    }
}

# PowerShell head and tail commandlets for Unix-like functionality
function Get-Head {
    <#
        .SYNOPSIS
                Gets the first N lines from input (similar to Unix head command).
        .DESCRIPTION
                Returns the first N lines from the input. Default is 10 lines.
        .PARAMETER InputObject
                The input to process.
        .PARAMETER Count
                Number of lines to return (default: 10).
        .EXAMPLE
                Get-Content file.txt | Get-Head -Count 5
        .EXAMPLE
                "line1`nline2`nline3" | Get-Head -Count 2
        #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$InputObject,
    
        [Parameter()]
        [int]$Count = 10
    )
  
    begin {
        $lines = @()
    }
  
    process {
        if ($InputObject) {
            $lines += $InputObject
        }
    }
  
    end {
        $lines | Select-Object -First $Count
    }
}

function Get-Tail {
    <#
        .SYNOPSIS
                Gets the last N lines from input (similar to Unix tail command).
        .DESCRIPTION
                Returns the last N lines from the input. Default is 10 lines.
        .PARAMETER InputObject
                The input to process.
        .PARAMETER Count
                Number of lines to return (default: 10).
        .EXAMPLE
                Get-Content file.txt | Get-Tail -Count 5
        .EXAMPLE
                "line1`nline2`nline3" | Get-Tail -Count 2
        #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$InputObject,
    
        [Parameter()]
        [int]$Count = 10
    )
  
    begin {
        $lines = @()
    }
  
    process {
        if ($InputObject) {
            $lines += $InputObject
        }
    }
  
    end {
        $lines | Select-Object -Last $Count
    }
}

# Create aliases for head and tail
Set-Alias -Name head -Value Get-Head
Set-Alias -Name tail -Value Get-Tail

# Initialize module installer cache
function Initialize-InstallerCache {
    # Validate paths
    if ($null -eq $script:ModuleConfig.InstallerCachePath -or [string]::IsNullOrWhiteSpace($script:ModuleConfig.InstallerCachePath)) {
        throw "InstallerCachePath is null or empty. Check module initialization."
    }
    if ($null -eq $script:ModuleConfig.InstallerCacheFile -or [string]::IsNullOrWhiteSpace($script:ModuleConfig.InstallerCacheFile)) {
        throw "InstallerCacheFile is null or empty. Check module initialization."
    }
    try {
        if (-not (Test-Path $script:ModuleConfig.InstallerCachePath)) {
            New-Item -Path $script:ModuleConfig.InstallerCachePath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $script:ModuleConfig.InstallerCacheFile)) {
            @{
                LastUpdateCheck   = $null
                AvailableVersions = @{}
                CurrentVersion    = $null
            } | ConvertTo-Json | Set-Content -Path $script:ModuleConfig.InstallerCacheFile
        }
    }
    catch {
        Write-Warning "Failed to initialize installer cache: $($_.Exception.Message)"
        # Don't throw here to prevent call depth overflow
    }
}

# Initialize module resource cache
function Initialize-ResourceCache {
    # Validate paths
    if ($null -eq $script:ModuleConfig.ResourceCachePath -or [string]::IsNullOrWhiteSpace($script:ModuleConfig.ResourceCachePath)) {
        throw "ResourceCachePath is null or empty. Check module initialization."
    }
    if ($null -eq $script:ModuleConfig.ResourceCacheFile -or [string]::IsNullOrWhiteSpace($script:ModuleConfig.ResourceCacheFile)) {
        throw "ResourceCacheFile is null or empty. Check module initialization."
    }
    try {
        if (-not (Test-Path $script:ModuleConfig.ResourceCachePath)) {
            New-Item -Path $script:ModuleConfig.ResourceCachePath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $script:ModuleConfig.ResourceCacheFile)) {
            @{
                LastUpdateCheck    = $null
                AvailableResources = @{}
                ResourceMetadata   = @{}
                CurrentVersions    = @{}
            } | ConvertTo-Json | Set-Content -Path $script:ModuleConfig.ResourceCacheFile
        }
    }
    catch {
        Write-Warning "Failed to initialize resource cache: $($_.Exception.Message)"
        # Don't throw here to prevent call depth overflow
    }
}

# Get installer cache data
function Get-InstallerCache {
    Initialize-InstallerCache
  
    try {
        $cacheContent = Get-Content -Path $script:ModuleConfig.InstallerCacheFile -Raw -ErrorAction Stop
        $cache = $cacheContent | ConvertFrom-Json -ErrorAction Stop
    
        # Validate cache structure
        if (-not $cache.PSObject.Properties.Name -contains "LastUpdateCheck" -or 
            -not $cache.PSObject.Properties.Name -contains "AvailableVersions" -or 
            -not $cache.PSObject.Properties.Name -contains "CurrentVersion") {
            throw "Invalid cache structure detected"
        }
    
        return $cache
    }
    catch {
        Write-Warning "Failed to read installer cache: $($_.Exception.Message). Reinitializing cache."
    
        # Reinitialize cache with default structure
        @{
            LastUpdateCheck   = $null
            AvailableVersions = @{}
            CurrentVersion    = $null
        } | ConvertTo-Json | Set-Content -Path $script:ModuleConfig.InstallerCacheFile -Force
    
        # Return the default cache structure
        return @{
            LastUpdateCheck   = $null
            AvailableVersions = @{}
            CurrentVersion    = $null
        }
    }
}

# Update installer cache
function Update-InstallerCache {
    param([object]$CacheData)
    $CacheData | ConvertTo-Json | Set-Content -Path $script:ModuleConfig.InstallerCacheFile
}

# Get resource cache data
function Get-ResourceCache {
    Initialize-ResourceCache
  
    try {
        $cacheContent = Get-Content -Path $script:ModuleConfig.ResourceCacheFile -Raw -ErrorAction Stop
        $cache = $cacheContent | ConvertFrom-Json -ErrorAction Stop
    
        # Validate cache structure
        if (-not $cache.PSObject.Properties.Name -contains "LastUpdateCheck" -or 
            -not $cache.PSObject.Properties.Name -contains "AvailableResources" -or 
            -not $cache.PSObject.Properties.Name -contains "ResourceMetadata" -or 
            -not $cache.PSObject.Properties.Name -contains "CurrentVersions") {
            throw "Invalid resource cache structure detected"
        }
    
        return $cache
    }
    catch {
        Write-Warning "Failed to read resource cache: $($_.Exception.Message). Reinitializing cache."
    
        # Reinitialize cache with default structure
        @{
            LastUpdateCheck    = $null
            AvailableResources = @{}
            ResourceMetadata   = @{}
            CurrentVersions    = @{}
        } | ConvertTo-Json | Set-Content -Path $script:ModuleConfig.ResourceCacheFile -Force
    
        # Return the default cache structure
        return @{
            LastUpdateCheck    = $null
            AvailableResources = @{}
            ResourceMetadata   = @{}
            CurrentVersions    = @{}
        }
    }
}

# Update resource cache
function Update-ResourceCache {
    param([object]$CacheData)
    $CacheData | ConvertTo-Json | Set-Content -Path $script:ModuleConfig.ResourceCacheFile
}

# Check if update check is needed
function Test-UpdateCheckNeeded {
    try {
        $cache = Get-InstallerCache
        if (-not $cache.LastUpdateCheck) { return $true }
    
        $lastCheck = [DateTime]::Parse($cache.LastUpdateCheck)
        $daysSinceLastCheck = (Get-Date) - $lastCheck
        return $daysSinceLastCheck.Days -ge $script:ModuleConfig.UpdateCheckInterval
    }
    catch {
        Write-Warning "Failed to check update status: $($_.Exception.Message). Assuming update is needed."
        return $true
    }
}

# Get platform-specific asset information
function Get-PlatformAsset {
    param([string]$Platform, [object[]]$Assets)
  
    switch ($Platform.ToLower()) {
        "windows" {
            # Look for Windows-specific assets (DSC v3 uses x86_64-pc-windows-msvc.zip format)
            $patterns = @(
                "*x86_64-pc-windows-msvc.zip",
                "*x86_64-windows*.zip",
                "*windows*.zip",
                "*win*.zip", 
                "*x64*.zip",
                "*.zip"
            )
        }
        "linux" {
            # Look for Linux-specific assets (DSC v3 uses x86_64-linux.tar.gz format)
            $patterns = @(
                "*x86_64-linux.tar.gz",
                "*x86_64-linux*.tar.gz",
                "*linux*.tar.gz",
                "*linux*.zip",
                "*ubuntu*.tar.gz",
                "*debian*.tar.gz"
            )
        }
        "macos" {
            # Look for macOS-specific assets (DSC v3 uses x86_64-apple-darwin.tar.gz format)
            $patterns = @(
                "*x86_64-apple-darwin.tar.gz",
                "*x86_64-macos*.tar.gz",
                "*macos*.tar.gz",
                "*mac*.tar.gz",
                "*osx*.tar.gz"
            )
        }
        default {
            # Default to Windows for backward compatibility
            $patterns = @("*x86_64-pc-windows-msvc.zip", "*windows*.zip", "*win*.zip", "*.zip")
        }
    }
  
    foreach ($pattern in $patterns) {
        $asset = $Assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if ($asset) {
            return $asset
        }
    }
  
    return $null
}

# Get latest DSC version information
function Get-LatestDscVersion {
    param([string]$Platform = "Windows")
  
    try {
        $releasesUrl = "https://api.github.com/repos/PowerShell/DSC/releases/latest"
        $response = Invoke-RestMethod -Uri $releasesUrl -Method Get
    
        Write-Host "Debug: Found release $($response.tag_name) with $($response.assets.Count) assets" -ForegroundColor Cyan
    
        # Get platform-specific asset
        $platformAsset = Get-PlatformAsset -Platform $Platform -Assets $response.assets
    
        if (-not $platformAsset) {
            Write-Warning "No DSC asset found for platform '$Platform' in latest release. Available assets:"
            foreach ($asset in $response.assets) {
                Write-Warning "  - $($asset.name)"
            }
            return $null
        }
    
        if (-not $platformAsset.browser_download_url) {
            Write-Warning "Download URL not found for DSC asset: $($platformAsset.name)"
            return $null
        }
    
        return @{
            Version     = $response.tag_name.TrimStart('v')
            DownloadUrl = $platformAsset.browser_download_url
            PublishedAt = $response.published_at
            Platform    = $Platform
            AssetName   = $platformAsset.name
        }
    }
    catch {
        Write-Warning "Failed to get latest DSC version information: $($_.Exception.Message)"
        return $null
    }
}

# Download DSC installer
function Download-DscInstaller {
    param([string]$Version, [string]$DownloadUrl, [string]$Platform = "Windows", [string]$AssetName, [switch]$Quiet)
  
    # Determine file extension from asset name
    $fileExtension = if ($AssetName) { [System.IO.Path]::GetExtension($AssetName) } else { ".zip" }
    $installerPath = Join-Path $script:ModuleConfig.InstallerCachePath "DSC-$Version-$Platform$fileExtension"
  
    if (Test-Path $installerPath) {
        if (-not $Quiet) {
            Write-Host "DSC installer version $Version for $Platform already exists locally" -ForegroundColor Green
        }
        return $installerPath
    }
  
    if (-not $Quiet) {
        Write-Host "Downloading DSC installer version $Version for $Platform..." -ForegroundColor Yellow
        Write-Host "Download URL: $DownloadUrl" -ForegroundColor Cyan
        Write-Host "Asset: $AssetName" -ForegroundColor Cyan
    }
  
    try {
        # Validate URL
        if (-not [System.Uri]::IsWellFormedUriString($DownloadUrl, [System.UriKind]::Absolute)) {
            throw "Invalid download URL: $DownloadUrl"
        }
    
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath -UseBasicParsing
        if (-not $Quiet) {
            Write-Host "DSC installer version $Version for $Platform downloaded successfully" -ForegroundColor Green
        }
        return $installerPath
    }
    catch {
        Write-Error "Failed to download DSC installer version $Version for $Platform`: $($_.Exception.Message)"
        return $null
    }
}

# Update DSC installer cache (internal function)
function Update-DscInstallerCacheInternal {
    param([switch]$Force, [switch]$Quiet, [int]$MaxVersions = $script:ModuleConfig.MaxCachedVersions, [string[]]$Platforms = @("Windows"))
  
    if (-not $Force -and -not (Test-UpdateCheckNeeded)) {
        if (-not $Quiet) {
            Write-Host "DSC installer cache is up to date" -ForegroundColor Green
        }
        return
    }
  
    if (-not $Quiet) {
        Write-Host "Checking for DSC installer updates..." -ForegroundColor Yellow
    }
  
    $cache = Get-InstallerCache
    $cache.LastUpdateCheck = (Get-Date).ToString("o")
  
    # Download for each platform
    foreach ($platform in $Platforms) {
        if (-not $Quiet) {
            Write-Host "Checking for $platform platform..." -ForegroundColor Cyan
        }
    
        $latestVersion = Get-LatestDscVersion -Platform $platform
        if (-not $latestVersion) {
            Write-Warning "Could not retrieve latest DSC version information for $platform"
            continue
        }
    
        if (-not $Quiet) {
            Write-Host "Latest DSC version for $platform found: $($latestVersion.Version)" -ForegroundColor Cyan
        }
    
        # Create platform-specific version key
        $versionKey = "$($latestVersion.Version)-$platform"
    
        # Check if we need to download the latest version for this platform
        if (-not $cache.AvailableVersions.PSObject.Properties.Name -contains $versionKey) {
            $installerPath = Download-DscInstaller -Version $latestVersion.Version -DownloadUrl $latestVersion.DownloadUrl -Platform $platform -AssetName $latestVersion.AssetName -Quiet:$Quiet
            if ($installerPath) {
                $cache.AvailableVersions | Add-Member -MemberType NoteProperty -Name $versionKey -Value @{
                    DownloadUrl = $latestVersion.DownloadUrl
                    PublishedAt = $latestVersion.PublishedAt
                    LocalPath   = $installerPath
                    Platform    = $platform
                    Version     = $latestVersion.Version
                    AssetName   = $latestVersion.AssetName
                } -Force
        
                # Set current version for this platform
                $cache.CurrentVersion = $latestVersion.Version
            }
        }
    }
  
    # Manage version limits
    $cache = Manage-CachedVersions -Cache $cache -MaxVersions $MaxVersions -Quiet:$Quiet
  
    Update-InstallerCache -CacheData $cache
  
    if (-not $Quiet) {
        Write-Host "DSC installer cache updated successfully" -ForegroundColor Green
    }
}

# Manage cached version limits
function Manage-CachedVersions {
    param(
        [object]$Cache,
        [int]$MaxVersions = $script:ModuleConfig.MaxCachedVersions,
        [switch]$Quiet
    )

    # Build a sortable list of versions based on the key prefix before the platform suffix
    $keys = $Cache.AvailableVersions.PSObject.Properties.Name
    $items = foreach ($k in $keys) {
        $v = [Version]"0.0.0"
        if ($k -match '^([^-]+)') {
            try {
                $v = [Version]$matches[1]
            }
            catch {
                $v = [Version]"0.0.0"
            }
        }
        [PSCustomObject]@{ Key = $k; Ver = $v }
    }
    $versions = ($items | Sort-Object Ver -Descending).Key

    if ($versions.Count -le $MaxVersions) {
        return $Cache
    }

    # Keep the most recent versions and remove older ones
    $versionsToKeep = $versions | Select-Object -First $MaxVersions
    $versionsToRemove = $versions | Select-Object -Skip $MaxVersions

    if (-not $Quiet) {
        Write-Host "Managing cached versions: keeping $MaxVersions most recent versions" -ForegroundColor Yellow
    }

    foreach ($version in $versionsToRemove) {
        $installerPath = $Cache.AvailableVersions[$version].LocalPath
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force
            if (-not $Quiet) {
                Write-Host "Removed older DSC installer version: $version" -ForegroundColor Yellow
            }
        }
        # Remove from cache
        $Cache.AvailableVersions.PSObject.Properties.Remove($version)
    }

    # Update current version if it was removed
    # Extract version part from the first kept version to update CurrentVersion
    if ($Cache.CurrentVersion -and $versionsToKeep.Count -gt 0) {
        $firstKeptVersion = $versionsToKeep[0]
        if ($firstKeptVersion -match '^([^-]+)') {
            $newCurrentVersion = $matches[1]
            if ($newCurrentVersion -ne $Cache.CurrentVersion) {
                $Cache.CurrentVersion = $newCurrentVersion
                if (-not $Quiet) {
                    Write-Host "Updated current version to: $($Cache.CurrentVersion)" -ForegroundColor Yellow
                }
            }
        }
    }

    return $Cache
}

# Get best available DSC installer path
function Get-DscInstallerPath {
    param([string]$PreferredVersion, [string]$TargetPlatform = "Windows", [switch]$Quiet)
  
    # Update cache if needed
    Update-DscInstallerCacheInternal -Quiet:$Quiet -Platforms @($TargetPlatform)
  
    $cache = Get-InstallerCache
  
    if (-not $Quiet) {
        $versions = $cache.AvailableVersions.PSObject.Properties.Name -join ', '
        Write-Host "Available cached versions: $versions" -ForegroundColor Cyan
        Write-Host "Current version: $($cache.CurrentVersion)" -ForegroundColor Cyan
        Write-Host "Target platform: $TargetPlatform" -ForegroundColor Cyan
    }
  
    # Look for platform-specific versions first
    $platformVersions = $cache.AvailableVersions.PSObject.Properties.Name | Where-Object { $_ -like "*-$TargetPlatform" }
  
    # If preferred version is specified, try to use it for the target platform
    if ($PreferredVersion) {
        $preferredKey = "$PreferredVersion-$TargetPlatform"
        if ($cache.AvailableVersions.PSObject.Properties.Name -contains $preferredKey) {
            $installerPath = $cache.AvailableVersions[$preferredKey].LocalPath
            if (Test-Path $installerPath) {
                if (-not $Quiet) {
                    Write-Host "Using preferred version for $TargetPlatform - $PreferredVersion" -ForegroundColor Green
                }
                return $installerPath
            }
        }
    }
  
    # Use current version for the target platform
    if ($cache.CurrentVersion) {
        $currentKey = "$($cache.CurrentVersion)-$TargetPlatform"
        if ($cache.AvailableVersions.PSObject.Properties.Name -contains $currentKey) {
            $installerPath = $cache.AvailableVersions[$currentKey].LocalPath
            if (Test-Path $installerPath) {
                if (-not $Quiet) {
                    Write-Host "Using current version for $TargetPlatform - $($cache.CurrentVersion)" -ForegroundColor Green
                }
                return $installerPath
            }
        }
    }
  
    # Use any available version for the target platform
    foreach ($version in $platformVersions) {
        $installerPath = $cache.AvailableVersions[$version].LocalPath
        if (Test-Path $installerPath) {
            if (-not $Quiet) {
                Write-Host "Using available version for $TargetPlatform - $version" -ForegroundColor Green
            }
            return $installerPath
        }
    }
  
    # Fallback to any Windows version if target platform not found
    if ($TargetPlatform -ne "Windows") {
        if (-not $Quiet) {
            Write-Host "No $TargetPlatform installer found, checking for Windows fallback..." -ForegroundColor Yellow
        }
        return Get-DscInstallerPath -PreferredVersion $PreferredVersion -TargetPlatform "Windows" -Quiet:$Quiet
    }
  
    if (-not $Quiet) {
        Write-Host "No cached installer found for $TargetPlatform" -ForegroundColor Red
        Write-Host "Available versions in cache: $($cache.AvailableVersions.PSObject.Properties.Name -join ', ')" -ForegroundColor Yellow
        Write-Host "To download installers, run: Update-DscInstallerCache" -ForegroundColor Cyan
        Write-Host "To allow online installation, use -AllowRemoteDownload parameter" -ForegroundColor Cyan
    }
    return $null
}

# Get mapped resource information
function Get-MappedResourceInfo {
    param([string]$ResourceType)
  
    if ($script:ResourceMapping.ContainsKey($ResourceType)) {
        return $script:ResourceMapping[$ResourceType]
    }
  
    # Try partial matching for resources that might not be exactly mapped
    foreach ($key in $script:ResourceMapping.Keys) {
        if ($key -like "*$ResourceType*" -or $ResourceType -like "*$($script:ResourceMapping[$key].ResourceName)*") {
            return $script:ResourceMapping[$key]
        }
    }
  
    return $null
}

# Get available DSC resources from official sources
function Get-DscResourceCatalog {
    param([switch]$Quiet)
  
    try {
        # DSC v3 resources are distributed through multiple channels:
        # 1. Built-in resources (bundled with DSC)
        # 2. PowerShell Gallery (for classic DSC resources via adapters)
        # 3. GitHub releases (for community resources)
        # 4. Microsoft official repositories
    
        $catalog = @{
            BuiltInResources   = @()
            GalleryResources   = @()
            CommunityResources = @()
            OfficialResources  = @()
            MappedResources    = @()
        }
    
        # Get built-in resources from current DSC installation
        if (-not $Quiet) {
            Write-Host "Discovering built-in DSC resources..." -ForegroundColor Cyan
        }
    
        try {
            $builtInResources = & dsc resource list --output-format json 2>&1 | ConvertFrom-Json
            $catalog.BuiltInResources = $builtInResources | ForEach-Object {
                @{
                    Type         = $_.type
                    Version      = $_.version
                    Kind         = $_.kind
                    Capabilities = $_.capabilities
                    Description  = $_.description
                    Directory    = $_.directory
                    Path         = $_.path
                    Source       = "BuiltIn"
                }
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Could not discover built-in resources: $($_.Exception.Message)"
            }
        }
    
        # Get PowerShell Gallery resources (classic DSC resources)
        if (-not $Quiet) {
            Write-Host "Discovering PowerShell Gallery DSC resources..." -ForegroundColor Cyan
        }
    
        try {
            # Search for DSC resources in PowerShell Gallery
            $galleryResources = Find-Module -Name "*DSC*" -ErrorAction SilentlyContinue 
      
            # If Find-Module fails or returns no results, try using Save-Module for known DSC modules
            if (-not $galleryResources -or $galleryResources.Count -eq 0) {
                if (-not $Quiet) {
                    Write-Host "Find-Module returned no results, trying Save-Module for known DSC modules..." -ForegroundColor Yellow
                }
        
                # List of known DSC modules to try
                $knownDscModules = @(
                    "NetworkingDsc",
                    "ComputerManagementDsc", 
                    "ActiveDirectoryDsc",
                    "SqlServerDsc",
                    "SharePointDsc",
                    "ExchangeDsc",
                    "OfficeOnlineServerDsc",
                    "FSLogixDsc",
                    "PSDscResources",
                    "xPSDesiredStateConfiguration"
                )
        
                $galleryResources = @()
                foreach ($moduleName in $knownDscModules) {
                    try {
                        # Try to get module info using Save-Module approach
                        $tempDir = Join-Path $env:TEMP "DscModuleInfo"
                        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            
                        try {
                            # Save the module to get its metadata
                            Save-Module -Name $moduleName -Path $tempDir -Force -ErrorAction Stop
                            $modulePath = Join-Path $tempDir $moduleName
                            $moduleManifest = Get-ChildItem -Path $modulePath -Name "*.psd1" | Select-Object -First 1
              
                            if ($moduleManifest) {
                                $manifestPath = Join-Path $modulePath $moduleManifest
                                $manifest = Import-PowerShellDataFile -Path $manifestPath
                
                                $galleryResources += [PSCustomObject]@{
                                    Name          = $moduleName
                                    Version       = $manifest.ModuleVersion
                                    Description   = $manifest.Description
                                    Author        = $manifest.Author
                                    ProjectUri    = $manifest.ProjectUri
                                    Tags          = $manifest.Tags
                                    PublishedDate = (Get-Date).ToString("o")
                                }
                
                                if (-not $Quiet) {
                                    Write-Host "Successfully discovered $moduleName using Save-Module" -ForegroundColor Green
                                }
                            }
                        }
                        finally {
                            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    catch {
                        if (-not $Quiet) {
                            Write-Debug "Could not discover $moduleName`: $($_.Exception.Message)"
                        }
                    }
                }
            }
      
            $catalog.GalleryResources = $galleryResources | ForEach-Object {
                @{
                    Name          = $_.Name
                    Version       = $_.Version
                    Description   = $_.Description
                    Author        = $_.Author
                    Source        = "PowerShellGallery"
                    GalleryUrl    = $_.ProjectUri
                    Tags          = $_.Tags
                    PublishedDate = $_.PublishedDate
                }
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Could not discover PowerShell Gallery resources: $($_.Exception.Message)"
            }
        }
    
        # Add mapped resources to catalog
        foreach ($mappedResource in $script:ResourceMapping.GetEnumerator()) {
            $catalog.MappedResources += @{
                OriginalType = $mappedResource.Key
                ModuleName   = $mappedResource.Value.ModuleName
                ResourceName = $mappedResource.Value.ResourceName
                GalleryName  = $mappedResource.Value.GalleryName
                Description  = $mappedResource.Value.Description
                Source       = "Mapped"
            }
        }
    
        # Get community resources from GitHub
        if (-not $Quiet) {
            Write-Host "Discovering community DSC resources..." -ForegroundColor Cyan
        }
    
        try {
            # Search for popular DSC resource repositories
            $communityRepos = @(
                "PowerShell/DscResources",
                "PowerShell/xDscResources", 
                "PowerShell/NetworkingDsc",
                "PowerShell/ComputerManagementDsc",
                "PowerShell/ActiveDirectoryDsc",
                "PowerShell/SqlServerDsc",
                "PowerShell/SharePointDsc",
                "PowerShell/ExchangeDsc",
                "PowerShell/OfficeOnlineServerDsc",
                "PowerShell/FSLogixDsc"
            )
      
            foreach ($repo in $communityRepos) {
                try {
                    $releasesUrl = "https://api.github.com/repos/$repo/releases/latest"
                    $release = Invoke-RestMethod -Uri $releasesUrl -Method Get -ErrorAction SilentlyContinue
          
                    if ($release) {
                        $catalog.CommunityResources += @{
                            Repository  = $repo
                            Version     = $release.tag_name
                            PublishedAt = $release.published_at
                            DownloadUrl = $release.zipball_url
                            Source      = "GitHub"
                            Name        = $repo.Split('/')[-1]
                        }
                    }
                }
                catch {
                    # Ignore individual repo failures
                    if (-not $Quiet) {
                        Write-Debug "Could not get release info for $repo"
                    }
                }
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Could not discover community resources: $($_.Exception.Message)"
            }
        }
    
        # Get official Microsoft DSC resources
        if (-not $Quiet) {
            Write-Host "Discovering official Microsoft DSC resources..." -ForegroundColor Cyan
        }
    
        try {
            $officialRepos = @(
                "PowerShell/DSC",
                "Microsoft/PowerShell-DSC-for-Linux",
                "Microsoft/PowerShell-DSC-for-Linux"
            )
      
            foreach ($repo in $officialRepos) {
                try {
                    $releasesUrl = "https://api.github.com/repos/$repo/releases/latest"
                    $release = Invoke-RestMethod -Uri $releasesUrl -Method Get -ErrorAction SilentlyContinue
          
                    if ($release) {
                        $catalog.OfficialResources += @{
                            Repository  = $repo
                            Version     = $release.tag_name
                            PublishedAt = $release.published_at
                            DownloadUrl = $release.zipball_url
                            Source      = "Microsoft"
                            Name        = $repo.Split('/')[-1]
                        }
                    }
                }
                catch {
                    # Ignore individual repo failures
                    if (-not $Quiet) {
                        Write-Debug "Could not get release info for $repo"
                    }
                }
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Could not discover official resources: $($_.Exception.Message)"
            }
        }
    
        return $catalog
    }
    catch {
        Write-Warning "Failed to get DSC resource catalog: $($_.Exception.Message)"
        return $null
    }
}

# Download DSC resource package
function Download-DscResource {
    param(
        [string]$ResourceType, 
        [string]$Version, 
        [string]$Source, 
        [string]$DownloadUrl, 
        [switch]$Quiet)
  
    # Check if this is a mapped resource
    $mappedInfo = Get-MappedResourceInfo -ResourceType $ResourceType
    if ($mappedInfo) {
        if (-not $Quiet) {
            Write-Host "Resource $ResourceType is mapped to module $($mappedInfo.ModuleName) from PowerShell Gallery" -ForegroundColor Cyan
        }
        $ResourceType = $mappedInfo.ModuleName
        $Source = "PowerShellGallery"
    }
  
    # Create resource-specific directory
    $resourceDir = Join-Path $script:ModuleConfig.ResourceCachePath $ResourceType
    if (-not (Test-Path $resourceDir)) {
        New-Item -Path $resourceDir -ItemType Directory -Force | Out-Null
    }
  
    # Determine file name and path
    $fileName = "$ResourceType-$Version.zip"
    $resourcePath = Join-Path $resourceDir $fileName
  
    if (Test-Path $resourcePath) {
        if (-not $Quiet) {
            Write-Host "DSC resource $ResourceType version $Version already exists locally" -ForegroundColor Green
        }
        return $resourcePath
    }
  
    if (-not $Quiet) {
        Write-Host "Downloading DSC resource $ResourceType version $Version from $Source..." -ForegroundColor Yellow
    }
  
    try {
        # Handle different source types
        switch ($Source.ToLower()) {
            "powershellgallery" {
                # Download from PowerShell Gallery
                $tempDir = Join-Path $env:TEMP "DscResourceDownload"
                New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        
                try {
                    # Use Save-Module to download the module
                    Save-Module -Name $ResourceType -Path $tempDir -Force -ErrorAction Stop
                    $modulePath = Join-Path $tempDir $ResourceType
          
                    # Verify the module was downloaded
                    if (-not (Test-Path $modulePath)) {
                        throw "Module $ResourceType was not downloaded successfully"
                    }
          
                    # Create a clean package structure
                    $packageDir = Join-Path $env:TEMP "DscResourcePackage"
                    New-Item -Path $packageDir -ItemType Directory -Force | Out-Null
          
                    try {
                        # Copy module files to package directory
                        Copy-Item -Path "$modulePath\*" -Destination $packageDir -Recurse -Force
            
                        # Create the resource package
                        Compress-Archive -Path $packageDir -DestinationPath $resourcePath -Force
                    }
                    finally {
                        Remove-Item -Path $packageDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                finally {
                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            "github" {
                # Download from GitHub
                if (-not [System.Uri]::IsWellFormedUriString($DownloadUrl, [System.UriKind]::Absolute)) {
                    throw "Invalid download URL: $DownloadUrl"
                }
        
                # Download the ZIP file
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $resourcePath -UseBasicParsing -ErrorAction Stop
        
                # Verify the download
                if (-not (Test-Path $resourcePath) -or (Get-Item $resourcePath).Length -eq 0) {
                    throw "Failed to download resource from GitHub or file is empty"
                }
            }
            "microsoft" {
                # Download from Microsoft official sources
                if (-not [System.Uri]::IsWellFormedUriString($DownloadUrl, [System.UriKind]::Absolute)) {
                    throw "Invalid download URL: $DownloadUrl"
                }
        
                # Download the ZIP file
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $resourcePath -UseBasicParsing -ErrorAction Stop
        
                # Verify the download
                if (-not (Test-Path $resourcePath) -or (Get-Item $resourcePath).Length -eq 0) {
                    throw "Failed to download resource from Microsoft or file is empty"
                }
            }
            "builtin" {
                # Copy from built-in DSC installation
                $dscInstallPath = (Get-Command 'dsc.exe' -ErrorAction SilentlyContinue).Source
                if ($dscInstallPath) {
                    $dscDir = Split-Path $dscInstallPath -Parent
                    $resourceFiles = Get-ChildItem -Path $dscDir -Recurse -Filter "*$ResourceType*" -ErrorAction SilentlyContinue
          
                    if ($resourceFiles) {
                        $tempDir = Join-Path $env:TEMP "DscResourceExtract"
                        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            
                        try {
                            foreach ($file in $resourceFiles) {
                                $relativePath = $file.FullName.Substring($dscDir.Length + 1)
                                $targetPath = Join-Path $tempDir $relativePath
                                $targetDir = Split-Path $targetPath -Parent
                
                                if (-not (Test-Path $targetDir)) {
                                    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                                }
                
                                Copy-Item -Path $file.FullName -Destination $targetPath -Force
                            }
              
                            Compress-Archive -Path $tempDir -DestinationPath $resourcePath -Force
                        }
                        finally {
                            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        throw "Resource $ResourceType not found in DSC installation"
                    }
                }
                else {
                    throw "DSC installation not found"
                }
            }
            default {
                throw "Unsupported resource source: $Source"
            }
        }
    
        if (-not $Quiet) {
            Write-Host "DSC resource $ResourceType version $Version downloaded successfully" -ForegroundColor Green
        }
        return $resourcePath
    }
    catch {
        Write-Error "Failed to download DSC resource $ResourceType version $Version`: $($_.Exception.Message)"
        return $null
    }
}

# Update DSC resource cache (internal function)
function Update-DscResourceCacheInternal {
    param([switch]$Force, [switch]$Quiet, [int]$MaxResources = $script:ModuleConfig.MaxCachedResources, [string]$SpecificResource)
  
    # If specific resource is requested, try to download it directly
    if ($SpecificResource) {
        if (-not $Quiet) {
            Write-Host "Attempting to download specific resource: $SpecificResource" -ForegroundColor Yellow
        }
    
        $cache = Get-ResourceCache
        $cache.LastUpdateCheck = (Get-Date).ToString("o")
    
        # Check if this is a mapped resource
        $mappedInfo = Get-MappedResourceInfo -ResourceType $SpecificResource
        if ($mappedInfo) {
            try {
                # Try to download from PowerShell Gallery
                $galleryModule = Find-Module -Name $mappedInfo.GalleryName -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $galleryModule) {
                    # Fallback: try Save-Module directly
                    $tempDir = Join-Path $env:TEMP "DscResourceDownload"
                    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                    try {
                        Save-Module -Name $mappedInfo.GalleryName -Path $tempDir -Force
                        $galleryModule = Get-ChildItem -Path $tempDir -Name $mappedInfo.GalleryName | Select-Object -First 1
                        if ($galleryModule) {
                            $galleryModule = [PSCustomObject]@{
                                Name    = $mappedInfo.GalleryName
                                Version = "1.0.0"  # Default version if we can't determine it
                            }
                        }
                    }
                    catch {
                        if (-not $Quiet) {
                            Write-Warning "Failed to download module $($mappedInfo.GalleryName) via Save-Module: $($_.Exception.Message)"
                        }
                    }
                }
        
                if ($galleryModule) {
                    $resourcePath = Download-DscResource -ResourceType $SpecificResource -Version $galleryModule.Version -Source "PowerShellGallery" -Quiet:$Quiet
                    if ($resourcePath) {
                        $resourceKey = "$SpecificResource-latest"
                        $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                            OriginalType = $SpecificResource
                            ModuleName   = $mappedInfo.ModuleName
                            ResourceName = $mappedInfo.ResourceName
                            GalleryName  = $mappedInfo.GalleryName
                            Version      = $galleryModule.Version
                            Description  = $mappedInfo.Description
                            Source       = "Mapped"
                            LocalPath    = $resourcePath
                            DownloadedAt = (Get-Date).ToString("o")
                        } -Force
            
                        Update-ResourceCache -CacheData $cache
            
                        if (-not $Quiet) {
                            Write-Host "Successfully downloaded specific resource: $SpecificResource" -ForegroundColor Green
                        }
                        return $true
                    }
                }
            }
            catch {
                if (-not $Quiet) {
                    Write-Warning "Failed to download specific resource $SpecificResource`: $($_.Exception.Message)"
                }
            }
        }
        else {
            # Try to find in PowerShell Gallery directly
            try {
                $galleryModule = Find-Module -Name $SpecificResource -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $galleryModule) {
                    # Try with common DSC module naming patterns
                    $possibleNames = @("$SpecificResource", "Dsc$SpecificResource", "$SpecificResource`Dsc")
                    foreach ($name in $possibleNames) {
                        $galleryModule = Find-Module -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($galleryModule) { break }
                    }
                }
        
                if ($galleryModule) {
                    $resourcePath = Download-DscResource -ResourceType $SpecificResource -Version $galleryModule.Version -Source "PowerShellGallery" -Quiet:$Quiet
                    if ($resourcePath) {
                        $resourceKey = "$SpecificResource-$($galleryModule.Version)"
                        $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                            Name          = $SpecificResource
                            Version       = $galleryModule.Version
                            Description   = $galleryModule.Description
                            Author        = $galleryModule.Author
                            Source        = "PowerShellGallery"
                            GalleryUrl    = $galleryModule.ProjectUri
                            Tags          = $galleryModule.Tags
                            PublishedDate = $galleryModule.PublishedDate
                            LocalPath     = $resourcePath
                            DownloadedAt  = (Get-Date).ToString("o")
                        } -Force
            
                        Update-ResourceCache -CacheData $cache
            
                        if (-not $Quiet) {
                            Write-Host "Successfully downloaded specific resource: $SpecificResource" -ForegroundColor Green
                        }
                        return $true
                    }
                }
            }
            catch {
                if (-not $Quiet) {
                    Write-Warning "Failed to download specific resource $SpecificResource`: $($_.Exception.Message)"
                }
            }
        }
    
        if (-not $Quiet) {
            Write-Warning "Could not download specific resource: $SpecificResource"
        }
        return $false
    }
  
    if (-not $Force -and -not (Test-UpdateCheckNeeded)) {
        if (-not $Quiet) {
            Write-Host "DSC resource cache is up to date" -ForegroundColor Green
        }
        return
    }
  
    if (-not $Quiet) {
        Write-Host "Checking for DSC resource updates..." -ForegroundColor Yellow
    }
  
    $cache = Get-ResourceCache
    $cache.LastUpdateCheck = (Get-Date).ToString("o")
  
    # Get resource catalog
    $catalog = Get-DscResourceCatalog -Quiet:$Quiet
    if (-not $catalog) {
        Write-Warning "Could not retrieve DSC resource catalog"
        return
    }
  
    $downloadCount = 0
    $errorCount = 0
  
    # Process built-in resources
    if (-not $Quiet) {
        Write-Host "Processing built-in DSC resources..." -ForegroundColor Cyan
    }
  
    foreach ($resource in $catalog.BuiltInResources) {
        $resourceKey = "$($resource.Type)-$($resource.Version)"
    
        if (-not $cache.AvailableResources.PSObject.Properties.Name -contains $resourceKey) {
            try {
                $resourcePath = Download-DscResource -ResourceType $resource.Type -Version $resource.Version -Source $resource.Source -Quiet:$Quiet
                if ($resourcePath) {
                    $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                        Type         = $resource.Type
                        Version      = $resource.Version
                        Kind         = $resource.Kind
                        Capabilities = $resource.Capabilities
                        Description  = $resource.Description
                        Directory    = $resource.Directory
                        Path         = $resource.Path
                        Source       = $resource.Source
                        LocalPath    = $resourcePath
                        DownloadedAt = (Get-Date).ToString("o")
                    } -Force
          
                    # Store metadata
                    $cache.ResourceMetadata | Add-Member -MemberType NoteProperty -Name $resource.Type -Value @{
                        LatestVersion = $resource.Version
                        LastUpdated   = (Get-Date).ToString("o")
                        Source        = $resource.Source
                    } -Force
          
                    $downloadCount++
                }
            }
            catch {
                $errorCount++
                if (-not $Quiet) {
                    Write-Warning "Failed to download built-in resource $($resource.Type): $($_.Exception.Message)"
                }
            }
        }
    }
  
    # Process mapped resources (classic DSC resources that need to be downloaded from PowerShell Gallery)
    if (-not $Quiet) {
        Write-Host "Processing mapped DSC resources..." -ForegroundColor Cyan
    }
  
    foreach ($mappedResource in $catalog.MappedResources) {
        $resourceKey = "$($mappedResource.OriginalType)-latest"
    
        if (-not $cache.AvailableResources.PSObject.Properties.Name -contains $resourceKey) {
            try {
                # Get the latest version from PowerShell Gallery
                $galleryModule = Find-Module -Name $mappedResource.GalleryName -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($galleryModule) {
                    $resourcePath = Download-DscResource -ResourceType $mappedResource.OriginalType -Version $galleryModule.Version -Source "PowerShellGallery" -Quiet:$Quiet
                    if ($resourcePath) {
                        $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                            OriginalType = $mappedResource.OriginalType
                            ModuleName   = $mappedResource.ModuleName
                            ResourceName = $mappedResource.ResourceName
                            GalleryName  = $mappedResource.GalleryName
                            Version      = $galleryModule.Version
                            Description  = $mappedResource.Description
                            Source       = "Mapped"
                            LocalPath    = $resourcePath
                            DownloadedAt = (Get-Date).ToString("o")
                        } -Force
            
                        # Store metadata
                        $cache.ResourceMetadata | Add-Member -MemberType NoteProperty -Name $mappedResource.OriginalType -Value @{
                            LatestVersion = $galleryModule.Version
                            LastUpdated   = (Get-Date).ToString("o")
                            Source        = "Mapped"
                            ModuleName    = $mappedResource.ModuleName
                        } -Force
            
                        $downloadCount++
                    }
                }
            }
            catch {
                $errorCount++
                if (-not $Quiet) {
                    Write-Warning "Failed to download mapped resource $($mappedResource.OriginalType): $($_.Exception.Message)"
                }
            }
        }
    }
  
    # Process PowerShell Gallery resources
    if (-not $Quiet) {
        Write-Host "Processing PowerShell Gallery DSC resources..." -ForegroundColor Cyan
    }
  
    foreach ($resource in $catalog.GalleryResources) {
        $resourceKey = "$($resource.Name)-$($resource.Version)"
    
        if (-not $cache.AvailableResources.PSObject.Properties.Name -contains $resourceKey) {
            try {
                $resourcePath = Download-DscResource -ResourceType $resource.Name -Version $resource.Version -Source $resource.Source -Quiet:$Quiet
                if ($resourcePath) {
                    $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                        Name          = $resource.Name
                        Version       = $resource.Version
                        Description   = $resource.Description
                        Author        = $resource.Author
                        Source        = $resource.Source
                        GalleryUrl    = $resource.GalleryUrl
                        Tags          = $resource.Tags
                        PublishedDate = $resource.PublishedDate
                        LocalPath     = $resourcePath
                        DownloadedAt  = (Get-Date).ToString("o")
                    } -Force
          
                    # Store metadata
                    $cache.ResourceMetadata | Add-Member -MemberType NoteProperty -Name $resource.Name -Value @{
                        LatestVersion = $resource.Version
                        LastUpdated   = (Get-Date).ToString("o")
                        Source        = $resource.Source
                    } -Force
          
                    $downloadCount++
                }
            }
            catch {
                $errorCount++
                if (-not $Quiet) {
                    Write-Warning "Failed to download Gallery resource $($resource.Name): $($_.Exception.Message)"
                }
            }
        }
    }
  
    # Process community resources from GitHub
    if (-not $Quiet) {
        Write-Host "Processing community DSC resources..." -ForegroundColor Cyan
    }
  
    foreach ($resource in $catalog.CommunityResources) {
        $resourceKey = "$($resource.Name)-$($resource.Version)"
    
        if (-not $cache.AvailableResources.PSObject.Properties.Name -contains $resourceKey) {
            try {
                $resourcePath = Download-DscResource -ResourceType $resource.Name -Version $resource.Version -Source $resource.Source -DownloadUrl $resource.DownloadUrl -Quiet:$Quiet
                if ($resourcePath) {
                    $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                        Name         = $resource.Name
                        Version      = $resource.Version
                        Repository   = $resource.Repository
                        PublishedAt  = $resource.PublishedAt
                        Source       = $resource.Source
                        LocalPath    = $resourcePath
                        DownloadedAt = (Get-Date).ToString("o")
                    } -Force
          
                    # Store metadata
                    $cache.ResourceMetadata | Add-Member -MemberType NoteProperty -Name $resource.Name -Value @{
                        LatestVersion = $resource.Version
                        LastUpdated   = (Get-Date).ToString("o")
                        Source        = $resource.Source
                    } -Force
          
                    $downloadCount++
                }
            }
            catch {
                $errorCount++
                if (-not $Quiet) {
                    Write-Warning "Failed to download community resource $($resource.Name): $($_.Exception.Message)"
                }
            }
        }
    }
  
    # Process official Microsoft resources
    if (-not $Quiet) {
        Write-Host "Processing official Microsoft DSC resources..." -ForegroundColor Cyan
    }
  
    foreach ($resource in $catalog.OfficialResources) {
        $resourceKey = "$($resource.Name)-$($resource.Version)"
    
        if (-not $cache.AvailableResources.PSObject.Properties.Name -contains $resourceKey) {
            try {
                $resourcePath = Download-DscResource -ResourceType $resource.Name -Version $resource.Version -Source $resource.Source -DownloadUrl $resource.DownloadUrl -Quiet:$Quiet
                if ($resourcePath) {
                    $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $resourceKey -Value @{
                        Name         = $resource.Name
                        Version      = $resource.Version
                        Repository   = $resource.Repository
                        PublishedAt  = $resource.PublishedAt
                        Source       = $resource.Source
                        LocalPath    = $resourcePath
                        DownloadedAt = (Get-Date).ToString("o")
                    } -Force
          
                    # Store metadata
                    $cache.ResourceMetadata | Add-Member -MemberType NoteProperty -Name $resource.Name -Value @{
                        LatestVersion = $resource.Version
                        LastUpdated   = (Get-Date).ToString("o")
                        Source        = $resource.Source
                    } -Force
          
                    $downloadCount++
                }
            }
            catch {
                $errorCount++
                if (-not $Quiet) {
                    Write-Warning "Failed to download official resource $($resource.Name): $($_.Exception.Message)"
                }
            }
        }
    }
  
    # Manage resource limits
    $cache = Manage-CachedResources -Cache $cache -MaxResources $MaxResources -Quiet:$Quiet
  
    Update-ResourceCache -CacheData $cache
  
    if (-not $Quiet) {
        Write-Host "DSC resource cache updated successfully" -ForegroundColor Green
        Write-Host "Downloaded $downloadCount new resources, $errorCount errors encountered" -ForegroundColor Cyan
    }
}

# Manage cached resource limits
function Manage-CachedResources {
    param([object]$Cache, [int]$MaxResources = $script:ModuleConfig.MaxCachedResources, [switch]$Quiet)
  
    $resources = $Cache.AvailableResources.PSObject.Properties.Name | Sort-Object -Descending
  
    if ($resources.Count -le $MaxResources) {
        return $Cache
    }
  
    # Keep the most recent resources and remove older ones
    $resourcesToKeep = $resources | Select-Object -First $MaxResources
    $resourcesToRemove = $resources | Select-Object -Skip $MaxResources
  
    if (-not $Quiet) {
        Write-Host "Managing cached resources: keeping $MaxResources most recent resources" -ForegroundColor Yellow
    }
  
    foreach ($resource in $resourcesToRemove) {
        $resourcePath = $Cache.AvailableResources[$resource].LocalPath
        if (Test-Path $resourcePath) {
            Remove-Item -Path $resourcePath -Force
            if (-not $Quiet) {
                Write-Host "Removed older DSC resource: $resource" -ForegroundColor Yellow
            }
        }
    
        # Remove from cache
        $Cache.AvailableResources.PSObject.Properties.Remove($resource)
    }
  
    return $Cache
}

# Get best available DSC resource path
function Get-DscResourcePath {
    param([string]$ResourceType, [string]$PreferredVersion, [switch]$Quiet)
  
    # Update cache if needed
    Update-DscResourceCacheInternal -Quiet:$Quiet
  
    # Load cache directly to avoid function scope issues
    Initialize-ResourceCache
    $cacheContent = Get-Content -Path $script:ModuleConfig.ResourceCacheFile -Raw
    $cache = $cacheContent | ConvertFrom-Json
  
    if (-not $Quiet) {
        $resources = $cache.AvailableResources.PSObject.Properties.Name -join ', '
        Write-Host "Available cached resources: $resources" -ForegroundColor Cyan
        Write-Host "Target resource: $ResourceType" -ForegroundColor Cyan
    }
  
    # Check if this is a mapped resource
    $mappedInfo = Get-MappedResourceInfo -ResourceType $ResourceType
    if ($mappedInfo) {
        if (-not $Quiet) {
            Write-Host "Resource $ResourceType is mapped to module $($mappedInfo.ModuleName)" -ForegroundColor Cyan
        }
    
        # Look for mapped resource in cache
        $mappedKey = "$ResourceType-latest"
        if ($cache.AvailableResources.PSObject.Properties.Name -contains $mappedKey) {
            $resourceObj = $cache.AvailableResources.PSObject.Properties[$mappedKey].Value
            $resourcePath = $resourceObj.LocalPath
            if (Test-Path $resourcePath) {
                if (-not $Quiet) {
                    Write-Host "Using mapped resource for $ResourceType" -ForegroundColor Green
                }
                return $resourcePath
            }
        }
    
        # If not found, try to download it now
        if (-not $Quiet) {
            Write-Host "Mapped resource not found in cache, attempting to download..." -ForegroundColor Yellow
        }
    
        try {
            $galleryModule = Find-Module -Name $mappedInfo.GalleryName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($galleryModule) {
                $resourcePath = Download-DscResource -ResourceType $ResourceType -Version $galleryModule.Version -Source "PowerShellGallery" -Quiet:$Quiet
                if ($resourcePath) {
                    # Add to cache
                    $cache = Get-ResourceCache
                    $cache.AvailableResources | Add-Member -MemberType NoteProperty -Name $mappedKey -Value @{
                        OriginalType = $ResourceType
                        ModuleName   = $mappedInfo.ModuleName
                        ResourceName = $mappedInfo.ResourceName
                        GalleryName  = $mappedInfo.GalleryName
                        Version      = $galleryModule.Version
                        Description  = $mappedInfo.Description
                        Source       = "Mapped"
                        LocalPath    = $resourcePath
                        DownloadedAt = (Get-Date).ToString("o")
                    } -Force
          
                    Update-ResourceCache -CacheData $cache
          
                    if (-not $Quiet) {
                        Write-Host "Successfully downloaded and cached mapped resource for $ResourceType" -ForegroundColor Green
                    }
                    return $resourcePath
                }
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Failed to download mapped resource $ResourceType`: $($_.Exception.Message)"
            }
        }
    }
  
    # Look for exact resource type match (support partial matches and return latest version)
    $matchingResources = $cache.AvailableResources.PSObject.Properties.Name | Where-Object { $_ -like "$ResourceType-*" -or $_ -eq $ResourceType -or $_ -like "$ResourceType*" }
  
    # If preferred version is specified, try to use it
    if ($PreferredVersion) {
        $preferredKey = "$ResourceType-$PreferredVersion"
        if ($cache.AvailableResources.PSObject.Properties.Name -contains $preferredKey) {
            $resourceObj = $cache.AvailableResources.PSObject.Properties[$preferredKey].Value
            $resourcePath = $resourceObj.LocalPath
            if (Test-Path $resourcePath) {
                if (-not $Quiet) {
                    Write-Host "Using preferred version for $ResourceType - $PreferredVersion" -ForegroundColor Green
                }
                return $resourcePath
            }
        }
    }
  
    # Use latest version (sort by version if possible)
    if ($matchingResources.Count -gt 0) {
        # Try to sort by version number if possible
        $latestResource = $matchingResources | Sort-Object { 
            if ($_ -match "-(\d+\.[\d\.]+)$") { [version]$matches[1] } else { [version]"0.0.0.0" } 
        } -Descending | Select-Object -First 1
    
        if (-not $Quiet) {
            Write-Host "Debug: Latest resource key: $latestResource" -ForegroundColor Cyan
            Write-Host "Debug: Type of AvailableResources: $($cache.AvailableResources.GetType().FullName)" -ForegroundColor Cyan
            Write-Host "Debug: Keys: $($cache.AvailableResources.PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan
        }
    
        $resourceObj = $cache.AvailableResources.PSObject.Properties[$latestResource].Value
        $resourcePath = $resourceObj.LocalPath
    
        if (-not $Quiet) {
            Write-Host "Debug: Resource path: $resourcePath" -ForegroundColor Cyan
        }
    
        if ($resourcePath -and (Test-Path $resourcePath)) {
            if (-not $Quiet) {
                Write-Host "Using available version for $ResourceType - $latestResource" -ForegroundColor Green
            }
            return $resourcePath
        }
        else {
            if (-not $Quiet) {
                Write-Host "Debug: Resource path is null or file doesn't exist" -ForegroundColor Yellow
            }
        }
    }
  
    if (-not $Quiet) {
        Write-Host "No cached resource found for $ResourceType" -ForegroundColor Red
    }
    return $null
}

# Ensure required DSC resources are available in cache
function Test-DscResourceAvailability {
    [CmdletBinding()]
    param(
        [string[]]$ResourceTypes,
        [switch]$Quiet,
        [switch]$Force
    )
  
    if (-not $ResourceTypes -or $ResourceTypes.Count -eq 0) {
        return @{ Success = $true; MissingResources = @() }
    }
  
    if (-not $Quiet) {
        Write-Host "Ensuring required DSC resources are available in cache..." -ForegroundColor Yellow
    }
  
    $missingResources = @()
    $availableResources = @()
  
    foreach ($resourceType in $ResourceTypes) {
        $resourcePath = Get-DscResourcePath -ResourceType $resourceType -Quiet:$Quiet
        if ($resourcePath) {
            $availableResources += $resourceType
            if (-not $Quiet) {
                Write-Host "✓ Resource available: $resourceType" -ForegroundColor Green
            }
        }
        else {
            $missingResources += $resourceType
            if (-not $Quiet) {
                Write-Host "✗ Resource missing: $resourceType" -ForegroundColor Red
            }
        }
    }

    # If any resources are missing and Force is specified, attempt to download/cache them now
    if ($missingResources.Count -gt 0 -and $Force) {
        $resolvedNow = @()
        foreach ($res in $missingResources.ToArray()) {
            try {
                $downloaded = Update-DscResourceCacheInternal -Force -Quiet:$Quiet -SpecificResource $res
                if ($downloaded) {
                    $resolvedNow += $res
                    $availableResources += $res
                    $missingResources = $missingResources | Where-Object { $_ -ne $res }
                    if (-not $Quiet) {
                        Write-Host "✓ Resource downloaded: $res" -ForegroundColor Green
                    }
                }
            }
            catch {
                if (-not $Quiet) {
                    Write-Warning "Failed to download ${res}: $($_.Exception.Message)"
                }
            }
        }
    }

    $success = $missingResources.Count -eq 0
    return @{
        Success = $success
        AvailableResources = $availableResources
        MissingResources = $missingResources
    }
}

# Internal helpers and public command wrappers migrated from legacy module

function Test-DscExecutable {
    try {
        $null = Get-Command 'dsc.exe' -ErrorAction Stop
    }
    catch {
        throw "DSC executable (dsc.exe) not found in PATH. Install DSC v3 or update the PATH."
    }
}

function Test-DscPaths {
    param([Parameter(Mandatory)] [string]$DscPath, [string]$ParametersPath)
    if (-not (Test-Path $DscPath -PathType Leaf)) { throw "DSC configuration file not found: $DscPath" }
    if ($ParametersPath -and -not (Test-Path $ParametersPath -PathType Leaf)) { throw "Parameters file not found: $ParametersPath" }
}

function Build-DscArguments {
    param(
        [Parameter(Mandatory)] [ValidateSet('Set','Test','Validate','Export')] [string]$Operation,
        [Parameter(Mandatory)] [string]$DscPath,
        [string]$ParametersPath,
        [switch]$WhatIf
    )
    $args = @('config', $Operation.ToLowerInvariant(), '--file', $DscPath, '--output-format', 'json')
    if ($ParametersPath) { $args += @('--parameters', $ParametersPath) }
    if ($WhatIf -and $Operation -eq 'Set') { $args += '--what-if' }
    return $args
}

function Invoke-DscCommand {
    param([string[]]$Arguments, [string]$TargetComputer = $env:COMPUTERNAME, [switch]$Quiet)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'dsc.exe'
    $psi.Arguments = ($Arguments -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdOut = $p.StandardOutput.ReadToEnd()
    $stdErr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if (-not $Quiet) { Write-Verbose "dsc.exe $($psi.Arguments) -> $($p.ExitCode)" }
    return @{ ExitCode = $p.ExitCode; Output = if ($stdOut) { $stdOut } else { $stdErr } }
}

function Convert-FromDscJson {
    param([Parameter(Mandatory)] [string]$Output)
    try { return ($Output | ConvertFrom-Json) } catch { return [PSCustomObject]@{ Raw = $Output } }
}

function Invoke-DscHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Alias('Path','ConfigPath')][string]$DscPath,
        [Parameter(Mandatory)][ValidateSet('Set','Test','Validate','Export')][Alias('Op','Action')][string]$Operation,
        [string]$ParametersPath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [switch]$ReturnInDesiredState,
        [switch]$Quiet,
        [switch]$WhatIf,
        [PSCredential]$Credential,
        [bool]$AutoInstallDsc = $true,
        [string]$DscInstallerPath,
        [string]$PreferredDscVersion,
        [switch]$ForceUpdateCache,
        [switch]$AllowRemoteDownload,
        [switch]$SshTransport,
        [switch]$UseSsl,
        [Nullable[int]]$Port,
        [string]$SshKeyPath,
        [switch]$SkipCertificateValidation,
        [bool]$AutoInstallDscResources = $true,
        [switch]$SkipResourceCheck
    )

    Test-DscExecutable
    Test-DscPaths -DscPath $DscPath -ParametersPath $ParametersPath
    $dscArgs = Build-DscArguments -Operation $Operation -DscPath $DscPath -ParametersPath $ParametersPath -WhatIf:$WhatIf

    $isRemote = $ComputerName -ne $env:COMPUTERNAME
    if ($isRemote) {
        # For now, simplified: run locally against remote path not supported in this trimmed implementation.
        throw "Remote execution path not yet migrated; use local ComputerName or complete remote helpers migration."
    } else {
        $dscResult = Invoke-DscCommand -Arguments $dscArgs -TargetComputer $env:COMPUTERNAME -Quiet:$Quiet
        if ($dscResult.ExitCode -eq 0) { $result = Convert-FromDscJson -Output $dscResult.Output }
        else { throw "DSC command failed with exit code $($dscResult.ExitCode): $($dscResult.Output)" }
    }

    if ($ReturnInDesiredState) {
        if ($null -ne $result.inDesiredState) { return $result.inDesiredState }
        elseif ($null -ne $result.InDesiredState) { return $result.InDesiredState }
        else { Write-Warning 'InDesiredState property not found in DSC result'; return $null }
    }
    return $result
}

function Test-DscConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Alias('Path','ConfigPath')][string]$DscPath,
        [string]$ParametersPath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [bool]$AutoInstallDsc = $true,
        [string]$DscInstallerPath,
        [string]$PreferredDscVersion,
        [switch]$ForceUpdateCache,
        [switch]$AllowRemoteDownload,
        [switch]$SshTransport,
        [switch]$UseSsl,
        [Nullable[int]]$Port,
        [string]$SshKeyPath,
        [switch]$SkipCertificateValidation,
        [bool]$AutoInstallDscResources = $true,
        [switch]$SkipResourceCheck
    )
    $invokeArgs = @{ DscPath = $DscPath; Operation = 'Test'; ComputerName = $ComputerName; ReturnInDesiredState = $true }
    if ($PSBoundParameters.ContainsKey('ParametersPath')) { $invokeArgs.ParametersPath = $ParametersPath }
    if ($PSBoundParameters.ContainsKey('Credential')) { $invokeArgs.Credential = $Credential }
    if ($PSBoundParameters.ContainsKey('AutoInstallDsc')) { $invokeArgs.AutoInstallDsc = $AutoInstallDsc }
    if ($PSBoundParameters.ContainsKey('DscInstallerPath')) { $invokeArgs.DscInstallerPath = $DscInstallerPath }
    if ($PSBoundParameters.ContainsKey('PreferredDscVersion')) { $invokeArgs.PreferredDscVersion = $PreferredDscVersion }
    if ($PSBoundParameters.ContainsKey('ForceUpdateCache')) { $invokeArgs.ForceUpdateCache = $ForceUpdateCache }
    if ($PSBoundParameters.ContainsKey('AllowRemoteDownload')) { $invokeArgs.AllowRemoteDownload = $AllowRemoteDownload }
    if ($PSBoundParameters.ContainsKey('SshTransport')) { $invokeArgs.SshTransport = $SshTransport }
    if ($PSBoundParameters.ContainsKey('UseSsl')) { $invokeArgs.UseSsl = $UseSsl }
    if ($PSBoundParameters.ContainsKey('Port')) { $invokeArgs.Port = $Port }
    if ($PSBoundParameters.ContainsKey('SshKeyPath')) { $invokeArgs.SshKeyPath = $SshKeyPath }
    if ($PSBoundParameters.ContainsKey('SkipCertificateValidation')) { $invokeArgs.SkipCertificateValidation = $SkipCertificateValidation }
    if ($PSBoundParameters.ContainsKey('AutoInstallDscResources')) { $invokeArgs.AutoInstallDscResources = $AutoInstallDscResources }
    if ($PSBoundParameters.ContainsKey('SkipResourceCheck')) { $invokeArgs.SkipResourceCheck = $SkipResourceCheck }
    return Invoke-DscHelper @invokeArgs
}

function Set-DscConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Alias('Path','ConfigPath')][string]$DscPath,
        [string]$ParametersPath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [switch]$WhatIf,
        [PSCredential]$Credential,
        [bool]$AutoInstallDsc = $true,
        [string]$DscInstallerPath,
        [string]$PreferredDscVersion,
        [switch]$ForceUpdateCache,
        [switch]$AllowRemoteDownload,
        [switch]$SshTransport,
        [switch]$UseSsl,
        [Nullable[int]]$Port,
        [string]$SshKeyPath,
        [switch]$SkipCertificateValidation,
        [bool]$AutoInstallDscResources = $true,
        [switch]$SkipResourceCheck
    )
    $invokeArgs = @{ DscPath = $DscPath; Operation = 'Set'; ComputerName = $ComputerName }
    if ($PSBoundParameters.ContainsKey('ParametersPath')) { $invokeArgs.ParametersPath = $ParametersPath }
    if ($PSBoundParameters.ContainsKey('Credential')) { $invokeArgs.Credential = $Credential }
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $invokeArgs.WhatIf = $WhatIf }
    if ($PSBoundParameters.ContainsKey('AutoInstallDsc')) { $invokeArgs.AutoInstallDsc = $AutoInstallDsc }
    if ($PSBoundParameters.ContainsKey('DscInstallerPath')) { $invokeArgs.DscInstallerPath = $DscInstallerPath }
    if ($PSBoundParameters.ContainsKey('PreferredDscVersion')) { $invokeArgs.PreferredDscVersion = $PreferredDscVersion }
    if ($PSBoundParameters.ContainsKey('ForceUpdateCache')) { $invokeArgs.ForceUpdateCache = $ForceUpdateCache }
    if ($PSBoundParameters.ContainsKey('AllowRemoteDownload')) { $invokeArgs.AllowRemoteDownload = $AllowRemoteDownload }
    if ($PSBoundParameters.ContainsKey('SshTransport')) { $invokeArgs.SshTransport = $SshTransport }
    if ($PSBoundParameters.ContainsKey('UseSsl')) { $invokeArgs.UseSsl = $UseSsl }
    if ($PSBoundParameters.ContainsKey('Port')) { $invokeArgs.Port = $Port }
    if ($PSBoundParameters.ContainsKey('SshKeyPath')) { $invokeArgs.SshKeyPath = $SshKeyPath }
    if ($PSBoundParameters.ContainsKey('SkipCertificateValidation')) { $invokeArgs.SkipCertificateValidation = $SkipCertificateValidation }
    if ($PSBoundParameters.ContainsKey('AutoInstallDscResources')) { $invokeArgs.AutoInstallDscResources = $AutoInstallDscResources }
    if ($PSBoundParameters.ContainsKey('SkipResourceCheck')) { $invokeArgs.SkipResourceCheck = $SkipResourceCheck }
    return Invoke-DscHelper @invokeArgs
}

function Validate-DscConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Alias('Path','ConfigPath')][string]$DscPath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [bool]$AutoInstallDsc = $true,
        [string]$DscInstallerPath,
        [string]$PreferredDscVersion,
        [switch]$ForceUpdateCache,
        [switch]$AllowRemoteDownload,
        [switch]$SshTransport,
        [switch]$UseSsl,
        [Nullable[int]]$Port,
        [string]$SshKeyPath,
        [switch]$SkipCertificateValidation,
        [bool]$AutoInstallDscResources = $true,
        [switch]$SkipResourceCheck
    )
    $invokeArgs = @{ DscPath = $DscPath; Operation = 'Validate'; ComputerName = $ComputerName }
    if ($PSBoundParameters.ContainsKey('Credential')) { $invokeArgs.Credential = $Credential }
    if ($PSBoundParameters.ContainsKey('AutoInstallDsc')) { $invokeArgs.AutoInstallDsc = $AutoInstallDsc }
    if ($PSBoundParameters.ContainsKey('DscInstallerPath')) { $invokeArgs.DscInstallerPath = $DscInstallerPath }
    if ($PSBoundParameters.ContainsKey('PreferredDscVersion')) { $invokeArgs.PreferredDscVersion = $PreferredDscVersion }
    if ($PSBoundParameters.ContainsKey('ForceUpdateCache')) { $invokeArgs.ForceUpdateCache = $ForceUpdateCache }
    if ($PSBoundParameters.ContainsKey('AllowRemoteDownload')) { $invokeArgs.AllowRemoteDownload = $AllowRemoteDownload }
    if ($PSBoundParameters.ContainsKey('SshTransport')) { $invokeArgs.SshTransport = $SshTransport }
    if ($PSBoundParameters.ContainsKey('UseSsl')) { $invokeArgs.UseSsl = $UseSsl }
    if ($PSBoundParameters.ContainsKey('Port')) { $invokeArgs.Port = $Port }
    if ($PSBoundParameters.ContainsKey('SshKeyPath')) { $invokeArgs.SshKeyPath = $SshKeyPath }
    if ($PSBoundParameters.ContainsKey('SkipCertificateValidation')) { $invokeArgs.SkipCertificateValidation = $SkipCertificateValidation }
    if ($PSBoundParameters.ContainsKey('AutoInstallDscResources')) { $invokeArgs.AutoInstallDscResources = $AutoInstallDscResources }
    if ($PSBoundParameters.ContainsKey('SkipResourceCheck')) { $invokeArgs.SkipResourceCheck = $SkipResourceCheck }
    return Invoke-DscHelper @invokeArgs
}

function Export-DscConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Alias('Path','ConfigPath')][string]$DscPath,
        [string]$ParametersPath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [switch]$Quiet
    )
    $invokeArgs = @{ DscPath = $DscPath; Operation = 'Export'; ComputerName = $ComputerName; Quiet = $Quiet }
    if ($ParametersPath) { $invokeArgs.ParametersPath = $ParametersPath }
    return Invoke-DscHelper @invokeArgs
}

<#
 Create secure remote session with fallback logic (SSH -> SSL -> HTTP)
 Ported from legacy module with updated branding.
#>
function New-SecureRemoteSession {
    [CmdletBinding()]
    param(
        [string]$TargetComputer,
        [PSCredential]$Credential,
        [switch]$SshTransport,
        [switch]$UseSsl,
        [Nullable[int]]$Port,
        [string]$SshKeyPath,
        [switch]$SkipCertificateValidation,
        [switch]$Quiet
    )

    if (-not $Port) {
        if ($SshTransport) { $Port = 22 }
        elseif ($UseSsl) { $Port = 5986 }
        else { $Port = 5985 }
    }

    $sessionParams = @{ ComputerName = $TargetComputer; Port = $Port }
    if ($Credential) { $sessionParams.Credential = $Credential }

    if ($SshTransport) {
        if (-not $Quiet) { Write-Host "Attempting SSH transport connection to $TargetComputer on port $Port..." -ForegroundColor Cyan }
        $sessionParams.TransportOption = @{ HostName = $TargetComputer; Port = $Port }
        if ($SshKeyPath) { $sessionParams.TransportOption.KeyFilePath = $SshKeyPath }
        try {
            $session = New-PSSession @sessionParams -ErrorAction Stop
            if (-not $Quiet) { Write-Host "SSH transport connection established successfully" -ForegroundColor Green }
            return $session
        }
        catch {
            if (-not $Quiet) {
                Write-Host "SSH transport failed: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "Falling back to SSL transport..." -ForegroundColor Yellow
            }
            $UseSsl = $true; $SshTransport = $false
        }
    }

    if ($UseSsl) {
        if (-not $Quiet) { Write-Host "Attempting SSL transport connection to $TargetComputer on port $Port..." -ForegroundColor Cyan }
        $sessionParams.UseSSL = $true
        if ($SkipCertificateValidation) { $sessionParams.SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck }
        try {
            $session = New-PSSession @sessionParams -ErrorAction Stop
            if (-not $Quiet) { Write-Host "SSL transport connection established successfully" -ForegroundColor Green }
            return $session
        }
        catch {
            if (-not $Quiet) {
                Write-Host "SSL transport failed: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "Falling back to HTTP transport..." -ForegroundColor Yellow
            }
            $UseSsl = $false
        }
    }

    if (-not $Quiet) { Write-Host "Attempting HTTP transport connection to $TargetComputer on port $Port..." -ForegroundColor Cyan }
    $sessionParams.Remove('UseSSL')
    $sessionParams.Remove('SessionOption')
    try {
        $session = New-PSSession @sessionParams -ErrorAction Stop
        if (-not $Quiet) { Write-Host "HTTP transport connection established successfully" -ForegroundColor Green }
        return $session
    }
    catch {
        throw "All transport methods failed for $TargetComputer. Last error: $($_.Exception.Message)"
    }
}

<#
 Repair incomplete DSC installation locally or remotely using cached installer
#>
function Repair-DscInstallation {
    [CmdletBinding()]
    param(
        [Alias('Computer','Target','Server')][string]$ComputerName = $env:COMPUTERNAME,
        [Alias('Cred')][PSCredential]$Credential,
        [switch]$Quiet,
        [switch]$Force
    )
    try {
        $isRemote = $ComputerName -ne $env:COMPUTERNAME
        if ($isRemote) {
            if (-not $Quiet) { Write-Host "Checking DSC installation on remote machine: $ComputerName" -ForegroundColor Yellow }
            $session = New-SecureRemoteSession -TargetComputer $ComputerName -Credential $Credential -Quiet:$Quiet
            try {
                $repairResult = Invoke-Command -Session $session -ScriptBlock {
                    param($Force,$Quiet)
                    $dscExePath = $null
                    try { $dscExePath = (Get-Command 'dsc.exe' -ErrorAction Stop).Source } catch { return @{ NeedsRepair = $false; Reason = "DSC not installed" } }
                    if (-not $dscExePath) { return @{ NeedsRepair = $false; Reason = "DSC not installed" } }
                    $installDir = Split-Path $dscExePath -Parent
                    $configFiles = @('settings.json','dsc.exe.config','*.dll','*.json')
                    $missingFiles = @()
                    foreach ($pattern in $configFiles) { if (-not (Get-ChildItem -Path $installDir -Name $pattern -ErrorAction SilentlyContinue)) { $missingFiles += $pattern } }
                    $totalFiles = (Get-ChildItem -Path $installDir -File | Measure-Object).Count
                    if ($Force -or $missingFiles.Count -gt 0 -or $totalFiles -lt 3) {
                        return @{ NeedsRepair=$true; InstallDir=$installDir; MissingFiles=$missingFiles; TotalFiles=$totalFiles; Reason='Incomplete installation detected' }
                    } else { return @{ NeedsRepair=$false; Reason='Installation appears complete' } }
                } -ArgumentList $Force,$Quiet

                if ($repairResult.NeedsRepair) {
                    if (-not $Quiet) {
                        Write-Host "Incomplete DSC installation detected on $ComputerName" -ForegroundColor Yellow
                        Write-Host "Install directory: $($repairResult.InstallDir)" -ForegroundColor Cyan
                        Write-Host "Missing files: $($repairResult.MissingFiles -join ', ')" -ForegroundColor Cyan
                        Write-Host "Repairing installation..." -ForegroundColor Yellow
                    }
                    $installerPath = Get-DscInstallerPath -Quiet:$Quiet
                    if (-not $installerPath) { throw "No cached DSC installer found. Run Update-DscInstallerCache first." }
                    $remoteTempDir = "C:\Temp\PedanticDscHelper"
                    Invoke-Command -Session $session -ScriptBlock { New-Item -Path $using:remoteTempDir -ItemType Directory -Force | Out-Null }
                    $installerFileName = Split-Path $installerPath -Leaf
                    $remoteInstallerPath = Join-Path $remoteTempDir $installerFileName
                    Copy-Item -Path $installerPath -Destination $remoteInstallerPath -ToSession $session -Force
                    $repairSuccess = Invoke-Command -Session $session -ScriptBlock {
                        param($RemoteInstallerPath,$InstallDir,$Quiet)
                        try {
                            $ext = [IO.Path]::GetExtension($RemoteInstallerPath).ToLower()
                            if ($ext -eq '.zip') {
                                if (-not $Quiet) { Write-Host 'Extracting DSC files for repair...' -ForegroundColor Cyan }
                                $extractPath = Join-Path $env:TEMP 'DscRepair'
                                Expand-Archive -Path $RemoteInstallerPath -DestinationPath $extractPath -Force
                                $dscExe = Get-ChildItem -Path $extractPath -Recurse -Name 'dsc.exe' | Select-Object -First 1
                                if ($dscExe) {
                                    $dscPath = Join-Path $extractPath $dscExe
                                    $dscDir = Split-Path $dscPath -Parent
                                    $backupDir = "$InstallDir.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
                                    if (Test-Path $InstallDir) { Copy-Item -Path $InstallDir -Destination $backupDir -Recurse -Force }
                                    Copy-Item -Path "$dscDir\*" -Destination $InstallDir -Recurse -Force
                                    Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                                    return $true
                                } else { Write-Host 'dsc.exe not found in installer' -ForegroundColor Yellow; return $false }
                            } else { Write-Host "Unsupported installer format: $ext" -ForegroundColor Yellow; return $false }
                        } catch { Write-Host "Repair failed: $($_.Exception.Message)" -ForegroundColor Yellow; return $false }
                    } -ArgumentList $remoteInstallerPath,$repairResult.InstallDir,$Quiet
                    if ($repairSuccess) { if (-not $Quiet) { Write-Host "✓ DSC installation repaired successfully on $ComputerName" -ForegroundColor Green } ; return $true }
                    else { throw "Failed to repair DSC installation on $ComputerName" }
                } else { if (-not $Quiet) { Write-Host "✓ DSC installation on $ComputerName appears complete: $($repairResult.Reason)" -ForegroundColor Green } ; return $true }
            } finally { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        }
        else {
            if (-not $Quiet) { Write-Host 'Checking local DSC installation...' -ForegroundColor Yellow }
            $dscExePath = $null
            try { $dscExePath = (Get-Command 'dsc.exe' -ErrorAction Stop).Source } catch { if (-not $Quiet) { Write-Host 'DSC executable not found in PATH' -ForegroundColor Yellow } ; return $false }
            if (-not $dscExePath) { return $false }
            $installDir = Split-Path $dscExePath -Parent
            $configFiles = @('settings.json','dsc.exe.config','*.dll','*.json')
            $missingFiles = @(); foreach ($pattern in $configFiles) { if (-not (Get-ChildItem -Path $installDir -Name $pattern -ErrorAction SilentlyContinue)) { $missingFiles += $pattern } }
            $totalFiles = (Get-ChildItem -Path $installDir -File | Measure-Object).Count
            if ($Force -or $missingFiles.Count -gt 0 -or $totalFiles -lt 3) {
                if (-not $Quiet) { Write-Host 'Repairing installation...' -ForegroundColor Yellow }
                $installerPath = Get-DscInstallerPath -Quiet:$Quiet
                if (-not $installerPath) { throw 'No cached DSC installer found. Run Update-DscInstallerCache first.' }
                try {
                    $ext = [IO.Path]::GetExtension($installerPath).ToLower()
                    if ($ext -eq '.zip') {
                        if (-not $Quiet) { Write-Host 'Extracting DSC files for repair...' -ForegroundColor Cyan }
                        $extractPath = Join-Path $env:TEMP 'DscRepair'
                        Expand-Archive -Path $installerPath -DestinationPath $extractPath -Force
                        $dscExe = Get-ChildItem -Path $extractPath -Recurse -Name 'dsc.exe' | Select-Object -First 1
                        if ($dscExe) {
                            $dscPath = Join-Path $extractPath $dscExe
                            $dscDir = Split-Path $dscPath -Parent
                            $backupDir = "$installDir.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
                            if (Test-Path $installDir) { Copy-Item -Path $installDir -Destination $backupDir -Recurse -Force }
                            Copy-Item -Path "$dscDir\*" -Destination $installDir -Recurse -Force
                            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                            if (-not $Quiet) { Write-Host '✓ Local DSC installation repaired successfully' -ForegroundColor Green }
                            return $true
                        } else { throw 'dsc.exe not found in installer' }
                    } else { throw "Unsupported installer format: $ext" }
                } catch { Write-Error "Local DSC repair failed: $($_.Exception.Message)"; throw }
            } else { if (-not $Quiet) { Write-Host '✓ Local DSC installation appears complete' -ForegroundColor Green } ; return $true }
        }
    } catch { Write-Error "DSC repair failed: $($_.Exception.Message)"; throw }
}

<#
 Install a DSC resource from local cache locally or remotely
#>
function Install-DscResourceOffline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)][string]$ResourceType,
        [Alias('Computer','Target','Server')][string]$ComputerName = $env:COMPUTERNAME,
        [Alias('Cred')][PSCredential]$Credential,
        [Alias('Version')][string]$PreferredVersion,
        [switch]$Quiet
    )
    try {
        $localResourcePath = Get-DscResourcePath -ResourceType $ResourceType -PreferredVersion $PreferredVersion -Quiet:$Quiet
        if (-not $localResourcePath) {
            if (-not $Quiet) { Write-Host "Resource $ResourceType not found in cache. Attempting to download automatically..." -ForegroundColor Yellow }
            $downloadResult = Update-DscResourceCacheInternal -Force -Quiet:$Quiet -SpecificResource $ResourceType
            if ($downloadResult) { $localResourcePath = Get-DscResourcePath -ResourceType $ResourceType -PreferredVersion $PreferredVersion -Quiet:$Quiet }
            if (-not $localResourcePath) { throw "Resource $ResourceType not available in cache and could not be downloaded automatically." }
        }

        $isRemote = $ComputerName -ne $env:COMPUTERNAME
        if ($isRemote) {
            if (-not $Quiet) { Write-Host "Installing DSC resource $ResourceType on remote machine: $ComputerName" -ForegroundColor Yellow }
            $session = New-SecureRemoteSession -TargetComputer $ComputerName -Credential $Credential -Quiet:$Quiet
            try {
                $remoteTempDir = "C:\Temp\PedanticDscHelper"
                Invoke-Command -Session $session -ScriptBlock { New-Item -Path $using:remoteTempDir -ItemType Directory -Force | Out-Null }
                $resourceFileName = Split-Path $localResourcePath -Leaf
                $remoteResourcePath = Join-Path $remoteTempDir $resourceFileName
                Copy-Item -Path $localResourcePath -Destination $remoteResourcePath -ToSession $session -Force
                $installResult = Invoke-Command -Session $session -ScriptBlock {
                    param($ResourceType,$RemoteResourcePath)
                    try {
                        $env:DSC_TRACE = '0'; $env:DSC_LOG_LEVEL = 'error'
                        Write-Host "Installing DSC resource $ResourceType from local package..." -ForegroundColor Cyan
                        $tempDir = Join-Path $env:TEMP 'DscResourceInstall'; New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                        try {
                            Expand-Archive -Path $RemoteResourcePath -DestinationPath $tempDir -Force
                            $dscExePath = (Get-Command 'dsc.exe' -ErrorAction SilentlyContinue).Source
                            $dscDir = if ($dscExePath) { Split-Path $dscExePath -Parent } else { 'C:\Program Files\Microsoft DSC' }
                            $resourceFiles = Get-ChildItem -Path $tempDir -Recurse -File
                            foreach ($file in $resourceFiles) {
                                $relativePath = $file.FullName.Substring($tempDir.Length + 1)
                                $targetPath = Join-Path $dscDir $relativePath
                                $targetDir = Split-Path $targetPath -Parent
                                if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
                                Copy-Item -Path $file.FullName -Destination $targetPath -Force
                            }
                            Write-Host "Successfully installed resource: $ResourceType" -ForegroundColor Green
                            return $true
                        } finally { if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } }
                    } catch { Write-Host "Exception installing resource $ResourceType`: $($_.Exception.Message)" -ForegroundColor Yellow; return $false }
                } -ArgumentList $ResourceType,$remoteResourcePath
                if ($installResult) { if (-not $Quiet) { Write-Host "✓ DSC resource $ResourceType installed successfully on $ComputerName" -ForegroundColor Green } ; return $true }
                else { throw "Failed to install DSC resource $ResourceType on $ComputerName" }
            } finally { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        }
        else {
            if (-not $Quiet) { Write-Host "Installing DSC resource $ResourceType locally..." -ForegroundColor Yellow }
            $installResult = & {
                try {
                    $env:DSC_TRACE = '0'; $env:DSC_LOG_LEVEL = 'error'
                    Write-Host "Installing DSC resource $ResourceType from local package..." -ForegroundColor Cyan
                    $tempDir = Join-Path $env:TEMP 'DscResourceInstall'; New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                    try {
                        Expand-Archive -Path $localResourcePath -DestinationPath $tempDir -Force
                        $dscExePath = (Get-Command 'dsc.exe' -ErrorAction SilentlyContinue).Source
                        $dscDir = if ($dscExePath) { Split-Path $dscExePath -Parent } else { 'C:\Program Files\Microsoft DSC' }
                        $resourceFiles = Get-ChildItem -Path $tempDir -Recurse -File
                        foreach ($file in $resourceFiles) {
                            $relativePath = $file.FullName.Substring($tempDir.Length + 1)
                            $targetPath = Join-Path $dscDir $relativePath
                            $targetDir = Split-Path $targetPath -Parent
                            if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
                            Copy-Item -Path $file.FullName -Destination $targetPath -Force
                        }
                        Write-Host "Successfully installed resource: $ResourceType" -ForegroundColor Green
                        return $true
                    } finally { if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } }
                } catch { Write-Host "Exception installing resource $ResourceType`: $($_.Exception.Message)" -ForegroundColor Yellow; return $false }
            }
            if ($installResult) { if (-not $Quiet) { Write-Host "✓ Local DSC resource $ResourceType installed successfully" -ForegroundColor Green } ; return $true }
            else { throw "Failed to install DSC resource $ResourceType locally" }
        }
    } catch { Write-Error "DSC resource installation failed: $($_.Exception.Message)"; throw }
}

# Back-compat shim; prefer Test-DscResourceAvailability (approved verb)
function Ensure-DscResourcesAvailable {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs','', Justification='Backward compatibility; use Test-DscResourceAvailability instead.')]
    [CmdletBinding()]
    param(
        [string[]]$ResourceTypes,
        [switch]$Quiet,
        [switch]$Force
    )
    Write-Warning "Ensure-DscResourcesAvailable is deprecated. Use Test-DscResourceAvailability instead."
    Test-DscResourceAvailability -ResourceTypes $ResourceTypes -Quiet:$Quiet -Force:$Force
}

# Export the functions
Export-ModuleMember -Function 'Invoke-DscHelper', 'Validate-DscConfiguration', 'Set-DscConfiguration', 'Test-DscConfiguration', 'Export-DscConfiguration', 'Get-DscInstallerCache', 'Update-DscInstallerCache', 'Remove-DscInstallerCache', 'Get-DscInstallerPath', 'Get-Head', 'Get-Tail', 'New-SecureRemoteSession', 'Repair-DscInstallation', 'Get-DscResourceCache', 'Update-DscResourceCache', 'Remove-DscResourceCache', 'Get-DscResourcePath', 'Install-DscResourceOffline', 'Ensure-DscResourcesAvailable', 'Get-MappedResourceInfo'

# Initialize caches on module import
try {
    Write-Host "Initializing DSC module caches..." -ForegroundColor Cyan
    
    # Initialize installer cache
    Initialize-InstallerCache
    
    # Initialize resource cache  
    Initialize-ResourceCache
    
    # Try to update installer cache if needed (but don't fail if it doesn't work)
    try {
        if (Test-UpdateCheckNeeded) {
            Write-Host "Updating DSC installer cache..." -ForegroundColor Yellow
            Update-DscInstallerCacheInternal -Quiet
        }
    }
    catch {
        Write-Warning "Failed to update DSC installer cache on import: $($_.Exception.Message)"
        Write-Warning "You can manually run Update-DscInstallerCache to download installers."
    }
    
    Write-Host "DSC module initialized successfully." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to initialize DSC module caches: $($_.Exception.Message)"
    Write-Warning "Some DSC operations may not work correctly. Please check the module configuration."
}
