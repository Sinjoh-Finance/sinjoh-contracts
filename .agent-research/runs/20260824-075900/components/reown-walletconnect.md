# Component: Reown AppKit / WalletConnect

**Date checked:** 2026-08-24
**Sources:**
- Documentation index: https://docs.reown.com/llms.txt
- AppKit FAQ and error codes: https://docs.reown.com/appkit/faq

## Facts

- The UI lockfile contains Reown AppKit 1.7.8 transitively through WalletConnect.
- Reown requires the real application origin in the project's allowed domains.
- The official FAQ maps an origin outside the allowlist to APKT002 and an unverified domain to APKT005.
- APKT007 means an invalid project ID, APKT008 means a missing project ID, and APKT010 is rate limiting.

## Assumptions

- Injected-wallet support remains available without a Reown project ID, but QR wallet support does not.

## Inferences

- A Preview wallet smoke test does not prove the Production domain is allowlisted.

## Risks

**HIGH — Production wallet connections depend on external domain configuration**

If `https://app.sinjoh.com` and the chosen Preview/canary origin are absent from Reown's project domains, QR wallet connection fails even with correct application code.

## Resolved questions

**Can the codebase prove the Production domain is allowlisted?**

No. This is dashboard state. Reown's public docs describe the requirement, but the current project configuration is not publicly inspectable.
