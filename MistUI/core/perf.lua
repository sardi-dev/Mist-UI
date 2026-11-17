-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- /mist perf: measures where the addon spends its time, with the client's own script profiler.
-- The profiler only counts while the scriptProfile console setting is on, and it slows every
-- addon down while on, so the command explains how to turn it on and off instead of doing it.
-- It finds functions by walking the addon's own tables and the scripts of the frames found
-- there; a function that is only a local upvalue is counted inside the function that calls it.

local addon = select(2, ...)

local SAVED_VARIABLE = "MistUIDB"
local TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
local WINDOW_SECONDS = 15
local MAX_DEPTH = 7
local MAX_TABLES = 30000
local TOP_FUNCTIONS = 30
local TOP_FRAMES = 15
local CHAT_LINES = 5
local MIN_REPORTED_MS = 0.05
local FRAME_SCRIPTS = { "OnUpdate", "OnEvent" }
-- Tables that hold settings or library state, not code worth timing.
local SKIP_KEYS = { db = true, L = true, defaults = true }
local EVENTS = {
    "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_AURA", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET",
    "BAG_UPDATE", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE",
    "SPELL_UPDATE_COOLDOWN", "UNIT_PORTRAIT_UPDATE", "GROUP_ROSTER_UPDATE", "CURSOR_UPDATE",
}

local Perf = {}
addon.Perf = Perf

local timer
local running = false

local function Number(value)
    return tonumber(value) or 0
end

local function IsFrame(value)
    return type(value) == "table" and type(rawget(value, 0)) == "userdata" and value.GetScript ~= nil
end

