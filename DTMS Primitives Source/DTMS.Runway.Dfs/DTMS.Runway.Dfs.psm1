[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Invoke-Command script blocks declare values with param() and receive them through ArgumentList.'
)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runwayManifest = Join-Path $PSScriptRoot '..\DTMS.Runway\DTMS.Runway.psd1'
if (-not (Get-Module -Name DTMS.Runway) -and
    (Test-Path -LiteralPath $runwayManifest -PathType Leaf)) {
    Import-Module $runwayManifest -ArgumentList Quiet -Force -ErrorAction Stop
}

function Get-DurableOperationRegistryConfiguration {
    <#
    .SYNOPSIS
    Resolves the shared DFS durable-operation registry configuration.
    #>
    [CmdletBinding()]
    param(
        [string]$NamespacePath = $env:DTMS_RUNWAY_REGISTRY_NAMESPACE,
        [ValidateRange(1, 10000)][int]$RetentionCount = 90
    )

    if ($env:DTMS_RUNWAY_REGISTRY_RETENTION_COUNT -as [int]) {
        $RetentionCount = [int]$env:DTMS_RUNWAY_REGISTRY_RETENTION_COUNT
    }
    $available = $false
    if (-not [string]::IsNullOrWhiteSpace($NamespacePath)) {
        try {
            $available = Test-Path -LiteralPath $NamespacePath -PathType Container -ErrorAction Stop
        } catch {
            Write-Verbose "Registry availability check failed: $($_.Exception.Message)"
        }
    }
    [pscustomobject]@{
        PSTypeName = 'DTMS.Runway.Dfs.Configuration'
        NamespacePath = $NamespacePath
        Enabled = $available
        ConfigurationPresent = -not [string]::IsNullOrWhiteSpace($NamespacePath)
        RetentionCount = $RetentionCount
    }
}

