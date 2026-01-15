# StateSmith Full Roadmap Completion Plan
**Goal:** Feature-complete vision with AI, advanced visualizations, and engine evolution  
**Timeline:** 6-7 months after MVP (Phases 4-7)  
**Dependencies:** 1.0 released, stable user base established

---

## Strategic Overview

### Post-1.0 Philosophy

**Principle:** Ship value incrementally. Each phase delivers standalone features.

**Release Cadence:**
- 1.1 (Phase 4): AI/MCP foundation - 2 months after 1.0
- 1.2 (Phase 5): Advanced visualizations - 1 month after 1.1
- 1.3 (Phase 6): Engine evolution - 2 months after 1.2
- 2.0 (Phase 7): Performance & hardening - 1 month after 1.3

---

## Phase 4: MCP Server & AI Workflows

**Timeline:** 3-4 weeks  
**Version:** 1.1.0  
**Dependencies:** 1.0 shipped, positive user feedback

### Goals

1. ✅ MCP server exposing 5 AI tools
2. ✅ Diff preview UI with Apply/Reject workflow
3. ✅ Audit log for AI changes
4. ✅ Safety validation (schema, allowlist)

### Week 1: MCP Server Foundation

**Day 1-2: MCP Package Setup**

```bash
cd extension
npm install @modelcontextprotocol/sdk --save
mkdir -p src/mcp-server
```

**Files to Create:**
- `extension/src/mcp-server/server.ts` - MCP server entry point
- `extension/src/mcp-server/schema.ts` - Tool schemas
- `extension/src/mcp-server/tools/` - Individual tool implementations

**Server Implementation:**
```typescript
// server.ts
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server(
  { name: 'statesmith-mcp', version: '1.1.0' },
  { capabilities: { tools: {} } }
);

// Register tools
server.setRequestHandler('tools/list', async () => ({
  tools: [
    {
      name: 'statesmith_generateConfig',
      description: 'Generate DSL configuration from natural language or requirements',
      inputSchema: {
        type: 'object',
        properties: {
          requirements: { type: 'string', description: 'Natural language description of desired config' },
          dialect: { type: 'string', enum: ['simple', 'sudo'], default: 'simple' },
          contextPaths: { type: 'array', items: { type: 'string' } }
        },
        required: ['requirements']
      }
    },
    {
      name: 'statesmith_explainConfig',
      description: 'Add explanatory comments to existing DSL configuration',
      inputSchema: {
        type: 'object',
        properties: {
          dslText: { type: 'string', description: 'DSL configuration to explain' }
        },
        required: ['dslText']
      }
    },
    {
      name: 'statesmith_optimizeInstallPlan',
      description: 'Reorder packages and suggest optimal providers',
      inputSchema: {
        type: 'object',
        properties: {
          dslText: { type: 'string' },
          constraints: {
            type: 'object',
            properties: {
              preferOffline: { type: 'boolean' },
              speedBias: { type: 'number', minimum: 0, maximum: 1 }
            }
          }
        },
        required: ['dslText']
      }
    },
    {
      name: 'statesmith_remediateDrift',
      description: 'Generate patch DSL to remediate configuration drift',
      inputSchema: {
        type: 'object',
        properties: {
          desiredDsl: { type: 'string' },
          actualStateJson: { type: 'string', description: 'JSON of actual system state' }
        },
        required: ['desiredDsl', 'actualStateJson']
      }
    },
    {
      name: 'statesmith_reverseToDsl',
      description: 'Convert exported DSC config to DSL with confidence ratings',
      inputSchema: {
        type: 'object',
        properties: {
          exportedConfigJson: { type: 'string', description: 'JSON export from existing DSC config' }
        },
        required: ['exportedConfigJson']
      }
    }
  ]
}));

server.setRequestHandler('tools/call', async (request) => {
  const { name, arguments: args } = request.params;
  
  switch (name) {
    case 'statesmith_generateConfig':
      return await generateConfig(args);
    case 'statesmith_explainConfig':
      return await explainConfig(args);
    // ... other tools
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

**Acceptance:**
- [ ] MCP server starts via child process
- [ ] All 5 tools listed correctly
- [ ] Basic tool invocation works

---

**Day 3-4: Tool Implementation - generateConfig**

**Requirements:**
1. Parse natural language requirements
2. Generate valid DSL (Simple or SudoLang)
3. Return with rationale

**Implementation Pattern:**
```typescript
// tools/generateConfig.ts
export async function generateConfig(args: {
  requirements: string;
  dialect: 'simple' | 'sudo';
  contextPaths?: string[];
}): Promise<ToolResponse> {
  
  // 1. Analyze requirements
  const analysis = await analyzeRequirements(args.requirements);
  
  // 2. Extract package list
  const packages = extractPackages(analysis);
  
  // 3. Generate DSL
  const dsl = args.dialect === 'simple' 
    ? generateSimpleDsl(packages)
    : generateSudoDsl(packages);
  
  // 4. Validate
  const validation = args.dialect === 'simple'
    ? parseSimple(dsl)
    : parseSudo(dsl);
  
  if (validation.doc.diagnostics?.some(d => d.severity === 'error')) {
    throw new Error('Generated invalid DSL');
  }
  
  return {
    content: [{
      type: 'text',
      text: JSON.stringify({
        version: '1.1.0',
        intent: args.requirements,
        proposedDraft: dsl,
        rationale: [
          `Identified ${packages.length} packages from requirements`,
          `Used ${args.dialect} dialect as requested`,
          'All packages validated against known providers'
        ],
        risk: [],
        diffs: [{
          type: 'addition',
          content: dsl,
          description: 'New configuration generated from requirements'
        }]
      }, null, 2)
    }]
  };
}

