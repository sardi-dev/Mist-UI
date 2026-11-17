import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { resolveLoadList } from '../tools/lib/loadlist.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ADDON_DIR = join(REPO_ROOT, 'MistUI');
const LOCALE_FILE = join(ADDON_DIR, 'Locales', 'enUS.lua');

// The name of an edit mode box, when it is written as text in the call.
const BOX_NAME = /CreateUIFrame\([^()]*,\s*["']([^"']+)["']\s*\)/g;
const LOCALE_KEY = /^L\["([^"]+)"\]\s*=/gm;

test('every edit mode box created by loaded code has an English label', () => {
  const labels = new Set();
  for (const match of readFileSync(LOCALE_FILE, 'utf8').matchAll(LOCALE_KEY)) {
    labels.add(match[1]);
  }

  const unlabelled = [];
  for (const file of resolveLoadList(ADDON_DIR).lua) {
    for (const match of readFileSync(file, 'utf8').matchAll(BOX_NAME)) {
      if (!labels.has(match[1])) {
        unlabelled.push(`${relative(REPO_ROOT, file)}: ${match[1]}`);
      }
    }
  }

  assert.deepEqual(unlabelled, []);
});
