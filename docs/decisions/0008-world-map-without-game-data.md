# 0008. Bring the world map into the first release, without game data

- **Date:** 2026-11-13
- **Status:** Accepted. Amends [0002](0002-first-release-scope.md), which left the world map out.

## Context

DragonUI rebuilds the windowed world map in the style of the later game: a
window with a title band, a breadcrumb (World, continent, zone, floor), a quest
list side panel with quest details, zoom and pan, coordinates, fading while
moving, and its own party pins. It also draws extra pins (inns, flight
masters, graveyards, dungeon entrances), fills in unexplored areas and shows
zone level ranges. Those extras come from tables generated from the 3.3.5a
client's data files and from a server database.

The owner asked for the map on 2026-11-13.

The 5.4.8 stock map differs from the 3.3.5a one in ways that matter here: the
objectives checkbox became a "Show" menu (quest objectives, bosses, dig sites,
pet tamers); the player arrow is two flat textures instead of a 3D model;
completed quest pins are numbered without gaps, so the 3.3.5a "quest pin
guard" that switched the `questPOI` setting off and drew pins of its own is
not needed; party and raid pins are already drawn in class colours; quest
areas are drawn with `DrawBlob`; and `GetCurrentMapAreaID` answers in the same
ids as `SetMapByID`.

## Decision

Port the map window, the breadcrumb, the quest panel and details, zoom,
coordinates, fading and the landmark and quest pin sizing. Leave out every
feature that needs generated game data: unexplored areas, the extra pins and
the zone levels. Their data cannot go into this repository (see
[0003](0003-code-only-repository.md)), and it would be wrong for 5.4.8, where
many zones were reshaped.

Leave out DragonUI's own party pins: the stock 5.4.8 pins are already class
coloured, and the stock code rewrites their texture coordinates every frame.

Keep the stock "Show" menu and let the player click it where it is placed in
the new window, so its handlers run as stock code. The quest panel's own
selection does not change the super tracked quest; picking a quest pin on the
map does, as in the stock map.

## Consequences

- The map is one more window module in the first release; the other window
  modules stay out.
- Features of the upstream map that need data are gone for good unless a
  5.4.8 source for the same facts turns up through the client's own functions.
- `/mistui worldmap off` and a reload bring back the stock map if the new one
  gets in the way.
