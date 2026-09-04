# ADR 0003: Effects require an explicit capability authorization

## Status

Accepted.

## Context

DSC operations, SSH/WinRM connectivity, resource discovery, file access, and cache downloads have host effects. Direct calls from multiple clients make consent, replay, and redaction inconsistent.

## Decision

The service accepts intent commands and lets PX determine whether an effect is eligible. An accepted authorization identifies the profile, configuration revision, capability, actor, idempotency key, and evidence requirements. Effect adapters return normalized observations only.

## Consequences

- `dsc config set` requires PX authorization tied to qualifying test evidence and recorded approval.
- Clients cannot smuggle arbitrary command lines through the service contract.
- Transport credentials and raw host output stay behind the adapter and are redacted before persistence/export.
