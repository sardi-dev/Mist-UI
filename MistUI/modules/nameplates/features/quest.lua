-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.
local addon = select(2, ...)
local NP = addon.Nameplates
local C = NP.const

-- Nameplates quest icons: mark a plate's mob as a kill/loot objective with our own
-- texture, found by a tooltip scan + quest-log crossref. Needs a token (target/mouseover/focus).

NP.quest = NP.quest or {}

local strmatch = string.match

-- Hidden scanner (never GameTooltip, so it can't fight the visible tooltip) and threat-line filter.
local QuestScanTip = CreateFrame("GameTooltip", "MistUINPQuestScan", UIParent, "GameTooltipTemplate")
QuestScanTip:SetOwner(UIParent, "ANCHOR_NONE")
-- Threat % line ("50% Threat") also parses as percent progress; filter it out.
local threatPattern = THREAT_TOOLTIP and THREAT_TOOLTIP:gsub("%%d", "%%d+")

local function IsThreatLine(text)
    return threatPattern ~= nil and strmatch(text, threatPattern) ~= nil
end

-- normalizedObjectiveText -> "loot" | "kill"
local objectiveTypeIndex = {}
local indexBuilt = false
-- Bumped on every quest log event; part of each plate's scan cache key.
local questLogVersion = 0
-- Engine tick of the last rebuild; coalesces QUEST_LOG_UPDATE bursts within a tick.
local lastBuildFrame = nil
-- Engine tick a quest change was seen; a deferred rebuild runs one tick later because the
-- first QUEST_LOG_UPDATE after accepting often carries an empty leaderboard.
local pendingRebuildFrame = nil

local SCAN_TTL = 0.7

-- Token-less: match plate name to objectives so stock clients get icons on every plate.
local killNameIndex = {}   -- normalizedMobName -> questID (kill objective)

-- Locale-safe capture of the mob name from a "monster" leaderboard line.
local killNamePattern
do
    local fmt = QUEST_MONSTERS_KILLED or "%s slain: %d/%d"
    fmt = fmt:gsub("%%s", "\001"):gsub("%%d", "\002")
    fmt = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    fmt = fmt:gsub("\001", "(.-)"):gsub("\002", "%%d+")
    killNamePattern = "^" .. fmt .. "$"
end

-- Persistent learned loot sources: [mobName] = {objectiveText=true}. nil until AceDB is ready.
local function GetLearnedDB()
    local db = addon.db
    if not (db and db.global) then return nil end
    db.global.questLootLearned = db.global.questLootLearned or {}
    return db.global.questLootLearned
end

local function QueueQuestRefresh()
    if NP.engine and NP.engine.QueueMass and NP.engine.Callbacks then
        NP.engine.QueueMass(NP.engine.Callbacks.OnUpdateQuest)
    end
end

local function NormalizeName(name)
    if not name then return nil end
    return name:gsub("^%s*(.-)%s*$", "%1"):lower()
end

-- Per-plate cache: the name-mode path runs every sync, so avoid re-normalizing a stable name.
local function NormalizedPlateName(plateData)
    local raw = plateData.plateName
    if plateData._questNormSrc ~= raw then
        plateData._questNormSrc = raw
        plateData._questNormName = NormalizeName(raw)
    end
    return plateData._questNormName
end

-- Token path taught us this mob is a loot source; persist it, keyed by normalized objective text.
local function LearnLootKey(mobKey, objText)
    local learned = GetLearnedDB()
    if not learned or not objText or not mobKey or mobKey == "" then return end
    local objs = learned[mobKey]
    if not objs then objs = {}; learned[mobKey] = objs end
    if not objs[objText] then
        objs[objText] = true
        QueueQuestRefresh()
    end
end

local function LearnLoot(plateData, objText)
    LearnLootKey(NormalizedPlateName(plateData), objText)
end

-- True if this mob is a learned loot source for a still-incomplete active objective.
local function LearnedLootActive(mobKey)
    local learned = GetLearnedDB()
    local objs = learned and learned[mobKey]
    if not objs then return false end
    for objText in pairs(objs) do
        if objectiveTypeIndex[objText] == "loot" then return true end
    end
    return false
end

-- Normalize tooltip lines and leaderboard text to one locale-agnostic key.
local function NormalizeObjectiveText(text)
    if not text then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%b[]", "")
    text = text:gsub("%b()", "")
    text = text:gsub("%d+%s*/%s*%d+", "")
    text = text:gsub("[%d%.]+%%", "")
    text = text:gsub("%p", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s*(.-)%s*$", "%1")
    return text:lower()
end

local function RebuildObjectiveIndex()
    wipe(objectiveTypeIndex)
    wipe(killNameIndex)
    local selection = GetQuestLogSelection()
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if not isHeader and not isComplete then
            SelectQuestLogEntry(i)
            local numObj = GetNumQuestLeaderBoards(i)
            for o = 1, numObj do
                local desc, objType, finished = GetQuestLogLeaderBoard(o, i)
                if desc and not finished then
                    local norm = NormalizeObjectiveText(desc)
                    if norm and norm ~= "" then
                        objectiveTypeIndex[norm] =
                            (objType == "item" or objType == "object") and "loot" or "kill"
                    end
                    if objType == "monster" then
                        local mobName = strmatch(desc, killNamePattern)
                        local key = NormalizeName(mobName)
                        if key and key ~= "" then
                            killNameIndex[key] = questID or true
                        end
                    end
                end
            end
        end
    end
    SelectQuestLogEntry(selection)
    indexBuilt = true
end

local function EnsureIndexBuilt()
    if not indexBuilt then
        RebuildObjectiveIndex()
    end
end

-- Returns hasObj, objType, tag; pointerMode skips the kill/loot crossref.
local function ScanUnitForQuest(unit, pointerMode)
    -- Show() populates the dynamic quest lines; same-frame Hide() = no visible flicker.
    QuestScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    QuestScanTip:ClearLines()
    QuestScanTip:SetUnit(unit)
    QuestScanTip:Show()
    local numLines = QuestScanTip:NumLines()

    local hasObj = false
    local foundKill, foundLoot = false, false
    local killKey, lootKey
    for i = 2, numLines do
        local fs = _G["MistUINPQuestScanTextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        if text and text ~= "" and not IsThreatLine(text) then
            local incomplete = false
            local done, total = strmatch(text, "(%d+)%s*/%s*(%d+)")
            if done and total then
                incomplete = tonumber(done) < tonumber(total)
            else
                local pct = tonumber(strmatch(text, "([%d%.]+)%%"))
                if pct then incomplete = pct < 100 end
            end
            if incomplete then
                if pointerMode then
                    hasObj = true
                    break
                end
                local norm = NormalizeObjectiveText(text) or ""
                local t = objectiveTypeIndex[norm]
                if t == "loot" then
                    foundLoot, lootKey = true, norm
                elseif t == "kill" then
                    foundKill, killKey = true, norm
                end
            end
        end
    end
    QuestScanTip:Hide()

    if not pointerMode then
        if foundLoot and not foundKill then
            return true, "loot", lootKey
        elseif foundKill or foundLoot then
            return true, "kill", killKey or lootKey
        end
        return false, nil, nil
    end
    return hasObj, nil, nil
end

-- Revalidate a token-less persisted icon; drop it once its objective/quest completes.
local function IsPersistValid(p)
    if p.ver == questLogVersion then return true end
    if p.pointer then return false end
    if not (p.tag and objectiveTypeIndex[p.tag]) then return false end
    p.ver = questLogVersion
    return true
end

local function QueryObjective(unit, pointerMode)
    if not pointerMode then
        EnsureIndexBuilt()
    end
    return ScanUnitForQuest(unit, pointerMode)
end

local function ResolveQuestForPlate(plateData, unit, pointerMode)
    local now = GetTime and GetTime() or 0
    local key = (plateData.plateName or "?") .. "|" .. questLogVersion .. "|" .. (pointerMode and "p" or "t")
    local cache = plateData._questScan
    if cache and cache.key == key and cache.at and now < cache.at + SCAN_TTL then
        return cache.hasObj, cache.objType, cache.tag
    end
    local hasObj, objType, tag = QueryObjective(unit, pointerMode)
    plateData._questScan = { key = key, at = now, hasObj = hasObj, objType = objType, tag = tag }
    return hasObj, objType, tag
end

-- Which texture shows for this objective, given the current config.
local function GetActiveIconKey(q, objType, isElite)
    if q.pointerMode then return "pointer" end
    if objType == "loot" then
        return (q.lootIcon == "chest") and "chest" or "bag"
    end
    if isElite and q.eliteKillIcon then return "elite" end
    return (q.killIcon == "skull") and "skull" or "sword"
end

local function EnsureQuestIcon(plateData)
    if plateData._questIcon then return plateData._questIcon end
    local parent = plateData.minaHp or plateData.visualRoot or plateData.plate
    if not parent then return nil end
    local icon = parent:CreateTexture(nil, "OVERLAY")
    icon:Hide()
    plateData._questIcon = icon
    return icon
end

local function HideQuestIcon(plateData)
    if not plateData then return end
    plateData._questElite = nil
    if plateData._questIcon then
        plateData._questIcon:Hide()
    end
end

-- Apply the given icon key's texture, per-icon size and per-icon x/y, then show.
local function ShowQuestIcon(plateData, q, key)
    local hp = plateData.minaHp
    if not hp or not key then HideQuestIcon(plateData); return end
    local icon = EnsureQuestIcon(plateData)
    if not icon then return end
    local ic = q.icons and q.icons[key]
    -- Signals the Elite widget to drop its dragon icon (avoids duplicate elite marks).
    plateData._questElite = (key == "elite")
    icon:SetTexture(C.QUEST_ICON_TEX[key])
    -- Shared texture: mirror the sword horizontally, reset the others.
    if key == "sword" then
        icon:SetTexCoord(1, 0, 0, 1)
    else
        icon:SetTexCoord(0, 1, 0, 1)
    end
    local size = (ic and ic.size) or 22
    icon:SetSize(size, size)
    if icon.SetParent then icon:SetParent(hp) end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", hp, "CENTER", (ic and ic.x) or 0, (ic and ic.y) or 20)
    icon:Show()
end

local function SyncQuestIcon(plateData, context)
    local q = NP.config.GetCfg().questIcons
    if not q or q.enabled ~= true then
        HideQuestIcon(plateData)
        return
    end

    -- Test preview: force one chosen icon on enemy/neutral plates for tuning.
    if q.testIcon and q.testIcon ~= "off" then
        local reaction = NP.native_style.GetPlateReaction(plateData)
        if reaction == "FRIENDLY" then
            HideQuestIcon(plateData)
            return
        end
        ShowQuestIcon(plateData, q, q.testIcon)
        return
    end

    local pointerMode = q.pointerMode == true
    local unit = context and context.resolvedUnit or NP.gather.ResolvePlateToken(plateData)

    local hasObj, objType
    -- Token first (most precise): resolve live and remember it.
    if unit and UnitExists(unit) and not UnitIsPlayer(unit) then
        local tag
        hasObj, objType, tag = ResolveQuestForPlate(plateData, unit, pointerMode)
        if hasObj then
            -- Learn loot sources from the tooltip scan so token-less plates can show them later.
            if objType == "loot" then
                LearnLoot(plateData, tag)
            end
            local p = plateData._questPersist or {}
            p.objType, p.tag, p.ver, p.pointer = objType, tag, questLogVersion, pointerMode
            plateData._questPersist = p
        end
    end
    -- Name fallback: the tooltip scan can miss (e.g. quest-tracking tooltip CVar off), so the
    -- addon-free kill index / learned loot still covers the plate even when it has a token.
    if not hasObj and q.nameResolution == true then
        local reaction, kind = NP.native_style.GetPlateReaction(plateData)
        if reaction ~= "FRIENDLY" and kind ~= "PLAYER" then
            local key = NormalizedPlateName(plateData)
            if key and key ~= "" then
                if killNameIndex[key] then
                    hasObj, objType = true, "kill"
                elseif LearnedLootActive(key) then
                    hasObj, objType = true, "loot"
                end
            end
        end
    end
    if not hasObj then
        -- Last resort: the persisted icon while its objective stays active.
        local p = plateData._questPersist
        if p and IsPersistValid(p) then
            hasObj, objType = true, p.objType
        else
            plateData._questPersist = nil
        end
    end

    if not hasObj then
        HideQuestIcon(plateData)
        return
    end
    local isElite = false
    if objType == "kill" and not pointerMode and q.eliteKillIcon then
        isElite = NP.native_style.ResolvePlateClassification(plateData, unit) ~= nil
    end
    ShowQuestIcon(plateData, q, GetActiveIconKey(q, objType, isElite))
end

NP.widgets.Register("Quest", {
    ShouldShow = function(plateData)
        local q = NP.config.GetCfg().questIcons
        return q ~= nil and q.enabled == true
    end,
    Ensure = function(plateData)
        return EnsureQuestIcon(plateData) ~= nil
    end,
    Sync = function(plateData, context)
        SyncQuestIcon(plateData, context)
    end,
    Hide = HideQuestIcon,
})

local function DoRebuildIndexes()
    RebuildObjectiveIndex()
    questLogVersion = questLogVersion + 1
end

-- Quest changed: rebuild indexes now (coalesced per tick), bump version, refresh.
function NP.quest.OnQuestLogChanged()
    local q = NP.config.GetCfg().questIcons
    if not q or q.enabled ~= true then return end
    local frame = NP.module and NP.module._engineFrame
    if frame == nil or lastBuildFrame ~= frame then
        lastBuildFrame = frame
        DoRebuildIndexes()
    end
    pendingRebuildFrame = frame or 0
    QueueQuestRefresh()
end

-- Engine tick hook: re-run the rebuild once the post-accept leaderboard has settled.
function NP.quest.TickDeferredRebuild(currentFrame)
    if pendingRebuildFrame == nil then return end
    if currentFrame and currentFrame > pendingRebuildFrame then
        pendingRebuildFrame = nil
        lastBuildFrame = currentFrame
        DoRebuildIndexes()
        QueueQuestRefresh()
    end
end

-- Gathering, opening and skinning are casts: loot right after one did not come from the dead target.
local lastPlayerCast = 0
local castWatcher = CreateFrame("Frame")
castWatcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castWatcher:SetScript("OnEvent", function(_, _, unit)
    if unit == "player" then lastPlayerCast = GetTime() end
end)

-- Loot fallback for the rare mob whose tooltip omits its loot objective; skips if token already taught it.
function NP.quest.OnLootOpened()
    local q = NP.config.GetCfg().questIcons
    if not q or q.enabled ~= true or q.nameResolution ~= true then return end
    if not next(objectiveTypeIndex) then return end
    if not (UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target")) then return end
    if IsFishingLoot() or not CheckInteractDistance("target", 3) then return end
    if GetTime() - lastPlayerCast < 2 then return end
    local mobKey = NormalizeName(UnitName("target"))
    if not mobKey or mobKey == "" then return end
    if LearnedLootActive(mobKey) then return end
    local learned = GetLearnedDB()
    if not learned then return end
    local numItems = GetNumLootItems and GetNumLootItems() or 0
    local changed = false
    for slot = 1, numItems do
        local _, itemName = GetLootSlotInfo(slot)
        local key = NormalizeObjectiveText(itemName)
        if key and objectiveTypeIndex[key] == "loot" then
            local objs = learned[mobKey]
            if not objs then objs = {}; learned[mobKey] = objs end
            if not objs[key] then
                objs[key] = true
                changed = true
            end
        end
    end
    if changed then QueueQuestRefresh() end
end

-- Fourth source: the mob-model mouseover token never resolves to a plate, so scan it directly.
-- Remembered with the quest log version: new objectives make the same mob worth a new scan.
local lastMouseoverScan, lastMouseoverVersion
function NP.quest.OnMouseover()
    local q = NP.config.GetCfg().questIcons
    if not q or q.enabled ~= true or q.nameResolution ~= true then return end
    if not next(objectiveTypeIndex) then return end
    if not (UnitExists("mouseover") and not UnitIsPlayer("mouseover")
        and UnitCanAttack("player", "mouseover")) then return end
    local guid = UnitGUID("mouseover")
    if guid == lastMouseoverScan and lastMouseoverVersion == questLogVersion then return end
    lastMouseoverScan, lastMouseoverVersion = guid, questLogVersion
    local mobKey = NormalizeName(UnitName("mouseover"))
    if not mobKey or mobKey == "" or LearnedLootActive(mobKey) then return end
    local hasObj, objType, tag = QueryObjective("mouseover", false)
    if hasObj and objType == "loot" and tag then
        LearnLootKey(mobKey, tag)
    end
end

function NP.quest.ClearIndex()
    wipe(objectiveTypeIndex)
    wipe(killNameIndex)
    indexBuilt = false
    lastBuildFrame = nil
    pendingRebuildFrame = nil
end
