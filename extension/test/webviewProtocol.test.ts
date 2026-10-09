import * as assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import {
  isGraphPayload,
  isInventoryPayload,
  isReadyMessage,
  isRevealNodeMessage,
} from '../src/webviews/webviewProtocol';

interface MockDisposable {
  dispose(): void;
}

class MockWebview {
  cspSource = 'vscode-webview:';
  private messageListener: ((message: unknown) => void | Promise<void>) | undefined;
  private htmlValue = '';
  onHtmlAssigned: (() => void) | undefined;
  messages: unknown[] = [];
  postMessageBehavior: (message: unknown) => Promise<boolean> = async () => true;

  asWebviewUri(uri: unknown): unknown {
    return uri;
  }

  get html(): string {
    return this.htmlValue;
  }

  set html(value: string) {
    this.htmlValue = value;
    this.onHtmlAssigned?.();
  }

  onDidReceiveMessage(
    listener: (message: unknown) => void | Promise<void>,
    _thisArgs?: unknown,
    disposables?: MockDisposable[],
  ): MockDisposable {
    this.messageListener = listener;
    const disposable = {
      dispose: () => {
        if (this.messageListener === listener) {
          this.messageListener = undefined;
        }
      },
    };
    disposables?.push(disposable);
    return disposable;
  }

  async postMessage(message: unknown): Promise<boolean> {
    this.messages.push(message);
    return this.postMessageBehavior(message);
  }

  async send(message: unknown): Promise<void> {
    await this.messageListener?.(message);
  }
}

class MockPanel {
  webview = new MockWebview();
  private disposeListener: (() => void) | undefined;

  onDidDispose(listener: () => void, _thisArgs?: unknown, disposables?: MockDisposable[]): MockDisposable {
    this.disposeListener = listener;
    const disposable = {
      dispose: () => {
        if (this.disposeListener === listener) {
          this.disposeListener = undefined;
        }
      },
    };
    disposables?.push(disposable);
    return disposable;
  }

  reveal(): void {}

  dispose(): void {
    this.disposeListener?.();
  }
}

class MockPanelHarness {
  panel = new MockPanel();
  readonly webview = this.panel.webview;

  constructor(readyOnHtml = false) {
    if (readyOnHtml) {
      this.webview.onHtmlAssigned = () => {
        void this.webview.send({ command: 'ready' });
      };
    }
  }

  dispose(): void {
    this.panel.dispose();
  }
}

let activeHarness: MockPanelHarness | undefined;
const vscodeMock = {
  window: {
    createWebviewPanel: () => {
      if (!activeHarness) throw new Error('No active mock webview');
      return activeHarness.panel;
    },
    activeTextEditor: undefined,
  },
  Uri: { file: (fsPath: string) => ({ fsPath }) },
  ViewColumn: { Beside: 2 },
};
type ModuleLoader = (request: string, parent: unknown, isMain?: boolean) => unknown;
const moduleRequire = createRequire(__filename);
const moduleLoader = moduleRequire('node:module') as {
  _load: ModuleLoader;
};
const originalLoad = moduleLoader._load;
moduleLoader._load = function (request, parent, isMain) {
  if (request === 'vscode') return vscodeMock;
  return originalLoad(request, parent, isMain);
};
const { ResourceGraphPanel } = moduleRequire('../src/webviews/resourceGraphPanel') as typeof import('../src/webviews/resourceGraphPanel');
const { ResourceInventoryPanel } = moduleRequire('../src/webviews/resourceInventoryPanel') as typeof import('../src/webviews/resourceInventoryPanel');
moduleLoader._load = originalLoad;

interface PanelAdapter {
  name: string;
  create(): { update(marker: string): void };
  marker(message: any): string | undefined;
}

const panels: PanelAdapter[] = [
  {
    name: 'inventory',
    create: () => {
      const panel = ResourceInventoryPanel.createOrShow({ extensionPath: '/extension' } as never);
      return { update: marker => panel.update({ dscVersion: marker }) };
    },
    marker: message => message.data.dscVersion,
  },
  {
    name: 'graph',
    create: () => {
      const panel = ResourceGraphPanel.createOrShow({ extensionPath: '/extension' } as never);
      return {
        update: marker => panel.updateFromSimpleDocument({
          blocks: [],
          diagnostics: [{ code: marker, message: 'test', severity: 'warning' }],
        }),
      };
    },
    marker: message => message.diagnostics[0]?.code,
  },
];

async function settle(): Promise<void> {
  await new Promise<void>(resolve => setImmediate(resolve));
}

