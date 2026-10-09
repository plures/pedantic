import { describe, it } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { bridgeAssetRelativePath, resolveBridgeAsset, validateBridgeAsset, validatePwshExecutable } from '../src/bridge/assets';
import { BoundedOutput, redactDiagnostic } from '../src/bridge/output';
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

  it('rejects a non-absolute configured PowerShell executable', async () => {
    await assert.rejects(
      validatePwshExecutable('malicious-pwsh'),
      /must be "pwsh" or an absolute path/
    );
  });

  it('restricts the PowerShell executable setting to the local machine', () => {
    const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../package.json'), 'utf-8'));
    const setting = manifest.contributes.configuration.properties['pedantic.bridge.pwshPath'];

    assert.equal(setting.scope, 'machine');
    assert.deepEqual(
      manifest.capabilities.untrustedWorkspaces.restrictedConfigurations,
      ['pedantic.bridge.pwshPath']
    );
  });

  it('bounds captured output and redacts sensitive diagnostics', () => {
    const output = new BoundedOutput(16);
    output.append('this output is much larger than sixteen bytes');

    assert.equal(output.wasTruncated, true);
    assert.match(output.text, /output truncated/);
    assert.equal(redactDiagnostic('token=abc123 password: secret'), 'token=[REDACTED] password: [REDACTED]');
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
