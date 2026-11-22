-- Loads the addon into the fake game, plays a session and prints every error.
-- Usage: lua5.1 run.lua <manifest.lua>   (tools/harness.mjs writes the manifest)

local manifestPath = arg[1]
local harnessDir = arg[0]:match("^(.*)[/\\]") or "."
local manifest = dofile(manifestPath)

local H = dofile(harnessDir .. "/fake_client.lua")
H.stock = manifest.stock
H.clientNames = manifest.clientNames

-- Stock constants and strings, as the client has them before any addon loads.
for _, path in ipairs(manifest.stockLuaFiles) do
    local f, err = loadfile(path)
    if f then pcall(f) else io.stderr:write("stock file: " .. tostring(err) .. "\n") end
end
for k, v in pairs(manifest.stock.constants) do
    if rawget(_G, k) == nil then rawset(_G, k, v) end
end
dofile(harnessDir .. "/fake_api.lua")
local units = H.units

-- Names the client program knows but the fake does not model answer nil when called.
local fallback = getmetatable(_G).__index
setmetatable(_G, { __index = function(t, k)
    local v = fallback(t, k)
    if v ~= nil then return v end
    if type(k) == "string" and H.clientNames[k] then
        H.unknownGlobals[k] = (H.unknownGlobals[k] or 0) + 1
        local s = H.Stub(k)
        rawset(t, k, s)
        return s
    end
    return nil
end })

UIParent = H.NewObject("Frame", "UIParent")
UIParent.__width, UIParent.__height = 1365, 768
WorldFrame = H.NewObject("Frame", "WorldFrame")
SlashCmdList = SlashCmdList or {}
StaticPopupDialogs = StaticPopupDialogs or {}
UISpecialFrames = UISpecialFrames or {}

-- ---------------------------------------------------------------------------
-- Events, time and addon loading
-- ---------------------------------------------------------------------------

