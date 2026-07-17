use std::{collections::HashMap, sync::Mutex};

use uuid::Uuid;

use super::client::{
    parse_pairing_invitation, PairingInvitationParseError, PairingJoinAttemptSummary,
    PairingJoinEndpoint, ParsedPairingInvitation,
};

const JOIN_ATTEMPT_MAX_TTL_MS: u64 = 5 * 60 * 1000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingJoinRuntimeError {
    Invitation(PairingInvitationParseError),
    InvalidAttemptId,
    AttemptMissing,
    AttemptExpired,
    InvalidCandidate,
    Unavailable,
}

struct PairingJoinAttempt {
    invitation: ParsedPairingInvitation,
    expires_at_ms: u64,
}

#[derive(Default)]
pub struct PairingJoinRuntime {
    attempts: Mutex<HashMap<Uuid, PairingJoinAttempt>>,
}

impl PairingJoinRuntime {
    pub fn begin(
        &self,
        invitation: String,
        now_ms: u64,
    ) -> Result<PairingJoinAttemptSummary, PairingJoinRuntimeError> {
        let parsed = parse_pairing_invitation(invitation, now_ms)
            .map_err(PairingJoinRuntimeError::Invitation)?;
        let attempt_id = Uuid::now_v7();
        let summary = parsed.public_summary(attempt_id, now_ms);
        let expires_at_ms = parsed
            .expires_at_ms
            .min(now_ms.saturating_add(JOIN_ATTEMPT_MAX_TTL_MS));
        let mut attempts = self
            .attempts
            .lock()
            .map_err(|_| PairingJoinRuntimeError::Unavailable)?;
        // The desktop UI has one join dialog. Replacing its invitation must also
        // drop the previous secret instead of accumulating hidden attempts.
        attempts.clear();
        attempts.insert(
            attempt_id,
            PairingJoinAttempt {
                invitation: parsed,
                expires_at_ms,
            },
        );
        Ok(summary)
    }

    pub fn discard(&self, attempt_id: &str) -> Result<bool, PairingJoinRuntimeError> {
        let attempt_id = parse_attempt_id(attempt_id)?;
        let removed = self
            .attempts
            .lock()
            .map_err(|_| PairingJoinRuntimeError::Unavailable)?
            .remove(&attempt_id)
            .is_some();
        Ok(removed)
    }

    pub fn expire(&self, now_ms: u64) -> Result<usize, PairingJoinRuntimeError> {
        let mut attempts = self
            .attempts
            .lock()
            .map_err(|_| PairingJoinRuntimeError::Unavailable)?;
        let before = attempts.len();
        attempts.retain(|_, attempt| attempt.expires_at_ms > now_ms);
        Ok(before.saturating_sub(attempts.len()))
    }

    /// The client handshake takes ownership of the only secret-bearing model.
    /// Whether that future operation succeeds or fails, dropping the returned
    /// value clears the pairing secret and no half-finished attempt remains.
    #[allow(dead_code)]
    pub(crate) fn take_for_handshake(
        &self,
        attempt_id: &str,
        now_ms: u64,
    ) -> Result<ParsedPairingInvitation, PairingJoinRuntimeError> {
        let attempt_id = parse_attempt_id(attempt_id)?;
        let mut attempts = self
            .attempts
            .lock()
            .map_err(|_| PairingJoinRuntimeError::Unavailable)?;
        let expired = attempts
            .get(&attempt_id)
            .map(|attempt| attempt.expires_at_ms <= now_ms)
            .unwrap_or(false);
        if expired {
            attempts.remove(&attempt_id);
            return Err(PairingJoinRuntimeError::AttemptExpired);
        }
        attempts
            .remove(&attempt_id)
            .map(|attempt| attempt.invitation)
            .ok_or(PairingJoinRuntimeError::AttemptMissing)
    }

    pub(crate) fn endpoint_for_candidate(
        &self,
        attempt_id: &str,
        candidate_id: &str,
        now_ms: u64,
    ) -> Result<PairingJoinEndpoint, PairingJoinRuntimeError> {
        let attempt_id = parse_attempt_id(attempt_id)?;
        let mut attempts = self
            .attempts
            .lock()
            .map_err(|_| PairingJoinRuntimeError::Unavailable)?;
        let expired = attempts
            .get(&attempt_id)
            .map(|attempt| attempt.expires_at_ms <= now_ms)
            .unwrap_or(false);
        if expired {
            attempts.remove(&attempt_id);
            return Err(PairingJoinRuntimeError::AttemptExpired);
        }
        let attempt = attempts
            .get(&attempt_id)
            .ok_or(PairingJoinRuntimeError::AttemptMissing)?;
        let index = candidate_id
            .strip_prefix("address-")
            .and_then(|value| value.parse::<usize>().ok())
            .and_then(|value| value.checked_sub(1))
            .ok_or(PairingJoinRuntimeError::InvalidCandidate)?;
        attempt
            .invitation
            .endpoints
            .get(index)
            .cloned()
            .ok_or(PairingJoinRuntimeError::InvalidCandidate)
    }

    #[cfg(test)]
    fn active_count(&self) -> usize {
        self.attempts
            .lock()
            .map(|attempts| attempts.len())
            .unwrap_or_default()
    }
}

