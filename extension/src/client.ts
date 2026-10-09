import * as path from 'path';
import { ExtensionContext, workspace } from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export function activateLanguageServer(context: ExtensionContext): void {
  // The server is implemented in Node
  const serverModule = context.asAbsolutePath(
    path.join('dist', 'server', 'server.js')
  );

  // The debug options for the server
  const debugOptions = { execArgv: ['--nolazy', '--inspect=6009'] };

  // If the extension is launched in debug mode then the debug server options are used
  // Otherwise the run options are used
  const serverOptions: ServerOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: debugOptions
    }
  };

  // Options to control the language client
  const clientOptions: LanguageClientOptions = {
    // Register the server for Simple DSL and SudoLang files
    documentSelector: [
      { scheme: 'file', language: 'pedantic-simple-dsc' },
      { scheme: 'file', language: 'pedantic-sudolang' }
    ],
    synchronize: {
      // Synchronize the setting section 'pedantic' to the server
      configurationSection: 'pedantic',
      // Notify the server about file changes to DSC files
      fileEvents: workspace.createFileSystemWatcher('**/*.{simple.dsc.yaml,ssudo}')
    }
  };

  // Create the language client and start the client
  client = new LanguageClient(
    'pedanticLanguageServer',
    'Pedantic Language Server',
    serverOptions,
    clientOptions
  );

  // Start the client. This will also launch the server
  client.start();
}

export function deactivateLanguageServer(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
