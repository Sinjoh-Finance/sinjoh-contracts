# Contracts v2 SDK

Typed, framework-neutral helpers generated from the exact audited Solidity artifacts.

```ts
import {
  buildLaunchFromPreset,
  encodeGovernanceAction,
  pendingWork,
  projectTreasuryVaultV2Abi,
  validateLaunchConfig,
} from "@sinjoh/contracts-v2-sdk";
```

- `buildLaunchFromPreset` accepts only creator-owned choices and hydrates a complete reviewed
  platform preset. Creator forms never collect adapter, oracle, pool, proof, route, or protocol
  infrastructure fields.
- `predictLaunch` returns stable deterministic addresses without requiring a complete launch.
- `validateLaunchConfig` performs the same full preflight used by `launch` before a wallet prompt.
- `encodeGovernanceAction` creates one `{ target, value, data }` action usable by either governance
  workflow without exposing raw calldata assembly to the UI.
- `projectRecord` discovers the complete project from the Registry.
- `pendingWork` provides one-call status helpers for every module with keeper or recovery work.
- `launchErrorMessage` converts stable Launcher custom-error names into corrective product copy.

Run `npm test` to rebuild the ABIs from Foundry artifacts, type-check the package, and verify the
shared Solidity/TypeScript calldata fixture.
