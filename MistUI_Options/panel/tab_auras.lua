-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
MistUI Options Panel - Auras Tab
================================================================================
Player buff/debuff layout, weapon enchants, aura borders, and target/focus auras.
================================================================================
]]

local addon = MistUI
if not addon then return end

local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

local function RefreshTargetFocusAuraLayout()
    if addon.RefreshTargetFocusAuraLayout then
        addon.RefreshTargetFocusAuraLayout()
    end
end

local function RefreshFocusFrame()
    if addon.RefreshFocusFrame then addon.RefreshFocusFrame() end
end

-- Discrete steps mapped to real wrap math: N per full 122px row -> size = floor(125/N) - 3; 6 = stock 17px.
local function PerRowToSize(perRow)
    return math.floor(125 / perRow) - 3
end

local function SizeToPerRow(size)
    if not size or size <= 0 then
        size = 17
    end
    local perRow = math.floor(125 / (size + 3))
    if perRow < 4 then perRow = 4 end
    if perRow > 8 then perRow = 8 end
    return perRow
end

-- Reflects the effective layout size (icon_size x icon_scale), matching GetCustomAuraSizes in target.lua.
local function EffectivePerRow(auraCfg)
    local size = tonumber(auraCfg and auraCfg.icon_size) or 0
    local scale = tonumber(auraCfg and auraCfg.icon_scale) or 1
    if size <= 0 then
        size = 17
    end
    return SizeToPerRow(math.floor(size * scale + 0.5))
end

local function RefreshPlayerAuraSpacing()
    if addon.BuffFrameModule and addon.BuffFrameModule.RefreshAuraSpacing then
        addon.BuffFrameModule:RefreshAuraSpacing()
        return
    end

    if BuffFrame_UpdateAllBuffAnchors then
        BuffFrame_UpdateAllBuffAnchors()
    end
    if addon.BuffFrameModule then
        addon.BuffFrameModule:UpdatePosition()
    end
end

-- The icon sizes keep the upstream "auracooldowns" key: target.lua reads them from there.
local function GetAuraIconConfig()
    local modules = addon.db and addon.db.profile and addon.db.profile.modules
    modules = modules or {}
    modules.auracooldowns = modules.auracooldowns or {}
    modules.auracooldowns.buffs = modules.auracooldowns.buffs or {}
    modules.auracooldowns.debuffs = modules.auracooldowns.debuffs or {}
    return modules.auracooldowns
end

local function IsIconCustomizationEnabled()
    return GetAuraIconConfig().icons_enabled == true
end

local function SetIconCustomizationEnabled(value)
    local cfg = GetAuraIconConfig()
    cfg.icons_enabled = value and true or false
    cfg.enabled = cfg.icons_enabled
end

local function ResetAuraIconSettings()
    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.modules
        and addon.defaults.profile.modules.auracooldowns
    if not defaults then return end

    local cfg = GetAuraIconConfig()
    cfg.buffs = addon.DeepCopy(defaults.buffs or {}, {})
    cfg.debuffs = addon.DeepCopy(defaults.debuffs or {}, {})
    SetIconCustomizationEnabled(defaults.icons_enabled == true)
end

-- ============================================================================
-- AURAS TAB BUILDER
-- ============================================================================

local function GetAuraBordersField(field)
    local m = addon.db.profile.modules
    return m and m.auraborders and m.auraborders[field]
end

local function IsAuraBordersEnabled()
    return GetAuraBordersField("enabled") == true
end

local function RefreshAuraBorders()
    if addon.RefreshAuraBordersSystem then
        addon.RefreshAuraBordersSystem()
    end
end

-- Dropdown index order; options dropdowns list entries by key.
local BORDER_STYLES = { "detailed", "rounded", "square" }

-- Detailed keeps the untinted action-bar art, so the buff color only drives Rounded and Square.
local function IsBuffColorDisabled()
    local style = GetAuraBordersField("border_style")
    return not IsAuraBordersEnabled() or (style ~= "rounded" and style ~= "square")
end

