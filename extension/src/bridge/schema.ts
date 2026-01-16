// JSON schema for PowerShell bridge communication

export interface BridgeRequest {
  command: 'generate' | 'test' | 'set';
  dslPath: string;
  options?: {
    whatIf?: boolean;
    verbose?: boolean;
    timeout?: number; // milliseconds
  };
}

export interface BridgeResponse {
  success: boolean;
  output?: string; // DSC YAML or result
  errors?: string[];
  warnings?: string[];
  duration?: number; // milliseconds
}
