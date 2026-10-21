use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};

const DOCUMENT: &str = "synthetic configuration; must never reach a real DSC process";
const TOKEN: &str = "0123456789abcdef0123456789abcdef";

fn digest() -> String {
    format!("sha256:{:x}", Sha256::digest(DOCUMENT.as_bytes()))
}

async fn approve(foundation: &ServiceFoundation, id: &str) {
    let result = foundation
        .approve_remediation(RemediationApprovalRequest {
            approval_id: id.into(),
            request_id: "operation".into(),
            actor_id: "reviewer@example.test".into(),
            approved: true,
            authorize: false,
        })
        .await
        .unwrap();
    assert_eq!(result.decision, "accepted");
}

async fn seed(foundation: &ServiceFoundation) {
    foundation._store.put(
        foundation.configuration_key("revision"),
        SERVICE_ACTOR,
        json!({
            "profileId": foundation.profile_id, "revisionId": "revision", "sourceDigest": digest(),
            "admissionState": "accepted", "validationState": "validated",
        }),
    );
    foundation
        .record_compliance_observation(
            &ComplianceObservation {
                observation_id: "observation".into(),
                request_id: "compliance".into(),
                revision_id: "revision".into(),
                decision: "observed".into(),
                constraint_id: "dsc_config_test".into(),
                resource_count: 1,
                compliant_resource_count: 0,
                drifted_resource_count: 1,
                reason: "synthetic fixture".into(),
            },
            &digest(),
        )
        .unwrap();
    let result = foundation
        .request_remediation(RemediationRequest {
            request_id: "operation".into(),
            revision_id: "revision".into(),
            observation_id: "observation".into(),
            actor_id: "operator@example.test".into(),
            idempotency_key: "effect-once".into(),
        })
        .await
        .unwrap();
    assert_eq!(result.decision, "accepted");
    approve(foundation, "approval").await;
}

async fn issue(foundation: &ServiceFoundation, id: &str) -> AuthorizationResult {
    foundation
        .authorize_remediation_v2(AuthorizationRequest {
            approval_id: id.into(),
        })
        .await
        .unwrap()
}

fn verification(authorization: Value) -> VerificationRequest {
    VerificationRequest {
        authorization_id: "approval".into(),
        authorization,
        input_digest: digest(),
        idempotency_key: "effect-once".into(),
    }
}

fn execution() -> RemediationExecutionRequest {
    RemediationExecutionRequest {
        execution_id: "execution".into(),
        authorization_id: "approval".into(),
        idempotency_key: "effect-once".into(),
        document: DOCUMENT.into(),
    }
}

fn output() -> DscOutput {
    #[cfg(unix)]
    use std::os::unix::process::ExitStatusExt;
    #[cfg(windows)]
    use std::os::windows::process::ExitStatusExt;
    DscOutput {
        status: std::process::ExitStatus::from_raw(0),
        stdout: String::new(),
        stderr: String::new(),
        json: Some(json!({"results": []})),
    }
}

#[tokio::test]
async fn service_issues_and_reopens_the_same_plan_grant_and_coordinator() {
    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    seed(&foundation).await;
    let issued = issue(&foundation, "approval").await;
    assert_eq!(
        issued.authorization["grant"]["actorId"],
        "reviewer@example.test"
    );
    assert_eq!(issued.authorization["grant"]["fencingToken"], 1);
    assert_eq!(
        issued.plan["resolvedSettings"]["configurationSource"]["sourceRevision"],
        "revision"
    );
    assert!(!issued.plan.to_string().contains(DOCUMENT));
    let evidence = foundation.evidence_count();
    let replay = issue(&foundation, "approval").await;
    assert_eq!(issued.authorization, replay.authorization);
    assert_eq!(foundation.evidence_count(), evidence);
    drop(foundation);

    let reopened = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    reopened
        .verify_remediation_v2(verification(issued.authorization.clone()))
        .await
        .unwrap();
    let replay = issue(&reopened, "approval").await;
    assert_eq!(issued.plan, replay.plan);
    assert_eq!(issued.authorization, replay.authorization);
    assert_eq!(reopened.evidence_count(), evidence);
}

