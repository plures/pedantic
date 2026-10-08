<#
.SYNOPSIS
    PowerShell module for SSH utilities and OpenSSH management on Windows.

.DESCRIPTION
    This module provides comprehensive SSH functionality including:
    - SSH configuration management
    - OpenSSH client/server installation and management
    - SSH key management and authentication
    - SSH tunneling and proxy functionality
    - Remote desktop proxy connections

.NOTES
    Note:Combined from SSHUtilities.ps1 and Install-OpenSSH.ps1
    Primary runtime: PowerShell 7.x
    Compatibility runtime: Windows PowerShell 5.1
#>

[CmdletBinding()]
param(
  [ValidateSet('Notify', 'Quiet', 'Prompt', 'Initialize')]
  [string]$StartupMode = 'Notify',

  [hashtable]$StartupOptions = @{}
)

# Set strict mode to catch common errors
Set-StrictMode -Version Latest

$runwayManifest = Join-Path $PSScriptRoot '..\DTMS.Runway\DTMS.Runway.psd1'
if (-not (Get-Module -Name 'DTMS.Runway') -and
    (Test-Path -LiteralPath $runwayManifest -PathType Leaf)) {
  Import-Module $runwayManifest -ArgumentList 'Quiet' -Force -ErrorAction Stop
}
$transferManifest = Join-Path $PSScriptRoot '..\DTMS.Transfer\DTMS.Transfer.psd1'
if (-not (Get-Module -Name 'DTMS.Transfer') -and
    (Test-Path -LiteralPath $transferManifest -PathType Leaf)) {
  Import-Module $transferManifest -Force -ErrorAction Stop
}
$configurationManifest = Join-Path $PSScriptRoot `
  '..\DTMS.Configuration\DTMS.Configuration.psd1'
if (-not (Get-Module -Name 'DTMS.Configuration') -and
  (Test-Path -LiteralPath $configurationManifest -PathType Leaf)) {
  Import-Module $configurationManifest -Force -ErrorAction Stop
}
. (Join-Path $PSScriptRoot 'DTMS.OpenSSH.Controller.ps1')

Function New-SSHConfig {
  <#
  .SYNOPSIS
      Creates a new SSH config file from a template.
  .DESCRIPTION
      Generates an SSH config file in the user's .ssh directory based on a predefined template file.
  .PARAMETER userSSHConfigPath
      Path to the user's SSH config file. Defaults to $env:USERPROFILE\.ssh\config
  .PARAMETER TemplateFile
      Path to the template file. Defaults to ./config.template
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  Param(
    [Parameter(Mandatory = $false)]
    [string]$userSSHConfigPath = "$env:USERPROFILE\.ssh\config",
    [Parameter(Mandatory = $false)]
    [string]$TemplateFile = "./config.template"
  )

  if ((-not (Test-Path -Path $userSSHConfigPath)) -and $PSCmdlet.ShouldProcess($userSSHConfigPath, "Create SSH config file")) {
    Write-Verbose "Creating SSH config file..."

    # Create the .ssh directory if it doesn't exist
    $sshDir = Split-Path -Path $userSSHConfigPath -Parent
    if (-not (Test-Path -Path $sshDir)) {
      New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
      Write-Verbose "Created SSH directory at $sshDir"
    }

    # Check if template file exists
    if (-not (Test-Path -Path $TemplateFile)) {
      Write-Error "Template file not found at $TemplateFile"
      return $null
    }

    # Write the template content to the user's SSH config file
    Get-Content $TemplateFile | Set-Content -Path $userSSHConfigPath
    Write-Output "SSH config file created at $userSSHConfigPath"
  }
  else {
    Write-Output "SSH config file already exists at $userSSHConfigPath"
  }
}
Function Set-AdminAuthKeys {
  <#
  .SYNOPSIS
      Sets up SSH authorized keys for administrator access on a remote Windows host.
  .DESCRIPTION
      Uses PowerShell remoting (Invoke-Command) to copy public keys to the remote host's administrators_authorized_keys file and sets proper permissions.
  .PARAMETER RemoteHost
      The remote Windows host to configure.
  .PARAMETER Credential
      PSCredential object for authentication to the remote host.
  .PARAMETER username
      Username for key generation comments. Defaults to current user.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Preserve the exported public command name for compatibility.')]
  Param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteHost,
    # [Parameter(Mandatory = $false)]
    # [PSCredential]$Credential,
    [Parameter(Mandatory = $false)]
    [string]$username = $env:USERNAME,
    [Parameter(Mandatory = $false)]
    [string]$keyfile
  )

  $sshFolder = "$env:USERPROFILE\.ssh"


  if (test-path -path $keyfile) {
    # If a specific key file is provided, use it
    $publicKeyFile = Get-ChildItem -Path "$($keyfile).pub"

    if (-not (Test-Path -Path $publicKeyFile)) {
      Write-Error "Specified public key was not found at $($keyfile).pub"
      return $false
    }
  }
  else {
    # Otherwise, look for all public key files in the .ssh directory
    Write-Error "Specified private key does not exist at $keyfile"
    # No public keys found, generate one
    Write-Verbose "No public key files found. Generating new key..."
    $keyPath = "$sshFolder\id_ecdsa"

    ssh-keygen -t ecdsa -b 521 -f $keyPath -C "$username@$(hostname)" -N '""'

    if (-not (Test-Path -Path "$($keyPath).pub")) {
      Write-Error "Failed to generate SSH key"
      return $false
    }

    $publicKeyFile = Get-ChildItem -Path "$keyPath.pub"

  }

  # Process all public key files
  $authorizedKey = Get-Content -Path $publicKeyFile.FullName -Raw

  Write-Verbose "Connecting to $RemoteHost via PowerShell remoting to set up authorized keys..."

  #if ($PSCmdlet.ShouldProcess($RemoteHost, "Set administrator authorized keys via Invoke-Command")) {
  try {
    # Define the script block to execute on the remote server
    $scriptBlock = {
      param($AuthorizedKey)

      $adminAuthKeysPath = "$env:ProgramData\ssh\administrators_authorized_keys"
      $authKeysPath = "$env:userprofile\.ssh\authorized_keys"
      $AuthorizedKey = Get-Content -Path "$env:userprofile\.ssh\$authorizedKey" -Raw
      # Create SSH directory if it doesn't exist
      if (-not (Test-Path -Path "$env:ProgramData\ssh")) {
        New-Item -Path "$env:ProgramData\ssh" -ItemType Directory -Force | Out-Null
      }
      if (-not (Test-Path -Path "$env:userprofile\.ssh")) {
        New-Item -Path "$env:userprofile\.ssh" -ItemType Directory -Force | Out-Null
      }

      # Add the authorized key if not already present
      $existingAdminKeys = ""
      if (Test-Path -Path $adminAuthKeysPath) {
        $existingAdminKeys = Get-Content -Path $adminAuthKeysPath -Raw
      }
      $existingKeys = ""
      if (Test-Path -Path $authKeysPath) {
        $existingKeys = Get-Content -Path $authKeysPath -Raw
      }


      if (-not $existingKeys.Contains($AuthorizedKey)) {
        Add-Content -Force -Path $authKeysPath -Value "$AuthorizedKey"
        Write-Output "Added new authorized key to $authKeysPath"
      }
      else {
        Write-Output "Authorized key already exists in $authKeysPath"
      }

      if (-not $existingAdminKeys.Contains($AuthorizedKey)) {
        Add-Content -Force -Path $adminAuthKeysPath -Value "$AuthorizedKey"
        Write-Output "Added new authorized key to $adminAuthKeysPath"
      }
      else {
        Write-Output "Authorized key already exists in $adminAuthKeysPath"
      }

      # Set proper permissions on the authorized_keys file
      try {
        & icacls.exe $adminAuthKeysPath /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null
        & icacls.exe $authKeysPath /inheritance:r /grant "$($env:username)@$($env:userdomain):F" /grant "SYSTEM:F" 2>$null
        Write-Output "Set permissions on $adminAuthKeysPath"
      }
      catch {
        Write-Warning "Failed to set permissions on $adminAuthKeysPath`: $($_.Exception.Message)"
      }

      return $true
    }

    $session = New-PSSession -ComputerName $RemoteHost -ErrorAction Stop

    Copy-Item -Path $publicKeyFile.FullName -Destination "$env:USERPROFILE\.ssh\" -toSession $session
    # Prepare Invoke-Command parameters
    $invokeParams = @{
      Session      = $session
      ScriptBlock  = $scriptBlock
      ArgumentList = ($publicKeyFile.name)
      ErrorAction  = 'Stop'
    }

    # Execute the script block on the remote server
    $result = Invoke-Command @invokeParams

    if ($result) {
      Write-Verbose "Key successfully processed on $RemoteHost"
    }
  }
  catch {
    Write-Error "Failed to set up authorized keys on $RemoteHost via PowerShell remoting. Error: $($_.Exception.Message)"
    Write-Verbose "Ensure PowerShell remoting is enabled on $RemoteHost and you have appropriate credentials."
    return $false
  }
  #}

  Write-Output "Successfully set up authorized keys for administrator on $RemoteHost"
  return $true
}
Function Set-KeyPassphrase {
  <#
  .SYNOPSIS
      Changes the passphrase for an SSH private key.
  .DESCRIPTION
      Uses ssh-keygen to change the passphrase of an existing SSH private key.
  .PARAMETER PrivateKeyPath
      Path to the private key file. Defaults to $env:USERPROFILE\.ssh\id_ecdsa
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  Param(
    [Parameter(Mandatory = $false)]
    [string]$PrivateKeyPath = "$env:USERPROFILE\.ssh\id_ecdsa"
  )

  if (-not (Test-Path -Path $PrivateKeyPath)) {
    Write-Error "Private key file not found at $PrivateKeyPath"
    return $false
  }

  if ($PSCmdlet.ShouldProcess($PrivateKeyPath, "Change passphrase")) {
    try {
      ssh-keygen -p -f $PrivateKeyPath
      Write-Output "Passphrase changed successfully"
      return $true
    }
    catch {
      Write-Error "Failed to change passphrase: $($_.Exception.Message)"
      return $false
    }
  }

  return $false
}
#region Proxy and Tunneling Functions
Function Start-RDProxy {
  <#
  .SYNOPSIS
      Starts an RDP connection through an SSH proxy.
  .DESCRIPTION
      Creates an SSH tunnel and launches Remote Desktop Connection through the tunnel.
  .PARAMETER username
      Username for SSH connection. Defaults to current user.
  .PARAMETER RemotePort
      Remote RDP port. Defaults to 3389.
  .PARAMETER LocalPort
      Local port for tunnel. Auto-selected if not specified.
  .PARAMETER RemoteHost
      The target remote host for RDP connection.
  .PARAMETER ProxyHost
      The SSH proxy host to tunnel through.
  .PARAMETER Admin
      Connect as administrator.
  .PARAMETER MultiMon
      Enable multi-monitor support.
  .PARAMETER FullScreen
      Start in full screen mode.
  .PARAMETER Retries
      Number of connection retries. Defaults to 3.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'username', Justification = 'Consumed by the nested Connect-ToProxy function through parent scope.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RemotePort', Justification = 'Consumed by the nested Connect-ToProxy function through parent scope.')]
  Param(
    [Parameter(Mandatory = $false)]
    [string]$username = $env:USERNAME,
    [Parameter(Mandatory = $false)]
    [int]$RemotePort = 3389,
    [Parameter(Mandatory = $false)]
    [int]$LocalPort,
    [Parameter(Mandatory = $true)]
    [string]$RemoteHost,
    [Parameter(Mandatory = $true)]
    [string]$ProxyHost,
    [Parameter(Mandatory = $false)]
    [switch]$Admin,
    [Parameter(Mandatory = $false)]
    [switch]$MultiMon,
    [Parameter(Mandatory = $false)]
    [switch]$FullScreen,
    [Parameter(Mandatory = $false)]
    [int]$Retries = 3
  )

  Function Connect-ToProxy {
    [CmdletBinding()]
    param ()

    Write-Progress -Activity "Establishing SSH tunnel to $RemoteHost via $ProxyHost..." -PercentComplete ((Get-Date).Subtract($startTime).TotalSeconds / $delay * 100)

    if ($null -eq $sshProcess -or $sshProcess.HasExited) {
      $script:currentRetries--
      Write-Verbose "Starting SSH tunnel. Retries left: $script:currentRetries"
      $script:sshProcess = Start-Process -NoNewWindow -FilePath "ssh" -ArgumentList "-L $($LocalPort):$($RemoteHost):$($RemotePort) $username@$ProxyHost -N" -PassThru

      # Wait for the tunnel to be established
      $tunnelReady = $false
      $timeoutTime = (Get-Date).AddSeconds($delay)

      while (-not $tunnelReady -and (Get-Date) -lt $timeoutTime) {
        Write-Progress -Activity "Establishing SSH tunnel to $RemoteHost via $ProxyHost..." -PercentComplete ((Get-Date).Subtract($startTime).TotalSeconds / $delay * 100)

        if ($sshProcess.HasExited) {
          Write-Verbose "SSH process exited prematurely with exit code $($sshProcess.ExitCode)"
          return $false
        }

        # Check if port is listening
        try {
          $tcpClient = New-Object System.Net.Sockets.TcpClient
          $tcpClient.Connect("localhost", $LocalPort)
          $tunnelReady = $tcpClient.Connected
          $tcpClient.Close()
        }
        catch {
          Write-Verbose "Local port $LocalPort is not ready: $($_.Exception.Message)"
          Start-Sleep -Seconds 1
        }
      }

      if (-not $tunnelReady) {
        Write-Verbose "Tunnel setup timeout"
        return $false
      }

      return $true
    }
    else {
      # Process is still running
      return $true
    }
  }

  try {
    # If no local port is specified, find an available one
    if ($null -eq $LocalPort -or $LocalPort -eq 0) {
      $tcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
      $tcpListener.Start()
      $LocalPort = ([System.Net.IPEndPoint]$tcpListener.LocalEndpoint).Port
      $tcpListener.Stop()
      Write-Verbose "Selected available local port: $LocalPort"
    }

    $script:sshProcess = $null
    $script:currentRetries = $Retries
    $delay = 10
    $startTime = Get-Date
    $argList = "/v:localhost:$LocalPort "

    if ($Admin) { $argList += "/admin " }
    if ($MultiMon) { $argList += "/multimon " }
    if ($FullScreen) { $argList += "/f " }

    $tunnelEstablished = $false

    while ($script:currentRetries -ge 0 -and -not $tunnelEstablished) {
      $tunnelEstablished = Connect-ToProxy

      if (-not $tunnelEstablished -and $script:currentRetries -gt 0) {
        Write-Verbose "Retrying tunnel setup..."
        Start-Sleep -Seconds 2
      }
      elseif (-not $tunnelEstablished) {
        throw "Failed to establish SSH tunnel after $Retries retries"
      }
    }

    if ($tunnelEstablished -and $PSCmdlet.ShouldProcess("localhost:$LocalPort", "Connect via RDP")) {
      # Launch Remote Desktop Connection
      Write-Output "Starting RDP connection to $RemoteHost through proxy $ProxyHost on localhost:$LocalPort"
      Start-Process -FilePath "mstsc.exe" -ArgumentList $argList
      return $true
    }

    return $false
  }
  catch {
    Write-Error "Error establishing RD Proxy connection: $($_.Exception.Message)"
    return $false
  }
  finally {
    if ($null -ne $script:sshProcess -and $tunnelEstablished -eq $false) {
      Write-Verbose "Cleaning up failed SSH tunnel process"
      try { $script:sshProcess.Kill() } catch { Write-Verbose "Failed to stop SSH tunnel process: $($_.Exception.Message)" }
    }
  }
}

