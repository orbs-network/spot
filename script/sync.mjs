#!/usr/bin/env node

import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const execFileAsync = promisify(execFile);
const rootPackageJsonPath = path.join(rootDir, "package.json");
const configPath = path.join(rootDir, "config.json");
const rootReadmePath = path.join(rootDir, "README.md");
const skillPackageJsonPath = path.join(rootDir, "skill", "package.json");
const skillReadmePath = path.join(rootDir, "skill", "README.md");
const skillSkillMdPath = path.join(rootDir, "skill", "SKILL.md");
const mcpPackageJsonPath = path.join(rootDir, "mcp", "package.json");
const mcpReadmePath = path.join(rootDir, "mcp", "README.md");
const serverJsonPath = path.join(rootDir, "mcp", "server.json");

if (process.argv.includes("-h") || process.argv.includes("--help")) {
  process.stdout.write(helpText());
  process.exit(0);
}

const [rootPkg, rootReadme, skillMd, config, existingMcpPkg] = await Promise.all([
  readJsonFile(rootPackageJsonPath),
  readFile(rootReadmePath, "utf8"),
  readFile(skillSkillMdPath, "utf8"),
  readJsonFile(configPath),
  readJsonFile(mcpPackageJsonPath),
]);

const version = requiredString(rootPkg.version, "package.json version");
const mcpName = requiredString(rootPkg.mcpName, "package.json mcpName");
const repository = requiredObject(rootPkg.repository, "package.json repository");
const bugs = requiredObject(rootPkg.bugs, "package.json bugs");
const engines = requiredObject(rootPkg.engines, "package.json engines");
const homepage = requiredString(rootPkg.homepage, "package.json homepage");
const repositoryUrl = normalizeRepositoryUrl(requiredString(repository.url, "package.json repository.url"));
const repositoryDefaultBranch = await resolveRepositoryDefaultBranch(rootDir);
const skillFrontmatter = parseFrontmatter(skillMd);
const skillConfig = normalizeSkillConfig(parseSkillConfig(skillMd), requiredObject(config, "config.json"));
const skillTitle = parseSkillTitle(skillMd);
const nextSkillMd = replaceSkillConfigBlock(skillMd, skillConfig);

const skillMetadata = {
  name: requiredString(skillFrontmatter.name, "skill frontmatter name"),
  title: skillTitle,
  description: requiredString(skillFrontmatter.description, "skill frontmatter description"),
  entrypoint: "SKILL.md",
  ...skillConfig,
};

const skillPkg = {
  name: "@orbs-network/spot-skill",
  version,
  description: skillMetadata.description,
  homepage,
  bugs,
  repository: {
    ...repository,
    directory: "skill",
  },
  license: requiredString(rootPkg.license, "package.json license"),
  author: requiredString(rootPkg.author, "package.json author"),
  engines,
  files: deriveSkillPackageFiles(skillMetadata),
};

const mcpPkg = {
  name: "@orbs-network/spot-mcp",
  version,
  mcpName,
  description: `MCP adapter for ${skillMetadata.title}.`,
  homepage,
  bugs,
  repository: {
    ...repository,
    directory: "mcp",
  },
  license: requiredString(rootPkg.license, "package.json license"),
  author: requiredString(rootPkg.author, "package.json author"),
  engines,
  bin: {
    "spot-mcp": "./stdio.mjs",
  },
  files: ["*.json", "*.md", "*.mjs"],
  ...omitKeys(existingMcpPkg, [
    "name",
    "version",
    "mcpName",
    "description",
    "homepage",
    "bugs",
    "repository",
    "license",
    "author",
    "engines",
    "bin",
    "files",
    "dependencies",
  ]),
  dependencies: {
    ...requiredObject(existingMcpPkg.dependencies, "mcp/package.json dependencies"),
    "@orbs-network/spot-skill": version,
  },
};

const serverJson = {
  $schema: "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  name: mcpName,
  title: skillMetadata.title,
  description: skillMetadata.description,
  repository: {
    url: repositoryUrl,
    source: "github",
  },
  version,
  packages: [
    {
      registryType: "npm",
      identifier: mcpPkg.name,
      version,
      transport: {
        type: "stdio",
      },
    },
  ],
};

const skillReadme = buildWorkspaceReadme({
  workspaceName: skillPkg.name,
  rootReadme,
  repositoryUrl,
  repositoryDefaultBranch,
});

const mcpReadme = buildWorkspaceReadme({
  workspaceName: mcpPkg.name,
  rootReadme,
  repositoryUrl,
  repositoryDefaultBranch,
});

await Promise.all([
  writeTextIfChanged(skillReadmePath, skillReadme),
  writeTextIfChanged(skillSkillMdPath, nextSkillMd),
  writeJsonIfChanged(skillPackageJsonPath, skillPkg),
  writeTextIfChanged(mcpReadmePath, mcpReadme),
  writeJsonIfChanged(mcpPackageJsonPath, mcpPkg),
  writeJsonIfChanged(serverJsonPath, serverJson),
]);

process.stdout.write(
  "synced skill/README.md, skill/SKILL.md, skill/package.json, mcp/README.md, mcp/package.json, and mcp/server.json\n",
);

