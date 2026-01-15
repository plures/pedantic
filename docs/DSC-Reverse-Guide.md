# DSC Reverse - Configuration Cataloging and Drift Detection

## Overview

DSC Reverse is a powerful feature that provides comprehensive configuration management capabilities including:

- **Configuration Cataloging**: Capture current system state as DSC YAML configurations
- **Historical Tracking**: Store snapshots with timestamps for change tracking
- **Diff Analysis**: Compare configurations between time periods
- **Drift Detection**: Identify what changed and when
- **Revert Capability**: Apply previous configurations to restore systems

## Key Features

### 1. System Cataloging (`New-DscSystemCatalog`)

Captures the current state of a system and generates DSC configuration files that represent the current configuration.

**Supported Resource Types:**
- Registry settings
- File contents
- Service configurations
- Windows Features
- Package installations

**Example:**
```powershell
# Catalog a remote system
$catalog = New-DscSystemCatalog -ComputerName "SERVER01" -CatalogName "WebServerConfig" -IncludeResources @("Registry", "File", "Service")

# Catalog with custom resources
$catalog = New-DscSystemCatalog -ComputerName "SERVER01" -CatalogName "CustomConfig" -IncludeResources @("Registry", "File") -ExcludeResources @("Service")
```

### 2. Historical Tracking (`Get-DscCatalogHistory`)

Maintains a history of all catalog snapshots for each system, allowing you to track changes over time.

**Example:**
```powershell
# Get recent catalog history
$history = Get-DscCatalogHistory -ComputerName "SERVER01" -Limit 10

# Get history for a custom system identifier
$history = Get-DscCatalogHistory -CustomIdentifier "WebServer-Prod" -Limit 20
```

### 3. Configuration Comparison (`Compare-DscCatalogs`)

Compares two catalog configurations and generates detailed diff reports showing what changed between snapshots.

**Example:**
```powershell
# Compare two catalogs
$diff = Compare-DscCatalogs -SourceCatalog "catalog1.yaml" -TargetCatalog "catalog2.yaml" -OutputPath "diff-report.json"

# Compare with detailed output
$diff = Compare-DscCatalogs -SourceCatalog "catalog1.yaml" -TargetCatalog "catalog2.yaml" -IncludeUnchanged
```

### 4. Configuration Restoration (`Restore-DscSystemConfiguration`)

Reverts a system configuration to a previous catalog state, enabling quick recovery from configuration drift.

**Example:**
```powershell
# Preview restoration (WhatIf mode)
$result = Restore-DscSystemConfiguration -CatalogPath "backup-catalog.yaml" -ComputerName "SERVER01" -WhatIf

# Perform actual restoration
$result = Restore-DscSystemConfiguration -CatalogPath "backup-catalog.yaml" -ComputerName "SERVER01"
```

## Use Cases

### 1. Configuration Drift Detection

**Scenario**: Monitor a production server for unauthorized changes.

```powershell
# Create baseline catalog
$baseline = New-DscSystemCatalog -ComputerName "PROD-SERVER" -CatalogName "Baseline" -IncludeResources @("Registry", "File", "Service")

# Later, create current catalog
$current = New-DscSystemCatalog -ComputerName "PROD-SERVER" -CatalogName "Current" -IncludeResources @("Registry", "File", "Service")

# Compare to detect drift
$drift = Compare-DscCatalogs -SourceCatalog $baseline.FilePath -TargetCatalog $current.FilePath

if ($drift.summary.totalChanged -gt 0) {
    Write-Host "Configuration drift detected!" -ForegroundColor Red
    Write-Host "Changed resources: $($drift.summary.totalChanged)" -ForegroundColor Yellow
}
```

### 2. Change Tracking and Auditing

**Scenario**: Track all configuration changes over time for compliance.

