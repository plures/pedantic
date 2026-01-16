import { Document } from '../dsl/ast';

/**
 * Formats a Simple DSL document to canonical form
 */
export function formatSimpleDsl(doc: Document): string {
  const lines: string[] = [];
  
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
            } else if (exec.path) {
              lines.push(`      executable: ${exec.path}`);
              if (exec.args && exec.args.length > 0) {
                lines.push(`      args: ${exec.args.join(' ')}`);
              }
            }
          }
        } else {
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
export function wouldFormat(source: string, doc: Document): boolean {
  const formatted = formatSimpleDsl(doc);
  return formatted !== source;
}
