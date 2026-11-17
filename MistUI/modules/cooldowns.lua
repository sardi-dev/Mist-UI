-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ============================================================================
-- MistUI - Cooldown Text Module
-- Displays countdown timers on action buttons via metatable hooking.
-- ============================================================================

local addon = select(2, ...)
local L = addon.L
local unpack = unpack
local ceil = math.ceil
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc

local CooldownsModule = {
    initialized = false,
    applied = false,
    hooks = {},
}
addon.CooldownsModule = CooldownsModule

if addon.RegisterModule then
    addon:RegisterModule("cooldowns", CooldownsModule,
        L["Cooldown Text"],
        L["Cooldown text on action buttons"])
end

-- Create a table within the main addon object to hold our functions
addon.CooldownText = {}

-- Tenths are only drawn under 5s (unless whole_seconds is on); above that the text changes once a second.
local TICK_FAST, TICK_SLOW = 0.05, 0.25

local COUNTDOWN_STEPS = {
    { ceiling = 5, decimals = '%.1f', rgb = { 1, 0, 0.2 } },
    { ceiling = 60, per = 1, unit = '', rgb = { 1, 1, 0 } },
    { ceiling = 3600, per = 60, unit = 'm' },
    { ceiling = math.huge, per = 3600, unit = 'h', shade = 0.7 },
}

local DEFAULT_TEXT_ANCHOR = { 'CENTER', 0, 1 }
local MIN_CHARGES_FOR_RECHARGE = 2
local ACTION_BAR_PREFIXES = {
    'ActionButton', 'MultiBarBottomLeftButton', 'MultiBarBottomRightButton', 'MultiBarRightButton', 'MultiBarLeftButton',
}
local ACTION_BAR_SLOTS = 12
addon.CooldownText.ACTION_BAR_PREFIXES = ACTION_BAR_PREFIXES
addon.CooldownText.ACTION_BAR_SLOTS = ACTION_BAR_SLOTS
local NO_FONT = {}

-- Stance, pet and possess buttons have no action slot; the stock code starts their cooldowns
-- through SetCooldown, so the hook below sees them once their cooldown frames are known.
local SMALL_BAR_BUTTONS = {
    { prefix = 'StanceButton', count = NUM_STANCE_SLOTS },
    { prefix = 'PetActionButton', count = NUM_PET_ACTION_SLOTS },
    { prefix = 'PossessButton', count = NUM_POSSESS_SLOTS },
}
local smallBarCooldowns = {}

local function CollectSmallBarCooldowns()
    for _, bar in ipairs(SMALL_BAR_BUTTONS) do
        for slot = 1, bar.count or 0 do
            local cooldown = _G[bar.prefix .. slot .. 'Cooldown']
            if cooldown then
                smallBarCooldowns[cooldown] = true
            end
        end
    end
end

-- True for the cooldown frame of an action, stance, pet or possess button; aura and item
-- cooldowns pass through the same hook and are left alone.
local function IsButtonCooldown(cooldown)
    if smallBarCooldowns[cooldown] then
        return true
    end
    local parent = cooldown:GetParent()
    return parent ~= nil and parent.action ~= nil
end

local function StepFor(secondsLeft)
    for _, step in ipairs(COUNTDOWN_STEPS) do
        if secondsLeft <= step.ceiling then
            return step
        end
    end
end

local function PaintCountdown(label, step, secondsLeft, dbColor, wholeSeconds)
    if step.decimals and wholeSeconds then
        label:SetText(ceil(secondsLeft) .. '')
    elseif step.decimals then
        label:SetText(step.decimals:format(secondsLeft))
    else
        label:SetText(ceil(secondsLeft / step.per) .. step.unit)
    end
    local rgb, shade = step.rgb, step.shade
    if rgb then
        label:SetTextColor(rgb[1], rgb[2], rgb[3])
    elseif shade then
        local r, g, b, a = unpack(dbColor)
        label:SetTextColor(r * shade, g * shade, b * shade, a)
    else
        label:SetTextColor(unpack(dbColor))
    end
end

local function StopCountdown(cooldown, blankText)
    cooldown.remain = nil
    local label = cooldown.text
    if label then
        label:Hide()
        if blankText then
            label:SetText('')
        end
    end
end

function addon.CooldownText:UpdateText(elapsed)
    if not self.remain or not IsButtonCooldown(self) then
        return
    end

    local wait = (self.mistUINextTick or 0) - (elapsed or 0)
    if wait > 0 then
        self.mistUINextTick = wait
        return
    end

    local settings = addon.db.profile.buttons.cooldown
    local wholeSeconds = settings and settings.whole_seconds
    local secondsLeft = self.remain - GetTime()
    self.mistUINextTick = (secondsLeft <= 5 and not wholeSeconds) and TICK_FAST or TICK_SLOW

    if secondsLeft <= 0 then
        StopCountdown(self, true)
        return
    end

    if settings == nil then
        return
    end
    PaintCountdown(self.text, StepFor(secondsLeft), secondsLeft, settings.color, wholeSeconds)
