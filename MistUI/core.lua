-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...);

--[[
================================================================================
MistUI - Core Initialization
================================================================================
This file handles the main addon initialization using AceAddon-3.0.
Utility functions have been moved to core/api.lua

Options are loaded on demand from MistUI_Options addon (inspired by ElvUI).
================================================================================
]]

-- Expose addon globally for MistUI_Options to access
_G.MistUI = addon

-- Localization (initialized early in config.lua so core/ files can use it)
local L = addon.L

-- Create addon object using AceAddon
addon.core = LibStub("AceAddon-3.0"):NewAddon("MistUI", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0");

-- Pre-define Options table (will be filled by MistUI_Options)
addon.Options = { type = "group", name = "MistUI", args = {} }

-- Track if options addon is loaded
addon.OptionsLoaded = false

function addon.core:OnInitialize()
    -- SavedVariables are loaded but AceDB is not, so read the account-wide setting
    -- straight off the table the way addon.GetActiveLocale does. AceDB consults this
    -- only for characters that have no profile yet, and New() errors on anything but
    -- a string or true - hence the type guard.
    local sv = _G.MistUIDB
    local defaultProfile = sv and sv.global and sv.global.defaultProfile
    if type(defaultProfile) ~= "string" or defaultProfile == "" then
        defaultProfile = nil
    end

    -- Replace the temporary addon.db with the real AceDB
    addon.db = LibStub("AceDB-3.0"):New("MistUIDB", addon.defaults, defaultProfile);

    -- First point where the stored language override is readable; UI is built later (PLAYER_LOGIN).
    addon.RefreshLocale()

    addon:ApplyDatabaseMigrations()

    -- Register callbacks for configuration changes
    addon.db.RegisterCallback(addon, "OnProfileChanged", "RefreshConfig");
    addon.db.RegisterCallback(addon, "OnProfileCopied", "RefreshConfig");
    addon.db.RegisterCallback(addon, "OnProfileReset", "RefreshConfig");

    -- Apply current profile configuration immediately
    -- This ensures the profile is loaded when the addon starts
    addon:RefreshConfig();
end

-- Account-wide default profile for characters that have never run MistUI.
-- Lives in global rather than a profile so it survives profile switch/copy/reset;
-- the raw fallback mirrors addon.GetActiveLocale for calls made before AceDB exists.
function addon:GetDefaultProfileKey()
    local key
    if addon.db and addon.db.global then
        key = addon.db.global.defaultProfile
    else
        local sv = _G.MistUIDB
        key = sv and sv.global and sv.global.defaultProfile
    end
    if type(key) == "string" and key ~= "" then
        return key
    end
    return nil
end

-- Pass nil or an empty string to go back to per-character profiles.
function addon:SetDefaultProfileKey(key)
    if not (addon.db and addon.db.global) then return end
    if type(key) == "string" and key ~= "" then
        addon.db.global.defaultProfile = key
    else
        addon.db.global.defaultProfile = nil
    end
end

function addon.core:OnEnable()
    addon.LoadCommands()

    -- Fire custom event to signal that MistUI is fully initialized
    -- This ensures modules get the correct config values
    self:SendMessage("MISTUI_READY");
end

-- ============================================================================
-- OPTIONS UI LOADING (inspired by ElvUI)
-- ============================================================================

function addon:ToggleOptionsUI(msg)
    if InCombatLockdown() then
        addon:Error(L["Cannot open options in combat."])
        return
    end

    if not IsAddOnLoaded("MistUI_Options") then
        local noConfig
        local reason = select(6, GetAddOnInfo("MistUI_Options"))
        
        if reason ~= "MISSING" and reason ~= "DISABLED" then
            LoadAddOn("MistUI_Options")
            
            -- Check if it actually loaded
            if not IsAddOnLoaded("MistUI_Options") then 
                noConfig = true 
            else
                addon.OptionsLoaded = true
            end
        else
            noConfig = true
        end

        if noConfig then
            addon:Error(L["Error -- Addon 'MistUI_Options' not found or is disabled."])
            if reason == "DISABLED" then
                addon:Print(L["Turn it back on from the AddOns list at character selection."])
            end
            return
        end
    end

    -- Use the custom panel
    if addon.OptionsPanel then
        addon.OptionsPanel:Toggle(msg)
    else
        addon:Error(L["Options panel not available. Try /reload."])
    end
end

-- Callback function that refreshes all modules when configuration changes
function addon:RefreshConfig()
    -- Also runs on profile switch: the newly-activated profile may be older than the current schema.
    addon:ApplyDatabaseMigrations()

    -- Initialize cooldown system if it hasn't been already
    if addon.InitializeCooldowns then
        addon.InitializeCooldowns()
    end

    local failed = addon:RefreshRegisteredSystems() or {}

    -- If some configurations failed, retry them after 2 seconds
    if #failed > 0 then
        addon.core:ScheduleTimer(function()
            addon:RefreshRegisteredSystems()
        end, 2);
    end
end
