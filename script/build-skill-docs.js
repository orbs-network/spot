const { copyFile, mkdir, readdir, readFile, rm, writeFile } = require("node:fs/promises");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const docsRoot = path.join(repoRoot, "docs");
const skillRoot = path.join(repoRoot, "skills", "advanced-swap-orders");
const mirrorRoot = path.join(docsRoot, "advanced-swap-orders");
const repoBlobBase = "https://github.com/orbs-network/spot/blob/master/skills/advanced-swap-orders/";
const rootSourceRel = "SKILL.md";
const rootPageLabel = "SKILL.md";
const rawAssetOrder = {
  "scripts/skill.config.json": 0,
  "scripts/order.sh": 1,
  "assets/repermit.skeleton.json": 2,
  "assets/web3-sign-and-submit.example.js": 3,
};

async function main() {
  const { marked } = await import("marked");
  marked.setOptions({ gfm: true, breaks: false });

  const sourceFiles = await listFiles(skillRoot);
  const markdownFiles = sourceFiles.filter((file) => file.endsWith(".md")).sort();
  const assetFiles = sourceFiles.filter((file) => !file.endsWith(".md")).sort();
  const docsPages = markdownFiles.map((sourceRel) => ({
    sourceRel,
    title: pageLabel(sourceRel),
    filePath: pagePathFor(sourceRel),
  })).sort((left, right) => pageRank(left.sourceRel) - pageRank(right.sourceRel) || left.sourceRel.localeCompare(right.sourceRel));
  const rawAssets = assetFiles.map((sourceRel) => ({
    sourceRel,
    title: path.basename(sourceRel),
    filePath: rawAssetPathFor(sourceRel),
  })).sort((left, right) => assetRank(left.sourceRel) - assetRank(right.sourceRel) || left.sourceRel.localeCompare(right.sourceRel));

  await mkdir(docsRoot, { recursive: true });
  await rm(mirrorRoot, { recursive: true, force: true });
  await writeFile(path.join(docsRoot, ".nojekyll"), "");

  for (const asset of rawAssets) {
    const outputPath = path.join(docsRoot, asset.filePath);
    await mkdir(path.dirname(outputPath), { recursive: true });
    await copyFile(path.join(skillRoot, asset.sourceRel), outputPath);
  }

  for (const page of docsPages) {
    const raw = await readFile(path.join(skillRoot, page.sourceRel), "utf8");
    const { body, frontMatter } = splitFrontMatter(raw);
    const heading = firstHeading(body) || path.basename(page.sourceRel, path.extname(page.sourceRel));
    const html = marked.parse(body, { async: false, renderer: createRenderer(marked, page.sourceRel) });
    const outputPath = path.join(docsRoot, page.filePath);

    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, renderPage({
      currentSourceRel: page.sourceRel,
      pageTitle: page.sourceRel === rootSourceRel ? `${heading} | Spot` : `${heading} | Advanced Swap Orders | Spot`,
      pageDescription: frontMatter.description || firstParagraph(body) || heading,
      heading,
      bodyHtml: html,
      docsPages,
      rawAssets,
      sourceUrl: sourceUrlFor(page.sourceRel),
    }));
  }
}

function createRenderer(marked, currentSourceRel) {
  const renderer = new marked.Renderer();

  renderer.link = function ({ href, title, tokens }) {
    const text = this.parser.parseInline(tokens);
    const attrs = [`href="${escapeHtmlAttr(rewriteHref(currentSourceRel, href))}"`];

    if (title) {
      attrs.push(`title="${escapeHtmlAttr(title)}"`);
    }

    return `<a ${attrs.join(" ")}>${text}</a>`;
  };

  return renderer;
}

function rewriteHref(currentSourceRel, href) {
  if (!href || href.startsWith("#")) {
    return href;
  }

  const { target, suffix } = splitHref(href);
  const sourceRel = toSourceRel(currentSourceRel, target);

  if (!sourceRel) {
    return href;
  }

  return `${relativeHref(pagePathFor(currentSourceRel), outputPathFor(sourceRel))}${suffix}`;
}

function toSourceRel(currentSourceRel, href) {
  const githubRawMatch = href.match(/^https:\/\/raw\.githubusercontent\.com\/orbs-network\/spot\/[^/]+\/skills\/advanced-swap-orders\/(.+)$/);
  if (githubRawMatch) {
    return githubRawMatch[1];
  }

  if (/^(?:[a-z]+:)?\/\//i.test(href) || href.startsWith("mailto:")) {
    return null;
  }

  const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(toPosix(currentSourceRel)), href));
  return resolved.startsWith("../") || resolved === ".." ? null : resolved;
}

