[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'StartupMode',
    Justification = 'Consumed by module startup processing.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'StartupOptions',
    Justification = 'Consumed by module startup processing.'
)]
param(
    [ValidateSet('Notify', 'Quiet', 'Prompt', 'Initialize')]
    [string]$StartupMode = 'Notify',

    [hashtable]$StartupOptions = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configurationManifest = Join-Path $PSScriptRoot `
    '..\DTMS.Configuration\DTMS.Configuration.psd1'
if (-not (Get-Module DTMS.Configuration) -and
    (Test-Path -LiteralPath $configurationManifest -PathType Leaf)) {
    Import-Module $configurationManifest -Force -ErrorAction Stop
}
$script:DTMSConfiguration = if (
    Get-Command Get-DTMSConfiguration -ErrorAction SilentlyContinue
) {
    Get-DTMSConfiguration
} else {
    [pscustomobject]@{
        Execution = [pscustomobject]@{
            DefaultAccount = 'USME\_is_dtms_util$'
            PowerShellEngine = 'Auto'
            TaskPath = '\DTMS\'
            ExecutionTimeLimitHours = 24
            PollIntervalMinutes = 5
        }
        Runway = [pscustomobject]@{
            OperationRoot = 'C:\ProgramData\DTMS\Runway\Operations'
            RebootDelaySeconds = 60
        }
    }
}
$script:DefaultOperationRoot = [string]$script:DTMSConfiguration.Runway.OperationRoot
$script:ActivitySequence = 1000
$script:ActivityFrames = @('|', '/', '-', '\')

function Start-DTMSActivity {
    <#
    .SYNOPSIS
    Announces a DTMS command immediately and starts adaptive progress feedback.
    .DESCRIPTION
    Writes intent to the Information stream before work begins. Interactive
    terminals receive animated Write-Progress output; remoting and redirected
    hosts receive concise textual feedback without animation.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Starts in-memory user feedback and does not change managed system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Intent,

        [string]$Target,

        [ValidateRange(1, 3600)]
        [int]$HeartbeatSeconds = 15
    )

    $mode = if ($env:DTMS_FEEDBACK_MODE) {
        $env:DTMS_FEEDBACK_MODE
    } else {
        'Adaptive'
    }
    if ($mode -notin @('Adaptive', 'Animated', 'Concise', 'Quiet')) {
        $mode = 'Adaptive'
    }
    $interactive = $mode -eq 'Animated' -or (
        $mode -eq 'Adaptive' -and
        [Environment]::UserInteractive -and
        $Host.Name -ne 'ServerRemoteHost' -and
        -not [Console]::IsOutputRedirected
    )
    $activityId = [Threading.Interlocked]::Increment(
        [ref]$script:ActivitySequence
    )
    $now = [DateTime]::UtcNow
    $activity = [pscustomobject]@{
        PSTypeName = 'DTMS.Runway.Activity'
        Id = $activityId
        Name = $Name
        Intent = $Intent
        Target = $Target
        StartedUtc = $now
        LastHeartbeatUtc = $now
        HeartbeatSeconds = $HeartbeatSeconds
        FrameIndex = 0
        Animated = $interactive
        Quiet = $mode -eq 'Quiet'
    }
    if (-not $activity.Quiet) {
        $targetText = if ($Target) { " Target: $Target." } else { '' }
        Write-Information `
            -MessageData "[DTMS] START $Name - $Intent.$targetText" `
            -Tags 'DTMS', 'Activity', 'Start' `
            -InformationAction Continue
        if ($activity.Animated) {
            Write-Progress `
                -Id $activity.Id `
                -Activity $activity.Name `
                -Status "$($script:ActivityFrames[0]) $Intent" `
                -PercentComplete 0
        }
    }
    $activity
}

