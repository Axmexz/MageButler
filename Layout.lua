-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: where the menu's buttons go, for every layout but the original.
--
-- This file is pure arithmetic. It creates no frames, reads no settings and
-- touches nothing in the game, so every arrangement in it can be checked
-- exactly rather than by eye. That is the whole reason it is separate.
--
-- Classic Radial is deliberately NOT in here. It stays on its own path in
-- RadialMenu.lua, untouched, and a player who never changes the setting never
-- reaches this file at all.
--
-- Coordinates are offsets from the centre of the menu frame, which is the
-- centre of the orb, with y counting upwards, matching the classic maths.
--
-- INVARIANT: the menu frame is anchored CENTER to CENTER on the orb once, at
-- creation, and is never re-anchored - ClearAllPoints on it is protected. So
-- an arrangement that sits to one side of the orb is expressed as offsets
-- inside a frame that is still centred on it, and the frame is sized to cover
-- the furthest button on either side. The frame takes no mouse input, so the
-- empty half swallows no clicks.

local _, MB = ...

local Layout = {}
MB.Layout = Layout

-- Display order, and the labels the settings page shows.
Layout.PRESETS = {
    { "classic", "Classic Radial" },
    { "customRadial", "Custom Radial" },
    { "doubleColumn", "Double Column" },
    { "horizontal", "Horizontal Toolbar" },
    { "vertical", "Vertical Toolbar" },
    { "grid", "Compact Grid" },
    { "arc", "Arc Menu" },
    { "diamond", "Diamond Formation" },
    { "sidePanel", "Side Panel" },
    { "fan", "Fan Menu" },
    { "tFormation", "T Formation" },
}

--- Whether a preset name is one this file knows how to place. "classic" is
--- not: it belongs to RadialMenu.lua.
function Layout:Handles(preset)
    return preset ~= nil and preset ~= "classic" and self.placers[preset] ~= nil
end

-------------------------------------------------------------------------------
-- The arrangements
--
-- Each takes (count, o) and returns a list of { x = , y = }. `o` carries the
-- sizes the player chose: size, launcher, gapX, gapY, columns, radius.
-- Nothing else is read, so none of these can be surprised by a setting.
-------------------------------------------------------------------------------
local placers = {}
Layout.placers = placers

--- Where the first row sits below the launcher, centre to centre.
local function Below(o)
    return -(o.launcher / 2 + o.gapY + o.size / 2)
end

--- Where the first column sits beside the launcher, centre to centre.
local function Beside(o)
    return o.launcher / 2 + o.gapX + o.size / 2
end

--- Buttons spread along an arc of `span` degrees centred on `centre`.
local function OnArc(count, radius, centre, span, stretch)
    local out = {}
    for i = 1, count do
        local degrees
        if count == 1 then
            degrees = centre
        else
            degrees = centre + span / 2 - (i - 1) * span / (count - 1)
        end
        local angle = math.rad(degrees)
        out[i] = {
            x = radius * math.cos(angle) * (stretch or 1),
            y = radius * math.sin(angle),
        }
    end
    return out
end

--- Rows of `columns`, filling left to right and then downwards.
local function Rows(count, o, columns, startY)
    local out = {}
    for i = 1, count do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        out[i] = {
            x = (col - (columns - 1) / 2) * (o.size + o.gapX),
            y = startY - row * (o.size + o.gapY),
        }
    end
    return out
end

-- A circle, as the classic menu draws it, but reachable by the engine so it
-- can carry square buttons. Never used for Classic Radial itself.
placers.customRadial = function(count, o)
    local out = {}
    for i = 1, count do
        -- From the top and clockwise, the same way the classic circle runs.
        local angle = math.rad(90 - (i - 1) * 360 / count)
        out[i] = { x = o.radius * math.cos(angle), y = o.radius * math.sin(angle) }
    end
    return out
end

-- Two columns under the launcher.
placers.doubleColumn = function(count, o)
    return Rows(count, o, 2, Below(o))
end

-- One row, running away from the launcher.
placers.horizontal = function(count, o)
    local out = {}
    local sign = (o.direction == "left") and -1 or 1
    for i = 1, count do
        out[i] = { x = sign * (Beside(o) + (i - 1) * (o.size + o.gapX)), y = 0 }
    end
    return out
end

-- One column, running away from the launcher.
placers.vertical = function(count, o)
    local out = {}
    local sign = (o.direction == "up") and 1 or -1
    for i = 1, count do
        out[i] = { x = 0, y = sign * (o.launcher / 2 + o.gapY + o.size / 2 + (i - 1) * (o.size + o.gapY)) }
    end
    return out
end

-- A block of rows under the launcher, as many columns as asked for.
placers.grid = function(count, o)
    return Rows(count, o, math.max(1, math.min(count, o.columns or 3)), Below(o))
end

-- An arc over the launcher, which sits below its centre.
placers.arc = function(count, o)
    return OnArc(count, o.radius, 90, 160)
end

-- The same idea, opened out wider and flattened. A half circle, not more:
-- past 180 degrees the ends drop below the launcher instead of fanning
-- above it.
placers.fan = function(count, o)
    return OnArc(count, o.radius, 90, 180, 1.25)
end

-- A circle pushed out to its corners, so the buttons sit on a diamond.
placers.diamond = function(count, o)
    local out = {}
    for i = 1, count do
        local angle = math.rad(90 - (i - 1) * 360 / count)
        local cos, sin = math.cos(angle), math.sin(angle)
        -- On a diamond |x| + |y| is constant, so pull the point in or out
        -- until it is. Never divides by zero: |cos| + |sin| >= 1.
        local reach = o.radius / (math.abs(cos) + math.abs(sin))
        out[i] = { x = reach * cos, y = reach * sin }
    end
    return out
