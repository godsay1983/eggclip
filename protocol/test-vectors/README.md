# EggClip v1 Test Vectors

These fixtures are shared by Rust and ArkTS implementations.

Current status:

- `handshake/`: schema fixtures for plaintext pre-auth envelopes.
- `sync/`: plaintext canonical payload fixtures for sync records.
- `errors/`: frames that must be rejected by schema or protocol checks.
- `crypto/`: placeholder for future byte-for-byte cryptographic vectors.

Do not put real clipboard content, pairing secrets, private keys, or production space keys in this directory.

Run the lightweight fixture check from the repository root:

```powershell
node .\protocol\scripts\validate-fixtures.mjs
```
