-- Minimal WoW Forever API mock for smoke-testing MageButler outside the game.
local js = require "js"
local window = js.global

function LOG(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    window.LOG:push(table.concat(parts, " "))
end

M = {
    combat = false,
    timers = {},
    frames = {},
    money = 500000,
    cursor = nil,
    trade = {},
    merchant = nil,
    bindings = {},
    popups = {},
    bought = {},
    time = 100,
    group = nil,       -- nil, "party" or "raid"
    rejectSplit = false,
    blockPickup = false,
    violations = 0,
    chat = {},
}

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------
local Methods = {}
local WidgetMT = {}

local function NewWidget(kind, name, parent, template)
    local w = {
        __kind = kind, __name = name, __parent = parent, __template = template or "",
        __scripts = {}, __attrs = {}, __events = {}, __shown = true, __w = 0, __h = 0, __scale = 1,
    }
    return setmetatable(w, WidgetMT)
end

WidgetMT.__index = function(_, key)
    local method = Methods[key]
    if method then return method end
    if type(key) == "string" and key:match("^%u") then
        if key:match("^Create") then
            return function(self) return NewWidget(key:sub(7), nil, self) end
        elseif key:match("^Is") or key:match("^Has") or key:match("^Can") then
            return function() return false end
        elseif key:match("^Get") then
            return function() return 0 end
        end
        return function() end
    end
    return nil
end

local function Protected(w)
    return w.__template:find("Secure") ~= nil
end

local function Guard(w, what)
    if M.combat and Protected(w) then
        M.violations = M.violations + 1
        LOG("PROTECTED VIOLATION: " .. what .. " on " .. tostring(w.__name) .. " in combat")
    end
end

function Methods:SetScript(name, fn) self.__scripts[name] = fn end
function Methods:GetScript(name) return self.__scripts[name] end
function Methods:HookScript(name, fn)
    local old = self.__scripts[name]
    if old then
        self.__scripts[name] = function(...) old(...) fn(...) end
    else
        self.__scripts[name] = fn
    end
end
function Methods:Show()
    Guard(self, "Show")
    local was = self.__shown
    self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function Methods:Hide()
    Guard(self, "Hide")
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function Methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Methods:IsShown() return self.__shown end
function Methods:IsVisible() return self.__shown end
function Methods:IsMouseOver() return M.mouseOver ~= false end
function Methods:SetOwner(owner) self.__owner = owner end
function Methods:IsOwned(owner) return self.__owner == owner end
function Methods:SetAttribute(name, value) Guard(self, "SetAttribute") self.__attrs[name] = value end
function Methods:GetAttribute(name) return self.__attrs[name] end
function Methods:SetFrameRef(name, frame) Guard(self, "SetFrameRef") self.__attrs["frameref-" .. name] = frame end
function Methods:WrapScript(frame, script, pre, post)
    Guard(self, "WrapScript")
    frame.__wrap = frame.__wrap or {}
    frame.__wrap[script] = pre
end
function Methods:SetPoint() Guard(self, "SetPoint") end
function Methods:ClearAllPoints() Guard(self, "ClearAllPoints") end
function Methods:SetSize(w, h) Guard(self, "SetSize") self.__w, self.__h = w, h end
function Methods:SetWidth(w) Guard(self, "SetWidth") self.__w = w end
function Methods:SetHeight(h) Guard(self, "SetHeight") self.__h = h end
function Methods:SetScale(s) Guard(self, "SetScale") self.__scale = s end
function Methods:GetScale() return self.__scale end
function Methods:GetEffectiveScale() return self.__scale end
function Methods:GetWidth() return self.__w end
function Methods:GetHeight() return self.__h end
function Methods:GetCenter() return 400, 300 end
function Methods:GetName() return self.__name end
function Methods:GetParent() return self.__parent end
function Methods:GetFrameLevel() return 1 end
function Methods:RegisterEvent(event)
    if event == "LEARNED_SPELL_IN_TAB" then error("unknown event " .. event) end
    self.__events[event] = true
end
function Methods:RegisterForClicks(...) self.__clicks = { ... } end
function Methods:SetText(text) self.__text = tostring(text) end
function Methods:GetText() return self.__text or "" end
function Methods:GetStringWidth() return #(self.__text or "") * 6 end
function Methods:GetStringHeight() return 12 end
function Methods:SetFont() end
function Methods:GetFont() return "font", 12, "" end
function Methods:SetChecked(v) self.__checked = v end
function Methods:GetChecked() return self.__checked end
function Methods:GetCheckedTexture() self.__ct = self.__ct or NewWidget("Texture") return self.__ct end
function Methods:GetThumbTexture() self.__tt = self.__tt or NewWidget("Texture") return self.__tt end
function Methods:SetMinMaxValues(lo, hi) self.__lo, self.__hi = lo, hi end
function Methods:SetValue(v)
    self.__value = v
    if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v, false) end