fn parse_attempt_id(value: &str) -> Result<Uuid, PairingJoinRuntimeError> {
    Uuid::parse_str(value).map_err(|_| PairingJoinRuntimeError::InvalidAttemptId)
}

#[cfg(test)]
mod tests {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};

    use super::*;

    const NOW_MS: u64 = 1_700_000_000_000;

    fn invitation(expires_at_ms: u64) -> String {
        let payload = serde_json::json!({
            "app": "eggclip",
            "version": 2,
            "kind": "pairingInvitation",
            "invitationId": "018ff6f0-1111-7222-8333-123456789abc",
            "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
            "spaceKeyVersion": 1,
            "issuerDeviceName": "Windows B",
            "issuerDeviceId": "018ff6f0-0a3b-7815-a4db-3eb6e23d9338",
            "issuerIdentityPublicKey": "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo",
            "pairingSecret": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "expiresAtMs": expires_at_ms,
            "connectionHints": {
                "transport": "ws",
                "endpoints": [{ "host": "192.168.10.24", "port": 4567 }]
            }
        });
        format!(
            "eggclip://pair?p={}",
            URL_SAFE_NO_PAD.encode(payload.to_string())
        )
    }

    #[test]
    fn replaces_and_cancels_the_single_active_join_attempt() {
        let runtime = PairingJoinRuntime::default();
        let first = runtime
            .begin(invitation(NOW_MS + 300_000), NOW_MS)
            .expect("first attempt");
        let second = runtime
            .begin(invitation(NOW_MS + 300_000), NOW_MS)
            .expect("second attempt");
        assert_ne!(first.attempt_id, second.attempt_id);
        assert_eq!(runtime.active_count(), 1);
        assert!(!runtime
            .discard(&first.attempt_id)
            .expect("old attempt lookup"));
        assert!(runtime.discard(&second.attempt_id).expect("cancel"));
        assert_eq!(runtime.active_count(), 0);
    }

    #[test]
    fn expires_attempt_at_the_invitation_deadline() {
        let runtime = PairingJoinRuntime::default();
        runtime
            .begin(invitation(NOW_MS + 1_000), NOW_MS)
            .expect("attempt");
        assert_eq!(runtime.expire(NOW_MS + 999).expect("expiry sweep"), 0);
        assert_eq!(runtime.expire(NOW_MS + 1_000).expect("expiry sweep"), 1);
        assert_eq!(runtime.active_count(), 0);
    }

    #[test]
    fn limits_attempt_lifetime_and_removes_secret_before_handshake() {
        let runtime = PairingJoinRuntime::default();
        runtime
            .begin(invitation(NOW_MS + 3_600_000), NOW_MS)
            .expect("attempt");
        assert_eq!(
            runtime
                .expire(NOW_MS + JOIN_ATTEMPT_MAX_TTL_MS - 1)
                .unwrap(),
            0
        );
        assert_eq!(runtime.expire(NOW_MS + JOIN_ATTEMPT_MAX_TTL_MS).unwrap(), 1);
        assert_eq!(runtime.active_count(), 0);

        let summary = runtime
            .begin(invitation(NOW_MS + 300_000), NOW_MS)
            .expect("attempt");
        let parsed = runtime
            .take_for_handshake(&summary.attempt_id, NOW_MS)
            .expect("handshake should take attempt");
        assert_eq!(parsed.pairing_secret, [0u8; 32]);
        assert_eq!(runtime.active_count(), 0);
        drop(parsed);
    }

    #[test]
    fn reports_expired_missing_and_invalid_attempt_ids_without_secrets() {
        let runtime = PairingJoinRuntime::default();
        let summary = runtime
            .begin(invitation(NOW_MS + 1_000), NOW_MS)
            .expect("attempt");
        assert!(matches!(
            runtime.take_for_handshake(&summary.attempt_id, NOW_MS + 1_000),
            Err(PairingJoinRuntimeError::AttemptExpired)
        ));
        assert!(matches!(
            runtime.take_for_handshake(&summary.attempt_id, NOW_MS),
            Err(PairingJoinRuntimeError::AttemptMissing)
        ));
        assert!(matches!(
            runtime.discard("not-a-uuid"),
            Err(PairingJoinRuntimeError::InvalidAttemptId)
        ));
    }

    #[test]
    fn resolves_only_candidates_owned_by_the_active_attempt() {
        let runtime = PairingJoinRuntime::default();
        let summary = runtime
            .begin(invitation(NOW_MS + 300_000), NOW_MS)
            .expect("attempt");
        let endpoint = runtime
            .endpoint_for_candidate(&summary.attempt_id, "address-1", NOW_MS)
            .expect("candidate");
        assert_eq!(endpoint.host.to_string(), "192.168.10.24");
        assert_eq!(endpoint.port, 4567);
        assert!(matches!(
            runtime.endpoint_for_candidate(&summary.attempt_id, "address-2", NOW_MS),
            Err(PairingJoinRuntimeError::InvalidCandidate)
        ));
        assert!(matches!(
            runtime.endpoint_for_candidate(&summary.attempt_id, "../address-1", NOW_MS),
            Err(PairingJoinRuntimeError::InvalidCandidate)
        ));
    }
}
