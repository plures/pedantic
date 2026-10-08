#Requires -Version 5.1

<#
.SYNOPSIS
Discovers, prepares, launches, and measures the BN1 to BN1CPS VM transfer benchmark.
.DESCRIPTION
Builds the approved five-VM plan, discovers each Hyper-V host, optionally
prepares OpenSSH and BITS, validates transport prerequisites, and starts two
Robocopy, two SCP, and one BITS durable transfers. The script persists its plan,
transfer IDs, and normalized performance reports under a timestamped result
directory.

With no action switches, the script performs read-only discovery and returns
the proposed plan. Use -WhatIf with action switches to preview all mutations.
.EXAMPLE
.\Invoke-BN1VMTransferBenchmark.ps1
.EXAMPLE
.\Invoke-BN1VMTransferBenchmark.ps1 -PrepareInfrastructure -StartTransfers -Watch
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Invoke-Command script blocks declare values in param() and receive them through ArgumentList.'
)]
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TransferAccount = 'USME\_is_dtms_util$',

    [ValidateNotNullOrEmpty()]
    [string]$SshUserName = 'USME\_is_dtms_util',

    [ValidateNotNullOrEmpty()]
    [string]$LocalKeyPath = "$env:ProgramData\DTMS\SSH\bn1-transfer-ed25519",

    [ValidateNotNullOrEmpty()]
    [string]$RemoteKeyPath = 'C:\ProgramData\DTMS\SSH\bn1-transfer-ed25519',

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = (Join-Path $env:ProgramData 'DTMS\Benchmarks'),

    [ValidateNotNullOrEmpty()]
    [string[]]$DiscoveryComputerName,

    [hashtable]$VMHostMap = @{},

    [ValidateNotNullOrEmpty()]
    [string]$VMHostMapPath,

    [ValidateNotNullOrEmpty()]
    [string]$FederatedUtilityServerPattern =
        '^(?:SN5|PHX23|PHX21)ISUTIL\d{2,3}$',

    [switch]$PrepareInfrastructure,

    [switch]$StartTransfers,

    [switch]$Watch,

    [switch]$SkipPreflight,

    [switch]$SkipFederatedRegistry,

    [ValidateRange(2, 300)]
    [int]$RefreshSeconds = 10,

    [ValidateRange(1, 10080)]
    [int]$TimeoutMinutes = 1440,

    [switch]$TurnOff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Information `
    -MessageData '[DTMS] START BN1 VM transfer benchmark - validate the launcher, discover hosts, and build the execution plan.' `
    -Tags 'DTMS', 'Activity', 'Start' `
    -InformationAction Continue

if ($env:COMPUTERNAME -ine 'PHX23ISUTIL01') {
    throw "This benchmark must be launched from PHX23ISUTIL01; current computer is '$env:COMPUTERNAME'."
}
if ($TransferAccount -notmatch '\$$') {
    throw "TransferAccount '$TransferAccount' must be a gMSA account ending in '$'."
}

$utilitiesManifest = Join-Path $PSScriptRoot '..\DTMS.Utilities\DTMS.Utilities.psd1'
Import-Module $utilitiesManifest -ArgumentList 'Quiet' -Force -ErrorAction Stop
$activity = Start-DTMSActivity `
    -Name 'BN1 VM transfer benchmark' `
    -Intent 'Discover, prepare, launch, monitor, and report the approved VM transfers'

$approvedMappings = @(
    [pscustomobject]@{
        SourceVMName = 'BN1USMEPRXYXGW1'
        TargetVMName = 'BN1CPSUSMEPRXYXGW1'
        Transport = 'Robocopy'
    }
    [pscustomobject]@{
        SourceVMName = 'BN1USMEPRXYXGW2'
        TargetVMName = 'BN1CPSUSMEPRXYXGW2'
        Transport = 'Robocopy'
    }
    [pscustomobject]@{
        SourceVMName = 'BN1USMEPRXYXGW3'
        TargetVMName = 'BN1CPSUSMEPRXYXGW3'
        Transport = 'Scp'
    }
    [pscustomobject]@{
        SourceVMName = 'BN1USMEPRXYXGW4'
        TargetVMName = 'BN1CPSUSMEPRXYXGW4'
        Transport = 'Scp'
    }
    [pscustomobject]@{
        SourceVMName = 'BN1USMEPRXYXGW5'
        TargetVMName = 'BN1CPSUSMEPRXYXGW5'
        Transport = 'Bits'
    }
)

function Resolve-SingleVMHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$DiscoveryResult,

        [Parameter(Mandatory)]
        [hashtable]$HostMap
    )

    if ($HostMap.ContainsKey($VMName)) {
        $mappedHost = [string]$HostMap[$VMName]
        if ([string]::IsNullOrWhiteSpace($mappedHost)) {
            throw "VMHostMap contains an empty host name for VM '$VMName'."
        }
        return $mappedHost
    }
    $hostMatches = @($DiscoveryResult | Where-Object {
        $_.PSObject.Properties['Found'] -and
        $_.PSObject.Properties['HostName'] -and
        $_.PSObject.Properties['VMName'] -and
        $_.Found -and
        $_.VMName -ieq $VMName
    })
    if ($hostMatches.Count -ne 1) {
        $hosts = @($hostMatches |
            ForEach-Object { $_.HostName } |
            Sort-Object -Unique)
        $location = if ($hosts.Count -gt 0) {
            $hosts -join ', '
        } else {
            'no accessible queried host'
        }
        throw (
            "Expected one accessible Hyper-V registration for VM '$VMName'; " +
            "found $($hostMatches.Count) on $location. VMs are not discovered " +
            'from Active Directory; AD supplies only candidate Hyper-V hosts. ' +
            "Provide -VMHostMap or -VMHostMapPath to identify this VM's host " +
            'without broad host probing.'
        )
    }
    $hostMatches[0].HostName
}

function Test-TransferWorkerAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Account
    )

    foreach ($computer in $ComputerName) {
        Invoke-Command -ComputerName $computer -ArgumentList $Account -ScriptBlock {
            param($Principal)
            $testCommand = Get-Command Test-ADServiceAccount -ErrorAction SilentlyContinue
            if (-not $testCommand) {
                throw 'Test-ADServiceAccount is unavailable. Install the Active Directory PowerShell feature.'
            }
            $samAccountName = ($Principal -split '\\')[-1].TrimEnd('$')
            if (-not (Test-ADServiceAccount -Identity $samAccountName)) {
                throw "gMSA '$Principal' is not installed or usable on '$env:COMPUTERNAME'."
            }
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                TransferAccount = $Principal
                Usable = $true
            }
        }
    }
}

function New-TransferKeyPair {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Path, 'generate benchmark SSH key pair')) {
        return
    }
    $keyDirectory = Split-Path -Path $Path -Parent
    New-Item -Path $keyDirectory -ItemType Directory -Force | Out-Null
    $sshKeygen = Get-Command ssh-keygen.exe -ErrorAction Stop
    $arguments = @(
        '-t'
        'ed25519'
        '-f'
        "`"$Path`""
        '-N'
        '""'
        '-C'
        "`"$TransferAccount@$env:COMPUTERNAME`""
    )
    $process = Start-Process `
        -FilePath $sshKeygen.Source `
        -ArgumentList $arguments `
        -Wait `
        -PassThru `
        -NoNewWindow
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath "$Path.pub" -PathType Leaf)) {
        throw "ssh-keygen failed with exit code $($process.ExitCode)."
    }
    & icacls.exe $Path /inheritance:r /grant:r `
        '*S-1-5-32-544:F' '*S-1-5-18:F' "$TransferAccount`:R" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to secure private key '$Path'; icacls exited with $LASTEXITCODE."
    }
}