function analyzeRequirements(text: string): Analysis {
  // Simple keyword extraction for MVP
  // Post-MVP: Use LLM for deeper analysis
  
  const packagePatterns = [
    /install\s+([A-Za-z0-9._-]+)/gi,
    /need\s+([A-Za-z0-9._-]+)/gi,
    /require\s+([A-Za-z0-9._-]+)/gi
  ];
  
  const packages = new Set<string>();
  for (const pattern of packagePatterns) {
    for (const match of text.matchAll(pattern)) {
      packages.add(match[1]);
    }
  }
  
  return {
    packages: Array.from(packages),
    providers: inferProviders(packages),
    constraints: extractConstraints(text)
  };
}
```

**Acceptance:**
- [ ] "Install Git and Node.js" generates valid DSL
- [ ] Output includes rationale array
- [ ] Generated DSL passes validation

---

**Day 5: Remaining Tools (explainConfig, optimizeInstallPlan)**

**explainConfig:**
- Parse input DSL
- Generate comment annotations for each package
- Return annotated version

**optimizeInstallPlan:**
- Parse DSL
- Apply provider scoring algorithm
- Reorder for optimal execution
- Suggest provider changes with justification

**Acceptance:**
- [ ] explainConfig adds helpful comments
- [ ] optimizeInstallPlan suggests valid improvements
- [ ] All tools return consistent response schema

---

### Week 2: AI Panel UI

**Day 6-7: Diff Preview Webview**

**Files to Create:**
- `extension/src/webviews/aiPanel.ts`
- Webview HTML with split-pane diff view

**Implementation:**
```typescript
// aiPanel.ts
export class AiPanel {
  private static instance: AiPanel | undefined;
  private currentDraft: string | undefined;
  private currentRationale: string[] = [];
  
  static createOrShow(context: vscode.ExtensionContext): AiPanel {
    if (AiPanel.instance) {
      AiPanel.instance.panel.reveal();
      return AiPanel.instance;
    }
    const panel = vscode.window.createWebviewPanel(
      'statesmithAi',
      'StateSmith AI Assistant',
      vscode.ViewColumn.Beside,
      { enableScripts: true, retainContextWhenHidden: true }
    );
    AiPanel.instance = new AiPanel(panel, context);
    return AiPanel.instance;
  }
  
