import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import type { CmdbModel } from '../logic/cmdb-logic';

export class CmdbPanel {
  private static instance: CmdbPanel | undefined;
  private readonly panel: vscode.WebviewPanel;
  private readonly disposables: vscode.Disposable[] = [];
  private readonly context: vscode.ExtensionContext;

  static createOrShow(context: vscode.ExtensionContext): CmdbPanel {
    if (CmdbPanel.instance) {
      CmdbPanel.instance.panel.reveal();
      return CmdbPanel.instance;
    }

    const panel = vscode.window.createWebviewPanel(
      'pedanticCmdb',
      'Pedantic CMDB',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
      }
    );

    CmdbPanel.instance = new CmdbPanel(panel, context);
    return CmdbPanel.instance;
  }

  static current(): CmdbPanel | undefined {
    return CmdbPanel.instance;
  }

  private constructor(panel: vscode.WebviewPanel, context: vscode.ExtensionContext) {
    this.panel = panel;
    this.context = context;
    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    void this.setHtml();
  }

  update(data: CmdbModel) {
    try {
      this.panel.webview.postMessage({ command: 'cmdbData', data });
    } catch {
      /* ignore */
    }
  }

  dispose() {
    while (this.disposables.length) {
      const x = this.disposables.pop();
      if (x) {
        x.dispose();
      }
    }
    CmdbPanel.instance = undefined;
  }

  private resolveComponentPath(): string {
    const candidatePaths = [
      path.join(this.context.extensionPath, 'src', 'webviews', 'cmdb', 'CmdbApp.svelte'),
      path.join(this.context.extensionPath, 'webviews', 'cmdb', 'CmdbApp.svelte'),
      path.join(this.context.extensionPath, 'dist', 'webviews', 'cmdb', 'CmdbApp.svelte')
    ];

    for (const candidate of candidatePaths) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }

    return candidatePaths[0];
  }

  private async compileSvelteApp(): Promise<{ js: string; css: string }> {
    const componentPath = this.resolveComponentPath();
    const source = fs.readFileSync(componentPath, 'utf-8');

    const dynamicImport = new Function('specifier', 'return import(specifier)') as (specifier: string) => Promise<any>;
    const compiler = await dynamicImport('svelte/compiler');

    const result = compiler.compile(source, {
      generate: 'dom',
      format: 'iife',
      name: 'CmdbApp'
    });

    return {
      js: result.js?.code ?? '',
      css: result.css?.code ?? ''
    };
  }

  private async setHtml() {
    try {
      this.panel.webview.html = await this.getHtml();
    } catch (err: any) {
      const message = err?.message ?? 'Failed to render CMDB webview.';
      this.panel.webview.html = this.getFallbackHtml(message);
    }
  }

  private async getHtml(): Promise<string> {
    const nonce = Math.random().toString(36).slice(2);
    const compiled = await this.compileSvelteApp();

    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src data:;">
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Pedantic CMDB</title>
<style>${compiled.css}</style>
</head>
<body>
<div id="app"></div>
<script nonce="${nonce}">
${compiled.js}
new CmdbApp({ target: document.getElementById('app') });
</script>
</body>
</html>`;
  }

  private getFallbackHtml(message: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline';">
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Pedantic CMDB</title>
<style>body{font-family:var(--vscode-font-family,Segoe UI,Arial);padding:1rem;}code{background:#0002;padding:2px 4px;border-radius:4px;}</style>
</head>
<body>
<h2>Pedantic CMDB</h2>
<p>${message}</p>
<p>Ensure <code>svelte</code> is installed in the extension dependencies.</p>
</body>
</html>`;
  }
}
