# Pedantic Capability Ownership Matrix

**Status:** Phase 0 baseline. This inventory records the current entry points and their intended PX-first owner. It must be updated before any legacy surface is retired.

| Current surface | Current entry points | Target capability | End-state owner | Migration disposition |
|---|---|---|---|---|
| PowerShell module | `Validate-DscConfiguration`, `Set-DscConfiguration`, `Test-DscConfiguration`, `Export-DscConfiguration` | configuration lifecycle, compliance, remediation | PX + Pedantic service | Compatibility client after service parity |
| PowerShell module | cache and resource functions; `Repair-DscInstallation`; `New-SecureRemoteSession` | resource catalog, capability effect | service effect adapter | Preserve only as adapter where DSC CLI lacks parity |
| PowerShell module | `Get-Head`, `Get-Tail` | text utility | PowerShell compatibility package | Retain outside operational domain |
| Rust core | DSC parser, validator, planner, `praxis` engine | normalized document model and decision lifecycle | contracts + PX | Retire duplicated imperative policy; retain parser only if required as an adapter |
| Rust executor | local/SSH DSC runner and inventory | DSC and transport effects | `pedantic-dsc-adapter`, `pedantic-transport` | Move without new policy |
| Rust CLI | `parse`, `validate`, `plan`, `export`, `resources`, `update`, `service health`, `service evidence` | service client and offline tooling | CLI client | Read-only service client exists for health/evidence; identify any operational offline-only mode explicitly |
| Rust MCP | resource list/get/test/export; config validate/export | automation API | service MCP facade | Remove unrestricted direct DSC operations |
| VS Code extension | authoring, language server, graph, inventory, fact gather, push config | editor projection and command submission | VS Code service client | Keep syntax-only diagnostics local; migrate operational commands |
| Radix plugin | config browser, compliance dashboard/history, widgets | Radix projection | Modulus-published service client | Replace local compliance store with service projections |
| Standalone app | absent | primary local operator workflow | Svelte/Tarui + Unum service client | New surface in Phase 3 |

## Required migration evidence

An entry point may change disposition only after the target capability has a PX procedure, contract test, service integration test, and cross-surface task result. A passing compile or parser check is not parity evidence.
