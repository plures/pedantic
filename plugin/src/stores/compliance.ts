/**
 * Pedantic compliance store — runs the real pedantic CLI against real configs.
 *
 * No embedded demo data. The plugin discovers config files, invokes
 * `pedantic parse|validate|plan` on them, and displays actual results.
 *
 * In a Tauri context the CLI is invoked via the shell. In a browser-only
 * context (SvelteKit dev) it imports pre-loaded results from the
 * PluginContext.data API (PluresDB).
 */

// ── Types ────────────────────────────────────────────────────────────────────

export interface DscConfig {
  id: string;
  name: string;
  version: string;
  description: string;
  resourceCount: number;
  yaml: string;
  filePath: string;
}

export interface ValidationError {
  code: string;
  message: string;
}

export interface ValidationReport {
  status: 'ok' | 'error';
  errors: ValidationError[];
}

export interface PlanStep {
  resourceName: string;
  resourceType: string;
}

export interface ExecutionPlan {
  steps: PlanStep[];
}

export interface PraxisOutcome {
  firedRules: string[];
  violations: string[];
  events: string[];
  iterations: number;
}

export interface ComplianceRun {
  id: string;
  configName: string;
  date: string;
  runType: 'test' | 'set' | 'validate';
  status: 'passed' | 'failed' | 'drifted';
  resourcesTotal: number;
  resourcesCompliant: number;
  resourcesDrifted: number;
}

export interface Host {
  hostname: string;
  os: string;
  connection: string;
  complianceStatus: string;
}

// ── Store ────────────────────────────────────────────────────────────────────

