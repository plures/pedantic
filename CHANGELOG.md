## [0.0.1] — 2026-04-07

- chore: centralize release to org-wide reusable workflow (c896eff)
- ci: standardize Node version to lts/* — remove hardcoded versions (eb33d55)
- ci: centralize lifecycle — event-driven with schedule guard (d4d2199)
- fix(lifecycle): v9.1 — fix QA dispatch (client_payload as JSON object) (222d903)
- fix(lifecycle): rewrite v9 — apply suggestions, merge, no nudges (89dac58)
- chore: switch license from MIT to BSL 1.1 (commercial product) (6753f9e)
- chore: standardize license to MIT (af82fab)
- chore: standardize copilot-pr-lifecycle.yml to canonical version (105761c)
- chore: apply org-standard automation files (#69) (e4083ed)
- deps(npm)(deps): bump yaml from 2.8.1 to 2.8.3 in /extension (#70) (5547ae1)
- ci(deps): bump actions/download-artifact from 4 to 8 (#68) (8e8a322)
- ci(deps): bump actions/setup-node from 4 to 6 (#67) (98e7045)
- ci(deps): bump actions/checkout from 4 to 6 (#66) (279d498)
- ci(deps): bump actions/upload-artifact from 4 to 7 (#65) (e578fc4)
- deps(npm)(deps-dev): bump undici from 7.24.1 to 7.24.4 in /extension (#64) (0fdb85d)
- deps(npm)(deps): bump chevrotain from 11.1.0 to 12.0.0 in /extension (#63) (92b1106)
- ci(deps): bump actions/download-artifact from 8.0.0 to 8.0.1 (#62) (196e6df)
- deps(npm)(deps-dev): bump undici from 7.18.2 to 7.24.1 in /extension (#61) (f728805)
- ci: fix non-existent GitHub Actions versions across all workflow files (#38) (69d6cde)
- ci(deps): bump peter-evans/repository-dispatch from 3 to 4 (#37) (80f10f6)
- ci: add PR lane event relay to centralized merge FSM (54aff12)
- deps(npm)(deps-dev): bump underscore from 1.13.7 to 1.13.8 in /extension (#36) (687127f)
- ci(deps): bump actions/download-artifact from 7.0.0 to 8.0.0 (#35) (81c9608)
- ci(deps): bump actions/upload-artifact from 6 to 7 (#34) (d9ac261)
- fix(ci): add id-token: write permission to release workflow (#33) (6dc0a45)
- deps(npm)(deps-dev): bump qs from 6.14.1 to 6.15.0 in /extension (#31) (c59d78a)
- Add DSC v3 adapter for Ansible modules (Pedantic.Ansible/Module) (#29) (91dbd41)
- Add dynamic inventory view with Ansible-style host management (#27) (b808659)
- Refactor README to reflect current state, remove roadmap content (#26) (e24637e)
- ci(deps): bump actions/download-artifact from 4.1.3 to 7.0.0 (#24) (2cfc32f)
- Implement MVP: LSP server, PowerShell bridge, ECharts visualization, and test suite (#23) (83874a3)
- deps(npm)(deps-dev): bump @types/node in /extension (#21) (3f04080)
- ci(deps): bump actions/setup-node from 4 to 6 (#20) (7215c59)
- ci(deps): bump actions/checkout from 4 to 6 (#19) (7ca286d)
- deps(npm)(deps): bump chevrotain from 10.5.0 to 11.1.0 in /extension (#18) (a6a03d0)
- ci(deps): bump codecov/codecov-action from 4 to 5 (#17) (f461ae8)
- ci(deps): bump github/codeql-action from 3 to 4 (#16) (d443b91)
- ci(deps): bump actions/upload-artifact from 4 to 6 (#15) (7f92d95)
- Change source from 'statesmith' to 'pedantic' (dd16107)
- Update server log name in MVP plan (19dae1f)
- Integrate praxis-inspired logic engine and reactive state management (#10) (77ad0a9)
- Bump undici from 7.16.0 to 7.18.2 in /extension (#14) (0be2053)
- Bump qs from 6.14.0 to 6.14.1 in /extension (#13) (d90dddc)
- Reposition Pedantic as DSC ecosystem hub (Ansible Galaxy analog) (#12) (8061f27)
- Implement comprehensive CI/CD pipeline with self-testing and multi-layer security (#8) (1e5731a)
- Merge pull request #6 from plures/copilot/analyze-project-roadmap (f2d322c)
- Merge branch 'main' of https://github.com/plures/pedantic into copilot/analyze-project-roadmap (dd870ad)
- Merge pull request #4 from plures/copilot/cleanup-repo-structure (d9192a5)
- Fix CI workflow and remove hardcoded values from test scripts (dc31152)
- Complete roadmap analysis with detailed execution plans (46498bd)
- Add comprehensive roadmap analysis and updates (5058bda)
- Fix build script for Linux/Mac and complete naming cleanup (32113fa)
- Update all documentation and test files to use Pedantic naming (4600073)
- Rename project from StateSmith to Pedantic across all files (cfe5257)
- Initial plan (41e3590)
- Organize repository structure - move docs, examples, tests to dedicated folders (262d28e)
- Initial plan (1e9e022)
- Merge pull request #2 from plures/copilot/install-adp-for-project (ebf9c5a)
- Refactor CI workflow for improved clarity (821b828)
- Refactor CI workflow configuration (5159724)
- Add implementation summary documentation (c22050f)
- Address code review feedback: fix config inconsistencies and CI optimization (70ac952)
- Add ADP setup verification script (2dc12ce)
- Update CI workflow to support ADP initialization (98295aa)
- Add ADP integration infrastructure and documentation (0a9a60d)
- Initial plan (b78ba5b)
- initial (613fa55)

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
