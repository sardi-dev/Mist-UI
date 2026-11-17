-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ===============================================================
-- MISTUI PARTY FRAMES MODULE
-- ===============================================================
local addon = select(2, ...)
local UF = addon.UF

-- ===============================================================
-- EARLY EXIT CHECK
-- ===============================================================
-- Simplified: Only check if addon.db exists, not specifically unitframe.party
if not addon or not addon.db then
    return -- Exit early if database not ready
end

-- ===============================================================
-- IMPORTS AND GLOBALS
-- ===============================================================

-- Cache globals and APIs
local _G = _G
local unpack = unpack
local select = select
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitName, UnitClass = UnitName, UnitClass
local UnitExists, UnitIsConnected = UnitExists, UnitIsConnected
local UnitInRange, UnitIsDeadOrGhost = UnitInRange, UnitIsDeadOrGhost
local MAX_PARTY_MEMBERS = MAX_PARTY_MEMBERS or 4
local PARTY_UNIT_TOKENS = { "party1", "party2", "party3", "party4" }

-- ===============================================================
-- MODULE NAMESPACE AND STORAGE
-- ===============================================================

-- Module namespace
local PartyFrames = {}
addon.PartyFrames = PartyFrames

PartyFrames.textElements = {}
PartyFrames.anchor = nil
PartyFrames.initialized = false

-- ===============================================================
-- CONSTANTS AND CONFIGURATION
-- ===============================================================

-- Texture paths from shared core (single source of truth)
local TEXTURES = UF.TEXTURES.party

local PREVIEW_MEMBERS = {
    Alliance = {
        { name = "Aldric", class = "WARRIOR", portrait = "Human_Male", health = 1, mana = 0.35, powerBar = "rageBar", maxPower = 100 },
        { name = "Sylwen", class = "DRUID", portrait = "NightElf_Female", health = 0.82, mana = 0.64, powerBar = "manaBar" },
        { name = "Tobbin", class = "ROGUE", portrait = "Gnome_Male", health = 0.57, mana = 0.91, powerBar = "energyBar", maxPower = 100 },
        { name = "Durgrim", class = "DEATHKNIGHT", portrait = "Dwarf_Male", health = 0.36, mana = 0.48, powerBar = "runicPowerBar", maxPower = 100 },
    },
    Horde = {
        { name = "Grushak", class = "WARRIOR", portrait = "Orc_Male", health = 1, mana = 0.35, powerBar = "rageBar", maxPower = 100 },
        { name = "Hanoka", class = "DRUID", portrait = "Tauren_Male", health = 0.82, mana = 0.64, powerBar = "manaBar" },
        { name = "Morvane", class = "ROGUE", portrait = "Undead_Female", health = 0.57, mana = 0.91, powerBar = "energyBar", maxPower = 100 },
        { name = "Sarethil", class = "DEATHKNIGHT", portrait = "BloodElf_Female", health = 0.36, mana = 0.48, powerBar = "runicPowerBar", maxPower = 100 },
    },
}

local function GetPreviewMember(index)
    local members = PREVIEW_MEMBERS[UnitFactionGroup("player")] or PREVIEW_MEMBERS.Alliance
    return members[index]
end

-- ===============================================================
-- CENTRALIZED SYSTEM INTEGRATION
-- ===============================================================

-- Create auxiliary frame for anchoring (similar to target.lua)
local function CreatePartyAnchorFrame()
    if PartyFrames.anchor then
        return PartyFrames.anchor
    end

    -- Use centralized function from core.lua
    -- Initial size - will be updated dynamically based on orientation
    PartyFrames.anchor = addon.CreateUIFrame(130, 300, "PartyFrames")

    return PartyFrames.anchor
end

-- Update anchor size based on orientation
local function UpdatePartyAnchorSize()
    if not PartyFrames.anchor then return end
    
    local settings = addon.db and addon.db.profile and addon.db.profile.unitframe and addon.db.profile.unitframe.party
    local orientation = settings and settings.orientation or 'vertical'
    local numMembers = MAX_PARTY_MEMBERS -- 4
    local scale = (settings and tonumber(settings.scale)) or 1

    if orientation == 'horizontal' then
        local padding = (settings and tonumber(settings.padding_horizontal)) or 50
        local frameWidth = 120
        local frameHeight = 50
        local totalWidth = numMembers * frameWidth + (numMembers - 1) * padding
        PartyFrames.anchor:SetSize(totalWidth * scale, frameHeight * scale)
    else
        local padding = (settings and tonumber(settings.padding_vertical)) or 30
        local frameWidth = 130
        local frameHeight = 50
        local totalHeight = numMembers * frameHeight + (numMembers - 1) * padding
        PartyFrames.anchor:SetSize(frameWidth * scale, totalHeight * scale)
    end
end

-- A row when horizontal, a column when vertical; shared by styling, the editor and the update hook.
local function PlacePartyMemberFrame(frame, index, step, orientation)
    frame:ClearAllPoints()
    if orientation == 'horizontal' then
        frame:SetPoint("TOPLEFT", PartyFrames.anchor, "TOPLEFT", (index - 1) * step, 0)
    else
        frame:SetPoint("TOPLEFT", PartyFrames.anchor, "TOPLEFT", 0, (index - 1) * -step)
    end
end

-- The stock raid frame manager stands on the left edge of the screen. It belongs to an add-on of the
-- client that is loaded by default, so the party frames make room for it whenever it exists.
local function IsCompactRaidFrameAddonLoaded()
    return _G.CompactRaidFrameManager ~= nil
end

local function GetDefaultPartyPosX()
    return 10
end

local function GetCompactRaidPartyOffsetX()
    -- Runtime-only offset: avoids persisting shifted positions in the profile.
    if IsCompactRaidFrameAddonLoaded() then
        return 9
    end
    return 0
end

local function NormalizeCompactRaidPartyPosX(posX)
    local basePosX = posX or GetDefaultPartyPosX()

    -- Backward compatibility: old migrated defaults should fall back to base when
    -- CompactRaidFrames is not active.
    if not IsCompactRaidFrameAddonLoaded() then
        if basePosX == 19 or basePosX == 25 or basePosX == 30 then
            return GetDefaultPartyPosX()
        end
        return basePosX
    end

    -- Apply offset only for default-like positions, keep custom positions intact.
    if basePosX == 10 or basePosX == 19 or basePosX == 25 or basePosX == 30 then
        return GetDefaultPartyPosX() + GetCompactRaidPartyOffsetX()
    end

    return basePosX
end

-- Function to apply position from widgets (similar to target.lua)
local function ApplyWidgetPosition()
    if not PartyFrames.anchor then
        return
    end

    -- CRITICAL: Set BACKGROUND strata to stay behind Compact Raid Frames (which use LOW/MEDIUM)
    -- But skip strata reset during editor mode (overlay needs FULLSCREEN strata)
    if not InCombatLockdown() and not (addon.EditorMode and addon.EditorMode:IsActive()) then
        PartyFrames.anchor:SetFrameStrata('BACKGROUND')
        PartyFrames.anchor:SetFrameLevel(1)
    end

    -- Ensure configuration exists
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets then
        return
    end

    local widgetConfig = addon.db.profile.widgets.party

    if widgetConfig and widgetConfig.posX and widgetConfig.posY then
        local normalizedPosX = NormalizeCompactRaidPartyPosX(widgetConfig.posX)
        if normalizedPosX ~= widgetConfig.posX then
            widgetConfig.posX = normalizedPosX
        end

        -- Use saved anchor, not always TOPLEFT
        local anchor = widgetConfig.anchor or "TOPLEFT"
        PartyFrames.anchor:ClearAllPoints()
        PartyFrames.anchor:SetPoint(anchor, UIParent, anchor, normalizedPosX, widgetConfig.posY)
    else
        -- Create default configuration if it doesn't exist
        if not addon.db.profile.widgets.party then
            addon.db.profile.widgets.party = {
                anchor = "TOPLEFT",
                posX = GetDefaultPartyPosX(),
                posY = -200
            }
        end
        PartyFrames.anchor:ClearAllPoints()
        PartyFrames.anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", GetDefaultPartyPosX(), -200)
    end
end

-- Functions required by the centralized system
function PartyFrames:LoadDefaultSettings()
    -- Ensure configuration exists in widgets
    if not addon.db.profile.widgets then
        addon.db.profile.widgets = {}
    end

    if not addon.db.profile.widgets.party then
        addon.db.profile.widgets.party = {
            anchor = "TOPLEFT",
            posX = GetDefaultPartyPosX(),
            posY = -200
        }
    end

    -- Ensure configuration exists in unitframe
    if not addon.db.profile.unitframe then
        addon.db.profile.unitframe = {}
    end

    if not addon.db.profile.unitframe.party then
        addon.db.profile.unitframe.party = {
            enabled = true,
            classcolor = false,
            textFormat = 'both',
            breakUpLargeNumbers = true,
            showHealthTextAlways = false,
            showManaTextAlways = false,
            orientation = 'vertical',
            padding_vertical = 30,
            padding_horizontal = 50,
            scale = 1.0,
            override = false,
            anchor = 'TOPLEFT',
            anchorParent = 'TOPLEFT',
            x = GetDefaultPartyPosX(),
            y = -200
        }
    end
end

function PartyFrames:UpdateWidgets()
    ApplyWidgetPosition()
    UpdatePartyAnchorSize() -- Update anchor size based on orientation
    PartyFrames:LayoutFrames()
end

-- The stock rule (GetDisplayedAllyFrames in UIParent.lua): party frames show in a group that is neither a
-- raid nor set to the raid-style party frames, and in an arena without that setting.
local function ShouldPartyFramesBeVisible()
    return GetNumSubgroupMembers() > 0 and GetDisplayedAllyFrames() == "party"
end

-- Test functions for the editor
local function ShowPartyFramesTest()
    -- Update anchor size for editor mode
    UpdatePartyAnchorSize()
    PartyFrames:LayoutFrames()
    -- Raise overlay strata so it appears ABOVE fake party frames
    if PartyFrames.anchor then
        PartyFrames.anchor:SetFrameStrata('FULLSCREEN')
        PartyFrames.anchor:SetFrameLevel(200)
    end
    -- Display party frames even if not in a group, keep strata below overlay
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            frame:SetFrameStrata('BACKGROUND')
            frame:SetFrameLevel(1)
        end
    end
    PartyFrames:UpdateEditorPreview()
end

local function HidePartyFramesTest()
    -- Restore normal strata
    if PartyFrames.anchor then
        PartyFrames.anchor:SetFrameStrata('MEDIUM')
        PartyFrames.anchor:SetFrameLevel(1)
    end
    -- Hide empty frames when not in a party. The frames are protected, so never during combat.
    if InCombatLockdown() then
        return
    end
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame and not UnitExists("party" .. i) then
            frame:Hide()
            local name = _G[frame:GetName() .. 'Name']
            local portrait = _G[frame:GetName() .. 'Portrait']
            if name then
                name:SetText("")
            end
            -- If SetPortraitTexture fails on a far-away member, the race portrait could stay behind.
            if portrait then
                portrait:SetTexture(nil)
            end
        end
    end
