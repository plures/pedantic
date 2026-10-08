# Federated transfer registry

`ServiceFoundation` stores the `FederatedTransferRegistry` in the profile-local
PluresDB store. Every accepted transfer event is immutable evidence identified
by `eventId`; replaying the identical event is idempotent, while trying to
reuse an event ID with different contents is rejected.

## Federation and monitoring

Replicas exchange `FederatedTransferRegistry` values through
`reconcile_transfer_registry`. Merging is set-union by immutable event ID, not
last-writer-wins. The registry sorts events by operation sequence and exposes
history gaps, target identity disagreement, and contradictory terminal states
as reconciliation findings. A replica that receives a terminal event before
its preceding history therefore reports an incomplete/conflicted operation
rather than success.

`query_transfers` supports exact operation ID, source VM, target VM, target
host, and active-state filters. `active: true` is the monitoring projection:
it remains active across service restart until a complete terminal event
sequence is present.

## Reports and redaction

`transfer_report` is derived only from recorded evidence. It includes provider,
bytes transferred, elapsed milliseconds, throughput, retry and resume counts,
verification state, and an optional failure category. A success report requires
both a complete `Succeeded` event sequence and an observation. Conflicting or
incomplete evidence is reported as `conflicted` or `incomplete`.

Transfer records deliberately have no fields for source/destination paths,
credentials, private keys, raw provider output, or infrastructure addresses.
Chronos evidence projections contain only operation and opaque VM/host
identifiers plus sequence/state metadata.

## Retention

Call `retain_terminal_transfer_history(retain_after)` with a Unix timestamp to
prune terminal operation events older than that timestamp. Active operation
history is never pruned. A terminal operation with events both before and after
the cutoff keeps the newer evidence, so retention is safe to run in bounded
batches at realistic registry volumes.
