use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use jsonschema::{Draft, JSONSchema};
use pedantic_agent::{AgentEnrollment, AgentObservationBatch};
use pedantic_executor::dsc::{
    DscCommand, DscError, DscInput, DscRunOptions, DscTestResult, parse_test_results, run_dsc,
};
use pedantic_executor::inventory::{HostRecord, parse_hosts};
use pedantic_operation::{
    EffectAuthorization, FederatedTransferRegistry, RetryClass, RiskClass,
    Signature as GrantSignature, TRANSFER_REGISTRY_STORAGE_SCHEMA_VERSION, TransferEvent,
    TransferIngestResult, TransferQuery, TransferReport,
};
use pluresdb::{CrdtStore, SledStorage, StorageEngine};
use pluresdb_chronos::{ChronosAction, ChronosEntry, ChronosTimeline};
use px_ast::{ConstraintDecl, Statement};
use px_eval::{ConstraintOutcome, FunctionRegistry, PureFunctionRegistry};
use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    future::Future,
    io::{self, Read, Write},
    path::{Path, PathBuf},
    sync::{Arc, OnceLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
#[cfg(windows)]
use windows_sys::Win32::{
    Foundation::LocalFree,
    Security::{
        Authorization::{ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1},
        SECURITY_ATTRIBUTES,
    },
};

pub const MAX_FRAME_BYTES: usize = 64 * 1024;
pub const MAX_EVIDENCE_RESULTS: usize = 100;
const SERVICE_ACTOR: &str = "pedantic-service";
const MAX_REMEDIATION_OBSERVATION_AGE: Duration = Duration::from_secs(5 * 60);
const CONFIGURATION_LIFECYCLE_SOURCE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../praxis/procedures/pedantic-configuration-lifecycle.px"
));
const EFFECT_AUTHORIZATION_SOURCE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../praxis/procedures/pedantic-effect-authorization.px"
));
const EFFECT_AUTHORIZATION_SCHEMA: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../contracts/v1/effect-authorization.schema.json"
));
const EFFECT_AUTHORIZATION_SCHEMA_VERSION: &str = "pedantic.effect-authorization.v1";
const EFFECT_AUTHORIZATION_LIFETIME: Duration = Duration::from_secs(5 * 60);
static CONFIGURATION_CONSTRAINTS: OnceLock<Result<Vec<ConstraintDecl>, String>> = OnceLock::new();
static EFFECT_AUTHORIZATION_CONSTRAINTS: OnceLock<Result<Vec<ConstraintDecl>, String>> =
    OnceLock::new();

/// A bounded, redacted projection of a Chronos entry for local clients.
///
/// The projection deliberately excludes data hashes, store keys, causal links,
/// rationales, constraint details, and operation payloads.
#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct EvidenceSummary {
    #[serde(rename = "eventId")]
    pub event_id: String,
    pub timestamp: u64,
    pub actor: String,
    pub action: String,
    pub level: String,
}

impl From<ChronosEntry> for EvidenceSummary {
    fn from(entry: ChronosEntry) -> Self {
        Self {
            event_id: entry.id,
            timestamp: entry.timestamp,
            actor: entry.actor,
            action: entry.action.to_string(),
            level: entry.level.to_string(),
        }
    }
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct EvidencePage {
    pub entries: Vec<EvidenceSummary>,
    pub truncated: bool,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentSyncResult {
    pub acknowledged_sequence: u64,
    pub replay_from_sequence: Option<u64>,
    pub accepted_observations: usize,
}

#[derive(Debug, Deserialize)]
pub struct ConfigurationAdmissionRequest {
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    #[serde(rename = "sourceDigest")]
    pub source_digest: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct ConfigurationAdmission {
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct ConfigurationValidationRequest {
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    pub document: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct ConfigurationValidation {
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct InventoryObservationRequest {
    #[serde(rename = "observationId")]
    pub observation_id: String,
    #[serde(rename = "sourceDigest")]
    pub source_digest: String,
    pub document: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct InventoryObservation {
    #[serde(rename = "observationId")]
    pub observation_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    #[serde(rename = "hostCount")]
    pub host_count: usize,
    pub hosts: Vec<HostRecord>,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct ComplianceRequest {
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "revisionId")]
    pub revision_id: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct ComplianceDecision {
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct ComplianceObservationRequest {
    #[serde(rename = "observationId")]
    pub observation_id: String,
    #[serde(rename = "requestId")]
    pub request_id: String,
    pub document: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct ComplianceObservation {
    #[serde(rename = "observationId")]
    pub observation_id: String,
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    #[serde(rename = "resourceCount")]
    pub resource_count: usize,
    #[serde(rename = "compliantResourceCount")]
    pub compliant_resource_count: usize,
    #[serde(rename = "driftedResourceCount")]
    pub drifted_resource_count: usize,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct RemediationRequest {
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    #[serde(rename = "observationId")]
    pub observation_id: String,
    #[serde(rename = "actorId")]
    pub actor_id: String,
    #[serde(rename = "idempotencyKey")]
    pub idempotency_key: String,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct RemediationDecision {
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    #[serde(rename = "observationId")]
    pub observation_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct RemediationApprovalRequest {
    #[serde(rename = "approvalId")]
    pub approval_id: String,
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "actorId")]
    pub actor_id: String,
    pub approved: bool,
    #[serde(skip)]
    authorize: bool,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct RemediationApproval {
    #[serde(rename = "approvalId")]
    pub approval_id: String,
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "authorizationId")]
    pub authorization_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authorization: Option<EffectAuthorization>,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct RemediationExecutionRequest {
    #[serde(rename = "executionId")]
    pub execution_id: String,
    #[serde(rename = "authorizationId")]
    pub authorization_id: String,
    #[serde(rename = "idempotencyKey")]
    pub idempotency_key: String,
    pub document: String,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct RemediationExecution {
    #[serde(rename = "executionId")]
    pub execution_id: String,
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "revisionId")]
    pub revision_id: String,
    pub decision: String,
    #[serde(rename = "constraintId")]
    pub constraint_id: String,
    #[serde(rename = "resourceCount")]
    pub resource_count: Option<usize>,
    #[serde(rename = "compliantResourceCount")]
    pub compliant_resource_count: Option<usize>,
    #[serde(rename = "driftedResourceCount")]
    pub drifted_resource_count: Option<usize>,
    pub reason: String,
}

/// The local service is the sole owner of a profile's embedded PluresDB store.
///
/// It owns authenticated transport, profile-local persistence, and Chronos
/// evidence. PX Lang evaluates the configuration-admission constraint; this
/// host does not reproduce that policy imperatively.
pub struct ServiceFoundation {
    profile_id: String,
    timeline: ChronosTimeline,
    _store: Arc<CrdtStore>,
    revision_lock: tokio::sync::Mutex<()>,
    transfer_registry: tokio::sync::Mutex<FederatedTransferRegistry>,
    authorization_signing_key: SigningKey,
}

impl ServiceFoundation {
    pub fn open(profile_id: &str, version: &str) -> Result<Self, ServiceErrorKind> {
        Self::open_at(profile_id, &profile_store_path(profile_id)?, version)
    }

    pub fn open_at(
        profile_id: &str,
        store_path: &Path,
        _version: &str,
    ) -> Result<Self, ServiceErrorKind> {
        let profile_id = normalize_profile_id(profile_id);
        if !is_valid_profile_id(&profile_id) {
            return Err(ServiceErrorKind::InvalidRequest(
                "Profile identifiers must be 1-64 characters of letters, numbers, underscores, or hyphens."
                    .into(),
            ));
        }
        std::fs::create_dir_all(store_path)?;
        let authorization_signing_key = load_or_create_authorization_signing_key(store_path)?;
        let storage = Arc::new(SledStorage::open(store_path).map_err(|error| {
            ServiceErrorKind::Foundation(format!("Unable to open profile PluresDB store: {error}"))
        })?);
        let store =
            Arc::new(CrdtStore::default().with_persistence(storage as Arc<dyn StorageEngine>));
        let timeline = ChronosTimeline::new(Arc::clone(&store));
        let transfer_registry = match store.get(format!("pedantic:transfer-registry:{profile_id}"))
        {
            Some(record) => {
                if record.data["profileId"].as_str() != Some(&profile_id)
                    || record.data["registrySchemaVersion"].as_str()
                        != Some(TRANSFER_REGISTRY_STORAGE_SCHEMA_VERSION)
                {
                    return Err(ServiceErrorKind::Foundation(
                        "Persisted transfer registry has an incompatible schema or profile.".into(),
                    ));
                }
                serde_json::from_value(record.data["registry"].clone()).map_err(|_| {
                    ServiceErrorKind::Foundation("Persisted transfer registry is malformed.".into())
                })?
            }
            None => FederatedTransferRegistry::default(),
        };
        let foundation = Self {
            profile_id: profile_id.clone(),
            timeline,
            _store: store,
            revision_lock: tokio::sync::Mutex::new(()),
            transfer_registry: tokio::sync::Mutex::new(transfer_registry),
            authorization_signing_key,
        };
        Ok(foundation)
    }

    pub fn evidence_count(&self) -> usize {
        self._store
            .get(self.evidence_counter_key())
            .and_then(|record| {
                record
                    .data
                    .get("count")
                    .and_then(serde_json::Value::as_u64)
                    .map(|count| count as usize)
            })
            .unwrap_or(0)
    }

    pub fn recent_evidence(&self) -> EvidencePage {
        let count = self.evidence_count();
        let first = count.saturating_sub(MAX_EVIDENCE_RESULTS);
        let entries = (first..count)
            .rev()
            .filter_map(|index| {
                self._store
                    .get(self.evidence_entry_key(index))
                    .and_then(|record| serde_json::from_value(record.data).ok())
            })
            .collect::<Vec<EvidenceSummary>>();
        EvidencePage {
            truncated: count > entries.len(),
            entries,
        }
    }

    /// Stores redacted immutable transfer evidence in the profile PluresDB
    /// store. Repeated identical event IDs are idempotent; conflicting IDs fail.
    pub async fn record_transfer_event(
        &self,
        event: TransferEvent,
    ) -> Result<bool, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let mut registry = self.transfer_registry.lock().await;
        let event_id = event.operation.event_id.clone();
        let ingest_result = registry.ingest(event);
        match ingest_result {
            TransferIngestResult::Duplicate => return Ok(false),
            TransferIngestResult::Conflict => {
                self.persist_transfer_registry(&registry);
                return Err(ServiceErrorKind::InvalidRequest(
                    "Transfer event ID conflicts with immutable durable evidence.".into(),
                ));
            }
            TransferIngestResult::Invalid => {
                return Err(ServiceErrorKind::InvalidRequest(
                    "Transfer event is missing required safe identity fields.".into(),
                ));
            }
            TransferIngestResult::Inserted => {}
        }
        self.persist_transfer_registry(&registry);
        let event = registry
            .event(&event_id)
            .expect("new transfer event is present")
            .clone();
        let entry = self.timeline.build_entry(
            &self.transfer_event_key(&event.operation.event_id),
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "operationId": event.operation.operation_id,
                "eventId": event.operation.event_id,
                "sequence": event.operation.sequence,
                "state": event.operation.resulting_state,
                "sourceVm": event.source_vm,
                "targetVm": event.target_vm,
                "targetHost": event.target_host,
            }),
            Vec::new(),
            Some("Redacted immutable transfer evidence recorded.".into()),
        );
        self.record_evidence_summary(entry)?;
        Ok(true)
    }

    pub async fn reconcile_transfer_registry(
        &self,
        replica: FederatedTransferRegistry,
    ) -> Result<(), ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let mut registry = self.transfer_registry.lock().await;
        registry.merge(&replica);
        self.persist_transfer_registry(&registry);
        Ok(())
    }

    pub async fn query_transfers(
        &self,
        query: &TransferQuery,
    ) -> Vec<pedantic_operation::TransferOperation> {
        self.transfer_registry.lock().await.query(query)
    }

    pub async fn transfer_report(&self, operation_id: &str) -> Option<TransferReport> {
        self.transfer_registry.lock().await.report(operation_id)
    }

    pub async fn retain_terminal_transfer_history(&self, retain_after: u64) {
        let _revision_guard = self.revision_lock.lock().await;
        let mut registry = self.transfer_registry.lock().await;
        registry.retain_terminal_after(retain_after);
        self.persist_transfer_registry(&registry);
    }

    pub async fn enroll_agent(
            &self,
            enrollment: AgentEnrollment,
            now: u64,
        ) -> Result<(), ServiceErrorKind> {
            let _revision_guard = self.revision_lock.lock().await;
            enrollment
                .validate(now)
                .map_err(|error| ServiceErrorKind::InvalidRequest(error.to_string()))?;
            if enrollment.profile_id != self.profile_id {
                return Err(ServiceErrorKind::InvalidRequest(
                    "Agent enrollment belongs to a different profile.".into(),
                ));
            }
            let public_key = URL_SAFE_NO_PAD
                .decode(&enrollment.public_key)
                .map_err(|_| ServiceErrorKind::InvalidRequest("Agent public key is invalid.".into()))?;
            let public_key: [u8; 32] = public_key.try_into().map_err(|_| {
                ServiceErrorKind::InvalidRequest("Agent public key has the wrong length.".into())
            })?;
            VerifyingKey::from_bytes(&public_key)
                .map_err(|_| ServiceErrorKind::InvalidRequest("Agent public key is invalid.".into()))?;
            let key = self.agent_enrollment_key(&enrollment.agent_id);
            if let Some(existing) = self._store.get(&key)
                && existing.data["enrollmentId"].as_str() != Some(&enrollment.enrollment_id)
            {
                return Err(ServiceErrorKind::InvalidRequest(
                    "An agent identity is already enrolled with different trust material.".into(),
                ));
            }
            self._store.put(
                key.clone(),
                SERVICE_ACTOR,
                serde_json::json!({
                    "profileId": self.profile_id,
                    "enrollmentId": enrollment.enrollment_id,
                    "agentId": enrollment.agent_id,
                    "targetId": enrollment.target_id,
                    "publicKey": enrollment.public_key,
                    "expiresAt": enrollment.expires_at,
                    "revokedAt": 0,
                }),
            );
            let entry = self.timeline.build_entry(
                &key,
                SERVICE_ACTOR,
                ChronosAction::Create,
                &serde_json::json!({
                    "profileId": self.profile_id,
                    "agentId": enrollment.agent_id,
                    "targetId": enrollment.target_id,
                    "enrollmentId": enrollment.enrollment_id,
                }),
                Vec::new(),
                Some("Remote agent enrollment trust material recorded.".into()),
            );
            self.record_evidence_summary(entry)
        }

    pub async fn revoke_agent(
            &self,
            agent_id: &str,
            revoked_at: u64,
        ) -> Result<(), ServiceErrorKind> {
            let _revision_guard = self.revision_lock.lock().await;
            let key = self.agent_enrollment_key(agent_id);
            let mut enrollment = self._store.get(&key).ok_or_else(|| {
                ServiceErrorKind::InvalidRequest("Agent is not enrolled for this profile.".into())
            })?.data;
            enrollment["revokedAt"] = serde_json::json!(revoked_at);
            self._store.put(key, SERVICE_ACTOR, enrollment);
            Ok(())
        }

    pub async fn sync_agent(
            &self,
            batch: AgentObservationBatch,
            now: u64,
        ) -> Result<AgentSyncResult, ServiceErrorKind> {
            let _revision_guard = self.revision_lock.lock().await;
            let enrollment = self
                ._store
                .get(self.agent_enrollment_key(&batch.agent_id))
                .ok_or_else(|| ServiceErrorKind::InvalidRequest("Agent is not enrolled.".into()))?
                .data;
            if enrollment["profileId"].as_str() != Some(&self.profile_id)
                || enrollment["targetId"].as_str() != Some(&batch.target_id)
                || enrollment["expiresAt"].as_u64().is_none_or(|expires_at| expires_at <= now)
                || enrollment["revokedAt"].as_u64().is_some_and(|revoked_at| revoked_at != 0 && revoked_at <= now)
            {
                return Err(ServiceErrorKind::InvalidRequest(
                    "Agent enrollment is no longer eligible for synchronization.".into(),
                ));
            }
            let public_key = enrollment["publicKey"]
                .as_str()
                .ok_or_else(|| ServiceErrorKind::Foundation("Enrollment key is missing.".into()))?;
            let public_key = URL_SAFE_NO_PAD.decode(public_key).map_err(|_| {
                ServiceErrorKind::Foundation("Enrollment key is malformed.".into())
            })?;
            let public_key: [u8; 32] = public_key.try_into().map_err(|_| {
                ServiceErrorKind::Foundation("Enrollment key has the wrong length.".into())
            })?;
            batch
                .verify(&VerifyingKey::from_bytes(&public_key).map_err(|_| {
                    ServiceErrorKind::Foundation("Enrollment key is malformed.".into())
                })?)
                .map_err(|_| ServiceErrorKind::InvalidRequest("Agent batch signature is invalid.".into()))?;
            if batch.profile_id != self.profile_id {
                return Err(ServiceErrorKind::InvalidRequest(
                    "Agent batch belongs to a different profile.".into(),
                ));
            }
            let acknowledgement_key = self.agent_acknowledgement_key(&batch.agent_id);
            let acknowledged_sequence = self._store.get(&acknowledgement_key)
                .and_then(|record| record.data["sequence"].as_u64())
                .unwrap_or(0);
            if batch.first_sequence > acknowledged_sequence + 1 {
                return Ok(AgentSyncResult {
                    acknowledged_sequence,
                    replay_from_sequence: Some(acknowledged_sequence + 1),
                    accepted_observations: 0,
                });
            }
            if batch.last_sequence <= acknowledged_sequence {
                return Ok(AgentSyncResult {
                    acknowledged_sequence,
                    replay_from_sequence: None,
                    accepted_observations: 0,
                });
            }
            if batch.first_sequence != acknowledged_sequence + 1 {
                return Ok(AgentSyncResult {
                    acknowledged_sequence,
                    replay_from_sequence: Some(acknowledged_sequence + 1),
                    accepted_observations: 0,
                });
            }
            let mut accepted = 0;
            for observation in &batch.observations {
                let key = self.agent_observation_key(&observation.event_id);
                if self._store.get(&key).is_none() {
                    self._store.put(
                        key.clone(),
                        SERVICE_ACTOR,
                        serde_json::json!({
                            "profileId": self.profile_id,
                            "agentId": batch.agent_id,
                            "targetId": batch.target_id,
                            "eventId": observation.event_id,
                            "sequence": observation.sequence,
                            "status": observation.status,
                            "redactionClass": observation.redaction_class,
                            "outputDigest": observation.output_digest,
                        }),
                    );
                    let entry = self.timeline.build_entry(
                        &key,
                        SERVICE_ACTOR,
                        ChronosAction::Create,
                        &serde_json::json!({
                            "profileId": self.profile_id,
                            "agentId": batch.agent_id,
                            "targetId": batch.target_id,
                            "eventId": observation.event_id,
                            "sequence": observation.sequence,
                            "status": observation.status,
                        }),
                        Vec::new(),
                        Some("Authenticated remote agent observation recorded.".into()),
                    );
                    self.record_evidence_summary(entry)?;
                    accepted += 1;
                }
            }
            self._store.put(
                acknowledgement_key,
                SERVICE_ACTOR,
                serde_json::json!({ "sequence": batch.last_sequence }),
            );
            Ok(AgentSyncResult {
                acknowledged_sequence: batch.last_sequence,
                replay_from_sequence: None,
                accepted_observations: accepted,
            })
        }
    pub async fn admit_configuration(
        &self,
        request: ConfigurationAdmissionRequest,
    ) -> Result<ConfigurationAdmission, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let prior_source_digest = self
            ._store
            .get(self.configuration_key(&request.revision_id))
            .and_then(|record| record.data["sourceDigest"].as_str().map(str::to_owned));
        let admission = evaluate_configuration_admission(&request, prior_source_digest.as_deref())?;
        let revision_key = format!(
            "pedantic:configuration:{}:{}",
            self.profile_id, admission.revision_id
        );
        if admission.decision == "accepted" {
            self._store.put(
                revision_key.clone(),
                SERVICE_ACTOR,
                serde_json::json!({
                    "profileId": self.profile_id,
                    "revisionId": admission.revision_id,
                    "sourceDigest": request.source_digest,
                    "admissionState": admission.decision,
                    "validationState": "pending",
                    "constraintId": admission.constraint_id,
                }),
            );
        }
        let evidence = self.timeline.build_entry(
            &revision_key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "revisionId": admission.revision_id,
                "decision": admission.decision,
                "constraintId": admission.constraint_id,
            }),
            Vec::new(),
            Some("PX configuration source-digest admission evaluated.".into()),
        );
        self.record_evidence_summary(evidence)?;
        Ok(admission)
    }

    pub async fn validate_configuration(
        &self,
        request: ConfigurationValidationRequest,
    ) -> Result<ConfigurationValidation, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        self.validate_configuration_locked(request).await
    }

    async fn validate_configuration_locked(
        &self,
        request: ConfigurationValidationRequest,
    ) -> Result<ConfigurationValidation, ServiceErrorKind> {
        let revision_key = self.configuration_key(&request.revision_id);
        let revision = self._store.get(&revision_key).ok_or_else(|| {
            ServiceErrorKind::InvalidRequest(
                "Configuration revision was not admitted for this profile.".into(),
            )
        })?;
        let validation_digest = format!("sha256:{:x}", Sha256::digest(request.document.as_bytes()));
        let variables = HashMap::from([
            (
                "revision".to_owned(),
                serde_json::json!({
                    "admission_state": revision.data["admissionState"],
                    "source_digest": revision.data["sourceDigest"],
                }),
            ),
            (
                "validation".to_owned(),
                serde_json::json!({ "source_digest": validation_digest }),
            ),
        ]);
        for constraint_name in [
            "configuration_validation_requires_accepted_admission",
            "configuration_validation_requires_matching_source_digest",
        ] {
            let decision =
                evaluate_configuration_constraint("validation", constraint_name, &variables)?;
            if !decision.accepted {
                let validation = ConfigurationValidation {
                    revision_id: request.revision_id,
                    decision: "rejected".into(),
                    constraint_id: decision.constraint_id,
                    reason: decision.reason,
                };
                self.record_configuration_validation_evidence(&revision_key, &validation)?;
                return Ok(validation);
            }
        }

        let options = DscRunOptions {
            timeout: Some(Duration::from_secs(30)),
            ..Default::default()
        };
        let validation = match run_dsc(
            DscCommand::ConfigValidate,
            DscInput::Stdin(request.document),
            &options,
        )
        .await
        {
            Ok(_) => ConfigurationValidation {
                revision_id: request.revision_id,
                decision: "validated".into(),
                constraint_id: "configuration_validation_requires_matching_source_digest".into(),
                reason: "DSC configuration validation completed.".into(),
            },
            Err(DscError::Execution { .. }) => ConfigurationValidation {
                revision_id: request.revision_id,
                decision: "invalid".into(),
                constraint_id: "dsc_config_validate".into(),
                reason: "DSC rejected the configuration document.".into(),
            },
            Err(error) => return Err(dsc_validation_error(error)),
        };
        self.record_configuration_validation(&revision_key, &validation)?;
        Ok(validation)
    }

    pub async fn observe_inventory(
        &self,
        request: InventoryObservationRequest,
    ) -> Result<InventoryObservation, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let observed_source_digest =
            format!("sha256:{:x}", Sha256::digest(request.document.as_bytes()));
        let variables = HashMap::from([
            (
                "inventory".to_owned(),
                serde_json::json!({ "source_digest": request.source_digest }),
            ),
            (
                "observation".to_owned(),
                serde_json::json!({ "source_digest": observed_source_digest }),
            ),
        ]);
        let policy = evaluate_configuration_constraint(
            "inventory observation",
            "inventory_observation_requires_matching_source_digest",
            &variables,
        )?;
        if !policy.accepted {
            let observation = InventoryObservation {
                observation_id: request.observation_id,
                decision: "rejected".into(),
                constraint_id: policy.constraint_id,
                host_count: 0,
                hosts: Vec::new(),
                reason: policy.reason,
            };
            self.record_inventory_observation(&observation, &observed_source_digest)?;
            return Ok(observation);
        }

        let observation = match parse_hosts(&request.document) {
            Ok(hosts) => InventoryObservation {
                observation_id: request.observation_id,
                decision: "observed".into(),
                constraint_id: policy.constraint_id,
                host_count: hosts.len(),
                hosts,
                reason: "Inventory observation completed.".into(),
            },
            Err(_) => InventoryObservation {
                observation_id: request.observation_id,
                decision: "failed".into(),
                constraint_id: "inventory_parse".into(),
                host_count: 0,
                hosts: Vec::new(),
                reason: "Inventory document could not be parsed.".into(),
            },
        };
        self.record_inventory_observation(&observation, &observed_source_digest)?;
        Ok(observation)
    }

