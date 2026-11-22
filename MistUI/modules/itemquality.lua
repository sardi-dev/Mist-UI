-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)

-- ============================================================================
-- ITEM QUALITY BORDERS MODULE FOR MISTUI
-- Adds quality-colored glow borders to item slots across all inventory frames:
--   Character Panel, Inspect Frame, Bags, Bank, Merchant, Guild Bank
--
-- Special thanks to haste (https://github.com/haste) for oGlow, whose clean
-- implementation served as reference for the bank and guild bank systems.
-- ============================================================================

-- Module state tracking
local ItemQualityModule = {
    initialized = false,
    applied = false,
    hooks = {},
    overlays = {} -- Track all created overlays for cleanup
}

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("itemquality", ItemQualityModule,
        addon.L["Item Quality"],
        addon.L["Color item borders by quality in bags, character panel, bank, and merchant"])
end

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon:GetModuleConfig("itemquality")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("itemquality")
end

-- ============================================================================
-- QUALITY COLORS
-- ============================================================================

-- Glow strength per quality; the colours come from the client's ITEM_QUALITY_COLORS so
-- they match item names everywhere (heirlooms are light blue on 5.4.8, not gold).
local QUALITY_ALPHA = {
    [0] = 0.5, -- Poor
    [1] = 0.5, -- Common
    [2] = 0.8, -- Uncommon
    [3] = 0.8, -- Rare
    [4] = 0.8, -- Epic
    [5] = 0.9, -- Legendary
    [6] = 0.9, -- Artifact
    [7] = 0.9, -- Heirloom
}

-- ============================================================================
-- OVERLAY CREATION
-- ============================================================================

-- Create or get the quality border overlay for any item frame
local function GetOrCreateOverlay(frame)
    if not frame then return nil end
    if frame.__MistUI_QualityOverlay then
        return frame.__MistUI_QualityOverlay
    end

    -- Use the stock glow border texture in ADD blend mode
    local overlay = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    overlay:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    overlay:SetBlendMode("ADD")
    overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
    -- 62/36 is the stock action-button fit, where the ring lands inside the icon; 70/37 puts it on the slot edge.
    local w, h = frame:GetWidth(), frame:GetHeight()
    if (not w or w == 0) then w = 37 end
    if (not h or h == 0) then h = 37 end
    overlay:SetWidth(w * 70 / 37)
    overlay:SetHeight(h * 70 / 37)
    overlay:Hide()

    frame.__MistUI_QualityOverlay = overlay
    ItemQualityModule.overlays[frame] = overlay
    return overlay
end

-- Apply quality color to overlay, or hide if below min threshold
local function SetOverlayQuality(frame, quality)
    local overlay = GetOrCreateOverlay(frame)
    if not overlay then return end

    local config = GetModuleConfig()
    local minQuality = config and config.min_quality or 2

    local color = quality and ITEM_QUALITY_COLORS[quality]
    if color and quality >= minQuality and QUALITY_ALPHA[quality] then
        overlay:SetVertexColor(color.r, color.g, color.b, QUALITY_ALPHA[quality])
        overlay:Show()
    else
        overlay:Hide()
    end
end

-- ============================================================================
-- ITEM LINK QUALITY PARSING (shared lookup)
-- ============================================================================

-- Map the item link color hex codes the client uses to the quality index
local COLOR_TO_QUALITY = {
    ["ff9d9d9d"] = 0, -- Poor
    ["ffffffff"] = 1, -- Common
    ["ff1eff00"] = 2, -- Uncommon
    ["ff0070dd"] = 3, -- Rare
    ["ffa335ee"] = 4, -- Epic
    ["ffff8000"] = 5, -- Legendary
    ["ffe6cc80"] = 6, -- Artifact
    ["ff00ccff"] = 7, -- Heirloom
}

-- Extract quality from an item link.
-- Tries GetItemInfo first; falls back to parsing the embedded color hex so
-- uncached items (first open of bank, etc.) still get colored correctly.
local function GetQualityFromLink(link)
    if not link then return nil end
    local _, _, quality = GetItemInfo(link)
    if not quality then
        local _, _, colorHex = string.find(link, "|c(%x+)|")
        if colorHex then
            quality = COLOR_TO_QUALITY[colorHex:lower()]
        end
    end
    return quality
end

-- ============================================================================
-- CHARACTER PANEL (equipped items)
-- ============================================================================

-- 5.4.8 has no ammo or ranged slot: bows and guns sit in the main hand.
local EQUIP_SLOT_FRAMES = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterShirtSlot",
    "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterBackSlot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterTabardSlot",
}

-- Bag equipment slot IDs (20-23) - these live on the bag-bar and should NOT get
-- quality overlays.  Only character-panel gear slots should be decorated.
local BAG_EQUIP_SLOT_IDS = { [20] = true, [21] = true, [22] = true, [23] = true }

