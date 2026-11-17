-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ===============================================================
-- MISTUI PET FRAME MODULE
-- ===============================================================
local addon = select(2, ...)
local L = addon.L
local UF = addon.UF
local PetFrameModule = {}
addon.PetFrameModule = PetFrameModule

-- ===============================================================
-- LOCALIZED API REFERENCES
-- ===============================================================
local _G = _G
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitExists = UnitExists
local UnitPowerType = UnitPowerType
local hooksecurefunc = hooksecurefunc

-- ===============================================================
-- MODULE CONSTANTS (from shared core)
-- ===============================================================
local PET_TEX = UF.TEXTURES.pet
local SMALL_FRAME_PATH = PET_TEX.SMALL_FRAME_PATH
local UNITFRAME_PATH = PET_TEX.UNITFRAME_PATH
local TOT_BASE = PET_TEX.TOT_BASE
local POWER_TEXTURES = PET_TEX.POWER_TEXTURES
local DEFAULT_ATTACH_X = 18
local DEFAULT_ATTACH_Y = -80

-- ===============================================================
-- COMBAT PULSE ANIMATIONS
-- ===============================================================

-- Combat pulse color configuration
local COMBAT_PULSE_SETTINGS = {
    speed = 9,              -- Heartbeat speed
    minIntensity = 0.3,     -- Minimum red intensity (0.4 = dark red)
    maxIntensity = 0.7,     -- Maximum red intensity (1.0 = bright red)
    enabled = true          -- Enable/disable animation
}

local combatPulseTimer = 0
local petFrameUpdateThrottle = 0

-- Forward declaration (defined after vehicle system section)
local UpdatePetTextSystemUnit


-- ===============================================================
-- COMBAT PULSE ANIMATION
-- ===============================================================
local function AnimatePetCombatPulse(elapsed)
    if not COMBAT_PULSE_SETTINGS.enabled then
        return
    end
    
    local texture = _G.PetAttackModeTexture
    if not texture or not texture:IsVisible() then
        return
    end
    
    -- Increment timer
    combatPulseTimer = combatPulseTimer + (elapsed * COMBAT_PULSE_SETTINGS.speed)
    
    -- Calculate red intensity using sine function
    local intensity = COMBAT_PULSE_SETTINGS.minIntensity + 
                     (COMBAT_PULSE_SETTINGS.maxIntensity - COMBAT_PULSE_SETTINGS.minIntensity) * 
                     (math.sin(combatPulseTimer) * 0.5 + 0.5)
    
    -- Pulse vertex color between min/max red intensity
    texture:SetVertexColor(intensity, 0.0, 0.0, 1.0)
end

-- ===============================================================
-- MODULE STATE
-- ===============================================================
local moduleState = {
    frame = {},
    hooks = {},
    textSystem = nil
}

-- ===============================================================
-- UTILITY FUNCTIONS
-- ===============================================================
-- Persistently hides the stock PetFrame texts (health/power)
local function HideStockPetTexts()
    local petTexts = {
        _G.PetFrameHealthBar and _G.PetFrameHealthBar.TextString,
        _G.PetFrameManaBar and _G.PetFrameManaBar.TextString,
        _G.PetFrameHealthBarText,
        _G.PetFrameManaBarText
    }
    for _, t in pairs(petTexts) do
        if t and not t.MistUIHidden then
            t:SetAlpha(0)
            -- hooksecurefunc instead of a direct .Show override to avoid taint
            hooksecurefunc(t, "Show", function(self)
                if not self.MistUI_ShowGuard then
                    self.MistUI_ShowGuard = true
                    self:SetAlpha(0)
                    self.MistUI_ShowGuard = nil
                end
            end)
            t:Hide()
            t.MistUIHidden = true
        end
    end
end

