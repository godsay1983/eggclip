# EggClip Protocol v1

EggClip v1 protocol is a local-network, paired-device clipboard sync protocol. mDNS only discovers candidate addresses. Trust is established by pairing, device identity signatures, and authenticated encrypted sessions.

## Scope

- Application protocol version: `1`.
- Transport: WebSocket text frames for v1.
- Encoding: JSON envelope. Binary crypto inputs and outputs are represented as Base64URL without padding in JSON.
- Maximum frame size: 1 MiB.
- Maximum plaintext clipboard text: 256 KiB UTF-8.
- Maximum `ITEM_BATCH` item count: 100.
- Maximum `ITEM_BATCH` plaintext total before encryption: 512 KiB.
- Handshake timeout: 8 seconds.
- Idle heartbeat interval: 20 seconds.
- Idle disconnect timeout: 60 seconds without valid traffic.
- Supported content type: `text/plain`.
- Pre-authentication messages are limited to handshake and auth messages.
- Post-authentication business messages are encrypted with application-layer AEAD.

## State Machine

```text
disconnected
  -> connecting
  -> handshaking
  -> authenticated
  -> syncing
  -> ready
```

Any state may move to `failed` on timeout, malformed frame, unsupported version, authentication failure, replay, AEAD failure, or transport close. Recovery creates a fresh connection and a fresh session counter space.

## Envelope

Every frame uses an envelope:

```json
{
  "version": 1,
  "type": "CLIENT_HELLO",
  "messageId": "018ff6f0-2b1f-7cc5-b5d0-7e82c5f70f01",
  "sessionCounter": 0,
  "payload": {}
}
```

Fields:

- `version`: protocol version. Unknown higher versions are rejected explicitly.
- `type`: message type.
- `messageId`: UUID v7. It is used for duplicate detection and logs.
- `sessionCounter`: unsigned 64-bit counter for the current session direction.
- `payload`: plaintext payload, only allowed before authentication.
- `ciphertext`: encrypted payload, required after authentication.

Authentication gating:

- Before authentication, only `CLIENT_HELLO`, `SERVER_HELLO`, `AUTH_PROOF`, `AUTH_OK`, `AUTH_ERROR`, and `ERROR` are accepted.
- After authentication, business messages must use `ciphertext`; plaintext `payload` is rejected except protocol-level `ERROR` frames that reveal no secrets.

## Message Types

Handshake:

- `CLIENT_HELLO`
- `SERVER_HELLO`
- `AUTH_PROOF`
- `AUTH_OK`
- `AUTH_ERROR`

Sync:

- `SYNC_HEADS`
- `REQUEST_RANGE`
- `ITEM_BATCH`
- `ITEM_LIVE`
- `ITEM_ACK`

Device and space:

- `DEVICE_REVOKED`
- `SPACE_KEY_ROTATED`

Connection:

- `PING`
- `PONG`
- `ERROR`

## Handshake Payloads

`CLIENT_HELLO` and `SERVER_HELLO` exchange only public, non-secret values:

```json
{
  "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
  "deviceId": "018ff6f0-0a3b-7815-a4db-3eb6e23d9338",
  "identityPublicKey": "base64url-ed25519-public-key",
  "ephemeralPublicKey": "base64url-x25519-public-key",
  "capabilities": ["textPlain", "syncHeads"]
}
```

`AUTH_PROOF` signs the canonical handshake transcript with the Ed25519 identity key and binds:

- protocol version
- role
- `spaceId`
- local and remote `deviceId`
- local and remote identity public keys
- local and remote ephemeral public keys
- pairing or trusted-device context

`AUTH_OK` confirms both sides derived the same session context. `AUTH_ERROR` terminates the session and must not include secrets.

## Encrypted Payload

After `AUTH_OK`, each business frame uses:

```json
{
  "version": 1,
  "type": "ITEM_LIVE",
  "messageId": "018ff6f3-0d8c-7d1e-a38a-f308c64de79f",
  "sessionCounter": 12,
  "ciphertext": {
    "algorithm": "AES-256-GCM",
    "keyId": "session-v1-client-to-server",
    "nonce": "base64url-12-byte-nonce",
    "aad": "base64url-canonical-envelope-aad",
    "body": "base64url-ciphertext",
    "tag": "base64url-16-byte-tag"
  }
}
```

Nonce rules:

- Each direction has an independent session key and counter.
- The sender increments `sessionCounter` monotonically.
- A receiver rejects old counters, repeated counters, repeated `messageId`, and AEAD failures.

## Clipboard Item

Clipboard records are immutable events:

```json
{
  "itemId": "018ff6f3-3653-7c79-b38b-f4af3575396b",
  "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
  "originDeviceId": "018ff6f0-0a3b-7815-a4db-3eb6e23d9338",
  "originSeq": 42,
  "hlc": "1781946000123:0:018ff6f0",
  "contentType": "text/plain",
  "contentLength": 18,
  "contentDigest": "base64url-hmac-sha256",
  "createdAt": 1781946000123,
  "content": "example text"
}
```

Rules:

- `originSeq` is a durable per-device monotonic sequence.
- `hlc` is used for stable cross-device ordering.
- `contentDigest` is HMAC-SHA-256 over content using the space key context. Do not use bare SHA-256.
- `ITEM_LIVE` is for online real-time events and may trigger desktop auto-write policy.
- `ITEM_BATCH` is for history backfill and must not overwrite the system clipboard.

## Sync Heads

`SYNC_HEADS` communicates durable progress:

```json
{
  "heads": {
    "018ff6f0-0a3b-7815-a4db-3eb6e23d9338": 120
  },
  "minimumAvailable": {
    "018ff6f0-0a3b-7815-a4db-3eb6e23d9338": 71
  }
}
```

If a requested range is below `minimumAvailable`, the sender returns a retention gap response rather than pretending synchronization is complete.

## Compatibility

- v1 rejects unknown higher `version` values.
- Unknown message `type` values are rejected.
- Unknown fields in known messages are rejected until an explicit compatibility rule is added.
- New cryptographic algorithms require a new protocol version or an explicit negotiated capability.

## Test Vectors

`test-vectors/` contains shared fixtures consumed by Rust and ArkTS:

```text
test-vectors/
├─ handshake/
├─ crypto/
├─ sync/
└─ errors/
```

Current fixtures are schema and parsing fixtures only. Cryptographic byte-for-byte vectors must be added before implementing encrypted sessions.
