local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Clan Hub & DBM-style Peer Version Check provider.
-- Features:
--   1. Shared Clan Status Tags (opt-in GUILD addon messaging, strictly rate-limited).
--   2. Guild Event Calls & Dungeon/Raid Signups (opt-in GUILD addon messaging).
--   3. Passive rate-limited Peer Version Detection (VH/VR on GUILD/group, toggleable).
-- Every outgoing message respects InCombatLockdown(), InChatMessagingLockdown(),
-- AreOutgoingAddonChatMessagesRestricted(), MAX_PAYLOAD_BYTES, and throttle circuit-breakers.
local Clan = {
    PREFIX = "SCentral1",
    MIN_SEND_INTERVAL = 5,
    VERSION_MIN_INTERVAL = 60,
    MAX_PAYLOAD_BYTES = 240,
    lastSyncSentAt = 0,
    lastVersionSentAt = 0,
    lastReqReplyAt = 0,
    isStoppedThisSession = false,
    throttledCount = 0,
    latestRemoteVersion = nil,
    latestReportedBy = nil,
    notifiedVersion = nil,
}

Clan.STATUS_TAGS = {
    { id = "NONE", labelKey = "No Status" },
    { id = "LFG", labelKey = "LFG (Looking for Group)" },
    { id = "MPLUS", labelKey = "Mythic+ / Dungeons" },
    { id = "RAID", labelKey = "Raid Ready" },
    { id = "PVP", labelKey = "PvP / Arena" },
    { id = "LEVELING", labelKey = "Leveling / Questing" },
    { id = "CRAFTING", labelKey = "Crafting / Professions" },
    { id = "BUSY", labelKey = "Busy" },
}

Clan.EVENT_CATEGORIES = {
    { id = "DUNGEON", labelKey = "Dungeon / M+" },
    { id = "RAID", labelKey = "Raid" },
    { id = "BOSS", labelKey = "World Boss" },
    { id = "PVP", labelKey = "PvP" },
    { id = "GUILD", labelKey = "Guild Event" },
}

Clan.ROLES = { "TANK", "HEALER", "DPS", "MAYBE", "DECLINE" }

Clan.PROFESSIONS = {
    { id = "NONE", labelKey = "None" },
    { id = "ALCHEMY", labelKey = "Alchemy" },
    { id = "BLACKSMITHING", labelKey = "Blacksmithing" },
    { id = "ENCHANTING", labelKey = "Enchanting" },
    { id = "ENGINEERING", labelKey = "Engineering" },
    { id = "HERBALISM", labelKey = "Herbalism" },
    { id = "INSCRIPTION", labelKey = "Inscription" },
    { id = "JEWELCRAFTING", labelKey = "Jewelcrafting" },
    { id = "LEATHERWORKING", labelKey = "Leatherworking" },
    { id = "MINING", labelKey = "Mining" },
    { id = "SKINNING", labelKey = "Skinning" },
    { id = "TAILORING", labelKey = "Tailoring" },
    { id = "COOKING", labelKey = "Cooking" },
}

Clan.guildChatLFG = {}

local function IsValidProfession(profId)
    for _, item in ipairs(Clan.PROFESSIONS) do
        if item.id == profId then return true end
    end
    return false
end

ns.Clan = Clan
table.insert(ns.modules, Clan)

local function IsValidTag(tagId)
    for _, item in ipairs(Clan.STATUS_TAGS) do
        if item.id == tagId then return true end
    end
    return false
end

local function IsValidCategory(catId)
    for _, item in ipairs(Clan.EVENT_CATEGORIES) do
        if item.id == catId then return true end
    end
    return false
end

local function IsValidRole(roleId)
    for _, r in ipairs(Clan.ROLES) do
        if r == roleId then return true end
    end
    return false
end

