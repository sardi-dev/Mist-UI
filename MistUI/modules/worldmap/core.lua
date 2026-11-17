-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.
-- Rewritten from a base module contributed by PentSec, with thanks.

local addon = select(2, ...)
local L = addon.L

-- Retail's Map & Quest Log over the windowed map; nothing here writes what the stock map reads.

local WorldMapModule = { initialized = false, applied = false }
addon.WorldMap = addon.WorldMap or {}
local WM = addon.WorldMap

if addon.RegisterModule then
    addon:RegisterModule("worldmap", WorldMapModule,
        L["World Map"],
        L["Retail-style world map with breadcrumb navigation and a quest log side panel"],
        { lifecyclePrefix = "WorldMap", loadOnce = true })
end

-- Retail's WorldMapFrame: 702x534 minimized, a 67px title band over a 697x465 canvas.
WM.SPACER_H = 67
WM.INSET_L, WM.INSET_R, WM.INSET_B = 2, 3, 2
WM.PANEL_W = 330
-- The UIPanel slot is (0,-104) and the corner art overhangs 13px; retail sits at (16,-116).
WM.FRAME_X, WM.FRAME_Y = 16, 12
WM.DETAIL_W, WM.DETAIL_H = 1002, 668
local WINDOWED_CANVAS_W = 697
-- Kept clear of the action bars and the screen's right edge when maximized.
local MAX_BOTTOM_MARGIN, MAX_RIGHT_MARGIN = 96, 24
local MAP_REPLACERS = { "Mapster" }
local PORTRAIT = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"
local ROCK = addon._dir .. "UI\\ui-background-rock"
local BASE_LEVEL = 10


local function loadedReplacer()
    for _, candidate in ipairs(MAP_REPLACERS) do
        if IsAddOnLoaded(candidate) then return candidate end
    end
end

-- Before login no replacer has loaded yet, so this asks whether one is going to.
local function replacerPending()
    for _, candidate in ipairs(MAP_REPLACERS) do
        local _, _, _, enabled, loadable = GetAddOnInfo(candidate)
        if enabled and loadable then return true end
    end
end

function WM:Config()
    return addon:GetModuleConfig("worldmap") or {}
end

function WM:Enabled()
    return addon:IsModuleEnabled("worldmap")
end

-- Booted, so the quest pick shown on the map is ours; its hooks stay until the reload.
function WM.IsApplied()
    return WorldMapModule.applied == true
end

-- The client's one "am I windowed" test, read and never written.
function WM.IsWindowed()
    return WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE
end

-- Geometric, so the chrome answers for the canvas under it even though it takes no mouse itself.
function WM.CursorOverMap()
    if WM.border and WM.border:IsShown() then return WM.border:IsMouseOver() end
    return WorldMapFrame:IsMouseOver()
end

-- Overlays belong to the terrain view; Dalaran has none, its city and Underbelly are both floors.
function WM.OnTerrainFloor()
    local level = GetCurrentMapDungeonLevel()
    if DungeonUsesTerrainMap() then level = level - 1 end
    return level <= 0
end

-- WorldMap_OpenToQuest writes WorldMapFrame.blockWorldMapUpdate, re-read by its every WORLD_MAP_UPDATE.
function WM.OpenToQuest(questID)
    local shown = WorldMapFrame:IsShown()
    -- Only showing the map is protected; an open one moves freely in combat.
    if not questID or (InCombatLockdown() and not shown) then return false end
    -- Not a getter: it moves the map whatever it answers, so a quest it cannot place must not strand you.
    local before, beforeFloor = GetCurrentMapAreaID() or 0, GetCurrentMapDungeonLevel()
    local area, floor = GetQuestWorldMapAreaID(questID)
    if area and area > 0 then
        SetMapByID(area)
        if floor and floor > 0 then SetDungeonMapLevel(floor) end
    elseif before > 0 then
        SetMapByID(before)
        if beforeFloor and beforeFloor > 0 then SetDungeonMapLevel(beforeFloor) end
    end
    if not shown then ShowUIPanel(WorldMapFrame) end
    return true
end

-- Moves the map to where it already is: the client answers with WORLD_MAP_UPDATE, and its own
-- handler redraws every pin, so no stock code runs from here.
function WM.RequestMapRefresh()
    local area, floor = GetCurrentMapAreaID(), GetCurrentMapDungeonLevel()
    if not area or area <= 0 then return end
    SetMapByID(area)
    if floor and floor > 0 then SetDungeonMapLevel(floor) end
