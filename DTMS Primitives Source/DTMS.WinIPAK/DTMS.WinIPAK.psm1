# PowerShell 7 is the primary runtime. The requirement below is the minimum
# compatibility floor for direct module imports under Windows PowerShell.
#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($dependency in @('DTMS.Forge', 'DTMS.Runway')) {
    if (-not (Get-Module $dependency)) {
        $manifest = Join-Path $PSScriptRoot `
            "..\$dependency\$dependency.psd1"
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            throw "Required module '$dependency' was not found."
        }
        $argumentList = if ($dependency -eq 'DTMS.Runway') {
            @('Quiet')
        } else {
            @()
        }
        Import-Module $manifest -ArgumentList $argumentList `
            -Force -ErrorAction Stop
    }
}

function New-WinIPAKPlan {
    <#
    .SYNOPSIS
    Creates a reboot-safe WinIPAK Forge plan.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates an in-memory declarative plan without changing system state.'
    )]
    [CmdletBinding(DefaultParameterSetName = 'Stage')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Stage')]
        [ValidateNotNullOrEmpty()]
        [string]$WinIPAKSource,

        [Parameter(Mandatory, ParameterSetName = 'Existing')]
        [ValidateNotNullOrEmpty()]
        [string]$WinIPAKPath,

        [Parameter(ParameterSetName = 'Stage')]
        [string]$WinIPAKRelativePath = 'winipak.exe',

        [string]$WinIPAKArguments =
            '/VALIDATEPATCH /REBOOT:false /FORCEREBOOT:false',

        [ValidatePattern('^\d+$')]
        [string]$RequiredOsBuild,

        [ValidatePattern('^\d+$')]
        [string]$MinimumOsBuild,

        [string]$RequiredEditionId,

        [ValidateSet('Server', 'Server Core')]
        [string]$RequiredInstallationType,

        [string[]]$RequiredPath = @(),

        [scriptblock]$RequirementScript,

        [switch]$SkipSetupCompleteRequirement,

        [int[]]$AcceptedExitCode = @(0),

        [ValidateRange(1, 100)]
        [int]$MaxRuns = 5,

        [ValidateRange(0, 3600)]
        [int]$RebootDelaySeconds = 60,

        [ValidateRange(1, 1440)]
        [int]$PollIntervalMinutes = 5,

        [string]$ExecutionAccount,

        [ValidateSet('Auto', 'PowerShell7', 'WindowsPowerShell')]
        [string]$PowerShellEngine
    )

    if ($RequiredOsBuild -and $MinimumOsBuild) {
        throw 'RequiredOsBuild and MinimumOsBuild are mutually exclusive.'
    }
    if ($AcceptedExitCode.Count -eq 0) {
        throw 'At least one accepted exit code is required.'
    }
    $data = [ordered]@{
        WinIPAKPath = if ($PSCmdlet.ParameterSetName -eq 'Existing') {
            $WinIPAKPath
        } else {
            $null
        }
        WinIPAKRelativePath = if (
            $PSCmdlet.ParameterSetName -eq 'Stage'
        ) {
            Join-Path 'Payload' $WinIPAKRelativePath
        } else {
            $null
        }
        WinIPAKArguments = $WinIPAKArguments
        RequiredOsBuild = $RequiredOsBuild
        MinimumOsBuild = $MinimumOsBuild
        RequiredEditionId = $RequiredEditionId
        RequiredInstallationType = $RequiredInstallationType
        RequiredPath = @($RequiredPath)
        RequirementScript = if ($RequirementScript) {
            $RequirementScript.ToString()
        } else {
            $null
        }
        SkipSetupCompleteRequirement =
            $SkipSetupCompleteRequirement.IsPresent
        AcceptedExitCode = @($AcceptedExitCode)
        MaxRuns = $MaxRuns
        RebootDelaySeconds = $RebootDelaySeconds
        PollIntervalMinutes = $PollIntervalMinutes
    }
    $steps = [Collections.Generic.List[object]]::new()
    if ($PSCmdlet.ParameterSetName -eq 'Stage') {
        $steps.Add((New-ForgeCopyStep `
            -Name stage-winipak `
            -Source $WinIPAKSource `
            -Destination Payload `
            -Mirror))
    }
    $dependency = if ($PSCmdlet.ParameterSetName -eq 'Stage') {
        @('stage-winipak')
    } else {
        @()
    }
    $steps.Add((New-ForgeStep `
        -Name run-winipak-cycle `
        -DependsOn $dependency `
        -Description 'Run WinIPAK and continue safely across required reboots.' `
        -RetryInterrupted `
        -ScriptBlock {
            param($Context)
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            function Save-WinIPAKState {
                param($State, [string]$Path)
                $State.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
                $temporaryPath = "$Path.tmp"
                $State | ConvertTo-Json -Depth 20 |
                    Set-Content -LiteralPath $temporaryPath -Encoding UTF8
                Move-Item -LiteralPath $temporaryPath `
                    -Destination $Path -Force
            }

            function Get-WinIPAKPendingReboot {
                $reasons = [Collections.Generic.List[string]]::new()
                if (Test-Path (
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\' +
                    'Component Based Servicing\RebootPending'
                )) {
                    $reasons.Add('ComponentBasedServicing')
                }
                if (Test-Path (
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\' +
                    'WindowsUpdate\Auto Update\RebootRequired'
                )) {
                    $reasons.Add('WindowsUpdate')
                }
                $sessionManager = Get-ItemProperty `
                    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                    -ErrorAction SilentlyContinue
                if ($sessionManager -and
                    $sessionManager.PendingFileRenameOperations) {
                    $reasons.Add('PendingFileRenameOperations')
                }
                $updateState = Get-ItemProperty `
                    'HKLM:\SOFTWARE\Microsoft\Updates' `
                    -Name UpdateExeVolatile `
                    -ErrorAction SilentlyContinue
                if ($updateState -and
                    [int]$updateState.UpdateExeVolatile -ne 0) {
                    $reasons.Add('UpdateExeVolatile')
                }
                try {
                    $client = Get-CimInstance `
                        -Namespace 'root\ccm\ClientSDK' `
                        -ClassName CCM_ClientUtilities `
                        -ErrorAction Stop
                    $sccm = Invoke-CimMethod `
                        -InputObject $client `
                        -MethodName DetermineIfRebootPending `
                        -ErrorAction Stop
                    if ($sccm.RebootPending -or
                        $sccm.IsHardRebootPending) {
                        $reasons.Add('ConfigurationManager')
                    }
                } catch [Microsoft.Management.Infrastructure.CimException] {
                    Write-Verbose (
                        'Configuration Manager reboot state is unavailable: ' +
                        $_.Exception.Message
                    )
                }
                [pscustomobject]@{
                    IsPending = $reasons.Count -gt 0
                    Reasons = $reasons.ToArray()
                }
            }

            $statePath = Join-Path $Context.OperationRoot `
                'Checkpoints\WinIPAK.json'
            if (Test-Path -LiteralPath $statePath -PathType Leaf) {
                $state = Get-Content -LiteralPath $statePath -Raw |
                    ConvertFrom-Json
            } else {
                $state = [pscustomobject][ordered]@{
                    Status = 'WaitingForRequirements'
                    RunCount = 0
                    LastRunBootUtc = $null
                    LastExitCode = $null
                    LastPendingRebootReasons = @()
                    UpdatedUtc = [DateTime]::UtcNow.ToString('o')
                    History = @()
                }
                Save-WinIPAKState -State $state -Path $statePath
            }
            if ($state.Status -eq 'Running') {
                $state.Status = 'NeedsReview'
                Save-WinIPAKState -State $state -Path $statePath
                throw (
                    'The prior WinIPAK process may have been interrupted; ' +
                    'manual review is required.'
                )
            }
            $os = Get-CimInstance Win32_OperatingSystem
            $version = Get-ItemProperty `
                'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $currentBootUtc = $os.LastBootUpTime.ToUniversalTime().ToString('o')
            if ($state.Status -eq 'AwaitingReboot' -and
                $state.LastRunBootUtc -eq $currentBootUtc) {
                return Request-DurableOperationReboot `
                    -OperationRoot $Context.OperationRoot `
                    -Reason 'WinIPAK requires a later boot session.' `
                    -DelaySeconds ([int]$Context.Data.RebootDelaySeconds) `
                    -Restart
            }
            if ([int]$state.RunCount -eq 0) {
                $unmet = [Collections.Generic.List[string]]::new()
                if ($Context.Data.RequiredOsBuild -and
                    $os.BuildNumber -ne
                        [string]$Context.Data.RequiredOsBuild) {
                    $unmet.Add('Required OS build is not installed.')
                }
                if ($Context.Data.MinimumOsBuild -and
                    [int]$os.BuildNumber -lt
                        [int]$Context.Data.MinimumOsBuild) {
                    $unmet.Add('Minimum OS build is not installed.')
                }
                if ($Context.Data.RequiredEditionId -and
                    $version.EditionID -ne
                        [string]$Context.Data.RequiredEditionId) {
                    $unmet.Add('Required edition is not installed.')
                }
                if ($Context.Data.RequiredInstallationType -and
                    $version.InstallationType -ne
                        [string]$Context.Data.RequiredInstallationType) {
                    $unmet.Add('Required installation type is not installed.')
                }
                foreach ($requiredPath in @($Context.Data.RequiredPath)) {
                    if ($requiredPath -and
                        -not (Test-Path -LiteralPath $requiredPath)) {
                        $unmet.Add(
                            "Required path is unavailable: $requiredPath"
                        )
                    }
                }
                if (-not $Context.Data.SkipSetupCompleteRequirement) {
                    $setup = Get-ItemProperty 'HKLM:\SYSTEM\Setup'
                    $imageState = (
                        Get-ItemProperty (
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\' +
                            'Setup\State'
                        )
                    ).ImageState
                    if ($setup.SystemSetupInProgress -ne 0 -or
                        $setup.OOBEInProgress -ne 0 -or
                        $imageState -ne 'IMAGE_STATE_COMPLETE') {
                        $unmet.Add('Windows Setup is not complete.')
                    }
                }
                if ($Context.Data.RequirementScript) {
                    $requirementContext = [pscustomobject]@{
                        Data = $Context.Data
                        State = $state
                        OperatingSystem = $os
                        CurrentVersion = $version
                        ComputerName = $env:COMPUTERNAME
                        OperationRoot = $Context.OperationRoot
                    }
                    $custom = @(
                        & ([scriptblock]::Create(
                            [string]$Context.Data.RequirementScript
                        )) $requirementContext
                    )
                    if ($custom.Count -ne 1 -or
                        $custom[0] -isnot [bool]) {
                        throw (
                            'RequirementScript must return exactly one Boolean.'
                        )
                    }
                    if (-not $custom[0]) {
                        $unmet.Add('RequirementScript returned false.')
                    }
                }
                if ($unmet.Count -gt 0) {
                    $state.Status = 'WaitingForRequirements'
                    Save-WinIPAKState -State $state -Path $statePath
                    return Suspend-DurableOperation `
                        -OperationRoot $Context.OperationRoot `
                        -Reason ($unmet -join ' ') `
                        -ResumeAfterUtc (
                            [DateTime]::UtcNow.AddMinutes(
                                [int]$Context.Data.PollIntervalMinutes
                            )
                        )
                }
            }
            if ([int]$state.RunCount -ge [int]$Context.Data.MaxRuns) {
                $state.Status = 'NeedsReview'
                Save-WinIPAKState -State $state -Path $statePath
                throw 'Maximum WinIPAK run count was reached.'
            }
            $executable = if ($Context.Data.WinIPAKPath) {
                [string]$Context.Data.WinIPAKPath
            } else {
                Join-Path $Context.StagingRoot `
                    ([string]$Context.Data.WinIPAKRelativePath)
            }
            if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
                return Suspend-DurableOperation `
                    -OperationRoot $Context.OperationRoot `
                    -Reason "WinIPAK is unavailable: $executable" `
                    -ResumeAfterUtc (
                        [DateTime]::UtcNow.AddMinutes(
                            [int]$Context.Data.PollIntervalMinutes
                        )
                    )
            }
            $state.RunCount = [int]$state.RunCount + 1
            $state.Status = 'Running'
            $state.LastRunBootUtc = $currentBootUtc
            Save-WinIPAKState -State $state -Path $statePath
            $logRoot = Join-Path $Context.OperationRoot (
                'Logs\WinIPAK-{0:D2}-{1}' -f
                    [int]$state.RunCount,
                    (Get-Date -Format 'yyyyMMdd-HHmmss')
            )
            New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
            $process = Start-Process `
                -FilePath $executable `
                -ArgumentList $Context.Data.WinIPAKArguments `
                -WorkingDirectory (Split-Path $executable -Parent) `
                -Wait `
                -PassThru `
                -RedirectStandardOutput (
                    Join-Path $logRoot 'WinIPAK.stdout.log'
                ) `
                -RedirectStandardError (
                    Join-Path $logRoot 'WinIPAK.stderr.log'
                )
            $exitCode = [int]$process.ExitCode
            $pending = Get-WinIPAKPendingReboot
            $state.LastExitCode = $exitCode
            $state.LastPendingRebootReasons = @($pending.Reasons)
            $state.History = @($state.History) + @([pscustomobject]@{
                RunNumber = [int]$state.RunCount
                BootUtc = $currentBootUtc
                CompletedUtc = [DateTime]::UtcNow.ToString('o')
                ExitCode = $exitCode
                PendingRebootReasons = @($pending.Reasons)
                LogRoot = $logRoot
            })
            if ($pending.IsPending) {
                if ([int]$state.RunCount -ge
                    [int]$Context.Data.MaxRuns) {
                    $state.Status = 'NeedsReview'
                    Save-WinIPAKState -State $state -Path $statePath
                    throw (
                        'A reboot remains pending after the maximum ' +
                        'WinIPAK run count.'
                    )
                }
                $state.Status = 'AwaitingReboot'
                Save-WinIPAKState -State $state -Path $statePath
                return Request-DurableOperationReboot `
                    -OperationRoot $Context.OperationRoot `
                    -Reason (
                        'WinIPAK pending reboot: ' +
                        ($pending.Reasons -join ', ')
                    ) `
                    -DelaySeconds ([int]$Context.Data.RebootDelaySeconds) `
                    -Restart
            }
            if ($exitCode -notin @(
                $Context.Data.AcceptedExitCode |
                    ForEach-Object { [int]$_ }
            )) {
                $state.Status = 'NeedsReview'
                Save-WinIPAKState -State $state -Path $statePath
                throw "WinIPAK returned unaccepted exit code $exitCode."
            }
            $state.Status = 'Completed'
            Save-WinIPAKState -State $state -Path $statePath
        }))
    $parameters = @{
        Name = 'WinIPAK-Cycle'
        Step = $steps.ToArray()
        Data = $data
        ExecutionTimeLimitHours = 12
        PollIntervalMinutes = $PollIntervalMinutes
    }
    if ($ExecutionAccount) {
        $parameters.ExecutionAccount = $ExecutionAccount
    }
    if ($PowerShellEngine) {
        $parameters.PowerShellEngine = $PowerShellEngine
    }
    New-ForgePlan @parameters
}

