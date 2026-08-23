#!/usr/bin/env zsh
set -euo pipefail

root="${0:A:h:h}"
plugin="$root/dist/spot"
skill="$plugin/skills/spot-advanced-swap-orders"
version="$(jq -r '.version' "$root/package.json")"

rm -rf "$plugin"
mkdir -p "$plugin/.codex-plugin" "$skill/assets" "$skill/references"
jq --indent 2 --arg version "$version" -n '{
  name: "spot",
  version: $version,
  description: "Gasless non-custodial EVM market and advanced swap orders",
  skills: "./skills/"
}' > "$plugin/.codex-plugin/plugin.json"
cp "$root/skill/SKILL.md" "$skill/"
cp "$root/skill/assets/"* "$skill/assets/"
cp "$root/skill/references/"* "$skill/references/"

print "$plugin"
