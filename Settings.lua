-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: settings panel (built on first use).

local _, MB = ...
local Settings = MB:NewModule("Settings")
local Theme

local WIDTH, HEIGHT = 640, 496
local SIDEBAR = 152
local TITLE = 38
local COLUMN = 215 -- horizontal distance between option columns
local PAGE_WIDTH = WIDTH - SIDEBAR - 54 -- usable width of a settings page

local SECTIONS = {
    { key = "general", label = "General", icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "radial", label = "Radial Menu", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    { key = "buffwatch", label = "Buff Watch", icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect" },
    { key = "reagents", label = "Reagents", icon = "Interface\\Icons\\INV_Misc_Rune_06" },
    { key = "conjuring", label = "Conjuring", icon = "Interface\\Icons\\INV_Drink_07" },
    { key = "trading", label = "Trading", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { key = "appearance", label = "Appearance", icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02" },
}

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true, PRINTSCREEN = true,
}

local frame
local pages, navButtons = {}, {}
local refreshers = {}
local builders = {}
local capture

local function Changed(section)
    MB:Fire("SETTINGS_CHANGED", section)
end

--- get/set pair for one field of a settings table (looked up at call time, so
--- it keeps working after the profile is copied or reset).
local function Field(section, getTable, key)
    return function()
        return getTable()[key]
    end, function(value)
        getTable()[key] = value
        Changed(section)
    end
end

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------
local function Label(parent, x, y, text, size, colorName)
    local label = Theme:Text(parent, size or 11)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    if colorName then
        label:SetTextColor(Theme:Color(colorName))
    end
    return label
end

local function Header(page, y, text)
    local label = Label(page, 0, y, text, 13, "gold")
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, y - 18)
    line:SetWidth(PAGE_WIDTH)
    return label
end

local function Note(page, y, text)
    local label = Label(page, 0, y, text, 10, "dim")
    label:SetWidth(PAGE_WIDTH)
    label:SetWordWrap(true)
    label:SetSpacing(2)
    return label
end

local function Checkbox(page, x, y, text, tooltip, get, set)
    local check = CreateFrame("CheckButton", nil, page, "BackdropTemplate")
    check:SetSize(18, 18)
    check:SetPoint("TOPLEFT", x, y)
    Theme:SkinBox(check, "panel")

    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local mark = check:GetCheckedTexture()
    if mark then
        mark:SetDesaturated(true)
        Theme:UseAccent(mark, "SetVertexColor", 1)
    end

    check.text = Theme:Text(check, 12)
    check.text:SetPoint("LEFT", check, "RIGHT", 7, 0)
    check.text:SetText(text or "")
    if text then
        check:SetHitRectInsets(0, -(check.text:GetStringWidth() + 8), 0, 0)
    end

    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    Theme:AttachTooltip(check, tooltip and (text or tooltip) or nil, text and tooltip or nil)

    refreshers[#refreshers + 1] = function()
        check:SetChecked(get() and true or false)
    end
    return check
end

local function Slider(page, x, y, width, text, tooltip, low, high, step, format, get, set)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(width, 36)
    holder:SetPoint("TOPLEFT", x, y)

    holder.label = Theme:Text(holder, 11)
    holder.label:SetPoint("TOPLEFT", 0, 0)
    holder.label:SetText(text)
    holder.label:SetTextColor(Theme:Color("dim"))

    holder.value = Theme:Text(holder, 11)
    holder.value:SetPoint("TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 10)
    slider:SetPoint("BOTTOMLEFT", 0, 4)
    Theme:SkinBox(slider, "panel")
    slider:SetThumbTexture(MB.MEDIA .. "Circle.tga")
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(16, 16)
        Theme:UseAccent(thumb, "SetVertexColor", 1)
    end
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local function Snap(value)
        return math.floor(value / step + 0.5) * step
    end

    slider:SetScript("OnValueChanged", function(_, value, userInput)
        value = Snap(value)
        holder.value:SetText(format(value))
        if userInput and math.abs(value - get()) > step / 100 then
            set(value)
        end
    end)
    Theme:AttachTooltip(slider, text, tooltip)

    refreshers[#refreshers + 1] = function()
        local value = Snap(get())
        slider:SetValue(value)
        holder.value:SetText(format(value))
    end
    return holder
end

local function NumberBox(page, x, y, width, title, tooltip, low, high, get, set)
    local box = CreateFrame("EditBox", nil, page, "BackdropTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", x, y)
    Theme:SkinBox(box, "panel")
    box:SetFontObject(GameFontHighlightSmall)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    box:SetJustifyH("CENTER")
    box:SetTextInsets(4, 4, 0, 0)

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(get()))
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText()) or low
        value = math.max(low, math.min(high, math.floor(value)))
        self:SetText(tostring(value))
        if value ~= get() then
            set(value)
        end
    end)
    Theme:AttachTooltip(box, title, tooltip)

    refreshers[#refreshers + 1] = function()
        if not box:HasFocus() then
            box:SetText(tostring(get()))
        end
    end
    return box
end

local function PanelButton(page, x, y, text, width, tooltip, onClick)
    local button = Theme:CreateButton(page, text, width, 22)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", onClick)
    Theme:AttachTooltip(button, tooltip and text or nil, tooltip)
    return button
end

--- A button that steps through a fixed list of choices: { { value, label }, ... }.
local function Cycle(page, x, y, width, title, tooltip, options, get, set)
    local button = Theme:CreateButton(page, "", width, 20)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", function()
        local current = get()
        local index = 1
        for i = 1, #options do
            if options[i][1] == current then index = i % #options + 1 end
        end
        set(options[index][1])
    end)
    Theme:AttachTooltip(button, title, tooltip)
    refreshers[#refreshers + 1] = function()
        local current = get()
        local text = options[1][2]
        for i = 1, #options do
            if options[i][1] == current then text = options[i][2] end
        end
        button.label:SetText(text)
    end
    return button
end

-------------------------------------------------------------------------------
-- Keybind capture
-------------------------------------------------------------------------------
local function BindingText(key)
    if type(key) == "string" and key ~= "" then return key end
    return "|cff8f9fc9Not bound|r"
end

local function StopCapture()
    if not capture then return end
    local button = capture.button
    capture = nil
    button:EnableKeyboard(false)
    button:SetScript("OnKeyDown", nil)
    button.label:SetText(BindingText(MB.db.keybinds[button.action]))
end

local function AssignKey(action, key)
    local binds = MB.db.keybinds
    if key then
        -- One key, one action.
        for other, bound in pairs(binds) do
            if bound == key and other ~= action then
                binds[other] = nil
            end
        end
        local existing = GetBindingAction(key)
        if type(existing) == "string" and existing ~= "" then
            MB:Print(key .. " also triggers a game binding; MageButler takes priority while it is enabled.")
        end
    end
    binds[action] = key
    Changed("radial")
end

local function StartCapture(button)
    StopCapture()
    if InCombatLockdown() then
        MB:Print("keybinds cannot be changed in combat.")
        return
    end
    capture = { button = button }
    button.label:SetText("|cffffd100Press a key...|r")
    button:EnableKeyboard(true)
    button:SetScript("OnKeyDown", function(self, key)
        if IGNORED_KEYS[key] then return end
        if key == "ESCAPE" then
            StopCapture()
            return
        end
        local combo = ""
        if IsAltKeyDown() then combo = combo .. "ALT-" end
        if IsControlKeyDown() then combo = combo .. "CTRL-" end
        if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
        local action = self.action
        StopCapture()
        AssignKey(action, combo .. key)
    end)
end

local function KeybindRow(page, x, y, binding)
    Label(page, x, y - 4, binding.label, 11)
    local button = Theme:CreateButton(page, "", 100, 20)
    button:SetPoint("TOPLEFT", x + 108, y)
    button.action = binding.key
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            StopCapture()
            AssignKey(self.action, nil)
        elseif capture and capture.button == self then
            StopCapture()
        else
            StartCapture(self)
        end
    end)
    Theme:AttachTooltip(button, binding.label, "Click, then press a key (modifiers allowed). Right-click to clear. Escape cancels.")
    refreshers[#refreshers + 1] = function()
        if not (capture and capture.button == button) then
            button.label:SetText(BindingText(MB.db.keybinds[binding.key]))
        end
    end
    return button
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
builders.general = function(page)
    local function general() return MB.db.general end
    local function readiness() return MB.db.readiness end

    Header(page, 0, "General Settings")
    Checkbox(page, 0, -28, "Enable MageButler", "Turns the whole addon on or off for this character.",
        Field("general", general, "enabled"))
    Checkbox(page, COLUMN, -28, "Show Mage orb", "The orb opens the radial menu. /mb orb also toggles it.",
        Field("general", general, "showOrb"))
    Checkbox(page, 0, -52, "Show inventory HUD", "A compact bar with food, water, mana gem and reagent counts.",
        Field("general", general, "showHUD"))
    Checkbox(page, COLUMN, -52, "Lock positions", "Prevents the orb and the HUD from being dragged.",
        Field("general", general, "lockPositions"))
    Checkbox(page, 0, -76, "Repeat notifications in chat", "Also prints MageButler's on-screen notifications to the chat frame.",
        Field("general", general, "chatMessages"))

    Slider(page, 0, -108, 200, "UI scale", "Scales the orb, the radial menu and the HUD.", 0.6, 1.6, 0.05,
        function(value) return math.floor(value * 100 + 0.5) .. "%" end,
        Field("general", general, "uiScale"))
    PanelButton(page, COLUMN, -118, "Reset positions", 130, "Moves the orb and the HUD back to their default places.", function()
        MB.Config:ResetPositions()
        Changed("all")
    end)

    Header(page, -160, "Preparation Check")
    Checkbox(page, 0, -188, "Show the preparation indicator",
        "A small pip on the orb and a dot on the HUD: green when you carry enough water, food, a mana gem and reagents. Click the pip for the checklist.",
        Field("general", readiness, "enabled"))
    Checkbox(page, 0, -212, "Report on ready checks", "Shows the preparation result whenever a ready check starts.",
        Field("general", readiness, "onReadyCheck"))
    Checkbox(page, COLUMN, -212, "Warn when entering instances", "Shows what is missing when you walk into a dungeon or raid short of supplies.",
        Field("general", readiness, "onInstance"))

    Header(page, -246, "Character Profile")
    local profileText = Label(page, 0, -272, "", 11, "dim")

    local selected
    local picker = PanelButton(page, 0, -294, "", 190, "Click to choose which character to copy from.", function(self)
        local list = MB.Config:GetOtherProfiles()
        if #list == 0 then return end
        local index = 1
        for i = 1, #list do
            if list[i] == selected then index = i % #list + 1 end
        end
        selected = list[index]
        self.label:SetText(selected)
    end)
    local copy = PanelButton(page, 198, -294, "Copy settings", 110, "Replaces this character's settings with the selected character's.", function()
        if selected and MB.Config:CopyFrom(selected) then
            MB:Print("settings copied from " .. selected .. ".")
        end
    end)
    PanelButton(page, 316, -294, "Reset defaults", 110, "Restores every MageButler setting for this character.", function()
        MB.Config:Reset()
        MB:Print("settings reset to defaults.")
    end)

    refreshers[#refreshers + 1] = function()
        profileText:SetText("Settings are saved per character: " .. MB.Config.key)
        local list = MB.Config:GetOtherProfiles()
        local found = false
        for i = 1, #list do
            if list[i] == selected then found = true end
        end
        if not found then selected = list[1] end
        picker.label:SetText(selected or "No other characters yet")
        picker:SetEnabled(#list > 0)
        copy:SetEnabled(selected ~= nil)
    end

    Label(page, 0, -340, "MageButler v" .. MB.version .. "  |cff8f9fc9by " .. MB.author .. "|r", 12)
    Label(page, 0, -358, "Your personal Mage assistant for WoW Forever.  /mb for commands.", 10, "dim")
end

builders.radial = function(page)
    local function radial() return MB.db.radial end
    local function shown() return MB.db.radial.buttons end
    local function whole(value) return tostring(math.floor(value + 0.5)) end

    Header(page, 0, "Radial Menu")
    Slider(page, 0, -30, 200, "Menu radius", "Distance of the buttons from the orb.", 50, 140, 2, whole,
        Field("radial", radial, "radius"))
    Slider(page, COLUMN, -30, 200, "Button size", "Size of the round buttons.", 28, 56, 2, whole,
        Field("radial", radial, "buttonSize"))

    Checkbox(page, 0, -78, "Opening animation", "A short fade when the menu opens.",
        Field("radial", radial, "animations"))
    Checkbox(page, COLUMN, -78, "Button labels", "Shows the name under each button.",
        Field("radial", radial, "showLabels"))
    Checkbox(page, 0, -102, "Inventory counts", "Shows how much water, food, gems and runes you carry on the buttons.",
        Field("radial", radial, "showCounts"))
    Checkbox(page, COLUMN, -102, "Close after travelling", "Closes the menu after you pick a portal or teleport (outside combat).",
        Field("radial", radial, "closeAfterTravel"))

    Header(page, -136, "Buttons")
    local names = {
        { "portals", "Portals" }, { "teleports", "Teleports" }, { "water", "Conjure Water" },
        { "food", "Conjure Food" }, { "gem", "Mana Gem" }, { "trade", "Trade" },
    }
    for i = 1, #names do
        local column = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        Checkbox(page, column * 145, -164 - row * 24, names[i][2], "Shows or hides this button on the radial menu.",
            Field("radial", shown, names[i][1]))
    end

    Header(page, -222, "Keybindings")
    local bindings = MB.RadialMenu.BINDINGS
    for i = 1, #bindings do
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        KeybindRow(page, column * 218, -250 - row * 26, bindings[i])
    end
    Note(page, -334, "Spells are always cast by your own key press or click. Keys set here work while MageButler is enabled and override the game's binding for the same key.")
end

builders.buffwatch = function(page)
    local function watch() return MB.db.buffwatch end
    local RIGHT = COLUMN

    Header(page, 0, "Buff Watch")
    Checkbox(page, 0, -28, "Enable Buff Watch",
        "Watches you and your group for missing or expiring Arcane Intellect and Arcane Brilliance. Right-click the orb to cast the recommended buff.",
        Field("buffwatch", watch, "enabled"))
    Checkbox(page, RIGHT, -28, "Orb status indicator",
        "A pip on the orb: green when everyone is buffed, yellow when buffs are expiring, red when players are missing Intellect, grey when there is nothing to watch.",
        Field("buffwatch", watch, "orbIndicator"))
    Checkbox(page, 0, -52, "Watch in parties", "Monitor party members.", Field("buffwatch", watch, "party"))
    Checkbox(page, RIGHT, -52, "Watch in raids", "Monitor every raid member, up to 40 players.", Field("buffwatch", watch, "raid"))
    Checkbox(page, 0, -76, "Watch while solo", "When you are not grouped, right-clicking the orb buffs you.", Field("buffwatch", watch, "solo"))

    Header(page, -106, "Buff Selection")
    Label(page, 0, -138, "Party threshold", 12)
    NumberBox(page, 130, -134, 44, "Party threshold",
        "In a party, use Arcane Brilliance once this many players need Intellect. Below that, players are buffed one at a time.", 1, 5,
        Field("buffwatch", watch, "partyThreshold"))
    Label(page, RIGHT, -138, "Raid threshold", 12)
    NumberBox(page, RIGHT + 130, -134, 44, "Raid threshold",
        "In a raid, use Arcane Brilliance once this many players across the whole raid need Intellect.", 1, 40,
        Field("buffwatch", watch, "raidThreshold"))
    Checkbox(page, 0, -162, "Prefer Arcane Brilliance", "Use Arcane Brilliance when the threshold is reached, it is learned and you carry Arcane Powder.",
        Field("buffwatch", watch, "preferBrilliance"))
    Checkbox(page, RIGHT, -162, "Fall back to Arcane Intellect", "Without Arcane Powder, buff players one at a time instead of doing nothing.",
        Field("buffwatch", watch, "fallbackIntellect"))
    Checkbox(page, 0, -186, "Accept lower ranks", "Treat any rank of Arcane Intellect or Arcane Brilliance as buffed. Turn this off to flag ranks weaker than your own.",
        Field("buffwatch", watch, "acceptLowerRanks"))
    Label(page, RIGHT, -190, "Brilliance covers", 12)
    Cycle(page, RIGHT + 110, -186, 104, "Arcane Brilliance covers",
        "Whether one cast reaches the target's group or the whole raid. Automatic reads the spell's own description.",
        { { "auto", "Automatic" }, { "group", "Target's group" }, { "raid", "Whole raid" } },
        Field("buffwatch", watch, "scope"))

    Header(page, -216, "Duration and Targets")
    Checkbox(page, 0, -244, "Watch for expiring buffs", "Count a buff that is about to run out as needing a rebuff.",
        Field("buffwatch", watch, "watchExpiry"))
    Label(page, RIGHT, -248, "Rebuff at (minutes)", 12)
    NumberBox(page, RIGHT + 130, -244, 44, "Rebuff threshold", "A buff with less than this many minutes left counts as expiring. Longer buffs are left alone.", 1, 30,
        Field("buffwatch", watch, "rebuffMinutes"))
    Checkbox(page, 0, -268, "Ignore offline players", "Players who are disconnected are not counted.", Field("buffwatch", watch, "ignoreOffline"))
    Checkbox(page, RIGHT, -268, "Ignore dead players", "Dead players and ghosts are not counted.", Field("buffwatch", watch, "ignoreDead"))
    Checkbox(page, 0, -292, "Skip unavailable players", "Players in another zone or too far away to be seen are not counted.",
        Field("buffwatch", watch, "skipUnavailable"))
    Checkbox(page, RIGHT, -292, "Missing before expiring", "Buff players with no Intellect at all before refreshing buffs that are running out.",
        Field("buffwatch", watch, "missingFirst"))
    Checkbox(page, 0, -316, "Mana users only", "Leave Warriors and Rogues out of the count.", Field("buffwatch", watch, "manaUsersOnly"))

    Header(page, -346, "Display")
    Checkbox(page, 0, -374, "Orb warning colours", "Tints the orb's ring yellow or red while buffs need attention.",
        Field("buffwatch", watch, "orbColors"))
    Checkbox(page, RIGHT, -374, "Coverage counter", "Shows group coverage such as 32/40 above the orb.",
        Field("buffwatch", watch, "showCounter"))
    Checkbox(page, 0, -398, "Names in tooltip", "Lists the players who need a buff in the orb's tooltip.",
        Field("buffwatch", watch, "tooltipNames"))
    Label(page, RIGHT, -402, "Notifications", 12)
    Cycle(page, RIGHT + 110, -398, 104, "Buff Watch notifications",
        "Where Buff Watch says what a right-click cast, or why it did nothing.",
        { { "toast", "On screen" }, { "chat", "Chat" }, { "off", "Off" } },
        Field("buffwatch", watch, "notify"))
end

builders.reagents = function(page)
    local Reagents = MB.Reagents
    local function reagents() return MB.db.reagents end

    Header(page, 0, "Reagent Restocking")
    Checkbox(page, 0, -28, "Restock automatically at reagent vendors",
        "When a merchant who sells your reagents is opened, MageButler buys up to each target.",
        Field("reagents", reagents, "enabled"))

    local columns = { 0, 190, 252, 314, 392 }
    Label(page, columns[1] + 25, -64, "Reagent", 10, "dim")
    Label(page, columns[2], -64, "Target", 10, "dim")
    Label(page, columns[3], -64, "Warn at", 10, "dim")
    Label(page, columns[4], -64, "Max gold", 10, "dim")
    Label(page, columns[5], -64, "Confirm", 10, "dim")

    for i, key in ipairs(Reagents.ORDER) do
        local y = -84 - (i - 1) * 30
        local function item() return MB.db.reagents.items[key] end

        local check = Checkbox(page, columns[1], y, Reagents:Name(key),
            "Track and restock this reagent. It is only bought once you know a spell that uses it.",
            Field("reagents", item, "enabled"))
        refreshers[#refreshers + 1] = function()
            check.text:SetText(Reagents:Name(key))
        end

        NumberBox(page, columns[2], y + 1, 48, "Target", "How many to carry after restocking.", 0, 200,
            Field("reagents", item, "target"))
        NumberBox(page, columns[3], y + 1, 48, "Low-stock warning", "Warn when you carry this many or fewer.", 0, 200,
            Field("reagents", item, "warn"))
        NumberBox(page, columns[4], y + 1, 48, "Spending limit", "Most gold to spend on this reagent per vendor visit. 0 means no limit.", 0, 999,
            Field("reagents", item, "maxSpend"))
        Checkbox(page, columns[5] + 12, y, nil, "Ask before buying this reagent.",
            Field("reagents", item, "confirm"))
    end

    Note(page, -184, "Purchases never go past the target, your free bag space, your gold or the spending limit. Reagents already in your bags are counted first.")
end

builders.conjuring = function(page)
    local function conjuring() return MB.db.conjuring end
    local function cells() return MB.db.hud.cells end

    Header(page, 0, "Conjuring")
    Label(page, 0, -34, "Water to carry", 12)
    NumberBox(page, 120, -30, 52, "Water target", "Counted in items (20 is one full stack). Used by the HUD and the preparation check. 0 turns tracking off.", 0, 400,
        Field("conjuring", conjuring, "waterTarget"))
    Label(page, COLUMN, -34, "Food to carry", 12)
    NumberBox(page, COLUMN + 120, -30, 52, "Food target", "Counted in items (20 is one full stack). 0 turns tracking off.", 0, 400,
        Field("conjuring", conjuring, "foodTarget"))

    Checkbox(page, 0, -64, "Keep a mana gem ready", "Counts a missing mana gem as unprepared.",
        Field("conjuring", conjuring, "wantGem"))
    Checkbox(page, COLUMN, -64, "Warn when supplies run out", "A short notification the moment your last conjured water or food is gone.",
        Field("conjuring", conjuring, "warnMissing"))

    Note(page, -94, "The radial buttons cast the highest rank you have learned, found in your spellbook. The Mana Gem button conjures the strongest gem you are not carrying; right-click uses your best gem. MageButler never casts on its own.")

    Header(page, -150, "HUD Counters")
    local names = {
        { "food", "Food" }, { "water", "Water" }, { "gem", "Mana Gem" },
        { "runeT", "Rune of Teleportation" }, { "runeP", "Rune of Portals" }, { "powder", "Arcane Powder" },
        { "intellect", "Intellect coverage" },
    }
    for i = 1, #names do
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        Checkbox(page, column * COLUMN, -178 - row * 24, names[i][2], "Shows this counter on the HUD.",
            Field("conjuring", cells, names[i][1]))
    end
end

builders.trading = function(page)
    local function trade() return MB.db.trade end

    Header(page, 0, "Trade Assistant")
    Checkbox(page, 0, -28, "Fill trades automatically",
        "When a trade window opens, offers conjured water and food for the matching preset. Hold Shift as the trade opens to skip it once.",
        function() return MB.db.trade.enabled end,
        function(value)
            MB.db.trade.enabled = value
            if value then MB.Trade:RetryAutomatic() end
            Changed("trade")
        end)
    Checkbox(page, COLUMN, -28, "Show Fill Trade button", "Adds a Fill Trade button above the trade window for filling by hand.",
        Field("trade", trade, "showFillButton"))
    Checkbox(page, 0, -52, "Food only for Warriors and Rogues",
        "Classes without mana get the preset's food but no water.",
        Field("trade", trade, "classAware"))

    Label(page, 0, -88, "Trading with", 10, "dim")
    Label(page, 150, -88, "Water", 10, "dim")
    Label(page, 220, -88, "Food", 10, "dim")

    local presets = { { "party", "Party members" }, { "raid", "Raid members" }, { "other", "Other players" } }
    for i = 1, #presets do
        local key, text = presets[i][1], presets[i][2]
        local y = -108 - (i - 1) * 28
        local function preset() return MB.db.trade.presets[key] end
        Label(page, 0, y - 4, text, 12)
        NumberBox(page, 150, y, 52, text .. ": water", "Items of conjured water to offer (20 is one full stack). 0 offers none.", 0, 120,
            Field("trade", preset, "water"))
        NumberBox(page, 220, y, 52, text .. ": food", "Items of conjured food to offer (20 is one full stack). 0 offers none.", 0, 120,
            Field("trade", preset, "food"))
    end

    local status = Label(page, 0, -200, "", 11)
    status:SetWidth(PAGE_WIDTH)
    status:SetWordWrap(true)
    refreshers[#refreshers + 1] = function()
        if MB.Trade:IsAutoBlocked() then
            status:SetText("|cffffbf40This client refused automatic filling, so it is paused. The Fill Trade button still works. Tick the box above to try again.|r")
        else
            status:SetText("")
        end
    end

    Note(page, -244, "Only conjured water and food are ever offered, only into empty trade slots, and only once per trade. MageButler never accepts a trade for you. A trade window has six slots, so at most six stacks fit.")
end

builders.appearance = function(page)
    local function appearance() return MB.db.appearance end

    Header(page, 0, "Appearance")
    Label(page, 0, -34, "Accent colour", 12)
    local accent = PanelButton(page, 120, -29, "", 130, "Click to cycle through the accent colours.", function()
        local order = Theme.accentOrder
        local index = 1
        for i = 1, #order do
            if order[i] == MB.db.appearance.accent then index = i % #order + 1 end
        end
        MB.db.appearance.accent = order[index]
        Changed("appearance")
    end)
    refreshers[#refreshers + 1] = function()
        accent.label:SetText(Theme.accentNames[MB.db.appearance.accent] or Theme.accentNames.arcane)
        accent.label:SetTextColor(Theme:Accent())
    end

    Slider(page, 0, -66, 200, "Panel opacity", "Background opacity of the HUD, submenus and this panel.", 0.5, 1, 0.05,
        function(value) return math.floor(value * 100 + 0.5) .. "%" end,
        Field("appearance", appearance, "panelAlpha"))

    Checkbox(page, 0, -116, "Orb glow", "A soft halo behind the orb.",
        Field("appearance", appearance, "glow"))
    Checkbox(page, COLUMN, -116, "HUD labels", "Shows a small name under each HUD counter.",
        Field("appearance", appearance, "hudLabels"))
    Checkbox(page, 0, -140, "Status animations",
        "The status pips on the orb pulse while something needs attention: slowly for a warning, faster when something is missing. Steady when all is well.",
        Field("appearance", appearance, "statusAnimations"))
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function Refresh()
    if not frame or not frame:IsShown() then return end
    for i = 1, #refreshers do
        refreshers[i]()
    end
end

local function SelectPage(key)
    StopCapture()
    for sectionKey, page in pairs(pages) do
        page:SetShown(sectionKey == key)
    end
    for sectionKey, button in pairs(navButtons) do
        local active = sectionKey == key
        button.bar:SetShown(active)
        button.fill:SetShown(active)
        button.label:SetTextColor(Theme:Color(active and "text" or "dim"))
    end
    frame.selected = key
end

local function CreateNavButton(sidebar, index, section)
    local button = CreateFrame("Button", nil, sidebar)
    button:SetSize(SIDEBAR - 12, 32)
    button:SetPoint("TOPLEFT", 6, -8 - (index - 1) * 34)

    button.fill = button:CreateTexture(nil, "BACKGROUND")
    button.fill:SetAllPoints()
    button.fill:SetColorTexture(Theme.colors.raised[1], Theme.colors.raised[2], Theme.colors.raised[3], 0.9)

    button.bar = button:CreateTexture(nil, "ARTWORK")
    button.bar:SetSize(2, 32)
    button.bar:SetPoint("LEFT", 0, 0)
    button.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:UseAccent(button.bar, "SetVertexColor", 1)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("LEFT", 9, 0)
    button.icon:SetTexture(section.icon)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.label = Theme:Text(button, 12)
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 9, 0)
    button.label:SetText(section.label)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetBlendMode("ADD")
    Theme:UseAccent(highlight, "SetVertexColor", 0.12)

    button:SetScript("OnClick", function()
        SelectPage(section.key)
    end)
    navButtons[section.key] = button
end

local function CreateFrameOnce()
    if frame then return end

    frame = Theme:CreatePanel("MageButlerSettings", UIParent, "bg")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", StopCapture)
    frame:Hide()
    tinsert(UISpecialFrames, "MageButlerSettings")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", 12, -9)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_MagicalSentry")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = Theme:Text(frame, 14)
    title:SetPoint("LEFT", icon, "RIGHT", 9, 0)
    title:SetText("MageButler - Settings")
    Theme:UseAccent(title, "SetTextColor", 1)

    local close = Theme:CreateButton(frame, "x", 22, 20)
    close:SetPoint("TOPRIGHT", -9, -9)
    close.label:SetTextColor(Theme:Color("bad"))
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local sidebar = Theme:CreatePanel(nil, frame, "panel")
    sidebar:SetPoint("TOPLEFT", 8, -TITLE)
    sidebar:SetPoint("BOTTOMLEFT", 8, 8)
    sidebar:SetWidth(SIDEBAR)

    local content = Theme:CreatePanel(nil, frame, "panel")
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -8, 8)

    for index, section in ipairs(SECTIONS) do
        CreateNavButton(sidebar, index, section)

        local page = CreateFrame("Frame", nil, content)
        page:SetPoint("TOPLEFT", 16, -14)
        page:SetPoint("BOTTOMRIGHT", -16, 12)
        page:Hide()
        pages[section.key] = page
        builders[section.key](page)
    end

    SelectPage("general")
end

function Settings:Toggle()
    if not MB.ready then return end
    CreateFrameOnce()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        Refresh()
    end
end

function Settings:Open(section)
    if not MB.ready then return end
    CreateFrameOnce()
    frame:Show()
    if section and pages[section] then
        SelectPage(section)
    end
    Refresh()
end

function Settings:OnEnable()
    Theme = MB.Theme
    MB:On("SETTINGS_CHANGED", Refresh)
    MB:On("SPELLS_UPDATED", Refresh)
end
