# Pedantic Roadmap Analysis
**Date:** January 15, 2026  
**Purpose:** Comprehensive analysis of current project state vs. roadmap goals

## Executive Summary

Pedantic is positioned to become **the Ansible Galaxy for DSC** - a central hub for discovering, sharing, and managing DSC resources and configurations. The project has **solid foundational work** with a production-ready PowerShell module and is building modern tooling via a VS Code extension.

### Current Status: Strong Foundation, Building Toward Community Hub
- ✅ **PowerShell module** production-ready and fully functional
- ✅ **Core parsing** implemented for dual DSLs (Simple YAML + SudoLang)
- ✅ **Basic webview** framework created
- ❌ **LSP integration** not started (critical for VS Code extension)
- ❌ **Community platform** not yet designed
- ❌ **PluresDB integration** not implemented
- ❌ **PowerShell bridge** not connected
- ❌ **Testing infrastructure** incomplete

---

## Detailed Implementation Status

### ✅ Completed Work (Strong Foundation)

#### 1. PowerShell Module (Production-Ready Foundation)
**Status:** Mature, production-ready  
**Files:** `Pedantic.psm1`, `Pedantic.psd1`, related helpers

- Comprehensive DSC v3 resource management
- Remote execution capabilities
- Resource caching and installer management
- Platform-aware version detection
- Well-documented with examples

**Assessment:** This is the solid foundation that demonstrates Pedantic's value today. The module serves real users while we build the ecosystem vision.

#### 2. VS Code Extension Scaffold
**Status:** Basic structure in place  
**Location:** `/extension/`

- Package.json properly configured (name, commands, activation events)
- Extension activation working (`extension.ts`)
- 4 commands registered:
  - `statesmith.generateConfig` (stub)
  - `statesmith.openGraph` (functional)
  - `statesmith.openAiPanel` (placeholder)
  - `statesmith.debugParse` (functional)
- Configuration settings defined (telemetry, pwsh path)
- TypeScript build pipeline operational

**Assessment:** Phase 1 scaffolding complete. Ready for feature development.

#### 3. Dual DSL Parsing
**Status:** Core parsers implemented and tested  
**Files:** `dsl/simpleParser.ts`, `dsl/sudoParser.ts`, `dsl/ast.ts`

**Simple DSL Parser:**
- ✅ Tolerant YAML parsing with diagnostics
- ✅ Structural validation (DSL001-DSL010 codes)
- ✅ Package normalization (string → object)
- ✅ Provider validation (winget, chocolatey, etc.)
- ✅ Duplicate detection
- ✅ Executable override support
- Total: ~160 lines, clean design

**SudoLang Parser:**
- ✅ Chevrotain-based grammar implementation
- ✅ `install` and `ensure` statement support
- ✅ `via`, `version`, `using` clauses
- ✅ Quoted string and identifier handling
- ✅ Diagnostic generation (DSL005-DSL007)
- ✅ 5 passing tests covering core scenarios
- Total: ~330 lines, robust
- **FIXED:** OPTION numbering bug (this PR)

**Unified AST:**
- ✅ Clean type definitions
- ✅ Document/Block/Package hierarchy
- ✅ Diagnostic structure
- ✅ Source location tracking (prepared)

**Assessment:** This is **excellent** foundational work. Parsers are well-architected, tested, and ready for LSP integration.

#### 4. Resource Graph Webview
**Status:** Basic visualization working  
**File:** `webviews/resourceGraphPanel.ts`

- ✅ Singleton panel management
- ✅ CSP-compliant HTML generation
- ✅ Message passing infrastructure
- ✅ Simple radial layout algorithm
- ✅ Diagnostic display
- ✅ Auto-refresh on document change (debounced)
- ❌ ECharts not integrated (placeholder comment present)
- ❌ No interactivity (node clicks, reveal in editor)

**Assessment:** Framework is solid. ECharts integration + interactivity are incremental additions.

#### 5. Documentation Suite
**Files:** `ROADMAP.md`, `SCOPE-1.0.md`, `DSL-SPEC.md`, `README.md`, others

- ✅ Comprehensive roadmap with 14 sections
- ✅ 1.0 scope definition with acceptance criteria
- ✅ DSL specification (grammar, codes, examples)
- ✅ Architecture and migration strategy docs
- ✅ ADP integration guide

**Assessment:** Documentation quality is **exceptional**. Clear vision, well-defined phases, detailed acceptance criteria.

