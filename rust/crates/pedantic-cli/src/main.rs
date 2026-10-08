use clap::{Parser, Subcommand};
use pedantic_core::export::{export_junit, export_sarif};
use pedantic_core::parser::parse_dsc_v3;
use pedantic_core::planner::plan_execution;
use pedantic_core::validator::validate_document;
use pedantic_service::LocalServiceClient;
use std::fs;

#[derive(Debug, Parser)]
#[command(name = "pedantic")]
#[command(about = "Pedantic DSC tooling", version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    Parse {
        file: String,
    },
    Validate {
        file: String,
    },
    Plan {
        file: String,
    },
    Export {
        #[command(subcommand)]
        kind: ExportKind,
    },
    Resources {
        #[command(subcommand)]
        kind: ResourceKind,
    },
    /// Check for updates and optionally install the latest version
    Update {
        /// Only check for updates without installing
        #[arg(long)]
        check: bool,
    },
    /// Query the profile-scoped Pedantic local service without opening its store.
    Service {
        /// Profile served by the local Pedantic service.
        #[arg(long, default_value = "default")]
        profile: String,
        #[command(subcommand)]
        kind: ServiceKind,
    },
}

#[derive(Debug, Subcommand)]
enum ExportKind {
    Junit { file: String },
    Sarif { file: String },
}

#[derive(Debug, Subcommand)]
enum ResourceKind {
    List,
}

#[derive(Debug, Subcommand)]
enum ServiceKind {
    /// Read the service health projection.
    Health,
    /// Read bounded, redacted Chronos evidence.
    Evidence,
    /// Submit a PX-governed remediation request for a recorded drift observation.
    RemediationRequest {
        #[arg(long)]
        request_id: String,
        #[arg(long)]
        revision_id: String,
        #[arg(long)]
        observation_id: String,
        #[arg(long)]
        actor_id: String,
        #[arg(long)]
        idempotency_key: String,
    },
    /// Record an explicit approval for a remediation request.
    RemediationApprove {
        #[arg(long)]
        approval_id: String,
        #[arg(long)]
        request_id: String,
        #[arg(long)]
        actor_id: String,
        #[arg(long)]
        approved: bool,
    },
    /// Issue a narrow local DSC-set authorization for a recorded approval.
    EffectAuthorize {
        #[arg(long)]
        approval_id: String,
        #[arg(long)]
        request_id: String,
        #[arg(long)]
        actor_id: String,
        #[arg(long)]
        approved: bool,
    },
    /// Execute an approved local DSC remediation using a configuration document.
    RemediationExecute {
        #[arg(long)]
        execution_id: String,
        #[arg(long)]
        authorization_id: String,
        #[arg(long)]
        idempotency_key: String,
        #[arg(long)]
        file: String,
    },
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();

    match cli.command {
        Commands::Parse { file } => {
            let doc = load_document(&file)?;
            let pretty = serde_json::to_string_pretty(&doc)?;
            println!("{}", pretty);
        }
        Commands::Validate { file } => {
            let doc = load_document(&file)?;
            let report = validate_document(&doc);
            if report.is_ok() {
                println!("OK");
            } else {
                for error in report.errors {
                    eprintln!("{}", error);
                }
                std::process::exit(1);
            }
        }
        Commands::Plan { file } => {
            let doc = load_document(&file)?;
            let plan = plan_execution(&doc)?;
            let pretty = serde_json::to_string_pretty(&plan)?;
            println!("{}", pretty);
        }
        Commands::Export { kind } => match kind {
            ExportKind::Junit { file } => {
                let doc = load_document(&file)?;
                let report = validate_document(&doc);
                let output = export_junit(&report, "pedantic");
                println!("{}", output);
            }
            ExportKind::Sarif { file } => {
                let doc = load_document(&file)?;
                let report = validate_document(&doc);
                let output = export_sarif(&report, "pedantic");
                println!("{}", output);
            }
        },
        Commands::Resources { kind } => match kind {
            ResourceKind::List => {
                println!("PSDesiredStateConfiguration/WindowsFeature");
            }
        },
        Commands::Update { check } => {
            run_update(check)?;
        }
        Commands::Service { profile, kind } => {
            let response = match kind {
                ServiceKind::Health => query_service_health(&profile).await?,
                ServiceKind::Evidence => query_service_evidence(&profile).await?,
                ServiceKind::RemediationRequest {
                    request_id,
                    revision_id,
                    observation_id,
                    actor_id,
                    idempotency_key,
                } => {
                    query_service(
                        &profile,
                        "remediation.request",
                        request_id.clone(),
                        serde_json::json!({
                            "requestId": request_id,
                            "revisionId": revision_id,
                            "observationId": observation_id,
                            "actorId": actor_id,
                            "idempotencyKey": idempotency_key,
                        }),
                    )
                    .await?
                }
                ServiceKind::RemediationApprove {
                    approval_id,
                    request_id,
                    actor_id,
                    approved,
                } => {
                    query_service(
                        &profile,
                        "approval.record",
                        approval_id.clone(),
                        serde_json::json!({
                            "approvalId": approval_id,
                            "requestId": request_id,
                            "actorId": actor_id,
                            "approved": approved,
                        }),
                    )
                    .await?
                }
                ServiceKind::EffectAuthorize {
                    approval_id,
                    request_id,
                    actor_id,
                    approved,
                } => {
                    query_service(
                        &profile,
                        "effect.authorize",
                        approval_id.clone(),
                        serde_json::json!({
                            "approvalId": approval_id,
                            "requestId": request_id,
                            "actorId": actor_id,
                            "approved": approved,
                        }),
                    )
                    .await?
                }
                ServiceKind::RemediationExecute {
                    execution_id,
                    authorization_id,
                    idempotency_key,
                    file,
                } => {
                    query_service(
                        &profile,
                        "remediation.execute",
                        execution_id.clone(),
                        serde_json::json!({
                            "executionId": execution_id,
                            "authorizationId": authorization_id,
                            "idempotencyKey": idempotency_key,
                            "document": fs::read_to_string(file)?,
                        }),
                    )
                    .await?
                }
            };
            if !response.ok {
                let error = response
                    .error
                    .map(|error| format!("{}: {}", error.code, error.message))
                    .unwrap_or_else(|| "local service rejected the request".into());
                return Err(std::io::Error::other(error).into());
            }
            println!("{}", serde_json::to_string_pretty(&response)?);
        }
    }

