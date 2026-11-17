-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Button sizes, offsets and texture coordinates adapted from DragonUI (MIT, (c) 2026 NeticSoul)
-- and DragonflightUI (MIT, (c) 2022 Karl-HeinzSchneider); see THIRD_PARTY_NOTICES.

-- Micro menu: the stock micro buttons in a bar of their own, with the newer icons.
--
-- The stock interface hands the buttons from bar to bar (main bar, override bar, pet battle) with
-- UpdateMicroButtonsParent and MoveMicroButtons, and re-anchors the game menu button on every
-- UpdateMicroButtons. This module lets those functions run and takes the buttons back from secure
-- hooks afterwards. The micro buttons are not protected frames, so that is allowed in combat.

local addon = select(2, ...)
local L = addon.L

local KEY = "micromenu"
local FADE_KEY = "micro"
local ART = addon._dir .. "Micromenu\\"
local SHEET = ART .. "uimicromenu2x"
local FACTION_SHEET = ART .. "micropvp"
local LATENCY_STRIP = ART .. "ui-mainmenubar-performancebar"

local BUTTON_WIDTH, BUTTON_HEIGHT = 32, 40
local DEFAULT_SCALE = 0.9
local DEFAULT_PADDING = -6
local MAX_COLUMNS = 12
-- The edit mode box is this much larger than the buttons, so its outline does not touch them.
local BOX_MARGIN = 10
local DEFAULT_ANCHOR, DEFAULT_X, DEFAULT_Y = "BOTTOMRIGHT", -3, 3
local PUSHED_ALPHA = 0.7
local HOVER_ALPHA = 0.5

-- The icon sheet is a grid of cells with a gutter between them and a one pixel border.
local SHEET_WIDTH, SHEET_HEIGHT = 1024, 512
local CELL_WIDTH, CELL_HEIGHT, CELL_GUTTER = 64, 82, 2

-- Each state of an icon is one cell: { column, row }, counted from zero.
local ICONS = {
    Achievements = { Disabled = { 0, 0 }, Down = { 0, 1 }, Mouseover = { 0, 2 }, Up = { 0, 3 } },
    AdventureGuide = { Disabled = { 0, 4 }, Down = { 0, 5 }, Mouseover = { 1, 0 }, Up = { 1, 1 } },
    Collections = { Disabled = { 1, 4 }, Down = { 1, 5 }, Mouseover = { 2, 0 }, Up = { 2, 1 } },
    GameMenu = { Disabled = { 2, 2 }, Down = { 2, 3 }, Mouseover = { 2, 4 }, Up = { 2, 5 } },
    Groupfinder = { Disabled = { 3, 0 }, Down = { 3, 1 }, Mouseover = { 3, 2 }, Up = { 3, 3 } },
    GuildCommunities = { Disabled = { 3, 4 }, Down = { 3, 5 }, Mouseover = { 4, 4 }, Up = { 4, 5 } },
    Questlog = { Disabled = { 5, 3 }, Down = { 5, 4 }, Mouseover = { 5, 5 }, Up = { 6, 0 } },
    Shop = { Disabled = { 6, 1 }, Down = { 6, 3 }, Mouseover = { 6, 2 }, Up = { 6, 4 } },
    SpecTalents = { Disabled = { 6, 5 }, Down = { 7, 0 }, Mouseover = { 7, 1 }, Up = { 7, 2 } },
    SpellbookAbilities = { Disabled = { 7, 3 }, Down = { 7, 4 }, Mouseover = { 7, 5 }, Up = { 8, 0 } },
}
-- The plate drawn behind every icon, raised and pressed.
local PLATE_UP, PLATE_DOWN = { 1, 2 }, { 1, 3 }
local PLATE_X, PLATE_Y = -1, 1

local FACTION_COORDS = {
    Alliance = { 0, 118 / 256, 0, 151 / 256 },
    Horde = { 118 / 256, 236 / 256, 0, 151 / 256 },
}

