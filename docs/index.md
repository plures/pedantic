# Pedantic documentation

Pedantic is a local-first DSC v3 toolchain that keeps validation, authorization,
execution, and evidence as distinct concerns. Its current native release
combines an offline Rust CLI with a profile-local service, typed operation
contracts, and bounded capability adapters.

## Start here

1. Follow [Getting started](getting-started.md) to validate a configuration
   without changing a host.
2. Read [Architecture](architecture.md) to understand the service and execution
   boundaries.
3. Use the [validation and planning guide](guides/validation-and-planning.md)
   for CI-ready report exports.
4. Review [governed remediation](guides/governed-remediation.md) before
   requesting any host effect.

## Documentation map

- **Concepts** explain local service ownership, PX decisions, authorization, and
  evidence.
- **Guides** provide safe procedures for the supported operation paths.
- **Reference** describes the CLI, versioned contracts, and every core Rust
  module.
- **Examples** point to maintained DSC documents in this repository.
- **Legacy** retains retired designs and compatibility material for historical
  context. It is not a release contract.

## Supported boundaries

Offline commands (`parse`, `validate`, `plan`, and report export) are safe to
run without a service. Service-backed remediation is Windows-local and requires
a running authenticated service, a fresh accepted observation, explicit
approval, and a plan-bound authorization. Remote remediation and bootstrap
paths are not documented as supported operations.

For release history, consult the
[changelog](https://github.com/plures/pedantic/blob/main/CHANGELOG.md).