#[tokio::test]
async fn fresh_approval_supersedes_the_lease_and_revocation_survives_restart() {
    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    seed(&foundation).await;
    let first = issue(&foundation, "approval").await;
    approve(&foundation, "approval-two").await;
    let second = issue(&foundation, "approval-two").await;
    assert_eq!(second.authorization["grant"]["fencingToken"], 2);
    assert!(
        foundation
            .verify_remediation_v2(verification(first.authorization.clone()))
            .await
            .is_err()
    );
    let calls = AtomicUsize::new(0);
    assert!(
        foundation
            .execute_remediation_with(execution(), Some(first.authorization), |_, _| {
                calls.fetch_add(1, Ordering::SeqCst);
                std::future::ready(Ok(output()))
            })
            .await
            .is_err()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert!(
        foundation
            .revoke_remediation_v2(RevocationRequest {
                authorization_id: "approval".into()
            })
            .await
            .is_err()
    );
    foundation
        .revoke_remediation_v2(RevocationRequest {
            authorization_id: "approval-two".into(),
        })
        .await
        .unwrap();
    drop(foundation);
    let reopened = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    let mut check = verification(second.authorization);
    check.authorization_id = "approval-two".into();
    assert!(reopened.verify_remediation_v2(check).await.is_err());
    assert!(
        reopened
            .authorize_remediation_v2(AuthorizationRequest {
                approval_id: "approval-two".into()
            })
            .await
            .is_err()
    );
    approve(&reopened, "approval-three").await;
    assert!(
        reopened
            .authorize_remediation_v2(AuthorizationRequest {
                approval_id: "approval-three".into()
            })
            .await
            .is_err()
    );
}

#[tokio::test]
async fn invalid_context_and_signature_never_reach_the_shared_provider() {
    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    seed(&foundation).await;
    let issued = issue(&foundation, "approval").await;
    for (path, value) in [
        ("/grant/actorId", json!("forged")),
        ("/grant/profileId", json!("other")),
        ("/grant/planRevision", json!(2)),
        ("/grant/fencingToken", json!(2)),
        ("/grant/rebootPermitted", json!(true)),
        ("/grant/execution/executorId", json!("remote")),
        ("/signature/value", json!(URL_SAFE_NO_PAD.encode([0u8; 64]))),
    ] {
        let mut grant = issued.authorization.clone();
        *grant.pointer_mut(path).unwrap() = value;
        let calls = AtomicUsize::new(0);
        assert!(
            foundation
                .execute_remediation_with(execution(), Some(grant), |_, _| {
                    calls.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Ok(output()))
                })
                .await
                .is_err(),
            "{path}"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }
    let mut wrong_document = execution();
    wrong_document.document = "different document".into();
    let mut wrong_idempotency = execution();
    wrong_idempotency.idempotency_key = "different key".into();
    for request in [wrong_document, wrong_idempotency] {
        let calls = AtomicUsize::new(0);
        assert!(
            foundation
                .execute_remediation_with(request, Some(issued.authorization.clone()), |_, _| {
                    calls.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Ok(output()))
                })
                .await
                .is_err()
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }
    assert!(
        foundation
            ._store
            .get(foundation.remediation_execution_idempotency_key("effect-once"))
            .is_none()
    );
}

#[tokio::test]
async fn changed_source_expired_authority_and_missing_evidence_fail_closed() {
    for mutation in [
        "source",
        "expiry",
        "evidence",
        "fence",
        "lease-expiry",
        "cancelled",
        "version",
    ] {
        let directory = tempfile::tempdir().unwrap();
        let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
        seed(&foundation).await;
        let issued = issue(&foundation, "approval").await;
        let key = match mutation {
            "source" => foundation.configuration_key("revision"),
            "evidence" => foundation.effect_authorization_key("approval"),
            _ => foundation.v2_authority_key("operation"),
        };
        let mut record = foundation.require_durable_record(&key).await.unwrap();
        match mutation {
            "source" => record["sourceDigest"] = format!("sha256:{}", "1".repeat(64)).into(),
            "expiry" => record["coordinator"]["authority"]["expiresAt"] = 1.into(),
            "fence" => record["coordinator"]["highestFencingTokens"][STEP] = 2.into(),
            "lease-expiry" => record["lease"]["expiresAt"] = 1.into(),
            "cancelled" => record["coordinator"]["state"] = "cancelled".into(),
            "version" => record["schemaVersion"] = "unknown".into(),
            _ => record["evidenceRecorded"] = false.into(),
        }
        foundation.persist_v2_record(&key, record).await.unwrap();
        let calls = AtomicUsize::new(0);
        assert!(
            foundation
                .execute_remediation_with(execution(), Some(issued.authorization), |_, _| {
                    calls.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Ok(output()))
                })
                .await
                .is_err(),
            "{mutation}"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }
}

#[cfg(windows)]
#[tokio::test]
async fn typed_v2_client_uses_the_real_profile_pipe_without_invoking_dsc() {
    let directory = tempfile::tempdir().unwrap();
    let profile = format!("v2-test-{}", std::process::id());
    let foundation =
        Arc::new(ServiceFoundation::open_at(&profile, directory.path(), "test").unwrap());
    seed(&foundation).await;
    let client = LocalServiceClient::for_profile(&profile, TOKEN).unwrap();
    let mut security = PipeSecurity::for_current_user().unwrap();
    let pipe = create_server_pipe(&client.pipe_name, true, &mut security).unwrap();
    drop(security);
    let server = async {
        pipe.connect().await?;
        serve_connection(pipe, &profile, TOKEN, "test", Arc::clone(&foundation)).await
    };
    let caller = client.call_v2(
        "typed-v2",
        Command::Authorize(AuthorizationRequest {
            approval_id: "approval".into(),
        }),
    );
    let (server_result, client_result) = tokio::time::timeout(Duration::from_secs(15), async {
        tokio::join!(server, caller)
    })
    .await
    .expect("bounded named-pipe exchange");
    server_result.unwrap();
    let reply = client_result.unwrap();
    assert!(reply.ok, "{:?}", reply.error);
    assert_eq!(
        reply.result.unwrap()["authorization"]["schemaVersion"],
        contract::AUTHORIZATION_VERSION
    );
    assert!(
        foundation
            .durable_record(&foundation.remediation_execution_idempotency_key("effect-once"))
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn shared_provider_runs_once_and_interrupted_claim_is_not_replayed() {
    for interrupted in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
        seed(&foundation).await;
        let issued = issue(&foundation, "approval").await;
        if interrupted {
            foundation
                .record_remediation_execution_claim(
                    &foundation.remediation_execution_idempotency_key("effect-once"),
                    "approval",
                    &digest(),
                    "execution",
                )
                .unwrap();
        }
        let calls = AtomicUsize::new(0);
        let result = foundation
            .execute_remediation_with(
                execution(),
                Some(issued.authorization.clone()),
                |document, options| {
                    assert_eq!(document, DOCUMENT);
                    assert_eq!(options.timeout, Some(Duration::from_secs(30)));
                    calls.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Ok(output()))
                },
            )
            .await;
        if interrupted {
            assert!(result.unwrap_err().to_string().contains("reconcile"));
            assert_eq!(calls.load(Ordering::SeqCst), 0);
        } else {
            assert_eq!(result.unwrap().decision, "completed");
            let replay = foundation
                .execute_remediation_with(execution(), Some(issued.authorization), |_, _| {
                    calls.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Ok(output()))
                })
                .await
                .unwrap();
            assert_eq!(replay.decision, "completed");
            assert_eq!(calls.load(Ordering::SeqCst), 1);
        }
    }
}

