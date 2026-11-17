-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.
-- Copyright (c) 2026 sardi-dev. Adapted to the 5.4.8 client: its arrow is already a flat texture.

local addon = select(2, ...)
local WM = addon.WorldMap

-- The client draws the player as two flat arrows (WorldMapPlayerLower and Upper) hung off
-- WorldMapButton, which carries the canvas scale; retail keeps the arrow and the markers one size.

local ARROW_SIZE = 28
local CORPSE_SIZE = 14
local ARROWS = { "WorldMapPlayerLower", "WorldMapPlayerUpper" }

-- What the client gave each marker, so the fullscreen map gets it back.
local stock = {}

local function remember(frame)
    if not stock[frame] then
        local w, h = frame:GetSize()
        stock[frame] = { w = w, h = h, level = frame:GetFrameLevel(), scale = frame:GetScale() }
    end
end

local function placeMarker(marker, scale)
    remember(marker)
    -- Zoom hands these to the scroll child, which lacks the scale the stock anchor offsets assume.
    marker:SetScale(WorldMapButton:GetEffectiveScale() / marker:GetParent():GetEffectiveScale())
    marker:SetSize(CORPSE_SIZE / scale, CORPSE_SIZE / scale)
    -- Over the pins and the arrow, as retail: its stock level ties our pins and they bury it.
    marker:SetFrameLevel(WORLDMAP_POI_FRAMELEVEL + 102)
end

-- Windowed only: the client's own size toggles size the arrows for its fullscreen map.
function WM.RefreshPlayerArrow()
    if not WM.IsWindowed() then return end
    local scale = WM.canvasScale or 1
    for _, name in ipairs(ARROWS) do
        local arrow = _G[name]
        if arrow then arrow:SetSize(ARROW_SIZE / scale, ARROW_SIZE / scale) end
    end
    placeMarker(WorldMapCorpse, scale)
    placeMarker(WorldMapDeathRelease, scale)
    -- A carried flag sits on its carrier, you included; under the arrow it would vanish.
    for i = 1, NUM_WORLDMAP_FLAGS do
        local flag = _G["WorldMapFlag" .. i]
        remember(flag)
        flag:SetFrameLevel(WORLDMAP_POI_FRAMELEVEL + 101)
    end
end

-- The fullscreen map is the client's: markers and flags go back to what it gave them.
function WM.RestorePlayerMarkers()
    for frame, info in pairs(stock) do
        frame:SetScale(info.scale)
        frame:SetSize(info.w, info.h)
        frame:SetFrameLevel(info.level)
    end
end

function WM.BuildPlayerArrow()
    WM.RefreshPlayerArrow()
end
