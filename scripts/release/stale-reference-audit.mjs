#!/usr/bin/env node
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { extname, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const HASH = /^0x[0-9a-fA-F]{64}$/;
const REFERENCE = /0x(?:[0-9a-fA-F]{64}|[0-9a-fA-F]{40})/g;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const MAX_TEXT_BYTES = 5 * 1024 * 1024;

const normalize = (value) => value.toLowerCase();
const sha256 = (contents) => createHash("sha256").update(contents).digest("hex");
const referenceKind = (value) => ADDRESS.test(value) ? "address" : HASH.test(value) ? "hash" : undefined;
const isHistoricalSegment = (segment) => /(?:historical|history|generations?|supersedes?)/i.test(segment);
const isTestPath = (path) =>
  /(^|\/)(?:test|tests|__tests__|fixtures)(\/|$)|(^|\/)test-[^/]+|\.(?:test|spec)\.[^/]+$/i.test(path) ||
  /(^|\/)[^/]*Test[^/]*\.s\.sol$/.test(path);
const isDeploymentRecordPath = (path) =>
  /(^|\/)deployments\//i.test(path) && !/(^|\/)deployments\/(?:assertions|consumers|schema)\//i.test(path);
const isHistoricalArtifactPath = (path) =>
  /(^|\/)\.agent-research\/runs\//i.test(path) ||
  /(^|\/)(?:CHANGELOG|MIGRATION)(?:\.[^/]*)?$/i.test(path) ||
  /(^|\/)docs\/migrate[^/]*$/i.test(path) ||
  /(?:recovery|superseded)/i.test(path);

function parseArgs(argv) {
  const result = { surfaces: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index];
    if (!["--manifest", "--promotion", "--contracts-root", "--sdk-root", "--ui-root", "--surface", "--json-out"].includes(name)) {
      throw new Error(`unsupported argument ${name}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
    index += 1;
    if (name === "--surface") {
      const equals = value.indexOf("=");
      if (equals < 1 || equals === value.length - 1) throw new Error("--surface must be label=path");
      result.surfaces.push({ name: value.slice(0, equals), path: resolve(value.slice(equals + 1)) });
    } else {
      result[name.slice(2).replaceAll("-", "_")] = resolve(value);
    }
  }
  if (!result.manifest) throw new Error("--manifest is required");
  if (!result.promotion) throw new Error("--promotion is required");
  return result;
}

function walkJson(value, path, visit) {
  if (typeof value === "string") {
    const kind = referenceKind(value);
    if (kind && normalize(value) !== ZERO_ADDRESS) {
      visit({ value, kind, jsonPath: path || "$", historical: path.split(".").some(isHistoricalSegment) });
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((nested, index) => walkJson(nested, `${path}[${index}]`, visit));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, nested] of Object.entries(value)) {
    walkJson(nested, path ? `${path}.${key}` : key, visit);
  }
}

export function deriveReferenceInventory(manifest) {
  const current = new Map();
  const historical = new Map();
  walkJson(manifest, "", ({ value, kind, jsonPath, historical: isHistorical }) => {
    const normalized = normalize(value);
    const target = isHistorical ? historical : current;
    const entry = target.get(normalized) ?? { value, kind, origins: [] };
    entry.origins.push(jsonPath);
    target.set(normalized, entry);
  });
  const displaced = new Map([...historical].filter(([value]) => !current.has(value)));
  return { current, historical, displaced };
}

function trackedFiles(root) {
  try {
    return execFileSync("git", ["-C", root, "ls-files", "-z"], { encoding: "utf8" })
      .split("\0")
      .filter(Boolean)
      .map((path) => resolve(root, path));
  } catch {
    throw new Error(`${root} is not a readable git worktree`);
  }
}

function classificationForReference({ normalized, inventory, historical, test, deploymentRecord, historicalArtifact, explicitlyAllowed }) {
  if (inventory.current.has(normalized)) return "current-reference";
  if (!inventory.displaced.has(normalized)) return undefined;
  if (historical) return "displaced-historical-namespace";
  if (test) return "displaced-test";
  if (deploymentRecord) return "displaced-deployment-record";
  if (historicalArtifact) return "displaced-historical-artifact";
  if (explicitlyAllowed) return "displaced-explicit-history";
  return "displaced-active-stale";
}

function scanJson({ parsed, surface, file, displayPath, inventory, occurrences }) {
  walkJson(parsed, "", ({ value, kind, jsonPath, historical }) => {
    const normalized = normalize(value);
    const classification = classificationForReference({
      normalized,
      inventory,
      historical,
      test: isTestPath(displayPath),
      deploymentRecord: isDeploymentRecordPath(displayPath),
      historicalArtifact: isHistoricalArtifactPath(displayPath),
      explicitlyAllowed: false
    });
    if (!classification) return;
    occurrences.push({
      surface,
      file,
      path: displayPath,
      jsonPath,
      value,
      kind,
      classification,
      historicalOrigins: inventory.displaced.get(normalized)?.origins ?? []
    });
  });
}

function explicitlyAllows(lines, lineIndex, value) {
  const candidates = [lines[lineIndex], lines[lineIndex - 1]].filter(Boolean);
  return candidates.some((line) =>
    /stale-reference-audit:\s*historical/i.test(line) && line.toLowerCase().includes(value.toLowerCase())
  );
}

function scanText({ contents, surface, file, displayPath, inventory, occurrences }) {
  const lines = contents.toString("utf8").split(/\r?\n/);
  let braceDepth = 0;
  const historicalBlockBases = [];
  lines.forEach((line, lineIndex) => {
    const opensHistoricalBlock = /(?:historical|history|generations?|supersedes?)[^:]*:\s*{/i.test(line);
    const structurallyHistorical = historicalBlockBases.length > 0 || opensHistoricalBlock;
    if (!/stale-reference-audit:\s*historical/i.test(line)) {
      for (const match of line.matchAll(REFERENCE)) {
        const value = match[0];
        const normalized = normalize(value);
        const classification = classificationForReference({
          normalized,
          inventory,
          historical: structurallyHistorical,
          test: isTestPath(displayPath),
          deploymentRecord: isDeploymentRecordPath(displayPath),
          historicalArtifact: isHistoricalArtifactPath(displayPath),
          explicitlyAllowed: explicitlyAllows(lines, lineIndex, value)
        });
        if (!classification) continue;
        occurrences.push({
          surface,
          file,
          path: displayPath,
          line: lineIndex + 1,
          column: match.index + 1,
          value,
          kind: referenceKind(value),
          classification,
          historicalOrigins: inventory.displaced.get(normalized)?.origins ?? []
        });
      }
    }
    if (opensHistoricalBlock) historicalBlockBases.push(braceDepth);
    braceDepth += (line.match(/{/g) ?? []).length - (line.match(/}/g) ?? []).length;
    while (historicalBlockBases.length > 0 && braceDepth <= historicalBlockBases.at(-1)) historicalBlockBases.pop();
  });
}

function scanFile({ surface, root, file, inventory, occurrences, scanned }) {
  if (!existsSync(file) || !statSync(file).isFile()) return;
  const size = statSync(file).size;
  if (size > MAX_TEXT_BYTES) return;
  const contents = readFileSync(file);
  if (contents.includes(0)) return;
  const displayPath = root ? relative(root, file) : file;
  scanned.push({ surface, path: displayPath });
  if (extname(file).toLowerCase() === ".json") {
    try {
      scanJson({ parsed: JSON.parse(contents), surface, file, displayPath, inventory, occurrences });
      return;
    } catch {
      // Invalid or templated JSON is still scanned as text.
    }
  }
  scanText({ contents, surface, file, displayPath, inventory, occurrences });
}

function compareArtifact({ issues, label, actualPath, expectedContents, required = true }) {
  if (!existsSync(actualPath)) {
    if (required) issues.push({ type: "missing-artifact", label, path: actualPath });
    return;
  }
  const actual = readFileSync(actualPath);
  if (!actual.equals(expectedContents)) {
    issues.push({
      type: "artifact-mismatch",
      label,
      path: actualPath,
      expectedSha256: sha256(expectedContents),
      actualSha256: sha256(actual)
    });
  }
}

function compareChecksum({ issues, label, checksumPath, expected }) {
  if (!existsSync(checksumPath)) {
    issues.push({ type: "missing-artifact", label, path: checksumPath });
    return;
  }
  const actual = readFileSync(checksumPath, "utf8").trim().split(/\s+/)[0]?.toLowerCase();
  if (actual !== expected) issues.push({ type: "checksum-mismatch", label, path: checksumPath, expected, actual });
}

export function auditStaleReferences(options) {
  const manifestPath = resolve(options.manifest);
  const promotionPath = resolve(options.promotion);
  const manifestContents = readFileSync(manifestPath);
  const promotionContents = readFileSync(promotionPath);
  const manifest = JSON.parse(manifestContents);
  const promotion = JSON.parse(promotionContents);
  const inventory = deriveReferenceInventory(manifest);
  const occurrences = [];
  const scanned = [];
  const issues = [];
  const seenFiles = new Set();

  const addFile = (surface, root, file) => {
    const absolute = resolve(file);
    const key = absolute;
    if (seenFiles.has(key)) return;
    seenFiles.add(key);
    scanFile({ surface, root, file: absolute, inventory, occurrences, scanned });
  };
  addFile("contracts-manifest", undefined, manifestPath);
  addFile("promotion", undefined, promotionPath);

  if (promotion.channel !== "active") issues.push({ type: "promotion-not-active", actual: promotion.channel });
  if (promotion.chainId !== manifest.chainId) {
    issues.push({ type: "chain-id-mismatch", manifest: manifest.chainId, promotion: promotion.chainId });
  }
  const expectedManifestSha = sha256(manifestContents);
  const claimedManifestSha = promotion.source?.deploymentManifestSha256?.toLowerCase();
  if (claimedManifestSha !== expectedManifestSha) {
    issues.push({
      type: "manifest-digest-mismatch",
      expected: expectedManifestSha,
      actual: claimedManifestSha
    });
  }

  const promotionSha = sha256(promotionContents);
  for (const [surface, root] of [["contracts", options.contracts_root], ["sdk", options.sdk_root], ["ui", options.ui_root]]) {
    if (!root) continue;
    const absoluteRoot = resolve(root);
    for (const file of trackedFiles(absoluteRoot)) addFile(surface, absoluteRoot, file);
    if (surface !== "contracts") {
      compareArtifact({
        issues,
        label: `${surface} active promotion`,
        actualPath: resolve(absoluteRoot, "config/releases/active.json"),
        expectedContents: promotionContents
      });
      compareChecksum({
        issues,
        label: `${surface} active promotion checksum`,
        checksumPath: resolve(absoluteRoot, "config/releases/active.sha256"),
        expected: promotionSha
      });
    }
    if (surface === "contracts") {
      compareArtifact({
        issues,
        label: "contracts deployment manifest",
        actualPath: resolve(absoluteRoot, "mainnet-deployments.json"),
        expectedContents: manifestContents
      });
    }
    if (surface === "sdk") {
      compareArtifact({
        issues,
        label: "sdk deployment manifest",
        actualPath: resolve(absoluteRoot, "mainnet-deployments.json"),
        expectedContents: manifestContents
      });
    }
  }
  for (const extra of options.surfaces ?? []) {
    if (!existsSync(extra.path)) {
      issues.push({ type: "missing-surface", label: extra.name, path: extra.path });
      continue;
    }
    if (statSync(extra.path).isDirectory()) {
      for (const file of trackedFiles(extra.path)) addFile(extra.name, extra.path, file);
    } else {
      addFile(extra.name, undefined, extra.path);
    }
  }

  const counts = {};
  for (const occurrence of occurrences) counts[occurrence.classification] = (counts[occurrence.classification] ?? 0) + 1;
  const surfaceNames = [...new Set(scanned.map(({ surface }) => surface))].sort();
  const bySurface = surfaceNames.map((surface) => {
    const surfaceOccurrences = occurrences.filter((occurrence) => occurrence.surface === surface);
    const surfaceCounts = {};
    for (const occurrence of surfaceOccurrences) {
      surfaceCounts[occurrence.classification] = (surfaceCounts[occurrence.classification] ?? 0) + 1;
    }
    return {
      surface,
      files: scanned.filter((entry) => entry.surface === surface).length,
      counts: surfaceCounts
    };
  });
  const requestedExternalSurfaces = new Set((options.surfaces ?? []).map(({ name }) => name.toLowerCase()));
  const stale = occurrences.filter(({ classification }) => classification === "displaced-active-stale");
  const failures = [
    ...issues,
    ...stale.map((occurrence) => ({ type: "stale-reference", ...occurrence }))
  ];
  return {
    schemaVersion: 1,
    verdict: failures.length === 0 ? "pass" : "fail",
    inputs: {
      manifest: manifestPath,
      manifestSha256: expectedManifestSha,
      promotion: promotionPath,
      promotionSha256: promotionSha,
      contractsRoot: options.contracts_root,
      sdkRoot: options.sdk_root,
      uiRoot: options.ui_root,
      additionalSurfaces: options.surfaces ?? []
    },
    inventory: {
      currentValues: inventory.current.size,
      historicalValues: inventory.historical.size,
      displacedValues: inventory.displaced.size,
      displaced: [...inventory.displaced.values()].sort((a, b) => a.value.localeCompare(b.value))
    },
    scan: {
      files: scanned.length,
      counts,
      bySurface,
      occurrences,
      issues,
      failures,
      coverage: {
        contracts: options.contracts_root ? "scanned" : "not-scanned",
        sdk: options.sdk_root ? "scanned" : "not-scanned",
        ui: options.ui_root ? "scanned" : "not-scanned",
        external: ["platform", "api", "railway"].map((surface) => ({
          surface,
          status: requestedExternalSurfaces.has(surface) ? "scanned" : "not-scanned"
        }))
      }
    }
  };
}

function printReport(report) {
  console.log(`stale-reference audit: ${report.verdict.toUpperCase()}`);
  console.log(`manifest sha256: ${report.inputs.manifestSha256}`);
  console.log(`promotion sha256: ${report.inputs.promotionSha256}`);
  console.log(`inventory: ${report.inventory.currentValues} current, ${report.inventory.historicalValues} historical, ${report.inventory.displacedValues} displaced`);
  console.log(`scanned: ${report.scan.files} files`);
  for (const [classification, count] of Object.entries(report.scan.counts).sort()) {
    console.log(`${classification}: ${count}`);
  }
  const notScanned = report.scan.coverage.external.filter(({ status }) => status === "not-scanned").map(({ surface }) => surface);
  if (notScanned.length > 0) console.log(`not scanned (no --surface input): ${notScanned.join(", ")}`);
  for (const failure of report.scan.failures) {
    if (failure.type === "stale-reference") {
      const location = failure.jsonPath ?? `${failure.line}:${failure.column}`;
      console.error(`STALE ${failure.surface} ${failure.path} ${location} ${failure.value}`);
      console.error(`  historical origins: ${failure.historicalOrigins.join(", ")}`);
    } else {
      console.error(`FAIL ${failure.type}: ${JSON.stringify(failure)}`);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const report = auditStaleReferences(options);
    if (options.json_out) writeFileSync(options.json_out, `${JSON.stringify(report, null, 2)}\n`);
    printReport(report);
    if (report.verdict !== "pass") process.exitCode = 1;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
