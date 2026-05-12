import { complianceTrend, demoConfigs, demoHosts, demoRuns } from '../data/demo.js';

export type ValidationError = {
  code: string;
  message: string;
  path: string;
};

export type ValidationReport = {
  status: 'ok' | 'error';
  errors: ValidationError[];
};

export type ExecutionPlan = {
  summary: string;
  steps: { id: string; action: string; detail: string }[];
};

export type PraxisOutcome = {
  status: 'clean' | 'blocked' | 'warning';
  firedRules: string[];
  violations: string[];
  messages: string[];
};

export const complianceStore = (() => {
  let configs = $state([...demoConfigs]);
  let selectedConfigId = $state(configs[0]?.id ?? '');
  let runs = $state([...demoRuns]);
  let hosts = $state([...demoHosts]);
  let lastExport = $state('');

  const selectedConfig = $derived(() => configs.find((config) => config.id === selectedConfigId));
  const validationReport = $derived<ValidationReport | null>(() => selectedConfig?.validation ?? null);
  const executionPlan = $derived<ExecutionPlan | null>(() => selectedConfig?.plan ?? null);
  const praxisOutcome = $derived<PraxisOutcome | null>(() => selectedConfig?.praxis ?? null);

  const latestRun = $derived(() => (runs.length ? runs[runs.length - 1] : null));
  const compliancePercent = $derived(() =>
    latestRun ? Math.round((latestRun.resources_compliant / latestRun.resources_total) * 100) : 0,
  );
  const totalResources = $derived(() => latestRun?.resources_total ?? 0);
  const violations = $derived(() => latestRun?.resources_drifted ?? 0);
  const lastRunTime = $derived(() => latestRun?.date ?? '—');
  const recentRuns = $derived(() => runs.slice(-3).reverse());

  function selectConfig(id: string) {
    selectedConfigId = id;
  }

  function validate() {
    if (!selectedConfig) return;
    lastExport = `Validated ${selectedConfig.name} at ${new Date().toISOString()}`;
  }

  function plan() {
    if (!selectedConfig) return;
    lastExport = `Planned execution for ${selectedConfig.name}`;
  }

  function runPraxis() {
    if (!selectedConfig) return;
    lastExport = `Ran praxis engine for ${selectedConfig.name}`;
  }

  function exportJunit() {
    if (!selectedConfig) return '';
    const errors = validationReport?.errors ?? [];
    const failures = errors
      .map((error) => `      <failure message="${error.code}">${error.message}</failure>`)
      .join('\n');
    const junit = `<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="${selectedConfig.name}" tests="${errors.length || 1}" failures="${errors.length}">
  <testcase classname="validation" name="schema" time="0.01">
${failures || '      <system-out>Validation passed</system-out>'}
  </testcase>
</testsuite>`;
    lastExport = junit;
    return junit;
  }

  function exportSarif() {
    if (!selectedConfig) return '';
    const errors = validationReport?.errors ?? [];
    const sarif = {
      version: '2.1.0',
      $schema: 'https://json.schemastore.org/sarif-2.1.0.json',
      runs: [
        {
          tool: {
            driver: {
              name: 'pedantic',
              version: '0.1.0',
            },
          },
          results: errors.length
            ? errors.map((error) => ({
                ruleId: error.code,
                level: 'error',
                message: { text: error.message },
                locations: [
                  {
                    physicalLocation: {
                      artifactLocation: { uri: `${selectedConfig.name}.yaml` },
                      region: { snippet: { text: error.path } },
                    },
                  },
                ],
              }))
            : [
                {
                  ruleId: 'ValidationOk',
                  level: 'note',
                  message: { text: 'Validation passed' },
                },
              ],
        },
      ],
    };
    const payload = JSON.stringify(sarif, null, 2);
    lastExport = payload;
    return payload;
  }

  return {
    configs,
    selectedConfigId,
    selectedConfig,
    validationReport,
    executionPlan,
    praxisOutcome,
    runs,
    hosts,
    complianceTrend,
    totalResources,
    compliancePercent,
    violations,
    lastRunTime,
    recentRuns,
    lastExport,
    selectConfig,
    validate,
    plan,
    runPraxis,
    exportJunit,
    exportSarif,
  };
})();
