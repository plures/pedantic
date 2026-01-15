# StateSmith 1.0 Release Plan
**Goal:** Professional, stable extension ready for marketplace launch  
**Timeline:** MVP + 4 weeks polish/testing = 7-8 weeks total  
**Dependencies:** MVP shipped and validated by beta testers

---

## Release Readiness Checklist

### Pre-1.0 Additions (Beyond MVP)

#### 1. Hovers (Package Info & Method Docs)
**Effort:** 1 day  
**Priority:** Medium

**Implementation:**
```typescript
// In server.ts
connection.onHover((params: HoverParams) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  
  const text = doc.getText();
  const offset = doc.offsetAt(params.position);
  const wordRange = getWordRangeAtPosition(text, offset);
  const word = text.substring(wordRange.start, wordRange.end);
  
  // Package hover
  if (isPackageId(word)) {
    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: `**Package:** ${word}\n\n` +
               `Common installation methods:\n` +
               `- \`winget\`: Windows Package Manager\n` +
               `- \`chocolatey\`: Chocolatey package manager\n\n` +
               `[View on winget.run](https://winget.run/pkg/${word})`
      }
    };
  }
  
  // Method hover
  if (word === 'winget' || word === 'chocolatey' || word === 'msi') {
    const docs = methodDocs[word];
    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: `**Method:** ${word}\n\n${docs}`
      }
    };
  }
  
  return null;
});
```

**Acceptance:**
- [ ] Hovering package shows description + links
- [ ] Hovering method shows usage documentation
- [ ] Hover response <100ms

---

#### 2. Performance Budgets Enforced in CI
**Effort:** 1 day  
**Priority:** High

**Files to Create:**
- `extension/test/benchmarks.test.ts`
- `.github/workflows/performance.yml`

**Benchmark Implementation:**
```typescript
// benchmarks.test.ts
import { parseSimple } from '../src/dsl/simpleParser';
import { parseSudo } from '../src/dsl/sudoParser';

test('Simple parser: 200-line file parses <40ms P95', () => {
  const fixture = generateLargeConfig(200); // 200 packages
  const iterations = 100;
  const times: number[] = [];
  
  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    parseSimple(fixture);
    times.push(performance.now() - start);
  }
  
  times.sort((a, b) => a - b);
  const p95 = times[Math.floor(iterations * 0.95)];
  
  assert.ok(p95 < 40, `P95 parse time ${p95.toFixed(2)}ms exceeds 40ms budget`);
});

test('Completion latency: <150ms P95', async () => {
  // Similar benchmark for completions
});
```

**CI Workflow:**
```yaml
name: Performance Benchmarks

