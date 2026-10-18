const { existsSync } = require('node:fs');
const { copyFile, mkdtemp, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { downloadAndUnzipVSCode, runTests, runVSCodeCommand } = require('@vscode/test-electron');

async function main() {
  const vsixPath = path.resolve(process.argv[2] || 'pedantic-dsc.vsix');
  if (!existsSync(vsixPath)) {
    throw new Error(`VSIX not found: ${vsixPath}`);
  }

  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), 'pedantic-vsix-smoke-'));
  const userDataDirectory = path.join(tempDirectory, 'user-data');
  const extensionsDirectory = path.join(tempDirectory, 'extensions');
  let testError;

  try {
    const vscodeExecutablePath = await downloadAndUnzipVSCode({
      version: '1.90.0',
      cachePath: tempDirectory,
    });
    await copyFile(vsixPath, path.join(tempDirectory, 'candidate.vsix'));
    await runVSCodeCommand(
      [
        '--install-extension',
        'candidate.vsix',
        '--force',
        '--no-sandbox',
        '--user-data-dir',
        'user-data',
        '--extensions-dir',
        'extensions',
      ],
      {
        version: '1.90.0',
        cachePath: tempDirectory,
        spawn: { cwd: tempDirectory, stdio: 'inherit', timeout: 60000 },
      },
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
        '--no-sandbox',
      ],
    });
  } catch (error) {
    testError = error;
    throw error;
  } finally {
    try {
      await rm(tempDirectory, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
    } catch (cleanupError) {
      if (testError !== undefined) {
        throw new AggregateError([testError, cleanupError], 'VSIX smoke test and cleanup both failed');
      }
      throw cleanupError;
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
