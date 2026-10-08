# DTMS.Runway.Federation

This module provides centralized visibility without DFS or DFS-R rights.
Target-local Runway state remains authoritative. Every configured utility
server independently pulls every registered target and maintains a complete
local index.

```powershell
Initialize-DurableOperationFederation `
    -UtilityServer PHX21ISUTIL01,PHX23ISUTIL01,SN5ISUTIL01 `
    -TargetComputerName server01,server02

Get-DurableOperationFederated -Active
Sync-DurableOperationFederation
```

Collectors run as the centrally configured gMSA and therefore require:

- gMSA password-retrieval permission on each utility server
- PowerShell remoting access from the gMSA to registered targets
- local scheduled-task and index-directory permissions

Query fan-out tolerates partial utility-server outages and deduplicates each
target/operation pair by newest `UpdatedUtc`. Active records are always kept;
only the newest configured number of terminal records are retained.
