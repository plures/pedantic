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
  CodeAction,
  CancellationToken
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
const validationTimers = new Map<string, ReturnType<typeof setTimeout>>();
const validationGenerations = new Map<string, number>();
const validationDebounceMs = 150;

type Dialect = 'simple' | 'sudo';

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
      textDocumentSync: TextDocumentSyncKind.Incremental,
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

function dialectForUri(uri: string): Dialect | undefined {
  const path = decodeURIComponent(uri.replace(/^file:\/\//, ''));
  if (path.endsWith('.simple.dsc.yaml')) {
    return 'simple';
  }
  if (path.endsWith('.ssudo')) {
    return 'sudo';
  }
  return undefined;
}

function isCurrentValidation(uri: string, version: number, generation: number): boolean {
  return validationGenerations.get(uri) === generation && documents.get(uri)?.version === version;
}

function scheduleValidation(textDocument: TextDocument): void {
  const uri = textDocument.uri;
  if (!dialectForUri(uri)) {
    return;
  }

  const generation = (validationGenerations.get(uri) ?? 0) + 1;
  validationGenerations.set(uri, generation);
  const timer = validationTimers.get(uri);
  if (timer) {
    clearTimeout(timer);
  }
  validationTimers.set(uri, setTimeout(() => {
    validationTimers.delete(uri);
    void validateDocument(uri, textDocument.version, generation);
  }, validationDebounceMs));
}

async function validateDocument(uri: string, version: number, generation: number): Promise<void> {
  const textDocument = documents.get(uri);
  const dialect = dialectForUri(uri);
  if (!textDocument || !dialect || !isCurrentValidation(uri, version, generation)) {
    return;
  }
  const text = textDocument.getText();

  try {
    let parsed: any;
    if (dialect === 'sudo') {
      const { parseSudo } = await import('../dsl/sudoParser.js');
      if (!isCurrentValidation(uri, version, generation)) {
        return;
      }
      parsed = parseSudo(text);
    } else {
      const { parseSimple } = await import('../dsl/simpleParser.js');
      if (!isCurrentValidation(uri, version, generation)) {
        return;
      }
      parsed = parseSimple(text);
    }
    if (!isCurrentValidation(uri, version, generation)) {
      return;
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
  } catch (err: unknown) {
    if (!isCurrentValidation(uri, version, generation)) {
      return;
    }
    const message = err instanceof Error ? err.message : String(err);
    connection.console.error(`Error validating document: ${message}`);
    
    // Send a diagnostic for the parse error
    const diagnostics: Diagnostic[] = [{
      severity: DiagnosticSeverity.Error,
      range: {
        start: { line: 0, character: 0 },
        end: { line: 0, character: 0 }
      },
      message: `Parse error: ${message}`,
      source: 'pedantic'
    }];
    
    documentDiagnostics.set(uri, diagnostics);
    connection.sendDiagnostics({ uri, diagnostics });
  }
}

// Document change events
documents.onDidChangeContent(change => {
  scheduleValidation(change.document);
});

documents.onDidOpen(change => {
  scheduleValidation(change.document);
});

documents.onDidClose(change => {
  const uri = change.document.uri;
  const timer = validationTimers.get(uri);
  if (timer) {
    clearTimeout(timer);
    validationTimers.delete(uri);
  }
  validationGenerations.delete(uri);
  documentDiagnostics.delete(uri);
  connection.sendDiagnostics({ uri, diagnostics: [] });
});

// Completions provider
connection.onCompletion((params: CompletionParams, token: CancellationToken): CompletionItem[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document || !dialectForUri(document.uri) || token.isCancellationRequested) {
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
connection.onDocumentFormatting(async (params: DocumentFormattingParams, token: CancellationToken): Promise<TextEdit[]> => {
  const document = documents.get(params.textDocument.uri);
  if (!document || !dialectForUri(document.uri)) {
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
    if (token.isCancellationRequested) {
      return [];
    }
    const parsed = parseSimple(text);
    if (token.isCancellationRequested) {
      return [];
    }
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
  } catch (err: unknown) {
    connection.console.error(`Formatting error: ${err instanceof Error ? err.message : String(err)}`);
    return [];
  }
});

// Code actions provider
connection.onCodeAction((params: CodeActionParams, token: CancellationToken): CodeAction[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document || !dialectForUri(document.uri) || token.isCancellationRequested) {
    return [];
  }

  const diagnostics = documentDiagnostics.get(params.textDocument.uri) || [];
  const documentText = document.getText();
  if (token.isCancellationRequested) {
    return [];
  }
  
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
