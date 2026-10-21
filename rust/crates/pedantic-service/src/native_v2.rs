use super::*;
use pedantic_operation::{
    durable_coordinator::{DurableCoordinator, EffectLease, PlanAuthority},
    native_v2::{
        self as contract, EffectContext, ExecutionIdentity, canonical_bytes, resolved_plan_digest,
        sign_authorization, verify_effect_authorization,
    },
};
use serde_json::{Value, json};
use std::collections::BTreeSet;

pub const REQUEST_VERSION: &str = "pedantic.local-service-request.v2";
const STATE_VERSION: &str = "pedantic.remediation-authority.v2";
const STEP: &str = "dsc-config-set";
const CAPABILITY: &str = "dsc.config.apply/v1";
const POLICY: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../praxis/procedures/pedantic-v2-remediation-authority.px"
));

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LocalRequest {
    schema_version: String,
    id: String,
    method: String,
    profile_id: String,
    authorization: String,
    params: Value,
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "method", content = "params")]
pub enum Command {
    #[serde(rename = "effect.authorize")]
    Authorize(AuthorizationRequest),
    #[serde(rename = "effect.verify")]
    Verify(VerificationRequest),
    #[serde(rename = "effect.revoke")]
    Revoke(RevocationRequest),
    #[serde(rename = "remediation.execute")]
    Execute(ExecutionRequest),
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AuthorizationRequest {
    pub approval_id: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VerificationRequest {
    pub authorization_id: String,
    pub authorization: Value,
    pub input_digest: String,
    pub idempotency_key: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RevocationRequest {
    pub authorization_id: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecutionRequest {
    pub execution_id: String,
    pub authorization_id: String,
    pub idempotency_key: String,
    pub document: String,
    pub authorization: Value,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AuthorizationResult {
    pub plan: Value,
    pub authorization: Value,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AuthorityRecord {
    schema_version: String,
    authorization_id: String,
    plan: Value,
    authorization: Value,
    coordinator: DurableCoordinator,
    lease: EffectLease,
}

struct ApprovedRemediation {
    request: RemediationApprovalRequest,
    revision_id: String,
    source_digest: String,
    idempotency_key: String,
    plan: Value,
}

fn invalid(message: &str) -> ServiceErrorKind {
    ServiceErrorKind::InvalidRequest(message.into())
}

fn contract_error(error: contract::ContractError) -> ServiceErrorKind {
    invalid(&format!("Native v2 contract rejected: {}.", error.code()))
}

fn v2_now() -> Result<u64, ServiceErrorKind> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .map_err(|_| ServiceErrorKind::Foundation("System clock is before the Unix epoch.".into()))
}

fn check_policy(name: &str, variables: &HashMap<String, Value>) -> Result<(), ServiceErrorKind> {
    static CONSTRAINTS: OnceLock<Result<Vec<ConstraintDecl>, String>> = OnceLock::new();
    let constraints = CONSTRAINTS
        .get_or_init(|| {
            let document = px_compiler::parse(POLICY).map_err(|error| error.to_string())?;
            Ok(document
                .statements
                .into_iter()
                .filter_map(|statement| match statement {
                    Statement::Constraint(constraint) => Some(constraint),
                    _ => None,
                })
                .collect())
        })
        .as_ref()
        .map_err(|error| ServiceErrorKind::Foundation(format!("V2 PX parse failed: {error}")))?;
    let constraint = constraints
        .iter()
        .find(|constraint| constraint.name.name == name)
        .ok_or_else(|| ServiceErrorKind::Foundation(format!("Missing v2 PX constraint: {name}")))?;
    let decision = evaluate_px_constraint("v2 remediation", constraint, variables)?;
    if !decision.accepted {
        return Err(invalid(&decision.reason));
    }
    Ok(())
}

impl ServiceFoundation {
    #[tracing::instrument(skip_all)]
    pub async fn handle_v2_request(
        &self,
        frame: &str,
        expected_token: &str,
    ) -> LocalServiceResponse {
        if frame.len() > MAX_FRAME_BYTES {
            return response(
                None,
                false,
                None,
                Some(("invalid_request", "V2 frame limit exceeded.".into())),
            );
        }
        let request: LocalRequest = match serde_json::from_str(frame) {
            Ok(request) => request,
            Err(_) => {
                return response(
                    None,
                    false,
                    None,
                    Some((
                        "invalid_request",
                        "Invalid closed v2 request envelope.".into(),
                    )),
                );
            }
        };
        if !constant_time_equal(&request.authorization, expected_token)
            || normalize_profile_id(&request.profile_id) != self.profile_id
        {
            return response(
                Some(request.id),
                false,
                None,
                Some(("unauthorized", "V2 profile authentication failed.".into())),
            );
        }
        if request.schema_version != REQUEST_VERSION {
            return response(
                Some(request.id),
                false,
                None,
                Some((
                    "unsupported_version",
                    "Unsupported local service version; no automatic conversion.".into(),
                )),
            );
        }
        static SCHEMA: OnceLock<JSONSchema> = OnceLock::new();
        let schema = SCHEMA.get_or_init(|| {
            let source: Value = serde_json::from_str(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../../contracts/v2/local-service-request.schema.json"
            )))
            .expect("embedded v2 request schema parses");
            JSONSchema::options()
                .with_draft(Draft::Draft7)
                .compile(&source)
                .expect("embedded v2 request schema compiles")
        });
        if !schema.is_valid(&json!(request)) {
            return response(
                Some(request.id),
                false,
                None,
                Some((
                    "invalid_request",
                    "Invalid closed v2 request contract.".into(),
                )),
            );
        }
        let command: Command = match serde_json::from_value(
            json!({"method": request.method, "params": request.params}),
        ) {
            Ok(command) => command,
            Err(_) => {
                return response(
                    Some(request.id),
                    false,
                    None,
                    Some((
                        "invalid_request",
                        "Invalid closed v2 command parameters.".into(),
                    )),
                );
            }
        };
        let result = match command {
            Command::Authorize(params) => self
                .authorize_remediation_v2(params)
                .await
                .map(|result| json!(result)),
            Command::Verify(params) => self
                .verify_remediation_v2(params)
                .await
                .map(|()| json!({"verified": true})),
            Command::Revoke(params) => self
                .revoke_remediation_v2(params)
                .await
                .map(|()| json!({"revoked": true})),
            Command::Execute(params) => {
                self.execute_remediation_v2(params)
                    .await
                    .and_then(|result| {
                        if result.decision == "rejected" || result.decision == "failed" {
                            return Err(invalid(&result.reason));
                        }
                        Ok(json!(result))
                    })
            }
        };
        match result {
            Ok(value) => response(Some(request.id), true, Some(value), None),
            Err(error) => {
                tracing::warn!("V2 profile command rejected");
                let code = match &error {
                    ServiceErrorKind::InvalidRequest(_) => "v2_rejected",
                    _ => "v2_foundation_failed",
                };
                response(
                    Some(request.id),
                    false,
                    None,
                    Some((code, error.to_string())),
                )
            }
        }
    }

    fn v2_authority_key(&self, operation_id: &str) -> String {
        format!("pedantic:v2-remediation:{}:{operation_id}", self.profile_id)
    }

    async fn durable_record(&self, key: &str) -> Result<Option<Value>, ServiceErrorKind> {
        let stored =
            self.storage.get(key).await.map_err(|_| {
                ServiceErrorKind::Foundation("Profile persistence read failed.".into())
            })?;
        stored
            .map(|node| {
                let data = node
                    .payload
                    .get("data")
                    .filter(|data| data.is_object())
                    .ok_or_else(|| {
                        ServiceErrorKind::Foundation(
                            "Persisted profile record is malformed.".into(),
                        )
                    })?;
                Ok(data.clone())
            })
            .transpose()
    }

    async fn require_durable_record(&self, key: &str) -> Result<Value, ServiceErrorKind> {
        self.durable_record(key)
            .await?
            .ok_or_else(|| invalid("Required durable profile record is missing."))
    }

    pub(super) async fn ensure_persisted(&self, key: &str) -> Result<(), ServiceErrorKind> {
        // CrdtStore::get may persist a computed quality score. Read the durable
        // value first so that a cache read cannot conceal an unconfirmed write.
        let persisted = self.require_durable_record(key).await?;
        let cached = self._store.get(key).ok_or_else(|| {
            ServiceErrorKind::Foundation("Expected profile projection is missing.".into())
        })?;
        if persisted != cached.data {
            return Err(ServiceErrorKind::Foundation(
                "Profile write was not durably confirmed; reconcile before retrying.".into(),
            ));
        }
        Ok(())
    }

    async fn persist_v2_record(&self, key: &str, value: Value) -> Result<(), ServiceErrorKind> {
        self._store.put(key, SERVICE_ACTOR, value);
        self.ensure_persisted(key).await
    }

    pub(super) async fn v2_operation_exists(
        &self,
        operation_id: &str,
    ) -> Result<bool, ServiceErrorKind> {
        Ok(self
            .durable_record(&self.v2_authority_key(operation_id))
            .await?
            .is_some())
    }

    pub(super) async fn check_v2_execution(
        &self,
        request: &RemediationExecutionRequest,
        authorization: &Value,
    ) -> Result<(), ServiceErrorKind> {
        self.verify_remediation_v2_locked(&VerificationRequest {
            authorization_id: request.authorization_id.clone(),
            authorization: authorization.clone(),
            input_digest: format!("sha256:{:x}", Sha256::digest(request.document.as_bytes())),
            idempotency_key: request.idempotency_key.clone(),
        })
        .await?;
        let approved = self
            .approved_v2_remediation(&request.authorization_id)
            .await?;
        let remediation_key = self.remediation_request_key(&approved.request.request_id);
        let remediation = self.require_durable_record(&remediation_key).await?;
        let observation_id = required_record_string(
            &remediation,
            "observationId",
            "Compliance observation binding is missing.",
        )?;
        for key in [
            self.effect_authorization_key(&request.authorization_id),
            self.remediation_approval_key(&request.authorization_id),
            remediation_key,
            self.configuration_key(&approved.revision_id),
            self.compliance_observation_key(&observation_id),
            self.compliance_current_key(&approved.revision_id),
        ] {
            self.ensure_persisted(&key).await?;
        }
        Ok(())
    }

    async fn approved_v2_remediation(
        &self,
        approval_id: &str,
    ) -> Result<ApprovedRemediation, ServiceErrorKind> {
        let approval = self
            .require_durable_record(&self.remediation_approval_key(approval_id))
            .await?;
        let request_id = required_record_string(
            &approval,
            "requestId",
            "Approval request binding is missing.",
        )?;
        let actor_id =
            required_record_string(&approval, "actorId", "Approval actor binding is missing.")?;
        let remediation = self
            .require_durable_record(&self.remediation_request_key(&request_id))
            .await?;
        let revision_id =
            required_record_string(&remediation, "revisionId", "Revision binding is missing.")?;
        let revision = self
            .require_durable_record(&self.configuration_key(&revision_id))
            .await?;
        let source_digest =
            required_record_string(&revision, "sourceDigest", "Source binding is missing.")?;
        let idempotency_key = required_record_string(
            &remediation,
            "idempotencyKey",
            "Idempotency binding is missing.",
        )?;
        let request = RemediationApprovalRequest {
            approval_id: approval_id.into(),
            request_id,
            actor_id,
            approved: true,
            authorize: true,
        };
        let decision = self.evaluate_effect_authorization_policy(
            &request,
            &approval,
            &remediation,
            &revision,
            &source_digest,
            &idempotency_key,
        )?;
        if !decision.accepted {
            return Err(invalid(&decision.reason));
        }
        let plan = json!({
            "schemaVersion": contract::PLAN_VERSION,
            "planId": request.request_id, "planRevision": 1,
            "operationId": request.request_id, "profileId": self.profile_id,
            "targetId": self.profile_id, "executionMode": "agentless",
            "resolvedSettings": {
                "configurationSource": { "value": source_digest, "source": "plan", "sourceRevision": revision_id }
            },
            "steps": [{
                "stepId": STEP, "stage": "execution", "capability": CAPABILITY,
                "dependsOn": [], "retryClass": "requires-fresh-authorization",
                "inputDigest": source_digest, "secretReferences": []
            }]
        });
        resolved_plan_digest(&plan).map_err(contract_error)?;
        check_policy(
            "v2_remediation_is_bounded",
            &HashMap::from([
                ("profile".into(), json!({"profile_id": self.profile_id})),
                (
                    "plan".into(),
                    json!({"profile_id": self.profile_id, "target_id": self.profile_id, "mode": "agentless"}),
                ),
                (
                    "effect".into(),
                    json!({"executor_id": SERVICE_ACTOR, "capability": CAPABILITY,
                "risk_class": "high", "reboot_permitted": false, "retry_class": "requires-fresh-authorization"}),
                ),
            ]),
        )?;
        Ok(ApprovedRemediation {
            request,
            revision_id,
            source_digest,
            idempotency_key,
            plan,
        })
    }

    async fn read_v2_authority(
        &self,
        operation_id: &str,
    ) -> Result<Option<AuthorityRecord>, ServiceErrorKind> {
        self.durable_record(&self.v2_authority_key(operation_id))
            .await?
            .map(|record| {
                let state: AuthorityRecord = serde_json::from_value(record).map_err(|_| {
                    ServiceErrorKind::Foundation("Persisted v2 authority is malformed.".into())
                })?;
                if state.schema_version != STATE_VERSION
                    || state.coordinator.authority.operation_id != operation_id
                {
                    return Err(ServiceErrorKind::Foundation(
                        "Persisted v2 authority has incompatible identity or version.".into(),
                    ));
                }
                Ok(state)
            })
            .transpose()
    }

    #[tracing::instrument(skip_all)]
    pub async fn authorize_remediation_v2(
        &self,
        request: AuthorizationRequest,
    ) -> Result<AuthorizationResult, ServiceErrorKind> {
        let _guard = self.revision_lock.lock().await;
        let approved = self.approved_v2_remediation(&request.approval_id).await?;
        let authorization_key = self.effect_authorization_key(&request.approval_id);
        if let Some(existing) = self.durable_record(&authorization_key).await? {
            if existing["authorization"]["schemaVersion"] != contract::AUTHORIZATION_VERSION {
                return Err(invalid(
                    "Authorization ID is already reserved; no v1/v2 conversion is allowed.",
                ));
            }
            let state = self
                .verify_remediation_v2_locked(&VerificationRequest {
                    authorization_id: request.approval_id,
                    authorization: existing["authorization"].clone(),
                    input_digest: approved.source_digest,
                    idempotency_key: approved.idempotency_key,
                })
                .await?;
            return Ok(AuthorizationResult {
                plan: state.plan,
                authorization: state.authorization,
            });
        }
        if self
            .durable_record(&self.remediation_execution_idempotency_key(&approved.idempotency_key))
            .await?
            .is_some()
        {
            return Err(invalid(
                "This remediation has an execution claim; reconcile before issuing another grant.",
            ));
        }
        let now = v2_now()?;
        let authority_key = self.v2_authority_key(&approved.request.request_id);
        let previous = self.read_v2_authority(&approved.request.request_id).await?;
        let mut coordinator = if let Some(previous) = previous {
            if canonical_bytes(&previous.plan).map_err(contract_error)?
                != canonical_bytes(&approved.plan).map_err(contract_error)?
            {
                return Err(invalid(
                    "The accepted immutable plan changed; create a fresh remediation request.",
                ));
            }
            previous.coordinator
        } else {
            // Legacy records have no operation-mode index. Check durable history once
            // before creating the first v2 authority for an existing operation.
            let prefix = format!("pedantic:effect-authorization:{}:", self.profile_id);
            let records = self.storage.list().await.map_err(|_| {
                ServiceErrorKind::Foundation("Profile authorization history read failed.".into())
            })?;
            if records.iter().any(|record| {
                record.id.starts_with(&prefix)
                    && record.payload["data"]["requestId"] == approved.request.request_id
            }) {
                return Err(invalid(
                    "An authorization already owns this operation; no implicit v1/v2 migration is allowed.",
                ));
            }
            DurableCoordinator::new(
                PlanAuthority {
                    plan_id: approved.request.request_id.clone(),
                    operation_id: approved.request.request_id.clone(),
                    target_id: self.profile_id.clone(),
                    agent_id: SERVICE_ACTOR.into(),
                    expires_at: now
                        .checked_add(EFFECT_AUTHORIZATION_LIFETIME.as_secs())
                        .filter(|value| *value <= 9_007_199_254_740_991)
                        .ok_or_else(|| invalid("V2 authority clock exceeds its contract range."))?,
                    revoked_at: 0,
                    ownership_manifest: BTreeSet::from([approved.revision_id.clone()]),
                },
                false,
            )
        };
        let fencing_token = coordinator
            .highest_fencing_tokens
            .get(STEP)
            .copied()
            .unwrap_or(0)
            .checked_add(1)
            .filter(|value| *value <= 9_007_199_254_740_991)
            .ok_or_else(|| invalid("V2 fencing counter exhausted."))?;
        let lease = EffectLease {
            lease_id: request.approval_id.clone(),
            plan_id: approved.request.request_id.clone(),
            operation_id: approved.request.request_id.clone(),
            step_id: STEP.into(),
            attempt_id: request.approval_id.clone(),
            target_id: self.profile_id.clone(),
            agent_id: SERVICE_ACTOR.into(),
            fencing_token,
            expires_at: coordinator.authority.expires_at,
        };
        coordinator
            .offer(lease.clone(), now)
            .map_err(|error| invalid(&format!("V2 coordinator rejected lease: {error}")))?;
        let authorization = sign_authorization(json!({
            "authorizationId": request.approval_id, "issuerId": "px", "actorId": approved.request.actor_id,
            "planId": approved.request.request_id, "planRevision": 1,
            "planDigest": resolved_plan_digest(&approved.plan).map_err(contract_error)?,
            "operationId": approved.request.request_id, "profileId": self.profile_id, "targetId": self.profile_id,
            "stepId": STEP, "attemptId": lease.attempt_id, "capability": CAPABILITY,
            "inputDigest": approved.source_digest, "execution": { "mode": "agentless", "executorId": SERVICE_ACTOR },
            "idempotencyKey": approved.idempotency_key, "fencingToken": fencing_token,
            "issuedAt": now, "expiresAt": lease.expires_at, "retryClass": "requires-fresh-authorization",
            "riskClass": "high", "rebootPermitted": false
        }), &authorization_signing_key_id(&self.authorization_signing_key), &self.authorization_signing_key).map_err(contract_error)?;
        let state = AuthorityRecord {
            schema_version: STATE_VERSION.into(),
            authorization_id: request.approval_id.clone(),
            plan: approved.plan.clone(),
            authorization: authorization.clone(),
            coordinator,
            lease,
        };
        let mut metadata = json!({
            "profileId": self.profile_id, "authorizationId": request.approval_id,
            "requestId": approved.request.request_id, "actorId": approved.request.actor_id,
            "revisionId": approved.revision_id, "sourceDigest": approved.source_digest,
            "idempotencyKey": approved.idempotency_key, "capability": CAPABILITY,
            "decision": "accepted", "authorization": authorization, "evidenceRecorded": false
        });
        self.persist_v2_record(&authority_key, json!(state)).await?;
        self.persist_v2_record(&authorization_key, metadata.clone())
            .await?;
        self.record_v2_evidence(&authority_key, "issued").await?;
        metadata["evidenceRecorded"] = true.into();
        self.persist_v2_record(&authorization_key, metadata).await?;
        Ok(AuthorizationResult {
            plan: state.plan,
            authorization: state.authorization,
        })
    }

    async fn record_v2_evidence(&self, key: &str, event: &str) -> Result<(), ServiceErrorKind> {
        let entry = self.timeline.build_entry(
            key,
            SERVICE_ACTOR,
            ChronosAction::Create,
            &json!({"profileId": self.profile_id, "event": event, "contractVersion": 2}),
            Vec::new(),
            Some("Profile-owned v2 remediation authority transition.".into()),
        );
        self.record_evidence_summary(entry)?;
        self.ensure_persisted(&self.evidence_counter_key()).await?;
        self.ensure_persisted(&self.evidence_entry_key(self.evidence_count() - 1))
            .await
    }

    async fn verify_remediation_v2_locked(
        &self,
        request: &VerificationRequest,
    ) -> Result<AuthorityRecord, ServiceErrorKind> {
        let approved = self
            .approved_v2_remediation(&request.authorization_id)
            .await?;
        let recorded = self
            .require_durable_record(&self.effect_authorization_key(&request.authorization_id))
            .await?;
        if recorded["evidenceRecorded"] != true
            || recorded["authorization"]["schemaVersion"] != contract::AUTHORIZATION_VERSION
        {
            return Err(invalid(
                "V2 authorization is not durably complete; reconcile before retrying.",
            ));
        }
        let state = self
            .read_v2_authority(&approved.request.request_id)
            .await?
            .ok_or_else(|| invalid("Current v2 operation authority is missing."))?;
        if state.authorization_id != request.authorization_id
            || canonical_bytes(&state.plan).map_err(contract_error)?
                != canonical_bytes(&approved.plan).map_err(contract_error)?
            || recorded["authorization"] != state.authorization
        {
            return Err(invalid(
                "V2 authorization or immutable plan is no longer current.",
            ));
        }
        let now = v2_now()?;
        let lease = &state.lease;
        check_policy(
            "v2_remediation_authority_is_current",
            &HashMap::from([
                (
                    "authority".into(),
                    json!({
                        "state": state.coordinator.state, "authorization_id": state.authorization_id,
                        "fencing_token": state.coordinator.highest_fencing_tokens.get(STEP),
                        "expires_at": state.coordinator.authority.expires_at,
                        "revoked_at": state.coordinator.authority.revoked_at,
                    }),
                ),
                (
                    "effect".into(),
                    json!({"authorization_id": request.authorization_id,
                "fencing_token": lease.fencing_token, "expires_at": lease.expires_at}),
                ),
                ("clock".into(), json!({"now": now})),
            ]),
        )?;
        state
            .coordinator
            .validate_agent_execution(lease, now, &approved.revision_id)
            .map_err(|error| invalid(&format!("V2 coordinator rejected execution: {error}")))?;
        let context = EffectContext {
            authorization_id: request.authorization_id.clone(),
            issuer_id: "px".into(),
            actor_id: approved.request.actor_id,
            operation_id: approved.request.request_id,
            profile_id: self.profile_id.clone(),
            target_id: self.profile_id.clone(),
            step_id: STEP.into(),
            attempt_id: lease.attempt_id.clone(),
            input_digest: request.input_digest.clone(),
            idempotency_key: approved.idempotency_key.clone(),
            execution: ExecutionIdentity::Agentless {
                executor_id: SERVICE_ACTOR.into(),
            },
            fencing_token: lease.fencing_token,
            risk_class: RiskClass::High,
            requires_reboot: false,
            now,
            revoked: state.coordinator.authority.revoked_at != 0,
        };
        if request.idempotency_key != approved.idempotency_key {
            return Err(invalid(
                "V2 execution idempotency does not match its approved request.",
            ));
        }
        verify_effect_authorization(
            &state.plan,
            &request.authorization,
            &context,
            &authorization_signing_key_id(&self.authorization_signing_key),
            &self.authorization_signing_key.verifying_key(),
        )
        .map_err(contract_error)?;
        Ok(state)
    }

    #[tracing::instrument(skip_all)]
    pub async fn verify_remediation_v2(
        &self,
        request: VerificationRequest,
    ) -> Result<(), ServiceErrorKind> {
        let _guard = self.revision_lock.lock().await;
        self.verify_remediation_v2_locked(&request).await?;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    pub async fn revoke_remediation_v2(
        &self,
        request: RevocationRequest,
    ) -> Result<(), ServiceErrorKind> {
        let _guard = self.revision_lock.lock().await;
        let recorded = self
            .require_durable_record(&self.effect_authorization_key(&request.authorization_id))
            .await?;
        let operation_id =
            required_record_string(&recorded, "requestId", "V2 operation binding is missing.")?;
        let mut state = self
            .read_v2_authority(&operation_id)
            .await?
            .ok_or_else(|| invalid("V2 authority is missing."))?;
        if state.authorization_id != request.authorization_id {
            return Err(invalid(
                "Only the current authorization can revoke its operation authority.",
            ));
        }
        state.coordinator.cancel();
        state.coordinator.authority.revoked_at = v2_now()?;
        let key = self.v2_authority_key(&operation_id);
        self.persist_v2_record(&key, json!(state)).await?;
        self.record_v2_evidence(&key, "revoked").await
    }

    #[tracing::instrument(skip_all)]
    pub async fn execute_remediation_v2(
        &self,
        request: ExecutionRequest,
    ) -> Result<RemediationExecution, ServiceErrorKind> {
        if request.execution_id.is_empty() || request.execution_id.chars().count() > 256 {
            return Err(invalid("V2 execution ID must contain 1-256 characters."));
        }
        self.execute_remediation_with(
            RemediationExecutionRequest {
                execution_id: request.execution_id,
                authorization_id: request.authorization_id,
                idempotency_key: request.idempotency_key,
                document: request.document,
            },
            Some(request.authorization),
            |document, options| async move {
                run_dsc(DscCommand::ConfigSet, DscInput::Stdin(document), &options).await
            },
        )
        .await
    }
}

impl LocalServiceClient {
    pub async fn call_v2(
        &self,
        id: impl Into<String>,
        command: Command,
    ) -> Result<LocalServiceResponse, ServiceErrorKind> {
        #[cfg(windows)]
        {
            use tokio::net::windows::named_pipe::ClientOptions;
            let command = serde_json::to_value(command)
                .map_err(|_| invalid("Unable to encode v2 command."))?;
            let request = json!({
                "schemaVersion": REQUEST_VERSION, "id": id.into(), "method": command["method"],
                "params": command["params"], "profileId": self.profile_id,
                "authorization": self.authorization_token,
            });
            let connection = ClientOptions::new()
                .open(&self.pipe_name)
                .map_err(ServiceErrorKind::Io)?;
            exchange(connection, request).await
        }
        #[cfg(not(windows))]
        {
            let _ = (id, command);
            Err(invalid(
                "The local service client requires Windows named pipes.",
            ))
        }
    }
}

#[cfg(test)]
mod tests;