    pub async fn request_compliance(
        &self,
        request: ComplianceRequest,
    ) -> Result<ComplianceDecision, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let revision = self
            ._store
            .get(self.configuration_key(&request.revision_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "Configuration revision was not admitted for this profile.".into(),
                )
            })?;
        let variables = HashMap::from([(
            "revision".to_owned(),
            serde_json::json!({ "validation_state": revision.data["validationState"] }),
        )]);
        let policy = evaluate_configuration_constraint(
            "compliance",
            "compliance_requires_validated_revision",
            &variables,
        )?;
        let decision = ComplianceDecision {
            request_id: request.request_id,
            revision_id: request.revision_id,
            decision: if policy.accepted {
                "accepted".into()
            } else {
                "rejected".into()
            },
            constraint_id: policy.constraint_id,
            reason: policy.reason,
        };
        self._store.put(
            self.compliance_key(&decision.request_id),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": self.profile_id,
                "requestId": decision.request_id,
                "revisionId": decision.revision_id,
                "decision": decision.decision,
                "constraintId": decision.constraint_id,
            }),
        );
        let entry = self.timeline.build_entry(
            &self.compliance_key(&decision.request_id),
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "requestId": decision.request_id,
                "revisionId": decision.revision_id,
                "decision": decision.decision,
                "constraintId": decision.constraint_id,
            }),
            Vec::new(),
            Some("Compliance request evaluated without executing a DSC effect.".into()),
        );
        self.record_evidence_summary(entry)?;
        Ok(decision)
    }

    pub async fn observe_compliance(
        &self,
        request: ComplianceObservationRequest,
    ) -> Result<ComplianceObservation, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let compliance_request = self
            ._store
            .get(self.compliance_key(&request.request_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "Compliance request was not recorded for this profile.".into(),
                )
            })?;
        let revision_id = compliance_request.data["revisionId"]
            .as_str()
            .filter(|revision_id| !revision_id.is_empty())
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded compliance request is missing its configuration revision.".into(),
                )
            })?
            .to_owned();
        let revision = self
            ._store
            .get(self.configuration_key(&revision_id))
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded compliance request refers to a missing configuration revision."
                        .into(),
                )
            })?;
        let request_variables = HashMap::from([(
            "request".to_owned(),
            serde_json::json!({ "decision": compliance_request.data["decision"] }),
        )]);
        let request_policy = evaluate_configuration_constraint(
            "compliance observation",
            "compliance_observation_requires_accepted_request",
            &request_variables,
        )?;
        let source_digest = format!("sha256:{:x}", Sha256::digest(request.document.as_bytes()));
        let source_variables = HashMap::from([
            (
                "revision".to_owned(),
                serde_json::json!({ "source_digest": revision.data["sourceDigest"] }),
            ),
            (
                "observation".to_owned(),
                serde_json::json!({ "source_digest": source_digest }),
            ),
        ]);
        let source_policy = evaluate_configuration_constraint(
            "compliance observation",
            "compliance_observation_requires_matching_source_digest",
            &source_variables,
        )?;
        if !request_policy.accepted || !source_policy.accepted {
            let policy = if request_policy.accepted {
                source_policy
            } else {
                request_policy
            };
            let observation = ComplianceObservation {
                observation_id: request.observation_id,
                request_id: request.request_id,
                revision_id,
                decision: "rejected".into(),
                constraint_id: policy.constraint_id,
                resource_count: 0,
                compliant_resource_count: 0,
                drifted_resource_count: 0,
                reason: policy.reason,
            };
            self.record_compliance_observation(&observation, &source_digest)?;
            return Ok(observation);
        }

        let options = DscRunOptions {
            timeout: Some(Duration::from_secs(30)),
            ..Default::default()
        };
        let observation = match run_dsc(
            DscCommand::ConfigTest,
            DscInput::Stdin(request.document),
            &options,
        )
        .await
        {
            Ok(output) => compliance_observation_from_results(
                request.observation_id,
                request.request_id,
                revision_id,
                parse_test_results(&output).map_err(dsc_compliance_observation_error)?,
            ),
            Err(DscError::Execution { .. }) => ComplianceObservation {
                observation_id: request.observation_id,
                request_id: request.request_id,
                revision_id,
                decision: "failed".into(),
                constraint_id: "dsc_config_test".into(),
                resource_count: 0,
                compliant_resource_count: 0,
                drifted_resource_count: 0,
                reason: "DSC rejected the compliance observation document.".into(),
            },
            Err(error) => return Err(dsc_compliance_observation_error(error)),
        };
        self.record_compliance_observation(&observation, &source_digest)?;
        Ok(observation)
    }

    /// Records the PX admission decision for a requested local remediation.
    /// This does not invoke DSC.
    pub async fn request_remediation(
        &self,
        request: RemediationRequest,
    ) -> Result<RemediationDecision, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let request_key = self.remediation_request_key(&request.request_id);
        if let Some(existing) = self._store.get(&request_key) {
            let matches = existing.data["revisionId"].as_str() == Some(&request.revision_id)
                && existing.data["observationId"].as_str() == Some(&request.observation_id)
                && existing.data["actorId"].as_str() == Some(&request.actor_id)
                && existing.data["idempotencyKey"].as_str() == Some(&request.idempotency_key);
            if !matches {
                return Err(ServiceErrorKind::InvalidRequest(
                    "A remediation request identifier cannot be reused with different inputs."
                        .into(),
                ));
            }
            return serde_json::from_value(existing.data["result"].clone()).map_err(|error| {
                ServiceErrorKind::Foundation(format!(
                    "Recorded remediation request is invalid: {error}"
                ))
            });
        }
        let observation = self
            ._store
            .get(self.compliance_observation_key(&request.observation_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "Compliance observation was not recorded for this profile.".into(),
                )
            })?;
        let current_evidence = self
            ._store
            .get(self.compliance_current_key(&request.revision_id));
        let variables = HashMap::from([
            (
                "remediation".to_owned(),
                serde_json::json!({
                    "revision_id": request.revision_id,
                    "actor_id": request.actor_id,
                    "idempotency_key": request.idempotency_key,
                }),
            ),
            (
                "observation".to_owned(),
                serde_json::json!({
                    "decision": observation.data["decision"],
                    "revision_id": observation.data["revisionId"],
                    "drifted_resource_count": observation.data["driftedResourceCount"],
                    "observation_id": observation.data["observationId"],
                    "observed_at": observation.data["observedAt"],
                }),
            ),
            (
                "current_evidence".to_owned(),
                serde_json::json!({
                    "observation_id": current_evidence
                        .as_ref()
                        .and_then(|record| record.data["observationId"].as_str())
                        .unwrap_or_default(),
                    "minimum_observed_at": remediation_evidence_cutoff(),
                }),
            ),
        ]);
        let policy = first_configuration_rejection(
            "remediation request",
            [
                "remediation_requires_drifted_observation",
                "remediation_requires_current_observation",
                "remediation_requires_fresh_observation",
                "remediation_requires_matching_revision",
                "remediation_requires_actor_and_idempotency_key",
            ],
            &variables,
        )?;
        let decision = RemediationDecision {
            request_id: request.request_id,
            revision_id: request.revision_id,
            observation_id: request.observation_id,
            decision: if policy.accepted {
                "accepted".into()
            } else {
                "rejected".into()
            },
            constraint_id: policy.constraint_id,
            reason: policy.reason,
        };
        self.record_remediation_request(&decision, &request.actor_id, &request.idempotency_key)?;
        Ok(decision)
    }

    /// Converts an explicit human or agent approval into one bounded DSC-set
    /// authorization. This does not invoke DSC.
    pub async fn approve_remediation(
        &self,
        request: RemediationApprovalRequest,
    ) -> Result<RemediationApproval, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let approval_key = self.remediation_approval_key(&request.approval_id);
        if let Some(existing) = self._store.get(&approval_key) {
            let matches = existing.data["requestId"].as_str() == Some(&request.request_id)
                && existing.data["actorId"].as_str() == Some(&request.actor_id)
                && existing.data["approved"].as_bool() == Some(request.approved);
            if !matches {
                return Err(ServiceErrorKind::InvalidRequest(
                    "An approval identifier cannot be reused with different inputs.".into(),
                ));
            }
            return serde_json::from_value(existing.data["result"].clone()).map_err(|error| {
                ServiceErrorKind::Foundation(format!(
                    "Recorded remediation approval is invalid: {error}"
                ))
            });
        }
        let remediation = self
            ._store
            .get(self.remediation_request_key(&request.request_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "Remediation request was not recorded for this profile.".into(),
                )
            })?;
        let variables = HashMap::from([
            (
                "remediation".to_owned(),
                serde_json::json!({ "decision": remediation.data["decision"] }),
            ),
            (
                "approval".to_owned(),
                serde_json::json!({
                    "approval_id": request.approval_id,
                    "actor_id": request.actor_id,
                    "approved": request.approved,
                }),
            ),
        ]);
        let policy = first_configuration_rejection(
            "remediation approval",
            [
                "remediation_approval_requires_accepted_request",
                "remediation_approval_requires_explicit_approval",
                "remediation_approval_requires_actor_and_identifier",
            ],
            &variables,
        )?;
        let accepted = policy.accepted;
        let approval = RemediationApproval {
            approval_id: request.approval_id,
            request_id: request.request_id,
            authorization_id: None,
            authorization: None,
            decision: if accepted {
                "accepted".into()
            } else {
                "rejected".into()
            },
            constraint_id: policy.constraint_id,
            reason: policy.reason,
        };
        if self
            ._store
            .get(self.effect_authorization_key(&approval.approval_id))
            .is_some()
        {
            return Err(ServiceErrorKind::InvalidRequest(
                "An approval identifier is already bound to an authorization.".into(),
            ));
        }
        self.record_remediation_approval(&approval, &request.actor_id, request.approved)?;
        Ok(approval)
    }

    /// Mints a DSC-set authorization only for an already-recorded approval.
    pub async fn authorize_remediation(
        &self,
        request: RemediationApprovalRequest,
    ) -> Result<RemediationApproval, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let approval = self
            ._store
            .get(self.remediation_approval_key(&request.approval_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "A recorded approval is required before effect authorization.".into(),
                )
            })?;
        if approval.data["requestId"].as_str() != Some(&request.request_id)
            || approval.data["actorId"].as_str() != Some(&request.actor_id)
            || approval.data["approved"].as_bool() != Some(true)
            || approval.data["decision"].as_str() != Some("accepted")
            || !request.approved
        {
            return Err(ServiceErrorKind::InvalidRequest(
                "Effect authorization must match an accepted recorded approval.".into(),
            ));
        }
        let remediation = self
            ._store
            .get(self.remediation_request_key(&request.request_id))
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded approval refers to a missing remediation request.".into(),
                )
            })?;
        let revision_id = required_record_string(
            &remediation.data,
            "revisionId",
            "Recorded remediation request is missing its configuration revision.",
        )?;
        let revision = self
            ._store
            .get(self.configuration_key(&revision_id))
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded remediation request refers to a missing configuration revision."
                        .into(),
                )
            })?;
        let source_digest = required_record_string(
            &revision.data,
            "sourceDigest",
            "Recorded configuration revision is missing its source digest.",
        )?;
        let idempotency_key = required_record_string(
            &remediation.data,
            "idempotencyKey",
            "Recorded remediation request is missing its idempotency key.",
        )?;
        let authorization_id = request.approval_id.clone();
        let authorization_key = self.effect_authorization_key(&authorization_id);
        let (authorization, policy) = if let Some(existing) = self._store.get(&authorization_key) {
            let matches = existing.data["requestId"].as_str() == Some(&request.request_id)
                && existing.data["actorId"].as_str() == Some(&request.actor_id)
                && existing.data["revisionId"].as_str() == Some(&revision_id)
                && existing.data["sourceDigest"].as_str() == Some(&source_digest)
                && existing.data["idempotencyKey"].as_str() == Some(&idempotency_key)
                && existing.data["decision"].as_str() == Some("accepted");
            if !matches {
                return Err(ServiceErrorKind::InvalidRequest(
                    "An approval identifier is already bound to a different authorization.".into(),
                ));
            }
            let authorization: EffectAuthorization = serde_json::from_value(
                existing.data["authorization"].clone(),
            )
            .map_err(|error| {
                ServiceErrorKind::Foundation(format!(
                    "Recorded effect authorization is invalid: {error}"
                ))
            })?;
            validate_signed_effect_authorization(
                &authorization,
                &self.authorization_signing_key.verifying_key(),
                &EffectAuthorizationBindings {
                    profile_id: &self.profile_id,
                    agent_id: SERVICE_ACTOR,
                    actor_id: &request.actor_id,
                    authorization_id: &authorization_id,
                    request_id: &request.request_id,
                    input_digest: &source_digest,
                    idempotency_key: &idempotency_key,
                },
            )?;
            let policy = authorization_decision_from_record(&existing.data)?;
            if !policy.accepted {
                return Err(ServiceErrorKind::InvalidRequest(policy.reason));
            }
            (authorization, policy)
        } else {
            let policy = self.evaluate_effect_authorization_policy(
                &request,
                &approval.data,
                &remediation.data,
                &revision.data,
                &source_digest,
                &idempotency_key,
            )?;
            if !policy.accepted {
                return Err(ServiceErrorKind::InvalidRequest(policy.reason));
            }
            let authorization = self.mint_effect_authorization(
                &authorization_id,
                &request,
                &source_digest,
                &idempotency_key,
            )?;
            validate_effect_authorization_constraints(&authorization)?;
            validate_effect_authorization_schema(&authorization)?;
            self.record_effect_authorization(&authorization, &request.actor_id, &policy)?;
            (authorization, policy)
        };
        if self
            ._store
            .get(&authorization_key)
            .is_some_and(|record| record.data["evidenceRecorded"].as_bool() != Some(true))
        {
            self.record_effect_authorization(&authorization, &request.actor_id, &policy)?;
        }
        Ok(RemediationApproval {
            approval_id: authorization_id.clone(),
            request_id: request.request_id,
            authorization_id: Some(authorization_id),
            authorization: Some(authorization),
            decision: if policy.accepted {
                "accepted".into()
            } else {
                "rejected".into()
            },
            constraint_id: policy.constraint_id,
            reason: policy.reason,
        })
    }

    fn evaluate_effect_authorization_policy(
        &self,
        request: &RemediationApprovalRequest,
        approval: &serde_json::Value,
        remediation: &serde_json::Value,
        revision: &serde_json::Value,
        source_digest: &str,
        idempotency_key: &str,
    ) -> Result<PxConstraintDecision, ServiceErrorKind> {
        let variables = HashMap::from([
            (
                "approval".to_owned(),
                serde_json::json!({
                    "approved": approval["approved"],
                    "decision": approval["decision"],
                    "request_id": approval["requestId"],
                    "actor_id": approval["actorId"],
                }),
            ),
            (
                "remediation".to_owned(),
                serde_json::json!({
                    "decision": remediation["decision"],
                    "request_id": remediation["requestId"],
                    "revision_id": remediation["revisionId"],
                    "idempotency_key": idempotency_key,
                }),
            ),
            (
                "revision".to_owned(),
                serde_json::json!({
                    "revision_id": revision["revisionId"],
                    "source_digest": revision["sourceDigest"],
                    "admission_state": revision["admissionState"],
                    "validation_state": revision["validationState"],
                }),
            ),
            (
                "profile".to_owned(),
                serde_json::json!({ "profile_id": self.profile_id }),
            ),
            (
                "authorization".to_owned(),
                serde_json::json!({
                    "actor_id": request.actor_id,
                    "profile_id": self.profile_id,
                    "operation_id": request.request_id,
                    "target_id": self.profile_id,
                    "agent_id": SERVICE_ACTOR,
                    "capability": "dsc.config.apply/v1",
                    "input_digest": source_digest,
                    "idempotency_key": idempotency_key,
                }),
            ),
        ]);
        evaluate_effect_authorization_constraint(
            "effect authorization",
            "durable_authorization_requires_accepted_approval",
            &variables,
        )
    }

    fn mint_effect_authorization(
        &self,
        authorization_id: &str,
        request: &RemediationApprovalRequest,
        source_digest: &str,
        idempotency_key: &str,
    ) -> Result<EffectAuthorization, ServiceErrorKind> {
        let issued_at = current_unix_timestamp();
        let expires_at = issued_at.saturating_add(EFFECT_AUTHORIZATION_LIFETIME.as_secs());
        let fencing_token_key = format!("pedantic:effect-authorization-fence:{}", self.profile_id);
        let fencing_token = self
            ._store
            .get(&fencing_token_key)
            .and_then(|record| record.data["value"].as_u64())
            .unwrap_or_default()
            .saturating_add(1)
            .max(1);
        self._store.put(
            fencing_token_key,
            SERVICE_ACTOR,
            serde_json::json!({ "profileId": self.profile_id, "value": fencing_token }),
        );
        let key_id = authorization_signing_key_id(&self.authorization_signing_key);
        let mut authorization = EffectAuthorization {
            schema_version: EFFECT_AUTHORIZATION_SCHEMA_VERSION.into(),
            authorization_id: authorization_id.into(),
            issuer_id: "px".into(),
            actor_id: request.actor_id.clone(),
            profile_id: self.profile_id.clone(),
            operation_id: request.request_id.clone(),
            step_id: "dsc-config-set".into(),
            attempt_id: authorization_id.into(),
            target_id: self.profile_id.clone(),
            agent_id: SERVICE_ACTOR.into(),
            capability: "dsc.config.apply/v1".into(),
            input_digest: source_digest.into(),
            idempotency_key: idempotency_key.into(),
            fencing_token,
            retry_class: RetryClass::RequiresFreshAuthorization,
            risk_class: RiskClass::High,
            reboot_permitted: false,
            issued_at,
            expires_at,
            revoked_at: 0,
            signature: GrantSignature {
                algorithm: "Ed25519".into(),
                key_id,
                payload_digest: String::new(),
                value: String::new(),
            },
        };
        authorization.signature.payload_digest = authorization.digest();
        authorization.signature.value = URL_SAFE_NO_PAD.encode(
            self.authorization_signing_key
                .sign(&authorization.signing_payload())
                .to_bytes(),
        );
        Ok(authorization)
    }

    /// Runs `dsc config set` locally after PX checks have accepted a persisted
    /// authorization. The service never supplies a remote transport adapter.
    pub async fn execute_remediation(
        &self,
        request: RemediationExecutionRequest,
    ) -> Result<RemediationExecution, ServiceErrorKind> {
        let _revision_guard = self.revision_lock.lock().await;
        let document_digest = format!("sha256:{:x}", Sha256::digest(request.document.as_bytes()));
        let idempotency_key = self.remediation_execution_idempotency_key(&request.idempotency_key);
        if let Some(existing) = self._store.get(&idempotency_key) {
            let recorded_authorization = required_record_string(
                &existing.data,
                "authorizationId",
                "Recorded remediation execution is missing its authorization.",
            )?;
            let recorded_digest = required_record_string(
                &existing.data,
                "documentDigest",
                "Recorded remediation execution is missing its document digest.",
            )?;
            if recorded_authorization != request.authorization_id
                || recorded_digest != document_digest
            {
                return Err(ServiceErrorKind::InvalidRequest(
                    "An idempotency key cannot be reused for a different remediation execution."
                        .into(),
                ));
            }
            if existing.data["status"].as_str() == Some("in_progress") {
                return Err(ServiceErrorKind::InvalidRequest(
                    "This remediation execution was interrupted after its durable claim; reconcile its effects before retrying."
                        .into(),
                ));
            }
            return serde_json::from_value(existing.data["result"].clone()).map_err(|error| {
                ServiceErrorKind::Foundation(format!(
                    "Recorded remediation execution is invalid: {error}"
                ))
            });
        }
        let authorization = self
            ._store
            .get(self.effect_authorization_key(&request.authorization_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "Remediation authorization was not recorded for this profile.".into(),
                )
            })?;
        if authorization.data["decision"].as_str() != Some("accepted")
            || authorization.data["evidenceRecorded"].as_bool() != Some(true)
        {
            return Err(ServiceErrorKind::InvalidRequest(
                "Remediation authorization is not fully recorded.".into(),
            ));
        }
        let signed_authorization: EffectAuthorization = serde_json::from_value(
            authorization.data["authorization"].clone(),
        )
        .map_err(|error| {
            ServiceErrorKind::Foundation(format!(
                "Recorded effect authorization is invalid: {error}"
            ))
        })?;
        let approval = self
            ._store
            .get(self.remediation_approval_key(&request.authorization_id))
            .ok_or_else(|| {
                ServiceErrorKind::InvalidRequest(
                    "Remediation authorization is missing its recorded approval.".into(),
                )
            })?;
        let actor_id = required_record_string(
            &approval.data,
            "actorId",
            "Recorded remediation approval is missing its actor.",
        )?;
        if approval.data["approved"].as_bool() != Some(true)
            || approval.data["decision"].as_str() != Some("accepted")
            || approval.data["requestId"].as_str()
                != Some(signed_authorization.operation_id.as_str())
        {
            return Err(ServiceErrorKind::InvalidRequest(
                "Remediation authorization does not match an accepted approval.".into(),
            ));
        }
        validate_signed_effect_authorization(
            &signed_authorization,
            &self.authorization_signing_key.verifying_key(),
            &EffectAuthorizationBindings {
                profile_id: &self.profile_id,
                agent_id: SERVICE_ACTOR,
                actor_id: &actor_id,
                authorization_id: &request.authorization_id,
                request_id: &required_record_string(
                    &authorization.data,
                    "requestId",
                    "Recorded remediation authorization is missing its request.",
                )?,
                input_digest: &document_digest,
                idempotency_key: &request.idempotency_key,
            },
        )?;
        let revision_id = required_record_string(
            &authorization.data,
            "revisionId",
            "Recorded remediation authorization is missing its configuration revision.",
        )?;
        let request_id = required_record_string(
            &authorization.data,
            "requestId",
            "Recorded remediation authorization is missing its request.",
        )?;
        let authorization_idempotency_key = required_record_string(
            &authorization.data,
            "idempotencyKey",
            "Recorded remediation authorization is missing its idempotency key.",
        )?;
        let binding_variables = HashMap::from([
            (
                "authorization".to_owned(),
                serde_json::json!({
                    "capability": authorization.data["capability"],
                    "decision": authorization.data["decision"],
                    "idempotency_key": authorization_idempotency_key,
                }),
            ),
            (
                "execution".to_owned(),
                serde_json::json!({ "idempotency_key": request.idempotency_key }),
            ),
        ]);
        let binding = evaluate_configuration_constraint(
            "remediation execution",
            "remediation_execution_requires_matching_idempotency_key",
            &binding_variables,
        )?;
        if !binding.accepted {
            let execution = RemediationExecution {
                execution_id: request.execution_id,
                request_id,
                revision_id,
                decision: "rejected".into(),
                constraint_id: binding.constraint_id,
                resource_count: None,
                compliant_resource_count: None,
                drifted_resource_count: None,
                reason: binding.reason,
            };
            self.record_remediation_binding_failure(&request.authorization_id, &execution)?;
            return Ok(execution);
        }

        let revision = self
            ._store
            .get(self.configuration_key(&revision_id))
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded remediation authorization refers to a missing configuration revision."
                        .into(),
                )
            })?;
        let remediation = self
            ._store
            .get(self.remediation_request_key(&request_id))
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded remediation authorization refers to a missing request.".into(),
                )
            })?;
        let observation_id = required_record_string(
            &remediation.data,
            "observationId",
            "Recorded remediation request is missing its compliance observation.",
        )?;
        let observation = self
            ._store
            .get(self.compliance_observation_key(&observation_id))
            .ok_or_else(|| {
                ServiceErrorKind::Foundation(
                    "Recorded remediation request refers to a missing compliance observation."
                        .into(),
                )
            })?;
        let current_evidence = self._store.get(self.compliance_current_key(&revision_id));
        let variables = HashMap::from([
            (
                "authorization".to_owned(),
                serde_json::json!({
                    "capability": authorization.data["capability"],
                    "decision": authorization.data["decision"],
                    "idempotency_key": authorization.data["idempotencyKey"],
                }),
            ),
            (
                "revision".to_owned(),
                serde_json::json!({ "source_digest": revision.data["sourceDigest"] }),
            ),
            (
                "observation".to_owned(),
                serde_json::json!({
                    "decision": observation.data["decision"],
                    "observation_id": observation.data["observationId"],
                    "observed_at": observation.data["observedAt"],
                }),
            ),
            (
                "current_evidence".to_owned(),
                serde_json::json!({
                    "observation_id": current_evidence
                        .as_ref()
                        .and_then(|record| record.data["observationId"].as_str())
                        .unwrap_or_default(),
                    "minimum_observed_at": remediation_evidence_cutoff(),
                }),
            ),
            (
                "execution".to_owned(),
                serde_json::json!({
                    "source_digest": document_digest,
                    "idempotency_key": request.idempotency_key,
                    "observation_id": observation_id,
                }),
            ),
        ]);
        let policy = first_configuration_rejection(
            "remediation execution",
            [
                "set_requires_pedantic_authorization",
                "remediation_execution_requires_matching_authorization",
                "remediation_execution_requires_matching_source_digest",
                "remediation_execution_requires_matching_idempotency_key",
                "remediation_execution_requires_current_observation",
                "remediation_execution_requires_fresh_observation",
            ],
            &variables,
        )?;
        let execution = if !policy.accepted {
            RemediationExecution {
                execution_id: request.execution_id,
                request_id,
                revision_id,
                decision: "rejected".into(),
                constraint_id: policy.constraint_id,
                resource_count: None,
                compliant_resource_count: None,
                drifted_resource_count: None,
                reason: policy.reason,
            }
        } else {
            self.record_remediation_execution_claim(
                &idempotency_key,
                &request.authorization_id,
                &document_digest,
                &request.execution_id,
            )?;
            let options = DscRunOptions {
                timeout: Some(Duration::from_secs(30)),
                ..Default::default()
            };
            let current_evidence = self._store.get(self.compliance_current_key(&revision_id));
            let evidence_variables = HashMap::from([
                (
                    "observation".to_owned(),
                    serde_json::json!({
                        "decision": observation.data["decision"],
                        "observation_id": observation.data["observationId"],
                        "observed_at": observation.data["observedAt"],
                    }),
                ),
                (
                    "current_evidence".to_owned(),
                    serde_json::json!({
                        "observation_id": current_evidence
                            .as_ref()
                            .and_then(|record| record.data["observationId"].as_str())
                            .unwrap_or_default(),
                        "minimum_observed_at": remediation_evidence_cutoff(),
                    }),
                ),
                (
                    "execution".to_owned(),
                    serde_json::json!({ "observation_id": observation_id }),
                ),
            ]);
            let final_evidence_check = first_configuration_rejection(
                "remediation execution",
                [
                    "remediation_execution_requires_current_observation",
                    "remediation_execution_requires_fresh_observation",
                ],
                &evidence_variables,
            )?;
            if !final_evidence_check.accepted {
                let execution = RemediationExecution {
                    execution_id: request.execution_id,
                    request_id,
                    revision_id,
                    decision: "rejected".into(),
                    constraint_id: final_evidence_check.constraint_id,
                    resource_count: None,
                    compliant_resource_count: None,
                    drifted_resource_count: None,
                    reason: final_evidence_check.reason,
                };
                self.record_remediation_execution(
                    &idempotency_key,
                    &request.authorization_id,
                    &document_digest,
                    &execution,
                )?;
                return Ok(execution);
            }
            match run_dsc(
                DscCommand::ConfigSet,
                DscInput::Stdin(request.document),
                &options,
            )
            .await
            {
                Ok(output) => RemediationExecution {
                    execution_id: request.execution_id,
                    request_id,
                    revision_id,
                    decision: "completed".into(),
                    constraint_id: "dsc_config_set".into(),
                    resource_count: output.json.as_ref().and_then(remediation_resource_count),
                    compliant_resource_count: None,
                    drifted_resource_count: None,
                    reason: "DSC remediation completed locally.".into(),
                },
                Err(error) => remediation_execution_failure(
                    request.execution_id,
                    request_id,
                    revision_id,
                    error,
                ),
            }
        };
        self.record_remediation_execution(
            &idempotency_key,
            &request.authorization_id,
            &document_digest,
            &execution,
        )?;
        Ok(execution)
    }

    pub fn record_start(&self, version: &str) {
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "service": SERVICE_ACTOR,
            "version": version,
            "event": "service.started",
        });
        let entry = self.timeline.build_entry(
            &self.evidence_key(),
            SERVICE_ACTOR,
            ChronosAction::Create,
            &metadata,
            Vec::new(),
            Some("Authenticated local service started; metadata only.".into()),
        );
        let _ = self.record_evidence_summary(entry);
        self._store
            .put(self.evidence_key(), SERVICE_ACTOR, metadata.clone());
    }

    fn record_evidence_summary(&self, entry: ChronosEntry) -> Result<(), ServiceErrorKind> {
        if !self.timeline.record(&entry) {
            return Err(ServiceErrorKind::Foundation(
                "Chronos evidence recording failed.".into(),
            ));
        }
        let count = self.evidence_count();
        self._store.put(
            self.evidence_entry_key(count),
            SERVICE_ACTOR,
            serde_json::to_value(EvidenceSummary::from(entry))
                .expect("evidence summary serializes"),
        );
        self._store.put(
            self.evidence_counter_key(),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": self.profile_id,
                "count": count + 1,
                "key": self.evidence_key(),
            }),
        );
        Ok(())
    }

    fn record_configuration_validation(
        &self,
        revision_key: &str,
        validation: &ConfigurationValidation,
    ) -> Result<(), ServiceErrorKind> {
        let existing = self
            ._store
            .get(revision_key)
            .map(|record| record.data)
            .unwrap_or_else(|| serde_json::json!({}));
        self._store.put(
            revision_key,
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": self.profile_id,
                "revisionId": validation.revision_id,
                "sourceDigest": existing["sourceDigest"],
                "admissionState": existing["admissionState"],
                "validationState": validation.decision,
                "constraintId": validation.constraint_id,
            }),
        );
        let entry = self.timeline.build_entry(
            revision_key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "revisionId": validation.revision_id,
                "decision": validation.decision,
                "constraintId": validation.constraint_id,
            }),
            Vec::new(),
            Some("Configuration validation completed without retaining source content.".into()),
        );
        self.record_evidence_summary(entry)
    }

    fn record_configuration_validation_evidence(
        &self,
        revision_key: &str,
        validation: &ConfigurationValidation,
    ) -> Result<(), ServiceErrorKind> {
        let entry = self.timeline.build_entry(
            revision_key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "revisionId": validation.revision_id,
                "decision": validation.decision,
                "constraintId": validation.constraint_id,
            }),
            Vec::new(),
            Some("Configuration validation rejection recorded without changing the admitted projection.".into()),
        );
        self.record_evidence_summary(entry)
    }

    fn persist_transfer_registry(&self, registry: &FederatedTransferRegistry) {
        self._store.put(
            self.transfer_registry_key(),
            SERVICE_ACTOR,
            serde_json::json!({
                "registrySchemaVersion": TRANSFER_REGISTRY_STORAGE_SCHEMA_VERSION,
                "profileId": self.profile_id,
                "registry": registry,
            }),
        );
    }

    fn transfer_registry_key(&self) -> String {
        format!("pedantic:transfer-registry:{}", self.profile_id)
    }

    fn transfer_event_key(&self, event_id: &str) -> String {
        format!("pedantic:transfer-event:{}:{event_id}", self.profile_id)
    }

    fn configuration_key(&self, revision_id: &str) -> String {
        format!("pedantic:configuration:{}:{revision_id}", self.profile_id)
    }

    fn agent_enrollment_key(&self, agent_id: &str) -> String {
        format!("pedantic:agent-enrollment:{}:{agent_id}", self.profile_id)
    }

    fn agent_acknowledgement_key(&self, agent_id: &str) -> String {
        format!("pedantic:agent-acknowledgement:{}:{agent_id}", self.profile_id)
    }

    fn agent_observation_key(&self, event_id: &str) -> String {
        format!("pedantic:agent-observation:{}:{event_id}", self.profile_id)
    }

    fn inventory_observation_key(&self, observation_id: &str) -> String {
        format!(
            "pedantic:inventory-observation:{}:{observation_id}",
            self.profile_id
        )
    }

    fn record_inventory_observation(
        &self,
        observation: &InventoryObservation,
        source_digest: &str,
    ) -> Result<(), ServiceErrorKind> {
        let key = self.inventory_observation_key(&observation.observation_id);
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "observationId": observation.observation_id,
            "sourceDigest": source_digest,
            "decision": observation.decision,
            "constraintId": observation.constraint_id,
            "hostCount": observation.host_count,
            "hosts": observation.hosts,
        });
        if observation.decision == "observed" {
            self._store
                .put(key.clone(), SERVICE_ACTOR, metadata.clone());
        }
        let entry = self.timeline.build_entry(
            &key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "observationId": observation.observation_id,
                "decision": observation.decision,
                "constraintId": observation.constraint_id,
                "hostCount": observation.host_count,
            }),
            Vec::new(),
            Some("Inventory observation recorded without retaining source content.".into()),
        );
        self.record_evidence_summary(entry)
    }

    fn compliance_key(&self, request_id: &str) -> String {
        format!(
            "pedantic:compliance-request:{}:{request_id}",
            self.profile_id
        )
    }

    fn compliance_observation_key(&self, observation_id: &str) -> String {
        format!(
            "pedantic:compliance-observation:{}:{observation_id}",
            self.profile_id
        )
    }

    fn remediation_request_key(&self, request_id: &str) -> String {
        format!(
            "pedantic:remediation-request:{}:{request_id}",
            self.profile_id
        )
    }

    fn remediation_approval_key(&self, approval_id: &str) -> String {
        format!(
            "pedantic:remediation-approval:{}:{approval_id}",
            self.profile_id
        )
    }

    fn compliance_current_key(&self, revision_id: &str) -> String {
        format!(
            "pedantic:compliance-current:{}:{revision_id}",
            self.profile_id
        )
    }

    fn effect_authorization_key(&self, authorization_id: &str) -> String {
        format!(
            "pedantic:effect-authorization:{}:{authorization_id}",
            self.profile_id
        )
    }

    fn remediation_execution_idempotency_key(&self, idempotency_key: &str) -> String {
        let digest = Sha256::digest(idempotency_key.as_bytes());
        format!(
            "pedantic:remediation-execution:{}:sha256:{digest:x}",
            self.profile_id
        )
    }

    fn record_remediation_request(
        &self,
        decision: &RemediationDecision,
        actor_id: &str,
        idempotency_key: &str,
    ) -> Result<(), ServiceErrorKind> {
        let key = self.remediation_request_key(&decision.request_id);
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "requestId": decision.request_id,
            "revisionId": decision.revision_id,
            "observationId": decision.observation_id,
            "actorId": actor_id,
            "idempotencyKey": idempotency_key,
            "decision": decision.decision,
            "constraintId": decision.constraint_id,
            "result": decision,
        });
        if let Some(existing) = self._store.get(&key) {
            if existing.data != metadata {
                return Err(ServiceErrorKind::InvalidRequest(
                    "A remediation request identifier cannot be reused for a different request."
                        .into(),
                ));
            }
        }
        self._store
            .put(key.clone(), SERVICE_ACTOR, metadata.clone());
        let entry = self.timeline.build_entry(
            &key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "requestId": decision.request_id,
                "revisionId": decision.revision_id,
                "observationId": decision.observation_id,
                "decision": decision.decision,
                "constraintId": decision.constraint_id,
            }),
            Vec::new(),
            Some(
                "PX remediation request decision recorded without retaining configuration content."
                    .into(),
            ),
        );
        self.record_evidence_summary(entry)
    }

    fn record_remediation_approval(
        &self,
        approval: &RemediationApproval,
        actor_id: &str,
        approved: bool,
    ) -> Result<(), ServiceErrorKind> {
        let key = self.remediation_approval_key(&approval.approval_id);
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "approvalId": approval.approval_id,
            "requestId": approval.request_id,
            "actorId": actor_id,
            "approved": approved,
            "authorizationId": approval.authorization_id,
            "decision": approval.decision,
            "constraintId": approval.constraint_id,
            "result": approval,
        });
        if let Some(existing) = self._store.get(&key) {
            if existing.data != metadata {
                return Err(ServiceErrorKind::InvalidRequest(
                    "A remediation approval identifier cannot be reused for a different approval."
                        .into(),
                ));
            }
        }
        self._store
            .put(key.clone(), SERVICE_ACTOR, metadata.clone());
        let entry = self.timeline.build_entry(
            &key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "approvalId": approval.approval_id,
                "requestId": approval.request_id,
                "decision": approval.decision,
                "constraintId": approval.constraint_id,
            }),
            Vec::new(),
            Some("PX remediation approval decision recorded.".into()),
        );
        self.record_evidence_summary(entry)
    }

    fn record_effect_authorization(
        &self,
        authorization: &EffectAuthorization,
        actor_id: &str,
        policy: &PxConstraintDecision,
    ) -> Result<(), ServiceErrorKind> {
        let key = self.effect_authorization_key(&authorization.authorization_id);
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "authorizationId": authorization.authorization_id,
            "requestId": authorization.operation_id,
            "actorId": actor_id,
            "revisionId": self._store.get(self.remediation_request_key(&authorization.operation_id))
                .and_then(|record| record.data["revisionId"].as_str().map(str::to_owned))
                .unwrap_or_default(),
            "sourceDigest": authorization.input_digest,
            "idempotencyKey": authorization.idempotency_key,
            "capability": "dsc.config.apply/v1",
            "decision": "accepted",
            "constraintId": policy.constraint_id,
            "reason": policy.reason,
            "authorization": authorization,
            "authorizationDecision": {
                "decision": if policy.accepted { "accepted" } else { "rejected" },
                "constraintId": policy.constraint_id,
                "reason": policy.reason,
            },
            "evidenceRecorded": false,
        });
        let current = self._store.get(&key);
        if let Some(existing) = current.as_ref() {
            let matches = existing.data["authorization"] == metadata["authorization"]
                && existing.data["requestId"] == metadata["requestId"]
                && existing.data["actorId"] == metadata["actorId"]
                && existing.data["revisionId"] == metadata["revisionId"]
                && existing.data["sourceDigest"] == metadata["sourceDigest"]
                && existing.data["idempotencyKey"] == metadata["idempotencyKey"]
                && existing.data["constraintId"] == metadata["constraintId"]
                && existing.data["decision"] == metadata["decision"];
            if !matches {
                return Err(ServiceErrorKind::InvalidRequest(
                    "An authorization identifier is already bound to different authorization evidence."
                        .into(),
                ));
            }
        } else {
            self._store
                .put(key.clone(), SERVICE_ACTOR, metadata.clone());
        }
        if current
            .as_ref()
            .is_some_and(|record| record.data["evidenceRecorded"].as_bool() == Some(true))
        {
            return Ok(());
        }
        let entry = self.timeline.build_entry(
            &key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "authorizationId": authorization.authorization_id,
                "requestId": authorization.operation_id,
                "revisionId": metadata["revisionId"],
                "actorId": actor_id,
                "capability": authorization.capability,
                "decision": "accepted",
                "constraintId": policy.constraint_id,
            }),
            Vec::new(),
            Some("PX issued a signed, bounded local DSC set authorization.".into()),
        );
        self.record_evidence_summary(entry)?;
        let mut recorded = self
            ._store
            .get(&key)
            .ok_or_else(|| {
                ServiceErrorKind::Foundation("Pending authorization disappeared.".into())
            })?
            .data;
        recorded["evidenceRecorded"] = serde_json::Value::Bool(true);
        self._store.put(key, SERVICE_ACTOR, recorded);
        Ok(())
    }

    fn record_remediation_execution(
        &self,
        idempotency_key: &str,
        authorization_id: &str,
        document_digest: &str,
        execution: &RemediationExecution,
    ) -> Result<(), ServiceErrorKind> {
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "status": "completed",
            "executionId": execution.execution_id,
            "authorizationId": authorization_id,
            "documentDigest": document_digest,
            "result": execution,
        });
        self._store
            .put(idempotency_key, SERVICE_ACTOR, metadata.clone());
        let entry = self.timeline.build_entry(
            idempotency_key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "executionId": execution.execution_id,
                "requestId": execution.request_id,
                "revisionId": execution.revision_id,
                "decision": execution.decision,
                "constraintId": execution.constraint_id,
            }),
            Vec::new(),
            Some(
                "Local DSC remediation outcome recorded without retaining configuration content."
                    .into(),
            ),
        );
        self.record_evidence_summary(entry)
    }

    fn record_remediation_execution_claim(
        &self,
        idempotency_key: &str,
        authorization_id: &str,
        document_digest: &str,
        execution_id: &str,
    ) -> Result<(), ServiceErrorKind> {
        self._store.put(
            idempotency_key,
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": self.profile_id,
                "status": "in_progress",
                "executionId": execution_id,
                "authorizationId": authorization_id,
                "documentDigest": document_digest,
            }),
        );
        let entry = self.timeline.build_entry(
            idempotency_key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &serde_json::json!({
                "profileId": self.profile_id,
                "executionId": execution_id,
                "authorizationId": authorization_id,
                "decision": "in_progress",
            }),
            Vec::new(),
            Some(
                "Local DSC remediation execution claimed; interrupted attempts require reconciliation."
                    .into(),
            ),
        );
        self.record_evidence_summary(entry)
    }

    fn record_remediation_binding_failure(
        &self,
        authorization_id: &str,
        execution: &RemediationExecution,
    ) -> Result<(), ServiceErrorKind> {
        let entry = self.timeline.build_entry(
            &self.effect_authorization_key(authorization_id),
            SERVICE_ACTOR,
            ChronosAction::Update,
            &serde_json::json!({
                "profileId": self.profile_id,
                "executionId": execution.execution_id,
                "decision": execution.decision,
                "constraintId": execution.constraint_id,
            }),
            Vec::new(),
            Some(
                "Remediation execution rejected because its authorization binding did not match."
                    .into(),
            ),
        );
        self.record_evidence_summary(entry)
    }

    fn record_compliance_observation(
        &self,
        observation: &ComplianceObservation,
        source_digest: &str,
    ) -> Result<(), ServiceErrorKind> {
        let key = self.compliance_observation_key(&observation.observation_id);
        let observed_at = current_unix_timestamp();
        let metadata = serde_json::json!({
            "profileId": self.profile_id,
            "observationId": observation.observation_id,
            "requestId": observation.request_id,
            "revisionId": observation.revision_id,
            "sourceDigest": source_digest,
            "observedAt": observed_at,
            "decision": observation.decision,
            "constraintId": observation.constraint_id,
            "resourceCount": observation.resource_count,
            "compliantResourceCount": observation.compliant_resource_count,
            "driftedResourceCount": observation.drifted_resource_count,
        });
        self._store
            .put(key.clone(), SERVICE_ACTOR, metadata.clone());
        self._store.put(
            self.compliance_current_key(&observation.revision_id),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": self.profile_id,
                "revisionId": observation.revision_id,
                "observationId": observation.observation_id,
                "observedAt": observed_at,
            }),
        );
        let entry = self.timeline.build_entry(
            &key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &metadata,
            Vec::new(),
            Some("Compliance observation recorded without retaining DSC source content.".into()),
        );
        self.record_evidence_summary(entry)
    }

    fn evidence_entry_key(&self, index: usize) -> String {
        format!("pedantic:service:evidence:{}:{index}", self.profile_id)
    }

    fn evidence_key(&self) -> String {
        format!("pedantic:service:{}", self.profile_id)
    }

    fn evidence_counter_key(&self) -> String {
        format!("pedantic:service:count:{}", self.profile_id)
    }
}

