# Encoding DTMS.Utilities Primitives into Pedantic

## Architecture and Implementation Report

**Prepared:** October 7, 2026  
**Status:** Recommendation and implementation blueprint  
**Scope:** Clean-room extraction of general durable-operation concepts from
DTMS.Utilities into Pedantic contracts, PX procedures, services, agents, and
bounded effect adapters

---

## 1. Executive summary

Encoding the general DTMS.Utilities primitives into Pedantic has greater
long-term architectural value than integrating Pedantic into DTMS.Utilities.

The recommended end state is:

> Pedantic owns intent, policy, plans, authorization, durable lifecycle, and
> evidence. Platform agents perform authorized bounded effects. DTMS-specific
> Windows capabilities remain external provider packs or reference
> implementations.

Pedantic should absorb the semantics of DTMS.Runway, DTMS.Forge,
DTMS.Transfer, DTMS.Runway.Federation, and DTMS activity feedback. It should
not copy their PowerShell implementations or organization-specific behavior.

The first production-quality vertical slice should remain deliberately narrow:

```text
admit configuration
  -> validate configuration
  -> authorize compliance
  -> durably execute DSC test
  -> propose remediation
  -> record approval
  -> authorize DSC set
  -> durably execute DSC set
  -> reboot and resume if required
  -> perform post-remediation test
  -> finalize causal evidence
```

This proves the operation model without allowing a general orchestration
platform to overwhelm Pedantic's core DSC mission.

### Assessment

| Dimension | Assessment |
|---|---:|
| Long-term architectural fit | 9/10 |
| Immediate implementation readiness | 4/10 |
| Potential operational value | 9/10 |
| Implementation complexity | High |
| Scope-expansion risk | High |
| Recommended direction | Proceed incrementally |

---

## 2. Strategic rationale

Pedantic already intends to centralize configuration admission, compliance,
remediation eligibility, approvals, execution authorization, and evidence in
PX procedures and a profile-scoped service. Its principal missing capability
is the reliable path from an authorized decision to durable completion on a
target.

DTMS.Utilities has already developed practical answers for:

- Durable operations that survive caller disconnection
- Preparation under a network-capable caller identity
- Execution under a service account or SYSTEM
- Declarative dependency plans
- Explicit interrupted and failed retry policies
- Suspension for unmet prerequisites
- Reboot checkpoint and continuation
- Target-local authoritative state
- No-DFS federated observation
- Transfer-provider selection and telemetry
- Immediate activity announcements, heartbeats, and progress

These concepts fill Pedantic's authorization-to-completion gap. Encoding them
in Pedantic would produce a coherent platform rather than another adapter
between two overlapping lifecycle engines.

---

## 3. Governing architectural principles

### 3.1 PX owns decisions

PX procedures and constraints own:

- Admission
- Eligibility
- Plan approval
- Effect authorization
- Retry eligibility
- Reboot eligibility
- Remediation approval
- Cancellation eligibility
- Evidence requirements
- Redaction policy

Rust, PowerShell, TypeScript, Svelte, and transport implementations must not
reimplement these decisions.

### 3.2 Native code performs bounded effects

Native adapters may:

- Invoke DSC
- Read or write explicitly authorized files
- Transfer payloads
- Query host facts
- Start processes
- Request a reboot
- Observe boot identity
- Install packages or capabilities
- Submit normalized observations

They must not decide whether an operation is permitted.

### 3.3 Plans use typed capabilities

The primary plan representation must not consist of arbitrary scripts.
Each step identifies a typed capability with versioned inputs and outputs.

Examples:

```text
file.stage
transfer.execute
dsc.config.validate
dsc.config.test
dsc.config.set
host.reboot
host.fact.observe
process.execute
package.install
windows.feature.ensure
windows.setup
```

Arbitrary shell or PowerShell execution may exist only as an explicitly
privileged escape-hatch capability.

### 3.4 Target observations and policy decisions remain distinct

- Target agents own observed execution facts.
- PX owns decisions and authorization.
- PluresDB owns current canonical projections.
- Chronos owns causal historical evidence.
- Clients own no operational truth.

### 3.5 Delivery is at least once

The system must assume:

- Duplicate messages
- Delayed messages
- Agent crashes
- Service restarts
- Network partitions
- Reordered observations
- Lost acknowledgements

Effects must therefore be idempotent, safely observable before replay, or
explicitly marked as requiring review.

