use pedantic_core::model::{DscDocument, DscResource};
use pedantic_core::parser::parse_dsc_v3;
use std::fs;
use std::path::PathBuf;

fn fixture_path(name: &str) -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("../../tests/fixtures");
    path.push(name);
    path
}

fn find_resource<'a>(doc: &'a DscDocument, name: &str) -> &'a DscResource {
    doc.resources
        .iter()
        .find(|resource| resource.name == name)
        .unwrap_or_else(|| panic!("resource {name} not found"))
}

#[test]
fn rejects_invalid_schema() {
    let yaml = r#"$schema: https://example.com/invalid.json
name: TestDoc
version: 1.0.0
resources: []
"#;
    let err = parse_dsc_v3(yaml).expect_err("expected schema error");
    assert!(err.to_string().contains("invalid $schema"));
}

#[test]
fn normalizes_parameter_types() {
    let yaml = r#"name: ParamDoc
version: 1.0.0
parameters:
  Count:
    type: int
  Enabled:
    type: bool
resources: []
"#;
    let doc = parse_dsc_v3(yaml).unwrap();
    let types: std::collections::HashMap<_, _> = doc
        .parameters
        .iter()
        .map(|param| (param.name.as_str(), param.param_type.as_str()))
        .collect();
    assert_eq!(types.get("Count"), Some(&"integer"));
    assert_eq!(types.get("Enabled"), Some(&"boolean"));
}

#[test]
fn normalizes_dependency_references() {
    let content = fs::read_to_string(fixture_path("AgentHost.Cluster.yaml")).unwrap();
    let doc = parse_dsc_v3(&content).unwrap();
    let vswitch = find_resource(&doc, "ExternalVSwitch");
    assert_eq!(vswitch.depends_on, vec!["HyperVFeature".to_string()]);
}

#[test]
fn extracts_nested_resources() {
    let content = fs::read_to_string(fixture_path("AgentVm.Guest.yaml")).unwrap();
    let doc = parse_dsc_v3(&content).unwrap();

    let names: std::collections::HashSet<_> =
        doc.resources.iter().map(|r| r.name.as_str()).collect();
    assert!(names.contains("OpenSshConfig"));
    assert!(names.contains("CopyCaPubKey"));
    assert!(names.contains("SshdConfig"));

    let adapter = find_resource(&doc, "OpenSshConfig");
    assert!(adapter.properties.get("resources").is_none());
}

#[test]
fn preserves_parameter_reference_strings() {
    let content = fs::read_to_string(fixture_path("AgentHost.Cluster.yaml")).unwrap();
    let doc = parse_dsc_v3(&content).unwrap();
    let vswitch = find_resource(&doc, "ExternalVSwitch");
    let net_adapter = vswitch
        .properties
        .get("NetAdapterName")
        .and_then(|value| value.as_str())
        .unwrap();
    assert_eq!(net_adapter, "[Parameter('VmSwitchAdapter')]");
}
