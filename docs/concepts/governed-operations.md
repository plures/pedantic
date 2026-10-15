# Governed operations

Pedantic treats an operation as a constrained lifecycle, not an arbitrary
command invocation. PX procedures define which facts and transitions are
accepted; the service records those decisions before any execution adapter is
selected.

## Lifecycle

1. A configuration is admitted and identified by its immutable source digest.
2. A compliant or drifting observation is recorded by the profile service.
3. A request binds the intended remediation to the recorded revision and
   observation.
4. An authorized actor records an explicit approval.
5. The service issues a narrow, plan-bound effect authorization.
6. The agent validates the authorization again, executes a typed capability,
   and records redacted observations.

Reusing an idempotency key returns the recorded outcome rather than initiating
the effect twice. An adapter cannot replace the authorized document, target, or
operation with caller-provided alternatives.

## Why this is different

The model makes offline planning useful without treating it as permission to
modify a host. It also makes durable evidence and safe recovery first-class:
policy belongs to PX and the service, while local adapters remain small,
testable effect boundaries.

See [Governed remediation](../guides/governed-remediation.md) for the supported
CLI sequence.
