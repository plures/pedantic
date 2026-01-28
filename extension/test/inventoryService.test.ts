import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import { InventoryService } from '../src/inventory/inventoryService';

describe('InventoryService', () => {
  it('should return mock inventory data', async () => {
    const service = InventoryService.getInstance();
    const inventory = await service.gatherInventory();

    assert.ok(inventory, 'Inventory should not be null');
    assert.ok(Array.isArray(inventory.hosts), 'Hosts should be an array');
    assert.ok(Array.isArray(inventory.groups), 'Groups should be an array');
    assert.ok(inventory.hosts.length > 0, 'Should have at least one host');
    assert.ok(inventory.groups.length > 0, 'Should have at least one group');
  });

  it('should return hosts with required properties', async () => {
    const service = InventoryService.getInstance();
    const inventory = await service.gatherInventory();
    const host = inventory.hosts[0];

    assert.ok(host.name, 'Host should have a name');
    // Handle optional fields - vars, facts, groups may be undefined
    if (host.vars !== undefined) {
      assert.ok(typeof host.vars === 'object', 'Host vars should be an object if present');
    }
    if (host.facts !== undefined) {
      assert.ok(typeof host.facts === 'object', 'Host facts should be an object if present');
    }
    if (host.groups !== undefined) {
      assert.ok(Array.isArray(host.groups), 'Host groups should be an array if present');
    }
  });

  it('should return groups with required properties', async () => {
    const service = InventoryService.getInstance();
    const inventory = await service.gatherInventory();
    const group = inventory.groups[0];

    assert.ok(group.name, 'Group should have a name');
    assert.ok(Array.isArray(group.hosts), 'Group should have hosts array');
    // Handle optional vars field
    if (group.vars !== undefined) {
      assert.ok(typeof group.vars === 'object', 'Group vars should be an object if present');
    }
  });

  it('should gather host facts', async () => {
    const service = InventoryService.getInstance();
    const facts = await service.gatherHostFacts('localhost');

    assert.ok(facts, 'Facts should not be null');
    // Facts structure may vary, just check it's an object
    assert.ok(typeof facts === 'object', 'Facts should be an object');
  });

  it('should have localhost in mock data', async () => {
    const service = InventoryService.getInstance();
    const inventory = await service.gatherInventory();
    const localhost = inventory.hosts.find(h => h.name === 'localhost');

    assert.ok(localhost, 'Should have localhost host');
  });

  it('should have production group in mock data', async () => {
    const service = InventoryService.getInstance();
    const inventory = await service.gatherInventory();
    const prodGroup = inventory.groups.find(g => g.name === 'production');

    assert.ok(prodGroup, 'Should have production group');
    assert.ok(prodGroup.hosts.length > 0, 'Production group should have hosts');
  });
});
