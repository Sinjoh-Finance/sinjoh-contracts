# Repository Migration

This repository was extracted with `git-filter-repo` from the private
`Sinjoh-Finance/sinjoh-legacy` monorepo.

- Legacy freeze tag: `provenance/pre-reorganization-2026-08-18`
- Original freeze commit: `01628f65885e732ffb7a2d84dce2f4065221e048`
- Filtered freeze commit: `eff7a678fd3a8ba4c34d953d4d84e6f52d86078c`
- Extraction date: 2026-08-18

The extraction retained the Solidity packages, cross-package integration tests,
clear-signing assets, contract-specific reports, deployment registry, and all
surviving deployment tags. Operational services and the TypeScript SDK moved to
their own repositories.

Filtered commit IDs are expected to differ. Source equivalence is established
by the retained path content and the deployment mapping in
`deployment-provenance.json`, not by identical commit hashes.
