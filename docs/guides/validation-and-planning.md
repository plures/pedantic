# Validate and plan DSC configurations

Use the native CLI before submitting a configuration for governed execution.
These commands are offline: they neither contact a target nor apply DSC.

## Validate locally

```powershell
cd rust
cargo run -p pedantic -- validate ../examples/simple-install.dsc.yaml
```

Treat a validation failure as a release-blocking configuration error. Do not
work around a failed validation by invoking a legacy apply surface.

## Generate a reviewable plan

```powershell
cargo run -p pedantic -- plan ../examples/simple-install.dsc.yaml
```

Review the plan together with the source configuration. A plan describes the
native core's proposed work; governed execution still requires the service
lifecycle described in [Governed remediation](governed-remediation.md).

## Export reports

```powershell
cargo run -p pedantic -- export junit ../examples/simple-install.dsc.yaml `
  > validation.junit.xml
cargo run -p pedantic -- export sarif ../examples/simple-install.dsc.yaml `
  > validation.sarif
```

Publish the JUnit or SARIF file through the reporting mechanism provided by
your CI system. Keep generated reports out of source control.
