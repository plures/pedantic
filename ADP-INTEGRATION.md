# ADP Integration Guide

## Overview

This document describes how to integrate ADP (Automated Development Process) into the StateSmith project.

## What is ADP?

ADP is a development automation and process management tool from the plures organization designed to help streamline development workflows, provide automated assistance, and keep projects on track.

## Integration Status

**Current Status:** Pending repository access

The ADP repository (https://github.com/plures/ADP.git) requires authentication to access. Once access is granted, follow the steps below to complete the integration.

## Setup Instructions

### Prerequisites

- Git access to https://github.com/plures/ADP.git
- PowerShell 7+ (for PowerShell module integration)
- Node.js 18+ (for VS Code extension integration)

### Step 1: Add ADP as a Git Submodule

```bash
# From the repository root
git submodule add https://github.com/plures/ADP.git .adp
git submodule update --init --recursive
```

### Step 2: Configure ADP

Create or update `.adp/config.json` with project-specific settings:

```json
{
  "project": "StateSmith DSC",
  "type": "hybrid",
  "components": {
    "powershell": {
      "enabled": true,
      "path": "./"
    },
    "vscode-extension": {
      "enabled": true,
      "path": "./extension"
    }
  },
  "automation": {
    "ci": true,
    "linting": true,
    "testing": true
  }
}
```

### Step 3: Update CI/CD Workflow

Add ADP initialization to `.github/workflows/ci.yml`:

```yaml
- name: Initialize ADP
  shell: pwsh
  run: |
    if (Test-Path '.adp') {
      ./.adp/scripts/init.ps1
    }
```

### Step 4: Initialize ADP

```bash
# Run ADP initialization
./.adp/scripts/init.sh  # On Unix-like systems
# or
.\.adp\scripts\init.ps1  # On Windows
```

## Usage

Once integrated, ADP should provide:

- Automated development workflow assistance
- Project structure validation
- Dependency management
- Build and test automation enhancements
- Development process monitoring

## Troubleshooting

### Cannot Access ADP Repository

If you receive authentication errors when trying to clone or initialize ADP:

1. Ensure you have proper permissions to the plures/ADP repository
2. Configure Git credentials: `git config --global credential.helper store`
3. Contact the repository maintainer for access

### ADP Scripts Not Found

If ADP scripts are not found after submodule initialization:

```bash
git submodule update --init --recursive --remote
```

## Documentation

For full ADP documentation, see:
- `.adp/README.md` (once initialized)
- `.adp/docs/` directory

## Support

For issues related to ADP integration, please:
1. Check the ADP repository issues: https://github.com/plures/ADP/issues
2. Review this integration guide
3. Open an issue in the StateSmith repository with the `adp-integration` label
