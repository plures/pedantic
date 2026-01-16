// DSL processing logic using praxis-inspired patterns
// Separates business logic from parsing concerns

import type { Document, PackageSpec } from '../dsl/ast';
import {
  createPraxisEngine,
  defineFact,
  defineEvent,
  defineRule,
  defineConstraint,
  PraxisRegistry,
  type ConstraintViolation,
  type Fact,
  type StepDiagnostics,
} from './praxis-core';

/**
 * Context for DSL processing
 */
export interface DslContext {
  document: Document | null;
  packageCount: number;
  providerStats: Record<string, number>;
  validationErrors: number;
  validationWarnings: number;
}

/**
 * Facts emitted during DSL processing
 */
export const DocumentParsed = defineFact<
  'DocumentParsed',
  { dialect: 'simple' | 'sudo'; blockCount: number }
>('DocumentParsed');

export const PackageDiscovered = defineFact<
  'PackageDiscovered',
  { id: string; provider?: string; version?: string }
>('PackageDiscovered');

export const ValidationIssue = defineFact<
  'ValidationIssue',
  { severity: 'error' | 'warning'; code: string; message: string }
>('ValidationIssue');

/**
 * Events that trigger processing
 */
export const ParseDocument = defineEvent<
  'PARSE_DOCUMENT',
  { document: Document }
>('PARSE_DOCUMENT');

export const ValidatePackage = defineEvent<
  'VALIDATE_PACKAGE',
  { package: PackageSpec }
>('VALIDATE_PACKAGE');

/**
 * Rules for DSL processing (business logic)
 */

// Rule: Process parsed document
const documentProcessingRule = defineRule<DslContext>({
  id: 'dsl.process-document',
  description: 'Extract metadata from parsed document',
  impl: (state, events) => {
    const parseEvent = events.find(ParseDocument.is);
    if (!parseEvent) return [];

    const doc = parseEvent.payload.document;
    state.context.document = doc;
    state.context.packageCount = 0;
    state.context.providerStats = {};
    state.context.validationErrors = 0;
    state.context.validationWarnings = 0;

    return [
      DocumentParsed.create({
        dialect: doc.dialect,
        blockCount: doc.blocks.length,
      }),
    ];
  },
});

// Rule: Discover packages in document
const packageDiscoveryRule = defineRule<DslContext>({
  id: 'dsl.discover-packages',
  description: 'Extract and catalog packages from document',
  impl: (state, events) => {
    const parseEvent = events.find(ParseDocument.is);
    if (!parseEvent) return [];

    const doc = parseEvent.payload.document;
    const facts = [];

    for (const block of doc.blocks) {
      if (block.kind === 'InstallBlock') {
        for (const pkg of block.packages) {
          state.context.packageCount++;

          const provider = pkg.providerOverride || 'default';
          state.context.providerStats[provider] =
            (state.context.providerStats[provider] || 0) + 1;

          facts.push(
            PackageDiscovered.create({
              id: pkg.id,
              provider: pkg.providerOverride,
              version: pkg.version,
            })
          );
        }
      }
    }

    return facts;
  },
});

// Rule: Process validation issues from document diagnostics
const diagnosticsProcessingRule = defineRule<DslContext>({
  id: 'dsl.process-diagnostics',
  description: 'Convert document diagnostics to validation facts',
  impl: (state, events) => {
    const parseEvent = events.find(ParseDocument.is);
    if (!parseEvent) return [];

    const doc = parseEvent.payload.document;
    const facts = [];

    if (doc.diagnostics) {
      for (const diag of doc.diagnostics) {
        if (diag.severity === 'error') {
          state.context.validationErrors++;
        } else if (diag.severity === 'warning') {
          state.context.validationWarnings++;
        }

        facts.push(
          ValidationIssue.create({
            severity: diag.severity === 'info' ? 'warning' : diag.severity,
            code: diag.code,
            message: diag.message,
          })
        );
      }
    }

    return facts;
  },
});

