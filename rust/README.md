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
```

## Development

```
cargo test
cargo clippy
```
