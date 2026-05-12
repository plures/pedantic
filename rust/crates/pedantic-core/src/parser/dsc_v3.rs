use crate::model::{DscDocument, DscResource};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DscParseError {
    #[error("failed to parse YAML: {0}")]
    Yaml(#[from] serde_yaml::Error),
    #[error("invalid $schema url: {0}")]
    InvalidSchema(String),
    #[error("invalid nested resource: {0}")]
    NestedResource(#[from] serde_json::Error),
    #[error("nested resources must be a list")]
    InvalidNestedResources,
}

pub fn parse_dsc_v3(yaml: &str) -> Result<DscDocument, DscParseError> {
    let mut doc: DscDocument = serde_yaml::from_str(yaml)?;

    if let Some(schema) = doc.schema.as_deref()
        && !is_valid_schema(schema) {
            return Err(DscParseError::InvalidSchema(schema.to_string()));
        }

    normalize_parameters(&mut doc);
    doc.resources = normalize_resources(doc.resources)?;

    Ok(doc)
}

fn is_valid_schema(schema: &str) -> bool {
    schema.starts_with("https://aka.ms/dsc/schemas/v3/") && schema.ends_with(".json")
}

fn normalize_parameters(doc: &mut DscDocument) {
    for param in &mut doc.parameters {
        param.param_type = normalize_param_type(&param.param_type);
    }
}

fn normalize_param_type(param_type: &str) -> String {
    match param_type.to_lowercase().as_str() {
        "int" | "integer" => "integer".to_string(),
        "bool" | "boolean" => "boolean".to_string(),
        other => other.to_string(),
    }
}

fn normalize_resources(resources: Vec<DscResource>) -> Result<Vec<DscResource>, DscParseError> {
    let mut normalized = Vec::new();

    for mut resource in resources {
        normalize_dependencies(&mut resource);
        let nested = extract_nested_resources(&mut resource)?;
        normalized.push(resource);
        if let Some(nested) = nested {
            for nested_resource in nested {
                normalized.push(nested_resource);
            }
        }
    }

    Ok(normalized)
}

fn normalize_dependencies(resource: &mut DscResource) {
    resource.depends_on = resource
        .depends_on
        .iter()
        .map(|dep| normalize_dependency(dep))
        .collect();
}

fn normalize_dependency(dep: &str) -> String {
    if dep.starts_with('[')
        && let Some(idx) = dep.rfind(']') {
            return dep[idx + 1..].to_string();
        }
    dep.to_string()
}

fn extract_nested_resources(
    resource: &mut DscResource,
) -> Result<Option<Vec<DscResource>>, DscParseError> {
    let Some(map) = resource.properties.as_object_mut() else {
        return Ok(None);
    };

    let Some(value) = map.remove("resources") else {
        return Ok(None);
    };

    let array = value.as_array().ok_or(DscParseError::InvalidNestedResources)?;
    let mut nested = Vec::new();
    for item in array {
        let nested_resource: DscResource = serde_json::from_value(item.clone())?;
        let normalized = normalize_resources(vec![nested_resource])?;
        nested.extend(normalized);
    }

    Ok(Some(nested))
}
