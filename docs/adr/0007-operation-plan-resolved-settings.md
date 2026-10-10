# ADR 0007: Operation plans carry resolved settings and provenance

## Status

Accepted.

## Context

PX resolves built-in, general, target, and plan settings after evaluating
capability safety requirements. Durable operation plans need to carry those
resolved values and their sources so consumers observe the same settings and
provenance that PX approved.

## Evidence

| Question | Evidence | Status |
| --- | --- | --- |
| Are the fields optional? | `resolvedSettings` and `resolvedSettingSources` are not in the schema's `required` list; the Rust fields default to empty maps and are omitted when empty. | Verified |
| Do old payloads remain valid? | The updated v1 schema accepts plans without resolved settings or provenance. | Verified by the operation-plan contract test |
| Can prior strict readers consume populated plans? | The v1 schema rejects unknown properties, so consumers validating with a schema that predates either field reject populated plans. | Incompatible until consumers update |
| Have all external client implementations been tested? | This repository's conformance test covers the Rust operation-plan model; downstream client behavior is not represented here. | Unknown |

## Decision

Add optional `resolvedSettings` and `resolvedSettingSources` to the v1
operation-plan contract. The values and provenance remain PX-derived; the Rust
client transports them and does not make policy decisions.

## Compatibility classification

This is a conditional additive change. Existing producers may continue omitting
the fields and those plans remain valid. Consumers using the previous closed v1
schema cannot read populated plans; providers must wait until those consumers
update to the current schema before emitting non-empty resolved settings or
provenance.

## Consequences

- The shared operation-plan fixture exercises both schema validation and Rust
  client serialization/deserialization.
- Before release, run `cargo test -p pedantic-operation` from `rust/`.
- Downstream client conformance remains a release prerequisite where those
  clients consume populated operation plans.
