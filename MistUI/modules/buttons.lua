-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local config, _G = addon.config, _G
local unpack, format, gsub, hooksecurefunc = unpack, string.format, string.gsub, hooksecurefunc
local NUM_PET_ACTION_SLOTS, NUM_STANCE_SLOTS = NUM_PET_ACTION_SLOTS, NUM_STANCE_SLOTS
local NUM_POSSESS_SLOTS, NUM_OVERRIDE_BUTTONS = NUM_POSSESS_SLOTS, NUM_OVERRIDE_BUTTONS

-- ============================================================================
-- BUTTONS MODULE FOR MISTUI
-- ============================================================================

local SLOTS_PER_BAR = 12
local STYLED_BAR_ROWS = { 'ActionButton', 'MultiBarBottomLeftButton', 'MultiBarBottomRightButton',
    'MultiBarRightButton', 'MultiBarLeftButton' }

-- Module state tracking
local ButtonsModule = {
    initialized = false,
    applied = false,
    hooked = false,
    pendingRefresh = false,  -- Flag to indicate pending refresh after combat
}

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("buttons", ButtonsModule,
        addon.L["Buttons"],
        addon.L["Action button styling and enhancements"])
end

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function IsModuleEnabled()
    return addon:IsModuleEnabled("buttons")
end

local function GetButtonsConfig()
    return addon.db and addon.db.profile and addon.db.profile.buttons
end

-- Stock in-range hotkey gray; custom color only needs OnUpdate recolor when it differs.
local HOTKEY_DEFAULT_R, HOTKEY_DEFAULT_G, HOTKEY_DEFAULT_B = 0.6, 0.6, 0.6
local hotkeyStyle = {
    ready = false,
    recolor = false,
    r = HOTKEY_DEFAULT_R, g = HOTKEY_DEFAULT_G, b = HOTKEY_DEFAULT_B, a = 1,
    font = nil, size = 12, flags = "OUTLINE",
    sr = 0, sg = 0, sb = 0, sa = 1,
}

local function UpdateHotkeyStyleCache()
    local db = GetButtonsConfig()
    local hk = db and db.hotkey
    local font = hk and hk.font
    local color = hk and hk.color
    local shadow = hk and hk.shadow

    hotkeyStyle.font = (font and font[1])
        or (addon.Fonts and addon.Fonts.ARIALN)
        or "Fonts\\ARIALN.TTF"
    hotkeyStyle.size = (hk and hk.font_size) or (font and font[2]) or 12
    hotkeyStyle.flags = (font and font[3]) or "OUTLINE"

    hotkeyStyle.r = (color and color[1]) or HOTKEY_DEFAULT_R
    hotkeyStyle.g = (color and color[2]) or HOTKEY_DEFAULT_G
    hotkeyStyle.b = (color and color[3]) or HOTKEY_DEFAULT_B
    hotkeyStyle.a = (color and color[4]) or 1

    hotkeyStyle.sr = (shadow and shadow[1]) or 0
    hotkeyStyle.sg = (shadow and shadow[2]) or 0
    hotkeyStyle.sb = (shadow and shadow[3]) or 0
    hotkeyStyle.sa = (shadow and shadow[4]) or 1

    hotkeyStyle.recolor = (hotkeyStyle.r ~= HOTKEY_DEFAULT_R)
        or (hotkeyStyle.g ~= HOTKEY_DEFAULT_G)
        or (hotkeyStyle.b ~= HOTKEY_DEFAULT_B)
        or (hotkeyStyle.a ~= 1)
    hotkeyStyle.ready = true
end

local function EnsureHotkeyStyleCache()
    if not hotkeyStyle.ready then
        UpdateHotkeyStyleCache()
    end
end

-- The bundled fonts lack the range dot; the stock hotkey font has it.
local function HotkeyFontFor(hotkey, font)
    if RANGE_INDICATOR and hotkey:GetText() == RANGE_INDICATOR then
        local stock = _G.NumberFontNormalSmallGray
        return (stock and stock:GetFont()) or font
    end
    return font
end

local function ApplyHotkeyTypography(hotkey)
    if not hotkey then return end
    EnsureHotkeyStyleCache()
    hotkey:SetFont(HotkeyFontFor(hotkey, hotkeyStyle.font), hotkeyStyle.size, hotkeyStyle.flags)
    hotkey:SetShadowOffset(-1.3, -1.1)
    hotkey:SetShadowColor(hotkeyStyle.sr, hotkeyStyle.sg, hotkeyStyle.sb, hotkeyStyle.sa)
end

local function ApplyHotkeyBoundColor(hotkey)
    if not hotkey then return end
    EnsureHotkeyStyleCache()
    hotkey:SetVertexColor(hotkeyStyle.r, hotkeyStyle.g, hotkeyStyle.b, hotkeyStyle.a)
end

function addon.ApplyHotkeyTypography(hotkey)
    ApplyHotkeyTypography(hotkey)
end

function addon.GetHotkeyBoundColor()
    EnsureHotkeyStyleCache()
    return hotkeyStyle.r, hotkeyStyle.g, hotkeyStyle.b, hotkeyStyle.a
end

local function IsAdditionalBarHotkeyEnabled(buttonName)
    if not buttonName or not addon.db or not addon.db.profile then
        return true
    end

    local additional = addon.db.profile.additional
    if not additional then
        return true
    end

    if buttonName:match('^StanceButton%d+$') then
        return not (additional.stance and additional.stance.show_hotkey == false)
    end

    if buttonName:match('^PetActionButton%d+$') then
        return not (additional.pet and additional.pet.show_hotkey == false)
    end

    -- Possess buttons keep the hidden key text they shared with the old totem bar setting.
    if buttonName:match('^PossessButton%d+$') then
        return false
    end

    return true
end

local function IsMulticastButton(buttonName)
    return buttonName and (
        buttonName:match('^MultiCastActionButton%d+$')
        or buttonName == 'MultiCastSummonSpellButton'
        or buttonName == 'MultiCastRecallSpellButton'
    )