Function Start-DynamicProxy {
  <#
  .SYNOPSIS
      Creates dynamic SOCKS proxy connections through SSH.
  .DESCRIPTION
      Establishes SSH sessions with dynamic port forwarding to create SOCKS proxies.
  .PARAMETER username
      Username for SSH connections. Defaults to current user.
  .PARAMETER ProxyHosts
      Array of proxy hosts to connect to.
  .PARAMETER StartingPort
      Starting port number for SOCKS proxies. Defaults to 8000.
  .PARAMETER PrivateKeyPath
      Path to private key file for authentication.
  .PARAMETER Credential
      PSCredential object for authentication.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $false)]
    [string]$username = $env:USERNAME,
    [Parameter(Mandatory = $true)]
    [string[]]$ProxyHosts,
    [Parameter(Mandatory = $false)]
    [int]$StartingPort = 8000,
    [Parameter(Mandatory = $false)]
    [string]$PrivateKeyPath = "$env:USERPROFILE\.ssh\id_rsa",
    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential
  )

  # Ensure Posh-SSH is installed
  if (-not (Get-Module -ListAvailable -Name "Posh-SSH")) {
    Write-Verbose "Posh-SSH module not found. Installing..."
    Install-PoshSSHModule -ModuleName "Posh-SSH"

    if (-not (Get-Module -ListAvailable -Name "Posh-SSH")) {
      Write-Error "Failed to install Posh-SSH module. Please install it manually."
      return $false
    }
  }

  Function New-DTMSControllerSession {
      <#
      .SYNOPSIS
          Opens a PowerShell-over-SSH session to a named DTMS controller profile.
      .DESCRIPTION
          Uses per-user key authentication from DTMS.Configuration. The private key
          is read from the configured local path and is never generated, copied, or
          persisted by DTMS.
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
        if ($controllerProfile.Contains('Port') -and $controllerProfile.Port) {
          $parameters.Port = [int]$controllerProfile.Port
        }
        $session = New-PSSession @parameters
        Complete-DTMSActivity `
          -Activity $activity `
          -Status "Connected to controller '$ProfileName'."
        $session
      }
      catch {
        Complete-DTMSActivity `
          -Activity $activity `
          -Status $_.Exception.Message `
          -Failed
        throw
      }
    }

    Function Start-DTMSWinRMTunnel {
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
        }
        finally {
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
      $arguments = @(
        '-N'
        '-o', 'BatchMode=yes'
        '-o', 'ExitOnForwardFailure=yes'
        '-i', [string]$controllerProfile.IdentityFile
        '-L', "$LocalPort`:$TargetComputerName`:$TargetPort"
        '-p', $(if ($controllerProfile.Contains('Port') -and
          $controllerProfile.Port) {
            [string]$controllerProfile.Port
          } else {
            '22'
          })
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
            $connection = $client.ConnectAsync('127.0.0.1', $LocalPort)
            if ($connection.Wait(500) -and $client.Connected) {
              $ready = $true
              break
            }
          }
          finally {
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
      }
      catch {
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

  # Import the module
  Import-Module -Name "Posh-SSH" -ErrorAction Stop

  $sessions = @()
  $port = $StartingPort

  foreach ($proxyHost in $ProxyHosts) {
    try {
      Write-Verbose "Setting up dynamic port forward for $proxyHost on local port $port"

      if ($PSCmdlet.ShouldProcess($proxyHost, "Create SSH session with dynamic port forward")) {
        $sshParams = @{
          ComputerName = $proxyHost
          AcceptKey    = $true
        }

        # Add credentials if provided
        if ($null -ne $Credential) {
          $sshParams.Credential = $Credential
        }
        elseif (Test-Path $PrivateKeyPath) {
          $sshParams.KeyFile = $PrivateKeyPath
        }
        else {
          $sshParams.Username = $username
        }

        $session = New-SSHSession @sshParams

        if ($null -ne $session) {
          $forwardResult = New-SSHDynamicPortForward -SSHSession $session -LocalPort $port

          if ($forwardResult) {
            $sessions += [PSCustomObject]@{
              Host    = $proxyHost
              Session = $session
              Port    = $port
            }
            Write-Output "Established dynamic SOCKS proxy via $proxyHost on localhost:$port"
            $port++
          }
          else {
            Write-Error "Failed to establish port forwarding for $proxyHost"
          }
        }
      }
    }
    catch {
      Write-Error "Error setting up dynamic proxy for $proxyHost`: $($_.Exception.Message)"
    }
  }

  return $sessions
}

