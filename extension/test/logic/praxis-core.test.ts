import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  createPraxisEngine,
  defineFact,
  defineEvent,
  defineRule,
  defineConstraint,
  PraxisRegistry,
} from '../../src/logic/praxis-core';

// Define test facts and events
const UserLoggedIn = defineFact<'UserLoggedIn', { userId: string }>('UserLoggedIn');
const Login = defineEvent<'LOGIN', { username: string }>('LOGIN');
const SessionCreated = defineFact<'SessionCreated', { sessionId: string }>('SessionCreated');

interface AuthContext {
  currentUser: string | null;
  sessionCount: number;
}

test('praxis engine executes rules and emits facts', () => {
  const loginRule = defineRule<AuthContext>({
    id: 'auth.login',
    description: 'Authenticate and emit fact',
    impl: (state: any, events: any) => {
      const evt = events.find(Login.is);
      if (!evt) return [];
      state.context.currentUser = evt.payload.username;
      state.context.sessionCount++;
      return [
        UserLoggedIn.create({ userId: evt.payload.username }),
        SessionCreated.create({ sessionId: `session-${state.context.sessionCount}` }),
      ];
    },
  });

  const registry = new PraxisRegistry<AuthContext>();
  registry.registerRule(loginRule);

  const engine = createPraxisEngine({
    initialContext: { currentUser: null, sessionCount: 0 },
    registry,
  });

  const result = engine.step([Login.create({ username: 'alice' })]);

  assert.equal(result.newFacts.length, 2);
  assert.equal(result.newFacts[0].tag, 'UserLoggedIn');
  assert.equal(result.newFacts[0].payload.userId, 'alice');
  assert.equal(result.newFacts[1].tag, 'SessionCreated');
  assert.equal(engine.getContext().currentUser, 'alice');
  assert.equal(engine.getContext().sessionCount, 1);
});

test('praxis engine checks constraints', () => {
  const maxSessionsConstraint = defineConstraint<AuthContext>({
    id: 'auth.maxSessions',
    description: 'Limit concurrent sessions',
    check: (state: any) => {
      if (state.context.sessionCount > 5) {
        return {
          constraintId: 'auth.maxSessions',
          message: 'Too many concurrent sessions',
          severity: 'error',
        };
      }
      return null;
    },
  });

  const registry = new PraxisRegistry<AuthContext>();
  registry.registerConstraint(maxSessionsConstraint);

  const engine = createPraxisEngine({
    initialContext: { currentUser: null, sessionCount: 6 },
    registry,
  });

  const result = engine.step([]);

  assert.equal(result.violations.length, 1);
  assert.equal(result.violations[0].constraintId, 'auth.maxSessions');
  assert.equal(result.violations[0].severity, 'error');
});

test('fact type guards work correctly', () => {
  const fact = UserLoggedIn.create({ userId: 'bob' });
  assert.ok(UserLoggedIn.is(fact));
  assert.equal(fact.tag, 'UserLoggedIn');
  assert.equal(fact.payload.userId, 'bob');
});

test('event type guards work correctly', () => {
  const event = Login.create({ username: 'charlie' });
  assert.ok(Login.is(event));
  assert.equal(event.type, 'LOGIN');
  assert.equal(event.payload.username, 'charlie');
});

test('engine diagnostics track execution when enabled', () => {
  const rule = defineRule<AuthContext>({
    id: 'test.rule',
    description: 'Test rule',
    impl: () => [],
  });

  const constraint = defineConstraint<AuthContext>({
    id: 'test.constraint',
    description: 'Test constraint',
    check: () => null,
  });

  const registry = new PraxisRegistry<AuthContext>();
  registry.registerRule(rule);
  registry.registerConstraint(constraint);

  const engine = createPraxisEngine({
    initialContext: { currentUser: null, sessionCount: 0 },
    registry,
    enableDiagnostics: true,
  });

  const result = engine.step([]);

  assert.ok(result.diagnostics);
  assert.ok(result.diagnostics.rulesExecuted.includes('test.rule'));
  assert.ok(result.diagnostics.constraintsChecked.includes('test.constraint'));
  assert.ok(typeof result.diagnostics.executionTimeMs === 'number');
});

test('engine reset clears facts and violations', () => {
  const registry = new PraxisRegistry<AuthContext>();

  const initialContext: AuthContext = { currentUser: 'alice', sessionCount: 3 };
  const engine = createPraxisEngine({
    initialContext,
    registry,
  });

  // Add some facts manually for testing
  engine.step([]);
  assert.equal(engine.getContext().currentUser, 'alice');

  const newContext: AuthContext = { currentUser: null, sessionCount: 0 };
  engine.reset(newContext);

  assert.equal(engine.getContext().currentUser, null);
  assert.equal(engine.getContext().sessionCount, 0);
  assert.equal(engine.getFacts().length, 0);
});
