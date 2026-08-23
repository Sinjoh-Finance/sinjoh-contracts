#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const promotionPath = argument("--promotion");
const consumerName = argument("--consumer");
if (!promotionPath) throw new Error("--promotion is required");
if (!consumerName) throw new Error("--consumer is required");
const contents = readFileSync(resolve(promotionPath));
const promotion = JSON.parse(contents);
const consumer = promotion.consumers?.[consumerName];
if (!consumer?.environment) throw new Error(`promotion has no environment for ${consumerName}`);
const environment = {
  SINJOH_RELEASE_CHANNEL: promotion.channel,
  SINJOH_RELEASE_ID: promotion.releaseId,
  SINJOH_PROMOTION_SHA256: createHash("sha256").update(contents).digest("hex"),
  ...consumer.environment
};
for (const [name, value] of Object.entries(environment)) console.log(`${name}=${value}`);

