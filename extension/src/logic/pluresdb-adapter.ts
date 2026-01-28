type PluresDbModule = {
  createDb?: (options?: any) => any;
  createClient?: (options?: any) => any;
};

function tryRequire(moduleName: string): PluresDbModule | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require(moduleName) as PluresDbModule;
  } catch {
    return null;
  }
}

const plures = tryRequire('pluresdb');

type InMemoryRecord = Record<string, any> & { _id: string; _type: string };

export interface InMemoryDb {
  upsert(record: InMemoryRecord): void;
  query(filter: Partial<InMemoryRecord>): InMemoryRecord[];
  list(): InMemoryRecord[];
}

class SimpleInMemoryDb implements InMemoryDb {
  private records = new Map<string, InMemoryRecord>();

  upsert(record: InMemoryRecord): void {
    this.records.set(record._id, record);
  }

  query(filter: Partial<InMemoryRecord>): InMemoryRecord[] {
    const entries = Array.from(this.records.values());
    return entries.filter(entry => {
      return Object.entries(filter).every(([key, value]) => (entry as any)[key] === value);
    });
  }

  list(): InMemoryRecord[] {
    return Array.from(this.records.values());
  }
}

export type DbClient = {
  type: 'pluresdb' | 'memory';
  client: any;
};

export function createDbClient(): DbClient {
  if (plures?.createDb) {
    return { type: 'pluresdb', client: plures.createDb({ mode: 'memory' }) };
  }
  if (plures?.createClient) {
    return { type: 'pluresdb', client: plures.createClient({ mode: 'memory' }) };
  }
  return { type: 'memory', client: new SimpleInMemoryDb() };
}
