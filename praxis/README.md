# Pedantic PX procedures

This directory contains Pedantic domain policy. Procedures and constraints must parse with the canonical PX parser before they are wired to the service. They own decisions and evidence requirements; adapters own only bounded effects.

Validate locally from PowerShell:

```powershell
$env:PX_DIR = (Resolve-Path ./praxis/procedures)
node C:/Users/kbristol/.openclaw/workspace/repos/plures/development-guide/scripts/validate-px-grammar.cjs
```

The live Praxis evaluator is not available in this checkout. Before connecting procedures to a runtime, register the constraints and add evaluator-based integration evidence; parser success alone is not enforcement proof.
