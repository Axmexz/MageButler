-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: defaults and SavedVariables.
-- Settings are stored per character inside one account-wide table, so a
-- profile can be copied from another character.

local _, MB = ...
local Config = MB:NewModule("Config")

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
        classAware = true,
        blockedBuild = "",
        presets = {
            party = { water = 40, food = 20 },
            raid = { water = 20, food = 0 },
            other = { water = 20, food = 20 },
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
    MB.db = ApplyDefaults(root.chars[self.key], self.defaults)
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