fn evaluate_configuration_admission(
    request: &ConfigurationAdmissionRequest,
    prior_source_digest: Option<&str>,
) -> Result<ConfigurationAdmission, ServiceErrorKind> {
    let variables = HashMap::from([(
        "revision".to_owned(),
        serde_json::json!({
            "revision_id": request.revision_id,
            "source_digest": request.source_digest,
        "prior_source_digest": prior_source_digest.unwrap_or_default(),
        }),
    )]);
    let decision = evaluate_configuration_constraint(
        "admission",
        if prior_source_digest.is_some() {
            "configuration_admission_requires_immutable_source_digest"
        } else {
            "configuration_requires_source_digest"
        },
        &variables,
    )?;
    Ok(ConfigurationAdmission {
        revision_id: request.revision_id.clone(),
        decision: if decision.accepted {
            "accepted".into()
        } else {
            "rejected".into()
        },
        constraint_id: decision.constraint_id,
        reason: decision.reason,
    })
}

fn compliance_observation_from_results(
    observation_id: String,
    request_id: String,
    revision_id: String,
    results: Vec<DscTestResult>,
) -> ComplianceObservation {
    let resource_count = results.len();
    let compliant_resource_count = results
        .iter()
        .filter(|result| result.in_desired_state)
        .count();
    ComplianceObservation {
        observation_id,
        request_id,
        revision_id,
        decision: "observed".into(),
        constraint_id: "dsc_config_test".into(),
        resource_count,
        compliant_resource_count,
        drifted_resource_count: resource_count - compliant_resource_count,
        reason: "DSC compliance observation completed.".into(),
    }
}

