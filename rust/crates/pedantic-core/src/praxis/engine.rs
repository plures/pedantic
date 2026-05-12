use crate::praxis::{Constraint, ConstraintViolation, Event, Fact, Rule, RuleOutput};

const DEFAULT_MAX_ITERATIONS: usize = 100;

pub struct Engine {
    pub rules: Vec<Box<dyn Rule>>,
    pub constraints: Vec<Box<dyn Constraint>>,
    pub max_iterations: usize,
}

#[derive(Debug, Default, serde::Serialize)]
pub struct EngineOutcome {
    pub facts: Vec<Fact>,
    pub events: Vec<Event>,
    pub fired_rules: Vec<String>,
    pub iterations: usize,
    pub constraint_violations: Vec<ConstraintViolation>,
}

impl EngineOutcome {
    pub fn config_documents(&self) -> Vec<&crate::model::DscDocument> {
        self.facts
            .iter()
            .filter_map(|fact| match fact {
                Fact::ConfigDocument(doc) => Some(doc),
                _ => None,
            })
            .collect()
    }

    pub fn resource_states(&self) -> Vec<&crate::praxis::ResourceState> {
        self.facts
            .iter()
            .filter_map(|fact| match fact {
                Fact::ResourceState(state) => Some(state),
                _ => None,
            })
            .collect()
    }

    pub fn plan_tasks(&self) -> Vec<&crate::praxis::PlanTask> {
        self.facts
            .iter()
            .filter_map(|fact| match fact {
                Fact::PlanTasks(tasks) => Some(tasks.as_slice()),
                _ => None,
            })
            .flat_map(|tasks| tasks.iter())
            .collect()
    }

    pub fn execution_results(&self) -> Vec<&crate::praxis::ExecutionResult> {
        self.facts
            .iter()
            .filter_map(|fact| match fact {
                Fact::ExecutionResult(result) => Some(result),
                _ => None,
            })
            .collect()
    }
}

pub struct EngineBuilder {
    rules: Vec<Box<dyn Rule>>,
    constraints: Vec<Box<dyn Constraint>>,
    max_iterations: usize,
}

impl Default for EngineBuilder {
    fn default() -> Self {
        Self {
            rules: Vec::new(),
            constraints: Vec::new(),
            max_iterations: DEFAULT_MAX_ITERATIONS,
        }
    }
}

impl EngineBuilder {
    pub fn add_rule(mut self, rule: Box<dyn Rule>) -> Self {
        self.rules.push(rule);
        self
    }

    pub fn add_constraint(mut self, constraint: Box<dyn Constraint>) -> Self {
        self.constraints.push(constraint);
        self
    }

    pub fn max_iterations(mut self, max_iterations: usize) -> Self {
        self.max_iterations = max_iterations;
        self
    }

    pub fn build(self) -> Engine {
        Engine {
            rules: self.rules,
            constraints: self.constraints,
            max_iterations: self.max_iterations,
        }
    }
}

impl Engine {
    pub fn new(rules: Vec<Box<dyn Rule>>, constraints: Vec<Box<dyn Constraint>>) -> Self {
        Self {
            rules,
            constraints,
            max_iterations: DEFAULT_MAX_ITERATIONS,
        }
    }

    pub fn builder() -> EngineBuilder {
        EngineBuilder::default()
    }

    pub fn evaluate(&self, input_facts: Vec<Fact>) -> EngineOutcome {
        let mut facts = input_facts;
        let mut events = Vec::new();
        let mut fired_rules = Vec::new();
        let mut iterations = 0;

        let mut rules: Vec<&dyn Rule> = self.rules.iter().map(|rule| rule.as_ref()).collect();
        rules.sort_by_key(|rule| rule.priority());

        for _ in 0..self.max_iterations {
            iterations += 1;
            let mut new_fact_added = false;

            for rule in &rules {
                let RuleOutput { new_facts, new_events } = rule.apply(&facts, &events);
                let mut rule_fired = false;

                for fact in new_facts {
                    if !facts.contains(&fact) {
                        facts.push(fact);
                        new_fact_added = true;
                        rule_fired = true;
                    }
                }

                if !new_events.is_empty() {
                    events.extend(new_events);
                    rule_fired = true;
                }

                if rule_fired {
                    fired_rules.push(rule.name().to_string());
                }
            }

            if !new_fact_added {
                break;
            }
        }

        let mut constraint_violations = Vec::new();
        for constraint in &self.constraints {
            if let Err(err) = constraint.check(&facts, &events) {
                constraint_violations.push(err);
            }
        }

        EngineOutcome {
            facts,
            events,
            fired_rules,
            iterations,
            constraint_violations,
        }
    }
}
