import * as vscode from 'vscode';
import * as path from 'path';
import { randomBytes } from 'crypto';
import { InventoryPayload, isInventoryPayload, isReadyMessage } from './webviewProtocol';

export interface ResourceInventoryData {
  dscInstalled?: boolean;
  dscVersion?: string;
  commonResources?: {
    requested: string[];
    available?: string[];
    missing?: string[];
    success?: boolean;
  };
  installed?: any[];
  cached?: any[];
  catalog?: any;
}

export class ResourceInventoryPanel {
  private static instance: ResourceInventoryPanel | undefined;
  private readonly panel: vscode.WebviewPanel;
  private readonly disposables: vscode.Disposable[] = [];
  private readonly context: vscode.ExtensionContext;
  private latestPayload: InventoryPayload | undefined;
  private ready = false;
  private disposed = false;

  static createOrShow(context: vscode.ExtensionContext): ResourceInventoryPanel {
    if (ResourceInventoryPanel.instance) {
      ResourceInventoryPanel.instance.panel.reveal();
      return ResourceInventoryPanel.instance;
    }

    const panel = vscode.window.createWebviewPanel(
      'pedanticResourceInventory',
      'Pedantic Resource Inventory',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        localResourceRoots: [
          vscode.Uri.file(path.join(context.extensionPath, 'dist', 'vendor'))
        ]
      }
    );

