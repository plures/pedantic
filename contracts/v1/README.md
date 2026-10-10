# Pedantic Contract v1

This directory is the transport-neutral contract boundary between Pedantic clients and the profile-scoped service. It deliberately contains schemas rather than a language-specific SDK so PowerShell, Rust, TypeScript, and MCP can share the same command semantics.

`command-envelope.schema.json` defines the transport-neutral command envelope.
`local-service-request.schema.json` and `local-service-response.schema.json`
define the authenticated named-pipe protocol used by the local service and its
thin clients. `evidence-summary.schema.json` defines the bounded redacted
Chronos projection returned by that protocol. These contracts do not authorize
effects: the service evaluates the corresponding PX procedure, writes
state/evidence, and returns the resulting projection. Request parameters are
typed per method; response schemas constrain the transport shape and redacted
projection without duplicating PX decision policy.

Durable operations use the versioned operation, effect, capability, and agent
schemas in this directory. They reject unknown fields and carry causal,
profile, target, agent, and idempotency identities. Authorization contracts
persist only opaque secret references; diagnostics are bounded and classified
for redaction before they can become evidence.

Operation plans may include `resolvedSettings` and `resolvedSettingSources`,
the immutable result and provenance of built-in, general, target, and plan
settings after PX evaluates capability safety requirements.

This is an optional additive v1 field: existing plans without it remain valid.
Consumers validating with the previous closed v1 schema reject populated
`resolvedSettings`, so providers must only emit it after those consumers update
to the current schema. The compatibility decision is recorded in
[ADR 0007](../../docs/adr/0007-operation-plan-resolved-settings.md).

Contract changes require an ADR, compatibility classification, schema tests,
and a pre-release client conformance run. The fixtures in `fixtures/` are
validated by `pedantic-service` tests against the same schemas and live service
responses. Before release, run `cargo test -p pedantic-operation` from `rust/`;
the operation-plan fixture is validated against the schema and round-tripped
through the Rust client model.