end
function Methods:GetValue() return self.__value or 0 end
function Methods:IsEnabled() return self.__disabled ~= true end
function Methods:SetEnabled(e) self.__disabled = not e end
function Methods:HasFocus() return false end
function Methods:CreateTexture() return NewWidget("Texture", nil, self) end
function Methods:CreateFontString() return NewWidget("FontString", nil, self) end
function Methods:CreateMaskTexture() return NewWidget("MaskTexture", nil, self) end
function Methods:CreateAnimationGroup() return NewWidget("AnimationGroup", nil, self) end
function Methods:CreateAnimation() return NewWidget("Animation", nil, self) end
function Methods:SetBackdrop(b) self.__backdrop = b end

function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind, name, parent, template)
    if template and template:find("Backdrop") == nil and template:find("Secure") == nil then
        LOG("NOTE: unusual template " .. template)
    end
    if name then _G[name] = w end
    M.frames[#M.frames + 1] = w
    return w
end

function FireEvent(event, ...)
    for i = 1, #M.frames do
        local frame = M.frames[i]
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

function RunScript(widget, script, ...)
    local fn = widget.__scripts[script]
    if fn then return fn(widget, ...) end
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.__w, UIParent.__h = 1024, 768
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
GameTooltip.__shown = false
function GetCursorPosition()
    if M.mouse then return M.mouse.x, M.mouse.y end
    return 400, 300 -- every mock frame is centred here
end
TradeFrame = CreateFrame("Frame", "TradeFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) M.chat[#M.chat + 1] = text end }
GameFontHighlightSmall = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
ACCEPT, CANCEL = "Accept", "Cancel"
NUM_BAG_SLOTS = 4
MAX_TRADABLE_ITEMS = 6
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2 } }

tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower

-------------------------------------------------------------------------------
-- Timers, combat, units
-------------------------------------------------------------------------------
C_Timer = {}
function C_Timer.After(delay, fn)
    M.timers[#M.timers + 1] = { at = M.time + delay, fn = fn }
end

--- Runs only the timers due within the next `seconds`, then moves the clock there.
function RunFor(seconds)
    local stop = M.time + seconds
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 500 then LOG("TIMER LIMIT HIT") break end
        table.sort(M.timers, function(a, b) return a.at < b.at end)
        local timer = M.timers[1]
        if not timer or timer.at > stop then break end
        table.remove(M.timers, 1)
        if timer.at > M.time then M.time = timer.at end
        timer.fn()
    end
    M.time = stop
end

--- Runs queued timers in time order until none are left.
function RunTimers(limit)
    local guard = 0
    while #M.timers > 0 do
        guard = guard + 1
        if guard > (limit or 500) then LOG("TIMER LIMIT HIT") break end
        table.sort(M.timers, function(a, b) return a.at < b.at end)
        local timer = table.remove(M.timers, 1)
        if timer.at > M.time then M.time = timer.at end
        timer.fn()
    end
end

function GetTime() return M.time end
function InCombatLockdown() return M.combat end
function issecretvalue() return false end
function GetBuildInfo() return "1.60.1", "70938", "Nov 1 2026", 16001 end
-- Roster: unit token -> { name, class, online, dead, visible, inRange, subgroup, aura }
M.roster = { player = { name = "Tester", class = "MAGE", online = true, visible = true, inRange = true, subgroup = 1 } }

--- Builds a party (player + party1..N-1) or a raid (raid1..N, raid1 being the player).
function SetGroup(kind, size)
    local me = M.roster.player
    M.group = kind
    M.roster = { player = me }
    if kind == "party" then
        for i = 1, (size or 5) - 1 do
            M.roster["party" .. i] = { name = (i == 1) and "Partner" or ("Party" .. i), class = "PRIEST",
                online = true, visible = true, inRange = true, subgroup = 1 }
        end
    elseif kind == "raid" then
        M.roster.raid1 = me
        for i = 2, size or 40 do
            M.roster["raid" .. i] = { name = (i == 7) and "Partner" or ("Raider" .. i), class = "PRIEST",
                online = true, visible = true, inRange = true, subgroup = math.floor((i - 1) / 5) + 1 }
        end
    end
end

function SetAura(unit, spellId, secondsLeft)
    local names = { [1459] = "Arcane Intellect", [10157] = "Arcane Intellect", [23028] = "Arcane Brilliance" }
    local entry = M.roster[unit]
    if not spellId then entry.aura = nil return end
    entry.aura = { name = names[spellId], spellId = spellId,
        expirationTime = secondsLeft and (M.time + secondsLeft) or 0 }
end

LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter", PALADIN = "Paladin",
    SHAMAN = "Shaman", DRUID = "Druid", PRIEST = "Priest", MAGE = "Mage", WARLOCK = "Warlock" }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
