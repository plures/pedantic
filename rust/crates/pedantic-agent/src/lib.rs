//! Target-local durable execution. This crate consumes PX grants and records
//! observed facts; it deliberately does not decide admission or retry policy.

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, Signer, Verifier, VerifyingKey};
use pedantic_capability::{CapabilityActivity, CapabilityError, CapabilityRegistry};
use pedantic_operation::{
    EffectAuthorization, OperationEvent, OperationState, RedactionClass, RetryClass,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use thiserror::Error;

pub const JOURNAL_SCHEMA_VERSION: &str = "pedantic.agent-journal.v1";
pub const EFFECT_AUTHORIZATION_SCHEMA_VERSION: &str = "pedantic.effect-authorization.v1";
pub const AGENT_ENROLLMENT_SCHEMA_VERSION: &str = "pedantic.agent-enrollment.v1";
pub const AGENT_OBSERVATION_BATCH_SCHEMA_VERSION: &str = "pedantic.agent-observation-batch.v1";

#[derive(Debug, Error)]
pub enum AgentError {
    #[error("journal I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("journal record is malformed: {0}")]
    Journal(#[from] serde_json::Error),
    #[error("authorization rejected: {0}")]
    Authorization(#[from] AuthorizationError),
    #[error(transparent)]
    Capability(#[from] CapabilityError),
    #[error("event {0} has already been journaled")]
    DuplicateEvent(String),
    #[error("a reboot was requested but the boot identity did not change")]
    UnchangedBootIdentity,
    #[error("agent enrollment is invalid: {0}")]
    Enrollment(&'static str),
    #[error("staged artifact digest does not match its immutable reference")]
    ArtifactDigest,
    #[error("staged artifact path is not a file")]
    ArtifactPath,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentEnrollment {
    pub schema_version: String,
    pub enrollment_id: String,
    pub agent_id: String,
    pub target_id: String,
    pub profile_id: String,
    pub public_key: String,
    pub issued_at: u64,
    pub expires_at: u64,
    #[serde(default)]
    pub secret_references: Vec<String>,
}

impl AgentEnrollment {
    pub fn validate(&self, now: u64) -> Result<(), AgentError> {
        if self.schema_version != AGENT_ENROLLMENT_SCHEMA_VERSION {
            return Err(AgentError::Enrollment("unsupported schema version"));
        }
        if self.enrollment_id.is_empty()
            || self.agent_id.is_empty()
            || self.target_id.is_empty()
            || self.profile_id.is_empty()
            || self.public_key.is_empty()
        {
            return Err(AgentError::Enrollment("required identity is empty"));
        }
        if self.agent_id == self.target_id {
            return Err(AgentError::Enrollment(
                "agent and target identities must remain distinct",
            ));
        }
        if self.expires_at <= now {
            return Err(AgentError::Enrollment("enrollment expired"));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ObservationSignature {
    pub algorithm: String,
    pub key_id: String,
    pub payload_digest: String,
    pub value: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentObservation {
    pub schema_version: String,
    pub event_id: String,
    pub command_id: String,
    pub operation_id: String,
    pub step_id: String,
    pub attempt_id: String,
    pub target_id: String,
    pub agent_id: String,
    pub sequence: u64,
    pub status: String,
    pub causation_id: String,
    pub correlation_id: String,
    pub redaction_class: RedactionClass,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_digest: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentObservationBatch {
    pub schema_version: String,
    pub batch_id: String,
    pub agent_id: String,
    pub target_id: String,
    pub profile_id: String,
    pub first_sequence: u64,
    pub last_sequence: u64,
    pub observations: Vec<AgentObservation>,
    pub signature: ObservationSignature,
}

impl AgentObservationBatch {
    pub fn sign(
        batch_id: String,
        profile_id: String,
        observations: Vec<AgentObservation>,
        key_id: String,
        key: &ed25519_dalek::SigningKey,
    ) -> Result<Self, AgentError> {
        let first = observations
            .first()
            .ok_or(AgentError::Enrollment("observation batch is empty"))?;
        let last = observations
            .last()
            .ok_or(AgentError::Enrollment("observation batch is empty"))?;
        if observations.iter().any(|observation| {
            observation.agent_id != first.agent_id || observation.target_id != first.target_id
        }) {
            return Err(AgentError::Enrollment("batch identities differ"));
        }
        let mut batch = Self {
            schema_version: AGENT_OBSERVATION_BATCH_SCHEMA_VERSION.into(),
            batch_id,
            agent_id: first.agent_id.clone(),
            target_id: first.target_id.clone(),
            profile_id,
            first_sequence: first.sequence,
            last_sequence: last.sequence,
            observations,
            signature: ObservationSignature {
                algorithm: "Ed25519".into(),
                key_id,
                payload_digest: String::new(),
                value: String::new(),
            },
        };
        batch.signature.payload_digest = batch.payload_digest();
        batch.signature.value =
            URL_SAFE_NO_PAD.encode(key.sign(&batch.signing_payload()).to_bytes());
        Ok(batch)
    }

    pub fn signing_payload(&self) -> Vec<u8> {
        let mut batch = self.clone();
        batch.signature.payload_digest.clear();
        batch.signature.value.clear();
        serde_json::to_vec(&batch).expect("observation batch is serializable")
    }

    pub fn payload_digest(&self) -> String {
        format!("sha256:{:x}", Sha256::digest(self.signing_payload()))
    }

    pub fn verify(&self, key: &VerifyingKey) -> Result<(), AuthorizationError> {
        if self.schema_version != AGENT_OBSERVATION_BATCH_SCHEMA_VERSION
            || self.signature.algorithm != "Ed25519"
            || self.batch_id.is_empty()
            || self.agent_id.is_empty()
            || self.target_id.is_empty()
            || self.profile_id.is_empty()
            || self.observations.is_empty()
            || self.first_sequence == 0
            || self.last_sequence < self.first_sequence
            || self.signature.payload_digest != self.payload_digest()
            || self
                .observations
                .first()
                .is_none_or(|event| event.sequence != self.first_sequence)
            || self
                .observations
                .last()
                .is_none_or(|event| event.sequence != self.last_sequence)
            || self
                .observations
                .windows(2)
                .any(|pair| pair[1].sequence != pair[0].sequence + 1)
            || self.observations.iter().any(|event| {
                event.agent_id != self.agent_id
                    || event.target_id != self.target_id
                    || event.event_id.is_empty()
            })
        {
            return Err(AuthorizationError::PayloadDigest);
        }
        let signature = URL_SAFE_NO_PAD
            .decode(&self.signature.value)
            .map_err(|_| AuthorizationError::Signature)?;
        let signature =
            Signature::from_slice(&signature).map_err(|_| AuthorizationError::Signature)?;
        key.verify(&self.signing_payload(), &signature)
            .map_err(|_| AuthorizationError::Signature)
    }
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum AuthorizationError {
    #[error("unsupported authorization schema version")]
    Schema,
    #[error("authorization has expired")]
    Expired,
    #[error("authorization is revoked")]
    Revoked,
    #[error("authorization binding mismatch: {0}")]
    Binding(&'static str),
    #[error("authorization payload digest is invalid")]
    PayloadDigest,
    #[error("authorization signing key is unknown")]
    UnknownKey,
    #[error("authorization signature is invalid")]
    Signature,
}

#[derive(Clone, Debug)]
pub struct AuthorizationContext<'a> {
    pub target_id: &'a str,
    pub agent_id: &'a str,
    pub capability: &'a str,
    pub input_digest: &'a str,
    pub now: u64,
}

pub trait AuthorizationVerifier: Send + Sync {
    fn validate(
        &self,
        authorization: &EffectAuthorization,
        context: &AuthorizationContext<'_>,
    ) -> Result<(), AuthorizationError>;
}

#[derive(Default)]
pub struct Ed25519AuthorizationVerifier {
    keys: BTreeMap<String, VerifyingKey>,
}

impl Ed25519AuthorizationVerifier {
    pub fn insert(&mut self, key_id: String, key: VerifyingKey) {
        self.keys.insert(key_id, key);
    }
}

impl AuthorizationVerifier for Ed25519AuthorizationVerifier {
    fn validate(
        &self,
        authorization: &EffectAuthorization,
        context: &AuthorizationContext<'_>,
    ) -> Result<(), AuthorizationError> {
        if authorization.schema_version != EFFECT_AUTHORIZATION_SCHEMA_VERSION {
            return Err(AuthorizationError::Schema);
        }
        if authorization.expires_at <= context.now {
            return Err(AuthorizationError::Expired);
        }
        if authorization.revoked_at != 0 && authorization.revoked_at <= context.now {
            return Err(AuthorizationError::Revoked);
        }
        for (actual, expected, name) in [
            (&authorization.target_id, context.target_id, "target"),
            (&authorization.agent_id, context.agent_id, "agent"),
            (&authorization.capability, context.capability, "capability"),
            (
                &authorization.input_digest,
                context.input_digest,
                "input digest",
            ),
        ] {
            if actual != expected {
                return Err(AuthorizationError::Binding(name));
            }
        }
        if authorization.signature.algorithm != "Ed25519"
            || authorization.signature.payload_digest != authorization.digest()
        {
            return Err(AuthorizationError::PayloadDigest);
        }
        let key = self
            .keys
            .get(&authorization.signature.key_id)
            .ok_or(AuthorizationError::UnknownKey)?;
        let bytes = URL_SAFE_NO_PAD
            .decode(&authorization.signature.value)
            .map_err(|_| AuthorizationError::Signature)?;
        let signature = Signature::from_slice(&bytes).map_err(|_| AuthorizationError::Signature)?;
        key.verify(&authorization.signing_payload(), &signature)
            .map_err(|_| AuthorizationError::Signature)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentIdentity {
    pub agent_id: String,
    pub key_id: String,
    pub private_key: String,
}

impl AgentIdentity {
    pub fn load_or_create(
        path: impl AsRef<Path>,
        agent_id: impl Into<String>,
        key_id: impl Into<String>,
        private_key: impl Into<String>,
    ) -> Result<Self, AgentError> {
        let path = path.as_ref();
        if path.exists() {
            return Ok(serde_json::from_reader(File::open(path)?)?);
        }
        let identity = Self {
            agent_id: agent_id.into(),
            key_id: key_id.into(),
            private_key: private_key.into(),
        };
        let temporary = path.with_extension("tmp");
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        options.mode(0o600);
        let mut file = options.open(&temporary)?;
        serde_json::to_writer(&mut file, &identity)?;
        file.sync_all()?;
        std::fs::rename(temporary, path)?;
        Ok(identity)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JournalRecord {
    pub schema_version: String,
    pub event: OperationEvent,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authorization_digest: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_class: Option<RetryClass>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkpoint: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resume_after: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub boot_identity: Option<String>,
    pub redaction_class: RedactionClass,
    pub synchronized: bool,
}

impl JournalRecord {
    pub fn new(event: OperationEvent, redaction_class: RedactionClass) -> Self {
        Self {
            schema_version: JOURNAL_SCHEMA_VERSION.into(),
            event,
            authorization_digest: None,
            retry_class: None,
            checkpoint: None,
            resume_after: None,
            boot_identity: None,
            redaction_class,
            synchronized: false,
        }
    }
}

pub struct Journal {
    path: PathBuf,
    records: Vec<JournalRecord>,
    event_ids: BTreeSet<String>,
}

impl Journal {
    pub fn open(path: impl Into<PathBuf>) -> Result<Self, AgentError> {
        let path = path.into();
        let mut records = Vec::new();
        let mut event_ids = BTreeSet::new();
        if path.exists() {
            for line in BufReader::new(File::open(&path)?).lines() {
                let line = line?;
                if line.is_empty() {
                    continue;
                }
                let record: JournalRecord = serde_json::from_str(&line)?;
                event_ids.insert(record.event.event_id.clone());
                records.push(record);
            }
        }
        Ok(Self {
            path,
            records,
            event_ids,
        })
    }

    pub fn records(&self) -> &[JournalRecord] {
        &self.records
    }

    pub fn append(&mut self, record: JournalRecord) -> Result<bool, AgentError> {
        if self.event_ids.contains(&record.event.event_id) {
            return Ok(false);
        }
        let encoded = serde_json::to_vec(&record)?;
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        file.write_all(&encoded)?;
        file.write_all(b"\n")?;
        file.sync_data()?;
        self.event_ids.insert(record.event.event_id.clone());
        self.records.push(record);
        Ok(true)
    }

    pub fn mark_synchronized(&mut self, event_id: &str) -> Result<(), AgentError> {
        let Some(record) = self
            .records
            .iter_mut()
            .find(|record| record.event.event_id == event_id)
        else {
            return Ok(());
        };
        if record.synchronized {
            return Ok(());
        }
        record.synchronized = true;
        self.rewrite()
    }

    pub fn due_suspensions(&self, now: u64) -> Vec<&JournalRecord> {
        self.records
            .iter()
            .filter(|record| {
                record.event.event_type == "step.suspended"
                    && record
                        .resume_after
                        .is_some_and(|resume_after| resume_after <= now)
            })
            .collect()
    }

    fn rewrite(&self) -> Result<(), AgentError> {
        let temporary = self.path.with_extension("tmp");
        let mut file = File::create(&temporary)?;
        for record in &self.records {
            serde_json::to_writer(&mut file, record)?;
            file.write_all(b"\n")?;
        }
        file.sync_all()?;
        std::fs::rename(temporary, &self.path)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RecoveryOutcome {
    Resume { event_id: String },
    NeedsReview { event_id: String },
}

pub fn recover(journal: &Journal) -> Vec<RecoveryOutcome> {
    let mut active = BTreeMap::<(String, String, String), &JournalRecord>::new();
    for record in journal.records() {
        let Some(step_id) = &record.event.step_id else {
            continue;
        };
        let Some(attempt_id) = &record.event.attempt_id else {
            continue;
        };
        let key = (
            record.event.operation_id.clone(),
            step_id.clone(),
            attempt_id.clone(),
        );
        match record.event.event_type.as_str() {
            "step.started" => {
                active.insert(key, record);
            }
            "step.completed" | "step.failed" | "step.needs_review" => {
                active.remove(&key);
            }
            _ => {}
        }
    }
    active
        .into_values()
        .map(|record| {
            if record.event.resulting_state == OperationState::NeedsReview
                || record.retry_class != Some(RetryClass::Safe)
            {
                RecoveryOutcome::NeedsReview {
                    event_id: record.event.event_id.clone(),
                }
            } else if record
                .authorization_digest
                .as_ref()
                .is_some_and(|_| record.event.event_type == "step.started")
            {
                RecoveryOutcome::Resume {
                    event_id: record.event.event_id.clone(),
                }
            } else {
                RecoveryOutcome::NeedsReview {
                    event_id: record.event.event_id.clone(),
                }
            }
        })
        .collect()
}

pub struct LocalAgent {
    pub identity: AgentIdentity,
    pub target_id: String,
    pub journal: Journal,
    registry: CapabilityRegistry,
    verifier: Arc<dyn AuthorizationVerifier>,
}

impl LocalAgent {
    pub fn new_with_production_providers(
        identity: AgentIdentity,
        target_id: String,
        journal: Journal,
        verifier: Arc<dyn AuthorizationVerifier>,
    ) -> Result<Self, AgentError> {
        let registry = pedantic_provider_pack::production_registry()?;
        Ok(Self::new(identity, target_id, journal, registry, verifier))
    }

    pub fn new(
        identity: AgentIdentity,
        target_id: String,
        journal: Journal,
        registry: CapabilityRegistry,
        verifier: Arc<dyn AuthorizationVerifier>,
    ) -> Self {
        Self {
            identity,
            target_id,
            journal,
            registry,
            verifier,
        }
    }

    pub fn execute(
        &mut self,
        authorization: &EffectAuthorization,
        input: &serde_json::Value,
        now: u64,
        started: OperationEvent,
        completed: OperationEvent,
    ) -> Result<serde_json::Value, AgentError> {
        let capability = self.registry.resolve(&authorization.capability)?;
        self.verifier.validate(
            authorization,
            &AuthorizationContext {
                target_id: &self.target_id,
                agent_id: &self.identity.agent_id,
                capability: &authorization.capability,
                input_digest: &authorization.input_digest,
                now,
            },
        )?;
        let mut start = JournalRecord::new(
            started.clone(),
            capability.manifest().redaction_class.clone(),
        );
        start.authorization_digest = Some(authorization.digest());
        start.retry_class = Some(authorization.retry_class.clone());
        self.journal.append(start)?;
        let (output, next_sequence) = {
            let mut next_sequence = started.sequence.saturating_add(1);
            let activity_event = started;
            let journal = &mut self.journal;
            let mut activity_sink = |activity: CapabilityActivity| {
                if !matches!(activity.event, "step.progressed" | "step.heartbeat") {
                    return Err(CapabilityError::Execution(
                        "capability emitted an unsupported activity event".into(),
                    ));
                }
                let mut event = activity_event.clone();
                event.event_id = format!("{}:activity:{next_sequence}", activity_event.event_id);
                event.event_type = activity.event.into();
                event.resulting_state = OperationState::Running;
                event.sequence = next_sequence;
                event.occurred_at = Some(now);
                next_sequence = next_sequence.saturating_add(1);
                journal
                    .append(JournalRecord::new(
                        event,
                        capability.manifest().redaction_class.clone(),
                    ))
                    .map_err(|error| CapabilityError::Execution(error.to_string()))?;
                Ok(())
            };
            let output = capability.execute_with_activity(input, &mut activity_sink)?;
            (output, next_sequence)
        };
        let mut completed = completed;
        completed.sequence = completed.sequence.max(next_sequence);
        self.journal.append(JournalRecord::new(
            completed,
            capability.manifest().redaction_class.clone(),
        ))?;
        Ok(output)
    }

    pub fn reboot_observed(
        &mut self,
        prior_boot_identity: &str,
        current_boot_identity: &str,
        event: OperationEvent,
    ) -> Result<(), AgentError> {
        if prior_boot_identity == current_boot_identity {
            return Err(AgentError::UnchangedBootIdentity);
        }
        let mut record = JournalRecord::new(event, RedactionClass::MetadataOnly);
        record.boot_identity = Some(current_boot_identity.into());
        self.journal.append(record)?;
        Ok(())
    }
}

pub fn output_digest(value: &serde_json::Value) -> String {
    format!(
        "sha256:{:x}",
        Sha256::digest(serde_json::to_vec(value).expect("value is serializable"))
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use pedantic_capability::Capability;
    use pedantic_operation::{CapabilityManifest, Idempotency, RiskClass};
    use serde_json::json;
    use tempfile::tempdir;

    struct TestCapability {
        manifest: CapabilityManifest,
        calls: std::sync::atomic::AtomicUsize,
    }

    impl Capability for TestCapability {
        fn manifest(&self) -> &CapabilityManifest {
            &self.manifest
        }

        fn readiness(
            &self,
            target: &str,
            agent: &str,
            now: u64,
        ) -> pedantic_operation::CapabilityReadiness {
            pedantic_operation::CapabilityReadiness {
                schema_version: "pedantic.capability-readiness.v1".into(),
                capability: self.manifest.capability.clone(),
                version: self.manifest.version.clone(),
                target_id: target.into(),
                agent_id: agent.into(),
                observed_at: now,
                ready: true,
                redaction_class: RedactionClass::MetadataOnly,
                state: Some("ready".into()),
                required: Some(true),
                findings: vec![],
                eligible_remediations: vec![],
                diagnostics: vec![],
            }
        }

        fn execute_unchecked(
            &self,
            _input: &serde_json::Value,
        ) -> Result<serde_json::Value, CapabilityError> {
            self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Ok(json!({"safe": true}))
        }

        fn execute_unchecked_with_activity(
            &self,
            input: &serde_json::Value,
            activity_sink: &mut dyn FnMut(CapabilityActivity) -> Result<(), CapabilityError>,
        ) -> Result<serde_json::Value, CapabilityError> {
            activity_sink(CapabilityActivity {
                event: "step.progressed",
                detail: "test capability progress".into(),
            })?;
            self.execute_unchecked(input)
        }
    }

    fn event(id: &str, event_type: &str, state: OperationState) -> OperationEvent {
        OperationEvent {
            schema_version: "pedantic.operation-event.v1".into(),
            event_id: id.into(),
            event_type: event_type.into(),
            resulting_state: state,
            operation_id: "operation".into(),
            plan_id: "plan".into(),
            step_id: Some("step".into()),
            attempt_id: Some("attempt".into()),
            profile_id: "profile".into(),
            actor_id: "actor".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            causation_id: "cause".into(),
            correlation_id: "correlation".into(),
            sequence: 1,
            occurred_at: Some(1),
        }
    }

    fn authorization(key: &SigningKey, retry_class: RetryClass) -> EffectAuthorization {
        let mut authorization = EffectAuthorization {
            schema_version: EFFECT_AUTHORIZATION_SCHEMA_VERSION.into(),
            authorization_id: "authorization".into(),
            issuer_id: "px".into(),
            actor_id: "actor".into(),
            profile_id: "profile".into(),
            operation_id: "operation".into(),
            step_id: "step".into(),
            attempt_id: "attempt".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            capability: "test.capability/v1".into(),
            input_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                .into(),
            idempotency_key: "key".into(),
            fencing_token: 1,
            retry_class,
            risk_class: RiskClass::Low,
            reboot_permitted: false,
            issued_at: 1,
            expires_at: 100,
            revoked_at: 0,
            signature: pedantic_operation::Signature {
                algorithm: "Ed25519".into(),
                key_id: "issuer".into(),
                payload_digest: String::new(),
                value: String::new(),
            },
        };
        authorization.signature.payload_digest = authorization.digest();
        authorization.signature.value =
            URL_SAFE_NO_PAD.encode(key.sign(&authorization.signing_payload()).to_bytes());
        authorization
    }

    fn registry(capability: Arc<TestCapability>) -> CapabilityRegistry {
        let mut registry = CapabilityRegistry::default();
        registry.register(capability).unwrap();
        registry
    }

    fn capability() -> Arc<TestCapability> {
        Arc::new(TestCapability {
            manifest: CapabilityManifest {
                schema_version: "pedantic.capability-manifest.v1".into(),
                capability: "test.capability".into(),
                version: "v1".into(),
                risk_class: RiskClass::Low,
                retry_class: RetryClass::Safe,
                idempotency: Idempotency::Idempotent,
                redaction_class: RedactionClass::MetadataOnly,
                requires_approval: Some(false),
                requires_checkpoint: Some(false),
                input_schema: None,
                output_schema: None,
            },
            calls: std::sync::atomic::AtomicUsize::new(0),
        })
    }

    #[cfg(unix)]
    #[test]
    fn agent_identity_private_key_file_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;

        let directory = tempdir().unwrap();
        let path = directory.path().join("identity.json");
        AgentIdentity::load_or_create(&path, "agent", "key", "private").unwrap();
        let mode = std::fs::metadata(path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[test]
    fn rejects_unbound_or_expired_authorization_before_effect() {
        let signing_key = SigningKey::from_bytes(&[7; 32]);
        let mut verifier = Ed25519AuthorizationVerifier::default();
        verifier.insert("issuer".into(), signing_key.verifying_key());
        let directory = tempdir().unwrap();
        let adapter = capability();
        let mut agent = LocalAgent::new(
            AgentIdentity {
                agent_id: "agent".into(),
                key_id: "local".into(),
                private_key: "opaque".into(),
            },
            "target".into(),
            Journal::open(directory.path().join("journal")).unwrap(),
            registry(adapter.clone()),
            Arc::new(verifier),
        );
        let mut grant = authorization(&signing_key, RetryClass::Safe);
        grant.expires_at = 2;
        let result = agent.execute(
            &grant,
            &json!({}),
            2,
            event("start", "step.started", OperationState::Running),
            event("done", "step.completed", OperationState::Succeeded),
        );
        assert!(matches!(
            result,
            Err(AgentError::Authorization(AuthorizationError::Expired))
        ));
        assert_eq!(adapter.calls.load(std::sync::atomic::Ordering::SeqCst), 0);
    }

    #[test]
    fn execution_activity_is_journaled_between_start_and_completion() {
        let signing_key = SigningKey::from_bytes(&[7; 32]);
        let mut verifier = Ed25519AuthorizationVerifier::default();
        verifier.insert("issuer".into(), signing_key.verifying_key());
        let directory = tempdir().unwrap();
        let adapter = capability();
        let mut agent = LocalAgent::new(
            AgentIdentity {
                agent_id: "agent".into(),
                key_id: "local".into(),
                private_key: "opaque".into(),
            },
            "target".into(),
            Journal::open(directory.path().join("journal")).unwrap(),
            registry(adapter),
            Arc::new(verifier),
        );
        agent
            .execute(
                &authorization(&signing_key, RetryClass::Safe),
                &json!({}),
                2,
                event("start", "step.started", OperationState::Running),
                event("done", "step.completed", OperationState::Running),
            )
            .unwrap();

        let records = agent.journal.records();
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].event.event_type, "step.started");
        assert_eq!(records[1].event.event_type, "step.progressed");
        assert_eq!(records[2].event.event_type, "step.completed");
        assert_eq!(
            records
                .iter()
                .map(|record| record.event.sequence)
                .collect::<Vec<_>>(),
            vec![1, 2, 3]
        );
    }

    #[test]
    fn production_constructor_registers_the_provider_pack() {
        let directory = tempdir().unwrap();
        let agent = LocalAgent::new_with_production_providers(
            AgentIdentity {
                agent_id: "agent".into(),
                key_id: "local".into(),
                private_key: "opaque".into(),
            },
            "target".into(),
            Journal::open(directory.path().join("journal")).unwrap(),
            Arc::new(Ed25519AuthorizationVerifier::default()),
        )
        .unwrap();
        assert!(agent.registry.resolve("transfer.filesystem/v1").is_ok());
        assert!(agent.registry.resolve("hyperv.vm/v1").is_ok());
    }

    #[test]
    fn rejects_tampered_signature_digest_and_target_bindings() {
        let signing_key = SigningKey::from_bytes(&[8; 32]);
        let mut verifier = Ed25519AuthorizationVerifier::default();
        verifier.insert("issuer".into(), signing_key.verifying_key());
        let context = AuthorizationContext {
            target_id: "target",
            agent_id: "agent",
            capability: "test.capability/v1",
            input_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            now: 2,
        };
        let grant = authorization(&signing_key, RetryClass::Safe);
        verifier.validate(&grant, &context).unwrap();

        let mut target_tampered = grant.clone();
        target_tampered.target_id = "other-target".into();
        assert_eq!(
            verifier.validate(&target_tampered, &context),
            Err(AuthorizationError::Binding("target"))
        );

        let mut digest_tampered = grant.clone();
        digest_tampered.input_digest =
            "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into();
        assert_eq!(
            verifier.validate(&digest_tampered, &context),
            Err(AuthorizationError::Binding("input digest"))
        );

        let mut signature_tampered = grant;
        signature_tampered.signature.value.replace_range(0..1, "B");
        assert_eq!(
            verifier.validate(&signature_tampered, &context),
            Err(AuthorizationError::Signature)
        );
    }

    #[test]
    fn recovery_never_replays_interrupted_unsafe_effect() {
        let directory = tempdir().unwrap();
        let mut journal = Journal::open(directory.path().join("journal")).unwrap();
        let mut started = JournalRecord::new(
            event("start", "step.started", OperationState::Running),
            RedactionClass::MetadataOnly,
        );
        started.authorization_digest =
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into());
        started.retry_class = Some(RetryClass::SafeAfterObservation);
        journal.append(started).unwrap();
        assert_eq!(
            recover(&journal),
            vec![RecoveryOutcome::NeedsReview {
                event_id: "start".into()
            }]
        );
    }

    #[test]
    fn recovery_resumes_interrupted_safe_validation() {
        let directory = tempdir().unwrap();
        let mut journal = Journal::open(directory.path().join("journal")).unwrap();
        let mut started = JournalRecord::new(
            event("start", "step.started", OperationState::Running),
            RedactionClass::MetadataOnly,
        );
        started.authorization_digest =
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into());
        started.retry_class = Some(RetryClass::Safe);
        journal.append(started).unwrap();
        drop(journal);
        let journal = Journal::open(directory.path().join("journal")).unwrap();
        assert_eq!(
            recover(&journal),
            vec![RecoveryOutcome::Resume {
                event_id: "start".into()
            }]
        );
    }

    #[test]
    fn resume_after_is_due_without_polling() {
        let directory = tempdir().unwrap();
        let mut journal = Journal::open(directory.path().join("journal")).unwrap();
        let mut suspended = JournalRecord::new(
            event("suspended", "step.suspended", OperationState::Waiting),
            RedactionClass::MetadataOnly,
        );
        suspended.resume_after = Some(10);
        journal.append(suspended).unwrap();
        assert!(journal.due_suspensions(9).is_empty());
        assert_eq!(journal.due_suspensions(10).len(), 1);
    }

    #[test]
    fn journal_deduplicates_and_does_not_store_input_secrets() {
        let directory = tempdir().unwrap();
        let path = directory.path().join("journal");
        let mut journal = Journal::open(&path).unwrap();
        let record = JournalRecord::new(
            event("start", "step.started", OperationState::Running),
            RedactionClass::MetadataOnly,
        );
        assert!(journal.append(record.clone()).unwrap());
        assert!(!journal.append(record).unwrap());
        let contents = std::fs::read_to_string(path).unwrap();
        assert_eq!(contents.lines().count(), 1);
        assert!(!contents.contains("plaintext-secret"));
    }

    #[test]
    fn reboot_requires_a_new_boot_identity() {
        let directory = tempdir().unwrap();
        let mut agent = LocalAgent::new(
            AgentIdentity {
                agent_id: "agent".into(),
                key_id: "local".into(),
                private_key: "opaque".into(),
            },
            "target".into(),
            Journal::open(directory.path().join("journal")).unwrap(),
            CapabilityRegistry::default(),
            Arc::new(Ed25519AuthorizationVerifier::default()),
        );
        assert!(matches!(
            agent.reboot_observed(
                "boot-1",
                "boot-1",
                event(
                    "boot",
                    "step.reboot_observed",
                    OperationState::AwaitingReboot
                )
            ),
            Err(AgentError::UnchangedBootIdentity)
        ));
        agent
            .reboot_observed(
                "boot-1",
                "boot-2",
                event("boot", "step.reboot_observed", OperationState::Running),
            )
            .unwrap();
        assert_eq!(agent.journal.records().len(), 1);
    }

    #[test]
    fn enrollment_requires_distinct_unexpired_agent_and_target_identities() {
        let enrollment = AgentEnrollment {
            schema_version: AGENT_ENROLLMENT_SCHEMA_VERSION.into(),
            enrollment_id: "enrollment".into(),
            agent_id: "agent".into(),
            target_id: "target".into(),
            profile_id: "profile".into(),
            public_key: "public-key".into(),
            issued_at: 1,
            expires_at: 2,
            secret_references: Vec::new(),
        };
        enrollment.validate(1).unwrap();

        let mut conflated = enrollment.clone();
        conflated.target_id = conflated.agent_id.clone();
        assert!(matches!(
            conflated.validate(1),
            Err(AgentError::Enrollment(
                "agent and target identities must remain distinct"
            ))
        ));
        assert!(matches!(
            enrollment.validate(2),
            Err(AgentError::Enrollment("enrollment expired"))
        ));
    }

    #[test]
    fn signed_observation_batches_reject_tampering_and_sequence_gaps() {
        let key = SigningKey::from_bytes(&[9; 32]);
        let observation = AgentObservation {
            schema_version: "pedantic.effect-observation.v1".into(),
            event_id: "event-1".into(),
            command_id: "command-1".into(),
            operation_id: "operation".into(),
            step_id: "step".into(),
            attempt_id: "attempt".into(),
            target_id: "target".into(),
            agent_id: "agent".into(),
            sequence: 1,
            status: "completed".into(),
            causation_id: "cause".into(),
            correlation_id: "correlation".into(),
            redaction_class: RedactionClass::MetadataOnly,
            output_digest: None,
        };
        let mut batch = AgentObservationBatch::sign(
            "batch".into(),
            "profile".into(),
            vec![observation],
            "key".into(),
            &key,
        )
        .unwrap();
        batch.verify(&key.verifying_key()).unwrap();
        batch.observations[0].event_id = "tampered".into();
        assert_eq!(
            batch.verify(&key.verifying_key()),
            Err(AuthorizationError::PayloadDigest)
        );
    }
}
