// StateSmith DSL AST definitions (aligned with DSL-SPEC.md v0.1)
// This file is intentionally minimal and framework agnostic.

export type Dialect = 'simple' | 'sudo';

export interface Document {
  kind: 'Document';
  dialect: Dialect;
  version: '0.1';
  metadata?: Meta;
  blocks: Block[];
  diagnostics?: Diagnostic[];
}

export interface Meta {
  name?: string;
  description?: string;
}

export type Block = InstallBlock; // future extension point

export interface InstallBlock {
  kind: 'InstallBlock';
  packages: PackageSpec[];
  sourceLocation?: SourceRange;
}

export interface PackageSpec {
  kind: 'PackageSpec';
  id: string;                 // canonical id
  display?: string;           // original token for round‑trip
  providerOverride?: ProviderId;
  executableOverride?: ExecutableSpec;
  version?: string;
  options?: Record<string, string | number | boolean>;
  sourceLocation?: SourceRange;
}

export interface ExecutableSpec {
  path: string;
  args?: string[];            // already tokenized
}

export type ProviderId = 'winget' | 'chocolatey' | 'msi' | 'apt' | 'yum' | 'brew' | 'unknown';

export interface Diagnostic {
  code: string;               // e.g. DSL001
  severity: 'error' | 'warning' | 'info';
  message: string;
  range: SourceRange;
  related?: RelatedInfo[];
}

export interface RelatedInfo {
  message: string;
  range: SourceRange;
}

export interface SourceRange {
  start: Position;
  end: Position;
}

export interface Position {
  line: number;   // 0-based
  character: number; // 0-based
}

// Convenience factory helpers
export function createEmptyDocument(dialect: Dialect): Document {
  return { kind: 'Document', dialect, version: '0.1', blocks: [], diagnostics: [] };
}

export function pushDiagnostic(doc: Document, d: Diagnostic) {
  (doc.diagnostics ||= []).push(d);
}
