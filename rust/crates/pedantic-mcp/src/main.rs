//! Pedantic MCP Server
//!
//! Exposes Pedantic's core DSC v3 tooling (resource discovery, get/test, and
//! config validate/export) as MCP (Model Context Protocol) tools over stdio.
//! This lets any MCP-compatible client (Claude, VS Code, other agents) drive
//! real `dsc` operations through Pedantic without a bespoke integration.

use pedantic_executor::dsc::{DscCommand, DscError, DscInput, DscRunOptions, run_dsc};
use rmcp::schemars;
use rmcp::{
    ErrorData as McpError, ServiceExt,
    handler::server::{tool::ToolRouter, wrapper::Parameters},
    model::{CallToolResult, Content, ServerCapabilities, ServerInfo},
    tool, tool_handler, tool_router,
    transport::stdio,
};
use schemars::JsonSchema;
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub struct PedanticMcpServer {
    tool_router: ToolRouter<Self>,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ResourceListRequest {
    /// Optional resource type name filter (glob-style, e.g. "SimpleDSC*"). Defaults to all.
    #[serde(default)]
    pub filter: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ResourceGetRequest {
    /// Fully-qualified DSC resource type, e.g. "SimpleDSC/PackageInstaller".
    pub resource_type: String,
    /// Optional JSON instance properties to pass on stdin (required by most resources).
    #[serde(default)]
    pub instance: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ResourceTestRequest {
    /// Fully-qualified DSC resource type, e.g. "SimpleDSC/PackageInstaller".
    pub resource_type: String,
    /// JSON instance properties to test against (required by most resources).
    pub instance: serde_json::Value,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ResourceExportRequest {
    /// Fully-qualified DSC resource type, e.g. "SimpleDSC/PackageInstaller".
    pub resource_type: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ConfigValidateRequest {
    /// Full DSC v3 config document as a YAML or JSON string.
    pub document: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ConfigExportRequest {
    /// Fully-qualified DSC resource type to export, e.g. "SimpleDSC/PackageInstaller".
    pub resource_type: String,
}

fn dsc_error_to_mcp(err: DscError) -> McpError {
    McpError::internal_error(err.to_string(), None)
}

fn text_result(value: impl std::fmt::Display) -> CallToolResult {
    CallToolResult::success(vec![Content::text(value.to_string())])
}

#[tool_router]
impl PedanticMcpServer {
    pub fn new() -> Self {
        Self {
            tool_router: Self::tool_router(),
        }
    }

    /// List DSC resources discoverable on this host (equivalent to `dsc resource list`).
    #[tool(
        description = "List DSC v3 resources discoverable via the real dsc binary, optionally filtered by type name glob."
    )]
    async fn resource_list(
        &self,
        Parameters(req): Parameters<ResourceListRequest>,
    ) -> Result<CallToolResult, McpError> {
        let options = DscRunOptions::default();
        let output = if let Some(filter) = &req.filter {
            let mut opts = options.clone();
            opts.env.push(("PEDANTIC_MCP".into(), "1".into()));
            run_dsc_with_filter(filter, &opts)
                .await
                .map_err(dsc_error_to_mcp)?
        } else {
            run_dsc(
                DscCommand::ResourceList,
                DscInput::Stdin(String::new()),
                &options,
            )
            .await
            .map_err(dsc_error_to_mcp)?
        };
        Ok(text_result(output.stdout))
    }

    /// Get the current state of a DSC resource instance (equivalent to `dsc resource get`).
    #[tool(
        description = "Get the current state of a DSC v3 resource instance via the real dsc binary."
    )]
    async fn resource_get(
        &self,
        Parameters(req): Parameters<ResourceGetRequest>,
    ) -> Result<CallToolResult, McpError> {
        let resource_type = req.resource_type;
        let options = options_for_resource(&resource_type);
        let input = match &req.instance {
            Some(value) => DscInput::Stdin(value.to_string()),
            None => DscInput::Stdin(String::new()),
        };
        let output = run_dsc(DscCommand::ResourceGet { resource_type }, input, &options)
            .await
            .map_err(dsc_error_to_mcp)?;
        Ok(text_result(output.stdout))
    }

    /// Test whether a DSC resource instance is in its desired state (`dsc resource test`).
    #[tool(
        description = "Test whether a DSC v3 resource instance is in its desired state via the real dsc binary."
    )]
    async fn resource_test(
        &self,
        Parameters(req): Parameters<ResourceTestRequest>,
    ) -> Result<CallToolResult, McpError> {
        let resource_type = req.resource_type;
        let options = options_for_resource(&resource_type);
        let output = run_dsc(
            DscCommand::ResourceTest { resource_type },
            DscInput::Stdin(req.instance.to_string()),
            &options,
        )
        .await
        .map_err(dsc_error_to_mcp)?;
        Ok(text_result(output.stdout))
    }

    /// Export all instances of a DSC resource type on this host (`dsc resource export`), used for
    /// drift detection and reverse-engineering existing configuration.
    #[tool(
        description = "Export all instances of a DSC v3 resource type on this host via the real dsc binary (drift detection)."
    )]
    async fn resource_export(
        &self,
        Parameters(req): Parameters<ResourceExportRequest>,
    ) -> Result<CallToolResult, McpError> {
        let resource_type = req.resource_type;
        let options = options_for_resource(&resource_type);
        let output = run_dsc(
            DscCommand::ResourceExport { resource_type },
            DscInput::Stdin(String::new()),
            &options,
        )
        .await
        .map_err(dsc_error_to_mcp)?;
        Ok(text_result(output.stdout))
    }

    /// Export a DSC config fragment from every discovered instance of a resource type.
    #[tool(
        description = "Export a DSC config fragment for a resource type via the real dsc config export command."
    )]
    async fn config_export(
        &self,
        Parameters(req): Parameters<ConfigExportRequest>,
    ) -> Result<CallToolResult, McpError> {
        let resource_type = req.resource_type;
        let options = options_for_resource(&resource_type);
        let output = run_dsc(
            DscCommand::ConfigExport { resource_type },
            DscInput::Stdin(String::new()),
            &options,
        )
        .await
        .map_err(dsc_error_to_mcp)?;
        Ok(text_result(output.stdout))
    }

    /// Validate a full DSC v3 config document against the real dsc engine (`dsc config validate`).
    #[tool(
        description = "Validate a full DSC v3 config document (YAML or JSON) against the real dsc binary."
    )]
    async fn config_validate(
        &self,
        Parameters(req): Parameters<ConfigValidateRequest>,
    ) -> Result<CallToolResult, McpError> {
        let options = DscRunOptions::default();
        let output = run_dsc(
            DscCommand::ConfigValidate,
            DscInput::Stdin(req.document),
            &options,
        )
        .await
        .map_err(dsc_error_to_mcp)?;
        Ok(text_result(if output.stdout.trim().is_empty() {
            "OK".to_string()
        } else {
            output.stdout
        }))
    }
}

