-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- Class resource bars under the new player frame: holy power, shadow orbs, the warlock bars,
-- the eclipse bar and chi, plus the small bars of druids and monks (the second mana bar and
-- stagger).
--
-- The stock bars are children of PlayerFrame and hang off its bottom edge at offsets made for
-- the stock art. Each sits just under the stock mana bar, so each is anchored here to the mana
-- bar instead, with the same offset it has from the stock mana bar; the new frame's mana bar
-- moves, and the bar follows it. The edit mode box ("Class Power") detaches the bar and keeps it
-- where it is dropped, as the rune row does. The bars stay the stock ones: the stock code still
-- fills them, shows them for the right specialization and hides them in a vehicle.
--
-- The small bars (PlayerFrameAlternateManaBar, MonkStaggerBar) follow the mana bar the same way,
-- by their BOTTOMLEFT, but have no edit mode box of their own: they stay by the mana bar when the
-- class bar is moved. The stock code re-anchors them in AlternatePowerBar_SetLook, which only runs
-- at login and on a specialization change (never in combat), so they are placed again after it.

local addon = select(2, ...)
local UF = addon.UF

-- Stock anchor of each bar: its TOP on PlayerFrame's BOTTOM at x, y (MonkHarmonyBar is anchored
-- to PlayerFrame's TOP, 46 down a 100 high frame, which is 54 up from the bottom).
local BARS = {
    PALADIN = { frame = "PaladinPowerBar", x = 43, y = 39 },
    PRIEST = { frame = "PriestBarFrame", x = 53, y = 37 },
    WARLOCK = { frame = "WarlockPowerFrame", x = 50, y = 34 },
    DRUID = { frame = "EclipseBarFrame", x = 48, y = 40 },
    MONK = { frame = "MonkHarmonyBar", x = 49, y = 54 },
}
-- The stock mana bar's bottom centre in the same terms: TOPLEFT (106, -52), 119 by 12, on a frame
-- 232 by 100, so 49.5 right of the frame's bottom centre and 36 up.
local STOCK_MANA_X, STOCK_MANA_Y = 49.5, 36
-- The stock mana bar's BOTTOMLEFT on PlayerFrame's BOTTOMLEFT (106, 100 - 52 - 12).
local STOCK_MANA_LEFT, STOCK_MANA_BOTTOM = 106, 36
-- Stock BOTTOMLEFT of the small bars on PlayerFrame (AlternatePowerBar_SetLook): monks in the
-- specializations with the monk art, then everyone else.
local SMALL_BARS = { "PlayerFrameAlternateManaBar", "MonkStaggerBar" }
local SMALL_MONK_X, SMALL_MONK_Y = 118, 4
local SMALL_X, SMALL_Y = 114, 23
local BOX_WIDTH, BOX_HEIGHT = 140, 30

local ClassPower = {}

local function Spec()
    local _, class = UnitClass("player")
    return class and BARS[class]
end

local function Bar()
    local spec = Spec()
    return spec and _G[spec.frame]
end

local function Config()
    return UF.GetConfig("player")
end

local function Enabled()
    return UF.IsEnabled("player")
end

-- Moved in the editor and with a saved spot (a layout reset can drop the spot while the flag stays).
function ClassPower.Detached()
    local widgets = addon.db.profile.widgets
    local spot = widgets and widgets.classpower
    return ClassPower.box and Config().classpower_detached and spot and spot.posX ~= nil and true or false
end

-- Moves the box onto UIParent's centre where it stands, so its offsets are screen ones.
function ClassPower.Pin()
    local x, y = ClassPower.box:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (x and cx) then return false end
    ClassPower.box:ClearAllPoints()
    ClassPower.box:SetPoint("CENTER", UIParent, "CENTER", x - cx, y - cy)
    return true
end

