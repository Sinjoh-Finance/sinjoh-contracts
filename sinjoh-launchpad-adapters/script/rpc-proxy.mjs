// Local JSON-RPC relay for fork tests.
//
// The public Robinhood RPC rate-limits the many small storage reads a fork test
// makes and starts returning Cloudflare 403 challenge pages. The Alchemy
// endpoint has no such limit but rejects any request without an `Origin` header
// on its allowlist, and forge cannot attach custom headers to --fork-url.
//
// This relay sits in between: forge talks to localhost, the relay adds the
// Origin header and forwards upstream.
//
//   node script/rpc-proxy.mjs &
//   forge test --match-path 'test/PonsV2Mainnet.fork.t.sol' \
//     --fork-url http://127.0.0.1:8545
//
// Reads ROBINHOOD_UPSTREAM_RPC_URL, or NEXT_PUBLIC_ROBINHOOD_RPC_URL from the
// UI's .env.local, and falls back to the public endpoint.

import { createServer } from "node:http";
import { readFileSync } from "node:fs";

const PORT = Number(process.env.RPC_PROXY_PORT ?? 8545);
const ORIGIN = process.env.ROBINHOOD_RPC_ORIGIN ?? "https://app.sinjoh.com";
const PUBLIC_FALLBACK = "https://rpc.mainnet.chain.robinhood.com";

function upstream() {
  if (process.env.ROBINHOOD_UPSTREAM_RPC_URL) {
    return process.env.ROBINHOOD_UPSTREAM_RPC_URL;
  }
  for (const path of [
    "../../../Sinjoh-UI/.env.local",
    "../../Sinjoh-UI/.env.local",
    process.env.SINJOH_UI_ENV ?? "",
  ]) {
    if (!path) continue;
    try {
      const match = readFileSync(new URL(path, import.meta.url), "utf8").match(
        /^NEXT_PUBLIC_ROBINHOOD_RPC_URL=(.+)$/m,
      );
      if (match?.[1]) return match[1].trim();
    } catch {
      // Try the next candidate.
    }
  }
  return PUBLIC_FALLBACK;
}

const target = upstream();
const label = target.replace(/\/v2\/.*$/, "/v2/<key>");

createServer((request, response) => {
  const chunks = [];
  request.on("data", (chunk) => chunks.push(chunk));
  request.on("end", async () => {
    try {
      const upstreamResponse = await fetch(target, {
        method: "POST",
        headers: { "content-type": "application/json", origin: ORIGIN },
        body: Buffer.concat(chunks),
      });
      const body = await upstreamResponse.text();
      response.writeHead(upstreamResponse.status, {
        "content-type": "application/json",
      });
      response.end(body);
    } catch (error) {
      response.writeHead(502, { "content-type": "application/json" });
      response.end(
        JSON.stringify({
          jsonrpc: "2.0",
          id: null,
          error: { code: -32603, message: String(error) },
        }),
      );
    }
  });
}).listen(PORT, "127.0.0.1", () => {
  console.log(`rpc relay :${PORT} -> ${label} (Origin: ${ORIGIN})`);
});