function Update-DTMSActivity {
    <#
    .SYNOPSIS
    Updates adaptive DTMS progress and emits periodic textual heartbeats.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Updates in-memory user feedback and does not change managed system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Activity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [ValidateRange(-1, 100)]
        [double]$PercentComplete = -1,

        [string]$CurrentOperation,

        [switch]$ForceHeartbeat
    )

    process {
        if ($Activity.Quiet) {
            return
        }
        $Activity.FrameIndex = (
            [int]$Activity.FrameIndex + 1
        ) % $script:ActivityFrames.Count
        $frame = $script:ActivityFrames[$Activity.FrameIndex]
        if ($Activity.Animated) {
            $progressParameters = @{
                Id = $Activity.Id
                Activity = $Activity.Name
                Status = "$frame $Status"
            }
            if ($PercentComplete -ge 0) {
                $progressParameters.PercentComplete = $PercentComplete
            } else {
                $progressParameters.PercentComplete = 0
            }
            if ($CurrentOperation) {
                $progressParameters.CurrentOperation = $CurrentOperation
            }
            Write-Progress @progressParameters
        }
        $now = [DateTime]::UtcNow
        if ($ForceHeartbeat -or
            ($now - [datetime]$Activity.LastHeartbeatUtc).TotalSeconds -ge
                [int]$Activity.HeartbeatSeconds) {
            $percentText = if ($PercentComplete -ge 0) {
                ' ({0:N1}%)' -f $PercentComplete
            } else {
                ''
            }
            Write-Information `
                -MessageData "[DTMS] ACTIVE $($Activity.Name) - $Status$percentText" `
                -Tags 'DTMS', 'Activity', 'Heartbeat' `
                -InformationAction Continue
            $Activity.LastHeartbeatUtc = $now
        }
    }
}

function Complete-DTMSActivity {
    <#
    .SYNOPSIS
    Completes adaptive DTMS progress with elapsed-time feedback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Activity,

        [string]$Status = 'Completed successfully.',

        [switch]$Failed
    )

    process {
        if ($Activity.Quiet) {
            return
        }
        if ($Activity.Animated) {
            Write-Progress `
                -Id $Activity.Id `
                -Activity $Activity.Name `
                -Completed
        }
        $elapsed = [math]::Round(
            ([DateTime]::UtcNow - [datetime]$Activity.StartedUtc).TotalSeconds,
            1
        )
        $state = if ($Failed) { 'FAILED' } else { 'DONE' }
        Write-Information `
            -MessageData "[DTMS] $state $($Activity.Name) - $Status Elapsed: $elapsed seconds." `
            -Tags 'DTMS', 'Activity', $state `
            -InformationAction Continue
    }
}

function ConvertTo-RunwayHashtable {
    param([Parameter(Mandatory)]$InputObject)

    if ($InputObject -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $value = $InputObject[$key]
            $result[$key] = if ($null -ne $value -and
                ($value -is [Collections.IDictionary] -or
                    $value.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject')) {
                ConvertTo-RunwayHashtable -InputObject $value
            } else {
                $value
            }
        }
        return $result
    }
    $result = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $value = $property.Value
        $result[$property.Name] = if ($null -ne $value -and
            ($value -is [Collections.IDictionary] -or
                $value.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject')) {
            ConvertTo-RunwayHashtable -InputObject $value
        } else {
            $value
        }
    }
    $result
}

function Write-RunwayJsonAtomically {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value,
        [int]$Depth = 30
    )

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-DurableOperationReadinessResult {
    <#
    .SYNOPSIS
    Creates a standard DTMS.Runway capability-readiness result.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory readiness value without changing system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Capability,
        [Parameter(Mandatory)]
        [ValidateSet('Ready', 'NotConfigured', 'Unavailable', 'Degraded', 'Unauthorized', 'Incompatible', 'Unknown')]
        [string]$Status,
        [Parameter(Mandatory)][bool]$Required,
        [Parameter(Mandatory)][string]$Message,
        [string]$RemediationCommand
    )

    [pscustomobject]@{
        PSTypeName = 'DTMS.Runway.Readiness'
        Module = $Module
        Capability = $Capability
        Status = $Status
        Required = $Required
        Message = $Message
        RemediationCommand = $RemediationCommand
    }
}

function Get-DurableOperationReadiness {
    <#
    .SYNOPSIS
    Reports readiness for local durable-operation execution.
    #>
    [CmdletBinding()]
    param(
        [string]$OperationRoot = $script:DefaultOperationRoot
    )

    $rootReady = Test-Path -LiteralPath $OperationRoot -PathType Container
    New-DurableOperationReadinessResult `
        -Module 'DTMS.Runway' `
        -Capability 'LocalState' `
        -Status $(if ($rootReady) { 'Ready' } else { 'NotConfigured' }) `
        -Required $true `
        -Message $(if ($rootReady) {
            "Operation root '$OperationRoot' is available."
        } else {
            "Operation root '$OperationRoot' has not been initialized."
        }) `
        -RemediationCommand $(if ($rootReady) { $null } else {
            "Initialize-DurableOperationEnvironment -OperationRoot '$OperationRoot'"
        })

    $scheduledTasksReady = $null -ne (
        Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue
    )
    New-DurableOperationReadinessResult `
        -Module 'DTMS.Runway' `
        -Capability 'ScheduledTasks' `
        -Status $(if ($scheduledTasksReady) { 'Ready' } else { 'Unavailable' }) `
        -Required $true `
        -Message $(if ($scheduledTasksReady) {
            'Windows scheduled-task commands are available.'
        } else {
            'Register-ScheduledTask is unavailable.'
        }) `
        -RemediationCommand $(if ($scheduledTasksReady) { $null } else {
            'Enable or install the Windows ScheduledTasks module.'
        })

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    New-DurableOperationReadinessResult `
        -Module 'DTMS.Runway' `
        -Capability 'PowerShell7Worker' `
        -Status $(if ($pwsh) { 'Ready' } else { 'Degraded' }) `
        -Required $false `
        -Message $(if ($pwsh) {
            "PowerShell 7 worker is available at '$($pwsh.Source)'."
        } else {
            'PowerShell 7 was not found; workers will use Windows PowerShell 5.1.'
        }) `
        -RemediationCommand $(if ($pwsh) { $null } else {
            'Install PowerShell 7 to use the preferred worker runtime.'
        })
}

function Initialize-DurableOperationEnvironment {
    <#
    .SYNOPSIS
    Initializes the local directory used by durable operations.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$OperationRoot = $script:DefaultOperationRoot,
        [string[]]$ExecutionAccount = @('SYSTEM', 'BUILTIN\Administrators')
    )

    $activity = Start-DTMSActivity `
        -Name 'Durable operation environment setup' `
        -Intent 'Create and secure the durable operation root' `
        -Target $OperationRoot
    if ($PSCmdlet.ShouldProcess($OperationRoot, 'initialize durable-operation environment')) {
        New-Item -Path $OperationRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $acl = Get-Acl -LiteralPath $OperationRoot
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($identityName in @($ExecutionAccount | Sort-Object -Unique)) {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new(
                $identityName,
                'FullControl',
                'ContainerInherit,ObjectInherit',
                'None',
                'Allow'
            )
            $acl.SetAccessRule($rule)
        }
        Set-Acl -LiteralPath $OperationRoot -AclObject $acl
    }
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'Durable operation environment evaluation completed.'
    Get-DurableOperationReadiness -OperationRoot $OperationRoot
}

