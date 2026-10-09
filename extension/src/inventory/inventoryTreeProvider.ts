import * as vscode from 'vscode';
import { Host, Inventory } from './inventoryModel';

export enum InventoryItemType {
  Host = 'host',
  HostVars = 'hostVars',
  HostGroupVars = 'hostGroupVars',
  HostFacts = 'hostFacts',
  VarItem = 'varItem',
  FactItem = 'factItem',
  Group = 'group'
}

export class InventoryTreeItem extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly itemType: InventoryItemType,
    public readonly data: any,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    public readonly parent?: InventoryTreeItem
  ) {
    super(label, collapsibleState);
    this.contextValue = itemType;
    this.tooltip = this.getTooltip();
    this.iconPath = this.getIcon();
  }

  private getTooltip(): string {
    switch (this.itemType) {
      case InventoryItemType.Host:
        return `Host: ${this.label}`;
      case InventoryItemType.HostVars:
        return 'Host variables';
      case InventoryItemType.HostGroupVars:
        return 'Group variables';
      case InventoryItemType.HostFacts:
        return 'Gathered facts';
      case InventoryItemType.VarItem:
      case InventoryItemType.FactItem:
        return `${this.label}: ${JSON.stringify(this.data.value)}`;
      case InventoryItemType.Group:
        return `Group: ${this.label}`;
      default:
        return this.label;
    }
  }

  private getIcon() {
    switch (this.itemType) {
      case InventoryItemType.Host:
        return { id: 'vm' };
      case InventoryItemType.HostVars:
      case InventoryItemType.HostGroupVars:
        return { id: 'symbol-variable' };
      case InventoryItemType.HostFacts:
        return { id: 'info' };
      case InventoryItemType.VarItem:
      case InventoryItemType.FactItem:
        return { id: 'symbol-property' };
      case InventoryItemType.Group:
        return { id: 'folder' };
      default:
        return { id: 'circle-outline' };
    }
  }
}

export class InventoryTreeProvider implements vscode.TreeDataProvider<InventoryTreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<InventoryTreeItem | undefined | null>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private inventory: Inventory | undefined;

  constructor() {}

  refresh(): void {
    this._onDidChangeTreeData.fire(undefined);
  }

  setInventory(inventory: Inventory): void {
    this.inventory = inventory;
    this.refresh();
  }

  getTreeItem(element: InventoryTreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: InventoryTreeItem): Thenable<InventoryTreeItem[]> {
    if (!this.inventory) {
      return Promise.resolve(element ? [] : [new InventoryTreeItem(
        'Inventory service is not configured',
        InventoryItemType.Group,
        {},
        vscode.TreeItemCollapsibleState.None
      )]);
    }

    if (!element) {
      // Root level: return hosts
      const items: InventoryTreeItem[] = [];
      
      // Add hosts
      for (const host of this.inventory.hosts || []) {
        items.push(new InventoryTreeItem(
          host.name,
          InventoryItemType.Host,
          host,
          vscode.TreeItemCollapsibleState.Collapsed
        ));
      }

      return Promise.resolve(items);
    }

    // Handle children based on item type
    switch (element.itemType) {
      case InventoryItemType.Host:
        return Promise.resolve(this.getHostChildren(element));
      case InventoryItemType.HostVars:
        return Promise.resolve(this.getVarChildren(element, InventoryItemType.VarItem));
      case InventoryItemType.HostGroupVars:
        return Promise.resolve(this.getVarChildren(element, InventoryItemType.VarItem));
      case InventoryItemType.HostFacts:
        return Promise.resolve(this.getFactChildren(element));
      case InventoryItemType.VarItem:
      case InventoryItemType.FactItem: {
        const value = element.data && (element.data as any).value;
        const children: InventoryTreeItem[] = [];

        if (value !== null && typeof value === 'object') {
          if (Array.isArray(value)) {
            for (const [index, childVal] of value.entries()) {
              const collapsible =
                childVal !== null && typeof childVal === 'object'
                  ? vscode.TreeItemCollapsibleState.Collapsed
                  : vscode.TreeItemCollapsibleState.None;

              children.push(
                new InventoryTreeItem(
                  `[${index}]`,
                  element.itemType,
                  { value: childVal },
                  collapsible,
                  element
                )
              );
            }
          } else {
            for (const [key, childVal] of Object.entries(value)) {
              const collapsible =
                childVal !== null && typeof childVal === 'object'
                  ? vscode.TreeItemCollapsibleState.Collapsed
                  : vscode.TreeItemCollapsibleState.None;

              children.push(
                new InventoryTreeItem(
                  key,
                  element.itemType,
                  { value: childVal },
                  collapsible,
                  element
                )
              );
            }
          }
        }

        return Promise.resolve(children);
      }
      default:
        return Promise.resolve([]);
    }
  }

  private getHostChildren(element: InventoryTreeItem): InventoryTreeItem[] {
    const host: Host = element.data;
    const children: InventoryTreeItem[] = [];

    // Add vars section if vars exist
    if (host.vars && Object.keys(host.vars).length > 0) {
      children.push(new InventoryTreeItem(
        'Vars',
        InventoryItemType.HostVars,
        { vars: host.vars },
        vscode.TreeItemCollapsibleState.Collapsed,
        element
      ));
    }

    // Add group_vars section - get from host's groups
    const groupVars = this.getGroupVarsForHost(host);
    if (groupVars && Object.keys(groupVars).length > 0) {
      children.push(new InventoryTreeItem(
        'Group Vars',
        InventoryItemType.HostGroupVars,
        { vars: groupVars },
        vscode.TreeItemCollapsibleState.Collapsed,
        element
      ));
    }

    // Add facts section if facts exist
    if (host.facts && Object.keys(host.facts).length > 0) {
      children.push(new InventoryTreeItem(
        'Facts',
        InventoryItemType.HostFacts,
        { facts: host.facts },
        vscode.TreeItemCollapsibleState.Collapsed,
        element
      ));
    }

    return children;
  }

  private getGroupVarsForHost(host: Host): any {
    if (!this.inventory || !host.groups || host.groups.length === 0) {
      return {};
    }

    const combinedVars: any = {};
    for (const groupName of host.groups) {
      const group = this.inventory.groups?.find(g => g.name === groupName);
      if (group && group.vars) {
        Object.assign(combinedVars, group.vars);
      }
    }

    return combinedVars;
  }

  private getVarChildren(element: InventoryTreeItem, itemType: InventoryItemType): InventoryTreeItem[] {
    const vars = element.data.vars || {};
    const children: InventoryTreeItem[] = [];

    for (const [key, value] of Object.entries(vars)) {
      const isExpandable = typeof value === 'object' && value !== null && !Array.isArray(value);
      children.push(new InventoryTreeItem(
        key,
        itemType,
        { key, value },
        isExpandable ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None,
        element
      ));
    }

    return children;
  }

  private getFactChildren(element: InventoryTreeItem): InventoryTreeItem[] {
    const facts = element.data.facts || {};
    const children: InventoryTreeItem[] = [];

    for (const [key, value] of Object.entries(facts)) {
      const isExpandable = typeof value === 'object' && value !== null && !Array.isArray(value);
      children.push(new InventoryTreeItem(
        key,
        InventoryItemType.FactItem,
        { key, value },
        isExpandable ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None,
        element
      ));
    }

    return children;
  }

  getParent(element: InventoryTreeItem): vscode.ProviderResult<InventoryTreeItem> {
    return element.parent;
  }
}
