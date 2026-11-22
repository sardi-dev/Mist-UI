-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
MistUI - Position Presets (Edit Mode)
================================================================================
Save, load, export and import element positions edited via /mistedit without
touching scales, colors, or other module settings.
================================================================================
]]

local addon = select(2, ...)
local L = addon.L

local PositionPresets = {}
addon.PositionPresets = PositionPresets

local SNAPSHOT_VERSION = 1
-- Not DragonUI's "!DUIPP1!": the frames differ, so its layout strings must not import here.
local EXPORT_HEADER = "!MISTUIPP1!"
local PANEL_WIDGET_KEY = "positionPresetPanel"

local WIDGET_POSITION_KEYS = {
    anchor = true,
    posX = true,
    posY = true,
    custom_position = true,
}

local CASTBAR_POSITION_KEYS = {
    override = true,
    x_position = true,
    y_position = true,
    anchor = true,
    anchorParent = true,
    anchorFrame = true,
}

local UNITFRAME_POSITION_KEYS = {
    override = true,
    x = true,
    y = true,
    anchor = true,
    anchorParent = true,
    anchorFrame = true,
}

local CASTBAR_PLAYER_POSITION_KEYS = {
    x_position = true,
    y_position = true,
}

local QUESTTRACKER_POSITION_KEYS = {
    anchor = true,
    x = true,
    y = true,
}

local LOOTROLL_POSITION_KEYS = {
    anchor = true,
    x = true,
    y = true,
}

-- What each saved position field may hold. A layout string can come from anyone, so anything
-- else is refused before it reaches the profile.
local NUMBER_FIELDS = { posX = true, posY = true, x = true, y = true, x_position = true, y_position = true }
local BOOLEAN_FIELDS = { override = true, custom_position = true }
local STRING_FIELDS = { anchor = true, anchorParent = true, anchorFrame = true }
local MAX_STRING_LENGTH = 100

local SNAPSHOT_SUBSECTIONS = {
    castbar = { player = CASTBAR_PLAYER_POSITION_KEYS, target = CASTBAR_POSITION_KEYS, focus = CASTBAR_POSITION_KEYS },
    unitframe = { tot = UNITFRAME_POSITION_KEYS, fot = UNITFRAME_POSITION_KEYS, party = UNITFRAME_POSITION_KEYS },
}
local SNAPSHOT_FLAT_SECTIONS = { questtracker = QUESTTRACKER_POSITION_KEYS, lootroll = LOOTROLL_POSITION_KEYS }

local Serializer = {}
LibStub("AceSerializer-3.0"):Embed(Serializer)
local LibDeflate = LibStub("LibDeflate")

-- ============================================================================
-- HELPERS
-- ============================================================================

local function PickFields(source, fieldMap)
    if type(source) ~= "table" or type(fieldMap) ~= "table" then
        return nil
    end

    local result = {}
    for key in pairs(fieldMap) do
        if source[key] ~= nil then
            result[key] = source[key]
        end
    end

    return next(result) and result or nil
end

local function CopyTable(source)
    if addon.DeepCopy then
        return addon.DeepCopy(source)
    end
    if addon.CopyTable then
        return addon:CopyTable(source)
    end
    return source
end

local function MergeFields(target, source, fieldMap)
    if type(source) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        if not fieldMap or fieldMap[key] then
            target[key] = value
        end
    end
end

local function IsValidFieldValue(key, value)
    if NUMBER_FIELDS[key] then
        return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    elseif BOOLEAN_FIELDS[key] then
        return type(value) == "boolean"
    elseif STRING_FIELDS[key] then
        return type(value) == "string" and #value <= MAX_STRING_LENGTH
    end
    return false
end

-- The path of the first unknown or badly typed field of one section, or nil when all are fine.
local function FindInvalidField(section, fieldMap, path)
    if type(section) ~= "table" then
        return path
    end
    for key, value in pairs(section) do
        if not fieldMap[key] or not IsValidFieldValue(key, value) then
            return path .. "." .. tostring(key)
        end
    end
end

local function IsKnownWidget(key)
    if type(key) ~= "string" or key == PANEL_WIDGET_KEY then
        return false
    end
    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.widgets
    local profile = addon.db and addon.db.profile and addon.db.profile.widgets
    return (defaults and defaults[key] ~= nil) or (profile and profile[key] ~= nil) or false
end