  async generateFromRequirements(requirements: string) {
    // Show loading state
    this.postMessage({ command: 'loading', message: 'Generating configuration...' });
    
    // Invoke MCP tool
    const response = await invokeMcpTool('statesmith_generateConfig', {
      requirements,
      dialect: 'simple'
    });
    
    const result = JSON.parse(response.content[0].text);
    
    this.currentDraft = result.proposedDraft;
    this.currentRationale = result.rationale;
    
    // Show diff
    this.postMessage({
      command: 'showDiff',
      original: '', // Empty for new config
      proposed: result.proposedDraft,
      rationale: result.rationale,
      risk: result.risk
    });
  }
  
  private handleMessage(msg: any) {
    switch (msg.command) {
      case 'apply':
        this.applyDraft();
        break;
      case 'reject':
        this.rejectDraft();
        break;
      case 'generate':
        this.generateFromRequirements(msg.requirements);
        break;
    }
  }
  
  private async applyDraft() {
    if (!this.currentDraft) return;
    
    // Log to audit trail
    await this.logAuditEntry({
      timestamp: new Date().toISOString(),
      tool: 'generateConfig',
      original: '',
      proposed: this.currentDraft,
      rationale: this.currentRationale,
      action: 'applied'
    });
    
    // Create new file or update active editor
    const doc = await vscode.workspace.openTextDocument({
      content: this.currentDraft,
      language: 'yaml'
    });
    
    await vscode.window.showTextDocument(doc);
    
    this.postMessage({ command: 'applied' });
    this.currentDraft = undefined;
  }
}
```

**Webview HTML (diff view):**
```html
<div class="ai-panel">
  <div class="input-section">
    <textarea id="requirements" placeholder="Describe desired configuration..."></textarea>
    <button onclick="generate()">Generate</button>
  </div>
  
  <div id="loading" style="display:none">
    <div class="spinner"></div>
    <p>Generating configuration...</p>
  </div>
  
  <div id="diff-section" style="display:none">
    <div class="rationale">
      <h3>AI Rationale</h3>
      <ul id="rationale-list"></ul>
    </div>
    
    <div class="diff-view">
      <div class="pane">
        <h4>Current</h4>
        <pre id="original"></pre>
      </div>
      <div class="pane">
        <h4>Proposed</h4>
        <pre id="proposed"></pre>
      </div>
    </div>
    
    <div class="actions">
      <button onclick="apply()" class="primary">Apply Changes</button>
      <button onclick="reject()">Reject</button>
    </div>
  </div>
</div>
```

**Acceptance:**
- [ ] AI panel opens with input field
- [ ] Generate button invokes MCP tool
- [ ] Diff displays side-by-side
- [ ] Apply creates new document
- [ ] Reject clears preview

---

**Day 8: Audit Log**

**Files to Create:**
- `.statesmith/changes/` directory (gitignored)
- `extension/src/auditLog.ts`

**Implementation:**
```typescript
// auditLog.ts
export interface AuditEntry {
  timestamp: string;
  tool: string;
  original: string;
  proposed: string;
  rationale: string[];
  risk: string[];
  action: 'applied' | 'rejected';
  user?: string;
}

export async function logAuditEntry(entry: AuditEntry) {
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!workspaceRoot) return;
  
  const auditDir = path.join(workspaceRoot, '.statesmith', 'changes');
  await fs.mkdir(auditDir, { recursive: true });
  
  const filename = `${entry.timestamp.replace(/:/g, '-')}.json`;
  const filepath = path.join(auditDir, filename);
  
  await fs.writeFile(filepath, JSON.stringify(entry, null, 2));
}

