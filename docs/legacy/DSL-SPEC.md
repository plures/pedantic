# Pedantic DSL Specification (v0.1 Draft)

This specification defines two authoring dialects that produce a unified canonical AST consumed by the Pedantic toolchain and execution bridge.

## 1. Scope & Goals

- Provide concise, readable configuration for Desired State Configuration (DSC) scenarios (initial focus: package installation).
- Support **two dialects**:
  1. **Simple DSL (YAML)** – key/value + arrays (low barrier, ops-focused).
  2. **SudoLang DSL** – verb-centric pseudo-language optimized for conversational & AI-assisted generation.
- Guarantee deterministic transformation: Dialect → AST → Canonical Simple DSL → DSC YAML.
- Allow safe evolution via explicit feature versioning and error / warning codes.

## 2. File Conventions

| Dialect | Extensions | Language ID (planned) | Notes |
|---------|------------|-----------------------|-------|
| Simple | `.simple.dsc.yaml`, `.simple.dsc.yml`, legacy `.simple.yaml` | `statesmith-simple` | Canonical serialization target |
| SudoLang | `.ssudo`, `.sudolang` | `statesmith-sudo` | Reversible subset; some constructs may downgrade |

## 3. Canonical AST (Simplified)

```ts
interface Document {
  kind: 'Document';
  dialect: 'simple' | 'sudo';
  version: '0.1';
  metadata?: Meta;              // future: name, description
  blocks: Block[];              // sequence of top-level logical operations
  diagnostics?: Diagnostic[];   // parser/validator generated
}

type Block = InstallBlock; // Future: ConfigureBlock, EnsureServiceBlock, etc.

interface InstallBlock {
  kind: 'InstallBlock';
  packages: PackageSpec[];
  sourceLocation?: SourceRange;
}

interface PackageSpec {
  kind: 'PackageSpec';
  id: string;              // canonical key (normalized lowercase; underscores -> dash)
  display?: string;        // original user token (for round-trip fidelity)
  providerOverride?: ProviderId; // optional method override
  executableOverride?: ExecutableSpec; // mutually exclusive with providerOverride
  version?: string;        // optional semantic or tag (e.g. latest)
  options?: Record<string,string|boolean|number>;
  sourceLocation?: SourceRange;
}

interface ExecutableSpec {
  path: string;
  args?: string[]; // already tokenized, no quoting
}

// Provider IDs (base set)
export type ProviderId = 'winget' | 'chocolatey' | 'msi' | 'apt' | 'yum' | 'brew' | 'unknown';

interface Diagnostic {
  code: string; // e.g., DSL001
  severity: 'error' | 'warning' | 'info';
  message: string;
  range: SourceRange;
  related?: RelatedInfo[];
}
```

## 4. Simple DSL Grammar (YAML Structural Schema)

The Simple DSL is a *structural subset* of YAML; only specific key paths are interpreted.

Top-level keys (current):

- `dsc.install`: object defining install context.

Schema (JSON Schema style pseudo):

```json
{
  "type": "object",
  "required": ["dsc.install"],
  "properties": {
    "dsc.install": {
      "type": "object",
      "required": ["packages"],
      "properties": {
        "packages": {
          "type": "array",
          "items": { "anyOf": [
            { "type": "string" },
            { "type": "object", "required": ["name"],
              "properties": {
                "name": { "type": "string" },
                "method": { "type": "string" },
                "version": { "type": "string" },
                "executable": { "type": "string" },
                "path": { "type": "string" },
                "args": { "type": "string" }
              },
              "additionalProperties": false }
          ]}
        }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false
}
```

### Normalization Rules

1. Package strings are treated as `{ name: <string> }`.
2. `name` canonicalized: trim whitespace, lowercase, replace internal spaces with `-`.
3. If `executable` present → create `executableOverride` ignoring `method`.
4. If `method` present and not known → diagnostic (warning), provider set to `unknown` (still forwarded to underlying engine if possible).

