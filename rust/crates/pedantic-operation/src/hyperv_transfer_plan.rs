use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use thiserror::Error;

pub const HYPERV_TRANSFER_PLAN_SCHEMA_VERSION: &str = "pedantic.hyperv-transfer-plan.v1";

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum HostFailureCategory {
    Authentication,
    HostUnavailable,
    HyperVUnavailable,
    InvalidResponse,
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HostQueryFailure {
    pub host_name: String,
    pub category: HostFailureCategory,
    pub error: String,
    pub retryable: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVHardDrive {
    pub path: String,
    #[serde(default)]
    pub differencing_chain: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVVmInventory {
    pub name: String,
    pub vm_id: String,
    pub effective_mac_addresses: Vec<String>,
    pub hard_drives: Vec<HyperVHardDrive>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVHostInventory {
    pub host_name: String,
    pub virtual_machines: Vec<HyperVVmInventory>,
}

/// A bounded observation boundary. Implementations discover inventory only and
/// must not admit, approve, retry, remediate, or start a transfer.
pub trait HyperVInventoryProvider {
    fn query_host(&self, host_name: &str) -> Result<HyperVHostInventory, HostQueryFailure>;
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum TransferTransport {
    Bits,
    Filesystem,
    Scp,
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovedVmPair {
    pub source_host: String,
    pub source_vm_name: String,
    pub target_host: String,
    pub target_vm_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVTransferPlanRequest {
    pub request_id: String,
    pub profile_id: String,
    pub selected_transport: TransferTransport,
    pub approved_pairs: Vec<ApprovedVmPair>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlannedVm {
    pub host_name: String,
    pub name: String,
    pub vm_id: String,
    pub effective_mac_addresses: Vec<String>,
    pub hard_drives: Vec<HyperVHardDrive>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlannedTransferPair {
    pub pair_id: String,
    pub source: PlannedVm,
    pub target: PlannedVm,
    pub selected_transport: TransferTransport,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVTransferPlan {
    pub schema_version: String,
    pub plan_id: String,
    pub request_id: String,
    pub profile_id: String,
    pub selected_transport: TransferTransport,
    pub pairs: Vec<PlannedTransferPair>,
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum TransferPlanValidationError {
    DuplicatePair {
        source_host: String,
        source_vm_name: String,
        target_host: String,
        target_vm_name: String,
    },
    DuplicateVmName {
        host_name: String,
        vm_name: String,
    },
    MissingPairVm {
        host_name: String,
        vm_name: String,
    },
    MissingRequestIdentity,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HyperVTransferPlanResult {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub plan: Option<HyperVTransferPlan>,
    #[serde(default)]
    pub host_failures: Vec<HostQueryFailure>,
    #[serde(default)]
    pub validation_errors: Vec<TransferPlanValidationError>,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum HyperVTransferPlanError {
    #[error("unsupported Hyper-V transfer-plan schema version: {0}")]
    UnsupportedSchemaVersion(String),
    #[error("transfer-plan identifiers must not be empty")]
    MissingIdentifier,
    #[error("transfer plan must contain at least one pair")]
    EmptyPlan,
    #[error("transfer pairs must be in deterministic order")]
    UnstablePairOrder,
}

impl HyperVTransferPlan {
    pub fn validate(&self) -> Result<(), HyperVTransferPlanError> {
        if self.schema_version != HYPERV_TRANSFER_PLAN_SCHEMA_VERSION {
            return Err(HyperVTransferPlanError::UnsupportedSchemaVersion(
                self.schema_version.clone(),
            ));
        }
        if self.plan_id.is_empty() || self.request_id.is_empty() || self.profile_id.is_empty() {
            return Err(HyperVTransferPlanError::MissingIdentifier);
        }
        if self.pairs.is_empty() {
            return Err(HyperVTransferPlanError::EmptyPlan);
        }
        if self
            .pairs
            .windows(2)
            .any(|pair| pair[0].pair_id >= pair[1].pair_id)
        {
            return Err(HyperVTransferPlanError::UnstablePairOrder);
        }
        Ok(())
    }
}

pub fn create_hyperv_transfer_plan<P: HyperVInventoryProvider>(
    provider: &P,
    request: &HyperVTransferPlanRequest,
) -> HyperVTransferPlanResult {
    let mut validation_errors = BTreeSet::new();
    if request.request_id.is_empty() || request.profile_id.is_empty() {
        validation_errors.insert(TransferPlanValidationError::MissingRequestIdentity);
    }

    let mut approved_pairs = request.approved_pairs.clone();
    approved_pairs.sort();
    for pairs in approved_pairs.windows(2) {
        if pairs[0] == pairs[1] {
            validation_errors.insert(TransferPlanValidationError::DuplicatePair {
                source_host: pairs[0].source_host.clone(),
                source_vm_name: pairs[0].source_vm_name.clone(),
                target_host: pairs[0].target_host.clone(),
                target_vm_name: pairs[0].target_vm_name.clone(),
            });
        }
    }

    let host_names = approved_pairs
        .iter()
        .flat_map(|pair| [&pair.source_host, &pair.target_host])
        .cloned()
        .collect::<BTreeSet<_>>();
    let mut inventories = BTreeMap::new();
    let mut host_failures = Vec::new();
    for host_name in host_names {
        match provider.query_host(&host_name) {
            Ok(mut inventory) => {
                inventory.host_name = host_name.clone();
                inventory.virtual_machines.sort_by(|left, right| {
                    left.name
                        .cmp(&right.name)
                        .then_with(|| left.vm_id.cmp(&right.vm_id))
                });
                inventories.insert(host_name, inventory);
            }
            Err(mut failure) => {
                failure.host_name = host_name;
                host_failures.push(failure);
            }
        }
    }
    host_failures.sort();

    let mut pairs = Vec::new();
    for pair in approved_pairs {
        let source = select_vm(
            &inventories,
            &pair.source_host,
            &pair.source_vm_name,
            &mut validation_errors,
        );
        let target = select_vm(
            &inventories,
            &pair.target_host,
            &pair.target_vm_name,
            &mut validation_errors,
        );
        if let (Some(source), Some(target)) = (source, target) {
            pairs.push(PlannedTransferPair {
                pair_id: pair_id(&pair),
                source,
                target,
                selected_transport: request.selected_transport.clone(),
            });
        }
    }
    pairs.sort_by(|left, right| left.pair_id.cmp(&right.pair_id));

    let validation_errors = validation_errors.into_iter().collect::<Vec<_>>();
    let plan = (host_failures.is_empty() && validation_errors.is_empty()).then(|| {
        let plan_id = plan_id(request, &pairs);
        HyperVTransferPlan {
            schema_version: HYPERV_TRANSFER_PLAN_SCHEMA_VERSION.into(),
            plan_id,
            request_id: request.request_id.clone(),
            profile_id: request.profile_id.clone(),
            selected_transport: request.selected_transport.clone(),
            pairs,
        }
    });
    HyperVTransferPlanResult {
        plan,
        host_failures,
        validation_errors,
    }
}

fn select_vm(
    inventories: &BTreeMap<String, HyperVHostInventory>,
    host_name: &str,
    vm_name: &str,
    errors: &mut BTreeSet<TransferPlanValidationError>,
) -> Option<PlannedVm> {
    let inventory = inventories.get(host_name)?;
    let matches = inventory
        .virtual_machines
        .iter()
        .filter(|vm| vm.name == vm_name)
        .collect::<Vec<_>>();
    match matches.as_slice() {
        [] => {
            errors.insert(TransferPlanValidationError::MissingPairVm {
                host_name: host_name.into(),
                vm_name: vm_name.into(),
            });
            None
        }
        [vm] => Some(PlannedVm {
            host_name: host_name.into(),
            name: vm.name.clone(),
            vm_id: vm.vm_id.clone(),
            effective_mac_addresses: vm.effective_mac_addresses.clone(),
            hard_drives: vm.hard_drives.clone(),
        }),
        _ => {
            errors.insert(TransferPlanValidationError::DuplicateVmName {
                host_name: host_name.into(),
                vm_name: vm_name.into(),
            });
            None
        }
    }
}

fn pair_id(pair: &ApprovedVmPair) -> String {
    digest(pair)
}

fn plan_id(request: &HyperVTransferPlanRequest, pairs: &[PlannedTransferPair]) -> String {
    digest(&(request, pairs))
}

fn digest<T: Serialize>(value: &T) -> String {
    format!(
        "sha256:{:x}",
        Sha256::digest(serde_json::to_vec(value).expect("transfer plan inputs serialize"))
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use jsonschema::{Draft, JSONSchema};

    #[derive(Default)]
    struct InventoryProvider {
        inventories: BTreeMap<String, Result<HyperVHostInventory, HostQueryFailure>>,
    }

    impl HyperVInventoryProvider for InventoryProvider {
        fn query_host(&self, host_name: &str) -> Result<HyperVHostInventory, HostQueryFailure> {
            self.inventories
                .get(host_name)
                .expect("test host exists")
                .clone()
        }
    }

    fn vm(name: &str, id: &str) -> HyperVVmInventory {
        HyperVVmInventory {
            name: name.into(),
            vm_id: id.into(),
            effective_mac_addresses: vec![format!("00-15-5D-00-00-{id}")],
            hard_drives: vec![HyperVHardDrive {
                path: format!("D:\\VMs\\{name}\\disk.vhdx"),
                differencing_chain: vec![format!("D:\\VMs\\{name}\\base.vhdx")],
            }],
        }
    }

    fn provider() -> InventoryProvider {
        let mut inventories = BTreeMap::new();
        inventories.insert(
            "source-host".into(),
            Ok(HyperVHostInventory {
                host_name: "source-host".into(),
                virtual_machines: (1..=5)
                    .map(|number| vm(&format!("source-{number}"), &number.to_string()))
                    .collect(),
            }),
        );
        inventories.insert(
            "target-host".into(),
            Ok(HyperVHostInventory {
                host_name: "target-host".into(),
                virtual_machines: (1..=5)
                    .rev()
                    .map(|number| vm(&format!("target-{number}"), &number.to_string()))
                    .collect(),
            }),
        );
        InventoryProvider { inventories }
    }

    fn request() -> HyperVTransferPlanRequest {
        HyperVTransferPlanRequest {
            request_id: "five-pair-request".into(),
            profile_id: "default".into(),
            selected_transport: TransferTransport::Filesystem,
            approved_pairs: (1..=5)
                .rev()
                .map(|number| ApprovedVmPair {
                    source_host: "source-host".into(),
                    source_vm_name: format!("source-{number}"),
                    target_host: "target-host".into(),
                    target_vm_name: format!("target-{number}"),
                })
                .collect(),
        }
    }

    #[test]
    fn creates_a_stable_five_pair_plan_with_inventory_evidence() {
        let result = create_hyperv_transfer_plan(&provider(), &request());
        let plan = result.plan.expect("complete inventory creates a plan");
        assert!(result.host_failures.is_empty());
        assert!(result.validation_errors.is_empty());
        assert_eq!(plan.pairs.len(), 5);
        assert!(plan
            .pairs
            .windows(2)
            .all(|pair| pair[0].pair_id < pair[1].pair_id));
        assert_eq!(
            plan.pairs[0].source.hard_drives[0].differencing_chain.len(),
            1
        );
        assert_eq!(
            plan.pairs[0].selected_transport,
            TransferTransport::Filesystem
        );
        plan.validate().expect("plan validates");
    }

    #[test]
    fn five_pair_scenario_fixture_conforms_to_the_public_contract() {
        let schema = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/hyperv-transfer-plan-result.schema.json"
        )))
        .expect("schema parses");
        let fixture = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/hyperv-transfer-plan.five-pair.valid.json"
        )))
        .expect("fixture parses");
        let compiled = JSONSchema::options()
            .with_draft(Draft::Draft7)
            .compile(&schema)
            .expect("schema compiles");
        assert!(compiled.is_valid(&fixture));
    }

    #[test]
    fn same_inventory_produces_byte_stable_plan() {
        let first = create_hyperv_transfer_plan(&provider(), &request())
            .plan
            .expect("plan");
        let second = create_hyperv_transfer_plan(&provider(), &request())
            .plan
            .expect("plan");
        assert_eq!(first.plan_id, second.plan_id);
        assert_eq!(
            serde_json::to_vec(&first).expect("serialize plan"),
            serde_json::to_vec(&second).expect("serialize plan")
        );
    }

    #[test]
    fn rejects_duplicate_exact_vm_names() {
        let mut provider = provider();
        provider
            .inventories
            .get_mut("source-host")
            .expect("source inventory")
            .as_mut()
            .expect("successful source inventory")
            .virtual_machines
            .push(vm("source-1", "duplicate"));
        let result = create_hyperv_transfer_plan(&provider, &request());
        assert!(result.plan.is_none());
        assert!(result
            .validation_errors
            .contains(&TransferPlanValidationError::DuplicateVmName {
                host_name: "source-host".into(),
                vm_name: "source-1".into(),
            }));
    }

    #[test]
    fn reports_missing_pairs_and_unavailable_hosts_individually() {
        let mut provider = provider();
        provider.inventories.insert(
            "target-host".into(),
            Err(HostQueryFailure {
                host_name: "ignored-by-planner".into(),
                category: HostFailureCategory::HostUnavailable,
                error: "WinRM connection timed out".into(),
                retryable: true,
            }),
        );
        let result = create_hyperv_transfer_plan(&provider, &request());
        assert!(result.plan.is_none());
        assert_eq!(
            result.host_failures,
            vec![HostQueryFailure {
                host_name: "target-host".into(),
                category: HostFailureCategory::HostUnavailable,
                error: "WinRM connection timed out".into(),
                retryable: true,
            }]
        );
        assert!(result.validation_errors.is_empty());
    }

    #[test]
    fn reports_missing_pair_vms() {
        let mut provider = provider();
        provider
            .inventories
            .get_mut("target-host")
            .expect("target inventory")
            .as_mut()
            .expect("successful target inventory")
            .virtual_machines
            .retain(|vm| vm.name != "target-3");
        let result = create_hyperv_transfer_plan(&provider, &request());
        assert!(result.plan.is_none());
        assert!(result
            .validation_errors
            .contains(&TransferPlanValidationError::MissingPairVm {
                host_name: "target-host".into(),
                vm_name: "target-3".into(),
            }));
    }

    #[test]
    fn preserves_partial_discovery_failures_without_policy() {
        let mut provider = provider();
        provider.inventories.insert(
            "target-host".into(),
            Err(HostQueryFailure {
                host_name: "target-host".into(),
                category: HostFailureCategory::Authentication,
                error: "credential rejected".into(),
                retryable: false,
            }),
        );
        let result = create_hyperv_transfer_plan(&provider, &request());
        assert!(result.plan.is_none());
        assert_eq!(result.host_failures.len(), 1);
        assert!(!result.host_failures[0].retryable);
    }
}
