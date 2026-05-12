use crate::praxis::{Constraint, ConstraintViolation, Event, Fact, Rule, RuleOutput};

pub struct Engine {
    pub rules: Vec<Box<dyn Rule>>,
    pub constraints: Vec<Box<dyn Constraint>>,
}

#[derive(Debug, Default)]
pub struct EngineOutcome {
    pub facts: Vec<Fact>,
    pub events: Vec<Event>,
}

impl Engine {
    pub fn new(rules: Vec<Box<dyn Rule>>, constraints: Vec<Box<dyn Constraint>>) -> Self {
        Self { rules, constraints }
    }

    pub fn evaluate(&self, input_facts: Vec<Fact>) -> Result<EngineOutcome, ConstraintViolation> {
        let mut facts = input_facts;
        let mut events = Vec::new();

        for rule in &self.rules {
            let RuleOutput { new_facts, new_events } = rule.apply(&facts, &events);
            facts.extend(new_facts);
            events.extend(new_events);
        }

        for constraint in &self.constraints {
            constraint.check(&facts, &events)?;
        }

        Ok(EngineOutcome { facts, events })
    }
}