#endregion

#region Module Installation Functions

Function Install-PoshSSHModule {
  <#
  .SYNOPSIS
      Installs the Posh-SSH PowerShell module.
  .DESCRIPTION
      Downloads and installs the Posh-SSH module, handling SAW environments appropriately.
  .PARAMETER ModuleName
      Name of the module to install. Defaults to "Posh-SSH".
  .PARAMETER ModulePath
      Custom installation path for the module.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)]
    [string]$ModuleName = "Posh-SSH",
    [Parameter(Mandatory = $false)]
    [string]$ModulePath
  )

  try {
    # Check if module is already installed
    if (Get-Module -ListAvailable -Name $ModuleName) {
      Write-Output "Module $ModuleName is already installed"
      return $true
    }

    # Define module path if not specified
    if (-not $ModulePath) {
      if ($env:PSModulePath -like "*\SAW*") {
        # We're in a SAW environment
        $ModulePath = "$env:USERPROFILE\SAWPSModulePath\"
      }
      else {
        # Regular environment - use standard module path
        $ModulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
      }
    }

    # Create directory if it doesn't exist
    if (-not (Test-Path -Path $ModulePath)) {
      New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
    }

    Write-Output "Installing $ModuleName module to $ModulePath..."
    Save-Module -Name $ModuleName -Path $ModulePath -Force

    # Verify installation
    if (Get-Module -ListAvailable -Name $ModuleName) {
      Write-Output "Module $ModuleName installed successfully"
      return $true
    }
    else {
      Write-Error "Module $ModuleName installation failed"
      return $false
    }
  }
  catch {
    Write-Error "Error installing module $ModuleName`: $($_.Exception.Message)"
    return $false
  }
}

