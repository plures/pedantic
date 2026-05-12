use crate::model::DscDocument;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ExportError {
    #[error("failed to render YAML: {0}")]
    Yaml(#[from] serde_yaml::Error),
}

pub fn export_dsc_v3(doc: &DscDocument) -> Result<String, ExportError> {
    let yaml = serde_yaml::to_string(doc)?;
    Ok(yaml)
}
