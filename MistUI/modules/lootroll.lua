-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local L = addon.L

-- =============================================================================
-- MISTUI LOOT ROLL MODULE
-- Moves GroupLootContainer (the parent of all roll frames) to a custom position.
-- The container is moved, not the individual GroupLootFrame1-4: the stock code
-- stacks the roll frames inside it (GroupLootContainer_Update) and keeps doing so.
-- =============================================================================

local LootRollModule = {
    initialized = false,
    applied = false,
}
addon.LootRollModule = LootRollModule

-- Loot Roll is not registered as a toggleable module - it always runs.
-- Position is managed via Editor Mode only.

-- =============================================================================
-- DEFAULT POSITION
-- =============================================================================
local DEFAULTS = {
    anchor = "BOTTOM",
    x = 0,
    y = 220,
}

-- The stock container is only 1 unit high until a roll opens; each roll reserves this much room.
local ROLL_SLOT_HEIGHT = 100
local CONTAINER_WIDTH = 256

-- =============================================================================
-- CONFIG
-- =============================================================================
local function GetLootRollConfig()
    if not (addon.db and addon.db.profile and addon.db.profile.lootroll) then
        return DEFAULTS.x, DEFAULTS.y, DEFAULTS.anchor
    end
    local cfg = addon.db.profile.lootroll
    return cfg.x or DEFAULTS.x, cfg.y or DEFAULTS.y, cfg.anchor or DEFAULTS.anchor
end

-- =============================================================================
-- POSITION HELPERS
-- =============================================================================

local function IsAtDefaultPosition(x, y, point)
    local defaults = addon.defaults and addon.defaults.profile.lootroll or DEFAULTS
    return point == defaults.anchor and math.abs(x - defaults.x) <= 1 and math.abs(y - defaults.y) <= 1
end

--- Move the invisible anchor frame to the saved (or default) position.
local function UpdateAnchorPosition()
    local anchor = LootRollModule.anchorFrame
    if not anchor then return end
    local x, y, point = GetLootRollConfig()
    local lift = 0
    if IsAtDefaultPosition(x, y, point) then
        lift = (addon.GetPetbarStackLift and addon.GetPetbarStackLift() or 0)
            + (addon.GetGCDStackLift and addon.GetGCDStackLift() or 0)
    end
    -- Position presets read this frame back; they subtract the lift so it is never saved as a move.
    anchor.MistUI_LayoutOffset = lift > 0 and { 0, lift } or nil
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, point, x, y + lift)
end

--- Attach GroupLootContainer to the bottom of our anchor frame.
--- Stock keeps managing frames *inside* the container; we only move
--- the container itself.
local attachingContainer = false  -- re-entrancy guard

local function AttachContainer()
    local anchor = LootRollModule.anchorFrame
    if not (anchor and GroupLootContainer) then return end

    -- UIParent_ManageFramePosition skips frames carrying this flag, so the stock layout pass
    -- (action bars, pet bar, reputation bar) no longer moves the container.
    GroupLootContainer.ignoreFramePositionManager = true

    attachingContainer = true
    GroupLootContainer:ClearAllPoints()
    GroupLootContainer:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    attachingContainer = false
end

-- =============================================================================
-- HOOKS  (installed once)
-- =============================================================================
local hookInstalled = false
local function InstallHooks()
    if hookInstalled or not GroupLootContainer then return end

    -- Another addon moving the container gets corrected right away.
    hooksecurefunc(GroupLootContainer, "SetPoint", function()
        if not LootRollModule.applied then return end
        if attachingContainer then return end   -- our own call
        AttachContainer()
    end)

    hookInstalled = true
end

-- Stores where the user left the anchor (drag or editor panel), re-anchored to its screen quadrant.
local function SaveAnchorPosition(f)
    local point, x, y = addon.GetQuadrantAnchor(f)
    if point then
        f:ClearAllPoints()
        f:SetPoint(point, UIParent, point, x, y)
        f:SetUserPlaced(false)

        -- Save to DB
        if addon.db and addon.db.profile then
            if not addon.db.profile.lootroll then
                addon.db.profile.lootroll = {}
            end
            addon.db.profile.lootroll.anchor = point
            addon.db.profile.lootroll.x = x
            addon.db.profile.lootroll.y = y
        end

        -- Re-attach container to new position
        AttachContainer()
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function LootRollModule:Initialize()
    if self.initialized then return end

    -- Create invisible anchor frame the user drags in editor mode
    local anchor = CreateFrame("Frame", "MistUI_LootRollAnchor", UIParent)
    local w = GroupLootContainer and GroupLootContainer:GetWidth() or CONTAINER_WIDTH
    local h = GroupLootContainer and GroupLootContainer.reservedSize or ROLL_SLOT_HEIGHT
    anchor:SetSize(w, h)
    anchor:EnableMouse(false)
    anchor:SetMovable(false)

    -- Add nineslice overlay for editor mode
    if addon.AddNineslice then
        addon.AddNineslice(anchor)
        addon.SetNinesliceState(anchor, false)
        addon.HideNineslice(anchor)
    end

    -- Create text label for editor mode
    local fontString = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fontString:SetPoint("CENTER")
    fontString:SetText(L["Loot Roll"])
    fontString:Hide()
    anchor.editorText = fontString

    self.anchorFrame = anchor

    -- Position anchor & attach container
    UpdateAnchorPosition()
    InstallHooks()
    AttachContainer()

    -- Register with Editor Mode
    if addon.RegisterEditableFrame then
        addon:RegisterEditableFrame({
            name = "lootroll",
            frame = anchor,
            configPath = nil, -- Custom save logic in OnDragStop
            onNudge = function()
                SaveAnchorPosition(anchor)
            end,
            showTest = function()
                LootRollModule:ShowEditorTest()
            end,
            hideTest = function()
                LootRollModule:HideEditorTest()
            end,
            onHide = function()
                UpdateAnchorPosition()
                AttachContainer()
            end,
            resetPosition = function()
                local cfg = addon.db and addon.db.profile and addon.db.profile.lootroll
                local defaults = addon.defaults and addon.defaults.profile.lootroll
                if not (cfg and defaults) then return end
                cfg.anchor, cfg.x, cfg.y = defaults.anchor, defaults.x, defaults.y
                UpdateAnchorPosition()
                AttachContainer()
            end,
            isDefaultPosition = function()
                return IsAtDefaultPosition(GetLootRollConfig())
            end,
            module = LootRollModule
        })
    end

    self.initialized = true
    self.applied = true
