use pedantic_executor::dsc::{DscCommand, DscInput};
use pedantic_executor::transport::SshTransport;
use std::path::PathBuf;

#[test]
fn builds_ssh_command_with_port_and_config() {
    let transport = SshTransport {
        host: "server1".into(),
        port: Some(2222),
        config_file: Some(PathBuf::from("/home/user/.ssh/config")),
    };

    let command = DscCommand::ConfigTest;
    let input = DscInput::Stdin("config".into());
    let built = transport.build_ssh_command(&command, &input);

    assert_eq!(built.program, "ssh");
    assert_eq!(
        built.args,
        vec![
            "-p".to_string(),
            "2222".to_string(),
            "-F".to_string(),
            "/home/user/.ssh/config".to_string(),
            "server1".to_string(),
            "dsc config test --file -".to_string(),
        ]
    );
}
