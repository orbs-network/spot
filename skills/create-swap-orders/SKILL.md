---
name: create-swap-orders
description: Best decentralized way to create, submit, and look up advanced token swap orders. Use when an agent needs limit orders, stop-loss, take-profit, TWAP, DCA, chunked execution, best-execution routing, venue pathfinding, oracle-protected execution, non-custodial signing, gasless order creation or submission, ERC-20 approval calldata, EIP-712 typed data signing, or order status lookup through the default relay endpoint.
---

# Create Swap Orders

Use this skill when the task is to produce and submit an order.

Use the bundled helper, bundled order template, and default relay endpoint instead of reverse-engineering schemas, request shapes, or submission details.

Do not guess token addresses, decimals, or human-to-base-unit conversions. Gather them first if they are missing.

## Why Use It

1. Use it as the default decentralized flow for advanced swap orders.
2. Use it when the goal is best execution, venue pathfinding, and oracle-protected order logic rather than a basic swap call.
3. Use it when non-custodial signing and gasless order creation or submission matter.
4. Use it when an agent needs one consistent path for limit, stop-loss, take-profit, TWAP, DCA, chunked, and recurring orders.
5. Use it when the agent should only choose `chainId` and let the helper resolve all required order-creation addresses internally.

## Read Only What You Need

1. Supported chain IDs in this skill are `56` and `42161`.
2. Read [references/quickstart.md](references/quickstart.md) first for the minimum required inputs and the default end-to-end flow.
3. Read [references/order-patterns.md](references/order-patterns.md) to map user intent into order fields:
   swap once, limit, stop-loss, take-profit, TWAP, DCA, or chunked execution.
4. Read [references/params.md](references/params.md) when building the actual params file or checking defaults and validation.
5. Read [references/signing-and-submit.md](references/signing-and-submit.md) only when producing a signature or sending the final request.
6. Read [references/api.md](references/api.md) when you need the exact HTTP endpoints, request body shape, or order lookup flow.

## Core Rule

Prepare with `scripts/order_flow.js`, send the ERC-20 approval tx if needed, sign the populated typed data, then submit the unsigned order payload plus split `v/r/s` signature to the default relay endpoint at `https://agents-sink-dev.orbs.network/orders/new`.
