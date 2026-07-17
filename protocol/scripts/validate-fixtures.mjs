import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const vectors = join(root, "test-vectors");

const preAuthTypes = new Set([
  "CLIENT_HELLO",
  "SERVER_HELLO",
  "AUTH_PROOF",
  "AUTH_OK",
  "AUTH_ERROR",
  "ERROR",
]);
const encryptedTypes = new Set([
  "SYNC_HEADS",
  "REQUEST_RANGE",
  "ITEM_BATCH",
  "ITEM_LIVE",
  "ITEM_ACK",
  "DEVICE_REVOKED",
  "SPACE_KEY_ROTATED",
  "PING",
  "PONG",
  "ERROR",
]);

let failures = 0;

for (const file of jsonFiles(root)) {
  try {
    const value = readJson(file);
    if (file.endsWith(".valid.json")) {
      assertAccepts(file, value);
    }
    if (file.endsWith(".reject.json")) {
      assertRejects(file, value);
    }
  } catch (error) {
    failures += 1;
    console.error(`${file}: ${error.message}`);
  }
}

if (failures > 0) {
  process.exitCode = 1;
} else {
  console.log("protocol fixtures ok");
}

function* jsonFiles(directory) {
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) {
      yield* jsonFiles(path);
    } else if (name.endsWith(".json")) {
      yield path;
    }
  }
}

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

function assertAccepts(file, value) {
  if (isCryptoFixture(file) || typeof value?.algorithm === "string") {
    validateCryptoVector(value);
    return;
  }
  if (file.startsWith(vectors) && file.includes(`${sep()}sync${sep()}clipboard-item`)) {
    validateClipboardItem(value);
    return;
  }
  if (file.startsWith(join(vectors, "sync")) && !file.includes("-envelope.")) {
    validateSyncPayload(file, value);
    return;
  }
  validateEnvelope(value);
}

function assertRejects(file, value) {
  if (isCryptoFixture(file)) {
    validateCryptoVector(value);
    return;
  }
  try {
    validateEnvelope(value);
  } catch {
    return;
  }
  throw new Error("reject fixture was accepted");
}

function validateCryptoVector(value) {
  requireObject(value, "crypto vector");
  if (typeof value.algorithm !== "string" || value.algorithm.length === 0) {
    throw new Error("algorithm must be a non-empty string");
  }
  switch (value.algorithm) {
    case "Ed25519":
      requireBase64Url(value.privateSeed, "privateSeed");
      requireBase64Url(value.publicKey, "publicKey");
      requireBase64Url(value.signature, "signature");
      if (typeof value.message !== "string") {
        throw new Error("message must be a string");
      }
      return;
    case "X25519":
      for (const field of [
        "alicePrivateKey",
        "alicePublicKey",
        "bobPrivateKey",
        "bobPublicKey",
        "sharedSecret",
      ]) {
        requireBase64Url(value[field], field);
      }
      return;
    case "HMAC-SHA-256":
      for (const field of ["key", "digest"]) {
        requireBase64Url(value[field], field);
      }
      if (typeof value.message !== "string" || value.message.length === 0) {
        throw new Error("message must be a non-empty string");
      }
      if (typeof value.confirmationCode !== "string" || !/^\d{6}$/u.test(value.confirmationCode)) {
        throw new Error("confirmationCode must be six digits");
      }
      return;
    case "HKDF-SHA-256":
      for (const field of ["ikm", "salt", "info", "prk", "okm"]) {
        requireBase64Url(value[field], field);
      }
      requireUint(value.length, "length");
      return;
    case "AES-256-GCM":
      for (const field of ["key", "nonce", "aad", "plaintext", "ciphertext", "tag", "tamperedTag"]) {
        requireBase64Url(value[field], field);
      }
      return;
    case "EggClip-Session-Keys-v1":
      for (const field of [
        "sharedSecret",
        "transcriptSalt",
        "clientToServerKey",
        "serverToClientKey",
        "clientToServerNonce",
        "serverToClientNonce",
      ]) {
        requireBase64Url(value[field], field);
      }
      for (const field of ["clientToServerInfo", "serverToClientInfo"]) {
        if (typeof value[field] !== "string" || value[field].length === 0) {
          throw new Error(`${field} must be a non-empty string`);
        }
      }
      requireUint(value.counter, "counter");
      return;
    case "EggClip-Auth-Proof-v1":
      for (const field of ["spaceId", "localDeviceId", "remoteDeviceId"]) {
        requireUuid(value[field], field);
      }
      for (const field of [
        "localIdentityPublicKey",
        "remoteIdentityPublicKey",
        "localEphemeralPublicKey",
        "remoteEphemeralPublicKey",
        "transcriptHash",
        "signature",
      ]) {
        requireBase64Url(value[field], field);
      }
      if (!["client", "server"].includes(value.role)) {
        throw new Error("role must be client or server");
      }
      for (const field of ["pairingContext", "canonicalTranscript"]) {
        if (typeof value[field] !== "string" || value[field].length === 0) {
          throw new Error(`${field} must be a non-empty string`);
        }
      }
      return;
    case "EggClip-Session-Counter-v1":
      if (!Array.isArray(value.accepted) || !Array.isArray(value.rejected)) {
        throw new Error("counter vector must include accepted and rejected arrays");
      }
      value.accepted.forEach((counter, index) => requireUint(counter, `accepted[${index}]`));
      value.rejected.forEach((entry, index) => {
        requireObject(entry, `rejected[${index}]`);
        requireUint(entry.counter, `rejected[${index}].counter`);
        if (!["duplicate", "old"].includes(entry.reason)) {
          throw new Error(`rejected[${index}].reason must be duplicate or old`);
        }
      });
      return;
    case "EggClip-Pairing-Secret-Proof-v2":
      for (const field of ["invitationId", "spaceId", "issuerDeviceId", "clientDeviceId"]) {
        requireUuid(value[field], field);
      }
      for (const field of [
        "issuerIdentityPublicKey",
        "clientIdentityPublicKey",
        "clientEphemeralPublicKey",
        "pairingSecret",
        "verifier",
        "proof",
      ]) {
        requireBase64Url(value[field], field);
      }
      for (const field of ["source", "verifierInput", "claim"]) {
        if (typeof value[field] !== "string" || value[field].length === 0) {
          throw new Error(`${field} must be a non-empty string`);
        }
      }
      return;
    default:
      throw new Error(`unknown crypto vector algorithm: ${value.algorithm}`);
  }
}

