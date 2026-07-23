# Remove Mantle, Manta, and Moonbeam Support Implementation Plan

> **For agentic workers:** Use superpowers:dispatching-parallel-agents only for two or more tasks that can run concurrently without shared files, shared state, or sequential dependencies. Otherwise use superpowers:executing-plans and implement inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Mantle, Manta, and Moonbeam from Spot configuration, agent-facing chain support, and the repository-owned Notion `Contracts` field.

**Architecture:** Treat `config.json` and `skill/SKILL.md` as the repository sync inputs, then regenerate derived package metadata through the existing build. Update Notion only after local verification, limiting the mutation to the owned `Contracts` property.

**Tech Stack:** JSON, Markdown, zsh, jq, npm, Foundry, Notion API

---

### Task 1: Remove Repository Support

**Files:**
- Modify: `config.json`
- Modify: `skill/SKILL.md`

- [ ] **Step 1: Verify the current support check fails**

Run:

```zsh
! jq -e 'has("5000") or has("169") or has("1284")' config.json
```

Expected: non-zero because Mantle chain ID `5000` is still configured.

- [ ] **Step 2: Remove the chain entries**

Delete the complete top-level `config.json` object keyed by `"5000"`. Delete the `Mantle - \`5000\`` supported-chain line from `skill/SKILL.md` and renumber the following entries. Do not change the numeric validation constant `slippage <= 5000` in `skill/references/params.md`.

- [ ] **Step 3: Verify all three chains are absent**

Run:

```zsh
! jq -e 'has("5000") or has("169") or has("1284")' config.json
! rg -ni '\b(mantle|manta|moonbeam)\b' skill README.md index.html server.json package.json config.json
```

Expected: both commands exit zero through negation.

- [ ] **Step 4: Run the required sync boundary**

Run:

```zsh
npm run build
```

Expected: exit zero and `synced skill metadata`.

- [ ] **Step 5: Run repository tests**

Run:

```zsh
npm test
```

Expected: exit zero with all Forge tests passing and configuration validation reporting no issues.

- [ ] **Step 6: Commit the repository removal**

```zsh
git add config.json skill/SKILL.md skill/package.json skill/README.md server.json skill/assets/repermit.template.json skill/references/examples.md
git commit -m "feat: remove mantle chain support"
```

### Task 2: Clear Notion Contracts

**Files:**
- Modify externally: Notion database `262312ca68a98089837bfaf4ac9ef209`

- [ ] **Step 1: Inspect the database schema and audit chain rows**

Query the database without printing `NOTION_API_KEY`. Confirm the exact title property and the `Contracts` property type. Compare every chain row with the canonical `skill/SKILL.md` supported-chain list, identify all unsupported rows, and locate Mantle, Manta, and Moonbeam specifically.

- [ ] **Step 2: Clear only owned values**

Update the located rows so `Contracts` is empty. Do not delete rows and do not mutate `Oracle` or any other property.

- [ ] **Step 3: Verify the external result**

Read all three rows back and confirm each `Contracts` field is empty. Report any absent row without creating one.

### Task 3: Final Verification

**Files:**
- Verify: repository and Notion state

- [ ] **Step 1: Check repository state**

Run:

```zsh
git diff --check
git status --short
```

Expected: no whitespace errors and a clean worktree.

- [ ] **Step 2: Re-run the canonical absence checks**

Run:

```zsh
! jq -e 'has("5000") or has("169") or has("1284")' config.json
! rg -ni '\b(mantle|manta|moonbeam)\b' skill README.md index.html server.json package.json config.json
```

Expected: both commands exit zero through negation.
