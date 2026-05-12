<script lang="ts">
  import { complianceStore } from '../../stores/compliance.js';

  const store = complianceStore;

  const statusTone = (status: string) =>
    status === 'passed' ? 'badge--ok' : status === 'drifted' ? 'badge--warn' : 'badge--danger';
</script>

<div class="widget">
  <div class="widget__header">
    <h3>Recent Runs</h3>
    <a class="link" href="/pedantic/history">History</a>
  </div>
  <ul>
    {#each store.recentRuns as run}
      <li>
        <div>
          <span class="date">{run.date}</span>
          <span class="meta">{run.resources_compliant}/{run.resources_total} compliant</span>
        </div>
        <span class="badge {statusTone(run.status)}">{run.status}</span>
      </li>
    {/each}
  </ul>
</div>

<style>
  .widget {
    background: var(--color-surface, #111827);
    border: 1px solid var(--color-border, #1f2937);
    border-radius: 6px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .widget__header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  ul {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  li {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .date {
    font-weight: 600;
  }
  .meta {
    display: block;
    font-size: 0.75rem;
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
  .link {
    color: var(--color-accent, #60a5fa);
    text-decoration: none;
    font-size: 0.85rem;
  }
</style>
