use pluresdb::{CrdtStore, SledStorage, StorageEngine};
use pluresdb_chronos::{ChronosAction, ChronosEntry, ChronosTimeline};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    io,
    path::{Path, PathBuf},
    sync::Arc,
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

/// The local service is the sole owner of a profile's embedded PluresDB store.
///
/// It records transport lifecycle evidence only. PX admission, policy, and
/// effect authorization remain outside this host until a PX evaluator is wired
/// in at the service boundary.
pub struct ServiceFoundation {
    profile_id: String,
    timeline: ChronosTimeline,
    _store: Arc<CrdtStore>,
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

    fn record_start(&self, version: &str) {
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
        let _ = self.timeline.record(&entry);
        self._store
            .put(self.evidence_key(), SERVICE_ACTOR, metadata.clone());
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

pub fn handle_request<F>(
    frame: &str,
    expected_profile: &str,
    expected_token: &str,
    version: &str,
    chronos_entries: usize,
    evidence: F,
) -> LocalServiceResponse
where
    F: FnOnce() -> EvidencePage,
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
            let evidence = evidence();
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
                || foundation.recent_evidence(),
            );
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

    #[test]
    fn health_requires_the_profile_and_token() {
        let response = handle_request(
            r#"{"id":"1","method":"service.health","profileId":"default","authorization":"0123456789abcdef0123456789abcdef"}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            || EvidencePage {
                entries: Vec::new(),
                truncated: false,
            },
        );
        assert!(response.ok);
    }

    #[test]
    fn rejects_unregistered_methods() {
        let response = handle_request(
            r#"{"id":"1","method":"effect.execute","profileId":"default","authorization":"0123456789abcdef0123456789abcdef"}"#,
            "default",
            "0123456789abcdef0123456789abcdef",
            "0.1.0",
            1,
            || EvidencePage {
                entries: Vec::new(),
                truncated: false,
            },
        );
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

    #[test]
    fn evidence_list_is_available_to_the_authenticated_profile() {
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
            move || evidence,
        );
        assert!(response.ok);
    }

    #[test]
    fn evidence_list_rejects_an_invalid_token() {
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
            move || evidence,
        );
        assert_eq!(
            response.error.expect("unauthorized response").code,
            "unauthorized"
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
