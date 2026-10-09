# Pedantic VS Code Extension

> **Rich DSC authoring experience with dual-dialect support, visual graph visualization, and PowerShell integration**

The Pedantic extension provides a modern development experience for Desired State Configuration (DSC) authoring, supporting both Simple DSL (YAML-based) and SudoLang (natural language-style) syntaxes.

## ✨ Features

### 🌐 Dynamic Inventory View
- **Preview unavailable**: Inventory, host facts, and configuration remediation require a configured Pedantic service backend and are not available in this extension release.
- **Truthful Explorer state**: The Explorer shows that the inventory service is not configured; it never displays demonstration hosts or reports a configuration push as successful.
- **Planned service integration**: A future service-backed view will render typed inventory observations and durable operation projections, including approval, authorization, progress, cancellation, and final evidence.

### 🔍 Language Server Protocol (LSP) Integration
- **Real-time diagnostics**: Instant validation with error/warning messages in Problems panel
- **Intelligent completions**: Auto-complete for keys, methods, and package managers
- **Document formatting**: One-click formatting to canonical DSL style
- **Quick fixes**: Three code actions for common patterns

### 📊 Visual Graph Visualization
- **Interactive force-directed graph**: Powered by ECharts for professional visualization
- **Click-to-navigate**: Click any package node to jump to its definition in code
- **Live updates**: Graph refreshes automatically as you edit
- **Diagnostic overlay**: View errors and warnings alongside the graph

### 🧰 Prereqs & Resource Management
- **DSC v3 prerequisite check**: Validate DSC installation and version from VS Code
- **Common resource guardrails**: Ensure baseline resources are present; one-click install missing items
- **Resource inventory**: Visual bar chart + tables showing installed vs cached/available resources
- **Add resources fast**: Quick-pick installer to pull DSC resources into your project

### ⚡ PowerShell Bridge
- **DSC generation**: Convert Simple DSL to standard DSC v3 YAML
- **JSON communication**: Structured error reporting and timeout handling
- **Configurable**: Set custom PowerShell executable path

### 🎨 Dual Dialect Support
- **Simple DSL**: Clean YAML-based syntax for package installations
- **SudoLang**: Natural language commands (`install git via winget`)

## 🚀 Quick Start

### Installation

1. Install the extension from VS Code Marketplace (or load from VSIX)
2. Ensure PowerShell 7+ is installed (`pwsh` must be in PATH)
3. Clone or create a DSC project

### Create Your First Configuration

1. Create a file named `my-dev-setup.simple.dsc.yaml`
2. Start typing `dsc.` to see auto-completions
3. Add packages:

```yaml
dsc.install:
  packages:
    - Git.Git
    - Microsoft.VisualStudioCode
    - name: Python.Python.3.12
      version: 3.12.1
      method: winget
```

4. Save the file (diagnostics will appear if there are issues)
5. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac) and run:
   - `Pedantic: Open Resource Graph` to visualize
   - `Pedantic: Generate DSC from DSL` to convert to DSC YAML

### Available Commands

- `Pedantic: Generate DSC from DSL` - Convert DSL to DSC v3 YAML
- `Pedantic: Open Resource Graph` - Visualize package dependencies
- `Pedantic: Debug Parse Current Document` - Show parser diagnostics
- `Pedantic: Open AI Assistant` - Placeholder for future MCP integration
- `Pedantic: Check DSC Prerequisites` - Verify DSC v3 + common resources; offers one-click fixes
- `Pedantic: Show Resource Inventory` - Graph/list view of installed vs cached/available resources
- `Pedantic: Add DSC Resource to Project` - Install a DSC resource from catalog/cache in one step

### Keyboard Shortcuts

- **Format Document**: `Shift+Alt+F` (or `Shift+Option+F` on Mac)
- **Quick Fix**: `Ctrl+.` (or `Cmd+.` on Mac) when on a diagnostic

## 📝 Syntax Examples

### Simple DSL (YAML-based)

```yaml
dsc.install:
  packages:
    # Simple form - just the package ID
    - Git.Git
    - Microsoft.VisualStudioCode
    
    # Object form - with version pinning
    - name: Python.Python.3.12
      version: 3.12.1
    
    # Provider override
    - name: Node.js
      method: chocolatey
    
    # Custom executable installer
    - name: CustomApp
      executable: C:\installers\custom.msi
      args: /quiet /norestart
```

### SudoLang (Natural Language)

```
install git via winget
install vscode via winget
ensure package nodejs via winget version 18.0.0
```

## 🛠️ Configuration

Settings are available under `pedantic.*` in VS Code settings:

```json
{
  "pedantic.bridge.pwshPath": "pwsh",
  "pedantic.telemetry.enabled": false
}
```

Bridge commands run only in trusted workspaces. The PowerShell executable setting
is machine-scoped and restricted in untrusted workspaces; use either `pwsh` or
an absolute path to an executable. Bridge execution does not override
PowerShell's execution policy.

## 🧪 Development

### Building from Source

```bash
cd extension
npm ci
npm run compile
```

The extension supports VS Code 1.90 and later and is type-checked against the
matching 1.90 VS Code API declarations. Building and packaging require Node.js
20.19.0 or later.

### Running Tests

```bash
npm run lint
npm test
```

All 31 tests should pass, covering:
- Golden test corpus (6 fixtures)
- DSL logic and validation
- Praxis engine integration
- Reactive state management
- Parser round-trip tests

### Packaging a VSIX

```bash
npm run package
```

This runs linting and unit tests, bundles the extension host (leaving the
`vscode` API external), and writes `pedantic-dsc.vsix`. To inspect the package
file list without creating the VSIX, run `npx --no-install vsce ls`.

### Debugging

1. Open the extension folder in VS Code
2. Press `F5` to launch Extension Development Host
3. Open a `.simple.dsc.yaml` or `.ssudo` file
4. Set breakpoints in TypeScript source files

## 📚 Documentation

- [MVP Plan](../MVP-PLAN.md) - Implementation roadmap
- [Full Roadmap](../FULL-ROADMAP-PLAN.md) - Long-term vision
- [CHANGELOG](../CHANGELOG.md) - Version history
- [Contributing](../CONTRIBUTING.md) - How to contribute

## 🐛 Known Issues

- Formatter only supports Simple DSL (SudoLang formatting coming soon)
- Graph visualization doesn't yet show dependency edges (nodes only)
- PowerShell bridge generates placeholder YAML (full generation pending)
- Source location tracking incomplete for some package properties

## 📋 Requirements

- VS Code 1.90.0 or higher
- PowerShell 7+ (`pwsh` command available)
- Pedantic PowerShell module (optional, for advanced features)

## 📄 License

MIT License - see [LICENSE](../LICENSE) for details

## 🙏 Acknowledgments

This extension is part of the [Plures](https://github.com/plures) ecosystem, designed to work seamlessly with:
- [PluresDB](https://github.com/plures/pluresdb) - Decentralized resource catalog
- [RuneBook](https://github.com/plures/runebook) - Interactive workflow development
- [Praxis](https://github.com/plures/praxis) - Full-stack framework integration

---

**Happy configuring! 🎉**

For questions or feedback, please [open an issue](https://github.com/plures/pedantic/issues) on GitHub.
