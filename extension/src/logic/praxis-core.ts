// Praxis-inspired logic engine for Pedantic DSL processing
// Based on plures/praxis: typed facts, events, rules, and constraints

/**
 * Core types for the praxis-inspired logic engine
 */

// Generic fact type with tag and payload
export interface Fact<Tag extends string = string, Payload = any> {
  tag: Tag;
  payload: Payload;
  timestamp?: number;
}

// Generic event type
export interface Event<Type extends string = string, Payload = any> {
  type: Type;
  payload: Payload;
  timestamp: number;
}

// Rule definition
export interface Rule<Context = any> {
  id: string;
  description: string;
  impl: (state: EngineState<Context>, events: Event[]) => Fact[];
}

// Constraint definition
export interface Constraint<Context = any> {
  id: string;
  description: string;
  check: (state: EngineState<Context>) => ConstraintViolation | null;
}

// Constraint violation
export interface ConstraintViolation {
  constraintId: string;
  message: string;
  severity: 'error' | 'warning';
}

// Engine state
export interface EngineState<Context = any> {
  context: Context;
  facts: Fact[];
  violations: ConstraintViolation[];
}

// Rule registry
export class PraxisRegistry<Context = any> {
  private rules: Map<string, Rule<Context>> = new Map();
  private constraints: Map<string, Constraint<Context>> = new Map();

  registerRule(rule: Rule<Context>): void {
    this.rules.set(rule.id, rule);
  }

  registerConstraint(constraint: Constraint<Context>): void {
    this.constraints.set(constraint.id, constraint);
  }

  getRules(): Rule<Context>[] {
    return Array.from(this.rules.values());
  }

  getConstraints(): Constraint<Context>[] {
    return Array.from(this.constraints.values());
  }

  getRule(id: string): Rule<Context> | undefined {
    return this.rules.get(id);
  }

  getConstraint(id: string): Constraint<Context> | undefined {
    return this.constraints.get(id);
  }
}

// Engine configuration
export interface EngineConfig<Context> {
  initialContext: Context;
  registry: PraxisRegistry<Context>;
  enableDiagnostics?: boolean;
}

// Step result
export interface StepResult<Context> {
  state: EngineState<Context>;
  newFacts: Fact[];
  violations: ConstraintViolation[];
  diagnostics?: StepDiagnostics;
}

// Step diagnostics for introspection
export interface StepDiagnostics {
  rulesExecuted: string[];
  constraintsChecked: string[];
  executionTimeMs: number;
}

/**
 * Praxis-inspired logic engine
 */
export class PraxisEngine<Context = any> {
  private state: EngineState<Context>;
  private registry: PraxisRegistry<Context>;
  private enableDiagnostics: boolean;

  constructor(config: EngineConfig<Context>) {
    this.state = {
      context: config.initialContext,
      facts: [],
      violations: [],
    };
    this.registry = config.registry;
    this.enableDiagnostics = config.enableDiagnostics ?? false;
  }

  /**
   * Execute one processing step with given events
   */
  step(events: Event[]): StepResult<Context> {
    const startTime = this.enableDiagnostics ? Date.now() : 0;
    const diagnostics: StepDiagnostics = {
      rulesExecuted: [],
      constraintsChecked: [],
      executionTimeMs: 0,
    };

    const newFacts: Fact[] = [];

    // Execute all rules
    for (const rule of this.registry.getRules()) {
      const facts = rule.impl(this.state, events);
      newFacts.push(...facts);
      if (this.enableDiagnostics) {
        diagnostics.rulesExecuted.push(rule.id);
      }
    }

    // Add new facts to state
    this.state.facts.push(...newFacts);

    // Check all constraints
    const violations: ConstraintViolation[] = [];
    for (const constraint of this.registry.getConstraints()) {
      const violation = constraint.check(this.state);
      if (violation) {
        violations.push(violation);
      }
      if (this.enableDiagnostics) {
        diagnostics.constraintsChecked.push(constraint.id);
      }
    }

    this.state.violations = violations;

    if (this.enableDiagnostics) {
      diagnostics.executionTimeMs = Date.now() - startTime;
    }

    return {
      state: this.state,
      newFacts,
      violations,
      diagnostics: this.enableDiagnostics ? diagnostics : undefined,
    };
  }

  /**
   * Get current engine state
   */
  getState(): EngineState<Context> {
    return this.state;
  }

  /**
   * Get current context
   */
  getContext(): Context {
    return this.state.context;
  }

  /**
   * Get all facts
   */
  getFacts(): Fact[] {
    return this.state.facts;
  }

  /**
   * Get current violations
   */
  getViolations(): ConstraintViolation[] {
    return this.state.violations;
  }

  /**
   * Reset engine to initial state
   */
  reset(context?: Context): void {
    this.state = {
      context: context ?? this.state.context,
      facts: [],
      violations: [],
    };
  }
}

/**
 * Factory functions for creating typed facts and events
 */

type FactFactory<Tag extends string, Payload> = {
  create: (payload: Payload) => Fact<Tag, Payload>;
  is: (fact: Fact) => fact is Fact<Tag, Payload>;
};

export function defineFact<Tag extends string, Payload>(
  tag: Tag
): FactFactory<Tag, Payload> {
  return {
    create: (payload: Payload) => ({
      tag,
      payload,
      timestamp: Date.now(),
    }),
    is: (fact: Fact): fact is Fact<Tag, Payload> => fact.tag === tag,
  };
}

type EventFactory<Type extends string, Payload> = {
  create: (payload: Payload) => Event<Type, Payload>;
  is: (event: Event) => event is Event<Type, Payload>;
};

export function defineEvent<Type extends string, Payload>(
  type: Type
): EventFactory<Type, Payload> {
  return {
    create: (payload: Payload) => ({
      type,
      payload,
      timestamp: Date.now(),
    }),
    is: (event: Event): event is Event<Type, Payload> => event.type === type,
  };
}

export function defineRule<Context>(
  rule: Rule<Context>
): Rule<Context> {
  return rule;
}

export function defineConstraint<Context>(
  constraint: Constraint<Context>
): Constraint<Context> {
  return constraint;
}

/**
 * Helper to create a praxis engine instance
 */
export function createPraxisEngine<Context>(
  config: EngineConfig<Context>
): PraxisEngine<Context> {
  return new PraxisEngine(config);
}
