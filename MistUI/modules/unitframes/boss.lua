-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
-- Art layout (textures, sizes, offsets) adapted from DragonUI (MIT, (c) 2026 NeticSoul);
-- see THIRD_PARTY_NOTICES.

-- Boss frames: the stock boss frames with the art of the target frame.
--
-- The stock code keeps deciding when a boss frame is shown (encounter events) and where it
-- stands (its layout pass puts the first one below the minimap on every pass, mostly in combat,
-- and the others hang below it). This module only repaints the frames. Whatever a protected
-- frame does not allow in combat (scale, hit area) is done once at login for all five frames;
-- the rest is texture, text and bar work, which is allowed at any time and is repeated from
-- hooks after the stock code restores its own art.

local addon = select(2, ...)
local L = addon.L

local UF = addon.UF
if not UF then return end

local KEY = "boss"
local TEXTURES = UF.TEXTURES.targetStyle
local BOSS_COORDS = UF.BOSS_COORDS.targetStyle
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
-- The scale BossTargetFrame_OnLoad gives the frames; the setting multiplies it.
local STOCK_SCALE = 0.75
local PORTRAIT_SIZE = 56
local HEALTH_WIDTH, HEALTH_HEIGHT = 125, 20
local MANA_WIDTH, MANA_HEIGHT = 132, 9
local RAID_ICON_SIZE = 24
-- The winged dragon is the default: a boss unit is a boss whatever its classification says.
local DEFAULT_DECORATION = "rareelite"
local DECORATION_BY_CLASSIFICATION = { worldboss = "rareelite", elite = "elite", rareelite = "rareelite", rare = "rare" }

-- Stock regions that follow the stock health bar's old shape; made invisible, never hidden,
-- because the stock code owns their Show and Hide.
local PREDICTION_FIELDS = {
    "myHealPredictionBar", "otherHealPredictionBar", "totalAbsorbBar", "totalAbsorbBarOverlay",
    "overAbsorbGlow", "overHealAbsorbGlow", "healAbsorbBar", "healAbsorbBarLeftShadow",
    "healAbsorbBarRightShadow",
}

local Boss = UF.CreateModule(KEY)
Boss.textSystems = {}

if addon.RegisterModule then
    addon:RegisterModule(KEY, Boss, L["Boss Frames"], L["Retail-styled boss target frames"])
end

local frames = {}
local isBossFrame = {}

local function Region(frame, suffix)
    return _G[frame:GetName() .. suffix]
end

-- ============================================================================
-- Painting (allowed in combat)
-- ============================================================================

local function PaintDecoration(frame)
    local unit = frame.unit
    local kind = unit and UnitExists(unit) and DECORATION_BY_CLASSIFICATION[UnitClassification(unit)]
    local coords = BOSS_COORDS[kind or DEFAULT_DECORATION]
    local dragon = frame.mistuiDragon
    dragon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    dragon:SetSize(coords[5], coords[6])
    dragon:ClearAllPoints()
    dragon:SetPoint("CENTER", Region(frame, "Portrait"), "CENTER", coords[7], coords[8])
    dragon:Show()
end

-- The stock threat flash, placed like the target frame's. The stock code keeps its colour and
-- decides when it shows; it also puts its own texture and anchor back on every classification
-- check, which is why this runs from that hook.
local function PaintFlash(frame)
    local flash = Region(frame, "Flash")
    flash:SetDrawLayer("BACKGROUND")
    flash:SetTexture(TEXTURES.THREAT)
    flash:SetTexCoord(0, 376 / 512, 0, 134 / 256)
    flash:ClearAllPoints()
    flash:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 24)
    flash:SetSize(188, 67)
end

local function PlaceRaidIcon(icon, portrait)
    icon.mistuiPlacing = true
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", portrait, "TOP", 0, 5)
    icon.mistuiPlacing = nil
end

local function PaintBars(frame, portrait)
    local health, mana = Region(frame, "HealthBar"), Region(frame, "ManaBar")
    health:ClearAllPoints()
    health:SetSize(HEALTH_WIDTH, HEALTH_HEIGHT)
    health:SetPoint("RIGHT", portrait, "LEFT", -1, 0)
    health:SetFrameLevel(frame:GetFrameLevel() + 1)
    mana:ClearAllPoints()
    mana:SetSize(MANA_WIDTH, MANA_HEIGHT)
    mana:SetPoint("RIGHT", portrait, "LEFT", 6.5, -16.5)
    mana:SetFrameLevel(frame:GetFrameLevel() + 1)

    for bar, file in pairs({ [health] = "Health", [mana] = "Mana" }) do
        local fill = bar:GetStatusBarTexture()
        fill:SetAllPoints(bar)
        fill:SetTexture(TEXTURES.BAR_PREFIX .. file)
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetVertexColor(1, 1, 1, 1)
    end
    for _, field in ipairs(PREDICTION_FIELDS) do
        if frame[field] then
            frame[field]:SetAlpha(0)
        end
    end
    return health, mana
