import * as vscode from 'vscode';
import { ResourceGraphPanel } from './webviews/resourceGraphPanel';
import { ResourceInventoryPanel } from './webviews/resourceInventoryPanel';
import { activateLanguageServer, deactivateLanguageServer } from './client';
import { invokePwsh } from './bridge/pwshBridge';
import { InventoryTreeProvider } from './inventory/inventoryTreeProvider';
import { InventoryDetailPanel } from './inventory/inventoryDetailPanel';
import { InventoryService } from './inventory/inventoryService';
import * as fs from 'fs';
import * as path from 'path';

let graphPanel: vscode.WebviewPanel | undefined;
let aiPanel: vscode.WebviewPanel | undefined;
let inventoryTreeProvider: InventoryTreeProvider | undefined;

export function activate(context: vscode.ExtensionContext) {
  // Start the language server
  activateLanguageServer(context);

  const disposables: vscode.Disposable[] = [];
  const commonResources = [
    'Microsoft.DSC/Archive',
    'Microsoft.DSC/File',
    'Microsoft.DSC/Service',
    'Microsoft.Windows/Registry',
    'Microsoft.Windows/File',
    'Microsoft.Windows/Service'
  ];
  const defaultTimeoutMs = 60000;

  const installResource = async (resourceType: string) => {
    return vscode.window.withProgress({
      location: vscode.ProgressLocation.Notification,
      title: `Pedantic: Installing ${resourceType}`
    }, async () => {
      const response = await invokePwsh({
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
      return invokePwsh({
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
    const missing: string[] = data.commonResources?.missing || [];
    const dscInstalled: boolean = !!data.dscInstalled;
    const dscVersion: string | undefined = data.dscVersion;

    const message = `DSC ${dscInstalled ? 'found' : 'not found'}${dscVersion ? ' (' + dscVersion + ')' : ''}. ` +
      (missing.length ? `${missing.length} common resource(s) missing.` : 'Common resources available.');

    const actions: string[] = missing.length ? ['Install missing resources', 'Open resource inventory'] : ['Open resource inventory'];
    const selection = await vscode.window.showInformationMessage(message, ...actions);

    if (selection === 'Install missing resources') {
      for (const res of missing) {
        await installResource(res);
      }
    }

    if (selection === 'Open resource inventory') {
      const panel = ResourceInventoryPanel.createOrShow(context);
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
      return invokePwsh({
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

    const panel = ResourceInventoryPanel.createOrShow(context);
    panel.update(response.data || {});
  }));

  disposables.push(vscode.commands.registerCommand('pedantic.addResourceToProject', async () => {
    const response = await vscode.window.withProgress({
      location: vscode.ProgressLocation.Notification,
      title: 'Pedantic: Loading available resources'
    }, async () => {
      return invokePwsh({
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
    const installedTypes = new Set<string>();
    for (const r of data.installed || data.installedResources || []) {
      const t = r.type || r.Type;
      if (t) installedTypes.add(t);
    }

    const candidates = new Map<string, vscode.QuickPickItem>();
    const addCandidate = (type?: string, version?: string, source?: string, detail?: string) => {
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
    if (!pick) { return; }

    await installResource(pick.label);

    const panel = ResourceInventoryPanel.current();
    if (panel) {
      panel.update(response.data || {});
    }
  }));

  disposables.push(vscode.commands.registerCommand('pedantic.generateConfig', async () => {
    const workspaceIsTrusted = ((vscode.workspace as unknown) as { isTrusted?: boolean }).isTrusted ?? true;
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
    let tempFile: string | undefined;
    
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
      
      const response = await invokePwsh({
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
      } else {
        const errors = response.errors?.join('\n') || 'Unknown error';
        vscode.window.showErrorMessage(`Pedantic: Generation failed:\n${errors}`);
      }
    } catch (err: any) {
      vscode.window.showErrorMessage(`Pedantic: Bridge error: ${err.message}`);
    } finally {
      // Clean up temp file
      if (tempFile && fs.existsSync(tempFile)) {
        fs.unlinkSync(tempFile);
      }
    }
  }));

  // Debounced graph refresh support
  let graphRefreshTimer: any;
  const scheduleGraphRefresh = () => {
  if (graphRefreshTimer) (globalThis as any).clearTimeout(graphRefreshTimer);
  graphRefreshTimer = (globalThis as any).setTimeout(async () => {
      const panel = ResourceGraphPanel.current();
      if (!panel) return;
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      try {
        const parserMod: any = await import('./dsl/simpleParser');
        const doc = parserMod.parseSimple(editor.document.getText());
        panel.updateFromSimpleDocument(doc);
      } catch (e: any) {
        vscode.window.showErrorMessage('Graph auto-refresh failed: ' + e.message);
      }
    }, 200); // 200ms debounce
  };

  disposables.push(vscode.commands.registerCommand('pedantic.openGraph', async () => {
    const panel = ResourceGraphPanel.createOrShow(context);
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showInformationMessage('Open a DSL document to populate the graph.');
      return;
    }
    // Graph visualization allowed in untrusted workspaces (read-only parse). If policy changes, gate here.
    try {
      const parserMod: any = await import('./dsl/simpleParser');
      const doc = parserMod.parseSimple(editor.document.getText());
      panel.updateFromSimpleDocument(doc);
    } catch (e: any) {
      vscode.window.showErrorMessage('Graph parse failed: ' + e.message);
    }
  }));

  // Auto-refresh when active document changes
  disposables.push(vscode.workspace.onDidChangeTextDocument((e: vscode.TextDocumentChangeEvent) => {
    if (!vscode.window.activeTextEditor) return;
    if (e.document === vscode.window.activeTextEditor.document && ResourceGraphPanel.current()) {
      scheduleGraphRefresh();
    }
  }));

  // Refresh on editor switch
  disposables.push(vscode.window.onDidChangeActiveTextEditor((ed: vscode.TextEditor | undefined) => {
    if (ed && ResourceGraphPanel.current()) {
      scheduleGraphRefresh();
    }
  }));

  disposables.push(vscode.commands.registerCommand('pedantic.openAiPanel', () => {
    if (aiPanel) {
      aiPanel.reveal();
      return;
    }
    aiPanel = vscode.window.createWebviewPanel(
      'pedanticAi',
      'Pedantic AI Assistant',
      vscode.ViewColumn.Beside,
      { enableScripts: true }
    );
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
    let parserMod: any;
    try {
      parserMod = await import('./dsl/simpleParser');
    } catch (e: any) {
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
          ch.appendLine(`  - ${p.id}${p.version ? '@'+p.version : ''}${p.providerOverride ? ' via '+p.providerOverride : ''}`);
        }
      }
    }
    if (doc.diagnostics?.length) {
      ch.appendLine('Diagnostics:');
      for (const d of doc.diagnostics) {
        ch.appendLine(` ${d.severity.toUpperCase()} ${d.code}: ${d.message}`);
      }
    } else {
      ch.appendLine('No diagnostics.');
    }
    ch.show(true);
  }));

  // ===== Dynamic Inventory View Commands =====
  
  // Initialize inventory tree provider
  inventoryTreeProvider = new InventoryTreeProvider();
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
      const inventoryService = InventoryService.getInstance();
      const inventory = await inventoryService.gatherInventory();
      inventoryTreeProvider?.setInventory(inventory);
    });
  }));

  // Command: Show inventory detail
  disposables.push(vscode.commands.registerCommand('pedantic.showInventoryDetail', (item) => {
    const panel = InventoryDetailPanel.createOrShow(context);
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
      const inventoryService = InventoryService.getInstance();
      const facts = await inventoryService.gatherHostFacts(hostName);
      
      // Update the host with new facts in the current inventory
      const currentInventory = await inventoryService.gatherInventory();
      const host = currentInventory.hosts.find(h => h.name === hostName);
      if (host) {
        host.facts = facts;
        // Update the tree provider with refreshed inventory
        inventoryTreeProvider?.setInventory(currentInventory);
        
        // Show updated details if panel is open
        const panel = InventoryDetailPanel.current();
        if (panel) {
          panel.showItemDetails(item);
          panel.addLog({
            hostName,
            timestamp: new Date(),
            level: 'success',
            message: 'Facts gathered successfully'
          });
        }
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
    const panel = InventoryDetailPanel.createOrShow(context);
    
    // Start the push operation
    panel.startConfigPush(hostName, configPath);
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

export function deactivate() {
  graphPanel = undefined;
  aiPanel = undefined;
  return deactivateLanguageServer();
}

function getBasicHtml(title: string, body: string): string {
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

let _outputChannel: vscode.OutputChannel | undefined;
function getOutputChannel(): vscode.OutputChannel {
  if (!_outputChannel) {
    _outputChannel = vscode.window.createOutputChannel('Pedantic DSL');
  }
  return _outputChannel;
}