end

-- ===============================================================
-- HELPER FUNCTIONS
-- ===============================================================

-- Get settings helper
local function GetSettings()
    -- Perform a robust check with default values
    if not addon.db or not addon.db.profile then
        return {
            scale = 1.0,
            classcolor = false,
            breakUpLargeNumbers = true
        }
    end

    local settings = addon.db.profile.unitframe and addon.db.profile.unitframe.party

    -- If configuration doesn't exist, create it with defaults
    if not settings then
        if not addon.db.profile.unitframe then
            addon.db.profile.unitframe = {}
        end

        addon.db.profile.unitframe.party = {
            enabled = true,
            classcolor = false,
            textFormat = 'both',
            breakUpLargeNumbers = true,
            showHealthTextAlways = false,
            showManaTextAlways = false,
            orientation = 'vertical',
            padding_vertical = 30,
            padding_horizontal = 50,
            scale = 1.0,
            override = false,
            anchor = 'TOPLEFT',
            anchorParent = 'TOPLEFT',
            x = GetDefaultPartyPosX(),
            y = -200
        }
        settings = addon.db.profile.unitframe.party
    end
    
    return settings
end

-- Format numbers helper - delegates to shared TextSystem
-- Text formatting - delegates to shared TextSystem
local function GetFormattedText(current, max, textFormat, breakUpLargeNumbers)
    return addon.TextSystem.FormatStatusText(current, max, textFormat, breakUpLargeNumbers)
end

-- Calculate step based on orientation
local function GetPartyStep()
    local settings = GetSettings()
    local orientation = settings and settings.orientation or 'vertical'
    
    if orientation == 'horizontal' then
        local pad = (settings and tonumber(settings.padding_horizontal)) or 50
        local base = 120  -- width of party frame
        return base + pad
    else
        local pad = (settings and tonumber(settings.padding_vertical)) or 30
        local base = 49   -- height of party frame
        return base + pad
    end
end

-- Get orientation from settings
local function GetOrientation()
    local settings = GetSettings()
    return settings and settings.orientation or 'vertical'
end

-- A method because UpdateWidgets and the editor test sit above the locals this reads.
function PartyFrames:LayoutFrames()
    if InCombatLockdown() or not self.anchor then return end

    local step = GetPartyStep()
    local orientation = GetOrientation()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            PlacePartyMemberFrame(frame, i, step, orientation)
        end
    end
end


-- Power bar texture resolver (delegates to shared core)
local function GetPowerBarTexture(unit)
    return UF.GetPartyPowerBarTexture(unit)
end

-- The unit a party frame shows. The stock frame swaps to the member's vehicle ("partypetN") while the
-- member rides one, so bars and numbers read this; who the member is stays "partyN".
local function GetDisplayedUnit(frame)
    return frame.unit or ("party" .. frame:GetID())
end

-- ===============================================================
-- CLASS COLORS
-- ===============================================================

-- New function: Get class color for party member
local function GetPartyClassColor(partyIndex)
    local unit = "party" .. partyIndex
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return 1, 1, 1 -- White if not a player
    end

    local _, class = UnitClass(unit)
    if class and RAID_CLASS_COLORS[class] then
        local color = RAID_CLASS_COLORS[class]
        return color.r, color.g, color.b
    end

    return 1, 1, 1 -- White by default
end

-- New function: Update party health bar with class color
local function UpdatePartyHealthBarColor(partyIndex)
    if not partyIndex or partyIndex < 1 or partyIndex > 4 then
        return
    end

    local unit = "party" .. partyIndex
    if not UnitExists(unit) then
        return
    end

    -- Color our own overlay bar, never the stock native bar (touching it taints it).
    local frame = _G['PartyMemberFrame' .. partyIndex]
    local healthbar = frame and frame.MistUI_HealthBar
    if not healthbar then
        return
    end

    local settings = GetSettings()
    if not settings then
        return
    end

    local texture = healthbar:GetStatusBarTexture()
    if not texture then
        return
    end

    if settings.classcolor and UnitIsPlayer(unit) then
        -- Use constant instead of hardcoded string
        local statusTexturePath = TEXTURES.healthBarStatus
        if texture:GetTexture() ~= statusTexturePath then
            texture:SetTexture(statusTexturePath)
        end

        -- Apply class color
        local r, g, b = GetPartyClassColor(partyIndex)
        healthbar:SetStatusBarColor(r, g, b, 1)
    else
        -- Use constant instead of hardcoded string
        local normalTexturePath = TEXTURES.healthBar
        if texture:GetTexture() ~= normalTexturePath then
            texture:SetTexture(normalTexturePath)
        end

        -- White color (texture already has color)
        healthbar:SetStatusBarColor(1, 1, 1, 1)
    end
end
-- ===============================================================
-- SIMPLE STOCK BUFF/DEBUFF REPOSITIONING
-- ===============================================================
local function RepositionStockBuffs()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            -- Position auras fully outside frame right edge
            -- Buff row at top, debuff row below (no vertical overlap between members)
            for auraIndex = 1, 4 do
                local buff = _G['PartyMemberFrame' .. i .. 'Buff' .. auraIndex]
                local debuff = _G['PartyMemberFrame' .. i .. 'Debuff' .. auraIndex]

                if buff then
                    buff:ClearAllPoints()
                    buff:SetPoint('TOPLEFT', frame, 'TOPRIGHT', 2 + (auraIndex - 1) * 17, -2)
                    buff:SetSize(15, 15)
                end

                if debuff then
                    debuff:ClearAllPoints()
                    debuff:SetPoint('TOPLEFT', frame, 'TOPRIGHT', 2 + (auraIndex - 1) * 17, -19)
                    debuff:SetSize(15, 15)
                end
            end
        end
    end
end


-- ===============================================================
-- DYNAMIC CLIPPING SYSTEM
-- ===============================================================

-- Bar geometry from the frame style (UF.SKINS.<style>.party.bars), TOPLEFT on the party frame.
local function PlacePartyBar(bar, frame, key)
    local b = UF.GetFrameSkin().party.bars[key]
    bar:SetSize(b.w, b.h)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", b.x, b.y)
end

local function PlacePartyIcon(icon, frame, spot)
    icon:SetSize(spot.w, spot.h)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", spot.x, spot.y)
end

-- The stock PartyMemberFrame_UpdateAssignedRoles sets PORTRAITROLES texcoords; this puts our sheet back after it.
local function ApplyPartyRole(frame)
    local icon = frame and _G[frame:GetName() .. 'RoleIcon']
    if not icon then return end
    local cell = UF.STATUS_ICONS.roles[UnitGroupRolesAssigned("party" .. frame:GetID())]
    PlacePartyIcon(icon, frame, UF.PARTY_ICONS.role)
    if cell then
        icon:SetTexture(UF.STATUS_ICONS.file)
        icon:SetTexCoord(unpack(cell))
    end
end

-- Crown, guide, master looter and role at retail's spots.
local function ApplyPartyIcons(frame)
    local name = frame:GetName()
    local leader = _G[name .. 'LeaderIcon']
    if leader then
        PlacePartyIcon(leader, frame, UF.PARTY_ICONS.leader)
        leader:SetTexture(UF.STATUS_ICONS.file)
        leader:SetTexCoord(unpack(UF.STATUS_ICONS.leader))
    end
    local guide = _G[name .. 'GuideIcon']
    if guide then
        PlacePartyIcon(guide, frame, UF.PARTY_ICONS.leader)
        guide:SetTexture(UF.STATUS_ICONS.file)
        guide:SetTexCoord(unpack(UF.STATUS_ICONS.guide))
    end
    local master = _G[name .. 'MasterIcon']
    if master then
        PlacePartyIcon(master, frame, UF.PARTY_ICONS.master)
        master:SetTexture(UF.STATUS_ICONS.file)
        master:SetTexCoord(unpack(UF.STATUS_ICONS.master))
    end
    ApplyPartyRole(frame)
end

-- Runs after PartyMemberFrame_UpdatePvPStatus, the only code that shows the icon.
local function ApplyPartyPvP(frame)
    local id = frame:GetID()
    local icon = _G["PartyMemberFrame" .. id .. "PVPIcon"]
    if not icon then return end
    local kind = UF.GetPvPKind("party" .. id)
    UF.ApplyClassicPvPTexture(icon, kind, true)
    -- Alpha, not Hide: stock owns the icon's Show/Hide.
    icon:SetAlpha(1)
end

