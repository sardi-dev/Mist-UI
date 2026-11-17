-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- /mist plates: writes the frame tree of the name plates on screen into the saved settings.
-- The client builds name plates itself and the stock interface code never describes their
-- layout, so the nameplate port needs one real sample from the game before it is written.

local addon = select(2, ...)

local SAVED_VARIABLE = "MistUIDB"
local TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
local MAX_DEPTH = 5
local MAX_LINES = 600
local MAX_KEYS = 20
local FULL_DUMPS = 2

local PlateDump = {}
addon.PlateDump = PlateDump

local lines

local function Add(text)
    if #lines < MAX_LINES then
        lines[#lines + 1] = text
    end
end

local function Number(value)
    return type(value) == "number" and string.format("%.1f", value) or tostring(value)
end

local function Anchor(object)
    if not object.GetNumPoints or object:GetNumPoints() == 0 then
        return "no anchor"
    end
    local point, relativeTo, relativePoint, x, y = object:GetPoint(1)
    local relativeName = relativeTo and (relativeTo.GetName and relativeTo:GetName() or "unnamed") or "nil"
    return string.format("%d pts, %s to %s %s %s,%s", object:GetNumPoints(), tostring(point), relativeName,
        tostring(relativePoint), Number(x), Number(y))
end

local function Common(object)
    return string.format("%s shown=%s vis=%s a=%s %sx%s %s", object:GetName() or "-", tostring(object:IsShown()),
        tostring(object:IsVisible()), Number(object:GetAlpha()), Number(object:GetWidth()), Number(object:GetHeight()),
        Anchor(object))
end

local function Color(r, g, b, a)
    return string.format("%s,%s,%s,%s", Number(r), Number(g), Number(b), Number(a))
end

local function DescribeRegion(region, indent)
    local kind = region:GetObjectType()
    local layer, sublevel = "", ""
    if region.GetDrawLayer then
        layer, sublevel = region:GetDrawLayer()
    end
    local detail = ""
    if kind == "Texture" then
        detail = string.format(" tex=%s color=%s", tostring(region:GetTexture()), Color(region:GetVertexColor()))
    elseif kind == "FontString" then
        local font, size = region:GetFont()
        detail = string.format(" text='%s' font=%s %s color=%s", tostring(region:GetText()), tostring(font),
            Number(size), Color(region:GetTextColor()))
    end
    Add(string.format("%s[%s] %s layer=%s/%s%s", indent, kind, Common(region), tostring(layer), tostring(sublevel),
        detail))
end

-- String keys on the frame's table: names other code gave its parts, if any.
local function DescribeKeys(frame, indent)
    local found = 0
    for key, value in pairs(frame) do
        if type(key) == "string" and found < MAX_KEYS then
            found = found + 1
            local kind = type(value) == "table" and value.GetObjectType and value:GetObjectType() or type(value)
            Add(string.format("%s.%s = %s", indent, key, tostring(kind)))
        end
    end
end

local function DescribeFrame(frame, indent, depth)
    local kind = frame:GetObjectType()
    local detail = string.format(" strata=%s level=%s mouse=%s onshow=%s", tostring(frame:GetFrameStrata()),
        tostring(frame:GetFrameLevel()), tostring(frame:IsMouseEnabled()), tostring(frame:GetScript("OnShow") ~= nil))
    if kind == "StatusBar" then
        local low, high = frame:GetMinMaxValues()
        local barTexture = frame:GetStatusBarTexture()
        detail = detail .. string.format(" value=%s of %s-%s color=%s bartex=%s", Number(frame:GetValue()), Number(low),
            Number(high), Color(frame:GetStatusBarColor()), tostring(barTexture and barTexture:GetTexture()))
    end
    Add(string.format("%s<%s> %s%s", indent, kind, Common(frame), detail))
    DescribeKeys(frame, indent .. "  ")
    for _, region in ipairs({ frame:GetRegions() }) do
        DescribeRegion(region, indent .. "  ")
    end
    if depth >= MAX_DEPTH then
        return
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        DescribeFrame(child, indent .. "  ", depth + 1)
    end
end

local function HasStatusBar(frame, depth)
    if frame:GetObjectType() == "StatusBar" then
        return true
    end
    if depth >= 2 then
        return false
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if HasStatusBar(child, depth + 1) then
            return true
        end
    end
    return false
end

-- Plates are named NamePlate1, NamePlate2 and so on on later clients; an unnamed child that
-- holds a status bar is listed too, in case this client leaves them unnamed.
local function FindPlates()
    local plates = {}
    for _, child in ipairs({ WorldFrame:GetChildren() }) do
        local name = child:GetName()
        if (name and name:match("^NamePlate%d+$")) or (not name and HasStatusBar(child, 0)) then
            plates[#plates + 1] = child
        end
    end
    return plates
end

function PlateDump.Run()
    lines = {}
    local worldChildren = select("#", WorldFrame:GetChildren())
    Add(string.format("time %s, world frame children %d, target '%s'", date(TIME_FORMAT), worldChildren,
        tostring((UnitName("target")))))
    Add(string.format("cvars: enemies=%s friends=%s motion=%s", tostring((GetCVar("nameplateShowEnemies"))),
        tostring((GetCVar("nameplateShowFriends"))), tostring((GetCVar("nameplateMotion")))))
    local plates = FindPlates()
    Add(string.format("plates found %d", #plates))
    for index, plate in ipairs(plates) do
        if index <= FULL_DUMPS then
            Add(string.format("=== plate %d ===", index))
            DescribeFrame(plate, "", 0)
        else
            Add(string.format("plate %d: %s", index, Common(plate)))
        end
    end

    local saved = _G[SAVED_VARIABLE]
    if type(saved) == "table" then
        saved.plateDump = lines
    end
    addon:Print(string.format("Name plates found: %d, %d lines saved. Type /reload so they are written to disk.",
        #plates, #lines))
end
