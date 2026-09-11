# letscash.fun registry reconciliation

The release preflight found that the canonical contracts registry still named
`0x8E0Ee024c2B547AaE91E6B9b1D3940449B3404F4` as the factory proxy implementation.
The platform's reviewed trust record already recognized the August 29 upgrade:
`Sinjoh-Finance/sinjoh-platform`,
`sinjoh-keeper/config/trust/letscash-factory.json`, review commit
`6a6993dc267b61b4bc460fb2580d401d57b92572`.

This reconciliation uses that reviewed identity plus fresh chain evidence. It
preserves the replaced implementation as historical; it does not change the
upstream proxy or its owner.

| Readback | Verified value |
| --- | --- |
| Proxy | `0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661` |
| Implementation | `0x40250b4C73FC30f8F6ad077744B0124B3f111C28` |
| Runtime keccak256 | `0x606a0bc3d6bac674f4aa28d4cf7b086fd73b84d1ddff69540c6af1128757b353` |
| Deployment transaction | `0x12ded6362aeede695b33cb9c48f9defa41d2b149b7412b27897f813bcbf7fbb5` |
| Deployment block | `48863220` |
| Upgrade transaction | `0x4bc727b39f25e4979724c3a97743a3526c72a2d852a6a1e9b2a3d92f52276755` |
| Upgrade block | `48878257` |
| Safe owner | `0xD2DeFbd13aFF22D6989E8C14B4517Ec308079E91` |
| Safe threshold | `2` |

Both configured RPC providers agree on successful deployment/upgrade receipts,
block hashes, current runtime identity, owner, and Safe threshold. The managed
archive provider also establishes the implementation transition from the prior
address at the upgrade block. The secondary provider rejects historical storage
queries with "metadata is not found"; its current-state and receipt checks are
not described as historical storage verification.

The older research/UI hash beginning `0xc420573f` does not match live deployed
bytecode. The actual hash above matches the existing platform trust record.
Blockscout exposes the deployment transaction and bytecode but no verified source
for this implementation. The registry therefore does not carry forward the old
implementation's source-verification assertion or compiler optimizer metadata.

## Compatibility evidence

- The live letscash.fun launch, router buyback/burn, and treasury fork test passes.
- The production-dependency raffle fork test passes through token launch, fee
  routing, raffle funding, draw, and payout using the successor raffle factory.
- That fixture previously encoded the new raffle tuple against the historical
  factory. It now rehearses a local successor by default and accepts
  `SINJOH_RAFFLE_FACTORY` for certification of the actual deployed replacement.
- The UI's 20 letscash regression tests pass with the corrected default pin.

These fork tests do not replace the wallet-signed public-release canary.
