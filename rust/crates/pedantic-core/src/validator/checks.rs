use crate::model::{DscDocument, DscResource};
use regex::Regex;
use thiserror::Error;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ValidationError {
    #[error("duplicate resource name: {0}")]
    DuplicateResource(String),
    #[error("unknown dependency: {0}")]
    UnknownDependency(String),
    #[error("circular dependency detected")]
    CircularDependency,
    #[error("missing required property '{property}' for resource '{resource}'")]
    MissingRequiredProperty { resource: String, property: String },
    #[error("unknown parameter reference: {0}")]
    UnknownParameter(String),
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct ValidationReport {
    pub errors: Vec<ValidationError>,
}

impl ValidationReport {
    pub fn is_ok(&self) -> bool {
        self.errors.is_empty()
    }
}

pub fn validate_document(doc: &DscDocument) -> ValidationReport {
    let mut report = ValidationReport::default();

    report.errors.extend(check_unique_resource_names(doc));
    report.errors.extend(check_dependencies(doc));
    report.errors.extend(check_required_properties(doc));
    report.errors.extend(check_parameter_references(doc));

    report
}

fn check_unique_resource_names(doc: &DscDocument) -> Vec<ValidationError> {
    let mut seen = std::collections::HashSet::new();
    let mut errors = Vec::new();

    for resource in &doc.resources {
        if !seen.insert(resource.name.clone()) {
            errors.push(ValidationError::DuplicateResource(resource.name.clone()));
        }
    }

    errors
}

fn check_dependencies(doc: &DscDocument) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    let resource_map: std::collections::HashMap<_, _> =
        doc.resources.iter().map(|r| (r.name.clone(), r)).collect();

    for resource in &doc.resources {
        for dep in &resource.depends_on {
            let normalized = normalize_dependency(dep);
            if !resource_map.contains_key(normalized) {
                errors.push(ValidationError::UnknownDependency(dep.clone()));
            }
        }
    }

    if has_cycle(doc) {
        errors.push(ValidationError::CircularDependency);
    }

    errors
}

fn has_cycle(doc: &DscDocument) -> bool {
    let resource_map: std::collections::HashMap<_, _> =
        doc.resources.iter().map(|r| (r.name.clone(), r)).collect();

    let mut visiting = std::collections::HashSet::new();
    let mut visited = std::collections::HashSet::new();

    for resource in &doc.resources {
        if detect_cycle(resource, &resource_map, &mut visiting, &mut visited) {
            return true;
        }
    }

    false
}

fn detect_cycle(
    resource: &DscResource,
    resource_map: &std::collections::HashMap<String, &DscResource>,
    visiting: &mut std::collections::HashSet<String>,
    visited: &mut std::collections::HashSet<String>,
) -> bool {
    if visited.contains(&resource.name) {
        return false;
    }
    if !visiting.insert(resource.name.clone()) {
        return true;
    }

    for dep in &resource.depends_on {
        let normalized = normalize_dependency(dep);
        if let Some(dep_resource) = resource_map.get(normalized)
            && detect_cycle(dep_resource, resource_map, visiting, visited)
        {
            return true;
        }
    }

    visiting.remove(&resource.name);
    visited.insert(resource.name.clone());
    false
}

fn check_required_properties(doc: &DscDocument) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    for resource in &doc.resources {
        let required = required_properties(&resource.resource_type);
        for prop in required {
            if resource.properties.get(prop).is_none() {
                errors.push(ValidationError::MissingRequiredProperty {
                    resource: resource.name.clone(),
                    property: prop.to_string(),
                });
            }
        }
    }
    errors
}

fn required_properties(resource_type: &str) -> &'static [&'static str] {
    match resource_type {
        "PSDesiredStateConfiguration/WindowsFeature" => &["Name", "Ensure"],
        _ => &[],
    }
}

fn normalize_dependency(dep: &str) -> &str {
    if let Some(idx) = dep.rfind(']') {
        return &dep[idx + 1..];
    }
    dep
}

fn check_parameter_references(doc: &DscDocument) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    let param_names: std::collections::HashSet<_> =
        doc.parameters.iter().map(|p| p.name.as_str()).collect();
    let re = Regex::new(r"(?i)\[parameters?\('([^']+)'\)\]").unwrap();

    for resource in &doc.resources {
        collect_parameter_refs(&resource.properties, &re, &param_names, &mut errors);
    }

    errors
}

fn collect_parameter_refs(
    value: &serde_json::Value,
    re: &Regex,
    param_names: &std::collections::HashSet<&str>,
    errors: &mut Vec<ValidationError>,
) {
    match value {
        serde_json::Value::String(text) => {
            for cap in re.captures_iter(text) {
                if let Some(name) = cap.get(1).map(|m| m.as_str())
                    && !param_names.contains(name)
                {
                    errors.push(ValidationError::UnknownParameter(name.to_string()));
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_parameter_refs(item, re, param_names, errors);
            }
        }
        serde_json::Value::Object(map) => {
            for value in map.values() {
                collect_parameter_refs(value, re, param_names, errors);
            }
        }
        _ => {}
    }
}
