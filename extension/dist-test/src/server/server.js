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
const node_1 = require("vscode-languageserver/node");
const vscode_languageserver_textdocument_1 = require("vscode-languageserver-textdocument");
const formatter_1 = require("./formatter");
const codeActions_1 = require("./codeActions");
// Create a connection for the server using Node IPC
const connection = (0, node_1.createConnection)(node_1.ProposedFeatures.all);
// Create a text document manager
const documents = new node_1.TextDocuments(vscode_languageserver_textdocument_1.TextDocument);
let hasConfigurationCapability = false;
let hasWorkspaceFolderCapability = false;
// Store diagnostics for code actions
const documentDiagnostics = new Map();
connection.onInitialize((params) => {
    const capabilities = params.capabilities;
    // Does the client support workspace folders?
    hasWorkspaceFolderCapability = !!(capabilities.workspace && !!capabilities.workspace.workspaceFolders);
    hasConfigurationCapability = !!(capabilities.workspace && !!capabilities.workspace.configuration);
    return {
        capabilities: {
            textDocumentSync: node_1.TextDocumentSyncKind.Full,
            completionProvider: {
                triggerCharacters: ['.', ':']
            },
            diagnosticProvider: {
                interFileDependencies: false,
                workspaceDiagnostics: false
            },
            documentFormattingProvider: true,
            codeActionProvider: true
        }
    };
});
connection.onInitialized(() => {
    if (hasConfigurationCapability) {
        // Register for all configuration changes
        connection.client.register(node_1.DidChangeConfigurationNotification.type, undefined);
    }
    if (hasWorkspaceFolderCapability) {
        connection.workspace.onDidChangeWorkspaceFolders(_event => {
            connection.console.log('Workspace folder change event received.');
        });
    }
    connection.console.log('Pedantic Language Server initialized');
});
// Validate document and publish diagnostics
async function validateDocument(textDocument) {
    const text = textDocument.getText();
    const uri = textDocument.uri;
    // Detect dialect by file extension or content
    const dialect = uri.endsWith('.ssudo') ? 'sudo' : 'simple';
    try {
        let parsed;
        if (dialect === 'sudo') {
            const { parseSudo } = await Promise.resolve().then(() => __importStar(require('../dsl/sudoParser')));
            parsed = parseSudo(text);
        }
        else {
            const { parseSimple } = await Promise.resolve().then(() => __importStar(require('../dsl/simpleParser')));
            parsed = parseSimple(text);
        }
        const diagnostics = (parsed.doc?.diagnostics || []).map((d) => ({
            severity: d.severity === 'error' ? node_1.DiagnosticSeverity.Error : node_1.DiagnosticSeverity.Warning,
            range: {
                start: { line: d.range.start.line, character: d.range.start.character },
                end: { line: d.range.end.line, character: d.range.end.character }
            },
            message: d.message,
            code: d.code,
            source: 'pedantic'
        }));
        // Store diagnostics for code actions
        documentDiagnostics.set(uri, diagnostics);
        connection.sendDiagnostics({ uri, diagnostics });
    }
    catch (err) {
        connection.console.error(`Error validating document: ${err.message}`);
        // Send a diagnostic for the parse error
        const diagnostics = [{
                severity: node_1.DiagnosticSeverity.Error,
                range: {
                    start: { line: 0, character: 0 },
                    end: { line: 0, character: 0 }
                },
                message: `Parse error: ${err.message}`,
                source: 'pedantic'
            }];
        documentDiagnostics.set(uri, diagnostics);
        connection.sendDiagnostics({ uri, diagnostics });
    }
}
// Document change events
documents.onDidChangeContent(change => {
    validateDocument(change.document);
});
documents.onDidOpen(change => {
    validateDocument(change.document);
});
// Completions provider
connection.onCompletion((params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
        return [];
    }
    const text = document.getText();
    const offset = document.offsetAt(params.position);
    const linePrefix = text.substring(0, offset).split('\n').pop() || '';
    // Top-level keys
    if (linePrefix.trim() === '' || linePrefix.match(/^[a-z]/)) {
        return [
            {
                label: 'dsc.install',
                kind: node_1.CompletionItemKind.Keyword,
                detail: 'Install packages block',
                insertText: 'dsc.install:\n  packages:\n    - '
            }
        ];
    }
    // Inside dsc.install
    if (linePrefix.includes('dsc.install:') || text.includes('dsc.install:')) {
        return [
            {
                label: 'packages',
                kind: node_1.CompletionItemKind.Property,
                detail: 'List of packages to install'
            }
        ];
    }
    // Method values
    if (linePrefix.match(/method:\s*$/)) {
        return ['winget', 'chocolatey', 'msi', 'apt', 'yum', 'brew'].map(m => ({
            label: m,
            kind: node_1.CompletionItemKind.EnumMember,
            detail: `${m} package manager`
        }));
    }
    return [];
});
// Document formatting provider
connection.onDocumentFormatting(async (params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
        return [];
    }
    const text = document.getText();
    const uri = params.textDocument.uri;
    // Only format Simple DSL files
    if (uri.endsWith('.ssudo')) {
        return []; // SudoLang formatting not implemented yet
    }
    try {
        const { parseSimple } = await Promise.resolve().then(() => __importStar(require('../dsl/simpleParser')));
        const parsed = parseSimple(text);
        const formatted = (0, formatter_1.formatSimpleDsl)(parsed);
        // Return a single edit that replaces the entire document
        return [
            node_1.TextEdit.replace({
                start: { line: 0, character: 0 },
                end: { line: document.lineCount, character: 0 }
            }, formatted)
        ];
    }
    catch (err) {
        connection.console.error(`Formatting error: ${err.message}`);
        return [];
    }
});
// Code actions provider
connection.onCodeAction((params) => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
        return [];
    }
    const diagnostics = documentDiagnostics.get(params.textDocument.uri) || [];
    const documentText = document.getText();
    // Get code actions based on diagnostics
    const actions = (0, codeActions_1.getCodeActions)(diagnostics, documentText);
    // Fix the URI in the edits (replace '' with actual URI)
    for (const action of actions) {
        if (action.edit?.changes) {
            const changes = action.edit.changes[''];
            if (changes) {
                delete action.edit.changes[''];
                action.edit.changes[params.textDocument.uri] = changes;
            }
        }
    }
    return actions;
});
// Make the text document manager listen on the connection
documents.listen(connection);
// Listen on the connection
connection.listen();