impl Default for PedanticMcpServer {
    fn default() -> Self {
        Self::new()
    }
}

fn options_for_resource(resource_type: &str) -> DscRunOptions {
    let mut options = DscRunOptions::default();
    if let Some(resource_path) = std::env::var_os("DSC_RESOURCE_PATH") {
        options.working_dir = find_resource_manifest_dir_in_path(resource_type, &resource_path);
    }
    options
}

fn find_resource_manifest_dir_in_path(
    resource_type: &str,
    resource_path: &std::ffi::OsStr,
) -> Option<PathBuf> {
    std::env::split_paths(resource_path)
        .find_map(|entry| find_resource_manifest_dir(&entry, resource_type))
}

fn find_resource_manifest_dir(entry: &Path, resource_type: &str) -> Option<PathBuf> {
    let files = std::fs::read_dir(entry).ok()?;
    for file in files.flatten() {
        let path = file.path();
        if !path.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if !name.ends_with(".dsc.resource.json") {
            continue;
        }
        let Ok(contents) = std::fs::read_to_string(&path) else {
            continue;
        };
        let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&contents) else {
            continue;
        };
        if manifest.get("type").and_then(|value| value.as_str()) == Some(resource_type) {
            return Some(entry.to_path_buf());
        }
    }
    None
}

