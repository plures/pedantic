# Transfer operations

Pedantic's transfer model coordinates verified resource transfer effects through
typed plans, approvals, and durable event projections. It is designed for
operations such as Hyper-V resource transfer where preflight, copying,
verification, and rollback must remain observable.

## Safety properties

- Transfer batches are stored by the profile service and mutations include an
  expected revision, preventing stale concurrent starts.
- Approval records carry a signed, plan-bound effect authorization that both
  service and agent validate.
- Provider results are reduced to typed observations. Incomplete rollback
  produces `NeedsReview`, not success.
- Registry projections retain opaque identity digests rather than paths,
  credentials, keys, raw provider output, or infrastructure addresses.

## Monitoring and reconciliation

The service exposes transfer records, reconciliation, query, reporting, and
retention operations through its authenticated API. A successful report requires
a complete successful event sequence and an observation; conflicting or
incomplete evidence remains visible as such.

For the data model and retention semantics, see
[Federated transfer registry](../federated-transfer-registry.md).
For target preparation before an approved transfer, see
[Windows transfer host preparation](../windows-transfer-host-preparation.md).
