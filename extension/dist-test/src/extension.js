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
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const resourceGraphPanel_1 = require("./webviews/resourceGraphPanel");
const resourceInventoryPanel_1 = require("./webviews/resourceInventoryPanel");
const client_1 = require("./client");
const pwshBridge_1 = require("./bridge/pwshBridge");
const inventoryTreeProvider_1 = require("./inventory/inventoryTreeProvider");
const inventoryDetailPanel_1 = require("./inventory/inventoryDetailPanel");
const inventoryService_1 = require("./inventory/inventoryService");
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
let graphPanel;
let aiPanel;
let inventoryTreeProvider;
function activate(context) {
    // Start the language server
    (0, client_1.activateLanguageServer)(context);
    const disposables = [];
    const commonResources = [
        'Microsoft.DSC/Archive',
        'Microsoft.DSC/File',
        'Microsoft.DSC/Service',
        'Microsoft.Windows/Registry',
        'Microsoft.Windows/File',
        'Microsoft.Windows/Service'
    ];
    const defaultTimeoutMs = 60000;
    const installResource = async (resourceType) => {
        return vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Pedantic: Installing ${resourceType}`
        }, async () => {
            const response = await (0, pwshBridge_1.invokePwsh)({
                command: 'installResource',
                resourceType,
                options: { timeout: defaultTimeoutMs }
            });
            if (!response.success) {
                const errors = response.errors?.join('\n') || 'Unknown error';
                vscode.window.showErrorMessage(`Pedantic: Failed to install ${resourceType}: ${errors}`);
                return false;
            }
            const installed = response.data?.installed;
            vscode.window.showInformationMessage(installed
                ? `Pedantic: Resource ${resourceType} installed`
                : `Pedantic: Install attempted for ${resourceType} (see output)`);
            return installed;
        });
    };
    disposables.push(vscode.commands.registerCommand('pedantic.checkPrereqs', async () => {
        const response = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Pedantic: Checking DSC prerequisites'
        }, async () => {
            return (0, pwshBridge_1.invokePwsh)({
                command: 'prereqs',
                resourceTypes: commonResources,
                options: { timeout: defaultTimeoutMs }
            });
        });
        if (!response.success) {
            const errors = response.errors?.join('\n') || 'Unknown error';
            vscode.window.showErrorMessage(`Pedantic: Prerequisite check failed: ${errors}`);
            return;
        }
        const data = response.data || {};
        const missing = data.commonResources?.missing || [];
        const dscInstalled = !!data.dscInstalled;
        const dscVersion = data.dscVersion;
        const message = `DSC ${dscInstalled ? 'found' : 'not found'}${dscVersion ? ' (' + dscVersion + ')' : ''}. ` +
            (missing.length ? `${missing.length} common resource(s) missing.` : 'Common resources available.');
        const actions = missing.length ? ['Install missing resources', 'Open resource inventory'] : ['Open resource inventory'];
        const selection = await vscode.window.showInformationMessage(message, ...actions);
        if (selection === 'Install missing resources') {
            for (const res of missing) {
                await installResource(res);
            }
        }
        if (selection === 'Open resource inventory') {
            const panel = resourceInventoryPanel_1.ResourceInventoryPanel.createOrShow(context);
            panel.update({
                dscInstalled,
                dscVersion,
                commonResources: data.commonResources,
                installed: data.installedResources,
                cached: data.cached
            });
        }
    }));
    disposables.push(vscode.commands.registerCommand('pedantic.showResourceInventory', async () => {
        const response = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Pedantic: Gathering resource inventory'
        }, async () => {
            return (0, pwshBridge_1.invokePwsh)({
                command: 'resources',
                resourceTypes: commonResources,
                options: { timeout: defaultTimeoutMs }
            });
        });
        if (!response.success) {
            const errors = response.errors?.join('\n') || 'Unknown error';
            vscode.window.showErrorMessage(`Pedantic: Resource inventory failed: ${errors}`);
            return;
        }
        const panel = resourceInventoryPanel_1.ResourceInventoryPanel.createOrShow(context);
        panel.update(response.data || {});
    }));
    disposables.push(vscode.commands.registerCommand('pedantic.addResourceToProject', async () => {
        const response = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Pedantic: Loading available resources'
        }, async () => {
            return (0, pwshBridge_1.invokePwsh)({
                command: 'resources',
                resourceTypes: commonResources,
                options: { timeout: defaultTimeoutMs }
            });
        });
        if (!response.success) {
            const errors = response.errors?.join('\n') || 'Unknown error';
            vscode.window.showErrorMessage(`Pedantic: Failed to load resources: ${errors}`);
            return;
        }
        const data = response.data || {};
        const installedTypes = new Set();
        for (const r of data.installed || data.installedResources || []) {
            const t = r.type || r.Type;
            if (t)
                installedTypes.add(t);
        }
        const candidates = new Map();
        const addCandidate = (type, version, source, detail) => {
            if (!type || installedTypes.has(type) || candidates.has(type)) {
                return;
            }
            candidates.set(type, {
                label: type,
                description: source || 'available',
                detail: version ? `version ${version}` : detail
            });
        };
        for (const r of data.cached || []) {
            addCandidate(r.Type || r.type || r.Key, r.Version || r.version, r.Source || r.source || 'cached', r.Path || r.path);
        }
        const catalog = data.catalog || {};
        for (const r of catalog.MappedResources || []) {
            addCandidate(r.OriginalType, r.Version, r.Source || 'mapped', r.Description);
        }
        for (const r of catalog.BuiltInResources || []) {
            addCandidate(r.Type, r.Version, 'built-in', r.Description);
        }
        for (const r of (catalog.GalleryResources || []).slice?.(0, 50) || []) {
            addCandidate(r.Name, r.Version, r.Source || 'gallery', r.Description);
        }
        if (candidates.size === 0) {
            vscode.window.showInformationMessage('Pedantic: No additional resources available to add.');
            return;
        }
        const pick = await vscode.window.showQuickPick(Array.from(candidates.values()), {
            placeHolder: 'Select a DSC resource to install into this project'
        });
        if (!pick) {
            return;
        }
        await installResource(pick.label);
        const panel = resourceInventoryPanel_1.ResourceInventoryPanel.current();
        if (panel) {
            panel.update(response.data || {});
        }
    }));
    disposables.push(vscode.commands.registerCommand('pedantic.generateConfig', async () => {
        const workspaceIsTrusted = vscode.workspace.isTrusted ?? true;
        if (!workspaceIsTrusted) {
            vscode.window.showWarningMessage('Pedantic: Workspace is not trusted. Enable trust to generate DSC output.');
            return;
        }
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor – open a DSL file to generate.');
            return;
        }
        const doc = editor.document;
        // Save document to temp file if it has unsaved changes
        let dslPath = doc.uri.fsPath;
        let tempFile;
        if (doc.isDirty) {
            const tempDir = path.join(context.globalStoragePath, 'temp');
            if (!fs.existsSync(tempDir)) {
                fs.mkdirSync(tempDir, { recursive: true });
            }
            tempFile = path.join(tempDir, path.basename(doc.fileName));
            fs.writeFileSync(tempFile, doc.getText(), 'utf-8');
            dslPath = tempFile;
        }
        try {
            vscode.window.showInformationMessage('Pedantic: Generating DSC configuration...');
            const response = await (0, pwshBridge_1.invokePwsh)({
                command: 'generate',
                dslPath,
                options: { timeout: 30000 }
            });
            if (response.success) {
                // Create a new document with the generated output
                const outputDoc = await vscode.workspace.openTextDocument({
                    content: response.output || '',
                    language: 'yaml'
                });
                await vscode.window.showTextDocument(outputDoc, vscode.ViewColumn.Beside);
                vscode.window.showInformationMessage('Pedantic: DSC configuration generated successfully');
            }
            else {
                const errors = response.errors?.join('\n') || 'Unknown error';
                vscode.window.showErrorMessage(`Pedantic: Generation failed:\n${errors}`);
            }
        }
        catch (err) {
            vscode.window.showErrorMessage(`Pedantic: Bridge error: ${err.message}`);
        }
        finally {
            // Clean up temp file
            if (tempFile && fs.existsSync(tempFile)) {
                fs.unlinkSync(tempFile);
            }
        }
    }));
    // Debounced graph refresh support
    let graphRefreshTimer;
    const scheduleGraphRefresh = () => {
        if (graphRefreshTimer)
            globalThis.clearTimeout(graphRefreshTimer);
        graphRefreshTimer = globalThis.setTimeout(async () => {
            const panel = resourceGraphPanel_1.ResourceGraphPanel.current();
            if (!panel)
                return;
            const editor = vscode.window.activeTextEditor;
            if (!editor)
                return;
            try {
                const parserMod = await Promise.resolve().then(() => __importStar(require('./dsl/simpleParser')));
                const doc = parserMod.parseSimple(editor.document.getText());
                panel.updateFromSimpleDocument(doc);
            }
            catch (e) {
                vscode.window.showErrorMessage('Graph auto-refresh failed: ' + e.message);
            }
        }, 200); // 200ms debounce
    };
    disposables.push(vscode.commands.registerCommand('pedantic.openGraph', async () => {
        const panel = resourceGraphPanel_1.ResourceGraphPanel.createOrShow(context);
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showInformationMessage('Open a DSL document to populate the graph.');
            return;
        }
        // Graph visualization allowed in untrusted workspaces (read-only parse). If policy changes, gate here.
        try {
            const parserMod = await Promise.resolve().then(() => __importStar(require('./dsl/simpleParser')));
            const doc = parserMod.parseSimple(editor.document.getText());
            panel.updateFromSimpleDocument(doc);
        }
        catch (e) {
            vscode.window.showErrorMessage('Graph parse failed: ' + e.message);
        }
    }));
    // Auto-refresh when active document changes
    disposables.push(vscode.workspace.onDidChangeTextDocument((e) => {
        if (!vscode.window.activeTextEditor)
            return;
        if (e.document === vscode.window.activeTextEditor.document && resourceGraphPanel_1.ResourceGraphPanel.current()) {
            scheduleGraphRefresh();
        }
    }));
    // Refresh on editor switch
    disposables.push(vscode.window.onDidChangeActiveTextEditor((ed) => {
        if (ed && resourceGraphPanel_1.ResourceGraphPanel.current()) {
            scheduleGraphRefresh();
        }
    }));
    disposables.push(vscode.commands.registerCommand('pedantic.openAiPanel', () => {
        if (aiPanel) {
            aiPanel.reveal();
            return;
        }
        aiPanel = vscode.window.createWebviewPanel('pedanticAi', 'Pedantic AI Assistant', vscode.ViewColumn.Beside, { enableScripts: true });
        aiPanel.onDidDispose(() => { aiPanel = undefined; }, null, context.subscriptions);
        aiPanel.webview.html = getBasicHtml('AI Assistant', `<p>AI panel placeholder. MCP integration forthcoming.</p>`);
    }));
    // Debug: parse active document (Simple DSL only for now) and show diagnostics
    disposables.push(vscode.commands.registerCommand('pedantic.debugParse', async () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor to parse.');
            return;
        }
        const text = editor.document.getText();
        let parserMod;
        try {
            parserMod = await Promise.resolve().then(() => __importStar(require('./dsl/simpleParser')));
        }
        catch (e) {
            vscode.window.showErrorMessage('Failed to load parser: ' + e.message);
            return;
        }
        const doc = parserMod.parseSimple(text);
        const ch = getOutputChannel();
        ch.clear();
        ch.appendLine('Pedantic Debug Parse Results');
        ch.appendLine('Dialect: simple');
        ch.appendLine('Blocks: ' + doc.blocks.length);
        for (const b of doc.blocks) {
            if (b.kind === 'InstallBlock') {
                ch.appendLine(` InstallBlock packages=${b.packages.length}`);
                for (const p of b.packages) {
                    ch.appendLine(`  - ${p.id}${p.version ? '@' + p.version : ''}${p.providerOverride ? ' via ' + p.providerOverride : ''}`);
                }
            }
        }
        if (doc.diagnostics?.length) {
            ch.appendLine('Diagnostics:');
            for (const d of doc.diagnostics) {
                ch.appendLine(` ${d.severity.toUpperCase()} ${d.code}: ${d.message}`);
            }
        }
        else {
            ch.appendLine('No diagnostics.');
        }
        ch.show(true);
    }));
    // ===== Dynamic Inventory View Commands =====
    // Initialize inventory tree provider
    inventoryTreeProvider = new inventoryTreeProvider_1.InventoryTreeProvider();
    const inventoryTreeView = vscode.window.createTreeView('pedanticInventory', {
        treeDataProvider: inventoryTreeProvider,
        showCollapseAll: true
    });
    disposables.push(inventoryTreeView);
    // Command: Refresh inventory
    disposables.push(vscode.commands.registerCommand('pedantic.refreshInventory', async () => {
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Pedantic: Gathering inventory...'
        }, async () => {
            const inventoryService = inventoryService_1.InventoryService.getInstance();
            const inventory = await inventoryService.gatherInventory();
            inventoryTreeProvider?.setInventory(inventory);
        });
    }));
    // Command: Show inventory detail
    disposables.push(vscode.commands.registerCommand('pedantic.showInventoryDetail', (item) => {
        const panel = inventoryDetailPanel_1.InventoryDetailPanel.createOrShow(context);
        panel.showItemDetails(item);
    }));
    // Command: Gather facts for host
    disposables.push(vscode.commands.registerCommand('pedantic.gatherHostFacts', async (item) => {
        if (!item || !item.data || !item.data.name) {
            vscode.window.showErrorMessage('Please select a host to gather facts');
            return;
        }
        const hostName = item.data.name;
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Pedantic: Gathering facts for ${hostName}...`
        }, async () => {
            const inventoryService = inventoryService_1.InventoryService.getInstance();
            const facts = await inventoryService.gatherHostFacts(hostName);
            // Update the host with new facts
            const panel = inventoryDetailPanel_1.InventoryDetailPanel.current();
            if (panel) {
                panel.addLog({
                    hostName,
                    timestamp: new Date(),
                    level: 'success',
                    message: 'Facts gathered successfully'
                });
            }
            vscode.window.showInformationMessage(`Facts gathered for ${hostName}`);
        });
    }));
    // Command: Push configuration to host
    disposables.push(vscode.commands.registerCommand('pedantic.pushConfigToHost', async (item) => {
        if (!item || !item.data || !item.data.name) {
            vscode.window.showErrorMessage('Please select a host to push configuration');
            return;
        }
        const hostName = item.data.name;
        // Ask user for config file
        const configFiles = await vscode.window.showOpenDialog({
            canSelectMany: false,
            filters: {
                'DSC Config': ['yaml', 'yml', 'dsc.yaml']
            }
        });
        if (!configFiles || configFiles.length === 0) {
            return;
        }
        const configPath = configFiles[0].fsPath;
        const panel = inventoryDetailPanel_1.InventoryDetailPanel.createOrShow(context);
        // The panel will handle the push internally
        panel.addLog({
            hostName,
            timestamp: new Date(),
            level: 'info',
            message: `Pushing configuration: ${path.basename(configPath)}`
        });
    }));
    // Auto-select item on tree selection change
    inventoryTreeView.onDidChangeSelection(e => {
        if (e.selection.length > 0) {
            vscode.commands.executeCommand('pedantic.showInventoryDetail', e.selection[0]);
        }
    });
    // Load initial inventory
    vscode.commands.executeCommand('pedantic.refreshInventory');
    context.subscriptions.push(...disposables);
}
function deactivate() {
    graphPanel = undefined;
    aiPanel = undefined;
    return (0, client_1.deactivateLanguageServer)();
}
function getBasicHtml(title, body) {
    const nonce = Math.random().toString(36).slice(2);
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${title}</title>
<style>body{font-family:var(--vscode-font-family,Segoe UI,Arial);padding:1rem;line-height:1.4;}h1{font-size:1.2rem;margin-top:0;}code{background:#0002;padding:2px 4px;border-radius:4px;}</style>
</head>
<body>
<h1>${title}</h1>
${body}
</body>
</html>`;
}
let _outputChannel;
function getOutputChannel() {
    if (!_outputChannel) {
        _outputChannel = vscode.window.createOutputChannel('Pedantic DSL');
    }
    return _outputChannel;
}
