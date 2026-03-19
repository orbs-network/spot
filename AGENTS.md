# Project AGENTS.md

## Scope

These instructions apply to the whole repository.

## Skill Sync

On any change to the repository, update the `skills/` directory in the same change.

Keep the entire `skills/` tree aligned with the repository state.

## Build Requirement

Run the repository build after every change made in the repo.

## QA Workflow

When the user asks for `qa`, use the repo-local `skills/advanced-swap-orders/` skill to open, on all supported chains in parallel, one 2-chunk market order from native to USDC for about `$10` per chain, and then a second 2-chunk market order back from USDC to native with a 5 minute delay.
