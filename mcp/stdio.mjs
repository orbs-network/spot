#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const packageDir = __dirname;
const packageJsonPath = path.join(packageDir, "package.json");
const skillDir = resolveSkillDir();
const skillMdPath = path.join(skillDir, "SKILL.md");
const cliPath = path.join(skillDir, "scripts", "order.js");

const [pkg, skillMd] = await Promise.all([
  readJsonFile(packageJsonPath),
  readFile(skillMdPath, "utf8"),
]);

const mcpName = requiredString(pkg.mcpName, "package.json mcpName");
const version = requiredString(pkg.version, "package.json version");
const skillFrontmatter = parseFrontmatter(skillMd);
const skillName = requiredString(skillFrontmatter.name, "skill frontmatter name");
const skillTitle = parseSkillTitle(skillMd);

const server = new McpServer({
  name: mcpName,
  version,
});

server.registerResource(
  "spot-skill",
  "spot://skill",
  {
    title: `${skillTitle} skill`,
    description: `Canonical ${skillName} SKILL.md with inline metadata for ${mcpName}`,
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

function parseFrontmatter(markdown) {
  const match = markdown.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    throw new Error("skill frontmatter is required");
  }

  return Object.fromEntries(
    match[1]
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const splitIndex = line.indexOf(":");
        if (splitIndex === -1) {
          throw new Error(`invalid frontmatter line: ${line}`);
        }
        return [line.slice(0, splitIndex).trim(), line.slice(splitIndex + 1).trim()];
      }),
  );
}

function parseSkillTitle(markdown) {
  const match = markdown.match(/^#\s+(.+)$/m);
  if (!match) {
    throw new Error("skill title heading is required");
  }
  return requiredString(match[1], "skill title");
}

function runCli(args, stdinJson) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: process.cwd(),
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

function resolveSkillDir() {
  try {
    return path.dirname(require.resolve("@orbs-network/spot-skill/package.json"));
  } catch {
    return path.resolve(packageDir, "..", "skill");
  }
}
