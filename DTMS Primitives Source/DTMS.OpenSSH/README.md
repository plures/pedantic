# DTMS.OpenSSH PowerShell Module

This repository contains a comprehensive PowerShell module for installing and managing OpenSSH on Windows systems, as well as utilities for common SSH operations.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Functions](#functions)
- [Requirements](#requirements)
- [Examples](#examples)
- [Official Microsoft Documentation](#official-microsoft-documentation)
- [Contributing](#contributing)

## Overview

The **SSHUtilities** PowerShell module provides a unified interface for OpenSSH management and SSH operations on Windows. The module combines OpenSSH installation capabilities with advanced SSH utilities including:

- OpenSSH Client and Server installation/management
- SSH configuration and key management  
- SSH tunneling and proxy functionality
- Remote desktop connections through SSH proxies
- PowerShell remoting integration for Windows Server environments

## Installation

### Import the Module

```powershell
# Import the module from the current directory
Import-Module .\DTMS.OpenSSH.psd1

# Or specify the full path
Import-Module "C:\Path\To\DTMS.OpenSSH\DTMS.OpenSSH.psd1"
```

Imports perform read-only capability checks and warn when optional tools are
unavailable. They do not install dependencies automatically. Inspect the
current state with:

```powershell
Get-SSHUtilitiesReadiness
```

Potentially blocking commands announce their intent immediately and use the
adaptive DTMS.Runway activity display. Set `DTMS_FEEDBACK_MODE` to `Adaptive`,
`Animated`, `Concise`, or `Quiet`; scheduled workers should use `Quiet`.

## Workstation controller profiles

Forge can use a jump server as either a remote controller or an SSH tunnel.
Profiles are stored in central DTMS configuration and reference an existing
per-user private key:

```json
{
  "OpenSSH": {
    "ControllerProfiles": {
      "PHX23": {
        "HostName": "PHX23ISUTIL01.USME.GBL",
        "UserName": "usme\\operator",
        "IdentityFile": "C:\\Users\\operator\\.ssh\\id_ed25519",
        "Port": 22
      }
    }
  }
}
```

```powershell
$session = New-DTMSControllerSession -ProfileName PHX23
$tunnel = Start-DTMSWinRMTunnel `
  -ProfileName PHX23 `
  -TargetComputerName BN1ISBURP005
```

DTMS validates and consumes the configured key. It does not generate,
distribute, or persist users' private keys.

When DTMS.Runway is present, supported noninteractive work can be launched as
a durable scheduled operation:

```powershell
Start-SSHUtilitiesOperation `
    -Operation InstallOpenSSHServer `
    -Parameter @{ Source = 'C:\Packages\OpenSSH' }
```

Administrator-key distribution requires a network-capable execution identity:

```powershell
Start-SSHUtilitiesOperation `
    -Operation SetAdminAuthKeys `
    -Parameter @{
        RemoteHost = 'server.example.com'
        keyfile = 'C:\Keys\id_ecdsa'
    } `
    -ExecutionAccount 'CONTOSO\ssh-maintenance$'
```

Interactive RDP and SOCKS proxy commands intentionally remain foreground
operations.

Available startup modes are `Notify` (default), `Quiet`, `Prompt`, and
explicit `Initialize`:

```powershell
Import-Module .\DTMS.OpenSSH.psd1 -ArgumentList 'Quiet'

Import-Module .\DTMS.OpenSSH.psd1 -ArgumentList 'Prompt'

Import-Module .\DTMS.OpenSSH.psd1 -ArgumentList @(
    'Initialize'
    @{
        InstallPsExec = $true
        InstallPowerShellModules = $true
        AddToPath = $true
    }
)
```

For module auto-loading and other cases where import arguments are not
available, set `SSHUTILITIES_STARTUP_MODE` in the process or machine
environment.

### Module Installation Methods

The module supports multiple installation methods for OpenSSH components:

1. Using Windows Capabilities (primary method)
2. Using a local CAB file source
3. Fallback to local package installation

## Functions

The SSHUtilities module provides the following functions:

### OpenSSH Installation Functions

#### Install-OpenSSH
Main function for OpenSSH installation and management.

**Parameters:**
- `-Client` - Install OpenSSH Client
- `-Server` - Install OpenSSH Server  
- `-All` - Install both Client and Server
- `-Uninstall` - Uninstall specified components
- `-Force` - Force installation (requires administrator privileges)
- `-Source` - Path to local CAB files for installation
- `-Info` - Display information about installed OpenSSH components

**Examples:**

```powershell
# Install OpenSSH Client
Install-OpenSSH -Client

# Install OpenSSH Server
Install-OpenSSH -Server

# Install both Client and Server
Install-OpenSSH -All

# Uninstall OpenSSH Client
Install-OpenSSH -Uninstall -Client

# Install from local source
Install-OpenSSH -Server -Source "C:\Path\To\WindowsCABs"

# Display installation status
Install-OpenSSH -Info
```

#### Additional Installation Functions
- `Install-OpenSSHClient` - Install only the OpenSSH Client
- `Install-OpenSSHServer` - Install only the OpenSSH Server
- `Uninstall-OpenSSHClient` - Uninstall the OpenSSH Client
- `Uninstall-OpenSSHServer` - Uninstall the OpenSSH Server
- `Get-OpenSSHInstallationInfo` - Get current installation status

### SSH Configuration and Key Management Functions

#### New-SSHConfig

Creates an SSH config file in the user's `.ssh` directory based on a template file.

```powershell
New-SSHConfig -userSSHConfigPath "$env:USERPROFILE\.ssh\config" -TemplateFile "./my-template.conf"
```

#### Set-AdminAuthKeys

Sets up authorized keys for administrator access on remote Windows servers using PowerShell remoting.

**Parameters:**
- `-RemoteHost` - The remote Windows host to configure (mandatory)
- `-Credential` - PSCredential object for authentication
- `-username` - Username for key generation comments

```powershell
# Basic usage with current user credentials
Set-AdminAuthKeys -RemoteHost "server.example.com"

# With explicit credentials
$cred = Get-Credential
Set-AdminAuthKeys -RemoteHost "server.example.com" -Credential $cred
```

#### Set-KeyPassphrase

Changes the passphrase of an existing SSH private key.

```powershell
Set-KeyPassphrase -PrivateKeyPath "$env:USERPROFILE\.ssh\id_ecdsa"
```

### SSH Tunneling and Proxy Functions

#### Start-RDProxy

Establishes an SSH tunnel to a remote host through a proxy and launches an RDP session.

```powershell
Start-RDProxy -RemoteHost "internal-server.local" -ProxyHost "jump.example.com" -Admin -MultiMon
```

#### Start-DynamicProxy

Creates dynamic SOCKS proxies through SSH for multiple hosts.

```powershell
Start-DynamicProxy -ProxyHosts "jump1.example.com", "jump2.example.com" -StartingPort 8000
```

### Module Management Functions

#### Install-PoshSSHModule

Installs the Posh-SSH module, which is required for some advanced SSH operations.

```powershell
Install-PoshSSHModule -ModulePath "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
```

## Requirements

- Windows 10 (1809+) or Windows Server 2019+
- PowerShell 7.x (primary) or Windows PowerShell 5.1 (compatibility)
- Administrator privileges for installation and server configuration
- Internet access for GitHub fallback installation (optional)
- Azure Artifacts Feed

### Connecting to Azure Artifacts Feed

### Updating the extension

```powershell
az extension add --name azure-devops
```

Connecting to the project

```powershell
az devops configure --defaults organization=https://dev.azure.com/msazuredev project=SFTCloudInfra
```

### Publishing a package

```powershell
 az artifacts universal publish --scope project --feed DTMSTools --name openssh-server-package  --version 1.0.0 --description "OpenSSH-Server Installation Package"  --path
"C:\Users\kbristol\Downloads\OpenSSH-Server-Package.cab"
{- Publishing ..
  "Description": "OpenSSH-Server Installation Package",
  "ManifestId": "3753877C783997F164300484116D35A05511CB761AED752B56A539865682E16201",
  "SuperRootId": "E480027948C597CA58610285CDA25A1ABE18FEFB9366F73595871EB8B48C0CBC02",
  "Version": "1.0.0"
```

## Examples

### Basic Module Usage

```powershell
# Import the DTMS.OpenSSH module
Import-Module .\DTMS.OpenSSH.psd1

# Check current OpenSSH installation status
Install-OpenSSH -Info

# Install OpenSSH Server
Install-OpenSSH -Server

# Set up authorized keys for administrator access
Set-AdminAuthKeys -RemoteHost "server.example.com"
```

### Remote Desktop through SSH Tunnel

```powershell
# Import the DTMS.OpenSSH module
Import-Module .\DTMS.OpenSSH.psd1

# Create SSH config if needed
New-SSHConfig

# Establish RDP connection through SSH tunnel
Start-RDProxy -RemoteHost "internal-server.local" -ProxyHost "bastion.example.com" -Admin -FullScreen
```

### SOCKS Proxy for Secure Browsing

```powershell
# Import the module
Import-Module .\DTMS.OpenSSH.psd1

# Install Posh-SSH module if not already installed
Install-PoshSSHModule

# Start dynamic SOCKS proxies
$sessions = Start-DynamicProxy -ProxyHosts "proxy1.example.com", "proxy2.example.com" -StartingPort 8080

# Configure your browser to use localhost:8080 as a SOCKS proxy
```

### Complete OpenSSH Setup Workflow

```powershell
# Import the module
Import-Module .\DTMS.OpenSSH.psd1

# Install both OpenSSH Client and Server
Install-OpenSSH -All -Force

# Create SSH configuration
New-SSHConfig -TemplateFile "corporate-template.config"

# Set up authorized keys on multiple servers
$servers = @("server01.domain.com", "server02.domain.com", "server03.domain.com")
$cred = Get-Credential
foreach ($server in $servers) {
    Set-AdminAuthKeys -RemoteHost $server -Credential $cred
}
```

## Using SCP for File Transfers

SCP (Secure Copy Protocol) is a network protocol that uses SSH for secure file transfers between hosts. Once you have OpenSSH installed using this module, you can use SCP for copying files and directories.

### Basic SCP Syntax

```
scp [options] source destination
```

### Copying Single Files

#### Local to Remote
```powershell
# Copy a single file to remote host
scp "C:\local\file.txt" user@remotehost:/remote/path/

# Copy with different filename
scp "C:\local\file.txt" user@remotehost:/remote/path/newname.txt

# Copy to user's home directory
scp "C:\local\file.txt" user@remotehost:~/
```

#### Remote to Local
```powershell
# Copy file from remote to local
scp user@remotehost:/remote/path/file.txt "C:\local\"

# Copy with different filename
scp user@remotehost:/remote/path/file.txt "C:\local\newname.txt"
```

### Copying Multiple Files

#### Multiple Specific Files
```powershell
# Copy multiple files to remote directory
scp "C:\local\file1.txt" "C:\local\file2.txt" "C:\local\file3.txt" user@remotehost:/remote/path/

# Using wildcards
scp "C:\local\*.txt" user@remotehost:/remote/path/
scp "C:\local\*.log" user@remotehost:/remote/path/
```

#### From Remote to Local
```powershell
# Copy multiple files from remote
scp user@remotehost:"/remote/path/file1.txt /remote/path/file2.txt" "C:\local\"

# Using wildcards (note: wildcards are expanded on remote host)
scp "user@remotehost:/remote/path/*.txt" "C:\local\"
```

### Copying Entire Directories

#### Recursive Directory Copy
```powershell
# Copy entire directory structure to remote
scp -r "C:\local\directory" user@remotehost:/remote/path/

# Copy directory contents (not the directory itself)
scp -r "C:\local\directory\*" user@remotehost:/remote/path/

# Copy from remote to local
scp -r user@remotehost:/remote/directory "C:\local\"
```

### Common SCP Options

| Option | Description |
|--------|-------------|
| `-r` | Recursively copy directories |
| `-p` | Preserve file timestamps and permissions |
| `-v` | Verbose output (show transfer progress) |
| `-P port` | Specify SSH port (capital P for scp, lowercase p for ssh) |
| `-i keyfile` | Use specific private key file |
| `-C` | Enable compression |
| `-q` | Quiet mode (suppress progress and warnings) |

### Advanced SCP Examples

#### Using SSH Keys
```powershell
# Copy using specific SSH key
scp -i "C:\Users\username\.ssh\id_ecdsa" "C:\local\file.txt" user@remotehost:/remote/path/

# Copy directory with key authentication
scp -r -i "C:\Users\username\.ssh\id_ecdsa" "C:\local\directory" user@remotehost:/remote/path/
```

#### Using Custom SSH Port
```powershell
# Copy to host using non-standard SSH port
scp -P 2222 "C:\local\file.txt" user@remotehost:/remote/path/

# Combine with other options
scp -r -P 2222 -v "C:\local\directory" user@remotehost:/remote/path/
```

#### Copying Through SSH Proxy/Jump Host
```powershell
# Copy through a jump host
scp -o "ProxyJump=jumpuser@jumphost" "C:\local\file.txt" user@finalhost:/remote/path/

# Alternative proxy command syntax
scp -o "ProxyCommand=ssh -W %h:%p jumpuser@jumphost" "C:\local\file.txt" user@finalhost:/remote/path/
```

### SCP with SSH Config

If you've set up SSH config using `New-SSHConfig`, you can reference configured hosts:

```powershell
# Assuming you have a host named "production" in your SSH config
scp "C:\local\file.txt" production:/remote/path/

# Copy directory to configured host
scp -r "C:\local\directory" production:/remote/path/
```

### PowerShell-Specific Tips

#### Handling Paths with Spaces
```powershell
# Use quotes for paths with spaces
scp "C:\Program Files\MyApp\config.txt" user@remotehost:/etc/myapp/

# Escape spaces in remote paths
scp "C:\local\file.txt" "user@remotehost:/remote/path with spaces/"
```

#### Progress Monitoring
```powershell
# Use verbose mode to see transfer progress
scp -v "C:\large-file.iso" user@remotehost:/remote/path/

# For scripting, you might want quiet mode
scp -q "C:\automated\backup.tar" user@backupserver:/backups/
```

#### Batch Operations
```powershell
# Copy multiple directories in a loop
$directories = @("logs", "config", "data")
foreach ($dir in $directories) {
    scp -r "C:\app\$dir" user@remotehost:/backup/app/
}

# Copy files based on date
Get-ChildItem "C:\logs" -Filter "*.log" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } | ForEach-Object {
    scp $_.FullName user@logserver:/logs/recent/
}
```

## Working with Windows SSH Features

### Automated Key-Based Authentication

The `Set-AdminAuthKeys` function helps automate the setup of key-based authentication for administrators on Windows machines running the OpenSSH server. **This function now uses PowerShell remoting (Invoke-Command) instead of SSH**, making it ideal for Windows Server environments where PowerShell remoting is the standard administrative method.

**Key benefits of the PowerShell remoting approach:**
- Uses native Windows authentication and encrypted PowerShell remoting
- More reliable than depending on SSH being configured on target servers
- Better integration with Windows security models
- Clearer error messages and troubleshooting guidance

### Windows Firewall Integration

When installing the OpenSSH server via the module's installation functions, appropriate Windows Firewall rules are automatically created to allow SSH traffic on port 22.

### Service Management

The OpenSSH Server is installed as a Windows service that can be managed through standard service commands:

```powershell
# Start the SSH server service
Start-Service sshd

# Stop the SSH server service
Stop-Service sshd

# Set to start automatically
Set-Service -Name sshd -StartupType 'Automatic'
```

### SSH Keys on Windows

SSH keys in Windows are stored in the user's `.ssh` directory (`%USERPROFILE%\.ssh\`). The utilities in this module help manage these keys and their configuration.

## Official Microsoft Documentation

Our scripts are based on Microsoft's official guidelines and best practices for OpenSSH on Windows. For detailed information, refer to the following Microsoft resources:

### Installation and Setup

- [Install OpenSSH](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=gui) - Official Microsoft guide for installing OpenSSH on Windows.
- [OpenSSH Server Configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_server_configuration) - How to configure the OpenSSH server.
- [OpenSSH Key Management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement) - Managing SSH keys on Windows.

### Authentication and Security

- [OpenSSH Authentication](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_auth_keys) - Guide for setting up key-based authentication.
- [Security Considerations](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_security_considerations) - Security best practices for Windows OpenSSH.

### Windows-Specific Features

- [Windows OpenSSH ](https://learn.microsoft.com/en-us/windows-server/administration/openssh/) - Main landing page for Windows OpenSSH documentation.
- [Windows Server 2025 OpenSSH Support](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=gui&pivots=windows-server-2025) - Specific guidance for Windows Server 2025.

### Known Issues and Troubleshooting

- [OpenSSH Known Issues](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_known_issues) - Common issues and workarounds.
- [Troubleshooting](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=gui&pivots=windows-server-2025#troubleshooting) - Steps to diagnose and fix common problems.

Microsoft's implementation of OpenSSH in Windows follows standard SSH practices while accounting for Windows-specific features and security models. Our PowerShell module extends these capabilities by providing streamlined installation and configuration workflows optimized for Windows Server environments.

## Module Features

- **Unified Interface**: Single module providing all SSH-related functionality
- **PowerShell Integration**: Uses PowerShell remoting for Windows Server management
- **Runtime-compatible**: PowerShell 7.x-first with Windows PowerShell 5.1 compatibility
- **Multiple Installation Methods**: Supports Windows Capabilities, local packages, and fallback methods
- **SAW Environment Support**: Handles Secure Admin Workstation environments appropriately
- **Comprehensive Error Handling**: Detailed error messages and troubleshooting guidance

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
