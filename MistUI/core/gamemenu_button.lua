-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Based on DragonUI's game menu button (MIT, NeticSoul and contributors), without its dragon
-- heads and flame effect and without the layout code for other clients.

-- A "MistUI" button in the Escape menu, below "Return to Game", that opens the settings.
-- The stock GameMenuFrame_UpdateVisibleButtons sets the menu's height each time the menu opens;
-- the button is placed and the height grown right after it. The menu is not a protected frame,
-- so this also works when the menu opens in combat (the settings themselves refuse to open then).

local addon = select(2, ...)
local L = addon.L

local OPTIONS_ADDON = "MistUI_Options"
-- The stock menu leaves this gap between its groups of buttons.
local GROUP_GAP = 16
-- Stock buttons overlap their neighbour by one pixel; the menu grows by the rest.
local BUTTON_OVERLAP = 1

local button

-- Without the settings addon (missing or switched off) the button would have nothing to open.
local function OptionsAvailable()
    local reason = select(6, GetAddOnInfo(OPTIONS_ADDON))
    return reason ~= "MISSING" and reason ~= "DISABLED"
end

local function OpenSettings()
    PlaySound("igMainMenuOption")
    HideUIPanel(GameMenuFrame)
    addon:ToggleOptionsUI()
end

local function CreateButton()
    button = CreateFrame("Button", "MistUIGameMenuButton", GameMenuFrame, "GameMenuButtonTemplate")
    button:SetText(L["MistUI"])
    if addon.ForeverUI and addon.ForeverUI.SkinButton then
        addon.ForeverUI.SkinButton(button)
    end
    button:SetScript("OnClick", OpenSettings)
end

local function PlaceButton(menu)
    if not OptionsAvailable() then
        if button then button:Hide() end
        return
    end
    if not button then CreateButton() end
    button:ClearAllPoints()
    button:SetPoint("TOP", GameMenuButtonContinue, "BOTTOM", 0, -GROUP_GAP)
    button:Show()
    menu:SetHeight(menu:GetHeight() + GROUP_GAP + button:GetHeight() - BUTTON_OVERLAP)
end

hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", PlaceButton)
addon.GameMenuButton = { Place = PlaceButton }
