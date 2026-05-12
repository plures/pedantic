use crate::praxis::{Event, Fact};
use thiserror::Error;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ConstraintViolation {
    #[error("cannot run set without a prior test")]
    NoSetWithoutTest,
    #[error("cannot deploy draft configuration")]
    NoDeployDraft,
    #[error("rendered config must be idempotent")]
    IdempotentRender,
}

pub trait Constraint: Send + Sync {
    fn name(&self) -> &'static str;
    fn check(&self, facts: &[Fact], events: &[Event]) -> Result<(), ConstraintViolation>;
}

pub struct NoSetWithoutTest;

impl Constraint for NoSetWithoutTest {
    fn name(&self) -> &'static str {
        "no-set-without-test"
    }

    fn check(&self, facts: &[Fact], _events: &[Event]) -> Result<(), ConstraintViolation> {
        let has_test = facts.iter().any(|fact| match fact {
            Fact::PlanTasks(tasks) => tasks.iter().any(|task| task.action == crate::praxis::PlanAction::Test),
            _ => false,
        });

        let has_set = facts.iter().any(|fact| match fact {
            Fact::PlanTasks(tasks) => tasks.iter().any(|task| task.action == crate::praxis::PlanAction::Set),
            _ => false,
        });

        if has_set && !has_test {
            Err(ConstraintViolation::NoSetWithoutTest)
        } else {
            Ok(())
        }
    }
}

pub struct NoDeployDraft;

impl Constraint for NoDeployDraft {
    fn name(&self) -> &'static str {
        "no-deploy-draft"
    }

    fn check(&self, _facts: &[Fact], _events: &[Event]) -> Result<(), ConstraintViolation> {
        Ok(())
    }
}

pub struct IdempotentRender;

impl Constraint for IdempotentRender {
    fn name(&self) -> &'static str {
        "idempotent-render"
    }

    fn check(&self, _facts: &[Fact], _events: &[Event]) -> Result<(), ConstraintViolation> {
        Ok(())
    }
}
