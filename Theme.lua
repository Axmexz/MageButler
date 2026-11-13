-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: visual styling shared by every frame.
-- Midnight navy panels, Arcane cyan highlights, restrained purple accents.

local _, MB = ...
local Theme = MB:NewModule("Theme")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

Theme.colors = {
    bg = { 0.027, 0.063, 0.118 },
    panel = { 0.047, 0.086, 0.165 },
    raised = { 0.078, 0.137, 0.259 },
    border = { 0.263, 0.345, 0.573 },
    text = { 0.878, 0.918, 1.000 },
    dim = { 0.560, 0.630, 0.790 },
    gold = { 1.000, 0.820, 0.000 },
    purple = { 0.420, 0.360, 0.800 },
    ok = { 0.350, 0.900, 0.550 },
    warn = { 1.000, 0.750, 0.250 },
    bad = { 1.000, 0.350, 0.350 },
    off = { 0.400, 0.440, 0.540 },
}

Theme.accents = {
    arcane = { 0.369, 0.843, 1.000 },
    violet = { 0.718, 0.612, 1.000 },
    frost = { 0.780, 0.930, 1.000 },
}
Theme.accentOrder = { "arcane", "violet", "frost" }
Theme.accentNames = { arcane = "Arcane Cyan", violet = "Violet", frost = "Frost" }

