# DTMS.Utilities

`DTMS.Utilities` is a thin umbrella that loads the focused DTMS operational
modules. It does not implement domain behavior or durable execution itself.

## Runtime policy

DTMS.Utilities is PowerShell 7.x-first. Windows PowerShell 5.1 remains a
supported compatibility runtime. Manifest `PowerShellVersion = '5.1'` and
`#requires -Version 5.1` declarations identify the minimum compatible version;
they do not select or prefer Windows PowerShell. Runway's default `Auto` engine
uses `pwsh.exe` when available and falls back to Windows PowerShell only when a
PowerShell 7 runtime is unavailable.

## Architecture

| Module | Responsibility |
|---|---|
| `DTMS.Configuration` | Versioned organization defaults, federation settings, and named OpenSSH controller profiles |
| `DTMS.Runway` | Durable identity, state, events, workers, scheduled tasks, suspension, and reboot continuation |
| `DTMS.Runway.Federation` | No-DFS utility-server pull indexes for all Runway operations |
| `DTMS.Runway.Dfs` | Optional legacy DFS event-registry provider |
| `DTMS.Forge` | Declarative DAG plans, dependency validation, caller-context preparation, and controller selection |
| `DTMS.Transfer` | Robocopy, SCP, and BITS transfer providers and telemetry |
| `DTMS.OpenSSH` | OpenSSH management, controller sessions, and WinRM tunnels |
| `DTMS.OSInstall` | Windows Server compatibility scan and installation plans |
| `DTMS.WinIPAK` | Reboot-safe WinIPAK validation-cycle plans |
| `DTMS.VMHelper` | Hyper-V discovery, migration, transfer, and configuration workflows |

```powershell
Import-Module .\DTMS.Utilities.psd1
Get-DTMSUtilitiesModule
Get-DTMSUtilitiesReadiness
```

Scheduled workers and tests should import with quiet startup:

```powershell
Import-Module .\DTMS.Utilities.psd1 -ArgumentList 'Quiet'
```

## Central configuration

```powershell
Initialize-DTMSConfiguration
$configuration = Get-DTMSConfiguration
```

The default file is
`C:\ProgramData\DTMS\Configuration\DTMS.Utilities.json`. The organization
default durable account is `USME\_is_dtms_util$`; individual plans may
override it, including explicit `SYSTEM` execution.

Named OpenSSH profiles enable two equal workstation launch modes:

- Remote controller: orchestration runs on a jump/utility server.
- Tunnel: orchestration remains on the workstation through a forwarded WinRM
  endpoint.

Profiles reference per-user private keys already present on the workstation.
DTMS never generates or distributes those private keys.

## Operation model

Domain modules create Forge plans. Preparation steps run as the network-capable
caller. Forge stages the plan and asks Runway to execute it durably under the
configured account. Runway owns all persistent operation state and can suspend
for prerequisites or resume after reboot.

Target-local state is authoritative. `DTMS.Runway.Federation` independently
pulls that state to every configured utility server and provides deduplicated
near-real-time queries without requiring DFS permissions.