-- ===============================================================
-- FRAME POSITIONING
-- ===============================================================
local function ApplyFramePositioning()
    local config = addon.db and addon.db.profile.unitframe.pet
    if not config or not PetFrame then return end

    PetFrame:SetScale(config.scale or 1.0)
    addon.SetEditorBoxScale(PetFrameModule.anchor, config.scale or 1)
    PetFrame:ClearAllPoints()

    if config.override and PetFrameModule.anchor then
        -- Detached: follow the free-floating anchor frame (widgets.pet).
        PetFrame:SetPoint("CENTER", PetFrameModule.anchor, "CENTER", 0, 0)
    else
        -- Attached (default): anchored directly to the player frame.
        PetFrame:SetPoint("CENTER", _G.PlayerFrame, "CENTER", config.x or DEFAULT_ATTACH_X, config.y or DEFAULT_ATTACH_Y)
    end
end

-- ===============================================================
-- POWER BAR MANAGEMENT
-- ===============================================================
-- The unit the stock pet frame shows: the pet, or the player while a vehicle takes the player frame.
local function GetPetFrameUnit()
    return PetFrame.unit or "pet"
end

local function UpdatePowerBarTexture()
    local unit = GetPetFrameUnit()
    if not UnitExists(unit) or not PetFrameManaBar then return end

    local _, powerType = UnitPowerType(unit)
    local texture = POWER_TEXTURES[powerType]
    
    if texture then
        local statusBar = PetFrameManaBar:GetStatusBarTexture()
        statusBar:SetTexture(texture)
        statusBar:SetVertexColor(1, 1, 1, 1)
    end
end

-- ===============================================================
-- COMBAT MODE TEXTURE
-- ===============================================================
local function ConfigureCombatMode()
    local texture = _G.PetAttackModeTexture
    if not texture then return end
    
    UF.ApplySkinPiece(texture, UF.GetFrameSkin().small.flash, 'LEFT', PetPortrait, 'CENTER', -24, -9)
    texture:SetVertexColor(1.0, 0.0, 0.0, 1.0)  -- Initial color
    texture:SetBlendMode("ADD")
    texture:SetAlpha(0.8)  -- Fixed alpha
    -- Sublevels stop at 7 on this client; the threat glow takes 7, one above this.
    texture:SetDrawLayer("OVERLAY", 6)
    
    --  RESET TIMER
    combatPulseTimer = 0
end

-- ===============================================================
-- OnUpdate FUNCTION FOR THE PET FRAME
-- ===============================================================
local function PetFrame_OnUpdate(self, elapsed)
    AnimatePetCombatPulse(elapsed)

    petFrameUpdateThrottle = petFrameUpdateThrottle + elapsed
    if petFrameUpdateThrottle < 0.1 then
        return
    end

    petFrameUpdateThrottle = 0
    -- Value changes already refresh the text through the SetValue hooks; only a vehicle swap needs this.
    local textSystem = moduleState.textSystem
    if textSystem and textSystem.unit ~= GetPetFrameUnit() then
        UpdatePetTextSystemUnit()
    end
end

-- ===============================================================
-- THREAT GLOW SYSTEM 
-- ===============================================================
local function ConfigurePetThreatGlow()
    --  The pet frame uses PetFrameFlash for the threat glow
    local threatFlash = _G.PetFrameFlash
    if not threatFlash then return end
    
    UF.ApplySkinPiece(threatFlash, UF.GetFrameSkin().small.flash, 'LEFT', PetPortrait, 'CENTER', -24, -9)

    -- Alpha, not Hide: UnitFrame_UpdateThreatIndicator owns Show/Hide and the threat color.
    local config = addon.db and addon.db.profile.unitframe.pet
    threatFlash:SetAlpha((config and config.enableThreatGlow == false) and 0 or 1)
    threatFlash:SetDrawLayer("OVERLAY", 7)
