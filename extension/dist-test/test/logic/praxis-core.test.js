"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = require("node:test");
const praxis_core_1 = require("../../src/logic/praxis-core");
// Define test facts and events
const UserLoggedIn = (0, praxis_core_1.defineFact)('UserLoggedIn');
const Login = (0, praxis_core_1.defineEvent)('LOGIN');
const SessionCreated = (0, praxis_core_1.defineFact)('SessionCreated');
(0, node_test_1.test)('praxis engine executes rules and emits facts', () => {
    const loginRule = (0, praxis_core_1.defineRule)({
        id: 'auth.login',
        description: 'Authenticate and emit fact',
        impl: (state, events) => {
            const evt = events.find(Login.is);
            if (!evt)
                return [];
            state.context.currentUser = evt.payload.username;
            state.context.sessionCount++;
            return [
                UserLoggedIn.create({ userId: evt.payload.username }),
                SessionCreated.create({ sessionId: `session-${state.context.sessionCount}` }),
            ];
        },
    });
    const registry = new praxis_core_1.PraxisRegistry();
    registry.registerRule(loginRule);
    const engine = (0, praxis_core_1.createPraxisEngine)({
        initialContext: { currentUser: null, sessionCount: 0 },
        registry,
    });
    const result = engine.step([Login.create({ username: 'alice' })]);
    strict_1.default.equal(result.newFacts.length, 2);
    strict_1.default.equal(result.newFacts[0].tag, 'UserLoggedIn');
    strict_1.default.equal(result.newFacts[0].payload.userId, 'alice');
    strict_1.default.equal(result.newFacts[1].tag, 'SessionCreated');
    strict_1.default.equal(engine.getContext().currentUser, 'alice');
    strict_1.default.equal(engine.getContext().sessionCount, 1);
});
(0, node_test_1.test)('praxis engine checks constraints', () => {
    const maxSessionsConstraint = (0, praxis_core_1.defineConstraint)({
        id: 'auth.maxSessions',
        description: 'Limit concurrent sessions',
        check: (state) => {
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
    const registry = new praxis_core_1.PraxisRegistry();
    registry.registerConstraint(maxSessionsConstraint);
    const engine = (0, praxis_core_1.createPraxisEngine)({
        initialContext: { currentUser: null, sessionCount: 6 },
        registry,
    });
    const result = engine.step([]);
    strict_1.default.equal(result.violations.length, 1);
    strict_1.default.equal(result.violations[0].constraintId, 'auth.maxSessions');
    strict_1.default.equal(result.violations[0].severity, 'error');
});
(0, node_test_1.test)('fact type guards work correctly', () => {
    const fact = UserLoggedIn.create({ userId: 'bob' });
    strict_1.default.ok(UserLoggedIn.is(fact));
    strict_1.default.equal(fact.tag, 'UserLoggedIn');
    strict_1.default.equal(fact.payload.userId, 'bob');
});
(0, node_test_1.test)('event type guards work correctly', () => {
    const event = Login.create({ username: 'charlie' });
    strict_1.default.ok(Login.is(event));
    strict_1.default.equal(event.type, 'LOGIN');
    strict_1.default.equal(event.payload.username, 'charlie');
});
(0, node_test_1.test)('engine diagnostics track execution when enabled', () => {
    const rule = (0, praxis_core_1.defineRule)({
        id: 'test.rule',
        description: 'Test rule',
        impl: () => [],
    });
    const constraint = (0, praxis_core_1.defineConstraint)({
        id: 'test.constraint',
        description: 'Test constraint',
        check: () => null,
    });
    const registry = new praxis_core_1.PraxisRegistry();
    registry.registerRule(rule);
    registry.registerConstraint(constraint);
    const engine = (0, praxis_core_1.createPraxisEngine)({
        initialContext: { currentUser: null, sessionCount: 0 },
        registry,
        enableDiagnostics: true,
    });
    const result = engine.step([]);
    strict_1.default.ok(result.diagnostics);
    strict_1.default.ok(result.diagnostics.rulesExecuted.includes('test.rule'));
    strict_1.default.ok(result.diagnostics.constraintsChecked.includes('test.constraint'));
    strict_1.default.ok(typeof result.diagnostics.executionTimeMs === 'number');
});
(0, node_test_1.test)('engine reset clears facts and violations', () => {
    const registry = new praxis_core_1.PraxisRegistry();
    const initialContext = { currentUser: 'alice', sessionCount: 3 };
    const engine = (0, praxis_core_1.createPraxisEngine)({
        initialContext,
        registry,
    });
    // Add some facts manually for testing
    engine.step([]);
    strict_1.default.equal(engine.getContext().currentUser, 'alice');
    const newContext = { currentUser: null, sessionCount: 0 };
    engine.reset(newContext);
    strict_1.default.equal(engine.getContext().currentUser, null);
    strict_1.default.equal(engine.getContext().sessionCount, 0);
    strict_1.default.equal(engine.getFacts().length, 0);
});
