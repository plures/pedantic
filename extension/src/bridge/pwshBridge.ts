import { spawn } from 'child_process';
import * as path from 'path';
import * as vscode from 'vscode';
import { BridgeRequest, BridgeResponse } from './schema';

/**
 * Invokes PowerShell to execute DSC operations
 */
export async function invokePwsh(request: BridgeRequest): Promise<BridgeResponse> {
  const config = vscode.workspace.getConfiguration('pedantic');
  const pwshPath = config.get<string>('bridge.pwshPath', 'pwsh');
  const timeout = request.options?.timeout || 30000;
  
  // Find the bridge script in the scripts directory (at repo root)
  const extensionPath = path.dirname(path.dirname(path.dirname(__dirname)));
  const scriptPath = path.join(extensionPath, 'scripts', 'bridge.ps1');
  
  const args = [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', scriptPath,
    '-Command', request.command,
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
  
  return new Promise((resolve, reject) => {
    const proc = spawn(pwshPath, args);
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    
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
    
    proc.stdout.on('data', data => stdout += data.toString());
    proc.stderr.on('data', data => stderr += data.toString());
    
    proc.on('close', code => {
      clearTimeout(timer);
      
      if (timedOut) {
        resolve({
          success: false,
          errors: [`PowerShell process timed out after ${timeout}ms`]
        });
        return;
      }
      
      try {
        // Try to parse JSON response
        const response: BridgeResponse = JSON.parse(stdout);
        resolve(response);
      } catch {
        // Fallback for non-JSON output
        if (code === 0) {
          resolve({ 
            success: true, 
            output: stdout,
            errors: stderr ? [stderr] : []
          });
        } else {
          resolve({ 
            success: false, 
            errors: [stderr || stdout || `Process exited with code ${code}`] 
          });
        }
      }
    });
    
    proc.on('error', err => {
      clearTimeout(timer);
      reject(new Error(`PowerShell bridge failed: ${err.message}`));
    });
  });
}