#endregion

#region OpenSSH Installation Functions

Function Get-OpenSSHInstallationInfo {
  <#
  .SYNOPSIS
      Gets the current installation status of OpenSSH Client and Server.
  .DESCRIPTION
      Queries Windows capabilities to determine if OpenSSH Client and/or Server are installed.
  #>
  [CmdletBinding()]
  [OutputType([hashtable])]
  param()

  $openSSHServer = Get-WindowsCapability -Online | Where-Object { $_.name -like "OpenSSH.Server*" }
  $openSSHClient = Get-WindowsCapability -Online | Where-Object { $_.name -like "OpenSSH.Client*" }

  # Set default values if needed
  if ($null -eq $openSSHServer) {
    $openSSHServer = [PSCustomObject]@{
      Name  = "OpenSSH.Server~~~~0.0.1.0"
      State = "NotPresent"
    }
  }

  if ($null -eq $openSSHClient) {
    $openSSHClient = [PSCustomObject]@{
      Name  = "OpenSSH.Client~~~~0.0.1.0"
      State = "NotPresent"
    }
  }

  return @{
    Client = $openSSHClient.State
    Server = $openSSHServer.State
  }
}

Function Install-OpenSSHClient {
  <#
  .SYNOPSIS
      Installs the OpenSSH Client on Windows.
  .DESCRIPTION
      Uses Windows capabilities to install the OpenSSH Client feature.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param()

  $activity = Start-DTMSActivity `
    -Name 'OpenSSH Client installation' `
    -Intent 'Install the Windows OpenSSH Client capability'
  if ($PSCmdlet.ShouldProcess("OpenSSH.Client~~~~0.0.1.0", "Install Windows Capability")) {
    try {
      Add-WindowsCapability -Online -Name "OpenSSH.Client~~~~0.0.1.0" -ErrorAction Stop
      Complete-DTMSActivity -Activity $activity -Status 'OpenSSH Client was installed.'
      Write-Output "OpenSSH Client installed successfully"
      return $true
    }
    catch {
      Complete-DTMSActivity -Activity $activity -Status $_.Exception.Message -Failed
      Write-Error "Failed to install OpenSSH Client: $($_.Exception.Message)"
      return $false
    }
  }

  Complete-DTMSActivity -Activity $activity -Status 'OpenSSH Client installation was not started.'
  return $false
}

Function Install-OpenSSHServer {
  <#
  .SYNOPSIS
      Installs the OpenSSH Server on Windows.
  .DESCRIPTION
      Uses Windows capabilities to install the OpenSSH Server feature.
  .PARAMETER Source
      Optional source path for local installation package.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $false)]
    [string]$source,
    [Parameter(Mandatory = $false)]
    [string]$computerName = $env:COMPUTERNAME
  )

  $activity = Start-DTMSActivity `
    -Name 'OpenSSH Server installation' `
    -Intent "Install and configure the Windows OpenSSH Server capability" `
    -Target $computerName
  if ($PSCmdlet.ShouldProcess("OpenSSH.Server~~~~0.0.1.0", "Install Windows Capability")) {
    try {
      if ($source) {
        $sourcefile = Get-Item -path $source #-ErrorAction stop
        Test-Path -Path ($sourceFile.FullName) #-ErrorAction Stop
        $sourceName = $sourceFile.Name
        $sourcePath = $sourceFile.FullName
        $session = New-PSSession -ComputerName $computerName
        Copy-Item -Path $sourcePath -Destination $env:TEMP -ToSession $session
        $psExecCommand = Get-Command -Name 'psexec.exe' -CommandType Application -ErrorAction Stop
        & $psExecCommand.Source \\$computername -s -accepteula powershell -c Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -Source "$env:temp\$Sourcename" -ErrorAction Stop

        Invoke-Command -Session $session  -ScriptBlock {
          $rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
          if ($null -ne $rule) {
            $rule | Remove-NetFirewallRule
          }
          New-NetFirewallRule `
            -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Protocol TCP `
            -LocalPort 22 `
            -Action Allow `
            -Profile Domain, Private, Public `
            -Enabled True `
            -ErrorAction SilentlyContinue


          Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
          Start-Service sshd -ErrorAction SilentlyContinue
        }
      }
      else {
        $psExecCommand = Get-Command -Name 'psexec.exe' -CommandType Application -ErrorAction Stop
        & $psExecCommand.Source \\$computername -s -accepteula powershell -c Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction Stop
        Invoke-Command -ComputerName $computerName  -scriptBlock {
          New-NetFirewallRule `
            -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Protocol TCP `
            -LocalPort 22 `
            -Action Allow `
            -Profile Domain, Private, Public `
            -Enabled True `
            -ErrorAction SilentlyContinue

          Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
          Start-Service sshd -ErrorAction SilentlyContinue
        }
        Complete-DTMSActivity -Activity $activity -Status 'OpenSSH Server was installed and configured.'
        Write-Output "OpenSSH Server installed successfully"
        return $true
      }
    }
    catch {
      Complete-DTMSActivity -Activity $activity -Status $_.Exception.Message -Failed
      if ($Source) {
        Write-Error "Failed to install OpenSSH Server from source $Source`: $($_.Exception.Message)"
        Write-Error "Failed to install OpenSSH Server: $($_.Exception.Message)"
        return $false

      }
      else {
        Write-Warning "Failed to install OpenSSH Server via Windows Capability. Attempting to use local cab installation..."
        Write-Error "Failed to install OpenSSH Server: $($_.Exception.Message)"
        return $false
      }
    }
  }
  Complete-DTMSActivity -Activity $activity -Status 'OpenSSH Server installation was not started.'
  return $false
}

Function Uninstall-OpenSSHClient {
  <#
  .SYNOPSIS
      Uninstalls the OpenSSH Client from Windows.
  .DESCRIPTION
      Uses Windows capabilities to remove the OpenSSH Client feature.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param()

  $info = Get-OpenSSHInstallationInfo
  if ($info.Client -eq "NotPresent") {
    Write-Output "OpenSSH Client is not installed"
    return $true
  }

  if ($PSCmdlet.ShouldProcess("OpenSSH.Client~~~~0.0.1.0", "Remove Windows Capability")) {
    try {
      Remove-WindowsCapability -Online -Name "OpenSSH.Client~~~~0.0.1.0" -ErrorAction Stop
      Write-Output "OpenSSH Client uninstalled successfully"
      return $true
    }
    catch {
      Write-Error "Failed to uninstall OpenSSH Client: $($_.Exception.Message)"
      return $false
    }
  }

  return $false
}

Function Uninstall-OpenSSHServer {
  <#
  .SYNOPSIS
      Uninstalls the OpenSSH Server from Windows.
  .DESCRIPTION
      Uses Windows capabilities to remove the OpenSSH Server feature.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param()

  $info = Get-OpenSSHInstallationInfo
  if ($info.Server -eq "NotPresent") {
    Write-Output "OpenSSH Server is not installed"
    return $true
  }

  if ($PSCmdlet.ShouldProcess("OpenSSH.Server~~~~0.0.1.0", "Remove Windows Capability")) {
    try {
      Remove-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction Stop
      Write-Output "OpenSSH Server uninstalled successfully"
      return $true
    }
    catch {
      Write-Error "Failed to uninstall OpenSSH Server: $($_.Exception.Message)"
      return $false
    }
  }

  return $false
}

