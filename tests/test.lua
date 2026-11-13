-- Smoke test scenario for MageButler against the mock API.
local js = require "js"
local window = js.global

local passed, failed = 0, 0

local function check(label, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        LOG("FAIL: " .. label .. (detail and (" -> " .. tostring(detail)) or ""))
    end
end

local function eq(label, actual, expected)
    check(label, actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function phase(name, fn)
    local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
    if not ok then
        failed = failed + 1
        LOG("ERROR in phase '" .. name .. "': " .. tostring(err))
    else
        LOG("phase ok: " .. name)
    end
end

local MB = {}

-- Load the addon files in TOC order, the way the client does.
phase("load files", function()
    local files = window.FILES
    for i = 0, files.length - 1 do
        local name = files[i]
        local chunk, err = load(window.SOURCES[name], "@" .. name)
        if not chunk then error(err) end
        chunk("MageButler", MB)
    end
end)

-- A level 60 Alliance Mage with most utility spells.
SetBook({
    133,
    5504, 5505, 5506, 6127, 10138, 10139, 10140,
    587, 597, 990, 6129, 10144, 10145,
    759, 3552, 10053, 10054,
    3561, 3562, 3565, 99999,
    10059, 11416,
    1459, 1460, 1461, 10156, 10157, 23028,
})
SetAura("player", 10157) -- already buffed, no known expiry
AddStack(8079, 20) AddStack(8079, 20) AddStack(8079, 7)   -- water: 47
AddStack(8076, 20) AddStack(8076, 5)                      -- food: 25
AddStack(8008, 1)                                         -- mana ruby
AddStack(17031, 3)                                        -- rune of teleportation
AddStack(17020, 4)                                        -- arcane powder
AddStack(6948, 1)                                         -- hearthstone: must never be traded

phase("login", function()
    FireEvent("PLAYER_LOGIN")
    FireEvent("PLAYER_ENTERING_WORLD")
    FireEvent("SPELLS_CHANGED")
    RunTimers()
    check("ready", MB.ready)
    check("orb exists", MageButlerOrb ~= nil)
    check("orb shown", MageButlerOrb and MageButlerOrb:IsShown())
    check("menu hidden at login", MageButlerMenu and not MageButlerMenu:IsShown())
    check("profile created", MageButlerDB and MageButlerDB.chars["Tester - TestRealm"] ~= nil)
end)

phase("spells", function()
    local teleports, portals = MB.Spells:GetTeleports(), MB.Spells:GetPortals()
    eq("teleport count", #teleports, 4)
    eq("portal count", #portals, 2)
    eq("first teleport", teleports[1] and teleports[1].short, "Stormwind")
    eq("discovered teleport", teleports[4] and teleports[4].short, "Karazhan")
    for i = 1, #teleports do
        check("no horde teleport", teleports[i].id ~= 3567 and teleports[i].id ~= 3563 and teleports[i].id ~= 3566)
    end
    eq("best water", MB.Spells:GetBest("water"), 10140)
    eq("best food", MB.Spells:GetBest("food"), 10145)
    eq("ritual unknown", MB.Spells:GetBest("ritual"), nil)
    eq("uses powder", MB.Spells:UsesReagent("powder"), true)
end)

phase("secure attributes", function()
    eq("water type", MageButlerButton_water:GetAttribute("*type1"), "spell")
    eq("water spell", MageButlerButton_water:GetAttribute("*spell1"), 10140)
    eq("water useOnKeyDown", MageButlerButton_water:GetAttribute("useOnKeyDown"), false)
    eq("food spell", MageButlerButton_food:GetAttribute("*spell1"), 10145)
    eq("food ritual", MageButlerButton_food:GetAttribute("*type2"), nil)
    eq("gem cast = strongest not held", MageButlerButton_gem:GetAttribute("*spell1"), 10053)
    eq("gem use", MageButlerButton_gem:GetAttribute("*item2"), "item:8008")
    eq("portal row 1", MageButlerSub_portalsRow1:GetAttribute("spell"), 10059)
    eq("portal row 2", MageButlerSub_portalsRow2:GetAttribute("spell"), 11416)
    eq("teleport row 4", MageButlerSub_teleportsRow4:GetAttribute("spell"), 99999)
    eq("portal row type", MageButlerSub_portalsRow1:GetAttribute("type"), "spell")
    check("portal sub has frame ref", MageButlerButton_portals:GetAttribute("frameref-mine") == MageButlerSub_portals)
    check("orb click snippet set", MageButlerOrb.__wrap and type(MageButlerOrb.__wrap.OnClick) == "string")
    check("orb knows the menu", MageButlerOrb:GetAttribute("frameref-menu") == MageButlerMenu)
end)

phase("inventory and readiness", function()
    eq("water count", MB.Conjuring:Count("water"), 47)
    eq("food count", MB.Conjuring:Count("food"), 25)
    eq("water state", MB.Conjuring:State("water"), "ok")
    eq("runeT state", MB.Reagents:State("runeT"), "ok")
    eq("runeP state", MB.Reagents:State("runeP"), "none")
    eq("powder state", MB.Reagents:State("powder"), "low")
    eq("readiness overall", MB.Readiness:GetOverall(), "none")
    check("HUD shown", MageButlerHUD:IsShown())
end)

phase("reagent restock", function()
    M.merchant = {
        { id = 2512, price = 10 },
        { id = 17031, price = 1000 },
        { id = 17032, price = 2000 },
        { id = 17020, price = 500 },
    }
    local before = M.money
    FireEvent("MERCHANT_SHOW")
    RunTimers()
    eq("runeT bought", M.bought[17031], 7)
    eq("runeP bought", M.bought[17032], 10)
    eq("powder bought", M.bought[17020], 16)
    eq("nothing else bought", M.bought[2512], nil)
    eq("money spent", before - M.money, 7 * 1000 + 10 * 2000 + 16 * 500)
    FireEvent("BAG_UPDATE_DELAYED")
    eq("runeP state after", MB.Reagents:State("runeP"), "ok")
    eq("readiness after restock", MB.Readiness:GetOverall(), "ok")

    -- A second look at the same vendor must not buy past the targets.
    FireEvent("MERCHANT_UPDATE")
    RunTimers()
    eq("no repeat purchase", M.bought[17031], 7)
    FireEvent("MERCHANT_CLOSED")

    -- Spending limit and confirmation.
    ResetBags()
    AddStack(8079, 20) AddStack(8079, 20) AddStack(8079, 7)
    AddStack(8076, 20) AddStack(8076, 5)
    AddStack(8008, 1)
    AddStack(6948, 1)
    M.bought = {}
    MB.db.reagents.items.runeP.maxSpend = 1      -- 1g = 5 runes at 20s each
    MB.db.reagents.items.powder.confirm = true
    FireEvent("BAG_UPDATE_DELAYED")
    FireEvent("MERCHANT_SHOW")
    RunTimers()
    eq("limited runeP", M.bought[17032], 5)
    eq("runeT full", M.bought[17031], 10)
    eq("powder waits for confirm", M.bought[17020], nil)
    eq("popup shown", #M.popups, 1)
    local popup = M.popups[1]
    StaticPopupDialogs[popup.which].OnAccept(nil, popup.data)
    RunTimers()
    eq("powder after confirm", M.bought[17020], 20)
    FireEvent("MERCHANT_CLOSED")
    MB.db.reagents.items.runeP.maxSpend = 5
    MB.db.reagents.items.powder.confirm = false
    FireEvent("BAG_UPDATE_DELAYED")
end)

phase("trade: party preset, whole stacks", function()
    OpenTrade("party")
    RunTimers()
    local totals, slots = TradeTotals()
    eq("water offered", totals[8079], 40)
    eq("food offered", totals[8076], 20)
    eq("slots used", slots, 3)
    eq("hearthstone not offered", totals[6948], nil)
    check("cursor empty", M.cursor == nil)

    -- Contents changing later must not trigger another pass.
    FireEvent("TRADE_PLAYER_ITEM_CHANGED", 1)
    RunTimers()
    local _, slotsAfter = TradeTotals()
    eq("no refill on change", slotsAfter, 3)
    CloseTradeWindow()
end)

phase("trade: speed", function()
    -- Three stacks must be in the window well inside a quarter of a second,
    -- without waiting on the trade window's own update events.
    local started = M.time
    OpenTrade("party")
    RunFor(0.25)
    local totals, slots = TradeTotals()
    eq("fast: water in", totals[8079], 40)
    eq("fast: food in", totals[8076], 20)
    eq("fast: slots", slots, 3)
    check("fast: within 0.25s", M.time - started <= 0.2501)
    RunTimers()
    CloseTradeWindow()
end)

phase("trade: class aware", function()
    M.partnerClass = "WARRIOR"
    OpenTrade("party")
    RunTimers()
    local totals, slots = TradeTotals()
    eq("warrior gets no water", totals[8079], nil)
    eq("warrior gets food", totals[8076], 20)
    eq("warrior: one slot", slots, 1)
    check("preset text mentions food only", MB.Trade:DescribePreset():find("food only", 1, true) ~= nil)
    CloseTradeWindow()

    M.partnerClass = "ROGUE"
    OpenTrade("party")
    RunTimers()
    eq("rogue gets no water", (TradeTotals())[8079], nil)
    CloseTradeWindow()

    M.partnerClass = "PRIEST"
    OpenTrade("party")
    RunTimers()
    eq("priest gets water", (TradeTotals())[8079], 40)
    CloseTradeWindow()

    M.partnerClass = "WARRIOR"
    MB.db.trade.classAware = false
    OpenTrade("party")
    RunTimers()
    eq("class awareness off: water for all", (TradeTotals())[8079], 40)
    CloseTradeWindow()
    MB.db.trade.classAware = true
    M.partnerClass = nil
end)

phase("trade: partial stacks", function()
    MB.db.trade.presets.other.water = 10
    MB.db.trade.presets.other.food = 3
    OpenTrade(nil)
    RunTimers()
    local totals, slots = TradeTotals()
    eq("partial water", totals[8079], 10)
    eq("partial food", totals[8076], 3)
    eq("partial slots", slots, 2)
    CloseTradeWindow()
end)

phase("trade: client refuses split stacks in trade slots", function()
    M.rejectSplit = true
    OpenTrade(nil)
    RunTimers()
    local totals = TradeTotals()
    eq("split via bag water", totals[8079], 10)
    eq("split via bag food", totals[8076], 3)
    check("cursor empty after fallback", M.cursor == nil)
    CloseTradeWindow()
    M.rejectSplit = false
    eq("water still all there", MB.API.ItemCount(8079), 47)
end)

phase("trade: pre-filled slot is not overwritten", function()
    SetGroup("raid", 10)
    M.trade = { [1] = { id = 6948, count = 1 } }
    FireEvent("TRADE_SHOW")
    RunTimers()
    eq("slot 1 untouched", M.trade[1].id, 6948)
    local totals = TradeTotals()
    eq("raid water", totals[8079], 20)
    eq("raid food", totals[8076], nil)
    CloseTradeWindow()
end)

phase("trade: not enough stock", function()
    MB.db.trade.presets.party.water = 100
    OpenTrade("party")
    RunTimers()
    local totals = TradeTotals()
    eq("offers what exists", totals[8079], 47)
    eq("still offers food", totals[8076], 20)
    CloseTradeWindow()
    MB.db.trade.presets.party.water = 40
end)

phase("trade: manual fill and blocked automation", function()
    MB.db.trade.enabled = false
    OpenTrade("party")
    RunTimers()
    local _, slots = TradeTotals()
    eq("disabled: nothing offered", slots, 0)
    MB.Trade:Fill(true)
    RunTimers()
    local totals = TradeTotals()
    eq("manual fill water", totals[8079], 40)
    MB.Trade:Fill(true)
    RunTimers()
    local totalsAgain = TradeTotals()
    eq("manual fill is idempotent", totalsAgain[8079], 40)
    CloseTradeWindow()

    MB.db.trade.enabled = true
    M.blockPickup = true
    OpenTrade("party")
    RunTimers()
    check("auto marked blocked", MB.Trade:IsAutoBlocked())
    CloseTradeWindow()
    OpenTrade("party")
    RunTimers()
    M.blockPickup = false
    local _, blockedSlots = TradeTotals()
    eq("blocked: no retry storm", blockedSlots, 0)
    CloseTradeWindow()
    MB.Trade:RetryAutomatic()
    check("retry clears block", not MB.Trade:IsAutoBlocked())
end)

local function RemoveItem(id)
    for bag = 0, 4 do
        for slot = 1, 16 do
            local item = M.bags[bag][slot]
            if item and item.id == id then M.bags[bag][slot] = nil end
        end
    end
end

local function Orb(attribute)
    return MageButlerOrb:GetAttribute(attribute)
end

phase("buff watch: solo", function()
    SetGroup(nil)
    FireEvent("GROUP_ROSTER_UPDATE")
    RunFor(1)
    local watch = MB.BuffWatch
    eq("solo starts buffed", watch:GetOverall(), "ok")
    eq("no action when buffed", Orb("type2"), nil)

    SetAura("player", nil)
    FireEvent("UNIT_AURA", "player")
    RunFor(1)
    eq("solo missing", watch:GetOverall(), "none")
    eq("orb buff type", Orb("type2"), "spell")
    eq("orb buff spell = top rank", Orb("spell2"), 10157)
    eq("orb buff unit", Orb("unit2"), "player")
    eq("orb acts on release", Orb("useOnKeyDown"), false)
    check("orb click wrapper installed", MageButlerOrb.__wrap and type(MageButlerOrb.__wrap.OnClick) == "string")

    RunScript(MageButlerOrb, "PreClick", "RightButton", true)
    RunScript(MageButlerOrb, "PostClick", "RightButton", false)

    SetAura("player", 10157, 3600)
    FireEvent("UNIT_AURA", "player")
    FireEvent("UNIT_AURA", "nameplate3") -- not a watched unit
    RunFor(1)
    eq("solo buffed", watch:GetOverall(), "ok")
    eq("action cleared once buffed", Orb("type2"), nil)

    -- Nothing happens until the buff nears its end; then one timer fires.
    RunFor(3200)
    eq("still fine at 6 minutes left", watch:GetOverall(), "ok")
    RunFor(120)
    eq("expiring inside the rebuff window", watch:GetOverall(), "low")
    eq("rebuff offered", Orb("unit2"), "player")

    MB.db.buffwatch.watchExpiry = false
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("expiry watching off", watch:GetOverall(), "ok")
    MB.db.buffwatch.watchExpiry = true

    MB.db.buffwatch.solo = false
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("solo monitoring off", watch:GetOverall(), "off")
    eq("no cast when not monitoring", Orb("type2"), nil)
    MB.db.buffwatch.solo = true
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
end)

phase("buff watch: party", function()
    local watch = MB.BuffWatch
    local state = watch:GetState()
    AddStack(17020, 20)
    FireEvent("BAG_UPDATE_DELAYED")
    SetGroup("party", 5)
    SetAura("player", 10157, 3600)
    FireEvent("GROUP_ROSTER_UPDATE")
    RunFor(1)
    eq("party total", state.total, 5)
    eq("party missing", state.missing, 4)
    eq("party: brilliance at threshold", state.action and state.action.kind, "brilliance")
    eq("brilliance spell", Orb("spell2"), 23028)
    eq("brilliance cast on self", Orb("unit2"), "player")

    SetAura("party1", 23028, 3600)
    SetAura("party2", 23028, 3600)
    M.roster.party3.inRange = false
    FireEvent("UNIT_AURA", "party1")
    RunFor(1)
    eq("below threshold: single buff", state.action and state.action.kind, "intellect")
    eq("skips the player out of range", state.action and state.action.unit, "party4")
    eq("single buff spell", Orb("spell2"), 10157)
    eq("out of range counted", state.outOfRange, 1)
    eq("coverage", table.concat({ watch:GetCoverage() }, "/"), "3/5")

    M.roster.party4.inRange = false
    FireEvent("UNIT_AURA", "party4")
    RunFor(1)
    eq("nobody reachable: no action", state.action, nil)
    check("nobody reachable: explained", state.note ~= nil)
    eq("nobody reachable: no cast", Orb("type2"), nil)
    M.roster.party3.inRange = true
    M.roster.party4.inRange = true

    -- Threshold reached but no Arcane Powder.
    SetAura("party1", nil)
    RemoveItem(17020)
    FireEvent("BAG_UPDATE_DELAYED")
    RunFor(1)
    eq("no powder: falls back", state.action and state.action.kind, "intellect")
    check("no powder: says so", state.note ~= nil)
    MB.db.buffwatch.fallbackIntellect = false
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("no powder, no fallback: nothing", state.action, nil)
    MB.db.buffwatch.fallbackIntellect = true
    AddStack(17020, 20)
    FireEvent("BAG_UPDATE_DELAYED")
    RunFor(1)
    eq("powder back: brilliance", state.action and state.action.kind, "brilliance")

    -- Filters.
    M.roster.party1.online = false
    M.roster.party2.dead = true
    FireEvent("UNIT_CONNECTION", "party1")
    RunFor(1)
    eq("offline and dead not counted", state.total, 3)
    M.roster.party3.class = "WARRIOR"
    MB.db.buffwatch.manaUsersOnly = true
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("mana users only", state.total, 2)
    MB.db.buffwatch.manaUsersOnly = false
    MB.db.buffwatch.ignoreOffline = false
    MB.db.buffwatch.ignoreDead = false
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("filters off: all counted", state.total, 5)
    MB.db.buffwatch.ignoreOffline = true
    MB.db.buffwatch.ignoreDead = true
end)

phase("buff watch: raid of 40", function()
    local watch = MB.BuffWatch
    local state = watch:GetState()
    local db = MB.db.buffwatch
    SetGroup("raid", 40)
    for i = 1, 40 do SetAura("raid" .. i, 10157, 3600) end
    for _, i in ipairs({ 6, 7, 8, 9, 21 }) do SetAura("raid" .. i, nil) end
    FireEvent("GROUP_ROSTER_UPDATE")
    RunFor(1)
    eq("raid total", state.total, 40)
    eq("raid missing", state.missing, 5)
    eq("raid coverage", table.concat({ watch:GetCoverage() }, "/"), "35/40")
    eq("raid overall", watch:GetOverall(), "none")

    -- The mock spell text says "target's party": group-scoped Brilliance.
    eq("scope read from the spell text", watch:GetScope(), "group")
    eq("group scope: brilliance on the neediest group", state.action and state.action.kind, "brilliance")
    eq("group scope: benefit", state.action and state.action.benefit, 4)
    local target = state.action and state.action.unit
    check("group scope: target is in that group", target == "raid6" or target == "raid7" or target == "raid8" or target == "raid9", target)

    -- A client whose Brilliance reaches the whole raid.
    M.brillianceText = "Infuses all party and raid members with brilliance."
    MB:Fire("SPELLS_UPDATED")
    RunFor(1)
    eq("scope follows the spell text", watch:GetScope(), "raid")
    eq("raid scope under threshold: single", state.action and state.action.kind, "intellect")
    eq("raid scope: first missing player", state.action and state.action.unit, "raid6")
    SetAura("raid22", nil)
    FireEvent("UNIT_AURA", "raid22")
    RunFor(1)
    eq("raid scope at threshold: brilliance", state.action and state.action.kind, "brilliance")
    eq("raid scope: benefit is raid-wide", state.action and state.action.benefit, 6)
    eq("raid scope: cast on self", Orb("unit2"), "player")

    db.scope = "group"
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("explicit scope wins", watch:GetScope(), "group")
    eq("explicit group scope: benefit", state.action and state.action.benefit, 4)
    db.scope = "auto"

    -- Weaker ranks.
    SetAura("raid30", 1459, 3600)
    db.acceptLowerRanks = false
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("weaker rank flagged", state.missing, 7)
    db.acceptLowerRanks = true
    MB:Fire("SETTINGS_CHANGED", "buffwatch")
    eq("weaker rank accepted", state.missing, 6)

    -- Missing players before expiring ones.
    for i = 1, 40 do SetAura("raid" .. i, 10157, 3600) end
    SetAura("raid10", 10157, 120)
    SetAura("raid12", nil)
    FireEvent("UNIT_AURA", "raid10")
    RunFor(1)
    eq("expiring counted", state.expiring, 1)
    eq("missing first", state.action and state.action.unit, "raid12")
    SetAura("raid12", 10157, 3600)
    FireEvent("UNIT_AURA", "raid12")
    RunFor(1)
    eq("then the expiring player", state.action and state.action.unit, "raid10")
    eq("yellow when only expiring", watch:GetOverall(), "low")

    -- Player list: fixed secure unit buttons.
    eq("list unit", MageButlerBuffUnit_raid5:GetAttribute("unit"), "raid5")
    eq("list left click", MageButlerBuffUnit_raid5:GetAttribute("*spell1"), 10157)
    eq("list right click", MageButlerBuffUnit_raid5:GetAttribute("*spell2"), 23028)
    check("list watches its unit", MageButlerBuffUnit_raid5.__unitWatch)
    check("orb knows the list", Orb("frameref-bufflist") == MageButlerBuffList)
    watch:ToggleList()
    check("list opens", MageButlerBuffList:IsShown())
    RunScript(MageButlerBuffUnit_raid10, "OnEnter")
    RunScript(MageButlerBuffUnit_raid5, "OnEnter")
    watch:ToggleList()
    check("list closes", not MageButlerBuffList:IsShown())

    -- Combat: the buff click is switched off first, nothing is touched during, restored after.
    FireEvent("PLAYER_REGEN_DISABLED")
    M.combat = true
    M.aurasFailInCombat = true
    eq("combat: orb buff click off", Orb("type2"), nil)
    RunScript(MageButlerOrb, "PreClick", "RightButton", true)
    RunScript(MageButlerOrb, "PostClick", "RightButton", false)
    SetAura("raid15", nil)
    FireEvent("UNIT_AURA", "raid15")
    FireEvent("GROUP_ROSTER_UPDATE")
    RunFor(1)
    watch:ToggleList()
    RunScript(MageButlerOrb, "OnEnter")
    M.combat = false
    FireEvent("PLAYER_REGEN_ENABLED")
    RunFor(1)
    eq("after combat: picture refreshed", state.missing, 1)
    eq("after combat: buff click back", Orb("type2"), "spell")
    eq("after combat: target", Orb("unit2"), "raid15")
    eq("protected violations so far", M.violations, 0)

    -- Shift and Ctrl right-clicks never prepare a cast.
    M.shift = true
    RunScript(MageButlerOrb, "PreClick", "RightButton", true)
    RunScript(MageButlerOrb, "PostClick", "RightButton", false)
    check("shift+right opens settings", MageButlerSettings ~= nil and MageButlerSettings:IsShown())
    RunScript(MageButlerOrb, "PostClick", "RightButton", false)
    M.shift = false

    eq("readiness lists intellect", MB.Readiness:GetOverall(), "none")
    SetGroup(nil)
    SetAura("player", 10157)
    FireEvent("GROUP_ROSTER_UPDATE")
    RunFor(1)
    eq("back to solo", watch:GetOverall(), "ok")
end)

phase("modifier keys and restricted areas", function()
    local watch = MB.BuffWatch

    -- A keybind that includes a modifier must still find the conjure spell.
    eq("alt-bound conjure type", ResolveAttribute(MageButlerButton_water, "alt-", "type", "1"), "spell")
    eq("alt-bound conjure spell", ResolveAttribute(MageButlerButton_water, "alt-", "spell", "1"), 10140)
    eq("unmodified conjure", ResolveAttribute(MageButlerButton_water, "", "spell", "1"), 10140)
    eq("gem use with a modifier", ResolveAttribute(MageButlerButton_gem, "ctrl-", "type", "2"), "item")
    eq("portal row with a modifier", ResolveAttribute(MageButlerSub_portalsRow1, "alt-", "type", "1"), "spell")
    eq("list button with a modifier", ResolveAttribute(MageButlerBuffUnit_raid5, "shift-", "spell", "1"), 10157)

    -- On the orb only a plain right-click reaches the buff.
    SetAura("player", nil)
    FireEvent("UNIT_AURA", "player")
    RunFor(1)
    eq("plain right-click casts", ResolveAttribute(MageButlerOrb, "", "type", "2"), "spell")
    eq("shift right-click has no action", ResolveAttribute(MageButlerOrb, "shift-", "type", "2"), nil)
    eq("ctrl right-click has no action", ResolveAttribute(MageButlerOrb, "ctrl-", "type", "2"), nil)
    eq("left-click has no action", ResolveAttribute(MageButlerOrb, "", "type", "1"), nil)

    -- The client withholding buff data: show nothing rather than a false alarm.
    M.aurasRestricted = true
    FireEvent("ADDON_RESTRICTION_STATE_CHANGED")
    RunFor(1)
    eq("restricted: grey", watch:GetOverall(), "off")
    eq("restricted: no cast", Orb("type2"), nil)
    check("restricted: paused", watch:GetState().paused)
    RunScript(MageButlerOrb, "PreClick", "RightButton", true)
    RunScript(MageButlerOrb, "PostClick", "RightButton", false)
    RunScript(MageButlerOrb, "OnEnter")
    M.aurasRestricted = false
    FireEvent("ADDON_RESTRICTION_STATE_CHANGED")
    RunFor(1)
    eq("readable again", watch:GetOverall(), "none")
    SetAura("player", 10157)
    FireEvent("UNIT_AURA", "player")
    RunFor(1)
    eq("buffed again", watch:GetOverall(), "ok")
end)

phase("combat deferral", function()
    FireEvent("PLAYER_REGEN_DISABLED")
    M.combat = true
    MB.db.radial.radius = 100
    MB:Fire("SETTINGS_CHANGED", "radial")
    SetBook({ 133, 5504, 587 })
    FireEvent("SPELLS_CHANGED")
    RunTimers()
    FireEvent("BAG_UPDATE_DELAYED")
    eq("attributes untouched in combat", MageButlerButton_water:GetAttribute("*spell1"), 10140)
    M.combat = false
    FireEvent("PLAYER_REGEN_ENABLED")
    RunTimers()
    eq("attributes applied after combat", MageButlerButton_water:GetAttribute("*spell1"), 5504)
    eq("no portals now", #MB.Spells:GetPortals(), 0)
    check("old portal row cleared", MageButlerSub_portalsRow1:GetAttribute("spell") == nil)
    eq("gem button cleared", MageButlerButton_gem:GetAttribute("*type1"), nil)
    eq("protected violations", M.violations, 0)
end)

phase("ui scripts", function()
    local buttons = { "portals", "teleports", "water", "food", "gem", "trade" }
    for _, key in ipairs(buttons) do
        local button = _G["MageButlerButton_" .. key]
        RunScript(button, "OnEnter")
        RunScript(button, "OnLeave")
    end
    RunScript(MageButlerOrb, "OnEnter")
    RunScript(MageButlerOrb, "OnDragStart")
    RunScript(MageButlerOrb, "OnDragStop")
    RunScript(MageButlerOrb, "PostClick", "MiddleButton", false)
    RunScript(MageButlerOrb, "PostClick", "MiddleButton", false)
    RunScript(MageButlerHUD, "OnEnter")
    RunScript(MageButlerHUD, "OnDragStart")
    RunScript(MageButlerHUD, "OnDragStop")
    RunScript(MageButlerButton_trade, "OnClick", "RightButton")
    RunScript(MageButlerButton_trade, "OnClick", "RightButton")
    RunScript(MageButlerButton_trade, "OnClick", "LeftButton")
    MageButlerMenu:Show()
    MageButlerSub_portals:Show()
    MageButlerSub_portals:Hide()
    RunScript(MageButlerSub_teleportsRow1, "OnEnter")
    RunScript(MageButlerSub_teleportsRow1, "PostClick", "LeftButton", true)
    check("menu stays open on key-down phase", MageButlerMenu:IsShown())
    RunScript(MageButlerSub_teleportsRow1, "PostClick", "LeftButton", false)
    check("menu closes after travel", not MageButlerMenu:IsShown())
    FireEvent("READY_CHECK")
    M.instance = "party"
    FireEvent("PLAYER_ENTERING_WORLD")
    RunTimers()
    M.instance = nil
    FireEvent("PLAYER_ENTERING_WORLD")
end)

phase("tooltips and status animations", function()
    local orb = MageButlerOrb
    local scale = orb:GetEffectiveScale()
    local function At(dx, dy) M.mouse = { x = (400 + dx) * scale, y = (300 + dy) * scale } end

    At(0, 0)
    RunScript(orb, "OnEnter")
    check("orb tooltip shows inside the circle", GameTooltip:IsShown())
    check("orb follows the cursor while hovered", orb:GetScript("OnUpdate") ~= nil)

    At(21, 21) -- still inside the 46px square, outside the circle
    RunScript(orb, "OnUpdate", 0.01)
    check("hidden in the square's empty corner", not GameTooltip:IsShown())
    At(5, 5)
    RunScript(orb, "OnUpdate", 0.01)
    check("back when the cursor returns to the circle", GameTooltip:IsShown())

    -- The client never delivers OnLeave: the tooltip must still close.
    M.mouseOver = false
    RunScript(orb, "OnUpdate", 0.01)
    check("closes without an OnLeave", not GameTooltip:IsShown())
    check("stops following the cursor", orb:GetScript("OnUpdate") == nil)
    M.mouseOver = nil

    RunScript(orb, "OnEnter")
    RunScript(orb, "OnLeave")
    check("closes on OnLeave", not GameTooltip:IsShown())
    check("no tracking left behind", orb:GetScript("OnUpdate") == nil)
    M.mouse = nil

    -- Pulse follows the state and the setting.
    local dot = UIParent:CreateTexture()
    MB.Theme:SetPulse(dot, MB.Theme:PulseForState("none"))
    eq("missing pulses fast", dot.mbPulseMode, "fast")
    MB.Theme:SetPulse(dot, MB.Theme:PulseForState("low"))
    eq("warning pulses slowly", dot.mbPulseMode, "slow")
    MB.Theme:SetPulse(dot, MB.Theme:PulseForState("ok"))
    eq("fine is steady", dot.mbPulseMode, nil)
    MB.db.appearance.statusAnimations = false
    MB.Theme:SetPulse(dot, "fast")
    eq("setting off: steady", dot.mbPulseMode, nil)
    MB.db.appearance.statusAnimations = true
end)

phase("settings panel", function()
    MB.Settings:Toggle()
    check("settings frame", MageButlerSettings ~= nil and MageButlerSettings:IsShown())
    for _, section in ipairs({ "general", "radial", "buffwatch", "reagents", "conjuring", "trading", "appearance" }) do
        MB.Settings:Open(section)
    end
    MB.db.keybinds.water = "ALT-W"
    MB.db.appearance.accent = "violet"
    MB:Fire("SETTINGS_CHANGED", "all")
    eq("binding applied", M.bindings["ALT-W"], "MageButlerButton_water:LeftButton")
    MB.Settings:Toggle()
    check("settings hidden", not MageButlerSettings:IsShown())
end)

phase("slash commands and profiles", function()
    local slash = SlashCmdList["MAGEBUTLER"]
    slash("")
    slash("")
    slash("menu")
    slash("menu")
    slash("orb")
    check("orb hidden by /mb orb", not MageButlerOrb:IsShown())
    slash("orb")
    check("orb restored", MageButlerOrb:IsShown())
    slash("hud")
    slash("hud")
    slash("ready")
    slash("buffs")
    slash("buffs")
    slash("fill")
    slash("reset")
    slash("help")
    MageButlerDB.chars["Alt - TestRealm"] = { general = { uiScale = 1.25 }, radial = { radius = 64 } }
    eq("other profiles", #MB.Config:GetOtherProfiles(), 1)
    check("copy works", MB.Config:CopyFrom("Alt - TestRealm"))
    eq("copied value", MB.db.radial.radius, 64)
    eq("defaults filled in", MB.db.trade.presets.party.water, 40)
    eq("orb scale applied", MageButlerOrb:GetScale(), 1.25)
    MB.Config:Reset()
    eq("reset value", MB.db.radial.radius, 78)
    MB.db.general.enabled = false
    MB:Fire("SETTINGS_CHANGED", "general")
    check("disabled hides orb", not MageButlerOrb:IsShown())
    check("disabled hides HUD", not MageButlerHUD:IsShown())
    eq("disabled clears bindings", next(M.bindings), nil)
    MB.db.general.enabled = true
    MB:Fire("SETTINGS_CHANGED", "general")
    RunTimers()
end)

LOG("violations: " .. M.violations)
LOG("RESULT: " .. passed .. " passed, " .. failed .. " failed")