-- The first setting of a snapshot this version does not know or cannot use, or nil when it is
-- safe to restore as a whole (a layout string is applied completely or not at all).
local function FindInvalidSetting(snapshot)
    if type(snapshot) ~= "table" or snapshot.version ~= SNAPSHOT_VERSION then
        return "version"
    end
    for key, value in pairs(snapshot) do
        local bad
        if key == "version" then
            bad = nil
        elseif SNAPSHOT_FLAT_SECTIONS[key] then
            bad = FindInvalidField(value, SNAPSHOT_FLAT_SECTIONS[key], key)
        elseif SNAPSHOT_SUBSECTIONS[key] then
            if type(value) ~= "table" then
                return key
            end
            for child, fields in pairs(value) do
                local fieldMap = SNAPSHOT_SUBSECTIONS[key][child]
                if not fieldMap then
                    return key .. "." .. tostring(child)
                end
                bad = FindInvalidField(fields, fieldMap, key .. "." .. child)
                if bad then
                    return bad
                end
            end
        elseif key == "widgets" then
            if type(value) ~= "table" then
                return key
            end
            for widgetKey, fields in pairs(value) do
                if not IsKnownWidget(widgetKey) then
                    return "widgets." .. tostring(widgetKey)
                end
                bad = FindInvalidField(fields, WIDGET_POSITION_KEYS, "widgets." .. widgetKey)
                if bad then
                    return bad
                end
            end
        elseif key == "additional" then
            -- Written empty by every snapshot so far; kept accepted so older strings still import.
            bad = (type(value) ~= "table" or next(value) ~= nil) and key or nil
        else
            bad = tostring(key)
        end
        if bad then
            return bad
        end
    end
end

local function SaveQuadrantSection(frame, sectionName)
    if not frame or not addon.db or not addon.db.profile then
        return
    end

    local point, x, y = addon.GetQuadrantAnchor(frame)
    if not point then
        return
    end
    -- A module's automatic shift (e.g. loot rolls lifted over a stacked pet bar) is not a saved move.
    local layoutOffset = frame.MistUI_LayoutOffset
    if layoutOffset then
        x = x - layoutOffset[1]
        y = y - layoutOffset[2]
    end

    addon.db.profile[sectionName] = addon.db.profile[sectionName] or {}
    local section = addon.db.profile[sectionName]
    section.anchor = point
    section.x = x
    section.y = y
end

function PositionPresets:GetStore()
    if not addon.db or not addon.db.profile then
        return {}
    end

    if not addon.db.profile.positionPresets then
        addon.db.profile.positionPresets = {}
    end

    return addon.db.profile.positionPresets
end

function PositionPresets:GetSortedNames()
    local names = {}
    for name in pairs(self:GetStore()) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function PositionPresets:UniqueName(baseName)
    local store = self:GetStore()
    if not store[baseName] then
        return baseName
    end

    local index = 2
    while store[baseName .. " (" .. index .. ")"] do
        index = index + 1
    end

    return baseName .. " (" .. index .. ")"
end

-- ============================================================================
-- FLUSH / SNAPSHOT / RESTORE
-- ============================================================================

local function ShouldFlushWidgetConfigPath(frameData)
    if not frameData.configPath or #frameData.configPath ~= 2 then
        return false
    end

    local section, key = frameData.configPath[1], frameData.configPath[2]
    local profile = addon.db and addon.db.profile

    if section == "additional" then
        return false
    end

    if section ~= "widgets" then
        return true
    end

    if key == "tot" or key == "fot" then
        local cfg = profile and profile.unitframe and profile.unitframe[key]
        return cfg and cfg.override
    end

    if key == "targetCastbar" then
        local cfg = profile and profile.castbar and profile.castbar.target
        return cfg and cfg.override
    end

    if key == "focusCastbar" then
        local cfg = profile and profile.castbar and profile.castbar.focus
        return cfg and cfg.override
    end

    return true
end

local function ShouldSnapshotWidgetKey(key, profile)
    if key == PANEL_WIDGET_KEY then
        return false
    end

    if key == "tot" or key == "fot" then
        local cfg = profile.unitframe and profile.unitframe[key]
        return cfg and cfg.override
    end

    if key == "targetCastbar" then
        local cfg = profile.castbar and profile.castbar.target
        return cfg and cfg.override
    end

    if key == "focusCastbar" then
        local cfg = profile.castbar and profile.castbar.focus
        return cfg and cfg.override
    end

    return true
