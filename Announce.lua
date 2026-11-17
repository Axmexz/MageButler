-- MageButler - Copyright (c) 2026 Padre Pidisc. All rights reserved. See LICENSE.txt.
-- MageButler: portal announcements.
-- Says in chat that a portal has opened, in the player's own words, once the
-- cast has actually gone through.
--
-- What the game allows decides how it is said:
--   * Party and raid chat can be sent as the portal opens.
--   * /say and /yell may only be sent by an addon from the player's own click,
--     except inside a dungeon or raid. Out in the world the announcement is
--     therefore offered as a button, and the click on it is what sends it.
--   * Where the client has chat locked down for addons, the text is put in
--     the chat box instead, for the player to send with Enter.
-- One cast is announced once, and nothing is sent at all when the chosen
-- channel would reach nobody.

local ADDON_NAME, MB = ...
local Announce = MB:NewModule("Announce")
local API = MB.API
local Theme, Spells

-- The channels on offer, in the order the settings step through them. GROUP
-- is raid chat in a raid and party chat in a party.
Announce.CHANNELS = {
    { "SAY", "Say" }, { "YELL", "Yell" }, { "PARTY", "Party" }, { "RAID", "Raid" },
    { "GROUP", "Party or raid" },
}

local SLASH = { SAY = "/s ", YELL = "/y ", PARTY = "/p ", RAID = "/raid " }
local WHERE = { SAY = "/say", YELL = "/yell", PARTY = "party chat", RAID = "raid chat" }
local NEEDS_CLICK = { SAY = true, YELL = true }   -- outside a dungeon or raid

local MAX_LENGTH = 255   -- the longest chat message the game takes
local REPEAT_GUARD = 3   -- seconds in which one spell is not announced twice
local OFFER_TIME = 20    -- how long the button waits to be clicked
local START_GUARD = 15   -- seconds a cast announced at its start is given to finish

local travel = {}        -- [spellID] = { kind, place, name } for each learned destination
local byName = {}        -- the same entries, by the spell's name
local refused = {}       -- [chatType] = true once the client has refused an unprompted send
local sending            -- the chat type being sent at this instant
local lastCast, lastSpell, lastTime
local startedSpell, startedTime   -- a cast already announced at the click that started it
local offer, offered
local offerToken = 0

-------------------------------------------------------------------------------
-- The text
-------------------------------------------------------------------------------
--- Cuts a message to what chat takes, without splitting a character in two.
local function Clip(text)
    if #text <= MAX_LENGTH then return text end
    local cut = MAX_LENGTH
    local nextByte = text:byte(cut + 1)
    while cut > 0 and nextByte and nextByte >= 128 and nextByte < 192 do
        cut = cut - 1
        nextByte = text:byte(cut + 1)
    end
    return text:sub(1, cut)
end

--- A message with its placeholders filled in: {portal} is the destination,
--- {player} the Mage and {spell} the spell's full name. Anything else in
--- braces is left as it was typed. Colour codes and line breaks cannot be
--- sent in chat, so they are taken out.
function Announce:Format(template, place, spellName)
    local player = API.Str(UnitName("player")) or "Your Mage"
    local text = tostring(template or ""):gsub("{(%a+)}", function(word)
        word = word:lower()
        if word == "portal" or word == "destination" then return place end
        if word == "player" then return player end
        if word == "spell" then return spellName or place end
    end)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
    text = text:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return Clip(text)
end

--- Saves one of the two messages ("text" or "teleportText"). Emptied, it goes
--- back to the standard wording, so there is always something to say and
--- clearing the box is the way to get the standard text back.
function Announce:SetMessage(key, value)
    if type(value) ~= "string" or value:match("^%s*$") then
        value = MB.Config.defaults.announce[key]
    end
    MB.db.announce[key] = value
    MB:Fire("SETTINGS_CHANGED", "announce")
end

--- The message for one kind of cast, as the settings hold it. `typed` stands
--- in for the saved text while the player is still writing it.
local function Template(kind, typed)
    if typed then return typed end
    local db = MB.db.announce
    return (kind == "teleport") and db.teleportText or db.text
end

--- What would be said, for the settings to show: the first destination the
--- player has learned, or Stormwind when there is none yet.
function Announce:Preview(kind, typed)
    local list = (kind == "teleport") and Spells:GetTeleports() or Spells:GetPortals()
    local spell = list[1]
    local place = spell and spell.short or "Stormwind"
    local name = spell and spell.name or ((kind == "teleport") and "Teleport: Stormwind" or "Portal: Stormwind")
    return self:Format(Template(kind, typed), place, name)
end

