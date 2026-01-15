# Pedantic Project Roadmap - Executive Summary
**Date:** January 15, 2026  
**Vision:** The Ansible Galaxy for DSC - A community hub for discovering, sharing, and managing DSC resources

---

## Quick Links

- **[ROADMAP-ANALYSIS.md](ROADMAP-ANALYSIS.md)** - Comprehensive implementation status analysis
- **[MVP-PLAN.md](MVP-PLAN.md)** - Detailed MVP execution plan  
- **[RELEASE-1.0-PLAN.md](RELEASE-1.0-PLAN.md)** - 1.0 release plan
- **[FULL-ROADMAP-PLAN.md](FULL-ROADMAP-PLAN.md)** - Complete long-term vision

---

## Project Vision

Pedantic aims to become **the central hub for the DSC community**, similar to how Ansible Galaxy serves the Ansible ecosystem. We're building:

1. **Resource Discovery Platform** - Central repository for DSC configurations and resources
2. **Modern Tooling** - VS Code extension with AI-assisted authoring
3. **Community Hub** - Sharing, rating, and collaboration on DSC resources
4. **Cross-Platform Support** - Works on Windows, macOS, and Linux
5. **Ecosystem Integration** - Seamless integration with Plures projects

---

## Current State (January 2026)

### ✅ What's Working
- **PowerShell Module:** Production-ready DSC v3 helper with remote execution, caching, resource management
- **VS Code Extension:** Scaffold complete with 4 commands, configuration, TypeScript build pipeline
- **Dual DSL Parsers:** Simple YAML and SudoLang parsers implemented with diagnostics (DSL001-DSL010)
- **Unified AST:** Clean type definitions with Document/Block/Package hierarchy
- **Resource Graph:** Basic webview with radial layout, auto-refresh on edits
- **Tests:** 5 SudoLang parser tests passing (bug fixed in this PR)

### ❌ Critical Gaps for DSC Hub Vision
- **No Resource Sharing Platform:** Community hub not yet built
- **No LSP Integration:** VS Code extension lacks real-time diagnostics
- **No PowerShell Bridge:** Can't execute DSC operations from extension
- **Limited Testing:** Only basic test coverage
- **No Plures Integration:** Not yet integrated with PluresDB, RuneBook, or Praxis
- **No AI/MCP Features:** Advanced authoring assistance not implemented

---

## Multi-Phase Strategy

### Phase 1: MVP - Core Tooling (Q1 2026) → Version 0.1.0
**Goal:** Ship functional VS Code extension that improves DSC authoring

**Priority Tasks:**
1. **LSP Integration** (2-3 weeks)
   - Wire language server/client
   - Publish diagnostics to Problems panel
   - Implement completions (keys, methods, package IDs)

2. **Testing** (1-2 days)
   - Golden test corpus (10+ fixtures)
   - Parser unit tests (≥80% coverage)

3. **PowerShell Bridge** (2-3 days)
   - JSON contract schema
   - Process wrapper with timeout/retry
   - Connect generateConfig command

4. **UI Polish** (2-3 days)
   - ECharts integration
   - Node click → reveal source
   - Formatter + code actions

**MVP Success:** 10+ beta testers, zero P0 bugs, positive feedback on tooling

---

### Phase 2: 1.0 Release - Production Ready (Q2 2026) → Version 1.0.0
**Goal:** Professional, stable extension ready for marketplace

**Additions Beyond MVP:**
- Hovers (package info, method docs)
- Performance budgets enforced in CI
- Security checklist complete
- Documentation polish
- VSIX packaging + reproducible builds
- Marketplace assets (logo, screenshots)
- Beta testing (2 weeks, 10+ testers)

**1.0 Success:** 100+ downloads week 1, ≥4.0 stars, stable operation

---

### Phase 3: Community Hub (Q3 2026) → Version 1.5.0
**Goal:** Launch the DSC community platform

**Core Features:**
- **Resource Repository** - Central catalog of DSC configurations
- **PluresDB Integration** - Decentralized storage using PluresDB
- **Discovery & Search** - Find resources by category, platform, rating
- **Community Features** - Ratings, comments, contributions
- **Sharing Tools** - Publish and download configurations

**Integration Points:**
- **PluresDB** - Decentralized graph database for resource metadata
- **RuneBook** - Visual DSC workflow builder
- **Praxis** - Framework integration for application deployment

