-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local L = addon.L

local function T(key, fallback)
    return (L and L[key]) or fallback or key
end

-- ============================================================================
-- BAG SORT MODULE FOR MISTUI
-- Sorts items in bags and bank by type, rarity, level, name.
-- Adds sort buttons to the Bagster frames and to the stock bag/bank frames.
-- ============================================================================

-- Module state tracking
local BagSortModule = {
    initialized = false,
    applied = false,
    originalStates = {},
    registeredEvents = {},
    hooks = {},
    frames = {}
}

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("bagsort", BagSortModule,
        T("Bag Sort", "Bag Sort"),
        T("Sort bags and bank items with buttons", "Sort bags and bank items with buttons"),
        { lifecyclePrefix = "BagSort" })
end

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon:GetModuleConfig("bagsort")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("bagsort")
end

local function IsBankFillFromBagsEnabled()
    local cfg = GetModuleConfig()
    if not cfg or cfg.bank_fill_from_bags == nil then
        return true
    end
    return cfg.bank_fill_from_bags
end

local function IsBagsterEnabled()
    return addon:IsModuleEnabled("bagster")
end

-- True only during an active guild bank sort; doesn't affect bag/bank sorting.
local guildBankSortActive = false
local GUILDBANK_MOVE_THROTTLE = 0.4
-- A whole round of disjoint moves in one frame trips server packet-flood kicks on big bank sorts.
local MAX_MOVES_PER_TICK = 3
-- A move the server neither finishes nor rejects visibly (a slot that stays locked) ends the sort after this.
local MOVE_TIMEOUT = 5

local function GetSortMoveInterval()
    local cfg = GetModuleConfig()
    local interval = cfg and tonumber(cfg.move_interval) or 0.1
    if guildBankSortActive and interval < GUILDBANK_MOVE_THROTTLE then
        interval = GUILDBANK_MOVE_THROTTLE
    end
    if interval < 0.05 then return 0.05 end
    if interval > 0.5 then return 0.5 end
    return interval
end

local DEFAULT_LOCK_HOTKEY = "ALT_LEFT"
local LOCK_HOTKEY_MAP = {
    ALT_LEFT = { modifier = "ALT", button = "LeftButton" },
    CTRL_LEFT = { modifier = "CTRL", button = "LeftButton" },
    SHIFT_LEFT = { modifier = "SHIFT", button = "LeftButton" },
    ALT_RIGHT = { modifier = "ALT", button = "RightButton" },
    CTRL_RIGHT = { modifier = "CTRL", button = "RightButton" },
    SHIFT_RIGHT = { modifier = "SHIFT", button = "RightButton" },
    ALT_MIDDLE = { modifier = "ALT", button = "MiddleButton" },
    CTRL_MIDDLE = { modifier = "CTRL", button = "MiddleButton" },
    SHIFT_MIDDLE = { modifier = "SHIFT", button = "MiddleButton" },
}

local function NormalizeLockHotkey(value)
    if type(value) ~= "string" then
        return DEFAULT_LOCK_HOTKEY
    end

    local normalized = string.upper(value)
    if LOCK_HOTKEY_MAP[normalized] then
        return normalized
    end

    return DEFAULT_LOCK_HOTKEY
end

local function GetConfiguredLockHotkey()
    local cfg = GetModuleConfig()
    local hotkey = NormalizeLockHotkey(cfg and cfg.lock_hotkey)
    if cfg and cfg.lock_hotkey ~= hotkey then
        cfg.lock_hotkey = hotkey
    end
    return hotkey
end

local function GetLocalizedModifierName(modifier)
    if modifier == "ALT" then
        return T("Alt", "Alt")
    elseif modifier == "CTRL" then
        return T("Ctrl", "Ctrl")
    end
    return T("Shift", "Shift")
end

local function GetLocalizedMouseButtonName(button)
    if button == "LeftButton" then
        return T("Left Click", "Left Click")
    elseif button == "RightButton" then
        return T("Right Click", "Right Click")
    end
    return T("Middle Click", "Middle Click")
end

local function GetLockHotkeyLabel()
    local hotkey = GetConfiguredLockHotkey()
    local bindData = LOCK_HOTKEY_MAP[hotkey] or LOCK_HOTKEY_MAP[DEFAULT_LOCK_HOTKEY]
    return string.format("%s + %s", GetLocalizedModifierName(bindData.modifier), GetLocalizedMouseButtonName(bindData.button))
end

local function IsLockHotkeyPressed(mouseButton)
    local hotkey = GetConfiguredLockHotkey()
    local bindData = LOCK_HOTKEY_MAP[hotkey] or LOCK_HOTKEY_MAP[DEFAULT_LOCK_HOTKEY]
    if mouseButton ~= bindData.button then
        return false
    end

    local altDown = IsAltKeyDown()
    local ctrlDown = IsControlKeyDown()
    local shiftDown = IsShiftKeyDown()

    if bindData.modifier == "ALT" then
        return altDown and not ctrlDown and not shiftDown
    elseif bindData.modifier == "CTRL" then
        return ctrlDown and not altDown and not shiftDown
    end

    return shiftDown and not altDown and not ctrlDown
end

-- Bag, bank and guild-tab sorts share this flag, the move plan and the tick driver: one sort at a time.
local running = false
local plannedMoves = {}
local nextMoveIndex = 1
local awaitedDrop
local waitingSince
local tickAccumulator = 0

-- Sort buttons show "moves done/planned" while a sort runs.
local sortButtons = {}

