import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const provenance = JSON.parse(readFileSync(new URL("../deployment-provenance.json", import.meta.url)));

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" }).trim();
}

const failures = [];
for (const entry of provenance.deployments) {
  let target;
  try {
    target = git("rev-list", "-n", "1", entry.tag);
  } catch {
    failures.push(`${entry.tag}: missing tag`);
    continue;
  }
  if (target !== entry.filteredCommit) {
    failures.push(`${entry.tag}: expected ${entry.filteredCommit}, found ${target}`);
  }
}

const freeze = git("rev-list", "-n", "1", provenance.freeze.tag);
if (freeze !== provenance.freeze.filteredCommit) {
  failures.push(
    `${provenance.freeze.tag}: expected ${provenance.freeze.filteredCommit}, found ${freeze}`,
  );
}

const total = provenance.deployments.reduce((sum, entry) => sum + entry.runtimeChecks, 0);
if (total !== provenance.runtimeChecksTotal) {
  failures.push(`runtime check total: expected ${provenance.runtimeChecksTotal}, found ${total}`);
}

if (failures.length > 0) {
  console.error("provenance map verification failed:");
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(
  `verified ${provenance.deployments.length} deployment tags and ` +
    `${provenance.runtimeChecksTotal} recorded runtime checks`,
);
