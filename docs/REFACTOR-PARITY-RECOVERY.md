# Refactor parity recovery

**Status:** active recovery. This is the release qualification record for the
PX-first refactor. The Windows-local remediation vertical slice now authorizes
only the bounded service effect described below; it does not authorize remote
execution, bootstrap, or resource download effects.

## What the released source actually provides

| Capability | Released state | Evidence | Recovery disposition |
|---|---|---|---|
| Parse, structural validation, planning, JUnit/SARIF export | Available through the offline Rust CLI | `pedantic` CLI and unit tests | Retain as explicitly offline tooling until it submits service intents. |
| Configuration admission, validation, local inventory, compliance test, redacted evidence | Windows-local, service-owned vertical slice | `pedantic-service` PX constraints, PluresDB, Chronos, service tests | Retain; package the Windows service and extend the same contract. |
| Configuration remediation (`dsc config set`) | Available through the Windows-local service and CLI after PX request, explicit approval, and digest-bound authorization | `remediation.request`, `remediation.approve`, and `remediation.execute`; PluresDB projections; Chronos evidence | Validate on an isolated DSC-capable host; do not expose remote execution until its transport contract exists. |
| Legacy local PowerShell apply | Best-effort compatibility only when DSC is already installed | `Set-DscConfiguration` directly runs `dsc.exe` | Keep clearly labelled as legacy; use the service-backed CLI path for governed local remediation. |
| Legacy remote PowerShell apply | Broken | `Invoke-DscHelper` unconditionally throws for a non-local `ComputerName` | Restore only behind the service capability boundary; do not revive an untracked remote bypass. |
| Legacy DSC bootstrap/resource preparation | Broken in the public apply path | Public flags are accepted but `Invoke-DscHelper` calls `Test-DscExecutable` first and never consumes those flags | Move bootstrap and resource preparation to approved, integrity-checked adapters. |
| Standalone operator app | Absent | No standalone project or packaged application | Deliver after the remediation vertical slice. |
| VS Code inventory and push | Demonstration only | inventory returns mock data; push reports simulated success | Remove simulated-success wording/behavior; migrate operational commands to the service. |
| Radix compliance dashboard | Direct CLI/subprocess projection, not a service client | `plugin/src/stores/compliance.ts` | Replace with Modulus-published service projections. |
| MCP operational integration | Direct read/test/export adapter calls; no remediation | `pedantic-mcp` tools | Keep read-only only; migrate to the service contract before expanding it. |

## Findings

### P0 — release and operator safety

1. The v0.6 installers contain the CLI and PowerShell module but not the
   Windows-only `pedantic-service` binary. The only PX/PluresDB/Chronos path is
   therefore not installable from the release artifact.
2. The installers do not provision DSC. The package nevertheless presents the
   PowerShell module as an applying configuration-management tool. A fresh
   machine reaches `dsc.exe not found` instead of a supported bootstrap or a
   clear prerequisite check.
3. `Invoke-DscHelper` has an explicit remote hard stop. The README and module
   manifest still promise remote SSH/WinRM execution and automatic remote
   setup.
4. The public bootstrap, cache, transport, and resource switches are forwarded
   into `Invoke-DscHelper` but have no effect on its execution path. This is a
   contract regression: callers cannot select offline preparation or opt in to
   a remote download as the cmdlet signature implies.
5. The v0.6 module initializes cache directories under its install location
   and performs an online installer-cache refresh at import time. Installed
   modules can therefore require elevation and make an unsolicited network
   request before the user invokes an operation.
6. Local remediation is now governed by PX request, approval, authorization,
   source-digest, and idempotency constraints. It still lacks a portable
   service transport, DSC bootstrap/resource preparation, and a remote target
   adapter; none of those are silently substituted by the local effect.

### P1 — incompatible surface claims

1. The `pedantic-service` named-pipe host is intentionally Windows-only while
   macOS and Linux installers advertise a cross-platform configuration toolkit.
   The package must state that their module requires a separately installed
   DSC CLI until a portable service transport exists.
