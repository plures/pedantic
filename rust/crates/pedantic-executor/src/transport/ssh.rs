use crate::dsc::{DscCommand, DscError, DscOutput};
use crate::transport::Transport;
use async_trait::async_trait;

#[derive(Debug, Clone)]
pub struct SshTransport {
    pub host: String,
}

#[async_trait]
impl Transport for SshTransport {
    async fn run_dsc(&self, _command: DscCommand, _config_path: &str) -> Result<DscOutput, DscError> {
        Err(std::io::Error::other("SSH transport not implemented").into())
    }
}
