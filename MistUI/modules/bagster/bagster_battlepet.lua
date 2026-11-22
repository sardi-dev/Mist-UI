-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- Caged battle pets are not items: their link is battlepet:species:level:quality:health:power:speed:id,
-- so GetItemInfo, GetItemIcon and item tooltips know nothing about them. The stock windows read the
-- pet details from the slot tooltip call instead; saved slots of other characters only have the link.
local addon = select(2, ...)

local tonumber, type = tonumber, type
local strfind, strmatch = string.find, string.match

local BattlePet = {}
addon.BagsterBattlePet = BattlePet

function BattlePet.IsLink(link)
    return type(link) == "string" and strfind(link, "battlepet:", 1, true) ~= nil
end

-- Returns species, level, quality, health, power, speed and the pet's name as typed in the link text.
function BattlePet.Parse(link)
    if not BattlePet.IsLink(link) then return nil end
    local species, level, quality, health, power, speed =
        strmatch(link, "battlepet:(%d+):(%d+):(%-?%d+):(%d+):(%d+):(%d+)")
    if not species then return nil end
    return tonumber(species), tonumber(level), tonumber(quality), tonumber(health), tonumber(power),
        tonumber(speed), strmatch(link, "%[(.-)%]")
end

function BattlePet.GetIcon(link)
    local species = BattlePet.Parse(link)
    if not species then return nil end
    return (select(2, C_PetJournal.GetPetInfoBySpeciesID(species)))
end

function BattlePet.GetQuality(link)
    return (select(3, BattlePet.Parse(link)))
end

-- Same call the stock bank and vault slots make once the slot tooltip reported a pet.
function BattlePet.ShowTooltip(link)
    local species, level, quality, health, power, speed, name = BattlePet.Parse(link)
    if not species then return false end
    BattlePetToolTip_Show(species, level, quality, health, power, speed, name)
    return true
end

function BattlePet.HideTooltip()
    if BattlePetTooltip then
        BattlePetTooltip:Hide()
    end
end
