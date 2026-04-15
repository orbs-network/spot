# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

## Canonical Surfaces

The self-contained `skill/` package is the canonical AI-agent bundle.

Within that bundle:

1. `skill/SKILL.md` is the human and agent entrypoint and carries the inline machine-readable skill metadata.
2. `skill/scripts/order.js` is the canonical execution surface.

Keep the canonical skill slug stable as `spot-advanced-swap-orders`.

Use `Spot Advanced Swap Orders` as the human-facing display title for the skill, MCP, and hosted distribution surfaces.

The repository `README.md` is the exception and may use broader protocol-level branding.

Keep `skill/SKILL.md` and `config.json` as the sync inputs for the inline metadata consumed by the self-contained skill package.

Optimize retrieval with frontmatter `description` and opening text before changing the skill slug again.

## Sync Rules

When changing behavior, docs, packaging, or metadata that affects agent or MCP consumption, update all affected surfaces in the same change.

This commonly includes `skill/SKILL.md`, `config.json`, `skill/`, `README.md`, `index.html`, `package.json`, `mcp/`, and derived metadata.

## MCP Metadata

Keep the MCP adapter thin and delegate to `skill/scripts/order.js`.

Treat root `package.json`, `skill/SKILL.md`, `config.json`, and MCP-owned fields in `mcp/package.json` as the sync inputs for MCP metadata.

Derive `skill/` and `mcp/server.json` via `node ./script/sync.mjs`.

Sync only the derived fields in `mcp/package.json`; do not hand-maintain duplicate fields there, but keep MCP-owned fields such as pinned runtime dependencies in that file.

The canonical MCP server name is `io.github.orbs-network/spot`.

The canonical skill npm package name is `@orbs-network/spot-skill`.

The canonical MCP npm package name is `@orbs-network/spot-mcp`.

The canonical npm bin name is `spot-mcp`.

Keep MCP runtime dependency versions pinned to specific versions unless explicitly asked to relax them.

## Build Requirement

Run `npm run build` after every change made in the repo.

Treat that build as the normal sync boundary for derived MCP metadata.

## QA Workflow

When the user asks for `qa`, use [`skill/SKILL.md`](./skill/SKILL.md).
Use chain skill and env.
Do not query, reference, or use any orders from before this run as examples for any purpose.

Honor user scope modifiers such as `just ethereum`;
otherwise run on all supported chains in parallel.
Do not probe a chain first; run the supported-chain set in parallel once.

Do not use zsh arithmetic for wei or token-amount sizing in `qa`.
Use a safer exact tool such as `bc` or `cast` for amount math.

The intended flow is:

1. Open one 2-chunk stop-loss order that should fill immediately (very high trigger).
2. Use it to swap about `$10` from native exposure into USDC.
3. Open one 2-chunk take-profit order (very low trigger) that swaps back into native exposure after a 5 minute delay.
4. If you need repo surfaces outside the skill bundle, report that as a skill gap.
5. Execute the full round trip and poll every 5 seconds until each order reaches a final state.
6. In the result, output a table that summarizes the run, including each chain, chosen tokens and amounts, order hashes and statuses, ending balances and deltas, per-chain costs.
7. In the result, report the choices made, the skill files that justified them, whether the bundle was sufficient, and any ambiguity or misleading guidance encountered.

A `qa` run passes only if:

1. The requested E2E flow completes.
2. The agent can explain its decisions from the skill bundle without unreported fallback.