local function IsSaneRemoteSemVer(ver)
    if type(ver) ~= "string" then return false end
    local maj, min, pat = ver:match("^(%d+)%.(%d+)%.(%d+)$")
    if not maj then return false end
    return (tonumber(maj) or 999) <= 50 and (tonumber(min) or 999) <= 999 and (tonumber(pat) or 999) <= 999
end

local function SplitTilde(str)
    local out = {}
    local start = 1
    while true do
        local pos = str:find("~", start, true)
        if not pos then
            table.insert(out, str:sub(start))
            break
        end
        table.insert(out, str:sub(start, pos - 1))
        start = pos + 1
    end
    return out
end

function Clan:IsMessagingLocked()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return true
    end
    if not C_ChatInfo then return true end
    for _, checkName in ipairs({ "AreOutgoingAddonChatMessagesRestricted", "InChatMessagingLockdown" }) do
        local fn = C_ChatInfo[checkName]
        if type(fn) == "function" then
            local ok, locked = pcall(fn)
            if ok and locked == true then return true end
        end
    end
    return false
end

local function TransmitAddonMessage(self, payload, channel, isVersionMsg)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    if channel == "GUILD" and not (IsInGuild and IsInGuild()) then return false end
    if type(payload) ~= "string" or payload == "" or #payload > self.MAX_PAYLOAD_BYTES then return false end
    if payload:find("[%c|]") then return false end

    local now = GetTime()
    if isVersionMsg then
        if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then
            return false
        end
        if (now - (self.lastVersionSentAt or 0)) < self.VERSION_MIN_INTERVAL then
            return false
        end
        self.lastVersionSentAt = now
    else
        if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            return false
        end
        if channel ~= "GUILD" then
            return false
        end
        if (now - (self.lastSyncSentAt or 0)) < self.MIN_SEND_INTERVAL then
            return false
        end
        self.lastSyncSentAt = now
    end

    local ok, result = pcall(C_ChatInfo.SendAddonMessage, self.PREFIX, payload, channel)
    if not ok then return false end

    if Enum and Enum.SendAddonMessageResult and type(result) == "number" then
        for name, value in pairs(Enum.SendAddonMessageResult) do
            if value == result and name:find("Throttle") then
                self.throttledCount = self.throttledCount + 1
                if self.throttledCount >= 3 then
                    self.isStoppedThisSession = true
                end
                return false
            end
        end
    end
    return true
end

function Clan:SendGuildSync(payload)
    return TransmitAddonMessage(self, payload, "GUILD", false)
end

local function GetActiveGroupChannel()
    if not (IsInGroup and IsInGroup()) then return nil end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    return "PARTY"
end

function Clan:SendVersionHello(preferChannel)
    if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then return false end
    if not IsSaneRemoteSemVer(ns.version) then return false end

    local channel = preferChannel
    if not channel then
        if IsInGuild and IsInGuild() then
            channel = "GUILD"
        else
            channel = GetActiveGroupChannel()
        end
    end
    if not channel then return false end

    return TransmitAddonMessage(self, "VH~" .. ns.version, channel, true)
end

local function ProcessPeerVersion(senderDisplay, senderLookupKey, remoteVer, chatType)
    if not IsSaneRemoteSemVer(remoteVer) then return end

    if chatType == "GUILD" and IsInGuild and IsInGuild() then
        local bucket = Store:GetClanScopeData()
        local peer = bucket.peers[senderLookupKey] or { displayName = senderDisplay, lookupKey = senderLookupKey }
        peer.displayName = senderDisplay
        peer.version = remoteVer
        peer.updatedAt = time()
        bucket.peers[senderLookupKey] = peer
    end

    if IsSaneRemoteSemVer(ns.version) and Compat.CompareSemVer(remoteVer, ns.version) > 0 then
        if not Clan.latestRemoteVersion or Compat.CompareSemVer(remoteVer, Clan.latestRemoteVersion) > 0 then
            Clan.latestRemoteVersion = remoteVer
            Clan.latestReportedBy = senderDisplay
        end
        if Clan.notifiedVersion ~= remoteVer then
            Clan.notifiedVersion = remoteVer
            local linkText = "|Haddon:SCentral:update|h|cff35c4ff[" .. L["GitHub Releases"] .. "]|r|h"
            ns:Print(L["New version v%s detected (you have v%s)! Click %s to update."]:format(remoteVer, ns.version, linkText))
            ns:Emit("VERSION_UPDATE_FOUND", remoteVer)
        end
    end
