# Roadmap

Mist-UI is ported from DragonUI in slices. A feature only counts as done when
it passes `npm run check` and has been tested in the 5.4.8 client.

## Version 0.1.0: the HUD

| Step | Scope | State |
|---|---|---|
| 0 | Project setup: import, tooling, docs | Done |
| 1 | Framework and settings panel load on 5.4.8 with every module off | Done, tested in game |
| 2 | Edit mode first, then the HUD modules one at a time: minimap, buffs, cast bars, unit frames, action bars, micro menu and bags, quest tracker, chat and tooltips | Edit mode, the minimap, buffs, cast bars and the first unit frames (player, target, focus, their targets, pet, totem timers) done and tested in game on one character. Combo points and party frames load but are not tested: they need a rogue or druid, and a group. Tooltips, chat, cooldown numbers, the quest tracker placement, the bag windows, the micro menu, the bag bar, the action button styling, the layout and art of the action bars, the experience and reputation bars, the stance, pet and possess bars and the boss frames load, not tested. Next: class resource bars, the override bar look, the remaining settings tabs |
| 3 | Nameplates | Ported; first run in the game on 2026-11-11 |
| 3b | World map (decision 0008): window, breadcrumb, quest panel, zoom, coordinates | Ported on 2026-11-13, not run in the game yet |
| 3c | Extras (decision 0009): loot roll, low health alert, item quality borders, item level, item compare, bag sorting, gold and items of other characters, personal resource bar | Ported on 2026-11-16, not run in the game yet |
| 3d | Raid frames (decision 0011): the game's raid frames restyled, dispel outline | Added on 2026-11-17, not run in the game yet |
| 4 | Release: install instructions for the artwork, final checks | Released as 0.1.0 on 2026-11-17 for community testing |

Notes for step 2:

- Unit frames need the class resources the 5.4.8 client has and 3.3.5a does
  not (chi, holy power, shadow orbs, the warlock resources, eclipse).
- Action bars need the 5.4.8 override bar in place of the old vehicle and
  bonus bars.
- Heal prediction and absorb overlays use the client's own values and must
  hide cleanly on servers that do not send them.

## Later versions

- Reskins of the stock windows: character, spellbook, professions, vendor,
  mail.
- More languages. English is the only language for now.
- A second art style, if there is demand.

## Out of scope

- Features the 5.4.8 client already has (heal prediction and absorb values,
  cast on key down, equipment sets).
- Features tied to 3.3.5a game data (rare NPC tables, trainer data, the old
  talent trees, the totem bar, the key ring).
- DragonUI extras dropped for the first release (decision 0009): dark mode, the key binding
  mode, cast on key down, the range tint on buttons, target aura timers, auto-accept of
  invites, the camera distance setting, the game menu restyle, the in-game addon list, the
  heal prediction layers and DragonUI's own quest tracker.
- A talent window. DragonUI's is built around the 3.3.5a talent trees; the
  5.4.8 client has no talent tree, so its own talent window stays.