function Sync-DurableOperationRegistry {
    <#
    .SYNOPSIS
    Publishes pending immutable operation events to a DFS namespace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('TransactionRoot')]
        [string]$OperationRoot,
        [string]$NamespacePath = $env:DTMS_RUNWAY_REGISTRY_NAMESPACE
    )

    process {
        $activity = Start-DTMSActivity `
            -Name 'Durable registry synchronization' `
            -Intent 'Publish pending immutable operation events' `
            -Target $OperationRoot
        $configuration = Get-DurableOperationRegistryConfiguration `
            -NamespacePath $NamespacePath
        $outboxPath = @(
            (Join-Path $OperationRoot 'Outbox')
            (Join-Path $OperationRoot 'RegistryOutbox')
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
            Select-Object -First 1
        if (-not $outboxPath) {
            $pendingCount = 0
        } else {
            if ($configuration.Enabled) {
                foreach ($eventFile in @(Get-ChildItem $outboxPath -Filter '*.json' -File |
                    Sort-Object Name)) {
                    try {
                        $registryEvent = Get-Content $eventFile.FullName -Raw |
                            ConvertFrom-Json
                        $operationIdProperty = $registryEvent.PSObject.Properties['operationId']
                        $transferIdProperty = $registryEvent.PSObject.Properties['transferId']
                        $operationId = if ($operationIdProperty -and $operationIdProperty.Value) {
                            $operationIdProperty.Value
                        } elseif ($transferIdProperty -and $transferIdProperty.Value) {
                            $transferIdProperty.Value
                        } else {
                            Split-Path $OperationRoot -Leaf
                        }
                        $eventsRoot = Join-Path (
                            Join-Path $configuration.NamespacePath $operationId
                        ) 'Events'
                        New-Item -Path $eventsRoot -ItemType Directory -Force | Out-Null
                        $destinationPath = Join-Path $eventsRoot $eventFile.Name
                        $sourceBytes = [IO.File]::ReadAllBytes($eventFile.FullName)
                        if (-not (Test-Path $destinationPath -PathType Leaf)) {
                            $stream = [IO.File]::Open(
                                $destinationPath,
                                [IO.FileMode]::CreateNew,
                                [IO.FileAccess]::Write,
                                [IO.FileShare]::Read
                            )
                            try {
                                $stream.Write($sourceBytes, 0, $sourceBytes.Length)
                                $stream.Flush()
                            } finally {
                                $stream.Dispose()
                            }
                        } else {
                            $destinationBytes = [IO.File]::ReadAllBytes($destinationPath)
                            $sha = [Security.Cryptography.SHA256]::Create()
                            try {
                                $sourceHash = [BitConverter]::ToString($sha.ComputeHash($sourceBytes))
                                $destinationHash = [BitConverter]::ToString($sha.ComputeHash($destinationBytes))
                            } finally {
                                $sha.Dispose()
                            }
                            if ($sourceHash -ne $destinationHash) {
                                throw "Registry event collision at '$destinationPath'."
                            }
                        }
                        Remove-Item $eventFile.FullName -Force
                    } catch {
                        Write-Warning "Registry publication remains pending for '$($eventFile.Name)': $($_.Exception.Message)"
                        break
                    }
                }
            }
            $pendingCount = @(Get-ChildItem $outboxPath -Filter '*.json' -File).Count
        }
        $statePath = Join-Path $OperationRoot 'State.json'
        if (Test-Path $statePath -PathType Leaf) {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            foreach ($entry in @{
                RegistryPendingEventCount = $pendingCount
                RegistryPublicationPending = $pendingCount -gt 0
            }.GetEnumerator()) {
                if ($null -eq $state.PSObject.Properties[$entry.Key]) {
                    $state | Add-Member NoteProperty $entry.Key $entry.Value
                } else {
                    $state.($entry.Key) = $entry.Value
                }
            }
            $temporaryPath = "$statePath.tmp"
            $state | ConvertTo-Json -Depth 30 |
                Set-Content $temporaryPath -Encoding UTF8
            Move-Item $temporaryPath $statePath -Force
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status "$pendingCount registry event(s) remain pending."
        [pscustomobject]@{
            PSTypeName = 'DTMS.Runway.Dfs.SyncResult'
            OperationRoot = $OperationRoot
            RegistryNamespace = $configuration.NamespacePath
            RegistryAvailable = $configuration.Enabled
            PendingEventCount = $pendingCount
            Synchronized = $pendingCount -eq 0
        }
    }
}

function Get-DurableOperationRegistry {
    <#
    .SYNOPSIS
    Reduces replicated append-only events into current operation status.
    #>
    [CmdletBinding()]
    param(
        [string]$OperationId,
        [string]$NamespacePath = $env:DTMS_RUNWAY_REGISTRY_NAMESPACE,
        [switch]$Active,
        [switch]$Latest
    )

    $configuration = Get-DurableOperationRegistryConfiguration -NamespacePath $NamespacePath
    if (-not $configuration.Enabled) {
        throw "The durable-operation registry '$NamespacePath' is unavailable."
    }
    $roots = if ($OperationId) {
        $path = Join-Path $NamespacePath $OperationId
        if (-not (Test-Path $path -PathType Container)) {
            throw "Operation '$OperationId' was not found."
        }
        @(Get-Item $path)
    } else {
        @(Get-ChildItem $NamespacePath -Directory)
    }
    $results = foreach ($root in $roots) {
        $eventsPath = Join-Path $root.FullName 'Events'
        if (-not (Test-Path $eventsPath -PathType Container)) {
            continue
        }
        $events = @(Get-ChildItem $eventsPath -Filter '*.json' -File |
            ForEach-Object {
                try {
                    Get-Content $_.FullName -Raw | ConvertFrom-Json
                } catch {
                    Write-Warning "Ignoring invalid registry event '$($_.FullName)': $($_.Exception.Message)"
                }
            } |
            Group-Object eventId |
            ForEach-Object { $_.Group | Select-Object -First 1 } |
            Sort-Object { [long]$_.sequence }, recordedUtc)
        if ($events.Count -eq 0) {
            continue
        }
        $terminal = @($events | Where-Object {
            $_.status -in @(
                'Succeeded', 'Completed', 'Failed', 'Cancelled',
                'RolledBack', 'RollbackFailed'
            ) -or $_.eventType -in @(
                'OperationCompleted', 'TransferCompleted', 'TransferFailed',
                'TransferRolledBack', 'TransferRollbackFailed'
            )
        } | Sort-Object { [long]$_.sequence } -Descending)
        $current = if ($terminal.Count -gt 0) { $terminal[0] } else { $events[-1] }
        if ($Active -and $current.status -notin @('Queued', 'Running', 'RollingBack')) {
            continue
        }
        $progress = @($events | Where-Object {
            $property = $_.PSObject.Properties['progressPercent']
            $null -ne $property -and $null -ne $property.Value
        } |
            Sort-Object { [long]$_.sequence } -Descending |
            Select-Object -First 1)
        $sequences = @($events.sequence | ForEach-Object { [long]$_ } | Sort-Object -Unique)
        $getEventValue = {
            param($EventObject, $Name, $DefaultValue)
            $property = $EventObject.PSObject.Properties[$Name]
            if ($null -ne $property) {
                return $property.Value
            }
            $DefaultValue
        }
        $operationEventId = & $getEventValue $current 'operationId' $null
        $transferEventId = & $getEventValue $current 'transferId' $null
        $resolvedId = if ($operationEventId) {
            $operationEventId
        } elseif ($transferEventId) {
            $transferEventId
        } else {
            $root.Name
        }
        [pscustomobject]@{
            PSTypeName = 'DTMS.Runway.RegistryOperation'
            OperationId = $resolvedId
            OperationType = & $getEventValue $current 'operationType' $null
            Status = $current.status
            CurrentPhase = $current.phase
            ProgressPercent = if ($progress.Count) {
                $progress[0].PSObject.Properties['progressPercent'].Value
            } else {
                $null
            }
            UpdatedUtc = $current.recordedUtc
            CreatedUtc = $events[0].recordedUtc
            CompletedUtc = if ($terminal.Count) { $current.recordedUtc } else { $null }
            Message = & $getEventValue $current 'message' $null
            Metadata = & $getEventValue $current 'data' $null
            RegistryRoot = $root.FullName
            RegistryHistoryComplete = $sequences.Count -gt 0 -and
                $sequences[0] -eq 1 -and $sequences.Count -eq $sequences[-1]
            RegistryEventCount = $events.Count
            Events = $events
        }
    }
    $results = @($results | Sort-Object { [datetime]$_.UpdatedUtc } -Descending)
    if ($Latest) { $results | Select-Object -First 1 } else { $results }
}

function Invoke-DurableOperationRegistryRetention {
    <#
    .SYNOPSIS
    Retains all active operations and the newest terminal operation records.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$NamespacePath = $env:DTMS_RUNWAY_REGISTRY_NAMESPACE,
        [ValidateRange(1, 10000)][int]$RetentionCount = 90
    )

    $activity = Start-DTMSActivity `
        -Name 'Durable registry retention' `
        -Intent "Retain active operations and the newest $RetentionCount terminal operations" `
        -Target $NamespacePath
    $terminal = @(Get-DurableOperationRegistry -NamespacePath $NamespacePath |
        Where-Object Status -in @(
            'Succeeded', 'Completed', 'Failed', 'Cancelled',
            'RolledBack', 'RollbackFailed'
        ) |
        Sort-Object { [datetime]$_.CompletedUtc } -Descending)
    foreach ($expired in @($terminal | Select-Object -Skip $RetentionCount)) {
        if ($PSCmdlet.ShouldProcess($expired.RegistryRoot, 'remove expired registry operation')) {
            Remove-Item $expired.RegistryRoot -Recurse -Force -ErrorAction Stop
        }
    }
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'Registry retention evaluation completed.'
}

function Initialize-DurableOperationDfsRegistry {
    <#
    .SYNOPSIS
    Creates SMB, DFS namespace, and DFS-R infrastructure for operation events.
    .PARAMETER Credential
    Optional administrator credential used for remote utility-server setup.
    The caller still needs permission to manage the domain DFS namespace and
    DFS-R configuration.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$NamespacePath,
        [Parameter(Mandatory)][string[]]$UtilityServer,
        [Parameter(Mandatory)][string]$WriterPrincipal,
        [string]$ReaderPrincipal = $WriterPrincipal,
        [string]$LocalPath = 'C:\ProgramData\DTMS\Runway\Registry',
        [string]$ShareName = 'DTMSRunway$',
        [string]$ReplicationGroup = 'DTMS-Runway',
        [ValidateRange(1, 10000)][int]$RetentionCount = 90,
        [pscredential]$Credential
    )

    $activity = Start-DTMSActivity `
        -Name 'DFS durable registry provisioning' `
        -Intent 'Validate utility servers, create shares, and configure DFS namespace and replication' `
        -Target $NamespacePath
    if ($NamespacePath -notmatch '^\\\\(?<Domain>[^\\]+)\\') {
        throw "NamespacePath '$NamespacePath' must be a domain UNC path."
    }
    $domainName = $Matches.Domain
    $UtilityServer = @($UtilityServer | Sort-Object -Unique)
    if ($UtilityServer.Count -eq 0) {
        throw 'At least one utility server is required.'
    }
    if (-not $PSCmdlet.ShouldProcess(
        $NamespacePath,
        "create distributed operation registry on $($UtilityServer -join ', ')"
    )) {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'Provisioning was not started.'
        return
    }
    foreach ($server in $UtilityServer) {
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Validating administrator access on $server." `
            -ForceHeartbeat
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
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Preparing the registry share on $server." `
            -ForceHeartbeat
        $invokeParameters = @{
            ComputerName = $server
            ArgumentList = @($LocalPath, $ShareName, $WriterPrincipal, $ReaderPrincipal)
            ErrorAction = 'Stop'
            ScriptBlock = {
            param($Path, $Share, $Writer, $Reader)
            New-Item $Path -ItemType Directory -Force | Out-Null
            $acl = Get-Acl $Path
            $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                $Writer, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
            ))
            if ($Reader -ine $Writer) {
                $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                    $Reader, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
                ))
            }
            Set-Acl $Path $acl
            $shareObject = Get-SmbShare -Name $Share -ErrorAction SilentlyContinue
            if ($shareObject -and $shareObject.Path -ine $Path) {
                throw "Share '$Share' already points to '$($shareObject.Path)'."
            }
            if (-not $shareObject) {
                $parameters = @{
                    Name = $Share; Path = $Path
                    FullAccess = 'BUILTIN\Administrators'
                    ChangeAccess = $Writer
                    FolderEnumerationMode = 'AccessBased'
                }
                if ($Reader -ine $Writer) { $parameters.ReadAccess = $Reader }
                New-SmbShare @parameters | Out-Null
            }
        }
        }
        if ($Credential) {
            $invokeParameters.Credential = $Credential
        }
        Invoke-Command @invokeParameters
    }
    Import-Module DFSN -ErrorAction Stop
    Update-DTMSActivity `
        -Activity $activity `
        -Status 'Configuring the DFS namespace.' `
        -ForceHeartbeat
    $firstTarget = "\\$($UtilityServer[0])\$ShareName"
    if (-not (Get-DfsnFolder -Path $NamespacePath -ErrorAction SilentlyContinue)) {
        New-DfsnFolder -Path $NamespacePath -TargetPath $firstTarget `
            -Description 'DTMS.Runway append-only operation registry' `
            -EnableTargetFailback $true | Out-Null
    }
    $targets = @(Get-DfsnFolderTarget $NamespacePath |
        Select-Object -ExpandProperty TargetPath)
    foreach ($server in $UtilityServer) {
        $target = "\\$server\$ShareName"
        if ($target -notin $targets) {
            New-DfsnFolderTarget -Path $NamespacePath -TargetPath $target | Out-Null
        }
    }
    Import-Module DFSR -ErrorAction Stop
    Update-DTMSActivity `
        -Activity $activity `
        -Status 'Configuring DFS replication.' `
        -ForceHeartbeat
    if (-not (Get-DfsReplicationGroup -GroupName $ReplicationGroup `
        -DomainName $domainName -ErrorAction SilentlyContinue)) {
        New-DfsReplicationGroup -GroupName $ReplicationGroup `
            -DomainName $domainName `
            -Description 'DTMS.Runway operation event registry' | Out-Null
    }
    $members = @(Get-DfsrMember -GroupName $ReplicationGroup `
        -DomainName $domainName -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ComputerName)
    foreach ($server in $UtilityServer) {
        if (($server -split '\.')[0] -notin @($members | ForEach-Object { ($_ -split '\.')[0] })) {
            Add-DfsrMember -GroupName $ReplicationGroup `
                -ComputerName $server -DomainName $domainName | Out-Null
        }
    }
    $folderName = 'Operations'
    if (-not (Get-DfsReplicatedFolder -GroupName $ReplicationGroup `
        -FolderName $folderName -DomainName $domainName -ErrorAction SilentlyContinue)) {
        New-DfsReplicatedFolder -GroupName $ReplicationGroup `
            -FolderName $folderName -DfsnPath $NamespacePath `
            -FileNameToExclude @('*.tmp', '*.partial') `
            -DomainName $domainName | Out-Null
    }
    for ($sourceIndex = 0; $sourceIndex -lt $UtilityServer.Count; $sourceIndex++) {
        for ($destinationIndex = $sourceIndex + 1;
            $destinationIndex -lt $UtilityServer.Count;
            $destinationIndex++) {
            $connectionParameters = @{
                GroupName = $ReplicationGroup
                SourceComputerName = $UtilityServer[$sourceIndex]
                DestinationComputerName = $UtilityServer[$destinationIndex]
                DomainName = $domainName
            }
            if (-not (Get-DfsrConnection @connectionParameters -ErrorAction SilentlyContinue)) {
                Add-DfsrConnection @connectionParameters | Out-Null
            }
        }
    }
    for ($index = 0; $index -lt $UtilityServer.Count; $index++) {
        $membership = @{
            GroupName = $ReplicationGroup; FolderName = $folderName
            ComputerName = $UtilityServer[$index]; ContentPath = $LocalPath
            DfsnPath = $NamespacePath; DomainName = $domainName; Force = $true
        }
        if ($index -eq 0) { $membership.PrimaryMember = $true }
        Set-DfsrMembership @membership | Out-Null
    }
    @(
        "DTMS_RUNWAY_REGISTRY_NAMESPACE=$NamespacePath"
        "DTMS_RUNWAY_REGISTRY_RETENTION_COUNT=$RetentionCount"
    ) | Set-Content "\\$($UtilityServer[0])\$ShareName\.env" -Encoding UTF8
    $env:DTMS_RUNWAY_REGISTRY_NAMESPACE = $NamespacePath
    $env:DTMS_RUNWAY_REGISTRY_RETENTION_COUNT = [string]$RetentionCount
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'DFS durable registry provisioning completed.'
    Get-DurableOperationRegistryConfiguration
}

Export-ModuleMember -Function @(
    'Get-DurableOperationRegistry'
    'Get-DurableOperationRegistryConfiguration'
    'Initialize-DurableOperationDfsRegistry'
    'Invoke-DurableOperationRegistryRetention'
    'Sync-DurableOperationRegistry'
)
