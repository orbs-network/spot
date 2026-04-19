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
const skillRepermitTemplatePath = path.join(rootDir, "skill", "assets", "repermit.template.json");
const skillExamplesMdPath = path.join(rootDir, "skill", "references", "examples.md");
const mcpPackageJsonPath = path.join(rootDir, "mcp", "package.json");
const mcpReadmePath = path.join(rootDir, "mcp", "README.md");
const serverJsonPath = path.join(rootDir, "mcp", "server.json");

const EXAMPLE_SPECS = [
  {
    title: "Limit Order",
    chainId: 42161,
    swapper: "0x2222222222222222222222222222222222222222",
    inputToken: "0x1111111111111111111111111111111111111111",
    inputAmount: "1000000",
    inputMaxAmount: "1000000",
    outputToken: "0x3333333333333333333333333333333333333333",
    outputLimit: "250000000000000",
    outputTriggerLower: "0",
    outputTriggerUpper: "0",
    nonce: "1712345601",
    start: "1712345601",
    deadline: "1712345901",
    epoch: 0,
    slippage: 500,
    signature:
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1b",
  },
  {
    title: "Stop-Loss Order",
    chainId: 1,
    swapper: "0x5555555555555555555555555555555555555555",
    inputToken: "0x4444444444444444444444444444444444444444",
    inputAmount: "5000000000000000000",
    inputMaxAmount: "5000000000000000000",
    outputToken: "0x6666666666666666666666666666666666666666",
    outputLimit: "0",
    outputTriggerLower: "9000000000000",
    outputTriggerUpper: "0",
    nonce: "1712346602",
    start: "1712346602",
    deadline: "1712347202",
    epoch: 0,
    slippage: 500,
    signature:
      "0xccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd1c",
  },
  {
    title: "TWAP Order",
    chainId: 8453,
    swapper: "0x8888888888888888888888888888888888888888",
    inputToken: "0x7777777777777777777777777777777777777777",
    inputAmount: "3000000",
    inputMaxAmount: "12000000",
    outputToken: "0x9999999999999999999999999999999999999999",
    outputLimit: "0",
    outputTriggerLower: "0",
    outputTriggerUpper: "0",
    nonce: "1712347603",
    start: "1712347603",
    deadline: "1712348503",
    epoch: 300,
    slippage: 500,
    signature:
      "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1b",
  },
];

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
const fullConfig = requiredObject(config, "config.json");
const skillConfig = normalizeSkillConfig(parseSkillConfig(skillMd), fullConfig);
const skillTitle = parseSkillTitle(skillMd);
const nextSkillMd = replaceSkillConfigBlock(skillMd, skillConfig);
const repermitTemplate = buildRepermitTemplate(fullConfig);
const skillExamples = buildExamplesMarkdown(fullConfig);

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
  files: ["*.json", "*.md", "*.mjs", "*.js"],
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
  writeJsonIfChanged(skillRepermitTemplatePath, repermitTemplate),
  writeTextIfChanged(skillExamplesMdPath, skillExamples),
  writeJsonIfChanged(skillPackageJsonPath, skillPkg),
  writeTextIfChanged(mcpReadmePath, mcpReadme),
  writeJsonIfChanged(mcpPackageJsonPath, mcpPkg),
  writeJsonIfChanged(serverJsonPath, serverJson),
]);

process.stdout.write(
  "synced skill/README.md, skill/SKILL.md, skill/assets/repermit.template.json, skill/references/examples.md, skill/package.json, mcp/README.md, mcp/package.json, and mcp/server.json\n",
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

function optionalStringArray(value, label) {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
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
    scripts: optionalStringArray(skillConfig.scripts, "skill config scripts"),
    assets: optionalStringArray(skillConfig.assets, "skill config assets"),
    runtime: deriveRuntime(skillConfig, fullConfig),
  };
}

