// Checks the addon folders: every file in the load list exists, every Lua
// file parses and stays inside the compiler's limits, and loaded code only
// uses names and draw sublevels the 5.4.8 client knows.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { resolveLoadList } from './loadlist.mjs';
import { MAX_LOCALS, MAX_UPVALUES } from './lualimits.mjs';
import { analyzeLua, LuaSyntaxError } from './luaglobals.mjs';
import { collectXmlNames, createNameClassifier } from './stockindex.mjs';

const ALLOWLIST_COMMENT = '#';
const LOCALES_FOLDER = 'Locales';
const LIBRARIES_FOLDER = 'libs';
const SAVED_VARIABLE_KEYS = ['SavedVariables', 'SavedVariablesPerCharacter'];
// The 5.4.8 client raises an error for a draw sublevel outside this range.
const MIN_SUBLEVEL = -8;
const MAX_SUBLEVEL = 7;

export function findAddonDirs(repoRoot) {
  return readdirSync(repoRoot)
    .map((name) => join(repoRoot, name))
    .filter((dir) => statSync(dir).isDirectory())
    .filter((dir) => readdirSync(dir).some((name) => name.toLowerCase().endsWith('.toc')));
}

// One name per line; text after '#' is the reason it was verified by hand.
export function parseAllowlist(text) {
  const names = new Set();
  for (const line of text.split(/\r?\n/)) {
    const name = line.split(ALLOWLIST_COMMENT)[0].trim();
    if (name) names.add(name);
  }
  return names;
}

// Fields of the shared addon table that loaded code reads but only parked
// files define. Each use needs a nil guard until its module is ported.
function findParkedDependencies(loaded, parked, repoRoot) {
  const definedByLoaded = new Set();
  for (const { analysis } of loaded) {
    for (const name of analysis.fieldWrites.keys()) definedByLoaded.add(name);
  }
  const definedByParked = new Map();
  for (const { file, analysis } of parked) {
    for (const name of analysis.fieldWrites.keys()) {
      if (!definedByParked.has(name)) definedByParked.set(name, relative(repoRoot, file));
    }
  }
  const dependencies = [];
  for (const { file, analysis } of loaded) {
    for (const [name, lines] of analysis.fieldReads) {
      if (definedByLoaded.has(name) || !definedByParked.has(name)) continue;
      dependencies.push({ file: relative(repoRoot, file), lines, field: name, definedIn: definedByParked.get(name) });
    }
  }
  return dependencies;
}

function analyzeFile(file, problems, repoRoot) {
  try {
    return analyzeLua(readFileSync(file, 'latin1'));
  } catch (error) {
    if (!(error instanceof LuaSyntaxError)) throw error;
    problems.push({ kind: 'syntax', file: relative(repoRoot, file), line: error.line, detail: error.message });
    return null;
  }
}

/**
 * @param {object} options
 * @param {string} options.repoRoot
 * @param {object|null} options.stockIndex result of buildStockIndex, or null to skip name checks
 * @param {Set<string>} [options.allowlist] names verified by hand
 * @param {string} [options.ownEventPrefix] prefix of the addon's own message names
 * @param {Record<string, string>} [options.localeTables] local name of a translation table
 *   (for example "L") mapped to the addon folder whose Locales files define its texts
 * @returns {{ problems: object[], stats: object, parkedDependencies: object[] }}
 */
