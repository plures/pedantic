[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Invoke-Command script blocks declare their values with param() and receive them through ArgumentList.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'StartupMode',
    Justification = 'Consumed by the module import readiness function after module initialization.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'StartupOptions',
    Justification = 'Consumed by the module import readiness function after module initialization.'
)]
param(
    [ValidateSet('Notify', 'Quiet', 'Prompt', 'Initialize')]
    [string]$StartupMode = 'Notify',

    [hashtable]$StartupOptions = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$minimumPowerShellVersion = [version]'5.1'
if ($PSVersionTable.PSVersion -lt $minimumPowerShellVersion) {
    throw "VMHelper requires PowerShell $minimumPowerShellVersion or later. Detected $($PSVersionTable.PSVersion)."
}
$powerShellEdition = if ($PSVersionTable.ContainsKey('PSEdition')) {
    [string]$PSVersionTable.PSEdition
} else {
    'Desktop'
}
$runtimeMode = if ($PSVersionTable.PSVersion.Major -ge 7) {
    'PowerShell7'
} else {
    'WindowsPowerShell'
}
$script:VMHelperRuntime = [pscustomobject]@{
    PSTypeName = 'VMHelper.Runtime'
    PowerShellVersion = $PSVersionTable.PSVersion
    PowerShellEdition = $powerShellEdition
    RuntimeMode = $runtimeMode
    CompatibilityMode = $runtimeMode -eq 'WindowsPowerShell'
    ProcessPath = (Get-Process -Id $PID).Path
    RemotingEndpoint = 'Microsoft.PowerShell'
}
Write-Verbose "VMHelper loaded in $runtimeMode mode using PowerShell $($PSVersionTable.PSVersion)."

$sharedModulePaths = @(
    (Join-Path $PSScriptRoot '..\DTMS.Runway\DTMS.Runway.psd1')
    (Join-Path $PSScriptRoot '..\DTMS.Transfer\DTMS.Transfer.psd1')
    (Join-Path $PSScriptRoot '..\DTMS.Runway.Dfs\DTMS.Runway.Dfs.psd1')
)
foreach ($sharedModulePath in $sharedModulePaths) {
    $sharedModuleName = [IO.Path]::GetFileNameWithoutExtension($sharedModulePath)
    if (-not (Get-Module -Name $sharedModuleName) -and
        (Test-Path -LiteralPath $sharedModulePath -PathType Leaf)) {
        Import-Module $sharedModulePath -Force -ErrorAction Stop
    }
}

function Get-VMHelperDefaultDomainName {
    $candidates = @(
        $env:USERDNSDOMAIN
        try {
            [DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
        } catch {
            Write-Verbose "Current-domain detection failed: $($_.Exception.Message)"
        }
    )
    @($candidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1)
}

function Read-VMHelperEnvironmentFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $values = @{}
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }
        $separatorIndex = $trimmed.IndexOf('=')
        if ($separatorIndex -lt 1) {
            throw "Invalid .env entry in '$Path': $line"
        }
        $name = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }
    $values
}

function Test-VMHelperPathAvailability {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('Any', 'Container', 'Leaf')]
        [string]$PathType = 'Any'
    )

    try {
        $parameters = @{
            LiteralPath = $Path
            ErrorAction = 'Stop'
        }
        if ($PathType -ne 'Any') {
            $parameters.PathType = $PathType
        }
        [bool](Test-Path @parameters)
    } catch {
        Write-Verbose "Path availability check failed for '$Path': $($_.Exception.Message)"
        $false
    }
}

function Resolve-VMHelperRegistryConfiguration {
    $domainNames = @(Get-VMHelperDefaultDomainName)
    $domainName = if ($domainNames.Count -gt 0) { [string]$domainNames[0] } else { $null }
    $defaultServiceRoot = if ($domainName) {
        "\\$domainName\Services\DTMS\VMM"
    } else {
        $null
    }
    $environmentValues = @{
        VMHELPER_REGISTRY_NAMESPACE = $env:VMHELPER_REGISTRY_NAMESPACE
        VMHELPER_REGISTRY_SERVERS = $env:VMHELPER_REGISTRY_SERVERS
        VMHELPER_REGISTRY_WRITER_PRINCIPAL = $env:VMHELPER_REGISTRY_WRITER_PRINCIPAL
        VMHELPER_REGISTRY_READER_PRINCIPAL = $env:VMHELPER_REGISTRY_READER_PRINCIPAL
        VMHELPER_REGISTRY_RETENTION_COUNT = $env:VMHELPER_REGISTRY_RETENTION_COUNT
        VMHELPER_REGISTRY_SHARE_NAME = $env:VMHELPER_REGISTRY_SHARE_NAME
        VMHELPER_REGISTRY_LOCAL_PATH = $env:VMHELPER_REGISTRY_LOCAL_PATH
        VMHELPER_REGISTRY_REPLICATION_GROUP = $env:VMHELPER_REGISTRY_REPLICATION_GROUP
        VMHELPER_REGISTRY_PROGRESS_PERCENT = $env:VMHELPER_REGISTRY_PROGRESS_PERCENT
        VMHELPER_REGISTRY_PROGRESS_MINUTES = $env:VMHELPER_REGISTRY_PROGRESS_MINUTES
    }
    $hasEnvironmentConfiguration = @($environmentValues.Values |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
    $defaultNamespacePath = if ($defaultServiceRoot) {
        Join-Path $defaultServiceRoot 'Transfers'
    } else {
        $null
    }
    $environmentFile = if ($defaultNamespacePath) {
        Join-Path $defaultNamespacePath '.env'
    } else {
        $null
    }
    $fileValues = @{}
    if (-not $hasEnvironmentConfiguration -and
        $environmentFile -and
        (Test-VMHelperPathAvailability -Path $environmentFile -PathType Leaf)) {
        $fileValues = Read-VMHelperEnvironmentFile -Path $environmentFile
    }
    $getValue = {
        param($Name, $DefaultValue)
        if (-not [string]::IsNullOrWhiteSpace($environmentValues[$Name])) {
            return [string]$environmentValues[$Name]
        }
        if ($fileValues.ContainsKey($Name) -and
            -not [string]::IsNullOrWhiteSpace($fileValues[$Name])) {
            return [string]$fileValues[$Name]
        }
        $DefaultValue
    }
    $namespacePath = & $getValue 'VMHELPER_REGISTRY_NAMESPACE' (
        $defaultNamespacePath
    )
    $retentionText = & $getValue 'VMHELPER_REGISTRY_RETENTION_COUNT' '90'
    $retentionCount = 0
    if (-not [int]::TryParse($retentionText, [ref]$retentionCount) -or $retentionCount -lt 1) {
        throw "VMHELPER_REGISTRY_RETENTION_COUNT must be a positive integer; received '$retentionText'."
    }
    $progressPercentText = & $getValue 'VMHELPER_REGISTRY_PROGRESS_PERCENT' '5'
    $progressPercent = 0
    if (-not [int]::TryParse($progressPercentText, [ref]$progressPercent) -or
        $progressPercent -lt 1 -or $progressPercent -gt 100) {
        throw "VMHELPER_REGISTRY_PROGRESS_PERCENT must be between 1 and 100; received '$progressPercentText'."
    }
    $progressMinutesText = & $getValue 'VMHELPER_REGISTRY_PROGRESS_MINUTES' '15'
    $progressMinutes = 0
    if (-not [int]::TryParse($progressMinutesText, [ref]$progressMinutes) -or
        $progressMinutes -lt 1) {
        throw "VMHELPER_REGISTRY_PROGRESS_MINUTES must be positive; received '$progressMinutesText'."
    }
    $serverText = & $getValue 'VMHELPER_REGISTRY_SERVERS' ''
    $servers = @($serverText -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ })
    $federatedServers = @($env:VMHELPER_FEDERATED_UTILITY_SERVERS -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ })
    $source = if ($hasEnvironmentConfiguration) {
        'Environment'
    } elseif ($fileValues.Count -gt 0) {
        'EnvironmentFile'
    } else {
        'Default'
    }
    [pscustomobject]@{
        PSTypeName = 'VMHelper.RegistryConfiguration'
        Enabled = [bool]($namespacePath -and
            (Test-VMHelperPathAvailability -Path $namespacePath -PathType Container))
        DomainName = $domainName
        ServiceRoot = $defaultServiceRoot
        EnvironmentFile = $environmentFile
        NamespacePath = $namespacePath
        UtilityServers = $servers
        FederatedUtilityServers = $federatedServers
        Mode = if ($federatedServers.Count -gt 0) {
            'FederatedPull'
        } elseif ($namespacePath -and
            (Test-VMHelperPathAvailability -Path $namespacePath -PathType Container)) {
            'Dfs'
        } else {
            'LocalOnly'
        }
        WriterPrincipal = & $getValue 'VMHELPER_REGISTRY_WRITER_PRINCIPAL' $null
        ReaderPrincipal = & $getValue 'VMHELPER_REGISTRY_READER_PRINCIPAL' $null
        RetentionCount = $retentionCount
        ShareName = & $getValue 'VMHELPER_REGISTRY_SHARE_NAME' 'DTMSVMMTransfers$'
        LocalPath = & $getValue 'VMHELPER_REGISTRY_LOCAL_PATH' 'C:\ProgramData\DTMS\VMM\Transfers'
        ReplicationGroup = & $getValue 'VMHELPER_REGISTRY_REPLICATION_GROUP' 'DTMS-VMM-Transfers'
        ProgressPercent = $progressPercent
        ProgressMinutes = $progressMinutes
        Source = $source
        ConfigurationPresent = $hasEnvironmentConfiguration -or
            $fileValues.Count -gt 0 -or
            $federatedServers.Count -gt 0
    }
}

function Get-VMHelperRegistryConfiguration {
    <#
    .SYNOPSIS
    Returns the resolved VMHelper distributed registry configuration.
    .DESCRIPTION
    Shows environment-variable or service-folder .env settings, namespace
    availability, utility servers, security principals, and retention count.
    #>
    [CmdletBinding()]
    param()

    $script:VMHelperRegistryConfiguration.PSObject.Copy()
}

function Initialize-VMResourceTransferRegistry {
    <#
    .SYNOPSIS
    Creates the distributed DFS-R registry used by VMHelper transfers.
    .DESCRIPTION
    Creates a registry share on each utility server, a multi-target DFS folder
    at \\<domain>\Services\DTMS\VMM\Transfers, a fully connected DFS-R group,
    and a replicated .env configuration file.
    .PARAMETER UtilityServerPattern
    Regular expression used to discover enabled AD computer accounts. Matching
    hosts are displayed and require confirmation through ShouldProcess.
    .PARAMETER Credential
    Optional administrator credential used for remote utility-server setup.
    The caller still needs permission to manage the domain DFS namespace and
    DFS-R configuration.
    .EXAMPLE
    Initialize-VMResourceTransferRegistry `
        -UtilityServerPattern '^(?:BN1|SN5|PHX23|PHX21)ISUTIL\d{2,3}$' `
        -WriterPrincipal 'USME\VMHelper-Registry-Writers'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$DomainName,

        [string[]]$UtilityServer,

        [string]$UtilityServerPattern,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WriterPrincipal,

        [ValidateNotNullOrEmpty()]
        [string]$ReaderPrincipal,

        [ValidateNotNullOrEmpty()]
        [string]$LocalPath = 'C:\ProgramData\DTMS\VMM\Transfers',

        [ValidateNotNullOrEmpty()]
        [string]$ShareName = 'DTMSVMMTransfers$',

        [ValidateNotNullOrEmpty()]
        [string]$ReplicationGroup = 'DTMS-VMM-Transfers',

        [ValidateRange(1, 10000)]
        [int]$RetentionCount = 90,

        [ValidateRange(1, 100)]
        [int]$ProgressPercent = 5,

        [ValidateRange(1, 1440)]
        [int]$ProgressMinutes = 15,

        [pscredential]$Credential
    )

    $activity = Start-DTMSActivity `
        -Name 'VM transfer DFS registry setup' `
        -Intent 'Discover utility servers and provision shares, namespace, and replication'
    if ($UtilityServer -and $UtilityServerPattern) {
        throw 'Specify either literal -UtilityServer names or -UtilityServerPattern, not both.'
    }
    $regexLikeUtilityServers = @($UtilityServer | Where-Object {
        $_ -match '[\^\$\(\)\[\]\{\}\|\+\*?\\]'
    })
    if ($regexLikeUtilityServers.Count -gt 0) {
        throw (
            "-UtilityServer accepts literal computer names. " +
            "Use -UtilityServerPattern for regular expressions such as " +
            "'$($regexLikeUtilityServers[0])'."
        )
    }
    if (-not $DomainName) {
        $detectedDomains = @(Get-VMHelperDefaultDomainName)
        if ($detectedDomains.Count -eq 0) {
            throw 'Cannot determine the domain. Specify -DomainName.'
        }
        $DomainName = [string]$detectedDomains[0]
    }
    if ($UtilityServerPattern) {
        try {
            Import-ActiveDirectoryModule
            $regex = [regex]::new(
                $UtilityServerPattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [TimeSpan]::FromSeconds(5)
            )
            $UtilityServer = @(Get-ADComputer `
                -Filter { Enabled -eq $true } `
                -Properties DNSHostName `
                -ErrorAction Stop |
                Where-Object { $regex.IsMatch($_.Name) } |
                ForEach-Object {
                    if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name }
                } |
                Sort-Object -Unique)
        } catch {
            throw "Utility-server discovery failed: $($_.Exception.Message)"
        }
    }
    $UtilityServer = @($UtilityServer |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
    if ($UtilityServer.Count -eq 0) {
        throw 'Specify at least one UtilityServer or a UtilityServerPattern that finds one.'
    }
    if (-not $ReaderPrincipal) {
        $ReaderPrincipal = $WriterPrincipal
    }
    $namespacePath = "\\$DomainName\Services\DTMS\VMM\Transfers"
    $serverSummary = $UtilityServer -join ', '
    Update-DTMSActivity `
        -Activity $activity `
        -Status "Resolved utility servers: $serverSummary." `
        -ForceHeartbeat
    Write-Information "VMHelper registry utility servers: $serverSummary" -InformationAction Continue
    if (-not $PSCmdlet.ShouldProcess(
        $namespacePath,
        "create distributed registry on $serverSummary for writer '$WriterPrincipal'"
    )) {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'Registry setup was not started.'
        return
    }

    if (Get-Command Initialize-DurableOperationDfsRegistry -ErrorAction SilentlyContinue) {
        $registryParameters = @{
            NamespacePath = $namespacePath
            UtilityServer = $UtilityServer
            WriterPrincipal = $WriterPrincipal
            ReaderPrincipal = $ReaderPrincipal
            LocalPath = $LocalPath
            ShareName = $ShareName
            ReplicationGroup = $ReplicationGroup
            RetentionCount = $RetentionCount
            Confirm = $false
        }
        if ($Credential) {
            $registryParameters.Credential = $Credential
        }
        Initialize-DurableOperationDfsRegistry @registryParameters | Out-Null
        $directEnvironmentPath = "\\$($UtilityServer[0])\$ShareName\.env"
        @(
            "VMHELPER_REGISTRY_NAMESPACE=$namespacePath"
            "VMHELPER_REGISTRY_SERVERS=$($UtilityServer -join ',')"
            "VMHELPER_REGISTRY_WRITER_PRINCIPAL=$WriterPrincipal"
            "VMHELPER_REGISTRY_READER_PRINCIPAL=$ReaderPrincipal"
            "VMHELPER_REGISTRY_RETENTION_COUNT=$RetentionCount"
            "VMHELPER_REGISTRY_SHARE_NAME=$ShareName"
            "VMHELPER_REGISTRY_LOCAL_PATH=$LocalPath"
            "VMHELPER_REGISTRY_REPLICATION_GROUP=$ReplicationGroup"
            "VMHELPER_REGISTRY_PROGRESS_PERCENT=$ProgressPercent"
            "VMHELPER_REGISTRY_PROGRESS_MINUTES=$ProgressMinutes"
        ) | Set-Content -LiteralPath $directEnvironmentPath -Encoding UTF8
        $env:VMHELPER_REGISTRY_NAMESPACE = $namespacePath
        $env:VMHELPER_REGISTRY_SERVERS = $UtilityServer -join ','
        $env:VMHELPER_REGISTRY_WRITER_PRINCIPAL = $WriterPrincipal
        $env:VMHELPER_REGISTRY_READER_PRINCIPAL = $ReaderPrincipal
        $env:VMHELPER_REGISTRY_RETENTION_COUNT = [string]$RetentionCount
        $script:VMHelperRegistryConfiguration = Resolve-VMHelperRegistryConfiguration
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'Distributed VM transfer registry is configured.'
        return $script:VMHelperRegistryConfiguration.PSObject.Copy()
    }

    foreach ($server in $UtilityServer) {
        $preflightParameters = @{
            ComputerName = $server
            ErrorAction = 'Stop'
            ScriptBlock = {
                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = [Security.Principal.WindowsPrincipal]::new($identity)
                if (-not $principal.IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator
                )) {
                    throw (
                        "Remote identity '$($identity.Name)' does not have an " +
                        'elevated local Administrators token.'
                    )
                }
                Get-Command New-SmbShare -ErrorAction Stop | Out-Null
            }
        }
        if ($Credential) {
            $preflightParameters.Credential = $Credential
        }
        try {
            Invoke-Command @preflightParameters
        } catch {
            throw "Registry provisioning preflight failed on '$server': $($_.Exception.Message)"
        }
    }
    foreach ($server in $UtilityServer) {
        $invokeParameters = @{
            ComputerName = $server
            ArgumentList = @(
                $LocalPath,
                $ShareName,
                $WriterPrincipal,
                $ReaderPrincipal
            )
            ErrorAction = 'Stop'
            ScriptBlock = {
            param($Path, $Share, $Writer, $Reader)
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $acl = Get-Acl -LiteralPath $Path
            $accessRules = @(
                [Security.AccessControl.FileSystemAccessRule]::new(
                    $Writer,
                    'Modify',
                    'ContainerInherit,ObjectInherit',
                    'None',
                    'Allow'
                )
            )
            if ($Reader -ine $Writer) {
                $accessRules += [Security.AccessControl.FileSystemAccessRule]::new(
                    $Reader,
                    'ReadAndExecute',
                    'ContainerInherit,ObjectInherit',
                    'None',
                    'Allow'
                )
            }
            foreach ($access in $accessRules) {
                $acl.SetAccessRule($access)
            }
            Set-Acl -LiteralPath $Path -AclObject $acl
            $existingShare = Get-SmbShare -Name $Share -ErrorAction SilentlyContinue
            if ($existingShare) {
                if ($existingShare.Path -ine $Path) {
                    throw "SMB share '$Share' already points to '$($existingShare.Path)', not '$Path'."
                }
            } else {
                $shareParameters = @{
                    Name = $Share
                    Path = $Path
                    FullAccess = 'BUILTIN\Administrators'
                    ChangeAccess = $Writer
                    FolderEnumerationMode = 'AccessBased'
                    ErrorAction = 'Stop'
                }
                if ($Reader -ine $Writer) {
                    $shareParameters.ReadAccess = $Reader
                }
                New-SmbShare @shareParameters | Out-Null
            }
        }
        }
        if ($Credential) {
            $invokeParameters.Credential = $Credential
        }
        Invoke-Command @invokeParameters
    }

    Import-Module DFSN -ErrorAction Stop
    $firstTarget = "\\$($UtilityServer[0])\$ShareName"
    $namespaceFolder = Get-DfsnFolder -Path $namespacePath -ErrorAction SilentlyContinue
    if (-not $namespaceFolder) {
        New-DfsnFolder `
            -Path $namespacePath `
            -TargetPath $firstTarget `
            -Description 'DTMS VMHelper distributed transfer event registry' `
            -EnableTargetFailback $true `
            -ErrorAction Stop | Out-Null
    }
    $existingTargets = @(Get-DfsnFolderTarget -Path $namespacePath -ErrorAction Stop |
        Select-Object -ExpandProperty TargetPath)
    foreach ($server in $UtilityServer) {
        $targetPath = "\\$server\$ShareName"
        if ($targetPath -notin $existingTargets) {
            New-DfsnFolderTarget `
                -Path $namespacePath `
                -TargetPath $targetPath `
                -ErrorAction Stop | Out-Null
        }
    }

    Import-Module DFSR -ErrorAction Stop
    if (-not (Get-DfsReplicationGroup `
        -GroupName $ReplicationGroup `
        -DomainName $DomainName `
        -ErrorAction SilentlyContinue)) {
        New-DfsReplicationGroup `
            -GroupName $ReplicationGroup `
            -DomainName $DomainName `
            -Description 'DTMS VMHelper append-only transfer event registry' `
            -ErrorAction Stop | Out-Null
    }
    $existingMembers = @(Get-DfsrMember `
        -GroupName $ReplicationGroup `
        -DomainName $DomainName `
        -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ComputerName)
    foreach ($server in $UtilityServer) {
        if (($server -split '\.')[0] -notin @($existingMembers | ForEach-Object { ($_ -split '\.')[0] })) {
            Add-DfsrMember `
                -GroupName $ReplicationGroup `
                -ComputerName $server `
                -DomainName $DomainName `
                -ErrorAction Stop | Out-Null
        }
    }
    $folderName = 'Transfers'
    if (-not (Get-DfsReplicatedFolder `
        -GroupName $ReplicationGroup `
        -FolderName $folderName `
        -DomainName $DomainName `
        -ErrorAction SilentlyContinue)) {
        New-DfsReplicatedFolder `
            -GroupName $ReplicationGroup `
            -FolderName $folderName `
            -DfsnPath $namespacePath `
            -FileNameToExclude @('*.tmp', '*.partial') `
            -DomainName $DomainName `
            -ErrorAction Stop | Out-Null
    }
    for ($sourceIndex = 0; $sourceIndex -lt $UtilityServer.Count; $sourceIndex++) {
        for ($destinationIndex = $sourceIndex + 1;
            $destinationIndex -lt $UtilityServer.Count;
            $destinationIndex++) {
            $sourceServer = $UtilityServer[$sourceIndex]
            $destinationServer = $UtilityServer[$destinationIndex]
            $connection = Get-DfsrConnection `
                -GroupName $ReplicationGroup `
                -SourceComputerName $sourceServer `
                -DestinationComputerName $destinationServer `
                -DomainName $DomainName `
                -ErrorAction SilentlyContinue
            if (-not $connection) {
                Add-DfsrConnection `
                    -GroupName $ReplicationGroup `
                    -SourceComputerName $sourceServer `
                    -DestinationComputerName $destinationServer `
                    -DomainName $DomainName `
                    -ErrorAction Stop | Out-Null
            }
        }
    }
    for ($index = 0; $index -lt $UtilityServer.Count; $index++) {
        $membershipParameters = @{
            GroupName = $ReplicationGroup
            FolderName = $folderName
            ComputerName = $UtilityServer[$index]
            ContentPath = $LocalPath
            DfsnPath = $namespacePath
            DomainName = $DomainName
            Force = $true
            ErrorAction = 'Stop'
        }
        if ($index -eq 0) {
            $membershipParameters.PrimaryMember = $true
        }
        Set-DfsrMembership @membershipParameters | Out-Null
    }

    $environmentLines = @(
        "VMHELPER_REGISTRY_NAMESPACE=$namespacePath"
        "VMHELPER_REGISTRY_SERVERS=$($UtilityServer -join ',')"
        "VMHELPER_REGISTRY_WRITER_PRINCIPAL=$WriterPrincipal"
        "VMHELPER_REGISTRY_READER_PRINCIPAL=$ReaderPrincipal"
        "VMHELPER_REGISTRY_RETENTION_COUNT=$RetentionCount"
        "VMHELPER_REGISTRY_SHARE_NAME=$ShareName"
        "VMHELPER_REGISTRY_LOCAL_PATH=$LocalPath"
        "VMHELPER_REGISTRY_REPLICATION_GROUP=$ReplicationGroup"
        "VMHELPER_REGISTRY_PROGRESS_PERCENT=$ProgressPercent"
        "VMHELPER_REGISTRY_PROGRESS_MINUTES=$ProgressMinutes"
    )
    $directEnvironmentPath = "\\$($UtilityServer[0])\$ShareName\.env"
    $environmentLines | Set-Content -LiteralPath $directEnvironmentPath -Encoding UTF8
    $env:VMHELPER_REGISTRY_NAMESPACE = $namespacePath
    $env:VMHELPER_REGISTRY_SERVERS = $UtilityServer -join ','
    $env:VMHELPER_REGISTRY_WRITER_PRINCIPAL = $WriterPrincipal
    $env:VMHELPER_REGISTRY_READER_PRINCIPAL = $ReaderPrincipal
    $env:VMHELPER_REGISTRY_RETENTION_COUNT = [string]$RetentionCount
    $env:VMHELPER_REGISTRY_SHARE_NAME = $ShareName
    $env:VMHELPER_REGISTRY_LOCAL_PATH = $LocalPath
    $env:VMHELPER_REGISTRY_REPLICATION_GROUP = $ReplicationGroup
    $env:VMHELPER_REGISTRY_PROGRESS_PERCENT = [string]$ProgressPercent
    $env:VMHELPER_REGISTRY_PROGRESS_MINUTES = [string]$ProgressMinutes
    $script:VMHelperRegistryConfiguration = Resolve-VMHelperRegistryConfiguration
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'Distributed VM transfer registry is configured.'
    $script:VMHelperRegistryConfiguration.PSObject.Copy()
}