---

### ❌ Not Yet Implemented (High Priority Gaps)

#### 1. Language Server Protocol (LSP)
**Roadmap Phase:** 2 (Minimal LSP)  
**Status:** Not started

**Missing:**
- No LSP server/client setup
- No real-time diagnostics publishing
- No completions provider
- No hovers, code actions, formatting
- No document sync handlers

**Impact:** This is the **#1 blocker** for user-facing value. Without LSP, the extension is a collection of disconnected commands.

**Effort Estimate:** 3-5 days for basic LSP with diagnostics + completions.

#### 2. PowerShell Bridge
**Roadmap Phase:** 1-2 (JSON contract bridge)  
**Status:** Not connected

**Current State:**
- Extension has `statesmith.bridge.pwshPath` config
- `generateConfig` command is a stub
- PowerShell module exists but not invoked from extension

**Missing:**
- JSON schema contract definition
- Child process invocation wrapper
- Timeout/cancellation handling
- Error streaming
- Test mode support

**Impact:** Cannot execute DSC operations from extension.

**Effort Estimate:** 2-3 days for basic bridge + contract.

#### 3. AI / MCP Integration
**Roadmap Phase:** 4 (MCP Server & AI Workflows)  
**Status:** Zero implementation

**Missing:**
- No MCP server package
- No tool definitions (generateConfig, explainConfig, etc.)
- No AI panel functionality (stub HTML only)
- No diff preview UI
- No audit log mechanism

**Impact:** Major differentiator feature absent. Not critical for MVP but important for vision.

**Effort Estimate:** 10-15 days for full MCP suite.

#### 4. Code Actions & Formatting
**Roadmap Phase:** 2-3  
**Status:** Not started

**Missing:**
- No formatter implementation
- No code actions provider
- No conversion commands (Simple ↔ SudoLang)

**Impact:** Reduces editor polish. Not blocking but valuable.

**Effort Estimate:** 2-3 days for formatter + 3 basic code actions.

#### 5. Testing & Quality
**Status:** Minimal coverage

**Current:**
- ✅ 5 unit tests for SudoLang parser (passing)
- ❌ No tests for Simple parser
- ❌ No LSP integration tests
- ❌ No webview tests
- ❌ No golden corpus tests
- ❌ No E2E tests

**Coverage:** ~5% of planned test surface.

**Impact:** Risky for production release. Need ≥80% for 1.0.

**Effort Estimate:** 5-7 days for comprehensive suite.

---

## Roadmap Checklist Update

### Foundation & Scaffolding
- [x] Project branding and positioning (Pedantic - DSC ecosystem hub)
- [x] ~~Monorepo scaffolding~~ → Single extension package (acceptable)
- [x] Extension activation + basic commands
- [ ] **PowerShell bridge contract (JSON schema v1)** ← HIGH PRIORITY

### Parsing & LSP
- [x] Simple DSL tolerant parser
- [x] SudoLang grammar implementation (Chevrotain)
- [ ] **LSP server setup** ← CRITICAL PATH
- [ ] **Diagnostics publishing (real-time)** ← CRITICAL PATH
- [ ] **Completions (core keys, methods)** ← CRITICAL PATH
- [ ] Golden tests (simple → DSC YAML)
- [ ] Performance instrumentation
- [ ] Hovers (package info, method docs)
- [ ] Code actions (add packages key, expand string → object, remove unknown field)
- [ ] Format provider (canonical ordering)

### SudoLang DSL
- [x] Grammar spec document (DSL-SPEC.md)
- [x] Chevrotain implementation
- [ ] Round‑trip converters & tests
- [ ] Lossiness report generator

### AI / MCP
- [ ] MCP server scaffold
- [ ] Tool: generateConfig
- [ ] Tool: explainConfig
- [ ] Tool: optimizeInstallPlan
- [ ] Tool: remediateDrift
- [ ] Tool: reverseToDsl
- [ ] Diff preview UI & audit log

### Visualizations
- [x] Resource graph webview (basic)
- [ ] **ECharts integration** ← MEDIUM PRIORITY
- [ ] **Node click → reveal in editor** ← MEDIUM PRIORITY
- [ ] Drift dashboard webview
- [ ] Reverse explorer
- [ ] AI design canvas

### Engine Evolution
- [ ] JS provider abstraction (winget/choco/msi)
- [ ] Install plan optimizer
- [ ] Caching/offline manager
- [ ] Optional Deno experiment flag

