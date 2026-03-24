#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const packageJsonPath = path.join(rootDir, "package.json");
const manifestPath = path.join(rootDir, "skills", "advanced-swap-orders", "manifest.json");
const serverJsonPath = path.join(rootDir, "server.json");

const [pkg, manifest] = await Promise.all([
  readJsonFile(packageJsonPath),
  readJsonFile(manifestPath),
]);

const mcpName = requiredString(pkg.mcpName, "package.json mcpName");
const packageName = requiredString(pkg.name, "package.json name");
const version = requiredString(pkg.version, "package.json version");
const title = requiredString(manifest.title, "skill manifest title");
const description = requiredString(manifest.description, "skill manifest description");
const repositoryUrl = normalizeRepositoryUrl(requiredString(pkg.repository?.url, "package.json repository.url"));

const serverJson = {
  $schema: "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  name: mcpName,
  title,
  description,
  repository: {
    url: repositoryUrl,
    source: "github",
  },
  version,
  packages: [
    {
      registryType: "npm",
      identifier: packageName,
      version,
      transport: {
        type: "stdio",
      },
    },
  ],
};

const next = `${JSON.stringify(serverJson, null, 2)}\n`;
const current = await readFile(serverJsonPath, "utf8").catch((error) => {
  if (error && error.code === "ENOENT") {
    return "";
  }
  throw error;
});

if (current !== next) {
  await writeFile(serverJsonPath, next);
}

process.stdout.write("synced server.json\n");

async function readJsonFile(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value.trim();
}

function normalizeRepositoryUrl(url) {
  return requiredString(url, "normalized repository url").replace(/^git\+/, "").replace(/\.git$/, "");
}