end

local function ResetDetachedWidgetDefaults(profile, widgetKey)
    if not profile.widgets then
        return
    end

    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.widgets
    if defaults and defaults[widgetKey] then
        if addon.CopyTable then
            profile.widgets[widgetKey] = addon:CopyTable(defaults[widgetKey])
        else
            profile.widgets[widgetKey] = CopyTable(defaults[widgetKey])
        end
    else
        profile.widgets[widgetKey] = nil
    end
end

function PositionPresets:FlushEditorPositions()
    if addon.EditorMode and addon.EditorMode.FlushPositions then
        addon.EditorMode:FlushPositions()
    end

    for name, frameData in pairs(addon.EditableFrames or {}) do
        local frame = frameData.frame
        local isShown = frame and frame:IsShown()

        if isShown and frameData.onHide then
            pcall(frameData.onHide)
        end

        if isShown and frameData.configPath and ShouldFlushWidgetConfigPath(frameData) then
            if #frameData.configPath == 2 then
                addon.SaveUIFramePosition(frame, frameData.configPath[1], frameData.configPath[2])
            else
                addon.SaveUIFramePosition(frame, frameData.configPath[1])
            end
        elseif isShown and name == "questtracker" then
            SaveQuadrantSection(frame, "questtracker")
        elseif isShown and name == "lootroll" then
            SaveQuadrantSection(frame, "lootroll")
        end
    end
end

function PositionPresets:Snapshot()
    self:FlushEditorPositions()

    local profile = addon.db and addon.db.profile
    if not profile then
        return nil
    end

    local snapshot = {
        version = SNAPSHOT_VERSION,
        widgets = {},
        questtracker = PickFields(profile.questtracker, QUESTTRACKER_POSITION_KEYS),
        lootroll = PickFields(profile.lootroll, LOOTROLL_POSITION_KEYS),
        castbar = {},
        unitframe = {},
        additional = {},
    }

    if profile.widgets then
        for key, widgetCfg in pairs(profile.widgets) do
            if ShouldSnapshotWidgetKey(key, profile) then
                local picked = PickFields(widgetCfg, WIDGET_POSITION_KEYS)
                if picked then
                    snapshot.widgets[key] = picked
                end
            end
        end
    end

    if profile.castbar then
        local playerCast = PickFields(profile.castbar, CASTBAR_PLAYER_POSITION_KEYS)
        if playerCast then
            snapshot.castbar.player = playerCast
        end

        for _, key in ipairs({ "target", "focus" }) do
            local picked = PickFields(profile.castbar[key], CASTBAR_POSITION_KEYS)
            if picked then
                snapshot.castbar[key] = picked
            end
        end
    end

    if profile.unitframe then
        for _, key in ipairs({ "tot", "fot", "party" }) do
            local picked = PickFields(profile.unitframe[key], UNITFRAME_POSITION_KEYS)
            if picked then
                snapshot.unitframe[key] = picked
            end
        end
    end

    return snapshot
end