function Initialize-VMResourceTransferFederation {
    <#
    .SYNOPSIS
    Configures independent utility-server indexes without DFS or DFS-R.
    .DESCRIPTION
    Installs a scheduled collector on every selected utility server. Each
    collector runs as a gMSA, pulls authoritative transfer state from every
    registered target host, retains active work plus the newest completed
    records, and stores an independent local index.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string[]]$UtilityServer,

        [string]$UtilityServerPattern,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TargetHostName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CollectorAccount,

        [ValidateRange(1, 1440)]
        [int]$IntervalMinutes = 5,

        [ValidateRange(1, 10000)]
        [int]$RetentionCount = 90,

        [ValidateNotNullOrEmpty()]
        [string]$LocalPath = 'C:\ProgramData\DTMS\VMM\FederatedTransfers',

        [ValidateNotNullOrEmpty()]
        [string]$DurableTransferRoot = 'C:\ProgramData\VMHelper\Transfers',

        [pscredential]$Credential
    )

    $activity = Start-DTMSActivity `
        -Name 'Federated transfer registry setup' `
        -Intent 'Configure independent utility-server collectors and indexes'
    if ($UtilityServer -and $UtilityServerPattern) {
        throw 'Specify either literal -UtilityServer names or -UtilityServerPattern, not both.'
    }
    if ($CollectorAccount -notmatch '\$$') {
        throw "CollectorAccount '$CollectorAccount' must be a gMSA ending in '$'."
    }
    if ($UtilityServerPattern) {
        Import-ActiveDirectoryModule
        $regex = [regex]::new(
            $UtilityServerPattern,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase,
            [TimeSpan]::FromSeconds(5)
        )
        $UtilityServer = @(Get-ADComputer `
            -Filter { Enabled -eq $true } `
            -Properties DNSHostName `
            -ErrorAction Stop |
            Where-Object { $regex.IsMatch($_.Name) } |
            ForEach-Object {
                if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name }
            } |
            Sort-Object -Unique)
    }
    $UtilityServer = @($UtilityServer |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
    $TargetHostName = @($TargetHostName |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
    if ($UtilityServer.Count -eq 0) {
        throw 'No utility servers were specified or discovered.'
    }
    if ($TargetHostName.Count -eq 0) {
        throw 'At least one target host is required.'
    }
    if (-not $PSCmdlet.ShouldProcess(
        ($UtilityServer -join ', '),
        "configure federated transfer collectors as '$CollectorAccount'"
    )) {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'Federated setup was not started.'
        return
    }

    $collectorPath = Join-Path $PSScriptRoot 'Invoke-VMResourceTransferFederatedCollector.ps1'
    $collectorContent = Get-Content -LiteralPath $collectorPath -Raw -ErrorAction Stop
    $configuredCount = 0
    $results = foreach ($server in $UtilityServer) {
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Configuring collector on $server." `
            -PercentComplete (
                ($configuredCount / [math]::Max(1, $UtilityServer.Count)) * 100
            ) `
            -ForceHeartbeat
        $invokeParameters = @{
            ComputerName = $server
            ArgumentList = @(
                $collectorContent,
                $TargetHostName,
                $CollectorAccount,
                $IntervalMinutes,
                $RetentionCount,
                $LocalPath,
                $DurableTransferRoot
            )
            ErrorAction = 'Stop'
            ScriptBlock = {
                param(
                    $CollectorContent,
                    $Targets,
                    $ServiceAccount,
                    $Minutes,
                    $KeepCount,
                    $Root,
                    $TransferRoot
                )

                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = [Security.Principal.WindowsPrincipal]::new($identity)
                if (-not $principal.IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator
                )) {
                    throw "Identity '$($identity.Name)' is not an elevated local administrator."
                }

                Import-Module ActiveDirectory -ErrorAction Stop
                $serviceAccountName = ($ServiceAccount -split '\\')[-1].TrimEnd('$')
                if (-not (Test-ADServiceAccount -Identity $serviceAccountName)) {
                    Install-ADServiceAccount -Identity $serviceAccountName -ErrorAction Stop
                }
                if (-not (Test-ADServiceAccount -Identity $serviceAccountName)) {
                    throw "gMSA '$ServiceAccount' is not usable on '$env:COMPUTERNAME'."
                }

                $indexRoot = Join-Path $Root 'Index'
                New-Item -Path $Root, $indexRoot -ItemType Directory -Force | Out-Null
                $acl = Get-Acl -LiteralPath $Root
                $acl.SetAccessRule(
                    [Security.AccessControl.FileSystemAccessRule]::new(
                        $ServiceAccount,
                        'Modify',
                        'ContainerInherit,ObjectInherit',
                        'None',
                        'Allow'
                    )
                )
                Set-Acl -LiteralPath $Root -AclObject $acl

                $scriptPath = Join-Path $Root 'Collect.ps1'
                [IO.File]::WriteAllText(
                    $scriptPath,
                    $CollectorContent,
                    [Text.UTF8Encoding]::new($false)
                )
                $configurationPath = Join-Path $Root 'Configuration.json'
                $existingTargets = @()
                if (Test-Path -LiteralPath $configurationPath -PathType Leaf) {
                    $existingConfiguration = Get-Content `
                        -LiteralPath $configurationPath `
                        -Raw | ConvertFrom-Json
                    $existingTargets = @($existingConfiguration.TargetHostName)
                }
                $configuration = [ordered]@{
                    SchemaVersion = 1
                    UtilityServer = $env:COMPUTERNAME
                    TargetHostName = @($existingTargets + $Targets | Sort-Object -Unique)
                    IndexRoot = $indexRoot
                    DurableTransferRoot = $TransferRoot
                    RetentionCount = $KeepCount
                    CollectorAccount = $ServiceAccount
                    IntervalMinutes = $Minutes
                    UpdatedUtc = [DateTime]::UtcNow.ToString('o')
                }
                $temporaryPath = "$configurationPath.tmp"
                $configuration | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath $temporaryPath -Encoding UTF8
                Move-Item $temporaryPath $configurationPath -Force

                $powerShell = Get-Command pwsh.exe -ErrorAction SilentlyContinue
                if (-not $powerShell) {
                    $powerShell = Get-Command powershell.exe -ErrorAction Stop
                }
                $action = New-ScheduledTaskAction `
                    -Execute $powerShell.Source `
                    -Argument (
                        '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
                        "-File `"$scriptPath`" -ConfigurationPath `"$configurationPath`""
                    )
                $trigger = New-ScheduledTaskTrigger `
                    -Once `
                    -At ([DateTime]::Now.AddMinutes(1)) `
                    -RepetitionInterval ([TimeSpan]::FromMinutes($Minutes)) `
                    -RepetitionDuration ([TimeSpan]::FromDays(3650))
                $taskPrincipal = New-ScheduledTaskPrincipal `
                    -UserId $ServiceAccount `
                    -LogonType ServiceAccount `
                    -RunLevel Highest
                $settings = New-ScheduledTaskSettingsSet `
                    -StartWhenAvailable `
                    -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit ([TimeSpan]::FromMinutes(
                        [math]::Max(30, $Minutes * 4)
                    ))
                $taskName = 'DTMS-VMTransfer-FederatedCollector'
                Register-ScheduledTask `
                    -TaskName $taskName `
                    -Action $action `
                    -Trigger $trigger `
                    -Principal $taskPrincipal `
                    -Settings $settings `
                    -Description 'Pulls authoritative DTMS VM transfer state into an independent local index.' `
                    -Force | Out-Null
                Start-ScheduledTask -TaskName $taskName

                [pscustomobject]@{
                    UtilityServer = $env:COMPUTERNAME
                    CollectorAccount = $ServiceAccount
                    TargetHostCount = @($configuration.TargetHostName).Count
                    IntervalMinutes = $Minutes
                    RetentionCount = $KeepCount
                    IndexRoot = $indexRoot
                    TaskName = $taskName
                }
            }
        }
        if ($Credential) {
            $invokeParameters.Credential = $Credential
        }
        try {
            Invoke-Command @invokeParameters
            $configuredCount++
        } catch {
            throw "Federated collector setup failed on '$server': $($_.Exception.Message)"
        }
    }
    $env:VMHELPER_FEDERATED_UTILITY_SERVERS = $UtilityServer -join ','
    [Environment]::SetEnvironmentVariable(
        'VMHELPER_FEDERATED_UTILITY_SERVERS',
        ($UtilityServer -join ','),
        [EnvironmentVariableTarget]::User
    )
    $script:VMHelperRegistryConfiguration = Resolve-VMHelperRegistryConfiguration
    Complete-DTMSActivity `
        -Activity $activity `
        -Status "Configured $($UtilityServer.Count) independent collector(s)."
    $results
}

function Sync-VMResourceTransferFederation {
    <#
    .SYNOPSIS
    Starts an immediate collection cycle on each federated utility server.
    .DESCRIPTION
    Starts the installed collector task on every selected utility server and
    returns the current scheduled-task execution information.
    #>
    [CmdletBinding()]
    param(
        [string[]]$UtilityServer = @(
            $env:VMHELPER_FEDERATED_UTILITY_SERVERS -split ',' |
                Where-Object { $_ }
        ),

        [pscredential]$Credential
    )

    if (@($UtilityServer).Count -eq 0) {
        throw 'Specify UtilityServer or set VMHELPER_FEDERATED_UTILITY_SERVERS.'
    }
    $activity = Start-DTMSActivity `
        -Name 'VM transfer federation synchronization' `
        -Intent 'Start an immediate collection cycle on every utility server' `
        -Target ($UtilityServer -join ', ')
    try {
        foreach ($server in @($UtilityServer | Sort-Object -Unique)) {
            Update-DTMSActivity `
                -Activity $activity `
                -Status "Starting the federated collector on $server." `
                -ForceHeartbeat
            $parameters = @{
                ComputerName = $server
                ArgumentList = 'DTMS-VMTransfer-FederatedCollector'
                ErrorAction = 'Stop'
                ScriptBlock = {
                    param($TaskName)
                    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
                    Get-ScheduledTaskInfo -TaskName $TaskName
                }
            }
            if ($Credential) {
                $parameters.Credential = $Credential
            }
            Invoke-Command @parameters
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'Federated collectors were started.'
    } catch {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'A federated collector could not be started.' `
            -Failed
        throw
    }
}

function Get-VMResourceTransferFederated {
    <#
    .SYNOPSIS
    Gets deduplicated VM transfer records from independent utility indexes.
    .DESCRIPTION
    Fans out across configured utility servers, reads their independent current
    records, tolerates partial utility-server outages, and selects the newest
    copy of each transfer.
    #>
    [CmdletBinding()]
    param(
        [string[]]$UtilityServer = @(
            $env:VMHELPER_FEDERATED_UTILITY_SERVERS -split ',' |
                Where-Object { $_ }
        ),

        [string[]]$TransferId,

        [ValidateSet('Queued', 'Running', 'Completed', 'Failed')]
        [string[]]$Status,

        [switch]$Active,

        [switch]$Latest,

        [string]$LocalPath = 'C:\ProgramData\DTMS\VMM\FederatedTransfers',

        [pscredential]$Credential
    )

    if (@($UtilityServer).Count -eq 0) {
        throw 'Specify UtilityServer or set VMHELPER_FEDERATED_UTILITY_SERVERS.'
    }
    $queryFailures = [Collections.Generic.List[string]]::new()
    $records = @(
        foreach ($server in @($UtilityServer | Sort-Object -Unique)) {
            $parameters = @{
                ComputerName = $server
                ArgumentList = (Join-Path $LocalPath 'Index')
                ErrorAction = 'Stop'
                ScriptBlock = {
                    param($IndexRoot)
                    if (-not (Test-Path -LiteralPath $IndexRoot -PathType Container)) {
                        return
                    }
                    Get-ChildItem -LiteralPath $IndexRoot -Directory |
                        ForEach-Object {
                            $currentPath = Join-Path $_.FullName 'Current.json'
                            if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
                                Get-Content -LiteralPath $currentPath -Raw |
                                    ConvertFrom-Json
                            }
                        }
                }
            }
            if ($Credential) {
                $parameters.Credential = $Credential
            }
            try {
                Invoke-Command @parameters
            } catch {
                $queryFailures.Add("$server`: $($_.Exception.Message)")
            }
        }
    )
    if ($queryFailures.Count -gt 0) {
        if ($records.Count -eq 0) {
            throw "Every federated index query failed: $($queryFailures -join '; ')"
        }
        Write-Warning "Some federated indexes were unavailable: $($queryFailures -join '; ')"
    }
    $filtered = @($records | Where-Object {
        (-not $TransferId -or $_.TransferId -in $TransferId) -and
        (-not $Status -or $_.Status -in $Status) -and
        (-not $Active -or $_.Status -in @('Queued', 'Running'))
    })
    $deduplicated = @($filtered |
        Group-Object TransferId |
        ForEach-Object {
            $copies = @($_.Group | Sort-Object {
                if ($_.UpdatedUtc) { [datetime]$_.UpdatedUtc } else { [datetime]::MinValue }
            } -Descending)
            $selected = $copies[0].PSObject.Copy()
            $selected | Add-Member NoteProperty UtilityServers @(
                $copies.CollectorUtilityServer | Sort-Object -Unique
            ) -Force
            $selected
        } |
        Sort-Object {
            if ($_.UpdatedUtc) { [datetime]$_.UpdatedUtc } else { [datetime]::MinValue }
        } -Descending)
    if ($Latest) {
        $deduplicated | Select-Object -First 1
    } else {
        $deduplicated
    }
}

function Get-VMHelperRuntime {
    <#
    .SYNOPSIS
    Returns the PowerShell runtime mode detected by VMHelper.
    .DESCRIPTION
    Reports whether VMHelper is running natively in PowerShell 7 or in its
    Windows PowerShell 5.1 compatibility mode. Both modes expose the same
    public VM operations.
    #>
    [CmdletBinding()]
    param()

    $script:VMHelperRuntime.PSObject.Copy()
}

function Open-RemoteSession {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [pscredential]$Credential
    )

    $parameters = @{
        ComputerName = $ComputerName
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $parameters.Credential = $Credential
    }
    New-PSSession @parameters
}

function Close-RemoteSession {
    param([System.Management.Automation.Runspaces.PSSession[]]$Session)

    foreach ($item in @($Session)) {
        if ($null -ne $item) {
            Remove-PSSession -Session $item -ErrorAction SilentlyContinue
        }
    }
}

function Import-ActiveDirectoryModule {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        if ($script:VMHelperRuntime.RuntimeMode -ne 'PowerShell7') {
            throw "Cannot load the ActiveDirectory module. Install the AD PowerShell tools. Details: $($_.Exception.Message)"
        }
        try {
            Import-Module ActiveDirectory -UseWindowsPowerShell -ErrorAction Stop
        } catch {
            throw "Cannot load the ActiveDirectory module natively or through Windows PowerShell compatibility. Install the AD PowerShell tools. Details: $($_.Exception.Message)"
        }
    }
}

function Get-DomainNameFromDistinguishedName {
    param(
        [Parameter(Mandatory)]
        [string]$DistinguishedName
    )

    $domainMatch = [regex]::Match(
        $DistinguishedName.Trim(),
        '(?i)(?:^|(?<!\\),)\s*(?<DomainDN>DC\s*=\s*[^,]+(?:,\s*DC\s*=\s*[^,]+)*)$'
    )
    if (-not $domainMatch.Success) {
        throw "SearchBase '$DistinguishedName' must end in domain components such as 'DC=contoso,DC=com'."
    }
    $domainParts = @($domainMatch.Groups['DomainDN'].Value -split ',' | ForEach-Object {
        ($_ -replace '(?i)^\s*DC\s*=\s*', '').Trim()
    })
    $domainParts -join '.'
}

function Get-ParentDistinguishedName {
    param(
        [Parameter(Mandatory)]
        [string]$DistinguishedName
    )

    $separator = [regex]::Match($DistinguishedName, '(?<!\\),')
    if (-not $separator.Success) {
        return $DistinguishedName
    }
    $DistinguishedName.Substring($separator.Index + 1).Trim()
}

function Invoke-HyperVHostParallelProbe {
    param(
        [Parameter(Mandatory)]
        [object[]]$Candidate,

        [Parameter(Mandatory)]
        [int]$ThrottleLimit,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,

        [pscredential]$Credential,

        [switch]$IncludeVirtualizedHosts
    )

    $probeScript = {
        param(
            [object]$Target,
            [pscredential]$ProbeCredential,
            [int]$OperationTimeoutSeconds,
            [bool]$AllowVirtualizedHost
        )

        function ConvertTo-ProbeResult {
            param(
                [bool]$ProbeSucceeded,
                [bool]$IsHyperVHost,
                [bool]$IsBareMetal,
                [string]$ErrorCategory,
                [string]$Message,
                [object]$System
            )

            [pscustomobject]@{
                HostName = [string]$Target.DNSHostName
                SearchBase = [string]$Target.SearchBase
                OperatingSystem = [string]$Target.OperatingSystem
                ProbeSucceeded = $ProbeSucceeded
                IsHyperVHost = $IsHyperVHost
                IsBareMetal = $IsBareMetal
                Manufacturer = if ($System) { [string]$System.Manufacturer } else { $null }
                Model = if ($System) { [string]$System.Model } else { $null }
                ErrorCategory = $ErrorCategory
                Message = $Message
            }
        }

        try {
            [void][Net.Dns]::GetHostAddresses([string]$Target.DNSHostName)
        } catch {
            return ConvertTo-ProbeResult `
                -ProbeSucceeded $false `
                -IsHyperVHost $false `
                -IsBareMetal $false `
                -ErrorCategory 'NameResolution' `
                -Message $_.Exception.Message
        }

        $invokeParameters = @{
            ComputerName = [string]$Target.DNSHostName
            ErrorAction = 'Stop'
            SessionOption = New-PSSessionOption `
                -OpenTimeout ($OperationTimeoutSeconds * 1000) `
                -OperationTimeout ($OperationTimeoutSeconds * 1000)
        }
        if ($ProbeCredential) {
            $invokeParameters.Credential = $ProbeCredential
        }
        try {
            $system = Invoke-Command @invokeParameters -ScriptBlock {
                $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    Manufacturer = [string]$computerSystem.Manufacturer
                    Model = [string]$computerSystem.Model
                    ProductType = [int]$operatingSystem.ProductType
                    HasHyperVService = $null -ne $vmms
                }
            }
            if ($system.ProductType -eq 2) {
                return ConvertTo-ProbeResult `
                    -ProbeSucceeded $true `
                    -IsHyperVHost $false `
                    -IsBareMetal $true `
                    -ErrorCategory 'DomainController' `
                    -Message 'Domain controllers are excluded from fallback Hyper-V discovery.' `
                    -System $system
            }
            $isVirtualized = "$($system.Manufacturer) $($system.Model)" -match '(?i)virtual|vmware|kvm|qemu|xen|bochs|parallels|hvm dom'
            if ($isVirtualized -and -not $AllowVirtualizedHost) {
                return ConvertTo-ProbeResult `
                    -ProbeSucceeded $true `
                    -IsHyperVHost $false `
                    -IsBareMetal $false `
                    -ErrorCategory 'VirtualizedServer' `
                    -Message 'The server appears to be virtualized; nested Hyper-V hosts are excluded by default.' `
                    -System $system
            }
            if (-not $system.HasHyperVService) {
                return ConvertTo-ProbeResult `
                    -ProbeSucceeded $true `
                    -IsHyperVHost $false `
                    -IsBareMetal (-not $isVirtualized) `
                    -ErrorCategory 'NotHyperVHost' `
                    -Message 'The Hyper-V Virtual Machine Management service is not installed.' `
                    -System $system
            }
            ConvertTo-ProbeResult `
                -ProbeSucceeded $true `
                -IsHyperVHost $true `
                -IsBareMetal (-not $isVirtualized) `
                -ErrorCategory $null `
                -Message 'Hyper-V host capability verified.' `
                -System $system
        } catch {
            $message = $_.Exception.Message
            $category = if ($message -match '(?i)access is denied|0x80070005|unauthorized|not authorized') {
                'AccessDenied'
            } elseif ($message -match '(?i)authentication|logon failure|credentials were rejected|unknown user name') {
                'Authentication'
            } elseif ($message -match '(?i)cannot be resolved|network path was not found|client cannot connect|connection.*failed|timed out|winrm.*firewall') {
                'Connectivity'
            } else {
                'RemoteQuery'
            }
            ConvertTo-ProbeResult `
                -ProbeSucceeded $false `
                -IsHyperVHost $false `
                -IsBareMetal $false `
                -ErrorCategory $category `
                -Message $message
        }
    }

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        1,
        [Math]::Min($ThrottleLimit, $Candidate.Count),
        $sessionState,
        $Host
    )
    $tasks = [Collections.Generic.List[object]]::new()
    try {
        $pool.Open()
        foreach ($target in $Candidate) {
            $powerShell = [System.Management.Automation.PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($probeScript).
                AddArgument($target).
                AddArgument($Credential).
                AddArgument($TimeoutSeconds).
                AddArgument($IncludeVirtualizedHosts.IsPresent)
            $tasks.Add([pscustomobject]@{
                PowerShell = $powerShell
                Handle = $powerShell.BeginInvoke()
                Target = $target
            })
        }
        foreach ($task in $tasks) {
            try {
                $task.PowerShell.EndInvoke($task.Handle)
            } catch {
                [pscustomobject]@{
                    HostName = [string]$task.Target.DNSHostName
                    SearchBase = [string]$task.Target.SearchBase
                    OperatingSystem = [string]$task.Target.OperatingSystem
                    ProbeSucceeded = $false
                    IsHyperVHost = $false
                    IsBareMetal = $false
                    Manufacturer = $null
                    Model = $null
                    ErrorCategory = 'ProbeInfrastructure'
                    Message = $_.Exception.Message
                }
            }
        }
    } finally {
        foreach ($task in $tasks) {
            $task.PowerShell.Dispose()
        }
        $pool.Close()
        $pool.Dispose()
    }
}