```powershell
# Get historical changes
$history = Get-DscCatalogHistory -ComputerName "PROD-SERVER" -Limit 50

foreach ($entry in $history) {
    Write-Host "Change on $($entry.timestamp): $($entry.catalogName)" -ForegroundColor Cyan
}

# Compare specific time periods
$oldCatalog = "catalog-2024-01-01.yaml"
$newCatalog = "catalog-2024-01-15.yaml"
$changes = Compare-DscCatalogs -SourceCatalog $oldCatalog -TargetCatalog $newCatalog
```

### 3. Disaster Recovery

**Scenario**: Quickly restore a system to a known good state.

```powershell
# Restore from a known good catalog
$restoreResult = Restore-DscSystemConfiguration -CatalogPath "known-good-config.yaml" -ComputerName "FAILED-SERVER"

if ($restoreResult.Success) {
    Write-Host "System restored successfully!" -ForegroundColor Green
} else {
    Write-Host "Restoration failed. Check errors:" -ForegroundColor Red
    foreach ($error in $restoreResult.Errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
}
```

### 4. Configuration Validation

**Scenario**: Validate that a system matches its expected configuration.

```powershell
# Create expected configuration catalog
$expected = New-DscSystemCatalog -ComputerName "TARGET-SERVER" -CatalogName "Expected" -IncludeResources @("Registry", "File")

# Create actual configuration catalog
$actual = New-DscSystemCatalog -ComputerName "TARGET-SERVER" -CatalogName "Actual" -IncludeResources @("Registry", "File")

# Compare to validate
$validation = Compare-DscCatalogs -SourceCatalog $expected.FilePath -TargetCatalog $actual.FilePath

if ($validation.summary.totalChanged -eq 0 -and $validation.summary.totalAdded -eq 0 -and $validation.summary.totalRemoved -eq 0) {
    Write-Host "Configuration validation passed!" -ForegroundColor Green
} else {
    Write-Host "Configuration validation failed!" -ForegroundColor Red
}
```

## File Structure

The DSC Reverse module creates the following directory structure:

```
src/DSC/
├── Catalogs/                    # Generated catalog files
│   └── {system-id}/            # Per-system catalog directories
│       ├── SystemCatalog-20241201-143022.yaml
│       └── SystemCatalog-20241201-143022-metadata.json
├── History/                     # Historical tracking data
│   └── {system-id}-history.json
└── Diffs/                       # Diff reports
    └── diff-report.json
```

## Configuration Options

### Module Configuration

The module uses the following default configuration:

```powershell
$script:ReverseConfig = @{
  CatalogPath        = Join-Path $PSScriptRoot "Catalogs"
  HistoryPath        = Join-Path $PSScriptRoot "History"
  DiffPath           = Join-Path $PSScriptRoot "Diffs"
  MaxHistoryEntries  = 50  # Maximum historical snapshots per system
  DefaultCatalogName = "SystemCatalog"
}
```

### Resource Filtering

You can control which resources are cataloged:

```powershell
# Include specific resources
-IncludeResources @("Registry", "File", "Service", "WindowsFeature")

# Exclude specific resources
-ExcludeResources @("Service", "Package")

# Default includes: Registry, File, Service, WindowsFeature, Package
```

## Security Considerations

### Remote Access

- Uses the same secure transport options as the main DSC module
- Supports SSH, SSL, and HTTP transport methods
- Credentials are required for remote cataloging

### Data Sensitivity

- Catalog files may contain sensitive configuration data
- Store catalogs in secure locations
- Consider encryption for sensitive environments
- Review catalog contents before sharing

### Restoration Safety

- Always use `-WhatIf` parameter to preview changes
- Test restoration procedures in non-production environments
- Keep backups before performing restorations
- Monitor restoration progress and results

## Best Practices

### 1. Regular Cataloging

```powershell
# Create scheduled task for regular cataloging
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-Command `"Import-Module Pedantic.Reverse; New-DscSystemCatalog -ComputerName 'SERVER01' -CatalogName 'DailyCatalog'`""
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
Register-ScheduledTask -TaskName "DSC-DailyCatalog" -Action $action -Trigger $trigger
```

### 2. Baseline Management

```powershell
# Create baseline after system setup
New-DscSystemCatalog -ComputerName "NEW-SERVER" -CatalogName "Baseline" -IncludeResources @("Registry", "File", "Service", "WindowsFeature")

