# Research Plan

1. Check Robinhood Chain official connection and contract documentation for chain identity, RPC,
   WETH, and permissionless-network constraints.
2. Read the live Delta builder, factory, position-manager, and candidate-pool state through chain
   4663 and the official Blockscout explorer.
3. Check official Uniswap V3 factory, pool-immutables, position-manager, and liquidity-minting
   documentation for pool identity, custody, tick spacing, deadlines, and slippage requirements.
4. Compare those facts with the existing pooled `MarketMakingSleeve` and determine whether an NFT
   owner can have genuine, isolated pool choice.
