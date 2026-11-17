import assert from 'node:assert/strict';
import { dirname, join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkRepo, parseAllowlist } from '../tools/lib/checker.mjs';
import { parseToc, parseXmlFileRefs, resolveLoadList } from '../tools/lib/loadlist.mjs';
import { analyzeLua, LuaSyntaxError } from '../tools/lib/luaglobals.mjs';
import { buildStockIndex, createNameClassifier } from '../tools/lib/stockindex.mjs';

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), 'fixtures');
const ADDON_ROOT = join(FIXTURES, 'addon');
const SAMPLE_ADDON = join(ADDON_ROOT, 'Sample');
const STOCK_SOURCE = join(FIXTURES, 'stock');

const portable = (path) => path.replace(/\\/g, '/');

test('parseToc separates metadata, comments and files', () => {
  const toc = parseToc('## Interface: 50400\n## Title: X\n\n# note\na.lua\nsub\\b.xml\n');
  assert.deepEqual(toc.meta, { Interface: '50400', Title: 'X' });
  assert.deepEqual(toc.files, ['a.lua', 'sub\\b.xml']);
});

test('parseXmlFileRefs ignores commented-out entries', () => {
  const refs = parseXmlFileRefs('<Ui><!-- <Script file="old.lua"/> --><Script file="a.lua"/><Include file="b.xml"/></Ui>');
  assert.deepEqual(refs, ['a.lua', 'b.xml']);
});

test('resolveLoadList follows includes in load order and reports missing and parked files', () => {
  const list = resolveLoadList(SAMPLE_ADDON);
  const names = (files) => files.map((file) => portable(relative(SAMPLE_ADDON, file)));
  assert.deepEqual(names(list.lua), ['first.lua', 'sub/second.lua', 'third.lua']);
  assert.deepEqual(names(list.xml), ['sub/load.xml', 'sub/more.xml']);
  assert.deepEqual(list.missing.map((miss) => miss.ref), ['gone.lua']);
  assert.deepEqual(names(list.parked).sort(), ['parked.lua', 'sub/parked_broken.lua']);
});

test('analyzeLua tells globals from locals and field names', () => {
  const { reads, writes } = analyzeLua(
    ['local a = GlobalRead', 'local t = { key = 1 }', 't.field = a', 'GlobalWrite = t.other', 'function GlobalFn(param) return param end'].join('\n'),
  );
  assert.deepEqual([...reads.keys()], ['GlobalRead']);
  assert.deepEqual([...writes.keys()].sort(), ['GlobalFn', 'GlobalWrite']);
});

test('analyzeLua treats writes through _G as global writes', () => {
  const { reads, writes } = analyzeLua('_G.Dotted = 1\n_G["Quoted"] = 2\n');
  assert.deepEqual([...writes.keys()].sort(), ['Dotted', 'Quoted']);
  assert.equal(reads.size, 0);
});

test('analyzeLua tracks reads and writes of addon table fields', () => {
  const { fieldReads, fieldWrites } = analyzeLua(
    ['local addon = select(2, ...)', 'addon.Value = 1', 'function addon.Fn() end', 'function addon:Method() end', 'local x = addon.Other', 'addon.Nested.deep = 2'].join('\n'),
  );
  assert.deepEqual([...fieldWrites.keys()].sort(), ['Fn', 'Method', 'Value']);
  assert.deepEqual([...fieldReads.keys()].sort(), ['Nested', 'Other']);
});

test('analyzeLua collects events and frame templates', () => {
  const { events, templates } = analyzeLua(
    'local f = CreateFrame("Frame", nil, UIParent, "A, B")\nf:RegisterEvent("SOME_EVENT")\nf:RegisterUnitEvent("UNIT_EVENT", "player")\n',
  );
  assert.deepEqual(events.map((event) => event.name), ['SOME_EVENT', 'UNIT_EVENT']);
  assert.deepEqual(templates.map((template) => template.name), ['A', 'B']);
});

