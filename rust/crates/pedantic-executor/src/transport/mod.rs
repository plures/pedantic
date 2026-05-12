mod local;
mod ssh;

pub use local::*;
pub use ssh::*;

use crate::dsc::{DscCommand, DscError, DscOutput};
use async_trait::async_trait;

#[async_trait]
pub trait Transport: Send + Sync {
    async fn run_dsc(&self, command: DscCommand, config_path: &str) -> Result<DscOutput, DscError>;
}
