use pedantic_executor::inventory::{discover_hosts, parse_hosts};
use std::path::PathBuf;

#[test]
fn parses_inventory_hosts() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("inventory.yaml");
    let mut hosts = discover_hosts(path).expect("inventory should parse");
    hosts.sort_by(|a, b| a.hostname.cmp(&b.hostname));

    assert_eq!(hosts.len(), 2);
    assert!(hosts.iter().any(|host| host.hostname == "192.168.1.10"
        && host.os == "windows"
        && host.connection == "winrm"));
    assert!(hosts.iter().any(|host| host.hostname == "192.168.1.11"
        && host.os == "linux"
        && host.connection == "ssh"));
}

#[test]
fn parses_inventory_hosts_from_a_supplied_document() {
    let content = include_str!("fixtures/inventory.yaml");
    let mut hosts = parse_hosts(content).expect("inventory should parse");
    hosts.sort_by(|a, b| a.hostname.cmp(&b.hostname));

    assert_eq!(hosts.len(), 2);
    assert_eq!(hosts[0].hostname, "192.168.1.10");
    assert_eq!(hosts[1].connection, "ssh");
}
