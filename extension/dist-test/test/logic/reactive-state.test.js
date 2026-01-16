"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = require("node:test");
const reactive_state_1 = require("../../src/logic/reactive-state");
(0, node_test_1.test)('writable observable emits initial value on subscribe', () => {
    const store = (0, reactive_state_1.writable)(42);
    let emittedValue;
    store.subscribe((value) => {
        emittedValue = value;
    });
    strict_1.default.equal(emittedValue, 42);
});
(0, node_test_1.test)('writable observable notifies subscribers on set', () => {
    const store = (0, reactive_state_1.writable)(10);
    let count = 0;
    let latestValue = 0;
    store.subscribe((value) => {
        count++;
        latestValue = value;
    });
    store.set(20);
    store.set(30);
    strict_1.default.equal(count, 3); // initial + 2 updates
    strict_1.default.equal(latestValue, 30);
});
(0, node_test_1.test)('writable observable update function works', () => {
    const store = (0, reactive_state_1.writable)(5);
    let latestValue = 0;
    store.subscribe((value) => {
        latestValue = value;
    });
    store.update((n) => n * 2);
    strict_1.default.equal(latestValue, 10);
    store.update((n) => n + 3);
    strict_1.default.equal(latestValue, 13);
});
(0, node_test_1.test)('derived observable computes values from source', () => {
    const count = (0, reactive_state_1.writable)(5);
    const doubled = (0, reactive_state_1.derived)(count, (n) => n * 2);
    let derivedValue = 0;
    doubled.subscribe((value) => {
        derivedValue = value;
    });
    strict_1.default.equal(derivedValue, 10);
    count.set(7);
    strict_1.default.equal(derivedValue, 14);
});
(0, node_test_1.test)('unsubscribe stops receiving updates', () => {
    const store = (0, reactive_state_1.writable)(1);
    let value = 0;
    const unsubscribe = store.subscribe((v) => {
        value = v;
    });
    strict_1.default.equal(value, 1);
    store.set(2);
    strict_1.default.equal(value, 2);
    unsubscribe();
    store.set(3);
    strict_1.default.equal(value, 2); // Should not update after unsubscribe
});
(0, node_test_1.test)('reactive state notifies subscribers on apply', () => {
    const state = (0, reactive_state_1.createReactiveState)({
        count: 0,
        name: 'test',
    });
    let updateCount = 0;
    let latestState = null;
    state.subscribe((s) => {
        updateCount++;
        latestState = { ...s };
    });
    strict_1.default.equal(updateCount, 1); // Initial emit
    state.apply((s) => {
        s.count = 10;
    });
    strict_1.default.equal(updateCount, 2);
    strict_1.default.ok(latestState);
    strict_1.default.equal(latestState.count, 10);
});
(0, node_test_1.test)('reactive state batches multiple mutations', () => {
    const state = (0, reactive_state_1.createReactiveState)({ x: 0, y: 0 });
    let updateCount = 0;
    state.subscribe(() => {
        updateCount++;
    });
    state.batch([
        (s) => {
            s.x = 5;
        },
        (s) => {
            s.y = 10;
        },
        (s) => {
            s.x = s.x + s.y;
        },
    ]);
    strict_1.default.equal(updateCount, 2); // Initial + 1 batched update
    strict_1.default.equal(state.get().x, 15);
    strict_1.default.equal(state.get().y, 10);
});
(0, node_test_1.test)('reactive state derive creates computed observables', () => {
    const state = (0, reactive_state_1.createReactiveState)({
        firstName: 'John',
        lastName: 'Doe',
    });
    const fullName = state.derive((s) => `${s.firstName} ${s.lastName}`);
    let name = '';
    fullName.subscribe((n) => {
        name = n;
    });
    strict_1.default.equal(name, 'John Doe');
    state.apply((s) => {
        s.firstName = 'Jane';
    });
    strict_1.default.equal(name, 'Jane Doe');
});
(0, node_test_1.test)('reactive state get returns current value', () => {
    const state = (0, reactive_state_1.createReactiveState)({ value: 100 });
    strict_1.default.equal(state.get().value, 100);
    state.apply((s) => {
        s.value = 200;
    });
    strict_1.default.equal(state.get().value, 200);
});
