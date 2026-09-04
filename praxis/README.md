# Pedantic PX procedures

This directory contains Pedantic domain policy. Procedures and constraints must parse with the canonical PX parser before they are wired to the service. They own decisions and evidence requirements; adapters own only bounded effects.

Validate locally from PowerShell:

```powershell
pwsh -NoProfile -File ./scripts/Test-PxProcedures.ps1
```

The script builds the canonical `plures/praxis-lang` v0.1.0 N-API parser in an isolated temporary checkout, validates every local procedure, then removes the checkout. Pass `-KeepCheckout` only when investigating a parser failure. Parser success is not live enforcement proof: before connecting procedures to a runtime, register the constraints and add evaluator-based integration evidence.