Function Install-OpenSSH {
  <#
  .SYNOPSIS
      Comprehensive OpenSSH installation function.
  .DESCRIPTION
      Installs OpenSSH Client, Server, or both based on parameters.
  .PARAMETER Client
      Install OpenSSH Client.
  .PARAMETER Server
      Install OpenSSH Server.
  .PARAMETER All
      Install both Client and Server.
  .PARAMETER Uninstall
      Uninstall instead of install.
  .PARAMETER Source
      Source path for installation packages.
  .PARAMETER Force
      Force installation (requires administrator privileges).
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $false)]
    [switch]$Client,
    [Parameter(Mandatory = $false)]
    [switch]$Server,
    [Parameter(Mandatory = $false)]
    [switch]$All,
    [Parameter(Mandatory = $false)]
    [switch]$Uninstall,
    [Parameter(Mandatory = $false)]
    [string]$Source,
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    [Parameter(Mandatory = $false)]
    [switch]$Info
  )

  $activity = Start-DTMSActivity `
    -Name 'OpenSSH management' `
    -Intent 'Inspect, install, or remove the requested Windows OpenSSH capabilities'
  $activityFailed = $false

  # Check for administrator privileges
  if ($Force -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Complete-DTMSActivity `
      -Activity $activity `
      -Status 'Administrator privileges are required.' `
      -Failed
    Write-Error "Administrator privileges required for OpenSSH installation"
    return $false
  }

  try {
    # If Info was requested, display the current state
    if ($Info) {
      $info = Get-OpenSSHInstallationInfo
      Write-Information "OpenSSH Client: $($info.Client)"
      Write-Information "OpenSSH Server: $($info.Server)"
      return $info
    }

    if ($Uninstall) {
      if ($Client -and (-not $Server)) {
        return Uninstall-OpenSSHClient
      }
      elseif ($Server -and (-not $Client)) {
        return Uninstall-OpenSSHServer
      }
      elseif (($Client -and $Server) -or $All) {
        $clientResult = Uninstall-OpenSSHClient
        $serverResult = Uninstall-OpenSSHServer
        return ($clientResult -and $serverResult)
      }
      else {
        Write-Error "Please specify -Client, -Server, or -All with -Uninstall"
        return $false
      }
    }
    else {
      if ($Client -and (-not $Server)) {
        return Install-OpenSSHClient
      }
      elseif ($Server -and (-not $Client)) {
        return Install-OpenSSHServer -Source $Source
      }
      elseif (($Client -and $Server) -or $All) {
        $clientResult = Install-OpenSSHClient
        $serverResult = Install-OpenSSHServer -Source $Source
        return ($clientResult -and $serverResult)
      }
      else {
        # Show current status if no action specified
        $info = Get-OpenSSHInstallationInfo
        Write-Output "OpenSSH Client: $($info.Client)"
        Write-Output "OpenSSH Server: $($info.Server)"
        return $true
      }
    }
  }
  catch {
    $activityFailed = $true
    Write-Error "Error during OpenSSH operation: $($_.Exception.Message)"
    return $false
  }
  finally {
    Complete-DTMSActivity `
      -Activity $activity `
      -Status $(if ($activityFailed) {
        'OpenSSH management failed.'
      } else {
        'OpenSSH management finished.'
      }) `
      -Failed:$activityFailed
  }
}
#endregion

#region Dependency Management Functions

