<script lang="ts">
  import { complianceStore } from '../stores/compliance.js';

  const store = complianceStore;

  let configPath = $state('');

  async function handleLoad() {
    if (!configPath.trim()) return;
    await store.loadConfig(configPath.trim());
  }

  async function handleExportJunit() {
    await store.exportJunit();
  }

  async function handleExportSarif() {
    await store.exportSarif();
  }

  function copyToClipboard(text: string) {
    navigator.clipboard.writeText(text);
  }
</script>

<div class="page">
  <header class="page__header">
    <h1>Config Browser</h1>
  </header>

  <!-- Load -->
  <section class="load-row">
    <input
      class="input"
      type="text"
      placeholder="Path to DSC v3 YAML config..."
      bind:value={configPath}
      onkeydown={(e) => { if (e.key === 'Enter') handleLoad(); }}
    />
    <button class="btn btn--primary" onclick={handleLoad} disabled={store.isRunning}>Load</button>
  </section>

  {#if store.error}
    <div class="error-banner">⚠️ {store.error}</div>
  {/if}

  <!-- Config selector -->
  {#if store.configs.length > 0}
    <section class="config-select">
      <label class="label">Select config:</label>
      <select class="select" bind:value={store.selectedConfigId} onchange={(e) => store.selectConfig(e.currentTarget.value)}>
        {#each store.configs as cfg}
          <option value={cfg.id}>{cfg.name} ({cfg.resourceCount} resources)</option>
        {/each}
      </select>
      <button class="btn" onclick={() => store.validate()} disabled={store.isRunning}>Validate</button>
      <button class="btn" onclick={() => store.plan()} disabled={store.isRunning}>Plan</button>
    </section>
  {/if}

  {#if store.selectedConfig}
    <section class="grid">
      <!-- YAML viewer -->
      <div class="panel">
        <div class="panel__header">
          <h2>YAML</h2>
          <span class="badge">{store.selectedConfig.name}</span>
        </div>
        <pre class="yaml-viewer"><code>{store.selectedConfig.yaml}</code></pre>
      </div>

      <!-- Validation + Plan -->
      <div class="panel">
        <div class="panel__header">
          <h2>Results</h2>
        </div>

        <!-- Validation -->
        <div class="section">
          <h3>Validation</h3>
          {#if store.validationReport === null}
            <p class="meta">Not yet validated</p>
          {:else if store.validationReport.status === 'ok'}
            <div class="result ok">✅ All checks passed</div>
          {:else}
            {#each store.validationReport.errors as err}
              <div class="result error">❌ {err.message}</div>
            {/each}
          {/if}
        </div>

        <!-- Plan -->
        <div class="section">
          <h3>Execution Plan</h3>
          {#if store.executionPlan === null}
            <p class="meta">Click "Plan" to compute execution order</p>
          {:else}
            <table class="plan-table">
              <thead>
                <tr><th>#</th><th>Resource</th><th>Type</th></tr>
              </thead>
              <tbody>
                {#each store.executionPlan.steps as step, i}
                  <tr>
                    <td class="num">{i + 1}</td>
                    <td>{step.resourceName}</td>
                    <td class="mono">{step.resourceType}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          {/if}
        </div>

        <!-- Export -->
        <div class="section">
          <h3>Export</h3>
          <div class="export-btns">
            <button class="btn" onclick={handleExportJunit}>Export JUnit XML</button>
            <button class="btn" onclick={handleExportSarif}>Export SARIF JSON</button>
          </div>
          {#if store.lastExport}
            <div class="export-preview">
              <div class="export-preview__header">
                <span>Export Output</span>
                <button class="btn btn--sm" onclick={() => copyToClipboard(store.lastExport)}>Copy</button>
              </div>
              <pre class="export-code"><code>{store.lastExport}</code></pre>
            </div>
          {/if}
        </div>
      </div>
    </section>
  {:else}
    <section class="empty">
      <p>Load a config to browse, validate, plan, and export.</p>
    </section>
  {/if}
</div>

<style>
  .page { padding: 24px; display: flex; flex-direction: column; gap: 20px; }
  h1 { margin: 0; font-size: 1.5rem; }
  h2 { margin: 0; font-size: 1.1rem; }
  h3 { margin: 0 0 8px; font-size: 0.95rem; color: var(--color-text, #e5e7eb); }
  p { margin: 0; }

  .load-row { display: flex; gap: 12px; }
  .input {
    flex: 1; padding: 10px 14px; border-radius: 6px;
    border: 1px solid var(--color-border, #1f2937);
    background: var(--color-surface, #111827);
    color: var(--color-text, #e5e7eb); font-family: monospace; font-size: 0.9rem;
  }
  .btn {
    border-radius: 6px; border: 1px solid var(--color-border);
    background: var(--color-surface); color: var(--color-text);
    padding: 8px 14px; font-weight: 600; cursor: pointer; white-space: nowrap;
  }
  .btn--primary { background: var(--color-accent, #2563eb); border-color: transparent; }
  .btn--sm { padding: 4px 10px; font-size: 0.75rem; }
  .btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .error-banner { padding: 10px; border-radius: 6px; background: #ef444420; color: #f87171; font-size: 0.9rem; }

  .config-select { display: flex; gap: 12px; align-items: center; }
  .label { font-size: 0.85rem; color: var(--color-text-muted); white-space: nowrap; }
  .select {
    flex: 1; padding: 8px; border-radius: 6px;
    border: 1px solid var(--color-border);
    background: var(--color-surface); color: var(--color-text);
  }

  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  @media (max-width: 900px) { .grid { grid-template-columns: 1fr; } }

  .panel {
    background: var(--color-surface); border: 1px solid var(--color-border);
    border-radius: 6px; padding: 16px; display: flex; flex-direction: column; gap: 16px;
    overflow: hidden;
  }
  .panel__header { display: flex; justify-content: space-between; align-items: center; }
  .badge { font-size: 0.7rem; text-transform: uppercase; padding: 2px 8px; border-radius: 999px; background: var(--color-hover); }

  .yaml-viewer {
    margin: 0; padding: 12px; border-radius: 6px;
    background: var(--color-bg, #0f1117); color: var(--color-text);
    font-size: 0.8rem; line-height: 1.5; overflow-x: auto; max-height: 600px;
  }

  .section { border-top: 1px solid var(--color-border); padding-top: 12px; }
  .meta { font-size: 0.85rem; color: var(--color-text-muted); }
  .result { margin-top: 6px; font-size: 0.9rem; }
  .result.ok { color: #34d399; }
  .result.error { color: #f87171; }

  .plan-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  .plan-table th { text-align: left; padding: 6px 8px; color: var(--color-text-muted); border-bottom: 1px solid var(--color-border); }
  .plan-table td { padding: 6px 8px; }
  .num { color: var(--color-text-muted); width: 30px; }
  .mono { font-family: monospace; font-size: 0.8rem; color: var(--color-text-muted); }

  .export-btns { display: flex; gap: 12px; margin-bottom: 12px; }
  .export-preview { border: 1px solid var(--color-border); border-radius: 6px; overflow: hidden; }
  .export-preview__header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 6px 12px; background: var(--color-hover); font-size: 0.8rem;
  }
  .export-code {
    margin: 0; padding: 12px; font-size: 0.75rem; line-height: 1.4;
    background: var(--color-bg); overflow-x: auto; max-height: 300px;
  }

  .empty { text-align: center; padding: 48px 24px; color: var(--color-text-muted); }
</style>