end

-- ============================================================================
-- GEOMETRY
-- ============================================================================

local function canvasSize()
    if WM:Config().maximized then
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        local panel = WM.PanelShown() and WM.PANEL_W or 0
        local top = -(UIParent:GetAttribute("TOP_OFFSET") or -104)
        local h = sh - top - WM.FRAME_Y - WM.SPACER_H - WM.INSET_B - MAX_BOTTOM_MARGIN
        local w = sw - WM.FRAME_X - WM.INSET_L - WM.INSET_R - panel - MAX_RIGHT_MARGIN
        local scale = math.max(math.min(h / WM.DETAIL_H, w / WM.DETAIL_W), WINDOWED_CANVAS_W / WM.DETAIL_W)
        return math.floor(WM.DETAIL_W * scale), math.floor(WM.DETAIL_H * scale)
    end
    return WINDOWED_CANVAS_W, math.floor(WINDOWED_CANVAS_W * WM.DETAIL_H / WM.DETAIL_W + 0.5)
end

-- Both passes write implicitly protected frames, so both are combat-deferred.
local canvasW, canvasH

-- The client places these by the detail frame's own units and, like the blob, scales them itself.
local CANVAS_LAYERS = { "WorldMapBlobFrame", "ScenarioPOIFrame" }

-- WorldMapFrame_Update places the boss buttons for the scale it found; a resize after it moves them.
local function placeBossButtons()
    local frame = WorldMapBossButtonFrame
    if not (frame and frame.ready and EJ_GetMapEncounter) then return end
    local width = WorldMapDetailFrame:GetWidth() * WorldMapDetailFrame:GetScale()
    local height = WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
    local index = 1
    local button = _G["EJMapButton" .. index]
    while button and button:IsShown() do
        local x, y = EJ_GetMapEncounter(index, WorldMapFrame.fromJournal)
        if not x then break end
        button:SetPoint("CENTER", frame, "BOTTOMLEFT", x * width, y * height)
        index = index + 1
        button = _G["EJMapButton" .. index]
    end
end

local function layoutCanvas()
    local f = WorldMapFrame
    local detail = WorldMapDetailFrame
    canvasW, canvasH = canvasSize()
    WM.canvasW, WM.canvasH = canvasW, canvasH
    local scale = canvasW / WM.DETAIL_W * (WM.zoom or 1)
    WM.canvasScale = scale
    -- WorldMapButton_OnUpdate multiplies POI and arrow offsets by this size; ours differs by it.
    WM.poiScale = scale / WORLDMAP_SETTINGS.size

    detail:SetScale(scale)
    detail:ClearAllPoints()
    if not (WM.LayoutZoom and WM.LayoutZoom()) then
        detail:SetPoint("TOPLEFT", f, "TOPLEFT", (WM.FRAME_X + WM.INSET_L) / scale, -(WM.FRAME_Y + WM.SPACER_H) / scale)
    end
    WorldMapButton:SetScale(scale)
    for _, name in ipairs(CANVAS_LAYERS) do
        local layer = _G[name]
        if layer then layer:SetScale(scale) end
    end
    -- Stock recomputes the blob hit box when this is nil, which keeps the value secure.
    WorldMapBlobFrame.xRatio = nil
    -- The window's scale whatever it hangs off: zoom.lua moves it out from under the button.
    local area = WorldMapFrameAreaFrame
    area:SetScale(f:GetEffectiveScale() / area:GetParent():GetEffectiveScale())

    placeBossButtons()
    if WM.RefreshPlayerArrow then WM.RefreshPlayerArrow() end
    if WM.RefreshPins then WM.RefreshPins() end
    if WM.RefreshBlobs then WM.RefreshBlobs() end
end

local function windowSize()
    local panel = WM.PanelShown() and WM.PANEL_W or 0
    return WM.INSET_L + canvasW + WM.INSET_R + panel, WM.SPACER_H + canvasH + WM.INSET_B
end

-- The chrome is ours and follows the panel at once; the frame under it is protected in combat.
local function layoutChrome()
    local w, h = windowSize()
    WM.border:SetSize(w, h)
    local panel = WM.PanelShown() and WM.PANEL_W or 0
    WM.spacer:SetPoint("BOTTOMRIGHT", WM.border, "TOPRIGHT", -(WM.INSET_R + panel), -WM.SPACER_H)
    WM.sideToggle:SetPoint("BOTTOMRIGHT", WM.border, "BOTTOMRIGHT", -(WM.INSET_R + panel + 5), WM.INSET_B + 5)
    if WM.OnLayout then WM.OnLayout() end
