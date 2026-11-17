-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Bar sizes, offsets and art layout adapted from DragonUI (MIT, (c) 2026 NeticSoul)
-- and DragonflightUI (MIT, (c) 2022 Karl-HeinzSchneider); see THIRD_PARTY_NOTICES.

-- Experience and reputation bars: two bars of this addon's own under the action bars. The stock
-- bars stay where they are, invisible, so the stock code that shows, hides and moves them keeps
-- working on frames nobody sees. Part of the action bar module, which starts it.
--
-- The action bars' default positions leave room for one bar below them. This file also tells the
-- shared position code how far to shift them when both bars are shown, or neither.

local addon = select(2, ...)
local L = addon.L

local ART = addon._dir
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 466, 14
-- The background and border strips are 1137 texels wide and ship as two files: a first one of
-- 1024 texels and a second with the remaining 113 of its 128.
local STRIP_FIRST_SHARE = 1024 / 1137
local STRIP_SECOND_COORD = 113 / 128
local BORDER_INSET = 1
local RESTED_ALPHA = 0.69
local MARK_WIDTH, MARK_EXTRA_HEIGHT = 14, 6
local MARK_COORDS = { 596 / 1024, 618 / 1024, 457 / 1024, 487 / 1024 }
-- A character's rested experience can reach one and a half levels.
local RESTED_CAP_LEVELS = 1.5
-- The rows of the short reputation textures sit lower in their files than those of the others.
local SHORT_FILL_TOP, SHORT_FILL_BOTTOM = 0.0605, 0.9677
-- The stock name of the rest state, in the client's language.
local RESTED_WORD = TUTORIAL_TITLE26
local FADE_KEY = "xprepbar"
local FADE_FLAGS = { "show_on_hover", "show_in_combat", "hide_in_combat", "visibility_logic" }

-- Texture by standing: hated and hostile, unfriendly, neutral; friendly and above are green.
local STANDING_TEXTURE = { "RepRed", "RepRed", "RepOrange", "RepYellow" }
local STANDING_FRIEND = 5

-- Saved positions that count as "never moved", for the bars that shift with the status bars.
-- Keep in sync with the widgets defaults in database.lua.
local DEFAULT_POSITIONS = {
    mainbar = { 0, 22 },
    bottombarleft = { 0, 67 },
    bottombarright = { 0, 106 },
    petbar = { 1, 146 },
    stance = { -211, 145 },
    vehicleExit = { -251, 145 },
    xpbar = { 1, 7 },
    repbar = { 1, 23 },
}
local DEFAULT_TOLERANCE = 2
local SHIFTED_WITH_STATUS_BARS = {
    mainbar = true, bottombarleft = true, bottombarright = true,
    petbar = true, stance = true, vehicleExit = true,
}
-- With neither bar the action bars drop only this far: a full slot would sink the end caps.
local EMPTY_DROP = 6
local STATUS_BAR_GAP = 2
-- The rows above the framed main bar sit this much lower, which evens out the gaps between rows.
local FRAMED_ROW_DROP = 1.32
local FRAMED_ROWS = { bottombarleft = true, bottombarright = true, petbar = true }
-- Without the frame the rows close up further.
local UNFRAMED_ROW_Y = { bottombarleft = 64.35, bottombarright = 104 }

local STOCK_BARS = { "MainMenuExpBar", "ReputationWatchBar", "ExhaustionTick" }

local Status = {}
addon.StatusBars = Status

local experience, reputation
local boxes = {}
local lastShift, lastExperienceShown

local function Settings()
    return addon.db.profile.xprepbar
end

local function BarSize()
    local settings = Settings()
    return tonumber(settings.bar_width) or DEFAULT_WIDTH, tonumber(settings.bar_height_dfui) or DEFAULT_HEIGHT
end

local function ExperienceShown()
    local maxXP = UnitXPMax("player")
    if not maxXP or maxXP <= 0 or IsXPUserDisabled() then
        return false
    end
    local cap = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()] or MAX_PLAYER_LEVEL
    return UnitLevel("player") < cap
