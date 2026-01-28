<script>
  let model = {
    summary: {
      hostCount: 0,
      resourceCount: 0,
      osStats: {},
      resourceKinds: {},
      catalogCount: 0
    },
    hosts: [],
    resources: [],
    warnings: [],
    dbType: 'memory',
    violations: [],
    diagnostics: null
  };

  let selectedHostId = '';
  let search = '';

  $: filteredHosts = model.hosts.filter(host => {
    if (!search) return true;
    const haystack = `${host.name ?? ''} ${host.os?.caption ?? ''} ${host.os?.version ?? ''}`.toLowerCase();
    return haystack.includes(search.toLowerCase());
  });

  $: selectedHost = model.hosts.find(h => h.id === selectedHostId) || model.hosts[0];
  $: selectedResources = selectedHost
    ? model.resources.filter(r => r.hostId === selectedHost.id)
    : [];

  function selectHost(id) {
    selectedHostId = id;
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('message', event => {
      const msg = event.data;
      if (msg?.command === 'cmdbData') {
        model = msg.data || model;
        if (!selectedHostId && model.hosts?.length) {
          selectedHostId = model.hosts[0].id;
        }
      }
    });
  }
</script>

<div class="container">
  <header class="header">
    <div>
      <h2>Pedantic CMDB</h2>
      <p class="subtitle">DSC v3 system catalog overview</p>
    </div>
    <div class="chips">
      <span class="chip">Catalogs: {model.summary.catalogCount}</span>
      <span class="chip">DB: {model.dbType}</span>
    </div>
  </header>

  <section class="cards">
    <div class="card">
      <h4>Hosts</h4>
      <div class="value">{model.summary.hostCount}</div>
    </div>
    <div class="card">
      <h4>Resources</h4>
      <div class="value">{model.summary.resourceCount}</div>
    </div>
    <div class="card">
      <h4>Top OS</h4>
      <div class="value">
        {#if Object.keys(model.summary.osStats).length}
          {Object.entries(model.summary.osStats)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 1)[0][0]}
        {:else}
          —
        {/if}
      </div>
    </div>
  </section>

  {#if model.warnings?.length}
    <section class="alerts">
      {#each model.warnings as warn}
        <div class="alert">{warn}</div>
      {/each}
    </section>
  {/if}

  {#if model.violations?.length}
    <section class="alerts">
      {#each model.violations as violation}
        <div class="alert warning">{violation.message}</div>
      {/each}
    </section>
  {/if}

  <section class="grid">
    <div class="panel">
      <div class="panel-header">
        <h3>Hosts</h3>
        <input class="search" placeholder="Filter hosts…" bind:value={search} />
      </div>
      <div class="table">
        <div class="row header">
          <span>Name</span>
          <span>OS</span>
          <span>Resources</span>
        </div>
        {#if filteredHosts.length === 0}
          <div class="row empty">No hosts match your filter.</div>
        {:else}
          {#each filteredHosts as host}
            <button
              type="button"
              class="row button {host.id === selectedHost?.id ? 'active' : ''}"
              on:click={() => selectHost(host.id)}>
              <span>{host.name}</span>
              <span>{host.os?.caption ?? 'Unknown'}</span>
              <span>{host.resourceCount}</span>
            </button>
          {/each}
        {/if}
      </div>
    </div>

    <div class="panel">
      <div class="panel-header">
        <h3>Details</h3>
        {#if selectedHost}
          <span class="meta">{selectedHost.name}</span>
        {/if}
      </div>

      {#if !selectedHost}
        <div class="empty">Select a host to see details.</div>
      {:else}
        <div class="details">
          <div>
            <h4>OS</h4>
            <p>{selectedHost.os?.caption ?? 'Unknown'} {selectedHost.os?.version ?? ''}</p>
            <small>Build {selectedHost.os?.buildNumber ?? '—'}</small>
          </div>
          <div>
            <h4>CPU</h4>
            <p>{selectedHost.cpu?.name ?? 'Unknown'}</p>
            <small>{selectedHost.cpu?.cores ?? 0} cores / {selectedHost.cpu?.logicalProcessors ?? 0} logical</small>
          </div>
          <div>
            <h4>BIOS</h4>
            <p>{selectedHost.bios?.manufacturer ?? 'Unknown'}</p>
            <small>{selectedHost.bios?.biosVersion ?? '—'}</small>
          </div>
        </div>

        <h4 class="section-title">Resources</h4>
        <div class="table compact">
          <div class="row header">
            <span>Type</span>
            <span>Version</span>
            <span>Kind</span>
          </div>
          {#if selectedResources.length === 0}
            <div class="row empty">No resources listed in this catalog.</div>
          {:else}
            {#each selectedResources as res}
              <div class="row">
                <span>{res.type ?? 'Unknown'}</span>
                <span>{res.version ?? '—'}</span>
                <span>{res.kind ?? '—'}</span>
              </div>
            {/each}
          {/if}
        </div>
      {/if}
    </div>
  </section>
</div>

<style>
  :global(body) {
    margin: 0;
    font-family: var(--vscode-font-family, 'Segoe UI', sans-serif);
    color: var(--vscode-foreground);
    background: var(--vscode-editor-background);
  }

  .container {
    padding: 1rem;
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }

  h2 {
    margin: 0;
  }

  .subtitle {
    margin: 0.25rem 0 0;
    color: var(--vscode-descriptionForeground);
  }

  .chips {
    display: flex;
    gap: 0.5rem;
  }

  .chip {
    background: var(--vscode-editorWidget-background);
    border: 1px solid var(--vscode-editorWidget-border);
    padding: 0.25rem 0.5rem;
    border-radius: 999px;
    font-size: 0.75rem;
  }

  .cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0.75rem;
    margin-bottom: 1rem;
  }

  .card {
    background: var(--vscode-editorWidget-background);
    border: 1px solid var(--vscode-editorWidget-border);
    border-radius: 8px;
    padding: 0.75rem;
  }

  .card h4 {
    margin: 0;
    font-size: 0.8rem;
    color: var(--vscode-descriptionForeground);
  }

  .value {
    font-size: 1.5rem;
    font-weight: 600;
    margin-top: 0.25rem;
  }

  .alerts {
    display: grid;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .alert {
    border-left: 3px solid var(--vscode-charts-green);
    padding: 0.5rem 0.75rem;
    background: rgba(0, 120, 212, 0.1);
  }

  .alert.warning {
    border-left-color: var(--vscode-charts-yellow);
  }

  .grid {
    display: grid;
    grid-template-columns: minmax(280px, 1fr) 2fr;
    gap: 0.75rem;
  }

  .panel {
    border: 1px solid var(--vscode-editorWidget-border);
    border-radius: 10px;
    background: var(--vscode-editorWidget-background);
    padding: 0.75rem;
  }

  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
  }

  .panel-header h3 {
    margin: 0;
  }

  .search {
    background: var(--vscode-input-background);
    border: 1px solid var(--vscode-input-border);
    color: var(--vscode-input-foreground);
    padding: 0.35rem 0.5rem;
    border-radius: 6px;
  }

  .table {
    display: grid;
    gap: 0.35rem;
  }

  .row {
    display: grid;
    grid-template-columns: 1.5fr 1.5fr 0.7fr;
    gap: 0.5rem;
    padding: 0.35rem 0.25rem;
    font-size: 0.85rem;
  }

  .row.header {
    font-size: 0.75rem;
    text-transform: uppercase;
    color: var(--vscode-descriptionForeground);
  }

  .row.button {
    background: transparent;
    border: 0;
    color: inherit;
    text-align: left;
    cursor: pointer;
    border-radius: 6px;
  }

  .row.button:hover,
  .row.button.active {
    background: rgba(0, 120, 212, 0.12);
  }

  .row.empty {
    color: var(--vscode-descriptionForeground);
  }

  .details {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0.75rem;
  }

  .details h4 {
    margin: 0 0 0.25rem 0;
  }

  .section-title {
    margin-top: 1rem;
  }

  .meta {
    font-size: 0.8rem;
    color: var(--vscode-descriptionForeground);
  }

  .table.compact .row {
    grid-template-columns: 2fr 1fr 1fr;
  }

  @media (max-width: 900px) {
    .grid {
      grid-template-columns: 1fr;
    }
  }
</style>