end

local function IsAdditionalHotkeyTarget(buttonName)
    return buttonName and (
        buttonName:match('^PetActionButton%d+$')
        or buttonName:match('^PossessButton%d+$')
        or IsMulticastButton(buttonName)
    )
end

local function GetSafeEffectiveScale(frame, fallback)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if scale and scale > 0 then
        return scale
    end

    scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if scale and scale > 0 then
        return scale
    end

    return fallback or 1
end

local function NormalizeAdditionalHotkeyVisual(button, hotkey)
    if not button or not hotkey then return end

    local buttonName = button:GetName()
    if not IsAdditionalHotkeyTarget(buttonName) then return end

    local isMulticast = IsMulticastButton(buttonName)
    local referenceButton = (isMulticast and _G.ActionButton1) or _G.StanceButton1
    local referenceHotkey = (isMulticast and _G.ActionButton1HotKey) or _G.StanceButton1HotKey

    hotkey:ClearAllPoints()
    hotkey:SetPoint('TOPRIGHT', button, 'TOPRIGHT', isMulticast and -2 or -4, -3)

    if not referenceHotkey then
        hotkey:SetJustifyH('RIGHT')
        return
    end

    hotkey:SetJustifyH(referenceHotkey:GetJustifyH() or 'RIGHT')
    hotkey:SetJustifyV(referenceHotkey:GetJustifyV() or 'MIDDLE')

    local font, size, flags = referenceHotkey:GetFont()
    if font and size then
        local referenceScale = GetSafeEffectiveScale(referenceButton, 1)
        local buttonScale = GetSafeEffectiveScale(button, referenceScale)
        hotkey:SetFont(HotkeyFontFor(hotkey, font), size * (referenceScale / buttonScale), flags)
    end
end

local function NumberedGlobal(prefix, index)
    return _G[format('%s%d', prefix, index)]
end

-- Stops at the first missing global, since a generic for ends on nil.
function addon.buttons_iterator()
    local row, slot = 1, 0
    local function advance()
        slot = slot + 1
        if slot > SLOTS_PER_BAR then
            row, slot = row + 1, 1
        end
        local prefix = STYLED_BAR_ROWS[row]
        if prefix then
            return NumberedGlobal(prefix, slot)
        end
    end
    return advance
end

-- With the bar's art hidden its empty slots hide like the other bars', unless the game always shows them.
function addon.MainSlotsFollowGrid()
    local db = GetButtonsConfig()
    return (db and db.hide_main_bar_background and GetCVar('alwaysShowActionBars') ~= '1') and true or false
end

-- The stock code counts the reasons to show empty slots in the 'showgrid' attribute (a drag, the
-- open spellbook), and only its own calls change the count. One share is added, never the count
-- reset. The share is written by secure snippets: a value written by addon code would taint the
-- stock ActionButton_Update that reads it, and that runs in combat on page and stance changes.
local GRID_SNIPPET = [[
    for slot = 1, %d do
        local button = self:GetFrameRef("slot" .. slot)
        local count = button and button:GetAttribute("showgrid") or 0
        if button and %s then
            button:SetAttribute("showgrid", %s)
        end
    end
]]
local GRID_KEEP = GRID_SNIPPET:format(NUM_ACTIONBAR_BUTTONS, 'count < 1', '1')
local GRID_RELEASE = GRID_SNIPPET:format(NUM_ACTIONBAR_BUTTONS, 'count > 0', 'count - 1')

-- Out of combat only: frame refs and Execute are refused in combat.
local function RunGridSnippet(snippet)
    local keeper = ButtonsModule.gridKeeper
    if not keeper then
        keeper = CreateFrame('Frame', nil, UIParent, 'SecureHandlerBaseTemplate')
        for slot = 1, NUM_ACTIONBAR_BUTTONS do
            local mainSlot = NumberedGlobal('ActionButton', slot)
            if mainSlot then
                keeper:SetFrameRef('slot' .. slot, mainSlot)
            end
        end
        ButtonsModule.gridKeeper = keeper
    end
    keeper:Execute(snippet)
end

function addon.RefreshButtonGrid()
    if not IsModuleEnabled() then return end
    if InCombatLockdown() then
        ButtonsModule.pendingRefresh = true
        return
    end
    local follow = addon.MainSlotsFollowGrid()
    if not follow then
        RunGridSnippet(GRID_KEEP)
    elseif ButtonsModule.mainGridForced then
        -- Only the share a forced pass added goes, so a drag or the open spellbook keeps its own.
        RunGridSnippet(GRID_RELEASE)
    end
    for slot = 1, NUM_ACTIONBAR_BUTTONS do
        local mainSlot = NumberedGlobal('ActionButton', slot)
        if mainSlot and not follow then
            ActionButton_ShowGrid(mainSlot)
        elseif mainSlot then
            local count = mainSlot:GetAttribute('showgrid') or 0
            if count == 0 and not (mainSlot.action and HasAction(mainSlot.action)) then
                mainSlot:Hide()
            end
        end
    end
    ButtonsModule.mainGridForced = not follow
end

local function HasPetSlotName(name)
    return name ~= nil and name:find('PetActionButton', 1, true) ~= nil
end

local ATLAS_FRAME = 'ui-hud-actionbar-iconframe'

-- A sheet path set without its texcoords would draw the whole sheet inside the button.
local function SetFrameTexture(button)
    button:SetNormalTexture(config.assets.normal)
    local art = button:GetNormalTexture()
    if art then art:SetAtlasTexture(ATLAS_FRAME) end
end

-- PetActionBar_Update swaps in the stock quickslot art; put ours back after it.
local function KeepPetFrameArt(petSlot, texturePath)
    if not IsModuleEnabled() then return end
    if texturePath and texturePath ~= config.assets.normal then
        SetFrameTexture(petSlot)
    end
end

local function PinCorners(region, target, right, top, left, bottom)
    region:SetPoint('TOPRIGHT', target, 'TOPRIGHT', right, top)
    region:SetPoint('BOTTOMLEFT', target, 'BOTTOMLEFT', left, bottom)