Theme.icons = {
    ok = "Interface\\RaidFrame\\ReadyCheck-Ready",
    info = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    warn = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    bad = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local accentUsers = {}
local panels = {}

-------------------------------------------------------------------------------
-- Colours
-------------------------------------------------------------------------------
function Theme:Accent()
    local key = MB.db and MB.db.appearance.accent
    local colour = self.accents[key] or self.accents.arcane
    return colour[1], colour[2], colour[3]
end

function Theme:Color(name)
    local colour = self.colors[name] or self.colors.text
    return colour[1], colour[2], colour[3]
end

--- Colour for an inventory state: "ok", "low", "none" or "off".
function Theme:StateColor(state)
    if state == "ok" then return self:Color("ok") end
    if state == "low" then return self:Color("warn") end
    if state == "none" then return self:Color("bad") end
    return self:Color("off")
end

function Theme:Hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function Theme:AccentHex()
    return self:Hex(self:Accent())
end

--- Keeps `object` tinted with the accent colour, including after it changes.
function Theme:UseAccent(object, method, alpha)
    alpha = alpha or 1
    accentUsers[#accentUsers + 1] = { object, method, alpha }
    local r, g, b = self:Accent()
    object[method](object, r, g, b, alpha)
end

function Theme:Refresh()
    local r, g, b = self:Accent()
    for i = 1, #accentUsers do
        local user = accentUsers[i]
        user[1][user[2]](user[1], r, g, b, user[3])
    end
    local alpha = MB.db and MB.db.appearance.panelAlpha or 0.92
    for i = 1, #panels do
        local panel = panels[i]
        local cr, cg, cb = self:Color(panel.mbColor)
        panel:SetBackdropColor(cr, cg, cb, panel.mbSolid and 1 or alpha)
    end
end

-------------------------------------------------------------------------------
-- Building blocks
-------------------------------------------------------------------------------
function Theme:Text(parent, size, layer, flags)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(FONT, size or 12, flags or "")
    if not text:GetFont() then
        text:SetFontObject(GameFontHighlightSmall)
    end
    text:SetTextColor(self:Color("text"))
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    return text
end

--- Applies the panel backdrop. colorName: "bg", "panel" or "raised".
function Theme:SkinPanel(frame, colorName, solid)
    frame:SetBackdrop({
        bgFile = WHITE,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame.mbColor = colorName or "bg"
    frame.mbSolid = solid
    local r, g, b = self:Color(frame.mbColor)
    local alpha = MB.db and MB.db.appearance.panelAlpha or 0.92
    frame:SetBackdropColor(r, g, b, solid and 1 or alpha)
    frame:SetBackdropBorderColor(self:Color("border"))
    panels[#panels + 1] = frame
    return frame
end

function Theme:CreatePanel(name, parent, colorName, solid)
    local frame = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    return self:SkinPanel(frame, colorName, solid)
end

--- A flat 1px-bordered box for inputs, rows and list items.
function Theme:SkinBox(frame, colorName)
    frame:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    local r, g, b = self:Color(colorName or "panel")
    frame:SetBackdropColor(r, g, b, 0.95)
    local br, bg, bb = self:Color("border")
    frame:SetBackdropBorderColor(br, bg, bb, 0.9)
    return frame
end

--- Round button artwork: disc, circular icon, accent ring and a hover glow.
function Theme:SkinRound(button)
    local media = MB.MEDIA

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetTexture(media .. "Circle.tga")
    button.bg:SetAllPoints()
    button.bg:SetVertexColor(self:Color("raised"))

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    if button.CreateMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture(media .. "Circle.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(button.icon)
        button.icon:AddMaskTexture(mask)
        button.mask = mask
    end

    button.ring = button:CreateTexture(nil, "OVERLAY")
    button.ring:SetTexture(media .. "Ring.tga")
    button.ring:SetPoint("TOPLEFT", -1, 1)
    button.ring:SetPoint("BOTTOMRIGHT", 1, -1)
    button.ring:SetVertexColor(self:Color("border"))

    button.glow = button:CreateTexture(nil, "HIGHLIGHT")
    button.glow:SetTexture(media .. "Glow.tga")
    button.glow:SetBlendMode("ADD")
    button.glow:SetPoint("TOPLEFT", -9, 9)
    button.glow:SetPoint("BOTTOMRIGHT", 9, -9)
    self:UseAccent(button.glow, "SetVertexColor", 0.55)

    return button
end

--- A themed text button for panels.
function Theme:CreateButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 110, height or 22)
    self:SkinBox(button, "raised")

    button.label = self:Text(button, 11)
    button.label:SetPoint("CENTER")
    button.label:SetText(label or "")

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(WHITE)
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetBlendMode("ADD")
    self:UseAccent(highlight, "SetVertexColor", 0.18)

    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.label:SetPoint("CENTER", 1, -1) end
    end)
    button:SetScript("OnMouseUp", function(self)
        self.label:SetPoint("CENTER", 0, 0)
    end)
    button:SetScript("OnDisable", function(self)
        self.label:SetTextColor(Theme:Color("off"))
    end)
    button:SetScript("OnEnable", function(self)
        self.label:SetTextColor(Theme:Color("text"))
    end)
    return button
end

--- Shows a tooltip with a title and optional wrapped body lines.
function Theme:ShowTooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local r, g, b = self:Accent()
    GameTooltip:AddLine(title, r, g, b)
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then
            GameTooltip:AddLine(line, 0.88, 0.92, 1, true)
        end
    end
    GameTooltip:Show()
end

function Theme:AttachTooltip(frame, title, body)
    if not title then return end
    frame:HookScript("OnEnter", function(self)
        Theme:ShowTooltip(self, title, body)
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function CursorInCircle(frame)
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local cx, cy = frame:GetCenter()
    if not (x and cx and scale) or scale == 0 then return true end
    local dx, dy = x / scale - cx, y / scale - cy
    local radius = frame:GetWidth() / 2
    return dx * dx + dy * dy <= radius * radius
end

local function HideOwnTooltip(frame)
    frame.mbTooltip = nil
    if GameTooltip:IsOwned(frame) then
        GameTooltip:Hide()
    end
end

--- Tooltip for a round widget. A frame's mouse area is its square bounding
--- box, so a plain OnEnter tooltip stays up in the empty corners around a
--- circle. This one shows only while the cursor is inside the circle, and it
--- watches the cursor itself while hovered, so it also closes if the client
--- never delivers the OnLeave. `build(frame)` fills and shows GameTooltip.
function Theme:RoundTooltip(frame, build)
    local function Track(self)
        if not self:IsVisible() or not self:IsMouseOver() then
            self:SetScript("OnUpdate", nil)
            HideOwnTooltip(self)
            return
        end
        local inside = CursorInCircle(self)
        if inside and not self.mbTooltip then
            self.mbTooltip = true
            build(self)
        elseif not inside and self.mbTooltip then
            HideOwnTooltip(self)
        end
    end
    frame:SetScript("OnEnter", function(self)
        self.mbTooltip = nil
        self:SetScript("OnUpdate", Track)
        Track(self)
    end)
    frame:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        HideOwnTooltip(self)
    end)
end

--- Status animation for an indicator: "fast" (something is missing), "slow"
--- (a warning) or nil for a steady light. A gentle alpha pulse, nothing more.
function Theme:SetPulse(region, mode)
    if mode and not (MB.db and MB.db.appearance.statusAnimations) then
        mode = nil
    end
    local group = region.mbPulse
    if not mode then
        if group and region.mbPulseMode then
            group:Stop()
        end
        region.mbPulseMode = nil
        region:SetAlpha(1)
        return
    end
    if not group then
        group = region:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        group.alpha = group:CreateAnimation("Alpha")
        group.alpha:SetFromAlpha(1)
        group.alpha:SetToAlpha(0.25)
        group.alpha:SetSmoothing("IN_OUT")
        region.mbPulse = group
    end
    if region.mbPulseMode ~= mode then
        group:Stop()
        group.alpha:SetDuration(mode == "fast" and 0.45 or 1.1)
        region.mbPulseMode = mode
        group:Play()
    end
end

--- The pulse that goes with an inventory / buff state.
function Theme:PulseForState(state)
    if state == "none" then return "fast" end
    if state == "low" then return "slow" end
    return nil
end

-------------------------------------------------------------------------------
-- Toast: one small, self-dismissing notification line
-------------------------------------------------------------------------------
local TOAST_HOLD = 4.0
local TOAST_MERGE = 2.5
local KIND_RANK = { ok = 1, info = 1, warn = 2, bad = 3 }

local function CreateToast()
    local toast = Theme:CreatePanel("MageButlerToast", UIParent, "bg")
    toast:SetFrameStrata("HIGH")
    toast:SetPoint("TOP", UIParent, "TOP", 0, -170)
    toast:SetSize(260, 34)
    toast:EnableMouse(false)
    toast:Hide()

    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(18, 18)
    toast.icon:SetPoint("LEFT", 10, 0)

    toast.text = Theme:Text(toast, 12)
    toast.text:SetPoint("LEFT", toast.icon, "RIGHT", 8, 0)
    toast.text:SetJustifyH("LEFT")

    toast.fade = toast:CreateAnimationGroup()
    local alpha = toast.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetStartDelay(TOAST_HOLD)
    alpha:SetDuration(0.8)
    toast.fade:SetScript("OnFinished", function()
        toast:Hide()
    end)

    toast.lines = {}
    return toast
end

--- kind: "ok", "info", "warn" or "bad". With `replace`, the message takes the
--- toast over instead of being stacked under what it already shows.
function Theme:Toast(message, kind, replace)
    if not message or message == "" then return end
    local toast = self.toast
    if not toast then
        toast = CreateToast()
        self.toast = toast
    end

    -- Messages arriving close together share one toast instead of replacing it.
    local now = GetTime()
    local lines = toast.lines
    if replace or not toast:IsShown() or (toast.lastTime and now - toast.lastTime > TOAST_MERGE) then
        wipe(lines)
        toast.kind = nil
    end
    while #lines >= 3 do
        table.remove(lines, 1)
    end
    lines[#lines + 1] = message
    toast.lastTime = now

    kind = kind or "info"
    if not toast.kind or (KIND_RANK[kind] or 1) > (KIND_RANK[toast.kind] or 1) then
        toast.kind = kind
    end

    toast.icon:SetTexture(self.icons[toast.kind] or self.icons.ok)
    toast.text:SetText(table.concat(lines, "\n"))
    toast:SetSize(math.max(180, toast.text:GetStringWidth() + 52), math.max(34, toast.text:GetStringHeight() + 20))
    local r, g, b = self:Accent()
    if toast.kind == "warn" then
        r, g, b = self:Color("warn")
    elseif toast.kind == "bad" then
        r, g, b = self:Color("bad")
    end
    toast:SetBackdropBorderColor(r, g, b, 0.9)

    toast.fade:Stop()
    toast:SetAlpha(1)
    toast:Show()
    toast.fade:Play()
end

-------------------------------------------------------------------------------
function Theme:OnEnable()
    MB:On("SETTINGS_CHANGED", function(section)
        if section == "appearance" or section == "all" then
            Theme:Refresh()
        end
    end)
end