end

-- name, standing, value and maximum of the watched faction, counted from the start of the standing.
local function WatchedFaction()
    local name, standing, minimum, maximum, value, factionID = GetWatchedFactionInfo()
    if not name then
        return nil
    end
    local friendID, friendValue, _, _, _, _, _, friendThreshold, nextFriendThreshold = GetFriendshipReputation(factionID)
    if friendID then
        if not nextFriendThreshold then
            -- The last rank of a friendship: shown as a full bar, as the stock bar does.
            return name, STANDING_FRIEND, 1, 1
        end
        return name, STANDING_FRIEND, friendValue - friendThreshold, nextFriendThreshold - friendThreshold
    end
    return name, standing, value - minimum, maximum - minimum
end

-- ============================================================================
-- Shared position rules
-- ============================================================================

function addon.IsWidgetAtDefaultPosition(key)
    local known = DEFAULT_POSITIONS[key]
    local saved = addon.db.profile.widgets and addon.db.profile.widgets[key]
    if not known or not saved then
        return false
    end
    -- A bar saved while it stood at one of its automatic heights was not moved either.
    local otherY = UNFRAMED_ROW_Y[key]
    if key == "repbar" then
        otherY = DEFAULT_POSITIONS.xpbar[2]
    end
    local y = saved.posY or 0
    return math.abs((saved.posX or 0) - known[1]) <= DEFAULT_TOLERANCE
        and (math.abs(y - known[2]) <= DEFAULT_TOLERANCE
            or (otherY ~= nil and math.abs(y - otherY) <= DEFAULT_TOLERANCE))
end

function addon.GetDualBarVerticalOffset()
    local experienceShown = ExperienceShown()
    local reputationShown = GetWatchedFactionInfo() ~= nil
    if experienceShown ~= reputationShown then
        return 0
    end
    if not (addon.IsWidgetAtDefaultPosition("xpbar") and addon.IsWidgetAtDefaultPosition("repbar")) then
        return 0
    end
    local _, height = BarSize()
    local slot = height + STATUS_BAR_GAP
    return experienceShown and slot or -math.min(slot, EMPTY_DROP)
end

-- The height a bar that was never moved is drawn at; a moved bar keeps its saved height.
function addon.ResolveWidgetDefaultY(key, posY)
    if not addon.IsWidgetAtDefaultPosition(key) then
        return posY
    end
    if key == "repbar" and not ExperienceShown() then
        -- Alone, the reputation bar takes the experience bar's place.
        return DEFAULT_POSITIONS.xpbar[2]
    end
    if FRAMED_ROWS[key] then
        local buttons = addon.db.profile.buttons
        if buttons and buttons.hide_main_bar_background then
            return UNFRAMED_ROW_Y[key] or DEFAULT_POSITIONS[key][2]
        end
        return DEFAULT_POSITIONS[key][2] - FRAMED_ROW_DROP
    end
    return posY
end

addon._dualBarOffsetWidgets = SHIFTED_WITH_STATUS_BARS

-- ============================================================================
-- Building the bars
-- ============================================================================

-- A strip that spans the bar, drawn from the two files it ships as.
local function CreateStrip(bar, parent, layer, file, inset)
    local first = parent:CreateTexture(nil, layer)
    first:SetTexture(ART .. file)
    first:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, inset)
    first:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, -inset)
    local second = parent:CreateTexture(nil, layer)
    second:SetTexture(ART .. file .. "_r")
    second:SetTexCoord(0, STRIP_SECOND_COORD, 0, 1)
    second:SetPoint("TOPLEFT", first, "TOPRIGHT", 0, 0)
    second:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, -inset)
    local function Fit()
        first:SetWidth(math.max(1, bar:GetWidth() * STRIP_FIRST_SHARE))
    end
    bar:HookScript("OnSizeChanged", Fit)
    Fit()
