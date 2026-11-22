-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.
-- Portions adapted from RetailUI (MIT, (c) 2024 Dmitriy); see THIRD_PARTY_NOTICES.

-- ============================================================================
-- MistUI - Minimap Module
-- ============================================================================

local addon = select(2, ...);
local L = addon.L

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local MinimapModule = {
    initialized = false,
    applied = false,
    originalStates = {},
    farmMode = { active = false, holder = nil, parents = {}, layers = {} },
    hooks = {},
    stateDrivers = {},
    frames = {},
    launcherButtons = {},
    -- Legacy properties for compatibility
    minimapFrame = nil,
    borderFrame = nil,
    isEnabled = false,
    originalMinimapSettings = {},
    originalMask = nil
}
addon.MinimapModule = MinimapModule;

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("minimap", MinimapModule,
        L["Minimap"],
        L["Custom minimap styling, positioning, tracking icons and calendar"])
end

-- Module config helpers (centralized in api.lua)
local function IsModuleEnabled()
    return addon:IsModuleEnabled("minimap")
end

local function IsMinimapSystemActive()
    return IsModuleEnabled() and MinimapModule.applied
end

local function IsMistUIMinimapControlling()
    return MinimapModule.applied or MinimapModule._initializingMinimapSystem
end

-- ============================================================================
-- FARM MODE
-- ============================================================================

local function GetMinimapSettings()
    return addon.db and addon.db.profile and addon.db.profile.minimap
end

-- The farm bonus means this at UI scale 0.8; any other keeps the farm map's size on screen.
local FARM_REFERENCE_UI_SCALE = 0.8

-- The player's minimap scale, times the farm bonus while farm mode is on.
local function GetEffectiveMinimapScale()
    local settings = GetMinimapSettings()
    local scale = tonumber(settings and settings.scale) or 1
    if scale <= 0 then scale = 1 end

    if settings and settings.farm_mode_enabled == true then
        local bonus = math.min(math.max(tonumber(settings.farm_mode_scale) or 1, 1), 2)
        scale = scale * math.max(bonus * FARM_REFERENCE_UI_SCALE / UIParent:GetEffectiveScale(), 1)
    end

    return scale
end

local blipScale = 1.12
-- The upstream blip sheet is laid out for an older client; this client's own sheet
-- holds more icons in other cells, so only the stock one draws the right icons here.
local STOCK_BLIP_TEXTURE = "Interface\\Minimap\\ObjectIcons"

-- Sampled at load: ReplaceStockFrame runs on every apply and would grow the map each time.
local mapUnscaledWidth = Minimap:GetWidth() * 1.36 / blipScale
local mapUnscaledHeight = Minimap:GetHeight() * 1.36 / blipScale
-- Drawn width: 284 was tuned under Texture:SetRotation, which draws the art 1/sqrt(2) smaller.
local BORDER_TO_MAP_RATIO = 284 / math.sqrt(2) / mapUnscaledWidth

local MISTUI_MINIMAP_MASK = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\uiminimapmask.tga"
local MISTUI_MINIMAP_CIRCLE = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\uiminimapborder.tga"
local SQUARE_MINIMAP_MASK = "Interface\\Buttons\\WHITE8X8"
local MISTUI_SQUARE_FRAME = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\uiminimapsquareborder.tga"
local MISTUI_SQUARE_COLLECTOR_ICON = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\collector_toggle_square.tga"
-- The icon is the frame's left chevron cut on 64 art texels, centred 201 texels left of centre.
local MISTUI_SQUARE_ARROW_SIZE, MISTUI_SQUARE_ARROW_X = 64, -201
-- Art texels across the map in game: the line sits ~2% inside the map's edge (measured, not 389).
local MISTUI_SQUARE_MAP_TEXELS = 397
-- The square frame's line runs 389 px apart in its 512 px art.
local MISTUI_SQUARE_SPAN = 389
-- The map's width inside the round ring's 256 px art: the square keeps the round style's map size.
local MISTUI_RING_MAP_SPAN = 238

-- Older LibDBIcon versions put launchers a fixed 80 units out; only their scale can move them.
local LIBDBICON_ORBIT = 80
local MAP_OFFSET_Y = -25
-- The square frame's top chevron rises past the round ring's; this keeps it as far below the bar.
local MISTUI_SQUARE_MAP_DROP = 11

local ADDON_ORBIT_RADIUS = 15
local MISTUI_SETTINGS_BUTTON_SIZE = 21
local MISTUI_SETTINGS_BUTTON_ICON = "Interface\\AddOns\\MistUI\\Textures\\UI\\INV_Misc_Head_Dragon_01"
local MISTUI_CLASSIC_COLLECTOR_ICON = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\collector_toggle.tga"

local MAP_PIN_NAME_FRAGMENTS = {
    "Archy", "GameTimeFrame", "GatherMatePin", "GatherNote", "HandyNotesPin", "HelpOpenTicketButton",
    "QueueStatusMinimapButton", "MiniMapMailFrame", "MiniMapTrackingButton", "MinimMap", "QuestMapPOI",
    "QuestieFrame", "Questie_MiniMapNote", "Spy_MapNoteList_mini", "TimeManagerClockButton", "WorldMapPOIFrame",
    "ZGVMarker", "pfMap", "pfMinimap", "pfQuest", "pfquest", "poiWorldMapPOIFrame",
}

-- Keep launcher buttons skinnable while still excluding internal quest pins.
-- Questie launcher is LibDBIcon-based (LibDBIcon10_Questie), while pfQuest
-- uses a named minimap button (pfQuestIcon).
local QUEST_ADDON_LAUNCHER_BUTTONS = {
    ["pfQuestIcon"] = true,
    ["LibDBIcon10_Questie"] = true,
}

local function IsQuestAddonLauncherButton(button)
    if not button or not button.GetName then
        return false
    end

    local frameName = button:GetName()
    if not frameName then
        return false
    end

    if QUEST_ADDON_LAUNCHER_BUTTONS[frameName] then
        return true
    end

    -- Defensive future-proofing for Questie forks that keep the same LibDBIcon prefix.
    if frameName:find("LibDBIcon10_Questie", 1, true) == 1 then
        return true
    end

    return false
end

local function IsFrameWhitelisted(frameName)
    if type(frameName) ~= "string" then return false end
    for index = 1, #MAP_PIN_NAME_FRAGMENTS do
        if string.find(frameName, MAP_PIN_NAME_FRAGMENTS[index], 1, true) then return true end
    end
    return false
end

local function IsQuestMinimapPin(button)
    if not button then
        return false
    end

    -- Cache positive detections: quest pins are stable frame objects and this
    -- avoids repeated texture/region scans on frequent minimap button rescans.
    if button.MistUI_IsQuestPin then
        return true
    end

    -- Do not classify the actual addon launcher icon as an internal quest pin.
    -- This lets MistUI skin the launcher button while still skipping map pins.
    if IsQuestAddonLauncherButton(button) then
        return false
    end

    local frameName = button:GetName()
    if IsFrameWhitelisted(frameName) then
        button.MistUI_IsQuestPin = true
        return true
    end

    local parent = button:GetParent()
    local parentName = parent and parent.GetName and parent:GetName()
    if IsFrameWhitelisted(parentName) then
        button.MistUI_IsQuestPin = true
        return true
    end

    if button.GetNumChildren then
        local children = { button:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            local childName = child and child.GetName and child:GetName()
            if IsFrameWhitelisted(childName) then
                button.MistUI_IsQuestPin = true
                return true
            end
        end
    end

    -- pfQuest/Questie/TomTom pins and TotemRadius rings are nameless Buttons on Minimap that name checks miss;
    -- detect them (read-only) by their own AddOn folder in a region texture path so the skin leaves them alone.
    if button.GetNumRegions then
        for i = 1, button:GetNumRegions() do
            local region = select(i, button:GetRegions())
            if region and region.GetTexture then
                local tex = region:GetTexture()
                if type(tex) == "string" then
                    local lower = tex:lower()
                    if lower:find("pfquest", 1, true)
                       or lower:find("pfmap", 1, true)
                       or lower:find("pfminimap", 1, true)
                       or lower:find("questie", 1, true)
                       or lower:find("questhelper", 1, true)
                       or lower:find("totemradius", 1, true)
                       or lower:find("\\tomtom\\", 1, true) then
                        button.MistUI_IsQuestPin = true
                        return true
                    end
                end
            end
        end
    end

    local isQuestPin = button.miniMapIcon or button.miniMapIconData or button.pfQuest or button.pfquest
    if isQuestPin then
        button.MistUI_IsQuestPin = true
        return true
    end

    return false
end

-- Profiles saved with the removed second art style keep its shape: round or square.
local STYLE_RENAMES = { square = "mistui_square" }

local function IsSquareLayout()
    local minimapConfig = addon.db and addon.db.profile and addon.db.profile.minimap
    if not minimapConfig then return false end
    local renamed = STYLE_RENAMES[minimapConfig.style]
    if renamed then
        minimapConfig.style = renamed
    end
    return minimapConfig.style == "mistui_square"
end

local function IsMistUISquareFrame()
    local texture = MinimapModule.circleTexture
    return texture == MISTUI_SQUARE_FRAME
end

local function UpdateMinimapCircleSize()
    if not Minimap or not Minimap.Circle then return end

    local mapSize = math.max(Minimap:GetWidth(), Minimap:GetHeight())
    if not mapSize or mapSize <= 0 then return end

    local borderSize = mapSize * BORDER_TO_MAP_RATIO
    if IsMistUISquareFrame() then
        borderSize = borderSize * MISTUI_RING_MAP_SPAN / 256 * 512 / MISTUI_SQUARE_SPAN
    end
    if MinimapModule.activeCircleSize ~= borderSize then
        Minimap.Circle:SetSize(borderSize, borderSize)
        Minimap.Circle:ClearAllPoints()
        Minimap.Circle:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
        MinimapModule.activeCircleSize = borderSize
    end
end

-- Size and x offset from the map's centre, in btn's units, of the frame's left chevron.
local function GetSquareArrowPlacement(btn)
    if not IsMistUISquareFrame() then return nil end
    local texel = Minimap:GetWidth() * Minimap:GetEffectiveScale() / btn:GetEffectiveScale() / MISTUI_SQUARE_MAP_TEXELS
    return MISTUI_SQUARE_ARROW_SIZE * texel, MISTUI_SQUARE_ARROW_X * texel
end

local function UpdateMinimapMaskForRotation()
    if not Minimap or not IsMistUIMinimapControlling() then return end

    local desiredMask = IsSquareLayout() and SQUARE_MINIMAP_MASK or MISTUI_MINIMAP_MASK
    if MinimapModule.activeMask ~= desiredMask then
        Minimap:SetMaskTexture(desiredMask)
        MinimapModule.activeMask = desiredMask
    end
end

local function GetLauncherScale()
    return (1 / blipScale) * (1 + ADDON_ORBIT_RADIUS / 100)
end

-- Old builds forced rotateMinimap off indoors, so a logout while forced saved it as 0.
local function RestoreForcedIndoorRotation()
    local minimapConfig = addon.db and addon.db.profile and addon.db.profile.minimap
    if not minimapConfig or minimapConfig.indoorRotatePreference == nil then return end
    if minimapConfig.indoorRotatePreference == "1" and GetCVar("rotateMinimap") == "0" then
        SetCVar("rotateMinimap", "1")
    end
    minimapConfig.indoorRotatePreference = nil
end

local function UpdateMinimapBackdropAlignment(force)
    if not Minimap or not MinimapBackdrop then return end

    local rotateEnabled = GetCVar("rotateMinimap") == "1"
    local isIndoor = IsIndoors and IsIndoors()
    local desiredYOffset = (rotateEnabled and isIndoor) and 0 or 3

    if force or MinimapModule.backdropYOffset ~= desiredYOffset then
        MinimapBackdrop:ClearAllPoints()
        MinimapBackdrop:SetPoint("CENTER", Minimap, "CENTER", 0, desiredYOffset)
        MinimapModule.backdropYOffset = desiredYOffset
    end
end

local function UpdateIndoorRotateScale()
    if not Minimap then return end

    local desiredScale = blipScale

    if MinimapModule.activeMinimapScale ~= desiredScale then
        Minimap:SetScale(desiredScale)
        MinimapModule.activeMinimapScale = desiredScale
    end
end

local function ResetRingRotation()
    if Minimap.Circle then
        -- Never SetRotation: it also shrinks the ring, and BORDER_TO_MAP_RATIO is its drawn size.
        Minimap.Circle:SetTexCoord(0, 1, 0, 1)
    end
end

local function LiftAbove(frame, key, cover)
    if not frame then return end
    local states = MinimapModule.originalStates
    if cover then
        if not states[key] then
            states[key] = frame:GetFrameLevel()
        end
        frame:SetFrameLevel(math.max(states[key], cover:GetFrameLevel() + 1))
    elseif states[key] then
        frame:SetFrameLevel(states[key])
        states[key] = nil
    end
end

-- The square frame would otherwise cover these icons.
local function SyncCornerIconLevels()
    local cover = IsSquareLayout() and IsMistUIMinimapControlling() and MinimapBackdrop or nil
    LiftAbove(MiniMapInstanceDifficulty, "InstanceDifficultyLevel", cover)
    LiftAbove(MiniMapMailFrame, "MailLevel", cover)
end

local function UpdateZoomButtonsLayout()
    if not MinimapZoomIn or not MinimapZoomOut then return end
    MinimapZoomIn:ClearAllPoints()
    MinimapZoomOut:ClearAllPoints()
    MinimapZoomIn:SetPoint("BOTTOMRIGHT", 0, 15)
    MinimapZoomIn:SetSize(25, 24)
    MinimapZoomOut:SetPoint("BOTTOMRIGHT", -22, 0)
    MinimapZoomOut:SetSize(20, 12)
end

-- The collector asks this when it hands a button back to the map; a module restore keeps the original scale.
local function AdoptLauncher(button)
    if MinimapModule._releasingLaunchers then return nil end
    if button:GetObjectType() ~= "Button" or IsFrameWhitelisted(button:GetName()) then return nil end
    MinimapModule.launcherButtons[button] = true
    return GetLauncherScale()
end

local function GetLibDBIcon()
    if not LibStub or not LibStub.GetLibrary then return nil end
    local ok, libDBIcon = pcall(LibStub.GetLibrary, LibStub, "LibDBIcon-1.0", true)
    if ok and libDBIcon and type(libDBIcon.SetButtonRadius) == "function" then
        return libDBIcon
    end
end

-- LibDBIcon repositions every button with the current shape when its radius is set.
local function SyncLibDBIconShape()
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if MinimapModule.libDBIconShape == shape then return end
    MinimapModule.libDBIconShape = shape
    local libDBIcon = GetLibDBIcon()
    local radius = libDBIcon and tonumber(libDBIcon.radius)
    if radius then
        libDBIcon:SetButtonRadius(radius)
    end
end

-- Calendar and tracking art share one 21x19 cell: pushed art sits one cell pixel down-right.
local function PressShift(frame)
    return frame:GetWidth() / 21, frame:GetHeight() / 19
end

-- The ADD highlight must follow the pushed art's shift or the icon draws twice.
local function AnchorPushedHighlight(button, cellFrame, pushed)
    local highlightTexture = button:GetHighlightTexture()
    if not highlightTexture then
        return
    end
    if pushed == nil then
        pushed = button:GetButtonState() == "PUSHED"
    end
    local dx, dy = 0, 0
    if pushed then
        dx, dy = PressShift(cellFrame)
    end
    highlightTexture:ClearAllPoints()
    highlightTexture:SetPoint("TOPLEFT", button, "TOPLEFT", dx, -dy)
    highlightTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", dx, -dy)
end

-- The plate's shadow rim widens it right and down, so its centre sits up-left of the frame's.
local function TrackingPlateCenter(pushed)
    local w, h = MiniMapTracking:GetWidth(), MiniMapTracking:GetHeight()
    local x, y = -2 * w / 21, 1.5 * h / 19
    if pushed then
        local sx, sy = PressShift(MiniMapTracking)
        x, y = x + sx, y - sy
    end
    return x, y
end

local function UpdateMailPosition()
    if not MiniMapMailFrame or not MiniMapTracking then return end
    MiniMapMailFrame:ClearAllPoints()
    local plateX, plateY = TrackingPlateCenter()
    if IsSquareLayout() then
        MiniMapMailFrame:SetPoint("RIGHT", MiniMapTracking, "LEFT", -3, plateY)
    else
        -- The plate ends two cell px above the frame's bottom; keep 3 units under what is drawn.
        MiniMapMailFrame:SetPoint("TOP", MiniMapTracking, "BOTTOM", plateX, 2 * MiniMapTracking:GetHeight() / 19 - 3)
    end
end

local function UpdateCornerIconsPosition()
    UpdateMailPosition()

    local difficulty = MiniMapInstanceDifficulty
    if difficulty then
        difficulty:ClearAllPoints()
        if IsSquareLayout() then
            difficulty:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -4, -4)
        elseif MinimapBorderTop then
            difficulty:SetPoint("TOP", MinimapBorderTop, 'BOTTOMRIGHT', -20, 6)
        else
            difficulty:SetPoint("TOPRIGHT", Minimap, 'TOPRIGHT', -20, 6)
        end
        difficulty:SetScale(0.85)
    end
