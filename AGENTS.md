# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

## Canonical Surfaces

Root `SKILL.md`, root `manifest.json`, and `skill/` are the canonical AI-agent bundle.

Within that bundle:

1. Root `SKILL.md` is the human and agent entrypoint.
2. Root `manifest.json` is the machine-readable companion.
3. `skill/scripts/order.js` is the canonical execution surface.

Keep the canonical skill slug stable as `spot-advanced-swap-orders`.

Use `Spot Advanced Swap Orders` as the human-facing display title for the skill, MCP, and hosted distribution surfaces.

The repository `README.md` is the exception and may use broader protocol-level branding.

Keep root `manifest.json` as the source of truth for the display title and description used by derived MCP metadata.

Optimize retrieval with frontmatter `description` and opening text before changing the skill slug again.

## Sync Rules

When changing behavior, docs, packaging, or metadata that affects agent or MCP consumption, update all affected surfaces in the same change.

This commonly includes `SKILL.md`, `manifest.json`, `skill/`, `README.md`, `index.html`, `package.json`, `mcp/`, and derived metadata.

## MCP Metadata

Keep the MCP adapter thin and delegate to `skill/scripts/order.js`.

Treat `package.json` and root `manifest.json` as the MCP metadata source of truth.

Derive `server.json` via `node ./script/sync-mcp.mjs`; do not hand-maintain duplicate fields there.

The canonical MCP server name is `io.github.orbs-network/spot`.

The canonical npm package name is `@orbs-network/spot`.

The canonical npm bin name is `spot-mcp`.

Keep MCP runtime dependency versions pinned to specific versions unless explicitly asked to relax them.

## Build Requirement

Run `npm run build` after every change made in the repo.

Treat that build as the normal sync boundary for derived MCP metadata.

## QA Workflow

When the user asks for `qa`, use [`SKILL.md`](./SKILL.md).
Use $chain skill and env as needed.

Honor user scope modifiers such as `just ethereum`;
otherwise run on all supported chains in parallel.

The intended flow is:

1. Open one 2-chunk stop-loss order that should fill immediately (very high trigger).
2. Use it to swap about `$10` from native exposure into USDC.
3. Open one 2-chunk take-profit order (very low trigger) that swaps back into native exposure after a 5 minute delay.
4. If you need repo surfaces outside the skill bundle, report that as a skill gap.
5. Execute the full round trip and poll every 5 seconds until each order reaches a final state.
6. In the result, report the choices made, the skill files that justified them, whether the bundle was sufficient, and any ambiguity or misleading guidance encountered.

A `qa` run passes only if:

1. The requested E2E flow completes.
2. The agent can explain its decisions from the skill bundle without unreported fallback.
