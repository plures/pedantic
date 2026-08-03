use serde::Deserialize;
use std::path::PathBuf;
use std::process::ExitStatus;
use std::time::Duration;
use thiserror::Error;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::time::timeout;

#[derive(Debug, Clone)]
pub enum DscCommand {
    ConfigGet,
    ConfigTest,
    ConfigSet,
    ConfigValidate,
    ConfigExport { resource_type: String },
    ResourceList,
    ResourceGet { resource_type: String },
    ResourceTest { resource_type: String },
    ResourceSet { resource_type: String },
    ResourceExport { resource_type: String },
}

#[derive(Debug, Clone)]
pub enum DscInput {
    Path(String),
    Stdin(String),
}

impl DscInput {
    pub fn stdin(&self) -> Option<&str> {
        match self {
            DscInput::Stdin(content) => Some(content),
            DscInput::Path(_) => None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct DscRunOptions {
    pub timeout: Option<Duration>,
    pub working_dir: Option<PathBuf>,
    pub env: Vec<(String, String)>,
}

#[derive(Debug, Clone)]
pub struct DscOutput {
    pub status: ExitStatus,
    pub stdout: String,
    pub stderr: String,
    pub json: Option<serde_json::Value>,
}

#[derive(Debug, Clone)]
pub struct DscTestResult {
    pub resource_name: String,
    pub resource_type: String,
    pub in_desired_state: bool,
    pub properties: serde_json::Value,
}

#[derive(Debug, Error)]
pub enum DscError {
    #[error("dsc not found")]
    NotFound,
    #[error("failed to spawn dsc: {0}")]
    Spawn(std::io::Error),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("dsc timed out after {0:?}")]
    Timeout(Duration),
    #[error("dsc exited with status {status}")]
    Execution {
        status: ExitStatus,
        stdout: String,
        stderr: String,
    },
    #[error("failed to parse dsc output: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("failed to serialize DSC config: {0}")]
    Yaml(#[from] serde_yaml::Error),
    #[error("ssh connection failed: {0}")]
    SshConnection(String),
}

pub fn build_dsc_args(command: &DscCommand, input: &DscInput) -> Vec<String> {
    match command {
        DscCommand::ConfigGet => build_config_args("get", input),
        DscCommand::ConfigTest => build_config_args("test", input),
        DscCommand::ConfigSet => build_config_args("set", input),
        DscCommand::ConfigValidate => build_config_args("validate", input),
        DscCommand::ConfigExport { resource_type } => {
            vec![
                "config".into(),
                "export".into(),
                "-r".into(),
                resource_type.clone(),
            ]
        }
        DscCommand::ResourceList => vec!["resource".into(), "list".into()],
        DscCommand::ResourceGet { resource_type } => {
            build_resource_args("get", resource_type, input)
        }
        DscCommand::ResourceTest { resource_type } => {
            build_resource_args("test", resource_type, input)
        }
        DscCommand::ResourceSet { resource_type } => {
            build_resource_args("set", resource_type, input)
        }
        DscCommand::ResourceExport { resource_type } => {
            vec![
                "resource".into(),
                "export".into(),
                "-r".into(),
                resource_type.clone(),
            ]
        }
    }
}

fn build_config_args(action: &str, input: &DscInput) -> Vec<String> {
    let mut args = vec!["config".into(), action.into()];
    match input {
        DscInput::Path(path) => args.push(path.clone()),
        DscInput::Stdin(_) => {
            args.push("--input".into());
            args.push("-".into());
        }
    }
    args
}

fn build_resource_args(action: &str, resource_type: &str, input: &DscInput) -> Vec<String> {
    let mut args = vec!["resource".into(), action.into(), resource_type.into()];
    if matches!(input, DscInput::Stdin(_)) {
        args.push("--input".into());
        args.push("-".into());
    }
    args
}

pub async fn run_dsc(
    command: DscCommand,
    input: DscInput,
    options: &DscRunOptions,
) -> Result<DscOutput, DscError> {
    let mut cmd = Command::new("dsc");
    cmd.args(build_dsc_args(&command, &input));
    if let Some(dir) = &options.working_dir {
        cmd.current_dir(dir);
    }
    if !options.env.is_empty() {
        cmd.envs(options.env.iter().cloned());
    }
    cmd.stdin(std::process::Stdio::piped())
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
        && let Some(mut stdin) = child.stdin.take()
    {
        stdin.write_all(stdin_content.as_bytes()).await?;
    }

    let output = if let Some(timeout_duration) = options.timeout {
        match timeout(timeout_duration, child.wait_with_output()).await {
            Ok(result) => result?,
            Err(_) => return Err(DscError::Timeout(timeout_duration)),
        }
    } else {
        child.wait_with_output().await?
    };

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
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

pub fn parse_test_results(output: &DscOutput) -> Result<Vec<DscTestResult>, DscError> {
    let Some(json) = output.json.clone() else {
        return Ok(Vec::new());
    };
    parse_test_results_from_value(&json)
}

fn parse_test_results_from_value(
    value: &serde_json::Value,
) -> Result<Vec<DscTestResult>, DscError> {
    let values = if let Some(array) = value.as_array() {
        array.clone()
    } else if let Some(obj) = value.as_object() {
        if let Some(array) = obj.get("results").and_then(|v| v.as_array()) {
            array.clone()
        } else if let Some(array) = obj.get("resources").and_then(|v| v.as_array()) {
            array.clone()
        } else if let Some(array) = obj.get("value").and_then(|v| v.as_array()) {
            array.clone()
        } else {
            Vec::new()
        }
    } else {
        Vec::new()
    };

    let mut results = Vec::new();
    for entry in values {
        let raw: RawDscTestResult = serde_json::from_value(entry)?;
        results.push(DscTestResult {
            resource_name: raw.name,
            resource_type: raw.resource_type,
            in_desired_state: raw.in_desired_state,
            properties: raw.properties,
        });
    }
    Ok(results)
}

#[derive(Debug, Deserialize)]
struct RawDscTestResult {
    name: String,
    #[serde(rename = "type")]
    resource_type: String,
    #[serde(rename = "inDesiredState")]
    in_desired_state: bool,
    #[serde(default)]
    properties: serde_json::Value,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_config_get_args_uses_stdin() {
        let args = build_dsc_args(&DscCommand::ConfigGet, &DscInput::Stdin("{}".into()));
        assert_eq!(args, vec!["config", "get", "--input", "-"]);
    }

    #[test]
    fn build_config_export_args() {
        let args = build_dsc_args(
            &DscCommand::ConfigExport {
                resource_type: "SimpleDSC/PackageInstaller".into(),
            },
            &DscInput::Stdin("{}".into()),
        );
        assert_eq!(
            args,
            vec!["config", "export", "-r", "SimpleDSC/PackageInstaller"]
        );
    }

    #[test]
    fn build_resource_get_args_uses_path_input() {
        let args = build_dsc_args(
            &DscCommand::ResourceGet {
                resource_type: "SimpleDSC/PackageInstaller".into(),
            },
            &DscInput::Path("config.yaml".into()),
        );
        assert_eq!(args, vec!["resource", "get", "SimpleDSC/PackageInstaller"]);
    }

    #[test]
    fn build_resource_export_args() {
        let args = build_dsc_args(
            &DscCommand::ResourceExport {
                resource_type: "SimpleDSC/PackageInstaller".into(),
            },
            &DscInput::Stdin("{}".into()),
        );
        assert_eq!(
            args,
            vec!["resource", "export", "-r", "SimpleDSC/PackageInstaller"]
        );
    }

    #[test]
    fn build_resource_test_args_with_stdin() {
        let args = build_dsc_args(
            &DscCommand::ResourceTest {
                resource_type: "Pedantic.Ansible/Module".into(),
            },
            &DscInput::Stdin("{}".into()),
        );
        assert_eq!(
            args,
            vec![
                "resource",
                "test",
                "Pedantic.Ansible/Module",
                "--input",
                "-"
            ]
        );
    }

    #[test]
    fn parse_test_results_from_array() {
        let value = serde_json::json!([
            {
                "name": "pkg",
                "type": "SimpleDSC/PackageInstaller",
                "inDesiredState": true,
                "properties": {}
            }
        ]);
        let output = DscOutput {
            status: std::process::ExitStatus::default(),
            stdout: String::new(),
            stderr: String::new(),
            json: Some(value),
        };
        let results = parse_test_results(&output).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].resource_name, "pkg");
        assert!(results[0].in_desired_state);
    }
}
