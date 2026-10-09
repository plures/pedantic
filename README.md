# Pedantic

**Modern DSC (Desired State Configuration) management toolkit**

Pedantic is a DSC authoring, validation, and configuration-management project
being refactored around PX Lang decisions, a profile-scoped PluresDB service,
and bounded DSC effects. The v0.6 release is a **pre-parity** release: its
offline CLI is usable for parsing, structural validation, planning, and export;
the Windows-local service supports admitted validation, inventory observation,
read-only compliance observation, and redacted Chronos evidence. It does not
yet provide service-backed remediation or remote deployment.

The shipped PowerShell module is a legacy compatibility surface. It can apply a
local configuration only when DSC is already installed, but its remote,
automatic-bootstrap, and automatic-resource preparation paths are not
supported in v0.6. Do not use those switches as an operational deployment
contract. See [the parity recovery record](docs/REFACTOR-PARITY-RECOVERY.md)
for the complete capability map and acceptance gates.

## Open-core model

Pedantic's native core is licensed under Apache-2.0. The open core includes
the versioned contracts, PX lifecycle, coordinator, profile-scoped local
service, ephemeral agent, capability SDK, core providers, CLI, MCP server, and
VS Code authoring and local operation experiences.

Commercial Pedantic products build on those stable public contracts to provide
shared multi-user governance, enterprise identity and RBAC, high availability,
private registries, commercial compliance content, fleet analytics, managed
distribution, and support. See
[the open-core product boundary](docs/OPEN-CORE-MODEL.md).

## Features

The legacy Pedantic PowerShell module currently provides:

- **Local DSC Compatibility** - Apply, test, validate, and export a local DSC configuration when DSC is already installed
- **Resource Cache Utilities** - Cache-management commands retained for migration; they are not wired into the v0.6 apply path
- **Remote Execution** - Not supported by the released compatibility apply path
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
# Inspect the user-scoped cache without making a network request
Get-DscInstallerCache

# Explicitly refresh the Windows DSC installer cache (network access)
Update-DscInstallerCache -Platform Windows

# Explicitly cache a DSC resource (network access)
Update-DscResourceCache -SpecificResource "Microsoft.Windows/Registry"

# Check that required resources are already cached. Add -Force only when an
# online download is intended.
Ensure-DscResourcesAvailable -ResourceTypes @("Microsoft.Windows/Registry", "Microsoft.Windows/File")
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

4. **Remote execution:** not available in v0.6. Use this example only after the
   service-backed remote remediation capability has passed its task suite.

```powershell
# Planned, not currently supported:
# Set-DscConfiguration -DscPath ./go-install.dsc.yaml -ComputerName 'server01'
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

### Key Functions and compatibility status

- **Configuration Management**: local-only compatibility `Set-DscConfiguration`, `Test-DscConfiguration`, `Validate-DscConfiguration`, `Export-DscConfiguration`
- **Resource Management**: `Update-DscResourceCache`, `Ensure-DscResourcesAvailable`, `Get-DscResourcePath` are retained migration utilities
- **Remote Operations**: `New-SecureRemoteSession`, `Repair-DscInstallation` are not wired into `Set-DscConfiguration` and are not a supported deployment route
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

## Cross-platform Ansible adapter demo

Pedantic ships a runnable Docker demo that drives two Linux targets through the same
`Pedantic.Ansible/Module` DSC adapter: it creates a managed file and provisions a real
802.1Q VLAN interface in a `NET_ADMIN`-capable network-target container. The control
container installs the released DSC CLI and Ansible; no mocked Ansible commands or
synthetic resource responses are used.

```powershell
pwsh -NoProfile -File ./examples/cross-platform-ansible/run-demo-host.ps1
```

The declarative configuration is in
[`examples/cross-platform-ansible/cross-platform.dsc.yaml`](examples/cross-platform-ansible/cross-platform.dsc.yaml).
The script reports `CROSS_PLATFORM_ANSIBLE_DEMO_OK` only after SSH verification sees
both `/var/tmp/pedantic-linux-demo.txt` and the `pedanticvlan42` VLAN link. The target
is a local Docker Linux container with `NET_ADMIN`, so it is a realistic Linux/network
substitute rather than an external switch.

## MCP server

`pedantic-mcp` exposes Pedantic's real DSC v3 integration over the Model Context
Protocol stdio transport. It does not emulate DSC: its tools execute the host `dsc`
binary and return its output.

```powershell
cd rust
cargo run -p pedantic-mcp
```

Configure an MCP client to launch `rust/target/debug/pedantic-mcp` (or the release
binary) with `dsc` on `PATH`. The server provides:

- `resource_list` — discover resources through `dsc resource list`
- `resource_get`, `resource_test`, and `resource_export` — inspect, check, and export
  concrete DSC resource instances
- `config_validate` and `config_export` — validate and export DSC configuration

Run the real stdio protocol smoke test after building to verify discovery and a read
operation end-to-end:

```powershell
$env:DSC_RESOURCE_PATH = (Join-Path $PWD '..\Resources\SimpleDSC.PackageInstaller')
node ../tests/mcp-smoke.mjs
```
