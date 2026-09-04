# Pedantic PX-First Refactor Plan

**Status:** proposed architecture and delivery plan
**Scope:** reorient Pedantic around PX Lang procedures, a local-first Pedantic service, and independently releasable client surfaces.
**Decision:** do not incrementally spread more policy across the PowerShell module, Rust workspace, VS Code extension, and Radix plugin. Consolidate policy, admission, lifecycle, and evidence in PX and PluresDB first; retain native and PowerShell code only for bounded effects.

## 1. Assessment: the as-built system

Pedantic is a valuable but fragmented DSC toolkit:

- The root PowerShell module is the mature user-facing DSC, cache, and remote-execution surface.
- The Rust workspace has a second domain model, DSC parser, validator, planner, imperative `praxis` rule engine, CLI, MCP server, and transport implementation.
- The VS Code extension has its own parser and a TypeScript `praxis-inspired` event/rule engine, plus direct PowerShell-bridge intent.
- The Radix plugin has its own schema, compliance store, and UI. It declares PluresDB permissions but is not backed by a shared Pedantic data/service boundary.
- The repository has no runtime dependencies or implementation for PX Lang, PluresDB, Chronos, Unum, Design Dojo, Pares Modulus, or the Svelte Tarui stack.

The consequence is three competing places for domain semantics. The existing `no-set-without-test` and draft-deployment rules are represented as imperative Rust and manifest logic rather than executable PX procedures with durable evidence. The project also has competing, stale plans: the module manifest is `0.9.0`, the extension package is `0.5.0`, and the Rust crates are `0.1.0`.

PluresLM supplies the right structural precedent, not an implementation to copy verbatim: it keeps one storage-owning service behind a stable tool/API boundary and makes plugins thin lifecycle adapters. Pedantic should use that pattern for configuration operations.

## 2. Target architecture

```text
                   PX Lang procedures and constraints
            admission | policy | lifecycle | evidence | projection
                                  |
                     Pedantic service (per user/profile)
     authenticated local API + MCP | sole PluresDB writer | Chronos writer
                                  |
          DSC effect adapter / inventory adapters / remote transports
                 Rust and PowerShell: bounded I/O, never policy
                                  |
      -------------------------------------------------------------
      |                 |                 |              |        |
Standalone app      Radix plugin       VS Code        CLI/MCP  PowerShell
Svelte + Tarui      Design Dojo        extension      client   compatibility
Unum projections    + Unum             + LSP          adapter  adapter
```

### Non-negotiable ownership rules

1. **PX owns decisions.** Every admission, state transition, eligibility decision, remediation plan, approval requirement, and evidence rule is a PX contract/procedure. No Rust, TypeScript, Svelte, or PowerShell fallback may reimplement it.
2. **The Pedantic service owns shared state.** It is the only process allowed to open the profile-scoped PluresDB store. Clients use authenticated local API/MCP calls; they do not open, copy, or mutate the same store directly.
3. **Chronos is the durable chronicle, not a log decoration.** Each accepted event and relevant PluresDB projection records causal identifiers, timestamps, actor, source, and redacted effect evidence. Timeline queries reconstruct why a configuration was or was not applied.
4. **Effects are explicit and bounded.** DSC invocation, file reads, secret lookup, SSH/WinRM, resource discovery, and package downloads occur only through declared capability adapters. An effect request requires a PX-produced authorization and returns normalized observations.
5. **The UI projects state; it does not decide it.** Unum subscribes to service projections, Design Dojo provides the app components, and Svelte/Tarui hosts the interaction. UI approval gestures create requests; PX evaluates them.
6. **Local-first is the default.** One authenticated service per user/profile supports embedded single-user operation. Remote or shared operation is a separately authorized service mode, never a silently shared database path.

## 3. Core capability modules

Organize the product by stable capabilities, each with PX contracts, PluresDB schema, Chronos events, service endpoints, fixtures, and client projections. Do not organize domain logic by UI or transport.

| Capability | PX ownership | Data and evidence | Bounded effects |
|---|---|---|---|
| Configuration lifecycle | ingest, parse-admission, validation, revision state | `config_revision`, `config_document`, source digest, diagnostics | read/write user-selected files |
| Inventory and facts | fact freshness, host identity, transport eligibility | `managed_host`, `host_fact_snapshot`, source/age | local, SSH, WinRM discovery |
| Compliance and drift | test selection, normalization, drift classification | `compliance_run`, `resource_result`, `drift_finding` | `dsc config test`, resource get/export |
| Remediation | proposal, risk classification, approval and test-before-set gate | `remediation_proposal`, `approval`, `execution_attempt` | `dsc config set` only after authorization |
| Resource catalog | mapping confidence, provenance, compatibility | `resource_capability`, cache metadata, discovery evidence | DSC resource list, gallery/cache access |
| Evidence and chronicle | redaction, retention, replay and export eligibility | Chronos timeline, evidence links, decision outcomes | safe export/import only |

