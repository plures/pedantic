import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import {
  InventoryBackendUnavailableError,
  InventoryService
} from '../src/inventory/inventoryService';

describe('InventoryService', () => {
  it('fails explicitly when inventory is not configured', async () => {
    const service = InventoryService.getInstance();
    await assert.rejects(
      service.gatherInventory(),
      InventoryBackendUnavailableError
    );
  });

  it('never fabricates host facts when inventory is not configured', async () => {
    const service = InventoryService.getInstance();
    await assert.rejects(
      service.gatherHostFacts('host-1'),
      InventoryBackendUnavailableError
    );
  });

  it('never parses an inventory file without the service backend', async () => {
    const service = InventoryService.getInstance();
    await assert.rejects(
      service.parseInventoryFile('/tmp/inventory.yaml'),
      InventoryBackendUnavailableError
    );
  });
});
