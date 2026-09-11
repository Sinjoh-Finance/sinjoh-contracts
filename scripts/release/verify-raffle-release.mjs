#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

/** Compare executable code to the release artifact, allowing only compiler-declared immutables. */
export function runtimeMatchesArtifact(runtime, artifact) {
  const template = artifact.deployedBytecode?.object;
  if (typeof runtime !== "string" || typeof template !== "string") return false;
  const actual = runtime.replace(/^0x/, "").toLowerCase().split("");
  const expected = template.replace(/^0x/, "").toLowerCase().split("");
  if (!actual.length || actual.length !== expected.length) return false;
  for (const references of Object.values(artifact.deployedBytecode.immutableReferences ?? {})) {
    for (const { start, length } of references) {
      if (!Number.isInteger(start) || !Number.isInteger(length) || start < 0 || length <= 0 || (start + length) * 2 > actual.length) return false;
      actual.fill("0", start * 2, (start + length) * 2);
      expected.fill("0", start * 2, (start + length) * 2);
    }
  }
  return actual.join("") === expected.join("");
}

async function main() {
  const arg = (name) => process.argv[process.argv.indexOf(name) + 1];
  for (const name of ["--release-bundle", "--rpc-url", "--secondary-rpc-url"]) {
    if (!process.argv.includes(name)) throw new Error(`${name} is required`);
  }
  const root = resolve(import.meta.dirname, "../..");
  const manifest = JSON.parse(readFileSync(resolve(root, "mainnet-deployments.json"), "utf8"));
  const factory = manifest.currentInfrastructure.raffleFactory;
  const bundle = resolve(arg("--release-bundle"));
  const artifact = (name) => JSON.parse(readFileSync(resolve(bundle, "artifacts/sinjoh-raffle-rewards", `${name}__${name}.json`), "utf8"));
  const factoryArtifact = artifact("SinjohRaffleRewardsFactory");
  const implementationArtifact = artifact("SinjohRaffleRewards");
  for (const [provider, url] of [["primary", arg("--rpc-url")], ["secondary", arg("--secondary-rpc-url")]]) {
    const rpc = async (method, params) => {
      const response = await fetch(url, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) throw new Error(`${provider}: ${method} failed with HTTP ${response.status}`);
      const body = await response.json();
      if (body.error || body.result === undefined) throw new Error(`${provider}: ${method} failed`);
      return body.result;
    };
    if (Number(BigInt(await rpc("eth_chainId", []))) !== 4663) throw new Error(`${provider}: wrong chain`);
    // Use one finalized block for every read on this provider.
    const block = await rpc("eth_getBlockByNumber", ["finalized", false]);
    for (const [label, address, compiled] of [
      ["factory", factory.address, factoryArtifact],
      ["implementation", factory.implementation, implementationArtifact],
    ]) {
      const code = await rpc("eth_getCode", [address, block.number]);
      if (!runtimeMatchesArtifact(code, compiled)) {
        throw new Error(`${provider}: raffle ${label} runtime does not match the release artifact. Deploy the matching generation before promotion.`);
      }
    }
    const implementation = await rpc("eth_call", [{
      to: factory.address,
      data: `0x${factoryArtifact.methodIdentifiers["implementation()"]}`,
    }, block.number]);
    if (implementation.toLowerCase() !== `0x${"0".repeat(24)}${factory.implementation.slice(2).toLowerCase()}`) {
      throw new Error(`${provider}: raffle implementation binding differs from the release manifest`);
    }
    console.log(`${provider}: finalized raffle factory and implementation match the release artifacts`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
