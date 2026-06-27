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
  if (file.startsWith(vectors) && file.includes(`${sep()}sync${sep()}clipboard-item`)) {
    validateClipboardItem(value);
    return;
  }
  validateEnvelope(value);
}

function assertRejects(file, value) {
  try {
    validateEnvelope(value);
  } catch {
    return;
  }
  throw new Error("reject fixture was accepted");
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

function sep() {
  return process.platform === "win32" ? "\\" : "/";
}