-- Under the mana bar until moved in the editor; then on the box (widgets.classpower).
-- A reload in combat lands here before the frames may move, so the placement waits for the end of combat.
function ClassPower.Place()
    local spec, bar = Spec(), Bar()
    if not (spec and bar) then return end
    if InCombatLockdown() then
        addon.CombatQueue:Add("classpower_place", ClassPower.Place)
        return
    end
    bar:ClearAllPoints()
    if ClassPower.Detached() then
        ClassPower.Pin()
        addon.ApplyWidgetPositionFromDB("classpower", ClassPower.box)
        bar:SetPoint("TOP", ClassPower.box, "TOP", 0, 0)
    else
        bar:SetPoint("TOP", PlayerFrameManaBar, "BOTTOM", spec.x - STOCK_MANA_X, spec.y - STOCK_MANA_Y)
    end
end

local function UsesMonkLook()
    local _, class = UnitClass("player")
    local spec = GetSpecialization()
    return class == "MONK" and (spec == SPEC_MONK_MISTWEAVER or spec == SPEC_MONK_BREWMASTER)
end

-- Each small bar by the mana bar's BOTTOMLEFT, at the offset the stock look gives it from the stock mana bar.
function ClassPower.PlaceSmallBars()
    if not Enabled() then return end
    if InCombatLockdown() then
        addon.CombatQueue:Add("classpower_small_bars", ClassPower.PlaceSmallBars)
        return
    end
    local x, y = SMALL_X, SMALL_Y
    if UsesMonkLook() then x, y = SMALL_MONK_X, SMALL_MONK_Y end
    for _, name in ipairs(SMALL_BARS) do
        local bar = _G[name]
        if bar then
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", PlayerFrameManaBar, "BOTTOMLEFT", x - STOCK_MANA_LEFT, y - STOCK_MANA_BOTTOM)
        end
    end
end

local function OnStockLookSet(bar)
    if bar == PlayerFrameAlternateManaBar or bar == MonkStaggerBar then
        ClassPower.PlaceSmallBars()
    end
end

function ClassPower.SyncBox()
    local bar = Bar()
    if bar and ClassPower.box and not ClassPower.Detached() then
        ClassPower.box:ClearAllPoints()
        ClassPower.box:SetPoint("TOP", bar, "TOP", 0, 0)
    end
end

function ClassPower.Detach()
    if ClassPower.Pin() then
        addon.SaveUIFramePosition(ClassPower.box, "widgets", "classpower")
        Config().classpower_detached = true
    end
    ClassPower.Place()
end

-- Attached, the box rides on the bar; turned around before the drag, the bar follows from the first move.
function ClassPower.Grab()
    local bar = Bar()
    if not bar or ClassPower.Detached() or InCombatLockdown() or not ClassPower.Pin() then return end
    bar:ClearAllPoints()
    bar:SetPoint("TOP", ClassPower.box, "TOP", 0, 0)
end

local function CreateEditor()
    if ClassPower.box or not Bar() then return end
    ClassPower.box = addon.CreateUIFrame(BOX_WIDTH, BOX_HEIGHT, "ClassPower")
    -- Before the stock handler's StartMoving: re-anchoring a frame mid-move breaks the drag.
    local startDrag = ClassPower.box:GetScript("OnDragStart")
    ClassPower.box:SetScript("OnDragStart", function(self, ...)
        ClassPower.Grab()
        if startDrag then return startDrag(self, ...) end
    end)
    ClassPower.box:HookScript("OnDragStop", ClassPower.Detach)
    addon:RegisterEditableFrame({
        name = "classpower",
        frame = ClassPower.box,
        configPath = { "widgets", "classpower" },
        editorVisible = Enabled,
        showTest = ClassPower.SyncBox,
        onNudge = ClassPower.Detach,
        resetPosition = function()
            Config().classpower_detached = false
            ClassPower.Place()
            ClassPower.SyncBox()
        end,
        isDefaultPosition = function()
            return not ClassPower.Detached()
        end,
        applyPosition = ClassPower.Place,
    })
end

local function Apply()
    if not Enabled() then return end
    ClassPower.PlaceSmallBars()
    if not ClassPower.hooked and AlternatePowerBar_SetLook then
        hooksecurefunc("AlternatePowerBar_SetLook", OnStockLookSet)
        ClassPower.hooked = true
    end
    if not Bar() then return end
    CreateEditor()
    ClassPower.Place()
    ClassPower.SyncBox()
end

ClassPower.Apply = Apply
addon.ClassPower = ClassPower

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    addon:SafeExecute("classpower", "apply", Apply)
end)
