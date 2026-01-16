// Simple DSL structural parser (YAML subset) - v0.1
// NOTE: Intentionally tolerant: collects diagnostics, continues when possible.

import { createEmptyDocument, Document, InstallBlock, PackageSpec, pushDiagnostic } from './ast';
import { parseDocument } from 'yaml';

type YamlDoc = any; // fallback type

// Diagnostic codes reused from spec where applicable
const Codes = {
  MissingRoot: 'DSL001',
  MissingPackages: 'DSL002',
  UnknownTop: 'DSL003',
  DuplicatePackage: 'DSL004',
  UnknownMethod: 'DSL005',
  BothExecAndMethod: 'DSL006',
  ExecMissingPath: 'DSL007',
  UnknownField: 'DSL008'
} as const;

export interface SimpleParserOptions {
  allowUnknownTopLevel?: boolean;
}

export function parseSimple(source: string, opts: SimpleParserOptions = {}): Document {
  const doc = createEmptyDocument('simple');
  // Size / complexity guard (initial simple heuristic): warn if very large to surface potential performance impact.
  try {
    const lineCount = source.split(/\r?\n/).length;
    const LINE_THRESHOLD = 5000; // configurable future option
    if (lineCount > LINE_THRESHOLD) {
      pushDiagnostic(doc, { code: 'DSL099', severity: 'warning', message: `Document has ${lineCount} lines (> ${LINE_THRESHOLD}); performance may degrade. Advanced normalization may be limited.`, range: zr() });
    }
  } catch { /* ignore size computation errors */ }
  let yaml: YamlDoc | undefined;
  try {
    yaml = parseDocument(source);
  } catch (e: any) {
    pushDiagnostic(doc, { code: 'DSL010', severity: 'error', message: 'YAML syntax error: ' + e.message, range: zr() });
    return doc;
  }
  const root = yaml.toJS({}) as any;
  if (!root || typeof root !== 'object') {
    pushDiagnostic(doc, { code: Codes.MissingRoot, severity: 'error', message: 'Document must contain dsc.install root.', range: zr() });
    return doc;
  }
  const allowedTop = new Set(['dsc.install']);
  for (const k of Object.keys(root)) {
    if (!allowedTop.has(k) && !opts.allowUnknownTopLevel) {
      pushDiagnostic(doc, diag(Codes.UnknownTop, `Unknown top-level key '${k}'`));
    }
  }
  const install = root['dsc.install'];
  if (!install) {
    pushDiagnostic(doc, diag(Codes.MissingRoot, 'Missing required key dsc.install'));
    return doc;
  }
  if (typeof install !== 'object') {
    pushDiagnostic(doc, diag(Codes.MissingRoot, 'dsc.install must be an object'));
    return doc;
  }
  const pkgs = install['packages'];
  if (!Array.isArray(pkgs) || pkgs.length === 0) {
    pushDiagnostic(doc, diag(Codes.MissingPackages, 'packages must be a non-empty array'));
  }
  const block: InstallBlock = { kind: 'InstallBlock', packages: [] };
  const seen = new Map<string, PackageSpec>();
  if (Array.isArray(pkgs)) {
    for (const entry of pkgs) {
      const pkg = normalizePackage(entry, doc);
      if (!pkg) continue;
      const prev = seen.get(pkg.id);
      if (prev) {
        pushDiagnostic(doc, diag(Codes.DuplicatePackage, `Duplicate package '${pkg.id}'`));
      } else {
        seen.set(pkg.id, pkg);
      }
      block.packages.push(pkg);
    }
  }
  doc.blocks.push(block);
  return doc;
}

function normalizePackage(raw: any, doc: Document): PackageSpec | undefined {
  if (typeof raw === 'string') {
    return makePackage(raw, raw);
  }
  if (!raw || typeof raw !== 'object') {
    pushDiagnostic(doc, diag('DSL010', 'Invalid package entry (must be string or object)'));
    return undefined;
  }
  const name = raw.name ?? raw.id ?? raw.package;
  if (!name || typeof name !== 'string') {
    pushDiagnostic(doc, diag('DSL010', 'Package object missing name field'));
    return undefined;
  }
  const canonical = canonicalize(name);
  const provider = typeof raw.method === 'string' ? raw.method.trim().toLowerCase() : undefined;
  const executable = raw.executable || raw.path ? { path: raw.path || raw.executable, args: splitArgs(raw.args) } : undefined;
  if (provider && executable) {
    pushDiagnostic(doc, diag('DSL006', 'Both method and executable/path specified'));
  }
  if (executable && !executable.path) {
    pushDiagnostic(doc, diag('DSL007', 'Executable override missing path'));
  }
  if (provider && !isKnownProvider(provider)) {
    pushDiagnostic(doc, diag('DSL005', `Unknown provider '${provider}'`));
  }
  const allowedFields = new Set(['name','method','version','executable','path','args']);
  for (const k of Object.keys(raw)) {
    if (!allowedFields.has(k)) {
      pushDiagnostic(doc, diag('DSL008', `Unknown field '${k}' in package '${name}'`));
    }
  }
  return {
    kind: 'PackageSpec',
    id: canonical,
    display: name,
  providerOverride: provider ? (isKnownProvider(provider) ? provider as any : 'unknown') : undefined,
    executableOverride: executable,
    version: typeof raw.version === 'string' ? raw.version : undefined,
    options: undefined
  };
}

function makePackage(name: string, display?: string): PackageSpec {
  return { kind: 'PackageSpec', id: canonicalize(name), display: display ?? name };
}

function canonicalize(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, '-');
}

function isKnownProvider(p: string): boolean {
  return ['winget','chocolatey','msi','apt','yum','brew'].includes(p);
}

function splitArgs(a: any): string[] | undefined {
  if (typeof a !== 'string') return undefined;
  return a.match(/[^"\s]+|"[^"]*"/g) || undefined;
}

function diag(code: string, message: string) {
  return { code, severity: code.startsWith('DSL00') && ['DSL004','DSL005','DSL008'].includes(code) ? 'warning' as const : 'error' as const, message, range: zr() };
}

function zr() { return { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }; }
