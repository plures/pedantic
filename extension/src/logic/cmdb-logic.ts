import { createDbClient, type DbClient } from './pluresdb-adapter';
import {
  createPraxisEngine,
  defineFact,
  defineEvent,
  defineRule,
  defineConstraint,
  PraxisRegistry,
  type ConstraintViolation,
  type Fact,
  type StepDiagnostics,
} from './praxis-adapter';

export interface CmdbCatalog {
  meta?: Record<string, any>;
  configuration?: Record<string, any>;
  resources?: any[];
}

export interface CmdbHost {
  id: string;
  name: string;
  sourcePath?: string;
  generatedAt?: string;
  os?: {
    caption?: string;
    version?: string;
    buildNumber?: string;
    installDate?: string;
  };
  bios?: {
    manufacturer?: string;
    biosVersion?: string;
    serialNumber?: string;
  };
  cpu?: {
    name?: string;
    cores?: number;
    logicalProcessors?: number;
  };
  network?: Array<{ name?: string; mac?: string; linkSpeed?: string }>;
  resourceCount: number;
}

export interface CmdbResource {
  id: string;
  hostId: string;
  type?: string;
  version?: string;
  kind?: string;
  description?: string;
}

export interface CmdbSummary {
  hostCount: number;
  resourceCount: number;
  osStats: Record<string, number>;
  resourceKinds: Record<string, number>;
  catalogCount: number;
}

export interface CmdbModel {
  summary: CmdbSummary;
  hosts: CmdbHost[];
  resources: CmdbResource[];
  warnings: string[];
  dbType: string;
  facts: Fact[];
  violations: ConstraintViolation[];
  diagnostics?: StepDiagnostics;
}

interface CmdbContext {
  catalogs: CmdbCatalog[];
  hosts: CmdbHost[];
  resources: CmdbResource[];
  summary: CmdbSummary;
  warnings: string[];
  db: DbClient;
}

export const LoadCatalogs = defineEvent<
  'CMDB_LOAD_CATALOGS',
  { catalogs: CmdbCatalog[] }
>('CMDB_LOAD_CATALOGS');

export const HostDiscovered = defineFact<
  'HostDiscovered',
  { host: CmdbHost }
>('HostDiscovered');

export const ResourceDiscovered = defineFact<
  'ResourceDiscovered',
  { resource: CmdbResource }
>('ResourceDiscovered');

function normalizeString(value: any): string | undefined {
  if (value === undefined || value === null) return undefined;
  return String(value);
}

function getHostName(meta: Record<string, any> | undefined, configuration: Record<string, any> | undefined, index: number): string {
  return (
    meta?.computer ||
    meta?.host ||
    meta?.name ||
    configuration?.OS?.ComputerName ||
    configuration?.OS?.Caption ||
    `host-${index + 1}`
  );
}

function getOsCaption(configuration: Record<string, any> | undefined): string {
  return configuration?.OS?.Caption || configuration?.OS?.Name || 'Unknown';
}

function upsertRecord(db: DbClient, record: Record<string, any> & { _id: string; _type: string }) {
  if (db.type === 'memory') {
    db.client.upsert(record);
    return;
  }

  const client = db.client as any;
  try {
    if (typeof client?.upsert === 'function') {
      client.upsert(record);
      return;
    }
    if (typeof client?.put === 'function') {
      client.put(record);
      return;
    }
    if (typeof client?.insert === 'function') {
      client.insert(record);
      return;
    }
  } catch {
    // ignore pluresdb adapter errors
  }
}