The initial PX procedure set should cover `configuration_ingested`, `facts_observed`, `compliance_requested`, `compliance_observed`, `remediation_requested`, `approval_recorded`, `execution_requested`, `execution_observed`, and `evidence_recorded`. Each procedure must declare inputs, output facts/events, PluresDB writes, permitted capabilities, rejection reasons, and Chronos evidence fields.

## 4. Repository shape

Adopt a workspace with clear public contracts and independently buildable surfaces. Exact package-manager choices are a Phase 0 decision; the separation is mandatory.

```text
pedantic/
  packages/
    pedantic-contracts/        # versioned schemas, API/MCP types, error/evidence envelopes
    pedantic-px/               # PX procedures, constraints, fixtures, parser validation
    pedantic-service-client/   # generated/thin TypeScript client; no business policy
    pedantic-ui/               # shared Design Dojo composition and Unum projections only
  services/
    pedantic-service/          # authenticated profile-scoped API/MCP, sole PluresDB/Chronos owner
  apps/
    pedantic-standalone/       # local desktop app from svelte-tarui-template, Svelte 5 + Unum + Dojo
    pedantic-radix-plugin/     # thin Pares Radix extension, published through Pares Modulus
    pedantic-vscode/           # editor/LSP adapter; invokes service, never DSC directly
  crates/
    pedantic-dsc-adapter/      # DSC v3 process protocol and result normalization
    pedantic-transport/        # local/SSH/WinRM effect implementations
    pedantic-cli/              # optional client of the service contract
  compat/
    powershell-module/         # supported compatibility adapter during migration
  tests/
    contracts/ px/ integration/ task-suite/
  docs/
    adr/ architecture/ migration/
```

`plugin/`, `extension/`, `rust/`, and the root PowerShell module are migration inputs, not permanent architectural roots. Retire them only after the corresponding service-backed surface has parity for its supported workflows.

## 5. Surface responsibilities

### Standalone app

Build the primary operator experience from `svelte-tarui-template`. Use Svelte 5, `svelte-ratatui`, Unum projections, and Design Dojo components. It provides configuration review, inventory, compliance, approval, evidence timeline, and local service/profile management. It must not shell out to DSC or read PluresDB itself.

### Pares Radix plugin

Rebuild the current `plugin/` as a Modulus-submitted plugin that consumes the Pedantic service client. It supplies Radix-native pages, widgets, routes, and provenance-aware projections. Its manifest describes declared Pedantic capabilities and permissions, while its data model is a projection of service-owned schema rather than a second compliance database.

### VS Code extension

Keep document parsing and LSP diagnostics local where they are purely editorial. Route validation that affects lifecycle state, resource discovery, plans, DSC execution, and audit history through the service. Code actions submit requests and show PX-issued diagnostics/rationale; the extension never starts a PowerShell child process as a domain bridge.

### CLI, MCP, and PowerShell

`pedantic` CLI, `pedantic-mcp`, and the PowerShell module become peer service clients. The MCP surface exposes request/query operations and redacted evidence, not unconstrained `dsc` execution. The PowerShell module remains a compatibility path until the supported DSC operations have service-backed parity, then becomes a thin installer/client module.

## 6. Delivery sequence

### Phase 0 — architecture baseline and contracts

Deliver:

- ADRs for service ownership, local-profile isolation, capability model, PX authority, and retention/redaction.
- A source-of-truth capability inventory that maps every exported PowerShell function, Rust command/MCP tool, VS Code command, and Radix action to an end-state capability or explicit retirement.
- Versioned contract schemas for commands, observations, evidence, errors, approval, and API compatibility.
- A minimal PX fixture corpus and canonical parser validation in CI.

Exit gate: two existing flows (validate a DSC document; test an explicitly selected local resource) are described end-to-end with no unexplained policy owner.

### Phase 1 — PX and service vertical slice

Implement the smallest useful core: configuration ingestion, validation admission, local inventory observation, compliance request/observation, and Chronos evidence recording. Use PluresDB schema migrations and a per-user/profile service instance. Implement `test-before-set` and `validated-before-deploy` in PX only.

Exit gate: a request submitted through the service yields an explainable PX decision, normalized DSC result, PluresDB projections, and a Chronos timeline query. A rejected request produces a stable rejection code and no DSC effect.

