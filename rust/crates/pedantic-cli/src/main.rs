use clap::{Parser, Subcommand};
use pedantic_core::export::{export_junit, export_sarif};
use pedantic_core::parser::parse_dsc_v3;
use pedantic_core::planner::plan_execution;
use pedantic_core::validator::validate_document;
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
    Parse { file: String },
    Validate { file: String },
    Plan { file: String },
    Export { #[command(subcommand)] kind: ExportKind },
    Resources { #[command(subcommand)] kind: ResourceKind },
    /// Check for updates and optionally install the latest version
    Update {
        /// Only check for updates without installing
        #[arg(long)]
        check: bool,
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

fn main() -> Result<(), Box<dyn std::error::Error>> {
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
    }

    Ok(())
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

fn load_document(path: &str) -> Result<pedantic_core::model::DscDocument, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let doc = parse_dsc_v3(&content)?;
    Ok(doc)
}
