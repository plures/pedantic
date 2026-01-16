# Praxis Integration Guide

## Overview

This project integrates concepts and patterns from the [plures/praxis](https://github.com/plures/praxis) framework to provide a clean, maintainable approach to logic handling and state management in the Pedantic DSC extension.

## What is Praxis?

Praxis is a TypeScript-based, schema-driven application framework that emphasizes:

- **Typed logic modeling**: Facts, events, rules, and constraints
- **Separation of concerns**: Business logic separated from UI and side effects
- **Reactive state management**: Observable state updates
- **Schema-driven design**: Declarative definitions drive code generation

## Integration in Pedantic

The praxis-inspired patterns are implemented in the `/extension/src/logic` directory:

### 1. Logic Engine (`praxis-core.ts`)

Core primitives for event-driven logic processing:

```typescript
import { createPraxisEngine, defineFact, defineEvent, defineRule, PraxisRegistry } from './logic/praxis-core';

// Define facts that represent state changes
const PackageInstalled = defineFact<'PackageInstalled', { packageId: string }>('PackageInstalled');

// Define events that trigger processing
const InstallPackage = defineEvent<'INSTALL_PACKAGE', { packageId: string }>('INSTALL_PACKAGE');

// Define rules that process events and emit facts
const installRule = defineRule({
  id: 'package.install',
  description: 'Process package installation',
  impl: (state, events) => {
    const evt = events.find(InstallPackage.is);
    if (!evt) return [];
    
    // Business logic here
    return [PackageInstalled.create({ packageId: evt.payload.packageId })];
  },
});

// Create and use the engine
const registry = new PraxisRegistry();
registry.registerRule(installRule);

const engine = createPraxisEngine({
  initialContext: { packages: [] },
  registry,
});

const result = engine.step([InstallPackage.create({ packageId: 'git' })]);
```

**Key Benefits:**
- Type-safe fact and event definitions
- Testable business logic (rules are pure functions)
- Introspection and diagnostics support
- Clear separation of logic from execution

### 2. DSL Logic (`dsl-logic.ts`)

Domain-specific logic for DSL document processing using praxis patterns:

```typescript
import { processDocument } from './logic/dsl-logic';

const doc = parseSimple(yamlSource);
const result = processDocument(doc);

// Access processed data
console.log(result.context.packageCount);
console.log(result.context.providerStats);
console.log(result.violations); // Constraint violations
console.log(result.facts); // All emitted facts
```

**Features:**
- Document parsing and validation rules
- Package discovery and cataloging
- Constraint checking (max packages, required fields, etc.)
- Diagnostic processing

### 3. Reactive State (`reactive-state.ts`)

Framework-agnostic reactive state management similar to Svelte stores:

```typescript
import { writable, derived, createReactiveState } from './logic/reactive-state';

// Simple observables
const count = writable(0);
const doubled = derived(count, (n) => n * 2);

count.subscribe((value) => {
  console.log('Count:', value);
});

count.set(5); // Triggers subscription

// Complex reactive state
interface AppState {
  documents: Document[];
  activeDocument: Document | null;
}

const state = createReactiveState<AppState>({
  documents: [],
  activeDocument: null,
});

// Subscribe to state changes
state.subscribe((s) => {
  updateUI(s);
});

// Apply mutations (batched for performance)
state.apply((s) => {
  s.documents.push(newDoc);
  s.activeDocument = newDoc;
});
```

**Key Benefits:**
- Observable state updates for UI reactivity
- Batched updates for performance
- Derived/computed values
- Compatible with any UI framework

## Design Principles

The praxis integration follows these core principles:

### 1. Separation of Concerns

**Business logic** is separated from:
- Parsing (AST generation)
- UI rendering
- Side effects (file I/O, network)

Example: DSL validation rules don't know about VS Code APIs - they just process documents and emit facts.

### 2. Typed Everything

All facts, events, and contexts are strongly typed:

```typescript
// Type-safe fact definition
const ValidationIssue = defineFact<
  'ValidationIssue',
  { severity: 'error' | 'warning'; code: string; message: string }
>('ValidationIssue');

// Compiler catches type errors
ValidationIssue.create({ severity: 'invalid' }); // ❌ Type error
```

### 3. Testable Logic

Rules are pure functions that can be tested in isolation:

```typescript
// Easy to test - no mocks needed
test('package discovery rule', () => {
  const rule = packageDiscoveryRule;
  const state = { packageCount: 0, /* ... */ };
  const events = [ParseDocument.create({ document: doc })];
  
  const facts = rule.impl(state, events);
  
  assert.equal(facts.length, 2);
  assert.equal(facts[0].tag, 'PackageDiscovered');
});
```

### 4. Introspection and Diagnostics

The engine can track what happened during processing:

```typescript
const engine = createPraxisEngine({
  initialContext: { /* ... */ },
  registry,
  enableDiagnostics: true,
});

const result = engine.step(events);

console.log(result.diagnostics.rulesExecuted);      // ['dsl.process-document', 'dsl.discover-packages']
console.log(result.diagnostics.constraintsChecked); // ['dsl.minimum-packages']
console.log(result.diagnostics.executionTimeMs);    // 12.5
```

## Extension Points

The praxis-inspired architecture makes it easy to extend:

### Adding New Facts

```typescript
export const PackageValidated = defineFact<
  'PackageValidated',
  { packageId: string; isValid: boolean }
>('PackageValidated');
```

### Adding New Events

```typescript
export const ValidateAllPackages = defineEvent<
  'VALIDATE_ALL',
  { force: boolean }
>('VALIDATE_ALL');
```

### Adding New Rules

```typescript
const validationRule = defineRule<DslContext>({
  id: 'dsl.validate-all',
  description: 'Validate all packages in document',
  impl: (state, events) => {
    const evt = events.find(ValidateAllPackages.is);
    if (!evt) return [];
    
    const facts = [];
    // Validation logic...
    return facts;
  },
});

registry.registerRule(validationRule);
```

### Adding New Constraints

```typescript
const uniquePackageNamesConstraint = defineConstraint<DslContext>({
  id: 'dsl.unique-package-names',
  description: 'Package IDs must be unique',
  check: (state) => {
    // Check logic...
    return null; // or return violation
  },
});

registry.registerConstraint(uniquePackageNamesConstraint);
```

## Benefits of This Approach

1. **Maintainability**: Clear structure makes code easy to understand and modify
2. **Testability**: Pure functions and dependency injection enable comprehensive testing
3. **Type Safety**: TypeScript catches errors at compile time
4. **Performance**: Batched updates and reactive patterns minimize unnecessary work
5. **Scalability**: Easy to add new rules, constraints, and facts without touching existing code
6. **Debugging**: Diagnostics and introspection help understand what's happening

## Comparison to Traditional Approaches

| Aspect | Traditional | Praxis-Inspired |
|--------|------------|-----------------|
| Logic location | Scattered across files | Centralized in rules |
| Testing | Requires mocking | Pure functions |
| State updates | Imperative | Reactive/declarative |
| Type safety | Manual type guards | Automatic type inference |
| Extensibility | Modify existing code | Add new rules |
| Debugging | Console logs | Structured diagnostics |

## Future Enhancements

The praxis integration provides a foundation for:

1. **AI/MCP Integration**: Logic rules can be used as tools for AI agents
2. **Undo/Redo**: Fact stream enables time-travel debugging
3. **Persistence**: Facts can be stored and replayed
4. **Distributed Processing**: Events can be sent across processes/network
5. **Visual Debugging**: Fact/event streams can be visualized

## References

- [Praxis GitHub Repository](https://github.com/plures/praxis)
- [Praxis Framework Introduction](http://praxis-framework.io/)
- [Extension Architecture](./ARCHITECTURE.md)
- [DSL Specification](./DSL-SPEC.md)

## Testing

All praxis-inspired logic is thoroughly tested:

```bash
cd extension
npm test
```

Tests cover:
- Core logic engine (facts, events, rules, constraints)
- DSL-specific logic (document processing, validation)
- Reactive state management (observables, derived values)

See `/extension/test/logic/` for test examples.