function PositionPresets:Restore(snapshot)
    local invalid = FindInvalidSetting(snapshot)
    if invalid then
        return false, invalid
    end

    local profile = addon.db and addon.db.profile
    if not profile then
        return false
    end

    if type(snapshot.questtracker) == "table" then
        profile.questtracker = profile.questtracker or {}
        MergeFields(profile.questtracker, snapshot.questtracker, QUESTTRACKER_POSITION_KEYS)
    end

    if type(snapshot.lootroll) == "table" then
        profile.lootroll = profile.lootroll or {}
        MergeFields(profile.lootroll, snapshot.lootroll, LOOTROLL_POSITION_KEYS)
    end

    if type(snapshot.castbar) == "table" then
        profile.castbar = profile.castbar or {}
        if type(snapshot.castbar.player) == "table" then
            MergeFields(profile.castbar, snapshot.castbar.player, CASTBAR_PLAYER_POSITION_KEYS)
        end
        for key, castCfg in pairs(snapshot.castbar) do
            if key ~= "player" then
                profile.castbar[key] = profile.castbar[key] or {}
                MergeFields(profile.castbar[key], castCfg, CASTBAR_POSITION_KEYS)
            end
        end
        if snapshot.castbar.target then
            if snapshot.castbar.target.override == true then
                profile.castbar.target.override = true
            else
                profile.castbar.target.override = false
                ResetDetachedWidgetDefaults(profile, "targetCastbar")
            end
        end
        if snapshot.castbar.focus then
            if snapshot.castbar.focus.override == true then
                profile.castbar.focus.override = true
            else
                profile.castbar.focus.override = false
                ResetDetachedWidgetDefaults(profile, "focusCastbar")
            end
        end
    end

    if type(snapshot.unitframe) == "table" then
        profile.unitframe = profile.unitframe or {}
        for key, unitCfg in pairs(snapshot.unitframe) do
            profile.unitframe[key] = profile.unitframe[key] or {}
            MergeFields(profile.unitframe[key], unitCfg, UNITFRAME_POSITION_KEYS)
            if key == "tot" or key == "fot" then
                if unitCfg.override == true then
                    profile.unitframe[key].override = true
                else
                    profile.unitframe[key].override = false
                    ResetDetachedWidgetDefaults(profile, key)
                end
            end
        end
    end

    if type(snapshot.widgets) == "table" then
        profile.widgets = profile.widgets or {}
        for key, widgetCfg in pairs(snapshot.widgets) do
            if ShouldSnapshotWidgetKey(key, profile) then
                profile.widgets[key] = profile.widgets[key] or {}
                MergeFields(profile.widgets[key], widgetCfg, WIDGET_POSITION_KEYS)
            end
        end
    end

    return true
end

local function ApplyEditableWidgetOverlays()
    if not addon.ApplyWidgetPositionFromDB then
        return
    end

    for name, frameData in pairs(addon.EditableFrames or {}) do
        if frameData.frame and ShouldFlushWidgetConfigPath(frameData) then
            local widgetKey = name
            if frameData.configPath and #frameData.configPath == 2 then
                widgetKey = frameData.configPath[2]
            end
            addon.ApplyWidgetPositionFromDB(widgetKey, frameData.frame)
        end
    end

    if addon.MinimapModule and addon.MinimapModule.lfgWrapper then
        addon.ApplyWidgetPositionFromDB("lfgframe", addon.MinimapModule.lfgWrapper)
    end
end

local function ClearEditorAttachFlags(frame)
    if not frame then
        return
    end

    frame.MistUI_WasDragged = nil
    frame.MistUI_WasAdjustedByEditor = nil
end

local function ApplySmallFrameAttachState(configKey, refreshFn)
    local frameData = addon.EditableFrames and addon.EditableFrames[configKey]
    local module = frameData and frameData.module
    if not module or not module.anchorFrame or not module.ApplyWidgetPosition then
        if refreshFn then
            refreshFn()
        end
        return
    end

    ClearEditorAttachFlags(module.anchorFrame)

    local profile = addon.db and addon.db.profile
    local unitCfg = profile and profile.unitframe and profile.unitframe[configKey]

    module:ApplyWidgetPosition()

    if unitCfg and unitCfg.override and module.UpdateWidgets then
        module:UpdateWidgets()
    elseif refreshFn then
        refreshFn()
    end
end

local function ApplyCastbarAttachStates()
    for _, frameName in ipairs({ "TargetCastbar", "FocusCastbar" }) do
        local frameData = addon.EditableFrames and addon.EditableFrames[frameName]
        ClearEditorAttachFlags(frameData and frameData.frame)
    end

    if addon.ApplyCastbarWidgetPositions then
        addon.ApplyCastbarWidgetPositions()
    end

    if addon.RefreshTargetCastbar then
        addon.RefreshTargetCastbar()
    end
    if addon.RefreshFocusCastbar then
        addon.RefreshFocusCastbar()
    end
end

local function ApplyDetachableAttachStates()
    ApplySmallFrameAttachState("tot", function()
        if addon.RefreshToTFrame then
            addon:RefreshToTFrame()
        end
    end)

    ApplySmallFrameAttachState("fot", function()
        if addon.RefreshToFFrame then
            addon:RefreshToFFrame()
        end
    end)

    ApplyCastbarAttachStates()
end

