# PowerShell 7 is the primary runtime. The requirement below is the minimum
# compatibility floor for direct module imports under Windows PowerShell.
#requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Every remoting script block declares parameters populated through ArgumentList.'
)]
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ModuleRoot = $PSScriptRoot

foreach ($dependency in @('DTMS.Configuration', 'DTMS.Runway')) {
    if (-not (Get-Module $dependency)) {
        $manifest = Join-Path $PSScriptRoot `
            "..\$dependency\$dependency.psd1"
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $argumentList = if ($dependency -eq 'DTMS.Runway') {
                @('Quiet')
            } else {
                @()
            }
            Import-Module $manifest -ArgumentList $argumentList `
                -Force -ErrorAction Stop
        }
    }
}

function Write-ForgeJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 30 |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-ForgeHashtable {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-ForgeHashtable `
                -InputObject $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [Collections.IEnumerable] -and
        $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object {
            ConvertTo-ForgeHashtable -InputObject $_
        })
    }
    if ($InputObject.PSObject.TypeNames -contains
        'System.Management.Automation.PSCustomObject') {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-ForgeHashtable `
                -InputObject $property.Value
        }
        return $result
    }
    $InputObject
}

function Get-OrderedForgeStep {
    param([Parameter(Mandatory)][object[]]$Step)

    $remaining = [Collections.Generic.List[object]]::new()
    foreach ($item in $Step) {
        $remaining.Add($item)
    }
    $ordered = [Collections.Generic.List[object]]::new()
    $completed = @{}
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object {
            $candidate = $_
            @($candidate.DependsOn | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_) -and
                -not $completed.ContainsKey([string]$_)
            }).Count -eq 0
        })
        if ($ready.Count -eq 0) {
            throw 'The Forge plan contains an unresolved dependency cycle.'
        }
        foreach ($item in $ready) {
            $ordered.Add($item)
            $completed[$item.Name] = $true
            [void]$remaining.Remove($item)
        }
    }
    $ordered.ToArray()
}

function New-ForgeStep {
    <#
    .SYNOPSIS
    Defines one declarative preparation or durable execution step.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates an in-memory declarative step without changing system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [ValidateSet('Preparation', 'Execution')]
        [string]$Stage = 'Execution',

        [string[]]$DependsOn = @(),

        [string]$Description = '',

        [switch]$RequiresNetwork,

        [switch]$RetryFailed,

        [switch]$RetryInterrupted
    )

    [pscustomobject]@{
        PSTypeName = 'DTMS.Forge.Step'
        Name = $Name
        Kind = 'Script'
        Stage = $Stage
        DependsOn = @($DependsOn)
        Description = $Description
        RequiresNetwork = $RequiresNetwork.IsPresent
        RetryFailed = $RetryFailed.IsPresent
        RetryInterrupted = $RetryInterrupted.IsPresent
        Script = $ScriptBlock.ToString()
        Source = $null
        Destination = $null
        Mirror = $false
    }
}

function New-ForgeCopyStep {
    <#
    .SYNOPSIS
    Defines a caller-context payload staging step.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates an in-memory declarative step without changing system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [string[]]$DependsOn = @(),

        [string]$Description = '',

        [switch]$Mirror
    )

    [pscustomobject]@{
        PSTypeName = 'DTMS.Forge.Step'
        Name = $Name
        Kind = 'Copy'
        Stage = 'Preparation'
        DependsOn = @($DependsOn)
        Description = $Description
        RequiresNetwork = $true
        RetryFailed = $false
        RetryInterrupted = $false
        Script = $null
        Source = $Source
        Destination = $Destination
        Mirror = $Mirror.IsPresent
    }
}

