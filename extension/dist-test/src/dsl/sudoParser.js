"use strict";
// SudoLang parser implementation using Chevrotain - v0.1 subset
// Converts SudoLang statements into canonical AST `InstallBlock` objects with diagnostics.
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseSudo = parseSudo;
const chevrotain_1 = require("chevrotain");
const ast_1 = require("./ast");
// -----------------------------------------------------------------------------
// Lexical tokens (order matters: keywords before identifiers)
// -----------------------------------------------------------------------------
const WhiteSpace = (0, chevrotain_1.createToken)({ name: 'WhiteSpace', pattern: /[ \t\f\v]+/, group: chevrotain_1.Lexer.SKIPPED });
const NewLine = (0, chevrotain_1.createToken)({ name: 'NewLine', pattern: /(?:\r?\n)+/, group: chevrotain_1.Lexer.SKIPPED });
const Comment = (0, chevrotain_1.createToken)({ name: 'Comment', pattern: /#.*/, group: chevrotain_1.Lexer.SKIPPED });
const Install = (0, chevrotain_1.createToken)({ name: 'Install', pattern: /install/i });
const Ensure = (0, chevrotain_1.createToken)({ name: 'Ensure', pattern: /ensure/i });
const Package = (0, chevrotain_1.createToken)({ name: 'Package', pattern: /package/i });
const Via = (0, chevrotain_1.createToken)({ name: 'Via', pattern: /via/i });
const Version = (0, chevrotain_1.createToken)({ name: 'Version', pattern: /version/i });
const Using = (0, chevrotain_1.createToken)({ name: 'Using', pattern: /using/i });
const Args = (0, chevrotain_1.createToken)({ name: 'Args', pattern: /args/i });
const QuotedString = (0, chevrotain_1.createToken)({ name: 'QuotedString', pattern: /"([^"\\]|\\.)*"/ });
const Ident = (0, chevrotain_1.createToken)({ name: 'Ident', pattern: /[A-Za-z0-9_.-]+/ });
const AllTokens = [WhiteSpace, NewLine, Comment, Install, Ensure, Package, Via, Version, Using, Args, QuotedString, Ident];
const lexer = new chevrotain_1.Lexer(AllTokens, { ensureOptimizations: true });
// -----------------------------------------------------------------------------
// Grammar definition
// -----------------------------------------------------------------------------
class SudoCstParser extends chevrotain_1.CstParser {
    constructor() {
        super(AllTokens, { recoveryEnabled: true });
        this.performSelfAnalysis();
    }
    document = this.RULE('document', () => {
        this.MANY(() => this.SUBRULE(this.statement));
    });
    statement = this.RULE('statement', () => {
        this.OR([
            { ALT: () => this.SUBRULE(this.installStmt) },
            { ALT: () => this.SUBRULE(this.ensureStmt) }
        ]);
    });
    installStmt = this.RULE('installStmt', () => {
        this.CONSUME(Install);
        this.OPTION(() => this.CONSUME(Package));
        this.SUBRULE(this.packageRef);
        this.OPTION2(() => this.SUBRULE(this.viaClause));
        this.OPTION3(() => this.SUBRULE(this.versionClause));
        this.OPTION4(() => this.SUBRULE(this.execClause));
    });
    ensureStmt = this.RULE('ensureStmt', () => {
        this.CONSUME(Ensure);
        this.CONSUME(Package);
        this.SUBRULE(this.packageRef);
        this.OPTION(() => this.SUBRULE(this.viaClause));
        this.OPTION2(() => this.SUBRULE(this.versionClause));
        this.OPTION3(() => this.SUBRULE(this.execClause));
    });
    packageRef = this.RULE('packageRef', () => {
        this.OR([
            { ALT: () => this.CONSUME(QuotedString) },
            { ALT: () => this.CONSUME(Ident) }
        ]);
    });
    viaClause = this.RULE('viaClause', () => {
        this.CONSUME(Via);
        this.CONSUME(Ident);
    });
    versionClause = this.RULE('versionClause', () => {
        this.CONSUME(Version);
        this.OR([
            { ALT: () => this.CONSUME(Ident) },
            { ALT: () => this.CONSUME(QuotedString) }
        ]);
    });
    execClause = this.RULE('execClause', () => {
        this.CONSUME(Using);
        this.SUBRULE(this.execPath);
        this.OPTION(() => this.SUBRULE(this.execArgs));
    });
    execPath = this.RULE('execPath', () => {
        this.OR([
            { ALT: () => this.CONSUME(QuotedString) },
            { ALT: () => this.CONSUME(Ident) }
        ]);
    });
    execArgs = this.RULE('execArgs', () => {
        this.CONSUME(Args);
        this.OR([
            { ALT: () => this.CONSUME(QuotedString) },
            { ALT: () => this.CONSUME(Ident) }
        ]);
    });
}
const parser = new SudoCstParser();
const BaseVisitor = parser.getBaseCstVisitorConstructorWithDefaults();
class SudoAstBuilder extends BaseVisitor {
    doc;
    constructor(doc) {
        super();
        this.doc = doc;
        this.validateVisitor();
    }
    document(ctx) {
        const packages = [];
        for (const stmt of ctx.statement ?? []) {
            const result = this.visit(stmt);
            if (result?.package) {
                packages.push(result.package);
            }
        }
        return packages;
    }
    statement(ctx) {
        if (ctx.installStmt?.length)
            return this.visit(ctx.installStmt[0]);
        if (ctx.ensureStmt?.length)
            return this.visit(ctx.ensureStmt[0]);
        return undefined;
    }
    installStmt(ctx) {
        const pkg = this.buildPackage(ctx);
        return pkg ? { package: pkg } : undefined;
    }
    ensureStmt(ctx) {
        const pkg = this.buildPackage(ctx);
        return pkg ? { package: pkg } : undefined;
    }
    buildPackage(ctx) {
        const refNode = ctx.packageRef?.[0];
        const refToken = refNode ? this.visit(refNode) : undefined;
        if (!refToken) {
            return undefined;
        }
        const display = stripQuotes(refToken.image);
        const pkg = {
            kind: 'PackageSpec',
            id: canonicalize(display),
            display,
            sourceLocation: tokenRange(refToken)
        };
        if (ctx.viaClause?.length) {
            const via = this.visit(ctx.viaClause[0]);
            if (via) {
                const normalized = normalizeProvider(via.image);
                if (!isKnownProvider(normalized)) {
                    (0, ast_1.pushDiagnostic)(this.doc, diag('DSL005', `Unknown provider '${via.image}'`, via, 'warning'));
                    pkg.providerOverride = 'unknown';
                }
                else {
                    pkg.providerOverride = normalized;
                }
            }
        }
        if (ctx.versionClause?.length) {
            const versionToken = this.visit(ctx.versionClause[0]);
            if (versionToken) {
                pkg.version = stripQuotes(versionToken.image);
            }
        }
        if (ctx.execClause?.length) {
            const exec = this.visit(ctx.execClause[0]);
            const path = exec.pathToken ? stripQuotes(exec.pathToken.image) : undefined;
            if (!path) {
                (0, ast_1.pushDiagnostic)(this.doc, diag('DSL007', 'Executable override missing path', exec.usingToken ?? exec.pathToken));
            }
            else {
                const args = tokenizeArgs(exec.argsToken?.image);
                pkg.executableOverride = { path, args };
                if (pkg.providerOverride) {
                    (0, ast_1.pushDiagnostic)(this.doc, diag('DSL006', 'Both method and executable/path specified', exec.pathToken ?? exec.usingToken));
                }
            }
        }
        return pkg;
    }
    packageRef(ctx) {
        return ctx.QuotedString?.[0] ?? ctx.Ident?.[0];
    }
    viaClause(ctx) {
        return ctx.Ident?.[0];
    }
    versionClause(ctx) {
        return ctx.Ident?.[0] ?? ctx.QuotedString?.[0];
    }
    execClause(ctx) {
        const usingToken = ctx.Using?.[0];
        const pathToken = ctx.execPath?.length ? this.visit(ctx.execPath[0]) : undefined;
        const argsToken = ctx.execArgs?.length ? this.visit(ctx.execArgs[0]) : undefined;
        return { usingToken, pathToken, argsToken };
    }
    execPath(ctx) {
        return ctx.QuotedString?.[0] ?? ctx.Ident?.[0];
    }
    execArgs(ctx) {
        return ctx.QuotedString?.[0] ?? ctx.Ident?.[0];
    }
}
function parseSudo(source) {
    const doc = (0, ast_1.createEmptyDocument)('sudo');
    const lexResult = lexer.tokenize(source);
    if (lexResult.errors.length) {
        for (const err of lexResult.errors) {
            (0, ast_1.pushDiagnostic)(doc, {
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
            (0, ast_1.pushDiagnostic)(doc, diag('DSL010', err.message, err.token ?? lexResult.tokens[err.context?.ruleStack?.length ?? 0]));
        }
    }
    const visitor = new SudoAstBuilder(doc);
    const packages = visitor.visit(cst);
    if (packages.length) {
        const block = { kind: 'InstallBlock', packages };
        doc.blocks.push(block);
    }
    parser.reset();
    return { doc, tokens: lexResult.tokens };
}
// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------
function stripQuotes(image) {
    if (!image)
        return image;
    if (image.startsWith('"') && image.endsWith('"')) {
        const inner = image.slice(1, -1);
        return inner.replace(/\\"/g, '"');
    }
    return image;
}
function canonicalize(value) {
    return value.trim().toLowerCase().replace(/\s+/g, '-');
}
function normalizeProvider(raw) {
    return raw ? raw.trim().toLowerCase() : '';
}
function isKnownProvider(provider) {
    return ['winget', 'chocolatey', 'msi', 'apt', 'yum', 'brew'].includes(provider);
}
function diag(code, message, token, severity = 'error') {
    return {
        code,
        severity,
        message,
        range: token ? tokenRange(token) : positionRange(1, 1, 1)
    };
}
function tokenRange(token) {
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
function positionRange(line, column, length) {
    const l = Math.max(line - 1, 0);
    const c = Math.max(column - 1, 0);
    return {
        start: { line: l, character: c },
        end: { line: l, character: c + Math.max(length - 1, 0) }
    };
}
function tokenizeArgs(raw) {
    if (!raw)
        return undefined;
    const stripped = stripQuotes(raw);
    if (!stripped.trim())
        return undefined;
    const normalized = stripped.replace(/\\"/g, '"');
    const segments = normalized.match(/"([^"\\]|\\.)*"|[^"\s]+/g);
    if (!segments)
        return undefined;
    const values = segments.map(seg => stripQuotes(seg));
    return values.length ? values : undefined;
}
