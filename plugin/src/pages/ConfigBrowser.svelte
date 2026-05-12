<script lang="ts">
  import { complianceStore } from '../stores/compliance.js';

  const store = complianceStore;

  async function copyToClipboard(payload: string) {
    if (!payload) return;
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(payload);
    }
  }

  function exportJunit() {
    const payload = store.exportJunit();
    copyToClipboard(payload);
  }

  function exportSarif() {
    const payload = store.exportSarif();
    copyToClipboard(payload);
  }
</script>

<div class="page">
  <header class="page__header">
    <div>
      <h1>Config Browser</h1>
      <p>Inspect, validate, and export compliance artifacts.</p>
    </div>
    <div class="select">
      <label for="config-select">Config</label>
      <select
        id="config-select"
        bind:value={store.selectedConfigId}
        on:change={(event) => store.selectConfig((event.target as HTMLSelectElement).value)}
      >
        {#each store.configs as config}
          <option value={config.id}>{config.name}</option>
        {/each}
      </select>
    </div>
  </header>

  <section class="grid">
    <div class="panel">
      <div class="panel__header">
        <h2>Configuration YAML</h2>
        <span class="badge">{store.selectedConfig?.status ?? 'unknown'}</span>
      </div>
      <pre class="code"><code>{store.selectedConfig?.yaml}</code></pre>
    </div>

    <div class="panel">
      <div class="panel__header">
        <h2>Validation Results</h2>
        <span class="badge {store.validationReport?.status === 'ok' ? 'badge--ok' : 'badge--danger'}">
          {store.validationReport?.status ?? 'unknown'}
        </span>
      </div>
      {#if store.validationReport?.status === 'ok'}
        <p class="ok">No errors detected.</p>
      {:else}
        <div class="errors">
          {#each store.validationReport?.errors ?? [] as error}
            <div class="error">
              <div class="error__head">
                <span class="error__code">{error.code}</span>
                <span class="error__path">{error.path}</span>
              </div>
              <p>{error.message}</p>
            </div>
          {/each}
        </div>
      {/if}
      <div class="actions">
        <button class="btn" on:click={() => store.validate()}>Re-validate</button>
      </div>
    </div>
  </section>

  <section class="panel">
    <div class="panel__header">
      <h2>Execution Plan</h2>
      <span class="panel__meta">{store.executionPlan?.summary}</span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Resource</th>
          <th>Action</th>
          <th>Detail</th>
        </tr>
      </thead>
      <tbody>
        {#each store.executionPlan?.steps ?? [] as step}
          <tr>
            <td>{step.id}</td>
            <td><span class="tag">{step.action}</span></td>
            <td>{step.detail}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </section>

  <section class="panel">
    <div class="panel__header">
      <h2>Export</h2>
      <span class="panel__meta">Copy results to clipboard</span>
    </div>
    <div class="export-actions">
      <button class="btn" on:click={exportJunit}>JUnit XML</button>
      <button class="btn" on:click={exportSarif}>SARIF JSON</button>
    </div>
    {#if store.lastExport}
      <pre class="code code--compact"><code>{store.lastExport}</code></pre>
    {/if}
  </section>
</div>

<style>
  .page {
    padding: 24px;
    display: flex;
    flex-direction: column;
    gap: 24px;
    --radius-lg: 6px;
  }
  .page__header {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: 16px;
  }
  h1 {
    margin: 0 0 4px;
  }
  p {
    margin: 0;
    color: var(--color-text-muted, #94a3b8);
  }
  .select {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  select {
    border-radius: 6px;
    border: 1px solid var(--color-border, #1f2937);
    background: var(--color-surface, #111827);
    color: var(--color-text, #e5e7eb);
    padding: 6px 10px;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: 16px;
  }
  .panel {
    background: var(--color-surface, #111827);
    border: 1px solid var(--color-border, #1f2937);
    border-radius: 6px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .panel__header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .badge {
    font-size: 0.7rem;
    text-transform: uppercase;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--color-hover, #1f2937);
  }
  .badge--ok {
    color: #10b981;
    background: #10b98120;
  }
  .badge--danger {
    color: #f87171;
    background: #f8717120;
  }
  .code {
    background: #0b1120;
    border-radius: 6px;
    padding: 14px;
    font-size: 0.82rem;
    color: #cbd5f5;
    overflow: auto;
    max-height: 340px;
  }
  .code--compact {
    max-height: 220px;
  }
  .errors {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .error {
    border: 1px solid #f8717120;
    border-radius: 6px;
    padding: 10px;
    background: #f8717110;
  }
  .error__head {
    display: flex;
    justify-content: space-between;
    font-size: 0.75rem;
    margin-bottom: 4px;
  }
  .error__code {
    color: #f87171;
    font-weight: 600;
  }
  .error__path {
    color: var(--color-text-muted, #94a3b8);
  }
  .ok {
    color: #34d399;
  }
  .actions {
    margin-top: 8px;
  }
  .btn {
    border-radius: 6px;
    border: 1px solid var(--color-border, #1f2937);
    background: var(--color-surface, #111827);
    color: var(--color-text, #e5e7eb);
    padding: 6px 12px;
    font-weight: 600;
    cursor: pointer;
  }
  table {
    width: 100%;
    border-collapse: collapse;
  }
  th,
  td {
    text-align: left;
    padding: 8px;
    border-bottom: 1px solid var(--color-border, #1f2937);
    font-size: 0.85rem;
  }
  th {
    color: var(--color-text-muted, #94a3b8);
    font-weight: 600;
  }
  .tag {
    font-size: 0.7rem;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--color-hover, #1f2937);
  }
  .export-actions {
    display: flex;
    gap: 12px;
  }
</style>
