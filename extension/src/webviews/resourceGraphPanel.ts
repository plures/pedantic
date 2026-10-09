import * as vscode from 'vscode';
import * as path from 'path';
import { randomBytes } from 'crypto';
import { GraphPayload, isGraphPayload, isReadyMessage, isRevealNodeMessage } from './webviewProtocol';

interface GraphNode { id: string; label: string; type: string; sourceLocation?: any; }
interface GraphEdge { from: string; to: string; kind: string; }

export class ResourceGraphPanel {
  private static instance: ResourceGraphPanel | undefined;
  private panel: vscode.WebviewPanel;
  private disposables: vscode.Disposable[] = [];
  private context: vscode.ExtensionContext;
  private currentDocument: any;
  private latestPayload: GraphPayload | undefined;
  private ready = false;
  private disposed = false;

  static createOrShow(context: vscode.ExtensionContext): ResourceGraphPanel {
    if (ResourceGraphPanel.instance) {
      ResourceGraphPanel.instance.panel.reveal();
      return ResourceGraphPanel.instance;
    }
    const panel = vscode.window.createWebviewPanel(
      'pedanticGraph',
      'Pedantic Resource Graph',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        localResourceRoots: [
          vscode.Uri.file(path.join(context.extensionPath, 'dist', 'vendor'))
        ]
      }
    );
    ResourceGraphPanel.instance = new ResourceGraphPanel(panel, context);
    return ResourceGraphPanel.instance;
  }

  static current(): ResourceGraphPanel | undefined {
    return ResourceGraphPanel.instance;
  }

  private constructor(panel: vscode.WebviewPanel, context: vscode.ExtensionContext) {
    this.panel = panel;
    this.context = context;
    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    this.panel.webview.html = this.getHtml();
    
    this.panel.webview.onDidReceiveMessage(
      async (msg: unknown) => {
        if (isReadyMessage(msg)) {
          this.ready = true;
          await this.flushLatestPayload();
        } else if (isRevealNodeMessage(msg)) {
          await this.revealNodeInEditor(msg.nodeId);
        }
      },
      null,
      this.disposables
    );
  }

  updateFromSimpleDocument(simpleDoc: any) {
    this.currentDocument = simpleDoc;
    
    // Extract packages as nodes with source location info
    const nodes: GraphNode[] = [];
    const edges: GraphEdge[] = [];
    const diagnostics: GraphPayload['diagnostics'] = Array.isArray(simpleDoc.diagnostics)
      ? (simpleDoc.diagnostics as unknown[])
        .filter((diagnostic: unknown): diagnostic is { code: string; message: string; severity: string } =>
          diagnostic !== null && typeof diagnostic === 'object'
          && typeof (diagnostic as { code?: unknown }).code === 'string'
          && typeof (diagnostic as { message?: unknown }).message === 'string'
          && typeof (diagnostic as { severity?: unknown }).severity === 'string')
        .map(({ code, message, severity }) => ({ code, message, severity }))
      : [];
    
    for (const block of simpleDoc.blocks || []) {
      if (block.kind === 'InstallBlock') {
        for (const p of block.packages) {
          nodes.push({ 
            id: p.id, 
            label: p.display || p.id,
            type: 'package'
          });
        }
      }
    }
    
    this.postMessage({
      command: 'graphData', 
      nodes, 
      edges, 
      diagnostics
    });
  }

  private async revealNodeInEditor(nodeId: string) {
    const editor = vscode.window.activeTextEditor;
    if (!editor || !this.currentDocument) {
      return;
    }

    // Find the package with matching ID
    const pkg = this.findPackageById(nodeId);
    if (!pkg?.sourceLocation) {
      return;
    }

    const range = new vscode.Range(
      pkg.sourceLocation.start.line,
      pkg.sourceLocation.start.character,
      pkg.sourceLocation.end.line,
      pkg.sourceLocation.end.character
    );

    editor.selection = new vscode.Selection(range.start, range.end);
    editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
    await vscode.window.showTextDocument(editor.document);
  }

  private findPackageById(nodeId: string): any {
    if (!this.currentDocument) {
      return null;
    }

    for (const block of this.currentDocument.blocks || []) {
      if (block.kind === 'InstallBlock') {
        for (const p of block.packages) {
          if (p.id === nodeId) {
            return p;
          }
        }
      }
    }
    return null;
  }

  private postMessage(message: unknown): void {
    if (!isGraphPayload(message) || this.disposed) {
      return;
    }
    this.latestPayload = message;
    if (this.ready) {
      void this.flushLatestPayload();
    }
  }

  private async flushLatestPayload(): Promise<void> {
    if (!this.ready || this.disposed || !this.latestPayload) {
      return;
    }
    try {
      const delivered = await this.panel.webview.postMessage(this.latestPayload);
      if (!delivered) this.ready = false;
    } catch {
      // Retain the newest payload for the next ready notification.
    }
  }

  private getEChartsUri(): vscode.Uri {
    const echartsPath = path.join(
      this.context.extensionPath,
      'dist',
      'vendor',
      'echarts.min.js'
    );
    const fileUri = vscode.Uri.file(echartsPath);
    
    // Use type guard to check if asWebviewUri exists
    if ('asWebviewUri' in this.panel.webview && typeof this.panel.webview.asWebviewUri === 'function') {
      return this.panel.webview.asWebviewUri(fileUri);
    }
    
    // Fallback for older VS Code versions
    return fileUri;
  }

  private getHtml(): string {
    const nonce = randomBytes(16).toString('base64');
    const echartsUri = this.getEChartsUri();
    const cspSource = this.panel.webview.cspSource;
    
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}' ${cspSource};">
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Pedantic Resource Graph</title>
<style nonce="${nonce}">
body { font-family: var(--vscode-font-family, Segoe UI, Arial, sans-serif); margin: 0; padding: 0.75rem; }
#graph { border: 1px solid var(--vscode-editorWidget-border,#555); height: 500px; width: 100%; background: var(--vscode-editor-background,#1e1e1e); }
#json { font-size: 11px; margin-top: .75rem; line-height: 1.3; }
.badge { display:inline-block; padding:2px 6px; border-radius:4px; background:#444; font-size:10px; margin-left:4px; }
.diag { margin:2px 0; }
.diag.error { color: #ff6b6b; }
.diag.warning { color: #ffb347; }
</style>
</head>
<body>
<h2 style="margin-top:0;">Resource Graph <span id="counts"></span></h2>
<div id="graph" aria-label="Resource Graph Visualization"></div>
<details open><summary>Raw Data & Diagnostics</summary>
<pre id="json"></pre>
<div id="diagnostics"></div>
</details>
<script nonce="${nonce}" src="${echartsUri}"></script>
<script nonce="${nonce}">
(function(){
  const vscode = acquireVsCodeApi();
  let chart = null;

  function initChart() {
    const graphEl = document.getElementById('graph');
    if (!chart && typeof echarts !== 'undefined') {
      chart = echarts.init(graphEl);
      
      // Handle click events
      chart.on('click', function(params) {
        if (params.dataType === 'node') {
          vscode.postMessage({ 
            command: 'revealNode', 
            nodeId: params.data.id 
          });
        }
      });
    }
  }

  window.addEventListener('message', e => {
    const msg = e.data;
    if (!msg) return;
    
    if (msg.command === 'graphData') {
      initChart();
      
      if (chart) {
        const option = {
          backgroundColor: 'transparent',
          tooltip: {
            trigger: 'item',
            renderMode: 'richText'
          },
          series: [{
            type: 'graph',
            layout: 'force',
            data: msg.nodes.map(n => ({
              id: n.id,
              name: n.label,
              symbolSize: 50,
              category: n.type,
              itemStyle: {
                color: '#0078d4'
              }
            })),
            links: msg.edges.map(e => ({
              source: e.from,
              target: e.to,
              label: { show: true, formatter: e.kind }
            })),
            categories: [{ name: 'package' }],
            roam: true,
            label: {
              show: true,
              position: 'right',
              color: '#ffffff'
            },
            force: {
              repulsion: 200,
              edgeLength: 150,
              gravity: 0.1
            },
            emphasis: {
              focus: 'adjacency',
              label: {
                fontSize: 14
              }
            }
          }]
        };
        
        chart.setOption(option);
      }
      
      document.getElementById('counts').textContent = '(' + msg.nodes.length + ' packages)';
      document.getElementById('json').textContent = JSON.stringify({nodes: msg.nodes, edges: msg.edges}, null, 2);
      
      const diagHost = document.getElementById('diagnostics');
      const heading = document.createElement('h4');
      heading.textContent = 'Diagnostics';
      const content = document.createElement('div');
      if (msg.diagnostics.length) {
        for (const diagnostic of msg.diagnostics) {
          const item = document.createElement('div');
          item.className = 'diag';
          if (diagnostic.severity === 'error' || diagnostic.severity === 'warning') {
            item.classList.add(diagnostic.severity);
          }
          item.textContent = diagnostic.severity.toUpperCase() + ' ' + diagnostic.code + ': ' + diagnostic.message;
          content.appendChild(item);
        }
      } else {
        content.textContent = 'No diagnostics';
      }
      diagHost.replaceChildren(heading, content);
    }
  });

  // Initialize on load
  if (typeof echarts !== 'undefined') {
    initChart();
  }
  vscode.postMessage({ command: 'ready' });
})();
</script>
</body>
</html>`;
  }

  private dispose() {
    this.disposed = true;
    this.latestPayload = undefined;
    ResourceGraphPanel.instance = undefined;
    this.disposables.forEach(d => { try { d.dispose(); } catch { /* noop */ } });
    this.disposables = [];
  }
}
