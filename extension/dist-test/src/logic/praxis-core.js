"use strict";
// Praxis-inspired logic engine for Pedantic DSL processing
// Based on plures/praxis: typed facts, events, rules, and constraints
Object.defineProperty(exports, "__esModule", { value: true });
exports.PraxisEngine = exports.PraxisRegistry = void 0;
exports.defineFact = defineFact;
exports.defineEvent = defineEvent;
exports.defineRule = defineRule;
exports.defineConstraint = defineConstraint;
exports.createPraxisEngine = createPraxisEngine;
// Rule registry
class PraxisRegistry {
    rules = new Map();
    constraints = new Map();
    registerRule(rule) {
        this.rules.set(rule.id, rule);
    }
    registerConstraint(constraint) {
        this.constraints.set(constraint.id, constraint);
    }
    getRules() {
        return Array.from(this.rules.values());
    }
    getConstraints() {
        return Array.from(this.constraints.values());
    }
    getRule(id) {
        return this.rules.get(id);
    }
    getConstraint(id) {
        return this.constraints.get(id);
    }
}
exports.PraxisRegistry = PraxisRegistry;
/**
 * Praxis-inspired logic engine
 */
class PraxisEngine {
    state;
    registry;
    enableDiagnostics;
    constructor(config) {
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
    step(events) {
        const startTime = this.enableDiagnostics ? Date.now() : 0;
        const diagnostics = {
            rulesExecuted: [],
            constraintsChecked: [],
            executionTimeMs: 0,
        };
        const newFacts = [];
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
        const violations = [];
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
    getState() {
        return this.state;
    }
    /**
     * Get current context
     */
    getContext() {
        return this.state.context;
    }
    /**
     * Get all facts
     */
    getFacts() {
        return this.state.facts;
    }
    /**
     * Get current violations
     */
    getViolations() {
        return this.state.violations;
    }
    /**
     * Reset engine to initial state
     */
    reset(context) {
        this.state = {
            context: context ?? this.state.context,
            facts: [],
            violations: [],
        };
    }
}
exports.PraxisEngine = PraxisEngine;
function defineFact(tag) {
    return {
        create: (payload) => ({
            tag,
            payload,
            timestamp: Date.now(),
        }),
        is: (fact) => fact.tag === tag,
    };
}
function defineEvent(type) {
    return {
        create: (payload) => ({
            type,
            payload,
            timestamp: Date.now(),
        }),
        is: (event) => event.type === type,
    };
}
function defineRule(rule) {
    return rule;
}
function defineConstraint(constraint) {
    return constraint;
}
/**
 * Helper to create a praxis engine instance
 */
function createPraxisEngine(config) {
    return new PraxisEngine(config);
}