-- Art and bars for the current frame style; read at apply time, so a style switch is a refresh.
local function ApplyPartySkin(frame)
    local skin = UF.GetFrameSkin().party
    if frame.MistUI_Background then
        UF.ApplySkinPiece(frame.MistUI_Background, skin.background, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    end
    local border = frame.MistUI_BorderFrame and frame.MistUI_BorderFrame.texture
    if border then
        UF.ApplySkinPiece(border, skin.border, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    end
    if frame.MistUI_HealthBar then
        PlacePartyBar(frame.MistUI_HealthBar, frame, "health")
    end
    if frame.MistUI_ManaBar then
        PlacePartyBar(frame.MistUI_ManaBar, frame, "mana")
    end
    local flash = _G[frame:GetName() .. 'Flash']
    if flash then
        UF.ApplySkinPiece(flash, skin.flash, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    end
    ApplyPartyIcons(frame)
    ApplyPartyPvP(frame)
end

-- Create our own health StatusBar overlaid on the stock native one. We never touch
-- the native bar (that taints it and breaks its in-combat/vehicle Show/Hide); instead
-- we read its value via the SetValue hook and mirror it onto our own bar.
local function EnsureDragonHealthBar(frame)
    if not frame or frame.MistUI_HealthBar then
        return frame and frame.MistUI_HealthBar
    end

    local native = _G[frame:GetName() .. 'HealthBar']
    if not native then
        return nil
    end

    local db = CreateFrame("StatusBar", nil, frame)
    -- Geometry from the frame style (native bar is hidden below via SetAlpha, see test below).
    PlacePartyBar(db, frame, "health")
    db:SetFrameLevel(native:GetFrameLevel() + 1)
    db:SetStatusBarTexture(TEXTURES.healthBar)
    db:SetStatusBarColor(1, 1, 1, 1)
    frame.MistUI_HealthBar = db

    -- Hide the native bar under our overlay; SetAlpha doesn't taint the frame (reskinning it does).
    native:SetAlpha(0)

    return db
end

-- Clip/color logic for a party health bar. `self` is the stock native bar (from the
-- SetValue hook or a direct call) and is only READ; all writes go to our own overlay.
local function ApplyHealthBarClipping(self, value)
    local frame = self:GetParent()
    if not frame then
        return
    end
    local db = EnsureDragonHealthBar(frame)
    if not db then
        return
    end
    local frameIndex = frame:GetID()
    -- NOTE: Do NOT early return on !UnitExists - during ghost/spirit release
    -- UnitExists can briefly return false, leaving texture stuck invisible

    -- Mirror the native bar's range/value onto our own (read-only on the native bar).
    local min, max = self:GetMinMaxValues()
    local current = value or self:GetValue()
    db:SetMinMaxValues(min, max)
    db:SetValue(current or 0)

    local texture = db:GetStatusBarTexture()
    if not texture then
        return
    end

    -- If disconnected, show full bar in gray (stock native behavior)
    if frame.MistUI_Disconnected then
        texture:SetTexCoord(0, 1, 0, 1)
        db:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        return
    end

    -- Apply class color first (safe if unit doesn't exist - checks internally)
    UpdatePartyHealthBarColor(frameIndex)

    -- Dynamic clipping: Only show the filled part of the texture
    if max > 0 and current then
        -- Clamp to [0.001, 1] - max=1 can happen during BG loading/phasing
        -- while current holds the real health value, producing TexCoord out of range
        local percentage = math.min(math.max(current / max, 0.001), 1)
        texture:SetTexCoord(0, percentage, 0, 1)
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

-- Setup dynamic texture clipping for health bars
local function SetupHealthBarClipping(frame)
    if not frame then
        return
    end

    local healthbar = _G[frame:GetName() .. 'HealthBar']
    if not healthbar then
        return
    end

    EnsureDragonHealthBar(frame)

    if not healthbar.MistUI_ClippingSetup then
        -- Read-only hook: the stock SetValue drives our overlay, native bar untouched.
        hooksecurefunc(healthbar, "SetValue", ApplyHealthBarClipping)
        healthbar.MistUI_ClippingSetup = true
        ApplyHealthBarClipping(healthbar, healthbar:GetValue()) -- seed initial fill
    end
end

-- Create our own mana StatusBar overlaid on the stock native one (see health bar rationale).
local function EnsureDragonManaBar(frame)
    if not frame or frame.MistUI_ManaBar then
        return frame and frame.MistUI_ManaBar
    end

    local native = _G[frame:GetName() .. 'ManaBar']
    if not native then
        return nil
    end

    local db = CreateFrame("StatusBar", nil, frame)
    PlacePartyBar(db, frame, "mana")
    db:SetFrameLevel(native:GetFrameLevel() + 1)
    local initTex = GetPowerBarTexture(GetDisplayedUnit(frame))
    db:SetStatusBarTexture(initTex)
    db.__mistUI_powerTex = initTex
    db:SetStatusBarColor(1, 1, 1, 1)
    frame.MistUI_ManaBar = db

    -- Hide the native bar under our overlay; SetAlpha doesn't taint (see health bar).
    native:SetAlpha(0)

    return db
end

-- Clip/texture logic for a party mana bar. `self` is the stock native bar (read-only);
-- all writes go to our own overlay.
local function ApplyManaBarClipping(self, value)
    local frame = self:GetParent()
    if not frame then
        return
    end
    local db = EnsureDragonManaBar(frame)
    if not db then
        return
    end
    local unit = GetDisplayedUnit(frame)
    -- NOTE: Do NOT early return on !UnitExists - see health bar comment

    -- If disconnected, mana bar is hidden (alpha=0), skip all processing
    if frame.MistUI_Disconnected then
        return
    end

    -- Mirror the native bar's range/value onto our own (read-only on the native bar).
    local min, max = self:GetMinMaxValues()
    local current = value or self:GetValue()
    db:SetMinMaxValues(min, max)
    db:SetValue(current or 0)

    -- Power-type texture (energy, rage, etc.) - only reassign when it actually changes.
    -- SetStatusBarTexture every SetValue rebuilds the texture region and caused a
    -- periodic hitch (energy ticks ~every 2s drove it constantly).
    local powerTexture = GetPowerBarTexture(unit)
    if db.__mistUI_powerTex ~= powerTexture then
        db:SetStatusBarTexture(powerTexture)
        db.__mistUI_powerTex = powerTexture
    end

    local texture = db:GetStatusBarTexture()
    if not texture then
        return
    end

    if max > 0 and current then
        -- Clamp to [0.001, 1] - max=1 can happen during BG loading/phasing
        -- while current holds the real mana value, producing TexCoord out of range
        local percentage = math.min(math.max(current / max, 0.001), 1)
        texture:SetTexCoord(0, percentage, 0, 1)
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end

    texture:SetVertexColor(1, 1, 1, 1)
end

-- Setup dynamic texture clipping for mana bars
local function SetupManaBarClipping(frame)
    if not frame then
        return
    end

    local manabar = _G[frame:GetName() .. 'ManaBar']
    if not manabar then
        return
    end

    EnsureDragonManaBar(frame)

    if not manabar.MistUI_ClippingSetup then
        -- Read-only hook: the stock SetValue drives our overlay, native bar untouched.
        hooksecurefunc(manabar, "SetValue", ApplyManaBarClipping)
        manabar.MistUI_ClippingSetup = true
        ApplyManaBarClipping(manabar, manabar:GetValue()) -- seed initial fill
    end
end

-- ===============================================================
-- TEXT MANAGEMENT SYSTEM (TAINT-FREE)
-- ===============================================================

-- Hide stock texts permanently with alpha 0 (no taint)
-- Fields the stock UnitFrame_Initialize gives a frame for its heal prediction and absorb textures.
local PREDICTION_FIELDS = {
    "myHealPredictionBar", "otherHealPredictionBar", "totalAbsorbBar", "totalAbsorbBarOverlay",
    "overAbsorbGlow", "overHealAbsorbGlow", "healAbsorbBar", "healAbsorbBarLeftShadow",
    "healAbsorbBarRightShadow",
}

local function HideStockTexts(frame)
    if not frame then return end

    -- The stock prediction textures follow the native health bar, which sits hidden under ours at
    -- another spot and size. Alpha only: the stock code owns their Show and Hide.
    for _, field in ipairs(PREDICTION_FIELDS) do
        if frame[field] then
            frame[field]:SetAlpha(0)
        end
    end

    
    local healthText = _G[frame:GetName() .. 'HealthBarText']
    local manaText = _G[frame:GetName() .. 'ManaBarText']
    
    -- Set alpha to 0 instead of hiding to avoid taint
    -- Use hooksecurefunc to re-force alpha=0 after any stock SetAlpha call
    -- A recursion guard flag prevents infinite loop since our SetAlpha(0) also triggers the hook
    if healthText then
        healthText:SetAlpha(0)
        if not healthText.MistUI_AlphaHooked then
            hooksecurefunc(healthText, "SetAlpha", function(self, alpha)
                if not self.MistUI_AlphaGuard and alpha ~= 0 then
                    self.MistUI_AlphaGuard = true
                    self:SetAlpha(0)
                    self.MistUI_AlphaGuard = nil
                end
            end)
            healthText.MistUI_AlphaHooked = true
        end
    end
    
    if manaText then
        manaText:SetAlpha(0)
        if not manaText.MistUI_AlphaHooked then
            hooksecurefunc(manaText, "SetAlpha", function(self, alpha)
                if not self.MistUI_AlphaGuard and alpha ~= 0 then
                    self.MistUI_AlphaGuard = true
                    self:SetAlpha(0)
                    self.MistUI_AlphaGuard = nil
                end
            end)
            manaText.MistUI_AlphaHooked = true
        end
    end
end

-- Tracking hover state to prevent text disappearing during updates
local hoverStates = {}

-- Forward declaration for CreateCustomTexts (used in update functions)
local CreateCustomTexts
local UpdateHealthText
local UpdateManaText

local PARTY_TEXT_SIZE = 11
local PARTY_TEXT_FLAGS = "OUTLINE"

local function ApplyPartyTextVisualStyle(fontString)
    if not fontString then
        return
    end

    fontString:SetTextColor(1, 1, 1, 1)
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 1)
end

local function GetPartyTextFontPath()
    return (UF and UF.DEFAULT_FONT) or (addon.Fonts and addon.Fonts.PRIMARY) or "Fonts\\FRIZQT__.TTF"
end

local function EnsurePartyTextFont(fontString)
    if not fontString then
        return false
    end

    if fontString:GetFont() then
        return true
    end

    if GameFontNormalSmall then
        fontString:SetFontObject(TextStatusBarText or GameFontNormalSmall)
    end

    local fontPath = GetPartyTextFontPath()
    if fontPath and fontString:SetFont(fontPath, PARTY_TEXT_SIZE, PARTY_TEXT_FLAGS) then
        return true
    end

    local fallbackPath, _, fallbackFlags = fontString:GetFont()
    if fallbackPath then
        return fontString:SetFont(fallbackPath, PARTY_TEXT_SIZE, fallbackFlags or PARTY_TEXT_FLAGS) and true or false
    end

    return false
end

-- ===============================================================
-- TEXT AND COLOR UPDATE FUNCTIONS
-- ===============================================================

local BAR_TEXT_KINDS = {
    health = {
        center = "MistUI_HealthText",
        left = "MistUI_HealthTextLeft",
        right = "MistUI_HealthTextRight",
        hoverKey = "health",
        alwaysKey = "showHealthTextAlways",
        GetValues = function(unit) return UnitHealth(unit), UnitHealthMax(unit) end,
    },
    mana = {
        center = "MistUI_ManaText",
        left = "MistUI_ManaTextLeft",
        right = "MistUI_ManaTextRight",
        hoverKey = "mana",
        alwaysKey = "showManaTextAlways",
        GetValues = function(unit) return UnitPower(unit), UnitPowerMax(unit) end,
    },
}

local function HidePartyBarText(frame, spec)
    local center, left, right = frame[spec.center], frame[spec.left], frame[spec.right]
    if center then center:Hide() end
    if left then left:Hide() end
    if right then right:Hide() end
end

-- Taint-free health/mana text update
local function UpdatePartyBarText(kind, statusBar, forceShow)
    if not statusBar then return end

    local spec = BAR_TEXT_KINDS[kind]
    local frame = statusBar:GetParent()
    local frameIndex = frame:GetName():match("PartyMemberFrame(%d+)")
    if not frameIndex then return end

    local TextSystem = addon.TextSystem
    local partyUnit, fake = TextSystem.GetPreviewUnit("party" .. frameIndex)
    if not UnitExists(partyUnit) then return end

    if not fake and not UnitIsConnected(partyUnit) then
        HidePartyBarText(frame, spec)
        return
    end

    CreateCustomTexts(frame)

    local centerText = frame[spec.center]
    if not centerText then return end

    local settings = GetSettings()

    local hoverState = hoverStates[tonumber(frameIndex)]
    local isHovering = false

    if hoverState then
        isHovering = hoverState.portrait or hoverState[spec.hoverKey]
    end

    local shouldShow = false

    if forceShow or isHovering or TextSystem.IsPreviewing("party") then
        shouldShow = true
    elseif settings and settings[spec.alwaysKey] then
        shouldShow = true
    end

    if not shouldShow then
        HidePartyBarText(frame, spec)
        return
    end

    local current, max = spec.GetValues(fake and partyUnit or GetDisplayedUnit(frame))
    if fake then
        local member = GetPreviewMember(tonumber(frameIndex))
        current, max = TextSystem.ScalePreviewValues(kind, current, max)
        if kind == "mana" and member.maxPower then
            max = member.maxPower
        end
        current = math.floor(max * member[kind])
    end

    if current and max and max > 0 then
        local textFormat = settings and settings.textFormat or "formatted"
        local breakUp = settings and settings.breakUpLargeNumbers
        local finalText = GetFormattedText(current, max, textFormat, breakUp)
        local leftText, rightText = frame[spec.left], frame[spec.right]

        if textFormat == "both" and type(finalText) == "table" then
            centerText:Hide()
            if EnsurePartyTextFont(leftText) then
                leftText:SetText(finalText.left or "")
                leftText:Show()
            end
            if EnsurePartyTextFont(rightText) then
                rightText:SetText(finalText.right or "")
                rightText:Show()
            end
        else
            if leftText then leftText:Hide() end
            if rightText then rightText:Hide() end
            if EnsurePartyTextFont(centerText) then
                centerText:SetText(finalText or "")
                centerText:Show()
            end
        end
    else
        HidePartyBarText(frame, spec)
    end
end

UpdateHealthText = function(statusBar, forceShow)
    UpdatePartyBarText("health", statusBar, forceShow)
end

UpdateManaText = function(statusBar, forceShow)
    UpdatePartyBarText("mana", statusBar, forceShow)
end

-- The editor's fake members have no unit events, so format changes repaint their texts from here.
local function RefreshPartyPreviewTexts()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame and frame:IsShown() then
            local healthBar = frame.MistUI_HealthBar or _G[frame:GetName() .. 'HealthBar']
            local manaBar = frame.MistUI_ManaBar or _G[frame:GetName() .. 'ManaBar']
            if healthBar then UpdateHealthText(healthBar, false) end
            if manaBar then UpdateManaText(manaBar, false) end
        end
    end
end
addon.TextSystem.RegisterPreviewUpdater("party", RefreshPartyPreviewTexts)

-- Create invisible hover frames for independent health/mana text display
local function CreateHoverFrames(frame, frameIndex)
    if not frame or frame.MistUI_HoverFrames then return end
    
    local healthBar = EnsureDragonHealthBar(frame) or _G[frame:GetName() .. 'HealthBar']
    local manaBar = EnsureDragonManaBar(frame) or _G[frame:GetName() .. 'ManaBar']
    local unitToken = "party" .. frameIndex
    
    -- Create hover frame for health bar
    if healthBar and not frame.MistUI_HealthHover then
        frame.MistUI_HealthHover = CreateFrame("Button", nil, frame.MistUI_TextFrame, "SecureUnitButtonTemplate")
        frame.MistUI_HealthHover:SetFrameLevel(frame.MistUI_TextFrame:GetFrameLevel() + 1)
        frame.MistUI_HealthHover:SetAllPoints(healthBar)
        frame.MistUI_HealthHover:RegisterForClicks("AnyUp")
        frame.MistUI_HealthHover:SetAttribute("unit", unitToken)
        frame.MistUI_HealthHover:SetAttribute("*type1", "target")
        frame.MistUI_HealthHover:SetAttribute("*type2", "togglemenu")
        frame.MistUI_HealthHover:EnableMouse(true)
        frame.MistUI_HealthHover:SetScript("OnEnter", function()
            hoverStates[frameIndex].health = true
            HideStockTexts(frame)
            UpdateHealthText(healthBar, true) -- Only show health text
            -- Only hide mana text if it's NOT set to always show
            local settings = GetSettings()
            if not (settings and settings.showManaTextAlways) then
                if frame.MistUI_ManaText then frame.MistUI_ManaText:Hide() end
                if frame.MistUI_ManaTextLeft then frame.MistUI_ManaTextLeft:Hide() end
                if frame.MistUI_ManaTextRight then frame.MistUI_ManaTextRight:Hide() end
            end
        end)
        frame.MistUI_HealthHover:SetScript("OnLeave", function()
            hoverStates[frameIndex].health = false
            HideStockTexts(frame)
            -- Return to normal visibility for both texts
            UpdateHealthText(healthBar, false)
            if manaBar then UpdateManaText(manaBar, false) end
        end)
    end
    
    -- Create hover frame for mana bar
    if manaBar and not frame.MistUI_ManaHover then
        frame.MistUI_ManaHover = CreateFrame("Button", nil, frame.MistUI_TextFrame, "SecureUnitButtonTemplate")
        frame.MistUI_ManaHover:SetFrameLevel(frame.MistUI_TextFrame:GetFrameLevel() + 1)
        frame.MistUI_ManaHover:SetAllPoints(manaBar)
        frame.MistUI_ManaHover:RegisterForClicks("AnyUp")
        frame.MistUI_ManaHover:SetAttribute("unit", unitToken)
        frame.MistUI_ManaHover:SetAttribute("*type1", "target")
        frame.MistUI_ManaHover:SetAttribute("*type2", "togglemenu")
        frame.MistUI_ManaHover:EnableMouse(true)
        frame.MistUI_ManaHover:SetScript("OnEnter", function()
            hoverStates[frameIndex].mana = true
            HideStockTexts(frame)
            UpdateManaText(manaBar, true) -- Only show mana text
            -- Only hide health text if it's NOT set to always show
            local settings = GetSettings()
            if not (settings and settings.showHealthTextAlways) then
                if frame.MistUI_HealthText then frame.MistUI_HealthText:Hide() end
                if frame.MistUI_HealthTextLeft then frame.MistUI_HealthTextLeft:Hide() end
                if frame.MistUI_HealthTextRight then frame.MistUI_HealthTextRight:Hide() end
            end
        end)
        frame.MistUI_ManaHover:SetScript("OnLeave", function()
            hoverStates[frameIndex].mana = false
            HideStockTexts(frame)
            -- Return to normal visibility for both texts
            if healthBar then UpdateHealthText(healthBar, false) end
            UpdateManaText(manaBar, false)
        end)
    end
    
    frame.MistUI_HoverFrames = true
end

-- Create our own text elements for party frames
CreateCustomTexts = function(frame)
    if not frame then return end

    if frame.MistUI_CustomTexts then
        EnsurePartyTextFont(frame.MistUI_HealthText)
        EnsurePartyTextFont(frame.MistUI_HealthTextLeft)
        EnsurePartyTextFont(frame.MistUI_HealthTextRight)
        EnsurePartyTextFont(frame.MistUI_ManaText)
        EnsurePartyTextFont(frame.MistUI_ManaTextLeft)
        EnsurePartyTextFont(frame.MistUI_ManaTextRight)
        return
    end

    if InCombatLockdown() then
        return
    end
    
    local frameIndex = frame:GetID()
    if not frameIndex or frameIndex < 1 or frameIndex > 4 then return end
    
    -- Initialize hover states (separate for health and mana)
    if not hoverStates[frameIndex] then
        hoverStates[frameIndex] = {
            portrait = false,
            health = false,
            mana = false
        }
    end
    
    -- Create text frame with proper layering (above border)
    if not frame.MistUI_TextFrame then
        frame.MistUI_TextFrame = CreateFrame("Frame", nil, frame)
        frame.MistUI_TextFrame:SetFrameLevel(frame:GetFrameLevel() + 4) -- Above border and bars
        frame.MistUI_TextFrame:SetAllPoints(frame)
    end

    -- Create custom health text elements (dual system for "both" format)
    -- Anchor to our overlay bar (not stock's), matching where the fill is drawn.
    local healthBar = EnsureDragonHealthBar(frame) or _G[frame:GetName() .. 'HealthBar']
    if healthBar then
        -- Center text for simple formats (numeric, percentage, formatted)
        if not frame.MistUI_HealthText then
            frame.MistUI_HealthText = frame.MistUI_TextFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            frame.MistUI_HealthText:SetPoint("CENTER", healthBar, "CENTER", 2, 0)
            frame.MistUI_HealthText:SetJustifyH("CENTER")
            frame.MistUI_HealthText:SetDrawLayer("OVERLAY", 1) -- Above everything
        end
        ApplyPartyTextVisualStyle(frame.MistUI_HealthText)
        EnsurePartyTextFont(frame.MistUI_HealthText)
        -- Left text for "both" format (percentage)
        if not frame.MistUI_HealthTextLeft then
            frame.MistUI_HealthTextLeft = frame.MistUI_TextFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            frame.MistUI_HealthTextLeft:SetPoint("RIGHT", healthBar, "RIGHT", -37, 0)
            frame.MistUI_HealthTextLeft:SetJustifyH("LEFT")
            frame.MistUI_HealthTextLeft:SetDrawLayer("OVERLAY", 1) -- Above everything
        end
        ApplyPartyTextVisualStyle(frame.MistUI_HealthTextLeft)
        EnsurePartyTextFont(frame.MistUI_HealthTextLeft)
        -- Right text for "both" format (numbers)
        if not frame.MistUI_HealthTextRight then
            frame.MistUI_HealthTextRight = frame.MistUI_TextFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            frame.MistUI_HealthTextRight:SetPoint("RIGHT", healthBar, "RIGHT", -1, 0)
            frame.MistUI_HealthTextRight:SetJustifyH("RIGHT")
            frame.MistUI_HealthTextRight:SetDrawLayer("OVERLAY", 1) -- Above everything
        end
        ApplyPartyTextVisualStyle(frame.MistUI_HealthTextRight)
        EnsurePartyTextFont(frame.MistUI_HealthTextRight)
    end

    -- Create custom mana text elements (dual system for "both" format)
    -- Anchor to our overlay bar (not stock's), matching where the fill is drawn.
    local manaBar = EnsureDragonManaBar(frame) or _G[frame:GetName() .. 'ManaBar']
    if manaBar then
        -- Center text for simple formats
        if not frame.MistUI_ManaText then
            frame.MistUI_ManaText = frame.MistUI_TextFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            frame.MistUI_ManaText:SetPoint("CENTER", manaBar, "CENTER", 3.5, 0)
            frame.MistUI_ManaText:SetJustifyH("CENTER")
            frame.MistUI_ManaText:SetDrawLayer("OVERLAY", 1) -- Above everything
        end
        ApplyPartyTextVisualStyle(frame.MistUI_ManaText)
        EnsurePartyTextFont(frame.MistUI_ManaText)
        -- Left text for "both" format (percentage)
        if not frame.MistUI_ManaTextLeft then
            frame.MistUI_ManaTextLeft = frame.MistUI_TextFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            frame.MistUI_ManaTextLeft:SetPoint("RIGHT", manaBar, "RIGHT", -37, 0)
            frame.MistUI_ManaTextLeft:SetJustifyH("LEFT")
            frame.MistUI_ManaTextLeft:SetDrawLayer("OVERLAY", 1) -- Above everything
        end
        ApplyPartyTextVisualStyle(frame.MistUI_ManaTextLeft)
        EnsurePartyTextFont(frame.MistUI_ManaTextLeft)
        -- Right text for "both" format (numbers)
        if not frame.MistUI_ManaTextRight then
            frame.MistUI_ManaTextRight = frame.MistUI_TextFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            frame.MistUI_ManaTextRight:SetPoint("RIGHT", manaBar, "RIGHT", -1, 0)
            frame.MistUI_ManaTextRight:SetJustifyH("RIGHT")
            frame.MistUI_ManaTextRight:SetDrawLayer("OVERLAY", 1) -- Above everything
        end
        ApplyPartyTextVisualStyle(frame.MistUI_ManaTextRight)
        EnsurePartyTextFont(frame.MistUI_ManaTextRight)
    end
    
    -- Create invisible dummy frames for independent hover (taint-free)
    CreateHoverFrames(frame, frameIndex)
    
    frame.MistUI_CustomTexts = true
end

-- (UpdateHealthText and UpdateManaText functions moved above before CreateHoverFrames)

-- Update party colors function
-- New function: Update mana bar texture
local function UpdateManaBarTexture(frame)
    if not frame then
        return
    end

    local unit = GetDisplayedUnit(frame)
    if not UnitExists(unit) then
        return
    end

    local manabar = EnsureDragonManaBar(frame)
    if manabar then
        local powerTexture = GetPowerBarTexture(unit)
        if manabar.__mistUI_powerTex ~= powerTexture then
            manabar:SetStatusBarTexture(powerTexture)
            manabar.__mistUI_powerTex = powerTexture
        end
        manabar:SetStatusBarColor(1, 1, 1, 1) -- Keep white
    end
end
-- ===============================================================
-- FRAME STYLING FUNCTIONS
-- ===============================================================

-- Main styling function for party frames
local function StylePartyFrames()
    -- Skip all restyling during editor mode (prevents texture/layer race conditions on fake frames)
    if addon.EditorMode and addon.EditorMode:IsActive() then return end

    local settings = GetSettings()
    if not settings then return end

    CreatePartyAnchorFrame()
    ApplyWidgetPosition()

    local step = GetPartyStep()
    local orientation = GetOrientation()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            if not InCombatLockdown() then
                frame:SetScale(settings.scale or 1)
                frame:SetFrameStrata('BACKGROUND')
                frame:SetFrameLevel(1)
                PlacePartyMemberFrame(frame, i, step, orientation)
            end

            -- Hide background (and permanently prevent the stock "Party/Arena Background" CVar from showing it)
            local bg = _G[frame:GetName() .. 'Background']
            if bg then
                bg:Hide()
                if not bg.MistUI_ShowHooked then
                    hooksecurefunc(bg, "Show", function(self) self:Hide() end)
                    bg.MistUI_ShowHooked = true
                end
            end

            -- Hide default texture
            local texture = _G[frame:GetName() .. 'Texture']
            if texture then
                texture:SetTexture()
                texture:Hide()
                if not texture.MistUI_ShowHooked then
                    hooksecurefunc(texture, "Show", function(self) self:Hide() end)
                    texture.MistUI_ShowHooked = true
                end
            end

            -- Hide vehicle texture (shown when party member is in a vehicle)
            local vehicleTex = _G[frame:GetName() .. 'VehicleTexture']
            if vehicleTex then
                vehicleTex:SetTexture()
                vehicleTex:Hide()
                if not vehicleTex.MistUI_ShowHooked then
                    hooksecurefunc(vehicleTex, "Show", function(self) self:Hide() end)
                    vehicleTex.MistUI_ShowHooked = true
                end
            end

            -- Lock portrait position so stock vehicle transitions can't move it
            local portrait = _G[frame:GetName() .. 'Portrait']
            if portrait and not portrait.MistUI_SetPointHooked then
                local isResetting = false
                hooksecurefunc(portrait, "SetPoint", function(self)
                    if isResetting or InCombatLockdown() then return end
                    isResetting = true
                    self:ClearAllPoints()
                    self:SetPoint("TOPLEFT", 7, -6)
                    isResetting = false
                end)
                portrait.MistUI_SetPointHooked = true
            end

            -- Health bar: native bar left untouched (reskinning it taints it); our own
            -- overlay bar is created and driven by SetupHealthBarClipping.
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            if healthbar and not InCombatLockdown() then
                SetupHealthBarClipping(frame)
                UpdatePartyHealthBarColor(i)
            end

            -- Mana bar: native bar left untouched (reskinning it taints it); our own
            -- overlay bar is created and driven by SetupManaBarClipping.
            local manabar = _G[frame:GetName() .. 'ManaBar']
            if manabar and not InCombatLockdown() then
                SetupManaBarClipping(frame)
                UpdateManaBarTexture(frame)
            end

            -- Name styling
           local name = _G[frame:GetName() .. 'Name']
            if name then
                name:SetFont(UF.DEFAULT_FONT, 10)
                name:SetShadowOffset(1, -1)
                name:SetTextColor(1, 0.82, 0, 1) -- Yellow like the rest

                if not InCombatLockdown() then
                    name:ClearAllPoints()
                    name:SetPoint('TOPLEFT', 46, -5)
                    name:SetSize(57, 12)
                end
            end

            ApplyPartyIcons(frame)

            -- Flash setup
            local flash = _G[frame:GetName() .. 'Flash']
            if flash then
                UF.ApplySkinPiece(flash, UF.GetFrameSkin().party.flash, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                flash:SetVertexColor(1, 0, 0, 1)
                flash:SetDrawLayer('OVERLAY', 1)
            end

            -- Create background and mark as styled
            if not frame.MistUIStyled then
                -- Background (behind everything); art and spot come from ApplyPartySkin
                frame.MistUI_Background = frame:CreateTexture(nil, 'BACKGROUND', nil, 0)

                -- Create border as a separate FRAME (not texture) to appear above bars
                if not frame.MistUI_BorderFrame then
                    frame.MistUI_BorderFrame = CreateFrame("Frame", nil, frame)
                    frame.MistUI_BorderFrame:SetFrameLevel(frame:GetFrameLevel() + 3) -- Above health/mana bars (level 2)
                    frame.MistUI_BorderFrame:SetAllPoints(frame)
                    
                    -- Now create border texture inside the border frame
                    local border = frame.MistUI_BorderFrame:CreateTexture(nil, 'ARTWORK', nil, 1)
                    border:SetVertexColor(1, 1, 1, 1)
                    frame.MistUI_BorderFrame.texture = border
                end
                ApplyPartySkin(frame)

                if not frame.MistUI_FlashContainer then
                    local flashContainer = CreateFrame("Frame", nil, frame)
                    flashContainer:SetFrameStrata("BACKGROUND")
                    flashContainer:SetFrameLevel(frame:GetFrameLevel() + 6) -- Above border, below icons
                    flashContainer:SetAllPoints(frame)
                    frame.MistUI_FlashContainer = flashContainer
                end

                -- Create icon container well above border frame
                if not frame.MistUI_IconContainer then
                    local iconContainer = CreateFrame("Frame", nil, frame)
                    iconContainer:SetFrameStrata("BACKGROUND")  -- Same strata as party frame
                    iconContainer:SetFrameLevel(frame:GetFrameLevel() + 10)  -- Well above border (+3)
                    iconContainer:SetAllPoints(frame)
                    frame.MistUI_IconContainer = iconContainer
                end

                if flash and frame.MistUI_FlashContainer and flash:GetParent() ~= frame.MistUI_FlashContainer then
                    flash:SetParent(frame.MistUI_FlashContainer)
                    UF.ApplySkinPiece(flash, UF.GetFrameSkin().party.flash, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                end

                -- Move icons to HIGH strata container and configure layers
                local name = _G[frame:GetName() .. 'Name']
                local healthText = _G[frame:GetName() .. 'HealthBarText']
                local manaText = _G[frame:GetName() .. 'ManaBarText']
                local leaderIcon = _G[frame:GetName() .. 'LeaderIcon']
                local masterLooterIcon = _G[frame:GetName() .. 'MasterIcon']
                local pvpIcon = _G[frame:GetName() .. 'PVPIcon']
                local stockRoleIcon = _G[frame:GetName() .. 'RoleIcon']
                local guideIcon = _G[frame:GetName() .. 'GuideIcon']
                
                -- Text elements stay in normal layer
                if name then
                    name:SetDrawLayer('OVERLAY', 1)
                end
                if healthText then
                    healthText:SetDrawLayer('OVERLAY', 1)
                end
                if manaText then
                    manaText:SetDrawLayer('OVERLAY', 1)
                end
                
                -- Move PvP and status icons to icon container (above border)
                if leaderIcon then
                    leaderIcon:SetParent(frame.MistUI_IconContainer)
                    leaderIcon:SetDrawLayer('OVERLAY', 1)
                end
                if masterLooterIcon then
                    masterLooterIcon:SetParent(frame.MistUI_IconContainer)
                    masterLooterIcon:SetDrawLayer('OVERLAY', 1)
                end
                if pvpIcon then
                    pvpIcon:SetParent(frame.MistUI_IconContainer)
                    pvpIcon:SetDrawLayer('OVERLAY', 1)
                end
                if stockRoleIcon then
                    stockRoleIcon:SetParent(frame.MistUI_IconContainer)
                    stockRoleIcon:SetDrawLayer('OVERLAY', 1)
                end
                if guideIcon then
                    guideIcon:SetParent(frame.MistUI_IconContainer)
                    guideIcon:SetDrawLayer('OVERLAY', 1)
                end

                frame.MistUIStyled = true
            end
            -- Hide stock texts and create our custom ones
            HideStockTexts(frame)
            CreateCustomTexts(frame)
            
            -- Update our custom texts initially
            if healthbar then
                UpdateHealthText(healthbar, false)
            end
            if manabar then
                UpdateManaText(manabar, false)
            end

            frame.MistUIStyled = true
        end
    end
end

-- ===============================================================
-- DISCONNECTED PLAYERS
-- ===============================================================
local function UpdateDisconnectedState(frame)
    if not frame then
        return
    end

    local unit = "party" .. frame:GetID()
    if not UnitExists(unit) then
        -- Member left or slot is empty: clear stale disconnected state.
        frame.MistUI_Disconnected = false

        local healthbar = EnsureDragonHealthBar(frame)
        local manabar = EnsureDragonManaBar(frame)
        local portrait = _G[frame:GetName() .. 'Portrait']
        local name = _G[frame:GetName() .. 'Name']

        if healthbar then
            healthbar:SetAlpha(1.0)
        end
        if manabar then
            manabar:SetAlpha(1.0)
        end
        if portrait then
            portrait:SetVertexColor(1, 1, 1, 1)
        end
        if name then
            name:SetTextColor(1, 0.82, 0, 1)
        end

        return
    end

    local isConnected = UnitIsConnected(unit)
    local healthbar = EnsureDragonHealthBar(frame)
    local manabar = EnsureDragonManaBar(frame)
    local portrait = _G[frame:GetName() .. 'Portrait']
    local name = _G[frame:GetName() .. 'Name']

    if not isConnected then
        -- Mark frame as disconnected (used by clipping hooks to force gray)
        frame.MistUI_Disconnected = true

        -- Disconnected member - gray bars at full, no text (stock native behavior)
        if healthbar then
            healthbar:SetAlpha(0.3)
            healthbar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        end

        -- Hide all custom health text elements (numbers should not show when offline)
        if frame.MistUI_HealthText then frame.MistUI_HealthText:Hide() end
        if frame.MistUI_HealthTextLeft then frame.MistUI_HealthTextLeft:Hide() end
        if frame.MistUI_HealthTextRight then frame.MistUI_HealthTextRight:Hide() end

        -- Hide all custom mana text elements
        if frame.MistUI_ManaText then frame.MistUI_ManaText:Hide() end
        if frame.MistUI_ManaTextLeft then frame.MistUI_ManaTextLeft:Hide() end
        if frame.MistUI_ManaTextRight then frame.MistUI_ManaTextRight:Hide() end

        if manabar then
            manabar:SetAlpha(0)  -- Completely hide mana bar when offline (works in combat)
        end

        if portrait then
            portrait:SetVertexColor(0.5, 0.5, 0.5, 1)
        end

        if name then
            name:SetTextColor(0.6, 0.6, 0.6, 1)
        end

    else
        -- Connected member - undo exactly what was done when disconnecting
        frame.MistUI_Disconnected = false

        -- Restore transparencies (without taint)
        if healthbar then
            healthbar:SetAlpha(1.0) -- Normal opacity
            -- Restore correct color (class color or white)
            local frameIndex = frame:GetID()
            UpdatePartyHealthBarColor(frameIndex) -- Only updates color, does not recreate frame
        end

        if manabar then
            manabar:SetAlpha(1.0) -- Restore visibility
            manabar:SetStatusBarColor(1, 1, 1, 1) -- White as it should be
            local manaTexture = manabar:GetStatusBarTexture()
            if manaTexture then
                manaTexture:SetVertexColor(1, 1, 1, 1)
            end
        end

        if portrait then
            portrait:SetVertexColor(1, 1, 1, 1) -- Normal color
        end

        if name then
            name:SetTextColor(1, 0.82, 0, 1) -- Normal yellow
        end
    end
end

local function ShouldShowMistUIPartySlot(index)
    if not ShouldPartyFramesBeVisible() then
        return false
    end
    return UnitExists("party" .. index)
end

-- Anything but a class icon needs the whole texture back: the classic icon leaves a crop on it.
local function UpdatePartyClassPortrait(frame)
    local unit = "party" .. frame:GetID()
    local portrait = _G[frame:GetName() .. 'Portrait']
    if not portrait or not UnitExists(unit) then return end
    local settings = GetSettings()
    -- In a vehicle frame.unit is the vehicle's token and the slot keeps the vehicle's portrait.
    if (settings.classPortrait or settings.racePortrait) and frame.unit == unit
        and UF.ApplyPortraitStyle(unit, portrait, settings) then
        return
    end
    SetPortraitTexture(portrait, frame.unit or unit)
    portrait:SetTexCoord(0, 1, 0, 1)
end

local function PaintPreviewMember(frame, member)
    UpdateDisconnectedState(frame)

    local name = _G[frame:GetName() .. 'Name']
    if name then
        name:SetText(member.name)
    end

    local portrait = _G[frame:GetName() .. 'Portrait']
    if portrait then
        local settings = GetSettings()
        if settings.classPortrait then
            UF.ApplyClassPortraitIcon(portrait, member.class, settings.alternativeClassIcons)
        elseif not UF.SetRacePortraitFile(portrait, member.portrait) then
            SetPortraitTexture(portrait, "player")
            portrait:SetTexCoord(0, 1, 0, 1)
        end
        SetDesaturation(portrait, nil)
    end

    local disconnect = _G[frame:GetName() .. 'Disconnect']
    if disconnect then
        disconnect:Hide()
    end

    -- The stock UI only updates this voice button on slots with a unit, and the template shows it.
    local speaker = _G[frame:GetName() .. 'Speaker']
    if speaker then
        speaker:Hide()
    end

    local healthBar = EnsureDragonHealthBar(frame)
    local healthTexture = healthBar and healthBar:GetStatusBarTexture()
    if healthTexture then
        -- Not UpdatePartyHealthBarColor: it returns early without a unit.
        local color = GetSettings().classcolor and RAID_CLASS_COLORS[member.class]
        local texturePath = color and TEXTURES.healthBarStatus or TEXTURES.healthBar
        if healthTexture:GetTexture() ~= texturePath then
            healthTexture:SetTexture(texturePath)
        end
        if color then
            healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)
        else
            healthBar:SetStatusBarColor(1, 1, 1, 1)
        end

        healthBar:SetMinMaxValues(0, 1)
        healthBar:SetValue(member.health)
        healthTexture:SetTexCoord(0, member.health, 0, 1)
    end

    local manaBar = EnsureDragonManaBar(frame)
    if manaBar then
        local powerTexture = TEXTURES[member.powerBar]
        if manaBar.__mistUI_powerTex ~= powerTexture then
            manaBar:SetStatusBarTexture(powerTexture)
            manaBar.__mistUI_powerTex = powerTexture
        end
        manaBar:SetStatusBarColor(1, 1, 1, 1)
        manaBar:SetMinMaxValues(0, 1)
        manaBar:SetValue(member.mana)

        local manaTexture = manaBar:GetStatusBarTexture()
        if manaTexture then
            manaTexture:SetTexCoord(0, member.mana, 0, 1)
        end
    end

    UpdateHealthText(healthBar, false)
    UpdateManaText(manaBar, false)
end

function PartyFrames:UpdateEditorPreview()
    if not (addon.EditorMode and addon.EditorMode:IsActive()) or InCombatLockdown() then
        return
    end

    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            if UnitExists("party" .. i) then
                frame:Show()
            elseif GetSettings().always_hidden then
                frame:Hide()
            else
                frame:Show()
                -- Leaving a group while hidden strands alpha 0: the engine stops managing the slot.
                if addon.VisibilityFade and not ShouldPartyFramesBeVisible() then
                    addon.VisibilityFade.Reset("party" .. i)
                end
                PaintPreviewMember(frame, GetPreviewMember(i))
            end
        end
    end
end

local function RefreshSinglePartyFrameVisibility(index)
    local frame = _G['PartyMemberFrame' .. index]
    if not frame then
        return
    end

    -- Never hide party frames while editor mode is active (test frames are shown intentionally)
    if addon.EditorMode and addon.EditorMode:IsActive() then
        return
    end

    -- Keep disconnect visuals in sync before deciding visibility.
    UpdateDisconnectedState(frame)

    if ShouldShowMistUIPartySlot(index) then
        frame:Show()
    else
        frame:Hide()
    end

    if addon.VisibilityFade then
        addon.VisibilityFade.Update("party" .. index)
    end
end

-- The party frames are protected: showing or hiding them waits for the end of combat.
local function RefreshAllPartyFrameVisibility()
    if InCombatLockdown() then
        if addon.CombatQueue then
            addon.CombatQueue:Add("party_refresh", RefreshAllPartyFrameVisibility)
        end
        return
    end

    for i = 1, MAX_PARTY_MEMBERS do
        RefreshSinglePartyFrameVisibility(i)
    end
end

local RequestPartyVisibilityRefresh = RefreshAllPartyFrameVisibility




-- ===============================================================
-- HOOK SETUP FUNCTION
-- ===============================================================

-- Setup all necessary hooks for party frames
local function SetupPartyHooks()
    -- PetFrame's hover shows the same PartyMemberBuffTooltip, so only party callers are filtered.
    hooksecurefunc("PartyMemberBuffTooltip_Update", function(frame)
        if not (frame and frame:GetName() and frame:GetName():match("^PartyMemberFrame%d+$")) then return end
        local mode = UF.GetConfig("party").buff_tooltip
        if mode == "never" or (mode == "combat" and UnitAffectingCombat("player")) then
            PartyMemberBuffTooltip:Hide()
        end
    end)

    hooksecurefunc("PartyMemberFrame_UpdateMember", function(frame)
        -- Skip restyling during editor mode (fake frames should stay as-is)
        if addon.EditorMode and addon.EditorMode:IsActive() then return end
        if frame and frame:GetName():match("^PartyMemberFrame%d+$") then
            local frameIndex = frame:GetID()
            local unit = frameIndex and ("party" .. frameIndex)

            if unit and UnitExists(unit) and not frame:IsShown() and not InCombatLockdown()
                and ShouldPartyFramesBeVisible() then
                frame:Show()
            end

            if PartyFrames.anchor and not InCombatLockdown() then
                if frameIndex and frameIndex >= 1 and frameIndex <= 4 then
                    PlacePartyMemberFrame(frame, frameIndex, GetPartyStep(), GetOrientation())
                end
            end

            -- Re-hide textures (always needed)
            local texture = _G[frame:GetName() .. 'Texture']
            if texture then
                texture:SetTexture()
                texture:Hide()
            end

            -- Re-hide vehicle texture
            local vehicleTex = _G[frame:GetName() .. 'VehicleTexture']
            if vehicleTex then
                vehicleTex:SetTexture()
                vehicleTex:Hide()
            end

            local bg = _G[frame:GetName() .. 'Background']
            if bg then
                bg:Hide()
            end

            -- Maintain only clipping configuration (ACE3 handles colors)
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            local manabar = _G[frame:GetName() .. 'ManaBar']

            if healthbar then
                SetupHealthBarClipping(frame)
            end

            if manabar then
                SetupManaBarClipping(frame)
            end

            -- Update power bar texture
            UpdateManaBarTexture(frame)
            -- Disconnected state
            UpdateDisconnectedState(frame)
            
            -- Always hide stock texts and ensure our custom texts exist
            HideStockTexts(frame)
            CreateCustomTexts(frame)
            
            -- Force reparent icons to icon container (for dynamic PvP icons)
            if frame.MistUI_IconContainer then
                local pvpIcon = _G[frame:GetName() .. 'PVPIcon']
                local leaderIcon = _G[frame:GetName() .. 'LeaderIcon']
                local guideIcon = _G[frame:GetName() .. 'GuideIcon']
                local roleIcon = _G[frame:GetName() .. 'RoleIcon']
                
                if pvpIcon then
                    pvpIcon:SetParent(frame.MistUI_IconContainer)
                    pvpIcon:SetDrawLayer('OVERLAY', 1)
                end
                if guideIcon then
                    guideIcon:SetParent(frame.MistUI_IconContainer)
                    guideIcon:SetDrawLayer('OVERLAY', 1)
                end
                if roleIcon then
                    roleIcon:SetParent(frame.MistUI_IconContainer)
                    roleIcon:SetDrawLayer('OVERLAY', 1)
                end
            end
            
            -- Update custom health/mana text
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            local manabar = _G[frame:GetName() .. 'ManaBar']
            if healthbar then UpdateHealthText(healthbar, false) end
            if manabar then UpdateManaText(manabar, false) end
        end
    end)

    hooksecurefunc("PartyMemberFrame_OnEvent", function(frame, event, eventUnit)
        -- The stock frame sets the role icon only on GROUP_ROSTER_UPDATE, which a /reload may not fire.
        if event == "PLAYER_ENTERING_WORLD" then
            if UnitExists("party" .. frame:GetID()) then
                PartyMemberFrame_UpdateAssignedRoles(frame)
            end
            return
        end
        if event ~= "UNIT_HEALTH" and event ~= "UNIT_MAXHEALTH" then return end
        if not frame or (eventUnit ~= frame.unit and eventUnit ~= PARTY_UNIT_TOKENS[frame:GetID()]) then return end
        if frame:GetName() and frame:GetName():match("^PartyMemberFrame%d+$") then
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            if healthbar then
                UpdateHealthText(healthbar, false)
            end
        end
    end)

    -- These bars hear every unit's health/power events; the stock UI only acts on the bar's own unit.
    hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
        if not statusbar or unit ~= statusbar.unit then return end
        if statusbar:GetName() and statusbar:GetName():match("^PartyMemberFrame%dHealthBar$") then
            -- Drive our overlay from the native bar (read-only); never clip the native texture.
            ApplyHealthBarClipping(statusbar, statusbar:GetValue())
            UpdateHealthText(statusbar, false)
        end
    end)

    -- Hook for mana bar (without touching health)
    hooksecurefunc("UnitFrameManaBar_Update", function(statusbar, unit)
        if not statusbar or unit ~= statusbar.unit then return end
        local id = statusbar:GetName()
            and statusbar:GetName():match("^PartyMemberFrame(%d)ManaBar$")
        if id then
            -- Only path that sees power changes: PartyMemberFrame itself registers no power event.
            UpdateManaBarTexture(_G['PartyMemberFrame' .. id])
            -- Drive our overlay from the native bar (read-only); never touch the native texture.
            ApplyManaBarClipping(statusbar, statusbar:GetValue())
            UpdateManaText(statusbar, false)
        end
    end)
    
    -- Handle hover text display with persistent state (portrait hover - shows both texts)
    hooksecurefunc("UnitFrame_OnEnter", function(self)
        if self and self:GetName() and self:GetName():match("^PartyMemberFrame%d+$") then
            local frameIndex = tonumber(self:GetID())
            if frameIndex and hoverStates[frameIndex] then
                hoverStates[frameIndex].portrait = true  -- Mark portrait as hovering
            end
            
            -- Immediately hide stock texts after hover
            HideStockTexts(self)
            
            -- Show both custom texts during portrait hover (even if always show is off)
            local healthbar = _G[self:GetName() .. 'HealthBar']
            local manabar = _G[self:GetName() .. 'ManaBar']
            if healthbar then UpdateHealthText(healthbar, true) end -- forceShow = true
            if manabar then UpdateManaText(manabar, true) end -- forceShow = true
        end
    end)
    
    hooksecurefunc("UnitFrame_OnLeave", function(self)
        if self and self:GetName() and self:GetName():match("^PartyMemberFrame%d+$") then
            local frameIndex = tonumber(self:GetID())
            if frameIndex and hoverStates[frameIndex] then
                hoverStates[frameIndex].portrait = false  -- Clear portrait hover state
            end
            
            -- Ensure stock texts stay hidden after hover ends
            HideStockTexts(self)
            
            -- Return to normal text visibility (respect always show setting)
            local healthbar = _G[self:GetName() .. 'HealthBar']
            local manabar = _G[self:GetName() .. 'ManaBar']
            if healthbar then UpdateHealthText(healthbar, false) end -- forceShow = false
            if manabar then UpdateManaText(manabar, false) end -- forceShow = false
        end
    end)
    
    hooksecurefunc("PartyMemberFrame_UpdateAssignedRoles", function(frame)
        if frame and frame:GetName() and frame:GetName():match("^PartyMemberFrame%d+$") then
            ApplyPartyRole(frame)
        end
    end)

    hooksecurefunc("PartyMemberFrame_UpdatePvPStatus", function(frame)
        if frame then
            ApplyPartyPvP(frame)
        end
    end)

    hooksecurefunc("UnitFramePortrait_Update", function(frame)
        if frame and frame:GetName() and frame:GetName():match("^PartyMemberFrame%d+$") then
            UpdatePartyClassPortrait(frame)
        end
    end)

    -- ===============================================================
    -- DISCONNECT VISUAL FIX (mod-playerbots compatibility)
    -- ===============================================================
    -- Hook PartyMemberFrame_UpdateOnlineStatus directly.
    -- This runs AFTER stock has already called UnitFrameHealthBar_Update
    -- (which triggers our SetValue hook that may override gray with class/white
    -- color because MistUI_Disconnected flag isn't set yet at that point).
    -- By hooking this function, we re-apply disconnect visuals as the LAST step.
    hooksecurefunc("PartyMemberFrame_UpdateOnlineStatus", function(frame)
        if not frame or not frame:GetName() then return end
        if not frame:GetName():match("^PartyMemberFrame%d+$") then return end
        
        local frameIndex = frame:GetID()
        local unit = "party" .. frameIndex
        if not UnitExists(unit) then return end
        
        -- Re-apply disconnect state - this runs after stock AND after our
        -- SetValue/UnitFrameHealthBar_Update hooks have already executed,
        -- ensuring the gray visuals stick.
        UpdateDisconnectedState(frame)

        -- Re-run clip logic directly, not via :SetValue() - that cascade taints Show() calls mid-combat.
        local healthbar = _G[frame:GetName() .. 'HealthBar']
        local manabar = _G[frame:GetName() .. 'ManaBar']
        if healthbar then
            ApplyHealthBarClipping(healthbar, healthbar:GetValue())
        end
        if manabar then
            ApplyManaBarClipping(manabar, manabar:GetValue())
        end
    end)
end

-- ===============================================================
-- MODULE INTERFACE FUNCTIONS
-- ===============================================================

function PartyFrames:UpdateSettings()
    if InCombatLockdown() then
        if addon.CombatQueue then
            addon.CombatQueue:Add("party_update_settings", function()
                PartyFrames:UpdateSettings()
            end)
        end
        return
    end

    -- Check initial configuration
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets or not addon.db.profile.widgets.party then
        self:LoadDefaultSettings()
    end

    -- Apply widget position first
    ApplyWidgetPosition()
    
    -- Only apply base styles - ACE3 handles class color
    StylePartyFrames()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame and frame.MistUIStyled then
            ApplyPartySkin(frame)
        end
    end

    -- Reposition buffs
    RepositionStockBuffs()
    
    -- Update anchor size for new orientation
    UpdatePartyAnchorSize()
    
    -- Refresh all texts and power bar textures with new settings
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            HideStockTexts(frame)
            CreateCustomTexts(frame)
            
            -- Refresh power bar texture (energy, rage, etc.)
            UpdateManaBarTexture(frame)
            
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            local manabar = _G[frame:GetName() .. 'ManaBar']
            
            if healthbar then UpdateHealthText(healthbar, false) end
            if manabar then UpdateManaText(manabar, false) end
            
            -- Re-apply disconnected state AFTER styling (gray name, hidden texts, etc.)
            -- StylePartyFrames resets name color to yellow, so this must come last
            UpdateDisconnectedState(frame)
            UpdatePartyClassPortrait(frame)

            if addon.VisibilityFade then
                local hoverFrames = { frame }
                if frame.MistUI_HealthHover then table.insert(hoverFrames, frame.MistUI_HealthHover) end
                if frame.MistUI_ManaHover then table.insert(hoverFrames, frame.MistUI_ManaHover) end
                addon.VisibilityFade.Register("party" .. i, frame, {
                    dbTable = function() return addon.UF.GetConfig("party") end,
                    hoverFrames = hoverFrames,
                    clickThrough = true,
                    shouldManage = ShouldPartyFramesBeVisible,
                })
                addon.VisibilityFade.Update("party" .. i)
            end
        end
    end

    -- Single source of truth for Show/Hide decisions.
    RefreshAllPartyFrameVisibility()
    self:UpdateEditorPreview()
end

-- ===============================================================
-- EXPORTS FOR OPTIONS.LUA
-- ===============================================================

function addon:RefreshPartyFrames()
    if PartyFrames and PartyFrames.UpdateSettings then
        PartyFrames:UpdateSettings()
    end
end

-- StylePartyFrames bails out while the editor is open, so scale and layout are re-applied here.
function PartyFrames:ApplyLiveLayout()
    if InCombatLockdown() then return end

    local settings = GetSettings()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            frame:SetScale((settings and settings.scale) or 1)
        end
    end

    self:UpdateWidgets()
end

-- ===============================================================
-- CENTRALIZED SYSTEM REGISTRATION AND INITIALIZATION
-- ===============================================================

local function InitializePartyFramesForEditor()
    if PartyFrames.initialized then
        return
    end

    -- Create anchor frame
    CreatePartyAnchorFrame()

    -- Always ensure configuration exists
    PartyFrames:LoadDefaultSettings()

    -- Apply initial position
    ApplyWidgetPosition()

    -- Register with centralized system
    if addon and addon.RegisterEditableFrame then
        addon:RegisterEditableFrame({
            name = "party",
            frame = PartyFrames.anchor,
            configPath = {"widgets", "party"}, -- Add configPath required by core.lua
            showTest = ShowPartyFramesTest,
            -- Styling and visibility skip while the editor is up, so roster changes made meanwhile land here.
            hideTest = function()
                HidePartyFramesTest()
                StylePartyFrames()
                RequestPartyVisibilityRefresh()
            end,
            hasTarget = ShouldPartyFramesBeVisible -- Use hasTarget instead of shouldShow
        })
    end

    PartyFrames.initialized = true
end

-- ===============================================================
-- INITIALIZATION
-- ===============================================================

-- Initialize everything in correct order
InitializePartyFramesForEditor() -- First: register with centralized system
StylePartyFrames() -- Second: visual properties and positioning
SetupPartyHooks() -- Third: safe hooks only

-- Listener for when the addon is fully loaded
local readyFrame = CreateFrame("Frame")
readyFrame:RegisterEvent("ADDON_LOADED")
readyFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "MistUI" then
        -- Apply position after the addon is fully loaded
        if PartyFrames and PartyFrames.UpdateSettings then
            PartyFrames:UpdateSettings()
        end
        RefreshAllPartyFrameVisibility()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local connectionFrame = CreateFrame("Frame")
connectionFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
connectionFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
connectionFrame:SetScript("OnEvent", function(self, event)
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        if frame then
            -- Set the flag FIRST so hooks respect it
            UpdateDisconnectedState(frame)
            -- Re-run clip logic directly, not via :SetValue() - that cascade taints Show() calls mid-combat.
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            local manabar = _G[frame:GetName() .. 'ManaBar']
            if healthbar then
                ApplyHealthBarClipping(healthbar, healthbar:GetValue())
            end
            if manabar then
                ApplyManaBarClipping(manabar, manabar:GetValue())
            end
        end
    end
    -- The loop above copies the native bars onto every overlay, invented members included.
    PartyFrames:UpdateEditorPreview()
end)

-- ===============================================================
-- DEATH/GHOST RECOVERY SYSTEM
-- ===============================================================
-- After death + spirit release, party frame textures can get stuck invisible
-- because SetValue hooks clip to zero-width and UnitExists may briefly return false.
-- These events force a full texture refresh to recover from that state.

-- The stock frames settle a moment after a loading screen; restyling sooner gets overwritten.
local WORLD_ENTRY_DELAY = 0.5

local function RefreshAfterWorldEntry()
    -- Editor mode shows test frames on purpose, and combat forbids the protected visibility change.
    if (addon.EditorMode and addon.EditorMode:IsActive()) or InCombatLockdown() then
        return
    end
    StylePartyFrames()
    RefreshAllPartyFrameVisibility()
end

-- Party frame index per unit token. "partypetN" too: it is the unit a frame shows while its
-- member rides a vehicle. A lookup, because this listener hears every unit's health in a raid.
local PARTY_FRAME_INDEX = {}
for index = 1, MAX_PARTY_MEMBERS do
    PARTY_FRAME_INDEX["party" .. index] = index
    PARTY_FRAME_INDEX["partypet" .. index] = index
end

local recoveryFrame = CreateFrame("Frame")
recoveryFrame:RegisterEvent("GROUP_ROSTER_UPDATE")     -- Group composition changes (join/leave/role swap/raid)
recoveryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")   -- Recovery after reload/zone transitions
recoveryFrame:RegisterEvent("PLAYER_ALIVE")             -- Player resurrects (accept rez or spirit healer)
recoveryFrame:RegisterEvent("PLAYER_UNGHOST")           -- Player returns from ghost form
recoveryFrame:RegisterEvent("UNIT_HEALTH")              -- Any unit health change (catches party member rez too)
recoveryFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        addon:After(WORLD_ENTRY_DELAY, RefreshAfterWorldEntry)
        return
    end

    -- Roster transitions can change protected visibility, so defer reconciliation in combat.
    if event == "GROUP_ROSTER_UPDATE" then
        -- Skip refresh while editor mode is active (test frames are intentionally shown)
        if addon.EditorMode and addon.EditorMode:IsActive() then
            -- The stock UI blanks empty slots on roster changes, so this waits for its handler.
            addon:After(0, function() PartyFrames:UpdateEditorPreview() end)
            return
        end
        RequestPartyVisibilityRefresh()
    end

    -- For UNIT_HEALTH, only process party units
    if event == "UNIT_HEALTH" then
        local frameIndex = unit and PARTY_FRAME_INDEX[unit]
        if frameIndex then
            local frame = _G['PartyMemberFrame' .. frameIndex]
            if frame and UnitExists(unit) then
                -- Skip disconnected frames - their visual state is managed by UpdateDisconnectedState
                if frame.MistUI_Disconnected then return end
                local healthbar = _G[frame:GetName() .. 'HealthBar']
                local manabar = _G[frame:GetName() .. 'ManaBar']
                if healthbar then
                    ApplyHealthBarClipping(healthbar, healthbar:GetValue())
                    UpdateHealthText(healthbar, false)
                end
                if manabar then
                    ApplyManaBarClipping(manabar, manabar:GetValue())
                    UpdateManaText(manabar, false)
                end
            end
        end
        return
    end
    
    -- For party-wide events, refresh ALL party frames
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G['PartyMemberFrame' .. i]
        local unit = "party" .. i
        if frame and UnitExists(unit) then
            -- Skip disconnected frames - their visual state is managed by UpdateDisconnectedState
            if not frame.MistUI_Disconnected then
            local healthbar = _G[frame:GetName() .. 'HealthBar']
            local manabar = _G[frame:GetName() .. 'ManaBar']
            if healthbar then
                ApplyHealthBarClipping(healthbar, healthbar:GetValue())
                UpdateHealthText(healthbar, false)
            end
            if manabar then
                ApplyManaBarClipping(manabar, manabar:GetValue())
                UpdateManaText(manabar, false)
            end
            end -- if not MistUI_Disconnected
        end
    end
end)


-- ===============================================================
-- COMPACT RAID FRAMES HANDSHAKE
-- ===============================================================

-- The "raid-style party frames" option calls this stock function when it changes.
local allyFramesFrame = CreateFrame("Frame")
allyFramesFrame:RegisterEvent("PLAYER_LOGIN")
allyFramesFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if type(_G.RaidOptionsFrame_UpdatePartyFrames) == "function" then
        hooksecurefunc("RaidOptionsFrame_UpdatePartyFrames", RequestPartyVisibilityRefresh)
    end
end)

-- ===============================================================
-- VEHICLE & RELOAD RECOVERY SYSTEM
-- ===============================================================
-- PartyMemberFrame_UpdateArt hook catches all vehicle art transitions.
-- PLAYER_ENTERING_WORLD with delay handles reload while in vehicle.

-- Reset portrait to MistUI's expected position after stock vehicle transitions
local function ResetPartyPortrait(frame)
    if InCombatLockdown() then return end
    local portrait = _G[frame:GetName() .. "Portrait"]
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetPoint("TOPLEFT", 7, -6)
    end
end

-- Hook PartyMemberFrame_UpdateArt - catches both vehicle enter and exit
if type(PartyMemberFrame_UpdateArt) == "function" then
    hooksecurefunc("PartyMemberFrame_UpdateArt", function(frame)
        if not frame or not frame:GetName() then return end
        if not frame:GetName():match("^PartyMemberFrame%d+$") then return end

        local texture = _G[frame:GetName() .. "Texture"]
        if texture then
            texture:SetTexture()
            texture:Hide()
        end

        local bg = _G[frame:GetName() .. "Background"]
        if bg then
            bg:Hide()
        end

        local frameIndex = frame:GetID()
        local healthbar = _G[frame:GetName() .. "HealthBar"]
        if healthbar then
            -- Refresh our overlay; never re-skin the native bar (that taints it).
            ApplyHealthBarClipping(healthbar, healthbar:GetValue())
        end

        if frame.MistUI_BorderFrame and frame.MistUI_BorderFrame.texture then
            frame.MistUI_BorderFrame.texture:Show()
        end

        UpdateManaBarTexture(frame)
        HideStockTexts(frame)
        CreateCustomTexts(frame)
        UpdateDisconnectedState(frame)
        ApplyPartyIcons(frame)
        ResetPartyPortrait(frame)
    end)
end

-- Hook PartyMemberFrame_ToVehicleArt - hides the vehicle texture stock shows
if type(PartyMemberFrame_ToVehicleArt) == "function" then
    hooksecurefunc("PartyMemberFrame_ToVehicleArt", function(frame)
        if not frame or not frame:GetName() then return end
        if not frame:GetName():match("^PartyMemberFrame%d+$") then return end

        -- Hide stock vehicle texture
        local vehicleTex = _G[frame:GetName() .. "VehicleTexture"]
        if vehicleTex then
            vehicleTex:SetTexture()
            vehicleTex:Hide()
        end

        -- Also re-hide the normal texture (the stock UI may have restored it)
        local texture = _G[frame:GetName() .. "Texture"]
        if texture then
            texture:SetTexture()
            texture:Hide()
        end

        local bg = _G[frame:GetName() .. "Background"]
        if bg then
            bg:Hide()
        end

        -- Re-apply MistUI styling
        local frameIndex = frame:GetID()
        local healthbar = _G[frame:GetName() .. "HealthBar"]
        if healthbar then
            -- Refresh our overlay; never re-skin the native bar (that taints it).
            ApplyHealthBarClipping(healthbar, healthbar:GetValue())
        end

        if frame.MistUI_BorderFrame and frame.MistUI_BorderFrame.texture then
            frame.MistUI_BorderFrame.texture:Show()
        end

        UpdateManaBarTexture(frame)
        HideStockTexts(frame)
        CreateCustomTexts(frame)
        UpdateDisconnectedState(frame)
        ApplyPartyIcons(frame)
        ResetPartyPortrait(frame)
    end)
end

-- Hook PartyMemberFrame_ToPlayerArt - re-applies MistUI styling when exiting vehicle
if type(PartyMemberFrame_ToPlayerArt) == "function" then
    hooksecurefunc("PartyMemberFrame_ToPlayerArt", function(frame)
        if not frame or not frame:GetName() then return end
        if not frame:GetName():match("^PartyMemberFrame%d+$") then return end

        -- Hide vehicle texture (may linger)
        local vehicleTex = _G[frame:GetName() .. "VehicleTexture"]
        if vehicleTex then
            vehicleTex:SetTexture()
            vehicleTex:Hide()
        end

        -- Hide normal stock texture
        local texture = _G[frame:GetName() .. "Texture"]
        if texture then
            texture:SetTexture()
            texture:Hide()
        end

        local bg = _G[frame:GetName() .. "Background"]
        if bg then
            bg:Hide()
        end

        -- Re-apply MistUI styling
        local frameIndex = frame:GetID()
        local healthbar = _G[frame:GetName() .. "HealthBar"]
        if healthbar then
            -- Refresh our overlay; never re-skin the native bar (that taints it).
            ApplyHealthBarClipping(healthbar, healthbar:GetValue())
        end

        if frame.MistUI_BorderFrame and frame.MistUI_BorderFrame.texture then
            frame.MistUI_BorderFrame.texture:Show()
        end

        UpdateManaBarTexture(frame)
        HideStockTexts(frame)
        CreateCustomTexts(frame)
        UpdateDisconnectedState(frame)
        ApplyPartyIcons(frame)
        ResetPartyPortrait(frame)
    end)
end

-- Helper: full party frame refresh (shared by vehicle and reload recovery)
local function RefreshAllPartyFrames()
    StylePartyFrames()
    RepositionStockBuffs()
    for i = 1, MAX_PARTY_MEMBERS do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and UnitExists("party" .. i) then
            HideStockTexts(frame)
            CreateCustomTexts(frame)
            UpdateManaBarTexture(frame)
            UpdateDisconnectedState(frame)
            ResetPartyPortrait(frame)
            local healthbar = _G[frame:GetName() .. "HealthBar"]
            local manabar = _G[frame:GetName() .. "ManaBar"]
            if healthbar then UpdateHealthText(healthbar, false) end
            if manabar then UpdateManaText(manabar, false) end
        end
    end
end

-- Reload recovery: stock re-initializes vehicle state after /reload
local vehicleRecoveryFrame = CreateFrame("Frame")
vehicleRecoveryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
vehicleRecoveryFrame:SetScript("OnEvent", function(self, event)
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(function()
            -- Skip refresh during editor mode (prevents strata/visibility reset)
            if addon.EditorMode and addon.EditorMode:IsActive() then
                return
            end
            if InCombatLockdown() then
                if addon.CombatQueue then
                    addon.CombatQueue:Add("party_vehicle_recovery", RefreshAllPartyFrames)
                end
                return
            end
            RefreshAllPartyFrames()
        end, 0.8)
    end
end)

-- ===============================================================
-- MODULE LOADED CONFIRMATION
-- ===============================================================

