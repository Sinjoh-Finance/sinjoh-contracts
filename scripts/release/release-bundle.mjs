import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve, sep } from "node:path";

const commitPattern = /^[0-9a-f]{40}$/;
const checksumPattern = /^([0-9a-f]{64})  (.+)$/;

export function sha256(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

export function loadReleaseBundle(bundlePath, expected = {}) {
  const directory = resolve(bundlePath);
  const releasePath = resolve(directory, "release.json");
  const checksumsPath = resolve(directory, "checksums.sha256");
  if (!existsSync(releasePath) || !existsSync(checksumsPath)) {
    throw new Error("release bundle requires release.json and checksums.sha256");
  }

  const checksumLines = readFileSync(checksumsPath, "utf8").trim().split("\n");
  const checksums = new Map();
  for (const line of checksumLines) {
    const match = checksumPattern.exec(line);
    if (!match) throw new Error(`invalid release checksum line: ${line}`);
    const filePath = resolve(directory, match[2]);
    if (filePath !== directory && !filePath.startsWith(`${directory}${sep}`)) {
      throw new Error(`release checksum escapes bundle: ${match[2]}`);
    }
    if (!existsSync(filePath) || !statSync(filePath).isFile()) {
      throw new Error(`release checksum references missing file: ${match[2]}`);
    }
    if (sha256(readFileSync(filePath)) !== match[1]) {
      throw new Error(`release checksum mismatch: ${match[2]}`);
    }
    checksums.set(match[2], match[1]);
  }
  if (!checksums.has("release.json")) throw new Error("release.json is not checksummed");

  const releaseContents = readFileSync(releasePath);
  const release = JSON.parse(releaseContents);
  if (release.schemaVersion !== 1) throw new Error("unsupported release schema version");
  if (release.sourceTreeClean !== true) throw new Error("release source tree was not clean");
  if (!commitPattern.test(release.sourceCommit)) throw new Error("release source commit is invalid");
  if (expected.releaseId && release.releaseId !== expected.releaseId) throw new Error("release ID mismatch");
  if (expected.chainId && release.chainId !== expected.chainId) throw new Error("release chain mismatch");
  if (expected.network && release.network !== expected.network) throw new Error("release network mismatch");
  if (!Array.isArray(release.artifacts) || release.artifacts.length === 0) {
    throw new Error("release bundle contains no contract artifacts");
  }

  if (expected.repoRoot) {
    const result = execFileSync(
      "git",
      ["merge-base", "--is-ancestor", release.sourceCommit, "HEAD"],
      { cwd: expected.repoRoot, stdio: "ignore" },
    );
    void result;
  }

  return {
    directory,
    release,
    releaseContents,
    releaseManifestSha256: sha256(releaseContents),
  };
}
