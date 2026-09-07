# ADR 0006: RuneBook composes Pedantic projections without owning Pedantic operations

## Status

Accepted.

## Context

Pedantic needs a visual operator experience for configuration relationships,
drift, compliance, remediation proposals, and evidence. RuneBook is an
interactive canvas environment and is therefore a strong fit for composing and
exploring that experience. A product or repository merger, however, would make
the canvas a second owner of configuration state, compliance decisions, and
DSC execution. That would violate the PX-first domain boundary and recreate
the multi-surface divergence this refactor is eliminating.

## Decision

RuneBook is integrated as a Pedantic projection and composition client, not as
the owner of the Pedantic lifecycle. Pedantic remains the source of operational
truth through its authenticated, profile-scoped service:

- PX owns admission, compliance, remediation, approval, and effect decisions.
- Pedantic owns the profile-scoped PluresDB projections and Chronos evidence.
- RuneBook reads a versioned Pedantic canvas projection and renders stable
  configuration, resource, drift, proposal, decision, and evidence nodes.
- RuneBook submits typed user intents to the Pedantic service. It never writes
  a Pedantic store record or invokes DSC, PowerShell, SSH, WinRM, or a package
  manager directly.

The first integration contract has these boundaries:

| Concern | Owner | RuneBook behavior |
| --- | --- | --- |
| Canvas node identity and provenance | Pedantic projection contract | Render stable IDs and links to configuration revision, PX decision, and Chronos event IDs. |
| Canvas layout, grouping, and annotations | RuneBook document | Keep presentation-only state separate from Pedantic operational state. |
| Configuration import or edit proposal | Pedantic command contract | Submit source/provenance for PX admission; do not mutate an admitted revision. |
| Compliance and remediation gestures | Pedantic command contract | Submit requests and display the returned decision/evidence. |
| DSC effects and credentials | Pedantic capability adapter | No RuneBook capability or fallback path. |

RuneBook and Pedantic remain independently releasable. The integration is a
thin adapter/package that depends on the versioned Pedantic service client and
declares only the read/propose capabilities it consumes. A future bundled
desktop experience may host both, but must preserve this process and data
boundary.

## Consequences

- The first deliverable is a versioned canvas projection schema plus a RuneBook
  adapter, not a database integration or repository merge.
- Each operational node must include enough provenance to navigate back to its
  Pedantic revision, PX decision identifier, and redacted Chronos evidence.
- A RuneBook-authored configuration becomes an import/proposal artifact; it is
  subject to the same Pedantic PX admission and source-digest checks as every
  other client input.
- Layout-only changes do not create Pedantic lifecycle events. Accepted
  operational commands and their effects continue to create Pedantic Chronos
  evidence.
- Before release, an integration task suite must prove that the same canvas
  scenario produces the same Pedantic decision identifiers and evidence as the
  standalone, Radix, VS Code, CLI/MCP, and PowerShell clients, and must prove
  the adapter cannot open the profile PluresDB store.
