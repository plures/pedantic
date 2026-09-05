# Pedantic local service

`pedantic-service` is the Windows-local transport host and the sole owner of a
profile-scoped embedded PluresDB store. On startup it opens
`%LOCALAPPDATA%\Pedantic\profiles\<profile>\pluresdb` and records a
metadata-only `service.started` event in its PluresDB-backed Chronos timeline.
The health response exposes only the bounded evidence count. Authenticated
`evidence.list` returns at most 100 redacted Chronos summaries (event ID,
timestamp, actor, action, and level), never store data, pipe names, or
credentials.

The service derives a user-SID- and secret-bound pipe name, creates every
named-pipe instance with a protected DACL granting access only to that user,
and rejects remote clients. This prevents another local account from binding
the discoverable service endpoint or reading requests to a running service.

The token is transport authentication only. `configuration.admit` is the first
live PX Lang admission boundary: it evaluates the canonical
`configuration_requires_source_digest` constraint, persists the resulting
configuration projection, and records a Chronos entry. It does not yet claim
full PX procedure/dataflow execution or effect authorization; those remain PX
and PluresDB decisions rather than imperative host policy.

`configuration.validate` accepts only an admitted revision whose supplied
document hashes to the admitted source digest. Those preconditions are live PX
constraints. The service then invokes `dsc config validate` through the DSC
adapter with a 30-second bound, stores only the normalized validation state,
and records redacted Chronos evidence; it never retains the document or raw
adapter output.

## Run

```powershell
Set-Location rust
$env:PEDANTIC_LOCAL_TOKEN = "replace-with-a-random-secret-of-at-least-32-bytes"
cargo run -p pedantic-service -- --profile default
```

## Verify

```powershell
cargo check -p pedantic-service
cargo test -p pedantic-service
cargo clippy -p pedantic-service -- -D warnings
```