-------------------------------------------------------------------------------
-- Where it can be said
-------------------------------------------------------------------------------
--- The chat type the chosen channel comes to at this moment, or nil when it
--- would reach nobody: party chat alone, raid chat outside a raid.
function Announce:ResolveChannel()
    -- Dungeons and raids have a channel of their own, the open world another.
    local inInstance = IsInInstance()
    local db = MB.db.announce
    local channel = (not MB.IsSecret(inInstance) and inInstance) and db.channelInstance or db.channelWorld
    if channel == "GROUP" then
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return nil
    end
    if channel == "RAID" then return IsInRaid() and "RAID" or nil end
    if channel == "PARTY" then return IsInGroup() and "PARTY" or nil end
    if channel == "YELL" then return "YELL" end
    return "SAY"
end

--- True while the client has chat messaging locked down for addons.
local function Locked()
    local info = C_ChatInfo
    if not (info and info.InChatMessagingLockdown) then return false end
    local ok, locked = pcall(info.InChatMessagingLockdown)
    if not ok or MB.IsSecret(locked) then return true end
    return locked and true or false
end

--- Whether a message of this type may be sent without the player clicking.
local function Unprompted(chatType)
    if refused[chatType] or Locked() then return false end
    if NEEDS_CLICK[chatType] then
        local inInstance = IsInInstance()
        if MB.IsSecret(inInstance) then return false end
        return inInstance and true or false
    end
    return true
end

-------------------------------------------------------------------------------
-- Saying it
-------------------------------------------------------------------------------
--- Sends one chat message. False when the client would not take it.
local function Send(text, chatType)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    if not send then return false end
    sending = chatType
    local ok = pcall(send, text, chatType)
    -- A refusal is reported while the call is still running, and clears this.
    local taken = ok and sending ~= nil
    sending = nil
    return taken
end

--- Puts the message in the chat box, for the player to send with Enter. That
--- is the player speaking, so it works whatever is locked down for addons.
local function OpenChat(text, chatType)
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
    if not open then return false end
    return (pcall(open, SLASH[chatType] .. text))
end

local function HideOffer()
    offered = nil
    offerToken = offerToken + 1
    if offer then offer:Hide() end
end

--- The click on the button: this is what the game wants before it will let a
--- message into /say or /yell.
local function TakeOffer()
    local what = offered
    HideOffer()
    if not what then return end
    if not Locked() and Send(what.text, what.chatType) then return end
    if not OpenChat(what.text, what.chatType) then
        MB:Notify("The game would not let that be announced here.", "warn")
    end
end

local function CreateOffer()
    offer = Theme:CreateButton(UIParent, "", 260, 26)
    offer:SetFrameStrata("HIGH")
    offer:SetPoint("TOP", UIParent, "TOP", 0, -232)
    offer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    offer:Hide()
    Theme:UseAccent(offer.label, "SetTextColor", 1)

    offer:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            HideOffer()
        else
            TakeOffer()
        end
    end)
    offer:SetScript("OnEnter", function(self)
        if not offered then return end
        Theme:ShowTooltip(self, "Announce in " .. WHERE[offered.chatType], offered.text,
            "Click to send it. Right-click to let it go.",
            "The game only lets an addon say this at your own click.")
    end)
    offer:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    Announce.offer = offer
end

--- Holds the announcement out as a button for a while.
local function Offer(text, chatType, place)
    if not offer then CreateOffer() end
    offered = { text = text, chatType = chatType }
    offer.label:SetText("Announce in " .. WHERE[chatType] .. ": " .. place)
    offer:SetWidth(math.max(180, offer.label:GetStringWidth() + 28))
    offer:Show()

    offerToken = offerToken + 1
    local token = offerToken
    C_Timer.After(OFFER_TIME, function()
        if token == offerToken then HideOffer() end
    end)
end

-------------------------------------------------------------------------------
-- The cast
-------------------------------------------------------------------------------
local function Rebuild()
    wipe(travel)
    wipe(byName)
    local function Add(list, kind)
        for i = 1, #list do
            local spell = list[i]
            local entry = { kind = kind, place = spell.short, name = spell.name }
            travel[spell.id] = entry
            if spell.name then byName[spell.name] = entry end
        end
    end
    Add(Spells:GetTeleports(), "teleport")
    Add(Spells:GetPortals(), "portal")
end

