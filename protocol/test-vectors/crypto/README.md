# Crypto Test Vectors

Add deterministic byte-for-byte vectors here before implementing encrypted sessions:

- Ed25519 signing and verification
- X25519 shared secret derivation
- HKDF-SHA-256 session key derivation
- AES-256-GCM encryption and tamper rejection
- Replay and counter rejection fixtures

Use fixed test-only keys. Never add production keys, pairing secrets, or real clipboard text.
