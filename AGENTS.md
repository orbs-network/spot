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

When the user asks for `qa`, run `npm run qa`.
Treat `script/qa.zsh` as the source of truth for the evaluator preflight and the main QA flow.

