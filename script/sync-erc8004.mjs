#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const packageJsonPath = path.join(rootDir, "package.json");
const manifestPath = path.join(rootDir, "manifest.json");
const registrationDir = path.join(rootDir, ".well-known");
const registrationPath = path.join(registrationDir, "agent-registration.json");

const [pkg, manifest] = await Promise.all([
  readJsonFile(packageJsonPath),
  readJsonFile(manifestPath),
]);

const packageName = requiredString(pkg.name, "package.json name");
const version = requiredString(pkg.version, "package.json version");
const mcpName = requiredString(pkg.mcpName, "package.json mcpName");
const repositoryUrl = normalizeRepositoryUrl(requiredString(pkg.repository?.url, "package.json repository.url"));
const hostedBaseUrl = trimTrailingSlash(requiredString(manifest.hostedBaseUrl, "manifest.json hostedBaseUrl"));
const title = requiredString(manifest.title, "manifest.json title");
const description = requiredString(manifest.description, "manifest.json description");
const imagePath = requiredString(manifest.image, "manifest.json image");
const erc8004 = requiredObject(manifest.erc8004, "manifest.json erc8004");
const x402Support = requiredBoolean(erc8004.x402Support, "manifest.json erc8004.x402Support");
const active = requiredBoolean(erc8004.active, "manifest.json erc8004.active");
const registrations = requiredRegistrationList(erc8004.registrations, "manifest.json erc8004.registrations");
const supportedTrust = requiredStringList(erc8004.supportedTrust, "manifest.json erc8004.supportedTrust");

const registration = {
  type: "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  name: title,
  description,
  image: `${hostedBaseUrl}/${trimLeadingSlash(imagePath)}`,
  services: [
    {
      name: "web",
      endpoint: `${hostedBaseUrl}/`,
    },
    {
      name: "MCP",
      endpoint: `${hostedBaseUrl}/server.json`,
      version,
    },
    {
      name: "skill",
      endpoint: `${hostedBaseUrl}/SKILL.md`,
      version,
    },
    {
      name: "npm",
      endpoint: `https://www.npmjs.com/package/${packageName}`,
      version,
    },
    {
      name: "GitHub",
      endpoint: repositoryUrl,
      version,
    },
  ],
  x402Support,
  active,
  registrations,
  supportedTrust,
};

const next = `${JSON.stringify(registration, null, 2)}\n`;
const current = await readFile(registrationPath, "utf8").catch((error) => {
  if (error && error.code === "ENOENT") {
    return "";
  }
  throw error;
});

await mkdir(registrationDir, { recursive: true });

if (current !== next) {
  await writeFile(registrationPath, next);
}

process.stdout.write(`synced ${path.relative(rootDir, registrationPath)} for ${mcpName}\n`);

async function readJsonFile(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value.trim();
}

function requiredObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value;
}

function requiredBoolean(value, label) {
  if (typeof value !== "boolean") {
    throw new Error(`${label} must be a boolean`);
  }
  return value;
}

function requiredStringList(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
  }

  return value.map((entry, index) => requiredString(entry, `${label}[${index}]`));
}

function requiredRegistrationList(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
  }

  return value.map((entry, index) => {
    const registration = requiredObject(entry, `${label}[${index}]`);
    const agentId = registration.agentId;

    if (!Number.isInteger(agentId) || agentId < 0) {
      throw new Error(`${label}[${index}].agentId must be a non-negative integer`);
    }

    return {
      agentId,
      agentRegistry: requiredString(registration.agentRegistry, `${label}[${index}].agentRegistry`),
    };
  });
}

function normalizeRepositoryUrl(url) {
  return requiredString(url, "normalized repository url").replace(/^git\+/, "").replace(/\.git$/, "");
}

function trimLeadingSlash(value) {
  return value.replace(/^\/+/, "");
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, "");
}