Function Install-PsExecDependency {
  <#
  .SYNOPSIS
      Downloads and installs PsExec from Microsoft Sysinternals.
  .DESCRIPTION
      Downloads PsExec.exe from the official Microsoft Sysinternals website and installs it to a specified location.
  .PARAMETER InstallPath
      Directory to install PsExec. Defaults to $env:ProgramFiles\SysInternals
  .PARAMETER AddToPath
      Add the installation directory to the system PATH environment variable.
  .PARAMETER Force
      Overwrite existing PsExec installation.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "$env:ProgramFiles\SysInternals",
    [Parameter(Mandatory = $false)]
    [switch]$AddToPath,
    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  # Check if PsExec is already available
  if (-not $Force) {
    try {
      $null = Get-Command psexec.exe -ErrorAction Stop
      Write-Output "PsExec is already available in PATH"
      return $true
    }
    catch {
      Write-Verbose "PsExec is not currently available: $($_.Exception.Message)"
    }
  }

  # Check for administrator privileges
  if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Administrator privileges required to install PsExec"
    return $false
  }

  $psExecPath = Join-Path $InstallPath "psexec.exe"
  $downloadUrl = "https://live.sysinternals.com/psexec.exe"

  if ($PSCmdlet.ShouldProcess($InstallPath, "Download and install PsExec")) {
    try {
      # Create installation directory if it doesn't exist
      if (-not (Test-Path -Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Verbose "Created directory: $InstallPath"
      }

      # Check if PsExec already exists
      if ((Test-Path -Path $psExecPath) -and -not $Force) {
        Write-Output "PsExec already exists at $psExecPath"

        # Still check if we need to add to PATH
        if ($AddToPath) {
          Add-DirectoryToPath -DirectoryPath $InstallPath
        }
        return $true
      }

      Write-Verbose "Downloading PsExec from $downloadUrl"

      # Download PsExec using Invoke-WebRequest
      $webClient = New-Object System.Net.WebClient
      $webClient.DownloadFile($downloadUrl, $psExecPath)

      # Verify download
      if (-not (Test-Path -Path $psExecPath)) {
        throw "Failed to download PsExec to $psExecPath"
      }

      # Verify it's a valid executable
      $fileInfo = Get-Item $psExecPath
      if ($fileInfo.Length -lt 1KB) {
        throw "Downloaded file appears to be invalid (too small)"
      }

      Write-Output "PsExec downloaded successfully to $psExecPath"

      # Add to PATH if requested
      if ($AddToPath) {
        Add-DirectoryToPath -DirectoryPath $InstallPath
      }

      # Test the installation
      try {
        $version = & $psExecPath /? 2>&1 | Select-Object -First 1
        Write-Verbose "PsExec version info: $version"
      }
      catch {
        Write-Warning "PsExec was downloaded but may not be working correctly: $($_.Exception.Message)"
      }

      return $true
    }
    catch {
      Write-Error "Failed to install PsExec: $($_.Exception.Message)"
      return $false
    }
  }

  return $false
}
Function Add-DirectoryToPath {
  <#
  .SYNOPSIS
      Adds a directory to the system PATH environment variable.
  .DESCRIPTION
      Adds a directory to the system PATH if it's not already present.
  .PARAMETER DirectoryPath
      The directory path to add to PATH.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$DirectoryPath
  )

  # Get current PATH
  $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

  # Check if directory is already in PATH
  $pathEntries = $currentPath -split ';'
  $normalizedDir = $DirectoryPath.TrimEnd('\')

  $alreadyInPath = $pathEntries | Where-Object {
    $_.TrimEnd('\') -eq $normalizedDir
  }

  if ($alreadyInPath) {
    Write-Verbose "Directory $DirectoryPath is already in system PATH"
    return $true
  }

  if ($PSCmdlet.ShouldProcess("System PATH", "Add directory $DirectoryPath")) {
    try {
      $newPath = $currentPath + ";" + $DirectoryPath
      [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")

      # Also update current session PATH
      $env:PATH = $env:PATH + ";" + $DirectoryPath

      Write-Output "Added $DirectoryPath to system PATH"
      Write-Warning "You may need to restart your PowerShell session for PATH changes to take effect"
      return $true
    }
    catch {
      Write-Error "Failed to add directory to PATH: $($_.Exception.Message)"
      return $false
    }
  }

  return $false
}
Function Test-PsExecAvailability {
  <#
  .SYNOPSIS
      Tests if PsExec is available and working.
  .DESCRIPTION
      Checks if PsExec can be found and executed properly.
  .PARAMETER InstallIfMissing
      Automatically install PsExec if it's not found.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)]
    [switch]$InstallIfMissing
  )

  try {
    # Try to find PsExec
    $psExecCommand = Get-Command psexec.exe -ErrorAction Stop

    # Test if it can run
    $null = & $psExecCommand.Source /? 2>$null

    Write-Verbose "PsExec is available at: $($psExecCommand.Source)"
    return $true
  }
  catch {
    Write-Verbose "PsExec not found or not working: $($_.Exception.Message)"

    if ($InstallIfMissing) {
      Write-Output "PsExec not found. Attempting to install..."
      return Install-PsExecDependency -AddToPath
    }

    return $false
  }
}
Function Install-ModuleDependencies {
  <#
  .SYNOPSIS
      Installs all required dependencies for the SSH module to function.
  .DESCRIPTION
      Checks and installs missing PowerShell modules required by the SSH module.
  .PARAMETER Force
      Force installation of modules, overwriting any existing versions.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Preserve the exported public command name for compatibility.')]
  param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  $activity = Start-DTMSActivity `
    -Name 'OpenSSH module dependencies' `
    -Intent 'Inspect and install the required PowerShell modules'
  $requiredModules = @(
    @{ Name = "Posh-SSH"; MinimumVersion = "2.0.0" },
    @{ Name = "SshNet"; MinimumVersion = "2016.1.0" }
  )

  foreach ($module in $requiredModules) {
    $moduleName = $module.Name
    $moduleVersion = $module.MinimumVersion
    Update-DTMSActivity `
      -Activity $activity `
      -Status "Checking $moduleName $moduleVersion or later." `
      -ForceHeartbeat

    try {
      # Check if module is already installed
      $installedModule = Get-Module -ListAvailable -Name $moduleName | Where-Object { $_.Version -ge [Version]$moduleVersion }

      if ($null -eq $installedModule -or $Force) {
        Write-Output "Installing/updating $moduleName (minimum required version: $moduleVersion)..."

        # Install or update the module
        Install-Module -Name $moduleName -MinimumVersion $moduleVersion -Force -Scope CurrentUser -ErrorAction Stop

        Write-Output "$moduleName installed/updated successfully"
      }
      else {
        Write-Output "$moduleName is already installed (version $($installedModule.Version))"
      }
    }
    catch {
      Write-Error "Failed to install $moduleName`: $($_.Exception.Message)"
    }
  }

  # Special handling for Posh-SSH module to ensure it's imported
  try {
    Import-Module -Name "Posh-SSH" -ErrorAction Stop
    Write-Output "Posh-SSH module imported successfully"
  }
  catch {
    Write-Error "Failed to import Posh-SSH module: $($_.Exception.Message)"
  }
  Complete-DTMSActivity `
    -Activity $activity `
    -Status 'Dependency inspection and installation finished.'
}
Function Initialize-SSHUtilities {
  <#
  .SYNOPSIS
      Initializes the SSH Utilities module with all dependencies.
  .DESCRIPTION
      Sets up the SSH Utilities module by installing all required dependencies
      and configuring the environment for optimal functionality.
  .PARAMETER InstallPsExec
      Install PsExec from Microsoft Sysinternals.
  .PARAMETER InstallPowerShellModules
      Install required PowerShell modules like Posh-SSH.
  .PARAMETER AddToPath
      Add installed tools to the system PATH.
  .PARAMETER Force
      Force installation even if dependencies already exist.
  #>
  [CmdletBinding(SupportsShouldProcess = $true)]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Preserve the existing command name for compatibility.')]
  param(
    [Parameter(Mandatory = $false)]
    [bool]$InstallPsExec = $true,
    [Parameter(Mandatory = $false)]
    [bool]$InstallPowerShellModules = $true,
    [Parameter(Mandatory = $false)]
    [bool]$AddToPath = $true,
    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  Write-Output "Initializing SSH Utilities module..."

  $results = @{}

  if ($InstallPsExec) {
    Write-Output "Installing PsExec dependency..."
    $results.PsExec = Install-PsExecDependency -AddToPath:$AddToPath -Force:$Force
  }

  if ($InstallPowerShellModules) {
    Write-Output "Installing PowerShell module dependencies..."
    $results.PowerShellModules = Install-ModuleDependencies -Force:$Force
  }

  # Display results
  Write-Output "`nInitialization Results:"
  if ($results.ContainsKey('PsExec')) {
    Write-Output "PsExec: $(if ($results.PsExec) { 'Success' } else { 'Failed' })"
  }
  if ($results.ContainsKey('PowerShellModules')) {
    Write-Output "PowerShell Modules: $(if ($results.PowerShellModules) { 'Success' } else { 'Failed' })"
  }

  $allSuccess = $results.Values | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count

  if ($allSuccess -eq 0) {
    Write-Output "`nSSH Utilities module is ready to use!"
    return $true
  }
  else {
    Write-Warning "Some dependencies failed to install. Check the output above for details."
    return $false
  }
}
Function Get-SSHUtilitiesReadiness {
    <#
    .SYNOPSIS
        Reports the availability of optional SSHUtilities capabilities.
    .DESCRIPTION
        Performs read-only local checks for OpenSSH, PsExec, and optional
        PowerShell dependencies. Missing optional capabilities do not prevent
        unrelated SSHUtilities commands from being used.
    #>
    [CmdletBinding()]
    param()

    $checks = @(
      @{
        Capability = 'OpenSSHClient'
        Required = $true
        Command = 'ssh.exe'
        Remediation = 'Install-OpenSSHClient'
      }
      @{
        Capability = 'SecureCopyTransport'
        Required = $false
        Command = 'scp.exe'
        Remediation = 'Install-OpenSSHClient'
      }
      @{
        Capability = 'PsExec'
        Required = $false
        Command = 'psexec.exe'
        Remediation = 'Install-PsExecDependency'
      }
    )
    foreach ($check in $checks) {
      $available = $null -ne (Get-Command $check.Command -ErrorAction SilentlyContinue)
      $parameters = @{
        Module = 'DTMS.OpenSSH'
        Capability = $check.Capability
        Status = if ($available) { 'Ready' } else { 'NotConfigured' }
        Required = [bool]$check.Required
        Message = if ($available) {
          "$($check.Command) is available."
        } else {
          "$($check.Command) was not found."
        }
        RemediationCommand = if ($available) { $null } else { $check.Remediation }
      }
      if (Get-Command New-DurableOperationReadinessResult -ErrorAction SilentlyContinue) {
        New-DurableOperationReadinessResult @parameters
      }
      else {
        [pscustomobject]$parameters
      }
    }

    $poshSsh = @(Get-Module -ListAvailable -Name 'Posh-SSH' -ErrorAction SilentlyContinue)
    $poshSshParameters = @{
      Module = 'DTMS.OpenSSH'
      Capability = 'PoshSSH'
      Status = if ($poshSsh.Count -gt 0) { 'Ready' } else { 'NotConfigured' }
      Required = $false
      Message = if ($poshSsh.Count -gt 0) {
        "Posh-SSH $($poshSsh[0].Version) is available."
      } else {
        'The optional Posh-SSH module was not found.'
      }
      RemediationCommand = if ($poshSsh.Count -gt 0) {
        $null
      } else {
        'Install-PoshSSHModule'
      }
    }
    if (Get-Command New-DurableOperationReadinessResult -ErrorAction SilentlyContinue) {
      New-DurableOperationReadinessResult @poshSshParameters
      New-DurableOperationReadinessResult `
        -Module DTMS.OpenSSH `
        -Capability DurableExecution `
        -Status Ready `
        -Required $false `
        -Message 'DTMS.Runway durable scheduled-task execution is available.'
    }
    else {
      [pscustomobject]$poshSshParameters
    }
    if (Get-Command Get-DurableTransferReadiness -ErrorAction SilentlyContinue) {
      Get-DurableTransferReadiness
    }
}

Function Start-SSHUtilitiesOperation {
    <#
    .SYNOPSIS
        Starts a supported SSHUtilities action as a durable scheduled operation.
    .DESCRIPTION
        Creates a declarative DTMS.Runway operation for OpenSSH installation or
        administrator-key distribution. Interactive proxy commands remain
        foreground operations and are not supported by this command.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
      [Parameter(Mandatory)]
      [ValidateSet('InstallOpenSSHClient', 'InstallOpenSSHServer', 'SetAdminAuthKeys')]
      [string]$Operation,

      [hashtable]$Parameter = @{},

      [string]$OperationRoot,

      [pscredential]$ExecutionCredential,

      [string]$ExecutionAccount = 'SYSTEM'
    )

    $activity = Start-DTMSActivity `
      -Name 'Durable OpenSSH operation' `
      -Intent "Validate, package, and schedule '$Operation'"
    if (-not (Get-Command Start-DurableOperation -ErrorAction SilentlyContinue)) {
      throw 'DTMS.Runway is required for durable SSHUtilities operations.'
    }
    if ($Operation -eq 'SetAdminAuthKeys' -and
        -not $ExecutionCredential -and
        $ExecutionAccount -eq 'SYSTEM') {
      throw 'SetAdminAuthKeys requires an execution credential or network-capable service account.'
    }
    $handlerPath = Join-Path $PSScriptRoot 'DTMS.OpenSSH.RunwayHandler.psm1'
    $definition = New-DurableOperationDefinition `
      -OperationType "DTMS.OpenSSH.$Operation" `
      -HandlerModulePath $handlerPath `
      -HandlerCommand Invoke-SSHUtilitiesRunwayHandler `
      -Payload @{
        Operation = $Operation
        Parameter = $Parameter
      } `
      -Metadata @{
        Module = 'DTMS.OpenSSH'
        Operation = $Operation
      }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "start durable SSHUtilities operation '$Operation'")) {
      Complete-DTMSActivity -Activity $activity -Status 'The durable OpenSSH operation was not started.'
      return
    }
    $startParameters = @{
      Definition = $definition
      ExecutionAccount = $ExecutionAccount
      Confirm = $false
    }
    if ($OperationRoot) {
      $startParameters.OperationRoot = $OperationRoot
    }
    if ($ExecutionCredential) {
      $startParameters.ExecutionCredential = $ExecutionCredential
    }
    $result = Start-DurableOperation @startParameters
    Complete-DTMSActivity -Activity $activity -Status "Durable operation '$Operation' was launched."
    $result
}

