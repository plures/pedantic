# CI/CD Pipeline Architecture

## Table of Contents
- [Overview](#overview)
- [Workflow Components](#workflow-components)
- [Roles and Responsibilities](#roles-and-responsibilities)
- [Architecture Diagram](#architecture-diagram)
- [Workflow Details](#workflow-details)
- [Security Best Practices](#security-best-practices)
- [Testing the CI/CD](#testing-the-cicd)
- [Troubleshooting](#troubleshooting)
- [Pain Points and Mitigations](#pain-points-and-mitigations)

## Overview

This repository implements a professional, industry-standard CI/CD pipeline designed to minimize developer friction while maximizing code quality, security, and automation. The pipeline follows best practices observed across the GitHub Plures organization and broader industry standards.

### Design Principles

1. **Automation First**: Minimize manual tasks through automated testing, security scanning, dependency management, and releases
2. **Security by Default**: Multiple layers of security scanning integrated into every workflow
3. **Developer Experience**: Fast feedback loops, clear error messages, comprehensive documentation
4. **Self-Testing**: The CI/CD pipeline tests itself to prevent configuration drift
5. **Fail-Safe**: Workflows continue on non-critical errors while reporting issues for review

## Workflow Components

The CI/CD pipeline consists of five primary workflows:

### 1. Build and Test (`build-test.yml`)
- **Trigger**: Push to main/master branches, Pull Requests
- **Purpose**: Validate code quality and functionality
- **Key Features**:
  - Matrix testing across multiple Windows versions and PowerShell versions
  - PSScriptAnalyzer for code quality and style checking
  - Pester test execution with code coverage
  - Artifact generation for distribution
  - Codecov integration for coverage tracking

### 2. Security Scanning (`security.yml`)
- **Trigger**: Push, Pull Requests, Weekly schedule (Mondays 6 AM UTC), Manual
- **Purpose**: Identify security vulnerabilities and compliance issues
- **Key Features**:
  - CodeQL analysis for JavaScript code
  - Dependency review on PRs
  - PowerShell-specific security rule scanning
  - Secret scanning with TruffleHog
  - NPM audit for extension dependencies

### 3. Release Management (`release.yml`)
- **Trigger**: Version tags (`v*.*.*`), Manual dispatch
- **Purpose**: Automate the release process
- **Key Features**:
  - Automated version validation
  - Changelog generation from git history
  - GitHub Release creation with artifacts
  - PowerShell Gallery publishing (when configured)
  - SHA256 checksums for all releases

### 4. Dependency Management (`dependabot.yml`)
- **Trigger**: Weekly schedule (Mondays 6 AM UTC)
- **Purpose**: Keep dependencies up-to-date automatically
- **Key Features**:
  - GitHub Actions version updates
  - NPM dependency updates with security grouping
  - NuGet package updates
  - Automated PR creation with appropriate labels

### 5. Workflow Self-Test (`workflow-test.yml`)
- **Trigger**: Changes to workflow files, Monthly schedule, Manual
- **Purpose**: Validate CI/CD configuration integrity
- **Key Features**:
  - Workflow syntax validation with actionlint
  - Component functionality testing
  - Integration point verification
  - Automated test reporting

## Roles and Responsibilities

### For Developers

**What to do:**
1. Write code and tests following repository standards
2. Ensure code passes local PSScriptAnalyzer checks before pushing
3. Review CI/CD feedback on pull requests
4. Update module version in manifest files when preparing releases

**What the CI/CD accomplishes:**
- Runs comprehensive tests automatically on every push
- Provides code coverage reports
- Identifies security issues early
- Validates code style and quality
- Packages the module for distribution

**Why it's best practice:**
- Catches bugs before they reach production
- Ensures consistent code quality across contributors
- Reduces manual testing burden
- Provides quick feedback on changes

### For Maintainers

**What to do:**
1. Review and merge pull requests (including Dependabot PRs)
2. Create version tags to trigger releases (format: `vX.Y.Z`)
3. Configure required secrets in repository settings
4. Review security scan results weekly
5. Respond to workflow failures promptly

**What the CI/CD accomplishes:**
- Automatically creates releases from tags
- Publishes to PowerShell Gallery
- Generates changelogs from commit history
- Updates dependencies automatically
- Monitors for security vulnerabilities

**Why it's best practice:**
- Eliminates manual release processes
- Ensures all releases follow the same quality standards
- Reduces time spent on dependency management
- Provides audit trail for all changes

### For Security Team

**What to do:**
1. Review security scan results from scheduled runs
2. Configure secret scanning policies
3. Approve or reject dependency updates with security implications
4. Define security baselines and policies

**What the CI/CD accomplishes:**
- Weekly automated security scans
- Dependency vulnerability detection
- Secret scanning across all commits
- CodeQL analysis for code vulnerabilities
- Security-focused PSScriptAnalyzer rules

**Why it's best practice:**
- Proactive security posture
- Comprehensive coverage of multiple vulnerability types
- Early detection before deployment
- Compliance with industry standards

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Developer Actions                        │
│  (Push, PR, Tag Release)                                    │
└────────────┬────────────────────────────────────────────────┘
             │
             v
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Repository                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Source Code  │  │  Workflows   │  │ Configuration│     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└────────────┬────────────────────────────────────────────────┘
             │
             v
┌─────────────────────────────────────────────────────────────┐
│              Continuous Integration (CI)                     │
│  ┌──────────────────────────────────────────────┐           │
│  │  Build & Test Workflow (Matrix)              │           │
│  │  - PSScriptAnalyzer                          │           │
│  │  - Pester Tests                              │           │
│  │  - Code Coverage                             │           │
│  └──────────────────────────────────────────────┘           │
│  ┌──────────────────────────────────────────────┐           │
│  │  Security Scanning Workflow                  │           │
│  │  - CodeQL Analysis                           │           │
│  │  - Dependency Review                         │           │
│  │  - Secret Scanning                           │           │
│  │  - PowerShell Security Rules                 │           │
│  └──────────────────────────────────────────────┘           │
│  ┌──────────────────────────────────────────────┐           │
│  │  Workflow Self-Test                          │           │
│  │  - Syntax Validation                         │           │
│  │  - Component Testing                         │           │
│  └──────────────────────────────────────────────┘           │
└────────────┬────────────────────────────────────────────────┘
             │
             v
┌─────────────────────────────────────────────────────────────┐
│         Continuous Delivery/Deployment (CD)                  │
│  ┌──────────────────────────────────────────────┐           │
│  │  Release Workflow (Tag-triggered)            │           │
│  │  - Version Validation                        │           │
│  │  - Changelog Generation                      │           │
│  │  - Package Creation                          │           │
│  │  - GitHub Release                            │           │
│  │  - PowerShell Gallery Publish                │           │
│  └──────────────────────────────────────────────┘           │
│  ┌──────────────────────────────────────────────┐           │
│  │  Automated Dependency Management             │           │
│  │  - Dependabot (Weekly)                       │           │
│  │  - Automated PRs                             │           │
│  └──────────────────────────────────────────────┘           │
└────────────┬────────────────────────────────────────────────┘
             │
             v
┌─────────────────────────────────────────────────────────────┐
│                    Distribution                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │GitHub Release│  │ PowerShell   │  │   Artifacts  │     │
│  │   Packages   │  │   Gallery    │  │   (CI/CD)    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
             │
             v
┌─────────────────────────────────────────────────────────────┐
│                      End Users                               │
│           (Install via PowerShell Gallery)                   │
└─────────────────────────────────────────────────────────────┘
```

## Workflow Details

### Build and Test Workflow

**Execution Flow:**
1. Checkout code
2. Initialize ADP (if configured)
3. Install PowerShell modules (Pester, PSScriptAnalyzer)
4. Run PSScriptAnalyzer with custom settings
5. Execute Pester tests with coverage
6. Upload test results and coverage to Codecov
7. Package module as ZIP
8. Upload build artifacts

**Matrix Strategy:**
- OS: Windows Latest, Windows 2019
- PowerShell: 7.2, 7.4
- Total: 4 test combinations

**Outputs:**
- Test results (NUnit XML format)
- Code coverage (JaCoCo XML format)
- Module packages (ZIP files)
- Retention: Test results (30 days), Packages (90 days)

### Security Workflow

**CodeQL Analysis:**
- Analyzes JavaScript code in the `extension` directory
- Uses security-extended and security-and-quality query suites
- Excludes node_modules and test directories
- Runs on push, PR, and weekly schedule

**Dependency Review:**
- Only on pull requests
- Fails on moderate or higher severity vulnerabilities
- Blocks GPL-2.0 and GPL-3.0 licenses
- Comments summary on PR when failures detected

**PowerShell Security Scan:**
- Checks for common PowerShell security anti-patterns
- Rules include:
  - Plain text password usage
  - Unsafe credential handling
  - Deprecated WMI cmdlets
  - Invoke-Expression usage
  - Global variable misuse

**Secret Scanning:**
- Uses TruffleHog for comprehensive secret detection
- Scans all commits with full git history
- Only reports verified secrets (reduces false positives)

**NPM Audit:**
- Runs on `extension` directory if package.json exists
- Production dependencies scanned at moderate severity level
- Results uploaded as artifacts for review

### Release Workflow

**Version Validation Phase:**
1. Extract version from tag or manual input
2. Validate semantic version format (X.Y.Z)
3. Compare against module manifest version
4. Fail if mismatch detected

**Changelog Generation:**
- Extracts commits since last tag
- Formats as markdown list with commit hashes
- Includes timestamp and metadata
- Uploaded as artifact

**Package Building:**
1. Run final test suite
2. Create release directory structure
3. Copy all distribution files
4. Create ZIP archive
5. Generate SHA256 checksum
6. Upload as artifact

**GitHub Release:**
- Creates release with changelog
- Attaches ZIP and checksum files
- Marks as prerelease if version contains alpha/beta/rc
- Auto-generates additional release notes from PRs

**PowerShell Gallery Publishing:**
- Only triggers on tag pushes (not manual releases)
- Requires PSGALLERY_API_KEY secret
- Gracefully skips if secret not configured
- Publishes validated module package

### Dependency Management

**GitHub Actions:**
- Weekly updates every Monday at 6 AM UTC
- Maximum 5 open PRs at once
- Labeled with `dependencies` and `github-actions`
- Auto-assigned to maintainers team

**NPM Dependencies:**
- Weekly updates for extension directory
- Security updates grouped together
- Ignores minor/patch updates for dev dependencies
- Maximum 10 open PRs
- Uses `increase` versioning strategy

**NuGet Packages:**
- Weekly scans for PowerShell module dependencies
- Follows same schedule as other ecosystems
- Limited to 5 concurrent PRs

### Workflow Self-Test

**Validation Phase:**
- Runs actionlint for syntax checking
- Verifies all expected workflow files exist
- Checks YAML syntax with yamllint

**Component Testing:**
- Tests PSScriptAnalyzer execution
- Validates Pester functionality
- Verifies packaging capability
- Tests security tooling availability
- Validates version format in manifests
- Tests changelog generation

**Integration Testing:**
- Checks for required documentation
- Verifies artifact retention policies
- Validates secret documentation

**Reporting:**
- Generates summary in GitHub Actions UI
- Shows pass/fail for each test component
- Timestamps all reports

## Security Best Practices

### Implemented Security Measures

1. **Multi-Layer Scanning**
   - Static code analysis (CodeQL)
   - Dependency vulnerability scanning
   - Secret detection
   - PowerShell-specific security rules
   - NPM audit for JavaScript dependencies

2. **Least Privilege Principle**
   - Workflows only request necessary permissions
   - Security workflow explicitly requests security-events write
   - Content permissions read-only where possible

3. **Secure Secrets Management**
   - Secrets never logged or exposed
   - Required secrets documented
   - Graceful degradation when secrets unavailable

4. **Supply Chain Security**
   - Dependency review on all PRs
   - License compliance checking (blocks GPL)
   - Automated dependency updates
   - Checksum verification for releases

5. **Audit Trail**
   - All workflow runs logged
   - Artifacts retained with appropriate lifecycles
   - Release notes auto-generated
   - Test reports preserved

### Configuration Required

**GitHub Repository Secrets:**
```
CODECOV_TOKEN          - For code coverage reporting (optional)
PSGALLERY_API_KEY      - For PowerShell Gallery publishing (required for releases)
```

**Branch Protection Rules (Recommended):**
- Require status checks before merging
- Require review from maintainers
- Require up-to-date branches
- Include administrators in restrictions

**Security Settings:**
- Enable Dependabot alerts
- Enable Dependabot security updates
- Enable secret scanning
- Enable push protection

## Testing the CI/CD

### Why Test the CI/CD?

Traditional CI/CD implementations focus on testing application code but neglect to test the pipeline itself. This creates several problems:
- Configuration drift goes undetected
- Breaking changes discovered only when triggered
- Workflow syntax errors block deployments
- Missing dependencies cause runtime failures

### Our Approach

We implement **CI/CD self-testing** through the `workflow-test.yml` workflow:

**Continuous Validation:**
- Runs on every workflow file change
- Monthly scheduled validation
- Manual trigger capability

**Multi-Level Testing:**
1. **Syntax Level**: Validates YAML syntax and GitHub Actions semantics
2. **Component Level**: Tests individual workflow components in isolation
3. **Integration Level**: Verifies workflows can interact correctly
4. **Functional Level**: Confirms workflows produce expected outputs

**Test Categories:**

1. **Workflow Validation**
   - actionlint checks for syntax errors
   - Validates required workflows exist
   - YAML linting for consistency

2. **Build Workflow Testing**
   - Verifies PSScriptAnalyzer installation and execution
   - Tests Pester functionality
   - Validates packaging process

3. **Security Workflow Testing**
   - Confirms security tools are accessible
   - Tests dependency review configuration
   - Validates secret scanning setup

4. **Release Workflow Testing**
   - Version validation logic
   - Changelog generation capability
   - Package creation process

5. **Integration Testing**
   - Required secrets documented
   - Artifact retention configured
   - Workflow dependencies resolved

### Running Self-Tests

**Automatic:**
- Triggered on workflow file changes
- Monthly validation (1st of month, 3 AM UTC)

**Manual:**
```bash
# Via GitHub UI
Actions → Workflow Self-Test → Run workflow

# Via GitHub CLI
gh workflow run workflow-test.yml
```

**Interpreting Results:**
- Green checkmark: All tests passed
- Red X: Review step summary for details
- Yellow warning: Non-critical issues detected

## Troubleshooting

### Common Issues and Solutions

#### Build Failures

**Problem**: PSScriptAnalyzer fails with errors
```
Solution:
1. Run locally: Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
2. Fix reported issues
3. Commit and push
4. Alternatively, update PSScriptAnalyzerSettings.psd1 to exclude specific rules temporarily
```

**Problem**: Pester tests fail in CI but pass locally
```
Solution:
1. Check PowerShell version compatibility (CI uses matrix of 7.2 and 7.4)
2. Verify test doesn't depend on local environment
3. Check for timing issues (use -Wait in async operations)
4. Review test output in workflow logs
```

**Problem**: Packaging fails
```
Solution:
1. Verify all required files exist
2. Check module manifest is valid: Test-ModuleManifest ./Pedantic.psd1
3. Ensure no file path length issues (Windows limitation)
4. Check temp directory has sufficient space
```

#### Security Scan Failures

**Problem**: CodeQL fails to initialize
```
Solution:
1. Verify JavaScript code exists in extension directory
2. Check for syntax errors in JS files
3. Ensure node_modules is properly excluded
4. Review CodeQL configuration in workflow file
```

**Problem**: Dependency review blocks PR
```
Solution:
1. Review the detected vulnerabilities
2. Update dependencies: npm update in extension directory
3. If vulnerability has no fix, add justification in PR description
4. Consider waiting for upstream fix
```

**Problem**: Secret scanning reports false positives
```
Solution:
1. Review reported secrets
2. If false positive, mark as such in GitHub Security tab
3. Update code to avoid patterns that look like secrets
4. Consider using placeholder values in examples
```

#### Release Failures

**Problem**: Version validation fails
```
Solution:
1. Ensure tag format is vX.Y.Z (e.g., v1.0.0)
2. Update module manifest version to match tag
3. Verify semantic versioning is used
```

**Problem**: PowerShell Gallery publish fails
```
Solution:
1. Verify PSGALLERY_API_KEY secret is set
2. Check API key hasn't expired
3. Ensure module name isn't already taken
4. Review PowerShell Gallery requirements
5. Check network connectivity to PowerShell Gallery
```

**Problem**: Release artifacts missing
```
Solution:
1. Ensure build-release job completed successfully
2. Check artifact upload step logs
3. Verify files exist in release directory
4. Review file path specifications in workflow
```

#### Dependabot Issues

**Problem**: Too many Dependabot PRs
```
Solution:
1. Adjust open-pull-requests-limit in dependabot.yml
2. Group related updates together
3. Schedule updates less frequently
4. Ignore specific dependencies if needed
```

**Problem**: Dependabot PRs fail checks
```
Solution:
1. Review failing checks (usually test failures)
2. Update tests to work with new dependency versions
3. Pin problematic dependencies temporarily
4. Report issues to upstream if dependency is broken
```

### Workflow Debug Mode

Enable debug logging:
```
GitHub Repository Settings → Secrets and variables → Actions
Add repository secret: ACTIONS_STEP_DEBUG = true
```

This provides verbose logging for all workflow steps.

### Getting Help

1. **Check Workflow Logs**: Detailed output for each step
2. **Review Job Summary**: High-level overview and test reports
3. **Search Issues**: Check if others encountered similar problems
4. **GitHub Actions Documentation**: https://docs.github.com/actions
5. **PowerShell Gallery Documentation**: https://docs.microsoft.com/powershell/gallery

## Pain Points and Mitigations

### Identified Pain Points

#### 1. Windows-Only Testing Environment

**Pain Point:**
- PowerShell DSC is primarily Windows-focused
- Matrix testing limited to Windows runners
- Longer CI execution times
- Higher costs for Windows runners

**Mitigation:**
- Use matrix strategy to parallelize across Windows versions
- Cache PowerShell modules to speed up installation
- Optimize test execution (run only changed tests when possible)
- Consider GitHub-hosted runners vs self-hosted for cost optimization
- Use fail-fast: false to see all failures, not just first

#### 2. Module Version Management

**Pain Point:**
- Manual version updates in manifest files
- Risk of version mismatches between manifest and release tag
- No automatic semantic versioning

**Mitigation:**
- Strict validation in release workflow
- Fail fast if version mismatch detected
- Document clear versioning policy
- Consider adding GitVersion for automatic versioning in future
- Provide clear error messages when validation fails

#### 3. PowerShell Gallery Publishing

**Pain Point:**
- Requires API key management
- No test environment for PowerShell Gallery
- Publishing is irreversible (can't delete versions)
- Rate limiting on PowerShell Gallery

**Mitigation:**
- Clearly document API key setup
- Graceful handling when API key missing
- Thorough testing before release
- Version validation before publish
- Manual approval option for production releases
- Keep local copies of all published versions

#### 4. Security Scanning Noise

**Pain Point:**
- High false positive rate in some scanners
- Alert fatigue from too many warnings
- Legitimate patterns flagged as secrets
- Different security tools may conflict

**Mitigation:**
- Use verified-only mode in TruffleHog
- Configure appropriate severity thresholds
- Document how to mark false positives
- Regular review of scanning rules
- Provide clear guidance on security exceptions
- Use multiple complementary tools vs single tool

#### 5. Dependency Update Volume

**Pain Point:**
- Frequent npm dependency updates
- Time spent reviewing dependency PRs
- Breaking changes in dependencies
- Dependency conflicts

**Mitigation:**
- Group security updates together
- Ignore patch/minor updates for dev dependencies
- Limit concurrent PRs (10 for npm, 5 for others)
- Automated testing catches breaking changes
- Clear labeling for easy identification
- Schedule updates weekly (not daily)

#### 6. CI/CD Configuration Complexity

**Pain Point:**
- Multiple workflow files to maintain
- GitHub Actions YAML can be verbose
- Difficult to test workflows locally
- Configuration spread across multiple files

**Mitigation:**
- Comprehensive workflow self-testing
- Clear documentation with examples
- Reusable workflow components
- actionlint for syntax validation
- Version control for all configuration
- This documentation as single source of truth

#### 7. Secret Management

**Pain Point:**
- Secrets need manual configuration in repository
- No validation that secrets are configured
- Difficult to rotate secrets across repositories
- Risk of secret exposure in logs

**Mitigation:**
- Document all required secrets clearly
- Workflows gracefully degrade without optional secrets
- Fail with clear messages for required secrets
- Never log secret values
- Use GitHub's built-in secret scanning
- Consider GitHub Actions environments for production secrets

#### 8. Test Coverage Gaps

**Pain Point:**
- Limited test infrastructure currently
- Code coverage may be incomplete
- Tests may not cover all PowerShell versions
- Remote execution scenarios hard to test

**Mitigation:**
- Matrix testing across PowerShell versions
- Clear documentation of test requirements
- Encourage test-driven development
- Code coverage tracking with Codecov
- Fail workflow if coverage drops significantly
- Provide test helpers and examples

### Future Improvements

Based on these pain points, potential future enhancements:

1. **Automated Semantic Versioning**: Integrate GitVersion or similar
2. **Reusable Workflows**: Extract common patterns to reduce duplication
3. **Local Testing Tools**: Provide scripts to run CI checks locally
4. **Enhanced Test Coverage**: Expand Pester tests to cover more scenarios
5. **Performance Optimization**: Implement caching strategies for dependencies
6. **Multi-Platform Support**: Add Linux/macOS runners if DSC becomes cross-platform
7. **Release Automation**: Auto-increment versions based on conventional commits
8. **Canary Deployments**: Test releases with subset of users first

## Conclusion

This CI/CD implementation represents industry best practices tailored for PowerShell module development. It provides:

✅ **Automated Testing**: Multi-version, multi-platform validation
✅ **Security First**: Multiple scanning layers with automated updates
✅ **Quality Gates**: PSScriptAnalyzer and Pester integration
✅ **Automated Releases**: Tag-triggered releases with changelog generation
✅ **Self-Testing**: The CI/CD validates itself
✅ **Clear Documentation**: Roles, responsibilities, and troubleshooting
✅ **Pain Point Mitigation**: Proactive solutions to common problems

The pipeline minimizes developer grind through automation while maintaining high quality and security standards. Regular workflow self-tests ensure the CI/CD remains reliable and catches configuration issues early.

For questions or improvements, please open an issue or submit a pull request.

---

**Document Version**: 1.0.0  
**Last Updated**: 2026-01-15  
**Maintained By**: Plures Organization Maintainers
