# Pedantic Contract v1

This directory is the transport-neutral contract boundary between Pedantic clients and the profile-scoped service. It deliberately contains schemas rather than a language-specific SDK so PowerShell, Rust, TypeScript, and MCP can share the same command semantics.

`command-envelope.schema.json` defines the first command envelope. It does not authorize effects. The service evaluates the corresponding PX procedure, writes state/evidence, and returns separately versioned decision and observation envelopes.

Contract changes require an ADR, compatibility classification, schema tests, and a pre-release client conformance run.
