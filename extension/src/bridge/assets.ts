import { constants } from 'node:fs';
import { access } from 'node:fs/promises';
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
  } catch {
    throw new Error(
      `Pedantic PowerShell bridge is missing or unreadable at "${bridgePath}". Reinstall the Pedantic extension.`,
    );
  }
}
