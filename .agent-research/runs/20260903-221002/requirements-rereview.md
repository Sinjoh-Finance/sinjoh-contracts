# Requirements Re-review

- **Sound:** tier prices, token-ID ranges, openings, and lifetime per-tier wallet limits are explicit.
- **Sound:** later windows do not depend on earlier sellout.
- **OpenSea constraint resolved:** the four allowlist stages are sequential and the one public stage
  is rotated among tiers; no two mint configurations are active at once.
- **Immutable choice:** every public configuration must uniquely match one tier's immutable price,
  wallet cap, fee, and fee-recipient rule.
- **Immutable choice:** the deployed NFT pins one mint policy before the first mint; the existing
  NFT with the old policy cannot be corrected in place.
- **Operational constraint:** OpenSea exposes one public stage, so each public boundary requires an
  NFT-owner transaction; missing a boundary pauses minting rather than discounting another tier.
- **Ownership constraint:** with a 24-hour production timelock and a launch less than 24 hours away,
  either move the launch or keep the launch manager as NFT owner through the initial rotation and
  transfer ownership immediately after Standard is configured.
- **Wrong assumption removed:** an allowed-payer gateway is unnecessary because the configured
  stages never overlap and all minting calls SeaDrop directly.
