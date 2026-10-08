function New-DTMSControllerSession {
    <#
    .SYNOPSIS
    Opens a PowerShell-over-SSH session to a named DTMS controller profile.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Creates and returns a remoting session without changing managed target state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileName
    )

    if (-not (Get-Command Get-DTMSConfiguration -ErrorAction SilentlyContinue)) {
        throw 'DTMS.Configuration is required for named OpenSSH controller profiles.'
    }
    $configuration = Get-DTMSConfiguration
    $profiles = $configuration.OpenSSH.ControllerProfiles
    if (-not $profiles.Contains($ProfileName)) {
        throw "OpenSSH controller profile '$ProfileName' is not configured."
    }
    $controllerProfile = $profiles[$ProfileName]
    if (-not (Test-Path -LiteralPath $controllerProfile.IdentityFile -PathType Leaf)) {
        throw (
            "Private key for controller profile '$ProfileName' was not found: " +
            $controllerProfile.IdentityFile
        )
    }
    $activity = Start-DTMSActivity `
        -Name 'SSH controller connection' `
        -Intent "Open the named controller profile '$ProfileName'" `
        -Target $controllerProfile.HostName
    try {
        $parameters = @{
            HostName = [string]$controllerProfile.HostName
            UserName = [string]$controllerProfile.UserName
            KeyFilePath = [string]$controllerProfile.IdentityFile
            ErrorAction = 'Stop'
        }
        if ($controllerProfile.Contains('Port') -and
            $controllerProfile.Port) {
            $parameters.Port = [int]$controllerProfile.Port
        }
        $session = New-PSSession @parameters
        Complete-DTMSActivity `
            -Activity $activity `
            -Status "Connected to controller '$ProfileName'."
        $session
    } catch {
        Complete-DTMSActivity `
            -Activity $activity `
            -Status $_.Exception.Message `
            -Failed
        throw
    }
}

function Start-DTMSWinRMTunnel {
    <#
    .SYNOPSIS
    Starts an SSH local forward from the workstation to a target WinRM port.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetComputerName,

        [ValidateRange(1, 65535)]
        [int]$TargetPort = 5985,

        [ValidateRange(0, 65535)]
        [int]$LocalPort = 0,

        [ValidateRange(5, 120)]
        [int]$TimeoutSeconds = 20
    )

    if (-not (Get-Command Get-DTMSConfiguration -ErrorAction SilentlyContinue)) {
        throw 'DTMS.Configuration is required for named OpenSSH controller profiles.'
    }
    $configuration = Get-DTMSConfiguration
    $profiles = $configuration.OpenSSH.ControllerProfiles
    if (-not $profiles.Contains($ProfileName)) {
        throw "OpenSSH controller profile '$ProfileName' is not configured."
    }
    $controllerProfile = $profiles[$ProfileName]
    if (-not (Test-Path -LiteralPath $controllerProfile.IdentityFile -PathType Leaf)) {
        throw (
            "Private key for controller profile '$ProfileName' was not found: " +
            $controllerProfile.IdentityFile
        )
    }
    if ($LocalPort -eq 0) {
        $listener = [Net.Sockets.TcpListener]::new(
            [Net.IPAddress]::Loopback,
            0
        )
        $listener.Start()
        try {
            $LocalPort = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
        } finally {
            $listener.Stop()
        }
    }
    if (-not $PSCmdlet.ShouldProcess(
        "localhost:$LocalPort",
        "forward to $TargetComputerName`:$TargetPort through $ProfileName"
    )) {
        return
    }
    $activity = Start-DTMSActivity `
        -Name 'SSH WinRM tunnel' `
        -Intent "Forward local port $LocalPort to $TargetComputerName`:$TargetPort" `
        -Target $controllerProfile.HostName
    $ssh = Get-Command ssh.exe -ErrorAction Stop
    $sshPort = if ($controllerProfile.Contains('Port') -and
        $controllerProfile.Port) {
        [string]$controllerProfile.Port
    } else {
        '22'
    }
    $arguments = @(
        '-N'
        '-o'
        'BatchMode=yes'
        '-o'
        'ExitOnForwardFailure=yes'
        '-i'
        [string]$controllerProfile.IdentityFile
        '-L'
        "$LocalPort`:$TargetComputerName`:$TargetPort"
        '-p'
        $sshPort
        "$($controllerProfile.UserName)@$($controllerProfile.HostName)"
    )
    $process = Start-Process `
        -FilePath $ssh.Source `
        -ArgumentList $arguments `
        -PassThru `
        -WindowStyle Hidden
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $ready = $false
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($process.HasExited) {
                throw "ssh.exe exited with code $($process.ExitCode)."
            }
            $client = [Net.Sockets.TcpClient]::new()
            try {
                $connection = $client.ConnectAsync(
                    '127.0.0.1',
                    $LocalPort
                )
                if ($connection.Wait(500) -and $client.Connected) {
                    $ready = $true
                    break
                }
            } finally {
                $client.Dispose()
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) {
            throw "SSH tunnel did not listen on local port $LocalPort."
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status "Tunnel is listening on local port $LocalPort."
        [pscustomobject]@{
            PSTypeName = 'DTMS.OpenSSH.WinRMTunnel'
            ProfileName = $ProfileName
            TargetComputerName = $TargetComputerName
            TargetPort = $TargetPort
            LocalPort = $LocalPort
            ProcessId = $process.Id
        }
    } catch {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        }
        Complete-DTMSActivity `
            -Activity $activity `
            -Status $_.Exception.Message `
            -Failed
        throw
    }
}
