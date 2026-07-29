import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseSudo } from '../src/dsl/sudoParser';

const baselineSource = `install git via winget version latest\ninstall package "NodeJS" via winget`; // two statements

test('parses install statements into canonical AST', () => {
  const { doc } = parseSudo(baselineSource);
  assert.equal(doc.blocks.length, 1);
  const block = doc.blocks[0];
  assert.equal(block.packages.length, 2);
  const [first, second] = block.packages;
  assert.equal(first.id, 'git');
  assert.equal(first.providerOverride, 'winget');
  assert.equal(first.version, 'latest');
  assert.equal(second.display, 'NodeJS');
  assert.equal(second.id, 'nodejs');
});

test('produces warning diagnostic for unknown provider', () => {
  const { doc } = parseSudo('install package custom via frobnicate');
  assert.equal(doc.blocks.length, 1);
  const pkg = doc.blocks[0].packages[0];
  assert.equal(pkg.providerOverride, 'unknown');
  assert.ok(doc.diagnostics && doc.diagnostics.some(d => d.code === 'DSL005' && d.severity === 'warning'));
});

test('ensure statements map to install block entries', () => {
  const { doc } = parseSudo('ensure package "Docker.DockerDesktop" via winget');
  assert.equal(doc.blocks.length, 1);
  const pkg = doc.blocks[0].packages[0];
  assert.equal(pkg.display, 'Docker.DockerDesktop');
  assert.equal(pkg.providerOverride, 'winget');
  assert.equal(pkg.version, undefined);
});

test('parses executable override with args clause', () => {
  const { doc } = parseSudo('install package "CustomApp" using "C:/Installers/CustomApp.msi" args "/quiet /norestart"');
  assert.equal(doc.blocks.length, 1);
  const pkg = doc.blocks[0].packages[0];
  assert.ok(pkg.executableOverride);
  assert.equal(pkg.executableOverride?.path, 'C:/Installers/CustomApp.msi');
  assert.deepEqual(pkg.executableOverride?.args, ['/quiet', '/norestart']);
  assert.equal(pkg.providerOverride, undefined);
});

test('provider and executable conflict yields DSL006 diagnostic', () => {
  const { doc } = parseSudo('install package tool via winget using "tool.exe"');
  assert.ok(doc.diagnostics?.some(d => d.code === 'DSL006' && d.severity === 'error'));
});

// Chevrotain compatibility smoke tests — validate the integration boundary so that
// major-version bumps are caught in CI rather than at extension activation time.

test('chevrotain smoke: parseSudo does not throw on empty input', () => {
  assert.doesNotThrow(() => parseSudo(''));
  const { doc, tokens } = parseSudo('');
  assert.equal(tokens.length, 0);
  assert.equal(doc.blocks.length, 0);
  assert.deepEqual(doc.diagnostics, []);
});

test('chevrotain smoke: lexer returns typed tokens for a simple statement', () => {
  const { tokens } = parseSudo('install git');
  assert.ok(tokens.length > 0, 'lexer should return at least one token');
  assert.equal(typeof tokens[0].image, 'string');
  assert.ok(tokens[0].tokenType, 'tokenType must be present on each token');
});

test('chevrotain smoke: parser produces no errors for a minimal valid statement', () => {
  const { doc } = parseSudo('install git');
  const errors = (doc.diagnostics ?? []).filter(d => d.severity === 'error');
  assert.equal(errors.length, 0, 'no parse errors expected for a minimal valid statement');
});
