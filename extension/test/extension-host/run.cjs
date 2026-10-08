const { execFileSync } = require('node:child_process');
const { existsSync } = require('node:fs');
const { mkdtemp, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { downloadAndUnzipVSCode, runTests } = require('@vscode/test-electron');

async function main() {
  const vsixPath = path.resolve(process.argv[2] || 'pedantic-dsc.vsix');
  if (!existsSync(vsixPath)) {
    throw new Error(`VSIX not found: ${vsixPath}`);
  }

  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), 'pedantic-vsix-smoke-'));
  const userDataDirectory = path.join(tempDirectory, 'user-data');
  const extensionsDirectory = path.join(tempDirectory, 'extensions');

  try {
    const vscodeExecutablePath = await downloadAndUnzipVSCode({
      version: '1.90.0',
      cachePath: tempDirectory,
    });
    execFileSync(
      vscodeExecutablePath,
      [
        '--install-extension',
        vsixPath,
        '--force',
        '--user-data-dir',
        userDataDirectory,
        '--extensions-dir',
        extensionsDirectory,
      ],
      { stdio: 'inherit' },
    );

    await runTests({
      vscodeExecutablePath,
      extensionDevelopmentPath: path.join(__dirname, 'fixture'),
      extensionTestsPath: path.join(__dirname, 'smoke.test.cjs'),
      launchArgs: [
        '--user-data-dir',
        userDataDirectory,
        '--extensions-dir',
        extensionsDirectory,
        '--disable-workspace-trust',
      ],
    });
  } finally {
    await rm(tempDirectory, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
