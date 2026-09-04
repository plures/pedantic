# ADR 0005: Every Pedantic surface uses the same contracts

## Status

Accepted.

## Context

The current VS Code extension bridges directly to PowerShell, the Radix plugin models its own compliance data, and the Rust MCP server exposes unrestricted DSC operations. This produces surface-specific behavior.

## Decision

The standalone application, Radix plugin, VS Code extension, CLI, MCP server, and PowerShell module consume versioned Pedantic contracts. The standalone app uses Svelte/Tarui with Unum projections and Design Dojo components; the Radix plugin is a Modulus-published projection client. Local editor syntax analysis may remain local, but operational state transitions cannot.

## Consequences

- Every surface can be tested against the same profile-scoped service fixture.
- New UI components belong in Design Dojo before use by a Pedantic application.
- The existing adapters are migrated incrementally and retired only after parity evidence.
