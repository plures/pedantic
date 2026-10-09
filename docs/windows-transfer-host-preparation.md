# Windows transfer-host preparation harness

`transfer.host-prepare/v1` performs only the prerequisites explicitly present
in its authorized input. PX supplies any remediation identifier; the provider
reports sanitized observations and never records command output or credentials.

## Real-machine verification

Run this on an isolated, domain-joined Windows host with a gMSA whose password
retrieval permission has just been granted to the host computer:

1. Submit an authorization for `transfer.host-prepare/v1` with the target
   hostname, gMSA account, and only the required OpenSSH, BITS, key, and
   directory flags. When keys are required, provide their local paths, never
   key contents; each path is verified as a file.
2. Verify the returned observation names the selected domain controller,
   reports `gmsa_ready` and `system_kerberos_refreshed`, and is `ready: true`.
   The adapter creates a one-shot task as `SYSTEM`; do not use WinRM
   credential delegation as proof of this path.
3. Revoke the computer's gMSA password-retrieval permission, repeat the
   request, and verify `ready: false` with
   `failureCategory: gmsa_authorization_denied`.
4. Grant the permission again and retry without rebooting. The second response
   must be ready, proving that the Local SYSTEM Kerberos cache was refreshed.
5. Confirm no task matching `PedanticTransferPreparation-*`, temporary script,
   result file, or credential remains after either invocation. Cancel an
   in-flight invocation and repeat this check.

For missing RSAT/ActiveDirectory tooling, the adapter reports
`ad_tooling_missing`; DC or AD Web Services discovery errors report
`domain_connectivity_failed`. Diagnostics are fixed identifiers, not raw
PowerShell output.
