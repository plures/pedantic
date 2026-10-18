import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkSourceProvenance } from '../scripts/check-source-provenance.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'pedantic-provenance-'));
  t.after(() => rmSync(root, { recursive: true }));
  const git = (...args) => execFileSync('git', ['-C', root, ...args], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
  const write = (path, content) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), content);
  };
  git('init', '--quiet');
  git('config', 'core.autocrlf', 'false');
  const heldPath = 'DTMS Primitives Source/independent-fixture.psm1';
  write(heldPath, '# Independently authored test marker; not legacy source.\n');
  write('rust/src/lib.rs', 'pub fn fixture() {}\n');
  write('.gitattributes', '"DTMS Primitives Source" export-ignore\n"DTMS Primitives Source/**" export-ignore\n');
  const policy = {
    schemaVersion: 1, heldRoot: 'DTMS Primitives Source',
    disposition: 'hold', reuseApproved: false,
    files: [{ path: heldPath, gitBlob: git('hash-object', '--', heldPath).trim() }],
  };
  const savePolicy = () => write('source-provenance.json', JSON.stringify(policy));
  savePolicy();
  git('add', '--all');
  git('-c', 'user.name=Provenance Fixture', '-c', 'user.email=fixture@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', `core.hooksPath=${join(root, '.git', 'no-hooks')}`,
    'commit', '--quiet', '-m', 'test: independent provenance fixture');
  return { root, git, write, policy, savePolicy, heldPath };
}

test('checks repository inputs and its real archive without claiming runtime acceptance', (t) => {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const result = checkSourceProvenance(root);
  assert.equal(result.heldPaths, 3);
  assert.ok(result.nativeFilesChecked > 0);
  assert.equal(result.licenseClearance, false);
  assert.equal(result.runtimeAcceptance, false);
  const temporary = mkdtempSync(join(tmpdir(), 'pedantic-source-archive-'));
  t.after(() => rmSync(temporary, { recursive: true }));
  const archive = join(temporary, 'source.tar');
  execFileSync('git', ['-C', root, 'archive', '--worktree-attributes', '--format=tar',
    `--output=${archive}`, 'HEAD', '--', 'DTMS Primitives Source', 'rust/Cargo.toml']);
  const entries = execFileSync('tar', ['-tf', archive], { encoding: 'utf8' }).split(/\r?\n/u);
  assert.ok(entries.includes('rust/Cargo.toml'));
  assert.ok(!entries.some((path) => path.startsWith('DTMS Primitives Source')));
});

test('accepts unchanged held inputs and independently authored runtime source', (t) => {
  const { root } = fixture(t);
  assert.deepEqual(checkSourceProvenance(root), {
    event: 'source_provenance_checked', heldPaths: 1, nativeFilesChecked: 1,
    licenseClearance: false, runtimeAcceptance: false,
  });
});

for (const [name, change] of [
  ['unknown schema version', (p) => { p.schemaVersion = 2; }],
  ['implicit reuse approval', (p) => { p.reuseApproved = true; }],
  ['empty inventory', (p) => { p.files = []; }],
  ['duplicate path', (p) => { p.files.push(p.files[0]); }],
  ['path traversal', (p) => { p.files[0].path = `${p.heldRoot}/../outside`; }],
  ['invalid blob identity', (p) => { p.files[0].gitBlob = 'not-a-git-object'; }],
]) {
  test(`rejects ${name}`, (t) => {
    const f = fixture(t);
    change(f.policy);
    f.savePolicy();
    assert.throws(() => checkSourceProvenance(f.root), /Invalid/u);
  });
}

test('rejects changed held bytes even when the index is unchanged', (t) => {
  const f = fixture(t);
  f.write(f.heldPath, '# Changed independent fixture.\n');
  assert.throws(() => checkSourceProvenance(f.root), /Held source changed/u);
});

test('rejects a changed staged object even if the working file is restored', (t) => {
  const f = fixture(t);
  const original = readFileSync(join(f.root, f.heldPath));
  f.write(f.heldPath, '# Different index object.\n');
  f.git('add', '--', f.heldPath);
  f.write(f.heldPath, original);
  assert.throws(() => checkSourceProvenance(f.root), /Held source changed/u);
});

test('rejects additional ignored files in the held directory', (t) => {
  const f = fixture(t);
  f.write('.gitignore', '*.ignored\n');
  f.write('DTMS Primitives Source/additional.ignored', 'independent fixture');
  assert.throws(() => checkSourceProvenance(f.root), /inventory changed/u);
});

test('rejects removal of a held file', (t) => {
  const f = fixture(t);
  rmSync(join(f.root, f.heldPath));
  assert.throws(() => checkSourceProvenance(f.root), /ENOENT/u);
});

test('rejects held symlink entries without requiring host symlink privileges', (t) => {
  const f = fixture(t);
  f.git('update-index', '--cacheinfo', `120000,${f.policy.files[0].gitBlob},${f.heldPath}`);
  assert.throws(() => checkSourceProvenance(f.root), /Held source changed/u);
});

for (const attributes of [
  '',
  '"DTMS Primitives Source" export-ignore\n"DTMS Primitives Source/**" export-ignore\n'
    + '"DTMS Primitives Source/independent-fixture.psm1" -export-ignore\n',
]) {
  test(`rejects ${attributes ? 'a file-specific archive opt-out' : 'missing archive exclusions'}`, (t) => {
    const f = fixture(t);
    f.write('.gitattributes', attributes);
    assert.throws(() => checkSourceProvenance(f.root), /excluded from Git archives/u);
  });
}

for (const path of ['rust/src/extra.rs', 'extension/src/extra.ts', 'praxis/extra.px']) {
  test(`rejects a new runtime reference in ${path}`, (t) => {
    const f = fixture(t);
    f.write(path, 'include "..\\\\DTMS Primitives Source\\\\independent-fixture.psm1";\n');
    assert.throws(() => checkSourceProvenance(f.root), /references the held directory/u);
  });
}

test('rejects non-regular Git runtime inputs', (t) => {
  const f = fixture(t);
  const path = 'rust/src/lib.rs';
  const blob = f.git('hash-object', '--', path).trim();
  f.git('update-index', '--cacheinfo', `120000,${blob},${path}`);
  assert.throws(() => checkSourceProvenance(f.root), /Runtime inputs must be regular/u);
});

test('an actual committed Git archive excludes the held directory and retains native source', (t) => {
  const f = fixture(t);
  const archive = join(f.root, 'source.tar');
  f.git('archive', '--format=tar', `--output=${archive}`, 'HEAD');
  const entries = execFileSync('tar', ['-tf', archive], { encoding: 'utf8' }).split(/\r?\n/u);
  assert.ok(entries.includes('rust/src/lib.rs'));
  assert.ok(entries.includes('source-provenance.json'));
  assert.ok(!entries.some((path) => path.startsWith(f.policy.heldRoot)));
});

test('CLI failures have a nonzero exit and explicit structured diagnostic', (t) => {
  const f = fixture(t);
  mkdirSync(join(f.root, 'scripts'));
  const script = join(f.root, 'scripts', 'check-source-provenance.mjs');
  copyFileSync(new URL('../scripts/check-source-provenance.mjs', import.meta.url), script);
  f.policy.reuseApproved = true;
  f.savePolicy();
  const result = spawnSync(process.execPath, [script], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  const diagnostic = JSON.parse(result.stderr);
  assert.equal(diagnostic.event, 'source_provenance_check_failed');
  assert.match(diagnostic.error, /Invalid source provenance hold/u);
});