end

-- Retail's slot fills the whole 45 point button, 90x90 of the frame canvas, so it runs under the band.
local function FitSlotArt(slot, owner)
    local cell = owner:GetWidth() / 79
    slot:ClearAllPoints()
    PinCorners(slot, owner, 7 * cell, 4 * cell, -4 * cell, -7 * cell)
end

local function SeatSlotArt(slot, owner)
    owner.__mistUIFitSlot = slot
    FitSlotArt(slot, owner)
end

addon.SeatButtonSlotArt = SeatSlotArt

local function AddSlotBackdrop(owner)
    if not IsModuleEnabled() or not owner or owner.background then return end
    local backdrop = owner:CreateTexture(nil, 'BACKGROUND')
    backdrop:SetAtlasTexture('ui-hud-actionbar-iconframe-slot')
    SeatSlotArt(backdrop, owner)
    backdrop:Show()
    return backdrop
end

local function DigitFree(text)
    return (gsub(text, '%d', ''))
end

-- Every entry is a Lua pattern; the localized names are deliberately left unescaped.
local KEY_SHORTHANDS = {
    { DigitFree(KEY_BUTTON4 or 'Button 4'), 'M' },
    { DigitFree(KEY_NUMPAD1 or 'NumPad 1'), 'N' },
    { 'a%-', 'a' }, { 'c%-', 'c' }, { 's%-', 's' },
    { KEY_BUTTON3 or 'Middle Mouse', 'M3' },
    { KEY_MOUSEWHEELUP or 'Mouse Wheel Up', 'MU' },
    { KEY_MOUSEWHEELDOWN or 'Mouse Wheel Down', 'MD' },
    { KEY_SPACE or 'Space', 'BAR' },
    { CAPSLOCK_KEY_TEXT or 'Caps Lock', 'CL' },
    { KEY_NUMLOCK or 'Num Lock', 'NL' },
    { 'BUTTON', 'M' }, { 'NUMPAD', 'N' },
    { 'ALT%-', 'a' }, { 'CTRL%-', 'c' }, { 'SHIFT%-', 's' },
    { 'MOUSEWHEELUP', 'MU' }, { 'MOUSEWHEELDOWN', 'MD' }, { 'SPACE', 'BAR' },
}

function addon.GetHotkeyText(key)
    local text = key
    if not text then
        return ''
    end
    for index = 1, #KEY_SHORTHANDS do
        local rule = KEY_SHORTHANDS[index]
        text = gsub(text, rule[1], rule[2])
    end
    return text
end
local GetHotkeyText = addon.GetHotkeyText

-- ============================================================================
-- BUTTON STYLING FUNCTIONS
-- ============================================================================

local function styleHotkey(button)
    if not IsModuleEnabled() then return end
    
	if not button then return end
	local buttonName = button:GetName()
	if not buttonName then return end
	
	local hotkey = _G[buttonName..'HotKey']
	if not hotkey then return end
	
	local db = GetButtonsConfig()
	if not db or not db.hotkey then return end

    local showHotkeyText = db.hotkey.show and IsAdditionalBarHotkeyEnabled(buttonName)
    if not showHotkeyText then
        hotkey:SetAlpha(0)
        hotkey:SetText('')
        hotkey:Hide()
        return
    end

    local function ResolveBindingTextFromCommand(command)
        if not command or command == '' then return nil end
        local key = GetBindingKey(command)
        if not key then return nil end
        return GetBindingText(key, 'KEY_') or key
    end

    local function ResolveButtonHotkeyText()
        -- The stock text of a stance or pet button is not the key: the pet bar shortens a
        -- binding to its last digit.
        local preferCanonicalBinding = buttonName:match('^StanceButton%d+$') ~= nil
            or buttonName:match('^PetActionButton%d+$') ~= nil
        local text = hotkey:GetText()
        if not preferCanonicalBinding and text and text ~= '' and (not RANGE_INDICATOR or text ~= RANGE_INDICATOR) then
            return text
        end

        local index = tonumber(buttonName:match('(%d+)$'))
        local candidates

        if buttonName:match('^ActionButton%d+$') then
            candidates = {index and ('ACTIONBUTTON' .. index) or nil}
        elseif buttonName:match('^MultiBarBottomLeftButton%d+$') then
            candidates = {index and ('MULTIACTIONBAR1BUTTON' .. index) or nil}
        elseif buttonName:match('^MultiBarBottomRightButton%d+$') then
            candidates = {index and ('MULTIACTIONBAR2BUTTON' .. index) or nil}
        elseif buttonName:match('^MultiBarRightButton%d+$') then
            candidates = {index and ('MULTIACTIONBAR3BUTTON' .. index) or nil}
        elseif buttonName:match('^MultiBarLeftButton%d+$') then
            candidates = {index and ('MULTIACTIONBAR4BUTTON' .. index) or nil}
        elseif buttonName:match('^StanceButton%d+$') then
            candidates = {index and ('SHAPESHIFTBUTTON' .. index) or nil}
        elseif buttonName:match('^PetActionButton%d+$') then
            -- The client names the pet bar's bindings after the old bonus bar.
            candidates = {index and ('BONUSACTIONBUTTON' .. index) or nil}
        elseif buttonName:match('^MultiCastActionButton%d+$') then
            candidates = {index and ('MULTICASTACTIONBUTTON' .. index) or nil}
        elseif buttonName == 'MultiCastSummonSpellButton' then
            candidates = {'MULTICASTSUMMONSPELL'}
        elseif buttonName == 'MultiCastRecallSpellButton' then
            candidates = {'MULTICASTRECALLSPELL'}
        else
            candidates = nil
        end

        if candidates then
            for _, command in ipairs(candidates) do
                local resolvedText = ResolveBindingTextFromCommand(command)
                if resolvedText and resolvedText ~= '' then
                    return resolvedText
                end
            end
        end

        if button.GetHotkey then
            local ok, resolved = pcall(button.GetHotkey, button)
            if ok and resolved and resolved ~= '' then
                return resolved
            end
        end

        if text and text ~= '' and (not RANGE_INDICATOR or text ~= RANGE_INDICATOR) then
            return preferCanonicalBinding and '' or text
        end

        return ''
    end

    -- Keep ● placeholder (hidden); wiping it on early login kills OnUpdate range dots until reload.
    local nativeText = hotkey:GetText()
    local isNativeRangeDot = RANGE_INDICATOR and nativeText == RANGE_INDICATOR
    local text = ResolveButtonHotkeyText()

    hotkey:SetAlpha(1)
    if isNativeRangeDot then
        if db.hotkey.range then
            hotkey:SetText(RANGE_INDICATOR)
            hotkey:Hide()
            if button.action and HasAction(button.action) then
                button.rangeTimer = -1
            end
        else
            hotkey:SetText('')
            hotkey:Hide()
        end
    else
        local formattedText = GetHotkeyText(text)
        hotkey:SetText(formattedText)
        hotkey:Show()
        ApplyHotkeyBoundColor(hotkey)
    end

    ApplyHotkeyTypography(hotkey)
    NormalizeAdditionalHotkeyVisual(button, hotkey)
