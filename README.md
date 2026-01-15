# Pedantic • DSC Helper Module

DSC helper module for the Pedantic project.

This module provides user-friendly DSC v3 operations with parameter autocomplete support. It automatically handles remote execution without requiring manual setup on remote machines. The module targets PowerShell 7 and includes features like resource mapping, installer/resource caching, and platform-specific DSC version management.

## Development Process

This project uses ADP (Automated Development Process) to streamline development workflows. See [ADP-INTEGRATION.md](ADP-INTEGRATION.md) for setup instructions.

📊 **[See Complete Roadmap Analysis →](NEXT-STEPS.md)**

### What's Working
- ✅ PowerShell module (production-ready)
- ✅ VS Code extension scaffold  
- ✅ Dual DSL parsers (Simple + SudoLang)
- ✅ Resource graph visualization (basic)
- ✅ Test framework with passing tests

### What's Next
- 🔴 **LSP Integration** ← Critical path (start here)
- 🟡 Testing infrastructure (golden corpus)
- 🟡 PowerShell bridge connection
- 🟢 UI polish (ECharts, formatter, code actions)

**Detailed Plans:**
- [MVP Plan (3-4 weeks)](MVP-PLAN.md)
- [1.0 Release Plan (7-8 weeks)](RELEASE-1.0-PLAN.md)
- [Full Roadmap (6-7 months)](FULL-ROADMAP-PLAN.md)
- [Implementation Analysis](ROADMAP-ANALYSIS.md)

---

## PowerShell Module Features

- PowerShell 7 compatible
- Remote DSC operations without manual remote setup
- Resource mapping and platform-aware DSC version management
- Installer and resource caching
- Unix-like `head` and `tail` helpers for PowerShell pipelines
- ADP-assisted development workflow (pending integration)

## Parameters

None.

## Notes

- Includes helper functions for managing DSC installers and resources
- Supports both local and remote DSC operations
- Provides lightweight text utilities (`Get-Head`, `Get-Tail`)

## Quick Start

```powershell
Import-Module Pedantic
# Use the module to manage DSC resources and configurations
```

## Examples

Get the first 5 lines of a file:

```powershell
Get-Content file.txt | Get-Head -Count 5
```

Get the last 5 lines of a file:

```powershell
Get-Content file.txt | Get-Tail -Count 5
```

Initialize installer cache:

```powershell
Initialize-InstallerCache
```

Get the latest DSC version for Windows:

```powershell
Get-LatestDscVersion -Platform "Windows"
```

Download a specific DSC resource:

```powershell
Download-DscResource -ResourceType "Microsoft.Windows/Registry" -Version "1.0.0" -Source "PowerShellGallery"
```

Ensure required DSC resources are available:

```powershell
Ensure-DscResourcesAvailable -ResourceTypes @("Microsoft.Windows/Registry", "Microsoft.Windows/File") -Force
```

---

If you need additional examples or command help, run `Get-Help <CommandName> -Full` after importing the module.

## Example: Install Go (Golang) on Windows with DSC v3

This example uses the transitional DSC v3 resource `Microsoft/DSC/Transitional/RunCommandOnSet` to run an idempotent PowerShell command that installs Go only if it isn't already present. The Pedantic module ensures the required resource is cached and runs the configuration.

1. Ensure required DSC resource is available locally (downloads/caches if needed):

```powershell
$resources = @("Microsoft/DSC/Transitional/RunCommandOnSet")
$ensure = Ensure-DscResourcesAvailable -ResourceTypes $resources -Force
if (-not $ensure.AllAvailable) { throw "Required DSC resources are not available: $($ensure.Missing -join ', ')" }
```

1. Create a DSC v3 YAML that installs Go if missing (save as `go-install.dsc.yaml`):

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

1. Apply the configuration locally with Pedantic:

```powershell
Import-Module Pedantic

# Run the Set operation (remove -WhatIf to execute for real)
Set-DscConfiguration -DscPath ./go-install.dsc.yaml -WhatIf:$false
```

Remote example (run on another computer) using integrated remoting and auto resource install:

```powershell
Set-DscConfiguration -DscPath ./go-install.dsc.yaml `
  -ComputerName 'server01' `
  -AutoInstallDscResources `
  -ForceUpdateCache
```

Notes:

- The MSI installer updates PATH automatically; open a new shell for `go` to be available.
- Update `$version` to the desired Go release. For offline environments, pre-stage the MSI and replace the download with a local path.

### Alternative: Install Go with the Winget DSC resource (if available)

If your environment exposes a Winget DSC resource (commonly `Microsoft.WinGet/Package`), you can install Go declaratively without a custom command.

1. Check for the Winget DSC resource:

```powershell
$resource = "Microsoft.WinGet.DSC"
Update-DscResourceCache -SpecificResource $resource 

```

1. Create `go-install-winget.dsc.yaml`:

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

1. Apply the configuration:

```powershell
Import-Module Pedantic
Set-DscConfiguration -DscPath ./go-install-winget.dsc.yaml
```

Notes:

- Winget may require Windows 11/Server 2022 with Desktop Experience and the App Installer/Store delivery channel enabled.
- In offline or locked-down environments without Winget, use the transitional example above or your internal package source.