export async function getRecentAuditEntries(limit: number = 10): Promise<AuditEntry[]> {
  // ... read and parse JSON files
}
```

**Acceptance:**
- [ ] Each AI action logged to `.statesmith/changes/`
- [ ] Audit files contain full context
- [ ] Directory auto-created
- [ ] Cleanup command (remove old entries)

---

### Week 3-4: Safety & Testing

**Day 9-10: Schema Validation**

**Tasks:**
- [ ] JSON Schema for all tool responses
- [ ] Validate AI output before displaying
- [ ] Reject malformed responses

**Implementation:**
```typescript
import Ajv from 'ajv';

const ajv = new Ajv();

const toolResponseSchema = {
  type: 'object',
  required: ['version', 'intent', 'proposedDraft', 'rationale'],
  properties: {
    version: { type: 'string', pattern: '^\\d+\\.\\d+\\.\\d+$' },
    intent: { type: 'string' },
    proposedDraft: { type: 'string' },
    rationale: { type: 'array', items: { type: 'string' } },
    risk: { type: 'array', items: { type: 'string' } },
    diffs: {
      type: 'array',
      items: {
        type: 'object',
        required: ['type', 'content', 'description'],
        properties: {
          type: { enum: ['addition', 'modification', 'deletion'] },
          content: { type: 'string' },
          description: { type: 'string' }
        }
      }
    }
  }
};

const validateResponse = ajv.compile(toolResponseSchema);

export function validateToolResponse(response: any): boolean {
  if (!validateResponse(response)) {
    console.error('Invalid tool response:', validateResponse.errors);
    return false;
  }
  return true;
}
```

**Acceptance:**
- [ ] Invalid responses rejected
- [ ] User shown error message
- [ ] Malformed JSON doesn't crash extension

---

**Day 11-12: Allowlist & Constraints**

**Resource Type Allowlist:**
```typescript
const ALLOWED_RESOURCE_TYPES = new Set([
  'package',
  'file',
  'registry',
  'service',
  'user',
  'group'
]);

