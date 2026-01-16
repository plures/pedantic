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
exports.ResourceGraphPanel = void 0;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
class ResourceGraphPanel {
    static instance;
    panel;
    disposables = [];
    context;
    currentDocument;
    static createOrShow(context) {
        if (ResourceGraphPanel.instance) {
            ResourceGraphPanel.instance.panel.reveal();
            return ResourceGraphPanel.instance;
        }
        const panel = vscode.window.createWebviewPanel('pedanticGraph', 'Pedantic Resource Graph', vscode.ViewColumn.Beside, {
            enableScripts: true,
            retainContextWhenHidden: true,
            localResourceRoots: [
                vscode.Uri.file(path.join(context.extensionPath, 'node_modules', 'echarts', 'dist'))
            ]
        });
        ResourceGraphPanel.instance = new ResourceGraphPanel(panel, context);
        return ResourceGraphPanel.instance;
    }
    static current() {
        return ResourceGraphPanel.instance;
    }
    constructor(panel, context) {
        this.panel = panel;
        this.context = context;
        this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
        this.panel.webview.html = this.getHtml();
        // Handle messages from webview
        this.panel.webview.onDidReceiveMessage(async (msg) => {
            if (msg.command === 'revealNode') {
                await this.revealNodeInEditor(msg.nodeId);
            }
        }, null, this.disposables);
    }
    updateFromSimpleDocument(simpleDoc) {
        this.currentDocument = simpleDoc;
        // Extract packages as nodes with source location info
        const nodes = [];
        const edges = [];
        for (const block of simpleDoc.blocks || []) {
            if (block.kind === 'InstallBlock') {
                for (const p of block.packages) {
                    nodes.push({
                        id: p.id,
                        label: p.display || p.id,
                        type: 'package',
                        sourceLocation: p.sourceLocation
                    });
                }
            }
        }
        this.postMessage({
            command: 'graphData',
            nodes,
            edges,
            diagnostics: simpleDoc.diagnostics || []
        });
    }
    async revealNodeInEditor(nodeId) {
        const editor = vscode.window.activeTextEditor;
        if (!editor || !this.currentDocument) {
            return;
        }
        // Find the package with matching ID
        const pkg = this.findPackageById(nodeId);
        if (!pkg?.sourceLocation) {
            return;
        }
        const range = new vscode.Range(pkg.sourceLocation.start.line, pkg.sourceLocation.start.character, pkg.sourceLocation.end.line, pkg.sourceLocation.end.character);
        editor.selection = new vscode.Selection(range.start, range.end);
        editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
        await vscode.window.showTextDocument(editor.document);
    }
    findPackageById(nodeId) {
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
    postMessage(message) {
        try {
            this.panel.webview.postMessage(message);
        }
        catch { /* ignore */ }
    }
    getEChartsUri() {
        const echartsPath = path.join(this.context.extensionPath, 'node_modules', 'echarts', 'dist', 'echarts.min.js');
        // Cast to any to avoid type issues with older vscode type definitions
        return this.panel.webview.asWebviewUri(vscode.Uri.file(echartsPath));
    }
    getHtml() {
        const nonce = Math.random().toString(36).slice(2);
        const echartsUri = this.getEChartsUri();
        return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}' ${echartsUri}; img-src data:;">
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Pedantic Resource Graph</title>
<style>
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
            formatter: function(params) {
              if (params.dataType === 'node') {
                return params.data.name;
              }
              return '';
            }
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
      diagHost.innerHTML = '<h4>Diagnostics</h4>' + 
        (msg.diagnostics.length 
          ? msg.diagnostics.map(d => '<div class="diag ' + d.severity + '">' + d.severity.toUpperCase() + ' ' + d.code + ': ' + d.message + '</div>').join('') 
          : '<div>No diagnostics</div>');
    }
  });

  // Initialize on load
  if (typeof echarts !== 'undefined') {
    initChart();
  }
})();
</script>
</body>
</html>`;
    }
    dispose() {
        ResourceGraphPanel.instance = undefined;
        this.disposables.forEach(d => { try {
            d.dispose();
        }
        catch { /* noop */ } });
        this.disposables = [];
    }
}
exports.ResourceGraphPanel = ResourceGraphPanel;
