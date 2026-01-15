# Pedantic MVP Execution Plan
**Target:** Ship functional VS Code extension for improved DSC authoring  
**Timeline:** Q1 2026  
**Effort:** 11-17 developer days

---

## MVP Features (Must-Have)

1. ✅ Simple DSL + SudoLang parsing with diagnostics
2. ✅ Real-time diagnostics in Problems panel (via LSP)
3. ✅ Basic completions (keys, methods, package IDs)
4. ✅ Resource graph visualization with ECharts
5. ✅ PowerShell bridge (generate DSC YAML)
6. ✅ Formatter (Simple DSL, idempotent)
7. ✅ 3 code actions (add packages, expand string, remove unknown)
8. ✅ Golden test suite (≥80% parser coverage)

---

## Week 1: LSP Foundation (Critical Path)

### Day 1-2: LSP Setup & Document Sync
**Goal:** Get extension communicating with language server

**Tasks:**
```bash
cd extension
npm install vscode-languageclient vscode-languageserver --save
```

**Files to Create:**
- `extension/src/server/server.ts` - Language server entry point
- `extension/src/client.ts` - Client connection logic

**Implementation:**
```typescript
// server.ts
import { createConnection, TextDocuments, ProposedFeatures } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

connection.onInitialize(() => ({
  capabilities: {
    textDocumentSync: 1, // Full sync
    completionProvider: { triggerCharacters: ['.', ':'] },
    diagnosticProvider: { interFileDependencies: false, workspaceDiagnostics: false }
  }
}));

documents.onDidChangeContent(change => {
  validateDocument(change.document);
});

connection.listen();
documents.listen(connection);
```

**Acceptance:**
- [ ] Language server starts when extension activates
- [ ] Server logs appear in Output → "StateSmith Language Server"
- [ ] Document sync events fire on open/edit/close

---

### Day 3-4: Diagnostics Publishing
**Goal:** Show parser errors/warnings in Problems panel

**Files to Modify:**
- `extension/src/server/server.ts` - Add `validateDocument()`
- `extension/src/dsl/simpleParser.ts` - Export position mapping
- `extension/src/dsl/sudoParser.ts` - Export position mapping

**Implementation:**
```typescript
async function validateDocument(doc: TextDocument): Promise<void> {
  const text = doc.getText();
  const uri = doc.uri;
  
  // Detect dialect by file extension or content
  const dialect = uri.endsWith('.ssudo') ? 'sudo' : 'simple';
  
  const parsed = dialect === 'sudo' 
    ? parseSudo(text) 
    : parseSimple(text);
  
  const diagnostics = parsed.doc.diagnostics?.map(d => ({
    severity: d.severity === 'error' ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
    range: {
      start: { line: d.range.start.line, character: d.range.start.character },
      end: { line: d.range.end.line, character: d.range.end.character }
    },
    message: d.message,
    code: d.code,
    source: 'statesmith'
  })) || [];
  
  connection.sendDiagnostics({ uri, diagnostics });
}
```

**Acceptance:**
- [ ] Invalid YAML shows DSL010 error in Problems panel
- [ ] Duplicate packages show DSL004 warning
- [ ] Unknown providers show DSL005 warning
- [ ] Diagnostics update on file edit (within 500ms)

---

### Day 5: Completions Provider
**Goal:** Autocomplete for keys, methods, package IDs

**Files to Modify:**
- `extension/src/server/server.ts` - Add `onCompletion` handler

**Implementation:**
```typescript
connection.onCompletion((params: CompletionParams) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  
  const text = doc.getText();
  const offset = doc.offsetAt(params.position);
  const linePrefix = text.substring(0, offset).split('\n').pop() || '';
  
  // Top-level keys
  if (linePrefix.trim() === '' || linePrefix.match(/^[a-z]/)) {
    return [
      { label: 'dsc.install', kind: CompletionItemKind.Keyword, detail: 'Install packages block' }
    ];
  }
  
  // Inside dsc.install
  if (linePrefix.includes('dsc.install:')) {
    return [
      { label: 'packages', kind: CompletionItemKind.Property, detail: 'List of packages to install' }
    ];
  }
  
  // Method values
  if (linePrefix.match(/method:\s*$/)) {
    return ['winget', 'chocolatey', 'msi', 'apt', 'yum', 'brew'].map(m => ({
      label: m,
      kind: CompletionItemKind.EnumMember,
      detail: `${m} package manager`
    }));
  }
  
  return [];
});
```

