use crate::dsc::{run_dsc, DscCommand, DscError, DscInput, DscOutput, DscRunOptions};
use crate::transport::Transport;
use async_trait::async_trait;

#[derive(Debug, Clone)]
#[derive(Default)]
pub struct LocalTransport {
    pub options: DscRunOptions,
}


#[async_trait]
impl Transport for LocalTransport {
    async fn run_dsc(&self, command: DscCommand, input: DscInput) -> Result<DscOutput, DscError> {
        run_dsc(command, input, &self.options).await
    }
}