end

-- Two columns beside the launcher, centred on it.
placers.sidePanel = function(count, o)
    local out = {}
    local rows = math.ceil(count / 2)
    local sign = (o.direction == "left") and -1 or 1
    for i = 1, count do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        out[i] = {
            x = sign * (Beside(o) + col * (o.size + o.gapX)),
            y = ((rows - 1) / 2 - row) * (o.size + o.gapY),
        }
    end
    return out
end

-- Three across under the launcher, the rest hanging below the middle one.
placers.tFormation = function(count, o)
    local out = {}
    local across = math.min(3, count)
    local top = Below(o)
    for i = 1, across do
        out[i] = { x = (i - (across + 1) / 2) * (o.size + o.gapX), y = top }
    end
    for i = across + 1, count do
        out[i] = { x = 0, y = top - (i - across) * (o.size + o.gapY) }
    end
    return out
end

-------------------------------------------------------------------------------
-- Staying on screen
--
-- Every arrangement here leans somewhere: a toolbar runs one way, a grid
-- hangs below, an arc sits above. Near a screen edge that lean puts buttons
-- where the player cannot click them.
--
-- The answer is one rule for all eleven rather than an edge policy per
-- arrangement: mirror the whole thing. Each is either symmetric across an
-- axis (where mirroring it changes nothing) or directional (where mirroring
-- it is exactly the other direction), so the four candidates below are
-- always arrangements the player could have asked for by hand. That is why
-- it can be one rule, and why it is arithmetic rather than a special case
-- bolted onto each placer.
--
-- `room` is how far the orb's centre is from each screen edge, in the menu's
-- own units. Without it nothing is mirrored, which is what the settings
-- preview wants: it should draw the arrangement as chosen, not as some
-- screen position would bend it.
-------------------------------------------------------------------------------

local MARGIN = 6

--- How far a mirrored copy would hang off the screen, in total. Zero means it
--- fits. Measured as a sum rather than a yes/no so that where nothing fits -
--- a toolbar wider than the screen - the least bad side still wins.
local function Overflow(positions, half, room, flipX, flipY)
    local over = 0
    for i = 1, #positions do
        local x, y = positions[i].x * flipX, positions[i].y * flipY
        over = over + math.max(0, (x + half + MARGIN) - room.right)
        over = over + math.max(0, (-x + half + MARGIN) - room.left)
        over = over + math.max(0, (y + half + MARGIN) - room.up)
        over = over + math.max(0, (-y + half + MARGIN) - room.down)
    end
    return over
end

--- Mirrors the arrangement onto whichever side has room for it.
---
--- The unmirrored arrangement is tried first and kept on a tie, so a player
--- with room all round always gets precisely what they chose.
local function KeepOnScreen(positions, o, room)
    if not room then return positions, 1, 1 end
    for _, key in ipairs({ "left", "right", "up", "down" }) do
        if type(room[key]) ~= "number" then return positions, 1, 1 end
    end

    local half = o.size / 2
    local bestX, bestY = 1, 1
    local best = Overflow(positions, half, room, 1, 1)
    for _, pair in ipairs({ { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        if best <= 0 then break end
        local over = Overflow(positions, half, room, pair[1], pair[2])
        if over < best then
            best, bestX, bestY = over, pair[1], pair[2]
        end
    end

    if bestX == 1 and bestY == 1 then return positions, 1, 1 end
    for i = 1, #positions do
        positions[i].x = positions[i].x * bestX
        positions[i].y = positions[i].y * bestY
    end
    return positions, bestX, bestY
end

-------------------------------------------------------------------------------
-- The one entry point
-------------------------------------------------------------------------------
local DEFAULTS = {
    size = 40, launcher = 46, gapX = 8, gapY = 8, columns = 3,
    direction = "down", radius = 78,
}

--- Where `count` buttons go under `preset`.
---
--- Returns the offsets, the width and height the menu frame needs to cover
--- them while staying centred on the orb, and `clearance`: how far above that
--- centre the arrangement reaches, which is what Buff Watch needs in order to
--- park its list clear of the buttons.
---
--- `opts.room` is how far the orb's centre sits from each screen edge, under
--- the keys left, right, up and down, in the menu's own units. Given it, an
--- arrangement that would run off the screen is mirrored onto the side that
--- has room. Left out, nothing is mirrored.
---
--- An unknown preset returns nothing, so a profile carrying a name this
--- version does not have falls back to the classic path rather than erroring.
function Layout:Positions(preset, count, opts)
    local place = preset and preset ~= "classic" and placers[preset]
    if not place or count <= 0 then return nil end

    local o = {}
    for key, value in pairs(DEFAULTS) do
        local given = opts and opts[key]
        o[key] = (type(given) == type(value) and given) or value
    end

    local positions = place(count, o)
    local flipX, flipY
    positions, flipX, flipY = KeepOnScreen(positions, o, opts and opts.room)

    -- The frame stays centred on the orb, so it has to reach the furthest
    -- button on whichever side that is, and the same distance the other way.
    -- Clearance starts at the orb itself: an arrangement that hangs entirely
    -- below it still reaches that far up, and Buff Watch parking its list on
    -- a clearance of nothing would drop it over the orb.
    local reachX, reachY, top = 0, 0, o.launcher / 2
    for i = 1, #positions do
        local p = positions[i]
        reachX = math.max(reachX, math.abs(p.x) + o.size / 2)
        reachY = math.max(reachY, math.abs(p.y) + o.size / 2)
        top = math.max(top, p.y + o.size / 2)
    end

    return positions, reachX * 2, reachY * 2, top, flipX, flipY
end
