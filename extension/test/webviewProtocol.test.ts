import * as assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import {
  isGraphPayload,
  isInventoryPayload,
  isReadyMessage,
  isRevealNodeMessage,
} from '../src/webviews/webviewProtocol';

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
});