end

-- The fill art has shaped ends, so it is cropped to the filled share instead of squeezed into it.
local function CropFill(fill)
    local minimum, maximum = fill:GetMinMaxValues()
    if not maximum or maximum <= minimum then
        return
    end
    local share = (fill:GetValue() - minimum) / (maximum - minimum)
    fill:GetStatusBarTexture():SetTexCoord(0, math.max(0, math.min(share, 1)), fill.cropTop or 0, fill.cropBottom or 1)
end

local function CreateFill(bar, file, level, sublevel)
    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetAllPoints(bar)
    fill:SetFrameLevel(level)
    local texture = fill:CreateTexture(nil, "ARTWORK", nil, sublevel)
    texture:SetTexture(ART .. file)
    fill:SetStatusBarTexture(texture)
    fill.texture = texture
    hooksecurefunc(fill, "SetValue", CropFill)
    return fill
end

local function CreateText(fill)
    local text = fill:CreateFontString(nil, "HIGHLIGHT", "SystemFont_Outline_Small")
    text:SetTextColor(1, 1, 1, 1)
    text:SetPoint("CENTER", fill, "CENTER", 0, 1)
    return text
end

local function CreateBar(name, baseLevel)
    local bar = CreateFrame("Frame", name, UIParent)
    bar:SetFrameLevel(baseLevel)
    CreateStrip(bar, bar, "BACKGROUND", "XP\\Background", 0)
    return bar
end

local function ShowExperienceTooltip(owner)
    local current, maximum = UnitXP("player"), UnitXPMax("player")
    if not maximum or maximum <= 0 then
        return
    end
    local rested = GetXPExhaustion() or 0
    local percent = 100 * current / maximum
    GameTooltip_SetDefaultAnchor(GameTooltip, owner)
    GameTooltip:SetText(format("%s%d / %d (%.1f%%)", L["XP: "], current, maximum, percent), 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Remaining: "], format("|cFFFFFFFF%d (%.1f%%)", maximum - current, 100 - percent))
    if rested > 0 then
        GameTooltip:AddDoubleLine(L["Rested: "],
            format("|cFFFFFFFF%d (%.1f%%)", rested, 100 * rested / (maximum * RESTED_CAP_LEVELS)))
    end
    local _, restName, multiplier = GetRestState()
    if restName and multiplier then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format(EXHAUST_TOOLTIP1, restName, multiplier * 100))
    end
    GameTooltip:Show()
end

local function ShowReputationTooltip(owner)
    local name, standing, value, maximum = WatchedFaction()
    if not name then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(name, 1, 1, 1)
    GameTooltip:AddLine(_G["FACTION_STANDING_LABEL" .. standing] or "",
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    GameTooltip:AddDoubleLine(L["Reputation: "], format("|cFFFFFFFF%s / %s", value, maximum))
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function CreateExperienceBar()
    local bar = CreateBar("MistUI_XPBar", 2)

    -- Behind the fill: how far the rested experience reaches.
    bar.rested = CreateFill(bar, "XP\\RestedBackground", 3, 0)
    bar.rested:SetAlpha(RESTED_ALPHA)

    bar.fill = CreateFill(bar, "XP\\Main", 4, 1)
    bar.fill:EnableMouse(true)
    bar.fill:SetScript("OnEnter", ShowExperienceTooltip)
    bar.fill:SetScript("OnLeave", HideTooltip)
    CreateStrip(bar, bar.fill, "OVERLAY", "XP\\Overlay", BORDER_INSET)

    bar.mark = bar.fill:CreateTexture(nil, "OVERLAY", nil, 1)
    bar.mark:SetTexture(ART .. "XP\\uiexperiencebar")
    bar.mark:SetTexCoord(unpack(MARK_COORDS))

    bar.text = CreateText(bar.fill)
    bar.percent = bar.fill:CreateFontString(nil, "HIGHLIGHT", "SystemFont_Outline_Small")
    bar.percent:SetTextColor(1, 1, 1, 1)
    bar.percent:SetPoint("LEFT", bar.text, "RIGHT", 0, 0)
    return bar
end

local function CreateReputationBar()
    local bar = CreateBar("MistUI_RepBar", 2)
    bar.fill = CreateFill(bar, "Reputation\\Rep", 3, 0)
    bar.fill:EnableMouse(true)
    bar.fill:SetScript("OnEnter", ShowReputationTooltip)
    bar.fill:SetScript("OnLeave", HideTooltip)
    -- Opening a window from addon code is not allowed in combat.
    bar.fill:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() then
            ToggleCharacter("ReputationFrame")
        end
    end)
    CreateStrip(bar, bar.fill, "OVERLAY", "XP\\Overlay", BORDER_INSET)
    bar.text = CreateText(bar.fill)
    return bar
