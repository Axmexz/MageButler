-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: spellbook discovery.
-- Everything shown in the menus comes from the player's own spellbook, matched
-- by spell ID and by localised name, so only learned spells of the player's
-- faction ever appear and the highest learned rank is always the one used.

local _, MB = ...
local Spells = MB:NewModule("Spells")
local API = MB.API

-- Reference data (classic spell IDs, which WoW Forever uses). Order is display order.
local TELEPORTS = {
    { id = 3561, faction = "Alliance" },  -- Stormwind
    { id = 3562, faction = "Alliance" },  -- Ironforge
    { id = 3565, faction = "Alliance" },  -- Darnassus
    { id = 32271, faction = "Alliance" }, -- Exodar
    { id = 49359, faction = "Alliance" }, -- Theramore
    { id = 33690, faction = "Alliance" }, -- Shattrath
    { id = 3567, faction = "Horde" },     -- Orgrimmar
    { id = 3563, faction = "Horde" },     -- Undercity
    { id = 3566, faction = "Horde" },     -- Thunder Bluff
    { id = 32272, faction = "Horde" },    -- Silvermoon
    { id = 49358, faction = "Horde" },    -- Stonard
    { id = 35715, faction = "Horde" },    -- Shattrath
    { id = 53140 },                       -- Dalaran
}

local PORTALS = {
    { id = 10059, faction = "Alliance" }, -- Stormwind
    { id = 11416, faction = "Alliance" }, -- Ironforge
    { id = 11419, faction = "Alliance" }, -- Darnassus
    { id = 32266, faction = "Alliance" }, -- Exodar
    { id = 49360, faction = "Alliance" }, -- Theramore
    { id = 33691, faction = "Alliance" }, -- Shattrath
    { id = 11417, faction = "Horde" },    -- Orgrimmar
    { id = 11418, faction = "Horde" },    -- Undercity
    { id = 11420, faction = "Horde" },    -- Thunder Bluff
    { id = 32267, faction = "Horde" },    -- Silvermoon
    { id = 49361, faction = "Horde" },    -- Stonard
    { id = 35717, faction = "Horde" },    -- Shattrath
    { id = 53142 },                       -- Dalaran
}

-- Every rank, lowest first. Used when a name lookup is not possible.
local RANKS = {
    water = { 5504, 5505, 5506, 6127, 10138, 10139, 10140, 27090, 37420 },
    food = { 587, 597, 990, 6129, 10144, 10145, 28612, 33717 },
    ritual = { 43987 },
    intellect = { 1459, 1460, 1461, 10156, 10157, 27126 },
    brilliance = { 23028, 27127 },
}
Spells.RANKS = RANKS

-- Conjure Mana Gem spells, weakest first, with the gem each one creates.
Spells.GEMS = {
    { spell = 759, item = 5514 },    -- Mana Agate
    { spell = 3552, item = 5513 },   -- Mana Jade
    { spell = 10053, item = 8007 },  -- Mana Citrine
    { spell = 10054, item = 8008 },  -- Mana Ruby
    { spell = 27101, item = 22044 }, -- Mana Emerald
}

local bookIDs = {}      -- [spellID] = true for every active spell in the book
local bookTop = {}      -- [localised name] = spellID of the highest learned rank
local teleports, portals = {}, {}
local best = {}
local signature = ""

-------------------------------------------------------------------------------
-- Spellbook scan
-------------------------------------------------------------------------------
local function ReadSpellbook()
    wipe(bookIDs)
    wipe(bookTop)

    local book = C_SpellBook
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo) then
        return false
    end

    local bank = Enum.SpellBookSpellBank.Player
    local spellType = Enum.SpellBookItemType.Spell
    local lowRanks = {}

    for line = 1, API.Num(book.GetNumSpellBookSkillLines(), 0) do
        local info = book.GetSpellBookSkillLineInfo(line)
        local offset = info and API.Num(info.itemIndexOffset)
        local count = info and API.Num(info.numSpellBookItems)
        if offset and count and not info.offSpecID then
            for slot = offset + 1, offset + count do
                local item = book.GetSpellBookItemInfo(slot, bank)
                if item and not MB.IsSecret(item.itemType) and item.itemType == spellType then
                    local spellID = API.Num(item.spellID)
                    local name = API.Str(item.name)
                    local passive = item.isPassive
                    if MB.IsSecret(passive) then passive = false end
                    if spellID and name and not passive then
                        bookIDs[spellID] = true
                        local low = false
                        if book.IsSpellBookItemLowRank then
                            low = book.IsSpellBookItemLowRank(slot, bank)
                            if MB.IsSecret(low) then low = false end
                        end
                        if low then
                            lowRanks[name] = spellID
                        else
                            bookTop[name] = spellID
                        end
                    end
                end
            end
        end
    end

    -- A spell listed only as "low rank" is still the best one available.
    for name, spellID in pairs(lowRanks) do
        if not bookTop[name] then
            bookTop[name] = spellID
        end
    end
    return true
