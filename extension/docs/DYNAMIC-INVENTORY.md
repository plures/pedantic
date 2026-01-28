# Dynamic Inventory View

The Pedantic VS Code extension now includes a dynamic inventory view inspired by ansible-cmdb, providing a comprehensive view of hosts, their variables, group variables, and gathered facts.

## Features

### Tree View
- **Host Inventory**: View all discovered hosts in a hierarchical tree structure
- **Expandable Sections**: Each host can be expanded to show:
  - **Vars**: Host-specific variables
  - **Group Vars**: Variables inherited from host groups
  - **Facts**: System facts gathered from the host (similar to Ansible's `gather_facts`)

### Detail Panel
- **Adjacent Pane**: Click any item in the tree to view its details in a side panel
- **Property Inspection**: See all properties and values for the selected item
- **Structured Display**: JSON-formatted view of complex data structures

### Configuration Management
- **Push Configuration**: Right-click on any host to push a DSC configuration
- **Progress Tracking**: Visual progress bar showing configuration deployment status
- **Real-time Updates**: Watch the progress as configuration is applied

### Logging
- **Per-Host Logs**: Session-based logging tracks operations per host (logs are cleared on extension reload)
- **Color-Coded Levels**: Info (blue), Success (green), Warning (yellow), Error (red)
- **Timestamp Tracking**: Every log entry includes a timestamp
- **Scrollable History**: View up to the last 100 log entries for the current session in the detail panel

## Usage

### Viewing Inventory

1. Open the **Pedantic Inventory** view in the VS Code Explorer sidebar
2. Click the refresh icon to gather the latest inventory
3. Expand any host to see its vars, group_vars, and facts
4. Click on any item to see its details in the adjacent pane

### Gathering Facts

1. Right-click on a host in the inventory tree
2. Select **Gather Facts** (or click the cloud download icon)
3. Wait for the facts to be collected
4. Expand the **Facts** section to view gathered information

### Pushing Configuration

1. Right-click on a host in the inventory tree
2. Select **Push Configuration** (or click the cloud upload icon)
3. Select a DSC configuration file (.yaml, .yml, .dsc.yaml)
4. Monitor progress in the detail panel
5. Check the logs for completion status

## Commands

- **`Pedantic: Refresh Inventory`** - Refresh the inventory tree
- **`Pedantic: Show Details`** - Show details for selected item
- **`Pedantic: Gather Facts`** - Gather facts for selected host
- **`Pedantic: Push Configuration`** - Push configuration to selected host

## Mock Data

For demonstration purposes, the service provides mock data including:
- 3 sample hosts (localhost, web-server-01, db-server-01)
- 5 groups (windows, webservers, database, production, development)
- Realistic facts mimicking Ansible's fact structure