## 5. SudoLang DSL (v0.1 Subset)

### Informal Grammar (EBNF)

```text
Document      ::= (NL | Statement)* EOF
Statement     ::= InstallStmt | EnsureStmt
InstallStmt   ::= 'install' 'package'? PackageRef (ViaClause)? (VersionClause)? NL
EnsureStmt    ::= 'ensure' 'package' PackageRef (ViaClause)? (VersionClause)? NL
PackageRef    ::= STRING | IDENT
ViaClause     ::= 'via' ProviderIdent
VersionClause ::= 'version' (IDENT | STRING)
ProviderIdent ::= 'winget' | 'chocolatey' | 'msi' | 'apt' | 'yum' | 'brew'
IDENT         ::= /[A-Za-z0-9_.-]+/
STRING        ::= '"' <any non-quote>* '"'
NL            ::= /\r?\n/
```
Multiple packages can be declared sequentially; they are aggregated into a single `InstallBlock` during AST normalization (maintaining original order).

### Examples

```text
install git via winget version latest
install nodejs via winget
ensure package "Docker.DockerDesktop" via winget
install package customTool via chocolatey version 1.2.3
```

### Round-trip Notes

- When converting SudoLang → Simple DSL, packages become items under `dsc.install.packages`.
- Version and provider overrides map directly to `version` and `method` respectively.
- Future groups (e.g., `group devtools:`) deferred until post v0.2.

## 6. Validation Rules & Error Codes

| Code | Severity | Condition | Suggested Fix |
|------|----------|----------|---------------|
| DSL001 | error | Missing required key `dsc.install` | Add `dsc.install:` root object |
| DSL002 | error | `packages` missing or empty | Provide at least one package entry |
| DSL003 | error | Unknown top-level key | Remove or rename key |
| DSL004 | warning | Duplicate package name after normalization | Rename or consolidate entries |
| DSL005 | warning | Unknown method/provider value | Use supported provider or remove method |
| DSL006 | error | Both `executable` and `method` supplied | Choose exactly one override strategy |
| DSL007 | error | `executable` provided without `path` | Supply `path` or remove `executable` |
| DSL008 | warning | Unrecognized extra field in package object | Remove unsupported field |
| DSL009 | info | Lossy round-trip (SudoLang feature not representable) | Accept or refactor construct |
| DSL010 | error | Syntax error (SudoLang tokenization) | Correct syntax around token |
| DSL099 | warning | Document exceeds size heuristic (>5000 lines) | Split / modularize config; remove unused entries |

Advisory / performance heuristic diagnostics use the 09x series (starting with `DSL099`). They do **not** block generation but highlight likely degradation or maintainability concerns. Tools MAY choose to suppress these in terse output modes. See Section 16 for performance rationale.

## 7. Completions (Phase Targets)

| Context | Suggestions | Ranking Strategy |
|---------|-------------|------------------|
| Root (Simple) | `dsc.install` | Unique required key first |
| `dsc.install.` | `packages` | Only when absent |
| Package object key | `name`, `method`, `version`, `executable`, `path`, `args` | Required `name` prioritized |
| SudoLang provider after `via` | Provider list | Based on platform preference order |
| Version after `version` | `latest`, semver hints (if cached) | `latest` top |

Dynamic sources: Known package IDs from config file (when implemented) appended with lower rank.

## 8. Hovers

- Package entry (Simple or SudoLang): show resolved canonical ID, chosen provider (predicted), planned command preview.
- Method/provider token: provider description & fallback order.
- Version token: if matches semantic pattern, show normalized semver parse; else literal.

## 9. Diagnostics Lifecycle

1. Parse phase collects structural & token diagnostics (e.g., DSL010).
2. AST normalization adds semantic diagnostics (e.g., DSL004 duplicates).
3. Provider inference adds method warnings when unknown (DSL005).
4. Round-trip attempt (SudoLang only) may append DSL009 warnings.

