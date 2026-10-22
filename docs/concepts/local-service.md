# The local service

One authenticated `pedantic-service` instance owns each user/profile's live
PluresDB store and Chronos writer. This avoids divergent policy and evidence
when CLI, MCP, editor, and compatibility clients operate on the same profile.

## Client contract

Clients communicate through the versioned local API and must not open the live
store. The native CLI reads the `PEDANTIC_LOCAL_TOKEN` environment variable for
service commands and can select a profile with `--profile`.

```powershell
$env:PEDANTIC_LOCAL_TOKEN = '<local service token>'
pedantic service --profile default health
pedantic service --profile default evidence
```

The commands read service projections; they do not invoke DSC. Tokens and raw
provider output must never be placed in configuration documents, reports, or
evidence.

The service model is local-first. Shared multi-user operation needs a separate
service mode and is not implied by the local profile API.
