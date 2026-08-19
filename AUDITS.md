# Audit Status

As of 2026-08-18, Sinjoh has not published an independent third-party security
audit covering the complete set of Sinjoh-owned contracts in this repository.

The repository includes self-audit records, adversarial tests, invariant tests,
fork tests, and deployment provenance evidence. Those materials are useful
engineering evidence, but none should be represented as an independent audit.
Audits or reviews of an upstream dependency do not extend automatically to
Sinjoh integrations, configuration, or deployed instances.

The `deploy/mainnet/*` tags establish which source generations reproduce known
deployed runtime bytecode. They do not establish that a deployment is safe,
economically sound, correctly configured, or free of vulnerabilities.

Security researchers should follow [`SECURITY.md`](./SECURITY.md). When an
independent report is commissioned and published, add its scope, commit, date,
auditor, and canonical report link here.
