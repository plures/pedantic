# StateSmith VS Code Extension (Preview Scaffold)

This is the initial scaffold for the StateSmith extension – providing DSC authoring, visualization, and future AI (MCP) assistance.

## Current Status
- Commands registered:
  - `StateSmith: Generate DSC from DSL` (stub – no bridge yet)
  - `StateSmith: Open Resource Graph` (placeholder webview)
  - `StateSmith: Open AI Assistant` (placeholder webview)
- Activation: on YAML files or when commands executed.

## Planned (Refer to root ROADMAP.md)
- PowerShell bridge (generate/apply/test)
- LSP (Simple DSL + SudoLang)
- MCP AI tools integration
- Graph + drift + reverse views

## Development
Install deps and compile (placeholder scripts – lint/tests to follow):

```bash
npm install
npm run compile
```

Launch the extension host from VS Code (F5) and run a registered command from the Command Palette.

## Notes
This scaffold intentionally keeps logic minimal until bridge schema & AST layers are introduced.
