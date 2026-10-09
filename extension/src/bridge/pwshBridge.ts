/// <reference types="node" />
import { setTimeout, clearTimeout } from 'node:timers';
import { execFile, spawn } from 'child_process';
import * as vscode from 'vscode';
import { ExtensionAssetContext, resolveBridgeAsset, validateBridgeAsset, validatePwshExecutable } from './assets';
import { bridgeProtocolVersion, BridgeRequest, BridgeResponse, parseBridgeResponse } from './schema';
import { BoundedOutput, redactDiagnostic } from './output';

const maximumOutputBytes = 64 * 1024;

export class PwshBridge {
  private readonly bridgePath: string;

  constructor(context: ExtensionAssetContext) {
    this.bridgePath = resolveBridgeAsset(context);
  }

  async invoke(request: BridgeRequest, cancellationToken?: vscode.CancellationToken): Promise<BridgeResponse> {
    try {
      await validateBridgeAsset(this.bridgePath);
      await validatePwshExecutable(vscode.workspace.getConfiguration('pedantic').get<string>('bridge.pwshPath', 'pwsh'));
    } catch (error) {
      return bridgeFailure(error);
    }

  const pwshPath = vscode.workspace.getConfiguration('pedantic').get<string>('bridge.pwshPath', 'pwsh');
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
    const proc = spawn(pwshPath, args, { detached: process.platform !== 'win32' });
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
      void terminateProcessTree(proc).finally(finishTermination);
    };

    const finishTermination = () => {
      if (timedOut) {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: [`PowerShell process timed out after ${timeout}ms`]
        });
      } else {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: ['PowerShell bridge operation was cancelled.']
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

function terminateProcessTree(proc: ReturnType<typeof spawn>): Promise<void> {
  if (proc.pid === undefined) {
    return Promise.resolve();
  }

  if (process.platform === 'win32') {
    return new Promise(resolve => {
      execFile('taskkill', ['/PID', String(proc.pid), '/T', '/F'], { windowsHide: true }, () => resolve());
    });
  }

  try {
    process.kill(-proc.pid, 'SIGKILL');
  } catch {
    proc.kill('SIGKILL');
  }
  return Promise.resolve();
}

export function createPwshBridge(context: ExtensionAssetContext): PwshBridge {
  return new PwshBridge(context);
}

function bridgeFailure(error: unknown): BridgeResponse {
  return {
    protocolVersion: bridgeProtocolVersion,
    success: false,
    errors: [error instanceof Error ? error.message : String(error)]
  };
}
