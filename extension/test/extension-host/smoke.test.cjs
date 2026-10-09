const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vscode = require('vscode');

async function run() {
  const extension = vscode.extensions.getExtension('pedantic.pedantic-dsc');
  assert.ok(extension, 'The packaged Pedantic extension should be installed');

  await extension.activate();
  assert.ok(
    fs.existsSync(path.join(extension.extensionPath, 'dist/server/server.js')),
    'The packaged language server should be present',
  );
  const bridgePath = path.join(extension.extensionPath, 'bridge', 'bridge.ps1');
  assert.ok(fs.existsSync(bridgePath), 'The packaged PowerShell bridge should be present');

  const bridgeResponse = runBridge(bridgePath, ['-Command', 'version']);
  assert.equal(bridgeResponse.protocolVersion, 1, 'The bridge protocol should be compatible');
  assert.equal(bridgeResponse.success, true, 'The bridge version command should succeed');
  const dslPath = path.join(os.tmpdir(), `pedantic-smoke-${process.pid}.dsl`);
  fs.writeFileSync(dslPath, 'configuration smoke {}', 'utf8');
  try {
    const generateResponse = runBridge(bridgePath, ['-Command', 'generate', '-DslPath', dslPath]);
    assert.equal(generateResponse.success, false, 'Unsupported generation must not report success');
    assert.match(generateResponse.errors.join('\n'), /not supported by the packaged bridge/i);
  } finally {
    fs.rmSync(dslPath, { force: true });
  }

  const incompatibleBridge = spawnSync(
    'pwsh',
    ['-NoProfile', '-NonInteractive', '-File', bridgePath, '-Command', 'version', '-ProtocolVersion', '2', '-OutputJson'],
    { encoding: 'utf8' },
  );
  assert.notEqual(incompatibleBridge.status, 0, 'An incompatible bridge protocol should fail');

  const commands = await vscode.commands.getCommands(true);
  assert.ok(commands.includes('pedantic.generateConfig'), 'Pedantic commands should be registered');
}

function runBridge(bridgePath, commandArgs) {
  const stdout = execFileSync(
    'pwsh',
    ['-NoProfile', '-NonInteractive', '-File', bridgePath, ...commandArgs, '-ProtocolVersion', '1', '-OutputJson'],
    { encoding: 'utf8' },
  );
  const responseLine = stdout.trimEnd().split(/\r?\n/).filter(Boolean).at(-1);
  assert.ok(responseLine, 'The bridge should emit a JSON response');
  return JSON.parse(responseLine);
}

module.exports = { run };
