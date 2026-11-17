-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
MistUI - Slash Commands
================================================================================
Centralized slash command handling for MistUI.
Slash-command layout inspired by ElvUI.
================================================================================
]]

local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- COMMAND HANDLERS
-- ============================================================================

-- Open configuration panel (uses ToggleOptionsUI which loads MistUI_Options)
local function OpenConfig(msg)
    addon:ToggleOptionsUI(msg)
end

-- Toggle editor/move mode
local function ToggleEditorMode()
    if InCombatLockdown() then
        addon:Print(L["Cannot toggle editor mode during combat!"])
        return
    end
    
    if addon.EditorMode then
        addon.EditorMode:Toggle()
    else
        addon:Print(L["Editor mode not available."])
    end
end

-- Reset all frame positions to defaults (widgets + the position keys the editor owns)
local function ResetPositions(arg)
    if InCombatLockdown() then
        addon:Print(L["Cannot reset positions during combat!"])
        return
    end

    -- No per-frame reset exists; EditorMode only resets the whole widget set.
    if arg and arg ~= "" then
        addon:Print(L["Reset only supports resetting every position at once. Use /mistui reset."])
        return
    end

    if addon.EditorMode then
        addon.EditorMode:ShowResetConfirmation()
    else
        addon:Print(L["Position editor not available."])
    end
end

-- Show module status
local function ShowStatus()
    addon:Print(L["=== MistUI Status ==="])
    
    -- Show registered modules from ModuleRegistry (if available)
    if addon.ModuleRegistry and addon.ModuleRegistry.Count and addon.ModuleRegistry:Count() > 0 then
        addon.ModuleRegistry:PrintStatus()
    else
        -- Fallback: Show manually detected modules
        print("  |cFF00FF00" .. L["Detected Modules:"] .. "|r")
        local modules = {
            { name = L["Main Bars"], check = function() return addon.RefreshMainbars end },
            { name = L["Buttons"], check = function() return addon.RefreshButtons end },
            { name = L["Micro Menu"], check = function() return addon.RefreshMicromenu end },
            { name = L["Minimap"], check = function() return addon.RefreshMinimap end },
            { name = L["Target Frame"], check = function() return addon.RefreshTargetFrame end },
            { name = L["Focus Frame"], check = function() return addon.RefreshFocusFrame end },
            { name = L["Party Frames"], check = function() return addon.RefreshPartyFrames end },
            { name = L["Stance Bar"], check = function() return addon.RefreshStance end },
            { name = L["Pet Bar"], check = function() return addon.RefreshPetbar end },
            { name = L["Cooldowns"], check = function() return addon.RefreshCooldowns end },
            { name = L["Buff Frame"], check = function() return addon.RefreshBuffFrame end },
            { name = L["Cast Bar"], check = function() return addon.RefreshCastbar end },
        }
        
        for _, module in ipairs(modules) do
            local status = module.check() and "|cFF00FF00" .. L["Loaded"] .. "|r" or "|cFFFF0000" .. L["Not Loaded"] .. "|r"
            print(string.format("    %s: %s", module.name, status))
        end
    end
    
    -- Show editable frames count
    if addon.EditableFrames then
        local count = 0
        for _ in pairs(addon.EditableFrames) do
            count = count + 1
        end
        print(string.format("  " .. L["Editable Frames: "] .. "|cFF00FF00%d|r", count))
    end
end

-- Reload UI shortcut
local function ReloadUICommand()
    ReloadUI()
end

local function SetDebugMode(arg)
    local normalized = arg and arg:lower() or ""

    if normalized == "" or normalized == "status" then
        addon:Print(string.format(L["Debug mode is %s"], addon.debugMode and L["enabled"] or L["disabled"]))
        return
    end

    if normalized == "on" or normalized == "true" or normalized == "1" then
        addon.debugMode = true
        addon:Print(L["Debug mode enabled"])
        return
    end

    if normalized == "off" or normalized == "false" or normalized == "0" then
        addon.debugMode = false
        addon:Print(L["Debug mode disabled"])
        return
    end

    addon:Print(L["Usage: /mistui debug on|off|status"])
end

local RECENT_ERRORS_SHOWN = 5

