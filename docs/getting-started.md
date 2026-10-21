# Getting started

## Prerequisites

- Rust toolchain compatible with the workspace edition (2024).
- A DSC v3 YAML configuration, such as
  [`simple-install.dsc.yaml`](https://github.com/plures/pedantic/blob/main/examples/simple-install.dsc.yaml).

The offline workflow does not need a running service, a local token, or DSC
installed on the host.

## Validate a configuration

From the repository root:

```powershell
cd rust
cargo run -p pedantic -- validate ../examples/simple-install.dsc.yaml
```

Validation prints `OK` when the document meets the native structural rules and
returns a non-zero exit code otherwise.

## Inspect and plan

```powershell
cargo run -p pedantic -- parse ../examples/simple-install.dsc.yaml
cargo run -p pedantic -- plan ../examples/simple-install.dsc.yaml
```

`parse` prints Pedantic's parsed representation. `plan` produces a
deterministic proposed execution plan; neither command invokes DSC or changes
the machine.

## Produce CI reports

```powershell
cargo run -p pedantic -- export junit ../examples/simple-install.dsc.yaml
cargo run -p pedantic -- export sarif ../examples/simple-install.dsc.yaml
```

Capture the standard output in the format expected by your CI system. See
[Validate and plan](guides/validation-and-planning.md) for an end-to-end
workflow.

## Next steps

- Review [the CLI reference](reference/cli.md).
- Learn how the [profile-local service](concepts/local-service.md) protects
  live state.
- Use [governed remediation](guides/governed-remediation.md) only when its
  prerequisites are met.
