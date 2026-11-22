local addon = select(2, ...)
local L = addon.L

-- Helper found by its body, whatever its name.
local function Translate(key, fallback)
    return (L and L[key]) or fallback or key
end
print(Translate("Known helper text"), Translate("Missing helper text", "x"))

-- Key table read through a local, as a lazy proxy does.
local KEYS = {
    Good = "Known table text",
    Bad = "Missing table text",
}
local proxy = setmetatable({}, {
    __index = function(_, name)
        local text = KEYS[name]
        return text and addon.L[text] or nil
    end,
})

-- Rows whose field is used as the key.
local ROWS = {
    { title = "Known row text", size = "not a text" },
    { title = "Missing row text", size = "not a text either" },
}
for _, row in ipairs(ROWS) do
    print(L[row.title])
end

-- Not used as a key: stays unreported.
local UNRELATED = { Name = "Unrelated text" }
print(UNRELATED.Name)
