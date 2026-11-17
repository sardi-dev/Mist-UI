-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
MistUI Options Panel - Minimap Tab
================================================================================
Minimap scale, tracking, clock, display settings.
================================================================================
]]

local addon = MistUI
if not addon then return end

local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

-- ============================================================================
-- MINIMAP TAB BUILDER
-- ============================================================================

local function RefreshMinimap()
    if addon.RefreshMinimap then
        addon:RefreshMinimap()
        return
    end

    if addon.MinimapModule then
        addon.MinimapModule:UpdateSettings()
    end
end

local function IsCollectorEnabled()
    local enabled = C:GetDBValue("minimap.collector_enabled")
    if enabled == nil then
        return true
    end
    return enabled
end

local function SetSectionVisualState(section, enabled)
    if not section or Panel.indexing then
        return
    end

    C.SetSectionState(section, enabled)
end

local function BuildMinimapTab(scroll)
    -- ====================================================================
    -- COLLECTOR SETTINGS (TOP PRIORITY)
    -- ====================================================================
    local collector = C:AddSection(scroll, LO["Minimap Buttons Collector"])
    local collectorWidgets = {}
    local collectorStyleDropdown

    local function GetCollectorStyle()
        return C:GetDBValue("minimap.collector_style") or "mistui"
    end

    local function UpdateCollectorSectionState()
        if Panel.indexing then return end
        local enabled = IsCollectorEnabled()
        for _, widget in ipairs(collectorWidgets) do
            if widget and widget.SetDisabled then
                widget:SetDisabled(not enabled)
            end
        end
        if collectorStyleDropdown then
            collectorStyleDropdown:SetValue(GetCollectorStyle())
            collectorStyleDropdown:SetDisabled(not enabled)
        end
        SetSectionVisualState(collector, enabled)
    end

    C:AddToggle(collector, {
        label = LO["Enable"],
        dbPath = "minimap.collector_enabled",
        callback = function()
            UpdateCollectorSectionState()
            RefreshMinimap()
        end,
    })

    collectorStyleDropdown = C:AddDropdown(collector, {
        label = LO["Style"],
        values = {
            mistui = LO["Circle"],
            classic = LO["Arrow"],
        },
        width = 220,
        dbPath = "minimap.collector_style",
        getFunc = GetCollectorStyle,
        callback = RefreshMinimap,
    })

    UpdateCollectorSectionState()

    -- ====================================================================
    -- BASIC SETTINGS
    -- ====================================================================
    local basic = C:AddSection(scroll, LO["Basic Settings"])

    C:AddDropdown(basic, {
        label = LO["Style"],
        dbPath = "minimap.style",
        values = {
            mistui = LO["MistUI"],
            mistui_square = LO["MistUI Square"],
        },
        callback = RefreshMinimap,
    })

    C:AddSlider(basic, {
        label = LO["Scale"],
        dbPath = "minimap.scale",
        min = 0.5, max = 2.0, step = 0.01,
        width = 200,
        callback = RefreshMinimap,
    })

    C:AddSlider(basic, {
        label = LO["Border Alpha"],
        desc = LO["Top border alpha (0 to hide)."],
        dbPath = "minimap.border_alpha",
        min = 0, max = 1, step = 0.1,
        width = 200,
        callback = function()
            local val = C:GetDBValue("minimap.border_alpha") or 1
            if MinimapBorderTop then MinimapBorderTop:SetAlpha(val) end
        end,
    })

    C:AddToggle(basic, {
        label = LO["Addon Button Skin"],
        desc = LO["Apply MistUI border styling to addon icons."],
        dbPath = "minimap.addon_button_skin",
        callback = function()
            if addon.RefreshMinimap then addon:RefreshMinimap() end
        end,
    })

    C:AddToggle(basic, {
        label = LO["Addon Button Fade"],
        desc = LO["Addon icons fade out when not hovered."],
        dbPath = "minimap.addon_button_fade",
        callback = function()
            if addon.RefreshMinimap then addon:RefreshMinimap() end
        end,
    })

    C:AddToggle(basic, {
        label = LO["Show Ping Sender"],
        desc = LO["Show who pinged the minimap, in their class color."],
        dbPath = "minimap.ping_sender",
    })

    C:AddSlider(basic, {
        label = LO["Addon Button Distance"],
        desc = LO["Moves LibDBIcon addon buttons out from the minimap's edge, or in with a negative value."],
        dbPath = "minimap.addon_button_distance",
        min = -10, max = 20, step = 1,
        width = 200,
        callback = RefreshMinimap,
    })

    local farm = C:AddSection(scroll, LO["Farm Mode"])
    C:AddDescription(farm, LO["Bigger minimap with the surrounding clutter hidden."])

    C:AddToggle(farm, {
        label = LO["Enable"],
        dbPath = "minimap.farm_mode_enabled",
        callback = RefreshMinimap,
    })

    C:AddSlider(farm, {
        label = LO["Extra scale"],
        desc = LO["Extra scale applied on top of the minimap scale."],
        dbPath = "minimap.farm_mode_scale",
        min = 1.0, max = 2.0, step = 0.05,
        width = 200,
        callback = RefreshMinimap,
    })

    -- ====================================================================
    -- TIME & CALENDAR
    -- ====================================================================
    local time = C:AddSection(scroll, LO["Time & Calendar"])

    C:AddToggle(time, {
        label = LO["Show Clock"],
        dbPath = "minimap.clock",
        callback = RefreshMinimap,
    })

    C:AddToggle(time, {
        label = LO["Show Calendar"],
        dbPath = "minimap.calendar",
        callback = function()
            local val = C:GetDBValue("minimap.calendar")
            if GameTimeFrame then
                if val then GameTimeFrame:Show() else GameTimeFrame:Hide() end
            end
        end,
    })

    C:AddSlider(time, {
        label = LO["Clock Font Size"],
        dbPath = "minimap.clock_font_size",
        min = 8, max = 20, step = 1,
        width = 200,
        callback = RefreshMinimap,
    })

    -- ====================================================================
    -- DISPLAY SETTINGS
    -- ====================================================================
    local display = C:AddSection(scroll, LO["Display Settings"])

    C:AddToggle(display, {
        label = LO["Zoom Buttons"],
        desc = LO["Show zoom buttons (+/-)."],
        dbPath = "minimap.zoom_buttons",
        callback = RefreshMinimap,
    })

    C:AddSlider(display, {
        label = LO["Zone Text Font Size"],
        desc = LO["Font size of the zone text above the minimap."],
        dbPath = "minimap.zonetext_font_size",
        min = 8, max = 20, step = 1,
        width = 200,
        callback = RefreshMinimap,
    })

    -- ====================================================================
    -- VISIBILITY (EXPERIMENTAL)
    -- ====================================================================
    local visibility = C:AddSection(scroll, LO["Visibility"])

    C:AddDescription(visibility,
        "|cFFFFAA00" .. LO["Experimental:"] .. "|r " ..
        LO["Fading the minimap can occasionally cause tracking icons to stop updating until you /reload. Use at your own risk."])

    local function SyncMinimapVisibilityOption()
        if addon.MinimapModule and addon.MinimapModule.SyncMinimapVisibility then
            addon.MinimapModule.SyncMinimapVisibility()
        end
    end

    -- Built manually (not via C:AddVisibilityFadeToggles) so "Hide in Combat" can sit right after
    -- "Show in Combat Only" instead of after the AND/OR dropdown.
    C:AddToggle(visibility, {
        label = LO["Show on Hover Only"],
        desc = LO["Fade the minimap until you hover over it."],
        dbPath = "minimap.show_on_hover",
        callback = SyncMinimapVisibilityOption,
    })

    C:AddToggle(visibility, {
        label = LO["Show in Combat Only"],
        desc = LO["Fade the minimap until you enter combat."],
        dbPath = "minimap.show_in_combat",
        callback = function()
            local conflicted = C:GetDBValue("minimap.show_in_combat") and C:GetDBValue("minimap.hide_in_combat")
            if conflicted then
                C:SetDBValue("minimap.hide_in_combat", false)
            end
            SyncMinimapVisibilityOption()
            if conflicted and Panel.currentTab then Panel:SelectTab(Panel.currentTab) end
        end,
    })

    C:AddToggle(visibility, {
        label = LO["Hide in Combat"],
        desc = LO["Hide the minimap while in combat."],
        dbPath = "minimap.hide_in_combat",
        callback = function()
            local conflicted = C:GetDBValue("minimap.hide_in_combat") and C:GetDBValue("minimap.show_in_combat")
            if conflicted then
                C:SetDBValue("minimap.show_in_combat", false)
            end
            SyncMinimapVisibilityOption()
            if conflicted and Panel.currentTab then Panel:SelectTab(Panel.currentTab) end
        end,
    })

    C:AddDropdown(visibility, {
        label = LO["Hover/Combat Logic"],
        desc = LO["When both hover and combat are enabled, choose whether both are required (AND) or either condition is enough (OR)."],
        dbPath = "minimap.visibility_logic",
        values = {
            ["and"] = LO["AND (both required)"],
            ["or"] = LO["OR (either condition)"],
        },
        callback = SyncMinimapVisibilityOption,
    })
end

-- Register the tab
Panel:RegisterTab("minimap", LO["Minimap"], BuildMinimapTab, 8)

