# Robinhood Chain

Version: chain ID 4663  
Disposition: MISS-unversioned  
Primary source: repository production deployment configuration and live RPC verification at release.

## Verified facts

- The production target in this repository is EVM chain ID 4663.
- The factory pins dependency runtime code hashes, including the configured SeaDrop deployment.

## Assumptions and inferences

- No chain-specific stage logic is required; stage configuration belongs to each collection.

## Risks

- **HIGH — Wrong external deployment.** A correct interface at an unverified SeaDrop address is not
  enough; deployment must pin and verify runtime code on chain ID 4663.
- **LOW — Reorganization.** Release scripts must wait for confirmations and re-verify deployed code.

## Unresolved

- None at implementation time; final deployment addresses and code hashes are release inputs.
