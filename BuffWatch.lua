-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: Buff Watch.
-- Watches the Mage, the party or the raid (up to 40 players) for missing or
-- expiring Arcane Intellect / Arcane Brilliance and works out the cheapest
-- useful cast. Right-clicking the orb casts that one spell: every cast is a
-- single secure click by the player, never a sequence.
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

-- Relative strength of each rank, so a weaker buff can be told from an equal one.
local STRENGTH = {
    [1459] = 1, [1460] = 2, [1461] = 3, [10156] = 4, [10157] = 5, [27126] = 6,
    [23028] = 5, [27127] = 6,
}
local NO_MANA_CLASS = { WARRIOR = true, ROGUE = true }

-- Used for "auto" scope when the spell's own description gives no answer.
-- On WoW Forever the Arcane Brilliance tooltip reads "the target's party and
-- raid", unlike original vanilla where it reached the target's party only.
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
    context = "solo",
    total = 0, ok = 0, expiring = 0, missing = 0, unreadable = 0, outOfRange = 0,
    overall = "off",
    units = {},
    byUnit = {},
    action = nil,
    note = nil,
}

local buffNames
local autoScope
local applied = {}
local dirty = false
local timerToken = 0
local clicked
local pip, counter, list, listPanel
local unitButtons = {}

-------------------------------------------------------------------------------
-- Reading the game
-------------------------------------------------------------------------------
local function Flag(value, default)
    if IsSecret(value) then return default end
    return value and true or false
end

