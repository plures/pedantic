# Reporting Pipeline (Design)

Goal: generate after-action reports for scenario runs (and eventually ad-hoc runs) using minijinja templates. Default outputs are Markdown (and optional HTML) with diffs, outcomes, asserts, and artifact links.

## Inputs to reporting
- Scenario spec (name, matrix, phases, report config)
- Scenario run results (per-instance): tasks with outcomes (ok/changed/skipped/failed), handler firings, diffs, check-mode notes, asserts results, timings.
- Artifacts: logs, diffs, captured stdout/stderr, optional user-provided files.

## Data model (in core)
- `ScenarioReport` → rollup of `ScenarioInstanceReport` (per matrix row).
- `ScenarioInstanceReport` → phases, asserts, task outcomes, vars/host.
- `TaskOutcome` already holds skip/error/when/diff/changed; we’ll serialize these for reports.
- See `rust/pedantic-core/src/lib.rs` exports for report structs.

## Template flow
1. Collect run data → build `ScenarioReport` (JSON-serializable).
2. Choose template: `report.template` from scenario spec (`builtin:markdown/basic`, `builtin:html/basic`, or path to `.j2`/`.mj`).
3. Render with minijinja using shared environment (same filters/tests as other templating).
4. Write outputs to `reports/<scenario>/<timestamp>.md` (and `.html` if requested).
5. Copy artifacts into the report folder and rewrite links to be relative.

## Built-in templates (MVP)
- `builtin:markdown/basic`: sections for Summary, Matrix, Instances, Phases, Tasks, Asserts, Diffs (collapsed), Artifacts.
- `builtin:html/basic`: same content, minimal CSS for collapsible details.

## Customization knobs
- Scenario YAML `report` section:
  - `template`: builtin or path
  - `format`: ["markdown", "html"] (default markdown)
  - `artifacts`: glob paths to include
- Branding: template variables include `title`, `subtitle`, `logo_url` (if provided by user/env).

## Required filters/tests in template env
- `tojson`, `default`, `length`, `sort`, `unique`, `flatten`, `regex_search`, `regex_replace`, `b64encode`, `b64decode`.
- Safe helpers: `relpath` (compute relative artifact links), `truncate`, `nl2br` (for HTML template only).

## CLI/extension hooks
- CLI: `pedantic scenario report <run.json> --format markdown,html --template builtin:markdown/basic` (run file produced by runner).
- VS Code: command to view latest report in Markdown preview/webview (HTML) with live links to artifacts.
- Node binding: exports `expand_scenario_yaml` and `render_scenario_report` for the extension/webviews to drive matrix expansion and rendering without shelling out.

## Open items
- Define `run.json` schema (wire up runner to emit). 
- Add render helper in core that accepts `ScenarioReport`, template id/path, and format → returns rendered string + written file path.
- Add artifact copier/rewriter utility.
- Add tests: render with builtin template; ensure relative links; ensure filters available.