const catalogProcessingRule = defineRule<CmdbContext>({
  id: 'cmdb.process-catalogs',
  description: 'Load DSC catalogs into CMDB context and database',
  impl: (state, events) => {
    const loadEvent = events.find(LoadCatalogs.is);
    if (!loadEvent) return [];

    const catalogs = loadEvent.payload.catalogs || [];
    state.context.catalogs = catalogs;
    state.context.hosts = [];
    state.context.resources = [];
    state.context.summary = {
      hostCount: 0,
      resourceCount: 0,
      osStats: {},
      resourceKinds: {},
      catalogCount: catalogs.length,
    };

    const facts: Fact[] = [];

    catalogs.forEach((catalog, index) => {
      const meta = catalog.meta || {};
      const configuration = catalog.configuration || {};
      const hostName = getHostName(meta, configuration, index);
      const hostId = `${hostName}:${index}`;

      const host: CmdbHost = {
        id: hostId,
        name: hostName,
        sourcePath: normalizeString(meta.sourcePath),
        generatedAt: normalizeString(meta.generatedAt),
        os: {
          caption: normalizeString(configuration.OS?.Caption),
          version: normalizeString(configuration.OS?.Version),
          buildNumber: normalizeString(configuration.OS?.BuildNumber),
          installDate: normalizeString(configuration.OS?.InstallDate),
        },
        bios: {
          manufacturer: normalizeString(configuration.BIOS?.Manufacturer),
          biosVersion: normalizeString(configuration.BIOS?.SMBIOSBIOSVersion),
          serialNumber: normalizeString(configuration.BIOS?.SerialNumber),
        },
        cpu: {
          name: normalizeString(configuration.CPU?.Name),
          cores: configuration.CPU?.Cores,
          logicalProcessors: configuration.CPU?.LogicalProcessors,
        },
        network: Array.isArray(configuration.Network)
          ? configuration.Network.map((nic: any) => ({
              name: normalizeString(nic.Name),
              mac: normalizeString(nic.Mac),
              linkSpeed: normalizeString(nic.LinkSpeed),
            }))
          : [],
        resourceCount: Array.isArray(catalog.resources) ? catalog.resources.length : 0,
      };

      state.context.summary.hostCount += 1;
      const osKey = getOsCaption(configuration);
      state.context.summary.osStats[osKey] = (state.context.summary.osStats[osKey] || 0) + 1;

      state.context.hosts.push(host);
      upsertRecord(state.context.db, { _id: hostId, _type: 'host', ...host });
      facts.push(HostDiscovered.create({ host }));

      const resources = Array.isArray(catalog.resources) ? catalog.resources : [];
      resources.forEach((resource: any, resIndex: number) => {
        const type = normalizeString(resource.type ?? resource.Type ?? resource.name ?? resource.Name);
        const version = normalizeString(resource.version ?? resource.Version);
        const kind = normalizeString(resource.kind ?? resource.Kind);
        const description = normalizeString(resource.description ?? resource.Description);
        const resourceId = `${hostId}:${type ?? 'resource'}:${version ?? resIndex}`;

        const cmdbResource: CmdbResource = {
          id: resourceId,
          hostId,
          type,
          version,
          kind,
          description,
        };

        state.context.resources.push(cmdbResource);
        upsertRecord(state.context.db, { _id: resourceId, _type: 'resource', ...cmdbResource });

        state.context.summary.resourceCount += 1;
        if (kind) {
          state.context.summary.resourceKinds[kind] = (state.context.summary.resourceKinds[kind] || 0) + 1;
        }

        facts.push(ResourceDiscovered.create({ resource: cmdbResource }));
      });
    });

    return facts;
  },
});

const minimumHostsConstraint = defineConstraint<CmdbContext>({
  id: 'cmdb.minimum-hosts',
  description: 'At least one host catalog should be loaded',
  check: (state) => {
    if (state.context.summary.hostCount === 0) {
      return {
        constraintId: 'cmdb.minimum-hosts',
        message: 'No catalogs were loaded. Generate or provide DSC catalogs to populate the CMDB.',
        severity: 'warning',
      };
    }

    return null;
  },
});

export function buildCmdbModel(
  catalogs: CmdbCatalog[],
  warnings: string[] = [],
  enableDiagnostics = false
): CmdbModel {
  const registry = new PraxisRegistry<CmdbContext>();
  registry.registerRule(catalogProcessingRule);
  registry.registerConstraint(minimumHostsConstraint);

  const db = createDbClient();

  const engine = createPraxisEngine({
    initialContext: {
      catalogs: [],
      hosts: [],
      resources: [],
      summary: {
        hostCount: 0,
        resourceCount: 0,
        osStats: {},
        resourceKinds: {},
        catalogCount: 0,
      },
      warnings: [...warnings],
      db,
    },
    registry,
    enableDiagnostics,
  });

  const result = engine.step([LoadCatalogs.create({ catalogs })]);

  return {
    summary: engine.getContext().summary,
    hosts: engine.getContext().hosts,
    resources: engine.getContext().resources,
    warnings: engine.getContext().warnings,
    dbType: db.type,
    facts: engine.getFacts(),
    violations: engine.getViolations(),
    diagnostics: result.diagnostics,
  };
}