async fn run_dsc_with_filter(
    filter: &str,
    options: &DscRunOptions,
) -> Result<pedantic_executor::dsc::DscOutput, DscError> {
    // The DscCommand enum's ResourceList variant has no filter field today; run the
    // underlying command directly with the extra positional argument to support filtering
    // without changing the shared enum's public shape for other callers.
    use tokio::io::AsyncWriteExt;
    use tokio::process::Command;

    let mut cmd = Command::new("dsc");
    cmd.args(["resource", "list", filter]);
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

    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(b"").await?;
    }

    let output = child.wait_with_output().await?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        return Err(DscError::Execution {
            status: output.status,
            stdout,
            stderr,
        });
    }

    Ok(pedantic_executor::dsc::DscOutput {
        status: output.status,
        stdout,
        stderr,
        json: None,
    })
}

#[tool_handler]
impl rmcp::ServerHandler for PedanticMcpServer {
    fn get_info(&self) -> ServerInfo {
        let _tool_router = &self.tool_router;
        ServerInfo::new(ServerCapabilities::builder().enable_tools().build()).with_instructions(
            "Pedantic MCP server: exposes real DSC v3 resource discovery (resource_list), \
             read (resource_get), compliance testing (resource_test), drift export \
             (resource_export), config export (config_export), and validation (config_validate) tools backed by the \
             actual `dsc` CLI binary on this host.",
        )
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .init();

    tracing::info!("Starting Pedantic MCP server (stdio transport)");

    let service = PedanticMcpServer::new()
        .serve(stdio())
        .await
        .inspect_err(|e| {
            tracing::error!("serving error: {:?}", e);
        })?;

    service.waiting().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::find_resource_manifest_dir_in_path;
    use std::ffi::OsString;
    use std::path::{Path, PathBuf};

    #[test]
    fn finds_matching_resource_manifest_dir_from_resource_path() {
        let root = unique_temp_dir("manifest-match");
        let resource_dir = root.join("SimpleDSC.PackageInstaller");
        let executable_dir = root.join("pwsh");
        std::fs::create_dir_all(&resource_dir).unwrap();
        std::fs::create_dir_all(&executable_dir).unwrap();
        std::fs::write(
            resource_dir.join("SimpleDSC.PackageInstaller.dsc.resource.json"),
            r#"{"type":"SimpleDSC/PackageInstaller"}"#,
        )
        .unwrap();

        let resource_path = join_paths([executable_dir.as_path(), resource_dir.as_path()]);
        let found =
            find_resource_manifest_dir_in_path("SimpleDSC/PackageInstaller", &resource_path)
                .unwrap();

        assert_eq!(found, resource_dir);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn ignores_non_matching_resource_manifests() {
        let root = unique_temp_dir("manifest-miss");
        let resource_dir = root.join("Other.Resource");
        std::fs::create_dir_all(&resource_dir).unwrap();
        std::fs::write(
            resource_dir.join("Other.Resource.dsc.resource.json"),
            r#"{"type":"Other/Resource"}"#,
        )
        .unwrap();

        let resource_path = join_paths([resource_dir.as_path()]);
        let found =
            find_resource_manifest_dir_in_path("SimpleDSC/PackageInstaller", &resource_path);

        assert!(found.is_none());
        std::fs::remove_dir_all(root).unwrap();
    }

    fn unique_temp_dir(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "pedantic-mcp-{name}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    fn join_paths<'a>(paths: impl IntoIterator<Item = &'a Path>) -> OsString {
        std::env::join_paths(paths).unwrap()
    }
}