fn remediation_resource_count(output: &serde_json::Value) -> Option<usize> {
    output
        .as_array()
        .or_else(|| output.get("results").and_then(serde_json::Value::as_array))
        .or_else(|| {
            output
                .get("resources")
                .and_then(serde_json::Value::as_array)
        })
        .or_else(|| output.get("value").and_then(serde_json::Value::as_array))
        .map(Vec::len)
}

fn current_unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn load_or_create_authorization_signing_key(
    store_path: &Path,
) -> Result<SigningKey, ServiceErrorKind> {
    let path = store_path.join(".pedantic-effect-authorization-key");
    match read_authorization_signing_key(&path) {
        Ok(key) => return Ok(key),
        Err(ServiceErrorKind::Io(error)) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    let key = SigningKey::generate(&mut OsRng);
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    match options.open(&path) {
        Ok(mut file) => {
            file.write_all(&key.to_bytes())?;
            file.sync_all()?;
            Ok(key)
        }
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
            read_authorization_signing_key(&path)
        }
        Err(error) => Err(error.into()),
    }
}

fn read_authorization_signing_key(path: &Path) -> Result<SigningKey, ServiceErrorKind> {
    let mut file = std::fs::File::open(path)?;
    let mut bytes = [0; 32];
    file.read_exact(&mut bytes)?;
    let mut trailing = [0; 1];
    if file.read(&mut trailing)? != 0 {
        return Err(ServiceErrorKind::Foundation(
            "Effect authorization signing key has an invalid length.".into(),
        ));
    }
    Ok(SigningKey::from_bytes(&bytes))
}

fn authorization_signing_key_id(key: &SigningKey) -> String {
    authorization_verifying_key_id(&key.verifying_key())
}

fn authorization_verifying_key_id(key: &VerifyingKey) -> String {
    let digest = Sha256::digest(key.as_bytes());
    format!("pedantic-service-sha256:{digest:x}")
}

struct EffectAuthorizationBindings<'a> {
    profile_id: &'a str,
    agent_id: &'a str,
    actor_id: &'a str,
    authorization_id: &'a str,
    request_id: &'a str,
    input_digest: &'a str,
    idempotency_key: &'a str,
}

fn validate_signed_effect_authorization(
    authorization: &EffectAuthorization,
    key: &VerifyingKey,
    bindings: &EffectAuthorizationBindings<'_>,
) -> Result<(), ServiceErrorKind> {
    validate_effect_authorization_schema(authorization)?;
    let now = current_unix_timestamp();
    if authorization.schema_version != EFFECT_AUTHORIZATION_SCHEMA_VERSION
        || authorization.issued_at > now
        || authorization.expires_at <= now
        || authorization.expires_at <= authorization.issued_at
        || authorization.revoked_at != 0
        || authorization.authorization_id != bindings.authorization_id
        || authorization.actor_id != bindings.actor_id
        || authorization.profile_id != bindings.profile_id
        || authorization.operation_id != bindings.request_id
        || authorization.target_id != bindings.profile_id
        || authorization.agent_id != bindings.agent_id
        || authorization.capability != "dsc.config.apply/v1"
        || authorization.input_digest != bindings.input_digest
        || authorization.idempotency_key != bindings.idempotency_key
        || authorization.signature.key_id != authorization_verifying_key_id(key)
        || authorization.signature.algorithm != "Ed25519"
        || authorization.signature.payload_digest != authorization.digest()
    {
        return Err(ServiceErrorKind::InvalidRequest(
            "Remediation authorization is expired, revoked, or bound to a different effect.".into(),
        ));
    }
    let signature_bytes = URL_SAFE_NO_PAD
        .decode(&authorization.signature.value)
        .map_err(|_| {
            ServiceErrorKind::InvalidRequest(
                "Remediation authorization has an invalid signature.".into(),
            )
        })?;
    let signature = Signature::from_slice(&signature_bytes).map_err(|_| {
        ServiceErrorKind::InvalidRequest(
            "Remediation authorization has an invalid signature.".into(),
        )
    })?;
    key.verify(&authorization.signing_payload(), &signature)
        .map_err(|_| {
            ServiceErrorKind::InvalidRequest(
                "Remediation authorization signature verification failed.".into(),
            )
        })
}

fn validate_effect_authorization_schema(
    authorization: &EffectAuthorization,
) -> Result<(), ServiceErrorKind> {
    let schema: serde_json::Value = serde_json::from_str(EFFECT_AUTHORIZATION_SCHEMA)
        .map_err(|error| ServiceErrorKind::Foundation(error.to_string()))?;
    let validator = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(&schema)
        .map_err(|error| ServiceErrorKind::Foundation(error.to_string()))?;
    let value = serde_json::to_value(authorization)
        .map_err(|error| ServiceErrorKind::Foundation(error.to_string()))?;
    validator.validate(&value).map_err(|mut errors| {
        ServiceErrorKind::InvalidRequest(
            errors
                .next()
                .map(|error| format!("Effect authorization does not match its schema: {error}"))
                .unwrap_or_else(|| "Effect authorization does not match its schema.".into()),
        )
    })
}

fn validate_effect_authorization_constraints(
    authorization: &EffectAuthorization,
) -> Result<(), ServiceErrorKind> {
    let variables = HashMap::from([(
        "authorization".to_owned(),
        serde_json::json!({
            "authorization_id": authorization.authorization_id,
            "issuer_id": authorization.issuer_id,
            "actor_id": authorization.actor_id,
            "profile_id": authorization.profile_id,
            "operation_id": authorization.operation_id,
            "step_id": authorization.step_id,
            "attempt_id": authorization.attempt_id,
            "target_id": authorization.target_id,
            "agent_id": authorization.agent_id,
            "capability": authorization.capability,
            "input_digest": authorization.input_digest,
            "idempotency_key": authorization.idempotency_key,
            "fencing_token": authorization.fencing_token,
            "retry_class": authorization.retry_class,
            "risk_class": authorization.risk_class,
            "issued_at": authorization.issued_at,
            "expires_at": authorization.expires_at,
            "revoked_at": authorization.revoked_at,
            "signature_algorithm": authorization.signature.algorithm,
            "signing_key_id": authorization.signature.key_id,
            "signature_payload_digest": authorization.signature.payload_digest,
            "signature": authorization.signature.value,
        }),
    )]);
    let decision = first_effect_authorization_rejection(
        "effect authorization",
        [
            "durable_authorization_is_bound",
            "durable_authorization_has_validity_window",
        ],
        &variables,
    )?;
    if !decision.accepted {
        return Err(ServiceErrorKind::InvalidRequest(decision.reason));
    }
    Ok(())
}

fn authorization_decision_from_record(
    record: &serde_json::Value,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let decision = &record["authorizationDecision"];
    let accepted = decision["decision"].as_str() == Some("accepted");
    Ok(PxConstraintDecision {
        accepted,
        constraint_id: required_record_string(
            decision,
            "constraintId",
            "Recorded authorization is missing its PX constraint.",
        )?,
        reason: required_record_string(
            decision,
            "reason",
            "Recorded authorization is missing its PX decision reason.",
        )?,
    })
}

fn remediation_evidence_cutoff() -> u64 {
    current_unix_timestamp().saturating_sub(MAX_REMEDIATION_OBSERVATION_AGE.as_secs())
}

fn required_record_string(
    record: &serde_json::Value,
    field: &str,
    error: &str,
) -> Result<String, ServiceErrorKind> {
    record[field]
        .as_str()
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| ServiceErrorKind::Foundation(error.into()))
}

fn first_configuration_rejection<const N: usize>(
    operation: &str,
    constraints: [&str; N],
    variables: &HashMap<String, serde_json::Value>,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let mut last = None;
    for constraint in constraints {
        let decision = evaluate_configuration_constraint(operation, constraint, variables)?;
        if !decision.accepted {
            return Ok(decision);
        }
        last = Some(decision);
    }
    last.ok_or_else(|| {
        ServiceErrorKind::Foundation(
            "PX remediation procedure has no constraints to evaluate.".into(),
        )
    })
}

fn first_effect_authorization_rejection<const N: usize>(
    operation: &str,
    constraints: [&str; N],
    variables: &HashMap<String, serde_json::Value>,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let mut last = None;
    for constraint in constraints {
        let decision = evaluate_effect_authorization_constraint(operation, constraint, variables)?;
        if !decision.accepted {
            return Ok(decision);
        }
        last = Some(decision);
    }
    last.ok_or_else(|| {
        ServiceErrorKind::Foundation(
            "PX effect authorization procedure has no constraints to evaluate.".into(),
        )
    })
}

fn remediation_execution_failure(
    execution_id: String,
    request_id: String,
    revision_id: String,
    error: DscError,
) -> RemediationExecution {
    let reason = match error {
        DscError::NotFound => "DSC remediation is unavailable because dsc is not installed.",
        DscError::Timeout(_) => "DSC remediation exceeded the bounded timeout.",
        DscError::Execution { .. } => "DSC rejected the remediation document.",
        DscError::Spawn(_) | DscError::Io(_) => "DSC remediation could not start.",
        DscError::Parse(_) => "DSC remediation returned an unsupported result.",
        DscError::Yaml(_) => "DSC remediation could not serialize the document.",
        DscError::SshConnection(_) => "DSC remediation could not reach its adapter.",
    };
    RemediationExecution {
        execution_id,
        request_id,
        revision_id,
        decision: "failed".into(),
        constraint_id: "dsc_config_set".into(),
        resource_count: None,
        compliant_resource_count: None,
        drifted_resource_count: None,
        reason: reason.into(),
    }
}

struct PxConstraintDecision {
    accepted: bool,
    constraint_id: String,
    reason: String,
}

struct PedanticPxFunctionRegistry;

impl FunctionRegistry for PedanticPxFunctionRegistry {
    fn call(&self, name: &str, args: &[serde_json::Value]) -> Result<serde_json::Value, String> {
        if name != "sha256" {
            return PureFunctionRegistry.call(name, args);
        }
        if args.len() != 1 {
            return Err("sha256: requires exactly one argument".into());
        }
        let document = args[0]
            .as_str()
            .ok_or_else(|| "sha256: argument must be a string".to_owned())?;
        Ok(serde_json::Value::String(format!(
            "sha256:{:x}",
            Sha256::digest(document.as_bytes())
        )))
    }

    fn contains(&self, name: &str) -> bool {
        name == "sha256" || PureFunctionRegistry.contains(name)
    }
}

fn evaluate_configuration_constraint(
    operation: &str,
    constraint_name: &str,
    variables: &HashMap<String, serde_json::Value>,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let constraint = configuration_constraint(constraint_name)?;
    evaluate_px_constraint(operation, constraint, variables)
}

fn evaluate_effect_authorization_constraint(
    operation: &str,
    constraint_name: &str,
    variables: &HashMap<String, serde_json::Value>,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let constraint = effect_authorization_constraint(constraint_name)?;
    evaluate_px_constraint(operation, constraint, variables)
}

fn evaluate_px_constraint(
    operation: &str,
    constraint: &ConstraintDecl,
    variables: &HashMap<String, serde_json::Value>,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let registry = PedanticPxFunctionRegistry;
    let outcome = px_eval::eval_constraint(constraint, variables, &registry).map_err(|error| {
        ServiceErrorKind::Foundation(format!("PX {operation} evaluation failed: {error}"))
    })?;
    let constraint_id = constraint.name.name.clone();
    let (accepted, reason) = match outcome {
        ConstraintOutcome::Satisfied => (true, "PX constraint accepted the request.".to_owned()),
        ConstraintOutcome::Violated { message, .. } => (
            false,
            message.unwrap_or_else(|| format!("PX {operation} constraint rejected the request.")),
        ),
        ConstraintOutcome::NotApplicable => (
            false,
            format!("PX {operation} constraint was not applicable."),
        ),
    };
    Ok(PxConstraintDecision {
        accepted,
        constraint_id,
        reason,
    })
}

fn configuration_constraint(name: &str) -> Result<&'static ConstraintDecl, ServiceErrorKind> {
    let result = CONFIGURATION_CONSTRAINTS.get_or_init(|| {
        let document = px_compiler::parse(CONFIGURATION_LIFECYCLE_SOURCE)
            .map_err(|error| format!("PX configuration lifecycle parse failed: {error}"))?;
        Ok(document
            .statements
            .into_iter()
            .filter_map(|statement| match statement {
                Statement::Constraint(constraint) => Some(constraint),
                _ => None,
            })
            .collect())
    });
    result
        .as_ref()
        .map_err(|error| ServiceErrorKind::Foundation(error.clone()))
        .and_then(|constraints| {
            constraints
                .iter()
                .find(|constraint| constraint.name.name == name)
                .ok_or_else(|| {
                    ServiceErrorKind::Foundation(format!(
                        "PX configuration constraint '{name}' is missing."
                    ))
                })
        })
}

fn effect_authorization_constraint(
    name: &str,
) -> Result<&'static ConstraintDecl, ServiceErrorKind> {
    let result = EFFECT_AUTHORIZATION_CONSTRAINTS.get_or_init(|| {
        let document = px_compiler::parse(EFFECT_AUTHORIZATION_SOURCE)
            .map_err(|error| format!("PX effect authorization parse failed: {error}"))?;
        Ok(document
            .statements
            .into_iter()
            .filter_map(|statement| match statement {
                Statement::Constraint(constraint) => Some(constraint),
                _ => None,
            })
            .collect())
    });
    result
        .as_ref()
        .map_err(|error| ServiceErrorKind::Foundation(error.clone()))
        .and_then(|constraints| {
            constraints
                .iter()
                .find(|constraint| constraint.name.name == name)
                .ok_or_else(|| {
                    ServiceErrorKind::Foundation(format!(
                        "PX effect authorization constraint '{name}' is missing."
                    ))
                })
        })
}

fn dsc_validation_error(error: DscError) -> ServiceErrorKind {
    dsc_operation_error(error, "configuration validation")
}

fn dsc_compliance_observation_error(error: DscError) -> ServiceErrorKind {
    dsc_operation_error(error, "compliance observation")
}

fn dsc_operation_error(error: DscError, operation: &str) -> ServiceErrorKind {
    let message = match error {
        DscError::NotFound => {
            format!("DSC {operation} is unavailable because dsc is not installed.")
        }
        DscError::Timeout(_) => format!("DSC {operation} exceeded the bounded timeout."),
        DscError::Spawn(_) | DscError::Io(_) => format!("DSC {operation} could not start."),
        DscError::Parse(_) => format!("DSC {operation} returned an unsupported result."),
        DscError::Yaml(_) => format!("DSC {operation} could not serialize the document."),
        DscError::SshConnection(_) => format!("DSC {operation} could not reach its adapter."),
        DscError::Execution { .. } => format!("DSC {operation} rejected the document."),
    };
    ServiceErrorKind::Foundation(message)
}

pub fn profile_store_path(profile_id: &str) -> Result<PathBuf, ServiceErrorKind> {
    let profile_id = normalize_profile_id(profile_id);
    if !is_valid_profile_id(&profile_id) {
        return Err(ServiceErrorKind::InvalidRequest(
            "Profile identifiers must be 1-64 characters of letters, numbers, underscores, or hyphens."
                .into(),
        ));
    }
    let local_app_data = std::env::var_os("LOCALAPPDATA").ok_or_else(|| {
        ServiceErrorKind::InvalidRequest(
            "LOCALAPPDATA is required to locate the profile-local Pedantic store.".into(),
        )
    })?;
    Ok(PathBuf::from(local_app_data)
        .join("Pedantic")
        .join("profiles")
        .join(&profile_id)
        .join("pluresdb"))
}

#[derive(Debug, Deserialize, Serialize)]
pub struct LocalServiceRequest {
    pub id: String,
    pub method: String,
    #[serde(rename = "profileId")]
    pub profile_id: String,
    pub authorization: String,
    #[serde(default)]
    pub params: serde_json::Value,
}

fn validate_local_service_request(request: &serde_json::Value) -> Result<(), String> {
    let schema: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../contracts/v1/local-service-request.schema.json"
    )))
    .expect("embedded local service request contract parses");
    let validator = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(&schema)
        .expect("embedded local service request contract compiles");
    validator.validate(request).map_err(|errors| {
        errors
            .map(|error| error.to_string())
            .collect::<Vec<_>>()
            .join("; ")
    })
}

#[derive(Debug, Deserialize, Serialize, PartialEq)]
pub struct LocalServiceResponse {
    pub id: Option<String>,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ServiceError>,
}

#[derive(Debug, Deserialize, Serialize, PartialEq)]
pub struct ServiceError {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum ServiceErrorKind {
    #[error("invalid request: {0}")]
    InvalidRequest(String),
    #[error("service I/O failed: {0}")]
    Io(#[from] io::Error),
    #[error("service foundation failed: {0}")]
    Foundation(String),
}

pub fn pipe_name_for_profile(
    profile_id: &str,
    authorization_token: &str,
) -> Result<String, ServiceErrorKind> {
    let profile_id = normalize_profile_id(profile_id);
    if !is_valid_profile_id(&profile_id) {
        return Err(ServiceErrorKind::InvalidRequest(
            "Profile identifiers must be 1-64 characters of letters, numbers, underscores, or hyphens."
                .into(),
        ));
    }
    validate_token(authorization_token)?;

    #[cfg(windows)]
    {
        let sid = current_user_sid()?;
        Ok(pipe_name_for_identity(
            &profile_id,
            authorization_token,
            &sid,
        ))
    }

    #[cfg(not(windows))]
    Ok(pipe_name_for_identity(
        &profile_id,
        authorization_token,
        "local",
    ))
}

/// Authenticated client for the profile-scoped local service.
///
/// This is intentionally a transport-only adapter. The caller submits a typed
/// request and receives the service result; PX decisions and PluresDB access
/// remain service-owned.
pub struct LocalServiceClient {
    profile_id: String,
    authorization_token: String,
    pipe_name: String,
}

impl LocalServiceClient {
    pub fn for_profile(
        profile_id: &str,
        authorization_token: &str,
    ) -> Result<Self, ServiceErrorKind> {
        let pipe_name = pipe_name_for_profile(profile_id, authorization_token)?;
        Ok(Self {
            profile_id: normalize_profile_id(profile_id),
            authorization_token: authorization_token.to_owned(),
            pipe_name,
        })
    }

    pub async fn call(
        &self,
        id: impl Into<String>,
        method: impl Into<String>,
        params: serde_json::Value,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        #[cfg(windows)]
        {
            use tokio::net::windows::named_pipe::ClientOptions;

            let connection = ClientOptions::new()
                .open(&self.pipe_name)
                .map_err(ServiceErrorKind::Io)?;
            exchange(
                connection,
                LocalServiceRequest {
                    id: id.into(),
                    method: method.into(),
                    profile_id: self.profile_id.clone(),
                    authorization: self.authorization_token.clone(),
                    params,
                },
            )
            .await
        }

        #[cfg(not(windows))]
        {
            let _ = (id, method, params);
            Err(ServiceErrorKind::InvalidRequest(
                "The local service client requires Windows named pipes.".into(),
            ))
        }
    }

    pub async fn health(&self) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call("service-health", "service.health", serde_json::Value::Null)
            .await
    }

    pub async fn list_evidence(&self) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call("evidence-list", "evidence.list", serde_json::Value::Null)
            .await
    }

    pub async fn record_transfer(
        &self,
        event: TransferEvent,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call(
            "transfer-record",
            "transfer.record",
            serde_json::json!({ "event": event }),
        )
        .await
    }

    pub async fn reconcile_transfers(
        &self,
        registry: FederatedTransferRegistry,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call(
            "transfer-reconcile",
            "transfer.reconcile",
            serde_json::json!({ "registry": registry }),
        )
        .await
    }

