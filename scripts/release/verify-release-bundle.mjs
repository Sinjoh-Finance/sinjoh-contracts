#!/usr/bin/env node
import { resolve } from "node:path";
import { loadReleaseBundle } from "./release-bundle.mjs";

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const repoRoot = resolve(import.meta.dirname, "../..");
const bundle = argument("--bundle");
const releaseId = argument("--release-id");
const chainId = Number(argument("--network"));
if (!bundle) throw new Error("--bundle is required");
if (!releaseId) throw new Error("--release-id is required");
if (![4663, 46630].includes(chainId)) throw new Error("--network must be 4663 or 46630");

const { release } = loadReleaseBundle(bundle, {
  releaseId,
  chainId,
  repoRoot,
});
process.stdout.write(`${release.sourceCommit}\n`);