#[tokio::test]
async fn px_denies_unapproved_or_unvalidated_inputs_before_issuing() {
    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    assert!(
        foundation
            .authorize_remediation_v2(AuthorizationRequest {
                approval_id: "absent".into()
            })
            .await
            .is_err()
    );
    seed(&foundation).await;
    let key = foundation.configuration_key("revision");
    let mut revision = foundation.require_durable_record(&key).await.unwrap();
    revision["validationState"] = "rejected".into();
    foundation.persist_v2_record(&key, revision).await.unwrap();
    assert!(
        foundation
            .authorize_remediation_v2(AuthorizationRequest {
                approval_id: "approval".into()
            })
            .await
            .is_err()
    );
    assert!(
        foundation
            .durable_record(&foundation.v2_authority_key("operation"))
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn v1_and_v2_cannot_silently_take_over_each_others_operation() {
    for first_v2 in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
        seed(&foundation).await;
        approve(&foundation, "other-approval").await;
        let legacy = |id: &str| RemediationApprovalRequest {
            approval_id: id.into(),
            request_id: "operation".into(),
            actor_id: "reviewer@example.test".into(),
            approved: true,
            authorize: true,
        };
        if first_v2 {
            issue(&foundation, "approval").await;
            assert!(
                foundation
                    .authorize_remediation(legacy("other-approval"))
                    .await
                    .is_err()
            );
            assert!(
                foundation
                    .execute_remediation_with(execution(), None, |_, _| {
                        std::future::ready(Err(DscError::NotFound))
                    })
                    .await
                    .is_err()
            );
        } else {
            foundation
                .authorize_remediation(legacy("approval"))
                .await
                .unwrap();
            assert!(
                foundation
                    .authorize_remediation_v2(AuthorizationRequest {
                        approval_id: "other-approval".into()
                    })
                    .await
                    .is_err()
            );
        }
    }
}

#[tokio::test]
async fn closed_v2_transport_authenticates_before_dispatch_and_never_downgrades() {
    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    seed(&foundation).await;
    let request = json!({
        "schemaVersion": REQUEST_VERSION, "id": "rpc", "method": "effect.authorize",
        "profileId": "default", "authorization": TOKEN, "params": {"approvalId": "approval"},
    });
    for (path, value) in [
        ("/authorization", json!("wrong token")),
        ("/profileId", json!("another-profile")),
        (
            "/schemaVersion",
            json!("pedantic.local-service-request.v99"),
        ),
        ("/method", json!("unsupported")),
        (
            "/params",
            json!({"approvalId": "approval", "actorId": "forged"}),
        ),
        ("/params", json!({"approvalId": ""})),
    ] {
        let mut frame = request.clone();
        *frame.pointer_mut(path).unwrap() = value;
        let reply = foundation
            .handle_v2_request(&frame.to_string(), TOKEN)
            .await;
        assert!(!reply.ok, "{path}");
        assert!(!serde_json::to_string(&reply).unwrap().contains(TOKEN));
        assert!(
            foundation
                .durable_record(&foundation.v2_authority_key("operation"))
                .await
                .unwrap()
                .is_none()
        );
    }
    let reply = foundation
        .handle_v2_request(&request.to_string(), TOKEN)
        .await;
    assert!(reply.ok, "{:?}", reply.error);
    let issued: AuthorizationResult = serde_json::from_value(reply.result.unwrap()).unwrap();
    let mut frame = request;
    frame["method"] = "effect.verify".into();
    frame["params"] = json!(verification(issued.authorization));
    assert!(
        foundation
            .handle_v2_request(&frame.to_string(), TOKEN)
            .await
            .ok
    );
    frame["method"] = "effect.revoke".into();
    frame["params"] = json!({"authorizationId": "approval"});
    assert!(
        foundation
            .handle_v2_request(&frame.to_string(), TOKEN)
            .await
            .ok
    );
}

#[tokio::test]
async fn unconfirmed_persistence_or_chronos_never_returns_a_grant() {
    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    seed(&foundation).await;
    let key = foundation.configuration_key("revision");
    assert!(foundation._store.get(&key).is_some());
    foundation.storage.delete(&key).await.unwrap();
    assert!(foundation.ensure_persisted(&key).await.is_err());
    assert!(
        foundation
            .authorize_remediation_v2(AuthorizationRequest {
                approval_id: "approval".into()
            })
            .await
            .is_err()
    );

    let directory = tempfile::tempdir().unwrap();
    let foundation = ServiceFoundation::open_at("default", directory.path(), "test").unwrap();
    seed(&foundation).await;
    foundation
        .timeline
        .set_level(pluresdb_chronos::ChronosLevel::Error);
    assert!(
        foundation
            .authorize_remediation_v2(AuthorizationRequest {
                approval_id: "approval".into()
            })
            .await
            .is_err()
    );
    let record = foundation
        .require_durable_record(&foundation.effect_authorization_key("approval"))
        .await
        .unwrap();
    assert_eq!(record["evidenceRecorded"], false);
    assert!(
        foundation
            .verify_remediation_v2(verification(record["authorization"].clone()))
            .await
            .is_err()
    );
}
