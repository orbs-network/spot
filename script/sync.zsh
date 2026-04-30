#!/usr/bin/env zsh
set -euo pipefail

root="${0:A:h:h}"
pkg="$root/package.json"
deploy="$root/config.json"
readme="$root/README.md"
skill="$root/skill/SKILL.md"
skill_pkg="$root/skill/package.json"
skill_readme="$root/skill/README.md"
template_skeleton="$root/script/input/repermit.skeleton.json"
example_specs="$root/script/input/examples.json"
template="$root/skill/assets/repermit.template.json"
examples="$root/skill/references/examples.md"

repo="https://github.com/orbs-network/spot"
branch="master"
skill_package="@orbs-network/spot-skill"
mock_adapter="0x9999999999999999999999999999999999999999"

config_text="$(
  awk '
  /^```json$/ && seen { inside = 1; next }
  /^```$/ && inside { exit }
  inside { print }
  /^## Config$/ { seen = 1 }
  ' "$skill" |
  jq --slurpfile deploy "$deploy" '
  .runtime.chains |= with_entries(
    .value.adapter = (
      $deploy[0][.key].dex.agent.adapter //
      ($deploy[0][.key].dex | to_entries | sort_by(.key)[0].value.adapter)
    )
  )
  '
)"

zmodload zsh/mapfile
config_marker=$'## Config\n\n```json\n'
config_fence=$'\n```'
skill_text="${mapfile[$skill]}"
if [[ "$skill_text" != *"$config_marker"* ]]; then
  print -u2 "missing config block in $skill"
  exit 1
fi
before_config="${skill_text%%$config_marker*}"
config_tail="${skill_text#*$config_marker}"
after_config="${config_tail#*$config_fence}"
mapfile[$skill]="${before_config}${config_marker}${config_text}${config_fence}${after_config}"

description="$(sed -n '2,/^---$/s/^description:[[:space:]]*//p' "$skill" | head -1)"
jq --indent 4 --arg description "$description" '
  {
    name: $ARGS.named.skill_package,
    version,
    description: $description,
    homepage,
    bugs,
    repository: (.repository + { directory: "skill" }),
    license,
    author,
    files: ["*.md", "references", "assets"]
  }
' --arg skill_package "$skill_package" "$pkg" > "$skill_pkg"

repermit="$(jq -r '."*".repermit' "$deploy")"
reactor="$(jq -r '."*".reactor' "$deploy")"
executor="$(jq -r '."*".executor' "$deploy")"
skeleton_slippage="$(jq -r '.message.witness.slippage' "$template_skeleton")"
skeleton_freshness="$(jq -r '.message.witness.freshness' "$template_skeleton")"

render() {
  local source_file="$1"
  shift
  sed "$@" \
    -e "s|<REPERMIT>|$repermit|g" \
    -e "s|<REACTOR>|$reactor|g" \
    -e "s|<EXECUTOR>|$executor|g" \
    -e "s|<REFERRER>|0x0000000000000000000000000000000000000000|g" \
    -e "s|<ADAPTER_USER_DATA>|0x|g" \
    "$source_file"
}

render "$template_skeleton" | jq --indent 4 . > "$template"

render_example() {
  jq --indent 2 -n \
    --argjson spec "$1" \
    --arg reactor "$reactor" \
    --arg executor "$executor" \
    --arg adapter "$mock_adapter" \
    --arg skeleton_slippage "$skeleton_slippage" \
    --arg skeleton_freshness "$skeleton_freshness" '
      if ($spec.epoch != 0 and $spec.epoch <= ($skeleton_freshness | tonumber)) then
        error("example epoch must be 0 or greater than skeleton freshness")
      else
      {
        order: {
          permitted: {
            token: $spec.inputToken,
            amount: $spec.inputMaxAmount
          },
          spender: $reactor,
          nonce: $spec.nonce,
          deadline: $spec.deadline,
          witness: {
            reactor: $reactor,
            executor: $executor,
            exchange: {
              adapter: $adapter,
              ref: "0x0000000000000000000000000000000000000000",
              share: 0,
              data: "0x"
            },
            swapper: $spec.swapper,
            nonce: $spec.nonce,
            start: $spec.start,
            deadline: $spec.deadline,
            chainid: $spec.chainId,
            exclusivity: 0,
            epoch: $spec.epoch,
            slippage: ($skeleton_slippage | tonumber),
            freshness: ($skeleton_freshness | tonumber),
            input: {
              token: $spec.inputToken,
              amount: $spec.inputAmount,
              maxAmount: $spec.inputMaxAmount
            },
            output: {
              token: $spec.outputToken,
              limit: $spec.outputLimit,
              triggerLower: $spec.outputTriggerLower,
              triggerUpper: $spec.outputTriggerUpper,
              recipient: ($spec.outputRecipient // $spec.swapper)
            }
          }
        },
        signature: $spec.signature
      }
      end
    '
}

{
  print '# Examples'
  print
  print 'These are mock final relay payloads.'
  print 'Copy the nearest shape, then replace addresses, amounts, timing, and signature.'
  print 'Mix limit, trigger, and delay fields as needed.'
  for spec in "${(@f)$(jq -c '.[]' "$example_specs")}"; do
    print
    print "## $(jq -r '.title' <<< "$spec")"
    print
    print '```json'
    render_example "$spec"
    print '```'
  done
  print
  print 'If a signer returns `{ "r": "...", "s": "...", "v": "..." }` instead of one full signature string, send that object unchanged in the same `signature` field.'
} > "$examples"

{
  print "<!-- Generated by script/sync.zsh from the repository root README.md. Do not edit directly. -->"
  print
  print '> Auto-synced workspace README for `'"$skill_package"'`. Repo-relative links are rewritten to canonical GitHub URLs.'
  sed -E \
    -e 's#]\(\./([^)]*)/\)#]('"$repo"'/tree/'"$branch"'/\1)#g' \
    -e 's#]\(\./([^)]*)\)#]('"$repo"'/blob/'"$branch"'/\1)#g' \
    "$readme"
} > "$skill_readme"

print "synced skill metadata"