--- Localised names of the two buffs; every rank shares one of them.
local function BuffNames()
    if buffNames then return buffNames end
    local names = {}
    local intellect, brilliance = API.SpellName(INTELLECT_ID), API.SpellName(BRILLIANCE_ID)
    if intellect then names[#names + 1] = intellect end
    if brilliance and brilliance ~= intellect then names[#names + 1] = brilliance end
    if #names > 0 then buffNames = names end
    return names
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
            return "buffed", remaining, spellID and STRENGTH[spellID] or nil
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
        for _, spellID in ipairs({ INTELLECT_ID, BRILLIANCE_ID }) do
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
    state.total, state.ok, state.expiring, state.missing = 0, 0, 0, 0
    state.unreadable, state.outOfRange = 0, 0
    state.action, state.note = nil, nil
end

local function Evaluate()
    local db = MB.db.buffwatch
    local context = Context()
    state.context = context
    state.paused = false
    ResetCounts()

    local intellect = Spells:GetBest("intellect")
    state.active = MB.db.general.enabled and db.enabled and db[context] and intellect ~= nil
    if not state.active then
        state.overall = "off"
        return
    end
    if AurasRestricted() then
        -- Nothing can be read reliably: show "paused", recommend nothing.
        state.paused = true
        state.overall = "off"
        return
    end

    local rebuff = db.watchExpiry and db.rebuffMinutes * 60 or nil
    local myStrength = STRENGTH[intellect]
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
                local found, remaining, strength = ReadBuff(unit)
                if found == "unknown" then
                    state.unreadable = state.unreadable + 1
                    state.byUnit[unit] = "unknown"
                else
                    local status = "ok"
                    if found == "missing" then
                        status = "missing"
                    elseif not db.acceptLowerRanks and strength and myStrength and strength < myStrength then
                        status = "missing" -- a weaker rank than the one this Mage would cast
                    elseif rebuff and remaining and remaining < rebuff then
                        status = "expiring"
                    end

                    local subgroup
                    if context == "raid" then
                        local _, _, group = GetRaidRosterInfo(index)
                        subgroup = API.Num(group)
                    end

                    local record = {
                        unit = unit,
                        name = API.Str(UnitName(unit)) or unit,
                        status = status,
                        remaining = remaining,
                        reachable = Reachable(unit, intellect),
                        subgroup = subgroup or 1,
                    }
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
    elseif state.expiring > 0 then
        state.overall = "low"
    else
        state.overall = "ok"
    end
end

--- Players who need the buff, in the order they should be served.
local function Needs()
    local missing, expiring = {}, {}
    for i = 1, #state.units do
        local record = state.units[i]
        if record.status == "missing" then
            missing[#missing + 1] = record
        elseif record.status == "expiring" then
            expiring[#expiring + 1] = record
        end
    end
    table.sort(expiring, function(a, b)
        return (a.remaining or 0) < (b.remaining or 0)
    end)

    local needs = {}
    if MB.db.buffwatch.missingFirst then
        for i = 1, #missing do needs[#needs + 1] = missing[i] end
        for i = 1, #expiring do needs[#needs + 1] = expiring[i] end
    else
        -- Roster order, whatever the reason.
        for i = 1, #state.units do
            if state.units[i].status ~= "ok" then needs[#needs + 1] = state.units[i] end
        end
    end
    return needs
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
            benefit = #needs
            target = "player"
            worthIt = benefit >= (context == "raid" and db.raidThreshold or db.partyThreshold)
        else
            -- Group-scoped Brilliance in a raid: aim it at the subgroup that
            -- gains the most, and judge it on the raid as a whole.
            local count, reach = {}, {}
            for i = 1, #needs do
                local record = needs[i]
                count[record.subgroup] = (count[record.subgroup] or 0) + 1
                if record.reachable and not reach[record.subgroup] then
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
            if Reagents:Count("powder") > 0 then
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

    -- Otherwise one player at a time, nearest need first, skipping anyone out of range.
    for i = 1, #needs do
        local record = needs[i]
        if record.reachable then
            state.action = {
                kind = "intellect", spell = intellect, unit = record.unit,
                name = record.name, waiting = #needs,
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

    local intellect, brilliance = Spells:GetBest("intellect"), Spells:GetBest("brilliance")
    if applied.intellect ~= intellect or applied.brilliance ~= brilliance or not applied.buttons then
        for i = 1, #unitButtons do
            local button = unitButtons[i]
            -- "*" = whatever modifier keys are held.
            button:SetAttribute("*type1", intellect and "spell" or nil)
            button:SetAttribute("*spell1", intellect)
            button:SetAttribute("*type2", brilliance and "spell" or nil)
            button:SetAttribute("*spell2", brilliance)
        end
        applied.intellect, applied.brilliance, applied.buttons = intellect, brilliance, true
    end
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------
local function Headline()
    if state.paused then
        return InCombatLockdown() and "Paused in combat" or "Paused (buffs cannot be read here)"
    end
    if state.overall == "ok" then return "Everyone is buffed" end
    if state.overall == "low" then return "Buffs expiring soon" end
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
    if record.status == "expiring" then return Theme:Color("warn") end
    return Theme:Color("ok")
end

local function RefreshList()
    if not listPanel then return end

    local shown = 0
    for i = 1, #unitButtons do
        local button = unitButtons[i]
        local unit = button.unit
        if button.context == state.context or (button.context == "party" and state.context == "solo") then
            if UnitExists(unit) then
                shown = shown + 1
                button.text:SetText(API.Str(UnitName(unit)) or unit)
                local r, g, b = StatusColor(state.byUnit[unit])
                button.text:SetTextColor(r, g, b)
                button.bar:SetVertexColor(r, g, b)
            end
        end
    end

    local rows = math.max(1, math.ceil(shown / LIST_COLUMNS))
    listPanel:SetSize(LIST_COLUMNS * (CELL_WIDTH + CELL_GAP) - CELL_GAP + LIST_PAD * 2,
        LIST_HEADER + rows * (CELL_HEIGHT + CELL_GAP) + LIST_FOOTER + LIST_PAD)

    if state.active and state.total > 0 then
        listPanel.coverage:SetText((state.ok + state.expiring) .. "/" .. state.total .. " buffed")
        listPanel.coverage:SetTextColor(Theme:StateColor(state.overall))
    else
        listPanel.coverage:SetText(state.paused and "paused" or "")
        listPanel.coverage:SetTextColor(Theme:Color("off"))
    end
end

function BuffWatch:RefreshVisuals()
    local db = MB.db.buffwatch
    local orb = MB.RadialMenu.orb
    local overall = state.overall
    local watching = MB.db.general.enabled and db.enabled

    if pip then
        if watching and db.orbIndicator then
            pip.dot:SetVertexColor(Theme:StateColor(overall))
            Theme:SetPulse(pip.dot, (not state.paused) and Theme:PulseForState(overall) or nil)
            pip:Show()
        else
            pip:Hide()
        end
    end

    -- Warning colours on the orb's ring; the accent colour when all is well.
    if watching and db.orbColors and (overall == "low" or overall == "none") and not state.paused then
        orb.ring:SetVertexColor(Theme:StateColor(overall))
    else
        orb.ring:SetVertexColor(Theme:Accent())
    end

    if counter then
        if watching and db.showCounter and state.active and state.context ~= "solo" and state.total > 0 then
            counter:SetText((state.ok + state.expiring) .. "/" .. state.total)
            counter:SetTextColor(Theme:StateColor(overall))
            counter:Show()
        else
            counter:Hide()
        end
    end

    RefreshList()
end

--- Buffed and watched player counts, for the HUD and the preparation check.
function BuffWatch:GetCoverage()
    return state.ok + state.expiring, state.total
end

--- "ok", "low" (expiring), "none" (missing), or "off".
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
        tooltip:AddLine(state.note, 0.56, 0.63, 0.79, true)
    end

    if db.tooltipNames and (state.missing > 0 or state.expiring > 0) then
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

-------------------------------------------------------------------------------
-- Updating: driven by events, never by polling
-------------------------------------------------------------------------------
local function ScheduleExpiryCheck()
    timerToken = timerToken + 1
    local db = MB.db.buffwatch
    if not (state.active and db.watchExpiry) then return end

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
    if not soonest then return end

    local token = timerToken
    C_Timer.After(soonest + 1, function()
        if token == timerToken then BuffWatch:Queue() end
    end)
end

function BuffWatch:Update()
    if InCombatLockdown() then
        dirty = true
        return
    end
    dirty = false
    Evaluate()
    Recommend()
    ApplyAttributes()
    ScheduleExpiryCheck()
    self:RefreshVisuals()
    MB:Fire("BUFFWATCH_UPDATED")
end

function BuffWatch:Queue()
    if InCombatLockdown() then
        dirty = true
        return
    end
    MB:Debounce("buffwatch", 0.25, function()
        BuffWatch:Update()
    end)
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

--- Called on the release of that click: says what was cast, or why nothing was.
function BuffWatch:AfterClick()
    local click = clicked
    clicked = nil
    local db = MB.db.buffwatch
    if not click or not (MB.db.general.enabled and db.enabled) then return end

    local text, kind = nil, "info"
    if click.combat then
        text, kind = "Buff Watch pauses in combat. Ctrl+right-click the orb for the player list.", "warn"
    elseif click.action then
        local action = click.action
        local spell = API.SpellName(action.spell) or "Intellect"
        if action.kind == "brilliance" then
            text = spell .. ": " .. action.benefit .. (action.benefit == 1 and " player needs it." or " players need it.")
        else
            text = spell .. " on " .. action.name .. "."
            if action.waiting > 1 then
                text = text .. " " .. (action.waiting - 1) .. " more to go."
            end
        end
        if click.note then text = click.note .. " " .. text end
        kind = "ok"
    elseif click.note then
        text = click.note
    elseif not click.active then
        text = "Buff Watch has nothing to watch here."
    end
    if not text then return end

    if db.notify == "toast" then
        Theme:Toast(text, kind, true)
    elseif db.notify == "chat" then
        MB:Print(text)
    end
end

-------------------------------------------------------------------------------
-- Player list: fixed secure unit buttons, usable in combat
-------------------------------------------------------------------------------
local function UnitTooltip(self)
    local record = state.byUnit[self.unit]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = StatusColor(record)
    GameTooltip:AddLine(API.Str(UnitName(self.unit)) or self.unit, r, g, b)
    if state.paused then
        GameTooltip:AddLine("Buffs are not read right now.", 0.56, 0.63, 0.79)
    elseif record == "excluded" then
        GameTooltip:AddLine("Not counted (offline, dead, away or filtered).", 0.56, 0.63, 0.79, true)
    elseif record == "unknown" or record == nil then
        GameTooltip:AddLine("Buffs could not be read.", 0.56, 0.63, 0.79)
    elseif record.status == "missing" then
        GameTooltip:AddLine("Missing Intellect", 1, 0.35, 0.35)
    elseif record.status == "expiring" then
        GameTooltip:AddLine("Expires in " .. math.ceil((record.remaining or 0) / 60) .. " min", 1, 0.75, 0.25)
    elseif record.remaining then
        GameTooltip:AddLine("Buffed, " .. math.ceil(record.remaining / 60) .. " min left", 0.35, 0.9, 0.55)
    else
        GameTooltip:AddLine("Buffed", 0.35, 0.9, 0.55)
    end
    if type(record) == "table" and not record.reachable then
        GameTooltip:AddLine("Out of range", 0.56, 0.63, 0.79)
    end
    GameTooltip:AddLine("Left-click: Arcane Intellect", 0.56, 0.63, 0.79)
    if Spells:GetBest("brilliance") then
        GameTooltip:AddLine("Right-click: Arcane Brilliance", 0.56, 0.63, 0.79)
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
    listPanel:EnableMouse(false)

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

function BuffWatch:PositionList()
    local radial = MB.db.radial
    list:SetScale(MB.db.general.uiScale)
    list:ClearAllPoints()
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

    pip = CreateFrame("Button", nil, orb)
    pip:SetSize(16, 16)
    pip:SetPoint("CENTER", orb, "TOPRIGHT", -6, -6)
    pip:SetFrameLevel(orb:GetFrameLevel() + 5)

    pip.rim = pip:CreateTexture(nil, "BACKGROUND")
    pip.rim:SetTexture(MB.MEDIA .. "Circle.tga")
    pip.rim:SetAllPoints()
    pip.rim:SetVertexColor(0.02, 0.04, 0.09)

    pip.dot = pip:CreateTexture(nil, "ARTWORK")
    pip.dot:SetTexture(MB.MEDIA .. "Circle.tga")
    pip.dot:SetPoint("TOPLEFT", 3, -3)
    pip.dot:SetPoint("BOTTOMRIGHT", -3, 3)

    pip:SetScript("OnClick", function()
        BuffWatch:ToggleList()
    end)
    Theme:RoundTooltip(pip, function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = Theme:Accent()
        GameTooltip:AddLine("Buff Watch", r, g, b)
        BuffWatch:AddTooltipLines(GameTooltip)
        GameTooltip:AddLine("Click for the player list", 0.56, 0.63, 0.79)
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
        BuffWatch:Queue()
    end
    MB:RegisterEvent("UNIT_AURA", OnUnitEvent)
    MB:RegisterEvent("UNIT_CONNECTION", OnUnitEvent)
    MB:RegisterEvent("UNIT_FLAGS", OnUnitEvent)

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
        local orb = MB.RadialMenu.orb
        orb:SetAttribute("type2", nil)
        orb:SetAttribute("spell2", nil)
        orb:SetAttribute("unit2", nil)
        applied.orb = nil
        state.paused = true
        dirty = true
        BuffWatch:RefreshVisuals()
    end)
    MB:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if dirty or state.paused then BuffWatch:Update() end
    end)

    MB:On("SPELLS_UPDATED", function()
        autoScope = nil
        BuffWatch:Queue()
    end)
    MB:On("INVENTORY_UPDATED", function()
        BuffWatch:Queue()
    end)
    MB:On("SETTINGS_CHANGED", function()
        MB:AfterCombat("buffwatch-layout", function()
            BuffWatch:PositionList()
            if not (MB.db.general.enabled and MB.db.buffwatch.enabled) then
                list:Hide()
            end
        end)
        BuffWatch:Update()
        BuffWatch:RefreshVisuals()
    end)
end