---

## 4. Proposed target architecture

```text
                         Pedantic clients
        VS Code | CLI | MCP | Standalone | Radix | PowerShell
                                |
                                v
                         Pedantic service
          PX decisions | PluresDB state | Chronos evidence
                                |
                    Operation coordinator
             plans | grants | leases | projections
                                |
                  +-------------+-------------+
                  |                           |
                  v                           v
             Target agent               Remote adapter
       local journal and effects     SSH | WinRM | cloud API
                  |
                  v
        Typed capability adapters
 DSC | transfer | reboot | process | package | operating system
```

### 4.1 Pedantic service

The service:

- Accepts intent commands
- Evaluates PX procedures
- Issues capability-bound effect authorizations
- Stores canonical projections
- Records Chronos evidence
- Coordinates plans and attempts
- Receives normalized agent observations
- Never directly assumes that transport delivery equals effect completion

### 4.2 Operation coordinator

The coordinator:

- Materializes authorized plans
- Determines which dependency-satisfied steps may be offered
- Issues leases and fencing tokens
- Tracks attempts
- Accepts step observations
- Requests PX decisions for retry, suspension, reboot, and cancellation
- Builds current projections from accepted events

The coordinator does not execute effects.

### 4.3 Target agent

The target agent:

- Has a stable machine and agent identity
- Maintains a target-local operation journal
- Validates signed authorizations
- Rejects expired, revoked, mismatched, or replayed grants
- Executes only registered capabilities
- Emits immediate lifecycle events
- Persists checkpoints before dangerous effects
- Resumes after process or machine restart
- Synchronizes observations when connectivity returns

### 4.4 Capability adapters

Each adapter declares:

- Capability name and version
- Input and output schemas
- Supported platforms
- Required privileges
- Network requirements
- Secret-reference requirements
- Default retry classification
- Reboot semantics
- Timeout semantics
- Readiness checks
- Evidence and redaction rules

---

## 5. Durable operation model

### 5.1 Proposed lifecycle

```text
Requested
  -> Admitted
  -> Authorized
  -> Preparing
  -> Prepared
  -> Queued
  -> Running
       -> Waiting
       -> AwaitingReboot
       -> NeedsReview
       -> Succeeded
       -> Failed
       -> Cancelled
```

`Waiting`, `AwaitingReboot`, and `NeedsReview` are normal durable states, not
transport errors.

### 5.2 Required entities

```text
OperationDefinition
OperationRequest
OperationAuthorization
OperationPlan
OperationStep
OperationAttempt
OperationCheckpoint
OperationSuspension
RebootRequest
EffectRequest
EffectObservation
OperationProjection
AgentLease
AgentObservationBatch
```

### 5.3 Required identifiers

Every operation and event should carry:

- `operation_id`
- `plan_id`
- `step_id`
- `attempt_id`
- `command_id`
- `authorization_id`
- `idempotency_key`
- `causation_id`
- `correlation_id`
- `agent_id`
- `target_id`
- `profile_id`
- `actor_id`
- `schema_version`

### 5.4 Operation events

Minimum event vocabulary:

```text
operation.requested
operation.admitted
operation.rejected
operation.authorized
operation.cancelled
preparation.started
preparation.completed
step.offered
step.leased
step.started
step.progressed
step.heartbeat
step.suspended
step.resumed
step.reboot_requested
step.reboot_observed
step.completed
step.failed
step.needs_review
operation.succeeded
operation.failed
evidence.finalized
```

Each event includes a monotonic agent-local sequence and a globally unique
event ID.

---

## 6. Declarative operation plans

### 6.1 Plan example

```json
{
  "schemaVersion": "pedantic.operation-plan.v1",
  "planId": "plan-01J...",
  "operationId": "operation-01J...",
  "targetId": "server01",
  "configurationRevision": "revision-01J...",
  "steps": [
    {
      "id": "stage-configuration",
      "stage": "preparation",
      "capability": "file.stage/v1",
      "dependsOn": [],
      "retryClass": "safe",
      "input": {
        "sourceArtifact": "artifact://revision-01J...",
        "destination": "workspace://configuration.yaml"
      }
    },
    {
      "id": "validate-configuration",
      "stage": "execution",
      "capability": "dsc.config.validate/v1",
      "dependsOn": ["stage-configuration"],
      "retryClass": "safe",
      "input": {
        "document": "workspace://configuration.yaml"
      }
    },
    {
      "id": "test-configuration",
      "stage": "execution",
      "capability": "dsc.config.test/v1",
      "dependsOn": ["validate-configuration"],
      "retryClass": "safe-after-observation",
      "input": {
        "document": "workspace://configuration.yaml"
      }
    }
  ]
}
```

