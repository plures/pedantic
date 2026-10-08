import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  TextDocumentSyncKind,
  CompletionItem,
  CompletionItemKind,
  DiagnosticSeverity,
  Diagnostic,
  CompletionParams,
  DidChangeConfigurationNotification,
  DocumentFormattingParams,
  TextEdit,
  CodeActionParams,
  CodeAction
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { formatSimpleDsl } from './formatter';
import { getCodeActions } from './codeActions';

// Create a connection for the server using Node IPC
const connection = createConnection(ProposedFeatures.all);

// Create a text document manager
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

let hasConfigurationCapability = false;
let hasWorkspaceFolderCapability = false;

// Store diagnostics for code actions
const documentDiagnostics = new Map<string, Diagnostic[]>();

connection.onInitialize((params: InitializeParams) => {
  const capabilities = params.capabilities;

  // Does the client support workspace folders?
  hasWorkspaceFolderCapability = !!(
    capabilities.workspace && !!capabilities.workspace.workspaceFolders
  );
  hasConfigurationCapability = !!(
    capabilities.workspace && !!capabilities.workspace.configuration
  );

  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Full,
      completionProvider: {
        triggerCharacters: ['.', ':']
      },
      documentFormattingProvider: true,
      codeActionProvider: true
    }
  };
});

connection.onInitialized(() => {
  if (hasConfigurationCapability) {
    // Register for all configuration changes
    connection.client.register(
      DidChangeConfigurationNotification.type,
      undefined
    );
  }
  if (hasWorkspaceFolderCapability) {
    connection.workspace.onDidChangeWorkspaceFolders(_event => {
      connection.console.log('Workspace folder change event received.');
    });
  }
  
  connection.console.log('Pedantic Language Server initialized');
});

// Validate document and publish diagnostics
async function validateDocument(textDocument: TextDocument): Promise<void> {
  const text = textDocument.getText();
  const uri = textDocument.uri;

  // Detect dialect by file extension or content
  const dialect = uri.endsWith('.ssudo') ? 'sudo' : 'simple';

  try {
    let parsed: any;
    if (dialect === 'sudo') {
      const { parseSudo } = await import('../dsl/sudoParser.js');
      parsed = parseSudo(text);
    } else {
      const { parseSimple } = await import('../dsl/simpleParser.js');
      parsed = parseSimple(text);
    }

    const diagnostics: Diagnostic[] = (parsed.doc?.diagnostics || []).map((d: any) => ({
      severity: d.severity === 'error' ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
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
  } catch (err: any) {
    connection.console.error(`Error validating document: ${err.message}`);
    
    // Send a diagnostic for the parse error
    const diagnostics: Diagnostic[] = [{
      severity: DiagnosticSeverity.Error,
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
connection.onCompletion((params: CompletionParams): CompletionItem[] => {
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
        kind: CompletionItemKind.Keyword,
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
        kind: CompletionItemKind.Property,
        detail: 'List of packages to install'
      }
    ];
  }

  // Method values
  if (linePrefix.match(/method:\s*$/)) {
    return ['winget', 'chocolatey', 'msi', 'apt', 'yum', 'brew'].map(m => ({
      label: m,
      kind: CompletionItemKind.EnumMember,
      detail: `${m} package manager`
    }));
  }

  return [];
});

// Document formatting provider
connection.onDocumentFormatting(async (params: DocumentFormattingParams): Promise<TextEdit[]> => {
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
    const { parseSimple } = await import('../dsl/simpleParser.js');
    const parsed = parseSimple(text);
    const formatted = formatSimpleDsl(parsed);

    // Return a single edit that replaces the entire document
    return [
      TextEdit.replace(
        {
          start: { line: 0, character: 0 },
          end: { line: document.lineCount, character: 0 }
        },
        formatted
      )
    ];
  } catch (err: any) {
    connection.console.error(`Formatting error: ${err.message}`);
    return [];
  }
});

// Code actions provider
connection.onCodeAction((params: CodeActionParams): CodeAction[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document) {
    return [];
  }

  const diagnostics = documentDiagnostics.get(params.textDocument.uri) || [];
  const documentText = document.getText();
  
  // Get code actions based on diagnostics
  const actions = getCodeActions(diagnostics, documentText);
  
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
