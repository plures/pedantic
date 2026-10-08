# DTMS.WinIPAK

`DTMS.WinIPAK` supplies reboot-safe validation-cycle plans to `DTMS.Forge`.
It owns WinIPAK requirements, process invocation, accepted exit codes, and
Windows pending-reboot detection. `DTMS.Runway` owns operation state,
scheduled execution, polling, restart requests, and post-boot continuation.

```powershell
Start-WinIPAKOperation `
    -ComputerName server01 `
    -WinIPAKSource '\\files\software\WinIPAK' `
    -RequiredOsBuild 26100 `
    -MaxRuns 5
```

Requirements are composed with AND semantics and evaluated before the first
run:

- Exact or minimum OS build
- Edition and Server/Core installation type
- Required paths
- Windows Setup completion
- A self-contained Boolean `RequirementScript`

When requirements are not ready, the step returns a generic Runway suspension.
When Windows reports a pending reboot, the step records its domain checkpoint,
calls `Request-DurableOperationReboot`, and resumes only after Runway observes
a later boot session.

Interrupted WinIPAK processes are never replayed automatically. The operation
enters `NeedsReview` because process completion cannot be inferred safely.
The former WinIPAK-specific scheduled task, worker launcher, and independent
top-level state machine were removed.
