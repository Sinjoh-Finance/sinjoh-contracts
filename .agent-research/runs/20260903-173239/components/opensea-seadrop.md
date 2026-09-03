# OpenSea SeaDrop

Version: unversioned canonical deployment  
Disposition: MISS-unversioned  
Primary sources: https://github.com/ProjectOpenSea/seadrop/blob/main/src/SeaDrop.sol and
https://github.com/ProjectOpenSea/seadrop/blob/main/docs/SeaDropTokenDeployment.md

## Verified facts

- A Merkle leaf is `keccak256(abi.encode(minter, mintParams))`; `MintParams` binds mint price,
  lifetime wallet limit, start/end times, stage index, cumulative stage-supply cap, fee BPS, and
  fee-recipient restriction.
- SeaDrop calls `getMintStats(minter)` before minting. Its wallet-limit check compares the first
  returned value plus quantity to the leaf's wallet limit.
- SeaDrop calls `mintSeaDrop(minter, quantity)` before forwarding proceeds. The callback contains
  neither the leaf nor its price, stage index, or fee BPS.
- For paid mints, SeaDrop holds the gross `msg.value` during the callback, then rounds the platform
  fee down and forwards `msg.value - feeAmount` to the configured creator payout address.
- If `mintPrice == 0`, SeaDrop does not call the creator payout address after minting.
- SeaDrop checks both the token contract's reported maximum supply and the leaf's cumulative
  `maxTokenSupplyForStage` before invoking the mint callback.

## Assumptions and inferences

- Stage-local wallet accounting can be implemented compatibly by returning the current configured
  stage's per-wallet count from `getMintStats`.
- Because payout happens after the callback, the proceeds vault can atomically reject a wrong net
  payout, but a zero-price leaf requires an additional guard during the callback.
- The generic contract should store stage terms supplied by each collection rather than infer them
  from Piggy Banks fee weights.

## Risks

- **CRITICAL — Opaque callback parameters.** The NFT callback cannot directly authenticate the
  Merkle leaf's price, fee, or stage. Accepting arbitrary roots without independent stage and
  proceeds checks can mint an unbacked NFT and leave pending accounting stuck.
- **HIGH — Lifetime wallet stats.** Returning lifetime collection mints prevents an eligible wallet
  from receiving each stage's stated allowance; raising the leaf limit instead lets wallets exceed
  a stage-specific cap.
- **HIGH — Cross-stage batch mint.** Without a stage-local supply ceiling, one transaction can cross
  the boundary and assign later-tier tokens at the earlier tier's terms.
- **MEDIUM — Fee rounding.** Expected creator proceeds must use SeaDrop's exact floor-rounding rule.

## Unresolved

- SeaDrop does not expose the active mint path or leaf parameters to the token callback. Complete
  cryptographic binding of callback behavior to a leaf would require a different callback or a
  collection-controlled mint entry point; this cannot be resolved from the published SeaDrop v1
  interface.
