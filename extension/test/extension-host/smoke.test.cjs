const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vscode = require('vscode');

async function run() {
  const extension = vscode.extensions.getExtension('pedantic.pedantic-dsc');
  assert.ok(extension, 'The packaged Pedantic extension should be installed');

  await extension.activate();
  assert.ok(
    fs.existsSync(path.join(extension.extensionPath, 'dist/server/server.js')),
    'The packaged language server should be present',
  );

  const commands = await vscode.commands.getCommands(true);
  assert.ok(commands.includes('pedantic.generateConfig'), 'Pedantic commands should be registered');
}

module.exports = { run };
