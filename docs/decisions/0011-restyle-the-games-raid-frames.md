# 0011. Raid frames restyle the game's own frames

- **Date:** 2026-11-17
- **Status:** Accepted

## Context

Mist-UI covered the player, target, focus, party and boss frames but nothing
for raids, the biggest gap for group play. The 5.4.8 client has its own raid
frames (the compact unit frames and the raid manager), which already handle
the roster, range, dead and offline members, click targeting, sorting, sizes
and saved positions per raid profile.

Options considered: restyle those frames; or build new ones on secure group
headers, as Grid or VuhDo do, with full control over the layout.

## Decision

Restyle the game's frames (owner's choice, 2026-11-17). `modules/raidframes.lua`
post-hooks `CompactUnitFrame_SetUpFrame`, `CompactUnitFrame_UpdateAuras` and
`CompactRaidFrameContainer_ApplyToFrames`, and only changes the bars' textures,
the background, the name font and its own outline textures: never the secure
buttons' size, position, attributes or scripts. A colored outline marks a member
with a debuff the player can dispel (the client's "RAID" debuff filter). Size,
layout and position stay in the game's raid profiles and its raid manager.

## Consequences

- Low risk of "action blocked" errors: no protected frame is moved, resized or
  scripted by addon code, in or out of combat.
- Works for raid-style party frames too, since they use the same setup.
- Moving and sizing use the game's Unlock in the raid manager and its raid
  profiles, not Mist-UI's edit mode; the settings say so.
- Layout ideas beyond the game's options (custom growth directions, buff
  tracking by spell) would need the second option later.
