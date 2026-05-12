<script lang="ts">
  import { KpiCard, TrendChart } from '@plures/design-dojo';
  import { complianceStore } from '../stores/compliance.js';

  const store = complianceStore;

  let kpis = $derived(() => [
    {
      label: 'Total Resources',
      value: store.totalResources,
      delta: 0,
      deltaLabel: 'since last run',
      trend: store.complianceTrend.map((point) => point.value),
    },
    {
      label: 'Compliant %',
      value: store.compliancePercent,
      unit: '%',
      status: store.compliancePercent === 100 ? 'achieved' : store.compliancePercent >= 85 ? 'on-track' : 'at-risk',
      trend: store.complianceTrend.map((point) => point.value),
    },
    {
      label: 'Violations',
      value: store.violations,
      status: store.violations === 0 ? 'achieved' : 'behind',
      trend: store.complianceTrend.map((point) => 100 - point.value),
    },
    {
      label: 'Last Run',
      value: store.lastRunTime,
      deltaLabel: 'UTC',
    },
  ]);

  let selected = $derived(() => store.selectedConfig);
</script>

<div class="page">
  <header class="page__header">
    <div>
      <h1>Compliance Dashboard</h1>
      <p>DSC v3 compliance posture across managed hosts.</p>
    </div>
    <div class="page__actions">
      <button class="btn" on:click={() => store.validate()}>Validate</button>
      <button class="btn btn--primary" on:click={() => store.runPraxis()}>Run Praxis</button>
    </div>
  </header>

  <section class="kpi-row">
    {#each kpis as kpi}
      <KpiCard config={kpi} />
    {/each}
  </section>

  <section class="grid">
    <div class="panel">
      <div class="panel__header">
        <h2>Config Summary</h2>
        <span class="badge {selected?.status === 'draft' ? 'badge--warn' : 'badge--ok'}">
          {selected?.status ?? 'unknown'}
        </span>
      </div>
      <div class="panel__body">
        <p class="panel__title">{selected?.name}</p>
        <p class="panel__meta">Version {selected?.version} · {selected?.resource_count} resources</p>
        <p class="panel__desc">{selected?.description}</p>
        <div class="validation">
          <h3>Validation</h3>
          {#if store.validationReport?.status === 'ok'}
            <div class="validation__item ok">✅ Validation passed</div>
          {:else}
            <div class="validation__item error">❌ {store.validationReport?.errors[0]?.message}</div>
          {/if}
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel__header">
        <h2>Praxis Engine</h2>
        <span class="badge badge--accent">{store.praxisOutcome?.status ?? 'unknown'}</span>
      </div>
      <div class="panel__body">
        <p class="panel__title">Rule Outcomes</p>
        <ul class="list">
          {#each store.praxisOutcome?.messages ?? [] as message}
            <li>{message}</li>
          {/each}
        </ul>
        <div class="rule-tags">
          {#each store.praxisOutcome?.firedRules ?? [] as rule}
            <span class="tag">{rule}</span>
          {/each}
        </div>
        {#if store.praxisOutcome?.violations?.length}
          <div class="violations">
            {#each store.praxisOutcome?.violations ?? [] as violation}
              <span class="tag tag--danger">{violation}</span>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </section>

  <section class="panel">
    <div class="panel__header">
      <h2>Compliance Trend</h2>
      <span class="panel__meta">Last 7 runs</span>
    </div>
    <TrendChart data={store.complianceTrend} title="Compliance %" yLabel="Compliance" />
  </section>
</div>

<style>
  .page {
    padding: 24px;
    display: flex;
    flex-direction: column;
    gap: 24px;
    --radius-lg: 6px;
    --radius-md: 6px;
  }
  h1 {
    margin: 0 0 4px;
    font-size: 1.5rem;
  }
  p {
    margin: 0;
    color: var(--color-text-muted, #94a3b8);
  }
  .page__header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }
  .page__actions {
    display: flex;
    gap: 12px;
  }
  .btn {
    border-radius: 6px;
    border: 1px solid var(--color-border, #1f2937);
    background: var(--color-surface, #111827);
    color: var(--color-text, #e5e7eb);
    padding: 8px 14px;
    font-weight: 600;
    cursor: pointer;
  }
  .btn--primary {
    background: var(--color-accent, #2563eb);
    border-color: transparent;
  }
  .kpi-row {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 16px;
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
    justify-content: space-between;
    align-items: center;
  }
  .panel__title {
    font-weight: 600;
    color: var(--color-text, #e5e7eb);
  }
  .panel__meta {
    font-size: 0.85rem;
    color: var(--color-text-muted, #94a3b8);
  }
  .panel__desc {
    color: var(--color-text-muted, #94a3b8);
  }
  .badge {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
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
  .badge--accent {
    color: var(--color-accent, #60a5fa);
    background: #2563eb20;
  }
  .validation {
    border-top: 1px solid var(--color-border, #1f2937);
    padding-top: 12px;
  }
  .validation__item {
    margin-top: 8px;
    font-size: 0.9rem;
  }
  .validation__item.error {
    color: #f87171;
  }
  .validation__item.ok {
    color: #34d399;
  }
  .list {
    margin: 0;
    padding-left: 18px;
    color: var(--color-text-muted, #94a3b8);
  }
  .rule-tags,
  .violations {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .tag {
    border-radius: 999px;
    padding: 4px 10px;
    font-size: 0.75rem;
    background: var(--color-hover, #1f2937);
    color: var(--color-text, #e5e7eb);
  }
  .tag--danger {
    background: #ef444420;
    color: #f87171;
  }
</style>