end

local function layoutWindow()
    local w, h = windowSize()
    WorldMapFrame:SetSize(WM.FRAME_X + w, WM.FRAME_Y + h)
    layoutChrome()
end

function WM.Layout(canvasChanged)
    if not (WM.border and WM.IsWindowed()) then return end
    if InCombatLockdown() then
        addon.CombatQueue:Add("worldmap_layout", WM.Layout, canvasChanged or WM.canvasDirty)
        WM.canvasDirty = WM.canvasDirty or canvasChanged
        if canvasW and not WM.canvasDirty then layoutChrome() end
        return
    end
    WM.canvasDirty = nil
    if canvasChanged or not canvasW then layoutCanvas() end
    layoutWindow()
end

-- ============================================================================
-- CHROME
-- ============================================================================

-- Hidden parent rather than a swapped Show: that method taints every secure caller reaching it.
local holder = CreateFrame("Frame", "MistUIWorldMapHolder", UIParent)
holder:Hide()

local RETIRED = {
    "WorldMapZoneMinimapDropDown", "WorldMapContinentDropDown", "WorldMapZoneDropDown",
    "WorldMapZoomOutButton", "WorldMapMagnifyingGlassButton", "WorldMapLevelDropDown",
    "WorldMapLevelUpButton", "WorldMapLevelDownButton", "WorldMapFrameSizeUpButton",
    "WorldMapFrameSizeDownButton", "WorldMapTrackQuest", "WorldMapTitleButton",
}

-- The client's "Show" menu (quest objectives, bosses, dig sites, pet tamers) stays the client's own,
-- clicked by the player, so its handlers run clean; only its place changes.
local showMenuStock
local function placeShowMenu(windowed)
    local menu = WorldMapShowDropDown
    if not menu then return end
    showMenuStock = showMenuStock or { strata = menu:GetFrameStrata(), level = menu:GetFrameLevel() }
    menu:ClearAllPoints()
    if windowed then
        menu:SetPoint("BOTTOMRIGHT", WM.sideToggle, "BOTTOMLEFT", 12, -4)
        menu:SetFrameStrata("HIGH")
        menu:SetFrameLevel(BASE_LEVEL + 5)
    else
        menu:SetPoint("BOTTOMRIGHT", WorldMapPositioningGuide, "BOTTOMRIGHT", 10, -2)
        menu:SetFrameStrata(showMenuStock.strata)
        menu:SetFrameLevel(showMenuStock.level)
    end
end

local function retireStockWidgets()
    for _, name in ipairs(RETIRED) do
        _G[name]:SetParent(holder)
    end
    WorldMapFrameTitle:Hide()
    WorldMapFrameMiniBorderLeft:Hide()
    WorldMapFrameMiniBorderRight:Hide()
end

-- The client's fullscreen map still needs its own controls.
local function restoreStockWidgets()
    for _, name in ipairs(RETIRED) do
        _G[name]:SetParent(WorldMapFrame)
    end
    WorldMapFrameTitle:Show()
end

-- The windowed map is a "center" panel the manager never re-anchors, so a drag keeps its spot.
local function savePosition()
    local f = WorldMapFrame
    WM:Config().position = { x = f:GetLeft(), y = f:GetTop() - UIParent:GetHeight() }
end

function WM.Place()
    -- The size toggle is a key binding and can reach here mid-combat.
    if InCombatLockdown() then
        addon.CombatQueue:Add("worldmap_place", WM.Place)
        return
    end
    local f = WorldMapFrame
    f:SetMovable(true)
    local position = WM:Config().position
    f:ClearAllPoints()
    if position then
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", position.x, position.y)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, UIParent:GetAttribute("TOP_OFFSET") or -104)
    end
end

