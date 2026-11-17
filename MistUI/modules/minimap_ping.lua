-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)

-- The 5.4.8 client draws the ping itself and has no ping frame to attach to, so the label
-- is placed from the event's coordinates and timed here.
local LABEL_SECONDS = 5 -- about as long as the client shows a ping
local FADE_SECONDS = 1
local LABEL_OFFSET_Y = -12
local LABEL_LEVEL_ABOVE_MINIMAP = 5

local holder, label

local function enabled()
    local settings = addon.db and addon.db.profile.minimap
    return settings and settings.ping_sender ~= false and addon:IsModuleEnabled("minimap")
end

local function onUpdate(self, elapsed)
    self.remaining = self.remaining - elapsed
    if self.remaining <= 0 then
        self:Hide()
    elseif self.remaining < FADE_SECONDS then
        self:SetAlpha(self.remaining / FADE_SECONDS)
    end
end

local function createLabel()
    holder = CreateFrame("Frame", nil, Minimap)
    holder:SetSize(1, 1)
    holder:SetFrameLevel(Minimap:GetFrameLevel() + LABEL_LEVEL_ABOVE_MINIMAP)
    holder:SetScript("OnUpdate", onUpdate)
    label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", holder, "CENTER", 0, LABEL_OFFSET_Y)
end

-- x and y run from -0.5 to 0.5 across the minimap, measured from its centre.
local function onPing(_, _, unit, x, y)
    if not (unit and enabled()) or UnitIsUnit(unit, "player") then
        if holder then holder:Hide() end
        return
    end
    if not holder then
        createLabel()
    end
    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
    label:SetText(UnitName(unit))
    label:SetTextColor(color.r, color.g, color.b)

    holder:ClearAllPoints()
    holder:SetPoint("CENTER", Minimap, "CENTER",
        (tonumber(x) or 0) * Minimap:GetWidth(), (tonumber(y) or 0) * Minimap:GetHeight())
    holder.remaining = LABEL_SECONDS
    holder:SetAlpha(1)
    holder:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("MINIMAP_PING")
events:SetScript("OnEvent", onPing)
