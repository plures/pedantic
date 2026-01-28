"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert"));
const inventoryService_1 = require("../src/inventory/inventoryService");
(0, node_test_1.describe)('InventoryService', () => {
    (0, node_test_1.it)('should return mock inventory data', async () => {
        const service = inventoryService_1.InventoryService.getInstance();
        const inventory = await service.gatherInventory();
        assert.ok(inventory, 'Inventory should not be null');
        assert.ok(Array.isArray(inventory.hosts), 'Hosts should be an array');
        assert.ok(Array.isArray(inventory.groups), 'Groups should be an array');
        assert.ok(inventory.hosts.length > 0, 'Should have at least one host');
        assert.ok(inventory.groups.length > 0, 'Should have at least one group');
    });
    (0, node_test_1.it)('should return hosts with required properties', async () => {
        const service = inventoryService_1.InventoryService.getInstance();
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
    (0, node_test_1.it)('should return groups with required properties', async () => {
        const service = inventoryService_1.InventoryService.getInstance();
        const inventory = await service.gatherInventory();
        const group = inventory.groups[0];
        assert.ok(group.name, 'Group should have a name');
        assert.ok(Array.isArray(group.hosts), 'Group should have hosts array');
        // Handle optional vars field
        if (group.vars !== undefined) {
            assert.ok(typeof group.vars === 'object', 'Group vars should be an object if present');
        }
    });
    (0, node_test_1.it)('should gather host facts', async () => {
        const service = inventoryService_1.InventoryService.getInstance();
        const facts = await service.gatherHostFacts('localhost');
        assert.ok(facts, 'Facts should not be null');
        // Facts structure may vary, just check it's an object
        assert.ok(typeof facts === 'object', 'Facts should be an object');
    });
    (0, node_test_1.it)('should have localhost in mock data', async () => {
        const service = inventoryService_1.InventoryService.getInstance();
        const inventory = await service.gatherInventory();
        const localhost = inventory.hosts.find(h => h.name === 'localhost');
        assert.ok(localhost, 'Should have localhost host');
    });
    (0, node_test_1.it)('should have production group in mock data', async () => {
        const service = inventoryService_1.InventoryService.getInstance();
        const inventory = await service.gatherInventory();
        const prodGroup = inventory.groups.find(g => g.name === 'production');
        assert.ok(prodGroup, 'Should have production group');
        assert.ok(prodGroup.hosts.length > 0, 'Production group should have hosts');
    });
});
