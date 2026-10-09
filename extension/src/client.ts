import * as path from 'path';
import { ExtensionContext, window, workspace } from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;
let stopping: { client: LanguageClient; promise: Promise<void> } | undefined;

function stopLanguageClient(activeClient: LanguageClient): Promise<void> {
  if (client === activeClient) {
    client = undefined;
  }
  if (stopping?.client === activeClient) {
    return stopping.promise;
  }
  const promise = Promise.resolve().then(() => activeClient.stop());
  stopping = { client: activeClient, promise };
  void promise.then(
    () => {
      if (stopping?.promise === promise) stopping = undefined;
    },
    () => {
      if (stopping?.promise === promise) stopping = undefined;
    },
  );
  return promise;
}

export async function activateLanguageServer(context: ExtensionContext): Promise<void> {
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
  const fileEvents = workspace.createFileSystemWatcher('**/*.{simple.dsc.yaml,ssudo}');
  context.subscriptions.push(fileEvents);
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
      fileEvents
    }
  };

  // Create the language client and start the client
  const languageClient = new LanguageClient(
    'pedanticLanguageServer',
    'Pedantic Language Server',
    serverOptions,
    clientOptions
  );

  client = languageClient;
  try {
    await languageClient.start();
  } catch (error) {
    fileEvents.dispose();
    try {
      await stopLanguageClient(languageClient);
    } catch {
      // Startup errors are reported below.
    }
    const message = error instanceof Error ? error.message : String(error);
    window.showErrorMessage(`Pedantic: Language server failed to start: ${message}`);
    throw error;
  }

  context.subscriptions.push({
    dispose: () => {
      if (client === languageClient) {
        void deactivateLanguageServer().catch(error => {
          const message = error instanceof Error ? error.message : String(error);
          window.showErrorMessage(`Pedantic: Language server failed to stop: ${message}`);
        });
      }
    }
  });
}

export async function deactivateLanguageServer(): Promise<void> {
  if (!client) {
    if (stopping) {
      await stopping.promise;
    }
    return;
  }
  const activeClient = client;
  await stopLanguageClient(activeClient);
}
