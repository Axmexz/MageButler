-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: preparation indicator.
-- One glance (the pip on the orb, the dot on the HUD) or one click (the pip,
-- or middle-click on the orb) answers "am I stocked for this dungeon or raid?":
-- conjured water and food against their targets, a mana gem, and each reagent.
-- It adds no button to the radial menu.

local _, MB = ...
local Readiness = MB:NewModule("Readiness")
local Theme, Conjuring, Reagents

local ROW_HEIGHT = 18
local MAX_ROWS = 7

local items = {}
local overall = "off"
local pip, panel
local wasInInstance = false

-------------------------------------------------------------------------------
-- Evaluation
-------------------------------------------------------------------------------
local function Add(label, have, want, state)
    if state == "off" then return end
    items[#items + 1] = { label = label, have = have, want = want, state = state }
end

local function Evaluate()
    wipe(items)
    overall = "off"
    if not (MB.db.general.enabled and MB.db.readiness.enabled) then return end

    Add("Water", Conjuring:Count("water"), Conjuring:Target("water"), Conjuring:State("water"))
    Add("Food", Conjuring:Count("food"), Conjuring:Target("food"), Conjuring:State("food"))
    Add("Mana Gem", Conjuring:Count("gem"), Conjuring:Target("gem"), Conjuring:State("gem"))
    for _, key in ipairs(Reagents.ORDER) do
        Add(Reagents:Name(key), Reagents:Count(key), MB.db.reagents.items[key].target, Reagents:State(key))
    end

    -- Buff Watch: how much of the group carries Intellect.
    local watch = MB.BuffWatch
    if watch and watch:GetOverall() ~= "off" then
        local have, total = watch:GetCoverage()
        Add("Intellect buffs", have, total, watch:GetOverall())
    end

    if #items == 0 then return end
    overall = "ok"
    for i = 1, #items do
        local state = items[i].state
        if state == "none" then
            overall = "none"
            break
        elseif state == "low" then
            overall = "low"
        end
    end
end

--- "ok", "low", "none", or "off" when nothing is being tracked.
function Readiness:GetOverall()
    return overall
end

local function Headline()
    if overall == "ok" then return "Ready" end
    if overall == "low" then return "Running low" end
    if overall == "none" then return "Not ready" end
    return "Nothing tracked"
end

--- One-line summary of what is short, e.g. "Water 12/40, Mana Gem 0/1".
local function Shortfalls()
    local parts = {}
    for i = 1, #items do
        local item = items[i]
        if item.state ~= "ok" then
            parts[#parts + 1] = item.label .. " " .. item.have .. "/" .. item.want
        end
    end
    return table.concat(parts, ", ")
end

function Readiness:AddTooltipLines(tooltip)
    if overall == "off" then return end
    tooltip:AddLine(" ")
    local r, g, b = Theme:StateColor(overall)
    tooltip:AddLine("Preparation: " .. Headline(), r, g, b)
    for i = 1, #items do
        local item = items[i]
        local ir, ig, ib = Theme:StateColor(item.state)
        tooltip:AddDoubleLine(item.label, item.have .. " / " .. item.want, 0.88, 0.92, 1, ir, ig, ib)
    end
end

--- Shows the result as a toast; `verbose` also lists every line in chat.
function Readiness:Report(verbose)
    Evaluate()
    if overall == "off" then
        if verbose then MB:Print("the preparation check is turned off.") end
        return
    end
    if overall == "ok" then
        MB.Theme:Toast("Preparation: ready.", "ok")
    else
        MB.Theme:Toast("Preparation: " .. Shortfalls() .. ".", overall == "none" and "bad" or "warn")
    end
    if verbose then
        MB:Print("preparation - " .. Headline() .. ":")
        for i = 1, #items do
            local item = items[i]
            local r, g, b = Theme:StateColor(item.state)
            MB:Print("  " .. Theme:Hex(r, g, b) .. item.label .. "  " .. item.have .. " / " .. item.want .. "|r")
        end
    end
end

-------------------------------------------------------------------------------
-- Pip on the orb and the one-click checklist
-------------------------------------------------------------------------------
local function UpdatePanel()
    if not panel or not panel:IsShown() then return end

    panel.status:SetText(Headline())
    panel.status:SetTextColor(Theme:StateColor(overall))

    for i = 1, MAX_ROWS do
        local row = panel.rows[i]
        local item = items[i]
        if item then
            row.icon:SetTexture(Theme.icons[(item.state == "ok" and "ok") or (item.state == "low" and "warn") or "bad"])
            row.label:SetText(item.label)
            row.value:SetText(item.have .. " / " .. item.want)
            row.value:SetTextColor(Theme:StateColor(item.state))
            row:Show()
        else
            row:Hide()
        end
    end
    panel:SetHeight(44 + math.max(1, math.min(#items, MAX_ROWS)) * ROW_HEIGHT)
end

local function CreatePanel()
    panel = Theme:CreatePanel("MageButlerReadiness", UIParent, "bg")
    panel:SetFrameStrata("HIGH")
    panel:SetSize(210, 120)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()

    panel.title = Theme:Text(panel, 12)
    panel.title:SetPoint("TOPLEFT", 12, -10)
    panel.title:SetText("Preparation")
    Theme:UseAccent(panel.title, "SetTextColor", 1)

    panel.status = Theme:Text(panel, 11)
    panel.status:SetPoint("TOPRIGHT", -12, -11)

    panel.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(186, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 12, -(30 + (i - 1) * ROW_HEIGHT))

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 0, 0)

        row.label = Theme:Text(row, 11)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)

        row.value = Theme:Text(row, 11)
        row.value:SetPoint("RIGHT", 0, 0)

        panel.rows[i] = row
    end

    -- Click anywhere on the checklist to dismiss it.
    panel:SetScript("OnMouseUp", function(self)
        self:Hide()
    end)
    panel:SetScript("OnShow", UpdatePanel)
end

function Readiness:TogglePanel()
    if not MB:IsActive() then return end
    if not panel then CreatePanel() end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    Evaluate()
    panel:ClearAllPoints()
    local orb = MB.RadialMenu.orb
    if orb and orb:IsShown() then
        panel:SetPoint("BOTTOMLEFT", orb, "TOPRIGHT", 6, 6)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    panel:Show()
end

local function CreatePip()
    local orb = MB.RadialMenu.orb
    pip = CreateFrame("Button", nil, orb)
    pip:SetSize(16, 16)
    pip:SetPoint("CENTER", orb, "BOTTOMRIGHT", -6, 6)
    pip:SetFrameLevel(orb:GetFrameLevel() + 5)

    pip.rim = pip:CreateTexture(nil, "BACKGROUND")
    pip.rim:SetTexture(MB.MEDIA .. "Circle.tga")
    pip.rim:SetAllPoints()
    pip.rim:SetVertexColor(0.02, 0.04, 0.09)

    pip.dot = pip:CreateTexture(nil, "ARTWORK")
    pip.dot:SetTexture(MB.MEDIA .. "Circle.tga")
    pip.dot:SetPoint("TOPLEFT", 3, -3)
    pip.dot:SetPoint("BOTTOMRIGHT", -3, 3)

    pip:SetScript("OnClick", function()
        Readiness:TogglePanel()
    end)
    Theme:RoundTooltip(pip, function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = Theme:StateColor(overall)
        GameTooltip:AddLine("Preparation: " .. Headline(), r, g, b)
        for i = 1, #items do
            local item = items[i]
            local ir, ig, ib = Theme:StateColor(item.state)
            GameTooltip:AddDoubleLine(item.label, item.have .. " / " .. item.want, 0.88, 0.92, 1, ir, ig, ib)
        end
        GameTooltip:AddLine("Click for the checklist", 0.56, 0.63, 0.79)
        GameTooltip:Show()
    end)
end

local function Update()
    Evaluate()
    if pip then
        if overall == "off" then
            pip:Hide()
        else
            pip.dot:SetVertexColor(Theme:StateColor(overall))
            Theme:SetPulse(pip.dot, Theme:PulseForState(overall))
            pip:Show()
        end
    end
    if panel and overall == "off" then
        panel:Hide()
    end
    UpdatePanel()
    MB:Fire("READINESS_UPDATED")
end

-------------------------------------------------------------------------------
function Readiness:OnEnable()
    Theme, Conjuring, Reagents = MB.Theme, MB.Conjuring, MB.Reagents

    CreatePip()

    MB:On("INVENTORY_UPDATED", Update)
    MB:On("SPELLS_UPDATED", Update)
    MB:On("SETTINGS_CHANGED", Update)
    MB:On("BUFFWATCH_UPDATED", Update)

    -- A ready check is exactly when the answer matters.
    MB:RegisterEvent("READY_CHECK", function()
        if MB:IsActive() and MB.db.readiness.enabled and MB.db.readiness.onReadyCheck then
            Readiness:Report(false)
        end
    end)

    -- Walking into a dungeon or raid short of supplies: say so once.
    MB:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        local inInstance, kind = IsInInstance()
        local inside = inInstance and (kind == "party" or kind == "raid") or false
        local entered = inside and not wasInInstance
        wasInInstance = inside
        if not entered then return end
        C_Timer.After(3, function()
            if not (MB:IsActive() and MB.db.readiness.enabled and MB.db.readiness.onInstance) then return end
            Evaluate()
            if overall == "low" or overall == "none" then
                Readiness:Report(false)
            end
        end)
    end)
end
