# Requirements Re-review

- **Missing constraint:** Every mutable upstream commitment used by a production launch must be covered by a current-state fork canary.
- **Wrong assumption:** A healthy RPC does not imply an unchanged third-party launch protocol; the Flap Portal version changed independently.
- **Underspecified:** "Stock raffles work" must include deployment route count readback, token launch, mandatory raffle binding, revenue conversion, round creation, and winner payout.
- **Immutable choice:** Stock rewards and exclusions are constructor configuration and cannot be added after a raffle clone is deployed.
- **Sound:** Launch should fail closed before token creation when routes, guards, upstream configuration, or bind state cannot be proven.
