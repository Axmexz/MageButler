-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: visual styling shared by every frame.
-- Midnight navy panels and an accent colour of the player's choosing.

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
local pips = {}

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

--- Icon for an inventory state: "ok", "low", "none" or "off".
function Theme:StateIcon(state)
    if state == "ok" then return self.icons.ok end
    if state == "low" then return self.icons.warn end
    return self.icons.bad
end

function Theme:Hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function Theme:AccentHex()
    return self:Hex(self:Accent())
end

-------------------------------------------------------------------------------
-- Frame strata
--
-- Which layer of the interface MageButler draws on. One setting moves the
-- whole addon together: a frame is registered at a fixed number of steps
-- above the strata the player chose, so the orb sits at the base, the panels
-- and the toast one above it and the settings window two, whatever that base
-- is. Choosing a single strata for everything would put a submenu behind the
-- menu it belongs to.
--
-- At the top of the list the offsets have nowhere left to go and collapse to
-- the same strata. Nothing is lost by that: the frames that share one are
-- parented to each other, so frame level still orders them.
-------------------------------------------------------------------------------
Theme.STRATA = {
    "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG",
    "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}

local STRATA_DEFAULT = "MEDIUM"
local STRATA_INDEX = {}
for i = 1, #Theme.STRATA do STRATA_INDEX[Theme.STRATA[i]] = i end

local strataUsers = {}

--- The strata `offset` steps above the player's choice, clamped to the list.
function Theme:Strata(offset)
    local chosen = MB.db and MB.db.appearance.strata or STRATA_DEFAULT
    local base = STRATA_INDEX[chosen] or STRATA_INDEX[STRATA_DEFAULT]
    local index = base + (offset or 0)
    if index < 1 then index = 1 end
    if index > #self.STRATA then index = #self.STRATA end
    return self.STRATA[index]
end

--- Re-seats every registered frame. `SetFrameStrata` is protected, and most
--- of these frames are the orb's own children, so the whole pass is queued
--- rather than refused one call at a time.
function Theme:RefreshStrata()
    MB:AfterCombat("theme-strata", function()
        for i = 1, #strataUsers do
            local user = strataUsers[i]
            user[1]:SetFrameStrata(Theme:Strata(user[2]))
        end
    end)
end

--- Keeps `frame` `offset` steps above the chosen strata, including after the
--- player changes it.
function Theme:UseStrata(frame, offset)
    strataUsers[#strataUsers + 1] = { frame, offset or 0 }
    self:RefreshStrata()
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
    self:RefreshStrata()
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

-- The game's own fantasy serif. There is no italic face on this client, so
-- this is what sets a line apart from the plain text around it.
local FANCY_FONT = "Fonts\\MORPHEUS.ttf"

--- Draws a font string in that serif. Morpheus runs small for its size, so
--- it is given a couple of points over the text it sits with. A client that
--- does not have the face keeps the font it had.
function Theme:Fancy(text, size)
    local font, height, flags = text:GetFont()
    size = size or (height and height + 2) or 13
    text:SetFont(FANCY_FONT, size, flags or "")
    if not text:GetFont() and font then
        text:SetFont(font, height or size, flags or "")
    end
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

--- A small status light on the rim of the orb: a dark disc with a coloured
--- dot in it. `point` is the corner of the orb it sits on.
function Theme:CreatePip(orb, point, x, y)
    local pip = CreateFrame("Button", nil, orb)
    pip:SetSize(16, 16)
    pip:SetPoint("CENTER", orb, point, x, y)
    pip:SetFrameLevel(orb:GetFrameLevel() + 5)

    pip.rim = pip:CreateTexture(nil, "BACKGROUND")
    pip.rim:SetTexture(MB.MEDIA .. "Circle.tga")
    pip.rim:SetAllPoints()
    pip.rim:SetVertexColor(0.02, 0.04, 0.09)

    pip.dot = pip:CreateTexture(nil, "ARTWORK")
    pip.dot:SetTexture(MB.MEDIA .. "Circle.tga")
    pip.dot:SetPoint("TOPLEFT", 3, -3)
    pip.dot:SetPoint("BOTTOMRIGHT", -3, 3)
    pips[#pips + 1] = pip
    pip.combatKey = "pip" .. #pips
    return pip
end

--- Shows or hides a status light. The pips are children of the orb, which is
--- a secure button, so their own Show and Hide are protected: in combat the
--- change is queued and made the moment the fight ends.
function Theme:ShowPip(pip, shown)
    if InCombatLockdown() then
        MB:AfterCombat(pip.combatKey, function() pip:SetShown(shown) end)
        return
    end
    if pip:IsShown() ~= shown then pip:SetShown(shown) end
end

--- Whether the status lights take the mouse. They sit on the orb's rim and
--- are easy to hit by accident; switched off, a click on one goes through to
--- the orb underneath, and so does the tooltip. EnableMouse is protected on
--- the orb's children, so this waits for the end of a fight as well.
function Theme:RefreshPips()
    MB:AfterCombat("theme-pips", function()
        local clickable = not MB.db or MB.db.appearance.pipClicks ~= false
        for i = 1, #pips do
            pips[i]:EnableMouse(clickable)
        end
    end)
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

--- One tooltip line in a colour from the palette ("text" when none is named).
function Theme:TipLine(tooltip, text, colorName, wrap)
    local r, g, b = self:Color(colorName or "text")
    tooltip:AddLine(text, r, g, b, wrap)
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

-- Every status animation keeps the same beat and the same phase, and none of
-- them is ever cut off or restarted in mid-movement:
--   * the first one to start sets the beat;
--   * one that starts later waits for the next beat and joins in step, rather
--     than everything being restarted around it;
--   * one that is no longer wanted plays on to the end of the beat, where the
--     ripple has faded to nothing and the halo is at its dimmest, and stops
--     there.
local BEAT = 2.5
local running = {}   -- [group] = true while it plays or waits for its beat
local ending = {}    -- [group] = what to do once it has played out
local waiting = {}   -- [group] = a token while it waits to join
local epoch          -- when the beat began
local tokens = 0

--- Seconds until the next beat.
local function ToNextBeat()
    if not epoch then return 0 end
    return BEAT - ((GetTime() - epoch) % BEAT)
end

local function Start(group)
    if ending[group] then
        ending[group] = nil   -- still playing, and still in step: carry on
        return
    end
    if running[group] then return end
    if not next(running) then
        epoch = GetTime()
        running[group] = true
        group:Play()
        return
    end
    -- Started in the same moment as the beat itself: it is on the beat
    -- already, and waiting for the next would hold it back a whole one.
    if epoch and (GetTime() - epoch) % BEAT < 0.05 then
        running[group] = true
        group:Play()
        return
    end
    running[group] = true
    tokens = tokens + 1
    local token = tokens
    waiting[group] = token
    C_Timer.After(ToNextBeat(), function()
        if waiting[group] ~= token then return end
        waiting[group] = nil
        if running[group] and not ending[group] then
            group:Stop()
            group:Play()
        end
    end)
end

--- Stops a group at the end of the beat, then calls `done`.
local function Halt(group, done)
    if not running[group] then
        if done then done() end
        return
    end
    if waiting[group] then
        -- It never began: there is nothing to play out.
        waiting[group] = nil
        running[group] = nil
        group:Stop()
        if done then done() end
        return
    end
    done = done or true
    local first = ending[group] == nil
    ending[group] = done
    if not first then return end
    C_Timer.After(ToNextBeat(), function()
        local after = ending[group]
        if not after then return end   -- wanted again in the meantime
        ending[group] = nil
        running[group] = nil
        group:Stop()
        if not next(running) then epoch = nil end
        if after ~= true then after() end
    end)
end

--- Fades a region out over a moment and then hides it.
local function FadeAway(region)
    local group = region.mbFade
    if not group then
        group = region:CreateAnimationGroup()
        group.alpha = group:CreateAnimation("Alpha")
        group.alpha:SetToAlpha(0)
        group.alpha:SetDuration(0.5)
        group.alpha:SetSmoothing("OUT")
        if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
        group:SetScript("OnFinished", function()
            region:Hide()
        end)
        region.mbFade = group
    end
    group.alpha:SetFromAlpha(region:GetAlpha() or 0.35)
    group:Stop()
    group:Play()
end

--- Status animation for an indicator: any mode for a pulse, nil for a steady
--- light. A gentle alpha pulse, nothing more.
function Theme:SetPulse(region, mode)
    if mode and not (MB.db and MB.db.appearance.statusAnimations) then
        mode = nil
    end
    local group = region.mbPulse
    if not mode then
        if group and region.mbPulseMode then
            region.mbPulseMode = nil
            Halt(group, function() region:SetAlpha(1) end)
        elseif not (group and ending[group]) then
            region:SetAlpha(1)
        end
        return
    end
    if not group then
        group = region:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        group.alpha = group:CreateAnimation("Alpha")
        group.alpha:SetFromAlpha(0.3)   -- dim to bright and back, the same way round as the halo
        group.alpha:SetToAlpha(1)
        group.alpha:SetSmoothing("IN_OUT")
        group.alpha:SetDuration(BEAT / 2)
        region.mbPulse = group
    end
    if not region.mbPulseMode then
        region.mbPulseMode = true
        Start(group)
    end
end

--- A halo that breathes: it swells a little and brightens, then eases back,
--- once a beat. Nil stops it at the end of the beat: with `hide` the halo then
--- fades away, otherwise it is left at a steady glow. With status animations
--- switched off it is always steady.
function Theme:SetBreath(region, mode, hide)
    if mode and not (MB.db and MB.db.appearance.statusAnimations) then
        mode = nil
    end
    local group = region.mbBreath
    if not mode then
        if group and (region.mbBreathMode or ending[group]) then
            -- Still breathing, or playing out its beat: the latest request
            -- decides what happens when the beat ends.
            region.mbBreathMode = nil
            Halt(group, function()
                if hide then
                    FadeAway(region)
                else
                    if region.mbFade then region.mbFade:Stop() end
                    region:SetAlpha(0.7)
                end
            end)
        elseif not hide then
            -- A fade from an earlier "stop" would carry on to invisible and
            -- hide the halo, though it is wanted lit.
            if region.mbFade then region.mbFade:Stop() end
            region:SetAlpha(0.7)
        elseif not (region.mbFade and region.mbFade:IsPlaying()) then
            region:Hide()   -- unless it is fading away already, which ends hidden
        end
        return
    end
    if region.mbFade then region.mbFade:Stop() end
    if not group then
        group = region:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        group.alpha = group:CreateAnimation("Alpha")
        group.alpha:SetFromAlpha(0.35)
        group.alpha:SetToAlpha(1)
        group.alpha:SetSmoothing("IN_OUT")
        group.alpha:SetDuration(BEAT / 2)
        group.scale = group:CreateAnimation("Scale")
        if group.scale.SetScaleFrom then
            group.scale:SetScaleFrom(0.85, 0.85)
            group.scale:SetScaleTo(1.3, 1.3)
        end
        group.scale:SetSmoothing("IN_OUT")
        group.scale:SetDuration(BEAT / 2)
        region.mbBreath = group
    end
    if not region.mbBreathMode then
        region:SetAlpha(0.35)   -- where the breath starts, so nothing jumps as it begins
        region.mbBreathMode = true
        Start(group)
    end
end

--- A ring that spreads outwards and fades to nothing, once a beat, like a
--- ripple. Nil lets the ripple in progress finish and then hides the ring.
--- With status animations switched off there is no ripple at all.
function Theme:SetWave(region, mode)
    if mode and not (MB.db and MB.db.appearance.statusAnimations) then
        mode = nil
    end
    local group = region.mbWave
    if not mode then
        if group and region.mbWaveMode then
            region.mbWaveMode = nil
            Halt(group, function() region:Hide() end)
        elseif not (group and ending[group]) then
            region:Hide()
        end
        return
    end
    if not group then
        group = region:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        group.scale = group:CreateAnimation("Scale")
        if group.scale.SetScaleFrom then
            group.scale:SetScaleFrom(1, 1)
            group.scale:SetScaleTo(2.2, 2.2)
        end
        group.scale:SetSmoothing("OUT")
        group.scale:SetDuration(BEAT)
        -- It fades in over the first fifth of the beat and out over the rest.
        -- Starting at full strength, each new ripple appeared all at once,
        -- drawn exactly on top of the orb's own ring, and that read as a
        -- flash every time the loop came round.
        local rise = BEAT * 0.2
        group.fadeIn = group:CreateAnimation("Alpha")
        group.fadeIn:SetFromAlpha(0)
        group.fadeIn:SetToAlpha(0.7)
        group.fadeIn:SetDuration(rise)
        group.alpha = group:CreateAnimation("Alpha")
        group.alpha:SetFromAlpha(0.7)
        group.alpha:SetToAlpha(0)
        group.alpha:SetStartDelay(rise)
        group.alpha:SetDuration(BEAT - rise)
        region.mbWave = group
    end
    -- Invisible in its own right, so that it is only ever seen through the
    -- animation: between one loop and the next a texture shows at its own
    -- opacity for an instant.
    if not region.mbWaveMode then
        region:SetAlpha(0)
        region:Show()
        region.mbWaveMode = true
        Start(group)
    end
end

--- The pulse that goes with an inventory / buff state.
function Theme:PulseForState(state)
    if state == "none" then return "fast" end
    if state == "low" then return "slow" end
    return nil
end

--- One soft swell of light and back, as feedback for a click. The glow is
--- wider than whatever it sits on, so it belongs on something with room
--- around it, not on a button with neighbours. `ring`, where given, brightens
--- with it; `restore` is then called to put that ring back to whatever colour
--- it should be by then, which need not be the colour it had before the click.
function Theme:Flash(region, ring, restore)
    if not region then return end
    if MB.db and not MB.db.radial.animations then return end

    -- A flash already running hands its ring back before this one takes over.
    local pending = region.mbFlashRestore
    region.mbFlashRestore = nil
    if pending then pending() end

    local group = region.mbFlash
    if not group then
        group = region:CreateAnimationGroup()
        local up = group:CreateAnimation("Alpha")
        up:SetFromAlpha(0)
        up:SetToAlpha(0.85)
        up:SetDuration(0.09)
        up:SetOrder(1)
        local down = group:CreateAnimation("Alpha")
        down:SetFromAlpha(0.85)
        down:SetToAlpha(0)
        down:SetDuration(0.42)
        down:SetSmoothing("OUT")
        down:SetOrder(2)
        group:SetScript("OnFinished", function()
            -- Taken before it is called, so a later flash cannot hand the
            -- same ring back a second time.
            local done = region.mbFlashRestore
            region.mbFlashRestore = nil
            region:SetAlpha(0)
            if done then done() end
        end)
        region.mbFlash = group
    end

    region.mbFlashRestore = restore
    if ring then
        ring:SetVertexColor(1, 1, 1, 1)
    end

    group:Stop()
    region:SetVertexColor(self:Accent())
    region:SetAlpha(0)
    group:Play()
end

-------------------------------------------------------------------------------
-- Toast: one small, self-dismissing notification line
-------------------------------------------------------------------------------
local TOAST_HOLD = 4.0
local TOAST_MERGE = 2.5
local KIND_RANK = { ok = 1, info = 1, warn = 2, bad = 3 }

local function CreateToast()
    local toast = Theme:CreatePanel("MageButlerToast", UIParent, "bg")
    Theme:UseStrata(toast, 1)
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
    -- A message the toast is already showing is not written under itself: it
    -- is simply shown again, for its full time, at the size it already has.
    -- Repeated warnings would otherwise pile up into a wall of the same line.
    local repeated = false
    for i = 1, #lines do
        if lines[i] == message then
            repeated = true
            break
        end
    end
    if not repeated then
        while #lines >= 3 do
            table.remove(lines, 1)
        end
        lines[#lines + 1] = message
    end
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
            Theme:RefreshPips()
        end
    end)
end
