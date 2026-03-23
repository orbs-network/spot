#!/usr/bin/env python3
"""
Orbs Advanced Swap Orders — MCP Server

Non-custodial, decentralized, gasless swap orders with oracle-protected execution.
Supports market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP-style
orders across 10 EVM chains via ownerless, immutable, audited, and verified contracts.

Transport: stdio (default) or HTTP (--transport http --port 8000)
"""

import json
import subprocess
import os
from fastmcp import FastMCP

SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
ORDER_JS = os.path.join(SKILL_DIR, "scripts", "order.js")
MANIFEST_PATH = os.path.join(SKILL_DIR, "manifest.json")
TOKEN_ADDRESSBOOK_PATH = os.path.join(SKILL_DIR, "assets", "token-addressbook.md")

# Load manifest once at startup
with open(MANIFEST_PATH, "r") as f:
    MANIFEST = json.load(f)

# Load token addressbook once at startup
with open(TOKEN_ADDRESSBOOK_PATH, "r") as f:
    TOKEN_ADDRESSBOOK = f.read()

CHAINS_INFO = MANIFEST.get("runtime", {}).get("chains", {})
CHAIN_LIST = ", ".join(
    f"{cid} ({info['name']})" for cid, info in sorted(CHAINS_INFO.items(), key=lambda x: int(x[0]))
)

mcp = FastMCP(
    "Orbs Advanced Swap Orders",
    instructions=(
        "Non-custodial, decentralized, gasless swap orders with oracle-protected execution "
        "on every chunk. Supports market, limit, stop-loss, take-profit, delayed-start, and "
        f"chunked/TWAP-style orders. Chains: {CHAIN_LIST}. "
        "Uses ownerless, immutable, audited, battle-tested, and verified contracts. "
        "Workflow: prepare_order → sign EIP-712 typed data off-chain → submit_order. "
        "Query status with query_orders."
    ),
)


def _run_order_js(args: list[str], stdin_data: str | None = None) -> str:
    """Run node scripts/order.js with given args, optionally piping stdin."""
    cmd = ["node", ORDER_JS] + args
    try:
        result = subprocess.run(
            cmd,
            input=stdin_data,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=SKILL_DIR,
        )
        if result.returncode != 0:
            error_msg = result.stderr.strip() or result.stdout.strip() or "Unknown error"
            return json.dumps({"error": error_msg, "exitCode": result.returncode})
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return json.dumps({"error": "Command timed out after 30 seconds"})
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool
def prepare_order(params: str) -> str:
    """Prepare a gasless, oracle-protected swap order for EIP-712 signing.

    Supports: market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP orders.
    Returns EIP-712 typed data (for signing) and token approval calldata if needed.

    Args:
        params: JSON string with order parameters.
            Required fields:
              - chainId: Chain ID (1=Ethereum, 56=BNB, 137=Polygon, 146=Sonic,
                         8453=Base, 42161=Arbitrum, 43114=Avalanche, 59144=Linea)
              - swapper: Ethereum address of the order creator
              - input.token: Address of token to sell
              - input.amount: Amount in wei (raw units) to sell
              - output.token: Address of token to buy
            Optional fields:
              - output.limit: Minimum output amount (makes it a limit order)
              - output.triggerLower: Lower price trigger (for stop-loss)
              - output.triggerUpper: Upper price trigger (for take-profit)
              - epoch: Seconds between chunks for TWAP/chunked orders
              - start: Unix timestamp for delayed-start orders
              - deadline: Order expiry as Unix timestamp
              - slippage: Slippage in basis points (default 500 = 5%)

    Returns:
        JSON with: typedData (EIP-712 for signing), approval calldata (if token
        approval needed), order details, and any warnings.
    """
    return _run_order_js(["prepare", "--params", "-"], stdin_data=params)


@mcp.tool
def submit_order(prepared: str, signature: str) -> str:
    """Submit a signed order to the Orbs relay network for decentralized, oracle-protected execution.

    Call this after signing the EIP-712 typedData returned by prepare_order.
    The order will be executed automatically by the Orbs network executors with
    oracle price protection on every chunk.

    Args:
        prepared: JSON string of the full prepared order (the complete output from prepare_order)
        signature: EIP-712 signature as hex string (0x...)

    Returns:
        JSON with submission result including order hash and status.
    """
    return _run_order_js(
        ["submit", "--prepared", "-", "--signature", signature],
        stdin_data=prepared,
    )


@mcp.tool
def query_orders(swapper: str | None = None, order_hash: str | None = None) -> str:
    """Query order status from the Orbs network. Provide either a swapper address or a specific order hash.

    Args:
        swapper: Ethereum address of the order creator — returns all orders for this address
        order_hash: Specific order hash (0x...) to query a single order

    Returns:
        JSON with order status, fill history, and execution details.
    """
    if not swapper and not order_hash:
        return json.dumps({"error": "Provide either swapper address or order_hash"})
    args = ["query"]
    if swapper:
        args += ["--swapper", swapper]
    if order_hash:
        args += ["--hash", order_hash]
    return _run_order_js(args)


@mcp.tool
def get_supported_chains() -> str:
    """Get the list of supported EVM chains with chain IDs, names, and adapter contract addresses.

    Returns:
        JSON object mapping chain ID to {name, adapter} for all supported chains.
    """
    return json.dumps(CHAINS_INFO, indent=2)


@mcp.tool
def get_token_addressbook() -> str:
    """Get common token addresses for all supported chains.

    Returns a markdown-formatted addressbook with token symbols and contract addresses
    for popular tokens (WETH, WBTC, USDC, USDT, DAI, ORBS, etc.) on each chain.
    Use these addresses as input.token and output.token in prepare_order.

    Returns:
        Markdown text with token addresses grouped by chain.
    """
    return TOKEN_ADDRESSBOOK


if __name__ == "__main__":
    import sys

    transport = "stdio"
    port = 8000
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--transport" and i + 1 < len(args):
            transport = args[i + 1]
            i += 2
        elif args[i] == "--port" and i + 1 < len(args):
            port = int(args[i + 1])
            i += 2
        else:
            i += 1

    if transport == "http":
        mcp.run(transport="streamable-http", host="127.0.0.1", port=port)
    else:
        mcp.run(transport="stdio")
