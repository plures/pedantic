use thiserror::Error;

#[derive(Debug, Clone)]
pub enum DscCommand {
    Test,
    Set,
    Validate,
}

#[derive(Debug, Clone)]
pub struct DscOutput {
    pub status: std::process::ExitStatus,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug, Error)]
pub enum DscError {
    #[error("failed to spawn dsc: {0}")]
    Spawn(#[from] std::io::Error),
}

pub async fn run_dsc(command: DscCommand, config_path: &str) -> Result<DscOutput, DscError> {
    let cmd_arg = match command {
        DscCommand::Test => "test",
        DscCommand::Set => "set",
        DscCommand::Validate => "validate",
    };

    let output = tokio::process::Command::new("dsc")
        .arg("config")
        .arg(cmd_arg)
        .arg(config_path)
        .output()
        .await?;

    Ok(DscOutput {
        status: output.status,
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}
