// Temporary stub for 'chevrotain' to allow compilation without installed dependency.
// Replace with real package installation when network / registry access is available.

declare module 'chevrotain' {
  export interface IToken {
    image: string;
    tokenType: any;
    startLine?: number;
    startColumn?: number;
    endLine?: number;
    endColumn?: number;
  }
  export interface ILexingError {
    message: string;
    line?: number;
    column?: number;
    length?: number;
    [key: string]: any;
  }
  export interface IRecognitionException {
    message: string;
    token?: IToken;
    context?: { ruleStack?: string[] };
    [key: string]: any;
  }
  export interface CstNode {
    name?: string;
    children?: Record<string, CstNode[]>;
    [key: string]: any;
  }
  export function createToken(def: any): any;
  export class Lexer {
    static SKIPPED: any;
    constructor(tokens: any[], config?: any);
    tokenize(input: string): { tokens: IToken[]; errors: ILexingError[] };
  }
  export class CstParser {
    constructor(tokens: any[], config?: any);
    input: any[];
    errors: IRecognitionException[];
    protected performSelfAnalysis(): void;
    RULE(name: string, impl: (...args: any[]) => any): any;
    SUBRULE(rule: any, options?: any): any;
    OPTION(impl: (...args: any[]) => any): any;
    OPTION2(impl: (...args: any[]) => any): any;
    OPTION3(impl: (...args: any[]) => any): any;
    MANY(impl: (...args: any[]) => any): any;
    OR(alts: any[]): any;
    CONSUME(token: any): any;
    getBaseCstVisitorConstructorWithDefaults(): any;
    reset(): void;
    [key: string]: any;
  }
}
