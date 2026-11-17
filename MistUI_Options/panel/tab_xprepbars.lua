-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ============================================================================
-- MistUI Options - XP & Rep Bars Tab
-- ============================================================================
local addon = MistUI
if not addon then return end

local LO = addon.LO
local Panel = addon.OptionsPanel
local C = addon.PanelControls

-- Shared callback: refresh the entire XP/Rep bar system
local function RefreshBars()
    if addon.RefreshXpRepBars then addon.RefreshXpRepBars() end
end

local function BuildXpRepTab(scroll)
    -- ====================================================================
    -- BAR DIMENSIONS & SCALE
    -- ====================================================================
    local sizeSection = C:AddSection(scroll, LO["Size & Scale"])

    C:AddSlider(sizeSection, {
        label = LO["Bar Width"],
        desc = LO["Width of the XP and Reputation bars (in pixels)."],
        dbPath = "xprepbar.bar_width",
        min = 200, max = 1500, step = 1,
        width = 200,
        callback = RefreshBars,
    })

    C:AddSlider(sizeSection, {
        label = LO["Bar Height"],
        desc = LO["Height of the XP and Reputation bars (in pixels)."],
        dbPath = "xprepbar.bar_height_dfui",
        min = 6, max = 30, step = 1,
        width = 200,
        callback = RefreshBars,
    })

    C:AddSlider(sizeSection, {
        label = LO["Experience Bar Scale"],
        desc = LO["Scale of the experience bar."],
        dbPath = "xprepbar.expbar_scale",
        min = 0.5, max = 1.5, step = 0.05,
        width = 200,
        callback = RefreshBars,
    })

    C:AddSlider(sizeSection, {
        label = LO["Reputation Bar Scale"],
        desc = LO["Scale of the reputation bar."],
        dbPath = "xprepbar.repbar_scale",
        min = 0.5, max = 1.5, step = 0.05,
        width = 200,
        callback = RefreshBars,
    })

    -- ====================================================================
    -- RESTED XP INDICATORS
    -- ====================================================================
    local restedSection = C:AddSection(scroll, LO["Rested XP"])

    C:AddToggle(restedSection, {
        label = LO["Show Rested XP Background"],
        desc = LO["Display a translucent bar showing the total available rested XP range."],
        dbPath = "xprepbar.show_rested_bar",
        callback = RefreshBars,
    })

    C:AddToggle(restedSection, {
        label = LO["Show Rested XP Mark"],
        desc = LO["Show a mark on the XP bar where the rested XP ends."],
        dbPath = "xprepbar.show_rested_mark",
        callback = RefreshBars,
    })

    -- ====================================================================
    -- TEXT DISPLAY
    -- ====================================================================
    local textSection = C:AddSection(scroll, LO["Text Display"])

    C:AddToggle(textSection, {
        label = LO["Always Show Text"],
        desc = LO["Always display XP/Rep text instead of only on hover."],
        dbPath = "xprepbar.always_show_text",
        callback = RefreshBars,
    })

    C:AddToggle(textSection, {
        label = LO["Show XP Percentage"],
        desc = LO["Display XP percentage alongside the value text."],
        dbPath = "xprepbar.show_xp_percent",
        callback = RefreshBars,
    })

    -- ====================================================================
    -- VISIBILITY
    -- ====================================================================
    local visSection = C:AddSection(scroll, LO["Visibility"])
    C:AddVisibilityFadeToggles(visSection, {
        dbPrefix = "xprepbar",
        hoverDesc = LO["Fade the XP and Reputation bars until you hover over them."],
        combatDesc = LO["Fade the XP and Reputation bars until you enter combat."],
        hideInCombat = true,
        hideInCombatDesc = LO["Hide the XP and Reputation bars while in combat."],
        callback = RefreshBars,
    })
end

-- Register the tab (order 5 = after the action bars)
Panel:RegisterTab("xprepbars", LO["XP & Rep Bars"], BuildXpRepTab, 5)
