use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum Event {
    ConfigParsed { name: String },
    ValidationFailed { message: String },
    DriftDetected { resource: String },
    ResourceConverged { resource: String },
    ResourceFailed { resource: String, message: String },
}
