-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: defaults and SavedVariables.
-- Settings are stored per character inside one account-wide table, so a
-- profile can be copied from another character.

local _, MB = ...
local Config = MB:NewModule("Config")

-- Classes with their own row in the trade settings, in display order.
Config.CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID", "PRIEST", "MAGE", "WARLOCK" }

local function Row(water, food)
    return { water = water, food = food }
end

Config.defaults = {
    general = {
        enabled = true,
        showOrb = true,
        showHUD = true,
        lockPositions = false,
        uiScale = 1.0,
        chatMessages = false,
    },
    orb = { x = -340, y = -120 },
    radial = {
        radius = 78,
        buttonSize = 40,
        animations = true,
        showLabels = true,
        showCounts = true,
        closeAfterTravel = true,
        buttons = {
            portals = true,
            teleports = true,
            water = true,
            food = true,
            gem = true,
            trade = true,
        },
    },
    reagents = {
        enabled = true,
        items = {
            runeT = { enabled = true, target = 10, warn = 2, maxSpend = 5, confirm = false },
            runeP = { enabled = true, target = 10, warn = 2, maxSpend = 5, confirm = false },
            powder = { enabled = true, target = 20, warn = 5, maxSpend = 5, confirm = false },
        },
    },
    conjuring = {
        waterTarget = 40,
        foodTarget = 20,
        wantGem = true,
        warnMissing = true,
    },
    trade = {
        enabled = true,
        showFillButton = true,
        usableOnly = true,
        blockedBuild = "",
        -- Items of water and food to offer, by who the player is to you and by
        -- their class (20 is one full stack). Standard numbers: two stacks of
        -- food and no water for the classes without mana, two stacks of water
        -- and one of food for everyone else. UNKNOWN is used when the client
        -- does not report the class.
        amounts = {
            party = {
                WARRIOR = Row(0, 40), ROGUE = Row(0, 40), HUNTER = Row(40, 20),
                PALADIN = Row(40, 20), SHAMAN = Row(40, 20), DRUID = Row(40, 20),
                PRIEST = Row(40, 20), MAGE = Row(40, 20), WARLOCK = Row(40, 20),
                UNKNOWN = Row(40, 20),
            },
            raid = {
                WARRIOR = Row(0, 40), ROGUE = Row(0, 40), HUNTER = Row(40, 20),
                PALADIN = Row(40, 20), SHAMAN = Row(40, 20), DRUID = Row(40, 20),
                PRIEST = Row(40, 20), MAGE = Row(40, 20), WARLOCK = Row(40, 20),
                UNKNOWN = Row(40, 20),
            },
            other = {
                WARRIOR = Row(0, 20), ROGUE = Row(0, 20), HUNTER = Row(20, 20),
                PALADIN = Row(20, 20), SHAMAN = Row(20, 20), DRUID = Row(20, 20),
                PRIEST = Row(20, 20), MAGE = Row(20, 20), WARLOCK = Row(20, 20),
                UNKNOWN = Row(20, 20),
            },
        },
    },
    buffwatch = {
        enabled = true,
        party = true,
        raid = true,
        solo = true,
        orbIndicator = true,
        orbColors = true,
        showCounter = true,
        tooltipNames = true,
        notify = "toast",        -- "toast", "chat" or "off"
        partyThreshold = 3,
        raidThreshold = 6,
        preferBrilliance = true,
        fallbackIntellect = true,
        acceptLowerRanks = true,
        scope = "auto",          -- what Arcane Brilliance covers: "auto", "group" or "raid"
        watchExpiry = true,
        rebuffMinutes = 5,
        ignoreOffline = true,
        ignoreDead = true,
        skipUnavailable = true,
        missingFirst = true,
        manaUsersOnly = false,
    },
    hud = {
        x = 0,
        y = -260,
        cells = {
            intellect = true,
            food = true,
            water = true,
            gem = true,
            runeT = true,
            runeP = true,
            powder = true,
        },
    },
    readiness = {
        enabled = true,
        onReadyCheck = true,
        onInstance = true,
    },
    appearance = {
        accent = "arcane",
        panelAlpha = 0.92,
        glow = true,
        hudLabels = true,
        statusAnimations = true,
    },
    keybinds = {},
}

