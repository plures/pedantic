import * as vscode from 'vscode';
import { ResourceGraphPanel } from './webviews/resourceGraphPanel';

let graphPanel: vscode.WebviewPanel | undefined;
let aiPanel: vscode.WebviewPanel | undefined;

export function activate(context: vscode.ExtensionContext) {
  const disposables: vscode.Disposable[] = [];

  disposables.push(vscode.commands.registerCommand('statesmith.generateConfig', async () => {
    const workspaceIsTrusted = ((vscode.workspace as unknown) as { isTrusted?: boolean }).isTrusted ?? true;
    if (!workspaceIsTrusted) {
      vscode.window.showWarningMessage('StateSmith: Workspace is not trusted. Enable trust to generate DSC output.');
      return;
    }
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showWarningMessage('No active editor – open a DSL file to generate.');
      return;
    }
    const doc = editor.document;
    // Placeholder: future bridge invocation to PowerShell / engine
    vscode.window.showInformationMessage(`StateSmith: (stub) would generate DSC for ${doc.fileName}`);
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

  disposables.push(vscode.commands.registerCommand('statesmith.openGraph', async () => {
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

  disposables.push(vscode.commands.registerCommand('statesmith.openAiPanel', () => {
    if (aiPanel) {
      aiPanel.reveal();
      return;
    }
    aiPanel = vscode.window.createWebviewPanel(
      'statesmithAi',
      'StateSmith AI Assistant',
      vscode.ViewColumn.Beside,
      { enableScripts: true }
    );
    aiPanel.onDidDispose(() => { aiPanel = undefined; }, null, context.subscriptions);
    aiPanel.webview.html = getBasicHtml('AI Assistant', `<p>AI panel placeholder. MCP integration forthcoming.</p>`);
  }));

  // Debug: parse active document (Simple DSL only for now) and show diagnostics
  disposables.push(vscode.commands.registerCommand('statesmith.debugParse', async () => {
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
    ch.appendLine('StateSmith Debug Parse Results');
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

  context.subscriptions.push(...disposables);
}

export function deactivate() {
  graphPanel = undefined;
  aiPanel = undefined;
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
    _outputChannel = vscode.window.createOutputChannel('StateSmith DSL');
  }
  return _outputChannel;
}