end

local function RefreshAdditionalBarHotkeys()
    -- Stance buttons
    for index = 1, NUM_STANCE_SLOTS do
        local button = _G['StanceButton' .. index]
        if button then
            styleHotkey(button)
        end
    end

    -- Pet buttons
    for index = 1, NUM_PET_ACTION_SLOTS do
        local button = _G['PetActionButton' .. index]
        if button then
            styleHotkey(button)
        end
    end

    -- Possess buttons
    for index = 1, NUM_POSSESS_SLOTS do
        local button = _G['PossessButton' .. index]
        if button then
            styleHotkey(button)
        end
    end

    -- Totem/multicast action buttons
    for index = 1, 12 do
        local button = _G['MultiCastActionButton' .. index]
        if button then
            styleHotkey(button)
        end
    end

    if _G.MultiCastSummonSpellButton then
        styleHotkey(_G.MultiCastSummonSpellButton)
    end

    if _G.MultiCastRecallSpellButton then
        styleHotkey(_G.MultiCastRecallSpellButton)
    end
end

function addon.RefreshAdditionalBarHotkeys()
    if not IsModuleEnabled() then return end
    RefreshAdditionalBarHotkeys()
end

local ICON_CROP = { 0.05, 0.95, 0.05, 0.95 }
local ATLAS_CHECKED = '_ui-hud-actionbar-iconborder-checked'
local ATLAS_PUSHED = '_ui-hud-actionbar-iconborder-pushed'
local ATLAS_EQUIPPED = '_ui-hud-actionbar-iconborder-equipped'
local ATLAS_FLASH = 'ui-hud-actionbar-iconframe-flash'
local AUTOCAST_EDGES = { { 'TOP', 14 }, { 'BOTTOM', -15 } }

local function Part(owner, suffix)
    return owner and _G[owner .. suffix]
end

local function DropToplevel(frame)
    if frame and frame.SetToplevel then
        frame:SetToplevel(false)
    end
end

-- All states share retail's 92x90 canvas; its 79 pixel opening, 4 in from top left, holds the icon.
local function FitFrameArt(art, owner)
    local cell = owner:GetWidth() / 79
    art:ClearAllPoints()
    PinCorners(art, owner, 9 * cell, 4 * cell, -4 * cell, -7 * cell)
end

-- Retail's icon runs under the band: its inner edge is soft, so stopping there lets the world through.
local ICON_BLEED = 0.6 / 79
-- What each corner gives up, measured from the bled rect, to clear the chamfer's soft outer edge.
local ICON_CORNER = 3.1 / 79
local ICON_MIRRORS = {}

-- The stock UI only knows the icon, so the strips copy every call that changes how it looks.
for _, method in ipairs({ 'SetTexture', 'SetVertexColor', 'SetDesaturated', 'Show', 'Hide' }) do
    ICON_MIRRORS[method] = function(face, ...)
        if not face.__mistUICut then return end
        local strips = face.__mistUIStrips
        strips[1][method](strips[1], ...)
        strips[2][method](strips[2], ...)
    end
end

-- This client has no icon mask: a column and two side strips skip the corners and never overlap.
local function FitIcon(face, owner)
    local left, right, top, bottom = unpack(ICON_CROP)
    local width, height = owner:GetWidth(), owner:GetHeight()
    local bleedX, bleedY = width * ICON_BLEED, height * ICON_BLEED
    local cutX, cutY = width * ICON_CORNER, height * ICON_CORNER
    local corner = ICON_CORNER / (1 + 2 * ICON_BLEED)
    local trimU, trimV = (right - left) * corner, (bottom - top) * corner
    local leftStrip, rightStrip = face.__mistUIStrips[1], face.__mistUIStrips[2]

    face:ClearAllPoints()
    face:SetPoint('TOPLEFT', owner, 'TOPLEFT', cutX - bleedX, bleedY)
    face:SetPoint('BOTTOMRIGHT', owner, 'BOTTOMRIGHT', bleedX - cutX, -bleedY)
    face:SetTexCoord(left + trimU, right - trimU, top, bottom)

    leftStrip:ClearAllPoints()
    leftStrip:SetPoint('TOPRIGHT', face, 'TOPLEFT', 0, -cutY)
    leftStrip:SetPoint('BOTTOMLEFT', owner, 'BOTTOMLEFT', -bleedX, cutY - bleedY)
    leftStrip:SetTexCoord(left, left + trimU, top + trimV, bottom - trimV)

    rightStrip:ClearAllPoints()
    rightStrip:SetPoint('TOPLEFT', face, 'TOPRIGHT', 0, -cutY)
    rightStrip:SetPoint('BOTTOMRIGHT', owner, 'BOTTOMRIGHT', bleedX, cutY - bleedY)
    rightStrip:SetTexCoord(right - trimU, right, top + trimV, bottom - trimV)
end

