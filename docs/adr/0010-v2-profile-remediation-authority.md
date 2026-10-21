# ADR 0010: Profile-owned v2 remediation authority

## Decision

The user selected the existing approved DSC-remediation path as the first v2
service integration. Do not introduce another service, coordinator algorithm,
general executor, implicit v1 conversion, or remote target.

An explicitly versioned local-service request opts into v2. Existing v1 request
schemas and APIs remain unchanged. The same authenticated, profile-scoped pipe,
PluresDB store, signing key, revision mutex, PX evaluator, evidence timeline and
bounded DSC adapter own both versions.

The service derives a single-step immutable plan from an already accepted
approval, remediation request and validated configuration revision. Clients
cannot choose the plan, actor, executor, permissions, signing key, clock, lease
or fencing token. The plan contains source-digest/revision provenance, not the
configuration document. PX must admit the recorded approval and the fixed local,
agentless, high-risk, no-reboot DSC capability.

Reuse `DurableCoordinator` and `EffectLease` inside profile-owned durable state.
A subsequent approved grant for the same operation advances its step fence;
older grants fail against current service state. Replays of an authorization ID
return the same still-active grant, never renew it silently. Revocation cancels
the operation authority; a fresh remediation request is required thereafter.
Expiry and interruption also require explicit reconciliation, not automatic
provider replay.

V1 and v2 share the authorization-ID namespace. A recorded authorization cannot
be reinterpreted as the other version. V2 verification reconstructs trusted
context from the approval, revision and current coordinator/lease, never from
the submitted signature payload. Issuance and execution both evaluate PX;
verification also checks the accepted plan, signature, input, permissions,
revocation, current fence and time. Final dispatch repeats the v2 check under the
same mutex immediately before the existing bounded DSC adapter.

Reuse the existing durable execution claim, idempotency handling and current
compliance-observation policy. No alternate provider execution implementation.
Only redacted event metadata enters Chronos. Keys, documents and signatures
must not be included in error or tracing output.

## Evidence and boundaries

| Expectation | Required evidence |
| --- | --- |
| Existing behavior | Existing service and operation tests remain green |
| Explicit opt-in | Closed v2 envelope, unknown-field/version rejection, unchanged v1 fixtures |
| Profile ownership | Wrong token/profile cannot issue, verify, revoke or execute |
| Durable authority | Reopen a temporary profile store and verify the same plan/grant/current fence |
| No stale dispatch | Tampered, expired, revoked, superseded and changed-source grants cause zero injected provider calls |
| One execution path | Accepted v2 grant uses the shared adapter seam once; replay returns the persisted outcome |
| Fail closed | Interrupted claim requires reconciliation; no automatic retry |
| PX ownership | Real compiled constraints reject invalid admission/runtime facts |

Tests use synthetic profile records and an injected DSC runner; no target effect
is approved. This bounded service slice is not general-operation scheduling,
ephemeral-agent bootstrap, recursive settings resolution, complete client
adoption, native security parity, release or product QA.