function New-ForgePlan {
    <#
    .SYNOPSIS
    Creates a validated account-aware declarative workflow plan.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates an in-memory declarative plan without changing system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_. -]{0,79}$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Step,

        [AllowNull()]
        [object]$Data,

        [string]$ExecutionAccount,

        [ValidateSet('Auto', 'PowerShell7', 'WindowsPowerShell')]
        [string]$PowerShellEngine,

        [ValidateRange(1, 168)]
        [int]$ExecutionTimeLimitHours,

        [ValidateRange(1, 1440)]
        [int]$PollIntervalMinutes,

        [string]$TaskPath
    )

    $configuration = Get-DTMSConfiguration
    if ([string]::IsNullOrWhiteSpace($ExecutionAccount)) {
        $ExecutionAccount = [string]$configuration.Execution.DefaultAccount
    }
    if ([string]::IsNullOrWhiteSpace($PowerShellEngine)) {
        $PowerShellEngine = [string]$configuration.Execution.PowerShellEngine
    }
    if ($ExecutionTimeLimitHours -eq 0) {
        $ExecutionTimeLimitHours = [int](
            $configuration.Execution.ExecutionTimeLimitHours
        )
    }
    if ($PollIntervalMinutes -eq 0) {
        $PollIntervalMinutes = [int](
            $configuration.Execution.PollIntervalMinutes
        )
    }
    if ([string]::IsNullOrWhiteSpace($TaskPath)) {
        $TaskPath = [string]$configuration.Execution.TaskPath
    }
    $accountType = if ($ExecutionAccount -ieq 'SYSTEM') {
        'System'
    } elseif ($ExecutionAccount.EndsWith('$')) {
        'GroupManagedServiceAccount'
    } else {
        'User'
    }
    $plan = [pscustomobject]@{
        PSTypeName = 'DTMS.Forge.Plan'
        SchemaVersion = 1
        Name = $Name
        ExecutionAccount = $ExecutionAccount
        AccountType = $accountType
        HasNetworkAccess = $accountType -ne 'System'
        PowerShellEngine = $PowerShellEngine
        ExecutionTimeLimitHours = $ExecutionTimeLimitHours
        PollIntervalMinutes = $PollIntervalMinutes
        TaskPath = $TaskPath
        Data = $Data
        Steps = @($Step)
    }
    $validation = @(Test-ForgePlan -Plan $plan)
    if ($validation.Count -gt 0) {
        throw "Invalid Forge plan:`n - $($validation -join "`n - ")"
    }
    $plan
}

function Test-ForgePlan {
    <#
    .SYNOPSIS
    Returns validation errors for a Forge plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Plan
    )

    process {
        $errors = [Collections.Generic.List[string]]::new()
        $steps = @($Plan.Steps)
        if ($steps.Count -eq 0) {
            $errors.Add('At least one step is required.')
            return $errors.ToArray()
        }
        $names = @{}
        foreach ($step in $steps) {
            if ($step.Name -notmatch
                '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$') {
                $errors.Add("Step name '$($step.Name)' is invalid.")
                continue
            }
            if ($names.ContainsKey($step.Name)) {
                $errors.Add("Step name '$($step.Name)' is duplicated.")
            } else {
                $names[$step.Name] = $step
            }
            if ($step.Stage -notin @('Preparation', 'Execution')) {
                $errors.Add(
                    "Step '$($step.Name)' has unsupported stage '$($step.Stage)'."
                )
            }
            if ($step.Kind -notin @('Script', 'Copy')) {
                $errors.Add(
                    "Step '$($step.Name)' has unsupported kind '$($step.Kind)'."
                )
            }
            if ($step.Kind -eq 'Script' -and
                [string]::IsNullOrWhiteSpace([string]$step.Script)) {
                $errors.Add("Script step '$($step.Name)' has no script.")
            }
            if ($step.Stage -eq 'Execution' -and
                $step.RequiresNetwork -and -not $Plan.HasNetworkAccess) {
                $errors.Add(
                    "Execution step '$($step.Name)' requires network access, " +
                    'but SYSTEM does not provide domain network identity.'
                )
            }
        }
        foreach ($step in $steps) {
            foreach ($dependency in @($step.DependsOn) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) {
                if (-not $names.ContainsKey($dependency)) {
                    $errors.Add(
                        "Step '$($step.Name)' depends on unknown step '$dependency'."
                    )
                } elseif ($step.Stage -eq 'Preparation' -and
                    $names[$dependency].Stage -eq 'Execution') {
                    $errors.Add(
                        "Preparation step '$($step.Name)' cannot depend on " +
                        "execution step '$dependency'."
                    )
                }
            }
        }
        try {
            Get-OrderedForgeStep -Step $steps | Out-Null
        } catch {
            $errors.Add($_.Exception.Message)
        }
        $errors.ToArray()
    }
}

function Invoke-ForgePreparation {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$TargetStagingRoot,
        [Management.Automation.Runspaces.PSSession]$Session
    )

    $ordered = @(Get-OrderedForgeStep -Step @($Plan.Steps))
    $context = [pscustomobject]@{
        Data = $Plan.Data
        StagingRoot = $TargetStagingRoot
        ComputerName = if ($Session) {
            $Session.ComputerName
        } else {
            $env:COMPUTERNAME
        }
        Session = $Session
    }
    foreach ($step in @($ordered | Where-Object Stage -eq 'Preparation')) {
        if ($step.Kind -eq 'Copy') {
            if (-not (Test-Path -LiteralPath $step.Source)) {
                throw "Forge copy source does not exist: $($step.Source)"
            }
            $destination = Join-Path $TargetStagingRoot $step.Destination
            if ($Session) {
                Invoke-Command -Session $Session -ArgumentList $destination `
                    -ScriptBlock {
                        param($Path)
                        New-Item -Path $Path -ItemType Directory -Force |
                            Out-Null
                    }
                $sourceItem = Get-Item -LiteralPath $step.Source
                if ($sourceItem.PSIsContainer) {
                    Get-ChildItem -LiteralPath $step.Source -Force |
                        Copy-Item `
                            -Destination $destination `
                            -ToSession $Session `
                            -Recurse `
                            -Force
                } else {
                    Copy-Item `
                        -LiteralPath $step.Source `
                        -Destination $destination `
                        -ToSession $Session `
                        -Force
                }
            } else {
                $sourceItem = Get-Item -LiteralPath $step.Source
                if ($sourceItem.PSIsContainer) {
                    New-Item -Path $destination -ItemType Directory -Force |
                        Out-Null
                    $arguments = @(
                        $step.Source, $destination,
                        $(if ($step.Mirror) { '/MIR' } else { '/E' }),
                        '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:2', '/NP'
                    )
                    & robocopy.exe @arguments
                    if ($LASTEXITCODE -ge 8) {
                        throw (
                            "Robocopy failed for Forge step '$($step.Name)' " +
                            "with exit code $LASTEXITCODE."
                        )
                    }
                } else {
                    New-Item -Path (Split-Path $destination -Parent) `
                        -ItemType Directory -Force | Out-Null
                    Copy-Item -LiteralPath $step.Source `
                        -Destination $destination -Force
                }
            }
        } else {
            & ([scriptblock]::Create([string]$step.Script)) $context
        }
    }
}

