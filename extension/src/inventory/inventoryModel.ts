/**
 * Data models for dynamic inventory system
 */

export interface HostVars {
  [key: string]: string | number | boolean | object | null;
}

export interface HostFacts {
  ansible_facts?: {
    [key: string]: string | number | boolean | object | null;
  };
  [key: string]: string | number | boolean | object | null | undefined;
}

export interface GroupVars {
  [key: string]: string | number | boolean | object | null;
}

export interface Host {
  name: string;
  vars?: HostVars;
  facts?: HostFacts;
  groups?: string[];
}

export interface HostGroup {
  name: string;
  hosts: string[];
  vars: GroupVars;
  children?: string[];
}

export interface Inventory {
  hosts: Host[];
  groups: HostGroup[];
  timestamp?: Date;
}

export interface ConfigPushTask {
  hostName: string;
  configPath: string;
  status: 'pending' | 'running' | 'success' | 'failed';
  progress: number;
  startTime?: Date;
  endTime?: Date;
  error?: string;
}

export interface HostLog {
  hostName: string;
  timestamp: Date;
  level: 'info' | 'warning' | 'error' | 'success';
  message: string;
  details?: any;
}
