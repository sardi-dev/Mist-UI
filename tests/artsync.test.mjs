import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { after, before, test } from 'node:test';
import { planArtCopy, runArtCopy } from '../tools/lib/artsync.mjs';

const MANIFEST = {
  copy: [
    { from: 'Up/Textures', to: 'Addon/Textures', exclude: ['Cut', 'Keep/skip.tga'], include: ['Cut/back.tga'] },
    { from: 'Up_Options/Textures', to: 'Addon_Options/Textures' },
  ],
};
const SOURCE_FILES = [
  'Up/Textures/Keep/a.tga',
  'Up/Textures/Keep/skip.tga',
  'Up/Textures/Keep/Deep/b.blp',
  'Up/Textures/Cut/c.blp',
  'Up/Textures/Cut/back.tga',
  'Up/Textures/CutNot/d.blp',
  'Up_Options/Textures/e.blp',
];

let workDir;
let sourceRoot;
let targetRoot;

before(() => {
  workDir = mkdtempSync(join(tmpdir(), 'mistui-artsync-'));
  sourceRoot = join(workDir, 'source');
  targetRoot = join(workDir, 'target');
  for (const file of SOURCE_FILES) {
    const full = join(sourceRoot, file);
    mkdirSync(join(full, '..'), { recursive: true });
    writeFileSync(full, `fixture ${file}`);
  }
});

after(() => {
  rmSync(workDir, { recursive: true, force: true });
});

const portable = (path) => path.replace(/\\/g, '/');

test('planArtCopy keeps the folder layout and applies excludes and includes exactly', () => {
  const plan = planArtCopy(MANIFEST, sourceRoot, targetRoot);
  const targets = plan.map((entry) => portable(relative(targetRoot, entry.to))).sort();
  assert.deepEqual(targets, [
    'Addon/Textures/Cut/back.tga',
    'Addon/Textures/CutNot/d.blp',
    'Addon/Textures/Keep/Deep/b.blp',
    'Addon/Textures/Keep/a.tga',
    'Addon_Options/Textures/e.blp',
  ]);
});

test('runArtCopy writes the planned files', () => {
  const copied = runArtCopy(planArtCopy(MANIFEST, sourceRoot, targetRoot));
  assert.equal(copied, 5);
  assert.equal(readFileSync(join(targetRoot, 'Addon/Textures/Keep/a.tga'), 'utf8'), 'fixture Up/Textures/Keep/a.tga');
  assert.equal(existsSync(join(targetRoot, 'Addon/Textures/Cut/c.blp')), false);
});

test('planArtCopy fails clearly when a source folder is missing', () => {
  assert.throws(() => planArtCopy({ copy: [{ from: 'Nope', to: 'X' }] }, sourceRoot, targetRoot), /Artwork source folder not found/);
});
