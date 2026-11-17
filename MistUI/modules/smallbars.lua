-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Button sizes, spacing and default positions adapted from DragonUI (MIT, (c) 2026 NeticSoul);
-- see THIRD_PARTY_NOTICES.

-- Stance, pet and possess bars, and the button that leaves a vehicle which keeps the main bar:
-- The stock buttons in rows and a box of this addon's own. Part of the action
-- bar module, which starts it, and built the same way: every button stays a child of its stock
-- bar, which keeps deciding when the buttons are shown, and is only anchored to a box, resized
-- and restyled, outside combat. The stock bar art is made invisible.

local addon = select(2, ...)

local DEFAULT_SIZE, DEFAULT_SPACING = 31, 6
-- A pet bar that was never moved sits this far above a stance row that was never moved either.
local STACK_GAP = 5
local SHINE_INSET = 2
local LEAVE_KEY, LEAVE_LABEL = "vehicleExit", "VehicleExitOverlay"
local LEAVE_ANCHOR, LEAVE_X, LEAVE_Y = "BOTTOM", -251, 145
local LEAVE_BOX_MARGIN = 10
local FADE_FLAGS = { "show_on_hover", "show_in_combat", "hide_in_combat", "visibility_logic" }
local FADE_NUMBERS = { "shown_alpha", "hidden_alpha", "fade_in_duration", "fade_out_duration", "fade_out_delay" }

-- key: edit mode name and saved position; box: another row's box to share instead of an own one;
-- settings: table under additional; style: the function of buttons.lua that restyles the row.
local ROWS = {
    {
        key = "stance", label = "StanceOverlay", settings = "stance",
        prefix = "StanceButton", count = NUM_STANCE_SLOTS, frame = "StanceBarFrame",
        art = { "StanceBarLeft", "StanceBarMiddle", "StanceBarRight" },
        style = "StyleStanceButtons", sizeKey = "button_size", spacingKey = "button_spacing",
        anchor = "BOTTOM", x = -211, y = 145, boxSlots = 1,
    },
    {
        key = "petbar", label = "petbar", settings = "pet",
        prefix = "PetActionButton", count = NUM_PET_ACTION_SLOTS, frame = "PetActionBarFrame",
        art = { "SlidingActionBarTexture0", "SlidingActionBarTexture1" },
        style = "StylePetButtons", sizeKey = "size", spacingKey = "spacing", scaleKey = "scale",
        anchor = "BOTTOM", x = 1, y = 146,
    },
    {
        -- Shown instead of the stance row while the player controls another unit.
        key = "possess", box = "stance", settings = "stance",
        prefix = "PossessButton", count = NUM_POSSESS_SLOTS, frame = "PossessBarFrame",
        art = { "PossessBackground1", "PossessBackground2" },
        style = "StylePossessButtons", sizeKey = "button_size", spacingKey = "button_spacing",
    },
}

local Small = {}
addon.SmallBars = Small

local boxes = {}
local applied = false

local function Metrics(row)
    local additional = addon.db.profile.additional
    local settings = additional[row.settings] or {}
    return tonumber(settings[row.sizeKey]) or tonumber(additional.size) or DEFAULT_SIZE,
        tonumber(settings[row.spacingKey]) or tonumber(additional.spacing) or DEFAULT_SPACING,
        row.scaleKey and tonumber(settings[row.scaleKey]) or 1
end

local function RowWidth(count, size, spacing)
    return count * size + (count - 1) * spacing
end

local function LayoutRow(row)
    local size, spacing, scale = Metrics(row)
    local box = boxes[row.box or row.key]
    _G[row.frame]:SetScale(scale)
    for index = 1, row.count do
        local button = _G[row.prefix .. index]
        button:SetSize(size, size)
        local shine = _G[row.prefix .. index .. "Shine"]
        if shine then
            -- The autocast sparkle of a pet button runs just inside the button's edge.
            shine:SetSize(size - SHINE_INSET, size - SHINE_INSET)
        end
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", (index - 1) * (size + spacing), 0)
    end
    if not row.box then
        -- The stance box is one button wide and the row grows to its right, so its first
        -- button stands at the main bar's left end however many stances a class has.
        local count = row.boxSlots or row.count
        box:SetSize(RowWidth(count, size, spacing) * scale, size * scale)
    end
end

