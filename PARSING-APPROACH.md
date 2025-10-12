# Parsing Approach Decision (v0.1)

## Decision Summary

Adopt a **hybrid parsing strategy**:
- **Simple DSL (YAML dialect)**: Structural extraction via a tolerant structural walker over a standard YAML parse (library: `yaml`). Fallback diagnostics when the library is absent (offline / dependency not installed yet). No full grammar—only whitelisting of key paths for stability and forward compatibility.
- **SudoLang DSL**: Grammar-based parsing using Chevrotain (LL(k)) to enable precise incremental parsing, rich diagnostics, and future grammar evolution (groups, file/service verbs). A lightweight heuristic extraction layer exists initially until the Chevrotain runtime dependency is available (current stub state).

## Context & Constraints

| Constraint | Impact |
|-----------|--------|
| Need fast iteration pre-network / offline (cannot reliably `npm install`) | Must degrade gracefully without runtime parser deps |
| Two dialects with different syntactic complexity | Avoid over-engineering Simple DSL; invest in formal grammar for SudoLang |
| LSP performance targets (edit reparse <15ms typical) | Keep Simple path O(n) YAML node scan; design SudoLang tokens lean |
| Future AI tooling needs structured AST + round-trip fidelity | Unified canonical AST layer defined in `ast.ts` |
| Security: no code execution during parsing | Pure text → data only; execute later with explicit consent |

## Alternatives Considered

| Option | Pros | Cons | Reason Not Chosen (if rejected) |
|--------|------|------|---------------------------------|
| Hand-written regex for Simple DSL | Zero deps, fast | Fragile for YAML edge cases (indent, quotes) | Rejected (maintenance risk) |
| Full Chevrotain for BOTH dialects | Uniform infra | Overkill for YAML subset; added friction | Rejected for Simple DSL |
| nearley for SudoLang | Earley: flexible | Slower, less guided errors vs Chevrotain | Chevrotain superior diagnostics |
| tree-sitter binding | Excellent incremental | Native build/complex distribution; slower bring-up | Defer (future optional) |
| Single unified meta-grammar | Potential reuse | Different surface styles; slower delivery | Defer until >v1 |

## Detailed Approach

### Simple DSL Flow
1. Attempt dynamic require of `yaml` module.
2. On success: parse → JS object → validate allowed top-level (`dsc.install`).
3. Normalize packages (string → object) + canonicalize names.
4. Emit diagnostics via codes DSL001–DSL008; structural / semantic only.
5. Build `InstallBlock` with ordered packages.
6. If YAML module missing → emit DSL010 once (graceful degradation).

### SudoLang Flow

1. Tokenization (Chevrotain) with explicit tokens for verbs (`install`, `ensure`, `via`, `version`).
2. Parse to CST; transform to AST (future step) with recovery to gather multiple diagnostics.
3. Current interim: heuristic linear scan to unblock early experimentation (no dependency runtime yet).
4. Later: add incremental reparse windows (line-level) using token diffing.

## Incremental Parsing Strategy

| Dialect | Strategy | Notes |
|---------|----------|-------|
| Simple | Re-parse whole doc (fast for typical <300 lines) | YAML parse cost acceptable; can later optimize by shallow-diff on unchanged prefix/suffix |
| SudoLang | Tokenize entire doc; reuse unchanged token spans for minor line edits (planned) | Chevrotain provides token stream; will implement diff buffer later |

## Performance Targets & Early Budget

| Step | Target | Rationale |
|------|--------|-----------|
| Simple parse (200 lines) | <40ms | YAML library typical ~5–15ms; extra normalization cheap |
| SudoLang parse (200 lines) | <55ms | LL(k) overhead + CST build |
| Simple incremental (small edit) | <15ms | Full reparse acceptable |
| SudoLang incremental (line edit) | <20ms | Token diff + partial rebuild |

## Error Handling Philosophy

- Collect and continue: never throw in normal syntax errors → produce as many diagnostics as possible.
- Single root failure (missing `dsc.install`) still returns doc with diagnostics for LSP display.
- Unknown future keys produce warnings (forward-compatible evolution path) once feature-flagging begins.

## Security Considerations

- Parsing never resolves external includes, executes commands, or loads scripts.
- Executable override fields are inert strings until explicit execution phase (separate trust gate).

## Tooling & Code Layout

| File | Purpose |
|------|---------|
| `extension/src/dsl/ast.ts` | Canonical AST types + helper functions |
| `extension/src/dsl/simpleParser.ts` | Structural YAML-based parser with dynamic dependency fallback |
| `extension/src/dsl/sudoParser.ts` | SudoLang Chevrotain skeleton + interim heuristic extraction |
| `extension/src/types/*-stub.d.ts` | Temporary type stubs when dependencies absent |

## Migration Plan (Parser Maturity Levels)

| Level | Simple DSL | SudoLang | Trigger to Advance |
|-------|------------|----------|--------------------|
| 0 (current) | Structural walk + diagnostics | Heuristic scan | Dependency stability |
| 1 | Add duplicate detection (done) | Chevrotain full grammar + diagnostics | Install success; tests |
| 2 | Incremental diff optimization (optional) | Incremental token diff | Performance profiling |
| 3 | Round-trip fidelity annotations | Round-trip + lossy warnings (DSL009) | AST converters merged |
| 4 | Configurable experimental features gating | Extended verbs (service/configure) | Feature flags design |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Dependency install blocked (offline) | No SudoLang parse | Heuristic scan + stubs (current) |
| YAML parser size/perf regressions | Slower completions | Option to swap to minimal subset parser later |
| Grammar creep / complexity | Maintenance overhead | Strict version gating + spec alignment PR reviews |
| Incremental parse complexity delays | Slower LSP edits | Accept whole-doc parse until perf threshold exceeded |

## Acceptance Criteria (Select Parsing Approach Task)

- [x] Canonical AST defined and versioned.
- [x] Simple DSL parser implemented with diagnostics codes.
- [x] SudoLang parsing path stubbed (tokens + heuristic extraction).
- [x] Decision document (this file) capturing rationale & trade-offs.
- [x] Debug parse command exposed (`statesmith.debugParse`).

## Next Steps

1. Add unit tests for normalization & diagnostics (Simple DSL) once test harness established.
2. Implement real Chevrotain CST → AST mapper after dependency install succeeds.
3. Wire diagnostics into upcoming LSP server for live feedback.
4. Add round-trip converter (SudoLang → Simple YAML) and mark lossy cases (DSL009).
5. Introduce performance timing instrumentation (dev flag) for parse durations.

---
*Owned by: Parsing Subsystem. Revisit after Chevrotain integration (Level 1) or if performance SLA breaches.*
