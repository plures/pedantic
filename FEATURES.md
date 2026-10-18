# Registered Features

Generated from the full PluresLM `feature:pedantic:*` registry. Do not edit this view independently.

The historical product feature inventory has not yet been reconciled. This view is not a complete product QA scope, and source-control tests are not runtime QA.

| Feature | Description | Status | Introduced | Last verified version | QA result | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| Native source provenance hold | Repository-only hold for unresolved legacy inputs: inventory and Git object checks, Git archive exclusion, literal runtime reference rejection, and independent negative-control tests. Does not establish license clearance or service-backed DSC acceptance. | in_review | unreleased | not yet qualified | not_run; source-control regression tests only | plures/pedantic #271 |
| VS Code 1.90 package compatibility | Restore API declarations and language-client compatibility with the documented minimum host; guard automated incompatible upgrades and validate the actual VSIX using an isolated CLI-installed profile with bounded cleanup. | in_review | unreleased baseline repair | not yet qualified | 68 unit tests and minimum-host VSIX smoke passed locally; not full product QA | plures/pedantic baseline compatibility |
