# Known issues and tech debt

Each entry: date, description, location, suggested fix.

## Open

- **2026-11-17 - Review follow-ups and new features: checked offline only.**
  Not run in the game yet: the raid frames restyle (`modules/raidframes.lua`, decision 0011), the
  profile per specialization prompt (`core/spec_profiles.lua`), edit mode snap, guide lines and undo
  (`core/editor_snap.lua`), the missing artwork message (`core/artwork_check.lua`), the sort progress,
  stop and snapshot age in the bag window (`modules/bagsort.lua`, `bagster/`), the buff frame
  post-hooks (`modules/buff_frame.lua`) and the neighbour-only plate stacking
  (`nameplates/pipeline/layout.lua`). Not known until the game shows it: whether the raid frame
  outline sits well at small frame sizes; whether `SetTexture` answers nil for a missing file on this
  client in every case (the unit frames rely on it for race portraits); the guide line placement at
  UI scales other than 1. Suggested fix: cover each in the next in-game test (a raid or a raid-style
  party for the raid frames).

- **2026-11-16 - Extras (decision 0009): ported, not run in the game yet.**
  Loaded and checked offline (the harness sorts a model of the bags, reads item levels and quality
  borders on gear, a bank bag slot and a loot roll, moves the loot roll container, switches the bag
  window to another character): `bagsort.lua`, `altmoney.lua`, `itemownership.lua`,
  `itemlevel.lua`, `itemquality.lua`, `equipmentcompare.lua`, `lootroll.lua`, `hp_low_alert.lua`,
  `personalresource.lua`, and the other character view of the bag window (`bagster/bagster_data.lua`,
  `bagster_frame.lua`). Not known until the game shows it: (1) whether the client adds an "Item
  Level" line to gear tooltips by itself (the old client needed a setting this client lacks); (2) the
  player's item level average comes from the client; an inspected player's uses 16 slots, empty slots
  as zero and a two-hander (also a gun, crossbow or wand without off hand) twice, from memory; (3) heirlooms show their base item level (often 1) and pull the average down; item
  levels ignore upgrades (the owner's server has none); (4) the bag sort, lock and sell buttons on the
  stock bag, bank and guild bank windows (only used with the one bag window off) are placed by guess;
  (5) the personal resource bar keeps showing the player's bars in a vehicle, and its spend preview is
  gone (5.4.8 has no spell cost function an addon can trust); (6) item counts per character skip
  equipped bags, void storage and the guild bank; (7) another character's bags only show after that
  character logged in once with this version, and its bank after it opened the bank once; characters
  of other realms are not listed.
  Suggested fix: cover each point in the next in-game test; fix what it finds.

- **2026-11-13 - World map: ported, not run in the game yet.**
  `MistUI/modules/worldmap/` (see `docs/decisions/0008-world-map-without-game-data.md`). Checked
  offline only: the window builds at login, the breadcrumb, the quest rows, details, search, filter
  and settings menus, maximize, the panel toggle, zoom, combat and both size toggles run without
  error. Not known until the game shows it: (1) whether the windowed map is on at the first login
  (the module turns the client's `miniWorldMap` setting on at load; if the stock fullscreen map
  shows, one press of its size button or a reload fixes it); (2) where the stock "Show" menu,
  the boss buttons (`WorldMapBossButtonFrame`), the dig sites, the scenario areas and the progress
  bar of some zones (`MapBarFrame`) land on the new canvas; (3) the size of the player arrow (28
  pixels, set by hand) and of the landmark and quest pins; (4) whether any of the stock frames
  the module rescales or re-anchors is protected in combat on this client (the layout waits for
  the end of combat, the quest areas are drawn in combat); (5) `GetCurrentMapAreaID` is taken to
  answer in `SetMapByID` ids on this client (the old client was off by one): a quest of another
  zone whose badge does not take the map there points at this; (6) the quest detail page shows
  item, spell, money and experience rewards but not currency rewards (valor, justice).
  From a second review (2026-11-13), left for the game test: quest pins are placed from the
  client's offsets, which it clamps to the stock windowed canvas, so a pin at the very edge can sit
  a few pixels off on the larger canvas; the client's quest pin and boss button overlap pass runs
  before the module re-places both; the zone progress bar (`MapBarFrame`) keeps the client's
  windowed placement and does not clip when zoomed; on the fullscreen map the area label keeps the
  new font and the close button keeps the new art; the module clears `WorldMapBlobFrame.xRatio`
  after a resize, a field the client reads on its tooltip path only.
  Suggested fix: test with quests in the current zone and in another zone, a dungeon map with
  floors, a zone with a progress bar (Isle of Thunder) and the boss buttons in a dungeon.

- **2026-11-10 - Third in-game test: two points still open.**
  Run on a level 4 warrior and the level 28 shaman, solo. Tooltips, chat, bag windows, the quest
  tracker box, the micro menu, the action bars in combat, edit mode and the settings tabs were reported
  as working. Three faults were fixed and confirmed in the game by the owner the same evening: the
  error window at login, buttons that ignored the mouse until edit mode had been opened, and the
  missing cooldown numbers (see the changelog). Open:
  (1) Cooldown numbers on the stance, pet and possess buttons: added on 2026-11-11; the owner reported
  the cooldown numbers working in the test of 2026-11-11 evening.
  (2) Cancelling the logout countdown raised "MistUI called CancelLogout()" (blocked action) once, on
  2026-11-10. In the test of 2026-11-11 the owner cancelled a logout with no message, and the error log
  has no such entry in nine later sessions. Not explained: candidates were a stock popup shown by the
  addon earlier in the session (`MistUI/core/reload.lua`, `core/position_presets.lua`,
  `modules/chatmods.lua`, `modules/editor_mode.lua`) or a stock global the addon wrote. Suggested fix:
  repeat the test after a session that showed a MistUI popup (reload prompt, layout preset); if the
  message returns, give the addon dialogs of its own instead of the stock popup frames.
  (3) Open bag windows stacked up over the minimap and the quest list: Bagster (one bag window) loads
  from 2026-11-11. Its first in-game run stopped at login (empty highlight texture path, fixed the same
  evening); the fixed window has not run in the game yet. The auction class order it relies on was
  confirmed in the game on 2026-11-11 (Weapon, Armor, Container, Consumable, Glyph, Trade Goods,
  Recipe, Gem, Miscellaneous, Quest, Battle Pets). The view of another character's bags stays empty
  until the parked `altmoney.lua` (per character data) is ported. Glyphs and battle pets only appear
  under "All".
  Not covered by this test: a group, a dungeon and boss frames, a vehicle, a pet, a stance class.

- **2026-11-11 - Nameplates: ported in place, first run in the game on 2026-11-11.**
  `MistUI/modules/nameplates/` reads the 5.4.8 plate layout as a public 5.4.8 addon describes it
  (`pipeline/discovery.lua`). The owner's test of 2026-11-11 showed the new plates with debuffs and
  reported them as looking great. Open: (1) the `/mistui plates` dump was taken in game but not yet
  written to disk (no reload or logout afterwards), so the layout is confirmed by looks only;
  (2) the bar mask (`discovery.lua`, `ApplyBarMask`) needs `Texture:SetMask`, which this client lacks,
  so the rounded fill ends are missing; (3) the combat resize of click boxes (`features/clickbox.lua`)
  shows a secure frame through the stock panel system and picks plates by size; it only runs when a
  click box factor is not 1 (default 1), and it is a taint risk; (4) the settings tab loads; every
  sub-tab is built offline since 2026-11-16. Points (2) and (3) were closed on 2026-11-13 (owner decision
  of 2026-11-11): the mask call and the combat resize with its setting are removed; both bar styles
  draw rounded ends from their own art. Not yet seen in the game.

- **2026-11-09 - First in-game test passed; coverage is one character.**
  The framework, the Ace3 r1109 libraries, edit mode and the minimap ran on
  the 5.4.8 client: login, settings panel and its tabs, layout presets,
  tracking button, edit mode, `/reload`. The error recorder logged no errors
  over two sessions. Tested on one level 28 shaman, out of combat, solo.
  Suggested fix: repeat in combat, in a group, in a dungeon queue (the queue
  eye) and on a second class before the release.

- **2026-11-10 - Boss frames: restyled only, not run in the game yet.**
  `MistUI/modules/unitframes/boss.lua` is new code. The frames stand where the stock code puts them
  (below the minimap) and cannot be moved in edit mode: the stock layout pass sets the first frame's
  position directly on every pass, mostly in combat. DragonUI moved them with a secure helper that puts
  the frame back several times a second; that can be added if the stock place turns out wrong, at the
  price of a visible jump on every layout pass. The quest tracker placed by this addon no longer makes
  room for boss frames, so the two can overlap during a fight. The alternate power bar, the cast bar,
  the numeric threat and the quest icon of a boss frame keep their stock anchors on the new art.
  Needs a boss fight to test; it is not known whether the owner's server sends boss units at all.
  Suggested fix: test in a dungeon (frame appears with the new art, health and name update, the frame
  can be clicked to target the boss, no "action blocked"). Owner decision (2026-11-11): keep the stock
  position; revisit moving them only if they get in the way in a real fight.

- **2026-11-10 - Action bars: first step only, not run in the game yet.**
  `MistUI/modules/mainbars.lua` is new code (see
  `docs/decisions/0007-keep-the-stock-action-bar-tree.md`). Still stock, and out of place next to the
  new bars: the override bar (the separate bar of a vehicle with its own art), which is all stock.
  `MistUI/modules/smallbars.lua` (stance, pet and possess rows, vehicle leave button) needs a class
  with stances, a pet, a mind control and a vehicle without its own bar to test. The stock pet bar
  still slides in from below; its buttons no longer move with it, so they may appear at once.
  The totem bar file and its edit mode entry were deleted on 2026-11-16 (decision 0009); if a shaman
  above level 30 shows the stock totem bar on this client, it keeps its stock look and place.
  In `MistUI/modules/xprepbar.lua` the fill of a bar is cropped by hand after
  each value change; if this client already crops status bar textures, the hook is redundant. The
  same file decides from the saved coordinates alone whether a bar "was never moved" (within two
  pixels of a default), so a bar the player moved by a pixel or two snaps back; a flag set when the
  player drags a bar would be exact.
  Override bar: given the new look on 2026-11-13 (`MistUI/modules/actionbars/overridebar.lua`,
  stock tree, art only), not run in the game yet. To check: the frame and dividers sit on the six
  buttons at scale 0.8 in all four stock layouts (with or without the aim controls and the leave
  button); the leave button next to the last slot; the aim controls keep the vehicle's own art;
  the bar's XP, health and power bars are hidden (the vehicle's health shows on the player frame,
  but XP is not shown while in such a vehicle); the bar may sit a little left of the screen centre
  because the stock layout keeps room for micro buttons that stay in their own bar here. The scale
  is `mainbars.scale_overridebar` ("Vehicle Bar Scale" in the Action Bars settings).