local function SeatIcon(face, owner)
    face:SetDrawLayer('BORDER')
    if not face.__mistUIStrips then
        face.__mistUIStrips = { owner:CreateTexture(nil, 'BORDER'), owner:CreateTexture(nil, 'BORDER') }
        for method, mirror in pairs(ICON_MIRRORS) do
            hooksecurefunc(face, method, mirror)
        end
    end
    local shown = face:IsShown()
    for _, strip in ipairs(face.__mistUIStrips) do
        strip:SetTexture(face:GetTexture())
        strip:SetVertexColor(face:GetVertexColor())
        strip:SetDesaturated(face:IsDesaturated())
        if shown then strip:Show() else strip:Hide() end
    end
    face.__mistUICut = true
    owner.__mistUIFitIcon = face
    FitIcon(face, owner)
end

addon.SeatButtonIcon = SeatIcon

local function SeatFrameArt(art, owner)
    art:SetAtlasTexture(ATLAS_FRAME)
    owner.__mistUIFitArt = art
    FitFrameArt(art, owner)
    -- Over the cooldown swipe, which the client draws in ARTWORK at the button's level.
    art:SetDrawLayer('OVERLAY')
    if not owner.__mistUIFitHooked then
        owner.__mistUIFitHooked = true
        owner:HookScript('OnSizeChanged', function(self)
            if self.__mistUIFitArt then FitFrameArt(self.__mistUIFitArt, self) end
            if self.__mistUIFitIcon then FitIcon(self.__mistUIFitIcon, self) end
            if self.__mistUIFitSlot then FitSlotArt(self.__mistUIFitSlot, self) end
        end)
    end
end

addon.SeatButtonFrameArt = SeatFrameArt

-- Retail's TextOverlayContainer: the rings draw in HIGHLIGHT, over anything in the button's own layers.
local function RaiseLabels(button, ...)
    -- Region SetParent is protected, and the vehicle bar can be styled in combat after a /reload.
    local inCombat = InCombatLockdown()
    if not button.__mistUILabels and not inCombat then
        button.__mistUILabels = CreateFrame('Frame', nil, button)
        button.__mistUILabels:SetAllPoints(button)
    end
    for i = 1, select('#', ...) do
        local label = select(i, ...)
        if label then
            label:SetDrawLayer('OVERLAY')
            if not inCombat then label:SetParent(button.__mistUILabels) end
        end
    end
end

addon.RaiseButtonLabels = RaiseLabels

local function SeatCooldown(swipe, owner)
    swipe:ClearAllPoints()
    swipe:SetAllPoints(owner)
    swipe:SetFrameLevel(owner:GetParent():GetFrameLevel() + 1)
end

local function DressLayer(layer, atlas, target)
    layer:SetAtlasTexture(atlas)
    layer:SetAllPoints(target)
end

local STATE_LAYERS = {
    { 'GetPushedTexture', ATLAS_PUSHED, 'OVERLAY' },
    { 'GetHighlightTexture', ATLAS_CHECKED, 'HIGHLIGHT' },
}

-- The lock keeps the layer lit off hover too, so hover's ring has to wait for the mouse.
local function SyncHoverRing(button)
    if not button.__mistUIRing then return end
    local waiting = button:GetChecked() and not button.__mistUIHover
    button:GetHighlightTexture():SetAlpha(waiting and 0 or 1)
end

local function SyncCheckedRing(button)
    if not button.__mistUIRing then return end
    if button:GetChecked() then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
    SyncHoverRing(button)
end

local function RingHoverOn(button)
    button.__mistUIHover = true
    SyncHoverRing(button)
end

local function RingHoverOff(button)
    button.__mistUIHover = nil
    SyncHoverRing(button)
end

-- Retail stacks both regions; only hover's layer is sure to land over the frame, so Checked joins it.
local function DriveRingFromChecked(button)
    local ring = button:GetCheckedTexture()
    ring:SetDrawLayer('HIGHLIGHT')
    ring:SetBlendMode('BLEND')
    button.__mistUIRing = true
    if not button.__mistUIRingHooked then
        button.__mistUIRingHooked = true
        hooksecurefunc(button, 'SetChecked', SyncCheckedRing)
        button:HookScript('OnEnter', RingHoverOn)
        button:HookScript('OnLeave', RingHoverOff)
        button:HookScript('OnHide', RingHoverOff)
    end
    SyncCheckedRing(button)
end

addon.DriveButtonRingFromChecked = DriveRingFromChecked

-- The stock template makes hover ADD; retail's art is meant to be BLEND.
local function DressStates(owner, art)
    owner:SetHighlightTexture(config.assets.highlight)
    for _, entry in ipairs(STATE_LAYERS) do
        local getter, atlas, drawLayer = entry[1], entry[2], entry[3]
        local layer = owner[getter](owner)
        DressLayer(layer, atlas, art)
        layer:SetDrawLayer(drawLayer)
        layer:SetBlendMode('BLEND')
    end
end

local function SeatStateArt(owner, art)
    DressStates(owner, art)
    DressLayer(owner:GetCheckedTexture(), ATLAS_CHECKED, art)
    DriveRingFromChecked(owner)
end

-- A plain Button with an icon, outside the bars: the frame must be its Normal so pressing swaps it.
function addon.SkinIconButton(button, face)
    button:SetNormalTexture(config.assets.normal)
    button:SetPushedTexture(config.assets.normal)
    local art = button:GetNormalTexture()
    SeatFrameArt(art, button)
    DressStates(button, art)
    SeatIcon(face, button)
end

-- Frame tint: border_color alone. Retail's usable tint stops at the icon; the stock code also turns the frame blue.
local frameColor = { 1, 1, 1, 1 }
local frameIsPlain = true
local trackedFrameArt = {}

local function ReadFrameColor()
    local db = GetButtonsConfig()
    local c = db and db.border_color
    frameColor[1], frameColor[2], frameColor[3] = c and c[1] or 1, c and c[2] or 1, c and c[3] or 1
    frameColor[4] = c and c[4] or 1
    frameIsPlain = frameColor[1] == 1 and frameColor[2] == 1 and frameColor[3] == 1 and frameColor[4] == 1
