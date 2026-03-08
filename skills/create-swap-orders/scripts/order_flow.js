#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const SINK_URL = "https://agents-sink-dev.orbs.network";
const CREATE_ORDER_PATH = "/orders/new";
const QUERY_ORDERS_PATH = "/orders";
const BPS = 10_000;
const MAX_SLIPPAGE = BPS / 2;
const APPROVE_SELECTOR = "095ea7b3";
const CORE_CONTRACTS = {
  repermit: "0x00002a9C4D9497df5Bd31768eC5d30eEf5405000",
  reactor: "0x000000b33fE4fB9d999Dd684F79b110731c3d000",
  executor: "0x000642A0966d9bd49870D9519f76b5cf823f3000",
};
const CHAIN_ADAPTERS = {
  56: "0x67Feba015c968c76cCB2EEabf197b4578640BE2C",
  42161: "0x026B8977319F67078e932a08feAcB59182B5380f",
};

const ASSET_DIR = path.join(__dirname, "..", "assets");
const SKELETON = readJson(path.join(ASSET_DIR, "repermit.skeleton.json"));

function usage(exitCode = 1) {
  console.error(
    [
      "Usage:",
      "  node skills/create-swap-orders/scripts/order_flow.js prepare --params <params.json> [--out <prepared.json>]",
      "  node skills/create-swap-orders/scripts/order_flow.js submit --prepared <prepared.json> --signature <0x...> [--format split|raw] [--dry-run] [--out <response.json>]",
      "  node skills/create-swap-orders/scripts/order_flow.js query [--page <n>] [--limit <n>] [--swapper <0x...>] [--recipient <0x...>] [--hash <0x...>] [--chainId <id>] [--filler <0x...>] [--exchange <0x...>] [--inputToken <0x...>] [--outputToken <0x...>] [--view list] [--dry-run] [--out <response.json>]",
    ].join("\n")
  );
  process.exit(exitCode);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function parseArgs(argv) {
  const args = { _: [] };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      args._.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    i += 1;
  }

  return args;
}

function getPath(object, dottedPath) {
  return dottedPath.split(".").reduce((current, part) => {
    if (current === undefined || current === null) {
      return undefined;
    }
    return current[part];
  }, object);
}

function choose(object, paths, fallback) {
  for (const dottedPath of paths) {
    const value = getPath(object, dottedPath);
    if (value !== undefined && value !== null && value !== "") {
      return value;
    }
  }
  return fallback;
}

function normalizeAddress(value, name, { allowZero = false } = {}) {
  if (typeof value !== "string") {
    throw new Error(`${name} must be a 0x-prefixed address string`);
  }
  if (!/^0x[0-9a-fA-F]{40}$/.test(value)) {
    throw new Error(`${name} must be a valid 20-byte hex address`);
  }
  if (!allowZero && value.toLowerCase() === ZERO_ADDRESS) {
    throw new Error(`${name} cannot be the zero address`);
  }
  return value;
}

function normalizeHexData(value, name) {
  if (typeof value !== "string") {
    throw new Error(`${name} must be a 0x-prefixed hex string`);
  }
  if (!/^0x([0-9a-fA-F]{2})*$/.test(value)) {
    throw new Error(`${name} must be valid hex data`);
  }
  return value;
}

function uintToDecimalString(value, name) {
  if (value === undefined || value === null || value === "") {
    throw new Error(`${name} is required`);
  }

  let bigintValue;
  if (typeof value === "bigint") {
    bigintValue = value;
  } else if (typeof value === "number") {
    if (!Number.isInteger(value) || !Number.isSafeInteger(value)) {
      throw new Error(`${name} must be an integer within JS safe range or a string`);
    }
    bigintValue = BigInt(value);
  } else if (typeof value === "string") {
    try {
      bigintValue = BigInt(value);
    } catch {
      throw new Error(`${name} must be a decimal or 0x-prefixed integer string`);
    }
  } else {
    throw new Error(`${name} must be an integer-like value`);
  }

  if (bigintValue < 0n) {
    throw new Error(`${name} cannot be negative`);
  }

  return bigintValue.toString(10);
}

function uint32Value(value, name) {
  const decimalString = uintToDecimalString(value, name);
  const bigintValue = BigInt(decimalString);
  if (bigintValue > 0xffffffffn) {
    throw new Error(`${name} must fit in uint32`);
  }
  return Number(bigintValue);
}

