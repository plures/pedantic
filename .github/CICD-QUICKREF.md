# CI/CD Quick Reference

> **Full Documentation**: See [CICD.md](CICD.md) for complete details.

## For Developers

### Before Pushing Code

```powershell
# Run linter locally
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# Run tests locally
Invoke-Pester -Path tests -Output Detailed

# Check module manifest is valid
Test-ModuleManifest ./StateSmith.DSC.psd1
```

### Understanding CI Results

- ✅ **All green**: Your code passed all checks
- ❌ **Red on Build & Test**: Check PSScriptAnalyzer or test failures
- ❌ **Red on Security**: Review security scan details
- ⚠️ **Warnings**: Review but won't block merge

### Creating a Pull Request

CI will automatically:
1. Run build and test matrix (Windows 2019/Latest, PS 7.2/7.4)
2. Run security scans
3. Check dependencies for vulnerabilities
4. Upload code coverage

No manual action needed unless checks fail.

## For Maintainers

### Merging Pull Requests

All checks must pass before merging:
- [x] Build & Test workflow (all matrix jobs)
- [x] Security workflow
- [x] Code review approved
- [x] All conversations resolved

### Creating a Release

1. **Update version** in `StateSmith.DSC.psd1`
   ```powershell
   ModuleVersion = 'X.Y.Z'  # Update this
   ```

2. **Commit and push** to main branch
   ```bash
   git add StateSmith.DSC.psd1
   git commit -m "chore: bump version to X.Y.Z"
   git push origin main
   ```

3. **Create and push tag**
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. **Wait for automation**:
   - Release workflow validates version
   - Generates changelog
   - Creates GitHub release
   - Publishes to PowerShell Gallery (if configured)

### Managing Dependabot PRs

Weekly automated PRs for dependency updates:

**Quick Actions:**
- ✅ Security updates: Review and merge quickly
- ✅ Minor/patch updates: Merge if tests pass
- ⚠️ Major updates: Review changelog, test locally if needed
- ❌ Breaking changes: May need code updates

**Batch Merging:**
```bash
# Approve multiple dependabot PRs at once (requires gh CLI)
gh pr list --label dependencies --json number --jq '.[].number' | \
  xargs -I {} gh pr merge {} --auto --squash
```

## Required Secrets

Configure in **Settings → Secrets and variables → Actions**:

| Secret | Required | Purpose |
|--------|----------|---------|
| `CODECOV_TOKEN` | Optional | Code coverage reporting |
| `PSGALLERY_API_KEY` | Required for releases | PowerShell Gallery publishing |

## Workflow Triggers

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| Build & Test | Push, PR | Validate code quality |
| Security | Push, PR, Weekly | Find vulnerabilities |
| Release | Tag `v*.*.*` | Create releases |
| Workflow Test | Workflow changes, Monthly | Validate CI/CD |
| Dependabot | Weekly (Monday 6 AM UTC) | Update dependencies |

## Common Commands

### Run Workflow Manually
```bash
# Via GitHub CLI
gh workflow run build-test.yml
gh workflow run security.yml
gh workflow run workflow-test.yml

# Via UI: Actions → Select workflow → Run workflow
```

### Check Workflow Status
```bash
gh run list --workflow=build-test.yml --limit 5
gh run view <run-id>
gh run watch <run-id>
```

### Download Artifacts
```bash
gh run download <run-id>
# Or: Actions → Workflow run → Artifacts section
```

## Troubleshooting Quick Fixes

### PSScriptAnalyzer Errors
```powershell
# Get detailed output
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 | Format-List

# Fix automatically (where possible)
Invoke-ScriptAnalyzer -Path . -Recurse -Fix
```

### Test Failures
```powershell
# Run specific test file
Invoke-Pester -Path tests/StateSmith.DSC.PublicApi.Tests.ps1 -Output Detailed

# Debug mode
$config = New-PesterConfiguration
$config.Debug.WriteDebugMessages = $true
Invoke-Pester -Configuration $config
```

### Version Mismatch
```powershell
# Check current manifest version
(Import-PowerShellDataFile './StateSmith.DSC.psd1').ModuleVersion

# Check git tags
git tag --list 'v*' | sort -V | tail -5
```

### Failed Release
```bash
# Delete failed tag (locally and remotely)
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z

# Fix issues, recreate tag
git tag vX.Y.Z
git push origin vX.Y.Z
```

## Workflow Status Badges

Add to README.md:
```markdown
[![Build & Test](https://github.com/plures/pedantic/actions/workflows/build-test.yml/badge.svg)](https://github.com/plures/pedantic/actions/workflows/build-test.yml)
[![Security](https://github.com/plures/pedantic/actions/workflows/security.yml/badge.svg)](https://github.com/plures/pedantic/actions/workflows/security.yml)
[![codecov](https://codecov.io/gh/plures/pedantic/branch/main/graph/badge.svg)](https://codecov.io/gh/plures/pedantic)
```

## Getting Help

1. **Workflow fails**: Check job logs in Actions tab
2. **Security alerts**: Review in Security → Code scanning
3. **Dependency issues**: Check Dependabot alerts in Security tab
4. **Questions**: Open issue with `question` label
5. **Full docs**: Read [CICD.md](CICD.md)

## Matrix Testing Overview

Every push/PR runs tests on:
- ✅ Windows Latest + PowerShell 7.2
- ✅ Windows Latest + PowerShell 7.4
- ✅ Windows 2019 + PowerShell 7.2
- ✅ Windows 2019 + PowerShell 7.4

All must pass for successful build.

---

**Quick Reference Version**: 1.0.0  
**See also**: [CICD.md](CICD.md) | [Troubleshooting](CICD.md#troubleshooting)
