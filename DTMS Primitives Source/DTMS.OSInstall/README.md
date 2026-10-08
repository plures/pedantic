# DTMS.OSInstall

`DTMS.OSInstall` supplies Windows Server Setup plans to `DTMS.Forge`.
Forge stages media under the caller's identity; `DTMS.Runway` executes and
tracks Setup under the centrally configured gMSA.

## Compatibility scan

```powershell
Start-WindowsServerInstall `
    -ComputerName server01 `
    -MediaSource '\\files\images\WindowsServer' `
    -Operation Scan `
    -AcceptEula
```

## In-place upgrade

```powershell
Start-WindowsServerInstall `
    -ComputerName server01 `
    -MediaSource '\\files\images\WindowsServer2025' `
    -Operation Upgrade `
    -TargetBuild 26100 `
    -AcceptEula
```

Setup completion and installed image validation are separate durable steps.
The validation step suspends through Runway while Setup or OOBE remains active.
Interrupted steps are only retried because their scripts first inspect durable
markers and current Windows state rather than blindly launching Setup again.

## Guarded clean installation

`CleanInstall` uses Setup `/auto clean`; it removes files, applications, and
settings and is not bare-metal deployment or secure erasure. It accepts
exactly one target, and `CleanInstallConfirmation` must exactly equal that
computer name:

```powershell
Start-WindowsServerInstall `
    -ComputerName server01 `
    -MediaSource '\\files\images\WindowsServer' `
    -Operation CleanInstall `
    -CleanInstallConfirmation server01 `
    -AcceptEula
```

Before Setup starts, the workflow creates a portable `/postoobe` hook. Because
the clean operation removes the original scheduled task and local state, this
hook reconstructs a terminal Runway record under the same operation ID and
validates the installed build, edition, and Server/Core type. That terminal
record is then visible to the generic federated collector.

Compatibility scans and in-place upgrades are the primary supported
workflows. Clean installation is an advanced destructive operation and must be
validated against the target image's preservation behavior before production
use.
