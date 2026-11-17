# 0007. Keep the stock action bar tree and paging

- **Date:** 2026-11-10
- **Status:** Accepted

## Context

DragonUI's action bar code (`mainbars.lua` and the files under
`modules/actionbars/`, about 10,000 lines) takes the action buttons away from
the stock bars. It gives them a parent of its own, and because the 3.3.5a
client then no longer knows which page the main bar shows, it drives the page
itself from a list of conditions (forms, stances, vehicles, possession).

The 5.4.8 client works differently:

- One stock controller (`ActionBarController.lua`) decides the page and writes
  it to `MainMenuBarArtFrame`. The twelve main buttons read the page from
  their parent. A button with another parent falls back to the plain page and
  loses the bonus, vehicle, override and temporary shapeshift pages.
- For a vehicle or an override with its own art, the controller slides
  `MainMenuBar` away, hides it and shows a separate bar (`OverrideActionBar`).
  Buttons outside `MainMenuBar` would stay on screen.
- The page conditions DragonUI lists are those of the older client. This
  client has more sources of a page and asks the game for the index of each.

## Decision

Mist-UI keeps every action button in its stock parent and leaves paging and
the override bar swap to the stock controller. A new, small
`MistUI/modules/mainbars.lua` replaces the DragonUI file and only does what
is allowed without owning the buttons:

- it anchors the buttons of the main bar and the four extra bars to boxes of
  its own, in a grid, and scales them;
- it draws the bar art (frame, dividers, end caps, page arrows) on a frame
  that is a child of the stock art frame, so the art hides and slides with
  the stock bar;
- it hides the stock art;
- it acts outside combat only, and queues a change made in combat.

The stock bar frames stay where the stock layout code puts them; only their
buttons are anchored elsewhere, so nothing has to stop the stock layout code.

DragonUI's look is kept: sizes, spacing, art and default positions are the
same and are credited in the file header.

## Consequences

- No addon code decides the bar page. Forms, stances, vehicles, possession
  and override bars page as on the stock interface, including cases DragonUI's
  list did not know.
- The settings "Page by Form" and the per-bar on and off switches of DragonUI
  are not offered: which extra bars are shown is set in the game's own
  interface options, as on the stock interface.
- A change to the layout made during combat is applied when combat ends.
- The stance, pet, possess and totem bars, the vehicle leave button and the
  override bar keep their stock look and place until they are handled the
  same way in later steps.
- Not run in the game yet. To check: paging with a form or stance, a vehicle
  with and without its own bar art, the extra bars switched on and off in the
  interface options, moving and scaling each bar in edit mode, and that no
  "action blocked" message appears in combat.
