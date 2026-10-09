import { describe, it } from 'node:test';
import * as assert from 'node:assert/strict';
import * as path from 'node:path';
import { bridgeAssetRelativePath, resolveBridgeAsset, validateBridgeAsset } from '../src/bridge/assets';
import { bridgeProtocolVersion, parseBridgeResponse } from '../src/bridge/schema';

describe('PowerShell bridge assets', () => {
  it('resolves the bridge from the extension directory', () => {
    const extensionRoot = path.join(path.sep, 'installed', 'pedantic');
    const bridgePath = resolveBridgeAsset({
      extensionUri: { fsPath: extensionRoot },
      asAbsolutePath: relativePath => path.join(extensionRoot, relativePath)
    });

    assert.equal(bridgePath, path.join(extensionRoot, bridgeAssetRelativePath));
  });

  it('rejects bridge paths that escape the extension directory', () => {
    assert.throws(() => resolveBridgeAsset({
      extensionUri: { fsPath: path.join(path.sep, 'installed', 'pedantic') },
      asAbsolutePath: () => path.join(path.sep, 'other-extension', 'bridge.ps1')
    }), /outside the installed extension directory/);
  });

  it('reports a missing bridge asset with reinstall guidance', async () => {
    await assert.rejects(
      validateBridgeAsset(path.join(path.sep, 'missing', 'bridge.ps1')),
      /Reinstall the Pedantic extension/
    );
  });

  it('accepts only compatible bridge responses', () => {
    assert.deepEqual(
      parseBridgeResponse({ protocolVersion: bridgeProtocolVersion, success: true, errors: [] }),
      { protocolVersion: bridgeProtocolVersion, success: true, errors: [] }
    );
    assert.throws(
      () => parseBridgeResponse({ protocolVersion: 2, success: true }),
      /incompatible/
    );
  });
});
