use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HostRecord {
    pub hostname: String,
    pub os: String,
    pub connection: String,
}

#[derive(Debug, Error)]
pub enum InventoryError {
    #[error("failed to read inventory: {0}")]
    Io(#[from] std::io::Error),
    #[error("failed to parse inventory yaml: {0}")]
    Yaml(#[from] serde_yaml::Error),
}

pub fn discover_hosts(path: impl AsRef<Path>) -> Result<Vec<HostRecord>, InventoryError> {
    let content = std::fs::read_to_string(path)?;
    parse_hosts(&content)
}

/// Normalizes a caller-supplied inventory document without retaining its source.
pub fn parse_hosts(content: &str) -> Result<Vec<HostRecord>, InventoryError> {
    let inventory: InventoryFile = serde_yaml::from_str(content)?;

    let mut builders: BTreeMap<String, HostBuilder> = inventory
        .all
        .hosts
        .into_iter()
        .map(|(name, host)| {
            (
                name.clone(),
                HostBuilder {
                    name,
                    hostname: host.hostname,
                    os: host.os,
                    connection: host.connection,
                },
            )
        })
        .collect();

    for group in inventory.all.groups.values() {
        for host_name in &group.hosts {
            if let Some(builder) = builders.get_mut(host_name) {
                if builder.hostname.is_none() {
                    builder.hostname = group.vars.hostname.clone();
                }
                if builder.os.is_none() {
                    builder.os = group.vars.os.clone();
                }
                if builder.connection.is_none() {
                    builder.connection = group.vars.connection.clone();
                }
            }
        }
    }

    Ok(builders
        .into_values()
        .map(|builder| HostRecord {
            hostname: builder.hostname.unwrap_or_else(|| builder.name.clone()),
            os: builder.os.unwrap_or_else(|| "unknown".into()),
            connection: builder.connection.unwrap_or_else(|| "unknown".into()),
        })
        .collect())
}

#[derive(Debug, Deserialize)]
struct InventoryFile {
    all: InventoryRoot,
}

#[derive(Debug, Deserialize)]
struct InventoryRoot {
    #[serde(default)]
    hosts: BTreeMap<String, HostVars>,
    #[serde(default)]
    groups: BTreeMap<String, GroupVars>,
}

#[derive(Debug, Deserialize, Default, Clone)]
struct HostVars {
    #[serde(default)]
    hostname: Option<String>,
    #[serde(default)]
    os: Option<String>,
    #[serde(default)]
    connection: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct GroupVars {
    #[serde(default)]
    hosts: Vec<String>,
    #[serde(default)]
    vars: HostVars,
}

#[derive(Debug)]
struct HostBuilder {
    name: String,
    hostname: Option<String>,
    os: Option<String>,
    connection: Option<String>,
}