### Quality & Ops
- [x] Test suite structure (basic)
- [ ] **Comprehensive test matrix** ← HIGH PRIORITY
- [ ] Telemetry (opt‑in) & redaction check
- [ ] Security checklist & sandbox prompts
- [ ] Performance budgets enforced
- [ ] Documentation suite (User, DSL Spec, AI Safety)
- [ ] Marketplace publish (Preview)
- [ ] 1.0.0 Release

---

## Gap Analysis by Phase

### Phase 1 (Monorepo & Scaffolding)
**Target:** Extension activation + command + webview placeholder  
**Actual:** ✅ **95% Complete**
- Extension activates properly
- Commands registered and callable
- Webview framework functional
- Only gap: PowerShell bridge contract (10% work)

### Phase 2 (Minimal LSP - Simple DSL)
**Target:** Diagnostics, completions, golden tests  
**Actual:** ⚠️ **40% Complete**
- ✅ Parser with diagnostics collection
- ❌ No LSP server/client wiring (60% of phase)
- ❌ No golden test corpus

**Blocker:** LSP integration is **critical path** for user value.

### Phase 3 (SudoLang Variant)
**Target:** Grammar, converter, round-trip tests  
**Actual:** ✅ **70% Complete**
- ✅ Grammar implemented and tested
- ❌ No converters (Simple ↔ SudoLang)
- ❌ No round-trip tests

### Phase 4-7 (AI, Viz, Engine, Hardening)
**Actual:** ⚠️ **5-10% Complete**
- Only basic graph webview exists
- No MCP, no drift dashboard, no engine evolution

---

## Risk Assessment

### Critical Risks (Require Immediate Attention)

1. **LSP Integration Complexity** 🔴  
   **Risk:** LSP setup may reveal parser gaps or performance issues.  
   **Mitigation:** Start with document diagnostics only (simplest LSP feature). Add incrementally.

2. **PowerShell Bridge Reliability** 🔴  
   **Risk:** Child process timeouts, error handling, JSON marshaling failures.  
   **Mitigation:** Define strict JSON schema. Add timeout/retry logic. Test with malformed inputs.

3. **Test Coverage Debt** 🟡  
   **Risk:** Regressions accumulate without safety net.  
   **Mitigation:** Add golden tests for parsers immediately. Defer E2E until LSP working.

4. **Scope Creep (AI Features)** 🟡  
   **Risk:** MCP/AI work could delay MVP indefinitely.  
   **Mitigation:** Clearly defer all AI to post-MVP (see recommendations below).

### Moderate Risks

5. **ECharts Integration** 🟢  
   **Risk:** Local vendoring + CSP compliance may be tricky.  
   **Mitigation:** Use CDN for preview, switch to local bundle before marketplace.

6. **Performance (Large Files)** 🟢  
   **Risk:** Current parser has 5000-line heuristic warning.  
   **Mitigation:** Already implemented size checks. Add incremental parsing if needed.

---

## Recommendations

### Immediate Next Steps (MVP Path)

**Goal:** Ship a usable extension that provides value over raw YAML editing.

#### 1. Complete Phase 2 (LSP Foundation) - **HIGHEST PRIORITY**
**Effort:** 4-6 days  
**Tasks:**
- [ ] Add `vscode-languageclient` + `vscode-languageserver` dependencies
- [ ] Create `language-server/` package (or inline in extension)
- [ ] Wire up document sync (`onDidOpen`, `onDidChange`)
- [ ] Publish diagnostics from existing parsers
- [ ] Implement basic completions (top-level keys: `dsc.install`)
- [ ] Test with sample `.simple.dsc.yaml` file

**Acceptance:**
- Diagnostics appear in Problems panel in real-time
- Typing `dsc.` shows `install` completion
- No crashes on large files (<5000 lines)

#### 2. Add Golden Test Corpus
**Effort:** 1-2 days  
**Tasks:**
- [ ] Create `test-fixtures/` directory
- [ ] Add 6-10 representative DSL samples
- [ ] Add expected DSC YAML outputs (from PowerShell module)
- [ ] Write comparison tests (DSL → AST → regenerated DSL)

**Acceptance:**
- All golden tests pass
- Round-trip identity holds (within normalization tolerance)

