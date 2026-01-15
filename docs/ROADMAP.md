# Pedantic Roadmap (Revised): VS Code Extension + MCP + AI + Multi-DSL

This revised roadmap pivots the project from “PowerShell module first” to a **VS Code extension ecosystem** with:

* Hybrid execution (existing PowerShell DSC engine retained initially).
* Language Server Protocol (LSP) for the existing Simple DSL and a new optional **SudoLang-inspired declarative DSL**.
* **MCP Server integration** to enable AI‑assisted configuration design, validation, remediation, explanation, and reverse engineering workflows.
* Rich Svelte 5 / ECharts webviews for visualization (resource graph, drift insights, reverse mapping, AI design canvas).

The legacy PowerShell module remains a “compatibility substrate” during early phases and is incrementally reimplemented or wrapped in TypeScript.

---
## 0. Guiding Principles

| Principle | Rationale | Implementation Cue |
|-----------|-----------|---------------------|
| Progressive enhancement | Don’t break current users | Keep PowerShell cmdlets callable via extension commands |
| Dual DSLs with convergence | Simple YAML and SudoLang variant serve different authoring styles | Provide converters & round‑trip safety tests |
| AI as assist, never silent mutator | Determinism & auditability | All AI changes produce diff previews + justification blocks |
| Clear boundaries | Separation of parsing, evaluation, execution | Packages by concern (dsl-core, lsp, engine, webview, ai) |
| Observability first | Fast diagnosis of parser or AI issues | Structured telemetry events + opt‑in usage metrics |

---
## 1. Target Deliverables (End State Vision)

1. VS Code Extension (Marketplace) – `statesmith-dsc`
2. Embedded LSP supporting:
   * Syntax highlighting & semantic tokens
   * Completions (keys, methods, package IDs)
   * Diagnostics (schema, unknown method, version mismatch)
   * Code actions (normalize, convert simple→object, add missing field)
   * Format provider (canonical ordering, style rules)
3. Dual DSL Support:
   * `*.simple.dsc.yaml` (current YAML form, stabilized)
   * `*.ssudo` (SudoLang-inspired declarative form)
   * Bidirectional conversion where lossless; warnings where not
4. AI / MCP Capabilities (via local or remote MCP server):
   * `generateConfig` – From natural language or SudoLang snippet to validated DSL
   * `explainConfig` – Annotate resources with rationale
   * `optimizeInstallPlan` – Reorder / choose best providers (winget/choco/msi) with justification
   * `remediateDrift` – Given diff of desired vs actual, produce patch + risk notes
   * `reverseToDsl` – Convert existing exported DSC JSON/PowerShell config into DSL + commentary
5. Visualizations (webviews):
   * Resource graph (ECharts) – nodes (resource), edges (dependency/sequence)
   * Drift dashboard – last test run, pending changes
   * AI design canvas – live edits + proposed AI patches side panel
   * Reverse view – imported config vs generated DSL diff heat-map
6. Execution Engine Layer:
   * Phase 1: PowerShell child process bridge (JSON contract)
   * Phase 2: Selected routines ported (resource presence checks, packaging) to Node
   * Phase 3: Optional Deno tasks (experiments) behind feature flag
7. Quality & Tooling:
   * Golden tests (DSL → DSC YAML parity with legacy module)
   * Performance budgets enforced (LSP <150 ms P95 completion)
   * Security model: explicit execution consent, signed script guidance

---
## 2. Phased Timeline & Milestones

### Phase 0 (Now) – Legacy Stabilization (Optional Hardening)
If required: finalize comment-based help, minimal CHANGELOG, license. Freeze further PowerShell churn.

### Phase 1 – Monorepo & Scaffolding
* Workspaces: `extension/`, `language-server/`, `dsl-core/`, `dsl-sudo/`, `webview-ui/`, `engine-bridge/`, `ai-mcp/`, `shared/`.
* Basic extension activation + command: “Pedantic: Generate Configuration (PowerShell)” piping through existing `ConvertFrom-SimpleDsc`.
* Webview placeholder + static asset pipeline (Vite + Svelte 5).
* Initial CI: build + minimal extension integration test (open sample workspace).

### Phase 2 – Minimal LSP (Simple DSL)
* Hand‑rolled tolerant parser -> AST (resources, packages, methods).
* Diagnostics: unknown top-level key, duplicate package, missing `packages` list.
* Completions: root keys, method values, dynamic package IDs from config file.
* Golden output test: sample simple DSL -> expected DSC YAML.

