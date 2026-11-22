import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkRepo } from '../tools/lib/checker.mjs';
import { analyzeLua } from '../tools/lib/luaglobals.mjs';

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), 'fixtures');

const usedKeys = (source) => analyzeLua(source).localeUses.map((use) => `${use.table}:${use.key}`).sort();

test('a helper that returns L[parameter] makes its string arguments interface texts', () => {
  const keys = usedKeys(
    ['local function Tr(a, b) return L[b] or a end', 'print(Tr("fallback", "Used key"), Tr("x"))', 'local function Other(key) return key end', 'Other("Not a text")'].join('\n'),
  );
  assert.deepEqual(keys, ['L:Used key']);
});

test('helpers are found by body when assigned to a local or a global', () => {
  const keys = usedKeys(
    ['local Local = function(key) return LO[key] end', 'function Global(key) return LO[key] end', 'Local("First") Global("Second")'].join('\n'),
  );
  assert.deepEqual(keys, ['LO:First', 'LO:Second']);
});

test('the values of a key table are texts when the table feeds a lookup', () => {
  const keys = usedKeys(
    ['local KEYS = { One = "First", Two = "Second" }', 'local UNUSED = { Three = "Third" }', 'local function Get(name) local k = KEYS[name] return k and addon.L[k] end'].join('\n'),
  );
  assert.deepEqual(keys, ['L:First', 'L:Second']);
});

test('a key table read directly inside the lookup counts too', () => {
  assert.deepEqual(usedKeys('local KEYS = { A = "Alpha" }\nprint(LO[KEYS[name]])'), ['LO:Alpha']);
});

test('a field used as key makes that field of table rows a text', () => {
  const keys = usedKeys(
    ['local ROWS = { { label = "Core", other = "Skip" }, { label = "Bars", other = "Skip" } }', 'for _, row in ipairs(ROWS) do print(LO[row.label]) end', 'Draw({ label = "Not a row" })'].join('\n'),
  );
  assert.deepEqual(keys, ['LO:Bars', 'LO:Core']);
});

test('a field passed to a helper is followed to the rows that define it', () => {
  const keys = usedKeys(
    ['local function Str(g, key) return _G[g] or LO[key] end', 'local ROWS = { { labelKey = "Pets" } }', 'for _, sub in ipairs(ROWS) do Str("X", sub.labelKey) end'].join('\n'),
  );
  assert.deepEqual(keys, ['LO:Pets']);
});

test('checkRepo reports missing texts behind helpers, key tables and rows', () => {
  const { problems } = checkRepo({
    repoRoot: join(FIXTURES, 'locale-indirect'),
    stockIndex: null,
    localeTables: { L: 'Flow' },
  });
  assert.deepEqual(
    problems.map((problem) => problem.detail).sort(),
    ['L["Missing helper text"]', 'L["Missing row text"]', 'L["Missing table text"]'],
  );
});