export const complianceStore = (() => {
  let configs = $state<DscConfig[]>([]);
  let selectedConfigId = $state<string>('');
  let validationReport = $state<ValidationReport | null>(null);
  let executionPlan = $state<ExecutionPlan | null>(null);
  let praxisOutcome = $state<PraxisOutcome | null>(null);
  let complianceRuns = $state<ComplianceRun[]>([]);
  let hosts = $state<Host[]>([]);
  let isRunning = $state(false);
  let lastExport = $state('');
  let error = $state<string | null>(null);

  const selectedConfig = $derived(configs.find((c) => c.id === selectedConfigId) ?? null);

  const latestRun = $derived(complianceRuns.length ? complianceRuns[complianceRuns.length - 1] : null);
  const compliancePercent = $derived(
    latestRun ? Math.round((latestRun.resourcesCompliant / latestRun.resourcesTotal) * 100) : 0,
  );
  const totalResources = $derived(latestRun?.resourcesTotal ?? 0);
  const violations = $derived(latestRun?.resourcesDrifted ?? 0);
  const lastRunTime = $derived(latestRun?.date ?? '—');
  const recentRuns = $derived(complianceRuns.slice(-5).reverse());

  // ── Actions ──────────────────────────────────────────────────────────────

  /**
   * Load a DSC config by invoking `pedantic parse <file>`.
   * The file path must be an absolute path to a real YAML config.
   */
  async function loadConfig(filePath: string): Promise<void> {
    isRunning = true;
    error = null;
    try {
      const parsed = await invokePedantic('parse', filePath);
      const doc = JSON.parse(parsed);
      const yaml = await readFile(filePath);

      const config: DscConfig = {
        id: filePath,
        name: doc.name,
        version: doc.version,
        description: doc.description ?? '',
        resourceCount: doc.resources?.length ?? 0,
        yaml,
        filePath,
      };

      // Replace existing or add new
      const idx = configs.findIndex((c) => c.id === filePath);
      if (idx >= 0) {
        configs[idx] = config;
      } else {
        configs.push(config);
      }
      selectedConfigId = filePath;

      // Auto-validate on load
      await validate();
    } catch (e: unknown) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      isRunning = false;
    }
  }

  async function validate(): Promise<void> {
    if (!selectedConfig) return;
    isRunning = true;
    error = null;
    try {
      const output = await invokePedantic('validate', selectedConfig.filePath);
      if (output.trim() === 'OK') {
        validationReport = { status: 'ok', errors: [] };
      } else {
        // Pedantic outputs one error per line on stderr/stdout
        const errors = output
          .trim()
          .split('\n')
          .filter(Boolean)
          .map((line) => ({
            code: 'validation',
            message: line.trim(),
          }));
        validationReport = { status: 'error', errors };
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      validationReport = { status: 'error', errors: [{ code: 'cli-error', message: msg }] };
    } finally {
      isRunning = false;
    }
  }

  async function plan(): Promise<void> {
    if (!selectedConfig) return;
    isRunning = true;
    error = null;
    try {
      const output = await invokePedantic('plan', selectedConfig.filePath);
      const parsed = JSON.parse(output);
      executionPlan = {
        steps: parsed.steps.map((s: { resource_name: string; resource_type: string }) => ({
          resourceName: s.resource_name,
          resourceType: s.resource_type,
        })),
      };
    } catch (e: unknown) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      isRunning = false;
    }
  }

  async function exportJunit(): Promise<string> {
    if (!selectedConfig) return '';
    try {
      const output = await invokePedantic('export junit', selectedConfig.filePath);
      lastExport = output;
      return output;
    } catch (e: unknown) {
      error = e instanceof Error ? e.message : String(e);
      return '';
    }
  }

  async function exportSarif(): Promise<string> {
    if (!selectedConfig) return '';
    try {
      const output = await invokePedantic('export sarif', selectedConfig.filePath);
      lastExport = output;
      return output;
    } catch (e: unknown) {
      error = e instanceof Error ? e.message : String(e);
      return '';
    }
  }

  function selectConfig(id: string): void {
    selectedConfigId = id;
    // Reset results when switching
    validationReport = null;
    executionPlan = null;
    praxisOutcome = null;
  }

  function addRun(run: ComplianceRun): void {
    complianceRuns.push(run);
  }

  function setHosts(newHosts: Host[]): void {
    hosts = newHosts;
  }

  // ── CLI Bridge ───────────────────────────────────────────────────────────

  /**
   * Invoke the pedantic CLI. In Tauri, this uses the shell command API.
   * Falls back to a no-op with error for browser-only dev.
   */
  async function invokePedantic(subcommand: string, filePath: string): Promise<string> {
    // Tauri shell API
    if (typeof window !== 'undefined' && '__TAURI__' in window) {
      const { Command } = await import('@tauri-apps/plugin-shell');
      const args = subcommand.split(' ').concat(filePath);
      const result = await Command.create('pedantic', args).execute();
      if (result.code !== 0) {
        throw new Error(result.stderr || `pedantic ${subcommand} exited with code ${result.code}`);
      }
      return result.stdout;
    }

    // SvelteKit SSR / server-side: use Node child_process
    if (typeof process !== 'undefined' && process.versions?.node) {
      const { execSync } = await import('child_process');
      return execSync(`pedantic ${subcommand} "${filePath}"`, {
        encoding: 'utf-8',
        timeout: 30_000,
      });
    }

    throw new Error(
      'pedantic CLI not available in this environment. ' +
        'Run inside Tauri or server-side SvelteKit with pedantic on PATH.',
    );
  }

  async function readFile(filePath: string): Promise<string> {
    if (typeof window !== 'undefined' && '__TAURI__' in window) {
      const { readTextFile } = await import('@tauri-apps/plugin-fs');
      return readTextFile(filePath);
    }
    if (typeof process !== 'undefined' && process.versions?.node) {
      const { readFileSync } = await import('fs');
      return readFileSync(filePath, 'utf-8');
    }
    throw new Error('File read not available in this environment.');
  }

  return {
    get configs() { return configs; },
    get selectedConfigId() { return selectedConfigId; },
    get selectedConfig() { return selectedConfig; },
    get validationReport() { return validationReport; },
    get executionPlan() { return executionPlan; },
    get praxisOutcome() { return praxisOutcome; },
    get complianceRuns() { return complianceRuns; },
    get hosts() { return hosts; },
    get isRunning() { return isRunning; },
    get error() { return error; },
    get compliancePercent() { return compliancePercent; },
    get totalResources() { return totalResources; },
    get violations() { return violations; },
    get lastRunTime() { return lastRunTime; },
    get recentRuns() { return recentRuns; },
    get lastExport() { return lastExport; },
    loadConfig,
    validate,
    plan,
    exportJunit,
    exportSarif,
    selectConfig,
    addRun,
    setHosts,
  };
})();