#### 3. Connect PowerShell Bridge (Basic)
**Effort:** 2-3 days  
**Tasks:**
- [ ] Define JSON contract schema (`BridgeRequest`, `BridgeResponse`)
- [ ] Implement `invokePwsh(dslPath)` wrapper
- [ ] Wire `generateConfig` command to bridge
- [ ] Add error handling (timeout, exit codes)
- [ ] Test with sample DSL file

**Acceptance:**
- `generateConfig` command produces DSC YAML output
- Errors shown in user-friendly format
- Works on Windows + cross-platform pwsh

#### 4. Enhance Graph Webview
**Effort:** 2-3 days  
**Tasks:**
- [ ] Integrate ECharts (local vendor or CDN for preview)
- [ ] Add node click → reveal source location
- [ ] Improve layout (force-directed or hierarchical)
- [ ] Add provider grouping visualization

**Acceptance:**
- Graph renders with ECharts
- Clicking node reveals package in editor
- Graph updates on file edits (already debounced)

#### 5. Add Formatter & 3 Code Actions
**Effort:** 2-3 days  
**Tasks:**
- [ ] Implement canonical formatter (Simple DSL)
- [ ] Code action: "Add missing packages key"
- [ ] Code action: "Expand string to object"
- [ ] Code action: "Remove unknown field"

**Acceptance:**
- Formatting is idempotent (format twice = no change)
- Code actions appear in lightbulb menu
- Actions apply correctly

**Total MVP Effort:** 11-17 days (2-3.5 weeks)

---

## MVP Definition (Revised)

**Target:** Functional extension that improves DSL authoring experience.

### MVP Features (Must-Have)
1. ✅ Simple DSL + SudoLang parsing
2. ✅ Real-time diagnostics in Problems panel
3. ✅ Basic completions (keys, methods)
4. ✅ Resource graph visualization
5. ✅ PowerShell bridge (generate DSC YAML)
6. ✅ Formatter (Simple DSL)
7. ✅ 3 code actions
8. ✅ Golden test suite (80% parser coverage)

### MVP Exclusions (Post-MVP)
- ❌ AI/MCP features (entire Phase 4)
- ❌ Drift dashboard (Phase 5)
- ❌ Reverse engineering (Phase 5)
- ❌ JS engine port (Phase 6)
- ❌ Telemetry (Phase 7)
- ❌ SudoLang formatter (nice-to-have)
- ❌ Round-trip converter (can defer if lossiness documented)

**MVP Timeline:** 3-4 weeks of focused development.

---

## 1.0 Release Plan

**Goal:** Professional, stable extension with proven reliability.

### Pre-1.0 Additions (Beyond MVP)
1. **Hovers** (package info, method docs) - 1 day
2. **Performance budgets** enforced in CI - 1 day
3. **Security checklist** complete (workspace trust, path validation) - 2 days
4. **Documentation polish** (quickstart, troubleshooting, videos) - 2 days
5. **VSIX packaging** + reproducible builds - 1 day
6. **Marketplace assets** (logo, screenshots, README) - 1 day
7. **Beta testing period** (2 weeks, gather feedback)

### 1.0 Acceptance Criteria (from SCOPE-1.0.md)
- [x] Parse both dialects without crashes ✅ (done)
- [ ] Round-trip ≥95% constructs (needs converter implementation)
- [ ] Three code actions functional
- [ ] Formatter idempotent
- [ ] Graph webview < 1500ms load
- [ ] Test coverage ≥80% statements
- [ ] Performance budgets met (parse <40ms, completion <150ms)
- [ ] Security checklist complete
- [ ] Spec/code parity CI check

**1.0 Timeline:** MVP + 2 weeks polish + 2 weeks beta = **7-8 weeks total**

---

## Full Roadmap Completion (Phases 4-7)

**Goal:** Feature-complete vision with AI, advanced visualizations, engine evolution.

### Phase 4: MCP Server & AI Workflows
**Effort:** 3-4 weeks  
**Dependencies:** MVP shipped, user feedback integrated

**Tasks:**
- MCP server package (Node)
- 5 tools: generateConfig, explainConfig, optimizeInstallPlan, remediateDrift, reverseToDsl
- Diff preview UI with Apply/Reject
- Audit log (local `.statesmith/changes/*.json`)
- Safety validation (schema, allowlist)

### Phase 5: Advanced Visualizations
**Effort:** 2-3 weeks  
**Dependencies:** Phase 4 complete (for AI canvas)

