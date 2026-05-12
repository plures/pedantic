use crate::dsc::{run_dsc, DscCommand, DscError, DscOutput};
use crate::transport::Transport;
use async_trait::async_trait;

#[derive(Debug, Default, Clone)]
pub struct LocalTransport;

#[async_trait]
impl Transport for LocalTransport {
    async fn run_dsc(&self, command: DscCommand, config_path: &str) -> Result<DscOutput, DscError> {
        run_dsc(command, config_path).await
    }
}
