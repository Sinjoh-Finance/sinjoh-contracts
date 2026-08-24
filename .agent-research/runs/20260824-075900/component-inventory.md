# Component Inventory

| Component | Type | Version | Role | Confidence |
|---|---|---|---|---|
| @sinjoh/sdk | SDK | 2.1.0 (local target; registry latest 2.0.0) | Builds, validates, encodes, verifies, and simulates the canonical Project V2 launch payload. | High |
| viem | SDK | 2.55.19 | ABI encoding, typed contract calls, prediction, simulation, and transaction readback. | High |
| Robinhood Chain | Blockchain | unversioned (mainnet chain ID 4663) | Target EVM network and RPC surface for launch, reads, and verification. | High |
| Uniswap v4 core | SDK | 1.0.2 | Provides the singleton PoolManager that receives token custody after Pons graduation. | High |
| OpenZeppelin Contracts | SDK | 5.6.1 | ERC-20, Permit, and transfer-hook primitives used by the Project voting token. | High |
| Reown AppKit / WalletConnect | Auth | 1.7.8 (transitive) | Enables QR wallet connections and validates the application origin/project ID. | High |
| Vercel | Infra | unversioned | Builds and hosts isolated Preview and Production environments. | High |
