# Nordstern Solver Implementation Plan

> **For agentic workers:** Use superpowers:dispatching-parallel-agents only for two or more tasks that can run concurrently without shared files, shared state, or sequential dependencies. Otherwise use superpowers:executing-plans and implement inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Nordstern default adapters on the 18 chains supported by both Nordstern and Spot, then register the verified adapter addresses in `config.json`.

**Architecture:** Treat Nordstern's live `/chains` response as the router source and Spot's `skill/SKILL.md` list as the protocol-chain boundary. Preflight and broadcast one existing `DeployDefaultAdapter` script per chain concurrently without writing shared config, verify each receipt and immutable router, then update `config.json` once from the validated result set.

**Tech Stack:** zsh, jq, GNU parallel, Foundry (`forge`, `cast`), the local `chain` environment, Solidity 0.8.27, npm.

---

### Task 1: Lock the live chain and adapter inputs

**Files:**
- Read: `skill/SKILL.md`
- Read: `src/adapter/DefaultDexAdapter.sol`
- Read: `script/06_DeployDefaultAdapter.s.sol`
- Read: `config.json`
- Test: in-memory zsh and jq assertions only

- [ ] **Step 1: Run the configuration assertion and verify it fails before implementation**

```zsh
selected=(1 10 14 56 130 137 143 146 169 999 1329 5000 8453 42161 43114 59144 80094 747474)
selected_json=$(printf '%s\n' "${selected[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')
jq -e --argjson selected "$selected_json" '
  . as $config
  | all($selected[];
      . as $chain
      | ($config[$chain].adapter.Nordstern // "")
      | test("^0x[0-9a-fA-F]{40}$")
    )
' config.json
```

Expected: exit `1`, because no selected chain has `adapter.Nordstern` yet.

- [ ] **Step 2: Fetch Nordstern's live registry into a private temporary run directory**

```zsh
run_dir=$(mktemp -d)
chmod 700 "$run_dir"
export SPOT_NORDSTERN_RUN_DIR="$run_dir"
curl -sSfL https://api.nordstern.finance/chains > "$run_dir/chains.json"
jq -e 'type == "object"' "$run_dir/chains.json" >/dev/null
```

Expected: `chains.json` is a valid JSON object; it contains no signer material.

- [ ] **Step 3: Validate the exact 18-chain router map**

```zsh
jq -n \
  --slurpfile live "$run_dir/chains.json" \
  --argjson expected '{
    "1":"0xa929c559E5e6537359680F39CB4E3708E1a14dd1",
    "10":"0xa575f37e869e6887564F87c07e2885e08D542C4a",
    "14":"0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d",
    "56":"0x1a3304cBef66de00FbE1548CC4C6585aD22FbCFf",
    "130":"0x3FFc2315A992b01dc4B3f79C8EEa1921091Ee24f",
    "137":"0x99bA7d569EA69671B399A7cC488b687515F7EC23",
    "143":"0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d",
    "146":"0x0a354845411CC1212cfb33Acc6A52Fcd4A80e3Ae",
    "169":"0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d",
    "999":"0x2fF506ed9729580EF8Bf04429614beB1baE5F76D",
    "1329":"0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d",
    "5000":"0x3FFc2315A992b01dc4B3f79C8EEa1921091Ee24f",
    "8453":"0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d",
    "42161":"0x57f96440f1b1cAD53B40A8924BD540b1279A491c",
    "43114":"0xa575f37e869e6887564F87c07e2885e08D542C4a",
    "59144":"0x2fF506ed9729580EF8Bf04429614beB1baE5F76D",
    "80094":"0x3FFc2315A992b01dc4B3f79C8EEa1921091Ee24f",
    "747474":"0xC87De04e2EC1F4282dFF2933A2D58199f688fC3d"
  }' '
  ($live[0]) as $registry
  | all($expected | to_entries[];
      $registry[.key].ChainID == .key
      and ($registry[.key].RouterAddress | ascii_downcase) == (.value | ascii_downcase)
    )
    and all(["196", "1284", "4326"][]; $registry[.] == null)
' >/dev/null
```

Expected: exit `0`. If Nordstern changed a router or chain set, stop and re-evaluate the design rather than silently deploying changed inputs.

- [ ] **Step 4: Confirm the existing adapter behavior is sufficient**

```zsh
forge test --match-contract DefaultDexAdapterTest
```

Expected: `5 passed, 0 failed`; the tests cover router pinning, direct approval, allowance cleanup, USDT-like tokens, and router-call failures.

