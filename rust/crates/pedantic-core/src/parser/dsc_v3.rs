use crate::model::DscDocument;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DscParseError {
    #[error("failed to parse YAML: {0}")]
    Yaml(#[from] serde_yaml::Error),
}

pub fn parse_dsc_v3(yaml: &str) -> Result<DscDocument, DscParseError> {
    let doc: DscDocument = serde_yaml::from_str(yaml)?;
    Ok(doc)
}
