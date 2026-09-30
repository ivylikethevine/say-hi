// SPDX-License-Identifier: MIT
// Prettier's own Markdown parser with a preprocess step that writes the
// generated parts of a doc before it is formatted: each `## Contents` list,
// from the page's `##` and `###` headings, and the `## Every setting` table,
// from scripts/settings' rows. `prettier --write --plugin
// ./.github/prettier-plugin-docs.mjs` writes them, and the lint gate's
// `--check` with the same flag fails a doc whose list or table is stale, so a
// new heading or setting needs no edit of the doc. .prettierrc.yaml does not
// name the plugin: that file is kept byte-identical across repos.
import { readFileSync } from "node:fs";
import { parsers as markdownParsers } from "prettier/plugins/markdown";

const builtin = markdownParsers.markdown;

// The anchor the published site gives a heading: links reduced to their
// text, `*` and backticks dropped, lowercased, anything but [a-z0-9 _-]
// dropped, spaces to `-` - so ` - ` between words is `--`.
function anchor(text) {
  return text
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[*`]/g, "")
    .replace(/[A-Z]/g, (c) => c.toLowerCase())
    .replace(/[^a-z0-9 _-]/g, "")
    .trim()
    .replace(/ /g, "-");
}

// A heading's ATX level and text, or null; a fenced block's lines are its
// content, not the page's structure.
function headings(lines) {
  const out = [];
  let fence = null;
  lines.forEach((line, i) => {
    const f = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (f) {
      if (fence === null) fence = f[1][0];
      else if (f[1][0] === fence) fence = null;
      return;
    }
    if (fence !== null) return;
    const h = line.match(/^(#{1,6}) +(.*?)(?: +#+)? *$/);
    if (h) out.push({ line: i, level: h[1].length, text: h[2] });
  });
  return out;
}

function writeContents(text) {
  const lines = text.split("\n");
  const heads = headings(lines);
  const at = heads.findIndex((h) => h.level === 2 && h.text === "Contents");
  if (at < 0) return text;
  const list = heads
    .filter((h, i) => i !== at && (h.level === 2 || h.level === 3))
    .map((h) => {
      const label = h.text.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1");
      return `${h.level === 3 ? "  " : ""}- [${label}](#${anchor(h.text)})`;
    });
  // the list is what follows the heading, blank lines and list items; text
  // after it stays
  let end = heads[at].line + 1;
  while (end < lines.length && /^(\s*$|\s*[-*+] )/.test(lines[end])) end++;
  lines.splice(heads[at].line + 1, end - heads[at].line - 1, "", ...list, "");
  return lines.join("\n");
}

// The table under `## Every setting` whose header starts `| variable`, one
// line a row of scripts/settings: <section> | <name> | <default> | ... |
// <what it does>, its section giving the "set by" cell.
function writeSettings(text) {
  const lines = text.split("\n");
  const at = lines.indexOf("## Every setting");
  if (at < 0) return text;
  let start = at + 1;
  while (start < lines.length && !/^\| *variable *\|/.test(lines[start])) {
    if (/^## /.test(lines[start])) return text;
    start++;
  }
  if (start === lines.length) return text;
  let rows;
  try {
    rows = readFileSync(
      new URL("../scripts/settings", import.meta.url),
      "utf8",
    );
  } catch {
    return text;
  }
  const setBy = { advanced: "`hi --configure` advanced", you: "you" };
  const table = rows
    .split("\n")
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const c = l.split(" | ");
      const by = setBy[c[0]] ?? "`hi --configure`";
      return `| \`${c[1]}\` | ${c[2]} | ${by} | ${c.slice(8).join(" | ")} |`;
    });
  let end = start;
  while (end < lines.length && lines[end].startsWith("|")) end++;
  lines.splice(
    start,
    end - start,
    "| variable | default | set by | what it does |",
    "| --- | --- | --- | --- |",
    ...table,
  );
  return lines.join("\n");
}

export const parsers = {
  markdown: {
    ...builtin,
    preprocess(text, options) {
      const pre = builtin.preprocess ? builtin.preprocess(text, options) : text;
      return writeSettings(writeContents(pre));
    },
  },
};
