/// <reference types="node" />
import { setTimeout, clearTimeout } from 'node:timers';
import { spawn } from 'child_process';
import * as vscode from 'vscode';
import { ExtensionAssetContext, resolveBridgeAsset, validateBridgeAsset } from './assets';
import { bridgeProtocolVersion, BridgeRequest, BridgeResponse, parseBridgeResponse } from './schema';

export class PwshBridge {
  private readonly bridgePath: string;

  constructor(context: ExtensionAssetContext) {
    this.bridgePath = resolveBridgeAsset(context);
  }

  async invoke(request: BridgeRequest, cancellationToken?: vscode.CancellationToken): Promise<BridgeResponse> {
    try {
      await validateBridgeAsset(this.bridgePath);
    } catch (error) {
      return bridgeFailure(error);
    }

  const config = vscode.workspace.getConfiguration('pedantic');
  const pwshPath = config.get<string>('bridge.pwshPath', 'pwsh');
  const timeout = request.options?.timeout || 30000;

  const args = [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
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
    const proc = spawn(pwshPath, args);
    let stdout = '';
    let stderr = '';
    let timedOut = false;
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
    
    // Manually implement timeout with process termination
    const timer = setTimeout(() => {
      timedOut = true;
      proc.kill('SIGTERM');
      // Force kill if SIGTERM doesn't work
      setTimeout(() => {
        if (!proc.killed) {
          proc.kill('SIGKILL');
        }
      }, 1000);
    }, timeout);
    const cancellationDisposable = cancellationToken?.onCancellationRequested(() => {
      proc.kill('SIGTERM');
      finish({
        protocolVersion: bridgeProtocolVersion,
        success: false,
        errors: ['PowerShell bridge operation was cancelled.']
      });
    });
    
    proc.stdout.on('data', data => stdout += data.toString());
    proc.stderr.on('data', data => stderr += data.toString());
    
    proc.on('close', code => {
      if (timedOut) {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: [`PowerShell process timed out after ${timeout}ms`]
        });
        return;
      }
      
      try {
        finish(parseBridgeResponse(JSON.parse(stdout)));
      } catch (error) {
        finish({
          protocolVersion: bridgeProtocolVersion,
          success: false,
          errors: [
            `PowerShell bridge returned an incompatible response: ${error instanceof Error ? error.message : String(error)}`,
            stderr || stdout || `Process exited with code ${code}`
          ].filter(Boolean)
        });
      }
    });
    
    proc.on('error', err => {
      finish(bridgeFailure(new Error(`PowerShell bridge failed: ${err.message}`)));
    });
  });
  }
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
