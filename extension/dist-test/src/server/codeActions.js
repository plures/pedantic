"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getCodeActions = getCodeActions;
const node_1 = require("vscode-languageserver/node");
/**
 * Provides code actions (quick fixes) for DSL diagnostics
 */
function getCodeActions(diagnostics, documentText) {
    const actions = [];
    for (const diagnostic of diagnostics) {
        // Action 1: "Add missing packages key" - when dsc.install exists but no packages
        if (diagnostic.code === 'DSL002' && diagnostic.message.includes('packages')) {
            actions.push({
                title: 'Add missing packages key',
                kind: node_1.CodeActionKind.QuickFix,
                diagnostics: [diagnostic],
                edit: {
                    changes: {
                        '': [
                            node_1.TextEdit.insert({ line: diagnostic.range.end.line + 1, character: 0 }, '  packages:\n    - ')
                        ]
                    }
                }
            });
        }
        // Action 2: "Expand string to object" - Convert simple form to object form
        // This would apply to any package line that's in simple form
        if (documentText) {
            const lines = documentText.split('\n');
            const lineText = lines[diagnostic.range.start.line];
            if (lineText && lineText.trim().startsWith('- ') && !lineText.includes('name:')) {
                const match = lineText.match(/^\s*-\s+(.+)/);
                if (match) {
                    const pkgName = match[1].trim();
                    actions.push({
                        title: 'Expand to object form',
                        kind: node_1.CodeActionKind.RefactorRewrite,
                        edit: {
                            changes: {
                                '': [
                                    node_1.TextEdit.replace({
                                        start: { line: diagnostic.range.start.line, character: 0 },
                                        end: { line: diagnostic.range.start.line, character: lineText.length }
                                    }, `    - name: ${pkgName}\n      method: winget`)
                                ]
                            }
                        }
                    });
                }
            }
        }
        // Action 3: "Remove unknown field" - when DSL008 diagnostic present
        if (diagnostic.code === 'DSL008') {
            const lineStart = diagnostic.range.start.line;
            const lineEnd = diagnostic.range.end.line;
            actions.push({
                title: 'Remove unknown field',
                kind: node_1.CodeActionKind.QuickFix,
                diagnostics: [diagnostic],
                edit: {
                    changes: {
                        '': [
                            node_1.TextEdit.del({
                                start: { line: lineStart, character: 0 },
                                end: { line: lineEnd + 1, character: 0 }
                            })
                        ]
                    }
                }
            });
        }
    }
    return actions;
}
