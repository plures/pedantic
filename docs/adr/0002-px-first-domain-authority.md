# ADR 0002: PX is Pedantic's domain authority

## Status

Accepted.

## Context

The repository currently duplicates configuration validation and compliance decisions in a Rust rule engine, TypeScript "praxis-inspired" engine, plugin manifest rules, and PowerShell orchestration. Those copies cannot provide one durable decision record.

## Decision

PX procedures and constraints own configuration admission, fact freshness, compliance classification, remediation eligibility, approvals, execution authorization, and evidence policy. The initial specification is `praxis/procedures/pedantic-configuration-lifecycle.px`.

## Consequences

- Rust and PowerShell invoke DSC and transports only through declared effect capabilities.
- TypeScript/Svelte clients render PX projections and submit commands; they do not choose lifecycle outcomes.
- Legacy rules remain compatibility behavior only until the matching PX procedure and service path has task-level parity.
