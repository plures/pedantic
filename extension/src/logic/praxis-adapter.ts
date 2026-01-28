import * as local from './praxis-core';

type PraxisModule = typeof local;

function tryRequire(moduleName: string): PraxisModule | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require(moduleName) as PraxisModule;
  } catch {
    return null;
  }
}

const external = tryRequire('@plures/praxis');
const source = external ?? local;

export const PraxisRegistry = (source.PraxisRegistry ?? local.PraxisRegistry) as typeof local.PraxisRegistry;
export const createPraxisEngine = (source.createPraxisEngine ?? local.createPraxisEngine) as typeof local.createPraxisEngine;
export const defineFact = (source.defineFact ?? local.defineFact) as typeof local.defineFact;
export const defineEvent = (source.defineEvent ?? local.defineEvent) as typeof local.defineEvent;
export const defineRule = (source.defineRule ?? local.defineRule) as typeof local.defineRule;
export const defineConstraint = (source.defineConstraint ?? local.defineConstraint) as typeof local.defineConstraint;

export type Fact<Tag extends string = string, Payload = any> = local.Fact<Tag, Payload>;
export type Event<Type extends string = string, Payload = any> = local.Event<Type, Payload>;
export type Rule<Context = any> = local.Rule<Context>;
export type Constraint<Context = any> = local.Constraint<Context>;
export type ConstraintViolation = local.ConstraintViolation;
export type EngineState<Context = any> = local.EngineState<Context>;
export type EngineConfig<Context = any> = local.EngineConfig<Context>;
export type StepResult<Context = any> = local.StepResult<Context>;
export type StepDiagnostics = local.StepDiagnostics;