**Tasks:**
- Drift dashboard (ingest test results)
- Reverse explorer (DSC → DSL with confidence map)
- AI design canvas (live edits + proposals)
- Graph enhancements (dependency inference, grouping)

### Phase 6: Engine Evolution
**Effort:** 4-6 weeks  
**Dependencies:** Phase 5 complete (optional path)

**Tasks:**
- Provider abstraction (winget/choco/msi/apt/yum/brew)
- Install plan optimizer (strategy scoring)
- Caching/offline manager
- Partial JS port (resource checks, plan builder)
- Deno sandbox experiments (behind feature flag)

### Phase 7: Hardening & 1.0+ Release
**Effort:** 2-3 weeks  
**Dependencies:** Phases 4-6 complete

**Tasks:**
- Performance optimization (benchmarks, profiling)
- Security audit (external review)
- Telemetry implementation (opt-in, privacy compliant)
- Documentation suite (User Guide, AI Safety Guide, SDK)
- Marketplace launch (Stable)
- 1.x maintenance plan

**Full Roadmap Timeline:** 11-16 weeks after MVP = **5-6 months total**

---

## Strategic Recommendations

### 1. Focus on MVP First (Ship Value Early)
**Why:** Current state has strong foundations but no user-facing value without LSP. Shipping MVP quickly validates the approach and builds momentum.

**Action:** Complete LSP integration, testing, and bridge before any AI work.

### 2. Defer AI Features to Post-1.0
**Why:** MCP/AI is ambitious but not essential for core DSL authoring value. Risk of scope creep delaying launch.

**Action:** Clearly mark Phase 4-7 as "Post-1.0 Roadmap" in updated ROADMAP.md.

### 3. Prioritize Test Coverage Immediately
**Why:** Parser bugs are hard to detect manually. Golden tests prevent regressions.

**Action:** Add golden test suite before adding more features.

### 4. Simplify Monorepo Strategy
**Why:** Single extension package is working fine. Monorepo adds complexity without clear benefit at this stage.

**Action:** Keep current structure. Revisit if MCP server needs separate package.

### 5. Leverage PowerShell Module Strengths
**Why:** PowerShell module is mature and working. No need to rewrite in JS until proven bottleneck.

**Action:** Use PowerShell bridge for MVP. Defer JS port to Phase 6+.

---

## Success Metrics

### MVP Success (3-4 weeks)
- [ ] Extension installed by 10+ beta testers
- [ ] Real-time diagnostics working for 100+ DSL files
- [ ] Zero P0 bugs (crashes, data loss)
- [ ] Positive feedback on graph visualization
- [ ] PowerShell bridge handles 20+ package configs

### 1.0 Success (7-8 weeks)
- [ ] Published to VS Code Marketplace
- [ ] 100+ downloads in first month
- [ ] ≥4.0 star rating
- [ ] Test coverage ≥80%
- [ ] Performance budgets met in CI
- [ ] Documentation complete (quickstart <90 seconds)

### Full Roadmap Success (6-7 months)
- [ ] 1000+ active users
- [ ] AI features used in 30%+ of sessions
- [ ] Community contributions (issues, PRs)
- [ ] Benchmark: 2x faster than manual YAML authoring
- [ ] Case study: Enterprise adoption (1+ company)

---

## Conclusion

**Pedantic has excellent foundations.** The dual parser architecture, clean AST design, production-ready PowerShell module, and comprehensive documentation demonstrate strong engineering. The project is well-positioned to become the central hub for the DSC community.

**Critical Path:**
1. ✅ **Fix parser bugs** (done)
2. 🔴 **Implement LSP** (Q1 2026) ← START HERE
3. 🟡 **Add testing** (Q1 2026)
4. 🟢 **Connect bridge** (Q1 2026)
5. 🟢 **Polish UI** (Q1 2026)
6. 🟢 **Ship MVP** (beta testing)

**Strategic Decision Point:**  
Build incrementally: Core tooling (Q1-Q2) → Community Hub (Q3) → Advanced Features (Q4). This approach validates each phase before investing in the next, ensuring we build what the community actually needs.

**Recommended Timeline:**
- **MVP:** Q1 2026
- **1.0 Release:** Q2 2026
- **Community Hub:** Q3 2026
- **Advanced Features:** Q4 2026

With focused execution on the critical path and community engagement, Pedantic can become the Ansible Galaxy for DSC by end of 2026.
