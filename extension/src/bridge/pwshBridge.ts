/// <reference types="node" />
import { setTimeout, clearTimeout } from 'node:timers';
import { execFile, spawn } from 'child_process';
import type * as vscode from 'vscode';
import { ExtensionAssetContext, resolveBridgeAsset, validateBridgeAsset, validatePwshExecutable } from './assets';
import { bridgeProtocolVersion, BridgeRequest, BridgeResponse, parseBridgeResponse } from './schema';
import { BoundedOutput, redactDiagnostic } from './output';

const maximumOutputBytes = 64 * 1024;

interface BridgeDependencies {
  getPwshPath(): string;
  spawn: typeof spawn;
  execFile: typeof execFile;
  platform: NodeJS.Platform;
}

export class PwshBridge {
  private readonly bridgePath: string;
  private readonly dependencies: BridgeDependencies;

  constructor(
    context: ExtensionAssetContext,
    dependencies: Pick<BridgeDependencies, 'getPwshPath'> & Partial<Omit<BridgeDependencies, 'getPwshPath'>>
  ) {
    this.bridgePath = resolveBridgeAsset(context);
    this.dependencies = {
      getPwshPath: dependencies.getPwshPath,
      spawn: dependencies.spawn ?? spawn,
      execFile: dependencies.execFile ?? execFile,
      platform: dependencies.platform ?? process.platform
    };
  }

  async invoke(request: BridgeRequest, cancellationToken?: vscode.CancellationToken): Promise<BridgeResponse> {
    let pwshPath: string;
    try {
      pwshPath = this.dependencies.getPwshPath();
      await validateBridgeAsset(this.bridgePath);
      await validatePwshExecutable(pwshPath);
    } catch (error) {
      return bridgeFailure(error);
    }

  const timeout = request.options?.timeout || 30000;

  const args = [
    '-NoProfile', '-NonInteractive',
    '-File', this.bridgePath,
    '-Command', request.command,
    '-ProtocolVersion', bridgeProtocolVersion.toString(),
    '-OutputJson'
  ];

  if (request.dslPath) {
    args.push('-DslPath', request.dslPath);
  }

  if (request.resourceTypes && request.resourceTypes.length > 0) {
    args.push('-ResourceTypes', request.resourceTypes.join(','));
  }

  if (request.resourceType) {
    args.push('-ResourceType', request.resourceType);
  }
  
  if (request.options?.whatIf) {
    args.push('-WhatIf');
  }
  
  if (request.options?.verbose) {
    args.push('-VerboseOutput');
  }
  
  return new Promise(resolve => {
    const proc = this.dependencies.spawn(pwshPath, args, { detached: this.dependencies.platform !== 'win32' });
    const stdout = new BoundedOutput(maximumOutputBytes);
    const stderr = new BoundedOutput(maximumOutputBytes);
    let timedOut = false;
    let cancelled = false;
    let completed = false;
    const finish = (response: BridgeResponse) => {
      if (completed) {
        return;
      }
      completed = true;
      clearTimeout(timer);
      cancellationDisposable?.dispose();
      resolve(response);
    };

    const terminate = (reason: 'cancelled' | 'timeout') => {
      if (completed || timedOut || cancelled) {
        return;
      }
      timedOut = reason === 'timeout';
      cancelled = reason === 'cancelled';
      void terminateProcessTree(proc, this.dependencies).then(
        () => finishTermination(),
        () => {
          try {
            proc.kill('SIGKILL');
          } catch {
            // The cleanup failure is returned to the caller below.
          }
          finishTermination(true);
        }
      );
    };

    const finishTermination = (cleanupFailed = false) => {
      const cleanupError = cleanupFailed
        ? ['PowerShell process-tree cleanup failed; a direct-process termination fallback was attempted.']
        : [];
      if (timedOut) {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: [`PowerShell process timed out after ${timeout}ms`, ...cleanupError]
        });
      } else {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: ['PowerShell bridge operation was cancelled.', ...cleanupError]
        });
      }
    };

    const timer = setTimeout(() => {
      terminate('timeout');
    }, timeout);
    const cancellationDisposable = cancellationToken?.onCancellationRequested(() => {
      terminate('cancelled');
    });
    
    proc.stdout.on('data', data => stdout.append(data));
    proc.stderr.on('data', data => stderr.append(data));
    
    proc.on('close', code => {
      if (timedOut) {
        return;
      }
      if (cancelled) {
        return;
      }
      
      try {
        if (stdout.wasTruncated || stderr.wasTruncated) {
          throw new Error(`PowerShell bridge output exceeded ${maximumOutputBytes} bytes.`);
        }
        const lines = stdout.text.trimEnd().split(/\r?\n/).filter(line => line.trim().length > 0);
        if (lines.length === 0) {
          throw new Error('PowerShell bridge returned no JSON response.');
        }
        finish(parseBridgeResponse(JSON.parse(lines[lines.length - 1])));
      } catch (error) {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: [
            `PowerShell bridge returned an incompatible response: ${error instanceof Error ? error.message : String(error)}`,
            redactDiagnostic(stderr.text || stdout.text || `Process exited with code ${code}`)
          ].filter(Boolean)
        });
      }
    });
    
    proc.on('error', err => {
      if (timedOut || cancelled) {
        return;
      }
      finish(bridgeFailure(new Error(`PowerShell bridge failed: ${err.message}`)));
    });
  });
  }
}

function terminateProcessTree(proc: ReturnType<typeof spawn>, dependencies: BridgeDependencies): Promise<void> {
  if (proc.pid === undefined) {
    return Promise.reject(new Error('PowerShell process has no PID.'));
  }

  if (dependencies.platform === 'win32') {
    return new Promise((resolve, reject) => {
      dependencies.execFile('taskkill', ['/PID', String(proc.pid), '/T', '/F'], { windowsHide: true }, error => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }

  try {
    process.kill(-proc.pid, 'SIGKILL');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ESRCH') {
      return Promise.resolve();
    }
    return Promise.reject(error);
  }
  return Promise.resolve();
}

function bridgeFailure(error: unknown): BridgeResponse {
  return {
    protocolVersion: bridgeProtocolVersion,
    success: false,
    errors: [error instanceof Error ? error.message : String(error)]
  };
}
