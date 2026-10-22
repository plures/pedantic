# StateSmith Migration Strategy: PowerShell Module → VS Code Extension Ecosystem

This document defines the phased migration path from a PowerShell-centric implementation to a VS Code extension platform with LSP, dual DSLs, AI (MCP), and a gradually re‑implemented execution engine.

## Objectives
1. Preserve current reliability (PowerShell module) while adding new UX layers.
2. Avoid long freeze: deliver user-visible value every 1–2 phases.
3. Enable rollback at each phase (feature flags, contract versioning).
4. Maintain deterministic outputs (golden tests) during rewrites.
5. Minimize duplicated logic—prefer bridging then replacing with test-verified parity.

## Core Streams
| Stream | Scope | Owners (future) | Success Metric |
|--------|-------|-----------------|----------------|
| Bridge | PowerShell invocation contract | engine-bridge | <2% failure rate on standardized ops |
| Parsing | DSL AST + validation | language-server, dsl-core | P95 completion <150ms |
| AI/MCP | Tool API + diff flows | ai-mcp | 95% safe acceptance (no schema rejects) |
| Visualization | Graph / Drift / Reverse | webview-ui | Load <2s cold |
| Engine Port | Provider abstraction + plan optimizer | engine-bridge → engine-js | 60% ops JS by Phase 6 |
| Quality | Test, perf, security, telemetry | shared | All gates green per release |

## Phase Overview
| Phase | Focus | Key Deliverables | Rollback Mechanism |
|-------|-------|------------------|--------------------|
| 1 | Scaffolding | Extension shell, bridge schema v1 | Disable extension (module intact) |
| 2 | Simple DSL LSP | Tolerant parser + diagnostics | Feature flag `statesmith.features.lsp` |
| 3 | SudoLang DSL | Chevrotain grammar + converters | Flag per dialect |
| 4 | MCP AI | MCP server tools + diff UI | `statesmith.features.ai` flag |
| 5 | Visualizations & Reverse | Graph, Drift, Reverse import | Independent command flags |
| 6 | Engine Partial Port | JS provider/core routines | Fallback to bridge if error |
| 7 | Hardening & Release | Perf, security, docs, 1.0 | Defer release tag |

## Detailed Phase Plans
### Phase 1 – Bridge & Contracts
- Define JSON schema (Zod) for requests/responses.
- PowerShell script wrapper: `Invoke-StateSmithBridge.ps1` (operations: generate, apply, test, reverse).
- Logging: structured JSON lines → ephemeral file for debugging.
- Tests: contract round-trip + failure scenarios (missing pwsh, timeout).

### Phase 2 – Simple DSL LSP
- Parser: line-based scanner → AST (Resource nodes) with tolerant error recording.
- Validation rules v1: unknown key, duplicate package, empty package list, unsupported method.
- Completion sources: static keywords + dynamic package list (read adjacent config file).
- Golden Tests: DSL input → DSC YAML via PowerShell; assert stable output hash.

### Phase 3 – SudoLang DSL Introduction
- Grammar (chevrotain) + incremental parse integration.
- Converter parity tests: SudoLang → AST → Simple DSL → DSC equals SudoLang → DSC path.
- Lossiness classifier (warnings when constructs collapse/expand differently).
- Code actions: convert between dialects.

### Phase 4 – MCP / AI Tooling
- MCP server process (Node) started on demand.
- Tools (initial): generateConfig, explainConfig.
- Safety pipeline: raw AI draft → schema validate → diff compute → present patch.
- Audit log: `.statesmith/ai/changes/<timestamp>.json` containing intent, diffs, rationale.
- Expand tools (optimizeInstallPlan, remediateDrift, reverseToDsl) once base stable.

### Phase 5 – Visualization & Reverse
- Resource Graph: AST -> graph JSON -> ECharts webview.
- Drift Panel: test results ingestion (bridge JSON) -> status table.
- Reverse Import: PowerShell export → normalizer → AST → DSL (confidence scoring). Show heatmap in UI.

### Phase 6 – Engine Partial Port
- Provider Abstraction Interface:
  ```ts
  interface Provider {
    id: string;
    detect(pkgId: string): Promise<'present'|'absent'|'unknown'>;
    install(spec: InstallSpec): Promise<InstallResult>;
  }
  ```
- Implement winget/choco/msi wrappers (spawning underlying executables with sanitized args).
- Plan Optimizer: choose provider based on (availability score, offline readiness, speed heuristic).
- Fallback ordering: JS provider attempt → if unsupported or error → PowerShell bridge.
- Metrics: capture provider decision rationale (for AI future hints).