end

local function PaintTexts(frame, health, mana)
    local nameBackground = Region(frame, "NameBackground")
    nameBackground:ClearAllPoints()
    nameBackground:SetPoint("BOTTOMLEFT", health, "TOPLEFT", -2, -5)
    nameBackground:SetSize(135, 18)
    nameBackground:SetTexture(TEXTURES.NAME_BACKGROUND)
    nameBackground:SetDrawLayer("BORDER", 1)
    nameBackground:SetBlendMode("ADD")

    local name = Region(frame, "TextureFrameName")
    name:ClearAllPoints()
    name:SetPoint("BOTTOM", health, "TOP", 4, 3)
    name:SetDrawLayer("OVERLAY", 2)

    local level = Region(frame, "TextureFrameLevelText")
    level:ClearAllPoints()
    level:SetPoint("BOTTOMRIGHT", health, "TOPLEFT", 18, 3)
    level:SetDrawLayer("OVERLAY", 2)

    local skull = Region(frame, "TextureFrameHighLevelTexture")
    skull:ClearAllPoints()
    skull:SetPoint("CENTER", level, "CENTER", -9, 6)
    skull:SetAtlasTexture("TargetFrame-HighLevelIcon", true)

    -- Dead and unconscious are two stock texts for the same spot.
    for _, suffix in ipairs({ "TextureFrameDeadText", "TextureFrameUnconsciousText" }) do
        local text = Region(frame, suffix)
        text:ClearAllPoints()
        text:SetPoint("CENTER", health, "CENTER", 0, 0)
        text:SetDrawLayer("OVERLAY")
    end

    -- The text module draws its own numbers over the bars; the stock ones stay invisible.
    for bar, suffix in pairs({ [health] = "TextureFrameHealthBarText", [mana] = "TextureFrameManaBarText" }) do
        local text = Region(frame, suffix)
        text:ClearAllPoints()
        text:SetPoint("CENTER", bar, "CENTER", 0, 0)
        text:SetAlpha(0)
    end
end

local function Paint(frame)
    Region(frame, "TextureFrameTexture"):SetAlpha(0)
    Region(frame, "Background"):SetAlpha(0)

    local portrait = Region(frame, "Portrait")
    portrait:ClearAllPoints()
    portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -47, -15)
    portrait:SetDrawLayer("ARTWORK", 1)

    -- Above the border and the dragon: this stock frame holds the name, level and icons.
    local border = frame.mistuiBorder
    border:SetFrameLevel(frame:GetFrameLevel() + 2)
    Region(frame, "TextureFrame"):SetFrameLevel(border:GetFrameLevel() + 2)

    local health, mana = PaintBars(frame, portrait)
    PaintTexts(frame, health, mana)

    local pvpIcon = Region(frame, "TextureFramePVPIcon")
    pvpIcon:ClearAllPoints()
    pvpIcon:SetPoint("CENTER", frame, "BOTTOMRIGHT", 6, 14)
    pvpIcon:SetDrawLayer("OVERLAY", 7)

    local leaderIcon = Region(frame, "TextureFrameLeaderIcon")
    leaderIcon:ClearAllPoints()
    leaderIcon:SetPoint("BOTTOM", frame, "TOP", 26, -3)

    local raidIcon = Region(frame, "TextureFrameRaidTargetIcon")
    raidIcon:SetDrawLayer("OVERLAY", 7)
    raidIcon:SetSize(RAID_ICON_SIZE, RAID_ICON_SIZE)
    PlaceRaidIcon(raidIcon, portrait)

    PaintDecoration(frame)
    PaintFlash(frame)
end

-- ============================================================================
-- One-time setup (login, outside combat)
-- ============================================================================

-- The bar art carries its own colour and has a shaped end: the fill is kept white and is cropped
-- to the filled share instead of squeezed into it.
local function HookBar(bar)
    hooksecurefunc(bar, "SetStatusBarColor", function(self)
        self:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
    end)
    hooksecurefunc(bar, "SetValue", function(self)
        local _, maximum = self:GetMinMaxValues()
        local value = self:GetValue()
        if maximum and maximum > 0 and value then
            self:GetStatusBarTexture():SetTexCoord(0, value / maximum, 0, 1)
        end
    end)
end

