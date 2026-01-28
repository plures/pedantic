"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.InventoryTreeProvider = exports.InventoryTreeItem = exports.InventoryItemType = void 0;
const vscode = __importStar(require("vscode"));
var InventoryItemType;
(function (InventoryItemType) {
    InventoryItemType["Host"] = "host";
    InventoryItemType["HostVars"] = "hostVars";
    InventoryItemType["HostGroupVars"] = "hostGroupVars";
    InventoryItemType["HostFacts"] = "hostFacts";
    InventoryItemType["VarItem"] = "varItem";
    InventoryItemType["FactItem"] = "factItem";
    InventoryItemType["Group"] = "group";
})(InventoryItemType || (exports.InventoryItemType = InventoryItemType = {}));
class InventoryTreeItem extends vscode.TreeItem {
    label;
    itemType;
    data;
    collapsibleState;
    parent;
    constructor(label, itemType, data, collapsibleState, parent) {
        super(label, collapsibleState);
        this.label = label;
        this.itemType = itemType;
        this.data = data;
        this.collapsibleState = collapsibleState;
        this.parent = parent;
        this.contextValue = itemType;
        this.tooltip = this.getTooltip();
        this.iconPath = this.getIcon();
    }
    getTooltip() {
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
    getIcon() {
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
exports.InventoryTreeItem = InventoryTreeItem;
class InventoryTreeProvider {
    _onDidChangeTreeData = new vscode.EventEmitter();
    onDidChangeTreeData = this._onDidChangeTreeData.event;
    inventory;
    constructor() { }
    refresh() {
        this._onDidChangeTreeData.fire();
    }
    setInventory(inventory) {
        this.inventory = inventory;
        this.refresh();
    }
    getTreeItem(element) {
        return element;
    }
    getChildren(element) {
        if (!this.inventory) {
            return Promise.resolve([]);
        }
        if (!element) {
            // Root level: return hosts and groups
            const items = [];
            // Add hosts
            for (const host of this.inventory.hosts || []) {
                items.push(new InventoryTreeItem(host.name, InventoryItemType.Host, host, vscode.TreeItemCollapsibleState.Collapsed));
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
                const value = element.data && element.data.value;
                const children = [];
                if (value !== null && typeof value === 'object') {
                    if (Array.isArray(value)) {
                        for (const [index, childVal] of value.entries()) {
                            const collapsible = childVal !== null && typeof childVal === 'object'
                                ? vscode.TreeItemCollapsibleState.Collapsed
                                : vscode.TreeItemCollapsibleState.None;
                            children.push(new InventoryTreeItem(`[${index}]`, element.itemType, { value: childVal }, collapsible, element));
                        }
                    }
                    else {
                        for (const [key, childVal] of Object.entries(value)) {
                            const collapsible = childVal !== null && typeof childVal === 'object'
                                ? vscode.TreeItemCollapsibleState.Collapsed
                                : vscode.TreeItemCollapsibleState.None;
                            children.push(new InventoryTreeItem(key, element.itemType, { value: childVal }, collapsible, element));
                        }
                    }
                }
                return Promise.resolve(children);
            }
            default:
                return Promise.resolve([]);
        }
    }
    getHostChildren(element) {
        const host = element.data;
        const children = [];
        // Add vars section if vars exist
        if (host.vars && Object.keys(host.vars).length > 0) {
            children.push(new InventoryTreeItem('Vars', InventoryItemType.HostVars, { vars: host.vars }, vscode.TreeItemCollapsibleState.Collapsed, element));
        }
        // Add group_vars section - get from host's groups
        const groupVars = this.getGroupVarsForHost(host);
        if (groupVars && Object.keys(groupVars).length > 0) {
            children.push(new InventoryTreeItem('Group Vars', InventoryItemType.HostGroupVars, { vars: groupVars }, vscode.TreeItemCollapsibleState.Collapsed, element));
        }
        // Add facts section if facts exist
        if (host.facts && Object.keys(host.facts).length > 0) {
            children.push(new InventoryTreeItem('Facts', InventoryItemType.HostFacts, { facts: host.facts }, vscode.TreeItemCollapsibleState.Collapsed, element));
        }
        return children;
    }
    getGroupVarsForHost(host) {
        if (!this.inventory || !host.groups || host.groups.length === 0) {
            return {};
        }
        const combinedVars = {};
        for (const groupName of host.groups) {
            const group = this.inventory.groups?.find(g => g.name === groupName);
            if (group && group.vars) {
                Object.assign(combinedVars, group.vars);
            }
        }
        return combinedVars;
    }
    getVarChildren(element, itemType) {
        const vars = element.data.vars || {};
        const children = [];
        for (const [key, value] of Object.entries(vars)) {
            const isExpandable = typeof value === 'object' && value !== null && !Array.isArray(value);
            children.push(new InventoryTreeItem(key, itemType, { key, value }, isExpandable ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None, element));
        }
        return children;
    }
    getFactChildren(element) {
        const facts = element.data.facts || {};
        const children = [];
        for (const [key, value] of Object.entries(facts)) {
            const isExpandable = typeof value === 'object' && value !== null && !Array.isArray(value);
            children.push(new InventoryTreeItem(key, InventoryItemType.FactItem, { key, value }, isExpandable ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None, element));
        }
        return children;
    }
    getParent(element) {
        return element.parent;
    }
}
exports.InventoryTreeProvider = InventoryTreeProvider;
