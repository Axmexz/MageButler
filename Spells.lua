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
local knownRanks = {}   -- [key] = every rank of it the player knows, weakest first
local gemSpells = {}    -- [index into Spells.GEMS] = the learned spell, or false
local signature = ""
local SIGNATURE_KEYS = { "water", "food", "intellect", "brilliance" }

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

--- Fills `out` with every rank of a spell the player knows, weakest first.
--- The book's own top rank can be an ID the table above does not list; it is
--- still the strongest, so it goes at the end, where the ranks below it can
--- be stepped through from.
local function LearnedRanks(key, out)
    wipe(out)
    local ranks = RANKS[key]
    for i = 1, #ranks do
        local spellID = ranks[i]
        if bookIDs[spellID] or API.IsSpellKnown(spellID) then
            out[#out + 1] = spellID
        end
    end
    local top = best[key]
    if top then
        for i = 1, #out do
            if out[i] == top then return out end
        end
        out[#out + 1] = top
    end
    return out
end

function Spells:Scan()
    if not ReadSpellbook() then return end

    BuildTravelList(TELEPORTS, teleports)
    BuildTravelList(PORTALS, portals)
    for key in pairs(RANKS) do
        best[key] = HighestRank(key)
        knownRanks[key] = LearnedRanks(key, knownRanks[key] or {})
    end
    -- Which gems can be conjured is asked on every redraw, so it is worked
    -- out here, once per scan, like everything else that comes from the book.
    for i = 1, #self.GEMS do
        local gem = self.GEMS[i]
        gemSpells[i] = Resolve(gem.spell) or (API.IsSpellKnown(gem.spell) and gem.spell) or false
    end

    -- Only announce a change when something MageButler shows actually changed.
    local parts = {}
    for i = 1, #teleports do parts[#parts + 1] = teleports[i].id end
    parts[#parts + 1] = "|"
    for i = 1, #portals do parts[#parts + 1] = portals[i].id end
    parts[#parts + 1] = "|"
    for _, key in ipairs(SIGNATURE_KEYS) do
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

--- Highest learned rank of "water", "food", "intellect" or "brilliance".
function Spells:GetBest(key) return best[key] end

local NO_RANKS = {}

--- Every rank of one of those the player knows, weakest first. Rebuilt by
--- each scan of the spellbook, so it is for reading only.
function Spells:KnownRanks(key)
    return knownRanks[key] or NO_RANKS
end

--- The learned Conjure Mana Gem spell for an entry of Spells.GEMS, or nil.
function Spells:GemSpell(index)
    return gemSpells[index] or nil
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


-- The Legacy Tree's "Reagent Economy" node: "Your class abilities no longer
-- require reagents purchaseable from vendors", which is every reagent this
-- addon tracks - Rune of Teleportation, Rune of Portals and Arcane Powder
-- are all bought from a vendor.
--
-- The tree and the node are the game's own global IDs and are the same for
-- everyone. The config is allocated per character (1065279 on one Mage,
-- whose class config was 1065266), so it cannot be known in advance and is
-- looked up from the tree each time. Read cold after a /reload with the
-- Legacy window never opened, so it does not depend on that UI.
local LEGACY_TREE, REAGENT_ECONOMY = 1189, 110309

local waived, waivedRead = false, false

--- Asks the game, fresh. Only a definite "yes" counts: a missing API, a
--- refused call, a config that is not a number, no node info or a rank count
--- the client withholds all come back false, so a read that fails leaves the
--- addon counting reagents as it would without the talent. It can never be
--- the reason a restock is skipped or a shortage goes unsaid.
local function ReadWaived()
    local traits = C_Traits
    if not (traits and traits.GetConfigIDByTreeID and traits.GetNodeInfo) then return false end
    local ok, config = pcall(traits.GetConfigIDByTreeID, LEGACY_TREE)
    if not ok or MB.IsSecret(config) or type(config) ~= "number" then return false end
    local got, info = pcall(traits.GetNodeInfo, config, REAGENT_ECONOMY)
    if not got or type(info) ~= "table" then return false end
    return (API.Num(info.ranksPurchased, 0) or 0) > 0
end

--- Whether the player's talents have lifted the cost of vendor reagents.
--- Cached, since this is asked every time a reagent's state is worked out.
function Spells:ReagentsWaived()
    if not waivedRead then
        waived, waivedRead = ReadWaived(), true
    end
    return waived
end

--- Reads it again. True when the answer changed, so the caller can tell the
--- rest of the addon to redraw.
function Spells:RefreshWaived()
    local now = ReadWaived()
    local changed = (now ~= waived) or not waivedRead
    waived, waivedRead = now, true
    return changed
end

--- Whether the player has any spell that consumes the given reagent.
function Spells:UsesReagent(key)
    if key == "runeT" then return #teleports > 0 end
    if key == "runeP" then return #portals > 0 end
    if key == "powder" then return best.brilliance ~= nil end
    return false
end

-------------------------------------------------------------------------------
function Spells:OnEnable()
    local function Scan()
        Spells:Scan()
    end
    local function Rescan()
        MB:Debounce("spells", 0.4, Scan)
    end

    -- Respeccing changes whether reagents are needed at all, so the tree is
    -- read again and everything that shows a reagent is told to redraw. The
    -- same message the spellbook scan fires, since the effect is the same:
    -- what the player can do has changed.
    local function Retalent()
        MB:Debounce("spells-traits", 0.4, function()
            if Spells:RefreshWaived() then MB:Fire("SPELLS_UPDATED") end
        end)
    end

    MB:RegisterEvent("SPELLS_CHANGED", Rescan)
    MB:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", Rescan)
    MB:RegisterEvent("PLAYER_LEVEL_UP", Rescan)
    MB:RegisterEvent("TRAIT_CONFIG_UPDATED", Retalent)
    MB:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED", Retalent)

    self:Scan()
end
