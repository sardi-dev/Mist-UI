-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Bar sizes, offsets and art names adapted from DragonUI (MIT, (c) 2026 NeticSoul)
-- and DragonflightUI (MIT, (c) 2022 Karl-HeinzSchneider); see THIRD_PARTY_NOTICES.

-- Action bars: layout and art of the main bar and the four extra bars.
--
-- The stock frame tree stays as it is. The main buttons remain children of MainMenuBarArtFrame,
-- which is where the stock code writes the bar page and what it hides for a vehicle; the extra
-- buttons remain children of their stock bars. This module only re-anchors the buttons to boxes
-- of its own, scales them and draws the bar art, and it does so outside combat.

local addon = select(2, ...)
local L = addon.L

local KEY = "mainbars"
local BUTTON_SIZE = 36
local DEFAULT_SPACING = 7
local DEFAULT_SCALE = 0.9
local SLOTS = NUM_ACTIONBAR_BUTTONS
-- The main bar frame is this much larger than its button grid: 2 at each side and below, 4 above.
local MAIN_PAD_X, MAIN_PAD_Y, MAIN_EDGE = 4, 6, 2
-- The frame's centre sits this far above the centre of its box, which centres the buttons.
local MAIN_CENTER_Y = MAIN_PAD_Y / 2 - MAIN_EDGE
-- Where a button is parked when the bar shows fewer than twelve.
local PARKED_Y = -666

-- The styled slot ring reaches this far outside a button (buttons.lua), and the bar's border art
-- this far outside the rings.
local RING_OUTSET, RING_OUTSET_TOP = 2.2, 2.3
local BORDER_OUTSET = { left = 2.8, top = 2.8, right = 2.8, bottom = 3.75 }
-- The art's own bottom and right pieces shade outward, so those are redrawn as mirrors of the
-- top and left ones: piece, atlas, then the texture coordinates to flip.
local MIRRORED_BORDER_PIECES = {
    { "TopRightCorner", "ui-hud-actionbar-frame-nineslice-cornertopleft", 1, 0, 0, 1 },
    { "BottomLeftCorner", "ui-hud-actionbar-frame-nineslice-cornertopleft", 0, 1, 1, 0 },
    { "BottomRightCorner", "ui-hud-actionbar-frame-nineslice-cornertopleft", 1, 0, 1, 0 },
    { "RightEdge", "!ui-hud-actionbar-frame-nineslice-edgeleft", 1, 0, 0, 1 },
    { "BottomEdge", "_ui-hud-actionbar-frame-nineslice-edgetop", 0, 1, 1, 0 },
}

local DIVIDER_ATLAS = "ui-hud-actionbar-frame-divider-threeslice-"
local DIVIDER_COUNT = SLOTS - 1
local ART_LEVELS_ABOVE_BARS = 15
local TOP_SUBLEVEL = 7

-- End cap styles: atlas stem, then fixed offsets (left x, left y, right x, right y). The default
-- style has none and is placed against the slot rings instead.
local END_CAPS = {
    old = { stem = "gryphon", -85, -22, 84, -22 },
    new = { alliance = "gryphon-thick", other = "wyvern-thick" },
    flying = { stem = "gryphon-flying", -80, -21, 80, -21 },
}

local PAGE_ARROWS = {
    { button = "ActionBarUpButton", art = "pageuparrow", y = 8 },
    { button = "ActionBarDownButton", art = "pagedownarrow", y = -14 },
}

local STOCK_ART = {
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
}

-- key: edit mode name and saved position; config: layout settings under mainbars; fade: prefix of
-- the fading settings under actionbars; frame: the stock bar that owns and scales the buttons.
local BARS = {
    {
        key = "mainbar", label = "MainBar", config = "player", prefix = "ActionButton",
        scale = "scale_actionbar", fade = "main", order = "bottom_left",
        anchor = "BOTTOM", x = 0, y = 22, columns = 12, main = true,
    },
    {
        key = "bottombarleft", label = "BottomBarLeft", config = "bottom_left",
        prefix = "MultiBarBottomLeftButton", frame = "MultiBarBottomLeft",
        scale = "scale_bottomleft", fade = "bottom_left", order = "bottom_left",
        anchor = "BOTTOM", x = 0, y = 67, columns = 12,
    },
    {
        key = "bottombarright", label = "BottomBarRight", config = "bottom_right",
        prefix = "MultiBarBottomRightButton", frame = "MultiBarBottomRight",
        scale = "scale_bottomright", fade = "bottom_right", order = "bottom_left",
        anchor = "BOTTOM", x = 0, y = 106, columns = 12,
    },
    {
        key = "rightbar", label = "RightBar", config = "right",
        prefix = "MultiBarRightButton", frame = "MultiBarRight",
        scale = "scale_rightbar", fade = "right", order = "top_left",
        anchor = "RIGHT", x = -5, y = -70, columns = 1,
    },
    {
        -- The stock left bar is a child of the right bar and inherits its scale.
        key = "leftbar", label = "LeftBar", config = "left",
        prefix = "MultiBarLeftButton", frame = "MultiBarLeft", scaleParent = "scale_rightbar",
        scale = "scale_leftbar", fade = "left", order = "top_left",
        anchor = "RIGHT", x = -45, y = -70, columns = 1,
    },
}

