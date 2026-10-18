# Native v2 contract foundation

These contracts are explicitly opt-in. Existing v1 schemas, APIs and signing
payloads are unchanged. The profile service now exposes a bounded v2 integration
for already-approved local DSC remediation; it is not general-operation or
ephemeral-agent execution.

- `resolved-plan.schema.json` binds plan ID/revision, operation, profile, target,
  execution mode, resolved values with source revisions, and step identities.
- `effect-authorization.schema.json` binds a signed grant to that plan's digest
  and a specific effect, attempt, executor/agent instance, lease and fencing token.
- `fixtures/conformance.json` contains synthetic positive, tampering and
  context-mismatch cases shared with Rust and Node tests. Its public key is not
  a trusted service identity.

The Rust `pedantic_operation::native_v2` module exposes:

- `resolved_plan_digest`: closed-schema and dependency validation, then the
  immutable plan digest.
- `canonical_bytes`: RFC 8785 JCS under the numeric profile below.
- `sign_authorization`: sign a structurally valid v2 grant with an explicitly
  supplied Ed25519 key; this does not evaluate PX admission or select a key.
- `verify_effect_authorization`: verify a grant against an independently supplied
  accepted plan, trusted key/key ID and current `EffectContext`. Never derive
  those trusted inputs from the untrusted grant being checked.

Digests are lowercase `sha256:` hashes of canonical UTF-8 bytes. Signing covers
the canonical object containing `schemaVersion` and `grant`; the separate
signature object contains Ed25519, key ID, payload digest and unpadded base64url
signature. Verification checks both the signature and payload digest, as well
as the current identity, input, permission, time and revocation bindings.

Reject non-finite numbers and integer-valued numbers outside
`[-9007199254740991, 9007199254740991]`. Equivalent integral forms such as `1`
and `1.0` canonicalize identically. Unknown fields, incompatible versions,
duplicate dependencies and malformed identity relationships are not silently
normalized into accepted contracts.

## Validation

From the repository root:

```powershell
node --test tests\native-v2-conformance.test.mjs
Push-Location rust
cargo test --locked -p pedantic-operation
Pop-Location
```

Node 20 or later is required for the independent ECMAScript test oracle. Rust
consumes the full rejection corpus; Node independently checks JCS vectors,
plan/payload digests and Ed25519 signature/tampering interoperability. This is
not complete TypeScript/CLI/MCP/PX client conformance.

`local-service-request.schema.json` adds an explicit
`schemaVersion: "pedantic.local-service-request.v2"` envelope on the existing
authenticated profile pipe:

| Method | Parameters |
| --- | --- |
| `effect.authorize` | `approvalId` |
| `effect.verify` | `authorizationId`, signed `authorization`, `inputDigest`, `idempotencyKey` |
| `effect.revoke` | `authorizationId` (current authority only) |
| `remediation.execute` | `executionId`, `authorizationId`, `idempotencyKey`, `document`, signed `authorization` |

The service constructs the plan from recorded approval/revision facts and owns
the key, clock, executor, permissions, coordinator and lease. A new approval for
the same operation advances the fence. Old grants, changed source revisions and
expired/revoked authorities are rejected. An authorization ID replay never
renews its lifetime. Revocation cancels the operation; start a fresh remediation
request after reconciliation. V1 and v2 cannot take over each other's operation.

The Rust service client exposes `call_v2(id, Command)`; the existing CLI/MCP and
TypeScript adapters have not adopted these methods. General capability
descriptors/mode admission, recursive settings and ephemeral-agent execution
remain dependent work. Tests do not authorize real effects or establish reboot,
cleanup or full product QA acceptance. See
[ADR 0009](../../docs/adr/0009-opt-in-native-v2-contracts.md) and
[ADR 0010](../../docs/adr/0010-v2-profile-remediation-authority.md).
