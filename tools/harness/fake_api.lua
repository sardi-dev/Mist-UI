-- Game functions the fake answers with plausible values: a level 90 warrior, alone, out of
-- combat, with a backpack and one bag. Everything else the client provides answers nil.

local H = __harness

-- ---------------------------------------------------------------------------
-- Lua extensions the client adds
-- ---------------------------------------------------------------------------

local function Bit(op)
    return function(a, ...)
        local r = a or 0
        for i = 1, select("#", ...) do
            local b = select(i, ...)
            local res, bitv = 0, 1
            local x, y = r, b
            for _ = 1, 32 do
                local xa, yb = x % 2, y % 2
                if op(xa, yb) then res = res + bitv end
                x, y, bitv = math.floor(x / 2), math.floor(y / 2), bitv * 2
            end
            r = res
        end
        return r
    end
end
bit = {
    band = Bit(function(a, b) return a == 1 and b == 1 end),
    bor = Bit(function(a, b) return a == 1 or b == 1 end),
    bxor = Bit(function(a, b) return a ~= b end),
    lshift = function(a, n) return (a * 2 ^ n) % 2 ^ 32 end,
    rshift = function(a, n) return math.floor(a / 2 ^ n) end,
    bnot = function(a) return 2 ^ 32 - 1 - a end,
}

strtrim = function(s, chars)
    chars = chars and ("[" .. chars:gsub("%p", "%%%0") .. "]") or "%s"
    return (s:gsub("^" .. chars .. "*(.-)" .. chars .. "*$", "%1"))
