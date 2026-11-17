function StockFunction()
    local health = UnitHealth("player")
    select(1, CreateFrame("Frame", nil, UIParent))
    return health
end
local known = GetCVar("knowncvar")
SetCVar("knowncvar", known)