function New-DurableOperationDefinition {
    <#
    .SYNOPSIS
    Creates a versioned declarative durable-operation definition.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns an in-memory declarative definition without changing system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OperationType,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$HandlerModulePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$HandlerCommand,
        [Parameter(Mandatory)][Collections.IDictionary]$Payload,
        [ValidateNotNullOrEmpty()][string]$DefinitionVersion = '1.0',
        [Collections.IDictionary]$Metadata = @{}
    )

    $resolvedHandlerPath = (Resolve-Path -LiteralPath $HandlerModulePath -ErrorAction Stop).Path
    [pscustomobject]@{
        PSTypeName = 'DTMS.Runway.OperationDefinition'
        SchemaVersion = 1
        DefinitionVersion = $DefinitionVersion
        OperationType = $OperationType
        HandlerModulePath = $resolvedHandlerPath
        HandlerCommand = $HandlerCommand
        Payload = [ordered]@{} + $Payload
        Metadata = [ordered]@{} + $Metadata
    }
}

function New-DurableOperation {
    <#
    .SYNOPSIS
    Persists a new durable operation and its initial append-only event.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$Definition,
        [string]$OperationRoot = $script:DefaultOperationRoot,
        [string]$ExecutionAccount
    )

    process {
        if ([string]::IsNullOrWhiteSpace($ExecutionAccount)) {
            $ExecutionAccount = [string](
                $script:DTMSConfiguration.Execution.DefaultAccount
            )
        }
        $operationId = '{0}-{1}' -f (
            Get-Date -Format 'yyyyMMdd-HHmmss'
        ), [guid]::NewGuid().ToString('N')
        $operationPath = Join-Path $OperationRoot $operationId
        if (-not $PSCmdlet.ShouldProcess($operationPath, 'create durable operation')) {
            return
        }
        New-Item -Path $operationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        foreach ($directory in @('Checkpoints', 'Logs', 'Outbox', 'Worker')) {
            New-Item -Path (Join-Path $operationPath $directory) `
                -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $definitionCopy = ConvertTo-RunwayHashtable -InputObject $Definition
        $definitionCopy.Remove('PSTypeName')
        Write-RunwayJsonAtomically `
            -Path (Join-Path $operationPath 'Definition.json') `
            -Value $definitionCopy
        $now = [DateTime]::UtcNow.ToString('o')
        $state = [ordered]@{
            SchemaVersion = 1
            OperationId = $operationId
            OperationType = $Definition.OperationType
            Status = 'Queued'
            CurrentPhase = 'Queued'
            ExecutionAccount = $ExecutionAccount
            AttemptCount = 0
            EventSequence = 0
            ProgressPercent = 0
            CreatedUtc = $now
            UpdatedUtc = $now
            StartedUtc = $null
            CompletedUtc = $null
            TaskName = $null
            TaskPath = $null
            ResumeAfterUtc = $null
            RebootRequestedUtc = $null
            RebootBootUtc = $null
            Message = 'Operation is queued.'
            PhaseHistory = @(
                [ordered]@{
                    Phase = 'Queued'
                    EnteredUtc = $now
                    Message = 'Operation is queued.'
                }
            )
            Metadata = $Definition.Metadata
        }
        Write-RunwayJsonAtomically `
            -Path (Join-Path $operationPath 'State.json') `
            -Value $state
        Add-DurableOperationEvent `
            -OperationRoot $operationPath `
            -EventType 'OperationQueued' `
            -Status Queued `
            -Phase Queued `
            -Message 'Operation is queued.' | Out-Null
        Get-DurableOperation -OperationId $operationId -OperationRoot $OperationRoot
    }
}