end

local function EnsureEventRecord(bucket, eventId)
    local evt = bucket.events[eventId]
    if evt and type(evt.signups) ~= "table" then
        evt.signups = {}
    end
    return evt
end

function Clan:SetMyStatus(tagId, note)
    if not IsValidTag(tagId) then tagId = "NONE" end
    local bucket = Store:GetClanScopeData()
    local cleanNote = Compat.CleanPayloadField(note or "", 36)
    bucket.myTag = tagId
    bucket.myNote = cleanNote

    local sent = self:SendGuildSync("TAG~" .. (ns.version or "0.2.0") .. "~" .. tagId .. "~" .. cleanNote)
    if (ns.db and ns.db.settings and ns.db.settings.clanSync) and not sent and IsInGuild and IsInGuild() then
        local waitRem = math.ceil(math.max(0, self.MIN_SEND_INTERVAL - (GetTime() - (self.lastSyncSentAt or 0))))
        if waitRem > 0 then
            ns:Print(L["Status saved locally; guild broadcast ready in %ds."]:format(waitRem))
        end
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:CreateEventCall(category, title, whenText, needT, needH, needD, minLvl)
    if not IsValidCategory(category) then category = "DUNGEON" end
    local cleanTitle = Compat.CleanPayloadField(title or "", 40)
    if cleanTitle == "" then
        ns:Print(L["Enter a valid title for the Clan event."])
        return false
    end
    local cleanWhen = Compat.CleanPayloadField(whenText or "", 24)
    if cleanWhen == "" then cleanWhen = L["Now"] end

    local nT = math.max(0, math.min(5, tonumber(needT) or 0))
    local nH = math.max(0, math.min(10, tonumber(needH) or 0))
    local nD = math.max(0, math.min(30, tonumber(needD) or 0))
    local nMinLvl = math.max(0, math.min(100, tonumber(minLvl) or 0))

    local myName = Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local parsed = Compat.ParseCharacterName(myName)
    local shortTag = (parsed and parsed.firstName or "me"):sub(1, 6):lower()
    local eventId = shortTag .. "-" .. tostring(time() % 100000)

    local bucket = Store:GetClanScopeData()
    local myParsed = Compat.ParseCharacterName(myName)
    local _, myClass = Safe.Call(UnitClass, "player")
    bucket.events[eventId] = {
        id = eventId,
        category = category,
        title = cleanTitle,
        whenText = cleanWhen,
        needT = nT,
        needH = nH,
        needD = nD,
        minLvl = nMinLvl,
        isOpen = true,
        creator = (myParsed and myParsed.displayName) or myName,
        creatorKey = (myParsed and myParsed.lookupKey) or shortTag,
        createdAt = time(),
        updatedAt = time(),
        signups = {
            [(myParsed and myParsed.lookupKey) or shortTag] = {
                name = (myParsed and myParsed.displayName) or myName,
                classFile = Safe.String(myClass),
                role = "DPS",
                updatedAt = time(),
            },
        },
    }

    local payload = ("EVT~%s~%s~%s~%s~%d~%d~%d~%d~1"):format(eventId, category, cleanTitle, cleanWhen, nT, nH, nD, nMinLvl)
    self:SendGuildSync(payload)
    ns:Emit("CLAN_UPDATED")
    return true, bucket.events[eventId]
end