-- In display order. The client shows either the store button or the help button, never both.
local BUTTONS = {
    { name = "CharacterMicroButton", portrait = true },
    { name = "SpellbookMicroButton", icon = "SpellbookAbilities" },
    { name = "TalentMicroButton", icon = "SpecTalents" },
    { name = "AchievementMicroButton", icon = "Achievements" },
    { name = "QuestLogMicroButton", icon = "Questlog" },
    { name = "GuildMicroButton", icon = "GuildCommunities" },
    { name = "PVPMicroButton", faction = true },
    { name = "LFDMicroButton", icon = "Groupfinder" },
    { name = "CompanionsMicroButton", icon = "Collections" },
    { name = "EJMicroButton", icon = "AdventureGuide" },
    { name = "StoreMicroButton", icon = "Shop" },
    { name = "MainMenuMicroButton", icon = "GameMenu" },
    { name = "HelpMicroButton", icon = "GameMenu" },
}

local STATES = {
    { cell = "Up", get = "GetNormalTexture", set = "SetNormalTexture", stockResets = true },
    { cell = "Down", get = "GetPushedTexture", set = "SetPushedTexture", stockResets = true },
    { cell = "Disabled", get = "GetDisabledTexture", set = "SetDisabledTexture", stockResets = true },
    { cell = "Mouseover", get = "GetHighlightTexture", set = "SetHighlightTexture" },
}

-- Out of a pet battle the bar is always shown; the second rule also hides it on a vehicle.
local DRIVER_DEFAULT = "[petbattle] hide; show"
local DRIVER_HIDE_ON_VEHICLE = "[petbattle][vehicleui][overridebar] hide; show"

local FADE_FLAGS = { "always_hidden", "show_on_hover", "show_in_combat", "hide_in_combat", "visibility_logic" }
local FADE_NUMBERS = { "shown_alpha", "hidden_alpha", "fade_in_duration", "fade_out_duration", "fade_out_delay" }

local Menu = { initialized = false, applied = false }
addon.MicroMenuModule = Menu

if addon.RegisterModule then
    addon:RegisterModule(KEY, Menu, L["Micro Menu"], L["Micro menu and bags system styling and positioning"])
end

local bar, box
local skinned = {}
local painting = false
local storeShown

function Menu.Profile()
    return addon.db.profile.micromenu
end

local function CellCoords(cell)
    local left = 1 + cell[1] * (CELL_WIDTH + CELL_GUTTER)
    local top = 1 + cell[2] * (CELL_HEIGHT + CELL_GUTTER)
    return left / SHEET_WIDTH, (left + CELL_WIDTH) / SHEET_WIDTH, top / SHEET_HEIGHT, (top + CELL_HEIGHT) / SHEET_HEIGHT
end

-- ============================================================================
-- Painting
-- ============================================================================

-- The help button takes the question mark. With the store off the game menu button is shown next
-- to it and gets the remaining icon, as in DragonUI; with the store on it is the question mark.
local function IconFor(info)
    if info.name == "MainMenuMicroButton" and not StoreMicroButton:IsShown() then
        return ICONS.Shop
    end
    return ICONS[info.icon]
end

local function PaintIcon(button, icon)
    for _, state in ipairs(STATES) do
        local texture = button[state.get](button)
        if not texture then
            button[state.set](button, SHEET)
            texture = button[state.get](button)
        end
        if texture then
            texture:SetTexture(SHEET)
            texture:SetTexCoord(CellCoords(icon[state.cell]))
            texture:ClearAllPoints()
            texture:SetAllPoints(button)
        end
    end
    local glow = button:GetHighlightTexture()
    if glow then
        glow:SetBlendMode("ADD")
    end
end

local function ClearStateTextures(button)
    for _, state in ipairs(STATES) do
        local texture = button[state.get](button)
        if texture then
            texture:SetTexture(nil)
        end
    end
end

local function PaintPortrait(button)
    ClearStateTextures(button)
    MicroButtonPortrait:ClearAllPoints()
    MicroButtonPortrait:SetPoint("CENTER", button, "CENTER", 0, -0.5)
    MicroButtonPortrait:SetSize(18, 24)