local VALID_ORDERS = { top_left = true, bottom_left = true, top_right = true, bottom_right = true }
local FADE_FLAGS = { "show_on_hover", "show_in_combat", "hide_in_combat", "visibility_logic" }
local FADE_NUMBERS = { "shown_alpha", "hidden_alpha", "fade_in_duration", "fade_out_duration", "fade_out_delay" }

local Bars = { initialized = false, applied = false }
addon.MainbarsModule = Bars
addon.ActionBarFrames = addon.ActionBarFrames or {}

if addon.RegisterModule then
    addon:RegisterModule(KEY, Bars, L["Main Bars"], L["Main action bars, status bars, scaling and positioning"])
end

local mainBar, mainArt
local dividers = {}
local endCaps = {}

local function Settings()
    return addon.db.profile.mainbars
end

local function ArtHidden()
    local buttons = addon.db.profile.buttons
    return buttons and buttons.hide_main_bar_background and true or false
end

-- ============================================================================
-- Grid
-- ============================================================================

local function Layout(bar)
    local settings = Settings()
    local config = settings[bar.config] or {}
    local shown = math.max(1, math.min(SLOTS, tonumber(config.buttons_shown) or SLOTS))
    local columns = math.max(1, math.min(shown, tonumber(config.columns) or bar.columns))
    local order = bar.order
    if config.change_button_order and VALID_ORDERS[config.button_order] then
        order = config.button_order
    end
    return {
        shown = shown,
        columns = columns,
        rows = math.ceil(shown / columns),
        spacing = tonumber(config.button_spacing) or DEFAULT_SPACING,
        order = order,
        scale = tonumber(settings[bar.scale]) or DEFAULT_SCALE,
    }
end

local function GridSize(layout)
    local width = layout.columns * BUTTON_SIZE + (layout.columns - 1) * layout.spacing
    local height = layout.rows * BUTTON_SIZE + (layout.rows - 1) * layout.spacing
    return width, height
end

local function PlaceButton(button, anchor, order, x, y)
    button:ClearAllPoints()
    if order == "top_left" then
        button:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
    elseif order == "bottom_left" then
        button:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, y)
    elseif order == "top_right" then
        button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -x, -y)
    else
        button:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
    end
end

-- Buttons past the shown count are parked off screen as well as hidden, because the stock
-- update shows any button that holds an action again.
local function ArrangeButtons(bar, layout, anchor, padX, padY)
    local step = BUTTON_SIZE + layout.spacing
    for slot = 1, SLOTS do
        local button = _G[bar.prefix .. slot]
        if slot <= layout.shown then
            local index = slot - 1
            PlaceButton(button, anchor, layout.order, padX + (index % layout.columns) * step,
                padY + math.floor(index / layout.columns) * step)
        else
            button:ClearAllPoints()
            button:SetPoint("CENTER", UIParent, "BOTTOM", 0, PARKED_Y)
            button:Hide()
        end
    end
end

-- ============================================================================
-- Main bar art
-- ============================================================================

-- The slot rings' outer edges as offsets from the main bar frame's matching edges.
local function RingEdges()
    local growX = ActionButton1:GetWidth() - BUTTON_SIZE
    local growY = ActionButton1:GetHeight() - BUTTON_SIZE
    return MAIN_EDGE - RING_OUTSET,
        growY - (MAIN_PAD_Y - MAIN_EDGE) + RING_OUTSET_TOP,
        growX - MAIN_EDGE + RING_OUTSET,
        MAIN_EDGE - RING_OUTSET
end

