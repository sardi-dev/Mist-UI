-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- Raid frames: the client's own raid frames (and its raid-style party frames) in the Mist-UI look.
-- The client keeps deciding who is shown, range, dead and offline states and click targeting;
-- this file only restyles, from post-hooks on the stock setup and aura passes, and only touches
-- the frames' bars, text and its own textures (never the secure buttons' size, place or scripts).

local addon = select(2, ...)
local L = addon.L

local RaidFrames = { applied = false }
addon.RaidFrames = RaidFrames

if addon.RegisterModule then
    addon:RegisterModule("raid_frames", RaidFrames, L["Raid Frames"],
        L["Retail-style look for the game's raid frames, with a colored outline for debuffs you can dispel."])
end

local BAR_TEXTURE = addon._dir .. "PersonalResource\\statusbar"
local BACKGROUND_COLOR = { 0.06, 0.06, 0.06, 0.85 }
local OUTLINE_SIZE = 2
local NAME_FLAGS = "OUTLINE"
-- Debuffs a player can remove, the most urgent first; the outline shows the first one found.
local DISPEL_ORDER = { "Magic", "Curse", "Disease", "Poison" }
local DISPEL_RANK = {}
for rank, kind in ipairs(DISPEL_ORDER) do DISPEL_RANK[kind] = rank end
local MAX_DEBUFF_SCAN = 40
-- Frames the client made before this module ran, by the names the stock code gives them.
local MAX_RAID_FRAMES, MAX_GROUPS, GROUP_SIZE = 80, 8, 5

-- Per frame: the stock look to put back, and the outline textures. Weak: frames are never freed,
-- but nothing here should keep one alive either.
local records = setmetatable({}, { __mode = "k" })

local function Config()
    return addon:GetModuleConfig("raid_frames") or {}
end

local function UseOwnBars()
    return Config().bar_texture ~= "stock"
end

local function TextureOf(bar)
    local texture = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    return texture and texture:GetTexture()
end

-- Taken after every stock setup pass, so what is remembered is always the stock look.
local function Remember(frame, record)
    local health = TextureOf(frame.healthBar)
    if health and health ~= BAR_TEXTURE then record.health = health end
    local power = TextureOf(frame.powerBar)
    if power and power ~= BAR_TEXTURE then record.power = power end
    if frame.background and not record.backgroundOwned then
        record.background = frame.background:GetTexture()
        record.backgroundCoords = { frame.background:GetTexCoord() }
    end
    if frame.name and not record.nameOwned then
        record.font = { frame.name:GetFont() }
    end
end