Write-Verbose 'Discovering authoritative Hyper-V registrations for the approved VM mappings.'
Update-DTMSActivity `
    -Activity $activity `
    -Status 'Discovering source and target Hyper-V registrations.' `
    -ForceHeartbeat
$effectiveVMHostMap = @{}
foreach ($entry in $VMHostMap.GetEnumerator()) {
    $effectiveVMHostMap[[string]$entry.Key] = [string]$entry.Value
}
if ($VMHostMapPath) {
    if (-not (Test-Path -LiteralPath $VMHostMapPath -PathType Leaf)) {
        throw "VM host-map file '$VMHostMapPath' was not found."
    }
    $mapRecords = if ([IO.Path]::GetExtension($VMHostMapPath) -ieq '.json') {
        $jsonMap = Get-Content -LiteralPath $VMHostMapPath -Raw |
            ConvertFrom-Json
        @($jsonMap.PSObject.Properties | ForEach-Object {
            [pscustomobject]@{ VMName = $_.Name; HostName = $_.Value }
        })
    } else {
        @(Import-Csv -LiteralPath $VMHostMapPath)
    }
    foreach ($record in $mapRecords) {
        if (-not $record.PSObject.Properties['VMName'] -or
            -not $record.PSObject.Properties['HostName'] -or
            [string]::IsNullOrWhiteSpace([string]$record.VMName) -or
            [string]::IsNullOrWhiteSpace([string]$record.HostName)) {
            throw "VM host-map file '$VMHostMapPath' requires VMName and HostName values."
        }
        $effectiveVMHostMap[[string]$record.VMName] = [string]$record.HostName
    }
}
$requiredVMNames = @(
    $approvedMappings.SourceVMName
    $approvedMappings.TargetVMName
)
$unmappedVMNames = @($requiredVMNames |
    Where-Object { -not $effectiveVMHostMap.ContainsKey($_) })
$discoveryParameters = @{
    VMName = 'BN1*USMEPRXYXGW*'
    IncludeQueryErrors = $true
}
if ($DiscoveryComputerName) {
    $discoveryParameters.ComputerName = $DiscoveryComputerName
}
$discoveryResults = if ($unmappedVMNames.Count -gt 0) {
    @(Find-VMHost @discoveryParameters)
} else {
    @()
}
$queryFailures = @($discoveryResults | Where-Object {
    $_.PSObject.Properties['QuerySucceeded'] -and
    -not $_.QuerySucceeded
})
if ($queryFailures.Count -gt 0) {
    $failureSummary = @($queryFailures |
        Group-Object ErrorCategory |
        Sort-Object Count -Descending |
        ForEach-Object { '{0}: {1}' -f $_.Name, $_.Count })
    Write-Warning (
        'Hyper-V discovery could not query {0} host(s). Failure categories: {1}' -f
        $queryFailures.Count,
        ($failureSummary -join '; ')
    )
}
$plan = @(
    foreach ($mapping in $approvedMappings) {
        [pscustomobject]@{
            SourceVMName = $mapping.SourceVMName
            TargetVMName = $mapping.TargetVMName
            SourceHostName = Resolve-SingleVMHost `
                -VMName $mapping.SourceVMName `
                -DiscoveryResult $discoveryResults `
                -HostMap $effectiveVMHostMap
            TargetHostName = Resolve-SingleVMHost `
                -VMName $mapping.TargetVMName `
                -DiscoveryResult $discoveryResults `
                -HostMap $effectiveVMHostMap
            Transport = $mapping.Transport
        }
    }
)

if (@($plan.SourceVMName | Sort-Object -Unique).Count -ne 5 -or
    @($plan.TargetVMName | Sort-Object -Unique).Count -ne 5) {
    throw 'The benchmark plan must contain five unique source and five unique target VMs.'
}
if (@($plan | Where-Object Transport -eq 'Robocopy').Count -ne 2 -or
    @($plan | Where-Object Transport -eq 'Scp').Count -ne 2 -or
    @($plan | Where-Object Transport -eq 'Bits').Count -ne 1) {
    throw 'The benchmark transport allocation must be two Robocopy, two SCP, and one BITS transfer.'
}

$sourceHosts = @($plan.SourceHostName | Sort-Object -Unique)
$targetHosts = @($plan.TargetHostName | Sort-Object -Unique)
$allHosts = @($sourceHosts + $targetHosts | Sort-Object -Unique)
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$resultPath = Join-Path $OutputRoot $runId
$plan | Format-Table SourceVMName, TargetVMName, SourceHostName, TargetHostName, Transport | Out-Host

if ($PrepareInfrastructure -and $PSCmdlet.ShouldProcess(
    ($allHosts -join ', '),
    'prepare benchmark OpenSSH, BITS, keys, and gMSA prerequisites'
)) {
    Update-DTMSActivity `
        -Activity $activity `
        -Status 'Preparing OpenSSH, BITS, keys, gMSA access, and federated indexes.' `
        -PercentComplete 20 `
        -ForceHeartbeat
    New-TransferKeyPair -Path $LocalKeyPath -Confirm:$false
    $publicKey = (Get-Content -LiteralPath "$LocalKeyPath.pub" -Raw).Trim()
    $privateKey = Get-Content -LiteralPath $LocalKeyPath -Raw

    Test-TransferWorkerAccount -ComputerName $targetHosts -Account $TransferAccount | Out-Host
    Initialize-SSHTransferHost `
        -ComputerName $sourceHosts `
        -AuthorizedKey $publicKey `
        -Confirm:$false | Out-Host
    Initialize-SSHTransferHost `
        -ComputerName $targetHosts `
        -PrivateKeyContent $privateKey `
        -PrivateKeyPath $RemoteKeyPath `
        -TransferAccount $TransferAccount `
        -Confirm:$false | Out-Host
    if (-not $SkipFederatedRegistry) {
        Initialize-VMResourceTransferFederation `
            -UtilityServerPattern $FederatedUtilityServerPattern `
            -TargetHostName $targetHosts `
            -CollectorAccount $TransferAccount `
            -RetentionCount 90 `
            -Confirm:$false | Out-Host
    }
}