-- Lua functions reachable from the addon table, each under the first path that reached it.
local function CollectFunctions()
    local functions, frames = {}, {}
    local seenTables, seenFunctions = {}, {}
    local tableCount = 0

    local function AddFunction(fn, path)
        if not seenFunctions[fn] then
            seenFunctions[fn] = true
            functions[#functions + 1] = { fn = fn, path = path }
        end
    end

    local function Walk(value, path, depth)
        if seenTables[value] or depth > MAX_DEPTH or tableCount >= MAX_TABLES then
            return
        end
        seenTables[value] = true
        tableCount = tableCount + 1
        if IsFrame(value) then
            frames[#frames + 1] = { frame = value, path = path }
            for _, scriptName in ipairs(FRAME_SCRIPTS) do
                local ok, script = pcall(value.GetScript, value, scriptName)
                if ok and type(script) == "function" then
                    AddFunction(script, path .. ":" .. scriptName)
                end
            end
        end
        for key, child in pairs(value) do
            if type(key) == "string" and not SKIP_KEYS[key] then
                local childPath = path .. "." .. key
                if type(child) == "function" then
                    AddFunction(child, childPath)
                elseif type(child) == "table" then
                    Walk(child, childPath, depth + 1)
                end
            elseif type(key) ~= "string" and type(child) == "table" then
                -- List entries such as the nameplate roster: walk them, name them by position only.
                Walk(child, path .. "[]", depth + 1)
            end
        end
    end

    Walk(addon, "addon", 0)
    return functions, frames
end

local function FunctionTime(fn, withCalls)
    local ok, ms = pcall(GetFunctionCPUUsage, fn, withCalls)
    return ok and Number(ms) or 0
end

local function SortedTop(list, key, limit)
    table.sort(list, function(a, b) return a[key] > b[key] end)
    local out = {}
    for i = 1, math.min(limit, #list) do
        if list[i][key] < MIN_REPORTED_MS then break end
        out[#out + 1] = list[i]
    end
    return out
end

local function VisiblePlates()
    local plates = addon.Nameplates and addon.Nameplates.module and addon.Nameplates.module.plates
    local count = 0
    for _, data in pairs(plates or {}) do
        local plate = data.plate
        if plate and plate:IsShown() then count = count + 1 end
    end
    return count
end

local function Report(elapsed, frameRates)
    UpdateAddOnCPUUsage()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local function PerSecond(ms) return ms / elapsed end

    local fpsSum, fpsMin = 0, math.huge
    for _, fps in ipairs(frameRates) do
        fpsSum = fpsSum + fps
        if fps < fpsMin then fpsMin = fps end
    end
    local fpsAverage = #frameRates > 0 and fpsSum / #frameRates or 0
    local addonMs = Number(GetAddOnCPUUsage("MistUI"))

    Add(string.format("time %s, zone '%s', window %.1f s, fps average %.1f, lowest %.1f", date(TIME_FORMAT),
        tostring((GetRealZoneText())), elapsed, fpsAverage, #frameRates > 0 and fpsMin or 0))
    Add(string.format("plates shown %d, nameplate module %s, in combat %s", VisiblePlates(),
        addon.Nameplates and addon.Nameplates.module and addon.Nameplates.module.applied and "on" or "off",
        tostring(InCombatLockdown() and true or false)))
    Add(string.format("MistUI total %.1f ms (%.2f ms per second)", addonMs, PerSecond(addonMs)))

    local functions, frames = CollectFunctions()
    for _, entry in ipairs(functions) do
        entry.self = FunctionTime(entry.fn, false)
        entry.total = FunctionTime(entry.fn, true)
    end

    Add("--- functions by own time (ms, ms per second, path) ---")
    for _, entry in ipairs(SortedTop(functions, "self", TOP_FUNCTIONS)) do
        Add(string.format("%8.1f %7.2f  %s", entry.self, PerSecond(entry.self), entry.path))
    end
    Add("--- functions with what they call (ms, ms per second, path) ---")
    for _, entry in ipairs(SortedTop(functions, "total", TOP_FUNCTIONS)) do
        Add(string.format("%8.1f %7.2f  %s", entry.total, PerSecond(entry.total), entry.path))
    end

    for _, entry in ipairs(frames) do
        local ok, ms = pcall(GetFrameCPUUsage, entry.frame, false)
        entry.ms = ok and Number(ms) or 0
    end
    Add("--- frames, scripts only (ms, ms per second, path) ---")
    for _, entry in ipairs(SortedTop(frames, "ms", TOP_FRAMES)) do
        Add(string.format("%8.1f %7.2f  %s", entry.ms, PerSecond(entry.ms), entry.path))
    end

    Add("--- events, all addons (ms, count) ---")
    for _, event in ipairs(EVENTS) do
        local ok, ms, count = pcall(GetEventCPUUsage, event)
        if ok and Number(ms) >= MIN_REPORTED_MS then
            Add(string.format("%8.1f %6d  %s", Number(ms), Number(count), event))
        end
    end

    local saved = _G[SAVED_VARIABLE]
    if type(saved) == "table" then
        saved.perfReport = lines
    end
    for i = 1, math.min(CHAT_LINES, #lines) do
        print("  " .. lines[i])
    end
    addon:Print(string.format("Measurement done, %d lines saved. Type /reload so they are written to disk.", #lines))
end

function Perf.Run()
    if running then
        addon:Print("A measurement is already running.")
        return
    end
    if GetCVar("scriptProfile") ~= "1" then
        addon:Print("Timing is off. Type /console scriptProfile 1 and then /reload, stand where the game is slow,"
            .. " and type /mist perf again. Afterwards: /console scriptProfile 0 and /reload, because timing slows"
            .. " every addon down.")
        return
    end
    running = true
    ResetCPUUsage()
    local elapsed, frameRates = 0, {}
    timer = timer or CreateFrame("Frame")
    timer:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        frameRates[#frameRates + 1] = GetFramerate()
        if elapsed >= WINDOW_SECONDS then
            self:SetScript("OnUpdate", nil)
            running = false
            Report(elapsed, frameRates)
        end
    end)
    addon:Print(string.format("Measuring for %d seconds. Play normally and stay in this zone.", WINDOW_SECONDS))
end
