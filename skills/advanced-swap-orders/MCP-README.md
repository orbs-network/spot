# MCP Server — Orbs Advanced Swap Orders

Model Context Protocol (MCP) server exposing gasless, oracle-protected swap orders across 10 EVM chains.

## Quick Start

```bash
# stdio transport (for MCP clients like Claude Desktop, Cursor, etc.)
./start-mcp.sh

# HTTP transport (for web-based MCP clients)
./start-mcp.sh http 8000
```

## Tools

| Tool | Description |
|------|-------------|
| `prepare_order` | Prepare a gasless swap order (market, limit, stop-loss, take-profit, TWAP, delayed-start). Returns EIP-712 typed data for signing. |
| `submit_order` | Submit a signed order to the Orbs relay network for oracle-protected execution. |
| `query_orders` | Query order status by swapper address or order hash. |
| `get_supported_chains` | List all supported chains with IDs, names, and adapter addresses. |
| `get_token_addressbook` | Common token addresses (WETH, USDC, USDT, etc.) for every supported chain. |

## Workflow

1. **`get_token_addressbook`** → find token addresses for your chain
2. **`prepare_order`** → get EIP-712 typed data + approval calldata
3. Sign the typed data with the user's wallet (off-chain, gasless)
4. **`submit_order`** → send signed order to Orbs relay network
5. **`query_orders`** → monitor order execution status

## MCP Client Configuration

### Claude Desktop / Cursor (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "orbs-swap": {
      "command": "/path/to/skills/advanced-swap-orders/start-mcp.sh"
    }
  }
}
```

### HTTP Mode (for remote clients)

```json
{
  "mcpServers": {
    "orbs-swap": {
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

## Supported Chains

Ethereum (1), BNB Chain (56), Polygon (137), Sonic (146), Base (8453), Arbitrum One (42161), Avalanche (43114), Linea (59144) — plus Optimism (10) and Mantle (5000) via runtime config.

## Requirements

- Python 3.10+
- `fastmcp` (`pip install fastmcp`)
- Node.js (for `scripts/order.js`)