function Invoke-ForgeWorkflow {
    <#
    .SYNOPSIS
    Executes durable Forge steps as a DTMS.Runway handler.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)]$Payload
    )

    $checkpointPath = Join-Path $OperationRoot `
        'Checkpoints\ForgeSteps.json'
    $steps = @($Payload.Steps)
    if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
        $checkpoint = ConvertTo-ForgeHashtable -InputObject (
            Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
        )
    } else {
        $checkpoint = [ordered]@{
            SchemaVersion = 1
            Steps = @($steps | ForEach-Object {
                [ordered]@{
                    Name = $_.Name
                    Status = 'Pending'
                    AttemptCount = 0
                    StartedUtc = $null
                    CompletedUtc = $null
                    Message = $null
                }
            })
        }
        Write-ForgeJson -Path $checkpointPath -Value $checkpoint
    }
    $ordered = @(Get-OrderedForgeStep -Step $steps)
    for ($index = 0; $index -lt $ordered.Count; $index++) {
        $step = $ordered[$index]
        $stepState = @($checkpoint.Steps | Where-Object {
            $_.Name -eq $step.Name
        })
        if ($stepState.Count -ne 1) {
            throw "Forge checkpoint for '$($step.Name)' is missing or duplicated."
        }
        $stepState = $stepState[0]
        if ($stepState.Status -eq 'Completed') {
            continue
        }
        $incomplete = @($step.DependsOn | Where-Object {
            $dependencyName = $_
            -not ($checkpoint.Steps | Where-Object {
                $_.Name -eq $dependencyName -and $_.Status -eq 'Completed'
            })
        })
        if ($incomplete.Count -gt 0) {
            throw (
                "Forge step '$($step.Name)' has incomplete dependencies: " +
                ($incomplete -join ', ')
            )
        }
        if ($stepState.Status -eq 'Running' -and
            -not $step.RetryInterrupted) {
            Set-DurableOperationPhase `
                -OperationRoot $OperationRoot `
                -Phase $step.Name `
                -Status NeedsReview `
                -Message 'The prior step execution may have been interrupted.' |
                Out-Null
            throw "Forge step '$($step.Name)' requires review."
        }
        $stepState.Status = 'Running'
        $stepState.AttemptCount = [int]$stepState.AttemptCount + 1
        $stepState.StartedUtc = [DateTime]::UtcNow.ToString('o')
        $stepState.CompletedUtc = $null
        $stepState.Message = $null
        Write-ForgeJson -Path $checkpointPath -Value $checkpoint
        $percent = [math]::Round(($index / $ordered.Count) * 100, 2)
        Set-DurableOperationPhase `
            -OperationRoot $OperationRoot `
            -Phase $step.Name `
            -Status Running `
            -Message $step.Description `
            -ProgressPercent $percent | Out-Null
        $context = [pscustomobject]@{
            Data = $Payload.Data
            StagingRoot = $Payload.StagingRoot
            OperationRoot = $OperationRoot
            StepName = $step.Name
            AttemptCount = $stepState.AttemptCount
            ComputerName = $env:COMPUTERNAME
        }
        try {
            $result = @(
                & ([scriptblock]::Create([string]$step.Script)) $context
            )
            $suspension = @($result | Where-Object {
                $_.PSObject.TypeNames -contains 'DTMS.Runway.Suspension'
            } | Select-Object -Last 1)
            if ($suspension.Count -gt 0) {
                $stepState.Status = [string]$suspension[0].Status
                $stepState.Message = [string]$suspension[0].Reason
                Write-ForgeJson -Path $checkpointPath -Value $checkpoint
                return $suspension[0]
            }
            $stepState.Status = 'Completed'
            $stepState.CompletedUtc = [DateTime]::UtcNow.ToString('o')
            Write-ForgeJson -Path $checkpointPath -Value $checkpoint
        } catch {
            $stepState.Message = $_.Exception.Message
            if ($step.RetryFailed) {
                $stepState.Status = 'Waiting'
                Write-ForgeJson -Path $checkpointPath -Value $checkpoint
                return Suspend-DurableOperation `
                    -OperationRoot $OperationRoot `
                    -Reason "Retrying Forge step '$($step.Name)': $($_.Exception.Message)" `
                    -ResumeAfterUtc ([DateTime]::UtcNow.AddMinutes(5))
            }
            $stepState.Status = 'NeedsReview'
            Write-ForgeJson -Path $checkpointPath -Value $checkpoint
            Set-DurableOperationPhase `
                -OperationRoot $OperationRoot `
                -Phase $step.Name `
                -Status NeedsReview `
                -Message $_.Exception.Message | Out-Null
            throw
        }
    }
}

function Start-ForgePlan {
    <#
    .SYNOPSIS
    Runs caller-context preparation and launches a Runway-backed Forge plan.
    .DESCRIPTION
    Direct mode uses local or WinRM target sessions. RemoteController delegates
    orchestration to a named OpenSSH controller profile. Tunnel establishes an
    SSH local forward to the target WinRM endpoint before staging the plan.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Plan,

        [Alias('Server')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [pscredential]$TargetCredential,

        [pscredential]$ExecutionCredential,

        [ValidateSet('Direct', 'RemoteController', 'Tunnel')]
        [string]$ControllerMode = 'Direct',

        [string]$ControllerProfile,

        [switch]$PreparationOnly
    )

    process {
        $validation = @(Test-ForgePlan -Plan $Plan)
        if ($validation.Count -gt 0) {
            throw "Invalid Forge plan:`n - $($validation -join "`n - ")"
        }
        if ($Plan.AccountType -eq 'User' -and -not $ExecutionCredential) {
            throw (
                "ExecutionCredential is required for '$($Plan.ExecutionAccount)'."
            )
        }
        if ($ControllerMode -ne 'Direct' -and
            [string]::IsNullOrWhiteSpace($ControllerProfile)) {
            throw "ControllerProfile is required for $ControllerMode mode."
        }
        if ($ControllerMode -eq 'RemoteController') {
            $controllerCommand = Get-Command New-DTMSControllerSession `
                -ErrorAction SilentlyContinue
            if (-not $controllerCommand) {
                throw 'Import DTMS.OpenSSH to use RemoteController mode.'
            }
            $controllerSession = New-DTMSControllerSession `
                -ProfileName $ControllerProfile
            try {
                return Invoke-Command `
                    -Session $controllerSession `
                    -ArgumentList $Plan, $ComputerName, $TargetCredential,
                        $ExecutionCredential, $PreparationOnly.IsPresent `
                    -ScriptBlock {
                        param(
                            $RemotePlan,
                            $Targets,
                            [pscredential]$RemoteTargetCredential,
                            [pscredential]$RemoteExecutionCredential,
                            $PrepareOnly
                        )
                        Import-Module DTMS.Utilities `
                            -ArgumentList 'Quiet' -Force -ErrorAction Stop
                        Start-ForgePlan `
                            -Plan $RemotePlan `
                            -ComputerName $Targets `
                            -TargetCredential $RemoteTargetCredential `
                            -ExecutionCredential $RemoteExecutionCredential `
                            -ControllerMode Direct `
                            -PreparationOnly:$PrepareOnly `
                            -Confirm:$false
                    }
            } finally {
                Remove-PSSession -Session $controllerSession
            }
        }
        foreach ($target in $ComputerName) {
            $activity = Start-DTMSActivity `
                -Name 'Forge workflow launch' `
                -Intent "Prepare and launch '$($Plan.Name)'" `
                -Target $target
            if (-not $PSCmdlet.ShouldProcess(
                $target,
                "prepare and launch Forge plan '$($Plan.Name)'"
            )) {
                Complete-DTMSActivity `
                    -Activity $activity `
                    -Status 'Forge plan was not started.'
                continue
            }
            $localTarget = $target -in @(
                '.', 'localhost', $env:COMPUTERNAME
            )
            $session = $null
            $tunnel = $null
            try {
                if ($ControllerMode -eq 'Tunnel') {
                    $tunnelCommand = Get-Command Start-DTMSWinRMTunnel `
                        -ErrorAction SilentlyContinue
                    if (-not $tunnelCommand) {
                        throw 'Import DTMS.OpenSSH to use Tunnel mode.'
                    }
                    $tunnel = Start-DTMSWinRMTunnel `
                        -ProfileName $ControllerProfile `
                        -TargetComputerName $target
                    $sessionParameters = @{
                        ComputerName = '127.0.0.1'
                        Port = $tunnel.LocalPort
                        Authentication = 'Negotiate'
                        ErrorAction = 'Stop'
                    }
                    if ($TargetCredential) {
                        $sessionParameters.Credential = $TargetCredential
                    }
                    $session = New-PSSession @sessionParameters
                } elseif (-not $localTarget) {
                    $sessionParameters = @{
                        ComputerName = $target
                        ErrorAction = 'Stop'
                    }
                    if ($TargetCredential) {
                        $sessionParameters.Credential = $TargetCredential
                    }
                    $session = New-PSSession @sessionParameters
                }
                $stagingId = '{0}-{1}' -f (
                    Get-Date -Format 'yyyyMMdd-HHmmss'
                ), [guid]::NewGuid().ToString('N')
                $targetStagingRoot = "C:\ProgramData\DTMS\Forge\Staging\$stagingId"
                if ($session) {
                    Invoke-Command -Session $session `
                        -ArgumentList $targetStagingRoot `
                        -ScriptBlock {
                            param($Path)
                            New-Item -Path $Path -ItemType Directory -Force |
                                Out-Null
                        }
                } else {
                    New-Item -Path $targetStagingRoot `
                        -ItemType Directory -Force | Out-Null
                }
                Invoke-ForgePreparation `
                    -Plan $Plan `
                    -TargetStagingRoot $targetStagingRoot `
                    -Session $session
                if ($PreparationOnly) {
                    [pscustomobject]@{
                        PSTypeName = 'DTMS.Forge.LaunchResult'
                        PlanName = $Plan.Name
                        ComputerName = $target
                        StagingRoot = $targetStagingRoot
                        Status = 'Prepared'
                    }
                    Complete-DTMSActivity `
                        -Activity $activity `
                        -Status 'Preparation completed.'
                    continue
                }
                $executionSteps = @($Plan.Steps |
                    Where-Object Stage -eq 'Execution')
                if ($executionSteps.Count -eq 0) {
                    throw 'The Forge plan has no durable execution steps.'
                }
                $payload = [ordered]@{
                    PlanName = $Plan.Name
                    Data = ConvertTo-ForgeHashtable -InputObject $Plan.Data
                    StagingRoot = $targetStagingRoot
                    Steps = @($executionSteps | ForEach-Object {
                        ConvertTo-ForgeHashtable -InputObject $_
                    })
                }
                $launchArguments = @(
                    $targetStagingRoot,
                    $payload,
                    $Plan.ExecutionAccount,
                    $Plan.PowerShellEngine,
                    [int]$Plan.ExecutionTimeLimitHours,
                    [int]$Plan.PollIntervalMinutes,
                    $Plan.TaskPath,
                    $ExecutionCredential
                )
                $launchScript = {
                    param(
                        $StagingRoot,
                        $Payload,
                        $ExecutionAccount,
                        $PowerShellEngine,
                        $ExecutionTimeLimitHours,
                        $PollIntervalMinutes,
                        $TaskPath,
                        [pscredential]$ExecutionCredential
                    )
                    $forgeManifest = Join-Path $StagingRoot `
                        'Modules\DTMS.Forge\DTMS.Forge.psd1'
                    $runwayManifest = Join-Path $StagingRoot `
                        'Modules\DTMS.Runway\DTMS.Runway.psd1'
                    Import-Module $runwayManifest `
                        -ArgumentList 'Quiet' -Force -ErrorAction Stop
                    Import-Module $forgeManifest -Force -ErrorAction Stop
                    $definition = New-DurableOperationDefinition `
                        -OperationType 'DTMS.Forge.Workflow' `
                        -HandlerModulePath $forgeManifest `
                        -HandlerCommand 'Invoke-ForgeWorkflow' `
                        -Payload $Payload `
                        -Metadata @{ PlanName = $Payload.PlanName }
                    Start-DurableOperation `
                        -Definition $definition `
                        -ExecutionAccount $ExecutionAccount `
                        -ExecutionCredential $ExecutionCredential `
                        -PowerShellEngine $PowerShellEngine `
                        -ExecutionTimeLimitHours $ExecutionTimeLimitHours `
                        -PollIntervalMinutes $PollIntervalMinutes `
                        -TaskPath $TaskPath `
                        -Confirm:$false
                }
                $moduleSources = @(
                    $script:ModuleRoot
                    (Split-Path (
                        Get-Module DTMS.Runway |
                            Select-Object -First 1 -ExpandProperty Path
                    ) -Parent)
                    (Split-Path (
                        Get-Module DTMS.Configuration |
                            Select-Object -First 1 -ExpandProperty Path
                    ) -Parent)
                )
                foreach ($moduleSource in $moduleSources) {
                    $moduleName = Split-Path $moduleSource -Leaf
                    $moduleDestination = Join-Path (
                        Join-Path $targetStagingRoot 'Modules'
                    ) $moduleName
                    if ($session) {
                        Invoke-Command -Session $session `
                            -ArgumentList $moduleDestination `
                            -ScriptBlock {
                                param($Path)
                                New-Item -Path $Path -ItemType Directory -Force |
                                    Out-Null
                            }
                        Get-ChildItem -LiteralPath $moduleSource -Force |
                            Copy-Item `
                                -Destination $moduleDestination `
                                -ToSession $session `
                                -Recurse `
                                -Force
                    } else {
                        New-Item -Path (Split-Path $moduleDestination -Parent) `
                            -ItemType Directory -Force | Out-Null
                        Copy-Item -LiteralPath $moduleSource `
                            -Destination $moduleDestination `
                            -Recurse -Force
                    }
                }
                $operation = if ($session) {
                    Invoke-Command -Session $session `
                        -ArgumentList $launchArguments `
                        -ScriptBlock $launchScript
                } else {
                    & $launchScript @launchArguments
                }
                Complete-DTMSActivity `
                    -Activity $activity `
                    -Status "Runway operation '$($operation.OperationId)' started."
                $operation
            } catch {
                Complete-DTMSActivity `
                    -Activity $activity `
                    -Status $_.Exception.Message `
                    -Failed
                throw
            } finally {
                if ($session) {
                    Remove-PSSession -Session $session
                }
                if ($tunnel -and $tunnel.ProcessId) {
                    Stop-Process -Id $tunnel.ProcessId -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-ForgeWorkflow'
    'New-ForgeCopyStep'
    'New-ForgePlan'
    'New-ForgeStep'
    'Start-ForgePlan'
    'Test-ForgePlan'
)
