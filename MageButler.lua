-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: core initialisation, event dispatch and shared helpers.
-- Target client: WoW Forever (interface 16001) - vanilla rules on the modern engine.

local ADDON_NAME, MB = ...
_G.MageButler = MB

MB.name = ADDON_NAME
MB.version = "1.1.1"
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

-- Where several handlers hear the same thing, one of them failing must not
-- silence the ones after it: an error in one module would otherwise leave
-- another module's display out of date with nothing to show for it. Each is
-- called on its own, and an error still reaches the client's error handler.
-- A lone handler has nobody to hold up, so it is simply called.
local securecall = _G.securecallfunction

local function Dispatch(list, ...)
    if #list == 1 or not securecall then
        for i = 1, #list do
            list[i](...)
        end
        return
    end
    for i = 1, #list do
        securecall(list[i], ...)
    end
end

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
    if list then Dispatch(list, event, ...) end
end)

-- Unit events that only matter for the player get a frame of their own, so
-- the client delivers them for the player alone. Registered the ordinary way,
-- an event such as UNIT_SPELLCAST_SUCCEEDED arrives for every player and
-- creature in sight, and for anyone but the player its details can be secret.
local playerFrame = CreateFrame("Frame")
local playerHandlers = {}

--- Registers a callback for a unit event, for the player only.
function MB:RegisterPlayerEvent(event, fn)
    local list = playerHandlers[event]
    if not list then
        if not pcall(playerFrame.RegisterUnitEvent, playerFrame, event, "player") then
            return false
        end
        list = {}
        playerHandlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

