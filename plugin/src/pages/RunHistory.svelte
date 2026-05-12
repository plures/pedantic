<script lang="ts">
  import { TrendChart } from '@plures/design-dojo';
  import { complianceStore } from '../stores/compliance.js';

  const store = complianceStore;

  const statusTone = (status: string) =>
    status === 'passed' ? 'badge--ok' : status === 'drifted' ? 'badge--warn' : 'badge--danger';
</script>

<div class="page">
  <header>
    <h1>Run History</h1>
    <p>Compliance run timeline across the last week.</p>
  </header>

  <section class="panel">
    <div class="panel__header">
      <h2>Compliance Trend</h2>
      <span class="panel__meta">7 run window</span>
    </div>
    <TrendChart data={store.complianceTrend} title="Compliance %" yLabel="Compliance" />
  </section>

  <section class="panel">
    <div class="panel__header">
      <h2>Runs</h2>
      <span class="panel__meta">{store.runs.length} total</span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Type</th>
          <th>Status</th>
          <th>Resources</th>
          <th>Drifted</th>
        </tr>
      </thead>
      <tbody>
        {#each store.runs as run}
          <tr>
            <td>{run.date}</td>
            <td class="caps">{run.run_type}</td>
            <td><span class="badge {statusTone(run.status)}">{run.status}</span></td>
            <td>{run.resources_compliant}/{run.resources_total}</td>
            <td>{run.resources_drifted}</td>
          </tr>
        {/each}
      </tbody>
    </table>
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
  h1 {
    margin: 0 0 4px;
  }
  p {
    margin: 0;
    color: var(--color-text-muted, #94a3b8);
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
  .panel__meta {
    color: var(--color-text-muted, #94a3b8);
    font-size: 0.85rem;
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
  .badge--warn {
    color: #f59e0b;
    background: #f59e0b20;
  }
  .badge--danger {
    color: #f87171;
    background: #f8717120;
  }
  .caps {
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
</style>
