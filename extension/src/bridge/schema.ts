export const bridgeProtocolVersion = 1;

export interface BridgeRequest {
  protocolVersion?: typeof bridgeProtocolVersion;
  command: 'generate' | 'test' | 'set' | 'prereqs' | 'resources' | 'installResource';
  dslPath?: string;
  resourceTypes?: string[];
  resourceType?: string;
  options?: {
    whatIf?: boolean;
    verbose?: boolean;
    timeout?: number; // milliseconds
  };
}

export interface BridgeResponse {
  protocolVersion: typeof bridgeProtocolVersion;
  success: boolean;
  output?: string; // DSC YAML or result
  data?: any;
  errors?: string[];
  warnings?: string[];
  duration?: number; // milliseconds
}

export function parseBridgeResponse(value: unknown): BridgeResponse {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('bridge response must be a JSON object');
  }

  const response = value as Record<string, unknown>;
  if (response.protocolVersion !== bridgeProtocolVersion) {
    throw new Error(
      `bridge protocol version ${String(response.protocolVersion)} is incompatible with extension protocol version ${bridgeProtocolVersion}`,
    );
  }
  if (typeof response.success !== 'boolean') {
    throw new Error('bridge response field "success" must be a boolean');
  }
  for (const field of ['errors', 'warnings']) {
    if (response[field] !== undefined && (!Array.isArray(response[field]) || !response[field].every(item => typeof item === 'string'))) {
      throw new Error(`bridge response field "${field}" must be an array of strings`);
    }
  }

  return response as unknown as BridgeResponse;
}
