// SudoLang parser implementation using Chevrotain - v0.1 subset
// Converts SudoLang statements into canonical AST `InstallBlock` objects with diagnostics.

import { createToken, Lexer, CstParser, IToken, CstNode } from 'chevrotain';
import { createEmptyDocument, Document, InstallBlock, PackageSpec, pushDiagnostic, ProviderId } from './ast';

// -----------------------------------------------------------------------------
// Lexical tokens (order matters: keywords before identifiers)
// -----------------------------------------------------------------------------
const WhiteSpace = createToken({ name: 'WhiteSpace', pattern: /[ \t\f\v]+/, group: Lexer.SKIPPED });
const NewLine = createToken({ name: 'NewLine', pattern: /(?:\r?\n)+/, group: Lexer.SKIPPED });
const Comment = createToken({ name: 'Comment', pattern: /#.*/, group: Lexer.SKIPPED });
const Install = createToken({ name: 'Install', pattern: /install/i });
const Ensure = createToken({ name: 'Ensure', pattern: /ensure/i });
const Package = createToken({ name: 'Package', pattern: /package/i });
const Via = createToken({ name: 'Via', pattern: /via/i });
const Version = createToken({ name: 'Version', pattern: /version/i });
const Using = createToken({ name: 'Using', pattern: /using/i });
const Args = createToken({ name: 'Args', pattern: /args/i });
const QuotedString = createToken({ name: 'QuotedString', pattern: /"([^"\\]|\\.)*"/ });
const Ident = createToken({ name: 'Ident', pattern: /[A-Za-z0-9_.-]+/ });

const AllTokens = [WhiteSpace, NewLine, Comment, Install, Ensure, Package, Via, Version, Using, Args, QuotedString, Ident];
const lexer = new Lexer(AllTokens, { ensureOptimizations: true });

// -----------------------------------------------------------------------------
// Grammar definition
// -----------------------------------------------------------------------------
class SudoCstParser extends CstParser {
  constructor() {
    super(AllTokens, { recoveryEnabled: true });
    this.performSelfAnalysis();
  }

  public document = this.RULE('document', () => {
    this.MANY(() => this.SUBRULE(this.statement));
  });

  private statement = this.RULE('statement', () => {
    this.OR([
      { ALT: () => this.SUBRULE(this.installStmt) },
      { ALT: () => this.SUBRULE(this.ensureStmt) }
    ]);
  });

  private installStmt = this.RULE('installStmt', () => {
    this.CONSUME(Install);
    this.OPTION(() => this.CONSUME(Package));
    this.SUBRULE(this.packageRef);
    this.OPTION2(() => this.SUBRULE(this.viaClause));
    this.OPTION3(() => this.SUBRULE(this.versionClause));
    this.OPTION4(() => this.SUBRULE(this.execClause));
  });

  private ensureStmt = this.RULE('ensureStmt', () => {
    this.CONSUME(Ensure);
    this.CONSUME(Package);
    this.SUBRULE(this.packageRef);
    this.OPTION(() => this.SUBRULE(this.viaClause));
    this.OPTION2(() => this.SUBRULE(this.versionClause));
    this.OPTION3(() => this.SUBRULE(this.execClause));
  });

  private packageRef = this.RULE('packageRef', () => {
    this.OR([
      { ALT: () => this.CONSUME(QuotedString) },
      { ALT: () => this.CONSUME(Ident) }
    ]);
  });

  private viaClause = this.RULE('viaClause', () => {
    this.CONSUME(Via);
    this.CONSUME(Ident);
  });

  private versionClause = this.RULE('versionClause', () => {
    this.CONSUME(Version);
    this.OR([
      { ALT: () => this.CONSUME(Ident) },
      { ALT: () => this.CONSUME(QuotedString) }
    ]);
  });

  private execClause = this.RULE('execClause', () => {
    this.CONSUME(Using);
    this.SUBRULE(this.execPath);
    this.OPTION(() => this.SUBRULE(this.execArgs));
  });

  private execPath = this.RULE('execPath', () => {
    this.OR([
      { ALT: () => this.CONSUME(QuotedString) },
      { ALT: () => this.CONSUME(Ident) }
    ]);
  });

  private execArgs = this.RULE('execArgs', () => {
    this.CONSUME(Args);
    this.OR([
      { ALT: () => this.CONSUME(QuotedString) },
      { ALT: () => this.CONSUME(Ident) }
    ]);
  });
}

const parser = new SudoCstParser();
const BaseVisitor = parser.getBaseCstVisitorConstructorWithDefaults();

interface StatementResult {
  package: PackageSpec;
}

interface ExecClauseResult {
  usingToken?: IToken;
  pathToken?: IToken;
  argsToken?: IToken;
}

class SudoAstBuilder extends BaseVisitor {
  constructor(private readonly doc: Document) {
    super();
    this.validateVisitor();
  }

  document(ctx: Record<string, CstNode[]>): PackageSpec[] {
    const packages: PackageSpec[] = [];
    for (const stmt of ctx.statement ?? []) {
      const result = this.visit(stmt) as StatementResult | undefined;
      if (result?.package) {
        packages.push(result.package);
      }
    }
    return packages;
  }

  statement(ctx: any): StatementResult | undefined {
    if (ctx.installStmt?.length) return this.visit(ctx.installStmt[0]);
    if (ctx.ensureStmt?.length) return this.visit(ctx.ensureStmt[0]);
    return undefined;
  }

  installStmt(ctx: any): StatementResult | undefined {
    const pkg = this.buildPackage(ctx);
    return pkg ? { package: pkg } : undefined;
  }

  ensureStmt(ctx: any): StatementResult | undefined {
    const pkg = this.buildPackage(ctx);
    return pkg ? { package: pkg } : undefined;
  }

  private buildPackage(ctx: any): PackageSpec | undefined {
    const refNode: CstNode | undefined = ctx.packageRef?.[0];
    const refToken = refNode ? this.visit(refNode) as IToken : undefined;
    if (!refToken) {
      return undefined;
    }
    const display = stripQuotes(refToken.image);
    const pkg: PackageSpec = {
      kind: 'PackageSpec',
      id: canonicalize(display),
      display,
      sourceLocation: tokenRange(refToken)
    };

    if (ctx.viaClause?.length) {
      const via = this.visit(ctx.viaClause[0]) as IToken | undefined;
      if (via) {
        const normalized = normalizeProvider(via.image);
        if (!isKnownProvider(normalized)) {
          pushDiagnostic(this.doc, diag('DSL005', `Unknown provider '${via.image}'`, via, 'warning'));
          pkg.providerOverride = 'unknown';
        } else {
          pkg.providerOverride = normalized as ProviderId;
        }
      }
    }

    if (ctx.versionClause?.length) {
      const versionToken = this.visit(ctx.versionClause[0]) as IToken | undefined;
      if (versionToken) {
        pkg.version = stripQuotes(versionToken.image);
      }
    }

    if (ctx.execClause?.length) {
      const exec = this.visit(ctx.execClause[0]) as ExecClauseResult;
      const path = exec.pathToken ? stripQuotes(exec.pathToken.image) : undefined;
      if (!path) {
        pushDiagnostic(this.doc, diag('DSL007', 'Executable override missing path', exec.usingToken ?? exec.pathToken));
      } else {
        const args = tokenizeArgs(exec.argsToken?.image);
        pkg.executableOverride = { path, args };
        if (pkg.providerOverride) {
          pushDiagnostic(this.doc, diag('DSL006', 'Both method and executable/path specified', exec.pathToken ?? exec.usingToken));
        }
      }
    }
    return pkg;
  }

  packageRef(ctx: any): IToken | undefined {
    return ctx.QuotedString?.[0] ?? ctx.Ident?.[0];
  }

  viaClause(ctx: any): IToken | undefined {
    return ctx.Ident?.[0];
  }

  versionClause(ctx: any): IToken | undefined {
    return ctx.Ident?.[0] ?? ctx.QuotedString?.[0];
  }

  execClause(ctx: any): ExecClauseResult {
    const usingToken: IToken | undefined = ctx.Using?.[0];
    const pathToken = ctx.execPath?.length ? (this.visit(ctx.execPath[0]) as IToken | undefined) : undefined;
    const argsToken = ctx.execArgs?.length ? (this.visit(ctx.execArgs[0]) as IToken | undefined) : undefined;
    return { usingToken, pathToken, argsToken };
  }

  execPath(ctx: any): IToken | undefined {
    return ctx.QuotedString?.[0] ?? ctx.Ident?.[0];
  }

  execArgs(ctx: any): IToken | undefined {
    return ctx.QuotedString?.[0] ?? ctx.Ident?.[0];
  }
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------
export interface SudoParseResult {
  doc: Document;
  tokens: IToken[];
}

export function parseSudo(source: string): SudoParseResult {
  const doc = createEmptyDocument('sudo');
  const lexResult = lexer.tokenize(source);

  if (lexResult.errors.length) {
    for (const err of lexResult.errors) {
      pushDiagnostic(doc, {
        code: 'DSL010',
        severity: 'error',
        message: err.message,
        range: positionRange(err.line ?? 1, err.column ?? 1, err.length ?? 1)
      });
    }
  }

  parser.input = lexResult.tokens;
  const cst = parser.document();

  if (parser.errors.length) {
    for (const err of parser.errors) {
      pushDiagnostic(doc, diag('DSL010', err.message, err.token ?? lexResult.tokens[err.context?.ruleStack?.length ?? 0]));
    }
  }

  const visitor = new SudoAstBuilder(doc);
  const packages = visitor.visit(cst) as PackageSpec[];
  if (packages.length) {
    const block: InstallBlock = { kind: 'InstallBlock', packages };
    doc.blocks.push(block);
  }

  parser.reset();
  return { doc, tokens: lexResult.tokens };
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------
function stripQuotes(image: string): string {
  if (!image) return image;
  if (image.startsWith('"') && image.endsWith('"')) {
    const inner = image.slice(1, -1);
    return inner.replace(/\\"/g, '"');
  }
  return image;
}

function canonicalize(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, '-');
}

function normalizeProvider(raw: string | undefined): string {
  return raw ? raw.trim().toLowerCase() : '';
}

function isKnownProvider(provider: string): provider is ProviderId {
  return ['winget', 'chocolatey', 'msi', 'apt', 'yum', 'brew'].includes(provider as ProviderId);
}

function diag(code: string, message: string, token?: IToken, severity: 'error' | 'warning' | 'info' = 'error') {
  return {
    code,
    severity,
    message,
    range: token ? tokenRange(token) : positionRange(1, 1, 1)
  };
}

function tokenRange(token: IToken) {
  const startLine = (token.startLine ?? 1) - 1;
  const startCol = (token.startColumn ?? 1) - 1;
  const endLine = (token.endLine ?? token.startLine ?? 1) - 1;
  const endColRaw = token.endColumn ?? (startCol + (token.image?.length ?? 1));
  const endCol = endColRaw - 1 >= startCol ? endColRaw - 1 : startCol;
  return {
    start: { line: startLine, character: startCol },
    end: { line: endLine, character: endCol }
  };
}

function positionRange(line: number, column: number, length: number) {
  const l = Math.max(line - 1, 0);
  const c = Math.max(column - 1, 0);
  return {
    start: { line: l, character: c },
    end: { line: l, character: c + Math.max(length - 1, 0) }
  };
}

function tokenizeArgs(raw: string | undefined): string[] | undefined {
  if (!raw) return undefined;
  const stripped = stripQuotes(raw);
  if (!stripped.trim()) return undefined;
  const normalized = stripped.replace(/\\"/g, '"');
  const segments = normalized.match(/"([^"\\]|\\.)*"|[^"\s]+/g);
  if (!segments) return undefined;
  const values = segments.map(seg => stripQuotes(seg));
  return values.length ? values : undefined;
}
