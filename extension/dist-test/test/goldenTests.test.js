"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert"));
const fs = __importStar(require("fs/promises"));
const path = __importStar(require("path"));
const simpleParser_1 = require("../src/dsl/simpleParser");
const sudoParser_1 = require("../src/dsl/sudoParser");
(0, node_test_1.describe)('Golden Test Corpus', () => {
    (0, node_test_1.it)('all fixtures parse without errors', async () => {
        // Use source directory fixtures, not dist-test
        const fixturesDir = path.join(__dirname, '../../test-fixtures');
        const files = await fs.readdir(fixturesDir);
        for (const file of files) {
            const content = await fs.readFile(path.join(fixturesDir, file), 'utf-8');
            const parsed = file.endsWith('.ssudo')
                ? (0, sudoParser_1.parseSudo)(content).doc
                : (0, simpleParser_1.parseSimple)(content);
            const errors = parsed.diagnostics?.filter((d) => d.severity === 'error') || [];
            assert.equal(errors.length, 0, `${file} should parse without errors, got: ${JSON.stringify(errors)}`);
        }
    });
    (0, node_test_1.it)('basic install fixture has expected structure', async () => {
        const fixturesDir = path.join(__dirname, '../../test-fixtures');
        const content = await fs.readFile(path.join(fixturesDir, '01-basic-install.simple.dsc.yaml'), 'utf-8');
        const parsed = (0, simpleParser_1.parseSimple)(content);
        assert.equal(parsed.blocks.length, 1, 'Should have one block');
        assert.equal(parsed.blocks[0].kind, 'InstallBlock', 'Block should be InstallBlock');
        const installBlock = parsed.blocks[0];
        assert.equal(installBlock.packages.length, 2, 'Should have 2 packages');
        assert.equal(installBlock.packages[0].id, 'git.git', 'First package should be git.git (canonicalized)');
        assert.equal(installBlock.packages[1].id, 'microsoft.visualstudiocode', 'Second package should be VSCode (canonicalized)');
    });
    (0, node_test_1.it)('version pinning fixture preserves versions', async () => {
        const fixturesDir = path.join(__dirname, '../../test-fixtures');
        const content = await fs.readFile(path.join(fixturesDir, '05-version-pinning.simple.dsc.yaml'), 'utf-8');
        const parsed = (0, simpleParser_1.parseSimple)(content);
        const installBlock = parsed.blocks[0];
        assert.equal(installBlock.packages[0].version, '2.43.0', 'Git version should be pinned');
        assert.equal(installBlock.packages[1].version, '3.12.1', 'Python version should be pinned');
    });
    (0, node_test_1.it)('provider override fixture preserves method', async () => {
        const fixturesDir = path.join(__dirname, '../../test-fixtures');
        const content = await fs.readFile(path.join(fixturesDir, '03-provider-override.simple.dsc.yaml'), 'utf-8');
        const parsed = (0, simpleParser_1.parseSimple)(content);
        const installBlock = parsed.blocks[0];
        assert.equal(installBlock.packages[0].providerOverride, 'winget', 'Git should use winget');
        assert.equal(installBlock.packages[1].providerOverride, 'chocolatey', 'Node.js should use chocolatey');
    });
    (0, node_test_1.it)('executable override fixture preserves executable and args', async () => {
        const fixturesDir = path.join(__dirname, '../../test-fixtures');
        const content = await fs.readFile(path.join(fixturesDir, '04-executable-override.simple.dsc.yaml'), 'utf-8');
        const parsed = (0, simpleParser_1.parseSimple)(content);
        const installBlock = parsed.blocks[0];
        const pkg = installBlock.packages[0];
        assert.ok(pkg.executableOverride, 'Should have executable override');
        assert.equal(pkg.executableOverride.path, 'C:\\custom\\installer.exe', 'Executable path should be preserved');
        assert.deepEqual(pkg.executableOverride.args, ['/silent', '/install'], 'Args should be preserved as array');
    });
});
