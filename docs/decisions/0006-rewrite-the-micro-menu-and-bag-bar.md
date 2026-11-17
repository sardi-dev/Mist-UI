# 0006. Rewrite the micro menu and bag bar for the 5.4.8 client

- **Date:** 2026-11-10
- **Status:** Accepted

## Context

DragonUI's micro menu module (`micromenu.lua`, about 2,700 lines) restyles
the micro buttons and the bag buttons of the 3.3.5a client. Most of its size
is not the look. It is bookkeeping for that client: a key ring button, the
old dungeon finder eye, a second (grayscale) icon style, servers with extra
buttons, and several passes that repeat the same work because art went
missing after a reload there.

On 5.4.8 the module does not fit in four ways:

- The client has thirteen micro buttons, not twelve, and a different set:
  guild, dungeon journal, pets and mounts, and store buttons exist; the
  socials button does not. The store and help buttons take turns.
- The stock interface moves the buttons between three bars. The main bar, the
  override bar (vehicles) and the pet battle bar each call
  `UpdateMicroButtonsParent` and `MoveMicroButtons` when they are shown, and
  `UpdateMicroButtons` re-anchors the game menu button every time it runs.
  DragonUI stops this by replacing each button's `SetPoint` with an empty
  function, which also blocks the stock code and leaves a replaced method on
  a stock frame.
- The key ring button and the old dungeon finder frames do not exist, so the
  module raises errors at login.
- The latency indicator, which DragonUI builds as a frame of its own, already
  exists on the stock game menu button.

## Decision

Mist-UI replaces the module with two new, small files instead of patching the
old one:

- `MistUI/modules/micromenu.lua` puts the thirteen stock micro buttons in a
  bar of its own. It lets the stock functions run and takes the buttons back
  afterwards from secure hooks on `UpdateMicroButtonsParent` and
  `UpdateMicroButtons`. No stock method is replaced. The micro buttons are
  not protected frames, so this is allowed in combat.
- `MistUI/modules/bagbar.lua` puts the backpack and the four bag slots in a
  second bar, with the arrow that folds the slots away. It runs as part of
  the micro menu module.

Both keep DragonUI's look: the same artwork, sizes, offsets and texture
coordinates, which are credited in the file headers. The settings keep their
names, so the edit mode dialogs and the settings tabs still apply.

One art style only, as decided for the first release: the grayscale icon
option is gone.

## Consequences

- About 2,700 lines become about 770, with no code for frames this client
  does not have.
- On a vehicle with an override bar and in a pet battle the buttons stay in
  the Mist-UI bars. The stock override bar and pet battle bar show an empty
  space where the buttons would be. The bars hide in a pet battle, and on a
  vehicle when the "Hide on Vehicle" setting is on.
- Until the action bars are ported, the stock main bar also shows empty
  spaces where its micro buttons and bag buttons were.
- The guild button shows the guild icon, not the guild's emblem.
- The game menu button and the help button share two icons. With the store
  off, help has the question mark and the game menu has the remaining icon,
  as in DragonUI; with the store on, the store button has that icon and the
  game menu has the question mark.
- The fading settings of both bars (hover, combat) are driven from this
  module. The parked action bar code has entries for the same two bars, which
  must be removed when it is ported.
- Not run in the game yet. To check: every button opens its window and shows
  as pressed while it is open, a vehicle with an action bar, a level-up
  talent alert, guild member and non-member, the fold arrow, and empty and
  filled bag slots.
