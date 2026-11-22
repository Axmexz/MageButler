-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: Buff Watch.
-- Watches the Mage, the party or the raid (up to 40 players) for missing,
-- weaker or expiring Arcane Intellect / Arcane Brilliance and works out the
-- cheapest useful cast. Right-clicking the orb casts that one spell: every
-- cast is a single secure click by the player, never a sequence.
--
-- Aura data is read only outside combat. In combat the last picture is kept,
-- the orb's buff click is switched off, and the player list (fixed unit
-- buttons) remains available for deliberate casts.

local _, MB = ...
local BuffWatch = MB:NewModule("BuffWatch")
local API = MB.API
local IsSecret = MB.IsSecret
local Theme, Spells, Reagents

local INTELLECT_ID, BRILLIANCE_ID = 1459, 23028
local BUFF_IDS = { INTELLECT_ID, BRILLIANCE_ID }

-- Relative strength of each rank, so a weaker buff can be told from an equal one.
local STRENGTH = {
    [1459] = 1, [1460] = 2, [1461] = 3, [10156] = 4, [10157] = 5, [27126] = 6,
    [23028] = 5, [27127] = 6,
}
local NO_MANA_CLASS = { WARRIOR = true, ROGUE = true }

-- Lowest level a target must be to receive each rank. Classic-rules clients
-- refuse a target well below the rank's own level, so buffing a low-level
-- player with your best rank simply fails. These follow the usual vanilla
-- pattern of ten levels under the rank; that is not confirmed on this client,
-- which is why "Match the player's level" can be turned off.
local MIN_TARGET_LEVEL = {
    [1459] = 1, [1460] = 4, [1461] = 18, [10156] = 32, [10157] = 46, [27126] = 58,
    [23028] = 46, [27127] = 58,
}

-- Used for "auto" scope when the spell's own description gives no answer.
-- On WoW Forever Arcane Brilliance is raid-wide, unlike original vanilla
-- where it reached the target's party only (owner, 17 Nov 2026). A cast that
-- looks as though it missed part of the raid is most likely range: a raid
-- buff still only reaches players who are near enough to receive it.
local DEFAULT_SCOPE = "raid"

local SOLO_TOKENS = { "player" }
local PARTY_TOKENS = { "player", "party1", "party2", "party3", "party4" }
local RAID_TOKENS = {}
local tracked = { player = true }
for i = 1, 4 do tracked["party" .. i] = true end
for i = 1, 40 do
    RAID_TOKENS[i] = "raid" .. i
    tracked["raid" .. i] = true
end

local LIST_COLUMNS = 5
local CELL_WIDTH, CELL_HEIGHT, CELL_GAP = 84, 18, 2
local LIST_PAD, LIST_HEADER, LIST_FOOTER = 8, 28, 18

local state = {
    active = false,
    paused = false,
    pausedWhy = nil,   -- "combat" or "restricted", while paused
    context = "solo",
    total = 0, ok = 0, expiring = 0, weak = 0, missing = 0, unreadable = 0, outOfRange = 0,
    overall = "off",
    units = {},
    byUnit = {},
    action = nil,
    note = nil,
}

local records = {}        -- [unit] = that unit's record, kept and filled in again each time
local buffNames
local buffNamesPartial    -- only one of the two names resolved: ask again
local autoScope
local applied = {}
local dirty = false
local timerToken = 0
local clicked
local awaiting            -- a cast asked for, waiting on the game to go through with it
local castToken = 0
local CAST_WAIT = 0.7     -- how long the game gets to start it
local pip, counter, list, listPanel
local unitButtons = {}

--- Ends a drag of the player list and keeps where it was put. The list holds
--- secure buttons, so it has to be let go before combat lockdown begins.
local function StopListDrag()
    if not (listPanel and listPanel.dragging) then return end
    -- StopMovingOrSizing is protected on the list, so in combat the whole
    -- thing waits: the flag stays set, and the mouse release queues the same
    -- call again rather than slipping past the guard above.
    if InCombatLockdown() then
        MB:AfterCombat("buffwatch-stop-drag", StopListDrag)
        return
    end
    listPanel.dragging = nil
    list:StopMovingOrSizing()
    local x, y = MB.CentreOffset(list)
    if x then
        MB.db.buffwatch.x, MB.db.buffwatch.y = x, y
    end
end

-------------------------------------------------------------------------------
-- Reading the game
-------------------------------------------------------------------------------
local function Flag(value, default)
    if IsSecret(value) then return default end
    return value and true or false
end

