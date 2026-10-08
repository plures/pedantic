# DTMS.Runway.Dfs

Optional DFS-R registry provider for DTMS.Runway. Local operation state remains
authoritative; registry publication is asynchronous through each operation's
outbox.

```powershell
Initialize-DurableOperationDfsRegistry `
    -NamespacePath '\\contoso.com\Services\DTMS\Operations' `
    -UtilityServer UTIL01,UTIL02 `
    -WriterPrincipal 'CONTOSO\DTMS-Operation-Writers' `
    -ReaderPrincipal 'CONTOSO\DTMS-Operation-Readers'
```

Query or retry publication:

```powershell
Get-DurableOperationRegistry
Sync-DurableOperationRegistry -OperationRoot C:\ProgramData\DTMS\Runway\Operations\<id>
```
