import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { formatTaintReport, parseTaintLog, summarizeTaint, UNKNOWN_LOCATION } from '../tools/lib/taintlog.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = join(HERE, 'fixtures', 'taint');
const FIXTURE = readFileSync(join(FIXTURE_DIR, 'taint.log'), 'utf8');
const CLI = join(HERE, '..', 'tools', 'taint.mjs');
const ADDONS = ['MistUI', 'MistUI_Options'];

test('parseTaintLog keeps blocked actions and tainted globals with their stack', () => {
  const entries = parseTaintLog(FIXTURE);
  assert.deepEqual(
    entries.map((entry) => `${entry.kind}|${entry.subject}|${entry.addon}`),
    [
      'tainted global|SAMPLE_SETTING|MistUI',
      'blocked action|SampleFrame:SetPoint()|MistUI',
      'tainted global|SAMPLE_SETTING|MistUI',
      'blocked action|SampleFrame:SetPoint()|MistUI',
      'blocked action|PickupContainerItem()|MistUI',
      'blocked action|Frame:Show()|MistUI_Options',
      'blocked action|Frame:Hide()|OtherAddon',
      'tainted global|OTHER_SETTING|OtherAddon',
    ],
  );
  assert.equal(entries[0].stack[1], 'Interface\\AddOns\\MistUI\\modules\\sample.lua:330 SetThing()');
});

test('summarizeTaint groups identical entries of the addon, most frequent first', () => {
  const groups = summarizeTaint(parseTaintLog(FIXTURE), ADDONS);
  assert.deepEqual(
    groups.map((group) => [group.count, group.kind, group.subject, group.addon, group.location]),
    [
      [2, 'tainted global', 'SAMPLE_SETTING', 'MistUI', 'MistUI\\modules\\sample.lua:330'],
      [2, 'blocked action', 'SampleFrame:SetPoint()', 'MistUI', UNKNOWN_LOCATION],
      [1, 'blocked action', 'Frame:Show()', 'MistUI_Options', 'MistUI_Options\\panel\\panel.lua:77'],
      [1, 'blocked action', 'PickupContainerItem()', 'MistUI', 'MistUI\\modules\\bags\\slot.lua:48'],
    ],
  );
});

test('summarizeTaint ignores other addons and the addon of a different folder name', () => {
  const groups = summarizeTaint(parseTaintLog(FIXTURE), ['OtherAddon']);
  assert.deepEqual(groups.map((group) => group.subject), ['Frame:Hide()', 'OTHER_SETTING']);
});

test('parseTaintLog accepts Windows line endings', () => {
  const entries = parseTaintLog(FIXTURE.replace(/\n/g, '\r\n'));
  assert.equal(entries.length, 8);
  assert.equal(entries[0].stack.length, 3);
});

test('formatTaintReport prints one aligned line per group', () => {
  const lines = formatTaintReport(summarizeTaint(parseTaintLog(FIXTURE), ADDONS)).split('\n');
  assert.equal(lines.length, 4);
  assert.equal(lines[0], '2x  tainted global  SAMPLE_SETTING  [MistUI]  MistUI\\modules\\sample.lua:330');
  assert.match(formatTaintReport([]), /^No blocked actions/);
});

test('the command reads a log file or a Logs folder and prints usage without a path', () => {
  const run = (args, env = {}) =>
    spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8', env: { ...process.env, MISTUI_TAINT_LOG: '', ...env } });

  const fromFolder = run([FIXTURE_DIR]);
  assert.equal(fromFolder.status, 0);
  assert.match(fromFolder.stdout, /2x {2}tainted global {2}SAMPLE_SETTING/);

  const fromEnv = run([], { MISTUI_TAINT_LOG: join(FIXTURE_DIR, 'taint.log') });
  assert.equal(fromEnv.stdout, fromFolder.stdout);

  const noPath = run([]);
  assert.equal(noPath.status, 2);
  assert.match(noPath.stdout, /Usage: npm run taint/);

  assert.equal(run([join(FIXTURE_DIR, 'missing.log')]).status, 1);
});
