-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: core initialisation, event dispatch and shared helpers.
-- Target client: WoW Forever (interface 16001) - vanilla rules on the modern engine.

local ADDON_NAME, MB = ...
_G.MageButler = MB

MB.name = ADDON_NAME
MB.version = "1.0.0"
MB.author = "Padre Pidisc"
MB.modules = {}
MB.isMage = false
MB.ready = false
MB.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------
function MB:NewModule(name)
    local module = { name = name }
    self.modules[#self.modules + 1] = module
    self[name] = module
    return module
end

-------------------------------------------------------------------------------
-- Events (one frame, one registration per event) and internal messages
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
local messageHandlers = {}

--- Registers a callback for a game event. Returns false when the client does
--- not know the event, so optional events can be requested safely.
function MB:RegisterEvent(event, fn)
    local list = eventHandlers[event]
    if not list then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            return false
        end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

function MB:On(message, fn)
    local list = messageHandlers[message]
    if not list then
        list = {}
        messageHandlers[message] = list
    end
    list[#list + 1] = fn
end

function MB:Fire(message, ...)
    local list = messageHandlers[message]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

-------------------------------------------------------------------------------
-- Output
-------------------------------------------------------------------------------
local PREFIX = "|cff5ed7ffMage|r|cffb79cffButler|r: "

function MB:Print(text)
    local chat = DEFAULT_CHAT_FRAME
    if chat then
        chat:AddMessage(PREFIX .. tostring(text))
    end
end

--- Discreet on-screen notification; falls back to chat before the theme loads.
--- kind: "ok", "warn" or "info".
function MB:Notify(text, kind)
    if self.Theme and self.Theme.Toast then
        self.Theme:Toast(text, kind)
    end
    if not self.db or self.db.general.chatMessages then
        self:Print(text)
    end
end

function MB.FormatMoney(copper)
    copper = math.max(0, math.floor((copper or 0) + 0.5))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = "|cffffd100" .. gold .. "g|r" end
    if silver > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. "s|r" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. rest .. "c|r" end
    return table.concat(parts, " ")
end

-------------------------------------------------------------------------------
-- Deferred work: combat lockdown and debouncing
-------------------------------------------------------------------------------
local combatQueue, combatOrder = {}, {}

--- Runs fn now, or once combat lockdown ends. A later call with the same key
--- replaces the queued one, so repeated requests collapse into a single run.
function MB:AfterCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    if not combatQueue[key] then
        combatOrder[#combatOrder + 1] = key
    end
    combatQueue[key] = fn
    return false
end

MB:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if #combatOrder == 0 then return end
    local order, queue = combatOrder, combatQueue
    combatOrder, combatQueue = {}, {}
    for i = 1, #order do
        local fn = queue[order[i]]
        if fn then fn() end
    end
end)

local debounced = {}

--- Collapses bursts of calls with the same key into one call after `delay`.
function MB:Debounce(key, delay, fn)
    local waiting = debounced[key] ~= nil
    debounced[key] = fn
    if waiting then return end
    C_Timer.After(delay, function()
        local run = debounced[key]
        debounced[key] = nil
        if run then run() end
    end)
end

-------------------------------------------------------------------------------
-- Client API wrappers
-- The modern engine can hand addons "secret" values; anything read from the
-- game is passed through these guards before it is compared or used in maths.
-------------------------------------------------------------------------------
local API = {}
MB.API = API

local issecretvalue = _G.issecretvalue

function MB.IsSecret(value)
    if issecretvalue then
        return issecretvalue(value) and true or false
    end
    return false
end

local IsSecret = MB.IsSecret

function API.Num(value, fallback)
    if IsSecret(value) then return fallback end
    if type(value) == "number" then return value end
    return fallback
end

function API.Str(value)
    if IsSecret(value) then return nil end
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- Items ----------------------------------------------------------------------
local rawItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local rawItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local rawItemIcon = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon

--- Number of an item carried in the bags (bank and charges excluded).
function API.ItemCount(itemID)
    if not rawItemCount then return 0 end
    return API.Num(rawItemCount(itemID, false, false), 0)
end

function API.ItemName(itemID)
    if not rawItemInfo then return nil end
    return API.Str((rawItemInfo(itemID)))
end

function API.ItemStackSize(itemID)
    if not rawItemInfo then return nil end
    local _, _, _, _, _, _, _, stackSize = rawItemInfo(itemID)
    stackSize = API.Num(stackSize)
    if stackSize and stackSize > 0 then return stackSize end
    return nil
end

function API.ItemIcon(itemID)
    if not rawItemIcon then return nil end
    local icon = rawItemIcon(itemID)
    if IsSecret(icon) then return nil end
    return icon
end

function API.RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Spells ---------------------------------------------------------------------
function API.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return API.Str(C_Spell.GetSpellName(spellID))
    end
    if _G.GetSpellInfo then
        return API.Str((_G.GetSpellInfo(spellID)))
    end
    return nil
end

function API.SpellTexture(spellID)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellID)
    elseif _G.GetSpellTexture then
        icon = _G.GetSpellTexture(spellID)
    end
    if IsSecret(icon) then return nil end
    return icon
end

function API.IsSpellKnown(spellID)
    local known
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        known = C_SpellBook.IsSpellKnown(spellID)
    elseif _G.IsPlayerSpell then
        known = _G.IsPlayerSpell(spellID)
    elseif _G.IsSpellKnown then
        known = _G.IsSpellKnown(spellID)
    end
    if IsSecret(known) then return false end
    return known and true or false
end

-- Bags -----------------------------------------------------------------------
MB.LAST_BAG = _G.NUM_BAG_SLOTS or 4

function API.BagSlots(bag)
    return API.Num(C_Container.GetContainerNumSlots(bag), 0)
end

--- Returns itemID, stackCount, isLocked for a bag slot, or nil when it is empty
--- or cannot be read.
function API.BagItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    local itemID = API.Num(info.itemID)
    if not itemID then return nil end
    local locked = info.isLocked
    if IsSecret(locked) then locked = true end
    return itemID, API.Num(info.stackCount, 1), locked and true or false
end

--- Free slots in a bag, and whether it is a general-purpose bag.
function API.BagFree(bag)
    local free, family = C_Container.GetContainerNumFreeSlots(bag)
    free = API.Num(free, 0)
    family = API.Num(family, 0)
    return free, family == 0
end

-------------------------------------------------------------------------------
-- Inventory snapshot: one refresh per bag-update batch, shared by all modules
-------------------------------------------------------------------------------
function MB:RefreshInventory()
    if not self.ready then return end
    for i = 1, #self.modules do
        local module = self.modules[i]
        if module.RefreshInventory then
            module:RefreshInventory()
        end
    end
    self:Fire("INVENTORY_UPDATED")
end

-------------------------------------------------------------------------------
-- Startup
-------------------------------------------------------------------------------
function MB:IsActive()
    return self.ready and self.db ~= nil and self.db.general.enabled
end

MB:RegisterEvent("PLAYER_LOGIN", function()
    local _, class = UnitClass("player")
    MB.isMage = (class == "MAGE")
    if not MB.isMage then return end

    MB.Config:Init()

    for i = 1, #MB.modules do
        local module = MB.modules[i]
        if module.OnEnable then
            module:OnEnable()
        end
    end
    MB.ready = true

    MB:RegisterEvent("BAG_UPDATE_DELAYED", function()
        MB:RefreshInventory()
    end)

    MB:RefreshInventory()
    MB:Fire("SETTINGS_CHANGED", "all")
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function PrintHelp()
    MB:Print("commands (|cff5ed7ff/mb|r or |cff5ed7ff/magebutler|r):")
    MB:Print("  |cff5ed7ff/mb|r - open or close the settings panel")
    MB:Print("  |cff5ed7ff/mb menu|r - toggle the radial menu")
    MB:Print("  |cff5ed7ff/mb orb|r - hide or restore the orb")
    MB:Print("  |cff5ed7ff/mb hud|r - hide or restore the inventory HUD")
    MB:Print("  |cff5ed7ff/mb ready|r - show the preparation check")
    MB:Print("  |cff5ed7ff/mb buffs|r - open or close the Buff Watch player list")
    MB:Print("  |cff5ed7ff/mb fill|r - fill the open trade window")
    MB:Print("  |cff5ed7ff/mb reset|r - move the orb and HUD back to their default positions")
end

SLASH_MAGEBUTLER1 = "/magebutler"
SLASH_MAGEBUTLER2 = "/mb"

SlashCmdList["MAGEBUTLER"] = function(message)
    if not MB.isMage then
        MB:Print("this character is not a Mage, so MageButler is idle.")
        return
    end
    if not MB.ready then return end

    local command = strlower(strtrim(message or ""))

    if command == "" or command == "config" or command == "settings" or command == "options" then
        MB.Settings:Toggle()
    elseif command == "menu" then
        MB.RadialMenu:Toggle()
    elseif command == "orb" then
        MB.db.general.showOrb = not MB.db.general.showOrb
        MB:Fire("SETTINGS_CHANGED", "general")
        MB:Print(MB.db.general.showOrb and "orb shown." or "orb hidden. Type /mb orb to restore it.")
    elseif command == "hud" then
        MB.db.general.showHUD = not MB.db.general.showHUD
        MB:Fire("SETTINGS_CHANGED", "general")
        MB:Print(MB.db.general.showHUD and "HUD shown." or "HUD hidden.")
    elseif command == "ready" or command == "prep" or command == "check" then
        MB.Readiness:Report(true)
    elseif command == "buffs" or command == "buff" or command == "buffwatch" then
        MB.BuffWatch:ToggleList()
    elseif command == "fill" or command == "trade" then
        MB.Trade:Fill(true)
    elseif command == "reset" then
        MB.Config:ResetPositions()
        MB:Fire("SETTINGS_CHANGED", "all")
        MB:Print("orb and HUD positions reset.")
    else
        PrintHelp()
    end
end