function Add-DurableOperationEvent {
    <#
    .SYNOPSIS
    Appends an immutable event to a durable operation's local outbox.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Phase,
        [string]$Message,
        [Nullable[double]]$ProgressPercent,
        [Collections.IDictionary]$Data = @{}
    )

    $statePath = Join-Path $OperationRoot 'State.json'
    $state = ConvertTo-RunwayHashtable -InputObject (
        Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json
    )
    $state.EventSequence = [int]$state.EventSequence + 1
    Write-RunwayJsonAtomically -Path $statePath -Value $state
    $eventId = [guid]::NewGuid().ToString('N')
    $registryEvent = [ordered]@{
        SchemaVersion = 1
        OperationId = $state.OperationId
        OperationType = $state.OperationType
        Sequence = $state.EventSequence
        EventId = $eventId
        EventType = $EventType
        Status = $Status
        Phase = $Phase
        RecordedUtc = [DateTime]::UtcNow.ToString('o')
        ProgressPercent = $ProgressPercent
        Message = $Message
        Data = [ordered]@{} + $Data
    }
    $eventName = '{0:D8}-{1}-{2}.json' -f (
        [int]$state.EventSequence
    ), $EventType, $eventId
    $eventPath = Join-Path (Join-Path $OperationRoot 'Outbox') $eventName
    $stream = [IO.File]::Open(
        $eventPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::Read
    )
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            ($registryEvent | ConvertTo-Json -Depth 30)
        )
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } finally {
        $stream.Dispose()
    }
    [pscustomobject]$registryEvent
}

function Set-DurableOperationPhase {
    <#
    .SYNOPSIS
    Atomically checkpoints a durable operation phase and appends an event.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Called noninteractively by durable workers to checkpoint authoritative operation state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)][string]$Phase,
        [ValidateSet(
            'Queued', 'Running', 'Waiting', 'AwaitingReboot', 'NeedsReview',
            'Succeeded', 'Failed', 'RollingBack', 'RolledBack',
            'RollbackFailed', 'Cancelled'
        )]
        [string]$Status = 'Running',
        [string]$Message,
        [Nullable[double]]$ProgressPercent
    )

    $statePath = Join-Path $OperationRoot 'State.json'
    $state = ConvertTo-RunwayHashtable -InputObject (
        Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json
    )
    $now = [DateTime]::UtcNow.ToString('o')
    if ($state.CurrentPhase -ne $Phase) {
        $state.PhaseHistory = @($state.PhaseHistory) + @(
            [ordered]@{
                Phase = $Phase
                EnteredUtc = $now
                Message = $Message
            }
        )
    }
    $state.CurrentPhase = $Phase
    $state.Status = $Status
    $state.Message = $Message
    $state.UpdatedUtc = $now
    if ($null -ne $ProgressPercent) {
        $state.ProgressPercent = [math]::Round([double]$ProgressPercent, 2)
    }
    if ($Status -eq 'Running' -and -not $state.StartedUtc) {
        $state.StartedUtc = $now
    }
    if ($Status -in @(
        'Succeeded', 'Failed', 'NeedsReview', 'RolledBack',
        'RollbackFailed', 'Cancelled'
    )) {
        $state.CompletedUtc = $now
    }
    Write-RunwayJsonAtomically -Path $statePath -Value $state
    Add-DurableOperationEvent `
        -OperationRoot $OperationRoot `
        -EventType $(if ($Status -in @(
            'Succeeded', 'Failed', 'NeedsReview', 'RolledBack',
            'RollbackFailed', 'Cancelled'
        )) {
            'OperationCompleted'
        } else {
            'PhaseChanged'
        }) `
        -Status $Status `
        -Phase $Phase `
        -Message $Message `
        -ProgressPercent $ProgressPercent | Out-Null
    Get-DurableOperation -OperationId $state.OperationId -OperationRoot (Split-Path $OperationRoot -Parent)
}