**Acceptance:**
- [ ] Typing `dsc.` shows `install` completion
- [ ] Inside `dsc.install:` shows `packages:` completion
- [ ] After `method:` shows winget, chocolatey, etc.

---

## Week 2: Testing & Bridge

### Day 6-7: Golden Test Corpus
**Goal:** Prevent parser regressions

**Files to Create:**
- `extension/test-fixtures/01-basic-install.simple.dsc.yaml`
- `extension/test-fixtures/02-multi-package.simple.dsc.yaml`
- `extension/test-fixtures/03-provider-override.simple.dsc.yaml`
- `extension/test-fixtures/04-executable-override.simple.dsc.yaml`
- `extension/test-fixtures/05-version-pinning.simple.dsc.yaml`
- `extension/test-fixtures/06-sudo-basic.ssudo`
- `extension/test/goldenTests.test.ts`

**Sample Fixture (01-basic-install.simple.dsc.yaml):**
```yaml
dsc.install:
  packages:
    - Git.Git
    - Microsoft.VisualStudioCode
```

**Test Implementation:**
```typescript
import { parseSimple } from '../src/dsl/simpleParser';
import { parseSudo } from '../src/dsl/sudoParser';
import fs from 'fs/promises';
import path from 'path';

test('golden corpus: all fixtures parse without errors', async () => {
  const fixturesDir = path.join(__dirname, '../test-fixtures');
  const files = await fs.readdir(fixturesDir);
  
  for (const file of files) {
    const content = await fs.readFile(path.join(fixturesDir, file), 'utf-8');
    const parsed = file.endsWith('.ssudo') ? parseSudo(content) : parseSimple(content);
    
    const errors = parsed.doc.diagnostics?.filter(d => d.severity === 'error') || [];
    assert.equal(errors.length, 0, `${file} should parse without errors`);
  }
});

test('round-trip: parse → regenerate → parse produces same AST', () => {
  const source = 'dsc.install:\n  packages:\n    - Git.Git\n';
  const doc1 = parseSimple(source);
  const regenerated = printSimpleDsl(doc1); // Need to implement
  const doc2 = parseSimple(regenerated);
  
  assert.deepEqual(doc1.blocks, doc2.blocks);
});
```

**Acceptance:**
- [ ] 10+ fixture files covering all DSL features
- [ ] All fixtures parse without errors
- [ ] Round-trip tests pass (within normalization)
- [ ] Test coverage ≥80% for parsers

---

### Day 8-9: PowerShell Bridge
**Goal:** Execute DSC operations from extension

**Files to Create:**
- `extension/src/bridge/schema.ts` - JSON contract types
- `extension/src/bridge/pwshBridge.ts` - Process wrapper
- PowerShell script for bridge (or use existing module)

**JSON Schema:**
```typescript
// schema.ts
export interface BridgeRequest {
  command: 'generate' | 'test' | 'set';
  dslPath: string;
  options?: {
    whatIf?: boolean;
    verbose?: boolean;
    timeout?: number; // milliseconds
  };
}

export interface BridgeResponse {
  success: boolean;
  output?: string; // DSC YAML or result
  errors?: string[];
  warnings?: string[];
  duration?: number; // milliseconds
}
```

**Bridge Implementation:**
```typescript
// pwshBridge.ts
import { spawn } from 'child_process';
import { workspace } from 'vscode';

export async function invokePwsh(request: BridgeRequest): Promise<BridgeResponse> {
  const pwshPath = workspace.getConfiguration('statesmith').get<string>('bridge.pwshPath', 'pwsh');
  const timeout = request.options?.timeout || 30000;
  
  const scriptPath = path.join(__dirname, '../../scripts/bridge.ps1');
  const args = [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', scriptPath,
    '-Command', request.command,
    '-DslPath', request.dslPath,
    '-OutputJson'
  ];
  
  return new Promise((resolve, reject) => {
    const proc = spawn(pwshPath, args, { timeout });
    let stdout = '';
    let stderr = '';
    
    proc.stdout.on('data', data => stdout += data.toString());
    proc.stderr.on('data', data => stderr += data.toString());
    
    proc.on('close', code => {
      try {
        const response: BridgeResponse = JSON.parse(stdout);
        resolve(response);
      } catch {
        resolve({ success: false, errors: [stderr || stdout] });
      }
    });
    
    proc.on('error', err => {
      reject(new Error(`PowerShell bridge failed: ${err.message}`));
    });
  });
}
```

