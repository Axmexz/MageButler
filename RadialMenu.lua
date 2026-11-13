-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: the orb, the radial menu and the portal / teleport submenus.
--
-- Everything that casts is a SecureActionButton the player clicks. The orb and
-- the two category buttons are secure handlers, so the menu and its submenus
-- open and close correctly in combat. Attributes, sizes and anchors of the
-- protected frames are only ever changed outside combat lockdown.

local _, MB = ...
local Radial = MB:NewModule("RadialMenu")
local API = MB.API
local Theme, Spells, Conjuring, Reagents

local ORDER = { "portals", "teleports", "water", "food", "gem", "trade" }
local LABELS = {
    portals = "Portals",
    teleports = "Teleports",
    water = "Water",
    food = "Food",
    gem = "Mana Gem",
    trade = "Trade",
}
local SUB_REAGENT = { portals = "runeP", teleports = "runeT" }
local FALLBACK_ICON = {
    portals = "Interface\\Icons\\Spell_Arcane_PortalStormWind",
    teleports = "Interface\\Icons\\Spell_Arcane_TeleportStormWind",
    trade = "Interface\\Icons\\INV_Misc_Bag_10",
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ORB_ICON = "Interface\\Icons\\Spell_Holy_MagicalSentry"

local ORB_SIZE = 46
local ROW_WIDTH, ROW_HEIGHT = 150, 24
local SUB_PAD, SUB_HEADER = 8, 30

-- Keybind actions -> the button a key press clicks.
Radial.BINDINGS = {
    { key = "toggle", label = "Toggle radial menu", button = "MageButlerOrb", click = "LeftButton" },
    { key = "water", label = "Conjure Water", button = "MageButlerButton_water", click = "LeftButton" },
    { key = "food", label = "Conjure Food", button = "MageButlerButton_food", click = "LeftButton" },
    { key = "gem", label = "Conjure Mana Gem", button = "MageButlerButton_gem", click = "LeftButton" },
    { key = "useGem", label = "Use Mana Gem", button = "MageButlerButton_gem", click = "RightButton" },
}

local orb, menu
local buttons = {}
local subs = {}

-------------------------------------------------------------------------------
-- Orb
-------------------------------------------------------------------------------
local function OrbTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = Theme:Accent()
    GameTooltip:AddLine("MageButler", r, g, b)
    GameTooltip:AddLine("Left-click: radial menu", 0.88, 0.92, 1)
    if MB.db.buffwatch.enabled then
        GameTooltip:AddLine("Right-click: cast the recommended buff", 0.88, 0.92, 1)
        GameTooltip:AddLine("Ctrl+right-click: Buff Watch player list", 0.88, 0.92, 1)
    end
    GameTooltip:AddLine("Shift+right-click: settings", 0.88, 0.92, 1)
    GameTooltip:AddLine("Middle-click: preparation check", 0.88, 0.92, 1)
    if not MB.db.general.lockPositions then
        GameTooltip:AddLine("Drag: move", 0.56, 0.63, 0.79)
    end
    if MB.BuffWatch and MB.BuffWatch.AddTooltipLines then
        MB.BuffWatch:AddTooltipLines(GameTooltip)
    end
    if MB.Readiness and MB.Readiness.AddTooltipLines then
        MB.Readiness:AddTooltipLines(GameTooltip)
    end
    GameTooltip:Show()
end

local function CreateOrb()
    -- A secure action button (the right-click casts Buff Watch's spell) that can
    -- also run restricted snippets (the left-click opens the menu in combat).
    orb = CreateFrame("Button", "MageButlerOrb", UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    orb:SetSize(ORB_SIZE, ORB_SIZE)
    orb:SetFrameStrata("MEDIUM")
    orb:SetClampedToScreen(true)
    orb:SetMovable(true)
    orb:RegisterForClicks("AnyUp", "AnyDown")
    orb:SetAttribute("useOnKeyDown", false) -- always act on release, whatever the CVar says
    orb:RegisterForDrag("LeftButton")

    orb.halo = orb:CreateTexture(nil, "BACKGROUND", nil, -1)
    orb.halo:SetTexture(MB.MEDIA .. "Glow.tga")
    orb.halo:SetBlendMode("ADD")
    orb.halo:SetPoint("TOPLEFT", -10, 10)
    orb.halo:SetPoint("BOTTOMRIGHT", 10, -10)
    Theme:UseAccent(orb.halo, "SetVertexColor", 0.35)

    orb.core = orb:CreateTexture(nil, "BACKGROUND", nil, 1)
    orb.core:SetTexture(MB.MEDIA .. "Orb.tga")
    orb.core:SetAllPoints()

    orb.icon = orb:CreateTexture(nil, "ARTWORK")
    orb.icon:SetTexture(ORB_ICON)
    orb.icon:SetPoint("TOPLEFT", 8, -8)
    orb.icon:SetPoint("BOTTOMRIGHT", -8, 8)
    orb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if orb.CreateMaskTexture then
        local mask = orb:CreateMaskTexture()
        mask:SetTexture(MB.MEDIA .. "Circle.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(orb.icon)
        orb.icon:AddMaskTexture(mask)
    end

    orb.ring = orb:CreateTexture(nil, "OVERLAY")
    orb.ring:SetTexture(MB.MEDIA .. "Ring.tga")
    orb.ring:SetPoint("TOPLEFT", -1, 1)
    orb.ring:SetPoint("BOTTOMRIGHT", 1, -1)
    Theme:UseAccent(orb.ring, "SetVertexColor", 1)

    orb.hover = orb:CreateTexture(nil, "HIGHLIGHT")
    orb.hover:SetTexture(MB.MEDIA .. "Glow.tga")
    orb.hover:SetBlendMode("ADD")
    orb.hover:SetPoint("TOPLEFT", -12, 12)
    orb.hover:SetPoint("BOTTOMRIGHT", 12, -12)
    Theme:UseAccent(orb.hover, "SetVertexColor", 0.5)

    orb:SetScript("OnDragStart", function(self)
        if MB.db.general.lockPositions or InCombatLockdown() then return end
        self.dragging = true
        -- Tells the click snippet that the release ending this drag is not a click.
        self:SetAttribute("mbdragging", true)
        self:StartMoving()
    end)
    orb:SetScript("OnDragStop", function(self)
        Radial:StopDrag()
    end)
    -- Both click phases arrive here; the press prepares, the release acts.
    orb:SetScript("PreClick", function(_, button, down)
        if button == "RightButton" and down and not IsShiftKeyDown() and not IsControlKeyDown() then
            MB.BuffWatch:PrepareClick()
        end
    end)
    orb:SetScript("PostClick", function(_, button, down)
        if down then return end
        if button == "RightButton" then
            if IsShiftKeyDown() then
                MB.Settings:Toggle()
            elseif not IsControlKeyDown() then
                MB.BuffWatch:AfterClick()
            end
        elseif button == "MiddleButton" then
            MB.Readiness:TogglePanel()
        end
    end)
    Theme:RoundTooltip(orb, OrbTooltip)

    Radial.orb = orb
end

--- Ends an orb drag and stores the position as an offset from screen centre.
function Radial:StopDrag()
    if not orb.dragging then return end
    orb.dragging = nil
    orb:StopMovingOrSizing()

    local cx, cy = orb:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and ux then
        local scale = orb:GetScale()
        MB.db.orb.x = cx * scale - ux
        MB.db.orb.y = cy * scale - uy
    end
    MB:AfterCombat("radial-layout", function()
        Radial:ApplyPosition()
        Radial:Layout()
    end)
    -- If no click followed the drag, drop the marker shortly afterwards.
    C_Timer.After(0.1, function()
        MB:AfterCombat("orb-drag-marker", function()
            orb:SetAttribute("mbdragging", nil)
        end)
    end)
end

function Radial:ApplyPosition()
    local scale = orb:GetScale()
    if not scale or scale <= 0 then scale = 1 end
    orb:ClearAllPoints()
    orb:SetPoint("CENTER", UIParent, "CENTER", MB.db.orb.x / scale, MB.db.orb.y / scale)
end

-------------------------------------------------------------------------------
-- Menu frame and round buttons
-------------------------------------------------------------------------------
local function CreateMenu()
    menu = CreateFrame("Frame", "MageButlerMenu", UIParent, "SecureHandlerBaseTemplate")
    menu:SetFrameStrata("MEDIUM")
    menu:SetPoint("CENTER", orb, "CENTER")
    menu:SetSize(200, 200)
    menu:Hide()

    menu.orbit = menu:CreateTexture(nil, "BACKGROUND")
    menu.orbit:SetTexture(MB.MEDIA .. "RingThin.tga")
    menu.orbit:SetPoint("CENTER")
    local r, g, b = Theme:Color("border")
    menu.orbit:SetVertexColor(r, g, b, 0.75)

    menu.fade = menu:CreateAnimationGroup()
    local alpha = menu.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.14)
    menu:HookScript("OnShow", function(self)
        if MB.db.radial.animations then
            self.fade:Stop()
            self.fade:Play()
        end
        Radial:RefreshVisuals()
    end)

    Radial.menu = menu
end

local ButtonTooltip

local function CreateRoundButton(key, template)
    local button = CreateFrame("Button", "MageButlerButton_" .. key, menu, template)
    button.key = key
    button:SetSize(40, 40)
    Theme:SkinRound(button)

    button.label = Theme:Text(button, 10, "OVERLAY", "OUTLINE")
    button.label:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button.label:SetText(LABELS[key])

    button.count = Theme:Text(button, 11, "OVERLAY", "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", 3, -1)

    button:HookScript("OnEnter", function(self)
        ButtonTooltip(self)
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- Both click phases arrive here; light up on the one that acts.
    button:HookScript("PostClick", function(self, _, down)
        if not down then
            Theme:Flash(self.flash, self.ring, Radial.RestoreRings)
        end
    end)

    buttons[key] = button
    return button
end

--- Puts the rings back to the colour the current state calls for, after a
--- click flash has brightened one. The state may have changed during it: the
--- click that opened a submenu turns its button's ring gold.
function Radial.RestoreRings()
    Radial:RefreshVisuals()
end

--- Visual state: available buttons are bright, unavailable ones are greyed.
local function SetButtonState(button, available, selected)
    button.available = available
    button.icon:SetDesaturated(not available)
    button.icon:SetAlpha(available and 1 or 0.4)
    if selected then
        button.ring:SetVertexColor(Theme:Color("gold"))
    elseif available then
        button.ring:SetVertexColor(Theme:Accent())
    else
        button.ring:SetVertexColor(Theme:Color("off"))
    end
    local r, g, b = Theme:Color(available and "text" or "off")
    button.label:SetTextColor(r, g, b)
end

local function SetCount(button, value, state)
    if value and MB.db.radial.showCounts then
        button.count:SetText(value)
        button.count:SetTextColor(Theme:StateColor(state))
        button.count:Show()
    else
        button.count:Hide()
    end
end

-------------------------------------------------------------------------------
-- Submenus
-------------------------------------------------------------------------------
local function CreateRow(sub, index)
    local row = CreateFrame("Button", sub:GetName() .. "Row" .. index, sub, "SecureActionButtonTemplate")
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetFrameLevel(sub:GetFrameLevel() + 3)
    row:RegisterForClicks("AnyUp", "AnyDown")
    row:SetAttribute("useOnKeyDown", false) -- always act on release, whatever the CVar says
    row:SetAttribute("type", "spell")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.text = Theme:Text(row, 12)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    Theme:UseAccent(highlight, "SetVertexColor", 0.2)

    row:HookScript("OnEnter", function(self)
        if not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row:SetScript("PostClick", function(_, _, down)
        -- The cast happens on release; close the menu after it when allowed.
        if down or not MB.db.radial.closeAfterTravel or InCombatLockdown() then return end
        menu:Hide()
    end)

    sub.rows[index] = row
    return row
end

local function CreateSub(key)
    local sub = CreateFrame("Frame", "MageButlerSub_" .. key, menu, "SecureHandlerBaseTemplate")
    sub.key = key
    sub.rows = {}
    sub:SetFrameStrata("HIGH")
    sub:SetClampedToScreen(true)
    sub:SetSize(ROW_WIDTH + SUB_PAD * 2, 80)
    sub:Hide()

    sub.panel = Theme:CreatePanel(nil, sub, "bg")
    sub.panel:SetAllPoints()
    sub.panel:SetFrameLevel(sub:GetFrameLevel() + 1)

    sub.title = Theme:Text(sub.panel, 12)
    sub.title:SetPoint("TOPLEFT", 12, -10)
    sub.title:SetText(LABELS[key])
    Theme:UseAccent(sub.title, "SetTextColor", 1)

    sub.reagent = Theme:Text(sub.panel, 10)
    sub.reagent:SetPoint("TOPRIGHT", -12, -11)

    sub.empty = Theme:Text(sub.panel, 11)
    sub.empty:SetPoint("TOPLEFT", 12, -(SUB_HEADER + 4))
    sub.empty:SetText("None learned yet")
    sub.empty:SetTextColor(Theme:Color("off"))

    local function Changed()
        Radial:RefreshVisuals()
    end
    sub:HookScript("OnShow", Changed)
    sub:HookScript("OnHide", Changed)

    subs[key] = sub
    return sub
end

--- Rebuilds one submenu from the learned spells. Out of combat only.
local function BuildSub(key)
    local sub = subs[key]
    local list = (key == "portals") and Spells:GetPortals() or Spells:GetTeleports()

    for i = 1, #list do
        local spell = list[i]
        local row = sub.rows[i] or CreateRow(sub, i)
        row.spellID = spell.id
        row:SetAttribute("spell", spell.id)
        row.icon:SetTexture(spell.icon or QUESTION)
        row.text:SetText(spell.short)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sub, "TOPLEFT", SUB_PAD, -(SUB_HEADER + (i - 1) * ROW_HEIGHT))
        row:Show()
    end
    for i = #list + 1, #sub.rows do
        local row = sub.rows[i]
        row.spellID = nil
        row:SetAttribute("spell", nil)
        row:Hide()
    end

    sub.empty:SetShown(#list == 0)
    sub:SetSize(ROW_WIDTH + SUB_PAD * 2, SUB_HEADER + math.max(1, #list) * ROW_HEIGHT + SUB_PAD)
end

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------
local function AddHint(text)
    GameTooltip:AddLine(text, 0.56, 0.63, 0.79, true)
end

ButtonTooltip = function(button)
    local key = button.key
    local r, g, b = Theme:Accent()
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    if key == "water" or key == "food" then
        local spellID = Conjuring:GetSpell(key)
        if spellID then
            GameTooltip:SetSpellByID(spellID)
        else
            GameTooltip:AddLine("Conjure " .. LABELS[key], r, g, b)
            GameTooltip:AddLine("Not learned yet.", 1, 0.35, 0.35)
        end
        local target = Conjuring:Target(key)
        local have = Conjuring:Count(key)
        GameTooltip:AddLine(" ")
        if target > 0 then
            GameTooltip:AddLine("In bags: " .. have .. " / " .. target, 0.88, 0.92, 1)
        else
            GameTooltip:AddLine("In bags: " .. have, 0.88, 0.92, 1)
        end
        if key == "food" and Spells:GetBest("ritual") then
            AddHint("Right-click: Ritual of Refreshment")
        end
    elseif key == "gem" then
        local spellID, allHeld = Conjuring:GetGemCast()
        if spellID then
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:AddLine(" ")
            if allHeld then
                GameTooltip:AddLine("You already hold every gem you can conjure.", 0.35, 0.9, 0.55, true)
            end
        else
            GameTooltip:AddLine("Conjure Mana Gem", r, g, b)
            GameTooltip:AddLine("Not learned yet.", 1, 0.35, 0.35)
        end
        local item = Conjuring:GetGemItem()
        if item then
            AddHint("Right-click: use " .. (API.ItemName(item) or "your mana gem"))
        end
    elseif key == "portals" or key == "teleports" then
        local list = (key == "portals") and Spells:GetPortals() or Spells:GetTeleports()
        local reagent = SUB_REAGENT[key]
        GameTooltip:AddLine(LABELS[key], r, g, b)
        if #list == 0 then
            GameTooltip:AddLine("None learned yet.", 1, 0.35, 0.35)
        else
            GameTooltip:AddLine(#list .. (#list == 1 and " destination" or " destinations"), 0.88, 0.92, 1)
            local cr, cg, cb = Theme:StateColor(Reagents:Count(reagent) > 0 and "ok" or "none")
            GameTooltip:AddLine(Reagents:Name(reagent) .. ": " .. Reagents:Count(reagent), cr, cg, cb)
            AddHint("Click to choose a destination")
        end
    elseif key == "trade" then
        GameTooltip:AddLine("Trade assistant", r, g, b)
        if MB.Trade:IsOpen() then
            GameTooltip:AddLine(MB.Trade:DescribePreset(), 0.88, 0.92, 1)
            AddHint("Left-click: fill the trade window")
        else
            AddHint("Left-click: trade with your target")
        end
        local auto
        if MB.Trade:IsAutoBlocked() then
            auto = "|cffffbf40not allowed by this client|r"
        elseif MB.db.trade.enabled then
            auto = "|cff59e68con|r"
        else
            auto = "|cff8f9fc9off|r"
        end
        GameTooltip:AddLine("Automatic filling: " .. auto, 0.88, 0.92, 1)
        AddHint("Right-click: turn automatic filling on or off")
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
--- Icons, counts and state colours. Safe at any time, including in combat.
function Radial:RefreshVisuals()
    if not menu then return end

    for _, kind in ipairs({ "water", "food" }) do
        local button = buttons[kind]
        button.icon:SetTexture(Conjuring:Icon(kind))
        SetButtonState(button, Conjuring:GetSpell(kind) ~= nil)
        local state = Conjuring:State(kind)
        SetCount(button, Conjuring:Count(kind), state == "off" and "ok" or state)
    end

    local gem = buttons.gem
    gem.icon:SetTexture(Conjuring:Icon("gem"))
    SetButtonState(gem, Conjuring:GetGemCast() ~= nil)
    local gemCount = Conjuring:Count("gem")
    SetCount(gem, gemCount, gemCount > 0 and "ok" or "none")

    for key, reagent in pairs(SUB_REAGENT) do
        local button = buttons[key]
        local sub = subs[key]
        local list = (key == "portals") and Spells:GetPortals() or Spells:GetTeleports()
        button.icon:SetTexture((list[1] and list[1].icon) or FALLBACK_ICON[key])
        SetButtonState(button, #list > 0, sub:IsShown())

        local have = Reagents:Count(reagent)
        local state = have > 0 and "ok" or "none"
        if #list > 0 then
            SetCount(button, have, state)
            sub.reagent:SetText(Reagents.SHORT[reagent] .. "  " .. have)
            sub.reagent:SetTextColor(Theme:StateColor(state))
        else
            SetCount(button, nil)
            sub.reagent:SetText("")
        end
        -- A destination cannot be cast without its rune: dim the list.
        for i = 1, #sub.rows do
            local row = sub.rows[i]
            row.icon:SetDesaturated(have <= 0)
            row.text:SetTextColor(Theme:Color(have > 0 and "text" or "off"))
        end
    end

    local trade = buttons.trade
    trade.icon:SetTexture(FALLBACK_ICON.trade)
    SetButtonState(trade, true, MB.Trade:IsOpen())
    SetCount(trade, nil)
end

--- Secure attributes for the conjure buttons. Out of combat only.
--- The "*" prefix makes each one apply whatever modifier keys are held; a
--- plain "type1" would be skipped by a keybind such as ALT-W, because the
--- client then looks for "alt-type1" and "*type1" only.
local function RefreshAttributes()
    local water = buttons.water
    local waterSpell = Conjuring:GetSpell("water")
    water:SetAttribute("*type1", waterSpell and "spell" or nil)
    water:SetAttribute("*spell1", waterSpell)

    local food = buttons.food
    local foodSpell = Conjuring:GetSpell("food")
    local ritual = Spells:GetBest("ritual")
    food:SetAttribute("*type1", foodSpell and "spell" or nil)
    food:SetAttribute("*spell1", foodSpell)
    food:SetAttribute("*type2", ritual and "spell" or nil)
    food:SetAttribute("*spell2", ritual)

    local gem = buttons.gem
    local gemSpell = Conjuring:GetGemCast()
    local gemItem = Conjuring:GetGemItem()
    gem:SetAttribute("*type1", gemSpell and "spell" or nil)
    gem:SetAttribute("*spell1", gemSpell)
    gem:SetAttribute("*type2", gemItem and "item" or nil)
    gem:SetAttribute("*item2", gemItem and ("item:" .. gemItem) or nil)
end

-- Where the open side is, for each combination of blocked edges. The key is
-- "<horizontal>,<vertical>", where 1 means the low edge (left, bottom) is in
-- the way and -1 the high one; the value is the angle pointing away from them.
local OPEN_TOWARDS = {
    ["1,0"] = 0, ["-1,0"] = 180, ["0,1"] = 90, ["0,-1"] = 270,
    ["1,1"] = 45, ["1,-1"] = 315, ["-1,1"] = 135, ["-1,-1"] = 225,
}

--- Where the buttons will fit: the middle of the arc and how wide it is, in
--- degrees. A span of 360 is the whole circle. Near a screen edge part of the
--- circle is off screen, so the buttons move to whichever side has room.
local function ArcFor(radius, size)
    local cx, cy = orb:GetCenter()
    if not cx then return 90, 360 end
    local scale = orb:GetScale()
    if not scale or scale <= 0 then scale = 1 end

    -- Room a button needs from the orb's centre, in screen units.
    local need = (radius + size / 2 + 6) * scale
    local left, bottom = cx * scale, cy * scale
    local right = UIParent:GetWidth() - left
    local top = UIParent:GetHeight() - bottom

    local dx = (left < need and 1 or 0) - (right < need and 1 or 0)
    local dy = (bottom < need and 1 or 0) - (top < need and 1 or 0)
    local towards = OPEN_TOWARDS[dx .. "," .. dy]
    if not towards then return 90, 360 end -- room all round, or nowhere to go
    return towards, 180
end

--- Positions the buttons and the submenus beside them. Out of combat only.
function Radial:Layout()
    local db = MB.db.radial
    local size, radius = db.buttonSize, db.radius

    local visible = {}
    for _, key in ipairs(ORDER) do
        local button = buttons[key]
        if db.buttons[key] then
            visible[#visible + 1] = button
        else
            button:Hide()
        end
    end

    local centre, span = ArcFor(radius, size)
    self.arcCentre, self.arcSpan = centre, span

    local count = #visible
    for i = 1, count do
        local button = visible[i]
        local degrees
        if span >= 360 then
            degrees = 90 - (i - 1) * 360 / count   -- from the top, clockwise
        elseif count == 1 then
            degrees = centre
        else
            degrees = centre + span / 2 - (i - 1) * span / (count - 1)
        end
        local angle = math.rad(degrees)
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("CENTER", menu, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
        button.label:SetShown(db.showLabels)
        button:Show()
    end

    local extent = (radius + size) * 2
    menu:SetSize(extent, extent)
    -- The hairline ring sits at 124/128 of the texture's half-width. It only
    -- makes sense while the buttons really do sit on a full circle.
    menu.orbit:SetSize(radius * 2 * 128 / 124, radius * 2 * 128 / 124)
    menu.orbit:SetShown(count > 0 and span >= 360)

    -- Submenus open towards the middle of the screen.
    local openRight = true
    local cx = orb:GetCenter()
    if cx then
        openRight = cx * orb:GetScale() < UIParent:GetWidth() * 0.6
    end
    local offset = radius + size / 2 + 16
    for _, sub in pairs(subs) do
        sub:ClearAllPoints()
        if openRight then
            sub:SetPoint("LEFT", menu, "CENTER", offset, 0)
        else
            sub:SetPoint("RIGHT", menu, "CENTER", -offset, 0)
        end
    end
end

function Radial:ApplyBindings()
    ClearOverrideBindings(orb)
    if not MB.db.general.enabled then return end
    for i = 1, #self.BINDINGS do
        local binding = self.BINDINGS[i]
        local key = MB.db.keybinds[binding.key]
        if type(key) == "string" and key ~= "" then
            SetOverrideBindingClick(orb, false, key, binding.button, binding.click)
        end
    end
end

--- Applies every setting. Protected changes wait for combat to end.
function Radial:Apply()
    MB:AfterCombat("radial-apply", function()
        local general = MB.db.general
        orb:SetScale(general.uiScale)
        menu:SetScale(general.uiScale)
        Radial:ApplyPosition()
        orb:SetShown(general.enabled and general.showOrb)
        if not general.enabled then
            menu:Hide()
        end
        BuildSub("portals")
        BuildSub("teleports")
        Radial:Layout()
        RefreshAttributes()
        Radial:ApplyBindings()
    end)
    orb.halo:SetShown(MB.db.appearance.glow)
    self:RefreshVisuals()
end

--- Slash-command toggle. In combat only the orb (a secure click) can do this.
function Radial:Toggle()
    if not MB.db.general.enabled then return end
    if InCombatLockdown() then
        MB:Print("in combat the radial menu can only be opened by clicking the orb or its keybind.")
        return
    end
    if menu:IsShown() then
        menu:Hide()
    else
        subs.portals:Hide()
        subs.teleports:Hide()
        menu:Show()
    end
end

-------------------------------------------------------------------------------
function Radial:OnEnable()
    Theme, Spells, Conjuring, Reagents = MB.Theme, MB.Spells, MB.Conjuring, MB.Reagents

    CreateOrb()
    CreateMenu()

    -- Category buttons toggle their submenu from the restricted environment.
    local portals = CreateRoundButton("portals", "SecureHandlerClickTemplate")
    local teleports = CreateRoundButton("teleports", "SecureHandlerClickTemplate")
    CreateSub("portals")
    CreateSub("teleports")

    local toggleSnippet = [=[
        local mine = self:GetFrameRef("mine")
        local other = self:GetFrameRef("other")
        if other then other:Hide() end
        if mine:IsShown() then mine:Hide() else mine:Show() end
    ]=]
    portals:RegisterForClicks("LeftButtonUp")
    portals:SetFrameRef("mine", subs.portals)
    portals:SetFrameRef("other", subs.teleports)
    portals:SetAttribute("_onclick", toggleSnippet)
    teleports:RegisterForClicks("LeftButtonUp")
    teleports:SetFrameRef("mine", subs.teleports)
    teleports:SetFrameRef("other", subs.portals)
    teleports:SetAttribute("_onclick", toggleSnippet)

    -- Conjure buttons: plain secure spell / item clicks.
    for _, key in ipairs({ "water", "food", "gem" }) do
        local button = CreateRoundButton(key, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("useOnKeyDown", false)
    end

    -- Trade button: no protected action involved.
    local trade = CreateRoundButton("trade")
    trade:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    trade:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            MB.db.trade.enabled = not MB.db.trade.enabled
            if MB.db.trade.enabled then
                MB.Trade:RetryAutomatic()
            end
            MB:Fire("SETTINGS_CHANGED", "trade")
            MB:Notify("Automatic trade filling " .. (MB.db.trade.enabled and "enabled." or "disabled."), "info")
            if GameTooltip:IsOwned(self) then ButtonTooltip(self) end
        else
            MB.Trade:Fill(true)
        end
    end)

    -- The orb opens and closes the menu from the restricted environment.
    orb:SetFrameRef("menu", menu)
    orb:SetFrameRef("subportals", subs.portals)
    orb:SetFrameRef("subteleports", subs.teleports)
    -- Runs before the orb's own secure click. Returning false stops that click,
    -- so only a plain right-click reaches the buff action.
    orb:WrapScript(orb, "OnClick", [=[
        if button == "LeftButton" then
            if not down then
                if self:GetAttribute("mbdragging") then
                    self:SetAttribute("mbdragging", nil)
                else
                    local menu = self:GetFrameRef("menu")
                    if menu:IsShown() then
                        menu:Hide()
                    else
                        self:GetFrameRef("subportals"):Hide()
                        self:GetFrameRef("subteleports"):Hide()
                        menu:Show()
                    end
                end
            end
            return false
        end
        if button == "RightButton" then
            if IsShiftKeyDown() then
                return false
            end
            if IsControlKeyDown() then
                if not down then
                    local list = self:GetFrameRef("bufflist")
                    if list then
                        if list:IsShown() then list:Hide() else list:Show() end
                    end
                end
                return false
            end
            return
        end
        return false
    ]=])

    MB:On("SETTINGS_CHANGED", function()
        Radial:Apply()
    end)
    MB:On("SPELLS_UPDATED", function()
        Radial:Apply()
    end)
    MB:On("INVENTORY_UPDATED", function()
        Radial:RefreshVisuals()
        MB:AfterCombat("radial-attributes", RefreshAttributes)
    end)

    -- Entering combat mid-drag: drop the orb while that is still permitted.
    MB:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        Radial:StopDrag()
    end)

    -- A different resolution or UI scale moves the screen edges.
    local function Relayout()
        MB:AfterCombat("radial-layout", function()
            Radial:ApplyPosition()
            Radial:Layout()
        end)
    end
    MB:RegisterEvent("DISPLAY_SIZE_CHANGED", Relayout)
    MB:RegisterEvent("UI_SCALE_CHANGED", Relayout)
    MB:RegisterEvent("TRADE_SHOW", function()
        Radial:RefreshVisuals()
    end)
    MB:RegisterEvent("TRADE_CLOSED", function()
        Radial:RefreshVisuals()
    end)
end
