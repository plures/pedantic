# Scenario Testing & Reporting (Design)

Goal: provide a native, Molecule-style experience for validating Simple DSC configs with integrated reporting. Scenarios are first-class YAML, executed via the Rust core/CLI, and yield templated Markdown/HTML after-action reports by default, with user-customizable templates.

## Objectives
- **Integrated**: live in-repo alongside configs; run with the same planner/runtime.
- **Deterministic & repeatable**: pure planning, explicit phases, stable outputs/artifacts.
- **Actionable reporting**: default Markdown (and optional HTML) reports with diffs, outcomes, and links to artifacts; templates are minijinja.
- **Customizable**: scenario YAML controls matrix, phases, asserts, and reporting templates/partials.

## Scenario YAML shape (proposal)
```yaml
name: webserver-smoke
matrix:
  hosts: ["win2019", "win2022"]
  vars:
    web_port: [80, 8080]
phases:
  prepare:
    - apply: examples/installGit.yaml
  converge:
    - apply: examples/simple-install.dsc.yaml
  verify:
    - assert: { type: command, command: "curl -s http://localhost:{{ web_port }}", contains: "OK" }
    - assert: { type: file, path: "C:/inetpub/wwwroot/index.html", contains: "hello" }
  destroy:
    - apply: examples/simple-install.dsc.yaml
      check: true
asserts:
  - fact: web_port
    expect: 80
report:
  template: builtin:markdown/basic
  format: [markdown, html]
  artifacts:
    - path: logs/**
    - path: diffs/**
```

### Notes on semantics
- **Matrix expansion**: cartesian product of hosts/vars produces scenario instances; facts include `matrix.*` vars.
- **Phases**: `prepare`, `converge`, `verify`, `destroy` are optional; each entry can be `apply` (run plan), `command`, or `assert`.
- **Asserts**: built-ins (command output, file existence/content/hash, HTTP check, fact equality, resource state) plus template-able custom assertions.
- **Check mode support**: `check: true` runs plan in check/preview; diffs captured for reporting.
- **Idempotence hint**: `destroy` defaults to no-op unless provided; optional `reset` step to rollback.

## Execution model
1. **Plan**: parse scenario YAML, expand matrix, build per-instance execution plan.
2. **Run phases** in order; each step uses the Rust core planner/runtime. Facts/registers flow across steps within a scenario instance.
3. **Capture telemetry**: task outcomes, diffs, stdout/err, timings, notify/handler firings, asserts (pass/fail/skip).
4. **Aggregate results**: per-instance summaries plus scenario-level rollup (counts: ok/changed/skipped/failed/assert failures).
5. **Render report**: feed aggregated data into minijinja template. Built-ins: `markdown/basic` and `html/basic`. Users can point to repo templates/partials. Outputs to `reports/<scenario>/<timestamp>.md` (and `.html` if requested).
6. **Artifacts**: copy referenced artifacts (logs/diffs) into the report folder with relative links.

## Data shapes (sketch)
```rust
struct ScenarioSpec { name, matrix, phases, asserts, report }
struct ScenarioInstance { id, vars, host, phases: Vec<PhaseStep> }
struct PhaseStep { kind: Apply|Command|Assert, check: bool, spec }
struct AssertResult { name, status: Pass|Fail|Skip, details, artifacts }
struct ScenarioReportModel { summary, instances: Vec<InstanceReport>, artifacts }
```

## Reporting semantics
- **Default Markdown**: sections for Summary, Matrix, Phase timelines, Task outcomes, Asserts, Diffs (collapsed), Logs/Artifacts links.
- **HTML (optional)**: same data with collapsible panels; generated via minijinja + lightweight CSS.
- **Custom templates**: scenario YAML `report.template` accepts `builtin:<name>` or path to `.j2`/`.mj` in repo; supports partials/includes.
- **Theming/branding**: template variables allow logo/title/footer; defaults are repo name/date.

## CLI and VS Code extension hooks
- CLI: `pedantic scenario run path/to/scenario.yaml [--matrix host=win2022 --var web_port=8080] [--format markdown,html] [--out reports/]`.
- VS Code: command to run current scenario, stream live status, and open the rendered Markdown; webview for HTML flavor.

## Integration points with existing work
- Reuse `TaskOutcome/TaskResult` for diffs/changed/failed/skipped.
- Use `when`/`register`/facts across steps; assertions can read `register` data.
- Reporting templates consume the same structured data exposed via Node binding for UI.

## Open questions / next iterations
- How to provision/tear down hosts (delegated to harness vs. built-in adapters?).
- Parallelism control per matrix row; max concurrency and fail-fast strategy.
- Pluggable assertions (custom Rust or JS hooks?).
- Secret management for scenario vars (vault integration?).
```