### 6.2 Plan constraints

PX and schema validation must enforce:

- Step IDs are unique.
- Every dependency exists.
- The graph is acyclic.
- Preparation steps cannot depend on execution steps.
- Capabilities are registered and version-compatible.
- Inputs validate against the capability schema.
- Required authorizations exist.
- A plan cannot contain plaintext credentials.
- Payload digests match the admitted revision.
- Target identity matches the authorization.
- Execution identity satisfies the capability requirement.
- Every non-idempotent step declares an observation or review policy.

### 6.3 Planning versus execution

Planning must remain deterministic and side-effect free.

Execution begins only after:

- The plan is admitted.
- Every required effect is authorized.
- The target and agent are eligible.
- Required artifacts are immutable and addressable.

---

## 7. Preparation and execution identities

### 7.1 Preparation context

Preparation may require:

- Interactive user identity
- Network share access
- Per-user SSH keys
- Artifact repository access
- Approval UI
- Local source files

Preparation produces immutable staged artifacts and observations. It must
never pass ephemeral credentials into the durable plan.

### 7.2 Durable execution context

Execution uses:

- Agent service identity
- gMSA on Windows where appropriate
- SYSTEM only when explicitly required
- A non-interactive durable process
- Target-local checkpoints

### 7.3 Identity constraints

```text
SYSTEM may not claim domain network identity.

An operation may not serialize a password, private key, token, or certificate
private material.

Secrets are referenced by opaque identifiers and resolved only by authorized
effect adapters.

A preparation artifact must be content-addressed before execution begins.

An execution effect must declare its effective identity requirements.
```

---

## 8. Effect authorization

### 8.1 Authorization structure

An effect authorization should be:

- Signed
- Immutable
- Short-lived
- Target-specific
- Capability-specific
- Input-digest-specific
- Actor-attributed
- Nonce protected
- Revocable
- Bound to an idempotency key

Example:

```json
{
  "schemaVersion": "pedantic.effect-authorization.v1",
  "authorizationId": "auth-01J...",
  "profileId": "default",
  "operationId": "operation-01J...",
  "stepId": "set-configuration",
  "targetId": "server01",
  "capability": "dsc.config.set/v1",
  "inputDigest": "sha256:...",
  "actor": {
    "kind": "user",
    "id": "..."
  },
  "issuedAt": 1791420000,
  "expiresAt": 1791423600,
  "idempotencyKey": "...",
  "retryClass": "safe-after-observation",
  "rebootPermitted": true,
  "signature": "..."
}
```

### 8.2 Agent validation

Before an effect begins, the agent verifies:

1. Signature
2. Schema version
3. Issuer
4. Expiration
5. Revocation state where connectivity permits
6. Target identity
7. Agent identity
8. Capability and version
9. Input digest
10. Idempotency key
11. Attempt and fencing token
12. Replay state in the local journal

---

## 9. Retry and interruption policy

### 9.1 Retry classes

```text
never
safe
safe-after-observation
requires-fresh-authorization
requires-operator-review
compensate-then-retry
```

### 9.2 Examples

| Capability | Default retry class |
|---|---|
| DSC validate | Safe |
| DSC test | Safe |
| File transfer | Safe or resumable |
| Package download | Safe |
| DSC set | Safe after observation |
| Host reboot request | Safe after boot observation |
| Firmware update | Requires operator review |
| Clean OS installation | Never |
| Interrupted arbitrary process | Requires operator review |

### 9.3 Retry procedure inputs

PX should consider:

- Capability retry class
- Prior attempt outcome
- Evidence freshness
- Authorization expiration
- Target boot identity
- Input digest
- Idempotency evidence
- Operator decision
- Maximum attempts
- Compensation status

Native code must not silently retry an effect that PX has not authorized for
replay.

---

## 10. Suspension and reboot continuation

### 10.1 Suspension

A suspension includes:

```text
reason
resume_after
required_observation
authorization_expiration
checkpoint_reference
```

Examples:

