# 0005. Keep the stock quest tracker and only place it

- **Date:** 2026-11-10
- **Status:** Accepted

## Context

The stock quest tracker sits under the bottom edge of the restyled minimap,
because the client anchors it to the stock minimap cluster.

DragonUI answers this with a tracker of its own
(`MistUI/modules/objectivetracker.lua`): it hides the stock tracker and draws
quests, tracked achievements and quest timers itself. That fits the 3.3.5a
client, whose tracker shows nothing else.

The 5.4.8 tracker shows more. It registers five kinds of content
(`WatchFrame_OnLoad` in the stock `WatchFrame.lua`): scenario objectives, the
popups for quests that are accepted or completed automatically, quest timers,
tracked achievements and tracked quests. It also has a sort and filter menu
on its header. A replacement that draws only three of the five would hide the
popups, and a quest that is completed from its popup could no longer be
handed in from the tracker.

Moving the stock tracker has a known risk on this client. The tracker holds
protected quest item buttons. If addon code makes the tracker redraw itself,
the client treats that redraw as addon code, and a later redraw during combat
can be blocked. Setting the tracker's size from addon code triggers such a
redraw immediately.

## Decision

Mist-UI keeps the stock tracker with all its content. A new module
(`MistUI/modules/questtracker.lua`) only places it:

- it marks the tracker as placed by the user, which is the condition under
  which the stock layout code stops positioning it;
- it sets a top and a bottom anchor and never a size, the same way the stock
  code gives the tracker its height;
- it does this outside combat only, and offers a box in edit mode to move it.

`objectivetracker.lua` stays in the repository, parked.

## Consequences

- Nothing the stock tracker shows is lost, and far less code runs.
- The tracker keeps its stock look: no restyled header, no restyled quest
  markers. The header, font size and fade settings of the DragonUI tracker
  have no effect and are not offered.
- The tracker no longer shifts by itself when the right action bars are shown
  or in an arena, which the stock layout did. The player moves it in edit
  mode.
- The redraw risk is reduced, not proven absent. It needs an in-game test: a
  tracked quest with a usable item, progress on it during combat, and no
  "action blocked" message. If that test fails, the fallback is to port the
  parked tracker and add the two missing kinds of content to it, in a new
  decision record.
