# DTMS.Runway

DTMS.Runway provides shared infrastructure for long-running PowerShell
operations. Domain modules declare a versioned operation handler and payload;
Runway owns durable state, append-only local events, progress, worker
packaging, and Windows scheduled-task execution.

Imports are read-only by default and report missing required capabilities.

## Immediate activity feedback

Long-running public commands use one shared lifecycle:

```powershell
$activity = Start-DTMSActivity `
    -Name 'Example operation' `
    -Intent 'Validate inputs and process every target'

Update-DTMSActivity `
    -Activity $activity `
    -Status 'Processing target 3 of 10.' `
    -PercentComplete 30

Complete-DTMSActivity `
    -Activity $activity `
    -Status 'All targets were processed.'
```

`Start-DTMSActivity` writes an Information-stream intent message immediately,
before blocking work begins. Adaptive mode renders rotating progress frames in
interactive terminals and emits periodic textual heartbeats during remoting or
redirected execution. Activity messages never enter the success pipeline.

Set `DTMS_FEEDBACK_MODE` to `Adaptive`, `Animated`, `Concise`, or `Quiet`.
`Adaptive` is the default. `Quiet` is intended for tests and scheduled workers.

```powershell
Import-Module .\DTMS.Runway.psd1
Get-DurableOperationReadiness
Initialize-DurableOperationEnvironment
```

Create a declarative operation:

```powershell
$definition = New-DurableOperationDefinition `
    -OperationType 'Example.Operation' `
    -HandlerModulePath .\Example.psd1 `
    -HandlerCommand Invoke-ExampleOperation `
    -Payload @{ Name = 'Example' }

Start-DurableOperation -Definition $definition
```

The handler command receives `OperationRoot` and `Payload`. It reports state
through `Set-DurableOperationPhase` and `Write-DurableOperationProgress`.
Preparation and module staging run as the caller. The worker defaults to the
centrally configured DTMS gMSA (`USME\_is_dtms_util$` by default); specify
`SYSTEM` explicitly for machine-local work that must use LocalSystem.

Handlers can suspend safely without being marked complete:

```powershell
Suspend-DurableOperation `
    -OperationRoot $OperationRoot `
    -Reason 'Waiting for an external prerequisite.' `
    -ResumeAfterUtc ([DateTime]::UtcNow.AddMinutes(15))
```

For reboot-spanning work, `Request-DurableOperationReboot` records the current
boot session before requesting a restart. Runway resumes only after it observes
a later boot session. Every Runway task has startup and periodic triggers, so
waiting operations resume without a module-specific scheduler.
