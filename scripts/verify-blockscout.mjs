#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const CHAIN_ID = 4663;
const API_URL =
  process.env.BLOCKSCOUT_API_URL ?? "https://robinhoodchain.blockscout.com/api/v2";
const COMPILER_VERSION = "v0.8.28+commit.7893614a";

function usage() {
  console.error(
    "usage: node scripts/verify-blockscout.mjs <worktree> <input.json> <output.json>",
  );
  process.exit(2);
}

const [worktreeArg, inputArg, outputArg] = process.argv.slice(2);
if (!worktreeArg || !inputArg || !outputArg) usage();

const worktree = path.resolve(worktreeArg);
const inputPath = path.resolve(inputArg);
const outputPath = path.resolve(outputArg);
const input = JSON.parse(await readFile(inputPath, "utf8"));

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function request(url, options = {}) {
  for (let attempt = 1; attempt <= 12; attempt += 1) {
    const response = await fetch(url, options);
    if (response.ok) return response;
    const body = await response.text();
    if (![429, 500, 502, 503, 504].includes(response.status) || attempt === 12) {
      throw new Error(`HTTP ${response.status} ${url}: ${body.slice(0, 500)}`);
    }
    await sleep(Math.min(15_000, attempt * 1_500));
  }
  throw new Error(`retry budget exhausted: ${url}`);
}

async function status(address) {
  const response = await request(`${API_URL}/smart-contracts/${address}`);
  return response.json();
}

function standardInput(entry) {
  const args = [
    "verify-contract",
    "--chain",
    String(CHAIN_ID),
    "--compiler-version",
    entry.forgeCompilerVersion ??
      (entry.compilerVersion
        ? entry.compilerVersion.replace(/^v/, "").replace(/\+commit\..*$/, "")
        : "0.8.28"),
    "--show-standard-json-input",
  ];
  for (const library of entry.libraries ?? []) args.push("--libraries", library);
  args.push(entry.address, `${entry.source}:${entry.contract}`);
  return execFileSync("forge", args, {
    cwd: path.join(worktree, entry.package),
    encoding: "utf8",
    maxBuffer: 128 * 1024 * 1024,
  });
}

async function submit(entry) {
  const current = await status(entry.address);
  if (
    current.is_verified === true &&
    current.creation_status === "success" &&
    current.is_changed_bytecode === false
  ) {
    return { action: "already_verified", status: current };
  }

  const form = new FormData();
  form.set("compiler_version", entry.compilerVersion ?? COMPILER_VERSION);
  form.set("contract_name", entry.contract);
  form.set("autodetect_constructor_args", "true");
  form.set("license_type", entry.license ?? "apache_2_0");
  form.set(
    "files[0]",
    new Blob([standardInput(entry)], { type: "application/json" }),
    "standard-input.json",
  );
  const response = await request(
    `${API_URL}/smart-contracts/${entry.address}/verification/via/standard-input`,
    { method: "POST", body: form },
  );
  const submission = await response.json().catch(() => ({}));

  for (let poll = 1; poll <= 40; poll += 1) {
    await sleep(Math.min(10_000, poll * 1_000));
    const currentStatus = await status(entry.address);
    if (
      currentStatus.is_verified === true &&
      currentStatus.creation_status === "success" &&
      currentStatus.is_changed_bytecode === false
    ) {
      return { action: "submitted", submission, status: currentStatus };
    }
    if (currentStatus.creation_status === "failed") {
      throw new Error(
        `${entry.address} ${entry.contract}: verification failed: ` +
          JSON.stringify(currentStatus),
      );
    }
  }
  throw new Error(`${entry.address} ${entry.contract}: verification timed out`);
}

const results = [];
for (const [index, entry] of input.contracts.entries()) {
  process.stdout.write(
    `[${index + 1}/${input.contracts.length}] ${entry.contract} ${entry.address} ... `,
  );
  try {
    const result = await submit(entry);
    results.push({ ...entry, ...result });
    console.log(result.action);
  } catch (error) {
    results.push({ ...entry, action: "failed", error: String(error) });
    await writeFile(
      outputPath,
      `${JSON.stringify({ ...input, verifiedAt: new Date().toISOString(), results }, null, 2)}\n`,
    );
    throw error;
  }
  await writeFile(
    outputPath,
    `${JSON.stringify({ ...input, verifiedAt: new Date().toISOString(), results }, null, 2)}\n`,
  );
}

console.log(`verified ${results.length} contract${results.length === 1 ? "" : "s"}`);
