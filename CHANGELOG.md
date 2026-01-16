# Changelog

All notable changes to the Pedantic project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-16

### Added - MVP Release

#### Language Server Protocol (LSP) Integration
- Full LSP server implementation with document sync
- Real-time diagnostics in Problems panel for both Simple DSL and SudoLang
- Intelligent code completions for:
  - Top-level keys (`dsc.install`)
  - Package properties (`packages`, `method`, `version`)
  - Package managers (winget, chocolatey, msi, apt, yum, brew)
- Document formatting with idempotent canonical output
- Three code actions:
  - Add missing packages key
  - Expand string to object form
  - Remove unknown fields

#### Visual Graph Visualization
- ECharts-based force-directed graph layout
- Interactive node visualization for installed packages
- Click-to-reveal: Navigate from graph node to source location
- Real-time graph updates on document changes
- Diagnostic display within graph panel

#### PowerShell Bridge
- JSON-based communication bridge between VS Code and PowerShell
- DSC YAML generation from Simple DSL
- Configurable PowerShell executable path
- Timeout handling and error reporting
- Support for WhatIf mode

#### Parsers & Testing
- Simple DSL parser with YAML-based syntax
- SudoLang parser with natural language-style commands
- Golden test suite with 6 fixture files covering:
  - Basic package installation
  - Multi-package scenarios
  - Provider overrides
  - Executable overrides with arguments
  - Version pinning
  - SudoLang basic commands
- 31 passing tests with comprehensive coverage

#### Developer Experience
- Renamed all commands from `statesmith.*` to `pedantic.*`
- Output channel for debug parsing
- Debounced graph refresh (200ms)
- Support for both trusted and untrusted workspaces
- Graceful error handling and user feedback

### Changed
- Updated extension display name to "Pedantic DSC"
- Improved YAML parser to use direct imports instead of dynamic require
- Enhanced diagnostics with proper severity levels and codes

### Fixed
- TypeScript compilation error in reactive-state.ts (parent reference)
- Package ID canonicalization (lowercase normalization)
- Executable override structure (object with path and args)
- Test fixture paths for golden tests

## [Unreleased]

### Planned Features
- Hover tooltips with package information
- Go-to-definition for package references
- Signature help for DSL methods
- Workspace symbol search
- Rename refactoring
- Find all references
- Semantic highlighting
- Inlay hints for implicit versions

---

[0.1.0]: https://github.com/plures/pedantic/releases/tag/v0.1.0
