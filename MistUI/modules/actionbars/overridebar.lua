-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Frame art names and offsets as in mainbars.lua; the exit button crop from DragonUI's vehicle
-- module (MIT, (c) 2026 NeticSoul).

-- The vehicle and override bar in the main bar's look.
--
-- The stock OverrideActionBar keeps its buttons, its page, its layout and its slide animation
-- (see docs/decisions/0007-keep-the-stock-action-bar-tree.md). Only its art changes: the vehicle
-- skin is made invisible, the main bar's frame and dividers are drawn around its six buttons and
-- the leave button takes the round vehicle exit art. The stock code re-skins the bar and
-- re-anchors its buttons when a vehicle is entered, often in combat; everything this file does
-- after that is texture work, which combat allows.

local addon = select(2, ...)

local BUTTONS = NUM_OVERRIDE_BUTTONS or 6
local DEFAULT_SCALE = 0.8
-- How far the slot rings (buttons.lua) and then the bar's border reach outside a button.
local RING_OUTSET, RING_OUTSET_TOP = 2.2, 2.3
local BORDER_OUTSET = { left = 2.8, top = 2.8, right = 2.8, bottom = 3.75 }
local MIRRORED_BORDER_PIECES = {
    { "TopRightCorner", "ui-hud-actionbar-frame-nineslice-cornertopleft", 1, 0, 0, 1 },
    { "BottomLeftCorner", "ui-hud-actionbar-frame-nineslice-cornertopleft", 0, 1, 1, 0 },
    { "BottomRightCorner", "ui-hud-actionbar-frame-nineslice-cornertopleft", 1, 0, 1, 0 },
    { "RightEdge", "!ui-hud-actionbar-frame-nineslice-edgeleft", 1, 0, 0, 1 },
    { "BottomEdge", "_ui-hud-actionbar-frame-nineslice-edgetop", 0, 1, 1, 0 },
}
local DIVIDER_ATLAS = "ui-hud-actionbar-frame-divider-threeslice-"

-- The skin pieces the stock code paints on every vehicle. The pitch slider, its marker and its
-- two buttons stay: they are the controls, and the skin is all the art they have.
local SKIN_HIDDEN = {
    "_BG", "EndCapL", "EndCapR", "_Border", "Divider1", "Divider2", "Divider3", "ExitBG",
    "MicroBGL", "MicroBGR", "_MicroBGMid", "ButtonBGL", "ButtonBGR", "_ButtonBGMid",
    "PitchButtonBG", "HealthBarBG", "HealthBarOverlay", "PowerBarBG", "PowerBarOverlay",
}

local EXIT_UP = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up"
local EXIT_DOWN = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Down"
local EXIT_GLOW = "Interface\\Vehicles\\UI-Vehicles-Button-Highlight"
local EXIT_CROP = { 0.140625, 0.859375, 0.140625, 0.859375 }
local GLOW_CROP = { 0.130625, 0.879375, 0.130625, 0.879375 }
local EXIT_SIZE = 40
local EXIT_GAP = 12

local built = false

local function Enabled()
    return addon:IsModuleEnabled("mainbars")
end

local function Button(index)
    return _G["OverrideActionBarButton" .. index]
end

-- By name: the bar's own LeaveButton key is only copied over by its leave frame's OnLoad.
local function LeaveButton()
    return OverrideActionBarLeaveFrameLeaveButton
end

local function Scale()
    local settings = addon.db and addon.db.profile and addon.db.profile.mainbars
    return tonumber(settings and settings.scale_overridebar) or DEFAULT_SCALE
end

-- ============================================================================
-- Art
-- ============================================================================

local function SeatBorder(art)
    local border = art.BorderArt
    for _, piece in ipairs(MIRRORED_BORDER_PIECES) do
        local texture = border[piece[1]]
        if texture then
            texture:SetAtlasTexture(piece[2], true)
            texture:SetSubTexCoord(piece[3], piece[4], piece[5], piece[6])
        end
    end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", Button(1), "TOPLEFT",
        -(RING_OUTSET + BORDER_OUTSET.left), RING_OUTSET_TOP + BORDER_OUTSET.top)
    border:SetPoint("BOTTOMRIGHT", Button(BUTTONS), "BOTTOMRIGHT",
        RING_OUTSET + BORDER_OUTSET.right, -(RING_OUTSET + BORDER_OUTSET.bottom))
end

