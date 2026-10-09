import { EventEmitter } from 'node:events';
import * as assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { ChildProcess } from 'node:child_process';
import { PassThrough } from 'node:stream';
import type { Readable } from 'node:stream';
import * as path from 'node:path';
import type * as vscode from 'vscode';
import { PwshBridge } from '../src/bridge/pwshBridge';
import { bridgeProtocolVersion, BridgeRequest } from '../src/bridge/schema';

type FakeChild = ChildProcess & {
  stdout: Readable & EventEmitter;
  stderr: Readable & EventEmitter;
  kill(signal?: NodeJS.Signals): boolean;
};

function createChild(kill: () => boolean = () => true): FakeChild {
  const child = new EventEmitter() as unknown as FakeChild;
  Object.defineProperties(child, {
    pid: { value: 7351 },
    stdout: { value: new PassThrough() },
    stderr: { value: new PassThrough() },
    kill: { value: kill }
  });
  return child;
}

function createBridge(options: {
  platform?: NodeJS.Platform;
  getPwshPath?: () => string;
  onSpawn?: (child: FakeChild, executable: string) => void;
  onExecFile?: (file: string, args: readonly string[], callback: (error: Error | null) => void) => void;
  child?: FakeChild;
} = {}): PwshBridge {
  const extensionRoot = path.resolve(__dirname, '../..');
  const child = options.child ?? createChild();
  const spawn = ((executable: string) => {
    options.onSpawn?.(child, executable);
    return child;
  }) as unknown as typeof import('node:child_process').spawn;
  const execFile = ((file: string, args: readonly string[], _options: object, callback: (error: Error | null) => void) => {
    options.onExecFile?.(file, args, callback);
  }) as unknown as typeof import('node:child_process').execFile;

  return new PwshBridge({
    extensionUri: { fsPath: extensionRoot },
    asAbsolutePath: relativePath => path.join(extensionRoot, relativePath)
  }, {
    getPwshPath: options.getPwshPath ?? (() => 'pwsh'),
    spawn,
    execFile,
    platform: options.platform ?? 'win32'
  });
}

function request(timeout = 30000): BridgeRequest {
  return { command: 'prereqs', options: { timeout } };
}

async function waitForSpawn(getChild: () => FakeChild | undefined): Promise<FakeChild> {
  for (let attempt = 0; attempt < 100 && !getChild(); attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  const child = getChild();
  assert.ok(child, 'PowerShell child process should spawn');
  return child;
}

function cancellationToken(): {
  token: vscode.CancellationToken;
  cancel(): void;
  getDisposeCount(): number;
} {
  let listener: ((event: void) => void) | undefined;
  let disposeCount = 0;
  return {
    token: {
      onCancellationRequested: callback => {
        listener = callback;
        return { dispose: () => { disposeCount += 1; } };
      }
    } as vscode.CancellationToken,
    cancel: () => listener?.(undefined),
    getDisposeCount: () => disposeCount
  };
}

describe('PowerShell bridge process handling', () => {
  it('validates and spawns the same captured executable setting', async () => {
    let reads = 0;
    let spawnedPath: string | undefined;
    let child: FakeChild | undefined;
    const bridge = createBridge({
      getPwshPath: () => {
        reads += 1;
        return reads === 1 ? 'pwsh' : 'unvalidated-relative-path';
      },
      onSpawn: (spawned, executable) => {
        child = spawned;
        spawnedPath = executable;
      }
    });
    const responsePromise = bridge.invoke(request());
    const spawned = await waitForSpawn(() => child);
    spawned.stdout.emit('data', Buffer.from(JSON.stringify({
      protocolVersion: bridgeProtocolVersion,
      success: true
    })));
    spawned.emit('close', 0);
    const response = await responsePromise;

    assert.equal(reads, 1);
    assert.equal(spawnedPath, 'pwsh');
    assert.equal(response.success, true);
  });

  it('returns a timeout after successfully terminating the process tree', async () => {
    let child: FakeChild | undefined;
    let taskkillArgs: readonly string[] | undefined;
    const bridge = createBridge({
      onSpawn: spawned => { child = spawned; },
      onExecFile: (_file, args, callback) => {
        taskkillArgs = args;
        callback(null);
      }
    });

    const response = await bridge.invoke(request(1));

    assert.equal(response.success, false);
    assert.match(response.errors?.[0] ?? '', /timed out/);
    assert.deepEqual(taskkillArgs, ['/PID', '7351', '/T', '/F']);
    assert.ok(child);
  });

  it('surfaces cleanup failure and attempts to terminate the direct process', async () => {
    let child: FakeChild | undefined;
    let directKillCount = 0;
    const proc = createChild(() => {
      directKillCount += 1;
      return true;
    });
    const bridge = createBridge({
      child: proc,
      onSpawn: spawned => { child = spawned; },
      onExecFile: (_file, _args, callback) => callback(new Error('taskkill failed'))
    });

    const response = await bridge.invoke(request(1));

    assert.equal(child, proc);
    assert.equal(directKillCount, 1);
    assert.match(response.errors?.join(' ') ?? '', /process-tree cleanup failed/);
  });

  it('settles cancellation once after process-tree cleanup', async () => {
    let taskkillCount = 0;
    const cancellation = cancellationToken();
    let child: FakeChild | undefined;
    const bridge = createBridge({
      onSpawn: spawned => { child = spawned; },
      onExecFile: (_file, _args, callback) => {
        taskkillCount += 1;
        callback(null);
      }
    });
    const responsePromise = bridge.invoke(request(), cancellation.token);

    const spawned = await waitForSpawn(() => child);
    cancellation.cancel();
    const response = await responsePromise;
    spawned.emit('close', 0);

    assert.deepEqual(response, {
      protocolVersion: bridgeProtocolVersion,
      success: false,
      errors: ['PowerShell bridge operation was cancelled.']
    });
    assert.equal(taskkillCount, 1);
    assert.equal(cancellation.getDisposeCount(), 1);
  });

  it('reports child spawn errors', async () => {
    let child: FakeChild | undefined;
    const bridge = createBridge({ onSpawn: spawned => { child = spawned; } });
    const responsePromise = bridge.invoke(request());

    const spawned = await waitForSpawn(() => child);
    spawned.emit('error', new Error('spawn failed'));

    const response = await responsePromise;
    assert.equal(response.success, false);
    assert.match(response.errors?.[0] ?? '', /spawn failed/);
  });

  it('rejects malformed process output and ignores later settlement events', async () => {
    let child: FakeChild | undefined;
    const cancellation = cancellationToken();
    const bridge = createBridge({
      onSpawn: spawned => { child = spawned; }
    });
    const responsePromise = bridge.invoke(request(), cancellation.token);

    const spawned = await waitForSpawn(() => child);
    spawned.stdout.emit('data', Buffer.from('not-json\n'));
    spawned.emit('close', 0);
    const response = await responsePromise;
    spawned.emit('error', new Error('late spawn error'));

    assert.equal(response.success, false);
    assert.match(response.errors?.join(' ') ?? '', /incompatible response/);
    assert.equal(cancellation.getDisposeCount(), 1);
  });
});
