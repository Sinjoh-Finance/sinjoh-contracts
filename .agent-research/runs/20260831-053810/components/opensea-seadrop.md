# OpenSea SeaDrop

Version: unversioned deployed instance (`0x00005EA00Ac477B1030CE78506496e8C2dE24bf5`)
Disposition: MISS-unversioned

Sources: https://docs.opensea.io/docs/seadrop,
https://docs.opensea.io/docs/deploying-a-seadrop-compatible-contract,
https://docs.opensea.io/docs/part-2-edit-collection-settings,
https://github.com/ProjectOpenSea/seadrop/blob/main/src/SeaDrop.sol,
https://github.com/ProjectOpenSea/seadrop/blob/main/src/lib/SeaDropStructs.sol

## Facts

- Custom SeaDrop-compatible ERC-721 contracts can mint through OpenSea.
- `mintPublic(address,address,address,uint256)` requires exact native value equal to quantity times
  mint price. SeaDrop mints, takes the configured fee, then sends net payout to the configured creator
  payout address.
- Public, token-gated, allowlist, signed-mint, payer, signer, and fee-recipient configuration are
  independently enumerable on the deployed SeaDrop contract.
- OpenSea Studio needs a wallet-controlled NFT owner for setup. YieldBankNFT uses Ownable2Step so the
  setup wallet can transfer control and the timelock can accept it.

## Risks

- **HIGH — Alternate mint path or wrong payout can bypass expected proceeds.** Mitigated by rejecting
  opaque-price allowlists, requiring paid callback-visible stages, and binding every enumerable path
  plus the payout address in the release manifest.
- **HIGH — Ownership transferred before Studio setup makes configuration operationally impossible.**
  Mitigated by explicit `openSeaManager`, exact SDK handoff calldata, and a release check requiring
  final timelock ownership.

No public-source question remains unresolved.