local function CreateArt(frame)
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    background:SetTexture(TEXTURES.BACKGROUND)
    background:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -8)

    -- The border sits on a frame of its own above the bars; the dragon on a child of that one,
    -- which keeps it above the border whatever the draw layers say.
    local border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints(frame)
    border:EnableMouse(false)
    frame.mistuiBorder = border
    local borderArt = border:CreateTexture(nil, "OVERLAY", nil, 5)
    borderArt:SetTexture(TEXTURES.BORDER)
    borderArt:SetPoint("TOPLEFT", background, "TOPLEFT", 0, 0)

    local decoration = CreateFrame("Frame", nil, border)
    decoration:SetAllPoints(frame)
    decoration:EnableMouse(false)
    frame.mistuiDecoration = decoration
    frame.mistuiDragon = decoration:CreateTexture(nil, "OVERLAY", nil, 6)
    frame.mistuiDragon:SetTexture(TEXTURES.BOSS)
    -- Over the border and under the dragon, like the target frame's. Moved once, here: giving a
    -- region of a protected frame another parent is not allowed in combat.
    Region(frame, "Flash"):SetParent(decoration)

    local portrait = Region(frame, "Portrait")
    local mask = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    mask:SetTexture(PORTRAIT_MASK)
    mask:SetVertexColor(0, 0, 0, 1)
    mask:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    mask:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
end

-- The stock code moves the raid target icon back and hides it in ways that lose a mark set
-- while the frame was hidden.
local function HookRaidIcon(frame)
    local icon, portrait = Region(frame, "TextureFrameRaidTargetIcon"), Region(frame, "Portrait")
    hooksecurefunc(icon, "SetPoint", function(self)
        if not self.mistuiPlacing then
            PlaceRaidIcon(self, portrait)
        end
    end)
    hooksecurefunc(icon, "Hide", function(self)
        local unit = frame.unit
        if unit and UnitExists(unit) and GetRaidTargetIndex(unit) then
            self:Show()
        end
    end)
end

local function SetupTexts(frame, index)
    local name = frame:GetName()
    local health, mana = Region(frame, "HealthBar"), Region(frame, "ManaBar")
    Boss.textSystems[index] = addon.TextSystem.SetupFrameTextSystem(KEY, KEY .. index, frame, health, mana, name)

    -- Same bar geometry as the target's: its right end runs under the portrait ring.
    local manaCenter, manaRight = frame[name .. "ManaText"], frame[name .. "ManaTextRight"]
    if manaCenter and manaRight then
        manaCenter:ClearAllPoints()
        manaCenter:SetPoint("CENTER", mana, "CENTER", -2, 0)
        manaRight:ClearAllPoints()
        manaRight:SetPoint("RIGHT", mana, "RIGHT", -13, 0)
    end
end

local function UpdateTexts()
    for _, texts in pairs(Boss.textSystems) do
        texts.update()
    end
end

local function ApplyScale()
    local scale = STOCK_SCALE * (tonumber(UF.GetConfig(KEY).scale) or 1)
    for _, frame in ipairs(frames) do
        frame:SetScale(scale)
    end
end

local function Setup()
    for index = 1, MAX_BOSS_FRAMES do
        local frame = _G["Boss" .. index .. "TargetFrame"]
        frames[index] = frame
        isBossFrame[frame] = true

        -- The stock hit area leaves out the right part of the frame, where the new art has the portrait.
        frame:SetHitRectInsets(0, 0, 0, 0)
        CreateArt(frame)
        HookBar(Region(frame, "HealthBar"))
        HookBar(Region(frame, "ManaBar"))
        HookRaidIcon(frame)
        SetupTexts(frame, index)
        Paint(frame)

        -- Alpha only: the mouse state of a protected frame cannot change in combat.
        addon.VisibilityFade.Register(KEY .. index, frame, {
            enableMouse = false,
            dbTable = function()
                return UF.GetConfig(KEY)
            end,
        })
    end
    ApplyScale()
    addon.TextSystem.RegisterPreviewUpdater(KEY, UpdateTexts)

    -- Both stock functions put stock art back; the first also runs when a boss appears.
    local function Repaint(frame)
        if isBossFrame[frame] then
            Paint(frame)
        end
    end
    hooksecurefunc("TargetFrame_Update", Repaint)
    hooksecurefunc("TargetFrame_CheckClassification", Repaint)

    Boss.initialized = true
    Boss.applied = true
    Boss.configured = true
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

-- Turning the module off takes effect on the next reload: the stock frames are then never touched.
function addon.RefreshBossFrames()
    if not UF.IsEnabled(KEY) then
        return
    end
    if InCombatLockdown() then
        addon.CombatQueue:Add("boss_refresh", addon.RefreshBossFrames)
        return
    end
    if not Boss.configured then
        if not IsLoggedIn() then
            return
        end
        Setup()
    end
    ApplyScale()
    UpdateTexts()
    for index = 1, MAX_BOSS_FRAMES do
        addon.VisibilityFade.Update(KEY .. index)
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", addon.RefreshBossFrames)
