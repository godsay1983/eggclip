# Crypto Test Vectors

Deterministic byte-for-byte vectors in this directory cover:

- Ed25519 signing and verification
- X25519 shared secret derivation
- HKDF-SHA-256 session key derivation
- AES-256-GCM encryption and tamper rejection
- EggClip v1 AUTH_PROOF transcript binding
- EggClip v1 directional session key and nonce derivation
- Replay and counter rejection fixtures

All current key material comes from public standards test vectors or synthetic
counter examples. Never add production keys, pairing secrets, or real clipboard
text.