function UnitLevel(unit)
    if unit == "NPC" then return M.partnerLevel end
    return 60
end
function UnitClass(unit)
    if unit == "NPC" then return M.partnerClass, M.partnerClass end
    local entry = M.roster[unit or "player"]
    if not entry then return nil end
    return entry.class, entry.class
end
function UnitName(unit)
    if unit == "NPC" then return "Partner" end
    local entry = M.roster[unit]
    return entry and entry.name or nil
end
function GetRealmName() return "TestRealm" end
function UnitFactionGroup() return "Alliance", "Alliance" end
function UnitExists(unit) return M.roster[unit] ~= nil end
function UnitIsConnected(unit) return M.roster[unit] and M.roster[unit].online or false end
function UnitIsDeadOrGhost(unit) return M.roster[unit] and M.roster[unit].dead or false end
function UnitIsVisible(unit) return M.roster[unit] and M.roster[unit].visible or false end
function UnitInRange(unit)
    -- On the real client these returns are secret, so the addon must not rely on them.
    return true, false
end
function GetRaidRosterInfo(index)
    local entry = M.roster["raid" .. index]
    if not entry then return nil end
    return entry.name, 0, entry.subgroup, 60, entry.class, entry.class, "Zone", entry.online, entry.dead
end
function UnitIsPlayer() return false end
function UnitIsFriend() return false end
function UnitIsUnit() return false end
function InitiateTrade() LOG("InitiateTrade called") end
function IsInGroup() return M.group ~= nil end
function IsInRaid() return M.group == "raid" end
function GetNumGroupMembers()
    local count = 0
    for unit in pairs(M.roster) do
        if unit ~= "player" or M.group == "party" then count = count + 1 end
    end
    return M.group and count or 0
end
function IsShiftKeyDown() return M.shift == true end
function IsAltKeyDown() return false end
function IsControlKeyDown() return M.ctrl == true end
function RegisterUnitWatch(frame) frame.__unitWatch = true end
function RegisterStateDriver(frame, kind, value) frame.__stateDriver = value end

C_Secrets = {}
function C_Secrets.ShouldAurasBeSecret() return M.aurasRestricted == true end
function C_Secrets.ShouldSpellAuraBeSecret() return M.aurasRestricted == true end

--- The client's attribute lookup order for a click with modifier `prefix`
--- ("", "shift-", "alt-" ...) and button `suffix` ("1", "2").
function ResolveAttribute(frame, prefix, name, suffix)
    local attrs = frame.__attrs
    local value = attrs[prefix .. name .. suffix]
    if value == nil then value = attrs["*" .. name .. suffix] end
    if value == nil then value = attrs[prefix .. name .. "*"] end
    if value == nil then value = attrs["*" .. name .. "*"] end
    if value == nil then value = attrs[name] end
    return value
