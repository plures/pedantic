import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const runtimeRoots = ['rust/', 'praxis/', 'extension/', 'plugin/', 'resources/'];
const sourceExtensions = new Set([
  '.rs', '.toml', '.lock', '.px', '.ts', '.tsx', '.js', '.mjs', '.cjs', '.json',
  '.ps1', '.psm1', '.psd1', '.yml', '.yaml', '.sh', '.cmd', '.bat', '.xml', '.wxs',
]);

export function checkSourceProvenance(root) {
  const git = (...args) => execFileSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  const policy = JSON.parse(readFileSync(join(root, 'source-provenance.json'), 'utf8'));
  const relativePath = (value) => typeof value === 'string'
    && value.length > 0 && !/[\x00-\x1f\\:]/u.test(value)
    && value.split('/').every((part) => part !== '' && part !== '.' && part !== '..');
  if (policy.schemaVersion !== 1 || policy.disposition !== 'hold'
      || policy.reuseApproved !== false || !relativePath(policy.heldRoot)
      || !Array.isArray(policy.files) || policy.files.length === 0) {
    throw new Error('Invalid source provenance hold; approval requires a separate reviewed decision.');
  }
  const expected = new Map();
  for (const file of policy.files) {
    if (!file || !relativePath(file.path) || !file.path.startsWith(`${policy.heldRoot}/`)
        || !/^[0-9a-f]{40}$/u.test(file.gitBlob ?? '') || expected.has(file.path)) {
      throw new Error('Invalid or duplicate held source inventory entry.');
    }
    expected.set(file.path, file.gitBlob);
  }
  const held = git('ls-files', '-z', '--cached', '--others', '--', policy.heldRoot)
    .split('\0').filter(Boolean);
  if (held.length !== expected.size || held.some((path) => !expected.has(path))) {
    throw new Error('Held source inventory changed; explicit provenance disposition is required.');
  }
  const index = new Map();
  for (const record of git('ls-files', '--stage', '-z').split('\0').filter(Boolean)) {
    const match = /^(\d+) ([0-9a-f]+) ([0-3])\t([\s\S]+)$/u.exec(record);
    if (!match || match[3] !== '0') {
      throw new Error('Source provenance requires an unconflicted Git index.');
    }
    index.set(match[4], { mode: match[1], blob: match[2] });
  }
  for (const [path, blob] of expected) {
    if (index.get(path)?.mode !== '100644' || index.get(path)?.blob !== blob
        || !lstatSync(join(root, path)).isFile()
        || git('hash-object', '--', path).trim() !== blob) {
      throw new Error(`Held source changed or is not an unchanged regular file: ${path}`);
    }
  }
  const archivePaths = [policy.heldRoot, ...expected.keys()];
  const attributes = git('check-attr', '-z', 'export-ignore', '--', ...archivePaths)
    .split('\0');
  if (attributes.length !== archivePaths.length * 3 + 1) {
    throw new Error('Incomplete Git archive attribute response.');
  }
  for (let i = 0; i < archivePaths.length; i += 1) {
    if (attributes[i * 3] !== archivePaths[i]
        || attributes[i * 3 + 1] !== 'export-ignore' || attributes[i * 3 + 2] !== 'set') {
      throw new Error(`Held source must be excluded from Git archives: ${archivePaths[i]}`);
    }
  }
  const paths = new Set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    .split('\0').filter(Boolean));
  let nativeFilesChecked = 0;
  for (const path of paths) {
    if (!runtimeRoots.some((prefix) => path.toLowerCase().startsWith(prefix))) continue;
    const mode = index.get(path)?.mode;
    if ((mode && mode !== '100644' && mode !== '100755') || !lstatSync(join(root, path)).isFile()) {
      throw new Error(`Runtime inputs must be regular files for provenance inspection: ${path}`);
    }
    if (!sourceExtensions.has(extname(path).toLowerCase())) continue;
    if (readFileSync(join(root, path), 'utf8').toLowerCase().includes(policy.heldRoot.toLowerCase())) {
      throw new Error(`Runtime source references the held directory: ${path}`);
    }
    nativeFilesChecked += 1;
  }
  return {
    event: 'source_provenance_checked',
    heldPaths: expected.size,
    nativeFilesChecked,
    licenseClearance: false,
    runtimeAcceptance: false,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = checkSourceProvenance(fileURLToPath(new URL('..', import.meta.url)));
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({
      event: 'source_provenance_check_failed',
      error: error instanceof Error ? error.message : String(error),
    })}\n`);
    process.exitCode = 1;
  }
}