local function AttachSortProgress(btn)
    local text = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
    btn.progressText = text
    sortButtons[#sortButtons + 1] = btn
    return btn
end

local function SetSortProgress(text)
    for _, btn in ipairs(sortButtons) do
        btn.progressText:SetText(text or "")
    end
end

local bank_open = false
local guild_bank_open = false
local bankSortActive = false
local guildBankTabHookInstalled = false
local clickHooksInstalled = false
local hookedSlotButtons = {}
local lockVisualFrame

-- Forward declarations
local StopSorting
local UpdateButtonVisibility

local function ItemIDFromLink(link)
    local digits = link and string.match(link, "item:(%d+)")
    return digits and tonumber(digits)
end

local function GetLockedSlotsTable()
    local cfg = GetModuleConfig()
    if not cfg then return nil end
    if type(cfg.lockedSlots) ~= "table" then
        cfg.lockedSlots = {}
    end
    return cfg.lockedSlots
end

local function MakeSlotKey(bag, slot)
    return tostring(bag) .. ":" .. tostring(slot)
end

local function IsSlotLocked(bag, slot)
    local locks = GetLockedSlotsTable()
    if not locks then return false end
    return locks[MakeSlotKey(bag, slot)] == true
end

local function SetSlotLocked(bag, slot, locked)
    local locks = GetLockedSlotsTable()
    if not locks then return false end
    local key = MakeSlotKey(bag, slot)
    if locked then
        locks[key] = true
    else
        locks[key] = nil
    end
    return true
end

local GetBagSlotFromButton

-- Lock icon texture, sized 12x12 and anchored to the slot's top-right corner.
local LOCK_MARKER_TEXTURE = "Interface\\AddOns\\MistUI\\Textures\\UI\\BagSortLock"
local LOCK_MARKER_SIZE = 12
local LOCK_MARKER_OFFSET_X = -1
local LOCK_MARKER_OFFSET_Y = -1
local DEFAULT_LOCK_MARKER_COLOR = { 0.15, 0.80, 1.00, 0.95 }

-- Icon art is plain white so it can be tinted (Bags > Bag Sort > Lock Icon Color).
local function GetLockMarkerColor()
    local cfg = GetModuleConfig()
    local c = cfg and cfg.lock_color
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c[1], c[2], c[3], type(c[4]) == "number" and c[4] or 1
    end
    return DEFAULT_LOCK_MARKER_COLOR[1], DEFAULT_LOCK_MARKER_COLOR[2], DEFAULT_LOCK_MARKER_COLOR[3], DEFAULT_LOCK_MARKER_COLOR[4]
end

local function EnsureLockMarker(button)
    if not button or button._mistUISortLockMarker then return end
    -- No CreateTexture sub-level param on this client; last-created wins draw order.
    local marker = button:CreateTexture(nil, "OVERLAY")
    marker:SetTexture(LOCK_MARKER_TEXTURE)
    marker:SetSize(LOCK_MARKER_SIZE, LOCK_MARKER_SIZE)
    marker:ClearAllPoints()
    -- Top-right corner keeps it clear of the stack-count text (bottom-right).
    marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", LOCK_MARKER_OFFSET_X, LOCK_MARKER_OFFSET_Y)
    marker:Hide()
    button._mistUISortLockMarker = marker
end

local function UpdateButtonLockMarker(button)
    if not button then return end
    EnsureLockMarker(button)

    local marker = button._mistUISortLockMarker
    if not marker then return end

    local bag, slot = GetBagSlotFromButton(button)
    -- The lock list outlives the module, but a disabled module must not draw its padlocks.
    if BagSortModule.applied and bag and slot and IsSlotLocked(bag, slot) then
        marker:SetVertexColor(GetLockMarkerColor())
        marker:Show()
    else
        marker:Hide()
    end
end

local function RefreshAllLockMarkers()
    for button, _ in pairs(hookedSlotButtons) do
        UpdateButtonLockMarker(button)
    end
end

local function HasLockedSlots()
    local locks = GetLockedSlotsTable()
    return locks ~= nil and next(locks) ~= nil
end

local BAGSTER_FRAME_COUNT = 3

-- Markers only render on visible slot buttons, and each button re-syncs its own marker on OnShow.
local function IsAnyBagUIVisible()
    if BankFrame and BankFrame:IsShown() then
        return true
    end
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            return true
        end
    end
    for i = 1, BAGSTER_FRAME_COUNT do
        local frame = _G["MistUI_BagsterFrame" .. i]
        if frame and frame:IsShown() then
            return true
        end
    end
    return false
end

local function ToggleSlotLockByBagSlot(bag, slot)
    local newState = not IsSlotLocked(bag, slot)
    SetSlotLocked(bag, slot, newState)
    if newState then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00cc66MistUI:|r " .. T("Slot locked (bag %d, slot %d).", "Slot locked (bag %d, slot %d)."), bag, slot), 0.4, 1, 0.4)
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00cc66MistUI:|r " .. T("Slot unlocked (bag %d, slot %d).", "Slot unlocked (bag %d, slot %d)."), bag, slot), 0.4, 1, 0.4)
    end

    RefreshAllLockMarkers()
end

-- Bagster item buttons expose GetBag; stock bank and container buttons are told apart by name and parent id.
GetBagSlotFromButton = function(btn)
    if not btn then return nil, nil end

    local bag, slot
    if btn.GetBag then
        bag = btn:GetBag()
        slot = btn:GetID()
    else
        -- Must come before the parent-frame path: BankFrame:GetID() returns 0, which would file
        -- a bank slot under the backpack.
        local bankSlot = tonumber(string.match(btn:GetName() or "", "^BankFrameItem(%d+)$"))
        local parent = btn:GetParent()
        if bankSlot then
            bag = BANK_CONTAINER
            slot = bankSlot
        elseif parent and string.match(parent:GetName() or "", "^ContainerFrame%d+$") then
            bag = parent:GetID()
            slot = btn:GetID()
        end
    end

    bag = tonumber(bag)
    slot = tonumber(slot)
    if bag == nil or slot == nil or slot < 1 then return nil, nil end
    return bag, slot
end

local function GetHoveredBagSlot()
    if not GameTooltip:IsShown() then return nil, nil end
    return GetBagSlotFromButton(GameTooltip:GetOwner())
end

local function ToggleHoveredSlotLock()
    local bag, slot = GetHoveredBagSlot()
    if not bag or not slot then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66MistUI:|r " .. T("Hover an item or slot, then type /sortlock.", "Hover an item or slot, then type /sortlock."), 1, 0.8, 0)
        return
    end

    ToggleSlotLockByBagSlot(bag, slot)
end

local function InstallAltClickHooks()
    if clickHooksInstalled then return end
    clickHooksInstalled = true

    local function HookSlotButton(button)
        if not button or button._mistUISortLockHooked then return end

        local objectType = button:GetObjectType()
        if objectType ~= "Button" and objectType ~= "CheckButton" then
            return
        end

        button._mistUISortLockHooked = true
        hookedSlotButtons[button] = true
        EnsureLockMarker(button)

        button:HookScript("OnShow", function(self)
            UpdateButtonLockMarker(self)
        end)

        button:HookScript("OnHide", function(self)
            if self._mistUISortLockMarker then
                self._mistUISortLockMarker:Hide()
            end
        end)

        local function HandleAltClick(self, mouseButton)
            if not BagSortModule.applied then return end
            if not IsLockHotkeyPressed(mouseButton) then return end
            local now = GetTime()
            if self._mistUISortLockLastClick and (now - self._mistUISortLockLastClick) < 0.15 then
                return
            end
            self._mistUISortLockLastClick = now

            local bag, slot = GetBagSlotFromButton(self)
            if not bag or not slot then return end

            ToggleSlotLockByBagSlot(bag, slot)

            -- Cancel pickup side effect from default click handlers.
            if CursorHasItem() then
                PickupContainerItem(bag, slot)
                if CursorHasItem() then
                    ClearCursor()
                end
            end
        end

        button:HookScript("OnClick", HandleAltClick)
        button:HookScript("PostClick", HandleAltClick)
        button:HookScript("OnMouseUp", HandleAltClick)

        UpdateButtonLockMarker(button)
    end

    local function HookKnownSlotButtons()
        -- Stock container bag items
        for frameIndex = 1, NUM_CONTAINER_FRAMES do
            for slot = 1, 36 do
                local btn = _G["ContainerFrame" .. frameIndex .. "Item" .. slot]
                if btn then HookSlotButton(btn) end
            end
        end

        -- Stock bank main container slots
        for slot = 1, NUM_BANKGENERIC_SLOTS do
            local btn = _G["BankFrameItem" .. slot]
            if btn then HookSlotButton(btn) end
        end

        -- Bagster item slots
        for idx = 1, 400 do
            local btn = _G["MistUI_BagsterItem" .. idx]
            if btn then HookSlotButton(btn) end
        end
    end

    -- Stock slot buttons exist from the start; bag window slots are made on demand and announce themselves.
    HookKnownSlotButtons()
    addon.OnBagsterItemCreated = HookSlotButton
    RefreshAllLockMarkers()

    lockVisualFrame = CreateFrame("Frame")
    local elapsed = 0
    lockVisualFrame:SetScript("OnUpdate", function(self, dt)
        if not BagSortModule.applied then return end
        elapsed = elapsed + dt
        if elapsed < 0.4 then return end
        elapsed = 0
        -- Closed bags show no marker; a slot that changed items re-reads its lock here.
        if not IsAnyBagUIVisible() then return end
        if HasLockedSlots() then
            RefreshAllLockMarkers()
        end
    end)
end

local function ClearAllLockedSlots()
    local locks = GetLockedSlotsTable()
    if not locks then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66MistUI:|r " .. T("Could not clear locks (config not ready).", "Could not clear locks (config not ready)."), 1, 0.4, 0.4)
        return
    end
    wipe(locks)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66MistUI:|r " .. T("Cleared all sort-locked slots.", "Cleared all sort-locked slots."), 0.4, 1, 0.4)
    RefreshAllLockMarkers()
end



-- ============================================================================
-- GUILD BANK COMPATIBILITY: SYNTHETIC BAG IDS
-- ============================================================================
-- Guild bank tab N is treated as bag id (GUILDBANK_TAB_OFFSET + N), reusing
-- the whole scan/compress/sort/move pipeline instead of duplicating it.
local GUILDBANK_TAB_OFFSET = 50

local function IsGuildBankBag(bag)
    return bag > GUILDBANK_TAB_OFFSET
end

-- Returns 0 for tabs without full view+deposit+withdraw access.
local function GetGuildBankTabSlotCount(tab)
    local name, _, canView, canDeposit, numWithdrawals = GetGuildBankTabInfo(tab)
    -- numWithdrawals is negative when withdrawals are unlimited for this rank.
    if name and canView and canDeposit and numWithdrawals ~= 0 then
        return MAX_GUILDBANK_SLOTS_PER_TAB
    end
    return 0
end

local function BagGetItemLink(bag, slot)
    if IsGuildBankBag(bag) then
        return GetGuildBankItemLink(bag - GUILDBANK_TAB_OFFSET, slot)
    end
    return GetContainerItemLink(bag, slot)
end

local function BagGetItemInfo(bag, slot)
    if IsGuildBankBag(bag) then
        return GetGuildBankItemInfo(bag - GUILDBANK_TAB_OFFSET, slot)
    end
    return GetContainerItemInfo(bag, slot)
end

local function BagPickupItem(bag, slot)
    if IsGuildBankBag(bag) then
        return PickupGuildBankItem(bag - GUILDBANK_TAB_OFFSET, slot)
    end
    return PickupContainerItem(bag, slot)
end

local function BagSplitItem(bag, slot, amount)
    if IsGuildBankBag(bag) then
        return SplitGuildBankItem(bag - GUILDBANK_TAB_OFFSET, slot, amount)
    end
    return SplitContainerItem(bag, slot, amount)
end

-- Pairs of inclusive (first, last) bag id spans, flattened in the order given.
local function ListBags(...)
    local bags = {}
    for i = 1, select("#", ...), 2 do
        local first, last = select(i, ...)
        for bag = first, last do
            bags[#bags + 1] = bag
        end
    end
    return bags
end

local LAST_BANK_BAG = NUM_BAG_SLOTS + NUM_BANKBAGSLOTS
local carriedBags = ListBags(BACKPACK_CONTAINER, NUM_BAG_SLOTS)
local bankPoolBags = ListBags(BANK_CONTAINER, BANK_CONTAINER, NUM_BAG_SLOTS + 1, LAST_BANK_BAG)
local personalBags = ListBags(BANK_CONTAINER, LAST_BANK_BAG)

local UNRANKED = 99

local classRankByName, subclassRankByClass, weaponClassName, armorClassName

-- A repeated name ends up with its last position.
local function PositionsByName(...)
    local positions = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil then
            positions[value] = index
        end
    end
    return positions
end

local function LoadAuctionRanks()
    if classRankByName then return end
    classRankByName = PositionsByName(GetAuctionItemClasses())
    subclassRankByClass = {}
    for _, rank in pairs(classRankByName) do
        subclassRankByClass[rank] = PositionsByName(GetAuctionItemSubClasses(rank))
    end
    weaponClassName, armorClassName = GetAuctionItemClasses()
end

-- Only the relative order matters; unlisted equip locations rank below all of these.
local gearRankByEquipLoc = {}
for rank, group in ipairs({
    "HEAD", "NECK", "SHOULDER", "BODY", "CHEST ROBE", "WAIST", "LEGS", "FEET", "WRIST", "HAND",
    "FINGER", "TRINKET", "CLOAK", "WEAPON", "SHIELD", "2HWEAPON", "WEAPONMAINHAND", "WEAPONOFFHAND",
    "HOLDABLE", "RANGED", "THROWN", "RANGEDRIGHT", "TABARD",
}) do
    for suffix in string.gmatch(group, "%S+") do
        gearRankByEquipLoc["INVTYPE_" .. suffix] = rank
    end
end

local itemFacts = {}
local slotGrid = {}

local function LearnItem(itemID)
    local facts = itemFacts[itemID]
    if facts then return facts end
    LoadAuctionRanks()
    local name, _, quality, level, _, class, subclass, stack, equipLoc = GetItemInfo(itemID)
    facts = {
        name = name or "",
        quality = quality or 0,
        level = level or 0,
        class = class or "",
        subclass = subclass or "",
        stack = stack or 1,
        equipLoc = equipLoc or "",
    }
    local classRank = classRankByName[facts.class] or UNRANKED
    local siblings = subclassRankByClass[classRank]
    facts.classRank = classRank
    facts.subclassRank = siblings and siblings[facts.subclass] or UNRANKED
    facts.isGear = facts.class == weaponClassName or facts.class == armorClassName
    facts.gearRank = gearRankByEquipLoc[facts.equipLoc] or 0
    itemFacts[itemID] = facts
    return facts
end

local function BagSlotCount(bag)
    if IsGuildBankBag(bag) then
        return GetGuildBankTabSlotCount(bag - GUILDBANK_TAB_OFFSET)
    end
    return GetContainerNumSlots(bag) or 0
end

-- Sort locks are read here only; a lock toggled mid-sort applies to the next sort.
-- Returns false when an item's details are not loaded yet: its stack size would be a guess.
local function CaptureBags(bags)
    wipe(slotGrid)
    wipe(itemFacts)
    local complete = true
    for _, bag in ipairs(bags) do
        local column = {}
        for slot = 1, BagSlotCount(bag) do
            local cell = { bag = bag, slot = slot, pinned = IsSlotLocked(bag, slot) }
            local link = BagGetItemLink(bag, slot)
            local itemID = ItemIDFromLink(link)
            if link and not itemID then
                -- A caged battle pet has no item id to plan with; leave its slot alone.
                cell.pinned = true
            elseif itemID then
                local _, count = BagGetItemInfo(bag, slot)
                cell.item = itemID
                cell.qty = count or 0
                local facts = LearnItem(itemID)
                cell.cap = facts.stack
                if facts.name == "" then complete = false end
            end
            column[slot] = cell
        end
        slotGrid[bag] = column
    end
    return complete
end

local function ReleaseSnapshot()
    wipe(slotGrid)
    wipe(itemFacts)
end

-- Bag family (0 = normal). Specialty bags (herb/enchant/…) sort in their own pool.
local function GetBagFamily(bag)
    if bag == BACKPACK_CONTAINER or bag == BANK_CONTAINER then
        return 0
    end
    if IsGuildBankBag(bag) then
        return 0
    end
    local _, bagType = GetContainerNumFreeSlots(bag)
    return bagType or 0
end

-- Specialty families first, then normal (0), so profession bags never share a sort pool.
local function GroupBagsByFamily(bags)
    local groups, families = {}, {}
    for _, bag in ipairs(bags) do
        local family = GetBagFamily(bag)
        if not groups[family] then
            groups[family] = {}
            tinsert(families, family)
        end
        tinsert(groups[family], bag)
    end
    table.sort(families, function(a, b)
        if a == 0 then return false end
        if b == 0 then return true end
        return a > b
    end)
    return families, groups
end

local SORT_CHAT_PREFIX = "|cff00cc66MistUI:|r "

local function Notify(key, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage(SORT_CHAT_PREFIX .. T(key, key), r, g, b)
end

local function ResetPlan()
    wipe(plannedMoves)
    nextMoveIndex = 1
end

-- Mirrors what the executor's drop does: a merge tops the target up and leaves the rest behind.
local function QueueMove(from, to)
    local movedItem = from.item
    if from.item and from.item == to.item and to.qty < to.cap then
        local total = from.qty + to.qty
        if total > to.cap then
            from.qty, to.qty = total - to.cap, to.cap
        else
            to.qty = total
            from.item, from.qty, from.cap = nil, nil, nil
        end
    else
        from.item, to.item = to.item, from.item
        from.qty, to.qty = to.qty, from.qty
        from.cap, to.cap = to.cap, from.cap
    end
    plannedMoves[#plannedMoves + 1] = {
        fromBag = from.bag, fromSlot = from.slot, toBag = to.bag, toSlot = to.slot, item = movedItem,
    }
end

local function UnlockedCells(bags)
    local cells = {}
    for _, bag in ipairs(bags) do
        local column = slotGrid[bag]
        if column then
            for slot = 1, #column do
                local cell = column[slot]
                if not cell.pinned then
                    cells[#cells + 1] = cell
                end
            end
        end
    end
    return cells
end

local function CopyList(list, backwards)
    local copy, size = {}, #list
    for i = 1, size do
        copy[i] = list[backwards and (size + 1 - i) or i]
    end
    return copy
end

local function TopUpStacks(donorBags, receiverBags, fullDonorsAllowed)
    local openStacks = {}
    for _, cell in ipairs(UnlockedCells(receiverBags)) do
        if cell.qty ~= cell.cap then
            openStacks[#openStacks + 1] = cell
        end
    end
    local receiversLastFirst = CopyList(openStacks, true)
    local gaveAway = {}
    for _, donor in ipairs(CopyList(UnlockedCells(donorBags), true)) do
        if donor.item and (fullDonorsAllowed or donor.qty < donor.cap) then
            for _, receiver in ipairs(receiversLastFirst) do
                if donor.item and receiver.item == donor.item and receiver ~= donor
                    and receiver.qty ~= receiver.cap and not gaveAway[receiver] then
                    gaveAway[donor] = true
                    QueueMove(donor, receiver)
                end
            end
        end
    end
end

-- A total order over the cells: every tie is broken down to item id, quantity, bag and slot, because
-- table.sort raises "invalid order function" when two cells each count as "not before" the other
-- while still ordering differently against a third.
local function ComesBefore(a, b)
    local itemA, itemB = a.item, b.item
    if not itemB then return itemA ~= nil end
    if not itemA then return false end
    if itemA == itemB then
        if a.qty ~= b.qty then return a.qty < b.qty end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end
    local fa, fb = itemFacts[itemA], itemFacts[itemB]
    if fa.quality ~= fb.quality then
        if fa.quality == 0 then return false end
        if fb.quality == 0 then return true end
    end
    if fa.classRank ~= fb.classRank then return fa.classRank < fb.classRank end
    if fa.quality ~= fb.quality then return fa.quality > fb.quality end
    if fa.isGear then
        if fa.gearRank ~= fb.gearRank then return fa.gearRank < fb.gearRank end
    elseif fa.subclassRank ~= fb.subclassRank then
        return fa.subclassRank < fb.subclassRank
    end
    if fa.level ~= fb.level then return fa.level > fb.level end
    if fa.name ~= fb.name then return fa.name < fb.name end
    return itemA < itemB
end

local function ReverseStackEnabled()
    local cfg = GetModuleConfig()
    return cfg and cfg.reverse_stack
end

-- Moves planned in one round touch disjoint slots, so the executor can issue several per tick.
local function ArrangePool(bags)
    local order = UnlockedCells(bags)
    local total = #order
    local homes = CopyList(order, ReverseStackEnabled())
    table.sort(order, ComesBefore)

    local positionOf = {}
    for i = 1, total do
        positionOf[order[i]] = i
    end

    local busy = {}
    local deferred = true
    while deferred do
        deferred = false
        wipe(busy)
        for i = 1, total do
            local holder, home = order[i], homes[i]
            local needed = holder ~= home and holder.item
                and not (holder.item == home.item and holder.qty == home.qty)
            if needed and (busy[holder] or busy[home]) then
                deferred = true
            elseif needed then
                busy[holder], busy[home] = true, true
                QueueMove(holder, home)
                local displaced = positionOf[home]
                order[displaced], positionOf[holder] = holder, displaced
                order[i], positionOf[home] = home, i
            end
        end
    end
end

local function PlanFamilyPools(candidates)
    local familyOrder, bagsByFamily = GroupBagsByFamily(candidates)
    for _, family in ipairs(familyOrder) do
        local poolBags = bagsByFamily[family]
        TopUpStacks(poolBags, poolBags, false)
        ArrangePool(poolBags)
    end
end

local tickDriver = CreateFrame("Frame")
tickDriver:Hide()

StopSorting = function(reason)
    running = false
    guildBankSortActive = false
    bankSortActive = false
    awaitedDrop = nil
    waitingSince = nil
    ResetPlan()
    tickDriver:Hide()
    SetSortProgress(nil)
    if reason then
        DEFAULT_CHAT_FRAME:AddMessage(reason, 1, 0.4, 0.4)
    end
end

local function IsSlotBusy(bag, slot)
    local _, _, busy = BagGetItemInfo(bag, slot)
    return busy
end

-- True once the sort has waited too long on the same move; the sort is stopped then, naming the slot.
local function WaitedTooLong(bag, slot)
    local now = GetTime()
    waitingSince = waitingSince or now
    if now - waitingSince > MOVE_TIMEOUT then
        StopSorting(string.format("MistUI: " .. T("Sort stopped because a move did not finish (bag %d, slot %d). Try again, or lock that slot.", "Sort stopped because a move did not finish (bag %d, slot %d). Try again, or lock that slot."), bag, slot))
        return true
    end
    return false
end

local function IssueNextMoves()
    if InCombatLockdown() then
        StopSorting("MistUI: Sort stopped because you entered combat.")
        return
    end
    if CursorHasItem() then
        local _, _, cursorLink = GetCursorInfo()
        if ItemIDFromLink(cursorLink) ~= (awaitedDrop and awaitedDrop.item) then
            StopSorting("MistUI: Sort interrupted.")
            return
        end
    end
    if awaitedDrop then
        if ItemIDFromLink(BagGetItemLink(awaitedDrop.bag, awaitedDrop.slot)) ~= awaitedDrop.item then
            WaitedTooLong(awaitedDrop.bag, awaitedDrop.slot)
            return
        end
        awaitedDrop = nil
        waitingSince = nil
    end

    local issued = 0
    while nextMoveIndex <= #plannedMoves do
        if CursorHasItem() or issued >= MAX_MOVES_PER_TICK then return end
        issued = issued + 1
        local move = plannedMoves[nextMoveIndex]
        local fromBag, fromSlot, toBag, toSlot = move.fromBag, move.fromSlot, move.toBag, move.toSlot
        if IsSlotBusy(fromBag, fromSlot) or IsSlotBusy(toBag, toSlot) then
            if IsSlotBusy(fromBag, fromSlot) then
                WaitedTooLong(fromBag, fromSlot)
            else
                WaitedTooLong(toBag, toSlot)
            end
            return
        end
        waitingSince = nil
        nextMoveIndex = nextMoveIndex + 1
        SetSortProgress(string.format("%d/%d", nextMoveIndex - 1, #plannedMoves))

        local sourceLink = BagGetItemLink(fromBag, fromSlot)
        if not sourceLink then
            StopSorting("MistUI: Sort confused, stopping.")
            return
        end
        local itemID = ItemIDFromLink(sourceLink)
        -- Looting or a manual move since the plan was made: the rest of the plan no longer fits the bags.
        if itemID ~= move.item then
            StopSorting(string.format("MistUI: " .. T("Sort stopped because the items in your bags changed (bag %d, slot %d). Sort again.", "Sort stopped because the items in your bags changed (bag %d, slot %d). Sort again."), fromBag, fromSlot))
            return
        end
        awaitedDrop = { bag = toBag, slot = toSlot, item = itemID }
        local stackLimit = itemID and select(8, GetItemInfo(itemID)) or 1

        local _, targetCount = BagGetItemInfo(toBag, toSlot)
        local _, sourceCount = BagGetItemInfo(fromBag, fromSlot)
        local sameItem = ItemIDFromLink(BagGetItemLink(toBag, toSlot)) == itemID
        local splitAmount = targetCount and stackLimit - targetCount
        if sameItem and splitAmount and splitAmount > 0
            and targetCount + (sourceCount or 0) > stackLimit then
            BagSplitItem(fromBag, fromSlot, splitAmount)
        else
            BagPickupItem(fromBag, fromSlot)
        end

        local guildSource = IsGuildBankBag(fromBag)
        if guildSource or CursorHasItem() then
            BagPickupItem(toBag, toSlot)
        end
        -- The guild bank updates cursor and slots late, so only one guild move goes out per tick.
        if guildSource then return end
    end

    -- The last drop is confirmed on the next tick before the sort calls itself done.
    if awaitedDrop then return end
    Notify("Sort complete.", 0.4, 1, 0.4)
    StopSorting()
end

tickDriver:SetScript("OnUpdate", function(_, elapsed)
    tickAccumulator = tickAccumulator + elapsed
    if tickAccumulator >= GetSortMoveInterval() then
        tickAccumulator = 0
        IssueNextMoves()
    end
end)

local function BeginMoves()
    ReleaseSnapshot()
    if #plannedMoves == 0 then
        return false
    end
    running = true
    tickDriver:Show()
    return true
end

local function SlotCode(bag, slot)
    return bag * 100 + slot
end

local function PrintBankScan()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66" .. T("=== BANK SCAN DEBUG ===", "=== BANK SCAN DEBUG ===") .. "|r")
    for _, bag in ipairs(bankPoolBags) do
        local column = slotGrid[bag] or {}
        for slot = 1, #column do
            local cell = column[slot]
            if cell.item then
                local facts = itemFacts[cell.item]
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%s] bag%s/s%s: %s (id=%s r=%s lv=%s t=%s st=%s eq=%s x%s)",
                    SlotCode(bag, slot), bag, slot, facts.name, cell.item, facts.quality, facts.level,
                    facts.class, facts.subclass, facts.equipLoc, cell.qty))
            end
        end
    end
end

local function PrintPlannedMoves()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66=== " .. #plannedMoves .. " MOVES ===|r")
    for _, move in ipairs(plannedMoves) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  move: [%s]->  [%s]",
            SlotCode(move.fromBag, move.fromSlot), SlotCode(move.toBag, move.toSlot)))
    end
end

-- Item moves from addon code are only allowed out of combat on this client.
-- GetItemInfo above also asks the server for the missing details, so a second press soon after works.
local function CaptureForSort(bags)
    if CaptureBags(bags) then return true end
    ReleaseSnapshot()
    Notify("Some item details are still loading. Try the sort again in a moment.", 1, 0.8, 0)
    return false
end

local function CanBeginSort()
    if running then
        StopSorting("MistUI: " .. T("Sort stopped.", "Sort stopped."))
        return false
    end
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage(SORT_CHAT_PREFIX .. "You cannot sort while in combat.", 1, 0.4, 0.4)
        return false
    end
    return true
end

local function SortPlayerBags()
    if not CanBeginSort() then return end
    ResetPlan()
    if not CaptureForSort(personalBags) then return end
    PlanFamilyPools(carriedBags)
    if not BeginMoves() then
        Notify("Bags already sorted!", 0.4, 1, 0.4)
    end
end

local function SortBankBags()
    if not CanBeginSort() then return end
    if not bank_open then
        Notify("You must be at the bank.", 1, 0.4, 0.4)
        return
    end
    ResetPlan()
    if not CaptureForSort(personalBags) then return end
    if addon.debugMode then
        PrintBankScan()
    end
    -- Families are ignored here on purpose: any carried stack may top up any open bank stack.
    if IsBankFillFromBagsEnabled() then
        TopUpStacks(carriedBags, bankPoolBags, true)
    end
    PlanFamilyPools(bankPoolBags)
    if addon.debugMode then
        PrintPlannedMoves()
    end
    if BeginMoves() then
        bankSortActive = true
    else
        Notify("Bank already sorted!", 0.4, 1, 0.4)
    end
end

-- Only the shown tab is touched; crossing tabs would spend withdrawal allowance just to reorder.
local function PerformGuildBankSort()
    if not CanBeginSort() then return end
    if not guild_bank_open then
        Notify("You must be at the guild bank.", 1, 0.4, 0.4)
        return
    end
    local tab = GetCurrentGuildBankTab()
    if not tab or tab < 1 then
        Notify("Could not determine the current guild bank tab.", 1, 0.4, 0.4)
        return
    end
    if GetGuildBankTabSlotCount(tab) == 0 then
        Notify("You need full deposit and withdraw access to this tab to sort it.", 1, 0.4, 0.4)
        return
    end
    local tabBags = { GUILDBANK_TAB_OFFSET + tab }
    ResetPlan()
    if not CaptureForSort(tabBags) then return end
    TopUpStacks(tabBags, tabBags, false)
    ArrangePool(tabBags)
    if #plannedMoves == 0 then
        ReleaseSnapshot()
        Notify("This guild bank tab is already sorted!", 0.4, 1, 0.4)
        return
    end
    guildBankSortActive = true
    BeginMoves()
end

StaticPopupDialogs["MISTUI_CONFIRM_GUILDBANK_SORT"] = {
    text = T("Sort this guild bank tab? Depending on your server, this may be logged and count against your guild's shared withdrawal allowance, the same as moving items by hand.", "Sort this guild bank tab? Depending on your server, this may be logged and count against your guild's shared withdrawal allowance, the same as moving items by hand."),
    button1 = T("Sort", "Sort"),
    button2 = CANCEL,
    OnAccept = PerformGuildBankSort,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function SortGuildBankTab()
    if running then
        StopSorting("MistUI: " .. T("Sort stopped.", "Sort stopped."))
        return
    end
    if not guild_bank_open then
        Notify("You must be at the guild bank.", 1, 0.4, 0.4)
        return
    end
    StaticPopup_Show("MISTUI_CONFIRM_GUILDBANK_SORT")
end

local function HandleSortLockCommand(msg)
    local command = msg and string.lower(string.gsub(msg, "^%s*(.-)%s*$", "%1")) or ""
    if command == "clear" or command == "reset" then
        ClearAllLockedSlots()
        return
    end
    ToggleHoveredSlotLock()
end

-- ============================================================================
-- BUTTON CREATION HELPERS
-- ============================================================================

-- Retail INV_Pet_Broom, the art behind retail's bag cleanup button; the 5.4.8 client has no broom icon.
local SORT_ICON_TEXTURE = "Interface\\AddOns\\MistUI\\Textures\\UI\\BagSortBroom"

local function CreateActionButton(name, parent, onClick, tooltipTitle, scale, iconPath, tooltipLines)
    scale = scale or 1.0
    local size = 32 * scale
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(size, size)
    btn:EnableMouse(true)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)

    -- Icon fills the button
    local icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(iconPath or SORT_ICON_TEXTURE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Square border (action button style)
    local border = btn:CreateTexture(name .. "Border", "OVERLAY")
    border:SetSize(size * 62/36, size * 62/36)
    border:SetPoint("CENTER", 0, 0)
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    btn.border = border

    -- Highlight
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    btn.highlight = highlight

    -- Pushed feedback
    btn:SetScript("OnMouseDown", function(self)
        self.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipTitle or T("Sort Items", "Sort Items"))
        local lines = tooltipLines
        if type(lines) == "function" then
            lines = lines()
        end
        if type(lines) == "table" then
            for _, line in ipairs(lines) do
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        elseif type(lines) == "string" then
            GameTooltip:AddLine(lines, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Click handler
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)

    return btn
end

local function CreateSortButton(name, parent, onClick, tooltipText, scale)
    local function BuildTooltipLines()
        return {
            T("Click to sort items by type, rarity, and name.", "Click to sort items by type, rarity, and name."),
            string.format(T("%s any bag slot (item or empty) to lock or unlock it.", "%s any bag slot (item or empty) to lock or unlock it."), GetLockHotkeyLabel()),
            T("Click the lock-clear button to remove all locked slots.", "Click the lock-clear button to remove all locked slots."),
            T("Click again while sorting to stop.", "Click again while sorting to stop."),
        }
    end

    return AttachSortProgress(CreateActionButton(
        name,
        parent,
        onClick,
        tooltipText,
        scale,
        SORT_ICON_TEXTURE,
        BuildTooltipLines
    ))
end

local function CreateClearLocksButton(name, parent, scale)
    local function BuildTooltipLines()
        return {
            T("Click to clear all locked bag slots.", "Click to clear all locked bag slots."),
            string.format(T("%s any bag slot (item or empty) to lock or unlock it.", "%s any bag slot (item or empty) to lock or unlock it."), GetLockHotkeyLabel())
        }
    end

    return CreateActionButton(
        name,
        parent,
        ClearAllLockedSlots,
        T("Clear Locked Slots", "Clear Locked Slots"),
        scale,
        "Interface\\Icons\\INV_Misc_Key_14",
        BuildTooltipLines
    )
end

-- ============================================================================
-- SELL SCRAP
-- ============================================================================

local function FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRem = copper % 100
    if gold > 0 then
        return string.format("|cffffd700%dg|r |cffc0c0c0%ds|r |cffeda55f%dc|r", gold, silver, copperRem)
    elseif silver > 0 then
        return string.format("|cffc0c0c0%ds|r |cffeda55f%dc|r", silver, copperRem)
    else
        return string.format("|cffeda55f%dc|r", copperRem)
    end
end

-- Scrap goes to the vendor a few stacks per tick, like the sort moves, so a full bag does not flood the server.
local SCRAP_RETRY_DELAY = 1
local scrapRun
local scrapDriver = CreateFrame("Frame")
scrapDriver:Hide()
local scrapElapsed = 0

local function PrintScrap(text)
    print("|cffff9900MistUI|r: " .. text)
end

-- The poor-quality flag is in the slot itself, so an item the client has not cached yet still shows up;
-- only its vendor price is missing, and those wait for a retry.
local function ScanScrap(run)
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemID = GetContainerItemID(bag, slot)
            if itemID and not IsSlotLocked(bag, slot) and not GetContainerItemQuestInfo(bag, slot) then
                local _, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
                local slotQuality = select(4, GetContainerItemInfo(bag, slot))
                if (quality or slotQuality) == 0 then
                    local entry = { bag = bag, slot = slot, item = itemID }
                    if sellPrice == nil then
                        run.deferred[#run.deferred + 1] = entry
                    elseif sellPrice > 0 then
                        entry.price = sellPrice
                        run.queue[#run.queue + 1] = entry
                    end
                end
            end
        end
    end
end

local function FinishScrapSale(run, merchantClosed)
    scrapRun = nil
    scrapDriver:Hide()
    local skipped = run.skipped + #run.deferred
    if run.sold > 0 then
        PrintScrap(string.format(T("Sold %d scrap item(s) for %s.", "Sold %d scrap item(s) for %s."), run.sold, FormatMoney(run.value)))
    elseif skipped == 0 then
        PrintScrap(T("No scrap items to sell.", "No scrap items to sell."))
    end
    if merchantClosed then
        PrintScrap(T("The merchant window closed before all scrap was sold.", "The merchant window closed before all scrap was sold."))
    end
    if skipped > 0 then
        PrintScrap(string.format(T("Skipped %d scrap item(s): item details still loading or the slot changed.", "Skipped %d scrap item(s): item details still loading or the slot changed."), skipped))
    end
end

-- Items whose details arrived since the scan join the queue; the rest are reported as skipped.
local function RetryDeferredScrap(run)
    run.retried = true
    local stillUnknown = {}
    for _, entry in ipairs(run.deferred) do
        local sellPrice = select(11, GetItemInfo(entry.item))
        if sellPrice == nil then
            stillUnknown[#stillUnknown + 1] = entry
        elseif sellPrice > 0 then
            entry.price = sellPrice
            run.queue[#run.queue + 1] = entry
        end
    end
    run.deferred = stillUnknown
end

local function SellNextScrap(run)
    for _ = 1, MAX_MOVES_PER_TICK do
        local entry = run.queue[run.next]
        if not entry then return end
        run.next = run.next + 1
        local _, count, busy = GetContainerItemInfo(entry.bag, entry.slot)
        -- A lock set or an item moved after the scan must not lose the player's item.
        if GetContainerItemID(entry.bag, entry.slot) ~= entry.item or IsSlotLocked(entry.bag, entry.slot) or busy then
            run.skipped = run.skipped + 1
        else
            UseContainerItem(entry.bag, entry.slot)
            run.sold = run.sold + 1
            run.value = run.value + entry.price * (count or 1)
        end
    end
end

scrapDriver:SetScript("OnUpdate", function(_, elapsed)
    scrapElapsed = scrapElapsed + elapsed
    if scrapElapsed < GetSortMoveInterval() then return end
    scrapElapsed = 0
    local run = scrapRun
    local waitingForRetry = #run.deferred > 0 and not run.retried
    local workLeft = run.queue[run.next] ~= nil or waitingForRetry
    if workLeft and not (MerchantFrame and MerchantFrame:IsShown()) then
        FinishScrapSale(run, true)
    elseif run.queue[run.next] then
        SellNextScrap(run)
    elseif waitingForRetry then
        if GetTime() - run.startedAt >= SCRAP_RETRY_DELAY then
            RetryDeferredScrap(run)
        end
    else
        FinishScrapSale(run)
    end
end)

local function SellScrapItems()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        PrintScrap(T("Open a merchant window first to sell scrap items.", "Open a merchant window first to sell scrap items."))
        return
    end
    if scrapRun then return end

    scrapRun = { queue = {}, deferred = {}, next = 1, sold = 0, skipped = 0, value = 0, startedAt = GetTime() }
    ScanScrap(scrapRun)
    scrapElapsed = 0
    scrapDriver:Show()
end

local function CreateSellScrapButton(name, parent, scale)
    local function BuildTooltipLines()
        return {
            T("Click to sell all gray (poor) items to vendor.", "Click to sell all gray (poor) items to vendor."),
            T("A merchant window must be open.", "A merchant window must be open.")
        }
    end

    return CreateActionButton(
        name,
        parent,
        SellScrapItems,
        T("Sell Scrap", "Sell Scrap"),
        scale,
        "Interface\\Icons\\INV_Misc_Coin_01",
        BuildTooltipLines
    )
end

-- ============================================================================
-- BAGSTER BUTTON INTEGRATION
-- ============================================================================

local bagsterBagSortBtn, bagsterBankSortBtn
local bagsterBagClearBtn, bagsterBankClearBtn
local bagsterBagSellScrapBtn, bagsterBankSellScrapBtn
local stockGuildBankSortBtn

local function GetBagsterFrame(index)
    return _G["MistUI_BagsterFrame" .. index]
end

local function AttachBagsterButtons(frame, sortRef, clearRef, sellScrapRef, sortFunc, sortBtnName, clearBtnName, sellScrapBtnName, tooltipText)
    if sortRef and clearRef and (not sellScrapBtnName or sellScrapRef) then
        return sortRef, clearRef, sellScrapRef
    end

    local frameName = frame:GetName()
    local searchBox = _G[frameName .. "Search"]
    local bagToggle = _G[frameName .. "BagToggle"]

    local sortBtn = sortRef or CreateSortButton(sortBtnName, frame, sortFunc, tooltipText, 0.55)
    local clearBtn = clearRef or CreateClearLocksButton(clearBtnName, frame, 0.55)
    local sellScrapBtn = sellScrapRef
    if sellScrapBtnName and not sellScrapRef then
        sellScrapBtn = CreateSellScrapButton(sellScrapBtnName, frame, 0.55)
    end

    -- Retail action-button chrome for the header buttons (same recipe as buttons.lua)
    local function StyleHeaderButton(b)
        if not b or b._bagsterStyled then return end
        b._bagsterStyled = true
        b:SetSize(22, 22)
        b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        b.border:SetTexture(addon._dir .. "ActionBars\\uiactionbariconframe")
        b.border:ClearAllPoints()
        b.border:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2.2, 2.3)
        b.border:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -2.2, -2.2)
        if b.highlight then
            b.highlight:SetTexture(addon._dir .. "ActionBars\\uiactionbariconframehighlight")
            b.highlight:ClearAllPoints()
            b.highlight:SetAllPoints(b.border)
        end
        b:SetScript("OnMouseDown", function(self)
            self.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end)
        b:SetScript("OnMouseUp", function(self)
            self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        end)
    end
    StyleHeaderButton(sortBtn)
    StyleHeaderButton(clearBtn)
    StyleHeaderButton(sellScrapBtn)

    -- Single header row: [ searchBox ][ sellScrap ][ clearBtn ][ sortBtn ][ bagToggle ]
    if bagToggle then
        bagToggle:ClearAllPoints()
        bagToggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -30)
    end

    sortBtn:ClearAllPoints()
    if bagToggle then
        sortBtn:SetPoint("RIGHT", bagToggle, "LEFT", -6, 0)
    else
        sortBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -32)
    end

    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("RIGHT", sortBtn, "LEFT", -4, 0)

    if sellScrapBtn then
        sellScrapBtn:ClearAllPoints()
        sellScrapBtn:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
    end

    -- Search box is fixed-width on the left; nothing to shrink anymore

    sortBtn:Show()
    clearBtn:Show()
    if sellScrapBtn then sellScrapBtn:Show() end
    return sortBtn, clearBtn, sellScrapBtn
end

local function CreateBagsterSortButtons()
    local inventoryFrame = GetBagsterFrame(1)
    local bankFrame = GetBagsterFrame(2)

    if inventoryFrame and (not bagsterBagSortBtn or not bagsterBagClearBtn or not bagsterBagSellScrapBtn) then
        bagsterBagSortBtn, bagsterBagClearBtn, bagsterBagSellScrapBtn = AttachBagsterButtons(
            inventoryFrame, bagsterBagSortBtn, bagsterBagClearBtn, bagsterBagSellScrapBtn,
            SortPlayerBags, "MistUI_BagsterBagSortBtn", "MistUI_BagsterBagClearBtn", "MistUI_BagsterBagSellScrapBtn",
            T("Sort Bags", "Sort Bags")
        )
        BagSortModule.frames.bagsterBagSortBtn = bagsterBagSortBtn
        BagSortModule.frames.bagsterBagClearBtn = bagsterBagClearBtn
        BagSortModule.frames.bagsterBagSellScrapBtn = bagsterBagSellScrapBtn
    end

    if bankFrame and (not bagsterBankSortBtn or not bagsterBankClearBtn) then
        bagsterBankSortBtn, bagsterBankClearBtn = AttachBagsterButtons(
            bankFrame, bagsterBankSortBtn, bagsterBankClearBtn, nil,
            SortBankBags, "MistUI_BagsterBankSortBtn", "MistUI_BagsterBankClearBtn", nil,
            T("Sort Bank", "Sort Bank")
        )
        BagSortModule.frames.bagsterBankSortBtn = bagsterBankSortBtn
        BagSortModule.frames.bagsterBankClearBtn = bagsterBankClearBtn
    end
end

-- ============================================================================
-- GUILD BANK BUTTON INTEGRATION
-- ============================================================================
-- No "Clear Locks" button here -- guild bank slots are never lockable.

local function CreateGuildBankSortButton(name, parent)
    local function BuildTooltipLines()
        return {
            T("Click to sort items in the currently open guild bank tab.", "Click to sort items in the currently open guild bank tab."),
            T("Never moves items between tabs.", "Never moves items between tabs."),
            T("Click again while sorting to stop.", "Click again while sorting to stop."),
        }
    end

    return AttachSortProgress(CreateActionButton(
        name,
        parent,
        SortGuildBankTab,
        T("Sort Guild Bank Tab", "Sort Guild Bank Tab"),
        0.61,
        SORT_ICON_TEXTURE,
        BuildTooltipLines
    ))
end

local function CreateStockGuildBankSortButton()
    if stockGuildBankSortBtn then return end
    local frame = _G.GuildBankFrame
    if not frame then return end

    stockGuildBankSortBtn = CreateGuildBankSortButton("MistUI_StockGuildBankSortBtn", frame)
    stockGuildBankSortBtn:ClearAllPoints()
    stockGuildBankSortBtn:SetPoint("RIGHT", GuildBankFrameWithdrawButton, "LEFT", -4, 0)
    BagSortModule.frames.stockGuildBankSortBtn = stockGuildBankSortBtn
end

local bagsterGuildSortBtn
local function CreateBagsterGuildBankSortButton()
    if bagsterGuildSortBtn then return end
    local frame = _G["MistUI_BagsterFrame3"]
    if not frame or not frame.itemFrame then return end

    -- Parented to the item grid so it auto-hides on the Log/Money/Info mode tabs
    bagsterGuildSortBtn = CreateGuildBankSortButton("MistUI_BagsterGuildSortBtn", frame.itemFrame)
    bagsterGuildSortBtn:SetSize(22, 22)
    bagsterGuildSortBtn.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    bagsterGuildSortBtn.border:SetTexture(addon._dir .. "ActionBars\\uiactionbariconframe")
    bagsterGuildSortBtn.border:ClearAllPoints()
    bagsterGuildSortBtn.border:SetPoint("TOPRIGHT", bagsterGuildSortBtn, "TOPRIGHT", 2.2, 2.3)
    bagsterGuildSortBtn.border:SetPoint("BOTTOMLEFT", bagsterGuildSortBtn, "BOTTOMLEFT", -2.2, -2.2)
    if bagsterGuildSortBtn.highlight then
        bagsterGuildSortBtn.highlight:SetTexture(addon._dir .. "ActionBars\\uiactionbariconframehighlight")
        bagsterGuildSortBtn.highlight:ClearAllPoints()
        bagsterGuildSortBtn.highlight:SetAllPoints(bagsterGuildSortBtn.border)
    end
    bagsterGuildSortBtn:ClearAllPoints()
    bagsterGuildSortBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -31)
    BagSortModule.frames.bagsterGuildSortBtn = bagsterGuildSortBtn
end

-- ============================================================================
-- STOCK FRAME BUTTON INTEGRATION
-- ============================================================================

local stockBagSortBtn, stockBankSortBtn
local stockBagClearBtn, stockBankClearBtn
local stockBagSellScrapBtn

local function CreateStockBagSortButton()
    if stockBagSortBtn then return end

    stockBagSortBtn = CreateSortButton(
        "MistUI_StockBagSortBtn",
        UIParent,
        SortPlayerBags,
        T("Sort Bags", "Sort Bags"),
        0.63
    )
    stockBagClearBtn = CreateClearLocksButton("MistUI_StockBagClearBtn", UIParent, 0.63)
    stockBagSellScrapBtn = CreateSellScrapButton("MistUI_StockBagSellScrapBtn", UIParent, 0.63)
    stockBagSortBtn:Hide()
    stockBagClearBtn:Hide()
    stockBagSellScrapBtn:Hide()
    BagSortModule.frames.stockBagSortBtn = stockBagSortBtn
    BagSortModule.frames.stockBagClearBtn = stockBagClearBtn
    BagSortModule.frames.stockBagSellScrapBtn = stockBagSellScrapBtn
end

-- Find which ContainerFrame is currently showing bag 0 (backpack)
local function GetBackpackFrame()
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() and frame:GetID() == 0 then
            return frame
        end
    end
end

local function UpdateStockBagSortButton()
    if not stockBagSortBtn or not stockBagClearBtn then return end
    local backpack = GetBackpackFrame()
    if backpack then
        stockBagSortBtn:SetParent(backpack)
        stockBagClearBtn:SetParent(backpack)
        stockBagSellScrapBtn:SetParent(backpack)
        stockBagSortBtn:ClearAllPoints()
        stockBagClearBtn:ClearAllPoints()
        stockBagSellScrapBtn:ClearAllPoints()
        local titleAnchor = _G[backpack:GetName() .. "Name"]
        local skinChrome = backpack._mistuiBagChrome
        if addon:IsModuleEnabled("bags_skin")
            and skinChrome and skinChrome.title and skinChrome.title:IsShown()
        then
            titleAnchor = skinChrome.title
        end
        stockBagSortBtn:SetPoint("TOP", titleAnchor, "BOTTOM", 70.5, -6.5)
        stockBagClearBtn:SetPoint("RIGHT", stockBagSortBtn, "LEFT", -3, 0)
        stockBagSellScrapBtn:SetPoint("RIGHT", stockBagClearBtn, "LEFT", -3, 0)
        stockBagSortBtn:SetFrameLevel(backpack:GetFrameLevel() + 10)
        stockBagClearBtn:SetFrameLevel(backpack:GetFrameLevel() + 10)
        stockBagSellScrapBtn:SetFrameLevel(backpack:GetFrameLevel() + 10)
        stockBagSortBtn:Show()
        stockBagClearBtn:Show()
        stockBagSellScrapBtn:Show()
    else
        stockBagSortBtn:Hide()
        stockBagClearBtn:Hide()
        stockBagSellScrapBtn:Hide()
    end
end

local function CreateStockBankSortButton()
    if stockBankSortBtn then return end

    local bankFrameUI = BankFrame
    if not bankFrameUI then return end

    stockBankSortBtn = CreateSortButton(
        "MistUI_StockBankSortBtn",
        bankFrameUI,
        SortBankBags,
        T("Sort Bank", "Sort Bank"),
        0.70
    )
    stockBankClearBtn = CreateClearLocksButton("MistUI_StockBankClearBtn", bankFrameUI, 0.70)
    -- In the title bar, to the left of the close button
    stockBankSortBtn:SetPoint("RIGHT", bankFrameUI.CloseButton, "LEFT", -2, 0)
    stockBankClearBtn:SetPoint("RIGHT", stockBankSortBtn, "LEFT", -2, 0)
    stockBankSortBtn:Show()
    stockBankClearBtn:Show()
    BagSortModule.frames.stockBankSortBtn = stockBankSortBtn
    BagSortModule.frames.stockBankClearBtn = stockBankClearBtn
end

-- ============================================================================
-- BUTTON VISIBILITY MANAGEMENT
-- ============================================================================

UpdateButtonVisibility = function()
    local bagsterActive = IsBagsterEnabled()
    local bagsterApplied = GetBagsterFrame(1) ~= nil

    if bagsterActive and bagsterApplied then
        CreateBagsterSortButtons()
        -- The buttons act on the current character's bags, so they hide while the window shows another.
        local function SetLive(button, frame)
            if not button then return end
            if frame and frame.IsViewingOtherCharacter and frame:IsViewingOtherCharacter() then
                button:Hide()
            else
                button:Show()
            end
        end
        local bagFrame, bankFrame = GetBagsterFrame(1), GetBagsterFrame(2)
        SetLive(bagsterBagSortBtn, bagFrame)
        SetLive(bagsterBagClearBtn, bagFrame)
        SetLive(bagsterBagSellScrapBtn, bagFrame)
        SetLive(bagsterBankSortBtn, bankFrame)
        SetLive(bagsterBankClearBtn, bankFrame)
        if stockBagSortBtn then stockBagSortBtn:Hide() end
        if stockBagClearBtn then stockBagClearBtn:Hide() end
        if stockBagSellScrapBtn then stockBagSellScrapBtn:Hide() end
        if stockBankSortBtn then stockBankSortBtn:Hide() end
        if stockBankClearBtn then stockBankClearBtn:Hide() end
    else
        CreateStockBagSortButton()
        CreateStockBankSortButton()
        UpdateStockBagSortButton()
        if stockBankSortBtn then stockBankSortBtn:Show() end
        if stockBankClearBtn then stockBankClearBtn:Show() end
        if bagsterBagSortBtn then bagsterBagSortBtn:Hide() end
        if bagsterBagClearBtn then bagsterBagClearBtn:Hide() end
        if bagsterBagSellScrapBtn then bagsterBagSellScrapBtn:Hide() end
        if bagsterBankSortBtn then bagsterBankSortBtn:Hide() end
        if bagsterBankClearBtn then bagsterBankClearBtn:Hide() end
    end

    CreateStockGuildBankSortButton()
    CreateBagsterGuildBankSortButton()
    if bagsterGuildSortBtn then
        if guild_bank_open and IsBagsterEnabled() then
            bagsterGuildSortBtn:Show()
        else
            bagsterGuildSortBtn:Hide()
        end
    end
    if stockGuildBankSortBtn then
        -- Only "bank" mode shows item slots (vs. log/money log/info sub-tabs).
        if guild_bank_open and _G.GuildBankFrame and _G.GuildBankFrame.mode == "bank" then
            stockGuildBankSortBtn:Show()
        else
            stockGuildBankSortBtn:Hide()
        end
    end
end

function addon.OnBagsterPlayerChanged()
    if BagSortModule.applied then UpdateButtonVisibility() end
end

-- Hook into frame show events for lazy/reliable button creation
local hooksInstalled = false
local function InstallShowHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- Hook bagster frames if they exist (they show/hide dynamically)
    local cFrame1 = GetBagsterFrame(1)
    local cFrame2 = GetBagsterFrame(2)
    if cFrame1 then
        hooksecurefunc(cFrame1, "Show", function()
            if BagSortModule.applied and not bagsterBagSortBtn then
                UpdateButtonVisibility()
            end
        end)
    end
    if cFrame2 then
        hooksecurefunc(cFrame2, "Show", function()
            if BagSortModule.applied and not bagsterBankSortBtn then
                UpdateButtonVisibility()
            end
        end)
    end

    -- Hook stock ContainerFrame open/close for backpack-only sort button
    if not IsBagsterEnabled() then
        for i = 1, NUM_CONTAINER_FRAMES do
            local frame = _G["ContainerFrame" .. i]
            if frame then
                frame:HookScript("OnShow", function()
                    if BagSortModule.applied then UpdateStockBagSortButton() end
                end)
                frame:HookScript("OnHide", function()
                    if BagSortModule.applied then UpdateStockBagSortButton() end
                end)
            end
        end
    end

    -- Hook BankFrame OnShow
    if BankFrame then
        hooksecurefunc(BankFrame, "Show", function()
            if BagSortModule.applied and not stockBankSortBtn and not IsBagsterEnabled() then
                UpdateButtonVisibility()
            end
        end)
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local eventFrame = CreateFrame("Frame")

-- ============================================================================
-- APPLY / RESTORE SYSTEM
-- ============================================================================

-- Forward declaration
local ApplyBagSortSystem

ApplyBagSortSystem = function()
    if BagSortModule.applied then return end

    -- Register bank events
    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "BANKFRAME_OPENED" then
            bank_open = true
            UpdateButtonVisibility()
        elseif event == "BANKFRAME_CLOSED" then
            bank_open = false
            if bankSortActive then
                StopSorting("MistUI: Sort stopped because the bank closed.")
            end
        elseif event == "GUILDBANKFRAME_OPENED" then
            guild_bank_open = true
            -- Guild bank UI loads on demand; this function doesn't exist at startup.
            if not guildBankTabHookInstalled and type(GuildBankFrameTab_OnClick) == "function" then
                guildBankTabHookInstalled = true
                hooksecurefunc("GuildBankFrameTab_OnClick", function()
                    if BagSortModule.applied then
                        UpdateButtonVisibility()
                    end
                end)
            end
            UpdateButtonVisibility()
            -- Second pass: the Bagster guild frame may be created lazily by this same event
            addon:After(0.3, function()
                if BagSortModule.applied and guild_bank_open then
                    UpdateButtonVisibility()
                end
            end)
        elseif event == "GUILDBANKFRAME_CLOSED" then
            guild_bank_open = false
            if guildBankSortActive then
                StopSorting("MistUI: Sort stopped because the guild bank closed.")
            end
        end
    end)
    for _, eventName in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }) do
        eventFrame:RegisterEvent(eventName)
        BagSortModule.registeredEvents[eventName] = true
    end

    -- Register slash commands
    SlashCmdList["MISTUI_SORT"] = SortPlayerBags
    SLASH_MISTUI_SORT1 = "/sort"
    SLASH_MISTUI_SORT2 = "/sortbags"

    SlashCmdList["MISTUI_SORTBANK"] = SortBankBags
    SLASH_MISTUI_SORTBANK1 = "/sortbank"

    SlashCmdList["MISTUI_SORTGUILDBANK"] = SortGuildBankTab
    SLASH_MISTUI_SORTGUILDBANK1 = "/sortguildbank"

    SlashCmdList["MISTUI_SORTLOCK"] = HandleSortLockCommand
    SLASH_MISTUI_SORTLOCK1 = "/sortlock"
    SLASH_MISTUI_SORTLOCK2 = "/sortignore"

    -- Delay button creation to ensure bagster frames are ready, then install hooks
    InstallAltClickHooks()

    addon:After(0.5, function()
        if BagSortModule.applied then
            UpdateButtonVisibility()
            InstallShowHooks()
        end
    end)

    BagSortModule.applied = true
    -- The hooks above ran before the module counted as applied, so paint the padlocks now.
    RefreshAllLockMarkers()