**3.0 Success:** 50+ shared resources, active community participation

---

### Phase 4: Advanced Features (Q4 2026) → Version 2.0.0
**Goal:** Feature-complete ecosystem with AI capabilities

**Features:**
- AI-assisted configuration generation (MCP integration)
- Drift detection and remediation
- Advanced visualizations
- Provider abstraction and optimization
- Enterprise-grade resource management
- Telemetry and analytics

**2.0 Success:** 5000+ users, enterprise adoption, community contributions

---

## Strategic Decision: Phased Approach to Community Hub

**Original Vision:** Build everything at once  
**Updated Strategy:** Deliver value incrementally, validate with community

**Rationale:**
1. **Validate Core Concept:** Prove DSL tooling value before building full hub
2. **Faster Time to Value:** Get useful tools in developers' hands quickly
3. **Community Feedback:** Let users guide hub feature priorities
4. **Risk Reduction:** Build foundation before complex distributed features

**Impact:** More sustainable development, better alignment with real needs

---

## Leveraging the Plures Ecosystem

Pedantic will integrate deeply with other Plures projects:

### PluresDB Integration
- **Purpose:** Decentralized resource catalog and metadata storage
- **Benefits:** No central server, community-owned data, offline capability
- **Timeline:** Phase 3 (Q3 2026)

### RuneBook Integration  
- **Purpose:** Visual canvas for building DSC workflows
- **Benefits:** Interactive development, component wiring, live execution
- **Timeline:** Phase 3-4 (Q3-Q4 2026)

### Praxis Integration
- **Purpose:** Full-stack framework with DSC deployment
- **Benefits:** Seamless app deployment, infrastructure as code
- **Timeline:** Phase 4 (Q4 2026)

These integrations will create a powerful, interconnected ecosystem where:
- Resources discovered in Pedantic can be visualized in RuneBook
- Workflows created in RuneBook can be stored in PluresDB
- Applications built with Praxis can be deployed via Pedantic configurations

---

## Key Recommendations

### 1. Focus on Production Module Value
**Action:** Highlight and document what works today (PowerShell module)  
**Why:** Provide immediate value while building future capabilities

### 2. Complete MVP Critical Path
**Action:** Finish LSP integration for VS Code extension  
**Why:** Modern tooling attracts developers to the ecosystem

### 3. Build Community Platform Foundation
**Action:** Design resource sharing architecture with PluresDB  
**Why:** Core differentiator - the "Galaxy" aspect of the vision

### 4. Leverage Plures Ecosystem
**Action:** Establish integration points with PluresDB, RuneBook, and Praxis  
**Why:** Unified ecosystem provides more value than standalone tools

### 5. Ship Early, Iterate Often
**Action:** Release MVP, gather feedback, refine vision  
**Why:** Community input guides the best path forward

---

## Timeline Summary

```
Now              Q1 2026         Q2 2026         Q3 2026         Q4 2026
 |                  |               |               |               |
 |---- MVP ---------|---- 1.0 ------|-- Hub 1.5 ----|---- 2.0 ------|
 |                  |               |               |               |
 Core Tooling    Polish +      Community      Advanced AI +    Full Ecosystem
                Marketplace      Platform       Integrations
```

**Milestones:**
- ✅ **Now:** PowerShell module production-ready, VS Code extension scaffold complete
- 🔲 **Q1 2026:** MVP with LSP, testing, bridge, and UI polish
- 🔲 **Q2 2026:** 1.0 marketplace launch with security and performance
- 🔲 **Q3 2026:** Community hub with PluresDB integration and resource sharing
- 🔲 **Q4 2026:** 2.0 with AI features and full ecosystem integration

---

## Success Metrics

### MVP (Q1 2026)
- [ ] 10+ beta testers using VS Code extension
- [ ] Zero P0 bugs (crashes, data loss)
- [ ] Real-time diagnostics working reliably
- [ ] Positive qualitative feedback on tooling

### 1.0 (Q2 2026)
- [ ] Published to VS Code Marketplace
- [ ] 100+ downloads in first week
- [ ] ≥4.0 star rating
- [ ] Test coverage ≥80%
- [ ] Performance budgets met

### Community Hub 1.5 (Q3 2026)
- [ ] 50+ shared DSC resources in catalog
- [ ] PluresDB integration functional
- [ ] Active community participation (contributions, ratings)
- [ ] Integration with at least one Plures ecosystem project