    ResourceInventoryPanel.instance = new ResourceInventoryPanel(panel, context);
    return ResourceInventoryPanel.instance;
  }

  static current(): ResourceInventoryPanel | undefined {
    return ResourceInventoryPanel.instance;
  }

  private constructor(panel: vscode.WebviewPanel, context: vscode.ExtensionContext) {
    this.panel = panel;
    this.context = context;
    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    this.panel.webview.onDidReceiveMessage(
      message => {
        if (isReadyMessage(message)) {
          this.ready = true;
          void this.flushLatestPayload();
        }
      },
      undefined,
      this.disposables,
    );
    this.panel.webview.html = this.getHtml();
  }

  update(data: ResourceInventoryData): void {
    const payload: unknown = { command: 'inventoryData', data };
    if (!isInventoryPayload(payload) || this.disposed) {
      return;
    }
    this.latestPayload = payload;
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

  dispose() {
    this.disposed = true;
    this.latestPayload = undefined;
    while (this.disposables.length) {
      const x = this.disposables.pop();
      if (x) {
        x.dispose();
      }
    }
    ResourceInventoryPanel.instance = undefined;
  }

  private getEChartsUri(): vscode.Uri {
    const echartsPath = path.join(
      this.context.extensionPath,
      'dist',
      'vendor',
      'echarts.min.js'
    );
    return (this.panel.webview as any).asWebviewUri(vscode.Uri.file(echartsPath));
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
<title>Pedantic Resource Inventory</title>
<style nonce="${nonce}">
body { font-family: var(--vscode-font-family, Segoe UI, Arial, sans-serif); margin: 0; padding: 0.75rem; }
.summary { margin-bottom: 0.5rem; }
.card { border: 1px solid var(--vscode-editorWidget-border,#555); padding: 0.75rem; border-radius: 6px; margin-top: 0.75rem; background: var(--vscode-editor-background,#1e1e1e); }
.badge { display:inline-block; padding:2px 6px; border-radius:4px; background:#444; font-size:10px; margin-left:4px; }
.table { width: 100%; border-collapse: collapse; font-size: 12px; }
.table th, .table td { border-bottom: 1px solid var(--vscode-editorWidget-border,#444); padding: 4px 6px; text-align: left; }
.missing { color: #ff6b6b; }
.ok { color: #74c69d; }
#chart { height: 260px; width: 100%; }
small { color: var(--vscode-descriptionForeground,#999); }
</style>
</head>
<body>
<h2 style="margin-top:0;">DSC Resource Inventory</h2>
<div class="summary" id="summary">Loading…</div>
<div id="chart"></div>
<div class="card">
  <h4 style="margin:0 0 4px 0;">Common Resources</h4>
  <div id="common"></div>
</div>
<div class="card">
  <h4 style="margin:0 0 4px 0;">Installed Resources</h4>
  <div id="installed"></div>
</div>
<div class="card">
  <h4 style="margin:0 0 4px 0;">Cached/Available Resources</h4>
  <div id="cached"></div>
</div>
<script nonce="${nonce}" src="${echartsUri}"></script>
<script nonce="${nonce}">
(function(){
  const vscode = acquireVsCodeApi();
  let chart;

  function initChart(){
    if (!chart && typeof echarts !== 'undefined') {
      chart = echarts.init(document.getElementById('chart'));
    }
  }

  function replaceChildren(host, ...children) {
    host.replaceChildren(...children);
  }

  function textElement(tag, text, className) {
    const element = document.createElement(tag);
    element.textContent = String(text);
    if (className) element.className = className;
    return element;
  }

  function renderTable(targetId, rows, emptyText){
    const host = document.getElementById(targetId);
    if (!rows || rows.length === 0) {
      replaceChildren(host, textElement('small', emptyText));
      return;
    }
    const table = document.createElement('table');
    table.className = 'table';
    const header = document.createElement('tr');
    for (const label of ['Type', 'Version', 'Source']) header.appendChild(textElement('th', label));
    table.appendChild(header);
    for (const row of rows) {
      const tableRow = document.createElement('tr');
      for (const value of [row.type || row.Type || row.name || '', row.version || row.Version || '', row.source || row.Source || '']) {
        tableRow.appendChild(textElement('td', value));
      }
      table.appendChild(tableRow);
    }
    replaceChildren(host, table);
  }

  function render(data){
    initChart();
    const installed = data.installed || [];
    const cached = data.cached || [];
    const missing = (data.commonResources && data.commonResources.missing) || [];
    const availableCommon = (data.commonResources && data.commonResources.available) || [];

    const summary = document.getElementById('summary');
    const dsc = document.createElement('div');
    dsc.append(textElement('strong', 'DSC:'), document.createTextNode(' ' + (data.dscInstalled ? 'Detected' : 'Not detected')));
    if (data.dscVersion) dsc.appendChild(textElement('span', data.dscVersion, 'badge'));
    replaceChildren(
      summary,
      dsc,
      textElement('div', 'Installed: ' + installed.length + '   Cached: ' + cached.length),
      textElement('div', 'Common resources: ' + availableCommon.length + ' available, ' + missing.length + ' missing'),
    );

    if (chart) {
      chart.setOption({
        backgroundColor: 'transparent',
        tooltip: { trigger: 'item' },
        xAxis: { type: 'category', data: ['Installed', 'Cached', 'Missing common'] },
        yAxis: { type: 'value' },
        series: [{
          type: 'bar',
          data: [installed.length, cached.length, missing.length],
          itemStyle: { color: '#0078d4' }
        }]
      });
    }

    const commonRows = [];
    const requested = (data.commonResources && data.commonResources.requested) || [];
    for (const res of requested) {
      const ok = availableCommon && availableCommon.indexOf(res) >= 0 && (!missing || missing.indexOf(res) < 0);
      commonRows.push({ type: res, version: ok ? 'ready' : 'missing', source: ok ? 'cached/installed' : 'not found', ok });
    }
    const commonHost = document.getElementById('common');
    if (commonRows.length === 0) {
      replaceChildren(commonHost, textElement('small', 'No common resources specified.'));
    } else {
      const fragment = document.createDocumentFragment();
      for (const row of commonRows) {
        const item = document.createElement('div');
        item.className = row.ok ? 'ok' : 'missing';
        item.append(document.createTextNode(row.type + ' '), textElement('span', row.version, 'badge'));
        fragment.appendChild(item);
      }
      replaceChildren(commonHost, fragment);
    }

    renderTable('installed', installed.map(r => ({ type: r.type || r.Type, version: r.version || r.Version, source: r.source || r.Source || 'local' })), 'No installed resources reported.');
    renderTable('cached', cached.map(r => ({ type: r.Type || r.type || r.Key, version: r.Version || r.version, source: r.Source || r.source, path: r.Path || r.path })), 'No cached resources found.');
  }

  window.addEventListener('message', e => {
    const msg = e.data;
    if (!msg || Object.getPrototypeOf(msg) !== Object.prototype || Object.keys(msg).length !== 2 ||
      msg.command !== 'inventoryData' || !msg.data || Object.getPrototypeOf(msg.data) !== Object.prototype) return;
    if (msg.command === 'inventoryData') {
      render(msg.data);
    }
  });
  vscode.postMessage({ command: 'ready' });
})();
</script>
</body>
</html>`;
  }
}
