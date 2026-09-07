use crate::model::{DscDocument, DscResource, Parameter};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SimpleParseError {
    #[error("failed to parse YAML: {0}")]
    Yaml(#[from] serde_yaml::Error),
    #[error("invalid simple DSL format")]
    InvalidFormat,
}

pub fn parse_simple_dsl(yaml: &str) -> Result<DscDocument, SimpleParseError> {
    let value: serde_yaml::Value = serde_yaml::from_str(yaml)?;
    let mapping = value.as_mapping().ok_or(SimpleParseError::InvalidFormat)?;

    let install_key = serde_yaml::Value::String("dsc.install".to_string());
    let install = mapping
        .get(&install_key)
        .ok_or(SimpleParseError::InvalidFormat)?;
    let install_map = install
        .as_mapping()
        .ok_or(SimpleParseError::InvalidFormat)?;

    let packages_key = serde_yaml::Value::String("packages".to_string());
    let packages = install_map
        .get(&packages_key)
        .ok_or(SimpleParseError::InvalidFormat)?;
    let packages = packages
        .as_sequence()
        .ok_or(SimpleParseError::InvalidFormat)?;

    let resources = packages
        .iter()
        .filter_map(|item| item.as_str())
        .enumerate()
        .map(|(idx, name)| DscResource {
            name: format!("package_{}_{}", idx + 1, name),
            resource_type: "Pedantic/Package".to_string(),
            depends_on: Vec::new(),
            properties: serde_json::json!({
                "Name": name,
                "Ensure": "Present"
            }),
        })
        .collect();

    Ok(DscDocument {
        schema: None,
        name: "SimpleInstall".to_string(),
        version: "1.0.0".to_string(),
        description: Some("Simple DSL install".to_string()),
        parameters: Vec::<Parameter>::new(),
        resources,
    })
}
