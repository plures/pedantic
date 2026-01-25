"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.formatSimpleDsl = formatSimpleDsl;
exports.wouldFormat = wouldFormat;
/**
 * Formats a Simple DSL document to canonical form
 */
function formatSimpleDsl(doc) {
    const lines = [];
    for (const block of doc.blocks) {
        if (block.kind === 'InstallBlock') {
            lines.push('dsc.install:');
            lines.push('  packages:');
            for (const pkg of block.packages) {
                // Use object form if any advanced properties are present
                if (pkg.version || pkg.providerOverride || pkg.executableOverride) {
                    lines.push(`    - name: ${pkg.display || pkg.id}`);
                    if (pkg.version) {
                        lines.push(`      version: ${pkg.version}`);
                    }
                    if (pkg.providerOverride) {
                        lines.push(`      method: ${pkg.providerOverride}`);
                    }
                    if (pkg.executableOverride) {
                        const exec = pkg.executableOverride;
                        if (typeof exec === 'string') {
                            lines.push(`      executable: ${exec}`);
                        }
                        else if (exec.path) {
                            lines.push(`      executable: ${exec.path}`);
                            if (exec.args && exec.args.length > 0) {
                                lines.push(`      args: ${exec.args.join(' ')}`);
                            }
                        }
                    }
                }
                else {
                    // Simple string form
                    lines.push(`    - ${pkg.display || pkg.id}`);
                }
            }
        }
    }
    // Ensure single trailing newline
    return lines.join('\n') + '\n';
}
/**
 * Check if formatting would make changes (for idempotency testing)
 */
function wouldFormat(source, doc) {
    const formatted = formatSimpleDsl(doc);
    return formatted !== source;
}