function deriveRuntime(skillConfig, fullConfig) {
  const chainNames = extractChainNames(skillConfig);

  return {
    url: extractRuntimeUrl(skillConfig),
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

function buildRepermitTemplate(fullConfig) {
  const shared = requiredObject(fullConfig["*"], 'config.json["*"]');

  return {
    domain: {
      name: "RePermit",
      version: "1",
      chainId: "<CHAIN_ID>",
      verifyingContract: requiredString(shared.repermit, 'config.json["*"].repermit'),
    },
    primaryType: "RePermitWitnessTransferFrom",
    types: {
      RePermitWitnessTransferFrom: [
        { name: "permitted", type: "TokenPermissions" },
        { name: "spender", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
        { name: "witness", type: "Order" },
      ],
      Exchange: [
        { name: "adapter", type: "address" },
        { name: "ref", type: "address" },
        { name: "share", type: "uint32" },
        { name: "data", type: "bytes" },
      ],
      Input: [
        { name: "token", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "maxAmount", type: "uint256" },
      ],
      Order: [
        { name: "reactor", type: "address" },
        { name: "executor", type: "address" },
        { name: "exchange", type: "Exchange" },
        { name: "swapper", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "start", type: "uint256" },
        { name: "deadline", type: "uint256" },
        { name: "chainid", type: "uint256" },
        { name: "exclusivity", type: "uint32" },
        { name: "epoch", type: "uint32" },
        { name: "slippage", type: "uint32" },
        { name: "freshness", type: "uint32" },
        { name: "input", type: "Input" },
        { name: "output", type: "Output" },
      ],
      Output: [
        { name: "token", type: "address" },
        { name: "limit", type: "uint256" },
        { name: "triggerLower", type: "uint256" },
        { name: "triggerUpper", type: "uint256" },
        { name: "recipient", type: "address" },
      ],
      TokenPermissions: [
        { name: "token", type: "address" },
        { name: "amount", type: "uint256" },
      ],
    },
    message: {
      permitted: {
        token: "<INPUT_TOKEN>",
        amount: "<INPUT_MAX_AMOUNT>",
      },
      spender: requiredString(shared.reactor, 'config.json["*"].reactor'),
      nonce: "<NONCE>",
      deadline: "<DEADLINE>",
      witness: {
        reactor: requiredString(shared.reactor, 'config.json["*"].reactor'),
        executor: requiredString(shared.executor, 'config.json["*"].executor'),
        exchange: {
          adapter: "<ADAPTER>",
          ref: "0x0000000000000000000000000000000000000000",
          share: 0,
          data: "0x",
        },
        swapper: "<SWAPPER>",
        nonce: "<NONCE>",
        start: "<START>",
        deadline: "<DEADLINE>",
        chainid: "<CHAIN_ID>",
        exclusivity: 0,
        epoch: "<EPOCH_SECONDS>",
        slippage: "<SLIPPAGE_BPS>",
        freshness: 30,
        input: {
          token: "<INPUT_TOKEN>",
          amount: "<INPUT_AMOUNT>",
          maxAmount: "<INPUT_MAX_AMOUNT>",
        },
        output: {
          token: "<OUTPUT_TOKEN>",
          limit: "<OUTPUT_LIMIT>",
          triggerLower: "<OUTPUT_TRIGGER_LOWER>",
          triggerUpper: "<OUTPUT_TRIGGER_UPPER>",
          recipient: "<OUTPUT_RECIPIENT>",
        },
      },
    },
  };
}

function buildExamplesMarkdown(fullConfig) {
  const sections = EXAMPLE_SPECS.map((spec) => {
    return `## ${spec.title}\n\n\`\`\`json\n${JSON.stringify(buildExampleRelayPayload(fullConfig, spec), null, 2)}\n\`\`\``;
  });

  return [
    "# Examples",
    "",
    "These are mock final relay payloads.",
    "Copy the nearest shape, then replace addresses, amounts, timing, and signature.",
    "Mix limit, trigger, and delay fields as needed.",
    "",
    ...sections.flatMap((section) => [section, ""]),
    'If a signer returns `{ "r": "...", "s": "...", "v": "..." }` instead of one full signature string, send that object unchanged in the same `signature` field.',
    "",
  ].join("\n");
}

function buildExampleRelayPayload(fullConfig, spec) {
  const template = buildRepermitTemplate(fullConfig);
  const chainId = String(spec.chainId);

  return {
    order: {
      ...template.message,
      permitted: {
        token: spec.inputToken,
        amount: spec.inputMaxAmount,
      },
      nonce: spec.nonce,
      deadline: spec.deadline,
      witness: {
        ...template.message.witness,
        exchange: {
          ...template.message.witness.exchange,
          adapter: pickAdapter(chainId, fullConfig),
        },
        swapper: spec.swapper,
        nonce: spec.nonce,
        start: spec.start,
        deadline: spec.deadline,
        chainid: spec.chainId,
        epoch: spec.epoch,
        slippage: spec.slippage,
        input: {
          token: spec.inputToken,
          amount: spec.inputAmount,
          maxAmount: spec.inputMaxAmount,
        },
        output: {
          token: spec.outputToken,
          limit: spec.outputLimit,
          triggerLower: spec.outputTriggerLower,
          triggerUpper: spec.outputTriggerUpper,
          recipient: spec.outputRecipient ?? spec.swapper,
        },
      },
    },
    signature: spec.signature,
    status: "pending",
  };
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
    "     Normalized `## Config` JSON block with relay URL and per-chain adapters derived from config.json.",
    "  3. skill/assets/repermit.template.json",
    "     Auto-synced typed-data template with fixed protocol fields inlined from the canonical runtime config.",
    "  4. skill/references/examples.md",
    "     Auto-synced full mock relay payloads for common order shapes.",
    "  5. skill/package.json",
    "     Publish metadata for @orbs-network/spot-skill.",
    "  6. mcp/README.md",
    "     Auto-synced workspace README generated from the root README with repo-relative links rewritten to canonical GitHub URLs.",
    "  7. mcp/package.json",
    "     Synced publish metadata for @orbs-network/spot-mcp. Derived fields are overwritten; MCP-owned fields are preserved.",
    "  8. mcp/server.json",
    "     MCP registry metadata for io.github.orbs-network/spot.",
    "",
    "🧭 Rules",
    "  1. skill/SKILL.md remains the canonical skill surface, and sync rewrites only its machine-readable `## Config` block.",
    "  2. config.json is the source of truth for deployed addresses and adapter selection.",
    "  3. skill/assets/repermit.template.json is fully derived by sync; do not hand-edit it.",
    "  4. skill/references/examples.md is fully derived by sync; do not hand-edit it.",
    "  5. README.md is the source of truth for workspace package README copies in skill/ and mcp/.",
    "  6. mcp/package.json may retain MCP-owned fields such as pinned runtime dependencies.",
    "  7. Sync overwrites only derived fields in mcp/package.json.",
    "  8. The script is intentionally non-interactive and takes no mutation flags.",
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
