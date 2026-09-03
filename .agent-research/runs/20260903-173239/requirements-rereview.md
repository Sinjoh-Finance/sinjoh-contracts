# Requirements re-review

- The threshold mapping is now exact and inclusive; balances below 10,000 $INJOH are ineligible.
- Access cascades downward. The Merkle dataset therefore needs multiple stage leaves for higher-tier
  wallets, not one mutually exclusive classification leaf.
- Wallet caps are stage-local. SeaDrop's default lifetime stat cannot implement that requirement
  without contract-side stage accounting.
- Stage supply boundaries must be cumulative: 3, 33, 333, and 3,333.
- The fee-weight schedule must follow mint order: 1-3 Alpha, 4-33 Prime, 34-333 Premium,
  334-3,333 Standard.
- Immutable decision before root generation: exact start/end time of each stage and the fee BPS
  observed in OpenSea's final configuration.
- Missing external answer: whether OpenSea will publish this collection without an effective public
  stage. If not, the whitelist requirement needs a custom mint page or OpenSea assistance.