on: [push, pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 20
      - run: npm ci
        working-directory: extension
      - run: npm run benchmark
        working-directory: extension
      - name: Comment PR with results
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v6
        with:
          script: |
            // Post benchmark results as PR comment
```

**Acceptance:**
- [ ] Benchmark suite runs in CI
- [ ] CI fails if budgets exceeded
- [ ] Results posted as PR comment

---

#### 3. Security Checklist
**Effort:** 2 days  
**Priority:** Critical

**Tasks:**
- [ ] Workspace trust gating verified
- [ ] Executable path whitelist/validation tests
- [ ] No dynamic eval / Function constructors
- [ ] Webview CSP: script-src nonce-only, no remote origins
- [ ] Dependency license & supply audit
- [ ] Input sanitization (path traversal, command injection)
- [ ] Error messages don't leak sensitive data

**Files to Create:**
- `SECURITY.md` - Security policy
- `extension/test/security.test.ts` - Security regression tests

**Security Tests:**
```typescript
test('rejects relative path traversal in executable override', () => {
  const malicious = 'dsc.install:\n  packages:\n    - name: evil\n      executable: ../../../etc/passwd\n';
  const doc = parseSimple(malicious);
  
  // Should have DSL007 diagnostic
  assert.ok(doc.diagnostics?.some(d => d.code === 'DSL007'));
});

test('PowerShell bridge sanitizes arguments', async () => {
  const malicious = { command: 'generate', dslPath: 'test.yaml; rm -rf /' };
  
  await assert.rejects(
    () => invokePwsh(malicious),
    /Invalid path/
  );
});

test('workspace trust blocks execution commands', () => {
  // Mock untrusted workspace
  (vscode.workspace as any).isTrusted = false;
  
  // generateConfig should show warning, not execute
  // ... test implementation
});
```

**Acceptance:**
- [ ] All 7 security checks pass
- [ ] No high/critical vulnerabilities in npm audit
- [ ] CodeQL scan clean (no new alerts)

---

#### 4. Documentation Polish
**Effort:** 2 days  
**Priority:** High

**Deliverables:**

**4.1 README Improvements**
- [ ] Add badges (build status, version, license)
- [ ] Quickstart guide (<90 seconds to first result)
- [ ] Feature matrix with screenshots
- [ ] Troubleshooting section (common errors)
- [ ] Link to video walkthrough

**4.2 User Guide (extension/docs/USER-GUIDE.md)**
- [ ] Installation instructions
- [ ] DSL syntax tutorial (Simple + SudoLang)
- [ ] Graph visualization guide
- [ ] PowerShell bridge configuration
- [ ] Keyboard shortcuts
- [ ] FAQ

**4.3 Video Walkthrough**
- [ ] 3-5 minute demo video
- [ ] Cover: install, write DSL, see diagnostics, view graph, generate YAML
- [ ] Upload to YouTube + link in README

**Acceptance:**
- [ ] New user can install + use in <90 seconds
- [ ] Documentation covers all MVP features
- [ ] Video published and linked

---

#### 5. VSIX Packaging & Reproducible Builds
**Effort:** 1 day  
**Priority:** Critical

**Tasks:**
```bash
npm install -g @vscode/vsce
cd extension
vsce package --out ../dist/statesmith-dsc-0.1.0.vsix
```

**Reproducibility:**
- [ ] Lock file committed (package-lock.json)
- [ ] Node version documented (.nvmrc)
- [ ] Build script in package.json
- [ ] CI produces artifact with hash

**Files to Create:**
- `.nvmrc` - Node version (20.x)
- `extension/scripts/package.sh` - VSIX build script

**Package Script:**
```bash
#!/bin/bash
set -euo pipefail

VERSION=$(node -p "require('./package.json').version")
OUTPUT="../dist/statesmith-dsc-${VERSION}.vsix"

echo "Building VSIX for version ${VERSION}..."
npm ci
npm run build
npm test

vsce package --out "${OUTPUT}"

echo "Package created: ${OUTPUT}"
shasum -a 256 "${OUTPUT}"
```

**Acceptance:**
- [ ] VSIX builds reproducibly (same hash)
- [ ] Extension installs from VSIX
- [ ] All commands functional after install

---

#### 6. Marketplace Assets
**Effort:** 1 day  
**Priority:** High

**Required Assets:**

**6.1 Extension Icon**
- [ ] 128x128 PNG logo
- [ ] Clean, professional design
- [ ] Theme-compatible (light/dark)

**6.2 Screenshots**
- [ ] Diagnostics in Problems panel
- [ ] Completions dropdown
- [ ] Resource graph visualization
- [ ] Code actions lightbulb menu

**6.3 Marketplace README**
- [ ] Compelling description (what/why/how)
- [ ] Feature bullets with icons
- [ ] Screenshots with captions
- [ ] Installation instructions
- [ ] Minimum requirements

**6.4 Metadata (package.json)**
```json
{
  "displayName": "StateSmith DSC",
  "description": "Authoring, visualization, and validation for Desired State Configuration (DSC) with dual DSL support.",
  "version": "0.1.0",
  "publisher": "statesmith",
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "https://github.com/plures/pedantic"
  },
  "categories": ["Programming Languages", "Linters", "Formatters", "Visualization"],
  "keywords": ["dsc", "yaml", "configuration", "infrastructure", "devops"],
  "galleryBanner": {
    "color": "#1e1e1e",
    "theme": "dark"
  },
  "icon": "icon.png"
}
```

**Acceptance:**
- [ ] Icon looks professional in marketplace
- [ ] Screenshots demonstrate value
- [ ] README compelling + clear
- [ ] Metadata complete

---

#### 7. Beta Testing Period
**Effort:** 2 weeks (async)  
**Priority:** Critical

**Beta Process:**

**Week 1: Internal Testing**
- [ ] Install on 3 different machines (Windows/Mac/Linux)
- [ ] Create 10+ real DSL configs
- [ ] Exercise all commands and features
- [ ] Log any bugs/issues

**Week 2: External Beta**
- [ ] Recruit 10+ beta testers (GitHub/social media)
- [ ] Provide VSIX + testing guide
- [ ] Collect feedback via GitHub Issues
- [ ] Fix P0/P1 bugs

**Beta Test Guide:**
```markdown
# StateSmith Beta Testing Guide