-- ============================================================================
-- ACTIVE SUB-TAB STATE
-- ============================================================================

local activeSubTab = "player"

local subTabs = {
    { key = "player", label = LO["Player"] },
    { key = "targetfocus", label = LO["Target"] .. " / " .. LO["Focus"] },
}

-- Search navigation sub-tab setter.
Panel.subTabSetters = Panel.subTabSetters or {}
Panel.subTabSetters["auras"] = function(key) activeSubTab = key or "player" end

-- Borders and tooltips reach every aura icon, so they sit above the sub-tabs.
local function BuildAuraStyle(scroll)
    -- ====================================================================
    -- AURA BORDERS
    -- ====================================================================
    local borderSection = C:AddSection(scroll, LO["Aura Borders"])

    C:AddToggle(borderSection, {
        label = LO["Enable Aura Borders"],
        desc = LO["Show modern borders around buff and debuff icons."],
        getFunc = function() return IsAuraBordersEnabled() end,
        setFunc = function(val)
            C:EnsureModuleTable("auraborders").enabled = val
        end,
        callback = function()
            RefreshAuraBorders()
            -- Rebuild so the style dropdown / color enable-state refresh at once.
            Panel:SelectTab("auras")
        end,
        requiresReload = false,
    })

    local buffColorPicker

    C:AddDropdown(borderSection, {
        label = LO["Border Style"],
        values = {
            [1] = LO["Detailed"],
            [2] = LO["Rounded"],
            [3] = LO["Square"],
        },
        getFunc = function()
            local style = GetAuraBordersField("border_style")
            for index, key in ipairs(BORDER_STYLES) do
                if key == style then return index end
            end
            return 1
        end,
        setFunc = function(val)
            C:EnsureModuleTable("auraborders").border_style = BORDER_STYLES[val] or BORDER_STYLES[1]
        end,
        callback = function()
            RefreshAuraBorders()
            if buffColorPicker and buffColorPicker.SetDisabled then
                buffColorPicker:SetDisabled(IsBuffColorDisabled())
            end
        end,
        disabled = function() return not IsAuraBordersEnabled() end,
        width = 200,
    })

    buffColorPicker = C:AddColorPicker(borderSection, {
        label = LO["Buff Border Color"],
        getFunc = function()
            local c = GetAuraBordersField("buff_color")
            if c and c.r then return c.r, c.g, c.b end
            return 0.2, 0.2, 0.2
        end,
        setFunc = function(r, g, b)
            local ab = C:EnsureModuleTable("auraborders")
            ab.buff_color = { r = r, g = g, b = b }
        end,
        callback = RefreshAuraBorders,
        disabled = IsBuffColorDisabled,
        hasAlpha = false,
    })

    C:AddSpacer(scroll)

    -- ====================================================================
    -- AURA TOOLTIPS
    -- ====================================================================
    local tooltipSection = C:AddSection(scroll, LO["Aura Tooltips"])

    C:AddToggle(tooltipSection, {
        label = LO["Show Spell IDs"],
        desc = LO["Show spell IDs on aura, spell and chat-link tooltips. Requires the Tooltip module."],
        getFunc = function()
            local tt = addon.db.profile.modules and addon.db.profile.modules.tooltip
            return tt and tt.show_aura_spell_id == true
        end,
        setFunc = function(val)
            C:EnsureModuleTable("tooltip").show_aura_spell_id = val
        end,
        disabled = function()
            local tt = addon.db.profile.modules and addon.db.profile.modules.tooltip
            return not (tt and tt.enabled == true)
        end,
        requiresReload = false,
    })

    C:AddSpacer(scroll)
end