### Phase 3 – SudoLang Variant Introduction
* Define `.ssudo` grammar subset (imperative‑like declarative syntax). Example:
  ```
  configure machine:
    install winget "Git.Git" version latest
    ensure package "NodeJS" method chocolatey
  ```
* Parser (chevrotain) generating unified canonical AST.
* Converter: SudoLang <-> Simple DSL (lossless constraints doc).
* Diagnostics specific to SudoLang (ambiguous verb, unknown directive).

### Phase 4 – MCP Server & AI Workflows (Foundational)
* Implement MCP server (Node) exposing tools:
  * `statesmith.generateConfig` (inputs: naturalLanguage | sudoSnippet, contextPaths[])
  * `statesmith.explainConfig`
  * `statesmith.optimizeInstallPlan`
  * `statesmith.reverseToDsl`
  * `statesmith.remediateDrift`
* Structured response envelope: `{ version, intent, original, proposedDraft, rationale[], risk[], diffs[] }`.
* Extension MCP client harness with cancellation & token usage logging.
* UI: AI panel command palette entries + diff preview (readonly -> apply).

### Phase 5 – Visualizations & Reverse Engineering
* Resource graph webview (graph JSON from AST + dependency inference heuristics).
* Drift dashboard (test results ingestion: PowerShell output -> normalized JSON -> view).
* Reverse pipeline: import existing DSC config (PowerShell export) -> normalize -> AST -> DSL (with mapping quality score per resource).

### Phase 6 – Engine Evolution & Partial JS Port
* Port resource presence checks & install plan builder to JS.
* Add provider abstraction (winget/choco/msi/future apt/brew) with pluggable strategy scoring (speed / id confidence / offline availability).
* Add caching & offline staging manager (hash-indexed store).
* Optional Deno feature flag for sandboxed evaluation experiments.

### Phase 7 – Hardening, Performance, Release 1.0 (Extension)
* Performance instrumentation & budgets enforced.
* Security review: execution prompts, script path allowlist, telemetry opt-in review.
* Final documentation set: User Guide, AI Safety Guide, DSL Spec (Simple + SudoLang), Extensibility (provider SDK).
* Marketplace launch (Preview → Stable).

---
## 3. Package / Workspace Layout (Proposed)

```
statesmith/
  extension/              # VS Code extension (activation, commands)
  language-server/        # LSP (AST, providers, protocol wiring)
  dsl-core/               # Shared AST types, normalization, schema, printers
  dsl-sudo/               # SudoLang grammar (chevrotain) + converter
  engine-bridge/          # PowerShell child process bridge + JSON contracts
  ai-mcp/                 # MCP server implementation (tools + schema validators)
  webview-ui/             # Svelte 5 app(s) (Vite build)
  shared/                 # Logging, telemetry, config loader, util libs
  scripts/                # Build, release, codegen (grammar -> types)
  test-fixtures/          # Sample DSL/DSC pairs, golden outputs
```

---
## 4. Dual DSL Strategy

| Aspect | Simple DSL (YAML) | SudoLang DSL |
|--------|-------------------|--------------|
| Primary Audience | Infra/YAML oriented | Exploratory / AI-assisted authoring |
| Syntax | Keyed hierarchical | Verb-first concise domain syntax |
| Parser Complexity | Low / tolerant | Medium (chevrotain grammar) |
| Round‑trip | Authoritative baseline | Derived (with annotations) |
| AI Generation | Target output form | Accepts as input & output |

Round‑trip policy: SudoLang → (AST) → Simple DSL must be deterministic. Simple DSL → SudoLang may include canonical ordering & grouping heuristics (documented).

---
## 5. AI / MCP Interaction Model

MCP Tool Contracts (draft):

| Tool | Inputs | Outputs | Notes |
|------|--------|---------|-------|
| generateConfig | specText?, sudoSnippet?, contextFiles[] | proposedDraft, rationale[], diffs[] | Chooses best starting DSL form |
| explainConfig | dslText | annotatedSegments[], summary | Inline rationale grouping |
| optimizeInstallPlan | dslText, constraints (offline?, speed bias?) | reorderedPackages[], risk[] | May propose provider changes |
| remediateDrift | desiredDsl, actualStateJson | patchDsl, diffs[], risk[] | Requires drift ingestion step |
| reverseToDsl | exportedConfigJson | dslDraft, confidenceMap | Confidence per resource |

Safety / Audit:
* All AI modifications rendered side-by-side; explicit Apply action required.
* Diff objects captured in local `.statesmith/changes/*.json` (audit trail).
* AI usage logged with event IDs; no raw config exfiltration unless user opt-in for telemetry.

---
## 6. Acceptance Criteria by Phase (Summary)