async function readJsonFile(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function writeJsonIfChanged(filePath, value) {
  await writeTextIfChanged(filePath, `${JSON.stringify(value, null, 4)}\n`);
}

async function writeTextIfChanged(filePath, next) {
  const current = await readFile(filePath, "utf8").catch((error) => {
    if (error && error.code === "ENOENT") {
      return "";
    }
    throw error;
  });

  if (current !== next) {
    await writeFile(filePath, next);
  }
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value.trim();
}

function requiredObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is required`);
  }
  return value;
}

function requiredStringArray(value, label) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error(`${label} is required`);
  }
  return value.map((entry, index) => requiredString(entry, `${label}[${index}]`));
}

function normalizeRepositoryUrl(url) {
  return requiredString(url, "normalized repository url").replace(/^git\+/, "").replace(/\.git$/, "");
}

async function resolveRepositoryDefaultBranch(cwd) {
  const commands = [
    ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
    ["branch", "--show-current"],
  ];

  for (const args of commands) {
    try {
      const { stdout } = await execFileAsync("git", args, { cwd });
      const branch = stdout.trim().replace(/^origin\//, "");
      if (branch) {
        return branch;
      }
    } catch {}
  }

  return "master";
}

function normalizeSkillConfig(skillConfig, fullConfig) {
  return {
    references: requiredStringArray(skillConfig.references, "skill config references"),
    scripts: requiredStringArray(skillConfig.scripts, "skill config scripts"),
    assets: requiredStringArray(skillConfig.assets, "skill config assets"),
    runtime: deriveRuntime(skillConfig, fullConfig),
  };
}

function deriveRuntime(skillConfig, fullConfig) {
  const shared = requiredObject(fullConfig["*"], 'config.json["*"]');
  const chainNames = extractChainNames(skillConfig);

  return {
    url: extractRuntimeUrl(skillConfig),
    contracts: {
      zero: "0x0000000000000000000000000000000000000000",
      repermit: requiredString(shared.repermit, 'config.json["*"].repermit'),
      reactor: requiredString(shared.reactor, 'config.json["*"].reactor'),
      executor: requiredString(shared.executor, 'config.json["*"].executor'),
    },
    chains: Object.fromEntries(
      Object.entries(chainNames).map(([chainId, chainName]) => [
        chainId,
        {
          name: requiredString(chainName, `skill config chains.${chainId}`),
          adapter: pickAdapter(chainId, fullConfig),
        },
      ]),
    ),
  };
}

function extractRuntimeUrl(skillConfig) {
  if (isPlainObject(skillConfig.runtime) && typeof skillConfig.runtime.url === "string") {
    return requiredString(skillConfig.runtime.url, "skill config runtime.url");
  }
  return requiredString(skillConfig.runtimeUrl, "skill config runtimeUrl");
}

function extractChainNames(skillConfig) {
  if (isPlainObject(skillConfig.runtime) && isPlainObject(skillConfig.runtime.chains)) {
    return Object.fromEntries(
      Object.entries(skillConfig.runtime.chains).map(([chainId, chainConfig]) => [
        chainId,
        requiredString(chainConfig?.name, `skill config runtime.chains.${chainId}.name`),
      ]),
    );
  }

  return requiredObject(skillConfig.chains, "skill config chains");
}

function pickAdapter(chainId, fullConfig) {
  const chainConfig = requiredObject(fullConfig[chainId], `config.json[${chainId}]`);
  const dex = requiredObject(chainConfig.dex, `config.json[${chainId}].dex`);

  if (dex.agent && typeof dex.agent === "object" && !Array.isArray(dex.agent) && typeof dex.agent.adapter === "string") {
    return requiredString(dex.agent.adapter, `config.json[${chainId}].dex.agent.adapter`);
  }

  const dexNames = Object.keys(dex).sort();
  if (dexNames.length === 0) {
    throw new Error(`config.json[${chainId}].dex is required`);
  }

  const fallbackDex = requiredObject(dex[dexNames[0]], `config.json[${chainId}].dex.${dexNames[0]}`);
  return requiredString(fallbackDex.adapter, `config.json[${chainId}].dex.${dexNames[0]}.adapter`);
}

function unique(values) {
  return [...new Set(values)];
}

function deriveSkillPackageFiles(skillMetadata) {
  return unique([
    "*.md",
    ...deriveTopLevelDirectories([
      ...skillMetadata.references,
      ...skillMetadata.assets,
      ...skillMetadata.scripts,
    ]),
  ]);
}

function deriveTopLevelDirectories(relativePaths) {
  return relativePaths.map((relativePath) => {
    const [topLevel] = requiredString(relativePath, "package file path").split("/");
    return requiredString(topLevel, "package file top-level directory");
  });
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function omitKeys(source, keys) {
  return Object.fromEntries(Object.entries(source).filter(([key]) => !keys.includes(key)));
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

function parseSkillConfig(markdown) {
  const match = markdown.match(/## Config\n\n```json\n([\s\S]*?)\n```/);
  if (!match) {
    throw new Error("skill config JSON block is required");
  }
  return JSON.parse(match[1]);
}

function replaceSkillConfigBlock(markdown, skillConfig) {
  const match = markdown.match(/## Config\n\n```json\n[\s\S]*?\n```/);
  if (!match || match.index == null) {
    throw new Error("skill config JSON block is required");
  }

  const nextBlock = `## Config\n\n\`\`\`json\n${JSON.stringify(skillConfig, null, 2)}\n\`\`\``;
  return `${markdown.slice(0, match.index)}${nextBlock}${markdown.slice(match.index + match[0].length)}`;
}