playerFrame:SetScript("OnEvent", function(_, event, ...)
    local list = playerHandlers[event]
    if list then Dispatch(list, event, ...) end
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
    if list then Dispatch(list, ...) end
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

-- A short trail of what the inventory gate did and why, read back with
-- /mb debug. It is saved with the settings, so it is still there after the
-- /reload that a counter gone wrong tends to be answered with.
local TRAIL_SIZE = 60
MB.trail = {}

function MB:Log(text)
    local trail = self.trail
    if #trail >= TRAIL_SIZE then
        table.remove(trail, 1)
    end
    trail[#trail + 1] = date("%H:%M:%S") .. "  " .. text
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
    -- Each piece of queued work on its own: one failing must not strand the
    -- rest of what was waiting for combat to end.
    for i = 1, #order do
        local fn = queue[order[i]]
        if fn then
            if securecall then securecall(fn) else fn() end
        end
    end
end)

--- Where a frame sits, as an offset from the centre of the screen in screen
--- units. Positions are stored this way so they survive a change of UI scale.
--- Nil when the frame has no position yet.
function MB.CentreOffset(frame)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return nil end
    local scale = frame:GetScale()
    return cx * scale - ux, cy * scale - uy
end

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

--- Number of an item carried in the bags (bank and charges excluded), or nil
--- when the client will not say. Nil is not zero, and nothing may treat it as
--- zero: only the inventory snapshot below reads this, and it keeps the last
--- count it could believe instead.
function API.ItemCount(itemID)
    if not rawItemCount then return nil end
    return API.Num(rawItemCount(itemID, false, false))
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

--- Character level needed to use an item, or nil while the item is not cached.
function API.ItemMinLevel(itemID)
    if not rawItemInfo then return nil end
    local _, _, _, _, minLevel = rawItemInfo(itemID)
    return API.Num(minLevel)
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

--- The item in a bag slot, or nil when the slot is empty or cannot be read.
function API.BagItemID(bag, slot)
    local byID = C_Container.GetContainerItemID
    if byID then
        return API.Num(byID(bag, slot))
    end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and API.Num(info.itemID) or nil
end

--- An item the bags can be seen to hold right now: the first one any slot
--- gives up, or nil when none does. That is the sign the client can say what
--- is in the bags at all. The number of slots is no guide, because the
--- backpack goes on reporting its sixteen while their contents are unknown.
function API.AnyBagItem()
    for bag = 0, MB.LAST_BAG do
        for slot = 1, API.BagSlots(bag) do
            local itemID = API.BagItemID(bag, slot)
            if itemID then return itemID end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Inventory snapshot: one read per bag-update batch, shared by all modules
--
-- Every count MageButler shows or acts on comes out of `snapshot`, and a
-- number only gets in there from a read made while the bags could be seen to
-- answer. The client has moments when it cannot say what is in the bags - a
-- loading screen above all - and at those moments every count reads zero,
-- which looks exactly like having run out of everything.
--
--   * A loading screen closes the gate: nothing is read until it is over.
--   * The gate opens when an item can actually be read out of a bag slot. The
--     backpack reporting its slots is not enough: it does that while their
--     contents are unknown.
--   * The client's counts are believed only while they agree with the slots:
--     an item seen in a slot must be counted as being there. When the two
--     disagree, the slots are counted directly instead.
--   * A read that finds no item anywhere is not believed straight away. The
--     counts stay as they were while the bags are asked again, and only bags
--     that go on reading empty are taken to be empty.
--   * A read is kept whole or not at all, so there is no half-zero state.
--   * Opening the gate never hangs on one event arriving: the end of a
--     loading screen, entering the world, any bag update, anything else that
--     asks for a refresh and a timer all lead there.
-------------------------------------------------------------------------------
local SETTLE_DELAY = 2.0   -- quiet period after a loading screen
local SETTLE_STEP = 0.5    -- how often the bags are asked after that
local SETTLE_TRIES = 16    -- asks after a loading screen before empty bags are believed
local DOUBT_TRIES = 4      -- the same when nothing explains why they read empty
local LOADING_LIMIT = 90   -- a loading screen older than this is taken to be over
local WITNESSES = 3        -- items asked about before the counts are doubted

MB.inventoryReady = false   -- the bags can be read and believed right now
MB.inventoryKnown = false   -- they have been read at least once this session

local tracked, trackedIndex = {}, {}   -- the item IDs that are counted, and each one's place in the list
local snapshot = {}                 -- [itemID] = count at the last read believed
local fresh = {}                    -- one read, before any of it is kept
local readingBy                     -- "counts" or "slots": how the last read was made
local loading = true                -- a loading screen is up, as it is when this file loads
local loadingSince = GetTime()
local closedAt                      -- when the gate last closed, for the trail
local asking = false                -- a timer is about to ask the bags again
local askToken = 0
local believedEmpty = false         -- the bags read empty for long enough to be believed
local inventoryWaiters = {}

--- Has an item counted from now on. Modules call this as they load.
function MB:TrackItem(itemID)
    if trackedIndex[itemID] then return end
    tracked[#tracked + 1] = itemID
    trackedIndex[itemID] = #tracked
end

--- How many of a tracked item were in the bags at the last read that could be
--- believed. This is the number every module shows and acts on.
function MB:CountOf(itemID)
    return snapshot[itemID] or 0
end

--- Runs fn now if the bag contents can be trusted, otherwise once they can.
function MB:AfterInventory(fn)
    if self.inventoryReady then
        fn()
        return
    end
    inventoryWaiters[#inventoryWaiters + 1] = fn
end

--- How the bags can be read at this moment, if at all.
---   "counts"  a bag slot gives up an item, and the count of that very item
---             agrees it is there: the client's counts can be believed.
---   "slots"   the slots show items that the counts deny or will not give.
---             The slots are the plainer evidence, so the counting is done
---             from them instead.
---   nil       no slot gives up anything: the client cannot say what is in
---             the bags, or there is nothing in them.
--- A few items are asked about before the counts are doubted, so one item the
--- client miscounts cannot send everything the slow way round.
local function Probe()
    local denied = 0
    for bag = 0, MB.LAST_BAG do
        for slot = 1, API.BagSlots(bag) do
            local itemID = API.BagItemID(bag, slot)
            if itemID then
                believedEmpty = false
                local count = API.ItemCount(itemID)
                if count and count >= 1 then return "counts" end
                denied = denied + 1
                if denied >= WITNESSES then return "slots" end
            end
        end
    end
    if denied > 0 then return "slots" end
    return believedEmpty and "counts" or nil
end

--- Reads every tracked count and keeps the lot or none of it. Returns true
--- and whether any count changed, or false when the bags gave nothing to go
--- on and the counts were left as they were. `expected` is false for a read
--- that nothing in the bags prompted: if one of those finds different
--- numbers, an update went missing, and the trail says so.
local function ReadSnapshot(source, expected)
    local how = Probe()
    if not how then return false end

    if how == "counts" then
        for i = 1, #tracked do
            local count = API.ItemCount(tracked[i])
            if not count then
                how = "slots"   -- one will not be given: count them all here instead
                break
            end
            fresh[i] = count
        end
    end
    if how == "slots" then
        for i = 1, #tracked do
            fresh[i] = 0
        end
        for bag = 0, MB.LAST_BAG do
            for slot = 1, API.BagSlots(bag) do
                local itemID, count = API.BagItem(bag, slot)
                local index = itemID and trackedIndex[itemID]
                if index then
                    fresh[index] = fresh[index] + count
                end
            end
        end
    end
    if how ~= readingBy then
        if how == "slots" then
            MB:Log("the client's counts disagree with the bags: counting slot by slot (" .. source .. ")")
        elseif readingBy == "slots" then
            MB:Log("the client's counts agree with the bags again")
        end
        readingBy = how
    end

    local changed, gone, missed = false, nil, nil
    for i = 1, #tracked do
        local itemID = tracked[i]
        local before, now = snapshot[itemID], fresh[i]
        if before ~= now then
            changed = true
            snapshot[itemID] = now
            if before then
                if now == 0 then
                    gone = (gone and (gone .. ", ") or "") .. itemID .. " x" .. before
                end
                if not expected then
                    missed = (missed and (missed .. ", ") or "") .. itemID .. " " .. before .. ">" .. now
                end
            end
        end
    end
    MB.inventoryKnown = true
    if gone then
        MB:Log("now zero: " .. gone .. " (" .. source .. (InCombatLockdown() and ", in combat" or "") .. ")")
    end
    if missed then
        MB:Log("counts were out of date: " .. missed .. " (" .. source .. ")")
    end
    return true, changed
end

local function Announce(redraw)
    for i = 1, #MB.modules do
        local module = MB.modules[i]
        if module.RefreshInventory then
            module:RefreshInventory()
        end
    end
    if redraw then
        MB:Fire("INVENTORY_UPDATED")
    end
end

--- Stops reading the bags. The counts stay exactly as they are.
local function Close(why)
    askToken = askToken + 1   -- whoever was about to ask need not
    asking = false
    if MB.inventoryReady then
        MB.inventoryReady = false
        closedAt = GetTime()
        MB:Log("counts held (" .. why .. ")")
    end
end

--- The bags answer: read them, and let everything that was waiting go ahead.
local function Open(why)
    askToken = askToken + 1
    asking = false
    MB.inventoryReady = true
    local held = closedAt and string.format(" after %.1fs", GetTime() - closedAt) or ""
    closedAt = nil
    MB:Log("counting again" .. held .. " (" .. why .. ")")

    -- Announced whether or not a count changed: this is the first word since
    -- the gate closed, and a good deal else may have been waiting on it.
    if not MB:RefreshInventory(true, why) then return end

    local waiters = inventoryWaiters
    inventoryWaiters = {}
    for i = 1, #waiters do
        waiters[i]()
    end
end

--- Asks the bags again shortly, and goes on asking until they answer. After a
--- loading screen they get a quiet moment first and plenty of patience; bags
--- that read empty for no known reason are asked sooner and believed sooner.
local function Ask(tries, patience, quiet)
    askToken = askToken + 1
    asking = true
    local token = askToken
    C_Timer.After((quiet and tries == 0) and SETTLE_DELAY or SETTLE_STEP, function()
        if token ~= askToken then return end
        asking = false
        if Probe() then
            Open("the bags answered")
        elseif tries < patience then
            Ask(tries + 1, patience, quiet)
        else
            -- Bags that go on reading empty are empty.
            believedEmpty = true
            Open("the bags stayed empty")
        end
    end)
end

--- Reads the bags and tells the modules. The display is redrawn only when a
--- count changed, or always with `force`. `source` names what asked, for the
--- trail. Returns false when the counts could not be read and were left as
--- they were.
function MB:RefreshInventory(force, source)
    if not self.ready then return false end
    source = source or "refresh"

    if not self.inventoryReady then
        -- Held. Whatever asks is a chance to notice that the bags are back,
        -- except while a loading screen is known to be up.
        if loading then
            if GetTime() - loadingSince < LOADING_LIMIT then return false end
            loading = false
            self:Log("a loading screen never reported ending: taken as over")
        end
        if Probe() then
            Open(source)
            return self.inventoryReady
        end
        if not asking then
            Ask(0, DOUBT_TRIES, false)
        end
        return false
    end

    local read, changed = ReadSnapshot(source, force or source == "bag update")
    if not read then
        -- Nothing explains bags that have stopped answering, so they are
        -- simply asked again, and the counts stay as they were meanwhile.
        Close("the bags read empty")
        Ask(0, DOUBT_TRIES, false)
        return false
    end
    Announce(changed or force)
    return true
end

local function LoadingStarted(event)
    if not MB.isMage then return end
    loading, loadingSince = true, GetTime()
    believedEmpty = false
    Close(event)
end

--- The world is back. PLAYER_ENTERING_WORLD says so for a change of map and
--- LOADING_SCREEN_DISABLED for every loading screen, including one that stays
--- on the same map and never fires the first. Either is enough.
local function LoadingEnded(event)
    if not MB.isMage then return end
    loading = false
    believedEmpty = false
    if MB.inventoryReady and event == "LOADING_SCREEN_DISABLED" then
        -- A bag update got there first. One more look, now the screen is gone.
        MB:RefreshInventory(false, "loading screen over")
        return
    end
    Close(event)
    Ask(0, SETTLE_TRIES, true)
end

MB:RegisterEvent("PLAYER_LEAVING_WORLD", LoadingStarted)
MB:RegisterEvent("LOADING_SCREEN_ENABLED", LoadingStarted)
MB:RegisterEvent("PLAYER_ENTERING_WORLD", LoadingEnded)
MB:RegisterEvent("LOADING_SCREEN_DISABLED", LoadingEnded)

local function PrintTrail(title, lines, limit)
    if type(lines) ~= "table" or #lines == 0 then return end
    MB:Print(title .. ":")
    for i = math.max(1, #lines - limit + 1), #lines do
        MB:Print("  " .. tostring(lines[i]))
    end
end

--- /mb debug: what the gate is doing, each count set against what the client
--- says this instant, and the trail of how things got here.
function MB:PrintDiagnostics()
    local state = self.inventoryReady and "counting" or "holding the last counts"
    if loading then state = state .. ", loading screen up" end
    if asking then state = state .. ", asking the bags" end
    if believedEmpty then state = state .. ", bags taken to be empty" end
    if readingBy == "slots" then state = state .. ", counted slot by slot" end
    local witness = API.AnyBagItem()
    self:Print("inventory: " .. state .. ". Backpack slots: " .. API.BagSlots(0) .. ". First item found: "
        .. (witness and (witness .. ", counted as " .. tostring(API.ItemCount(witness))) or "none") .. ".")

    local shown = 0
    for i = 1, #tracked do
        local itemID = tracked[i]
        local kept, live = snapshot[itemID] or 0, API.ItemCount(itemID)
        if kept > 0 or (live or 0) > 0 then
            shown = shown + 1
            local text = "  " .. (API.ItemName(itemID) or ("item " .. itemID)) .. ": " .. kept
            if not live then
                text = text .. "  |cffffbf40(the client will not give a count)|r"
            elseif live ~= kept then
                text = text .. "  |cffff5959(the client says " .. live .. ")|r"
            end
            self:Print(text)
        end
    end
    if shown == 0 then
        self:Print("  nothing that is counted is in the bags.")
    end

    local saved = self.Config.root and self.Config.root.trail
    PrintTrail("before the last reload", saved and saved.last, 10)
    PrintTrail("this session", self.trail, 15)
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

    -- The trail of this session is saved, and the one before it is kept
    -- beside it, so /mb debug can still show what led up to a /reload.
    local root = MB.Config.root
    local saved = root.trail
    root.trail = {
        last = type(saved) == "table" and type(saved.now) == "table" and saved.now or nil,
        now = MB.trail,
    }

    MB:RegisterEvent("BAG_UPDATE_DELAYED", function()
        MB:RefreshInventory(false, "bag update")
    end)
    -- A new zone reached without a loading screen: a cheap moment to make
    -- sure nothing went missing on the way.
    MB:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        MB:RefreshInventory(false, "zone")
    end)

    MB:Fire("SETTINGS_CHANGED", "all")
    MB.Settings:MaybeWelcome()
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function PrintHelp()
    MB:Print("commands (|cff5ed7ff/mb|r or |cff5ed7ff/magebutler|r):")
    MB:Print("  |cff5ed7ff/mb|r - open or close the settings panel")
    MB:Print("  |cff5ed7ff/mb menu|r - toggle the radial menu")
    MB:Print("  |cff5ed7ff/mb orb|r - hide or restore the orb")
    MB:Print("  |cff5ed7ff/mb ready|r - show the preparation check")
    MB:Print("  |cff5ed7ff/mb buffs|r - open or close the Buff Watch player list")
    MB:Print("  |cff5ed7ff/mb fill|r - fill the open trade window")
    MB:Print("  |cff5ed7ff/mb welcome|r - show the introduction again")
    MB:Print("  |cff5ed7ff/mb debug|r - show what MageButler counts in your bags, and why")
    MB:Print("  |cff5ed7ff/mb reset|r - move the orb and panels back to their default positions")
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
    elseif command == "ready" or command == "prep" or command == "check" then
        MB.Readiness:Report(true)
    elseif command == "welcome" then
        MB.Settings:ShowWelcome()
    elseif command == "debug" then
        -- Printed first, so a count that has gone wrong is seen as it stood;
        -- then the bags are read again, which the trail will show next time.
        MB:PrintDiagnostics()
        MB:RefreshInventory(false, "debug")
    elseif command == "buffs" or command == "buff" or command == "buffwatch" then
        MB.BuffWatch:ToggleList()
    elseif command == "fill" or command == "trade" then
        MB.Trade:Fill(true)
    elseif command == "reset" then
        MB.Config:ResetPositions()
        MB:Fire("SETTINGS_CHANGED", "all")
        MB:Print("positions reset.")
    else
        PrintHelp()
    end
end
