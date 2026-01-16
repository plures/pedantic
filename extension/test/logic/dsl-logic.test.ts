import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createEmptyDocument } from '../../src/dsl/ast';
import { processDocument, createDslEngine, ParseDocument } from '../../src/logic/dsl-logic';

test('dsl logic processes simple document', () => {
  const doc = createEmptyDocument('simple');
  doc.blocks.push({
    kind: 'InstallBlock',
    packages: [
      {
        kind: 'PackageSpec',
        id: 'git',
        display: 'Git.Git',
        providerOverride: 'winget',
      },
      {
        kind: 'PackageSpec',
        id: 'nodejs',
        display: 'OpenJS.NodeJS',
        providerOverride: 'winget',
        version: 'latest',
      },
    ],
  });

  const result = processDocument(doc);

  assert.equal(result.context.packageCount, 2);
  const wingetCount = result.context.providerStats['winget'];
  assert.equal(wingetCount, 2);
  assert.equal(result.context.validationErrors, 0);
  assert.equal(result.facts.length, 3); // DocumentParsed + 2 PackageDiscovered
});

test('dsl logic detects provider/executable conflict', () => {
  const doc = createEmptyDocument('simple');
  doc.blocks.push({
    kind: 'InstallBlock',
    packages: [
      {
        kind: 'PackageSpec',
        id: 'tool',
        providerOverride: 'winget',
        executableOverride: { path: 'tool.exe' },
      },
    ],
  });

  const result = processDocument(doc);

  assert.equal(result.context.validationErrors, 1);
  const errorFact = result.facts.find(
    (f: any) => f.tag === 'ValidationIssue' && f.payload.code === 'DSL006'
  );
  assert.ok(errorFact);
});

test('dsl logic processes document diagnostics', () => {
  const doc = createEmptyDocument('simple');
  doc.diagnostics = [
    {
      code: 'DSL001',
      severity: 'error',
      message: 'Test error',
      range: {
        start: { line: 0, character: 0 },
        end: { line: 0, character: 1 },
      },
    },
    {
      code: 'DSL002',
      severity: 'warning',
      message: 'Test warning',
      range: {
        start: { line: 1, character: 0 },
        end: { line: 1, character: 1 },
      },
    },
  ];
  doc.blocks.push({
    kind: 'InstallBlock',
    packages: [],
  });

  const result = processDocument(doc);

  assert.equal(result.context.validationErrors, 1);
  assert.equal(result.context.validationWarnings, 1);
  const validationFacts = result.facts.filter((f: any) => f.tag === 'ValidationIssue');
  assert.equal(validationFacts.length, 2);
});

test('dsl engine enforces minimum packages constraint', () => {
  const engine = createDslEngine();

  const doc = createEmptyDocument('simple');
  doc.blocks.push({
    kind: 'InstallBlock',
    packages: [],
  });

  const result = engine.step([ParseDocument.create({ document: doc })]);

  assert.equal(result.violations.length, 1);
  assert.equal(result.violations[0].constraintId, 'dsl.minimum-packages');
  assert.equal(result.violations[0].severity, 'warning');
});

test('dsl engine enforces maximum packages constraint', () => {
  const engine = createDslEngine();

  const doc = createEmptyDocument('simple');
  const packages = [];
  for (let i = 0; i < 1001; i++) {
    packages.push({
      kind: 'PackageSpec' as const,
      id: `package-${i}`,
    });
  }
  doc.blocks.push({
    kind: 'InstallBlock',
    packages,
  });

  const result = engine.step([ParseDocument.create({ document: doc })]);

  const maxPackageViolation = result.violations.find(
    (v: any) => v.constraintId === 'dsl.maximum-packages'
  );
  assert.ok(maxPackageViolation);
  assert.equal(maxPackageViolation.severity, 'warning');
});

test('dsl engine tracks provider statistics', () => {
  const doc = createEmptyDocument('simple');
  doc.blocks.push({
    kind: 'InstallBlock',
    packages: [
      { kind: 'PackageSpec', id: 'git', providerOverride: 'winget' },
      { kind: 'PackageSpec', id: 'nodejs', providerOverride: 'winget' },
      { kind: 'PackageSpec', id: 'python', providerOverride: 'chocolatey' },
      { kind: 'PackageSpec', id: 'docker' },
    ],
  });

  const result = processDocument(doc);

  const wingetCount = result.context.providerStats['winget'];
  const chocoCount = result.context.providerStats['chocolatey'];
  const defaultCount = result.context.providerStats['default'];
  
  assert.equal(wingetCount, 2);
  assert.equal(chocoCount, 1);
  assert.equal(defaultCount, 1);
});
