<script lang="ts">
  import { complianceStore } from '../../stores/compliance.js';

  const store = complianceStore;
</script>

<div class="widget">
  {#if store.selectedConfig}
    <div class="status-indicator {store.validationReport?.status === 'ok' ? 'ok' : store.validationReport ? 'error' : 'unknown'}">
      {store.validationReport?.status === 'ok' ? '✓' : store.validationReport ? '✗' : '?'}
    </div>
    <div class="details">
      <span class="config-name">{store.selectedConfig.name}</span>
      <span class="meta">{store.selectedConfig.resourceCount} resources</span>
    </div>
  {:else}
    <div class="status-indicator unknown">—</div>
    <div class="details">
      <span class="config-name">No config loaded</span>
      <span class="meta">Load a DSC config to see status</span>
    </div>
  {/if}
</div>

<style>
  .widget { display: flex; align-items: center; gap: 14px; padding: 4px 0; }
  .status-indicator {
    width: 48px; height: 48px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 1.4rem; font-weight: 700; flex-shrink: 0;
  }
  .status-indicator.ok { background: #10b98120; color: #34d399; }
  .status-indicator.error { background: #ef444420; color: #f87171; }
  .status-indicator.unknown { background: var(--color-hover, #1f2937); color: var(--color-text-muted); }
  .details { display: flex; flex-direction: column; gap: 2px; }
  .config-name { font-weight: 600; font-size: 0.95rem; color: var(--color-text, #e5e7eb); }
  .meta { font-size: 0.8rem; color: var(--color-text-muted, #94a3b8); }
</style>
