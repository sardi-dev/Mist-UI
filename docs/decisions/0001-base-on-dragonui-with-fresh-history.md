# 0001. Base Mist-UI on DragonUI, in a standalone repository with fresh history

- **Date:** 2026-11-09
- **Status:** Accepted

## Context

Mist-UI needs a retail-style interface for the 5.4.8 client. Writing one from
nothing would take far longer than porting an existing one. DragonUI is an
actively developed, MIT-licensed addon of that kind for the 3.3.5a client,
with a modular framework, an edit mode and a settings panel. No port of it to
5.4.8 was found.

DragonUI has about 1,300 commits and its history includes roughly 200 MB of
artwork that this project does not redistribute.

## Decision

Port DragonUI. Start a standalone repository (not a fork on the hosting
platform) whose first commit imports the kept files unmodified from one
recorded upstream commit. Credit DragonUI in the license, the README, the
third-party notices and `docs/UPSTREAM.md`, and keep all original license
headers.

## Consequences

- The repository is small and holds only what Mist-UI uses.
- Upstream fixes cannot be merged with git; they are carried over by hand and
  credited in the commit body.
- Line-by-line history of the upstream code is not available here; it stays
  in the DragonUI repository.