### Phase 7 – Hardening & Release
- Performance tuning (incremental parse caches, webview bundling, lazy AI load).
- Security review: command allowlist, path normalization, extension settings threat model.
- Telemetry gating & docs (opt-in explanation).
- Final docs: DSL spec (Simple + SudoLang), AI Safety & Audit, Provider SDK.
- Version: tag `1.0.0` after meeting acceptance gates.

## Cutover Criteria
| Capability | Bridge Source of Truth | JS Engine Cutover Condition |
|------------|------------------------|-----------------------------|
| Package plan build | PowerShell | Parity test success (≥50 golden cases) |
| Presence detection | PowerShell | Error rate <1% vs module during shadow run |
| Install execution | PowerShell | Dry-run parity + rollback harness |
| Reverse mapping | PowerShell | Confidence scoring average ≥0.9 for corpus |

## Testing Matrix
| Test Type | Scope | Tooling |
|-----------|-------|---------|
| Unit | AST utils, converters, provider strategies | Vitest / Jest |
| Parser | Golden corpus (Simple & SudoLang) | Snapshot + structural asserts |
| LSP | Completions, diagnostics latency | vscode-languageserver test harness |
| Bridge | Operation success/failure, timeouts | Node tests spawning pwsh |
| AI Tools | Schema validity, diff correctness (dry-run) | Contract tests with mock model |
| Webview | Render & message contract | Playwright (component + E2E) |
| Perf | Parse timing, completion P95 | Custom harness + CI reporting |

## Rollback & Feature Flags
| Flag | Description | Default | Phase Introduced |
|------|-------------|---------|------------------|
| statesmith.features.lsp | Enable LSP features | true after Phase 2 | 2 |
| statesmith.features.sudolang | Enable SudoLang dialect | false until stable | 3 |
| statesmith.features.ai | Enable AI MCP integration | false | 4 |
| statesmith.features.visualization | Enable graph/drift panels | false → true post Phase 5 | 5 |
| statesmith.engine.preferJs | Prefer JS engine over bridge | false until Phase 6 mid | 6 |

## KPIs & Monitoring
| KPI | Target | Collection |
|-----|--------|-----------|
| Completion latency P95 | <150 ms | Performance telemetry (opt-in) |
| AI suggestion acceptance | >60% accepted after preview | AI diff audit stats |
| Bridge failure rate | <2% operations | Structured logs aggregation |
| Parser error rate (valid docs) | <1% | Golden corpus CI run |
| Provider fallback frequency | <15% after Phase 6 | Engine metrics |

## Risk Mitigation Mapping
| Risk | Mitigation | Validation |
|------|-----------|------------|
| Divergent outputs post rewrite | Golden snapshots + hash compare | CI diff gate |
| AI unsafe command injection | Schema + allowlist | AI tool unit tests |
| Performance regressions | Budget thresholds fail build | CI perf job |
| Bridge hangs | Timeout + cancellation token | Simulated delay tests |
| Partial AST corruption | Parse invariant assertions | Fuzz tests (Phase 3+) |

## Migration Work Items (Backlog Extract)
1. Implement bridge script + JSON schema validator.
2. Golden corpus fixture collection from current examples.
3. Tolerant parser + AST diff harness.
4. Chevrotain grammar draft PR.
5. MCP server skeleton with mock tool responses.
6. Graph data builder (AST→graph). 
7. Provider interface + winget detection prototype.
8. Shadow run harness comparing JS vs PowerShell outputs.
9. Telemetry event schema & redaction tests.
10. Security checklist completion before enabling AI by default.

## Operational Playbooks (Summaries)
### Rollback
1. Disable feature flag in settings default JSON.
2. Publish patch version with release note “Feature temporarily disabled due to regression #ISSUE”.
3. Investigate using captured logs + golden diff outputs.

### Adding New DSL Directive
1. Draft directive spec (syntax, semantics, AST impact).
2. Update grammar + parser tests, then converters.
3. Add golden test, update docs, version DSL schema.
4. If AI: extend prompt templates & tool validation.

### AI Tool Evolution
1. Introduce new field with `x-experimental` marker in response.
2. Update validator schema; maintain backward compatibility.
3. After 2 minor versions stable, remove experimental marker.

## Exit Criteria for Declaring Legacy Module “Secondary”
- ≥80% of user workflows achievable inside VS Code without manual PowerShell scripting.
- All core DSC actions reachable via commands & UI.
- JS engine handles at least: presence detection, plan generation, command construction (install still may delegate).

---
This strategy will be iteratively updated; changes require: PR + reviewer sign-off from parsing + engine stakeholders once those roles exist.
