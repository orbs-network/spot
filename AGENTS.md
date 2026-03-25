# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

## Canonical Surfaces

`skills/advanced-swap-orders/` is the canonical AI-agent bundle.

Within that bundle:

1. `SKILL.md` is the human and agent entrypoint.
2. `manifest.json` is the machine-readable companion.
3. `scripts/order.js` is the canonical execution surface.

Keep the canonical skill slug stable as `advanced-swap-orders`.

Use `Spot Advanced Swap Orders` as the human-facing display title for the skill, MCP, and hosted distribution surfaces.

The repository `README.md` is the exception and may use broader protocol-level branding.

Keep `skills/advanced-swap-orders/manifest.json` as the source of truth for the display title and description used by derived MCP metadata.

Optimize retrieval with frontmatter `description` and opening text, not by renaming the skill slug.

## Sync Rules

When changing behavior, docs, packaging, or metadata that affects agent or MCP consumption, update all affected surfaces in the same change.

This commonly includes `skills/`, `README.md`, `index.html`, `package.json`, `mcp/`, and derived metadata.

## MCP Metadata

Keep the MCP adapter thin and delegate to `skills/advanced-swap-orders/scripts/order.js`.

Treat `package.json` and `skills/advanced-swap-orders/manifest.json` as the MCP metadata source of truth.

Derive `server.json` via `node ./script/sync-mcp.mjs`; do not hand-maintain duplicate fields there.

The canonical MCP server name is `io.github.orbs-network/spot`.

The canonical npm package name is `@orbs-network/spot`.

The canonical npm bin name is `spot-mcp`.

Keep MCP runtime dependency versions pinned to specific versions unless explicitly asked to relax them.

## Build Requirement

Run `npm run build` after every change made in the repo.

Treat that build as the normal sync boundary for derived MCP metadata.

## QA Workflow

When the user asks for `qa`,
use the repo-local `skills/advanced-swap-orders/` bundle as the primary and preferred source of truth for planning and execution.

Honor user scope modifiers such as `just ethereum`;
otherwise run on all supported chains in parallel.

The intended flow is:

1. Open one 2-chunk stop-loss order with a very high trigger so it is effectively immediate.
2. Use that order to swap from native exposure into USDC for about `$10` per chain.
3. Then open a second 2-chunk take-profit order with a very low trigger so it is effectively immediate after its delay elapses.
4. Use that second order to swap back from USDC into native exposure with a 5 minute delay before it can start.

1. Start at `skills/advanced-swap-orders/SKILL.md` and follow the bundle references progressively.
2. Use only the skill bundle, `cast`, `jq`, and env unless the bundle is insufficient.
3. Keep the intent description above at the user level; exact parameter names, token handling, wrapping steps, chunk sizing, and trigger encoding should come from the skill bundle.
4. If you must rely on repo surfaces outside the skill bundle, explicitly report that as a skill gap.
5. Execute the full round trip implied by the user request and poll every 5 seconds until each order reaches a final state.
6. In the result, report the choices made.
7. In the result, report which skill files justified those choices.
8. In the result, report whether the skill bundle alone was sufficient.
9. In the result, report any ambiguity, missing guidance, or misleading guidance encountered.

A `qa` run passes only if:

1. The requested E2E flow completes.
2. The agent can explain its decisions from the skill bundle without unreported fallback.