- **2026-11-10 - Action button styling: not run in the game yet.**
  `MistUI/modules/buttons.lua` loads for the main bar and the four extra bars. Not checked in the game:
  the icon corners (three textures per icon mirror what the stock code does to the icon), the glow of a
  proc on a restyled button, spell flyout arrows, charges, the green ring of equipped items, key text on
  empty main bar slots (the module keeps them shown), and that nothing is blocked in combat. The
  module writes `rangeTimer`, a field the stock button code owns, to bring the range dot back after a
  restyle; a review flagged it as a possible source of "action blocked" messages.
  `addon.StyleVehicleButtons`, `StylePetButtons`, `StyleStanceButtons` and `StylePossessButtons` are
  defined but only called by the parked bar files. The settings tab for buttons is part of the parked
  action bar tab. Fields the module sets on buttons still carry the upstream `_dui` prefix, shared with
  parked files.
  Suggested fix: test with spells, macros, an item with a count, a proc, a flyout (mage portals,
  hunter pets), dragging a spell onto an empty slot, and combat; rename the prefix once the parked
  files that read it are ported.

- **2026-11-10 - Micro menu and bag bar: not run in the game yet.**
  `MistUI/modules/micromenu.lua` and `MistUI/modules/bagbar.lua` are new code (see
  `docs/decisions/0006-rewrite-the-micro-menu-and-bag-bar.md`). Known limits: the stock main bar shows
  empty spaces where its micro and bag buttons were until the action bars are ported; the override bar
  and the pet battle bar show the same; the guild button shows no guild emblem; the game menu button
  uses the shop icon while the store is off; the glow of a micro button alert (new talent point) keeps
  its stock size on a smaller button and may sit off centre.
  Suggested fix: test every button (opens its window, looks pressed while open), a vehicle with an
  action bar (`.cast 66393` in Kezan) with "Hide on Vehicle" off and on, moving and scaling both bars
  in edit mode, the fold arrow, empty and filled bag slots, and the fading settings.

