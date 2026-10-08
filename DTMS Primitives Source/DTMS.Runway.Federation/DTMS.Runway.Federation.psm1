# PowerShell 7 is the primary runtime. The requirement below is the minimum
# compatibility floor for direct module imports under Windows PowerShell.
#requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Remoting script blocks declare parameters populated through ArgumentList.'
)]
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($dependency in @('DTMS.Configuration', 'DTMS.Runway')) {
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

function Initialize-DurableOperationFederation {
    <#
    .SYNOPSIS
    Installs independent Runway collectors on utility servers.
    .DESCRIPTION
    Every utility server pulls every registered target. Target-local Runway
    state remains authoritative; no DFS namespace or replication rights are
    required.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string[]]$UtilityServer,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TargetComputerName,

        [string]$CollectorAccount,

        [string]$LocalPath,

        [ValidateRange(1, 10000)]
        [int]$RetentionCount,

        [ValidateRange(1, 1440)]
        [int]$IntervalMinutes = 5,

        [pscredential]$Credential
    )

    $configuration = Get-DTMSConfiguration
    if (@($UtilityServer).Count -eq 0) {
        $UtilityServer = @($configuration.Federation.UtilityServers)
    }
    if (@($UtilityServer).Count -eq 0) {
        throw 'Specify UtilityServer or configure Federation.UtilityServers.'
    }
    if ([string]::IsNullOrWhiteSpace($CollectorAccount)) {
        $CollectorAccount = [string](
            $configuration.Federation.CollectorAccount
        )
    }
    if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        $LocalPath = [string]$configuration.Federation.LocalPath
    }
    if ($RetentionCount -eq 0) {
        $RetentionCount = [int]$configuration.Federation.RetentionCount
    }
    if (-not $CollectorAccount.EndsWith('$')) {
        throw 'CollectorAccount must be a gMSA ending in a dollar sign.'
    }
    $UtilityServer = @($UtilityServer | Sort-Object -Unique)
    $TargetComputerName = @($TargetComputerName | Sort-Object -Unique)
    $activity = Start-DTMSActivity `
        -Name 'Runway federation setup' `
        -Intent 'Install independent pull collectors and register targets' `
        -Target ($UtilityServer -join ', ')
    if (-not $PSCmdlet.ShouldProcess(
        ($UtilityServer -join ', '),
        "configure Runway federation for $($TargetComputerName.Count) target(s)"
    )) {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status 'Federation setup was not started.'
        return
    }
    $collectorSource = Join-Path $PSScriptRoot `
        'Invoke-DurableOperationFederatedCollector.ps1'
    foreach ($server in $UtilityServer) {
        Update-DTMSActivity `
            -Activity $activity `
            -Status "Configuring collector on $server." `
            -ForceHeartbeat
        $sessionParameters = @{
            ComputerName = $server
            ErrorAction = 'Stop'
        }
        if ($Credential) {
            $sessionParameters.Credential = $Credential
        }
        $session = New-PSSession @sessionParameters
        try {
            $remote = Invoke-Command `
                -Session $session `
                -ArgumentList $LocalPath `
                -ScriptBlock {
                    param($Root)
                    $principal = [Security.Principal.WindowsPrincipal]::new(
                        [Security.Principal.WindowsIdentity]::GetCurrent()
                    )
                    if (-not $principal.IsInRole(
                        [Security.Principal.WindowsBuiltInRole]::Administrator
                    )) {
                        throw 'Elevated local administrator rights are required.'
                    }
                    New-Item -Path $Root -ItemType Directory -Force |
                        Out-Null
                    [pscustomobject]@{
                        CollectorPath = Join-Path $Root `
                            'Invoke-DurableOperationFederatedCollector.ps1'
                        ConfigurationPath = Join-Path $Root `
                            'CollectorConfiguration.json'
                    }
                }
            Copy-Item `
                -LiteralPath $collectorSource `
                -Destination $remote.CollectorPath `
                -ToSession $session `
                -Force
            $collectorConfiguration = [ordered]@{
                SchemaVersion = 1
                TargetComputerName = $TargetComputerName
                OperationRoot = [string]$configuration.Runway.OperationRoot
                LocalPath = $LocalPath
                RetentionCount = $RetentionCount
            }
            $configurationJson = $collectorConfiguration |
                ConvertTo-Json -Depth 10
            Invoke-Command `
                -Session $session `
                -ArgumentList $remote.ConfigurationPath,
                    $configurationJson,
                    $remote.CollectorPath,
                    $CollectorAccount,
                    $IntervalMinutes `
                -ScriptBlock {
                    param(
                        $ConfigurationPath,
                        $ConfigurationJson,
                        $CollectorPath,
                        $Account,
                        $Minutes
                    )
                    $ConfigurationJson |
                        Set-Content -LiteralPath $ConfigurationPath `
                            -Encoding UTF8
                    $engine = Join-Path $env:ProgramFiles `
                        'PowerShell\7\pwsh.exe'
                    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
                        $engine = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                    }
                    $arguments = (
                        '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
                        '-File "{0}" -ConfigurationPath "{1}"'
                    ) -f $CollectorPath, $ConfigurationPath
                    $action = New-ScheduledTaskAction `
                        -Execute $engine `
                        -Argument $arguments `
                        -WorkingDirectory (Split-Path $CollectorPath -Parent)
                    $triggers = @(
                        New-ScheduledTaskTrigger -AtStartup
                        New-ScheduledTaskTrigger `
                            -Once `
                            -At (Get-Date).AddMinutes(1) `
                            -RepetitionInterval (
                                New-TimeSpan -Minutes $Minutes
                            ) `
                            -RepetitionDuration (New-TimeSpan -Days 3650)
                    )
                    $service = New-Object -ComObject 'Schedule.Service'
                    $service.Connect()
                    $rootFolder = $service.GetFolder('\')
                    try {
                        $null = $rootFolder.GetFolder('DTMS')
                    } catch {
                        $null = $rootFolder.CreateFolder('DTMS')
                    }
                    $principal = New-ScheduledTaskPrincipal `
                        -UserId $Account `
                        -LogonType Password `
                        -RunLevel Highest
                    $settings = New-ScheduledTaskSettingsSet `
                        -StartWhenAvailable `
                        -MultipleInstances IgnoreNew `
                        -ExecutionTimeLimit (New-TimeSpan -Hours 1)
                    Register-ScheduledTask `
                        -TaskName 'Runway-FederatedCollector' `
                        -TaskPath '\DTMS\' `
                        -Action $action `
                        -Trigger $triggers `
                        -Principal $principal `
                        -Settings $settings `
                        -Force | Out-Null
                    Start-ScheduledTask `
                        -TaskName 'Runway-FederatedCollector' `
                        -TaskPath '\DTMS\'
                    [pscustomobject]@{
                        ComputerName = $env:COMPUTERNAME
                        CollectorPath = $CollectorPath
                        ConfigurationPath = $ConfigurationPath
                        CollectorAccount = $Account
                    }
                }
        } finally {
            Remove-PSSession -Session $session
        }
    }
    $env:DTMS_FEDERATED_UTILITY_SERVERS = $UtilityServer -join ','
    [Environment]::SetEnvironmentVariable(
        'DTMS_FEDERATED_UTILITY_SERVERS',
        ($UtilityServer -join ','),
        [EnvironmentVariableTarget]::User
    )
    Complete-DTMSActivity `
        -Activity $activity `
        -Status "Configured $($UtilityServer.Count) collector(s)."
}

