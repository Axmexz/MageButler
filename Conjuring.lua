-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: conjured food, water and mana gems.
-- This module only reports inventory and picks which spell a button should
-- cast. Every cast is started by the player clicking a secure button.

local _, MB = ...
local Conjuring = MB:NewModule("Conjuring")
local API = MB.API

-- Conjured items, weakest first.
local WATER = { 5350, 2288, 2136, 3772, 8077, 8078, 8079, 30703, 22018 }
local FOOD = { 5349, 1113, 1114, 1487, 8075, 8076, 22895, 22019 }
local SHARED = { 34062 } -- Conjured Manna Biscuit restores both

-- Level needed to eat or drink each one, used when the client has not cached
-- the item yet.
local MIN_LEVEL = {
    [5350] = 1, [2288] = 5, [2136] = 15, [3772] = 25, [8077] = 35, [8078] = 45, [8079] = 55,
    [30703] = 60, [22018] = 65,
    [5349] = 1, [1113] = 5, [1114] = 15, [1487] = 25, [8075] = 35, [8076] = 45, [22895] = 55,
    [22019] = 65, [34062] = 65,
}

local FALLBACK_SPELL = { water = 5504, food = 587, gem = 759 }
local LABEL = { water = "water", food = "food" }

local kindOf = {}
for _, itemID in ipairs(WATER) do kindOf[itemID] = "water" end
for _, itemID in ipairs(FOOD) do kindOf[itemID] = "food" end
for _, itemID in ipairs(SHARED) do kindOf[itemID] = "both" end

-- Everything counted here is read by the core, in one pass with the reagents,
-- and only while the bags can be seen to answer.
for _, list in ipairs({ WATER, FOOD, SHARED }) do
    for i = 1, #list do MB:TrackItem(list[i]) end
end
for i = 1, #MB.Spells.GEMS do MB:TrackItem(MB.Spells.GEMS[i].item) end