export function checkRepo({ repoRoot, stockIndex, allowlist = new Set(), ownEventPrefix = '', localeTables = {} }) {
  const problems = [];
  const stats = { addons: [], loadedLua: 0, parkedLua: 0, derivedNames: 0 };
  const loaded = [];
  const parked = [];
  const ownNames = new Set(allowlist);
  const ownTemplates = new Set();
  const localeTexts = new Map(); // addon folder -> texts its loaded Locales files define

  for (const addonDir of findAddonDirs(repoRoot)) {
    const list = resolveLoadList(addonDir);
    const addonName = relative(repoRoot, addonDir);
    stats.addons.push(addonName);
    localeTexts.set(addonName, new Set());
    for (const miss of list.missing) {
      problems.push({ kind: 'missing-file', file: join(relative(repoRoot, addonDir), miss.from), detail: miss.ref });
    }
    for (const key of SAVED_VARIABLE_KEYS) {
      for (const name of (list.toc.meta[key] ?? '').split(',')) {
        if (name.trim()) ownNames.add(name.trim());
      }
    }
    for (const file of list.xml) {
      collectXmlNames(readFileSync(file, 'utf8'), ownNames, new Set());
    }
    for (const file of list.lua) {
      const analysis = analyzeFile(file, problems, repoRoot);
      if (!analysis) continue;
      loaded.push({ file, analysis });
      if (relative(addonDir, file).split(sep).includes(LOCALES_FOLDER)) {
        for (const text of analysis.localeDefs) localeTexts.get(addonName).add(text);
      }
    }
    for (const file of list.parked) {
      if (!file.toLowerCase().endsWith('.lua')) continue;
      stats.parkedLua += 1;
      const analysis = analyzeFile(file, problems, repoRoot);
      if (analysis) parked.push({ file, analysis });
    }
  }
  stats.loadedLua = loaded.length;
  for (const name of ownNames) ownTemplates.add(name);

  for (const { analysis } of loaded) {
    for (const name of analysis.writes.keys()) ownNames.add(name);
  }

  // The translation library reports an error for every text that has no entry.
  // Bundled libraries keep translation tables of their own under the same local names.
  for (const { file, analysis } of loaded) {
    if (relative(repoRoot, file).split(sep).includes(LIBRARIES_FOLDER)) continue;
    const reported = new Set();
    for (const use of analysis.localeUses) {
      const texts = localeTexts.get(localeTables[use.table]);
      if (!texts || texts.has(use.key) || reported.has(use.key)) continue;
      reported.add(use.key);
      problems.push({ kind: 'missing-locale-text', file: relative(repoRoot, file), line: use.line, detail: `${use.table}["${use.key}"]` });
    }
  }

  // Neither check needs the stock source: both are rules of the client itself.
  for (const { file, analysis } of loaded) {
    const rel = relative(repoRoot, file);
    for (const fn of analysis.limits) {
      if (fn.locals > MAX_LOCALS) {
        problems.push({ kind: 'too-many-locals', file: rel, line: fn.line, detail: `${fn.name}: ${fn.locals} of ${MAX_LOCALS}` });
      }
      if (fn.upvalues > MAX_UPVALUES) {
        problems.push({ kind: 'too-many-upvalues', file: rel, line: fn.line, detail: `${fn.name}: ${fn.upvalues} of ${MAX_UPVALUES}` });
      }
    }
    for (const sublevel of analysis.sublevels) {
      if (sublevel.value < MIN_SUBLEVEL || sublevel.value > MAX_SUBLEVEL) {
        problems.push({ kind: 'bad-sublevel', file: rel, line: sublevel.line, detail: String(sublevel.value) });
      }
    }
  }

  if (stockIndex) {
    const classify = createNameClassifier(stockIndex, ownNames);
    for (const { file, analysis } of loaded) {
      const rel = relative(repoRoot, file);
      for (const [name, lines] of analysis.reads) {
        const verdict = classify(name);
        if (verdict === 'derived') stats.derivedNames += 1;
        if (verdict === 'unknown') problems.push({ kind: 'unknown-global', file: rel, line: lines[0], detail: name, uses: lines.length });
      }
      for (const hook of analysis.hooks) {
        if (classify(hook.name) === 'unknown') {
          problems.push({ kind: 'unknown-hook', file: rel, line: hook.line, detail: hook.name });
        }
      }
      for (const event of analysis.events) {
        const isOwn = ownEventPrefix !== '' && event.name.startsWith(ownEventPrefix);
        if (!isOwn && !stockIndex.uppercaseStrings.has(event.name) && !allowlist.has(event.name)) {
          problems.push({ kind: 'unknown-event', file: rel, line: event.line, detail: event.name });
        }
      }
      for (const cvar of analysis.cvars) {
        if (!stockIndex.cvars.has(cvar.name.toLowerCase()) && !allowlist.has(cvar.name)) {
          problems.push({ kind: 'unknown-cvar', file: rel, line: cvar.line, detail: cvar.name });
        }
      }
      for (const template of analysis.templates) {
        if (!stockIndex.xmlNames.has(template.name) && !ownTemplates.has(template.name)) {
          problems.push({ kind: 'unknown-template', file: rel, line: template.line, detail: template.name });
        }
      }
    }
  }
  return { problems, stats, parkedDependencies: findParkedDependencies(loaded, parked, repoRoot) };
}

export function loadAllowlist(path) {
  return existsSync(path) ? parseAllowlist(readFileSync(path, 'utf8')) : new Set();
}
