# ADR 0008: Native source provenance and acceptance boundaries

## Status

Accepted for the conservative source hold and independent implementation
boundary. License clearance and native runtime acceptance remain unverified.
This is a bounded contribution to [#271](https://github.com/plures/pedantic/issues/271),
not completion of that issue or its dependencies.

## Context and evidence

The source assessment is bound to commit
`7a201be513530a05a2204c76b3cbbcd1b54cb526`. A public checkout, a closed parent
issue, or passing helper tests is not permission to reuse source or evidence
that a service-backed operation is accepted.

| Question | Source evidence | Disposition |
| --- | --- | --- |
| What legacy source is already tracked? | [Source inventory](../../source-provenance.json): three paths under `DTMS Primitives Source`, last changed by `6995f18a94256450d5b7af866590cd6395411a3a` | Record Git object identities without reproducing or executing the files. Origin rights and license compatibility are unverified. |
| Are operation contracts absent? | [v1 contracts](../../contracts/v1/README.md), [operation models and contract tests](../../rust/crates/pedantic-operation/src/lib.rs) | Existing schemas and fixtures must be reused. #240 still needs criterion-level shared-client, identity, and version conformance evidence; source presence does not close it. |
| Is the provider interface absent? | [Capability trait, registry and validators](../../rust/crates/pedantic-capability/src/lib.rs) | Reuse these for #248. Registration, version/mode rejection, authorization binding and client descriptor parity still need acceptance evidence through the actual service. |
| Does local service remediation exist? | [Service](../../rust/crates/pedantic-service/src/lib.rs): `request_remediation`, `approve_remediation`, `authorize_remediation`, `execute_remediation`, `evaluate_px_constraint` | Yes: source includes native PX evaluation, persisted approval, digest-bound authorization, and interrupted-claim rejection. This assessment did not execute DSC. |
| Is coordinator replacement accepted? | [Durable coordinator](../../rust/crates/pedantic-operation/src/durable_coordinator.rs) defines serializable authority, leases and cleanup checks | Helper serialization and tests do not establish service/agent persistence, replay or removal acceptance. #235 being closed does not close its open child obligations. |
| Can broad provider expansion or replacement proceed? | #271 requires the complete service-backed slice below | No acceptance claim until real-interface evidence exists. This source-control gate does not implement or certify that runtime gate. |
| Can the existing documentation lane be overwritten? | #272 / draft PR #273 is still open at `857589e292ac7e756bb0f9438e56a77da6262793` | Preserve that lane; this change does not rewrite its owned pages or create another coding-agent assignment. |

## Decision: permitted inputs and conservative hold

Native implementation inputs are permitted public contracts, suitably licensed
public dependencies, and independently authored behavior and synthetic fixtures.
This does not grant rights to arbitrary public source. The repository's
Apache-2.0 declaration does not settle the rights of an imported file or a
transitive dependency.

For every inventoried legacy path:

- Provenance and license compatibility are **unverified**, not approved.
- Do not copy, translate, execute, package, or use the files as implementation
  examples for new native functionality.
- Retain the existing tracked objects unchanged pending an owner-approved
  disposition. Exclude the directory and descendants from Git source archives.
- Any modification to the held inventory, its object identities, archive
  attributes, or allowed-input policy requires explicit provenance review.
- A removal decision must be a separate deletion-only change. Do not rewrite
  history or silently delete the evidence. Existing clones and Git history
  still contain the objects; archive exclusion is not retroactive erasure.

[#253](https://github.com/plures/pedantic/issues/253) remains the owner of
contribution/DCO, trademark, security-support, and licensing decisions. This ADR
does not invent those legal policies or assert production license clearance.
Private source, customer catalogs, identifiers, mappings, credentials and real
evidence must remain outside public source, tests, logs, issues and artifacts.

## Executable source controls

`node scripts/check-source-provenance.mjs` checks the complete held-path
inventory, unchanged Git blob identities, regular-file status and effective
`export-ignore` attributes. It rejects literal references to the held directory
in tracked or non-ignored new runtime source under Rust, PX, extension, plugin
and resource roots. `node --test tests/source-provenance.test.mjs` exercises
negative controls and an actual Git archive with independently generated files.
Both commands run in CI and the local CI entry point.

These are bounded repository controls, not a copyright scanner or a proof that
renamed/copied derivatives cannot exist. Encoded or dynamically constructed
references require review. Custom packagers do not inherit Git archive
attributes and must continue to use their explicit product input lists. No
artifact, runtime, provider, or license acceptance is inferred from this gate.

## Native contracts and ownership

### Foundation acceptance reconciliation

The following source inspection is bound to
`00d28ce3ed5df50d34a58b5da48b451e7146be85` and the acceptance criteria of
[#240](https://github.com/plures/pedantic/issues/240) through
[#249](https://github.com/plures/pedantic/issues/249). None of these issues is
accepted or closed by this inspection. Existing component tests are not evidence
of the complete service-backed exit gate.

| Issue | Existing source | Unmet or unverified acceptance |
| --- | --- | --- |
| #240 | [Operation models](../../rust/crates/pedantic-operation/src/lib.rs) and [v1 schemas/fixtures](../../contracts/v1/README.md) distinguish plans, authorizations, effects and projections. | Shared Rust/PX/TypeScript/CLI/MCP fixture conformance and complete identity relationships remain unqualified. The generic authorization has an input digest, while resolved-plan binding is represented separately by the transfer checkpoint. |
| #241 | [Settings resolver](../../rust/crates/pedantic-operation/src/settings.rs) applies ordered, flat key replacement and records four source categories. | Recursive merge, declared list strategies, target-rule conflicts, reset/inherit semantics, source revisions, and canonical cross-client digest evidence are not supplied by this helper. |
| #242 | [Lifecycle](../../praxis/procedures/pedantic-operation-lifecycle.px) and [plan admission](../../praxis/procedures/pedantic-plan-admission.px) declare PX constraints; the service evaluates configuration/remediation policy. | General native lifecycle integration and complete recovery/cleanup policy coverage are not established by those declarations. |
| #243 | [Profile service](../../rust/crates/pedantic-service/src/lib.rs) owns persistent state and Chronos evidence, including agent synchronization, remediation claims and a transfer registry. | These domain-specific paths do not establish durable persistence/restart of the general coordinator or complete cross-client operation projections. |
| #244 | [Durable coordinator](../../rust/crates/pedantic-operation/src/durable_coordinator.rs) has lease/approval/cleanup helpers and serialization tests. | No production use of `DurableCoordinator` was found in the inspected Rust workspace. Service restart, scheduling, lost acknowledgements and full failure-injection acceptance remain open. |
| #245 | [Agent](../../rust/crates/pedantic-agent/src/lib.rs) validates signed grants, target bindings and observation sequences. | The complete operation-owned artifact/cleanup manifest, shared prerequisite handling and independent removal verification are not demonstrated. |
| #246 | The agent library journals progress and has recovery tests. | Real agent-binary/service disconnection and reboot acceptance are absent. [Windows boot identity](../../rust/crates/pedantic-windows-agent/src/lib.rs) currently returns changing uptime, not a stable boot identifier; this is a separate unresolved prerequisite. |
| #247 | The coordinator models cleanup verification; the Windows adapter currently exposes a boot fact. | No native install/rollback/service-registration/agentless-removal implementation was found in the inspected Rust workspace. Helper cleanup booleans do not verify target residue. |
| #248 | [Capability registry and SDK](../../rust/crates/pedantic-capability/src/lib.rs) validate schemas; the [agent](../../rust/crates/pedantic-agent/src/lib.rs) validates grants before dispatching resolved providers. | Duplicate registration at the inspected baseline replaces the accepted provider before reporting rejection. Service registration, execution-mode/platform/lifecycle declarations and descriptor parity remain separate open requirements. |
| #249 | CLI and MCP use the authenticated profile-service client for existing methods; the extension reports unavailable inventory truthfully. | One general operation list/get/watch projection and normalized cross-surface fixture comparison are not established. |

### Decision: rejected registration preserves the accepted provider

Registration is a structural SDK operation, not a new PX lifecycle decision.
Validate the candidate manifest first. A duplicate capability/version key must
return the existing `Duplicate` error without replacing the accepted provider
or adding readiness entries. Invalid candidates must also leave the registry
unchanged; different versions remain separately registerable.

Verify both registry identity preservation and downstream `LocalAgent`
dispatch with the existing signed-grant and temporary-journal fixtures. This
repairs a component-level prerequisite of #248 without changing wire contracts,
adding a service registration API, performing target effects, or claiming
native acceptance. The boot-identity defect and the other gaps above remain
open and must not be hidden by this repair.

Use the existing `pedantic.*.v1` contract naming and explicit schema versions.
New security contracts belong to the existing #261 / #262-#268 program, not a
second epic. Domain-specific catalogs are opaque versioned content inputs, not
core types. Incompatible payloads or canonicalization changes require a new
version and independent byte-level conformance vectors; do not silently claim
compatibility with a different serializer.

PX owns applicability, admission, sufficiency, approval and recovery decisions.
Rust capabilities perform bounded typed effects. The profile service owns
operational projections and causal evidence. Clients consume authenticated
versioned service APIs, not live stores or parallel policy engines. Repository,
work-item and PR delivery orchestration remains outside Pedantic.

Evidence must be bounded and redacted before persistence or export. Keep
observation, intent, authorization and independently verified postconditions
distinct. Successful mutation is not a satisfied security assessment.

## Remaining mandatory service-backed exit gate

Before claiming broader provider readiness or replacing a durable substrate,
the versioned build must demonstrate, through real service and client interfaces:

1. Request and PX admission; denied or unsupported requests produce no effects.
2. Explicit approval and authorization bound to target, immutable plan/document
   digest, operation, attempt and idempotency key.
3. A durably claimed, bounded DSC effect on an explicitly approved disposable
   target. Declarations of timeout or memory limits are not enforcement.
4. An independent postcondition observation, not the effect handler's exit code.
5. Causal evidence joining the decision, authorization, claim, effect and
   observation without secret leakage.
6. Consistent CLI, MCP and VS Code projections of that same operation.
7. Interruption after claim, uncertain effects, stale leases, cancellation,
   replay, reboot continuation and independently verified cleanup. Uncertain
   effects require observation/reconciliation before any retry.

Conformance fixtures must cover operation identity/version errors, effect
authorization mismatch, provider version/mode rejection, reordered/duplicate
synchronization, retry after unknown outcome, stale reboot continuation, and
cleanup refusal for unowned or unverified resources. Share the fixtures across
Rust, PX and clients; synthetic unit cases are not live-target acceptance.

Use the existing engineering lifecycle and evidence validation, not another
coordinator. Record exact source/build identities, commands, outputs, effect
ownership, failure injections and cleanup receipts. No DSC execution, host
modification, reboot, cloud provisioning or tenant attachment is authorized by
this source-control change.

## Parity, cutover and rollback

Characterize existing behavior using permitted inputs before replacement.
Prove contract and client parity and account for every active operation and
owned resource. Quiesce the old coordinator before activating the new one for
an operation; never operate two authorities or replay an ambiguous imported
journal automatically. Preserve causal history, an explicit rollback path and
independent cleanup evidence. Until those gates pass, the current substrate is
not declared replaceable and #271 remains open.