describe('webview protocol validation', () => {
  it('accepts hostile labels only as string data', () => {
    const hostile = '<img src=x onerror=alert(1)>';
    assert.equal(isInventoryPayload({
      command: 'inventoryData',
      data: { installed: [{ type: hostile, version: hostile, source: hostile }] },
    }), true);
    assert.equal(isGraphPayload({
      command: 'graphData',
      nodes: [{ id: 'node-1', label: hostile, type: 'package' }],
      edges: [],
      diagnostics: [{ code: hostile, message: hostile, severity: 'error' }],
    }), true);
  });

  it('rejects malformed and unknown webview messages', () => {
    assert.equal(isReadyMessage({ command: 'ready', unexpected: true }), false);
    assert.equal(isRevealNodeMessage({ command: 'revealNode', nodeId: 'node-1', extra: 'x' }), false);
    assert.equal(isRevealNodeMessage({ command: 'revealNode', nodeId: 1 }), false);
    assert.equal(isInventoryPayload({ command: 'inventoryData', data: { installed: [{ type: 'x', html: '<script>' }] } }), false);
    assert.equal(isGraphPayload({ command: 'graphData', nodes: [], edges: [], diagnostics: [], extra: true }), false);
  });

  it('keeps webview CSP, lifecycle, and rendering boundaries hardened', () => {
    for (const file of ['resourceInventoryPanel.ts', 'resourceGraphPanel.ts']) {
      const source = readFileSync(join(__dirname, '../../src/webviews', file), 'utf8');
      assert.equal(source.includes('innerHTML'), false, `${file} must not use HTML parsing for data`);
      assert.match(source, /webview\.cspSource/);
      assert.match(source, /randomBytes\(16\)/);
      assert.equal(source.includes('retainContextWhenHidden'), false);
      assert.match(source, /command: 'ready'/);
      assert.match(source, /localResourceRoots/);
      assert.match(source, /style-src 'nonce-\$\{nonce\}'/);
    }
    const graphSource = readFileSync(join(__dirname, '../../src/webviews/resourceGraphPanel.ts'), 'utf8');
    assert.match(graphSource, /renderMode: 'richText'/);
  });

  it('projects bridge-shaped inventory responses into the allowlisted payload', async () => {
    activeHarness = new MockPanelHarness();
    const panel = ResourceInventoryPanel.createOrShow({ extensionPath: '/extension' } as never);
    const bridgeResponse = {
      installed: [{
        Type: 'Microsoft.DSC/File',
        Version: '1.0.0',
        kind: 'resource',
        capabilities: ['get', 'set'],
      }],
      cached: [{
        Key: 'Microsoft.DSC/Archive',
        Type: 'Microsoft.DSC/Archive',
        Version: '2.0.0',
        Source: 'gallery',
        Path: '/cache/archive',
        extra: true,
      }],
      catalog: { BuiltInResources: [{ Type: 'Microsoft.DSC/File' }] },
    };

    assert.equal(isInventoryPayload({ command: 'inventoryData', data: bridgeResponse }), false);
    panel.update(bridgeResponse as never);
    await activeHarness.webview.send({ command: 'ready' });
    await settle();

    assert.equal(activeHarness.webview.messages.length, 1);
    const payload = activeHarness.webview.messages[0] as any;
    assert.equal(isInventoryPayload(payload), true);
    assert.equal(payload.data.catalog, undefined);
    assert.deepEqual(payload.data.installed, [{ Type: 'Microsoft.DSC/File', Version: '1.0.0' }]);
    assert.deepEqual(payload.data.cached, [{
      Key: 'Microsoft.DSC/Archive',
      Type: 'Microsoft.DSC/Archive',
      Version: '2.0.0',
      Source: 'gallery',
      Path: '/cache/archive',
    }]);
    activeHarness.dispose();
  });

  for (const panelKind of panels) {
    describe(`${panelKind.name} panel lifecycle`, () => {
      it('receives ready during startup and sends a subsequently queued payload', async () => {
        activeHarness = new MockPanelHarness(true);
        const panel = panelKind.create();
        panel.update('startup-ready');
        await settle();

        assert.equal(activeHarness.webview.messages.length, 1);
        assert.equal(panelKind.marker(activeHarness.webview.messages[0]), 'startup-ready');
        activeHarness.dispose();
      });

      it('replays only the latest payload after a slow startup', async () => {
        activeHarness = new MockPanelHarness();
        const panel = panelKind.create();
        panel.update('older');
        panel.update('latest');
        assert.equal(activeHarness.webview.messages.length, 0);

        await activeHarness.webview.send({ command: 'ready' });
        await settle();

        assert.equal(activeHarness.webview.messages.length, 1);
        assert.equal(panelKind.marker(activeHarness.webview.messages[0]), 'latest');
        activeHarness.dispose();
      });

      for (const failure of ['false', 'rejected']) {
        it(`retries the latest payload after a ${failure} postMessage result`, async () => {
          activeHarness = new MockPanelHarness();
          const panel = panelKind.create();
          activeHarness.webview.postMessageBehavior = failure === 'false'
            ? async () => false
            : async () => { throw new Error('postMessage failed'); };
          panel.update('first');
          await activeHarness.webview.send({ command: 'ready' });
          await settle();

          activeHarness.webview.postMessageBehavior = async () => true;
          panel.update('latest');
          assert.equal(activeHarness.webview.messages.length, 1);
          await activeHarness.webview.send({ command: 'ready' });
          await settle();

          assert.equal(activeHarness.webview.messages.length, 2);
          assert.equal(panelKind.marker(activeHarness.webview.messages[1]), 'latest');
          activeHarness.dispose();
        });
      }

      it('does not deliver or retain updates after disposal during an in-flight post', async () => {
        activeHarness = new MockPanelHarness();
        const panel = panelKind.create();
        let resolvePost!: (delivered: boolean) => void;
        activeHarness.webview.postMessageBehavior = () => new Promise(resolve => {
          resolvePost = resolve;
        });
        panel.update('in-flight');
        void activeHarness.webview.send({ command: 'ready' });
        assert.equal(activeHarness.webview.messages.length, 1);

        activeHarness.dispose();
        panel.update('after-dispose');
        resolvePost(true);
        await settle();

        assert.equal(activeHarness.webview.messages.length, 1);
      });
    });
  }
});