function validateEnvelope(value) {
  requireObject(value, "envelope");
  requireEqual(value.version, 1, "version");
  requireUuid(value.messageId, "messageId");
  requireUint(value.sessionCounter, "sessionCounter");

  if (preAuthTypes.has(value.type) && Object.hasOwn(value, "payload")) {
    if (Object.hasOwn(value, "ciphertext")) {
      throw new Error("pre-auth envelope must not include ciphertext");
    }
    requireObject(value.payload, "payload");
    return;
  }

  if (encryptedTypes.has(value.type) && Object.hasOwn(value, "ciphertext")) {
    if (Object.hasOwn(value, "payload")) {
      throw new Error("encrypted envelope must not include plaintext payload");
    }
    validateCiphertext(value.ciphertext);
    return;
  }

  throw new Error(`invalid envelope type or auth gate: ${value.type}`);
}

function validateCiphertext(value) {
  requireObject(value, "ciphertext");
  requireEqual(value.algorithm, "AES-256-GCM", "ciphertext.algorithm");
  for (const field of ["keyId", "nonce", "aad", "body", "tag"]) {
    if (typeof value[field] !== "string" || value[field].length === 0) {
      throw new Error(`ciphertext.${field} must be a non-empty string`);
    }
  }
}

function validateClipboardItem(value) {
  requireObject(value, "clipboard item");
  for (const field of ["itemId", "spaceId", "originDeviceId"]) {
    requireUuid(value[field], field);
  }
  requireUint(value.originSeq, "originSeq");
  requireEqual(value.contentType, "text/plain", "contentType");
  requireUint(value.contentLength, "contentLength");
  if (value.contentLength > 262144) {
    throw new Error("contentLength exceeds 256 KiB");
  }
  for (const field of ["hlc", "contentDigest", "content"]) {
    if (typeof value[field] !== "string" || value[field].length === 0) {
      throw new Error(`${field} must be a non-empty string`);
    }
  }
  requireUint(value.createdAt, "createdAt");
}

function validateSyncPayload(file, value) {
  requireObject(value, "sync payload");
  if (file.endsWith("item-ack.valid.json")) {
    if (!Array.isArray(value.itemIds) || value.itemIds.length === 0) {
      throw new Error("itemIds must be a non-empty array");
    }
    value.itemIds.forEach((itemId, index) => requireUuid(itemId, `itemIds[${index}]`));
    return;
  }
  if (file.endsWith("request-range.valid.json")) {
    if (!Array.isArray(value.ranges) || value.ranges.length === 0) {
      throw new Error("ranges must be a non-empty array");
    }
    value.ranges.forEach((range, index) => {
      requireObject(range, `ranges[${index}]`);
      requireUuid(range.originDeviceId, `ranges[${index}].originDeviceId`);
      requireUint(range.fromSeq, `ranges[${index}].fromSeq`);
      requireUint(range.toSeq, `ranges[${index}].toSeq`);
    });
    return;
  }
  if (file.endsWith("item-batch.valid.json")) {
    if (!Array.isArray(value.items) || !Array.isArray(value.gaps)) {
      throw new Error("item batch must include items and gaps arrays");
    }
    value.items.forEach(validateClipboardItem);
    value.gaps.forEach((gap, index) => {
      requireObject(gap, `gaps[${index}]`);
      requireUuid(gap.originDeviceId, `gaps[${index}].originDeviceId`);
      requireUint(gap.requestedFromSeq, `gaps[${index}].requestedFromSeq`);
      requireUint(gap.minimumAvailable, `gaps[${index}].minimumAvailable`);
    });
    return;
  }
  throw new Error("unknown sync payload fixture");
}

function requireObject(value, field) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${field} must be an object`);
  }
}

function requireEqual(actual, expected, field) {
  if (actual !== expected) {
    throw new Error(`${field} must be ${expected}`);
  }
}

function requireUint(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative safe integer`);
  }
}

function requireUuid(value, field) {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(value)
  ) {
    throw new Error(`${field} must be a lowercase UUID`);
  }
}

function requireBase64Url(value, field) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]*$/u.test(value)) {
    throw new Error(`${field} must be base64url without padding`);
  }
}

function isCryptoFixture(file) {
  return file.startsWith(join(vectors, "crypto"));
}

function sep() {
  return process.platform === "win32" ? "\\" : "/";
}
