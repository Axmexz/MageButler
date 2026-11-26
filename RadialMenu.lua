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
local CONJURED = { "water", "food" }
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
-- `label` is read in the settings panel, where it shares a narrow row with the
-- key button, so each one is kept short; `hint` says the rest in the tooltip.
Radial.BINDINGS = {
    { key = "toggle", label = "Radial menu", hint = "Opens and closes the radial menu.",
      button = "MageButlerOrb", click = "LeftButton" },
    { key = "water", label = "Conjure Water", hint = "Casts the rank of Conjure Water the button is set to.",
      button = "MageButlerButton_water", click = "LeftButton" },
    { key = "food", label = "Conjure Food", hint = "Casts the rank of Conjure Food the button is set to.",
      button = "MageButlerButton_food", click = "LeftButton" },
    { key = "gem", label = "Conjure Gem", hint = "Conjures the strongest mana gem you are not carrying.",
      button = "MageButlerButton_gem", click = "LeftButton" },
    { key = "useGem", label = "Use Gem", hint = "Uses the best mana gem in your bags.",
      button = "MageButlerButton_gem", click = "RightButton" },
}

local orb, menu
local buttons = {}
local subs = {}

-------------------------------------------------------------------------------
-- Orb
-------------------------------------------------------------------------------
local function OrbTooltip(self)
    MB:RefreshInventory(false, "tooltip")   -- the preparation lines below are counts
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = Theme:Accent()
    GameTooltip:AddLine("MageButler", r, g, b)
    Theme:TipLine(GameTooltip, "Left-click: radial menu", "text")
    if MB.db.buffwatch.enabled then
        Theme:TipLine(GameTooltip, "Right-click: cast the recommended buff", "text")
        Theme:TipLine(GameTooltip, "Ctrl+right-click: Buff Watch player list", "text")
    end
    Theme:TipLine(GameTooltip, "Shift+right-click: settings", "text")
    Theme:TipLine(GameTooltip, "Middle-click: preparation check", "text")
    if not MB.db.general.lockPositions then
        Theme:TipLine(GameTooltip, "Drag: move", "dim")
    end
    -- Only worth saying while the trade assistant would otherwise fill by itself.
    if MB.db.trade.enabled and MB.db.trade.shiftSkips then
        Theme:TipLine(GameTooltip, "Shift as a trade opens: no water or food is given", "dim")
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
    Theme:UseStrata(orb, 0)
    orb:SetClampedToScreen(true)
    orb:SetMovable(true)
    orb:RegisterForClicks("AnyUp", "AnyDown")
    orb:SetAttribute("useOnKeyDown", false) -- always act on release, whatever the CVar says
    orb:RegisterForDrag("LeftButton")

    orb.halo = orb:CreateTexture(nil, "BACKGROUND", nil, -1)
    orb.halo:SetTexture(MB.MEDIA .. "Glow.tga")
    orb.halo:SetBlendMode("ADD")
    orb.halo:SetPoint("TOPLEFT", -22, 22)
    orb.halo:SetPoint("BOTTOMRIGHT", 22, -22)
    orb.halo:Hide()   -- lit, coloured and set breathing by RefreshGlow, and only then

    -- A ring that travels outwards from the orb and fades as it goes, over
    -- and over, while something needs attention.
    orb.wave = orb:CreateTexture(nil, "BACKGROUND", nil, -2)
    orb.wave:SetTexture(MB.MEDIA .. "Ring.tga")
    orb.wave:SetBlendMode("ADD")
    orb.wave:SetAllPoints()
    orb.wave:Hide()

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
    orb.ring:SetVertexColor(Theme:Accent())   -- RefreshGlow owns its colour from here on

    -- Lit briefly whenever the orb or one of its buttons is clicked. It sits
    -- at the centre, where the glow has room to spread without washing over
    -- the ring of a neighbouring button.
    orb.flash = orb:CreateTexture(nil, "OVERLAY", nil, -1)
    orb.flash:SetTexture(MB.MEDIA .. "Glow.tga")
    orb.flash:SetBlendMode("ADD")
    orb.flash:SetPoint("TOPLEFT", -14, 14)
    orb.flash:SetPoint("BOTTOMRIGHT", 14, -14)
    -- Invisible until a click plays it. It is not registered for the accent
    -- colour like the other textures: colouring a texture also sets how
    -- opaque it is, which left this one fully lit from login until the first
    -- click faded it out. Theme:Flash colours it as it plays instead.
    orb.flash:SetAlpha(0)

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
        -- The buff click is a plain right-click on purpose: held with Shift,
        -- Ctrl or Alt the secure button casts nothing, so nothing is expected.
        if button == "RightButton" and down then
            if not IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown() then
                MB.BuffWatch:PrepareClick()
            else
                -- A press that casts nothing also clears whatever an earlier
                -- press left behind, so no later release can report a cast
                -- that was never made.
                MB.BuffWatch:CancelClick()
            end
        end
    end)
    orb:SetScript("PostClick", function(self, button, down)
        if down then return end
        Theme:Flash(self.flash)
        if button == "RightButton" then
            if IsShiftKeyDown() then
                MB.Settings:Toggle()
            elseif not IsControlKeyDown() and not IsAltKeyDown() then
                MB.BuffWatch:AfterClick()
            end
        elseif button == "MiddleButton" then
            MB.Readiness:TogglePanel()
        end
    end)
    Theme:RoundTooltip(orb, OrbTooltip)

    Radial.orb = orb
