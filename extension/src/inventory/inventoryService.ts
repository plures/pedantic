import { HostFacts, Inventory } from './inventoryModel';

export class InventoryBackendUnavailableError extends Error {
  constructor() {
    super('Inventory and host facts are unavailable because no Pedantic service backend is configured.');
    this.name = 'InventoryBackendUnavailableError';
  }
}

export class InventoryService {
  private static instance: InventoryService;

  static getInstance(): InventoryService {
    if (!InventoryService.instance) {
      InventoryService.instance = new InventoryService();
    }
    return InventoryService.instance;
  }

  private constructor() {}

  async gatherInventory(): Promise<Inventory> {
    throw new InventoryBackendUnavailableError();
  }

  async gatherHostFacts(_hostName: string): Promise<HostFacts> {
    throw new InventoryBackendUnavailableError();
  }

  async parseInventoryFile(_filePath: string): Promise<Inventory> {
    throw new InventoryBackendUnavailableError();
  }
}
