# Third-Party Notices

Mist-UI's own code is released under the MIT License (`LICENSE` at the repository root,
`LICENSE.txt` inside the `MistUI` addon folder). This file lists everything in the two addon
folders that is not Mist-UI's own work, or that is under other terms.

Paths are relative to the repository root, except `LICENSES/`, which is the folder next to this
file (`MistUI/LICENSES/`). Users install only the `MistUI/` and `MistUI_Options/` folders, so this
file and `LICENSES/` live inside `MistUI/` to ship with the addon, and `MistUI_Options/LICENSES/`
holds the texts that apply to that folder.

## DragonUI (the base of this project)

Mist-UI is a port of DragonUI to the 5.4.8 client. DragonUI is Copyright (c) 2026 NeticSoul and
DragonUI contributors, https://github.com/NeticSoul/DragonUI, released under the MIT License. The
files keep their original copyright headers. `docs/UPSTREAM.md` in the repository records the
upstream commit the code was taken from and which parts were left out.

The notices below were inherited from DragonUI and cover the code Mist-UI kept. Where they say a
component was adapted or modified, that work was done by the DragonUI contributors unless a later
entry in `CHANGELOG.md` says otherwise.

## Artwork and game data

The repository contains no game artwork and no tables generated from the game's data files.

The texture files the addon draws with (the `MistUI/Textures/` and `MistUI_Options/Textures/`
folders, which are not in the repository) are World of Warcraft user-interface artwork
(c) Blizzard Entertainment, Inc. That artwork is not covered by Mist-UI's MIT License, nor by the
MIT licenses of the projects named in this file. `docs/ARTWORK.md` explains how the files are
obtained. A texture that another project cropped, recoloured, re-encoded or repacked is still
Blizzard's artwork.

The code refers to that artwork by file name and by texture coordinates. Some of those file names
and coordinates came from DragonflightUI and RetailUI (see below).

World of Warcraft, Warcraft and Blizzard Entertainment are trademarks or registered trademarks of
Blizzard Entertainment, Inc. Mist-UI is a free, fan-made addon and is not affiliated with or
endorsed by Blizzard Entertainment.

## Ace3 and CallbackHandler-1.0

Copyright (c) 2007, Ace3 Development Team. BSD-style license with an extra clause that forbids
redistributing a stand-alone version without written permission. Mist-UI only embeds these
libraries, loaded from its own TOC files, which the license allows. Full text:
[LICENSES/Ace3.txt](LICENSES/Ace3.txt).

- `MistUI/libs/`: AceAddon-3.0, AceConsole-3.0, AceDB-3.0, AceEvent-3.0, AceLocale-3.0,
  AceSerializer-3.0, AceTimer-3.0, CallbackHandler-1.0.
- `MistUI_Options/libs/`: AceConfig-3.0, AceGUI-3.0, CallbackHandler-1.0.

CallbackHandler-1.0 is published in the Ace3 repository and is covered by the same text.
`MistUI/libs/AceLocale-3.0/AceLocale-3.0-MistUI.lua` is a fork of AceLocale-3.0 made by DragonUI
and renamed here; it remains under the Ace3 license.