function Sync-DurableOperationFederation {
    <#
    .SYNOPSIS
    Starts an immediate collection cycle on every utility server.
    #>
    [CmdletBinding()]
    param(
        [string[]]$UtilityServer,
        [pscredential]$Credential
    )

    if (@($UtilityServer).Count -eq 0) {
        $UtilityServer = @((
            Get-DTMSConfiguration
        ).Federation.UtilityServers)
    }
    if (@($UtilityServer).Count -eq 0) {
        throw 'Specify UtilityServer or configure Federation.UtilityServers.'
    }
    $activity = Start-DTMSActivity `
        -Name 'Runway federation synchronization' `
        -Intent 'Start every utility-server collector' `
        -Target ($UtilityServer -join ', ')
    try {
        foreach ($server in @($UtilityServer | Sort-Object -Unique)) {
            Update-DTMSActivity `
                -Activity $activity `
                -Status "Starting collector on $server." `
                -ForceHeartbeat
            $parameters = @{
                ComputerName = $server
                ErrorAction = 'Stop'
                ScriptBlock = {
                    Start-ScheduledTask `
                        -TaskName 'Runway-FederatedCollector' `
                        -TaskPath '\DTMS\'
                    Get-ScheduledTaskInfo `
                        -TaskName 'Runway-FederatedCollector' `
                        -TaskPath '\DTMS\'
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
            -Status $_.Exception.Message `
            -Failed
        throw
    }
}

function Get-DurableOperationFederated {
    <#
    .SYNOPSIS
    Gets newest deduplicated Runway operation records from utility indexes.
    #>
    [CmdletBinding()]
    param(
        [string[]]$UtilityServer,
        [string[]]$OperationId,
        [string[]]$ComputerName,
        [string[]]$OperationType,
        [string[]]$Status,
        [switch]$Active,
        [switch]$Latest,
        [string]$LocalPath,
        [pscredential]$Credential
    )

    $configuration = Get-DTMSConfiguration
    if (@($UtilityServer).Count -eq 0) {
        $UtilityServer = @($configuration.Federation.UtilityServers)
    }
    if (@($UtilityServer).Count -eq 0) {
        throw 'Specify UtilityServer or configure Federation.UtilityServers.'
    }
    if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        $LocalPath = [string]$configuration.Federation.LocalPath
    }
    $failures = [Collections.Generic.List[string]]::new()
    $records = @(
        foreach ($server in @($UtilityServer | Sort-Object -Unique)) {
            $parameters = @{
                ComputerName = $server
                ArgumentList = (Join-Path $LocalPath 'Index')
                ErrorAction = 'Stop'
                ScriptBlock = {
                    param($IndexRoot)
                    if (-not (Test-Path -LiteralPath $IndexRoot)) {
                        return
                    }
                    Get-ChildItem -LiteralPath $IndexRoot `
                        -Filter Current.json -File -Recurse |
                        ForEach-Object {
                            Get-Content -LiteralPath $_.FullName -Raw |
                                ConvertFrom-Json
                        }
                }
            }
            if ($Credential) {
                $parameters.Credential = $Credential
            }
            try {
                Invoke-Command @parameters
            } catch {
                $failures.Add("$server`: $($_.Exception.Message)")
            }
        }
    )
    if ($failures.Count -gt 0) {
        if ($records.Count -eq 0) {
            throw "Every federated query failed: $($failures -join '; ')"
        }
        Write-Warning "Some federated indexes failed: $($failures -join '; ')"
    }
    $filtered = @($records | Where-Object {
        (-not $OperationId -or $_.OperationId -in $OperationId) -and
        (-not $ComputerName -or $_.ComputerName -in $ComputerName) -and
        (-not $OperationType -or $_.OperationType -in $OperationType) -and
        (-not $Status -or $_.Status -in $Status) -and
        (-not $Active -or $_.Status -in @(
            'Queued', 'Running', 'Waiting', 'AwaitingReboot',
            'RollingBack'
        ))
    })
    $deduplicated = @($filtered |
        Group-Object ComputerName, OperationId |
        ForEach-Object {
            $_.Group |
                Sort-Object { [datetime]$_.UpdatedUtc } -Descending |
                Select-Object -First 1
        } |
        Sort-Object { [datetime]$_.UpdatedUtc } -Descending)
    if ($Latest) {
        $deduplicated | Select-Object -First 1
    } else {
        $deduplicated
    }
}

Export-ModuleMember -Function @(
    'Get-DurableOperationFederated'
    'Initialize-DurableOperationFederation'
    'Sync-DurableOperationFederation'
)
