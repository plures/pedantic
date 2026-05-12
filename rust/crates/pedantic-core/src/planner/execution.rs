use crate::model::{DscDocument, DscResource};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ExecutionPlan {
    pub steps: Vec<PlanStep>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PlanStep {
    pub resource_name: String,
    pub resource_type: String,
}

#[derive(Debug, Error)]
pub enum PlanError {
    #[error("unknown dependency: {0}")]
    UnknownDependency(String),
    #[error("circular dependency detected")]
    CircularDependency,
}

pub fn plan_execution(doc: &DscDocument) -> Result<ExecutionPlan, PlanError> {
    let mut steps = Vec::new();
    let mut visiting = Vec::new();
    let mut visited = std::collections::HashSet::new();
    let resource_map: std::collections::HashMap<_, _> = doc
        .resources
        .iter()
        .map(|r| (r.name.clone(), r))
        .collect();

    for resource in &doc.resources {
        visit_resource(resource, &resource_map, &mut visiting, &mut visited, &mut steps)?;
    }

    Ok(ExecutionPlan { steps })
}

fn visit_resource<'a>(
    resource: &'a DscResource,
    resource_map: &std::collections::HashMap<String, &'a DscResource>,
    visiting: &mut Vec<String>,
    visited: &mut std::collections::HashSet<String>,
    steps: &mut Vec<PlanStep>,
) -> Result<(), PlanError> {
    if visited.contains(&resource.name) {
        return Ok(());
    }

    if visiting.contains(&resource.name) {
        return Err(PlanError::CircularDependency);
    }

    visiting.push(resource.name.clone());
    for dep in &resource.depends_on {
        let normalized = normalize_dependency(dep);
        let dep_resource = resource_map
            .get(normalized)
            .ok_or_else(|| PlanError::UnknownDependency(dep.clone()))?;
        visit_resource(dep_resource, resource_map, visiting, visited, steps)?;
    }

    visiting.retain(|name| name != &resource.name);
    visited.insert(resource.name.clone());
    steps.push(PlanStep {
        resource_name: resource.name.clone(),
        resource_type: resource.resource_type.clone(),
    });
    Ok(())
}

fn normalize_dependency(dep: &str) -> &str {
    if let Some(idx) = dep.rfind(']') {
        return &dep[idx + 1..];
    }
    dep
}
