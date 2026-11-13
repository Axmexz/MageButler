-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: optional compact HUD with inventory counters.
-- Purely informational (no protected frames), updated only when the bags,
-- the spellbook or the settings change.

local _, MB = ...
local HUD = MB:NewModule("HUD")
local API = MB.API
local Theme, Conjuring, Reagents

local CELLS = {
    { key = "food", label = "Food", source = "conjured" },
    { key = "water", label = "Water", source = "conjured" },
    { key = "gem", label = "Mana Gem", source = "conjured" },
    { key = "runeT", label = "Rune T", source = "reagent" },
    { key = "runeP", label = "Rune P", source = "reagent" },
    { key = "powder", label = "Arcane", source = "reagent" },
    { key = "intellect", label = "Intellect", source = "buffwatch" },
}

local HEIGHT = 38
local PAD = 10
local DOT = 10

local frame
local cells = {}

local function CreateCell(info)
    local cell = CreateFrame("Frame", nil, frame)
    cell:SetHeight(HEIGHT)
    cell.info = info

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(22, 22)
    cell.icon:SetPoint("LEFT", 0, 0)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cell.count = Theme:Text(cell, 14)
    cell.label = Theme:Text(cell, 9)
    cell.label:SetTextColor(Theme:Color("dim"))

    cell.divider = cell:CreateTexture(nil, "BORDER")
    cell.divider:SetColorTexture(1, 1, 1, 0.12)
    cell.divider:SetSize(1, HEIGHT - 16)
    cell.divider:SetPoint("LEFT", -7, 0)

    cells[#cells + 1] = cell
    return cell
end

local function CellData(info)
    local key = info.key
    if info.source == "conjured" then
        local item = (key == "gem") and Conjuring:GetGemItem() or Conjuring:BestItem(key)
        local icon = (item and API.ItemIcon(item)) or Conjuring:Icon(key)
        return Conjuring:Count(key), Conjuring:State(key), icon
    end
    if info.source == "buffwatch" then
        -- Group coverage, e.g. "34/40"; nothing to show while solo.
        local watch = MB.BuffWatch
        local overall = watch:GetOverall()
        local have, total = watch:GetCoverage()
        if overall == "off" or watch:GetState().context == "solo" then
            return 0, "off", nil
        end
        return have .. "/" .. total, overall, API.SpellTexture(1459)
    end
    return Reagents:Count(key), Reagents:State(key), API.ItemIcon(Reagents.ITEMS[key])
end

function HUD:Refresh()
    if not frame then return end
    local db = MB.db
    if not (db.general.enabled and db.general.showHUD) then
        frame:Hide()
        return
    end

    local labels = db.appearance.hudLabels
    local x = PAD
    local shown = 0

    -- Readiness dot at the left edge.
    local overall = MB.Readiness and MB.Readiness:GetOverall() or "off"
    if overall ~= "off" then
        frame.dot:SetVertexColor(Theme:StateColor(overall))
        Theme:SetPulse(frame.dot, Theme:PulseForState(overall))
        frame.dot:Show()
        x = x + DOT + 8
    else
        frame.dot:Hide()
    end

    for i = 1, #cells do
        local cell = cells[i]
        local count, state, icon = CellData(cell.info)
        -- Untracked supplies are only worth a cell while some are carried.
        if db.hud.cells[cell.info.key] and (state ~= "off" or (type(count) == "number" and count > 0)) then
            cell.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            cell.count:SetText(count)
            if state == "low" or state == "none" then
                cell.count:SetTextColor(Theme:StateColor(state))
            else
                cell.count:SetTextColor(Theme:Color("text"))
            end
            cell.icon:SetDesaturated(count == 0)

            cell.count:ClearAllPoints()
            cell.label:ClearAllPoints()
            local width
            if labels then
                cell.label:SetText(cell.info.label)
                cell.label:Show()
                cell.count:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", 6, 2)
                cell.label:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMRIGHT", 6, -3)
                width = 28 + math.max(cell.count:GetStringWidth(), cell.label:GetStringWidth())
            else
                cell.label:Hide()
                cell.count:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
                width = 28 + cell.count:GetStringWidth()
            end

            cell:SetWidth(width)
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", frame, "LEFT", x, 0)
            cell.divider:SetShown(shown > 0)
            cell:Show()
            x = x + width + 14
            shown = shown + 1
        else
            cell:Hide()
        end
    end

    if shown == 0 then
        frame:Hide()
        return
    end
    frame:SetSize(x - 14 + PAD, HEIGHT)
    frame:Show()
end

function HUD:ApplyPosition()
    local scale = MB.db.general.uiScale
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", MB.db.hud.x / scale, MB.db.hud.y / scale)
end

function HUD:OnEnable()
    Theme, Conjuring, Reagents = MB.Theme, MB.Conjuring, MB.Reagents

    frame = Theme:CreatePanel("MageButlerHUD", UIParent, "bg")
    frame:SetFrameStrata("LOW")
    frame:SetSize(300, HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    frame.dot = frame:CreateTexture(nil, "ARTWORK")
    frame.dot:SetTexture(MB.MEDIA .. "Circle.tga")
    frame.dot:SetSize(DOT, DOT)
    frame.dot:SetPoint("LEFT", PAD, 0)

    frame:SetScript("OnDragStart", function(self)
        if MB.db.general.lockPositions then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            local scale = self:GetScale()
            MB.db.hud.x = cx * scale - ux
            MB.db.hud.y = cy * scale - uy
        end
        HUD:ApplyPosition()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            MB.Settings:Toggle()
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local r, g, b = Theme:Accent()
        GameTooltip:AddLine("MageButler", r, g, b)
        if MB.Readiness and MB.Readiness.AddTooltipLines then
            MB.Readiness:AddTooltipLines(GameTooltip)
        end
        GameTooltip:AddLine("Right-click: settings", 0.56, 0.63, 0.79)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    for i = 1, #CELLS do
        CreateCell(CELLS[i])
    end

    self.frame = frame

    MB:On("SETTINGS_CHANGED", function()
        HUD:ApplyPosition()
        HUD:Refresh()
    end)
    MB:On("READINESS_UPDATED", function()
        HUD:Refresh()
    end)
end