end

local function PaintFrameArt(art, withColor)
    local r, g, b, a = art.__mistUIR, art.__mistUIG, art.__mistUIB, 1
    if withColor then
        r, g, b, a = frameColor[1], frameColor[2], frameColor[3], frameColor[4]
    end
    art.__mistUIPainting = true
    art:SetVertexColor(r, g, b, a)
    art.__mistUIPainting = nil
end

-- The stock UI repaints the frame on every usable and grid update (alpha 0.5 on empty slots), so re-tint after each write.
local function OnFrameArtColored(art, r, g, b, a)
    if art.__mistUIPainting then return end
    art.__mistUIR, art.__mistUIG, art.__mistUIB = r or 1, g or 1, b or 1
    local isWhite = art.__mistUIR == 1 and art.__mistUIG == 1 and art.__mistUIB == 1 and (a == nil or a == 1)
    if frameIsPlain and isWhite then return end
    if IsModuleEnabled() then
        PaintFrameArt(art, true)
    end
end

local function FrameArtOf(button)
    local id = button:GetName()
    return Part(id, 'NormalTexture2') or Part(id, 'NormalTexture') or button:GetNormalTexture()
end

local function OnNormalTextureSet(button)
    local art = button.__mistUIFrameArt
    if art and not frameIsPlain and IsModuleEnabled() then
        PaintFrameArt(art, true)
    end
end

local function TrackFrameArt(button)
    if not button then return end
    local art = button.__mistUIFrameArt or FrameArtOf(button)
    if not art then return end
    if not trackedFrameArt[art] then
        trackedFrameArt[art] = true
        art.__mistUIR, art.__mistUIG, art.__mistUIB = 1, 1, 1
        hooksecurefunc(art, 'SetVertexColor', OnFrameArtColored)
    end
    if not button.__mistUIFrameArt then
        button.__mistUIFrameArt = art
        hooksecurefunc(button, 'SetNormalTexture', OnNormalTextureSet)
    end
    OnNormalTextureSet(button)
end

local function RefreshFrameTint()
    ReadFrameColor()
    local enabled = IsModuleEnabled()
    for art in pairs(trackedFrameArt) do
        PaintFrameArt(art, enabled)
    end
end

addon.TrackButtonFrameArt = TrackFrameArt
addon.RefreshButtonFrameTint = RefreshFrameTint

function addon.GetButtonFrameColor()
    if not IsModuleEnabled() then return 1, 1, 1, nil end
    return frameColor[1], frameColor[2], frameColor[3], frameColor[4]
end

local function IsSlotFillHidden(db, isMainSlot)
    return db.hide_slot_backgrounds or (not isMainSlot and db.only_actionbackground)
end

local function StyleActionSlot(slotButton, skipCombatGuard)
    if not IsModuleEnabled() then return end
    if not skipCombatGuard and InCombatLockdown() then return end
    if not slotButton or slotButton._mistUIStyled then return end

    local id = slotButton:GetName()
    if not skipCombatGuard and not (id and id:match('^ActionButton%d+$')) then
        DropToplevel(slotButton)
        DropToplevel(slotButton:GetParent())
    end

    local art = Part(id, 'NormalTexture') or slotButton:GetNormalTexture()
    SeatFrameArt(art, slotButton)
    art:SetVertexColor(1, 1, 1, 1)
    TrackFrameArt(slotButton)

    local flash, face = Part(id, 'Flash'), Part(id, 'Icon')
    local swipe, equipRing = Part(id, 'Cooldown'), Part(id, 'Border')
    if flash then DressLayer(flash, ATLAS_FLASH, art) end
    if face then SeatIcon(face, slotButton) end
    if swipe then SeatCooldown(swipe, slotButton) end
    if equipRing then
        DressLayer(equipRing, ATLAS_EQUIPPED, art)
        equipRing:SetBlendMode('BLEND')
    end
    SeatStateArt(slotButton, art)
    RaiseLabels(slotButton, Part(id, 'HotKey'), Part(id, 'Count'))

    local backdrop = AddSlotBackdrop(slotButton)
    slotButton.background = backdrop
    local db = GetButtonsConfig()
    -- Hidden right away so the slot art never flashes for one frame before RefreshButtons.
    if backdrop and db and IsSlotFillHidden(db, id and id:match('^ActionButton%d+$')) then
        backdrop:Hide()
    end
    slotButton._mistUIStyled = true
end

local function StyleExtraSlot(slotButton)
    if not IsModuleEnabled() or InCombatLockdown() or not slotButton then return end
    DropToplevel(slotButton)
    DropToplevel(slotButton:GetParent())
    SetFrameTexture(slotButton)
    TrackFrameArt(slotButton)
    if slotButton.background then return end

    local id = slotButton:GetName()
    local art = Part(id, 'NormalTexture2') or Part(id, 'NormalTexture')
    SeatFrameArt(art, slotButton)
    SeatStateArt(slotButton, art)
    RaiseLabels(slotButton, Part(id, 'HotKey'), Part(id, 'Count'))

    local swipe, face = Part(id, 'Cooldown'), Part(id, 'Icon')
    local flash, autocast = Part(id, 'Flash'), Part(id, 'AutoCastable')
    if swipe then SeatCooldown(swipe, slotButton) end
    if face then SeatIcon(face, slotButton) end
    if flash then DressLayer(flash, ATLAS_FLASH, art) end
    if autocast then
        autocast:ClearAllPoints()
        for _, edge in ipairs(AUTOCAST_EDGES) do
            autocast:SetPoint(edge[1], 0, edge[2])
        end
    end
    if HasPetSlotName(id) then
        hooksecurefunc(slotButton, 'SetNormalTexture', KeepPetFrameArt)
    end

    local backdrop = AddSlotBackdrop(slotButton)
    slotButton.background = backdrop
    local db = GetButtonsConfig()
    -- Hidden right away so the slot art never flashes for one frame before RefreshButtons.
    if backdrop and db and IsSlotFillHidden(db) then
        backdrop:Hide()
    end