local function SeatBorder()
    local border = mainBar.BorderArt
    for _, piece in ipairs(MIRRORED_BORDER_PIECES) do
        local texture = border[piece[1]]
        if texture then
            texture:SetAtlasTexture(piece[2], true)
            texture:SetSubTexCoord(piece[3], piece[4], piece[5], piece[6])
        end
    end
    local left, top, right, bottom = RingEdges()
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", mainBar, "TOPLEFT", left - BORDER_OUTSET.left, top + BORDER_OUTSET.top)
    border:SetPoint("BOTTOMRIGHT", mainBar, "BOTTOMRIGHT", right + BORDER_OUTSET.right, bottom - BORDER_OUTSET.bottom)
end

local function CreateDividers()
    for index = 1, DIVIDER_COUNT do
        local divider = {
            top = mainBar:CreateTexture(nil, "BORDER"),
            bottom = mainBar:CreateTexture(nil, "BORDER"),
            middle = mainBar:CreateTexture(nil, "BORDER"),
        }
        divider.top:SetAtlasTexture(DIVIDER_ATLAS .. "edgetop", true)
        divider.bottom:SetAtlasTexture(DIVIDER_ATLAS .. "edgebottom", true)
        divider.middle:SetAtlasTexture("!" .. DIVIDER_ATLAS .. "center", true)
        dividers[index] = divider
    end
end

local function ShowDivider(divider, button)
    divider.top:ClearAllPoints()
    divider.top:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", -3, 39)
    divider.bottom:ClearAllPoints()
    divider.bottom:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", -3, 9)
    -- The second centre anchor replaces the first, so the middle piece hangs off the bottom one.
    divider.middle:ClearAllPoints()
    divider.middle:SetPoint("CENTER", divider.top, "CENTER", 0, -15)
    divider.middle:SetPoint("CENTER", divider.bottom, "CENTER", 0, 15)
    divider.top:Show()
    divider.bottom:Show()
    divider.middle:Show()
end

-- One divider after every button that has a neighbour to its right in the same row.
local function PlaceDividers(layout)
    local used = 0
    if not ArtHidden() and layout.columns > 1 then
        local fromRight = layout.order == "top_right" or layout.order == "bottom_right"
        for row = 0, layout.rows - 1 do
            local inRow = math.min(layout.columns, layout.shown - row * layout.columns)
            for column = 0, inRow - 2 do
                local gridColumn = fromRight and (inRow - 1 - column) or column
                used = used + 1
                ShowDivider(dividers[used], _G["ActionButton" .. (row * layout.columns + gridColumn + 1)])
            end
        end
    end
    for index = used + 1, DIVIDER_COUNT do
        local divider = dividers[index]
        divider.top:Hide()
        divider.bottom:Hide()
        divider.middle:Hide()
    end
end

local function PlaceEndCaps()
    local style = addon.db.profile.style or {}
    local look = END_CAPS[style.gryphons]
    if not look or ArtHidden() then
        endCaps.left:Hide()
        endCaps.right:Hide()
        return
    end

    local stem = look.stem or (UnitFactionGroup("player") == "Alliance" and look.alliance or look.other)
    endCaps.left:SetAtlasTexture("ui-hud-actionbar-" .. stem .. "-left", true)
    endCaps.right:SetAtlasTexture("ui-hud-actionbar-" .. stem .. "-right", true)

    local leftX, leftY, rightX, rightY = look[1], look[2], look[3], look[4]
    if not leftX then
        -- 9 and 6 inside the bar's ends and 24 below its slot rings, as on the newer client.
        local ringLeft, _, ringRight, ringBottom = RingEdges()
        local width = endCaps.left:GetWidth()
        leftX, leftY = ringLeft + 9 - width, ringBottom - 24
        rightX, rightY = ringRight - 6 + width, ringBottom - 24
    end

    local scale = tonumber(style.gryphonScale) or 1
    local offsetX, offsetY = tonumber(style.gryphonOffsetX) or 0, tonumber(style.gryphonOffsetY) or 0
    endCaps.left:SetSinglePoint("BOTTOMLEFT", mainArt, "BOTTOMLEFT", leftX + offsetX, leftY + offsetY)
    endCaps.right:SetSinglePoint("BOTTOMRIGHT", mainArt, "BOTTOMRIGHT", rightX - offsetX, rightY + offsetY)
    for _, cap in pairs(endCaps) do
        cap:SetSize(cap:GetWidth() * scale, cap:GetHeight() * scale)
        cap:Show()
    end