local function buildChrome()
    local f = WorldMapFrame

    -- The stone sits at the map's own level so the detail frame draws over it.
    local ground = CreateFrame("Frame", "MistUIWorldMapGround", f)
    ground:SetFrameLevel(f:GetFrameLevel())
    ground:EnableMouse(false)
    WM.ground = ground

    local border = CreateFrame("Frame", "MistUIWorldMapBorder", f)
    border:SetFrameStrata("HIGH")
    border:SetFrameLevel(BASE_LEVEL)
    border:SetPoint("TOPLEFT", f, "TOPLEFT", WM.FRAME_X, -WM.FRAME_Y)
    border:EnableMouse(false)
    WM.border = border

    ground:SetPoint("TOPLEFT", border, "TOPLEFT", 2, -21)
    ground:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)
    local rock = ground:CreateTexture(nil, "BACKGROUND")
    rock:SetTexture(ROCK, "REPEAT", "REPEAT")
    rock:SetHorizTile(true)
    rock:SetVertTile(true)
    rock:SetAllPoints(ground)

    MistUI_NineSlice.ApplyLayout(border, MistUI_NineSlice.GetLayout("PortraitFrameTemplateMinimizable"))

    -- Retail's TitleCanvasSpacerFrame: the band the breadcrumb lives in, stopping at the canvas.
    local spacer = CreateFrame("Frame", "MistUIWorldMapSpacer", border)
    spacer:SetPoint("TOPLEFT", border, "TOPLEFT", WM.INSET_L, 0)
    spacer:SetFrameLevel(BASE_LEVEL + 1)
    spacer:EnableMouse(true)
    WM.spacer = spacer

    local separator = border:CreateTexture(nil, "BACKGROUND", nil, -5)
    separator:SetAtlasTexture("_UI-Frame-InnerTopTile")
    separator:SetHeight(3)
    separator:SetPoint("TOPLEFT", border, "TOPLEFT", WM.INSET_L, -(WM.SPACER_H - 4))
    separator:SetPoint("RIGHT", spacer, "RIGHT", 0, 0)

    -- ARTWORK, under the OVERLAY corner whose ring frames it. Square art shrinks to clear the ring.
    local portrait = border:CreateTexture(nil, "ARTWORK")
    portrait:SetTexture(PORTRAIT)
    portrait:SetSize(56, 56)
    -- The book does not fill its own art, so it hangs low unless lifted inside the ring.
    portrait:SetPoint("TOPLEFT", border, "TOPLEFT", -2, 7)

    local title = border:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", border, "TOP", 0, -5)
    title:SetText(L["Map & Quest Log"])
    WM.title = title

    -- The title band drags the window. The frame is protected, so never in combat.
    local titleBar = CreateFrame("Frame", "MistUIWorldMapTitleBar", border)
    -- Over the spacer and the panel: at a shared level the spacer won, so only its right end dragged.
    titleBar:SetFrameLevel(BASE_LEVEL + 4)
    titleBar:SetPoint("TOPLEFT", border, "TOPLEFT", 58, -1)
    titleBar:SetPoint("TOPRIGHT", border, "TOPRIGHT", -52, -1)
    titleBar:SetHeight(20)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    local dragging, lastLeft, lastTop
    -- Blobs are rasterised where they were drawn, so they are redrawn wherever the window goes.
    local function follow()
        local left, top = f:GetLeft(), f:GetTop()
        if left == lastLeft and top == lastTop then return end
        lastLeft, lastTop = left, top
        if WM.RedrawBlobs then WM.RedrawBlobs() end
    end
    local function drop()
        if not dragging then return end
        dragging = nil
        titleBar:SetScript("OnUpdate", nil)
        f:StopMovingOrSizing()
        savePosition()
        -- Stock recomputes the blob hit box when this is nil.
        WorldMapBlobFrame.xRatio = nil
        if WM.RefreshBlobs then WM.RefreshBlobs() end
    end
    titleBar:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        dragging = true
        lastLeft, lastTop = f:GetLeft(), f:GetTop()
        titleBar:SetScript("OnUpdate", follow)
        f:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        addon:SafeExecute("worldmap", "drop", drop)
    end)
    -- The client keeps moving the window in combat but refuses the stop, so drop it before lockdown.
    titleBar:RegisterEvent("PLAYER_REGEN_DISABLED")
    titleBar:SetScript("OnEvent", function()
        if dragging then addon:SafeExecute("worldmap", "drop", drop) end
    end)

    -- Textures only: the close button's secure OnClick is what closes the map in combat.
    local close = WorldMapFrameCloseButton
    close:SetFrameStrata("HIGH")
    close:SetFrameLevel(BASE_LEVEL + 5)
    WM.ModernizeCloseButton(close, border, 1, 0)

    WM.maxMin = WM.BuildMaxMinButton(border, close)
    WM.sideToggle = WM.BuildSideToggle(border)
end

local function chromeAlpha(opacity)
    local alpha = 0.5 + (1 - (opacity or 0)) * 0.5
    WM.border:SetAlpha(alpha)
    WM.ground:SetAlpha(alpha)
end

-- ============================================================================
-- CONTROLS
-- ============================================================================

