// Runs the players' artwork script (Windows PowerShell) on a throwaway folder. Skipped elsewhere.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = join(REPO_ROOT, 'MistUI', 'install-artwork.ps1');
const windowsOnly = { skip: process.platform !== 'win32' && 'the artwork script is for Windows' };

// An AddOns folder with the script and a one-rule manifest, and an unpacked upstream folder.
function setUp(upstreamFiles) {
  const root = mkdtempSync(join(tmpdir(), 'mistui-art-'));
  const addons = join(root, 'AddOns');
  mkdirSync(join(addons, 'MistUI', 'Textures'), { recursive: true });
  mkdirSync(join(addons, 'MistUI_Options'), { recursive: true });
  copyFileSync(SCRIPT, join(addons, 'MistUI', 'install-artwork.ps1'));
  writeFileSync(
    join(addons, 'MistUI', 'art-manifest.json'),
    JSON.stringify({ upstream: { repository: 'https://example.com/none', commit: '0' }, copy: [{ from: 'Up/Textures', to: 'MistUI/Textures' }] }),
  );
  const upstream = join(root, 'upstream');
  for (const [path, text] of Object.entries(upstreamFiles)) {
    const full = join(upstream, 'Up', 'Textures', path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, text);
  }
  return { root, addons, upstream, textures: join(addons, 'MistUI', 'Textures') };
}

function run({ addons, upstream }) {
  return spawnSync(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', join(addons, 'MistUI', 'install-artwork.ps1'), '-Source', upstream],
    { encoding: 'utf8' },
  );
}

test('the artwork script copies the selected files', windowsOnly, () => {
  const box = setUp({ 'a.tga': 'new a', 'sub/d.tga': 'new d' });
  try {
    const result = run(box);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(readFileSync(join(box.textures, 'a.tga'), 'utf8'), 'new a');
    assert.equal(readFileSync(join(box.textures, 'sub', 'd.tga'), 'utf8'), 'new d');
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a failed copy puts the previous artwork back', windowsOnly, () => {
  const box = setUp({ 'a.tga': 'new a', 'b.tga': 'new b', 'sub/d.tga': 'new d' });
  try {
    writeFileSync(join(box.textures, 'a.tga'), 'old a');
    // A file where the script needs a folder: the copy of sub/d.tga fails after a.tga and b.tga.
    writeFileSync(join(box.textures, 'sub'), 'not a folder');
    const result = run(box);
    assert.notEqual(result.status, 0, 'the script should report the failure');
    assert.equal(readFileSync(join(box.textures, 'a.tga'), 'utf8'), 'old a');
    assert.equal(existsSync(join(box.textures, 'b.tga')), false);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});
