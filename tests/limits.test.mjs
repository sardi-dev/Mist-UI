import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { checkRepo } from '../tools/lib/checker.mjs';
import { MAX_LOCALS, MAX_UPVALUES } from '../tools/lib/lualimits.mjs';
import { analyzeLua } from '../tools/lib/luaglobals.mjs';

const locals = (count, prefix = 'v') =>
  Array.from({ length: count }, (_, index) => `local ${prefix}${index} = ${index}`).join('\n');

const byName = (source) => new Map(analyzeLua(source).limits.map((fn) => [fn.name, fn]));

test('limits count the local variables in scope at file level', () => {
  assert.equal(byName(locals(5)).get('(file level)').locals, 5);
  assert.equal(byName('local a, b, c = 1, 2, 3\nlocal function f() end').get('(file level)').locals, 4);
});

test('limits release the variables of a closed block', () => {
  const source = `do\n${locals(10, 'a')}\nend\ndo\n${locals(4, 'b')}\nend\nlocal last = 1`;
  assert.equal(byName(source).get('(file level)').locals, 10);
});

test('limits count a loop variable and the three hidden ones of its loop', () => {
  assert.equal(byName('for i = 1, 2 do local x = i end').get('(file level)').locals, 5);
  assert.equal(byName('for k, v in pairs({}) do end').get('(file level)').locals, 5);
});

test('limits count parameters and the implicit self of a method', () => {
  const functions = byName('local t = {}\nfunction t:method(a, b) local c = a end\nfunction t.plain(a) end');
  assert.equal(functions.get('t:method').locals, 4);
  assert.equal(functions.get('t.plain').locals, 1);
});

test('limits count each outer variable a function captures once', () => {
  const functions = byName('local a, b, c = 1, 2, 3\nlocal function f() return a + a + b end');
  assert.equal(functions.get('f').upvalues, 2);
});

test('limits charge a captured variable to every function it passes through', () => {
  const functions = byName('local a = 1\nlocal function outer()\n  local function inner() return a end\n  return inner\nend');
  assert.equal(functions.get('inner').upvalues, 1);
  assert.equal(functions.get('outer').upvalues, 1);
});

test('limits do not count globals or field names as captured variables', () => {
  const functions = byName('local t = {}\nlocal function f() return print, t.field, { key = 1 } end');
  assert.equal(functions.get('f').upvalues, 1);
});

test('analyzeLua collects draw sublevels written as plain numbers', () => {
  const { sublevels } = analyzeLua(
    'local layer = 3\n' +
      'tex:SetDrawLayer("OVERLAY", 7)\n' +
      'tex:SetDrawLayer("OVERLAY", -8)\n' +
      'tex:SetDrawLayer("OVERLAY", layer)\n' +
      'tex:SetDrawLayer("ARTWORK")\n' +
      'frame:CreateTexture(nil, "BORDER", nil, 9)\n',
  );
  assert.deepEqual(sublevels, [
    { value: 7, line: 2 },
    { value: -8, line: 3 },
    { value: 9, line: 6 },
  ]);
});

test('checkRepo reports functions over the compiler limits and sublevels out of range', (t) => {
  const repoRoot = mkdtempSync(join(tmpdir(), 'mistui-limits-'));
  t.after(() => rmSync(repoRoot, { recursive: true, force: true }));
  const addonDir = join(repoRoot, 'Limits');
  mkdirSync(addonDir);
  writeFileSync(join(addonDir, 'Limits.toc'), '## Interface: 50400\nlocals.lua\nupvalues.lua\nsublevels.lua\nfine.lua\n');
  writeFileSync(join(addonDir, 'locals.lua'), locals(MAX_LOCALS + 1));
  const captured = Array.from({ length: MAX_UPVALUES + 1 }, (_, index) => `v${index}`).join(' + ');
  writeFileSync(
    join(addonDir, 'upvalues.lua'),
    `${locals(MAX_UPVALUES + 1)}\nlocal function greedy()\n  return ${captured}\nend\n`,
  );
  writeFileSync(
    join(addonDir, 'sublevels.lua'),
    'local frame = CreateFrame("Frame")\nlocal tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)\ntex:SetDrawLayer("OVERLAY", 9)\ntex:SetDrawLayer("BACKGROUND", -9)\n',
  );
  writeFileSync(join(addonDir, 'fine.lua'), `${locals(MAX_LOCALS)}\n`);

  const { problems } = checkRepo({ repoRoot, stockIndex: null });
  assert.deepEqual(
    problems.map((problem) => `${problem.kind} ${problem.file.split(/[\\/]/).pop()}:${problem.line} ${problem.detail}`),
    [
      `too-many-locals locals.lua:1 (file level): ${MAX_LOCALS + 1} of ${MAX_LOCALS}`,
      `too-many-upvalues upvalues.lua:${MAX_UPVALUES + 2} greedy: ${MAX_UPVALUES + 1} of ${MAX_UPVALUES}`,
      'bad-sublevel sublevels.lua:3 9',
      'bad-sublevel sublevels.lua:4 -9',
    ],
  );
});
