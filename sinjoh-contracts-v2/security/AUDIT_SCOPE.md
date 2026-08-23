# Contracts v2 independent audit scope

An independent review must cover the complete package, not only core Solidity contracts:

- project identity, automatic-vote token, staking, and PoS NFT;
- Multisig Accounts, Governor, and Timelock under liquid and staked vote sources;
- Treasury, Router, Airdrop, Basket Manager/NFT/Vault, Funding Bands, Raffle, and Liquidity;
- `ERC4626BasketYieldAdapter`, its ownerless deterministic factory, and every production external
  adapter/guard/oracle/randomness implementation selected for release;
- Launcher, deployment engine, CREATE3, creation-code stores, Registry, atomic module wiring, and
  all custody/voting/reward exclusions;
- all unit/fuzz/invariant/integration/fork tests and the nine named `testE2E*` journeys;
- TypeScript ABI generation, launch/config helpers, governance batch encoding, and shared fixtures;
- release preflight, deployment script, runtime/creation-code verification, manifest schema, and
  manifest verifier;
- off-chain Airdrop snapshot/Merkle-sum construction, attestor operations, keeper behavior, and
  published artifacts;
- target-chain opcode support, Uniswap/Permit2 dependencies, selected ERC-4626 vaults, oracle
  freshness/manipulation assumptions, and randomness failure modes.

The audit report must identify its git commit and package tree hash, compiler/settings, external
runtime hashes, fork/testnet evidence versions, unresolved findings by severity, and remediation
commit(s). Production release requires every critical/high finding resolved and independently
verified.
