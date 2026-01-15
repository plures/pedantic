# CI/CD Troubleshooting Playbook

This playbook provides step-by-step solutions for common CI/CD issues.

## Table of Contents
- [Build & Test Failures](#build--test-failures)
- [Security Scan Failures](#security-scan-failures)
- [Release Failures](#release-failures)
- [Dependabot Issues](#dependabot-issues)
- [Workflow Self-Test Failures](#workflow-self-test-failures)
- [Performance Issues](#performance-issues)

## Build & Test Failures

### PSScriptAnalyzer Errors

**Symptom**: Workflow fails with PSScriptAnalyzer errors

**Diagnosis**:
```powershell
# Run locally to see exact errors
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
```

**Solutions**:

1. **Fix code issues** (preferred):
   ```powershell
   # Get detailed report
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 | Format-List
   
   # Auto-fix where possible
   Invoke-ScriptAnalyzer -Path . -Recurse -Fix
   ```

2. **Suppress specific rules** (temporary):
   Edit `PSScriptAnalyzerSettings.psd1`:
   ```powershell
   @{
       ExcludeRules = @(
           'RuleName'  # Add rule to exclude with comment explaining why
       )
   }
   ```

3. **Inline suppression** (for specific cases):
   ```powershell
   [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
   param()
   ```

### Pester Test Failures

**Symptom**: Tests pass locally but fail in CI

**Common Causes**:
1. PowerShell version differences (CI uses 7.2 and 7.4)
2. Environment-specific dependencies
3. Timing issues in async operations
4. Path separator differences

**Diagnosis**:
```powershell
# Check PowerShell version
$PSVersionTable

# Run with specific version
pwsh-7.2 -Command "Invoke-Pester -Path tests -Output Detailed"

# Check for environment dependencies
Get-Command SomeCommand -ErrorAction SilentlyContinue
```

**Solutions**:

1. **Version compatibility**:
   ```powershell
   # In test, check version
   if ($PSVersionTable.PSVersion.Major -lt 7) {
       Set-ItResult -Skipped -Because "Requires PowerShell 7+"
   }
   ```

2. **Path handling**:
   ```powershell
   # Use Join-Path instead of string concatenation
   $path = Join-Path $PSScriptRoot 'file.txt'  # ✅ Good
   $path = "$PSScriptRoot\file.txt"            # ❌ Bad (Windows-specific)
   ```

3. **Async operations**:
   ```powershell
   # Add explicit waits
   Start-Job -ScriptBlock { ... } | Wait-Job | Receive-Job
   ```

4. **Debug CI-specific issues**:
   - Enable debug logging: Set `ACTIONS_STEP_DEBUG=true` secret
   - Add verbose output to tests:
     ```powershell
     Write-Host "Debug: Variable value is $value" -ForegroundColor Cyan
     ```

### Module Packaging Failures

**Symptom**: "Package created" step fails

**Diagnosis**:
```powershell
# Test packaging locally
$out = Join-Path $env:TEMP 'test-package'
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Path $out }

$ver = (Import-PowerShellDataFile './Pedantic.psd1').ModuleVersion
Compress-Archive -Path 'Pedantic.psd1','Pedantic.psm1' -DestinationPath (Join-Path $out "test-$ver.zip")
```

**Solutions**:

1. **Missing files**:
   ```powershell
   # Check all required files exist
   $required = @('Pedantic.psd1', 'Pedantic.psm1')
   $required | ForEach-Object {
       if (-not (Test-Path $_)) { Write-Warning "Missing: $_" }
   }
   ```

2. **Invalid manifest**:
   ```powershell
   # Validate manifest
   Test-ModuleManifest ./Pedantic.psd1
   ```

3. **Path too long** (Windows):
   - Keep file paths under 260 characters
   - Use shorter output directory names

### Code Coverage Upload Failures

**Symptom**: Codecov upload fails or times out

**Solutions**:

1. **Token not set** (non-blocking):
   - This is optional, workflow continues
   - Set `CODECOV_TOKEN` secret to enable

2. **Coverage file missing**:
   ```powershell
   # Ensure coverage is enabled in Pester
   $config = New-PesterConfiguration
   $config.CodeCoverage.Enabled = $true
   $config.CodeCoverage.OutputPath = 'coverage.xml'
   ```

3. **Network timeout**:
   - Workflow has `fail_ci_if_error: false`, so won't block
   - Check Codecov status page
   - Retry workflow run

## Security Scan Failures

### CodeQL Initialization Failures

**Symptom**: CodeQL fails to initialize or find code

**Diagnosis**:
- Check if `extension` directory exists and has JavaScript code
- Verify node_modules is excluded in CodeQL config

**Solutions**:

1. **No JavaScript code**:
   - Normal if repository is PowerShell-only
   - Workflow will skip or show as success

2. **Syntax errors**:
   ```bash
   # Check JavaScript syntax
   node -c extension/**/*.js
   ```

3. **Configuration issues**:
   - Review `.github/workflows/security.yml`
   - Verify `paths` and `paths-ignore` are correct

### Dependency Review Blocks PR

**Symptom**: PR blocked by dependency vulnerability

**Diagnosis**:
```bash
# Check PR comments for vulnerability details
# Or run locally (requires npm):
cd extension
npm audit --production
```

**Solutions**:

1. **Update dependency**:
   ```bash
   cd extension
   npm update <package-name>
   npm audit fix
   ```

2. **No fix available**:
   - Document vulnerability in PR description
   - Explain mitigation (e.g., not exposed, dev-only)
   - Add justification for override
   - Consider alternative package

3. **False positive**:
   - Check if vulnerability applies to your usage
   - Document in PR why it's safe
   - May need security team approval

### Secret Scanning False Positives

**Symptom**: TruffleHog flags test data or examples as secrets

**Solutions**:

1. **Use placeholder values**:
   ```powershell
   # Instead of real-looking example API key
   $apiKey = "sk_test_EXAMPLE_NOT_REAL_KEY"  # ❌ May trigger scanner
   
   # Use obvious placeholder
   $apiKey = "YOUR_API_KEY_HERE"  # ✅ Recognized as placeholder
   ```

2. **Mark as false positive**:
   - Go to Security → Code scanning alerts
   - Find alert, click "Dismiss"
   - Select reason: "Used in tests"

3. **Update code comments**:
   ```powershell
   # Example API key format (not a real key)
   $apiKey = "sk_test_..."
   ```

### PowerShell Security Rule Violations

**Symptom**: Security workflow fails on PowerShell security rules

**Solutions**:

1. **Plain text password**:
   ```powershell
   # ❌ Bad
   $password = "MyPassword"
   
   # ✅ Good
   $securePassword = Read-Host "Enter password" -AsSecureString
   ```

2. **Invoke-Expression usage**:
   ```powershell
   # ❌ Avoid
   Invoke-Expression $userInput
   
   # ✅ Use safer alternatives
   & $command $args
   ```

3. **Global variables**:
   ```powershell
   # ❌ Avoid
   $global:MyVar = "value"
   
   # ✅ Use module-scoped or pass parameters
   $script:MyVar = "value"
   ```

## Release Failures

### Version Mismatch

**Symptom**: "Version mismatch: Manifest=X.Y.Z, Release=A.B.C"

**Solution**:
```powershell
# 1. Check current manifest version
(Import-PowerShellDataFile './Pedantic.psd1').ModuleVersion

# 2. Update manifest to match tag
# Edit Pedantic.psd1:
ModuleVersion = '1.2.3'  # Match your tag

# 3. Commit and push
git add Pedantic.psd1
git commit -m "chore: update version to 1.2.3"
git push

# 4. Delete and recreate tag
git tag -d v1.2.3
git push origin :refs/tags/v1.2.3
git tag v1.2.3
git push origin v1.2.3
```

### Invalid Version Format

**Symptom**: "Invalid version format: vX.Y.Z-alpha"

**Solution**:
- Use semantic versioning: `vX.Y.Z` (e.g., v1.0.0)
- Pre-releases: Workflow marks as prerelease automatically if tag contains alpha/beta/rc
- Don't include 'v' in manifest, only in git tag

### PowerShell Gallery Publish Fails

**Symptom**: Publishing to PSGallery fails

**Diagnosis**:
```powershell
# Check if secret is set
# In GitHub: Settings → Secrets → Actions → PSGALLERY_API_KEY

# Test locally (if you have API key)
Publish-Module -Path ./release/Pedantic -NuGetApiKey $env:PSGALLERY_API_KEY -WhatIf
```

**Solutions**:

1. **API key not set**:
   - Get key from https://www.powershellgallery.com/account/apikeys
   - Add as `PSGALLERY_API_KEY` secret in GitHub
   - Workflow will skip publish if not set

2. **Module name already taken**:
   - Check PowerShell Gallery for name conflicts
   - Choose different module name
   - Update manifest

3. **Manifest validation fails**:
   ```powershell
   # Validate manifest
   Test-ModuleManifest -Path ./Pedantic.psd1
   
   # Check for required fields
   $manifest = Import-PowerShellDataFile './Pedantic.psd1'
   $manifest.Author       # Must be set
   $manifest.Description  # Must be set
   ```

4. **Network/timeout issues**:
   - Check PowerShell Gallery status
   - Wait 5-10 minutes, retry
   - Use workflow_dispatch to retry release manually

### Changelog Generation Issues

**Symptom**: Empty or malformed changelog

**Solutions**:

1. **No commits since last tag**:
   - Expected for hotfix releases
   - Add manual notes to GitHub release

2. **Merge commits clutter**:
   - Already filtered with `--no-merges`
   - Use squash merges for cleaner history

3. **Want custom changelog format**:
   - Edit `.github/workflows/release.yml`
   - Modify changelog generation script
   - Consider using conventional commits

## Dependabot Issues

### Too Many PRs

**Symptom**: Drowning in dependency update PRs

**Solutions**:

1. **Reduce frequency**:
   ```yaml
   # Edit .github/dependabot.yml
   schedule:
     interval: "monthly"  # Instead of weekly
   ```

2. **Limit concurrent PRs**:
   ```yaml
   open-pull-requests-limit: 3  # Reduce from 5 or 10
   ```

3. **Group updates**:
   ```yaml
   groups:
     all-dependencies:
       patterns:
         - "*"
   ```

### Dependabot PRs Fail Tests

**Symptom**: Automated PRs break tests

**Solutions**:

1. **Minor/patch updates**:
   ```bash
   # Merge if tests pass
   gh pr merge <pr-number> --auto --squash
   ```

2. **Major version breaks**:
   - Review changelog of updated package
   - Update code to work with new version
   - Or pin to old version temporarily:
     ```yaml
     # In dependabot.yml
     ignore:
       - dependency-name: "package-name"
         update-types: ["version-update:semver-major"]
     ```

3. **Close batch of failing PRs**:
   ```bash
   # Close all failing dependabot PRs
   gh pr list --label dependencies --json number,statusCheckRollup \
     | jq -r '.[] | select(.statusCheckRollup[0].state == "FAILURE") | .number' \
     | xargs -I {} gh pr close {}
   ```

### Dependabot Can't Access Private Packages

**Symptom**: PRs fail because can't download private dependencies

**Solutions**:

1. **Add registry credentials**:
   - Settings → Secrets → Dependabot secrets
   - Add NPM_TOKEN or similar

2. **Use GitHub Packages**:
   - Configure authentication in dependabot.yml
   - See: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/configuring-access-to-private-registries-for-dependabot

## Workflow Self-Test Failures

### actionlint Errors

**Symptom**: Workflow validation fails with syntax errors

**Solutions**:

1. **Install actionlint locally**:
   ```bash
   # macOS
   brew install actionlint
   
   # Linux
   curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
   
   # Windows
   scoop install actionlint
   ```

2. **Run locally**:
   ```bash
   actionlint .github/workflows/*.yml
   ```

3. **Common issues**:
   - Missing required fields
   - Invalid step references
   - Type mismatches in expressions
   - Unknown context variables

4. **Fix and verify**:
   ```bash
   # Edit workflow file
   # Then validate again
   actionlint .github/workflows/your-workflow.yml
   ```

### Component Tests Fail

**Symptom**: Individual workflow components don't work

**Solutions**:

1. **PSScriptAnalyzer not working**:
   ```powershell
   # Reinstall
   Install-Module PSScriptAnalyzer -Force -SkipPublisherCheck
   
   # Test
   Invoke-ScriptAnalyzer -Path . -Recurse | Select-Object -First 1
   ```

2. **Pester not working**:
   ```powershell
   # Ensure Pester 5.x
   Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
   
   # Verify version
   (Get-Module Pester -ListAvailable).Version
   ```

3. **Packaging fails**:
   - Check file paths exist
   - Verify temp directory accessible
   - Check disk space

## Performance Issues

### Slow Workflow Runs

**Symptom**: Workflows take too long to complete

**Solutions**:

1. **Cache PowerShell modules**:
   ```yaml
   # Add to workflow
   - name: Cache PowerShell modules
     uses: actions/cache@v3
     with:
       path: ~/Documents/PowerShell/Modules
       key: ${{ runner.os }}-psmodules-${{ hashFiles('**/*.psd1') }}
   ```

2. **Reduce matrix size**:
   ```yaml
   # Instead of 4 combinations, use 2
   strategy:
     matrix:
       os: [windows-latest]  # Remove windows-2019
       ps-version: ['7.2', '7.4']
   ```

3. **Skip redundant jobs**:
   ```yaml
   # Skip security on PR if also running on push
   if: github.event_name != 'pull_request'
   ```

### Timeout Errors

**Symptom**: Workflow hits timeout limit

**Solutions**:

1. **Increase timeout**:
   ```yaml
   jobs:
     my-job:
       timeout-minutes: 60  # Increase from default 30
   ```

2. **Optimize tests**:
   ```powershell
   # Run in parallel where possible
   # Skip slow integration tests in PR builds
   ```

3. **Split into multiple jobs**:
   ```yaml
   jobs:
     unit-tests:
       # Fast tests
     integration-tests:
       needs: unit-tests
       # Slow tests
   ```

## General Debugging Steps

### Step 1: Check Workflow Logs

```bash
# List recent runs
gh run list --limit 10

# View specific run
gh run view <run-id> --log

# Download logs
gh run download <run-id>
```

### Step 2: Enable Debug Logging

```bash
# Set secret
gh secret set ACTIONS_STEP_DEBUG -b"true"

# Or via UI: Settings → Secrets → Actions → New repository secret
# Name: ACTIONS_STEP_DEBUG
# Value: true
```

### Step 3: Reproduce Locally

```powershell
# Run same commands locally
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-Pester -Path tests
```

### Step 4: Check Dependencies

```bash
# Verify all tools installed
gh --version
git --version
pwsh --version
```

### Step 5: Review Recent Changes

```bash
# Check recent workflow changes
git log --oneline .github/workflows/ -10

# Compare with last working version
git diff <last-working-commit> .github/workflows/
```

## Getting Additional Help

If issues persist:

1. **Check GitHub Status**: https://www.githubstatus.com/
2. **Search Issues**: Look for similar problems in repository issues
3. **Open Issue**: Create new issue with:
   - Workflow run URL
   - Error messages
   - Steps to reproduce
   - What you've tried
4. **Review Documentation**: [CICD.md](CICD.md)
5. **GitHub Actions Docs**: https://docs.github.com/actions

---

**Troubleshooting Playbook Version**: 1.0.0  
**Last Updated**: 2026-01-15  
**See Also**: [CICD.md](CICD.md) | [CICD-QUICKREF.md](CICD-QUICKREF.md)
