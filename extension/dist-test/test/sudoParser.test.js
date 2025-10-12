"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = require("node:test");
const sudoParser_1 = require("../src/dsl/sudoParser");
const baselineSource = `install git via winget version latest\ninstall package "NodeJS" via winget`; // two statements
(0, node_test_1.test)('parses install statements into canonical AST', () => {
    const { doc } = (0, sudoParser_1.parseSudo)(baselineSource);
    strict_1.default.equal(doc.blocks.length, 1);
    const block = doc.blocks[0];
    strict_1.default.equal(block.packages.length, 2);
    const [first, second] = block.packages;
    strict_1.default.equal(first.id, 'git');
    strict_1.default.equal(first.providerOverride, 'winget');
    strict_1.default.equal(first.version, 'latest');
    strict_1.default.equal(second.display, 'NodeJS');
    strict_1.default.equal(second.id, 'nodejs');
});
(0, node_test_1.test)('produces warning diagnostic for unknown provider', () => {
    const { doc } = (0, sudoParser_1.parseSudo)('install package custom via frobnicate');
    strict_1.default.equal(doc.blocks.length, 1);
    const pkg = doc.blocks[0].packages[0];
    strict_1.default.equal(pkg.providerOverride, 'unknown');
    strict_1.default.ok(doc.diagnostics && doc.diagnostics.some(d => d.code === 'DSL005' && d.severity === 'warning'));
});
(0, node_test_1.test)('ensure statements map to install block entries', () => {
    const { doc } = (0, sudoParser_1.parseSudo)('ensure package "Docker.DockerDesktop" via winget');
    strict_1.default.equal(doc.blocks.length, 1);
    const pkg = doc.blocks[0].packages[0];
    strict_1.default.equal(pkg.display, 'Docker.DockerDesktop');
    strict_1.default.equal(pkg.providerOverride, 'winget');
    strict_1.default.equal(pkg.version, undefined);
});
(0, node_test_1.test)('parses executable override with args clause', () => {
    const { doc } = (0, sudoParser_1.parseSudo)('install package "CustomApp" using "C:/Installers/CustomApp.msi" args "/quiet /norestart"');
    strict_1.default.equal(doc.blocks.length, 1);
    const pkg = doc.blocks[0].packages[0];
    strict_1.default.ok(pkg.executableOverride);
    strict_1.default.equal(pkg.executableOverride?.path, 'C:/Installers/CustomApp.msi');
    strict_1.default.deepEqual(pkg.executableOverride?.args, ['/quiet', '/norestart']);
    strict_1.default.equal(pkg.providerOverride, undefined);
});
(0, node_test_1.test)('provider and executable conflict yields DSL006 diagnostic', () => {
    const { doc } = (0, sudoParser_1.parseSudo)('install package tool via winget using "tool.exe"');
    strict_1.default.ok(doc.diagnostics?.some(d => d.code === 'DSL006' && d.severity === 'error'));
});
