import * as vscode from 'vscode';

interface GraphNode { id: string; label: string; type: string; }
interface GraphEdge { from: string; to: string; kind: string; }

export class ResourceGraphPanel {
  private static instance: ResourceGraphPanel | undefined;
  private panel: vscode.WebviewPanel;
  private disposables: vscode.Disposable[] = [];

  static createOrShow(context: vscode.ExtensionContext): ResourceGraphPanel {
    if (ResourceGraphPanel.instance) {
      ResourceGraphPanel.instance.panel.reveal();
      return ResourceGraphPanel.instance;
    }
    const panel = vscode.window.createWebviewPanel(
      'statesmithGraph',
      'StateSmith Resource Graph',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
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
    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    this.panel.webview.html = this.initialHtml();
  this.panel.webview.onDidReceiveMessage((msg: any) => {
      if (msg?.command === 'ready') {
        // Could trigger a refresh if needed.
      }
    });
  }

  updateFromSimpleDocument(simpleDoc: any) {
    // Extract packages as nodes. Future: infer edges for dependencies/providers.
    const nodes: GraphNode[] = [];
    const edges: GraphEdge[] = [];
    for (const block of simpleDoc.blocks || []) {
      if (block.kind === 'InstallBlock') {
        for (const p of block.packages) {
          nodes.push({ id: p.id, label: p.id + (p.version ? '@'+p.version : ''), type: 'package' });
        }
      }
    }
    this.postMessage({ command: 'graphData', nodes, edges, diagnostics: simpleDoc.diagnostics || [] });
  }

  private postMessage(message: any) {
    try { this.panel.webview.postMessage(message); } catch { /* ignore */ }
  }

  private initialHtml(): string {
    const nonce = Math.random().toString(36).slice(2);
    // Note: ECharts not yet bundled; placeholder canvas + JSON view. Later we'll vendor ECharts locally (no remote src per marketplace rules).
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src data:;">
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>StateSmith Resource Graph</title>
<style>
body { font-family: var(--vscode-font-family, Segoe UI, Arial, sans-serif); margin: 0; padding: 0.75rem; }
#graph { border: 1px solid var(--vscode-editorWidget-border,#555); height: 320px; position: relative; overflow: auto; background: var(--vscode-editor-background,#1e1e1e); }
.node { position: absolute; padding: 4px 8px; background: var(--vscode-button-secondaryBackground,#444); color: var(--vscode-button-foreground,#fff); border-radius: 6px; font-size: 12px; white-space: nowrap; }
#json { font-size: 11px; margin-top: .75rem; line-height: 1.3; }
.badge { display:inline-block; padding:2px 6px; border-radius:4px; background:#444; font-size:10px; margin-left:4px; }
.diag { margin:2px 0; }
.diag.ERROR { color: #ff6b6b; }
.diag.WARN { color: #ffb347; }
</style>
</head>
<body>
<h2 style="margin-top:0;">Resource Graph <span id="counts"></span></h2>
<div id="graph" aria-label="Resource Graph Visualization"></div>
<details open><summary>Raw Data & Diagnostics</summary>
<pre id="json"></pre>
<div id="diagnostics"></div>
</details>
<script nonce="${nonce}">
(function(){
  const vscode = acquireVsCodeApi();
  vscode.postMessage({command:'ready'});
  function layout(nodes){
    // Simple radial layout placeholder
    const cx = 600/2, cy = 300/2; const r = Math.min(cx,cy)-30; const n = nodes.length;
    return nodes.map((n,i)=>{ const angle = (i / Math.max(1,n)) * Math.PI*2; return { id:n.id, label:n.label, x: cx + r*Math.cos(angle), y: cy + r*Math.sin(angle) }; });
  }
  window.addEventListener('message', e => {
    const msg = e.data; if (!msg) return;
    if (msg.command === 'graphData') {
      const graphEl = document.getElementById('graph');
      graphEl.innerHTML='';
      const laidOut = layout(msg.nodes);
      for (const node of laidOut) {
        const div = document.createElement('div');
        div.className='node';
        div.style.left = (node.x)+'px';
        div.style.top = (node.y)+'px';
        div.textContent = node.label;
        graphEl.appendChild(div);
      }
  document.getElementById('counts').textContent = '(' + msg.nodes.length + ' pkg)';
  document.getElementById('json').textContent = JSON.stringify({nodes:msg.nodes, edges:msg.edges}, null, 2);
  const diagHost = document.getElementById('diagnostics');
  diagHost.innerHTML = '<h4>Diagnostics</h4>' + (msg.diagnostics.length ? msg.diagnostics.map(d=>'<div class="diag '+d.severity+'">'+d.severity+' '+d.code+': '+d.message+'</div>').join('') : '<div>None</div>');
    }
  });
})();
</script>
</body>
</html>`;
  }

  private dispose() {
    ResourceGraphPanel.instance = undefined;
    this.disposables.forEach(d => { try { d.dispose(); } catch { /* noop */ } });
    this.disposables = [];
  }
}