## Setup
1. Download VSIX: [link]
2. Install: `code --install-extension statesmith-dsc-0.1.0.vsix`
3. Reload VS Code

## Test Scenarios
1. **Create a Simple DSL config**
   - Open new file `test.simple.dsc.yaml`
   - Type `dsc.install:` (should autocomplete)
   - Add packages list
   - Verify diagnostics appear

2. **View Resource Graph**
   - Run command: "StateSmith: Open Resource Graph"
   - Verify graph renders
   - Click node → should reveal source

3. **Generate DSC YAML**
   - Run command: "StateSmith: Generate DSC from DSL"
   - Verify output appears

## Feedback
Please report:
- ✅ What worked well
- 🐛 Bugs (with steps to reproduce)
- 💡 Feature suggestions
- ⚡ Performance issues
```

**Acceptance:**
- [ ] 10+ testers install and use
- [ ] Zero P0 bugs (crashes, data loss)
- [ ] All P1 bugs fixed
- [ ] Positive feedback on core value

---

## 1.0 Acceptance Criteria (from SCOPE-1.0.md)

### Functional ✅
- [x] Parse both dialects without crashes
- [x] Round-trip ≥95% constructs (Simple DSL)
- [x] Three code actions functional
- [x] Formatter idempotent
- [x] Graph webview < 1500ms load

### Quality & Reliability ✅
- [x] Test coverage ≥80% statements
- [x] Parser/converter ≥90% branch coverage
- [x] No unhandled promise rejections (E2E smoke)
- [x] All diagnostic codes in spec (CI validates)

### Performance ✅
- [x] Simple parse 200 lines P95 < 40ms
- [x] SudoLang parse 200 lines P95 < 55ms
- [x] Completion P95 < 150ms (warm cache)

### Security & Safety ✅
- [x] Workspace trust gating verified
- [x] Executable path validation tests pass
- [x] No dynamic eval / Function constructors
- [x] Webview CSP: nonce-only, no remote
- [x] Dependency audit clean (no high/critical)

### Packaging & Distribution ✅
- [x] VSIX reproducible (hash stable)
- [x] CHANGELOG entry for 1.0
- [x] Version bump (spec + package.json + tags)

### Documentation ✅
- [x] README: quickstart <90s
- [x] CONTRIBUTING: build, test, guidelines
- [x] Spec v1.0 matches implementation
- [x] User guide complete
- [x] Video walkthrough published

---

## Release Process

### Pre-Release (RC Week)

**Monday:**
- [ ] Code freeze (main branch protected)
- [ ] Create release branch `release/1.0`
- [ ] Update version in package.json
- [ ] Update CHANGELOG with all changes since MVP

**Tuesday-Wednesday:**
- [ ] Full regression testing
- [ ] Performance benchmarks
- [ ] Security audit
- [ ] Documentation review

**Thursday:**
- [ ] Build release candidate VSIX
- [ ] Tag: `v1.0.0-rc.1`
- [ ] Deploy to internal testers

**Friday:**
- [ ] Collect RC feedback
- [ ] Fix critical bugs only
- [ ] Prepare release notes

### Release Day (Week 8)

**Steps:**
1. Final version bump to `1.0.0` (remove `-rc`)
2. Update CHANGELOG (final release date)
3. Build production VSIX
4. Create Git tag: `v1.0.0`
5. Publish to VS Code Marketplace:
   ```bash
   vsce publish
   ```
6. Create GitHub Release with notes
7. Announce on:
   - GitHub Discussions
   - Twitter/LinkedIn
   - Reddit (r/vscode, r/devops)
   - Internal channels

**Release Notes Template:**
```markdown
# StateSmith DSC 1.0.0