end

--- Puts the orb and its buttons where the settings and the screen say. Both
--- callers queue it under one key, so they have to be the same work.
local function Relayout()
    MB:AfterCombat("radial-layout", function()
        Radial:ApplyPosition()
        Radial:Layout()
    end)
end

--- Ends an orb drag and stores the position as an offset from screen centre.
function Radial:StopDrag()
    if not orb.dragging then return end
    -- StopMovingOrSizing is protected on the orb, so in combat the whole
    -- thing waits. The drag flag stays set meanwhile, so the mouse release
    -- queues the same call again under the same key rather than slipping
    -- past the guard above and leaving the orb stuck to the cursor.
    if InCombatLockdown() then
        MB:AfterCombat("orb-stop-drag", function() Radial:StopDrag() end)
        return
    end
    orb.dragging = nil
    orb:StopMovingOrSizing()

    local x, y = MB.CentreOffset(orb)
    if x then
        MB.db.orb.x, MB.db.orb.y = x, y
    end
    Relayout()
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
    Theme:UseStrata(menu, 0)
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
        -- The moment the counts are looked at: read them now, so the menu
        -- shows what is in the bags even if a bag update went missing.
        MB:RefreshInventory(false, "menu")
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

    -- Which rank the button conjures, shown only while that is not the
    -- strongest: otherwise a rank stepped down to is easy to forget about.
    button.rank = Theme:Text(button, 10, "OVERLAY", "OUTLINE")
    button.rank:SetPoint("TOPLEFT", -2, 2)
    button.rank:Hide()

    button:HookScript("OnEnter", function(self)
        ButtonTooltip(self)
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- Both click phases arrive here; light up on the one that acts. The glow
    -- goes on the orb at the centre; only the ring of the button itself
    -- brightens, so nothing spills over a neighbour.
    button:HookScript("PostClick", function(self, _, down)
        if not down then
            Theme:Flash(orb.flash, self.ring, Radial.RestoreRings)
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

-- U+221E, written as its UTF-8 bytes so the source stays ASCII. Shown in
-- place of a rune count when a talent has lifted the cost: the supply is
-- no longer a number, so a number would be the wrong thing to show.
local INFINITY = "\226\136\158"

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
    -- The release is the click that casts, and this runs just before it does:
    -- inside the player's own click, which is the one moment an announcement
    -- in /say or /yell may be made out in the world, and early enough that
    -- "can this cast start?" is not answered by the cast itself having begun.
    row:SetScript("PreClick", function(self, _, down)
        if not down and self.spellID then MB.Announce:OnTravelClick(self.spellID) end
    end)
    row:SetScript("PostClick", function(self, _, down)
        -- The cast happens on release.
        if down then return end
        -- Close the menu after it when allowed.
        if not MB.db.radial.closeAfterTravel or InCombatLockdown() then return end
        menu:Hide()
    end)

    sub.rows[index] = row
    return row
end

local function CreateSub(key)
    local sub = CreateFrame("Frame", "MageButlerSub_" .. key, menu, "SecureHandlerBaseTemplate")
    sub.key = key
    sub.rows = {}
    Theme:UseStrata(sub, 1)
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

--- The learned destinations behind one of the two travel buttons.
local function TravelList(key)
    return (key == "portals") and Spells:GetPortals() or Spells:GetTeleports()
end

--- Rebuilds one submenu from the learned spells. Out of combat only.
local function BuildSub(key)
    local sub = subs[key]
    local list = TravelList(key)

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
    Theme:TipLine(GameTooltip, text, "dim", true)
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
            Theme:TipLine(GameTooltip, "Not learned yet.", "bad")
        end
        local target = Conjuring:Target(key)
        local have = Conjuring:Count(key)
        -- The count is of the strongest rank carried and of that alone, so it
        -- says which rank that is: a bare number next to a button set to
        -- conjure another rank reads as a contradiction. Manna biscuits are
        -- the exception, since they count as both food and water: with those
        -- in the total it names no rank and itemises everything below.
        local counted = Conjuring:BestItem(key)
        local countedRank = counted and Conjuring:RankOfItem(counted)
        local mixed = counted and MB:CountOf(counted) ~= have
        GameTooltip:AddLine(" ")
        if not MB.inventoryKnown then
            Theme:TipLine(GameTooltip, "In bags: not counted yet", "dim")
        else
            local line = "In bags"
            if countedRank and not mixed then line = line .. "  Rank " .. countedRank end
            line = line .. ": " .. have
            if target > 0 then line = line .. " / " .. target end
            Theme:TipLine(GameTooltip, line, "text")

            -- Lower ranks, kept for players too low for the strongest.
            local carried = Conjuring:RanksCarried(key)
            for i = #carried, 1, -1 do
                local entry = carried[i]
                if mixed or entry.item ~= counted then
                    local name = entry.rank and ("Rank " .. entry.rank) or (API.ItemName(entry.item) or "Other")
                    Theme:TipLine(GameTooltip, "  " .. name .. ": " .. entry.count
                        .. "  (level " .. entry.level .. ")", "dim")
                end
            end
        end
        -- What the button will make, which is not always what is carried, and
        -- from what level it can be eaten or drunk: that decides who in the
        -- group it is any use to.
        local _, rank, ranks, _, level = Conjuring:RankInfo(key)
        if rank and level then
            Theme:TipLine(GameTooltip, "Conjures Rank " .. rank .. ", usable from level " .. level,
                Conjuring:SteppedDown(key) and "gold" or "text", true)
        end

        if ranks and ranks > 1 then
            AddHint("Right-click: step down a rank, for players too low for this one")
        end
    elseif key == "gem" then
        local spellID, allHeld = Conjuring:GetGemCast()
        if spellID then
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:AddLine(" ")
            if allHeld then
                Theme:TipLine(GameTooltip, "You already hold every gem you can conjure.", "ok", true)
            end
        else
            GameTooltip:AddLine("Conjure Mana Gem", r, g, b)
            Theme:TipLine(GameTooltip, "Not learned yet.", "bad")
        end
        local item = Conjuring:BestItem("gem")
        if item then
            AddHint("Right-click: use " .. (API.ItemName(item) or "your mana gem"))
        end
    elseif key == "portals" or key == "teleports" then
        local list = TravelList(key)
        local reagent = SUB_REAGENT[key]
        GameTooltip:AddLine(LABELS[key], r, g, b)
        if #list == 0 then
            Theme:TipLine(GameTooltip, "None learned yet.", "bad")
        else
            Theme:TipLine(GameTooltip, #list .. (#list == 1 and " destination" or " destinations"), "text")
            if Reagents:InactiveReason(reagent) == "talent" then
                local cr, cg, cb = Theme:StateColor("ok")
                GameTooltip:AddLine(Reagents:Name(reagent) .. ": " .. INFINITY, cr, cg, cb)
                Theme:TipLine(GameTooltip, "Your talents have lifted the cost.", "dim")
            elseif MB.inventoryKnown then
                local cr, cg, cb = Theme:StateColor(Reagents:Count(reagent) > 0 and "ok" or "none")
                GameTooltip:AddLine(Reagents:Name(reagent) .. ": " .. Reagents:Count(reagent), cr, cg, cb)
            else
                Theme:TipLine(GameTooltip, Reagents:Name(reagent) .. ": not counted yet", "dim")
            end
            AddHint("Click to choose a destination")
        end
    elseif key == "trade" then
        GameTooltip:AddLine("Trade assistant", r, g, b)
        if MB.Trade:IsOpen() then
            Theme:TipLine(GameTooltip, MB.Trade:DescribePreset(), "text")
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
        Theme:TipLine(GameTooltip, "Automatic filling: " .. auto, "text")
        AddHint("Right-click: turn automatic filling on or off")
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
--- Icons, counts and state colours. Safe at any time, including in combat.
--- Nothing here can be seen while the menu is closed, and opening it comes
--- straight back here, so a closed menu is left alone.
function Radial:RefreshVisuals()
    if not menu or not menu:IsShown() then return end

    -- Until the bags have been read once the counts are unknown, not zero,
    -- so no number is shown at all and nothing is dimmed for want of a rune.
    local known = MB.inventoryKnown

    for _, kind in ipairs(CONJURED) do
        local button = buttons[kind]
        button.icon:SetTexture(Conjuring:Icon(kind))
        SetButtonState(button, Conjuring:GetSpell(kind) ~= nil)
        local state = Conjuring:State(kind)
        SetCount(button, known and Conjuring:Count(kind) or nil, state == "off" and "ok" or state)

        -- A rank stepped down to is marked, so it is not conjured for the
        -- rest of the evening by mistake.
        local _, rank = Conjuring:RankInfo(kind)
        if rank and Conjuring:SteppedDown(kind) then
            button.rank:SetText("R" .. rank)
            button.rank:SetTextColor(Theme:Color("gold"))
            button.rank:Show()
        else
            button.rank:Hide()
        end
    end

    local gem = buttons.gem
    gem.icon:SetTexture(Conjuring:Icon("gem"))
    SetButtonState(gem, Conjuring:GetGemCast() ~= nil)
    local gemCount = Conjuring:Count("gem")
    SetCount(gem, known and gemCount or nil, gemCount > 0 and "ok" or "none")

    for key, reagent in pairs(SUB_REAGENT) do
        local button = buttons[key]
        local sub = subs[key]
        local list = TravelList(key)
        button.icon:SetTexture((list[1] and list[1].icon) or FALLBACK_ICON[key])
        SetButtonState(button, #list > 0, sub:IsShown())

        -- With the cost lifted there is no number to show and nothing can
        -- run short, so the badge carries the symbol and the list stays lit.
        local free = Reagents:InactiveReason(reagent) == "talent"
        local have = Reagents:Count(reagent)
        local state = (free or have > 0) and "ok" or "none"
        if #list > 0 and (known or free) then
            SetCount(button, free and INFINITY or have, state)
            sub.reagent:SetText(Reagents.SHORT[reagent] .. "  " .. (free and INFINITY or have))
            sub.reagent:SetTextColor(Theme:StateColor(state))
        else
            SetCount(button, nil)
            sub.reagent:SetText("")
        end
        -- A destination cannot be cast without its rune: dim the list.
        local short = known and not free and have <= 0
        for i = 1, #sub.rows do
            local row = sub.rows[i]
            row.icon:SetDesaturated(short)
            row.text:SetTextColor(Theme:Color(short and "off" or "text"))
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
    food:SetAttribute("*type1", foodSpell and "spell" or nil)
    food:SetAttribute("*spell1", foodSpell)
    -- Nothing is cast by a right-click on the food button: a plain one steps
    -- the rank down, and that is done in a PostClick hook, not here.
    food:SetAttribute("*type2", nil)
    food:SetAttribute("*spell2", nil)

    local gem = buttons.gem
    local gemSpell = Conjuring:GetGemCast()
    local gemItem = Conjuring:BestItem("gem")
    gem:SetAttribute("*type1", gemSpell and "spell" or nil)
    gem:SetAttribute("*spell1", gemSpell)
    gem:SetAttribute("*type2", gemItem and "item" or nil)
    gem:SetAttribute("*item2", gemItem and ("item:" .. gemItem) or nil)
end

--- Steps the water or food button down to the next rank, and round to the
--- strongest again below the weakest: a stock of a rank a low-level player
--- can drink is made by stepping down and conjuring as usual. The rank is a
--- secure attribute, so it cannot be changed in combat, and that is said
--- rather than silently ignored. Called from the player's own right-click.
function Radial:StepRank(kind)
    if InCombatLockdown() then
        MB:Notify("The rank can only be changed out of combat.", "warn")
        return
    end
    if not Conjuring:CycleRank(kind) then return end
    RefreshAttributes()
    self:RefreshVisuals()
    -- The cursor is on the button, so its tooltip is the answer to the click.
    local button = buttons[kind]
    if GameTooltip:IsOwned(button) then ButtonTooltip(button) end
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

--- Where the submenus open: towards the middle of the screen, so a menu near
--- the right edge drops its list on the left. Shared by both arrangements.
local function OpenRight()
    local cx = orb:GetCenter()
    if not cx then return true end
    return cx * orb:GetScale() < UIParent:GetWidth() * 0.6
end

--- The original arrangement: buttons on a circle around the orb, or on an
--- arc where the screen edge leaves no room for a full one.
---
--- This is the path a player who never touches the layout setting takes, and
--- it is kept exactly as it was. A harness phase asserts its anchors, sizes
--- and menu extent against figures read from the addon before any of the
--- other arrangements existed.
local function LayoutClassic(db, visible)
    local size, radius = db.buttonSize, db.radius

    local centre, span = ArcFor(radius, size)
    Radial.arcCentre, Radial.arcSpan = centre, span

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
    local openRight = OpenRight()
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

--- Any other arrangement, placed by Layout.lua.
---
--- Returns false if the stored preset is one this version does not know, so
--- a profile from a newer build falls back to the circle rather than erroring.
local function LayoutEngine(db, visible)
    local size = db.buttonSize
    local positions, width, height, top = MB.Layout:Positions(db.preset, #visible, {
        size = size,
        launcher = ORB_SIZE,
        gapX = db.gapX,
        gapY = db.gapY,
        columns = db.columns,
        direction = db.direction,
        radius = db.radius,
    })
    if not positions then return false end

    for i = 1, #visible do
        local button = visible[i]
        local point = positions[i]
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("CENTER", menu, "CENTER", point.x, point.y)
        button.label:SetShown(db.showLabels)
        button:Show()
    end

    -- The frame is still centred on the orb and must cover the furthest
    -- button; Layout.lua has already doubled the reach for that.
    menu:SetSize(math.max(width, ORB_SIZE), math.max(height, ORB_SIZE))
    -- The orbit ring is a circle and means nothing off the circle.
    menu.orbit:Hide()

    -- Cleared rather than left behind: these are module fields that nothing
    -- else resets, and a stale pair from the classic path would read as
    -- though this arrangement were still a circle.
    Radial.arcCentre, Radial.arcSpan = nil, nil
    Radial.clearance = top

    -- Here a submenu hangs off its own button. Anchoring it to the middle of
    -- the frame, as the circle does, would drop it across a toolbar's own
    -- buttons.
    local openRight = OpenRight()
    for key, sub in pairs(subs) do
        local parent = buttons[key]
        sub:ClearAllPoints()
        if openRight then
            sub:SetPoint("LEFT", parent, "RIGHT", 10, 0)
        else
            sub:SetPoint("RIGHT", parent, "LEFT", -10, 0)
        end
    end
    return true
end

--- Positions the buttons and the submenus beside them. Out of combat only.
---
--- Which arrangement is used is the one decision made here: the original
--- circle, or one of the others from Layout.lua.
function Radial:Layout()
    local db = MB.db.radial

    local visible = {}
    for _, key in ipairs(ORDER) do
        local button = buttons[key]
        if db.buttons[key] then
            visible[#visible + 1] = button
        else
            button:Hide()
        end
    end

    -- Shape is settled here, with the placement, rather than in RefreshVisuals
    -- where the rest of the artwork lives. RefreshVisuals runs immediately,
    -- outside the combat queue, so a shape change made in a fight would land
    -- while the positions and sizes waited for it to end: square buttons on a
    -- circle, behind a round orbit ring, until the fight was over.
    --
    -- Classic Radial is round, full stop. The shape setting belongs to the
    -- other arrangements, and reaching it cannot change the original.
    -- The orb itself stays round. Its artwork is a sphere with a halo, a
    -- ripple and a flash, all drawn from radial textures, and none of them has
    -- a square counterpart; squaring it is its own piece of work, not a
    -- side effect of this setting.
    local engine = MB.Layout:Handles(db.preset)
    local shape = engine and db.buttonShape or "round"
    for _, key in ipairs(ORDER) do
        Theme:SetShape(buttons[key], shape)
    end

    if engine and LayoutEngine(db, visible) then return end
    self.clearance = nil
    LayoutClassic(db, visible)
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
function Radial:Apply(section)
    -- The orb, the buttons and the bindings only depend on the general and
    -- menu settings: a change anywhere else redraws, and rebuilds nothing.
    local rebuild = section == nil or section == "all" or section == "general" or section == "radial"
    if rebuild then MB:AfterCombat("radial-apply", function()
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
    end) end
    self:RefreshGlow()
    self:RefreshVisuals()
end

--- The halo behind the orb is a call for attention, not decoration: it is lit
--- only while Buff Watch has players to buff or the preparation check is
--- short of something, and dark the rest of the time.
--- The ring goes with it: at rest it is drawn at about half strength, so the
--- orb sits quietly on the screen, and it comes up to full brightness, or to
--- Buff Watch's warning colour, only while there is something to see to.
local REST = 0.5

function Radial:RefreshGlow()
    if not orb then return end
    local watch, ready = MB.BuffWatch, MB.Readiness
    -- In combat Buff Watch stops reading buffs but keeps its last picture,
    -- and that picture goes on being shown: a player who went into the fight
    -- without Intellect is still without it. It is read afresh as combat ends.
    -- Switched off, though, it has no say at all, in combat or out of it.
    local watching = MB.db.general.enabled and MB.db.buffwatch.enabled
    local buffs = watching and watch and watch:GetOverall()
    local supplies = ready and ready:GetOverall()
    local buffsNeed = buffs == "low" or buffs == "none"
    local attention = MB.db.general.enabled and (buffsNeed or supplies == "low" or supplies == "none")

    -- The halo takes the colour of the worst thing that needs seeing to,
    -- yellow for running low and red for missing, and breathes on the shared
    -- beat. The speed is the same for both: every status animation keeps one
    -- beat, so the mode only says whether to move at all.
    if attention and MB.db.appearance.glow then
        local worst = (buffs == "none" or supplies == "none") and "none" or "low"
        orb.halo:SetVertexColor(Theme:StateColor(worst))
        orb.halo:Show()
        Theme:SetBreath(orb.halo, worst == "none" and "fast" or "slow")
        orb.wave:SetVertexColor(Theme:StateColor(worst))
        Theme:SetWave(orb.wave, worst == "none" and "fast" or "slow")
    else
        -- Not snatched away: each plays out its beat, and the halo then fades.
        Theme:SetBreath(orb.halo, nil, true)
        Theme:SetWave(orb.wave, nil)
    end

    if buffsNeed and MB.db.buffwatch.orbColors then
        orb.ring:SetVertexColor(Theme:StateColor(buffs))
    else
        local r, g, b = Theme:Accent()
        local strength = attention and 1 or REST
        orb.ring:SetVertexColor(r * strength, g * strength, b * strength)
    end
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

    -- A plain right-click on water or food steps down a rank. It casts
    -- nothing, so it is done here and not by a secure attribute. Shift is
    -- left free on purpose: a right-click with it held does nothing at all,
    -- rather than stepping a rank the player did not mean to step.
    for _, key in ipairs(CONJURED) do
        buttons[key]:HookScript("PostClick", function(_, click, down)
            if down or click ~= "RightButton" or IsShiftKeyDown() then return end
            Radial:StepRank(key)
        end)
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
                    -- Opened only while Buff Watch is on; one that is open
                    -- can always be closed.
                    if list and (self:GetAttribute("mbbufflist") or list:IsShown()) then
                        if list:IsShown() then list:Hide() else list:Show() end
                    end
                end
                return false
            end
            return
        end
        return false
    ]=])

    MB:On("SETTINGS_CHANGED", function(section)
        Radial:Apply(section)
    end)
    MB:On("SPELLS_UPDATED", function()
        Radial:Apply()
    end)
    MB:On("INVENTORY_UPDATED", function()
        Radial:RefreshVisuals()
        MB:AfterCombat("radial-attributes", RefreshAttributes)
    end)

    -- Entering combat mid-drag: ask for the orb to be dropped. Lockdown is
    -- already in force by now, so StopDrag queues it for the end of the fight.
    MB:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        Radial:StopDrag()
    end)

    -- A different resolution or UI scale moves the screen edges.
    MB:RegisterEvent("DISPLAY_SIZE_CHANGED", Relayout)
    MB:RegisterEvent("UI_SCALE_CHANGED", Relayout)
    MB:RegisterEvent("TRADE_SHOW", function()
        Radial:RefreshVisuals()
    end)
    MB:RegisterEvent("TRADE_CLOSED", function()
        Radial:RefreshVisuals()
    end)
end