end
string.trim = strtrim
strsplit = function(sep, s, limit)
    local out, pos = {}, 1
    if s == nil then return nil end
    while true do
        if limit and #out == limit - 1 then out[#out + 1] = s:sub(pos); break end
        local a, b = s:find(sep, pos, true)
        if not a then out[#out + 1] = s:sub(pos); break end
        out[#out + 1] = s:sub(pos, a - 1)
        pos = b + 1
    end
    return unpack(out)
end
string.split = function(s, sep, limit) return strsplit(sep, s, limit) end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strconcat = function(...) return table.concat({ ... }) end
strlen, strsub, strfind, strmatch, strupper, strlower, strrep, strbyte, strchar, strrev =
    string.len, string.sub, string.find, string.match, string.upper, string.lower, string.rep, string.byte,
    string.char, string.reverse
gsub, format, gmatch = string.gsub, string.format, string.gmatch
tinsert, tremove, sort, getn, foreach = table.insert, table.remove, table.sort, table.getn, table.foreach
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
abs, ceil, floor, max, min, sqrt, random, mod, exp, log, deg, rad = math.abs, math.ceil, math.floor, math.max,
    math.min, math.sqrt, math.random, math.fmod, math.exp, math.log, math.deg, math.rad
sin = function(d) return math.sin(math.rad(d)) end
cos = function(d) return math.cos(math.rad(d)) end
fastrandom = math.random
date, time = os.date, os.time
debugstack = function() return debug.traceback("", 2) end
debugprofilestop = function() return H.now * 1000 end
GetTime = function() return H.now end
securecall = function(f, ...)
    if type(f) == "string" then f = _G[f] end
    return f(...)
end
issecure = function() return nil end
issecurevariable = function() return nil, "MistUI" end
forceinsecure = function() end
local errorHandler = function(e) H.Report("error handler", e) end
geterrorhandler = function() return errorHandler end
seterrorhandler = function(f) errorHandler = f end
hooksecurefunc = function(tbl, name, hook)
    if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
    local old = tbl[name]
    if type(old) ~= "function" and not H.IsStub(old) then
        error("hooksecurefunc: " .. tostring(name) .. " is not a function", 2)
    end
    tbl[name] = function(...)
        local r = { old(...) }
        hook(...)
        return unpack(r)
    end
end
RecentTimeDate = function() return "1 hour ago" end
GetDenominationsFromCopper = function(m) return tostring(m) .. "c" end
GetMoneyString = function(m) return tostring(m) .. "c" end
GetQuestDifficultyColor = function() return { r = 1, g = 0.82, b = 0, font = "QuestDifficulty_Difficult" } end
GetRelativeDifficultyColor = GetQuestDifficultyColor
getglobal = function(name) return _G[name] end
setglobal = function(name, value) _G[name] = value end
tContains = function(t, v) for _, x in pairs(t) do if x == v then return 1 end end return nil end
CopyTable = function(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
tDeleteItem = function(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end

-- ---------------------------------------------------------------------------
-- Client and character
-- ---------------------------------------------------------------------------

GetBuildInfo = function() return "5.4.8", "18414", "Jan 1 2014", 50400 end
GetLocale = function() return "enUS" end
GetRealmName = function() return "Harness" end
IsLoggedIn = function() return H.loggedIn and 1 or nil end
InCombatLockdown = function() return H.inCombat and 1 or nil end
UnitAffectingCombat = function(u) return u == "player" and H.inCombat and 1 or nil end
GetScreenWidth = function() return 1365 end
GetScreenHeight = function() return 768 end
GetFramerate = function() return 60 end
GetCursorPosition = function() return 500, 400 end
IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown, IsModifiedClick = function() end, function() end, function() end,
    function() end
GetCurrentResolution = function() return 1 end
GetScreenResolutions = function() return "1920x1080" end
GetNumAddOns = function() return 2 end
local addons = { MistUI = true, MistUI_Options = true }
IsAddOnLoaded = function(n) return addons[n] and 1 or nil end
GetAddOnInfo = function(n)
    if type(n) == "number" then n = n == 1 and "MistUI" or "MistUI_Options" end
    return n, n, "", 1, nil, nil, nil
end
GetAddOnMetadata = function(n, k) if k == "Version" then return "0.1.0-dev" end end
GetAddOnEnableState = function() return 2 end
LoadAddOn = function(n) return addons[n] and 1 or nil, addons[n] and nil or "MISSING" end
EnableAddOn, DisableAddOn = function() end, function() end

local cvars = {}
GetCVar = function(k) return cvars[k] or "0" end
GetCVarBool = function(k) return cvars[k] == "1" and 1 or nil end
GetCVarDefault = function() return "0" end
SetCVar = function(k, v) cvars[k] = tostring(v) end
RegisterCVar = function(k, v) cvars[k] = cvars[k] or v end

local units = {
    player = { name = "Tester", class = "Warrior", token = "WARRIOR", classId = 1, level = 90, guid = "0x0000000000000001",
        health = 400000, healthMax = 450000, power = 30, powerMax = 100, powerType = 1, powerToken = "RAGE" },
}
H.units = units
local function U(u) return u and units[u] end
UnitExists = function(u) return U(u) and 1 or nil end
UnitName = function(u) local d = U(u); if d then return d.name, nil end end
UnitGUID = function(u) local d = U(u); return d and d.guid end
UnitClass = function(u) local d = U(u); if d then return d.class, d.token, d.classId end end
UnitClassBase = function(u) local d = U(u); if d then return d.token, d.classId end end
UnitRace = function(u) if U(u) then return "Human", "Human" end end
UnitSex = function() return 2 end
UnitLevel = function(u) local d = U(u); return d and d.level or 0 end
UnitEffectiveLevel = UnitLevel
UnitHealth = function(u) local d = U(u); return d and d.health or 0 end
UnitHealthMax = function(u) local d = U(u); return d and d.healthMax or 0 end
UnitPower = function(u) local d = U(u); return d and d.power or 0 end
UnitPowerMax = function(u) local d = U(u); return d and d.powerMax or 0 end
UnitPowerType = function(u) local d = U(u); if d then return d.powerType, d.powerToken end return 0, "MANA" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
-- Stock UIParent.lua builds it in the client from the quality colours.
ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 },
    [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
    [6] = { r = 0.9, g = 0.8, b = 0.5 }, [7] = { r = 0, g = 0.8, b = 1 },
}
-- Stock UnitFrame.lua defines it as a table literal, which the stock reader does not import.
PowerBarColor = {
    MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, FOCUS = { r = 1, g = 0.5, b = 0.25 },
    ENERGY = { r = 1, g = 1, b = 0 }, RUNIC_POWER = { r = 0, g = 0.82, b = 1 },
    [0] = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 }, [3] = { r = 1, g = 1, b = 0 },
}
UnitGetIncomingHeals = function() return nil end
UnitGetTotalAbsorbs = function() return nil end
UnitIsPlayer = function(u) return u == "player" and 1 or nil end
UnitIsUnit = function(a, b) return a == b and U(a) and 1 or nil end
UnitIsDead, UnitIsGhost, UnitIsDeadOrGhost = function() end, function() end, function() end
UnitIsConnected = function(u) return U(u) and 1 or nil end
UnitFactionGroup = function(u) if U(u) then return "Alliance", "Alliance" end end
UnitReaction = function(a, b) return U(b) and 5 or nil end
UnitCanAttack, UnitIsEnemy = function() end, function() end
UnitIsFriend = function(a, b) return U(b) and 1 or nil end
UnitClassification = function(u) return U(u) and "normal" or nil end
UnitCreatureType = function() return nil end
UnitInVehicle, UnitHasVehicleUI, UnitUsingVehicle = function() end, function() end, function() end
UnitInParty, UnitInRaid = function() end, function() end
UnitIsGroupLeader, UnitIsGroupAssistant = function() end, function() end
UnitGroupRolesAssigned = function() return "NONE" end
UnitAura, UnitBuff, UnitDebuff = function() end, function() end, function() end
UnitCastingInfo, UnitChannelInfo = function() end, function() end
UnitThreatSituation = function() end
UnitDetailedThreatSituation = function() end
UnitXP = function() return 1000 end
UnitXPMax = function() return 5000 end
GetXPExhaustion = function() return nil end
GetRestState = function() return 2, "Normal", 1 end
GetWatchedFactionInfo = function() return nil end
UnitStat = function() return 100, 100, 0, 0 end
GetComboPoints = function() return 0 end
GetNumShapeshiftForms = function() return 0 end
GetShapeshiftForm = function() return 0 end
GetShapeshiftFormInfo = function() end
GetShapeshiftFormCooldown = function() return 0, 0, 1 end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function() return 71, "Arms", "", "", "", "DAMAGER" end
IsInGroup, IsInRaid = function() end, function() end
GetNumGroupMembers, GetNumSubgroupMembers = function() return 0 end, function() return 0 end
GetNumArenaOpponents = function() return 0 end
IsInInstance = function() return nil, "none" end
GetInstanceInfo = function() return "Test Forest", "none", 0, "", 5, 0, false, 0 end
GetZoneText, GetRealZoneText, GetSubZoneText, GetMinimapZoneText = function() return "Test Forest" end,
    function() return "Test Forest" end, function() return "" end, function() return "Test Village" end
GetZonePVPInfo = function() return "friendly" end
GetGuildInfo = function() return nil end
IsInGuild = function() end
GetMoney = function() return 123456 end
GetCoinTextureString = function(m) return tostring(m) end
GetPlayerFacing = function() return 0 end
GetRaidTargetIndex = function() end
GetLootMethod = function() return "freeforall" end
HasPetUI, PetHasActionBar = function() end, function() end
HasAction = function() end
GetActionInfo, GetActionTexture, GetActionText = function() end, function() end, function() end
GetActionCount, GetActionCharges = function() return 0 end, function() return 0, 0 end
GetActionCooldown = function() return 0, 0, 1 end
IsUsableAction = function() end
IsCurrentAction, IsAutoRepeatAction, IsAttackAction, IsEquippedAction, IsConsumableAction, IsStackableAction,
    IsItemAction = function() end, function() end, function() end, function() end, function() end, function() end,
    function() end
ActionHasRange, IsActionInRange = function() end, function() end
GetBonusBarOffset, GetActionBarPage = function() return 0 end, function() return 1 end
HasOverrideActionBar, HasVehicleActionBar, HasTempShapeshiftActionBar, HasBonusActionBar = function() end,
    function() end, function() end, function() end
GetPetActionInfo = function() end
GetPetActionCooldown = function() return 0, 0, 1 end
GetPetActionSlotUsable = function() end
GetBindingKey, GetBindingText, GetBindingAction = function() end, function(k) return k or "" end, function() end
GetNumQuestWatches, GetNumQuestLogEntries = function() return 0 end, function() return 0, 0 end
GetQuestLogSelection = function() return 0 end
GetNumTrackedAchievements = function() return 0 end
GetMinimapShape = function() return "ROUND" end
GetNumTrackingTypes = function() return 0 end
GetTrackingInfo = function() end
GetSpellInfo = function(id)
    if id == nil then return nil end
    return "Spell " .. tostring(id), "", "Interface\\Icons\\INV_Misc_QuestionMark", 0, 0, 0, tonumber(id) or 1
end
GetSpellTexture = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end
GetSpellCooldown = function() return 0, 0, 1 end
IsSpellKnown = function() end
GetItemInfo = function(item)
    if item == nil then return nil end
    local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) or 1
    return "Item " .. id, "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:90:0|h[Item " .. id .. "]|h|r", 1, 400, 85,
        "Miscellaneous", "Junk", 20, "", "Interface\\Icons\\INV_Misc_QuestionMark", 100
end
GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end
GetItemIcon = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end
GetItemFamily = function() return 0 end
GetItemCount = function() return 1 end
GetItemCooldown = function() return 0, 0, 1 end
GetAuctionItemClasses = function()
    return "Weapon", "Armor", "Container", "Consumable", "Glyph", "Trade Goods", "Recipe", "Gem", "Miscellaneous",
        "Quest", "Battle Pets"
end
GetAuctionItemSubClasses = function(i)
    if i == 6 then
        return "Elemental", "Cloth", "Leather", "Metal & Stone", "Cooking", "Herb", "Enchanting", "Jewelcrafting",
            "Parts", "Devices", "Explosives", "Materials", "Other", "Item Enchantment"
    elseif i == 8 then
        return "Red", "Blue", "Yellow", "Purple", "Green", "Orange", "Meta", "Simple", "Prismatic", "Hydraulic", "Cogwheel"
    end
end
GetInventoryItemLink = function(u, slot)
    if slot == 20 then return "|cffffffff|Hitem:4500:0:0:0:0:0:0:0:90:0|h[Traveler's Backpack]|h|r" end
end
GetInventoryItemID = function(u, slot) if slot == 20 then return 4500 end end
GetInventoryItemTexture = function() end
GetInventoryItemCount = function() return 0 end
GetInventoryItemDurability = function() end
GetInventorySlotInfo = function() return 20, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Bag" end
IsInventoryItemLocked = function() end
ContainerIDToInventoryID = function(bag) return 19 + bag end
BankButtonIDToInvSlotID = function(id, isBag) return isBag and (67 + id) or (39 + id) end

-- Bags: a 16 slot backpack with two items and one 18 slot bag in slot 1.
local bagSizes = { [0] = 16, [1] = 18, [2] = 0, [3] = 0, [4] = 0 }
H.bagSizes = bagSizes
local bagItems = { [0] = { [1] = 6948, [2] = 2589 }, [1] = { [3] = 858 } }
GetContainerNumSlots = function(bag) return bagSizes[bag] or 0 end
GetContainerNumFreeSlots = function(bag)
    local n = bagSizes[bag] or 0
    local used = 0
    for _ in pairs(bagItems[bag] or {}) do used = used + 1 end
    return n - used, 0
end
GetContainerItemID = function(bag, slot) return bagItems[bag] and bagItems[bag][slot] end
GetContainerItemLink = function(bag, slot)
    local id = GetContainerItemID(bag, slot)
    if id then return "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:90:0|h[Item " .. id .. "]|h|r" end
end
GetContainerItemInfo = function(bag, slot)
    local id = GetContainerItemID(bag, slot)
    if id then return "Interface\\Icons\\INV_Misc_QuestionMark", 1, nil, 1, nil, nil, GetContainerItemLink(bag, slot), nil end
end
GetContainerItemCooldown = function() return 0, 0, 1 end
GetContainerItemQuestInfo = function() return nil, nil, nil end
GetContainerItemDurability = function() end
GetBagName = function(bag) if (bagSizes[bag] or 0) > 0 then return "Bag " .. bag end end
GetNumBankSlots = function() return 0, nil end
GetBankSlotCost = function() return 1000 end
GetCursorInfo = function() end
CursorHasItem = function() end
GetMouseFocus = function() return nil end
UnitIsAFK, UnitIsDND = function() end, function() end
GetNetStats = function() return 0, 0, 50, 50 end
GetGameTime = function() return 12, 0 end
GetNumFriends = function() return 0, 0 end
BNGetNumFriends = function() return 0, 0 end
GetChatWindowInfo = function(i) return "General", 14, 0, 0, 0, 1, 1, 0, 0 end
GetChatWindowChannels = function() end
GetChannelList = function() end
GetNumWorldStateUI = function() return 0 end
GetNumBattlefieldScores = function() return 0 end
GetNumGuildBankTabs = function() return 0 end
GetCurrentGuildBankTab = function() return 1 end
GetGuildBankTabInfo = function() end
GetNumMacros = function() return 0, 0 end

-- ---------------------------------------------------------------------------
-- Switchable state for the scenarios: group, vehicle, pet, stances, bank bags, guild bank
-- ---------------------------------------------------------------------------

local S = { group = false, vehicle = false, pet = false, forms = 0, bankBags = 0, guildTabs = 0 }
H.state = S

IsInGroup = function() return S.group and 1 or nil end
GetNumSubgroupMembers = function() return S.group and 1 or 0 end
GetNumGroupMembers = function() return S.group and 2 or 0 end
UnitInParty = function(u) return S.group and (u == "player" or u == "party1") and 1 or nil end
UnitIsGroupLeader = function(u) return S.group and u == "player" and 1 or nil end
GetPartyLeaderIndex = function() return 0 end

UnitInVehicle = function(u) return u == "player" and S.vehicle and 1 or nil end
UnitHasVehicleUI = UnitInVehicle
UnitUsingVehicle = UnitInVehicle
HasVehicleActionBar = function() return S.vehicle and 1 or nil end
HasOverrideActionBar = function() return nil end
CanExitVehicle = function() return S.vehicle and 1 or nil end
UnitVehicleSkin = function() return S.vehicle and "Natural" or nil end
UnitVehicleSeatCount = function() return S.vehicle and 1 or 0 end

HasPetUI = function() return S.pet and 1 or nil, S.pet and 1 or nil end
PetHasActionBar = function() return S.pet and 1 or nil end
GetPetActionInfo = function(i)
    if S.pet and i <= 4 then
        return "PET_ACTION_" .. i, nil, "Interface\\Icons\\Ability_Hunter_Pet_Bear", nil, i == 1, true, i == 2
    end
end
GetPetActionSlotUsable = function() return S.pet and 1 or nil end
GetPetHappiness = function() end
GetPetExperience = function() return 0, 1 end

GetNumShapeshiftForms = function() return S.forms end
GetShapeshiftForm = function() return S.forms > 0 and 1 or 0 end
GetShapeshiftFormInfo = function(i)
    if i <= S.forms then return "Interface\\Icons\\Ability_Warrior_DefensiveStance", "Stance " .. i, i == 1, true end
end

GetNumBankSlots = function() return S.bankBags, S.bankBags >= 7 end
local bankItems = { [1] = 6948, [5] = 2589 }
local baseNumSlots = GetContainerNumSlots
GetContainerNumSlots = function(bag)
    if bag == -1 then return 28 end
    if bag >= 5 and bag <= 11 then return (bag - 4) <= S.bankBags and 16 or 0 end
    return baseNumSlots(bag)
end
local baseItemID = GetContainerItemID
GetContainerItemID = function(bag, slot)
    if bag == -1 then return bankItems[slot] end
    if bag == 5 and slot == 2 and S.bankBags > 0 then return 858 end
    return baseItemID(bag, slot)
end
local baseInvLink = GetInventoryItemLink
GetInventoryItemLink = function(u, slot)
    local bankBag = slot and slot - BankButtonIDToInvSlotID(5, 1) + 1
    if bankBag and bankBag >= 1 and bankBag <= S.bankBags then
        return "|cffffffff|Hitem:4500:0:0:0:0:0:0:0:90:0|h[Traveler's Backpack]|h|r"
    end
    return baseInvLink(u, slot)
end

GetNumGuildBankTabs = function() return S.guildTabs end
GetGuildBankTabInfo = function(tab)
    if tab <= S.guildTabs then
        return "Tab " .. tab, "Interface\\Icons\\INV_Misc_QuestionMark", 1, 1, -1, -1
    end
end
GetGuildBankItemInfo = function(tab, slot)
    if tab <= S.guildTabs and slot <= 3 then return "Interface\\Icons\\INV_Misc_QuestionMark", slot, nil end
end
GetGuildBankItemLink = function(tab, slot)
    if tab <= S.guildTabs and slot <= 3 then
        return "|cffffffff|Hitem:" .. (2588 + slot) .. ":0:0:0:0:0:0:0:90:0|h[Item]|h|r"
    end
end
GetGuildBankMoney = function() return 500000 end
GetGuildBankWithdrawMoney = function() return -1 end
GetGuildBankTabCost = function() return 10000 end
GetGuildBankText = function() return "Tab info" end
GetNumGuildBankTransactions = function() return 1 end
GetGuildBankTransaction = function() return "deposit", "Tester", "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", 5, 1, nil, 0, 0, 1, 2 end
GetNumGuildBankMoneyTransactions = function() return 1 end
GetGuildBankMoneyTransaction = function() return "deposit", "Tester", 100, 0, 0, 1, 2 end
CanEditGuildBankTabInfo = function() return 1 end
CanEditGuildTabInfo = function() return 1 end
CanGuildBankRepair = function() return nil end
CanWithdrawGuildBankMoney = function() return 1 end
IsGuildLeader = function() return nil end
IsInGuild = function() return S.guildTabs > 0 and 1 or nil end
GetGuildInfo = function(u) if u == "player" and S.guildTabs > 0 then return "Harness Guild", "Member", 1 end end
GetGuildTabardFileNames = function() end
GetMacroItemIcons = function(t) t[#t + 1] = "INV_Misc_Bag_08"; t[#t + 1] = "INV_Sword_04" end
GetMacroIcons = function(t) t[#t + 1] = "Spell_Nature_Rejuvenation" end

-- ---------------------------------------------------------------------------
-- World map and quest log: two continents, a zone with a landmark, one quest header with two
-- quests (one open, one ready to hand in) that both show on the zone map
-- ---------------------------------------------------------------------------

local MAP = { continent = 2, zone = 1, level = 0 }
H.map = MAP
local ZONE_AREA = { [2] = { 30 } }
GetMapContinents = function() return "Kalimdor", "Eastern Kingdoms" end
GetMapZones = function(c) if c == 2 then return "Test Forest" end end
GetCurrentMapContinent = function() return MAP.continent end
GetCurrentMapZone = function() return MAP.zone end
GetCurrentMapAreaID = function()
    local zones = ZONE_AREA[MAP.continent]
    return zones and zones[MAP.zone] or (MAP.continent > 0 and 10 + MAP.continent or 0)
end
GetCurrentMapDungeonLevel = function() return MAP.level end
GetNumDungeonMapLevels = function() return 0 end
DungeonUsesTerrainMap = function() return nil end
GetMapInfo = function() if MAP.zone > 0 then return "TestForest", 1, 1, nil end return "TestWorld", 1, 1, nil end
SetMapZoom = function(c, z) MAP.continent, MAP.zone = c or 0, z or 0; H.Fire("WORLD_MAP_UPDATE") end
SetMapByID = function(id) if id == 30 then MAP.continent, MAP.zone = 2, 1 end; H.Fire("WORLD_MAP_UPDATE") end
SetMapToCurrentZone = function() MAP.continent, MAP.zone = 2, 1; H.Fire("WORLD_MAP_UPDATE") end
SetDungeonMapLevel = function(l) MAP.level = l end
GetPlayerMapPosition = function(u) if u == "player" and MAP.zone == 1 then return 0.42, 0.65 end return 0, 0 end
GetNumMapLandmarks = function() return MAP.zone == 1 and 1 or 0 end
GetMapLandmarkInfo = function(i) if i == 1 then return "Test Village", "", 6, 0.43, 0.66 end end
GetNumMapOverlays = function() return 0 end
GetUnitSpeed = function() return 0 end
EJ_GetMapEncounter = function() end
-- WorldMapFrame.lua builds this table; the fake runs no stock code, so it starts windowed as the
-- client does after VARIABLES_LOADED with the miniWorldMap setting on.
WORLDMAP_WINDOWED_SIZE = WORLDMAP_WINDOWED_SIZE or 0.573
WORLDMAP_QUESTLIST_SIZE = WORLDMAP_QUESTLIST_SIZE or 0.691
WORLDMAP_FULLMAP_SIZE = WORLDMAP_FULLMAP_SIZE or 1.0
WORLDMAP_POI_FRAMELEVEL = WORLDMAP_POI_FRAMELEVEL or 100
NUM_WORLDMAP_FLAGS = NUM_WORLDMAP_FLAGS or 4
WORLDMAP_SETTINGS = { opacity = 0, locked = true, superTrackedQuestID = 0, size = WORLDMAP_WINDOWED_SIZE }

local QUESTS = {
    { title = "Test Forest", header = true },
    { title = "A Threat Within", level = 1, id = 783, objectives = { { "Wolves slain: 3/8", "monster", false } } },
    { title = "Report to Test Village", level = 2, id = 54, complete = 1, objectives = {} },
}
local watched = { [2] = true }
local selected = 0
GetNumQuestLogEntries = function() return #QUESTS, #QUESTS - 1 end
GetQuestLogTitle = function(i)
    local q = QUESTS[i]
    if not q then return nil end
    if q.header then return q.title, 0, nil, 0, 1, nil end
    return q.title, q.level, nil, 0, nil, nil, q.complete, nil, q.id, nil, 0
end
GetNumQuestLeaderBoards = function(i) local q = QUESTS[i]; return q and q.objectives and #q.objectives or 0 end
GetQuestLogLeaderBoard = function(j, i)
    local o = QUESTS[i or selected] and QUESTS[i or selected].objectives and QUESTS[i or selected].objectives[j]
    if o then return o[1], o[2], o[3] end
end
GetQuestLogRequiredMoney = function() return 0 end
GetQuestLogCompletionText = function(i) local q = QUESTS[i]; if q and q.complete then return "Return to Marshal." end end
GetQuestWorldMapAreaID = function() return 30, 0 end
IsQuestWatched = function(i) return watched[i] and 1 or nil end
GetNumQuestWatches = function() local n = 0 for _ in pairs(watched) do n = n + 1 end return n end
AddQuestWatch = function(i) watched[i] = true end
RemoveQuestWatch = function(i) watched[i] = nil end
SelectQuestLogEntry = function(i) selected = i end
GetQuestLogSelection = function() return selected end
GetQuestLogQuestText = function() return "Kill the wolves.", "Slay 8 wolves." end
GetNumQuestLogChoices, GetNumQuestLogRewards = function() return 1 end, function() return 0 end
GetQuestLogChoiceInfo = function() return "Sturdy Boots", "Interface\\Icons\\INV_Boots_01", 1, 2, 1 end
GetQuestLogRewardMoney, GetQuestLogRewardXP = function() return 250 end, function() return 400 end
GetQuestLogRewardSpell = function() end
GetQuestLogPushable = function() return 1 end
ExpandQuestHeader, CollapseQuestHeader = function() end, function() end
QuestMapUpdateAllQuests = function() return MAP.zone == 1 and 2 or 0 end
QuestPOIGetQuestIDByVisibleIndex = function(i) if i == 1 then return 783, 2 elseif i == 2 then return 54, 3 end end
QuestPOIGetIconInfo = function(id)
    if id == 783 then return 1, 0.30, 0.40, 1 elseif id == 54 then return 1, 0.55, 0.60, 1 end
end
QuestPOIUpdateIcons = function() end
GetSuperTrackedQuestID, SetSuperTrackedQuestID = function() return 0 end, function() end
GetQuestDifficultyColor = function() return { r = 1, g = 0.82, b = 0 } end

-- Tables the stock Lua files build (SharedUIPanelTemplates.lua), which the fake does not run.
TOOLTIP_DEFAULT_COLOR = TOOLTIP_DEFAULT_COLOR or { r = 1, g = 1, b = 1 }
TOOLTIP_DEFAULT_BACKGROUND_COLOR = TOOLTIP_DEFAULT_BACKGROUND_COLOR or { r = 0.09, g = 0.09, b = 0.19 }

-- Tables the client fills itself.
MAX_PLAYER_LEVEL_TABLE = { [0] = 60, [1] = 70, [2] = 80, [3] = 85, [4] = 90 }
GetExpansionLevel, GetAccountExpansionLevel = function() return 4 end, function() return 4 end
ChatTypeInfo = setmetatable({}, { __index = function(t, k)
    local v = { r = 1, g = 1, b = 1, id = 1, sticky = 0 }
    rawset(t, k, v)
    return v
end })

-- Chat message filters, run the way ChatFrame_MessageEventHandler runs them: a true first
-- result hides the line, a text result replaces the arguments for the next filter.
local chatFilters = {}
ChatFrame_AddMessageEventFilter = function(event, filter)
    chatFilters[event] = chatFilters[event] or {}
    for _, known in ipairs(chatFilters[event]) do
        if known == filter then return end
    end
    table.insert(chatFilters[event], filter)
end
ChatFrame_RemoveMessageEventFilter = function(event, filter)
    for index, known in ipairs(chatFilters[event] or {}) do
        if known == filter then table.remove(chatFilters[event], index) break end
    end
end
-- Returns hidden (boolean), then the message as the filters left it.
function H.RunChatFilters(event, msg, author)
    for _, filter in ipairs(chatFilters[event] or {}) do
        local hide, newMsg, newAuthor = filter(nil, event, msg, author)
        if hide then return true, msg end
        if newMsg then msg, author = newMsg, newAuthor end
    end
    return false, msg
end
