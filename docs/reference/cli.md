# CLI reference

The `pedantic` binary has two command families.

## Offline commands

| Command | Result |
| --- | --- |
| `pedantic parse <file>` | Prints the parsed DSC v3 document |
| `pedantic validate <file>` | Prints `OK` or validation errors and exits non-zero |
| `pedantic plan <file>` | Prints a deterministic plan |
| `pedantic export junit <file>` | Prints a JUnit validation report |
| `pedantic export sarif <file>` | Prints a SARIF validation report |
| `pedantic resources list` | Lists built-in resource metadata |

These commands do not open a profile store or execute DSC.

## Service commands

| Command | Result |
| --- | --- |
| `pedantic service [--profile <name>] health` | Reads the service health projection |
| `pedantic service [--profile <name>] evidence` | Reads redacted Chronos evidence |
| `pedantic service remediation-request ...` | Submits a PX-governed request bound to revision and observation |
| `pedantic service remediation-approve ...` | Records explicit approval or denial |
| `pedantic service effect-authorize ...` | Requests a narrow effect authorization |
| `pedantic service remediation-execute ...` | Executes an authorized Windows-local DSC remediation |

Service commands require `PEDANTIC_LOCAL_TOKEN` and a running local service.
They are clients of the service API and never open PluresDB directly.

Use `pedantic --help` and `pedantic service --help` for exact flags. Consult
[Governed local remediation](../guides/governed-remediation.md) before using an
effect command.
