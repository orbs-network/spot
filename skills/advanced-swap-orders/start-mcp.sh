#!/usr/bin/env bash
# Start the Orbs Advanced Swap Orders MCP server (stdio transport)
# Usage:
#   ./start-mcp.sh              # stdio transport (default, for MCP clients)
#   node mcp-server.js          # direct invocation

set -euo pipefail
cd "$(dirname "$0")"

exec node mcp-server.js
