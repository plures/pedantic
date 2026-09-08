# Pedantic Contract v1

This directory is the transport-neutral contract boundary between Pedantic clients and the profile-scoped service. It deliberately contains schemas rather than a language-specific SDK so PowerShell, Rust, TypeScript, and MCP can share the same command semantics.

`command-envelope.schema.json` defines the transport-neutral command envelope.
`local-service-request.schema.json` and `local-service-response.schema.json`
define the authenticated named-pipe protocol used by the local service and its
thin clients. `evidence-summary.schema.json` defines the bounded redacted
Chronos projection returned by that protocol. These contracts do not authorize
effects: the service evaluates the corresponding PX procedure, writes
state/evidence, and returns the resulting projection.

Contract changes require an ADR, compatibility classification, schema tests,
and a pre-release client conformance run. The fixtures in `fixtures/` are
validated by `pedantic-service` tests against the same schemas and live service
responses.