Diagnostics sorted by (severity desc, range start, code).

## 10. Code Actions

| Action ID | Title | Trigger Condition | Effect |
|-----------|-------|------------------|--------|
| statesmith.addPackagesKey | Add `packages` key | DSL002 | Insert empty array skeleton |
| statesmith.normalizePackage | Normalize package casing | DSL004 | Replace duplicate variant with canonical |
| statesmith.removeUnknownField | Remove unsupported field | DSL008 | Delete field text |
| statesmith.convertStringToObject | Expand string package | Cursor on string item | Replace with object template |
| statesmith.convertDialectToSimple | Convert SudoLang file to Simple DSL | SudoLang doc | Open new buffer with YAML |
| statesmith.convertDialectToSudo | Convert Simple doc to SudoLang | Simple doc | Open new buffer with SudoLang draft |

## 11. Formatting Rules

- Indentation: 2 spaces (Simple DSL canonical output).
- Key ordering (Simple DSL root): `dsc.install`, future keys alphabetical after required.
- Package object canonical field order: `name`, `method`, `version`, `executable`, `path`, `args`.
- Remove trailing spaces; ensure final newline.
- SudoLang: one statement per line; collapse multiple blank lines to one.

## 12. Extensibility (Future Keys / Blocks)

Planned (not active in v0.1):

- `dsc.configure` (system settings)
- `dsc.services` (ensure service state)
- SudoLang verbs: `service`, `configure`, `ensure file`.

Feature flag gating: new root keys produce DSL009 (info) when downgraded by older extension versions.

## 13. Test Fixture Conventions

```text
/test-fixtures/
  simple/
    install-basic.simple.dsc.yaml
    install-provider-override.simple.dsc.yaml
  sudo/
    install-basic.ssudo
  golden/
    install-basic.dsc.yaml   # final DSC output
  roundtrip/
    install-basic.ssudo.expected.simple.dsc.yaml
```
 
Hashes (SHA256) stored in `fixtures-index.json` for drift detection in CI.

## 14. Versioning & Backward Compatibility

- DSL spec version string (`Document.version`) increments minor when:
  - New optional field added.
  - New provider recognized.
- Major increment (1.x → 2.x) only when a construct becomes invalid or meaning changes; extension must provide migration code actions.

## 15. Security Considerations

- Executable overrides validated: path must be absolute or workspace-relative; arguments tokenized & sanitized.
- AI-generated content passes through same validator; rejection if any *error* severity diagnostic produced.

## 16. Performance Targets (Parsing)

| Metric | Target |
|--------|--------|
| Simple doc (200 lines) parse | < 40 ms |
| SudoLang doc (200 lines) parse | < 55 ms |
| Incremental edit (single line) reparse | < 15 ms |

### Heuristics

To protect interactive latency, a lightweight pre-parse heuristic emits `DSL099` (warning) when a document surpasses 5000 physical lines. This threshold is conservative and MAY be refined in later spec versions. The diagnostic is advisory: no semantic validation is skipped at present, but future tooling may elide expensive inference passes beyond this limit unless explicitly overridden.

## 17. Open Questions

1. Should we permit inline comments to carry semantic tags (e.g., `# statesmith:disable DSL004`)? (Proposed yes v0.2)
2. Support for version constraints (`>=`, `<`) vs simple string? (Defer until package provider capability hashed.)
3. Multi-block ordering influence (install order vs auto-sorted)? (Current: preserve author order.)

## 18. Implementation Phasing Reference

| Phase | Spec Sections Implemented |
|-------|---------------------------|
| 2 | Sections 3–4, parts of 6 (DSL001–DSL006), 7 (baseline completions) |
| 3 | Section 5, round-trip & DSL009, more code actions |
| 4 | Section 15 AI validation integration |
| 5 | Additional diagnostics for reverse mapping accuracy |
| 6 | Provider expansion (apt/yum/brew) + method inference |

---
*This is a living document; changes require PR + spec version bump with rationale.*
