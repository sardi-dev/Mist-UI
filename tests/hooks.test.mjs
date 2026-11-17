import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkRepo } from '../tools/lib/checker.mjs';
import { analyzeLua } from '../tools/lib/luaglobals.mjs';
import { buildStockIndex } from '../tools/lib/stockindex.mjs';

const STOCK_SOURCE = join(dirname(fileURLToPath(import.meta.url)), 'fixtures', 'stock');

test('analyzeLua collects the global function names passed to hooksecurefunc', () => {
  const { hooks } = analyzeLua(
    'hooksecurefunc("StockFunction", function() end)\n' +
      'hooksecurefunc(frame, "SetPoint", function() end)\n' +
      'local name = "Dynamic"\n' +
      'hooksecurefunc(name, function() end)\n',
  );
  assert.deepEqual(hooks, [{ name: 'StockFunction', line: 1 }]);
});

test('checkRepo reports a hook on a function the client does not have', (t) => {
  const repoRoot = mkdtempSync(join(tmpdir(), 'mistui-hooks-'));
  t.after(() => rmSync(repoRoot, { recursive: true, force: true }));
  const addonDir = join(repoRoot, 'Hooks');
  mkdirSync(addonDir);
  writeFileSync(join(addonDir, 'Hooks.toc'), '## Interface: 50400\nmain.lua\n');
  writeFileSync(
    join(addonDir, 'main.lua'),
    'function OwnFunction() end\n' +
      'hooksecurefunc("StockFunction", function() end)\n' +
      'hooksecurefunc("stockFunction", function() end)\n' +
      'hooksecurefunc("OwnFunction", function() end)\n' +
      'hooksecurefunc("AllowedFunction", function() end)\n',
  );

  const { problems } = checkRepo({
    repoRoot,
    stockIndex: buildStockIndex(STOCK_SOURCE),
    allowlist: new Set(['hooksecurefunc', 'AllowedFunction']),
  });
  assert.deepEqual(
    problems.map((problem) => `${problem.kind} ${problem.line} ${problem.detail}`),
    ['unknown-hook 3 stockFunction'],
  );
});
