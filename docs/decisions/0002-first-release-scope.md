# 0002. Scope of the first release: the HUD and nameplates, one style, English

- **Date:** 2026-11-09
- **Status:** Accepted; amended by [0008](0008-world-map-without-game-data.md) (the world map is in)

## Context

DragonUI is about 150,000 lines written against 3.3.5a internals. Its modules
fall into three groups: HUD elements that sit on the same stock frames in
5.4.8, elements that 5.4.8 changed (action bars, class resources), and whole
windows that DragonUI rebuilt around 3.3.5a systems and game data (talents,
spellbook, character panel, world map, professions, collections).

The 5.4.8 client already has several things DragonUI adds to 3.3.5a: incoming
heal and absorb values, cast on key down, a level-up display.

## Decision

The first release covers the HUD (unit frames, action bars, minimap, cast
bars, buffs, micro menu, bags, quest tracker, chat and tooltip tweaks), the
edit mode, the settings panel and the nameplates. It ships one art style and
English only. Window modules, the libraries that emulate what 5.4.8 does
natively, the other languages and the second art style are left out.

Mist-UI targets the 5.4.8 (18414) client on any server and does not rely on
behaviour specific to one server.

## Consequences

- The stock 5.4.8 windows stay as they are until a later version reskins them.
- Features that depend on server data (heal prediction, absorbs, boss frames,
  the alternate power bar) must degrade cleanly when a server sends nothing.
- Settings and texts for the left-out features remain in the code until they
  are pruned (tracked in `TODO.md`).
