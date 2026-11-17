-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local L = addon.L
local WM = addon.WorldMap
local QP = addon.QuestPOI

-- What sits on the canvas: landmark pins, quest POIs, the zone label and the filter button.

local PIN_SCALE = 1
local LABEL_FONT_SIZE, DESCRIPTION_FONT_SIZE = 24, 16
-- The ring's circle is off-centre in the stock border sheet, hence the icon nudge.
local FILTER_ICON = 26
local FILTER_ICON_X, FILTER_ICON_Y = 2, -2
-- The numbered glyph needs a larger scale to match the completed quest icon.
local QUEST_POI_SCALE, QUEST_POI_NUMERIC_SCALE = 0.7, 1.05
local ROCK = addon._dir .. "UI\\ui-background-rock"
local GLOW = "Interface\\WorldMap\\UI-QuestPoi-IconGlow"
local RING_SHEET = "Interface\\WorldMap\\UI-QuestPoi-NumberIcons"
-- QuestPOITemplate's turn-in glyph is 24px inside its 32px ring.
local TURNIN_SHARE = 24 / 32
local FLASH_SECONDS, FLASH_PULSES, FLASH_GROW = 2.5, 3, 0.35
local FLASH_PATIENCE = 5

local objectivesPlate
local pendingQuestFlash, pendingQuestFlashUntil

-- ============================================================================
-- LANDMARKS AND QUEST POIS
-- ============================================================================

-- The stock UI anchors pins in the map's own units and scales them with it; retail keeps pins one size.
-- The stock art and the stock choice of which pins show (graveyards, special pins) are kept.
local function restyleLandmarks()
    local scale = WM.canvasScale
    if not scale then return end
    local windowed = WM.IsWindowed()
    -- The filter is the new window's; the fullscreen map shows what the client shows.
    local shown = not windowed or WM:Config().landmarks ~= false
    local pinScale = windowed and PIN_SCALE / scale or 1
    local width, height = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
    for index = 1, GetNumMapLandmarks() do
        local pin = _G["WorldMapFramePOI" .. index]
        if pin then
            if not shown then
                pin:Hide()
            elseif pin:IsShown() then
                local _, _, _, x, y = GetMapLandmarkInfo(index)
                pin:SetScale(pinScale)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x * width / pinScale, -y * height / pinScale)
            end
        end
    end
end

-- Offsets are read in the button's own space, so the badge scale has to come back out of them.
local function placeQuestPOI(button)
    if not button.mistUIRawX then return end
    if not WM.IsWindowed() then
        -- The fullscreen map is the client's own: its scale, its offset and its templates' hit insets.
        button:SetScale(1)
        if button.type == QUEST_POI_COMPLETE_SWAP then
            button:SetHitRectInsets(12, 12, 8, 8)
        else
            button:SetHitRectInsets(8, 8, 8, 8)
        end
        button:SetPoint("CENTER", WorldMapPOIFrame, "TOPLEFT", button.mistUIRawX, button.mistUIRawY)
    elseif WM.poiScale then
        local scale = button.type == QUEST_POI_NUMERIC and QUEST_POI_NUMERIC_SCALE or QUEST_POI_SCALE
        button:SetScale(scale)
        -- The template insets 8 of 32 a side, leaving the ring we draw mostly unclickable.
        button:SetHitRectInsets(0, 0, 0, 0)
        local factor = WM.poiScale / scale
        button:SetPoint("CENTER", WorldMapPOIFrame, "TOPLEFT", button.mistUIRawX * factor, button.mistUIRawY * factor)
    end
end

-- The stock UI only re-anchors a POI it has a position for; the offset it just wrote is the raw one.
local function onQuestPOIDisplayed(questFrame)
    local button = questFrame.poiIcon
    if not button then return end
    local _, posX = QuestPOIGetIconInfo(questFrame.questId)
    if posX then
        local _, _, _, x, y = button:GetPoint(1)
        button.mistUIRawX, button.mistUIRawY = x, y
        placeQuestPOI(button)
    end
end

-- Resized, not rescaled: it hangs off an offset in its own scale, so scaling slides it away.
local function sizeQuestPOI(button, size)
    local rings = { button.normalTexture or button.ring, button.pushedTexture or button.ringPushed,
        button.highlightTexture or button.ringHighlight }
    for _, texture in ipairs(rings) do
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", button, "CENTER", 0, 0)
        texture:SetSize(size, size)
    end
    if button.number then
        button.number:ClearAllPoints()
        button.number:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.number:SetSize(size, size)
    end
    if button.mistUIRing then button.mistUIRing:SetSize(size / TURNIN_SHARE, size / TURNIN_SHARE) end
end

