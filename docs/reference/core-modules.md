# Core module reference

The Rust workspace is the current native implementation. Each crate has a
single responsibility so that domain authority, storage, and host effects stay
separate.

| Module | Responsibility |
| --- | --- |
| `pedantic-core` | DSC v3 parsing, model, validation, deterministic planning, and JUnit/SARIF export |
| `pedantic-cli` | User-facing offline commands and authenticated service client commands |
| `pedantic-service` | Profile-local API, PX admission, PluresDB ownership, serialized state, and Chronos evidence |
| `pedantic-operation` | Typed plans, settings resolution, effect authorization, durable coordination, and event projections |
| `pedantic-capability` | Capability manifests, schema validation, readiness, and bounded adapter interfaces |
| `pedantic-provider-pack` | Production adapters, including host preparation and verified Hyper-V transfer effects |
| `pedantic-agent` | Durable target-side journal, enrollment/grant validation, recovery, and observed facts |
| `pedantic-windows-agent` | Windows-specific target-agent adapters |
| `pedantic-transport` | Transport-neutral authenticated envelopes for service/agent exchange |
| `pedantic-executor` | DSC process and transport integration behind the execution boundary |
| `pedantic-mcp` | MCP server exposing supported Pedantic DSC tools |
| `pedantic-node` | Node binding for the native core |

## Dependency direction

Domain models and procedures establish accepted decisions. The service persists
them, operations project them, agents validate authorized work, and capability
or provider modules perform effects. Transport carries authenticated opaque
messages without deciding policy.

See [Architecture](../architecture.md) and
[Contracts](contracts.md) for the shared boundary rules.
