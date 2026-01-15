# Helper Scripts

This directory contains helper scripts for local development and CI/CD workflow testing.

## Available Scripts

### Test-Workflows.ps1

Validates GitHub Actions workflow files locally before pushing.

**Usage:**
```powershell
./scripts/Test-Workflows.ps1
```

**What it checks:**
- ✅ Workflow syntax with actionlint
- ✅ YAML syntax with yamllint
- ✅ Required workflow files exist
- ✅ Dependabot configuration is valid

**Requirements:**
- [actionlint](https://github.com/rhysd/actionlint) - Required
- [yamllint](https://github.com/adrienverge/yamllint) - Optional

**Installation:**
```bash
# macOS
brew install actionlint yamllint

# Linux
# actionlint
curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
# yamllint
pip install yamllint

# Windows
scoop install actionlint
pip install yamllint
```

### Test-LocalCI.ps1

Runs the same checks that will run in CI/CD on your local machine.

**Usage:**
```powershell
# Run all checks
./scripts/Test-LocalCI.ps1

# Skip tests
./scripts/Test-LocalCI.ps1 -SkipTests

# Skip linter
./scripts/Test-LocalCI.ps1 -SkipLinter
```

**What it checks:**
- ✅ PSScriptAnalyzer (code quality and style)
- ✅ Pester tests (functionality)
- ✅ Module manifest validation

**Requirements:**
- PowerShell 7.2+
- Pester 5.x (auto-installed if missing)
- PSScriptAnalyzer (auto-installed if missing)

## Workflow: Pre-Commit Checks

Recommended workflow before committing:

```powershell
# 1. Validate workflows (if you changed .github/workflows/)
./scripts/Test-Workflows.ps1

# 2. Run local CI checks
./scripts/Test-LocalCI.ps1

# 3. If all pass, commit and push
git add .
git commit -m "your message"
git push
```

## Integration with Git Hooks

You can set up these scripts as pre-commit hooks:

### Option 1: Manual Hook

Create `.git/hooks/pre-commit`:
```bash
#!/bin/sh
pwsh -File scripts/Test-LocalCI.ps1 -SkipTests
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

### Option 2: Using Husky (for Node.js projects)

```bash
npm install --save-dev husky
npx husky install
npx husky add .git/hooks/pre-commit "pwsh -File scripts/Test-LocalCI.ps1 -SkipTests"
```

## Troubleshooting

### actionlint Not Found

```bash
# Install actionlint
curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash

# Add to PATH or move to /usr/local/bin
sudo mv ./actionlint /usr/local/bin/
```

### Pester/PSScriptAnalyzer Missing

The scripts auto-install these modules if missing. If you encounter issues:

```powershell
# Manually install
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
```

### Permission Denied

Make scripts executable:
```bash
chmod +x scripts/*.ps1
```

On Windows, you may need to adjust execution policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## CI/CD Documentation

For complete CI/CD documentation, see:
- 📚 [Complete CI/CD Guide](../.github/CICD.md)
- ⚡ [Quick Reference](../.github/CICD-QUICKREF.md)
- 🔧 [Troubleshooting](../.github/CICD-TROUBLESHOOTING.md)

## Contributing

When adding new helper scripts:

1. Follow PowerShell best practices
2. Include comment-based help
3. Add entry to this README
4. Test on Windows, Linux, and macOS if possible
5. Keep scripts focused on a single task

---

**Last Updated**: 2026-01-15