local function PlaceBoxes()
    for _, row in ipairs(ROWS) do
        local box = boxes[row.key]
        if box then
            box.MistUI_LayoutOffset = nil
            box:ClearAllPoints()
            box:SetPoint(row.anchor, UIParent, row.anchor, row.x, row.y)
            addon.ApplyWidgetPositionFromDB(row.key, box)
        end
    end

    local petBox = boxes.petbar
    if GetNumShapeshiftForms() > 0 and addon.IsWidgetAtDefaultPosition("petbar")
        and addon.IsWidgetAtDefaultPosition("stance") then
        local lift = boxes.stance:GetHeight() + STACK_GAP
        local point, relativeTo, relativePoint, x, y = petBox:GetPoint(1)
        petBox:SetPoint(point, relativeTo, relativePoint, x, y + lift)
        -- Tells the shared code that saves positions that this shift is not a move by the player.
        petBox.MistUI_LayoutOffset = { 0, lift }
    end

    local leaveBox = boxes[LEAVE_KEY]
    leaveBox:ClearAllPoints()
    leaveBox:SetPoint(LEAVE_ANCHOR, UIParent, LEAVE_ANCHOR, LEAVE_X, LEAVE_Y)
    addon.ApplyWidgetPositionFromDB(LEAVE_KEY, leaveBox)
end

-- The stock code anchors the leave button to the stance or possess buttons again whenever it
-- updates it. The button is not a protected frame, so it is put back from a hook, in combat too.
local function PlaceLeaveButton()
    MainMenuBarVehicleLeaveButton:ClearAllPoints()
    MainMenuBarVehicleLeaveButton:SetPoint("CENTER", boxes[LEAVE_KEY], "CENTER")
end

local function CreateLeaveBox()
    local size = MainMenuBarVehicleLeaveButton:GetWidth() + LEAVE_BOX_MARGIN
    local box = addon.CreateUIFrame(size, size, LEAVE_LABEL)
    boxes[LEAVE_KEY] = box
    addon:RegisterEditableFrame({
        name = LEAVE_KEY,
        frame = box,
        stockFrame = MainMenuBarVehicleLeaveButton,
        configPath = { "widgets", LEAVE_KEY },
        module = addon.MainbarsModule,
    })
    hooksecurefunc("MainMenuBarVehicleLeaveButton_Update", PlaceLeaveButton)
    PlaceLeaveButton()
end

local function HideStockArt(row)
    for _, name in ipairs(row.art) do
        -- The stock code shows these textures again by itself; invisible survives that.
        _G[name]:SetAlpha(0)
    end
    -- The stock bar is a strip that takes clicks where its buttons no longer are.
    _G[row.frame]:EnableMouse(false)
end

local function FadeConfig(row)
    return function()
        local settings = addon.db.profile.additional[row.settings] or {}
        local bars = addon.db.profile.actionbars or {}
        local config = {}
        for _, flag in ipairs(FADE_FLAGS) do
            config[flag] = settings[flag]
        end
        for _, number in ipairs(FADE_NUMBERS) do
            config["visibility_" .. number] = bars["visibility_" .. number]
        end
        return config
    end
end

-- A row that shares this row's box (possess with stance) fades with it.
local function RegisterFade(row)
    local buttons, sharing = {}, {}
    for _, other in ipairs(ROWS) do
        if other == row or other.box == row.key then
            for index = 1, other.count do
                buttons[#buttons + 1] = _G[other.prefix .. index]
            end
            if other ~= row then
                sharing[#sharing + 1] = _G[other.frame]
            end
        end
    end
    -- Only alpha is driven: the mouse state of secure buttons cannot change in combat.
    addon.VisibilityFade.Register(row.key, _G[row.frame], {
        frames = sharing,
        hoverFrames = buttons,
        enableMouse = false,
        dbTable = FadeConfig(row),
    })
end

local function Refresh()
    if not applied then
        return
    end
    if InCombatLockdown() then
        addon.CombatQueue:Add("smallbars_refresh", Refresh)
        return
    end
    for _, row in ipairs(ROWS) do
        LayoutRow(row)
        addon[row.style]()
        if not row.box then
            addon.VisibilityFade.Update(row.key)
        end
    end
    PlaceBoxes()
    addon.RefreshAdditionalBarHotkeys()
end

-- Called by the action bar module at login, outside combat.
function Small.Apply()
    for _, row in ipairs(ROWS) do
        HideStockArt(row)
        if not row.box then
            local box = addon.CreateUIFrame(DEFAULT_SIZE, DEFAULT_SIZE, row.label)
            boxes[row.key] = box
            addon:RegisterEditableFrame({
                name = row.key,
                frame = box,
                stockFrame = _G[row.frame],
                configPath = { "widgets", row.key },
                module = addon.MainbarsModule,
            })
            RegisterFade(row)
        end
    end
    CreateLeaveBox()
    applied = true

    -- Gaining or losing the stance row changes where the pet bar stacks.
    local events = CreateFrame("Frame")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    events:SetScript("OnEvent", Refresh)
    Refresh()
end

addon.RefreshStance = Refresh
addon.RefreshPetbarFrame = Refresh
addon.UpdateStanceBarPosition = Refresh
addon.UpdatePetbarPosition = Refresh