-- Show, clear or switch the error recorder (core/errorlog.lua)
local function ShowErrors(arg)
    local log = addon.ErrorLog
    local normalized = arg and arg:lower() or ""

    if normalized == "clear" then
        log.Clear()
        addon:Print(L["Error log cleared."])
        return
    end

    if normalized == "on" or normalized == "off" then
        log.SetEnabled(normalized == "on")
        addon:Print(string.format(L["Error log is %s"], log.IsEnabled() and L["enabled"] or L["disabled"]))
        return
    end

    local entries = log.GetEntries()
    addon:Print(string.format(L["Error log is %s, %d recorded. Usage: /mistui errors on|off|clear"],
        log.IsEnabled() and L["enabled"] or L["disabled"], #entries))
    for i = math.max(1, #entries - RECENT_ERRORS_SHOWN + 1), #entries do
        local entry = entries[i]
        print(string.format("  [%s] x%d %s", tostring(entry.time), tonumber(entry.count) or 1, tostring(entry.message)))
    end
end

local MOUSE_CHAIN_DEPTH = 5
-- Shorter waits are the pause after every spell, which never gets a number.
local COOLDOWN_REPORT_MINIMUM = 2

-- What the client reports for a button's cooldown, what the cooldown number last saw, and what it shows.
local function PrintCooldownState(button)
    local start, duration, enable, charges, maxCharges = GetActionCooldown(button.action)
    print(string.format("  %s: game %s+%s on %s ch %s/%s", button:GetName() or "?", tostring(start), tostring(duration),
        tostring(enable), tostring(charges), tostring(maxCharges)))
    local cooldown = button.cooldown
    if type(cooldown) ~= "table" then
        return
    end
    local label = cooldown.text
    print(string.format("    seen %s+%s ch %s/%s ends %s; number %s shown %s '%s'", tostring(cooldown._mistUI_cdStart),
        tostring(cooldown._mistUI_cdDur), tostring(cooldown._mistUI_cdCharges), tostring(cooldown._mistUI_cdMaxCharges),
        tostring(cooldown.remain), label and "made" or "never made", tostring(label and label:IsShown()),
        tostring(label and label:GetText())))
end

-- Lists every action bar button that is on cooldown, for reports of missing cooldown numbers.
local function ShowCooldowns()
    local settings = addon.db.profile.buttons.cooldown
    addon:Print(string.format("cooldowns: now %.1f, hooked %s, module on %s, minimum %s", GetTime(),
        tostring(addon.CooldownText and addon.CooldownText.hooked), tostring(addon.db.profile.modules.cooldowns.enabled),
        tostring(settings and settings.min_duration)))
    local text = addon.CooldownText
    for _, prefix in ipairs(text and text.ACTION_BAR_PREFIXES or {}) do
        for slot = 1, text.ACTION_BAR_SLOTS do
            local button = _G[prefix .. slot]
            if button and type(button.action) == "number" then
                local start, duration = GetActionCooldown(button.action)
                if type(start) == "number" and start > 0 and type(duration) == "number"
                    and duration >= COOLDOWN_REPORT_MINIMUM then
                    PrintCooldownState(button)
                end
            end
        end
    end
end

-- Names what takes the mouse at the pointer, for reports of buttons that do not react to clicks.
-- On an action button it also prints the cooldown values the client reports for it.
local function ShowMouseFocus()
    local frame = GetMouseFocus()
    if not frame then
        addon:Print(L["Nothing under the mouse takes clicks."])
        return
    end
    addon:Print(L["Under the mouse, topmost first:"])
    local button = type(frame.action) == "number" and frame or nil
    for _ = 1, MOUSE_CHAIN_DEPTH do
        if not frame then
            break
        end
        print(string.format("  %s (%s, %s, level %d)", frame:GetName() or "?", frame:GetObjectType(),
            frame.GetFrameStrata and frame:GetFrameStrata() or "?", frame.GetFrameLevel and frame:GetFrameLevel() or 0))
        frame = frame:GetParent()
    end
    if button then
        PrintCooldownState(button)
    end
end

-- Turns the nameplate module on or off at once, so a fault on the plates can be stopped mid-session.
local function SetNameplates(arg)
    local normalized = arg and arg:lower() or ""
    local cfg = addon:GetModuleConfig("nameplates")
    if not cfg or not addon.ApplyNameplatesSystem then
        addon:Print(L["Nameplates module not available."])
        return
    end
    if normalized ~= "on" and normalized ~= "off" then
        addon:Print(string.format(L["Nameplates are %s. Usage: /mistui nameplates on|off"],
            cfg.enabled ~= false and L["enabled"] or L["disabled"]))
        return
    end
    if InCombatLockdown() then
        addon:Print(L["Cannot change the nameplates during combat."])
        return
    end
    cfg.enabled = normalized == "on"
    if cfg.enabled then
        addon:ApplyNameplatesSystem()
    else
        addon:RestoreNameplatesSystem()
    end
    addon:Print(string.format(L["Nameplates are %s. Usage: /mistui nameplates on|off"],
        cfg.enabled and L["enabled"] or L["disabled"]))
end

-- The map keeps its hooks until a reload, so the switch is saved and applied by the next one.
local function SetWorldMap(arg)
    local normalized = arg and arg:lower() or ""
    local cfg = addon:GetModuleConfig("worldmap")
    if not cfg then
        addon:Print(L["World map module not available."])
        return
    end
    if normalized == "on" or normalized == "off" then
        cfg.enabled = normalized == "on"
        addon:Print(L["Type /reload to apply the change."])
    end
    addon:Print(string.format(L["The world map is %s. Usage: /mistui worldmap on|off"],
        cfg.enabled ~= false and L["enabled"] or L["disabled"]))
end

-- Print version info
local function ShowVersion()
    local version = GetAddOnMetadata("MistUI", "Version") or "Unknown"
    addon:Print(L["MistUI Version: "] .. version)
end

-- Show help
local function ShowHelp()
    addon:Print(L["=== MistUI Commands ==="])
    print("  " .. L["/mistui or /mist - Open configuration"])
    print("  " .. L["/mistui config - Open configuration"])
    print("  " .. L["/mistui edit - Toggle editor mode (move UI elements)"])
    print("  " .. L["/mistui reset - Reset all positions to defaults"])
    print("  " .. L["/mistui status - Show module status"])
    print("  " .. L["/mistui farm - Toggle farm mode (big minimap, chrome hidden)"])
    print("  " .. L["/mistui debug on|off|status - Toggle diagnostic logging"])
    print("  " .. L["/mistui errors - Show recorded MistUI errors (on|off|clear)"])
    print("  " .. L["/mistui mouse - Show what is under the mouse pointer"])
    print("  " .. L["/mistui plates - Save the layout of the name plates on screen"])
    print("  " .. L["/mistui nameplates on|off - Turn the nameplate module on or off"])
    print("  " .. L["/mistui perf - Measure where the addon spends its time"])
    print("  " .. L["/mistui worldmap on|off - Turn the new world map on or off (after a reload)"])
    print("  " .. L["/mistui version - Show version info"])
    print("  " .. L["/mistui help - Show this help"])
    print("  " .. L["/rl - Reload UI"])
end

-- ============================================================================
-- MAIN COMMAND HANDLER
-- ============================================================================

local function SlashCommandHandler(input)
    if not input or input:trim() == "" then
        OpenConfig()
        return
    end
    
    local cmd, arg = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    
    if cmd == "config" or cmd == "options" or cmd == "opt" then
        OpenConfig()
    elseif cmd == "edit" or cmd == "editor" or cmd == "move" or cmd == "moveui" then
        ToggleEditorMode()
    elseif cmd == "reset" then
        ResetPositions(arg)
    elseif cmd == "status" then
        ShowStatus()
    elseif cmd == "farm" or cmd == "farmmode" then
        if addon.MinimapModule and addon.MinimapModule.ToggleFarmMode then
            addon.MinimapModule:ToggleFarmMode()
        else
            addon:Print(L["Minimap module not available."])
        end
    elseif cmd == "debug" then
        SetDebugMode(arg)
    elseif cmd == "errors" or cmd == "error" then
        ShowErrors(arg)
    elseif cmd == "mouse" then
        ShowMouseFocus()
    elseif cmd == "cd" or cmd == "cooldowns" then
        ShowCooldowns()
    elseif cmd == "plates" then
        addon.PlateDump.Run()
    elseif cmd == "perf" then
        addon.Perf.Run()
    elseif cmd == "worldmap" or cmd == "map" then
        SetWorldMap(arg)
    elseif cmd == "nameplates" or cmd == "np" then
        SetNameplates(arg)
    elseif cmd == "version" or cmd == "ver" then
        ShowVersion()
    elseif cmd == "castlog" then
        local NP = addon.Nameplates
        if not (NP and NP.castbar and NP.castbar.SetCastLog) then
            addon:Print("Nameplate cast log not available")
            return
        end
        arg = arg and arg:lower() or ""
        if arg == "clear" then
            NP.castbar.SetCastLog("clear")
            addon:Print("Cast log cleared.")
        elseif arg == "on" or arg == "off" then
            NP.castbar.SetCastLog(arg == "on")
            addon:Print("Cast log " .. arg .. ". /reload to write it to SavedVariables.")
        else
            local log = _G.MistUIDB and _G.MistUIDB.castlog
            addon:Print(string.format("Cast log is %s, %d lines. Usage: /mist castlog on|off|clear",
                NP.castbar.IsCastLogOn() and "on" or "off", log and #log or 0))
        end
    elseif cmd == "unitcache" then
        local UC = addon.Nameplates and addon.Nameplates.unitcache
        if not UC then
            addon:Print("Nameplate unit cache not available")
            return
        end
        arg = arg and arg:trim() or ""
        if arg:lower() == "forget" then
            UC.Forget()
            addon:Print("Nameplate unit cache cleared")
        elseif arg ~= "" then
            addon:Print(arg .. ": " .. (UC.Describe(arg) or "not known"))
        else
            local s = UC.GetStats()
            addon:Print(string.format("Unit cache: %d players, %d guilds, %d titles, %d NPCs, %d GUIDs seen; active=%s remember=%s background=%s",
                s.players, s.guilds, s.titles, s.npcs, s.seenGUIDs, tostring(s.active), tostring(s.persist), tostring(s.background)))
        end
    elseif cmd == "npclamp" then
        local NP = addon.Nameplates
        if NP and NP.layout and NP.layout.DebugPrintClampState then
            NP.layout.DebugPrintClampState()
        else
            addon:Print("Nameplates clamp diagnostic not available")
        end
    elseif cmd == "help" or cmd == "?" then
        ShowHelp()
    else
        -- Unknown command
        addon:Print(L["Unknown command: "] .. cmd)
        ShowHelp()
    end
end

-- ============================================================================
-- COMMAND REGISTRATION
-- ============================================================================

local Commands = {}

function Commands:RegisterCommands()
    -- Register with AceConsole if available
    if addon.core and addon.core.RegisterChatCommand then
        -- Main commands
        addon.core:RegisterChatCommand("mistui", SlashCommandHandler)
        addon.core:RegisterChatCommand("mist", SlashCommandHandler)

        -- Quick reload
        addon.core:RegisterChatCommand("rl", ReloadUICommand)
    else
        -- Fallback to direct slash command registration
        SLASH_MISTUI1 = "/mistui"
        SLASH_MISTUI2 = "/mist"
        SlashCmdList["MISTUI"] = SlashCommandHandler
        
        SLASH_MISTUIRL1 = "/rl"
        SlashCmdList["MISTUIRL"] = ReloadUICommand
    end
end

-- Store reference for module access
addon.Commands = Commands

-- ============================================================================
-- INTEGRATION WITH CORE
-- ============================================================================

-- Override the SlashCommand function in core.lua
-- This will be called from core.lua's OnEnable
function addon.LoadCommands()
    Commands:RegisterCommands()
end

-- Also expose individual handlers for other modules
addon.CommandHandlers = {
    OpenConfig = OpenConfig,
    ToggleEditorMode = ToggleEditorMode,
    ResetPositions = ResetPositions,
    ShowStatus = ShowStatus,
    ShowVersion = ShowVersion,
    ShowHelp = ShowHelp
}
