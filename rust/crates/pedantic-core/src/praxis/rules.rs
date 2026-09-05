use crate::planner::plan_execution;
use crate::praxis::{Event, Fact, PlanAction, PlanTask, ResourceStatus};
use regex::Regex;

pub trait Rule: Send + Sync {
    fn name(&self) -> &'static str;
    fn priority(&self) -> u32 {
        100
    }
    fn apply(&self, facts: &[Fact], events: &[Event]) -> RuleOutput;
}

#[derive(Debug, Default, Clone)]
pub struct RuleOutput {
    pub new_facts: Vec<Fact>,
    pub new_events: Vec<Event>,
}

pub struct ParseAndValidate;

impl Rule for ParseAndValidate {
    fn name(&self) -> &'static str {
        "parse-and-validate"
    }

    fn priority(&self) -> u32 {
        10
    }

    fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        if let Some(Fact::ConfigDocument(doc)) =
            facts.iter().find(|f| matches!(f, Fact::ConfigDocument(_)))
        {
            output.new_events.push(Event::ConfigParsed {
                name: doc.name.clone(),
            });
        }
        output
    }
}

pub struct ValidateParameters;

impl Rule for ValidateParameters {
    fn name(&self) -> &'static str {
        "validate-parameters"
    }

    fn priority(&self) -> u32 {
        15
    }

    fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        let Some(Fact::ConfigDocument(doc)) =
            facts.iter().find(|f| matches!(f, Fact::ConfigDocument(_)))
        else {
            return output;
        };

        let param_names: std::collections::HashSet<_> =
            doc.parameters.iter().map(|p| p.name.as_str()).collect();
        let re = Regex::new(r"(?i)\[parameters?\('([^']+)'\)\]").unwrap();

        for resource in &doc.resources {
            collect_parameter_refs(&resource.properties, &re, &param_names, &mut output);
        }

        output
    }
}

pub struct ResolveExecutionOrder;

impl Rule for ResolveExecutionOrder {
    fn name(&self) -> &'static str {
        "resolve-execution-order"
    }

    fn priority(&self) -> u32 {
        30
    }

    fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        let Some(Fact::ConfigDocument(doc)) =
            facts.iter().find(|f| matches!(f, Fact::ConfigDocument(_)))
        else {
            return output;
        };

        match plan_execution(doc) {
            Ok(plan) => {
                let tasks: Vec<PlanTask> = plan
                    .steps
                    .into_iter()
                    .map(|step| PlanTask {
                        resource_name: step.resource_name,
                        action: PlanAction::Test,
                    })
                    .collect();
                if !tasks.is_empty() {
                    output.new_facts.push(Fact::PlanTasks(tasks));
                }
            }
            Err(err) => {
                output.new_events.push(Event::ValidationFailed {
                    message: err.to_string(),
                });
            }
        }

        output
    }
}

pub struct DetectDrift;

impl Rule for DetectDrift {
    fn name(&self) -> &'static str {
        "detect-drift"
    }

    fn priority(&self) -> u32 {
        20
    }

    fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        for fact in facts {
            if let Fact::ResourceState(state) = fact
                && state.status == ResourceStatus::Drifted
            {
                output.new_events.push(Event::DriftDetected {
                    resource: state.name.clone(),
                });
            }
        }
        output
    }
}

pub struct PlanRemediation;

impl Rule for PlanRemediation {
    fn name(&self) -> &'static str {
        "plan-remediation"
    }

    fn priority(&self) -> u32 {
        40
    }

    fn apply(&self, _facts: &[Fact], events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        let mut tasks = Vec::new();

        for event in events {
            if let Event::DriftDetected { resource } = event {
                tasks.push(PlanTask {
                    resource_name: resource.clone(),
                    action: PlanAction::Set,
                });
            }
        }

        if !tasks.is_empty() {
            output.new_facts.push(Fact::PlanTasks(tasks));
        }

        output
    }
}

pub struct EscalateFailure;

impl Rule for EscalateFailure {
    fn name(&self) -> &'static str {
        "escalate-failure"
    }

    fn priority(&self) -> u32 {
        50
    }

    fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        for fact in facts {
            if let Fact::ResourceState(state) = fact
                && state.status == ResourceStatus::Failed
            {
                output.new_events.push(Event::ResourceFailed {
                    resource: state.name.clone(),
                    message: "resource failed".to_string(),
                });
            }
        }
        output
    }
}

fn collect_parameter_refs(
    value: &serde_json::Value,
    re: &Regex,
    param_names: &std::collections::HashSet<&str>,
    output: &mut RuleOutput,
) {
    match value {
        serde_json::Value::String(text) => {
            for cap in re.captures_iter(text) {
                if let Some(name) = cap.get(1).map(|m| m.as_str())
                    && !param_names.contains(name)
                {
                    output.new_events.push(Event::ValidationFailed {
                        message: format!("unknown parameter reference: {}", name),
                    });
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_parameter_refs(item, re, param_names, output);
            }
        }
        serde_json::Value::Object(map) => {
            for value in map.values() {
                collect_parameter_refs(value, re, param_names, output);
            }
        }
        _ => {}
    }
}