Function Invoke-SSHUtilitiesModuleInitialization {
  [CmdletBinding()]
  param(
    [switch]$AutoInstallDependencies
  )

  Write-Verbose "Initializing SSH Utilities module..."

  # Check for PsExec availability
  $psExecAvailable = Test-PsExecAvailability

  if (-not $psExecAvailable) {
    if ($AutoInstallDependencies) {
      Write-Warning "PsExec not found. Installing automatically..."
      try {
        Install-PsExecDependency -AddToPath
        Write-Output "PsExec installed successfully"
      }
      catch {
        Write-Warning "Failed to install PsExec automatically: $($_.Exception.Message)"
        Write-Warning "Some features requiring PsExec may not work. Use Install-ModuleDependencies to install manually."
      }
    }
    else {
      Write-Warning "PsExec not found. Some features may not work properly."
      Write-Warning "Run 'Install-ModuleDependencies' or 'Install-PsExecDependency' to install required dependencies."
    }
  }

  $script:ModuleInitialized = $true
  Write-Verbose "SSH Utilities module initialization complete"
}

#endregion

function Initialize-SSHTransferHost {
  <#
  .SYNOPSIS
      Prepares a Windows host for key-authenticated durable SCP transfers.
  .DESCRIPTION
      Installs the Windows OpenSSH client and server capabilities, configures
      sshd and its firewall rule, starts BITS, and optionally installs an
      administrator authorized key or a private key for a durable worker.
      All changes occur only when explicitly requested.
  .PARAMETER ComputerName
      One or more Windows hosts to prepare through PowerShell remoting.
  .PARAMETER AuthorizedKey
      OpenSSH public key text added to administrators_authorized_keys.
  .PARAMETER PrivateKeyContent
      OpenSSH private key text installed for a target-host durable worker.
  .PARAMETER PrivateKeyPath
      Destination path for PrivateKeyContent on the remote host.
  .PARAMETER TransferAccount
      Domain gMSA or service account granted read access to PrivateKeyPath.
  .PARAMETER OpenSSHServerCabPath
      Local OpenSSH Server capability CAB to use when present. When the file
      is absent, installation uses the host's configured capability source.
  .EXAMPLE
      Initialize-SSHTransferHost -ComputerName hv01 -AuthorizedKey $publicKey
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'The Invoke-Command block declares values in param() and receives them through ArgumentList.'
  )]
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('HostName', 'DNSHostName')]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [ValidateNotNullOrEmpty()]
    [string]$AuthorizedKey,

    [ValidateNotNullOrEmpty()]
    [string]$PrivateKeyContent,

    [ValidateNotNullOrEmpty()]
    [string]$PrivateKeyPath = 'C:\ProgramData\DTMS\SSH\id_ed25519',

    [ValidateNotNullOrEmpty()]
    [string]$TransferAccount,

    [ValidateNotNullOrEmpty()]
    [string]$OpenSSHServerCabPath =
      'C:\temp\OpenSSH-Server-Package~31bf3856ad364e35~amd64~~.cab'
  )

  begin {
    $activity = Start-DTMSActivity `
      -Name 'OpenSSH transfer host preparation' `
      -Intent 'Install OpenSSH, configure sshd and BITS, and deploy transfer keys'
  }
  process {
    foreach ($computer in $ComputerName) {
      Update-DTMSActivity `
        -Activity $activity `
        -Status "Preparing $computer." `
        -ForceHeartbeat
      if ($PrivateKeyContent -and -not $TransferAccount) {
        throw 'TransferAccount is required when installing private key content.'
      }
      if (-not $PSCmdlet.ShouldProcess(
        $computer,
        'install and configure OpenSSH transfer prerequisites'
      )) {
        continue
      }

      Invoke-Command -ComputerName $computer -ArgumentList @(
        $AuthorizedKey,
        $PrivateKeyContent,
        $PrivateKeyPath,
        $TransferAccount,
        $OpenSSHServerCabPath
      ) -ErrorAction Stop -ScriptBlock {
        param(
          $PublicKey,
          $PrivateKey,
          $RemotePrivateKeyPath,
          $WorkerAccount,
          $ServerCabPath
        )

        $capabilityNames = @(
          'OpenSSH.Client~~~~0.0.1.0'
          'OpenSSH.Server~~~~0.0.1.0'
        )
        foreach ($capabilityName in $capabilityNames) {
          $capability = Get-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop
          if ($capability.State -ne 'Installed') {
            if ($capabilityName -like 'OpenSSH.Server*' -and
              (Test-Path -LiteralPath $ServerCabPath -PathType Leaf)) {
              Add-WindowsCapability `
                -Online `
                -Name $capabilityName `
                -Source (Split-Path -Path $ServerCabPath -Parent) `
                -LimitAccess `
                -ErrorAction Stop | Out-Null
            } else {
              Add-WindowsCapability `
                -Online `
                -Name $capabilityName `
                -ErrorAction Stop | Out-Null
            }
          }
        }

        Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
        Start-Service -Name sshd -ErrorAction Stop
        $firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
          New-NetFirewallRule `
            -Name 'OpenSSH-Server-In-TCP' `
            -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 `
            -ErrorAction Stop | Out-Null
        } else {
          Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -ErrorAction Stop
        }

        Set-Service -Name BITS -StartupType Manual -ErrorAction Stop
        Start-Service -Name BITS -ErrorAction Stop

        if ($PublicKey) {
          $sshRoot = Join-Path $env:ProgramData 'ssh'
          $authorizedKeysPath = Join-Path $sshRoot 'administrators_authorized_keys'
          New-Item -Path $sshRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
          $existingKeys = if (Test-Path -LiteralPath $authorizedKeysPath -PathType Leaf) {
            @(Get-Content -LiteralPath $authorizedKeysPath -ErrorAction Stop)
          } else {
            @()
          }
          $normalizedKey = $PublicKey.Trim()
          if ($normalizedKey -notin $existingKeys) {
            Add-Content -LiteralPath $authorizedKeysPath -Value $normalizedKey -Encoding UTF8 -ErrorAction Stop
          }
          & icacls.exe $authorizedKeysPath /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null
          if ($LASTEXITCODE -ne 0) {
            throw "icacls failed for '$authorizedKeysPath' with exit code $LASTEXITCODE."
          }
        }

        if ($PrivateKey) {
          $privateKeyDirectory = Split-Path -Path $RemotePrivateKeyPath -Parent
          New-Item -Path $privateKeyDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
          [IO.File]::WriteAllText(
            $RemotePrivateKeyPath,
            $PrivateKey.TrimEnd() + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
          )
          & icacls.exe $RemotePrivateKeyPath /inheritance:r /grant:r `
            '*S-1-5-32-544:F' '*S-1-5-18:F' "$WorkerAccount`:R" | Out-Null
          if ($LASTEXITCODE -ne 0) {
            throw "icacls failed for '$RemotePrivateKeyPath' with exit code $LASTEXITCODE."
          }
        }

        [pscustomobject]@{
          ComputerName = $env:COMPUTERNAME
          OpenSSHClient = (Get-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0').State
          OpenSSHServer = (Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0').State
          OpenSSHServerCabPath = if (Test-Path -LiteralPath $ServerCabPath -PathType Leaf) {
            $ServerCabPath
          } else {
            $null
          }
          SshdStatus = (Get-Service -Name sshd).Status
          BitsStatus = (Get-Service -Name BITS).Status
          AuthorizedKeyInstalled = [bool]$PublicKey
          PrivateKeyInstalled = [bool]$PrivateKey
          PrivateKeyPath = if ($PrivateKey) { $RemotePrivateKeyPath } else { $null }
        }
      }
    }
    end {
      Complete-DTMSActivity `
        -Activity $activity `
        -Status 'OpenSSH transfer-host preparation completed.'
    }
  }
}

