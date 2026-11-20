# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- **Error when hovering the bag window title** (2026-11-19)
  - Summary: The three texts of the other characters picker (the title tooltip hint, the menu title and the empty menu message) were missing from the English locale file; they are added, and a test now checks every bag window text against it.
  - Why: Hovering the bag window title, for example while selling at a vendor, raised a "Missing entry" Lua error. The repository check cannot see these texts because the bag window looks them up through a key table.
- **License shown as MIT on GitHub** (2026-11-17)
  - Summary: The root LICENSE file is now the plain MIT text with both copyright lines; the note on the origin, bundled components and artwork stays in the README's Credits and License sections and in the addon folders' own LICENSE.txt files.
  - Why: The extra section stopped GitHub from recognising the license, so the repository showed no license.

## [0.1.0] - 2026-11-17

### Added
- **First public release** (2026-11-17)
  - Summary: Mist-UI, a retail-style interface for the 5.4.8 (build 18414) client, ported from DragonUI (written for 3.3.5a) and tested on a SkyFire-based 5.4.8 server. Every feature below can be switched off on its own in the Modules tab, which hands its part of the screen back to the stock interface.
  - Why: Baseline for community testing and future changes.
- **Unit frames and class resources** (2026-11-17)
  - Summary: Player, target, focus, their targets, pet, party and boss frames in the retail style, with class colors, portraits and text options. Holy power, chi, shadow orbs, soul shards, burning embers, demonic fury, eclipse, runes, stagger and the druid and monk mana bar sit under the player frame or anywhere in edit mode.
  - Why: The frames players look at most.
- **Raid frames** (2026-11-17)
  - Summary: The game's own raid frames and raid-style party frames in the retail look, with a colored outline on members who have a debuff you can dispel (decision 0011).
  - Why: Group content without moving secure frames, so without "action blocked" errors.
- **Action bars, cast bars, buffs and minimap** (2026-11-17)
  - Summary: Retail bar art, button styling, cooldown numbers, a global cooldown indicator, stance, pet, possess and vehicle bars; player, target and focus cast bars with latency, channel ticks and interrupt state; movable buff and debuff rows with sorting and dispel-type borders; a retail minimap with a collector for other addons' buttons.
  - Why: The core of a modern interface.
- **Nameplates and world map** (2026-11-17)
  - Summary: Nameplates with health, cast bars, auras, quest, elite, rare and totem markers, threat colors and stacking. A windowed world map with a quest panel, quest details, search, zoom and coordinates, built without game data tables (decision 0008).
  - Why: The two largest stock windows players use in the open world.
- **Bags, items and helpers** (2026-11-17)
  - Summary: One bag window for bags, bank and guild bank with search, sorting (progress shown, a second click stops it), sort locks, gray item selling, other characters' bags and gold, and item counts per character in tooltips. Item levels and quality borders on gear, bags, the character window and vendors; equipment comparison; a loot roll window; a low health alert; a personal resource bar.
  - Why: The helpers most players otherwise install as separate addons (decision 0009).
- **Edit mode, settings and profiles** (2026-11-17)
  - Summary: `/mist edit` shows every movable part, with snap to grid, guide lines, nudging, undo, reset and layout presets. One settings panel (`/mist`, or the MistUI button in the Escape menu) with search, profiles and an optional profile per specialization. A message at login when the artwork is missing, and `/mist errors` for reports.
  - Why: Everything can be placed and configured without editing files.
- **Artwork script, release builder and bug report form** (2026-11-17)
  - Summary: `MistUI/Install-Artwork.cmd` downloads the artwork Mist-UI draws with (it is not part of the repository, decisions 0003 and 0010) and puts the previous files back if a copy fails; `npm run release` builds the zip; GitHub issues use a bug report form.
  - Why: Players need a simple install, and reports need enough detail to reproduce.

### Known issues
- **Checked offline, not yet in the game** (2026-11-17)
  - Summary: Many features, among them the world map, raid frames, class resource bars, bag extras and edit mode snapping, have so far only run in the offline test with a fake client; see TODO.md for the details of each.
  - Why: Released for community testing; please report problems with the bug report form.
