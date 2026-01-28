// JSON schema for PowerShell bridge communication

export interface BridgeRequest {
  command: 'generate' | 'test' | 'set' | 'prereqs' | 'resources' | 'installResource' | 'cmdb';
  dslPath?: string;
  resourceTypes?: string[];
  resourceType?: string;
  catalogPath?: string;
  includeResources?: boolean;
  options?: {
    whatIf?: boolean;
    verbose?: boolean;
    timeout?: number; // milliseconds
  };
}

export interface BridgeResponse {
  success: boolean;
  output?: string; // DSC YAML or result
  data?: any;
  errors?: string[];
  warnings?: string[];
  duration?: number; // milliseconds
}