- **2026-11-10 - Bag windows: not run in the game yet.**
  `MistUI/modules/bags_skin.lua`, `bags_newitems.lua` and `bags_usability.lua` load. Known limits: the
  glow on new items only works while the bag skin is on; the skin calls the stock functions that place
  the tracked currency bar from addon code, which may mark the backpack code as changed by an addon;
  the red tint trusts red tooltip lines and remembers the answer per item;
  `MistUI/modules/bagsort.lua`, `altmoney.lua` and `bagster/` stay parked.
  Suggested fix: test opening every bag and the bank, a one-slot bag if available, the search box of
  the backpack, a tracked currency, looting an item (glow, gone on hover), an item of another class
  (red, also in the bank), and using a potion from the bag in combat without an "action blocked"
  message.

- **2026-11-10 - Quest tracker placement: not run in the game yet, with one known risk.**
  `MistUI/modules/questtracker.lua` moves the stock tracker, which holds protected quest item buttons.
  The module is written so that the tracker never redraws as addon code (see
  `docs/decisions/0005-keep-the-stock-quest-tracker.md`), but only the game can confirm it. The tracker
  also no longer makes room by itself for the right action bars or the arena frames, and it cannot
  fade. `MistUI/modules/objectivetracker.lua` and `MistUI_Options/panel/tab_questtracker.lua` stay
  parked.
  Suggested fix: test that the tracker stands clear of the minimap, move it in edit mode and reload;
  then track a quest that has a usable item, make progress on it during combat, and check that no
  "action blocked" message appears and that the item button still works.