function unixNow() {
  return Math.floor(Date.now() / 1000);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function stripTrailingSlash(value) {
  return value.replace(/\/+$/, "");
}

function resolveCreateOrderUrl(baseOrUrl) {
  const normalized = stripTrailingSlash(baseOrUrl);
  if (normalized.endsWith(CREATE_ORDER_PATH)) {
    return normalized;
  }
  return `${normalized}${CREATE_ORDER_PATH}`;
}

function resolveQueryOrdersUrl(baseOrUrl) {
  const normalized = stripTrailingSlash(baseOrUrl);
  if (normalized.endsWith(QUERY_ORDERS_PATH)) {
    return normalized;
  }
  return `${normalized}${QUERY_ORDERS_PATH}`;
}

function strip0x(value) {
  return value.startsWith("0x") ? value.slice(2) : value;
}

function encodeAddressWord(address) {
  return strip0x(address).toLowerCase().padStart(64, "0");
}

function encodeUintWord(value) {
  return BigInt(value).toString(16).padStart(64, "0");
}

function encodeApprove(spender, amount) {
  return `0x${APPROVE_SELECTOR}${encodeAddressWord(spender)}${encodeUintWord(amount)}`;
}

function resolveContracts(chainId) {
  const adapter = CHAIN_ADAPTERS[chainId];
  if (!adapter) {
    throw new Error(`unsupported chainId: ${chainId}`);
  }

  return {
    chainId,
    ...CORE_CONTRACTS,
    adapter,
  };
}

function normalizeParams(raw) {
  const now = unixNow();
  const chainIdDecimal = uintToDecimalString(choose(raw, ["chainId", "chainID"], undefined), "chainId");
  const chainId = Number(BigInt(chainIdDecimal));
  if (!Number.isSafeInteger(chainId)) {
    throw new Error("chainId must fit in a JS safe integer");
  }

  const swapper = normalizeAddress(choose(raw, ["swapper", "account", "signer"], undefined), "swapper");

  const nonce = uintToDecimalString(choose(raw, ["nonce"], `${Date.now()}`), "nonce");
  const start = uintToDecimalString(choose(raw, ["start"], `${now}`), "start");
  const deadline = uintToDecimalString(choose(raw, ["deadline"], `${now + 86400}`), "deadline");
  const exclusivity = uint32Value(choose(raw, ["exclusivity"], 0), "exclusivity");
  const epoch = uint32Value(choose(raw, ["epoch"], 0), "epoch");
  const slippage = uint32Value(choose(raw, ["slippage"], 100), "slippage");

  let defaultFreshness = 60;
  if (epoch !== 0 && defaultFreshness >= epoch) {
    defaultFreshness = Math.max(1, epoch - 1);
  }
  const freshness = uint32Value(choose(raw, ["freshness"], defaultFreshness), "freshness");

  const input = {
    token: normalizeAddress(choose(raw, ["input.token", "inputToken"], undefined), "input.token"),
    amount: uintToDecimalString(choose(raw, ["input.amount", "inputAmount"], undefined), "input.amount"),
    maxAmount: uintToDecimalString(
      choose(raw, ["input.maxAmount", "inputMaxAmount"], undefined),
      "input.maxAmount"
    ),
  };

  const output = {
    token: normalizeAddress(choose(raw, ["output.token", "outputToken"], undefined), "output.token"),
    limit: uintToDecimalString(choose(raw, ["output.limit", "outputLimit"], undefined), "output.limit"),
    triggerLower: uintToDecimalString(
      choose(raw, ["output.triggerLower", "outputTriggerLower"], 0),
      "output.triggerLower"
    ),
    triggerUpper: uintToDecimalString(
      choose(raw, ["output.triggerUpper", "outputTriggerUpper"], 0),
      "output.triggerUpper"
    ),
    recipient: normalizeAddress(
      choose(raw, ["output.recipient", "recipient"], swapper),
      "output.recipient"
    ),
  };

  const exchange = {
    adapter: choose(raw, ["exchange.adapter", "adapter"], undefined),
    ref: normalizeAddress(choose(raw, ["exchange.ref", "exchangeRef"], ZERO_ADDRESS), "exchange.ref", {
      allowZero: true,
    }),
    share: uint32Value(choose(raw, ["exchange.share", "exchangeShare"], 0), "exchange.share"),
    data: normalizeHexData(choose(raw, ["exchange.data", "exchangeData"], "0x"), "exchange.data"),
  };

  if (BigInt(start) === 0n) {
    throw new Error("start must be non-zero");
  }
  if (BigInt(start) > BigInt(now)) {
    throw new Error("start cannot be in the future");
  }
  if (BigInt(deadline) <= BigInt(now)) {
    throw new Error("deadline must be after the current time");
  }
  if (BigInt(input.amount) === 0n) {
    throw new Error("input.amount must be non-zero");
  }
  if (BigInt(input.amount) > BigInt(input.maxAmount)) {
    throw new Error("input.amount cannot exceed input.maxAmount");
  }
  if (input.token.toLowerCase() === output.token.toLowerCase()) {
    throw new Error("input.token and output.token must differ");
  }
  if (BigInt(output.triggerUpper) !== 0n && BigInt(output.triggerLower) > BigInt(output.triggerUpper)) {
    throw new Error("output.triggerLower cannot exceed output.triggerUpper when triggerUpper is set");
  }
  if (slippage > MAX_SLIPPAGE) {
    throw new Error(`slippage cannot exceed ${MAX_SLIPPAGE}`);
  }
  if (exchange.share > BPS) {
    throw new Error(`exchange.share cannot exceed ${BPS}`);
  }
  if (freshness === 0) {
    throw new Error("freshness must be greater than zero");
  }
  if (epoch !== 0 && freshness >= epoch) {
    throw new Error("freshness must be smaller than epoch when epoch is non-zero");
  }
  if (exchange.adapter !== undefined) {
    exchange.adapter = normalizeAddress(exchange.adapter, "exchange.adapter");
  }

  return {
    chainId,
    swapper,
    nonce,
    start,
    deadline,
    exclusivity,
    epoch,
    slippage,
    freshness,
    input,
    output,
    exchange,
  };
}

function buildTypedData(params, contracts) {
  const typedData = clone(SKELETON);
  const adapter = params.exchange.adapter || contracts.adapter;
  if (!adapter) {
    throw new Error(`no adapter configured for chainId ${params.chainId}`);
  }

  typedData.domain.chainId = params.chainId;
  typedData.domain.verifyingContract = contracts.repermit;

  typedData.message.permitted.token = params.input.token;
  typedData.message.permitted.amount = params.input.maxAmount;
  typedData.message.spender = contracts.reactor;
  typedData.message.nonce = params.nonce;
  typedData.message.deadline = params.deadline;

  typedData.message.witness.reactor = contracts.reactor;
  typedData.message.witness.executor = contracts.executor;
  typedData.message.witness.exchange.adapter = adapter;
  typedData.message.witness.exchange.ref = params.exchange.ref;
  typedData.message.witness.exchange.share = params.exchange.share;
  typedData.message.witness.exchange.data = params.exchange.data;
  typedData.message.witness.swapper = params.swapper;
  typedData.message.witness.nonce = params.nonce;
  typedData.message.witness.start = params.start;
  typedData.message.witness.deadline = params.deadline;
  typedData.message.witness.chainid = params.chainId;
  typedData.message.witness.exclusivity = params.exclusivity;
  typedData.message.witness.epoch = params.epoch;
  typedData.message.witness.slippage = params.slippage;
  typedData.message.witness.freshness = params.freshness;
  typedData.message.witness.input.token = params.input.token;
  typedData.message.witness.input.amount = params.input.amount;
  typedData.message.witness.input.maxAmount = params.input.maxAmount;
  typedData.message.witness.output.token = params.output.token;
  typedData.message.witness.output.limit = params.output.limit;
  typedData.message.witness.output.triggerLower = params.output.triggerLower;
  typedData.message.witness.output.triggerUpper = params.output.triggerUpper;
  typedData.message.witness.output.recipient = params.output.recipient;

  return typedData;
}

function buildPrepared(rawParams) {
  const params = normalizeParams(rawParams);
  const contracts = resolveContracts(params.chainId);
  const typedData = buildTypedData(params, contracts);
  const approvalAmount = params.input.maxAmount;
  const createOrderUrl = resolveCreateOrderUrl(SINK_URL);
  const queryOrdersUrl = resolveQueryOrdersUrl(SINK_URL);

  return {
    meta: {
      skill: "create-swap-orders",
      preparedAt: new Date().toISOString(),
      orderKind: params.epoch === 0 ? "single-shot" : "twap",
      triggerMode:
        BigInt(params.output.triggerLower) === 0n && BigInt(params.output.triggerUpper) === 0n
          ? "limit-only"
          : "triggered",
    },
    approval: {
      description: "Approve the required spender for the maximum input amount",
      token: params.input.token,
      spender: contracts.repermit,
      amount: approvalAmount,
      tx: {
        to: params.input.token,
        data: encodeApprove(contracts.repermit, approvalAmount),
        value: "0x0",
      },
    },
    typedData,
    signing: {
      signer: params.swapper,
      jsonRpcMethod: "eth_signTypedData_v4",
      params: [params.swapper, JSON.stringify(typedData)],
    },
    submit: {
      url: createOrderUrl,
      path: CREATE_ORDER_PATH,
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: {
        order: typedData.message,
        signature: {
          v: null,
          r: null,
          s: null,
        },
      },
    },
    query: {
      url: queryOrdersUrl,
      path: QUERY_ORDERS_PATH,
      example: `${queryOrdersUrl}?swapper=${params.swapper}&chainId=${params.chainId}&limit=10`,
    },
  };
}

function extractTypedData(prepared) {
  if (prepared && prepared.typedData) {
    return prepared.typedData;
  }
  if (prepared && prepared.order && prepared.order.domain && prepared.order.types && prepared.order.message) {
    return prepared.order;
  }
  if (prepared && prepared.domain && prepared.types && prepared.message) {
    return prepared;
  }
  throw new Error("could not find typed data in prepared input");
}

function extractOrderMessage(prepared) {
  if (prepared && prepared.submit && prepared.submit.body && prepared.submit.body.order) {
    return prepared.submit.body.order;
  }
  const typedData = extractTypedData(prepared);
  return typedData.message;
}

function normalizeSignature(signature) {
  if (typeof signature !== "string") {
    throw new Error("signature must be a hex string");
  }
  const prefixed = signature.startsWith("0x") ? signature : `0x${signature}`;
  if (!/^0x[0-9a-fA-F]{130}$/.test(prefixed)) {
    throw new Error("signature must be a 65-byte hex string");
  }
  return prefixed;
}

function splitSignature(signature) {
  const normalized = normalizeSignature(signature).slice(2);
  return {
    r: `0x${normalized.slice(0, 64)}`,
    s: `0x${normalized.slice(64, 128)}`,
    v: `0x${normalized.slice(128, 130)}`,
  };
}

function readSignature(args) {
  if (typeof args.signature === "string") {
    return args.signature.trim();
  }
  if (typeof args["signature-file"] === "string") {
    return fs.readFileSync(args["signature-file"], "utf8").trim();
  }
  throw new Error("submit requires --signature or --signature-file");
}

async function runPrepare(args) {
  if (typeof args.params !== "string") {
    throw new Error("prepare requires --params");
  }
  const rawParams = readJson(args.params);
  const prepared = buildPrepared(rawParams);

  if (typeof args.out === "string") {
    writeJson(args.out, prepared);
    return;
  }

  printJson(prepared);
}

async function runSubmit(args) {
  if (typeof args.prepared !== "string") {
    throw new Error("submit requires --prepared");
  }

  const prepared = readJson(args.prepared);
  const order = extractOrderMessage(prepared);
  const signatureInput = readSignature(args);
  const format = args.format || "split";
  if (!["split", "raw"].includes(format)) {
    throw new Error("--format must be 'split' or 'raw'");
  }

  const request = {
    url: prepared.submit?.url || resolveCreateOrderUrl(SINK_URL),
    method: "POST",
    headers: prepared.submit?.headers || { "content-type": "application/json" },
    body: {
      order,
      signature: format === "split" ? splitSignature(signatureInput) : normalizeSignature(signatureInput),
    },
  };

  if (args["dry-run"]) {
    if (typeof args.out === "string") {
      writeJson(args.out, request);
      return;
    }
    printJson(request);
    return;
  }

  if (typeof fetch !== "function") {
    throw new Error("global fetch is unavailable in this Node runtime; use --dry-run");
  }

  const response = await fetch(request.url, {
    method: request.method,
    headers: request.headers,
    body: JSON.stringify(request.body),
  });

  const text = await response.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = text;
  }

  const result = {
    ok: response.ok,
    status: response.status,
    url: request.url,
    request,
    response: parsed,
  };

  if (typeof args.out === "string") {
    writeJson(args.out, result);
  } else {
    printJson(result);
  }

  if (!response.ok) {
    process.exitCode = 1;
  }
}