**PowerShell Bridge Script (scripts/bridge.ps1):**
```powershell
param(
    [ValidateSet('generate', 'test', 'set')]
    [string]$Command,
    [string]$DslPath,
    [switch]$OutputJson
)

Import-Module StateSmith.DSC -ErrorAction Stop

try {
    $result = switch ($Command) {
        'generate' {
            ConvertFrom-SimpleDsc -Path $DslPath
        }
        'test' {
            Test-DscConfiguration -DscPath $DslPath
        }
        'set' {
            Set-DscConfiguration -DscPath $DslPath
        }
    }
    
    $response = @{
        success = $true
        output = $result | Out-String
        errors = @()
        warnings = @()
    }
} catch {
    $response = @{
        success = $false
        errors = @($_.Exception.Message)
        warnings = @()
    }
}

if ($OutputJson) {
    $response | ConvertTo-Json -Depth 10
} else {
    $response.output
}
```

**Acceptance:**
- [ ] `generateConfig` command produces DSC YAML output
- [ ] Timeout handling works (kills process after 30s)
- [ ] Error messages displayed to user
- [ ] Works on Windows + macOS/Linux (pwsh 7+)

---

## Week 3: UI Polish

### Day 10-11: ECharts Graph Integration
**Goal:** Professional graph visualization

**Tasks:**
```bash
cd extension
npm install echarts --save
```

**Files to Modify:**
- `extension/src/webviews/resourceGraphPanel.ts` - Replace placeholder layout

**Implementation:**
```typescript
// Generate ECharts configuration
private getEChartsHtml(nodes: GraphNode[], edges: GraphEdge[]): string {
  const nonce = Math.random().toString(36).slice(2);
  
  // ECharts data format
  const echartsData = {
    nodes: nodes.map(n => ({ 
      id: n.id, 
      name: n.label, 
      symbolSize: 40,
      category: n.type 
    })),
    links: edges.map(e => ({ 
      source: e.from, 
      target: e.to,
      label: { show: true, formatter: e.kind }
    })),
    categories: [{ name: 'package' }]
  };
  
  return `<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline';">
  <script nonce="${nonce}" src="${this.getEChartsUri()}"></script>
</head>
<body>
  <div id="graph" style="width:100%;height:600px;"></div>
  <script nonce="${nonce}">
    const chart = echarts.init(document.getElementById('graph'));
    chart.setOption({
      series: [{
        type: 'graph',
        layout: 'force',
        data: ${JSON.stringify(echartsData.nodes)},
        links: ${JSON.stringify(echartsData.links)},
        categories: ${JSON.stringify(echartsData.categories)},
        roam: true,
        label: { show: true, position: 'right' },
        force: { repulsion: 100, edgeLength: 150 }
      }]
    });
    
    chart.on('click', params => {
      if (params.dataType === 'node') {
        vscode.postMessage({ command: 'revealNode', nodeId: params.data.id });
      }
    });
  </script>
</body>
</html>`;
}
```

**Acceptance:**
- [ ] Graph renders with force-directed layout
- [ ] Nodes draggable
- [ ] Clicking node reveals source location (next task)

---

### Day 12: Node Click → Reveal Source
**Goal:** Navigate from graph to code

**Files to Modify:**
- `extension/src/webviews/resourceGraphPanel.ts` - Add message handler
- `extension/src/dsl/ast.ts` - Ensure sourceLocation populated

**Implementation:**
```typescript
// In resourceGraphPanel.ts
this.panel.webview.onDidReceiveMessage(async (msg: any) => {
  if (msg.command === 'revealNode') {
    const editor = vscode.window.activeTextEditor;
    if (!editor) return;
    
    // Find package in AST with matching ID
    const pkg = this.findPackageById(msg.nodeId);
    if (!pkg?.sourceLocation) return;
    
    const range = new vscode.Range(
      pkg.sourceLocation.start.line,
      pkg.sourceLocation.start.character,
      pkg.sourceLocation.end.line,
      pkg.sourceLocation.end.character
    );
    
    editor.selection = new vscode.Selection(range.start, range.end);
    editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
    
    vscode.window.showTextDocument(editor.document);
  }
});
```

