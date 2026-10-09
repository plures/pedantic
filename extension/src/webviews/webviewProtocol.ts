export interface InventoryResourceRow {
  type?: string;
  Type?: string;
  name?: string;
  Key?: string;
  version?: string;
  Version?: string;
  source?: string;
  Source?: string;
  path?: string;
  Path?: string;
}

export interface InventoryPayload {
  command: 'inventoryData';
  data: {
    dscInstalled?: boolean;
    dscVersion?: string;
    commonResources?: {
      requested: string[];
      available?: string[];
      missing?: string[];
      success?: boolean;
    };
    installed?: InventoryResourceRow[];
    cached?: InventoryResourceRow[];
  };
}

export interface GraphPayload {
  command: 'graphData';
  nodes: Array<{ id: string; label: string; type: string }>;
  edges: Array<{ from: string; to: string; kind: string }>;
  diagnostics: Array<{ code: string; message: string; severity: string }>;
}

export interface ReadyMessage {
  command: 'ready';
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  return Object.keys(value).every(key => keys.includes(key));
}

function stringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(item => typeof item === 'string');
}

function resourceRow(value: unknown): value is InventoryResourceRow {
  const row = record(value);
  return row !== undefined
    && hasOnlyKeys(row, ['type', 'Type', 'name', 'Key', 'version', 'Version', 'source', 'Source', 'path', 'Path'])
    && Object.values(row).every(field => typeof field === 'string');
}

export function isInventoryPayload(value: unknown): value is InventoryPayload {
  const message = record(value);
  if (!message || !hasOnlyKeys(message, ['command', 'data']) || message.command !== 'inventoryData') {
    return false;
  }
  const data = record(message.data);
  if (!data || !hasOnlyKeys(data, ['dscInstalled', 'dscVersion', 'commonResources', 'installed', 'cached'])) {
    return false;
  }
  if (data.dscInstalled !== undefined && typeof data.dscInstalled !== 'boolean') return false;
  if (data.dscVersion !== undefined && typeof data.dscVersion !== 'string') return false;
  if (data.installed !== undefined && (!Array.isArray(data.installed) || !data.installed.every(resourceRow))) return false;
  if (data.cached !== undefined && (!Array.isArray(data.cached) || !data.cached.every(resourceRow))) return false;
  if (data.commonResources !== undefined) {
    const common = record(data.commonResources);
    if (!common || !hasOnlyKeys(common, ['requested', 'available', 'missing', 'success'])
      || !stringArray(common.requested)
      || (common.available !== undefined && !stringArray(common.available))
      || (common.missing !== undefined && !stringArray(common.missing))
      || (common.success !== undefined && typeof common.success !== 'boolean')) return false;
  }
  return true;
}

export function isGraphPayload(value: unknown): value is GraphPayload {
  const message = record(value);
  if (!message || !hasOnlyKeys(message, ['command', 'nodes', 'edges', 'diagnostics']) || message.command !== 'graphData'
    || !Array.isArray(message.nodes) || !Array.isArray(message.edges) || !Array.isArray(message.diagnostics)) return false;
  return message.nodes.every(node => {
    const item = record(node);
    return item && hasOnlyKeys(item, ['id', 'label', 'type'])
      && typeof item.id === 'string' && typeof item.label === 'string' && typeof item.type === 'string';
  }) && message.edges.every(edge => {
    const item = record(edge);
    return item && hasOnlyKeys(item, ['from', 'to', 'kind'])
      && typeof item.from === 'string' && typeof item.to === 'string' && typeof item.kind === 'string';
  }) && message.diagnostics.every(diagnostic => {
    const item = record(diagnostic);
    return item && hasOnlyKeys(item, ['code', 'message', 'severity'])
      && typeof item.code === 'string' && typeof item.message === 'string' && typeof item.severity === 'string';
  });
}

export function isReadyMessage(value: unknown): value is ReadyMessage {
  const message = record(value);
  return message !== undefined
    && hasOnlyKeys(message, ['command'])
    && message.command === 'ready';
}

export function isRevealNodeMessage(value: unknown): value is { command: 'revealNode'; nodeId: string } {
  const message = record(value);
  return message !== undefined
    && hasOnlyKeys(message, ['command', 'nodeId'])
    && message.command === 'revealNode'
    && typeof message.nodeId === 'string'
    && message.nodeId.length > 0;
}
