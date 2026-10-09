import * as assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { describe, it } from 'node:test';

type ModuleLoader = (request: string, parent: unknown, isMain?: boolean) => unknown;
const moduleRequire = createRequire(__filename);
const moduleLoader = moduleRequire('node:module') as { _load: ModuleLoader };
const originalLoad = moduleLoader._load;
let stopBehavior: () => Promise<void> = async () => undefined;
let stopCalls = 0;
const errorMessages: string[] = [];

class MockLanguageClient {
  constructor(_id: string, _name: string, _serverOptions: unknown, _clientOptions: unknown) {}

  async start(): Promise<void> {}

  stop(): Promise<void> {
    stopCalls += 1;
    return stopBehavior();
  }
}

const vscodeMock = {
  window: {
    showErrorMessage: (message: string) => errorMessages.push(message),
  },
  workspace: {
    createFileSystemWatcher: () => ({ dispose: () => undefined }),
  },
};

moduleLoader._load = function (request, parent, isMain) {
  if (request === 'vscode') return vscodeMock;
  if (request === 'vscode-languageclient/node') {
    return { LanguageClient: MockLanguageClient, TransportKind: { ipc: 1 } };
  }
  return originalLoad(request, parent, isMain);
};
const { activateLanguageServer, deactivateLanguageServer } = moduleRequire('../src/client') as typeof import('../src/client');
moduleLoader._load = originalLoad;

function context(): import('vscode').ExtensionContext {
  return {
    asAbsolutePath: (relativePath: string) => relativePath,
    subscriptions: [],
  } as unknown as import('vscode').ExtensionContext;
}

function resetMocks(): void {
  stopBehavior = async () => undefined;
  stopCalls = 0;
  errorMessages.length = 0;
}

describe('language server lifecycle', () => {
  it('shares an in-flight stop between disposal and explicit deactivation', async () => {
    resetMocks();
    let finishStop!: () => void;
    stopBehavior = () => new Promise(resolve => {
      finishStop = resolve;
    });
    const extensionContext = context();
    await activateLanguageServer(extensionContext);

    extensionContext.subscriptions.at(-1)?.dispose();
    const deactivation = deactivateLanguageServer();
    let settled = false;
    void deactivation.then(() => { settled = true; });
    await new Promise<void>(resolve => setImmediate(resolve));

    assert.equal(stopCalls, 1);
    assert.equal(settled, false);
    finishStop();
    await deactivation;
    assert.equal(settled, true);
  });

  it('handles a rejected stop initiated by subscription disposal', async () => {
    resetMocks();
    let failStop!: (error: Error) => void;
    stopBehavior = () => new Promise((_, reject) => {
      failStop = reject;
    });
    const extensionContext = context();
    await activateLanguageServer(extensionContext);

    extensionContext.subscriptions.at(-1)?.dispose();
    await new Promise<void>(resolve => setImmediate(resolve));
    failStop(new Error('stop failed'));
    await new Promise<void>(resolve => setImmediate(resolve));

    assert.equal(stopCalls, 1);
    assert.deepEqual(errorMessages, ['Pedantic: Language server failed to stop: stop failed']);
  });
});
