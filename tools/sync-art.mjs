#!/usr/bin/env node
// Usage: node tools/sync-art.mjs [--from <upstream checkout>]
// Copies the texture files listed in tools/art-manifest.json from a local
// checkout of the upstream project (default: ../DragonUI-upstream) into the
// git-ignored texture folders of the addon.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { planArtCopy, runArtCopy } from './lib/artsync.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST_PATH = join(REPO_ROOT, 'tools', 'art-manifest.json');
const DEFAULT_SOURCE = resolve(REPO_ROOT, '..', 'DragonUI-upstream');

function checkedOutCommit(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch (error) {
    throw new Error(`Could not read the checked-out commit of ${dir}: ${error.message}`);
  }
}

function main(argv) {
  const flag = argv.indexOf('--from');
  const source = resolve(flag >= 0 ? argv[flag + 1] : DEFAULT_SOURCE);
  if (!existsSync(source)) {
    console.error(`Upstream checkout not found: ${source}\nClone it first, or pass --from <path>.`);
    process.exitCode = 1;
    return;
  }
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'));
  const commit = checkedOutCommit(source);
  if (commit !== manifest.upstream.commit) {
    console.warn(`Warning: the checkout is at ${commit.slice(0, 7)}, the manifest expects ${manifest.upstream.commit.slice(0, 7)}.`);
  }
  const copied = runArtCopy(planArtCopy(manifest, source, REPO_ROOT));
  console.log(`Copied ${copied} artwork file(s) from ${source}.`);
}

main(process.argv.slice(2));