test('analyzeLua accepts a byte order mark and reports syntax errors with a line', () => {
  const decodedMark = String.fromCharCode(0xfeff);
  const rawMarkBytes = String.fromCharCode(0xef, 0xbb, 0xbf);
  assert.doesNotThrow(() => analyzeLua(`${decodedMark}local x = 1`));
  assert.doesNotThrow(() => analyzeLua(`${rawMarkBytes}local x = 1`));
  assert.throws(
    () => analyzeLua('local ok = 1\nlocal broken = = 1'),
    (error) => error instanceof LuaSyntaxError && error.line === 2,
  );
});

test('stock index classifies known, derived and unknown names', () => {
  const classify = createNameClassifier(buildStockIndex(STOCK_SOURCE), new Set(['OwnName']));
  assert.equal(classify('UnitHealth'), 'known');
  assert.equal(classify('ActionButton1'), 'known');
  assert.equal(classify('OwnName'), 'known');
  assert.equal(classify('ActionButton1Icon'), 'derived');
  assert.equal(classify('RemovedFunction'), 'unknown');
  assert.equal(classify('Icon'), 'unknown');
});

test('parseAllowlist reads names and drops reasons', () => {
  assert.deepEqual([...parseAllowlist('A # why\n\n# only a comment\nB\n')], ['A', 'B']);
});

test('checkRepo reports only real problems in loaded files', () => {
  const { problems, stats } = checkRepo({
    repoRoot: ADDON_ROOT,
    stockIndex: buildStockIndex(STOCK_SOURCE),
    ownEventPrefix: 'SAMPLE_',
  });
  const found = problems.map((problem) => `${problem.kind}:${problem.detail.split(/[\\/]/).pop()}`).sort();
  assert.deepEqual(found.filter((entry) => !entry.startsWith('syntax:')), [
    'missing-file:gone.lua',
    'unknown-cvar:removedCVar',
    'unknown-event:OLD_REMOVED_EVENT',
    'unknown-global:RemovedFunction',
    'unknown-template:MissingTemplate',
  ]);
  const syntax = problems.filter((problem) => problem.kind === 'syntax');
  assert.deepEqual(syntax.map((problem) => portable(problem.file)), ['Sample/sub/parked_broken.lua']);
  assert.deepEqual(stats, { addons: ['Sample'], loadedLua: 3, parkedLua: 2, derivedNames: 1 });
});

test('checkRepo lists loaded code that reads fields only parked files define', () => {
  const { parkedDependencies } = checkRepo({ repoRoot: ADDON_ROOT, stockIndex: null });
  assert.deepEqual(
    parkedDependencies.map((dependency) => ({ ...dependency, file: portable(dependency.file), definedIn: portable(dependency.definedIn) })),
    [{ file: 'Sample/first.lua', lines: [12, 12], field: 'ParkedThing', definedIn: 'Sample/parked.lua' }],
  );
});

test('checkRepo reports interface texts that the locale file does not define', () => {
  const { problems } = checkRepo({
    repoRoot: join(FIXTURES, 'locale'),
    stockIndex: null,
    localeTables: { L: 'Texts' },
  });
  assert.deepEqual(
    problems.map((problem) => ({ kind: problem.kind, file: portable(problem.file), line: problem.line, detail: problem.detail })),
    [{ kind: 'missing-locale-text', file: 'Texts/main.lua', line: 2, detail: 'L["Missing text"]' }],
  );
});

test('checkRepo skips name checks without a stock index and honours the allowlist', () => {
  const withoutStock = checkRepo({ repoRoot: ADDON_ROOT, stockIndex: null });
  assert.deepEqual(withoutStock.problems.map((problem) => problem.kind).sort(), ['missing-file', 'syntax']);

  const allowed = checkRepo({
    repoRoot: ADDON_ROOT,
    stockIndex: buildStockIndex(STOCK_SOURCE),
    allowlist: new Set(['RemovedFunction', 'OLD_REMOVED_EVENT']),
    ownEventPrefix: 'SAMPLE_',
  });
  assert.deepEqual(
    allowed.problems.map((problem) => problem.kind).sort(),
    ['missing-file', 'syntax', 'unknown-cvar', 'unknown-template'],
  );
});
