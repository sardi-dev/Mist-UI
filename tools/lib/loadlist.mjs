// Resolves which files the game client loads for an addon: the TOC lists
// Lua and XML files, and XML files pull in more through <Script> and <Include>.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';

const TOC_COMMENT = /^\s*#/;
const TOC_META = /^##\s*([^:]+):\s*(.*)$/;
const XML_COMMENT = /<!--[\s\S]*?-->/g;
const XML_FILE_REF = /<(Script|Include)\b[^>]*?\bfile\s*=\s*"([^"]+)"/gi;

export function parseToc(text) {
  const meta = {};
  const files = [];
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === '') continue;
    const metaMatch = line.match(TOC_META);
    if (metaMatch) {
      meta[metaMatch[1].trim()] = metaMatch[2].trim();
      continue;
    }
    if (TOC_COMMENT.test(line)) continue;
    files.push(line);
  }
  return { meta, files };
}

export function parseXmlFileRefs(text) {
  const refs = [];
  const withoutComments = text.replace(XML_COMMENT, '');
  for (const match of withoutComments.matchAll(XML_FILE_REF)) {
    refs.push(match[2]);
  }
  return refs;
}

// The client accepts both slashes; normalise to the host separator.
function toHostPath(baseDir, ref) {
  return resolve(baseDir, ref.replace(/\\/g, '/'));
}

function walkFiles(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walkFiles(full, out);
    else out.push(full);
  }
  return out;
}

/**
 * @param {string} addonDir folder that holds <name>.toc
 * @returns {{ toc: object, lua: string[], xml: string[], missing: {from: string, ref: string}[], parked: string[] }}
 *   lua and xml are absolute paths in load order; parked are Lua and XML files
 *   on disk that nothing loads.
 */
export function resolveLoadList(addonDir) {
  const root = resolve(addonDir);
  const tocName = readdirSync(root).find((name) => name.toLowerCase().endsWith('.toc'));
  if (!tocName) throw new Error(`No .toc file in ${root}`);
  const tocPath = join(root, tocName);
  const toc = parseToc(readFileSync(tocPath, 'utf8'));

  const lua = [];
  const xml = [];
  const missing = [];
  const seen = new Set();

  const visit = (file, from) => {
    const key = file.toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    if (!existsSync(file)) {
      missing.push({ from: relative(root, from), ref: relative(root, file) });
      return;
    }
    if (key.endsWith('.xml')) {
      xml.push(file);
      for (const ref of parseXmlFileRefs(readFileSync(file, 'utf8'))) {
        visit(toHostPath(dirname(file), ref), file);
      }
    } else {
      lua.push(file);
    }
  };

  for (const ref of toc.files) visit(toHostPath(root, ref), tocPath);

  const parked = walkFiles(root)
    .filter((file) => /\.(lua|xml)$/i.test(file) && !seen.has(file.toLowerCase()))
    .filter((file) => file.toLowerCase() !== join(root, 'Bindings.xml').toLowerCase());

  return { toc, tocPath, lua, xml, missing, parked };
}