| Phase | Key Acceptance Tests |
|-------|----------------------|
| 1 | Extension activates; command generates DSC config via PowerShell; CI green |
| 2 | LSP diagnostics + completions functional; golden test parity >= 95% lines |
| 3 | SudoLang parse & convert; round‑trip tests pass; grammar documented |
| 4 | MCP server responds to all tools; AI panel diff apply flow works |
| 5 | Graph view loads <1.5s; reverse import confidence map displayed |
| 6 | JS engine handles 60% of calls (presence/plan) with parity tests |
| 7 | Performance budgets met; security review checklist complete; marketplace publication |

Performance Budgets (Phase 7):
* Completion latency P95 < 150 ms (warm parse cache).
* Initial webview load (cold) < 2000 ms; subsequent < 800 ms.
* AI round‑trip (generateConfig) < 8 s P90 (excluding remote model queueing) or progress updates every 1.5 s.

---
## 7. Risk Register (Active)

| Risk | Impact | Phase | Mitigation |
|------|--------|-------|------------|
| Parser divergence across DSLs | Confusing diagnostics | 3 | Unified AST + golden corpus tests |
| AI hallucinated unsafe commands | Misconfiguration risk | 4 | Strict schema validation + allowlist of resource types |
| PowerShell bridge flakiness | UX instability | 1–2 | Structured timeout/cancellation + retry with backoff |
| Performance regressions LSP | Editor sluggishness | 2 | Incremental parsing + parse cache invalidation strategy |
| SudoLang ambiguity | Parsing errors | 3 | Grammar conflict tests + disambiguation tokens |
| MCP network / model availability | Feature degradation | 4 | Local fallback (synthetic heuristics) + clear status messaging |
| Security (command injection) | Execution compromise | All | Escaped arguments, explicit execution consent, path sanitation |

---
## 8. Telemetry & Privacy (Draft Policy)
* Opt‑in toggle: `statesmith.telemetry.enabled` (default false until Beta).
* Event categories: `lsp.performance`, `ai.invocation`, `bridge.exec`, `webview.load`.
* No raw DSL or secrets; hashed resource names for frequency counting.
* Local audit log for AI modifications retained 30 days (user configurable).

---
## 9. Release Tracks
* Preview (Phases 1–4): frequent minor bumps (0.3.x – 0.6.x).
* Beta (Phases 5–6): feature freeze except perf/security (0.9.x).
* Stable 1.0.0 (Post Phase 7): semantic versioning; deprecation policy (N+2 minors) for DSL changes.

---
## 10. Updated Checklist (Live)

Legend: [ ] pending, [~] in progress, [x] done

**Last Updated:** January 15, 2026  
**Status Summary:** Phase 1-2 foundations (parsers) complete. LSP integration is critical path.  
**See:** [ROADMAP-ANALYSIS.md](ROADMAP-ANALYSIS.md) for detailed status assessment.

### Foundation & Scaffolding (~95% Complete)
* [x] Rebrand to StateSmith (PowerShell core)
* [x] Extension activation + basic commands (4 registered)
* [x] Extension package.json + TypeScript build pipeline
* [x] Webview framework (resource graph panel)
* [ ] PowerShell bridge contract (JSON schema v1) ← **HIGH PRIORITY**

### Parsing & LSP (~40% Complete - CRITICAL PATH)
* [x] Simple DSL tolerant parser (DSL001-DSL010 diagnostics)
* [x] SudoLang Chevrotain parser (5 passing tests)
* [x] Unified AST design (Document/Block/Package hierarchy)
* [ ] **LSP server setup** ← **START HERE**
* [ ] **Real-time diagnostics publishing** ← **CRITICAL**
* [ ] **Completions provider (keys, methods, package IDs)** ← **CRITICAL**
* [ ] Golden tests (simple → DSC YAML corpus)
* [ ] Performance instrumentation
* [ ] Hovers (package info, method docs)
* [ ] Code actions (add packages key, expand string → object, remove unknown field)
* [ ] Format provider (canonical ordering, idempotent)

### SudoLang DSL (~70% Complete)
* [x] Grammar spec document (DSL-SPEC.md)
* [x] Chevrotain implementation (install/ensure statements)
* [x] Test suite (5 core scenarios passing)
* [ ] Round‑trip converters (Simple ↔ SudoLang)
* [ ] Round‑trip tests with lossiness detection
* [ ] Lossiness report generator

