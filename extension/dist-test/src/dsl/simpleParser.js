"use strict";
// Simple DSL structural parser (YAML subset) - v0.1
// NOTE: Intentionally tolerant: collects diagnostics, continues when possible.
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseSimple = parseSimple;
const ast_1 = require("./ast");
const yaml_1 = require("yaml");
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
};
function parseSimple(source, opts = {}) {
    const doc = (0, ast_1.createEmptyDocument)('simple');
    // Size / complexity guard (initial simple heuristic): warn if very large to surface potential performance impact.
    try {
        const lineCount = source.split(/\r?\n/).length;
        const LINE_THRESHOLD = 5000; // configurable future option
        if (lineCount > LINE_THRESHOLD) {
            (0, ast_1.pushDiagnostic)(doc, { code: 'DSL099', severity: 'warning', message: `Document has ${lineCount} lines (> ${LINE_THRESHOLD}); performance may degrade. Advanced normalization may be limited.`, range: zr() });
        }
    }
    catch { /* ignore size computation errors */ }
    let yaml;
    try {
        yaml = (0, yaml_1.parseDocument)(source);
    }
    catch (e) {
        (0, ast_1.pushDiagnostic)(doc, { code: 'DSL010', severity: 'error', message: 'YAML syntax error: ' + e.message, range: zr() });
        return doc;
    }
    const root = yaml.toJS({});
    if (!root || typeof root !== 'object') {
        (0, ast_1.pushDiagnostic)(doc, { code: Codes.MissingRoot, severity: 'error', message: 'Document must contain dsc.install root.', range: zr() });
        return doc;
    }
    const allowedTop = new Set(['dsc.install']);
    for (const k of Object.keys(root)) {
        if (!allowedTop.has(k) && !opts.allowUnknownTopLevel) {
            (0, ast_1.pushDiagnostic)(doc, diag(Codes.UnknownTop, `Unknown top-level key '${k}'`));
        }
    }
    const install = root['dsc.install'];
    if (!install) {
        (0, ast_1.pushDiagnostic)(doc, diag(Codes.MissingRoot, 'Missing required key dsc.install'));
        return doc;
    }
    if (typeof install !== 'object') {
        (0, ast_1.pushDiagnostic)(doc, diag(Codes.MissingRoot, 'dsc.install must be an object'));
        return doc;
    }
    const pkgs = install['packages'];
    if (!Array.isArray(pkgs) || pkgs.length === 0) {
        (0, ast_1.pushDiagnostic)(doc, diag(Codes.MissingPackages, 'packages must be a non-empty array'));
    }
    const block = { kind: 'InstallBlock', packages: [] };
    const seen = new Map();
    if (Array.isArray(pkgs)) {
        for (const entry of pkgs) {
            const pkg = normalizePackage(entry, doc);
            if (!pkg)
                continue;
            const prev = seen.get(pkg.id);
            if (prev) {
                (0, ast_1.pushDiagnostic)(doc, diag(Codes.DuplicatePackage, `Duplicate package '${pkg.id}'`));
            }
            else {
                seen.set(pkg.id, pkg);
            }
            block.packages.push(pkg);
        }
    }
    doc.blocks.push(block);
    return doc;
}
function normalizePackage(raw, doc) {
    if (typeof raw === 'string') {
        return makePackage(raw, raw);
    }
    if (!raw || typeof raw !== 'object') {
        (0, ast_1.pushDiagnostic)(doc, diag('DSL010', 'Invalid package entry (must be string or object)'));
        return undefined;
    }
    const name = raw.name ?? raw.id ?? raw.package;
    if (!name || typeof name !== 'string') {
        (0, ast_1.pushDiagnostic)(doc, diag('DSL010', 'Package object missing name field'));
        return undefined;
    }
    const canonical = canonicalize(name);
    const provider = typeof raw.method === 'string' ? raw.method.trim().toLowerCase() : undefined;
    const executable = raw.executable || raw.path ? { path: raw.path || raw.executable, args: splitArgs(raw.args) } : undefined;
    if (provider && executable) {
        (0, ast_1.pushDiagnostic)(doc, diag('DSL006', 'Both method and executable/path specified'));
    }
    if (executable && !executable.path) {
        (0, ast_1.pushDiagnostic)(doc, diag('DSL007', 'Executable override missing path'));
    }
    if (provider && !isKnownProvider(provider)) {
        (0, ast_1.pushDiagnostic)(doc, diag('DSL005', `Unknown provider '${provider}'`));
    }
    const allowedFields = new Set(['name', 'method', 'version', 'executable', 'path', 'args']);
    for (const k of Object.keys(raw)) {
        if (!allowedFields.has(k)) {
            (0, ast_1.pushDiagnostic)(doc, diag('DSL008', `Unknown field '${k}' in package '${name}'`));
        }
    }
    return {
        kind: 'PackageSpec',
        id: canonical,
        display: name,
        providerOverride: provider ? (isKnownProvider(provider) ? provider : 'unknown') : undefined,
        executableOverride: executable,
        version: typeof raw.version === 'string' ? raw.version : undefined,
        options: undefined
    };
}
function makePackage(name, display) {
    return { kind: 'PackageSpec', id: canonicalize(name), display: display ?? name };
}
function canonicalize(s) {
    return s.trim().toLowerCase().replace(/\s+/g, '-');
}
function isKnownProvider(p) {
    return ['winget', 'chocolatey', 'msi', 'apt', 'yum', 'brew'].includes(p);
}
function splitArgs(a) {
    if (typeof a !== 'string')
        return undefined;
    return a.match(/[^"\s]+|"[^"]*"/g) || undefined;
}
function diag(code, message) {
    return { code, severity: code.startsWith('DSL00') && ['DSL004', 'DSL005', 'DSL008'].includes(code) ? 'warning' : 'error', message, range: zr() };
}
function zr() { return { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }; }