end
-- The border sits on PetFrameHealthBar, a child frame, so PetFrame's own glows drew under it; they are raised over it.
local function RaisePetGlows()
    if moduleState.frame.glowLayer then return end
    local layer = CreateFrame("Frame", nil, PetFrame)
    layer:SetAllPoints(PetFrame)
    layer:SetFrameLevel(math.max(PetFrameHealthBar:GetFrameLevel(), PetFrameManaBar:GetFrameLevel()) + 1)
    _G.PetAttackModeTexture:SetParent(layer)
    _G.PetFrameFlash:SetParent(layer)
    moduleState.frame.glowLayer = layer
end

-- ===============================================================
-- FRAME SETUP
-- ===============================================================
local function SetupFrameElement(parent, name, layer, texture, point, size)
    local element = parent:CreateTexture(name)
    element:SetDrawLayer(layer[1], layer[2])
    element:SetTexture(texture)
    element:SetPoint(unpack(point))
    if size then element:SetSize(unpack(size)) end
    return element
end

local function SetupStatusBar(bar, point, size, texture)
    bar:ClearAllPoints()
    bar:SetPoint(unpack(point))
    bar:SetSize(unpack(size))
    if texture then
        bar:GetStatusBarTexture():SetTexture(texture)
        bar:SetStatusBarColor(1, 1, 1, 1)
        -- Phase 2.5: hooksecurefunc instead of direct override to avoid taint
        if not bar.MistUI_ColorHooked then
            hooksecurefunc(bar, "SetStatusBarColor", function(self)
                local tex = self:GetStatusBarTexture()
                if tex then
                    tex:SetVertexColor(1, 1, 1, 1)
                end
            end)
            bar.MistUI_ColorHooked = true
        end
    end
end

-- ===============================================================
-- VEHICLE SYSTEM INTEGRATION FOR PET FRAME
-- ===============================================================

-- Function to update PetFrame textSystem unit based on vehicle state
UpdatePetTextSystemUnit = function()
    if not moduleState.textSystem then
        return
    end
    
    local targetUnit = GetPetFrameUnit()

    -- Update both the public unit field and internal reference
    moduleState.textSystem.unit = targetUnit
    if moduleState.textSystem._unitRef then
        moduleState.textSystem._unitRef.unit = targetUnit
    end
    
    -- Force immediate update
    if moduleState.textSystem.update then
        moduleState.textSystem.update()
    end
end

local function ApplyPetSkin()
    local skin = UF.GetFrameSkin().small
    if moduleState.frame.background then
        UF.ApplySkinPiece(moduleState.frame.background, skin.background, 'LEFT', PetPortrait, 'CENTER', -24, -9)
    end
    if moduleState.frame.border then
        UF.ApplySkinPiece(moduleState.frame.border, skin.border, 'LEFT', PetPortrait, 'CENTER', -24, -9)
    end
end

