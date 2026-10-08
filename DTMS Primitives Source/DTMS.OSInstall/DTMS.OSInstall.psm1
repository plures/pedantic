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

function New-WindowsServerInstallPlan {
    <#
    .SYNOPSIS
    Creates a declarative Windows Server Setup Forge plan.
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
        [string]$MediaSource,

        [Parameter(Mandatory, ParameterSetName = 'Existing')]
        [ValidateNotNullOrEmpty()]
        [string]$MediaPath,

        [ValidateSet('Scan', 'Upgrade', 'CleanInstall')]
        [string]$Operation = 'Scan',

        [Parameter(Mandatory)]
        [switch]$AcceptEula,

        [switch]$IgnoreDismissibleWarnings,

        [ValidateRange(1, 65535)]
        [int]$TargetImageIndex,

        [ValidatePattern('^\d+$')]
        [string]$TargetBuild,

        [string]$TargetEditionId,

        [ValidateSet('Server', 'Server Core')]
        [string]$TargetInstallationType,

        [ValidateSet(9)]
        [int]$TargetArchitecture = 9,

        [ValidatePattern('^\d+$')]
        [string]$ExpectedSourceBuild,

        [string]$PostSetupCommand,

        [string]$PostSetupArguments = '',

        [ValidateRange(1, 168)]
        [int]$PostSetupTimeoutHours = 2,

        [string]$ExecutionAccount,

        [ValidateSet('Auto', 'PowerShell7', 'WindowsPowerShell')]
        [string]$PowerShellEngine
    )

    $data = [ordered]@{
        AcceptEula = $AcceptEula.IsPresent
        Operation = $Operation
        MediaRelativePath = if ($PSCmdlet.ParameterSetName -eq 'Stage') {
            'Media'
        } else {
            $null
        }
        MediaPath = if ($PSCmdlet.ParameterSetName -eq 'Existing') {
            $MediaPath
        } else {
            $null
        }
        IgnoreDismissibleWarnings = $IgnoreDismissibleWarnings.IsPresent
        TargetImageIndex = $TargetImageIndex
        TargetBuild = $TargetBuild
        TargetEditionId = $TargetEditionId
        TargetInstallationType = $TargetInstallationType
        TargetArchitecture = $TargetArchitecture
        ExpectedSourceBuild = $ExpectedSourceBuild
        PostSetupCommand = $PostSetupCommand
        PostSetupArguments = $PostSetupArguments
        PostSetupTimeoutHours = $PostSetupTimeoutHours
    }
    $steps = [Collections.Generic.List[object]]::new()
    if ($PSCmdlet.ParameterSetName -eq 'Stage') {
        $steps.Add((New-ForgeCopyStep `
            -Name stage-media `
            -Source $MediaSource `
            -Destination Media `
            -Mirror))
    }
    $dependency = if ($PSCmdlet.ParameterSetName -eq 'Stage') {
        @('stage-media')
    } else {
        @()
    }
    $steps.Add((New-ForgeStep `
        -Name run-windows-setup `
        -DependsOn $dependency `
        -Description 'Validate media and run Windows Setup.' `
        -RetryInterrupted `
        -ScriptBlock {
            param($Context)
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'
            $mediaRoot = if ($Context.Data.MediaPath) {
                [string]$Context.Data.MediaPath
            } else {
                Join-Path $Context.StagingRoot `
                    ([string]$Context.Data.MediaRelativePath)
            }
            $setupExe = Join-Path $mediaRoot 'setup.exe'
            $installWim = Join-Path $mediaRoot 'sources\install.wim'
            foreach ($requiredFile in @($setupExe, $installWim)) {
                if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
                    throw "Windows installation media file is missing: $requiredFile"
                }
            }
            $markerPath = Join-Path $Context.OperationRoot `
                'Checkpoints\WindowsSetupStarted.json'
            if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
                return
            }
            $os = Get-CimInstance Win32_OperatingSystem
            $version = Get-ItemProperty `
                'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            if ($os.ProductType -ne 3) {
                throw 'The target is not a Windows Server system.'
            }
            if ($Context.Data.ExpectedSourceBuild -and
                $os.BuildNumber -ne [string]$Context.Data.ExpectedSourceBuild) {
                throw (
                    "Source build '$($os.BuildNumber)' does not match expected " +
                    "'$($Context.Data.ExpectedSourceBuild)'."
                )
            }
            if (Get-CimInstance Win32_Process -Filter (
                "Name = 'setup.exe' OR Name = 'setuphost.exe' OR " +
                "Name = 'setupprep.exe'"
            )) {
                throw 'Windows Setup is already running.'
            }
            $edition = if ($Context.Data.TargetEditionId) {
                [string]$Context.Data.TargetEditionId
            } else {
                [string]$version.EditionID
            }
            $installationType = if (
                $Context.Data.TargetInstallationType
            ) {
                [string]$Context.Data.TargetInstallationType
            } else {
                [string]$version.InstallationType
            }
            $images = @(Get-WindowsImage -ImagePath $installWim |
                ForEach-Object {
                    Get-WindowsImage `
                        -ImagePath $installWim `
                        -Index $_.ImageIndex
                })
            $matchingImages = if ([int]$Context.Data.TargetImageIndex -gt 0) {
                @($images | Where-Object {
                    $_.ImageIndex -eq [int]$Context.Data.TargetImageIndex
                })
            } else {
                @($images | Where-Object {
                    $_.EditionId -eq $edition -and
                    $_.InstallationType -eq $installationType -and
                    $_.Architecture -eq
                        [int]$Context.Data.TargetArchitecture -and
                    (-not $Context.Data.TargetBuild -or
                        ([version]$_.Version).Build -eq
                            [int]$Context.Data.TargetBuild)
                })
            }
            if ($matchingImages.Count -ne 1) {
                throw (
                    'Expected exactly one matching install.wim image; found ' +
                    "$($matchingImages.Count). Specify TargetImageIndex."
                )
            }
            $targetImage = $matchingImages[0]
            $target = [ordered]@{
                Build = [string]([version]$targetImage.Version).Build
                EditionId = [string]$targetImage.EditionId
                InstallationType = [string]$targetImage.InstallationType
                ImageIndex = [int]$targetImage.ImageIndex
                StartedUtc = [DateTime]::UtcNow.ToString('o')
                DeadlineUtc = [DateTime]::UtcNow.AddHours(
                    [int]$Context.Data.PostSetupTimeoutHours
                ).ToString('o')
            }
            $target | ConvertTo-Json |
                Set-Content -LiteralPath $markerPath -Encoding UTF8
            $postOobePath = $null
            if ($Context.Data.Operation -eq 'CleanInstall') {
                $postOobePath = Join-Path $Context.OperationRoot `
                    'Checkpoints\CleanInstallSetupComplete.cmd'
                $postScript = @'
$ErrorActionPreference = 'Stop'
$operationRoot = '__OPERATION_ROOT__'
$operationId = '__OPERATION_ID__'
$expectedBuild = '__BUILD__'
$expectedEdition = '__EDITION__'
$expectedType = '__TYPE__'
New-Item -Path $operationRoot -ItemType Directory -Force | Out-Null
foreach ($directory in @('Checkpoints', 'Logs', 'Outbox', 'Worker')) {
    New-Item -Path (Join-Path $operationRoot $directory) -ItemType Directory -Force | Out-Null
}
$os = Get-CimInstance Win32_OperatingSystem
$version = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$matches = $os.BuildNumber -eq $expectedBuild -and
    $version.EditionID -eq $expectedEdition -and
    $version.InstallationType -eq $expectedType
$now = [DateTime]::UtcNow.ToString('o')
$status = if ($matches) { 'Succeeded' } else { 'NeedsReview' }
$message = if ($matches) {
    'Clean installation completed and the installed Windows image was validated.'
} else {
    "Clean installation completed, but validation found build=$($os.BuildNumber), edition=$($version.EditionID), type=$($version.InstallationType)."
}
$state = [ordered]@{
    SchemaVersion = 1
    OperationId = $operationId
    OperationType = 'DTMS.Forge.Workflow'
    Status = $status
    CurrentPhase = 'PostOOBEValidation'
    ExecutionAccount = 'SYSTEM'
    AttemptCount = 1
    EventSequence = 0
    ProgressPercent = 100
    CreatedUtc = $now
    UpdatedUtc = $now
    StartedUtc = $now
    CompletedUtc = $now
    TaskName = $null
    TaskPath = $null
    ResumeAfterUtc = $null
    RebootRequestedUtc = $null
    RebootBootUtc = $null
    Message = $message
    PhaseHistory = @([ordered]@{
        Phase = 'PostOOBEValidation'
        EnteredUtc = $now
        Message = $message
    })
    Metadata = [ordered]@{ PlanName = 'WindowsServer-CleanInstall' }
}
$temporaryPath = Join-Path $operationRoot 'State.json.tmp'
$state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
Move-Item -LiteralPath $temporaryPath -Destination (Join-Path $operationRoot 'State.json') -Force
$state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $operationRoot 'Logs\PostOOBEValidation.json') -Encoding UTF8
'@
                $escape = {
                    param([string]$Value)
                    $Value.Replace("'", "''")
                }
                $postScript = $postScript.
                    Replace(
                        '__OPERATION_ROOT__',
                        (& $escape $Context.OperationRoot)
                    ).
                    Replace(
                        '__OPERATION_ID__',
                        (& $escape (
                            Split-Path $Context.OperationRoot -Leaf
                        ))
                    ).
                    Replace('__BUILD__', (& $escape $target.Build)).
                    Replace('__EDITION__', (& $escape $target.EditionId)).
                    Replace(
                        '__TYPE__',
                        (& $escape $target.InstallationType)
                    )
                $encodedPostScript = [Convert]::ToBase64String(
                    [Text.Encoding]::Unicode.GetBytes($postScript)
                )
                @(
                    '@echo off'
                    (
                        '"%SystemRoot%\System32\WindowsPowerShell\v1.0\' +
                        'powershell.exe" -NoProfile -NonInteractive ' +
                        "-ExecutionPolicy Bypass -EncodedCommand $encodedPostScript"
                    )
                    'exit /b %errorlevel%'
                ) -join "`r`n" |
                    Set-Content -LiteralPath $postOobePath -Encoding ASCII
            }
            $autoMode = if ($Context.Data.Operation -eq 'CleanInstall') {
                'clean'
            } else {
                'upgrade'
            }
            $logRoot = Join-Path $Context.OperationRoot 'Logs\WindowsSetup'
            New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
            $arguments = @(
                "/auto $autoMode"
                '/quiet'
                '/eula accept'
                '/dynamicupdate disable'
                '/telemetry disable'
                "/imageindex $($target.ImageIndex)"
                ('/copylogs "{0}"' -f $logRoot)
            )
            if ($Context.Data.Operation -eq 'Scan') {
                $arguments += '/compat scanonly'
            }
            if ($postOobePath) {
                $arguments += ('/postoobe "{0}"' -f $postOobePath)
            }
            if ($Context.Data.IgnoreDismissibleWarnings) {
                $arguments += '/compat ignorewarning'
            }
            $process = Start-Process `
                -FilePath $setupExe `
                -ArgumentList ($arguments -join ' ') `
                -WorkingDirectory $mediaRoot `
                -Wait `
                -PassThru
            $exitCode = [int]$process.ExitCode
            $hexCode = '0x{0:X8}' -f [BitConverter]::ToUInt32(
                [BitConverter]::GetBytes($exitCode),
                0
            )
            if ($Context.Data.Operation -eq 'Scan' -and
                $hexCode -eq '0xC1900210') {
                $exitCode = 0
            }
            if ($exitCode -ne 0) {
                throw "Windows Setup returned $exitCode ($hexCode)."
            }
        }))
    $steps.Add((New-ForgeStep `
        -Name validate-installed-os `
        -DependsOn run-windows-setup `
        -Description 'Validate Windows Setup completion and optional post-setup work.' `
        -RetryInterrupted `
        -ScriptBlock {
            param($Context)
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'
            if ($Context.Data.Operation -eq 'Scan') {
                return
            }
            $target = Get-Content -LiteralPath (
                Join-Path $Context.OperationRoot `
                    'Checkpoints\WindowsSetupStarted.json'
            ) -Raw | ConvertFrom-Json
            $setup = Get-ItemProperty 'HKLM:\SYSTEM\Setup'
            $imageState = (
                Get-ItemProperty `
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'
            ).ImageState
            $setupProcesses = @(Get-CimInstance Win32_Process -Filter (
                "Name = 'setup.exe' OR Name = 'setuphost.exe' OR " +
                "Name = 'setupprep.exe'"
            ))
            $complete = $setup.SystemSetupInProgress -eq 0 -and
                $setup.OOBEInProgress -eq 0 -and
                $imageState -eq 'IMAGE_STATE_COMPLETE' -and
                $setupProcesses.Count -eq 0
            if (-not $complete) {
                return Suspend-DurableOperation `
                    -OperationRoot $Context.OperationRoot `
                    -Reason 'Waiting for Windows Setup and OOBE to complete.' `
                    -ResumeAfterUtc ([DateTime]::UtcNow.AddMinutes(5))
            }
            $os = Get-CimInstance Win32_OperatingSystem
            $version = Get-ItemProperty `
                'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            if ($os.BuildNumber -ne [string]$target.Build -or
                $version.EditionID -ne [string]$target.EditionId -or
                $version.InstallationType -ne
                    [string]$target.InstallationType) {
                if ([DateTime]::UtcNow -lt [datetime]$target.DeadlineUtc) {
                    return Suspend-DurableOperation `
                        -OperationRoot $Context.OperationRoot `
                        -Reason 'Waiting for the target Windows image.' `
                        -ResumeAfterUtc ([DateTime]::UtcNow.AddMinutes(5))
                }
                throw 'Installed Windows image does not match the selected target.'
            }
            if ($Context.Data.PostSetupCommand) {
                $process = Start-Process `
                    -FilePath $Context.Data.PostSetupCommand `
                    -ArgumentList $Context.Data.PostSetupArguments `
                    -Wait `
                    -PassThru
                if ($process.ExitCode -ne 0) {
                    throw (
                        "Post-setup command returned $($process.ExitCode)."
                    )
                }
            }
        }))
    $parameters = @{
        Name = "WindowsServer-$Operation"
        Step = $steps.ToArray()
        Data = $data
        ExecutionTimeLimitHours = 48
        PollIntervalMinutes = 5
    }
    if ($ExecutionAccount) {
        $parameters.ExecutionAccount = $ExecutionAccount
    }
    if ($PowerShellEngine) {
        $parameters.PowerShellEngine = $PowerShellEngine
    }
    New-ForgePlan @parameters
}

