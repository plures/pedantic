use crate::dsc::{build_dsc_args, DscCommand, DscError, DscInput, DscOutput};
use crate::transport::Transport;
use async_trait::async_trait;
use std::path::PathBuf;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

#[derive(Debug, Clone)]
pub struct SshTransport {
    pub host: String,
    pub port: Option<u16>,
    pub config_file: Option<PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuiltSshCommand {
    pub program: String,
    pub args: Vec<String>,
}

impl SshTransport {
    pub fn build_ssh_command(&self, command: &DscCommand, input: &DscInput) -> BuiltSshCommand {
        let mut args = Vec::new();
        if let Some(port) = self.port {
            args.push("-p".into());
            args.push(port.to_string());
        }
        if let Some(config_file) = &self.config_file {
            args.push("-F".into());
            args.push(config_file.to_string_lossy().to_string());
        }
        args.push(self.host.clone());

        let remote_command = build_remote_command(command, input);
        args.push(remote_command);

        BuiltSshCommand {
            program: "ssh".into(),
            args,
        }
    }
}

#[async_trait]
impl Transport for SshTransport {
    async fn run_dsc(&self, command: DscCommand, input: DscInput) -> Result<DscOutput, DscError> {
        let built = self.build_ssh_command(&command, &input);
        let mut cmd = Command::new(&built.program);
        cmd.args(&built.args)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());

        let mut child = cmd.spawn().map_err(|err| {
            if err.kind() == std::io::ErrorKind::NotFound {
                DscError::NotFound
            } else {
                DscError::Spawn(err)
            }
        })?;

        if let Some(stdin_content) = input.stdin()
            && let Some(mut stdin) = child.stdin.take() {
                stdin.write_all(stdin_content.as_bytes()).await?;
            }

        let output = child.wait_with_output().await?;
        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();

        if !output.status.success() {
            if output.status.code() == Some(255) {
                return Err(DscError::SshConnection(stderr));
            }
            return Err(DscError::Execution {
                status: output.status,
                stdout,
                stderr,
            });
        }

        let json = if stdout.trim().is_empty() {
            None
        } else {
            Some(serde_json::from_str(&stdout)?)
        };

        Ok(DscOutput {
            status: output.status,
            stdout,
            stderr,
            json,
        })
    }
}

fn build_remote_command(command: &DscCommand, input: &DscInput) -> String {
    let args = build_dsc_args(command, input);
    let mut pieces = Vec::with_capacity(args.len() + 1);
    pieces.push(shell_escape("dsc"));
    pieces.extend(args.iter().map(|arg| shell_escape(arg)));
    pieces.join(" ")
}

fn shell_escape(arg: &str) -> String {
    if arg.is_empty() {
        return "''".to_string();
    }

    let escaped = arg.replace('\'', "'\"'\"'");
    format!("'{}'", escaped)
}
