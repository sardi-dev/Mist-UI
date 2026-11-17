-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- Modules read these tables at apply time, never into a file local, so a style switch is a refresh.
local addon = select(2, ...)
local UF = addon.UF

local ART = "Interface\\AddOns\\MistUI\\Textures\\UnitFrames\\"
local FULL_TEXCOORD = { 0, 1, 0, 1 }

-- Piece x, y are added to the offset the module already anchors with (SetPoint convention, +y up).
UF.SKINS = {
    mistui = {
        target = {
            -- Registered by the ring; the 2x wells sit 1 lower and 1 further left, hence the bars.
            background = { file = ART .. "HD\\Target-BACKGROUND", w = 256, h = 128, x = -0.5, y = -2.5 },
            border = { file = ART .. "HD\\Target-BORDER", w = 256, h = 128, x = 0, y = 0 },
            -- Centred on the HD ring; the 1x ring's thick inner shadow used to hide a 1.75 px offset.
            portrait = { w = 54, h = 54, x = -48.75, y = -14.75 },
            -- RIGHT of each bar to the portrait's LEFT.
            bars = {
                health = { w = 126, h = 20, x = -1.25, y = -2.25 },
                mana = { w = 133, h = 9.5, x = 6.25, y = -18.75 },
            },
            -- Combat flash BOTTOMLEFT on TargetFrame: its box lines land on the HD contours.
            flash = { x = 1, y = 24 },
            -- Name strip BOTTOMLEFT on HealthBar's TOPLEFT, placed like retail's; MistUI's PTR cells, solid left.
            nameBackground = {
                file = ART .. "HD\\Target-NameStrip", w = 134, h = 15.5, x = -0.5, y = -0.5,
                blend = "ADD", color = { 1, 1, 1 }, cells = {},
                tapped = { cell = "green", blend = "BLEND", desaturate = true, color = { 0.08, 0.08, 0.08 } },
            },
        },
        -- Player decoration without fat (fat keeps its 1x art): the HD target mirrored, on the health bar's LEFT.
        playerDecoration = {
            background = { file = ART .. "HD\\Target-BACKGROUND", w = 256, h = 128, x = -126.5, y = -30.5, tc = { 1, 0, 0, 1 } },
            border = { file = ART .. "HD\\Target-BORDER", w = 256, h = 128, x = -126.5, y = -30.5, tc = { 1, 0, 0, 1 } },
            -- On PlayerPortrait's RIGHT: health starts under the ring, both stop where the end line's chamfer begins.
            bars = {
                health = { w = 127, h = 20, x = -1, y = -1.5 },
                mana = { w = 131, h = 9, x = 126, y = -17.5 },
            },
            -- How far each bar's ends moved from the text layout; a 3rd value moves only the left text (mana's % under health's).
            edges = { health = { -2, -1 }, mana = { 0, -1, -6 } },
            -- The ring curves past the mana's start: half-unit strips of one texture column, { row down, left } on it.
            manaCorner = {
                step = 0.5, column = 7.5 / 128,
                rows = { { 1.5, -0.5 }, { 2, -0.5 }, { 2.5, -1 }, { 3, -1.5 }, { 3.5, -2 }, { 4, -2 }, { 4.5, -2.5 },
                         { 5, -3 }, { 5.5, -3.5 }, { 6, -4 }, { 6.5, -4.5 }, { 7, -5 }, { 7.5, -5.5 }, { 8, -6 },
                         { 8.5, -6.5 } },
            },
            -- The target's flash at its approved spot on this art, mirrored with it.
            glows = {
                status = { file = ART .. "Forever\\Target-InCombat", w = 188, h = 67, x = 66.5, y = 1.5,
                           tc = { 376 / 512, 0, 0, 134 / 256 } },
                combat = { file = ART .. "Forever\\Target-InCombat", w = 188, h = 67, x = 66.5, y = 1.5,
                           tc = { 376 / 512, 0, 0, 134 / 256 } },
            },
        },
        -- Fat decoration: the same art without the health/mana line (gen_uf_fat.py), at the same screen spot.
        playerDecorationFat = {
            background = { file = ART .. "HD\\Target-Fat-BACKGROUND", w = 256, h = 128, x = -126.5, y = -25, tc = { 1, 0, 0, 1 } },
            border = { file = ART .. "HD\\Target-Fat-BORDER", w = 256, h = 128, x = -126.5, y = -25, tc = { 1, 0, 0, 1 } },
            -- One bar from the health well's top to the mana well's bottom; the fat mana bar sits apart.
            bars = {
                health = { w = 127, h = 31, x = -1, y = -7 },
            },
            edges = { health = { -2, -1 } },
            -- The lower well opens left under the ring, as the mana's did: strips measured on this art.
            healthCorner = {
                step = 0.5, column = 7.5 / 128,
                rows = { { 20.5, -3 }, { 21, -3 }, { 21.5, -3 }, { 22, -3.5 }, { 22.5, -3.5 }, { 23, -4 },
                         { 23.5, -4 }, { 24, -4.5 }, { 24.5, -5 }, { 25, -5.5 }, { 25.5, -5.5 }, { 26, -6 },
                         { 26.5, -6.5 }, { 27, -7 }, { 27.5, -7.5 }, { 28, -8 }, { 28.5, -8 }, { 29, -9 },
                         { 29.5, -9.5 }, { 30, -10 }, { 30.5, -10.5 } },
            },
        },
        -- Both anchor to the portrait; the HD ring lands on its centre, the bar end 0.5 under the contour.
        small = {
            background = { file = ART .. "HD\\TargetofTarget-BACKGROUND", w = 128, h = 64, x = -0.5, y = -0.5 },
            border = { file = ART .. "HD\\TargetofTarget-BORDER", w = 128, h = 64, x = -0.5, y = -0.5 },
            -- Pet glows: the party's ToT glow, 1.25 right and 0.25 up of the border like there, ring on the portrait.
            flash = { file = ART .. "HD\\Party-InCombat", w = 114, h = 47, x = 0.75, y = 8.25,
                      tc = { 0, 228 / 256, 0, 94 / 128 } },
        },
        -- Retail's party shares the ToT's contour, so the HD ToT pair serves; all TOPLEFT on the party frame.
        party = {
            background = { file = ART .. "HD\\TargetofTarget-BACKGROUND", w = 128, h = 64, x = 1, y = -2 },
            border = { file = ART .. "HD\\TargetofTarget-BORDER", w = 128, h = 64, x = 1, y = -2 },
            bars = {
                health = { w = 71, h = 10, x = 44, y = -18.5 },
                mana = { w = 74, h = 7, x = 41, y = -29.5 },
            },
            -- Aggro glow: retail's ToT one in 2x, its ring on the portrait (lines and end within 0.25).
            flash = { file = ART .. "HD\\Party-InCombat", w = 114, h = 47, x = 2.25, y = -1.75,
                      tc = { 0, 228 / 256, 0, 94 / 128 } },
        },
        -- Normal player frame (fat keeps its own art); both pieces on the health bar's LEFT.
        player = {
            background = { file = ART .. "HD\\Player-BACKGROUND", w = 256, h = 128, x = -67, y = -28 },
            border = { file = ART .. "HD\\Player-BORDER", w = 256, h = 128, x = -67, y = -28 },
            -- The copper wedge's CENTER on the portrait's, moved with the ring.
            corner = { x = 16.5, y = -16.5 },
            -- Retail's 2x Status and InCombat, TOPLEFT on the background's TOPLEFT at retail's anchors.
            glows = {
                status = { file = ART .. "Forever\\Player-Status", w = 196, h = 71, x = 0, y = 0.5,
                           tc = { 0, 392 / 512, 0, 142 / 256 } },
                combat = { file = ART .. "Forever\\Player-InCombat", w = 192, h = 71, x = 1.5, y = 1,
                           tc = { 0, 384 / 512, 0, 142 / 256 } },
            },
            -- LEFT on PlayerPortrait's RIGHT, the art riding on the health: HD ring centred, health between its lines.
            bars = {
                health = { w = 125, h = 20, x = 2, y = -1 },
                mana = { w = 125, h = 9, x = 2, y = -17 },
            },
        },
    },
}