function Write-DurableOperationProgress {
    <#
    .SYNOPSIS
    Records normalized progress for a durable operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)][ValidateRange(0, 100)][double]$PercentComplete,
        [string]$Message
    )

    $state = Get-Content -LiteralPath (Join-Path $OperationRoot 'State.json') -Raw |
        ConvertFrom-Json
    Set-DurableOperationPhase `
        -OperationRoot $OperationRoot `
        -Phase $state.CurrentPhase `
        -Status $state.Status `
        -Message $Message `
        -ProgressPercent $PercentComplete
}

function Get-DurableOperation {
    <#
    .SYNOPSIS
    Gets durable operations from authoritative local state.
    #>
    [CmdletBinding()]
    param(
        [string]$OperationId,
        [string]$OperationRoot = $script:DefaultOperationRoot,
        [switch]$Active,
        [switch]$Latest
    )

    if (-not (Test-Path -LiteralPath $OperationRoot -PathType Container)) {
        return
    }
    $paths = if ($OperationId) {
        @(Join-Path $OperationRoot $OperationId)
    } else {
        @(Get-ChildItem -LiteralPath $OperationRoot -Directory -ErrorAction Stop |
            Select-Object -ExpandProperty FullName)
    }
    $results = foreach ($path in $paths) {
        $statePath = Join-Path $path 'State.json'
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $state | Add-Member NoteProperty OperationRoot $path -Force
            $state.PSObject.TypeNames.Insert(0, 'DTMS.Runway.Operation')
            $state
        }
    }
    $results = @($results | Sort-Object UpdatedUtc -Descending)
    if ($Active) {
        $results = @($results | Where-Object Status -in @(
            'Queued', 'Running', 'Waiting', 'AwaitingReboot', 'RollingBack'
        ))
    }
    if ($Latest) {
        $results = @($results | Select-Object -First 1)
    }
    $results
}

function Initialize-RunwayTaskPath {
    param([Parameter(Mandatory)][string]$TaskPath)

    if ($TaskPath -eq '\') {
        return
    }
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    foreach ($segment in @($TaskPath.Trim('\') -split '\\' |
        Where-Object { $_ })) {
        try {
            $folder = $folder.GetFolder($segment)
        } catch {
            $folder = $folder.CreateFolder($segment)
        }
    }
}

function Suspend-DurableOperation {
    <#
    .SYNOPSIS
    Checkpoints a durable operation for a later scheduled invocation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reason,

        [datetime]$ResumeAfterUtc = [DateTime]::UtcNow
    )

    $statePath = Join-Path $OperationRoot 'State.json'
    $state = ConvertTo-RunwayHashtable -InputObject (
        Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    )
    $state.Status = 'Waiting'
    $state.CurrentPhase = 'Waiting'
    $state.Message = $Reason
    $state.ResumeAfterUtc = $ResumeAfterUtc.ToUniversalTime().ToString('o')
    $state.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    Write-RunwayJsonAtomically -Path $statePath -Value $state
    Add-DurableOperationEvent `
        -OperationRoot $OperationRoot `
        -EventType 'OperationSuspended' `
        -Status 'Waiting' `
        -Phase 'Waiting' `
        -Message $Reason | Out-Null
    [pscustomobject]@{
        PSTypeName = 'DTMS.Runway.Suspension'
        Status = 'Waiting'
        Reason = $Reason
        ResumeAfterUtc = $state.ResumeAfterUtc
    }
}