### Phase 2 — remediation and capability boundary

Add PX-owned remediation proposals, risk tiers, user approvals, idempotency keys, cancellation, and execution result normalization. Move the existing Rust DSC runner and transports under the declared adapter boundary. Preserve PowerShell resource-cache behavior behind an adapter only where no stable DSC CLI equivalent exists.

Exit gate: `set` cannot be invoked without an accepted PX authorization tied to fresh test evidence; replay demonstrates the exact decision and effect outcome.

### Phase 3 — primary standalone application

Create the standalone Svelte/Tarui application from the shared UI package. Compose UI exclusively from Design Dojo and bind read models with Unum. Deliver the operator flow: select profile, inspect configuration, observe drift, review proposed remediation, approve/reject, and inspect Chronos evidence.

Exit gate: the complete local operator task works against a packaged pre-release service without direct database access or duplicated decision logic in the UI.

### Phase 4 — migrate satellite surfaces

Migrate the Radix plugin through Pares Modulus and migrate the VS Code extension to the service client. Retain local LSP syntax work, but remove direct lifecycle/execution ownership. Convert MCP, CLI, and PowerShell to the same versioned contracts.

Exit gate: each surface completes the same compliance-and-remediation scenario with equivalent PX decision identifiers and evidence; contract conformance tests prove compatibility.

### Phase 5 — compatibility retirement and distribution

Move remaining PowerShell/Rust responsibilities into compatibility/effect packages, delete duplicated in-process `praxis` engines, and stop shipping legacy roots once parity gates pass. Release independently versioned service, standalone app, Radix plugin, VS Code extension, CLI/MCP, and compatibility module from one source revision with a compatibility matrix.

Exit gate: fresh-profile installation, upgrade, rollback, offline resource-cache workflow, and inter-surface task suite pass against signed/installable artifacts.

## 7. Migration rules and guardrails

- Keep the existing PowerShell module supported until equivalent workflows have task-level evidence. Do not perform a big-bang rewrite.
- Treat DSC YAML and existing Simple/SudoLang files as import formats. The canonical operational model is the versioned Pedantic contract plus PX facts; retain source/provenance and round-trip lossiness reports.
- Do not migrate records by copying opaque state. Import through a procedure that validates source, normalizes facts, records provenance, and writes a Chronos migration event.
- Do not open the shared PluresDB database from the desktop app, extension, plugin, CLI, or PowerShell module.
- Do not add cron/polling orchestration. React to persisted events and service subscriptions; allow explicit user-initiated refresh only as an effect request.
- Do not claim PX-first status while imperative engines remain authoritative. During transition, name the legacy policy owner and provide a removal issue for each duplicate.

## 8. Quality and release gates

Every phase follows `design -> develop -> test -> pre-release -> QA -> release`:

1. **Design:** PX procedures/constraints and ADRs parse and have source-linked examples.
2. **Develop:** domain changes include PluresDB migration, Chronos event schema, client contract, and feature-ledger entry.
3. **Test:** unit, parser, contract, database-isolation, and real DSC adapter tests pass.
4. **Pre-release:** package a clean-install service and every surface under test; expose CLI/MCP or API task interfaces.
5. **QA:** run full user task suites across standalone, Radix, VS Code, CLI/MCP, and PowerShell compatibility paths. Store findings as evidence.
6. **Release:** publish only after the above gate passes; compatibility versions and reversible migration path are documented.

Required negative tests include: a client cannot open the service database; a `set` is rejected without fresh qualifying test/approval; malformed PX output cannot authorize an effect; a stale fact cannot silently permit remediation; and redaction rules hold in every Chronos/API/MCP export.

## 9. First planning backlog

1. Approve the target ownership diagram and write the five Phase 0 ADRs.
2. Inventory current public operations and create the capability-to-owner matrix.
3. Establish the workspace and `pedantic-contracts` package without moving behavior.
4. Define and validate the Phase 1 PX procedures against the canonical PX parser.
5. Build the profile-scoped service with a health endpoint, authenticated local transport, PluresDB migration, and Chronos append/query boundary.
6. Port one vertical slice: validate -> test -> evidence; do not include `set` until its PX authorization and approval chain exist.
7. Cut a pre-release and run the cross-surface task suite before widening scope.

## 10. Explicitly deferred decisions

The plan intentionally does not select a cloud deployment, multi-user tenancy model, remote PluresDB replication policy, package manager, desktop shell implementation beyond the Svelte/Tarui starting point, or a wholesale DSL replacement. Resolve each with an ADR only after the Phase 1 local-first vertical slice proves the service and PX boundaries.
