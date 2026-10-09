# Federated transfer registry

`ServiceFoundation` stores the `FederatedTransferRegistry` in the profile-local
PluresDB store. Every accepted transfer event is immutable evidence identified
by `eventId`; replaying the identical event is idempotent. A conflicting reuse
is rejected as a new record but retained in the registry as reconciliation
evidence. Existing persisted registries must match the storage schema and
deserialize successfully; malformed or incompatible data fails service
startup rather than being replaced with an empty registry.

## Federation and monitoring

Replicas exchange `FederatedTransferRegistry` values through
`reconcile_transfer_registry`. Merging is set-union by immutable event ID, not
last-writer-wins. Reusing an event ID with different contents retains both
variants and reports an `event-id-conflict` finding rather than discarding
either replica's evidence. The registry sorts events by operation sequence and
exposes history gaps, target identity disagreement, and contradictory terminal
states as reconciliation findings. A replica that receives a terminal event
before its preceding history therefore reports an incomplete/conflicted
operation rather than success.

`query_transfers` supports exact operation ID, source VM, target VM, target
host, and active-state filters. `active: true` is the monitoring projection:
it remains active across service restart until a complete terminal event
sequence is present. The authenticated versioned service API exposes
`transfer.record`, `transfer.reconcile`, `transfer.query`, `transfer.report`,
and `transfer.retain`; `LocalServiceClient` provides matching typed methods.

## Reports and redaction

`transfer_report` is derived only from recorded evidence. It includes provider,
bytes transferred, elapsed milliseconds, throughput, retry and resume counts,
verification state, and an optional failure category. A success report requires
both a complete `Succeeded` event sequence and an observation. Conflicting or
incomplete evidence is reported as `conflicted` or `incomplete`.

Transfer records deliberately have no fields for source/destination paths,
credentials, private keys, raw provider output, or infrastructure addresses.
VM and host identifiers are converted to stable, domain-separated opaque
digests before entering registry projections, and query filters are normalized
the same way. Chronos evidence projections contain only operation and opaque
VM/host identifiers plus sequence/state metadata.

## Retention

Call `retain_terminal_transfer_history(retain_after)` with a Unix timestamp to
prune terminal operation events older than that timestamp. Active operation
history is never pruned. Retention is operation-atomic: it removes a terminal
operation only when every event has a timestamp older than the cutoff. If any
event is at or after the cutoff, or has no timestamp, the entire operation
history is retained so pruning cannot create a sequence gap.
