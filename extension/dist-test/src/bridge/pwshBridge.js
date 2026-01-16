"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.invokePwsh = invokePwsh;
const child_process_1 = require("child_process");
const path = __importStar(require("path"));
const vscode = __importStar(require("vscode"));
/**
 * Invokes PowerShell to execute DSC operations
 */
async function invokePwsh(request) {
    const config = vscode.workspace.getConfiguration('pedantic');
    const pwshPath = config.get('bridge.pwshPath', 'pwsh');
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
        const proc = (0, child_process_1.spawn)(pwshPath, args, { timeout });
        let stdout = '';
        let stderr = '';
        proc.stdout.on('data', data => stdout += data.toString());
        proc.stderr.on('data', data => stderr += data.toString());
        proc.on('close', code => {
            try {
                // Try to parse JSON response
                const response = JSON.parse(stdout);
                resolve(response);
            }
            catch {
                // Fallback for non-JSON output
                if (code === 0) {
                    resolve({
                        success: true,
                        output: stdout,
                        errors: stderr ? [stderr] : []
                    });
                }
                else {
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