-- ===============================================================
-- MAIN FRAME REPLACEMENT
-- ===============================================================
local function ReplaceStockPetFrame()
    local petFrame = PetFrame
    if not petFrame then return end

    if not moduleState.hooks.onUpdate then
        -- HookScript instead of SetScript to avoid taint on stock PetFrame
        petFrame:HookScript("OnUpdate", PetFrame_OnUpdate)
        moduleState.hooks.onUpdate = true
        
    end
    
    -- Combat protection for secure frame positioning
    if InCombatLockdown() then
        if addon and addon.CombatQueue then
            addon.CombatQueue:Add("petbar_position", ApplyFramePositioning)
        end
    else
        ApplyFramePositioning()
    end
    
    -- Hide original stock texture
    PetFrameTexture:SetTexture('')
    PetFrameTexture:Hide()
    
    -- Hide original text elements to avoid conflicts
    HideStockPetTexts()
    
    -- Setup portrait
    local portrait = PetPortrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetPoint("LEFT", 6, 0)
        portrait:SetSize(34, 34)
        portrait:SetDrawLayer('BACKGROUND')
    end
    
    -- Create MistUI elements if needed
    if not moduleState.frame.background then
        moduleState.frame.background = SetupFrameElement(
            petFrame,
            'MistUIPetFrameBackground',
            {'BACKGROUND', 1},
            SMALL_FRAME_PATH .. TOT_BASE .. 'BACKGROUND',
            {'LEFT', portrait, 'CENTER', -24, -9}
        )
    end
    
    if not moduleState.frame.border then
        moduleState.frame.border = SetupFrameElement(
            PetFrameHealthBar,
            'MistUIPetFrameBorder',
            {'OVERLAY', 6},
            SMALL_FRAME_PATH .. TOT_BASE .. 'BORDER',
            {'LEFT', portrait, 'CENTER', -24, -9}
        )
    end
    ApplyPetSkin()

    -- Setup health bar
    SetupStatusBar(
        PetFrameHealthBar,
        {'LEFT', portrait, 'RIGHT', 2, 1},
        {70.5, 10},
        UNITFRAME_PATH .. TOT_BASE .. 'Bar-Health'
    )

    -- TexCoord clipping for health bar (prevents baked texture squish)
    if not PetFrameHealthBar.MistUI_TexCoordHooked then
        hooksecurefunc(PetFrameHealthBar, "SetValue", function(self)
            local texture = self:GetStatusBarTexture()
            if not texture then return end
            local _, max = self:GetMinMaxValues()
            local cur = self:GetValue()
            if max > 0 and cur then
                texture:SetTexCoord(0, cur / max, 0, 1)
            end
        end)
        PetFrameHealthBar.MistUI_TexCoordHooked = true
    end
    
    -- Setup mana bar
    SetupStatusBar(
        PetFrameManaBar,
        {'LEFT', portrait, 'RIGHT', -1, -9},
        {74, 7.5}
    )
    UpdatePowerBarTexture()

    -- TexCoord clipping for mana bar (prevents baked texture squish/inversion)
    if not PetFrameManaBar.MistUI_TexCoordHooked then
        hooksecurefunc(PetFrameManaBar, "SetValue", function(self)
            local texture = self:GetStatusBarTexture()
            if not texture then return end
            -- Re-apply power texture in case stock reset it
            UpdatePowerBarTexture()
            local _, max = self:GetMinMaxValues()
            local cur = self:GetValue()
            if max > 0 and cur then
                texture:SetTexCoord(0, cur / max, 0, 1)
            end
        end)
        PetFrameManaBar.MistUI_TexCoordHooked = true
    end
    
    RaisePetGlows()

    -- Configure combat mode
    ConfigureCombatMode()
    if not moduleState.hooks.combatMode then
        hooksecurefunc(_G.PetAttackModeTexture, "Show", function(self)
            ConfigureCombatMode()
        end)
        
        --  MODIFY THE SetVertexColor HOOK TO NOT INTERFERE
        hooksecurefunc(_G.PetAttackModeTexture, "SetVertexColor", function(self, r, g, b, a)
            -- Only intervene if not in our pulse color range
            if not COMBAT_PULSE_SETTINGS.enabled then
                if r ~= 1.0 or g ~= 0.0 or b ~= 0.0 then
                    self:SetVertexColor(1.0, 0.0, 0.0, 1.0)
                end
            end
            -- If the pulse is active, let the animation control the color
        end)
        
        moduleState.hooks.combatMode = true
    end

    -- Configure custom threat glow
    if not moduleState.hooks.threatGlow then
        ConfigurePetThreatGlow()
        
        --  HOOK to maintain configuration
        hooksecurefunc(_G.PetFrameFlash, "Show", ConfigurePetThreatGlow)
        
        moduleState.hooks.threatGlow = true
    end
    
    -- Setup pet name positioning (single-line, no word wrap)
    if PetName then
        PetName:ClearAllPoints()
        PetName:SetPoint("CENTER", petFrame, "CENTER", 10, 13)
        PetName:SetJustifyH("LEFT")
        PetName:SetWidth(65)
        PetName:SetWordWrap(false)
        PetName:SetNonSpaceWrap(false)
        PetName:SetDrawLayer("OVERLAY")
    end
    
    -- ===============================================================
    -- INTEGRATE TEXT SYSTEM
    -- ===============================================================
    if addon.TextSystem then
        
        
        -- Setup the advanced text system for pet frame with dynamic unit
        local initialUnit = GetPetFrameUnit()

        moduleState.textSystem = addon.TextSystem.SetupFrameTextSystem(
            "pet",                 -- frameType
            initialUnit,           -- unit (dynamic based on vehicle state)
            petFrame,              -- parentFrame
            PetFrameHealthBar,     -- healthBar
            PetFrameManaBar,       -- manaBar
            "PetFrame"             -- prefix
        )
        
        -- Ensure we have the correct unit after setup
        UpdatePetTextSystemUnit()
        
    else
        
    end