end

--- The learned spell behind a reference ID: the ID itself when it is in the
--- book, otherwise the book entry that carries the same localised name.
local function Resolve(spellID)
    if bookIDs[spellID] then return spellID end
    local name = API.SpellName(spellID)
    if name and bookTop[name] then return bookTop[name] end
    return nil
end

local function Destination(name)
    local place = name:match(":%s*(.+)$")
    return place or name
end

local function BuildTravelList(reference, out)
    wipe(out)
    local faction = UnitFactionGroup("player")
    local seen = {}
    local prefix

    for i = 1, #reference do
        local entry = reference[i]
        local name = API.SpellName(entry.id)
        if name and not prefix then
            -- "Teleport: Stormwind" -> "Teleport:" in whatever the client language is.
            prefix = name:match("^(.-:)")
        end
        if not entry.faction or entry.faction == faction then
            local spellID = Resolve(entry.id)
            if spellID and not seen[spellID] then
                seen[spellID] = true
                name = API.SpellName(spellID) or name
                out[#out + 1] = {
                    id = spellID,
                    name = name,
                    short = name and Destination(name) or "?",
                    icon = API.SpellTexture(spellID),
                }
            end
        end
    end

    -- Destinations this table does not list yet: anything else in the book
    -- that carries the same "Teleport:" / "Portal:" prefix.
    if prefix then
        local extra = {}
        for name, spellID in pairs(bookTop) do
            if not seen[spellID] and name:sub(1, #prefix) == prefix then
                seen[spellID] = true
                extra[#extra + 1] = {
                    id = spellID,
                    name = name,
                    short = Destination(name),
                    icon = API.SpellTexture(spellID),
                }
            end
        end
        table.sort(extra, function(a, b) return a.short < b.short end)
        for i = 1, #extra do
            out[#out + 1] = extra[i]
        end
    end
end

local function HighestRank(key)
    local ranks = RANKS[key]
    -- Preferred: the spellbook's own top rank for this spell name.
    local name = API.SpellName(ranks[1])
    if name and bookTop[name] then
        return bookTop[name]
    end
    for i = #ranks, 1, -1 do
        if bookIDs[ranks[i]] or API.IsSpellKnown(ranks[i]) then
            return ranks[i]
        end
    end
    return nil
end

function Spells:Scan()
    if not ReadSpellbook() then return end

    BuildTravelList(TELEPORTS, teleports)
    BuildTravelList(PORTALS, portals)
    for key in pairs(RANKS) do
        best[key] = HighestRank(key)
    end

    -- Only announce a change when something MageButler shows actually changed.
    local parts = {}
    for i = 1, #teleports do parts[#parts + 1] = teleports[i].id end
    parts[#parts + 1] = "|"
    for i = 1, #portals do parts[#parts + 1] = portals[i].id end
    parts[#parts + 1] = "|"
    for _, key in ipairs({ "water", "food", "ritual", "intellect", "brilliance" }) do
        parts[#parts + 1] = best[key] or 0
    end
    parts[#parts + 1] = "|"
    for i = 1, #self.GEMS do
        parts[#parts + 1] = self:KnowsGem(i) and 1 or 0
    end
    local newSignature = table.concat(parts, ",")

    if newSignature ~= signature then
        signature = newSignature
        MB:Fire("SPELLS_UPDATED")
    end
end

-------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------
function Spells:GetTeleports() return teleports end
function Spells:GetPortals() return portals end

--- Highest learned rank of "water", "food", "ritual", "intellect" or "brilliance".
function Spells:GetBest(key) return best[key] end

--- The learned Conjure Mana Gem spell for an entry of Spells.GEMS, or nil.
function Spells:GemSpell(index)
    local gem = self.GEMS[index]
    if not gem then return nil end
    local spellID = Resolve(gem.spell)
    if spellID then return spellID end
    if API.IsSpellKnown(gem.spell) then return gem.spell end
    return nil
end

function Spells:KnowsGem(index)
    return self:GemSpell(index) ~= nil
end

function Spells:KnowsAnyGem()
    for i = 1, #self.GEMS do
        if self:KnowsGem(i) then return true end
    end
    return false
end

--- Whether the player has any spell that consumes the given reagent.
function Spells:UsesReagent(key)
    if key == "runeT" then return #teleports > 0 end
    if key == "runeP" then return #portals > 0 end
    if key == "powder" then return best.brilliance ~= nil or best.ritual ~= nil end
    return false
end

-------------------------------------------------------------------------------
function Spells:OnEnable()
    local function Rescan()
        MB:Debounce("spells", 0.4, function()
            Spells:Scan()
        end)
    end

    MB:RegisterEvent("SPELLS_CHANGED", Rescan)
    MB:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", Rescan)
    MB:RegisterEvent("PLAYER_LEVEL_UP", Rescan)

    self:Scan()
end
