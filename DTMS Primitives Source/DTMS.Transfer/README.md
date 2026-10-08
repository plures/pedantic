# DTMS.Transfer

DTMS.Transfer separates transfer requirements from transport implementation.

```powershell
$request = New-DurableTransferRequest `
    -Source '\\server\share\disk.vhdx' `
    -Destination 'D:\VMs\disk.vhdx' `
    -Transport Auto `
    -RequireResume `
    -PreserveAcl

Invoke-DurableTransfer -Request $request
```

`Auto` selects only an installed provider satisfying required capabilities.
Robocopy provides restartable SMB copies and Windows metadata preservation.
SCP provides encrypted SSH transfer but is not advertised as restartable.
BITS provides service-backed restartable SMB file transfer.

All providers can write normalized JSONL telemetry with `-MetricsPath`.
Samples contain transferred and total bytes, percent complete, elapsed time,
instantaneous and average Mbps, ETA, provider, and status.