end


-- ===============================================================
-- UPDATE HANDLER
-- ===============================================================
local function OnPetFrameUpdate()
    ApplyPetSkin()

    UpdatePowerBarTexture()
    ConfigureCombatMode()
    ConfigurePetThreatGlow()
    
    -- Update text system unit for vehicle support
    UpdatePetTextSystemUnit()
    
    -- Update text system if available
    if moduleState.textSystem and moduleState.textSystem.update then
        moduleState.textSystem.update()
    end

    -- Ensure stock texts remain hidden
    HideStockPetTexts()
end

-- ===============================================================
-- MODULE INTERFACE
-- ===============================================================
function PetFrameModule:OnEnable()
    if not moduleState.hooks.petUpdate then
        hooksecurefunc('PetFrame_Update', OnPetFrameUpdate)
        -- The stock totem code gives a warlock's pet frame a second anchor point, which would
        -- stretch it away from ours.
        if select(2, UnitClass("player")) == "WARLOCK" then
            hooksecurefunc('TotemFrame_AdjustPetFrame', function()
                PetFrameModule:UpdateWidgets()
            end)
        end
        moduleState.hooks.petUpdate = true
    end
    -- Hide stock texts when enabling the module
    HideStockPetTexts()
end

function PetFrameModule:OnDisable()
    if moduleState.textSystem and moduleState.textSystem.clear then
        moduleState.textSystem.clear()
    end
end

function PetFrameModule:PLAYER_ENTERING_WORLD()
    ReplaceStockPetFrame()
    -- Defensive redundancy in case stock re-activates the texts
    HideStockPetTexts()
end

-- ===============================================================
-- REFRESH FUNCTION FOR OPTIONS
-- ===============================================================
function addon.RefreshPetFrame()
    PetFrameModule:UpdateWidgets()
    if UnitExists("pet") then
        OnPetFrameUpdate()
    end

    if addon.VisibilityFade and _G.PetFrame then
        local petFrame = _G.PetFrame
        local hoverFrames = { petFrame }
        addon.VisibilityFade.Register("pet", petFrame, {
            dbTable = function() return addon.UF.GetConfig("pet") end,
            hoverFrames = hoverFrames,
            clickThrough = true,
        })
        addon.VisibilityFade.Update("pet")
    end
end



-- ===============================================================
-- EVENT HANDLING
-- ===============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Vehicle events for proper unit switching in PetFrame
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "MistUI" then
        PetFrameModule:OnEnable()
    elseif event == "PLAYER_ENTERING_WORLD" then
        PetFrameModule:PLAYER_ENTERING_WORLD()
        -- Update unit on world enter (handles reloads)
        UpdatePetTextSystemUnit()
    elseif event == "UNIT_ENTERED_VEHICLE" and arg1 == "player" then
        -- When player enters vehicle, PetFrame should show player as "pet"
        UpdatePetTextSystemUnit()
        OnPetFrameUpdate()
    elseif event == "UNIT_EXITED_VEHICLE" and arg1 == "player" then
        -- When player exits vehicle, PetFrame should show actual pet again
        UpdatePetTextSystemUnit()
        OnPetFrameUpdate()
    end