function buildWorkspaceReadme({ workspaceName, rootReadme, repositoryUrl, repositoryDefaultBranch }) {
  const note = [
    "<!-- Generated by script/sync.mjs from the repository root README.md. Do not edit directly. -->",
    "",
    `> Auto-synced workspace README for \`${workspaceName}\`. Repo-relative links are rewritten to canonical GitHub URLs.`,
    "",
  ].join("\n");

  return `${note}${rewriteRelativeMarkdownLinks(rootReadme, repositoryUrl, repositoryDefaultBranch)}`;
}

function rewriteRelativeMarkdownLinks(markdown, repositoryUrl, repositoryDefaultBranch) {
  return markdown.replace(/\]\((\.\/[^)]+)\)/g, (match, target) => {
    return match.replace(target, toRepositoryUrl(target, repositoryUrl, repositoryDefaultBranch));
  });
}

function toRepositoryUrl(target, repositoryUrl, repositoryDefaultBranch) {
  const relativePath = target.slice(2);
  if (relativePath.length === 0) {
    return repositoryUrl;
  }

  const kind = relativePath.endsWith("/") ? "tree" : "blob";
  const normalizedPath = relativePath
    .split("/")
    .filter(Boolean)
    .map((segment) => encodeURIComponent(segment))
    .join("/");

  return `${repositoryUrl}/${kind}/${repositoryDefaultBranch}/${normalizedPath}`;
}

function helpText() {
  return [
    "🛠️  sync.mjs",
    "",
    "Generate derived skill, MCP, and workspace README metadata from the canonical repo inputs.",
    "",
    "🚀 Usage",
    "  node ./script/sync.mjs",
    "  node ./script/sync.mjs -h",
    "  node ./script/sync.mjs --help",
    "",
    "📥 Inputs",
    "  1. package.json",
    "     Root package metadata used for versions, repository, author, license, engines, and MCP package naming.",
    "  2. config.json",
    "     Chain deployment config used to derive runtime addresses and adapters.",
    "  3. README.md",
    "     Root repository README used as the source for auto-synced workspace package READMEs in skill/ and mcp/.",
    "  4. skill/SKILL.md",
    "     Canonical skill source. Frontmatter provides slug and description. The H1 provides title. The `## Config` JSON block provides references, assets, scripts, and inline runtime metadata.",
    "  5. mcp/package.json",
    "     MCP package input for MCP-owned fields such as pinned runtime dependencies and any extra publish metadata not derived by sync.",
    "",
    "📤 Outputs",
    "  1. skill/README.md",
    "     Auto-synced workspace README generated from the root README with repo-relative links rewritten to canonical GitHub URLs.",
    "  2. skill/SKILL.md",
    "     Normalized `## Config` JSON block with runtime contracts and per-chain adapters derived from config.json.",
    "  3. skill/package.json",
    "     Publish metadata for @orbs-network/spot-skill.",
    "  4. mcp/README.md",
    "     Auto-synced workspace README generated from the root README with repo-relative links rewritten to canonical GitHub URLs.",
    "  5. mcp/package.json",
    "     Synced publish metadata for @orbs-network/spot-mcp. Derived fields are overwritten; MCP-owned fields are preserved.",
    "  6. mcp/server.json",
    "     MCP registry metadata for io.github.orbs-network/spot.",
    "",
    "🧭 Rules",
    "  1. skill/SKILL.md remains the canonical skill surface, and sync rewrites only its machine-readable `## Config` block.",
    "  2. config.json is the source of truth for deployed addresses and adapter selection.",
    "  3. README.md is the source of truth for workspace package README copies in skill/ and mcp/.",
    "  4. mcp/package.json may retain MCP-owned fields such as pinned runtime dependencies.",
    "  5. Sync overwrites only derived fields in mcp/package.json.",
    "  6. The script is intentionally non-interactive and takes no mutation flags.",
    "",
    "🔎 Validation",
    "  1. Missing README.md, missing frontmatter, missing `## Config`, invalid JSON, missing chain config, missing mcp/package.json dependencies, or missing package metadata will fail the run.",
    "  2. If git remote HEAD cannot be resolved, the script falls back to the current branch and then `master` for canonical GitHub README links.",
    "  3. If a chain lacks `dex.agent.adapter`, the script falls back to the first sorted dex entry for that chain.",
    "",
    "✅ Typical flow",
    "  1. Edit README.md, skill/SKILL.md, config.json, root package.json, or MCP-owned fields in mcp/package.json.",
    "  2. Run `npm run sync`.",
    "  3. Run `npm run build`.",
    "",
  ].join("\n");
}
