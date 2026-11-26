-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: settings panel (built on first use).

local _, MB = ...
local Settings = MB:NewModule("Settings")
local Theme

-- The Announcements page is the tallest and sets the height: with a preview
-- under each of its three messages it needs every pixel of this. Appearance,
-- which carries the menu's arrangement too, ends near -452.
local WIDTH, HEIGHT = 640, 576
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
    { key = "announce", label = "Announcements", icon = "Interface\\Icons\\Spell_Arcane_PortalStormWind" },
    { key = "appearance", label = "Appearance", icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02" },
}

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true, PRINTSCREEN = true,
}

local frame
local pages, navButtons = {}, {}
local refreshers = {}
local Refresh            -- defined below; the panel's own redraw
local builders = {}
local capture

-- The parts of the preparation check, and what each one counts. The General
-- page and the greeting both offer them, each in its own order and wording.
local PREP_WHAT = {
    water = "conjured water", food = "conjured food", gem = "a mana gem",
    intellect = "how much of your group carries Arcane Intellect",
    runeT = "Rune of Teleportation", runeP = "Rune of Portals", powder = "Arcane Powder",
}
local PREP_GENERAL = {
    { "water", "Water" }, { "food", "Food" }, { "gem", "Mana Gem" }, { "intellect", "Intellect" },
    { "runeT", "Rune T" }, { "runeP", "Rune P" }, { "powder", "Arcane" },
}

local function PrepTip(key)
    return "Count " .. PREP_WHAT[key]
        .. " in the preparation check. Anything you are not high enough to use stays out of it either way."
end

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


--- The arrangement and the button shape, which the Appearance page and the
--- Menu Layout page both offer. One get/set pair for both, in the spirit of
--- AutoTradeField above, so the two controls cannot drift apart.
---
--- The section fired is "radial", not "layout", whichever page the control is
--- on. Radial:Apply only rebuilds the menu for nil, "all", "general" or
--- "radial", so a "layout" event would be heard by nothing and changing the
--- arrangement would appear to do nothing at all.
local function RadialField(key)
    return Field("radial", function() return MB.db.radial end, key)
end

--- The arrangements, in the order Layout.lua lists them.
local function PresetOptions()
    local out = {}
    for i = 1, #MB.Layout.PRESETS do
        out[i] = { MB.Layout.PRESETS[i][1], MB.Layout.PRESETS[i][2] }
    end
    return out
end

local SHAPE_OPTIONS = { { "round", "Round" }, { "square", "Square" } }

local ARRANGEMENT_HELP = "How the buttons sit around the orb. Classic Radial is the original circle and is unaffected by the sizes on the Menu Layout page."
local SHAPE_HELP = "Round or square buttons. The orb takes the same shape, so the launcher matches what it opens. Classic Radial is always round."
--- Automatic trade filling, which both the Trading page and the greeting
--- switch on and off. Switching it on gives a trade window that is already
--- open another go, so ticking it mid-trade is not a dead click.
local function AutoTradeField()
    return function()
        return MB.db.trade.enabled
    end, function(value)
        MB.db.trade.enabled = value
        if value then MB.Trade:RetryAutomatic() end
        Changed("trade")
    end
