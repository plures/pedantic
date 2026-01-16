import assert from 'node:assert/strict';
import { test } from 'node:test';

import { writable, derived, createReactiveState } from '../../src/logic/reactive-state';

test('writable observable emits initial value on subscribe', () => {
  const store = writable(42);
  let emittedValue: number | undefined;

  store.subscribe((value: number) => {
    emittedValue = value;
  });

  assert.equal(emittedValue, 42);
});

test('writable observable notifies subscribers on set', () => {
  const store = writable(10);
  let count = 0;
  let latestValue = 0;

  store.subscribe((value: number) => {
    count++;
    latestValue = value;
  });

  store.set(20);
  store.set(30);

  assert.equal(count, 3); // initial + 2 updates
  assert.equal(latestValue, 30);
});

test('writable observable update function works', () => {
  const store = writable(5);
  let latestValue = 0;

  store.subscribe((value: number) => {
    latestValue = value;
  });

  store.update((n: number) => n * 2);
  assert.equal(latestValue, 10);

  store.update((n: number) => n + 3);
  assert.equal(latestValue, 13);
});

test('derived observable computes values from source', () => {
  const count = writable(5);
  const doubled = derived(count, (n: number) => n * 2);

  let derivedValue = 0;
  doubled.subscribe((value: number) => {
    derivedValue = value;
  });

  assert.equal(derivedValue, 10);

  count.set(7);
  assert.equal(derivedValue, 14);
});

test('unsubscribe stops receiving updates', () => {
  const store = writable(1);
  let value = 0;

  const unsubscribe = store.subscribe((v: number) => {
    value = v;
  });

  assert.equal(value, 1);

  store.set(2);
  assert.equal(value, 2);

  unsubscribe();

  store.set(3);
  assert.equal(value, 2); // Should not update after unsubscribe
});

test('reactive state notifies subscribers on apply', () => {
  interface State {
    count: number;
    name: string;
  }

  const state = createReactiveState<State>({
    count: 0,
    name: 'test',
  });

  let updateCount = 0;
  let latestState: State | null = null;

  state.subscribe((s: State) => {
    updateCount++;
    latestState = { ...s };
  });

  assert.equal(updateCount, 1); // Initial emit

  state.apply((s: State) => {
    s.count = 10;
  });

  assert.equal(updateCount, 2);
  assert.ok(latestState);
  assert.equal((latestState as State).count, 10);
});

test('reactive state batches multiple mutations', () => {
  interface State {
    x: number;
    y: number;
  }

  const state = createReactiveState<State>({ x: 0, y: 0 });

  let updateCount = 0;
  state.subscribe(() => {
    updateCount++;
  });

  state.batch([
    (s: State) => {
      s.x = 5;
    },
    (s: State) => {
      s.y = 10;
    },
    (s: State) => {
      s.x = s.x + s.y;
    },
  ]);

  assert.equal(updateCount, 2); // Initial + 1 batched update
  assert.equal(state.get().x, 15);
  assert.equal(state.get().y, 10);
});

test('reactive state derive creates computed observables', () => {
  interface State {
    firstName: string;
    lastName: string;
  }

  const state = createReactiveState<State>({
    firstName: 'John',
    lastName: 'Doe',
  });

  const fullName = state.derive((s: State) => `${s.firstName} ${s.lastName}`);

  let name = '';
  fullName.subscribe((n: string) => {
    name = n;
  });

  assert.equal(name, 'John Doe');

  state.apply((s: State) => {
    s.firstName = 'Jane';
  });

  assert.equal(name, 'Jane Doe');
});

test('reactive state get returns current value', () => {
  const state = createReactiveState({ value: 100 });

  assert.equal(state.get().value, 100);

  state.apply((s: { value: number }) => {
    s.value = 200;
  });

  assert.equal(state.get().value, 200);
});