2. The root module manifest is `0.9.0`, while the release source and installer
   labels are `0.6.0`. Release artifacts therefore contain two incompatible
   version identities.
3. `pedantic update` expects a self-update-compatible archive, while the
   release publishes MSI, PKG, DEB, and RPM assets only. It must not claim to
   update those package-manager installations.
4. The changelog contains duplicate `0.6.0` sections, so it is not a reliable
   released-change record.
5. The current executor owns `ConfigSet` and SSH execution but no service
   adapter binds either to a PX authorization. It is a dormant bypass risk and
   must remain unreachable from user-facing clients until the Phase 2 contract
   is live.

### P2 — migration work that must not be represented as shipped

1. The VS Code extension exposes mock inventory/facts and a simulated
   successful configuration push. It is an authoring prototype, not an
   operational client.
2. The Radix plugin calls the CLI directly and has a Node `execSync` fallback.
   It does not consume the profile service, Modulus, or Unum projections.
3. The legacy Rust and TypeScript `praxis` engines still contain decision
   logic. They are compatibility code only and cannot be called the authority
   while the PX procedures are incomplete.
4. The README describes the MCP server as host-DSC integration without making
   its direct, read-only adapter status clear.

## Recovery sequence and exit evidence

1. **Release truthfulness (this change):** package the Windows service,
   correct public capability claims, and maintain this inventory. Validate
   installer contents rather than treating a green workflow as proof.
2. **PX remediation contract (implemented locally):**
   `remediation.request`, `remediation.approve`, and
   `remediation.execute` bind fresh drift evidence, actor, explicit approval,
   configuration digest, idempotency key, PluresDB projections, and redacted
   Chronos evidence. Bootstrap/resource-preparation intent remains next.
3. **Bounded effect adapters:** expose only service-owned local execution
   first. Add remote transport and DSC bootstrap only after an approved
   artifact has an expected digest, an explicit target/transport capability,
   redacted result normalization, cancellation, and cleanup tests. A remote
   download is opt-in; cached/offline artifacts are the default.
4. **Client parity:** add contract clients for CLI, PowerShell, MCP, VS Code,
   and Radix. Retire direct effects and simulated success only after the same
   compliance-and-remediation task returns matching decision and evidence IDs.
5. **Cross-platform and release parity:** choose a portable local transport
   before advertising service-backed operations on macOS/Linux. Synchronize
   package/module versions, make self-update package-manager aware, and run
   clean-install, upgrade, rollback, offline, and real DSC task suites before
   a non-prerelease release.

## Non-negotiable acceptance checks

- A `set` request without a fresh accepted compliance observation and approval
  is rejected by a canonical PX constraint before any adapter starts.
- Replaying an idempotency key returns the recorded outcome and cannot execute
  DSC twice.
- An effect cannot select a client-provided executable, command line, source
  path, or target after authorization.
- Bootstrap rejects an unsigned or digest-mismatched artifact and never
  silently downloads it.
- A successful task has a PX decision ID, a PluresDB projection, and a
  redacted Chronos execution observation.
- Each released installer is opened on a clean VM and verified to contain the
  documented binaries, compatible module version, and declared prerequisites.

## Guarded local remediation CLI

The CLI makes only the service contract available; it cannot select an
executable, shell command, remote target, or transport. A qualifying
`compliance.observe` result with drift is required before this sequence:

```powershell
pedantic service remediation-request --request-id remediation-1 --revision-id revision-1 --observation-id observation-1 --actor-id operator@example.test --idempotency-key change-123
pedantic service remediation-approve --approval-id approval-1 --request-id remediation-1 --actor-id reviewer@example.test --approved
pedantic service remediation-execute --execution-id execution-1 --authorization-id approval-1 --idempotency-key change-123 --file .\configuration.yaml
```

`PEDANTIC_LOCAL_TOKEN` and a running Windows `pedantic-service` are required.
The effect is `dsc config set` on the service host only and has a 30-second
timeout. Replaying the same execution idempotency key returns the recorded
outcome; a mismatched authorization or document is rejected before DSC runs.
