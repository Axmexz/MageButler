-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: trade assistant.
-- Offers the configured amount of conjured water and food when a trade opens.
--
-- Safety rules this file keeps:
--   * only conjured food and water from the Conjuring whitelist are ever picked up
--   * only empty trade slots are used, so nothing already offered is replaced
--   * the trade is never accepted or completed here
--   * one automatic pass per trade; later changes to the window do not restart it
--   * if the client refuses addon-driven filling, automation switches itself off
--     for the session and the player-clicked Fill Trade control remains

local ADDON_NAME, MB = ...
local Trade = MB:NewModule("Trade")
local API = MB.API

local TRADE_SLOTS = _G.MAX_TRADABLE_ITEMS or 6
local MAX_STEPS = 30
local STEP_GAP = 0.05    -- pause between two stacks: about a frame
local VERIFY_WAIT = 0.4  -- how long the trade window gets to show a stack

-- Classes without a mana bar have no use for water.
local FOOD_ONLY_CLASS = { WARRIOR = true, ROGUE = true }

local tradeOpen = false
local autoBlocked = false
local job

-------------------------------------------------------------------------------
-- Trade window state
-------------------------------------------------------------------------------
local function TradeSlotItem(slot)
    local name, _, quantity = GetTradePlayerItemInfo(slot)
    if not API.Str(name) then return nil end
    local link = API.Str(GetTradePlayerItemLink(slot))
    local itemID = link and tonumber(link:match("item:(%d+)"))
    return itemID or 0, API.Num(quantity, 1)
end

--- Conjured water and food already sitting in the player's side of the trade.
local function Offered()
    local water, food = 0, 0
    for slot = 1, TRADE_SLOTS do
        local itemID, quantity = TradeSlotItem(slot)
        local kind = itemID and MB.Conjuring:KindOf(itemID)
        if kind == "water" or kind == "both" then water = water + quantity end
        if kind == "food" or kind == "both" then food = food + quantity end
    end
    return water, food
end

local function FreeTradeSlot(used)
    for slot = 1, TRADE_SLOTS do
        if not used[slot] and not TradeSlotItem(slot) then
            return slot
        end
    end
    return nil
end

--- "party", "raid" or "other", from the trade partner's relation to the player.
local function PartnerPreset()
    local partner = API.Str(UnitName("NPC"))
    if not partner or not IsInGroup() then return "other" end
    local raid = IsInRaid()
    local prefix = raid and "raid" or "party"
    for i = 1, API.Num(GetNumGroupMembers(), 0) do
        if API.Str(UnitName(prefix .. i)) == partner then
            return raid and "raid" or "party"
        end
    end
    return "other"
end

function Trade:GetPreset()
    local name = PartnerPreset()
    return MB.db.trade.presets[name], name
end

--- What to offer this trade partner: the preset's amounts, with the water
--- left out for classes that cannot drink it. Returns water, food, the preset
--- name and whether the water was dropped for the partner's class.
function Trade:GetAmounts()
    local preset, name = self:GetPreset()
    local water, food = preset.water, preset.food
    local foodOnly = false
    if MB.db.trade.classAware and water > 0 then
        local _, class = UnitClass("NPC")
        if not MB.IsSecret(class) and class and FOOD_ONLY_CLASS[class] then
            water = 0
            foodOnly = true
        end
    end
    return water, food, name, foodOnly
end

