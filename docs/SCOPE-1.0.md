# Pedantic 1.0 Scope & Acceptance (Freeze Draft)

> Purpose: Establish a frozen, minimal yet valuable 1.0 release definition focused on authoritative authoring, validation, and visualization — intentionally deferring advanced AI orchestration and deep engine re‑writes.

## 1. Vision Snapshot

Deliver a VS Code extension that lets users author Desired State configurations in either a Simple YAML DSL or a concise SudoLang variant, receive deterministic diagnostics, format & convert between dialects, visualize package resources, and package the tool reliably.

## 2. In-Scope (Must for 1.0)

| Area | Capability | Notes |
|------|------------|-------|
| Parsing | Simple DSL full structural + semantic validations (DSL001–DSL010, DSL099) | Additional semantic checks allowed if low-risk |
| Parsing | SudoLang grammar subset → unified AST | No advanced conditionals or platform filters yet |
| Conversion | Round‑trip Simple ⇄ SudoLang where lossless | Emits DSL009 for lossy cases |
| Diagnostics | Real-time via LSP publish | Severity ordering + code stable |
| Editor Features | Completions, hovers, at least 3 code actions | Add packages key, expand string → object, remove unknown field |
| Formatting | Canonical formatter (Simple DSL) + convert-to-DSL command | Idempotent guarantee |
| Visualization | Resource graph webview (ECharts, local vendored) | Node click → reveal in editor |
| Performance | Instrumentation + budget checks (parse & completion) | Budget doc & CI threshold gating |
| Packaging | VSIX build pipeline + CI workflow | Reproducible, version stamped |
| Documentation | Spec v1.0, README quickstart, CHANGELOG, CONTRIBUTING | Spec/code parity required in CI |
| Security | Workspace trust gating + executable path validation | No remote code fetch, CSP locked webviews |
| Tests | Fixture corpus + golden tests + coverage target | 80% lines / 90% critical paths |
| Risk Management | Risk register & mitigation owners | Updated before RC |

## 3. Should (Nice-to-Have if Time Allows)

| Area | Capability | Rationale |
|------|------------|-----------|
| Code Actions | Normalize duplicate names, convert dialect both ways | Improves polish |
| Graph | Basic grouping (provider clusters) | Visual clarity |
| Telemetry | Opt‑in anonymous perf metrics | Feedback loop |
| Formatter | SudoLang pretty-printer | Symmetry; can slip |
| Lossiness Report | Structured JSON export | Aids automation & AI |

## 4. Explicitly Deferred (Post‑1.0)

- AI / MCP tool suite (generateConfig, optimizeInstallPlan, etc.)
- Drift dashboard & reverse engineering view
- Advanced provider strategy scoring & JS engine port
- Offline AI / local model integration
- Platform conditional expressions in SudoLang
- Dependency inference beyond simple sequential order

## 5. Non-Goals

- Full DSC execution engine replacement
- Remote resource fetching or plugin runtime loading
- Multi-workspace orchestration / graph merging

## 6. Acceptance Criteria (All Must Pass)

### Functional

1. Parse both dialects without crashes (malformed input yields deterministic diagnostics).
2. Round‑trip (SudoLang → Simple → SudoLang) preserves ≥ 95% of constructs without DSL009; remaining cases documented.
3. Three mandatory code actions operate correctly on sample documents.
4. Formatter second run produces zero diff (idempotent) on fixture corpus.
5. Graph webview loads within performance budget and node selection reveals corresponding source.

### Quality & Reliability

1. Test suite: ≥ 80% statement coverage overall; parser & converters ≥ 90% branch coverage.
2. No unhandled promise rejections during end-to-end smoke run.
3. All diagnostic codes referenced in spec; CI fails if drift detected.

### Performance

1. Simple DSL parse (200 lines) P95 < 40 ms; SudoLang parse (200 lines) P95 < 55 ms (local benchmark script).
2. Completion request after warm parse P95 < 150 ms.

### Security & Safety

1. Executable overrides rejected if path is unsafe (relative traversal, non-approved pattern).
2. Generation / execution commands hard‑blocked in untrusted workspace.
3. Webview CSP forbids remote scripts; only hashed or nonce local bundles.

### Packaging & Distribution

