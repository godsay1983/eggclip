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

Authentication gate:

- `connecting` and `handshaking` accept only plaintext handshake messages.
- `AUTH_OK` moves the session to `authenticated`.
- `authenticated`, `syncing`, and `ready` accept encrypted business messages only.
- `SYNC_HEADS`, `REQUEST_RANGE`, and `ITEM_BATCH` move the session through `syncing`.
- `ITEM_LIVE`, `ITEM_ACK`, `PING`, and `PONG` keep or return the session to `ready`.
- `AUTH_ERROR` or safe protocol `ERROR` moves the session to `failed`.
- The inbound session rejects repeated `messageId` values and non-increasing
  `sessionCounter` values before dispatching payloads to sync or storage code.

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
  "pairingContext": "pairing-invitation:v1:018ff6f0-1111-7222-8333-123456789abc",
  "capabilities": ["textPlain", "syncHeads"]
}
```

`pairingContext` is optional for an already trusted-device reconnect, but required for
invitation-based pairing. It is a public routing and transcript-binding value; it
must not contain the `pairingSecret`.

`AUTH_PROOF` signs the canonical handshake transcript with the Ed25519 identity key and binds:

- protocol version
- role
- `spaceId`
- local and remote `deviceId`
- local and remote identity public keys
- local and remote ephemeral public keys
- pairing or trusted-device context

The canonical transcript is UTF-8 text with fixed LF line endings:

```text
EggClip v1 auth transcript
role=<client|server>
spaceId=<uuid>
localDeviceId=<uuid>
remoteDeviceId=<uuid>
localIdentityPublicKey=<base64url>
remoteIdentityPublicKey=<base64url>
localEphemeralPublicKey=<base64url>
remoteEphemeralPublicKey=<base64url>
pairingContext=<versioned context>
```

An `AUTH_PROOF` payload carries:

```json
{
  "role": "client",
  "signatureAlgorithm": "Ed25519",
  "transcriptHash": "base64url-sha256-canonical-transcript",
  "signature": "base64url-ed25519-signature"
}
```

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
- Session keys are derived with HKDF-SHA-256 from the X25519 shared secret,
  handshake transcript salt and a direction-specific info string.
- The sender increments `sessionCounter` monotonically.
- The 96-bit AES-GCM nonce is `directionPrefix || sessionCounter`, where
  `directionPrefix` is `c2s\x01` or `s2c\x01` and `sessionCounter` is an
  unsigned 64-bit big-endian integer.
- A receiver rejects old counters, repeated counters, repeated `messageId`, and AEAD failures.

AAD rules:

- `aad` is the Base64URL encoding of the canonical UTF-8 AAD text.
- The canonical AAD has fixed LF line endings and fixed field order:

```text
EggClip v1 ciphertext aad
version=1
type=<message type>
messageId=<uuid>
sessionCounter=<u64>
algorithm=AES-256-GCM
keyId=<session key id>
```

- The receiver reconstructs the canonical AAD from the envelope fields and
  rejects mismatched `aad`, mismatched direction/key id, mismatched nonce, and
  AEAD authentication failures before exposing plaintext to sync or storage code.

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

`REQUEST_RANGE` uses `ranges: [{ originDeviceId, fromSeq, toSeq }]`. The sender replies with
`ITEM_BATCH { items, gaps }`; a gap contains `originDeviceId`, `requestedFromSeq`, and
`minimumAvailable`. After history-only persistence, the receiver sends
`ITEM_ACK { itemIds }`. Batch items never trigger a system clipboard write.

## Space Key Delivery

During invitation-based pairing, the desktop sends the initial space key after
`AUTH_OK` as an encrypted `SPACE_KEY_ROTATED` frame on the authenticated
session:

```json
{
  "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
  "keyVersion": 1,
  "spaceKey": "base64url-32-byte-space-key",
  "delivery": "pairing-v1"
}
```

Rules:

- This payload is never valid before authentication and must only appear inside `ciphertext`.
- `spaceKey` is a raw 256-bit member secret encoded with Base64URL, so it must not be logged, copied to UI, or stored in plaintext.
- Receivers must verify `spaceId`, `keyVersion`, and key length before creating or updating a local secure-storage reference.

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

Current fixtures include schema/parsing JSON and deterministic byte-for-byte
crypto vectors for Ed25519, X25519, HKDF-SHA-256, AES-256-GCM, directional
session keys, nonce construction and replay counter rejection. These are public
or synthetic test-only vectors; they are not production keys, invitations or
clipboard content.