end

local function PlacePageControls()
    local pages = addon.db.profile.buttons.pages or {}
    local label = MainMenuBarPageNumber
    if not pages.show then
        for _, arrow in ipairs(PAGE_ARROWS) do
            _G[arrow.button]:Hide()
        end
        label:Hide()
        return
    end
    for _, arrow in ipairs(PAGE_ARROWS) do
        addon.functions.SetupPageArrow(_G[arrow.button], mainArt, arrow.art, arrow.y)
        _G[arrow.button]:Show()
    end
    label:SetParent(mainArt)
    label:SetSinglePoint("CENTER", ActionBarDownButton, "CENTER", -1, 12)
    if pages.font then
        label:SetFont(unpack(pages.font))
    end
    label:SetDrawLayer("OVERLAY", TOP_SUBLEVEL)
    label:SetShadowOffset(1.2, -1.2)
    label:SetShadowColor(0, 0, 0, 1)
    label:Show()
end

local function PaintMainArt(layout)
    local hidden = ArtHidden()
    if hidden then
        mainBar.BorderArt:Hide()
        mainBar.Background:Hide()
    else
        mainBar.BorderArt:Show()
        mainBar.Background:Show()
        SeatBorder()
    end
    PlaceDividers(layout)
    PlaceEndCaps()
    PlacePageControls()
end

local function HideStockArt()
    for _, name in ipairs(STOCK_ART) do
        _G[name]:Hide()
    end
    -- The stock code shows this frame again at the level cap; kept invisible instead of hidden.
    MainMenuBarMaxLevelBar:SetAlpha(0)
    -- The stock bar is a full-width strip that takes clicks; only its buttons should.
    MainMenuBar:EnableMouse(false)
end

local function CreateMainBar()
    -- A child of the stock art frame, so it hides and slides away with the stock bar.
    mainBar = CreateFrame("Frame", "MistUI_MainActionBar", MainMenuBarArtFrame, "MistUIMainBarTemplate")
    mainBar:SetToplevel(false)
    addon.MainBar = mainBar

    -- The bar's frame is drawn under the slots: above them its inner shadow lands on the icons.
    local below = math.max(0, ActionButton1:GetFrameLevel() - 1)
    mainBar:SetFrameLevel(below)
    mainBar.BorderArt:SetFrameLevel(below)
    mainBar.Background:SetFrameLevel(math.max(0, below - 1))

    mainArt = CreateFrame("Frame", "MistUI_MainActionBarArt", mainBar)
    mainArt:SetAllPoints(mainBar)
    mainArt:SetFrameLevel(ActionButton1:GetFrameLevel() + ART_LEVELS_ABOVE_BARS)

    endCaps.left = mainArt:CreateTexture(nil, "OVERLAY", nil, TOP_SUBLEVEL)
    endCaps.right = mainArt:CreateTexture(nil, "OVERLAY", nil, TOP_SUBLEVEL)
    CreateDividers()
end

-- ============================================================================
-- Placing the bars
-- ============================================================================

-- The stock extra bars are drawn in a layer above every window, and each is a strip that
-- takes clicks at its stock position, where its buttons no longer are.
local function TameStockBar(frame)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(false)
    frame:EnableMouse(false)
end

local function PlaceBox(bar)
    local box = addon.ActionBarFrames[bar.key]
    box:ClearAllPoints()
    box:SetPoint(bar.anchor, UIParent, bar.anchor, bar.x, bar.y)
    addon.ApplyWidgetPositionFromDB(bar.key, box)
end

local function ApplyBar(bar)
    local layout = Layout(bar)
    local width, height = GridSize(layout)
    local box = addon.ActionBarFrames[bar.key]

    if bar.main then
        mainBar:SetScale(layout.scale)
        mainBar:SetSize(width + MAIN_PAD_X, height + MAIN_PAD_Y)
        mainBar:ClearAllPoints()
        mainBar:SetPoint("CENTER", box, "CENTER", 0, MAIN_CENTER_Y)
        for slot = 1, SLOTS do
            _G[bar.prefix .. slot]:SetScale(layout.scale)
        end
        box:SetSize((width + MAIN_PAD_X) * layout.scale, (height + MAIN_PAD_Y) * layout.scale)
        ArrangeButtons(bar, layout, mainBar, MAIN_EDGE, MAIN_EDGE)
        PaintMainArt(layout)
    else
        local parentScale = bar.scaleParent and (tonumber(Settings()[bar.scaleParent]) or DEFAULT_SCALE) or 1
        _G[bar.frame]:SetScale(layout.scale / parentScale)
        box:SetSize(width * layout.scale, height * layout.scale)
        ArrangeButtons(bar, layout, box, 0, 0)
    end
