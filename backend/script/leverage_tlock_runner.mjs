#!/usr/bin/env node
/**
 * Server-side tlock encrypt helper.
 * Loads the browser vendored IIFE with Node's require/crypto available.
 *
 * Usage:
 *   echo '{"bytes_base64":"...","locked_until_ms":123}' | node script/leverage_tlock_runner.mjs encrypt-bytes
 *   echo '{"armored":"...","locked_until_ms":123}' | node script/leverage_tlock_runner.mjs encrypt-outer
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

async function readStdinJson() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) throw new Error("Empty stdin");
  return JSON.parse(raw);
}

async function encryptPayload(api, bytes, lockedUntilMs) {
  const client = api.mainnetClient();
  const chainInfo = api.defaultChainInfo || (await client.chain().info());
  const round = api.roundAt(lockedUntilMs, chainInfo);
  if (!Number.isFinite(round) || round < 1) {
    throw new Error("Invalid drand round for selected duration");
  }
  const armored = await api.timelockEncrypt(
    round,
    api.Buffer.from(bytes),
    client
  );
  return {
    armored,
    round,
    chain_hash: chainInfo.hash
  };
}

async function main() {
  const command = process.argv[2];
  if (!["encrypt-bytes", "encrypt-outer"].includes(command)) {
    throw new Error("Usage: encrypt-bytes | encrypt-outer");
  }

  const input = await readStdinJson();
  const lockedUntilMs = Number(input.locked_until_ms);
  if (!Number.isFinite(lockedUntilMs) || lockedUntilMs <= Date.now()) {
    throw new Error("locked_until_ms must be a future timestamp");
  }

  const api = loadTlock();
  let bytes;
  if (command === "encrypt-bytes") {
    if (!input.bytes_base64) throw new Error("bytes_base64 required");
    bytes = Buffer.from(input.bytes_base64, "base64");
  } else {
    if (!input.armored) throw new Error("armored required");
    bytes = Buffer.from(String(input.armored), "utf8");
  }

  const result = await encryptPayload(api, bytes, lockedUntilMs);
  process.stdout.write(JSON.stringify(result));
}

main().catch((err) => {
  process.stderr.write(String(err && err.stack ? err.stack : err) + "\n");
  process.exit(1);
});