local function setButtonState(button, atlas)
    button:GetNormalTexture():SetAtlasTexture(atlas)
    button:GetPushedTexture():SetAtlasTexture(atlas .. "-pressed")
    button:GetDisabledTexture():SetAtlasTexture(atlas .. "-disabled")
end

function WM.BuildMaxMinButton(border, close)
    local button = CreateFrame("Button", "MistUIWorldMapMaximizeButton", border)
    button:SetSize(24, 24)
    button:SetPoint("RIGHT", close, "LEFT", -1, 0)
    button:SetFrameLevel(BASE_LEVEL + 5)
    button:SetNormalTexture(ROCK)
    button:SetPushedTexture(ROCK)
    button:SetDisabledTexture(ROCK)
    button:SetHighlightTexture(ROCK)
    button:GetHighlightTexture():SetAtlasTexture("redbutton-highlight")
    button:GetHighlightTexture():SetBlendMode("ADD")

    local function refresh()
        setButtonState(button, WM:Config().maximized and "redbutton-condense" or "redbutton-expand")
    end
    button:SetScript("OnClick", function()
        -- Rescaling the canvas writes the protected blob frame; the client refuses that in combat.
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1, 1.0)
            return
        end
        WM:Config().maximized = not WM:Config().maximized
        refresh()
        WM.Layout(true)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(WM:Config().maximized and MINIMIZE or L["Maximize"])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refresh()
    return button
end

function WM.BuildSideToggle(border)
    local button = CreateFrame("Button", "MistUIWorldMapQuestLogToggle", border)
    button:SetSize(32, 32)
    button:SetFrameLevel(BASE_LEVEL + 5)
    button:SetNormalTexture(ROCK)
    button:SetPushedTexture(ROCK)
    button:SetHighlightTexture(ROCK)
    button:GetHighlightTexture():SetBlendMode("ADD")

    -- On the frame like its left twin, not the button: the button's level put it over the bottom rail.
    local shadow = border:CreateTexture(nil, "ARTWORK")
    shadow:SetAtlasTexture("mapcornershadow-right", true)
    shadow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -5)

    -- No highlight cell in the sheet, so the arrow brightens itself and follows the pressed art.
    function button:SetHighlightArt(pressed)
        local state = WM.PanelShown() and "hide" or "show"
        self:GetHighlightTexture():SetAtlasTexture("questcollapse-" .. state .. (pressed and "-down" or "-up"))
    end

    function button:Refresh()
        local state = WM.PanelShown() and "hide" or "show"
        self:GetNormalTexture():SetAtlasTexture("questcollapse-" .. state .. "-up")
        self:GetPushedTexture():SetAtlasTexture("questcollapse-" .. state .. "-down")
        self:SetHighlightArt(false)
    end
    button:SetScript("OnMouseDown", function(self) self:SetHighlightArt(true) end)
    button:SetScript("OnMouseUp", function(self) self:SetHighlightArt(false) end)
    button:SetScript("OnClick", function()
        WM.SetPanelShown(not WM.PanelShown())
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(WM.PanelShown() and L["Hide Quest Log"] or L["Show Quest Log"])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Refresh()
    return button
end

function WM.PanelShown()
    return WM:Config().questLog ~= false
end

-- The panel is ours and shows at once; the window width it needs is the protected part.
function WM.SetPanelShown(shown)
    -- Maximized, the canvas is sized around the panel, and the canvas is protected in combat.
    if WM:Config().maximized and InCombatLockdown() then
        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1, 1.0)
        return
    end
    WM:Config().questLog = shown and true or false
    WM.sideToggle:Refresh()
    if WM.SetQuestLogShown then WM.SetQuestLogShown(shown) end
    WM.Layout(WM:Config().maximized)
end

-- ============================================================================
-- STOCK SIZE MODES
-- ============================================================================