function Start-WindowsServerInstall {
    <#
    .SYNOPSIS
    Creates and starts a Windows Server Setup workflow.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Stage',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Stage')]
        [string]$MediaSource,

        [Parameter(Mandatory, ParameterSetName = 'Existing')]
        [string]$MediaPath,

        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [ValidateSet('Scan', 'Upgrade', 'CleanInstall')]
        [string]$Operation = 'Scan',

        [Parameter(Mandatory)]
        [switch]$AcceptEula,

        [string]$CleanInstallConfirmation,

        [switch]$IgnoreDismissibleWarnings,

        [int]$TargetImageIndex,

        [string]$TargetBuild,

        [string]$TargetEditionId,

        [ValidateSet('Server', 'Server Core')]
        [string]$TargetInstallationType,

        [string]$ExpectedSourceBuild,

        [string]$PostSetupCommand,

        [string]$PostSetupArguments = '',

        [string]$ExecutionAccount,

        [pscredential]$ExecutionCredential,

        [pscredential]$TargetCredential,

        [ValidateSet('Direct', 'RemoteController', 'Tunnel')]
        [string]$ControllerMode = 'Direct',

        [string]$ControllerProfile
    )

    if ($Operation -eq 'CleanInstall') {
        if ($ComputerName.Count -ne 1 -or
            $CleanInstallConfirmation -cne $ComputerName[0]) {
            throw (
                'CleanInstall requires exactly one target and ' +
                'CleanInstallConfirmation equal to its ComputerName.'
            )
        }
    }
    $planParameters = @{
        Operation = $Operation
        AcceptEula = $AcceptEula
        IgnoreDismissibleWarnings = $IgnoreDismissibleWarnings
        PostSetupArguments = $PostSetupArguments
    }
    foreach ($optionalParameter in @{
        TargetBuild = $TargetBuild
        TargetEditionId = $TargetEditionId
        TargetInstallationType = $TargetInstallationType
        ExpectedSourceBuild = $ExpectedSourceBuild
        PostSetupCommand = $PostSetupCommand
    }.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace(
            [string]$optionalParameter.Value
        )) {
            $planParameters[$optionalParameter.Key] =
                $optionalParameter.Value
        }
    }
    if ($TargetImageIndex -gt 0) {
        $planParameters.TargetImageIndex = $TargetImageIndex
    }
    if ($PSCmdlet.ParameterSetName -eq 'Stage') {
        $planParameters.MediaSource = $MediaSource
    } else {
        $planParameters.MediaPath = $MediaPath
    }
    if ($ExecutionAccount) {
        $planParameters.ExecutionAccount = $ExecutionAccount
    }
    $plan = New-WindowsServerInstallPlan @planParameters
    if (-not $PSCmdlet.ShouldProcess(
        ($ComputerName -join ', '),
        "start Windows Server $Operation workflow"
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

function Get-WindowsServerInstall {
    <#
    .SYNOPSIS
    Gets Windows Server Setup operations from Runway state.
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
        $_.Metadata.PlanName -like 'WindowsServer-*'
    }
}

Export-ModuleMember -Function @(
    'Get-WindowsServerInstall'
    'New-WindowsServerInstallPlan'
    'Start-WindowsServerInstall'
)
