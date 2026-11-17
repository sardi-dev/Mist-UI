#!/usr/bin/env node
// Usage: node tools/check.mjs [--ui-source <dir>] [--deps]
// --deps also lists where loaded code reads addon fields that only parked
// (not yet ported) files define, so each use can be reviewed for a nil guard.
// The stock 5.4.8 interface source is looked up in --ui-source, then in the
// MISTUI_UI_SOURCE environment variable, then in ../ui-source-5.4.8.
// Without it the name checks are skipped and only files and syntax are checked.

import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkRepo, loadAllowlist } from './lib/checker.mjs';
import { buildStockIndex } from './lib/stockindex.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_UI_SOURCE = resolve(REPO_ROOT, '..', 'ui-source-5.4.8');
const ALLOWLIST_PATH = join(REPO_ROOT, 'tools', 'known-globals.txt');
const OWN_EVENT_PREFIX = 'MISTUI_';
// Local name of each translation table and the addon folder that defines its texts.
const LOCALE_TABLES = { L: 'MistUI', LO: 'MistUI_Options' };

const KIND_TITLES = {
  'missing-file': 'Files in the load list that do not exist',
  syntax: 'Lua syntax errors',
  'missing-locale-text': 'Interface texts with no entry in the English locale file',
  'too-many-locals': 'Functions over the limit of 200 local variables in scope (the client would not load the file)',
  'too-many-upvalues': 'Functions over the limit of 60 captured outer variables (the client would not load the file)',
  'bad-sublevel': 'Draw sublevels outside -8 to 7 (the client raises an error)',
  'unknown-global': 'Global names the 5.4.8 client does not know',
  'unknown-hook': 'Hooked functions the 5.4.8 client does not know',
  'unknown-event': 'Events the 5.4.8 client does not know',
  'unknown-template': 'Frame templates the 5.4.8 client does not know',
  'unknown-cvar': 'Console variables the 5.4.8 client does not know',
};

function findUiSource(argv) {
  const flag = argv.indexOf('--ui-source');
  const candidate = flag >= 0 ? argv[flag + 1] : process.env.MISTUI_UI_SOURCE ?? DEFAULT_UI_SOURCE;
  return candidate && existsSync(candidate) ? resolve(candidate) : null;
}

function main(argv) {
  const uiSource = findUiSource(argv);
  const stockIndex = uiSource ? buildStockIndex(uiSource) : null;
  const { problems, stats, parkedDependencies } = checkRepo({
    repoRoot: REPO_ROOT,
    stockIndex,
    allowlist: loadAllowlist(ALLOWLIST_PATH),
    ownEventPrefix: OWN_EVENT_PREFIX,
    localeTables: LOCALE_TABLES,
  });

  console.log(`Addons: ${stats.addons.join(', ')}`);
  console.log(`Lua files: ${stats.loadedLua} loaded, ${stats.parkedLua} parked (on disk, not loaded yet)`);
  console.log(
    stockIndex
      ? `Name checks: on (${stockIndex.identifiers.size} stock names; ${stats.derivedNames} names accepted as frame children)`
      : 'Name checks: SKIPPED, stock interface source not found',
  );

  for (const [kind, title] of Object.entries(KIND_TITLES)) {
    const group = problems.filter((problem) => problem.kind === kind);
    if (group.length === 0) continue;
    console.log(`\n${title} (${group.length}):`);
    for (const problem of group) {
      const where = problem.line ? `${problem.file}:${problem.line}` : problem.file;
      const uses = problem.uses > 1 ? ` (${problem.uses} uses)` : '';
      console.log(`  ${where}  ${problem.detail}${uses}`);
    }
  }

  if (argv.includes('--deps')) {
    console.log(`\nReads of addon fields that only parked files define (${parkedDependencies.length}):`);
    for (const dependency of parkedDependencies) {
      console.log(`  ${dependency.file}:${dependency.lines.join(',')}  addon.${dependency.field}  (defined in ${dependency.definedIn})`);
    }
  } else if (parkedDependencies.length > 0) {
    console.log(`\nNote: ${parkedDependencies.length} read(s) of addon fields that only parked files define. Run with --deps to list them.`);
  }

  if (problems.length > 0) {
    console.log(`\nFAILED: ${problems.length} problem(s).`);
    process.exitCode = 1;
  } else {
    console.log('\nOK: no problems found.');
  }
}

main(process.argv.slice(2));
