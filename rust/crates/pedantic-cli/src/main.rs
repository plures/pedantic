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
    }

    Ok(())
}

fn load_document(path: &str) -> Result<pedantic_core::model::DscDocument, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let doc = parse_dsc_v3(&content)?;
    Ok(doc)
}
