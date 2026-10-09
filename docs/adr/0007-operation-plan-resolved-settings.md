# ADR 0007: Operation plans carry resolved settings

## Status

Accepted.

## Context

PX resolves built-in, general, target, and plan settings after evaluating
capability safety requirements. Durable operation plans need to carry those
resolved values so consumers observe the same settings that PX approved.

## Evidence

| Question | Evidence | Status |
| --- | --- | --- |
| Is the field optional? | `resolvedSettings` is not in the schema's `required` list; the Rust field defaults to an empty map and is omitted when empty. | Verified |
| Do old payloads remain valid? | The updated v1 schema accepts plans without `resolvedSettings`. | Verified by the operation-plan contract test |
| Can prior strict readers consume populated plans? | The v1 schema rejects unknown properties, so consumers validating with the previous schema reject this field. | Incompatible until consumers update |
| Have all external client implementations been tested? | This repository's conformance test covers the Rust operation-plan model; downstream client behavior is not represented here. | Unknown |

## Decision

Add optional `resolvedSettings` to the v1 operation-plan contract. The values
remain PX-derived; the Rust client transports them and does not make policy
decisions.

## Compatibility classification

This is a conditional additive change. Existing producers may continue omitting
the field and those plans remain valid. Consumers using the previous closed v1
schema cannot read populated plans; providers must wait until those consumers
update to the current schema before emitting non-empty `resolvedSettings`.

## Consequences

- The shared operation-plan fixture exercises both schema validation and Rust
  client serialization/deserialization.
- Before release, run `cargo test -p pedantic-operation` from `rust/`.
- Downstream client conformance remains a release prerequisite where those
  clients consume populated operation plans.