--- Localised names of the two buffs; every rank shares one of them. The
--- client has no name for a spell whose data it has not loaded, which is the
--- usual state at login for one the Mage does not know, so a list with only
--- one of the two in it is used but not kept: it is asked for again at the
--- next update, or Arcane Brilliance would go unrecognised all session.
local function BuffNames()
    if buffNames then return buffNames end
    local names = {}
    local intellect, brilliance = API.SpellName(INTELLECT_ID), API.SpellName(BRILLIANCE_ID)
    if intellect then names[#names + 1] = intellect end
    if brilliance and brilliance ~= intellect then names[#names + 1] = brilliance end
    if #names > 0 then
        buffNames = names
        buffNamesPartial = not (intellect and brilliance)
    end
    return names
end

local rankCache = {}

--- Every rank of "intellect" or "brilliance" the player knows, weakest first.
--- The spellbook scan is the authority everywhere else in the addon, and it
--- sees ranks `IsSpellKnown` on its own does not, so the list comes from
--- there. Only ranks the tables above can judge are kept: an ID with no
--- strength and no minimum level cannot be weighed against another.
local function KnownRanks(key)
    local cached = rankCache[key]
    if cached then return cached end

    local known = Spells:KnownRanks(key)
    local list = {}
    for i = 1, #known do
        if STRENGTH[known[i]] then list[#list + 1] = known[i] end
    end
    if #list == 0 and #known > 0 then
        -- This client names the ranks differently. An unjudged rank is
        -- better than no buff at all, so the book's list stands as it is.
        for i = 1, #known do list[i] = known[i] end
    end
    -- An empty list before the first scan is not an answer, so it is not kept.
    if #list > 0 then rankCache[key] = list end
    return list
end

local function LevelOf(unit)
    local level = API.Num(UnitLevel(unit))
    if level and level > 0 then return level end
    return nil -- the client will not say; treat the target as able to take any rank
end

--- The strongest rank the player knows that a target of this level can
--- receive. Without level matching, or without a level to go on, the
--- strongest known rank; if even the weakest is too strong, the weakest.
local function RankForLevel(key, level)
    local list = KnownRanks(key)
    if #list == 0 then return nil end
    if not level or not MB.db.buffwatch.matchLevel then
        return list[#list]
    end
    for i = #list, 1, -1 do
        if level >= (MIN_TARGET_LEVEL[list[i]] or 1) then return list[i] end
    end
    return list[1]
end

--- Which rank a spell ID is, counting from 1. The rank tables list every rank
--- weakest first, so the position is the rank number.
local function RankNumber(key, spellID)
    local ranks = Spells.RANKS[key]
    for i = 1, #ranks do
        if ranks[i] == spellID then return i end
    end
    return nil
end

--- Whether a target of this level can receive the given rank.
local function CanReceive(spellID, level)
    if not spellID or not level or not MB.db.buffwatch.matchLevel then return true end
    return level >= (MIN_TARGET_LEVEL[spellID] or 1)
end

--- "buffed", "missing" or "unknown" (the client would not say), plus the
--- seconds left and the rank strength when they can be read.
local function ReadBuff(unit)
    local names = BuffNames()
    if #names == 0 or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return "unknown"
    end
    for i = 1, #names do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, names[i], "HELPFUL")
        if not ok or IsSecret(aura) then return "unknown" end
        if aura then
            local expires = API.Num(aura.expirationTime)
            local remaining
            if expires and expires > 0 then
                remaining = expires - GetTime()
            end
            local spellID = API.Num(aura.spellId)
            return "buffed", remaining, spellID and STRENGTH[spellID] or nil, spellID
        end
    end
    return "missing"
end

--- Whether a unit is close enough to be buffed right now. The spell's own
--- range check is the reliable one here: UnitInRange hands addons a secret
--- value on this client, so it is only a second opinion.
local function Reachable(unit, spellID)
    if unit == "player" then return true end
    if spellID and C_Spell and C_Spell.IsSpellInRange then
        local inRange = C_Spell.IsSpellInRange(spellID, unit)
        if not IsSecret(inRange) and inRange ~= nil then
            return inRange and true or false
        end
    end
    local inRange, checked = UnitInRange(unit)
    if not IsSecret(inRange) and not IsSecret(checked) and checked then
        return inRange and true or false
    end
    return Flag(UnitIsVisible(unit), true)
end

--- True while the client withholds buff data (encounters, PvP matches and the
--- like). Reading then would show buffed players as unbuffed.
local function AurasRestricted()
    local secrets = C_Secrets
    if not (secrets and secrets.ShouldAurasBeSecret) then return false end
    local ok, restricted = pcall(secrets.ShouldAurasBeSecret)
    if not ok or IsSecret(restricted) then return true end
    if not restricted then return false end
    -- Individual spells can stay readable under a general restriction.
    if secrets.ShouldSpellAuraBeSecret then
        for _, spellID in ipairs(BUFF_IDS) do
            local fine, secret = pcall(secrets.ShouldSpellAuraBeSecret, spellID)
            if not fine or IsSecret(secret) or secret then return true end
        end
        return false
    end
    return true
end

--- What Arcane Brilliance covers on this client: "group" (the target's party)
--- or "raid". On "auto" the spell's own description decides.
function BuffWatch:GetScope()
    local setting = MB.db.buffwatch.scope
    if setting == "raid" or setting == "group" then return setting end
    if not autoScope and C_Spell and C_Spell.GetSpellDescription then
        local spellID = Spells:GetBest("brilliance") or BRILLIANCE_ID
        local text = API.Str(C_Spell.GetSpellDescription(spellID))
        if text then
            text = text:lower()
            if text:find("raid", 1, true) then
                autoScope = "raid"
            elseif text:find("party", 1, true) then
                autoScope = "group"
            end
        end
    end
    return autoScope or DEFAULT_SCOPE
end

-------------------------------------------------------------------------------
-- Evaluation
-------------------------------------------------------------------------------
local function Context()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

local function Tokens(context)
    if context == "raid" then return RAID_TOKENS end
    if context == "party" then return PARTY_TOKENS end
    return SOLO_TOKENS
end

local function ResetCounts()
    wipe(state.units)
    wipe(state.byUnit)
    state.total, state.ok, state.expiring, state.weak, state.missing = 0, 0, 0, 0, 0
    state.unreadable, state.outOfRange = 0, 0
    state.action, state.note = nil, nil
end

local function Evaluate()
    local db = MB.db.buffwatch
    local context = Context()
    state.context = context
    state.paused, state.pausedWhy = false, nil
    ResetCounts()

    local intellect = Spells:GetBest("intellect")
    state.active = MB.db.general.enabled and db.enabled and db[context] and intellect ~= nil
    if not state.active then
        state.overall = "off"
        return
    end
    if AurasRestricted() then
        -- Nothing can be read reliably: show "paused", recommend nothing.
        state.paused, state.pausedWhy = true, "restricted"
        state.overall = "off"
        return
    end

    local rebuff = db.watchExpiry and db.rebuffMinutes * 60 or nil
    local tokens = Tokens(context)

    for index = 1, #tokens do
        local unit = tokens[index]
        if UnitExists(unit) then
            local excluded = false
            if db.ignoreOffline and not Flag(UnitIsConnected(unit), true) then
                excluded = true
            elseif db.ignoreDead and Flag(UnitIsDeadOrGhost(unit), false) then
                excluded = true
            elseif db.skipUnavailable and unit ~= "player" and not Flag(UnitIsVisible(unit), true) then
                excluded = true
            elseif db.manaUsersOnly then
                local _, class = UnitClass(unit)
                if not IsSecret(class) and NO_MANA_CLASS[class] then excluded = true end
            end

            if excluded then
                state.byUnit[unit] = "excluded"
            else
                local found, remaining, strength, auraSpell = ReadBuff(unit)
                if found == "unknown" then
                    state.unreadable = state.unreadable + 1
                    state.byUnit[unit] = "unknown"
                else
                    -- The rank this player could actually receive, which on a
                    -- low-level character is not the Mage's best one.
                    local level = LevelOf(unit)
                    local cast = RankForLevel("intellect", level)
                    local castStrength = STRENGTH[cast]

                    -- "weak" is buffed, but at a lower rank than the Mage
                    -- could give this player: what another, lower-level Mage
                    -- leaves behind. It is judged against the rank their
                    -- level can take, so the best a low-level player can
                    -- hold is never held against them.
                    local status = "ok"
                    if found == "missing" then
                        status = "missing"
                    elseif db.upgradeWeaker and strength and castStrength and strength < castStrength then
                        status = "weak"
                    elseif rebuff and remaining and remaining < rebuff
                        and not (strength and castStrength and strength > castStrength) then
                        -- A stronger rank than the Mage can give cannot be
                        -- refreshed: the game refuses the weaker cast until
                        -- it has run out, so it is left alone until then.
                        status = "expiring"
                    end

                    local subgroup
                    if context == "raid" then
                        local _, _, group = GetRaidRosterInfo(index)
                        subgroup = API.Num(group)
                    end

                    -- One table per unit for the whole session, rewritten in
                    -- full here: a raid would otherwise shed forty of them
                    -- on every update.
                    local record = records[unit]
                    if not record then
                        record = { unit = unit }
                        records[unit] = record
                    end
                    record.name = API.Str(UnitName(unit)) or unit
                    record.status = status
                    record.remaining = remaining
                    record.level = level
                    record.cast = cast
                    record.reachable = Reachable(unit, cast or intellect)
                    record.subgroup = subgroup or 1
                    record.aura = auraSpell      -- the buff they carry, when it could be read
                    record.strength = strength   -- nil when its rank is not one that is known
                    state.units[#state.units + 1] = record
                    state.byUnit[unit] = record
                    state.total = state.total + 1
                    state[status] = state[status] + 1
                    if status ~= "ok" and not record.reachable then
                        state.outOfRange = state.outOfRange + 1
                    end
                end
            end
        end
    end

    if state.total == 0 then
        state.overall = "off"
    elseif state.missing > 0 then
        state.overall = "none"
    elseif state.weak > 0 or state.expiring > 0 then
        state.overall = "low"
    else
        state.overall = "ok"
    end
end

local function ByRemaining(a, b)
    return (a.remaining or 0) < (b.remaining or 0)
end

--- Players who need the buff, in the order they should be served: those with
--- none first, then those carrying a weaker rank than they could have, which
--- is short for as long as it lasts, then those whose buff is running out.
local function Needs()
    local missing, weak, expiring = {}, {}, {}
    for i = 1, #state.units do
        local record = state.units[i]
        if record.status == "missing" then
            missing[#missing + 1] = record
        elseif record.status == "weak" then
            weak[#weak + 1] = record
        elseif record.status == "expiring" then
            expiring[#expiring + 1] = record
        end
    end
    table.sort(expiring, ByRemaining)

    local needs = {}
    if MB.db.buffwatch.missingFirst then
        for i = 1, #missing do needs[#needs + 1] = missing[i] end
        for i = 1, #weak do needs[#needs + 1] = weak[i] end
        for i = 1, #expiring do needs[#needs + 1] = expiring[i] end
    else
        -- Roster order, whatever the reason.
        for i = 1, #state.units do
            if state.units[i].status ~= "ok" then needs[#needs + 1] = state.units[i] end
        end
    end
    return needs
end

--- Whether Arcane Brilliance would do anything for a player who needs a buff:
--- they have to be of a level to receive it, and one who already carries a
--- weaker Intellect has to be given something stronger than that.
local function Gains(record, brilliance)
    if not CanReceive(brilliance, record.level) then return false end
    local strength = STRENGTH[brilliance]
    if record.status == "weak" and record.strength and strength and strength <= record.strength then
        return false
    end
    return true
end

--- Whether the client says a spell can be cast right now. Asked rather than
--- assumed, because a talent can lift a reagent requirement: with no Arcane
--- Powder left, a Brilliance the client still calls usable plainly needs
--- none. Anything it will not say is taken as "no", so the reagent rule
--- below stands unless the game itself contradicts it.
local function UsableNow(spellID)
    if not (C_Spell and C_Spell.IsSpellUsable) then return false end
    local ok, usable = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok or IsSecret(usable) then return false end
    return usable == true
end

--- Picks the one spell a right-click should cast, or explains why none.
local function Recommend()
    state.action, state.note = nil, nil
    if not state.active then return end
    if state.paused then
        state.note = "The game is withholding buff data here, so Buff Watch is paused."
        return
    end

    local db = MB.db.buffwatch
    local needs = Needs()
    if #needs == 0 then
        if state.total > 0 then state.note = "Everyone has Intellect." end
        return
    end

    local intellect = Spells:GetBest("intellect")
    local brilliance = db.preferBrilliance and Spells:GetBest("brilliance") or nil
    local context = state.context

    -- Arcane Brilliance: only when enough players gain from the reagent.
    if brilliance and context ~= "solo" then
        local benefit, target, worthIt = 0, nil, false
        if context == "party" or BuffWatch:GetScope() == "raid" then
            -- Only the players it would actually reach are counted. The rest
            -- are served one at a time below, at the rank they can take.
            for i = 1, #needs do
                if Gains(needs[i], brilliance) then benefit = benefit + 1 end
            end
            target = "player"
            worthIt = benefit >= (context == "raid" and db.raidThreshold or db.partyThreshold)
        else
            -- Group-scoped Brilliance in a raid: aim it at the subgroup that
            -- gains the most, and judge it on the raid as a whole. The player
            -- it is aimed at has to be high enough level to receive it.
            local count, reach = {}, {}
            for i = 1, #needs do
                local record = needs[i]
                if Gains(record, brilliance) then
                    count[record.subgroup] = (count[record.subgroup] or 0) + 1
                end
                if record.reachable and not reach[record.subgroup]
                    and CanReceive(brilliance, record.level) then
                    reach[record.subgroup] = record.unit
                end
            end
            for subgroup, amount in pairs(count) do
                if reach[subgroup] and amount > benefit then
                    benefit, target = amount, reach[subgroup]
                end
            end
            worthIt = benefit >= db.partyThreshold or (#needs >= db.raidThreshold and benefit >= 2)
        end

        if worthIt and target then
            -- A count that has not been read yet is unknown, not zero. With
            -- none left the client gets the last word: a talent can lift the
            -- reagent, and then an empty powder bag stops nothing.
            if not MB.inventoryKnown or Reagents:Count("powder") > 0
                or UsableNow(brilliance) then
                state.action = {
                    kind = "brilliance", spell = brilliance, unit = target,
                    benefit = benefit, waiting = #needs,
                }
                return
            elseif not db.fallbackIntellect then
                state.note = "Arcane Brilliance needs Arcane Powder."
                return
            end
            state.note = "No Arcane Powder: using Arcane Intellect."
        end
    end

    -- Otherwise one player at a time, nearest need first, skipping anyone out
    -- of range. Each is cast at the rank their own level can receive.
    for i = 1, #needs do
        local record = needs[i]
        if record.reachable then
            state.action = {
                kind = "intellect", spell = record.cast or intellect, unit = record.unit,
                name = record.name, waiting = #needs,
                downranked = record.cast ~= nil and record.cast ~= intellect,
            }
            return
        end
    end
    state.note = #needs .. (#needs == 1 and " player needs" or " players need") .. " Intellect but none is in range."
end

-------------------------------------------------------------------------------
-- Secure attributes (outside combat only)
-------------------------------------------------------------------------------
local function ApplyAttributes()
    local orb = MB.RadialMenu.orb
    local action = state.action
    local spell, unit = action and action.spell or nil, action and action.unit or nil
    if applied.spell ~= spell or applied.unit ~= unit or not applied.orb then
        orb:SetAttribute("type2", spell and "spell" or nil)
        orb:SetAttribute("spell2", spell)
        orb:SetAttribute("unit2", unit)
        applied.spell, applied.unit, applied.orb = spell, unit, true
    end

    -- Each player's own button casts the rank that player can receive.
    local brilliance = Spells:GetBest("brilliance")
    for i = 1, #unitButtons do
        local button = unitButtons[i]
        local spellForUnit = RankForLevel("intellect", LevelOf(button.unit))
        if button.appliedSpell ~= spellForUnit or button.appliedBrilliance ~= brilliance then
            -- "*" = whatever modifier keys are held.
            button:SetAttribute("*type1", spellForUnit and "spell" or nil)
            button:SetAttribute("*spell1", spellForUnit)
            button:SetAttribute("*type2", brilliance and "spell" or nil)
            button:SetAttribute("*spell2", brilliance)
            button.appliedSpell, button.appliedBrilliance = spellForUnit, brilliance
        end
    end
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------
--- How many of those watched carry Intellect at all, whatever its rank and
--- however long it has left.
local function Buffed()
    return state.ok + state.expiring + state.weak
end

local function Headline()
    if state.paused then
        local why = state.pausedWhy or (InCombatLockdown() and "combat" or "restricted")
        return why == "combat" and "Paused in combat" or "Paused (buffs cannot be read here)"
    end
    if state.overall == "ok" then return "Everyone is buffed" end
    if state.overall == "low" then
        return state.weak > 0 and "Weaker buffs to upgrade" or "Buffs expiring soon"
    end
    if state.overall == "none" then return "Players missing Intellect" end
    return "Nothing to watch"
end

local function ActionText()
    local action = state.action
    if not action then return nil end
    return API.SpellName(action.spell) or (action.kind == "brilliance" and "Arcane Brilliance" or "Arcane Intellect")
end

local function StatusColor(record)
    if record == "excluded" or record == "unknown" or record == nil then
        return Theme:Color("off")
    end
    if record.status == "missing" then return Theme:Color("bad") end
    if record.status == "expiring" or record.status == "weak" then return Theme:Color("warn") end
    return Theme:Color("ok")
end

--- What is known about the player holding a unit token now. Records are kept
--- by token and are not read again in combat, so after a change of roster in
--- a fight the one on file can belong to whoever held the token before: that
--- is no answer for the newcomer, and none is given.
local function RecordFor(unit)
    local record = state.byUnit[unit]
    if type(record) == "table" then
        local name = API.Str(UnitName(unit))
        if name and record.name ~= unit and record.name ~= name then return nil end
    end
    return record
end

--- Names and colours in the player list. A closed list is left alone: it is
--- brought up to date as it opens.
local function RefreshList()
    if not listPanel or not list:IsShown() then return end

    local shown = 0
    for i = 1, #unitButtons do
        local button = unitButtons[i]
        local unit = button.unit
        if button.context == state.context or (button.context == "party" and state.context == "solo") then
            if UnitExists(unit) then
                shown = shown + 1
                button.text:SetText(API.Str(UnitName(unit)) or unit)
                local r, g, b = StatusColor(RecordFor(unit))
                button.text:SetTextColor(r, g, b)
                button.bar:SetVertexColor(r, g, b)
            end
        end
    end

    -- The backdrop is a child of the list, which is a secure frame, so its
    -- size is protected: in combat the new size waits for the fight to end.
    local rows = math.max(1, math.ceil(shown / LIST_COLUMNS))
    local width = LIST_COLUMNS * (CELL_WIDTH + CELL_GAP) - CELL_GAP + LIST_PAD * 2
    local height = LIST_HEADER + rows * (CELL_HEIGHT + CELL_GAP) + LIST_FOOTER + LIST_PAD
    MB:AfterCombat("buffwatch-list-size", function()
        if listPanel then listPanel:SetSize(width, height) end
    end)

    if state.active and state.total > 0 then
        listPanel.coverage:SetText(Buffed() .. "/" .. state.total .. " buffed")
        listPanel.coverage:SetTextColor(Theme:StateColor(state.overall))
    else
        listPanel.coverage:SetText(state.paused and "paused" or "")
        listPanel.coverage:SetTextColor(Theme:Color("off"))
    end
end

function BuffWatch:RefreshVisuals()
    local db = MB.db.buffwatch
    local overall = state.overall
    local watching = MB.db.general.enabled and db.enabled

    if pip then
        if watching and db.orbIndicator then
            pip.dot:SetVertexColor(Theme:StateColor(overall))
            Theme:SetPulse(pip.dot, (not state.paused) and Theme:PulseForState(overall) or nil)
        else
            Theme:SetPulse(pip.dot, nil)   -- so a later show joins the beat afresh
        end
        Theme:ShowPip(pip, watching and db.orbIndicator and true or false)
    end


    if counter then
        if watching and db.showCounter and state.active and state.context ~= "solo" and state.total > 0 then
            counter:SetText(Buffed() .. "/" .. state.total)
            counter:SetTextColor(Theme:StateColor(overall))
            counter:Show()
        else
            counter:Hide()
        end
    end

    RefreshList()
    MB.RadialMenu:RefreshGlow()
end

--- Buffed and watched player counts, for the preparation check.
function BuffWatch:GetCoverage()
    return Buffed(), state.total
end

--- "ok", "low" (expiring, or a weaker rank than could be given), "none" (missing), or "off".
function BuffWatch:GetOverall()
    if not state.active then return "off" end
    return state.overall
end

function BuffWatch:GetState()
    return state
end

function BuffWatch:AddTooltipLines(tooltip)
    local db = MB.db.buffwatch
    if not (MB.db.general.enabled and db.enabled) then return end

    tooltip:AddLine(" ")
    local r, g, b = Theme:StateColor(state.overall)
    tooltip:AddLine("Buff Watch: " .. Headline(), r, g, b)
    if not state.active or state.total == 0 then return end

    local label = (state.context == "raid" and "Raid members") or (state.context == "party" and "Party members") or "Solo"
    tooltip:AddDoubleLine(label, state.total, 0.88, 0.92, 1, 0.88, 0.92, 1)
    tooltip:AddDoubleLine("Buffed", state.ok, 0.88, 0.92, 1, Theme:Color("ok"))
    if state.missing > 0 then
        tooltip:AddDoubleLine("Missing buffs", state.missing, 0.88, 0.92, 1, Theme:Color("bad"))
    end
    if state.expiring > 0 then
        tooltip:AddDoubleLine("Expiring soon", state.expiring, 0.88, 0.92, 1, Theme:Color("warn"))
    end
    if state.weak > 0 then
        tooltip:AddDoubleLine("Weaker rank", state.weak, 0.88, 0.92, 1, Theme:Color("warn"))
    end
    if state.outOfRange > 0 then
        tooltip:AddDoubleLine("Out of range", state.outOfRange, 0.88, 0.92, 1, Theme:Color("off"))
    end
    if state.unreadable > 0 then
        tooltip:AddDoubleLine("Could not be read", state.unreadable, 0.88, 0.92, 1, Theme:Color("off"))
    end

    local spell = ActionText()
    if spell then
        local ar, ag, ab = Theme:Accent()
        tooltip:AddDoubleLine("Recommended spell", spell, 0.88, 0.92, 1, ar, ag, ab)
    elseif state.note then
        Theme:TipLine(tooltip, state.note, "dim", true)
    end

    if db.tooltipNames and (state.missing > 0 or state.weak > 0 or state.expiring > 0) then
        local names, more = {}, 0
        for i = 1, #state.units do
            local record = state.units[i]
            if record.status ~= "ok" then
                if #names < 8 then
                    local cr, cg, cb = StatusColor(record)
                    names[#names + 1] = Theme:Hex(cr, cg, cb) .. record.name .. "|r"
                else
                    more = more + 1
                end
            end
        end
        local text = table.concat(names, ", ")
        if more > 0 then text = text .. " and " .. more .. " more" end
        tooltip:AddLine(text, 1, 1, 1, true)
    end
end

--- What Buff Watch makes of each player, for /mb debug. The spell IDs are
--- the point of it: everything that decides who needs a buff rests on the
--- rank the client reports for the aura they carry. If that ID is one this
--- table does not know, or the same ID comes back whatever the rank really
--- is, the comparison is working from the wrong numbers, and these lines are
--- what show it.
function BuffWatch:Diagnostics()
    local db = MB.db.buffwatch
    local ranks = KnownRanks("intellect")
    local names = {}
    for i = 1, #ranks do names[i] = tostring(ranks[i]) end

    -- Which kind of paused matters: in combat it is working as intended and
    -- the picture below is the last one from before the pull, while
    -- "restricted" means the client will not give buff data here at all.
    local paused = ""
    if state.paused then
        paused = (state.pausedWhy == "restricted")
            and ", paused (buffs cannot be read here)" or ", paused (in combat)"
    end
    MB:Print("buff watch: " .. (state.active and state.context or "off")
        .. paused .. ", " .. state.total .. " watched."
        .. " Upgrade weaker ranks: " .. (db.upgradeWeaker and "on" or "off")
        .. ", rebuff under " .. tostring(db.rebuffMinutes) .. " min.")
    MB:Print("  Intellect ranks you know: " .. (#names > 0 and table.concat(names, ", ") or "none"))

    -- What Arcane Brilliance is taken to cover, and what the spell's own
    -- description said, which is what "Automatic" goes by.
    local described = "not read"
    if C_Spell and C_Spell.GetSpellDescription then
        local spellID = Spells:GetBest("brilliance") or BRILLIANCE_ID
        local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
        if ok then text = API.Str(text) end
        if text then described = "\"" .. text .. "\"" end
    end
    MB:Print("  Brilliance covers: " .. self:GetScope()
        .. " (setting: " .. tostring(db.scope) .. "). Description: " .. described)

    -- Whether Arcane Brilliance really costs a reagent on this client. A
    -- talent can lift it, and then the powder in the bags is beside the
    -- point. "casts left" is the client's own count of how many casts the
    -- reagents allow: with powder carried, a count matching it means the
    -- reagent is required, and 0 means it is not.
    local brilliance = Spells:GetBest("brilliance")
    if brilliance then
        local casts, usable = "not read", "not read"
        if C_Spell and C_Spell.GetSpellCastCount then
            local ok, n = pcall(C_Spell.GetSpellCastCount, brilliance)
            if ok then casts = tostring(API.Num(n) or "withheld") end
        end
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, can = pcall(C_Spell.IsSpellUsable, brilliance)
            if ok and not IsSecret(can) then usable = can and "yes" or "no" end
        end
        MB:Print("  Brilliance reagent: Arcane Powder " .. Reagents:Count("powder")
            .. " carried, casts left " .. casts .. ", usable now " .. usable)
    end

    -- The Legacy Tree talent that lifts vendor reagent costs. Printed whether
    -- or not Brilliance is known, since it covers the runes too. This is the
    -- line to ask for if a reagent has stopped being counted unexpectedly.
    MB:Print("  Reagent Economy talent: "
        .. (Spells:ReagentsWaived()
            and "active - Arcane Powder and both runes are not being tracked"
            or "not detected, so reagents are tracked as usual"))

    for i = 1, #state.units do
        local record = state.units[i]
        local cast = record.cast
        local carries
        if record.status == "missing" then
            carries = "nothing"
        elseif record.aura then
            carries = tostring(record.aura) .. " (strength " .. tostring(record.strength or "not known") .. ")"
        else
            carries = "a buff whose rank the client will not give"
        end
        MB:Print("  " .. tostring(record.name) .. ": " .. tostring(record.status)
            .. ", level " .. tostring(record.level or "?")
            .. ", carries " .. carries
            .. ", you would cast " .. tostring(cast or "?")
            .. " (strength " .. tostring((cast and STRENGTH[cast]) or "not known") .. ")")
    end
    if state.total == 0 then
        MB:Print("  nobody is being watched.")
    end
end

-------------------------------------------------------------------------------
-- Updating: driven by events, never by polling
-------------------------------------------------------------------------------
local expiryDue   -- when the pending expiry check will run
local sent = {}   -- what BUFFWATCH_UPDATED last reported

local function ScheduleExpiryCheck()
    local db = MB.db.buffwatch
    if not (state.active and db.watchExpiry) then
        timerToken = timerToken + 1
        expiryDue = nil
        return
    end

    -- The next moment a buff either crosses the rebuff threshold or runs out.
    local rebuff = db.rebuffMinutes * 60
    local soonest
    for i = 1, #state.units do
        local remaining = state.units[i].remaining
        if remaining then
            local wait = (remaining > rebuff) and (remaining - rebuff) or remaining
            if wait > 0 and (not soonest or wait < soonest) then soonest = wait end
        end
    end
    if not soonest then
        timerToken = timerToken + 1
        expiryDue = nil
        return
    end

    -- An update that comes to the same moment keeps the timer already
    -- waiting for it, instead of leaving another behind every time.
    local due = GetTime() + soonest + 1
    if expiryDue and math.abs(expiryDue - due) < 0.5 then return end
    expiryDue = due
    timerToken = timerToken + 1
    local token = timerToken
    C_Timer.After(soonest + 1, function()
        if token ~= timerToken then return end
        expiryDue = nil
        BuffWatch:Queue()
    end)
end

--- Reads the group and redraws. Returns false in combat, where it is put off
--- until combat ends and nothing has been redrawn.
function BuffWatch:Update()
    if InCombatLockdown() then
        dirty = true
        return false
    end
    dirty = false
    -- Only one of the two buff names was known last time: ask once more, in
    -- case the client has loaded the other one since.
    if buffNamesPartial then buffNames = nil end
    Evaluate()
    Recommend()
    ApplyAttributes()
    ScheduleExpiryCheck()
    self:RefreshVisuals()
    -- Told only when what others go by has changed: updates come several
    -- times a second in a group, and most of them change nothing.
    local overall, have, total, paused = self:GetOverall(), Buffed(), state.total, state.paused
    if overall ~= sent.overall or have ~= sent.have or total ~= sent.total or paused ~= sent.paused then
        sent.overall, sent.have, sent.total, sent.paused = overall, have, total, paused
        MB:Fire("BUFFWATCH_UPDATED")
    end
    return true
end

local function RunUpdate()
    BuffWatch:Update()
end

function BuffWatch:Queue()
    if InCombatLockdown() then
        dirty = true
        return
    end
    MB:Debounce("buffwatch", 0.25, RunUpdate)
end

-------------------------------------------------------------------------------
-- The orb's right-click
-------------------------------------------------------------------------------
--- Called on the press of a right-click, before the secure click runs, so the
--- cast uses a target chosen from what is true at this moment.
function BuffWatch:PrepareClick()
    clicked = { combat = InCombatLockdown() }
    if clicked.combat then return end
    self:Update()
    clicked.action = state.action
    clicked.note = state.note
    clicked.active = state.active
end

--- Drops a snapshot whose release never reached AfterClick, so no later
--- click can report a cast that was never made.
function BuffWatch:CancelClick()
    clicked = nil
end

--- Called on the release of that click: says what was cast, or why nothing was.
local function Say(text, kind)
    if not text then return end
    local notify = MB.db.buffwatch.notify
    if notify == "toast" then
        Theme:Toast(text, kind, true)
    elseif notify == "chat" then
        MB:Print(text)
    end
end

--- What a click was meant to do, said only once the game has gone through with it.
local function CastDescription(action)
    local spell = API.SpellName(action.spell) or "Intellect"
    if action.kind == "brilliance" then
        return spell .. ": " .. action.benefit .. (action.benefit == 1 and " player needs it." or " players need it.")
    end
    local rank = action.downranked and RankNumber("intellect", action.spell)
    local text = spell .. (rank and (" (Rank " .. rank .. ")") or "") .. " on " .. action.name .. "."
    if action.waiting > 1 then
        text = text .. " " .. (action.waiting - 1) .. " more to go."
    end
    return text
end

--- Why a cast the player asked for did not happen, where the game will say.
local function WhyNot(spellID)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, spellID)
        if ok and not IsSecret(noPower) and noPower then return "not enough mana" end
        if ok and not IsSecret(usable) and usable == false then return "not ready" end
    end
    return nil
end

local function ReportCast(ok)
    local wait = awaiting
    if not wait then return end
    awaiting = nil
    castToken = castToken + 1

    if ok then
        local text = CastDescription(wait.action)
        if wait.note then text = wait.note .. " " .. text end
        Say(text, "ok")
        return
    end

    -- The spell never went off: say so rather than claim a buff that is not there.
    local spell = API.SpellName(wait.action.spell) or "The buff"
    local why = WhyNot(wait.action.spell)
    local who = (wait.action.kind == "brilliance") and "" or (" on " .. wait.action.name)
    Say(spell .. who .. ": " .. (why or "the cast did not go off") .. ".", "warn")
end

function BuffWatch:AfterClick()
    local click = clicked
    clicked = nil
    local db = MB.db.buffwatch
    if not click or not (MB.db.general.enabled and db.enabled) then return end

    if click.combat then
        Say("Buff Watch pauses in combat. Ctrl+right-click the orb for the player list.", "warn")
        return
    end

    if click.action then
        -- Nothing is said yet: whether the spell actually goes off is only
        -- known when the game says so, and out of mana it does not.
        castToken = castToken + 1
        local token = castToken
        awaiting = { action = click.action, note = click.note }
        C_Timer.After(CAST_WAIT, function()
            if token == castToken then ReportCast(false) end
        end)
        return
    end

    if click.note then
        Say(click.note, "info")
    elseif not click.active then
        Say("Buff Watch has nothing to watch here.", "info")
    end
end

-------------------------------------------------------------------------------
-- Player list: fixed secure unit buttons, usable in combat
-------------------------------------------------------------------------------
local function UnitTooltip(self)
    local record = RecordFor(self.unit)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = StatusColor(record)
    GameTooltip:AddLine(API.Str(UnitName(self.unit)) or self.unit, r, g, b)
    if state.paused then
        Theme:TipLine(GameTooltip, "Buffs are not read right now.", "dim")
    elseif record == "excluded" then
        Theme:TipLine(GameTooltip, "Not counted (offline, dead, away or filtered).", "dim", true)
    elseif record == "unknown" or record == nil then
        Theme:TipLine(GameTooltip, "Buffs could not be read.", "dim")
    elseif record.status == "missing" then
        Theme:TipLine(GameTooltip, "Missing Intellect", "bad")
    elseif record.status == "weak" then
        local has = RankNumber("intellect", record.aura)
        local can = record.cast and RankNumber("intellect", record.cast)
        if has and can then
            Theme:TipLine(GameTooltip, "Has Rank " .. has .. ", and you can give Rank " .. can, "warn")
        else
            Theme:TipLine(GameTooltip, "A weaker rank than you can give them", "warn")
        end
    elseif record.status == "expiring" then
        Theme:TipLine(GameTooltip, "Expires in " .. math.ceil((record.remaining or 0) / 60) .. " min", "warn")
    elseif record.remaining then
        Theme:TipLine(GameTooltip, "Buffed, " .. math.ceil(record.remaining / 60) .. " min left", "ok")
    else
        Theme:TipLine(GameTooltip, "Buffed", "ok")
    end
    if type(record) == "table" then
        if not record.reachable then
            Theme:TipLine(GameTooltip, "Out of range", "dim")
        end
        -- Said rather than left unsaid: a buff whose rank cannot be told is
        -- taken as good enough, and that is why no upgrade is offered.
        if record.status ~= "missing" and not record.strength and MB.db.buffwatch.upgradeWeaker then
            GameTooltip:AddLine("The rank of this buff could not be told, so it is not compared with yours.",
                0.56, 0.63, 0.79, true)
        end
        local rank = record.cast and RankNumber("intellect", record.cast)
        if rank and record.level and record.cast ~= Spells:GetBest("intellect") then
            GameTooltip:AddLine("Level " .. record.level .. ": Rank " .. rank .. " is the strongest they can take",
                0.56, 0.63, 0.79, true)
        end
    end
    Theme:TipLine(GameTooltip, "Left-click: Arcane Intellect", "dim")
    if Spells:GetBest("brilliance") then
        Theme:TipLine(GameTooltip, "Right-click: Arcane Brilliance", "dim")
    end
    GameTooltip:Show()
end

local function CreateUnitButton(parent, unit, index, context)
    local button = CreateFrame("Button", "MageButlerBuffUnit_" .. unit, parent, "SecureActionButtonTemplate")
    button.unit = unit
    button.context = context
    button:SetSize(CELL_WIDTH, CELL_HEIGHT)
    local column = (index - 1) % LIST_COLUMNS
    local row = math.floor((index - 1) / LIST_COLUMNS)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", column * (CELL_WIDTH + CELL_GAP), -row * (CELL_HEIGHT + CELL_GAP))
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("unit", unit)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(Theme.colors.panel[1], Theme.colors.panel[2], Theme.colors.panel[3], 0.95)

    button.bar = button:CreateTexture(nil, "ARTWORK")
    button.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.bar:SetPoint("TOPLEFT", 0, 0)
    button.bar:SetPoint("BOTTOMLEFT", 0, 0)
    button.bar:SetWidth(3)

    button.text = Theme:Text(button, 10)
    button.text:SetPoint("LEFT", 7, 0)
    button.text:SetPoint("RIGHT", -3, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    Theme:UseAccent(highlight, "SetVertexColor", 0.2)

    button:HookScript("OnEnter", UnitTooltip)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- The client shows and hides each button as its unit comes and goes.
    RegisterUnitWatch(button)
    unitButtons[#unitButtons + 1] = button
    return button
end

local function CreateList()
    local orb = MB.RadialMenu.orb

    list = CreateFrame("Frame", "MageButlerBuffList", UIParent, "SecureHandlerBaseTemplate")
    list:SetFrameStrata("HIGH")
    list:SetClampedToScreen(true)
    list:SetSize(LIST_COLUMNS * (CELL_WIDTH + CELL_GAP), 8 * (CELL_HEIGHT + CELL_GAP))
    list:Hide()

    -- Plain artwork frame, so it can be resized whenever the roster changes.
    listPanel = Theme:CreatePanel(nil, list, "bg")
    listPanel:SetPoint("TOPLEFT", list, "TOPLEFT", -LIST_PAD, LIST_HEADER)
    listPanel:SetFrameLevel(list:GetFrameLevel())

    -- The backdrop is the handle: dragging it moves the list. The list holds
    -- secure buttons, so it can only be moved out of combat.
    list:SetMovable(true)
    listPanel:EnableMouse(true)
    listPanel:RegisterForDrag("LeftButton")
    listPanel:SetScript("OnDragStart", function()
        if MB.db.general.lockPositions or InCombatLockdown() then return end
        listPanel.dragging = true
        list:StartMoving()
    end)
    listPanel:SetScript("OnDragStop", StopListDrag)

    listPanel.title = Theme:Text(listPanel, 12)
    listPanel.title:SetPoint("TOPLEFT", 12, -9)
    listPanel.title:SetText("Buff Watch")
    Theme:UseAccent(listPanel.title, "SetTextColor", 1)

    listPanel.coverage = Theme:Text(listPanel, 11)
    listPanel.coverage:SetPoint("TOPRIGHT", -12, -10)

    listPanel.hint = Theme:Text(listPanel, 9)
    listPanel.hint:SetPoint("BOTTOMLEFT", 12, 8)
    listPanel.hint:SetText("Left-click: Arcane Intellect    Right-click: Arcane Brilliance")
    listPanel.hint:SetTextColor(Theme:Color("dim"))

    -- One container per kind of group; the client switches between them.
    local party = CreateFrame("Frame", "MageButlerBuffListParty", list, "SecureHandlerBaseTemplate")
    party:SetAllPoints()
    for i = 1, #PARTY_TOKENS do
        CreateUnitButton(party, PARTY_TOKENS[i], i, "party")
    end
    RegisterStateDriver(party, "visibility", "[group:raid] hide; show")

    local raid = CreateFrame("Frame", "MageButlerBuffListRaid", list, "SecureHandlerBaseTemplate")
    raid:SetAllPoints()
    for i = 1, #RAID_TOKENS do
        CreateUnitButton(raid, RAID_TOKENS[i], i, "raid")
    end
    RegisterStateDriver(raid, "visibility", "[group:raid] show; hide")

    list:HookScript("OnShow", RefreshList)
    orb:SetFrameRef("bufflist", list)
    BuffWatch.list = list
end

--- Where the player list sits: wherever it was last dragged to, otherwise
--- above the orb and clear of the radial menu.
function BuffWatch:PositionList()
    local db = MB.db.buffwatch
    local scale = MB.db.general.uiScale
    list:SetScale(scale)
    list:ClearAllPoints()
    if db.x and db.y then
        list:SetPoint("CENTER", UIParent, "CENTER", db.x / scale, db.y / scale)
        return
    end
    local radial = MB.db.radial
    list:SetPoint("BOTTOM", MB.RadialMenu.orb, "TOP", 0, radial.radius + radial.buttonSize + 12)
end

--- Opens or closes the player list from insecure code (outside combat).
function BuffWatch:ToggleList()
    if not MB:IsActive() or not MB.db.buffwatch.enabled then return end
    if InCombatLockdown() then
        MB:Print("in combat, Ctrl+right-click the orb to open or close the Buff Watch list.")
        return
    end
    list:SetShown(not list:IsShown())
end

-------------------------------------------------------------------------------
local function CreateIndicators()
    local orb = MB.RadialMenu.orb

    pip = Theme:CreatePip(orb, "TOPRIGHT", -6, -6)
    pip:SetScript("OnClick", function()
        BuffWatch:ToggleList()
    end)
    Theme:RoundTooltip(pip, function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = Theme:Accent()
        GameTooltip:AddLine("Buff Watch", r, g, b)
        BuffWatch:AddTooltipLines(GameTooltip)
        Theme:TipLine(GameTooltip, "Click for the player list", "dim")
        GameTooltip:Show()
    end)

    counter = Theme:Text(orb, 10, "OVERLAY", "OUTLINE")
    counter:SetPoint("BOTTOM", orb, "TOP", 0, 3)
    counter:Hide()
end

function BuffWatch:OnEnable()
    Theme, Spells, Reagents = MB.Theme, MB.Spells, MB.Reagents

    CreateIndicators()
    CreateList()

    local function OnUnitEvent(_, unit)
        if IsSecret(unit) or not tracked[unit] then return end
        if not state.active then return end   -- nothing is being watched
        BuffWatch:Queue()
    end
    MB:RegisterEvent("UNIT_AURA", OnUnitEvent)
    MB:RegisterEvent("UNIT_CONNECTION", OnUnitEvent)
    MB:RegisterEvent("UNIT_FLAGS", OnUnitEvent)

    -- The game going through with a cast, or refusing to. Asked for the
    -- player alone: these fire for every unit in sight otherwise, and for
    -- anyone else the client may hand over secret values that cannot even be
    -- compared.
    MB:RegisterPlayerEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, spellID)
        if awaiting and API.Num(spellID) == awaiting.action.spell then
            ReportCast(true)
        end
    end)
    local function CastStopped(_, _, _, spellID)
        if awaiting and API.Num(spellID) == awaiting.action.spell then
            ReportCast(false)
        end
    end
    MB:RegisterPlayerEvent("UNIT_SPELLCAST_FAILED", CastStopped)
    MB:RegisterPlayerEvent("UNIT_SPELLCAST_FAILED_QUIET", CastStopped)
    MB:RegisterPlayerEvent("UNIT_SPELLCAST_INTERRUPTED", CastStopped)

    MB:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        RefreshList() -- names can change even while combat blocks a full update
        BuffWatch:Queue()
    end)
    MB:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        BuffWatch:Queue()
    end)
    -- The client starting or ending a period in which buff data is withheld.
    MB:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function()
        BuffWatch:Queue()
    end)

    -- Entering combat: switch the orb's buff click off while that is still allowed.
    MB:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        StopListDrag()   -- a drag still under way: dropped at the end of the fight
        -- Lockdown is in force by the time this arrives, so the attributes
        -- cannot be cleared here. Forgetting what was applied is enough:
        -- Update rewrites all three as combat ends.
        if not InCombatLockdown() then
            local orb = MB.RadialMenu.orb
            orb:SetAttribute("type2", nil)
            orb:SetAttribute("spell2", nil)
            orb:SetAttribute("unit2", nil)
        end
        applied.orb = nil
        state.paused, state.pausedWhy = true, "combat"
        dirty = true
        BuffWatch:RefreshVisuals()
    end)
    MB:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if dirty or state.paused then BuffWatch:Update() end
    end)

    MB:On("SPELLS_UPDATED", function()
        autoScope = nil
        wipe(rankCache)
        buffNames, buffNamesPartial = nil, nil
        BuffWatch:Queue()
    end)
    MB:On("INVENTORY_UPDATED", function()
        BuffWatch:Queue()
    end)
    MB:On("SETTINGS_CHANGED", function()
        MB:AfterCombat("buffwatch-layout", function()
            BuffWatch:PositionList()
            local on = MB.db.general.enabled and MB.db.buffwatch.enabled
            -- The orb's Ctrl+right-click reads this before it opens the list.
            MB.RadialMenu.orb:SetAttribute("mbbufflist", on and true or nil)
            if not on then
                list:Hide()
            end
        end)
        -- In combat the update is put off, and the display alone is redrawn.
        if not BuffWatch:Update() then
            BuffWatch:RefreshVisuals()
        end
    end)
end