-------------------------------------------------------------------------------
-- Bag search
-------------------------------------------------------------------------------
--- Finds the bag stack to offer next. Prefers the best item rank, then one
--- stack that covers the whole amount (smallest that does), then the largest
--- stack. Returns bag, slot, itemID, stackCount - or nil plus whether a
--- suitable stack exists but is locked right now.
local function FindSource(kind, need)
    local locked = false
    local items = MB.Conjuring:ItemsBestFirst(kind)
    for i = 1, #items do
        local wanted = items[i]
        if API.ItemCount(wanted) > 0 then
            local coverBag, coverSlot, coverCount
            local bigBag, bigSlot, bigCount
            for bag = 0, MB.LAST_BAG do
                for slot = 1, API.BagSlots(bag) do
                    local itemID, count, isLocked = API.BagItem(bag, slot)
                    if itemID == wanted then
                        if isLocked then
                            locked = true
                        else
                            if count >= need and (not coverCount or count < coverCount) then
                                coverBag, coverSlot, coverCount = bag, slot, count
                            end
                            if not bigCount or count > bigCount then
                                bigBag, bigSlot, bigCount = bag, slot, count
                            end
                        end
                    end
                end
            end
            if coverBag then return coverBag, coverSlot, wanted, coverCount end
            if bigBag then return bigBag, bigSlot, wanted, bigCount end
        end
    end
    return nil, locked
end

local function FindEmptyBagSlot()
    for bag = 0, MB.LAST_BAG do
        local free, general = API.BagFree(bag)
        if general and free > 0 then
            for slot = 1, API.BagSlots(bag) do
                if not C_Container.GetContainerItemInfo(bag, slot) then
                    return bag, slot
                end
            end
        end
    end
    return nil
end

local function CursorItem()
    local kind, itemID = GetCursorInfo()
    if MB.IsSecret(kind) or kind == nil then return nil end
    return kind, API.Num(itemID)
end

-------------------------------------------------------------------------------
-- Fill job: stacks are offered back to back, about a frame apart, and the
-- result is checked against the trade window once at the end.
-------------------------------------------------------------------------------
local Step

local function Continue(delay)
    local current = job
    if not current then return end
    current.token = current.token + 1
    local token = current.token
    C_Timer.After(delay, function()
        if job == current and current.token == token then
            Step()
        end
    end)
end

