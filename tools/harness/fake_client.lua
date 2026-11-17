-- A fake 5.4.8 game environment for loading the addon outside the client.
-- It models frames, scripts, events and timers well enough to run addon code paths, and
-- answers everything else with stand-ins so the run reaches the code under test. It cannot
-- show how anything looks, and it knows nothing about taint.

local H = {}
_G.__harness = H

H.now = 1000
H.errors = {}
H.unknownGlobals = {}
H.eventFrames = {}
H.updateFrames = {}
H.animations = {}
H.currentPhase = "load"

-- ---------------------------------------------------------------------------
-- Errors
-- ---------------------------------------------------------------------------

local function Trace(err)
    return debug.traceback(tostring(err), 2)
end

function H.Report(where, err)
    local key = tostring(err)
    for _, e in ipairs(H.errors) do
        if e.key == key then
            e.count = e.count + 1
            return
        end
    end
    H.errors[#H.errors + 1] = { key = key, where = where, phase = H.currentPhase, trace = err, count = 1 }
end

function H.Call(where, fn, ...)
    local args = { ... }
    local n = select("#", ...)
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, Trace)
    if not ok then
        H.Report(where, err)
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- Stand-ins: callable and indexable values for things the fake does not model
-- ---------------------------------------------------------------------------

local stubMT = {}
local function Stub(name)
    return setmetatable({ __stubName = name }, stubMT)
end
H.Stub = Stub
stubMT.__index = function(t, k)
    if k == "__stubName" then return nil end
    local v = Stub(rawget(t, "__stubName") .. "." .. tostring(k))
    rawset(t, k, v)
    return v
end
stubMT.__call = function() return nil end
stubMT.__tostring = function(t) return "stub:" .. tostring(rawget(t, "__stubName")) end
stubMT.__concat = function(a, b) return tostring(a) .. tostring(b) end
H.IsStub = function(v) return type(v) == "table" and getmetatable(v) == stubMT end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

local Widget = {}
local widgetMT = {}
local allByName = {}
H.allByName = allByName

