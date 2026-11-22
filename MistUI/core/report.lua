-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- /mist report: everything a bug report needs (versions, which modules run, the latest
-- recorded errors) in one box to copy, so nobody has to open the saved settings file.
-- Character and realm names are left out on purpose: reports are posted in public.

local addon = select(2, ...)
local L = addon.L

local Report = {}
addon.Report = Report

local REPORT_ERRORS = 10
local TRACE_LINES = 3
local MAX_MESSAGE_LENGTH = 400
local DIALOG_WIDTH, DIALOG_HEIGHT = 560, 400
local BOX_WIDTH, BOX_HEIGHT = 484, 282

local function ModuleLists()
    local registry = addon.ModuleRegistry
    local on, off = {}, {}
    for _, name in ipairs(registry and registry:GetAll() or {}) do
        local list = registry:IsEnabled(name) and on or off
        list[#list + 1] = name
    end
    return on, off
end

-- The first few stack lines inside this addon say where an error came from.
local function AddonTraceLines(trace)
    local picked = {}
    for line in tostring(trace or ""):gmatch("[^\n]+") do
        if line:find("AddOns\\MistUI", 1, true) then
            picked[#picked + 1] = "      " .. line:gsub("^%s+", "")
            if #picked >= TRACE_LINES then
                break
            end
        end
    end
    return picked
end

function Report.Build()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end

    local version, build, _, toc = GetBuildInfo()
    Add(string.format("Mist-UI %s", GetAddOnMetadata("MistUI", "Version") or "?"))
    Add(string.format("Client %s (build %s), interface %s, locale %s",
        tostring(version), tostring(build), tostring(toc), tostring(GetLocale())))

    local on, off = ModuleLists()
    Add("Modules on: " .. (#on > 0 and table.concat(on, ", ") or "none"))
    Add("Modules off: " .. (#off > 0 and table.concat(off, ", ") or "none"))

    local log = addon.ErrorLog
    local entries = log and log.GetEntries() or {}
    Add(string.format("Errors recorded: %d (recording %s)", #entries, log and log.IsEnabled() and "on" or "off"))
    for i = math.max(1, #entries - REPORT_ERRORS + 1), #entries do
        local entry = entries[i]
        Add(string.format("  [%s] x%d %s: %s", tostring(entry.time), tonumber(entry.count) or 1,
            tostring(entry.kind or "error"), tostring(entry.message):sub(1, MAX_MESSAGE_LENGTH)))
        for _, traceLine in ipairs(AddonTraceLines(entry.trace)) do
            Add(traceLine)
        end
    end
    return table.concat(lines, "\n")
end

local dialog

local function GetDialog()
    if dialog then
        return dialog
    end
    local ui = addon.EditorUI
    dialog = addon.ForeverUI.CreateDialog("MistUI_ReportDialog", UIParent,
        { title = L["Mist-UI report"], closable = true, escClose = true })
    dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata(ui.STRATA)
    dialog:SetFrameLevel(ui.MODAL)

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", dialog.Content, "TOPLEFT", 0, 0)
    hint:SetText(L["Copy this text (Ctrl+C) into your bug report."])

    local scroll = CreateFrame("ScrollFrame", "MistUI_ReportScroll", dialog, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    scroll:SetSize(BOX_WIDTH, BOX_HEIGHT)

    local box = CreateFrame("EditBox", "MistUI_ReportBox", scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(BOX_WIDTH)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        dialog:Hide()
    end)
    -- Read only: typing puts the report back, so what is copied is always the real report.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(dialog.reportText or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(box)
    dialog.box = box
    return dialog
end

function Report.Show()
    local frame = GetDialog()
    frame.reportText = Report.Build()
    frame.box:SetText(frame.reportText)
    frame:Show()
    frame.box:SetFocus()
    frame.box:HighlightText()
end