- **2026-11-10 - Second in-game test passed; coverage is still one character.**
  Buffs, cast bars and the first unit frames ran on the 5.4.8 client on the same level 28 shaman, solo.
  The first run raised one error (pet frame draw sublevels, fixed); after the fix the owner reported that
  everything works and the error recorder showed no new entry. Seen in screenshots: the player and
  target frames with the new art, the combat glow and the PvP icon on the player frame, debuffs under
  the target, buffs top right with the collapse arrow, and the edit mode movers of every loaded frame.
  Not covered: a group (party, role icon, leader crown, raid tab), a pet, a vehicle, another class
  (runes, combo points, class resource bars), a focus or target of target in play, a dead target.
  Suggested fix: cover these with GM characters before the release.

- **2026-11-10 - Unit frames: first slice only; tested on one shaman.**
  Loaded: `player.lua`, `target.lua`, `focus.lua`, `tot.lua`, `tof.lua`, `pet.lua`, `totemframe.lua` and
  their shared files in `MistUI/modules/unitframes/`, `combopoints.lua`, `party.lua` and `boss.lua`
  (see its own entry). The layers pair (heal prediction and absorb overlays) was deleted on 2026-11-16:
  the stock frames already draw both on this client. Known gaps: holy power, shadow orbs, the warlock bars,
  eclipse and chi follow the new mana bar since 2026-11-13 (`classpower.lua`, same offset as from the
  stock mana bar, movable in edit mode as "Class Power"), not seen in the game yet; stagger and the
  small mana bar of druids and monks follow the mana bar the same way since 2026-11-16 (no edit mode
  box of their own: moving the class bar leaves them by the mana bar), not seen in the game yet; the
  encounter power bar keeps its stock anchor and may overlap the new art; the stock heal prediction and absorb textures, the
  quest and pet battle icons of the target frame and the multi-group icon of the player frame were not
  placed for the new art; totem timers can only be moved by shamans, while the client also shows them
  to other classes; a player frame that was unlocked and dragged with the stock menu is not handled;
  the target-of-target frame ignores the stock "show in raid / party / solo" choice.
  Party frames, not run in the game yet: they show no heal prediction or absorbs (the stock textures
  are faded); the stock dispel highlight (`PartyMemberFrameNStatus`), ready check, phasing icon, party
  pet frames and voice icons keep their stock spots and art; a click on a bar targets the member even
  while the frame shows the member's vehicle; the frames always make room for the raid frame manager
  on the left edge; the hover buttons over the bars are secure buttons that are created on first use,
  which may be blocked if that first use falls in combat. Test with a second player or a server bot: join and leave, a raid, the raid-style
  party frames option, a member in a vehicle, a dead and an offline member.
  Suggested fix: test on a shaman (totems), then with `.levelup` characters of each class with a class
  bar, in a vehicle, in a group and in combat; place what overlaps; then port the parked files.

