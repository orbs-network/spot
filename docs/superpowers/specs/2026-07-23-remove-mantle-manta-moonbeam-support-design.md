# Remove Mantle, Manta, and Moonbeam Support

## Goal

Remove Mantle, Manta, and Moonbeam from Spot configuration, canonical agent-facing support metadata, and this repository's owned Notion dashboard field.

## Repository Changes

1. Delete chain ID `5000` (Mantle) from `config.json`.
2. Delete Mantle from `skill/SKILL.md` and renumber the supported-chain list.
3. Verify Manta (`169`) and Moonbeam (`1284`) are already absent from configuration and agent-facing support surfaces.
4. Run the repository sync boundary with `npm run build`, then run tests.

## Notion Changes

Use the `TWAP/Spot Integrations` database (`262312ca68a98089837bfaf4ac9ef209`). Clear only the `Contracts` property for Mantle, Manta, and Moonbeam. Preserve the rows and every other property, including `Oracle`.

## Error Handling

Stop and report any build or test failure. If a Notion row is absent, report it without creating a replacement. If the database schema or property type differs from expectations, inspect it before issuing updates.

## Verification

Search canonical and generated repository surfaces for the three chain names and IDs, confirm the supported-chain list and `config.json` no longer include them, verify build and tests pass, then read the affected Notion rows back to confirm their `Contracts` fields are empty.