### Task 2: Preflight every chain without broadcasting

**Files:**
- Read: `config.json`
- Read: `script/06_DeployDefaultAdapter.s.sol`
- Create: temporary files under `$SPOT_NORDSTERN_RUN_DIR/preflight/` only
- Test: per-chain router bytecode, signer balance, simulation, and expected CREATE2 address checks

- [ ] **Step 1: Confirm tools and signer inputs without printing secrets**

```zsh
for tool_name in cast forge jq parallel; do
  command -v "$tool_name" >/dev/null || { print -r -- "missing:$tool_name"; return 1; }
done
for env_name in ETH_FROM ETH_KEYSTORE ETH_PASSWORD; do
  [[ -n ${(P)env_name:-} ]] && print -r -- "$env_name=set" || print -r -- "$env_name=unset"
done
```

Expected: all four tools exist. Activate the chain-managed signer before concluding any signer variable is unavailable.

- [ ] **Step 2: Verify every Nordstern router has bytecode in parallel**

```zsh
mkdir -p "$run_dir/preflight"
export SPOT_NORDSTERN_REGISTRY="$run_dir/chains.json"
parallel --tag zsh -lc '
  chain "$1" >/dev/null
  router=$(jq -r --arg chain_id "$1" ".[\$chain_id].RouterAddress" "$SPOT_NORDSTERN_REGISTRY")
  code=$(cast code "$router")
  [[ -n $code && $code != 0x ]]
' _ {} ::: "${selected[@]}" > "$run_dir/preflight/router-code.log"
```

Expected: all 18 jobs exit `0`; no router returns empty bytecode.

- [ ] **Step 3: Dry-run the deployment script on all chains in parallel**

```zsh
salt=$(cast keccak Nordstern)
export SPOT_NORDSTERN_SALT="$salt"
parallel --tag zsh -lc '
  set -euo pipefail
  chain "$1" >/dev/null
  dev true >/dev/null
  router=$(jq -r --arg chain_id "$1" ".[\$chain_id].RouterAddress" "$SPOT_NORDSTERN_REGISTRY")
  load -u -c "$1" config.json env SALT="$SPOT_NORDSTERN_SALT" ROUTER="$router" \
    forge script DeployDefaultAdapter --json > "$SPOT_NORDSTERN_RUN_DIR/preflight/$1.json"
' _ {} ::: "${selected[@]}"
```

Expected: 18 successful simulations, each returning a nonzero adapter address. No transaction is broadcast.

- [ ] **Step 4: Record the public write summary before broadcasting**

For every chain, report the chain ID/name, public sender, Nordstern router, expected adapter address, zero native value, gas estimate, and the reason `Deploy Nordstern DefaultDexAdapter`. Never print RPC URLs, keys, keystore contents, or password paths.

Expected: exactly 18 bounded contract-creation actions with `SALT = keccak256("Nordstern")` and no token transfer.

### Task 3: Broadcast all 18 deployments concurrently

**Files:**
- Read: `script/06_DeployDefaultAdapter.s.sol`
- Create: temporary files under `$SPOT_NORDSTERN_RUN_DIR/deploy/` only
- Test: final receipts, bytecode, and immutable-router checks

- [ ] **Step 1: Broadcast one deployment branch per chain with isolated logs**

```zsh
mkdir -p "$run_dir/deploy"
parallel --tag zsh -lc '
  set -euo pipefail
  chain "$1" >/dev/null
  dev true >/dev/null
  router=$(jq -r --arg chain_id "$1" ".[\$chain_id].RouterAddress" "$SPOT_NORDSTERN_REGISTRY")
  load -u -c "$1" config.json env SALT="$SPOT_NORDSTERN_SALT" ROUTER="$router" \
    forge script DeployDefaultAdapter --broadcast --json \
    > "$SPOT_NORDSTERN_RUN_DIR/deploy/$1.log" 2>&1
' _ {} ::: "${selected[@]}"
```

Expected: GNU parallel exits `0`. Foundry waits for each receipt; do not use `cast send --async` or detach any branch.

- [ ] **Step 2: Extract one result record per chain**

Parse each isolated log into `$run_dir/results.tsv` with these columns: chain ID, router, adapter, transaction hash, receipt status. If the deterministic adapter already existed, record `preexisting` instead of inventing a transaction hash.

Expected: 18 unique chain IDs, 18 valid adapter addresses, and only successful or preexisting statuses.