-- One divider in each gap, hung off the button to its left like the main bar's.
local function AddDividers(art)
    local height = Button(1):GetHeight()
    for index = 1, BUTTONS - 1 do
        local button = Button(index)
        local top = art:CreateTexture(nil, "BORDER")
        local bottom = art:CreateTexture(nil, "BORDER")
        local middle = art:CreateTexture(nil, "BORDER")
        top:SetAtlasTexture(DIVIDER_ATLAS .. "edgetop", true)
        bottom:SetAtlasTexture(DIVIDER_ATLAS .. "edgebottom", true)
        middle:SetAtlasTexture("!" .. DIVIDER_ATLAS .. "center", true)
        top:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", -3, height + 3)
        bottom:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", -3, 9)
        middle:SetPoint("TOP", top, "BOTTOM", 0, 0)
        middle:SetPoint("BOTTOM", bottom, "TOP", 0, 0)
    end
end

local function BuildArt()
    local bar = OverrideActionBar
    local art = CreateFrame("Frame", "MistUI_OverrideBarArt", bar, "MistUIOverrideBarArtTemplate")
    art:SetPoint("TOPLEFT", Button(1), "TOPLEFT", -2, 4)
    art:SetPoint("BOTTOMRIGHT", Button(BUTTONS), "BOTTOMRIGHT", 2, -2)
    -- Under the buttons, as on the main bar: above them its inner shadow lands on the icons.
    local below = math.max(0, Button(1):GetFrameLevel() - 1)
    art:SetFrameLevel(below)
    art.BorderArt:SetFrameLevel(below)
    art.Background:SetFrameLevel(math.max(0, below - 1))
    SeatBorder(art)
    AddDividers(art)
    return art
end

-- ============================================================================
-- The stock bar
-- ============================================================================

local function DressExitFace(texture, file, box, blend)
    if not texture then return end
    texture:SetTexture(file)
    texture:SetTexCoord(box[1], box[2], box[3], box[4])
    if blend then texture:SetBlendMode(blend) end
end

-- Runs after every OverrideActionBar_SetSkin: the skin call repaints the leave button's faces.
local function Repaint()
    local bar = OverrideActionBar
    for _, key in ipairs(SKIN_HIDDEN) do
        local region = bar[key]
        if region then region:SetAlpha(0) end
    end
    local leave = LeaveButton()
    DressExitFace(leave:GetNormalTexture(), EXIT_UP, EXIT_CROP)
    DressExitFace(leave:GetPushedTexture(), EXIT_DOWN, EXIT_CROP)
    DressExitFace(leave:GetHighlightTexture(), EXIT_GLOW, GLOW_CROP, "ADD")
end

local function PlaceStockParts()
    local bar = OverrideActionBar
    -- With the micro menu module on, the micro buttons stay in their own bar, so the leave button
    -- comes in from the space the stock bar keeps for them and sits next to the last slot. With
    -- it off, the stock code moves the micro buttons onto this bar and the leave button keeps its
    -- stock place past them.
    local leave = LeaveButton()
    leave:SetSize(EXIT_SIZE, EXIT_SIZE)
    if addon:IsModuleEnabled("micromenu") then
        leave:ClearAllPoints()
        leave:SetPoint("LEFT", Button(BUTTONS), "RIGHT", EXIT_GAP, 0)
    end
    -- The vehicle's health and power show on the player frame; the stock XP bar on this bar is
    -- vehicle skin art from end to end.
    for _, part in ipairs({ bar.healthBar, bar.powerBar, bar.xpBar }) do
        if part then
            part:SetAlpha(0)
            -- Invisible, so not hoverable either: each would show its tooltip.
            part:EnableMouse(false)
        end
    end
end

local function StyleButtons()
    if addon.StyleVehicleButtons then addon.StyleVehicleButtons(true) end
end

local function Build()
    if built or not Enabled() or not OverrideActionBar then return end
    if InCombatLockdown() then
        addon.CombatQueue:Add("overridebar_build", Build)
        return
    end
    -- Marked and hooked first: a failure further down must neither build the art twice nor leave
    -- the skin unhidden on the next vehicle.
    built = true
    hooksecurefunc("OverrideActionBar_SetSkin", Repaint)
    OverrideActionBar:SetScale(Scale())
    BuildArt()
    PlaceStockParts()
    Repaint()
    -- Once, while the bar is hidden: the restyle survives every later vehicle.
    StyleButtons()
end

-- The edit mode dialogs and the settings call this after a change to the bar scale.
function addon.RefreshOverrideBar()
    if not built then return Build() end
    if InCombatLockdown() then
        addon.CombatQueue:Add("overridebar_scale", addon.RefreshOverrideBar)
        return
    end
    OverrideActionBar:SetScale(Scale())
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    addon:SafeExecute("overridebar", "build", Build)
end)
