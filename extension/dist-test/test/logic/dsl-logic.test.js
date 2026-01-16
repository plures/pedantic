"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = require("node:test");
const ast_1 = require("../../src/dsl/ast");
const dsl_logic_1 = require("../../src/logic/dsl-logic");
(0, node_test_1.test)('dsl logic processes simple document', () => {
    const doc = (0, ast_1.createEmptyDocument)('simple');
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
    const result = (0, dsl_logic_1.processDocument)(doc);
    strict_1.default.equal(result.context.packageCount, 2);
    const wingetCount = result.context.providerStats['winget'];
    strict_1.default.equal(wingetCount, 2);
    strict_1.default.equal(result.context.validationErrors, 0);
    strict_1.default.equal(result.facts.length, 3); // DocumentParsed + 2 PackageDiscovered
});
(0, node_test_1.test)('dsl logic detects provider/executable conflict', () => {
    const doc = (0, ast_1.createEmptyDocument)('simple');
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
    const result = (0, dsl_logic_1.processDocument)(doc);
    strict_1.default.equal(result.context.validationErrors, 1);
    const errorFact = result.facts.find((f) => f.tag === 'ValidationIssue' && f.payload.code === 'DSL006');
    strict_1.default.ok(errorFact);
});
(0, node_test_1.test)('dsl logic processes document diagnostics', () => {
    const doc = (0, ast_1.createEmptyDocument)('simple');
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
    const result = (0, dsl_logic_1.processDocument)(doc);
    strict_1.default.equal(result.context.validationErrors, 1);
    strict_1.default.equal(result.context.validationWarnings, 1);
    const validationFacts = result.facts.filter((f) => f.tag === 'ValidationIssue');
    strict_1.default.equal(validationFacts.length, 2);
});
(0, node_test_1.test)('dsl engine enforces minimum packages constraint', () => {
    const engine = (0, dsl_logic_1.createDslEngine)();
    const doc = (0, ast_1.createEmptyDocument)('simple');
    doc.blocks.push({
        kind: 'InstallBlock',
        packages: [],
    });
    const result = engine.step([dsl_logic_1.ParseDocument.create({ document: doc })]);
    strict_1.default.equal(result.violations.length, 1);
    strict_1.default.equal(result.violations[0].constraintId, 'dsl.minimum-packages');
    strict_1.default.equal(result.violations[0].severity, 'warning');
});
(0, node_test_1.test)('dsl engine enforces maximum packages constraint', () => {
    const engine = (0, dsl_logic_1.createDslEngine)();
    const doc = (0, ast_1.createEmptyDocument)('simple');
    const packages = [];
    for (let i = 0; i < 1001; i++) {
        packages.push({
            kind: 'PackageSpec',
            id: `package-${i}`,
        });
    }
    doc.blocks.push({
        kind: 'InstallBlock',
        packages,
    });
    const result = engine.step([dsl_logic_1.ParseDocument.create({ document: doc })]);
    const maxPackageViolation = result.violations.find((v) => v.constraintId === 'dsl.maximum-packages');
    strict_1.default.ok(maxPackageViolation);
    strict_1.default.equal(maxPackageViolation.severity, 'warning');
});
(0, node_test_1.test)('dsl engine tracks provider statistics', () => {
    const doc = (0, ast_1.createEmptyDocument)('simple');
    doc.blocks.push({
        kind: 'InstallBlock',
        packages: [
            { kind: 'PackageSpec', id: 'git', providerOverride: 'winget' },
            { kind: 'PackageSpec', id: 'nodejs', providerOverride: 'winget' },
            { kind: 'PackageSpec', id: 'python', providerOverride: 'chocolatey' },
            { kind: 'PackageSpec', id: 'docker' },
        ],
    });
    const result = (0, dsl_logic_1.processDocument)(doc);
    const wingetCount = result.context.providerStats['winget'];
    const chocoCount = result.context.providerStats['chocolatey'];
    const defaultCount = result.context.providerStats['default'];
    strict_1.default.equal(wingetCount, 2);
    strict_1.default.equal(chocoCount, 1);
    strict_1.default.equal(defaultCount, 1);
});
