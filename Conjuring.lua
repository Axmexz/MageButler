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

local counts = { water = 0, food = 0, gem = 0 }
local bestItem = {}
local lastState = {}

-------------------------------------------------------------------------------
-- Inventory
-------------------------------------------------------------------------------
--- How many of the strongest rank carried, and which rank that is. Lists run
--- weakest first. Leftovers of an older rank are not counted: a handful of
--- Rank 4 water is not the same as having that much of Rank 7, and treating
--- it as the same made the counts, the HUD and the preparation check claim
--- more than the player really had.
local function CountBest(list)
    for i = #list, 1, -1 do
        local n = API.ItemCount(list[i])
        if n > 0 then return n, list[i] end
    end
    return 0, nil
end

-- A count that only dips for a moment - a stale read around a zone change, an
-- item in flight during a trade - must not raise a warning, so a supply that
-- reads empty is checked again before anything is said.
local WARN_CONFIRM = 1.5
local pending = {}

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
        local n = API.ItemCount(itemID)
        if n > 0 then
            gems = gems + n
            gemBest = itemID
        end
    end
    counts.gem = gems
    bestItem.gem = gemBest
end

--- Says what is still empty a moment after it first read empty.
local function ConfirmMissing()
    ReadCounts()
    for kind, label in pairs(LABEL) do
        local state = Conjuring:State(kind)
        if pending[kind] and state == "none"
            and MB:IsActive() and MB.db.conjuring.warnMissing then
            MB:Notify("Out of conjured " .. label .. ".", "warn")
        end
        lastState[kind] = state   -- trusted now, whichever way it went
    end
    wipe(pending)
end

function Conjuring:RefreshInventory()
    ReadCounts()

    -- One warning at the moment a supply runs out, not on every bag update.
    local check = false
    for kind in pairs(LABEL) do
        local state = self:State(kind)
        if state == "none" then
            -- Left for ConfirmMissing to judge, so lastState keeps the edge.
            if lastState[kind] == "ok" or lastState[kind] == "low" then
                pending[kind] = true
            end
            check = true
        else
            lastState[kind] = state
            pending[kind] = nil
        end
    end
    if check then
        MB:Debounce("conjuring-warning", WARN_CONFIRM, ConfirmMissing)
    end
end

--- Items carried: "water", "food" or "gem".
function Conjuring:Count(kind)
    return counts[kind] or 0
end

--- Best conjured item of a kind currently in the bags, or nil.
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

--- Conjured items of a kind, best first, for the trade assistant.
function Conjuring:ItemsBestFirst(kind)
    local source = (kind == "water") and WATER or FOOD
    local list = {}
    for i = #source, 1, -1 do
        list[#list + 1] = source[i]
    end
    for i = 1, #SHARED do
        list[#list + 1] = SHARED[i]
    end
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
--- Highest learned rank of Conjure Water / Conjure Food.
function Conjuring:GetSpell(kind)
    return MB.Spells:GetBest(kind)
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
            if API.ItemCount(spells.GEMS[i].item) == 0 then
                return spellID, false
            end
        end
    end
    return strongest, strongest ~= nil
end

--- Strongest mana gem in the bags, for the "use" click.
function Conjuring:GetGemItem()
    return bestItem.gem
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