Apart from that fork, these libraries are the unmodified files of Ace3 `Release-r1109`
(2014-02-19, https://github.com/WoWUIDev/Ace3), the last release made for the 5.4 client. They
replace the older versions DragonUI ships for 3.3.5a.

## zlib License: LibDeflate

`MistUI/libs/LibDeflate/LibDeflate.lua` (1.0.2) is Copyright (C) 2018-2020 Haoqian He, licensed
under the zlib License. The license is kept in the file's own header; the file is unmodified.

## Public-domain libraries

- LibStub (`MistUI/libs/LibStub/`, `MistUI_Options/libs/LibStub/`): placed in the public domain.

## MIT License: RetailUI

Copyright (c) 2024 Dmitriy (a3st), https://github.com/a3st/RetailUI. Full text:
[LICENSES/MIT-RetailUI.txt](LICENSES/MIT-RetailUI.txt).

Code adapted from RetailUI: `MistUI/modules/minimap.lua`, `MistUI/modules/buff_frame.lua`,
`MistUI/core/api.lua`. RetailUI's MIT License covers only RetailUI's own contribution, not the
game artwork its texture names refer to.

## MIT License: Combuctor (via KPack)

Copyright (c) 2010 Jason Greer (Tuller) and João Cardoso (Jaliborc). Combuctor's repository carried
an MIT License from September 2010 to September 2012; the file holds its December 2011 text. The
code reached DragonUI through KPack's Combuctor module. Full text:
[LICENSES/MIT-Combuctor.txt](LICENSES/MIT-Combuctor.txt).

Files containing adapted code: the Bagster module in `MistUI/modules/bagster/`, chiefly
`bagster.lua`, `bagster_classes.lua`, `bagster_frame.lua`, `bagster_data.lua`,
`bagster_system.lua` and `bagster.xml`.

## MIT License: KPack ChatMods

KPack by Kader (bkader), https://github.com/bkader/KPack, which declares "MIT/X" in its TOC.
Full text and details: [LICENSES/MIT-KPack.txt](LICENSES/MIT-KPack.txt).

File containing adapted code: `MistUI/modules/chatmods.lua`.

## MIT License: NotPlater

Copyright (c) 2023 RichSteini, https://github.com/RichSteini/NotPlater (the code came from
NotPlater 3.2.4, whose LICENSE is this MIT text). Full text:
[LICENSES/MIT-NotPlater.txt](LICENSES/MIT-NotPlater.txt).

File containing adapted code: `MistUI_Options/panel/controls.lua` (the spell-filter prompt popup
and the spell-filter import/export dialog, with the code that opens it).

## MIT License: DragonflightUI

Copyright (c) 2022 Karl-HeinzSchneider, https://github.com/Karl-HeinzSchneider/WoW-DragonflightUI.
Full text: [LICENSES/MIT-DragonflightUI.txt](LICENSES/MIT-DragonflightUI.txt).

- Small code snippets adapted from DragonflightUI: `MistUI/core/api.lua` (nine-slice helper),
  `MistUI/modules/micromenu.lua`, `MistUI/modules/bagbar.lua`, `MistUI/modules/mainbars.lua`,
  `MistUI/modules/xprepbar.lua`, `MistUI/modules/smallbars.lua`,
  `MistUI/modules/bagster/bagster_classes.lua`.
- Texture coordinates for unit frames, cast bars, the experience and reputation bars, edit mode,
  bags and the micro menu follow DragonflightUI's layout of that artwork.

DragonflightUI's MIT License covers only Karl-Heinz Schneider's own contribution, not the game
artwork its texture names refer to.

## Bundled fonts

| Font | Path | License | License file |
|---|---|---|---|
| Fira Sans Condensed SemiBold (© 2012-2015 The Mozilla Foundation and Telefonica S.A.) | `MistUI/Fonts/FiraSansCondensed-SemiBold.ttf` | SIL Open Font License 1.1 | [LICENSES/OFL-1.1.txt](LICENSES/OFL-1.1.txt) |
| PT Sans Narrow Bold (© 2009-2010 ParaType Ltd; Reserved Font Names "PT Sans", "PT Serif", "ParaType") | `MistUI_Options/fonts/PTSansNarrow.ttf` | SIL Open Font License 1.1 | [LICENSES/OFL-1.1.txt](LICENSES/OFL-1.1.txt) |

Both font files are shipped unmodified, under the SIL Open Font License 1.1, whose full text is in
`LICENSES/OFL-1.1.txt`. Fira Sans Condensed comes from the Google Fonts collection
(`ofl/firasanscondensed`); PT Sans Narrow also carries the full OFL text inside the font file itself.

## Not carried over from DragonUI

These DragonUI components are not part of Mist-UI, so their terms do not apply here: the
AbsorbsMonitor-1.0 library (GPL), LibHealComm-4.0, LibSwingTimer-1.0, AceComm-3.0 with
ChatThrottleLib, the SexyMap minimap
border presets (which DragonUI uses under a permission given to DragonUI only), the GearScore
formula, and every data table generated from game or server databases.
