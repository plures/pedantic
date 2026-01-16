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
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const resourceGraphPanel_1 = require("./webviews/resourceGraphPanel");
const client_1 = require("./client");
const pwshBridge_1 = require("./bridge/pwshBridge");
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
let graphPanel;
let aiPanel;
function activate(context) {
    // Start the language server
    (0, client_1.activateLanguageServer)(context);
    const disposables = [];
    disposables.push(vscode.commands.registerCommand('pedantic.generateConfig', async () => {
        const workspaceIsTrusted = vscode.workspace.isTrusted ?? true;
        if (!workspaceIsTrusted) {
            vscode.window.showWarningMessage('Pedantic: Workspace is not trusted. Enable trust to generate DSC output.');
            return;
        }
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor – open a DSL file to generate.');
            return;
        }
        const doc = editor.document;
        // Save document to temp file if it has unsaved changes
        let dslPath = doc.uri.fsPath;
        let tempFile;
        if (doc.isDirty) {
            const tempDir = path.join(context.globalStoragePath, 'temp');
            if (!fs.existsSync(tempDir)) {
                fs.mkdirSync(tempDir, { recursive: true });
            }
            tempFile = path.join(tempDir, path.basename(doc.fileName));
            fs.writeFileSync(tempFile, doc.getText(), 'utf-8');
            dslPath = tempFile;
        }
        try {
            vscode.window.showInformationMessage('Pedantic: Generating DSC configuration...');
            const response = await (0, pwshBridge_1.invokePwsh)({
                command: 'generate',
                dslPath,
                options: { timeout: 30000 }
            });
            if (response.success) {
                // Create a new document with the generated output
                const outputDoc = await vscode.workspace.openTextDocument({
                    content: response.output || '',
                    language: 'yaml'
                });
                await vscode.window.showTextDocument(outputDoc, vscode.ViewColumn.Beside);
                vscode.window.showInformationMessage('Pedantic: DSC configuration generated successfully');
            }
            else {
                const errors = response.errors?.join('\n') || 'Unknown error';
                vscode.window.showErrorMessage(`Pedantic: Generation failed:\n${errors}`);
            }
        }
        catch (err) {
            vscode.window.showErrorMessage(`Pedantic: Bridge error: ${err.message}`);
        }
        finally {
            // Clean up temp file
            if (tempFile && fs.existsSync(tempFile)) {
                fs.unlinkSync(tempFile);
            }
        }
    }));
    // Debounced graph refresh support
    let graphRefreshTimer;
    const scheduleGraphRefresh = () => {
        if (graphRefreshTimer)
            globalThis.clearTimeout(graphRefreshTimer);
        graphRefreshTimer = globalThis.setTimeout(async () => {
            const panel = resourceGraphPanel_1.ResourceGraphPanel.current();
            if (!panel)
                return;
            const editor = vscode.window.activeTextEditor;
            if (!editor)
                return;
            try {
                const parserMod = await Promise.resolve().then(() => __importStar(require('./dsl/simpleParser')));
                const doc = parserMod.parseSimple(editor.document.getText());
                panel.updateFromSimpleDocument(doc);
            }
            catch (e) {
                vscode.window.showErrorMessage('Graph auto-refresh failed: ' + e.message);
            }
        }, 200); // 200ms debounce
    };
    disposables.push(vscode.commands.registerCommand('pedantic.openGraph', async () => {
        const panel = resourceGraphPanel_1.ResourceGraphPanel.createOrShow(context);
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showInformationMessage('Open a DSL document to populate the graph.');
            return;
        }
        // Graph visualization allowed in untrusted workspaces (read-only parse). If policy changes, gate here.
        try {
            const parserMod = await Promise.resolve().then(() => __importStar(require('./dsl/simpleParser')));
            const doc = parserMod.parseSimple(editor.document.getText());
            panel.updateFromSimpleDocument(doc);
        }
        catch (e) {
            vscode.window.showErrorMessage('Graph parse failed: ' + e.message);
        }
    }));
    // Auto-refresh when active document changes
    disposables.push(vscode.workspace.onDidChangeTextDocument((e) => {
        if (!vscode.window.activeTextEditor)
            return;
        if (e.document === vscode.window.activeTextEditor.document && resourceGraphPanel_1.ResourceGraphPanel.current()) {
            scheduleGraphRefresh();
        }
    }));
    // Refresh on editor switch
    disposables.push(vscode.window.onDidChangeActiveTextEditor((ed) => {
        if (ed && resourceGraphPanel_1.ResourceGraphPanel.current()) {
            scheduleGraphRefresh();
        }
    }));
    disposables.push(vscode.commands.registerCommand('pedantic.openAiPanel', () => {
        if (aiPanel) {
            aiPanel.reveal();
            return;
        }
        aiPanel = vscode.window.createWebviewPanel('pedanticAi', 'Pedantic AI Assistant', vscode.ViewColumn.Beside, { enableScripts: true });
        aiPanel.onDidDispose(() => { aiPanel = undefined; }, null, context.subscriptions);
        aiPanel.webview.html = getBasicHtml('AI Assistant', `<p>AI panel placeholder. MCP integration forthcoming.</p>`);
    }));
    // Debug: parse active document (Simple DSL only for now) and show diagnostics
    disposables.push(vscode.commands.registerCommand('pedantic.debugParse', async () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor to parse.');
            return;
        }
        const text = editor.document.getText();
        let parserMod;
        try {
            parserMod = await Promise.resolve().then(() => __importStar(require('./dsl/simpleParser')));
        }
        catch (e) {
            vscode.window.showErrorMessage('Failed to load parser: ' + e.message);
            return;
        }
        const doc = parserMod.parseSimple(text);
        const ch = getOutputChannel();
        ch.clear();
        ch.appendLine('Pedantic Debug Parse Results');
        ch.appendLine('Dialect: simple');
        ch.appendLine('Blocks: ' + doc.blocks.length);
        for (const b of doc.blocks) {
            if (b.kind === 'InstallBlock') {
                ch.appendLine(` InstallBlock packages=${b.packages.length}`);
                for (const p of b.packages) {
                    ch.appendLine(`  - ${p.id}${p.version ? '@' + p.version : ''}${p.providerOverride ? ' via ' + p.providerOverride : ''}`);
                }
            }
        }
        if (doc.diagnostics?.length) {
            ch.appendLine('Diagnostics:');
            for (const d of doc.diagnostics) {
                ch.appendLine(` ${d.severity.toUpperCase()} ${d.code}: ${d.message}`);
            }
        }
        else {
            ch.appendLine('No diagnostics.');
        }
        ch.show(true);
    }));
    context.subscriptions.push(...disposables);
}
function deactivate() {
    graphPanel = undefined;
    aiPanel = undefined;
    return (0, client_1.deactivateLanguageServer)();
}
function getBasicHtml(title, body) {
    const nonce = Math.random().toString(36).slice(2);
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${title}</title>
<style>body{font-family:var(--vscode-font-family,Segoe UI,Arial);padding:1rem;line-height:1.4;}h1{font-size:1.2rem;margin-top:0;}code{background:#0002;padding:2px 4px;border-radius:4px;}</style>
</head>
<body>
<h1>${title}</h1>
${body}
</body>
</html>`;
}
let _outputChannel;
function getOutputChannel() {
    if (!_outputChannel) {
        _outputChannel = vscode.window.createOutputChannel('Pedantic DSL');
    }
    return _outputChannel;
}
