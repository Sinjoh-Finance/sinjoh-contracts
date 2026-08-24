# Component: @sinjoh/sdk

**Date checked:** 2026-08-24
**Sources:**
- npm registry metadata and package README: https://registry.npmjs.org/@sinjoh%2fsdk

## Facts

- The UI and local SDK workspace target version 2.1.0.
- The public npm registry's `latest` dist-tag is 2.0.0 and its version map contains no 2.1.0 package.
- The published package describes byte-exact codecs and prepared calls, requires Node.js 22+, and declares viem `>=2.55.10 <3` as a peer.
- Published releases include npm provenance metadata.

## Assumptions

- The intended 2.1.0 release will publish `@sinjoh/sdk`, `@sinjoh/abis`, and `@sinjoh/deployments` together.

## Inferences

- A clean Vercel build cannot resolve the UI's 2.1.0 dependency until all three packages are published.
- Installing local tarballs proves package contents locally but does not make a remote deployment reproducible.

## Risks

**CRITICAL — Required 2.1.0 package is not published**

Preview and Production builds fail before application code runs because npm can resolve only 2.0.0. Publish the coordinated 2.1.0 package set with provenance before treating any deployment as releasable.

## Resolved questions

**Is 2.1.0 available to a clean remote builder?**

No. The registry metadata exposes 2.0.0 as latest and lists no 2.1.0 version.