end

local function PlaceFactionIcon(button, pushed)
    local icon = button.mistuiFactionIcon
    local pushX, pushY = button:GetPushedTextOffset()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER", pushed and pushX or 0, pushed and pushY or 0)
    icon:SetAlpha(pushed and PUSHED_ALPHA or 1)
    -- The stock faction emblem is drawn by the stock code on every state change.
    PVPMicroButtonTexture:SetAlpha(0)
end

local function PaintFaction(button)
    ClearStateTextures(button)
    local icon = button.mistuiFactionIcon
    local coords = FACTION_COORDS[UnitFactionGroup("player")]
    if not coords then
        -- A character that has not chosen a faction yet: the stock code keeps the button disabled.
        icon:Hide()
        PVPMicroButtonTexture:SetAlpha(0)
        return
    end
    icon:SetTexture(FACTION_SHEET)
    icon:SetTexCoord(unpack(coords))
    icon:Show()
    local glow = button:GetHighlightTexture()
    if glow then
        glow:SetTexture(FACTION_SHEET)
        glow:SetTexCoord(unpack(coords))
        glow:ClearAllPoints()
        glow:SetAllPoints(button)
        glow:SetBlendMode("ADD")
        glow:SetAlpha(HOVER_ALPHA)
    end
    PlaceFactionIcon(button, button.mistuiPanelOpen)
end

local function PaintByKind(button)
    local info = skinned[button]
    if info.portrait then
        PaintPortrait(button)
    elseif info.faction then
        PaintFaction(button)
    else
        PaintIcon(button, IconFor(info))
    end
end

-- Also runs from hooks on the three texture setters the stock code uses to put its own art
-- back: on the game menu button every second, on the guild button when the guild emblem
-- changes. The stock code calls them one after the other, so hooking only the first would
-- leave the art of the later ones in place.
local function Paint(button)
    if painting or not Menu.applied or not skinned[button] then
        return
    end
    painting = true
    local ok, err = pcall(PaintByKind, button)
    painting = false
    if not ok then
        error(err, 0)
    end
end

local function ShowPlate(button, pushed)
    if pushed then
        button.mistuiPlateUp:Hide()
        button.mistuiPlateDown:Show()
    else
        button.mistuiPlateUp:Show()
        button.mistuiPlateDown:Hide()
    end
end

-- The stock code pushes a button in while its window is open (SetButtonState).
local function OnButtonState(button, state)
    button.mistuiPanelOpen = state == "PUSHED"
    ShowPlate(button, button.mistuiPanelOpen)
end

local function OnMouseDown(button)
    if button:IsEnabled() then
        ShowPlate(button, true)
    end
end

local function OnMouseUp(button)
    ShowPlate(button, button.mistuiPanelOpen)
end

local function CreatePlate(button, cell, x, y)
    local plate = button:CreateTexture(nil, "BACKGROUND")
    plate:SetTexture(SHEET)
    plate:SetTexCoord(CellCoords(cell))
    plate:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT + 1)
    plate:SetPoint("CENTER", button, "CENTER", x, y)
    return plate
end

local function CreatePortraitGlow(button)
    local glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetAllPoints(MicroButtonPortrait)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(HOVER_ALPHA)
    glow:Hide()
    button:HookScript("OnEnter", function()
        SetPortraitTexture(glow, "player")
        glow:SetTexCoord(MicroButtonPortrait:GetTexCoord())
        glow:Show()
    end)
    button:HookScript("OnLeave", function()
        glow:Hide()
    end)
end

