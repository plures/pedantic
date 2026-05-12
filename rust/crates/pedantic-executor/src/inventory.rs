use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HostRecord {
    pub hostname: String,
    pub os: String,
    pub connection: String,
}

pub fn discover_hosts() -> Vec<HostRecord> {
    Vec::new()
}