-- The fat decoration's combat and rest glows trace the frame too: the same pieces and spots, minus the
-- health/mana line. The glow art lives in the "Forever" texture folder, whatever the frame art.
do
    local decoration = UF.SKINS.mistui.playerDecoration
    local function fatGlow(glow)
        local copy = {}
        for k, v in pairs(glow) do
            copy[k] = v
        end
        copy.file = ART .. "Forever\\Target-InCombat-Fat"
        return copy
    end
    UF.SKINS.mistui.playerDecorationFat.glows = {
        status = fatGlow(decoration.glows.status),
        combat = fatGlow(decoration.glows.combat),
    }
end

-- One cell per colour, in the generator's order: HD/Target-NameStrip 268x31 every 32.
for row, key in ipairs({ "blue", "green", "orange", "red", "yellow" }) do
    UF.SKINS.mistui.target.nameBackground.cells[key] = { 0, 268 / 512, (row - 1) * 32 / 256, ((row - 1) * 32 + 31) / 256 }
end

-- The totem timers' ring.
UF.SKINS.mistui.totem = { file = ART .. "TotemRing", tc = { 2 / 128, 62 / 128, 2 / 64, 62 / 64 } }

-- One sheet: retail's 2x crown, guide, "Group N" tab and 1x roles; HD looter bags.
do
    local function cell(x, y, w, h)
        return { x / 256, (x + w) / 256, y / 128, (y + h) / 128 }
    end
    UF.STATUS_ICONS = {
        file = ART .. "Icons\\StatusIcons",
        leader = cell(0, 0, 32, 32),
        guide = cell(34, 0, 32, 32),
        master = cell(120, 50, 32, 32),
        roles = { TANK = cell(0, 50, 16, 16), HEALER = cell(18, 50, 16, 16), DAMAGER = cell(36, 50, 16, 16) },
        tabLeft = cell(56, 50, 10, 26),
        tabRight = cell(68, 50, 14, 32),
        -- Stretched sideways: half a texel in keeps the neighbours out of the filter.
        tabMid = { 84.5 / 256, 115.5 / 256, 50 / 128, 76 / 128 },
    }