local function Style(info)
    local button = _G[info.name]
    local pushX, pushY = button:GetPushedTextOffset()
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    -- The stock button is taller than its art and ignores clicks on the empty top part.
    button:SetHitRectInsets(0, 0, 0, 0)
    button.Flash:ClearAllPoints()
    button.Flash:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 0)

    button.mistuiPlateUp = CreatePlate(button, PLATE_UP, PLATE_X, PLATE_Y)
    button.mistuiPlateDown = CreatePlate(button, PLATE_DOWN, PLATE_X + pushX, PLATE_Y + pushY)
    button.mistuiPanelOpen = button:GetButtonState() == "PUSHED"
    ShowPlate(button, button.mistuiPanelOpen)

    if info.portrait then
        CreatePortraitGlow(button)
    elseif info.faction then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
        button.mistuiFactionIcon = icon
    end

    hooksecurefunc(button, "SetButtonState", OnButtonState)
    for _, state in ipairs(STATES) do
        if state.stockResets then
            hooksecurefunc(button, state.set, Paint)
        end
    end
    button:HookScript("OnMouseDown", OnMouseDown)
    button:HookScript("OnMouseUp", OnMouseUp)

    skinned[button] = info
    Paint(button)
end

-- The stock latency strip lives on the game menu button, which also shows the numbers on hover.
local function PaintLatencyStrip()
    local strip = MainMenuBarPerformanceBar
    strip:SetTexture(LATENCY_STRIP)
    strip:SetBlendMode("ADD")
    strip:ClearAllPoints()
    strip:SetPoint("BOTTOM", MainMenuMicroButton, "BOTTOM", 1, -6.5)
    strip:SetSize(22, 60)
    if Menu.Profile().show_latency_indicator then
        strip:Show()
    else
        strip:Hide()
    end
end

-- ============================================================================
-- Ownership and layout
-- ============================================================================

local function TakeButtons()
    for _, info in ipairs(BUTTONS) do
        _G[info.name]:SetParent(bar)
    end
end

local function Layout()
    local config = Menu.Profile().normal
    local buttons = {}
    for _, info in ipairs(BUTTONS) do
        local button = _G[info.name]
        if button:IsShown() then
            buttons[#buttons + 1] = button
        end
    end
    local count = #buttons
    if count == 0 then
        return
    end

    local padding = tonumber(config.icon_spacing) or DEFAULT_PADDING
    local columns = math.floor(tonumber(config.columns) or MAX_COLUMNS)
    columns = math.max(1, math.min(columns, count))
    local rows = math.ceil(count / columns)
    local stepX, stepY = BUTTON_WIDTH + padding, BUTTON_HEIGHT + padding

    for position, button in ipairs(buttons) do
        local index = config.invert_order and (count - position) or (position - 1)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (index % columns) * stepX, math.floor(index / columns) * stepY)
    end

    local width = columns * BUTTON_WIDTH + (columns - 1) * padding
    local height = rows * BUTTON_HEIGHT + (rows - 1) * padding
    local scale = tonumber(config.scale_menu) or DEFAULT_SCALE
    bar:SetScale(scale)
    bar:SetSize(width, height)
    box:SetSize((width + BOX_MARGIN) * scale, (height + BOX_MARGIN) * scale)
end

local function AfterStockUpdate()
    -- The guild emblem is drawn for the stock button shape; the guild icon is shown instead.
    GuildMicroButtonTabard:SetAlpha(0)
    local shown = StoreMicroButton:IsShown() and true or false
    if shown ~= storeShown then
        storeShown = shown
        Paint(MainMenuMicroButton)
    end
    Layout()
end

local function InstallHooks()
    hooksecurefunc("UpdateMicroButtonsParent", function()
        if Menu.applied then
            TakeButtons()
        end
    end)
    -- MoveMicroButtons ends in UpdateMicroButtons, so this one hook also follows every move.
    hooksecurefunc("UpdateMicroButtons", function()
        if Menu.applied then
            AfterStockUpdate()
        end
    end)
    hooksecurefunc("PVPMicroButton_SetPushed", function()
        if Menu.applied then
            PlaceFactionIcon(PVPMicroButton, true)
        end
    end)
    hooksecurefunc("PVPMicroButton_SetNormal", function()
        if Menu.applied then
            PlaceFactionIcon(PVPMicroButton, false)
        end
    end)