function Select-HyperVProbeResult {
    param(
        [Parameter(Mandatory)]
        [object[]]$ProbeResult
    )

    $inaccessibleSearchBases = @($ProbeResult |
        Group-Object SearchBase |
        Where-Object {
            @($_.Group | Where-Object {
                $_.ErrorCategory -in @('AccessDenied', 'Authentication')
            }).Count -gt 0
        } |
        Select-Object -ExpandProperty Name)
    $hostNames = @($ProbeResult |
        Where-Object {
            $_.ProbeSucceeded -and
            $_.IsHyperVHost -and
            $_.SearchBase -notin $inaccessibleSearchBases
        } |
        Select-Object -ExpandProperty HostName |
        Sort-Object -Unique)
    $diagnostics = [Collections.Generic.List[object]]::new()
    foreach ($result in $ProbeResult) {
        if ($result.SearchBase -in $inaccessibleSearchBases) {
            if ($result.ErrorCategory -in @('AccessDenied', 'Authentication')) {
                $diagnostics.Add($result)
            } else {
                $diagnostics.Add([pscustomobject]@{
                    HostName = $result.HostName
                    SearchBase = $result.SearchBase
                    OperatingSystem = $result.OperatingSystem
                    ProbeSucceeded = $result.ProbeSucceeded
                    IsHyperVHost = $result.IsHyperVHost
                    IsBareMetal = $result.IsBareMetal
                    Manufacturer = $result.Manufacturer
                    Model = $result.Model
                    ErrorCategory = 'SearchBaseAccessDenied'
                    Message = "Excluded because another candidate in '$($result.SearchBase)' returned AccessDenied or Authentication."
                })
            }
        } elseif (-not ($result.ProbeSucceeded -and $result.IsHyperVHost)) {
            $diagnostics.Add($result)
        }
    }

    [pscustomobject]@{
        HostNames = $hostNames
        Diagnostics = $diagnostics.ToArray()
        InaccessibleSearchBases = $inaccessibleSearchBases
    }
}