- Required service is unavailable.
- Installation media is not staged.
- Another installer is active.
- Maintenance window has not opened.
- Reboot is pending.
- Target connectivity is temporarily unavailable.

### 10.2 Reboot procedure

1. Record the current boot identity.
2. Persist the current step checkpoint.
3. Obtain or validate reboot authorization.
4. Append `step.reboot_requested`.
5. Request reboot through the host adapter.
6. Stop execution.
7. Agent starts after boot.
8. Agent observes the new boot identity.
9. Reject resume if boot identity did not change.
10. Append `step.reboot_observed`.
11. Re-evaluate authorization and prerequisites.
12. Resume from the next incomplete checkpoint.

Reboot continuation must not replay an already completed effect.

---

## 11. Agent journal and synchronization

### 11.1 Target-local authority

The agent journal is authoritative for observed target execution facts while
the agent is disconnected.

The journal should contain:

- Accepted authorization digest
- Step and attempt IDs
- Event sequence
- Start and end timestamps
- Checkpoints
- Effect observations
- Redaction classification
- Synchronization acknowledgement

It must not contain plaintext secrets.

### 11.2 Synchronization

Agents send immutable event batches:

```json
{
  "schemaVersion": "pedantic.agent-observation-batch.v1",
  "agentId": "agent-...",
  "targetId": "server01",
  "fromSequence": 101,
  "throughSequence": 125,
  "events": []
}
```

The service:

- Validates agent identity and signatures
- Rejects sequence gaps or requests replay from the last acknowledgement
- Deduplicates by event ID
- Retains causal ordering
- Applies redaction rules
- Evaluates resulting PX procedures
- Updates PluresDB projections
- Appends Chronos evidence

This replaces file-copy federation and does not require DFS or shared storage.

---

## 12. Capability readiness

Readiness is a structured observation:

```json
{
  "schemaVersion": "pedantic.capability-readiness.v1",
  "targetId": "server01",
  "capability": "dsc.config.set/v1",
  "state": "degraded",
  "required": true,
  "observedAt": 1791420000,
  "findings": [
    {
      "code": "dsc_cli_missing",
      "message": "DSC v3 is not installed"
    }
  ],
  "eligibleRemediations": [
    "dsc.runtime.install/v1"
  ]
}
```

PX uses readiness to determine whether:

- A plan may be admitted
- Preparation is required
- Execution should suspend
- Remediation requires approval
- A target should be excluded
- A fallback provider is eligible

---

## 13. Transfer model

### 13.1 Generic capability

```text
transfer.execute/v1
```

Provider implementations may include:

```text
transfer.robocopy/v1
transfer.scp/v1
transfer.bits/v1
transfer.http/v1
transfer.object-store/v1
```

### 13.2 Transfer observation

```text
provider
source
destination
bytes_total
bytes_transferred
elapsed_ms
current_throughput_bps
average_throughput_bps
estimated_completion
resume_count
retry_count
source_digest
destination_digest
verification_state
```

Provider selection is a PX decision based on:

- Target readiness
- Source and destination type
- Required identity
- Network policy
- Payload size
- Resume requirements
- Historical telemetry
- Security requirements

The provider performs the copy and returns observations only.

---

## 14. Activity and progress protocol

All long-running operations emit immediate feedback before blocking work.

The first event states:

- What is executing
- Why it is executing
- Where it is executing
- Which identity is responsible
- What the first potentially blocking action is

Recommended events:

```text
operation.announced
operation.started
step.started
step.progressed
step.heartbeat
step.suspended
step.resumed
step.completed
operation.completed
```

The same protocol drives:

- CLI output
- VS Code notifications
- Standalone application timelines
- MCP progress
- Radix projections
- Markdown and HTML reports

Presentation remains a client responsibility.

---

## 15. Repository changes

### 15.1 Contracts

```text
contracts/v1/
  operation-definition.schema.json
  operation-plan.schema.json
  operation-event.schema.json
  operation-projection.schema.json
  effect-authorization.schema.json
  effect-request.schema.json
  effect-observation.schema.json
  capability-manifest.schema.json
  capability-readiness.schema.json
  agent-enrollment.schema.json
  agent-observation-batch.schema.json
```

### 15.2 PX procedures

```text
praxis/procedures/
  pedantic-operation-lifecycle.px
  pedantic-effect-authorization.px
  pedantic-plan-admission.px
  pedantic-retry-policy.px
  pedantic-reboot-continuation.px
  pedantic-agent-synchronization.px
  pedantic-capability-readiness.px
```

