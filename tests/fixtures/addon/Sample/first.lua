local addon = select(2, ...)
_G.SampleAddon = addon
SampleDB = SampleDB or {}
function Sample_Global() return UnitHealth("player") end
local frame = CreateFrame("Frame", "SampleFrame", UIParent, "KnownTemplate, MissingTemplate")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("OLD_REMOVED_EVENT")
frame:RegisterEvent("SAMPLE_OWN_MESSAGE")
local icon = ActionButton1Icon
RemovedFunction()
addon.LoadedThing = 1
if addon.ParkedThing then addon.ParkedThing() end
local scale = GetCVar("knownCVar")
SetCVar("removedCVar", 1)