    pub async fn query_transfers(
        &self,
        query: TransferQuery,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call(
            "transfer-query",
            "transfer.query",
            serde_json::to_value(query).map_err(|error| {
                ServiceErrorKind::InvalidRequest(format!("Transfer query encoding failed: {error}"))
            })?,
        )
        .await
    }

    pub async fn transfer_report(
        &self,
        operation_id: impl Into<String>,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call(
            "transfer-report",
            "transfer.report",
            serde_json::json!({ "operationId": operation_id.into() }),
        )
        .await
    }

    pub async fn retain_transfer_history(
        &self,
        retain_after: u64,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        self.call(
            "transfer-retain",
            "transfer.retain",
            serde_json::json!({ "retainAfter": retain_after }),
        )
        .await
    }
}

async fn exchange<T>(
    connection: T,
    request: LocalServiceRequest,
) -> Result<LocalServiceResponse, ServiceErrorKind>
where
    T: AsyncRead + AsyncWrite + Unpin,
{
    let request = serde_json::to_vec(&request).map_err(|error| {
        ServiceErrorKind::InvalidRequest(format!("Request encoding failed: {error}"))
    })?;
    if request.len() > MAX_FRAME_BYTES {
        return Err(ServiceErrorKind::InvalidRequest(
            "Request exceeds the local service frame limit.".into(),
        ));
    }

    let mut connection = connection;
    connection.write_all(&request).await?;
    connection.write_all(b"\n").await?;

    let mut response = String::new();
    let mut reader = BufReader::new(connection);
    let bytes_read = reader.read_line(&mut response).await?;
    if bytes_read == 0 {
        return Err(ServiceErrorKind::Io(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "Local service closed the pipe before responding.",
        )));
    }
    if response.len() > MAX_FRAME_BYTES {
        return Err(ServiceErrorKind::InvalidRequest(
            "Local service response exceeds the frame limit.".into(),
        ));
    }
    serde_json::from_str(&response).map_err(|error| {
        ServiceErrorKind::InvalidRequest(format!("Response decoding failed: {error}"))
    })
}

pub struct RequestHandlers<F, G, H, I, J, K, L, M, N, P> {
    pub evidence: F,
    pub admission: G,
    pub validation: H,
    pub inventory: I,
    pub compliance: J,
    pub observation: K,
    pub remediation: L,
    pub approval: M,
    pub execution: N,
    pub transfer: P,
}

impl<F, G, H, I, J, K, L, M, N, P> RequestHandlers<F, G, H, I, J, K, L, M, N, P> {
    #[cfg(test)]
    fn with_transfer<Q>(self, transfer: Q) -> RequestHandlers<F, G, H, I, J, K, L, M, N, Q> {
        RequestHandlers {
            evidence: self.evidence,
            admission: self.admission,
            validation: self.validation,
            inventory: self.inventory,
            compliance: self.compliance,
            observation: self.observation,
            remediation: self.remediation,
            approval: self.approval,
            execution: self.execution,
            transfer,
        }
    }
}

#[cfg(any(windows, test))]
#[derive(Deserialize)]
struct TransferEventRequest {
    event: TransferEvent,
}

#[cfg(any(windows, test))]
#[derive(Deserialize)]
struct TransferRegistryRequest {
    registry: FederatedTransferRegistry,
}

#[cfg(any(windows, test))]
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransferReportRequest {
    operation_id: String,
}

#[cfg(any(windows, test))]
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransferRetentionRequest {
    retain_after: u64,
}

#[cfg(any(windows, test))]
async fn dispatch_transfer_request(
    foundation: &ServiceFoundation,
    method: &str,
    params: serde_json::Value,
) -> Result<serde_json::Value, ServiceErrorKind> {
    fn parse<T: serde::de::DeserializeOwned>(
        method: &str,
        params: serde_json::Value,
    ) -> Result<T, ServiceErrorKind> {
        serde_json::from_value(params).map_err(|error| {
            ServiceErrorKind::InvalidRequest(format!("{method} parameters are invalid: {error}"))
        })
    }

    match method {
        "transfer.record" => {
            let request: TransferEventRequest = parse(method, params)?;
            let recorded = foundation.record_transfer_event(request.event).await?;
            Ok(serde_json::json!({ "recorded": recorded }))
        }
        "transfer.reconcile" => {
            let request: TransferRegistryRequest = parse(method, params)?;
            foundation
                .reconcile_transfer_registry(request.registry)
                .await?;
            Ok(serde_json::json!({ "reconciled": true }))
        }
        "transfer.query" => {
            let query: TransferQuery = parse(method, params)?;
            Ok(serde_json::json!(foundation.query_transfers(&query).await))
        }
        "transfer.report" => {
            let request: TransferReportRequest = parse(method, params)?;
            Ok(serde_json::json!(
                foundation.transfer_report(&request.operation_id).await
            ))
        }
        "transfer.retain" => {
            let request: TransferRetentionRequest = parse(method, params)?;
            foundation
                .retain_terminal_transfer_history(request.retain_after)
                .await;
            Ok(serde_json::json!({ "retained": true }))
        }
        _ => Err(ServiceErrorKind::InvalidRequest(
            "Transfer method is not registered.".into(),
        )),
    }
}

pub async fn handle_request<
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    P,
    AdmissionFuture,
    ValidationFuture,
    InventoryFuture,
    ComplianceFuture,
    ObservationFuture,
    RemediationFuture,
    ApprovalFuture,
    ExecutionFuture,
    TransferFuture,
>(
    frame: &str,
    expected_profile: &str,
    expected_token: &str,
    version: &str,
    chronos_entries: usize,
    handlers: RequestHandlers<F, G, H, I, J, K, L, M, N, P>,
) -> LocalServiceResponse
where
    F: FnOnce() -> EvidencePage,
    G: FnOnce(ConfigurationAdmissionRequest) -> AdmissionFuture,
    H: FnOnce(ConfigurationValidationRequest) -> ValidationFuture,
    I: FnOnce(InventoryObservationRequest) -> InventoryFuture,
    J: FnOnce(ComplianceRequest) -> ComplianceFuture,
    K: FnOnce(ComplianceObservationRequest) -> ObservationFuture,
    L: FnOnce(RemediationRequest) -> RemediationFuture,
    M: FnOnce(RemediationApprovalRequest) -> ApprovalFuture,
    N: FnOnce(RemediationExecutionRequest) -> ExecutionFuture,
    P: FnOnce(String, serde_json::Value) -> TransferFuture,
    AdmissionFuture: Future<Output = Result<ConfigurationAdmission, ServiceErrorKind>>,
    ValidationFuture: Future<Output = Result<ConfigurationValidation, ServiceErrorKind>>,
    InventoryFuture: Future<Output = Result<InventoryObservation, ServiceErrorKind>>,
    ComplianceFuture: Future<Output = Result<ComplianceDecision, ServiceErrorKind>>,
    ObservationFuture: Future<Output = Result<ComplianceObservation, ServiceErrorKind>>,
    RemediationFuture: Future<Output = Result<RemediationDecision, ServiceErrorKind>>,
    ApprovalFuture: Future<Output = Result<RemediationApproval, ServiceErrorKind>>,
    ExecutionFuture: Future<Output = Result<RemediationExecution, ServiceErrorKind>>,
    TransferFuture: Future<Output = Result<serde_json::Value, ServiceErrorKind>>,
{
    let request_value = match serde_json::from_str::<serde_json::Value>(frame) {
        Ok(request) => request,
        Err(error) => {
            return response(
                None,
                false,
                None,
                Some((
                    "invalid_request",
                    format!("Request must be valid JSON: {error}"),
                )),
            );
        }
    };
    let request = match serde_json::from_value::<LocalServiceRequest>(request_value.clone()) {
        Ok(request) => request,
        Err(error) => {
            return response(
                None,
                false,
                None,
                Some((
                    "invalid_request",
                    format!("Request must be valid JSON: {error}"),
                )),
            );
        }
    };

    let expected_profile = normalize_profile_id(expected_profile);
    let request_profile_id = normalize_profile_id(&request.profile_id);

    if !constant_time_equal(&request.authorization, expected_token) {
        return response(
            Some(request.id),
            false,
            None,
            Some(("unauthorized", "Local service authorization failed.".into())),
        );
    }
    if request_profile_id != expected_profile {
        return response(
            Some(request.id),
            false,
            None,
            Some((
                "unauthorized",
                "Request profile does not match this service instance.".into(),
            )),
        );
    }
    if is_registered_method(&request.method)
        && let Err(error) = validate_local_service_request(&request_value)
    {
        return response(
            Some(request.id),
            false,
            None,
            Some(("invalid_request", error)),
        );
    }
    match request.method.as_str() {
        "service.health" => response(
            Some(request.id),
            true,
            Some(serde_json::json!({
                "profileId": expected_profile,
                "service": "pedantic-service",
                "version": version,
                "chronosEntries": chronos_entries,
            })),
            None,
        ),
        "evidence.list" => {
            let evidence = (handlers.evidence)();
            response(
                Some(request.id),
                true,
                Some(serde_json::json!({
                    "entries": evidence.entries,
                    "truncated": evidence.truncated,
                })),
                None,
            )
        }
        "configuration.admit" => {
            let admission_request = match serde_json::from_value(request.params) {
                Ok(admission_request) => admission_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("configuration.admit parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.admission)(admission_request).await {
                Ok(result) if result.decision == "accepted" => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Ok(result) => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("configuration_rejected", result.reason.clone())),
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("px_evaluation_failed", error.to_string())),
                ),
            }
        }
        "configuration.validate" => {
            let validation_request = match serde_json::from_value(request.params) {
                Ok(validation_request) => validation_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("configuration.validate parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.validation)(validation_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("configuration_rejected", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("validation_failed", error.to_string())),
                ),
            }
        }
        "inventory.observe" => {
            let inventory_request = match serde_json::from_value(request.params) {
                Ok(inventory_request) => inventory_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("inventory.observe parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.inventory)(inventory_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("inventory_rejected", result.reason.clone())),
                ),
                Ok(result) if result.decision == "failed" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("inventory_observation_failed", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("inventory_observation_failed", error.to_string())),
                ),
            }
        }
        "compliance.request" => {
            let compliance_request = match serde_json::from_value(request.params) {
                Ok(compliance_request) => compliance_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("compliance.request parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.compliance)(compliance_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("compliance_rejected", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("compliance_failed", error.to_string())),
                ),
            }
        }
        "compliance.observe" => {
            let observation_request = match serde_json::from_value(request.params) {
                Ok(observation_request) => observation_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("compliance.observe parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.observation)(observation_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("compliance_rejected", result.reason.clone())),
                ),
                Ok(result) if result.decision == "failed" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("compliance_observation_failed", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("compliance_observation_failed", error.to_string())),
                ),
            }
        }
        "remediation.request" => {
            let remediation_request = match serde_json::from_value(request.params) {
                Ok(remediation_request) => remediation_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("remediation.request parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.remediation)(remediation_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("remediation_rejected", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("remediation_failed", error.to_string())),
                ),
            }
        }
        "remediation.approve" | "approval.record" => {
            let approval_request: RemediationApprovalRequest =
                match serde_json::from_value(request.params) {
                    Ok(approval_request) => approval_request,
                    Err(error) => {
                        return response(
                            Some(request.id),
                            false,
                            None,
                            Some((
                                "invalid_request",
                                format!("remediation.approve parameters are invalid: {error}"),
                            )),
                        );
                    }
                };
            match (handlers.approval)(approval_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("remediation_rejected", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("remediation_failed", error.to_string())),
                ),
            }
        }
        "effect.authorize" => {
            let mut approval_request: RemediationApprovalRequest =
                match serde_json::from_value(request.params) {
                    Ok(approval_request) => approval_request,
                    Err(error) => {
                        return response(
                            Some(request.id),
                            false,
                            None,
                            Some((
                                "invalid_request",
                                format!("effect.authorize parameters are invalid: {error}"),
                            )),
                        );
                    }
                };
            approval_request.authorize = true;
            match (handlers.approval)(approval_request).await {
                Ok(result) => match result.authorization {
                    Some(authorization) => response(
                        Some(request.id),
                        true,
                        Some(serde_json::json!(authorization)),
                        None,
                    ),
                    None => response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "authorization_failed",
                            "Effect authorization returned no signed grant.".into(),
                        )),
                    ),
                },
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("remediation_failed", error.to_string())),
                ),
            }
        }
        "remediation.execute" => {
            let execution_request = match serde_json::from_value(request.params) {
                Ok(execution_request) => execution_request,
                Err(error) => {
                    return response(
                        Some(request.id),
                        false,
                        None,
                        Some((
                            "invalid_request",
                            format!("remediation.execute parameters are invalid: {error}"),
                        )),
                    );
                }
            };
            match (handlers.execution)(execution_request).await {
                Ok(result) if result.decision == "rejected" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("remediation_rejected", result.reason.clone())),
                ),
                Ok(result) if result.decision == "failed" => response(
                    Some(request.id),
                    false,
                    Some(serde_json::json!(result)),
                    Some(("remediation_failed", result.reason.clone())),
                ),
                Ok(result) => response(
                    Some(request.id),
                    true,
                    Some(serde_json::json!(result)),
                    None,
                ),
                Err(error) => response(
                    Some(request.id),
                    false,
                    None,
                    Some(("remediation_failed", error.to_string())),
                ),
            }
        }
        "transfer.record" | "transfer.reconcile" | "transfer.query" | "transfer.report"
        | "transfer.retain" => match (handlers.transfer)(request.method, request.params).await {
            Ok(result) => response(Some(request.id), true, Some(result), None),
            Err(error) => response(
                Some(request.id),
                false,
                None,
                Some(("transfer_failed", error.to_string())),
            ),
        },
        _ => response(
            Some(request.id),
            false,
            None,
            Some((
                "method_not_found",
                format!("Method '{}' is not registered.", request.method),
            )),
        ),
    }
}

fn is_registered_method(method: &str) -> bool {
    matches!(
        method,
        "service.health"
            | "evidence.list"
            | "configuration.admit"
            | "configuration.validate"
            | "inventory.observe"
            | "compliance.request"
            | "compliance.observe"
            | "remediation.request"
            | "remediation.approve"
            | "approval.record"
            | "effect.authorize"
            | "remediation.execute"
            | "transfer.record"
            | "transfer.reconcile"
            | "transfer.query"
            | "transfer.report"
            | "transfer.retain"
    )
}

pub fn validate_token(token: &str) -> Result<(), ServiceErrorKind> {
    if token.chars().count() < 32 {
        return Err(ServiceErrorKind::InvalidRequest(
            "PEDANTIC_LOCAL_TOKEN must contain at least 32 characters.".into(),
        ));
    }
    Ok(())
}

#[cfg(windows)]
pub async fn run(
    pipe_name: &str,
    profile_id: &str,
    token: &str,
    version: &str,
    foundation: ServiceFoundation,
) -> Result<(), ServiceErrorKind> {
    let foundation = Arc::new(foundation);
    let mut pipe_security = PipeSecurity::for_current_user()?;
    let mut server = create_server_pipe(pipe_name, true, &mut pipe_security)?;
    foundation.record_start(version);
    loop {
        server.connect().await?;
        let connection = server;
        server = create_server_pipe(pipe_name, false, &mut pipe_security)?;
        let profile_id = profile_id.to_owned();
        let token = token.to_owned();
        let version = version.to_owned();
        let foundation = Arc::clone(&foundation);
        tokio::spawn(async move {
            let _ = serve_connection(connection, &profile_id, &token, &version, foundation).await;
        });
    }
}

#[cfg(windows)]
fn create_server_pipe(
    pipe_name: &str,
    first_instance: bool,
    pipe_security: &mut PipeSecurity,
) -> Result<tokio::net::windows::named_pipe::NamedPipeServer, ServiceErrorKind> {
    use tokio::net::windows::named_pipe::ServerOptions;

    let mut options = ServerOptions::new();
    options.first_pipe_instance(first_instance);
    options.reject_remote_clients(true);
    let mut attributes = pipe_security.attributes();
    // SAFETY: `attributes` and its security descriptor remain valid throughout
    // the synchronous CreateNamedPipe call; Windows copies the descriptor.
    unsafe {
        options
            .create_with_security_attributes_raw(
                pipe_name,
                (&mut attributes as *mut SECURITY_ATTRIBUTES).cast(),
            )
            .map_err(ServiceErrorKind::Io)
    }
}

#[cfg(not(windows))]
pub async fn run(
    _pipe_name: &str,
    _profile_id: &str,
    _token: &str,
    _version: &str,
    _foundation: ServiceFoundation,
) -> Result<(), ServiceErrorKind> {
    Err(ServiceErrorKind::InvalidRequest(
        "The local service host requires Windows named pipes.".into(),
    ))
}

#[cfg(windows)]
async fn serve_connection(
    mut connection: tokio::net::windows::named_pipe::NamedPipeServer,
    profile_id: &str,
    token: &str,
    version: &str,
    foundation: Arc<ServiceFoundation>,
) -> Result<(), ServiceErrorKind> {
    let mut reader = BufReader::new(&mut connection);
    let mut frame = Vec::new();
    while reader.read_until(b'\n', &mut frame).await? > 0 {
        if frame.len() > MAX_FRAME_BYTES {
            break;
        }
        let line = String::from_utf8_lossy(&frame).trim().to_owned();
        if !line.is_empty() {
            let transfer_foundation = Arc::clone(&foundation);
            let response = handle_request(
                &line,
                profile_id,
                token,
                version,
                foundation.evidence_count(),
                RequestHandlers {
                    evidence: || foundation.recent_evidence(),
                    admission: |request| foundation.admit_configuration(request),
                    validation: |request| foundation.validate_configuration(request),
                    inventory: |request| foundation.observe_inventory(request),
                    compliance: |request| foundation.request_compliance(request),
                    observation: |request| foundation.observe_compliance(request),
                    remediation: |request| foundation.request_remediation(request),
                    approval: |request: RemediationApprovalRequest| async {
                        if request.authorize {
                            foundation.authorize_remediation(request).await
                        } else {
                            foundation.approve_remediation(request).await
                        }
                    },
                    execution: |request| foundation.execute_remediation(request),
                    transfer: |method: String, params| async move {
                        dispatch_transfer_request(&transfer_foundation, &method, params).await
                    },
                },
            )
            .await;
            let encoded = serde_json::to_vec(&response).map_err(|error| {
                ServiceErrorKind::InvalidRequest(format!("Response encoding failed: {error}"))
            })?;
            reader.get_mut().write_all(&encoded).await?;
            reader.get_mut().write_all(b"\n").await?;
        }
        frame.clear();
    }
    Ok(())
}

fn response(
    id: Option<String>,
    ok: bool,
    result: Option<serde_json::Value>,
    error: Option<(&'static str, String)>,
) -> LocalServiceResponse {
    LocalServiceResponse {
        id,
        ok,
        result,
        error: error.map(|(code, message)| ServiceError {
            code: code.to_owned(),
            message,
        }),
    }
}

fn normalize_profile_id(profile_id: &str) -> String {
    profile_id.trim().to_ascii_lowercase()
}

fn is_valid_profile_id(profile_id: &str) -> bool {
    !profile_id.is_empty()
        && profile_id.len() <= 64
        && profile_id.bytes().enumerate().all(|(index, byte)| {
            byte.is_ascii_alphanumeric() || byte == b'_' || (byte == b'-' && index > 0)
        })
}

fn pipe_name_for_identity(profile_id: &str, authorization_token: &str, identity: &str) -> String {
    let digest = Sha256::digest(authorization_token.as_bytes());
    let token_hint = digest[..16]
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    #[cfg(windows)]
    let identity_hint = {
        let digest = Sha256::digest(identity.as_bytes());
        digest[..16]
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    };

    #[cfg(windows)]
    return format!(r"\\.\pipe\pedantic-{identity_hint}-{profile_id}-{token_hint}");

    #[cfg(not(windows))]
    format!("/tmp/pedantic-{identity}-{profile_id}-{token_hint}")
}

fn constant_time_equal(left: &str, right: &str) -> bool {
    let mut difference = left.len() ^ right.len();
    for (a, b) in left.bytes().zip(right.bytes()) {
        difference |= usize::from(a ^ b);
    }
    difference == 0
}

#[cfg(windows)]
struct PipeSecurity {
    descriptor: *mut core::ffi::c_void,
}

#[cfg(windows)]
impl PipeSecurity {
    fn for_current_user() -> Result<Self, ServiceErrorKind> {
        let sddl = "D:P(A;;GA;;;OW)\0";
        let wide = sddl.encode_utf16().collect::<Vec<_>>();
        let mut descriptor = std::ptr::null_mut();
        let converted = unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                wide.as_ptr(),
                SDDL_REVISION_1,
                &mut descriptor,
                std::ptr::null_mut(),
            )
        };
        if converted == 0 {
            return Err(ServiceErrorKind::Io(io::Error::last_os_error()));
        }
        Ok(Self { descriptor })
    }

    fn attributes(&mut self) -> SECURITY_ATTRIBUTES {
        SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: self.descriptor,
            bInheritHandle: 0,
        }
    }
}

#[cfg(windows)]
impl Drop for PipeSecurity {
    fn drop(&mut self) {
        if !self.descriptor.is_null() {
            unsafe { LocalFree(self.descriptor) };
        }
    }
}

#[cfg(windows)]
fn current_user_sid() -> Result<String, ServiceErrorKind> {
    let output = std::process::Command::new("whoami")
        .args(["/user", "/fo", "csv", "/nh"])
        .output()?;
    if !output.status.success() {
        return Err(ServiceErrorKind::InvalidRequest(
            "Unable to determine the current Windows user SID.".into(),
        ));
    }
    parse_current_user_sid(&String::from_utf8_lossy(&output.stdout))
}