### 15.3 Rust crates

```text
rust/crates/
  pedantic-operation
  pedantic-agent
  pedantic-capability
  pedantic-transport
  pedantic-windows-agent
```

### 15.4 Responsibilities

#### `pedantic-operation`

- Contract types
- Deterministic plan validation
- DAG ordering
- Event and projection types
- No I/O
- No policy duplication

#### `pedantic-agent`

- Journal
- Lease handling
- Authorization validation
- Capability registry
- Checkpoint and resume
- Progress events
- Synchronization

#### `pedantic-capability`

- Capability trait
- Input/output validation
- Readiness
- Retry metadata
- Redaction metadata

#### `pedantic-transport`

- Authenticated service and agent protocol
- Local, SSH, WinRM, and future transport implementations
- No domain policy

#### `pedantic-windows-agent`

- Windows service hosting
- Service identity
- Boot identity observation
- Reboot adapter
- PowerShell 7 process adapter
- Windows filesystem and ACL adapter
- Optional Scheduled Task bootstrap

---

## 16. DSC remediation vertical slice

### 16.1 Required capabilities

```text
dsc.runtime.readiness/v1
dsc.config.validate/v1
dsc.config.test/v1
dsc.config.set/v1
host.reboot/v1
```

### 16.2 Required service methods

```text
operation.submit
operation.get
operation.cancel
operation.events
remediation.request
approval.record
effect.authorize
effect.observe
agent.enroll
agent.sync
```

### 16.3 Acceptance flow

1. Admit immutable configuration revision.
2. Validate the document digest.
3. Authorize a compliance request.
4. Build a typed compliance plan.
5. Execute DSC test through the local agent.
6. Normalize drift results.
7. Record compliance evidence.
8. Propose remediation for drift.
9. Record an approval.
10. Authorize `dsc.config.set`.
11. Execute set durably.
12. Suspend and reboot when required.
13. Resume after observing a new boot identity.
14. Execute post-remediation DSC test.
15. Finalize the operation and causal evidence.

### 16.4 Vertical-slice acceptance criteria

- No `dsc config set` occurs without a PX-issued authorization.
- Authorization is bound to target, revision digest, and capability.
- Killing the agent during a safe step does not lose the operation.
- Killing the agent during an uncertain set attempt produces observation or
  `NeedsReview`; it does not blindly replay.
- Reboot continuation resumes at the correct checkpoint.
- Duplicate observation batches do not duplicate projections or evidence.
- The CLI, MCP, and VS Code clients see the same operation state.
- Raw DSC documents and raw process output are not persisted in Chronos.
- A post-remediation test proves the final compliance state.

---

## 17. Delivery phases

### Phase 0: governance and architecture

Deliver:

- IP and licensing decision
- Architecture decision records
- Ownership matrix
- Threat model
- Contract naming/versioning policy
- Definition of authoritative state
- Redaction classifications
- Compatibility policy

Exit criteria:

- Approved architecture
- Approved clean-room implementation process
- No unresolved repository-license conflict
- No internal DTMS identifiers in public artifacts

### Phase 1: contracts and PX model

Deliver:

- Operation schemas
- Effect schemas
- Capability schema
- Agent synchronization schema
- PX lifecycle procedures
- PX retry procedures
- PX reboot procedure
- Golden fixtures
- Schema conformance tests

Exit criteria:

- Complete lifecycle can be modeled without executing an effect
- Invalid DAGs are rejected
- Unauthorized effects are rejected
- Retry outcomes are deterministic
- Reboot continuation can be simulated from events

### Phase 2: local durable agent

Deliver:

- Local journal
- Capability registry
- Agent identity
- Signed authorization validation
- Crash recovery
- Resume-after scheduling
- Reboot continuation
- Progress events
- Local DSC adapters

Exit criteria:

- DSC validation/test survives agent restart
- Reboot-resume scenario passes
- Duplicate delivery tests pass
- Interrupted unsafe effect moves to `NeedsReview`

### Phase 3: service-backed DSC remediation

Deliver:

- Remediation request
- Approval recording
- Effect authorization
- Durable set operation
- Post-set test
- Chronos evidence
- Client projections

Exit criteria:

- Full vertical slice passes
- No direct client can invoke DSC set
- Every set has an authorization and approval evidence chain
- Task-suite evidence exists for CLI, MCP, and VS Code projections

