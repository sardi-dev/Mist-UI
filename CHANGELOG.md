# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **/mist nameplates and /mist worldmap use the Modules tab's switch** (2026-11-22)
  - Summary: Both commands now switch their module exactly like the Modules tab: a change that needs a reload shows the reload prompt and is only saved when you reload.
  - Why: They wrote the setting directly (the map) or switched hooks that cannot be removed until a reload (the nameplates), so the saved settings could describe something other than what was running. Found in a code audit; a harness check now covers it.
- **Cast bars read the combat log only when needed** (2026-11-22)
  - Summary: The cast bars listen to the combat log only while a cast bar that names the interrupter is on.
  - Why: They ran code for every combat log event, which is heavy in a raid, even with every cast bar off, although only interrupts matter. Found in a code audit; a harness check now covers it.

### Fixed
- **Minimap border frame hides with the interface** (2026-11-22)
  - Summary: The helper frame behind the minimap border now belongs to the interface parent, so hiding the interface with Alt+Z hides it too.
  - Why: It had no parent because of a wrong argument order. Found in a code audit.
- **Layout strings are checked before they are imported** (2026-11-22)
  - Summary: An imported layout string (and a saved layout preset) is applied only if every setting in it is a known position field with the right kind of value; otherwise nothing changes and the message names the first setting that is wrong.
  - Why: A layout string can come from anyone. An edited or broken one could write unknown entries or wrong values into the settings, half-apply, or raise an error. Found in a code audit; a harness check now covers it.
- **Errors the addon catches itself reach the error log** (2026-11-22)
  - Summary: Failures the addon handles on its own (a module refresh, a change queued for after combat, a layout preset) are now kept in the saved error log as well as printed in chat.
  - Why: They were only printed, so the error log attached to bug reports missed the most likely failures. Found in a code audit; a harness check now covers it.
- **Combat visibility is right after a /reload in combat** (2026-11-22)
  - Summary: Parts set to show only in combat, or to hide in combat, now start in the right state when the interface loads during a fight.
  - Why: They assumed "not in combat" until the next fight started, so after a /reload mid-fight a show-in-combat bar stayed hidden and a hide-in-combat bar stayed visible. Found in a code audit; a harness check now covers it.
- **Action buttons no longer taint the stock button code** (2026-11-22)
  - Summary: The setting that keeps empty main bar slots visible is now written by secure code instead of addon code, and a settings refresh restyles the buttons itself instead of running the game's own button update.
  - Why: The game's button update reads that setting in combat (page and stance changes), so a value written by the addon could block its later actions with "action blocked". Found in a code audit; a harness check now covers it. Needs an in-game check that empty main bar slots still show as before.
- **Layout presets refuse to load in combat** (2026-11-22)
  - Summary: Loading a saved layout preset in combat now says frames cannot be moved in combat and changes nothing.
  - Why: It wrote the preset's positions into the saved settings first and only then refused to move the frames, so the screen and the saved positions no longer matched and frames jumped later. Found in a code audit; a harness check now covers it.
- **After-combat work runs in order and is never dropped** (2026-11-22)
  - Summary: The queue of changes that wait for the end of combat now runs them in the order they were queued, and keeps (and runs) work that one of them queues while the batch is running.
  - Why: It ran them in random order and then cleared the whole queue, so a change queued during the run was silently lost or an old one ran twice. Found in a code audit; a harness check now covers it.
- **Player frame layout waits for the end of combat in a vehicle** (2026-11-22)
  - Summary: Entering or leaving a vehicle in combat now only updates the player frame's art; the portrait, name, health bar and group icons are moved and sized once combat ends.
  - Why: Moving the parts of the protected player frame in combat can raise "action blocked", and vehicles are often entered mid-fight. Found in a code audit; a harness check now covers it.
- **Party frame icons no longer move in combat** (2026-11-22)
  - Summary: The party frames' leader, PvP, guide and role icons are moved above the frame border only out of combat; a move asked for in combat (a member joins or zones mid-fight, or a /reload in combat) waits until combat ends.
  - Why: Giving a region of a protected frame another parent is blocked in combat, so these updates could raise "action blocked". Found in a code audit; a harness check now covers it.
- **Currency icons and tooltips in the bag window** (2026-11-22)
  - Summary: The currency strip at the bottom of the bag window now reads the game's watched currency info in the 5.4.8 order (name, count, icon, currency id) and shows the stock backpack currency tooltip; the arena and honor point branches of the old client are gone.
  - Why: It read the info in the 3.3.5a order, so a currency shown on the backpack (Valor, Justice) got its currency id as the icon (no icon) and never showed a tooltip. Found in a code audit; a harness check now covers it.
- **Error when hovering the bag window title** (2026-11-19)
  - Summary: The three texts of the other characters picker (the title tooltip hint, the menu title and the empty menu message) were missing from the English locale file; they are added, and a test now checks every bag window text against it.
  - Why: Hovering the bag window title, for example while selling at a vendor, raised the Lua error `AceLocale-3.0-MistUI: MistUI: Missing entry for '|cff00ff00Right-Click|r to see another character's items'` (bagster.lua:355, from `OnTitleEnter`). It was reported again in game on 2026-11-21 on two characters running 0.1.0. The repository check cannot see these texts because the bag window looks them up through a key table.
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
