# GitHub Workflows

This directory contains the CI/CD workflows for the Pedantic module.

## Active Workflows

### Core CI/CD Workflows

- **[build-test.yml](build-test.yml)** - Build and test workflow with matrix testing
- **[security.yml](security.yml)** - Security scanning and vulnerability detection
- **[release.yml](release.yml)** - Automated release management and publishing
- **[workflow-test.yml](workflow-test.yml)** - CI/CD self-testing and validation

### Automation

- **[../dependabot.yml](../dependabot.yml)** - Automated dependency management

### Legacy/Backup

- **[ci.yml.old](ci.yml.old)** - Previous CI workflow (replaced by build-test.yml)

## Documentation

📚 **Full Documentation**: [../CICD.md](../CICD.md)  
⚡ **Quick Reference**: [../CICD-QUICKREF.md](../CICD-QUICKREF.md)

## Workflow Execution Matrix

| Workflow | Trigger | Runs On | Purpose |
|----------|---------|---------|---------|
| Build & Test | Push, PR | Windows (matrix) | Quality validation |
| Security | Push, PR, Weekly | Windows, Ubuntu | Vulnerability scanning |
| Release | Tag `v*.*.*` | Windows, Ubuntu | Release automation |
| Workflow Test | Workflow changes, Monthly | Windows, Ubuntu | CI/CD validation |
| Dependabot | Weekly (Mon 6 AM UTC) | GitHub | Dependency updates |

## Quick Start

### Running Workflows Manually

Via GitHub CLI:
```bash
gh workflow run build-test.yml
gh workflow run security.yml
gh workflow run workflow-test.yml
```

Via GitHub UI:
1. Go to **Actions** tab
2. Select workflow from left sidebar
3. Click **Run workflow** button

### Viewing Workflow Results

```bash
# List recent runs
gh run list --limit 10

# Watch a running workflow
gh run watch

# View specific run
gh run view <run-id>
```

## Workflow Design Principles

1. **Fail Fast**: Catch issues early in the pipeline
2. **Matrix Testing**: Test across multiple OS and PowerShell versions
3. **Security First**: Multiple layers of security scanning
4. **Self-Testing**: Workflows validate themselves
5. **Clear Feedback**: Detailed error messages and summaries
6. **Artifact Retention**: Appropriate retention periods for different artifacts

## Maintenance

### Adding a New Workflow

1. Create workflow file in this directory
2. Test with actionlint: `actionlint <workflow-file.yml>`
3. Add to **workflow-test.yml** validation list
4. Document in **[../CICD.md](../CICD.md)**
5. Update this README

### Modifying Existing Workflows

1. Make changes to workflow file
2. Test syntax: `actionlint <workflow-file.yml>`
3. Run **workflow-test.yml** to validate
4. Update documentation if needed
5. Test with real trigger (use workflow_dispatch if available)

### Debugging Workflows

Enable debug logging:
```bash
# Set repository secret ACTIONS_STEP_DEBUG=true
gh secret set ACTIONS_STEP_DEBUG -b"true"

# Or via UI: Settings → Secrets → Actions → New repository secret
```

## Required Secrets

Configure in **Settings → Secrets and variables → Actions**:

- `CODECOV_TOKEN` - Optional, for code coverage reporting
- `PSGALLERY_API_KEY` - Required for PowerShell Gallery publishing

## Support

- **Issues**: Report workflow problems with the `ci/cd` label
- **Questions**: See [../CICD.md](../CICD.md) or open a discussion
- **Changes**: Submit PRs with workflow changes

---

**Last Updated**: 2026-01-15  
**Maintained By**: Plures Organization
