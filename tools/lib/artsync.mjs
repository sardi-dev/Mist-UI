// Artwork is not stored in this repository. This copies the texture files
// the addon needs from a local checkout of the upstream project into the
// git-ignored texture folders.

import { copyFileSync, existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const portable = (path) => path.replace(/\\/g, '/').toLowerCase();

/**
 * @param {{ copy: { from: string, to: string, exclude?: string[], include?: string[] }[] }} manifest
 *   exclude and include entries are folder or file paths relative to `from`;
 *   include brings back files that an exclude entry would skip
 * @param {string} sourceRoot checkout of the upstream project
 * @param {string} targetRoot this repository
 * @returns {{ from: string, to: string }[]} absolute file pairs
 */
export function planArtCopy(manifest, sourceRoot, targetRoot) {
  const plan = [];
  for (const rule of manifest.copy) {
    const fromDir = join(sourceRoot, rule.from);
    if (!existsSync(fromDir)) throw new Error(`Artwork source folder not found: ${fromDir}`);
    const excluded = (rule.exclude ?? []).map(portable);
    const included = (rule.include ?? []).map(portable);
    const matches = (key, entry) => key === entry || key.startsWith(`${entry}/`);
    for (const file of walk(fromDir)) {
      const rel = relative(fromDir, file);
      const key = portable(rel);
      if (excluded.some((entry) => matches(key, entry)) && !included.some((entry) => matches(key, entry))) continue;
      plan.push({ from: file, to: join(targetRoot, rule.to, rel) });
    }
  }
  return plan;
}

export function runArtCopy(plan) {
  for (const { from, to } of plan) {
    mkdirSync(dirname(to), { recursive: true });
    copyFileSync(from, to);
  }
  return plan.length;
}
