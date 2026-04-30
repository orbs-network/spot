# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

## Canonical Surfaces

The self-contained `skill/` package is the canonical AI-agent bundle.

Within that bundle:

1. `skill/SKILL.md` is the human and agent entrypoint and carries the inline machine-readable skill metadata.
2. `skill/SKILL.md` and the bundled markdown references are the canonical execution surface for the published skill.

Keep the canonical skill slug stable as `spot-advanced-swap-orders`.

Use `Spot Advanced Swap Orders` as the human-facing display title for the skill and hosted distribution surfaces.

The repository `README.md` is the exception and may use broader protocol-level branding.

Keep `skill/SKILL.md` and `config.json` as the sync inputs for the inline metadata consumed by the self-contained skill package.

Optimize retrieval with frontmatter `description` and opening text before changing the skill slug again.

## Sync Rules

When changing behavior, docs, packaging, or metadata that affects agent consumption, update all affected surfaces in the same change.

This commonly includes `skill/SKILL.md`, `config.json`, `skill/`, `README.md`, `index.html`, `package.json`, and derived metadata.

The canonical skill npm package name is `@orbs-network/spot-skill`.

## Build Requirement

Run `npm run build` after every change made in the repo.

Treat that build as the normal sync boundary for derived skill metadata.

## QA Workflow

When the user asks for `qa`:

1. Run `./script/qa-security.zsh` and format the result with emojis.
2. Include the `qa-security` result as a single emoji-prefixed line in the final report whenever `qa-security` ran during the task, with verdict, confidence, and summary.
3. Treat `qa` as a local dev task that validates full skill inference from the bundled skill docs, except `qa mcp` validates inference from MCP-exposed surfaces only.
4. When the user asks for `qa mcp`, use only the MCP surface for Spot order preparation, relay submission, relay queries, and order-state polling.
5. In `qa mcp`, do not read local skill files, bundled markdown references, helper scripts, package metadata, generated artifacts, or repository docs to infer Spot order behavior.
6. In `qa mcp`, it is acceptable to read any skill docs, references, schemas, examples, metadata, or guidance exposed through the MCP surface.
7. In `qa mcp`, use non-MCP local tools only for generic shell orchestration, chain context, signer-managed EVM transactions, token balances, token metadata, wrapping, approvals, exact amount math, and formatting.
8. The default `qa` flow is two sequential TWAP orders, not one mixed order or a single-shot market order.
9. Unless the user overrides scope or shape, place a first order that is a 2-chunk stop-loss from wrapped native to USDC, wait for that order to reach a final state, then place a second order that is a 2-chunk take-profit from USDC back to native.
10. For each default order, size `input.maxAmount` to about `$10` of that leg's input token, use exactly 2 equal chunks so `input.amount = input.maxAmount / 2` is about `$5` per chunk, and set `epoch = 60`.
11. For the default stop-loss leg, set `output.triggerLower` to effectively infinite output-token units so the order is immediately eligible for QA, and set `output.triggerUpper = 0`.
12. For the default take-profit leg, set `output.triggerUpper = 1` wei so the order is immediately eligible for QA, and set `output.triggerLower = 0`.
13. Unless the user overrides tokens, use wrapped native input and USDC output on the first order, then USDC input and native output on the second order, on each supported chain.
14. Use the `$chain` skill and its environment for local EVM context, signer-managed Foundry execution, address resolution, balances, token metadata, wrapping, approvals, and transaction sending.
15. Do not use helper surfaces unless the user explicitly asks to test those surfaces.
16. If the skill bundle is insufficient, report the gap instead of falling back silently.
17. Do not query, reference, or use any orders from before this run as examples for any purpose.
18. Honor user scope modifiers such as `just ethereum`; otherwise run on all supported chains in parallel.
19. Do not probe a chain first; run the supported-chain set in parallel once.
20. For prerequisite onchain transactions such as wrap or approve, fan out across chains with `parallel`.
21. In `qa`, when approval is needed, always use a standing max approval such as `approve(..., maxUint256)` rather than an exact `input.maxAmount` approval.
22. In `qa`, do not send approval-reset or zero-allowance cleanup transactions before, between, or after the default order legs unless the user explicitly asks for them.
23. Do not use `cast send --async` in `qa`; each branch should surface the tx hash and final receipt directly so retries remain unambiguous.
24. Do not use zsh arithmetic for wei or token-amount sizing in `qa`.
25. Use a safer exact tool such as `bc` or `cast` for amount math.
26. Execute the intended two-order flow, poll every 5 seconds until each order reaches a final state.
27. Report a table with the run summary, choices, skill files, sufficiency, ambiguity, any retries or inline fixes or double takes taken, and final order states.
28. A `qa` run passes only if both requested E2E orders complete and you can explain decisions from the active QA surface without unreported fallback.