end

-- ============================================================================
-- Shared with the bag bar: fading and the vehicle rule
-- ============================================================================

function Menu.RegisterFade(prefix, frame, hoverFrames)
    local fade = addon.VisibilityFade
    fade.Register(prefix, frame, {
        hoverFrames = hoverFrames,
        clickThrough = true,
        -- These buttons only open windows, so their mouse state may change in combat.
        mouseSafeInCombat = true,
        dbTable = function()
            local bars = addon.db.profile.actionbars
            if not bars then
                return nil
            end
            local config = {}
            for _, flag in ipairs(FADE_FLAGS) do
                config[flag] = bars[prefix .. "_" .. flag]
            end
            for _, number in ipairs(FADE_NUMBERS) do
                config["visibility_" .. number] = bars[prefix .. "_visibility_" .. number]
            end
            return config
        end,
    })
    fade.Update(prefix)
end

function Menu.ApplyVisibilityDriver(frame, queueKey, retry)
    if InCombatLockdown() then
        addon.CombatQueue:Add(queueKey, retry)
        return
    end
    local rule = Menu.Profile().hide_on_vehicle and DRIVER_HIDE_ON_VEHICLE or DRIVER_DEFAULT
    RegisterStateDriver(frame, "visibility", rule)
end

function addon.RefreshMicroMenuVisibility()
    addon.VisibilityFade.Update(FADE_KEY)
    if Menu.Bags then
        addon.VisibilityFade.Update(Menu.Bags.FADE_KEY)
    end
end

function addon.RefreshMicromenuVehicle()
    if bar then
        Menu.ApplyVisibilityDriver(bar, "micromenu_vehicle", addon.RefreshMicromenuVehicle)
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function Apply()
    bar = CreateFrame("Frame", "MistUI_MicroButtonBar", UIParent)
    -- Above the stock main bar art, in case the two overlap.
    bar:SetFrameLevel(MainMenuBar:GetFrameLevel() + 2)
    box = addon.CreateUIFrame(BUTTON_WIDTH, BUTTON_HEIGHT, "MicroMenu")
    box:SetPoint(DEFAULT_ANCHOR, UIParent, DEFAULT_ANCHOR, DEFAULT_X, DEFAULT_Y)
    addon.ApplyWidgetPositionFromDB(KEY, box)
    bar:SetPoint("CENTER", box, "CENTER")

    Menu.applied = true
    TakeButtons()
    local hoverFrames = { bar }
    for _, info in ipairs(BUTTONS) do
        Style(info)
        hoverFrames[#hoverFrames + 1] = _G[info.name]
    end
    PaintLatencyStrip()
    InstallHooks()
    AfterStockUpdate()

    addon:RegisterEditableFrame({
        name = KEY,
        frame = box,
        stockFrame = bar,
        configPath = { "widgets", KEY },
        module = Menu,
    })
    Menu.RegisterFade(FADE_KEY, bar, hoverFrames)
    addon.RefreshMicromenuVehicle()

    if Menu.Bags then
        Menu.Bags.Apply()
    end
end

function addon.RefreshMicromenu()
    if not Menu.applied then
        return
    end
    Layout()
    PaintLatencyStrip()
    addon.RefreshMicromenuVehicle()
end

-- Kept as a second name: the edit mode settings call it for the latency strip.
addon.RefreshMicromenuButtons = addon.RefreshMicromenu

-- Turning the module off takes effect on the next reload: the stock bars get their buttons back
-- by never having them taken.
function addon.RefreshMicromenuSystem()
    if not addon:IsModuleEnabled(KEY) then
        return
    end
    if not Menu.applied then
        if not IsLoggedIn() then
            return
        end
        Apply()
    end
    addon.RefreshMicromenu()
    if addon.RefreshBags then
        addon.RefreshBags()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
boot:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Menu.initialized = true
        addon.RefreshMicromenuSystem()
    else
        Paint(PVPMicroButton)
    end
end)