**Acceptance:**
- [ ] Clicking node in graph highlights package in editor
- [ ] Editor scrolls to show selection
- [ ] Works for both Simple and SudoLang dialects

---

### Day 13-14: Formatter & Code Actions
**Goal:** Editor polish features

**Files to Create:**
- `extension/src/server/formatter.ts`
- `extension/src/server/codeActions.ts`

**Formatter Implementation:**
```typescript
// formatter.ts
export function formatSimpleDsl(doc: Document): string {
  const lines: string[] = [];
  lines.push('dsc.install:');
  lines.push('  packages:');
  
  for (const block of doc.blocks) {
    if (block.kind === 'InstallBlock') {
      for (const pkg of block.packages) {
        if (pkg.version || pkg.providerOverride || pkg.executableOverride) {
          // Object form
          lines.push(`    - name: ${pkg.display || pkg.id}`);
          if (pkg.version) lines.push(`      version: ${pkg.version}`);
          if (pkg.providerOverride) lines.push(`      method: ${pkg.providerOverride}`);
          // ... etc
        } else {
          // Simple form
          lines.push(`    - ${pkg.display || pkg.id}`);
        }
      }
    }
  }
  
  return lines.join('\n') + '\n';
}
```

**Code Actions:**
1. **"Add missing packages key"** - When `dsc.install:` exists but no `packages:`
2. **"Expand string to object"** - Convert `- Git.Git` to `- name: Git.Git`
3. **"Remove unknown field"** - When DSL008 diagnostic present

**Acceptance:**
- [ ] Format command produces canonical ordering
- [ ] Formatting is idempotent (format twice = no change)
- [ ] 3 code actions appear in lightbulb menu
- [ ] Actions apply correctly without errors

---

## Week 4: Testing & Polish

### Day 15-16: Test Coverage Push
**Goal:** ≥80% statement coverage

**Tasks:**
- Add unit tests for Simple parser edge cases
- Add LSP integration tests
- Add formatter round-trip tests
- Add code action tests

**Acceptance:**
- [ ] Coverage report shows ≥80% statements
- [ ] All critical paths covered (≥90% branches)
- [ ] CI runs full test suite

---

### Day 17: MVP Review & Bug Fixes
**Goal:** Ensure all acceptance criteria met

**Checklist:**
- [ ] Extension activates without errors
- [ ] Diagnostics appear in Problems panel
- [ ] Completions work for keys/methods
- [ ] Graph visualization functional
- [ ] PowerShell bridge executes successfully
- [ ] Formatter idempotent
- [ ] Code actions apply correctly
- [ ] Test coverage ≥80%
- [ ] No P0/P1 bugs

**Tasks:**
- Manual testing with sample configs
- Fix any discovered bugs
- Performance profiling (parse <40ms, completion <150ms)

---

## MVP Acceptance Criteria

### Functional
- [x] Parse both dialects without crashes
- [x] Real-time diagnostics in Problems panel
- [x] Completions for top-level keys, methods
- [x] Graph webview loads and updates on edits
- [x] PowerShell bridge generates DSC YAML
- [x] Formatter produces canonical output (idempotent)
- [x] 3 code actions functional

### Quality
- [x] Test coverage ≥80% statements
- [x] No unhandled promise rejections
- [x] Performance budgets met (parse <40ms P95)

### Documentation
- [x] README quickstart (<90 seconds)
- [x] CHANGELOG entry for MVP
- [x] Known issues documented

---

## MVP Deliverables

1. **Working Extension**
   - VSIX package (installable)
   - Source code (committed to main)
   - CI passing (all tests green)

2. **Documentation**
   - README with quickstart
   - CHANGELOG for 0.1.0
   - Known issues list

3. **Demo Materials**
   - Sample config files (5-10 examples)
   - Screenshot/GIF of graph visualization
   - Video walkthrough (optional, 2-3 minutes)

---

## Success Metrics

**MVP is successful if:**
- [ ] 10+ beta testers install and use it
- [ ] Zero P0 bugs (crashes, data loss) reported
- [ ] Positive feedback on core features (LSP, graph)
- [ ] Users create ≥20 real DSL configs with extension
- [ ] Performance acceptable on 200-line configs

**Next Phase:** 1.0 polish (4 weeks) → Marketplace launch
