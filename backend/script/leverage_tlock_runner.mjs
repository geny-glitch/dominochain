#!/usr/bin/env node
/**
 * Server-side tlock encrypt/decrypt helper.
 *
 * Uses the Node tlock-js package (native Buffer) rather than the browser
 * vendor IIFE. The IIFE's Buffer polyfill copies large payloads as JS
 * numbers and OOMs around the default ~512MB heap.
 *
 * Encrypt uses the quicknet public key in defaultChainInfo (no drand HTTP).
 * Decrypt uses mainnetClient so it can fetch beacons after the round.
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
import {
  defaultChainInfo,
  mainnetClient,
  roundAt,
  timelockDecrypt,
  timelockEncrypt
} from "tlock-js";

const MAX_INPUT_BYTES = 48 * 1024 * 1024;

function staticChainClient() {
  const info = defaultChainInfo;
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

function readInput(inPath) {
  const st = fs.statSync(inPath);
  if (st.size === 0) throw new Error("empty input");
  if (st.size > MAX_INPUT_BYTES) {
    throw new Error(`input too large (${st.size} bytes)`);
  }
  return fs.readFileSync(inPath);
}

async function encryptPayload(bytes, lockedUntilMs) {
  const chainInfo = defaultChainInfo;
  const round = roundAt(lockedUntilMs, chainInfo);
  if (!Number.isFinite(round) || round < 1) {
    throw new Error("Invalid drand round for selected duration");
  }
  const armored = await timelockEncrypt(
    round,
    bytes,
    staticChainClient()
  );
  return {
    armored,
    round,
    chain_hash: chainInfo.hash
  };
}

async function peelLayers(outerArmored) {
  const client = mainnetClient();
  let payload = outerArmored;
  let layersPeeled = 0;
  const max = 64;
  while (layersPeeled < max) {
    const decrypted = await timelockDecrypt(payload, client);
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

  if (command === "decrypt-bytes") {
    const armored = readInput(inPath).toString("utf8");
    if (!armored.trim()) throw new Error("empty input");
    const peeled = await peelLayers(armored);
    fs.writeFileSync(outPath, peeled);
    process.stdout.write(JSON.stringify({ ok: true }));
    return;
  }

  const lockedUntilMs = Number(process.argv[5]);
  if (!Number.isFinite(lockedUntilMs) || lockedUntilMs <= Date.now()) {
    throw new Error("locked_until_ms must be a future timestamp");
  }

  const buf = readInput(inPath);
  const bytes = Buffer.from(buf);
  const result = await encryptPayload(bytes, lockedUntilMs);
  fs.writeFileSync(outPath, result.armored, "utf8");
  process.stdout.write(JSON.stringify({
    round: result.round,
    chain_hash: result.chain_hash
  }));
}

main().catch((err) => {
  process.stderr.write(String(err && err.message ? err.message : err) + "\n");
  process.exit(1);
});
