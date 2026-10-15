# Pedantic open-core model

Pedantic uses a genuine open-core model. The operational substrate required to
author, inspect, execute, recover, and extend native Pedantic plans is public
under Apache-2.0. Commercial products add organizational governance,
collaboration, distribution, assurance, and support without replacing the
public execution engine.

## Open core

The public Pedantic repository owns:

- Versioned target, fact, plan, capability, operation, and evidence contracts.
- PX procedures and constraints for the native single-profile lifecycle.
- The Rust service, coordinator, and local PluresDB and Chronos integration.
- Agentless execution transports and plan-scoped ephemeral agents.
- Durable journals, reboot continuation, cleanup, and removal verification.
- The capability manifest, provider SDK, conformance suite, and core providers.
- Local policy authoring, approvals, evidence, and operation history.
- CLI, MCP, VS Code, and agent-harness service clients.
- Documentation, examples, migration tools, and task-suite fixtures.

These features must remain sufficient for useful production operation by an
individual or small team. The hybrid agent lifecycle is part of the open core;
it is not an enterprise-only execution path.

## Commercial products

Commercial Pedantic products may provide:

- Shared multi-user organizations, projects, and delegated administration.
- Enterprise SSO, federation, fine-grained RBAC, and separation of duties.
- Multi-party approval workflows and centralized policy administration.
- High availability, disaster recovery, data residency, and managed upgrades.
- Private capability and policy registries with signing and promotion channels.
- Commercial compliance and assurance content.
- Fleet-scale analytics, reporting, retention, and SIEM integrations.
- Air-gapped distribution channels and enterprise update management.
- Premium providers whose maintenance requires vendor certification or
  specialized interoperability testing.
- Support subscriptions, service-level agreements, training, and professional
  services.

Commercial features consume the same public contracts and capability
interfaces. They must not require a private replacement for the coordinator,
agent, or provider SDK.

## Deployment products

Pedantic is local-first and supports customer-managed distributed operation.
A hosted control or evidence plane remains a separate product decision. No
cloud service is required to author plans, execute native effects, retain local
evidence, or develop providers.

Any future cloud-specific distribution is an optional commercial product over
the vendor-neutral core. It must not introduce cloud dependencies into public
contracts or local execution.

## Contribution and compatibility policy

- Public contracts follow documented versioning and compatibility rules.
- Commercial products may depend on public interfaces but do not receive
  undocumented privileged hooks.
- Provider authors can build and distribute production capabilities without a
  commercial license.
- Security fixes affecting the execution substrate are made in the public core.
- Customer configuration, facts, evidence, and secrets remain customer data.

## Product review test

A feature belongs in the open core when it is necessary to:

1. Safely execute or recover a native Pedantic plan.
2. Develop or validate a capability provider.
3. Inspect the decisions and evidence for a local operation.
4. Keep public clients behaviorally consistent.

A feature may be commercial when its primary value is coordinating multiple
people or organizations, operating the platform at enterprise scale,
delivering maintained proprietary content, or providing contractual assurance.