### Phase 4: remote target execution

Deliver:

- Agent enrollment
- Target identities
- Authenticated synchronization
- Remote bootstrap strategy
- Artifact staging
- Disconnected execution
- Revocation handling

Exit criteria:

- Target executes while controller is disconnected
- Target reconnects and synchronizes without duplicate evidence
- Expired grants are rejected
- Stale leases cannot complete a newer attempt

### Phase 5: provider ecosystem

Deliver:

- Transfer providers
- Package providers
- Windows feature provider
- OS setup provider
- Hyper-V provider
- Scenario execution and reporting

Exit criteria:

- Providers pass shared capability conformance tests
- No provider embeds PX policy
- Readiness, progress, retry, and redaction contracts are consistent

---

## 18. Testing strategy

### 18.1 Contract tests

- Every request and response validates against its schema.
- Unknown properties are rejected.
- Version incompatibility is explicit.
- Golden fixtures work across Rust, TypeScript, and PowerShell clients.

### 18.2 PX tests

- Admission
- Rejection reasons
- Retry decisions
- Reboot eligibility
- Authorization expiry
- Approval requirements
- Cancellation eligibility
- Evidence redaction

### 18.3 Property tests

- DAG ordering is deterministic.
- Cycles are always rejected.
- Replaying an event batch is idempotent.
- Projection rebuilding from the same events is deterministic.
- An older fencing token cannot supersede a newer attempt.

### 18.4 Failure-injection tests

Terminate:

- Service before offer
- Agent after lease
- Agent before checkpoint
- Agent after effect but before observation
- Network during event upload
- Machine during reboot checkpoint

Validate the required retry or review outcome.

### 18.5 Security tests

- Modified authorization signature
- Expired grant
- Wrong target
- Wrong input digest
- Wrong agent
- Replay attack
- Stale fencing token
- Unauthorized capability
- Secret included in evidence
- Raw output exceeding redaction policy
- Named-pipe or local-socket impersonation

### 18.6 Cross-surface task suite

Run equivalent workflows through:

- CLI
- MCP
- VS Code
- Standalone application
- PowerShell compatibility client

All must produce the same service-side lifecycle and evidence.

---

## 19. Security requirements

### 19.1 Threats

- Authorization theft
- Agent impersonation
- Replay
- Stale worker completion
- Payload substitution
- Secret leakage
- Arbitrary command injection
- Privilege escalation
- Malicious capability package
- Evidence tampering
- Cross-profile access

### 19.2 Controls

- Signed, expiring authorizations
- Mutual agent/service authentication
- Target- and digest-bound grants
- Lease fencing
- Content-addressed artifacts
- Capability allowlists
- Sandboxed process invocation where possible
- Secret references instead of secret values
- Append-only signed observations
- Redaction before persistence
- Per-profile isolation
- Agent package signing
- Capability provenance

### 19.3 Dangerous capability policy

Capabilities such as clean installation, firmware updates, disk
repartitioning, and arbitrary shell execution require:

- Explicit risk classification
- Strong approval
- Exact target binding
- Fresh authorization
- No automatic retry
- Pre-effect checkpoint
- Mandatory post-effect evidence

---

## 20. Scope boundaries

### Include in Pedantic core

- Durable lifecycle
- Typed plans
- Effect authorization
- Retry policy
- Suspension
- Reboot continuation
- Agent journal
- Synchronization
- Readiness
- Progress events
- Evidence integration

### Keep as capability packs

- Windows setup
- Hyper-V migration
- WinIPAK
- Organization-specific transfers
- Datacenter naming conventions
- Enterprise account defaults
- Product-specific validation

### Do not reproduce

- DFS/DFS-R federation
- Shared-folder state synchronization
- PowerShell scriptblocks as the universal plan representation
- Global module imports as the runtime composition model
- Organization-specific service-account names
- Internal hosts, domains, or network topology

---

## 21. Intellectual-property and licensing boundary

DTMS resides in an organizational repository while Pedantic is a
personal/public project. The team must not assume that code or documentation
can be moved between them.

Required safeguards:

- Obtain explicit authorization before using DTMS implementation material.
- Do not copy source, tests, internal documentation, or comments.
- Do not expose internal domains, service accounts, hosts, paths, or policies.
- Implement public schemas and code independently.
- Document clean-room provenance.
- Treat DTMS only as evidence that the general operational problems are real.
- Complete legal review of any contributor's employment obligations.