We're excited to announce the first stable release of StateSmith DSC!

## What is StateSmith?

StateSmith is a VS Code extension for authoring Desired State Configuration
(DSC) files using two intuitive DSL syntaxes: Simple YAML and SudoLang.

## Key Features

✨ **Dual DSL Support** - Choose between YAML-based or concise SudoLang syntax
🔍 **Real-time Diagnostics** - Catch errors as you type
🎨 **Resource Graph** - Visualize package dependencies with ECharts
🔧 **Code Actions** - Quick fixes for common issues
📝 **Formatter** - Canonical formatting with one command
🔗 **PowerShell Bridge** - Generate native DSC YAML output

## Installation

Install from [VS Code Marketplace](link) or via:
```
code --install-extension statesmith.statesmith-dsc
```

## Documentation

- [User Guide](link)
- [DSL Specification](link)
- [Video Walkthrough](link)

## What's Next?

Version 1.1+ will add:
- AI-assisted configuration generation (MCP integration)
- Drift dashboard
- Advanced visualizations

See [ROADMAP.md](link) for details.

## Thank You

Thanks to our 20+ beta testers and contributors!

## Support

- [Report Issues](link)
- [Discussions](link)
- [Contributing Guide](link)
```

---

## Post-Release (Week 9)

### Monitoring (First 7 Days)
- [ ] Watch GitHub Issues for bugs
- [ ] Monitor marketplace ratings/reviews
- [ ] Track download metrics
- [ ] Collect user feedback

### Quick Patches (If Needed)
- [ ] Fix P0 bugs within 24 hours → 1.0.1
- [ ] Fix P1 bugs within 1 week → 1.0.2

### Retrospective
- [ ] Team review: what went well / what to improve
- [ ] Update processes based on learnings
- [ ] Plan 1.1 features based on feedback

---

## Success Metrics (1.0)

### Week 1
- [ ] 100+ downloads
- [ ] ≥4.0 star rating
- [ ] <5 P0/P1 bugs reported
- [ ] Positive social media feedback

### Month 1
- [ ] 500+ downloads
- [ ] 10+ GitHub stars
- [ ] Community contributions (1+ PR)
- [ ] Case study: 1+ company using in production

---

## Contingency Plans

### If Critical Bug Found in RC
- Delay release by 1 week
- Fix + additional regression testing
- New RC with extended testing period

### If Beta Feedback is Negative
- Analyze root causes
- Prioritize fixes
- Consider MVP feature cuts
- Extended beta period

### If Performance Budgets Not Met
- Profile and optimize hot paths
- Consider lazy loading for graph
- Add progress indicators
- Document minimum system requirements

---

## Next Phase: Post-1.0 Roadmap

**See:** [ROADMAP.md](ROADMAP.md) sections 4-7

**Priorities After 1.0:**
1. Stabilization period (1-2 months)
2. Community feedback integration
3. MCP server implementation (Phase 4)
4. Advanced visualizations (Phase 5)

**Timeline:** 6-7 months to full roadmap completion
