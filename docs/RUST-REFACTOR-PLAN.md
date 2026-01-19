# Rust Replatform Blueprint (Pedantic / Simple DSC)

## Goals
- Preserve project tenets: praxis logic (practical, testable), reactive/functional style, idempotence first, and strong typing to prevent drift/bugs.
- Deliver Ansible-like ergonomics via `dsc.noun.verb`, powered by DSC v3 documents, with check/diff semantics.
- Make templating a first-class capability using `minijinja` (critical module).
- Provide a single Rust core that can serve the VS Code extension (Node) via napi-rs and future WASM targets.

## Architecture (Rust-centric)
- **crate `pedantic-core`**: pure library, no IO, functional pipeline: parse → normalize → project → render.
  - Parsing: Simple DSC YAML → strongly typed AST; later SudoLang → same AST.
  - Mapping: load `docs/ansible-mapping.yaml` to translate `dsc.noun.verb` to resource intents.
  - Validation: type-checked structures; rich diagnostics with source spans.
  - Idempotence helpers: compute desired vs current, expose `Test`-like dry runs.
  - Rendering: emit DSC v3 JSON/YAML documents.
  - Templating: `minijinja` for `dsc.file.template`, producing content and diff summaries.
- **crate `pedantic-node`**: napi-rs binding exposing safe, typed APIs to the TS extension (convert/validate/test, render template, diff).
- **crate `pedantic-cli` (optional)**: thin CLI for local use and CI (generate/test/format).
- **FFI contract**: mirror existing bridge contract; versioned; JSON payloads; deterministic outputs for golden tests.

## Functional + Reactive Principles
- Pure functions for parse/validate/normalize/project; no hidden global state.
- Deterministic outputs given inputs; leverage immutable data structures where practical.
- Reactive hooks: surface structured events (parse start/end, diagnostics, timing) that the extension can observe.
- Idempotence: every operation supports dry-run (`check`) and produces diff metadata when applicable.

## Templating (Critical Path)
- `dsc.file.template`: render with `minijinja`, expose variables from the DSL, optional defaults, and strict mode for undefined vars.
- Diff: compute textual diff (unified) and checksum before/after; emit in diagnostics for the extension.
- Security: sandbox templates (no file IO), allow controlled filters; document allowed filters.

## Type Safety & Diagnostics
- Use `serde` + `schemars` for config shapes; `miette`/`ariadne` style spans for friendly errors.
- Strong enums for verbs/nouns; no stringly-typed dispatch internally.
- Validation layers: schema validation → semantic validation (e.g., template requires `src` & `dest`).

## Interop with existing PowerShell/DSC
- Output DSC v3 documents consumed by existing PS DSC engine; keep PS resources for apply/reverse.
- Keep bridge plumbing: Node (extension) → napi binding → Rust core → produce DSC doc; PowerShell still executes DSC where needed.

## Testing Strategy
- Golden fixtures: reuse `test-fixtures/` and add Rust-side golden tests for parse/project/render (including template outputs).
- Property tests for idempotence (input -> render -> parse -> render should stabilize).
- Integration tests for template diff, package/service/file scenarios.

## Incremental Delivery Plan
- Milestone 1: Scaffold `pedantic-core` with Simple DSC parser, mapping loader, DSC render, and minijinja template support; add golden tests.
- Milestone 2: napi binding (`pedantic-node`) exposing convert/validate/template APIs; wire VS Code extension to use it behind a feature flag.
- Milestone 3: Add SudoLang parsing to Rust, extend mapping coverage (line/block, git, http, archive, schedule).
- Milestone 4: Performance hardening, more DSC resources, CLI polish, and full replacement of TS projection logic.

## Alignment Checklist
- Praxis logic: every feature backed by tests, fixtures, and measurable diagnostics.
- Reactive: structured events for the extension to visualize progress and drift.
- Functional: pure transformations, data-in/data-out; avoid side effects in core.
- Idempotence: check/diff everywhere; stable renders.
- Type safety: enums/newtypes instead of strings; schema-derived validation.