--- A spell of the player's has gone off. Only reached for the player's own
--- casts, and only for one that completed: a portal that was interrupted or
--- cancelled never gets here.
local function OnCast(_, _, castID, spellID)
    local db = MB.db.announce
    if not (db.enabled and MB:IsActive()) then return end

    spellID = API.Num(spellID)
    if not spellID then return end
    -- By ID, or by name when the cast reports a different ID for the same spell.
    local entry = travel[spellID] or byName[API.SpellName(spellID) or ""]
    if not entry then return end
    if entry.kind == "teleport" and not db.teleports then return end

    castID = API.Str(castID)
    local now = GetTime()

    -- Already said, at the click that started this cast. Destinations are
    -- compared, not IDs, since the cast may report another ID for the same
    -- spell; and the cast is noted, so a second report of it stays quiet too.
    if startedSpell and travel[startedSpell] == entry and now - startedTime < START_GUARD then
        startedSpell = nil
        lastCast, lastSpell, lastTime = castID, spellID, now
        return
    end

    -- Once per cast, however often the client reports it.
    if (castID and castID == lastCast) or (spellID == lastSpell and now - lastTime < REPEAT_GUARD) then
        return
    end
    lastCast, lastSpell, lastTime = castID, spellID, now

    local chatType = Announce:ResolveChannel()
    if not chatType then return end
    local text = Announce:Format(Template(entry.kind), entry.place, entry.name)
    if text == "" then return end

    if Unprompted(chatType) and Send(text, chatType) then return end
    Offer(text, chatType, entry.place)
end

--- Whether a cast clicked at this instant will actually begin. A click while
--- the spell or the global cooldown is still running, while another spell is
--- being cast, or while moving, casts nothing, and must announce nothing.
--- Where the client will not say, the answer is no: better a button to click
--- when the portal opens than words for a portal that never came.
local function CanStartNow(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if not ok or MB.IsSecret(info) then return false end
        local active = type(info) == "table" and info.isActive
        if type(active) == "boolean" and not MB.IsSecret(active) then
            -- Said outright, and readable where the duration is withheld.
            if active then return false end
        elseif type(info) == "table" then
            local duration = info.duration
            if MB.IsSecret(duration) then return false end
            if type(duration) == "number" and duration > 0 then return false end
        end
    end
    if UnitCastingInfo and UnitCastingInfo("player") then return false end
    if UnitChannelInfo and UnitChannelInfo("player") then return false end
    if IsPlayerMoving and IsPlayerMoving() then return false end
    return true
end

--- A destination has just been clicked in MageButler's own menu, and this is
--- still inside that click. With "as I start casting" switched on, this is
--- where /say and /yell are said out in the world: it is the only moment the
--- game allows it without a second click. The price is that the cast has not
--- finished, so if it then fails the words are already out. Wherever the game
--- lets the announcement wait for the portal, it still waits.
function Announce:OnTravelClick(spellID)
    local db = MB.db.announce
    if not (db.enabled and db.atStart and MB:IsActive()) then return end
    local entry = travel[spellID]
    if not entry or (entry.kind == "teleport" and not db.teleports) then return end

    local chatType = self:ResolveChannel()
    if not (chatType and NEEDS_CLICK[chatType]) or Locked() then return end
    local inInstance = IsInInstance()
    if MB.IsSecret(inInstance) or inInstance then return end

    -- Not for a cast that plainly cannot start, nor twice for one cast.
    local now = GetTime()
    if startedSpell == spellID and now - startedTime < START_GUARD then return end
    if MB.inventoryKnown and MB.Reagents:Count(entry.kind == "portal" and "runeP" or "runeT") <= 0 then return end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, spellID)
        if ok and not MB.IsSecret(usable) and usable == false then return end
    end
    if not CanStartNow(spellID) then return end

    local template = (entry.kind == "teleport") and db.teleportText or db.startText
    local text = self:Format(template, entry.place, entry.name)
    if text ~= "" and Send(text, chatType) then
        startedSpell, startedTime = spellID, now
    end
end

-------------------------------------------------------------------------------
function Announce:OnEnable()
    Theme, Spells = MB.Theme, MB.Spells
    Rebuild()

    MB:On("SPELLS_UPDATED", Rebuild)
    MB:RegisterPlayerEvent("UNIT_SPELLCAST_SUCCEEDED", OnCast)

    -- The client refusing a send that was not the player's own click. The
    -- message goes on offer instead, and that channel is not tried again
    -- unprompted this session.
    local function OnBlocked(_, addon)
        if sending and not MB.IsSecret(addon) and addon == ADDON_NAME then
            refused[sending] = true
            sending = nil
        end
    end
    MB:RegisterEvent("ADDON_ACTION_BLOCKED", OnBlocked)
    MB:RegisterEvent("ADDON_ACTION_FORBIDDEN", OnBlocked)

    -- An offer is for the place and the settings it was made under: a change
    -- to the announcements withdraws it, and so does a loading screen.
    MB:On("SETTINGS_CHANGED", function(section)
        if offered and (section == "announce" or section == "all"
            or not (MB.db.announce.enabled and MB:IsActive())) then
            HideOffer()
        end
    end)
    MB:RegisterEvent("LOADING_SCREEN_ENABLED", HideOffer)
    MB:RegisterEvent("PLAYER_LEAVING_WORLD", HideOffer)
end
