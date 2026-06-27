use std::{collections::HashSet, fmt};

use aes_gcm::{
    aead::{Aead, Payload},
    Aes256Gcm, Key, KeyInit, Nonce,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use hkdf::Hkdf;
use sha2::Sha256;
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret};

pub const ED25519_PRIVATE_SEED_BYTES: usize = 32;
pub const ED25519_PUBLIC_KEY_BYTES: usize = 32;
pub const ED25519_SIGNATURE_BYTES: usize = 64;
pub const X25519_PRIVATE_KEY_BYTES: usize = 32;
pub const X25519_PUBLIC_KEY_BYTES: usize = 32;
pub const X25519_SHARED_SECRET_BYTES: usize = 32;
pub const AES_256_KEY_BYTES: usize = 32;
pub const AES_GCM_NONCE_BYTES: usize = 12;
pub const AES_GCM_TAG_BYTES: usize = 16;
pub const SESSION_KEY_BYTES: usize = AES_256_KEY_BYTES;
pub const SESSION_KEY_INFO_CLIENT_TO_SERVER: &[u8] = b"EggClip v1 session key client-to-server";
pub const SESSION_KEY_INFO_SERVER_TO_CLIENT: &[u8] = b"EggClip v1 session key server-to-client";
const NONCE_PREFIX_CLIENT_TO_SERVER: [u8; 4] = [b'c', b'2', b's', 1];
const NONCE_PREFIX_SERVER_TO_CLIENT: [u8; 4] = [b's', b'2', b'c', 1];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CryptoError {
    InvalidBase64,
    InvalidLength {
        field: &'static str,
        actual: usize,
        expected: usize,
    },
    InvalidPublicKey,
    InvalidSignature,
    VerificationFailed,
    KdfFailed,
    AeadFailed,
    Replay,
}

impl fmt::Display for CryptoError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CryptoError::InvalidBase64 => formatter.write_str("invalid base64url"),
            CryptoError::InvalidLength {
                field,
                actual,
                expected,
            } => write!(
                formatter,
                "invalid {field} length: got {actual} bytes, expected {expected}"
            ),
            CryptoError::InvalidPublicKey => formatter.write_str("invalid public key"),
            CryptoError::InvalidSignature => formatter.write_str("invalid signature"),
            CryptoError::VerificationFailed => formatter.write_str("signature verification failed"),
            CryptoError::KdfFailed => formatter.write_str("key derivation failed"),
            CryptoError::AeadFailed => formatter.write_str("AEAD operation failed"),
            CryptoError::Replay => formatter.write_str("replayed or old counter"),
        }
    }
}

impl std::error::Error for CryptoError {}

pub fn decode_base64url(value: &str) -> Result<Vec<u8>, CryptoError> {
    URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| CryptoError::InvalidBase64)
}

pub fn encode_base64url(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

pub fn fixed_bytes<const N: usize>(
    value: &[u8],
    field: &'static str,
) -> Result<[u8; N], CryptoError> {
    value.try_into().map_err(|_| CryptoError::InvalidLength {
        field,
        actual: value.len(),
        expected: N,
    })
}

#[derive(Debug, Clone)]
pub struct Ed25519Identity {
    signing_key: SigningKey,
}

impl Ed25519Identity {
    pub fn from_seed(seed: [u8; ED25519_PRIVATE_SEED_BYTES]) -> Self {
        Self {
            signing_key: SigningKey::from_bytes(&seed),
        }
    }

    pub fn public_key(&self) -> [u8; ED25519_PUBLIC_KEY_BYTES] {
        self.signing_key.verifying_key().to_bytes()
    }

    pub fn sign(&self, message: &[u8]) -> [u8; ED25519_SIGNATURE_BYTES] {
        self.signing_key.sign(message).to_bytes()
    }
}

pub fn verify_ed25519_signature(
    public_key: [u8; ED25519_PUBLIC_KEY_BYTES],
    message: &[u8],
    signature: [u8; ED25519_SIGNATURE_BYTES],
) -> Result<(), CryptoError> {
    let verifying_key =
        VerifyingKey::from_bytes(&public_key).map_err(|_| CryptoError::InvalidPublicKey)?;
    let signature = Signature::from_slice(&signature).map_err(|_| CryptoError::InvalidSignature)?;
    verifying_key
        .verify(message, &signature)
        .map_err(|_| CryptoError::VerificationFailed)
}

#[derive(Clone)]
pub struct X25519Secret {
    secret: StaticSecret,
}

impl X25519Secret {
    pub fn from_private_key(private_key: [u8; X25519_PRIVATE_KEY_BYTES]) -> Self {
        Self {
            secret: StaticSecret::from(private_key),
        }
    }

    pub fn public_key(&self) -> [u8; X25519_PUBLIC_KEY_BYTES] {
        X25519PublicKey::from(&self.secret).to_bytes()
    }

    pub fn shared_secret(
        &self,
        peer_public_key: [u8; X25519_PUBLIC_KEY_BYTES],
    ) -> [u8; X25519_SHARED_SECRET_BYTES] {
        let peer_public_key = X25519PublicKey::from(peer_public_key);
        self.secret.diffie_hellman(&peer_public_key).to_bytes()
    }
}

pub fn hkdf_sha256(
    ikm: &[u8],
    salt: &[u8],
    info: &[u8],
    output_length: usize,
) -> Result<Vec<u8>, CryptoError> {
    let hkdf = Hkdf::<Sha256>::new(Some(salt), ikm);
    let mut okm = vec![0u8; output_length];
    hkdf.expand(info, &mut okm)
        .map_err(|_| CryptoError::KdfFailed)?;
    Ok(okm)
}

pub fn hkdf_sha256_extract(ikm: &[u8], salt: &[u8]) -> Vec<u8> {
    let (prk, _) = Hkdf::<Sha256>::extract(Some(salt), ikm);
    prk.as_slice().to_vec()
}

pub fn aes256_gcm_encrypt(
    key: [u8; AES_256_KEY_BYTES],
    nonce: [u8; AES_GCM_NONCE_BYTES],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<(Vec<u8>, [u8; AES_GCM_TAG_BYTES]), CryptoError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&key));
    let encrypted = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CryptoError::AeadFailed)?;
    let split_at = encrypted
        .len()
        .checked_sub(AES_GCM_TAG_BYTES)
        .ok_or(CryptoError::AeadFailed)?;
    let (ciphertext, tag) = encrypted.split_at(split_at);
    Ok((
        ciphertext.to_vec(),
        fixed_bytes::<AES_GCM_TAG_BYTES>(tag, "tag")?,
    ))
}

