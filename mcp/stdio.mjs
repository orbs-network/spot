#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const packageJsonPath = path.join(rootDir, "package.json");
const skillMdPath = path.join(rootDir, "SKILL.md");
const manifestPath = path.join(rootDir, "manifest.json");
const cliPath = path.join(rootDir, "skill", "scripts", "order.js");

const [pkg, manifest] = await Promise.all([
  readJsonFile(packageJsonPath),
  readJsonFile(manifestPath),
]);

const mcpName = requiredString(pkg.mcpName, "package.json mcpName");
const version = requiredString(pkg.version, "package.json version");
const skillName = requiredString(manifest.name, "skill manifest name");
const skillTitle = requiredString(manifest.title, "skill manifest title");

const server = new McpServer({
  name: mcpName,
  version,
});

server.registerResource(
  "spot-skill",
  "spot://skill",
  {
    title: `${skillTitle} skill`,
    description: `Canonical ${skillName} SKILL.md for ${mcpName}`,
    mimeType: "text/markdown",
  },
  async (uri) => ({
    contents: [
      {
        uri: uri.href,
        text: await readFile(skillMdPath, "utf8"),
        mimeType: "text/markdown",
      },
    ],
  }),
);

server.registerResource(
  "spot-manifest",
  "spot://manifest",
  {
    title: `${skillTitle} manifest`,
    description: `Canonical ${skillName} manifest.json for ${mcpName}`,
    mimeType: "application/json",
  },
  async (uri) => ({
    contents: [
      {
        uri: uri.href,
        text: JSON.stringify(manifest, null, 2),
        mimeType: "application/json",
      },
    ],
  }),
);

server.registerTool(
  "prepare_order",
  {
    title: "Prepare order",
    description: "Prepare approval calldata, typed data, submit payload, and query URL.",
    inputSchema: {
      params: z.record(z.string(), z.unknown()),
    },
  },
  async ({ params }) => runTool(["prepare", "--params", "-"], params),
);

server.registerTool(
  "submit_order",
  {
    title: "Submit order",
    description: "Submit a prepared order with a signature.",
    inputSchema: {
      prepared: z.unknown(),
      signature: z.union([
        z.string(),
        z.object({
          r: z.string(),
          s: z.string(),
          v: z.union([z.string(), z.number()]),
        }),
      ]),
    },
  },
  async ({ prepared, signature }) => {
    const signatureArgs =
      typeof signature === "string"
        ? ["--signature", signature]
        : ["--signature", JSON.stringify(signature)];

    return runTool(["submit", "--prepared", "-", ...signatureArgs], prepared);
  },
);

server.registerTool(
  "query_orders",
  {
    title: "Query orders",
    description: "Query orders by swapper and/or order hash.",
    inputSchema: {
      swapper: z.string().optional(),
      hash: z.string().optional(),
    },
  },
  async ({ swapper, hash }) => {
    if (!swapper && !hash) {
      return toolError("query_orders requires swapper or hash");
    }

    const args = ["query"];
    if (swapper) {
      args.push("--swapper", swapper);
    }
    if (hash) {
      args.push("--hash", hash);
    }

    return runTool(args);
  },
);

await server.connect(new StdioServerTransport());

async function readJsonFile(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value;
}

function runCli(args, stdinJson) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: rootDir,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += String(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += String(chunk);
    });
    child.on("error", reject);

    child.on("close", (code) => {
      const out = stdout.trim();
      const err = stderr.trim();

      if (code !== 0) {
        reject(new Error(err || out || `order.js exited with code ${code}`));
        return;
      }

      try {
        resolve(out ? JSON.parse(out) : {});
      } catch {
        resolve({
          raw: out,
          stderr: err,
        });
      }
    });

    const payload = stdinJson == null ? "" : `${JSON.stringify(stdinJson)}\n`;
    child.stdin.end(payload);
  });
}

async function runTool(args, stdinJson) {
  try {
    const output = await runCli(args, stdinJson);
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(output, null, 2),
        },
      ],
      structuredContent: output,
    };
  } catch (error) {
    return toolError(String(error?.message ?? error));
  }
}

function toolError(message) {
  return {
    isError: true,
    content: [
      {
        type: "text",
        text: message,
      },
    ],
  };
}