Pedantic also has a repository-level Business Source License while its Rust
workspace declares MIT. Resolve this discrepancy before distribution or
commercial adoption.

---

## 22. Key risks and mitigations

| Risk | Mitigation |
|---|---|
| Pedantic loses focus | Ship only the DSC remediation vertical slice first |
| Policy duplicated in Rust | Require PX procedure and conformance test for every decision |
| Two sources of execution truth | Separate target observations, PX decisions, projections, and evidence |
| Blind retry causes damage | Capability retry classes and fencing |
| Agent expands security surface | Signed grants, allowlists, enrollment, package signing |
| Offline execution loses revocation | Short-lived grants and bounded offline windows |
| Cross-platform abstractions become vague | Start with Windows and DSC, generalize only proven contracts |
| Public project receives internal IP | Clean-room process and legal approval |
| Service/agent protocol churn | Versioned schemas and golden client fixtures |
| Operation engine delays DSC parity | Make full DSC remediation the mandatory Phase 3 exit gate |

---

## 23. Success measures

The initiative is successful when:

- A DSC remediation cannot run without PX authorization.
- A permitted remediation survives caller disconnect and service restart.
- A rebooted target resumes from the correct checkpoint.
- An uncertain effect is never blindly replayed.
- Every result links to its actor, authorization, revision, target, and
  evidence.
- Every client displays the same canonical operation state.
- Agents operate temporarily offline and synchronize idempotently.
- New capability providers require no new lifecycle engine.
- Organization-specific providers remain outside Pedantic core.

---

## 24. Recommended decision

Proceed with the conceptual extraction of DTMS.Utilities primitives into
Pedantic, subject to IP and licensing approval.

Start with contracts and PX procedures, then implement one local durable agent
and one complete service-backed DSC remediation workflow. Do not begin remote
transport, transfer providers, OS installation, Hyper-V, or general shell
execution until the DSC vertical slice has task-level parity and durable
evidence.

The guiding boundary is:

> Pedantic decides and records why an effect may occur. A durable agent
> reliably performs the authorized effect and reports what actually happened.

---

## 25. Source references

### Pedantic

- Repository:
  https://github.com/plures/pedantic
- README and current v0.6 limitations:
  https://github.com/plures/pedantic/blob/main/README.md
- PX-first refactor plan:
  https://github.com/plures/pedantic/blob/main/docs/PX-FIRST-REFACTOR-PLAN.md
- Capability ownership:
  https://github.com/plures/pedantic/blob/main/docs/CAPABILITY-OWNERSHIP-MATRIX.md
- PX domain authority:
  https://github.com/plures/pedantic/blob/main/docs/adr/0002-px-first-domain-authority.md
- Capability authorization boundary:
  https://github.com/plures/pedantic/blob/main/docs/adr/0003-local-profile-capability-boundary.md
- Chronos evidence:
  https://github.com/plures/pedantic/blob/main/docs/adr/0004-chronos-evidence-is-a-first-class-projection.md
- Shared client contracts:
  https://github.com/plures/pedantic/blob/main/docs/adr/0005-client-surfaces-are-thin-service-adapters.md
- Contract v1:
  https://github.com/plures/pedantic/tree/main/contracts/v1
- Configuration lifecycle PX procedure:
  https://github.com/plures/pedantic/blob/main/praxis/procedures/pedantic-configuration-lifecycle.px
- Service boundary PX procedure:
  https://github.com/plures/pedantic/blob/main/praxis/procedures/pedantic-service-boundary.px
- Service implementation:
  https://github.com/plures/pedantic/tree/main/rust/crates/pedantic-service
- Executor:
  https://github.com/plures/pedantic/tree/main/rust/crates/pedantic-executor
- License:
  https://github.com/plures/pedantic/blob/main/LICENSE

### DTMS conceptual reference

- DTMS.Utilities umbrella and module composition
- DTMS.Runway durable operation lifecycle
- DTMS.Forge declarative plans and preparation/execution separation
- DTMS.Transfer provider selection and telemetry
- DTMS.Runway.Federation target-local state and no-DFS pull projections
- DTMS.OpenSSH remote controller and tunnel concepts

These DTMS references are conceptual only. The Pedantic implementation should
be independently authored after the required IP review.
