use serde::{Deserialize, Serialize};
use std::io;
use thiserror::Error;
#[cfg(windows)]
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

pub const MAX_FRAME_BYTES: usize = 64 * 1024;

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
}

pub fn pipe_name_for_profile(profile_id: &str) -> Result<String, ServiceErrorKind> {
    if !is_valid_profile_id(profile_id) {
        return Err(ServiceErrorKind::InvalidRequest(
            "Profile identifiers must be 1-64 characters of letters, numbers, underscores, or hyphens."
                .into(),
        ));
    }

    #[cfg(windows)]
    {
        let sid = current_user_sid()?;
        return Ok(format!(r"\\.\pipe\pedantic-{sid}-{profile_id}"));
    }

    #[cfg(not(windows))]
    Ok(format!("/tmp/pedantic-{profile_id}"))
}

pub fn handle_request(
    frame: &str,
    expected_profile: &str,
    expected_token: &str,
    version: &str,
) -> LocalServiceResponse {
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

    if !constant_time_equal(&request.authorization, expected_token) {
        return response(
            Some(request.id),
            false,
            None,
            Some(("unauthorized", "Local service authorization failed.".into())),
        );
    }
    if request.profile_id != expected_profile {
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
    if request.method != "service.health" {
        return response(
            Some(request.id),
            false,
            None,
            Some((
                "method_not_found",
                format!("Method '{}' is not registered.", request.method),
            )),
        );
    }

    response(
        Some(request.id),
        true,
        Some(serde_json::json!({
            "profileId": expected_profile,
            "service": "pedantic-service",
            "version": version,
        })),
        None,
    )
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
) -> Result<(), ServiceErrorKind> {
    use tokio::net::windows::named_pipe::ServerOptions;

    let mut server = ServerOptions::new()
        .first_pipe_instance(true)
        .create(pipe_name)?;
    loop {
        server.connect().await?;
        let connection = server;
        server = ServerOptions::new().create(pipe_name)?;
        let profile_id = profile_id.to_owned();
        let token = token.to_owned();
        let version = version.to_owned();
        tokio::spawn(async move {
            let _ = serve_connection(connection, &profile_id, &token, &version).await;
        });
    }
}

#[cfg(not(windows))]
pub async fn run(
    _pipe_name: &str,
    _profile_id: &str,
    _token: &str,
    _version: &str,
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
) -> Result<(), ServiceErrorKind> {
    let mut reader = BufReader::new(&mut connection);
    let mut frame = Vec::new();
    while reader.read_until(b'\n', &mut frame).await? > 0 {
        if frame.len() > MAX_FRAME_BYTES {
            break;
        }
        let line = String::from_utf8_lossy(&frame).trim().to_owned();
        if !line.is_empty() {
            let response = handle_request(&line, profile_id, token, version);
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

fn is_valid_profile_id(profile_id: &str) -> bool {
    !profile_id.is_empty()
        && profile_id.len() <= 64
        && profile_id.bytes().enumerate().all(|(index, byte)| {
            byte.is_ascii_alphanumeric() || byte == b'_' || (byte == b'-' && index > 0)
        })
}

fn constant_time_equal(left: &str, right: &str) -> bool {
    let mut difference = left.len() ^ right.len();
    for (a, b) in left.bytes().zip(right.bytes()) {
        difference |= usize::from(a ^ b);
    }
    difference == 0
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
    let line = String::from_utf8_lossy(&output.stdout);
    let sid = line
        .split(',')
        .nth(1)
        .map(|value| value.trim_matches('"').trim())
        .filter(|value| value.starts_with("S-"))
        .ok_or_else(|| ServiceErrorKind::InvalidRequest("Invalid Windows user SID.".into()))?;
    Ok(sid.to_owned())
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
        );
        assert_eq!(response.error.unwrap().code, "method_not_found");
    }
}
