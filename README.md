# Mist-UI

Mist-UI is a retail-style interface addon for the 5.4.8 (build 18414) game
client, made for and tested on SkyFire-based 5.4.8 servers. It replaces the
stock unit frames, action bars, minimap, cast bars, buffs, micro menu, bags,
nameplates and world map with a modern look, adds an edit mode to move and
size everything, and bundles the small helpers most players install separately
(bag sorting, item levels, loot rolls and more), all set from one settings
panel. It is a port of [DragonUI](https://github.com/NeticSoul/DragonUI) by
NeticSoul and contributors, which was written for the 3.3.5a client.

> **Status: first public release (0.1.0).** Tested on one SkyFire-based
> server with a few classes. Expect rough edges, and please
> [report what you find](../../issues/new/choose): the bug form asks for
> everything needed to reproduce it.

## Features

| Area | What you get |
|---|---|
| Unit frames | Player, target, focus, their targets, pet, party and boss frames in the retail style, with class colors, portraits and text options |
| Raid frames | The game's own raid frames (and raid-style party frames) in the retail look, with a colored outline on members who have a debuff you can dispel |
| Class resources | Holy power, chi, shadow orbs, soul shards, burning embers, demonic fury, eclipse, runes, stagger and the druid and monk mana bar, placed under the player frame or anywhere you like |
| Action bars | Retail bar art, button styling, cooldown numbers, a global cooldown indicator, stance, pet, possess and vehicle bars |
| Cast bars | Player, target and focus cast bars with latency, channel ticks and interrupt state |
| Buffs and debuffs | Movable buff and debuff rows with sorting and dispel-type borders |
| Minimap | Retail minimap with a button collector for other addons' minimap buttons |
| Nameplates | Health, cast bars, auras, quest and elite markers, threat colors and stacking |
| World map | A windowed map with a quest panel, quest details, search, zoom and coordinates |
| Bags | One bag window for bags and bank (and guild bank), search, sorting, gray item selling, other characters' bags and gold, item counts per character in tooltips |
| Items | Item level and quality borders on gear, bags and the character window, equipment comparison |
| Combat helpers | A loot roll window, a low health alert and a personal resource bar near the center of the screen |
| Chat and tooltips | Cleaner chat frames and editbox, styled tooltips with health bars |
| Edit mode | `/mist edit` shows every movable part; drag with snap to grid and guide lines, nudge, undo, reset, and save layouts as presets |
| Settings | One panel (`/mist` or the **MistUI** button in the Escape menu) with search and profiles, optionally one profile per specialization |

Every feature can be switched off on its own in the Modules tab; a switched-off
feature hands its part of the screen back to the stock interface.

## Requirements

- The 5.4.8 (build 18414) client, interface version `50400`, on any 5.4.8
  server. Development and testing happen on a SkyFire-based server.
- The artwork, which is not part of this repository or of the release zip. The
  install steps below fetch it (see [docs/ARTWORK.md](docs/ARTWORK.md) for why).
- For development only: [Node.js](https://nodejs.org/) 20 or newer and git.

## Install

1. Download `MistUI-<version>.zip` from the
   [Releases page](../../releases) of this repository.
2. Unzip it into the client's `Interface/AddOns/` folder, so that `MistUI`
   and `MistUI_Options` sit side by side there.
3. Get the artwork: on Windows, double-click `MistUI/Install-Artwork.cmd`. It
   downloads DragonUI's public source archive from GitHub and copies the
   texture folders Mist-UI uses (about 50 MB) into `MistUI/Textures/` and
   `MistUI_Options/Textures/`. On other systems, or without internet access on
   the game PC, follow the manual steps in [docs/ARTWORK.md](docs/ARTWORK.md).
4. Start the game and check that both are enabled in the AddOns list.
5. Type `/mist` (or press Escape and click **MistUI**) to open the settings, and
   `/mist edit` to move things.

Without the artwork the addon still loads, but its frames show as plain green
boxes; Mist-UI says so in a message at login. The game only finds new files
when it starts, so close it before running the artwork step. Run the step again
after updating Mist-UI if the release notes say the artwork changed.

## Commands

| Command | Action |
|---|---|
| `/mist` | Open the settings (also the **MistUI** button in the Escape menu) |
| `/mist edit` | Toggle edit mode |
| `/mist errors` | Show the errors Mist-UI recorded (`on`, `off`, `clear`) |
| `/mist help` | List every command |

Mist-UI keeps its last 50 errors in its saved settings file
(`WTF/Account/<account>/SavedVariables/MistUI.lua`, under `errorLog`), written
on logout or `/reload`. Attach that part of the file when you report a problem.

## Reporting problems and contributing

Use the [bug report form](../../issues/new/choose). Pull requests are welcome;
read [CONTRIBUTING.md](CONTRIBUTING.md) first. Test reports from classes and
servers other than the ones listed in the status note are the most useful
contribution right now.

## Development

    npm install        # one development dependency: a Lua parser
    npm test           # tests for the tools in tools/
    npm run check      # checks the addon itself
    npm run art        # copies the artwork from a local DragonUI checkout
    npm run harness    # plays a short session in a fake client (needs a portable Lua 5.1)
    npm run release    # builds dist/MistUI-<version>.zip from the committed state

`npm run check` verifies that every file in the load list exists, that every
Lua file parses and stays inside the limits of the client's Lua compiler, that
draw sublevels are in the range the client accepts, and that loaded code only
uses and hooks functions, frames, events and templates that exist in the 5.4.8
client.
For the last part it needs a copy of the stock 5.4.8 interface source, which
is not part of this repository.

### Environment variables

There is no `.env` file. These optional variables exist:

| Variable | Purpose | Default |
|---|---|---|
| `MISTUI_UI_SOURCE` | Folder with the stock 5.4.8 interface source used by `npm run check` and `npm run harness` | `../ui-source-5.4.8` |
| `MISTUI_LUA51` | Lua 5.1 interpreter for `npm run harness` | `../tools-lua51/` |
| `MISTUI_CLIENT_EXE` | The client program, read only, for the names of the client's own functions in `npm run harness` | none |

Without the interface source the name checks are skipped and the tool says so.

## Project structure

| Path | Purpose |
|---|---|
| `MistUI/` | The addon: `core/` (framework), `utils/` (shared widgets and helpers), `modules/` (one file or folder per feature), `libs/` (bundled libraries), `Locales/` |
| `MistUI_Options/` | The settings panel, loaded on demand when `/mist` is first used |
| `tools/` | Development checks, the offline harness, the artwork sync and the release builder |
| `tests/` | Tests for the tools |
| `docs/` | Roadmap, artwork setup, upstream record and decision records |
| `.github/` | The bug report form |

A module only runs once it is listed in `MistUI/modules/modules.xml`.

## Credits

Mist-UI exists because of DragonUI. The design, the framework and nearly all
of the code come from [DragonUI](https://github.com/NeticSoul/DragonUI) by
NeticSoul and its contributors, under the MIT License. DragonUI in turn builds
on the work of other addon authors; all of them are credited in
[MistUI/THIRD_PARTY_NOTICES.md](MistUI/THIRD_PARTY_NOTICES.md).

## License

Mist-UI's code is released under the [MIT License](LICENSE). Bundled libraries,
fonts and code adapted from other projects keep their own licenses, listed in
[MistUI/THIRD_PARTY_NOTICES.md](MistUI/THIRD_PARTY_NOTICES.md) with the full
texts in [MistUI/LICENSES/](MistUI/LICENSES/).

This repository contains no game artwork. Mist-UI is a free, fan-made addon
and is not affiliated with or endorsed by the game's publisher.