function Request-DurableOperationReboot {
    <#
    .SYNOPSIS
    Checkpoints an operation and optionally requests a restart.
    .DESCRIPTION
    Records the current boot session before restarting. The Runway worker will
    not resume the handler until a later boot session is observed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$OperationRoot,

        [string]$Reason = 'The durable operation requires a reboot.',

        [ValidateRange(0, 3600)]
        [int]$DelaySeconds = [int](
            $script:DTMSConfiguration.Runway.RebootDelaySeconds
        ),

        [switch]$Restart
    )

    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $bootUtc = $operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o')
    $statePath = Join-Path $OperationRoot 'State.json'
    $state = ConvertTo-RunwayHashtable -InputObject (
        Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    )
    $state.Status = 'AwaitingReboot'
    $state.CurrentPhase = 'AwaitingReboot'
    $state.Message = $Reason
    $state.RebootRequestedUtc = [DateTime]::UtcNow.ToString('o')
    $state.RebootBootUtc = $bootUtc
    $state.UpdatedUtc = $state.RebootRequestedUtc
    Write-RunwayJsonAtomically -Path $statePath -Value $state
    Add-DurableOperationEvent `
        -OperationRoot $OperationRoot `
        -EventType 'RebootRequested' `
        -Status 'AwaitingReboot' `
        -Phase 'AwaitingReboot' `
        -Message $Reason | Out-Null
    $result = [pscustomobject]@{
        PSTypeName = 'DTMS.Runway.Suspension'
        Status = 'AwaitingReboot'
        Reason = $Reason
        RebootBootUtc = $bootUtc
    }
    if ($Restart -and $PSCmdlet.ShouldProcess(
        $env:COMPUTERNAME,
        "restart after $DelaySeconds seconds"
    )) {
        & shutdown.exe /r /t $DelaySeconds /d p:4:1 /c $Reason
        if ($LASTEXITCODE -ne 0) {
            throw "shutdown.exe failed with exit code $LASTEXITCODE."
        }
    }
    $result
}

function Start-DurableOperation {
    <#
    .SYNOPSIS
    Packages and starts a durable operation in a Windows scheduled task.
    .DESCRIPTION
    Preparation and module staging run as the caller. The scheduled worker
    invokes the declared handler as the selected execution account. The
    handler command receives OperationRoot and Payload parameters.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$Definition,
        [string]$ComputerName = $env:COMPUTERNAME,
        [string]$OperationRoot = $script:DefaultOperationRoot,
        [pscredential]$ExecutionCredential,
        [string]$ExecutionAccount,

        [ValidateSet('Auto', 'PowerShell7', 'WindowsPowerShell')]
        [string]$PowerShellEngine,

        [ValidateRange(1, 168)]
        [int]$ExecutionTimeLimitHours,

        [ValidateRange(1, 1440)]
        [int]$PollIntervalMinutes,

        [string]$TaskPath
    )

    process {
        $activity = Start-DTMSActivity `
            -Name 'Durable operation launch' `
            -Intent "Stage and schedule '$($Definition.OperationType)'" `
            -Target $ComputerName
        if ([string]::IsNullOrWhiteSpace($ExecutionAccount)) {
            $ExecutionAccount = [string](
                $script:DTMSConfiguration.Execution.DefaultAccount
            )
        }
        if ([string]::IsNullOrWhiteSpace($PowerShellEngine)) {
            $PowerShellEngine = [string](
                $script:DTMSConfiguration.Execution.PowerShellEngine
            )
        }
        if ($ExecutionTimeLimitHours -eq 0) {
            $ExecutionTimeLimitHours = [int](
                $script:DTMSConfiguration.Execution.ExecutionTimeLimitHours
            )
        }
        if ($PollIntervalMinutes -eq 0) {
            $PollIntervalMinutes = [int](
                $script:DTMSConfiguration.Execution.PollIntervalMinutes
            )
        }
        if ([string]::IsNullOrWhiteSpace($TaskPath)) {
            $TaskPath = [string]$script:DTMSConfiguration.Execution.TaskPath
        }
        if ($ExecutionCredential) {
            $ExecutionAccount = $ExecutionCredential.UserName
        } elseif ($ExecutionAccount -ne 'SYSTEM' -and -not $ExecutionAccount.EndsWith('$')) {
            throw 'A normal domain execution account requires ExecutionCredential. Use a trailing-dollar gMSA or SYSTEM otherwise.'
        }
        if (-not $PSCmdlet.ShouldProcess(
            "$ComputerName\$OperationRoot",
            "stage and start durable operation '$($Definition.OperationType)'"
        )) {
            Complete-DTMSActivity `
                -Activity $activity `
                -Status 'Durable operation launch was not started.'
            return
        }
        $localComputer = $ComputerName -in @('.', 'localhost', $env:COMPUTERNAME)
        if (-not $localComputer) {
            throw 'This release stages workers locally. Invoke Start-DurableOperation through remoting on the target computer.'
        }
        $operation = New-DurableOperation `
            -Definition $Definition `
            -OperationRoot $OperationRoot `
            -ExecutionAccount $ExecutionAccount `
            -Confirm:$false
            $operationPath = $operation.OperationRoot
            $workerRoot = Join-Path $operationPath 'Worker'
            $runwayDestination = Join-Path $workerRoot 'DTMS.Runway'
            Copy-Item -LiteralPath $PSScriptRoot -Destination $runwayDestination -Recurse -Force
            $handlerModulePath = [string]$Definition.HandlerModulePath
            $handlerSourceRoot = Split-Path $handlerModulePath -Parent
            $handlerDestination = Join-Path $workerRoot 'Handler'
            Copy-Item -LiteralPath $handlerSourceRoot -Destination $handlerDestination -Recurse -Force
            $handlerLeaf = Split-Path $handlerModulePath -Leaf
            $workerConfiguration = [ordered]@{
                RunwayManifest = Join-Path $runwayDestination 'DTMS.Runway.psd1'
                HandlerModule = Join-Path $handlerDestination $handlerLeaf
                HandlerCommand = $Definition.HandlerCommand
            }
            Write-RunwayJsonAtomically `
                -Path (Join-Path $workerRoot 'WorkerConfiguration.json') `
                -Value $workerConfiguration
            $workerScript = @'