end

function addon.CooldownText:CreateText()
    -- The template guarantees a font even when the SetFont path below fails on this locale.
    local label = self:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    label:SetFont(addon.Fonts.ACTIONBAR, 16, 'OUTLINE')
    label:SetPoint('CENTER', self, 'CENTER')
    self.text = label
    self:SetScript('OnUpdate', addon.CooldownText.UpdateText)
    return label
end

function addon.CooldownText:OnSetCooldown(start, duration, charges, maxCharges)
    -- The metatable hook fires for ALL CooldownFrame:SetCooldown calls. Processing aura
    -- cooldowns causes unnecessary SetPoint/Show calls that interfere with the sweep animation.
    if not IsButtonCooldown(self) then
        return
    end

    -- Skip redundant calls with identical cooldown values.
    -- This prevents unnecessary text updates (and visual flicker) when
    -- e.g. TargetFrame_UpdateAuras re-fires SetTimer with the same values.
    if self._mistUI_cdStart == start and self._mistUI_cdDur == duration and self._mistUI_cdCharges == charges
        and self._mistUI_cdMaxCharges == maxCharges then
        return
    end
    self._mistUI_cdStart = start
    self._mistUI_cdDur   = duration
    self._mistUI_cdCharges = charges
    self._mistUI_cdMaxCharges = maxCharges

    local moduleDb = addon.db.profile.modules.cooldowns
    local db = addon.db.profile.buttons.cooldown
    if not db then
        return
    end

    if type(start) ~= 'number' or type(duration) ~= 'number' then
        return
    end

    -- Defensive normalization: some environments/addons can feed SetCooldown
    -- with a start value from a different clock base than GetTime().
    -- If remaining time is much larger than duration, keep duration and
    -- rebase start to the local clock to avoid absurd values (e.g. 1194h).
    if start > 0 and duration > 0 then
        local now = GetTime()
        local remaining = (start + duration) - now
        if remaining > (duration + 2) then
            start = now
        end
    end

    -- A spell with a charge left can still be cast: the sweep then shows the next charge
    -- coming back, and a countdown over the button would read as "not ready". Only spells with
    -- several charges count: a server may report a plain cooldown as "one charge of one".
    local recharging = type(charges) == 'number' and charges > 0
        and type(maxCharges) == 'number' and maxCharges >= MIN_CHARGES_FOR_RECHARGE
    local showText = moduleDb.enabled and start > 0 and duration > db.min_duration and not recharging
    if not showText then
        StopCountdown(self)
        return
    end

    self.remain = start + duration
    self.mistUINextTick = 0
    local label = self.text or addon.CooldownText.CreateText(self)
    local font = db.font or NO_FONT
    label:SetFont(font[1] or addon.Fonts.ACTIONBAR, db.font_size or font[2] or 16, font[3] or 'OUTLINE')
    -- No ClearAllPoints: the DB point is layered on top of CreateText's CENTER anchor.
    label:SetPoint(unpack(db.position or DEFAULT_TEXT_ANCHOR))
    label:Show()
end

-- Feeds the countdown from what the client reports for each stock action button.
function addon.CooldownText.ReadActionButtons()
    -- With the numbers off there is nothing to feed; the event fires for every cooldown change.
    if not addon.db.profile.modules.cooldowns.enabled then return end
    for _, prefix in ipairs(ACTION_BAR_PREFIXES) do
        for slot = 1, ACTION_BAR_SLOTS do
            local button = _G[prefix .. slot]
            local cooldown = button and button.cooldown
            if cooldown and type(button.action) == 'number' then
                local start, duration, enable, charges, maxCharges = GetActionCooldown(button.action)
                -- As the stock code does: a cooldown that is not running yet counts as none.
                if not enable or enable == 0 then
                    start, duration = 0, 0
                end
                addon.CooldownText.OnSetCooldown(cooldown, start, duration, charges, maxCharges)
            end
        end
    end
end

local function RefreshCooldown(cooldown, moduleDb, db)
    if cooldown.text then
        local fontPath = db.font and db.font[1]
        cooldown.text:SetFont(
            fontPath or addon.Fonts.ACTIONBAR,
            db.font_size or (db.font and db.font[2]) or 16,
            (db.font and db.font[3]) or 'OUTLINE'
        )
        if not moduleDb.enabled then
            cooldown.text:Hide()
        end
    end

    -- A Cooldown cannot be asked for its times here; OnSetCooldown caches the last ones it was given.
    local start, duration = cooldown._mistUI_cdStart, cooldown._mistUI_cdDur
    local now = GetTime()
    local cached = type(start) == 'number' and type(duration) == 'number'
    -- OnSetCooldown rebased this future start to "now"; replaying it would restart the countdown.
    local rebased = cached and start > now + 2
    if cached and not rebased and start > 0 and start + duration > now then
        -- Forget the dedupe values, or a running cooldown skips the enable/disable change.
        cooldown._mistUI_cdStart = nil
        addon.CooldownText.OnSetCooldown(cooldown, start, duration, cooldown._mistUI_cdCharges,
            cooldown._mistUI_cdMaxCharges)
    elseif not rebased and moduleDb.enabled and cooldown.text then
        cooldown.text:Hide()
        cooldown.remain = nil
    end
