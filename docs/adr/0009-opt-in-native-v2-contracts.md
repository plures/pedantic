# ADR 0009: Opt-in native v2 contracts

## Status

Accepted compatibility direction: introduce explicit v2 contracts and retain
existing v1 APIs, schemas and signing payloads unchanged. No automatic upgrade,
downgrade, dual coordinator, or activation of v2 effects is authorized.

## First delivery boundary

The first #240 foundation unit defines immutable resolved plans and signed
effect authorizations. It supplies closed schemas, Rust verification and shared
positive/negative fixtures. Service issuance, persistence, PX admission, provider
enforcement and client adoption are subsequent dependency-ordered work. This
unit does not complete #240, #248, or the service-backed acceptance gate.

Plans bind a plan ID and revision, operation, profile, target, execution mode,
resolved settings with source/revision provenance and dependency-ordered steps.
Reuse the existing DAG algorithm
after v2 structural validation. Agentless and ephemeral-agent execution use the
same plan and grant model; their execution identities are explicitly tagged.
An ephemeral identity includes the agent, instance and lease, not just an agent
name. Unsupported versions and unknown fields are rejected.

An authorization signs the complete versioned grant, including the immutable
plan digest, step input digest, operation/profile/target, attempt, execution
identity, fencing token, validity window and effect permissions. Verification
requires an independently supplied trusted key and current execution context.
It checks the accepted plan and actual effect context, expiry, revocation,
signature and payload digest. Key selection and revocation belong to the service,
not to untrusted grant fields. Verification is not PX admission or provider
execution.

## Canonical bytes and compatibility

Use RFC 8785 JSON Canonicalization Scheme (JCS), UTF-8 and SHA-256 with the
`sha256:` lowercase hexadecimal prefix. The plan digest covers the entire v2
plan. The signature covers the canonical object containing `schemaVersion` and
`grant`, excluding the signature object. Sign with Ed25519; encode signatures as
unpadded base64url. The signature's payload digest hashes those same bytes.

Reject non-finite numbers and integer-valued numbers outside the JavaScript
safe-integer range before canonicalization. This conservative numeric profile
prevents Rust and JavaScript clients from accepting different numeric identities.
Do not substitute ordinary serializer order for JCS. Shared vectors must cover
property order, Unicode ordering, number normalization and tampering.

Changing a resolved value, plan revision, effect input, execution identity or
permission invalidates the old binding. There is no conversion of a v1 signature
into v2 evidence. Existing v1 callers continue to use their existing paths.
Future v2 entry points must opt in explicitly and consume these same contracts;
they must not silently accept v1 grants or run a second operation authority.

## Qualification

Rust and Node tests consume the same synthetic conformance corpus. Synthetic
keys are test-only and are never service identities. All negative cases must
fail with explicit errors, not a success-shaped fallback.

These are contract and cryptographic component tests, not actual service/client
execution, reboot, cleanup, native security parity or full product QA. No target
effects or release are permitted by this ADR.