async function runQuery(args) {
  const reserved = new Set(["out", "dry-run"]);
  const params = new URLSearchParams();

  for (const [key, value] of Object.entries(args)) {
    if (key === "_" || reserved.has(key) || value === undefined || value === false) {
      continue;
    }
    params.set(key, String(value));
  }

  const url = params.toString()
    ? `${resolveQueryOrdersUrl(SINK_URL)}?${params.toString()}`
    : resolveQueryOrdersUrl(SINK_URL);

  if (args["dry-run"]) {
    const request = { method: "GET", url };
    if (typeof args.out === "string") {
      writeJson(args.out, request);
      return;
    }
    printJson(request);
    return;
  }

  if (typeof fetch !== "function") {
    throw new Error("global fetch is unavailable in this Node runtime; use --dry-run");
  }

  const response = await fetch(url, { method: "GET" });
  const text = await response.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = text;
  }

  const result = {
    ok: response.ok,
    status: response.status,
    url,
    response: parsed,
  };

  if (typeof args.out === "string") {
    writeJson(args.out, result);
  } else {
    printJson(result);
  }

  if (!response.ok) {
    process.exitCode = 1;
  }
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv[0] === "help" || argv[0] === "--help") {
    usage(argv.length === 0 ? 1 : 0);
  }

  const [command, ...rest] = argv;
  const args = parseArgs(rest);

  if (command === "prepare") {
    await runPrepare(args);
    return;
  }

  if (command === "submit") {
    await runSubmit(args);
    return;
  }

  if (command === "query") {
    await runQuery(args);
    return;
  }

  usage();
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