local function UpdateCharacterSlot(button)
    if not button then return end
    if not IsModuleEnabled() then return end

    local slotID = button:GetID()
    if not slotID or slotID < 0 then return end

    -- Skip bag equipment slots - they sit on the bag-bar, not the character panel
    if BAG_EQUIP_SLOT_IDS[slotID] then return end

    local hasItem = GetInventoryItemTexture("player", slotID)
    if hasItem then
        local quality = GetInventoryItemQuality("player", slotID)
        SetOverlayQuality(button, quality)
    else
        SetOverlayQuality(button, nil)
    end
end

local function UpdateAllCharacterSlots()
    if not IsModuleEnabled() then return end

    for _, frameName in ipairs(EQUIP_SLOT_FRAMES) do
        local button = _G[frameName]
        if button then
            UpdateCharacterSlot(button)
        end
    end
end

-- ============================================================================
-- INSPECT FRAME (inspected player's equipped items)
-- ============================================================================

local INSPECT_SLOTS = {
    "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot", "InspectShirtSlot",
    "InspectChestSlot", "InspectWaistSlot", "InspectLegsSlot", "InspectFeetSlot",
    "InspectWristSlot", "InspectHandsSlot", "InspectFinger0Slot", "InspectFinger1Slot",
    "InspectTrinket0Slot", "InspectTrinket1Slot", "InspectBackSlot",
    "InspectMainHandSlot", "InspectSecondaryHandSlot", "InspectTabardSlot",
}

local function UpdateInspectSlot(button)
    if not button then return end
    if not IsModuleEnabled() then return end
    if not InspectFrame or not InspectFrame.unit then return end

    local slotID = button:GetID()
    if not slotID then return end
    if slotID >= 20 and slotID <= 23 then return end

    local unit = InspectFrame.unit
    local hasItem = addon:IsInspectDataFor(unit) and GetInventoryItemTexture(unit, slotID)
    if hasItem then
        local quality = GetInventoryItemQuality(unit, slotID)
        if not quality then
            local link = GetInventoryItemLink(unit, slotID)
            quality = GetQualityFromLink(link)
        end
        SetOverlayQuality(button, quality)
    else
        SetOverlayQuality(button, nil)
    end
end

local function UpdateAllInspectSlots()
    if not IsModuleEnabled() then return end
    if not InspectFrame or not InspectFrame:IsShown() then return end
    for _, slotName in ipairs(INSPECT_SLOTS) do
        local button = _G[slotName]
        if button then
            UpdateInspectSlot(button)
        end
    end
end

-- ============================================================================
-- BAGS (container frames)
-- ============================================================================

local function GetBagItemQuality(bag, slot)
    return GetQualityFromLink(GetContainerItemLink(bag, slot))
end

local function UpdateBagSlot(frame, bag, slot)
    if not frame or not IsModuleEnabled() then return end
    local quality = GetBagItemQuality(bag, slot)
    SetOverlayQuality(frame, quality)
end

local function UpdateContainerFrame(frame)
    if not frame or not IsModuleEnabled() then return end

    local bag = frame:GetID()
    local frameName = frame:GetName()
    for btnIdx = 1, GetContainerNumSlots(bag) do
        local itemButton = _G[frameName .. "Item" .. btnIdx]
        if itemButton then
            -- Use the button's actual slot ID, NOT the loop index: bag items are
            -- displayed in reverse order, so ContainerFrame1Item1 may be slot 16.
            UpdateBagSlot(itemButton, bag, itemButton:GetID())
        end
    end
end

local function UpdateAllBags()
    if not IsModuleEnabled() then return end

    -- Covers the backpack, the equipped bags and the bank bags (ids 5-11): all of them
    -- are ContainerFrames.
    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame" .. i]
        if containerFrame and containerFrame:IsShown() then
            UpdateContainerFrame(containerFrame)
        end
    end
end

-- ============================================================================
-- BANK (personal bank slots + bank bag containers)
-- ============================================================================

local function UpdateBankSlots()
    if not IsModuleEnabled() then return end
    if not BankFrame or not BankFrame:IsShown() then return end

    -- Bank slots use sequential IDs 1..28 matching BankFrameItem1..28
    for i = 1, NUM_BANKGENERIC_SLOTS do
        local button = _G["BankFrameItem" .. i]
        if button then
            local link = GetContainerItemLink(BANK_CONTAINER, i)
            SetOverlayQuality(button, GetQualityFromLink(link))
        end
    end

    UpdateAllBags()
end

-- ============================================================================
-- MERCHANT FRAME
-- ============================================================================

local MERCHANT_ITEMS_PER_PAGE = MERCHANT_ITEMS_PER_PAGE or 10
local BUYBACK_ITEMS_PER_PAGE = BUYBACK_ITEMS_PER_PAGE or 12

local function UpdateMerchantItems()
    if not IsModuleEnabled() then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    -- Same index math as FrameXML MerchantFrame_UpdateMerchantInfo
    local page = MerchantFrame.page or 1
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then
            local index = ((page - 1) * MERCHANT_ITEMS_PER_PAGE) + i
            SetOverlayQuality(button, GetQualityFromLink(GetMerchantItemLink(index)))
        end
    end

    local buybackButton = _G["MerchantBuyBackItemItemButton"]
    if buybackButton then
        local lastSold = GetNumBuybackItems()
        SetOverlayQuality(buybackButton, lastSold > 0 and GetQualityFromLink(GetBuybackItemLink(lastSold)) or nil)
    end
end

local function UpdateBuybackItems()
    if not IsModuleEnabled() then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    for i = 1, BUYBACK_ITEMS_PER_PAGE do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then
            SetOverlayQuality(button, GetQualityFromLink(GetBuybackItemLink(i)))
        end
    end
end

-- ============================================================================
-- GUILD BANK
-- ============================================================================

local function UpdateGuildBankSlots()
    if not IsModuleEnabled() then return end
    -- Blizzard_GuildBankUI is a load-on-demand addon; bail if not loaded yet
    if not IsAddOnLoaded("Blizzard_GuildBankUI") then return end
    if not GuildBankFrame or not GuildBankFrame:IsShown() then return end

    local tab = GetCurrentGuildBankTab()
    -- Each tab has 98 slots arranged in 7 columns of 14 rows
    for i = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
        -- Derive row (1-14) and column (1-7) from the linear slot index
        local index = math.fmod(i, 14)
        if index == 0 then index = 14 end
        local column = math.ceil((i - 0.5) / 14)

        local button = _G["GuildBankColumn" .. column .. "Button" .. index]
        if button then
            local link = GetGuildBankItemLink(tab, i)
            SetOverlayQuality(button, GetQualityFromLink(link))
        end
    end
end

-- ============================================================================
-- REFRESH ALL
-- ============================================================================

local function UpdateAllQualityBorders()
    if not IsModuleEnabled() then return end
    UpdateAllCharacterSlots()
    UpdateAllBags()
    UpdateBankSlots()
    if MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 2 then
        UpdateBuybackItems()
    else
        UpdateMerchantItems()
    end
    UpdateGuildBankSlots()
end

-- ============================================================================
-- APPLY / RESTORE SYSTEM
-- ============================================================================

local function InstallInspectHook()
    if ItemQualityModule.hooks["Inspect"] then return end
    if not InspectPaperDollItemSlotButton_Update then return end
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        if not IsModuleEnabled() then return end
        UpdateInspectSlot(button)
    end)

    ItemQualityModule.hooks["Inspect"] = true
