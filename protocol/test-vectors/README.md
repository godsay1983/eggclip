# EggClip v1 Test Vectors

These fixtures are shared by Rust and ArkTS implementations.

Current status:

- `handshake/`: schema fixtures for plaintext pre-auth envelopes.
- `sync/`: plaintext canonical payload fixtures for sync records, plus encrypted
  business-envelope fixtures such as `ITEM_LIVE` and `SPACE_KEY_ROTATED`.
- `errors/`: frames that must be rejected by schema or protocol checks.
- `crypto/`: byte-for-byte cryptographic vectors for Ed25519, X25519,
  HKDF-SHA-256, AES-256-GCM, auth proof transcript binding, directional session
  keys, nonce construction and replay counter rejection.

Do not put real clipboard content, pairing secrets, private keys, or production space keys in this directory.

Run the lightweight fixture check from the repository root:

```powershell
node .\protocol\scripts\validate-fixtures.mjs
```
