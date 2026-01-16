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
    '-DslPath', request.dslPath,
    '-OutputJson'
  ];
  
  if (request.options?.whatIf) {
    args.push('-WhatIf');
  }
  
  if (request.options?.verbose) {
    args.push('-Verbose');
  }
  
  return new Promise((resolve, reject) => {
    const proc = spawn(pwshPath, args, { timeout });
    let stdout = '';
    let stderr = '';
    
    proc.stdout.on('data', data => stdout += data.toString());
    proc.stderr.on('data', data => stderr += data.toString());
    
    proc.on('close', code => {
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
      reject(new Error(`PowerShell bridge failed: ${err.message}`));
    });
  });
}