# Module initialization script
# This runs automatically when the module is imported

Write-Verbose "Initializing SSH Utilities module..."

#region Module Initialization
# Check and optionally install dependencies when module loads
$script:ModuleInitialized = $false


$effectiveStartupMode = if (-not [string]::IsNullOrWhiteSpace($env:SSHUTILITIES_STARTUP_MODE)) {
  $env:SSHUTILITIES_STARTUP_MODE
}
else {
  $StartupMode
}
if ($effectiveStartupMode -notin @('Notify', 'Quiet', 'Prompt', 'Initialize')) {
  throw "SSHUTILITIES_STARTUP_MODE '$effectiveStartupMode' is invalid. Use Notify, Quiet, Prompt, or Initialize."
}
$readiness = @(Get-SSHUtilitiesReadiness)
$missingCapabilities = @($readiness | Where-Object Status -ne 'Ready')
if ($effectiveStartupMode -eq 'Initialize') {
  $initializeParameters = @{
    InstallPsExec = if ($StartupOptions.ContainsKey('InstallPsExec')) {
      [bool]$StartupOptions.InstallPsExec
    } else {
      $true
    }
    InstallPowerShellModules = if ($StartupOptions.ContainsKey('InstallPowerShellModules')) {
      [bool]$StartupOptions.InstallPowerShellModules
    } else {
      $true
    }
    AddToPath = if ($StartupOptions.ContainsKey('AddToPath')) {
      [bool]$StartupOptions.AddToPath
    } else {
      $true
    }
  }
  Initialize-SSHUtilities @initializeParameters | Out-Null
  $readiness = @(Get-SSHUtilitiesReadiness)
  $missingCapabilities = @($readiness | Where-Object Status -ne 'Ready')
}
elseif ($effectiveStartupMode -eq 'Prompt' -and $missingCapabilities.Count -gt 0) {
  if ([Environment]::UserInteractive -and $Host.Name -ne 'ServerRemoteHost') {
    $initialize = Read-Host 'SSHUtilities has optional capabilities that are not configured. Initialize them now? [y/N]'
    if ($initialize -match '^(?i)y(?:es)?$') {
      Initialize-SSHUtilities | Out-Null
      $readiness = @(Get-SSHUtilitiesReadiness)
      $missingCapabilities = @($readiness | Where-Object Status -ne 'Ready')
    }
  }
  else {
    Write-Warning 'SSHUtilities Prompt startup mode was requested in a noninteractive session. No setup changes were made.'
  }
}
elseif ($effectiveStartupMode -eq 'Notify' -and $missingCapabilities.Count -gt 0) {
  $recommendations = @($missingCapabilities.RemediationCommand |
    Where-Object { $_ } |
    Sort-Object -Unique)
  Write-Warning @"
SSHUtilities imported with optional capabilities unavailable: $(
  $missingCapabilities.Capability -join ', '
).
No dependencies were installed automatically. Run Get-SSHUtilitiesReadiness for
details. Recommended commands: $($recommendations -join ', ').
"@
}

$psExecAvailable = ($readiness |
  Where-Object Capability -eq 'PsExec').Status -eq 'Ready'
$script:ModuleDependenciesChecked = $true
$script:PsExecAvailable = $psExecAvailable

Write-Verbose "SSH Utilities module initialized"


#endregion
