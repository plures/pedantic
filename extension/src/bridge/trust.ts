export function requireTrustedWorkspace(isTrusted: boolean, showWarning: () => void): boolean {
  if (isTrusted) {
    return true;
  }

  showWarning();
  return false;
}

export async function invokeInTrustedWorkspace<T>(
  isTrusted: boolean,
  showWarning: () => void,
  operation: () => Promise<T>
): Promise<T | undefined> {
  if (!requireTrustedWorkspace(isTrusted, showWarning)) {
    return undefined;
  }

  return operation();
}
