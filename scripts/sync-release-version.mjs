#!/usr/bin/env node
/** Synchronize shipped package metadata for a release computed by the shared workflow. */
import fs from 'node:fs';
import path from 'node:path';

const version = process.argv[2] || process.env.RELEASE_VERSION;
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version || '')) {
  throw new Error('Provide a SemVer release version as argv[2] or RELEASE_VERSION.');
}

const root = process.cwd();
const ignored = new Set(['.git', 'node_modules', 'target']);
const cargoPackages = new Map();

function walk(directory, filename) {
  const matches = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (ignored.has(entry.name)) continue;
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) matches.push(...walk(full, filename));
    else if (entry.isFile() && entry.name === filename) matches.push(full);
  }
  return matches;
}

function writeIfChanged(file, before, after) {
  if (before !== after) {
    fs.writeFileSync(file, after);
    console.log('synced ' + path.relative(root, file));
  }
}

function nearestCargoLock(manifest) {
  let directory = path.dirname(manifest);
  while (true) {
    const candidate = path.join(directory, 'Cargo.lock');
    if (fs.existsSync(candidate)) return candidate;
    if (directory === root) return null;
    const parent = path.dirname(directory);
    if (parent === directory || !parent.startsWith(root)) return null;
    directory = parent;
  }
}

for (const manifest of walk(root, 'Cargo.toml')) {
  const before = fs.readFileSync(manifest, 'utf8');
  let after = before;
  const workspaceSection = /^\[workspace\.package\]\s*$([\s\S]*?)(?=^\[[^\]]+\]\s*$|(?![\s\S]))/m.exec(after);
  const workspaceVersion = workspaceSection && /^version\s*=\s*"[^"]+"\s*$/m.exec(workspaceSection[1]);
  if (workspaceSection && workspaceVersion) {
    const replacement = workspaceVersion[0].replace(/"[^"]+"/, '"' + version + '"');
    after = after.slice(0, workspaceSection.index) + workspaceSection[0].replace(workspaceVersion[0], replacement) + after.slice(workspaceSection.index + workspaceSection[0].length);
  }

  const section = /^\[package\]\s*$([\s\S]*?)(?=^\[[^\]]+\]\s*$|(?![\s\S]))/m.exec(after);
  if (!section) {
    writeIfChanged(manifest, before, after);
    continue;
  }
  const name = /^name\s*=\s*"([^"]+)"\s*$/m.exec(section[1])?.[1];
  const packageVersion = /^version\s*=\s*"[^"]+"\s*$/m.exec(section[1]);
  if (!name || !packageVersion) {
    writeIfChanged(manifest, before, after);
    continue;
  }

  const replacement = packageVersion[0].replace(/"[^"]+"/, '"' + version + '"');
  after = after.slice(0, section.index) + section[0].replace(packageVersion[0], replacement) + after.slice(section.index + section[0].length);
  writeIfChanged(manifest, before, after);

  const lock = nearestCargoLock(manifest);
  if (!lock) continue;
  if (!cargoPackages.has(lock)) cargoPackages.set(lock, new Set());
  cargoPackages.get(lock).add(name);
}

for (const [lock, names] of cargoPackages) {
  const before = fs.readFileSync(lock, 'utf8');
  const blocks = before.split(/(?=^\[\[package\]\]\s*$)/m);
  const found = new Set();
  for (let index = 0; index < blocks.length; index += 1) {
    const block = blocks[index];
    const name = /^name\s*=\s*"([^"]+)"\s*$/m.exec(block)?.[1];
    if (!name || !names.has(name) || /^source\s*=/m.test(block)) continue;
    const packageVersion = /^version\s*=\s*"[^"]+"\s*$/m.exec(block);
    if (!packageVersion) throw new Error(path.relative(root, lock) + ': ' + name + ' has no version record.');
    blocks[index] = block.replace(packageVersion[0], packageVersion[0].replace(/"[^"]+"/, '"' + version + '"'));
    found.add(name);
  }
  const missing = [...names].filter((name) => !found.has(name));
  if (missing.length) throw new Error(path.relative(root, lock) + ': no local package record for ' + missing.join(', ') + '.');
  writeIfChanged(lock, before, blocks.join(''));
}

// Pedantic's compatibility module ships in the same release artifacts as the
// Rust CLI. Keep its manifest identity aligned with the release tag so a
// package manager and PowerShell do not report different installed versions.
const powerShellManifest = path.join(root, 'Pedantic.psd1');
if (!fs.existsSync(powerShellManifest)) {
  throw new Error('Pedantic.psd1 is required for a Pedantic release.');
}
const manifestBefore = fs.readFileSync(powerShellManifest, 'utf8');
const manifestVersion = /^\s*ModuleVersion\s*=\s*'[^']+'\s*$/m.exec(manifestBefore);
if (!manifestVersion) {
  throw new Error('Pedantic.psd1 has no single-quoted ModuleVersion entry.');
}
const manifestAfter = manifestBefore.replace(
  manifestVersion[0],
  manifestVersion[0].replace(/'[^']+'/, "'" + version + "'"),
);
writeIfChanged(powerShellManifest, manifestBefore, manifestAfter);