function PositionPresets:ApplyStoredPositions()
    addon._positionPresetApply = true
    local ok, err = pcall(function()
        ApplyDetachableAttachStates()

        if addon.ApplyActionBarPositions then
            addon.ApplyActionBarPositions()
        end

        if addon.RefreshCastbar then
            addon.RefreshCastbar()
        end

        ApplyEditableWidgetOverlays()

        ApplyDetachableAttachStates()

        if addon.UpdatePetbarPosition then
            addon.UpdatePetbarPosition()
        end
        if addon.UpdateStanceBarPosition then
            addon.UpdateStanceBarPosition()
        end
        if addon.UpdateVehicleExitPosition then
            addon.UpdateVehicleExitPosition()
        end

        if addon.RefreshQuestTracker then
            addon.RefreshQuestTracker()
        end

        if addon.RefreshLootRoll then
            addon.RefreshLootRoll()
        elseif addon.LootRollModule and addon.LootRollModule.ApplySystem then
            addon.LootRollModule:ApplySystem()
        end

        if addon.ApplyErrorMessagesPosition then
            addon.ApplyErrorMessagesPosition()
        end

        if addon.RefreshBuffFrame then
            addon:RefreshBuffFrame()
        end

        if addon.RefreshPartyFrames then
            addon:RefreshPartyFrames()
        end

        if addon.RefreshMinimap then
            addon:RefreshMinimap()
        end

        local MR = addon.ModuleRegistry
        if MR and MR.RefreshAll then
            MR:RefreshAll()
        end
    end)

    addon._positionPresetApply = nil

    if not ok then
        addon:Error("PositionPresets:ApplyStoredPositions failed", err)
        return false
    end

    return true
end

local function SyncAttachedSmallFrameOverlay(configKey)
    local frameData = addon.EditableFrames and addon.EditableFrames[configKey]
    if not frameData or not frameData.frame then
        return
    end

    local profile = addon.db and addon.db.profile
    local unitCfg = profile and profile.unitframe and profile.unitframe[configKey]
    if unitCfg and unitCfg.override then
        return
    end

    local mainFrame
    if configKey == "tot" and TargetFrameToT then
        mainFrame = TargetFrameToT
    elseif configKey == "fot" and FocusFrameToT then
        mainFrame = FocusFrameToT
    end

    if not mainFrame then
        return
    end

    local fx, fy = mainFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (fx and fy and ux and uy) then
        return
    end

    frameData.frame:ClearAllPoints()
    frameData.frame:SetPoint("CENTER", UIParent, "CENTER", fx - ux, fy - uy)
end

function PositionPresets:RefreshEditorOverlays()
    for _, frameData in pairs(addon.EditableFrames or {}) do
        if not frameData.frame or not frameData.frame:IsShown() then
            -- skip hidden overlays
        elseif frameData.editorVisible and not frameData.editorVisible() then
            -- skip disabled editor entries
        else
            if frameData.name == "tot" or frameData.name == "fot" then
                SyncAttachedSmallFrameOverlay(frameData.name)
            end

            if frameData.showTest then
                local ok, err = pcall(frameData.showTest)
                if not ok and addon.Debug then
                    addon:Debug("Position preset showTest failed:", frameData.name or "?", err)
                end
            end
        end
    end
end

function PositionPresets:Apply()
    if InCombatLockdown() then
        addon:Print(L["Cannot move frames during combat!"])
        return false
    end

    if not self:ApplyStoredPositions() then
        return false
    end

    if addon.EditorMode and addon.EditorMode:IsActive() then
        self:RefreshEditorOverlays()

        if addon.UpdateOverlaySizes then
            addon.UpdateOverlaySizes()
        end

        if addon.DeselectEditorFrame then
            addon.DeselectEditorFrame()
        end

        self:RefreshPanel()
    end

    return true
end

function PositionPresets:Save(name)
    if not name or name == "" then
        return false
    end

    name = strtrim(name):gsub("|", "")
    if name == "" then
        return false
    end

    local snapshot = self:Snapshot()
    if not snapshot then
        return false
    end

    local store = self:GetStore()
    store[name] = {
        data = snapshot,
        date = date("%Y-%m-%d %H:%M"),
    }
    self.currentName = name

    return true
end

function PositionPresets:Load(name)
    local store = self:GetStore()
    local entry = store[name]
    if not entry or not entry.data then
        return false
    end

    -- Checked before Restore writes the profile: in combat Apply refuses to move anything, which
    -- would leave saved positions that do not match the screen.
    if InCombatLockdown() then
        addon:Print(L["Cannot move frames during combat!"])
        return false
    end

    if not self:Restore(entry.data) then
        return false
    end

    local applied = self:Apply()
    if applied then
        self.currentName = name
        self:RefreshPanel()
    end
    return applied