- [ ] **Step 3: Verify runtime bytecode and immutable routers in parallel**

```zsh
export SPOT_NORDSTERN_RESULTS="$run_dir/results.tsv"
parallel --colsep '\t' --tag zsh -lc '
  set -euo pipefail
  chain "$1" >/dev/null
  code=$(cast code "$3")
  configured_router=$(cast call "$3" "router()(address)")
  [[ -n $code && $code != 0x ]]
  [[ ${(L)configured_router} == ${(L)2} ]]
' _ {1} {2} {3} :::: "$run_dir/results.tsv"
```

Expected: all 18 adapters have bytecode and return the exact Nordstern router for their chain.

- [ ] **Step 4: Contain any failure before config mutation**

If a branch fails, inspect its own log and transaction hash. Retry only when no transaction was submitted or the submitted transaction has a final failed receipt. Do not replace an unknown or pending transaction. Do not edit `config.json` until all 18 result records are verified.

### Task 4: Register the verified adapters

**Files:**
- Modify: `config.json` (`adapter.Nordstern` under chain IDs `1`, `10`, `14`, `56`, `130`, `137`, `143`, `146`, `169`, `999`, `1329`, `5000`, `8453`, `42161`, `43114`, `59144`, `80094`, `747474`)
- Test: in-memory jq assertions, build, and config report

- [ ] **Step 1: Apply one minimal config edit from the verified result set**

Use `apply_patch` to add each adapter address from `$run_dir/results.tsv` as the `Nordstern` value in the corresponding chain's `adapter` object. Do not add `dex.nordstern`, fee contracts, aliases, fallback behavior, or entries for chain IDs `196`, `1284`, or `4326`.

- [ ] **Step 2: Run the required build immediately after the repository change**

```zsh
npm run build
```

Expected: metadata sync succeeds and Foundry builds successfully.

- [ ] **Step 3: Run the original configuration assertion and verify it passes**

```zsh
selected_json=$(printf '%s\n' "${selected[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')
jq -e --argjson selected "$selected_json" '
  . as $config
  | (
      all($selected[];
        . as $chain
        | ($config[$chain].adapter.Nordstern // "")
        | test("^0x[0-9a-fA-F]{40}$")
      )
      and all(["196", "1284", "4326"][];
        . as $chain
        | $config[$chain].adapter.Nordstern? == null
      )
    )
' config.json
```

Expected: exit `0`.

- [ ] **Step 4: Perform the cleanup pass**

Check that only the 18 requested map entries were added, existing solver ordering remains readable, no duplicate `Nordstern` keys exist, and no generated or temporary deployment files are tracked.

- [ ] **Step 5: Commit the config registration**

```zsh
git add config.json
git commit -m '🚀 Add Nordstern adapters across supported chains'
```

Expected: one config-only implementation commit.

### Task 5: Verify the rollout and preserve baseline context

**Files:**
- Read: `config.json`
- Read: `skill/SKILL.md`
- Test: full build, Solidity suite, config validation, git diff, and onchain reads

- [ ] **Step 1: Run the full build and Solidity suite**

```zsh
npm run build
forge test
```

Expected: build succeeds and all 203 baseline Solidity tests pass.

- [ ] **Step 2: Run config validation separately and compare with baseline**

```zsh
./script/config
config_exit=$?
print -r -- "config_exit=$config_exit"
```

Expected: Nordstern appears on all 18 selected chains. Flare and Sei improve from `2/3` to at least `3/3`; Katana improves from `1/3` to `2/3`. The command may remain exit `1` only for the acknowledged pre-existing Moonbeam, X Layer, and Katana coverage gaps.

- [ ] **Step 3: Re-run the 18-chain onchain verification**

Repeat Task 3 Step 3 from the retained private result file.

Expected: all 18 runtime-code and immutable-router checks still pass.

- [ ] **Step 4: Review repository state and requirements**

```zsh
git diff --check
git status --short
git log -4 --oneline
```

Expected: no uncommitted repository changes, no tracked temporary logs, and commits for the design, worktree ignore, plan, and Nordstern config registration.

- [ ] **Step 5: Prepare the final deployment report**

Report all 18 chain IDs/names, Nordstern routers, deployed adapter addresses, transaction hashes or `preexisting`, and final receipt states. Explicitly identify the adapter as `DefaultDexAdapter`, cite the official Nordstern docs and live registry, and distinguish the acknowledged config baseline gaps from deployment success.