end

C_UnitAuras = {}
function C_UnitAuras.GetAuraDataBySpellName(unit, name)
    local entry = M.roster[unit]
    if not entry then return nil end
    if M.combat and M.aurasFailInCombat then error("aura data is restricted") end
    if entry.aura and entry.aura.name == name then return entry.aura end
    return nil
end
function IsInInstance() return M.instance ~= nil, M.instance or "none" end
function GetBindingAction() return "" end
function ClearOverrideBindings() wipe(M.bindings) end
function SetOverrideBindingClick(owner, priority, key, button, click)
    if M.combat then M.violations = M.violations + 1 LOG("PROTECTED VIOLATION: SetOverrideBindingClick in combat") end
    M.bindings[key] = button .. ":" .. click
end
function StaticPopup_Show(which, a, b, data)
    M.popups[#M.popups + 1] = { which = which, a = a, b = b, data = data }
end
function StaticPopup_Hide() end
function AcceptTrade() LOG("FORBIDDEN: AcceptTrade was called") M.violations = M.violations + 1 end

-------------------------------------------------------------------------------
-- Spells
-------------------------------------------------------------------------------
local SPELL_NAMES = {
    [5504] = "Conjure Water", [5505] = "Conjure Water", [5506] = "Conjure Water", [6127] = "Conjure Water",
    [10138] = "Conjure Water", [10139] = "Conjure Water", [10140] = "Conjure Water",
    [587] = "Conjure Food", [597] = "Conjure Food", [990] = "Conjure Food", [6129] = "Conjure Food",
    [10144] = "Conjure Food", [10145] = "Conjure Food", [28612] = "Conjure Food",
    [759] = "Conjure Mana Agate", [3552] = "Conjure Mana Jade", [10053] = "Conjure Mana Citrine", [10054] = "Conjure Mana Ruby",
    [3561] = "Teleport: Stormwind", [3562] = "Teleport: Ironforge", [3565] = "Teleport: Darnassus",
    [3567] = "Teleport: Orgrimmar", [3563] = "Teleport: Undercity", [3566] = "Teleport: Thunder Bluff",
    [10059] = "Portal: Stormwind", [11416] = "Portal: Ironforge", [11419] = "Portal: Darnassus",
    [11417] = "Portal: Orgrimmar", [11418] = "Portal: Undercity", [11420] = "Portal: Thunder Bluff",
    [23028] = "Arcane Brilliance", [1459] = "Arcane Intellect", [1460] = "Arcane Intellect", [1461] = "Arcane Intellect",
    [10156] = "Arcane Intellect", [10157] = "Arcane Intellect", [99999] = "Teleport: Karazhan", [133] = "Fireball",
}

M.book = {}
function SetBook(ids)
    M.book = {}
    local last = {}
    for i, id in ipairs(ids) do
        M.book[i] = { id = id, name = SPELL_NAMES[id] or ("Spell" .. id), low = false }
        local name = M.book[i].name
        if last[name] then M.book[last[name]].low = true end
        last[name] = i
    end
end

C_Spell = {}
function C_Spell.GetSpellName(id) return SPELL_NAMES[id] end
function C_Spell.GetSpellTexture(id) if SPELL_NAMES[id] then return 136000 + id % 100 end return nil end
function C_Spell.IsSpellInRange(id, unit)
    local entry = M.roster[unit]
    if not entry or not SPELL_NAMES[id] then return nil end
    return entry.inRange
end
function C_Spell.GetSpellDescription(id)
    if id == 23028 then return M.brillianceText or "Infuses the target's party with brilliance, increasing their Intellect by 31 for 1 hour." end
    return ""
end

C_SpellBook = {}
function C_SpellBook.GetNumSpellBookSkillLines() return 2 end
function C_SpellBook.GetSpellBookSkillLineInfo(line)
    if line == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 0 } end
    return { name = "Arcane", itemIndexOffset = 0, numSpellBookItems = #M.book }
end
function C_SpellBook.GetSpellBookItemInfo(slot)
    local entry = M.book[slot]
    if not entry then return nil end
    return { itemType = 1, spellID = entry.id, name = entry.name, isPassive = false, actionID = entry.id }
end
function C_SpellBook.IsSpellBookItemLowRank(slot) return M.book[slot] and M.book[slot].low or false end
function C_SpellBook.IsSpellKnown(id)
    for i = 1, #M.book do if M.book[i].id == id then return true end end
    return false
end

-------------------------------------------------------------------------------
-- Bags, cursor, items
-------------------------------------------------------------------------------
local STACK = { [17031] = 10, [17032] = 10, [17020] = 20 }
local function MaxStack(id) return STACK[id] or 20 end

M.bags = {}
function ResetBags()
    for bag = 0, 4 do M.bags[bag] = {} end
    M.cursor = nil
end
ResetBags()

function AddItem(id, count)
    local stack = MaxStack(id)
    while count > 0 do
        local placed = false
        for bag = 0, 4 do
            for slot = 1, 16 do
                local item = M.bags[bag][slot]
                if item and item.id == id and item.count < stack then
                    local n = math.min(stack - item.count, count)
                    item.count = item.count + n
                    count = count - n
                    placed = true
                    break
                end
            end
            if placed then break end
        end
        if not placed then
            for bag = 0, 4 do
                for slot = 1, 16 do
                    if not M.bags[bag][slot] then
                        local n = math.min(stack, count)
                        M.bags[bag][slot] = { id = id, count = n, locked = false }
                        count = count - n
                        placed = true
                        break
                    end
                end
                if placed then break end
            end
        end
        if not placed then return false end
    end
    return true
end

--- Puts an exact stack in the first empty slot (no merging).
function AddStack(id, count)
    for bag = 0, 4 do
        for slot = 1, 16 do
            if not M.bags[bag][slot] then
                M.bags[bag][slot] = { id = id, count = count, locked = false }
                return
            end
        end
    end
end

C_Container = {}
function C_Container.GetContainerNumSlots() return 16 end
function C_Container.GetContainerItemInfo(bag, slot)
    local item = M.bags[bag] and M.bags[bag][slot]
    if not item then return nil end
    return { itemID = item.id, stackCount = item.count, isLocked = item.locked }
end
function C_Container.GetContainerNumFreeSlots(bag)
    local free = 0
    for slot = 1, 16 do if not M.bags[bag][slot] then free = free + 1 end end
    return free, 0
end
function C_Container.PickupContainerItem(bag, slot)
    if M.blockPickup then
        FireEvent("ADDON_ACTION_BLOCKED", "MageButler", "PickupContainerItem")
        return
    end
    local item = M.bags[bag][slot]
    if M.cursor then
        if not item then
            local c = M.cursor
            M.bags[bag][slot] = { id = c.id, count = c.count, locked = false }
            local source = M.bags[c.bag][c.slot]
            if c.split then
                source.count = source.count - c.count
                source.locked = false
            else
                M.bags[c.bag][c.slot] = nil
            end
            M.cursor = nil
        end
        return
    end
    if item and not item.locked then
        item.locked = true
        M.cursor = { id = item.id, count = item.count, bag = bag, slot = slot }
    end
end
function C_Container.SplitContainerItem(bag, slot, amount)
    if M.blockPickup then
        FireEvent("ADDON_ACTION_BLOCKED", "MageButler", "SplitContainerItem")
        return
    end
    local item = M.bags[bag][slot]
    if M.cursor or not item or item.locked or amount >= item.count then return end
    item.locked = true
    M.cursor = { id = item.id, count = amount, bag = bag, slot = slot, split = true }
end
function GetCursorInfo()
    if M.cursor then return "item", M.cursor.id, "link" end
    return nil
end
function ClearCursor()
    if M.cursor then
        M.bags[M.cursor.bag][M.cursor.slot].locked = false
        M.cursor = nil
    end
end

C_Item = {}
function C_Item.GetItemCount(id)
    local total = 0
    for bag = 0, 4 do
        for slot = 1, 16 do
            local item = M.bags[bag][slot]
            if item and item.id == id then total = total + item.count end
        end
    end
    return total
end
local ITEM_MIN_LEVEL = { [8079] = 55, [8078] = 45, [3772] = 25, [8076] = 45, [1487] = 25 }
function C_Item.GetItemInfo(id)
    return "Item" .. id, "link", 1, 1, ITEM_MIN_LEVEL[id] or 1, "Type", "Sub", MaxStack(id)
end
function C_Item.GetItemIconByID(id) return 134400 end
function C_Item.RequestLoadItemDataByID() end

-------------------------------------------------------------------------------
-- Trade
-------------------------------------------------------------------------------
function ClickTradeButton(slot)
    local c = M.cursor
    if not c then return end
    if M.trade[slot] then
        LOG("FORBIDDEN: ClickTradeButton on an occupied slot " .. slot)
        M.violations = M.violations + 1
        return
    end
    if c.split and M.rejectSplit then return end
    M.trade[slot] = { id = c.id, count = c.count }
    M.cursor = nil -- the bag stack stays locked while it is in the trade window
    C_Timer.After(0.1, function() FireEvent("TRADE_PLAYER_ITEM_CHANGED", slot) end)
end
function GetTradePlayerItemInfo(slot)
    local t = M.trade[slot]
    if not t then return nil end
    return "Item" .. t.id, 1, t.count, 1, nil, false, false, t.id
end
function GetTradePlayerItemLink(slot)
    local t = M.trade[slot]
    if not t then return nil end
    return "|cffffffff|Hitem:" .. t.id .. "::::::::60:::::|h[Item]|h|r"
end
function OpenTrade(group)
    SetGroup(group, group == "raid" and 10 or 5)
    M.trade = {}
    FireEvent("TRADE_SHOW")
end
function CloseTradeWindow()
    FireEvent("TRADE_CLOSED")
    M.trade = {}
    for bag = 0, 4 do
        for slot = 1, 16 do
            if M.bags[bag][slot] then M.bags[bag][slot].locked = false end
        end
    end
    M.cursor = nil
end
function TradeTotals()
    local totals = {}
    local slots = 0
    for slot = 1, 6 do
        local t = M.trade[slot]
        if t then
            totals[t.id] = (totals[t.id] or 0) + t.count
            slots = slots + 1
        end
    end
    return totals, slots
end

-------------------------------------------------------------------------------
-- Merchant
-------------------------------------------------------------------------------
function GetMoney() return M.money end
function GetMerchantNumItems() return M.merchant and #M.merchant or 0 end
function GetMerchantItemID(index) return M.merchant and M.merchant[index] and M.merchant[index].id or nil end
function GetMerchantItemMaxStack(index) return MaxStack(M.merchant[index].id) end
C_MerchantFrame = {}
function C_MerchantFrame.GetItemInfo(index)
    local m = M.merchant and M.merchant[index]
    if not m then return nil end
    return { name = "Item" .. m.id, price = m.price, stackCount = 1, numAvailable = m.avail or -1,
             isPurchasable = true, isUsable = true, hasExtendedCost = false }
end
function BuyMerchantItem(index, quantity)
    local m = M.merchant[index]
    quantity = quantity or 1
    if quantity > MaxStack(m.id) then LOG("BAD: BuyMerchantItem quantity above max stack") end
    local cost = m.price * quantity
    if cost > M.money then LOG("BAD: purchase without enough money") return end
    if not AddItem(m.id, quantity) then LOG("BAD: purchase without bag room") return end
    M.money = M.money - cost
    M.bought[m.id] = (M.bought[m.id] or 0) + quantity
end

-- Anything the addon touches that this mock does not define shows up in the log.
setmetatable(_G, {
    __index = function(_, key)
        if key ~= "MageButlerDB" and key ~= "GetSpellInfo" and key ~= "GetItemCount" and key ~= "GetItemInfo"
            and key ~= "GetItemIcon" and key ~= "GetSpellTexture" and key ~= "IsPlayerSpell" and key ~= "IsSpellKnown"
            and key ~= "GetMerchantItemInfo" and key ~= "MageButler" then
            LOG("UNDEFINED GLOBAL: " .. tostring(key))
        end
        return nil
    end,
})
