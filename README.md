# Pedantic • A DSC Ecosystem Hub

**The Ansible Galaxy for Desired State Configuration**

Pedantic is an evolving ecosystem for discovering, sharing, and managing DSC (Desired State Configuration) resources and configurations. Like Ansible Galaxy provides a central hub for Ansible roles and collections, Pedantic aims to become the go-to platform for the DSC community.

## Vision

We're building a comprehensive DSC ecosystem that combines:
- **Resource Discovery & Sharing** - A community hub for DSC configurations and resources
- **Powerful Tooling** - Modern development tools for authoring and managing DSC
- **Cross-Platform Support** - Works on Windows, macOS, and Linux with PowerShell 7+
- **Integration** - Seamless integration with the [Plures](https://github.com/plures) ecosystem of development tools

## What Works Today

### ✅ PowerShell Module (Production-Ready)

The Pedantic PowerShell module is fully functional and ready to use in production environments:

- **Remote DSC Operations** - Execute DSC on remote machines without manual setup
- **Smart Resource Management** - Automatic resource mapping and caching
- **Platform-Aware** - Detects and manages DSC versions across Windows, macOS, and Linux
- **Installer Caching** - Downloads and caches DSC installers for offline use
- **Resource Discovery** - Maps classic DSC resources to PowerShell Gallery modules
- **PowerShell 7+ Compatible** - Modern PowerShell Core support

### 🚧 In Development

- **VS Code Extension** - Rich editing experience with dual DSL support
- **Resource Graph Visualization** - Visual dependency mapping
- **AI-Assisted Configuration** - Intelligent DSC authoring
- **Community Hub** - Central repository for sharing DSC configurations

## Roadmap

### Current Phase: Foundation (Q1 2026)
Building the core infrastructure and establishing the PowerShell module as the foundation.

### Near-Term Goals (Q2-Q3 2026)
- Launch community hub for DSC resource sharing
- Complete VS Code extension with LSP integration
- Establish integration points with Plures ecosystem projects:
  - [PluresDB](https://github.com/plures/pluresdb) - Decentralized resource catalog
  - [RuneBook](https://github.com/plures/runebook) - Interactive DSC workflow development
  - [Praxis](https://github.com/plures/praxis) - Full-stack framework integration

### Long-Term Vision (2026-2027)
- Become the primary DSC resource discovery platform
- Support for community contributions and ratings
- Advanced AI-powered configuration generation
- Enterprise-grade resource management

**Detailed Plans:**
- [MVP Plan](MVP-PLAN.md) - Next phase development
- [1.0 Release Plan](RELEASE-1.0-PLAN.md) - Production release targets
- [Full Roadmap](FULL-ROADMAP-PLAN.md) - Complete vision
- [Next Steps](NEXT-STEPS.md) - Current priorities

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

The PowerShell module provides powerful DSC management capabilities today:

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

---

## Module Reference

For detailed command documentation, use PowerShell's built-in help system:

```powershell
# Get help for a specific command
Get-Help Set-DscConfiguration -Full

# List all available commands
Get-Command -Module Pedantic
```

## Integration with Plures Ecosystem

Pedantic is part of the [Plures](https://github.com/plures) ecosystem, designed to work seamlessly with:

- **[PluresDB](https://github.com/plures/pluresdb)** - Decentralized graph database for sharing DSC resources
- **[RuneBook](https://github.com/plures/runebook)** - Interactive canvas environment for building DSC workflows
- **[Praxis](https://github.com/plures/praxis)** - Full-stack application framework with DSC integration

These integrations will enable:
- Decentralized resource discovery and sharing
- Visual DSC workflow development
- Seamless application deployment with DSC

## Contributing

We welcome contributions! Whether you're:
- Sharing DSC configurations and resources
- Improving the PowerShell module
- Building integrations with other tools
- Enhancing documentation

See our [Contributing Guide](CONTRIBUTING.md) (coming soon) for details.

## Community & Support

- **GitHub Issues** - Bug reports and feature requests
- **Discussions** - Questions and community support
- **Plures Organization** - Explore related projects at [github.com/plures](https://github.com/plures)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Roadmap Documents

For detailed information about our plans and progress:

- **[NEXT-STEPS.md](NEXT-STEPS.md)** - Current priorities and immediate next steps
- **[MVP-PLAN.md](MVP-PLAN.md)** - Next phase development plan
- **[RELEASE-1.0-PLAN.md](RELEASE-1.0-PLAN.md)** - Production release targets
- **[FULL-ROADMAP-PLAN.md](FULL-ROADMAP-PLAN.md)** - Complete long-term vision
- **[ROADMAP-ANALYSIS.md](ROADMAP-ANALYSIS.md)** - Detailed status analysis
