<script lang="ts">
  import { complianceStore } from '../stores/compliance.js';

  const store = complianceStore;

  let configPath = $state('');

  async function handleLoadConfig() {
    if (!configPath.trim()) return;
    await store.loadConfig(configPath.trim());
    await store.plan();
  }
</script>

<div class="page">
  <header class="page__header">
    <div>
      <h1>Compliance Dashboard</h1>
      <p>DSC v3 compliance posture — real configs, real validation.</p>
    </div>
  </header>

  <!-- Load config -->
  <section class="load-section">
    <div class="load-row">
      <input
        class="input"
        type="text"
        placeholder="Absolute path to DSC v3 YAML config..."
        bind:value={configPath}
        onkeydown={(e) => { if (e.key === 'Enter') handleLoadConfig(); }}
      />
      <button class="btn btn--primary" onclick={handleLoadConfig} disabled={store.isRunning}>
        {store.isRunning ? 'Loading…' : 'Load & Validate'}
      </button>
    </div>
    {#if store.error}
      <div class="error-banner">⚠️ {store.error}</div>
    {/if}
  </section>

  <!-- KPIs -->
  {#if store.selectedConfig}
    <section class="kpi-row">
      <div class="kpi">
        <span class="kpi__value">{store.selectedConfig.resourceCount}</span>
        <span class="kpi__label">Resources</span>
      </div>
      <div class="kpi">
        <span class="kpi__value {store.validationReport?.status === 'ok' ? 'ok' : 'error'}">
          {store.validationReport?.status === 'ok' ? '✓ Valid' : store.validationReport ? '✗ Errors' : '—'}
        </span>
        <span class="kpi__label">Validation</span>
      </div>
      <div class="kpi">
        <span class="kpi__value">{store.executionPlan?.steps.length ?? '—'}</span>
        <span class="kpi__label">Plan Steps</span>
      </div>
      <div class="kpi">
        <span class="kpi__value">{store.violations}</span>
        <span class="kpi__label">Violations</span>
      </div>
    </section>

    <!-- Main grid -->
    <section class="grid">
      <!-- Config summary + validation -->
      <div class="panel">
        <div class="panel__header">
          <h2>Configuration</h2>
          <span class="badge badge--ok">{store.selectedConfig.version}</span>
        </div>
        <div class="panel__body">
          <p class="panel__title">{store.selectedConfig.name}</p>
          <p class="panel__meta">{store.selectedConfig.resourceCount} resources · {store.selectedConfig.filePath}</p>
          {#if store.selectedConfig.description}
            <p class="panel__desc">{store.selectedConfig.description}</p>
          {/if}

          <div class="validation">
            <h3>Validation</h3>
            {#if store.validationReport === null}
              <p class="panel__meta">Not yet validated</p>
            {:else if store.validationReport.status === 'ok'}
              <div class="validation__item ok">✅ All checks passed</div>
            {:else}
              {#each store.validationReport.errors as err}
                <div class="validation__item error">❌ {err.message}</div>
              {/each}
            {/if}
          </div>
        </div>
      </div>

      <!-- Execution plan -->
      <div class="panel">
        <div class="panel__header">
          <h2>Execution Plan</h2>
          {#if store.executionPlan}
            <span class="badge badge--accent">{store.executionPlan.steps.length} steps</span>
          {/if}
        </div>
        <div class="panel__body">
          {#if store.executionPlan === null}
            <p class="panel__meta">Run planning to see execution order</p>
          {:else}
            <table class="plan-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Resource</th>
                  <th>Type</th>
                </tr>
              </thead>
              <tbody>
                {#each store.executionPlan.steps as step, i}
                  <tr>
                    <td class="step-num">{i + 1}</td>
                    <td>{step.resourceName}</td>
                    <td class="type-cell">{step.resourceType}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          {/if}
        </div>
      </div>
    </section>

    <!-- Config selector for multiple loaded configs -->
    {#if store.configs.length > 1}
      <section class="panel">
        <div class="panel__header">
          <h2>Loaded Configs</h2>
        </div>
        <div class="config-list">
          {#each store.configs as cfg}
            <button
              class="config-item"
              class:active={cfg.id === store.selectedConfigId}
              onclick={() => store.selectConfig(cfg.id)}
            >
              <span class="config-item__name">{cfg.name}</span>
              <span class="config-item__meta">{cfg.resourceCount} resources</span>
            </button>
          {/each}
        </div>
      </section>
    {/if}
  {:else}
    <section class="empty">
      <p>Load a DSC v3 config file to begin.</p>
      <p class="panel__meta">Example: <code>/path/to/AgentHost.Cluster.yaml</code></p>
    </section>
  {/if}
</div>

<style>
  .page { padding: 24px; display: flex; flex-direction: column; gap: 24px; }
  h1 { margin: 0 0 4px; font-size: 1.5rem; }
  h2 { margin: 0; font-size: 1.1rem; }
  h3 { margin: 0 0 8px; font-size: 0.95rem; }
  p { margin: 0; color: var(--color-text-muted, #94a3b8); }
  .page__header { display: flex; align-items: center; justify-content: space-between; }

  .load-section { display: flex; flex-direction: column; gap: 8px; }
  .load-row { display: flex; gap: 12px; }
  .input {
    flex: 1; padding: 10px 14px; border-radius: 6px;
    border: 1px solid var(--color-border, #1f2937);
    background: var(--color-surface, #111827);
    color: var(--color-text, #e5e7eb);
    font-family: monospace; font-size: 0.9rem;
  }
  .btn {
    border-radius: 6px; border: 1px solid var(--color-border, #1f2937);
    background: var(--color-surface, #111827); color: var(--color-text, #e5e7eb);
    padding: 10px 18px; font-weight: 600; cursor: pointer; white-space: nowrap;
  }
  .btn--primary { background: var(--color-accent, #2563eb); border-color: transparent; }
  .btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .error-banner {
    padding: 10px 14px; border-radius: 6px;
    background: #ef444420; color: #f87171; font-size: 0.9rem;
  }

  .kpi-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 16px; }
  .kpi {
    background: var(--color-surface, #111827);
    border: 1px solid var(--color-border, #1f2937);
    border-radius: 6px; padding: 16px; text-align: center;
    display: flex; flex-direction: column; gap: 4px;
  }
  .kpi__value { font-size: 1.6rem; font-weight: 700; color: var(--color-text, #e5e7eb); }
  .kpi__value.ok { color: #34d399; }
  .kpi__value.error { color: #f87171; }
  .kpi__label { font-size: 0.8rem; color: var(--color-text-muted, #94a3b8); text-transform: uppercase; letter-spacing: 0.04em; }

  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }
  .panel {
    background: var(--color-surface, #111827);
    border: 1px solid var(--color-border, #1f2937);
    border-radius: 6px; padding: 16px;
    display: flex; flex-direction: column; gap: 12px;
  }
  .panel__header { display: flex; justify-content: space-between; align-items: center; }
  .panel__title { font-weight: 600; color: var(--color-text, #e5e7eb); }
  .panel__meta { font-size: 0.85rem; color: var(--color-text-muted, #94a3b8); }
  .panel__desc { color: var(--color-text-muted, #94a3b8); }

  .badge {
    font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em;
    padding: 2px 8px; border-radius: 999px; background: var(--color-hover, #1f2937);
  }
  .badge--ok { color: #10b981; background: #10b98120; }
  .badge--accent { color: var(--color-accent, #60a5fa); background: #2563eb20; }

  .validation { border-top: 1px solid var(--color-border, #1f2937); padding-top: 12px; }
  .validation__item { margin-top: 8px; font-size: 0.9rem; }
  .validation__item.error { color: #f87171; }
  .validation__item.ok { color: #34d399; }

  .plan-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  .plan-table th { text-align: left; padding: 6px 8px; color: var(--color-text-muted); border-bottom: 1px solid var(--color-border); }
  .plan-table td { padding: 6px 8px; }
  .step-num { color: var(--color-text-muted); width: 30px; }
  .type-cell { font-family: monospace; font-size: 0.8rem; color: var(--color-text-muted); }

  .config-list { display: flex; flex-direction: column; gap: 4px; }
  .config-item {
    display: flex; justify-content: space-between; padding: 8px 12px;
    border: 1px solid var(--color-border); border-radius: 6px;
    background: transparent; color: var(--color-text); cursor: pointer;
  }
  .config-item.active { background: var(--color-accent-bg, #2563eb20); border-color: var(--color-accent); }
  .config-item__name { font-weight: 500; }
  .config-item__meta { font-size: 0.8rem; color: var(--color-text-muted); }

  .empty { text-align: center; padding: 48px 24px; }
  .empty code { font-size: 0.85rem; color: var(--color-accent, #60a5fa); }
</style>
