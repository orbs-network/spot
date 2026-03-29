# MCP Server — Orbs Advanced Swap Orders

Model Context Protocol (MCP) server exposing gasless, oracle-protected swap orders across multiple EVM chains.

**Zero external dependencies** — implements the MCP stdio protocol (JSON-RPC 2.0 over stdin/stdout) directly in Node.js. All configuration is read dynamically from `manifest.json` and `assets/`.

## Quick Start

```bash
# stdio transport (for MCP clients like Claude Desktop, Cursor, etc.)
./start-mcp.sh

# or directly
node mcp-server.js
```

## Tools

| Tool | Description |
|------|-------------|
| `prepare_order` | Prepare a gasless swap order (market, limit, stop-loss, take-profit, TWAP, delayed-start). Returns EIP-712 typed data for signing. |
| `submit_order` | Submit a signed order to the Orbs relay network for oracle-protected execution. |
| `query_orders` | Query order status by swapper address or order hash. |
| `get_supported_chains` | List all supported chains with IDs, names, and adapter addresses (from manifest.json). |
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
      "command": "node",
      "args": ["/path/to/skills/advanced-swap-orders/mcp-server.js"]
    }
  }
}
```

### Via npx (if published)

```json
{
  "mcpServers": {
    "orbs-swap": {
      "command": "npx",
      "args": ["@orbs-network/spot", "mcp"]
    }
  }
}
```

## Architecture

- **Single file**: `mcp-server.js` — no build step, no transpilation
- **Zero dependencies**: implements JSON-RPC 2.0 / MCP protocol inline
- **Config from manifest**: chains, contracts, and metadata read from `manifest.json` at startup
- **Token data from assets**: `assets/token-addressbook.md` loaded and served directly
- **Tool execution**: each tool calls `node scripts/order.js` via `child_process`
- **Transport**: stdio (newline-delimited JSON-RPC 2.0)

## Supported Chains

Dynamically loaded from `manifest.json`. Currently:

Ethereum (1), BNB Chain (56), Polygon (137), Sonic (146), Base (8453), Arbitrum One (42161), Avalanche (43114), Linea (59144).

## Requirements

- Node.js 18+ (uses `node:fs`, `node:path`, `node:child_process`)
- No additional npm packages required