function validateProposedDsl(dsl: string): ValidationResult {
  const parsed = parseSimple(dsl);
  
  for (const block of parsed.blocks) {
    if (block.kind === 'InstallBlock') {
      // Packages always allowed
      continue;
    }
    
    if (!ALLOWED_RESOURCE_TYPES.has(block.kind.toLowerCase())) {
      return {
        valid: false,
        reason: `Unsafe resource type: ${block.kind}`
      };
    }
  }
  
  return { valid: true };
}
```

**Acceptance:**
- [ ] Only allowed resource types accepted
- [ ] Unsafe proposals rejected with reason
- [ ] User can configure allowlist (future)

---

**Day 13-14: Integration Tests**

**Test Scenarios:**
1. Generate valid DSL from requirements
2. Apply changes creates correct file
3. Reject clears state
4. Audit log entries created
5. Invalid responses handled gracefully
6. MCP server restarts on crash

**Acceptance:**
- [ ] All integration tests pass
- [ ] MCP server tested with mocked AI responses
- [ ] Error paths covered

---

### Phase 4 Deliverables

- [x] MCP server with 5 tools
- [x] AI panel with diff preview
- [x] Audit log for all changes
- [x] Schema validation
- [x] Safety allowlist
- [x] Integration test suite

**Release:** Version 1.1.0

---

## Phase 5: Advanced Visualizations

**Timeline:** 2-3 weeks  
**Version:** 1.2.0  
**Dependencies:** Phase 4 complete

### Features

1. ✅ Drift dashboard (test results ingestion)
2. ✅ Reverse explorer (DSC → DSL with confidence)
3. ✅ AI design canvas (live edits + proposals)
4. ✅ Graph enhancements (dependency inference)

### Week 1: Drift Dashboard

**Goal:** Show configuration drift insights

**Implementation:**
- Ingest DSC test results (JSON)
- Display drift summary (packages out of sync)
- Highlight affected resources in graph
- "Fix drift" action (calls remediateDrift tool)

**Acceptance:**
- [ ] Dashboard shows drift count
- [ ] Clicking item shows details
- [ ] Fix action generates remediation DSL

---

### Week 2: Reverse Explorer

**Goal:** Import existing DSC configs

**Implementation:**
- Parse exported DSC JSON
- Map to DSL constructs
- Assign confidence scores (100% = perfect match, <100% = guessed)
- Show heat-map view

**Acceptance:**
- [ ] Import wizard functional
- [ ] Confidence map displayed
- [ ] User can review/edit before saving

---

### Week 3: AI Design Canvas

**Goal:** Live editing with AI suggestions

**Implementation:**
- Split editor: DSL on left, AI panel on right
- As user types, AI suggests completions
- User accepts/rejects inline
- Changes logged to audit

**Acceptance:**
- [ ] Live suggestions appear
- [ ] Accept/reject workflow smooth
- [ ] No performance degradation

---

## Phase 6: Engine Evolution

**Timeline:** 4-6 weeks  
**Version:** 1.3.0  
**Dependencies:** Phase 5 complete

### Features

1. ✅ Provider abstraction (winget/choco/msi/apt/yum/brew)
2. ✅ Install plan optimizer (strategy scoring)
3. ✅ Caching/offline manager
4. ✅ Partial JS port (resource checks)

### Tasks

**Week 1-2: Provider Abstraction**
- Define provider interface
- Implement adapters for each manager
- Strategy scoring (speed, reliability, offline)

**Week 3-4: Install Plan Optimizer**
- Dependency graph analysis
- Topological sort for execution order
- Provider selection based on constraints

**Week 5-6: Caching & Offline**
- Package cache management
- Offline staging workflow
- Hash verification

---

## Phase 7: Hardening & 2.0 Release

**Timeline:** 2-3 weeks  
**Version:** 2.0.0  
**Dependencies:** Phases 4-6 complete

### Goals

1. ✅ Performance optimization (profiling, benchmarks)
2. ✅ Security audit (external review)
3. ✅ Telemetry implementation (opt-in)
4. ✅ Documentation suite complete
5. ✅ Marketplace stable release

### Tasks

**Week 1: Performance & Security**
- Profile hot paths
- Optimize parse/LSP performance
- External security review
- Fix vulnerabilities

**Week 2: Telemetry & Docs**
- Implement opt-in telemetry
- Privacy policy
- User guide (complete)
- AI safety guide
- SDK documentation

**Week 3: Release**
- 2.0.0 RC testing
- Release to marketplace
- Marketing push
- Community engagement

---

## Full Roadmap Timeline Summary

| Phase | Version | Duration | Deliverables |
|-------|---------|----------|--------------|
| MVP | 0.1.0 | 3-4 weeks | LSP, parsers, graph, bridge |
| 1.0 | 1.0.0 | +4 weeks | Polish, security, marketplace |
| Phase 4 | 1.1.0 | +3-4 weeks | MCP, AI tools, audit log |
| Phase 5 | 1.2.0 | +2-3 weeks | Drift, reverse, canvas |
| Phase 6 | 1.3.0 | +4-6 weeks | Providers, optimizer, cache |
| Phase 7 | 2.0.0 | +2-3 weeks | Performance, security, telemetry |

**Total:** 18-24 weeks (4.5-6 months) from MVP to 2.0

---

## Success Metrics (2.0)

### Adoption
- [ ] 5000+ active users
- [ ] 100+ GitHub stars
- [ ] 10+ contributors

### Quality
- [ ] ≥4.5 star marketplace rating
- [ ] <1% crash rate
- [ ] Performance budgets met

### Community
- [ ] Active discussions forum
- [ ] Regular feature requests
- [ ] Case studies published

### Business
- [ ] Enterprise adoption (5+ companies)
- [ ] Integration partnerships (DSC vendors)
- [ ] Sustainable maintenance model

---

## Conclusion

This plan delivers the full roadmap vision incrementally over 6-7 months. Each phase adds significant value while maintaining stability and user trust.

**Key Principles:**
1. Ship early, ship often
2. User feedback drives priorities
3. Quality over features
4. Community-first development

**Next Step:** Complete MVP (3-4 weeks) → Start Phase 4 planning