end

-- Retail's spots +(16, -6.5), clear of Zzz, names, tab, PvP and every dragon; the same with a decoration.
UF.PLAYER_ICONS = {
    leader = { x = 108.5, y = -3.5, w = 16, h = 16 },
    master = { x = 126.5, y = -3.5, w = 16, h = 16 },
    -- Retail's (196, -27) 3 to the left, off the tab's right cap; the MistUI level text hides while it shows.
    role = { x = 209, y = -20.5, w = 12, h = 12 },
    -- BOTTOMRIGHT on PlayerFrame's TOPLEFT, growing left: text width + 40.
    tab = { x = 226, y = -22.5 },
}
-- Target/focus: the crown's TOPRIGHT on the frame's TOPLEFT (retail TOPRIGHT (-85, -8) + (-20.5, -6)).
UF.TARGET_ICONS = {
    leader = { x = 126.5, y = -2, w = 16, h = 16 },
    -- Off the portrait's top, round the ring: clear of the crown's art.
    raidOffCombo = { x = -17, y = -2.5 },
}

-- Party, TOPLEFT on the member frame: retail's spots, the crown 1 higher to clear our name at (46, -5).
UF.PARTY_ICONS = {
    leader = { x = 42, y = 11, w = 16, h = 16 },
    master = { x = 60, y = 11, w = 16, h = 16 },
    role = { x = 103, y = -5, w = 12, h = 12 },
}

-- kinds maps a classification (elite, rare, rareelite, boss) to the cell each set draws for it.
UF.DRAGON_SETS = {
    mistui = {
        file = ART .. "uiunitframeboss2x",
        cells = {
            elite = { 0.001953125, 0.314453125, 0.322265625, 0.630859375 },
            rare = { 0.00390625, 0.31640625, 0.64453125, 0.953125 },
            rareelite = { 0.001953125, 0.388671875, 0.001953125, 0.31835937 },
        },
        kinds = { elite = "elite", rare = "rare", rareelite = "rareelite", boss = "rareelite" },
    },
}

