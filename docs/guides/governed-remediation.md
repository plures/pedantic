# Governed local remediation

> **Scope:** This workflow is Windows-local and requires a running authenticated
> `pedantic-service`. It does not provide remote execution, DSC bootstrap, or
> automatic resource download.

Use remediation only after the configuration has been admitted and a fresh
service observation identifies drift. The identifiers below are records
returned by the service workflow; they are not values to invent or reuse.

```powershell
$env:PEDANTIC_LOCAL_TOKEN = '<local service token>'

pedantic service remediation-request `
  --request-id remediation-1 `
  --revision-id revision-1 `
  --observation-id observation-1 `
  --actor-id operator@example.test `
  --idempotency-key change-123

pedantic service remediation-approve `
  --approval-id approval-1 `
  --request-id remediation-1 `
  --actor-id reviewer@example.test `
  --approved

pedantic service effect-authorize `
  --approval-id approval-1 `
  --request-id remediation-1 `
  --actor-id reviewer@example.test `
  --approved

pedantic service remediation-execute `
  --execution-id execution-1 `
  --authorization-id authorization-1 `
  --idempotency-key change-123 `
  --file .\configuration.dsc.yaml
```

The service binds the authorization to the accepted request and document
identity. The agent validates it before calling a bounded DSC capability.
Repeated idempotency keys return the recorded result instead of executing the
effect again.

Read [Governed operations](../concepts/governed-operations.md) for the model
and [the CLI reference](../reference/cli.md) for command arguments.
