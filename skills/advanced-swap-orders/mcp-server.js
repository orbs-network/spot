#!/usr/bin/env node
'use strict';

/**
 * Orbs Advanced Swap Orders — MCP Server (Node.js, zero dependencies)
 *
 * Implements the Model Context Protocol over stdio transport using
 * JSON-RPC 2.0. No external dependencies — reads all config from
 * manifest.json and assets/ at startup.
 *
 * Usage:
 *   node mcp-server.js
 *   npx @orbs-network/spot mcp
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');

// ── Paths (relative to this file) ──────────────────────────────────────────
const SKILL_DIR = __dirname;
const MANIFEST_PATH = path.join(SKILL_DIR, 'manifest.json');
const TOKEN_ADDRESSBOOK_PATH = path.join(SKILL_DIR, 'assets', 'token-addressbook.md');
const ORDER_JS = path.join(SKILL_DIR, 'scripts', 'order.js');

// ── Load manifest & assets at startup ──────────────────────────────────────
const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
const tokenAddressbook = fs.readFileSync(TOKEN_ADDRESSBOOK_PATH, 'utf8');

const chains = manifest.runtime?.chains ?? {};
const contracts = manifest.runtime?.contracts ?? {};
const chainList = Object.entries(chains)
  .sort((a, b) => Number(a[0]) - Number(b[0]))
  .map(([id, info]) => `${id} (${info.name})`)
  .join(', ');

const chainEnum = Object.keys(chains).sort((a, b) => Number(a) - Number(b));

// ── MCP Protocol Constants ─────────────────────────────────────────────────
const PROTOCOL_VERSION = '2024-11-05';
const SERVER_INFO = {
  name: 'orbs-advanced-swap-orders',
  version: '1.0.0',
};
const SERVER_CAPABILITIES = {
  tools: { listChanged: false },
};

// ── Tool Definitions (dynamically built from manifest) ─────────────────────
const TOOLS = [
  {
    name: 'prepare_order',
    description:
      'Prepare a gasless, oracle-protected swap order for EIP-712 signing. ' +
      'Supports: market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP orders. ' +
      'Returns EIP-712 typed data (for signing) and token approval calldata if needed. ' +
      `Chains: ${chainList}.`,
    inputSchema: {
      type: 'object',
      properties: {
        params: {
          type: 'object',
          description: 'Order parameters object',
          properties: {
            chainId: {
              type: 'string',
              description: `Chain ID. Supported: ${chainList}`,
              enum: chainEnum,
            },
            swapper: {
              type: 'string',
              description: 'Ethereum address of the order creator',
            },
            input: {
              type: 'object',
              description: 'Input (sell) token config',
              properties: {
                token: { type: 'string', description: 'Token address to sell' },
                amount: { type: 'string', description: 'Amount in wei (raw units)' },
              },
              required: ['token', 'amount'],
            },
            output: {
              type: 'object',
              description: 'Output (buy) token config',
              properties: {
                token: { type: 'string', description: 'Token address to buy' },
                limit: { type: 'string', description: 'Minimum output amount (limit order)' },
                triggerLower: { type: 'string', description: 'Lower price trigger (stop-loss)' },
                triggerUpper: { type: 'string', description: 'Upper price trigger (take-profit)' },
              },
              required: ['token'],
            },
            epoch: { type: 'number', description: 'Seconds between chunks (TWAP/chunked orders)' },
            start: { type: 'number', description: 'Unix timestamp for delayed-start orders' },
            deadline: { type: 'number', description: 'Order expiry as Unix timestamp' },
            slippage: { type: 'number', description: 'Slippage in basis points (default 500 = 5%)' },
          },
          required: ['chainId', 'swapper', 'input', 'output'],
        },
      },
      required: ['params'],
    },
  },
  {
    name: 'submit_order',
    description:
      'Submit a signed order to the Orbs relay network for decentralized, oracle-protected execution. ' +
      'Call after signing the EIP-712 typedData returned by prepare_order.',
    inputSchema: {
      type: 'object',
      properties: {
        prepared: {
          type: 'object',
          description: 'Full prepared order object (complete output from prepare_order)',
        },
        signature: {
          type: 'string',
          description: 'EIP-712 signature as hex string (0x...)',
        },
      },
      required: ['prepared', 'signature'],
    },
  },
  {
    name: 'query_orders',
    description:
      'Query order status from the Orbs network. Provide either a swapper address or a specific order hash.',
    inputSchema: {
      type: 'object',
      properties: {
        swapper: {
          type: 'string',
          description: 'Ethereum address — returns all orders for this address',
        },
        order_hash: {
          type: 'string',
          description: 'Specific order hash (0x...) to query a single order',
        },
      },
    },
  },
  {
    name: 'get_supported_chains',
    description:
      'Get the list of supported EVM chains with chain IDs, names, and adapter contract addresses. ' +
      `Currently supported: ${chainList}.`,
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'get_token_addressbook',
    description:
      'Get common token addresses (WETH, WBTC, USDC, USDT, DAI, ORBS, etc.) for all supported chains. ' +
      'Use these addresses as input.token and output.token in prepare_order.',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
];

// ── Helper: run node scripts/order.js ──────────────────────────────────────
function runOrderJs(args, stdinData) {
  return new Promise((resolve, reject) => {
    const child = execFile('node', [ORDER_JS, ...args], {
      cwd: SKILL_DIR,
      timeout: 30000,
      maxBuffer: 1024 * 1024,
    }, (error, stdout, stderr) => {
      if (error) {
        const msg = stderr?.trim() || stdout?.trim() || error.message || 'Unknown error';
        reject(new Error(msg));
      } else {
        resolve(stdout.trim());
      }
    });

    if (stdinData != null) {
      child.stdin.write(typeof stdinData === 'string' ? stdinData : JSON.stringify(stdinData));
      child.stdin.end();
    }
  });
}

// ── Tool Handlers ──────────────────────────────────────────────────────────
const toolHandlers = {
  async prepare_order({ params }) {
    const result = await runOrderJs(
      ['prepare', '--params', '-'],
      typeof params === 'string' ? params : JSON.stringify(params)
    );
    return [{ type: 'text', text: result }];
  },

  async submit_order({ prepared, signature }) {
    const result = await runOrderJs(
      ['submit', '--prepared', '-', '--signature', signature],
      typeof prepared === 'string' ? prepared : JSON.stringify(prepared)
    );
    return [{ type: 'text', text: result }];
  },

  async query_orders({ swapper, order_hash }) {
    if (!swapper && !order_hash) {
      throw new Error('Provide either swapper address or order_hash');
    }
    const args = ['query'];
    if (swapper) args.push('--swapper', swapper);
    if (order_hash) args.push('--hash', order_hash);
    const result = await runOrderJs(args);
    return [{ type: 'text', text: result }];
  },

  async get_supported_chains() {
    return [{ type: 'text', text: JSON.stringify(chains, null, 2) }];
  },

  async get_token_addressbook() {
    return [{ type: 'text', text: tokenAddressbook }];
  },
};

// ── JSON-RPC / MCP Message Handling ────────────────────────────────────────
async function handleMessage(msg) {
  // Type guard: msg must be a non-null object
  if (typeof msg !== 'object' || msg === null) {
    return {
      jsonrpc: '2.0',
      id: null,
      error: { code: -32600, message: 'Invalid Request: expected a JSON object' },
    };
  }

  const { jsonrpc, id, method, params } = msg;

  // Notifications (no id field) — acknowledge silently per JSON-RPC 2.0 spec
  // Note: id === null is a valid request id; only missing id (undefined) is a notification
  if (id === undefined) {
    return null; // no response for notifications
  }

  switch (method) {
    case 'initialize':
      return {
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: SERVER_CAPABILITIES,
          serverInfo: SERVER_INFO,
          instructions:
            'Non-custodial, decentralized, gasless swap orders with oracle-protected execution. ' +
            `Workflow: prepare_order → sign EIP-712 → submit_order. Chains: ${chainList}.`,
        },
      };

    case 'tools/list':
      return {
        jsonrpc: '2.0',
        id,
        result: { tools: TOOLS },
      };

    case 'tools/call': {
      const toolName = params?.name;
      const toolArgs = params?.arguments ?? {};
      const handler = toolHandlers[toolName];

      if (!handler) {
        return {
          jsonrpc: '2.0',
          id,
          result: {
            content: [{ type: 'text', text: `Unknown tool: ${toolName}` }],
            isError: true,
          },
        };
      }

      try {
        const content = await handler(toolArgs);
        return {
          jsonrpc: '2.0',
          id,
          result: { content },
        };
      } catch (err) {
        return {
          jsonrpc: '2.0',
          id,
          result: {
            content: [{ type: 'text', text: `Error: ${err.message}` }],
            isError: true,
          },
        };
      }
    }

    case 'ping':
      return { jsonrpc: '2.0', id, result: {} };

    default:
      return {
        jsonrpc: '2.0',
        id,
        error: { code: -32601, message: `Method not found: ${method}` },
      };
  }
}

// ── stdio Transport ────────────────────────────────────────────────────────
function startStdioTransport() {
  let buffer = '';
  const messageQueue = [];
  let processing = false;

  async function processQueue() {
    if (processing) return;
    processing = true;
    while (messageQueue.length > 0) {
      const msg = messageQueue.shift();
      try {
        const response = await handleMessage(msg);
        if (response) {
          process.stdout.write(JSON.stringify(response) + '\n');
        }
      } catch (err) {
        // Unexpected error in handleMessage — emit JSON-RPC internal error
        const errorId = (typeof msg === 'object' && msg !== null) ? msg.id ?? null : null;
        const errResp = {
          jsonrpc: '2.0',
          id: errorId,
          error: { code: -32603, message: `Internal error: ${err.message}` },
        };
        process.stdout.write(JSON.stringify(errResp) + '\n');
      }
    }
    processing = false;
  }

  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => {
    buffer += chunk;

    // MCP uses newline-delimited JSON
    let newlineIdx;
    while ((newlineIdx = buffer.indexOf('\n')) !== -1) {
      const line = buffer.slice(0, newlineIdx).trim();
      buffer = buffer.slice(newlineIdx + 1);

      if (!line) continue;

      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        const errResp = {
          jsonrpc: '2.0',
          id: null,
          error: { code: -32700, message: 'Parse error' },
        };
        process.stdout.write(JSON.stringify(errResp) + '\n');
        continue;
      }

      messageQueue.push(msg);
    }

    processQueue();
  });

  process.stdin.on('end', () => {
    process.exit(0);
  });

  // Prevent unhandled errors from crashing — log and exit
  process.on('uncaughtException', (err) => {
    process.stderr.write(`MCP server uncaught exception: ${err.message}\n`);
    process.exit(1);
  });

  process.on('unhandledRejection', (reason) => {
    const msg = reason instanceof Error ? reason.message : String(reason);
    process.stderr.write(`MCP server unhandled rejection: ${msg}\n`);
    process.exit(1);
  });
}

// ── Main ───────────────────────────────────────────────────────────────────
startStdioTransport();
