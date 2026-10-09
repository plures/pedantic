import { constants } from 'node:fs';
import { access, stat } from 'node:fs/promises';
import * as path from 'node:path';

export const bridgeAssetRelativePath = path.join('bridge', 'bridge.ps1');

export interface ExtensionAssetContext {
  readonly extensionUri: { fsPath: string };
  asAbsolutePath(relativePath: string): string;
}

export function resolveBridgeAsset(context: ExtensionAssetContext): string {
  const extensionRoot = path.resolve(context.extensionUri.fsPath);
  const bridgePath = path.resolve(context.asAbsolutePath(bridgeAssetRelativePath));
  const relativePath = path.relative(extensionRoot, bridgePath);

  if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
    throw new Error('Pedantic bridge asset resolved outside the installed extension directory.');
  }

  return bridgePath;
}

export async function validateBridgeAsset(bridgePath: string): Promise<void> {
  try {
    await access(bridgePath, constants.R_OK);
    if (!(await stat(bridgePath)).isFile() || path.extname(bridgePath).toLowerCase() !== '.ps1') {
      throw new Error('not a PowerShell script');
    }
  } catch {
    throw new Error(
      `Pedantic PowerShell bridge is missing or unreadable at "${bridgePath}". Reinstall the Pedantic extension.`,
    );
  }
}

export async function validatePwshExecutable(pwshPath: string): Promise<void> {
  if (pwshPath === 'pwsh') {
    return;
  }

  if (!path.isAbsolute(pwshPath)) {
    throw new Error('Pedantic PowerShell executable must be "pwsh" or an absolute path.');
  }

  try {
    if (!(await stat(pwshPath)).isFile()) {
      throw new Error('not a file');
    }
    await access(pwshPath, constants.X_OK);
  } catch {
    throw new Error(`Pedantic PowerShell executable is missing or not executable at "${pwshPath}".`);
  }
}
