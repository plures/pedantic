import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'fs/promises';
import * as path from 'path';
import { parseSimple } from '../src/dsl/simpleParser';
import { parseSudo } from '../src/dsl/sudoParser';

describe('Golden Test Corpus', () => {
  it('all fixtures parse without errors', async () => {
    // Use source directory fixtures, not dist-test
    const fixturesDir = path.join(__dirname, '../../test-fixtures');
    const files = await fs.readdir(fixturesDir);
    
    for (const file of files) {
      const content = await fs.readFile(path.join(fixturesDir, file), 'utf-8');
      const parsed = file.endsWith('.ssudo') 
        ? parseSudo(content).doc 
        : parseSimple(content);
      
      const errors = parsed.diagnostics?.filter((d: any) => d.severity === 'error') || [];
      assert.equal(errors.length, 0, `${file} should parse without errors, got: ${JSON.stringify(errors)}`);
    }
  });

  it('basic install fixture has expected structure', async () => {
    const fixturesDir = path.join(__dirname, '../../test-fixtures');
    const content = await fs.readFile(
      path.join(fixturesDir, '01-basic-install.simple.dsc.yaml'), 
      'utf-8'
    );
    const parsed = parseSimple(content);
    
    assert.equal(parsed.blocks.length, 1, 'Should have one block');
    assert.equal(parsed.blocks[0].kind, 'InstallBlock', 'Block should be InstallBlock');
    
    const installBlock = parsed.blocks[0] as any;
    assert.equal(installBlock.packages.length, 2, 'Should have 2 packages');
    assert.equal(installBlock.packages[0].id, 'git.git', 'First package should be git.git (canonicalized)');
    assert.equal(installBlock.packages[1].id, 'microsoft.visualstudiocode', 'Second package should be VSCode (canonicalized)');
  });

  it('version pinning fixture preserves versions', async () => {
    const fixturesDir = path.join(__dirname, '../../test-fixtures');
    const content = await fs.readFile(
      path.join(fixturesDir, '05-version-pinning.simple.dsc.yaml'), 
      'utf-8'
    );
    const parsed = parseSimple(content);
    
    const installBlock = parsed.blocks[0] as any;
    assert.equal(installBlock.packages[0].version, '2.43.0', 'Git version should be pinned');
    assert.equal(installBlock.packages[1].version, '3.12.1', 'Python version should be pinned');
  });

  it('provider override fixture preserves method', async () => {
    const fixturesDir = path.join(__dirname, '../../test-fixtures');
    const content = await fs.readFile(
      path.join(fixturesDir, '03-provider-override.simple.dsc.yaml'), 
      'utf-8'
    );
    const parsed = parseSimple(content);
    
    const installBlock = parsed.blocks[0] as any;
    assert.equal(installBlock.packages[0].providerOverride, 'winget', 'Git should use winget');
    assert.equal(installBlock.packages[1].providerOverride, 'chocolatey', 'Node.js should use chocolatey');
  });

  it('executable override fixture preserves executable and args', async () => {
    const fixturesDir = path.join(__dirname, '../../test-fixtures');
    const content = await fs.readFile(
      path.join(fixturesDir, '04-executable-override.simple.dsc.yaml'), 
      'utf-8'
    );
    const parsed = parseSimple(content);
    
    const installBlock = parsed.blocks[0] as any;
    const pkg = installBlock.packages[0];
    assert.ok(pkg.executableOverride, 'Should have executable override');
    assert.equal(pkg.executableOverride.path, 'C:\\custom\\installer.exe', 'Executable path should be preserved');
    assert.deepEqual(pkg.executableOverride.args, ['/silent', '/install'], 'Args should be preserved as array');
  });
});