end

-- Action bar rows and the stance, pet and possess buttons, so a settings change shows at once on all.
function addon.RefreshCooldowns()
    if not addon.buttons_iterator then
        return
    end
    local moduleDb = addon.db.profile.modules.cooldowns
    local db = addon.db.profile.buttons.cooldown
    if not db then
        return
    end

    for button in addon.buttons_iterator() do
        local cooldown = button and _G[button:GetName() .. 'Cooldown']
        if cooldown then
            RefreshCooldown(cooldown, moduleDb, db)
        end
    end
    for cooldown in pairs(smallBarCooldowns) do
        RefreshCooldown(cooldown, moduleDb, db)
    end
end


-- Called from core.lua to ensure the hook is applied only once at the right time
local isHooked = false
function addon.InitializeCooldowns()
    if isHooked then return end

    if not _G.ActionButton1Cooldown then
        return
    end
    CollectSmallBarCooldowns()

    -- One hook on the shared widget method table sees every Cooldown's SetCooldown.
    local widgetMeta = getmetatable(_G.ActionButton1Cooldown)
    local cooldownMethods = widgetMeta and widgetMeta.__index
    if type(cooldownMethods) == 'table' and cooldownMethods.SetCooldown then
        hooksecurefunc(cooldownMethods, 'SetCooldown', addon.CooldownText.OnSetCooldown)
        isHooked = true
        addon.CooldownText.hooked = true
    end

    -- The client starts the cooldown of a stock action button itself, without calling SetCooldown
    -- from the interface code, so the hook above only sees a cooldown after a full button update.
    local watcher = CreateFrame('Frame')
    watcher:RegisterEvent('ACTIONBAR_UPDATE_COOLDOWN')
    watcher:SetScript('OnEvent', addon.CooldownText.ReadActionButtons)

    -- =========================================================================
    -- BUFF/DEBUFF SWEEP ANIMATION PROTECTION (taint-safe)
    -- =========================================================================
    -- When TargetFrame_UpdateAuras runs (e.g. on target change, UNIT_AURA),
    -- it calls CooldownFrame_SetTimer → :SetCooldown() for EVERY buff/debuff,
    -- even when start/duration haven't changed.  Each :SetCooldown() resets
    -- the sweep animation to 12-o'clock, causing a visible flash.
    --
    -- We CANNOT replace the global CooldownFrame_SetTimer (causes taint on
    -- secure action button code paths).  Instead we replace :SetCooldown()
    -- on individual buff/debuff cooldown frame INSTANCES.  These frames are
    -- NOT secure, so the replacement doesn't propagate taint to action bars.
    -- =========================================================================
    local MAX_TARGET_BUFFS  = 32
    local MAX_TARGET_DEBUFFS = 16

    local function ProtectCooldownSweep(cd)
        if not cd or cd._mistUI_sweepProtected then return end
        local origSetCooldown = cd.SetCooldown
        if not origSetCooldown then return end

        cd.SetCooldown = function(self, start, duration, ...)
            if self._mistUI_cdStart == start and self._mistUI_cdDur == duration then
                return  -- identical values → skip → sweep continues smoothly
            end
            self._mistUI_cdStart = start
            self._mistUI_cdDur   = duration
            return origSetCooldown(self, start, duration, ...)
        end
        cd._mistUI_sweepProtected = true
    end

    -- The stock code creates aura buttons in order, 1 upwards, as a target first needs them, so each
    -- pass only looks past the last one already protected instead of every name each aura update.
    local nextAuraIndex = {}

    local function ProtectAuraRange(frameName, kind, maximum)
        local key = frameName .. kind
        local index = nextAuraIndex[key] or 1
        while index <= maximum do
            local cd = _G[frameName .. kind .. index .. "Cooldown"]
            if not cd then break end
            ProtectCooldownSweep(cd)
            index = index + 1
        end
        nextAuraIndex[key] = index
    end

    local function ProtectAuraCooldownsForFrame(frameName)
        ProtectAuraRange(frameName, "Buff", MAX_TARGET_BUFFS)
        ProtectAuraRange(frameName, "Debuff", MAX_TARGET_DEBUFFS)
    end

    -- Hook TargetFrame_UpdateAuras: the stock UI may create buff frames lazily,
    -- so we re-scan after each call to catch any new cooldown frames.
    if _G.TargetFrame_UpdateAuras then
        hooksecurefunc("TargetFrame_UpdateAuras", function(self)
            local name = self and self.GetName and self:GetName()
            if name then
                ProtectAuraCooldownsForFrame(name)
            end
        end)
    end

    -- Also scan immediately for any frames that already exist at init time
    ProtectAuraCooldownsForFrame("TargetFrame")
    ProtectAuraCooldownsForFrame("FocusFrame")
end

