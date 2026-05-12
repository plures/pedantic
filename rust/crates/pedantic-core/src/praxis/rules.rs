use crate::praxis::{Event, Fact, ResourceStatus};

pub trait Rule: Send + Sync {
    fn name(&self) -> &'static str;
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

    fn apply(&self, facts: &[Fact], _events: &[Event]) -> RuleOutput {
        let mut output = RuleOutput::default();
        if let Some(Fact::ConfigDocument(doc)) = facts.iter().find(|f| matches!(f, Fact::ConfigDocument(_))) {
            output.new_events.push(Event::ConfigParsed { name: doc.name.clone() });
        }
        output
    }
}

pub struct DetectDrift;

impl Rule for DetectDrift {
    fn name(&self) -> &'static str {
        "detect-drift"
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

    fn apply(&self, _facts: &[Fact], _events: &[Event]) -> RuleOutput {
        RuleOutput::default()
    }
}

pub struct EscalateFailure;

impl Rule for EscalateFailure {
    fn name(&self) -> &'static str {
        "escalate-failure"
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