end

local function UpdateFrameStyle()
    local circle = Minimap and Minimap.Circle
    if not circle then return end

    UpdateCornerIconsPosition()

    local square = IsSquareLayout()
    local texture = square and MISTUI_SQUARE_FRAME or MISTUI_MINIMAP_CIRCLE
    if MinimapModule.circleTexture ~= texture then
        MinimapModule.circleTexture = texture
        circle:SetTexture(texture)
        circle:SetTexCoord(0, 1, 0, 1)
    end
    circle:SetAlpha(1)
    circle:Show()

    UpdateMinimapCircleSize()
    SyncCornerIconLevels()
    UpdateZoomButtonsLayout()
    if square or GetCVar("rotateMinimap") ~= "1" then
        ResetRingRotation()
    end
    SyncLibDBIconShape()
end

local function GetStyleOffsets()
    if IsSquareLayout() then
        return 0, MAP_OFFSET_Y - MISTUI_SQUARE_MAP_DROP
    end
    return 0, MAP_OFFSET_Y
end

-- Farm mode grows the map from the screen corner it sits in, so a map at an edge grows inward.
local function GetMinimapGrowthPivot(mover)
    local settings = GetMinimapSettings()
    if not (mover and settings and settings.farm_mode_enabled == true) then return "CENTER" end
    local x, y = mover:GetCenter()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (x and y and width and height and width > 0 and height > 0) then return "CENTER" end
    -- GetCenter answers in the mover's own scaled units.
    local ratio = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = x * ratio / width, y * ratio / height
    local pivot = ((y > 2 / 3 and "TOP") or (y < 1 / 3 and "BOTTOM") or "")
        .. ((x > 2 / 3 and "RIGHT") or (x < 1 / 3 and "LEFT") or "")
    return pivot ~= "" and pivot or "CENTER"
end

-- Farm parks the zone bar, so the map alone hugs the box's edges, as far in as it sits at scale 1.
local function GetClusterGrowthShift(mover, clusterLift, mapOffsetY)
    local pivot = GetMinimapGrowthPivot(mover)
    if pivot == "CENTER" then return 0, 0 end
    local scale = MinimapCluster:GetEffectiveScale() / mover:GetEffectiveScale()
    local inward = mapUnscaledWidth * blipScale / 2 * (scale - 1) / scale
    local shiftX = (pivot:find("RIGHT") and -inward) or (pivot:find("LEFT") and inward) or 0
    local mapY = (pivot:find("TOP") and -inward) or (pivot:find("BOTTOM") and inward)
    return shiftX, mapY and mapY - clusterLift - mapOffsetY or 0
end

-- Live style switches and farm growth; ReplaceStockFrame anchors both frames itself on every apply.
local function ApplyStyleAnchors()
    local mover = MinimapModule.minimapFrame
    if not mover then return end
    local clusterLift, mapOffsetY = GetStyleOffsets()
    local shiftX, shiftY = GetClusterGrowthShift(mover, clusterLift, mapOffsetY)
    if MinimapModule.appliedMapOffsetY == mapOffsetY and MinimapModule.appliedShiftX == shiftX
        and MinimapModule.appliedShiftY == shiftY then
        return
    end
    if InCombatLockdown() then
        addon.CombatQueue:Add("minimap_style_anchors", ApplyStyleAnchors)
        return
    end

    MinimapCluster:ClearAllPoints()
    MinimapCluster:SetPoint("CENTER", mover, "CENTER", shiftX, clusterLift + shiftY)
    -- Anchor offsets are read in the map's own scaled units.
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", MinimapCluster, "CENTER", 0, mapOffsetY / blipScale)
    MinimapModule.appliedMapOffsetY = mapOffsetY
    MinimapModule.appliedShiftX, MinimapModule.appliedShiftY = shiftX, shiftY
end

-- SECURE HOOKS: Add secure hooks for critical functions
local function SetupSecureHooks()
    if MinimapModule.hooks.CloseDropDownMenus then
        return -- Already hooked
    end

    -- Secure hook for CloseDropDownMenus
    MinimapModule.hooks.CloseDropDownMenus = function()
        if not MinimapModule.applied then return end
        if MiniMapTrackingIcon and MiniMapTrackingIcon:GetAlpha() > 0 then
            MiniMapTrackingIcon:ClearAllPoints()
            MiniMapTrackingIcon:SetPoint('CENTER', MiniMapTracking, 'CENTER', TrackingPlateCenter())
        end
    end
    hooksecurefunc("CloseDropDownMenus", MinimapModule.hooks.CloseDropDownMenus)

    -- Secure hook for SetTracking
    MinimapModule.hooks.SetTracking = function()
        if MinimapModule.applied then
            MinimapModule:UpdateTrackingIcon()
        end
    end
    hooksecurefunc("SetTracking", MinimapModule.hooks.SetTracking)

    -- Hook for Minimap_UpdateRotationSetting if it exists
    -- Uses indirection via MinimapModule.UpdateRotation to avoid infinite recursion
    -- (calling the global from a post-hook would re-trigger the hook)
    if Minimap_UpdateRotationSetting then
        MinimapModule.hooks.Minimap_UpdateRotationSetting = function()
            if MinimapModule.applied and MinimapModule.UpdateRotation then
                MinimapModule.UpdateRotation()
            end
        end
        hooksecurefunc("Minimap_UpdateRotationSetting", MinimapModule.hooks.Minimap_UpdateRotationSetting)
    end
end

