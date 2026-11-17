# 0009. Which DragonUI extras go into the first release

- **Date:** 2026-11-16
- **Status:** Accepted

## Context

After the HUD, the nameplates and the world map, 21 smaller DragonUI modules were still parked
(about 14,600 lines): bag and item helpers, combat helpers, look changes and a few tweaks. Each
parked file keeps settings, texts and hooks alive in the loaded code. Before the first release
every one of them has to be either ported or removed.

## Decision

Port for 0.1.0:

- Bag extras: bag sorting (`bagsort.lua`; the 5.4.8 client has no sort button), the gold of all
  characters (`altmoney.lua`) and their item counts (`itemownership.lua`), which also fill the
  other character view of the bag window.
- Item info: item level on gear (`itemlevel.lua`), item quality borders (`itemquality.lua`) and the
  comparison tooltips (`equipmentcompare.lua`).
- Combat helpers: the loot roll frames (`lootroll.lua`) and the low health alert
  (`hp_low_alert.lua`).
- The personal resource bar (`personalresource.lua`).

Delete, with their settings, defaults, texts and hooks: dark mode, the key binding mode and its
library (LibKeyBound), cast on key down (the 5.4.8 client has it built in), the range and mana tint
on action buttons, the target and focus aura timers (the aura icon size settings stay: the target
frame code reads them), auto-accept of group invites, the camera distance setting, the game menu
restyle and its dragons, the in-game addon list, the totem bar, the heal prediction layers (the
stock frames draw both on this client), the add-on compatibility manager and DragonUI's own quest
tracker (decision 0005 keeps the stock one).

## Consequences

- The first release has one less class of half-loaded code: every module file in the tree is
  either loaded or on the port list above.
- Deleted modules stay in DragonUI's history at the commit in `docs/UPSTREAM.md` and can be
  ported later if players ask for them.
- The aura icon size settings keep the upstream `auracooldowns` key in the saved settings.
