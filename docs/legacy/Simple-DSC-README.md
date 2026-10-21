# Simple DSC - A Minimal DSL for DSC Configurations

## Overview

Simple DSC provides a clean, minimal syntax for creating DSC configurations while leveraging the full power of PowerShell DSC v3 underneath. It's inspired by Ansible's simplicity but generates native DSC configurations.

## The Problem

Standard DSC configurations are verbose and repetitive:

```yaml
# Standard DSC - 15+ lines per package
$schema: "https://aka.ms/dsc/schemas/v3/config/document.json"
metadata:
  name: "Install Development Tools"
resources:
  - name: install_git
    type: Microsoft.DSC.Transitional/RunCommandOnSet
    properties:
      executable: winget
      arguments:
        - install
        - --id
        - Git.Git
        - --source
        - winget
        - --accept-package-agreements
        - --accept-source-agreements
  # Repeat for each package...
```

## The Solution

Simple DSC uses minimal syntax:

```yaml
# Simple DSC - 5 lines total
dsc.install:
  packages:
    - git
    - nodejs
    - docker
    - golang
    - vscode
```

## How It Works

1. **Write Simple DSL**: Use the minimal syntax for common operations
2. **Convert to DSC**: The converter generates full DSC configurations
3. **Run with DSC**: Use standard DSC tooling to execute the configuration

## Quick Start

### 1. Create a Simple DSL file

**simple-install.yaml**:

```yaml
dsc.install:
  packages:
    - git
    - nodejs
    - docker
```

### 2. Convert to DSC

```powershell
Import-Module .\projects\dsc\Simple.DSC.Basic.psm1
ConvertFrom-SimpleDsc -SimpleDslPath .\simple-install.yaml -OutputPath .\output.dsc.yaml
```

### 3. Run the DSC Configuration

```powershell
Import-Module .\projects\dsc\Pedantic.DSC.psm1
Set-DscConfiguration -DscPath .\output.dsc.yaml
```

## Features

 
### ✅ Implemented
 
- **Package Installation**: Simple package lists with automatic WinGet mapping
- **Common Package Names**: Built-in mappings for popular packages (git → Git.Git)
- **DSC Generation**: Converts to valid DSC v3 configurations
- **Validation**: Integrates with existing DSC validation tools

 
### 🚧 Planned
 
- **Configuration File**: Centralized preferences for install methods
- **Platform Detection**: Automatic selection of package manager (WinGet/apt/yum)
- **Override Support**: Custom executables and installation methods
- **Multiple Operations**: Beyond just installs (configure, ensure, etc.)

## Examples

 
### Basic Package Installation

```yaml
dsc.install:
  packages:
    - git
    - nodejs
    - docker
    - golang
    - vscode
```

 
### With Custom Packages (Planned)

```yaml
dsc.install:
  packages:
    - git
    - nodejs
    - name: custom-app
      executable: msiexec
      path: "C:/Installers/CustomApp.msi"
      args: "/quiet /norestart"
```

 
### With Method Override (Planned)

```yaml
dsc.install:
  packages:
    - git
    - name: docker
      method: chocolatey  # Override default WinGet preference
```

## Architecture

```text
Simple DSL → Converter → Full DSC → DSC Engine → System Changes
    ↑            ↑           ↑          ↑
  5 lines    Preferences  15+ lines   Execution
```

### Benefits

1. **Developer Productivity**: Write 80% less configuration code
2. **Consistency**: Centralized preferences reduce copy-paste errors  
3. **Flexibility**: Still generates standard DSC for advanced scenarios
4. **Compatibility**: Works with existing DSC tooling and resources

## Configuration System (Planned)

**simple-dsc-config.yaml**:

```yaml
preferences:
  windows:
    - winget      # Try WinGet first
    - chocolatey  # Then Chocolatey
    - msi         # Then MSI files
  
  packages:
    git: 
      winget: Git.Git
      chocolatey: git
    nodejs:
      winget: OpenJS.NodeJS
      chocolatey: nodejs
```

## Current Status

This is a **proof-of-concept** demonstrating:

- ✅ Simple DSL parsing
- ✅ DSC configuration generation  
- ✅ Package name mapping
- ✅ WinGet integration
- ✅ Validation integration

**Try it now:**

```powershell
# Test the current implementation
Import-Module .\projects\dsc\Simple.DSC.Basic.psm1
Test-SimpleDsc -SimpleDslPath .\projects\dsc\simple-install.yaml
```

## Next Steps

1. Implement configuration file system
2. Add multi-platform package manager support
3. Extend DSL beyond installations
4. Add error handling and validation
5. Package as a proper PowerShell module

## Ansible Parity and Rust Replatform

### Why

- Achieve Ansible-like ergonomics with `dsc.noun.verb` while emitting DSC v3 under the hood.
- Deliver first-class templating (critical): Jinja-like syntax via Rust `minijinja` for `dsc.file.template`.
- Align implementation language with DSC v3 core for performance and shared libraries.

### Initial Ansible ⇔ Simple DSC coverage

- Package → `dsc.install`
- Service → `dsc.service.ensure`
- File → `dsc.file.ensure`
- Copy → `dsc.file.copy`
- Template → `dsc.file.template` (minijinja render + DSC File)
- User/Group → `dsc.user.ensure` / `dsc.group.ensure`
- Git → `dsc.git.clone`
- Download → `dsc.http.fetch`
- Unarchive → `dsc.archive.extract`
- Line/Block edit → `dsc.file.line` / `dsc.file.block`
- Schedule/Cron → `dsc.schedule.ensure`

See `docs/ansible-mapping.yaml` for the source-of-truth manifest (parameters, check/diff, backends).

### Rust refactor game plan

- Create a Rust core that parses Simple DSC YAML, loads `ansible-mapping.yaml`, and projects to DSC v3 documents.
- Embed `minijinja` for templates; expose `dsc.file.template` with check/diff output.
- Provide FFI/bridge for the VS Code extension (TypeScript) to call into the Rust core (napi-rs/wasm32 for webviews, or native binary).
- Keep DSC resources in PowerShell where needed but let Rust handle mapping, validation, and rendering.
- Add golden tests that mirror Ansible behaviors (package, service, template, file mutations) to guard parity and idempotency.

### Current Rust core status (planner/runtime)

- Rust workspace (`rust/`): `pedantic-core` exposes planning, templating, mapping loaders; `pedantic-node` exports Node bindings.
- Planner: classifies tasks as resource vs runtime primitives from `ansible-mapping.yaml`, strips control params, expands loops, and carries `when`/`register` metadata.
- Runtime primitives supported: `register`, `set_fact`, `debug`, `when`, `loop`, `group`, `group_by` (non-DSC control flow).
- Conditions & overrides: `when` uses Jinja expressions; `changed_when` / `failed_when` parsed and evaluated with `result` in scope.
- Handlers: tasks may `notify` handler names; `listen` marks handlers; changed tasks enqueue handlers for post-run execution (deduped, order-preserving).
- Results/diff/check: `TaskResult` carries `changed`, `check`, structured `diffs`; surfaced through Node bindings for UI/register use.
- Docs: see `docs/EXPRESSIONS-AND-TEMPLATING.md` for expression/filter plan and `docs/RUST-RUNTIME-PRIMITIVES.md` for control/handler semantics.

---

*Simple DSC: The power of DSC with the simplicity of modern configuration management.*