end

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------
--- `maxWidth` is for a label that sits beside a control: it holds the text to
--- that width and stops it wrapping, so a long one is cut short instead of
--- running under whatever is next to it.
local function Label(parent, x, y, text, size, colorName, maxWidth)
    local label = Theme:Text(parent, size or 11)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    if colorName then
        label:SetTextColor(Theme:Color(colorName))
    end
    if maxWidth then
        label:SetWidth(maxWidth)
        label:SetWordWrap(false)
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

    local function RefreshValue()
        check:SetChecked(get() and true or false)
    end
    refreshers[#refreshers + 1] = RefreshValue
    check.Refresh = RefreshValue   -- the greeting reuses its own widgets' refreshers
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

    local function RefreshValue()
        if not box:HasFocus() then
            box:SetText(tostring(get()))
        end
    end
    refreshers[#refreshers + 1] = RefreshValue
    box.Refresh = RefreshValue   -- the greeting reuses its own widgets' refreshers
    return box
end

--- A one-line text field. The text is saved when the field is left; while it
--- is being typed, `onTyping` hears what is in it so far.
local function TextBox(page, x, y, width, title, tooltip, maxLetters, onTyping, get, set)
    local box = CreateFrame("EditBox", nil, page, "BackdropTemplate")
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", x, y)
    Theme:SkinBox(box, "panel")
    box:SetFontObject(GameFontHighlightSmall)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    box:SetTextInsets(6, 6, 0, 0)

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(get() or "")
        if onTyping then onTyping(get() or "") end
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        local value = self:GetText() or ""
        if value ~= get() then
            set(value)
        end
    end)
    if onTyping then
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then onTyping(self:GetText() or "") end
        end)
    end
    Theme:AttachTooltip(box, title, tooltip)

    refreshers[#refreshers + 1] = function()
        if not box:HasFocus() then
            box:SetText(get() or "")
            box:SetCursorPosition(0)   -- show the start of a long text, not its end
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

-------------------------------------------------------------------------------
-- Dropdowns
--
-- These used to be click-cycles: one button that stepped to the next choice
-- each time it was pressed. That is fine for two options and poor for eleven,
-- where the only way to see what is on offer is to click through the lot and
-- the only way back is to go all the way round.
--
-- Its replacement keeps the same signature, so a control is a dropdown or a
-- cycle by one word at the call site and nothing else changes.
--
-- Only one list is open at a time. It is parented to the settings window
-- rather than to the page, so it can hang past the page's edge, and it comes
-- with a catcher behind it covering the whole window, which closes it on a
-- click anywhere else. Both are plain frames in the settings window, which is
-- never secure, so none of this is protected and no part of it waits for
-- combat.
-------------------------------------------------------------------------------
local openList    -- the list showing now, if any

local ROW_H = 18

--- The window a control sits in, which is where its list belongs.
local function Host(widget)
    local parent = widget:GetParent()
    while parent and parent ~= UIParent do
        widget = parent
        parent = widget:GetParent()
    end
    return widget
end

local function CloseDropdown()
    if openList then
        openList:Hide()
        openList = nil
    end
end

local function Dropdown(page, x, y, width, title, tooltip, options, get, set)
    local button = Theme:CreateButton(page, "", width, 20)
    button:SetPoint("TOPLEFT", x, y)

    -- The value sits left, the arrow right, so a long label does not run over
    -- the arrow and the arrow does not wander with the text length.
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 7, 0)
    button.label:SetPoint("RIGHT", -18, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)

    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(MB.MEDIA .. "Chevron.tga")
    arrow:SetSize(8, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    Theme:UseAccent(arrow, "SetVertexColor", 0.9)

    --- Writes the current choice on the button.
    local function Show()
        local current = get()
        local text = options[1] and options[1][2] or ""
        for i = 1, #options do
            if options[i][1] == current then text = options[i][2] end
        end
        button.label:SetText(text)
    end

    local list, rows, host

    --- Builds the list the first time it is wanted. Kept afterwards: a page
    --- refresh must not create frames, and nor must opening a list twice.
    local function Build()
        -- Parented to whichever window the control is in, not to the settings
        -- window: the greeting has one of these too, and a list parented to a
        -- window that is not open would never be seen.
        host = Host(button)
        list = CreateFrame("Frame", nil, host)
        list:SetSize(math.max(width, 80), #options * ROW_H + 8)
        Theme:CreatePanel(nil, list, "raised"):SetAllPoints()
        -- No strata of its own: a frame inherits its parent, so the list
        -- stays with whatever window it belongs to and the frame level above
        -- puts it over the page. Setting one here would have to be kept in
        -- step with the window by hand.

        list:SetFrameLevel(host:GetFrameLevel() + 20)
        list:Hide()

        -- Behind the list and in front of everything else: a click anywhere
        -- but on the list closes it.
        local catcher = CreateFrame("Button", nil, list)
        catcher:SetPoint("CENTER", host, "CENTER")
        catcher:SetSize(2048, 2048)
        catcher:SetFrameLevel(list:GetFrameLevel() - 1)
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseDropdown)

        rows = {}
        for i = 1, #options do
            local row = CreateFrame("Button", nil, list)
            row:SetSize(list:GetWidth() - 8, ROW_H)
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
            row:SetFrameLevel(list:GetFrameLevel() + 1)

            row.text = Theme:Text(row, 11)
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetPoint("RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.text:SetText(options[i][2])

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetTexture(MB.MEDIA .. "Circle.tga")
            highlight:SetAllPoints()
            Theme:UseAccent(highlight, "SetVertexColor", 0.2)

            -- A tick beside whichever one is in force, so the list says what
            -- is set as well as what is available.
            row.mark = Theme:Text(row, 11)
            row.mark:SetPoint("RIGHT", -4, 0)
            Theme:UseAccent(row.mark, "SetTextColor", 1)

            -- What this row stands for, so the list can be driven by value
            -- rather than by counting clicks the way a cycle had to be.
            row.value = options[i][1]
            row:SetScript("OnClick", function()
                CloseDropdown()
                set(options[i][1])
                Show()   -- at once: the page's refreshers only run while the panel is open
            end)
            rows[i] = row
        end
        list.rows = rows
        button.list = list
    end

    button:SetScript("OnClick", function(self)
        if openList == list and list and list:IsShown() then
            CloseDropdown()
            return
        end
        CloseDropdown()
        if not list then Build() end

        local current = get()
        for i = 1, #rows do
            rows[i].mark:SetText(options[i][1] == current and "*" or "")
            rows[i].text:SetText(options[i][2])
        end

        -- Opens downwards, or upwards where the window has no room below.
        -- Measured rather than assumed: the longest list here is the eleven
        -- arrangements, and where that control ends up on the page decides
        -- which way it has to go.
        list:ClearAllPoints()
        local below = self:GetBottom() and host:GetBottom()
            and (self:GetBottom() - host:GetBottom()) or 0
        if below >= list:GetHeight() then
            list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        else
            list:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
        end
        list:Show()
        openList = list
    end)

    Theme:AttachTooltip(button, title, tooltip)
    refreshers[#refreshers + 1] = Show
    button.Refresh = Show
    button.CloseList = CloseDropdown
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

-- A keybinding row: a name, then the key button to its right. The name is
-- held to its own width and does not wrap, so a long one is cut short rather
-- than running under the button beside it.
local KEY_COLUMN, KEY_GAP, KEY_WIDTH = 212, 116, 92

local function KeybindRow(page, x, y, binding)
    local name = Label(page, x, y - 4, binding.label, 11)
    name:SetWidth(KEY_GAP - 8)
    name:SetWordWrap(false)
    local button = Theme:CreateButton(page, "", KEY_WIDTH, 20)
    button:SetPoint("TOPLEFT", x + KEY_GAP, y)
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
    Theme:AttachTooltip(button, binding.label,
        (binding.hint and (binding.hint .. " ") or "")
        .. "Click, then press a key (modifiers allowed). Right-click to clear. Escape cancels.")
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
    Checkbox(page, 0, -52, "Lock positions", "Prevents the orb and MageButler's panels from being dragged.",
        Field("general", general, "lockPositions"))
    Checkbox(page, COLUMN, -52, "Repeat notifications in chat", "Also prints MageButler's on-screen notifications to the chat frame.",
        Field("general", general, "chatMessages"))
    Checkbox(page, COLUMN, -76, "Clickable status dots on the orb",
        "The two small dots on the orb's right edge: the upper one shows Buff Watch, the lower one the preparation check. Ticked, clicking the upper dot opens the Buff Watch player list and the lower dot the preparation checklist. Unticked, they only show their colour and a click on them counts as a click on the orb, so neither can be opened by accident.",
        Field("appearance", function() return MB.db.appearance end, "pipClicks"))

    Slider(page, 0, -84, 200, "UI scale", "Scales the orb and the radial menu.", 0.6, 1.6, 0.05,
        function(value) return math.floor(value * 100 + 0.5) .. "%" end,
        Field("general", general, "uiScale"))
    PanelButton(page, COLUMN, -102, "Reset positions", 130, "Moves the orb and MageButler's panels back to their default places.", function()
        MB.Config:ResetPositions()
        Changed("all")
    end)

    Header(page, -136, "Preparation Check")
    Checkbox(page, 0, -164, "Show the preparation indicator",
        "A small pip on the orb: green when you carry enough water, food, a mana gem and reagents. Click the pip for the checklist.",
        Field("readiness", readiness, "enabled"))
    Checkbox(page, 0, -188, "Report on ready checks", "Shows the preparation result whenever a ready check starts.",
        Field("readiness", readiness, "onReadyCheck"))
    Checkbox(page, COLUMN, -188, "Warn when entering instances", "Shows what is missing when you walk into a dungeon or raid short of supplies.",
        Field("readiness", readiness, "onInstance"))

    Label(page, 0, -216, "Count towards ready", 10, "dim")
    local function prepItems() return MB.db.readiness.items end
    for i = 1, #PREP_GENERAL do
        local key, label = PREP_GENERAL[i][1], PREP_GENERAL[i][2]
        local column = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        Checkbox(page, column * 108, -234 - row * 24, label, PrepTip(key),
            Field("readiness", prepItems, key))
    end

    Header(page, -292, "Character Profile")
    local profileText = Label(page, 0, -318, "", 11, "dim")

    local selected
    local picker = PanelButton(page, 0, -340, "", 190, "Click to choose which character to copy from.", function(self)
        local list = MB.Config:GetOtherProfiles()
        if #list == 0 then return end
        local index = 1
        for i = 1, #list do
            if list[i] == selected then index = i % #list + 1 end
        end
        selected = list[index]
        self.label:SetText(selected)
    end)
    local copy = PanelButton(page, 198, -340, "Copy settings", 110, "Replaces this character's settings with the selected character's.", function()
        if selected and MB.Config:CopyFrom(selected) then
            MB:Print("settings copied from " .. selected .. ".")
        end
    end)
    PanelButton(page, 316, -340, "Reset defaults", 110, "Restores every MageButler setting for this character.", function()
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

    Label(page, 0, -404, "MageButler v" .. MB.version .. "  |cff8f9fc9by " .. MB.author .. "|r", 12)
    -- Set apart from the lines around it, since the client has no italic.
    Theme:Fancy(Label(page, 0, -422, "Credit to Ski Infinite and Keen Mage for their help.", 10, "dim"), 13)
    Label(page, 0, -438, "Your personal Mage assistant for WoW Forever.  /mb for commands.", 10, "dim")
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

    Checkbox(page, 0, -78, "Menu animations", "A short fade when the menu opens, and a soft glow on a button as it is clicked.",
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
        KeybindRow(page, column * KEY_COLUMN, -250 - row * 26, bindings[i])
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
        "A pip on the orb: green when everyone is buffed, yellow when buffs are expiring or a stronger rank could be given, red when players are missing Intellect, grey when there is nothing to watch.",
        Field("buffwatch", watch, "orbIndicator"))
    Checkbox(page, 0, -52, "Watch in parties", "Monitor party members.", Field("buffwatch", watch, "party"))
    Checkbox(page, RIGHT, -52, "Watch in raids", "Monitor every raid member, up to 40 players.", Field("buffwatch", watch, "raid"))
    Checkbox(page, 0, -76, "Watch while solo", "When you are not grouped, right-clicking the orb buffs you.", Field("buffwatch", watch, "solo"))

    Header(page, -106, "Buff Selection")
    Label(page, 0, -138, "Party threshold", 12, nil, 124)
    NumberBox(page, 130, -134, 44, "Party threshold",
        "In a party, use Arcane Brilliance once this many players need Intellect. Below that, players are buffed one at a time.", 1, 5,
        Field("buffwatch", watch, "partyThreshold"))
    Label(page, RIGHT, -138, "Raid threshold", 12, nil, 124)
    NumberBox(page, RIGHT + 130, -134, 44, "Raid threshold",
        "In a raid, use Arcane Brilliance once this many players need Intellect. Below that, players are buffed one at a time.", 1, 40,
        Field("buffwatch", watch, "raidThreshold"))
    Checkbox(page, 0, -162, "Prefer Arcane Brilliance", "Use Arcane Brilliance when the threshold is reached, it is learned and you carry Arcane Powder.",
        Field("buffwatch", watch, "preferBrilliance"))
    Checkbox(page, RIGHT, -162, "Fall back to Arcane Intellect", "Without Arcane Powder, buff players one at a time instead of doing nothing.",
        Field("buffwatch", watch, "fallbackIntellect"))
    Checkbox(page, 0, -186, "Upgrade weaker ranks",
        "Counts a player carrying a weaker rank of Intellect than you could give them as needing a rebuff, as when a lower-level Mage has buffed the group. Turn this off to treat any rank as good enough.",
        Field("buffwatch", watch, "upgradeWeaker"))
    Checkbox(page, 0, -210, "Match the player's level",
        "Buffs a low-level player with the strongest rank their level can receive, instead of your own best rank, which the game would refuse. Turn this off to always cast your highest rank.",
        Field("buffwatch", watch, "matchLevel"))
    Label(page, RIGHT, -190, "Brilliance covers", 12, nil, 104)
    Dropdown(page, RIGHT + 110, -186, 104, "Arcane Brilliance covers",
        "Whether one cast reaches the target's group or the whole raid. Automatic reads the spell's own description.",
        { { "auto", "Automatic" }, { "group", "Target's group" }, { "raid", "Whole raid" } },
        Field("buffwatch", watch, "scope"))

    Header(page, -240, "Duration and Targets")
    Checkbox(page, 0, -268, "Watch for expiring buffs", "Count a buff that is about to run out as needing a rebuff.",
        Field("buffwatch", watch, "watchExpiry"))
    Label(page, RIGHT, -272, "Rebuff at (minutes)", 12, nil, 124)
    NumberBox(page, RIGHT + 130, -268, 44, "Rebuff threshold", "A buff with less than this many minutes left counts as expiring. Longer buffs are left alone.", 1, 30,
        Field("buffwatch", watch, "rebuffMinutes"))
    Checkbox(page, 0, -292, "Ignore offline players", "Players who are disconnected are not counted.", Field("buffwatch", watch, "ignoreOffline"))
    Checkbox(page, RIGHT, -292, "Ignore dead players", "Dead players and ghosts are not counted.", Field("buffwatch", watch, "ignoreDead"))
    Checkbox(page, 0, -316, "Skip unavailable players", "Players in another zone or too far away to be seen are not counted.",
        Field("buffwatch", watch, "skipUnavailable"))
    Checkbox(page, RIGHT, -316, "Missing before expiring", "Buff players with no Intellect at all before refreshing buffs that are running out.",
        Field("buffwatch", watch, "missingFirst"))
    Checkbox(page, 0, -340, "Mana users only", "Leave Warriors and Rogues out of the count: Intellect does nothing for a class with no mana.", Field("buffwatch", watch, "manaUsersOnly"))

    Header(page, -370, "Display")
    Checkbox(page, 0, -398, "Orb warning colours", "Tints the orb's ring yellow or red while buffs need attention.",
        Field("buffwatch", watch, "orbColors"))
    Checkbox(page, RIGHT, -398, "Coverage counter", "Shows group coverage such as 32/40 above the orb.",
        Field("buffwatch", watch, "showCounter"))
    Checkbox(page, 0, -422, "Names in tooltip", "Lists the players who need a buff in the orb's tooltip.",
        Field("buffwatch", watch, "tooltipNames"))
    Label(page, RIGHT, -426, "Notifications", 12, nil, 104)
    Dropdown(page, RIGHT + 110, -422, 104, "Buff Watch notifications",
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
            "Track and restock this reagent. It is left alone until you are high enough and have learned a spell that uses it.",
            Field("reagents", item, "enabled"))
        -- The longest name plus its reason would otherwise run under the
        -- Target box, so the label is held inside its own column.
        check.text:SetWidth(columns[2] - 33)
        check.text:SetWordWrap(false)
        refreshers[#refreshers + 1] = function()
            -- Say why a reagent is being left alone, rather than silently
            -- doing nothing on a Mage who is not high enough yet.
            local name = Reagents:Name(key)
            local reason = Reagents:InactiveReason(key)
            if reason == "talent" then
                name = name .. "  |cff8f9fc9(not needed)|r"
            elseif reason == "level" then
                name = name .. "  |cff8f9fc9(lvl " .. Reagents:MinLevel(key) .. ")|r"
            elseif reason == "spell" then
                name = name .. "  |cff8f9fc9(unlearned)|r"
            end
            check.text:SetText(name)
            -- The clickable area follows the drawn label, never past it.
            check:SetHitRectInsets(0, -(math.min(check.text:GetStringWidth(), check.text:GetWidth()) + 8), 0, 0)
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

    Note(page, -184, "Rune of Teleportation is used from level 20, Rune of Portals from 40 and Arcane Powder from 56; until then they are left alone. Purchases never go past the target, your free bag space, your gold or the spending limit. Reagents already in your bags are counted first.")
end

builders.conjuring = function(page)
    local function conjuring() return MB.db.conjuring end

    Header(page, 0, "Conjuring")
    Label(page, 0, -34, "Water to carry", 12, nil, 114)
    NumberBox(page, 120, -30, 52, "Water target", "Counted in items (20 is one full stack). Used by the preparation check. 0 turns tracking off.", 0, 400,
        Field("conjuring", conjuring, "waterTarget"))
    Label(page, COLUMN, -34, "Food to carry", 12, nil, 114)
    NumberBox(page, COLUMN + 120, -30, 52, "Food target", "Counted in items (20 is one full stack). 0 turns tracking off.", 0, 400,
        Field("conjuring", conjuring, "foodTarget"))

    Checkbox(page, 0, -64, "Keep a mana gem ready", "Counts a missing mana gem as unprepared.",
        Field("conjuring", conjuring, "wantGem"))
    Checkbox(page, COLUMN, -64, "Warn when supplies run out", "A short notification the moment your last conjured water or food is gone.",
        Field("conjuring", conjuring, "warnMissing"))

    Note(page, -94, "The radial buttons cast the highest rank you have learned, unless you have right-clicked one to step down a rank. The Mana Gem button conjures the strongest gem you are not carrying; right-click uses your best gem. MageButler never casts on its own.")
end

builders.trading = function(page)
    local function trade() return MB.db.trade end

    Header(page, 0, "Trade Assistant")
    Checkbox(page, 0, -28, "Fill trades automatically",
        "When a trade window opens, offers conjured water and food for the matching preset. Hold Shift as the trade opens to skip it once.",
        AutoTradeField())
    Checkbox(page, COLUMN, -28, "Show Fill Trade button", "Adds a Fill Trade button above the trade window for filling by hand.",
        Field("trade", trade, "showFillButton"))
    Checkbox(page, COLUMN, -52, "Hold Shift to skip a trade",
        "While you hold Shift as a trade window opens, nothing is offered automatically. The Fill Trade button still works, since clicking it is asking for it.",
        Field("trade", trade, "shiftSkips"))
    Checkbox(page, 0, -52, "Match the player's level",
        "Offers the best rank the other player is high enough to eat or drink. Ranks above their level are left in your bags.",
        Field("trade", trade, "usableOnly"))

    -- One table of plain numbers per class; the selector picks whose table
    -- is shown: party members, raid members or everyone else.
    local selected = "party"
    local boxes = {}
    Label(page, 0, -90, "Amounts for", 12, nil, 86)
    Dropdown(page, 92, -86, 130, "Amounts for",
        "Which set of numbers the table below shows and edits. Each kind of trade partner has its own.",
        { { "party", "Party members" }, { "raid", "Raid members" }, { "other", "Other players" } },
        function() return selected end,
        function(value)
            -- A number still being typed belongs to the table it was typed
            -- under: it is taken now, before the selection moves on.
            for i = 1, #boxes do
                local box = boxes[i]
                if box and box.HasFocus and box:HasFocus() then box:ClearFocus() end
            end
            selected = value
            -- Which table is on screen is this panel's own business: nothing
            -- in the saved settings changed, so nobody else is told.
            Refresh() -- redraws the table for the new selection
        end)
    PanelButton(page, 232, -86, "Standard numbers", 130,
        "Puts every number in all three tables back to MageButler's standard amounts.", function()
            MB.Config:ResetTradeAmounts()
        end)

    local classColors = _G.RAID_CLASS_COLORS
    local classes = MB.Config.CLASSES
    local perColumn = math.ceil(#classes / 2)
    for column = 0, 1 do
        local x = column * 222
        Label(page, x, -118, "Class", 10, "dim")
        Label(page, x + 96, -118, "Water", 10, "dim")
        Label(page, x + 146, -118, "Food", 10, "dim")
    end
    for i, class in ipairs(classes) do
        local column = (i > perColumn) and 1 or 0
        local x = column * 222
        local y = -136 - ((i - 1) % perColumn) * 24
        local function row() return MB.db.trade.amounts[selected][class] end
        local name = MB.Trade:ClassName(class)

        local label = Label(page, x, y - 4, name, 12, nil, 88)
        local colour = classColors and classColors[class]
        if colour and colour.r then
            label:SetTextColor(colour.r, colour.g, colour.b)
        end
        boxes[#boxes + 1] = NumberBox(page, x + 96, y, 44, name .. ": water",
            "Items of conjured water to offer a " .. name .. " (20 is one full stack). 0 offers none.", 0, 120,
            Field("trade", row, "water"))
        boxes[#boxes + 1] = NumberBox(page, x + 146, y, 44, name .. ": food",
            "Items of conjured food to offer a " .. name .. " (20 is one full stack). 0 offers none.", 0, 120,
            Field("trade", row, "food"))
    end

    local status = Label(page, 0, -264, "", 11)
    status:SetWidth(PAGE_WIDTH)
    status:SetWordWrap(true)
    refreshers[#refreshers + 1] = function()
        if MB.Trade:IsAutoBlocked() then
            status:SetText("|cffffbf40This client refused automatic filling, so it is paused. The Fill Trade button still works. Tick the box above to try again.|r")
        else
            status:SetText("")
        end
    end

    Note(page, -304, "Numbers are items, not stacks. Only the strongest rank you carry is handed over, so older leftovers stay in your bags. Only conjured water and food are ever offered, only into empty trade slots, and only once per trade. MageButler never accepts a trade for you. A trade window has six slots, so at most six stacks fit.")
end

builders.announce = function(page)
    local Announce = MB.Announce
    local function announce() return MB.db.announce end

    --- get/set for one of the messages.
    local function Message(key)
        return function()
            return MB.db.announce[key]
        end, function(value)
            Announce:SetMessage(key, value)
        end
    end

    --- The line showing what would actually be said. It follows the typing.
    --- `lines` is how many it is given room for; a message long enough to
    --- wrap needs two.
    local function Preview(y, kind, lines)
        Label(page, 0, y, "Preview", 10, "dim")
        local text = Label(page, 0, y - 15, "", 11)
        text:SetSize(PAGE_WIDTH, (lines or 2) * 16)
        text:SetJustifyV("TOP")
        text:SetWordWrap(true)
        text:SetSpacing(2)
        refreshers[#refreshers + 1] = function()
            text:SetText(Announce:Preview(kind))
        end
        return function(typed)
            text:SetText(Announce:Preview(kind, typed))
        end
    end

    Header(page, 0, "Portal Announcements")
    Checkbox(page, 0, -28, "Announce my portals",
        "Says in chat that your portal is open. A portal that is interrupted or cancelled is never announced, and one cast is announced once.",
        Field("announce", announce, "enabled"))
    --- The channel for one of the two places, with a word on how it is said there.
    local HOW_X = 222   -- just past the cycle button, which ends at 210
    local function Channel(y, key, where, how)
        Label(page, 0, y - 4, "Announce in", 12, nil, 86)
        Dropdown(page, 92, y, 118, "Announce in",
            "Where your portal is announced " .. where .. ". Party and raid chat only reach your group, and nothing is said when the channel would reach nobody.",
            Announce.CHANNELS, Field("announce", announce, key))
        -- Held inside the page: uncapped, this ran past the right edge.
        Label(page, HOW_X, y - 5, how, 10, "dim", PAGE_WIDTH - HOW_X)
    end

    -- Where the game lets an addon speak unprompted: said as the portal opens.
    Header(page, -58, "In Dungeons and Raids")
    Channel(-82, "channelInstance", "inside a dungeon or raid", "by itself, as the portal opens")
    local showPortal = Preview(-134, "portal")
    TextBox(page, 0, -108, PAGE_WIDTH, "Message when the portal opens",
        "What is said once your portal is open. {portal} becomes the destination, {player} your name and {spell} the spell's full name. Empty the box to get the standard text back.",
        200, showPortal, Message("text"))

    -- Where /say and /yell need the player's own click.
    Header(page, -188, "Out in the World")
    Channel(-212, "channelWorld", "out in the world", "/say and /yell need your click")
    Checkbox(page, 0, -238, "Announce as I start casting",
        "Ticked, it is said as you click the destination in MageButler's menu, before the cast has finished, in the words below. Nothing is said if the spell is on cooldown or you are moving. Unticked, a button appears when the portal opens and your click on it sends the message above. A portal cast any other way always gets the button.",
        Field("announce", announce, "atStart"))
    local showStart = Preview(-288, "start", 1)
    TextBox(page, 0, -262, PAGE_WIDTH, "Message as the cast starts",
        "What is said at that click, for a portal. The same placeholders work here.",
        200, showStart, Message("startText"))

    Header(page, -326, "Your Own Teleports")
    Checkbox(page, 0, -352, "Announce my own teleports too",
        "Also says so when you teleport yourself, in the words below, wherever you are. Off, only portals are announced.",
        Field("announce", announce, "teleports"))
    local showTeleport = Preview(-404, "teleport")
    TextBox(page, 0, -378, PAGE_WIDTH, "Teleport message",
        "What is said when you teleport yourself, if that is switched on. The same placeholders work here.",
        200, showTeleport, Message("teleportText"))

    Note(page, -458, "{portal} is the destination, {player} is you, {spell} the spell's full name. A message is cut at 255 characters.")
end

-- Appearance, which carries the menu's arrangement as well.
--
-- The arrangement and its sizes were a page of their own for a day. They are
-- here because this is the page a player opens to change what MageButler
-- looks like, and the shape of the menu is the largest part of that; two
-- pages meant choosing between them first.
--
-- It ends near -452 of the page's 504. A preview of the arrangement sat
-- under that for a day and was taken out: drawn at a fifth of its size it
-- said little the names did not, and it cost the whole window 104 pixels of
-- height to carry.
--
-- Everything in the layout half is stored under `radial` and fires
-- Changed("radial"). Radial:Apply only rebuilds the menu for nil, "all",
-- "general" or "radial", so a section of its own would fire an event nothing
-- acts on and changing the arrangement would appear to do nothing at all.
builders.appearance = function(page)
    local function appearance() return MB.db.appearance end
    local function whole(value) return tostring(math.floor(value + 0.5)) end

    Header(page, 0, "Appearance")
    Label(page, 0, -34, "Accent colour", 12, nil, 114)
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

    Slider(page, 0, -66, 200, "Panel opacity", "Background opacity of the submenus and this panel.", 0.5, 1, 0.05,
        function(value) return math.floor(value * 100 + 0.5) .. "%" end,
        Field("appearance", appearance, "panelAlpha"))

    Checkbox(page, 0, -112, "Orb glow", "A soft halo behind the orb while something needs your attention: players to buff, or supplies running short. Dark when all is well.",
        Field("appearance", appearance, "glow"))
    Checkbox(page, COLUMN, -112, "Status animations",
        "The status pips on the orb pulse while something needs attention, and the orb's halo and ripple move with them. Steady when all is well.",
        Field("appearance", appearance, "statusAnimations"))

    -- One choice moves the whole addon between layers of the interface.
    -- The names are the game's own, tidied: a player reaching for this
    -- setting is one who already knows what a frame strata is.
    local function Pretty(name)
        local text = name:gsub("_", " "):lower()
        return text:sub(1, 1):upper() .. text:sub(2)
    end
    local strataOptions = {}
    for i = 1, #Theme.STRATA do
        local name = Theme.STRATA[i]
        strataOptions[i] = { name, name == "MEDIUM" and "Medium (default)" or Pretty(name) }
    end

    Label(page, 0, -148, "UI Strata", 12, nil, 114)
    Dropdown(page, 120, -144, 150, "UI Strata",
        "Which layer of the interface the orb draws on. Raise it to keep the orb above other addons, lower it to tuck it behind them. The orb and its menu sit at the layer you pick, with the submenus, panels and the toast just above. This window and the welcome screen are not affected: they stay on their own layer so they are never buried under the orb they are setting up.",
        strataOptions,
        Field("appearance", appearance, "strata"))

    Header(page, -186, "Menu Layout")

    Label(page, 0, -220, "Arrangement", 12, nil, 114)
    Dropdown(page, 120, -216, 170, "Arrangement", ARRANGEMENT_HELP,
        PresetOptions(), RadialField("preset"))

    Label(page, 0, -250, "Button shape", 12, nil, 114)
    Dropdown(page, 120, -246, 110, "Button shape", SHAPE_HELP,
        SHAPE_OPTIONS, RadialField("buttonShape"))

    Label(page, 0, -280, "Opens towards", 12, nil, 114)
    Dropdown(page, 120, -276, 110, "Opens towards",
        "Which way a toolbar or side panel runs from the orb. Arrangements that sit around the orb ignore this.",
        { { "down", "Down" }, { "up", "Up" }, { "right", "Right" }, { "left", "Left" } },
        RadialField("direction"))

    Slider(page, 0, -312, 200, "Gap across", "Space between buttons side to side. On the arrangements that sit around the orb it widens the ring across.", 0, 40, 1, whole,
        RadialField("gapX"))
    Slider(page, COLUMN, -312, 200, "Gap down", "Space between rows. On the arrangements that sit around the orb it widens the ring downwards, so the two together can make it oval.", 0, 40, 1, whole,
        RadialField("gapY"))
    Slider(page, 0, -358, 200, "Grid columns", "How many across the Compact Grid uses.", 1, 6, 1, whole,
        RadialField("columns"))

    Note(page, -404, "Classic Radial keeps its own radius and button size on the Radial Menu page, and stays round whatever shape is set here. The other arrangements take the button size from that page and the gaps from this one; a single row or column has only the one gap to give. Near a screen edge an arrangement is mirrored onto whichever side has room.")
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
Refresh = function()
    if not frame or not frame:IsShown() then return end
    for i = 1, #refreshers do
        refreshers[i]()
    end
end

local function SelectPage(key)
    StopCapture()
    CloseDropdown()   -- a list left open over a page that is no longer shown
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
    Theme:FixStrata(frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        StopCapture()
        CloseDropdown()
    end)
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

-------------------------------------------------------------------------------
-- First run: a short greeting, once per character
-------------------------------------------------------------------------------
local welcome
local welcomeChecks = {}
local WELCOME_HEIGHT = 608

-- The greeting's own grid, so everything in it stands on the same few edges:
-- two columns, an indent for whatever sits under a heading, and one right
-- edge that the number boxes and the channel buttons all end on.
local INDENT = 12               -- items under a heading
local COLUMN_TWO = 180          -- where the right-hand column's items begin
local BOX = 40                  -- width of a number box
local CHANNEL = 130             -- width of a channel button
local RIGHT_EDGE = 382          -- where the right-hand column ends
local COLUMN_ONE_EDGE = COLUMN_TWO - 16   -- and where the left-hand one does

local function readinessDB() return MB.db.readiness end
local function prepDB() return MB.db.readiness.items end

-- The preparation check's parts, in the order they are laid out: two columns,
-- conjured supplies down the left, reagents down the right.
-- The same parts in the greeting, in its own order and with room for the
-- reagents' full names.
local WELCOME_PREP = {
    { "water", "Water" }, { "runeT", "Rune of Teleportation" },
    { "food", "Food" }, { "runeP", "Rune of Portals" },
    { "gem", "Mana Gem" }, { "powder", "Arcane Powder" },
    { "intellect", "Intellect" },
}

--- A checkbox on the greeting. The settings panel's own refresh stops early
--- while that panel is closed, so these keep their own list and are brought
--- up to date whenever the greeting is shown.
local function WelcomeCheck(parent, x, y, text, tooltip, get, set)
    local check = Checkbox(parent, x, y, text, tooltip, get, set)
    welcomeChecks[#welcomeChecks + 1] = check.Refresh
    return check
end

local function RefreshWelcome()
    for i = 1, #welcomeChecks do
        welcomeChecks[i]()
    end
end

local function CreateWelcome()
    welcome = Theme:CreatePanel("MageButlerWelcome", UIParent, "bg")
    welcome:SetSize(416, WELCOME_HEIGHT)
    welcome:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    Theme:FixStrata(welcome)
    welcome:SetClampedToScreen(true)
    welcome:SetMovable(true)
    welcome:EnableMouse(true)
    welcome:RegisterForDrag("LeftButton")
    welcome:SetScript("OnDragStart", welcome.StartMoving)
    welcome:SetScript("OnDragStop", welcome.StopMovingOrSizing)
    welcome:Hide()
    tinsert(UISpecialFrames, "MageButlerWelcome")

    -- However it is closed, it has been seen.
    welcome:SetScript("OnHide", function()
        if MB.db then MB.db.general.welcomed = true end
    end)

    local icon = welcome:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", 16, -14)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_MagicalSentry")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = Theme:Text(welcome, 15)
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText("Welcome to MageButler")
    Theme:UseAccent(title, "SetTextColor", 1)

    local intro = Theme:Text(welcome, 12)
    intro:SetPoint("TOPLEFT", 16, -54)
    intro:SetWidth(384)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetSpacing(3)
    intro:SetText("Your orb is on screen now, a little to the right of the middle. Drag it wherever suits you.")

    local clicks = Theme:Text(welcome, 12)
    clicks:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
    clicks:SetWidth(378)
    clicks:SetJustifyH("LEFT")
    clicks:SetSpacing(5)
    local accent = Theme:AccentHex()
    clicks:SetText(
        accent .. "Left-click|r  the radial menu\n" ..
        accent .. "Right-click|r  cast the buff your group needs\n" ..
        accent .. "Shift + right-click|r  these settings\n" ..
        accent .. "Right-click water or food|r  cycle to an older rank\n" ..
        accent .. "Shift as a trade opens|r  no water or food is given")

    local closing = Theme:Text(welcome, 11)
    closing:SetPoint("TOPLEFT", clicks, "BOTTOMLEFT", 0, -14)
    closing:SetWidth(384)
    closing:SetJustifyH("LEFT")
    closing:SetWordWrap(true)
    closing:SetSpacing(3)
    closing:SetTextColor(Theme:Color("dim"))
    closing:SetText("Out of the box it restocks your reagents at vendors and keeps an eye on your group's Intellect. A trade is filled with the rank of food and water the other player is high enough to eat and drink, and reagents stay untouched until you are high enough to use them.")

    ---------------------------------------------------------------------------
    -- The choices, under the greeting rather than behind a second page.
    ---------------------------------------------------------------------------
    local checks = {}

    local choices = CreateFrame("Frame", nil, welcome)
    choices:SetPoint("TOPLEFT", closing, "BOTTOMLEFT", 0, -16)
    choices:SetPoint("RIGHT", welcome, "RIGHT", -16, 0)
    choices:SetHeight(320)

    checks.prep = WelcomeCheck(choices, 0, 0, "Preparation check",
        "Answers whether you are stocked before a dungeon or raid.",
        Field("readiness", readinessDB, "enabled"))

    -- Beside it, since both are about the orb's own small indicators.
    checks.pipClicks = WelcomeCheck(choices, COLUMN_TWO - 12, 0, "Clickable status dots",
        "The two small dots on the orb's right edge: the upper one shows Buff Watch, the lower one the preparation check. Ticked, clicking them opens the Buff Watch player list and the preparation checklist. Unticked, they only show their colour and a click on them counts as a click on the orb, so neither can be opened by accident. Also under General in the settings.",
        Field("appearance", function() return MB.db.appearance end, "pipClicks"))

    -- The third of the big switches, and the one a new Mage is most likely
    -- to want a say over before the first trade window opens.
    checks.autoTrade = WelcomeCheck(choices, 0, -24, "Fill trades automatically",
        "When a trade window opens, offers conjured water and food for whoever you are trading: how much, by their class, is set under Settings, Trading. Hold Shift as the window opens to skip it that once.",
        AutoTradeField())

    local counts = Theme:Text(choices, 10)
    counts:SetPoint("TOPLEFT", 0, -52)
    counts:SetJustifyH("LEFT")
    counts:SetTextColor(Theme:Color("dim"))
    counts:SetText("What counts as prepared, and how much is enough")

    for i = 1, #WELCOME_PREP do
        local key, label = WELCOME_PREP[i][1], WELCOME_PREP[i][2]
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        checks[key] = WelcomeCheck(choices, INDENT + column * (COLUMN_TWO - INDENT), -70 - row * 24,
            label, PrepTip(key), Field("readiness", prepDB, key))
    end

    -- How much water and food is enough, beside their ticks: below this the
    -- orb calls for attention. The same numbers as on the Conjuring page.
    local function conjuringDB() return MB.db.conjuring end
    local amounts = {}
    local function Amount(key, row, field, name)
        local get, set = Field("conjuring", conjuringDB, field)
        local box = NumberBox(choices, COLUMN_ONE_EDGE - BOX, -69 - row * 24, BOX, name .. " to carry",
            "How many " .. name:lower() .. " you want on you (20 is one full stack). Below this the orb turns yellow and starts to pulse; with none left it turns red. Untick " .. name .. " to leave it out altogether.",
            0, 400, get, set)
        welcomeChecks[#welcomeChecks + 1] = box.Refresh
        amounts[key] = box
    end
    Amount("water", 0, "waterTarget", "Water")
    Amount("food", 1, "foodTarget", "Food")

    -- The reagents, down the right-hand column: how few is too few. The same
    -- numbers as "Warn at" on the Reagents page.
    for row, key in ipairs(MB.Reagents.ORDER) do
        local function item() return MB.db.reagents.items[key] end
        local get, set = Field("reagents", item, "warn")
        local name = MB.Reagents:Name(key)
        local box = NumberBox(choices, RIGHT_EDGE - BOX, -69 - (row - 1) * 24, BOX, name .. ": warn at",
            "With this many " .. name .. " or fewer the orb turns yellow and starts to pulse; with none left it turns red. How many to restock up to is set on the Reagents page.",
            0, 200, get, set)
        welcomeChecks[#welcomeChecks + 1] = box.Refresh
        amounts[key] = box
    end
    welcome.amounts = amounts

    -- Portal announcements: whether, where, and whether /say is made at the
    -- click. The wording itself is written on the Announcements page.
    local function announceDB() return MB.db.announce end
    local announcing = Theme:Text(choices, 10)
    announcing:SetPoint("TOPLEFT", 0, -170)
    announcing:SetJustifyH("LEFT")
    announcing:SetTextColor(Theme:Color("dim"))
    announcing:SetText("Announcing your portals")

    checks.announce = WelcomeCheck(choices, INDENT, -188, "Announce my portals",
        "Says in chat that your portal is open. What it says is yours to write, under Settings, Announcements.",
        Field("announce", announceDB, "enabled"))

    -- The two places it can happen, under their own headings, each with the
    -- channel it is said in there.
    local channels = MB.Announce.CHANNELS
    local function Heading(y, text)
        local label = Theme:Text(choices, 10)
        label:SetPoint("TOPLEFT", 0, y)
        label:SetJustifyH("LEFT")
        label:SetTextColor(Theme:Color("dim"))
        label:SetText(text)
        return label
    end
    local function ChannelButton(y, key, where)
        local get, set = Field("announce", announceDB, key)
        local button = Dropdown(choices, RIGHT_EDGE - CHANNEL, y, CHANNEL, "Announce in",
            "Where your portal is announced " .. where .. ". Party and raid chat only reach your group.",
            channels, get, set)
        welcomeChecks[#welcomeChecks + 1] = button.Refresh
        return button
    end

    -- One block per place: its heading with the channel beside it, and a
    -- line underneath saying how the announcement is made there.
    local function Where(y, heading, note, key, which)
        Heading(y, heading)
        local line = Theme:Text(choices, 11)
        line:SetPoint("TOPLEFT", INDENT, y - 18)
        line:SetJustifyH("LEFT")
        line:SetTextColor(Theme:Color("dim"))
        line:SetText(note)
        return ChannelButton(y - 2, key, which)
    end

    welcome.channelInstance = Where(-216, "In dungeons and raids",
        "Said by itself as the portal opens.", "channelInstance", "inside a dungeon or raid")
    welcome.channelWorld = Where(-262, "Out in the world",
        "/say and /yell need a click of your own.", "channelWorld", "out in the world")

    checks.atStart = WelcomeCheck(choices, INDENT, -300, "Announce as I start casting",
        "Out in the world the game only lets an addon speak in /say or /yell at your own click. Ticked, it is said as you click the destination in MageButler's menu. Unticked, a button appears when the portal opens, for you to click.",
        Field("announce", announceDB, "atStart"))

    welcome.checks = checks

    -- Sized from its own text, so a larger font or a longer line cannot push
    -- the choices down over the buttons. It never shrinks below the designed
    -- height, and the gaps below are the ones used above: 12, 14 and 16.
    welcome.Resize = function()
        local text = (intro:GetStringHeight() or 0)
            + (clicks:GetStringHeight() or 0)
            + (closing:GetStringHeight() or 0)
        welcome:SetHeight(math.max(WELCOME_HEIGHT, 54 + text + 42 + 320 + 44))
    end

    local open = Theme:CreateButton(welcome, "Open settings", 120, 24)
    open:SetPoint("BOTTOMRIGHT", -16, 14)
    open:SetScript("OnClick", function()
        welcome:Hide()
        Settings:Open("general")
    end)

    local later = Theme:CreateButton(welcome, "Got it", 90, 24)
    later:SetPoint("RIGHT", open, "LEFT", -8, 0)
    later:SetScript("OnClick", function()
        welcome:Hide()
    end)

    Settings.welcome = welcome
end

--- The first-run greeting. Shows itself once per character; `/mb welcome`
--- brings it back.
function Settings:ShowWelcome()
    if not MB.ready then return end
    if not welcome then CreateWelcome() end
    welcome.Resize()
    RefreshWelcome()
    welcome:Show()
end

function Settings:MaybeWelcome()
    if MB.db.general.welcomed then return end
    -- A few seconds in, so it does not land during the loading screen.
    C_Timer.After(4, function()
        if MB.ready and not MB.db.general.welcomed then
            Settings:ShowWelcome()
        end
    end)
end

-------------------------------------------------------------------------------
-- A shortcut in the game's own Options -> AddOns list
-------------------------------------------------------------------------------
--- Nothing of MageButler's is drawn in Blizzard's options window: every
--- setting lives in MageButler's own, so opening the entry there closes that
--- window and opens this one. The page keeps a button as well, for the case
--- where the game will not let its window be closed from here, in combat
--- above all.
local function RegisterGameOptions()
    local panel = CreateFrame("Frame")
    panel.name = "MageButler"

    local text = Theme:Text(panel, 13)
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetWidth(420)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText("MageButler keeps its settings in a window of its own, which opens as you come here. "
        .. "Type /mb to open it at any time.")

    local button = Theme:CreateButton(panel, "Open MageButler", 160, 24)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    button:SetScript("OnClick", function()
        Settings:Open()
    end)

    panel:SetScript("OnShow", function()
        -- A frame later: the options window is still laying itself out, and
        -- closing a window in the middle of its own show is asking for it.
        C_Timer.After(0, function()
            local options = _G.SettingsPanel
            if options and options:IsShown() and not InCombatLockdown() then
                if _G.HideUIPanel then _G.HideUIPanel(options) else options:Hide() end
            end
            Settings:Open()
        end)
    end)

    local api = _G.Settings   -- the game's own, not this module
    if api and api.RegisterCanvasLayoutCategory and api.RegisterAddOnCategory then
        local category = api.RegisterCanvasLayoutCategory(panel, "MageButler")
        category.ID = "MageButler"
        api.RegisterAddOnCategory(category)
    elseif _G.InterfaceOptions_AddCategory then
        _G.InterfaceOptions_AddCategory(panel)
    end
end

function Settings:OnEnable()
    Theme = MB.Theme
    MB:On("SETTINGS_CHANGED", Refresh)
    MB:On("SPELLS_UPDATED", Refresh)
    RegisterGameOptions()
end
