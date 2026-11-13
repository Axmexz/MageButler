-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: reagent inventory and merchant restocking.

local _, MB = ...
local Reagents = MB:NewModule("Reagents")
local API = MB.API

Reagents.ORDER = { "runeT", "runeP", "powder" }
Reagents.ITEMS = { runeT = 17031, runeP = 17032, powder = 17020 }
Reagents.SHORT = { runeT = "Rune T", runeP = "Rune P", powder = "Arcane" }

local FALLBACK_NAME = {
    runeT = "Rune of Teleportation",
    runeP = "Rune of Portals",
    powder = "Arcane Powder",
}
local FALLBACK_STACK = { runeT = 10, runeP = 10, powder = 20 }

local POPUP = "MAGEBUTLER_RESTOCK"

local counts = {}
local warned = {}
local merchantOpen = false
local visitDone = false

-------------------------------------------------------------------------------
-- Inventory
-------------------------------------------------------------------------------
function Reagents:Name(key)
    return API.ItemName(self.ITEMS[key]) or FALLBACK_NAME[key]
end

function Reagents:Count(key)
    return counts[key] or 0
end

--- A reagent is tracked when it is enabled and the player knows a spell that
--- consumes it, so low-level Mages are not nagged about Rune of Portals.
function Reagents:IsTracked(key)
    local config = MB.db.reagents.items[key]
    return config ~= nil and config.enabled and MB.Spells:UsesReagent(key)
end

--- "ok", "low", "none", or "off" when the reagent is not tracked.
function Reagents:State(key)
    if not self:IsTracked(key) then return "off" end
    local have = self:Count(key)
    if have <= 0 then return "none" end
    if have <= MB.db.reagents.items[key].warn then return "low" end
    return "ok"
end