end

-- ============================================================================
-- Updating
-- ============================================================================

local function TextLayer()
    return Settings().always_show_text and "OVERLAY" or "HIGHLIGHT"
end

local function UpdateExperience()
    if not ExperienceShown() then
        experience:Hide()
        return
    end
    experience:Show()

    local settings = Settings()
    local width, height = BarSize()
    local current, maximum = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion() or 0

    experience.fill.texture:SetTexture(ART .. (GetRestState() == 1 and "XP\\Rested" or "XP\\Main"))
    experience.fill:SetMinMaxValues(0, maximum)
    experience.fill:SetValue(current)

    local reach = current + rested
    if settings.show_rested_bar ~= false and rested > 0 then
        experience.rested:SetMinMaxValues(0, maximum)
        experience.rested:SetValue(math.min(reach, maximum))
        experience.rested:Show()
    else
        experience.rested:Hide()
    end
    if settings.show_rested_bar ~= false and settings.show_rested_mark ~= false and rested > 0 and reach <= maximum then
        experience.mark:SetSize(MARK_WIDTH, height + MARK_EXTRA_HEIGHT)
        experience.mark:ClearAllPoints()
        experience.mark:SetPoint("LEFT", experience, "LEFT", reach / maximum * width - MARK_WIDTH / 2, 0)
        experience.mark:Show()
    else
        experience.mark:Hide()
    end

    local layer = TextLayer()
    experience.text:SetDrawLayer(layer)
    experience.percent:SetDrawLayer(layer)
    experience.text:SetText(format(L["XP: %d/%d"], current, maximum))
    experience.text:ClearAllPoints()
    if settings.show_xp_percent then
        local share = " = " .. format("%.1f%%", 100 * current / maximum)
        if rested > 0 then
            share = share .. " (" .. format("%.1f%%", 100 * rested / (maximum * RESTED_CAP_LEVELS)) .. " " .. RESTED_WORD .. ")"
        end
        experience.percent:SetText(share)
        experience.percent:Show()
        -- Shifted left by half of the second text, so the two together are centred.
        experience.text:SetPoint("CENTER", experience.fill, "CENTER", -experience.percent:GetStringWidth() / 2, 1)
    else
        experience.percent:Hide()
        experience.text:SetPoint("CENTER", experience.fill, "CENTER", 0, 1)
    end
end

local function UpdateReputation()
    local name, standing, value, maximum = WatchedFaction()
    if not name then
        reputation:Hide()
        return
    end
    reputation:Show()

    local file = STANDING_TEXTURE[standing] or "RepGreen"
    reputation.fill.texture:SetTexture(ART .. "Reputation\\" .. file)
    if file == "RepYellow" then
        reputation.fill.cropTop, reputation.fill.cropBottom = 0, 1
    else
        reputation.fill.cropTop, reputation.fill.cropBottom = SHORT_FILL_TOP, SHORT_FILL_BOTTOM
    end
    reputation.fill:SetMinMaxValues(0, maximum)
    reputation.fill:SetValue(value)

    reputation.text:SetDrawLayer(TextLayer())
    reputation.text:SetText(name .. " " .. value .. " / " .. maximum)