-- CLEANUP: Function for cleaning up hooks
-- Use flag-based approach instead of clearing table
-- (hooksecurefunc can't be undone; clearing the table enables re-registration and duplication)
local function CleanupSecureHooks()
    MinimapModule.hooksDisabled = true
end

local function UpdateCalendarDate()
    local _, _, day = CalendarGetDate()
    if not day or day < 1 or day > 31 then
        return
    end

    local gameTimeFrame = GameTimeFrame
    if not gameTimeFrame then
        return
    end

    local normalTexture = gameTimeFrame:GetNormalTexture()
    if not normalTexture then
        return
    end
    normalTexture:SetAllPoints(gameTimeFrame)
    normalTexture:SetAtlasTexture('Minimap-Calendar-' .. day .. '-Normal', true)

    local highlightTexture = gameTimeFrame:GetHighlightTexture()
    if highlightTexture then
        AnchorPushedHighlight(gameTimeFrame, gameTimeFrame)
        highlightTexture:SetAtlasTexture('Minimap-Calendar-' .. day .. '-Highlight', true)
    end

    local pushedTexture = gameTimeFrame:GetPushedTexture()
    if pushedTexture then
        pushedTexture:SetAllPoints(gameTimeFrame)
        pushedTexture:SetAtlasTexture('Minimap-Calendar-' .. day .. '-Pushed', true)
    end
end

local durabilityMover
local durabilityCaptureBarActive = false

local function GetDurabilityConfig()
    local widgets = addon.db and addon.db.profile and addon.db.profile.widgets
    return widgets and widgets.durability
end

local function IsDurabilityCustomPlaced()
    local cfg = GetDurabilityConfig()
    return durabilityMover ~= nil and cfg ~= nil and cfg.custom_position == true
end

local function ApplyDurabilityPosition()
    local durabilityFrame = DurabilityFrame
    if not durabilityFrame or durabilityFrame.MistUI_SettingPoint then return end
    durabilityFrame.MistUI_SettingPoint = true
    durabilityFrame:ClearAllPoints()
    if IsDurabilityCustomPlaced() then
        durabilityFrame:SetPoint("CENTER", durabilityMover, "CENTER", 0, 0)
    elseif durabilityCaptureBarActive then
        durabilityFrame:SetPoint("TOP", Minimap, "BOTTOM", -15, -35)
    else
        durabilityFrame:SetPoint("TOP", Minimap, "BOTTOM", -15, -5)
    end
    durabilityFrame.MistUI_SettingPoint = nil
end

local function UpdateDurabilityPosition(captureBarVisible)
    durabilityCaptureBarActive = captureBarVisible and true or false
    ApplyDurabilityPosition()
end

local function SyncDurabilityMover()
    if not durabilityMover or not DurabilityFrame then return end
    local ratio = DurabilityFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    durabilityMover:SetSize(DurabilityFrame:GetWidth() * ratio, DurabilityFrame:GetHeight() * ratio)
    local cfg = GetDurabilityConfig()
    if cfg and cfg.custom_position then
        local anchor = cfg.anchor or "CENTER"
        durabilityMover:ClearAllPoints()
        durabilityMover:SetPoint(anchor, UIParent, anchor, cfg.posX or 0, cfg.posY or 0)
    end
end

-- Snapshot coordinates, never anchor to DurabilityFrame: it anchors to the mover once detached.
local function SnapDurabilityMoverToFigure()
    local cx, cy = DurabilityFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    durabilityMover:ClearAllPoints()
    if cx and cy and ux and uy then
        local ratio = DurabilityFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        durabilityMover:SetPoint("CENTER", UIParent, "CENTER", cx * ratio - ux, cy * ratio - uy)
    else
        durabilityMover:SetPoint("TOP", Minimap, "BOTTOM", 0, 0)
    end
end

-- The snapshot goes stale when the minimap moves or rescales in the editor while the figure is attached.
local durabilityFollower = CreateFrame("Frame")
durabilityFollower:Hide()
durabilityFollower:SetScript("OnUpdate", function(self)
    if not (addon.EditorMode and addon.EditorMode:IsActive()) then
        self:Hide()
        return
    end
    if IsDurabilityCustomPlaced() then return end
    local cx, cy = DurabilityFrame:GetCenter()
    local scale = DurabilityFrame:GetEffectiveScale()
    if cx == self.cx and cy == self.cy and scale == self.scale then return end
    self.cx, self.cy, self.scale = cx, cy, scale
    SyncDurabilityMover()
    SnapDurabilityMoverToFigure()
end)

local function DetachDurabilityFrame()
    local widgets = addon.db and addon.db.profile and addon.db.profile.widgets
    if not widgets then return end
    widgets.durability = widgets.durability or {}
    widgets.durability.custom_position = true
    ApplyDurabilityPosition()
end

local function ReplaceStockFrame(frame)
    -- Check combat lockdown before making secure frame changes
    if InCombatLockdown() then
        addon.CombatQueue:Add("minimap_replace_stock_frame", ReplaceStockFrame, frame)
        return
    end

    -- Store original states before modification
    if not MinimapModule.originalStates.MinimapCluster then
        MinimapModule.originalStates.MinimapCluster = {
            points = {},
            scale = MinimapCluster:GetScale()
        }
        for i = 1, MinimapCluster:GetNumPoints() do
            MinimapModule.originalStates.MinimapCluster.points[i] = {MinimapCluster:GetPoint(i)}
        end
    end

    -- Store DurabilityFrame original state
    if DurabilityFrame and not MinimapModule.originalStates.DurabilityFrame then
        MinimapModule.originalStates.DurabilityFrame = {
            points = {},
            scale = DurabilityFrame:GetScale()
        }
        for i = 1, DurabilityFrame:GetNumPoints() do
            MinimapModule.originalStates.DurabilityFrame.points[i] = {DurabilityFrame:GetPoint(i)}
        end
    end

    local clusterLift, mapOffsetY = GetStyleOffsets()
    MinimapModule.appliedMapOffsetY = mapOffsetY

    local minimapCluster = MinimapCluster
    minimapCluster:ClearAllPoints()
    minimapCluster:SetPoint("CENTER", frame, "CENTER", 0, clusterLift)
    -- Stock caps UIPanels at a minimap still in its place; ours can be anywhere.
    minimapCluster:SetMovable(true)
    minimapCluster:SetDontSavePosition(true)
    minimapCluster:SetUserPlaced(true)
    MinimapModule.appliedShiftX, MinimapModule.appliedShiftY = 0, 0

    -- MistUI border top styling
    local minimapBorderTop = MinimapBorderTop
    minimapBorderTop:ClearAllPoints()
    minimapBorderTop:SetPoint("TOP", 0, 5)
    minimapBorderTop:SetAtlasTexture('Minimap-Border-Top', true)
    minimapBorderTop:SetSize(156, 20)

    local minimapZoneButton = MinimapZoneTextButton
    minimapZoneButton:ClearAllPoints()
    minimapZoneButton:SetPoint("LEFT", minimapBorderTop, "LEFT", 7, 1)
    minimapZoneButton:SetWidth(108)

    minimapZoneButton:EnableMouse(true)
    minimapZoneButton:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if WorldMapFrame:IsShown() then
                HideUIPanel(WorldMapFrame)
            else
                ShowUIPanel(WorldMapFrame)
            end
        end
    end)

    local minimapZoneText = MinimapZoneText
    minimapZoneText:SetAllPoints(minimapZoneButton)
    minimapZoneText:SetJustifyH("LEFT")

    -- MistUI clock/calendar positioning (anchored to MistUI's border top)
    local timeClockButton = TimeManagerClockButton
    timeClockButton:GetRegions():Hide()
    timeClockButton:ClearAllPoints()
    timeClockButton:SetPoint("RIGHT", MinimapBorderTop, "RIGHT", -5, 0)
    timeClockButton:SetWidth(30)

    local gameTimeFrame = GameTimeFrame
    gameTimeFrame:ClearAllPoints()
    gameTimeFrame:SetPoint("LEFT", MinimapBorderTop, "RIGHT", 3, -1)
    gameTimeFrame:SetSize(26, 24)
    gameTimeFrame:SetHitRectInsets(0, 0, 0, 0)
    gameTimeFrame:GetFontString():Hide()

    UpdateCalendarDate()

    -- Stock refreshes calendar visuals on several events; re-apply our atlas after each update.
    if not gameTimeFrame.MistUI_CalendarHooked then
        gameTimeFrame.MistUI_CalendarHooked = true
        gameTimeFrame:HookScript("OnEvent", function()
            if MinimapModule.applied then
                UpdateCalendarDate()
            end
        end)
        gameTimeFrame:HookScript("OnShow", function()
            if MinimapModule.applied then
                UpdateCalendarDate()
            end
        end)
        gameTimeFrame:HookScript("OnMouseDown", function(self)
            if MinimapModule.applied then
                AnchorPushedHighlight(self, self, true)
                -- GetButtonState lags the mouse events by a frame.
                addon:After(0, function() AnchorPushedHighlight(self, self) end)
            end
        end)
        gameTimeFrame:HookScript("OnMouseUp", function(self)
            if MinimapModule.applied then
                addon:After(0, function() AnchorPushedHighlight(self, self) end)
            end
        end)
        -- Released off the button, OnMouseUp never arrives; resync before the highlight shows again.
        gameTimeFrame:HookScript("OnEnter", function(self)
            if MinimapModule.applied then
                AnchorPushedHighlight(self, self)
            end
        end)
    end

    -- Configure DurabilityFrame properly
    local durabilityFrame = DurabilityFrame
    if durabilityFrame then
        ApplyDurabilityPosition()
        -- Adjust scale to match the minimap
        durabilityFrame:SetScale(3 / blipScale)
    end

    -- Hook DurabilityFrame:SetPoint to prevent the stock UI from overriding our position
    if durabilityFrame and not durabilityFrame._mistUISetPointHooked then
        hooksecurefunc(durabilityFrame, "SetPoint", ApplyDurabilityPosition)
        durabilityFrame._mistUISetPointHooked = true
    end

    -- MistUI positioning for elements anchored to the border top
    local minimapInstanceFrame = MiniMapInstanceDifficulty
    minimapInstanceFrame:ClearAllPoints()
    minimapInstanceFrame:SetPoint("TOP", MinimapBorderTop, 'BOTTOMRIGHT', -20, 6)
    minimapInstanceFrame:SetScale(0.85) -- Fixed scale for difficulty icon

    local minimapTracking = MiniMapTracking
    minimapTracking:ClearAllPoints()
    -- Mirrors the calendar's gap: the plate stops 3 cell px short of this frame's right edge.
    minimapTracking:SetPoint("RIGHT", MinimapBorderTop, "LEFT", -3 + 3 * 26 / 21, -1)
    minimapTracking:SetSize(26, 24)

    local minimapMailFrame = MiniMapMailFrame
    minimapMailFrame:SetSize(20, 14)
    minimapMailFrame:SetHitRectInsets(0, 0, 0, 0)
    UpdateCornerIconsPosition()

    local minimapMailIconTexture = MiniMapMailIcon
    minimapMailIconTexture:SetAllPoints(minimapMailFrame)
    minimapMailIconTexture:SetAtlasTexture('Minimap-Mail-Normal', true)

    local backgroundTexture = _G[minimapTracking:GetName() .. "Background"]
    backgroundTexture:SetAllPoints(minimapTracking)
    backgroundTexture:SetAtlasTexture('Minimap-Tracking-Background', true)

    local minimapTrackingButton = _G[minimapTracking:GetName() .. 'Button']
    minimapTrackingButton:ClearAllPoints()
    minimapTrackingButton:SetPoint("CENTER", minimapTracking, "CENTER", TrackingPlateCenter())

    -- 17x15 binoculars plus room for the press shift (gen_minimap_tracking.py).
    minimapTrackingButton:SetSize(20, 18)
    minimapTrackingButton:SetHitRectInsets(0, 0, 0, 0)

    -- Left clicks stay the stock button's OnClick: the tracking menu must open from secure code.
    minimapTrackingButton:RegisterForClicks("LeftButtonUp")

    local shineTexture = _G[minimapTrackingButton:GetName() .. "Shine"]
    shineTexture:SetTexture(nil)

    local normalTexture = minimapTrackingButton:GetNormalTexture() or minimapTrackingButton:CreateTexture(nil, "BORDER")
    normalTexture:SetAllPoints(minimapTrackingButton)
    normalTexture:SetAtlasTexture('Minimap-Tracking-Normal', true)

    minimapTrackingButton:SetNormalTexture(normalTexture)

    local highlightTexture = minimapTrackingButton:GetHighlightTexture()
    highlightTexture:SetAllPoints(minimapTrackingButton)
    highlightTexture:SetAtlasTexture('Minimap-Tracking-Highlight', true)

    local pushedTexture = minimapTrackingButton:GetPushedTexture() or minimapTrackingButton:CreateTexture(nil, "BORDER")
    pushedTexture:SetAllPoints(minimapTrackingButton)
    pushedTexture:SetAtlasTexture('Minimap-Tracking-Pushed', true)

    minimapTrackingButton:SetPushedTexture(pushedTexture)

    local minimapFrame = Minimap
    minimapFrame:ClearAllPoints()
    minimapFrame:SetPoint("CENTER", minimapCluster, "CENTER", 0, mapOffsetY)
    minimapFrame:SetScale(blipScale)
    minimapFrame:SetSize(mapUnscaledWidth, mapUnscaledHeight)
    MinimapModule.activeMinimapScale = blipScale

    UpdateMinimapMaskForRotation()

    -- POI (Point of Interest) Custom Textures
    minimapFrame:SetStaticPOIArrowTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-static")
    minimapFrame:SetCorpsePOIArrowTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-corpse")
    minimapFrame:SetPOIArrowTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-guard")
    minimapFrame:SetPlayerTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-player")

    minimapFrame:SetBlipTexture(STOCK_BLIP_TEXTURE)

    -- =====================================================================
    -- BLIP TEXTURE PROTECTION: Override SetBlipTexture with a filter wrapper.
    -- Uses method override (pre-hook) instead of hooksecurefunc (post-hook)
    -- to intercept BEFORE the texture changes, eliminating any flicker from
    -- addons like Carbonite that call SetBlipTexture on a repeating timer.
    -- =====================================================================
    if not MinimapModule.hooks.SetBlipTexture then
        -- Public function: re-applies all MistUI minimap textures
        -- Called by compatibility module after conflicting addons load
        MinimapModule.ReapplyMinimapTextures = function()
            MinimapModule._settingBlipTexture = true
            Minimap:SetBlipTexture(STOCK_BLIP_TEXTURE)
            MinimapModule._settingBlipTexture = false

            -- Re-apply POI textures (Carbonite resets these on init)
            Minimap:SetStaticPOIArrowTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-static")
            Minimap:SetCorpsePOIArrowTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-corpse")
            Minimap:SetPOIArrowTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-guard")
            Minimap:SetPlayerTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\poi-player")
            UpdateMinimapMaskForRotation()
        end

        MinimapModule.hooks.SetBlipTexture = true
    end

    do
        local childScale = 1 / blipScale
        local launcherScale = GetLauncherScale()
        local listed, mapChildren = pcall(function() return { minimapFrame:GetChildren() } end)
        for _, child in ipairs(listed and mapChildren or {}) do
            if child ~= WatchFrame then
                local isLauncher = child:GetObjectType() == "Button" and not IsFrameWhitelisted(child:GetName())
                child:SetScale(isLauncher and launcherScale or childScale)
                if isLauncher then
                    MinimapModule.launcherButtons[child] = true
                end
            end
        end

        -- Anchor offsets are read in the map's own scaled units, so the scale is divided back out.
        local function ShrinkAnchor(point, relativeTo, relativePoint, x, y)
            return { point, relativeTo, relativePoint, (x or 0) / blipScale, (y or 0) / blipScale }
        end
        local anchors = {}
        for index = 1, minimapFrame:GetNumPoints() do
            anchors[#anchors + 1] = ShrinkAnchor(minimapFrame:GetPoint(index))
        end
        minimapFrame:ClearAllPoints()
        for _, anchor in ipairs(anchors) do
            minimapFrame:SetPoint(unpack(anchor, 1, 5))
        end

        _G.GetMinimapShape = function()
            return IsSquareLayout() and "SQUARE" or "ROUND"
        end
    end

    -- Enable mouse wheel zooming on minimap
    minimapFrame:EnableMouseWheel(true)
    minimapFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            -- Scroll up = Zoom in
            Minimap_ZoomIn()
        else
            -- Scroll down = Zoom out
            Minimap_ZoomOut()
        end
    end)

    local minimapBackdropTexture = MinimapBackdrop
    minimapBackdropTexture:ClearAllPoints()
    minimapBackdropTexture:SetPoint("CENTER", minimapFrame, "CENTER", 0, 3)
    MinimapModule.backdropYOffset = 3

    local minimapBorderTexture = MinimapBorder
    minimapBorderTexture:Hide()
    if not Minimap.Circle then
        Minimap.Circle = MinimapBackdrop:CreateTexture(nil, 'ARTWORK')
        Minimap.Circle:SetTexture(MISTUI_MINIMAP_CIRCLE)
    end
    -- A restore hid it.
    Minimap.Circle:Show()
    UpdateMinimapCircleSize()
    UpdateFrameStyle()

    local zoomInButton = MinimapZoomIn
    zoomInButton:SetHitRectInsets(0, 0, 0, 0)

    local normalTexture = zoomInButton:GetNormalTexture()
    normalTexture:SetAllPoints(zoomInButton)
    normalTexture:SetAtlasTexture('Minimap-ZoomIn-Normal', true)

    local highlightTexture = zoomInButton:GetHighlightTexture()
    highlightTexture:SetAllPoints(zoomInButton)
    highlightTexture:SetAtlasTexture('Minimap-ZoomIn-Highlight', true)

    local pushedTexture = zoomInButton:GetPushedTexture()
    pushedTexture:SetAllPoints(zoomInButton)
    pushedTexture:SetAtlasTexture('Minimap-ZoomIn-Pushed', true)

    local disabledTexture = zoomInButton:GetDisabledTexture()
    disabledTexture:SetAllPoints(zoomInButton)
    disabledTexture:SetAtlasTexture('Minimap-ZoomIn-Pushed', true)

    local zoomOutButton = MinimapZoomOut
    zoomOutButton:SetHitRectInsets(0, 0, 0, 0)

    local normalTexture = zoomOutButton:GetNormalTexture()
    normalTexture:SetAllPoints(zoomOutButton)
    normalTexture:SetAtlasTexture('Minimap-ZoomOut-Normal', true)

    local highlightTexture = zoomOutButton:GetHighlightTexture()
    highlightTexture:SetAllPoints(zoomOutButton)
    highlightTexture:SetAtlasTexture('Minimap-ZoomOut-Highlight', true)

    local pushedTexture = zoomOutButton:GetPushedTexture()
    pushedTexture:SetAllPoints(zoomOutButton)
    pushedTexture:SetAtlasTexture('Minimap-ZoomOut-Pushed', true)

    local disabledTexture = zoomOutButton:GetDisabledTexture()
    disabledTexture:SetAllPoints(zoomOutButton)
    disabledTexture:SetAtlasTexture('Minimap-ZoomOut-Pushed', true)

    UpdateZoomButtonsLayout()

    -- Reposition a single WorldStateCaptureBar to below the minimap
    local function RepositionCaptureBar(bar)
        if not bar then return end
        if not bar._mistUISetPointHooked then
            -- Post-hook SetPoint to re-apply our positioning after any stock repositioning
            hooksecurefunc(bar, "SetPoint", function(self, point, relativeTo, relativePoint)
                if not (point == 'CENTER' and relativeTo == minimapFrame and relativePoint == 'BOTTOM') then
                    if not self.MistUI_SettingPoint then
                        self.MistUI_SettingPoint = true
                        self:ClearAllPoints()
                        self:SetPoint('CENTER', minimapFrame, 'BOTTOM', 0, -20)
                        self.MistUI_SettingPoint = nil
                    end
                end
            end)
            -- Hook Show/Hide to update durability position dynamically
            hooksecurefunc(bar, "Show", function() UpdateDurabilityPosition(true) end)
            hooksecurefunc(bar, "Hide", function() UpdateDurabilityPosition(false) end)
            -- OnHide fires after the frame is actually hidden (more reliable than Hide hook)
            bar:HookScript("OnHide", function() UpdateDurabilityPosition(false) end)
            bar:HookScript("OnShow", function() UpdateDurabilityPosition(true) end)
            bar._mistUISetPointHooked = true
        end
        -- Always force our position (safe even with the hook's recursion guard)
        if not bar.MistUI_SettingPoint then
            bar.MistUI_SettingPoint = true
            bar:ClearAllPoints()
            bar:SetPoint('CENTER', minimapFrame, 'BOTTOM', 0, -20)
            bar.MistUI_SettingPoint = nil
        end
    end

    -- Check and reposition all capture bars (there can be multiple in some BGs)
    local function SetupWorldStateCaptureBar()
        local anyVisible = false
        for i = 1, 5 do
            local bar = _G['WorldStateCaptureBar' .. i]
            if bar then
                RepositionCaptureBar(bar)
                if bar:IsVisible() then
                    anyVisible = true
                end
            end
        end
        -- Update durability frame position based on capture bar visibility
        UpdateDurabilityPosition(anyVisible)
        return anyVisible
    end

    -- Try to setup immediately (frame rarely exists at load time)
    SetupWorldStateCaptureBar()

    -- Hook UIParent_ManageFramePositions -stock calls this AFTER creating/repositioning
    -- capture bars, so by the time our post-hook runs the frame is guaranteed to exist
    if UIParent_ManageFramePositions then
        hooksecurefunc("UIParent_ManageFramePositions", SetupWorldStateCaptureBar)
    end

    -- Also listen for key events as a safety net
    local captureBarWatcher = CreateFrame("Frame")
    local captureBarDelayFrame = CreateFrame("Frame")
    local captureBarDelayElapsed = 0
    local captureBarDelayRetries = 0
    captureBarWatcher:RegisterEvent("UPDATE_WORLD_STATES")
    captureBarWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    captureBarWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    captureBarWatcher:RegisterEvent("ZONE_CHANGED")
    captureBarWatcher:SetScript("OnEvent", function(self, event)
        SetupWorldStateCaptureBar()
        -- After reload/login, capture bars may not exist yet -do delayed re-checks
        if event == "PLAYER_ENTERING_WORLD" then
            captureBarDelayElapsed = 0
            captureBarDelayRetries = 0
            captureBarDelayFrame:SetScript("OnUpdate", function(delaySelf, dt)
                captureBarDelayElapsed = captureBarDelayElapsed + dt
                if captureBarDelayElapsed >= 0.5 then
                    captureBarDelayElapsed = 0
                    captureBarDelayRetries = captureBarDelayRetries + 1
                    SetupWorldStateCaptureBar()
                    -- Stop after 5 retries (2.5 seconds total)
                    if captureBarDelayRetries >= 5 then
                        delaySelf:SetScript("OnUpdate", nil)
                    end
                end
            end)
        end
    end)

    --  MANUALLY CONTROL BUTTON MOVEMENT
    minimapTrackingButton:SetScript("OnMouseDown", function(self, button)
        AnchorPushedHighlight(self, MiniMapTracking, true)
        -- GetButtonState lags the mouse events by a frame.
        addon:After(0, function() AnchorPushedHighlight(self, MiniMapTracking) end)
        if button == "LeftButton" then
            -- Old style's tracking icon gets the same press shift as the pushed art.
            if MiniMapTrackingIcon and MiniMapTrackingIcon:GetAlpha() > 0 then
                MiniMapTrackingIcon:ClearAllPoints()
                MiniMapTrackingIcon:SetPoint('CENTER', MiniMapTracking, 'CENTER', TrackingPlateCenter(true))
            end
        end
    end)

    minimapTrackingButton:SetScript("OnMouseUp", function(self, button)
        addon:After(0, function() AnchorPushedHighlight(self, MiniMapTracking) end)
        if button == "LeftButton" then
            -- Restore original position on release
            if MiniMapTrackingIcon and MiniMapTrackingIcon:GetAlpha() > 0 then
                MiniMapTrackingIcon:ClearAllPoints()
                MiniMapTrackingIcon:SetPoint('CENTER', MiniMapTracking, 'CENTER', TrackingPlateCenter())
            end
        elseif button == "RightButton" and self:IsMouseOver() then
            ClearAllTracking()
            MinimapModule:UpdateTrackingIcon()
        end
    end)

    if not minimapTrackingButton.MistUI_PushedHighlightHooked then
        minimapTrackingButton.MistUI_PushedHighlightHooked = true
        minimapTrackingButton:HookScript("OnEnter", function(self)
            if not MinimapModule.applied then return end
            -- Released off the button, OnMouseUp never arrives; resync before the highlight shows again.
            AnchorPushedHighlight(self, MiniMapTracking)
            -- The stock ANCHOR_RIGHT lays the tooltip over the icon and the zone bar; Retail opens it left.
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPRIGHT", MiniMapTracking, "TOPLEFT", -2, 0)
            GameTooltip:SetText(TRACKING, 1, 1, 1)
            GameTooltip:AddLine(MINIMAP_TRACKING_TOOLTIP_NONE, nil, nil, nil, 1)
            GameTooltip:Show()
        end)
    end

    --  HOOK TO RESET ICON POSITION AFTER CLICKS

    -- Setup secure hooks after frame modifications (handles CloseDropDownMenus)
    SetupSecureHooks()

end -- End of ReplaceStockFrame function

local function CreateMinimapBorderFrame(width, height)
    local minimapBorderFrame = CreateFrame('Frame', nil, UIParent)
    minimapBorderFrame:SetSize(width, height)
    minimapBorderFrame._mistUIHeavyUpdateElapsed = 0
    minimapBorderFrame:SetScript("OnUpdate", function(self, elapsed)
        if not IsMistUIMinimapControlling() then return end

        self._mistUIHeavyUpdateElapsed = self._mistUIHeavyUpdateElapsed + elapsed
        if self._mistUIHeavyUpdateElapsed >= 0.1 then
            self._mistUIHeavyUpdateElapsed = 0
            UpdateMinimapMaskForRotation()
            UpdateMinimapBackdropAlignment(false)
            UpdateIndoorRotateScale()
            UpdateMinimapCircleSize()
        end
    end)

    do
        local texture = minimapBorderFrame:CreateTexture(nil, "BORDER")
        texture:SetAllPoints(minimapBorderFrame)
        texture:SetTexture("Interface\\AddOns\\MistUI\\Textures\\Minimap\\MinimapBorder.blp")
        texture:SetAlpha(0)

        minimapBorderFrame.border = texture
    end

    minimapBorderFrame:Hide()
    return minimapBorderFrame
end

-- Helper: is addon button fade currently enabled?
local function IsFadeEnabled()
    return addon.db and addon.db.profile and addon.db.profile.minimap
        and addon.db.profile.minimap.addon_button_fade or false
end

-- Collector buttons should stay fully visible inside the collector box.
local function IsInsideCollector(button)
    local collector = MinimapModule.frames and MinimapModule.frames.iconCollector
    return collector and button and button:GetParent() == collector
end

-- The stock fade helpers share one global table of fading frames; securecall keeps it untainted.
local function FadeAddonButton(frame, helperName, targetAlpha)
    if IsInsideCollector(frame) then
        frame:SetAlpha(1)
    elseif IsFadeEnabled() then
        securecall(helperName, frame, 0.2, frame:GetAlpha(), targetAlpha)
    end
end

local function fadein(frame)
    FadeAddonButton(frame, "UIFrameFadeIn", 1)
end

local function fadeout(frame)
    FadeAddonButton(frame, "UIFrameFadeOut", 0.2)
end

local ADDON_ICON_RING = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\border_buttons.tga"
local ADDON_ICON_FADE_SCRIPTS = { OnEnter = fadein, OnLeave = fadeout }

-- Puts the button ring art on a texture; sizes the ring too when given a side.
local function DressButtonRing(ring, side)
    ring:SetTexture(ADDON_ICON_RING)
    ring:SetTexCoord(0, 1, 0, 1)
    if side then
        ring:SetSize(side, side)
    end
end
local DECORATION_PATH_WORDS = { "Border", "Background", "AlphaMask" }
local addonIconLayouts = {}

local function IsTextureRegion(region)
    return region ~= nil and region:GetObjectType() == "Texture"
end

local function IsDecorationTexture(region)
    local path = tostring(region:GetTexture() or "")
    for _, word in ipairs(DECORATION_PATH_WORDS) do
        if path:find(word, 1, true) then return true end
    end
    return false
end

-- UnskinAddonButton restores from exactly these fields.
local function SnapshotRegion(region)
    local anchors = {}
    for index = 1, region:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(index)
        anchors[index] = { point, relativeTo, relativePoint, x, y }
    end
    region.MistUI_OrigPoints = anchors
    region.MistUI_OrigW, region.MistUI_OrigH = region:GetSize()
    region.MistUI_OrigLayer = region:GetDrawLayer()
    region.MistUI_OrigAlpha = region:GetAlpha()
    region.MistUI_OrigTexCoord = { region:GetTexCoord() }
end

local function BuildAddonIconLayout(button)
    button.MistUI_Skinned = true
    button.MistUI_OrigW, button.MistUI_OrigH = button:GetSize()

    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    local stateful = (normal and pushed and normal:GetTexture() and pushed:GetTexture()) and true or false
    button.MistUI_UsesStateTextures = stateful

    local icons, highlights, decorations, snapshotted = {}, {}, {}, {}
    local function Adopt(region, list)
        if snapshotted[region] then return end
        snapshotted[region] = true
        SnapshotRegion(region)
        list[#list + 1] = region
    end

    for _, region in ipairs({ button:GetRegions() }) do
        if IsTextureRegion(region) then
            if region:GetDrawLayer() == "HIGHLIGHT" then
                Adopt(region, highlights)
            elseif IsDecorationTexture(region) then
                region.MistUI_OrigAlpha = region:GetAlpha()
                decorations[#decorations + 1] = region
            else
                Adopt(region, icons)
            end
        end
    end
    if IsTextureRegion(normal) then Adopt(normal, icons) end
    if IsTextureRegion(pushed) then Adopt(pushed, icons) end
    local hover = button:GetHighlightTexture()
    if IsTextureRegion(hover) then Adopt(hover, highlights) end

    button.MistUI_IconRegions = icons
    button.MistUI_HighlightRegions = highlights
    button.MistUI_DecoRegions = decorations

    local layout = { primary = icons, extra = {} }
    if stateful and IsTextureRegion(normal) then
        layout.primary = { normal, IsTextureRegion(pushed) and pushed or nil }
        for _, region in ipairs(icons) do
            if region ~= normal and region ~= pushed then
                layout.extra[#layout.extra + 1] = region
            end
        end
    end
    addonIconLayouts[button] = layout

    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(ADDON_ICON_RING)
    ring:SetPoint("CENTER", button, "CENTER")
    ring:SetWidth(23)
    ring:SetHeight(23)
    button.circle = ring

    if not button.MistUI_FadeHooked then
        button.MistUI_FadeHooked = true
        for scriptName, handler in pairs(ADDON_ICON_FADE_SCRIPTS) do
            button:HookScript(scriptName, handler)
        end
    end
end

local function ShowAddonIconLayout(button)
    local layout = addonIconLayouts[button]
    if not layout then return end
    local stateful = button.MistUI_UsesStateTextures
    local inset = stateful and 0 or 2
    local side = stateful and 24 or 21

    button.MistUI_SkinActive = true
    button:SetSize(side, side)

    for _, hidden in ipairs({ button.MistUI_DecoRegions, layout.extra }) do
        for _, region in ipairs(hidden) do region:SetAlpha(0) end
    end

    for _, region in ipairs(layout.primary) do
        region:SetAlpha(1)
        region:SetSinglePoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        local savedCoords = stateful and region.MistUI_OrigTexCoord
        if savedCoords then
            region:SetTexCoord(unpack(savedCoords))
        else
            region:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
        region:SetDrawLayer("ARTWORK")
    end

    for _, region in ipairs(button.MistUI_HighlightRegions) do
        region:ClearAllPoints()
        region:SetAllPoints(button)
    end

    local ring = button.circle
    if ring then
        DressButtonRing(ring, stateful and 26 or 23)
        ring:Show()
    end

    button:SetAlpha(IsFadeEnabled() and 0.2 or 1)
end

local function ApplyAddonIconSkin(button)
    if not button or button:GetObjectType() ~= "Button" or IsQuestMinimapPin(button) then
        return
    end
    if not button.MistUI_Skinned then
        BuildAddonIconLayout(button)
    end
    ShowAddonIconLayout(button)
end

-- Restore original button appearance (non-destructive toggle)
local function UnskinAddonButton(button)
    if not button or not button.MistUI_Skinned then return end

    button.MistUI_SkinActive = false

    -- Restore original size
    if button.MistUI_OrigW then
        button:SetSize(button.MistUI_OrigW, button.MistUI_OrigH)
    end

    -- Restore decoration regions
    if button.MistUI_DecoRegions then
        for _, region in ipairs(button.MistUI_DecoRegions) do
            region:SetAlpha(region.MistUI_OrigAlpha or 1)
        end
    end

    -- Restore icon regions to original positioning
    if button.MistUI_IconRegions then
        for _, region in ipairs(button.MistUI_IconRegions) do
            region:SetAlpha(region.MistUI_OrigAlpha or 1)
            if region.MistUI_OrigTexCoord then
                region:SetTexCoord(unpack(region.MistUI_OrigTexCoord))
            else
                region:SetTexCoord(0, 1, 0, 1)
            end
            region:SetDrawLayer(region.MistUI_OrigLayer or 'ARTWORK')
            region:ClearAllPoints()
            if region.MistUI_OrigPoints then
                for _, pt in ipairs(region.MistUI_OrigPoints) do
                    region:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            else
                region:SetAllPoints(button)
            end
            if region.MistUI_OrigW then
                region:SetSize(region.MistUI_OrigW, region.MistUI_OrigH)
            end
        end
    end

    -- Restore highlight regions to original positioning
    if button.MistUI_HighlightRegions then
        for _, region in ipairs(button.MistUI_HighlightRegions) do
            region:ClearAllPoints()
            if region.MistUI_OrigPoints then
                for _, pt in ipairs(region.MistUI_OrigPoints) do
                    region:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            else
                region:SetAllPoints(button)
            end
            if region.MistUI_OrigW then
                region:SetSize(region.MistUI_OrigW, region.MistUI_OrigH)
            end
        end
    end

    -- Hide MistUI circle border
    if button.circle then button.circle:Hide() end

    -- Full alpha
    button:SetAlpha(1)
end

-- Skin addon icons by removing borders

-- Collect all minimap-related buttons from multiple parent frames
-- Some addons (e.g. Carbonite) parent buttons to MinimapBackdrop instead of Minimap
-- NOTE: Do NOT scan MinimapCluster - it contains stock UI buttons (zone text,
-- zoom buttons, clock, etc.) that should never be skinned as addon icons.
local STOCK_MINIMAP_BUTTONS = {
    ['MinimapZoneTextButton'] = true,
    ['MinimapZoomIn'] = true,
    ['MinimapZoomOut'] = true,
    ['MiniMapWorldMapButton'] = true,
    ['MinimapBackdrop'] = true,
    ['QueueStatusMinimapButton'] = true, -- queue eye: has its own mover, skip skin
    ['MiniMapTrackingButton'] = true,
    ['MiniMapMailFrame'] = true,
    ['GameTimeFrame'] = true,
    ['TimeManagerClockButton'] = true,
    ['MiniMapInstanceDifficulty'] = true,
    ['GuildInstanceDifficulty'] = true,
    ['MiniMapChallengeMode'] = true,
    ['MiniMapRecordingButton'] = true,
    ['MiniMapVoiceChatFrame'] = true,
    ['MiniMapVoiceChatFrameIcon'] = true,
    ['MistUI_MinimapSettingsButton'] = true,
}

local function GetAllMinimapButtons()
    local buttons = {}
    local seen = {}

    local function TryAddButton(button)
        if not button or seen[button] or button:GetObjectType() ~= "Button" then
            return
        end

        local buttonName = button:GetName()
        if buttonName and STOCK_MINIMAP_BUTTONS[buttonName] then
            return
        end
        if IsQuestMinimapPin(button) then
            return
        end

        seen[button] = true
        table.insert(buttons, button)
    end

    -- Scan direct Button children, plus one level of Frame wrappers (e.g. AtlasButtonFrame > AtlasButton).
    local function ScanFrame(parentFrame, nested)
        if not parentFrame then
            return
        end
        
        -- Addons like Questie parent hundreds of map pins directly to Minimap, which overflows the Lua
        -- C stack before we can filter them. pcall catches that error so we fail gracefully instead of
        -- spamming an error every frame.
        local ok, children = pcall(function() return { parentFrame:GetChildren() } end)
        if not ok then return end
        for i = 1, #children do
            local child = children[i]
            if not child then
            elseif child:GetObjectType() == "Button" then
                TryAddButton(child)
            elseif not nested and child:GetObjectType() == "Frame" then
                local childName = child:GetName()
                if not (childName and STOCK_MINIMAP_BUTTONS[childName]) then
                    ScanFrame(child, true)
                end
            end
        end
    end

    -- Scan Minimap and MinimapBackdrop only
    -- MinimapCluster is excluded: it contains stock frames (zone text, zoom, etc.)
    ScanFrame(Minimap, false)
    ScanFrame(MinimapBackdrop, false)

    return buttons
end

-- EnableMouse doesn't cascade to children, so every clickable minimap element (native stock
-- buttons, third-party addon icons, collected icons) needs to be listed individually for the
-- hidden-minimap click-through to actually let clicks pass through everywhere, not just the circle.
local function CollectMinimapClickThroughFrames()
    local frames = {}
    for name in pairs(STOCK_MINIMAP_BUTTONS) do
        -- MinimapBackdrop excluded: mouse-off overlay over the circle; enabling it eats native blip tooltips.
        local namedFrame = name ~= 'MinimapBackdrop' and _G[name]
        if namedFrame then table.insert(frames, namedFrame) end
    end
    for _, btn in ipairs(GetAllMinimapButtons()) do
        table.insert(frames, btn)
    end
    local iconCollector = MinimapModule.frames and MinimapModule.frames.iconCollector
    if iconCollector then
        local ok, children = pcall(function() return { iconCollector:GetChildren() } end)
        if ok then
            for _, child in ipairs(children) do
                if child and child.EnableMouse then table.insert(frames, child) end
            end
        end
    end
    return frames
end

-- ============================================================================
-- ADDON BUTTON DISTANCE
-- ============================================================================

-- LibDBIcon r15, still shipped by many addons, has no SetButtonRadius, so its SetPoint is hooked.
local AddonButtonDistance = { hooked = {} }

function AddonButtonDistance.Get()
    -- Off while RestoreMinimapSystem hands the buttons back: it runs before `applied` clears.
    if AddonButtonDistance.off then return 0 end
    local settings = GetMinimapSettings()
    return IsMistUIMinimapControlling() and settings and tonumber(settings.addon_button_distance) or 0
end

-- The r15 library, or nil when a newer one (with SetButtonRadius) is loaded.
function AddonButtonDistance.GetOldLibrary()
    if not LibStub or not LibStub.GetLibrary then return nil end
    local ok, libDBIcon = pcall(LibStub.GetLibrary, LibStub, "LibDBIcon-1.0", true)
    if ok and libDBIcon and type(libDBIcon.objects) == "table" and type(libDBIcon.SetButtonRadius) ~= "function" then
        return libDBIcon
    end
end

-- Offsets are in the button's launcher scale; scaling both keeps r15's square-map clamp square.
function AddonButtonDistance.OnSetPoint(button, point, relativeTo, relativePoint, x, y)
    if AddonButtonDistance.busy or point ~= "CENTER" or relativeTo ~= Minimap or type(x) ~= "number" then return end
    if button:GetParent() ~= Minimap then return end -- collected
    -- The collector puts back the point it saved on the way in, which is already pushed out.
    local placed = button.MistUI_DistancePoint
    if placed and math.abs(x - placed[1]) < 0.05 and math.abs(y - placed[2]) < 0.05 then return end
    local distance = AddonButtonDistance.Get()
    button.MistUI_Distance = distance
    if distance == 0 then
        button.MistUI_DistancePoint = nil
        return
    end
    local orbit = LIBDBICON_ORBIT * button:GetScale()
    local outward = (orbit + distance) / orbit
    x, y = x * outward, y * outward
    placed = placed or {}
    placed[1], placed[2] = x, y
    button.MistUI_DistancePoint = placed
    AddonButtonDistance.busy = true
    button:SetPoint(point, relativeTo, relativePoint, x, y)
    AddonButtonDistance.busy = nil
end

-- Collected buttons are the collector's to place; the library re-places the rest when their distance is stale.
function AddonButtonDistance.ApplyToOldLibrary()
    local libDBIcon = AddonButtonDistance.GetOldLibrary()
    if not libDBIcon then return end
    local distance = AddonButtonDistance.Get()
    for name, button in pairs(libDBIcon.objects) do
        if not AddonButtonDistance.hooked[button] then
            AddonButtonDistance.hooked[button] = true
            hooksecurefunc(button, "SetPoint", AddonButtonDistance.OnSetPoint)
        end
        if (button.MistUI_Distance or 0) ~= distance and button:GetParent() == Minimap and libDBIcon.Refresh then
            -- With its saved db, so a button its addon hides stays hidden (Refresh shows it otherwise).
            libDBIcon:Refresh(name, button.db)
        end
    end
end

-- Compatibility: some addons ship LibDBIcon with a larger default radius,
-- which pushes minimap addon buttons farther from the map edge.
-- Keep this defensive and minimal: only clamp excessive defaults while MistUI minimap is active.
local function NormalizeLibDBIconRadius()
    AddonButtonDistance.ApplyToOldLibrary()

    local libDBIcon = GetLibDBIcon()
    if not libDBIcon then return end

    local currentRadius = tonumber(libDBIcon.radius)
    if not currentRadius then return end
    if MinimapModule.originalStates.LibDBIconRadius == nil then
        if currentRadius <= 5 then return end
        MinimapModule.originalStates.LibDBIconRadius = currentRadius
    elseif currentRadius <= 5 and currentRadius ~= AddonButtonDistance.radius then
        return -- an addon picked its own small radius after ours
    end

    local radius = -5 + AddonButtonDistance.Get()
    if currentRadius ~= radius then
        libDBIcon:SetButtonRadius(radius)
    end
    AddonButtonDistance.radius = radius
end

local function RestoreLibDBIconRadius()
    -- r15 buttons: placed again with the distance off, so they go back to the library's own spot.
    AddonButtonDistance.off = true
    AddonButtonDistance.ApplyToOldLibrary()
    AddonButtonDistance.off = nil

    local originalRadius = MinimapModule.originalStates.LibDBIconRadius
    if originalRadius == nil then return end

    local libDBIcon = GetLibDBIcon()
    if libDBIcon then
        libDBIcon:SetButtonRadius(originalRadius)
    end

    MinimapModule.originalStates.LibDBIconRadius = nil
end

-- ============================================================================
-- MINIMAP ICON COLLECTOR (bridge to minimap_collector.lua)
-- ============================================================================

local function GetConfiguredMinimapCollector()
    local collector = addon and addon.MinimapCollector
    if not collector or type(collector.Configure) ~= "function" then
        return nil
    end

    collector:Configure({
        addon = addon,
        L = L,
        MinimapModule = MinimapModule,
        MISTUI_SETTINGS_BUTTON_SIZE = MISTUI_SETTINGS_BUTTON_SIZE,
        MISTUI_SETTINGS_BUTTON_ICON = MISTUI_SETTINGS_BUTTON_ICON,
        MISTUI_CLASSIC_COLLECTOR_ICON = MISTUI_CLASSIC_COLLECTOR_ICON,
        GetAllMinimapButtons = GetAllMinimapButtons,
        IsQuestMinimapPin = IsQuestMinimapPin,
        ApplyAddonIconSkin = ApplyAddonIconSkin,
        UnskinAddonButton = UnskinAddonButton,
        IsFadeEnabled = IsFadeEnabled,
        fadein = fadein,
        fadeout = fadeout,
        IsMistUISquareFrame = IsMistUISquareFrame,
        GetSquareArrowPlacement = GetSquareArrowPlacement,
        MISTUI_SQUARE_COLLECTOR_ICON = MISTUI_SQUARE_COLLECTOR_ICON,
        DressButtonRing = DressButtonRing,
        AdoptLauncher = AdoptLauncher,
    })

    return collector
end

local function RefreshIntegratedMinimapCollector()
    local collector = GetConfiguredMinimapCollector()
    if collector and collector.Refresh then
        collector:Refresh()
    end
end

local function HideIntegratedAddonMinimapButtons()
    local collector = GetConfiguredMinimapCollector()
    if collector and collector.HideIntegratedAddonButtons then
        collector:HideIntegratedAddonButtons()
    end
end

local function HideIntegratedMinimapCollector()
    local collector = GetConfiguredMinimapCollector()
    if collector and collector.Hide then
        collector:Hide()
    end
end

local function RestoreCollectedButtonsToOrigin()
    local collector = GetConfiguredMinimapCollector()
    if collector and collector.Restore then
        collector:Restore()
    end
end

local function UpdateMistUISettingsButton()
    local collector = GetConfiguredMinimapCollector()
    if collector and collector.UpdateSettingsButton then
        collector:UpdateSettingsButton()
    end
end

-- Function to apply skins to all minimap buttons (exposed for re-application on addon load)
local function ApplySkinsToAllMinimapButtons()
    if not IsMinimapSystemActive() then return end

    local skinEnabled = addon.db and addon.db.profile and addon.db.profile.minimap and
                            addon.db.profile.minimap.addon_button_skin
    if not skinEnabled then return end

    local buttons = GetAllMinimapButtons()
    for _, child in ipairs(buttons) do
        -- Always re-apply. Some addons/editor transitions mutate existing icon regions in-place.
        ApplyAddonIconSkin(child)
    end
end

-- Update fade alpha on all addon buttons (works with or without skin)
local function UpdateAddonButtonFade()
    local fadeEnabled = IsFadeEnabled()
    local buttons = GetAllMinimapButtons()
    for _, child in ipairs(buttons) do
        if not IsQuestMinimapPin(child) then
            -- Hook fade scripts once if not already hooked
            if not child.MistUI_FadeHooked then
                child.MistUI_FadeHooked = true
                child:HookScript('OnEnter', fadein)
                child:HookScript('OnLeave', fadeout)
            end
            child:SetAlpha(fadeEnabled and 0.2 or 1)
        end
    end
end

-- Expose for options to trigger
MinimapModule.ApplySkinsToAllMinimapButtons = ApplySkinsToAllMinimapButtons

-- Unskin all addon buttons (toggle back to original stock appearance)
local function UnskinAllMinimapButtons()
    local buttons = GetAllMinimapButtons()
    for _, child in ipairs(buttons) do
        if child.MistUI_Skinned then
            UnskinAddonButton(child)
        end
    end
end
MinimapModule.UnskinAllMinimapButtons = UnskinAllMinimapButtons

local function RemoveAllMinimapIconBorders()

    -- Apply immediately
    ApplySkinsToAllMinimapButtons()
end

-- Create frame to re-apply skins when new addons load or after reload
local minimapButtonSkinFrame = CreateFrame("Frame")
minimapButtonSkinFrame:RegisterEvent("ADDON_LOADED")
minimapButtonSkinFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
minimapButtonSkinFrame:SetScript("OnEvent", function(self, event, addonName)
    if not IsMinimapSystemActive() then
        self:SetScript("OnUpdate", nil)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Watch for new minimap children for a few seconds after login/reload.
        -- Re-scan periodically: some addons mutate existing icon regions without changing child count.
        local skinEnabled = addon.db and addon.db.profile and addon.db.profile.minimap and
            addon.db.profile.minimap.addon_button_skin
        if skinEnabled then
            ApplySkinsToAllMinimapButtons()
        end
        UpdateCalendarDate()
        RefreshIntegratedMinimapCollector()
        local elapsed = 0
        local checkInterval = 0
        self:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed > 6.0 then
                self:SetScript("OnUpdate", nil)
                return
            end
            checkInterval = checkInterval + dt
            if checkInterval >= 0.3 then
                checkInterval = 0
                if skinEnabled then
                    ApplySkinsToAllMinimapButtons()
                end
                UpdateCalendarDate()
                RefreshIntegratedMinimapCollector()
            end
        end)
        return
    end

    -- ADDON_LOADED handling
    -- Skip MistUI's own loading to avoid double-processing
    if addonName == "MistUI" then return end

    -- Apply defensive LibDBIcon compatibility for late-loading addons.
    NormalizeLibDBIconRadius()

    -- Allow the loading addon to create its minimap button before we rescan.
    local skinEnabled = addon.db and addon.db.profile and addon.db.profile.minimap and
        addon.db.profile.minimap.addon_button_skin
    local elapsed = 0
    self:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed > 0.5 then
            if skinEnabled then
                ApplySkinsToAllMinimapButtons()
            end
            RefreshIntegratedMinimapCollector()
            self:SetScript("OnUpdate", nil)
        end
    end)
end)

local function GetUnmanagedCollectorButtonCount()
    local buttons = GetAllMinimapButtons()
    local settingsButton = MinimapModule.frames and MinimapModule.frames.settingsButton
    local count = 0

    for _, child in ipairs(buttons) do
        if child ~= settingsButton and not IsQuestMinimapPin(child) and not child.MistUI_CollectorManaged then
            count = count + 1
        end
    end

    return count
end

local minimapCollectorSyncFrame = CreateFrame("Frame")
local SetCollectorSyncEnabled
do
    local elapsed = 0
    local syncInterval = 1.00
    local lastUnmanagedCount = 0
    local lastMinimapChildCount = -1
    local lastBackdropChildCount = -1

    local function ResetSyncState()
        lastUnmanagedCount = 0
        lastMinimapChildCount = -1
        lastBackdropChildCount = -1
    end

    local function CollectorSync_OnUpdate(_, dt)
        elapsed = elapsed + dt
        if elapsed < syncInterval then
            return
        end
        elapsed = 0

        if not IsMinimapSystemActive() then
            ResetSyncState()
            return
        end

        local minimapConfig = addon.db and addon.db.profile and addon.db.profile.minimap
        if minimapConfig and minimapConfig.collector_enabled == false then
            ResetSyncState()
            return
        end

        local iconCollector = MinimapModule.frames and MinimapModule.frames.iconCollector
        if iconCollector and iconCollector.isOpen then
            ResetSyncState()
            return
        end

        local minimapChildCount = (Minimap and Minimap.GetNumChildren and Minimap:GetNumChildren()) or 0
        local backdropChildCount = (MinimapBackdrop and MinimapBackdrop.GetNumChildren and MinimapBackdrop:GetNumChildren()) or 0
        local childCountChanged = minimapChildCount ~= lastMinimapChildCount
            or backdropChildCount ~= lastBackdropChildCount

        if not childCountChanged then
            return
        end

        lastMinimapChildCount = minimapChildCount
        lastBackdropChildCount = backdropChildCount

        local unmanagedCount = GetUnmanagedCollectorButtonCount()
        if unmanagedCount <= 0 then
            lastUnmanagedCount = 0
            return
        end

        local shouldRefresh = unmanagedCount ~= lastUnmanagedCount

        lastUnmanagedCount = unmanagedCount

        if shouldRefresh then
            RefreshIntegratedMinimapCollector()
            if addon.VisibilityFade then
                addon.VisibilityFade.AddHoverFrames("minimap", CollectMinimapClickThroughFrames())
            end
        end
    end

    -- Armed by Apply, disarmed by Restore: a disabled module must not keep a per-frame poller.
    SetCollectorSyncEnabled = function(enabled)
        ResetSyncState()
        elapsed = 0
        minimapCollectorSyncFrame:SetScript("OnUpdate", enabled and CollectorSync_OnUpdate or nil)
    end
end

local function RemoveStockFrames()
    -- Hidden is enough, and its scripts stay: nulled, the button comes back dead if anything shows it.
    if MiniMapWorldMapButton then
        MiniMapWorldMapButton:Hide()
        MiniMapWorldMapButton:UnregisterAllEvents()
    end

    local blizzFrames =
        {MiniMapTrackingIcon, MiniMapTrackingIconOverlay, MiniMapMailBorder, MiniMapTrackingButtonBorder}

    for _, frame in pairs(blizzFrames) do
        frame:SetAlpha(0)
    end

    -- Hide stock north indicator and compass -MistUI doesn't use them
    if MinimapNorthTag then MinimapNorthTag:Hide() end
    if MinimapCompassTexture then MinimapCompassTexture:Hide() end

    --  CALL THE NEW FUNCTIONS
    RemoveAllMinimapIconBorders()
    UpdateMistUISettingsButton()
end

-- Stored on module table so the hooksecurefunc post-hook can reference it
-- without calling the global (which would cause infinite recursion)
MinimapModule.UpdateRotation = function()
    if not IsMistUIMinimapControlling() then return end

    -- Always hide the stock MinimapBorder -MistUI uses Minimap.Circle instead.
    -- The stock Minimap_UpdateRotationSetting re-shows MinimapBorder when rotation
    -- is toggled off (e.g. closing Interface Options); our post-hook must counteract that.
    if MinimapBorder then
        MinimapBorder:Hide()
    end

    if GetCVar("rotateMinimap") == "1" then
        if MinimapModule.borderFrame then
            MinimapModule.borderFrame:Show()
        end
        UpdateMinimapMaskForRotation()
        UpdateMinimapBackdropAlignment(false)
        UpdateIndoorRotateScale()
        UpdateMinimapCircleSize()
    else
        if MinimapModule.borderFrame then
            MinimapModule.borderFrame:Hide()
        end
        UpdateMinimapMaskForRotation()
        UpdateMinimapBackdropAlignment(false)
        UpdateIndoorRotateScale()
        UpdateMinimapCircleSize()
        if Minimap then
            ResetRingRotation()
        end
    end

    MinimapNorthTag:Hide()
    MinimapCompassTexture:Hide()
end

local selectedRaidDifficulty
local allowedRaidDifficulty

-- Update tracking icon using atlas textures
function MinimapModule:UpdateTrackingIcon()
    if not addon.db or not MiniMapTrackingIcon or not MiniMapTrackingButton then
        return
    end

    -- Several kinds of tracking can be active at once on this client, so there is no single
    -- "current tracking" icon to show: the button always carries the modern art.
    MiniMapTrackingIcon:SetTexture('')
    MiniMapTrackingIcon:SetAlpha(0)

    local normalTexture = MiniMapTrackingButton:GetNormalTexture()
    if normalTexture then
        normalTexture:SetAtlasTexture('Minimap-Tracking-Normal', true)
    end

    local pushedTexture = MiniMapTrackingButton:GetPushedTexture()
    if pushedTexture then
        pushedTexture:SetAtlasTexture('Minimap-Tracking-Pushed', true)
    end

    local highlightTexture = MiniMapTrackingButton:GetHighlightTexture()
    if highlightTexture then
        highlightTexture:SetAtlasTexture('Minimap-Tracking-Highlight', true)
    end

    -- Always hide overlay
    if MiniMapTrackingIconOverlay then
        MiniMapTrackingIconOverlay:SetAlpha(0)
    end
end

-- =================================================================
-- MODULE ENABLE/DISABLE SYSTEM
-- =================================================================

function MinimapModule:StoreOriginalSettings()
    -- Store original stock minimap settings
    if MinimapCluster then
        local point, relativeTo, relativePoint, xOfs, yOfs = MinimapCluster:GetPoint()
        self.originalMinimapSettings = {
            scale = MinimapCluster:GetScale(),
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs,
            isStored = true
        }
    end

    -- Store original DurabilityFrame settings
    if DurabilityFrame then
        local point, relativeTo, relativePoint, xOfs, yOfs = DurabilityFrame:GetPoint(1)
        self.originalMinimapSettings.durability = {
            scale = DurabilityFrame:GetScale(),
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs
        }
    end

    -- Store that we need to restore to stock default mask
    if not self.originalMask then
        self.originalMask = "Textures\\MinimapMask" -- Standard stock default

    end
end

-- Queue eye editor frame, separate from the minimap's own. On this client one button,
-- QueueStatusMinimapButton, stands for every queue (dungeons, raids, battlegrounds, pet battles).
local QUEUE_EYE_FALLBACK_SIZE = 33 -- The stock size of the button

function MinimapModule:RegisterLFGEditorFrame()
    local MiniMapLFGFrame = QueueStatusMinimapButton
    if not MiniMapLFGFrame then return end
    if self.lfgWrapper then return end  -- already registered

    -- Size wrapper to match the eye frame
    local lfgW = (MiniMapLFGFrame:GetWidth()  > 0 and MiniMapLFGFrame:GetWidth())  or QUEUE_EYE_FALLBACK_SIZE
    local lfgH = (MiniMapLFGFrame:GetHeight() > 0 and MiniMapLFGFrame:GetHeight()) or QUEUE_EYE_FALLBACK_SIZE
    local lfgWrapper = addon.CreateUIFrame(lfgW, lfgH, "LFGFrame")

    -- Apply saved or default position
    local lfgCfg    = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.lfgframe
    local lfgAnchor = (lfgCfg and lfgCfg.anchor) or "TOPRIGHT"
    local lfgX      = (lfgCfg and lfgCfg.posX)   or -20
    local lfgY      = (lfgCfg and lfgCfg.posY)   or -220
    lfgWrapper:SetPoint(lfgAnchor, UIParent, lfgAnchor, lfgX, lfgY)

    -- Hook SetPoint/ClearAllPoints BEFORE reparenting so stock can't move it
    local origLFGSetPoint       = MiniMapLFGFrame.SetPoint
    local origLFGClearAllPoints = MiniMapLFGFrame.ClearAllPoints
    local lfgLocked = false

    MiniMapLFGFrame.SetPoint = function(self, ...)
        if lfgLocked then return end
        origLFGSetPoint(self, ...)
    end
    MiniMapLFGFrame.ClearAllPoints = function(self)
        if lfgLocked then return end
        origLFGClearAllPoints(self)
    end

    -- Reparent and lock in place
    MiniMapLFGFrame:SetParent(lfgWrapper)
    origLFGClearAllPoints(MiniMapLFGFrame)
    origLFGSetPoint(MiniMapLFGFrame, "TOPLEFT", lfgWrapper, "TOPLEFT", 0, 0)
    lfgLocked = true

    -- Keep track of original Show/Hide so we can force-show in editor mode
    local origLFGShow = MiniMapLFGFrame.Show
    local origLFGHide = MiniMapLFGFrame.Hide

    -- Register wrapper in editor so it becomes a moveable mover
    addon:RegisterEditableFrame({
        name    = "lfgframe",
        frame   = lfgWrapper,
        configPath = {"widgets", "lfgframe"},
        showTest = function()
            -- Hide the real eye so the wrapper can receive mouse/drag events
            origLFGHide(MiniMapLFGFrame)
            lfgWrapper:Show()
        end,
        hideTest = function()
            -- The queue may have changed while editing: let the stock code decide whether the eye shows.
            origLFGHide(MiniMapLFGFrame)
            if QueueStatusFrame_Update and QueueStatusFrame then
                QueueStatusFrame_Update(QueueStatusFrame)
            end
        end,
        module  = self
    })

    self.lfgWrapper = lfgWrapper
end

-- Durability figure follows the minimap (and dodges the PvP capture bar) until dragged.
function MinimapModule:RegisterDurabilityEditorFrame()
    if not DurabilityFrame or durabilityMover then return end

    durabilityMover = addon.CreateUIFrame(DurabilityFrame:GetWidth(), DurabilityFrame:GetHeight(), "DurabilityFrame")
    durabilityMover:HookScript("OnDragStart", DetachDurabilityFrame)
    SyncDurabilityMover()

    addon:RegisterEditableFrame({
        name = "durability",
        frame = durabilityMover,
        stockFrame = DurabilityFrame,
        configPath = {"widgets", "durability"},
        showTest = function()
            SyncDurabilityMover()
            if not IsDurabilityCustomPlaced() then
                SnapDurabilityMoverToFigure()
            end
            durabilityMover:Show()
            durabilityFollower.cx, durabilityFollower.cy, durabilityFollower.scale = nil, nil, nil
            durabilityFollower:Show()
        end,
        onNudge = DetachDurabilityFrame,
        onHide = function()
            durabilityFollower:Hide()
            durabilityMover.MistUI_WasDragged = nil
            durabilityMover.MistUI_WasAdjustedByEditor = nil
            ApplyDurabilityPosition()
        end,
        module = self
    })

    self.durabilityMover = durabilityMover
end

function MinimapModule:ResetDurabilityPosition()
    local cfg = GetDurabilityConfig()
    if cfg then
        cfg.custom_position = false
    end
    ApplyDurabilityPosition()
end

function MinimapModule:ApplyMinimapSystem()
    if self.applied then
        return -- Already applied
    end

    -- Check module enabled state
    if not IsModuleEnabled() then
        return
    end

    -- Check combat lockdown
    if InCombatLockdown() then
        addon.CombatQueue:Add("minimap_apply", function()
            MinimapModule:ApplyMinimapSystem()
        end)
        return
    end

    -- Store original settings before applying MistUI changes
    self:StoreOriginalSettings()

    -- Defensive compatibility for LibDBIcon-based addon buttons.
    NormalizeLibDBIconRadius()
    HideIntegratedAddonMinimapButtons()
    
    RestoreForcedIndoorRotation()

    -- Initialize the MistUI minimap system
    self._initializingMinimapSystem = true
    self:InitializeMinimapSystem()
    self.applied = true
    self._initializingMinimapSystem = nil
    self.isEnabled = true -- Legacy compatibility
    SetCollectorSyncEnabled(true)
end

function MinimapModule:RestoreMinimapSystem()
    if not self.applied then
        return -- Already restored
    end

    -- Check combat lockdown
    if InCombatLockdown() then
        addon.CombatQueue:Add("minimap_restore", function()
            MinimapModule:RestoreMinimapSystem()
        end)
        return
    end

    if addon.VisibilityFade then addon.VisibilityFade.Reset("minimap", 1) end

    self:RestoreFarmMode()

    SetCollectorSyncEnabled(false)

    -- Hide MistUI frames
    if self.minimapFrame then
        self.minimapFrame:Hide()
        self.frames.minimapFrame = nil
    end
    if self.borderFrame then
        self.borderFrame:SetScript("OnUpdate", nil)
        self.borderFrame:Hide()
        self.frames.borderFrame = nil
    end
    if self.frames.settingsButton then
        self.frames.settingsButton:Hide()
    end
    HideIntegratedMinimapCollector()
    self._releasingLaunchers = true
    RestoreCollectedButtonsToOrigin()
    self._releasingLaunchers = nil

    if MinimapCluster then
        MinimapCluster:SetUserPlaced(false)
        MinimapCluster:SetDontSavePosition(false)
        MinimapCluster:SetMovable(false)
    end
    -- Restore original MinimapCluster state
    if MinimapCluster and self.originalStates.MinimapCluster then
        MinimapCluster:ClearAllPoints()
        local originalState = self.originalStates.MinimapCluster
        for _, point in ipairs(originalState.points) do
            MinimapCluster:SetPoint(unpack(point))
        end
        MinimapCluster:SetScale(originalState.scale)
    elseif MinimapCluster and self.originalMinimapSettings.isStored then
        -- Fallback to legacy method
        MinimapCluster:ClearAllPoints()
        MinimapCluster:SetPoint(self.originalMinimapSettings.point or "TOPRIGHT",
            self.originalMinimapSettings.relativeTo or UIParent,
            self.originalMinimapSettings.relativePoint or "TOPRIGHT", self.originalMinimapSettings.xOfs or -16,
            self.originalMinimapSettings.yOfs or -116)
        MinimapCluster:SetScale(self.originalMinimapSettings.scale or 1.0)
    end

    -- Restore original DurabilityFrame state
    if DurabilityFrame and self.originalStates.DurabilityFrame then
        DurabilityFrame:ClearAllPoints()
        local originalState = self.originalStates.DurabilityFrame
        for _, point in ipairs(originalState.points) do
            DurabilityFrame:SetPoint(unpack(point))
        end
        DurabilityFrame:SetScale(originalState.scale)
    elseif DurabilityFrame and self.originalMinimapSettings.durability then
        -- Fallback to legacy method
        local durSettings = self.originalMinimapSettings.durability
        DurabilityFrame:ClearAllPoints()
        DurabilityFrame:SetPoint(
            durSettings.point or "TOPLEFT",
            durSettings.relativeTo or MinimapCluster,
            durSettings.relativePoint or "BOTTOMLEFT",
            durSettings.xOfs or -15,
            durSettings.yOfs or -10
        )
        DurabilityFrame:SetScale(durSettings.scale or 1.0)
    end

    -- Restore other original states
    if MiniMapWorldMapButton then
        -- Its OnLoad took this to keep the binding in the tooltip; UnregisterAllEvents dropped it.
        MiniMapWorldMapButton:RegisterEvent("UPDATE_BINDINGS")
        MiniMapWorldMapButton:Show()
    end

    -- CRITICAL: Restore original stock minimap mask
    if Minimap and self.originalMask then
        Minimap:SetMaskTexture(self.originalMask)
    end

    -- Restore original stock blip texture
    if Minimap then
        MinimapModule._settingBlipTexture = true
        Minimap:SetBlipTexture(STOCK_BLIP_TEXTURE)
        MinimapModule._settingBlipTexture = false
    end

    -- Restore external LibDBIcon radius if we normalized it.
    RestoreLibDBIconRadius()

    -- Fully disable minimap icon/calendar styling when the module is toggled off.
    UnskinAllMinimapButtons()
    if GameTimeFrame and GameTimeFrame.GetFontString then
        local gameTimeText = GameTimeFrame:GetFontString()
        if gameTimeText then
            gameTimeText:Show()
        end
    end
    if GameTimeFrame_SetDate then
        GameTimeFrame_SetDate()
    end

    -- Cleanup hooks (tracked for debugging)
    CleanupSecureHooks()

    self.applied = false
    self._initializingMinimapSystem = nil
    self.isEnabled = false -- Legacy compatibility

    -- Undo MistUI-owned chrome only after we applied; never run this on cold start (fights other minimap addons).
    if Minimap and Minimap.Circle then
        Minimap.Circle:Hide()
    end
    SyncCornerIconLevels()
    if self.appliedMapOffsetY and self.appliedMapOffsetY ~= MAP_OFFSET_Y and Minimap and MinimapCluster then
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", MinimapCluster, "CENTER", 0, MAP_OFFSET_Y / blipScale)
    end
    self.appliedMapOffsetY = nil
    -- The stock mask went back on above; a re-apply must not trust the cached one.
    self.activeMask = nil
    if MinimapBorder then
        MinimapBorder:Show()
    end
    if MinimapBorderTop then
        MinimapBorderTop:ClearAllPoints()
        MinimapBorderTop:SetPoint("TOPRIGHT")
        MinimapBorderTop:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
        MinimapBorderTop:SetTexCoord(0.25, 1.0, 0.0, 0.125)
        MinimapBorderTop:SetSize(192, 32)
        MinimapBorderTop:SetAlpha(1)
    end
    if MinimapBackdrop and MinimapCluster then
        MinimapBackdrop:ClearAllPoints()
        MinimapBackdrop:SetPoint("CENTER", MinimapCluster, "CENTER", 0, -20)
    end
    local blizzFrames = {
        MiniMapTrackingIcon, MiniMapTrackingIconOverlay, MiniMapMailBorder, MiniMapTrackingButtonBorder,
    }
    for _, frame in pairs(blizzFrames) do
        if frame then
            frame:SetAlpha(1)
        end
    end
    if Minimap and self.activeMinimapScale then
        Minimap:SetScale(1)
        self.activeMinimapScale = nil
    end
    self.backdropYOffset = nil
    if Minimap_UpdateRotationSetting then
        Minimap_UpdateRotationSetting()
    end

    addon:Print(L["Minimap module restored to stock defaults"])
end

-- Blips don't respect MinimapCluster's cascaded alpha (confirmed: swapping to the stock
-- atlas only restyles them, doesn't hide them - they're still fully opaque). A nonexistent texture
-- path renders nothing at all, so point there while hidden instead of touching Minimap's own alpha,
-- which risks blips not refreshing until /reload.
local function ApplyBlipTextureForFadeVisibility(shouldShow)
    if not Minimap then return end
    local settings = addon.db and addon.db.profile and addon.db.profile.minimap
    if not settings then return end
    local texture
    if shouldShow then
        texture = STOCK_BLIP_TEXTURE
    else
        texture = "Interface\\AddOns\\MistUI\\Textures\\Minimap\\blip_blank"
    end
    MinimapModule._settingBlipTexture = true
    Minimap:SetBlipTexture(texture)
    MinimapModule._settingBlipTexture = false
end

-- After the minimap's effective alpha (even cascaded, not just its own) sits at 0 for a while, the
-- client stops refreshing the terrain texture - it comes back frozen/blank until something like a
-- zoom change wakes it up. Bump the zoom a level and immediately revert it to force that refresh
-- without an actual visible zoom change.
local function ForceMinimapTerrainRefresh()
    if not Minimap or not Minimap.GetZoom or not Minimap.SetZoom then return end
    local currentZoom = Minimap:GetZoom()
    Minimap:SetZoom(currentZoom + 1)
    if Minimap:GetZoom() == currentZoom then
        Minimap:SetZoom(math.max(0, currentZoom - 1))
    end
    Minimap:SetZoom(currentZoom)
end

local function OnMinimapFadeComplete(shouldShow)
    if shouldShow then
        ForceMinimapTerrainRefresh()
    end
end

-- Alpha-only fade on MinimapCluster (never Minimap itself, and never Hide/Show) - Minimap's own
-- SetAlpha/Hide has been reported to stall blip texture updates until a reload.
local function SyncMinimapVisibility()
    if not MinimapCluster or not addon.VisibilityFade then return end
    -- MinimapCluster's cascade covers Minimap/zone text/buttons, but MistUI's own border ring
    -- (self.borderFrame) and the addon-icon collector are siblings parented to UIParent, not
    -- children - fade them explicitly too.
    local extraFrames = {}
    if MinimapModule.borderFrame then table.insert(extraFrames, MinimapModule.borderFrame) end
    local iconCollector = MinimapModule.frames and MinimapModule.frames.iconCollector
    if iconCollector then table.insert(extraFrames, iconCollector) end
    -- MinimapBackdrop excluded on purpose: mouse-off overlay over the circle; enabling it eats native blip tooltips.
    local hoverFrames = { MinimapCluster }
    if Minimap then table.insert(hoverFrames, Minimap) end
    if iconCollector then table.insert(hoverFrames, iconCollector) end
    addon.VisibilityFade.Register("minimap", MinimapCluster, {
        frames = extraFrames,
        hoverFrames = hoverFrames,
        -- IsMouseOver() polling (not OnEnter/OnLeave) so hovering any button drawn on top of the
        -- minimap (settings gear, addon icon collector, zoom, tracking...) still counts as hover -
        -- a plain geometric check doesn't care which frame actually wins the hit-test at that pixel.
        pollHover = true,
        -- Minimap isn't a secure/protected frame, so EnableMouse can react live even mid-combat.
        clickThrough = true,
        mouseSafeInCombat = true,
        onVisibilityChange = ApplyBlipTextureForFadeVisibility,
        onFadeComplete = OnMinimapFadeComplete,
        dbTable = function() return addon.db and addon.db.profile and addon.db.profile.minimap end,
    })
    addon.VisibilityFade.AddHoverFrames("minimap", CollectMinimapClickThroughFrames())
    addon.VisibilityFade.Update("minimap")
end
MinimapModule.SyncMinimapVisibility = SyncMinimapVisibility

-- Always on while editing: the client's minimap renderer breaks once the map is partly off screen.
function MinimapModule:ApplyEditorClamp()
    local mover = self.minimapFrame
    if not mover then return end
    if not self.editorActive then
        mover:SetClampRectInsets(0, 0, 0, 0)
        mover:SetClampedToScreen(false)
        return
    end

    local moverLeft, moverRight = mover:GetLeft(), mover:GetRight()
    local moverTop, moverBottom = mover:GetTop(), mover:GetBottom()
    if not (moverLeft and moverRight and moverTop and moverBottom) then return end
    local moverScale = mover:GetEffectiveScale()
    local left, right, top, bottom
    -- A top border faded out by Border Alpha 0 doesn't count; the zone text still can.
    for _, frame in ipairs({ Minimap, MinimapBorderTop, MinimapZoneTextButton }) do
        local shown = frame and frame:IsVisible() and frame:GetAlpha() > 0
        local frameLeft, frameRight = shown and frame:GetLeft(), shown and frame:GetRight()
        local frameTop, frameBottom = shown and frame:GetTop(), shown and frame:GetBottom()
        if frameLeft and frameRight and frameTop and frameBottom then
            -- Edges come back in each frame's own scaled units; a texture (the top border) has its parent's.
            local scaled = frame.GetEffectiveScale and frame or frame:GetParent()
            local ratio = scaled:GetEffectiveScale() / moverScale
            frameLeft, frameRight = frameLeft * ratio, frameRight * ratio
            frameTop, frameBottom = frameTop * ratio, frameBottom * ratio
            left = left and math.min(left, frameLeft) or frameLeft
            right = right and math.max(right, frameRight) or frameRight
            top = top and math.max(top, frameTop) or frameTop
            bottom = bottom and math.min(bottom, frameBottom) or frameBottom
        end
    end
    if not left then return end

    -- Positive left/bottom and negative right/top shrink the clamp rect toward the visible map.
    mover:SetClampRectInsets(left - moverLeft, right - moverRight, top - moverTop, bottom - moverBottom)
    mover:SetClampedToScreen(true)
end

function MinimapModule:InitializeMinimapSystem()
    -- Load TimeManager addon if not loaded
    if not IsAddOnLoaded('Blizzard_TimeManager') then
        LoadAddOn('Blizzard_TimeManager')
    end

    self.minimapFrame = addon.CreateUIFrame(230, 230, "MinimapFrame")
    -- Simple visual tweak: keep minimap editor overlay 10px lower.
    do
        if self.minimapFrame then
            self.minimapFrame.MistUI_BoxShiftY = -10
            addon.SetEditorBoxScale(self.minimapFrame, addon.db.profile.minimap.scale or 1)
        end
        if self.minimapFrame and self.minimapFrame.editorText then
            self.minimapFrame.editorText:ClearAllPoints()
            self.minimapFrame.editorText:SetPoint("CENTER", self.minimapFrame, "CENTER", 0, -10)
        end
    end

    --  AUTOMATIC REGISTRATION IN THE CENTRALIZED SYSTEM
    addon:RegisterEditableFrame({
        name = "minimap",
        frame = self.minimapFrame,
        stockFrame = MinimapCluster,
        configPath = {"widgets", "minimap"},
        onShow = function()
            -- Match quest tracker behavior: clamp while editing.
            self.editorActive = true
            self:ApplyEditorClamp()
            -- Force full opacity while dragging so the user can actually see what they're moving.
            if addon.VisibilityFade then addon.VisibilityFade.Reset("minimap", 1) end
        end,
        onHide = function()
            -- Remove custom clamp settings after editor mode.
            self.editorActive = false
            self:ApplyEditorClamp()
            self:UpdateWidgets() -- Apply new configuration on editor exit
            addon:RefreshMinimap()
        end,
        module = self
    })

    -- Queue eye (QueueStatusMinimapButton) -independent moveable frame
    self:RegisterLFGEditorFrame()
    self:RegisterDurabilityEditorFrame()

    local defaultX, defaultY = -7, 0
    local widgetConfig = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.minimap

    if widgetConfig then
        self.minimapFrame:SetPoint(widgetConfig.anchor or "TOPRIGHT", UIParent, widgetConfig.anchor or "TOPRIGHT",
            widgetConfig.posX or defaultX, widgetConfig.posY or defaultY)
    else
        self.minimapFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", defaultX, defaultY)
    end

    self.borderFrame = CreateMinimapBorderFrame(232, 232)
    self.borderFrame:SetPoint("CENTER", MinimapBorder, "CENTER", 0, -2)

    RemoveStockFrames()
    ReplaceStockFrame(self.minimapFrame)
    UpdateMistUISettingsButton()

    --  ADD THIS LINE TO APPLY ALL SETTINGS AT STARTUP
    self:UpdateSettings()

    -- Must run AFTER UpdateSettings(): it unconditionally applies settings.blip_skin's texture,
    -- which would otherwise stomp the fade-aware blip texture chosen here right after login.
    SyncMinimapVisibility()

    if self.UpdateRotation then
        self.UpdateRotation()
    end

    -- Hook tracking changes to update icon automatically
    MiniMapTrackingButton:HookScript("OnEvent", function()
        self:UpdateTrackingIcon()
    end)

    -- Initial tracking icon update
    self:UpdateTrackingIcon()

    -- A /reload with farm mode on never goes through RefreshMinimap, so park here too.
    self:ApplyFarmMode()
end

function MinimapModule:Initialize()
    if self.initialized then
        return -- Already initialized
    end
    
    -- Check if minimap module is enabled
    if not IsModuleEnabled() then
        return
    end

    -- Only apply MistUI modifications if module is enabled
    self:ApplyMinimapSystem()
    
    self.initialized = true
end

-- Remove functions that no longer exist and convert to MistUI functions
function MinimapModule:UpdateSettings()
    local scale = GetEffectiveMinimapScale()

    if self.minimapFrame then
        local widgetConfig = addon.db.profile.widgets.minimap
        local anchor = widgetConfig.anchor or "TOPRIGHT"
        local x = widgetConfig.posX or 0
        local y = widgetConfig.posY or 0

        -- Update DurabilityFrame position
        if DurabilityFrame then
            DurabilityFrame:SetScale(addon.db.profile.minimap.scale or 1.0)
            SyncDurabilityMover()
            ApplyDurabilityPosition()
        end
        
        --  APPLY POSITION
        self.minimapFrame:ClearAllPoints()
        self.minimapFrame:SetPoint(anchor, UIParent, anchor, x, y)

        --  APPLY SCALE (works perfectly now)
        if MinimapCluster then
            MinimapCluster:SetScale(scale)
            addon.SetEditorBoxScale(self.minimapFrame, scale, GetMinimapGrowthPivot(self.minimapFrame))
        end

        if self.borderFrame then
            self.borderFrame:SetScale(scale)
        end

        ApplyStyleAnchors()
        UpdateFrameStyle()
        UpdateMinimapMaskForRotation()
        UpdateMinimapCircleSize()

        --  APPLY ALL SETTINGS
        self:ApplyAllSettings()
    end

    --  GLOBAL MINIMAP SETTINGS
    if Minimap then
        MinimapModule._settingBlipTexture = true
        Minimap:SetBlipTexture(STOCK_BLIP_TEXTURE)
        MinimapModule._settingBlipTexture = false
    end

    --  REFRESH OTHER ELEMENTS
    self:UpdateTrackingIcon()
end

local function GetClockTextFrame()
    if not TimeManagerClockButton then
        return nil
    end

    -- Try multiple methods to find the clock text
    local clockText = TimeManagerClockButton.text
    if clockText then
        return clockText
    end

    clockText = TimeManagerClockButton:GetFontString()
    if clockText then
        return clockText
    end

    -- Search in children
    local children = { TimeManagerClockButton:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child.GetFont then
            return child
        end
    end

    -- Search in regions
    for i = 1, TimeManagerClockButton:GetNumRegions() do
        local region = select(i, TimeManagerClockButton:GetRegions())
        if region and region.GetFont then
            return region
        end
    end

    return nil
end

local function ApplyClockAndZoneLayout(showClock)
    if TimeManagerClockButton then
        if showClock then
            TimeManagerClockButton:Show()
        else
            TimeManagerClockButton:Hide()
        end
    end

    if MinimapZoneTextButton and MinimapBorderTop then
        MinimapZoneTextButton:ClearAllPoints()
        if showClock then
            -- Restore default MistUI position when clock is visible.
            MinimapZoneTextButton:SetPoint("LEFT", MinimapBorderTop, "LEFT", 7, 1)
            MinimapZoneTextButton:SetWidth(108)
        else
            -- Center the zone text when clock is hidden.
            MinimapZoneTextButton:SetPoint("CENTER", MinimapBorderTop, "CENTER", 0, 1)
            MinimapZoneTextButton:SetWidth(150)
        end
    end

    if MinimapZoneText then
        MinimapZoneText:SetJustifyH(showClock and "LEFT" or "CENTER")
        if MinimapZoneTextButton then
            MinimapZoneText:SetAllPoints(MinimapZoneTextButton)
        end
    end
end

-- ============================================================================
-- FARM MODE TOGGLE
-- ============================================================================

-- Parked on a hidden holder, so they stay hidden whatever calls Show(); missing globals are skipped.
local FARM_MODE_CHROME = {
    "MinimapBorderTop",
    "MinimapZoneTextButton",
    "GameTimeFrame",
    "TimeManagerClockButton",
    "MiniMapTracking",
    "MiniMapMailFrame",
    "MiniMapInstanceDifficulty",
    "GuildInstanceDifficulty",
    "MiniMapChallengeMode",
    "MistUI_MinimapSettingsButton",
    "MistUI_MinimapIconCollector",
}

function MinimapModule:ToggleFarmMode()
    local settings = GetMinimapSettings()
    if not settings or not IsMinimapSystemActive() then
        addon:Print(L["Minimap module not available."])
        return
    end

    local active = settings.farm_mode_enabled == true
    settings.farm_mode_enabled = not active

    addon:Print(active and L["Farm mode disabled"] or L["Farm mode enabled"])

    addon:RefreshMinimap()
end

local function CreateFarmModeHolder()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    return holder
end

local function SaveFrameLayers(frame, layers)
    if not frame.GetFrameLevel then return end
    layers[frame] = { frame:GetFrameStrata(), frame:GetFrameLevel() }
    local children = { frame:GetChildren() }
    for index = 1, #children do
        SaveFrameLayers(children[index], layers)
    end
end

-- Top-down, since a parent's SetFrameStrata also moves its children.
local function RestoreFrameLayers(frame, layers)
    if not frame.GetFrameLevel then return end
    local saved = layers[frame]
    if saved then
        if frame:GetFrameStrata() ~= saved[1] then frame:SetFrameStrata(saved[1]) end
        if frame:GetFrameLevel() ~= saved[2] then frame:SetFrameLevel(saved[2]) end
    end
    local children = { frame:GetChildren() }
    for index = 1, #children do
        RestoreFrameLayers(children[index], layers)
    end
end

-- Parents are read for everything before anything moves: a parked child would record the holder.
local function ParkFarmModeFrames()
    local holder = MinimapModule.farmMode.holder or CreateFarmModeHolder()
    MinimapModule.farmMode.holder = holder
    local parents, layers = MinimapModule.farmMode.parents, MinimapModule.farmMode.layers

    local parkable = {}
    for index = 1, #FARM_MODE_CHROME do
        local region = _G[FARM_MODE_CHROME[index]]
        if region and not parents[region] then
            parents[region] = region:GetParent()
            SaveFrameLayers(region, layers)
            parkable[#parkable + 1] = region
        end
    end

    for index = 1, #parkable do
        parkable[index]:SetParent(holder)
    end
end

-- SetParent resets strata and level (e.g. the gear sits at Minimap + 20), so both are put back.
local function RestoreFarmModeFrames()
    local parents, layers = MinimapModule.farmMode.parents, MinimapModule.farmMode.layers

    for region, parent in pairs(parents) do
        region:SetParent(parent)
    end
    for region in pairs(parents) do
        RestoreFrameLayers(region, layers)
    end
    wipe(parents)
    wipe(layers)
end

function MinimapModule:RestoreFarmMode()
    RestoreFarmModeFrames()
    self.farmMode.active = false
end

-- RefreshMinimap already queues this while in combat.
function MinimapModule:ApplyFarmMode()
    local settings = GetMinimapSettings()
    if not settings then return end

    if settings.farm_mode_enabled ~= true then
        if self.farmMode.active then self:RestoreFarmMode() end
        return
    end

    self.farmMode.active = true

    -- Runs while active too: chrome created since (the gear once the collector is enabled) gets parked.
    ParkFarmModeFrames()
end

-- Apply all minimap settings from the database
function MinimapModule:ApplyAllSettings()
    if not addon.db or not addon.db.profile or not addon.db.profile.minimap then
        return
    end

    local settings = addon.db.profile.minimap

    --  APPLY BORDER ALPHA
    if MinimapBorderTop and settings.border_alpha then
        MinimapBorderTop:SetAlpha(settings.border_alpha)
    end

    --  APPLY CALENDAR VISIBILITY
    if settings.calendar ~= nil then
        if GameTimeFrame then
            if settings.calendar then
                GameTimeFrame:Show()
            else
                GameTimeFrame:Hide()
            end
        end
    end

    --  APPLY CLOCK VISIBILITY AND ADJUST ZONE TEXT
    if settings.clock ~= nil then
        ApplyClockAndZoneLayout(settings.clock)
    end

    --  APPLY ZOOM BUTTONS VISIBILITY
    if settings.zoom_buttons ~= nil then
        if MinimapZoomIn and MinimapZoomOut then
            if settings.zoom_buttons then
                MinimapZoomIn:Show()
                MinimapZoomOut:Show()
            else
                MinimapZoomIn:Hide()
                MinimapZoomOut:Hide()
            end
        end
    end

    -- Apply clock font size
    if settings.clock_font_size and TimeManagerClockButton then
        local clockText = GetClockTextFrame()
        if clockText then
            local font, _, flags = clockText:GetFont()
            clockText:SetFont(font, settings.clock_font_size, flags)
        end
    end

    --  APPLY ZONE TEXT FONT SIZE
    if settings.zonetext_font_size and MinimapZoneText then
        local font, _, flags = MinimapZoneText:GetFont()
        MinimapZoneText:SetFont(font, settings.zonetext_font_size, flags)
    end

    UpdateCornerIconsPosition()
end
-- Editor mode interface
function MinimapModule:LoadDefaultSettings()
    -- Use correct database: addon.db (not addon.core.db)
    if not addon.db.profile.widgets then
        addon.db.profile.widgets = {}
    end
    addon.db.profile.widgets.minimap = {
        anchor = "TOPRIGHT",
        posX = 0,
        posY = 0
    }
end

function MinimapModule:UpdateWidgets()
    -- Use correct database: addon.db (not addon.core.db)
    if not addon.db or not addon.db.profile.widgets or not addon.db.profile.widgets.minimap then

        self:LoadDefaultSettings()
        return
    end

    local widgetOptions = addon.db.profile.widgets.minimap
    self.minimapFrame:SetPoint(widgetOptions.anchor, widgetOptions.posX, widgetOptions.posY)

end

-- Editor mode uses centralized system

-- Refresh function to be called from options.lua
function addon:RefreshMinimap()
    if InCombatLockdown() then
        if addon.CombatQueue then
            addon.CombatQueue:Add("minimap_refresh", addon.RefreshMinimap)
        end
        return
    end

    if MinimapModule.isEnabled then
        -- Parks or restores the chrome first: the settings pass below re-applies visibility.
        MinimapModule:ApplyFarmMode()
        MinimapModule:UpdateSettings()
        -- Also update tracking icon when settings change
        MinimapModule:UpdateTrackingIcon()
        MinimapModule.SyncMinimapVisibility()
        -- Addon Button Distance (LibDBIcon radius, or the r15 hook).
        NormalizeLibDBIconRadius()

        -- Refresh addon icon skinning
        local skinEnabled = addon.db and addon.db.profile and addon.db.profile.minimap
            and addon.db.profile.minimap.addon_button_skin
        if skinEnabled then
            RemoveAllMinimapIconBorders()
        else
            UnskinAllMinimapButtons()
        end

        -- Instant toggle for addon button fade
        UpdateAddonButtonFade()
        UpdateMistUISettingsButton()

        -- Parks chrome this pass just created, e.g. the gear when the collector gets enabled.
        MinimapModule:ApplyFarmMode()

        -- Scale, style and farm mode move the map inside its mover; refit the editor clamp to it.
        if MinimapModule.editorActive then MinimapModule:ApplyEditorClamp() end
    end
end

-- Profile Callbacks for configuration change handling
MinimapModule.OnProfileChanged = function()
    addon:RefreshMinimapSystem()
end

MinimapModule.OnProfileCopied = function()
    addon:RefreshMinimapSystem()
end

MinimapModule.OnProfileReset = function()
    addon:RefreshMinimapSystem()
end

-- System refresh function for enable/disable
function addon:RefreshMinimapSystem()
    local isEnabled =
        addon.db and addon.db.profile and addon.db.profile.modules and addon.db.profile.modules.minimap and
            addon.db.profile.modules.minimap.enabled

    if isEnabled == nil then
        isEnabled = true -- Default to enabled
    end

    if isEnabled then
        if MinimapModule.applied then
            addon:RefreshMinimap()
        else
            MinimapModule:ApplyMinimapSystem()
        end
    else
        if addon:ShouldDeferModuleDisable("minimap", MinimapModule) then
            return
        end
        MinimapModule:RestoreMinimapSystem()
    end
end

-- =================================================================
-- INITIALIZATION
-- =================================================================

-- Initialize when the addon is ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MistUI" then
        -- Set original mask to standard stock default
        if not MinimapModule.originalMask then
            MinimapModule.originalMask = "Textures\\MinimapMask"
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        MinimapModule:Initialize()
        self:UnregisterAllEvents()
    end
end)

-- The farm map's size follows the UI scale, which changes without a reload.
local function RefreshFarmForUIScale()
    local settings = GetMinimapSettings()
    if settings and settings.farm_mode_enabled == true then addon:RefreshMinimap() end
end

addon.core.RegisterMessage(MinimapModule, "MISTUI_UI_SCALE_CHANGED", RefreshFarmForUIScale)
local uiScaleWatcher = CreateFrame("Frame")
uiScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
uiScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- A frame later: the client settles UIParent's scale around these events.
uiScaleWatcher:SetScript("OnEvent", function() addon:After(0, RefreshFarmForUIScale) end)