function H.Fire(event, ...)
    local set = H.eventFrames[event]
    if not set then return end
    local frames = {}
    for f in pairs(set) do frames[#frames + 1] = f end
    for _, f in ipairs(frames) do
        local s = f.__scripts.OnEvent
        if s then H.Call(event .. " on " .. (f.__name or f.__type), s, f, event, ...) end
    end
end

function H.Tick(seconds, step)
    step = step or 0.1
    local t = 0
    while t < seconds do
        H.now = H.now + step
        t = t + step
        local list = {}
        for f in pairs(H.updateFrames) do list[#list + 1] = f end
        for _, f in ipairs(list) do
            local s = f.__scripts.OnUpdate
            if s and f:IsVisible() then H.Call("OnUpdate of " .. (f.__name or f.__type), s, f, step) end
        end
        local anims = {}
        for g in pairs(H.animations) do anims[#anims + 1] = g end
        for _, g in ipairs(anims) do
            local duration = 0
            for _, a in ipairs(g.__anims or {}) do duration = math.max(duration, a.__duration or 0) end
            if g.__playing and H.now - g.__started >= duration then
                local looping = g.__looping == "REPEAT" or g.__looping == "BOUNCE"
                if looping then g.__started = H.now else g:Stop() end
                for _, a in ipairs(g.__anims or {}) do H.FireScript(a, "OnFinished") end
                H.FireScript(g, looping and "OnLoop" or "OnFinished")
            end
        end
    end
end

-- The client skips a UTF-8 byte order mark at the start of a file; plain Lua does not.
local function LoadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil, "cannot open " .. path end
    local text = handle:read("*a")
    handle:close()
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
    return loadstring(text, "@" .. path)
end

local loaded = {}
local function LoadAddon(addon)
    if loaded[addon.name] then return end
    loaded[addon.name] = true
    local ns = {}
    H.namespaces = H.namespaces or {}
    H.namespaces[addon.name] = ns
    for _, path in ipairs(addon.files) do
        local f, err = LoadFile(path)
        if not f then
            H.Report("syntax", err)
        else
            H.Call(path, f, addon.name, ns)
        end
    end
    if addon.saved then
        local f = LoadFile(addon.saved)
        if f then H.Call("saved variables", f) end
    end
    H.Fire("ADDON_LOADED", addon.name)
end

local byName = {}
for _, a in ipairs(manifest.addons) do byName[a.name] = a end
LoadAddOn = function(name)
    local a = byName[name]
    if not a then return nil, "MISSING" end
    local phase = H.currentPhase
    H.currentPhase = "load " .. name
    LoadAddon(a)
    H.currentPhase = phase
    return 1
end
IsAddOnLoaded = function(name) return loaded[name] and 1 or nil end

local function Slash(command)
    local verb, rest = command:match("^(/%S+)%s*(.*)$")
    for key, handler in pairs(SlashCmdList) do
        for i = 1, 9 do
            local alias = rawget(_G, "SLASH_" .. key .. i)
            if alias and alias:lower() == verb:lower() then
                H.Call("slash " .. command, handler, rest)
                return
            end
        end
    end
    H.Report("slash", "no handler for " .. command)
end

-- ---------------------------------------------------------------------------
-- The session
-- ---------------------------------------------------------------------------

local function Phase(name, fn)
    H.currentPhase = name
    H.Call(name, fn)
end

Phase("load", function()
    for _, a in ipairs(manifest.addons) do
        if not a.loadOnDemand then LoadAddon(a) end
    end
end)

Phase("login", function()
    H.loggedIn = true
    H.Fire("PLAYER_LOGIN")
    H.Fire("PLAYER_ENTERING_WORLD", true, false)
    H.Fire("UPDATE_BINDINGS")
    H.Fire("PLAYER_TALENT_UPDATE")
    H.Tick(3)
end)

Phase("bags", function()
    H.Fire("BAG_UPDATE", 0)
    H.Fire("BAG_UPDATE", 1)
    H.Fire("BAG_UPDATE_DELAYED")
    H.Tick(1)
    if ToggleAllBags then ToggleAllBags() end
    H.Tick(1)
    if ToggleBackpack then ToggleBackpack() end
    if OpenAllBags then OpenAllBags() end
    H.Fire("ITEM_LOCK_CHANGED", 0, 1)
    H.Fire("BAG_UPDATE_COOLDOWN")
    H.Fire("BANKFRAME_OPENED")
    H.Tick(1)
    H.Fire("PLAYERBANKSLOTS_CHANGED", 1)
    H.Fire("BANKFRAME_CLOSED")
    if CloseAllBags then CloseAllBags() end
    H.Tick(1)
end)

Phase("combat", function()
    units.target = { name = "Training Dummy", class = "Warrior", token = "WARRIOR", classId = 1, level = 92,
        guid = "0xF1307A1800001234", health = 1000, healthMax = 1000, power = 0, powerMax = 0, powerType = 1,
        powerToken = "RAGE" }
    H.Fire("PLAYER_TARGET_CHANGED")
    H.Fire("UNIT_TARGET", "player")
    H.Fire("UNIT_HEALTH", "target")
    H.Fire("UNIT_AURA", "target")
    H.inCombat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    H.Fire("ACTIONBAR_UPDATE_COOLDOWN")
    H.Fire("SPELL_UPDATE_COOLDOWN")
    H.Fire("COMBAT_LOG_EVENT_UNFILTERED", H.now, "SPELL_CAST_START", false, "0xF1307A1800001234",
        "Training Dummy", 0xa48, 0, "", nil, 0x80000000, 0, 133, "Fireball", 4)
    H.Fire("UNIT_SPELLCAST_START", "target", "Fireball", "", 1, 133)
    -- Stance and pet cooldowns go through SetCooldown, as the stock bars start them. The bars are
    -- shown first: a hidden frame does not tick, so its countdown would never be painted.
    for _, name in ipairs({ "StanceButton1Cooldown", "PetActionButton1Cooldown" }) do
        local cd = _G[name]
        if cd then
            local o = cd
            while o do o.__shown = true; o = o.__parent end
            cd:SetCooldown(H.now, 10)
            H.Tick(0.5)
            local label = rawget(cd, "text")
            if not (label and label:IsShown() and label:GetText()) then
                H.Report("cooldowns", name .. ": no countdown text after a 10 second cooldown")
            end
        end
    end
    H.Tick(2)
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    units.target = nil
    H.Fire("PLAYER_TARGET_CHANGED")
    H.Tick(1)
end)

local function Unit(name, guid, level, classification)
    return { name = name, class = "Warrior", token = "WARRIOR", classId = 1, level = level, guid = guid,
        health = 900, healthMax = 1000, power = 50, powerMax = 100, powerType = 1, powerToken = "RAGE",
        classification = classification }
end

-- What the owner has never tested in the game: a group, a boss, a vehicle, a pet, stances.
Phase("group", function()
    units.party1 = Unit("Botfriend", "0x0000000000000002", 90)
    H.state.group = true
    H.Fire("GROUP_ROSTER_UPDATE")
    H.Fire("PARTY_LEADER_CHANGED")
    H.Fire("UNIT_HEALTH", "party1")
    H.Fire("UNIT_POWER", "party1", "RAGE")
    H.Fire("UNIT_AURA", "party1")
    H.Fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
    H.Tick(1)
    units.party1 = nil
    H.state.group = false
    H.Fire("GROUP_ROSTER_UPDATE")
    H.Tick(1)
end)

Phase("boss", function()
    units.boss1 = Unit("Hogger", "0xF130001C4E000001", -1, "worldboss")
    H.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    H.Fire("UNIT_HEALTH", "boss1")
    H.Fire("UNIT_TARGETABLE_CHANGED", "boss1")
    H.Tick(1)
    units.boss1 = nil
    H.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    H.Tick(1)
end)

Phase("vehicle", function()
    units.vehicle = Unit("Siege Tank", "0xF150000000000001", 90)
    H.state.vehicle = true
    H.Fire("UNIT_ENTERING_VEHICLE", "player", true, false, "Natural", "", 1, false)
    H.Fire("UNIT_ENTERED_VEHICLE", "player", true, false, "Natural", "", 1, false)
    H.Fire("UPDATE_VEHICLE_ACTIONBAR")
    H.Fire("VEHICLE_UPDATE")
    H.Fire("UPDATE_BONUS_ACTIONBAR")
    H.Fire("ACTIONBAR_PAGE_CHANGED")
    -- The stock controller skins and sets up the override bar, in combat as vehicles often are;
    -- the fake runs no stock code, so the two calls the module hooks are made here.
    H.inCombat = true
    OverrideActionBar_SetSkin("Interface\\Vehicles\\UI-Vehicle-Frame")
    OverrideActionBar_Setup("Interface\\Vehicles\\UI-Vehicle-Frame", 12)
    OverrideActionBar:Show()
    H.Tick(1)
    local art = rawget(_G, "MistUI_OverrideBarArt")
    if not art then
        H.Report("vehicle", "the override bar art was not built at login")
    elseif OverrideActionBar._BG and OverrideActionBar._BG:GetAlpha() ~= 0 then
        H.Report("vehicle", "the override bar skin is still visible after a re-skin")
    end
    OverrideActionBar:Hide()
    H.inCombat = false
    H.Tick(1)
    H.state.vehicle = false
    units.vehicle = nil
    H.Fire("UNIT_EXITING_VEHICLE", "player")
    H.Fire("UNIT_EXITED_VEHICLE", "player")
    H.Fire("UPDATE_VEHICLE_ACTIONBAR")
    H.Tick(1)
end)

-- A paladin: the class bar goes under the mana bar, then is moved in edit mode and reset.
Phase("class power", function()
    local CP = H.namespaces.MistUI.ClassPower
    if not CP then
        H.Report("class power", "the class power file did not load")
        return
    end
    local player = units.player
    local token, class = player.token, player.class
    player.token, player.class = "PALADIN", "Paladin"
    CP.Apply()
    local bar = PaladinPowerBar
    local _, relative = bar:GetPoint(1)
    if relative ~= PlayerFrameManaBar then
        H.Report("class power", "the holy power bar is not anchored to the mana bar")
    end
    CP.Detach()
    CP.Place()
    CP.SyncBox()
    player.token, player.class = token, class
    H.Tick(0.5)
end)

-- A mistweaver monk: the small bars follow the mana bar, also after the stock code re-anchors them.
Phase("small class bars", function()
    local CP = H.namespaces.MistUI.ClassPower
    if not CP then return end
    local player = units.player
    local token, class, getSpec = player.token, player.class, GetSpecialization
    player.token, player.class = "MONK", "Monk"
    GetSpecialization = function() return SPEC_MONK_MISTWEAVER end
    CP.Apply()
    for _, bar in ipairs({ PlayerFrameAlternateManaBar, MonkStaggerBar }) do
        -- What AlternatePowerBar_SetLook does: a second point without clearing the first.
        bar:SetPoint("BOTTOMLEFT", PlayerFrame, "BOTTOMLEFT", 118, 4)
        AlternatePowerBar_SetLook(bar)
        local _, relative = bar:GetPoint(1)
        if bar:GetNumPoints() ~= 1 or relative ~= PlayerFrameManaBar then
            H.Report("small class bars", bar:GetName() .. " is not anchored to the mana bar alone")
        end
    end
    player.token, player.class, GetSpecialization = token, class, getSpec
    H.Tick(0.5)
end)

Phase("pet and stances", function()
    units.pet = Unit("Bear", "0xF140000000000001", 90)
    H.state.pet = true
    H.Fire("UNIT_PET", "player")
    H.Fire("PET_BAR_UPDATE")
    H.Fire("PET_UI_UPDATE")
    H.Fire("PET_BAR_UPDATE_COOLDOWN")
    H.Fire("UNIT_HEALTH", "pet")
    H.Tick(1)
    H.state.forms = 3
    H.Fire("UPDATE_SHAPESHIFT_FORMS")
    H.Fire("UPDATE_SHAPESHIFT_FORM")
    H.Fire("UPDATE_SHAPESHIFT_COOLDOWN")
    H.Tick(1)
    H.state.pet = false
    units.pet = nil
    H.Fire("UNIT_PET", "player")
    H.Fire("PET_BAR_UPDATE")
    H.Tick(1)
end)

Phase("bank with bags", function()
    H.state.bankBags = 2
    H.Fire("BANKFRAME_OPENED")
    H.Tick(1)
    H.Fire("PLAYERBANKBAGSLOTS_CHANGED")
    H.Fire("BAG_UPDATE", 5)
    H.Fire("PLAYERBANKSLOTS_CHANGED", 3)
    H.Tick(1)
    H.Fire("BANKFRAME_CLOSED")
    H.Tick(1)
end)

Phase("bag currency strip", function()
    local mod = H.namespaces.MistUI.BagsterModule
    if not (mod and mod.TokenBar) then
        H.Report("bag currency strip", "the currency strip class is not there")
        return
    end
    local VALOR_ICON = "Interface\\Icons\\pvecurrency-valor"
    local savedInfo = GetBackpackCurrencyInfo
    -- The 5.4.8 return order: name, count, icon, currency id
    GetBackpackCurrencyInfo = function(index)
        if index == 1 then return "Valor Points", 1200, VALOR_ICON, 396 end
    end
    local bar = mod.TokenBar:New(UIParent)
    bar:Refresh()
    local button = bar.tokenButtons[1]
    if not button then
        H.Report("bag currency strip", "no button for a watched currency")
    else
        if button.icon:GetTexture() ~= VALOR_ICON then
            H.Report("bag currency strip", "currency icon is " .. tostring(button.icon:GetTexture()))
        end
        local shownIndex
        local savedSetter = GameTooltip.SetBackpackToken
        GameTooltip.SetBackpackToken = function(_, index) shownIndex = index end
        H.FireScript(button, "OnEnter")
        H.FireScript(button, "OnLeave")
        GameTooltip.SetBackpackToken = savedSetter
        if shownIndex ~= 1 then
            H.Report("bag currency strip", "tooltip did not show watched currency 1, got " .. tostring(shownIndex))
        end
    end
    GetBackpackCurrencyInfo = savedInfo
end)

Phase("guild bank", function()
    H.state.guildTabs = 2
    H.Fire("PLAYER_GUILD_UPDATE")
    H.Fire("GUILDBANKFRAME_OPENED")
    H.Fire("GUILDBANK_UPDATE_TABS")
    H.Fire("GUILDBANKBAGSLOTS_CHANGED")
    H.Fire("GUILDBANK_ITEM_LOCK_CHANGED")
    H.Fire("GUILDBANK_UPDATE_MONEY")
    H.Tick(1)
    local mod = H.namespaces.MistUI.BagsterModule
    local guild = mod and mod.guildFrame
    if not (guild and guild:IsShown()) then
        H.Report("guild bank", "the guild bank window did not open")
    else
        for _, mode in ipairs({ "log", "moneylog", "info", "bank" }) do
            guild:SetMode(mode)
            H.Fire("GUILDBANKLOG_UPDATE")
            H.Fire("GUILDBANK_UPDATE_TEXT")
        end
        guild:ShowTabEditPopup(1)
        H.Tick(0.5)
    end
    H.Fire("GUILDBANKFRAME_CLOSED")
    H.Tick(1)
end)

-- A plate as the 5.4.8 client builds it (layout from a public 5.4.8 addon; /mist plates confirms it).
local function MakePlate(index, unitName, level, r, g, b)
    local plate = CreateFrame("Frame", "NamePlate" .. index, WorldFrame)
    plate:SetSize(156, 39)
    local barFrame = CreateFrame("Frame", nil, plate)
    local nameFrame = CreateFrame("Frame", nil, plate)
    local health = CreateFrame("StatusBar", nil, barFrame)
    health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    health:SetMinMaxValues(0, 100)
    health:SetValue(80)
    health:SetStatusBarColor(r, g, b)
    local cast = CreateFrame("StatusBar", nil, barFrame)
    cast:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    cast:CreateTexture():SetTexture("Interface\\Tooltips\\Nameplate-CastBar")
    cast:CreateTexture():SetTexture("Interface\\Tooltips\\Nameplate-CastBar-Shield")
    cast:CreateTexture()
    cast:CreateFontString()
    cast:CreateTexture()
    cast:Hide()
    barFrame:CreateTexture():SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Flash")
    barFrame:CreateTexture():SetTexture("Interface\\Tooltips\\Nameplate-Border")
    barFrame:CreateTexture():SetTexture("Interface\\Tooltips\\Nameplate-Glow")
    local levelText = barFrame:CreateFontString()
    levelText:SetText(tostring(level))
    barFrame:CreateTexture():SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    barFrame:CreateTexture():SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    barFrame:CreateTexture():SetTexture("Interface\\Tooltips\\EliteNameplateIcon")
    local nameText = nameFrame:CreateFontString()
    nameText:SetText(unitName)
    return plate, cast
end

do
    Phase("plates", function()
        SetCVar("nameplateShowEnemies", "1")
        local plate1, cast1 = MakePlate(1, "Training Dummy", 92, 1, 0, 0)
        local plate2 = MakePlate(2, "Kobold Vermin", 1, 1, 1, 0)
        local plate3 = MakePlate(3, "Stormwind Guard", 90, 0, 1, 0)
        H.Tick(2)
        -- The run only proves something if the module found the plates and drew its own bars.
        local NP = H.namespaces.MistUI.Nameplates
        local found, styled = 0, 0
        for _, data in pairs(NP and NP.module and NP.module.plates or {}) do
            found = found + 1
            if data.minaHp then styled = styled + 1 end
        end
        print(("Plates found by the module: %d, styled: %d (3 on screen)"):format(found, styled))
        if found ~= 3 or styled ~= 3 then
            H.Report("plates", ("expected 3 plates found and styled, got %d and %d"):format(found, styled))
        end
        -- Stacking: two overlapping plates move apart, one far to the side stays where it is.
        local cfg = NP.config.GetCfg()
        local stackingBefore = cfg.retailStackingEnabled
        cfg.retailStackingEnabled = true
        plate1:ClearAllPoints(); plate1:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", 100, 200)
        plate2:ClearAllPoints(); plate2:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", 120, 205)
        plate3:ClearAllPoints(); plate3:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", 900, 200)
        H.Tick(1)
        local raised, farRaised = 0, nil
        for _, data in pairs(NP.module.plates) do
            local state = NP.module._retailStackData and NP.module._retailStackData[data]
            local position = state and state.position or 0
            if data.plate == plate3 then farRaised = position > 0
            elseif position > 0 then raised = raised + 1 end
        end
        if raised ~= 1 then H.Report("plates", "stacking raised " .. raised .. " of the two overlapping plates, not 1") end
        if farRaised then H.Report("plates", "stacking moved a plate with no neighbour") end
        cfg.retailStackingEnabled = stackingBefore
        H.Tick(0.2)
        units.target = { name = "Training Dummy", class = "Warrior", token = "WARRIOR", classId = 1, level = 92,
            guid = "0xF1307A1800001234", health = 800, healthMax = 1000, power = 0, powerMax = 0, powerType = 1,
            powerToken = "RAGE" }
        plate2.__alpha, plate3.__alpha = 0.5, 0.5
        H.Fire("PLAYER_TARGET_CHANGED")
        H.Fire("UNIT_HEALTH", "target")
        H.Fire("UNIT_AURA", "target")
        H.Tick(1)
        -- The dummy starts a cast: the combat log, the unit event and the plate's own bar.
        H.Fire("COMBAT_LOG_EVENT_UNFILTERED", H.now, "SPELL_CAST_START", false, "0xF1307A1800001234",
            "Training Dummy", 0xa48, 0, "", nil, 0x80000000, 0, 133, "Fireball", 4)
        H.Fire("UNIT_SPELLCAST_START", "target", "Fireball", "", 1, 133)
        cast1:SetMinMaxValues(0, 2.5)
        cast1:Show()
        cast1:SetValue(0.5)
        H.Tick(1)
        cast1:SetValue(1.5)
        H.Fire("COMBAT_LOG_EVENT_UNFILTERED", H.now, "SPELL_AURA_APPLIED", false, units.player.guid, "Tester",
            0x511, 0, "0xF1307A1800001234", "Training Dummy", 0xa48, 0, 772, "Rend", 1, "DEBUFF")
        H.Fire("COMBAT_LOG_EVENT_UNFILTERED", H.now, "SPELL_INTERRUPT", false, units.player.guid, "Tester",
            0x511, 0, "0xF1307A1800001234", "Training Dummy", 0xa48, 0, 6552, "Pummel", 1, 133, "Fireball", 4)
        cast1:Hide()
        H.Tick(1)
        -- The client recycles a plate for another unit.
        plate2:Hide()
        H.Tick(0.5)
        plate2:Show()
        H.Tick(1)
        H.Fire("COMBAT_LOG_EVENT_UNFILTERED", H.now, "UNIT_DIED", false, "", nil, 0, 0, "0xF1307A1800001234",
            "Training Dummy", 0xa48, 0)
        units.target = nil
        H.Fire("PLAYER_TARGET_CHANGED")
        plate1:Hide()
        H.Tick(2)
        -- The off switch restores the stock plates; on again restyles them.
        Slash("/mist nameplates off")
        H.Tick(1)
        Slash("/mist nameplates on")
        H.Tick(1)
    end)
end

-- The world map: the stock code is not run, so its quest pass is played by hand (rows, pins,
-- selection) before the hooks the module put on it fire; then every control of the new window.
Phase("worldmap", function()
    local NS = H.namespaces.MistUI
    local WM = NS.WorldMap
    if not (WM and WM.border) then
        H.Report("worldmap", "the map window was not built at login")
        return
    end
    WatchFrame.showObjectives = true
    SetCVar("questPOI", "1")
    local function questPass()
        local rows = {}
        for i, q in ipairs({ { id = 783, log = 2 }, { id = 54, log = 3, done = true } }) do
            local row = rawget(_G, "WorldMapQuestFrame" .. i) or CreateFrame("Frame", "WorldMapQuestFrame" .. i)
            row.index, row.questId, row.questLogIndex, row.completed, row.level = i, q.id, q.log, q.done, 1
            local kind = q.done and QUEST_POI_COMPLETE_SWAP or QUEST_POI_NUMERIC
            local name = "poiWorldMapPOIFrame" .. kind .. "_1"
            local poi = rawget(_G, name) or CreateFrame("Button", name, WorldMapPOIFrame,
                q.done and "QuestPOICompletedTemplate" or "QuestPOITemplate")
            poi.index, poi.type, poi.questId, poi.quest = 1, kind, q.id, row
            poi:SetPoint("CENTER", WorldMapPOIFrame, "TOPLEFT", 100 * i, -80 * i)
            row.poiIcon = poi
            rows[i] = row
        end
        WorldMapFrame.numQuests = #rows
        WorldMapFrame_UpdateQuests()
        for _, row in ipairs(rows) do WorldMapFrame_DisplayQuestPOI(row, row.completed) end
        WorldMapFrame_SelectQuestFrame(rows[1])
        WorldMapFrame_DisplayQuests()
        WorldMapFrame_Update()
        return rows
    end
    WorldMapFrame:Show()
    H.Fire("WORLD_MAP_UPDATE")
    local rows = questPass()
    H.Tick(0.5)
    -- The breadcrumb, then the quest panel: a row opens the details, Back returns.
    local bar = WM.navBar
    for _, crumb in ipairs(bar and bar.crumbs or {}) do
        if crumb:IsShown() then crumb:Click() end
        if crumb.arrow and crumb.arrow:IsShown() then crumb.arrow:Click() end
        NS.Menu.Close()
    end
    questPass()
    H.Tick(0.2)
    local list = rawget(_G, "MistUIWorldMapQuestList")
    local child = list and list:GetScrollChild()
    local clicked = 0
    local children = {}
    if child then children = { child:GetChildren() } end
    for _, row in ipairs(children) do
        if row:IsShown() and row.badge then
            row:GetScript("OnEnter")(row)
            row.badge:Click()
            row:GetScript("OnLeave")(row)
            row:Click("RightButton")
            row:Click("LeftButton")
            clicked = clicked + 1
            H.Tick(0.2)
            local detail = rawget(_G, "MistUIWorldMapQuestDetail")
            if not (detail and detail:IsShown()) then H.Report("worldmap", "a quest row did not open its details") end
            WM.HideQuestDetail()
        end
    end
    print(("Quest rows in the map panel: %d"):format(clicked))
    if clicked ~= 2 then H.Report("worldmap", ("expected 2 quest rows, got %d"):format(clicked)) end
    local search = rawget(_G, "MistUIWorldMapQuestSearch")
    if search then
        search:SetText("threat")
        H.FireScript(search, "OnTextChanged")
        H.Tick(0.2)
        search:SetText("")
        H.FireScript(search, "OnTextChanged")
    end
    -- Filter menu, panel settings, maximize, the panel toggle, zoom and pan, and the size toggles.
    rawget(_G, "MistUIWorldMapFilterButton"):Click()
    NS.Menu.Close()
    rawget(_G, "MistUIWorldMapQuestSettings"):Click()
    NS.Menu.Close()
    rawget(_G, "MistUIWorldMapMaximizeButton"):Click()
    H.Tick(0.2)
    rawget(_G, "MistUIWorldMapMaximizeButton"):Click()
    rawget(_G, "MistUIWorldMapQuestLogToggle"):Click()
    H.Tick(0.2)
    rawget(_G, "MistUIWorldMapQuestLogToggle"):Click()
    local wheel = WorldMapButton:GetScript("OnMouseWheel")
    if wheel then
        wheel(WorldMapButton, 1)
        wheel(WorldMapButton, 1)
        H.Tick(0.5)
        H.FireScript(WorldMapButton, "OnMouseDown", "LeftButton")
        H.Tick(0.3)
        H.FireScript(WorldMapButton, "OnMouseUp", "LeftButton")
        -- Combat drops the zoom; the layout waits for the end of combat.
        H.inCombat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        rawget(_G, "MistUIWorldMapQuestLogToggle"):Click()
        H.Tick(0.5)
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        rawget(_G, "MistUIWorldMapQuestLogToggle"):Click()
        H.Tick(0.2)
    end
    WORLDMAP_SETTINGS.size = WORLDMAP_QUESTLIST_SIZE
    WorldMap_ToggleSizeUp()
    questPass()
    H.Tick(0.3)
    WORLDMAP_SETTINGS.size = WORLDMAP_WINDOWED_SIZE
    WorldMap_ToggleSizeDown()
    questPass()
    H.Tick(0.3)
    if not WM.border:IsShown() then H.Report("worldmap", "the window chrome did not come back in windowed mode") end
    WorldMapFrame:Hide()
    H.Tick(9)
end)

Phase("commands", function()
    for _, c in ipairs({ "/mist help", "/mist status", "/mist errors", "/mist cd", "/mist mouse", "/mist plates",
        "/mist edit", "/mist edit", "/mist" }) do
        Slash(c)
        H.Tick(0.5)
    end
    -- /mist perf: first with the client's timing off (only a hint), then a full measurement.
    Slash("/mist perf")
    -- The plate engine's frame is given the most time: the report must reach it and rank it first.
    local NP = H.namespaces.MistUI.Nameplates
    local engineFrame = NP and NP.module and NP.module.scannerFrame
    GetFrameCPUUsage = function(frame) return frame == engineFrame and 50 or 1.5 end
    GetFunctionCPUUsage = function() return 2.5 end
    GetAddOnCPUUsage = function() return 40 end
    GetEventCPUUsage = function() return 3, 12 end
    ResetCPUUsage, UpdateAddOnCPUUsage = function() end, function() end
    SetCVar("scriptProfile", "1")
    Slash("/mist perf")
    H.Tick(16)
    SetCVar("scriptProfile", "0")
    local report = MistUIDB and MistUIDB.perfReport
    print(("Perf report lines: %d"):format(report and #report or 0))
    if not report or #report < 6 then
        H.Report("perf", "/mist perf saved no report")
    elseif not table.concat(report, "\n"):find("Nameplates.module.scannerFrame", 1, true) then
        -- The plate engine's frame is the one the measurement exists for.
        H.Report("perf", "/mist perf did not reach the nameplate engine frame")
    end
end)

-- Loot rolls stay on the movable anchor; the low health alert runs; the personal resource bar
-- (off by default) is switched on, gets heal and absorb values, and is switched off again.
Phase("loot roll, low health, personal resource", function()
    local addon = H.namespaces.MistUI
    local player = units.player
    GroupLootContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
    local _, relative = GroupLootContainer:GetPoint(1)
    if relative ~= MistUI_LootRollAnchor then
        H.Report("loot roll", "the roll container is not on the MistUI anchor")
    end
    H.Fire("START_LOOT_ROLL", 1, 60000)
    local health = player.health
    player.health = 100
    H.Fire("UNIT_HEALTH_FREQUENT", "player")
    H.Tick(4)
    player.health = health
    H.Fire("UNIT_HEALTH_FREQUENT", "player")
    local heals, absorbs = UnitGetIncomingHeals, UnitGetTotalAbsorbs
    addon.db.profile.modules.personalresource.enabled = true
    addon.RefreshPersonalResourceSystem()
    H.Tick(1)
    H.Fire("UNIT_HEAL_PREDICTION", "player")
    UnitGetIncomingHeals = function(_, caster) return caster and 10000 or 30000 end
    UnitGetTotalAbsorbs = function() return 50000 end
    H.Fire("UNIT_HEAL_PREDICTION", "player")
    H.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    H.Fire("UNIT_MAXPOWER", "player")
    H.Fire("UNIT_DISPLAYPOWER", "player")
    H.Tick(1)
    UnitGetIncomingHeals, UnitGetTotalAbsorbs = heals, absorbs
    addon.db.profile.modules.personalresource.enabled = false
    addon.RefreshPersonalResourceSystem()
end)

-- Item level labels and quality borders: gear in the character window, a bank bag slot, a loot roll.
Phase("item info", function()
    local function Expect(ok, what)
        if not ok then H.Report("item info", "expected: " .. what) end
    end

    local items = {
        [1001] = { quality = 4, ilvl = 489, slot = "INVTYPE_HEAD" },
        [1002] = { quality = 3, ilvl = 463, slot = "INVTYPE_2HWEAPON" },
        [1003] = { quality = 7, ilvl = 1, slot = "INVTYPE_CHEST" },
    }
    local function Link(id)
        return "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:90:0|h[Item " .. id .. "]|h|r"
    end
    local worn = { [1] = 1001, [5] = 1003, [16] = 1002 }
    local real = {
        GetItemInfo = GetItemInfo, GetInventoryItemLink = GetInventoryItemLink,
        GetInventoryItemTexture = GetInventoryItemTexture, GetInventoryItemQuality = GetInventoryItemQuality,
        GetContainerItemLink = GetContainerItemLink, GetLootRollItemLink = GetLootRollItemLink,
    }
    GetItemInfo = function(link)
        local item = items[tonumber(tostring(link):match("item:(%d+)"))]
        if not item then return nil end
        return "Item", link, item.quality, item.ilvl, 85, "Armor", "Plate", 1, item.slot, "", 0
    end
    GetInventoryItemLink = function(_, slot) return worn[slot] and Link(worn[slot]) or nil end
    GetInventoryItemTexture = function(_, slot) return worn[slot] and "Interface\\Icons\\INV_Misc_QuestionMark" or nil end
    GetInventoryItemQuality = function(_, slot) return worn[slot] and items[worn[slot]].quality or nil end
    GetContainerItemLink = function(bag, slot) return bag == -1 and slot == 1 and Link(1001) or nil end
    GetLootRollItemLink = function() return Link(1001) end
    local averageItemLevel = GetAverageItemLevel
    GetAverageItemLevel = function() return 90.2, 88.9 end

    -- Window open with the stat pane closed: the floating average may show.
    CharacterFrame:Show()
    PaperDollFrame:Show()
    CharacterStatsPane:Hide()
    local slots = { CharacterHeadSlot = 1, CharacterChestSlot = 5, CharacterMainHandSlot = 16 }
    for name, id in pairs(slots) do
        _G[name]:SetID(id)
        PaperDollItemSlotButton_Update(_G[name])
    end
    H.Fire("PLAYER_EQUIPMENT_CHANGED")
    H.Tick(1)

    local function Label(button) return button.__MistUI_ILvl and button.__MistUI_ILvl:GetText() end
    local function Border(button) return button.__MistUI_QualityOverlay and button.__MistUI_QualityOverlay:IsShown() end
    Expect(Label(CharacterHeadSlot) == "489", "head slot labelled 489")
    Expect(Label(CharacterMainHandSlot) == "463", "main hand labelled 463")
    Expect(Border(CharacterHeadSlot), "head slot has a quality border")
    Expect(Border(CharacterChestSlot), "heirloom chest has a quality border")

    local function AverageText()
        for _, holder in ipairs(PaperDollFrame.__children) do
            for _, region in ipairs(holder.__regions) do
                if region.__shown and region.__text and region.__text:find("^Item Level") then return region.__text end
            end
        end
    end
    -- The player's average is the client's own equipped value, rounded down.
    Expect(AverageText() == "Item Level: 88", "average 88, got " .. tostring(AverageText() or "none"))
    CharacterStatsPane:Show()
    H.Tick(1)
    Expect(AverageText() == nil, "floating average hidden while the stat pane shows it")
    CharacterStatsPane:Hide()

    -- A bank bag slot runs through the same update as bank items; its id must not read as item slot 1.
    BankFrame:Show()
    BankFrameBag1.isBag = 1
    BankFrameBag1:SetID(1)
    BankFrameItemButton_Update(BankFrameBag1)
    Expect(not BankFrameBag1.__MistUI_QualityOverlay, "bank bag slot has no quality border")
    BankFrame:Hide()

    -- The loot roll icon is a parentKey child without a global name.
    local roll = GroupLootFrame1
    roll.IconFrame = roll.IconFrame or CreateFrame("Button", nil, roll)
    roll.rollID = 1
    GroupLootFrame_OnShow(roll)
    H.Tick(0.5)
    Expect(Label(roll.IconFrame) == "489", "loot roll icon labelled 489")

    for name, fn in pairs(real) do _G[name] = fn end
    GetAverageItemLevel = averageItemLevel
    CharacterFrame:Hide()
end)

-- Another character's saved bags show in the bag window, read only, and the view goes back on close.
Phase("other character bags", function()
    local addon = H.namespaces.MistUI
    local mod = addon.BagsterModule
    local frame = mod and mod.frames and mod.frames[1]
    if not (mod and frame and frame.SetPlayer) then
        H.Report("other character bags", "the bag window is not there")
        return
    end
    local link = "|cff1eff00|Hitem:2589:0:0:0:0:0:0:0:90:0|h[Linen Cloth]|h|r"
    local root = addon.db.global.bagsterCache or {}
    addon.db.global.bagsterCache = root
    root[GetRealmName() .. "|Alt"] = { bags = { [0] = { size = 16, slots = { [3] = { link = link, count = 12 } } } } }

    local names = mod("BankCache"):GetOtherCharacters()
    if names[1] ~= "Alt" then H.Report("other character bags", "the saved character is not listed") end
    local _, count, _, _, _, _, itemLink = mod("ItemSlotInfo"):GetItemInfo("Alt", 0, 3)
    if itemLink ~= link or count ~= 12 then
        H.Report("other character bags", "the saved item is not read back for the other character")
    end
    if mod("BagSlotInfo"):GetSize("Alt", 0) ~= 16 then
        H.Report("other character bags", "the saved backpack size is not used")
    end

    -- ShowUIPanel is a stand-in in this fake, so the window is shown directly.
    frame:Show()
    local showBags = frame.sets.showBags
    frame.sets.showBags = true
    frame:UpdateBagFrame()
    if #frame.bagButtons == 0 then H.Report("other character bags", "the bag slots did not show for the current character") end
    H.Tick(0.2)
    frame:SetPlayer("Alt")
    H.Tick(0.5)
    if frame:GetPlayer() ~= "Alt" then H.Report("other character bags", "the window did not switch") end
    -- Sorting and selling act on the live bags, so their buttons and the bag slots hide for another character.
    local sortButton = _G.MistUI_BagsterBagSortBtn
    if sortButton and sortButton:IsShown() then
        H.Report("other character bags", "the sort button stays shown for another character")
    end
    if #frame.bagButtons > 0 then
        H.Report("other character bags", "the bag slots of the current character stay shown")
    end
    frame:Hide()
    H.Tick(0.2)
    if frame:GetPlayer() ~= mod.playerName then
        H.Report("other character bags", "closing the window did not go back to the current character")
    end
    frame.sets.showBags = showBags
    frame:UpdateBagFrame()
    root[GetRealmName() .. "|Alt"] = nil

    -- The character list says how old another character's snapshot is.
    root[GetRealmName() .. "|Alt"] = { lastSeen = time() - 7200, bags = { [0] = { size = 16, slots = {} } } }
    if mod("BankCache"):GetLastSeen("Alt") ~= root[GetRealmName() .. "|Alt"].lastSeen then
        H.Report("other character bags", "the last seen time of another character is not read back")
    end
    root[GetRealmName() .. "|Alt"] = nil

    -- An active search runs again when item details arrive late.
    local refreshed = false
    local refreshSearch = frame.itemFrame.RefreshSearch
    frame.itemFrame.RefreshSearch = function(self) refreshed = true; return refreshSearch(self) end
    frame:Show()
    frame.itemFrame.search = "cloth"
    H.Fire("GET_ITEM_INFO_RECEIVED")
    H.Tick(0.5)
    if not refreshed then H.Report("other character bags", "the search did not run again when item details arrived") end
    frame.itemFrame.search = nil
    frame.itemFrame.RefreshSearch = nil
    frame:Hide()

    -- Bag window slots made on demand get the Alt+click lock hook as they are created.
    local newSlot = mod.ItemSlot:New()
    if not (newSlot and newSlot._mistUISortLockHooked) then
        H.Report("other character bags", "a new bag window slot has no sort lock hook")
    end
    if newSlot then newSlot:Free() end

    -- A window the player opened stays open when a vendor that also asked for the bags closes.
    local vendor = { GetName = function() return "MerchantFrame" end }
    local hideUIPanel, hidden = HideUIPanel, false
    HideUIPanel = function(panel) if panel == frame then hidden = true end end
    -- Shown by hand, as the player's own click would (the bank phase left it marked as opened for the bank).
    frame:Show()
    frame.autoShown = nil
    OpenAllBags(vendor)
    CloseAllBags(vendor)
    if hidden then H.Report("other character bags", "closing a vendor closed a bag window the player opened") end
    HideUIPanel = hideUIPanel
    frame:Hide()
end)

-- A raid frame set up by the stock code gets the Mist-UI bars, and a dispellable debuff outlines it.
Phase("raid frames", function()
    local addon = H.namespaces.MistUI
    local frame = CreateFrame("Button", "CompactRaidFrame1", UIParent)
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.background = frame:CreateTexture()
    frame.name = frame:CreateFontString()
    frame.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    frame.unit, frame.displayedUnit = "raid1", "raid1"
    local function StockSetup(f)
        f.healthBar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
        f.powerBar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
        f.background:SetTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Bg")
    end
    -- The client's CompactUnitFrame_SetUpFrame runs the setup before the hooks; this fake's does not.
    StockSetup(frame)
    CompactUnitFrame_SetUpFrame(frame, StockSetup)
    local fill = frame.healthBar:GetStatusBarTexture() and frame.healthBar:GetStatusBarTexture():GetTexture()
    if not (fill and fill:find("PersonalResource")) then
        H.Report("raid frames", "a raid frame kept the stock bar: " .. tostring(fill))
    end
    -- The client's debuff colors (DebuffFrame.lua); this fake has none.
    local debuffColors = DebuffTypeColor
    DebuffTypeColor = { Curse = { r = 0.6, g = 0, b = 1 } }
    local unitDebuff = UnitDebuff
    UnitDebuff = function(unit, index, filter)
        if unit == "raid1" and index == 1 and filter == "RAID" then return "Curse of Tests", nil, "", 1, "Curse" end
    end
    CompactUnitFrame_UpdateAuras(frame)
    local shown = 0
    for _, region in ipairs({ frame.healthBar:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:IsShown() and region ~= frame.healthBar:GetStatusBarTexture() then
            shown = shown + 1
        end
    end
    if shown < 4 then H.Report("raid frames", "no dispel outline for a curse the player can remove") end
    UnitDebuff = unitDebuff
    DebuffTypeColor = debuffColors
    addon.RestoreRaidFramesSystem()
    fill = frame.healthBar:GetStatusBarTexture() and frame.healthBar:GetStatusBarTexture():GetTexture()
    if fill ~= "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" then H.Report("raid frames", "switching the module off kept the Mist-UI bar") end
    addon.ApplyRaidFramesSystem()
    frame:Hide()
end)

-- A dropped box snaps to the edit mode grid, and Undo puts it back where the drag started.
Phase("edit mode snap and undo", function()
    local addon = H.namespaces.MistUI
    local snap = addon.EditorSnap
    local box = addon.CreateUIFrame(40, 40, "HarnessSnapBox")
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 400)
    local dx, dy, _, _, ratio = snap.Target(box)
    if not (dx or dy) then
        H.Report("edit mode snap and undo", "the test box is not near a grid line")
        return
    end
    box:GetScript("OnDragStart")(box, "LeftButton")
    box:GetScript("OnDragStop")(box)
    local _, _, _, x, y = box:GetPoint(1)
    if math.abs(x - (100 + (dx or 0) / ratio)) > 0.01 or math.abs(y - (400 + (dy or 0) / ratio)) > 0.01 then
        H.Report("edit mode snap and undo", ("the box did not snap: %s, %s"):format(tostring(x), tostring(y)))
    end
    if not snap.Undo() then H.Report("edit mode snap and undo", "nothing to undo after a drag") end
    _, _, _, x, y = box:GetPoint(1)
    if x ~= 100 or y ~= 400 then
        H.Report("edit mode snap and undo", ("undo did not restore the start: %s, %s"):format(tostring(x), tostring(y)))
    end
    snap.SetEnabled(false)
    box:GetScript("OnDragStart")(box, "LeftButton")
    box:GetScript("OnDragStop")(box)
    _, _, _, x = box:GetPoint(1)
    if x ~= 100 then H.Report("edit mode snap and undo", "the box snapped with snapping off") end
    snap.SetEnabled(true)
    snap.ClearUndo()
    box:Hide()
end)

-- Giving a region of a protected frame another parent is blocked in combat: the party frame's
-- status icons wait for the end of combat.
Phase("party icons in combat", function()
    local frame, icon = _G.PartyMemberFrame1, _G.PartyMemberFrame1PVPIcon
    if not (frame and icon and frame.MistUI_IconContainer and PartyMemberFrame_UpdateMember) then
        H.Report("party icons in combat", "party frame 1, its PvP icon or the icon container is missing")
        return
    end
    units.party1 = Unit("Botfriend", "0x0000000000000002", 90)
    H.state.group = true
    icon:SetParent(frame)
    local movedInCombat
    local setParent = icon.SetParent
    icon.SetParent = function(self, parent)
        if InCombatLockdown() then movedInCombat = true end
        return setParent(self, parent)
    end
    H.inCombat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    PartyMemberFrame_UpdateMember(frame)
    if movedInCombat then H.Report("party icons in combat", "the PvP icon got a new parent in combat") end
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    if icon:GetParent() ~= frame.MistUI_IconContainer then
        H.Report("party icons in combat", "the PvP icon was not moved above the border after combat")
    end
    icon.SetParent = nil
    units.party1 = nil
    H.state.group = false
    H.Fire("GROUP_ROSTER_UPDATE")
    H.Tick(1)
end)

-- A vehicle entered in combat: the player frame's parts are laid out only once combat ends.
Phase("player frame vehicle in combat", function()
    local parts = { PlayerPortrait, PlayerName, PlayerFrameHealthBar }
    local METHODS = { "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetParent" }
    local moved = {}
    for _, part in ipairs(parts) do
        for _, method in ipairs(METHODS) do
            local original = part[method]
            part[method] = function(self, ...)
                local caller = debug.getinfo(2, "S")
                if InCombatLockdown() and caller and caller.source:find("MistUI", 1, true) then
                    moved[#moved + 1] = (self:GetName() or "?") .. ":" .. method
                end
                return original(self, ...)
            end
        end
    end
    units.vehicle = Unit("Siege Tank", "0xF150000000000001", 90)
    H.state.vehicle = true
    H.inCombat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    PlayerFrame_ToVehicleArt(PlayerFrame, "Natural")
    if #moved > 0 then
        H.Report("player frame vehicle in combat", "moved in combat: " .. table.concat(moved, ", "))
    end
    H.state.vehicle = false
    units.vehicle = nil
    PlayerFrame_ToPlayerArt(PlayerFrame)
    H.inCombat = false
    for _, part in ipairs(parts) do
        for _, method in ipairs(METHODS) do part[method] = nil end
    end
    H.Fire("PLAYER_REGEN_ENABLED")
    H.Tick(1)
end)

-- Work queued for the end of combat runs in the order it was queued, and work an operation
-- queues while the batch runs is kept.
Phase("combat queue order", function()
    local queue = H.namespaces.MistUI.CombatQueue
    local ran = {}
    H.inCombat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    for _, id in ipairs({ "harness_first", "harness_second", "harness_third", "harness_fourth" }) do
        queue:Add(id, function()
            ran[#ran + 1] = id
            if id == "harness_second" then
                queue:Add("harness_late", function() ran[#ran + 1] = "harness_late" end)
            end
        end)
    end
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    local got = table.concat(ran, ",")
    if got ~= "harness_first,harness_second,harness_third,harness_fourth,harness_late" then
        H.Report("combat queue order", "ran: " .. got)
    end
end)

-- A specialization with its own profile offers the switch; nothing is offered while it is off.
Phase("spec profiles", function()
    local addon = H.namespaces.MistUI
    local specs = addon.SpecProfiles
    local settings = specs.Settings()
    local spec = GetSpecialization() or 1
    local getSpecialization = GetSpecialization
    GetSpecialization = function() return spec end
    addon.db.sv.profiles["Healer"] = addon.db.sv.profiles["Healer"] or {}
    settings[spec] = "Healer"
    local shown, data
    local showPopup = StaticPopup_Show
    StaticPopup_Show = function(which, _, _, popupData) shown, data = which, popupData end
    specs.Check()
    if shown then H.Report("spec profiles", "a switch was offered while the option is off") end
    settings.enabled = true
    specs.Check()
    if shown ~= "MISTUI_SPEC_PROFILE" or data ~= "Healer" then
        H.Report("spec profiles", "no switch to the specialization's profile was offered")
    end
    StaticPopup_Show = showPopup
    GetSpecialization = getSpecialization
    settings.enabled, settings[spec] = nil, nil
    addon.db.sv.profiles["Healer"] = nil
end)

-- Missing artwork is reported with a popup; installed artwork says nothing.
Phase("artwork check", function()
    local check = H.namespaces.MistUI.ArtworkCheck
    local shown
    local showPopup = StaticPopup_Show
    StaticPopup_Show = function(which) shown = which end
    check.Run()
    if shown then H.Report("artwork check", "a popup came up with the artwork installed") end
    local probe = check.probe
    local setTexture = probe.SetTexture
    probe.SetTexture = function(self, path) setTexture(self, path); return nil end
    check.Run()
    if shown ~= "MISTUI_ARTWORK_MISSING" then H.Report("artwork check", "no popup for missing artwork") end
    probe.SetTexture = setTexture
    StaticPopup_Show = showPopup
end)

-- The help ticket status moves BuffFrame (TicketStatusFrame_OnShow); it goes back onto ours.
Phase("buff frame anchor", function()
    local ours = _G.MistUI_Buff
    if not ours then
        H.Report("buff frame anchor", "the buff frame mover is missing")
        return
    end
    BuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -60)
    local _, relative = BuffFrame:GetPoint(1)
    if relative ~= ours or BuffFrame:GetNumPoints() ~= 1 then
        H.Report("buff frame anchor", "a stock move of BuffFrame was not put back onto the mover")
    end
    ConsolidatedBuffs:ClearAllPoints()
    local _, cbRelative = ConsolidatedBuffs:GetPoint(1)
    if cbRelative ~= ours then
        H.Report("buff frame anchor", "clearing ConsolidatedBuffs left it off the mover")
    end
end)

-- Hover polling only runs while "show on hover" can show the frame.
Phase("hover polling", function()
    local VF = H.namespaces.MistUI.VisibilityFade
    local cfg = { show_on_hover = false }
    VF.Register("harnessHover", CreateFrame("Frame"), { dbTable = function() return cfg end, pollHover = true })
    local function Polling() return VF.IsPolling("harnessHover") end
    if Polling() then H.Report("hover polling", "the poller runs with show on hover off") end
    cfg.show_on_hover = true
    VF.Update("harnessHover")
    if not Polling() then H.Report("hover polling", "the poller did not start with show on hover on") end
    VF.Unregister("harnessHover")
end)

-- Totem plates get an icon from the 5.4.8 totem list: Mist-UI art where it exists, the spell's icon otherwise.
Phase("nameplate totems", function()
    local NP = H.namespaces.MistUI.Nameplates
    local searing = NP.widgets.ResolveTotemTexturePath("Searing Totem")
    if not (searing and searing:find("Searing Totem X", 1, true)) then
        H.Report("nameplate totems", "Searing Totem did not get the Mist-UI icon: " .. tostring(searing))
    end
    local capacitor = NP.widgets.ResolveTotemTexturePath("Capacitor Totem")
    if not (capacitor and capacitor:find("Icons", 1, true)) then
        H.Report("nameplate totems", "Capacitor Totem did not get the spell's icon: " .. tostring(capacitor))
    end
    if not NP.widgets.IsTotemName("Healing Tide Totem") then
        H.Report("nameplate totems", "Healing Tide Totem is not known as a totem")
    end
    if NP.widgets.ResolveTotemTexturePath("Totem of Wrath IV") then
        H.Report("nameplate totems", "a totem the 5.4.8 client does not have still has an icon")
    end
end)

-- Rare icons are told apart by the corner coordinates of the client's elite icon.
Phase("nameplate rare icon", function()
    local NP = H.namespaces.MistUI.Nameplates
    local icon = CreateFrame("Frame"):CreateTexture()
    icon:SetTexture("Interface\\Tooltips\\EliteNameplateIcon")
    icon:SetTexCoord(unpack(NP.const.PLATE_CLASS_TEXCOORDS.rare))
    icon:Show()
    local plate = { eliteIcon = icon }
    NP.native_style.NoteNativePlateClassification(plate)
    if plate._plateClassification ~= "rare" then
        H.Report("nameplate rare icon", "a rare icon was read as " .. tostring(plate._plateClassification))
    end
end)

-- Edit mode boxes are labelled with the readable name from the locale.
Phase("edit mode labels", function()
    local box = H.namespaces.MistUI.CreateUIFrame(10, 10, "PlayerFrame")
    local text = box and box.editorText and box.editorText:GetText()
    if text ~= "Player" then H.Report("edit mode labels", "the player box is labelled " .. tostring(text)) end
end)

-- The Escape menu gets a MistUI button below "Return to Game", and the button opens the settings.
Phase("game menu button", function()
    local panel = H.namespaces.MistUI.OptionsPanel
    GameMenuFrame:SetHeight(270)
    GameMenuFrame_UpdateVisibleButtons(GameMenuFrame)
    local button = _G.MistUIGameMenuButton
    if not (button and button:IsShown()) then
        H.Report("game menu button", "no MistUI button in the Escape menu")
        return
    end
    local _, relative = button:GetPoint(1)
    if relative ~= GameMenuButtonContinue then
        H.Report("game menu button", "the button is not below Return to Game")
    end
    if GameMenuFrame:GetHeight() <= 270 then
        H.Report("game menu button", "the menu did not grow to fit the button")
    end
    if panel and panel:IsOpen() then panel:Toggle() end
    button:Click()
    if not (panel and panel:IsOpen()) then
        H.Report("game menu button", "the button did not open the settings")
    elseif panel then
        panel:Toggle()
    end
end)

-- Every tab of the settings panel is built once.
Phase("settings tabs", function()
    local panel = H.namespaces.MistUI.OptionsPanel
    if not (panel and panel.tabOrder) then
        H.Report("settings tabs", "the settings panel did not load")
        return
    end
    -- Each tab with sub-tabs hands AddSubTabs the sub-tab list and the click handler; both are
    -- kept so every sub-tab can be clicked once after its tab is built.
    local controls = H.namespaces.MistUI.PanelControls
    local addSubTabs = controls.AddSubTabs
    local pending
    controls.AddSubTabs = function(self, parent, tabs, activeKey, onSelect, ...)
        if not panel.indexing and not pending then pending = { tabs = tabs, onSelect = onSelect } end
        return addSubTabs(self, parent, tabs, activeKey, onSelect, ...)
    end
    local subTabs = 0
    for _, key in ipairs(panel.tabOrder) do
        pending = nil
        H.Call("settings tab " .. tostring(key), panel.SelectTab, panel, key)
        H.Tick(0.2)
        local found = pending
        if found and found.onSelect then
            for _, tab in ipairs(found.tabs) do
                pending = found
                H.Call("settings tab " .. tostring(key) .. " / " .. tostring(tab.key), found.onSelect, tab.key)
                subTabs = subTabs + 1
                H.Tick(0.1)
            end
            H.Call("settings tab " .. tostring(key) .. " / " .. tostring(found.tabs[1].key), found.onSelect, found.tabs[1].key)
        end
    end
    controls.AddSubTabs = addSubTabs
    print(("Settings tabs built: %d (%d sub-tabs)"):format(#panel.tabOrder, subTabs))
end)

-- Runs last: it replaces the client's bag functions with a small model of the bags and cursor.
-- Bag sort, item counts and alt gold against a small model of the client's bags.
Phase("bag sort, item counts and alt gold", function()
    local addon = H.namespaces.MistUI
    DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or { AddMessage = function(_, text) print("chat: " .. tostring(text)) end }
    local function Check(condition, message)
        if not condition then H.Report("bag sort scenario", message) end
    end

    local ITEMS = {
        [100] = { name = "Linen Cloth", quality = 1, class = "Trade Goods", subclass = "Cloth", stack = 20, equip = "" },
        [200] = { name = "Iron Sword", quality = 3, class = "Weapon", subclass = "One-Handed Swords", stack = 1, equip = "INVTYPE_WEAPON" },
        [300] = { name = "Healing Potion", quality = 1, class = "Consumable", subclass = "Potion", stack = 20, equip = "" },
        [400] = { name = "Broken Fang", quality = 0, class = "Miscellaneous", subclass = "Junk", stack = 1, equip = "", price = 5 },
        [500] = { name = "Plate Chest", quality = 2, class = "Armor", subclass = "Plate", stack = 1, equip = "INVTYPE_CHEST" },
    }
    local PET_LINK = "|cff0070dd|Hbattlepet:244:1:3:155:10:10:0000000000000001|h[Cat]|h|r"
    local function ItemLink(id) return "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:90:0|h[Item " .. id .. "]|h|r" end

    local sizes = { [-1] = 28, [0] = 8, [1] = 6, [2] = 0, [3] = 0, [4] = 0, [5] = 4 }
    local grid = {
        [-1] = {},
        [0] = { [1] = { id = 400, count = 1 }, [2] = { id = 100, count = 5 }, [4] = { id = 200, count = 1 },
                [5] = { id = 100, count = 10 }, [7] = { id = 300, count = 3 } },
        [1] = { [2] = { id = 500, count = 1 }, [3] = { pet = true, count = 1 }, [5] = { id = 100, count = 3 },
                [6] = { id = 300, count = 4 } },
        [5] = { [1] = { id = 100, count = 7 } },
    }
    local cursor

    _G.GetContainerNumSlots = function(bag) return sizes[bag] or 0 end
    _G.GetContainerNumFreeSlots = function() return 0, 0 end
    _G.GetNumBankSlots = function() return 1, false end
    _G.GetContainerItemID = function(bag, slot)
        local entry = grid[bag] and grid[bag][slot]
        return entry and entry.id
    end
    _G.GetContainerItemLink = function(bag, slot)
        local entry = grid[bag] and grid[bag][slot]
        if not entry then return nil end
        return entry.pet and PET_LINK or ItemLink(entry.id)
    end
    _G.GetContainerItemInfo = function(bag, slot)
        local entry = grid[bag] and grid[bag][slot]
        if not entry then return nil end
        return "Interface\\Icons\\INV_Misc_QuestionMark", entry.count, entry.locked, 1, nil, nil,
            _G.GetContainerItemLink(bag, slot), nil
    end
    _G.GetItemInfo = function(item)
        local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        local facts = ITEMS[id]
        if not facts then return nil end
        return facts.name, ItemLink(id), facts.quality, 10, 1, facts.class, facts.subclass, facts.stack, facts.equip,
            "Interface\\Icons\\INV_Misc_QuestionMark", facts.price
    end
    -- As in the client: a picked-up item stays in its slot until dropped, and a drop on another
    -- item swaps the two, so the cursor is empty again afterwards.
    local function CursorItem()
        if not cursor then return nil end
        return cursor.item or grid[cursor.bag][cursor.slot]
    end
    _G.CursorHasItem = function() return cursor ~= nil end
    _G.GetCursorInfo = function()
        local item = CursorItem()
        if not item then return nil end
        return "item", item.id, ItemLink(item.id)
    end
    _G.ClearCursor = function() cursor = nil end
    _G.PickupContainerItem = function(bag, slot)
        local dst = grid[bag][slot]
        if not cursor then
            if dst then cursor = { bag = bag, slot = slot } end
            return
        end
        local src = CursorItem()
        if cursor.bag == bag and cursor.slot == slot then
            cursor = nil
        elseif not dst then
            grid[bag][slot] = src
            if not cursor.item then grid[cursor.bag][cursor.slot] = nil end
            cursor = nil
        elseif src.id and dst.id == src.id and dst.count < ITEMS[dst.id].stack then
            local moved = math.min(ITEMS[dst.id].stack - dst.count, src.count)
            dst.count = dst.count + moved
            src.count = src.count - moved
            if src.count == 0 and not cursor.item then grid[cursor.bag][cursor.slot] = nil end
            cursor = (cursor.item and src.count > 0) and cursor or nil
        elseif cursor.item then
            -- A split-off part cannot swap
        else
            grid[bag][slot], grid[cursor.bag][cursor.slot] = src, dst
            cursor = nil
        end
    end
    _G.SplitContainerItem = function(bag, slot, amount)
        local entry = grid[bag][slot]
        if cursor or not entry or amount < 1 or amount >= entry.count then return end
        entry.count = entry.count - amount
        cursor = { bag = bag, slot = slot, item = { id = entry.id, count = amount } }
    end

    local function Layout(bags)
        local out = {}
        for _, bag in ipairs(bags) do
            for slot = 1, sizes[bag] do
                local entry = grid[bag][slot]
                out[#out + 1] = entry and (entry.pet and "pet" or (entry.id .. "x" .. entry.count)) or "-"
            end
        end
        return table.concat(out, " ")
    end
    local function Total(id)
        local n = 0
        for bag, slots in pairs(grid) do
            for _, entry in pairs(slots) do if entry.id == id then n = n + entry.count end end
        end
        return n
    end
    local before = { Total(100), Total(300) }

    -- Item counts per character
    addon.db.profile.modules.itemownership = addon.db.profile.modules.itemownership or {}
    addon.db.profile.modules.itemownership.enabled = true
    addon.ApplyItemOwnershipSystem()
    H.Fire("BAG_UPDATE", 0)
    H.Fire("BANKFRAME_OPENED")
    H.Tick(1)
    local realm, player = GetRealmName() or "", UnitName("player")
    local data = addon.db.global.itemOwnership.realms[realm].characters[player]
    Check(data and data.bags and data.bags[100] == 18, "bag count of item 100 should be 18, got " .. tostring(data and data.bags and data.bags[100]))
    Check(data and data.bank and data.bank[100] == 7, "bank count of item 100 should be 7, got " .. tostring(data and data.bank and data.bank[100]))
    Check(not (data and data.bags and data.bags[0]), "a battle pet link must not be counted")

    -- Sorting the bags: the pet slot stays, stacks merge, gray goes last
    local petBefore = grid[1][3]
    Check(addon.SortPlayerBags ~= nil, "SortPlayerBags is not exposed")
    addon.SortPlayerBags()
    H.Tick(30)
    local layout = Layout({ 0, 1 })
    Check(grid[1][3] == petBefore, "the battle pet slot must not move: " .. layout)
    Check(Total(100) == before[1] and Total(300) == before[2], "stack totals changed while sorting: " .. layout)
    Check(layout == "200x1 500x1 300x7 100x18 400x1 - - - - - pet - - -", "unexpected sorted order: " .. layout)

    -- Combat blocks a sort
    H.inCombat = true
    grid[0][8] = { id = 400, count = 1 }
    addon.SortPlayerBags()
    H.Tick(2)
    Check(grid[0][8] ~= nil and grid[0][8].id == 400, "a sort ran during combat: " .. Layout({ 0, 1 }))
    H.inCombat = false
    grid[0][8] = nil

    local chat = {}
    local addMessage = DEFAULT_CHAT_FRAME.AddMessage
    DEFAULT_CHAT_FRAME.AddMessage = function(self, text, ...)
        chat[#chat + 1] = tostring(text)
        return addMessage(self, text, ...)
    end
    local function Said(fragment)
        for _, line in ipairs(chat) do
            if line:find(fragment, 1, true) then return true end
        end
        return false
    end

    -- A running sort shows its progress on the sort button, and a second click stops it
    local sortButton = _G.MistUI_BagsterBagSortBtn
    grid[0][1], grid[0][3] = grid[0][3], grid[0][1]
    grid[0][2], grid[0][5] = grid[0][5], grid[0][2]
    addon.SortPlayerBags()
    H.Tick(0.15, 0.05)
    local progress = sortButton and sortButton.progressText and sortButton.progressText:GetText()
    Check(progress and progress:match("^%d+/%d+$"), "no progress on the sort button during a sort: " .. tostring(progress))
    addon.SortPlayerBags()
    Check(Said("Sort stopped."), "a second click did not stop the sort")
    Check(sortButton and sortButton.progressText:GetText() == "", "the progress stayed after the sort stopped")
    addon.SortPlayerBags()
    H.Tick(30)

    -- An item whose details are not loaded yet stops the sort before anything moves
    grid[0][8] = { id = 999, count = 1 }
    local unsorted = Layout({ 0, 1 })
    addon.SortPlayerBags()
    H.Tick(5)
    Check(Layout({ 0, 1 }) == unsorted, "a sort ran with an item whose details were not loaded: " .. Layout({ 0, 1 }))
    Check(Said("still loading"), "no message about item details still loading")
    grid[0][8] = nil

    -- A slot that stays locked ends the sort with a message instead of waiting forever
    grid[0][8] = { id = 200, count = 1, locked = true }
    addon.SortPlayerBags()
    H.Tick(10)
    Check(Said("did not finish"), "a sort waiting on a locked slot never stopped")
    grid[0][8] = nil
    DEFAULT_CHAT_FRAME.AddMessage = addMessage

    -- Sorting the bank tops up bank stacks from the bags
    addon.SortBankBags()
    H.Tick(30)
    Check(Total(100) == before[1], "bank sort changed the cloth total")
    H.Fire("BANKFRAME_CLOSED")

    -- Alt gold
    H.Fire("PLAYER_MONEY")
    Check(addon.GetCharacterMoney(player) ~= nil, "the current character's gold was not stored")
    addon.db.global.characterMoney["Other Realm|Alt"] = { copper = 123456789, class = "MAGE" }
    local known = addon.GetKnownCharacters()
    Check(known["Other Realm|Alt"] == "Alt - Other Realm", "known characters did not list the stored alt")
    local button = _G.ContainerFrame1MoneyFrameGoldButton
    Check(button ~= nil, "stock money frame button missing")
    if button then
        H.FireScript(button, "OnEnter")
        H.FireScript(button, "OnLeave")
    end
    Check(addon.ForgetCharacter("Other Realm", "Alt"), "ForgetCharacter refused")
    Check(addon.GetCharacterMoney("Alt", "Other Realm") == nil, "forgotten gold still stored")
end)

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

local function Sorted(t, limit)
    local list = {}
    for k, n in pairs(t) do list[#list + 1] = { k, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local out = {}
    for i = 1, math.min(limit, #list) do out[i] = list[i][1] .. " (" .. list[i][2] .. ")" end
    return out, #list
end

print(("Errors: %d"):format(#H.errors))
for i, e in ipairs(H.errors) do
    print(("\n[%d] phase %s, %s, x%d"):format(i, e.phase, e.where, e.count))
    print(e.trace)
end
local globals, nGlobals = Sorted(H.unknownGlobals, manifest.verbose and 300 or 25)
print(("\nClient names answered with a stand-in (%d): %s"):format(nGlobals, table.concat(globals, ", ")))
os.exit(#H.errors == 0 and 0 or 1)
