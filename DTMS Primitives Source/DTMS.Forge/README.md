# DTMS.Forge

`DTMS.Forge` is the declarative workflow-authoring layer for `DTMS.Runway`.
Forge owns plans, dependency-ordered steps, caller-context preparation,
staging, retry policy, and controller selection. Runway exclusively owns
operation identity, authoritative state, events, worker packaging, scheduled
tasks, execution accounts, suspension, reboot continuation, and federation.

## Build and launch a workflow

```powershell
$steps = @(
    New-ForgeCopyStep `
        -Name stage-payload `
        -Source '\\files\software\Payload' `
        -Destination Payload

    New-ForgeStep `
        -Name install `
        -DependsOn stage-payload `
        -Description 'Install the staged payload.' `
        -ScriptBlock {
            param($Context)
            $setup = Join-Path $Context.StagingRoot 'Payload\setup.exe'
            $process = Start-Process $setup '/quiet' -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                throw "Installer returned $($process.ExitCode)."
            }
        }
)

$plan = New-ForgePlan -Name Install-Payload -Step $steps
Start-ForgePlan -Plan $plan -ComputerName server01
```

The default execution account comes from `DTMS.Configuration` and is
`USME\_is_dtms_util$` unless overridden. Use `-ExecutionAccount SYSTEM` only
for work that specifically requires LocalSystem.

## Controller modes

- `Direct`: local orchestration with WinRM target sessions.
- `RemoteController`: connect to a named OpenSSH controller profile and run
  orchestration on the jump/utility server.
- `Tunnel`: establish an SSH local forward to the target WinRM endpoint and
  orchestrate through that tunnel.

OpenSSH profiles contain per-user public connection metadata and private-key
paths. DTMS never generates, copies, or persists users' private keys.

## Recovery

Each execution step has its own checkpoint below the Runway operation root.
Completed steps are not replayed. Interrupted or failed steps require review
unless the step explicitly enables `RetryInterrupted` or `RetryFailed`.
Scripts can return `Suspend-DurableOperation` or
`Request-DurableOperationReboot` to pause without being marked complete.

Version 2 is intentionally a clean break. The former `TaskForge` commands,
state format, scheduler, and worker were removed rather than retained as a
second execution engine.