### 2.0 (Q4 2026)
- [ ] 1000+ active users
- [ ] 100+ GitHub stars
- [ ] 5+ enterprise adoptions
- [ ] Community contributions (10+ PRs)
- [ ] Full ecosystem integration (PluresDB, RuneBook, Praxis)

---

## Next Actions (Priority Order)

### Immediate (This Week)
1. [x] Clarify project vision as DSC ecosystem hub
2. [x] Update README and roadmap documentation
3. [ ] Set up LSP server/client packages for VS Code extension
4. [ ] Begin community hub architecture design

### Q1 2026 (MVP Phase)
5. [ ] Implement LSP integration with diagnostics
6. [ ] Add completions provider
7. [ ] Create comprehensive test suite
8. [ ] Build PowerShell bridge
9. [ ] Integrate ECharts visualization
10. [ ] Implement formatter and code actions
11. [ ] Beta testing program
12. [ ] MVP release

### Q2 2026 (1.0 Release)
13. [ ] Security audit and hardening
14. [ ] Performance optimization
15. [ ] Documentation polish
16. [ ] Marketplace preparation
17. [ ] Public 1.0 release

### Q3 2026 (Community Hub)
18. [ ] Design resource catalog schema
19. [ ] Integrate PluresDB for decentralized storage
20. [ ] Build discovery and search interface
21. [ ] Implement sharing and rating features
22. [ ] Launch community platform

### Q4 2026 (Advanced Features)
23. [ ] MCP integration for AI-assisted authoring
24. [ ] RuneBook integration for visual workflows
25. [ ] Praxis integration for deployment
26. [ ] Advanced analytics and telemetry
27. [ ] 2.0 release

---

## Risk Mitigation

### Critical Risks

**1. Community Adoption** 🔴
- **Risk:** DSC community may not embrace a new platform
- **Mitigation:** Start with excellent tooling, prove value before asking for contributions
- **Contingency:** Focus on tooling value even without large-scale sharing

**2. PluresDB Integration Complexity** 🟡
- **Risk:** Decentralized architecture may be technically challenging
- **Mitigation:** Phase 3 allows time for PluresDB to mature, prototype integration early
- **Contingency:** Start with centralized catalog, migrate to decentralized later

**3. Ecosystem Fragmentation** 🟡
- **Risk:** Multiple competing DSC tools/platforms emerge
- **Mitigation:** Focus on unique value (AI, visualization, Plures integration)
- **Contingency:** Emphasize interoperability and open standards

**4. LSP Integration Complexity** 🔴
- **Mitigation:** Start with diagnostics only (simplest), add features incrementally
- **Contingency:** Use inline decorations if LSP proves too complex

**5. PowerShell Bridge Reliability** 🟡
- **Mitigation:** Strict JSON schema, timeout/retry logic, comprehensive error handling
- **Contingency:** Document manual workflow if bridge unstable

---

## Conclusion

**Pedantic is positioned to become the central hub for the DSC community**, providing the same value that Ansible Galaxy provides to Ansible users. The strategy prioritizes:

1. **Immediate Value** - Production-ready PowerShell module available now
2. **Modern Tooling** - VS Code extension with LSP for better authoring experience
3. **Community Platform** - Resource sharing and discovery via PluresDB
4. **Ecosystem Integration** - Seamless workflow with RuneBook and Praxis
5. **Advanced Features** - AI-assisted configuration and intelligent automation

By delivering incrementally and validating with the community at each phase, we'll build a sustainable platform that truly serves DSC users' needs.

**Recommended Next Step:** Complete MVP tooling (Q1 2026), then launch community hub (Q3 2026). Follow detailed plans in [MVP-PLAN.md](MVP-PLAN.md) and [RELEASE-1.0-PLAN.md](RELEASE-1.0-PLAN.md).

---

## Files in This Analysis

1. **README.md** - Updated project description and vision
2. **NEXT-STEPS.md** - This executive summary (updated)
3. **ROADMAP-ANALYSIS.md** - Comprehensive implementation status
4. **MVP-PLAN.md** - Detailed MVP execution plan
5. **RELEASE-1.0-PLAN.md** - 1.0 release planning
6. **FULL-ROADMAP-PLAN.md** - Complete long-term vision

All documents provide actionable guidance for building Pedantic from its current state (production PowerShell module + VS Code scaffold) to a full-featured DSC ecosystem hub integrated with the Plures platform.
