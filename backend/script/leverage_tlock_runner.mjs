#!/usr/bin/env node
/**
 * Server-side tlock encrypt/decrypt helper.
 *
 * Loads the browser vendored IIFE, then encrypts or peels a file in place
 * without shuttling the payload through JSON/base64. Encrypt uses the
 * quicknet public key already in defaultChainInfo (no drand HTTP). Decrypt
 * uses mainnetClient so it can fetch beacons after the round.
 *
 * Usage:
 *   node script/leverage_tlock_runner.mjs encrypt-bytes <in> <out> <locked_until_ms>
 *   node script/leverage_tlock_runner.mjs encrypt-outer <in> <out> <locked_until_ms>
 *   node script/leverage_tlock_runner.mjs decrypt-bytes <in> <out>
 *
 * Encrypt writes armored ciphertext to <out> and prints JSON {round, chain_hash}.
 * Decrypt writes the peeled payload bytes to <out>.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { createRequire } from "node:module";
import { webcrypto } from "node:crypto";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const vendorPath = path.resolve(__dirname, "../public/vendor/tlock-js.js");
const nodeRequire = createRequire(import.meta.url);

function loadTlock() {
  const code = fs.readFileSync(vendorPath, "utf8");
  const sandbox = {
    console,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    fetch: globalThis.fetch,
    URL,
    URLSearchParams,
    TextEncoder,
    TextDecoder,
    Buffer,
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
    btoa: (s) => Buffer.from(s, "binary").toString("base64"),
    crypto: globalThis.crypto || webcrypto,
    require: nodeRequire,
    process,
    global: {},
    module: { exports: {} },
    exports: {}
  };
  sandbox.global = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  if (!sandbox.TlockJs || typeof sandbox.TlockJs.timelockEncrypt !== "function") {
    throw new Error("Failed to load TlockJs from vendor bundle");
  }
  return sandbox.TlockJs;
}

// Encrypt only needs the scheme public key. Creating a fresh HttpCachingChain
// would HTTP GET api.drand.sh/info on every lock (~1s+, and hangs when drand
// is slow). defaultChainInfo is the same quicknet metadata baked into the client.
function staticChainClient(api) {
  const info = api.defaultChainInfo;
  if (!info?.public_key || !info?.hash) {
    throw new Error("defaultChainInfo missing");
  }
  return {
    chain() {
      return {
        async info() {
          return info;
        }
      };
    }
  };
}

function isArmoredAge(text) {
  return typeof text === "string" && text.trimStart().indexOf("-----BEGIN AGE ENCRYPTED FILE-----") === 0;
}

async function encryptPayload(api, bytes, lockedUntilMs) {
  const chainInfo = api.defaultChainInfo;
  const round = api.roundAt(lockedUntilMs, chainInfo);
  if (!Number.isFinite(round) || round < 1) {
    throw new Error("Invalid drand round for selected duration");
  }
  const armored = await api.timelockEncrypt(
    round,
    bytes,
    staticChainClient(api)
  );
  return {
    armored,
    round,
    chain_hash: chainInfo.hash
  };
}

async function peelLayers(api, outerArmored) {
  const client = api.mainnetClient();
  let payload = outerArmored;
  let layersPeeled = 0;
  const max = 64;
  while (layersPeeled < max) {
    const decrypted = await api.timelockDecrypt(payload, client);
    layersPeeled += 1;
    const buf = Buffer.from(decrypted);
    const asText = buf.toString("utf8");
    if (isArmoredAge(asText)) {
      payload = asText;
      continue;
    }
    return buf;
  }
  throw new Error("RESTORE_LAYER_LIMIT");
}

async function main() {
  const command = process.argv[2];
  const inPath = process.argv[3];
  const outPath = process.argv[4];
  if (!["encrypt-bytes", "encrypt-outer", "decrypt-bytes"].includes(command)) {
    throw new Error("Usage: encrypt-bytes|encrypt-outer <in> <out> <locked_until_ms> OR decrypt-bytes <in> <out>");
  }
  if (!inPath || !outPath) {
    throw new Error("input and output paths required");
  }

  const api = loadTlock();

  if (command === "decrypt-bytes") {
    const armored = fs.readFileSync(inPath, "utf8");
    if (!armored.trim()) throw new Error("empty input");
    const peeled = await peelLayers(api, armored);
    fs.writeFileSync(outPath, peeled);
    process.stdout.write(JSON.stringify({ ok: true }));
    return;
  }

  const lockedUntilMs = Number(process.argv[5]);
  if (!Number.isFinite(lockedUntilMs) || lockedUntilMs <= Date.now()) {
    throw new Error("locked_until_ms must be a future timestamp");
  }

  const buf = fs.readFileSync(inPath);
  if (buf.length === 0) throw new Error("empty input");
  const bytes = command === "encrypt-outer"
    ? buf
    : new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);

  const result = await encryptPayload(api, bytes, lockedUntilMs);
  fs.writeFileSync(outPath, result.armored, "utf8");
  process.stdout.write(JSON.stringify({
    round: result.round,
    chain_hash: result.chain_hash
  }));
}

main().catch((err) => {
  process.stderr.write(String(err && err.stack ? err.stack : err) + "\n");
  process.exit(1);
});
