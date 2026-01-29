# Pedantic

**Modern DSC (Desired State Configuration) management toolkit**

Pedantic is a PowerShell module and toolset for managing DSC resources and configurations across Windows, macOS, and Linux with PowerShell 7.2+. It provides a simplified interface for working with DSC v3, resource caching, remote execution, and dual DSL support for configuration authoring.

## Features

The Pedantic PowerShell module (v0.9.0) provides:

- **DSC Configuration Management** - Apply, test, validate, and export DSC configurations
- **Resource Caching** - Automatic downloading and caching of DSC resources from PowerShell Gallery
- **Remote Execution** - Secure remote DSC operations via SSH and WinRM
- **Dual DSL Support** - Work with both simplified YAML syntax and SudoLang configurations
- **Built-in Resource Mapping** - Pre-configured mappings for 30+ classic DSC resources
- **Ansible Integration** - DSC v3 adapter for Ansible modules (Pedantic.Ansible/Module)
- **Cross-Platform** - PowerShell 7.2+ on Windows, macOS, and Linux
- **Utility Functions** - Text processing helpers like `Get-Head` and `Get-Tail`

### VS Code Extension (Early Development)

The VS Code extension (v0.0.1) includes basic scaffolding for:
- Language Server Protocol (LSP) with syntax diagnostics
- Resource graph visualization
- DSL parsing and code completion

---

## Getting Started

### Installation

```powershell
# Clone the repository
git clone https://github.com/plures/pedantic.git
cd pedantic

# Import the module
Import-Module ./Pedantic.psd1
```

### Quick Start Examples

#### Example 1: Text Utilities

Get the first or last lines of command output:

```powershell
Get-Content file.txt | Get-Head -Count 5
```

Get the last 5 lines of a file:

```powershell
Get-Content file.txt | Get-Tail -Count 5
```

#### Example 2: Resource Management

Initialize the DSC resource cache and ensure required resources are available:

```powershell
# Initialize the installer cache
Initialize-InstallerCache

# Get platform-specific DSC version
Get-LatestDscVersion -Platform "Windows"

# Download a specific DSC resource
Download-DscResource -ResourceType "Microsoft.Windows/Registry" -Version "1.0.0" -Source "PowerShellGallery"

# Ensure multiple resources are available (downloads if needed)
Ensure-DscResourcesAvailable -ResourceTypes @("Microsoft.Windows/Registry", "Microsoft.Windows/File") -Force
```

#### Example 3: Install Go (Golang) with DSC v3

This example demonstrates using DSC v3 with the transitional `RunCommandOnSet` resource to install Go on Windows:

1. **Ensure the required DSC resource is cached:**

```powershell
$resources = @("Microsoft/DSC/Transitional/RunCommandOnSet")
$ensure = Ensure-DscResourcesAvailable -ResourceTypes $resources -Force
if (-not $ensure.AllAvailable) { 
    throw "Required DSC resources are not available: $($ensure.Missing -join ', ')" 
}
```

2. **Create a DSC v3 YAML configuration** (save as `go-install.dsc.yaml`):

```yaml
# Minimal DSC v3 document using a transitional resource to run a PowerShell command on Set
description: Install Go (Golang) if not already installed
resources:
  - name: InstallGolang
    type: Microsoft/DSC/Transitional/RunCommandOnSet
    properties:
      Command: >-
        powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command
        "if (-not (Get-Command go.exe -ErrorAction SilentlyContinue)) {
            $version = '1.22.5';
            $url = "https://go.dev/dl/go$version.windows-amd64.msi";
            $msi = Join-Path $env:TEMP 'go.msi';
            Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing;
            Start-Process msiexec.exe -ArgumentList '/i', $msi, '/qn', '/norestart' -Wait;
          }"
```

3. **Apply the configuration locally:**

```powershell
Import-Module Pedantic

# Run the Set operation (remove -WhatIf to execute for real)
Set-DscConfiguration -DscPath ./go-install.dsc.yaml -WhatIf:$false
```

4. **Remote execution** (optional):

```powershell
Set-DscConfiguration -DscPath ./go-install.dsc.yaml `
  -ComputerName 'server01' `
  -AutoInstallDscResources `
  -ForceUpdateCache