end

local function Resize()
    local settings = Settings()
    local width, height = BarSize()
    local scales = { xpbar = tonumber(settings.expbar_scale) or 1, repbar = tonumber(settings.repbar_scale) or 1 }
    for key, bar in pairs({ xpbar = experience, repbar = reputation }) do
        bar:SetSize(width, height)
        bar:SetScale(scales[key])
        boxes[key]:SetSize(width * scales[key], height * scales[key])
    end
end

-- These boxes hold no protected frames, so they are placed here and not by the shared helper,
-- which skips its work in combat.
local function PlaceBoxes()
    local widgets = addon.db.profile.widgets or {}
    for key, box in pairs(boxes) do
        local known = DEFAULT_POSITIONS[key]
        local saved = widgets[key] or {}
        local anchor = saved.anchor or "BOTTOM"
        box:ClearAllPoints()
        box:SetPoint(anchor, UIParent, anchor, saved.posX or known[1],
            addon.ResolveWidgetDefaultY(key, saved.posY or known[2]))
    end
end

-- The action bars move when the number of status bars changes; they are protected, so the
-- shared code that places them waits for the end of combat by itself.
local function ShiftActionBars()
    local shift = addon.GetDualBarVerticalOffset()
    if shift == lastShift then
        return
    end
    lastShift = shift
    addon.ApplyActionBarPositions()
end

local function Update()
    UpdateExperience()
    UpdateReputation()
    -- Where the reputation bar stands by default depends on whether the experience bar is shown.
    local experienceShown = experience:IsShown() and true or false
    if experienceShown ~= lastExperienceShown then
        lastExperienceShown = experienceShown
        PlaceBoxes()
    end
    ShiftActionBars()
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function HideStockBars()
    for _, name in ipairs(STOCK_BARS) do
        local frame = _G[name]
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    end
end

local function FadeConfig()
    local settings = Settings()
    local bars = addon.db.profile.actionbars or {}
    local config = {
        visibility_shown_alpha = bars.visibility_shown_alpha,
        visibility_hidden_alpha = bars.visibility_hidden_alpha,
        visibility_fade_in_duration = bars.visibility_fade_in_duration,
        visibility_fade_out_duration = bars.visibility_fade_out_duration,
        visibility_fade_out_delay = bars.visibility_fade_out_delay,
    }
    for _, flag in ipairs(FADE_FLAGS) do
        config[flag] = settings[flag]
    end
    return config
end

function Status.Apply()
    HideStockBars()
    experience = CreateExperienceBar()
    reputation = CreateReputationBar()
    for key, entry in pairs({ xpbar = { experience, "XPBar" }, repbar = { reputation, "RepBar" } }) do
        local bar, label = entry[1], entry[2]
        local box = addon.CreateUIFrame(DEFAULT_WIDTH, DEFAULT_HEIGHT, label)
        boxes[key] = box
        addon.ActionBarFrames[key] = box
        bar:SetPoint("CENTER", box, "CENTER")
        addon:RegisterEditableFrame({
            name = key,
            frame = box,
            stockFrame = bar,
            configPath = { "widgets", key },
            module = addon.MainbarsModule,
        })
    end

    local events = CreateFrame("Frame")
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
        "PLAYER_UPDATE_RESTING", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "UPDATE_FACTION",
        "UPDATE_EXPANSION_LEVEL",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", Update)

    addon.VisibilityFade.Register(FADE_KEY, experience, {
        frames = { reputation },
        hoverFrames = { experience.fill, reputation.fill },
        enableMouse = false,
        dbTable = FadeConfig,
    })
    addon.RefreshXpRepBars()
end

function addon.RefreshXpRepBars()
    if not experience then
        return
    end
    Resize()
    Update()
    PlaceBoxes()
    addon.VisibilityFade.Update(FADE_KEY)
end