local function EnsureOutline(frame, record)
    if record.outline then return record.outline end
    local bar = frame.healthBar
    local outline = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = bar:CreateTexture(nil, "OVERLAY")
        edge:SetTexture(1, 1, 1, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", bar, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", bar, side .. "RIGHT", 0, 0)
            edge:SetHeight(OUTLINE_SIZE)
        else
            edge:SetPoint("TOP" .. side, bar, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side, 0, 0)
            edge:SetWidth(OUTLINE_SIZE)
        end
        edge:Hide()
        outline[#outline + 1] = edge
    end
    record.outline = outline
    return outline
end

local function ShowOutline(record, color)
    if not record.outline then return end
    for _, edge in ipairs(record.outline) do
        if color then
            edge:SetVertexColor(color.r, color.g, color.b, 1)
            edge:Show()
        else
            edge:Hide()
        end
    end
end

-- The most urgent debuff type on the unit that this player can remove ("RAID" filter), or nil.
local function DispellableType(unit)
    if not unit then return nil end
    local best
    for index = 1, MAX_DEBUFF_SCAN do
        local name, _, _, _, debuffType = UnitDebuff(unit, index, "RAID")
        if not name then break end
        local rank = debuffType and DISPEL_RANK[debuffType]
        if rank and (not best or rank < best) then
            best = rank
            if rank == 1 then break end
        end
    end
    return best and DISPEL_ORDER[best]
end

local function UpdateDispel(frame)
    local record = records[frame]
    if not record then return end
    local kind = RaidFrames.applied and Config().dispel_highlight ~= false
        and DispellableType(frame.displayedUnit or frame.unit)
    local color = kind and DebuffTypeColor and DebuffTypeColor[kind]
    if color then EnsureOutline(frame, record) end
    ShowOutline(record, color)
end

local function Skin(frame)
    if not (RaidFrames.applied and frame and frame.healthBar) then return end
    local record = records[frame]
    if not record then
        record = {}
        records[frame] = record
    end
    Remember(frame, record)

    if UseOwnBars() then
        frame.healthBar:SetStatusBarTexture(BAR_TEXTURE, "BORDER")
        if frame.powerBar then frame.powerBar:SetStatusBarTexture(BAR_TEXTURE, "BORDER") end
    elseif record.health then
        frame.healthBar:SetStatusBarTexture(record.health, "BORDER")
        if frame.powerBar and record.power then frame.powerBar:SetStatusBarTexture(record.power, "BORDER") end
    end
    if frame.background then
        frame.background:SetTexture(unpack(BACKGROUND_COLOR))
        frame.background:SetTexCoord(0, 1, 0, 1)
        record.backgroundOwned = true
    end
    if frame.name and record.font and record.font[1] then
        frame.name:SetFont(addon.Fonts.PRIMARY, Config().name_size or record.font[2] or 11, NAME_FLAGS)
        record.nameOwned = true
    end
    UpdateDispel(frame)
end

-- Puts back the stock look this file changed, for a module switched off without a reload.
local function Unskin(frame, record)
    if record.health then frame.healthBar:SetStatusBarTexture(record.health, "BORDER") end
    if frame.powerBar and record.power then frame.powerBar:SetStatusBarTexture(record.power, "BORDER") end
    if frame.background and record.backgroundOwned and record.background then
        frame.background:SetTexture(record.background)
        frame.background:SetTexCoord(unpack(record.backgroundCoords))
    end
    record.backgroundOwned = nil
    if frame.name and record.nameOwned and record.font and record.font[1] then
        frame.name:SetFont(unpack(record.font))
    end
    record.nameOwned = nil
    ShowOutline(record, nil)
end

local function ForEachExistingFrame(callback)
    local seen = {}
    local function visit(frame)
        if frame and frame.healthBar and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end
    for frame in pairs(records) do visit(frame) end
    for index = 1, MAX_RAID_FRAMES do visit(_G["CompactRaidFrame" .. index]) end
    for index = 1, GROUP_SIZE do visit(_G["CompactPartyFrameMember" .. index]) end
    for group = 1, MAX_GROUPS do
        for member = 1, GROUP_SIZE do visit(_G["CompactRaidGroup" .. group .. "Member" .. member]) end
    end
end
RaidFrames.ForEachExistingFrame = ForEachExistingFrame

-- Hooks: installed once; they go quiet when the module is off (a hook cannot be removed).
local hooked = false
local function InstallHooks()
    if hooked then return end
    hooked = true
    hooksecurefunc("CompactUnitFrame_SetUpFrame", Skin)
    hooksecurefunc("CompactUnitFrame_UpdateAuras", UpdateDispel)
end

-- Raid profile changes re-run the stock setup on every frame without the hook above.
local containerHooked = false
local function HookContainer()
    if containerHooked or not _G.CompactRaidFrameContainer_ApplyToFrames then return end
    containerHooked = true
    hooksecurefunc("CompactRaidFrameContainer_ApplyToFrames", function()
        if RaidFrames.applied then ForEachExistingFrame(Skin) end
    end)
end

local addonWatcher = CreateFrame("Frame")
addonWatcher:RegisterEvent("ADDON_LOADED")
addonWatcher:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_CompactRaidFrames" then
        HookContainer()
        self:UnregisterAllEvents()
    end
end)

function addon.ApplyRaidFramesSystem()
    InstallHooks()
    HookContainer()
    RaidFrames.applied = true
    ForEachExistingFrame(Skin)
end

function addon.RestoreRaidFramesSystem()
    RaidFrames.applied = false
    for frame, record in pairs(records) do
        Unskin(frame, record)
    end
end

function addon.RefreshRaidFramesSystem()
    if addon:IsModuleEnabled("raid_frames") then
        addon.ApplyRaidFramesSystem()
    else
        addon.RestoreRaidFramesSystem()
    end
end
