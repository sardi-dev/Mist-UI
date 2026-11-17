-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Button sizes, offsets and texture coordinates adapted from DragonUI (MIT, (c) 2026 NeticSoul)
-- and DragonflightUI (MIT, (c) 2022 Karl-HeinzSchneider); see THIRD_PARTY_NOTICES.

-- Bag bar: the backpack and the four bag slots in a bar of their own, with an arrow that folds
-- the slots away. It is part of the micro menu module, which starts it and shares its settings.
-- The bag buttons are not protected frames, so moving, showing and hiding them is allowed in combat.

local addon = select(2, ...)
local Menu = addon.MicroMenuModule

local KEY = "bagsbar"
local BACKPACK_SIZE, SLOT_SIZE = 50, 28
local BACKPACK_GAP, SLOT_GAP = 14, 4
-- The slots sit a little below the backpack's centre line.
local SLOT_DROP = -2
local SLOT_COUNT = 4
local BAR_WIDTH = BACKPACK_SIZE + BACKPACK_GAP + SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP
local BAR_HEIGHT = 54
local DEFAULT_ANCHOR, DEFAULT_X, DEFAULT_Y = "BOTTOMRIGHT", -5, 40
local TOGGLE_WIDTH, TOGGLE_HEIGHT = 12, 18
local SLOT_HOVER_ALPHA = 0.4
local TOP_SUBLEVEL = 7
local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
local SLOT_BACKDROP = addon._dir .. "Bags\\bagslots2x"
local SLOT_BACKDROP_COORDS = { 295 / 512, 356 / 512, 64 / 128, 125 / 128 }

local Bags = { FADE_KEY = "bag" }
Menu.Bags = Bags

local bar, box, toggle
local slots = {}
local isSlot = {}
local toggleFaces = {}

local function Scale()
    local bags = addon.db.profile.bags
    return tonumber(bags and bags.scale) or 1
end

-- ============================================================================
-- Painting
-- ============================================================================

-- A button face (normal, pushed, highlight, checked) as a texture this module may restyle.
local function Face(button, name)
    local texture = button["Get" .. name .. "Texture"](button)
    if not texture then
        texture = button:CreateTexture(nil, "ARTWORK")
        button["Set" .. name .. "Texture"](button, texture)
    end
    return texture
end

local function HideFace(button, name)
    local texture = Face(button, name)
    texture:SetTexture(nil)
    texture:SetAlpha(0)
end

local function PaintGlow(button, name, atlas)
    local texture = Face(button, name)
    texture:ClearAllPoints()
    texture:SetAllPoints(button)
    texture:SetBlendMode("ADD")
    texture:SetAtlasTexture(atlas)
    return texture
end

local function PaintBackpack()
    local backpack = MainMenuBarBackpackButton
    backpack:SetSize(BACKPACK_SIZE, BACKPACK_SIZE)
    HideFace(backpack, "Normal")
    HideFace(backpack, "Pushed")
    PaintGlow(backpack, "Highlight", "bag-main-highlight-2x")
    PaintGlow(backpack, "Checked", "bag-main-highlight-2x"):SetDrawLayer("OVERLAY", TOP_SUBLEVEL)
    MainMenuBarBackpackButtonIconTexture:SetAtlasTexture("bag-main-2x")
    MainMenuBarBackpackButtonCount:SetSinglePoint("CENTER", backpack, "BOTTOM", 0, 14)
end

-- The stock code refreshes a slot's icon by itself; an empty slot gets a placeholder picture,
-- which is hidden here so that only the ring shows.
local function PaintSlotIcon(slot)
    local icon = _G[slot:GetName() .. "IconTexture"]
    icon:ClearAllPoints()
    icon:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -5, -2.9)
    icon:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 2.9, 5)
    icon:SetTexCoord(unpack(ICON_CROP))
    icon:SetAlpha(GetInventoryItemID("player", slot:GetID()) and 1 or 0)
end

local function PaintSlot(slot)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    HideFace(slot, "Normal")
    HideFace(slot, "Pushed")
    PaintGlow(slot, "Highlight", "bag-border-highlight-2x"):SetAlpha(SLOT_HOVER_ALPHA)
    PaintGlow(slot, "Checked", "bag-border-highlight-2x"):SetDrawLayer("OVERLAY", TOP_SUBLEVEL)

    local count = _G[slot:GetName() .. "Count"]
    count:SetSinglePoint("CENTER", slot, "CENTER", 0, -10)
    count:SetDrawLayer("OVERLAY")

    if not slot.mistuiRing then
        local ring = slot:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("CENTER", slot, "CENTER")
        ring:SetAtlasTexture("bag-border-2x", true)
        slot.mistuiRing = ring

        local backdrop = slot:CreateTexture(nil, "BACKGROUND")
        backdrop:SetSize(ring:GetWidth(), ring:GetHeight())
        backdrop:SetPoint("CENTER", slot, "CENTER")
        backdrop:SetTexture(SLOT_BACKDROP)
        backdrop:SetTexCoord(unpack(SLOT_BACKDROP_COORDS))
    end
    PaintSlotIcon(slot)