# Create baseline after major changes
New-DscSystemCatalog -ComputerName "UPDATED-SERVER" -CatalogName "PostUpdateBaseline" -IncludeResources @("Registry", "File", "Service", "WindowsFeature")
```

### 3. Change Documentation

```powershell
# Document changes with descriptive catalog names
New-DscSystemCatalog -ComputerName "SERVER01" -CatalogName "BeforeSecurityPatch" -IncludeResources @("Registry", "File")
# Apply security patch
New-DscSystemCatalog -ComputerName "SERVER01" -CatalogName "AfterSecurityPatch" -IncludeResources @("Registry", "File")

# Compare to document changes
Compare-DscCatalogs -SourceCatalog "BeforeSecurityPatch.yaml" -TargetCatalog "AfterSecurityPatch.yaml" -OutputPath "SecurityPatch-Changes.json"
```

### 4. Monitoring and Alerting

```powershell
# Monitor for configuration drift
$baseline = "baseline-catalog.yaml"
$current = New-DscSystemCatalog -ComputerName "PROD-SERVER" -CatalogName "Current" -Quiet
$drift = Compare-DscCatalogs -SourceCatalog $baseline -TargetCatalog $current.FilePath

if ($drift.summary.totalChanged -gt 0) {
    # Send alert
    Send-MailMessage -To "admin@company.com" -Subject "Configuration Drift Detected" -Body "Server PROD-SERVER has $($drift.summary.totalChanged) changed resources"
}
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure proper credentials for remote access
   - Check file system permissions for catalog storage

2. **Resource Not Found**
   - Verify DSC resources are available on target system
   - Check resource type names in IncludeResources parameter

3. **Large Catalog Files**
   - Use ExcludeResources to filter out unnecessary resources
   - Consider cataloging specific resource types only

4. **Restoration Failures**
   - Check DSC resource availability on target system
   - Review error messages for specific resource failures
   - Use WhatIf mode to preview changes

### Debug Information

Enable verbose output for troubleshooting:

```powershell
# Enable verbose output
$VerbosePreference = "Continue"
New-DscSystemCatalog -ComputerName "SERVER01" -CatalogName "DebugCatalog" -Verbose
```

## Integration with Existing DSC Workflows

DSC Reverse integrates seamlessly with existing DSC workflows:

```powershell
# Use catalog as baseline for new systems
$baseline = New-DscSystemCatalog -ComputerName "TEMPLATE-SERVER" -CatalogName "Template"
Copy-Item $baseline.FilePath "new-server-template.yaml"

# Apply template to new server
Invoke-DscHelper -DscPath "new-server-template.yaml" -Operation "Set" -ComputerName "NEW-SERVER"

# Validate against template
$validation = New-DscSystemCatalog -ComputerName "NEW-SERVER" -CatalogName "Validation"
Compare-DscCatalogs -SourceCatalog $baseline.FilePath -TargetCatalog $validation.FilePath
```

## Future Enhancements

Planned features for future releases:

1. **Automated Drift Detection**: Scheduled monitoring and alerting
2. **Configuration Templates**: Reusable configuration patterns
3. **Compliance Reporting**: Built-in compliance checking
4. **Change Approval Workflows**: Approval processes for configuration changes
5. **Integration with CI/CD**: Pipeline integration for automated validation
6. **Advanced Diff Visualization**: Web-based diff viewing interface
7. **Configuration Analytics**: Trend analysis and reporting
8. **Multi-System Comparison**: Compare configurations across multiple systems

## Conclusion

DSC Reverse provides a comprehensive solution for configuration management, drift detection, and system recovery. By combining cataloging, historical tracking, diff analysis, and restoration capabilities, it enables organizations to maintain control over their infrastructure configurations and quickly respond to changes or issues.

The modular design allows for easy integration with existing workflows while providing powerful new capabilities for configuration management and compliance. 