end

function PositionPresets:Delete(name)
    local store = self:GetStore()
    if not store[name] then
        return false
    end

    store[name] = nil
    if self.currentName == name then
        self.currentName = nil
    end
    return true
end

function PositionPresets:ExportToString(name)
    local store = self:GetStore()
    local entry = store[name]
    if not entry or not entry.data then
        return nil
    end

    local serialized = Serializer:Serialize(entry.data)
    if not serialized then
        return nil
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil
    end

    return EXPORT_HEADER .. encoded
end

function PositionPresets:ImportFromString(str)
    if type(str) ~= "string" then
        return nil, "empty"
    end

    str = strtrim(str)
    if str == "" then
        return nil, "empty"
    end

    if str:sub(1, #EXPORT_HEADER) ~= EXPORT_HEADER then
        return nil, "header"
    end

    local payload = str:sub(#EXPORT_HEADER + 1)
    if payload == "" then
        return nil, "payload"
    end

    local decoded = LibDeflate:DecodeForPrint(payload)
    if not decoded then
        return nil, "decode"
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "decompress"
    end

    local ok, data = Serializer:Deserialize(decompressed)
    if not ok or type(data) ~= "table" or data.version ~= SNAPSHOT_VERSION then
        return nil, "deserialize"
    end

    local invalid = FindInvalidSetting(data)
    if invalid then
        return nil, "invalid", invalid
    end

    return data
end

-- ============================================================================
-- STATIC POPUPS (load / delete / import name only)
-- ============================================================================

StaticPopupDialogs["MISTUI_POSITION_PRESET_LOAD"] = {
    text = L["Load position preset '%s'? This will overwrite your current element positions."],
    button1 = L["Load"],
    button2 = L["Cancel"],
    OnAccept = function(self)
        local name = self.data
        if name and PositionPresets:Load(name) then
            addon:Print("|cFF00FF00[MistUI]|r " .. L["Position preset loaded: "] .. name)
            PositionPresets:RefreshPanel()
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["MISTUI_POSITION_PRESET_DELETE"] = {
    text = L["Delete position preset '%s'? This cannot be undone."],
    button1 = L["Delete"],
    button2 = L["Cancel"],
    OnAccept = function(self)
        local name = self.data
        if name and PositionPresets:Delete(name) then
            addon:Print("|cFF00FF00[MistUI]|r " .. L["Position preset deleted: "] .. name)
            PositionPresets:RefreshPanel()
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["MISTUI_POSITION_PRESET_IMPORT_NAME"] = {
    text = "",
    button1 = "",
    button2 = "",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        self.text:SetText(L["Enter a name for the imported position preset:"])
        self.button1:SetText(L["Save"])
        self.button2:SetText(L["Cancel"])

        local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
        if editBox then
            editBox:SetText(PositionPresets:UniqueName(L["Imported Position Preset"]))
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
        local name = editBox and editBox:GetText() and strtrim(editBox:GetText())
        if not name or name == "" then
            return
        end

        name = name:gsub("|", "")
        if name == "" then
            return
        end

        local importedData = self.data
        if type(importedData) ~= "table" then
            return
        end

        local store = PositionPresets:GetStore()
        store[name] = {
            data = CopyTable(importedData),
            date = date("%Y-%m-%d %H:%M"),
        }

        addon:Print("|cFF00FF00[MistUI]|r " .. L["Position preset imported: "] .. name)
        PositionPresets:RefreshPanel()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["MISTUI_POSITION_PRESET_IMPORT_NAME"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["MISTUI_POSITION_PRESET_SAVE_NAME"] = {
    text = L["Enter a name for the layout:"],
    button1 = L["Save"],
    button2 = L["Cancel"],
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
        if editBox then
            editBox:SetText(PositionPresets.currentName or PositionPresets:UniqueName(L["Position Preset"]))
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
        local name = editBox and strtrim(editBox:GetText() or "")
        if not name or name == "" then
            return
        end

        name = name:gsub("|", "")
        if name == "" then
            return
        end

        if PositionPresets:Save(name) then
            addon:Print("|cFF00FF00[MistUI]|r " .. L["Position preset saved: "] .. name)
            PositionPresets:RefreshPanel()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["MISTUI_POSITION_PRESET_SAVE_NAME"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

-- ============================================================================
-- IMPORT / EXPORT WINDOW
-- ============================================================================

local importExportFrame

local function GetImportExportFrame()
    if importExportFrame then
        return importExportFrame
    end

    local forever = addon.ForeverUI
    local ui = addon.EditorUI

    local frame = CreateFrame("Frame", "MistUI_PositionPresetImportExport", UIParent)
    frame:SetSize(508, 352)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata(ui.STRATA)
    frame:SetFrameLevel(ui.MODAL)
    forever.SkinDialog(frame, { closable = true, escClose = true })
    frame:Hide()

    local content = frame.Content
    local boxBack = CreateFrame("Frame", nil, frame)
    boxBack:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    boxBack:SetSize(432, 242)
    local boxFill = boxBack:CreateTexture(nil, "BACKGROUND")
    boxFill:SetAllPoints(boxBack)
    boxFill:SetTexture(0, 0, 0, 0.5)

    local ieScroll = CreateFrame("ScrollFrame", "MistUI_PositionPresetIEScroll", frame, "UIPanelScrollFrameTemplate")
    ieScroll:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    ieScroll:SetSize(424, 234)
    local ok, err = pcall(forever.SkinScrollBar, ieScroll)
    if not ok then
        geterrorhandler()(err)
    end

    local editBox = CreateFrame("EditBox", "MistUI_PositionPresetIEEditBox", ieScroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(424)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    ieScroll:SetScrollChild(editBox)
    frame.editBox = editBox

    frame.btn1 = forever.CreateButton(frame, "", 130, 28)
    frame.btn1:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 26, 24)

    frame.btn2 = forever.CreateButton(frame, L["Cancel"], 130, 28)
    frame.btn2:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 24)
    frame.btn2:SetScript("OnClick", function()
        frame:Hide()
    end)

    importExportFrame = frame
    return frame
end

local function ShowExportFrame(presetName, exportString)
    local frame = GetImportExportFrame()
    frame:SetTitle(L["Export Position Preset"])
    frame.editBox:SetText(exportString)
    frame.editBox:SetScript("OnTextChanged", function(self, userInput)
        -- Keep export payload read-only without risking recursive SetText loops.
        if userInput and self:GetText() ~= exportString then
            self:SetText(exportString)
            self:HighlightText()
        end
    end)
    frame.editBox:SetCursorPosition(0)
    frame.btn1:SetText(L["Select All"])
    frame.btn1:SetScript("OnClick", function()
        frame.editBox:SetFocus()
        frame.editBox:HighlightText()
    end)
    frame:Show()
    frame.editBox:SetFocus()
    frame.editBox:HighlightText()
end

local function ShowImportFrame()
    local frame = GetImportExportFrame()
    frame:SetTitle(L["Import Position Preset"])
    frame.editBox:SetText("")
    frame.editBox:SetScript("OnTextChanged", nil)
    frame.btn1:SetText(L["Import"])
    frame.btn1:SetScript("OnClick", function()
        local text = strtrim(frame.editBox:GetText())
        if text == "" then
            return
        end

        local data, errType, detail = PositionPresets:ImportFromString(text)
        if not data then
            local msg = L["Invalid position preset string."]
            if errType == "header" then
                msg = L["Not a valid MistUI position preset string."]
            elseif errType == "invalid" then
                msg = string.format(L["Layout not imported: it has a setting this version does not know or cannot use (%s)."], detail)
            end
            addon:Print("|cFFFF4444[MistUI]|r " .. msg)
            return
        end

        frame:Hide()
        local dialog = StaticPopup_Show("MISTUI_POSITION_PRESET_IMPORT_NAME")
        if dialog then
            dialog.data = data
        end
    end)
    frame:Show()
    frame.editBox:SetFocus()
end

-- ============================================================================
-- LAYOUT DROPDOWN (lives in the editor manager)
-- ============================================================================

local layoutDropdown

local function AskLoad(name)
    local dialog = StaticPopup_Show("MISTUI_POSITION_PRESET_LOAD", name)
    if dialog then
        dialog.data = name
    end
end

local function CurrentLayoutName()
    local current = PositionPresets.currentName
    if current and not PositionPresets:GetStore()[current] then
        PositionPresets.currentName = nil
        current = nil
    end
    return current
end

local function BuildLayoutEntries()
    local current = CurrentLayoutName()
    local names = PositionPresets:GetSortedNames()
    local entries = {}

    if #names == 0 then
        entries[1] = { text = L["No position presets saved yet."], disabled = true }
    else
        for _, name in ipairs(names) do
            entries[#entries + 1] = {
                text = name,
                checked = name == current,
                func = function() AskLoad(name) end,
            }
        end
    end

    entries[#entries + 1] = { isDivider = true }
    entries[#entries + 1] = {
        text = L["Save Layout"],
        func = function() StaticPopup_Show("MISTUI_POSITION_PRESET_SAVE_NAME") end,
    }
    entries[#entries + 1] = {
        text = L["Delete Layout"],
        disabled = not current,
        func = function()
            local dialog = StaticPopup_Show("MISTUI_POSITION_PRESET_DELETE", current)
            if dialog then
                dialog.data = current
            end
        end,
    }
    entries[#entries + 1] = {
        text = L["Export Layout"],
        disabled = not current,
        func = function()
            local exportString = PositionPresets:ExportToString(current)
            if exportString then
                ShowExportFrame(current, exportString)
            else
                addon:Print("|cFFFF4444[MistUI]|r " .. L["Failed to export position preset."])
            end
        end,
    }
    entries[#entries + 1] = { text = L["Import Layout"], func = ShowImportFrame }
    return entries
end

-- The stock dropdown menu cannot hold actions or dividers, so this swaps in a richer menu on the same anchor.
local function OpenLayoutMenu(button)
    if not (addon.Menu and addon.Menu.Open) then
        return
    end

    addon.Menu.Open(button, BuildLayoutEntries(), {
        large = true, style = "forever", at = "BOTTOMLEFT", x = -4, y = 0, minWidth = button:GetWidth(),
    })
    button:SetScript("OnUpdate", function(self)
        if not addon.Menu.IsOpenFor(self) then
            self:SetScript("OnUpdate", nil)
            self:Refresh()
        end
    end)
    button:Refresh()
end

function PositionPresets:CreateLayoutDropdown(parent, width)
    if layoutDropdown then
        return layoutDropdown
    end

    layoutDropdown = addon.ForeverUI.CreateDropdown(parent, {
        style = "wow1",
        width = width or 300,
        placeholder = L["Custom Layout"],
        get = CurrentLayoutName,
        builder = function()
            local items = {}
            for _, name in ipairs(PositionPresets:GetSortedNames()) do
                items[#items + 1] = { value = name, text = name }
            end
            return items
        end,
        set = AskLoad,
    })
    layoutDropdown.OpenMenu = OpenLayoutMenu
    return layoutDropdown
end

function PositionPresets:RefreshPanel()
    if layoutDropdown then
        layoutDropdown:Refresh()
    end
end

function PositionPresets:CloseDialogs()
    if importExportFrame then
        importExportFrame:Hide()
    end
    if addon.Menu then
        addon.Menu.Close()
    end
    for _, which in ipairs({ "LOAD", "DELETE", "SAVE_NAME", "IMPORT_NAME" }) do
        StaticPopup_Hide("MISTUI_POSITION_PRESET_" .. which)
    end
end

-- The old floating panel is gone; these keep external callers working against the editor manager.
local function GetEditorMode()
    return addon.EditorMode
end

function PositionPresets:CreatePanel()
    local mode = GetEditorMode()
    return mode and mode:GetManager()
end

function PositionPresets:ShowPanel()
    local mode = GetEditorMode()
    if mode and mode:IsActive() then
        mode:ShowManager()
    end
end

function PositionPresets:HidePanel()
    self:CloseDialogs()
    local mode = GetEditorMode()
    if mode then
        mode:HideManager()
    end
end

function PositionPresets:IsPanelShown()
    local mode = GetEditorMode()
    local manager = mode and mode:IsActive() and mode:GetManager()
    return manager and not not manager:IsShown() or false
end

function PositionPresets:ExpandMenu()
    if layoutDropdown and not (addon.Menu and addon.Menu.IsOpenFor(layoutDropdown)) then
        layoutDropdown:OpenMenu()
    end
end

function PositionPresets:CollapseMenu()
    if layoutDropdown and addon.Menu and addon.Menu.IsOpenFor(layoutDropdown) then
        addon.Menu.Close()
    end
end

function PositionPresets:ToggleMenu()
    if layoutDropdown then
        layoutDropdown:OpenMenu()
    end
end
