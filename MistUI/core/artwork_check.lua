-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- The artwork is installed separately (docs/ARTWORK.md). Without it every frame draws as a plain
-- green box, which looks like a broken addon; this says what is missing and how to get it.

local addon = select(2, ...)
local L = addon.L

-- A file every install has (edit mode draws it): if this one is missing, the artwork is.
local PROBE_FILE = "Editmode\\editmodeui"
local POPUP = "MISTUI_ARTWORK_MISSING"

local ArtworkCheck = {}
addon.ArtworkCheck = ArtworkCheck

-- SetTexture answers nil for a file the client did not find when it started.
function ArtworkCheck.IsInstalled()
    local probe = ArtworkCheck.probe
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        ArtworkCheck.probe = probe
    end
    local found = probe:SetTexture(addon._dir .. PROBE_FILE)
    probe:SetTexture(nil)
    return found and true or false
end

StaticPopupDialogs[POPUP] = {
    text = L["MistUI artwork is missing, so its frames show as green boxes.\n\nClose the game, double-click Install-Artwork.cmd in the Interface\\AddOns\\MistUI folder, then start the game again. The README on the project page has steps for other systems."],
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ArtworkCheck.Run()
    if ArtworkCheck.IsInstalled() then return end
    addon:Print(L["Artwork missing: close the game and run MistUI\\Install-Artwork.cmd, then start the game again."])
    StaticPopup_Show(POPUP)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    addon:SafeExecute("artwork_check", "run", ArtworkCheck.Run)
end)
