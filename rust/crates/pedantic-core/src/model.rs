use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DscDocument {
    #[serde(rename = "$schema", default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    pub name: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, deserialize_with = "deserialize_parameters")]
    pub parameters: Vec<Parameter>,
    #[serde(default)]
    pub resources: Vec<DscResource>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DscResource {
    pub name: String,
    #[serde(rename = "type")]
    pub resource_type: String,
    #[serde(default, rename = "dependsOn", alias = "depends_on")]
    pub depends_on: Vec<String>,
    #[serde(default)]
    pub properties: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Parameter {
    pub name: String,
    #[serde(rename = "type")]
    pub param_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Host {
    pub hostname: String,
    pub os: OsType,
    pub connection: ConnectionType,
    pub compliance_status: ComplianceStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_check: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ComplianceRun {
    pub id: String,
    pub run_type: RunType,
    pub status: RunStatus,
    pub started_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<DateTime<Utc>>,
    pub resources_total: usize,
    pub resources_compliant: usize,
    pub resources_drifted: usize,
    pub results: Vec<ResourceResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ResourceResult {
    pub name: String,
    pub status: ResourceStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum OsType {
    Windows,
    Linux,
    Macos,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ConnectionType {
    Local,
    Ssh,
    Winrm,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ComplianceStatus {
    Unknown,
    Compliant,
    Drifted,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum RunType {
    Test,
    Set,
    Validate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum RunStatus {
    Pending,
    Running,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ResourceStatus {
    Compliant,
    Drifted,
    Failed,
}

fn deserialize_parameters<'de, D>(deserializer: D) -> Result<Vec<Parameter>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum ParameterDef {
        List(Vec<Parameter>),
        Map(std::collections::BTreeMap<String, ParameterBody>),
    }

    #[derive(Deserialize)]
    struct ParameterBody {
        #[serde(rename = "type")]
        param_type: String,
        #[serde(default)]
        default: Option<serde_json::Value>,
    }

    let def = ParameterDef::deserialize(deserializer)?;
    match def {
        ParameterDef::List(list) => Ok(list),
        ParameterDef::Map(map) => Ok(map
            .into_iter()
            .map(|(name, body)| Parameter {
                name,
                param_type: body.param_type,
                default: body.default,
            })
            .collect()),
    }
}
