# Upstream record

Mist-UI is based on [DragonUI](https://github.com/NeticSoul/DragonUI) by
NeticSoul and contributors (MIT License).

| | |
|---|---|
| Upstream commit | `407dd0069f2b853388483e9e7e169198abf4c6d0` |
| Upstream version | v3.0 plus 20 commits (2026-11-06) |
| Imported on | 2026-11-09 |

The first commit of this repository holds the imported files unmodified, under
their upstream names. The rename to MistUI is the next code commit, so
`git diff` between the two shows exactly what the rename touched.

## Taken from upstream

- The framework: `core/`, `utils/`, `config.lua`, `database.lua`, `core.lua`.
- The settings panel: `DragonUI_Options/` (now `MistUI_Options/`).
- The HUD modules and the nameplates under `modules/`.
- The bundled libraries that work on the 5.4.8 client, the two fonts and the
  English locale.

## Left out

| What | Why |
|---|---|
| All texture files | Game artwork, outside the MIT License. Fetched separately, see [ARTWORK.md](ARTWORK.md) |
| Generated data tables (`data/`) | Game data for 3.3.5a, wrong for 5.4.8 and not redistributable here |
| LibHealComm-4.0, AbsorbsMonitor-1.0, LibSwingTimer-1.0 | Built around 3.3.5a internals; the 5.4.8 client reports incoming heals and absorbs itself |
| Minimap decoration presets (`modules/minimap_decorations.lua`) | Adapted from SexyMap under a permission that was given to DragonUI only |
| Nine of the ten languages | English only until the texts stop changing |
| Window modules: character panel, inspect, dressing room, spellbook, professions, collections, vendor, mail, flight map, quest dialog, loot window, level-up banner | Out of scope for the first release, and several depend on 3.3.5a game data |
| Talent window | Built around the 3.3.5a talent trees; the 5.4.8 client has no talent tree. Not planned |
| World map data and the features built on it: `fogdata.lua`, `entrancedata.lua`, `graveyarddata.lua`, `flightpointdata.lua`, `inndata.lua`, `zonelevels.lua`, `fog.lua`, `mappins.lua`; and `grouppins.lua` | Generated from 3.3.5a game data and a server database. The map itself was imported on 2026-11-13 from the same commit, see [decision 0008](decisions/0008-world-map-without-game-data.md); the stock 5.4.8 party pins are already class coloured |
| Version check, swing timer | Tied to DragonUI's own releases, or of little use on 5.4.8 |

## Removed after the import

These came over with the import and were removed while bringing the framework
up on the 5.4.8 client.

| What | Why |
|---|---|
| AceComm-3.0 with ChatThrottleLib | Only the version check used it |
| `core/combatlog_fix.lua` | Works around a combat log fault of the 3.3.5a client |
| `core/modelview.lua` | Model viewer helpers used only by the window modules |
| `MistUI_Options/panel/tab_panels.lua` | Settings for the window modules |
| `Bindings.xml` | Its key bindings belong to the extra action bar and to window modules. The extra bar bindings return when that bar is ported |

## Taking later upstream changes

Upstream keeps moving. To bring a fix over, compare the upstream file at the
commit above with its current version, apply the relevant change to the
renamed file here, and credit it in the commit body ("Based on DragonUI
commit <hash> (MIT)").