function splitHref(href) {
  const hashIndex = href.indexOf("#");
  const queryIndex = href.indexOf("?");
  const splitIndex = hashIndex >= 0 && queryIndex >= 0 ? Math.min(hashIndex, queryIndex) : Math.max(hashIndex, queryIndex);

  return splitIndex < 0
    ? { target: href, suffix: "" }
    : { target: href.slice(0, splitIndex), suffix: href.slice(splitIndex) };
}

function splitFrontMatter(raw) {
  if (!raw.startsWith("---\n")) {
    return { frontMatter: {}, body: raw };
  }

  const end = raw.indexOf("\n---\n", 4);
  if (end < 0) {
    return { frontMatter: {}, body: raw };
  }

  const frontMatter = {};
  for (const line of raw.slice(4, end).split("\n")) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (match) {
      frontMatter[match[1]] = match[2].trim();
    }
  }

  return {
    frontMatter,
    body: raw.slice(end + 5).replace(/^\n/, ""),
  };
}

function firstHeading(markdown) {
  const match = markdown.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : "";
}

function firstParagraph(markdown) {
  const paragraphs = markdown
    .split("\n\n")
    .map((chunk) => chunk.trim())
    .filter(Boolean);

  for (const paragraph of paragraphs) {
    if (!/^(#|```|\d+\.\s|- )/.test(paragraph)) {
      return paragraph.replace(/\s+/g, " ");
    }
  }

  return "";
}

function renderPage({ currentSourceRel, pageTitle, pageDescription, heading, bodyHtml, docsPages, rawAssets, sourceUrl }) {
  const currentPagePath = pagePathFor(currentSourceRel);
  const docsLinks = docsPages.map((page) => {
    const current = page.sourceRel === currentSourceRel ? ' aria-current="page"' : "";
    return `<li><a href="${escapeHtmlAttr(relativeHref(currentPagePath, page.filePath))}"${current}>${escapeHtml(page.title)}</a></li>`;
  }).join("\n");
  const assetLinks = rawAssets.map((asset) => `<li><a href="${escapeHtmlAttr(relativeHref(currentPagePath, asset.filePath))}">${escapeHtml(asset.title)}</a></li>`).join("\n");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(pageTitle)}</title>
  <meta name="description" content="${escapeHtmlAttr(pageDescription)}">
  <style>
    :root {
      color-scheme: light;
      --paper: #f7f1e3;
      --ink: #1f1a17;
      --muted: #6a5f57;
      --line: rgba(31, 26, 23, 0.12);
      --accent: #9d3c23;
      --accent-soft: rgba(157, 60, 35, 0.12);
      font-family: "Avenir Next", "Segoe UI", Helvetica, Arial, sans-serif;
      background: linear-gradient(180deg, #efe2c0 0%, #f7f1e3 18%, #fcfaf3 100%);
      color: var(--ink);
    }

    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; color: var(--ink); background: transparent; }
    a { color: var(--accent); text-decoration-thickness: 0.08em; text-underline-offset: 0.18em; }
    a:hover { text-decoration-thickness: 0.12em; }
    code, pre { font-family: "SF Mono", "JetBrains Mono", Menlo, Consolas, monospace; }
    .layout { width: min(1180px, calc(100vw - 32px)); margin: 0 auto; padding: 28px 0 40px; display: grid; gap: 20px; grid-template-columns: minmax(0, 290px) minmax(0, 1fr); align-items: start; }
    .panel { background: rgba(255, 250, 240, 0.92); border: 1px solid var(--line); border-radius: 20px; box-shadow: 0 18px 40px rgba(42, 28, 18, 0.08); }
    .sidebar { position: sticky; top: 20px; padding: 22px; }
    .eyebrow { display: inline-block; padding: 6px 10px; border-radius: 999px; background: var(--accent-soft); color: var(--accent); font-size: 0.78rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
    .sidebar h1 { margin: 16px 0 10px; font-size: 1.55rem; line-height: 1.1; }
    .sidebar p { margin: 0 0 16px; color: var(--muted); line-height: 1.5; }
    .nav-group + .nav-group { margin-top: 20px; padding-top: 20px; border-top: 1px solid var(--line); }
    .nav-group h2 { margin: 0 0 10px; font-size: 0.92rem; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
    .nav-group ol { margin: 0; padding-left: 20px; display: grid; gap: 8px; }
    .nav-group a[aria-current="page"] { font-weight: 700; }
    .content { padding: 28px; }
    .crumbs { margin: 0 0 12px; color: var(--muted); font-size: 0.92rem; }
    .content h1:first-child { margin-top: 0; font-size: clamp(2rem, 4vw, 3rem); line-height: 0.95; letter-spacing: -0.02em; }
    .content h2, .content h3 { margin-top: 1.8em; line-height: 1.15; }
    .content p, .content li { font-size: 1.03rem; line-height: 1.68; }
    .content ol, .content ul { padding-left: 1.5rem; }
    .content pre { overflow-x: auto; padding: 16px; border-radius: 14px; border: 1px solid var(--line); background: #fffdf8; }
    .content code { padding: 0.12em 0.32em; border-radius: 0.36em; background: rgba(31, 26, 23, 0.08); font-size: 0.92em; }
    .content pre code { padding: 0; background: transparent; }
    .source-note { margin-top: 30px; padding-top: 18px; border-top: 1px solid var(--line); color: var(--muted); font-size: 0.92rem; word-break: break-word; }
    @media (max-width: 920px) {
      .layout { width: min(100vw - 24px, 100%); padding-top: 16px; grid-template-columns: 1fr; }
      .sidebar { position: static; }
      .content { padding: 22px; }
    }
  </style>
</head>
<body>
  <div class="layout">
    <aside class="sidebar panel">
      <span class="eyebrow">GitHub Pages Mirror</span>
      <h1>Advanced Swap Orders</h1>
      <div class="nav-group">
        <h2>Documentation</h2>
        <ol>
          ${docsLinks}
        </ol>
      </div>
      <div class="nav-group">
        <h2>Raw Files</h2>
        <ol>
          ${assetLinks}
        </ol>
      </div>
    </aside>
    <main class="content panel">
      <p class="crumbs"><a href="${escapeHtmlAttr(relativeHref(currentPagePath, pagePathFor(rootSourceRel)))}">${escapeHtml(rootPageLabel)}</a> / ${escapeHtml(heading)}</p>
      <article class="doc">
        ${bodyHtml}
      </article>
      <p class="source-note">Source: <a href="${escapeHtmlAttr(sourceUrl)}">${escapeHtml(sourceUrl)}</a></p>
    </main>
  </div>
</body>
</html>
`;
}

function pageLabel(sourceRel) {
  if (sourceRel === rootSourceRel) {
    return rootPageLabel;
  }

  return path.basename(sourceRel, path.extname(sourceRel))
    .replace(/^\d+-/, "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function pageRank(sourceRel) {
  if (sourceRel === rootSourceRel) return 0;
  if (sourceRel.startsWith("references/")) return 1;
  if (sourceRel.startsWith("assets/")) return 2;
  return 3;
}

function assetRank(sourceRel) {
  return rawAssetOrder[sourceRel] ?? Number.MAX_SAFE_INTEGER;
}

function sourceUrlFor(sourceRel) {
  return `${repoBlobBase}${sourceRel}`;
}

function outputPathFor(sourceRel) {
  return sourceRel.endsWith(".md") ? pagePathFor(sourceRel) : rawAssetPathFor(sourceRel);
}

function pagePathFor(sourceRel) {
  return sourceRel === rootSourceRel
    ? "index.html"
    : path.join("advanced-swap-orders", sourceRel.slice(0, -path.extname(sourceRel).length), "index.html");
}

function rawAssetPathFor(sourceRel) {
  return path.join("advanced-swap-orders", sourceRel);
}

function relativeHref(fromFilePath, toFilePath) {
  return path.posix.relative(path.posix.dirname(toPosix(fromFilePath)), toPosix(toFilePath)) || "index.html";
}

function escapeHtml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function escapeHtmlAttr(value) {
  return escapeHtml(value).replaceAll('"', "&quot;");
}

function toPosix(filePath) {
  return filePath.split(path.sep).join(path.posix.sep);
}

async function listFiles(rootDir, prefix = "") {
  const entries = await readdir(path.join(rootDir, prefix), { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const relativePath = path.join(prefix, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listFiles(rootDir, relativePath));
    } else if (entry.isFile()) {
      files.push(relativePath);
    }
  }

  return files;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
