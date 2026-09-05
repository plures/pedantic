use pedantic_executor::dsc::{DscCommand, DscError, DscInput, DscRunOptions, run_dsc};
use pluresdb::{CrdtStore, SledStorage, StorageEngine};
use pluresdb_chronos::{ChronosAction, ChronosEntry, ChronosTimeline};
use px_ast::{ConstraintDecl, Statement};
use px_eval::{ConstraintOutcome, PureFunctionRegistry};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    future::Future,
    io,
    path::{Path, PathBuf},
    sync::{Arc, OnceLock},
    time::Duration,
};
use thiserror::Error;
#[cfg(windows)]
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
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
const CONFIGURATION_LIFECYCLE_SOURCE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../praxis/procedures/pedantic-configuration-lifecycle.px"
));
static CONFIGURATION_CONSTRAINTS: OnceLock<Result<Vec<ConstraintDecl>, String>> = OnceLock::new();

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
        let storage = Arc::new(SledStorage::open(store_path).map_err(|error| {
            ServiceErrorKind::Foundation(format!("Unable to open profile PluresDB store: {error}"))
        })?);
        let store =
            Arc::new(CrdtStore::default().with_persistence(storage as Arc<dyn StorageEngine>));
        let timeline = ChronosTimeline::new(Arc::clone(&store));
        let foundation = Self {
            profile_id: profile_id.clone(),
            timeline,
            _store: store,
            revision_lock: tokio::sync::Mutex::new(()),
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
        self.record_evidence_summary(evidence);
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
            let decision = evaluate_configuration_constraint(constraint_name, &variables)?;
            if !decision.accepted {
                let validation = ConfigurationValidation {
                    revision_id: request.revision_id,
                    decision: "rejected".into(),
                    constraint_id: decision.constraint_id,
                    reason: decision.reason,
                };
                self.record_configuration_validation_evidence(&revision_key, &validation);
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
        self.record_configuration_validation(&revision_key, &validation);
        Ok(validation)
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
        self.record_evidence_summary(entry);
        self._store
            .put(self.evidence_key(), SERVICE_ACTOR, metadata.clone());
    }

    fn record_evidence_summary(&self, entry: ChronosEntry) {
        let _ = self.timeline.record(&entry);
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
    }

    fn record_configuration_validation(
        &self,
        revision_key: &str,
        validation: &ConfigurationValidation,
    ) {
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
        self.record_evidence_summary(entry);
    }

    fn record_configuration_validation_evidence(
        &self,
        revision_key: &str,
        validation: &ConfigurationValidation,
    ) {
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
        self.record_evidence_summary(entry);
    }

    fn configuration_key(&self, revision_id: &str) -> String {
        format!("pedantic:configuration:{}:{revision_id}", self.profile_id)
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

struct PxConstraintDecision {
    accepted: bool,
    constraint_id: String,
    reason: String,
}

fn evaluate_configuration_constraint(
    constraint_name: &str,
    variables: &HashMap<String, serde_json::Value>,
) -> Result<PxConstraintDecision, ServiceErrorKind> {
    let constraint = configuration_constraint(constraint_name)?;
    let registry = PureFunctionRegistry;
    let outcome = px_eval::eval_constraint(constraint, variables, &registry).map_err(|error| {
        ServiceErrorKind::Foundation(format!(
            "PX configuration admission evaluation failed: {error}"
        ))
    })?;
    let constraint_id = constraint.name.name.clone();
    let (accepted, reason) = match outcome {
        ConstraintOutcome::Satisfied => (true, "PX constraint accepted the request.".to_owned()),
        ConstraintOutcome::Violated { message, .. } => (
            false,
            message.unwrap_or_else(|| "PX constraint rejected the configuration revision.".into()),
        ),
        ConstraintOutcome::NotApplicable => (
            false,
            "PX configuration constraint was not applicable.".to_owned(),
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

fn dsc_validation_error(error: DscError) -> ServiceErrorKind {
    let message = match error {
        DscError::NotFound => {
            "DSC configuration validation is unavailable because dsc is not installed."
        }
        DscError::Timeout(_) => "DSC configuration validation exceeded the bounded timeout.",
        DscError::Spawn(_) | DscError::Io(_) => "DSC configuration validation could not start.",
        DscError::Parse(_) => "DSC configuration validation returned an unsupported result.",
        DscError::Yaml(_) => "DSC configuration validation could not serialize the document.",
        DscError::SshConnection(_) => "DSC configuration validation could not reach its adapter.",
        DscError::Execution { .. } => "DSC rejected the configuration document.",
    };
    ServiceErrorKind::Foundation(message.into())
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

#[derive(Debug, Deserialize)]
pub struct LocalServiceRequest {
    pub id: String,
    pub method: String,
    #[serde(rename = "profileId")]
    pub profile_id: String,
    pub authorization: String,
    #[serde(default)]
    pub params: serde_json::Value,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct LocalServiceResponse {
    pub id: Option<String>,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ServiceError>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct ServiceError {
    pub code: &'static str,
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

pub struct RequestHandlers<F, G, H> {
    pub evidence: F,
    pub admission: G,
    pub validation: H,
}

pub async fn handle_request<F, G, H, AdmissionFuture, ValidationFuture>(
    frame: &str,
    expected_profile: &str,
    expected_token: &str,
    version: &str,
    chronos_entries: usize,
    handlers: RequestHandlers<F, G, H>,
) -> LocalServiceResponse
where
    F: FnOnce() -> EvidencePage,
    G: FnOnce(ConfigurationAdmissionRequest) -> AdmissionFuture,
    H: FnOnce(ConfigurationValidationRequest) -> ValidationFuture,
    AdmissionFuture: Future<Output = Result<ConfigurationAdmission, ServiceErrorKind>>,
    ValidationFuture: Future<Output = Result<ConfigurationValidation, ServiceErrorKind>>,
{
    let request = match serde_json::from_str::<LocalServiceRequest>(frame) {
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

pub fn validate_token(token: &str) -> Result<(), ServiceErrorKind> {
    if token.len() < 32 {
        return Err(ServiceErrorKind::InvalidRequest(
            "PEDANTIC_LOCAL_TOKEN must contain at least 32 bytes.".into(),
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
        error: error.map(|(code, message)| ServiceError { code, message }),
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

    fn test_handlers() -> RequestHandlers<
        impl FnOnce() -> EvidencePage,
        impl FnOnce(
            ConfigurationAdmissionRequest,
        ) -> std::future::Ready<Result<ConfigurationAdmission, ServiceErrorKind>>,
        impl FnOnce(
            ConfigurationValidationRequest,
        ) -> std::future::Ready<Result<ConfigurationValidation, ServiceErrorKind>>,
    > {
        RequestHandlers {
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
        }
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