local function BuildPlayerAuras(scroll)
    -- ====================================================================
    -- WEAPON ENCHANTS
    -- ====================================================================
    local weaponSection = C:AddSection(scroll, LO["Weapon Enchants"])

    C:AddDescription(weaponSection,
        LO["Weapon enchant icons include rogue poisons, sharpening stones, wizard oils, and similar temporary weapon enhancements."])

    C:AddToggle(weaponSection, {
        label = LO["Separate Weapon Enchants"],
        desc = LO["Detach weapon enchant icons (poisons, sharpening stones, etc.) from the buff bar into their own independently moveable frame. Position it freely using Editor Mode."],
        getFunc = function()
            return addon.db.profile.buffs and addon.db.profile.buffs.separate_weapon_enchants
        end,
        setFunc = function(val)
            if not addon.db.profile.buffs then addon.db.profile.buffs = {} end
            addon.db.profile.buffs.separate_weapon_enchants = val
        end,
        callback = function(val)
            if addon.BuffFrameModule then
                addon.BuffFrameModule:ToggleWeaponEnchantSeparation(val)
            end
        end,
        requiresReload = false,
    })

    C:AddDescription(weaponSection,
        "|cff888888" .. LO["When enabled, a 'Weapon Enchants' mover appears in Editor Mode that you can drag to any position on screen."] .. "|r")

    C:AddSpacer(scroll)
    local playerAuraSection = C:AddSection(scroll, LO["Player Buffs & Debuffs"])

    C:AddDescription(playerAuraSection,
        LO["Layout settings for the player buff and debuff bar. These do not affect target or focus auras."])

    C:AddToggle(playerAuraSection, {
        label = LO["Show Toggle Button"],
        desc = LO["Show a collapse/expand button next to the buff icons."],
        dbPath = "buffs.show_toggle_button",
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddHeading(playerAuraSection, LO["Buffs"])

    C:AddDropdown(playerAuraSection, {
        label = LO["Buff Order"],
        desc = LO["How to sort player buff icons on the buff bar."],
        dbPath = "buffs.buff_order",
        values = {
            stock = LO["Default Order"],
            player_first = LO["Player Buffs First"],
            other_first = LO["Other Player Buffs First"],
            duration = LO["Duration Buffs First"],
        },
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Buff Icon Scale"],
        dbPath = "buffs.buff_scale",
        min = 0.5, max = 2, step = 0.05,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Buffs Per Row"],
        desc = LO["How many buff icons to show in each row."],
        dbPath = "buffs.buffs_per_row",
        min = 1, max = 32, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Max Buff Rows"],
        desc = LO["Maximum number of buff rows to display. Use 0 for no limit."],
        dbPath = "buffs.max_buff_rows",
        min = 0, max = 10, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Buff Horizontal Gap"],
        dbPath = "buffs.buff_horizontal_gap",
        min = 0, max = 20, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Buff Vertical Gap"],
        desc = LO["Space between buff rows."],
        dbPath = "buffs.buff_vertical_gap",
        min = 0, max = 40, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddHeading(playerAuraSection, LO["Debuffs"])

    C:AddToggle(playerAuraSection, {
        label = LO["Show Debuffs"],
        desc = LO["Show your debuffs on the player aura bar."],
        dbPath = "buffs.show_debuffs",
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Debuff Icon Scale"],
        dbPath = "buffs.debuff_scale",
        min = 0.5, max = 2, step = 0.05,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Debuffs Per Row"],
        desc = LO["How many debuff icons to show in each row."],
        dbPath = "buffs.debuffs_per_row",
        min = 1, max = 32, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Max Debuff Rows"],
        desc = LO["Maximum number of debuff rows to display. Use 0 for no limit."],
        dbPath = "buffs.max_debuff_rows",
        min = 0, max = 10, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Debuff Horizontal Gap"],
        dbPath = "buffs.debuff_horizontal_gap",
        min = 0, max = 20, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Debuff Vertical Gap"],
        desc = LO["Space between debuff rows."],
        dbPath = "buffs.debuff_vertical_gap",
        min = 0, max = 40, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Debuff Attached Offset Y"],
        desc = LO["Vertical gap below the buff bar when debuffs are attached (not detached in Editor Mode)."],
        dbPath = "buffs.debuff_offset_y",
        min = 0, max = 120, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddHeading(playerAuraSection, LO["Layout Preview"])

    C:AddDescription(playerAuraSection,
        LO["Shows fake buff and debuff icons so you can tune scale, rows, and spacing without needing real auras. Turn this off when finished."])

    C:AddToggle(playerAuraSection, {
        label = LO["Enable Layout Preview"],
        dbPath = "buffs.layout_preview",
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Preview Buff Count"],
        dbPath = "buffs.layout_preview_buffs",
        min = 0, max = 64, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSection, {
        label = LO["Preview Debuff Count"],
        dbPath = "buffs.layout_preview_debuffs",
        min = 0, max = 40, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })


    -- ====================================================================
    -- RESET POSITION
    -- ====================================================================
    C:AddSpacer(scroll)
    local resetSection = C:AddSection(scroll, LO["Positions"])

    C:AddButton(resetSection, {
        label = LO["Reset Buff Frame Position"],
        width = 220,
        callback = function()
            if addon.BuffFrameModule then
                addon.BuffFrameModule:ResetBuffFramePosition()
            end
            addon:Print(LO["Buff frame position reset."])
        end,
    })

    C:AddButton(resetSection, {
        label = LO["Reset Weapon Enchant Position"],
        width = 220,
        callback = function()
            if addon.db.profile.widgets and addon.db.profile.widgets.weapon_enchants then
                local w = addon.db.profile.widgets.weapon_enchants
                w.anchor = "TOPRIGHT"
                w.posX = -100
                w.posY = -15
                w.custom_position = false
            end
            if addon.BuffFrameModule then
                addon.BuffFrameModule:UpdateWeaponEnchantPosition()
            end
            addon:Print(LO["Weapon enchant position reset."])
        end,
    })

    C:AddSpacer(resetSection)

    local isDebuffDetached = C:GetDBValue("widgets.debuffs.custom_position")
    if isDebuffDetached then
        C:AddDescription(resetSection, "|cff" .. C.Theme.accentHex .. "- " .. LO["Debuffs detached - positioned freely via Editor Mode"] .. "|r")
    else
        C:AddDescription(resetSection, "|cffaaaaaa- " .. LO["Debuffs attached - follow buff row"] .. "|r")
    end

    C:AddButton(resetSection, {
        label = LO["Reset Debuff Position"],
        width = 220,
        disabled = function()
            return not C:GetDBValue("widgets.debuffs.custom_position")
        end,
        callback = function()
            if addon.BuffFrameModule then
                addon.BuffFrameModule:ResetDebuffPosition()
            end
            addon:Print(LO["Debuff position reset."])
            Panel:SelectTab("auras")
        end,
    })
end

local function BuildTargetFocusAuras(scroll)
    -- ====================================================================
    -- TARGET/FOCUS AURA CUSTOMIZATION
    -- ====================================================================
    -- Same settings as the Unit Frames sub-tabs (one database key each), repeated here where the aura options live.
    local showSection = C:AddSection(scroll, LO["Show Auras"])

    C:AddHeading(showSection, LO["Target"])
    C:AddToggle(showSection, {
        label = LO["Show Buffs"],
        desc = LO["Show the buffs under the target frame."],
        dbPath = "unitframe.target.show_buffs",
        callback = RefreshTargetFocusAuraLayout,
    })
    C:AddToggle(showSection, {
        label = LO["Show Debuffs"],
        desc = LO["Show the debuffs under the target frame."],
        dbPath = "unitframe.target.show_debuffs",
        callback = RefreshTargetFocusAuraLayout,
    })

    C:AddHeading(showSection, LO["Focus"])
    C:AddToggle(showSection, {
        label = LO["Show Buff/Debuff on Focus"],
        desc = LO["Uses the native large focus frame mode to show buffs and debuffs on the focus frame."],
        dbPath = "unitframe.focus.show_buff_debuff",
        callback = RefreshFocusFrame,
    })

    C:AddSpacer(scroll)
    local dynamicWidgets = {}
    local isRefreshingAuraWidgets = false

    local function RegisterDynamicWidget(widget, disabledFunc, valueFunc)
        table.insert(dynamicWidgets, { widget = widget, disabledFunc = disabledFunc, valueFunc = valueFunc })
        return widget
    end

    local function RefreshAuraControlStates()
        isRefreshingAuraWidgets = true
        for _, entry in ipairs(dynamicWidgets) do
            if entry.widget and entry.widget.SetValue and entry.valueFunc then
                entry.widget:SetValue(entry.valueFunc())
            end
            if entry.widget and entry.widget.SetDisabled and entry.disabledFunc then
                entry.widget:SetDisabled(entry.disabledFunc())
            end
        end
        isRefreshingAuraWidgets = false
    end

    local function RefreshAuraUI()
        RefreshAuraControlStates()
        RefreshTargetFocusAuraLayout()
    end

    local iconSection = C:AddSection(scroll, LO["Aura Icon Customization"])

    C:AddDescription(iconSection, LO["Customize icon size and scale for target/focus auras."])

    RegisterDynamicWidget(C:AddToggle(iconSection, {
        label = LO["Customize Aura Icons"],
        desc = LO["Enable custom icon styling for target/focus aura icons."],
        getFunc = IsIconCustomizationEnabled,
        setFunc = function(val)
            SetIconCustomizationEnabled(val)
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
        requiresReload = false,
    }), nil, function()
        return IsIconCustomizationEnabled()
    end)

    C:AddHeading(iconSection, LO["Aura Size"])

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Auras Per Row"],
        desc = LO["Discrete size steps: how many auras fit in a full-width row. 6 is the stock default (17px). Your own auras render slightly larger, and rows beside a visible Target-of-Target are narrower, so fewer may fit there."],
        min = 4, max = 8, step = 1,
        width = 220,
        getFunc = function()
            return EffectivePerRow(GetAuraIconConfig().buffs)
        end,
        setFunc = function(value)
            local size = PerRowToSize(value)
            local cfg = GetAuraIconConfig()
            cfg.buffs.icon_size = size
            cfg.debuffs.icon_size = size
        end,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return EffectivePerRow(GetAuraIconConfig().buffs)
    end)

    C:AddHeading(iconSection, LO["Aura Buffs"])

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Buff Icon Size"],
        dbPath = "modules.auracooldowns.buffs.icon_size",
        min = 0, max = 64, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraIconConfig().buffs.icon_size
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Buff Icon Scale"],
        dbPath = "modules.auracooldowns.buffs.icon_scale",
        min = 0.5, max = 3, step = 0.01,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraIconConfig().buffs.icon_scale
    end)

    C:AddHeading(iconSection, LO["Aura Debuffs"])

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Debuff Icon Size"],
        dbPath = "modules.auracooldowns.debuffs.icon_size",
        min = 0, max = 64, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraIconConfig().debuffs.icon_size
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Debuff Icon Scale"],
        dbPath = "modules.auracooldowns.debuffs.icon_scale",
        min = 0.5, max = 3, step = 0.01,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraIconConfig().debuffs.icon_scale
    end)

    C:AddSpacer(iconSection)

    C:AddButton(iconSection, {
        label = LO["Reset Aura Customization"],
        width = 220,
        callback = function()
            ResetAuraIconSettings()
            RefreshAuraUI()
            addon:Print(LO["Aura icon customization settings reset."])
        end,
    })

    RefreshAuraControlStates()
end

local subTabBuilders = {
    player = BuildPlayerAuras,
    targetfocus = BuildTargetFocusAuras,
}

local function BuildAurasTab(scroll)
    BuildAuraStyle(scroll)

    C:AddSubTabs(scroll, subTabs, activeSubTab, function(key)
        activeSubTab = key
        Panel:SelectTab("auras")
    end, subTabBuilders)

    if not Panel.indexing then
        local builder = subTabBuilders[activeSubTab]
        if builder then builder(scroll) end
    end
end

-- Register the tab (order 12 - after Enhancements, before Profiles)
Panel:RegisterTab("auras", LO["Auras"], BuildAurasTab, 12)
