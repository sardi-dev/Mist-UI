-- Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.

-- Edit mode helpers for dragged boxes: snap to the grid on drop, guide lines that show the snap
-- while dragging, and undo of the last moves. The grid geometry matches the one edit mode draws
-- (cells of about 32 units, split evenly from the centre of the screen).

local addon = select(2, ...)

local EditorSnap = {}
addon.EditorSnap = EditorSnap

local CELL_TARGET = 32
-- How close (in UIParent units) an edge or the centre must come to a grid line to snap to it.
local SNAP_DISTANCE = 8
local MAX_UNDO = 20
local GUIDE_COLOR = { 0.2, 0.9, 1, 0.9 }
local GUIDE_THICKNESS = 2

local undoStack = {}
local guides, dragging

function EditorSnap.IsEnabled()
    local profile = addon.db and addon.db.profile
    return not (profile and profile.editorSnapToGrid == false)
end

function EditorSnap.SetEnabled(enabled)
    if addon.db and addon.db.profile then
        if enabled then
            addon.db.profile.editorSnapToGrid = nil
        else
            addon.db.profile.editorSnapToGrid = false
        end
    end
end

-- Width and height of a grid cell, as edit mode's grid splits the screen.
function EditorSnap.CellSize()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local columns = math.max(1, math.floor(width / 2 / CELL_TARGET)) * 2
    local rows = math.max(1, math.floor(height / 2 / CELL_TARGET)) * 2
    return width / columns, height / rows
end

-- The smallest shift that puts one of the values on a line of the given spacing (lines from origin).
local function NearestShift(values, spacing, origin)
    local best
    for _, value in ipairs(values) do
        local offset = value - origin
        local shift = math.floor(offset / spacing + 0.5) * spacing - offset
        if not best or math.abs(shift) < math.abs(best) then best = shift end
    end
    if best and math.abs(best) <= SNAP_DISTANCE then return best end
    return nil
end

-- Shift (in UIParent units) that snaps the frame, and the grid line it snaps to, per axis; nil when
-- no edge or centre is close enough to a line.
function EditorSnap.Target(frame)
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, right, top, bottom = left * ratio, right * ratio, top * ratio, bottom * ratio
    local cellWidth, cellHeight = EditorSnap.CellSize()
    local screenTop = UIParent:GetHeight()
    local xs = { left, (left + right) / 2, right }
    local ys = { top, (top + bottom) / 2, bottom }
    -- Rows are counted from the top of the screen, as edit mode draws them.
    local dx = NearestShift(xs, cellWidth, 0)
    local dy = NearestShift(ys, cellHeight, screenTop)
    local guideX, guideY
    if dx then
        for _, x in ipairs(xs) do
            local line = x + dx
            if math.abs(line / cellWidth - math.floor(line / cellWidth + 0.5)) < 0.001 then guideX = line break end
        end
    end
    if dy then
        for _, y in ipairs(ys) do
            local line = y + dy
            local fromTop = (screenTop - line) / cellHeight
            if math.abs(fromTop - math.floor(fromTop + 0.5)) < 0.001 then guideY = line break end
        end
    end
    return dx, dy, guideX, guideY, ratio
end

function EditorSnap.Apply(frame)
    local dx, dy, _, _, ratio = EditorSnap.Target(frame)
    if not (dx or dy) then return false end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return false end
    frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + (dx or 0) / ratio, (y or 0) + (dy or 0) / ratio)
    return true
end

local function CreateGuides()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetAllPoints(UIParent)
    holder:SetFrameStrata("TOOLTIP")
    local vertical = holder:CreateTexture(nil, "OVERLAY")
    vertical:SetTexture(unpack(GUIDE_COLOR))
    vertical:SetWidth(GUIDE_THICKNESS)
    local horizontal = holder:CreateTexture(nil, "OVERLAY")
    horizontal:SetTexture(unpack(GUIDE_COLOR))
    horizontal:SetHeight(GUIDE_THICKNESS)
    holder.vertical, holder.horizontal = vertical, horizontal
    holder:Hide()
    holder:SetScript("OnUpdate", function(self)
        if not dragging then self:Hide() return end
        local _, _, guideX, guideY = EditorSnap.Target(dragging)
        if guideX then
            vertical:ClearAllPoints()
            vertical:SetPoint("TOP", UIParent, "TOPLEFT", guideX, 0)
            vertical:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", guideX, 0)
            vertical:Show()
        else
            vertical:Hide()
        end
        if guideY then
            horizontal:ClearAllPoints()
            horizontal:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, guideY)
            horizontal:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, guideY)
            horizontal:Show()
        else
            horizontal:Hide()
        end
    end)
    return holder
end

local function Remember(frame)
    local points = {}
    for index = 1, frame:GetNumPoints() do
        points[index] = { frame:GetPoint(index) }
    end
    undoStack[#undoStack + 1] = { frame = frame, points = points }
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
end

-- From the box's OnDragStart, after StartMoving.
function EditorSnap.BeginDrag(frame)
    Remember(frame)
    dragging = frame
    if EditorSnap.IsEnabled() then
        guides = guides or CreateGuides()
        guides:Show()
    end
end

-- From the box's OnDragStop, after StopMovingOrSizing and before the position is saved.
function EditorSnap.EndDrag(frame)
    dragging = nil
    if guides then guides:Hide() end
    if frame.MistUI_Undoing or not EditorSnap.IsEnabled() then return end
    EditorSnap.Apply(frame)
end

function EditorSnap.CanUndo()
    return #undoStack > 0
end

-- Puts the last dragged box back where it was and saves that, as its own drop would.
function EditorSnap.Undo()
    if InCombatLockdown() then return false end
    local entry = table.remove(undoStack)
    if not entry then return false end
    local frame = entry.frame
    frame:ClearAllPoints()
    for _, point in ipairs(entry.points) do
        frame:SetPoint(unpack(point))
    end
    local onDragStop = frame:GetScript("OnDragStop")
    if onDragStop then
        frame.MistUI_Undoing = true
        onDragStop(frame)
        frame.MistUI_Undoing = nil
    end
    return true
end

function EditorSnap.ClearUndo()
    wipe(undoStack)
end
