# 0003. Keep artwork out of the repository

- **Date:** 2026-11-09
- **Status:** Accepted

## Context

The addon's look comes from texture files that are game artwork. They are
owned by the game's publisher and are not covered by the MIT License of this
project or of DragonUI. Similar addons commonly commit such files anyway.

## Decision

The repository holds code only. The texture folders are git-ignored. A
manifest (`tools/art-manifest.json`) pins the upstream commit and lists the
folders in use, and `npm run art` copies them from a local DragonUI checkout.
The same rule covers tables generated from game data files: none are
committed.

## Consequences

- Nothing in the repository is outside its license.
- Installing takes an extra step, and the addon cannot be used straight from
  a source download. A simpler path for players is needed before the first
  release (tracked in `TODO.md`).
- Screenshots of the addon are not kept in the repository.
- Texture file names and coordinates in the code must keep matching the
  upstream artwork at the pinned commit.
