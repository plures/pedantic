# StateSmith Extension Architecture (Initial Draft)

This document captures the high-level architecture for transforming StateSmith into a VS Code–centric platform with multi-DSL authoring, AI assistance (MCP), and visualizations.

## Layered Overview

```
┌──────────────────────────────┐
│        VS Code Client        │
│  Commands • Webviews • LSP   │
└─────────────┬────────────────┘
              │ (JSON RPC / IPC)
┌─────────────▼────────────────┐
│        Language Server        │
│  Parsing • AST • Validation   │
└─────────────┬────────────────┘
              │ Unified AST
┌─────────────▼────────────────┐
│          DSL Core            │
│  AST Types • Normalizers     │
│  Printers • Converters       │
└─────────────┬────────────────┘
              │ Exec Contracts
┌─────────────▼────────────────┐
│        Engine Bridge         │
│ PowerShell child process     │
│  (Invoke DSC / Reverse /     │
│   Resource Detection)        │
└─────────────┬────────────────┘
              │ Optional
┌─────────────▼────────────────┐
│         JS Engine (Future)   │
│ Provider Strategies • Cache  │
└─────────────┬────────────────┘
              │ AI Tool Calls
┌─────────────▼────────────────┐
│          MCP Server          │
│ AI Tools • Prompts • Diffing │
└──────────────────────────────┘
```

## Packages (Workspaces)

| Package | Responsibility | Tech |
|---------|----------------|------|
| extension | Activation, commands, UI wiring | TypeScript (Node) |
| language-server | LSP implementation (Simple + SudoLang) | TypeScript + vscode-languageserver |
| dsl-core | AST, schema, printers, golden tests | TS |
| dsl-sudo | SudoLang grammar (chevrotain) + converter | TS (chevrotain) |
| engine-bridge | Child process runner for PowerShell + JSON contract | TS + PowerShell scripts |
| ai-mcp | MCP server exposing AI tools (generate/explain/optimize/remediate/reverse) | TS |
| webview-ui | Svelte 5 + ECharts visualizations | Svelte/Vite |
| shared | Logging, telemetry, config loader | TS |

## Command Surface (Initial)

| Command ID | Purpose |
|------------|---------|
| statesmith.generateConfig | Convert current DSL file -> DSC YAML (bridge) |
| statesmith.applyConfig | Set DSC configuration (with confirmation) |
| statesmith.testConfig | Run Test/Validate and show drift panel |
| statesmith.openGraph | Open resource graph webview |
| statesmith.openAiPanel | Open AI assistant panel (MCP) |

## JSON Bridge Contract (v1 Draft)

Request:
```json
{
  "version": 1,
  "operation": "generate-dsc" | "apply-dsc" | "test-dsc" | "reverse-dsc",
  "payload": { "dslPath": "...", "tempDir": "..." }
}
```
Response:
```json
{
  "version": 1,
  "ok": true,
  "operation": "generate-dsc",
  "result": { "outputPath": "...", "lines": 123 },
  "diagnostics": [],
  "timingsMs": { "total": 540 }
}
```
Errors: `ok:false`, `error:{ code, message, detail }`.

## AST (Canonical Subset)

```ts
interface Document {
  kind: 'Document';
  dialect: 'simple' | 'sudo';
  resources: Resource[];
  meta: Meta;
}
interface Resource {
  kind: 'PackageInstall';
  name: string;            // logical id
  packageId: string;       // canonical identifier
  provider: 'winget' | 'chocolatey' | 'msi' | 'unknown';
  version?: string;
  options?: Record<string, string | boolean>;
  sourceLocation?: SourceLoc;
}
```

## SudoLang Snapshot (Illustrative)

```
configure host:
  install package "Git.Git" via winget
  ensure package "NodeJS" via chocolatey version latest
```

## MVP Parsing Strategy

1. Tolerant line scanner for Simple DSL (Phase 2).
2. Chevrotain grammar for SudoLang (Phase 3) generating same AST shape.
3. Normalization layer ensures deterministic ordering & hashing (for caching and diffing).

## Visualizations Data Contracts

Graph JSON:
```json
{ "version":1, "nodes":[{"id":"install_Git","type":"PackageInstall"}], "edges":[] }
```

Drift Panel Input:
```json
{ "version":1, "tests":[{"resource":"install_Git","status":"InDesiredState"}] }
```

## AI / MCP Tool Envelope

```json
{
  "intent": "generateConfig",
  "input": { "naturalLanguage": "Install git and node" },
  "draft": "dsc.install:\n  packages:\n    - Git.Git\n    - OpenJS.NodeJS",
  "rationale": ["Mapped 'git' -> 'Git.Git' winget id"],
  "diffs": [{"path":"/packages/1","change":"add"}]
}
```

## Security Considerations

* Execution consent prompt before first bridge call.
* Sanitize and escape all arguments; forbid arbitrary shell injection.
* AI outputs pass through schema validation before display.

## Performance Budgets (Design Targets)

| Component | Budget |
|-----------|--------|
| Initial parse (200 lines) | < 40 ms |
| Completion P95 | < 150 ms |
| Webview cold load | < 2000 ms |
| generateConfig AI round-trip | < 8 s P90 |

## Next Architectural Tasks

1. Scaffold extension package and activation events.
2. Implement bridge schema validator (Zod or custom).
3. Establish golden test fixture format under `test-fixtures/`.
4. Draft SudoLang grammar outline (non-executable doc) -> PR discussion.

---
This architecture draft will evolve as DSL & MCP specifications stabilize.
