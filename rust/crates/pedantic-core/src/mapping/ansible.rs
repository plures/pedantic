use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AnsibleMapping {
    pub mappings: Vec<MappingEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MappingEntry {
    pub dsc_resource: String,
    pub ansible_module: String,
}

pub fn load_ansible_mapping() -> Result<AnsibleMapping, serde_yaml::Error> {
    let content = include_str!("ansible-mapping.yaml");
    serde_yaml::from_str(content)
}
