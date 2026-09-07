use pedantic_core::model::{DscDocument, DscResource, Parameter};
use pedantic_core::praxis::{
    ConstraintViolation, Engine, Event, Fact, HostInventory, IdempotentRender, MaxDriftThreshold,
    NoDeployDraft, NoSetWithoutTest, PlanAction, PlanTask, ResourceDesired, ResourceState,
    ResourceStatus, Rule, RuleOutput,
};
use serde_json::json;
use std::sync::Mutex;

#[test]
fn fixed_point_evaluation_runs_multiple_rounds() {
    struct AddHost;
    struct AddDesired;

    impl Rule for AddHost {
        fn name(&self) -> &'static str {
            "add-host"
        }

        fn priority(&self) -> u32 {
            10
        }

        fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
            let mut output = RuleOutput::default();
            let has_host = facts
                .iter()
                .any(|fact| matches!(fact, Fact::HostInventory(_)));
            if !has_host {
                output.new_facts.push(Fact::HostInventory(HostInventory {
                    hostname: "alpha".to_string(),
                    os: "linux".to_string(),
                }));
            }
            output
        }
    }

    impl Rule for AddDesired {
        fn name(&self) -> &'static str {
            "add-desired"
        }

        fn priority(&self) -> u32 {
            5
        }

        fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
            let mut output = RuleOutput::default();
            let has_host = facts
                .iter()
                .any(|fact| matches!(fact, Fact::HostInventory(_)));
            let has_desired = facts
                .iter()
                .any(|fact| matches!(fact, Fact::ResourceDesired(_)));
            if has_host && !has_desired {
                output
                    .new_facts
                    .push(Fact::ResourceDesired(ResourceDesired {
                        resource: DscResource {
                            name: "res-a".to_string(),
                            resource_type: "Test/Resource".to_string(),
                            depends_on: vec![],
                            properties: json!({}),
                        },
                    }));
            }
            output
        }
    }

    let engine = Engine::builder()
        .add_rule(Box::new(AddHost))
        .add_rule(Box::new(AddDesired))
        .build();
    let outcome = engine.evaluate(vec![]);

    assert!(
        outcome
            .facts
            .iter()
            .any(|fact| matches!(fact, Fact::ResourceDesired(_)))
    );
    assert_eq!(outcome.iterations, 3);
}

#[test]
fn rules_execute_in_priority_order() {
    struct LowPriority;
    struct HighPriority;

    impl Rule for LowPriority {
        fn name(&self) -> &'static str {
            "low"
        }

        fn priority(&self) -> u32 {
            1
        }

        fn apply(&self, _facts: &[Fact], _events: &[Event]) -> RuleOutput {
            RuleOutput {
                new_facts: vec![],
                new_events: vec![Event::ConfigParsed {
                    name: "low".to_string(),
                }],
            }
        }
    }

    impl Rule for HighPriority {
        fn name(&self) -> &'static str {
            "high"
        }

        fn priority(&self) -> u32 {
            10
        }

        fn apply(&self, _facts: &[Fact], _events: &[Event]) -> RuleOutput {
            RuleOutput {
                new_facts: vec![],
                new_events: vec![Event::ConfigParsed {
                    name: "high".to_string(),
                }],
            }
        }
    }

    let engine = Engine::builder()
        .max_iterations(1)
        .add_rule(Box::new(HighPriority))
        .add_rule(Box::new(LowPriority))
        .build();

    let outcome = engine.evaluate(vec![]);
    assert_eq!(
        outcome.fired_rules,
        vec!["low".to_string(), "high".to_string()]
    );
}

