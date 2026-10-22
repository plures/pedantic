# Pedantic

**Pedantic is a local-first, PX-governed toolkit for validating, planning, and
operating DSC v3 configurations.**

Current release: **0.11.0**. Pedantic makes the boundary between configuration
intent and host effects explicit: native tools parse and validate documents
offline, while governed operations are admitted by PX procedures, recorded by
the profile service, and executed only through bounded capabilities.

## Why Pedantic

DSC tooling often couples authoring, policy, and host-side execution. Pedantic
separates them:

- **Offline-first authoring** — parse, validate, plan, and export reports
  without opening a service store or contacting a target.
- **Governed effects** — service-backed operations require an admitted request,
  explicit approval, and scoped authorization before an adapter can act.
- **Durable evidence** — the local service owns the profile's PluresDB store
  and emits redacted Chronos projections.
- **Bounded execution** — agents and provider packs execute typed contracts;
  they do not make policy decisions.

The repository also retains a PowerShell module for compatibility. It is a
legacy surface, not the supported path for governed or remote operations. See
[legacy documentation](docs/legacy/index.md) for its historical material.

## Quick start

Build the native CLI with Rust, then validate and plan a DSC v3 document:

```powershell
cd rust
cargo run -p pedantic -- validate ../examples/simple-install.dsc.yaml
cargo run -p pedantic -- plan ../examples/simple-install.dsc.yaml
```

The first command validates document structure and exits non-zero on errors.
The second emits a deterministic plan; neither command applies a configuration.

Export validation results for CI:

```powershell
cargo run -p pedantic -- export sarif ../examples/simple-install.dsc.yaml
```

## Native capabilities

| Capability | Use |
| --- | --- |
| `parse`, `validate`, `plan` | Offline DSC v3 inspection and deterministic planning |
| `export junit` / `export sarif` | CI-consumable validation reports |
| `service health` / `service evidence` | Authenticated reads from a profile-local service |
| Service remediation commands | PX-governed, Windows-local DSC remediation after approval and authorization |
| Target agent and provider packs | Durable, typed execution of authorized capabilities |

Service commands require `PEDANTIC_LOCAL_TOKEN` and a running local
`pedantic-service`; they never open the live PluresDB store directly.

## Documentation

The documentation site is built with MkDocs:

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Core module reference](docs/reference/core-modules.md)
- [Guides and examples](docs/guides/validation-and-planning.md)
- [Key concepts](docs/concepts/governed-operations.md)
- [Architecture decisions](docs/adr/0001-pedantic-service-store-ownership.md)
- [Changelog](CHANGELOG.md)

Serve it locally when MkDocs is installed:

```powershell
mkdocs serve
```

## Development

```powershell
cd rust
cargo test
cargo clippy -- -W clippy::all
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance and
[the documentation index](docs/index.md) for the complete knowledge base.

## License

Apache-2.0. See [LICENSE](LICENSE).