-- Which item each rank of the spell conjures, and which rank number it is.
-- Both lists run weakest first and are the same length, so rank N of the
-- spell makes the Nth item: Conjure Water Rank 4 makes Conjured Spring
-- Water, which is drinkable from level 25.
local itemOfSpell, rankOfSpell = {}, {}
for _, kind in ipairs({ "water", "food" }) do
    local items = (kind == "water") and WATER or FOOD
    local ranks = MB.Spells.RANKS[kind]
    for i = 1, math.min(#items, #ranks) do
        itemOfSpell[ranks[i]] = items[i]
        rankOfSpell[ranks[i]] = i
    end
end

local counts = { water = 0, food = 0, gem = 0 }
local bestItem = {}
local lastState = {}
local chosen = {}   -- [kind] = the rank stepped down to, while it is not the strongest

-------------------------------------------------------------------------------
-- Inventory
-------------------------------------------------------------------------------
--- How many of the strongest rank carried, and which rank that is. Lists run
--- weakest first. Leftovers of an older rank are not counted: a handful of
--- Rank 4 water is not the same as having that much of Rank 7, and treating
--- it as the same made the counts, the radial menu and the preparation
--- check claim more than the player really had.
local function CountBest(list)
    for i = #list, 1, -1 do
        local n = MB:CountOf(list[i])
        if n > 0 then return n, list[i] end
    end
    return 0, nil
end

-- A count that only dips for a moment - an item in flight during a trade -
-- must not raise a warning, so a supply that reads empty is looked at again
-- before anything is said.
local WARN_CONFIRM = 1.5
local pending = {}
local confirming = false

--- Works the totals out from the counts the core last read.
local function ReadCounts()
    local shared, sharedBest = CountBest(SHARED)
    local water, waterBest = CountBest(WATER)
    local food, foodBest = CountBest(FOOD)

    counts.water = water + shared
    counts.food = food + shared
    bestItem.water = waterBest or sharedBest
    bestItem.food = foodBest or sharedBest

    -- Gems are each used for their own cooldown, so every one of them counts.
    local gems, gemBest = 0, nil
    for i = 1, #MB.Spells.GEMS do
        local itemID = MB.Spells.GEMS[i].item
        local n = MB:CountOf(itemID)
        if n > 0 then
            gems = gems + n
            gemBest = itemID
        end
    end
    counts.gem = gems
    bestItem.gem = gemBest
end

--- The second look. It asks the core for a fresh read like everything else,
--- so it cannot land on bags that are not answering and take their silence
--- for empty shelves. If they are not answering nothing is decided: the
--- refresh that follows their return finds the supply still short and starts
--- this again.
local function Confirm()
    confirming = true
    MB:RefreshInventory(false, "second look")
    confirming = false
end

function Conjuring:RefreshInventory()
    ReadCounts()

    -- One warning at the moment a supply runs out, not on every bag update.
    local check = false
    for kind, label in pairs(LABEL) do
        local state = self:State(kind)
        if state ~= "none" then
            lastState[kind] = state
            pending[kind] = nil
        elseif confirming then
            -- Still empty a moment later: trusted now, and said once.
            if pending[kind] and MB:IsActive() and MB.db.conjuring.warnMissing then
                MB:Notify("Out of conjured " .. label .. ".", "warn")
            end
            lastState[kind] = state
            pending[kind] = nil
        elseif lastState[kind] ~= "none" then
            -- Left for the second look to judge, so lastState keeps the edge.
            if lastState[kind] == "ok" or lastState[kind] == "low" then
                pending[kind] = true
            end
            check = true
        end
    end
    if check then
        MB:Debounce("conjuring-warning", WARN_CONFIRM, Confirm)
    end
end

--- Items carried: "water", "food" or "gem".
function Conjuring:Count(kind)
    return counts[kind] or 0
end

--- The strongest item of a kind in the bags: the mana gem the "use" click
--- goes to, and the rank of water or food that is the one counted.
function Conjuring:BestItem(kind)
    return bestItem[kind]
end

--- "water", "food" or "both" for conjured consumables; nil for anything else.
function Conjuring:KindOf(itemID)
    return kindOf[itemID]
end

--- Character level needed to use a conjured item (the client's own figure
--- when it has one).
function Conjuring:MinLevel(itemID)
    return API.ItemMinLevel(itemID) or MIN_LEVEL[itemID] or 1
end

local bestFirst = {}

--- Conjured items of a kind, best first, for the trade assistant. The lists
--- never change, so each is built once; they are for reading only.
function Conjuring:ItemsBestFirst(kind)
    local list = bestFirst[kind]
    if list then return list end

    local source = (kind == "water") and WATER or FOOD
    list = {}
    for i = #source, 1, -1 do
        list[#list + 1] = source[i]
    end
    for i = 1, #SHARED do
        list[#list + 1] = SHARED[i]
    end
    bestFirst[kind] = list
    return list
end

function Conjuring:Target(kind)
    if kind == "water" then return MB.db.conjuring.waterTarget end
    if kind == "food" then return MB.db.conjuring.foodTarget end
    if kind == "gem" then return MB.db.conjuring.wantGem and 1 or 0 end
    return 0
end

--- "ok", "low", "none", or "off" when the supply is not being tracked.
function Conjuring:State(kind)
    local target = self:Target(kind)
    local have = self:Count(kind)
    if target <= 0 then return "off" end
    if kind == "gem" then
        if not MB.Spells:KnowsAnyGem() then return "off" end
    elseif not MB.Spells:GetBest(kind) and have == 0 then
        return "off"
    end
    if have >= target then return "ok" end
    if have > 0 then return "low" end
    return "none"
end

-------------------------------------------------------------------------------
-- Spell selection
-------------------------------------------------------------------------------
--- The rank of Conjure Water / Conjure Food the button will cast: the one the
--- player has stepped down to, or the strongest they know. A rank that is no
--- longer in the spellbook is dropped rather than carried.
function Conjuring:GetSpell(kind)
    local pick = chosen[kind]
    if pick then
        local ranks = MB.Spells:KnownRanks(kind)
        for i = 1, #ranks do
            if ranks[i] == pick then return pick end
        end
        chosen[kind] = nil
    end
    return MB.Spells:GetBest(kind)
end

--- Steps down to the next rank, and round to the strongest again below the
--- weakest. Lower ranks are what a low-level player can actually eat or
--- drink, so this is how a stock of them is made. Returns the rank now set,
--- or nil when the player knows only one.
function Conjuring:CycleRank(kind)
    local ranks = MB.Spells:KnownRanks(kind)
    if #ranks < 2 then return nil end

    local current = self:GetSpell(kind)
    local at = #ranks
    for i = 1, #ranks do
        if ranks[i] == current then
            at = i
            break
        end
    end

    local step = (at > 1) and ranks[at - 1] or ranks[#ranks]
    -- The strongest is held as "no choice", so levelling up follows along.
    chosen[kind] = (step ~= ranks[#ranks]) and step or nil
    return self:GetSpell(kind)
end

--- What the button is set to conjure: the spell, its rank number, how many
--- ranks are known, the item it makes and the level needed to use that item.
function Conjuring:RankInfo(kind)
    local spellID = self:GetSpell(kind)
    if not spellID then return nil end
    local itemID = itemOfSpell[spellID]
    return spellID, rankOfSpell[spellID], #MB.Spells:KnownRanks(kind),
        itemID, itemID and self:MinLevel(itemID) or nil
end

--- Whether a rank below the strongest is set.
function Conjuring:SteppedDown(kind)
    return chosen[kind] ~= nil
end

--- Which rank an item is, for anything that shows one.
function Conjuring:RankOfItem(itemID)
    local list = (kindOf[itemID] == "water") and WATER or FOOD
    for i = 1, #list do
        if list[i] == itemID then return i end
    end
    return nil
end

--- Every rank of a kind carried, weakest first, as a list of
--- { item, count, rank, level }. Built on a tooltip, not on a redraw.
function Conjuring:RanksCarried(kind)
    local list = (kind == "water") and WATER or FOOD
    local out = {}
    for i = 1, #list do
        local itemID = list[i]
        local count = MB:CountOf(itemID)
        if count > 0 then
            out[#out + 1] = { item = itemID, count = count, rank = i, level = self:MinLevel(itemID) }
        end
    end
    for i = 1, #SHARED do
        local count = MB:CountOf(SHARED[i])
        if count > 0 then
            out[#out + 1] = { item = SHARED[i], count = count, level = self:MinLevel(SHARED[i]) }
        end
    end
    return out
end

--- The gem to conjure next: the strongest learned gem the player does not hold
--- yet. Returns spellID, allHeld (true when every learned gem is already held).
function Conjuring:GetGemCast()
    local spells = MB.Spells
    local strongest
    for i = #spells.GEMS, 1, -1 do
        local spellID = spells:GemSpell(i)
        if spellID then
            strongest = strongest or spellID
            if MB:CountOf(spells.GEMS[i].item) == 0 then
                return spellID, false
            end
        end
    end
    return strongest, strongest ~= nil
end

function Conjuring:Icon(kind)
    local spellID
    if kind == "gem" then
        spellID = self:GetGemCast()
    else
        spellID = self:GetSpell(kind)
    end
    return API.SpellTexture(spellID or FALLBACK_SPELL[kind]) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