function Start-WinIPAKOperation {
    <#
    .SYNOPSIS
    Creates and starts a reboot-safe WinIPAK workflow.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Stage',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Stage')]
        [string]$WinIPAKSource,

        [Parameter(Mandatory, ParameterSetName = 'Existing')]
        [string]$WinIPAKPath,

        [Parameter(ParameterSetName = 'Stage')]
        [string]$WinIPAKRelativePath = 'winipak.exe',

        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [string]$RequiredOsBuild,

        [string]$MinimumOsBuild,

        [string]$RequiredEditionId,

        [ValidateSet('Server', 'Server Core')]
        [string]$RequiredInstallationType,

        [string[]]$RequiredPath = @(),

        [scriptblock]$RequirementScript,

        [switch]$SkipSetupCompleteRequirement,

        [int[]]$AcceptedExitCode = @(0),

        [ValidateRange(1, 100)]
        [int]$MaxRuns = 5,

        [ValidateRange(0, 3600)]
        [int]$RebootDelaySeconds = 60,

        [ValidateRange(1, 1440)]
        [int]$PollIntervalMinutes = 5,

        [string]$ExecutionAccount,

        [pscredential]$ExecutionCredential,

        [pscredential]$TargetCredential,

        [ValidateSet('Direct', 'RemoteController', 'Tunnel')]
        [string]$ControllerMode = 'Direct',

        [string]$ControllerProfile
    )

    $planParameters = @{
        RequiredPath = $RequiredPath
        SkipSetupCompleteRequirement = $SkipSetupCompleteRequirement
        AcceptedExitCode = $AcceptedExitCode
        MaxRuns = $MaxRuns
        RebootDelaySeconds = $RebootDelaySeconds
        PollIntervalMinutes = $PollIntervalMinutes
    }
    foreach ($optionalParameter in @{
        RequiredOsBuild = $RequiredOsBuild
        MinimumOsBuild = $MinimumOsBuild
        RequiredEditionId = $RequiredEditionId
        RequiredInstallationType = $RequiredInstallationType
    }.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace(
            [string]$optionalParameter.Value
        )) {
            $planParameters[$optionalParameter.Key] =
                $optionalParameter.Value
        }
    }
    if ($RequirementScript) {
        $planParameters.RequirementScript = $RequirementScript
    }
    if ($PSCmdlet.ParameterSetName -eq 'Stage') {
        $planParameters.WinIPAKSource = $WinIPAKSource
        $planParameters.WinIPAKRelativePath = $WinIPAKRelativePath
    } else {
        $planParameters.WinIPAKPath = $WinIPAKPath
    }
    if ($ExecutionAccount) {
        $planParameters.ExecutionAccount = $ExecutionAccount
    }
    $plan = New-WinIPAKPlan @planParameters
    if (-not $PSCmdlet.ShouldProcess(
        ($ComputerName -join ', '),
        'start WinIPAK operation'
    )) {
        return
    }
    Start-ForgePlan `
        -Plan $plan `
        -ComputerName $ComputerName `
        -TargetCredential $TargetCredential `
        -ExecutionCredential $ExecutionCredential `
        -ControllerMode $ControllerMode `
        -ControllerProfile $ControllerProfile `
        -Confirm:$false
}

function Get-WinIPAKOperation {
    <#
    .SYNOPSIS
    Gets WinIPAK workflows from Runway state.
    #>
    [CmdletBinding()]
    param(
        [string]$OperationId,
        [string]$OperationRoot,
        [switch]$Active,
        [switch]$Latest
    )

    $parameters = @{
        OperationId = $OperationId
        Active = $Active
        Latest = $Latest
    }
    if ($OperationRoot) {
        $parameters.OperationRoot = $OperationRoot
    }
    Get-DurableOperation @parameters | Where-Object {
        $_.Metadata.PlanName -eq 'WinIPAK-Cycle'
    }
}

Export-ModuleMember -Function @(
    'Get-WinIPAKOperation'
    'New-WinIPAKPlan'
    'Start-WinIPAKOperation'
)
