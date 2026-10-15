# StateSmith Extension Security & Sandbox Review

Version: 0.1 (initial draft)
Status: Draft – to be iterated as features land.
Owner: TBD (initial authoring via automation)

## 1. Goals & Non‑Goals
**Goals**
- Prevent unintended code execution or escalation through DSL parsing, webviews, or AI tooling.
- Provide a defendable story for marketplace review (no remote code, controlled subprocesses).
- Define trust boundaries and mitigation controls early to avoid retrofits.
- Enable future DSC execution and AI-assisted code actions under explicit user consent.

**Non-Goals (for this iteration)**
- Full cryptographic supply chain attestation.
- Production telemetry pipeline (covered separately in Telemetry plan).
- Finalized AI model risk assessment (pending MCP integration design).

## 2. Trust Boundaries
| Boundary | Description | Primary Risks | Controls |
|----------|-------------|---------------|----------|
| VS Code Extension Host (TypeScript) | Core activation + parsing | Supply chain deps, prototype pollution | Minimal deps, lockfile, audit gating (future) |
| Webview (Resource Graph, future Svelte) | Untrusted HTML/JS sandbox | XSS via template injection, data exfiltration | Strict CSP (no remote src, no eval), sanitize dynamic text |
| PowerShell DSC Bridge (future) | Child process invocation | Command injection, credential leakage | Argument escaping, allow‑list commands, execution gating |
| Filesystem (Workspace) | User-provided DSL/config | Malicious payload in DSL triggering code exec | Parser is data-only, no `eval`, treat all content as untrusted |
| AI/MCP Channel (future) | Model prompts/responses | Prompt injection, leakage of secrets | Redaction layer, system prompt hardening, user confirmation for actions |
| Network (Optional future) | Package/resource lookups | MITM, data leak | Default offline; opt-in network operations with explicit consent |

## 3. Asset Inventory
- DSL Documents (Simple / SudoLang) – Untrusted input feeding parsers.
- Generated DSC Scripts (future) – High integrity output, may be executed.
- PowerShell Executable Path – Configuration surface susceptible to tampering.
- Webview State (graph nodes/diagnostics) – Non-sensitive but must avoid script injection.
- Telemetry (future) – Potential privacy surface.

## 4. Threat Model (STRIDE Snapshot)
| Threat | Scenario | Impact | Mitigation |
|--------|----------|--------|------------|
| Spoofing | Fake provider override impersonates internal provider | Misconfiguration, trust misplacement | Validate provider strings against schema allow-list |
| Tampering | DSL injection alters execution command line | Host compromise | No direct templated exec: generation layer escapes & isolates params |
| Repudiation | User disputes auto-applied AI refactor | Audit gap | Immutable change log (planned), require user commit review |
| Information Disclosure | AI panel leaks proprietary DSL content to model | Data leak | Opt-in, file-level consent, redaction patterns (secrets/IDs) |
| DoS | Large pathological DSL file stalls UI | Productivity loss | Incremental parsing & size cap with graceful degrade |
| Elevation | Malicious webview script accesses workspace | Sandbox breakout | No nodeIntegration, message schema validation, CSP locked |

## 5. Parsing & Validation Hardening
- All parsing is pure & deterministic (no network, filesystem writes, dynamic `require` except optional YAML which is local).
- Input size guard (TODO): If document > N lines (e.g. 5000) -> skip advanced normalization, emit performance diagnostic.
- Diagnostics do not echo entire user payload slices; messages minimize sensitive echo.

## 6. Webview Security
Current Controls:
- CSP: `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-<rand>'; img-src data:`.
- No remote CDNs (ECharts to be locally bundled). 
- No inline event handlers; single boot script with nonce.
Planned Enhancements:
- DOMPurify (or minimal sanitizer) only if future user-generated HTML needed (not currently).
- Message schema validation: enforce `{command: string, ...}` shape before acting.

## 7. Subprocess / PowerShell Strategy (Planned)
Execution Flow (future):
1. User invokes generation / apply command.
2. Extension builds command array: `[pwsh, '-NoProfile', '-File', scriptPath, '--arg', value]`.
3. All user-sourced values shell-escaped; no concatenated raw command strings.
4. Timeout & cancellation token. If exceeded, process killed.
5. Captured stdout/stderr truncated to max length in UI.

