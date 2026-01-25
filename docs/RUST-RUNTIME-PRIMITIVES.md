# Runtime Primitives & Fact Flow (Rust Core)

This sketch covers how to model Ansible-like control primitives (`when`, `loop`, `group`, `group_by`, `register`, `set_fact`, `debug`) inside the Rust core while keeping DSC resource emission pure and idempotent.

## Objectives
- Separate **control/runtime** from **resource emission**: no DSC resources for control primitives.
- Maintain **functional, deterministic** transforms for planning; isolate side effects to execution adapter.
- Provide **structured facts** and **task results** for `register`/`set_fact`, and **condition evaluation** for `when`.
- Support **loop expansion** and **group scoping** without duplicating business logic.

## Data Model
- `Task`: { id, command (dsc.* or primitive), params, meta { when, loop, register, group, tags } }
- `Plan`: ordered list of `TaskInstance` (post-expansion), each with `context` (facts, item vars, group vars) and `origin` (source span).
- `FactStore`: immutable map during planning; mutable facade during execution; supports shadowing for task-local vars.
- `Result`: { changed, failed, msg, data (arbitrary JSON), diffs? } used by `register`.

## Pipeline (Planning)
1. **Parse → Tasks**: ingest DSL, produce `Task`s (including primitives).
2. **Group normalization**: inline `group`/`group_by` to annotate child tasks with group scope/vars.
3. **Loop expansion**: expand `loop` into multiple `TaskInstance`s with `item`/`item_var` injected.
4. **When filtering**: retain condition AST; evaluation happens with facts at execution time.
5. **Projection**: for resource tasks, map to DSC resources; for primitives, emit runtime op nodes.
6. **Plan output**: deterministic list; each node marked `kind: resource | runtime`.

## Execution Semantics
- **when**: evaluate Jinja expression with current `FactStore`; skip task if false (record `skipped`). Expressions share the same syntax/filters/tests as templating (minijinja expressions only, no statements), with strict undefined handling to catch typos.
- **loop**: already expanded; each instance gets `item`.
- **register**: take the `Result` of the just-executed task, bind to facts under given name.
- **set_fact**: merge provided key/values into facts (scope = play/run); deterministic overwrite.
- **group/group_by**: scoping for vars and conditions; may partition plan per host/group.
- **debug**: emit structured log; no state change.

## Handlers, status overrides, and diff/check (design)
- **Notify/handlers**: tasks may declare `notify: [handlerName...]`; handler tasks are flagged (`is_handler: true`) and collected by name (or `listen`). When any notifying task is `changed`, enqueue the handler (deduplicated, keep declaration order). Handlers run after the main task list, honoring their own `when` and status overrides. A handler itself can `notify` downstream handlers.
- **Status overrides**: add `changed_when` and `failed_when` expressions evaluated after the task result is available (including `register` data). Defaults are module-driven (`result.changed`, `result.failed`). Overrides can force `changed=true/false` or `failed=true/false` based on facts/result fields.
- **Skip semantics**: if `when` is false, mark `skipped` (no notify). If a task fails and `ignore_errors` is not set (future), stop run; otherwise continue.
- **Diff/check**: `TaskResult` carries `changed`, `diff` (list of {before, after, path, message}), and `data` (`result_json`). In check mode, modules should return predicted diffs with `changed=false` unless known safe; overrides still apply. Diffs propagate into `register` so later `when`/`changed_when` can see them.
- **Ordering/inheritance**: notify firing is per-task-instance; handlers execute once per handler name per run. `when`/overrides on handlers are evaluated at handler execution time using current facts (including registers from prior tasks).

## Type & Safety
- Expressions for `when`: restricted expression language; consider `rhai` or a small eval with serde values; reject dynamic code.
- Facts: `serde_json::Value` map; expose typed getters for common shapes.
- Results: include `checksum/diff` when available from resource operations.

## Suggested Rust Shapes (sketch)
- `enum TaskKind { Resource(ResourceSpec), Runtime(RuntimeOp) }`
- `enum RuntimeOp { When(Expr), Loop(Vec<Value>, String), Register(String), SetFact(Map), Debug(DebugSpec), Group(GroupSpec), GroupBy { key, value } }`
- `struct TaskInstance { id, kind, params, context, origin }`
- `struct Plan { tasks: Vec<TaskInstance> }`
- `struct Facts { data: Map<String, Value> }` with layered scopes.

## Idempotence & Determinism
- Planning is pure/deterministic; execution records results.
- `register` stores only the **serialized Result**, not side effects.
- `set_fact` is explicit and ordered; no implicit mutation.

## Extension/NAPI Considerations
- Expose plan/build endpoints returning JSON: tasks with kinds, expanded loops, attached `when` expressions.
- Expose execution driver later (or bridge to PowerShell) that honors runtime ops and updates facts.

## Next Implementation Steps
- Add `Task/RuntimeOp/Plan/Facts` structs to `pedantic-core`.
- Add a minimal `when` expression evaluator (pure) and serializer.
- Extend mapping/projection to tag tasks as resource or runtime based on `ansiblePrimitive`/`ansibleModule`.
- Provide a planning API: `plan(document, mapping) -> Plan` that expands loops/groups and returns annotated tasks.
- Add tests: loop expansion determinism, when filtering, register fact binding, debug no-op, group scoping.