end

-- ============================================================================
-- APPLY STYLING
-- ============================================================================

local function ApplyButtonStyling()
    if ButtonsModule.applied then return end

    if InCombatLockdown() then
        if addon.CombatQueue then
            addon.CombatQueue:Add("buttons_apply_styling", ApplyButtonStyling)
        end
        return
    end

    for slotButton in addon.buttons_iterator() do
        StyleActionSlot(slotButton)
        slotButton:SetSize(37, 37)
    end
    
    ButtonsModule.applied = true
end

-- ============================================================================
-- UPDATE HANDLERS
-- ============================================================================

local function refreshSlotButton(slotButton)
    if not IsModuleEnabled() then return end
    if not slotButton or not slotButton._mistUIStyled then return end
    local id = slotButton:GetName()
    SetFrameTexture(slotButton)
    -- Retail paints this ring at 0.5; the stock code writes 0.35 on every update.
    local equipRing = Part(id, 'Border')
    if equipRing then equipRing:SetVertexColor(0, 1, 0, 0.5) end
    -- The stock UI grays an empty slot's hotkey here, and the range recolor below never revisits it.
    if hotkeyStyle.recolor and not slotButton.rangeTimer then
        local hotkey = Part(id, 'HotKey')
        if hotkey and hotkey:GetText() ~= RANGE_INDICATOR then
            ApplyHotkeyBoundColor(hotkey)
        end
    end
end

function addon.RefreshButtons()
    if not IsModuleEnabled() then return end
    RefreshFrameTint()

    -- CRITICAL: Don't refresh buttons during combat to avoid taint
    if InCombatLockdown() then 
        ButtonsModule.pendingRefresh = true
        return 
    end

    UpdateHotkeyStyleCache()
    
    local db = GetButtonsConfig()
    if not db then return end

    for button in addon.buttons_iterator() do
        if button and button.background then
            local buttonName = button:GetName()
            if buttonName then
                local isMainActionButton = buttonName:match("^ActionButton%d+$")

                -- show/hide action backgrounds
                if IsSlotFillHidden(db, isMainActionButton) then
                    button.background:Hide()
                else
                    button.background:Show()
                end

                -- update hotkeys and range indicators
                pcall(styleHotkey, button)

                -- handle macro text
                local macros = _G[buttonName .. 'Name']
                if macros and db.macros then
                    if db.macros.show then
                        macros:Show()
                    else
                        macros:Hide()
                    end
                    if db.macros.color then macros:SetVertexColor(unpack(db.macros.color)) end
                    if db.macros.font then macros:SetFont(unpack(db.macros.font)) end
                end

                -- handle count text
                local count = _G[buttonName .. 'Count']
                if count and db.count then
                    count:SetAlpha(db.count.show and 1 or 0)
                end

                -- The module's own restyle, not the stock ActionButton_Update: run from addon code,
                -- that would write the stock button's event state tainted.
                refreshSlotButton(button)
            end
        end
    end

    -- buttons_iterator() only walks main/multi bars, so pet/stance/possess need their own toggle pass.
    local additionalBars = {
        { prefix = 'PetActionButton', count = NUM_PET_ACTION_SLOTS },
        { prefix = 'StanceButton', count = NUM_STANCE_SLOTS },
        { prefix = 'PossessButton', count = NUM_POSSESS_SLOTS },
    }
    for _, bar in ipairs(additionalBars) do
        for index = 1, bar.count do
            local button = _G[bar.prefix .. index]
            if button and button.background then
                if IsSlotFillHidden(db) then
                    button.background:Hide()
                else
                    button.background:Show()
                end
            end
        end
    end

    RefreshAdditionalBarHotkeys()
end

-- ============================================================================
-- TEMPLATE FUNCTIONS
-- ============================================================================

-- Texture-only work, so an override bar shown mid-combat can still be skinned with the skip flag.
function addon.StyleVehicleButtons(skipCombatGuard)
    if not IsModuleEnabled() then return end
    if skipCombatGuard or OverrideActionBar:IsShown() then
        for seat = 1, NUM_OVERRIDE_BUTTONS do
            local vehicleSlot = NumberedGlobal('OverrideActionBarButton', seat)
            if vehicleSlot then
                StyleActionSlot(vehicleSlot, skipCombatGuard)
                styleHotkey(vehicleSlot)
            end
        end
    end
    RefreshAdditionalBarHotkeys()
end

function addon.RefreshAllHotkeys()
    if not IsModuleEnabled() then return end

    UpdateHotkeyStyleCache()

    for button in addon.buttons_iterator() do
        if button then
            styleHotkey(button)
        end
    end

    RefreshAdditionalBarHotkeys()
end

function addon.RefreshHotkeyStyle()
    if IsModuleEnabled() then
        addon.RefreshAllHotkeys()
    else
        UpdateHotkeyStyleCache()
    end
end

local function StyleExtraRow(prefix, count, withHotkeys)
    for index = 1, count do
        local extra = NumberedGlobal(prefix, index)
        StyleExtraSlot(extra)
        if extra and withHotkeys then
            styleHotkey(extra)
        end
    end
end

-- Hotkeys only: restyling the multicast buttons left the stock totem bar invisible.
function addon.StyleTotemButtons()
    if not IsModuleEnabled() then return end
    RefreshAdditionalBarHotkeys()
end

-- export name -> { button prefix, slot count, refresh hotkeys too }
local EXTRA_ROW_EXPORTS = {
    StylePossessButtons = { 'PossessButton', NUM_POSSESS_SLOTS, false },
    StylePetButtons = { 'PetActionButton', NUM_PET_ACTION_SLOTS, true },
    StyleStanceButtons = { 'StanceButton', NUM_STANCE_SLOTS, true },
}
for exportName, row in pairs(EXTRA_ROW_EXPORTS) do
    addon[exportName] = function()
        if not IsModuleEnabled() then return end
        StyleExtraRow(row[1], row[2], row[3])
    end