1. VSIX artifact reproducible (hash stable ignoring timestamp metadata).
2. CHANGELOG entry for 1.0 enumerates added/changed/removed compared to v0.1 draft.
3. Version bump procedure executed (spec + package.json + tags).

### Documentation

1. README: quickstart (< 90 seconds), feature matrix, troubleshooting.
2. CONTRIBUTING: build, test, add diagnostic/code action guidelines.
3. Spec at 1.0 matches implemented grammar & diagnostics.

## 7. Freeze & Change Control

- Scope Freeze Trigger: Creation + merge of this file to main.
- Post-freeze additions require: Issue labeled `scope-exception` + approval from maintainer + updated risk register.
- Any new diagnostic code post-freeze must be behind a feature flag or deferred to 1.1.

## 8. Risk Gates (Blocking Conditions)

| Risk | Gate Condition | Resolution Path |
|------|----------------|-----------------|
| Performance regression | Parse/completion > 20% over budget | Optimize or reduce SudoLang features subset |
| Grammar ambiguity | Chevrotain conflicts unresolved > 2 days | Reduce grammar surface (defer feature) |
| Coverage shortfall | < 70% statements two weeks pre‑RC | Add focused tests; drop non-critical code paths |
| Security finding | Exec path bypass or CSP violation | Patch & add regression test before release |

## 9. Timeline (Indicative Sequence)

| Week | Focus | Outputs |
|------|-------|---------|
| 1 | SudoLang grammar + AST | Grammar, initial CST→AST, failing tests allowed early |
| 2 | Round‑trip + fixtures | Conversion + golden corpus |
| 3 | LSP skeleton + diagnostics stream | Live diagnostics, completions stub |
| 4 | Code actions + formatter | 3 required actions, idempotent format |
| 5 | Graph (ECharts) + performance instrumentation | Interactive graph, timing logs |
| 6 | Packaging CI + security hardening | VSIX, path validation, trust checks solid |
| 7 | Coverage uplift + docs + polishing | Tests, README, spec 1.0, CHANGELOG |
| 8 | RC soak & release | Performance re-check, tag 1.0.0 |

## 10. Test Strategy (Summary)

- Unit: parser modules, converters, formatter, diagnostic utilities.
- Integration: LSP end-to-end (fixture open → diagnostics), code actions application.
- Webview: Graph serialization shape + smoke load (DOM checks).
- Performance: Node script measuring median/P95 across N iterations.
- Security: Path validation negative tests, CSP header presence.

## 11. Performance Budgets (Initial Targets)

| Metric | Budget | Enforcement |
|--------|--------|-------------|
| Simple parse 200 lines P95 | < 40 ms | Benchmark CI job fail |
| SudoLang parse 200 lines P95 | < 55 ms | Benchmark CI job fail |
| Completion P95 (warm) | < 150 ms | Benchmark CI job warn @ >140, fail @ >170 |
| Graph first paint | < 1500 ms | Manual + telemetry (optional) |

## 12. Security Checklist (1.0)

- [ ] Workspace trust gating verified
- [ ] Executable path whitelist/validation tests
- [ ] No dynamic eval / Function constructors
- [ ] Webview CSP: script-src `nonce-<nonce>` no remote origins
- [ ] Dependency license & supply audit (basic)

## 13. Out-of-Scope Clarifications

- No remote AI calls unless behind experimental flag (excluded here)
- No telemetry enabled by default (opt-in only if implemented)
- No DSC execution scheduling / orchestration layer

## 14. Release Readiness Checklist (Roll-Up)

| Item | Status |
|------|--------|
| All acceptance criteria satisfied |  |
| Coverage report meets thresholds |  |
| Performance benchmarks recorded & archived |  |
| Security checklist all checked |  |
| Spec & README updated to 1.0 |  |
| CHANGELOG entry drafted & approved |  |
| Tag & package produced (dry run) |  |
| Final manual smoke test pass |  |

## 15. Glossary

- **AST**: Abstract Syntax Tree (canonical unified model)
- **Lossiness**: Information not representable identically when converting dialects
- **Heuristic Diagnostic**: Advisory code (e.g., DSL099) that does not block execution
- **Round‑trip**: Convert A→B→A with semantic equivalence and ordering tolerance

---
*Edits beyond typo fixes require scope-exception approval once merged.*