end

-- =============================================================================
-- APPLY / RESTORE
-- =============================================================================
function LootRollModule:ApplySystem()
    if not self.initialized then
        self:Initialize()
        return
    end

    UpdateAnchorPosition()
    AttachContainer()
    self.applied = true
end

-- Public refresh helper used by position presets and profile operations.
function addon.RefreshLootRoll()
    if not LootRollModule.initialized then
        LootRollModule:Initialize()
        return
    end

    UpdateAnchorPosition()
    AttachContainer()
end

function LootRollModule:RestoreSystem()
    if not self.applied then return end
    -- Give the container back to the stock position manager
    if GroupLootContainer then
        GroupLootContainer.ignoreFramePositionManager = nil
    end
    self.applied = false
end

-- =============================================================================
-- EDITOR MODE
-- =============================================================================
function LootRollModule:ShowEditorTest()
    local frame = self.anchorFrame
    if not frame then return end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    -- Show nineslice
    if frame.NineSlice and addon.ShowNineslice then
        addon.SetNinesliceState(frame, false)
        addon.ShowNineslice(frame)
    end

    if frame.editorText then
        frame.editorText:Show()
    end

    -- Click to select in editor panel
    frame:SetScript("OnMouseDown", function(f, button)
        if button == "LeftButton" and addon.SelectEditorFrame then
            addon.SelectEditorFrame(f)
        end
    end)

    frame:SetScript("OnDragStart", function(f)
        f.MistUI_LayoutOffset = nil
        f:StartMoving()
        -- Ensure selected
        if addon.selectedEditorFrame ~= f and addon.SelectEditorFrame then
            addon.SelectEditorFrame(f)
        end
        -- Clear green tint while dragging (show default drag nineslice)
        if addon.ClearSelectionTint then
            addon.ClearSelectionTint(f)
        end
    end)

    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        f:SetScript("OnUpdate", nil)
        -- Re-apply green tint after drop (frame stays selected)
        if addon.ApplySelectionTint then
            addon.ApplySelectionTint(f)
        end

        SaveAnchorPosition(f)
    end)
end

function LootRollModule:HideEditorTest()
    local frame = self.anchorFrame
    if not frame then return end

    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
    frame:SetScript("OnMouseDown", nil)

    if frame.NineSlice and addon.HideNineslice then
        addon.HideNineslice(frame)
    end
    if frame.editorText then
        frame.editorText:Hide()
    end
end

-- =============================================================================
-- EVENTS
-- =============================================================================
addon.package:Subscribe(function()
    LootRollModule:Initialize()
end, "PLAYER_LOGIN")

-- Re-attach after zone changes and reloads.
addon.package:Subscribe(function()
    if LootRollModule.applied then
        AttachContainer()
    end
end, "PLAYER_ENTERING_WORLD")

-- =============================================================================
-- AUTO ROLL (Auto Greed/DE)
-- =============================================================================

local ROLL_GREED, ROLL_DISENCHANT, GREEN_QUALITY = 2, 3, 2

local function AutoRollOnLoot(_, _, rollID)
    local cfg = addon.db and addon.db.profile and addon.db.profile.lootroll
    if not (cfg and cfg.autoRoll) then return end

    if UnitLevel("player") ~= MAX_PLAYER_LEVEL then return end

    local _, _, _, quality, bindOnPickUp, _, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if quality ~= GREEN_QUALITY or bindOnPickUp then return end

    if canDisenchant then
        RollOnLoot(rollID, ROLL_DISENCHANT)
    elseif canGreed then
        RollOnLoot(rollID, ROLL_GREED)
    end
end

addon.package:Subscribe(AutoRollOnLoot, "START_LOOT_ROLL")