#[cfg(windows)]
fn parse_current_user_sid(output: &str) -> Result<String, ServiceErrorKind> {
    output
        .split(',')
        .nth(1)
        .map(|value| value.trim().trim_matches('"'))
        .filter(|value| value.starts_with("S-"))
        .map(str::to_owned)
        .ok_or_else(|| ServiceErrorKind::InvalidRequest("Invalid Windows user SID.".into()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use jsonschema::{Draft, JSONSchema, SchemaResolver, SchemaResolverError};
    use pedantic_operation::{OperationEvent, OperationState, TransferObservation};
    use std::sync::Arc;
    use url::Url;

    #[test]
    fn hyperv_plan_admission_rejects_a_document_with_a_stale_plan_id() {
        let source = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../praxis/procedures/pedantic-hyperv-transfer-planning.px"
        ));
        let procedure = px_compiler::parse(source).expect("parse Hyper-V planning procedure");
        let constraint = procedure
            .statements
            .iter()
            .find_map(|statement| match statement {
                Statement::Constraint(constraint)
                    if constraint.name.name == "hyperv_transfer_plan_requires_complete_identity" =>
                {
                    Some(constraint)
                }
                _ => None,
            })
            .expect("find plan admission constraint");
        let document = r#"{"inventory":[{"vmId":"vm-1"}]}"#;
        let plan_id = format!("sha256:{:x}", Sha256::digest(document.as_bytes()));
        let plan = |plan_document: &str| {
            serde_json::json!({
                "plan_id": plan_id,
                "request_id": "request-1",
                "profile_id": "profile-1",
                "plan_document": plan_document,
            })
        };
        let variables = HashMap::from([("plan".into(), plan(document))]);
        let registry = PedanticPxFunctionRegistry;

        assert_eq!(
            px_eval::eval_constraint(constraint, &variables, &registry).unwrap(),
            ConstraintOutcome::Satisfied
        );
        let replaced_document = HashMap::from([(
            "plan".into(),
            plan(r#"{"inventory":[{"vmId":"vm-2"}]}"#),
        )]);
        assert!(matches!(
            px_eval::eval_constraint(constraint, &replaced_document, &registry).unwrap(),
            ConstraintOutcome::Violated { .. }
        ));
    }

    struct ContractResolver {
        evidence_schema: Arc<serde_json::Value>,
    }

    impl SchemaResolver for ContractResolver {
        fn resolve(
            &self,
            _root_schema: &serde_json::Value,
            url: &Url,
            _original_reference: &str,
        ) -> Result<Arc<serde_json::Value>, SchemaResolverError> {
            if url.as_str()
                == "https://schemas.pedantic.dev/contracts/v1/evidence-summary.schema.json"
            {
                Ok(Arc::clone(&self.evidence_schema))
            } else {
                Err(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    format!("unsupported local contract reference: {url}"),
                )
                .into())
            }
        }
    }

    #[tokio::test]
    async fn agent_sync_is_signed_idempotent_gap_aware_and_revocable() {
        let directory = tempfile::tempdir().unwrap();
        let service = ServiceFoundation::open_at("profile", directory.path(), "test").unwrap();
        let signing_key = SigningKey::from_bytes(&[11; 32]);
        service
            .enroll_agent(
                AgentEnrollment {
                    schema_version: "pedantic.agent-enrollment.v1".into(),
                    enrollment_id: "enrollment".into(),
                    agent_id: "agent".into(),
                    target_id: "target".into(),
                    profile_id: "profile".into(),
                    public_key: URL_SAFE_NO_PAD.encode(signing_key.verifying_key().as_bytes()),
                    issued_at: 1,
                    expires_at: 100,
                    secret_references: Vec::new(),
                },
                1,
            )
            .await
            .unwrap();
        let observation = pedantic_agent::AgentObservation {
            schema_version: "pedantic.effect-observation.v1".into(),
            event_id: "event-1".into(),
            command_id: "command".into(),
            operation_id: "operation".into(),
            step_id: "step".into(),
            attempt_id: "attempt".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            sequence: 1,
            status: "completed".into(),
            causation_id: "cause".into(),
            correlation_id: "correlation".into(),
            redaction_class: pedantic_operation::RedactionClass::MetadataOnly,
            output_digest: None,
        };
        let batch = AgentObservationBatch::sign(
            "batch".into(),
            "profile".into(),
            vec![observation.clone()],
            "key".into(),
            &signing_key,
        )
        .unwrap();
        assert_eq!(service.sync_agent(batch.clone(), 2).await.unwrap().accepted_observations, 1);
        assert_eq!(service.sync_agent(batch, 2).await.unwrap().accepted_observations, 0);
        service.revoke_agent("agent", 2).await.unwrap();
        assert!(service.sync_agent(
            AgentObservationBatch::sign(
                "batch-2".into(),
                "profile".into(),
                vec![pedantic_agent::AgentObservation {
                    event_id: "event-2".into(),
                    sequence: 2,
                    ..observation
                }],
                "key".into(),
                &signing_key,
            )
            .unwrap(),
            2,
        ).await.is_err());
    }

    fn assert_contract(schema_source: &str, instance: serde_json::Value) {
        let schema = serde_json::from_str(schema_source).expect("parse JSON Schema");
        let validator = JSONSchema::options()
            .with_draft(Draft::Draft7)
            .compile(&schema)
            .expect("compile JSON Schema");
        if let Err(errors) = validator.validate(&instance) {
            let messages = errors.map(|error| error.to_string()).collect::<Vec<_>>();
            panic!("contract validation failed: {messages:?}");
        }
    }

    fn assert_contract_rejects(schema_source: &str, instance: serde_json::Value) {
        let schema = serde_json::from_str(schema_source).expect("parse JSON Schema");
        let validator = JSONSchema::options()
            .with_draft(Draft::Draft7)
            .compile(&schema)
            .expect("compile JSON Schema");
        assert!(
            !validator.is_valid(&instance),
            "contract unexpectedly accepted {instance}"
        );
    }

    fn assert_response_contract(
        schema_source: &str,
        evidence_schema_source: &str,
        instance: serde_json::Value,
    ) {
        let schema = serde_json::from_str(schema_source).expect("parse response JSON Schema");
        let evidence_schema =
            serde_json::from_str(evidence_schema_source).expect("parse evidence JSON Schema");
        let validator = JSONSchema::options()
            .with_draft(Draft::Draft7)
            .with_resolver(ContractResolver {
                evidence_schema: Arc::new(evidence_schema),
            })
            .compile(&schema)
            .expect("compile response JSON Schema");
        if let Err(errors) = validator.validate(&instance) {
            let messages = errors.map(|error| error.to_string()).collect::<Vec<_>>();
            panic!("response contract validation failed: {messages:?}");
        }
    }

    fn assert_response_contract_rejects(
        schema_source: &str,
        evidence_schema_source: &str,
        instance: serde_json::Value,
    ) {
        let schema = serde_json::from_str(schema_source).expect("parse response JSON Schema");
        let evidence_schema =
            serde_json::from_str(evidence_schema_source).expect("parse evidence JSON Schema");
        let validator = JSONSchema::options()
            .with_draft(Draft::Draft7)
            .with_resolver(ContractResolver {
                evidence_schema: Arc::new(evidence_schema),
            })
            .compile(&schema)
            .expect("compile response JSON Schema");
        assert!(
            !validator.is_valid(&instance),
            "response contract unexpectedly accepted {instance}"
        );
    }

    #[test]
    fn token_length_matches_schema_character_rule() {
        assert!(validate_token(&"é".repeat(32)).is_ok());
        assert!(validate_token(&"é".repeat(31)).is_err());
    }

    #[test]
    fn effect_authorization_signing_key_persists_with_private_permissions() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let first =
            load_or_create_authorization_signing_key(directory.path()).expect("create signing key");
        let reopened =
            load_or_create_authorization_signing_key(directory.path()).expect("reload signing key");
        assert_eq!(
            authorization_signing_key_id(&first),
            authorization_signing_key_id(&reopened)
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let permissions =
                std::fs::metadata(directory.path().join(".pedantic-effect-authorization-key"))
                    .expect("key permissions")
                    .permissions()
                    .mode();
            assert_eq!(permissions & 0o777, 0o600);
        }
    }

    type TestReady<T> = std::future::Ready<Result<T, ServiceErrorKind>>;

    type TestRequestHandlers = RequestHandlers<
        fn() -> EvidencePage,
        fn(ConfigurationAdmissionRequest) -> TestReady<ConfigurationAdmission>,
        fn(ConfigurationValidationRequest) -> TestReady<ConfigurationValidation>,
        fn(InventoryObservationRequest) -> TestReady<InventoryObservation>,
        fn(ComplianceRequest) -> TestReady<ComplianceDecision>,
        fn(ComplianceObservationRequest) -> TestReady<ComplianceObservation>,
        fn(RemediationRequest) -> TestReady<RemediationDecision>,
        fn(RemediationApprovalRequest) -> TestReady<RemediationApproval>,
        fn(RemediationExecutionRequest) -> TestReady<RemediationExecution>,
        fn(String, serde_json::Value) -> TestReady<serde_json::Value>,
    >;

    fn empty_evidence() -> EvidencePage {
        EvidencePage {
            entries: Vec::new(),
            truncated: false,
        }
    }

    fn reject_request<T, U>(_: T) -> TestReady<U> {
        std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
    }

    fn reject_transfer(_: String, _: serde_json::Value) -> TestReady<serde_json::Value> {
        std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
    }

    async fn transfer_api_request(
        foundation: &ServiceFoundation,
        method: &str,
        params: serde_json::Value,
    ) -> LocalServiceResponse {
        let frame = serde_json::json!({
            "id": "transfer-api",
            "method": method,
            "profileId": "default",
            "authorization": "0123456789abcdef0123456789abcdef",
            "params": params,
        })
        .to_string();
        let handlers =
            test_handlers().with_transfer(|method: String, params: serde_json::Value| async move {
                dispatch_transfer_request(foundation, &method, params).await
            });
        handle_request(
            &frame,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            handlers,
        )
        .await
    }

    fn test_handlers() -> TestRequestHandlers {
        RequestHandlers {
            evidence: empty_evidence,
            admission: reject_request,
            validation: reject_request,
            inventory: reject_request,
            compliance: reject_request,
            observation: reject_request,
            remediation: reject_request,
            approval: reject_request,
            execution: reject_request,
            transfer: reject_transfer,
        }
    }

    #[tokio::test]
    async fn effect_authorize_returns_the_schema_conforming_grant() {
        let grant: EffectAuthorization = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/effect-authorization.valid.json"
        )))
        .expect("valid authorization fixture");
        let handlers = RequestHandlers {
            evidence: || EvidencePage {
                entries: Vec::new(),
                truncated: false,
            },
            admission: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            validation: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            inventory: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            compliance: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            observation: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            remediation: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            approval: move |request: RemediationApprovalRequest| {
                std::future::ready(Ok(RemediationApproval {
                    approval_id: request.approval_id,
                    request_id: request.request_id,
                    authorization_id: Some(grant.authorization_id.clone()),
                    authorization: Some(grant.clone()),
                    decision: "accepted".into(),
                    constraint_id: "durable_authorization_requires_accepted_approval".into(),
                    reason: "PX accepted the authorization.".into(),
                }))
            },
            execution: |_| {
                std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
            },
            transfer: reject_transfer,
        };
        let response = handle_request(
            r#"{"id":"authorize-1","method":"effect.authorize","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"approvalId":"approval-1","requestId":"request-1","actorId":"actor-1","approved":true}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            handlers,
        )
        .await;
        assert!(response.ok);
        let returned_grant: EffectAuthorization =
            serde_json::from_value(response.result.expect("authorization result"))
                .expect("effect.authorize returns a grant");
        validate_effect_authorization_schema(&returned_grant)
            .expect("returned effect authorization matches published schema");
    }

    #[tokio::test]
    async fn local_service_v1_contracts_validate_fixtures_and_live_responses() {
        const REQUEST_SCHEMA: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/local-service-request.schema.json"
        ));
        const RESPONSE_SCHEMA: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/local-service-response.schema.json"
        ));
        const EVIDENCE_SCHEMA: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/evidence-summary.schema.json"
        ));
        const REQUEST_FIXTURE: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/local-service-health.request.json"
        ));
        const RESPONSE_FIXTURE: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/local-service-health.response.json"
        ));
        const EVIDENCE_FIXTURE: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/fixtures/evidence-summary.json"
        ));

        assert_contract(
            REQUEST_SCHEMA,
            serde_json::from_str(REQUEST_FIXTURE).expect("parse request fixture"),
        );
        assert_contract_rejects(
            REQUEST_SCHEMA,
            serde_json::json!({
                "id": "admission-missing-params",
                "method": "configuration.admit",
                "profileId": "default",
                "authorization": "0123456789abcdef0123456789abcdef"
            }),
        );
        assert_response_contract(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::from_str(RESPONSE_FIXTURE).expect("parse response fixture"),
        );
        assert_response_contract(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::json!({
                "id": "execution-1",
                "ok": true,
                "result": {
                    "executionId": "execution-1",
                    "requestId": "request-1",
                    "revisionId": "revision-1",
                    "decision": "completed",
                    "constraintId": "dsc_config_set",
                    "resourceCount": 2,
                    "compliantResourceCount": null,
                    "driftedResourceCount": null,
                    "reason": "DSC remediation completed locally."
                }
            }),
        );
        assert_response_contract_rejects(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::json!({
                "id": "health-invalid-result",
                "ok": true,
                "result": null
            }),
        );
        assert_response_contract_rejects(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::json!({
                "id": "evidence-invalid-entry",
                "ok": true,
                "result": {
                    "entries": [{
                        "eventId": "chronos-1",
                        "timestamp": 1750000000,
                        "actor": "pedantic-service",
                        "action": "create",
                        "level": "info",
                        "storeKey": "must-not-project"
                    }],
                    "truncated": false
                }
            }),
        );
        assert_contract(
            EVIDENCE_SCHEMA,
            serde_json::from_str(EVIDENCE_FIXTURE).expect("parse evidence fixture"),
        );

        let response = handle_request(
            REQUEST_FIXTURE,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            test_handlers(),
        )
        .await;
        assert_response_contract(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::to_value(response).expect("serialize live response"),
        );

        let unauthorized = handle_request(
            REQUEST_FIXTURE,
            "default",
            "fedcba9876543210fedcba9876543210",
            "0.1.0",
            0,
            test_handlers(),
        )
        .await;
        assert_response_contract(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::to_value(unauthorized).expect("serialize rejected response"),
        );
        let unknown_field = handle_request(
            r#"{"id":"health-extra","method":"service.health","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","unexpected":true}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            test_handlers(),
        )
        .await;
        assert!(!unknown_field.ok);
        assert_eq!(
            unknown_field.error.expect("schema rejection").code,
            "invalid_request"
        );

        let rejected_request = serde_json::json!({
            "id": "admission-1",
            "method": "configuration.admit",
            "profileId": "default",
            "authorization": "0123456789abcdef0123456789abcdef",
            "params": {
                "revisionId": "revision-1",
                "sourceDigest": "digest-1"
            }
        })
        .to_string();
        let rejected = handle_request(
            &rejected_request,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| {
                    std::future::ready(Ok(ConfigurationAdmission {
                        revision_id: "revision-1".into(),
                        decision: "rejected".into(),
                        constraint_id: "configuration_requires_source_digest".into(),
                        reason: "Source digest is required.".into(),
                    }))
                },
                validation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                inventory: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                compliance: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                observation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                remediation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                approval: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                execution: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                transfer: reject_transfer,
            },
        )
        .await;
        assert_response_contract(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::to_value(rejected).expect("serialize policy-rejected response"),
        );
    }

    #[tokio::test]
    async fn health_requires_the_profile_and_token() {
        let response = handle_request(
            r#"{"id":"1","method":"service.health","profileId":"default","authorization":"0123456789abcdef0123456789abcdef"}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            test_handlers(),
        )
        .await;
        assert!(response.ok);
    }

    #[tokio::test]
    async fn rejects_unregistered_methods() {
        let response = handle_request(
            r#"{"id":"1","method":"effect.execute","profileId":"default","authorization":"0123456789abcdef0123456789abcdef"}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            test_handlers(),
        )
        .await;
        assert_eq!(response.error.unwrap().code, "method_not_found");
    }

    #[test]
    fn pipe_name_is_bound_to_the_service_secret() {
        let first = pipe_name_for_identity(
            "default",
            "0123456789abcdef0123456789abcdef",
            "S-1-5-21-test",
        );
        let second = pipe_name_for_identity(
            "default",
            "fedcba9876543210fedcba9876543210",
            "S-1-5-21-test",
        );
        assert_ne!(first, second);
        assert!(first.contains("-default-"));
        #[cfg(windows)]
        assert!(!first.contains("S-1-5-21-test"));
        #[cfg(not(windows))]
        assert!(first.contains("S-1-5-21-test"));
    }

    #[test]
    fn local_service_client_reuses_the_profile_bound_endpoint() {
        let token = "0123456789abcdef0123456789abcdef";
        let client = LocalServiceClient::for_profile("Default", token)
            .expect("construct authenticated local service client");

        assert_eq!(client.profile_id, "default");
        assert_eq!(
            client.pipe_name,
            pipe_name_for_profile("default", token).expect("derive profile endpoint")
        );
    }

    fn transport_request() -> LocalServiceRequest {
        LocalServiceRequest {
            id: "request-1".into(),
            method: "service.health".into(),
            profile_id: "default".into(),
            authorization: "0123456789abcdef0123456789abcdef".into(),
            params: serde_json::Value::Null,
        }
    }

    #[tokio::test]
    async fn transport_exchange_frames_requests_and_decodes_responses() {
        let (client, mut server) = tokio::io::duplex(MAX_FRAME_BYTES);
        let server_task = tokio::spawn(async move {
            let mut request = String::new();
            tokio::io::AsyncBufReadExt::read_line(
                &mut tokio::io::BufReader::new(&mut server),
                &mut request,
            )
            .await
            .expect("read framed request");
            assert!(request.ends_with('\n'));
            assert_eq!(
                serde_json::from_str::<LocalServiceRequest>(&request)
                    .expect("decode request")
                    .method,
                "service.health"
            );
            server
                .write_all(
                    br#"{"id":"request-1","ok":true,"result":{"status":"ok"}}
"#,
                )
                .await
                .expect("write response");
        });

        let response = exchange(client, transport_request())
            .await
            .expect("exchange response");
        server_task.await.expect("server task");
        assert_eq!(response.id.as_deref(), Some("request-1"));
        assert_eq!(response.result, Some(serde_json::json!({"status": "ok"})));
    }

    #[tokio::test]
    async fn transport_exchange_rejects_malformed_and_eof_responses() {
        let (client, mut server) = tokio::io::duplex(MAX_FRAME_BYTES);
        let malformed = tokio::spawn(async move {
            server
                .write_all(b"not-json\n")
                .await
                .expect("write malformed response");
        });
        let error = exchange(client, transport_request())
            .await
            .expect_err("malformed response must fail");
        malformed.await.expect("malformed server task");
        assert!(
            matches!(error, ServiceErrorKind::InvalidRequest(message) if message.contains("Response decoding failed"))
        );

        let (client, mut server) = tokio::io::duplex(MAX_FRAME_BYTES);
        let eof = tokio::spawn(async move {
            let mut request = String::new();
            tokio::io::AsyncBufReadExt::read_line(
                &mut tokio::io::BufReader::new(&mut server),
                &mut request,
            )
            .await
            .expect("read request before EOF");
        });
        let error = exchange(client, transport_request())
            .await
            .expect_err("EOF response must fail");
        eof.await.expect("EOF server task");
        assert!(matches!(
            error,
            ServiceErrorKind::Io(error) if error.kind() == io::ErrorKind::UnexpectedEof
        ));
    }

    #[tokio::test]
    async fn transport_exchange_enforces_request_and_response_frame_limits() {
        let (client, _server) = tokio::io::duplex(MAX_FRAME_BYTES);
        let mut request = transport_request();
        request.params = serde_json::json!({"payload": "x".repeat(MAX_FRAME_BYTES)});
        let error = exchange(client, request)
            .await
            .expect_err("oversized request must fail");
        assert!(
            matches!(error, ServiceErrorKind::InvalidRequest(message) if message.contains("Request exceeds"))
        );

        let (client, mut server) = tokio::io::duplex(MAX_FRAME_BYTES + 1);
        let server_task = tokio::spawn(async move {
            server
                .write_all(format!("{}\n", "x".repeat(MAX_FRAME_BYTES)).as_bytes())
                .await
                .expect("write oversized response");
        });
        let error = exchange(client, transport_request())
            .await
            .expect_err("oversized response must fail");
        server_task.await.expect("oversized server task");
        assert!(
            matches!(error, ServiceErrorKind::InvalidRequest(message) if message.contains("response exceeds"))
        );
    }

    #[test]
    fn profile_ids_are_canonicalized_before_the_store_key_and_pipe_name() {
        let normalized = normalize_profile_id("Default");
        assert_eq!(normalized, "default");
        assert_eq!(
            pipe_name_for_profile("Default", "0123456789abcdef0123456789abcdef").unwrap(),
            pipe_name_for_profile("default", "0123456789abcdef0123456789abcdef").unwrap()
        );
    }

    #[test]
    fn persistent_profile_store_records_startup_evidence() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let first = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open first profile store");
        first.record_start("0.1.0");
        assert_eq!(first.evidence_count(), 1);
        drop(first);

        let reopened = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("reopen profile store");
        assert_eq!(reopened.evidence_count(), 1);
    }

    #[tokio::test]
    async fn transfer_registry_is_durable_idempotent_and_reconciles_replicas() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let service = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        let started = transfer_registry_event("started", 1, OperationState::Running, None);
        assert!(
            service
                .record_transfer_event(started.clone())
                .await
                .expect("record start")
        );
        assert!(
            !service
                .record_transfer_event(started.clone())
                .await
                .expect("deduplicate start")
        );

        let mut replica = FederatedTransferRegistry::default();
        replica.ingest(transfer_registry_event(
            "completed",
            2,
            OperationState::Succeeded,
            Some(TransferObservation {
                provider: "filesystem".into(),
                bytes_transferred: 1024,
                elapsed_millis: 50,
                throughput_bps: 20_480,
                retry_count: 1,
                resume_count: 1,
                verification_state: "verified".into(),
                failure_category: None,
            }),
        ));
        service
            .reconcile_transfer_registry(replica)
            .await
            .expect("merge replica");
        assert_eq!(
            service
                .transfer_report("transfer")
                .await
                .expect("report")
                .state,
            pedantic_operation::TransferReportState::Succeeded
        );
        let mut conflicting = started;
        conflicting.target_host = "different-sensitive-host.example".into();
        assert!(service.record_transfer_event(conflicting).await.is_err());
        assert_eq!(
            service
                .transfer_report("transfer")
                .await
                .expect("conflict report")
                .state,
            pedantic_operation::TransferReportState::Conflicted
        );
        let persisted_registry = service
            ._store
            .get(service.transfer_registry_key())
            .expect("durable transfer registry");
        let persisted_registry = persisted_registry.data.to_string();
        for identifier in [
            "source-vm",
            "target-vm",
            "target-host",
            "different-sensitive-host.example",
        ] {
            assert!(!persisted_registry.contains(identifier));
        }
        drop(service);

        let restarted = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("reopen profile store");
        assert_eq!(
            restarted
                .query_transfers(&TransferQuery {
                    operation_id: Some("transfer".into()),
                    source_vm: None,
                    target_vm: None,
                    target_host: None,
                    active: Some(false),
                })
                .await
                .len(),
            1
        );
        assert_eq!(
            restarted
                .transfer_report("transfer")
                .await
                .expect("conflict report after restart")
                .state,
            pedantic_operation::TransferReportState::Conflicted
        );
    }

    #[tokio::test]
    async fn transfer_versioned_api_records_reconciles_queries_reports_and_retains() {
        let first_directory = tempfile::tempdir().expect("first profile store");
        let service = ServiceFoundation::open_at("default", first_directory.path(), "0.1.0")
            .expect("open first profile store");
        let started = transfer_registry_event("started", 1, OperationState::Running, None);

        let recorded = transfer_api_request(
            &service,
            "transfer.record",
            serde_json::json!({ "event": started }),
        )
        .await;
        assert!(recorded.ok, "{:?}", recorded.error);

        let mut replica = FederatedTransferRegistry::default();
        replica.ingest(transfer_registry_event(
            "completed",
            2,
            OperationState::Succeeded,
            Some(TransferObservation {
                provider: "filesystem".into(),
                bytes_transferred: 1024,
                elapsed_millis: 50,
                throughput_bps: 20_480,
                retry_count: 1,
                resume_count: 1,
                verification_state: "verified".into(),
                failure_category: None,
            }),
        ));
        let reconciled = transfer_api_request(
            &service,
            "transfer.reconcile",
            serde_json::json!({ "registry": replica }),
        )
        .await;
        assert!(reconciled.ok, "{:?}", reconciled.error);

        let queried = transfer_api_request(
            &service,
            "transfer.query",
            serde_json::json!({ "sourceVm": "source-vm", "active": false }),
        )
        .await;
        assert!(queried.ok, "{:?}", queried.error);
        let operation = &queried.result.expect("query result")[0];
        assert!(
            operation["sourceVm"]
                .as_str()
                .unwrap()
                .starts_with("opaque:")
        );
        assert!(!operation.to_string().contains("source-vm"));

        let report = transfer_api_request(
            &service,
            "transfer.report",
            serde_json::json!({ "operationId": "transfer" }),
        )
        .await;
        assert!(report.ok, "{:?}", report.error);
        assert_eq!(report.result.expect("report result")["state"], "succeeded");

        let retained = transfer_api_request(
            &service,
            "transfer.retain",
            serde_json::json!({ "retainAfter": 2 }),
        )
        .await;
        assert!(retained.ok, "{:?}", retained.error);
        assert_eq!(
            service
                .query_transfers(&TransferQuery {
                    operation_id: Some("transfer".into()),
                    source_vm: None,
                    target_vm: None,
                    target_host: None,
                    active: None,
                })
                .await
                .len(),
            1
        );
    }

    #[test]
    fn persisted_transfer_registry_corruption_and_schema_mismatch_fail_startup() {
        for (registry_schema_version, registry) in [
            (
                TRANSFER_REGISTRY_STORAGE_SCHEMA_VERSION,
                serde_json::json!("malformed"),
            ),
            (
                "pedantic.transfer-registry-storage.v99",
                serde_json::json!({}),
            ),
        ] {
            let directory = tempfile::tempdir().expect("temporary profile store");
            let service = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
                .expect("create profile store");
            service._store.put(
                service.transfer_registry_key(),
                SERVICE_ACTOR,
                serde_json::json!({
                    "profileId": "default",
                    "registrySchemaVersion": registry_schema_version,
                    "registry": registry,
                }),
            );
            drop(service);

            assert!(matches!(
                ServiceFoundation::open_at("default", directory.path(), "0.1.0"),
                Err(ServiceErrorKind::Foundation(_))
            ));
        }
    }

    #[tokio::test]
    async fn transfer_registries_replicate_concurrent_writes_and_retain_at_volume() {
        let first_directory = tempfile::tempdir().expect("first profile store");
        let second_directory = tempfile::tempdir().expect("second profile store");
        let first = Arc::new(
            ServiceFoundation::open_at("default", first_directory.path(), "0.1.0")
                .expect("open first profile store"),
        );
        let second = Arc::new(
            ServiceFoundation::open_at("default", second_directory.path(), "0.1.0")
                .expect("open second profile store"),
        );
        const OPERATION_COUNT: u64 = 128;
        let mut writes = tokio::task::JoinSet::new();
        for index in 0..OPERATION_COUNT {
            let service = Arc::clone(&first);
            writes.spawn(async move {
                service
                    .record_transfer_event(transfer_registry_event_for(
                        &format!("transfer-{index}"),
                        &format!("start-{index}"),
                        1,
                        OperationState::Running,
                        100,
                        None,
                    ))
                    .await
                    .expect("concurrent source-side write");
            });
            let service = Arc::clone(&second);
            let occurred_at = if index < OPERATION_COUNT / 2 {
                200
            } else {
                2_000
            };
            writes.spawn(async move {
                service
                    .record_transfer_event(transfer_registry_event_for(
                        &format!("transfer-{index}"),
                        &format!("finish-{index}"),
                        2,
                        OperationState::Succeeded,
                        occurred_at,
                        Some(TransferObservation {
                            provider: "filesystem".into(),
                            bytes_transferred: index,
                            elapsed_millis: 50,
                            throughput_bps: index * 20,
                            retry_count: 0,
                            resume_count: 0,
                            verification_state: "verified".into(),
                            failure_category: None,
                        }),
                    ))
                    .await
                    .expect("concurrent target-side write");
            });
        }
        while let Some(result) = writes.join_next().await {
            result.expect("concurrent transfer write task");
        }

        let first_replica = first.transfer_registry.lock().await.clone();
        let second_replica = second.transfer_registry.lock().await.clone();
        first
            .reconcile_transfer_registry(second_replica)
            .await
            .expect("replicate target events");
        second
            .reconcile_transfer_registry(first_replica)
            .await
            .expect("replicate source events");
        let query = TransferQuery {
            operation_id: None,
            source_vm: Some("source-vm".into()),
            target_vm: Some("target-vm".into()),
            target_host: Some("target-host".into()),
            active: Some(false),
        };
        assert_eq!(
            first.query_transfers(&query).await.len(),
            OPERATION_COUNT as usize
        );
        assert_eq!(
            second.query_transfers(&query).await.len(),
            OPERATION_COUNT as usize
        );
        assert_eq!(
            second
                .transfer_report("transfer-127")
                .await
                .expect("replicated operation report")
                .state,
            pedantic_operation::TransferReportState::Succeeded
        );

        first.retain_terminal_transfer_history(1_000).await;
        assert_eq!(
            first.query_transfers(&query).await.len(),
            (OPERATION_COUNT / 2) as usize
        );
        assert_eq!(
            first
                .transfer_report("transfer-127")
                .await
                .expect("operation retained as an atomic unit")
                .state,
            pedantic_operation::TransferReportState::Succeeded
        );
    }

    fn transfer_registry_event(
        event_id: &str,
        sequence: u64,
        state: OperationState,
        observation: Option<TransferObservation>,
    ) -> TransferEvent {
        TransferEvent {
            schema_version: pedantic_operation::TRANSFER_REGISTRY_SCHEMA_VERSION.into(),
            operation: OperationEvent {
                schema_version: pedantic_operation::OPERATION_EVENT_SCHEMA_VERSION.into(),
                event_id: event_id.into(),
                event_type: "transfer.observed".into(),
                resulting_state: state,
                operation_id: "transfer".into(),
                plan_id: "plan".into(),
                step_id: Some("step".into()),
                attempt_id: Some("attempt".into()),
                profile_id: "default".into(),
                actor_id: "agent".into(),
                target_id: "target".into(),
                agent_id: "agent".into(),
                causation_id: "cause".into(),
                correlation_id: "correlation".into(),
                sequence,
                occurred_at: Some(sequence),
            },
            source_vm: "source-vm".into(),
            target_vm: "target-vm".into(),
            target_host: "target-host".into(),
            observation,
        }
    }

    fn transfer_registry_event_for(
        operation_id: &str,
        event_id: &str,
        sequence: u64,
        state: OperationState,
        occurred_at: u64,
        observation: Option<TransferObservation>,
    ) -> TransferEvent {
        let mut event = transfer_registry_event(event_id, sequence, state, observation);
        event.operation.operation_id = operation_id.into();
        event.operation.occurred_at = Some(occurred_at);
        event
    }

    #[test]
    fn evidence_query_is_bounded_and_redacted() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        for _ in 0..=MAX_EVIDENCE_RESULTS {
            foundation.record_start("0.1.0");
        }

        let page = foundation.recent_evidence();
        assert_eq!(page.entries.len(), MAX_EVIDENCE_RESULTS);
        assert!(page.truncated);

        let serialized = serde_json::to_value(&page).expect("serialize evidence projection");
        let entry = serialized["entries"][0]
            .as_object()
            .expect("serialized evidence entry");
        assert_eq!(entry.len(), 5);
        for field in ["eventId", "timestamp", "actor", "action", "level"] {
            assert!(entry.contains_key(field), "missing {field}");
        }
    }

    #[tokio::test]
    async fn evidence_list_is_available_to_the_authenticated_profile() {
        let evidence = EvidencePage {
            entries: Vec::new(),
            truncated: false,
        };
        let response = handle_request(
            r#"{"id":"1","method":"evidence.list","profileId":"default","authorization":"0123456789abcdef0123456789abcdef"}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            RequestHandlers {
                evidence: move || evidence,
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(response.ok);
    }

    #[tokio::test]
    async fn evidence_list_rejects_an_invalid_token() {
        let evidence = EvidencePage {
            entries: Vec::new(),
            truncated: false,
        };
        let response = handle_request(
            r#"{"id":"1","method":"evidence.list","profileId":"default","authorization":"incorrect-token"}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            RequestHandlers {
                evidence: move || evidence,
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert_eq!(
            response.error.expect("unauthorized response").code,
            "unauthorized"
        );
    }

    #[tokio::test]
    async fn configuration_admission_is_evaluated_by_px_and_recorded_as_evidence() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");

        let accepted = foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-accepted".into(),
                source_digest: "sha256:accepted".into(),
            })
            .await
            .expect("evaluate accepted configuration");
        assert_eq!(accepted.decision, "accepted");
        assert_eq!(
            accepted.constraint_id,
            "configuration_requires_source_digest"
        );
        let changed = foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-accepted".into(),
                source_digest: "sha256:changed".into(),
            })
            .await
            .expect("evaluate changed configuration");
        assert_eq!(changed.decision, "rejected");
        assert_eq!(
            changed.constraint_id,
            "configuration_admission_requires_immutable_source_digest"
        );
        assert_eq!(
            foundation
                ._store
                .get(&foundation.configuration_key("revision-accepted"))
                .expect("original projection")
                .data["sourceDigest"],
            "sha256:accepted"
        );

        let rejected = foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-rejected".into(),
                source_digest: String::new(),
            })
            .await
            .expect("evaluate rejected configuration");
        assert_eq!(rejected.decision, "rejected");
        assert_eq!(foundation.evidence_count(), 3);
        assert_eq!(foundation.recent_evidence().entries.len(), 3);
    }

    #[tokio::test]
    async fn configuration_admit_returns_a_stable_px_rejection_code() {
        let response = handle_request(
            r#"{"id":"1","method":"configuration.admit","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"revisionId":"revision-rejected","sourceDigest":""}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |request| std::future::ready(evaluate_configuration_admission(&request, None)),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(!response.ok);
        assert_eq!(
            response.error.expect("PX rejection response").code,
            "configuration_rejected"
        );
    }

    #[tokio::test]
    async fn configuration_validate_maps_validation_outcomes_at_the_protocol_boundary() {
        let request = |id| {
            format!(
                r#"{{"id":"{id}","method":"configuration.validate","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{{"revisionId":"revision-1","document":"document"}}}}"#
            )
        };
        let validation = |decision: &'static str| ConfigurationValidation {
            revision_id: "revision-1".into(),
            decision: decision.into(),
            constraint_id: "test".into(),
            reason: "test result".into(),
        };

        let success = handle_request(
            &request("success"),
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                validation: move |_| std::future::ready(Ok(validation("validated"))),
                inventory: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                compliance: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                observation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                remediation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                approval: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                execution: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(success.ok);

        let invalid = handle_request(
            &request("invalid"),
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                validation: move |_| std::future::ready(Ok(validation("invalid"))),
                inventory: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                compliance: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                observation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                remediation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                approval: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                execution: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(invalid.ok);

        let failed = handle_request(
            &request("failed"),
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                validation: |_| {
                    std::future::ready(Err(ServiceErrorKind::Foundation("adapter failed".into())))
                },
                inventory: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                compliance: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                observation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                remediation: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                approval: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                execution: |_| {
                    std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into())))
                },
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(!failed.ok);
        assert_eq!(
            failed.error.expect("validation failure").code,
            "validation_failed"
        );
    }

    #[tokio::test]
    async fn configuration_validation_rejects_a_document_with_a_different_admitted_digest() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-validated".into(),
                source_digest: "sha256:admitted-source".into(),
            })
            .await
            .expect("admit configuration");

        let validation = foundation
            .validate_configuration(ConfigurationValidationRequest {
                revision_id: "revision-validated".into(),
                document: "$schema: example".into(),
            })
            .await
            .expect("evaluate PX validation precondition");
        assert_eq!(validation.decision, "rejected");
        assert_eq!(
            validation.constraint_id,
            "configuration_validation_requires_matching_source_digest"
        );
        assert_eq!(foundation.evidence_count(), 2);
    }

    #[tokio::test]
    async fn inventory_observation_is_rejected_before_document_normalization() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");

        let observation = foundation
            .observe_inventory(InventoryObservationRequest {
                observation_id: "inventory-rejected".into(),
                source_digest: "sha256:not-the-supplied-document".into(),
                document: "not a Pedantic inventory".into(),
            })
            .await
            .expect("evaluate PX inventory precondition");

        assert_eq!(observation.decision, "rejected");
        assert_eq!(
            observation.constraint_id,
            "inventory_observation_requires_matching_source_digest"
        );
        assert_eq!(observation.host_count, 0);
        assert!(observation.hosts.is_empty());
        assert_eq!(foundation.evidence_count(), 1);
    }

    #[tokio::test]
    async fn inventory_observation_normalizes_hosts_and_redacts_chronos_evidence() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        let document = include_str!("../../pedantic-executor/tests/fixtures/inventory.yaml");
        let source_digest = format!("sha256:{:x}", Sha256::digest(document.as_bytes()));

        let observation = foundation
            .observe_inventory(InventoryObservationRequest {
                observation_id: "inventory-observed".into(),
                source_digest,
                document: document.into(),
            })
            .await
            .expect("normalize supplied inventory document");

        assert_eq!(observation.decision, "observed");
        assert_eq!(
            observation.constraint_id,
            "inventory_observation_requires_matching_source_digest"
        );
        assert_eq!(observation.host_count, 2);
        assert_eq!(observation.hosts[0].hostname, "192.168.1.10");
        assert_eq!(observation.hosts[1].connection, "ssh");

        let evidence = serde_json::to_string(&foundation.recent_evidence())
            .expect("serialize redacted evidence projection");
        assert!(!evidence.contains("192.168.1.10"));
        assert!(!evidence.contains("sourceDigest"));
    }

    #[tokio::test]
    async fn compliance_request_is_rejected_until_px_observes_a_validated_revision() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-compliance".into(),
                source_digest: "sha256:admitted-source".into(),
            })
            .await
            .expect("admit configuration");

        let decision = foundation
            .request_compliance(ComplianceRequest {
                request_id: "request-compliance".into(),
                revision_id: "revision-compliance".into(),
            })
            .await
            .expect("evaluate compliance request");
        assert_eq!(decision.decision, "rejected");
        assert_eq!(
            decision.constraint_id,
            "compliance_requires_validated_revision"
        );
        assert_eq!(foundation.evidence_count(), 2);
    }

    #[tokio::test]
    async fn compliance_request_is_accepted_after_px_observes_a_validated_revision() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-compliance".into(),
                source_digest: "sha256:admitted-source".into(),
            })
            .await
            .expect("admit configuration");
        foundation._store.put(
            foundation.configuration_key("revision-compliance"),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": foundation.profile_id,
                "revisionId": "revision-compliance",
                "sourceDigest": "sha256:admitted-source",
                "admissionState": "accepted",
                "validationState": "validated",
                "constraintId": "configuration_validation_requires_matching_source_digest",
            }),
        );

        let decision = foundation
            .request_compliance(ComplianceRequest {
                request_id: "request-compliance".into(),
                revision_id: "revision-compliance".into(),
            })
            .await
            .expect("evaluate accepted compliance request");
        assert_eq!(decision.decision, "accepted");
        assert_eq!(
            decision.constraint_id,
            "compliance_requires_validated_revision"
        );
        let projection = foundation
            ._store
            .get(&foundation.compliance_key("request-compliance"))
            .expect("stored compliance projection");
        assert_eq!(projection.data["decision"], "accepted");

        let response = handle_request(
            r#"{"id":"1","method":"compliance.request","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"requestId":"request-2","revisionId":"revision-compliance"}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |request: ComplianceRequest| std::future::ready(Ok(ComplianceDecision {
                    request_id: request.request_id,
                    revision_id: request.revision_id,
                    decision: "accepted".into(),
                    constraint_id: "compliance_requires_validated_revision".into(),
                    reason: "PX accepted the request.".into(),
                })),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(response.ok);
        assert_eq!(
            response.result.expect("accepted compliance result")["decision"],
            "accepted"
        );
    }

    #[tokio::test]
    async fn compliance_request_returns_a_stable_px_rejection_code() {
        let response = handle_request(
            r#"{"id":"1","method":"compliance.request","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"requestId":"request-1","revisionId":"revision-1"}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |request: ComplianceRequest| std::future::ready(Ok(ComplianceDecision {
                    request_id: request.request_id,
                    revision_id: request.revision_id,
                    decision: "rejected".into(),
                    constraint_id: "compliance_requires_validated_revision".into(),
                    reason: "PX rejected the request.".into(),
                })),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(!response.ok);
        assert_eq!(
            response.error.expect("PX rejection response").code,
            "compliance_rejected"
        );
    }

    #[tokio::test]
    async fn inventory_observation_returns_a_stable_px_rejection_code() {
        let response = handle_request(
            r#"{"id":"1","method":"inventory.observe","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"observationId":"inventory-1","sourceDigest":"sha256:source","document":"document"}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |request: InventoryObservationRequest| std::future::ready(Ok(InventoryObservation {
                    observation_id: request.observation_id,
                    decision: "rejected".into(),
                    constraint_id: "inventory_observation_requires_matching_source_digest".into(),
                    host_count: 0,
                    hosts: Vec::new(),
                    reason: "PX rejected the observation.".into(),
                })),
                compliance: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(!response.ok);
        assert_eq!(
            response.error.expect("PX rejection response").code,
            "inventory_rejected"
        );
    }

    #[tokio::test]
    async fn compliance_observation_is_px_rejected_before_dsc_runs() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        foundation
            .admit_configuration(ConfigurationAdmissionRequest {
                revision_id: "revision-observation".into(),
                source_digest: "sha256:admitted-source".into(),
            })
            .await
            .expect("admit configuration");
        foundation
            .request_compliance(ComplianceRequest {
                request_id: "request-observation".into(),
                revision_id: "revision-observation".into(),
            })
            .await
            .expect("record rejected compliance request");

        let observation = foundation
            .observe_compliance(ComplianceObservationRequest {
                observation_id: "observation-rejected".into(),
                request_id: "request-observation".into(),
                document: "document that must not reach DSC".into(),
            })
            .await
            .expect("evaluate PX observation precondition");
        assert_eq!(observation.decision, "rejected");
        assert_eq!(
            observation.constraint_id,
            "compliance_observation_requires_accepted_request"
        );
        assert_eq!(observation.resource_count, 0);
        assert_eq!(foundation.evidence_count(), 3);
        assert_eq!(
            foundation
                ._store
                .get(&foundation.compliance_observation_key("observation-rejected"))
                .expect("stored compliance observation")
                .data["sourceDigest"],
            format!(
                "sha256:{:x}",
                Sha256::digest("document that must not reach DSC".as_bytes())
            )
        );
    }

    #[test]
    fn compliance_observation_normalizes_dsc_results_without_properties() {
        let observation = compliance_observation_from_results(
            "observation-1".into(),
            "request-1".into(),
            "revision-1".into(),
            vec![
                DscTestResult {
                    resource_name: "compliant-resource".into(),
                    resource_type: "Example/Resource".into(),
                    in_desired_state: true,
                    properties: serde_json::json!({ "sensitive": "not projected" }),
                },
                DscTestResult {
                    resource_name: "drifted-resource".into(),
                    resource_type: "Example/Resource".into(),
                    in_desired_state: false,
                    properties: serde_json::json!({ "sensitive": "not projected" }),
                },
            ],
        );
        assert_eq!(observation.decision, "observed");
        assert_eq!(observation.resource_count, 2);
        assert_eq!(observation.compliant_resource_count, 1);
        assert_eq!(observation.drifted_resource_count, 1);
        let serialized = serde_json::to_value(observation).expect("serialize observation");
        assert!(serialized.get("properties").is_none());
        assert!(serialized.get("sourceDigest").is_none());
        assert!(!serialized.to_string().contains("not projected"));
    }

    #[tokio::test]
    async fn compliance_observation_returns_a_stable_px_rejection_code() {
        let response = handle_request(
            r#"{"id":"1","method":"compliance.observe","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"observationId":"observation-1","requestId":"request-1","document":"document"}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage {
                    entries: Vec::new(),
                    truncated: false,
                },
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                observation: |request: ComplianceObservationRequest| std::future::ready(Ok(ComplianceObservation {
                    observation_id: request.observation_id,
                    request_id: request.request_id,
                    revision_id: "revision-1".into(),
                    decision: "rejected".into(),
                    constraint_id: "compliance_observation_requires_accepted_request".into(),
                    resource_count: 0,
                    compliant_resource_count: 0,
                    drifted_resource_count: 0,
                    reason: "PX rejected the observation.".into(),
                })),
                remediation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(!response.ok);
        assert_eq!(
            response.error.expect("PX rejection response").code,
            "compliance_rejected"
        );
    }

    #[tokio::test]
    async fn remediation_requires_drift_then_explicit_approval_and_never_reaches_dsc_on_digest_mismatch()
     {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        let document = "document admitted for remediation";
        let source_digest = format!("sha256:{:x}", Sha256::digest(document.as_bytes()));
        foundation._store.put(
            foundation.configuration_key("revision-remediation"),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": foundation.profile_id,
                "revisionId": "revision-remediation",
                "sourceDigest": source_digest,
                "admissionState": "accepted",
                "validationState": "validated",
                "constraintId": "configuration_validation_requires_matching_source_digest",
            }),
        );
        foundation
            .record_compliance_observation(
                &ComplianceObservation {
                    observation_id: "observation-drifted".into(),
                    request_id: "compliance-request".into(),
                    revision_id: "revision-remediation".into(),
                    decision: "observed".into(),
                    constraint_id: "dsc_config_test".into(),
                    resource_count: 1,
                    compliant_resource_count: 0,
                    drifted_resource_count: 1,
                    reason: "fixture".into(),
                },
                &source_digest,
            )
            .expect("record drift observation");

        let remediation = foundation
            .request_remediation(RemediationRequest {
                request_id: "remediation-request".into(),
                revision_id: "revision-remediation".into(),
                observation_id: "observation-drifted".into(),
                actor_id: "operator@example.test".into(),
                idempotency_key: "remediation-key".into(),
            })
            .await
            .expect("evaluate remediation request");
        assert_eq!(remediation.decision, "accepted");
        assert_eq!(
            remediation.constraint_id,
            "remediation_requires_actor_and_idempotency_key"
        );
        let request_retry = foundation
            .request_remediation(RemediationRequest {
                request_id: "remediation-request".into(),
                revision_id: "revision-remediation".into(),
                observation_id: "observation-drifted".into(),
                actor_id: "operator@example.test".into(),
                idempotency_key: "remediation-key".into(),
            })
            .await
            .expect("retry remediation request");
        assert_eq!(request_retry, remediation);
        assert!(matches!(
            foundation
                .request_remediation(RemediationRequest {
                    request_id: "remediation-request".into(),
                    revision_id: "revision-remediation".into(),
                    observation_id: "different-observation".into(),
                    actor_id: "operator@example.test".into(),
                    idempotency_key: "remediation-key".into(),
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));

        let partial_approval = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-partial".into(),
                request_id: "remediation-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("record approval before interrupted authorization");
        let evidence_before_interruption = foundation.evidence_count();
        foundation
            .timeline
            .set_level(pluresdb_chronos::ChronosLevel::Error);
        assert!(matches!(
            foundation
                .authorize_remediation(RemediationApprovalRequest {
                    approval_id: partial_approval.approval_id.clone(),
                    request_id: partial_approval.request_id.clone(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::Foundation(_))
        ));
        assert_eq!(foundation.evidence_count(), evidence_before_interruption);
        assert_eq!(
            foundation
                ._store
                .get(foundation.effect_authorization_key("approval-partial"))
                .expect("pending authorization")
                .data["evidenceRecorded"],
            false
        );
        foundation
            .timeline
            .set_level(pluresdb_chronos::ChronosLevel::Info);
        let repaired_authorization = foundation
            .authorize_remediation(RemediationApprovalRequest {
                approval_id: partial_approval.approval_id.clone(),
                request_id: partial_approval.request_id.clone(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("repair authorization evidence on retry");
        assert_eq!(repaired_authorization.decision, "accepted");
        assert_eq!(
            foundation.evidence_count(),
            evidence_before_interruption + 1
        );
        assert!(matches!(
            foundation
                .approve_remediation(RemediationApprovalRequest {
                    approval_id: "approval-partial".into(),
                    request_id: "remediation-request".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: false,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert!(
            foundation
                ._store
                .get(foundation.remediation_approval_key("approval-partial"))
                .is_some()
        );
        assert_eq!(
            foundation
                ._store
                .get(foundation.effect_authorization_key("approval-partial"))
                .expect("repaired authorization")
                .data["evidenceRecorded"],
            true
        );

        let denied_approval = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-denied".into(),
                request_id: "remediation-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: false,
                authorize: false,
            })
            .await
            .expect("evaluate denied approval");
        assert_eq!(denied_approval.decision, "rejected");
        assert_eq!(
            denied_approval.constraint_id,
            "remediation_approval_requires_explicit_approval"
        );
        assert!(denied_approval.authorization_id.is_none());
        let denied_evidence_count = foundation.evidence_count();
        assert!(matches!(
            foundation
                .authorize_remediation(RemediationApprovalRequest {
                    approval_id: "approval-denied".into(),
                    request_id: "remediation-request".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert_eq!(foundation.evidence_count(), denied_evidence_count);
        assert!(
            foundation
                ._store
                .get(foundation.effect_authorization_key("approval-denied"))
                .is_none()
        );
        assert!(matches!(
            foundation
                .approve_remediation(RemediationApprovalRequest {
                    approval_id: "approval-denied".into(),
                    request_id: "remediation-request".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));

        let missing_actor = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-missing-actor".into(),
                request_id: "remediation-request".into(),
                actor_id: String::new(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("evaluate incomplete approval");
        assert_eq!(missing_actor.decision, "rejected");
        assert_eq!(
            missing_actor.constraint_id,
            "remediation_approval_requires_actor_and_identifier"
        );
        let missing_actor_evidence_count = foundation.evidence_count();
        assert!(matches!(
            foundation
                .authorize_remediation(RemediationApprovalRequest {
                    approval_id: "approval-missing-actor".into(),
                    request_id: "remediation-request".into(),
                    actor_id: String::new(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert_eq!(foundation.evidence_count(), missing_actor_evidence_count);
        assert!(
            foundation
                ._store
                .get(foundation.effect_authorization_key("approval-missing-actor"))
                .is_none()
        );
        let missing_approval_evidence_count = foundation.evidence_count();
        assert!(matches!(
            foundation
                .authorize_remediation(RemediationApprovalRequest {
                    approval_id: "approval-not-recorded".into(),
                    request_id: "remediation-request".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert_eq!(foundation.evidence_count(), missing_approval_evidence_count);
        assert!(
            foundation
                ._store
                .get(foundation.effect_authorization_key("approval-not-recorded"))
                .is_none()
        );

        let approved = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-accepted".into(),
                request_id: "remediation-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("approve remediation");
        assert_eq!(approved.decision, "accepted");
        assert_eq!(approved.authorization_id.as_deref(), None);
        let approved_evidence_count = foundation.evidence_count();
        for invalid_request in [
            RemediationApprovalRequest {
                approval_id: approved.approval_id.clone(),
                request_id: "unrelated-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            },
            RemediationApprovalRequest {
                approval_id: approved.approval_id.clone(),
                request_id: approved.request_id.clone(),
                actor_id: "different-reviewer@example.test".into(),
                approved: true,
                authorize: false,
            },
            RemediationApprovalRequest {
                approval_id: approved.approval_id.clone(),
                request_id: approved.request_id.clone(),
                actor_id: "reviewer@example.test".into(),
                approved: false,
                authorize: false,
            },
        ] {
            assert!(matches!(
                foundation.authorize_remediation(invalid_request).await,
                Err(ServiceErrorKind::InvalidRequest(_))
            ));
            assert_eq!(foundation.evidence_count(), approved_evidence_count);
            assert!(
                foundation
                    ._store
                    .get(foundation.effect_authorization_key(&approved.approval_id))
                    .is_none()
            );
        }
        let px_denied_approval = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-px-denied".into(),
                request_id: approved.request_id.clone(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("record approval for PX denial test");
        let remediation_key = foundation.remediation_request_key(&approved.request_id);
        let recorded_remediation = foundation
            ._store
            .get(&remediation_key)
            .expect("accepted remediation request");
        let mut denied_remediation = recorded_remediation.data.clone();
        denied_remediation["decision"] = serde_json::Value::String("rejected".into());
        foundation
            ._store
            .put(remediation_key.clone(), SERVICE_ACTOR, denied_remediation);
        let px_denied_evidence_count = foundation.evidence_count();
        assert!(matches!(
            foundation
                .authorize_remediation(RemediationApprovalRequest {
                    approval_id: px_denied_approval.approval_id.clone(),
                    request_id: px_denied_approval.request_id.clone(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert_eq!(foundation.evidence_count(), px_denied_evidence_count);
        assert!(
            foundation
                ._store
                .get(foundation.effect_authorization_key("approval-px-denied"))
                .is_none()
        );
        foundation
            ._store
            .put(remediation_key, SERVICE_ACTOR, recorded_remediation.data);
        let conflicting_approval = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-conflicting".into(),
                request_id: "remediation-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("record approval for conflicting grant");
        foundation._store.put(
            foundation.effect_authorization_key(&conflicting_approval.approval_id),
            SERVICE_ACTOR,
            serde_json::json!({
                "requestId": "different-request",
                "actorId": "reviewer@example.test",
                "revisionId": "revision-remediation",
                "sourceDigest": source_digest,
                "idempotencyKey": "remediation-key",
                "decision": "accepted",
            }),
        );
        let conflict_evidence_count = foundation.evidence_count();
        assert!(matches!(
            foundation
                .authorize_remediation(RemediationApprovalRequest {
                    approval_id: conflicting_approval.approval_id.clone(),
                    request_id: conflicting_approval.request_id,
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert_eq!(foundation.evidence_count(), conflict_evidence_count);
        let authorization = foundation
            .authorize_remediation(RemediationApprovalRequest {
                approval_id: "approval-accepted".into(),
                request_id: "remediation-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("authorize recorded approval");
        assert_eq!(
            authorization.authorization_id.as_deref(),
            Some("approval-accepted")
        );
        let signed_authorization = authorization
            .authorization
            .as_ref()
            .expect("signed effect authorization");
        validate_effect_authorization_schema(signed_authorization)
            .expect("authorization conforms to the published schema");
        assert_eq!(signed_authorization.actor_id, "reviewer@example.test");
        assert_eq!(signed_authorization.target_id, foundation.profile_id);
        assert_eq!(signed_authorization.agent_id, SERVICE_ACTOR);
        assert!(signed_authorization.expires_at > current_unix_timestamp());
        let mut expired_authorization = signed_authorization.clone();
        expired_authorization.expires_at = current_unix_timestamp().saturating_sub(1);
        assert!(
            validate_signed_effect_authorization(
                &expired_authorization,
                &foundation.authorization_signing_key.verifying_key(),
                &EffectAuthorizationBindings {
                    profile_id: &foundation.profile_id,
                    agent_id: SERVICE_ACTOR,
                    actor_id: "reviewer@example.test",
                    authorization_id: "approval-accepted",
                    request_id: "remediation-request",
                    input_digest: &source_digest,
                    idempotency_key: "remediation-key",
                },
            )
            .is_err()
        );
        let mut forged_authorization = signed_authorization.clone();
        forged_authorization.signature.value = URL_SAFE_NO_PAD.encode([0; 64]);
        assert!(
            validate_signed_effect_authorization(
                &forged_authorization,
                &foundation.authorization_signing_key.verifying_key(),
                &EffectAuthorizationBindings {
                    profile_id: &foundation.profile_id,
                    agent_id: SERVICE_ACTOR,
                    actor_id: "reviewer@example.test",
                    authorization_id: "approval-accepted",
                    request_id: "remediation-request",
                    input_digest: &source_digest,
                    idempotency_key: "remediation-key",
                },
            )
            .is_err()
        );
        let authorization_evidence_count = foundation.evidence_count();
        let retried_authorization = foundation
            .authorize_remediation(RemediationApprovalRequest {
                approval_id: "approval-accepted".into(),
                request_id: "remediation-request".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("retry effect authorization");
        assert_eq!(
            retried_authorization.authorization,
            authorization.authorization
        );
        assert_eq!(foundation.evidence_count(), authorization_evidence_count);
        assert_eq!(
            foundation
                .approve_remediation(RemediationApprovalRequest {
                    approval_id: "approval-accepted".into(),
                    request_id: "remediation-request".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await
                .expect("retry approval"),
            approved
        );
        assert!(matches!(
            foundation
                .approve_remediation(RemediationApprovalRequest {
                    approval_id: "approval-accepted".into(),
                    request_id: "another-request".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));

        let second_request = foundation
            .request_remediation(RemediationRequest {
                request_id: "remediation-request-second".into(),
                revision_id: "revision-remediation".into(),
                observation_id: "observation-drifted".into(),
                actor_id: "operator@example.test".into(),
                idempotency_key: "remediation-key-second".into(),
            })
            .await
            .expect("create second remediation request");
        assert_eq!(second_request.decision, "accepted");
        let second_approval = foundation
            .approve_remediation(RemediationApprovalRequest {
                approval_id: "approval-second".into(),
                request_id: "remediation-request-second".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("approve second remediation request");
        assert_eq!(second_approval.decision, "accepted");
        foundation
            .authorize_remediation(RemediationApprovalRequest {
                approval_id: "approval-second".into(),
                request_id: "remediation-request-second".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("authorize second remediation request");
        assert_eq!(
            foundation
                .request_remediation(RemediationRequest {
                    request_id: "remediation-request-second".into(),
                    revision_id: "revision-remediation".into(),
                    observation_id: "observation-drifted".into(),
                    actor_id: "operator@example.test".into(),
                    idempotency_key: "remediation-key-second".into(),
                })
                .await
                .expect("retry second remediation request"),
            second_request
        );
        let third_request = foundation
            .request_remediation(RemediationRequest {
                request_id: "remediation-request-third".into(),
                revision_id: "revision-remediation".into(),
                observation_id: "observation-drifted".into(),
                actor_id: "operator@example.test".into(),
                idempotency_key: "remediation-key-third".into(),
            })
            .await
            .expect("create third remediation request");
        assert_eq!(third_request.decision, "accepted");
        assert_eq!(
            foundation
                .approve_remediation(RemediationApprovalRequest {
                    approval_id: "approval-third".into(),
                    request_id: "remediation-request-third".into(),
                    actor_id: "reviewer@example.test".into(),
                    approved: true,
                    authorize: false,
                })
                .await
                .expect("approve third remediation request")
                .decision,
            "accepted"
        );
        foundation
            .authorize_remediation(RemediationApprovalRequest {
                approval_id: "approval-third".into(),
                request_id: "remediation-request-third".into(),
                actor_id: "reviewer@example.test".into(),
                approved: true,
                authorize: false,
            })
            .await
            .expect("authorize third remediation request");

        assert!(matches!(
            foundation
                .execute_remediation(RemediationExecutionRequest {
                    execution_id: "execution-mismatched-binding".into(),
                    authorization_id: "approval-accepted".into(),
                    idempotency_key: "remediation-key-second".into(),
                    document: document.into(),
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert!(
            foundation
                ._store
                .get(foundation.remediation_execution_idempotency_key("remediation-key-second"))
                .is_none()
        );

        foundation
            .record_compliance_observation(
                &ComplianceObservation {
                    observation_id: "observation-current-clean".into(),
                    request_id: "compliance-request-new".into(),
                    revision_id: "revision-remediation".into(),
                    decision: "observed".into(),
                    constraint_id: "dsc_config_test".into(),
                    resource_count: 1,
                    compliant_resource_count: 1,
                    drifted_resource_count: 0,
                    reason: "fixture".into(),
                },
                &source_digest,
            )
            .expect("record newer compliance observation");
        let second_valid_attempt = foundation
            .execute_remediation(RemediationExecutionRequest {
                execution_id: "execution-second-current-evidence".into(),
                authorization_id: "approval-second".into(),
                idempotency_key: "remediation-key-second".into(),
                document: document.into(),
            })
            .await
            .expect("reject authorization bound to superseded evidence");
        assert_eq!(
            second_valid_attempt.constraint_id,
            "remediation_execution_requires_current_observation"
        );

        foundation._store.put(
            foundation.compliance_observation_key("observation-drifted"),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": foundation.profile_id,
                "observationId": "observation-drifted",
                "requestId": "compliance-request",
                "revisionId": "revision-remediation",
                "sourceDigest": source_digest,
                "observedAt": 0,
                "decision": "observed",
                "constraintId": "dsc_config_test",
                "resourceCount": 1,
                "compliantResourceCount": 0,
                "driftedResourceCount": 1,
            }),
        );
        foundation._store.put(
            foundation.compliance_current_key("revision-remediation"),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": foundation.profile_id,
                "revisionId": "revision-remediation",
                "observationId": "observation-drifted",
                "observedAt": 0,
            }),
        );
        let stale_execution = foundation
            .execute_remediation(RemediationExecutionRequest {
                execution_id: "execution-stale-evidence".into(),
                authorization_id: "approval-third".into(),
                idempotency_key: "remediation-key-third".into(),
                document: document.into(),
            })
            .await
            .expect("reject execution with stale compliance evidence");
        assert_eq!(
            stale_execution.constraint_id,
            "remediation_execution_requires_fresh_observation"
        );
        let stale_request = foundation
            .request_remediation(RemediationRequest {
                request_id: "remediation-request-stale".into(),
                revision_id: "revision-remediation".into(),
                observation_id: "observation-drifted".into(),
                actor_id: "operator@example.test".into(),
                idempotency_key: "remediation-key-stale".into(),
            })
            .await
            .expect("reject stale compliance evidence");
        assert_eq!(
            stale_request.constraint_id,
            "remediation_requires_fresh_observation"
        );

        assert!(matches!(
            foundation
                .execute_remediation(RemediationExecutionRequest {
                    execution_id: "execution-rejected".into(),
                    authorization_id: "approval-accepted".into(),
                    idempotency_key: "remediation-key".into(),
                    document: "different document that must not reach DSC".into(),
                })
                .await,
            Err(ServiceErrorKind::InvalidRequest(_))
        ));
        assert!(
            foundation
                ._store
                .get(foundation.remediation_execution_idempotency_key("remediation-key"))
                .is_none()
        );
        let evidence = serde_json::to_string(&foundation.recent_evidence())
            .expect("serialize redacted evidence projection");
        assert!(!evidence.contains("different document"));
        assert!(!evidence.contains("sourceDigest"));
    }

    #[tokio::test]
    async fn interrupted_remediation_claim_survives_service_restart_and_blocks_replay() {
        let directory = tempfile::tempdir().expect("temporary profile store");
        let foundation = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("open profile store");
        let document = "configuration document";
        let document_digest = format!("sha256:{:x}", Sha256::digest(document.as_bytes()));
        let authorization_id = "approval-interrupted";
        let request_id = "request-interrupted";
        let idempotency_key = "key-interrupted";
        foundation._store.put(
            foundation.effect_authorization_key(authorization_id),
            SERVICE_ACTOR,
            serde_json::json!({
                "profileId": foundation.profile_id,
                "authorizationId": authorization_id,
                "requestId": request_id,
                "revisionId": "revision-interrupted",
                "sourceDigest": document_digest,
                "idempotencyKey": idempotency_key,
                "capability": "dsc_config_set",
                "decision": "accepted",
            }),
        );
        let execution_key = foundation.remediation_execution_idempotency_key(idempotency_key);
        foundation
            .record_remediation_execution_claim(
                &execution_key,
                authorization_id,
                &document_digest,
                "execution-interrupted",
            )
            .expect("persist execution claim");
        drop(foundation);

        let restarted = ServiceFoundation::open_at("default", directory.path(), "0.1.0")
            .expect("reopen profile store");
        let error = restarted
            .execute_remediation(RemediationExecutionRequest {
                execution_id: "execution-interrupted".into(),
                authorization_id: authorization_id.into(),
                idempotency_key: idempotency_key.into(),
                document: document.into(),
            })
            .await
            .expect_err("interrupted execution must require reconciliation");
        assert!(matches!(
            error,
            ServiceErrorKind::InvalidRequest(message)
                if message.contains("reconcile its effects")
        ));
        assert_eq!(
            restarted
                ._store
                .get(&execution_key)
                .expect("durable claim")
                .data["status"],
            "in_progress"
        );
    }

    #[test]
    fn remediation_resource_counts_are_normalized_without_inventing_unavailable_counts() {
        assert_eq!(
            remediation_resource_count(&serde_json::json!([
                {"name": "one"},
                {"name": "two"}
            ])),
            Some(2)
        );
        assert_eq!(
            remediation_resource_count(&serde_json::json!({
                "resources": [{"name": "one"}]
            })),
            Some(1)
        );
        assert_eq!(remediation_resource_count(&serde_json::json!({})), None);
    }

    #[tokio::test]
    async fn remediation_request_returns_a_stable_px_rejection_code() {
        const RESPONSE_SCHEMA: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/local-service-response.schema.json"
        ));
        const EVIDENCE_SCHEMA: &str = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../contracts/v1/evidence-summary.schema.json"
        ));
        let response = handle_request(
            r#"{"id":"1","method":"remediation.request","profileId":"default","authorization":"0123456789abcdef0123456789abcdef","params":{"requestId":"request-1","revisionId":"revision-1","observationId":"observation-1","actorId":"operator","idempotencyKey":"key-1"}}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            0,
            RequestHandlers {
                evidence: || EvidencePage { entries: Vec::new(), truncated: false },
                admission: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                validation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                inventory: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                compliance: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                observation: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                remediation: |request: RemediationRequest| std::future::ready(Ok(RemediationDecision {
                    request_id: request.request_id,
                    revision_id: request.revision_id,
                    observation_id: request.observation_id,
                    decision: "rejected".into(),
                    constraint_id: "remediation_requires_drifted_observation".into(),
                    reason: "PX rejected the remediation request.".into(),
                })),
                approval: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                execution: |_| std::future::ready(Err(ServiceErrorKind::InvalidRequest("not invoked".into()))),
                transfer: reject_transfer,
            },
        )
        .await;
        assert!(!response.ok);
        assert_eq!(
            response.error.as_ref().expect("PX rejection response").code,
            "remediation_rejected"
        );
        assert_response_contract(
            RESPONSE_SCHEMA,
            EVIDENCE_SCHEMA,
            serde_json::to_value(response).expect("serialize remediation response"),
        );
    }

    #[cfg(windows)]
    #[test]
    fn pipe_name_stays_within_the_windows_limit_for_long_sids() {
        let sid = format!("S-{}", "1".repeat(182));
        let pipe_name =
            pipe_name_for_identity(&"p".repeat(64), "0123456789abcdef0123456789abcdef", &sid);
        assert!(pipe_name.len() <= 256);
    }

    #[cfg(windows)]
    #[test]
    fn parses_the_sid_from_whoami_csv_output() {
        let sid = parse_current_user_sid("\"redmond\\kbristol\",\"S-1-12-1-123-456-789-101\"\r\n")
            .expect("valid whoami CSV output");
        assert_eq!(sid, "S-1-12-1-123-456-789-101");
    }
}