end

local function RestoreBagSortSystem()
    if not BagSortModule.applied then return end

    -- Stop any running sort
    StopSorting()

    -- Unregister events
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    wipe(BagSortModule.registeredEvents)

    -- Hide and clean up buttons
    if bagsterBagSortBtn then bagsterBagSortBtn:Hide() end
    if bagsterBagClearBtn then bagsterBagClearBtn:Hide() end
    if bagsterBankSortBtn then bagsterBankSortBtn:Hide() end
    if bagsterBankClearBtn then bagsterBankClearBtn:Hide() end
    if stockBagSortBtn then stockBagSortBtn:Hide() end
    if stockBagClearBtn then stockBagClearBtn:Hide() end
    if stockBagSellScrapBtn then stockBagSellScrapBtn:Hide() end
    if stockBankSortBtn then stockBankSortBtn:Hide() end
    if stockBankClearBtn then stockBankClearBtn:Hide() end
    if stockGuildBankSortBtn then stockGuildBankSortBtn:Hide() end
    if bagsterGuildSortBtn then bagsterGuildSortBtn:Hide() end

    -- Remove slash commands
    SlashCmdList["MISTUI_SORT"] = nil
    SlashCmdList["MISTUI_SORTBANK"] = nil
    SlashCmdList["MISTUI_SORTGUILDBANK"] = nil
    SlashCmdList["MISTUI_SORTLOCK"] = nil

    if lockVisualFrame then
        lockVisualFrame:SetScript("OnUpdate", nil)
        lockVisualFrame:Hide()
        lockVisualFrame = nil
    end
    -- Lets a later Apply rebuild the refresh frame; already hooked buttons are skipped by their flag.
    clickHooksInstalled = false

    for button, _ in pairs(hookedSlotButtons) do
        if button and button._mistUISortLockMarker then
            button._mistUISortLockMarker:Hide()
        end
    end

    BagSortModule.applied = false
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