end

local function ApplyItemQualitySystem()
    if ItemQualityModule.applied then return end

    -- Character Panel: hook PaperDollItemSlotButton_Update
    if not ItemQualityModule.hooks["PaperDoll"] and PaperDollItemSlotButton_Update then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
            if not IsModuleEnabled() then return end
            UpdateCharacterSlot(button)
        end)
        ItemQualityModule.hooks["PaperDoll"] = true
    end

    -- Inspect Frame: installed via InstallInspectHook() when Blizzard_InspectUI loads
    InstallInspectHook()

    -- Bags: hook ContainerFrame_Update
    -- The stock update also runs when a bag opens, so no open/toggle hooks are needed
    if not ItemQualityModule.hooks["ContainerFrame"] and ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", UpdateContainerFrame)
        ItemQualityModule.hooks["ContainerFrame"] = true
    end

    -- Merchant: hook MerchantFrame_UpdateMerchantInfo
    if not ItemQualityModule.hooks["Merchant"] and MerchantFrame_UpdateMerchantInfo then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
            if not IsModuleEnabled() then return end
            UpdateMerchantItems()
        end)
        ItemQualityModule.hooks["Merchant"] = true
    end

    -- Merchant Buyback tab (slots use GetBuybackItemLink, not merchant indices)
    if not ItemQualityModule.hooks["MerchantBuyback"] and MerchantFrame_UpdateBuybackInfo then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function()
            if not IsModuleEnabled() then return end
            UpdateBuybackItems()
        end)
        ItemQualityModule.hooks["MerchantBuyback"] = true
    end

    -- Bank: hook BankFrameItemButton_Update for per-slot real-time updates.
    if not ItemQualityModule.hooks["BankFrame"] and BankFrameItemButton_Update then
        hooksecurefunc("BankFrameItemButton_Update", function(button)
            if not IsModuleEnabled() then return end
            if not BankFrame or not BankFrame:IsShown() then return end
            -- The bag slots along the bottom run through this function too, and their ids
            -- (1-7) would otherwise be read as bank item slots.
            if button.isBag then return end
            SetOverlayQuality(button, GetQualityFromLink(GetContainerItemLink(BANK_CONTAINER, button:GetID())))
        end)
        ItemQualityModule.hooks["BankFrame"] = true
    end

    -- Guild Bank: hook is installed dynamically on GUILDBANKFRAME_OPENED
    -- because Blizzard_GuildBankUI is load-on-demand (not available at startup)

    -- Initial update
    addon:After(0.5, UpdateAllQualityBorders)

    ItemQualityModule.applied = true
    ItemQualityModule.initialized = true