### AI / MCP (~0% Complete - DEFERRED TO POST-MVP)
* [ ] MCP server scaffold
* [ ] Tool: generateConfig
* [ ] Tool: explainConfig
* [ ] Tool: optimizeInstallPlan
* [ ] Tool: remediateDrift
* [ ] Tool: reverseToDsl
* [ ] Diff preview UI & audit log

### Visualizations (~20% Complete)
* [x] Resource graph webview (basic radial layout)
* [x] Auto-refresh on document change (debounced)
* [x] Diagnostic display in webview
* [ ] **ECharts integration** (currently placeholder)
* [ ] **Node click → reveal source location**
* [ ] Provider grouping visualization
* [ ] Drift dashboard webview
* [ ] Reverse explorer
* [ ] AI design canvas

### Engine Evolution (~0% Complete - DEFERRED TO PHASE 6)
* [ ] JS provider abstraction (winget/choco/msi)
* [ ] Install plan optimizer
* [ ] Caching/offline manager
* [ ] Optional Deno experiment flag

### Quality & Ops (~10% Complete)
* [x] Test infrastructure (node:test framework)
* [x] SudoLang parser tests (5 passing)
* [ ] **Simple parser tests** ← **HIGH PRIORITY**
* [ ] **Golden test corpus** (6-10 representative configs)
* [ ] LSP integration tests
* [ ] Webview tests
* [ ] E2E smoke tests
* [ ] Test coverage ≥80% statements
* [ ] Telemetry (opt‑in) & redaction check
* [ ] Security checklist & sandbox prompts
* [ ] Performance budgets enforced (CI gating)
* [ ] Documentation suite (User, DSL Spec, AI Safety)
* [ ] Marketplace publish (Preview)
* [ ] 1.0.0 Release

---
## 11. Deprecations & Compatibility
* PowerShell module remains supported until ≥ 1 minor after 1.0.0 extension release.
* Mark naive YAML parsing functions as internal (already done) – replaced by robust parsers.
* Provide migration guide: Simple DSL ↔ SudoLang, plus AI-assisted conversion examples.

---
## 12. Open Design Questions (To Resolve Early)
1. Should SudoLang support inline conditionals (platform filters) in v1 or defer? (Default: defer to post-1.0)
2. Do we bundle a lightweight local model (for offline suggestions) or rely solely on external MCP endpoints? (Default: start external, design interface for local).
3. Graph dependencies: infer only or allow explicit `dependsOn` in DSL? (Default: allow explicit optional key to avoid over-inference errors.)

---
## 13. Contribution Guidelines (Forthcoming)
Will define standards for:
* AST change process & versioning
* Adding new DSL directives (feature flags + spec PR)
* AI tool contract evolution (semantic version headers)

---
## 14. Next Immediate Actions
1. Scaffold monorepo + extension skeleton.
2. Define JSON bridge schema (PowerShell invocation contract).
3. Draft SudoLang grammar v0 (non-executable doc) before implementation.
4. Establish golden test corpus (collect 6–10 representative configs).
5. Implement minimal tolerant parser (Phase 2 start).

---
This roadmap supersedes prior “clean stable release” module-centric plan. Historical material retained in version control history for reference.


---
## 15. Status Update (January 2026)

**Current Implementation Status:** ~15-20% complete toward 1.0. See [ROADMAP-ANALYSIS.md](ROADMAP-ANALYSIS.md) for comprehensive assessment.

### What's Working
- ✅ PowerShell module (mature, production-ready)
- ✅ VS Code extension scaffold (commands, activation, webview)
- ✅ Dual DSL parsers (Simple YAML + SudoLang with Chevrotain)
- ✅ Unified AST design with diagnostics
- ✅ Resource graph webview (basic visualization)
- ✅ Test framework (5 SudoLang tests passing)

### Critical Path (Next 3-4 Weeks)
1. **LSP Integration** ← START HERE
   - Wire up language server/client
   - Publish real-time diagnostics to Problems panel
   - Implement completions for keys, methods, package IDs
   
2. **Testing Infrastructure**
   - Add golden test corpus (6-10 representative configs)
   - Simple parser unit tests
   - Round-trip validation tests

3. **PowerShell Bridge**
   - Define JSON contract schema
   - Connect generateConfig command to PowerShell module
   - Error handling and timeout management

4. **UI Polish**
   - ECharts integration for graph
   - Node click → reveal source
   - Formatter + 3 code actions

**MVP Delivery Target:** 3-4 weeks  
**1.0 Release Target:** 7-8 weeks  
**Full Roadmap (with AI):** 6-7 months

### Strategic Decision
AI/MCP features (Phase 4-7) are **explicitly deferred** until after MVP ships. This focuses effort on core value delivery and reduces scope risk.
