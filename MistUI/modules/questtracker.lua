-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- Quest tracker: the stock tracker, placed by MistUI.
--
-- The stock tracker keeps its whole job (quests, achievements, timers, the auto-accept and
-- auto-complete popups, scenario objectives). This file only decides where it stands and how
-- tall it may grow, and gives it a box to drag in edit mode. See docs/decisions/0005.

local addon = select(2, ...)
local L = addon.L

local KEY = "questtracker"
-- The stock frame's size in WatchFrame.xml; the edit mode box wraps the same area.
local STOCK_WIDTH, STOCK_HEIGHT = 204, 140
-- Room kept free under the tracker for the bag buttons and the bars at the bottom of the screen.
local BOTTOM_MARGIN = 150
-- The tracker reads its room from its own top and bottom edges; with no room it draws nothing.
local MIN_HEIGHT = STOCK_HEIGHT
-- Used when the profile holds no position, and by a position reset.
local DEFAULT_ANCHOR, DEFAULT_X, DEFAULT_Y = "TOPRIGHT", -40, -250

local Tracker = { initialized = false, applied = false }
addon.QuestTrackerModule = Tracker

if addon.RegisterModule then
    addon:RegisterModule(KEY, Tracker,
        L["Quest Tracker"],
        L["Quest tracker positioning and styling"],
        { lifecyclePrefix = "QuestTracker", loadOnce = true })
end

local box

local function Config()
    return addon.db.profile.questtracker
end

local function PlaceBox()
    local config = Config()
    local anchor = config.anchor or DEFAULT_ANCHOR
    box:ClearAllPoints()
    box:SetPoint(anchor, UIParent, anchor, config.x or DEFAULT_X, config.y or DEFAULT_Y)
end

-- The box's top right corner as offsets from the screen's top right corner.
local function BoxCorner()
    local right, top = box:GetRight(), box:GetTop()
    if not (right and top) then
        return nil
    end
    return right - UIParent:GetRight(), top - UIParent:GetTop()
end

local function SaveBox()
    local x, y = BoxCorner()
    if not x then
        return
    end
    local config = Config()
    config.anchor = "TOPRIGHT"
    config.x = math.floor(x + 0.5)
    config.y = math.floor(y + 0.5)
    PlaceBox()
end

-- The stock layout code leaves a "user placed" tracker alone (UIParent.lua), so the flag is what
-- hands the position over. Top and bottom are both anchors, as the stock code does it: the height
-- then follows from them and no size is ever set here. Setting a size from addon code would run
-- the tracker's own redraw as addon code, which the client holds against it later in combat.
local function PlaceTracker()
    local x, y = BoxCorner()
    if not x then
        return
    end
    local config = Config()
    WatchFrame:SetMovable(true)
    WatchFrame:SetUserPlaced(true)
    WatchFrame:ClearAllPoints()
    WatchFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y)
    local height = config.custom_height and tonumber(config.height)
    if height then
        height = math.max(height, MIN_HEIGHT)
    elseif UIParent:GetHeight() + y - BOTTOM_MARGIN < MIN_HEIGHT then
        -- The box sits near the bottom edge, where the stock bottom margin would leave no room.
        height = MIN_HEIGHT
    end
    if height then
        WatchFrame:SetPoint("BOTTOMRIGHT", UIParent, "TOPRIGHT", x, y - height)
    else
        WatchFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, BOTTOM_MARGIN)
    end
end

local function ReleaseTracker()
    WatchFrame:SetUserPlaced(false)
    -- The stock layout pass puts the tracker back under the minimap cluster.
    UIParent_ManageFramePositions()
end

local function Apply()
    PlaceBox()
    -- The tracker carries protected quest item buttons, so it cannot be moved during combat.
    addon:SafeExecute(KEY, "place", PlaceTracker)
end

local function CreateBox()
    if box then
        return
    end
    box = addon.CreateUIFrame(STOCK_WIDTH, STOCK_HEIGHT, "QuestTracker")
    box:HookScript("OnDragStop", function()
        SaveBox()
        Apply()
    end)
    addon:RegisterEditableFrame({
        name = KEY,
        frame = box,
        -- Saved by SaveBox: the layout presets read the position from the questtracker settings.
        configPath = nil,
        editorVisible = function()
            return Tracker.applied
        end,
        onNudge = function()
            SaveBox()
            Apply()
        end,
        onHide = function()
            SaveBox()
            Apply()
        end,
        resetPosition = function()
            local config = Config()
            config.anchor, config.x, config.y = DEFAULT_ANCHOR, DEFAULT_X, DEFAULT_Y
            Apply()
        end,
        isDefaultPosition = function()
            local config = Config()
            return (config.anchor or DEFAULT_ANCHOR) == DEFAULT_ANCHOR
                and math.abs((config.x or DEFAULT_X) - DEFAULT_X) <= 1
                and math.abs((config.y or DEFAULT_Y) - DEFAULT_Y) <= 1
        end,
        applyPosition = Apply,
        module = Tracker,
    })
end

-- The name core/api.lua and the layout presets call for this module.
function addon.RefreshQuestTracker()
    if not Tracker.initialized then
        return
    end
    if addon:IsModuleEnabled(KEY) then
        Tracker.applied = true
        Apply()
    elseif Tracker.applied then
        Tracker.applied = false
        addon:SafeExecute(KEY, "place", ReleaseTracker)
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
-- A new resolution or interface scale moves every corner the offsets are measured from.
boot:RegisterEvent("DISPLAY_SIZE_CHANGED")
boot:RegisterEvent("UI_SCALE_CHANGED")
boot:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CreateBox()
        Tracker.initialized = true
    end
    addon.RefreshQuestTracker()
end)