-- Profile change callbacks (handled via ADDON_LOADED registration)
local function OnProfileChanged()
    if IsModuleEnabled() then
        if not BagSortModule.applied then
            ApplyBagSortSystem()
        else
            UpdateButtonVisibility()
        end
    else
        if addon:ShouldDeferModuleDisable("bagsort", BagSortModule) then
            return
        end
        RestoreBagSortSystem()
    end
end

-- Initialization via events
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "MistUI" then
        if not IsModuleEnabled() then return end

        -- Register profile callbacks after DB is ready
        -- Use After to ensure DB is fully initialized
        if addon.After then
            addon:After(0.6, function()
                if addon.db and addon.db.RegisterCallback then
                    -- Use a unique callback object to avoid overwriting other modules
                    local callbackObj = {}
                    addon.db.RegisterCallback(callbackObj, "OnProfileChanged", OnProfileChanged)
                    addon.db.RegisterCallback(callbackObj, "OnProfileCopied", OnProfileChanged)
                    addon.db.RegisterCallback(callbackObj, "OnProfileReset", OnProfileChanged)
                end
            end)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        ApplyBagSortSystem()
    end
end)

-- Registry lifecycle resolves these off `addon` via lifecyclePrefix "BagSort".
addon.ApplyBagSortSystem = ApplyBagSortSystem
addon.RestoreBagSortSystem = RestoreBagSortSystem

-- Expose sort functions for other modules/macros
addon.SortPlayerBags = SortPlayerBags
addon.SortBankBags = SortBankBags
addon.SortGuildBankTab = SortGuildBankTab
-- Lets the options panel re-tint visible lock icons live when the color changes.
addon.RefreshBagSortLockMarkers = RefreshAllLockMarkers
addon.BagSortDefaultLockColor = DEFAULT_LOCK_MARKER_COLOR