end

-- ============================================================================
-- ACTION BUTTON TOOLTIPS
-- ============================================================================

-- buttons.tooltips: "always" | "combat" (hidden in combat) | "never"
function addon.ShouldHideActionTooltip()
    local db = GetButtonsConfig()
    local mode = db and db.tooltips
    local hide = mode == "never" or (mode == "combat" and InCombatLockdown())
    return hide and IsModuleEnabled() or false
end

local function HideActionTooltip(tooltip)
    if addon.ShouldHideActionTooltip() then
        tooltip:Hide()
    end
end

-- ============================================================================
-- HOOKS MANAGEMENT
-- ============================================================================

local function SetupHooks()
    if ButtonsModule.hooked or not IsModuleEnabled() then return end

    hooksecurefunc('ActionButton_Update', refreshSlotButton)

    hooksecurefunc(GameTooltip, 'SetAction', HideActionTooltip)
    hooksecurefunc(GameTooltip, 'SetShapeshift', HideActionTooltip)
    -- Pet commands (Attack, Follow...) fill the tooltip with SetText, never SetPetAction.
    hooksecurefunc('PetActionButton_OnEnter', function(button)
        if GameTooltip:IsOwned(button) then
            HideActionTooltip(GameTooltip)
        end
    end)

    if type(_G.ActionButton_UpdateHotkeys) == 'function' then
        -- The stock function also serves the extra action button and the override bar.
        hooksecurefunc('ActionButton_UpdateHotkeys', function(button)
            if not IsModuleEnabled() then return end
            if button and button._mistUIStyled then
                styleHotkey(button)
            end
        end)
    end

    -- Stock ActionButton_OnUpdate paints in-range gray; reassert custom color only when needed.
    if type(_G.ActionButton_OnUpdate) == 'function' then
        hooksecurefunc('ActionButton_OnUpdate', function(self)
            -- The stock UI only repaints the hotkey on the frame it resets rangeTimer, so only recolor then.
            if not hotkeyStyle.recolor or not self or self.rangeTimer ~= TOOLTIP_UPDATE_TIME then return end
            if not self._mistUIStyled or not IsModuleEnabled() then return end
            local name = self:GetName()
            if not name then return end
            local hotkey = _G[name .. 'HotKey']
            if not hotkey or not hotkey:IsShown() then return end
            local text = hotkey:GetText()
            if not text or text == '' or text == RANGE_INDICATOR then return end
            -- Keep stock OOR red; IsActionInRange(0) matches ActionButton.lua range branch.
            if IsActionInRange(self.action) == 0 then return end
            hotkey:SetVertexColor(hotkeyStyle.r, hotkeyStyle.g, hotkeyStyle.b, hotkeyStyle.a)
        end)
    end

    if type(_G.PetActionButton_SetHotkeys) == 'function' then
        hooksecurefunc('PetActionButton_SetHotkeys', function()
            if not IsModuleEnabled() then return end
            RefreshAdditionalBarHotkeys()
        end)
    end

    -- HideGrid hook: protect ONLY main bar from ever being hidden.
    -- Additional bars are fully managed by the stock UI - we don't touch them.
    hooksecurefunc('ActionButton_HideGrid', function(button)
        if not IsModuleEnabled() then return end
        if InCombatLockdown() then return end
        if not button or addon.MainSlotsFollowGrid() then return end
        local name = button:GetName()
        if name and name:match("^ActionButton%d+$") then
            RunGridSnippet(GRID_KEEP)
            if not button:GetAttribute('statehidden') then
                button:Show()
            end
        end
    end)
    
    ButtonsModule.hooked = true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function Initialize()
    if ButtonsModule.initialized then return end
    ReadFrameColor()

    -- Only apply styling if module is enabled
    if IsModuleEnabled() then
        ApplyButtonStyling()
        SetupHooks()
    end

    if addon.db and addon.db.RegisterCallback then
        local function OnProfileChanged()
            hotkeyStyle.ready = false
            hotkeyStyle.recolor = false
            RefreshFrameTint()
            if IsModuleEnabled() then
                addon.RefreshAllHotkeys()
                addon.RefreshButtonGrid()
            end
        end
        addon.db.RegisterCallback(ButtonsModule, "OnProfileChanged", OnProfileChanged)
        addon.db.RegisterCallback(ButtonsModule, "OnProfileCopied", OnProfileChanged)
        addon.db.RegisterCallback(ButtonsModule, "OnProfileReset", OnProfileChanged)
    end
    
    ButtonsModule.initialized = true
end

local function OnLoginGridPass()
    if IsModuleEnabled() then
        addon.RefreshButtonGrid()
        addon.RefreshButtons()
    end
end
addon.package:Subscribe(OnLoginGridPass, 'PLAYER_LOGIN')

-- Auto-initialize when addon loads and handle post-combat refresh
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:RegisterEvent("UPDATE_BINDINGS")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MistUI" then
        Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-enforce main bar grid on every zone / instance / reload.
        if IsModuleEnabled() then
            addon.RefreshButtonGrid()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Execute pending refreshes after combat ends
        if IsModuleEnabled() and ButtonsModule.pendingRefresh then
            ButtonsModule.pendingRefresh = false
            addon.RefreshButtonGrid()
            addon.RefreshButtons()
        end
    elseif event == "UPDATE_BINDINGS" then
        -- ORIGINAL PATTERN: Update hotkeys when bindings change
        if IsModuleEnabled() then
            addon.RefreshAllHotkeys()
        end
    end
end)

-- Multibar grids are left to the stock option setFunc (MultiActionBar_ShowAllGrids/HideAllGrids).
hooksecurefunc("SetCVar", function(name, value)
    if name == "alwaysShowActionBars" then
        if not IsModuleEnabled() then return end
        addon.RefreshButtonGrid()
        local mixin = addon.MainMenuBarMixin
        if mixin and mixin.update_main_bar_background then
            mixin:update_main_bar_background()
        end
    end
end)