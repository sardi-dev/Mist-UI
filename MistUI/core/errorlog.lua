-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- Keeps the most recent errors that involve MistUI in the saved settings, so a problem
-- seen in game can be read from the settings file afterwards. The client itself only
-- shows errors on screen.

local addonName, addon = ...

local SAVED_VARIABLE = "MistUIDB"
local MAX_ENTRIES = 50
local MAX_TRACE_LENGTH = 2000
local TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
-- Skips the recording function itself. The trace may still open with a line or two of this
-- file: how many levels the client's error path adds is not something to rely on.
local TRACE_LEVEL = 2

local ErrorLog = {}
addon.ErrorLog = ErrorLog

-- Errors collect here until the saved settings have loaded; the saved list then takes over.
local entries = {}
local savedLog
local enabled = true
local session -- number of the current login or reload, known once the settings have loaded
local recording = false -- an error raised while recording one must not loop

-- Also true for MistUI_Options, whose name and file paths start with this addon's name.
local function Mentions(text)
    return type(text) == "string" and text:find(addonName, 1, true) ~= nil
end

local function Append(list, entry)
    for i = #list, 1, -1 do
        local known = list[i]
        if known.message == entry.message and known.session == entry.session then
            known.count = known.count + entry.count
            known.time = entry.time
            return
        end
    end
    while #list >= MAX_ENTRIES do
        tremove(list, 1)
    end
    list[#list + 1] = entry
end

local function Record(kind, message, wantTrace)
    message = tostring(message)
    local trace = wantTrace and debugstack(TRACE_LEVEL) or nil
    if not (Mentions(message) or Mentions(trace)) then
        return
    end
    Append(entries, {
        kind = kind,
        message = message,
        trace = type(trace) == "string" and trace:sub(1, MAX_TRACE_LENGTH) or nil,
        count = 1,
        time = date(TIME_FORMAT),
        session = session,
    })
end

-- Runs inside the client's error handling, where a second error would hide the first.
local function SafeRecord(kind, message, wantTrace)
    if not enabled or recording then
        return
    end
    recording = true
    pcall(Record, kind, message, wantTrace)
    recording = false
end

-- The settings file can be edited by hand; a malformed entry must not break the merge below.
local function DropInvalidEntries(list)
    for i = #list, 1, -1 do
        local entry = list[i]
        if type(entry) ~= "table" or type(entry.message) ~= "string" then
            tremove(list, i)
        else
            entry.count = tonumber(entry.count) or 1
        end
    end
end

local function AttachSavedLog()
    local saved = _G[SAVED_VARIABLE]
    if type(saved) ~= "table" then
        saved = {}
        _G[SAVED_VARIABLE] = saved
    end
    if type(saved.errorLog) ~= "table" then
        saved.errorLog = {}
    end
    savedLog = saved.errorLog
    if type(savedLog.entries) ~= "table" then
        savedLog.entries = {}
    end
    DropInvalidEntries(savedLog.entries)

    savedLog.sessions = (tonumber(savedLog.sessions) or 0) + 1
    session = savedLog.sessions
    enabled = savedLog.enabled ~= false

    local early = entries
    entries = savedLog.entries
    if enabled then
        for _, entry in ipairs(early) do
            entry.session = session
            Append(entries, entry)
        end
    end
end

function ErrorLog.GetEntries()
    return entries
end

function ErrorLog.IsEnabled()
    return enabled
end

function ErrorLog.SetEnabled(value)
    enabled = value and true or false
    if savedLog then
        savedLog.enabled = enabled
    end
end

function ErrorLog.Clear()
    wipe(entries)
end

-- Chained, not replaced: the error still reaches whatever showed it before. An addon that
-- installs its own handler later without chaining takes this recorder out of the path.
local previousHandler = geterrorhandler()
local forwarding = false
seterrorhandler(function(message, ...)
    SafeRecord("error", message, true)
    -- The stock error window can raise an error of its own while it shows one. Passing that one
    -- on as well sends it back into the same window, over and over, until the client's stack overflows.
    if forwarding then
        return
    end
    forwarding = true
    local ok, result = pcall(previousHandler, message, ...)
    forwarding = false
    if ok then
        return result
    end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent", function(self, event, name, protectedCall)
    if event == "ADDON_LOADED" then
        if name == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            AttachSavedLog()
        end
    elseif Mentions(name) then
        -- No trace: at this point the stack is the event delivery, not the blocked call.
        SafeRecord("blocked", string.format("%s: %s called %s", event, name, tostring(protectedCall)), false)
    end
end)