local function Unpack(t) return unpack(t, 1, t.n or #t) end

local function FireScript(obj, script, ...)
    local s = obj.__scripts and obj.__scripts[script]
    if s then
        H.Call(script .. " of " .. (obj.__name or obj.__type), s, obj, ...)
    end
end
H.FireScript = FireScript

local FRAME_TYPES = {
    Frame = true, Button = true, CheckButton = true, StatusBar = true, Slider = true, EditBox = true,
    ScrollFrame = true, Cooldown = true, GameTooltip = true, MessageFrame = true, ScrollingMessageFrame = true,
    Model = true, PlayerModel = true, Minimap = true, ColorSelect = true, SimpleHTML = true, MovieFrame = true,
    DressUpModel = true, TabardModel = true,
    QuestPOIFrame = true, ArchaeologyDigSiteFrame = true, ScenarioPOIFrame = true,
}

local function NewObject(objType, name, parent, template)
    local obj = setmetatable({}, widgetMT)
    rawset(obj, 0, newproxy()) -- the game keeps a userdata at key 0
    obj.__type = objType
    obj.__name = name
    obj.__parent = parent
    obj.__shown = true
    obj.__alpha = 1
    obj.__scale = 1
    obj.__width, obj.__height = 0, 0
    obj.__points = {}
    obj.__scripts = {}
    obj.__children = {}
    obj.__regions = {}
    obj.__attributes = {}
    obj.__level = parent and parent.__level and parent.__level + 1 or 1
    obj.__strata = parent and parent.__strata or "MEDIUM"
    obj.__template = template
    obj.__isFrame = FRAME_TYPES[objType] or false
    obj.__min, obj.__max, obj.__value = 0, 1, 0
    obj.__text = nil
    obj.__id = 0
    if parent and rawget(parent, "__children") then
        if obj.__isFrame then
            table.insert(parent.__children, obj)
        else
            table.insert(parent.__regions, obj)
        end
    end
    if name then
        allByName[name] = obj
        rawset(_G, name, obj)
    end
    return obj
end
H.NewObject = NewObject

local function ResolveName(name, parent)
    if name and parent and name:find("$parent", 1, true) then
        name = name:gsub("%$parent", parent.__name or "")
    end
    return name
end

-- Unknown keys are nil, as in the game. A call to a widget method the fake lacks then fails
-- with "attempt to call method"; the report lists those apart from the other errors.
widgetMT.__index = Widget

-- A widget method the fake lacks but whose name is in the client program does nothing; any
-- other one is nil, so a call to a method of a later client fails here as it would in game.
local METHOD_PREFIX = { "Set", "Get", "Is", "Has", "Can", "Enable", "Disable", "Clear", "Register", "Unregister",
    "Start", "Stop", "Lock", "Unlock", "Add", "Insert", "Scroll", "Update", "Refresh", "Draw" }
local function noop() end
setmetatable(Widget, { __index = function(_, key)
    if type(key) ~= "string" or not (H.clientNames and H.clientNames[key]) then return nil end
    for _, prefix in ipairs(METHOD_PREFIX) do
        if key:sub(1, #prefix) == prefix and key:sub(#prefix + 1, #prefix + 1):match("%u") then
            H.unknownGlobals["method " .. key] = (H.unknownGlobals["method " .. key] or 0) + 1
            return noop
        end
    end
    return nil
end })

-- Widget methods whose effect the fake does not need: setters that change nothing it reads.
for _, name in ipairs({
    "SetMovable", "SetResizable", "SetToplevel", "SetHitRectInsets", "SetClampedToScreen", "SetClampRectInsets",
    "SetFading", "SetUserPlaced", "SetMinResize", "SetMaxResize", "StartMoving", "StartSizing",
    "StopMovingOrSizing", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetHorizTile",
    "SetVertTile", "SetGradient", "SetGradientAlpha", "SetRotation", "SetDontSavePosition", "EnableMouseWheel",
    "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetMaxLetters", "SetMaxBytes", "SetFocus",
    "ClearFocus", "HighlightText", "SetMultiLine", "SetNumeric", "SetTextInsets", "SetReverse", "SetDrawEdge",
    "SetOrientation", "SetRotatesTexture", "SetHyperlinksEnabled", "SetMaxLines", "SetFadeDuration",
    "SetTimeVisible", "AddMessage", "Clear", "ScrollToBottom", "ScrollToTop", "SetValueStep",
    "SetStepsPerPage", "SetThumbTexture", "UpdateScrollChildRect", "SetVerticalScroll", "SetHorizontalScroll",
    "SetModel", "SetUnit", "SetPortraitZoom", "SetCamera", "ClearModel", "SetFacing", "SetPosition", "SetSequence",
    "SetDisplayInfo", "SetCreature", "SetButtonState", "LockHighlight", "UnlockHighlight",
    "SetMotionScriptsWhileDisabled", "SetDisabledFontObject", "SetNormalFontObject", "SetHighlightFontObject",
    "SetPushedTextOffset", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetDepth", "SetCountInvisibleLetters", "SetHistoryLines", "AddHistoryLine", "SetAltArrowKeyMode", "SetBlinkSpeed",
    "SetCursorPosition", "Insert", "SetSpacing", "SetChecked", "SetDisabledCheckedTexture",
    "SetNonBlocking", "SetLight", "SetBlipTexture", "SetIconTexture",
    "SetPlayerTexture", "SetCorpsePOIArrowTexture", "SetPOIArrowTexture", "SetStaticPOIArrowTexture", "SetZoom",
    "SetArchBlobRingScalar", "SetQuestBlobRingScalar", "SetPadding", "SetMinimumWidth", "SetSmoothing", "SetChange", "SetOrder", "SetStartDelay", "SetEndDelay",
    "SetOffset", "SetDegrees", "SetOrigin", "SetInsertMode", "EnableDrawLayer", "DisableDrawLayer", }) do
    if not Widget[name] then Widget[name] = function() end end
end
function Widget:IsMouseOver() return nil end
function Widget:IsDragging() return nil end
function Widget:IsMovable() return nil end
function Widget:IsUserPlaced() return nil end
function Widget:IsToplevel() return nil end
function Widget:IsClampedToScreen() return nil end
function Widget:HasFocus() return nil end
function Widget:GetPushedTextOffset() return 1, -1 end
function Widget:GetHitRectInsets() return 0, 0, 0, 0 end
function Widget:SetThumbTexture(t)
    local tex = rawget(self, "__thumb") or self:CreateTexture()
    if type(t) == "table" then tex = t else tex.__texture = t end
    self.__thumb = tex
end
function Widget:GetThumbTexture() if not rawget(self, "__thumb") then self:SetThumbTexture() end return self.__thumb end
function Widget:GetBackdrop() return nil end
function Widget:GetBackdropColor() return 0, 0, 0, 1 end
function Widget:GetBackdropBorderColor() return 1, 1, 1, 1 end
function Widget:GetButtonState() return "NORMAL" end
function Widget:GetNumLetters() return #(self.__text or "") end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:GetHorizontalScroll() return 0 end
function Widget:SetScrollChild(c) self.__scrollChild = c end
function Widget:GetScrollChild() return self.__scrollChild end
function Widget:GetFontObject() return self.__fontObject end
function Widget:SetFontString(fs) self.__fontString = fs end
function Widget:GetMinResize() return 0, 0 end
function Widget:GetMaxResize() return 0, 0 end
function Widget:GetModel() return nil end
function Widget:GetFacing() return 0 end
function Widget:IsForbidden() return nil end
function Widget:CanChangeProtectedState() return 1 end
function Widget:GetDebugName() return self.__name or self.__type end
function Widget:GetFrameType() return self.__type end
function Widget:GetZoom() return 0 end
function Widget:GetZoomLevels() return 5 end
function Widget:GetPingPosition() return 0, 0 end
function Widget:GetLooping() return self.__looping or "NONE" end
function Widget:GetChange() return 0 end
function Widget:GetProgress() return 0 end
function Widget:GetElapsed() return 0 end
function Widget:GetCursorPosition() return 0 end
function Widget:GetMaxLetters() return 0 end
function Widget:GetNumber() return tonumber(self.__text) end
function Widget:SetNumber(n) self.__text = tostring(n) end
function Widget:IsNumeric() return nil end
function Widget:IsMultiLine() return nil end
function Widget:IsAutoFocus() return nil end
function Widget:GetInsertMode() return "TOP" end

-- Geometry and visibility
function Widget:GetName() return self.__name end
function Widget:GetObjectType() return self.__type end
function Widget:IsObjectType(t) return self.__type == t or (t == "Frame" and self.__isFrame) or (t == "Region") end
function Widget:GetParent() return self.__parent end
function Widget:SetParent(p)
    if type(p) == "string" then p = _G[p] end
    self.__parent = p
end
function Widget:Show()
    if not self.__shown then
        self.__shown = true
        if self:IsVisible() then FireScript(self, "OnShow") end
    end
end
function Widget:Hide()
    if self.__shown then
        local wasVisible = self:IsVisible()
        self.__shown = false
        if wasVisible then FireScript(self, "OnHide") end
    end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown and 1 or nil end
function Widget:IsVisible()
    local o = self
    while o do
        if type(o) ~= "table" or H.IsStub(o) then return 1 end
        if not o.__shown then return nil end
        o = o.__parent
    end
    return 1
end
function Widget:SetAlpha(a) self.__alpha = a end
function Widget:GetAlpha() return self.__alpha end
function Widget:GetEffectiveAlpha() return self.__alpha end
function Widget:SetScale(s) self.__scale = s end
function Widget:GetScale() return self.__scale end
function Widget:GetEffectiveScale() return self.__scale end
function Widget:SetWidth(w) self.__width = w end
function Widget:SetHeight(h) self.__height = h end
function Widget:SetSize(w, h) self.__width, self.__height = w, h or w end
function Widget:GetWidth() return self.__width end
function Widget:GetHeight() return self.__height end
function Widget:GetSize() return self.__width, self.__height end
function Widget:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    if type(rel) == "string" then rel = _G[rel] end
    local entry = { point, rel or self.__parent, relPoint or point, x or 0, y or 0 }
    -- As in the client: setting a point the frame already has replaces that anchor.
    for index, existing in ipairs(self.__points) do
        if existing[1] == point then
            self.__points[index] = entry
            return
        end
    end
    table.insert(self.__points, entry)
end
function Widget:SetAllPoints(rel) self.__points = { { "TOPLEFT", rel or self.__parent, "TOPLEFT", 0, 0 },
    { "BOTTOMRIGHT", rel or self.__parent, "BOTTOMRIGHT", 0, 0 } } end
function Widget:ClearAllPoints() self.__points = {} end
function Widget:GetNumPoints() return #self.__points end
function Widget:GetPoint(i) local p = self.__points[i or 1]; if p then return Unpack(p) end end
function Widget:GetLeft() return 100 end
function Widget:GetRight() return 100 + self.__width end
function Widget:GetTop() return 400 + self.__height end
function Widget:GetBottom() return 400 end
function Widget:GetCenter() return 100 + self.__width / 2, 400 + self.__height / 2 end
function Widget:GetRect() return 100, 400, self.__width, self.__height end
function Widget:GetBoundsRect() return 100, 400, self.__width, self.__height end

-- Frame structure and scripts
function Widget:GetChildren() return unpack(self.__children) end
function Widget:GetNumChildren() return #self.__children end
function Widget:GetRegions() return unpack(self.__regions) end
function Widget:GetNumRegions() return #self.__regions end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:GetFrameLevel() return self.__level end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetFrameStrata() return self.__strata end
function Widget:SetID(id) self.__id = id end
function Widget:GetID() return self.__id end
function Widget:SetScript(name, fn) self.__scripts[name] = fn
    if name == "OnUpdate" then H.updateFrames[self] = fn and true or nil end end
function Widget:GetScript(name) return self.__scripts[name] end
function Widget:HasScript() return true end
function Widget:HookScript(name, fn)
    local old = self.__scripts[name]
    if old then
        self.__scripts[name] = function(...) old(...); return fn(...) end
    else
        self.__scripts[name] = fn
    end
    if name == "OnUpdate" then H.updateFrames[self] = true end
end
function Widget:RegisterEvent(event)
    if type(event) ~= "string" then error("RegisterEvent: event name expected", 2) end
    H.eventFrames[event] = H.eventFrames[event] or {}
    H.eventFrames[event][self] = true
end
Widget.RegisterUnitEvent = Widget.RegisterEvent
function Widget:UnregisterEvent(event) if H.eventFrames[event] then H.eventFrames[event][self] = nil end end
function Widget:UnregisterAllEvents() for _, set in pairs(H.eventFrames) do set[self] = nil end end
function Widget:IsEventRegistered(event) return H.eventFrames[event] and H.eventFrames[event][self] and 1 or nil end
function Widget:EnableMouse(v) self.__mouse = v end
function Widget:IsMouseEnabled() return self.__mouse and 1 or nil end
function Widget:SetAttribute(k, v) self.__attributes[k] = v end
function Widget:GetAttribute(k) return self.__attributes[k] end
function Widget:IsProtected() return nil end
function Widget:Raise() end
function Widget:Lower() end

-- Regions
function Widget:CreateTexture(name, layer, template, sub)
    local t = NewObject("Texture", ResolveName(name, self), self, template)
    t.__layer, t.__sublevel = layer or "ARTWORK", sub or 0
    return t
end
function Widget:CreateFontString(name, layer, template)
    local t = NewObject("FontString", ResolveName(name, self), self, template)
    t.__layer, t.__sublevel = layer or "ARTWORK", 0
    return t
end
function Widget:SetDrawLayer(layer, sub)
    if sub and (sub < -8 or sub > 7) then error("SetDrawLayer: sublevel out of range", 2) end
    self.__layer, self.__sublevel = layer, sub or 0
end
function Widget:GetDrawLayer() return self.__layer, self.__sublevel end
function Widget:SetTexture(t, ...) self.__texture = t; return 1 end
function Widget:GetTexture() return self.__texture end
function Widget:SetTexCoord(...) self.__texcoord = { ... } end
function Widget:GetTexCoord()
    local c = self.__texcoord
    if not c or #c == 0 then return 0, 0, 0, 1, 1, 0, 1, 1 end
    if #c == 4 then return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4] end
    return unpack(c)
end
function Widget:SetVertexColor(r, g, b, a) self.__color = { r, g, b, a or 1 } end
function Widget:GetVertexColor() local c = self.__color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Widget:SetTextColor(r, g, b, a) self.__color = { r, g, b, a or 1 } end
Widget.GetTextColor = Widget.GetVertexColor
function Widget:SetText(t) self.__text = t ~= nil and tostring(t) or nil end
function Widget:SetFormattedText(f, ...) self.__text = string.format(f, ...) end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return self.__text and #self.__text * 6 or 0 end
function Widget:GetStringHeight() return 12 end
function Widget:GetTextWidth() return self.__text and #self.__text * 6 or 0 end
function Widget:GetTextHeight() return 12 end
function Widget:SetFont(path, size, flags) self.__font = { path, size, flags }; return 1 end
function Widget:GetFont() local f = self.__font or { "Fonts\\FRIZQT__.TTF", 12, "" }; return f[1], f[2], f[3] end
function Widget:SetFontObject(o) self.__fontObject = o end
function Widget:GetFontObject() return self.__fontObject end
function Widget:SetBlendMode(m) self.__blend = m end
function Widget:GetBlendMode() return self.__blend or "BLEND" end
function Widget:SetDesaturated(v) self.__desat = v; return 1 end
function Widget:IsDesaturated() return self.__desat and 1 or nil end

-- Buttons and bars
-- On 5.4.8, setting a state texture to "" or nil leaves the button without one, and the getter
-- then returns nil (seen in game: bagster_frame.lua, 2026-11-11). Older clients made an empty
-- texture. `false` marks that cleared state; a slot never set still answers with a stand-in,
-- because the fake does not build the textures that XML templates declare.
local function ButtonTexture(self, kind, tex)
    if type(tex) == "table" then self[kind] = tex; return end
    if tex == nil or tex == "" then self[kind] = false; return end
    local t = rawget(self, kind) or self:CreateTexture()
    t.__texture = tex
    self[kind] = t
end
local function GetButtonTexture(self, kind)
    local t = rawget(self, kind)
    if t == false then return nil end
    if t == nil then
        t = self:CreateTexture()
        self[kind] = t
    end
    return t
end
function Widget:SetNormalTexture(t) ButtonTexture(self, "__normal", t) end
function Widget:SetPushedTexture(t) ButtonTexture(self, "__pushed", t) end
function Widget:SetHighlightTexture(t) ButtonTexture(self, "__highlight", t) end
function Widget:SetCheckedTexture(t) ButtonTexture(self, "__checked", t) end
function Widget:SetDisabledTexture(t) ButtonTexture(self, "__disabled", t) end
function Widget:GetNormalTexture() return GetButtonTexture(self, "__normal") end
function Widget:GetPushedTexture() return GetButtonTexture(self, "__pushed") end
function Widget:GetHighlightTexture() return GetButtonTexture(self, "__highlight") end
function Widget:GetCheckedTexture() return GetButtonTexture(self, "__checked") end
function Widget:GetDisabledTexture() return GetButtonTexture(self, "__disabled") end
function Widget:GetFontString() if not rawget(self, "__fontString") then self.__fontString = self:CreateFontString() end return self.__fontString end
function Widget:SetChecked(v) self.__checkedState = v and v ~= 0 end
function Widget:GetChecked() return self.__checkedState and 1 or nil end
function Widget:Enable() self.__disabledState = false end
function Widget:Disable() self.__disabledState = true end
function Widget:IsEnabled() return not self.__disabledState and 1 or nil end
function Widget:Click(button) FireScript(self, "OnClick", button or "LeftButton", false) end
function Widget:RegisterForClicks() end
function Widget:RegisterForDrag() end
function Widget:SetStatusBarTexture(t)
    local tex = rawget(self, "__barTexture") or self:CreateTexture()
    if type(t) == "table" then tex = t else tex.__texture = t end
    self.__barTexture = tex
end
function Widget:GetStatusBarTexture() if not rawget(self, "__barTexture") then self:SetStatusBarTexture() end return self.__barTexture end
function Widget:SetStatusBarColor(r, g, b, a) self.__barColor = { r, g, b, a or 1 } end
function Widget:GetStatusBarColor() local c = self.__barColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Widget:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function Widget:GetMinMaxValues() return self.__min, self.__max end
function Widget:SetValue(v)
    local changed = v ~= self.__value
    self.__value = v
    if changed then FireScript(self, "OnValueChanged", v) end
end
function Widget:GetValue() return self.__value end
function Widget:SetCooldown(start, duration) self.__cd = { start, duration } end
function Widget:GetCooldownTimes() local c = self.__cd or { 0, 0 }; return c[1] * 1000, c[2] * 1000 end

-- Animations (the timer library runs on them)
function Widget:CreateAnimationGroup(name)
    local g = NewObject("AnimationGroup", name, self)
    g.__anims = {}
    return g
end
function Widget:CreateAnimation(kind, name)
    local a = NewObject(kind or "Animation", name, self)
    a.__duration = 0
    table.insert(self.__anims or {}, a)
    if self.__anims then self.__anims[#self.__anims] = a end
    return a
end
function Widget:SetDuration(d) self.__duration = d end
function Widget:GetDuration() return self.__duration or 0 end
function Widget:SetLooping(l) self.__looping = l end
function Widget:Play() self.__playing = true; self.__started = H.now; H.animations[self] = true end
function Widget:Stop() self.__playing = false; H.animations[self] = nil end
function Widget:IsPlaying() return self.__playing and 1 or nil end
function Widget:Finish() self:Stop() end

-- Tooltips
function Widget:SetOwner(owner) self.__owner = owner; self.__lines = {} end
function Widget:GetOwner() return self.__owner end
function Widget:AddLine(t) self.__lines = self.__lines or {}; table.insert(self.__lines, t) end
function Widget:AddDoubleLine(a) self:AddLine(a) end
function Widget:NumLines() return #(self.__lines or {}) end
function Widget:ClearLines() self.__lines = {} end
function Widget:IsOwned(o) return self.__owner == o and 1 or nil end

H.Widget = Widget
H.widgetMT = widgetMT

-- ---------------------------------------------------------------------------
-- CreateFrame and stock frames
-- ---------------------------------------------------------------------------

-- Children a template declares, made with the frame: "$parent" names and parentKey fields.
-- Template data comes from the stock XML (H.stock.templates) and the addon's own XML.
-- Scripts the XML declares exist on the frame; the fake does not run their stock code.
local function DeclaredScript() end
local function SetDeclaredScripts(obj, scripts)
    for _, name in ipairs(scripts or {}) do
        if not obj.__scripts[name] then obj.__scripts[name] = DeclaredScript end
    end
end

local function ApplyTemplates(obj, templates, depth)
    if not templates or depth > 8 then return end
    for tmplName in tostring(templates):gmatch("[^,%s]+") do
        local tmpl = H.stock.templates[tmplName]
        if tmpl then
            ApplyTemplates(obj, tmpl.inherits, depth + 1)
            SetDeclaredScripts(obj, tmpl.scripts)
            for _, child in ipairs(tmpl.children) do
                local parent = obj
                if child.parentPath ~= "" then
                    parent = obj.__byPath and obj.__byPath[child.parentPath] or obj
                end
                local name = child.name and obj.__name and child.name:gsub("%$parent", obj.__name) or nil
                local c
                if child.type == "Texture" or child.type == "FontString" then
                    c = NewObject(child.type, name, parent, child.inherits)
                else
                    c = NewObject(child.type, name, parent, child.inherits)
                    ApplyTemplates(c, child.inherits, depth + 1)
                end
                c.__shown = not child.hidden
                SetDeclaredScripts(c, child.scripts)
                if child.parentKey then rawset(parent, child.parentKey, c) end
                if child.slot then rawset(parent, child.slot, c) end
                obj.__byPath = obj.__byPath or {}
                obj.__byPath[child.path] = c
            end
        end
    end
end

function _G.CreateFrame(frameType, name, parent, template)
    if type(frameType) ~= "string" then error("CreateFrame: frame type expected", 2) end
    if type(parent) == "string" then parent = _G[parent] end
    if H.IsStub(parent) then parent = nil end
    name = ResolveName(name, parent)
    local f = NewObject(frameType, name, parent, template)
    ApplyTemplates(f, template, 0)
    return f
end

-- Stock frames are made on first use, with the type and templates the stock XML gives them.
function H.StockFrame(name)
    local info = H.stock.frames[name]
    if not info then return nil end
    local existing = rawget(_G, name)
    if existing then return existing end
    local parent = info.parent and (rawget(_G, info.parent) or H.StockFrame(info.parent)) or nil
    local f = NewObject(info.type, name, parent, info.inherits)
    f.__stock = true
    f.__shown = not info.hidden
    ApplyTemplates(f, info.inherits, 0)
    SetDeclaredScripts(f, info.scripts)
    for _, k in ipairs(info.keys or {}) do
        local child = k.name and (rawget(_G, k.name) or H.StockFrame(k.name))
        if not child then
            child = NewObject(k.type, nil, f, k.inherits)
            child.__shown = not k.hidden
            ApplyTemplates(child, k.inherits, 0)
            SetDeclaredScripts(child, k.scripts)
        end
        if k.key then rawset(f, k.key, child) end
        if k.slot then rawset(f, k.slot, child) end
    end
    return f
end

-- Tooltip setters (the tooltip module hooks several of them)
for _, name in ipairs({
    "SetAction", "SetShapeshift", "SetHyperlink", "SetUnit", "SetBagItem", "SetInventoryItem", "SetSpellByID",
    "SetSpellBookItem", "SetPetAction", "SetGuildBankItem", "SetLootItem", "SetLootRollItem", "SetMerchantItem",
    "SetQuestItem", "SetQuestLogItem", "SetTradePlayerItem", "SetTradeTargetItem", "SetUnitAura", "SetUnitBuff",
    "SetUnitDebuff", "SetTotem", "SetItemByID", "SetToyByItemID", "SetCurrencyToken", "SetBackpackToken",
    "SetMinimumWidth", "SetPadding", "SetAnchorType", "FadeOut", "AppendText", "SetSendMailItem",
    "SetInboxItem", "SetAuctionItem", "SetAuctionSellItem", "SetCraftItem", "SetTradeSkillItem",
    "SetPossession", "SetTalent", "SetGlyph", "SetEquipmentSet", "SetHyperlinkCompareItem", "SetBuybackItem",
    "SetExistingSocketGem", "SetSocketGem", "SetSocketedItem", "SetRecipeResultItem", "SetCompareItem",
    "SetMountBySpellID", "SetCurrencyByID", "SetQuestCurrency", "SetQuestLogCurrency", "SetQuestLogRewardSpell",
    "SetQuestRewardSpell", "SetVoidItem", "SetVoidDepositItem", "SetVoidWithdrawalItem", "SetTrainerService",
    "SetBattlePet",
}) do
    if not Widget[name] then Widget[name] = function() end end
end
function Widget:GetItem() return nil end
function Widget:GetSpell() return nil end
function Widget:GetUnit() return nil end

-- Secure handler methods the stock templates add
for _, name in ipairs({ "SetFrameRef", "Execute", "WrapScript", "UnwrapScript", "SetAttributeNoHandler" }) do
    Widget[name] = function() end
end
function Widget:CreateTitleRegion() return NewObject("Frame", nil, self) end
function Widget:GetTitleRegion() return nil end

-- Fonts (CreateFont and the stock font objects)
function _G.CreateFont(name)
    local f = NewObject("Font", name)
    return f
end
function Widget:CopyFontObject(other)
    if type(other) == "string" then other = _G[other] end
    if type(other) == "table" and other.__font then self.__font = { other.__font[1], other.__font[2], other.__font[3] } end
end
function Widget:SetShadowColor() end
function Widget:SetShadowOffset() end
function Widget:GetShadowColor() return 0, 0, 0, 1 end
function Widget:GetShadowOffset() return 1, -1 end
function Widget:SetJustifyH(j) self.__justifyH = j end
function Widget:SetJustifyV(j) self.__justifyV = j end
function Widget:GetJustifyH() return self.__justifyH or "CENTER" end
function Widget:GetJustifyV() return self.__justifyV or "MIDDLE" end
function Widget:SetWordWrap() end
function Widget:SetNonSpaceWrap() end
function Widget:SetSpacing() end

-- ---------------------------------------------------------------------------
-- Global fallback
-- ---------------------------------------------------------------------------

H.realGlobals = {}
setmetatable(_G, {
    __index = function(t, k)
        if type(k) ~= "string" then return nil end
        local stock = H.stock
        if stock then
            if stock.frames[k] then
                return H.StockFrame(k)
            end
            -- A child a template gives a stock frame ("ActionButton1Cooldown") exists once its
            -- frame does: make the longest stock frame its name starts with.
            for i = #k - 1, 3, -1 do
                local prefix = k:sub(1, i)
                if stock.frames[prefix] and not rawget(t, prefix) then
                    H.StockFrame(prefix)
                    local v = rawget(t, k)
                    if v ~= nil then return v end
                    break
                end
            end
            if stock.functions[k] then
                local f = function() return nil end
                rawset(t, k, f)
                return f
            end
        end
        -- Unknown names stay nil when they look like addon or optional globals.
        if not k:match("^[%u_]") then return nil end
        H.unknownGlobals[k] = (H.unknownGlobals[k] or 0) + 1
        return nil
    end,
})

return H
