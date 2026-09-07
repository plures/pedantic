# pedantic-rs

Pure-Rust rewrite of Pedantic, a DSC v3 configuration management toolkit.

## Workspace

- `pedantic-core` — domain model, parser, validator, planner, praxis engine
- `pedantic-executor` — IO layer (invokes `dsc` and transports)
- `pedantic` — CLI

## CLI

```
pedantic parse <file>
pedantic validate <file>
pedantic plan <file>
pedantic export junit <file>
pedantic export sarif <file>
pedantic resources list
PEDANTIC_LOCAL_TOKEN=<secret> pedantic service health
PEDANTIC_LOCAL_TOKEN=<secret> pedantic service evidence
```

The `service` commands are read-only clients of the Windows-local
`pedantic-service` named pipe. They return its profile-scoped health and
redacted Chronos evidence projections without opening PluresDB or invoking
DSC.

## Development

```
cargo test
cargo clippy
```
