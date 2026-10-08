# DTMS.Configuration

`DTMS.Configuration` owns the versioned configuration contract shared by all
DTMS utility modules. The default file is:

`C:\ProgramData\DTMS\Configuration\DTMS.Utilities.json`

## Runtime policy

PowerShell 7.x is the primary DTMS runtime. Windows PowerShell 5.1 is retained
as a compatibility floor for hosts that cannot yet run PowerShell 7.

The module manifest therefore declares `PowerShellVersion = '5.1'`. PowerShell
interprets this field, and `#requires -Version 5.1`, as a minimum version rather
than a preferred or exact version. The `DTMSRuntime` manifest metadata records
PowerShell Core 7.x as the preferred runtime. With the default
`Execution.PowerShellEngine = 'Auto'`, Runway selects `pwsh.exe` when available
and falls back to Windows PowerShell only when necessary.

Built-in defaults use `USME\_is_dtms_util$` for durable execution, prefer
PowerShell 7, place tasks under `\DTMS\`, and keep Runway state under
`C:\ProgramData\DTMS\Runway\Operations`.

```powershell
Initialize-DTMSConfiguration
$configuration = Get-DTMSConfiguration
```

Configuration precedence is:

1. Built-in organization defaults
2. Versioned JSON configuration
3. Supported environment overrides
4. Per-operation overrides

Named OpenSSH controller profiles contain `HostName`, `UserName`,
`IdentityFile`, and optionally `Port`. Private key material is never stored in
DTMS configuration and is never generated or distributed automatically.
