# Rebranding Plan and Naming Evaluation

> **STATUS: COMPLETED** - The project has been unified under the name "Pedantic" to match the repository name. This document is kept for historical reference.

Previously selected name: StateSmith (not implemented)

This document evaluates the repository naming and outlines the plan that was considered but ultimately reversed - the project is now named "Pedantic" to match the repository.

## Name evaluation: "Pedantic"

Pros

- Memorable and distinctive; conveys attention to detail
- Short, easy to type; available as a unique brand in some ecosystems

Cons/Risks

- "Pedantic" can imply nitpicking or inflexibility; may read negatively
- Does not signal what the project does (DSC helper/DSL)
- Harder for new users to discover or infer purpose from name alone

Conclusion

If branding for broad adoption, consider a purpose-revealing name ("SimpleDSC", "DSC Kit", etc.). If targeting a niche internal audience and the name has context, keeping it may be okay. For public/open-source, a clearer name is recommended.

## Naming goals

- Communicate scope: DSC v3 helper + lightweight DSL
- Neutral-positive tone; professional
- Short, pronounceable; easy to search
- Avoid collisions with established DSC modules

## Alternative name ideas (with angles)

- SimpleDSC – Clear and descriptive; aligns with the "Simple" DSL and existing `SimpleDSC` resource
- DSCraft – Suggests tools/crafting for DSC; short and brandable
- DSC Kit – Toolkit connotation; familiar
- DSC Pilot – Guides DSC operations; evokes control and reliability
- DSC Bridge – Bridges DSL and DSC v3; descriptive
- DSCworks – Practical, action-oriented; brandable
- DscLift – Lightweight helper that "lifts" friction; short
- DscFlow – Emphasizes smooth workflows; positive
- Dialtone.DSC – If Dialtone remains a brand umbrella; consistent
- StateSmith – State management and clarity; metaphorical but positive

Shortlist (recommend evaluating availability): SimpleDSC, DSCraft, DscFlow, DSC Kit.

## Rename decision points

- Module naming conventions (PowerShell): Prefer PascalCase and clarity, e.g., `SimpleDSC` or `DscFlow`.
- Public function prefixes: Keep existing `*-Dsc*` verbs/nouns for continuity.
- Resource packs: `SimpleDSC.PackageInstaller` already uses the SimpleDSC motif; synergy with `SimpleDSC` module name is strong.

## Implementation plan

Pre-work

- Choose the final name (placeholder below: NEWNAME)
- Reserve package namespace if publishing to PowerShell Gallery later
- Update license and repository metadata

Step-by-step

1. Repository and folder

- Rename repository to `NEWNAME` (or `SimpleDSC` if selected)
- If needed, rename the top folder from `Pedantic` to `NEWNAME`

1. PowerShell module manifests and files

- Legacy-named modules have been removed; StateSmith-only modules replace them.
  - Option B: Rename to `NEWNAME.DSC` or consolidate into `NEWNAME` with subfolders
- Update `ModuleVersion`, `Author`, `CompanyName`, `GUID` (new), `Description`, `PrivateData.PSData` (Tags, LicenseUri, ProjectUri, IconUri)
- Decide whether `DSCHelper.ps1` functionality becomes public cmdlets inside the main module; if so, integrate and remove the standalone script or keep it as a thin wrapper

1. Simple DSL modules

- Consolidate `Simple.DSC.Basic.psm1` and `Simple.DSC.psm1` under a clear module name:
  - If `SimpleDSC` is chosen:
    - Primary module: `SimpleDSC.psd1/psm1`
    - Experimental/basic converter moved to `examples` or `contrib`
- Update docs to reflect the primary path

1. Resource pack alignment

- Resource pack already uses `SimpleDSC.PackageInstaller` – this strongly favors choosing `SimpleDSC` as the project name for brand cohesion
- Ensure `DscResourcesToExport` and manifests reference the final module name correctly

1. Code changes (search/replace with care)

- Search strings: `Pedantic` and any prior brand mentions in READMEs and comments. Replace with StateSmith.
- Update: module imports, paths, examples in docs, and function references
- Add alias/shims if renaming public module names to avoid breaking existing users (e.g., temporary meta-module that re-exports)

1. Documentation and assets

- Update `README.md` to reflect new name, scope, and getting started
- Add `ROADMAP.md` (done) and keep up to date
- Add `CHANGELOG.md` using Keep a Changelog format
- Consider a minimal logo/icon in `/assets` if helpful

1. CI/CD and distribution

- Add/rename build pipelines to produce module artifacts under the new name
- Update gallery publishing scripts (if applicable)
- Tag a pre-release (e.g., `v0.9.0`) under the new name and include migration notes

1. Migration notes (BREAKING CHANGES section)

- If module name changes:
  - Old: `Import-Module <old module name>` → New: `Import-Module StateSmith.DSC`
  - Provide a transitional period: a thin module that depends on the new one and re-exports public functions (or explicit aliases)
- If namespaces/classes change, document equivalent mappings

## Rebranding checklist

- [x] Final name chosen: NEWNAME = StateSmith
- [ ] Repo renamed and description updated
- [ ] Module manifests updated (`.psd1`): metadata, GUIDs, Tags, URIs
- [ ] Public API stabilized and names aligned
- [ ] Docs updated: README, Simple-DSC-README, ROADMAP, this guide
- [ ] Examples and YAML files renamed if they embed names
- [ ] CI/CD updated
- [ ] Pre-release tagged and migration notes published

## Recommendation

- Preferred new name: SimpleDSC
  - Rationale: aligns with existing `SimpleDSC.PackageInstaller`, clearly communicates purpose, positive/neutral tone, short and memorable.
- Backup options: DscFlow, DSCraft

If you decide to keep "Pedantic", add a tagline/subtitle everywhere to clarify scope, e.g.,

> Pedantic – a simple DSC v3 helper and DSL

and ensure README leads with what it does rather than the brand.
