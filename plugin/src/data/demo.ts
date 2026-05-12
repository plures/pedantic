import type { TimeSeriesPoint } from '@plures/design-dojo';

const agentHostClusterYaml = `$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json

name: AgentHostCluster
version: 1.0.0
parameters:
- name: VmSwitchAdapter
  type: string
- name: CsvRoot
  type: string
resources:
# --- Ensure Hyper-V role present ---
- name: HyperVFeature
  type: PSDesiredStateConfiguration/WindowsFeature
  properties:
    Name: Hyper-V
    Ensure: Present
    IncludeAllSubFeature: true
# --- Ensure Failover-Clustering role (for clustered hosts) ---
- name: ClusterFeature
  type: PSDesiredStateConfiguration/WindowsFeature
  properties:
    Name: Failover-Clustering
    Ensure: Present
    IncludeAllSubFeature: false
# --- Create external VMSwitch ---
- name: ExternalVSwitch
  type: HyperVDsc/VMSwitch
  dependsOn:
  - '[WindowsFeature]HyperVFeature'
  properties:
    Name: External
    SwitchType: External
    NetAdapterName: "[Parameter('VmSwitchAdapter')]"
    EnableIov: true
# --- Ensure CSV storage directories exist ---
- name: CsvFolders
  type: PSDesiredStateConfiguration/File
  properties:
    DestinationPath: "[Parameter('CsvRoot')]\\VMs"
    Type: Directory
    Ensure: Present
# another directory
- name: CsvHdFolders
  type: PSDesiredStateConfiguration/File
  properties:
    DestinationPath: "[Parameter('CsvRoot')]\\VMHardDrives"
    Type: Directory
    Ensure: Present
`;

const agentVmGuestYaml = `$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json

name: AgentVmGuest
version: 1.0.0
parameters:
  SshPort:
    type: integer
    default: 22
  Port:
    type: int # alias
resources:
# --- Ensure OpenSSH configuration & CA trust ---
- name: OpenSshConfig
  type: Microsoft.Windows/WindowsPowerShell
  dependsOn: []
  properties:
    resources:
    - name: CopyCaPubKey
      type: PSDesiredStateConfiguration/File
      properties:
        DestinationPath: 'C:\\ProgramData\\ssh\\ca_authorized_keys'
        Ensure: Present
        Type: File
        SourcePath: 'C:\\DscConfigs\\Artifacts\\ssh\\ca_authorized_keys'
    - name: SshdConfig
      type: PSDesiredStateConfiguration/File
      properties:
        DestinationPath: 'C:\\ProgramData\\ssh\\sshd_config'
        Ensure: Present
        Type: File
        SourcePath: 'C:\\DscArtifacts\\ssh\\sshd_config'
# --- Import Bootstrap Certificates ---
- name: ImportPfx
  type: CertificateDsc/PfxImport
  dependsOn: []
  properties:
    Thumbprint: ''   # to be supplied via parameter file
    Location: LocalMachine
    Path: 'C:\\DscConfigs\\Artifacts\\certs\\bootstrap.pfx'
    Store: My
    Password: "[Parameter('PfxPassword')]"
# --- Register DSC to Automation Account (ScheduledTask) ---
- name: RegistrationTask
  type: ScheduledTaskDsc/ScheduledTask
  properties:
    TaskName: 'RegistrationDSC'
    ActionExecutable: 'powershell.exe'
    ActionArguments: '-ExecutionPolicy Bypass -File C:\\DscScripts\\RegistrationMetaConfigV2.signed.ps1 -Url ${AutomationAccountUrl} -Key ${DscKey} -Configuration ${DscConfiguration}'
    ScheduleType: AtStartup
    RandomDelay: '00:00:30'
    RunLevel: Highest
    User: SYSTEM
# --- Placeholder for additional guest config (networking/firewall) ---
- name: GuestNetwork
  type: Microsoft.Windows/WindowsPowerShell
  properties:
    resources: []
# --- Generate OpenSSH host keys and ensure sshd_config ---
- name: GenerateHostKeys
  type: PSDesiredStateConfiguration/Script
  dependsOn:
    - CopyCaPubKey
  properties:
    GetScript: |
      if (Test-Path 'C:\\ProgramData\\ssh\\ssh_host_ed25519_key') { 'Exists' } else { 'Missing' }
    TestScript: |
      Test-Path 'C:\\ProgramData\\ssh\\ssh_host_ed25519_key'
    SetScript: |
      if (-not (Get-Service -Name sshd -ErrorAction SilentlyContinue)) {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
      }
      New-Item -ItemType Directory -Path C:\\ProgramData\\ssh -Force | Out-Null
      & ssh-keygen -t ed25519 -f C:\\ProgramData\\ssh\\ssh_host_ed25519_key -N ''
      Set-Content -Path C:\\ProgramData\\ssh\\sshd_config -Value (
        @(
          "Port ${SshPort}",
          'HostKey C:/ProgramData/ssh/ssh_host_ed25519_key',
          'HostCertificate C:/ProgramData/ssh/ssh_host_ed25519_key-cert.pub',
          'PasswordAuthentication yes',
          'Subsystem powershell pwsh.exe -sshs',
          'Subsystem sftp sftp-server.exe',
          'TrustedUserCAKeys C:/ProgramData/ssh/ca_authorized_keys'
        ) -join "`n") -Encoding ascii
      Restart-Service sshd -Force
