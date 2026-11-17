-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ============================================================================
-- MistUI Options - Additional Bars Tab
-- ============================================================================
-- The stance row (which the possess row shares) and the pet bar of smallbars.lua.
local addon = MistUI
if not addon then return end

local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

-- One refresh lays out, restyles and fades every row.
local function RefreshRows()
    if addon.RefreshStance then addon.RefreshStance() end
end

local function RefreshHotkeys()
    if addon.RefreshAdditionalBarHotkeys then addon.RefreshAdditionalBarHotkeys() end
end

-- The pet bar has no size of its own until one is set; the row then uses the shared one.
local function PetValue(key, fallback)
    local additional = addon.db.profile.additional
    local value = additional.pet and additional.pet[key]
    if value == nil then value = additional[key] end
    return tonumber(value) or fallback
end

local function PetSlider(section, label, key, fallback)
    C:AddSlider(section, {
        label = label,
        getFunc = function() return PetValue(key, fallback) end,
        setFunc = function(value)
            local additional = addon.db.profile.additional
            additional.pet = additional.pet or {}
            additional.pet[key] = value
        end,
        min = key == "size" and 16 or 0, max = key == "size" and 64 or 20, step = 1,
        width = 200,
        callback = RefreshRows,
    })
end

local function BuildAdditionalBarsTab(scroll)
    C:AddDescription(scroll, LO["Bars that appear based on your class and situation."])

    local stance = C:AddSection(scroll, LO["Stance Bar"])

    C:AddToggle(stance, {
        label = LO["Show Hotkey Text"],
        dbPath = "additional.stance.show_hotkey",
        callback = RefreshHotkeys,
    })

    C:AddSlider(stance, {
        label = LO["Button Size"],
        dbPath = "additional.stance.button_size",
        min = 16, max = 64, step = 1,
        width = 200,
        callback = RefreshRows,
    })

    C:AddSlider(stance, {
        label = LO["Button Spacing"],
        dbPath = "additional.stance.button_spacing",
        min = 0, max = 20, step = 1,
        width = 200,
        callback = RefreshRows,
    })

    C:AddHeading(stance, LO["Visibility"])
    C:AddVisibilityFadeToggles(stance, {
        dbPrefix = "additional.stance",
        hoverDesc = LO["Fade the stance bar until you hover over it."],
        combatDesc = LO["Fade the stance bar until you enter combat."],
        callback = RefreshRows,
    })

    local pet = C:AddSection(scroll, LO["Pet Bar"])

    C:AddToggle(pet, {
        label = LO["Show Hotkey Text"],
        dbPath = "additional.pet.show_hotkey",
        callback = RefreshHotkeys,
    })

    C:AddSlider(pet, {
        label = LO["Scale"],
        dbPath = "additional.pet.scale",
        min = 0.5, max = 2.0, step = 0.05,
        width = 200,
        callback = RefreshRows,
    })

    PetSlider(pet, LO["Button Size"], "size", 31)
    PetSlider(pet, LO["Button Spacing"], "spacing", 6)

    C:AddHeading(pet, LO["Visibility"])
    C:AddVisibilityFadeToggles(pet, {
        dbPrefix = "additional.pet",
        hoverDesc = LO["Fade the pet bar until you hover over it."],
        combatDesc = LO["Fade the pet bar until you enter combat."],
        callback = RefreshRows,
    })
end

-- Right after Action Bars, before XP & Rep Bars.
Panel:RegisterTab("additionalbars", LO["Additional Bars"], BuildAdditionalBarsTab, 4)
