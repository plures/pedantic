<script lang="ts">
  import { complianceStore } from '../../stores/compliance.js';

  const store = complianceStore;

  let status = $derived(() => (store.violations === 0 ? 'compliant' : 'drifted'));
</script>

<div class="widget">
  <div class="widget__header">
    <h3>Compliance Status</h3>
    <span class="badge {status === 'compliant' ? 'badge--ok' : 'badge--warn'}">{status}</span>
  </div>
  <div class="summary">
    <div>
      <strong>{store.totalResources}</strong>
      <span>resources</span>
    </div>
    <div>
      <strong>{store.totalResources - store.violations}</strong>
      <span>compliant</span>
    </div>
    <div>
      <strong>{store.violations}</strong>
      <span>drifted</span>
    </div>
  </div>
  <a class="link" href="/pedantic">View dashboard →</a>
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
  .summary {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
    font-size: 0.85rem;
    color: var(--color-text-muted, #94a3b8);
  }
  strong {
    display: block;
    color: var(--color-text, #e5e7eb);
    font-size: 1.1rem;
  }
  .link {
    color: var(--color-accent, #60a5fa);
    text-decoration: none;
    font-size: 0.85rem;
  }
</style>