end

local function PaintToggle(folded)
    local atlas = folded and "bag-arrow-2x" or "bag-arrow-invert-2x"
    for _, face in ipairs(toggleFaces) do
        face:SetAtlasTexture(atlas)
    end
end

-- ============================================================================
-- Layout
-- ============================================================================

local function Place()
    local backpack = MainMenuBarBackpackButton
    backpack:SetParent(bar)
    backpack:ClearAllPoints()
    backpack:SetPoint("RIGHT", bar, "RIGHT")

    local previous, gap, drop = backpack, BACKPACK_GAP, SLOT_DROP
    for _, slot in ipairs(slots) do
        slot:SetParent(bar)
        slot:ClearAllPoints()
        slot:SetPoint("RIGHT", previous, "LEFT", -gap, drop)
        previous, gap, drop = slot, SLOT_GAP, 0
    end
end

local function ApplyFold()
    local folded = Menu.Profile().bags_collapsed and true or false
    for _, slot in ipairs(slots) do
        if folded then
            slot:Hide()
        else
            slot:Show()
        end
    end
    toggle:SetChecked(folded and 1 or nil)
    PaintToggle(folded)
end

local function CreateToggle()
    toggle = CreateFrame("CheckButton", "MistUI_BagsToggle", bar)
    toggle:SetSize(TOGGLE_WIDTH, TOGGLE_HEIGHT)
    toggle:SetPoint("RIGHT", MainMenuBarBackpackButton, "LEFT", 0, SLOT_DROP)
    toggle:SetFrameLevel(MainMenuBarBackpackButton:GetFrameLevel() + 1)
    for _, name in ipairs({ "Normal", "Pushed", "Highlight" }) do
        local face = Face(toggle, name)
        face:SetAllPoints(toggle)
        toggleFaces[#toggleFaces + 1] = face
    end
    toggle:RegisterForClicks("LeftButtonUp")
    -- A check button flips its checked state before OnClick runs, so GetChecked is the new state.
    toggle:SetScript("OnClick", function(self)
        Menu.Profile().bags_collapsed = self:GetChecked() and true or false
        ApplyFold()
    end)
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Bags.Apply()
    bar = CreateFrame("Frame", "MistUI_BagButtonBar", UIParent)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    box = addon.CreateUIFrame(BAR_WIDTH, BAR_HEIGHT, "BagsBar")
    box:SetPoint(DEFAULT_ANCHOR, UIParent, DEFAULT_ANCHOR, DEFAULT_X, DEFAULT_Y)
    bar:SetPoint("RIGHT", box, "RIGHT")

    for index = 0, SLOT_COUNT - 1 do
        local slot = _G["CharacterBag" .. index .. "Slot"]
        slots[#slots + 1] = slot
        isSlot[slot] = true
    end

    Place()
    PaintBackpack()
    for _, slot in ipairs(slots) do
        PaintSlot(slot)
    end
    CreateToggle()

    hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
        if isSlot[button] then
            PaintSlotIcon(button)
        end
    end)

    addon:RegisterEditableFrame({
        name = KEY,
        frame = box,
        stockFrame = bar,
        configPath = { "widgets", KEY },
        module = Menu,
    })

    local hoverFrames = { bar, MainMenuBarBackpackButton, toggle }
    for _, slot in ipairs(slots) do
        hoverFrames[#hoverFrames + 1] = slot
    end
    Menu.RegisterFade(Bags.FADE_KEY, bar, hoverFrames)
end

function addon.RefreshBagsPosition()
    if not bar then
        return
    end
    local scale = Scale()
    bar:SetScale(scale)
    addon.SetEditorBoxScale(box, scale, "RIGHT")
    addon.ApplyWidgetPositionFromDB(KEY, box)
end

function addon.RefreshBagsVehicle()
    if bar then
        Menu.ApplyVisibilityDriver(bar, "bagsbar_vehicle", addon.RefreshBagsVehicle)
    end
end

function addon.RefreshBags()
    if not bar then
        return
    end
    addon.RefreshBagsPosition()
    ApplyFold()
    addon.RefreshBagsVehicle()
end