function Resolve-HyperVHostName {
    param(
        [string]$SearchBase,

        [string]$DomainName,

        [pscredential]$Credential,

        [switch]$IncludeAllWindowsServers,

        [switch]$IncludeVirtualizedHosts,

        [string[]]$ComputerNamePattern = @(),

        [Parameter(Mandatory)]
        [int]$ThrottleLimit,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    Import-ActiveDirectoryModule
    if (-not $DomainName -and $SearchBase) {
        $DomainName = Get-DomainNameFromDistinguishedName -DistinguishedName $SearchBase
    }
    if (-not $DomainName) {
        $DomainName = [string]$env:USERDNSDOMAIN
    }
    if (-not $DomainName) {
        try {
            $domainParameters = @{ ErrorAction = 'Stop' }
            if ($Credential) {
                $domainParameters.Credential = $Credential
            }
            $DomainName = [string](Get-ADDomain @domainParameters).DNSRoot
        } catch {
            throw "Cannot determine the current Active Directory domain. Specify -DomainName or -SearchBase. Details: $($_.Exception.Message)"
        }
    }

    $controllerParameters = @{
        Discover = $true
        DomainName = $DomainName
        Service = 'ADWS'
        ErrorAction = 'Stop'
    }
    try {
        $controller = Get-ADDomainController @controllerParameters
        $adServer = [string](@($controller.HostName)[0])
        if ([string]::IsNullOrWhiteSpace($adServer)) {
            throw 'Domain controller discovery returned no hostname.'
        }
    } catch {
        throw "Cannot discover an AD Web Services domain controller for '$DomainName'. Details: $($_.Exception.Message)"
    }

    $connectionParameters = @{
        Server = $adServer
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $connectionParameters.Credential = $Credential
    }
    try {
        $rootDse = Get-ADRootDSE @connectionParameters
        $domainDn = [string](@($rootDse.defaultNamingContext)[0])
        if (-not $SearchBase) {
            $SearchBase = $domainDn
        }
        $null = Get-ADObject -Identity $SearchBase @connectionParameters
    } catch {
        throw "Cannot validate search base '$SearchBase' on '$adServer'. Details: $($_.Exception.Message)"
    }

    $baseComputerParameters = @{
        Server = $adServer
        SearchBase = $SearchBase
        SearchScope = 'Subtree'
        Properties = @('DNSHostName', 'DistinguishedName', 'OperatingSystem')
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $baseComputerParameters.Credential = $Credential
    }
    $nameFilter = ''
    if ($ComputerNamePattern.Count -gt 0) {
        $patternFilters = @($ComputerNamePattern | ForEach-Object {
            if ($_ -notmatch '^[A-Za-z0-9*?.-]+$') {
                throw "Computer name wildcard pattern '$_' contains unsupported characters."
            }
            $ldapPattern = $_ -replace '\?', '*'
            "(|(name=$ldapPattern)(dNSHostName=$ldapPattern))"
        })
        $nameFilter = if ($patternFilters.Count -eq 1) {
            $patternFilters[0]
        } else {
            '(|{0})' -f ($patternFilters -join '')
        }
    }
    try {
        $spnComputerParameters = $baseComputerParameters.Clone()
        $spnComputerParameters.LDAPFilter = '(&(objectCategory=computer){0}(servicePrincipalName=Microsoft Virtual System Migration Service/*)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(userAccountControl:1.2.840.113556.1.4.803:=8192)))' -f $nameFilter
        $spnHosts = @(Get-ADComputer @spnComputerParameters |
            Where-Object {
                $computer = $_
                $ComputerNamePattern.Count -eq 0 -or
                @($ComputerNamePattern | Where-Object {
                    $computer.Name -like $_ -or $computer.DNSHostName -like $_
                }).Count -gt 0
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.DNSHostName) } |
            Select-Object -ExpandProperty DNSHostName |
            Sort-Object -Unique)
        if ($spnHosts.Count -gt 0 -and -not $IncludeAllWindowsServers) {
            return [pscustomobject]@{
                HostNames = $spnHosts
                Diagnostics = @()
                SearchBases = @($SearchBase)
                Strategy = 'HyperVServicePrincipalName'
                DomainName = $DomainName
                ADServer = $adServer
            }
        }

        $serverComputerParameters = $baseComputerParameters.Clone()
        $serverComputerParameters.LDAPFilter = '(&(objectCategory=computer){0}(operatingSystem=Windows Server*)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(userAccountControl:1.2.840.113556.1.4.803:=8192)))' -f $nameFilter
        $serverCandidates = @(Get-ADComputer @serverComputerParameters |
            Where-Object {
                $computer = $_
                $ComputerNamePattern.Count -eq 0 -or
                @($ComputerNamePattern | Where-Object {
                    $computer.Name -like $_ -or $computer.DNSHostName -like $_
                }).Count -gt 0
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.DNSHostName) } |
            ForEach-Object {
                [pscustomobject]@{
                    DNSHostName = [string]$_.DNSHostName
                    DistinguishedName = [string]$_.DistinguishedName
                    OperatingSystem = [string]$_.OperatingSystem
                    SearchBase = Get-ParentDistinguishedName -DistinguishedName ([string]$_.DistinguishedName)
                }
            } |
            Sort-Object DNSHostName -Unique)
    } catch {
        throw "Failed to discover Hyper-V hosts below '$SearchBase' using '$adServer'. Details: $($_.Exception.Message)"
    }
    if ($serverCandidates.Count -eq 0) {
        return [pscustomobject]@{
            HostNames = @()
            Diagnostics = @()
            SearchBases = @()
            Strategy = 'WindowsServerFallback'
            DomainName = $DomainName
            ADServer = $adServer
        }
    }

    $searchBases = @($serverCandidates.SearchBase | Sort-Object -Unique)
    Write-Verbose "No usable Hyper-V SPN candidates were found. Probing $($serverCandidates.Count) enabled non-DC Windows Server computer(s) across $($searchBases.Count) search base(s)."
    $probeResults = @(Invoke-HyperVHostParallelProbe `
        -Candidate $serverCandidates `
        -ThrottleLimit ([Math]::Min($ThrottleLimit, $serverCandidates.Count)) `
        -TimeoutSeconds $TimeoutSeconds `
        -Credential $Credential `
        -IncludeVirtualizedHosts:$IncludeVirtualizedHosts)
    $selection = Select-HyperVProbeResult -ProbeResult $probeResults
    foreach ($inaccessibleBase in $selection.InaccessibleSearchBases) {
        Write-Verbose "Eliminated search base '$inaccessibleBase' because at least one candidate denied access or authentication."
    }

    [pscustomobject]@{
        HostNames = @($selection.HostNames)
        Diagnostics = @($selection.Diagnostics)
        SearchBases = $searchBases
        InaccessibleSearchBases = @($selection.InaccessibleSearchBases)
        Strategy = 'WindowsServerParallelProbe'
        DomainName = $DomainName
        ADServer = $adServer
    }
}

function Invoke-VMHostParallelQuery {
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [int]$ThrottleLimit,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,

        [pscredential]$Credential
    )

    $queryScript = {
        param(
            [string]$TargetComputerName,
            [string]$TargetVMName,
            [pscredential]$QueryCredential,
            [int]$OperationTimeoutSeconds
        )

        $invokeParameters = @{
            ComputerName = $TargetComputerName
            ErrorAction = 'Stop'
            SessionOption = New-PSSessionOption `
                -OpenTimeout ($OperationTimeoutSeconds * 1000) `
                -OperationTimeout ($OperationTimeoutSeconds * 1000)
        }
        if ($QueryCredential) {
            $invokeParameters.Credential = $QueryCredential
        }
        try {
            $virtualMachines = @(Invoke-Command @invokeParameters -ArgumentList $TargetVMName -ScriptBlock {
                param($Name)
                Import-Module Hyper-V -ErrorAction Stop
                @(Get-VM -Name $Name -ErrorAction SilentlyContinue | ForEach-Object {
                    [pscustomobject]@{
                        Name = $_.Name
                        Id = [string]$_.Id
                        State = [string]$_.State
                        Uptime = $_.Uptime
                        Status = [string]$_.Status
                        Version = [string]$_.Version
                        IsClustered = [bool]$_.IsClustered
                    }
                })
            })
            if ($virtualMachines.Count -eq 0) {
                [pscustomobject]@{
                    PSTypeName = 'VMHelper.VMHostSearchResult'
                    HostName = $TargetComputerName
                    VMName = $null
                    VMId = $null
                    State = $null
                    Uptime = $null
                    Status = $null
                    Version = $null
                    IsClustered = $null
                    Found = $false
                    QuerySucceeded = $true
                    Phase = 'VMQuery'
                    ErrorCategory = $null
                    Error = $null
                }
            } else {
                foreach ($virtualMachine in $virtualMachines) {
                    [pscustomobject]@{
                        PSTypeName = 'VMHelper.VMHostSearchResult'
                        HostName = $TargetComputerName
                        VMName = $virtualMachine.Name
                        VMId = $virtualMachine.Id
                        State = $virtualMachine.State
                        Uptime = $virtualMachine.Uptime
                        Status = $virtualMachine.Status
                        Version = $virtualMachine.Version
                        IsClustered = $virtualMachine.IsClustered
                        Found = $true
                        QuerySucceeded = $true
                        Phase = 'VMQuery'
                        ErrorCategory = $null
                        Error = $null
                    }
                }
            }
        } catch {
            $message = $_.Exception.Message
            $category = if ($message -match '(?i)access is denied|0x80070005|unauthorized|not authorized') {
                'AccessDenied'
            } elseif ($message -match '(?i)authentication|logon failure|credentials were rejected|unknown user name') {
                'Authentication'
            } elseif ($message -match '(?i)cannot be resolved') {
                'NameResolution'
            } elseif ($message -match '(?i)network path was not found|client cannot connect|connection.*failed|timed out|winrm.*firewall') {
                'Connectivity'
            } else {
                'RemoteQuery'
            }
            [pscustomobject]@{
                PSTypeName = 'VMHelper.VMHostSearchResult'
                HostName = $TargetComputerName
                VMName = $null
                VMId = $null
                State = $null
                Uptime = $null
                Status = $null
                Version = $null
                IsClustered = $null
                Found = $false
                QuerySucceeded = $false
                Phase = 'VMQuery'
                ErrorCategory = $category
                Error = $message
            }
        }
    }

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        1,
        [Math]::Min($ThrottleLimit, $ComputerName.Count),
        $sessionState,
        $Host
    )
    $tasks = [Collections.Generic.List[object]]::new()
    try {
        $pool.Open()
        foreach ($target in $ComputerName) {
            $powerShell = [System.Management.Automation.PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($queryScript).
                AddArgument($target).
                AddArgument($VMName).
                AddArgument($Credential).
                AddArgument($TimeoutSeconds)
            $tasks.Add([pscustomobject]@{
                PowerShell = $powerShell
                Handle = $powerShell.BeginInvoke()
                HostName = $target
            })
        }
        foreach ($task in $tasks) {
            try {
                $task.PowerShell.EndInvoke($task.Handle)
            } catch {
                [pscustomobject]@{
                    PSTypeName = 'VMHelper.VMHostSearchResult'
                    HostName = $task.HostName
                    VMName = $null
                    VMId = $null
                    State = $null
                    Uptime = $null
                    Status = $null
                    Version = $null
                    IsClustered = $null
                    Found = $false
                    QuerySucceeded = $false
                    Phase = 'VMQuery'
                    ErrorCategory = 'QueryInfrastructure'
                    Error = $_.Exception.Message
                }
            }
        }
    } finally {
        foreach ($task in $tasks) {
            $task.PowerShell.Dispose()
        }
        $pool.Close()
        $pool.Dispose()
    }
}

function Find-VMHost {
    <#
    .SYNOPSIS
    Finds Hyper-V hosts where a virtual machine is registered.
    .DESCRIPTION
    Queries Hyper-V hosts concurrently using a bounded runspace pool that works
    in both PowerShell 7 and Windows PowerShell 5.1.

    Supply ComputerName for a known host list. Otherwise, Active Directory is
    searched recursively. By default, AD discovery targets enabled computers
    that publish the Hyper-V migration-service SPN. When SearchBase is omitted,
    the current domain naming context is used.

    Results are structured objects. Matches are returned by default. Use
    IncludeQueryErrors or IncludeNotFound to include diagnostic results.
    .PARAMETER VMName
    VM name or wildcard pattern accepted by Get-VM -Name.
    .PARAMETER ComputerName
    Explicit Hyper-V host names or wildcard patterns. Literal names bypass
    Active Directory. Wildcards are expanded against computer Name and
    DNSHostName in AD before capability probing.
    .PARAMETER SearchBase
    Optional OU, container, or domain distinguished name for recursive AD
    discovery. Defaults to the current domain naming context.
    .PARAMETER IncludeAllWindowsServers
    Skips the Hyper-V SPN shortcut and probes all enabled non-DC Windows Server
    computer objects in parallel.
    .PARAMETER IncludeVirtualizedHosts
    Allows nested or virtualized Hyper-V hosts during fallback probing. Bare
    metal candidates are required by default.
    .PARAMETER ThrottleLimit
    Maximum concurrent host queries. Defaults to four times the logical
    processor count, bounded between 8 and 64.
    .PARAMETER TimeoutSeconds
    Open and operation timeout for each remote host query. Defaults to 30.
    .EXAMPLE
    Find-VMHost -VMName 'SQL01' -ComputerName 'hv01','hv02'
    .EXAMPLE
    Find-VMHost -VMName 'web*' -SearchBase 'OU=HyperV,DC=contoso,DC=com'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ActiveDirectory')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ComputerName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DNSHostName', 'HostName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [switch]$IncludeAllWindowsServers,

        [switch]$IncludeVirtualizedHosts,

        [ValidateRange(1, 256)]
        [int]$ThrottleLimit = [Math]::Min(64, [Math]::Max(8, [Environment]::ProcessorCount * 4)),

        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 30,

        [pscredential]$Credential,

        [switch]$IncludeQueryErrors,

        [switch]$IncludeNotFound,

        [switch]$IncludeDiscoveryDiagnostics
    )

    begin {
        $activity = Start-DTMSActivity `
            -Name 'Hyper-V host discovery' `
            -Intent "Locate virtual machine pattern '$VMName'"
        $explicitHosts = [Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($item in @($ComputerName)) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $explicitHosts.Add($item.Trim())
            }
        }
    }
    end {
        $discoveryDiagnostics = @()
        $discoveryStrategy = 'ExplicitComputerName'
        $hostNames = @(
            if ($PSCmdlet.ParameterSetName -eq 'ComputerName') {
                $wildcardPatterns = @($explicitHosts |
                    Where-Object { [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($_) } |
                    Sort-Object -Unique)
                foreach ($wildcardPattern in $wildcardPatterns) {
                    if ($wildcardPattern -notmatch '^[A-Za-z0-9*?.-]+$') {
                        throw "Computer name wildcard pattern '$wildcardPattern' contains unsupported characters."
                    }
                }
                $literalHosts = @($explicitHosts |
                    Where-Object { -not [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($_) } |
                    Sort-Object -Unique)
                $expandedHosts = @()
                if ($wildcardPatterns.Count -gt 0) {
                    $resolution = Resolve-HyperVHostName `
                        -SearchBase $SearchBase `
                        -DomainName $DomainName `
                        -Credential $Credential `
                        -IncludeAllWindowsServers:$IncludeAllWindowsServers `
                        -IncludeVirtualizedHosts:$IncludeVirtualizedHosts `
                        -ComputerNamePattern $wildcardPatterns `
                        -ThrottleLimit $ThrottleLimit `
                        -TimeoutSeconds $TimeoutSeconds
                    $discoveryStrategy = if ($literalHosts.Count -gt 0) {
                        "ExplicitAndWildcard+$($resolution.Strategy)"
                    } else {
                        "ComputerNameWildcard+$($resolution.Strategy)"
                    }
                    $discoveryDiagnostics = @($resolution.Diagnostics | ForEach-Object {
                        [pscustomobject]@{
                            PSTypeName = 'VMHelper.VMHostSearchResult'
                            HostName = $_.HostName
                            VMName = $null
                            VMId = $null
                            State = $null
                            Uptime = $null
                            Status = $null
                            Version = $null
                            IsClustered = $null
                            Found = $false
                            QuerySucceeded = $_.ProbeSucceeded
                            Phase = 'Discovery'
                            ErrorCategory = $_.ErrorCategory
                            Error = $_.Message
                            SearchBase = $_.SearchBase
                            OperatingSystem = $_.OperatingSystem
                            Manufacturer = $_.Manufacturer
                            Model = $_.Model
                        }
                    })
                    $expandedHosts = @($resolution.HostNames)
                }
                $literalHosts + $expandedHosts | Sort-Object -Unique
            } else {
                $resolution = Resolve-HyperVHostName `
                    -SearchBase $SearchBase `
                    -DomainName $DomainName `
                    -Credential $Credential `
                    -IncludeAllWindowsServers:$IncludeAllWindowsServers `
                    -IncludeVirtualizedHosts:$IncludeVirtualizedHosts `
                    -ThrottleLimit $ThrottleLimit `
                    -TimeoutSeconds $TimeoutSeconds
                $discoveryStrategy = $resolution.Strategy
                $discoveryDiagnostics = @($resolution.Diagnostics | ForEach-Object {
                    [pscustomobject]@{
                        PSTypeName = 'VMHelper.VMHostSearchResult'
                        HostName = $_.HostName
                        VMName = $null
                        VMId = $null
                        State = $null
                        Uptime = $null
                        Status = $null
                        Version = $null
                        IsClustered = $null
                        Found = $false
                        QuerySucceeded = $_.ProbeSucceeded
                        Phase = 'Discovery'
                        ErrorCategory = $_.ErrorCategory
                        Error = $_.Message
                        SearchBase = $_.SearchBase
                        OperatingSystem = $_.OperatingSystem
                        Manufacturer = $_.Manufacturer
                        Model = $_.Model
                    }
                })
                $resolution.HostNames
            }
        )
        if ($hostNames.Count -eq 0) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'No candidate Hyper-V hosts were discovered.'
            Write-Warning "No accessible Hyper-V hosts were discovered using strategy '$discoveryStrategy'."
            if ($IncludeDiscoveryDiagnostics) {
                $discoveryDiagnostics | Sort-Object SearchBase, HostName
            }
            return
        }

        $effectiveThrottle = [Math]::Min($ThrottleLimit, $hostNames.Count)
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Querying $($hostNames.Count) candidate Hyper-V host(s)." `
            -ForceHeartbeat
        Write-Verbose "Discovery strategy '$discoveryStrategy' produced $($hostNames.Count) host(s). Querying with throttle $effectiveThrottle and timeout $TimeoutSeconds seconds."
        $results = @(Invoke-VMHostParallelQuery `
            -ComputerName $hostNames `
            -VMName $VMName `
            -ThrottleLimit $effectiveThrottle `
            -TimeoutSeconds $TimeoutSeconds `
            -Credential $Credential)
        $queryErrors = @($results | Where-Object { -not $_.QuerySucceeded })
        if ($queryErrors.Count -gt 0) {
            Write-Warning "$($queryErrors.Count) of $($hostNames.Count) Hyper-V host queries failed. Use -IncludeQueryErrors to return details."
            foreach ($queryError in $queryErrors) {
                Write-Verbose "$($queryError.HostName): $($queryError.Error)"
            }
        }

        $output = @($results | Where-Object {
            $_.Found -or
            ($IncludeQueryErrors -and -not $_.QuerySucceeded) -or
            ($IncludeNotFound -and $_.QuerySucceeded -and -not $_.Found)
        })
        if ($IncludeDiscoveryDiagnostics) {
            $output += $discoveryDiagnostics
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status "Discovery returned $($output.Count) result record(s)."
        @($output | Sort-Object Phase, HostName, VMName)
    }
}

function Resolve-VMOperationHostName {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [pscredential]$Credential,

        [Parameter(Mandatory)]
        [ValidateSet('source', 'target', 'destination')]
        [string]$Role
    )

    if ($HostName) {
        return $HostName
    }

    $vmMatches = @(Find-VMHost -VMName $VMName -Credential $Credential)
    if ($vmMatches.Count -eq 0) {
        throw "Unable to locate the $Role VM '$VMName' on an accessible Hyper-V host. Specify the host name explicitly or review Find-VMHost diagnostics."
    }
    if ($vmMatches.Count -gt 1) {
        $locations = @($vmMatches | ForEach-Object {
            '{0}:{1}' -f $_.HostName, $_.VMName
        }) -join ', '
        throw "The $Role VM '$VMName' was found in multiple locations: $locations. Specify the host name explicitly."
    }

    $vmMatches[0].HostName
}

function Copy-RemoteItem {
    <#
    .SYNOPSIS
    Copies a file or directory between two remote Windows computers.
    .DESCRIPTION
    Relays the item through a local staging directory because Copy-Item cannot
    use FromSession and ToSession in one operation. The caller must have enough
    local disk space for the complete item.

    PowerShell remoting must be enabled on both computers. Existing destination
    content is rejected unless Force is specified.
    .PARAMETER SourcePath
    Absolute path as seen by the source computer.
    .PARAMETER DestinationPath
    Parent directory as seen by the destination computer.
    .PARAMETER StagingPath
    Local parent directory for the temporary relay. A unique child directory
    is created and removed automatically unless RetainStagingData is specified.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [ValidateNotNullOrEmpty()]
        [string]$StagingPath = ([IO.Path]::GetTempPath()),

        [pscredential]$SourceCredential,

        [pscredential]$DestinationCredential,

        [switch]$Force,

        [switch]$RetainStagingData
    )

    if ($SourceComputerName -ieq $DestinationComputerName) {
        throw 'SourceComputerName and DestinationComputerName must be different.'
    }
    $activity = Start-DTMSActivity `
        -Name 'Remote item relay' `
        -Intent "Relay '$SourcePath' through local staging" `
        -Target "$DestinationComputerName`:$DestinationPath"
    $copySucceeded = $false
    $copyCancelled = $false
    $sourceSession = $null
    $destinationSession = $null
    $relayRoot = Join-Path $StagingPath ('VMHelper-{0}' -f [guid]::NewGuid().ToString('N'))
    try {
        $sourceSession = Open-RemoteSession -ComputerName $SourceComputerName -Credential $SourceCredential
        $destinationSession = Open-RemoteSession -ComputerName $DestinationComputerName -Credential $DestinationCredential
        $sourceInfo = Invoke-Command -Session $sourceSession -ArgumentList $SourcePath -ScriptBlock {
            param($Path)
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            [pscustomobject]@{
                Name = $item.Name
                FullName = $item.FullName
                IsContainer = [bool]$item.PSIsContainer
            }
        }
        $destinationItemPath = Join-Path $DestinationPath $sourceInfo.Name
        $destinationExists = Invoke-Command -Session $destinationSession -ArgumentList $destinationItemPath -ScriptBlock {
            param($Path)
            Test-Path -LiteralPath $Path
        }
        if ($destinationExists -and -not $Force) {
            throw "Destination item already exists: $destinationItemPath. Specify -Force to replace it."
        }
        if (-not $PSCmdlet.ShouldProcess(
            "$SourceComputerName`:$SourcePath -> $DestinationComputerName`:$DestinationPath",
            'relay remote item'
        )) {
            $copyCancelled = $true
            return
        }

        New-Item -Path $relayRoot -ItemType Directory -Force | Out-Null
        Copy-Item -FromSession $sourceSession -LiteralPath $SourcePath -Destination $relayRoot -Recurse -Force:$Force -ErrorAction Stop
        Invoke-Command -Session $destinationSession -ArgumentList $DestinationPath, $destinationItemPath, $Force.IsPresent -ScriptBlock {
            param($Parent, $ItemPath, $Replace)
            New-Item -Path $Parent -ItemType Directory -Force | Out-Null
            if ($Replace -and (Test-Path -LiteralPath $ItemPath)) {
                Remove-Item -LiteralPath $ItemPath -Recurse -Force
            }
        }
        $localItemPath = Join-Path $relayRoot $sourceInfo.Name
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Sending '$($sourceInfo.Name)' to $DestinationComputerName." `
            -ForceHeartbeat
        Copy-Item -ToSession $destinationSession -LiteralPath $localItemPath -Destination $DestinationPath -Recurse -Force:$Force -ErrorAction Stop
        $copySucceeded = $true
        [pscustomobject]@{
            PSTypeName = 'VMHelper.RemoteItemCopyResult'
            SourceComputerName = $SourceComputerName
            DestinationComputerName = $DestinationComputerName
            SourcePath = $SourcePath
            DestinationPath = $destinationItemPath
            StagingPath = $relayRoot
            StagingRetained = $RetainStagingData.IsPresent
            RuntimeMode = $script:VMHelperRuntime.RuntimeMode
        }
    } finally {
        Close-RemoteSession -Session @($sourceSession, $destinationSession)
        if (-not $RetainStagingData -and (Test-Path -LiteralPath $relayRoot)) {
            Remove-Item -LiteralPath $relayRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status $(if ($copyCancelled) {
                'Remote item relay was not started.'
            } elseif ($copySucceeded) {
                'Remote item relay completed.'
            } else {
                'Remote item relay did not complete.'
            }) `
            -Failed:(-not $copySucceeded -and -not $copyCancelled)
    }
}

function Move-VMToHost {
    <#
    .SYNOPSIS
    Stages an identity-preserving Hyper-V VM move to another host.
    .DESCRIPTION
    Stops the source VM and leaves it stopped, exports it, relays the exported
    files through the management computer, and registers the copied VM on the
    destination with Import-VM -Register.

    Register import preserves the VM ID, configuration, virtual disks, and
    static MAC addresses. The destination is never started automatically.
    Source registration and original VM files are never removed.

    This is intentionally not live migration. The source and destination must
    be different hosts, and the same VM ID or name must not already exist on
    the destination.
    .PARAMETER TurnOff
    Uses an immediate power-off when the VM cannot shut down normally. This can
    cause guest data loss. Without this switch, Stop-VM requests the normal
    Hyper-V stop operation.
    .PARAMETER RetainTransferArtifacts
    Retains the source export and local relay directory for diagnostics.
    Destination files are always retained because they back the registered VM.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceHostName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationHostName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceExportRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationRoot,

        [ValidateNotNullOrEmpty()]
        [string]$LocalStagingRoot = ([IO.Path]::GetTempPath()),

        [pscredential]$SourceCredential,

        [pscredential]$DestinationCredential,

        [switch]$TurnOff,

        [switch]$RetainTransferArtifacts
    )

    $activity = Start-DTMSActivity `
        -Name 'VM host move' `
        -Intent "Stop, export, transfer, and register '$VMName' while preserving identity" `
        -Target $DestinationHostName
    if ($SourceHostName -ieq $DestinationHostName) {
        throw 'SourceHostName and DestinationHostName must be different.'
    }
    $sourceSession = $null
    $destinationSession = $null
    $runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N')
    $sourceRunRoot = Join-Path $SourceExportRoot $runId
    $localRunRoot = Join-Path $LocalStagingRoot "VMHelper-$runId"
    $destinationVMRoot = Join-Path $DestinationRoot $VMName
    $sourceExportedVMRoot = Join-Path $sourceRunRoot $VMName
    $sourceWasStopped = $false
    try {
        $sourceSession = Open-RemoteSession -ComputerName $SourceHostName -Credential $SourceCredential
        $destinationSession = Open-RemoteSession -ComputerName $DestinationHostName -Credential $DestinationCredential
        $sourceVM = Invoke-Command -Session $sourceSession -ArgumentList $VMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            [pscustomobject]@{
                Name = $vm.Name
                Id = [string]$vm.Id
                State = [string]$vm.State
                Generation = $vm.Generation
            }
        }
        $destinationCollision = Invoke-Command -Session $destinationSession -ArgumentList $sourceVM.Name, $sourceVM.Id -ScriptBlock {
            param($Name, $Id)
            Import-Module Hyper-V -ErrorAction Stop
            $byName = Get-VM -Name $Name -ErrorAction SilentlyContinue
            $byId = Get-VM -Id ([guid]$Id) -ErrorAction SilentlyContinue
            if ($byName -or $byId) {
                [pscustomobject]@{
                    NameExists = $null -ne $byName
                    IdExists = $null -ne $byId
                }
            }
        }
        if ($destinationCollision) {
            throw "Destination host already contains VM name '$($sourceVM.Name)' or ID '$($sourceVM.Id)'."
        }
        $destinationPathExists = Invoke-Command -Session $destinationSession -ArgumentList $destinationVMRoot -ScriptBlock {
            param($Path)
            Test-Path -LiteralPath $Path
        }
        if ($destinationPathExists) {
            throw "Destination path already exists: $destinationVMRoot"
        }
        if (-not $PSCmdlet.ShouldProcess(
            "$VMName from $SourceHostName to $DestinationHostName",
            'stop, export, transfer, and register VM while preserving its ID'
        )) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'The VM move was not started.'
            return
        }

        $networkIdentity = Invoke-Command -Session $sourceSession -ArgumentList $VMName, $TurnOff.IsPresent -ScriptBlock {
            param($Name, $UseTurnOff)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ($vm.State -ne 'Off') {
                if ($UseTurnOff) {
                    Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
                } else {
                    Stop-VM -VM $vm -Confirm:$false -ErrorAction Stop
                }
                $deadline = [DateTime]::UtcNow.AddMinutes(10)
                do {
                    Start-Sleep -Seconds 2
                    $vm = Get-VM -Name $Name -ErrorAction Stop
                } while ($vm.State -ne 'Off' -and [DateTime]::UtcNow -lt $deadline)
                if ($vm.State -ne 'Off') {
                    throw "VM '$Name' did not reach the Off state within 10 minutes."
                }
            }
            $networkIdentity = @(Get-VMNetworkAdapter -VM $vm | ForEach-Object {
                if (-not $_.MacAddress) {
                    throw "Network adapter '$($_.Name)' has no assigned MAC address."
                }
                if ($_.DynamicMacAddressEnabled) {
                    Set-VMNetworkAdapter -VMNetworkAdapter $_ -StaticMacAddress $_.MacAddress -ErrorAction Stop
                }
                Complete-DTMSActivity `
                    -Activity $activity `
                    -Status "VM '$VMName' was registered on '$DestinationHostName'."
                [pscustomobject]@{
                    Name = $_.Name
                    MacAddress = $_.MacAddress
                }
            })
            $networkIdentity
        }
        $sourceWasStopped = $true
        Invoke-Command -Session $sourceSession -ArgumentList $VMName, $sourceRunRoot -ScriptBlock {
            param($Name, $ExportRoot)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ($vm.State -ne 'Off') {
                throw "VM '$Name' is no longer off; refusing to export it."
            }
            New-Item -Path $ExportRoot -ItemType Directory -Force | Out-Null
            Export-VM -VM $vm -Path $ExportRoot -ErrorAction Stop
        }

        New-Item -Path $localRunRoot -ItemType Directory -Force | Out-Null
        Copy-Item -FromSession $sourceSession -LiteralPath $sourceExportedVMRoot -Destination $localRunRoot -Recurse -ErrorAction Stop
        Invoke-Command -Session $destinationSession -ArgumentList $DestinationRoot -ScriptBlock {
            param($Path)
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
        $localExportedVMRoot = Join-Path $localRunRoot $VMName
        Copy-Item -ToSession $destinationSession -LiteralPath $localExportedVMRoot -Destination $DestinationRoot -Recurse -ErrorAction Stop

        $importResult = Invoke-Command -Session $destinationSession -ArgumentList $destinationVMRoot, $sourceVM.Id, @($networkIdentity) -ScriptBlock {
            param($VMRoot, $ExpectedId, $ExpectedNetworkIdentity)
            Import-Module Hyper-V -ErrorAction Stop
            $configurationFiles = @(Get-ChildItem -LiteralPath $VMRoot -Filter '*.vmcx' -Recurse -File)
            if ($configurationFiles.Count -ne 1) {
                throw "Expected one VMCX file below '$VMRoot'; found $($configurationFiles.Count)."
            }
            $report = Compare-VM -Path $configurationFiles[0].FullName -ErrorAction SilentlyContinue
            if ($report -and $report.Incompatibilities.Count -gt 0) {
                $messages = @($report.Incompatibilities | ForEach-Object Message)
                throw "VM is incompatible with the destination host: $($messages -join '; ')"
            }
            $importedVM = Import-VM -Path $configurationFiles[0].FullName -Register -ErrorAction Stop
            if ([string]$importedVM.Id -ne $ExpectedId) {
                throw "Imported VM ID '$($importedVM.Id)' does not match source ID '$ExpectedId'."
            }
            $importedAdapters = @(Get-VMNetworkAdapter -VM $importedVM)
            foreach ($expectedAdapter in @($ExpectedNetworkIdentity)) {
                $matchingAdapter = @($importedAdapters | Where-Object Name -eq $expectedAdapter.Name)
                if ($matchingAdapter.Count -ne 1) {
                    throw "Expected one imported network adapter named '$($expectedAdapter.Name)'; found $($matchingAdapter.Count)."
                }
                if ($matchingAdapter[0].DynamicMacAddressEnabled -or
                    $matchingAdapter[0].MacAddress -ine $expectedAdapter.MacAddress) {
                    throw "Imported adapter '$($expectedAdapter.Name)' did not preserve static MAC address '$($expectedAdapter.MacAddress)'."
                }
            }
            [pscustomobject]@{
                Name = $importedVM.Name
                Id = [string]$importedVM.Id
                State = [string]$importedVM.State
                Path = $VMRoot
                MacAddresses = @($importedAdapters | Select-Object -ExpandProperty MacAddress)
            }
        }
        [pscustomobject]@{
            PSTypeName = 'VMHelper.MoveResult'
            VMName = $importResult.Name
            VMId = $importResult.Id
            SourceHostName = $SourceHostName
            DestinationHostName = $DestinationHostName
            SourceState = 'Off'
            DestinationState = $importResult.State
            DestinationPath = $importResult.Path
            MacAddresses = @($importResult.MacAddresses)
            SourceRegistrationRetained = $true
            SourceFilesRetained = $true
            TransferArtifactsRetained = $RetainTransferArtifacts.IsPresent
            RuntimeMode = $script:VMHelperRuntime.RuntimeMode
        }
    } catch {
        $message = if ($sourceWasStopped) {
            "$($_.Exception.Message) The source VM remains stopped on '$SourceHostName'."
        } else {
            $_.Exception.Message
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status $message `
            -Failed
        throw [System.InvalidOperationException]::new($message, $_.Exception)
    } finally {
        if (-not $RetainTransferArtifacts) {
            if (Test-Path -LiteralPath $localRunRoot) {
                Remove-Item -LiteralPath $localRunRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($sourceSession) {
                Invoke-Command -Session $sourceSession -ArgumentList $sourceRunRoot -ScriptBlock {
                    param($Path)
                    if (Test-Path -LiteralPath $Path) {
                        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                } -ErrorAction SilentlyContinue
            }
        }
        Close-RemoteSession -Session @($sourceSession, $destinationSession)
    }
}

function ConvertTo-RemoteAdministrativePath {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path -match '^\\\\') {
        return $Path
    }
    if ($Path -notmatch '^(?<Drive>[A-Za-z]):\\(?<Tail>.+)$') {
        throw "Source disk path '$Path' is not drive-qualified or a UNC path."
    }
    '\\{0}\{1}$\{2}' -f $ComputerName, $Matches.Drive, $Matches.Tail
}

function Publish-PendingVMResourceRegistryEvent {
    param(
        [Parameter(Mandatory)]
        [string]$TransactionRoot
    )

    if ([string]::IsNullOrWhiteSpace($script:VMHelperRegistryConfiguration.NamespacePath)) {
        return
    }
    if (Get-Command Sync-DurableOperationRegistry -ErrorAction SilentlyContinue) {
        $syncResult = Sync-DurableOperationRegistry `
            -OperationRoot $TransactionRoot `
            -NamespacePath $script:VMHelperRegistryConfiguration.NamespacePath
        $script:VMHelperRegistryConfiguration.Enabled = $syncResult.RegistryAvailable
        return
    }
    if (-not (Test-VMHelperPathAvailability `
        -Path $script:VMHelperRegistryConfiguration.NamespacePath `
        -PathType Container)) {
        $script:VMHelperRegistryConfiguration.Enabled = $false
        return
    }
    $script:VMHelperRegistryConfiguration.Enabled = $true
    $outboxPath = Join-Path $TransactionRoot 'RegistryOutbox'
    if (-not (Test-Path -LiteralPath $outboxPath -PathType Container)) {
        return
    }
    foreach ($eventFile in @(Get-ChildItem -LiteralPath $outboxPath -Filter '*.json' -File |
        Sort-Object Name)) {
        try {
            $registryEvent = Get-Content -LiteralPath $eventFile.FullName -Raw | ConvertFrom-Json
            $transferRoot = Join-Path $script:VMHelperRegistryConfiguration.NamespacePath $registryEvent.transferId
            $eventsRoot = Join-Path $transferRoot 'Events'
            New-Item -Path $eventsRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $destinationPath = Join-Path $eventsRoot $eventFile.Name
            $bytes = [IO.File]::ReadAllBytes($eventFile.FullName)
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                $stream = [IO.File]::Open(
                    $destinationPath,
                    [IO.FileMode]::CreateNew,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::Read
                )
                try {
                    $stream.Write($bytes, 0, $bytes.Length)
                    $stream.Flush()
                } finally {
                    $stream.Dispose()
                }
            } else {
                $destinationBytes = [IO.File]::ReadAllBytes($destinationPath)
                $hashAlgorithm = [Security.Cryptography.SHA256]::Create()
                try {
                    $sourceHash = [BitConverter]::ToString(
                        $hashAlgorithm.ComputeHash($bytes)
                    )
                    $destinationHash = [BitConverter]::ToString(
                        $hashAlgorithm.ComputeHash($destinationBytes)
                    )
                } finally {
                    $hashAlgorithm.Dispose()
                }
                if ($sourceHash -ne $destinationHash) {
                    throw "Registry event collision detected at '$destinationPath'."
                }
            }
            Remove-Item -LiteralPath $eventFile.FullName -Force -ErrorAction Stop
        } catch {
            Write-Warning "VMHelper registry publication remains pending for '$($eventFile.Name)': $($_.Exception.Message)"
            break
        }
    }
}

function Sync-VMResourceTransferRegistry {
    <#
    .SYNOPSIS
    Retries pending append-only VMHelper registry event publication.
    .DESCRIPTION
    Publishes JSON events from a durable transfer's local RegistryOutbox to the
    configured DFS namespace. Publication failures remain queued and do not
    alter VM transaction state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('TransferRoot')]
        [string]$TransactionRoot
    )

    process {
        $activity = Start-DTMSActivity `
            -Name 'VM transfer registry synchronization' `
            -Intent 'Publish pending immutable transfer events' `
            -Target $TransactionRoot
        Publish-PendingVMResourceRegistryEvent -TransactionRoot $TransactionRoot
        $outboxPath = Join-Path $TransactionRoot 'RegistryOutbox'
        $pendingCount = if (Test-Path -LiteralPath $outboxPath -PathType Container) {
            @(Get-ChildItem -LiteralPath $outboxPath -Filter '*.json' -File).Count
        } else {
            0
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status "$pendingCount registry event(s) remain pending."
        $statePath = Join-Path $TransactionRoot 'State.json'
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            foreach ($stateProperty in @{
                RegistryPendingEventCount = $pendingCount
                RegistryPublicationPending = $pendingCount -gt 0
            }.GetEnumerator()) {
                if ($null -eq $state.PSObject.Properties[$stateProperty.Key]) {
                    $state | Add-Member `
                        -MemberType NoteProperty `
                        -Name $stateProperty.Key `
                        -Value $stateProperty.Value
                } else {
                    $state.($stateProperty.Key) = $stateProperty.Value
                }
            }
            $temporaryStatePath = "$statePath.tmp"
            $state | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $temporaryStatePath -Encoding UTF8
            Move-Item -LiteralPath $temporaryStatePath -Destination $statePath -Force
        }
        [pscustomobject]@{
            PSTypeName = 'VMHelper.RegistrySyncResult'
            TransactionRoot = $TransactionRoot
            RegistryNamespace = $script:VMHelperRegistryConfiguration.NamespacePath
            RegistryAvailable = $script:VMHelperRegistryConfiguration.Enabled
            PendingEventCount = $pendingCount
            Synchronized = $pendingCount -eq 0
        }
    }
}

function Write-VMResourceRegistryEvent {
    param(
        [Parameter(Mandatory)]
        [string]$TransactionRoot,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$State,

        [Parameter(Mandatory)]
        [string]$Phase,

        [string]$Message,

        [Nullable[double]]$ProgressPercent
    )

    if ([string]::IsNullOrWhiteSpace($script:VMHelperRegistryConfiguration.NamespacePath)) {
        return
    }
    $eventId = [guid]::NewGuid().ToString('N')
    $sequence = [int]$State.RegistrySequence
    $eventType = switch ($Phase) {
        'Completed' { 'TransferCompleted' }
        'Failed' { 'TransferFailed' }
        'RolledBack' { 'TransferRolledBack' }
        'RollbackFailed' { 'TransferRollbackFailed' }
        default { 'PhaseChanged' }
    }
    $status = switch ($Phase) {
        'Completed' { 'Completed' }
        { $_ -in @('Failed', 'RolledBack', 'RollbackFailed') } { 'Failed' }
        default { 'Running' }
    }
    $getStateValue = {
        param($Name, $DefaultValue)
        if ($State.Contains($Name)) {
            return $State[$Name]
        }
        $DefaultValue
    }
    $registryEvent = [ordered]@{
        schemaVersion = 1
        transferId = & $getStateValue 'TransferId' (Split-Path $TransactionRoot -Leaf)
        sequence = $sequence
        eventId = $eventId
        eventType = $eventType
        status = $status
        phase = $Phase
        recordedUtc = [DateTime]::UtcNow.ToString('o')
        attempt = [int](& $getStateValue 'AttemptCount' 0)
        sourceVMName = & $getStateValue 'SourceVMName' $null
        targetVMName = & $getStateValue 'TargetVMName' $null
        sourceHostName = & $getStateValue 'SourceHostName' $null
        targetHostName = & $getStateValue 'TargetHostName' $null
        writerHostName = $env:COMPUTERNAME
        progressPercent = if ($Phase -eq 'Completed') {
            100
        } elseif ($null -ne $ProgressPercent) {
            [math]::Round([double]$ProgressPercent, 2)
        } else {
            $null
        }
        message = $Message
    }
    $outboxPath = Join-Path $TransactionRoot 'RegistryOutbox'
    New-Item -Path $outboxPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $eventName = '{0:D8}-{1}-{2}.json' -f $sequence, $eventType, $eventId
    $eventPath = Join-Path $outboxPath $eventName
    $temporaryPath = "$eventPath.tmp"
    $registryEvent | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $eventPath -Force
    Publish-PendingVMResourceRegistryEvent -TransactionRoot $TransactionRoot
}

function Invoke-VMResourceRegistryRetention {
    if (-not $script:VMHelperRegistryConfiguration.Enabled) {
        return
    }
    if (Get-Command Invoke-DurableOperationRegistryRetention -ErrorAction SilentlyContinue) {
        Invoke-DurableOperationRegistryRetention `
            -NamespacePath $script:VMHelperRegistryConfiguration.NamespacePath `
            -RetentionCount $script:VMHelperRegistryConfiguration.RetentionCount `
            -Confirm:$false
        return
    }
    try {
        $terminalTransfers = @(
            Get-ChildItem `
                -LiteralPath $script:VMHelperRegistryConfiguration.NamespacePath `
                -Directory `
                -ErrorAction Stop |
                ForEach-Object {
                    $eventsPath = Join-Path $_.FullName 'Events'
                    $registryEvents = @(Get-ChildItem `
                        -LiteralPath $eventsPath `
                        -Filter '*.json' `
                        -File `
                        -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            try {
                                Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                            } catch {
                                Write-Warning "Ignoring invalid registry event during retention: $($_.FullName)"
                            }
                        } |
                        Sort-Object { [long]$_.sequence })
                    if ($registryEvents.Count -eq 0) {
                        return
                    }
                    $completed = @($registryEvents | Where-Object eventType -eq 'TransferCompleted')
                    $currentEvent = if ($completed.Count -gt 0) {
                        $completed | Sort-Object { [long]$_.sequence } -Descending |
                            Select-Object -First 1
                    } else {
                        $registryEvents[-1]
                    }
                    if ($currentEvent.status -in @('Completed', 'Failed', 'Cancelled')) {
                        [pscustomobject]@{
                            Directory = $_
                            TerminalEvent = $currentEvent
                        }
                    }
                } |
                Sort-Object { [datetime]$_.TerminalEvent.recordedUtc } -Descending
        )
        foreach ($expiredTransfer in @(
            $terminalTransfers |
                Select-Object -Skip $script:VMHelperRegistryConfiguration.RetentionCount
        )) {
            Remove-Item `
                -LiteralPath $expiredTransfer.Directory.FullName `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }
    } catch {
        Write-Warning "VMHelper registry retention could not complete: $($_.Exception.Message)"
    }
}

function Write-VMResourceTransferPhase {
    param(
        [Parameter(Mandatory)]
        [string]$TransactionRoot,

        [Parameter(Mandatory)]
        [ValidateSet(
            'Preflight',
            'StoppingVMs',
            'CapturingConfiguration',
            'CopyingDisks',
            'RelinkingDisks',
            'ApplyingTargetConfiguration',
            'Verifying',
            'RollingBack',
            'RolledBack',
            'RollbackFailed',
            'RestoringTargetState',
            'Failed',
            'Completed'
        )]
        [string]$Phase,

        [string]$Message,

        [Nullable[double]]$ProgressPercent
    )

    $statePath = Join-Path $TransactionRoot 'State.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Durable transfer state was not found: $statePath"
    }
    $stateObject = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state = [ordered]@{}
    foreach ($property in $stateObject.PSObject.Properties) {
        $state[$property.Name] = $property.Value
    }
    $timestamp = [DateTime]::UtcNow.ToString('o')
    $history = @($state.PhaseHistory)
    if ($state.CurrentPhase -ne $Phase) {
        $history += [pscustomobject]@{
            Phase = $Phase
            EnteredUtc = $timestamp
            Message = $Message
        }
    }
    $state.CurrentPhase = $Phase
    $state.PhaseHistory = $history
    $state.UpdatedUtc = $timestamp
    if (-not $state.Contains('RegistrySequence')) {
        $state.RegistrySequence = 0
    }
    if (-not [string]::IsNullOrWhiteSpace($script:VMHelperRegistryConfiguration.NamespacePath)) {
        $state.RegistrySequence = [int]$state.RegistrySequence + 1
    }
    if ($Message) {
        $state.Message = $Message
    }
    if ($null -ne $ProgressPercent) {
        $state.ProgressPercent = [math]::Round([double]$ProgressPercent, 2)
    }
    $temporaryPath = "$statePath.tmp"
    $state | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
    if (-not [string]::IsNullOrWhiteSpace($script:VMHelperRegistryConfiguration.NamespacePath)) {
        try {
            Write-VMResourceRegistryEvent `
                -TransactionRoot $TransactionRoot `
                -State $state `
                -Phase $Phase `
                -Message $Message `
                -ProgressPercent $ProgressPercent
            if ($Phase -eq 'Completed') {
                Invoke-VMResourceRegistryRetention
            }
        } catch {
            $state.RegistryPublicationPending = $true
            Write-Warning "VMHelper registry event creation failed without interrupting the VM transaction: $($_.Exception.Message)"
        }
        $outboxPath = Join-Path $TransactionRoot 'RegistryOutbox'
        $pendingEventCount = if (Test-Path -LiteralPath $outboxPath -PathType Container) {
            @(Get-ChildItem -LiteralPath $outboxPath -Filter '*.json' -File).Count
        } else {
            0
        }
        $state.RegistryPendingEventCount = $pendingEventCount
        $state.RegistryPublicationPending = $pendingEventCount -gt 0
        $state | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
    }
}

function Start-DurableVMResourceTransfer {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SourceVMName,

        [Parameter(Mandatory)]
        [string]$TargetVMName,

        [Parameter(Mandatory)]
        [string]$SourceHostName,

        [Parameter(Mandatory)]
        [string]$TargetHostName,

        [Parameter(Mandatory)]
        [string[]]$Resource,

        [string]$DestinationVhdRoot,

        [Parameter(Mandatory)]
        [string]$DurableTransferRoot,

        [pscredential]$SourceCredential,

        [pscredential]$TargetCredential,

        [pscredential]$TransferCredential,

        [string]$TransferAccount,

        [ValidateSet('Auto', 'Robocopy', 'Scp', 'Bits')]
        [string]$TransferTransport = 'Robocopy',

        [string]$ScpSourceEndpoint,

        [string]$ScpIdentityFile,

        [bool]$TurnOff
    )

    if (-not $PSCmdlet.ShouldProcess($TargetHostName, 'register and start durable VM resource transfer')) {
        return
    }
    if ($TransferCredential -and $TransferAccount) {
        throw 'Specify either TransferCredential or TransferAccount, not both.'
    }
    if (-not $TransferCredential -and [string]::IsNullOrWhiteSpace($TransferAccount)) {
        throw 'Cross-host hard-drive copies require TransferCredential or a gMSA TransferAccount.'
    }
    if ($TransferAccount -and -not $TransferAccount.EndsWith('$')) {
        throw "TransferAccount '$TransferAccount' must be a group managed service account ending in '$'. Use TransferCredential for a normal domain account."
    }
    if ($TransferTransport -eq 'Scp' -and [string]::IsNullOrWhiteSpace($ScpSourceEndpoint)) {
        throw 'Scp transport requires ScpSourceEndpoint in user@host form.'
    }

    $executionAccount = if ($TransferCredential) {
        $TransferCredential.UserName
    } else {
        $TransferAccount
    }
    $transferId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N')
    $transferRoot = Join-Path $DurableTransferRoot $transferId
    $taskName = "VMHelper-ResourceTransfer-$transferId"
    $sourceSession = $null
    $targetSession = $null
    try {
        $sourceSession = Open-RemoteSession -ComputerName $SourceHostName -Credential $SourceCredential
        $targetSession = Open-RemoteSession -ComputerName $TargetHostName -Credential $TargetCredential
        $sourceSummary = Invoke-Command -Session $sourceSession -ArgumentList $SourceVMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            [pscustomobject]@{
                Id = [string]$vm.Id
                State = [string]$vm.State
            }
        }
        $targetSummary = Invoke-Command -Session $targetSession -ArgumentList $TargetVMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            [pscustomobject]@{
                Id = [string]$vm.Id
                State = [string]$vm.State
            }
        }
        if ($sourceSummary.Id -eq $targetSummary.Id) {
            throw 'Source and target VMs must have different VM IDs.'
        }
        if ($targetSummary.State -notin @('Running', 'Off')) {
            throw "Target VM must be Running or Off; current state is '$($targetSummary.State)'."
        }
        Invoke-Command -Session $targetSession -ArgumentList $transferRoot, $executionAccount -ScriptBlock {
            param($Root, $Account)
            New-Item -Path $Root -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $acl = Get-Acl -LiteralPath $Root
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($rule in @($acl.Access)) {
                [void]$acl.RemoveAccessRuleSpecific($rule)
            }
            foreach ($identityName in @('SYSTEM', 'BUILTIN\Administrators', $Account)) {
                $identity = [Security.Principal.NTAccount]::new($identityName)
                $rule = [Security.AccessControl.FileSystemAccessRule]::new(
                    $identity,
                    'FullControl',
                    'ContainerInherit,ObjectInherit',
                    'None',
                    'Allow'
                )
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $Root -AclObject $acl
        }

        foreach ($moduleFile in @('DTMS.VMHelper.psm1', 'DTMS.VMHelper.psd1')) {
            Copy-Item -ToSession $targetSession `
                -LiteralPath (Join-Path $PSScriptRoot $moduleFile) `
                -Destination $transferRoot `
                -Force `
                -ErrorAction Stop
        }
        $sharedModulesRoot = Join-Path $transferRoot 'Modules'
        Invoke-Command -Session $targetSession -ArgumentList $sharedModulesRoot -ScriptBlock {
            param($Path)
            New-Item $Path -ItemType Directory -Force | Out-Null
        }
        foreach ($sharedModuleName in @('DTMS.Transfer', 'DTMS.Runway.Dfs')) {
            $sharedModule = Get-Module $sharedModuleName -ErrorAction SilentlyContinue
            if ($sharedModule) {
                $sharedDestination = Join-Path $sharedModulesRoot $sharedModuleName
                Invoke-Command -Session $targetSession -ArgumentList $sharedDestination -ScriptBlock {
                    param($Path)
                    New-Item $Path -ItemType Directory -Force | Out-Null
                }
                foreach ($sharedFile in @(Get-ChildItem $sharedModule.ModuleBase -File)) {
                    Copy-Item -ToSession $targetSession `
                        -LiteralPath $sharedFile.FullName `
                        -Destination $sharedDestination `
                        -Force
                }
            }
        }

        $configuration = [ordered]@{
            TransferId = $transferId
            SourceVMName = $SourceVMName
            TargetVMName = $TargetVMName
            SourceHostName = $SourceHostName
            TargetHostName = $TargetHostName
            Resource = @($Resource)
            DestinationVhdRoot = $DestinationVhdRoot
            TransferTransport = $TransferTransport
            ScpSourceEndpoint = $ScpSourceEndpoint
            ScpIdentityFile = $ScpIdentityFile
            TurnOff = $TurnOff
            RestoreTargetRunning = $targetSummary.State -eq 'Running'
        }
        $state = [ordered]@{
            TransferId = $transferId
            Status = 'Queued'
            SourceVMName = $SourceVMName
            TargetVMName = $TargetVMName
            SourceHostName = $SourceHostName
            TargetHostName = $TargetHostName
            ExecutionAccount = $executionAccount
            CreatedUtc = [DateTime]::UtcNow.ToString('o')
            StartedUtc = $null
            LastAttemptStartedUtc = $null
            AttemptCount = 0
            RegistrySequence = 0
            RegistryPublicationPending = $false
            RegistryPendingEventCount = 0
            CompletedUtc = $null
            UpdatedUtc = [DateTime]::UtcNow.ToString('o')
            CurrentPhase = 'Queued'
            PhaseHistory = @(
                [pscustomobject]@{
                    Phase = 'Queued'
                    EnteredUtc = [DateTime]::UtcNow.ToString('o')
                    Message = 'Transfer is waiting for the scheduled worker.'
                }
            )
            Message = $null
        }
        $workerScript = @'
param([Parameter(Mandatory)][string]$TransferRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-TransferState {
    param([hashtable]$State)
    $State.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    $statePath = Join-Path $TransferRoot 'State.json'
    $temporaryPath = "$statePath.tmp"
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
}

$statePath = Join-Path $TransferRoot 'State.json'
$stateObject = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($stateObject.Status -eq 'Completed') {
    $sharedModulesRoot = Join-Path $TransferRoot 'Modules'
    foreach ($sharedManifest in @(Get-ChildItem $sharedModulesRoot -Filter '*.psd1' -Recurse -ErrorAction SilentlyContinue)) {
        Import-Module $sharedManifest.FullName -Force -ErrorAction Stop
    }
    Import-Module (Join-Path $TransferRoot 'DTMS.VMHelper.psd1') -ArgumentList 'Quiet' -Force -ErrorAction Stop
    Sync-VMResourceTransferRegistry -TransactionRoot $TransferRoot | Out-Null
    return
}
$state = @{}
foreach ($property in $stateObject.PSObject.Properties) {
    $state[$property.Name] = $property.Value
}
$state.Status = 'Running'
$attemptStartedUtc = [DateTime]::UtcNow.ToString('o')
if (-not $state.StartedUtc) {
    $state.StartedUtc = $attemptStartedUtc
}
$state.LastAttemptStartedUtc = $attemptStartedUtc
$state.AttemptCount = [int]$state.AttemptCount + 1
$state.Message = $null
Write-TransferState -State $state

$transcriptPath = Join-Path $TransferRoot 'Transcript.log'
$transcriptStarted = $false
try {
    Start-Transcript -Path $transcriptPath -Append | Out-Null
    $transcriptStarted = $true
    Import-Module (Join-Path $TransferRoot 'DTMS.VMHelper.psd1') -Force -ErrorAction Stop
    $configuration = Get-Content -LiteralPath (Join-Path $TransferRoot 'Configuration.json') -Raw |
        ConvertFrom-Json
    $parameters = @{
        SourceVMName = $configuration.SourceVMName
        TargetVMName = $configuration.TargetVMName
        SourceHostName = $configuration.SourceHostName
        TargetHostName = $configuration.TargetHostName
        Resource = @($configuration.Resource)
        DurableWorker = $true
        TransferId = $configuration.TransferId
        TransferLogPath = (Join-Path $TransferRoot 'Transfer.log')
        TransactionRoot = $TransferRoot
        TransferTransport = [string]$configuration.TransferTransport
        Confirm = $false
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$configuration.ScpSourceEndpoint)) {
        $parameters.ScpSourceEndpoint = [string]$configuration.ScpSourceEndpoint
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$configuration.ScpIdentityFile)) {
        $parameters.ScpIdentityFile = [string]$configuration.ScpIdentityFile
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$configuration.DestinationVhdRoot)) {
        $parameters.DestinationVhdRoot = [string]$configuration.DestinationVhdRoot
    }
    if ([bool]$configuration.TurnOff) {
        $parameters.TurnOff = $true
    }
    if ([bool]$configuration.RestoreTargetRunning) {
        $parameters.RestoreTargetRunning = $true
    }
    $result = Copy-VMResource @parameters
    Sync-VMResourceTransferRegistry -TransactionRoot $TransferRoot | Out-Null
    $result | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $TransferRoot 'Result.json') -Encoding UTF8
    $stateObject = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state = @{}
    foreach ($property in $stateObject.PSObject.Properties) {
        $state[$property.Name] = $property.Value
    }
    $state.Status = 'Completed'
    $state.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $state.Message = 'Transfer completed successfully.'
    Write-TransferState -State $state
} catch {
    $stateObject = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state = @{}
    foreach ($property in $stateObject.PSObject.Properties) {
        $state[$property.Name] = $property.Value
    }
    $state.Status = 'Failed'
    $state.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $state.Message = $_.Exception.Message
    Write-TransferState -State $state
    throw
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
'@
        Invoke-Command -Session $targetSession -ArgumentList (
            $transferRoot,
            ($configuration | ConvertTo-Json -Depth 10),
            ($state | ConvertTo-Json -Depth 10),
            $workerScript,
            $taskName,
            $executionAccount,
            $TransferCredential
        ) -ScriptBlock {
            param(
                $Root,
                $ConfigurationJson,
                $StateJson,
                $Worker,
                $TaskName,
                $Account,
                [pscredential]$Credential
            )
            $configurationPath = Join-Path $Root 'Configuration.json'
            $statePath = Join-Path $Root 'State.json'
            $workerPath = Join-Path $Root 'Invoke-Transfer.ps1'
            Set-Content -LiteralPath $configurationPath -Value $ConfigurationJson -Encoding UTF8
            Set-Content -LiteralPath $statePath -Value $StateJson -Encoding UTF8
            Set-Content -LiteralPath $workerPath -Value $Worker -Encoding UTF8

            $powerShellPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
            if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
                $powerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            }
            $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -TransferRoot "{1}"' -f $workerPath, $Root
            $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $settings = New-ScheduledTaskSettingsSet `
                -StartWhenAvailable `
                -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit ([TimeSpan]::Zero) `
                -RestartCount 3 `
                -RestartInterval (New-TimeSpan -Minutes 1)
            if ($Credential) {
                Register-ScheduledTask `
                    -TaskName $TaskName `
                    -Action $action `
                    -Trigger $trigger `
                    -Settings $settings `
                    -User $Account `
                    -Password $Credential.GetNetworkCredential().Password `
                    -RunLevel Highest `
                    -Force | Out-Null
            } else {
                $principal = New-ScheduledTaskPrincipal `
                    -UserId $Account `
                    -LogonType Password `
                    -RunLevel Highest
                Register-ScheduledTask `
                    -TaskName $TaskName `
                    -Action $action `
                    -Trigger $trigger `
                    -Settings $settings `
                    -Principal $principal `
                    -Force | Out-Null
            }
            Start-ScheduledTask -TaskName $TaskName
        }

        [pscustomobject]@{
            PSTypeName = 'VMHelper.ResourceTransfer'
            TransferId = $transferId
            Status = 'Queued'
            SourceHostName = $SourceHostName
            TargetHostName = $TargetHostName
            TaskName = $taskName
            TransferRoot = $transferRoot
            ExecutionAccount = $executionAccount
            StatusCommand = "Get-VMResourceTransfer -TransferId '$transferId'"
        }
    } finally {
        Close-RemoteSession -Session @($sourceSession, $targetSession)
    }
}

function Get-VMResourceTransferFromRegistry {
    param(
        [string]$TransferId,
        [string]$SourceVMName,
        [string]$TargetVMName,
        [string[]]$Status,
        [bool]$Active,
        [bool]$Latest
    )

    if (-not [string]::IsNullOrWhiteSpace(
        $script:VMHelperRegistryConfiguration.NamespacePath
    ) -and (Test-VMHelperPathAvailability `
        -Path $script:VMHelperRegistryConfiguration.NamespacePath `
        -PathType Container)) {
        $script:VMHelperRegistryConfiguration.Enabled = $true
    }
    if (-not $script:VMHelperRegistryConfiguration.Enabled) {
        throw 'The distributed VMHelper transfer registry is not configured or unavailable. Specify -TargetHostName to query target-local state.'
    }
    $roots = if ($TransferId) {
        $exactRoot = Join-Path $script:VMHelperRegistryConfiguration.NamespacePath $TransferId
        if (-not (Test-VMHelperPathAvailability -Path $exactRoot -PathType Container)) {
            throw "Transfer '$TransferId' was not found in '$($script:VMHelperRegistryConfiguration.NamespacePath)'."
        }
        @(Get-Item -LiteralPath $exactRoot)
    } else {
        @(Get-ChildItem `
            -LiteralPath $script:VMHelperRegistryConfiguration.NamespacePath `
            -Directory `
            -ErrorAction Stop)
    }
    $transfers = @($roots | ForEach-Object {
        $eventsPath = Join-Path $_.FullName 'Events'
        if (-not (Test-Path -LiteralPath $eventsPath -PathType Container)) {
            return
        }
        $events = @(Get-ChildItem -LiteralPath $eventsPath -Filter '*.json' -File |
            ForEach-Object {
                try {
                    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                } catch {
                    Write-Warning "Ignoring invalid VMHelper registry event '$($_.FullName)': $($_.Exception.Message)"
                }
            } |
            Group-Object eventId |
            ForEach-Object { $_.Group | Select-Object -First 1 } |
            Sort-Object { [long]$_.sequence }, recordedUtc)
        if ($events.Count -eq 0) {
            return
        }
        $completedEvent = @($events |
            Where-Object eventType -eq 'TransferCompleted' |
            Sort-Object { [long]$_.sequence } -Descending |
            Select-Object -First 1)
        $currentEvent = if ($completedEvent.Count -gt 0) {
            $completedEvent[0]
        } else {
            $events[-1]
        }
        if ($SourceVMName -and $currentEvent.sourceVMName -notlike $SourceVMName) {
            return
        }
        if ($TargetVMName -and $currentEvent.targetVMName -notlike $TargetVMName) {
            return
        }
        if ($null -ne $Status -and
            $Status.Count -gt 0 -and
            $currentEvent.status -notin $Status) {
            return
        }
        if ($Active -and $currentEvent.status -notin @('Queued', 'Running')) {
            return
        }
        $progressEvent = @($events |
            Where-Object { $null -ne $_.progressPercent } |
            Sort-Object { [long]$_.sequence } -Descending |
            Select-Object -First 1)
        $sequences = @($events | ForEach-Object { [long]$_.sequence } | Sort-Object -Unique)
        $historyComplete = if ($sequences.Count -eq 0) {
            $false
        } else {
            $sequences[0] -eq 1 -and $sequences.Count -eq $sequences[-1]
        }
        [pscustomobject]@{
            PSTypeName = 'VMHelper.ResourceTransferStatus'
            TransferId = $currentEvent.transferId
            Status = $currentEvent.status
            CurrentPhase = $currentEvent.phase
            ProgressPercent = if ($progressEvent.Count -gt 0) {
                $progressEvent[0].progressPercent
            } else {
                $null
            }
            TaskState = 'Registry'
            TargetVMName = $currentEvent.targetVMName
            SourceVMName = $currentEvent.sourceVMName
            TargetHostName = $currentEvent.targetHostName
            SourceHostName = $currentEvent.sourceHostName
            AttemptCount = $currentEvent.attempt
            UpdatedUtc = $currentEvent.recordedUtc
            CreatedUtc = $events[0].recordedUtc
            StartedUtc = $events[0].recordedUtc
            LastAttemptStartedUtc = $null
            CompletedUtc = if ($currentEvent.status -eq 'Completed') {
                $currentEvent.recordedUtc
            } else {
                $null
            }
            ExecutionAccount = $null
            PhaseHistory = @($events | ForEach-Object {
                [pscustomobject]@{
                    Sequence = $_.sequence
                    Phase = $_.phase
                    EnteredUtc = $_.recordedUtc
                    Message = $_.message
                }
            })
            Message = $currentEvent.message
            TransferRoot = $_.FullName
            TranscriptPath = $null
            RobocopyLogPath = $null
            RecentRobocopyOutput = @()
            TransferProvider = $null
            BytesTransferred = $null
            BytesTotal = $null
            InstantaneousMbps = $null
            AverageMbps = $null
            EstimatedRemainingSeconds = $null
            MetricsPath = $null
            Result = $null
            RegistryHistoryComplete = $historyComplete
            RegistryEventCount = $events.Count
            RegistryPublicationPending = $false
            RegistryPendingEventCount = 0
        }
    } | Sort-Object { [datetime]$_.CreatedUtc } -Descending)
    if ($Latest) {
        $transfers | Select-Object -First 1
    } else {
        $transfers
    }
}

function Add-VMResourceTransferDefaultDisplay {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )

    process {
        $InputObject.PSObject.TypeNames.Insert(0, 'VMHelper.ResourceTransferStatus')
        $defaultDisplay = [Management.Automation.PSPropertySet]::new(
            'DefaultDisplayPropertySet',
            [string[]]@(
                'TransferId',
                'Status',
                'CurrentPhase',
                'ProgressPercent',
                'TransferProvider',
                'AverageMbps',
                'TargetVMName',
                'AttemptCount',
                'UpdatedUtc'
            )
        )
        $InputObject | Add-Member `
            -MemberType MemberSet `
            -Name PSStandardMembers `
            -Value ([Management.Automation.PSMemberInfo[]]@($defaultDisplay)) `
            -Force
        $InputObject
    }
}

function Get-VMResourceTransfer {
    <#
    .SYNOPSIS
    Lists or gets durable VM resource transfers from a target Hyper-V host.
    .DESCRIPTION
    Lists every persisted transfer when TransferId is omitted. Results are
    newest first and include phase, scheduled-task state, attempt count, and
    best-effort Robocopy percentage. Use filters to find active transfers or a
    particular source or target VM.
    .PARAMETER TransferId
    Exact transfer identifier. Omit it to list transfers.
    .PARAMETER Active
    Returns only queued or running transfers.
    .PARAMETER Latest
    Returns only the newest transfer after applying other filters.
    .EXAMPLE
    Get-VMResourceTransfer -TargetHostName 'hv02'
    .EXAMPLE
    Get-VMResourceTransfer -TargetHostName 'hv02' -Active
    .EXAMPLE
    Get-VMResourceTransfer -TargetHostName 'hv02' -TargetVMName 'SQL*' -Latest
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$TransferId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetHostName,

        [ValidateNotNullOrEmpty()]
        [string]$DurableTransferRoot = "$env:ProgramData\VMHelper\Transfers",

        [pscredential]$Credential,

        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string]$SourceVMName,

        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string]$TargetVMName,

        [ValidateSet('Queued', 'Running', 'Completed', 'Failed')]
        [string[]]$Status,

        [switch]$Active,

        [switch]$Latest
    )

    process {
        if ([string]::IsNullOrWhiteSpace($TargetHostName)) {
            Get-VMResourceTransferFromRegistry `
                -TransferId $TransferId `
                -SourceVMName $SourceVMName `
                -TargetVMName $TargetVMName `
                -Status $Status `
                -Active $Active.IsPresent `
                -Latest $Latest.IsPresent |
                Add-VMResourceTransferDefaultDisplay
            return
        }
        $session = $null
        try {
            $session = Open-RemoteSession -ComputerName $TargetHostName -Credential $Credential
            $statusFilter = if ($null -ne $Status -and $Status.Count -gt 0) {
                $Status -join ','
            } else {
                $null
            }
            $remoteResults = @(Invoke-Command -Session $session -ArgumentList (
                $TransferId,
                $DurableTransferRoot,
                $SourceVMName,
                $TargetVMName,
                $statusFilter,
                $Active.IsPresent,
                $Latest.IsPresent
            ) -ScriptBlock {
                param(
                    $Id,
                    $BaseRoot,
                    $SourceName,
                    $TargetName,
                    $RequestedStatus,
                    $OnlyActive,
                    $OnlyLatest
                )
                if (-not (Test-Path -LiteralPath $BaseRoot -PathType Container)) {
                    return
                }
                $transferRoots = if ($Id) {
                    $exactRoot = Join-Path $BaseRoot $Id
                    if (-not (Test-Path -LiteralPath $exactRoot -PathType Container)) {
                        throw "Transfer '$Id' was not found at '$exactRoot'."
                    }
                    @(Get-Item -LiteralPath $exactRoot)
                } else {
                    @(Get-ChildItem -LiteralPath $BaseRoot -Directory -ErrorAction Stop)
                }

                $transfers = @($transferRoots | ForEach-Object {
                    $root = $_.FullName
                    $statePath = Join-Path $root 'State.json'
                    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
                        Write-Error "Transfer directory '$root' has no State.json file."
                        return
                    }
                    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                    $stateDefaults = @{
                        TransferId = $_.Name
                        Status = 'Unknown'
                        CurrentPhase = $null
                        SourceVMName = $null
                        TargetVMName = $null
                        SourceHostName = $null
                        TargetHostName = $null
                        AttemptCount = 0
                        CreatedUtc = $_.CreationTimeUtc.ToString('o')
                        UpdatedUtc = $_.LastWriteTimeUtc.ToString('o')
                        StartedUtc = $null
                        LastAttemptStartedUtc = $null
                        CompletedUtc = $null
                        ExecutionAccount = $null
                        PhaseHistory = @()
                        Message = $null
                        RegistryPublicationPending = $false
                        RegistryPendingEventCount = 0
                    }
                    foreach ($propertyName in $stateDefaults.Keys) {
                        if ($null -eq $state.PSObject.Properties[$propertyName]) {
                            $state | Add-Member `
                                -MemberType NoteProperty `
                                -Name $propertyName `
                                -Value $stateDefaults[$propertyName]
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$state.CurrentPhase)) {
                        $state.CurrentPhase = $state.Status
                    }
                    if ($SourceName -and $state.SourceVMName -notlike $SourceName) {
                        return
                    }
                    if ($TargetName -and $state.TargetVMName -notlike $TargetName) {
                        return
                    }
                    if ($RequestedStatus -and
                        $state.Status -notin @($RequestedStatus -split ',')) {
                        return
                    }
                    if ($OnlyActive -and $state.Status -notin @('Queued', 'Running')) {
                        return
                    }

                    $task = Get-ScheduledTask `
                        -TaskName "VMHelper-ResourceTransfer-$($state.TransferId)" `
                        -ErrorAction SilentlyContinue
                    $resultPath = Join-Path $root 'Result.json'
                    $robocopyLogPath = Join-Path $root 'Robocopy.log'
                    $transferLogPath = Join-Path $root 'Transfer.log'
                    $metricsPath = Join-Path $root 'TransferMetrics.jsonl'
                    $recentRobocopyOutput = @()
                    $latestMetric = @(if (Test-Path -LiteralPath $metricsPath -PathType Leaf) {
                        Get-Content -LiteralPath $metricsPath -Tail 20 |
                            ForEach-Object {
                                try {
                                    $_ | ConvertFrom-Json
                                } catch {
                                    $null
                                }
                            } |
                            Where-Object { $null -ne $_ } |
                            Select-Object -Last 1
                    })
                    $progressPercent = if ($latestMetric.Count -gt 0 -and
                        $null -ne $latestMetric[0].operationPercentComplete) {
                        [double]$latestMetric[0].operationPercentComplete
                    } elseif ($state.Status -eq 'Completed') {
                        100
                    } elseif (Test-Path -LiteralPath $robocopyLogPath -PathType Leaf) {
                        $recentRobocopyOutput = @(
                            Get-Content -LiteralPath $robocopyLogPath -Tail 40 |
                                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        )
                        $percentageMatches = [regex]::Matches(
                            ($recentRobocopyOutput -join [Environment]::NewLine),
                            '(?<!\d)(?<Percent>\d{1,3}(?:\.\d+)?)%'
                        )
                        if ($percentageMatches.Count -gt 0) {
                            [double]$percentageMatches[$percentageMatches.Count - 1].Groups['Percent'].Value
                        }
                    }
                    $aggregateAverageMbps = if ($latestMetric.Count -gt 0 -and
                        $state.StartedUtc) {
                        $endTime = if ($state.CompletedUtc) {
                            [datetime]$state.CompletedUtc
                        } else {
                            [DateTime]::UtcNow
                        }
                        $elapsedSeconds = [math]::Max(
                            0.001,
                            ($endTime - [datetime]$state.StartedUtc).TotalSeconds
                        )
                        [math]::Round(
                            ([long]$latestMetric[0].operationBytesTransferred * 8 / 1000000) /
                                $elapsedSeconds,
                            3
                        )
                    } else {
                        $null
                    }
                    $aggregateRemainingSeconds = if (
                        $latestMetric.Count -gt 0 -and
                        $aggregateAverageMbps -gt 0 -and
                        [long]$latestMetric[0].operationBytesTotal -gt
                            [long]$latestMetric[0].operationBytesTransferred
                    ) {
                        [math]::Round(
                            (
                                (
                                    [long]$latestMetric[0].operationBytesTotal -
                                    [long]$latestMetric[0].operationBytesTransferred
                                ) * 8 / 1000000
                            ) / $aggregateAverageMbps,
                            1
                        )
                    } else {
                        $null
                    }
                    [pscustomobject]@{
                        PSTypeName = 'VMHelper.ResourceTransferStatus'
                        TransferId = $state.TransferId
                        Status = $state.Status
                        CurrentPhase = $state.CurrentPhase
                        ProgressPercent = $progressPercent
                        TaskState = if ($task) { [string]$task.State } else { 'NotFound' }
                        TargetVMName = $state.TargetVMName
                        SourceVMName = $state.SourceVMName
                        TargetHostName = $state.TargetHostName
                        SourceHostName = $state.SourceHostName
                        AttemptCount = $state.AttemptCount
                        UpdatedUtc = $state.UpdatedUtc
                        CreatedUtc = $state.CreatedUtc
                        StartedUtc = $state.StartedUtc
                        LastAttemptStartedUtc = $state.LastAttemptStartedUtc
                        CompletedUtc = $state.CompletedUtc
                        ExecutionAccount = $state.ExecutionAccount
                        PhaseHistory = @($state.PhaseHistory)
                        Message = $state.Message
                        RegistryPublicationPending = $state.RegistryPublicationPending
                        RegistryPendingEventCount = $state.RegistryPendingEventCount
                        TransferRoot = $root
                        TranscriptPath = Join-Path $root 'Transcript.log'
                        RobocopyLogPath = $robocopyLogPath
                        RecentRobocopyOutput = $recentRobocopyOutput
                        TransferLogPath = $transferLogPath
                        MetricsPath = $metricsPath
                        TransferProvider = if ($latestMetric.Count) {
                            $latestMetric[0].provider
                        } else {
                            $null
                        }
                        BytesTransferred = if ($latestMetric.Count) {
                            $latestMetric[0].operationBytesTransferred
                        } else {
                            $null
                        }
                        BytesTotal = if ($latestMetric.Count) {
                            $latestMetric[0].operationBytesTotal
                        } else {
                            $null
                        }
                        InstantaneousMbps = if ($latestMetric.Count) {
                            $latestMetric[0].instantaneousMbps
                        } else {
                            $null
                        }
                        AverageMbps = $aggregateAverageMbps
                        EstimatedRemainingSeconds = $aggregateRemainingSeconds
                        Result = if (Test-Path -LiteralPath $resultPath) {
                            Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                        } else {
                            $null
                        }
                    }
                } | Sort-Object { [datetime]$_.CreatedUtc } -Descending)

                if ($OnlyLatest) {
                    $transfers | Select-Object -First 1
                } else {
                    $transfers
                }
            })
            foreach ($remoteResult in $remoteResults) {
                $remoteResult | Add-VMResourceTransferDefaultDisplay
            }
        } finally {
            Close-RemoteSession -Session @($session)
        }
    }
}

