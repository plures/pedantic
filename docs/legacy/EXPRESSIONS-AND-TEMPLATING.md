# Expressions & Templating (minijinja)

We use a single expression engine (Jinja via `minijinja`) for templating and logic paths (`when`, `changed_when`, `failed_when`, and future assertions). This document spells out scopes, syntax, and intended filters/tests/lookups.

## Where Jinja is used
- **Templates**: `render_template` for files/content.
- **Conditions**: `when` expressions (already wired), `changed_when`/`failed_when` (parsed; execution forthcoming), future `until`/asserts.
- **Scenario/reporting**: planned for assertions and Markdown/HTML report rendering.

## Syntax
- Jinja expressions (no statements in conditions). Examples: `foo == 'bar'`, `item > 3 and env == 'prod'`, `result.changed and (result.rc == 0)`.
- Truthiness follows Jinja rules; undefined variables error (strict) in conditions to catch typos. Templates can run strict or lenient per call.

## Scopes & variables
- **Facts**: the fact map is the primary scope; loop vars (`item` or custom `loop_var`) are injected during expansion.
- **Result**: for overrides (`changed_when`/`failed_when`) we will expose `result` (task result data/diffs) in the same scope.
- **Future**: `register` bindings, magic vars, inventory/hostvars will extend the scope.

## Filters/tests/lookups
- **Current**: core Jinja/minijinja built-ins only (no custom filters/tests yet).
- **Planned curated set** (to be registered globally and reused across templates/conditions):
  - General: `default`, `length`, `upper`, `lower`, `trim`, `replace`, `split`, `join`, `unique`, `flatten`, `first`, `last`, `sort`.
  - JSON/encoding: `tojson`, `b64encode`, `b64decode`, `urlencode`, `urldecode`.
  - Regex: `regex_search`, `regex_replace`.
  - Collections: `selectattr`, `map`, `sum`.
  - Tests: `defined`, `undefined`, `string`, `number`, `mapping`, `sequence`, `truthy`, `falsy`.
- **Lookups (gated/safe)**: `env`, `vars`, `file` (with repo-root sandbox), possibly `secret`/`vault` later. These will be opt-in and side-effect free.

## Behavior choices
- **Strictness**: Conditions run strict; templates configurable. Prefer strict by default to avoid silent typos.
- **Caching**: Expression strings will be compiled and cached to avoid re-parsing per task instance.
- **Determinism**: Only pure filters/tests/lookups; no IO in conditions unless explicitly allowed (e.g., gated `env`).

## Upcoming work
- Register the curated filter/test set in the shared `Environment` used for templates and expression evaluation.
- Wire `changed_when`/`failed_when` to evaluate with Jinja expressions and `result` in scope.
- Document any added lookups/filters inline in code and here; keep the set small, deterministic, and test-covered.
