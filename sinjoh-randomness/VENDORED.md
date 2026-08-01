# Vendored verifier provenance

`src/libraries/VRF.sol` is copied without modification from Chainlink's official
`smartcontractkit/chainlink-evm` repository:

- repository commit: `7a7120887d050120054c6e7b61b8b3ec00ae00a5`
- source path: `contracts/src/v0.8/vrf/VRF.sol`
- SHA-256: `f9c6222edaf4917cd3470b2d518e74bb2fa2d993678e13485ffaddaa43481b09`
- license: MIT, retained in the source header

To review an upgrade, fetch the file at an explicitly chosen upstream commit and
compare both the checksum and full diff. Any change alters the proof verification
rules and requires a fresh cryptographic review and fixture regeneration.
