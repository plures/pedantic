use pedantic_core::export::export_dsc_v3;
use pedantic_core::parser::{parse_dsc_v3, parse_simple_dsl};
use pedantic_core::validator::validate_document;
use std::fs;
use std::path::PathBuf;

fn fixture_path(name: &str) -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("../../tests/fixtures");
    path.push(name);
    path
}

#[test]
fn parse_cluster_example_and_validate() {
    let content = fs::read_to_string(fixture_path("AgentHost.Cluster.yaml")).unwrap();
    let doc = parse_dsc_v3(&content).unwrap();
    let report = validate_document(&doc);
    assert!(report.is_ok(), "expected no validation errors: {report:?}");
}

#[test]
fn parse_guest_example_reports_errors() {
    let content = fs::read_to_string(fixture_path("AgentVm.Guest.yaml")).unwrap();
    let doc = parse_dsc_v3(&content).unwrap();
    let report = validate_document(&doc);
    assert!(!report.is_ok());
}

#[test]
fn parse_simple_install_dsl() {
    let content = fs::read_to_string(fixture_path("simple-install.yaml")).unwrap();
    let doc = parse_simple_dsl(&content).unwrap();
    assert!(!doc.resources.is_empty());
}

#[test]
fn round_trip_export_parse() {
    let content = fs::read_to_string(fixture_path("AgentHost.Cluster.yaml")).unwrap();
    let doc = parse_dsc_v3(&content).unwrap();
    let yaml = export_dsc_v3(&doc).unwrap();
    let doc_round = parse_dsc_v3(&yaml).unwrap();
    assert_eq!(doc, doc_round);
}
