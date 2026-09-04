use pedantic_service::{pipe_name_for_profile, run, validate_token};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    let profile_id = read_profile_id(std::env::args().skip(1))?;
    let token = std::env::var("PEDANTIC_LOCAL_TOKEN")
        .map_err(|_| "PEDANTIC_LOCAL_TOKEN is required to start the local Pedantic service")?;
    validate_token(&token)?;
    let pipe_name = pipe_name_for_profile(&profile_id)?;
    tracing::info!(pipe = %pipe_name, profile = %profile_id, "starting pedantic service");
    run(&pipe_name, &profile_id, &token, env!("CARGO_PKG_VERSION")).await?;
    Ok(())
}

fn read_profile_id(mut args: impl Iterator<Item = String>) -> Result<String, &'static str> {
    while let Some(arg) = args.next() {
        if arg == "--profile" {
            return args.next().ok_or("--profile requires a profile identifier");
        }
    }
    Ok("default".into())
}
