# Pedantic local service

`pedantic-service` is the Windows-local transport host for Pedantic. It only
serves authenticated `service.health` requests today; it does not own data,
evaluate PX, write Chronos events, or execute effects.

The service derives a user-SID- and secret-bound pipe name, creates every
named-pipe instance with a protected DACL granting access only to that user,
and rejects remote clients. This prevents another local account from binding
the discoverable service endpoint or reading requests to a running service.

The token is transport authentication only. Effect authorization remains a PX
and PluresDB decision; no effect endpoint is registered until that evaluator
and store boundary are live.

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