```

**Notes:**
- The MSI installer updates PATH automatically; open a new shell for `go` to be available
- Update `$version` to the desired Go release
- For offline environments, pre-stage the MSI and replace the download URL with a local path

---

## Advanced Usage

### Using Winget DSC Resource (Alternative)

If your environment has the Winget DSC resource available, you can use a declarative approach:

1. **Check for the Winget DSC resource:**

```powershell
$resource = "Microsoft.WinGet.DSC"
Update-DscResourceCache -SpecificResource $resource
```

2. **Create a Winget-based configuration** (`go-install-winget.dsc.yaml`):

```yaml
description: Install Go (Golang) using Winget DSC resource if present
resources:
  - name: InstallGolang
    type: Microsoft.WinGet.DSC/Package
    properties:
      Id: GoLang.Go
      Ensure: Present
      Source: winget
      # Optional: pin a version (if supported in your resource build)
      # Version: "1.22.5"
```

3. **Apply the configuration:**

```powershell
Import-Module Pedantic
Set-DscConfiguration -DscPath ./go-install-winget.dsc.yaml
```

**Notes:**
- Winget requires Windows 11/Server 2022 with Desktop Experience and the App Installer
- For offline or restricted environments, use the transitional approach shown in Example 3

### Using the Ansible Adapter

The Pedantic.Ansible/Module resource enables you to use any Ansible module with DSC semantics. This allows you to target Windows, Linux, and network devices using a unified configuration language.

**Prerequisites:**
- Ansible installed and available in PATH
- Required Ansible collections installed

**Example: Managing files on Linux with ansible.builtin.file**

```yaml
resources:
  - name: Ensure config directory
    type: Pedantic.Ansible/Module
    properties:
      name: config-dir
      module: ansible.builtin.file
      args:
        path: /etc/myapp
        state: directory
        mode: '0755'
      host: localhost
      become: true
      idempotencyMode: native
```

**Example: Network device configuration with cisco.nxos.nxos_vlan**

```yaml
resources:
  - name: Configure VLAN
    type: Pedantic.Ansible/Module
    properties:
      name: vlan-100
      module: cisco.nxos.nxos_vlan
      args:
        vlan_id: 100
        name: production
        state: present
      host: switch-01
      connection:
        type: network_cli
        user: admin
      idempotencyMode: native
```

For more examples and detailed documentation, see:
- [Ansible Adapter README](Resources/Pedantic.Ansible.Module/README.md)
- [Example Configurations](examples/ansible-adapter-examples.yaml)

---

## Module Reference

The module includes 20 exported functions for DSC management. For detailed command documentation:

```powershell
# Get help for a specific command
Get-Help Set-DscConfiguration -Full

# List all available commands
Get-Command -Module Pedantic
```

### Key Functions

- **Configuration Management**: `Set-DscConfiguration`, `Test-DscConfiguration`, `Validate-DscConfiguration`, `Export-DscConfiguration`
- **Resource Management**: `Update-DscResourceCache`, `Ensure-DscResourcesAvailable`, `Get-DscResourcePath`
- **Remote Operations**: `New-SecureRemoteSession`, `Repair-DscInstallation`
- **Utilities**: `Get-Head`, `Get-Tail`, `Invoke-DscHelper`

## Related Projects

Pedantic is part of the [Plures](https://github.com/plures) organization. Related projects include:

- **[PluresDB](https://github.com/plures/pluresdb)** - Decentralized graph database
- **[RuneBook](https://github.com/plures/runebook)** - Interactive canvas environment
- **[Praxis](https://github.com/plures/praxis)** - Full-stack application framework

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Community & Support

- **[GitHub Issues](https://github.com/plures/pedantic/issues)** - Bug reports and feature requests
- **[GitHub Discussions](https://github.com/plures/pedantic/discussions)** - Questions and community support
- **[Plures Organization](https://github.com/plures)** - Explore related projects

## License

MIT License - see [LICENSE](LICENSE) for details.

## Roadmap & Planning

For detailed information about future plans and development roadmap, see:

- [NEXT-STEPS.md](NEXT-STEPS.md) - Current priorities
- [MVP-PLAN.md](MVP-PLAN.md) - MVP development plan
- [RELEASE-1.0-PLAN.md](RELEASE-1.0-PLAN.md) - 1.0 release targets
- [FULL-ROADMAP-PLAN.md](FULL-ROADMAP-PLAN.md) - Long-term vision
- [CHANGELOG.md](CHANGELOG.md) - Version history
