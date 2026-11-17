#!/usr/bin/env node
// Usage: node tools/release.mjs [--pre]
// Builds dist/MistUI-<version>.zip from the committed state of HEAD: the MistUI and
// MistUI_Options folders, plus the artwork manifest as MistUI/art-manifest.json so the
// install script in the zip finds it. Refuses to build from a working tree with changes
// to those folders, and checks the version against both .toc files and CHANGELOG.md.
// --pre allows a pre-release version (for example 0.1.0-dev) for a test build.

import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ADDONS, checkRelease, zipName } from './lib/release.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const git = (args) => execFileSync('git', ['-C', REPO_ROOT, ...args], { encoding: 'utf8' });

function main(argv) {
  const dirty = git(['status', '--porcelain', '--', ...ADDONS, 'tools/art-manifest.json']).trim();
  if (dirty) {
    console.error(`Commit or discard these changes first; the zip is built from HEAD:\n${dirty}`);
    process.exitCode = 1;
    return;
  }
  const tocTexts = Object.fromEntries(ADDONS.map((name) => [name, git(['show', `HEAD:${name}/${name}.toc`])]));
  const { version, problems } = checkRelease(tocTexts, git(['show', 'HEAD:CHANGELOG.md']), {
    allowPrerelease: argv.includes('--pre'),
  });
  if (problems.length) {
    console.error(`Not built:\n- ${problems.join('\n- ')}`);
    process.exitCode = 1;
    return;
  }
  const distDir = join(REPO_ROOT, 'dist');
  mkdirSync(distDir, { recursive: true });
  const out = join(distDir, zipName(version));
  const manifest = join(REPO_ROOT, 'tools', 'art-manifest.json');
  // The manifest goes in from the working tree, which the status check above proved equal to HEAD.
  // --add-file takes the last --prefix before it; the empty --prefix after it is the tracked files.
  git(['archive', '--format=zip', `--output=${out}`, '--prefix=MistUI/', `--add-file=${manifest}`, '--prefix=', 'HEAD', ...ADDONS]);
  console.log(`Built ${out} (version ${version}).`);
}

main(process.argv.slice(2));
