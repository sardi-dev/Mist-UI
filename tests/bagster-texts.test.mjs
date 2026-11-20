import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const LOCALE_FILE = join(REPO_ROOT, 'MistUI', 'Locales', 'enUS.lua');
const BAGSTER_FILE = join(REPO_ROOT, 'MistUI', 'modules', 'bagster', 'bagster.lua');

const LOCALE_KEY = /^L\["([^"]+)"\]\s*=/gm;
const LKEYS_TABLE = /^local LKEYS = \{\r?\n([\s\S]*?)^\}/m;
const LKEYS_ENTRY = /^\s*(\w+)\s*=\s*"([^"]*)",?\s*$/gm;

// The bag window looks its texts up through a key table, so the repository
// check cannot see them; a missing one only shows up in game as an error.
test('every bag window text has an English locale entry', () => {
  const texts = new Set();
  for (const match of readFileSync(LOCALE_FILE, 'utf8').matchAll(LOCALE_KEY)) {
    texts.add(match[1]);
  }

  const table = readFileSync(BAGSTER_FILE, 'utf8').match(LKEYS_TABLE);
  assert.ok(table, 'LKEYS table not found in bagster.lua');

  const entries = [...table[1].matchAll(LKEYS_ENTRY)];
  assert.ok(entries.length > 0, 'LKEYS table has no entries');

  const missing = entries
    .filter(([, , text]) => !texts.has(text))
    .map(([, key, text]) => `${key}: ${text}`);

  assert.deepEqual(missing, []);
});