local function Finish(problem)
    local done = job
    job = nil
    if not done then return end

    local parts = {}
    if done.placed.water > 0 then parts[#parts + 1] = done.placed.water .. " Water" end
    if done.placed.food > 0 then parts[#parts + 1] = done.placed.food .. " Food" end

    local shortfall = {}
    if done.short.water > 0 then shortfall[#shortfall + 1] = done.short.water .. " water" end
    if done.short.food > 0 then shortfall[#shortfall + 1] = done.short.food .. " food" end

    local label = done.manual and "Trade: " or "Auto-trade: "
    if #parts > 0 then
        local text = label .. "filled trade with " .. table.concat(parts, " and ") .. "."
        if done.foodOnly then
            text = text .. " No water: this class has no mana."
        end
        if #shortfall > 0 then
            text = text .. " Short by " .. table.concat(shortfall, " and ") .. "."
        elseif problem then
            text = text .. " " .. problem
        end
        MB:Notify(text, (#shortfall > 0 or problem) and "warn" or "ok")
    elseif problem then
        MB:Notify(label .. problem, "warn")
    elseif #shortfall > 0 then
        MB:Notify(label .. "no conjured " .. table.concat(shortfall, " or ") .. " to offer.", "warn")
    elseif done.manual then
        MB:Notify("Trade already holds the configured food and water.", "info")
    end
end

--- Stops offering and confirms what the trade window actually took. Only
--- stacks that show up there are reported as traded.
local function Verify(problem)
    local current = job
    if not current then return end
    current.verifying = true
    current.problem = current.problem or problem
    if #current.pending == 0 then
        return Finish(current.problem)
    end
    Continue(STEP_GAP)
end

Step = function()
    local current = job
    if not current then return end
    if not tradeOpen then
        job = nil
        return
    end

    current.steps = current.steps + 1
    if current.steps > MAX_STEPS then
        return Finish("stopped after too many attempts.")
    end

    if current.verifying then
        local pending = current.pending
        for i = #pending, 1, -1 do
            local entry = pending[i]
            if TradeSlotItem(entry.slot) then
                current.placed[entry.kind] = current.placed[entry.kind] + entry.amount
                table.remove(pending, i)
            end
        end
        if #pending == 0 then
            return Finish(current.problem)
        end
        current.verifyWaits = current.verifyWaits + 1
        if current.verifyWaits > 4 then
            return Finish(current.problem or "the trade window did not accept every stack.")
        end
        return Continue(VERIFY_WAIT)
    end

    -- What is still missing: the target, minus what the window held at the
    -- start, minus what has been sent since (it may not show there yet).
    local need = {
        water = current.target.water - current.base.water - current.sent.water - current.short.water,
        food = current.target.food - current.base.food - current.sent.food - current.short.food,
    }

    while true do
        local kind = (need.water > 0 and "water") or (need.food > 0 and "food") or nil
        if not kind then
            return Verify()
        end

        local tradeSlot = FreeTradeSlot(current.used)
        if not tradeSlot then
            return Verify("the trade window is full.")
        end
        if CursorItem() then
            return Verify("your cursor is holding something, so nothing more was moved.")
        end

        local bag, slot, itemID, count = FindSource(kind, need[kind])
        if not bag then
            local locked = slot
            if locked and current.lockWaits < 12 then
                current.lockWaits = current.lockWaits + 1
                return Continue(0.15)
            end
            -- Nothing (more) of this kind to give; move on to the next kind.
            current.short[kind] = current.short[kind] + need[kind]
            need[kind] = 0
        else
            local amount = math.min(count, need[kind])
            local partial = amount < count

            if partial and current.splitViaBag then
                -- This client does not take a split stack straight into the
                -- trade window: split into a free bag slot and offer it next step.
                local emptyBag, emptySlot = FindEmptyBagSlot()
                if not emptyBag then
                    return Verify("no free bag slot to split a stack.")
                end
                C_Container.SplitContainerItem(bag, slot, amount)
                local cursorKind, cursorID = CursorItem()
                if cursorKind ~= "item" or cursorID ~= itemID then
                    if cursorKind then ClearCursor() end
                    return Verify("could not split a stack.")
                end
                C_Container.PickupContainerItem(emptyBag, emptySlot)
                if CursorItem() then ClearCursor() end
                -- The new stack exists once the server answers; until then it is locked.
                return Continue(0.3)
            end

            if partial then
                C_Container.SplitContainerItem(bag, slot, amount)
            else
                C_Container.PickupContainerItem(bag, slot)
            end

            -- Only ever hand over exactly the item that was meant to be picked up.
            local cursorKind, cursorID = CursorItem()
            if cursorKind ~= "item" or cursorID ~= itemID then
                if cursorKind then ClearCursor() end
                current.failures = current.failures + 1
                if current.failures > 3 then
                    return Verify("could not pick up the items.")
                end
                return Continue(0.15)
            end

            ClickTradeButton(tradeSlot)

            if CursorItem() then
                -- The trade slot refused the stack; put it back where it came from.
                ClearCursor()
                if partial and not current.splitViaBag then
                    current.splitViaBag = true
                    return Continue(0.15)
                end
                return Verify("the trade window refused the items.")
            end

            -- Sent. The next stack follows a frame later; nothing waits on the server here.
            current.used[tradeSlot] = true
            current.sent[kind] = current.sent[kind] + amount
            current.pending[#current.pending + 1] = { slot = tradeSlot, kind = kind, amount = amount }
            return Continue(STEP_GAP)
        end
    end
end

local function StartJob(manual)
    if job or not tradeOpen then return end
    local wantWater, wantFood, _, foodOnly = Trade:GetAmounts()

    local water, food = Offered()
    if not manual and wantWater - water <= 0 and wantFood - food <= 0 then
        return -- nothing configured for this kind of trade partner
    end

    job = {
        manual = manual,
        foodOnly = foodOnly,
        target = { water = wantWater, food = wantFood },
        base = { water = water, food = food },
        sent = { water = 0, food = 0 },
        placed = { water = 0, food = 0 },
        short = { water = 0, food = 0 },
        pending = {},
        used = {},
        steps = 0,
        token = 0,
        lockWaits = 0,
        failures = 0,
        verifyWaits = 0,
    }
    Step()
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------
function Trade:IsOpen()
    return tradeOpen
end

function Trade:IsAutoBlocked()
    return autoBlocked
end

--- Player-initiated fill. Tops the trade up to the configured amounts.
function Trade:Fill(manual)
    if not MB:IsActive() then return end
    if not tradeOpen then
        if manual then
            -- UnitIsUnit can come back secret on restricted maps; treat that as "not me".
            local isSelf = UnitIsUnit("player", "target")
            if MB.IsSecret(isSelf) then isSelf = false end
            if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target")
                and not isSelf then
                InitiateTrade("target")
            else
                MB:Notify("Open a trade window first, or target a player to trade with.", "info")
            end
        end
        return
    end
    if job then return end
    StartJob(manual and true or false)
end

function Trade:DescribePreset()
    local water, food, name, foodOnly = self:GetAmounts()
    local label = name:sub(1, 1):upper() .. name:sub(2)
    local text = label .. " preset: " .. water .. " water, " .. food .. " food"
    if foodOnly then
        text = text .. " (food only for this class)"
    end
    return text
end

-------------------------------------------------------------------------------
-- Fill Trade button on the trade window (the manual fallback)
-------------------------------------------------------------------------------
local fillButton

local function UpdateFillButton()
    if not fillButton then
        if not (tradeOpen and TradeFrame) then return end
        fillButton = MB.Theme:CreateButton(TradeFrame, "Fill Trade", 92, 22)
        fillButton:SetPoint("BOTTOMLEFT", TradeFrame, "TOPLEFT", 8, 2)
        fillButton:SetFrameStrata("HIGH")
        fillButton:SetScript("OnClick", function()
            Trade:Fill(true)
        end)
        fillButton:SetScript("OnEnter", function(self)
            MB.Theme:ShowTooltip(self, "Fill Trade", Trade:DescribePreset(),
                "Adds conjured water and food up to the preset amounts. You still accept the trade yourself.")
        end)
        fillButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    fillButton:SetShown(MB:IsActive() and MB.db.trade.showFillButton)
end

-------------------------------------------------------------------------------
--- Clears a remembered refusal so automatic filling is attempted again.
function Trade:RetryAutomatic()
    autoBlocked = false
    MB.db.trade.blockedBuild = ""
end

function Trade:OnEnable()
    local _, build = GetBuildInfo()
    self.build = tostring(build or "")
    autoBlocked = (self.build ~= "" and MB.db.trade.blockedBuild == self.build)

    MB:RegisterEvent("TRADE_SHOW", function()
        tradeOpen = true
        job = nil
        UpdateFillButton()
        if not MB:IsActive() or not MB.db.trade.enabled or autoBlocked then return end
        if IsShiftKeyDown() then return end -- hold Shift to trade without the butler
        -- One automatic pass per trade, started on the next frame.
        C_Timer.After(0, function()
            if tradeOpen and not job then
                StartJob(false)
            end
        end)
    end)

    MB:RegisterEvent("TRADE_CLOSED", function()
        tradeOpen = false
        job = nil
    end)

    -- Lets a job that is waiting for confirmation finish sooner. A finished or
    -- absent job is never restarted by a change to the window.
    MB:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", function()
        if job and job.verifying then
            Continue(STEP_GAP)
        end
    end)

    local function OnBlocked(_, addon)
        if addon ~= ADDON_NAME or not job then return end
        local manual = job.manual
        job = nil
        if CursorItem() then ClearCursor() end
        if manual then
            MB:Notify("The client only allows one stack per click here. Click Fill Trade again for the next stack.", "warn")
        else
            -- Remembered for this client build so the refusal is not provoked again.
            autoBlocked = true
            MB.db.trade.blockedBuild = Trade.build
            MB:Notify("This client does not allow automatic trade filling. Use the Fill Trade button instead.", "warn")
        end
    end
    MB:RegisterEvent("ADDON_ACTION_BLOCKED", OnBlocked)
    MB:RegisterEvent("ADDON_ACTION_FORBIDDEN", OnBlocked)

    MB:On("SETTINGS_CHANGED", function()
        if fillButton then UpdateFillButton() end
    end)
end