-- The size keybind still reaches the stock fullscreen map, where our chrome gets out of the way.
local function onWindowedChanged()
    -- Its release would hand lent widgets back to the parents they had before this switch.
    addon.Menu.Close()
    local windowed = WM.IsWindowed()
    -- The chrome is ours and follows at once; the stock frames it re-anchors wait for the end of
    -- combat, and the pass then reads whichever mode the map is in by then.
    if InCombatLockdown() then
        if windowed then WM.border:Show() WM.ground:Show() else WM.border:Hide() WM.ground:Hide() end
        addon.CombatQueue:Add("worldmap_mode", onWindowedChanged)
        return
    end
    -- The clip is sized to the windowed canvas and would crop the stock fullscreen map.
    if WM.ResetZoom then WM.ResetZoom() end
    if windowed then
        WM.border:Show()
        WM.ground:Show()
        retireStockWidgets()
        placeShowMenu(true)
        WM.Place()
        -- Both size toggles re-anchor the close button to the chrome they just showed.
        WorldMapFrameCloseButton:ClearAllPoints()
        WorldMapFrameCloseButton:SetPoint("TOPRIGHT", WM.border, "TOPRIGHT", 1, 0)
        WM.Layout(true)
    else
        WM.border:Hide()
        WM.ground:Hide()
        -- Stock sets these only on a size change, so the canvas scale would follow them into fullscreen.
        if ScenarioPOIFrame then ScenarioPOIFrame:SetScale(WORLDMAP_FULLMAP_SIZE) end
        if WM.RefreshPins then WM.RefreshPins() end
        if WM.RestorePlayerMarkers then WM.RestorePlayerMarkers() end
        if WM.RefreshFade then WM.RefreshFade() end
        placeShowMenu(false)
        restoreStockWidgets()
        -- Where WorldMap_ToggleSizeUp puts it; a login straight into fullscreen never ran that.
        WorldMapFrameCloseButton:ClearAllPoints()
        WorldMapFrameCloseButton:SetPoint("TOPRIGHT", WorldMapPositioningGuide, 4, 4)
    end
    if WM.OnModeChanged then WM.OnModeChanged(windowed) end
end

local function installHooks()
    -- Every windowed re-layout of the stock map runs through ToggleSizeDown and re-anchors the canvas.
    hooksecurefunc("WorldMap_ToggleSizeUp", onWindowedChanged)
    hooksecurefunc("WorldMap_ToggleSizeDown", onWindowedChanged)
    hooksecurefunc("WorldMapFrame_SetOpacity", chromeAlpha)

    local function relayout()
        if WM:Config().maximized then WM.Layout(true) end
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:SetScript("OnEvent", relayout)
    addon.core.RegisterMessage(WM, "MISTUI_UI_SCALE_CHANGED", relayout)
end

-- ============================================================================
-- BOOT
-- ============================================================================

-- Stock reads this once, at VARIABLES_LOADED, and toggles itself down there; later costs a reload
-- or one press of the map's own size button.
local function prepareWindowedMode()
    if not GetCVarBool("miniWorldMap") then SetCVar("miniWorldMap", 1) end
end

local function boot()
    -- OnInitialize refreshes every module at our own ADDON_LOADED, when addons after us are still
    -- unloaded and no map replacer would be seen. Only the CVars are worth doing that early.
    if not IsLoggedIn() then
        -- Mapster drops the map from UIPanelWindows, so a forced miniWorldMap breaks the stock late toggle.
        if not replacerPending() then prepareWindowedMode() end
        return
    end
    if InCombatLockdown() then
        addon.CombatQueue:Add("worldmap_boot", boot)
        return
    end
    if WorldMapModule.initialized then return end
    WorldMapModule.initialized = true

    -- They reparent the same frame and drag it out of windowed mode on login; the two cannot share it.
    local replacer = loadedReplacer()
    if replacer then
        addon:Print(format(L["World map module disabled: %s replaces the same map frame."], replacer))
        return
    end

    prepareWindowedMode()

    buildChrome()
    installHooks()
    if WM.BuildNavBar then WM.BuildNavBar() end
    if WM.BuildPins then WM.BuildPins() end
    if WM.BuildQuestLog then WM.BuildQuestLog() end
    if WM.BuildCoords then WM.BuildCoords() end
    if WM.BuildPlayerArrow then WM.BuildPlayerArrow() end
    if WM.BuildFade then WM.BuildFade() end
    if WM.BuildZoom then WM.BuildZoom() end

    chromeAlpha(WORLDMAP_SETTINGS.opacity)
    onWindowedChanged()
    WorldMapModule.applied = true
end

function addon.ApplyWorldMapSystem()
    if WM:Enabled() and not WorldMapModule.applied then boot() end
end

function addon.RefreshWorldMapSystem()
    if not WorldMapModule.applied then
        addon.ApplyWorldMapSystem()
        return
    end
    WM.RefreshLandmarks()
    WM.RefreshNavBar()
    WM.RefreshCoords()
    WM.RefreshFade()
end

-- Hooks and reparented widgets cannot be undone in-session, so a disable waits for the reload.
function addon.RestoreWorldMapSystem()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    addon.ApplyWorldMapSystem()
end)