    Ok(())
}

fn service_client(profile: &str) -> Result<LocalServiceClient, Box<dyn std::error::Error>> {
    let token = std::env::var("PEDANTIC_LOCAL_TOKEN")?;
    Ok(LocalServiceClient::for_profile(profile, &token)?)
}

async fn query_service_health(
    profile: &str,
) -> Result<pedantic_service::LocalServiceResponse, Box<dyn std::error::Error>> {
    service_client(profile)?.health().await.map_err(Into::into)
}

async fn query_service_evidence(
    profile: &str,
) -> Result<pedantic_service::LocalServiceResponse, Box<dyn std::error::Error>> {
    service_client(profile)?
        .list_evidence()
        .await
        .map_err(Into::into)
}

async fn query_service(
    profile: &str,
    method: &str,
    id: String,
    params: serde_json::Value,
) -> Result<pedantic_service::LocalServiceResponse, Box<dyn std::error::Error>> {
    service_client(profile)?
        .call(id, method, params)
        .await
        .map_err(Into::into)
}

fn run_update(check_only: bool) -> Result<(), Box<dyn std::error::Error>> {
    let current = self_update::cargo_crate_version!();
    eprintln!("Current version: v{current}");

    let updater = self_update::backends::github::Update::configure()
        .repo_owner("plures")
        .repo_name("pedantic")
        .bin_name("pedantic")
        .show_download_progress(true)
        .current_version(current)
        .build()?;

    let latest = updater.get_latest_release()?;
    let latest_ver = latest.version.trim_start_matches('v');
    eprintln!("Latest version:  v{latest_ver}");

    if latest_ver == current {
        eprintln!("Already up to date.");
        return Ok(());
    }

    if check_only {
        eprintln!("Update available: v{current} -> v{latest_ver}");
        eprintln!("Run `pedantic update` to install.");
        return Ok(());
    }

    eprintln!("Updating to v{latest_ver}...");
    let status = updater.update()?;
    eprintln!("Updated to v{}.", status.version());
    Ok(())
}

fn load_document(
    path: &str,
) -> Result<pedantic_core::model::DscDocument, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let doc = parse_dsc_v3(&content)?;
    Ok(doc)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_read_only_service_evidence_command() {
        let cli = Cli::try_parse_from(["pedantic", "service", "--profile", "Default", "evidence"])
            .expect("parse service evidence command");

        match cli.command {
            Commands::Service {
                profile,
                kind: ServiceKind::Evidence,
            } => assert_eq!(profile, "Default"),
            _ => panic!("expected service evidence command"),
        }
    }

    #[test]
    fn parses_the_guarded_remediation_execution_command() {
        let cli = Cli::try_parse_from([
            "pedantic",
            "service",
            "remediation-execute",
            "--execution-id",
            "execution-1",
            "--authorization-id",
            "approval-1",
            "--idempotency-key",
            "operation-1",
            "--file",
            "configuration.yaml",
        ])
        .expect("parse guarded remediation command");

        match cli.command {
            Commands::Service {
                profile,
                kind:
                    ServiceKind::RemediationExecute {
                        execution_id,
                        authorization_id,
                        idempotency_key,
                        file,
                    },
            } => {
                assert_eq!(profile, "default");
                assert_eq!(execution_id, "execution-1");
                assert_eq!(authorization_id, "approval-1");
                assert_eq!(idempotency_key, "operation-1");
                assert_eq!(file, "configuration.yaml");
            }
            _ => panic!("expected guarded remediation execution command"),
        }
    }

    #[test]
    fn parses_the_effect_authorization_command() {
        let cli = Cli::try_parse_from([
            "pedantic",
            "service",
            "effect-authorize",
            "--approval-id",
            "approval-1",
            "--request-id",
            "request-1",
            "--actor-id",
            "reviewer@example.test",
            "--approved",
        ])
        .expect("parse effect authorization command");

        assert!(matches!(
            cli.command,
            Commands::Service {
                kind: ServiceKind::EffectAuthorize { .. },
                ..
            }
        ));
    }
}
