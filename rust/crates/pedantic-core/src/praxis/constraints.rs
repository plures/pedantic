use crate::praxis::{Event, Fact};
use thiserror::Error;

#[derive(Debug, Error, Clone, PartialEq, Eq, serde::Serialize)]
pub enum ConstraintViolation {
    #[error("cannot run set without a prior test")]
    NoSetWithoutTest,
    #[error("cannot deploy draft configuration")]
    NoDeployDraft,
    #[error("rendered config must be idempotent")]
    IdempotentRender,
    #[error("drift exceeds threshold ({drifted}/{total} > {threshold}%)")]
    MaxDriftThresholdExceeded {
        drifted: usize,
        total: usize,
        threshold: u32,
    },
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
            Fact::PlanTasks(tasks) => tasks
                .iter()
                .any(|task| task.action == crate::praxis::PlanAction::Test),
            _ => false,
        });

        let has_set = facts.iter().any(|fact| match fact {
            Fact::PlanTasks(tasks) => tasks
                .iter()
                .any(|task| task.action == crate::praxis::PlanAction::Set),
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

    fn check(&self, facts: &[Fact], _events: &[Event]) -> Result<(), ConstraintViolation> {
        let Some(Fact::ConfigDocument(doc)) = facts
            .iter()
            .find(|fact| matches!(fact, Fact::ConfigDocument(_)))
        else {
            return Ok(());
        };

        let version = doc.version.to_lowercase();
        if version.contains("draft") || version.contains("0.0") {
            Err(ConstraintViolation::NoDeployDraft)
        } else {
            Ok(())
        }
    }
}

pub struct IdempotentRender;

impl Constraint for IdempotentRender {
    fn name(&self) -> &'static str {
        "idempotent-render"
    }

    fn check(&self, facts: &[Fact], _events: &[Event]) -> Result<(), ConstraintViolation> {
        let mut saw_set = false;
        let mut saw_successful_test = false;

        for fact in facts {
            if let Fact::ExecutionResult(result) = fact {
                if result.action == crate::praxis::PlanAction::Set {
                    saw_set = true;
                }
                if result.action == crate::praxis::PlanAction::Test && result.success {
                    saw_successful_test = true;
                }
            }
        }

        if saw_set && !saw_successful_test {
            Err(ConstraintViolation::IdempotentRender)
        } else {
            Ok(())
        }
    }
}

pub struct MaxDriftThreshold {
    pub threshold: u32,
}

impl Default for MaxDriftThreshold {
    fn default() -> Self {
        Self { threshold: 50 }
    }
}

impl Constraint for MaxDriftThreshold {
    fn name(&self) -> &'static str {
        "max-drift-threshold"
    }

    fn check(&self, facts: &[Fact], _events: &[Event]) -> Result<(), ConstraintViolation> {
        let drifted = facts
            .iter()
            .filter(|fact| matches!(fact, Fact::ResourceState(state) if state.status == crate::praxis::ResourceStatus::Drifted))
            .count();

        let total = if let Some(Fact::ConfigDocument(doc)) = facts
            .iter()
            .find(|fact| matches!(fact, Fact::ConfigDocument(_)))
        {
            doc.resources.len()
        } else {
            facts
                .iter()
                .filter(|fact| matches!(fact, Fact::ResourceState(_)))
                .count()
        };

        if total == 0 {
            return Ok(());
        }

        if drifted * 100 > self.threshold as usize * total {
            Err(ConstraintViolation::MaxDriftThresholdExceeded {
                drifted,
                total,
                threshold: self.threshold,
            })
        } else {
            Ok(())
        }
    }
}