end)

-- ===============================================================
-- CENTRALIZED SYSTEM INTEGRATION
-- ===============================================================

-- Variables for the centralized system
PetFrameModule.anchor = nil
PetFrameModule.initialized = false

-- Create auxiliary frame for anchoring (like party.lua and castbar.lua)
local function CreatePetAnchorFrame()
    if PetFrameModule.anchor then
        return PetFrameModule.anchor
    end

    --  USE CENTRALIZED FUNCTION FROM CORE.LUA
    PetFrameModule.anchor = addon.CreateUIFrame(130, 44, "PetFrame")
    
    return PetFrameModule.anchor
end

-- Detached mode: position the anchor frame from its saved UIParent-relative offset.
local function ApplyWidgetPosition()
    if not PetFrameModule.anchor then return end
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets then return end

    local widgetConfig = addon.db.profile.widgets.pet
    PetFrameModule.anchor:ClearAllPoints()
    if widgetConfig and widgetConfig.posX and widgetConfig.posY then
        local anchor = widgetConfig.anchor or "TOPRIGHT"
        PetFrameModule.anchor:SetPoint(anchor, UIParent, anchor, widgetConfig.posX, widgetConfig.posY)
    else
        PetFrameModule.anchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -150)
    end
end

-- Keep the draggable overlay tracking the real frame while attached.
local function SyncPetOverlayToRealFrame()
    if not PetFrameModule.anchor then return end
    local config = addon.db and addon.db.profile and addon.db.profile.unitframe and addon.db.profile.unitframe.pet
    PetFrameModule.anchor:ClearAllPoints()
    if config and config.override then
        ApplyWidgetPosition()
    elseif not (PetFrame and pcall(PetFrameModule.anchor.SetPoint, PetFrameModule.anchor, "CENTER", PetFrame, "CENTER", 0, 0)) then
        ApplyWidgetPosition()
    end
end

-- Save the anchor frame's current screen position (mirrors ToT/FoT).
local function PersistDetachedPetPosition()
    if not PetFrameModule.anchor then return false end
    if not (addon.db and addon.db.profile) then return false end

    local cx, cy = PetFrameModule.anchor:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return false end

    addon.db.profile.widgets = addon.db.profile.widgets or {}
    addon.db.profile.widgets.pet = addon.db.profile.widgets.pet or {}
    addon.db.profile.widgets.pet.anchor = "CENTER"
    addon.db.profile.widgets.pet.posX = math.floor((cx - ux) + 0.5)
    addon.db.profile.widgets.pet.posY = math.floor((cy - uy) + 0.5)
    return true
end

-- Centralized system interface
function PetFrameModule:LoadDefaultSettings()
    -- Ensure widgets config table exists
    if not addon.db.profile.widgets then
        addon.db.profile.widgets = {}
    end
    
    if not addon.db.profile.widgets.pet then
        addon.db.profile.widgets.pet = {
            anchor = "TOPRIGHT",
            posX = -50,
            posY = -150
        }
        
    end
    
    -- Ensure unitframe.pet config table exists
    if not addon.db.profile.unitframe then
        addon.db.profile.unitframe = {}
    end
    
    if not addon.db.profile.unitframe.pet then
        -- Pet configuration should already exist in database.lua
        
    end
end

function PetFrameModule:UpdateWidgets()
    if InCombatLockdown() then
        if addon and addon.CombatQueue then
            addon.CombatQueue:Add("petframe_widgets", function() PetFrameModule:UpdateWidgets() end)
        end
        return
    end
    ApplyWidgetPosition()
    ApplyFramePositioning()
    SyncPetOverlayToRealFrame()
end

-- Always visible in editor mode, not filtered by class
local function ShouldPetFrameBeVisible()
    return true
end