-- Player Dragon Decoration values.
UF.PLAYER_DECORATIONS = {
    elite = { kind = "elite", set = "mistui" },
    rareelite = { kind = "rareelite", set = "mistui" },
}

-- [frame][set][cell]: target sits on the portrait CENTER, player on PlayerFrame TOPLEFT. ToT/ToF get none, like retail.
UF.DRAGON_PLACEMENT = {
    target = {
        mistui = {
            elite = { w = 80, h = 79, x = 4.75, y = -0.25 },
            rare = { w = 80, h = 79, x = 4.75, y = -0.25 },
            rareelite = { w = 99, h = 81, x = 13.75, y = -0.25 },
        },
    },
    player = {
        -- rest: the Zzz's TOPLEFT on PlayerPortrait's, its first z 2.2-2.4 off the snout so the dragon breathes it.
        mistui = {
            elite = { w = 80, h = 79, x = 25.5, y = -4, flip = true, rest = { x = 60, y = 20 } },
            rareelite = { w = 99, h = 81, x = 6.5, y = -3, flip = true, rest = { x = 60, y = 20 } },
        },
    },
}

-- boss.lua reads this raw shape (cell, w, h, x, y) and stays on the MistUI set.
do
    local cells = UF.DRAGON_SETS.mistui.cells
    local function boss(cell, w, h, x, y)
        local c = cells[cell]
        return { c[1], c[2], c[3], c[4], w, h, x, y }
    end
    UF.BOSS_COORDS = {
        targetStyle = {
            elite = boss("elite", 80, 79, 4, 1),
            rare = boss("rare", 80, 79, 4, 1),
            rareelite = boss("rareelite", 99, 81, 13, 1),
        },
    }
end

-- Mist-UI ships one art style. The style getters stay so the layout code has one place to ask.
function UF.GetFrameSkin()
    return UF.SKINS.mistui
end

function UF.GetDragonSet()
    return "mistui"
end

-- Returns file, left, right, top, bottom and the placement table, or nil when the frame has no such dragon.
function UF.GetDragon(frameKind, kind, forcedSet)
    local setKey = UF.DRAGON_SETS[forcedSet] and forcedSet or UF.GetDragonSet()
    local set = UF.DRAGON_SETS[setKey]
    local cell = set.kinds[kind] or kind
    local placements = UF.DRAGON_PLACEMENT[frameKind]
    local place = placements and placements[setKey] and placements[setKey][cell]
    local c = set.cells[cell]
    if not place or not c then
        return nil
    end
    if place.flip then
        return set.file, c[2], c[1], c[3], c[4], place
    end
    return set.file, c[1], c[2], c[3], c[4], place
end

function UF.ApplySkinPiece(texture, piece, point, relativeTo, relativePoint, x, y)
    texture:SetTexture(piece.file)
    texture:SetTexCoord(unpack(piece.tc or FULL_TEXCOORD))
    texture:SetSize(piece.w, piece.h)
    texture:ClearAllPoints()
    texture:SetPoint(point, relativeTo, relativePoint, x + piece.x, y + piece.y)
end

local SKINNED_FRAME_REFRESHES = {
    "RefreshTargetFrame", "RefreshFocusFrame", "RefreshToTFrame", "RefreshToFFrame", "RefreshPetFrame",
    "RefreshPartyFrames",
}

function UF.RefreshSkins()
    if InCombatLockdown() then
        addon.CombatQueue:Add("uf_refresh_skins", UF.RefreshSkins)
        return
    end
    for _, name in ipairs(SKINNED_FRAME_REFRESHES) do
        local refresh = addon[name]
        if refresh then
            refresh(addon)
        end
    end
    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
        addon.PlayerFrame.RefreshPlayerFrame()
    end
    -- Portrait off moves the ToT/ToF, and with them how many aura rows stay short.
    if addon.RefreshTargetFocusAuraLayout then
        addon.RefreshTargetFocusAuraLayout()
    end
    -- The target's combo points swap arc and column with portrait off.
    if addon.RefreshComboPointsSystem then
        addon.RefreshComboPointsSystem()
    end
    if addon.RefreshTotemFrameSystem then
        addon.RefreshTotemFrameSystem()
    end
end