function Get-VMResourceTransferHistory {
    <#
    .SYNOPSIS
    Gets durable VM transfer history from one or more target hosts.
    .DESCRIPTION
    Provides an explicit history-oriented wrapper over Get-VMResourceTransfer.
    Results include normalized transport performance when target-local metrics
    are available.
    #>
    [CmdletBinding(DefaultParameterSetName = 'TargetHost')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'TargetHost')]
        [string[]]$TargetHostName,

        [Parameter(Mandatory, ParameterSetName = 'Federated')]
        [string[]]$UtilityServer,

        [string]$TransferId,

        [pscredential]$Credential,

        [string]$SourceVMName,

        [string]$TargetVMName,

        [ValidateSet('Queued', 'Running', 'Completed', 'Failed')]
        [string[]]$Status,

        [string]$DurableTransferRoot = "$env:ProgramData\VMHelper\Transfers"
    )

    if ($PSCmdlet.ParameterSetName -eq 'Federated') {
        Get-VMResourceTransferFederated `
            -UtilityServer $UtilityServer `
            -TransferId $TransferId `
            -Credential $Credential `
            -Status $Status |
            Where-Object {
                (-not $SourceVMName -or $_.SourceVMName -like $SourceVMName) -and
                (-not $TargetVMName -or $_.TargetVMName -like $TargetVMName)
            }
    } else {
        foreach ($hostName in $TargetHostName) {
            Get-VMResourceTransfer `
                -TargetHostName $hostName `
                -TransferId $TransferId `
                -Credential $Credential `
                -SourceVMName $SourceVMName `
                -TargetVMName $TargetVMName `
                -Status $Status `
                -DurableTransferRoot $DurableTransferRoot
        }
    }
}

function Watch-VMResourceTransfer {
    <#
    .SYNOPSIS
    Monitors VM transfer progress and performance in near real time.
    .DESCRIPTION
    Polls authoritative target-local transfer state and normalized transport
    metrics. The command displays progress for each transfer and returns final
    status objects when every requested transfer reaches a terminal state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$TargetHostName,

        [string[]]$TransferId,

        [pscredential]$Credential,

        [ValidateRange(2, 300)]
        [int]$RefreshSeconds = 10,

        [ValidateRange(1, 10080)]
        [int]$TimeoutMinutes = 1440,

        [string]$DurableTransferRoot = "$env:ProgramData\VMHelper\Transfers",

        [switch]$PassThru
    )

    $activity = Start-DTMSActivity `
        -Name 'VM transfer monitor' `
        -Intent 'Poll authoritative target-host state and display live performance' `
        -Target ($TargetHostName -join ', ')
    $started = [DateTime]::UtcNow
    $terminalStatuses = @('Completed', 'Failed')
    do {
        $snapshots = @(
            foreach ($hostName in $TargetHostName) {
                if ($TransferId) {
                    foreach ($id in $TransferId) {
                        Get-VMResourceTransfer `
                            -TargetHostName $hostName `
                            -TransferId $id `
                            -Credential $Credential `
                            -DurableTransferRoot $DurableTransferRoot `
                            -ErrorAction SilentlyContinue
                    }
                } else {
                    Get-VMResourceTransfer `
                        -TargetHostName $hostName `
                        -Active `
                        -Credential $Credential `
                        -DurableTransferRoot $DurableTransferRoot
                }
            }
        )
        for ($index = 0; $index -lt $snapshots.Count; $index++) {
            $snapshot = $snapshots[$index]
            $percent = if ($null -ne $snapshot.ProgressPercent) {
                [math]::Max(0, [math]::Min(100, [double]$snapshot.ProgressPercent))
            } else {
                0
            }
            $status = '{0} | {1} | {2:N1}% | {3:N2} Mbps avg | {4:N2} Mbps current' -f
                $snapshot.Status,
                $snapshot.TransferProvider,
                $percent,
                [double]$snapshot.AverageMbps,
                [double]$snapshot.InstantaneousMbps
            Write-Progress `
                -Id ($index + 1) `
                -Activity "$($snapshot.SourceVMName) -> $($snapshot.TargetVMName)" `
                -Status $status `
                -PercentComplete $percent
            Write-Information (
                '[{0}] {1} -> {2}: {3}' -f
                ([DateTime]::UtcNow.ToString('u')),
                $snapshot.SourceVMName,
                $snapshot.TargetVMName,
                $status
            ) -InformationAction Continue
            if ($PassThru) {
                $snapshot
            }
        }
        $allTerminal = $snapshots.Count -gt 0 -and @(
            $snapshots | Where-Object Status -notin $terminalStatuses
        ).Count -eq 0
        $overallPercent = if ($snapshots.Count -gt 0) {
            [math]::Round(
                (@($snapshots | ForEach-Object {
                    if ($null -ne $_.ProgressPercent) {
                        [double]$_.ProgressPercent
                    } elseif ($_.Status -eq 'Completed') {
                        100
                    } else {
                        0
                    }
                }) | Measure-Object -Average).Average,
                1
            )
        } else {
            0
        }
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Observed $($snapshots.Count) transfer(s)." `
            -PercentComplete $overallPercent
        if ($allTerminal) {
            for ($index = 0; $index -lt $snapshots.Count; $index++) {
                Write-Progress -Id ($index + 1) -Activity 'VM resource transfer' -Completed
            }
            if (-not $PassThru) {
                $snapshots
            }
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'All monitored transfers reached a terminal state.'
            return
        }
        if ([DateTime]::UtcNow - $started -ge [TimeSpan]::FromMinutes($TimeoutMinutes)) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status "Monitoring exceeded the $TimeoutMinutes minute timeout." `
                -Failed
            throw "Transfer monitoring exceeded the $TimeoutMinutes minute timeout."
        }
        Start-Sleep -Seconds $RefreshSeconds
    } while ($true)
}

function Get-VMResourceTransferPerformanceReport {
    <#
    .SYNOPSIS
    Produces a comparative VM transfer performance report.
    .DESCRIPTION
    Queries authoritative target-local state and returns normalized throughput,
    byte-count, duration, progress, and outcome rows suitable for comparison
    across Robocopy, SCP, and BITS. Optionally writes the rows as CSV.
    #>
    [CmdletBinding(DefaultParameterSetName = 'TargetHost')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'TargetHost')]
        [string[]]$TargetHostName,

        [Parameter(Mandatory, ParameterSetName = 'Federated')]
        [string[]]$UtilityServer,

        [string[]]$TransferId,

        [pscredential]$Credential,

        [string]$DurableTransferRoot = "$env:ProgramData\VMHelper\Transfers",

        [string]$Path
    )

    $rows = @(
        $queryGroups = if ($PSCmdlet.ParameterSetName -eq 'Federated') {
            ,@(
                Get-VMResourceTransferFederated `
                    -UtilityServer $UtilityServer `
                    -TransferId $TransferId `
                    -Credential $Credential
            )
        } else {
            foreach ($hostName in $TargetHostName) {
                ,@(if ($TransferId) {
                    foreach ($id in $TransferId) {
                        Get-VMResourceTransfer `
                            -TargetHostName $hostName `
                            -TransferId $id `
                            -Credential $Credential `
                            -DurableTransferRoot $DurableTransferRoot `
                            -ErrorAction SilentlyContinue
                    }
                } else {
                    Get-VMResourceTransfer `
                        -TargetHostName $hostName `
                        -Credential $Credential `
                        -DurableTransferRoot $DurableTransferRoot
                })
            }
        }
        foreach ($transfers in $queryGroups) {
            foreach ($transfer in @($transfers)) {
                $durationSeconds = if ($transfer.StartedUtc) {
                    $end = if ($transfer.CompletedUtc) {
                        [datetime]$transfer.CompletedUtc
                    } else {
                        [DateTime]::UtcNow
                    }
                    [math]::Round(
                        ($end - [datetime]$transfer.StartedUtc).TotalSeconds,
                        3
                    )
                } else {
                    $null
                }
                [pscustomobject]@{
                    PSTypeName = 'VMHelper.TransferPerformanceReport'
                    TransferId = $transfer.TransferId
                    Provider = $transfer.TransferProvider
                    Status = $transfer.Status
                    SourceVMName = $transfer.SourceVMName
                    TargetVMName = $transfer.TargetVMName
                    SourceHostName = $transfer.SourceHostName
                    TargetHostName = $transfer.TargetHostName
                    BytesTransferred = $transfer.BytesTransferred
                    BytesTotal = $transfer.BytesTotal
                    ProgressPercent = $transfer.ProgressPercent
                    DurationSeconds = $durationSeconds
                    AverageMbps = $transfer.AverageMbps
                    LastInstantaneousMbps = $transfer.InstantaneousMbps
                    StartedUtc = $transfer.StartedUtc
                    CompletedUtc = $transfer.CompletedUtc
                    AttemptCount = $transfer.AttemptCount
                    OutcomeMessage = $transfer.Message
                    MetricsPath = if ($transfer.PSObject.Properties['MetricsPath']) {
                        $transfer.MetricsPath
                    } else {
                        $null
                    }
                    UtilityServers = if ($transfer.PSObject.Properties['UtilityServers']) {
                        @($transfer.UtilityServers)
                    } else {
                        @()
                    }
                }
            }
        }
    )
    if ($Path) {
        $parent = Split-Path $Path -Parent
        if ($parent -and -not (Test-Path $parent -PathType Container)) {
            New-Item $parent -ItemType Directory -Force | Out-Null
        }
        $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    $rows
}

function Copy-VMResource {
    <#
    .SYNOPSIS
    Copies selected disks or MAC addresses from a source VM to a target VM.
    .DESCRIPTION
    Copies only the resource groups named by Resource. The source VM is stopped
    and remains stopped. If the target was running, it is stopped for the
    operation and returned to its original running state afterward.

    HardDrives copies each attached VHD/VHDX or differencing chain. Source
    attachments and files remain unchanged. A target attachment at the same
    controller type, number, and location is replaced, but its original disk
    file is never deleted.

    MacAddress freezes each source adapter's effective MAC as static, then
    applies it to a target adapter. Adapters are matched by name first and by
    ordinal position when names do not match.

    Same-host and cross-host operations are supported. Cross-host hard-drive
    copies start a durable scheduled task on the target host, return a tracking
    object immediately, and transfer directly from the source with restartable
    unbuffered Robocopy.
    .PARAMETER SourceHostName
    Source Hyper-V host. When omitted, Find-VMHost locates SourceVMName.
    .PARAMETER TargetHostName
    Target Hyper-V host. When omitted, Find-VMHost locates TargetVMName.
    .PARAMETER Resource
    One or more resource groups to copy: HardDrives or MacAddress.
    .PARAMETER DestinationVhdRoot
    Parent directory for copied target disks. Defaults to a unique directory
    below the target VM's Virtual Hard Disks directory.
    .PARAMETER TransferCredential
    Domain credential used by the durable target-host transfer task. The
    account needs source-file access and Hyper-V access on both hosts.
    .PARAMETER TransferAccount
    gMSA used by the durable target-host transfer task. Use the trailing-dollar
    account name and do not also supply TransferCredential.
    .PARAMETER TurnOff
    Immediately powers off a running source or target VM instead of requesting
    a normal guest shutdown. This can cause data loss.
    .EXAMPLE
    Copy-VMResource -SourceVMName 'OldVM' -TargetVMName 'NewVM' `
        -SourceHostName 'hv01' -TargetHostName 'hv02' `
        -Resource HardDrives,MacAddress
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceVMName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetVMName,

        [ValidateNotNullOrEmpty()]
        [string]$SourceHostName,

        [ValidateNotNullOrEmpty()]
        [string]$TargetHostName,

        [Parameter(Mandatory)]
        [ValidateSet('HardDrives', 'MacAddress')]
        [string[]]$Resource,

        [ValidateNotNullOrEmpty()]
        [string]$DestinationVhdRoot,

        [ValidateNotNullOrEmpty()]
        [string]$LocalStagingRoot = ([IO.Path]::GetTempPath()),

        [pscredential]$SourceCredential,

        [pscredential]$TargetCredential,

        [pscredential]$TransferCredential,

        [ValidateNotNullOrEmpty()]
        [string]$TransferAccount,

        [ValidateSet('Auto', 'Robocopy', 'Scp', 'Bits')]
        [string]$TransferTransport = 'Robocopy',

        [ValidateNotNullOrEmpty()]
        [string]$ScpSourceEndpoint,

        [ValidateNotNullOrEmpty()]
        [string]$ScpIdentityFile,

        [ValidateNotNullOrEmpty()]
        [string]$DurableTransferRoot = "$env:ProgramData\VMHelper\Transfers",

        [switch]$TurnOff,

        [Parameter(DontShow)]
        [switch]$DurableWorker,

        [Parameter(DontShow)]
        [string]$TransferId,

        [Parameter(DontShow)]
        [string]$TransferLogPath,

        [Parameter(DontShow)]
        [switch]$RestoreTargetRunning,

        [Parameter(DontShow)]
        [string]$TransactionRoot
    )

    $activity = Start-DTMSActivity `
        -Name 'VM resource copy' `
        -Intent "Copy $($Resource -join ', ') from '$SourceVMName' to '$TargetVMName'"
    $SourceHostName = Resolve-VMOperationHostName `
        -VMName $SourceVMName `
        -HostName $SourceHostName `
        -Credential $SourceCredential `
        -Role source
    $TargetHostName = Resolve-VMOperationHostName `
        -VMName $TargetVMName `
        -HostName $TargetHostName `
        -Credential $TargetCredential `
        -Role target
    if ($SourceHostName -ieq $TargetHostName -and $SourceVMName -ieq $TargetVMName) {
        throw 'Source and target must identify different virtual machines.'
    }
    $selectedResources = @($Resource | Sort-Object -Unique)
    $copyHardDrives = 'HardDrives' -in $selectedResources
    $copyMacAddress = 'MacAddress' -in $selectedResources
    $sameHost = $SourceHostName -ieq $TargetHostName
    if ($copyHardDrives -and -not $sameHost -and -not $DurableWorker) {
        if (-not $PSCmdlet.ShouldProcess(
            "$SourceHostName`:$SourceVMName -> $TargetHostName`:$TargetVMName",
            "start durable direct transfer of: $($selectedResources -join ', ')"
        )) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'The VM resource copy was not started.'
            return
        }
        $durableTransfer = Start-DurableVMResourceTransfer `
            -SourceVMName $SourceVMName `
            -TargetVMName $TargetVMName `
            -SourceHostName $SourceHostName `
            -TargetHostName $TargetHostName `
            -Resource $selectedResources `
            -DestinationVhdRoot $DestinationVhdRoot `
            -DurableTransferRoot $DurableTransferRoot `
            -SourceCredential $SourceCredential `
            -TargetCredential $TargetCredential `
            -TransferCredential $TransferCredential `
            -TransferAccount $TransferAccount `
            -TransferTransport $TransferTransport `
            -ScpSourceEndpoint $ScpSourceEndpoint `
            -ScpIdentityFile $ScpIdentityFile `
            -TurnOff $TurnOff.IsPresent
        Complete-DTMSActivity `
            -Activity $activity `
            -Status "Durable transfer '$($durableTransfer.TransferId)' was launched."
        return $durableTransfer
    }
    $sourceSession = $null
    $targetSession = $null
    $targetWasRunning = $false
    $sourceStopped = $false
    $targetModified = $false
    $targetOriginalDisks = @()
    $targetOriginalAdapters = @()
    $destinationRunRoot = $null
    $localRunRoot = $null
    $operationResult = $null
    $operationError = $null
    $rollbackError = $null
    $phasePersistenceError = $null
    $targetRestartError = $null
    $transactionStateError = $null
    $runId = if ($TransferId) {
        $TransferId
    } else {
        '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N')
    }
    if ($DurableWorker) {
        if ([string]::IsNullOrWhiteSpace($TransactionRoot)) {
            throw 'TransactionRoot is required for a durable worker.'
        }
        Write-VMResourceTransferPhase `
            -TransactionRoot $TransactionRoot `
            -Phase Preflight `
            -Message 'Validating source and target virtual machines.'
    }
    try {
        $effectiveSourceCredential = if ($sameHost -and -not $SourceCredential) {
            $TargetCredential
        } else {
            $SourceCredential
        }
        $sourceSession = Open-RemoteSession -ComputerName $SourceHostName -Credential $effectiveSourceCredential
        $targetSession = if ($sameHost) {
            $sourceSession
        } else {
            Open-RemoteSession -ComputerName $TargetHostName -Credential $TargetCredential
        }
        $sourceSummary = Invoke-Command -Session $sourceSession -ArgumentList $SourceVMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            [pscustomobject]@{
                Name = $vm.Name
                Id = [string]$vm.Id
                State = [string]$vm.State
            }
        }
        $targetSummary = Invoke-Command -Session $targetSession -ArgumentList $TargetVMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            [pscustomobject]@{
                Name = $vm.Name
                Id = [string]$vm.Id
                State = [string]$vm.State
                Path = [string]$vm.Path
            }
        }
        if ($sourceSummary.Id -eq $targetSummary.Id) {
            throw 'Source and target VMs must have different VM IDs.'
        }
        if ($targetSummary.State -notin @('Running', 'Off')) {
            throw "Target VM must be Running or Off; current state is '$($targetSummary.State)'."
        }
        $targetWasRunning = $targetSummary.State -eq 'Running' -or $RestoreTargetRunning
        $targetVhdBase = if (-not $copyHardDrives) {
            $null
        } elseif ($DestinationVhdRoot) {
            $DestinationVhdRoot
        } else {
            if ([string]::IsNullOrWhiteSpace($targetSummary.Path)) {
                throw 'Target VM path is unavailable. Specify -DestinationVhdRoot when copying hard drives.'
            }
            Join-Path $targetSummary.Path 'Virtual Hard Disks'
        }
        $destinationRunRoot = if ($copyHardDrives) {
            Join-Path $targetVhdBase "VMHelper-$TargetVMName-$runId"
        } else {
            $null
        }
        $localRunRoot = Join-Path $LocalStagingRoot "VMHelper-$runId"

        if (-not $PSCmdlet.ShouldProcess(
            "$SourceHostName`:$SourceVMName -> $TargetHostName`:$TargetVMName",
            "copy selected VM resources: $($selectedResources -join ', ')"
        )) {
            return
        }

        if ($DurableWorker) {
            Write-VMResourceTransferPhase `
                -TransactionRoot $TransactionRoot `
                -Phase StoppingVMs `
                -Message 'Stopping source and target virtual machines.'
        }
        if ($targetSummary.State -ne 'Off') {
            Invoke-Command -Session $targetSession -ArgumentList $TargetVMName, $TurnOff.IsPresent -ScriptBlock {
                param($Name, $UseTurnOff)
                Import-Module Hyper-V -ErrorAction Stop
                $vm = Get-VM -Name $Name -ErrorAction Stop
                if ($UseTurnOff) {
                    Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
                } else {
                    Stop-VM -VM $vm -Confirm:$false -ErrorAction Stop
                }
                $deadline = [DateTime]::UtcNow.AddMinutes(10)
                do {
                    Start-Sleep -Seconds 2
                    $vm = Get-VM -Name $Name -ErrorAction Stop
                } while ($vm.State -ne 'Off' -and [DateTime]::UtcNow -lt $deadline)
                if ($vm.State -ne 'Off') {
                    throw "Target VM '$Name' did not reach the Off state within 10 minutes."
                }
            }
        }

        if ($sourceSummary.State -ne 'Off') {
            Invoke-Command -Session $sourceSession -ArgumentList $SourceVMName, $TurnOff.IsPresent -ScriptBlock {
                param($Name, $UseTurnOff)
                Import-Module Hyper-V -ErrorAction Stop
                $vm = Get-VM -Name $Name -ErrorAction Stop
                if ($UseTurnOff) {
                    Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
                } else {
                    Stop-VM -VM $vm -Confirm:$false -ErrorAction Stop
                }
                $deadline = [DateTime]::UtcNow.AddMinutes(10)
                do {
                    Start-Sleep -Seconds 2
                    $vm = Get-VM -Name $Name -ErrorAction Stop
                } while ($vm.State -ne 'Off' -and [DateTime]::UtcNow -lt $deadline)
                if ($vm.State -ne 'Off') {
                    throw "Source VM '$Name' did not reach the Off state within 10 minutes."
                }
            }
        }
        $sourceStopped = $true

        if ($DurableWorker) {
            Write-VMResourceTransferPhase `
                -TransactionRoot $TransactionRoot `
                -Phase CapturingConfiguration `
                -Message 'Capturing source resources and the target rollback baseline.'
        }
        $sourceData = Invoke-Command -Session $sourceSession -ArgumentList $SourceVMName, $copyHardDrives, $copyMacAddress -ScriptBlock {
            param($Name, $ReadHardDrives, $ReadMacAddress)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ($vm.State -ne 'Off') {
                throw "Source VM '$Name' must remain off while resources are read."
            }
            $disks = @()
            if ($ReadHardDrives) {
                $disks = @(Get-VMHardDiskDrive -VM $vm | ForEach-Object {
                    if (-not $_.Path) {
                        throw "Pass-through disk at $($_.ControllerType) $($_.ControllerNumber):$($_.ControllerLocation) is not supported."
                    }
                    $chain = [Collections.Generic.List[object]]::new()
                    $currentPath = $_.Path
                    do {
                        $vhd = Get-VHD -Path $currentPath -ErrorAction Stop
                        $vhdFile = Get-Item -LiteralPath $vhd.Path -ErrorAction Stop
                        $chain.Add([pscustomobject]@{
                            Path = [string]$vhd.Path
                            ParentPath = [string]$vhd.ParentPath
                            VhdType = [string]$vhd.VhdType
                            Length = [long]$vhdFile.Length
                        })
                        $currentPath = [string]$vhd.ParentPath
                    } while (-not [string]::IsNullOrWhiteSpace($currentPath))
                    [pscustomobject]@{
                        ControllerType = [string]$_.ControllerType
                        ControllerNumber = [int]$_.ControllerNumber
                        ControllerLocation = [int]$_.ControllerLocation
                        Chain = $chain.ToArray()
                    }
                })
            }
            $adapters = @()
            if ($ReadMacAddress) {
                $adapters = @(Get-VMNetworkAdapter -VM $vm | ForEach-Object {
                    if (-not $_.MacAddress) {
                        throw "Source network adapter '$($_.Name)' has no effective MAC address."
                    }
                    if ($_.DynamicMacAddressEnabled) {
                        Set-VMNetworkAdapter -VMNetworkAdapter $_ -StaticMacAddress $_.MacAddress -ErrorAction Stop
                    }
                    [pscustomobject]@{
                        Name = [string]$_.Name
                        MacAddress = [string]$_.MacAddress
                    }
                })
            }
            [pscustomobject]@{
                HardDrives = $disks
                NetworkAdapters = $adapters
            }
        }

        $targetState = Invoke-Command -Session $targetSession -ArgumentList $TargetVMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ($vm.State -ne 'Off') {
                throw "Target VM '$Name' must be off while resources are changed."
            }
            [pscustomobject]@{
                HardDrives = @(Get-VMHardDiskDrive -VM $vm | ForEach-Object {
                    [pscustomobject]@{
                        ControllerType = [string]$_.ControllerType
                        ControllerNumber = [int]$_.ControllerNumber
                        ControllerLocation = [int]$_.ControllerLocation
                        Path = [string]$_.Path
                    }
                })
                NetworkAdapters = @(Get-VMNetworkAdapter -VM $vm | ForEach-Object {
                    [pscustomobject]@{
                        Name = [string]$_.Name
                        DynamicMacAddressEnabled = [bool]$_.DynamicMacAddressEnabled
                        MacAddress = [string]$_.MacAddress
                    }
                })
            }
        }
        if ($DurableWorker) {
            $rollbackPath = Join-Path $TransactionRoot 'Rollback.json'
            if (Test-Path -LiteralPath $rollbackPath -PathType Leaf) {
                $rollbackSnapshot = Get-Content -LiteralPath $rollbackPath -Raw | ConvertFrom-Json
                if ($rollbackSnapshot.TargetVMName -ne $TargetVMName -or
                    $rollbackSnapshot.TargetVMId -ne $targetSummary.Id) {
                    throw "Rollback snapshot '$rollbackPath' does not match target VM '$TargetVMName'."
                }
            } else {
                $rollbackSnapshot = [ordered]@{
                    TransferId = $TransferId
                    TargetVMName = $TargetVMName
                    TargetVMId = $targetSummary.Id
                    CapturedUtc = [DateTime]::UtcNow.ToString('o')
                    HardDrives = @($targetState.HardDrives)
                    NetworkAdapters = @($targetState.NetworkAdapters)
                }
                $temporaryRollbackPath = "$rollbackPath.tmp"
                $rollbackSnapshot | ConvertTo-Json -Depth 20 |
                    Set-Content -LiteralPath $temporaryRollbackPath -Encoding UTF8
                Move-Item -LiteralPath $temporaryRollbackPath -Destination $rollbackPath -Force
            }
            $targetOriginalDisks = @($rollbackSnapshot.HardDrives)
            $targetOriginalAdapters = @($rollbackSnapshot.NetworkAdapters)
        } else {
            $targetOriginalDisks = @($targetState.HardDrives)
            $targetOriginalAdapters = @($targetState.NetworkAdapters)
        }

        $adapterMappings = @()
        if ($copyMacAddress) {
            if (@($sourceData.NetworkAdapters).Count -gt @($targetState.NetworkAdapters).Count) {
                throw "Source VM has $(@($sourceData.NetworkAdapters).Count) network adapters; target VM has only $(@($targetState.NetworkAdapters).Count)."
            }
            $usedTargetNames = @{}
            for ($index = 0; $index -lt @($sourceData.NetworkAdapters).Count; $index++) {
                $sourceAdapter = @($sourceData.NetworkAdapters)[$index]
                $nameMatch = @($targetState.NetworkAdapters | Where-Object {
                    $_.Name -eq $sourceAdapter.Name -and -not $usedTargetNames.ContainsKey($_.Name)
                })
                $targetAdapter = if ($nameMatch.Count -eq 1) {
                    $nameMatch[0]
                } else {
                    $ordinalAdapter = @($targetState.NetworkAdapters)[$index]
                    if ($usedTargetNames.ContainsKey($ordinalAdapter.Name)) {
                        throw "Cannot map source adapter '$($sourceAdapter.Name)' to a unique target adapter."
                    }
                    $ordinalAdapter
                }
                $usedTargetNames[$targetAdapter.Name] = $true
                $adapterMappings += [pscustomobject]@{
                    SourceName = $sourceAdapter.Name
                    TargetName = $targetAdapter.Name
                    MacAddress = $sourceAdapter.MacAddress
                }
            }
        }

        $copiedDisks = @()
        if ($copyHardDrives) {
            $totalTransferBytes = [long](($sourceData.HardDrives |
                ForEach-Object { $_.Chain } |
                Measure-Object -Property Length -Sum).Sum)
            $completedTransferBytes = [long]0
            if ($DurableWorker) {
                Write-VMResourceTransferPhase `
                    -TransactionRoot $TransactionRoot `
                    -Phase CopyingDisks `
                    -Message 'Copying virtual disk layers directly from the source host.' `
                    -ProgressPercent 0
            }
            Invoke-Command -Session $targetSession -ArgumentList $destinationRunRoot, $DurableWorker.IsPresent -ScriptBlock {
                param($Path, $AllowExisting)
                if (-not $AllowExisting -and (Test-Path -LiteralPath $Path)) {
                    throw "Destination disk directory already exists: $Path"
                }
                New-Item -Path $Path -ItemType Directory -Force | Out-Null
            }
            if (-not $sameHost -and -not $DurableWorker) {
                New-Item -Path $localRunRoot -ItemType Directory -Force | Out-Null
            }
            for ($diskIndex = 0; $diskIndex -lt @($sourceData.HardDrives).Count; $diskIndex++) {
                $sourceDisk = @($sourceData.HardDrives)[$diskIndex]
                $targetDiskDirectory = Join-Path $destinationRunRoot ('Disk-{0:D2}' -f $diskIndex)
                Invoke-Command -Session $targetSession -ArgumentList $targetDiskDirectory -ScriptBlock {
                    param($Path)
                    New-Item -Path $Path -ItemType Directory -Force | Out-Null
                }
                $targetChain = [Collections.Generic.List[string]]::new()
                for ($layerIndex = 0; $layerIndex -lt @($sourceDisk.Chain).Count; $layerIndex++) {
                    $sourceLayer = @($sourceDisk.Chain)[$layerIndex]
                    $extension = [IO.Path]::GetExtension($sourceLayer.Path)
                    $targetLayerPath = Join-Path $targetDiskDirectory ('Layer-{0:D2}{1}' -f $layerIndex, $extension)
                    if ($sameHost) {
                        Invoke-Command -Session $targetSession -ArgumentList $sourceLayer.Path, $targetLayerPath -ScriptBlock {
                            param($SourcePath, $TargetPath)
                            Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -ErrorAction Stop
                        }
                    } elseif ($DurableWorker) {
                        $targetLayerDirectory = Join-Path $targetDiskDirectory ('Layer-{0:D2}' -f $layerIndex)
                        New-Item -Path $targetLayerDirectory -ItemType Directory -Force | Out-Null
                        $sourceFileName = [IO.Path]::GetFileName($sourceLayer.Path)
                        $targetLayerPath = Join-Path $targetLayerDirectory $sourceFileName
                        $effectiveTransport = if (
                            $TransferTransport -eq 'Auto' -and
                            -not [string]::IsNullOrWhiteSpace($ScpSourceEndpoint) -and
                            (Get-DurableTransferProvider -Name Scp).Available
                        ) {
                            'Scp'
                        } elseif ($TransferTransport -eq 'Auto') {
                            'Robocopy'
                        } else {
                            $TransferTransport
                        }
                        $sourceTransferPath = if ($effectiveTransport -eq 'Scp') {
                            if ([string]::IsNullOrWhiteSpace($ScpSourceEndpoint)) {
                                throw 'SCP transfer requires ScpSourceEndpoint in user@host form.'
                            }
                            $scpSourcePath = $sourceLayer.Path -replace '\\', '/'
                            if ($scpSourcePath -match '^[A-Za-z]:/') {
                                $scpSourcePath = "/$scpSourcePath"
                            }
                            "$ScpSourceEndpoint`:$scpSourcePath"
                        } else {
                            ConvertTo-RemoteAdministrativePath `
                                -ComputerName $SourceHostName `
                                -Path $sourceLayer.Path
                        }
                        $transferRequest = New-DurableTransferRequest `
                            -Source $sourceTransferPath `
                            -Destination $targetLayerPath `
                            -Transport $effectiveTransport `
                            -RequireResume:($effectiveTransport -in @('Robocopy', 'Bits')) `
                            -CompletedBytesBefore $completedTransferBytes `
                            -OperationBytesTotal $totalTransferBytes `
                            -SshKeyPath $(if ($effectiveTransport -eq 'Scp') {
                                $ScpIdentityFile
                            })
                        $metricsPath = Join-Path $TransactionRoot 'TransferMetrics.jsonl'
                        Invoke-DurableTransfer `
                            -Request $transferRequest `
                            -LogPath $TransferLogPath `
                            -MetricsPath $metricsPath `
                            -Confirm:$false | Out-Null
                        if (-not (Test-Path -LiteralPath $targetLayerPath -PathType Leaf)) {
                            throw "$effectiveTransport reported success but destination file was not found: $targetLayerPath"
                        }
                        $completedTransferBytes += [long]$sourceLayer.Length
                        if ($totalTransferBytes -gt 0) {
                            $overallProgress = [math]::Min(
                                99.99,
                                ($completedTransferBytes / $totalTransferBytes) * 100
                            )
                            Write-VMResourceTransferPhase `
                                -TransactionRoot $TransactionRoot `
                                -Phase CopyingDisks `
                                -Message (
                                    'Copied {0}; {1:N1}% of disk bytes complete.' -f
                                    $sourceFileName,
                                    $overallProgress
                                ) `
                                -ProgressPercent $overallProgress
                        }
                    } else {
                        $localDiskDirectory = Join-Path $localRunRoot ('Disk-{0:D2}' -f $diskIndex)
                        New-Item -Path $localDiskDirectory -ItemType Directory -Force | Out-Null
                        $localLayerPath = Join-Path $localDiskDirectory ('Layer-{0:D2}{1}' -f $layerIndex, $extension)
                        Copy-Item -FromSession $sourceSession -LiteralPath $sourceLayer.Path -Destination $localLayerPath -ErrorAction Stop
                        Copy-Item -ToSession $targetSession -LiteralPath $localLayerPath -Destination $targetLayerPath -ErrorAction Stop
                    }
                    $targetChain.Add($targetLayerPath)
                }
                $copiedDisks += [pscustomobject]@{
                    ControllerType = $sourceDisk.ControllerType
                    ControllerNumber = $sourceDisk.ControllerNumber
                    ControllerLocation = $sourceDisk.ControllerLocation
                    Path = $targetChain[0]
                    Chain = $targetChain.ToArray()
                }
            }
            if ($DurableWorker) {
                Write-VMResourceTransferPhase `
                    -TransactionRoot $TransactionRoot `
                    -Phase RelinkingDisks `
                    -Message 'Relinking copied differencing-disk chains.'
            }
            foreach ($copiedDisk in @($copiedDisks)) {
                if (@($copiedDisk.Chain).Count -gt 1) {
                    Invoke-Command -Session $targetSession -ArgumentList (,$copiedDisk.Chain) -ScriptBlock {
                        param($Chain)
                        Import-Module Hyper-V -ErrorAction Stop
                        for ($index = 0; $index -lt $Chain.Count - 1; $index++) {
                            Set-VHD -Path $Chain[$index] -ParentPath $Chain[$index + 1] -ErrorAction Stop
                        }
                    }
                }
            }
        }

        if ($DurableWorker) {
            Write-VMResourceTransferPhase `
                -TransactionRoot $TransactionRoot `
                -Phase ApplyingTargetConfiguration `
                -Message 'Applying copied disks and MAC addresses to the target VM.'
        }
        $targetUpdate = [pscustomobject]@{
            Disks = @($copiedDisks)
            Adapters = @($adapterMappings)
            ApplyHardDrives = $copyHardDrives
            ApplyMacAddress = $copyMacAddress
        }
        $targetModified = $true
        Invoke-Command -Session $targetSession -ArgumentList $TargetVMName, $targetUpdate -ScriptBlock {
            param($Name, $Update)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ($Update.ApplyHardDrives) {
                foreach ($disk in @($Update.Disks)) {
                    $existing = Get-VMHardDiskDrive -VM $vm |
                        Where-Object {
                            [string]$_.ControllerType -eq $disk.ControllerType -and
                            $_.ControllerNumber -eq $disk.ControllerNumber -and
                            $_.ControllerLocation -eq $disk.ControllerLocation
                        }
                    if ($existing) {
                        Remove-VMHardDiskDrive -VMHardDiskDrive $existing -ErrorAction Stop
                    }
                    Add-VMHardDiskDrive -VM $vm `
                        -ControllerType $disk.ControllerType `
                        -ControllerNumber $disk.ControllerNumber `
                        -ControllerLocation $disk.ControllerLocation `
                        -Path $disk.Path `
                        -ErrorAction Stop
                }
            }
            if ($Update.ApplyMacAddress) {
                foreach ($adapterMapping in @($Update.Adapters)) {
                    $adapter = @(Get-VMNetworkAdapter -VM $vm |
                        Where-Object Name -eq $adapterMapping.TargetName)
                    if ($adapter.Count -ne 1) {
                        throw "Expected one target adapter named '$($adapterMapping.TargetName)'; found $($adapter.Count)."
                    }
                    Set-VMNetworkAdapter `
                        -VMNetworkAdapter $adapter[0] `
                        -StaticMacAddress $adapterMapping.MacAddress `
                        -ErrorAction Stop
                }
            }
        }

        if ($DurableWorker) {
            Write-VMResourceTransferPhase `
                -TransactionRoot $TransactionRoot `
                -Phase Verifying `
                -Message 'Verifying target disk attachments and MAC addresses.'
        }
        Invoke-Command -Session $targetSession -ArgumentList $TargetVMName, $targetUpdate -ScriptBlock {
            param($Name, $Expected)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ($Expected.ApplyHardDrives) {
                $actualDisks = @(Get-VMHardDiskDrive -VM $vm)
                foreach ($expectedDisk in @($Expected.Disks)) {
                    $actualDisk = @($actualDisks | Where-Object {
                        [string]$_.ControllerType -eq $expectedDisk.ControllerType -and
                        $_.ControllerNumber -eq $expectedDisk.ControllerNumber -and
                        $_.ControllerLocation -eq $expectedDisk.ControllerLocation
                    })
                    if ($actualDisk.Count -ne 1 -or
                        $actualDisk[0].Path -ine $expectedDisk.Path) {
                        throw "Target disk verification failed at $($expectedDisk.ControllerType) $($expectedDisk.ControllerNumber):$($expectedDisk.ControllerLocation)."
                    }
                }
            }
            if ($Expected.ApplyMacAddress) {
                $actualAdapters = @(Get-VMNetworkAdapter -VM $vm)
                foreach ($expectedAdapter in @($Expected.Adapters)) {
                    $actualAdapter = @($actualAdapters | Where-Object Name -eq $expectedAdapter.TargetName)
                    $actualMac = if ($actualAdapter.Count -eq 1) {
                        [string]$actualAdapter[0].MacAddress -replace '[:-]', ''
                    } else {
                        $null
                    }
                    $expectedMac = [string]$expectedAdapter.MacAddress -replace '[:-]', ''
                    if ($actualAdapter.Count -ne 1 -or $actualMac -ine $expectedMac) {
                        throw "Target MAC address verification failed for adapter '$($expectedAdapter.TargetName)'."
                    }
                }
            }
        }

        $operationResult = [pscustomobject]@{
            PSTypeName = 'VMHelper.ResourceCopyResult'
            SourceVMName = $SourceVMName
            TargetVMName = $TargetVMName
            SourceHostName = $SourceHostName
            TargetHostName = $TargetHostName
            Resources = $selectedResources
            SourceState = 'Off'
            TargetOriginalState = if ($RestoreTargetRunning) { 'Running' } else { $targetSummary.State }
            TargetFinalState = 'Off'
            DestinationVhdRoot = if ($copyHardDrives) { $destinationRunRoot } else { $null }
            CopiedHardDrives = @($copiedDisks)
            MacAddressMappings = @($adapterMappings)
            ReplacedTargetDiskFilesRetained = $true
            SourceDiskAttachmentsRetained = $true
            RuntimeMode = $script:VMHelperRuntime.RuntimeMode
        }
    } catch {
        $operationError = $_
        if ($targetModified) {
            if ($DurableWorker) {
                try {
                    Write-VMResourceTransferPhase `
                        -TransactionRoot $TransactionRoot `
                        -Phase RollingBack `
                        -Message 'An operation failed; restoring the original target configuration.'
                } catch {
                    $phasePersistenceError = $_.Exception.Message
                }
            }
            try {
                $rollback = [pscustomobject]@{
                    OriginalDisks = @($targetOriginalDisks)
                    OriginalAdapters = @($targetOriginalAdapters)
                    RestoreHardDrives = $copyHardDrives
                    RestoreMacAddress = $copyMacAddress
                }
                Invoke-Command -Session $targetSession -ArgumentList $TargetVMName, $rollback -ScriptBlock {
                    param($Name, $Rollback)
                    Import-Module Hyper-V -ErrorAction Stop
                    $vm = Get-VM -Name $Name -ErrorAction Stop
                    if ($Rollback.RestoreHardDrives) {
                        foreach ($currentDisk in @(Get-VMHardDiskDrive -VM $vm)) {
                            Remove-VMHardDiskDrive -VMHardDiskDrive $currentDisk -ErrorAction Stop
                        }
                        foreach ($originalDisk in @($Rollback.OriginalDisks)) {
                            Add-VMHardDiskDrive -VM $vm `
                                -ControllerType $originalDisk.ControllerType `
                                -ControllerNumber $originalDisk.ControllerNumber `
                                -ControllerLocation $originalDisk.ControllerLocation `
                                -Path $originalDisk.Path `
                                -ErrorAction Stop
                        }
                    }
                    if ($Rollback.RestoreMacAddress) {
                        foreach ($originalAdapter in @($Rollback.OriginalAdapters)) {
                            $adapter = @(Get-VMNetworkAdapter -VM $vm |
                                Where-Object Name -eq $originalAdapter.Name)
                            if ($adapter.Count -ne 1) {
                                throw "Cannot restore target adapter '$($originalAdapter.Name)'."
                            }
                            if ($originalAdapter.DynamicMacAddressEnabled) {
                                Set-VMNetworkAdapter -VMNetworkAdapter $adapter[0] -DynamicMacAddress -ErrorAction Stop
                            } else {
                                Set-VMNetworkAdapter -VMNetworkAdapter $adapter[0] -StaticMacAddress $originalAdapter.MacAddress -ErrorAction Stop
                            }
                        }
                    }
                }
            } catch {
                $rollbackError = $_.Exception.Message
            }
        }
    } finally {
        if ($DurableWorker -and $targetSession) {
            try {
                Write-VMResourceTransferPhase `
                    -TransactionRoot $TransactionRoot `
                    -Phase RestoringTargetState `
                    -Message 'Restoring the target VM to its original power state.'
            } catch {
                $transactionStateError = $_
                Write-Warning "Transfer phase persistence failed while restoring the target state: $($_.Exception.Message)"
            }
        }
        if ($targetWasRunning -and $targetSession) {
            try {
                Invoke-Command -Session $targetSession -ArgumentList $TargetVMName -ScriptBlock {
                    param($Name)
                    Import-Module Hyper-V -ErrorAction Stop
                    $vm = Get-VM -Name $Name -ErrorAction Stop
                    if ($vm.State -ne 'Running') {
                        Start-VM -VM $vm -ErrorAction Stop | Out-Null
                    }
                }
                if ($operationResult) {
                    $operationResult.TargetFinalState = 'Running'
                }
            } catch {
                if ($operationResult) {
                    $operationResult.TargetFinalState = 'RestoreFailed'
                }
                $targetRestartError = $_
                Write-Warning "Target VM '$TargetVMName' could not be returned to its original running state: $($_.Exception.Message)"
            }
        }
        if ($DurableWorker -and $operationError) {
            $terminalPhase = if (-not $targetModified) {
                'Failed'
            } elseif ($rollbackError -or $targetRestartError) {
                'RollbackFailed'
            } else {
                'RolledBack'
            }
            $terminalMessage = switch ($terminalPhase) {
                'RolledBack' {
                    'The operation failed and the original target configuration and power state were restored.'
                }
                'RollbackFailed' {
                    'The operation failed and one or more rollback or power-state restoration steps failed.'
                }
                default {
                    'The operation failed before target configuration was changed.'
                }
            }
            try {
                Write-VMResourceTransferPhase `
                    -TransactionRoot $TransactionRoot `
                    -Phase $terminalPhase `
                    -Message $terminalMessage
            } catch {
                $transactionStateError = $_
                Write-Warning "Transfer terminal phase persistence failed: $($_.Exception.Message)"
            }
        }
        if ($localRunRoot -and (Test-Path -LiteralPath $localRunRoot)) {
            Remove-Item -LiteralPath $localRunRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($sameHost) {
            Close-RemoteSession -Session @($sourceSession)
        } else {
            Close-RemoteSession -Session @($sourceSession, $targetSession)
        }
    }
    if ($operationError) {
        $message = $operationError.Exception.Message
        if ($sourceStopped) {
            $message += " Source VM '$SourceVMName' remains stopped."
        }
        if ($rollbackError) {
            $message += " Target rollback also failed: $rollbackError"
        }
        if ($targetRestartError) {
            $message += " Target power-state restoration also failed: $($targetRestartError.Exception.Message)"
        }
        if ($phasePersistenceError -or $transactionStateError) {
            $stateErrorMessage = if ($transactionStateError) {
                $transactionStateError.Exception.Message
            } else {
                $phasePersistenceError
            }
            $message += " Transaction state persistence also failed: $stateErrorMessage"
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status $message `
            -Failed
        throw [System.InvalidOperationException]::new($message, $operationError.Exception)
    }
    if ($targetRestartError) {
        throw [System.InvalidOperationException]::new(
            "Resources were copied, but target VM '$TargetVMName' could not be returned to its original running state.",
            $targetRestartError.Exception
        )
    }
    if ($transactionStateError) {
        throw [System.InvalidOperationException]::new(
            'The VM resource operation completed, but durable transaction state could not be persisted.',
            $transactionStateError.Exception
        )
    }
    if ($DurableWorker) {
        Write-VMResourceTransferPhase `
            -TransactionRoot $TransactionRoot `
            -Phase Completed `
            -Message 'The resource transfer transaction completed successfully.'
    }
    if ($operationResult) {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'VM resources were copied successfully.'
        $operationResult
    }
}

function Sync-VMConfiguration {
    <#
    .SYNOPSIS
    Synchronizes selected Hyper-V VM configuration groups between hosts.
    .DESCRIPTION
    Copies explicitly selected mutable configuration groups from a source VM
    to an existing destination VM. This command does not copy virtual disks,
    checkpoints, firmware generation, VM ID, or guest data.

    NetworkAdapters requires matching adapter names on the destination. It
    copies static/dynamic MAC configuration and VLAN settings. Switch
    connections are copied only when IncludeSwitchConnection is specified and
    an identically named switch exists on the destination.
    .PARAMETER SourceHostName
    Source Hyper-V host. When omitted, Find-VMHost locates SourceVMName.
    .PARAMETER DestinationHostName
    Destination Hyper-V host. When omitted, Find-VMHost locates
    DestinationVMName.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceVMName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationVMName,

        [ValidateNotNullOrEmpty()]
        [string]$SourceHostName,

        [ValidateNotNullOrEmpty()]
        [string]$DestinationHostName,

        [Parameter(Mandatory)]
        [ValidateSet('Processor', 'Memory', 'AutomaticActions', 'Checkpoint', 'NetworkAdapters')]
        [string[]]$Property,

        [pscredential]$SourceCredential,

        [pscredential]$DestinationCredential,

        [switch]$IncludeSwitchConnection
    )

    $activity = Start-DTMSActivity `
        -Name 'VM configuration synchronization' `
        -Intent "Copy $($Property -join ', ') from '$SourceVMName' to '$DestinationVMName'"
    $SourceHostName = Resolve-VMOperationHostName `
        -VMName $SourceVMName `
        -HostName $SourceHostName `
        -Credential $SourceCredential `
        -Role source
    $DestinationHostName = Resolve-VMOperationHostName `
        -VMName $DestinationVMName `
        -HostName $DestinationHostName `
        -Credential $DestinationCredential `
        -Role destination

    $sourceSession = $null
    $destinationSession = $null
    try {
        $sourceSession = Open-RemoteSession -ComputerName $SourceHostName -Credential $SourceCredential
        $destinationSession = Open-RemoteSession -ComputerName $DestinationHostName -Credential $DestinationCredential
        $configuration = Invoke-Command -Session $sourceSession -ArgumentList $SourceVMName -ScriptBlock {
            param($Name)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            $processor = Get-VMProcessor -VM $vm
            $memory = Get-VMMemory -VM $vm
            $adapters = @(Get-VMNetworkAdapter -VM $vm | ForEach-Object {
                $vlan = Get-VMNetworkAdapterVlan -VMNetworkAdapter $_
                [pscustomobject]@{
                    Name = $_.Name
                    DynamicMacAddressEnabled = $_.DynamicMacAddressEnabled
                    StaticMacAddress = $_.MacAddress
                    SwitchName = $_.SwitchName
                    VlanMode = [string]$vlan.OperationMode
                    AccessVlanId = $vlan.AccessVlanId
                    NativeVlanId = $vlan.NativeVlanId
                    AllowedVlanIdList = $vlan.AllowedVlanIdList
                }
            })
            [pscustomobject]@{
                Processor = [pscustomobject]@{
                    Count = $processor.Count
                    Reserve = $processor.Reserve
                    Maximum = $processor.Maximum
                    RelativeWeight = $processor.RelativeWeight
                    ExposeVirtualizationExtensions = $processor.ExposeVirtualizationExtensions
                    CompatibilityForMigrationEnabled = $processor.CompatibilityForMigrationEnabled
                }
                Memory = [pscustomobject]@{
                    DynamicMemoryEnabled = $memory.DynamicMemoryEnabled
                    Startup = $memory.Startup
                    Minimum = $memory.Minimum
                    Maximum = $memory.Maximum
                    Buffer = $memory.Buffer
                    Priority = $memory.Priority
                }
                AutomaticActions = [pscustomobject]@{
                    AutomaticStartAction = [string]$vm.AutomaticStartAction
                    AutomaticStartDelay = $vm.AutomaticStartDelay
                    AutomaticStopAction = [string]$vm.AutomaticStopAction
                }
                Checkpoint = [pscustomobject]@{
                    CheckpointType = [string]$vm.CheckpointType
                    AutomaticCheckpointsEnabled = $vm.AutomaticCheckpointsEnabled
                }
                NetworkAdapters = $adapters
            }
        }
        if (-not $PSCmdlet.ShouldProcess(
            "$DestinationHostName`:$DestinationVMName",
            "synchronize $($Property -join ', ') from $SourceHostName`:$SourceVMName"
        )) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'Configuration synchronization was not started.'
            return
        }
        $result = Invoke-Command -Session $destinationSession -ArgumentList $DestinationVMName, @($Property), $configuration, $IncludeSwitchConnection.IsPresent -ScriptBlock {
            param($Name, $SelectedProperty, $Source, $CopySwitch)
            Import-Module Hyper-V -ErrorAction Stop
            $vm = Get-VM -Name $Name -ErrorAction Stop
            if ('Processor' -in $SelectedProperty) {
                Set-VMProcessor -VM $vm `
                    -Count $Source.Processor.Count `
                    -Reserve $Source.Processor.Reserve `
                    -Maximum $Source.Processor.Maximum `
                    -RelativeWeight $Source.Processor.RelativeWeight `
                    -ExposeVirtualizationExtensions $Source.Processor.ExposeVirtualizationExtensions `
                    -CompatibilityForMigrationEnabled $Source.Processor.CompatibilityForMigrationEnabled
            }
            if ('Memory' -in $SelectedProperty) {
                Set-VMMemory -VM $vm `
                    -DynamicMemoryEnabled $Source.Memory.DynamicMemoryEnabled `
                    -StartupBytes $Source.Memory.Startup `
                    -MinimumBytes $Source.Memory.Minimum `
                    -MaximumBytes $Source.Memory.Maximum `
                    -Buffer $Source.Memory.Buffer `
                    -Priority $Source.Memory.Priority
            }
            if ('AutomaticActions' -in $SelectedProperty) {
                Set-VM -VM $vm `
                    -AutomaticStartAction $Source.AutomaticActions.AutomaticStartAction `
                    -AutomaticStartDelay $Source.AutomaticActions.AutomaticStartDelay `
                    -AutomaticStopAction $Source.AutomaticActions.AutomaticStopAction
            }
            if ('Checkpoint' -in $SelectedProperty) {
                Set-VM -VM $vm `
                    -CheckpointType $Source.Checkpoint.CheckpointType `
                    -AutomaticCheckpointsEnabled $Source.Checkpoint.AutomaticCheckpointsEnabled
            }
            if ('NetworkAdapters' -in $SelectedProperty) {
                $destinationAdapters = @(Get-VMNetworkAdapter -VM $vm)
                foreach ($sourceAdapter in @($Source.NetworkAdapters)) {
                    $adapter = @($destinationAdapters | Where-Object Name -eq $sourceAdapter.Name)
                    if ($adapter.Count -ne 1) {
                        throw "Expected one destination network adapter named '$($sourceAdapter.Name)'; found $($adapter.Count)."
                    }
                    if ($sourceAdapter.DynamicMacAddressEnabled) {
                        Set-VMNetworkAdapter -VMNetworkAdapter $adapter[0] -DynamicMacAddress
                    } else {
                        Set-VMNetworkAdapter -VMNetworkAdapter $adapter[0] -StaticMacAddress $sourceAdapter.StaticMacAddress
                    }
                    switch ($sourceAdapter.VlanMode) {
                        'Access' {
                            Set-VMNetworkAdapterVlan -VMNetworkAdapter $adapter[0] -Access -VlanId $sourceAdapter.AccessVlanId
                        }
                        'Trunk' {
                            Set-VMNetworkAdapterVlan -VMNetworkAdapter $adapter[0] -Trunk -NativeVlanId $sourceAdapter.NativeVlanId -AllowedVlanIdList $sourceAdapter.AllowedVlanIdList
                        }
                        default {
                            Set-VMNetworkAdapterVlan -VMNetworkAdapter $adapter[0] -Untagged
                        }
                    }
                    if ($CopySwitch) {
                        $switch = Get-VMSwitch -Name $sourceAdapter.SwitchName -ErrorAction SilentlyContinue
                        if ($null -eq $switch) {
                            throw "Destination virtual switch '$($sourceAdapter.SwitchName)' does not exist."
                        }
                        Connect-VMNetworkAdapter -VMNetworkAdapter $adapter[0] -VMSwitch $switch
                    }
                }
            }
            Get-VM -Name $Name
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'VM configuration synchronization completed.'
        $result
    } catch {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status $_.Exception.Message `
            -Failed
        throw
    } finally {
        Close-RemoteSession -Session @($sourceSession, $destinationSession)
    }
}

function Test-VMHelperInteractiveSession {
    if ($env:VMHELPER_REGISTRY_NO_PROMPT -eq '1' -or
        -not [Environment]::UserInteractive -or
        $Host.Name -eq 'ServerRemoteHost') {
        return $false
    }
    try {
        -not [Console]::IsInputRedirected
    } catch {
        $true
    }
}

function Initialize-VMHelperRegistryOnImport {
    $script:VMHelperRegistryConfiguration = Resolve-VMHelperRegistryConfiguration
    if ($script:VMHelperRegistryConfiguration.Mode -eq 'FederatedPull') {
        Write-Verbose (
            'VMHelper federated pull indexes are configured on: {0}.' -f
            ($script:VMHelperRegistryConfiguration.FederatedUtilityServers -join ', ')
        )
        return
    }
    if ($script:VMHelperRegistryConfiguration.Enabled) {
        Write-Verbose "VMHelper distributed registry is available at '$($script:VMHelperRegistryConfiguration.NamespacePath)'."
        return
    }
    $effectiveStartupMode = if ($env:VMHELPER_REGISTRY_NO_PROMPT -eq '1') {
        'Quiet'
    } elseif (-not [string]::IsNullOrWhiteSpace($env:VMHELPER_STARTUP_MODE)) {
        $env:VMHELPER_STARTUP_MODE
    } else {
        $StartupMode
    }
    if ($effectiveStartupMode -notin @('Notify', 'Quiet', 'Prompt', 'Initialize')) {
        throw "VMHELPER_STARTUP_MODE '$effectiveStartupMode' is invalid. Use Notify, Quiet, Prompt, or Initialize."
    }
    if ($script:VMHelperRegistryConfiguration.ConfigurationPresent) {
        if ($effectiveStartupMode -ne 'Quiet') {
            Write-Warning @"
VMHelper imported in LocalOnly mode because the configured distributed registry
'$($script:VMHelperRegistryConfiguration.NamespacePath)' is unavailable.
Target-local durable state remains enabled. Run Get-VMHelperRegistryConfiguration
and Sync-VMResourceTransferRegistry after registry access is restored.
"@
        }
        return
    }
    if ($effectiveStartupMode -eq 'Quiet') {
        return
    }
    if ($effectiveStartupMode -eq 'Notify') {
        Write-Warning @'
VMHelper imported in LocalOnly mode. Durable target-local transfers are available,
but centralized transfer discovery is not configured.
Recommended: run Initialize-VMResourceTransferFederation to configure independent
utility-server pull indexes without requiring DFS or DFS-R permissions.
'@
        return
    }
    if ($effectiveStartupMode -eq 'Initialize') {
        $allowedOptions = @(
            'DomainName'
            'UtilityServer'
            'UtilityServerPattern'
            'WriterPrincipal'
            'ReaderPrincipal'
            'LocalPath'
            'ShareName'
            'ReplicationGroup'
            'RetentionCount'
            'ProgressPercent'
            'ProgressMinutes'
        )
        $unsupportedOptions = @($StartupOptions.Keys |
            Where-Object { $_ -notin $allowedOptions })
        if ($unsupportedOptions.Count -gt 0) {
            throw "Unsupported VMHelper startup option(s): $($unsupportedOptions -join ', ')."
        }
        if (-not $StartupOptions.ContainsKey('WriterPrincipal')) {
            throw "StartupMode Initialize requires StartupOptions.WriterPrincipal."
        }
        if (-not $StartupOptions.ContainsKey('UtilityServer') -and
            -not $StartupOptions.ContainsKey('UtilityServerPattern')) {
            throw 'StartupMode Initialize requires StartupOptions.UtilityServer or StartupOptions.UtilityServerPattern.'
        }
        $initializeParameters = @{}
        foreach ($optionName in $allowedOptions) {
            if ($StartupOptions.ContainsKey($optionName)) {
                $initializeParameters[$optionName] = $StartupOptions[$optionName]
            }
        }
        Initialize-VMResourceTransferRegistry @initializeParameters -Confirm:$false | Out-Null
        $script:VMHelperRegistryConfiguration = Resolve-VMHelperRegistryConfiguration
        return
    }
    if (-not (Test-VMHelperInteractiveSession)) {
        Write-Warning @'
VMHelper Prompt startup mode was requested in a noninteractive session.
No setup changes were made. Run Initialize-VMResourceTransferRegistry explicitly,
or use StartupMode Initialize with complete StartupOptions.
'@
        return
    }

    $initialize = Read-Host 'VMHelper DFS-R registry is not configured. Initialize it now? [y/N]'
    if ($initialize -notmatch '^(?i)y(?:es)?$') {
        Write-Warning 'VMHelper will use target-local transfer state until the distributed registry is configured.'
        return
    }
    $principal = Read-Host 'Enter the AD writer principal (group, gMSA, or domain account)'
    if ([string]::IsNullOrWhiteSpace($principal)) {
        throw 'A writer principal is required to initialize the VMHelper registry.'
    }
    $reader = Read-Host "Enter the AD reader principal, or press Enter to reuse '$principal'"
    if ([string]::IsNullOrWhiteSpace($reader)) {
        $reader = $principal
    }
    $serverInput = Read-Host "Enter comma-separated utility servers, or a regex such as ^(?:BN1|SN5|PHX23|PHX21)ISUTIL\d{2,3}$"
    if ([string]::IsNullOrWhiteSpace($serverInput)) {
        throw 'At least one utility server or a utility-server regular expression is required.'
    }
    $parameters = @{
        WriterPrincipal = $principal
        ReaderPrincipal = $reader
        Confirm = $true
    }
    if ($serverInput.Contains(',') -or $serverInput -match '^[A-Za-z0-9.-]+$') {
        $parameters.UtilityServer = @($serverInput -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ })
    } else {
        $parameters.UtilityServerPattern = $serverInput
    }
    Initialize-VMResourceTransferRegistry @parameters | Out-Null
}

Initialize-VMHelperRegistryOnImport

Export-ModuleMember -Function @(
    'Copy-RemoteItem'
    'Copy-VMResource'
    'Find-VMHost'
    'Get-VMHelperRegistryConfiguration'
    'Get-VMHelperRuntime'
    'Get-VMResourceTransfer'
    'Get-VMResourceTransferFederated'
    'Get-VMResourceTransferHistory'
    'Get-VMResourceTransferPerformanceReport'
    'Initialize-VMResourceTransferRegistry'
    'Initialize-VMResourceTransferFederation'
    'Move-VMToHost'
    'Sync-VMResourceTransferRegistry'
    'Sync-VMResourceTransferFederation'
    'Sync-VMConfiguration'
    'Watch-VMResourceTransfer'
)
