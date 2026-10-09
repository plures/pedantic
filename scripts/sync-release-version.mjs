#!/usr/bin/env node
/** Synchronize shipped package metadata for a release computed by the shared workflow. */
import fs from 'node:fs';
import path from 'node:path';

const version = process.argv[2] || process.env.RELEASE_VERSION;
const semver = /^(\d+\.\d+\.\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$/.exec(version || '');
if (!semver) {
  throw new Error('Provide a SemVer release version as argv[2] or RELEASE_VERSION.');
}
const [, versionCore, prereleaseLabel] = semver;

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
  const inheritsWorkspaceVersion = /^version\.workspace\s*=\s*true\s*$/m.test(section[1]);
  if (!name || (!packageVersion && !inheritsWorkspaceVersion)) {
    writeIfChanged(manifest, before, after);
    continue;
  }

  if (packageVersion) {
    const replacement = packageVersion[0].replace(/"[^"]+"/, '"' + version + '"');
    after = after.slice(0, section.index) + section[0].replace(packageVersion[0], replacement) + after.slice(section.index + section[0].length);
  }
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

for (const packageLock of walk(root, 'package-lock.json')) {
  const before = fs.readFileSync(packageLock, 'utf8');
  const lockfile = JSON.parse(before);
  let changed = false;
  if (typeof lockfile.version === 'string' && lockfile.version !== version) {
    lockfile.version = version;
    changed = true;
  }
  if (typeof lockfile.packages?.['']?.version === 'string' && lockfile.packages[''].version !== version) {
    lockfile.packages[''].version = version;
    changed = true;
  }
  if (changed) writeIfChanged(packageLock, before, JSON.stringify(lockfile, null, 2) + '\n');
}

// Pedantic's compatibility module ships in the same release artifacts as the
// Rust CLI. Keep its manifest identity aligned with the release tag so a
// package manager and PowerShell do not report different installed versions.
// `ModuleVersion` must be a numeric System.Version, so SemVer prerelease
// suffixes are preserved through PrivateData.PSData.Prerelease instead.
// PowerShell prerelease strings allow only ASCII alphanumerics, so separators
// from the SemVer label are dropped rather than emitting an invalid manifest.
const prereleaseTag = (prereleaseLabel || '').replace(/[^0-9A-Za-z]/g, '');
if (prereleaseLabel && !/^[A-Za-z][0-9A-Za-z]*$/.test(prereleaseTag)) {
  throw new Error('Prerelease label ' + prereleaseLabel + ' does not map to a PSData.Prerelease value starting with an ASCII letter.');
}

const powerShellManifests = [
  path.join(root, 'Pedantic.psd1'),
  path.join(root, 'extension/bridge/module/Pedantic.psd1'),
];
for (const powerShellManifest of powerShellManifests) {
  if (!fs.existsSync(powerShellManifest)) {
    throw new Error(path.relative(root, powerShellManifest) + ' is required for a Pedantic release.');
  }
  const manifestBefore = fs.readFileSync(powerShellManifest, 'utf8');
  const manifestVersion = /^\s*ModuleVersion\s*=\s*'[^']+'\s*$/m.exec(manifestBefore);
  if (!manifestVersion) {
    throw new Error(path.relative(root, powerShellManifest) + ' has no single-quoted ModuleVersion entry.');
  }
  let manifestAfter = manifestBefore.replace(
    manifestVersion[0],
    manifestVersion[0].replace(/'[^']+'/, "'" + versionCore + "'"),
  );

  const prereleaseLine = /^[ \t]*Prerelease\s*=\s*'[^']*'[ \t]*;?[ \t]*\r?\n/m;
  const prereleaseInline = /(^|[\s;{])Prerelease\s*=\s*'[^']*'[ \t]*;?/m;
  const lineMatch = prereleaseLine.exec(manifestAfter);
  const existingPrerelease = lineMatch || prereleaseInline.exec(manifestAfter);
  if (prereleaseTag) {
    const entry = "Prerelease = '" + prereleaseTag + "'";
    if (existingPrerelease) {
      manifestAfter = manifestAfter.replace(
        existingPrerelease[0],
        existingPrerelease[0].replace(/Prerelease\s*=\s*'[^']*'/, entry),
      );
    } else {
      const psData = /PSData\s*=\s*@\{/.exec(manifestAfter);
      if (!psData) {
        throw new Error(path.relative(root, powerShellManifest) + ' has no PrivateData.PSData hashtable for the prerelease label.');
      }
      const insertAt = psData.index + psData[0].length;
      manifestAfter = manifestAfter.slice(0, insertAt) + ' ' + entry + ';' + manifestAfter.slice(insertAt);
    }
  } else if (existingPrerelease) {
    manifestAfter = manifestAfter.replace(existingPrerelease[0], lineMatch ? '' : existingPrerelease[1]);
  }

  writeIfChanged(powerShellManifest, manifestBefore, manifestAfter);
}
