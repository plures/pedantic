# ADR 0001: Pedantic service is the sole live-store owner

## Status

Accepted.

## Context

Pedantic currently has independent PowerShell, Rust, VS Code, and Radix execution/state surfaces. A future shared PluresDB store would be unsafe if each client opened it directly, and policy/evidence would diverge between surfaces.

## Decision

Run one authenticated Pedantic service for each user/profile. That service is the only process that opens the profile's live PluresDB store and owns the associated Chronos writer. Standalone, Radix, VS Code, CLI, MCP, and PowerShell are service clients.

## Consequences

- Clients must use the versioned local API or MCP contract; direct database access is prohibited.
- Store locking, schema migration, backup, recovery, and profile isolation are service responsibilities.
- Embedded single-user operation remains local-first. Multi-user/shared operation requires a separate ADR and service mode.
