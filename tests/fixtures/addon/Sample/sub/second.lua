local addon = select(2, ...)
local f = CreateFrame("Frame", nil, UIParent, "SampleTemplate")
Sample_Global()
SampleAddon.x = addon.LoadedThing
