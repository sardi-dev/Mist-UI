# 0010. Players get the artwork with a download script

- **Date:** 2026-11-16
- **Status:** Accepted

## Context

Decision 0003 keeps the game artwork out of the repository, and with it out of
the release zip. Until now the only way to get it was `npm run art`, which
needs Node.js, git and a local DragonUI checkout: fine for development, not
for players. The first release needs a simple path.

Options considered: written steps only (players download DragonUI's archive
and copy two folders by hand); a script that does those steps; or shipping
the artwork in the zip, as many addons do, which would break decision 0003.

## Decision

Ship `MistUI/Install-Artwork.cmd` and `MistUI/install-artwork.ps1` in the
addon folder. A double-click runs the script with the Windows PowerShell 5.1
that every supported Windows has. It downloads the source archive of the
DragonUI commit pinned in the artwork manifest from GitHub, applies the same
copy rules as `npm run art` (folders, exclusions, inclusions), and deletes
its temporary files. The release zip carries the manifest as
`MistUI/art-manifest.json`; in a repository checkout the script reads
`tools/art-manifest.json`. Manual steps in `docs/ARTWORK.md` cover other
systems and offline game PCs.

## Consequences

- Players need one extra double-click after unzipping, and an internet
  connection the first time.
- The script depends on GitHub serving archives of the pinned commit and on
  DragonUI's repository staying public. If it goes away, the manual steps
  still work with any copy of that commit.
- A test runs the script on a fixture and compares its result with the art
  sync, so the two copy rule implementations cannot drift apart unnoticed.
- The client ignores the script files: they are not in a `.toc`.
