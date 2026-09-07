pub mod dsc;
pub mod inventory;
pub mod transport;

use crate::dsc::{DscCommand, DscError, DscInput, parse_test_results};
use crate::transport::Transport;
use pedantic_core::{ModelResourceStatus, ResourceResult, RunStatus};

pub struct DscRunner<T: Transport> {
    transport: T,
}

impl<T: Transport> DscRunner<T> {
    pub fn new(transport: T) -> Self {
        Self { transport }
    }

    pub async fn test(
        &self,
        doc: &pedantic_core::DscDocument,
    ) -> Result<Vec<ResourceResult>, DscError> {
        let yaml = serde_yaml::to_string(doc)?;
        let output = self
            .transport
            .run_dsc(DscCommand::ConfigTest, DscInput::Stdin(yaml))
            .await?;
        let results = parse_test_results(&output)?;
        Ok(results
            .into_iter()
            .map(|result| ResourceResult {
                name: result.resource_name,
                status: if result.in_desired_state {
                    ModelResourceStatus::Compliant
                } else {
                    ModelResourceStatus::Drifted
                },
                message: None,
            })
            .collect())
    }

    pub async fn set(
        &self,
        doc: &pedantic_core::DscDocument,
    ) -> Result<Vec<ResourceResult>, DscError> {
        let yaml = serde_yaml::to_string(doc)?;
        let output = self
            .transport
            .run_dsc(DscCommand::ConfigSet, DscInput::Stdin(yaml))
            .await?;
        let results = parse_test_results(&output)?;
        Ok(results
            .into_iter()
            .map(|result| ResourceResult {
                name: result.resource_name,
                status: if result.in_desired_state {
                    ModelResourceStatus::Compliant
                } else {
                    ModelResourceStatus::Drifted
                },
                message: None,
            })
            .collect())
    }

    pub async fn validate(&self, doc: &pedantic_core::DscDocument) -> Result<RunStatus, DscError> {
        let yaml = serde_yaml::to_string(doc)?;
        self.transport
            .run_dsc(DscCommand::ConfigValidate, DscInput::Stdin(yaml))
            .await?;
        Ok(RunStatus::Completed)
    }
}