if (($PrepareInfrastructure -or $StartTransfers) -and
    -not $SkipPreflight -and
    $PSCmdlet.ShouldProcess(
        ($targetHosts -join ', '),
        'run non-mutating SCP connectivity and key-authentication preflight'
    )) {
    foreach ($row in @($plan | Where-Object Transport -eq 'Scp')) {
        $connectivity = Invoke-Command `
            -ComputerName $row.TargetHostName `
            -ArgumentList $row.SourceHostName, $RemoteKeyPath, $SshUserName `
            -ScriptBlock {
                param($SourceHost, $IdentityFile, $SshUser)
                if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
                    throw "SCP private key '$IdentityFile' is unavailable."
                }
                $test = Test-NetConnection -ComputerName $SourceHost -Port 22 -WarningAction SilentlyContinue
                if (-not $test.TcpTestSucceeded) {
                    throw "TCP port 22 is unavailable on '$SourceHost'."
                }
                $output = & ssh.exe `
                    -i $IdentityFile `
                    -o BatchMode=yes `
                    -o StrictHostKeyChecking=accept-new `
                    "$SshUser@$SourceHost" hostname 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Key-authenticated SSH preflight failed: $($output -join ' ')"
                }
                [pscustomobject]@{
                    TargetHostName = $env:COMPUTERNAME
                    SourceHostName = $SourceHost
                    Port22 = $true
                    KeyAuthentication = $true
                }
            }
        $connectivity | Out-Host
    }
}

$launches = @()
if ($StartTransfers) {
    Update-DTMSActivity `
        -Activity $activity `
        -Status 'Launching the five durable VM transfers.' `
        -PercentComplete 35 `
        -ForceHeartbeat
    foreach ($row in $plan) {
        $target = "$($row.SourceVMName) -> $($row.TargetVMName) using $($row.Transport)"
        if (-not $PSCmdlet.ShouldProcess($target, 'start durable VM resource transfer')) {
            continue
        }
        $parameters = @{
            SourceVMName = $row.SourceVMName
            TargetVMName = $row.TargetVMName
            SourceHostName = $row.SourceHostName
            TargetHostName = $row.TargetHostName
            Resource = @('HardDrives', 'MacAddress')
            TransferAccount = $TransferAccount
            TransferTransport = $row.Transport
            TurnOff = $TurnOff
            Confirm = $false
        }
        if ($row.Transport -eq 'Scp') {
            $parameters.ScpSourceEndpoint = "$SshUserName@$($row.SourceHostName)"
            $parameters.ScpIdentityFile = $RemoteKeyPath
        }
        $launch = Copy-VMResource @parameters
        $launches += [pscustomobject]@{
            TransferId = $launch.TransferId
            SourceVMName = $row.SourceVMName
            TargetVMName = $row.TargetVMName
            SourceHostName = $row.SourceHostName
            TargetHostName = $row.TargetHostName
            Transport = $row.Transport
            StartedUtc = [DateTime]::UtcNow.ToString('o')
        }
    }
}

if ($launches.Count -gt 0 -and $PSCmdlet.ShouldProcess($resultPath, 'write benchmark plan and transfer manifest')) {
    New-Item -Path $resultPath -ItemType Directory -Force | Out-Null
    $plan | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $resultPath 'Plan.json') -Encoding UTF8
    $launches | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $resultPath 'Transfers.json') -Encoding UTF8
}

if ($Watch -and $launches.Count -gt 0) {
    Update-DTMSActivity `
        -Activity $activity `
        -Status 'Monitoring active transfers and collecting performance data.' `
        -PercentComplete 50 `
        -ForceHeartbeat
    $watchParameters = @{
        TargetHostName = @($launches.TargetHostName | Sort-Object -Unique)
        TransferId = @($launches.TransferId)
        RefreshSeconds = $RefreshSeconds
        TimeoutMinutes = $TimeoutMinutes
    }
    Watch-VMResourceTransfer @watchParameters | Out-Host
    $reportPath = Join-Path $resultPath 'Performance.csv'
    $report = @(Get-VMResourceTransferPerformanceReport `
        -TargetHostName $watchParameters.TargetHostName `
        -TransferId $watchParameters.TransferId `
        -Path $reportPath)
    $report | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $resultPath 'Performance.json') -Encoding UTF8
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'Benchmark transfers and performance reports completed.'
    $report
} elseif ($launches.Count -gt 0) {
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'Benchmark transfers were launched successfully.'
    $launches
} else {
    Complete-DTMSActivity `
        -Activity $activity `
        -Status 'Read-only benchmark discovery plan completed.'
    $plan
}