-- Stock rings a completed pin only via the twin its own pick swaps in; ours rings the shared focus.
local function ringCompletedPOI(button, selected)
    local ring = button.mistUIRing
    if not ring then
        if not selected then return end
        ring = button:CreateTexture(nil, "BORDER")
        ring:SetTexture(RING_SHEET)
        local box = QP.SELECTED_RING
        ring:SetTexCoord(box[1], box[2], box[3], box[4])
        ring:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.mistUIRing = ring
        sizeQuestPOI(button, button:GetWidth())
        local glow = button.selectionGlow:GetWidth() / TURNIN_SHARE
        button.selectionGlow:SetSize(glow, glow)
    end
    if selected then
        ring:Show()
        button.selectionGlow:Show()
    else
        ring:Hide()
        button.selectionGlow:Hide()
    end
end

-- These are the stock pooled buttons: one handed to another quest must drop the pulse it was
-- running, or the next quest to land on it inherits the animation. Hidden ones freeze mid-pulse.
local flashing = {}

local function poiQuest(button)
    return button.questId or (button.quest and button.quest.questId)
end

local function stopQuestFlash(button)
    flashing[button] = nil
    if not button.mistUIFlashTime then return end
    button:SetScript("OnUpdate", nil)
    sizeQuestPOI(button, button:GetWidth())
    button.mistUIFlashTime = nil
    button.mistUIFlashGlow:Hide()
end

local function dropStaleFlashes()
    for button, questID in pairs(flashing) do
        if not button:IsShown() or poiQuest(button) ~= questID then stopQuestFlash(button) end
    end
end

local function flashQuestPOI(button)
    flashing[button] = poiQuest(button)
    local glow = button.mistUIFlashGlow
    if not glow then
        glow = button:CreateTexture(nil, "OVERLAY")
        glow:SetTexture(GLOW)
        glow:SetBlendMode("ADD")
        glow:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.mistUIFlashGlow = glow
    end
    button.mistUIFlashTime = 0
    glow:Show()
    button:SetScript("OnUpdate", function(self, elapsed)
        local time = self.mistUIFlashTime + elapsed
        self.mistUIFlashTime = time
        if time >= FLASH_SECONDS then
            stopQuestFlash(self)
            return
        end
        local beat = math.sin(time / FLASH_SECONDS * FLASH_PULSES * math.pi * 2) * 0.5 + 0.5
        local fade = 1 - time / FLASH_SECONDS
        local grow = 1 + FLASH_GROW * beat * fade
        sizeQuestPOI(self, self:GetWidth() * grow)
        self.mistUIFlashGlow:SetSize(self:GetWidth() * 2 * grow, self:GetHeight() * 2 * grow)
        self.mistUIFlashGlow:SetAlpha(beat * fade)
    end)
end

local function cropQuestPOI(button, selected)
    if button.type == QUEST_POI_COMPLETE_SWAP then return ringCompletedPOI(button, selected) end
    QP.CropStockPOI(button, selected)
end

function WM.SelectQuestPOI(questID)
    -- The panel's pick lives in the new window; the fullscreen map keeps the client's selection art.
    if not WM.IsWindowed() then return end
    for index = 1, WorldMapFrame.numQuests or 0 do
        local row = _G["WorldMapQuestFrame" .. index]
        if row and row.poiIcon then cropQuestPOI(row.poiIcon, row.questId == questID) end
    end
end

local function tryFlashQuestPOI()
    dropStaleFlashes()
    if not pendingQuestFlash then return end
    if GetTime() > pendingQuestFlashUntil then
        pendingQuestFlash = nil
        return
    end
    for index = 1, WorldMapFrame.numQuests or 0 do
        local row = _G["WorldMapQuestFrame" .. index]
        if row and row.questId == pendingQuestFlash then
            local button = row.poiIcon
            if button and button:IsShown() then
                flashQuestPOI(button)
                pendingQuestFlash = nil
            end
            return
        end
    end
end

function WM.FlashQuestPOI(questID)
    if not questID then return end
    pendingQuestFlash, pendingQuestFlashUntil = questID, GetTime() + FLASH_PATIENCE
    tryFlashQuestPOI()
end

WM.RefreshLandmarks = restyleLandmarks

function WM.RefreshPins()
    restyleLandmarks()
    for index = 1, WorldMapFrame.numQuests or 0 do
        local row = _G["WorldMapQuestFrame" .. index]
        if row and row.poiIcon then placeQuestPOI(row.poiIcon) end
    end
end

local function styleAreaLabel()
    local font = addon.Fonts.PRIMARY
    WorldMapFrameAreaLabel:SetFont(font, LABEL_FONT_SIZE)
    WorldMapFrameAreaLabel:SetTextColor(1, 0.82, 0)
    WorldMapFrameAreaLabel:SetShadowColor(0, 0, 0, 1)
    WorldMapFrameAreaLabel:SetShadowOffset(1, -1)
    WorldMapFrameAreaDescription:SetFont(font, DESCRIPTION_FONT_SIZE)
    WorldMapFrameAreaDescription:SetTextColor(1, 1, 1)
    WorldMapFrameAreaDescription:SetShadowColor(0, 0, 0, 1)
    WorldMapFrameAreaDescription:SetShadowOffset(1, -1)
end

