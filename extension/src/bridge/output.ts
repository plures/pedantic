const truncationMarker = '\n[output truncated]\n';

export class BoundedOutput {
  private value = '';
  private truncated = false;

  constructor(private readonly limit: number) {}

  append(chunk: Buffer | string): void {
    if (this.truncated) {
      return;
    }

    const text = chunk.toString();
    const remaining = this.limit - Buffer.byteLength(this.value);
    if (remaining <= 0 || Buffer.byteLength(text) > remaining) {
      this.value += truncationMarker.slice(0, remaining);
      this.truncated = true;
      return;
    }
    this.value += text;
  }

  get text(): string {
    return this.value;
  }

  get wasTruncated(): boolean {
    return this.truncated;
  }
}

export function redactDiagnostic(value: string): string {
  return value.replace(
    /((?:"(?:password|token|secret|apikey|api_key)"|(?:password|token|secret|apikey|api_key))\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\S+)/gi,
    (match, prefix: string) => {
      const secret = match.slice(prefix.length);
      const quote = secret[0] === '"' || secret[0] === "'" ? secret[0] : '';
      return `${prefix}${quote}[REDACTED]${quote}`;
    },
  );
}
