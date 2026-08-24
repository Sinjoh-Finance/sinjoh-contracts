# Component: Vercel

**Date checked:** 2026-08-24
**Sources:**
- Documentation index: https://vercel.com/llms.txt
- Deployment environments: https://vercel.com/docs/deployments/environments

## Facts

- Vercel separates Local, Preview, and Production environments.
- Each environment can have distinct environment variables and API keys.
- Preview deployments do not affect the live site; merging the production branch or using `vercel --prod` creates a Production deployment.
- A Production deployment updates Production domains only after it succeeds.

## Assumptions

- The Sinjoh project uses the repository's production branch as the Vercel Production source.

## Inferences

- A passing Preview cannot prove Production Reown, RPC, API, or feature-flag values.
- A remote build cannot consume locally packed SDK artifacts.

## Risks

**MEDIUM — Preview parity can hide missing Production configuration**

Environment-scoped values can differ while source code is identical. Promotion must include an explicit Production configuration audit and rollback plan.

## Resolved questions

**Does a Preview deployment change Production?**

No. Vercel documents Preview as a separate pre-production environment.
