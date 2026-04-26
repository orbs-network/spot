# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

## Canonical Surfaces

The self-contained `skill/` package is the canonical AI-agent bundle.

Within that bundle:

1. `skill/SKILL.md` is the human and agent entrypoint and carries the inline machine-readable skill metadata.
2. `skill/SKILL.md` and the bundled markdown references are the canonical execution surface for the published skill.

Keep the canonical skill slug stable as `spot-advanced-swap-orders`.

Use `Spot Advanced Swap Orders` as the human-facing display title for the skill, MCP, and hosted distribution surfaces.

The repository `README.md` is the exception and may use broader protocol-level branding.

Keep `skill/SKILL.md` and `config.json` as the sync inputs for the inline metadata consumed by the self-contained skill package.

Optimize retrieval with frontmatter `description` and opening text before changing the skill slug again.

## Sync Rules

When changing behavior, docs, packaging, or metadata that affects agent or MCP consumption, update all affected surfaces in the same change.

This commonly includes `skill/SKILL.md`, `config.json`, `skill/`, `README.md`, `index.html`, `package.json`, `mcp/`, and derived metadata.

## MCP Metadata

Keep the MCP adapter thin and delegate to `mcp/order.js`.

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

When the user asks for `qa`:

1. Run `./script/qa-security.zsh` and format the result with emojis.
2. Include the `qa-security` result as a single emoji-prefixed line in the final report whenever `qa-security` ran during the task, with verdict, confidence, and summary.
3. Treat `qa` as a local dev task that validates full skill inference from the bundled skill docs.
4. The default `qa` flow is two sequential TWAP orders, not one mixed order or a single-shot market order.
5. Unless the user overrides scope or shape, place a first order that is a 2-chunk stop-loss from wrapped native to USDC, wait for that order to reach a final state, then place a second order that is a 2-chunk take-profit from USDC back to native.
6. For each default order, size `input.maxAmount` to about `$10` of that leg's input token, use exactly 2 equal chunks so `input.amount = input.maxAmount / 2` is about `$5` per chunk, and set `epoch = 60`.
7. For the default stop-loss leg, set `output.triggerLower` to effectively infinite output-token units so the order is immediately eligible for QA, and set `output.triggerUpper = 0`.
8. For the default take-profit leg, set `output.triggerUpper = 1` wei so the order is immediately eligible for QA, and set `output.triggerLower = 0`.
9. Unless the user overrides tokens, use wrapped native input and USDC output on the first order, then USDC input and native output on the second order, on each supported chain.
10. Use the `$chain` skill and its environment for local EVM context, signer-managed Foundry execution, address resolution, balances, token metadata, wrapping, approvals, and transaction sending.
11. Do not use `mcp/order.js`, MCP tools, or other repo helper surfaces unless the user explicitly asks to test those surfaces.
12. If the skill bundle is insufficient, report the gap instead of falling back silently.
13. Do not query, reference, or use any orders from before this run as examples for any purpose.
14. Honor user scope modifiers such as `just ethereum`; otherwise run on all supported chains in parallel.
15. Do not probe a chain first; run the supported-chain set in parallel once.
16. For prerequisite onchain transactions such as wrap or approve, fan out across chains with `parallel`.
17. In `qa`, when approval is needed, always use a standing max approval such as `approve(..., maxUint256)` rather than an exact `input.maxAmount` approval.
18. In `qa`, do not send approval-reset or zero-allowance cleanup transactions before, between, or after the default order legs unless the user explicitly asks for them.
19. Do not use `cast send --async` in `qa`; each branch should surface the tx hash and final receipt directly so retries remain unambiguous.
20. Do not use zsh arithmetic for wei or token-amount sizing in `qa`.
21. Use a safer exact tool such as `bc` or `cast` for amount math.
22. Execute the intended two-order flow, poll every 5 seconds until each order reaches a final state.
23. Report a table with the run summary, choices, skill files, sufficiency, ambiguity, any retries or inline fixes or double takes taken, and final order states.
24. A `qa` run passes only if both requested E2E orders complete and you can explain decisions from the skill bundle without unreported fallback.