- **2026-11-10 - Chat: not run in the game yet, and two known limits.**
  `MistUI/modules/chatmods.lua` replaces the stock function that handles a click on a chat link, so that
  a click on an address opens the copy popup. Everything that runs from a link click after that counts
  as addon code for the client, which may block protected actions started from a chat link menu. The
  minimize button of the chat button frame, new on this client, does not fade with the other buttons.
  Suggested fix: test an address in chat, the tab double-click copy, `/tt`, the edit box positions, a
  right click on a player name in chat (the menu and its entries); if a menu entry is blocked, detect
  addresses without replacing the stock function.

- **2026-11-10 - Tooltips: not run in the game yet.**
  `MistUI/modules/tooltip.lua` loads unchanged. Suggested fix: test a player, a mob and an object
  tooltip, a buff tooltip (caster line), the cursor anchor option, and the tooltip mover in edit mode.

- **2026-11-09 - Buffs: tested solo on 2026-11-10; two known gaps.**
  `MistUI/modules/buff_frame.lua` and `auraborders.lua` load. The row wrap
  count does not reserve a cell for the raid buff tray button when it shows
  (the stock layout does), which also holds for DragonUI on 3.3.5a. The Auras
  tab (`MistUI_Options/panel/tab_auras.lua`) already shows the target and
  focus aura settings, which do nothing until the unit frames are ported.
  Suggested fix: test in a group with consolidated buffs on, with weapon
  enchants, and in combat (the buff buttons can be cancelled by click, so
  moving them in combat may be blocked); then fix the wrap count.

- **2026-11-09 - Cast bars: tested solo on 2026-11-10; known gaps.**
  `MistUI/modules/castbar.lua` handles the player, target and focus. The pet,
  boss and arena cast bars keep their stock look. Casts made from a vehicle
  are not shown on the custom player bar. A cast stop is not matched to the
  cast's line id as the stock bar does. The module does not look at the
  stock "show enemy cast bar" setting.
  Suggested fix: test casts, channels, interrupts (the "interrupted by" text
  reads the combat log), a non-interruptible cast, and target and focus bars;
  then decide which gaps to close.

- **2026-11-09 - Minimap: stock elements not placed yet; pruning not run in the game.**
  `MistUI/modules/minimap.lua` and `minimap_collector.lua` were changed where
  the 5.4.8 client differs (queue button, tracking, clock, pings, blip sheet),
  and on 2026-11-10 lost the second art style, the SexyMap sharing modes and
  the decoration settings (not run in the game yet). The guild and challenge
  mode difficulty flags and the recording button keep their stock positions.
  The queue eye sits in its own mover and keeps its stock look. The parked
  `MistUI/modules/compatibility.lua` still holds its SexyMap section and the
  `MistUI/Locales/enUS.lua` texts it uses; drop both when that file is ported.
  The art sync still copies the removed style's minimap textures (unused).
  Suggested fix: test both minimap styles (round and square), the collector in
  both styles, the zoom buttons, rotation on and off, farm mode and a reload;
  then place the remaining stock elements with the minimap visible.

