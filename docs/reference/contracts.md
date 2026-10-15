# Contracts and authority

Pedantic keeps versioned machine-readable contracts in
[`contracts/v1`](../../contracts/v1). They define the data exchanged across
the native boundaries, including operation plans, capability manifests,
authorizations, agent records, and service requests.

## Contract invariants

- A resolved operation setting carries both its value and its source.
- Effect authorization is signed and binds the intended operation.
- Configuration revisions bind the SHA-256 digest of raw document bytes.
- Agents validate grants and record observations; they do not determine policy.
- Capability adapters validate declared JSON input and output schemas.

PX procedures in [`praxis/procedures`](../../praxis/procedures) are the source
of truth for accepted domain transitions and constraints. Rust modules implement
and project those decisions; neither a client nor a provider adapter can
override them.

For the service ownership decision, see
[ADR 0001](../adr/0001-pedantic-service-store-ownership.md). For operation
settings, see [ADR 0007](../adr/0007-operation-plan-resolved-settings.md).
