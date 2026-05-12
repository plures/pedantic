<script lang="ts">
  import { complianceStore } from '../../stores/compliance.js';

  const store = complianceStore;
</script>

<div class="widget">
  {#if store.recentRuns.length === 0}
    <p class="empty">No runs recorded</p>
  {:else}
    <ul class="run-list">
      {#each store.recentRuns as run}
        <li class="run-item">
          <span class="run-status {run.status === 'passed' ? 'ok' : run.status === 'drifted' ? 'warn' : 'error'}">
            {run.status === 'passed' ? '✓' : run.status === 'drifted' ? '⚠' : '✗'}
          </span>
          <span class="run-info">
            <span class="run-config">{run.configName}</span>
            <span class="run-date">{run.date}</span>
          </span>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .widget { padding: 4px 0; }
  .empty { margin: 0; font-size: 0.85rem; color: var(--color-text-muted, #94a3b8); }
  .run-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; }
  .run-item { display: flex; align-items: center; gap: 10px; }
  .run-status {
    width: 24px; height: 24px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 0.8rem; font-weight: 700; flex-shrink: 0;
  }
  .run-status.ok { background: #10b98120; color: #34d399; }
  .run-status.warn { background: #f59e0b20; color: #f59e0b; }
  .run-status.error { background: #ef444420; color: #f87171; }
  .run-info { display: flex; flex-direction: column; }
  .run-config { font-size: 0.85rem; font-weight: 500; color: var(--color-text, #e5e7eb); }
  .run-date { font-size: 0.75rem; color: var(--color-text-muted, #94a3b8); }
</style>