- **2026-11-09 - Edit mode: settings of parked modules and removed styles remain.**
  `MistUI/core/editor_settings.lua` still defines the per-frame dialogs of
  parked modules. They cannot be reached while those modules are parked. The
  manager's sections are hidden until their module loads.
  Suggested fix: prune each block when its module is ported.

- **2026-11-09 - Edit mode closes itself when combat starts.**
  `MistUI/modules/editor_mode.lua` saves positions inside the
  `PLAYER_REGEN_DISABLED` handler and relies on protected frames still being
  movable at that moment.
  Suggested fix: confirm in game on 5.4.8 once a protected frame (action bar,
  unit frame) is registered with the editor.

- **2026-11-09 - A module can be enabled in the settings while its code is parked.**
  `addon:IsModuleEnabled` (`MistUI/core/api.lua`) only reads the saved flag.
  The texture preload in `MistUI/core/texture_warmup.lua` therefore still
  loads the art of parked modules that are enabled by default.
  Suggested fix: harmless for now; revisit once most modules are ported.

- **2026-11-09 - Fonts for non-English clients are unverified.**
  `MistUI/core/fonts.lua` names the Russian and Simplified Chinese client
  fonts of 5.4.8, but only an English client was available to test with.
  Suggested fix: verify on those clients before adding their languages.

- **2026-11-09 - Settings and defaults for features that were left out (mostly done 2026-11-13).**
  The defaults of the modules that were never imported and the texts no file uses any more are
  gone (see the changelog), and so are the files, settings and texts of the modules dropped on
  2026-11-16 (decision 0009). Left: the texts and defaults only the modules still waiting for their
  port use (loot roll, bag sort and the others in decision 0009); the parked
  `MistUI_Options/panel/tab_modules.lua` (module on/off list).
  Suggested fix: remove each block when its parked file is ported.

- **2026-11-09 - Second art style still in the code.**
  Unit frames (updated 2026-11-10): the "Forever" skins, dragons and settings are gone and the style
  getters in `MistUI/modules/unitframes/uf_skins.lua` always answer the one style, but the branches that
  ask them remain (level circle, PvP badge, name spot, status icon cells) in `player.lua`,
  `target_style.lua`, `uf_core.lua`, `uf_compact.lua` and the parked unit frame files, with the saved
  defaults in `MistUI/database.lua`. The minimap no longer carries the style (2026-11-10). Note that
  `MistUI/utils/forever_*.lua` is also the widget kit the settings panel and edit mode are built with,
  and that part of the one style's art lives in a texture folder named "Forever"; both stay.
  Suggested fix: remove the dead branches once the unit frames pass their in-game test, so a layout
  fault found there is not confused with the cleanup.

- **2026-11-10 - A name in the stock source can still be missing in the client.**
  The checker accepts every name the stock 5.4.8 interface source mentions. That source still calls
  `GetKeyRingSize`, which the client program does not contain (the key ring was removed); a call would
  raise an error. Found by searching the client program for the name while porting the bag code.
  Location: `tools/lib/stockindex.mjs`.
  Suggested fix: when a port keeps a call to a function that only old-looking stock code uses, search
  the client program for the name by hand; longer term, build the list of client
  function names from the client program and check calls against it.

- **2026-11-09 - The checker does not verify texture paths or inline XML scripts.**
  Location: `tools/lib/checker.mjs`.
  Suggested fix: add a check that every texture path used by loaded code
  exists in the synced artwork folders, and analyse `<Scripts>` blocks in XML.

- **2026-11-09 - Nameplate data tables are missing.**
  The nameplate module expects aura duration and rare NPC tables that were
  generated from 3.3.5a game data and were not imported.
  Location: `MistUI/modules/nameplates/`.
  Suggested fix: decide during the nameplate port whether each feature can
  use live client data instead, or should be dropped.