end

local function ApplyAll()
    for _, bar in ipairs(BARS) do
        ApplyBar(bar)
    end
end

-- Buttons and bars are protected frames: every layout change waits for the end of combat.
local function OutsideCombat(queueKey, action)
    if InCombatLockdown() then
        addon.CombatQueue:Add(queueKey, action)
        return false
    end
    return true
end

-- ============================================================================
-- Fading
-- ============================================================================

local function FadeConfig(prefix)
    return function()
        local bars = addon.db.profile.actionbars
        if not bars then
            return nil
        end
        local config = {}
        for _, flag in ipairs(FADE_FLAGS) do
            config[flag] = bars[prefix .. "_" .. flag]
        end
        for _, number in ipairs(FADE_NUMBERS) do
            config["visibility_" .. number] = bars["visibility_" .. number]
        end
        return config
    end
end

local function RegisterFades()
    local fade = addon.VisibilityFade
    for _, bar in ipairs(BARS) do
        local buttons = {}
        for slot = 1, SLOTS do
            buttons[slot] = _G[bar.prefix .. slot]
        end
        -- The main bar fades as a whole, art included. The extra bars fade button by button: the
        -- stock left bar is a child of the right bar and would fade with it.
        local frame, others = MainMenuBarArtFrame, nil
        if not bar.main then
            frame, others = buttons[1], { unpack(buttons, 2) }
        end
        -- Only alpha is driven: the mouse state of secure buttons cannot change in combat.
        fade.Register(bar.fade, frame, {
            frames = others,
            hoverFrames = buttons,
            enableMouse = false,
            dbTable = FadeConfig(bar.fade),
        })
        fade.Update(bar.fade)
    end
end

function addon.RefreshActionBarVisibility()
    if not Bars.applied then
        return
    end
    for _, bar in ipairs(BARS) do
        addon.VisibilityFade.Update(bar.fade)
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function Apply()
    if not OutsideCombat("mainbars_apply", Apply) then
        return
    end
    HideStockArt()
    CreateMainBar()
    for _, bar in ipairs(BARS) do
        local stockFrame = bar.main and mainBar or _G[bar.frame]
        if not bar.main then
            TameStockBar(stockFrame)
        end
        local box = addon.CreateUIFrame(BUTTON_SIZE, BUTTON_SIZE, bar.label)
        addon.ActionBarFrames[bar.key] = box
        PlaceBox(bar)
        addon:RegisterEditableFrame({
            name = bar.key,
            frame = box,
            stockFrame = stockFrame,
            configPath = { "widgets", bar.key },
            -- An extra bar that the game options switch off has nothing to move.
            editorVisible = function()
                return bar.main or _G[bar.frame]:IsShown()
            end,
            module = Bars,
        })
    end
    Bars.applied = true
    ApplyAll()
    RegisterFades()
    addon.StatusBars.Apply()
    addon.SmallBars.Apply()
end

function addon.ApplyActionBarPositions()
    if not Bars.applied or not OutsideCombat("mainbars_positions", addon.ApplyActionBarPositions) then
        return
    end
    for _, bar in ipairs(BARS) do
        PlaceBox(bar)
    end
    addon.UpdateStanceBarPosition()
end

function addon.RefreshMainbars()
    if not Bars.applied or not OutsideCombat("mainbars_refresh", addon.RefreshMainbars) then
        return
    end
    ApplyAll()
    addon.RefreshActionBarVisibility()
    addon.RefreshXpRepBars()
end

-- The edit mode dialogs call these two after a change to the art settings or the box sizes.
addon.RefreshMainBarArt = addon.RefreshMainbars
addon.UpdateOverlaySizes = addon.RefreshMainbars

-- Turning the module off takes effect on the next reload: the stock bar is then never touched.
function addon.RefreshMainbarsSystem()
    if not addon:IsModuleEnabled(KEY) then
        return
    end
    if not Bars.applied then
        if not IsLoggedIn() then
            return
        end
        Apply()
        return
    end
    addon.RefreshMainbars()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    Bars.initialized = true
    addon.RefreshMainbarsSystem()
end)