Hardening Ideas:
- Optional hash verification for shipped helper scripts.
- Refuse to run if workspace not trusted (VS Code trust API).
- Disallow execution if script resides outside extension or workspace root (avoid path traversal).

## 8. Configuration & Secrets
- No secrets stored currently.
- Future: Secure storage (VS Code SecretStorage) only for ephemeral tokens (never plain JSON configs).
- Redaction patterns: GUIDs, connection strings, keys via regex library before AI prompt send.

## 9. Dependency & Supply Chain
Immediate Steps:
- Pin exact versions (no caret) once initial dependency install stabilizes.
- Add integrity hashes (npm lockfile) at packaging stage.
- Pre-publish script to run `npm audit --production` (fail on high severity).
Future:
- Consider `ossf/scorecard` CI gating.
- Evaluate reproducible build (deterministic bundler config + lockfile).

## 10. Telemetry (Preview – Off by Default)
- Config key: `statesmith.telemetry.enabled` default false.
- Allowed events (draft): activation, parse timing aggregated (bucketed), non-identifying error codes.
- Exclusions: document contents, file names, environment variables.
- Circuit breaker: If telemetry send fails repeatedly, auto-disable for session.

## 11. AI / MCP Integration Guardrails (Planned)
- Role separation: Read-only analysis vs code generation actions.
- User confirmation required before applying AI-suggested edits (diff preview panel).
- Prompt Composition: System prefix forbidding secrets exfiltration + disclaimers.
- Output Validation: Parser re-run on AI-produced DSL; block if diagnostics severity ERROR present.

## 12. Performance & Resource Safety
- Debounced parsing (200ms) prevents thrash.
- Future memory cap: If object allocations > threshold, skip graph layout refinement.
- Webview animation frame budget target: <16ms per render (once ECharts added; measure with instrumentation message).

## 13. Logging & Audit (Planned)
| Event | Logged Fields | PII Risk | Storage |
|-------|---------------|----------|---------|
| Command Execution | commandId, durationMs, successFlag | Low | Local (dev) / Telemetry (if enabled) |
| AI Suggestion Applied | hash(diff), codes affected | Low | Local log file (rotated) |
| Parse Failure | code, durationMs | None | Output channel + optional telemetry |

## 14. Open Questions
| Topic | Question | Status |
|-------|----------|--------|
| PowerShell Sandbox | Should we enforce Constrained Language Mode? | Investigate feasibility |
| ECharts License | Confirm license compat for offline bundling | Pending review |
| Secret Redaction | Library vs custom regex set | Evaluate libs |
| AI Model Choice | On-device vs cloud inference risk trade-off | Pending MCP design |

## 15. Security Checklist (Running)
- [x] CSP locked down (no remote eval)
- [x] No remote network calls in current code
- [x] Parsing side-effect free
- [ ] Max document size guard
- [ ] Provider allow-list enforcement
- [ ] Execution gating by workspace trust
- [ ] Subprocess escaping utility
- [ ] Diff approval flow for AI changes
- [ ] Telemetry event allow-list & schema validation
- [ ] Local ECharts bundling (no CDN)

## 16. Immediate Action Items
| Priority | Item | Rationale |
|----------|------|-----------|
| High | Implement provider allow-list in parser normalization | Prevent arbitrary provider injection |
| High | Add workspace trust check before execution features | Align with VS Code security model |
| Medium | Introduce size/complexity guard for parser | Avoid perf DoS |
| Medium | Build subprocess argument escaper util | Prevent injection risk |
| Medium | Local ECharts bundle & CSP review | Avoid remote code |
| Low | Basic redaction util scaffolding | AI readiness |

## 17. Roadmap Integration
Map to existing TODO items:
- Security & sandbox review (this document)
- Telemetry plan (separate doc – will cross-reference sections 10 & 13)
- MCP Plan (extends sections 11 & 14)
- Risk Register (derive from threat model & open questions)

## 18. Revision Plan
| Version | Trigger | Expected Changes |
|---------|---------|------------------|
| 0.2 | After subprocess bridge prototype | Finalize execution controls |
| 0.3 | After AI/MCP initial integration | Add prompt & diff audit specs |
| 0.4 | Pre VSIX preview | Harden dependency + telemetry gating |

---
*End of document – iterate early & often.*
