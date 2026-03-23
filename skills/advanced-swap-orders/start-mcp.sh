#!/usr/bin/env bash
# Start the Orbs Advanced Swap Orders MCP server
# Usage:
#   ./start-mcp.sh              # stdio transport (default, for MCP clients)
#   ./start-mcp.sh http         # HTTP transport on port 8000
#   ./start-mcp.sh http 9000    # HTTP transport on custom port

set -euo pipefail
cd "$(dirname "$0")"

TRANSPORT="${1:-stdio}"
PORT="${2:-8000}"

exec python3 mcp-server.py --transport "$TRANSPORT" --port "$PORT"
