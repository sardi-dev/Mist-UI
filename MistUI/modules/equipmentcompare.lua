-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local L = addon.L

-- Stock compares on Shift, or always with the alwaysCompareItems option, and never for item
-- link windows without Shift. The tooltips are filled directly so Ctrl can switch the
-- comparison off and link windows can show it.

local EquipmentCompareModule = {
    initialized = false,
    applied = false,
    hooks = {},
}

if addon.RegisterModule then
    addon:RegisterModule("equipmentcompare", EquipmentCompareModule,
        (L and L["Automatic Equipment Comparison"]) or "Automatic Equipment Comparison",
        (L and L["Compare equippable items with your equipped gear without holding Shift, including item links opened from chat."])
            or "Compare equippable items with your equipped gear without holding Shift, including item links opened from chat.", {
        lifecyclePrefix = "EquipmentCompare",
    })
end

local PAIRS = {
    { tooltip = "GameTooltip", shopping = { "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3" }, ownShift = true },
    { tooltip = "ItemRefTooltip", shopping = { "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "ItemRefShoppingTooltip3" }, refillOnLeave = true },
}

-- The stock order: the third comparison sits next to the item, then the first, then the second.
local COMPARE_ORDER = { 3, 1, 2 }

local function IsModuleEnabled()
    return addon:IsModuleEnabled("equipmentcompare")
end

-- The link window drops its comparison on the update after Shift is released; the refill waits
-- for that update.
local SHIFT_REFILL_DELAY = 0.1

-- Ctrl suppresses the comparison while held; Shift keeps its own meaning.
local function IsSuppressed()
    return IsControlKeyDown and IsControlKeyDown() or false
end

-- ============================================================================
-- COMPARISON TOOLTIPS
-- ============================================================================

local function HideComparison(pair)
    for index = 1, #pair.shopping do
        local tooltip = _G[pair.shopping[index]]
        if tooltip then
            tooltip:Hide()
        end
    end
end

local function ShowComparison(pair)
    local frame = _G[pair.tooltip]
    if not frame or not frame:IsShown() or not IsModuleEnabled() then
        return
    end
    local shift = IsModifiedClick("COMPAREITEMS")
    -- Shift on GameTooltip is the stock compare path on every client; filling too would fight it.
    if shift and pair.ownShift then
        return
    end
    if not shift and (IsSuppressed() or frame:IsEquippedItem()) then
        HideComparison(pair)
        return
    end

    local _, link = frame:GetItem()
    if not link then
        HideComparison(pair)
        return
    end

    local left = frame:GetLeft() or 0
    local right = frame:GetRight() or 0
    local placeOnLeft = left > ((GetScreenWidth() or 0) - right)
    local point = placeOnLeft and "TOPRIGHT" or "TOPLEFT"
    local relativePoint = placeOnLeft and "TOPLEFT" or "TOPRIGHT"
    local anchor, offsetY = frame, -10

    for _, index in ipairs(COMPARE_ORDER) do
        local tooltip = _G[pair.shopping[index]]
        if tooltip then
            tooltip:SetOwner(anchor, "ANCHOR_NONE")
            if tooltip:SetHyperlinkCompareItem(link, index, 1, frame) then
                -- The stock UI only clamps ShoppingTooltip1-3; ItemRef's ran off the bottom edge.
                tooltip:SetClampedToScreen(true)
                tooltip:ClearAllPoints()
                tooltip:SetPoint(point, anchor, relativePoint, 0, offsetY)
                tooltip:Show()
                anchor, offsetY = tooltip, 0
            else
                tooltip:Hide()
            end
        end
    end
end

local function ForEachPair(fn)
    for _, pair in ipairs(PAIRS) do
        fn(pair)
    end
end

local function HideOwnComparison(pair)
    if not (pair.ownShift and IsModifiedClick("COMPAREITEMS")) then
        HideComparison(pair)
    end
end

-- ============================================================================
-- MODIFIER WATCH
-- ============================================================================

-- Watched by event so Ctrl takes effect mid-hover, not only when the tooltip is set.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
watcher:SetScript("OnEvent", function(_, _, key, down)
    if not IsModuleEnabled() then
        return
    end
    -- down is 1 or 0, and 0 is truthy in Lua.
    if key == "LCTRL" or key == "RCTRL" then
        ForEachPair(down == 1 and HideOwnComparison or ShowComparison)
    elseif (key == "LSHIFT" or key == "RSHIFT") and down == 0 then
        addon:After(SHIFT_REFILL_DELAY, function()
            if IsModuleEnabled() then
                ForEachPair(ShowComparison)
            end
        end)
    end
end)

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function InstallHooks(pair)
    local frame = _G[pair.tooltip]
    if not frame or EquipmentCompareModule.hooks[frame] then
        return
    end
    EquipmentCompareModule.hooks[frame] = true

    frame:HookScript("OnTooltipSetItem", function()
        ShowComparison(pair)
    end)
    frame:HookScript("OnTooltipCleared", function()
        if IsModuleEnabled() then
            HideOwnComparison(pair)
        end
    end)
    if pair.refillOnLeave then
        -- The stock OnLeave hides these (Shift-while-hovering model); ours stay up with the window.
        frame:HookScript("OnLeave", function()
            ShowComparison(pair)
        end)
    end
end

local function ApplyEquipmentCompareSystem()
    if not IsModuleEnabled() then
        return
    end
    ForEachPair(InstallHooks)

    EquipmentCompareModule.applied = true
    EquipmentCompareModule.initialized = true
end

local function RestoreEquipmentCompareSystem()
    ForEachPair(HideComparison)
    EquipmentCompareModule.applied = false
end

local function RefreshEquipmentCompareSystem()
    if IsModuleEnabled() then
        ApplyEquipmentCompareSystem()
    else
        RestoreEquipmentCompareSystem()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    if IsModuleEnabled() then
        ApplyEquipmentCompareSystem()
    end
end)

addon.ApplyEquipmentCompareSystem = ApplyEquipmentCompareSystem
addon.RestoreEquipmentCompareSystem = RestoreEquipmentCompareSystem
addon.RefreshEquipmentCompareSystem = RefreshEquipmentCompareSystem
