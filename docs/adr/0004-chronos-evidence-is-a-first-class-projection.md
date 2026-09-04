# ADR 0004: Chronos records causal Pedantic evidence

## Status

Accepted.

## Context

An operational result without its policy decision, actor, source, and configuration revision cannot explain why Pedantic acted or support safe replay.

## Decision

For each accepted command, PX decision, effect authorization, effect observation, and projection change, the service appends a Chronos event with causal identifiers, Unix-second timestamps, actor/source, redaction class, and evidence links. Chronos remains the timeline/replay projection; PluresDB remains the canonical graph state.

## Consequences

- API and MCP queries can answer why a remediation was accepted, rejected, or cancelled.
- Evidence exports must apply the same redaction policy as persisted timeline events.
- Log text alone is not acceptance evidence.
