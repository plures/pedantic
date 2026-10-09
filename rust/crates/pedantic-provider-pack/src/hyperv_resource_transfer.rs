use pedantic_capability::CapabilityError;
use serde::{Deserialize, Serialize};

/// Explicit, approved resource mapping. Differencing-chain entries are ordered
/// from the child disk's immediate parent to the base disk.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVResource {
    pub source_path: String,
    pub destination_path: String,
    pub expected_size: u64,
    pub expected_sha256: String,
    #[serde(default)]
    pub destination_differencing_chain: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVMacConfiguration {
    pub adapter_name: String,
    pub effective_mac_address: String,
    pub freeze_dynamic: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVResourceTransferRequest {
    pub destination_vm_name: String,
    pub resources: Vec<HyperVResource>,
    #[serde(default)]
    pub mac_configurations: Vec<HyperVMacConfiguration>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVPreflightObservation {
    pub ready: bool,
    #[serde(default)]
    pub diagnostics: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVCopyObservation {
    pub source_path: String,
    pub destination_path: String,
    pub source_size: u64,
    pub destination_size: u64,
    pub source_sha256: String,
    pub destination_sha256: String,
    pub destination_created: bool,
    pub complete: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVMacObservation {
    pub adapter_name: String,
    pub before_mac_address: String,
    pub after_mac_address: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVVerificationObservation {
    pub verified: bool,
    #[serde(default)]
    pub diagnostics: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVRollbackObservation {
    pub completed: bool,
    pub recovery_action: String,
    #[serde(default)]
    pub diagnostics: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum HyperVResourceTransferState {
    Verified,
    Failed,
    NeedsReview,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVResourceTransferObservation {
    pub state: HyperVResourceTransferState,
    pub preflight: HyperVPreflightObservation,
    #[serde(default)]
    pub diagnostics: Vec<String>,
    #[serde(default)]
    pub copies: Vec<HyperVCopyObservation>,
    #[serde(default)]
    pub mac_configurations: Vec<HyperVMacObservation>,
    pub verification: Option<HyperVVerificationObservation>,
    pub rollback: Option<HyperVRollbackObservation>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct HyperVAppliedChanges {
    pub destination_vm_name: String,
    pub copied_destination_paths: Vec<String>,
    pub changed_mac_configurations: Vec<HyperVMacObservation>,
}

/// Bounded Hyper-V effects. This boundary only performs the resource and MAC
/// operations explicitly supplied in a durable plan; PX remains responsible
/// for deciding which request to authorize.
pub trait HyperVResourceTransferBackend: Send + Sync {
    fn preflight(
        &self,
        request: &HyperVResourceTransferRequest,
    ) -> Result<HyperVPreflightObservation, CapabilityError>;
    fn copy_resource(
        &self,
        resource: &HyperVResource,
    ) -> Result<HyperVCopyObservation, HyperVCopyFailure>;
    fn configure_mac(
        &self,
        destination_vm_name: &str,
        configuration: &HyperVMacConfiguration,
    ) -> Result<HyperVMacObservation, CapabilityError>;
    fn verify(
        &self,
        request: &HyperVResourceTransferRequest,
    ) -> Result<HyperVVerificationObservation, CapabilityError>;
    fn rollback(
        &self,
        changes: &HyperVAppliedChanges,
    ) -> Result<HyperVRollbackObservation, CapabilityError>;

    fn available(&self) -> Result<(), CapabilityError> {
        Ok(())
    }
}

pub struct HyperVCopyFailure {
    pub error: CapabilityError,
    pub destination_created: bool,
}

pub struct HyperVResourceTransfer<B> {
    backend: B,
}

impl<B: HyperVResourceTransferBackend> HyperVResourceTransfer<B> {
    pub fn new(backend: B) -> Self {
        Self { backend }
    }

    pub fn execute(
        &self,
        request: &HyperVResourceTransferRequest,
    ) -> Result<HyperVResourceTransferObservation, CapabilityError> {
        let preflight = self.backend.preflight(request)?;
        if !preflight.ready {
            return Ok(HyperVResourceTransferObservation {
                state: HyperVResourceTransferState::Failed,
                preflight,
                diagnostics: Vec::new(),
                copies: Vec::new(),
                mac_configurations: Vec::new(),
                verification: None,
                rollback: None,
            });
        }

        let mut changes = HyperVAppliedChanges {
            destination_vm_name: request.destination_vm_name.clone(),
            ..HyperVAppliedChanges::default()
        };
        let mut copies = Vec::new();
        let mut mac_configurations = Vec::new();
        for resource in &request.resources {
            let copy = match self.backend.copy_resource(resource) {
                Ok(copy) => copy,
                Err(failure) => {
                    if failure.destination_created {
                        changes
                            .copied_destination_paths
                            .push(resource.destination_path.clone());
                    }
                    return self.rollback_error(
                        preflight,
                        copies,
                        mac_configurations,
                        changes,
                        failure.error,
                    );
                }
            };
            let valid_copy = copy.complete
                && copy.source_path == resource.source_path
                && copy.destination_path == resource.destination_path
                && copy.source_size == resource.expected_size
                && copy.destination_size == resource.expected_size
                && copy.source_sha256 == resource.expected_sha256
                && copy.destination_sha256 == resource.expected_sha256;
            copies.push(copy);
            if copies.last().is_some_and(|copy| copy.destination_created) {
                changes
                    .copied_destination_paths
                    .push(resource.destination_path.clone());
            }
            if !valid_copy {
                return self.rollback_failure(preflight, copies, mac_configurations, changes, None);
            }
        }
        for configuration in request
            .mac_configurations
            .iter()
            .filter(|configuration| configuration.freeze_dynamic)
        {
            let mac = match self
                .backend
                .configure_mac(&request.destination_vm_name, configuration)
            {
                Ok(mac) => mac,
                Err(error) => {
                    return self.rollback_error(
                        preflight,
                        copies,
                        mac_configurations,
                        changes,
                        error,
                    );
                }
            };
            let valid_mac = mac.adapter_name == configuration.adapter_name
                && mac.after_mac_address == configuration.effective_mac_address;
            changes.changed_mac_configurations.push(mac.clone());
            mac_configurations.push(mac);
            if !valid_mac {
                return self.rollback_failure(preflight, copies, mac_configurations, changes, None);
            }
        }
        let verification = match self.backend.verify(request) {
            Ok(verification) => verification,
            Err(error) => {
                return self.rollback_error(preflight, copies, mac_configurations, changes, error);
            }
        };
        if verification.verified {
            Ok(HyperVResourceTransferObservation {
                state: HyperVResourceTransferState::Verified,
                preflight,
                diagnostics: Vec::new(),
                copies,
                mac_configurations,
                verification: Some(verification),
                rollback: None,
            })
        } else {
            self.rollback_failure(
                preflight,
                copies,
                mac_configurations,
                changes,
                Some(verification),
            )
        }
    }

    fn rollback_failure(
        &self,
        preflight: HyperVPreflightObservation,
        copies: Vec<HyperVCopyObservation>,
        mac_configurations: Vec<HyperVMacObservation>,
        changes: HyperVAppliedChanges,
        verification: Option<HyperVVerificationObservation>,
    ) -> Result<HyperVResourceTransferObservation, CapabilityError> {
        let rollback = self.backend.rollback(&changes).unwrap_or_else(|error| {
            HyperVRollbackObservation {
                completed: false,
                recovery_action: "operator-review-required: inspect destination disks and restore adapter MAC addresses".into(),
                diagnostics: vec![error.to_string()],
            }
        });
        Ok(HyperVResourceTransferObservation {
            state: if rollback.completed {
                HyperVResourceTransferState::Failed
            } else {
                HyperVResourceTransferState::NeedsReview
            },
            preflight,
            diagnostics: Vec::new(),
            copies,
            mac_configurations,
            verification,
            rollback: Some(rollback),
        })
    }

    fn rollback_error(
        &self,
        preflight: HyperVPreflightObservation,
        copies: Vec<HyperVCopyObservation>,
        mac_configurations: Vec<HyperVMacObservation>,
        changes: HyperVAppliedChanges,
        error: CapabilityError,
    ) -> Result<HyperVResourceTransferObservation, CapabilityError> {
        let mut observation =
            self.rollback_failure(preflight, copies, mac_configurations, changes, None)?;
        observation.diagnostics.push(error.to_string());
        Ok(observation)
    }
}

impl<B: HyperVResourceTransferBackend> super::ProviderBackend for HyperVResourceTransfer<B> {
    fn ready(&self) -> Result<(), CapabilityError> {
        self.backend.available()
    }

    fn execute(&self, input: &serde_json::Value) -> Result<serde_json::Value, CapabilityError> {
        let request = serde_json::from_value(input.clone()).map_err(|_| {
            CapabilityError::InvalidInput("Hyper-V transfer request is invalid".into())
        })?;
        serde_json::to_value(self.execute(&request)?).map_err(|_| {
            CapabilityError::Execution("Hyper-V transfer result could not be serialized".into())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[derive(Clone)]
    struct Backend {
        preflight_ready: bool,
        copy_complete: bool,
        copy_destination_created: bool,
        copy_error: bool,
        verification_valid: bool,
        rollback_complete: bool,
        rollback_error: bool,
        changes: std::sync::Arc<Mutex<Vec<HyperVAppliedChanges>>>,
    }

    impl HyperVResourceTransferBackend for Backend {
        fn preflight(
            &self,
            _request: &HyperVResourceTransferRequest,
        ) -> Result<HyperVPreflightObservation, CapabilityError> {
            Ok(HyperVPreflightObservation {
                ready: self.preflight_ready,
                diagnostics: vec!["destination-space-checked".into()],
            })
        }

        fn copy_resource(
            &self,
            resource: &HyperVResource,
        ) -> Result<HyperVCopyObservation, HyperVCopyFailure> {
            if self.copy_error {
                return Err(HyperVCopyFailure {
                    error: CapabilityError::Execution("copy failed".into()),
                    destination_created: true,
                });
            }
            Ok(HyperVCopyObservation {
                source_path: resource.source_path.clone(),
                destination_path: resource.destination_path.clone(),
                source_size: resource.expected_size,
                destination_size: resource.expected_size,
                source_sha256: resource.expected_sha256.clone(),
                destination_sha256: resource.expected_sha256.clone(),
                destination_created: self.copy_destination_created,
                complete: self.copy_complete,
            })
        }

        fn configure_mac(
            &self,
            _destination_vm_name: &str,
            configuration: &HyperVMacConfiguration,
        ) -> Result<HyperVMacObservation, CapabilityError> {
            Ok(HyperVMacObservation {
                adapter_name: configuration.adapter_name.clone(),
                before_mac_address: "00155D000000".into(),
                after_mac_address: configuration.effective_mac_address.clone(),
            })
        }

        fn verify(
            &self,
            _request: &HyperVResourceTransferRequest,
        ) -> Result<HyperVVerificationObservation, CapabilityError> {
            Ok(HyperVVerificationObservation {
                verified: self.verification_valid,
                diagnostics: vec!["attachments-and-differencing-chain-checked".into()],
            })
        }

        fn rollback(
            &self,
            changes: &HyperVAppliedChanges,
        ) -> Result<HyperVRollbackObservation, CapabilityError> {
            self.changes.lock().unwrap().push(changes.clone());
            if self.rollback_error {
                return Err(CapabilityError::Execution("rollback failed".into()));
            }
            Ok(HyperVRollbackObservation {
                completed: self.rollback_complete,
                recovery_action: "remove-copied-disks-and-restore-macs".into(),
                diagnostics: vec!["destination-only-rollback".into()],
            })
        }
    }

    fn request(dynamic: bool) -> HyperVResourceTransferRequest {
        HyperVResourceTransferRequest {
            destination_vm_name: "destination".into(),
            resources: vec![
                HyperVResource {
                    source_path: "source/base.vhdx".into(),
                    destination_path: "destination/base.vhdx".into(),
                    expected_size: 10,
                    expected_sha256: "sha256:base".into(),
                    destination_differencing_chain: vec![],
                },
                HyperVResource {
                    source_path: "source/child.avhdx".into(),
                    destination_path: "destination/child.avhdx".into(),
                    expected_size: 20,
                    expected_sha256: "sha256:child".into(),
                    destination_differencing_chain: vec!["destination/base.vhdx".into()],
                },
            ],
            mac_configurations: vec![HyperVMacConfiguration {
                adapter_name: "Network Adapter".into(),
                effective_mac_address: "00155D000001".into(),
                freeze_dynamic: dynamic,
            }],
        }
    }

    fn backend(
        preflight_ready: bool,
        copy_complete: bool,
        verification_valid: bool,
        rollback_complete: bool,
    ) -> Backend {
        Backend {
            preflight_ready,
            copy_complete,
            copy_destination_created: true,
            copy_error: false,
            verification_valid,
            rollback_complete,
            rollback_error: false,
            changes: Default::default(),
        }
    }

    #[test]
    fn verifies_fixed_mac_single_disk_without_mutating_mac_configuration() {
        let backend = backend(true, true, true, true);
        let adapter = HyperVResourceTransfer::new(backend);
        let mut request = request(false);
        request.resources.truncate(1);

        let observation = adapter.execute(&request).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Verified);
        assert_eq!(observation.copies.len(), 1);
        assert!(observation.mac_configurations.is_empty());
        assert!(observation.rollback.is_none());
    }

    #[test]
    fn verifies_dynamic_mac_and_differencing_chain_with_before_after_evidence() {
        let backend = backend(true, true, true, true);
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Verified);
        assert_eq!(observation.copies.len(), 2);
        assert_eq!(
            observation.mac_configurations[0].before_mac_address,
            "00155D000000"
        );
        assert_eq!(
            observation.mac_configurations[0].after_mac_address,
            "00155D000001"
        );
    }

    #[test]
    fn preflight_failures_for_missing_paths_or_space_do_not_mutate_destination() {
        let backend = backend(false, true, true, true);
        let changes = backend.changes.clone();
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Failed);
        assert!(observation.copies.is_empty());
        assert!(observation.rollback.is_none());
        assert!(changes.lock().unwrap().is_empty());
    }

    #[test]
    fn partial_copy_is_rolled_back_with_destination_only_evidence() {
        let backend = backend(true, false, true, true);
        let changes = backend.changes.clone();
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Failed);
        assert_eq!(
            observation.rollback.unwrap().recovery_action,
            "remove-copied-disks-and-restore-macs"
        );
        assert_eq!(
            changes.lock().unwrap()[0].copied_destination_paths,
            vec!["destination/base.vhdx"]
        );
        assert_eq!(
            changes.lock().unwrap()[0].destination_vm_name,
            "destination"
        );
    }

    #[test]
    fn copy_error_after_destination_creation_is_rolled_back() {
        let mut backend = backend(true, true, true, true);
        backend.copy_error = true;
        let changes = backend.changes.clone();
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Failed);
        assert_eq!(
            changes.lock().unwrap()[0].copied_destination_paths,
            vec!["destination/base.vhdx"]
        );
    }

    #[test]
    fn incomplete_copy_without_creation_evidence_is_not_removed() {
        let mut backend = backend(true, false, true, true);
        backend.copy_destination_created = false;
        let changes = backend.changes.clone();
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Failed);
        assert!(
            changes.lock().unwrap()[0]
                .copied_destination_paths
                .is_empty()
        );
    }

    #[test]
    fn verification_mismatch_rolls_back_copied_resources_and_dynamic_mac() {
        let backend = backend(true, true, false, true);
        let changes = backend.changes.clone();
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::Failed);
        assert_eq!(
            observation.verification.as_ref().unwrap().diagnostics,
            vec!["attachments-and-differencing-chain-checked"]
        );
        let rollback = changes.lock().unwrap();
        assert_eq!(rollback[0].copied_destination_paths.len(), 2);
        assert_eq!(
            rollback[0].changed_mac_configurations[0].adapter_name,
            "Network Adapter"
        );
        assert_eq!(
            rollback[0].changed_mac_configurations[0].before_mac_address,
            "00155D000000"
        );
    }

    #[test]
    fn incomplete_rollback_requires_review_instead_of_success() {
        let backend = backend(true, true, false, false);
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::NeedsReview);
        assert!(!observation.rollback.unwrap().completed);
    }

    #[test]
    fn rollback_backend_error_returns_needs_review_with_recovery_instructions() {
        let mut backend = backend(true, true, false, true);
        backend.rollback_error = true;
        let adapter = HyperVResourceTransfer::new(backend);

        let observation = adapter.execute(&request(true)).unwrap();

        assert_eq!(observation.state, HyperVResourceTransferState::NeedsReview);
        let rollback = observation.rollback.unwrap();
        assert!(!rollback.completed);
        assert!(
            rollback
                .recovery_action
                .contains("operator-review-required")
        );
        assert_eq!(
            rollback.diagnostics,
            vec!["bounded adapter failed: rollback failed"]
        );
    }
}