#[test]
fn constraint_violations_are_collected() {
    let doc = DscDocument {
        schema: None,
        name: "draft".to_string(),
        version: "0.0.1-draft".to_string(),
        description: None,
        parameters: vec![],
        resources: vec![
            DscResource {
                name: "res-a".to_string(),
                resource_type: "Test/Resource".to_string(),
                depends_on: vec![],
                properties: json!({}),
            },
            DscResource {
                name: "res-b".to_string(),
                resource_type: "Test/Resource".to_string(),
                depends_on: vec![],
                properties: json!({}),
            },
        ],
    };

    let facts = vec![
        Fact::ConfigDocument(doc),
        Fact::PlanTasks(vec![PlanTask {
            resource_name: "res-a".to_string(),
            action: PlanAction::Set,
        }]),
        Fact::ExecutionResult(pedantic_core::praxis::ExecutionResult {
            resource_name: "res-a".to_string(),
            action: PlanAction::Set,
            success: true,
            message: None,
        }),
        Fact::ResourceState(ResourceState {
            name: "res-a".to_string(),
            status: ResourceStatus::Drifted,
        }),
        Fact::ResourceState(ResourceState {
            name: "res-b".to_string(),
            status: ResourceStatus::Drifted,
        }),
    ];

    let engine = Engine::builder()
        .add_constraint(Box::new(NoSetWithoutTest))
        .add_constraint(Box::new(NoDeployDraft))
        .add_constraint(Box::new(IdempotentRender))
        .add_constraint(Box::new(MaxDriftThreshold::default()))
        .build();

    let outcome = engine.evaluate(facts);
    assert!(
        outcome
            .constraint_violations
            .iter()
            .any(|violation| matches!(violation, ConstraintViolation::NoSetWithoutTest))
    );
    assert!(
        outcome
            .constraint_violations
            .iter()
            .any(|violation| matches!(violation, ConstraintViolation::NoDeployDraft))
    );
    assert!(
        outcome
            .constraint_violations
            .iter()
            .any(|violation| matches!(violation, ConstraintViolation::IdempotentRender))
    );
    assert!(outcome.constraint_violations.iter().any(|violation| {
        matches!(
            violation,
            ConstraintViolation::MaxDriftThresholdExceeded { .. }
        )
    }));
}

#[test]
fn full_pipeline_emits_events_and_plans() {
    let doc = DscDocument {
        schema: None,
        name: "demo".to_string(),
        version: "1.0.0".to_string(),
        description: None,
        parameters: vec![Parameter {
            name: "ParamA".to_string(),
            param_type: "string".to_string(),
            default: None,
        }],
        resources: vec![
            DscResource {
                name: "res-a".to_string(),
                resource_type: "Test/Resource".to_string(),
                depends_on: vec![],
                properties: json!({"Value": "[parameters('ParamA')]"}),
            },
            DscResource {
                name: "res-b".to_string(),
                resource_type: "Test/Resource".to_string(),
                depends_on: vec!["res-a".to_string()],
                properties: json!({}),
            },
        ],
    };

    let engine = Engine::builder()
        .add_rule(Box::new(pedantic_core::praxis::ParseAndValidate))
        .add_rule(Box::new(pedantic_core::praxis::ValidateParameters))
        .add_rule(Box::new(pedantic_core::praxis::ResolveExecutionOrder))
        .add_rule(Box::new(pedantic_core::praxis::DetectDrift))
        .add_rule(Box::new(pedantic_core::praxis::PlanRemediation))
        .add_rule(Box::new(pedantic_core::praxis::EscalateFailure))
        .build();

    let outcome = engine.evaluate(vec![
        Fact::ConfigDocument(doc),
        Fact::ResourceState(ResourceState {
            name: "res-b".to_string(),
            status: ResourceStatus::Drifted,
        }),
    ]);

    assert!(
        outcome
            .events
            .iter()
            .any(|event| matches!(event, Event::ConfigParsed { .. }))
    );
    assert!(
        outcome
            .events
            .iter()
            .any(|event| matches!(event, Event::DriftDetected { .. }))
    );
    assert!(
        !outcome
            .events
            .iter()
            .any(|event| matches!(event, Event::ValidationFailed { .. }))
    );

    let tasks = outcome.plan_tasks();
    assert!(tasks.iter().any(|task| task.action == PlanAction::Test));
    assert!(tasks.iter().any(|task| task.action == PlanAction::Set));
}

#[test]
fn max_iteration_cap_prevents_infinite_loop() {
    struct EndlessRule {
        counter: Mutex<u32>,
    }

    impl Rule for EndlessRule {
        fn name(&self) -> &'static str {
            "endless"
        }

        fn apply(&self, _facts: &[Fact], _events: &[Event]) -> RuleOutput {
            let mut output = RuleOutput::default();
            let mut count = self.counter.lock().unwrap();
            *count += 1;
            output.new_facts.push(Fact::HostInventory(HostInventory {
                hostname: format!("host-{count}"),
                os: "linux".to_string(),
            }));
            output
        }
    }

    let engine = Engine::builder()
        .max_iterations(5)
        .add_rule(Box::new(EndlessRule {
            counter: Mutex::new(0),
        }))
        .build();

    let outcome = engine.evaluate(vec![]);
    assert_eq!(outcome.iterations, 5);
}
