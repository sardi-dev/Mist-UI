-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- Profile per specialization: each spec of a character can name a profile. A profile only takes
-- full effect after a reload (no module is proven to re-read every key on a live switch), so a
-- spec change offers the switch and the reload together instead of doing it silently.

local addon = select(2, ...)
local L = addon.L

local POPUP = "MISTUI_SPEC_PROFILE"

local SpecProfiles = {}
addon.SpecProfiles = SpecProfiles

-- Per character: { enabled = bool, [specIndex] = profileName }.
function SpecProfiles.Settings()
    local db = addon.db
    if not db or not db.char then return nil end
    db.char.specProfiles = db.char.specProfiles or {}
    return db.char.specProfiles
end

local function ProfileExists(name)
    for _, profile in ipairs(addon.db:GetProfiles()) do
        if profile == name then return true end
    end
    return false
end

-- The profile the current spec asks for, when it differs from the active one; nil otherwise.
function SpecProfiles.WantedProfile()
    local settings = SpecProfiles.Settings()
    if not (settings and settings.enabled) then return nil end
    local spec = GetSpecialization()
    local wanted = spec and settings[spec]
    if not wanted or wanted == "" or wanted == addon.db:GetCurrentProfile() or not ProfileExists(wanted) then
        return nil
    end
    return wanted
end

StaticPopupDialogs[POPUP] = {
    text = L["This specialization uses the MistUI profile \"%s\". Switch to it now? The interface reloads."],
    button1 = L["Switch and Reload"],
    button2 = L["Not Now"],
    OnAccept = function(_, profile)
        addon.db:SetProfile(profile)
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function SpecProfiles.Check()
    local wanted = SpecProfiles.WantedProfile()
    if not wanted then return end
    -- The reload would drop the fight's state, and the popup should not cover the screen in combat.
    if InCombatLockdown() then
        addon.CombatQueue:Add("spec_profile_check", SpecProfiles.Check)
        return
    end
    StaticPopup_Show(POPUP, wanted, nil, wanted)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Once per session: the character's spec is known by then, and later loading screens change nothing.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif unit and unit ~= "player" then
        return
    end
    addon:SafeExecute("spec_profiles", "check", SpecProfiles.Check)
end)