param([Parameter(Mandatory)][string]$OperationRoot)
$ErrorActionPreference = 'Stop'
$workerRoot = Join-Path $OperationRoot 'Worker'
$configuration = Get-Content -LiteralPath (Join-Path $workerRoot 'WorkerConfiguration.json') -Raw | ConvertFrom-Json
Import-Module $configuration.RunwayManifest -ArgumentList 'Quiet' -Force -ErrorAction Stop
Import-Module $configuration.HandlerModule -Force -ErrorAction Stop
$definition = Get-Content -LiteralPath (Join-Path $OperationRoot 'Definition.json') -Raw | ConvertFrom-Json
$statePath = Join-Path $OperationRoot 'State.json'
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($state.Status -in @('Succeeded', 'Failed', 'NeedsReview', 'Cancelled')) { return }
if ($state.Status -eq 'Waiting' -and $state.ResumeAfterUtc -and
    [DateTime]::UtcNow -lt [datetime]$state.ResumeAfterUtc) { return }
if ($state.Status -eq 'AwaitingReboot') {
    $currentBootUtc = (
        Get-CimInstance Win32_OperatingSystem
    ).LastBootUpTime.ToUniversalTime()
    if ($state.RebootBootUtc -and
        $currentBootUtc -le [datetime]$state.RebootBootUtc) { return }
}
try {
    Set-DurableOperationPhase -OperationRoot $OperationRoot -Phase Starting -Status Running -Message 'Scheduled worker started.' | Out-Null
    & $configuration.HandlerCommand `
        -OperationRoot $OperationRoot `
        -Payload $definition.Payload | Out-Null
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.Status -notin @('Waiting', 'AwaitingReboot', 'NeedsReview')) {
        Set-DurableOperationPhase -OperationRoot $OperationRoot -Phase Completed -Status Succeeded -Message 'Operation completed successfully.' -ProgressPercent 100 | Out-Null
    }
} catch {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.Status -ne 'NeedsReview') {
        Set-DurableOperationPhase -OperationRoot $OperationRoot -Phase Failed -Status Failed -Message $_.Exception.Message | Out-Null
    }
    throw
}
'@
            $workerPath = Join-Path $workerRoot 'Start-Worker.ps1'
            Set-Content -LiteralPath $workerPath -Value $workerScript -Encoding UTF8
            $taskName = "Runway-$($operation.OperationId)"
            $powerShell7Path = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
            $windowsPowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            if ($PowerShellEngine -in @('Auto', 'PowerShell7') -and
                (Test-Path -LiteralPath $powerShell7Path -PathType Leaf)) {
                $powerShellPath = $powerShell7Path
            } elseif ($PowerShellEngine -eq 'PowerShell7') {
                throw 'PowerShell 7 was requested but pwsh.exe was not found.'
            } elseif (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf) {
                $powerShellPath = $windowsPowerShellPath
            } else {
                throw 'No compatible PowerShell worker executable was found.'
            }
            $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -OperationRoot "{1}"' -f $workerPath, $operationPath
            $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
            $triggers = @(
                New-ScheduledTaskTrigger -AtStartup
                New-ScheduledTaskTrigger `
                    -Once `
                    -At (Get-Date).AddMinutes(1) `
                    -RepetitionInterval (
                        New-TimeSpan -Minutes $PollIntervalMinutes
                    ) `
                    -RepetitionDuration (New-TimeSpan -Days 3650)
            )
            $settings = New-ScheduledTaskSettingsSet `
                -StartWhenAvailable `
                -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit (
                    New-TimeSpan -Hours $ExecutionTimeLimitHours
                ) `
                -RestartCount 3 `
                -RestartInterval (New-TimeSpan -Minutes 1)
            Initialize-RunwayTaskPath -TaskPath $TaskPath
            if ($ExecutionCredential) {
                Register-ScheduledTask `
                    -TaskName $taskName `
                    -TaskPath $TaskPath `
                    -Action $action `
                    -Trigger $triggers `
                    -Settings $settings `
                    -User $ExecutionAccount `
                    -Password ($ExecutionCredential.GetNetworkCredential().Password) `
                    -RunLevel Highest `
                    -Force | Out-Null
            } else {
                $logonType = if ($ExecutionAccount -eq 'SYSTEM') {
                    'ServiceAccount'
                } elseif ($ExecutionAccount.EndsWith('$')) {
                    'Password'
                } else {
                    'Password'
                }
                $principal = New-ScheduledTaskPrincipal `
                    -UserId $ExecutionAccount `
                    -LogonType $logonType `
                    -RunLevel Highest
                Register-ScheduledTask `
                    -TaskName $taskName `
                    -TaskPath $TaskPath `
                    -Action $action `
                    -Trigger $triggers `
                    -Settings $settings `
                    -Principal $principal `
                    -Force | Out-Null
            }
            $statePath = Join-Path $operationPath 'State.json'
            $operationState = ConvertTo-RunwayHashtable -InputObject (
                Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            )
            $operationState.TaskName = $taskName
            $operationState.TaskPath = $TaskPath
            Write-RunwayJsonAtomically `
                -Path $statePath `
                -Value $operationState
            Start-ScheduledTask -TaskName $taskName -TaskPath $TaskPath
            $operation | Add-Member NoteProperty TaskName $taskName -Force
            $operation | Add-Member NoteProperty TaskPath $TaskPath -Force
            Complete-DTMSActivity `
                -Activity $activity `
                -Status "Scheduled task '$taskName' was started."
            $operation
    }
}

function Invoke-RunwayStartup {
    $effectiveMode = if ($env:DTMS_RUNWAY_STARTUP_MODE) {
        $env:DTMS_RUNWAY_STARTUP_MODE
    } else {
        $StartupMode
    }
    if ($effectiveMode -notin @('Notify', 'Quiet', 'Prompt', 'Initialize')) {
        throw "DTMS_RUNWAY_STARTUP_MODE '$effectiveMode' is invalid."
    }
    $operationRoot = if ($StartupOptions.ContainsKey('OperationRoot')) {
        [string]$StartupOptions.OperationRoot
    } else {
        $script:DefaultOperationRoot
    }
    $readiness = @(Get-DurableOperationReadiness -OperationRoot $operationRoot)
    $missing = @($readiness | Where-Object Status -notin @('Ready', 'Degraded'))
    if ($effectiveMode -eq 'Initialize') {
        Initialize-DurableOperationEnvironment `
            -OperationRoot $operationRoot `
            -Confirm:$false | Out-Null
    } elseif ($effectiveMode -eq 'Prompt' -and $missing.Count -gt 0) {
        if ([Environment]::UserInteractive -and $Host.Name -ne 'ServerRemoteHost') {
            $answer = Read-Host "DTMS.Runway local state is not initialized at '$operationRoot'. Initialize now? [y/N]"
            if ($answer -match '^(?i)y(?:es)?$') {
                Initialize-DurableOperationEnvironment `
                    -OperationRoot $operationRoot `
                    -Confirm:$false | Out-Null
            }
        } else {
            Write-Warning 'DTMS.Runway Prompt mode was requested in a noninteractive session. No changes were made.'
        }
    } elseif ($effectiveMode -eq 'Notify' -and $missing.Count -gt 0) {
        Write-Warning @"
DTMS.Runway imported with required capabilities unavailable: $(
    $missing.Capability -join ', '
).
No changes were made. Run Get-DurableOperationReadiness for details and
Initialize-DurableOperationEnvironment to create local durable state.
"@
    }
}

Invoke-RunwayStartup

Export-ModuleMember -Function @(
    'Add-DurableOperationEvent'
    'Complete-DTMSActivity'
    'Get-DurableOperation'
    'Get-DurableOperationReadiness'
    'Initialize-DurableOperationEnvironment'
    'New-DurableOperation'
    'New-DurableOperationDefinition'
    'New-DurableOperationReadinessResult'
    'Request-DurableOperationReboot'
    'Set-DurableOperationPhase'
    'Start-DurableOperation'
    'Start-DTMSActivity'
    'Suspend-DurableOperation'
    'Update-DTMSActivity'
    'Write-DurableOperationProgress'
)
