# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

- Never open an issue on the Spot repository unless the user specifically asks for one.
- When adding a DEX integration, always use the universal adapter type unless the user explicitly specifies another type.
- Supported chains must be explicitly included in config and have all six core contracts plus at least one deployed shared or chain-specific adapter. Keep config and the skill chain list in sync; named solver count is not a prerequisite. Do not restore intentionally removed chains based on existing deployments; Manta is excluded.

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

## Spot Runtime QA

Live relay and taker coverage is a manual AI check during `qa`, or when explicitly requested. Normal testing (`t`, `npm test`, and `test:e2e`) checks contracts, deployments, and oracle coverage; it must not query relay/taker health or require their integration coverage.

1. Use the relay URL from `skill/SKILL.md` to inspect `/health` and `/status`: service health, enabled and fresh block listeners, and registered adapter addresses for the QA chains and integrations.
2. Read the comma-separated `SPOT_TAKER_HEALTH_URLS` from the private environment. If missing or empty, report taker health checking as skipped. Never expose private URLs or invent endpoints.
3. Inspect active takers, recent relay polling, fresh integration loops, and matching chain/refinery/solver-adapter metadata. Use 120 seconds for health, polling, and listener freshness, and 180 seconds for loop freshness; distinguish current errors from historical ones.
4. Before interpreting gaps, compare the live library versions and adapter addresses with current config and remote code in `orbs-network/twap-bidder` and `orbs-network/order-sink`. Account for SAFO/backup/L3 assignments and the health endpoints actually observed. An unobserved loop is not proof that an integration is unsupported or broken.
5. Include a concise runtime diagnosis in the QA report, separating confirmed mismatches, unavailable evidence, and the results of this run's orders. Health checks alone do not prove successful swaps.

## Spot Notion Dashboard

Notion checking is a manual AI task during `qa`, or when explicitly requested. Normal testing (`t`, `npm test`, and `test:e2e`) must not query Notion or evaluate board readiness.

1. Read all pages of the integrations board (`262312ca68a98089837bfaf4ac9ef209`) using `NOTION_API_KEY` from the environment. Keep tokens and private taker endpoints out of committed files and output.
2. Review only SPOT rows and the `Contracts`, `Oracle`, `Takers`, and `Relay` status columns, plus chain membership and solver labels. Compare with current Spot config, deployments, oracle coverage, and live relay/taker observations. TWAP/LH rows and other team readiness columns are outside this review.
3. Distinguish implementation readiness from observed runtime coverage. Check deployed library versions, adapter addresses, and SAFO/backup/L3 taker assignments before interpreting missing loops. Missing health access or partial observations mean unknown coverage, not an automatic downgrade. Honor user-confirmed readiness.
4. Treat integrations absent from config and already marked `Takers: Dead` as resolved. For other stale SPOT rows, propose marking Takers Dead; do not restore removed integrations to config.
5. Report only an ultra-concise numbered fix list: group partners by target status, combine identical column changes, and group stale rows. If access is unavailable, state that the manual review could not be completed. Do not produce a full board table.
6. Review is read-only unless the user has authorized board updates. After authorized updates, read the affected rows again to verify them.

## Build Requirement

Run `npm run build` after every change made in the repo.

Treat that build as the normal sync boundary for derived skill metadata.

## QA Workflow

When the user asks for `skill qa`:

1. Run `npm run test:qa` and format the result with emojis.
2. Include the result as a single emoji-prefixed line in the final report with verdict, confidence, and summary.

When the user asks for `qa`:

Manually review relay/taker coverage and Notion using the Spot Runtime QA and Spot Notion Dashboard instructions above and include the concise findings in the QA report. These are AI reviews, not test commands or automated test side effects.

Before any onchain QA action, run `t` from this repository. It builds and runs all tests, including live Spot/oracle dependency coverage. Stop if any test fails; report the failures before placing orders.

1. Treat `qa` as a local E2E dev task.
2. The default `qa` flow is two sequential TWAP orders, not one mixed order or a single-shot market order.
3. Unless the user overrides scope or shape, place a first order that is a 2-chunk stop-loss from wrapped native to USDC, wait for that order to reach a final state, then place a second order that is a 2-chunk take-profit from USDC back to native.
4. For each default order, size `input.maxAmount` to about `$10` of that leg's input token, use exactly 2 equal chunks so `input.amount = input.maxAmount / 2` is about `$5` per chunk, and set `epoch = 60`.
5. For the default stop-loss leg, set `output.triggerLower` to effectively infinite output-token units so the order is immediately eligible for QA, and set `output.triggerUpper = 0`.
6. For the default take-profit leg, set `output.triggerUpper = 1` wei so the order is immediately eligible for QA, and set `output.triggerLower = 0`.
7. Unless the user overrides tokens, use wrapped native input and USDC output on the first order, then USDC input and native output on the second order, on each supported chain. If USDC is unavailable, use the chain's configured canonical USD stablecoin for both legs; on MegaETH, use USDM; on Robinhood Chain, use USDG.
8. Use the `$chain` skill and its environment for local EVM context, signer-managed Foundry execution, address resolution, balances, token metadata, wrapping, approvals, and transaction sending.
9. Do not use helper surfaces unless the user explicitly asks to test those surfaces.
10. If the skill bundle is insufficient, report the gap instead of falling back silently.
11. Do not query, reference, or use any orders from before this run as examples for any purpose.
12. Honor user scope modifiers such as `just ethereum`; otherwise run on all supported chains in parallel.
13. Do not probe a chain first; run the supported-chain set in parallel once.
14. For prerequisite onchain transactions such as wrap or approve, fan out across chains with `parallel`.
15. In `qa`, when approval is needed, always use a standing max approval such as `approve(..., maxUint256)` rather than an exact `input.maxAmount` approval.
16. In `qa`, do not send approval-reset or zero-allowance cleanup transactions before, between, or after the default order legs unless the user explicitly asks for them.
17. Do not use `cast send --async` in `qa`; each branch should surface the tx hash and final receipt directly so retries remain unambiguous.
18. Do not use zsh arithmetic for wei or token-amount sizing in `qa`.
19. Use a safer exact tool such as `bc` or `cast` for amount math.
20. Execute the intended two-order flow, poll every 5 seconds until each order reaches a final state.
21. Report a table with the run summary, choices, skill files, sufficiency, ambiguity, any retries or inline fixes or double takes taken, and final order states.
22. A `qa` run passes only if both requested E2E orders complete and you can explain decisions from the active QA surface without unreported fallback.
