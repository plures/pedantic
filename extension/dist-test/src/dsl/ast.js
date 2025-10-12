"use strict";
// StateSmith DSL AST definitions (aligned with DSL-SPEC.md v0.1)
// This file is intentionally minimal and framework agnostic.
Object.defineProperty(exports, "__esModule", { value: true });
exports.createEmptyDocument = createEmptyDocument;
exports.pushDiagnostic = pushDiagnostic;
// Convenience factory helpers
function createEmptyDocument(dialect) {
    return { kind: 'Document', dialect, version: '0.1', blocks: [], diagnostics: [] };
}
function pushDiagnostic(doc, d) {
    (doc.diagnostics ||= []).push(d);
}
