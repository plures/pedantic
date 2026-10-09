//! Transport-neutral authenticated message exchange.
//!
//! This crate deliberately carries opaque payload bytes. Enrollment, grants,
//! observation ordering, and all other domain decisions belong to the service
//! and target agent crates.

use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, Signer, Verifier as _, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::Mutex;

pub const AUTHENTICATED_ENVELOPE_VERSION: &str = "pedantic.authenticated-envelope.v1";

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthenticatedEnvelope {
    pub schema_version: String,
    pub sender_id: String,
    pub key_id: String,
    pub payload_digest: String,
    pub payload: Vec<u8>,
    pub signature: String,
}

impl AuthenticatedEnvelope {
    pub fn sign(
        sender_id: impl Into<String>,
        key_id: impl Into<String>,
        payload: Vec<u8>,
        key: &ed25519_dalek::SigningKey,
    ) -> Self {
        let mut envelope = Self {
            schema_version: AUTHENTICATED_ENVELOPE_VERSION.into(),
            sender_id: sender_id.into(),
            key_id: key_id.into(),
            payload_digest: payload_digest(&payload),
            payload,
            signature: String::new(),
        };
        envelope.signature = URL_SAFE_NO_PAD.encode(key.sign(&envelope.signing_payload()).to_bytes());
        envelope
    }

    pub fn signing_payload(&self) -> Vec<u8> {
        serde_json::to_vec(&(
            &self.schema_version,
            &self.sender_id,
            &self.key_id,
            &self.payload_digest,
            &self.payload,
        ))
        .expect("authenticated envelope fields are serializable")
    }
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum AuthenticationError {
    #[error("unsupported authenticated-envelope schema version")]
    UnsupportedSchema,
    #[error("authenticated envelope is missing a required identity")]
    MissingIdentity,
    #[error("authenticated envelope payload digest is invalid")]
    InvalidDigest,
    #[error("authenticated envelope signing key is unknown")]
    UnknownKey,
    #[error("authenticated envelope signature is invalid")]
    InvalidSignature,
}

#[derive(Default)]
pub struct Verifier {
    keys: BTreeMap<(String, String), VerifyingKey>,
}

impl Verifier {
    pub fn insert(&mut self, sender_id: String, key_id: String, key: VerifyingKey) {
        self.keys.insert((sender_id, key_id), key);
    }

    pub fn verify(&self, envelope: &AuthenticatedEnvelope) -> Result<(), AuthenticationError> {
        if envelope.schema_version != AUTHENTICATED_ENVELOPE_VERSION {
            return Err(AuthenticationError::UnsupportedSchema);
        }
        if envelope.sender_id.is_empty() || envelope.key_id.is_empty() {
            return Err(AuthenticationError::MissingIdentity);
        }
        if envelope.payload_digest != payload_digest(&envelope.payload) {
            return Err(AuthenticationError::InvalidDigest);
        }
        let key = self
            .keys
            .get(&(envelope.sender_id.clone(), envelope.key_id.clone()))
            .ok_or(AuthenticationError::UnknownKey)?;
        let bytes = URL_SAFE_NO_PAD
            .decode(&envelope.signature)
            .map_err(|_| AuthenticationError::InvalidSignature)?;
        let signature =
            Signature::from_slice(&bytes).map_err(|_| AuthenticationError::InvalidSignature)?;
        key.verify(&envelope.signing_payload(), &signature)
            .map_err(|_| AuthenticationError::InvalidSignature)
    }
}

pub fn payload_digest(payload: &[u8]) -> String {
    format!("sha256:{:x}", Sha256::digest(payload))
}

#[derive(Debug, Error)]
pub enum TransportError {
    #[error(transparent)]
    Serialization(#[from] serde_json::Error),
    #[error("transport handler failed: {0}")]
    Handler(String),
}

#[async_trait]
pub trait Transport: Send + Sync {
    async fn exchange(
        &self,
        envelope: AuthenticatedEnvelope,
    ) -> Result<AuthenticatedEnvelope, TransportError>;
}

#[async_trait]
pub trait ExchangeHandler: Send + Sync {
    async fn handle(
        &self,
        envelope: AuthenticatedEnvelope,
    ) -> Result<AuthenticatedEnvelope, TransportError>;
}

/// CI-safe local transport for protocol tests. It has no authorization or
/// operation semantics; those remain in the handler.
#[derive(Clone)]
pub struct InProcessTransport {
    handler: Arc<dyn ExchangeHandler>,
}

impl InProcessTransport {
    pub fn new(handler: Arc<dyn ExchangeHandler>) -> Self {
        Self { handler }
    }
}

#[async_trait]
impl Transport for InProcessTransport {
    async fn exchange(
        &self,
        envelope: AuthenticatedEnvelope,
    ) -> Result<AuthenticatedEnvelope, TransportError> {
        self.handler.handle(envelope).await
    }
}

/// A deterministic in-process endpoint useful for testing reconnect and
/// delivery behavior without a remote host.
#[derive(Clone, Default)]
pub struct RecordingEndpoint {
    received: Arc<Mutex<Vec<AuthenticatedEnvelope>>>,
}

impl RecordingEndpoint {
    pub async fn received(&self) -> Vec<AuthenticatedEnvelope> {
        self.received.lock().await.clone()
    }
}

#[async_trait]
impl ExchangeHandler for RecordingEndpoint {
    async fn handle(
        &self,
        envelope: AuthenticatedEnvelope,
    ) -> Result<AuthenticatedEnvelope, TransportError> {
        self.received.lock().await.push(envelope.clone());
        Ok(envelope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::SigningKey;

    #[test]
    fn rejects_tampered_authenticated_payload() {
        let key = SigningKey::from_bytes(&[3; 32]);
        let mut verifier = Verifier::default();
        verifier.insert("agent".into(), "key".into(), key.verifying_key());
        let mut envelope =
            AuthenticatedEnvelope::sign("agent", "key", b"immutable bytes".to_vec(), &key);
        envelope.payload.push(b'!');
        assert_eq!(
            verifier.verify(&envelope),
            Err(AuthenticationError::InvalidDigest)
        );
    }

    #[tokio::test]
    async fn in_process_transport_round_trips_opaque_authenticated_bytes() {
        let key = SigningKey::from_bytes(&[4; 32]);
        let endpoint = Arc::new(RecordingEndpoint::default());
        let transport = InProcessTransport::new(endpoint.clone());
        let request = AuthenticatedEnvelope::sign("agent", "key", vec![0, 1, 2], &key);
        assert_eq!(transport.exchange(request.clone()).await.unwrap(), request);
        assert_eq!(endpoint.received().await, vec![request]);
    }
}
