import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { planArtCopy } from '../tools/lib/artsync.mjs';
import { checkRelease, zipName } from '../tools/lib/release.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const toc = (version) => `## Interface: 50400\n## Version: ${version}\n\ncore.lua\n`;
const tocs = (a, b = a) => ({ MistUI: toc(a), MistUI_Options: toc(b) });
const CHANGELOG = '# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-12-01\n';

test('checkRelease accepts matching versions with a changelog section', () => {
  assert.deepEqual(checkRelease(tocs('0.1.0'), CHANGELOG), { version: '0.1.0', problems: [] });
});

test('checkRelease reports differing versions, a missing section and pre-releases', () => {
  assert.match(checkRelease(tocs('0.1.0', '0.1.1'), CHANGELOG).problems.join('\n'), /versions differ/);
  assert.match(checkRelease(tocs('0.2.0'), CHANGELOG).problems.join('\n'), /no "## \[0\.2\.0\]" section/);
  assert.match(checkRelease(tocs('0.1.0-dev'), CHANGELOG).problems.join('\n'), /pre-release/);
  assert.deepEqual(checkRelease(tocs('0.1.0-dev'), CHANGELOG, { allowPrerelease: true }).problems, []);
  assert.match(checkRelease(tocs('1.0'), CHANGELOG).problems.join('\n'), /not MAJOR\.MINOR\.PATCH/);
});

test('zipName names the zip after the version', () => {
  assert.equal(zipName('0.1.0'), 'MistUI-0.1.0.zip');
});

// The players' install script must copy exactly what npm run art copies.
test('install-artwork.ps1 follows the same manifest rules as the art sync', { skip: process.platform !== 'win32' }, () => {
  const work = mkdtempSync(join(tmpdir(), 'mistui-installart-'));
  try {
    const upstream = join(work, 'up');
    const target = join(work, 'addons');
    const files = [
      'DragonUI/Textures/Keep/a.tga',
      'DragonUI/Textures/Cut/c.blp',
      'DragonUI/Textures/Cut/back.tga',
      'DragonUI/Textures/CutNot/d.blp',
      'DragonUI_Options/Textures/e.blp',
    ];
    for (const file of files) {
      mkdirSync(dirname(join(upstream, file)), { recursive: true });
      writeFileSync(join(upstream, file), file);
    }
    const manifest = {
      upstream: { repository: 'https://example.com/none', commit: '0' },
      copy: [
        { from: 'DragonUI/Textures', to: 'MistUI/Textures', exclude: ['Cut'], include: ['Cut/back.tga'] },
        { from: 'DragonUI_Options/Textures', to: 'MistUI_Options/Textures' },
      ],
    };
    const scriptDir = join(target, 'MistUI');
    mkdirSync(scriptDir, { recursive: true });
    mkdirSync(join(target, 'MistUI_Options'));
    writeFileSync(join(scriptDir, 'art-manifest.json'), JSON.stringify(manifest));
    writeFileSync(join(scriptDir, 'install-artwork.ps1'), readFileSync(join(REPO_ROOT, 'MistUI', 'install-artwork.ps1')));

    const run = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
      join(scriptDir, 'install-artwork.ps1'), '-Source', upstream], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr || run.stdout);

    const expected = planArtCopy(manifest, upstream, target).map((pair) => relative(target, pair.to)).sort();
    const copied = files
      .map((file) => file.replace(/^DragonUI_Options\/Textures/, 'MistUI_Options/Textures').replace(/^DragonUI\/Textures/, 'MistUI/Textures'))
      .filter((file) => {
        try { readFileSync(join(target, file)); return true; } catch { return false; }
      })
      .map((file) => relative(target, join(target, file)))
      .sort();
    assert.deepEqual(copied, expected);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