-- Test display functions for editor mode
local function ShowPetFrameTest()
    -- Show the PET frame even if there is no pet; it is protected, so never during combat.
    if PetFrame and not InCombatLockdown() then
        PetFrame:Show()
        
        -- Simulate having a pet for the test
        if PetName then
            PetName:SetText(L["Test Pet"])
            PetName:Show()
        end
        
        if PetPortrait then
            PetPortrait:Show()
        end
        
        if PetFrameHealthBar then
            PetFrameHealthBar:SetMinMaxValues(0, 100)
            PetFrameHealthBar:SetValue(75)
            PetFrameHealthBar:Show()
        end
        
        if PetFrameManaBar then
            PetFrameManaBar:SetMinMaxValues(0, 100)
            PetFrameManaBar:SetValue(50)
            PetFrameManaBar:Show()
        end

        SyncPetOverlayToRealFrame()
    end
end

local function HidePetFrameTest()
    -- Restore the normal state of the PET frame
    if PetFrame and not InCombatLockdown() then
        if UnitExists("pet") then
            -- If there is a real pet, restore real values
            if PetName then
                PetName:SetText(UnitName("pet") or "")
            end
            
            -- Force update bars with real values
            if PetFrameHealthBar then
                PetFrameHealthBar:SetMinMaxValues(0, UnitHealthMax("pet"))
                PetFrameHealthBar:SetValue(UnitHealth("pet"))
            end
            
            if PetFrameManaBar then
                PetFrameManaBar:SetMinMaxValues(0, UnitPowerMax("pet"))
                PetFrameManaBar:SetValue(UnitPower("pet"))
            end
        else
            -- If there is no real pet, hide everything
            PetFrame:Hide()
            
            -- Clear test values
            if PetName then
                PetName:SetText("")
            end
        end
    end
end

-- Detach and persist when the user drags/nudges/types a new position (mirrors ToT/FoT).
local function DetachPetFrame()
    local config = addon.db and addon.db.profile and addon.db.profile.unitframe and addon.db.profile.unitframe.pet
    if config then
        config.override = true
    end
    PersistDetachedPetPosition()
    PetFrameModule:UpdateWidgets()
end

-- Initialize pet frame for the editor system
local function InitializePetFrameForEditor()
    -- Create the anchor frame
    CreatePetAnchorFrame()

    -- Detach immediately on drag stop, like ToT/FoT's small_frame.lua.
    PetFrameModule.anchor:HookScript("OnDragStop", function(self)
        self.MistUI_WasDragged = true
        DetachPetFrame()
    end)

    -- Register with editor system (full interface like party.lua and castbar.lua)
    addon:RegisterEditableFrame({
        name = "PetFrame",
        frame = PetFrameModule.anchor,
        configPath = {"widgets", "pet"},
        hasTarget = ShouldPetFrameBeVisible,
        showTest = ShowPetFrameTest,
        hideTest = HidePetFrameTest,
        onNudge = DetachPetFrame,
        onHide = function()
            -- Nudge/typed-coordinate edits also count as a manual detach.
            if PetFrameModule.anchor.MistUI_WasDragged or PetFrameModule.anchor.MistUI_WasAdjustedByEditor then
                DetachPetFrame()
                PetFrameModule.anchor.MistUI_WasDragged = nil
                PetFrameModule.anchor.MistUI_WasAdjustedByEditor = nil
            else
                PetFrameModule:UpdateWidgets()
            end
        end,
        LoadDefaultSettings = function() PetFrameModule:LoadDefaultSettings() end,
        UpdateWidgets = function() PetFrameModule:UpdateWidgets() end
    })

    PetFrameModule.initialized = true

end

-- Initialization
InitializePetFrameForEditor()

-- Apply widget positions once addon is fully loaded
local readyFrame = CreateFrame("Frame")
readyFrame:RegisterEvent("ADDON_LOADED")
readyFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "MistUI" then
        -- Apply widget position when the addon is ready
        if PetFrameModule.UpdateWidgets then
            PetFrameModule:UpdateWidgets()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