// Rule: Package-level validation
const packageValidationRule = defineRule<DslContext>({
  id: 'dsl.validate-package',
  description: 'Validate individual package specifications',
  impl: (state, events) => {
    const validateEvent = events.find(ValidatePackage.is);
    if (!validateEvent) return [];

    const pkg = validateEvent.payload.package;
    const facts = [];

    // Check for both provider and executable (conflict)
    if (pkg.providerOverride && pkg.executableOverride) {
      facts.push(
        ValidationIssue.create({
          severity: 'error',
          code: 'DSL006',
          message: `Package '${pkg.id}' cannot specify both provider and executable`,
        })
      );
      state.context.validationErrors++;
    }

    // Check for executable without path
    if (pkg.executableOverride && !pkg.executableOverride.path) {
      facts.push(
        ValidationIssue.create({
          severity: 'error',
          code: 'DSL007',
          message: `Package '${pkg.id}' executable override missing path`,
        })
      );
      state.context.validationErrors++;
    }

    return facts;
  },
});

/**
 * Constraints for DSL validation
 */

// Constraint: Document must have at least one package
const minimumPackagesConstraint = defineConstraint<DslContext>({
  id: 'dsl.minimum-packages',
  description: 'Document must contain at least one package',
  check: (state) => {
    if (!state.context.document) return null;

    if (state.context.packageCount === 0) {
      return {
        constraintId: 'dsl.minimum-packages',
        message: 'Document must contain at least one package',
        severity: 'warning',
      };
    }

    return null;
  },
});

// Constraint: Limit maximum packages for performance
const maximumPackagesConstraint = defineConstraint<DslContext>({
  id: 'dsl.maximum-packages',
  description: 'Document should not exceed reasonable package count',
  check: (state) => {
    const MAX_PACKAGES = 1000;
    if (state.context.packageCount > MAX_PACKAGES) {
      return {
        constraintId: 'dsl.maximum-packages',
        message: `Document contains ${state.context.packageCount} packages (max ${MAX_PACKAGES}); performance may degrade`,
        severity: 'warning',
      };
    }

    return null;
  },
});

// Constraint: Validation errors block processing
const noValidationErrorsConstraint = defineConstraint<DslContext>({
  id: 'dsl.no-validation-errors',
  description: 'Document must not have validation errors',
  check: (state) => {
    if (state.context.validationErrors > 0) {
      return {
        constraintId: 'dsl.no-validation-errors',
        message: `Document has ${state.context.validationErrors} validation error(s)`,
        severity: 'error',
      };
    }

    return null;
  },
});

/**
 * Create a DSL processing engine with all rules and constraints
 */
export function createDslEngine(enableDiagnostics = false) {
  const registry = new PraxisRegistry<DslContext>();

  // Register rules
  registry.registerRule(documentProcessingRule);
  registry.registerRule(packageDiscoveryRule);
  registry.registerRule(diagnosticsProcessingRule);
  registry.registerRule(packageValidationRule);

  // Register constraints
  registry.registerConstraint(minimumPackagesConstraint);
  registry.registerConstraint(maximumPackagesConstraint);
  registry.registerConstraint(noValidationErrorsConstraint);

  return createPraxisEngine({
    initialContext: {
      document: null,
      packageCount: 0,
      providerStats: {},
      validationErrors: 0,
      validationWarnings: 0,
    },
    registry,
    enableDiagnostics,
  });
}

/**
 * Process a document through the logic engine
 */
export function processDocument(doc: Document, enableDiagnostics = false): {
  context: DslContext;
  facts: Fact[];
  violations: ConstraintViolation[];
  diagnostics?: StepDiagnostics;
} {
  const engine = createDslEngine(enableDiagnostics);

  // Process document
  const result = engine.step([ParseDocument.create({ document: doc })]);

  // Validate each package in a single engine step to avoid repeated recalculation
  const packageEvents = [];
  for (const block of doc.blocks) {
    if (block.kind === 'InstallBlock') {
      for (const pkg of block.packages) {
        packageEvents.push(ValidatePackage.create({ package: pkg }));
      }
    }
  }

  if (packageEvents.length > 0) {
    engine.step(packageEvents);
  }
  return {
    context: engine.getContext(),
    facts: engine.getFacts(),
    violations: engine.getViolations(),
    diagnostics: result.diagnostics,
  };
}