`;

export const demoConfigs = [
  {
    id: 'agent-host-cluster',
    name: 'AgentHostCluster',
    version: '1.0.0',
    description: 'Hyper-V host clustering baseline with CSV storage and external switch.',
    status: 'validated',
    resource_count: 5,
    yaml: agentHostClusterYaml,
    validation: {
      status: 'ok',
      errors: [],
    },
    plan: {
      summary: 'All resources in desired state. No changes required.',
      steps: [
        { id: 'HyperVFeature', action: 'noop', detail: 'Hyper-V already present' },
        { id: 'ClusterFeature', action: 'noop', detail: 'Failover-Clustering already present' },
        { id: 'ExternalVSwitch', action: 'noop', detail: 'External switch configured' },
        { id: 'CsvFolders', action: 'noop', detail: 'CSV folder already exists' },
        { id: 'CsvHdFolders', action: 'noop', detail: 'VMHardDrives folder already exists' },
      ],
    },
    praxis: {
      status: 'clean',
      firedRules: ['overdue-compliance', 'drift-escalation'],
      violations: [],
      messages: ['All compliance checks within drift threshold.'],
    },
  },
  {
    id: 'agent-vm-guest',
    name: 'AgentVmGuest',
    version: '1.0.0',
    description: 'Guest VM bootstrap for SSH trust, certificates, and scheduled registration.',
    status: 'draft',
    resource_count: 7,
    yaml: agentVmGuestYaml,
    validation: {
      status: 'error',
      errors: [
        {
          code: 'UnknownParameter',
          message: 'Parameter "PfxPassword" is referenced but not declared.',
          path: "resources[ImportPfx].properties.Password",
        },
      ],
    },
    plan: {
      summary: '1 validation error blocks deployment. Resolve parameter declaration first.',
      steps: [
        { id: 'ImportPfx', action: 'blocked', detail: 'Unknown parameter PfxPassword' },
        { id: 'GenerateHostKeys', action: 'pending', detail: 'Waiting on SSH config' },
      ],
    },
    praxis: {
      status: 'blocked',
      firedRules: ['failed-run-alert'],
      violations: ['draft-config-block'],
      messages: ['Draft config cannot be deployed. Validation failed.'],
    },
  },
];

export const demoRuns = [
  {
    id: 'run-001',
    date: '2026-05-05',
    run_type: 'validate',
    status: 'drifted',
    resources_total: 12,
    resources_compliant: 8,
    resources_drifted: 4,
  },
  {
    id: 'run-002',
    date: '2026-05-06',
    run_type: 'test',
    status: 'drifted',
    resources_total: 12,
    resources_compliant: 9,
    resources_drifted: 3,
  },
  {
    id: 'run-003',
    date: '2026-05-07',
    run_type: 'test',
    status: 'passed',
    resources_total: 12,
    resources_compliant: 10,
    resources_drifted: 2,
  },
  {
    id: 'run-004',
    date: '2026-05-08',
    run_type: 'test',
    status: 'passed',
    resources_total: 12,
    resources_compliant: 11,
    resources_drifted: 1,
  },
  {
    id: 'run-005',
    date: '2026-05-09',
    run_type: 'validate',
    status: 'passed',
    resources_total: 12,
    resources_compliant: 12,
    resources_drifted: 0,
  },
  {
    id: 'run-006',
    date: '2026-05-10',
    run_type: 'test',
    status: 'passed',
    resources_total: 12,
    resources_compliant: 12,
    resources_drifted: 0,
  },
  {
    id: 'run-007',
    date: '2026-05-11',
    run_type: 'validate',
    status: 'passed',
    resources_total: 12,
    resources_compliant: 12,
    resources_drifted: 0,
  },
];

export const complianceTrend: TimeSeriesPoint[] = demoRuns.map((run) => ({
  date: run.date,
  value: Math.round((run.resources_compliant / run.resources_total) * 100),
}));

export const demoHosts = [
  { id: 'host-01', hostname: 'edge-hv-01', os: 'windows', connection: 'winrm', compliance_status: 'compliant' },
  { id: 'host-02', hostname: 'edge-hv-02', os: 'windows', connection: 'winrm', compliance_status: 'drifted' },
  { id: 'host-03', hostname: 'vm-guest-01', os: 'windows', connection: 'ssh', compliance_status: 'unknown' },
];