local function DeepCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

--- Fills in keys missing from `target`; values of the wrong type are replaced.
local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            ApplyDefaults(target[key], value)
        elseif type(target[key]) ~= type(value) then
            target[key] = value
        end
    end
    return target
end

--- Earlier versions stored trade amounts as three presets (party, raid, other)
--- plus a per-class scale. A profile that changed those keeps its numbers,
--- worked out into the per-class table; an untouched one gets the standard
--- numbers. The old keys are removed either way.
local function MigrateTrade(profile)
    local trade = profile.trade
    if type(trade) ~= "table" then return end
    local presets, classes = trade.presets, trade.classes

    if type(presets) == "table" and type(trade.amounts) ~= "table" then
        local oldPresets = { party = Row(40, 20), raid = Row(20, 0), other = Row(20, 20) }
        local function Scale(class)
            local scale = type(classes) == "table" and classes[class] or nil
            local water = (class == "WARRIOR" or class == "ROGUE") and 0 or 1
            local food = 1
            local changed = false
            if type(scale) == "table" then
                if type(scale.water) == "number" and scale.water ~= water then water, changed = scale.water, true end
                if type(scale.food) == "number" and scale.food ~= food then food, changed = scale.food, true end
            end
            if trade.classAware == false and water == 0 then water, changed = 1, true end
            return water, food, changed
        end

        local customised = false
        for relation, old in pairs(oldPresets) do
            local preset = presets[relation]
            if type(preset) ~= "table" or preset.water ~= old.water or preset.food ~= old.food then
                customised = true
            end
        end
        for _, class in ipairs(Config.CLASSES) do
            local _, _, changed = Scale(class)
            if changed then customised = true end
        end

        if customised then
            local amounts = {}
            for relation, old in pairs(oldPresets) do
                local preset = presets[relation]
                local water = type(preset) == "table" and type(preset.water) == "number" and preset.water or old.water
                local food = type(preset) == "table" and type(preset.food) == "number" and preset.food or old.food
                amounts[relation] = { UNKNOWN = Row(water, food) }
                for _, class in ipairs(Config.CLASSES) do
                    local waterScale, foodScale = Scale(class)
                    amounts[relation][class] = Row(math.floor(water * waterScale + 0.5), math.floor(food * foodScale + 0.5))
                end
            end
            trade.amounts = amounts
        end
    end

    trade.presets, trade.classes, trade.classAware = nil, nil, nil
end

function Config:Init()
    if type(MageButlerDB) ~= "table" then
        MageButlerDB = {}
    end
    local root = MageButlerDB
    root.version = 1
    if type(root.chars) ~= "table" then
        root.chars = {}
    end

    self.root = root
    self.key = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")

    if type(root.chars[self.key]) ~= "table" then
        root.chars[self.key] = {}
    end
    MigrateTrade(root.chars[self.key])
    MB.db = ApplyDefaults(root.chars[self.key], self.defaults)
end

function Config:ResetTradeAmounts()
    MB.db.trade.amounts = DeepCopy(self.defaults.trade.amounts)
    MB:Fire("SETTINGS_CHANGED", "trade")
end

--- Names of the other characters that have a stored profile.
function Config:GetOtherProfiles()
    local list = {}
    for key in pairs(self.root.chars) do
        if key ~= self.key then
            list[#list + 1] = key
        end
    end
    table.sort(list)
    return list
end

function Config:CopyFrom(key)
    local source = self.root.chars[key]
    if type(source) ~= "table" or key == self.key then return false end
    local copy = DeepCopy(source)
    MigrateTrade(copy)
    self.root.chars[self.key] = copy
    MB.db = ApplyDefaults(copy, self.defaults)
    MB:Fire("SETTINGS_CHANGED", "all")
    return true
end

function Config:Reset()
    local fresh = DeepCopy(self.defaults)
    self.root.chars[self.key] = fresh
    MB.db = fresh
    MB:Fire("SETTINGS_CHANGED", "all")
end

function Config:ResetPositions()
    MB.db.orb.x, MB.db.orb.y = self.defaults.orb.x, self.defaults.orb.y
    MB.db.hud.x, MB.db.hud.y = self.defaults.hud.x, self.defaults.hud.y
end
