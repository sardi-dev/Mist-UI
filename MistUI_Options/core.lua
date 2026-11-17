-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
MistUI Options - Core
================================================================================
This file provides the options registration system and initialization.
Inspired by the ElvUI_OptionsUI pattern - accesses MistUI addon via global.
================================================================================
]]

-- Access the main MistUI addon (exposed globally in MistUI/core.lua)
local addon = MistUI

-- Initialize localization before any fallback/error path uses it.
-- Load-on-demand, so unlike MistUI/config.lua this always sees the stored override.
local activeLocale = addon and addon.GetActiveLocale and addon.GetActiveLocale()
local L = LibStub("AceLocale-3.0-MistUI"):GetLocale("MistUI", activeLocale)
local LO = LibStub("AceLocale-3.0-MistUI"):GetLocale("MistUI_Options", activeLocale)

if not addon then
    print("|cFFFF0000[MistUI_Options]|r " .. ((LO and LO["Error: MistUI addon not found!"]) or "Error: MistUI addon not found!"))
    return
end

addon.LO = LO  -- Expose for other option files

-- Dropped reload-only changes: the open tab re-reads the saved values its toggles now show again.
addon.Reload.OnDiscard(function()
    local panel = addon.OptionsPanel
    if panel and panel.frame and panel.frame:IsShown() and panel.currentTab then
        panel:SelectTab(panel.currentTab)
    end
end)

StaticPopupDialogs["MISTUI_DELETE_PROFILE"] = {
    text = LO["Are you sure you want to delete the profile '%s'? This cannot be undone."],
    button1 = LO["Delete"],
    button2 = LO["Not Now"],
    OnAccept = function(self)
        local profileName = self.data
        if profileName and addon.db then
            addon.db:DeleteProfile(profileName, true)
            -- Left set, the next new character would recreate it empty.
            if addon.GetDefaultProfileKey and addon:GetDefaultProfileKey() == profileName then
                addon:SetDefaultProfileKey(nil)
            end
            addon:Print((LO["Deleted profile: "] or "Deleted profile: ") .. profileName)
            if addon.OptionsPanel then
                addon.OptionsPanel:SelectTab("profiles")
            end
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3
}

-- ============================================================================
-- INITIALIZE OPTIONS (called after all option files are loaded)
-- ============================================================================

function addon:InitializeOptions()
    -- Register a minimal BlizzOptions entry that redirects to the custom panel
    addon.Options.args.open_panel = {
        type = "execute",
        name = "|cff1784d1" .. (LO["Open MistUI Settings"] or "Open MistUI Settings") .. "|r",
        desc = LO["Open the MistUI configuration panel."] or "Open the MistUI configuration panel.",
        func = function()
            local AceConfigDialog = LibStub("AceConfigDialog-3.0")
            if AceConfigDialog then
                AceConfigDialog:Close("MistUI")
            end
            if addon.OptionsPanel then
                addon.OptionsPanel:Toggle()
            end
        end,
        order = 1,
        width = "full"
    }
    addon.Options.args.info = {
        type = "description",
        name = "\n" .. (LO["Use /mistui to open the full settings panel."] or "Use /mistui to open the full settings panel."),
        order = 2
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("MistUI", addon.Options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MistUI", "MistUI")

    addon.OptionsLoaded = true
end

-- Initialize when this addon finishes loading
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == "MistUI_Options" then
        addon:InitializeOptions()
        self:UnregisterAllEvents()
    end
end)
