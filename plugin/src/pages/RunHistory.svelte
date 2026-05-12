<script lang="ts">
  import { complianceStore } from '../stores/compliance.js';

  const store = complianceStore;
</script>

<div class="page">
  <header class="page__header">
    <h1>Run History</h1>
    <p>Compliance run records from real pedantic executions.</p>
  </header>

  {#if store.complianceRuns.length === 0}
    <section class="empty">
      <p>No compliance runs recorded yet.</p>
      <p class="meta">Run <code>pedantic validate</code> or <code>pedantic plan</code> against a config to generate history.</p>
    </section>
  {:else}
    <section class="panel">
      <table class="runs-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Config</th>
            <th>Type</th>
            <th>Status</th>
            <th>Resources</th>
            <th>Compliant</th>
            <th>Drifted</th>
          </tr>
        </thead>
        <tbody>
          {#each store.recentRuns as run}
            <tr>
              <td class="mono">{run.date}</td>
              <td>{run.configName}</td>
              <td><span class="badge">{run.runType}</span></td>
              <td>
                <span class="badge {run.status === 'passed' ? 'badge--ok' : run.status === 'drifted' ? 'badge--warn' : 'badge--danger'}">
                  {run.status}
                </span>
              </td>
              <td>{run.resourcesTotal}</td>
              <td class="ok">{run.resourcesCompliant}</td>
              <td class="{run.resourcesDrifted > 0 ? 'error' : ''}">{run.resourcesDrifted}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </section>
  {/if}
</div>

<style>
  .page { padding: 24px; display: flex; flex-direction: column; gap: 20px; }
  h1 { margin: 0; font-size: 1.5rem; }
  p { margin: 0; color: var(--color-text-muted, #94a3b8); }
  .meta { font-size: 0.85rem; }
  .meta code { color: var(--color-accent, #60a5fa); }

  .panel {
    background: var(--color-surface, #111827); border: 1px solid var(--color-border, #1f2937);
    border-radius: 6px; padding: 16px; overflow-x: auto;
  }

  .runs-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  .runs-table th {
    text-align: left; padding: 8px; color: var(--color-text-muted);
    border-bottom: 1px solid var(--color-border); white-space: nowrap;
  }
  .runs-table td { padding: 8px; }
  .runs-table tbody tr:hover { background: var(--color-hover, #1f2937); }

  .mono { font-family: monospace; font-size: 0.8rem; }
  .ok { color: #34d399; }
  .error { color: #f87171; }

  .badge {
    font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em;
    padding: 2px 8px; border-radius: 999px; background: var(--color-hover, #1f2937);
  }
  .badge--ok { color: #10b981; background: #10b98120; }
  .badge--warn { color: #f59e0b; background: #f59e0b20; }
  .badge--danger { color: #ef4444; background: #ef444420; }

  .empty { text-align: center; padding: 48px 24px; }
</style>