end

local function RestoreItemQualitySystem()
    if not ItemQualityModule.applied then return end

    -- Hide all tracked quality overlays
    for frame, overlay in pairs(ItemQualityModule.overlays) do
        if overlay then overlay:Hide() end
    end

    ItemQualityModule.applied = false
end

-- ============================================================================
-- PROFILE CHANGE HANDLER
-- ============================================================================

local function OnProfileChanged()
    if IsModuleEnabled() then
        RestoreItemQualitySystem()
        ItemQualityModule.applied = false
        ApplyItemQualitySystem()
    else
        if addon:ShouldDeferModuleDisable("itemquality", ItemQualityModule) then
            return
        end
        RestoreItemQualitySystem()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Bank slot events arrive in bursts; one repaint per burst is enough.
local pendingUpdates = {}

local function Debounce(key, delay, callback)
    if pendingUpdates[key] then return end
    pendingUpdates[key] = true
    addon:After(delay, function()
        pendingUpdates[key] = nil
        callback()
    end)
end

local BANK_REPAINT_DELAY = 0.2
-- Some servers send the bank slots after the bank window has opened.
local BANK_LATE_REPAINT_DELAYS = { 0.5, 1.5 }

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_UPDATE")
eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
eventFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")

-- Borders clear the moment a new player is requested and repaint once their reply lands
addon:RegisterInspectDataCallback(function(ownerGUID)
    if not IsModuleEnabled() then return end
    if ownerGUID then
        InstallInspectHook()
        addon:After(0.1, UpdateAllInspectSlots)
    else
        UpdateAllInspectSlots()
    end
end)

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
        if not IsModuleEnabled() then return end
        InstallInspectHook()

    elseif event == "ADDON_LOADED" and arg1 == "MistUI" then
        -- Registered even while the module is off: a profile switch can turn it on
        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(ItemQualityModule, "OnProfileChanged", OnProfileChanged)
                addon.db.RegisterCallback(ItemQualityModule, "OnProfileCopied", OnProfileChanged)
                addon.db.RegisterCallback(ItemQualityModule, "OnProfileReset", OnProfileChanged)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        addon:After(1.0, function()
            ApplyItemQualitySystem()
        end)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if not IsModuleEnabled() then return end
        addon:After(0.2, UpdateAllCharacterSlots)

    elseif event == "BAG_UPDATE" then
        if not IsModuleEnabled() then return end
        -- One BAG_UPDATE per changed bag; without this a sweep is scheduled per event.
        if ItemQualityModule.bagSweepPending then return end
        ItemQualityModule.bagSweepPending = true
        addon:After(0.2, function()
            ItemQualityModule.bagSweepPending = false
            UpdateAllBags()
        end)

    elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if not IsModuleEnabled() then return end
        Debounce("bank", BANK_REPAINT_DELAY, UpdateBankSlots)
        if event == "BANKFRAME_OPENED" then
            for index, delay in ipairs(BANK_LATE_REPAINT_DELAYS) do
                Debounce("bankLate" .. index, delay, UpdateBankSlots)
            end
        end

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if not IsModuleEnabled() then return end
        if InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and arg1 == InspectFrame.unit then
            addon:After(0.2, UpdateAllInspectSlots)
        end

    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if not IsModuleEnabled() then return end
        addon:After(0.2, function()
            if MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 2 then
                UpdateBuybackItems()
            else
                UpdateMerchantItems()
            end
        end)

    elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANKBAGSLOTS_CHANGED" then
        if not IsModuleEnabled() then return end
        -- Install GuildBankFrame_Update hook on first open (load-on-demand addon)
        if not ItemQualityModule.hooks["GuildBank"] and GuildBankFrame_Update then
            hooksecurefunc("GuildBankFrame_Update", function()
                if not IsModuleEnabled() then return end
                UpdateGuildBankSlots()
            end)
            ItemQualityModule.hooks["GuildBank"] = true
        end
        UpdateGuildBankSlots()
    end
end)

-- Export for external use
addon.ApplyItemQualitySystem = ApplyItemQualitySystem
addon.RestoreItemQualitySystem = RestoreItemQualitySystem
addon.UpdateAllQualityBorders = UpdateAllQualityBorders