function Reagents:RefreshInventory()
    local low = {}
    for _, key in ipairs(self.ORDER) do
        counts[key] = API.ItemCount(self.ITEMS[key])
        local state = self:State(key)
        if state == "low" or state == "none" then
            -- Warn once per shortage; standing at a vendor is not the moment.
            if not warned[key] and not merchantOpen then
                warned[key] = true
                low[#low + 1] = self:Name(key) .. " (" .. counts[key] .. ")"
            end
        else
            warned[key] = nil
        end
    end
    if #low > 0 and MB:IsActive() then
        MB:Notify("Low on " .. table.concat(low, ", ") .. ".", "warn")
    end
end

-------------------------------------------------------------------------------
-- Merchant
-------------------------------------------------------------------------------
--- Returns price, bundleSize, numAvailable (-1 = unlimited), purchasable.
local function MerchantItem(index)
    local price, bundle, available, purchasable, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if not info then return nil end
        price, bundle, available = info.price, info.stackCount, info.numAvailable
        purchasable, extended = info.isPurchasable, info.hasExtendedCost
    elseif _G.GetMerchantItemInfo then
        local _
        _, _, price, bundle, available, purchasable, _, extended = _G.GetMerchantItemInfo(index)
    else
        return nil
    end

    price = API.Num(price)
    if not price then return nil end
    bundle = API.Num(bundle, 1)
    if bundle < 1 then bundle = 1 end
    available = API.Num(available, -1)
    if MB.IsSecret(purchasable) or purchasable == nil then purchasable = true end
    if MB.IsSecret(extended) then extended = true end
    return price, bundle, available, (purchasable and not extended) and true or false
end

local function FindMerchantIndex(itemID)
    for index = 1, API.Num(GetMerchantNumItems(), 0) do
        if API.Num(GetMerchantItemID(index)) == itemID then
            return index
        end
    end
    return nil
end

--- Room left in stacks of this item that are already in the bags.
local function PartialStackRoom(itemID, stackSize)
    local room = 0
    for bag = 0, MB.LAST_BAG do
        for slot = 1, API.BagSlots(bag) do
            local id, count = API.BagItem(bag, slot)
            if id == itemID and count < stackSize then
                room = room + (stackSize - count)
            end
        end
    end
    return room
end

--- Works out what to buy. Returns the purchase list and a list of reasons for
--- anything that had to be reduced or skipped.
local function BuildPlan()
    local plan, notes = {}, {}

    local freeSlots = 0
    for bag = 0, MB.LAST_BAG do
        local free, general = API.BagFree(bag)
        if general then freeSlots = freeSlots + free end
    end
    local money = API.Num(GetMoney(), 0)

    for _, key in ipairs(Reagents.ORDER) do
        local config = MB.db.reagents.items[key]
        if Reagents:IsTracked(key) then
            local itemID = Reagents.ITEMS[key]
            local have = API.ItemCount(itemID)
            local wanted = config.target - have
            local index = wanted > 0 and FindMerchantIndex(itemID) or nil
            local price, bundle, available, purchasable
            if index then
                price, bundle, available, purchasable = MerchantItem(index)
            end

            if index and price and purchasable then
                local name = Reagents:Name(key)
                local quantity = wanted

                if available >= 0 then
                    quantity = math.min(quantity, available * bundle)
                end

                local stackSize = API.ItemStackSize(itemID) or FALLBACK_STACK[key]
                local partial = PartialStackRoom(itemID, stackSize)
                local room = partial + freeSlots * stackSize
                if quantity > room then
                    quantity = room
                    notes[#notes + 1] = name .. ": bags are full"
                end

                local unit = price / bundle
                if unit > 0 then
                    local budget = money
                    local limited = false
                    if config.maxSpend > 0 and config.maxSpend * 10000 < budget then
                        budget = config.maxSpend * 10000
                        limited = true
                    end
                    local affordable = math.floor(budget / unit)
                    if quantity > affordable then
                        quantity = affordable
                        notes[#notes + 1] = name .. (limited and ": spending limit reached" or ": not enough gold")
                    end
                end

                -- Whole merchant bundles only, and never past the target.
                quantity = math.floor(quantity / bundle) * bundle

                if quantity > 0 then
                    local cost = unit * quantity
                    money = money - cost
                    freeSlots = freeSlots - math.ceil(math.max(0, quantity - partial) / stackSize)
                    plan[#plan + 1] = {
                        key = key,
                        itemID = itemID,
                        index = index,
                        quantity = quantity,
                        bundle = bundle,
                        unit = unit,
                        cost = cost,
                        have = have,
                        confirm = config.confirm,
                    }
                end
            end
        end
    end
    return plan, notes
end

local function Describe(entries)
    local parts, total = {}, 0
    for i = 1, #entries do
        local entry = entries[i]
        parts[#parts + 1] = entry.quantity .. " " .. Reagents:Name(entry.key)
        total = total + entry.cost
    end
    return table.concat(parts, ", "), total
end

--- Reports what actually arrived in the bags, not what was requested.
local function ReportPurchase(entries)
    local parts, total, short = {}, 0, false
    for i = 1, #entries do
        local entry = entries[i]
        local gained = API.ItemCount(entry.itemID) - entry.have
        if gained > 0 then
            parts[#parts + 1] = gained .. " " .. Reagents:Name(entry.key)
            total = total + entry.unit * gained
        end
        if gained < entry.quantity then short = true end
    end
    if #parts > 0 then
        MB:Notify("Restocked " .. table.concat(parts, ", ") .. " for " .. MB.FormatMoney(total) .. ".", short and "warn" or "ok")
    else
        MB:Notify("Reagent purchase did not go through.", "warn")
    end
end

local function Execute(entries)
    if not merchantOpen then return end
    local bought = {}
    for i = 1, #entries do
        local entry = entries[i]
        -- The merchant page can change while a confirmation is open.
        if API.Num(GetMerchantItemID(entry.index)) == entry.itemID then
            if entry.bundle > 1 then
                for _ = 1, entry.quantity / entry.bundle do
                    BuyMerchantItem(entry.index)
                end
            else
                local maxStack = API.Num(GetMerchantItemMaxStack(entry.index), 1)
                if maxStack < 1 then maxStack = 1 end
                local left = entry.quantity
                while left > 0 do
                    local amount = math.min(left, maxStack)
                    BuyMerchantItem(entry.index, amount)
                    left = left - amount
                end
            end
            bought[#bought + 1] = entry
        end
    end
    if #bought > 0 then
        C_Timer.After(1.5, function()
            ReportPurchase(bought)
        end)
    end
end

local function TryRestock()
    if not merchantOpen or visitDone then return end
    if not MB:IsActive() or not MB.db.reagents.enabled then return end
    if API.Num(GetMerchantNumItems(), 0) == 0 then return end -- retried on MERCHANT_UPDATE
    visitDone = true

    local plan, notes = BuildPlan()

    local automatic, needsConfirm = {}, {}
    for i = 1, #plan do
        if plan[i].confirm then
            needsConfirm[#needsConfirm + 1] = plan[i]
        else
            automatic[#automatic + 1] = plan[i]
        end
    end

    if #automatic > 0 then
        Execute(automatic)
    end
    if #needsConfirm > 0 then
        local text, total = Describe(needsConfirm)
        StaticPopup_Show(POPUP, text, MB.FormatMoney(total), needsConfirm)
    end
    if #notes > 0 then
        MB:Notify(table.concat(notes, "; ") .. ".", "warn")
    end
end

-------------------------------------------------------------------------------
function Reagents:OnEnable()
    for _, key in ipairs(self.ORDER) do
        API.RequestItem(self.ITEMS[key])
    end

    StaticPopupDialogs[POPUP] = {
        text = "MageButler: buy %s for %s?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function(_, entries)
            if entries then Execute(entries) end
        end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    MB:RegisterEvent("MERCHANT_SHOW", function()
        merchantOpen = true
        visitDone = false
        -- A short pause lets the merchant's item list finish loading.
        C_Timer.After(0.2, TryRestock)
    end)
    MB:RegisterEvent("MERCHANT_UPDATE", function()
        if merchantOpen and not visitDone then
            MB:Debounce("restock", 0.2, TryRestock)
        end
    end)
    MB:RegisterEvent("MERCHANT_CLOSED", function()
        merchantOpen = false
        visitDone = false
        StaticPopup_Hide(POPUP)
    end)

    -- Which reagents matter depends on the spells known.
    MB:On("SPELLS_UPDATED", function()
        MB:RefreshInventory()
    end)
end