function Clan:ToggleEventOpen(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local myName = Safe.String(Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    if not (myParsed and evt.creatorKey == myParsed.lookupKey) then
        ns:Print(L["Only the group creator can open or close this Clan listing."])
        return false
    end
    evt.isOpen = evt.isOpen == false
    evt.updatedAt = time()
    self:SendGuildSync(("EVS~%s~%s"):format(Compat.CleanPayloadField(eventId, 16), evt.isOpen and "1" or "0"))
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:ReannounceEvent(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local payload = ("EVT~%s~%s~%s~%s~%d~%d~%d~%d~%s"):format(
        Compat.CleanPayloadField(evt.id, 16),
        evt.category or "DUNGEON",
        Compat.CleanPayloadField(evt.title or "", 40),
        Compat.CleanPayloadField(evt.whenText or L["Now"], 24),
        tonumber(evt.needT) or 0,
        tonumber(evt.needH) or 0,
        tonumber(evt.needD) or 0,
        tonumber(evt.minLvl) or 0,
        evt.isOpen ~= false and "1" or "0"
    )
    local sent = self:SendGuildSync(payload)
    if not sent then
        ns:Print(L["Clan sync throttled or blocked during combat."])
        return false
    end
    evt.updatedAt = time()
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:SetMyProfessions(prof1, prof2, craftNote)
    if not IsValidProfession(prof1) then prof1 = "NONE" end
    if not IsValidProfession(prof2) then prof2 = "NONE" end
    local bucket = Store:GetClanScopeData()
    local cleanNote = Compat.CleanPayloadField(craftNote or "", 40)
    bucket.myProf1 = prof1
    bucket.myProf2 = prof2
    bucket.myCraftNote = cleanNote

    local sent = self:SendGuildSync(("PRF~%s~%s~%s"):format(prof1, prof2, cleanNote))
    if (ns.db and ns.db.settings and ns.db.settings.clanSync) and not sent and IsInGuild and IsInGuild() then
        local waitRem = math.ceil(math.max(0, self.MIN_SEND_INTERVAL - (GetTime() - (self.lastSyncSentAt or 0))))
        if waitRem > 0 then
            ns:Print(L["Professions saved locally; guild broadcast ready in %ds."]:format(waitRem))
        end
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:SignupEvent(eventId, role)
    if not IsValidRole(role) then return false end
    local bucket = Store:GetClanScopeData()
    local evt = EnsureEventRecord(bucket, eventId)
    if not evt then return false end

    local myName = Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local myParsed = Compat.ParseCharacterName(myName)
    if not myParsed then return false end
    local _, myClass = Safe.Call(UnitClass, "player")

    if role == "DECLINE" then
        evt.signups[myParsed.lookupKey] = nil
    else
        evt.signups[myParsed.lookupKey] = {
            name = myParsed.displayName,
            classFile = Safe.String(myClass),
            role = role,
            updatedAt = time(),
        }
    end
    evt.updatedAt = time()

    self:SendGuildSync(("SIG~%s~%s~%s"):format(Compat.CleanPayloadField(eventId, 16), role, Safe.String(myClass) or ""))
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:RemoveEvent(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local myName = Safe.String(Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    local isCreator = myParsed and evt.creatorKey == myParsed.lookupKey

    bucket.events[eventId] = nil
    if isCreator then
        self:SendGuildSync("DEL~" .. Compat.CleanPayloadField(eventId, 16))
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:RequestClanSync()
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        ns:Print(L["Enable Clan guild sync (opt-in) in Settings or above to sync with guildmates."])
        return false
    end
    if not (IsInGuild and IsInGuild()) then
        ns:Print(L["No guild"])
        return false
    end
    local bucket = Store:GetClanScopeData()
    local tag = IsValidTag(bucket.myTag) and bucket.myTag or "NONE"
    local note = Compat.CleanPayloadField(bucket.myNote or "", 36)
    local p1 = IsValidProfession(bucket.myProf1) and bucket.myProf1 or "NONE"
    local p2 = IsValidProfession(bucket.myProf2) and bucket.myProf2 or "NONE"
    local cNote = Compat.CleanPayloadField(bucket.myCraftNote or "", 40)
    local sent = self:SendGuildSync(("REQ~%s~%s~%s~%s~%s~%s"):format(ns.version or "0.2.2", tag, note, p1, p2, cNote))
    if not sent then
        ns:Print(L["Clan sync throttled or blocked during combat."])
        return false
    end
    return true
end

function Clan:GetPeersList()
    local bucket = Store:GetClanScopeData()
    local liveByLookup = {}
    if ns.Social then
        for _, row in ipairs(ns.Social:GetList("guild")) do
            if row.lookupKey then
                liveByLookup[row.lookupKey] = row
            end
        end
    end

    local out = {}
    for key, peer in pairs(bucket.peers) do
        local live = liveByLookup[key]
        table.insert(out, {
            lookupKey = key,
            displayName = (live and live.displayName) or peer.displayName or key,
            version = peer.version,
            tag = IsValidTag(peer.tag) and peer.tag or "NONE",
            note = peer.note or "",
            level = live and live.level,
            classFile = live and live.classFile,
            area = live and live.area or "",
            online = live ~= nil,
            updatedAt = peer.updatedAt or 0,
        })
    end

    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.updatedAt or 0) > (b.updatedAt or 0)
    end)
    return out
end

function Clan:GetEventsList(filterId)
    local bucket = Store:GetClanScopeData()
    local out = {}
    for _, evt in pairs(bucket.events) do
        local include = true
        if filterId and filterId ~= "all" then
            if filterId == "open" then
                include = evt.isOpen ~= false
            elseif filterId == "need_tank" then
                local sum = self:GetSignupSummary(evt)
                include = evt.isOpen ~= false and (tonumber(evt.needT) or 0) > sum.TANK
            elseif filterId == "need_heal" then
                local sum = self:GetSignupSummary(evt)
                include = evt.isOpen ~= false and (tonumber(evt.needH) or 0) > sum.HEALER
            else
                include = evt.category == filterId
            end
        end
        if include then
            table.insert(out, evt)
        end
    end
    table.sort(out, function(a, b)
        local aOpen = a.isOpen ~= false
        local bOpen = b.isOpen ~= false
        if aOpen ~= bOpen then return aOpen end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return out
end

function Clan:GetProfessionsList(query)
    local bucket = Store:GetClanScopeData()
    local out = {}
    local q = type(query) == "string" and query ~= "" and query:lower() or nil

    local function PushEntry(lookupKey, displayName, prof1, prof2, note, isSelf, classFile, updatedAt)
        if (not prof1 or prof1 == "NONE") and (not prof2 or prof2 == "NONE") and (not note or note == "") then
            return
        end
        if q then
            local p1Label = (L[prof1] or prof1 or ""):lower()
            local p2Label = (L[prof2] or prof2 or ""):lower()
            local hay = ((displayName or "") .. " " .. p1Label .. " " .. p2Label .. " " .. (note or "")):lower()
            if not hay:find(q, 1, true) then
                return
            end
        end
        table.insert(out, {
            lookupKey = lookupKey,
            displayName = displayName,
            prof1 = prof1 or "NONE",
            prof2 = prof2 or "NONE",
            craftNote = note or "",
            isSelf = isSelf,
            classFile = classFile,
            updatedAt = updatedAt,
        })
    end

    local myName = Safe.String(Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    local _, myClass = Safe.Call(UnitClass, "player")
    PushEntry(myParsed and myParsed.lookupKey or "me", myParsed and myParsed.displayName or "Me", bucket.myProf1, bucket.myProf2, bucket.myCraftNote, true, Safe.String(myClass), time())

    for key, peer in pairs(bucket.peers) do
        PushEntry(key, peer.displayName or key, peer.prof1, peer.prof2, peer.craftNote, false, peer.classFile, peer.updatedAt)
    end

    table.sort(out, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        return (a.displayName or "") < (b.displayName or "")
    end)
    return out
end

function Clan:GetGuildChatLFGList()
    local now = time()
    local out = {}
    for i = #self.guildChatLFG, 1, -1 do
        local row = self.guildChatLFG[i]
        if (now - (row.timestamp or 0)) > 900 then
            table.remove(self.guildChatLFG, i)
        else
            table.insert(out, row)
        end
    end
    return out
end

function Clan:GetSignupSummary(evt)
    local counts = { TANK = 0, HEALER = 0, DPS = 0, MAYBE = 0 }
    local signups = {}
    if evt and type(evt.signups) == "table" then
        for key, s in pairs(evt.signups) do
            if type(s) == "table" and counts[s.role] ~= nil then
                counts[s.role] = counts[s.role] + 1
                table.insert(signups, {
                    key = key,
                    name = s.name or key,
                    classFile = s.classFile,
                    role = s.role,
                })
            end
        end
    end
    table.sort(signups, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    counts.signups = signups
    return counts
end

local function OnAddonMessage(_, _, prefix, text, chatType, sender)
    if prefix ~= Clan.PREFIX then return end
    if chatType ~= "GUILD" and chatType ~= "PARTY" and chatType ~= "RAID" and chatType ~= "INSTANCE_CHAT" then
        return
    end

    local cleanText = Safe.String(text)
    local cleanSender = Safe.String(sender)
    if not cleanText or not cleanSender or cleanText:find("%c") or cleanText:find("|", 1, true) then
        return
    end
    if Compat.IsMe(cleanSender) then return end

    local parsed = Compat.ParseCharacterName(cleanSender)
    if not parsed then return end

    local parts = SplitTilde(cleanText)
    local cmd = parts[1]

    -- Version discovery packets (allowed for PARTY/RAID/INSTANCE_CHAT/GUILD when versionCheck ~= false)
    if cmd == "VH" or cmd == "VR" then
        if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then return end
        local remoteVer = parts[2]
        ProcessPeerVersion(parsed.displayName, parsed.lookupKey, remoteVer, chatType)

        if cmd == "VH" and IsSaneRemoteSemVer(ns.version) and IsSaneRemoteSemVer(remoteVer) and Compat.CompareSemVer(ns.version, remoteVer) >= 0 then
            local delay = 1.5 + math.random() * 2.5
            local targetChannel = chatType
            if targetChannel == "GUILD" and GetNumGuildMembers then
                local _, online = GetNumGuildMembers()
                local chances = math.max(1, math.ceil((Safe.Number(online) or 1) / 40))
                if math.random(1, chances) ~= 1 then
                    return
                end
            end
            C_Timer.After(delay, function()
                TransmitAddonMessage(Clan, "VR~" .. ns.version, targetChannel, true)
            end)
        end
        if chatType == "GUILD" then ns:Emit("CLAN_UPDATED") end
        return
    end

    -- Legacy PING support
    if cmd and cmd:find("^PING:") then
        if chatType ~= "GUILD" or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return end
        local ver = cmd:match("^PING:(.*)$")
        ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, chatType)
        ns:Emit("CLAN_UPDATED")
        return
    end

    -- All Clan Hub interactive features require GUILD + explicit clanSync opt-in.
    if chatType ~= "GUILD" or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        return
    end

    local bucket = Store:GetClanScopeData()
    local now = time()

    if cmd == "TAG" or cmd == "REQ" then
        local ver, tagId, note = parts[2], parts[3], Compat.CleanPayloadField(parts[4] or "", 36)
        local peer = bucket.peers[parsed.lookupKey] or {}
        peer.displayName = parsed.displayName
        peer.lookupKey = parsed.lookupKey
        if IsSaneRemoteSemVer(ver) then
            peer.version = ver
            ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, "GUILD")
        end
        peer.tag = IsValidTag(tagId) and tagId or "NONE"
        peer.note = note
        if parts[5] and IsValidProfession(parts[5]) then peer.prof1 = parts[5] end
        if parts[6] and IsValidProfession(parts[6]) then peer.prof2 = parts[6] end
        if parts[7] ~= nil then peer.craftNote = Compat.CleanPayloadField(parts[7], 40) end
        peer.updatedAt = now
        bucket.peers[parsed.lookupKey] = peer
        ns:Emit("CLAN_UPDATED")

        if cmd == "REQ" and (GetTime() - (Clan.lastReqReplyAt or 0)) >= 15 then
            Clan.lastReqReplyAt = GetTime()
            local replyDelay = 0.8 + math.random() * 2.2
            C_Timer.After(replyDelay, function()
                local b = Store:GetClanScopeData()
                local myTag = IsValidTag(b.myTag) and b.myTag or "NONE"
                local myNote = Compat.CleanPayloadField(b.myNote or "", 36)
                local p1 = IsValidProfession(b.myProf1) and b.myProf1 or "NONE"
                local p2 = IsValidProfession(b.myProf2) and b.myProf2 or "NONE"
                local cNote = Compat.CleanPayloadField(b.myCraftNote or "", 40)
                Clan:SendGuildSync(("TAG~%s~%s~%s~%s~%s~%s"):format(ns.version or "0.2.2", myTag, myNote, p1, p2, cNote))
            end)
        end

    elseif cmd == "EVT" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local cat = parts[3]
        local title = Compat.CleanPayloadField(parts[4] or "", 40)
        local whenText = Compat.CleanPayloadField(parts[5] or "", 24)
        local nT = math.max(0, math.min(5, tonumber(parts[6]) or 0))
        local nH = math.max(0, math.min(10, tonumber(parts[7]) or 0))
        local nD = math.max(0, math.min(30, tonumber(parts[8]) or 0))
        local nMinLvl = math.max(0, math.min(100, tonumber(parts[9]) or 0))
        local isOpen = parts[10] ~= "0"
        if eventId ~= "" and IsValidCategory(cat) and title ~= "" then
            local existing = bucket.events[eventId]
            bucket.events[eventId] = {
                id = eventId,
                category = cat,
                title = title,
                whenText = whenText ~= "" and whenText or L["Now"],
                needT = nT,
                needH = nH,
                needD = nD,
                minLvl = nMinLvl,
                isOpen = isOpen,
                creator = parsed.displayName,
                creatorKey = parsed.lookupKey,
                createdAt = existing and existing.createdAt or now,
                updatedAt = now,
                signups = existing and existing.signups or {},
            }
            ns:Emit("CLAN_UPDATED")
        end

    elseif cmd == "EVS" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local evt = bucket.events[eventId]
        if evt and evt.creatorKey == parsed.lookupKey then
            evt.isOpen = parts[3] ~= "0"
            evt.updatedAt = now
            ns:Emit("CLAN_UPDATED")
        end

    elseif cmd == "PRF" then
        local p1, p2, cNote = parts[2], parts[3], Compat.CleanPayloadField(parts[4] or "", 40)
        local peer = bucket.peers[parsed.lookupKey] or {
            displayName = parsed.displayName,
            lookupKey = parsed.lookupKey,
            tag = "NONE",
            note = "",
        }
        peer.prof1 = IsValidProfession(p1) and p1 or "NONE"
        peer.prof2 = IsValidProfession(p2) and p2 or "NONE"
        peer.craftNote = cNote
        peer.updatedAt = now
        bucket.peers[parsed.lookupKey] = peer
        ns:Emit("CLAN_UPDATED")

    elseif cmd == "SIG" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local role = parts[3]
        local classFile = Compat.CleanPayloadField(parts[4] or "", 16)
        local evt = EnsureEventRecord(bucket, eventId)
        if evt and IsValidRole(role) then
            if role == "DECLINE" then
                evt.signups[parsed.lookupKey] = nil
            else
                evt.signups[parsed.lookupKey] = {
                    name = parsed.displayName,
                    classFile = classFile ~= "" and classFile or nil,
                    role = role,
                    updatedAt = now,
                }
            end
            evt.updatedAt = now
            ns:Emit("CLAN_UPDATED")
        end

    elseif cmd == "DEL" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local evt = bucket.events[eventId]
        if evt and evt.creatorKey == parsed.lookupKey then
            bucket.events[eventId] = nil
            ns:Emit("CLAN_UPDATED")
        end
    end
end

local LFG_PATTERNS = {
    "%flfm%f", "%flfg%f", "lf%d+m", "precis", "falta", "procuro", "busco",
    "tank", "heal", "dps", "%fdg%f", "masmorra", "dungeon", "raid", "raide", "boss",
}

local function OnGuildChatPassive(_, _, text, sender)
    if not (ns.db and ns.db.settings and ns.db.settings.guildChatFinder) then return end
    local cleanMsg = Safe.String(text)
    local cleanSender = Safe.String(sender)
    if not cleanMsg or not cleanSender then return end
    cleanMsg = Compat.CleanInput(cleanMsg)
    local parsed = Compat.ParseCharacterName(cleanSender)
    if not cleanMsg or not parsed then return end

    local low = cleanMsg:lower()
    local matched = false
    for _, pat in ipairs(LFG_PATTERNS) do
        if low:find(pat) then
            matched = true
            break
        end
    end
    if not matched then return end

    for i = #Clan.guildChatLFG, 1, -1 do
        if Clan.guildChatLFG[i].lookupKey == parsed.lookupKey then
            table.remove(Clan.guildChatLFG, i)
        end
    end
    table.insert(Clan.guildChatLFG, 1, {
        lookupKey = parsed.lookupKey,
        sender = parsed.displayName,
        displayName = parsed.displayName,
        text = cleanMsg:sub(1, 120),
        timestamp = time(),
        ts = time(),
    })
    while #Clan.guildChatLFG > 12 do
        table.remove(Clan.guildChatLFG)
    end
    ns:Emit("CLAN_UPDATED")
end

function Clan:ApplyAutoInstanceStatus()
    if not (ns.db and ns.db.settings and ns.db.settings.autoStatusInstance) then return end
    if self:IsMessagingLocked() then return end
    local inInst, instType = Safe.Call(IsInInstance)
    local bucket = Store:GetClanScopeData()
    if inInst ~= true then
        if self._didAutoBusyTag then
            self._didAutoBusyTag = false
            bucket.myTag = "NONE"
            ns:Emit("CLAN_UPDATED")
        end
        return
    end
    local autoTag
    if instType == "party" then
        autoTag = "MPLUS"
    elseif instType == "raid" then
        autoTag = "RAID"
    elseif instType == "pvp" or instType == "arena" then
        autoTag = "PVP"
    end
    if not autoTag then return end
    if bucket.myTag == autoTag then return end
    self._didAutoBusyTag = true
    bucket.myTag = autoTag
    if ns.db.settings.clanSync and (GetTime() - (self.lastSyncSentAt or 0)) >= self.VERSION_MIN_INTERVAL then
        self:SendGuildSync(("TAG~%s~%s~%s"):format(ns.version or "0.2.2", autoTag, Compat.CleanPayloadField(bucket.myNote or "", 36)))
    end
    ns:Emit("CLAN_UPDATED")
end

function Clan:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, self.PREFIX)
    end
    ns.RegisterEvent(self, "CHAT_MSG_ADDON", OnAddonMessage)
    ns.RegisterEvent(self, "CHAT_MSG_GUILD", OnGuildChatPassive)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        C_Timer.After(6, function()
            Clan:SendVersionHello()
            Clan:ApplyAutoInstanceStatus()
        end)
    end)
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", function()
        local grpChan = GetActiveGroupChannel()
        if grpChan then
            C_Timer.After(4, function()
                Clan:SendVersionHello(grpChan)
            end)
        end
    end)
end