-- ============================================================================
-- FILTER BUTTON
-- ============================================================================

-- The stock "Show" menu keeps the CVar and this flag together.
function WM.ObjectivesShown()
    return (WatchFrame.showObjectives and GetCVarBool("questPOI")) and true or false
end

local function filterEntries()
    local entries = { { text = FILTERS, isTitle = true } }
    local function toggle(text, key, onChanged)
        entries[#entries + 1] = {
            text = text,
            checked = function() return WM:Config()[key] ~= false end,
            keepShown = true,
            func = function()
                WM:Config()[key] = not (WM:Config()[key] ~= false)
                onChanged()
            end,
        }
    end
    -- Only the client's own map pass decides which landmarks show, so turning them back on asks for one.
    toggle(L["Show Landmarks"], "landmarks", function()
        if WM:Config().landmarks ~= false then WM.RequestMapRefresh() else restyleLandmarks() end
    end)
    toggle(L["Show Map Coordinates"], "coordinates", WM.RefreshCoords)
    return entries
end

local function buildFilterButton()
    local button = CreateFrame("Button", "MistUIWorldMapFilterButton", WM.border)
    button:SetSize(32, 32)
    button:SetFrameLevel(WM.border:GetFrameLevel() + 5)
    button:SetPoint("TOPRIGHT", WM.spacer, "BOTTOMRIGHT", -4, -4)

    -- The stock tracking button: a 54px ring hung off the top-left corner of a 32px button.
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAtlasTexture("map-tracking-border", true)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    local function face(setter, getter, atlas)
        button[setter](button, ROCK)
        local tex = button[getter](button)
        tex:SetAtlasTexture(atlas)
        tex:ClearAllPoints()
        tex:SetSize(FILTER_ICON, FILTER_ICON)
        tex:SetPoint("CENTER", button, "CENTER", FILTER_ICON_X, FILTER_ICON_Y)
        return tex
    end
    face("SetNormalTexture", "GetNormalTexture", "map-filter-button")
    face("SetPushedTexture", "GetPushedTexture", "map-filter-button-down")
    -- MiniMapTracking's highlight fills the button unoffset; only the icon needs the nudge.
    button:SetHighlightTexture(ROCK)
    local highlight = button:GetHighlightTexture()
    highlight:SetAtlasTexture("map-zoom-highlight")
    highlight:SetBlendMode("ADD")
    highlight:ClearAllPoints()
    highlight:SetAllPoints(button)

    button:SetScript("OnClick", function(self)
        addon.Menu.Open(self, filterEntries())
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(FILTERS)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- ============================================================================
-- CANVAS SHADOW
-- ============================================================================

-- Where the stock "show quest objectives" box sat before it moved into the filter menu.
local function buildCanvasShadow()
    objectivesPlate = WM.border:CreateTexture(nil, "ARTWORK")
    objectivesPlate:SetAtlasTexture("mapcornershadow-left", true)
    objectivesPlate:SetPoint("BOTTOMLEFT", WM.spacer, "BOTTOMLEFT", 0, -(WM.canvasH or 465))
end

-- ============================================================================
-- BUILD
-- ============================================================================

function WM.BuildPins()
    styleAreaLabel()
    buildFilterButton()
    buildCanvasShadow()

    hooksecurefunc("WorldMapFrame_Update", restyleLandmarks)
    hooksecurefunc("WorldMapFrame_Update", tryFlashQuestPOI)
    -- Stock reselects a pin of its own on every rebuild, so ours is re-cropped after it.
    hooksecurefunc("WorldMapFrame_SelectQuestFrame", function()
        if not WM.IsWindowed() then return end
        -- The stock pick is not ours: undo the twin it swaps in, as its numbered crop is undone below.
        local swap = QUEST_POI_SWAP_BUTTONS and QUEST_POI_SWAP_BUTTONS.WorldMapPOIFrame
        if swap and swap:IsShown() then
            swap:Hide()
            local source = swap.quest and swap.quest.poiIcon
            if source then source:Show() end
        end
        WM.SelectQuestPOI(QP.GetFocus())
    end)
    QP.RegisterFocusListener(WM.SelectQuestPOI)
    hooksecurefunc("WorldMapFrame_UpdateQuests", dropStaleFlashes)
    hooksecurefunc("WorldMapFrame_DisplayQuestPOI", onQuestPOIDisplayed)

    hooksecurefunc("WorldMapFrame_DisplayQuests", tryFlashQuestPOI)

    local onLayout = WM.OnLayout
    WM.OnLayout = function()
        if onLayout then onLayout() end
        objectivesPlate:SetPoint("BOTTOMLEFT", WM.spacer, "BOTTOMLEFT", 0, -(WM.canvasH or 465))
    end

    local onMode = WM.OnModeChanged
    WM.OnModeChanged = function(windowed)
        if onMode then onMode(windowed) end
        if objectivesPlate then
            if windowed then objectivesPlate:Show() else objectivesPlate:Hide() end
        end
    end
end
