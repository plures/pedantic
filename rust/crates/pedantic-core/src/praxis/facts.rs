use crate::model::{DscDocument, DscResource};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum Fact {
    ConfigDocument(DscDocument),
    ResourceState(ResourceState),
    ResourceDesired(ResourceDesired),
    HostInventory(HostInventory),
    PlanTasks(Vec<PlanTask>),
    ExecutionResult(ExecutionResult),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ResourceState {
    pub name: String,
    pub status: ResourceStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ResourceDesired {
    pub resource: DscResource,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HostInventory {
    pub hostname: String,
    pub os: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanTask {
    pub resource_name: String,
    pub action: PlanAction,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionResult {
    pub success: bool,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PlanAction {
    Test,
    Set,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ResourceStatus {
    Compliant,
    Drifted,
    Failed,
}