pub fn aes256_gcm_decrypt(
    key: [u8; AES_256_KEY_BYTES],
    nonce: [u8; AES_GCM_NONCE_BYTES],
    aad: &[u8],
    ciphertext: &[u8],
    tag: [u8; AES_GCM_TAG_BYTES],
) -> Result<Vec<u8>, CryptoError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&key));
    let mut body_and_tag = Vec::with_capacity(ciphertext.len() + AES_GCM_TAG_BYTES);
    body_and_tag.extend_from_slice(ciphertext);
    body_and_tag.extend_from_slice(&tag);
    cipher
        .decrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &body_and_tag,
                aad,
            },
        )
        .map_err(|_| CryptoError::AeadFailed)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionDirection {
    ClientToServer,
    ServerToClient,
}

impl SessionDirection {
    fn key_info(self) -> &'static [u8] {
        match self {
            SessionDirection::ClientToServer => SESSION_KEY_INFO_CLIENT_TO_SERVER,
            SessionDirection::ServerToClient => SESSION_KEY_INFO_SERVER_TO_CLIENT,
        }
    }

    fn nonce_prefix(self) -> [u8; 4] {
        match self {
            SessionDirection::ClientToServer => NONCE_PREFIX_CLIENT_TO_SERVER,
            SessionDirection::ServerToClient => NONCE_PREFIX_SERVER_TO_CLIENT,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionKeys {
    pub client_to_server: [u8; SESSION_KEY_BYTES],
    pub server_to_client: [u8; SESSION_KEY_BYTES],
}

pub fn derive_session_keys(
    shared_secret: [u8; X25519_SHARED_SECRET_BYTES],
    transcript_salt: &[u8],
) -> Result<SessionKeys, CryptoError> {
    Ok(SessionKeys {
        client_to_server: derive_directional_session_key(
            shared_secret,
            transcript_salt,
            SessionDirection::ClientToServer,
        )?,
        server_to_client: derive_directional_session_key(
            shared_secret,
            transcript_salt,
            SessionDirection::ServerToClient,
        )?,
    })
}

pub fn derive_directional_session_key(
    shared_secret: [u8; X25519_SHARED_SECRET_BYTES],
    transcript_salt: &[u8],
    direction: SessionDirection,
) -> Result<[u8; SESSION_KEY_BYTES], CryptoError> {
    fixed_bytes(
        &hkdf_sha256(
            &shared_secret,
            transcript_salt,
            direction.key_info(),
            SESSION_KEY_BYTES,
        )?,
        "sessionKey",
    )
}

pub fn session_nonce(direction: SessionDirection, counter: u64) -> [u8; AES_GCM_NONCE_BYTES] {
    let mut nonce = [0u8; AES_GCM_NONCE_BYTES];
    nonce[..4].copy_from_slice(&direction.nonce_prefix());
    nonce[4..].copy_from_slice(&counter.to_be_bytes());
    nonce
}

#[derive(Debug, Default)]
pub struct SessionCounterGuard {
    highest_seen: Option<u64>,
    seen: HashSet<u64>,
}

impl SessionCounterGuard {
    pub fn accept(&mut self, counter: u64) -> Result<(), CryptoError> {
        if self.seen.contains(&counter)
            || self.highest_seen.is_some_and(|highest| counter <= highest)
        {
            return Err(CryptoError::Replay);
        }
        self.highest_seen = Some(counter);
        self.seen.insert(counter);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use std::{fs, path::PathBuf};

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Ed25519Vector {
        private_seed: String,
        public_key: String,
        message: String,
        signature: String,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct X25519Vector {
        alice_private_key: String,
        alice_public_key: String,
        bob_private_key: String,
        bob_public_key: String,
        shared_secret: String,
    }

    #[derive(Debug, Deserialize)]
    struct HkdfVector {
        ikm: String,
        salt: String,
        info: String,
        length: usize,
        prk: String,
        okm: String,
    }

    #[derive(Debug, Deserialize)]
    struct AesGcmVector {
        key: String,
        nonce: String,
        aad: String,
        plaintext: String,
        ciphertext: String,
        tag: String,
        #[serde(rename = "tamperedTag")]
        tampered_tag: String,
    }

    #[derive(Debug, Deserialize)]
    struct CounterVector {
        accepted: Vec<u64>,
        rejected: Vec<RejectedCounter>,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SessionKeysVector {
        shared_secret: String,
        transcript_salt: String,
        client_to_server_info: String,
        server_to_client_info: String,
        client_to_server_key: String,
        server_to_client_key: String,
        counter: u64,
        client_to_server_nonce: String,
        server_to_client_nonce: String,
    }

    #[derive(Debug, Deserialize)]
    struct RejectedCounter {
        counter: u64,
        reason: String,
    }

    fn vector_path(parts: &[&str]) -> PathBuf {
        let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        path.push("..");
        path.push("..");
        path.push("protocol");
        for part in parts {
            path.push(part);
        }
        path
    }

    fn read_vector<T: for<'de> Deserialize<'de>>(parts: &[&str]) -> T {
        let data = fs::read_to_string(vector_path(parts)).expect("test vector should be readable");
        serde_json::from_str(&data).expect("test vector should deserialize")
    }

    fn decoded_fixed<const N: usize>(
        value: &str,
        field: &'static str,
    ) -> Result<[u8; N], CryptoError> {
        fixed_bytes(&decode_base64url(value)?, field)
    }

    #[test]
    fn ed25519_matches_shared_vector() {
        let vector: Ed25519Vector =
            read_vector(&["test-vectors", "crypto", "ed25519-signature.valid.json"]);
        let identity = Ed25519Identity::from_seed(
            decoded_fixed(&vector.private_seed, "privateSeed").expect("seed should decode"),
        );
        let expected_public_key =
            decoded_fixed(&vector.public_key, "publicKey").expect("public key should decode");
        let expected_signature =
            decoded_fixed(&vector.signature, "signature").expect("signature should decode");

        assert_eq!(identity.public_key(), expected_public_key);
        assert_eq!(identity.sign(vector.message.as_bytes()), expected_signature);
        verify_ed25519_signature(
            expected_public_key,
            vector.message.as_bytes(),
            expected_signature,
        )
        .expect("signature should verify");
        let mut tampered = expected_signature;
        tampered[0] ^= 0x01;
        assert_eq!(
            verify_ed25519_signature(expected_public_key, vector.message.as_bytes(), tampered)
                .unwrap_err(),
            CryptoError::VerificationFailed
        );
    }

    #[test]
    fn x25519_matches_shared_vector() {
        let vector: X25519Vector =
            read_vector(&["test-vectors", "crypto", "x25519-shared-secret.valid.json"]);
        let alice = X25519Secret::from_private_key(
            decoded_fixed(&vector.alice_private_key, "alicePrivateKey")
                .expect("alice private key should decode"),
        );
        let bob = X25519Secret::from_private_key(
            decoded_fixed(&vector.bob_private_key, "bobPrivateKey")
                .expect("bob private key should decode"),
        );
        let alice_public_key =
            decoded_fixed(&vector.alice_public_key, "alicePublicKey").expect("alice public key");
        let bob_public_key =
            decoded_fixed(&vector.bob_public_key, "bobPublicKey").expect("bob public key");
        let shared_secret =
            decoded_fixed(&vector.shared_secret, "sharedSecret").expect("shared secret");

        assert_eq!(alice.public_key(), alice_public_key);
        assert_eq!(bob.public_key(), bob_public_key);
        assert_eq!(alice.shared_secret(bob_public_key), shared_secret);
        assert_eq!(bob.shared_secret(alice_public_key), shared_secret);
    }

    #[test]
    fn hkdf_sha256_matches_shared_vector() {
        let vector: HkdfVector = read_vector(&["test-vectors", "crypto", "hkdf-sha256.valid.json"]);
        let ikm = decode_base64url(&vector.ikm).expect("ikm should decode");
        let salt = decode_base64url(&vector.salt).expect("salt should decode");
        let info = decode_base64url(&vector.info).expect("info should decode");
        let expected_prk = decode_base64url(&vector.prk).expect("prk should decode");
        let expected_okm = decode_base64url(&vector.okm).expect("okm should decode");

        assert_eq!(hkdf_sha256_extract(&ikm, &salt), expected_prk);
        assert_eq!(
            hkdf_sha256(&ikm, &salt, &info, vector.length).expect("hkdf should expand"),
            expected_okm
        );
    }

    #[test]
    fn aes256_gcm_matches_shared_vector_and_rejects_tampering() {
        let vector: AesGcmVector =
            read_vector(&["test-vectors", "crypto", "aes-256-gcm.valid.json"]);
        let key = decoded_fixed(&vector.key, "key").expect("key should decode");
        let nonce = decoded_fixed(&vector.nonce, "nonce").expect("nonce should decode");
        let aad = decode_base64url(&vector.aad).expect("aad should decode");
        let plaintext = decode_base64url(&vector.plaintext).expect("plaintext should decode");
        let expected_ciphertext =
            decode_base64url(&vector.ciphertext).expect("ciphertext should decode");
        let expected_tag = decoded_fixed(&vector.tag, "tag").expect("tag should decode");
        let tampered_tag =
            decoded_fixed(&vector.tampered_tag, "tamperedTag").expect("tampered tag");

        let (ciphertext, tag) =
            aes256_gcm_encrypt(key, nonce, &aad, &plaintext).expect("encrypt should succeed");
        assert_eq!(ciphertext, expected_ciphertext);
        assert_eq!(tag, expected_tag);
        assert_eq!(
            aes256_gcm_decrypt(key, nonce, &aad, &ciphertext, tag).expect("decrypt should succeed"),
            plaintext
        );
        assert_eq!(
            aes256_gcm_decrypt(key, nonce, &aad, &ciphertext, tampered_tag).unwrap_err(),
            CryptoError::AeadFailed
        );
    }

    #[test]
    fn session_keys_and_nonces_match_shared_vector() {
        let vector: SessionKeysVector =
            read_vector(&["test-vectors", "crypto", "session-keys.valid.json"]);
        assert_eq!(
            vector.client_to_server_info.as_bytes(),
            SESSION_KEY_INFO_CLIENT_TO_SERVER
        );
        assert_eq!(
            vector.server_to_client_info.as_bytes(),
            SESSION_KEY_INFO_SERVER_TO_CLIENT
        );

        let shared_secret =
            decoded_fixed(&vector.shared_secret, "sharedSecret").expect("shared secret");
        let transcript_salt =
            decode_base64url(&vector.transcript_salt).expect("transcript salt should decode");
        let expected_client_key =
            decoded_fixed(&vector.client_to_server_key, "clientToServerKey").expect("c2s key");
        let expected_server_key =
            decoded_fixed(&vector.server_to_client_key, "serverToClientKey").expect("s2c key");
        let expected_client_nonce =
            decoded_fixed(&vector.client_to_server_nonce, "clientToServerNonce")
                .expect("c2s nonce");
        let expected_server_nonce =
            decoded_fixed(&vector.server_to_client_nonce, "serverToClientNonce")
                .expect("s2c nonce");

        let keys = derive_session_keys(shared_secret, &transcript_salt)
            .expect("session keys should derive");
        assert_eq!(keys.client_to_server, expected_client_key);
        assert_eq!(keys.server_to_client, expected_server_key);
        assert_ne!(keys.client_to_server, keys.server_to_client);
        assert_eq!(
            session_nonce(SessionDirection::ClientToServer, vector.counter),
            expected_client_nonce
        );
        assert_eq!(
            session_nonce(SessionDirection::ServerToClient, vector.counter),
            expected_server_nonce
        );
    }

    #[test]
    fn session_counter_guard_rejects_old_and_duplicate_counters() {
        let vector: CounterVector =
            read_vector(&["test-vectors", "crypto", "replay-counter.reject.json"]);
        let mut guard = SessionCounterGuard::default();

        for counter in vector.accepted {
            guard.accept(counter).expect("counter should be accepted");
        }
        for rejected in vector.rejected {
            assert!(matches!(rejected.reason.as_str(), "duplicate" | "old"));
            assert_eq!(
                guard.accept(rejected.counter).unwrap_err(),
                CryptoError::Replay
            );
        }
    }
}
