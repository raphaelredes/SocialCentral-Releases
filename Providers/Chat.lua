local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Unified Conversations Hub, Verified In-Addon Direct Chat, and Addon Private Chat Rooms.
-- Security guarantees:
--   - Respects 16001 / 12.x Secret Values on all chat & addon events.
--   - Never calls SendChatMessage or BNSendWhisper (non-addon replies safely pre-open Blizzard chat).
--   - Never stores BattleTag / Real ID or BN_WHISPER history in SavedVariables.
--   - Addon messaging (SCentral1 RM/RMI/RMJ/RML/DPING/DPONG/DM/DMA/DPIN) obeys IsMessagingLocked(),
--     combat guards, per-peer verification, Enum.SendAddonMessageResult throttles, and 240B limit.
local Chat = {
    threads = {},
    roomBNetTargets = {},
    sessionPeers = {},
    sessionBNetPeers = {},
    resolvedWhisperTargets = {},
    rejectedWhisperTargets = {},
    probeAttemptIndex = {},
    lastProbeCandidate = {},
    seenOnlineChars = {},
    sessionOfflineChars = {},
    sessionUnverifiedPeers = {},
    knownFullByFirst = {},
    knownFactionByKey = {},
    pendingProbes = {},
    pendingOfficialOpen = {},
    probeSentAt = {},
    pongSentAt = {},
    nackSentAt = {},
    seenAllianceMsgs = {},
    deliveryIndex = {},
    msgSeq = 0,
    lastRoomSendAt = 0,
    lastDirectSendAt = 0,
    lastChimeAt = 0,
    lastChimeBySender = {},
    _lastChimeSenderCount = 0,
    activeTempChannel = nil,
    _unreadDirty = true,
    _unreadDirectCache = 0,
    _unreadSummaryDirty = true,
    _unreadSummaryCache = nil,
    _unreadSummaryChanFlag = false,
    _peerStateGen = 0,
    _lastCandidateTrackAt = 0,
    _lastDirectDedupPruneAt = 0,
    _lastAllianceDedupPruneAt = 0,
}

ns.Chat = Chat
table.insert(ns.modules, Chat)

local PREFIX = "SCentral1"
local MAX_THREAD_LINES = 300
local MAX_SAVED_WHISPERS = 2000
local MAX_ROOM_MEMBERS = 12
local MAX_PAYLOAD_BYTES = 240
local ROOM_SEND_COOLDOWN = 1.2
local DIRECT_SEND_COOLDOWN = 0.8
local PING_COOLDOWN = 6
local PONG_COOLDOWN = 6
local NACK_COOLDOWN = 8
local SOUND_COOLDOWN = 3.0
local DEFAULT_SOUND_COOLDOWN = 6.0
local PING_TIMEOUT = 5.0
local HISTORY_TTL_SECONDS = nil -- keep Conversations history indefinitely unless explicitly cleared by the user
local MAX_SAVED_THREADS = 2000
local PEER_TTL_SECONDS = nil    -- preserve verified [SC] peer records across breaks
local MAX_SAVED_PEERS = 1500
local DISCOVERY_PING_INTERVAL = 2.5
local BNET_CACHE_TTL = 4.0
local function BuildNotFoundPattern(tmpl)
    if type(tmpl) ~= "string" or tmpl == "" or not tmpl:find("%", 1, true) then
        return nil
    end
    local escaped = tmpl:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    local pat = escaped:gsub("%%%%%d*%$?[sd]", ".*")
    if pat == "" or pat == ".*" then
        return nil
    end
    return "^" .. pat
end

local ERR_NOT_FOUND_PATTERN = BuildNotFoundPattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S)

local STATIC_NONE_STATE = { state = "none", verified = false }
local STATIC_ROOM_STATE = { state = "room", verified = true }
local STATIC_ALLIANCE_STATE = { state = "alliance", verified = true, slash = "/al " }
local STATIC_DISABLED_STATE = { state = "disabled", verified = false }

function Chat:InvalidateUnreadCache()
    self._unreadDirty = true
    self._unreadSummaryDirty = true
end

function Chat:BumpPeerStateGen()
    self._peerStateGen = (self._peerStateGen or 0) + 1
end

local STATIC_CHANNEL_ORDER = {
    ["ch:general"] = { titleKey = "General", kind = "GENERAL", slash = "/s ", order = 0 },
    ["ch:party"] = { titleKey = "Party", kind = "PARTY", slash = "/p ", order = 1 },
    ["ch:instance"] = { titleKey = "Instance", kind = "INSTANCE_CHAT", slash = "/i ", order = 2 },
    ["ch:raid"] = { titleKey = "Raid", kind = "RAID", slash = "/ra ", order = 3 },
    ["ch:guild"] = { titleKey = "Guild", kind = "GUILD", slash = "/g ", order = 4 },
    ["ch:officer"] = { titleKey = "Officer", kind = "OFFICER", slash = "/o ", order = 5 },
    ["ch:alliance"] = { titleKey = "Alliance", kind = "ALLIANCE", slash = "/al ", order = 6 },
}

local function GetHistoryScopeTable()
    local root = ns.db and ns.db.chatHistory
    if not root then return nil end
    if Store and Store.EnsureScopedBucket then
        return Store:EnsureScopedBucket(root, "chatHistory")
    end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

local function GetRoomsScopeTable()
    local root = ns.db and ns.db.chatRooms
    if not root then return nil end
    if Store and Store.EnsureScopedBucket then
        return Store:EnsureScopedBucket(root, "chatRooms")
    end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

local function GetAddonPeersScopeTable()
    local root = ns.db and ns.db.addonPeers
    if not root then return nil end
    if Store and Store.EnsureScopedBucket then
        return Store:EnsureScopedBucket(root, "addonPeers")
    end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

local function CountHashKeys(tbl)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
    end
    return n
end

local function GetHistoryStamp(saved)
    local ts = tonumber(saved.updatedAt)
    if ts and ts > 0 then return ts end
    if type(saved.lines) == "table" and #saved.lines > 0 then
        local lastLine = saved.lines[#saved.lines]
        return tonumber(type(lastLine) == "table" and lastLine.ts) or 0
    end
    return 0
end

local function GetPeerStamp(peer)
    return tonumber(peer.lastSeenAt) or 0
end

local function PruneSavedScopeTable(tbl, ttlSeconds, maxEntries, getStamp, isProtected)
    if type(tbl) ~= "table" then return end
    local now = time()
    local entries = {}
    for k, v in pairs(tbl) do
        if type(k) ~= "string" or type(v) ~= "table" then
            tbl[k] = nil
        else
            local protected = (type(isProtected) == "function") and (isProtected(k, v) == true) or false
            local ts = tonumber(getStamp(v)) or 0
            if (not protected) and ttlSeconds and ttlSeconds > 0 and now > ttlSeconds and ts > 0 and (now - ts) > ttlSeconds then
                tbl[k] = nil
            else
                entries[#entries + 1] = { key = k, ts = ts, protected = protected }
            end
        end
    end
    if maxEntries and #entries > maxEntries then
        table.sort(entries, function(a, b)
            if a.protected ~= b.protected then
                return a.protected
            end
            if a.ts ~= b.ts then
                return a.ts > b.ts
            end
            return a.key < b.key
        end)
        for i = maxEntries + 1, #entries do
            if not entries[i].protected then
                tbl[entries[i].key] = nil
            end
        end
    end
end

local function IsProtectedThreadRecord(threadKey)
    if type(threadKey) ~= "string" then return false end
    if threadKey == "notes:self"
        or threadKey == "mentions:radar"
        or threadKey == "ch:general"
        or threadKey == "ch:alliance"
        or threadKey == "ch:party"
        or threadKey == "ch:instance"
        or threadKey == "ch:raid"
        or threadKey == "ch:say"
        or threadKey == "ch:yell"
        or threadKey:sub(1, 7) == "ch:pub:"
        or threadKey:sub(1, 8) == "ch:guild"
        or threadKey:sub(1, 10) == "ch:officer"
        or threadKey:sub(1, 5) == "room:"
    then
        return true
    end
    return (Chat.IsThreadPinned and Chat:IsThreadPinned(threadKey)) == true
end

local function CleanRoomToken(raw)
    if type(raw) ~= "string" then return nil end
    local clean = raw:gsub("[^%w_%-]", ""):sub(1, 24)
    if clean == "" then return nil end
    return clean
end

local function NonEmptyField(text, maxLen, fallback)
    local s = Compat.CleanPayloadField(text, maxLen)
    if s == "" then
        return fallback
    end
    return s
end

local MAX_CHAT_SESSION_CACHE = 400
local knownFullCount = 0
local knownFactionCount = 0

local function NoteKnownFullName(rawName, factionHint)
    if type(rawName) ~= "string" or rawName == "" or not Compat.ParseCharacterFields then
        return
    end
    local lk, firstName, disp, surname = Compat.ParseCharacterFields(rawName)
    if not lk then return end
    if surname and surname ~= "" and firstName and firstName ~= "" then
        local firstLow = firstName:lower()
        Chat.knownFullByFirst = Chat.knownFullByFirst or {}
        local cur = Chat.knownFullByFirst[firstLow]
        if cur == nil then
            if knownFullCount >= MAX_CHAT_SESSION_CACHE then
                wipe(Chat.knownFullByFirst)
                knownFullCount = 0
            end
            knownFullCount = knownFullCount + 1
            Chat.knownFullByFirst[firstLow] = {
                lookupKey = lk,
                displayName = disp,
                firstName = firstName,
                surname = surname,
            }
        elseif cur ~= false and cur.lookupKey ~= lk then
            Chat.knownFullByFirst[firstLow] = false
        end
    end
    if factionHint and Compat.NormalizeFaction then
        local nf = Compat.NormalizeFaction(factionHint)
        if nf then
            Chat.knownFactionByKey = Chat.knownFactionByKey or {}
            if Chat.knownFactionByKey[lk] == nil then
                if knownFactionCount >= MAX_CHAT_SESSION_CACHE then
                    wipe(Chat.knownFactionByKey)
                    knownFactionCount = 0
                end
                knownFactionCount = knownFactionCount + 1
            end
            Chat.knownFactionByKey[lk] = nf
        end
    end
end

function Chat:SeedKnownNamesFromSavedData()
    self.knownFullByFirst = self.knownFullByFirst or {}
    self.knownFactionByKey = self.knownFactionByKey or {}
    local altsTbl = ns.db and ns.db.alts
    if type(altsTbl) == "table" then
        for _, alt in pairs(altsTbl) do
            if type(alt) == "table" and (not Store or not Store.AltMatchesWorldScope or Store:AltMatchesWorldScope(alt, "pool")) then
                NoteKnownFullName(alt.fullName or alt.name, alt.faction)
            end
        end
    end
    local hist = GetHistoryScopeTable()
    if type(hist) == "table" then
        local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
        for key, saved in pairs(hist) do
            if type(key) == "string" and key:sub(1, 2) == "w:" and type(saved) == "table" then
                NoteKnownFullName(saved.targetName or saved.title or key:sub(3), saved.faction or myFac)
                if type(saved.lines) == "table" then
                    for _, ln in ipairs(saved.lines) do
                        if type(ln) == "table" then
                            NoteKnownFullName(ln.sender, ln.senderFaction)
                            NoteKnownFullName(ln.targetChar, ln.targetFaction)
                        end
                    end
                end
            end
        end
    end
    local savedPeers = GetAddonPeersScopeTable()
    if type(savedPeers) == "table" then
        for _, peer in pairs(savedPeers) do
            if type(peer) == "table" and type(peer.name) == "string" then
                NoteKnownFullName(peer.name, nil)
            end
        end
    end
    local scope = Compat.ScopeKey()
    local metaTbl = ns.db and ns.db.socialMeta and ns.db.socialMeta[scope]
    if type(metaTbl) == "table" then
        for k, rec in pairs(metaTbl) do
            NoteKnownFullName(k, nil)
            if type(rec) == "table" and type(rec.mainName) == "string" then
                NoteKnownFullName(rec.mainName, nil)
            end
        end
    end
    if Store and Store.GetWatchlistTable then
        local wl = Store:GetWatchlistTable()
        if type(wl) == "table" then
            for _, entry in pairs(wl) do
                if type(entry) == "table" and entry.displayName then
                    NoteKnownFullName(entry.displayName, nil)
                end
            end
        end
    end
end

function Chat:GetKnownCharacterFaction(nameOrKey, guidHint, bnetAccountID)
    if Compat.ResolveCharacterFaction then
        local fac = Compat.ResolveCharacterFaction(nameOrKey, guidHint, bnetAccountID)
        if fac then
            if type(nameOrKey) == "string" and nameOrKey ~= "" and Compat.ParseCharacterFields then
                local lk = Compat.ParseCharacterFields(nameOrKey)
                if lk then
                    self.knownFactionByKey = self.knownFactionByKey or {}
                    self.knownFactionByKey[lk] = fac
                end
            end
            return fac
        end
    end
    if type(nameOrKey) == "string" and nameOrKey ~= "" and Compat.ParseCharacterFields and self.knownFactionByKey then
        local lk = Compat.ParseCharacterFields(nameOrKey)
        if lk and self.knownFactionByKey[lk] then
            return self.knownFactionByKey[lk]
        end
    end
    return nil
end

local function LookupFullAltByFirst(firstName)
    if type(firstName) ~= "string" or firstName == "" then return nil end
    local altsTbl = ns.db and ns.db.alts
    if type(altsTbl) ~= "table" then return nil end
    local wantLow = firstName:lower()
    local count, foundDisp = 0, nil
    for _, alt in pairs(altsTbl) do
        if type(alt) == "table" and type(alt.fullName) == "string" and alt.fullName ~= "" then
            if not Store or not Store.AltMatchesWorldScope or Store:AltMatchesWorldScope(alt, "pool") then
                local _, fn, disp, sn = Compat.ParseCharacterFields(alt.fullName)
                if fn and sn and sn ~= "" and fn:lower() == wantLow then
                    count = count + 1
                    foundDisp = disp
                    if count > 1 then return nil end
                end
            end
        end
    end
    if count == 1 then return foundDisp end
    return nil
end

local function GetMyInfo()
    local myAlt = Store and Store.GetCurrentAltRecord and Store:GetCurrentAltRecord()
    local altFull = myAlt and myAlt.fullName
    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName(altFull)
    local cand = (resolvedSelf and resolvedSelf.fullName and resolvedSelf.fullName ~= "") and resolvedSelf.fullName
        or Safe.String(Safe.Call(UnitName, "player"))
        or "Unknown"
    local p = Compat.ParseCharacterName and Compat.ParseCharacterName(cand)
    if p and (not p.surname or p.surname == "") and p.firstName then
        local fullAlt = LookupFullAltByFirst(p.firstName)
        if fullAlt then
            p = Compat.ParseCharacterName(fullAlt) or p
        else
            local kf = Chat.knownFullByFirst and Chat.knownFullByFirst[p.firstName:lower()]
            if type(kf) == "table" and kf.displayName then
                p = Compat.ParseCharacterName(kf.displayName) or p
            end
        end
    end
    if p then
        NoteKnownFullName(p.displayName, Compat.PlayerFaction and Compat.PlayerFaction())
        return p.displayName, p.lookupKey, p.firstName, p.surname
    end
    return cand, cand:lower(), cand, nil
end

local function ResolveChatSenderDisplay(rawAuthor, guidHint, fallbackDisplay)
    if type(rawAuthor) == "string" and rawAuthor == L["System"] then
        return rawAuthor
    end
    if rawAuthor and rawAuthor ~= "" and Compat.IsMe and Compat.IsMe(rawAuthor, guidHint) then
        return (GetMyInfo())
    end
    local parsed = (type(rawAuthor) == "string" and rawAuthor ~= "") and Compat.ParseCharacterName and Compat.ParseCharacterName(rawAuthor) or nil
    if parsed and parsed.surname and parsed.surname ~= "" then
        NoteKnownFullName(parsed.displayName)
        return parsed.displayName
    end
    if parsed and parsed.firstName then
        local fbParsed = (type(fallbackDisplay) == "string" and fallbackDisplay ~= "") and Compat.ParseCharacterName and Compat.ParseCharacterName(fallbackDisplay) or nil
        if fbParsed and fbParsed.surname and fbParsed.surname ~= "" and fbParsed.firstName:lower() == parsed.firstName:lower() then
            NoteKnownFullName(fbParsed.displayName)
            return fbParsed.displayName
        end
        if Compat.LookupForeverFullName then
            local fullRec = Compat.LookupForeverFullName(guidHint, parsed.firstName, false)
            if fullRec and fullRec.fullName and fullRec.surname and fullRec.surname ~= "" then
                NoteKnownFullName(fullRec.fullName)
                return fullRec.fullName
            end
        end
        local altFull = LookupFullAltByFirst(parsed.firstName)
        if altFull then
            NoteKnownFullName(altFull)
            return altFull
        end
        if Store and type(Store.guildRosterRanks) == "table" then
            local wantFirst = parsed.firstName:lower()
            local matchCount, matchDisp = 0, nil
            for _, rk in pairs(Store.guildRosterRanks) do
                if type(rk) == "table" and rk.displayName and not rk.isSelf then
                    local _, fn, _, sn = Compat.ParseCharacterFields(rk.displayName)
                    if fn and sn and sn ~= "" and fn:lower() == wantFirst then
                        matchCount = matchCount + 1
                        matchDisp = rk.displayName
                        if matchCount > 1 then break end
                    end
                end
            end
            if matchCount == 1 and matchDisp then
                NoteKnownFullName(matchDisp)
                return matchDisp
            end
        end
        local kf = Chat.knownFullByFirst and Chat.knownFullByFirst[parsed.firstName:lower()]
        if type(kf) == "table" and kf.displayName then
            return kf.displayName
        end
        return parsed.displayName
    end
    if type(fallbackDisplay) == "string" and fallbackDisplay ~= "" then
        local fbParsed = Compat.ParseCharacterName and Compat.ParseCharacterName(fallbackDisplay)
        return (fbParsed and fbParsed.displayName) or fallbackDisplay
    end
    return (type(rawAuthor) == "string" and rawAuthor ~= "") and rawAuthor or "?"
end

local function TrackDeliveryEntry(self, msgId, threadKey, entry)
    if not (msgId and entry) then return end
    self.deliveryIndex = self.deliveryIndex or {}
    local nowClock = (GetTime and GetTime()) or 0
    local count, oldestId, oldestTs = 0, nil, nil
    for id, rec in pairs(self.deliveryIndex) do
        local ts = (type(rec) == "table" and rec.sentAt) or 0
        if type(rec) ~= "table" or (nowClock > ts and (nowClock - ts) > 600) then
            self.deliveryIndex[id] = nil
        else
            count = count + 1
            if not oldestTs or ts < oldestTs then
                oldestTs = ts
                oldestId = id
            end
        end
    end
    if count >= 80 and oldestId then
        self.deliveryIndex[oldestId] = nil
    end
    self.deliveryIndex[msgId] = { threadKey = threadKey, entry = entry, sentAt = nowClock }
end

local function PruneProbeTracking(self, nowClock)
    local total = 0
    for k, ts in pairs(self.probeSentAt) do
        if (not self.threads[k]) or (nowClock > (ts or 0) and (nowClock - (ts or 0)) > 600) then
            self.probeSentAt[k] = nil
            if self.probeFailures then
                self.probeFailures[k] = nil
            end
        else
            total = total + 1
        end
    end
    if total >= 80 then
        local oldestK, oldestTs
        for k, ts in pairs(self.probeSentAt) do
            if not oldestTs or ts < oldestTs then
                oldestTs = ts
                oldestK = k
            end
        end
        if oldestK then
            self.probeSentAt[oldestK] = nil
            if self.probeFailures then
                self.probeFailures[oldestK] = nil
            end
        end
    end
end

local function IsPublicChannelKind(kind)
    return kind == "GUILD" or kind == "OFFICER" or kind == "PARTY" or kind == "RAID" or kind == "INSTANCE_CHAT" or kind == "LOCAL_SAY" or kind == "LOCAL_YELL" or kind == "PUB_CHANNEL"
end

function Chat:_IsInDungeonOrRaid()
    if not IsInInstance then return false end
    local ok, inInst, instType = pcall(IsInInstance)
    if ok and Safe and Safe.Value(inInst) == true then
        local t = Safe.String(instType)
        if t == "party" or t == "raid" or t == "scenario" then
            return true
        end
    end
    return false
end

function Chat:_ResolveMuteTitle(threadKey)
    if not threadKey then return "?" end
    local meta = STATIC_CHANNEL_ORDER[threadKey]
    if meta and meta.titleKey and L[meta.titleKey] then
        return L[meta.titleKey]
    end
    local t = self.threads and self.threads[threadKey]
    if t then
        return t.title or t.targetName or threadKey
    end
    return tostring(threadKey)
end

function Chat:_ScheduleMuteCheck(delaySec)
    if not (C_Timer and C_Timer.After) then return end
    self._threadMuteTimerGen = (self._threadMuteTimerGen or 0) + 1
    local gen = self._threadMuteTimerGen
    local waitSec = math.max(0.5, math.min(86400, tonumber(delaySec) or 1))
    local chatRef = self
    C_Timer.After(waitSec, function()
        if chatRef._threadMuteTimerGen ~= gen then return end
        if chatRef.CheckExpiredThreadMutes then
            chatRef:CheckExpiredThreadMutes(true)
        end
    end)
end

function Chat:CheckExpiredThreadMutes(scheduleTimerIfPending)
    if self._checkingThreadMutes then
        return false
    end
    local s = ns.db and ns.db.settings
    local savedRules = s and s.chatMutedThreadRules
    local savedMuted = s and s.chatMutedThreads
    -- Purge any legacy BNet keys out of SavedVariables into session-only mute tables.
    if type(savedMuted) == "table" then
        for k, v in pairs(savedMuted) do
            if type(k) == "string" and k:sub(1, 3) == "bn:" then
                if v == true then
                    self.sessionMutedThreads = self.sessionMutedThreads or {}
                    self.sessionMutedThreads[k] = true
                end
                savedMuted[k] = nil
            end
        end
    end
    if type(savedRules) == "table" then
        for k, v in pairs(savedRules) do
            if type(k) == "string" and k:sub(1, 3) == "bn:" then
                if type(v) == "table" then
                    self.sessionMutedThreadRules = self.sessionMutedThreadRules or {}
                    self.sessionMutedThreadRules[k] = v
                end
                savedRules[k] = nil
            end
        end
    end

    local hasSavedRules = (type(savedRules) == "table" and next(savedRules) ~= nil)
    local hasSessRules = (type(self.sessionMutedThreadRules) == "table" and next(self.sessionMutedThreadRules) ~= nil)
    if not hasSavedRules and not hasSessRules then
        return false
    end
    self._checkingThreadMutes = true
    if s and type(savedMuted) ~= "table" and hasSavedRules then
        savedMuted = {}
        s.chatMutedThreads = savedMuted
    end
    local now = time()
    local inDungRaid = self:_IsInDungeonOrRaid()
    local minRemaining = nil
    local expiredKeys = {}
    local ruleSets = {
        { savedRules, savedMuted },
        { self.sessionMutedThreadRules, self.sessionMutedThreads },
    }
    for si = 1, 2 do
        local rulesTbl, mutedTbl = ruleSets[si][1], ruleSets[si][2]
        if type(rulesTbl) == "table" then
            if type(mutedTbl) ~= "table" then
                mutedTbl = {}
                if si == 1 and s then
                    s.chatMutedThreads = mutedTbl
                elseif si == 2 then
                    self.sessionMutedThreads = mutedTbl
                end
            end
            for k, rule in pairs(rulesTbl) do
                if mutedTbl[k] ~= true or type(rule) ~= "table" then
                    rulesTbl[k] = nil
                elseif type(rule.untilTs) == "number" and rule.untilTs > 0 then
                    if now >= rule.untilTs then
                        mutedTbl[k] = nil
                        rulesTbl[k] = nil
                        expiredKeys[#expiredKeys + 1] = k
                    else
                        local rem = rule.untilTs - now
                        if not minRemaining or rem < minRemaining then
                            minRemaining = rem
                        end
                    end
                elseif rule.untilLeaveInstance == true then
                    if inDungRaid then
                        rule.instanceEntered = true
                    elseif rule.instanceEntered == true then
                        mutedTbl[k] = nil
                        rulesTbl[k] = nil
                        expiredKeys[#expiredKeys + 1] = k
                    end
                else
                    rulesTbl[k] = nil
                end
            end
        end
    end
    self._checkingThreadMutes = nil

    if #expiredKeys > 0 then
        self:InvalidateUnreadCache()
        self:BumpPeerStateGen()
        for _, ek in ipairs(expiredKeys) do
            if ns.Print then
                local muteDisp = self:_ResolveMuteTitle(ek)
                if Compat and Compat.IsStreamerMode and Compat.IsStreamerMode() then
                    local thr = self.threads and self.threads[ek]
                    if thr and thr.kind == "ROOM" then
                        muteDisp = L["Private Room"]
                    elseif ((type(ek) == "string" and ek:sub(1, 3) == "bn:") or tostring(muteDisp):find("#", 1, true)) and Compat.MaskStreamerBNetName then
                        muteDisp = Compat.MaskStreamerBNetName(muteDisp)
                    end
                end
                ns:Print(L["Notifications re-enabled for %s."]:format(muteDisp))
            end
        end
        ns:Emit("CHAT_UPDATED")
        ns:Emit("SETTINGS_UPDATED")
        if ns.Settings and ns.Settings.Refresh then
            ns.Settings:Refresh()
        end
    end
    if minRemaining and scheduleTimerIfPending then
        self:_ScheduleMuteCheck(minRemaining + 0.5)
    end
    return #expiredKeys > 0
end

function Chat:IsThreadMuted(threadKey)
    local isBn = type(threadKey) == "string" and threadKey:sub(1, 3) == "bn:"
    local s = ns.db and ns.db.settings
    local rules = isBn and self.sessionMutedThreadRules or (s and s.chatMutedThreadRules)
    if type(rules) == "table" and next(rules) ~= nil then
        self:CheckExpiredThreadMutes(false)
    end
    if isBn then
        return type(self.sessionMutedThreads) == "table" and self.sessionMutedThreads[threadKey] == true or false
    end
    local muted = s and s.chatMutedThreads
    return type(muted) == "table" and threadKey and muted[threadKey] == true or false
end

function Chat:GetThreadMuteInfo(threadKey)
    if not self:IsThreadMuted(threadKey) then
        return false, nil, nil
    end
    local isBn = type(threadKey) == "string" and threadKey:sub(1, 3) == "bn:"
    local s = ns.db and ns.db.settings
    local rules = isBn and self.sessionMutedThreadRules or (s and s.chatMutedThreadRules)
    local rule = type(rules) == "table" and rules[threadKey] or nil
    if type(rule) == "table" then
        if type(rule.untilTs) == "number" and rule.untilTs > 0 then
            return true, "timed", math.max(1, math.ceil(rule.untilTs - time()))
        elseif rule.untilLeaveInstance == true then
            return true, "instance", nil
        end
    end
    return true, "forever", nil
end

function Chat:FormatThreadMuteStatus(threadKey)
    local isMuted, mode, remSec = self:GetThreadMuteInfo(threadKey)
    if not isMuted then
        return nil
    end
    if mode == "timed" and remSec then
        local mins = math.max(1, math.ceil(remSec / 60))
        return L["Silenced (%dm left)"]:format(mins)
    elseif mode == "instance" then
        return L["Silenced until leaving dungeon or raid"]
    end
    return L["Silenced until re-enabled"]
end

function Chat:SetThreadMuted(threadKey, state, opts)
    if not threadKey or not (ns.db and ns.db.settings) then
        return false
    end
    local isBn = type(threadKey) == "string" and threadKey:sub(1, 3) == "bn:"
    local muted, rules
    if isBn then
        self.sessionMutedThreads = self.sessionMutedThreads or {}
        self.sessionMutedThreadRules = self.sessionMutedThreadRules or {}
        muted = self.sessionMutedThreads
        rules = self.sessionMutedThreadRules
        if type(ns.db.settings.chatMutedThreads) == "table" then
            ns.db.settings.chatMutedThreads[threadKey] = nil
        end
        if type(ns.db.settings.chatMutedThreadRules) == "table" then
            ns.db.settings.chatMutedThreadRules[threadKey] = nil
        end
    else
        if type(ns.db.settings.chatMutedThreads) ~= "table" then
            ns.db.settings.chatMutedThreads = {}
        end
        if type(ns.db.settings.chatMutedThreadRules) ~= "table" then
            ns.db.settings.chatMutedThreadRules = {}
        end
        muted = ns.db.settings.chatMutedThreads
        rules = ns.db.settings.chatMutedThreadRules
    end
    local t = self.threads[threadKey]
    if state then
        muted[threadKey] = true
        if type(opts) == "table" and type(opts.durationSec) == "number" and opts.durationSec > 0 then
            rules[threadKey] = { untilTs = time() + math.floor(opts.durationSec + 0.5) }
            self:CheckExpiredThreadMutes(true)
        elseif type(opts) == "table" and opts.untilLeaveInstance == true then
            rules[threadKey] = {
                untilLeaveInstance = true,
                instanceEntered = self:_IsInDungeonOrRaid() and true or false,
            }
        else
            rules[threadKey] = nil
        end
        if t then
            t.unread = 0
            t.hasMention = nil
            t.firstUnreadTs = nil
            t.firstUnreadEntry = nil
            if type(threadKey) == "string" and (threadKey:sub(1, 2) == "w:" or self:IsGuildHistoryKey(threadKey)) then
                local hist = GetHistoryScopeTable()
                if hist and type(hist[threadKey]) == "table" then
                    hist[threadKey].unread = 0
                end
            end
        end
        ns:Emit("CHAT_THREAD_READ", {
            threadKey = threadKey,
            channelKey = threadKey,
            kind = t and t.kind or nil,
            bnetAccountID = t and t.bnetAccountID or nil,
        })
    else
        muted[threadKey] = nil
        rules[threadKey] = nil
    end
    self:InvalidateUnreadCache()
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
    ns:Emit("SETTINGS_UPDATED")
    return true
end

function Chat:ToggleThreadMuted(threadKey)
    local nextState = not self:IsThreadMuted(threadKey)
    self:SetThreadMuted(threadKey, nextState)
    return nextState
end

Chat._THREAD_MUTE_PRESETS = {
    { durationSec = 300, labelKey = "For 5 minutes" },
    { durationSec = 600, labelKey = "For 10 minutes" },
    { durationSec = 1800, labelKey = "For 30 minutes" },
    { untilLeaveInstance = true, labelKey = "Until leaving dungeon or raid" },
    { permanent = true, labelKey = "Until I turn it off" },
}

function Chat:PopulateThreadMuteMenu(menuRoot, threadKey, displayTitle, onAfterChange)
    if not (menuRoot and threadKey) then return end
    local isMuted = self:GetThreadMuteInfo(threadKey)
    local titleLbl = displayTitle or self:_ResolveMuteTitle(threadKey)
    if isMuted then
        local statusTxt = self:FormatThreadMuteStatus(threadKey)
        if statusTxt then
            menuRoot:CreateTitle("|cffff9b3d" .. statusTxt .. "|r")
        end
        menuRoot:CreateButton("|cff3fb950" .. L["Re-enable Notifications"] .. "|r", function()
            self:SetThreadMuted(threadKey, false)
            if type(onAfterChange) == "function" then
                onAfterChange(false, nil)
            end
        end)
        menuRoot:CreateDivider()
    end
    local addRadio = menuRoot.CreateRadio or menuRoot.CreateCheckbox
    for _, preset in ipairs(self._THREAD_MUTE_PRESETS) do
        local lbl = L[preset.labelKey]
        local function applyPreset()
            local opts = nil
            if preset.durationSec then
                opts = { durationSec = preset.durationSec }
            elseif preset.untilLeaveInstance then
                opts = { untilLeaveInstance = true }
            end
            self:SetThreadMuted(threadKey, true, opts)
            if type(onAfterChange) == "function" then
                onAfterChange(true, opts)
            end
        end
        if addRadio then
            addRadio(menuRoot, lbl, function()
                local mNow, modeNow = self:GetThreadMuteInfo(threadKey)
                if not mNow then return false end
                if preset.untilLeaveInstance then
                    return modeNow == "instance"
                elseif preset.permanent then
                    return modeNow == "forever"
                end
                return false
            end, applyPreset)
        else
            menuRoot:CreateButton(lbl, applyPreset)
        end
    end
end

local UNMUTE_CHANNEL_MAP = {
    msgPreviewGroup = { "ch:party", "ch:instance" },
    quickReplyNotifyParty = { "ch:party", "ch:instance" },
    quickReplyNotifyRaid = { "ch:raid" },
    msgPreviewGuild = { "ch:guild", "ch:officer" },
    quickReplyNotifyGuild = { "ch:guild", "ch:officer" },
    quickReplyNotifySay = { "ch:general" },
}

function Chat:UnmuteChannelKeysForSetting(settingKey)
    local keys = settingKey and UNMUTE_CHANNEL_MAP[settingKey]
    if not keys then
        return false
    end
    local changed = false
    for _, k in ipairs(keys) do
        if self:IsThreadMuted(k) then
            self:SetThreadMuted(k, false)
            changed = true
        end
    end
    return changed
end

local function IsSessionOnlyPinnedKey(threadKey)
    return type(threadKey) == "string" and threadKey:sub(1, 3) == "bn:"
end

local function SyncPinnedOrder(chatObj)
    chatObj._runtimePinnedOrder = chatObj._runtimePinnedOrder or {}
    local order = chatObj._runtimePinnedOrder
    local savedOrder = (ns.charDb and type(ns.charDb.pinnedChatOrder) == "table") and ns.charDb.pinnedChatOrder or nil
    if #order == 0 and savedOrder then
        for i = 1, #savedOrder do
            local k = savedOrder[i]
            if type(k) == "string" and k ~= "" and not IsSessionOnlyPinnedKey(k) and chatObj:IsThreadPinned(k) then
                order[#order + 1] = k
            end
        end
    end

    local seen = {}
    local cleaned = {}
    for i = 1, #order do
        local k = order[i]
        if type(k) == "string" and k ~= "" and not seen[k] and chatObj:IsThreadPinned(k) then
            seen[k] = true
            cleaned[#cleaned + 1] = k
        end
    end

    local persisted = ns.charDb and ns.charDb.pinnedChatThreads
    if type(persisted) == "table" then
        for k, v in pairs(persisted) do
            if v == true and type(k) == "string" and k ~= "" and not IsSessionOnlyPinnedKey(k) and not seen[k] then
                seen[k] = true
                cleaned[#cleaned + 1] = k
            end
        end
    end
    if type(chatObj.sessionPinnedThreads) == "table" then
        for k, v in pairs(chatObj.sessionPinnedThreads) do
            if v == true and type(k) == "string" and k ~= "" and not seen[k] then
                seen[k] = true
                cleaned[#cleaned + 1] = k
            end
        end
    end

    chatObj._runtimePinnedOrder = cleaned
    if ns.charDb then
        local outPersist = {}
        for i = 1, #cleaned do
            local k = cleaned[i]
            if not IsSessionOnlyPinnedKey(k) then
                outPersist[#outPersist + 1] = k
            end
        end
        ns.charDb.pinnedChatOrder = outPersist
    end
    local ranks = chatObj._pinnedRanksCache
    if not ranks then
        ranks = {}
        chatObj._pinnedRanksCache = ranks
    else
        wipe(ranks)
    end
    for i = 1, #cleaned do
        ranks[cleaned[i]] = i
    end
    chatObj._pinnedDbRef = persisted
    chatObj._pinnedOrderDirty = false
    return cleaned
end

function Chat:InvalidatePinnedOrderCache()
    self._pinnedOrderDirty = true
end

function Chat:IsThreadPinned(threadKey)
    if not threadKey or threadKey == "notes:self" then
        return false
    end
    if IsSessionOnlyPinnedKey(threadKey) then
        return self.sessionPinnedThreads and self.sessionPinnedThreads[threadKey] == true or false
    end
    local pinned = ns.charDb and ns.charDb.pinnedChatThreads
    return type(pinned) == "table" and pinned[threadKey] == true or false
end

function Chat:GetPinnedOrderMap()
    local persisted = ns.charDb and ns.charDb.pinnedChatThreads
    if (not self._pinnedOrderDirty) and self._pinnedRanksCache and self._pinnedDbRef == persisted then
        return self._pinnedRanksCache
    end
    SyncPinnedOrder(self)
    return self._pinnedRanksCache or {}
end

function Chat:SetThreadPinned(threadKey, state)
    if not threadKey or threadKey == "notes:self" then
        return false
    end
    if IsSessionOnlyPinnedKey(threadKey) then
        self.sessionPinnedThreads = self.sessionPinnedThreads or {}
        self.sessionPinnedThreads[threadKey] = state and true or nil
    elseif ns.charDb then
        if type(ns.charDb.pinnedChatThreads) ~= "table" then
            ns.charDb.pinnedChatThreads = {}
        end
        ns.charDb.pinnedChatThreads[threadKey] = state and true or nil
    else
        return false
    end
    local order = SyncPinnedOrder(self)
    if state then
        local exists = false
        for i = 1, #order do
            if order[i] == threadKey then
                exists = true
                break
            end
        end
        if not exists then
            order[#order + 1] = threadKey
            SyncPinnedOrder(self)
        end
    end
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:MovePinnedThread(sourceKey, targetKey, insertAfter)
    if not sourceKey or not targetKey or sourceKey == targetKey then
        return false
    end
    if not (self:IsThreadPinned(sourceKey) and self:IsThreadPinned(targetKey)) then
        return false
    end
    local order = SyncPinnedOrder(self)
    local srcIdx, tgtIdx
    for i = 1, #order do
        if order[i] == sourceKey then srcIdx = i end
        if order[i] == targetKey then tgtIdx = i end
    end
    if not srcIdx or not tgtIdx then
        return false
    end
    table.remove(order, srcIdx)
    if srcIdx < tgtIdx then
        tgtIdx = tgtIdx - 1
    end
    local destIdx = insertAfter and (tgtIdx + 1) or tgtIdx
    if destIdx < 1 then destIdx = 1 end
    if destIdx > #order + 1 then destIdx = #order + 1 end
    table.insert(order, destIdx, sourceKey)
    SyncPinnedOrder(self)
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:ToggleThreadPinned(threadKey)
    local nextState = not self:IsThreadPinned(threadKey)
    self:SetThreadPinned(threadKey, nextState)
    return nextState
end

function Chat:_FormatBilingualQuickReply(enText, localText)
    local loc = localText or L[enText] or enText
    if type(loc) == "string" and loc ~= "" and loc ~= enText then
        return loc .. " / " .. enText
    end
    return enText
end

Chat._DEFAULT_QUICK_REPLY_KEYS = {
    whisper = {
        "On my way!",
        "1 min, brb!",
        "Up for a dungeon?",
        "Invite please!",
        "Thanks for the group!",
    },
    party = {
        "On my way! ({zone})",
        "1 min, brb!",
        "Ready for pull!",
        "Thanks for the group!",
    },
    raid = {
        "Ready!",
        "Need summon please!",
        "1 min, buffing up!",
        "Thanks for the raid!",
    },
    guild = {
        "Up for a dungeon?",
        "On my way from {zone}!",
        "Need a hand with anything?",
        "Count me in!",
    },
    defense = {
        "Enemy spotted in {zone}!",
        "Need help defending {zone}!",
        "Area is clear in {zone}.",
        "Where exactly in {zone}?",
    },
    ["local"] = {
        "Anyone for quests in {zone}?",
        "Looking for group in {zone}!",
        "WTB / Looking for crafter in {zone}",
        "On my way! ({zone})",
    },
}

local function BuildDefaultQuickReplies()
    local out = {}
    for _, enKey in ipairs(Chat._DEFAULT_QUICK_REPLY_KEYS.whisper) do
        out[#out + 1] = Chat:_FormatBilingualQuickReply(enKey)
    end
    return out
end

function Chat:GetQuickReplyContexts()
    return {
        { id = "local", label = L["Local & Trade (/1, /2)"] },
        { id = "defense", label = L["Defense (/3)"] },
        { id = "party", label = L["Party / Instance"] },
        { id = "raid", label = L["Raid"] },
        { id = "guild", label = L["Guild"] },
        { id = "whisper", label = L["Whispers"] },
    }
end

function Chat:BuildDefaultQuickRepliesForContext(ctxId)
    local keys = Chat._DEFAULT_QUICK_REPLY_KEYS[ctxId or "whisper"] or Chat._DEFAULT_QUICK_REPLY_KEYS.whisper
    local out = {}
    for _, enKey in ipairs(keys) do
        out[#out + 1] = self:_FormatBilingualQuickReply(enKey)
    end
    return out
end

function Chat:GetPortalDestinationsForPlayer()
    local fac = (Compat.PlayerFaction and Compat.PlayerFaction()) or "Neutral"
    local zoneRaw = (GetRealZoneText and Safe.String(Safe.Call(GetRealZoneText)))
        or (Compat.CurrentZoneName and Compat.CurrentZoneName())
        or ""
    local subRaw = (GetSubZoneText and Safe.String(Safe.Call(GetSubZoneText))) or ""
    if self._portalCacheFac == fac
        and self._portalCacheZone == zoneRaw
        and self._portalCacheSub == subRaw
        and self._portalCacheOut
    then
        return self._portalCacheOut
    end

    local byFac = self._PORTAL_DESTS_BY_FACTION
    if not byFac then
        byFac = {
            Horde = {
                { id = "uc", name = L["Undercity"], enName = "Undercity", abbr = "UC", match = { "undercity", "cidade baixa", "entranas", "entrañas" } },
                { id = "org", name = "Orgrimmar", enName = "Orgrimmar", abbr = "Org", match = { "orgrimmar" } },
                { id = "tb", name = L["Thunder Bluff"], enName = "Thunder Bluff", abbr = "TB", match = { "thunder bluff", "penhasco do trovao", "penhasco do trovão", "cima del trueno" } },
                { id = "smc", name = L["Silvermoon"], enName = "Silvermoon", abbr = "SMC", match = { "silvermoon", "luaprata", "lunargenta" } },
                { id = "shatt", name = "Shattrath", enName = "Shattrath", abbr = "Shatt", match = { "shattrath" } },
            },
            Alliance = {
                { id = "sw", name = L["Stormwind"], enName = "Stormwind", abbr = "SW", match = { "stormwind", "ventobravo", "ventormenta" } },
                { id = "if", name = L["Ironforge"], enName = "Ironforge", abbr = "IF", match = { "ironforge", "altaforja", "forjaz" } },
                { id = "darn", name = "Darnassus", enName = "Darnassus", abbr = "Darn", match = { "darnassus" } },
                { id = "exo", name = "Exodar", enName = "Exodar", abbr = "Exo", match = { "exodar", "el exodar" } },
                { id = "shatt", name = "Shattrath", enName = "Shattrath", abbr = "Shatt", match = { "shattrath" } },
            },
            Neutral = {
                { id = "shatt", name = "Shattrath", enName = "Shattrath", abbr = "Shatt", match = { "shattrath" } },
                { id = "org", name = "Orgrimmar", enName = "Orgrimmar", abbr = "Org", match = { "orgrimmar" } },
                { id = "sw", name = L["Stormwind"], enName = "Stormwind", abbr = "SW", match = { "stormwind", "ventobravo", "ventormenta" } },
            },
        }
        for _, list in pairs(byFac) do
            for _, d in ipairs(list) do
                local locPortal = string.format(L["LF portal to %s (%s)!"], d.name, d.abbr)
                local enPortal = string.format("LF portal to %s (%s)!", d.enName or d.name, d.abbr)
                d.entry = {
                    id = d.id,
                    name = d.name,
                    abbr = d.abbr,
                    text = self:_FormatBilingualQuickReply(enPortal, locPortal),
                }
            end
        end
        self._PORTAL_DESTS_BY_FACTION = byFac
    end

    local dests = byFac[fac] or byFac.Neutral
    local curFold = self:FoldSearchText(zoneRaw .. " " .. subRaw)
    local out = self._portalCacheOut
    if not out then
        out = {}
        self._portalCacheOut = out
    else
        wipe(out)
    end
    for _, d in ipairs(dests) do
        local isHere = false
        if curFold ~= "" then
            for _, pat in ipairs(d.match) do
                if curFold:find(pat, 1, true) then
                    isHere = true
                    break
                end
            end
        end
        if not isHere then
            out[#out + 1] = d.entry
        end
    end
    self._portalCacheFac = fac
    self._portalCacheZone = zoneRaw
    self._portalCacheSub = subRaw
    return out
end

function Chat:ResolveQuickReplyContext(threadKey)
    local t = threadKey and self.threads and self.threads[threadKey] or nil
    if not t then
        return "whisper"
    end
    if t.kind == "PARTY" or t.kind == "INSTANCE_CHAT" then
        return "party"
    elseif t.kind == "RAID" then
        return "raid"
    elseif t.kind == "GUILD" or t.kind == "OFFICER" or t.kind == "ALLIANCE" then
        return "guild"
    elseif t.kind == "PUB_CHANNEL" then
        local chNameFold = self:FoldSearchText(t.channelName or t.title or "")
        if t.channelId == 3 or chNameFold:find("defesa", 1, true) or chNameFold:find("defense", 1, true) or chNameFold:find("defensa", 1, true) then
            return "defense"
        end
        return "local"
    elseif t.kind == "GENERAL" then
        local gTarget = self.GetGeneralTargetInfo and self:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.channelId then
            local chNameFold = self:FoldSearchText(gTarget.name or gTarget.title or "")
            if gTarget.channelId == 3 or chNameFold:find("defesa", 1, true) or chNameFold:find("defense", 1, true) or chNameFold:find("defensa", 1, true) then
                return "defense"
            end
        end
        return "local"
    elseif t.kind == "LOCAL_SAY" or t.kind == "LOCAL_YELL" then
        return "local"
    end
    return "whisper"
end

function Chat:GetQuickRepliesForContext(ctxId)
    local key = ctxId or "whisper"
    local cfg = ns.db and ns.db.settings
    if not cfg then
        return self:BuildDefaultQuickRepliesForContext(key)
    end
    if cfg.quickRepliesBilingualV1 ~= true then
        cfg.quickRepliesBilingualV1 = true
        local upgradeMap = {}
        for _, enKeys in pairs(Chat._DEFAULT_QUICK_REPLY_KEYS) do
            for _, enKey in ipairs(enKeys) do
                local locVal = L[enKey]
                if type(locVal) == "string" and locVal ~= "" and locVal ~= enKey then
                    upgradeMap[locVal] = self:_FormatBilingualQuickReply(enKey)
                end
            end
        end
        if next(upgradeMap) ~= nil then
            local function UpgradeList(tbl)
                if type(tbl) ~= "table" then return end
                for i = 1, #tbl do
                    local repl = upgradeMap[tbl[i]]
                    if repl then
                        tbl[i] = repl
                    end
                end
            end
            UpgradeList(cfg.chatQuickReplies)
            if type(cfg.chatQuickRepliesByContext) == "table" then
                for _, subList in pairs(cfg.chatQuickRepliesByContext) do
                    UpgradeList(subList)
                end
            end
        end
    end
    if key == "whisper" then
        if type(cfg.chatQuickReplies) ~= "table" or #cfg.chatQuickReplies == 0 then
            cfg.chatQuickReplies = self:BuildDefaultQuickRepliesForContext("whisper")
        end
        return cfg.chatQuickReplies
    end
    if type(cfg.chatQuickRepliesByContext) ~= "table" then
        cfg.chatQuickRepliesByContext = {}
    end
    local list = cfg.chatQuickRepliesByContext[key]
    if type(list) ~= "table" or #list == 0 then
        list = self:BuildDefaultQuickRepliesForContext(key)
        cfg.chatQuickRepliesByContext[key] = list
    end
    return list
end

function Chat:GetQuickReplies(threadKey)
    local ctx = threadKey and self:ResolveQuickReplyContext(threadKey) or "whisper"
    local base = self:GetQuickRepliesForContext(ctx)
    if ctx == "local" then
        local portals = self:GetPortalDestinationsForPlayer()
        local combined = self._localQrCombinedBuf
        if not combined then
            combined = {}
            self._localQrCombinedBuf = combined
        else
            wipe(combined)
        end
        if portals[1] then combined[#combined + 1] = portals[1].text end
        if portals[2] then combined[#combined + 1] = portals[2].text end
        for _, v in ipairs(base) do
            combined[#combined + 1] = v
        end
        for i = 3, #portals do
            combined[#combined + 1] = portals[i].text
        end
        return combined
    end
    return base
end

function Chat:AddQuickReplyForContext(ctxId, rawText)
    local clean = Compat.CleanInput(rawText)
    if not clean or not (ns.db and ns.db.settings) then
        return false
    end
    local list = self:GetQuickRepliesForContext(ctxId or "whisper")
    for _, existing in ipairs(list) do
        if existing == clean then
            return true
        end
    end
    if #list >= 12 then
        table.remove(list, 1)
    end
    table.insert(list, clean)
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:RemoveQuickReplyForContext(ctxId, index)
    local key = ctxId or "whisper"
    local list = self:GetQuickRepliesForContext(key)
    if type(list) == "table" and index and index >= 1 and index <= #list then
        table.remove(list, index)
        if #list == 0 then
            local defaults = self:BuildDefaultQuickRepliesForContext(key)
            for i = 1, #defaults do
                list[i] = defaults[i]
            end
        end
        ns:Emit("CHAT_UPDATED")
        return true
    end
    return false
end

function Chat:ResetQuickRepliesForContext(ctxId)
    local key = ctxId or "whisper"
    local cfg = ns.db and ns.db.settings
    if not cfg then return false end
    if key == "whisper" then
        cfg.chatQuickReplies = self:BuildDefaultQuickRepliesForContext("whisper")
    else
        if type(cfg.chatQuickRepliesByContext) ~= "table" then
            cfg.chatQuickRepliesByContext = {}
        end
        cfg.chatQuickRepliesByContext[key] = self:BuildDefaultQuickRepliesForContext(key)
    end
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:AddQuickReply(rawText, threadKey)
    local ctx = threadKey and self:ResolveQuickReplyContext(threadKey) or "whisper"
    return self:AddQuickReplyForContext(ctx, rawText)
end

function Chat:RemoveQuickReply(index)
    return self:RemoveQuickReplyForContext("whisper", index)
end

function Chat:ResetQuickReplies()
    return self:ResetQuickRepliesForContext("whisper")
end

local UTF8_FOLD_MAP = {
    ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\163"] = "a", ["\195\164"] = "a",
    ["\195\128"] = "a", ["\195\129"] = "a", ["\195\130"] = "a", ["\195\131"] = "a", ["\195\132"] = "a",
    ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
    ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e",
    ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
    ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i",
    ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\181"] = "o", ["\195\182"] = "o",
    ["\195\146"] = "o", ["\195\147"] = "o", ["\195\148"] = "o", ["\195\149"] = "o", ["\195\150"] = "o",
    ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u", ["\195\188"] = "u",
    ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u", ["\195\156"] = "u",
    ["\195\167"] = "c", ["\195\135"] = "c",
    ["\195\177"] = "n", ["\195\145"] = "n",
}

function Chat:FoldSearchText(raw)
    if type(raw) ~= "string" or raw == "" then return "" end
    local s = raw:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    s = s:gsub("[\195][\128-\191]", UTF8_FOLD_MAP)
    return s:lower()
end

function Chat:EncodeUrlLink(url)
    if type(url) ~= "string" then return "" end
    return (url:gsub("([^%w%-%._~/])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

function Chat:DecodeUrlLink(encoded)
    if type(encoded) ~= "string" then return "" end
    return (encoded:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function WrapSingleUrlToken(token)
    local trailing = ""
    local clean = token
    while #clean > 4 do
        local lastCh = clean:sub(-1)
        if lastCh == "." or lastCh == "," or lastCh == "!" or lastCh == "?" or lastCh == ")" or lastCh == "]" or lastCh == ";" then
            trailing = lastCh .. trailing
            clean = clean:sub(1, -2)
        else
            break
        end
    end
    if #clean < 6 or clean:find("|", 1, true) then
        return token
    end
    local encoded = Chat:EncodeUrlLink(clean)
    return "|cff58a6ff|Haddon:SCentral:url:" .. encoded .. "|h[" .. clean .. "]|h|r" .. trailing
end

local function MapOutsideHyperlinks(str, fn)
    if type(str) ~= "string" or str == "" then return str end
    if not str:find("|H", 1, true) then
        return fn(str)
    end
    local parts = {}
    local pos = 1
    local len = #str
    while pos <= len do
        local hStart, hEnd = str:find("|H.-|h.-|h", pos)
        local segEnd = hStart and (hStart - 1) or len
        if segEnd >= pos then
            parts[#parts + 1] = fn(str:sub(pos, segEnd))
        end
        if hStart and hEnd then
            parts[#parts + 1] = str:sub(hStart, hEnd)
            pos = hEnd + 1
        else
            break
        end
    end
    return table.concat(parts)
end

function Chat:LinkifyUrls(text)
    if type(text) ~= "string" or text == "" then return text end
    local low = text:lower()
    if not (low:find("http://", 1, true) or low:find("https://", 1, true) or low:find("discord.gg/", 1, true) or low:find("www.", 1, true)) then
        return text
    end
    -- Apply each pass strictly outside WoW |H...|h...|h links so newly created links are never double-wrapped.
    local out = MapOutsideHyperlinks(text, function(seg)
        return (seg:gsub("([Hh][Tt][Tt][Pp][Ss]?://[^%s|<>\"']+)", WrapSingleUrlToken))
    end)
    out = MapOutsideHyperlinks(out, function(seg)
        seg = seg:gsub("(^)([Ww][Ww][Ww]%.[^%s|<>\"']+%.[A-Za-z][^%s|<>\"']*)", function(pre, tok)
            return pre .. WrapSingleUrlToken(tok)
        end)
        seg = seg:gsub("([%s%(%[\"'])([Ww][Ww][Ww]%.[^%s|<>\"']+%.[A-Za-z][^%s|<>\"']*)", function(pre, tok)
            return pre .. WrapSingleUrlToken(tok)
        end)
        return seg
    end)
    out = MapOutsideHyperlinks(out, function(seg)
        return (seg:gsub("([Dd][Ii][Ss][Cc][Oo][Rr][Dd]%.[Gg][Gg]/[^%s|<>\"']+)", WrapSingleUrlToken))
    end)
    return out
end

function Chat:ExpandQuickReplyText(rawText)
    if type(rawText) ~= "string" or rawText == "" then return rawText end
    if not rawText:find("{", 1, true) then return rawText end
    local locZone = (Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
    local enZone = (Compat.EnglishZoneName and Compat.EnglishZoneName()) or locZone
    local lvl = tostring((UnitLevel and Safe.Number(Safe.Call(UnitLevel, "player"))) or "")
    local rawLocCls, rawFileCls = Safe.Call(UnitClass, "player")
    local locClass = Safe.String(rawLocCls) or ""
    local enClass = (Compat.EnglishClassName and Compat.EnglishClassName(Safe.String(rawFileCls))) or locClass
    local res = rawText
    res = res:gsub("{[Zz]ona}", function() return locZone end)
    res = res:gsub("{[Zz]one}", function() return enZone end)
    res = res:gsub("{[Nn]ivel}", function() return lvl end):gsub("{[Ll]evel}", function() return lvl end):gsub("{nível}", function() return lvl end):gsub("{Nível}", function() return lvl end)
    res = res:gsub("{[Cc]lasse}", function() return locClass end):gsub("{[Cc]lase}", function() return locClass end)
    res = res:gsub("{[Cc]lass}", function() return enClass end)
    return res
end

function Chat:GetCategorizedQuickReplies()
    return {
        {
            title = L["Group"],
            items = {
                self:_FormatBilingualQuickReply("On my way! ({zone})"),
                self:_FormatBilingualQuickReply("Lv {level} {class} ready for dungeon!"),
                self:_FormatBilingualQuickReply("Invite please!"),
                self:_FormatBilingualQuickReply("Thanks for the group!"),
            },
        },
        {
            title = L["Trade & Craft"],
            items = {
                self:_FormatBilingualQuickReply("How much for that item?"),
                self:_FormatBilingualQuickReply("I have the materials, can you craft it?"),
                self:_FormatBilingualQuickReply("I'm in {zone}, meet me at the mailbox!"),
            },
        },
        {
            title = L["Guild"],
            items = {
                self:_FormatBilingualQuickReply("Count me in!"),
                self:_FormatBilingualQuickReply("Need a hand with anything?"),
                self:_FormatBilingualQuickReply("On my way from {zone}!"),
            },
        },
        {
            title = L["Busy / AFK"],
            items = {
                self:_FormatBilingualQuickReply("1 min, brb!"),
                self:_FormatBilingualQuickReply("In a dungeon right now, I'll reply soon!"),
                self:_FormatBilingualQuickReply("Busy at the moment, whisper me in a few minutes."),
            },
        },
    }
end

function Chat:MarkAllRead()
    local hist = GetHistoryScopeTable()
    local cleared = {}
    for key, t in pairs(self.threads) do
        local hadUnread = ((t.unread or 0) > 0) or (t.hasMention == true)
        t.unread = 0
        t.hasMention = nil
        t.firstUnreadTs = nil
        t.firstUnreadEntry = nil
        t.lastReadBannerTs = nil
        t.lastReadBannerEntry = nil
        if hist and type(key) == "string" and (key:sub(1, 2) == "w:" or self:IsGuildHistoryKey(key)) and type(hist[key]) == "table" then
            hist[key].unread = 0
        end
        if hadUnread then
            cleared[#cleared + 1] = {
                threadKey = key,
                channelKey = key,
                kind = t.kind,
                bnetAccountID = t.bnetAccountID,
            }
        end
    end
    self:InvalidateUnreadCache()
    for i = 1, #cleared do
        ns:Emit("CHAT_THREAD_READ", cleared[i])
    end
    ns:Emit("CHAT_UPDATED")
end

local function ShouldPlaySoundForThread(kind, threadKey)
    local s = ns.db and ns.db.settings
    if not s or s.chatSound == false then
        return false
    end
    if threadKey and Chat:IsThreadMuted(threadKey) then
        return false
    end
    if kind == "WHISPER" or kind == "BN_WHISPER" then
        return s.chatSoundWhispers ~= false
    elseif kind == "ROOM" then
        return s.chatSoundRooms ~= false
    elseif kind == "ALLIANCE" then
        return s.chatSoundAlliance ~= false
    elseif kind == "GUILD" or kind == "OFFICER" then
        return s.chatSoundGuild == true
    elseif kind == "PARTY" or kind == "RAID" or kind == "INSTANCE_CHAT" then
        return s.chatSoundGroup == true
    end
    return false
end

local function GetMessageSoundCooldown()
    local s = ns.db and ns.db.settings
    local configured = s and tonumber(s.chatSoundCooldown) or DEFAULT_SOUND_COOLDOWN
    if configured < SOUND_COOLDOWN then
        return SOUND_COOLDOWN
    end
    return configured
end

local function RecordMessageChimeStamp(monoNow, senderKey)
    Chat.lastChimeAt = monoNow
    if senderKey and senderKey ~= "" then
        local map = Chat.lastChimeBySender
        if type(map) ~= "table" then
            map = {}
            Chat.lastChimeBySender = map
            Chat._lastChimeSenderCount = 0
        end
        if not map[senderKey] then
            if (Chat._lastChimeSenderCount or 0) >= 200 then
                wipe(map)
                Chat._lastChimeSenderCount = 0
            end
            Chat._lastChimeSenderCount = (Chat._lastChimeSenderCount or 0) + 1
        end
        map[senderKey] = monoNow
    end
end

local function IsMessageChimeThrottled(monoNow, senderKey)
    local cd = GetMessageSoundCooldown()
    if (monoNow - (Chat.lastChimeAt or 0)) < cd then
        return true
    end
    if senderKey and senderKey ~= "" and type(Chat.lastChimeBySender) == "table" then
        local prevSenderAt = Chat.lastChimeBySender[senderKey]
        if prevSenderAt and (monoNow - prevSenderAt) < cd then
            return true
        end
    end
    return false
end

local function PlayIncomingChime(kind, threadKey, viaAddon, senderKey, bypassSettingCheck, bnetAccountID)
    local isManualTest = (bypassSettingCheck == "test")
    if (ns.db and ns.db.settings and ns.db.settings.moduleChatEnabled == false) then
        return false
    end
    if not isManualTest and kind ~= "MENTION" and kind ~= "ROOM" and kind ~= "ALLIANCE" and not viaAddon
        and Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode()
    then
        return false
    end
    if not isManualTest and (Compat.IsFocusSilenced and Compat.IsFocusSilenced(senderKey or threadKey, bnetAccountID)) then
        return false
    end
    if not bypassSettingCheck and not ShouldPlaySoundForThread(kind, threadKey) then
        return false
    end
    local monoNow = GetTime and GetTime() or time()
    local throttleKey = senderKey or threadKey
    if IsMessageChimeThrottled(monoNow, throttleKey) then
        return false
    end
    if PlaySound and SOUNDKIT then
        local kit
        if kind == "MENTION" then
            -- Distinct high-priority alert tone when your name or monitored keyword is called.
            kit = SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING or SOUNDKIT.RAID_BOSS_WHISPER_WARNING or SOUNDKIT.MAP_PING or 3175
        elseif kind == "ROOM" or kind == "ALLIANCE" then
            -- Softer social chime for Private Rooms and cross-guild Alliance chat.
            kit = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856
        elseif viaAddon or kind == "WHISPER" or kind == "BN_WHISPER" then
            -- Crisp direct ping for Whispers, Battle.net, and 1-on-1 addon messages.
            kit = SOUNDKIT.MAP_PING or 3175
        else
            -- Subtle tick for mirrored Guild / Party / Raid channels.
            kit = SOUNDKIT.IG_CHAT_SCROLL_UP or 1115
        end
        if kit then
            RecordMessageChimeStamp(monoNow, throttleKey)
            pcall(PlaySound, kit, "Master")
            return true
        end
    end
    return false
end

function Chat:PlayMessageNotificationSound(kind, threadKey, viaAddon, senderKey, bypassSettingCheck, bnetAccountID)
    return PlayIncomingChime(kind, threadKey, viaAddon, senderKey, bypassSettingCheck, bnetAccountID)
end

function Chat:PlayTestNotificationSound()
    return PlayIncomingChime("WHISPER", nil, false, "manual_test_sound", "test")
end

local function EnsureThread(key, kind, title, extra)
    if not key or key == "" then return nil end
    local t = Chat.threads[key]
    if extra and extra.targetName then
        NoteKnownFullName(extra.targetName, extra.faction)
    end
    if not t then
        t = {
            key = key,
            kind = kind or "WHISPER",
            title = title or key,
            targetName = extra and extra.targetName or nil,
            bnetAccountID = extra and extra.bnetAccountID or nil,
            bnetName = extra and extra.bnetName or nil,
            classFile = extra and extra.classFile or nil,
            level = (extra and tonumber(extra.level) and tonumber(extra.level) > 0) and math.floor(tonumber(extra.level)) or nil,
            faction = (extra and extra.faction)
                or ((kind == "WHISPER" or kind == "BN_WHISPER") and Chat:GetKnownCharacterFaction((extra and extra.targetName) or title, nil, extra and extra.bnetAccountID))
                or nil,
            roomId = extra and extra.roomId or nil,
            slash = extra and extra.slash or nil,
            unread = 0,
            lastAt = 0,
            messages = {},
        }
        Chat.threads[key] = t
    else
        if title and title ~= "" and (not t.title or t.title == "" or t.title == key or (title:find("%s") and not t.title:find("%s"))) then
            t.title = title
        end
        if extra then
            if extra.targetName and extra.targetName ~= t.targetName then
                t.targetName = extra.targetName
                t._targetParsed = nil
                t._targetParsedRaw = nil
            elseif extra.targetName then
                t.targetName = extra.targetName
            end
            if extra.bnetAccountID then t.bnetAccountID = extra.bnetAccountID end
            if extra.bnetName then t.bnetName = extra.bnetName end
            if extra.classFile then t.classFile = extra.classFile end
            if extra.level and tonumber(extra.level) and tonumber(extra.level) > 0 then
                t.level = math.floor(tonumber(extra.level))
            end
            if extra.faction then t.faction = extra.faction end
            if extra.slash then t.slash = extra.slash end
        end
        if not t.faction and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
            t.faction = Chat:GetKnownCharacterFaction(t.targetName or t.title, nil, t.bnetAccountID)
        end
    end
    return t
end

function Chat:IsGuildHistoryKey(threadKey)
    return threadKey == "ch:guild" or threadKey == "ch:officer"
end

function Chat:IsGroupHistoryKey(threadKey)
    return threadKey == "ch:party" or threadKey == "ch:instance" or threadKey == "ch:raid"
end

function Chat:IsGeneralHistoryKey(threadKey)
    if type(threadKey) ~= "string" then return false end
    return threadKey == "ch:general" or threadKey == "ch:alliance" or threadKey == "mentions:radar" or threadKey:sub(1, 5) == "room:"
end

function Chat:GetGuildStorageKey(threadKey)
    if not self:IsGuildHistoryKey(threadKey) then
        return threadKey
    end
    local curGuild = Compat and Compat.GuildName and Compat.GuildName() or nil
    if type(curGuild) == "string" and curGuild ~= "" then
        return threadKey .. ":" .. curGuild
    end
    return threadKey
end

function Chat:ShouldSaveGuildHistory()
    local s = ns.db and ns.db.settings
    return s == nil or s.guildChatHistorySave ~= false
end

function Chat:ShouldSaveGroupHistory()
    local s = ns.db and ns.db.settings
    return s == nil or s.groupChatHistorySave ~= false
end

function Chat:ShouldSaveGeneralHistory()
    local s = ns.db and ns.db.settings
    return s == nil or s.generalChatHistorySave ~= false
end

function Chat:GetGuildHistoryLimit()
    if not self:ShouldSaveGuildHistory() then
        return 0
    end
    local raw = ns.db and ns.db.settings and ns.db.settings.guildChatHistoryLimit
    local num = tonumber(raw) or 300
    if num < 50 then num = 50 end
    if num > 2000 then num = 2000 end
    return math.floor(num)
end

function Chat:GetGeneralHistoryLimit()
    local raw = ns.db and ns.db.settings and ns.db.settings.generalChatHistoryLimit
    local num = tonumber(raw) or 300
    if num < 50 then num = 50 end
    if num > 2000 then num = 2000 end
    return math.floor(num)
end

local function GetChatHistoryLimit()
    local raw = ns.db and ns.db.settings and ns.db.settings.chatHistoryLimit
    if raw == nil then return 300 end
    local num = tonumber(raw) or 300
    if num > MAX_SAVED_WHISPERS then return MAX_SAVED_WHISPERS end
    return math.max(0, num)
end

function Chat:GetHistoryLimitForKey(threadKey)
    if type(threadKey) ~= "string" then return 0 end
    if threadKey == "notes:self" then
        return 999999
    elseif threadKey:sub(1, 2) == "w:" then
        return GetChatHistoryLimit()
    elseif self:IsGuildHistoryKey(threadKey) then
        return self:GetGuildHistoryLimit()
    elseif self:IsGroupHistoryKey(threadKey) then
        return self:ShouldSaveGroupHistory() and self:GetGeneralHistoryLimit() or 0
    elseif self:IsGeneralHistoryKey(threadKey) then
        return self:ShouldSaveGeneralHistory() and self:GetGeneralHistoryLimit() or 0
    end
    return 0
end

function Chat:ShouldPersistThreadKey(threadKey)
    return self:GetHistoryLimitForKey(threadKey) > 0
end

Chat._MAX_TEXT_HISTORY_BYTES = 6 * 1024 * 1024
Chat._TEXT_QUOTA_TARGET_BYTES = 4.5 * 1024 * 1024

function Chat:_EstimateEntryTextBytes(entry)
    if type(entry) ~= "table" then return 0 end
    return 24
        + (type(entry.text) == "string" and #entry.text or 0)
        + (type(entry.rawText) == "string" and #entry.rawText or 0)
        + (type(entry.sender) == "string" and #entry.sender or 0)
        + (type(entry.targetChar) == "string" and #entry.targetChar or 0)
        + (type(entry.generalTag) == "string" and #entry.generalTag or 0)
        + (type(entry.senderCharName) == "string" and #entry.senderCharName or 0)
        + (type(entry.mentionTerm) == "string" and #entry.mentionTerm or 0)
end

function Chat:_EstimateThreadRecordBytes(rec)
    if type(rec) ~= "table" then return 0 end
    local total = (type(rec.title) == "string" and #rec.title or 0) + (type(rec.targetName) == "string" and #rec.targetName or 0)
    if type(rec.lines) == "table" then
        for i = 1, #rec.lines do
            total = total + self:_EstimateEntryTextBytes(rec.lines[i])
        end
    end
    return total
end

function Chat:_EstimateAllSavedTextBytes()
    local total = 0
    local histRoot = ns.db and ns.db.chatHistory
    if type(histRoot) == "table" then
        for _, scopeTbl in pairs(histRoot) do
            if type(scopeTbl) == "table" then
                for _, rec in pairs(scopeTbl) do
                    total = total + self:_EstimateThreadRecordBytes(rec)
                end
            end
        end
    end
    local editHist = ns.db and ns.db.chatEditHistory
    if type(editHist) == "table" then
        for i = 1, #editHist do
            if type(editHist[i]) == "string" then
                total = total + #editHist[i] + 8
            end
        end
    end
    return total
end

function Chat:_EnforceSavedHistoryTextQuota()
    local curBytes = tonumber(self._savedTextBytes) or 0
    local maxBytes = self._MAX_TEXT_HISTORY_BYTES or (6 * 1024 * 1024)
    if curBytes <= maxBytes then
        return
    end
    local targetBytes = self._TEXT_QUOTA_TARGET_BYTES or (4.5 * 1024 * 1024)
    local histRoot = ns.db and ns.db.chatHistory
    if type(histRoot) ~= "table" then
        return
    end
    local buckets = {}
    for _, scopeTbl in pairs(histRoot) do
        if type(scopeTbl) == "table" then
            for tKey, rec in pairs(scopeTbl) do
                if type(rec) == "table" and type(rec.lines) == "table" and #rec.lines > 0 and tKey ~= "notes:self" then
                    buckets[#buckets + 1] = {
                        scopeTbl = scopeTbl,
                        key = tKey,
                        rec = rec,
                        ts = GetHistoryStamp(rec),
                        protected = IsProtectedThreadRecord(tKey) and true or false,
                    }
                end
            end
        end
    end
    table.sort(buckets, function(a, b)
        if a.protected ~= b.protected then
            return not a.protected
        end
        if a.ts ~= b.ts then
            return a.ts < b.ts
        end
        return tostring(a.key) < tostring(b.key)
    end)
    for _, b in ipairs(buckets) do
        if curBytes <= targetBytes then break end
        local lines = b.rec.lines
        while #lines > 200 and curBytes > targetBytes do
            local rem = table.remove(lines, 1)
            curBytes = math.max(0, curBytes - self:_EstimateEntryTextBytes(rem))
        end
    end
    for _, b in ipairs(buckets) do
        if curBytes <= targetBytes then break end
        if not b.protected then
            for i = 1, #b.rec.lines do
                curBytes = math.max(0, curBytes - self:_EstimateEntryTextBytes(b.rec.lines[i]))
            end
            b.scopeTbl[b.key] = nil
        end
    end
    self._savedTextBytes = curBytes
end

local function PersistWhisperLine(threadKey, entry, unreadCount, threadObj)
    if type(threadKey) ~= "string" then
        return
    end
    local limit = Chat:GetHistoryLimitForKey(threadKey)
    if limit <= 0 then
        return
    end
    local isNotes = (threadKey == "notes:self")
    local isGuild = Chat:IsGuildHistoryKey(threadKey)
    local isChannelLike = isGuild or Chat:IsGroupHistoryKey(threadKey) or Chat:IsGeneralHistoryKey(threadKey)
    local hist = GetHistoryScopeTable()
    if not hist then return end

    local storageKey = isGuild and Chat:GetGuildStorageKey(threadKey) or threadKey
    local saved = hist[storageKey]
    local isNewThread = (type(saved) ~= "table")
    if isNewThread then
        local curGuild = isGuild and Compat and Compat.GuildName and Compat.GuildName() or nil
        if isGuild and storageKey ~= threadKey and type(hist[threadKey]) == "table" and type(hist[threadKey].lines) == "table" then
            local leg = hist[threadKey]
            if not leg.guildName or leg.guildName == "" or leg.guildName == curGuild then
                saved = leg
                saved.guildName = curGuild or saved.guildName
                hist[storageKey] = saved
                isNewThread = false
            end
        end
        if isNewThread then
            saved = { title = (threadObj and threadObj.title) or entry.threadTitle, targetName = entry.targetName, lines = {} }
            hist[storageKey] = saved
        end
    end
    saved.title = (threadObj and threadObj.title) or entry.threadTitle or saved.title
    saved.targetName = (threadObj and threadObj.targetName) or entry.targetName or saved.targetName
    saved.faction = (threadObj and threadObj.faction) or saved.faction
    if threadObj and tonumber(threadObj.level) and tonumber(threadObj.level) > 0 then
        saved.level = math.floor(tonumber(threadObj.level))
    end
    if isGuild then
        local curGuild = Compat and Compat.GuildName and Compat.GuildName() or nil
        if type(curGuild) == "string" and curGuild ~= "" then
            if storageKey == threadKey and type(saved.guildName) == "string" and saved.guildName ~= "" and saved.guildName ~= curGuild then
                saved.lines = {}
            end
            saved.guildName = curGuild
        end
    end
    saved.updatedAt = entry.ts or time()
    saved.unread = isChannelLike and 0 or math.max(0, math.floor(tonumber(unreadCount) or 0))
    if type(saved.lines) ~= "table" then saved.lines = {} end

    local targetLines = saved.lines
    local isWhisperKey = type(threadKey) == "string" and threadKey:sub(1, 2) == "w:"
    local isInc = entry.incoming and true or false
    local myFac = Compat and Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local savedSender = entry.sender
    if isWhisperKey and isInc and saved.targetName and savedSender == saved.targetName then
        savedSender = nil
    end
    local savedSenderFac = entry.senderFaction
    if isWhisperKey and savedSenderFac and saved.faction and savedSenderFac == saved.faction then
        savedSenderFac = nil
    end
    local savedTargetFac = entry.targetFaction
    if isWhisperKey and savedTargetFac and myFac and savedTargetFac == myFac then
        savedTargetFac = nil
    end
    local newEntry = {
        sender = savedSender,
        targetChar = entry.targetChar,
        text = entry.text,
        ts = entry.ts,
        incoming = isInc or nil,
        classFile = entry.classFile,
        targetClass = entry.targetClass,
        senderFaction = savedSenderFac,
        targetFaction = savedTargetFac,
        senderLevel = (tonumber(entry.senderLevel) and tonumber(entry.senderLevel) > 0) and math.floor(tonumber(entry.senderLevel)) or nil,
        viaAddon = entry.viaAddon and true or nil,
        noteId = entry.noteId,
        isMention = entry.isMention and true or nil,
        mentionTerm = entry.mentionTerm,
        mentionChannel = entry.mentionChannel,
        mentionType = entry.mentionType,
        rawText = entry.rawText,
        senderCharName = entry.senderCharName,
        senderLookupKey = entry.senderLookupKey,
        senderGuid = entry.senderGuid,
        sourceThreadKey = entry.sourceThreadKey,
        groupRosterId = entry.groupRosterId,
        generalTag = entry.generalTag,
        msgKind = entry.msgKind,
        noSenderColon = entry.noSenderColon and true or nil,
        isStatusNotice = (threadKey == "ch:general" and entry.isStatusNotice) and true or nil,
        channelId = entry.channelId,
        guildEventKind = entry.guildEventKind,
        guildTarget = entry.guildTarget,
        guildActor = entry.guildActor,
        guildRank = entry.guildRank,
        guildActionSent = entry.guildActionSent and true or nil,
    }
    table.insert(targetLines, newEntry)
    if Chat._savedTextBytes ~= nil then
        Chat._savedTextBytes = Chat._savedTextBytes + Chat:_EstimateEntryTextBytes(newEntry)
    end
    if entry.groupRosterId and threadObj and type(threadObj.groupRosters) == "table" and threadObj.groupRosters[entry.groupRosterId] then
        if type(saved.groupRosters) ~= "table" then saved.groupRosters = {} end
        saved.groupRosters[entry.groupRosterId] = threadObj.groupRosters[entry.groupRosterId]
    end
    if not isNotes then
        local trimmedRoster = false
        while #saved.lines > limit do
            local rem = table.remove(saved.lines, 1)
            if Chat._savedTextBytes ~= nil and rem then
                Chat._savedTextBytes = math.max(0, Chat._savedTextBytes - Chat:_EstimateEntryTextBytes(rem))
            end
            if rem and rem.groupRosterId then
                trimmedRoster = true
            end
        end
        if trimmedRoster and type(saved.groupRosters) == "table" then
            local keep = {}
            for _, ln in ipairs(saved.lines) do
                if type(ln) == "table" and ln.groupRosterId then
                    keep[ln.groupRosterId] = true
                end
            end
            for rk in pairs(saved.groupRosters) do
                if not keep[rk] then
                    saved.groupRosters[rk] = nil
                end
            end
        end
        if isNewThread and not IsProtectedThreadRecord(storageKey) and CountHashKeys(hist) > MAX_SAVED_THREADS then
            PruneSavedScopeTable(hist, HISTORY_TTL_SECONDS, MAX_SAVED_THREADS, GetHistoryStamp, IsProtectedThreadRecord)
        end
    end
    if Chat._savedTextBytes and Chat._savedTextBytes > (Chat._MAX_TEXT_HISTORY_BYTES or (6 * 1024 * 1024)) then
        Chat:_EnforceSavedHistoryTextQuota()
    end
end

local function RewriteThreadHistory(thread)
    if not thread or type(thread.key) ~= "string" then return end
    local limit = Chat:GetHistoryLimitForKey(thread.key)
    if limit <= 0 then return end
    local isNotes = (thread.key == "notes:self")
    local isGuild = Chat:IsGuildHistoryKey(thread.key)
    local isChannelLike = isGuild or Chat:IsGroupHistoryKey(thread.key) or Chat:IsGeneralHistoryKey(thread.key)
    local hist = GetHistoryScopeTable()
    if not hist then return end

    local storageKey = isGuild and Chat:GetGuildStorageKey(thread.key) or thread.key
    local prevBytes = (Chat._savedTextBytes ~= nil and type(hist[storageKey]) == "table") and Chat:_EstimateThreadRecordBytes(hist[storageKey]) or 0
    local outLines = {}
    local msgs = thread.messages or {}
    local startIdx = isNotes and 1 or math.max(1, #msgs - limit + 1)
    for i = startIdx, #msgs do
        local m = msgs[i]
        local allowNotice = (not m.isStatusNotice) or (thread.key == "ch:general" and not m.isCatchupNotice)
        if type(m) == "table" and allowNotice and type(m.text) == "string" and m.text ~= "" then
            outLines[#outLines + 1] = {
                sender = m.sender,
                targetChar = m.targetChar,
                text = m.text,
                ts = m.ts,
                incoming = m.incoming and true or false,
                classFile = m.classFile,
                targetClass = m.targetClass,
                senderFaction = m.senderFaction,
                targetFaction = m.targetFaction,
                senderLevel = (tonumber(m.senderLevel) and tonumber(m.senderLevel) > 0) and math.floor(tonumber(m.senderLevel)) or nil,
                viaAddon = m.viaAddon and true or nil,
                noteId = m.noteId,
                isMention = m.isMention and true or nil,
                mentionTerm = m.mentionTerm,
                mentionChannel = m.mentionChannel,
                mentionType = m.mentionType,
                rawText = m.rawText,
                senderCharName = m.senderCharName,
                senderLookupKey = m.senderLookupKey,
                senderGuid = m.senderGuid,
                sourceThreadKey = m.sourceThreadKey,
                groupRosterId = m.groupRosterId,
                generalTag = m.generalTag,
                msgKind = m.msgKind,
                noSenderColon = m.noSenderColon and true or nil,
                isStatusNotice = (thread.key == "ch:general" and m.isStatusNotice) and true or nil,
                channelId = m.channelId,
                guildEventKind = m.guildEventKind,
                guildTarget = m.guildTarget,
                guildActor = m.guildActor,
                guildRank = m.guildRank,
                guildActionSent = m.guildActionSent and true or nil,
            }
        end
    end
    local savedRosters = nil
    if type(thread.groupRosters) == "table" then
        for _, ol in ipairs(outLines) do
            if ol.groupRosterId and thread.groupRosters[ol.groupRosterId] then
                if not savedRosters then savedRosters = {} end
                savedRosters[ol.groupRosterId] = thread.groupRosters[ol.groupRosterId]
            end
        end
    end
    local guildName = nil
    if isGuild then
        local curGuild = Compat and Compat.GuildName and Compat.GuildName() or nil
        if type(curGuild) == "string" and curGuild ~= "" then
            guildName = curGuild
        elseif type(hist[storageKey]) == "table" and type(hist[storageKey].guildName) == "string" then
            guildName = hist[storageKey].guildName
        end
    end
    hist[storageKey] = {
        title = thread.title,
        targetName = thread.targetName,
        faction = thread.faction,
        guildName = guildName,
        level = (tonumber(thread.level) and tonumber(thread.level) > 0) and math.floor(tonumber(thread.level)) or nil,
        updatedAt = thread.lastAt or time(),
        unread = isChannelLike and 0 or math.max(0, math.floor(tonumber(thread.unread) or 0)),
        lines = outLines,
        groupRosters = savedRosters,
    }
    if Chat._savedTextBytes ~= nil then
        local newBytes = Chat:_EstimateThreadRecordBytes(hist[storageKey])
        Chat._savedTextBytes = math.max(0, Chat._savedTextBytes - prevBytes + newBytes)
        if Chat._savedTextBytes > (Chat._MAX_TEXT_HISTORY_BYTES or (6 * 1024 * 1024)) then
            Chat:_EnforceSavedHistoryTextQuota()
        end
    end
end

function Chat:TrimRuntimeMemory()
    local nowEpoch = time()
    local nowMono = (GetTime and GetTime()) or 0
    if type(self._recentWorldOnlyDedup) == "table" then
        for k, at in pairs(self._recentWorldOnlyDedup) do
            if (nowMono - (tonumber(at) or 0)) > 6.0 then
                self._recentWorldOnlyDedup[k] = nil
            end
        end
    end
    if type(self._worldLogDedup) == "table" then
        for k, at in pairs(self._worldLogDedup) do
            if (nowEpoch - (tonumber(at) or 0)) > 8 then
                self._worldLogDedup[k] = nil
            end
        end
    end
    if type(self._errorOriginLineCache) == "table" then
        for k, rec in pairs(self._errorOriginLineCache) do
            if type(rec) ~= "table" or (nowMono - (rec.at or 0)) > 3.0 then
                self._errorOriginLineCache[k] = nil
            end
        end
    end
    if type(self.silentNotFoundLedger) == "table" then
        for k, rec in pairs(self.silentNotFoundLedger) do
            if type(rec) ~= "table" or nowMono > (rec.expiresAt or 0) then
                self.silentNotFoundLedger[k] = nil
            end
        end
    end
    if type(self.lastWhisperCandidates) == "table" then
        for k, rec in pairs(self.lastWhisperCandidates) do
            if type(rec) ~= "table" or (nowMono - (rec.at or 0)) > 20 then
                self.lastWhisperCandidates[k] = nil
            end
        end
    end
    if type(self.seenAllianceMsgs) == "table" then
        for k, at in pairs(self.seenAllianceMsgs) do
            if (nowMono - (tonumber(at) or 0)) > 120 then
                self.seenAllianceMsgs[k] = nil
            end
        end
    end
    if self._ResetTransientShieldCaches then
        self:_ResetTransientShieldCaches()
    end
    local hist = GetHistoryScopeTable()
    if type(hist) == "table" and type(self.threads) == "table" then
        for key, t in pairs(self.threads) do
            if type(key) == "string" and key:sub(1, 2) == "w:" and type(t) == "table"
                and t._hydrated ~= false and type(t.messages) == "table" and #t.messages > 10
                and (tonumber(t.unread) or 0) == 0
                and (nowEpoch - (tonumber(t.lastAt) or 0)) > 600
                and not (self.IsThreadPinned and self:IsThreadPinned(key))
                and not (self.IsQuickReplyPinned and self:IsQuickReplyPinned(key))
                and not (ns.QuickReply and ns.QuickReply.IsViewingThread and ns.QuickReply:IsViewingThread(key))
                and not (ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible(key))
                and self.activeThreadKey ~= key
            then
                local histKey = t._savedHistKey or key
                local saved = hist[histKey]
                if type(saved) == "table" and type(saved.lines) == "table" and #saved.lines > 0 and self:ShouldPersistThreadKey(key) then
                    t._savedHistKey = histKey
                    t._savedCanonDisp = t.targetName or t.title
                    t._savedCount = math.min(#saved.lines, self:GetHistoryLimitForKey(key))
                    t._savedLastLine = saved.lines[#saved.lines]
                    t._hydrated = false
                    t.messages = {}
                end
            end
        end
    end
end

Chat._flushChatEmitFn = Chat._flushChatEmitFn or function()
    Chat._chatEmitQueued = false
    ns:Emit("CHAT_UPDATED")
end

local function QueueChatEmit(delay)
    if Chat._chatEmitQueued then return end
    Chat._chatEmitQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.30, Chat._flushChatEmitFn)
    else
        Chat._chatEmitQueued = false
        ns:Emit("CHAT_UPDATED")
    end
end

function Chat:EchoAddonMessageToOfficialFrames(thread, senderName, text, incoming, classFile, extraFields)
    if not thread or not text or text == "" then return false end
    local s = ns.db and ns.db.settings
    if incoming then
        if s and s.addonMsgChatEcho == false then return false end
    else
        if s and s.addonMsgChatEchoSent == false then return false end
    end

    local cleanPreview = Compat.CleanPayloadField(text, 220)
    if cleanPreview == "" then return false end
    if self.FormatRaidTargetTokens then
        cleanPreview = self:FormatRaidTargetTokens(cleanPreview)
    end

    local info
    if thread.kind == "ROOM" then
        info = _G.ChatTypeInfo and (_G.ChatTypeInfo["BN_WHISPER"] or _G.ChatTypeInfo["WHISPER"])
    elseif thread.kind == "ALLIANCE" then
        info = _G.ChatTypeInfo and _G.ChatTypeInfo["GUILD"]
    else
        info = _G.ChatTypeInfo and (incoming and _G.ChatTypeInfo["WHISPER"] or _G.ChatTypeInfo["WHISPER_INFORM"])
    end
    local r = (info and info.r) or 1.0
    local g = (info and info.g) or 0.5
    local b = (info and info.b) or 1.0

    local hex = classFile and Compat.ClassHex(classFile) or "|cffd2a8ff"
    local streamerOn = (Compat and Compat.IsStreamerMode and Compat.IsStreamerMode()) == true
    local line
    if thread.kind == "ROOM" or thread.kind == "ALLIANCE" then
        local sourceTag = (thread.kind == "ALLIANCE") and L["Alliance"]
            or ((not streamerOn and thread.title and thread.title ~= "") and thread.title or L["Private Room"])
        local roomSender = tostring(senderName or "?")
        if streamerOn and roomSender:find("#", 1, true) and Compat.MaskStreamerBNetName then
            roomSender = Compat.MaskStreamerBNetName(roomSender)
        end
        line = string.format("|cff3fb950[SC %s]|r |Haddon:SCentral:thread:%s|h%s[%s]|r|h: %s",
            tostring(sourceTag),
            tostring(thread.key),
            hex,
            roomSender,
            cleanPreview)
    elseif incoming then
        local disp = tostring(senderName or thread.title or "?")
        if streamerOn and (thread.kind == "BN_WHISPER" or disp:find("#", 1, true)) and Compat.MaskStreamerBNetName then
            disp = Compat.MaskStreamerBNetName(disp)
        end
        line = string.format("|cff3fb950[SC]|r |Haddon:SCentral:thread:%s|h%s[%s]|r|h: %s",
            tostring(thread.key),
            hex,
            disp,
            cleanPreview)
    else
        local targetDisp = tostring((extraFields and extraFields.targetChar) or thread.targetName or thread.title or "?")
        if streamerOn and (thread.kind == "BN_WHISPER" or targetDisp:find("#", 1, true)) and Compat.MaskStreamerBNetName then
            targetDisp = Compat.MaskStreamerBNetName(targetDisp)
        end
        line = string.format("|cff3fb950[SC]|r |cff88d2ff%s|r |Haddon:SCentral:thread:%s|h%s[%s]|r|h: %s",
            L["To"],
            tostring(thread.key),
            hex,
            targetDisp,
            cleanPreview)
    end

    local framesCfg = s and s.addonChatFrames
    local delivered = false
    for chatID = 1, 10 do
        local enabled = (type(framesCfg) ~= "table" and chatID == 1)
            or (type(framesCfg) == "table" and framesCfg[chatID] == true)
        if enabled then
            local cf = _G["ChatFrame" .. tostring(chatID)]
            if cf and cf.AddMessage then
                local isActiveTab = (chatID == 1) or cf.isDocked or cf:IsShown()
                if not isActiveTab and GetChatWindowInfo then
                    local ok, winName, _, _, _, _, _, isShownFlag = pcall(GetChatWindowInfo, chatID)
                    if ok then
                        winName = Safe.String(winName)
                        isShownFlag = Safe.Bool(isShownFlag)
                        if winName and winName ~= "" and isShownFlag then
                            isActiveTab = true
                        end
                    end
                end
                if isActiveTab then
                    cf:AddMessage(line, r, g, b)
                    delivered = true
                end
            end
        end
    end
    return delivered
end

local function LookupClassFromCache(lookupKey, guid)
    if not lookupKey and not guid then return nil end
    if guid and Compat.ClassFileFromGuid then
        local cf = Compat.ClassFileFromGuid(guid)
        if cf then return cf end
    end
    local altsTbl = ns.db and ns.db.alts
    if lookupKey and type(altsTbl) == "table" then
        local qLk, qFirst, _, qSurname = Compat.ParseCharacterFields(lookupKey)
        local fLow = qFirst and qFirst:lower() or nil
        local fCount, fClass = 0, nil
        for _, alt in pairs(altsTbl) do
            if type(alt) == "table" and alt.classFile and not (guid and alt.guid and alt.guid ~= guid) then
                if not Store or not Store.AltMatchesWorldScope or Store:AltMatchesWorldScope(alt, "pool") then
                    local aLk, aFirst = Compat.ParseCharacterFields(alt.fullName or alt.name or "")
                    if qLk and aLk == qLk then
                        return alt.classFile
                    elseif (not qSurname or qSurname == "") and fLow and aFirst and aFirst:lower() == fLow then
                        fCount = fCount + 1
                        fClass = alt.classFile
                    end
                end
            end
        end
        if fCount == 1 and fClass then
            return fClass
        end
    end
    if Store and Store.social then
        local byGuid = Store.socialByGuid
        local byLookup = Store.socialByLookup
        if byGuid or byLookup then
            local gRow = guid and byGuid and byGuid[guid]
            if gRow and gRow.classFile then return gRow.classFile end
            if lookupKey then
                local lRow = byLookup and byLookup[lookupKey]
                if lRow and lRow.classFile and not (guid and lRow.guid and lRow.guid ~= guid) then
                    return lRow.classFile
                end
            end
        elseif lookupKey then
            local direct = Store.social[lookupKey]
            if direct and direct.classFile then return direct.classFile end
            for _, row in pairs(Store.social) do
                if type(row) == "table" and row.lookupKey == lookupKey and row.classFile then
                    return row.classFile
                end
            end
        end
    end
    if lookupKey then
        if Store and Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookupKey] then
            local dr = Store.socialDirectoryByLookup[lookupKey]
            if dr.classFile and not (guid and dr.guid and dr.guid ~= guid) then
                return dr.classFile
            end
        end
        if Store and Store.nearby and Store.nearby[lookupKey] then
            return Store.nearby[lookupKey].classFile
        end
        if Store and Store.GetWatchlistTable then
            local wl = Store:GetWatchlistTable()
            if wl and wl[lookupKey] then
                return wl[lookupKey].classFile
            end
        end
        if Store and Store.GetFriendPresence then
            local pres = Store:GetFriendPresence(lookupKey)
            if pres and pres.classFile then
                return pres.classFile
            end
        end
        if ns.Clan and ns.Clan.GetCachedLfgPlayerInfo then
            local lfgRec = ns.Clan:GetCachedLfgPlayerInfo(lookupKey)
            if lfgRec and lfgRec.classFile then
                return lfgRec.classFile
            end
        end
    end
    return nil
end

local whoLevelCache = {}
local whoLevelCount = 0
local MAX_WHO_LEVEL_CACHE = 500

local function ValidLevel(val)
    local n = tonumber(val)
    if n and n > 0 then
        return math.floor(n)
    end
    return nil
end

local function MatchUnitTokenLevel(unit, lk, firstLow, hasSurname, guid)
    if not (unit and UnitExists and Safe) then return nil end
    if Safe.Value(Safe.Call(UnitExists, unit)) ~= true then return nil end
    if Safe.Value(Safe.Call(UnitIsPlayer, unit)) ~= true then return nil end
    local matched = false
    local uGuid = Safe.String(Safe.Call(UnitGUID, unit))
    if guid and uGuid and guid == uGuid then
        matched = true
    elseif (lk or firstLow) and Compat and Compat.ResolveUnitFullName then
        local resolved = Compat.ResolveUnitFullName(unit, uGuid, nil, true)
        if resolved then
            if lk and resolved.lookupKey == lk then
                matched = true
            elseif (not hasSurname) and firstLow and resolved.firstName and resolved.firstName:lower() == firstLow then
                matched = true
            end
        end
    end
    if not matched then return nil end
    return ValidLevel(Safe.Number(Safe.Call(UnitLevel, unit)))
end

local function LookupLevelFromCache(lookupKey, displayName, guid, bnetAccountID, cacheOnly)
    local dispStr = (type(displayName) == "string" and not (Safe.IsSecret and Safe.IsSecret(displayName))) and displayName or nil
    if dispStr then
        dispStr = dispStr:gsub("^<[^>]+>%s*", "")
    end
    local lk = (type(lookupKey) == "string" and lookupKey ~= "") and lookupKey or nil
    local firstLow, hasSurname = nil, false
    if (not lk) and dispStr and dispStr ~= "" and not dispStr:find("|K", 1, true) and not dispStr:find("#", 1, true) and Compat.ParseCharacterFields then
        local pLk, pFirst, _, pSur = Compat.ParseCharacterFields(dispStr)
        lk = pLk
        firstLow = pFirst and pFirst:lower() or nil
        hasSurname = (pSur ~= nil and pSur ~= "")
    elseif lk and Compat.ParseCharacterFields then
        local pLk, pFirst, _, pSur = Compat.ParseCharacterFields(lk)
        if pLk and pLk ~= "" then
            lk = pLk
        end
        firstLow = pFirst and pFirst:lower() or nil
        hasSurname = (pSur ~= nil and pSur ~= "")
    end

    if (dispStr and Compat.IsMe and Compat.IsMe(dispStr, guid)) or (lk and Compat.IsMe and Compat.IsMe(lk, guid)) then
        local meLvl = ValidLevel(Safe.Number(Safe.Call(UnitLevel, "player")))
        if meLvl then return meLvl end
    end

    local resolvedLvl = nil
    if Store then
        local byGuid = Store.socialByGuid
        local gRow = guid and byGuid and byGuid[guid]
        resolvedLvl = ValidLevel(gRow and gRow.level)
        if not resolvedLvl and lk and Store.socialByLookup then
            local lRow = Store.socialByLookup[lk]
            if lRow and not (guid and lRow.guid and lRow.guid ~= guid) then
                resolvedLvl = ValidLevel(lRow.level)
            end
        end
        if not resolvedLvl and lk and Store.socialDirectoryByLookup then
            local dr = Store.socialDirectoryByLookup[lk]
            if dr and not (guid and dr.guid and dr.guid ~= guid) then
                resolvedLvl = ValidLevel(dr.level)
            end
        end
    end

    if not resolvedLvl and ns.Group and type(ns.Group.members) == "table" and (lk or guid) then
        for _, gm in ipairs(ns.Group.members) do
            if type(gm) == "table" and ((guid and gm.guid == guid) or (lk and gm.lookupKey == lk)) then
                resolvedLvl = ValidLevel(gm.level)
                if resolvedLvl then break end
            end
        end
    end

    if not resolvedLvl and Chat.GetBNetCachedLevel and (lk or guid or bnetAccountID) then
        resolvedLvl = ValidLevel(Chat:GetBNetCachedLevel(lk, guid, bnetAccountID))
    end

    if (not cacheOnly) and not resolvedLvl and (guid or lk or firstLow) then
        for _, u in ipairs({ "target", "focus", "mouseover" }) do
            resolvedLvl = MatchUnitTokenLevel(u, lk, firstLow, hasSurname, guid)
            if resolvedLvl then break end
        end
        if not resolvedLvl and Compat.IsInRaid and Compat.IsInRaid() then
            local n = (Compat.GetNumGroupMembers and Compat.GetNumGroupMembers()) or 0
            for i = 1, math.min(n, 40) do
                resolvedLvl = MatchUnitTokenLevel("raid" .. tostring(i), lk, firstLow, hasSurname, guid)
                if resolvedLvl then break end
            end
        elseif not resolvedLvl and Compat.IsInGroup and Compat.IsInGroup() then
            for i = 1, 4 do
                resolvedLvl = MatchUnitTokenLevel("party" .. tostring(i), lk, firstLow, hasSurname, guid)
                if resolvedLvl then break end
            end
        end
        if not resolvedLvl then
            for i = 1, 40 do
                local np = "nameplate" .. tostring(i)
                if Safe.Value(Safe.Call(UnitExists, np)) == true then
                    resolvedLvl = MatchUnitTokenLevel(np, lk, firstLow, hasSurname, guid)
                    if resolvedLvl then break end
                end
            end
        end
    end

    if not resolvedLvl and lk and Store then
        if Store.nearby and Store.nearby[lk] then
            resolvedLvl = ValidLevel(Store.nearby[lk].level)
        end
        if not resolvedLvl and ns.Watchlist and ns.Watchlist.GetEntry then
            local wl = ns.Watchlist:GetEntry(lk)
            resolvedLvl = ValidLevel(wl and wl.level)
        elseif not resolvedLvl and Store.GetWatchlistTable then
            local wlTbl = Store:GetWatchlistTable()
            resolvedLvl = ValidLevel(wlTbl and wlTbl[lk] and wlTbl[lk].level)
        end
        if not resolvedLvl and Store.liveUnitObs and Store.liveUnitObs[lk] then
            resolvedLvl = ValidLevel(Store.liveUnitObs[lk].level)
        end
        if not resolvedLvl and Store.GetFriendPresence then
            local pres = Store:GetFriendPresence(lk)
            resolvedLvl = ValidLevel(pres and (pres.lastLevel or pres.level))
        end
        if not resolvedLvl and Store.GetRecentCompanion then
            local comp = Store:GetRecentCompanion(lk)
            resolvedLvl = ValidLevel(comp and comp.level)
        end
    end

    if not resolvedLvl and ns.Spotter then
        local sp = (guid and ns.Spotter.entryByGuid and ns.Spotter.entryByGuid[guid])
            or (lk and ns.Spotter.entries and ns.Spotter.entries[lk])
        resolvedLvl = ValidLevel(sp and sp.level)
    end

    if not resolvedLvl and lk and ns.Clan and ns.Clan.GetCachedLfgPlayerInfo then
        local lfgRec = ns.Clan:GetCachedLfgPlayerInfo(lk, dispStr)
        resolvedLvl = ValidLevel(lfgRec and lfgRec.level)
    end

    if (not cacheOnly) and not resolvedLvl and lk and ns.db and type(ns.db.alts) == "table" then
        for _, alt in pairs(ns.db.alts) do
            if type(alt) == "table" and ValidLevel(alt.level) and not (guid and alt.guid and alt.guid ~= guid) then
                if not Store or not Store.AltMatchesWorldScope or Store:AltMatchesWorldScope(alt, "pool") then
                    local aLk = Compat.ParseCharacterFields(alt.fullName or alt.name or "")
                    if aLk == lk then
                        resolvedLvl = ValidLevel(alt.level)
                        break
                    end
                end
            end
        end
    end

    if not resolvedLvl and lk and whoLevelCache[lk] then
        resolvedLvl = ValidLevel(whoLevelCache[lk])
    end

    if not resolvedLvl and lk and Chat.threads and Chat.threads["w:" .. lk] then
        resolvedLvl = ValidLevel(Chat.threads["w:" .. lk].level)
    end

    if resolvedLvl and lk and Chat.threads and Chat.threads["w:" .. lk] then
        Chat.threads["w:" .. lk].level = resolvedLvl
    end
    return resolvedLvl
end

function Chat:ResolvePlayerLevel(lookupKey, displayName, guid, bnetAccountID, cacheOnly)
    return LookupLevelFromCache(lookupKey, displayName, guid, bnetAccountID, cacheOnly)
end

function Chat:RecordWhoObservation(fullName, level, classFile, area, guild, skipEmit, obsSource)
    if type(fullName) ~= "string" or fullName == "" then return false end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(fullName)
    local lk = parsed and parsed.lookupKey
    if not lk or lk == "" then return false end
    local lvl = ValidLevel(level)
    local cleanCls = (type(classFile) == "string" and classFile ~= "") and classFile or nil
    local cleanArea = (type(area) == "string" and area ~= "") and area or nil
    local cleanGuild = (type(guild) == "string" and guild ~= "") and guild or nil
    local changed = false

    if lvl then
        if whoLevelCache[lk] == nil then
            if whoLevelCount >= MAX_WHO_LEVEL_CACHE then
                wipe(whoLevelCache)
                whoLevelCount = 0
            end
            whoLevelCount = whoLevelCount + 1
        end
        if whoLevelCache[lk] ~= lvl then
            whoLevelCache[lk] = lvl
            changed = true
        end
    end

    local wt = Chat.threads and Chat.threads["w:" .. lk]
    if wt then
        if lvl and (not wt.level or wt.level <= 0 or wt.level < lvl) then
            wt.level = lvl
            changed = true
        end
        if cleanCls and (not wt.classFile or wt.classFile == "") then
            wt.classFile = cleanCls
            changed = true
        end
    end

    if Store and Store.RecordLiveUnitObservation and (lvl or cleanCls or cleanArea or cleanGuild) then
        Store:RecordLiveUnitObservation(parsed.displayName, {
            level = lvl,
            classFile = cleanCls,
            area = cleanArea,
            guild = cleanGuild,
            source = obsSource or "who",
        })
        changed = true
    end

    if changed and not skipEmit then
        QueueChatEmit(0.1)
    end
    return changed
end

local function LookupGuidFromCache(lookupKey)
    if not lookupKey or lookupKey == "" then return nil end
    if Store then
        local byLookup = Store.socialByLookup
        if byLookup and byLookup[lookupKey] and byLookup[lookupKey].guid then
            return byLookup[lookupKey].guid
        end
        if Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookupKey] and Store.socialDirectoryByLookup[lookupKey].guid then
            return Store.socialDirectoryByLookup[lookupKey].guid
        end
        if Store.nearby and Store.nearby[lookupKey] and Store.nearby[lookupKey].guid then
            return Store.nearby[lookupKey].guid
        end
    end
    return nil
end

local function ResolvePreviewCategory(threadKind, extraFields)
    if extraFields and extraFields.previewCategory then
        return extraFields.previewCategory
    end
    if threadKind == "BN_WHISPER" then
        return "BN_WHISPER"
    elseif threadKind == "WHISPER" then
        return "WHISPER"
    elseif threadKind == "PARTY" or threadKind == "RAID" or threadKind == "INSTANCE_CHAT" then
        return "GROUP"
    elseif threadKind == "GUILD" or threadKind == "OFFICER" then
        return "GUILD"
    elseif threadKind == "ROOM" or threadKind == "ALLIANCE" then
        return "ROOM"
    end
    return nil
end

local function ResolvePreviewChannelKind(threadKind, extraFields)
    if extraFields and extraFields.previewChannelKind then
        return extraFields.previewChannelKind
    end
    if extraFields and extraFields.viaAddon and threadKind == "WHISPER" then
        return "DIRECT"
    end
    return threadKind
end

Chat._GENERAL_TAG_HEX = {
    WHISPER = "|cffff7fff",
    DIRECT = "|cffff7fff",
    BN_WHISPER = "|cff1ad1ff",
    PARTY = "|cff7aaeff",
    INSTANCE_CHAT = "|cff7aaeff",
    RAID = "|cffff8a2e",
    GUILD = "|cff47ef66",
    OFFICER = "|cff47ef66",
    ALLIANCE = "|cffbd80ff",
    ROOM = "|cffc084fc",
    LOCAL_SAY = "|cffffffff",
    LOCAL_YELL = "|cffff4d4d",
    PUB_CHANNEL = "|cffffc0c0",
    SYSTEM = "|cffffff00",
    LOOT = "|cff47ef66",
    XP = "|cff8899ff",
    ACHIEVEMENT = "|cffffd24d",
    MONSTER = "|cffffa040",
}

Chat._recentGeneralDedup = Chat._recentGeneralDedup or {}

function Chat:_NormalizeGeneralDedupText(rawText)
    if Safe.IsSecret(rawText) or type(rawText) ~= "string" then
        return nil
    end
    local s = rawText
    if s:find("|K", 1, true) then
        s = s:gsub("|K[^|]*|k", "")
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", " ")
    s = s:gsub("{rt[1-8]}", " ")
    s = s:gsub("|A.-|a", " ")
    s = s:gsub("|H(item:%d+)[^|]*|h[^|]*|h", "<%1>")
    s = s:gsub("|H(spell:%d+)[^|]*|h[^|]*|h", "<%1>")
    s = s:gsub("|H(quest:%d+)[^|]*|h[^|]*|h", "<%1>")
    s = s:gsub("|H(achievement:%d+)[^|]*|h[^|]*|h", "<%1>")
    s = s:gsub("|H(enchant:%d+)[^|]*|h[^|]*|h", "<%1>")
    for _ = 1, 6 do
        local nextS = s:gsub("|H[^|]-|h(.-)|h", "%1")
        if nextS == s then break end
        s = nextS
    end
    s = s:gsub("[%c]+", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    if s == "" then
        return nil
    end
    return (Compat.LowerUtf8 and Compat.LowerUtf8(s)) or s:lower()
end

function Chat:_ExtractGeneralSenderKey(rawSenderOrLink, isMeHint)
    if isMeHint == true then
        return "__me__"
    end
    local rawStr = Safe.String(rawSenderOrLink)
    if not rawStr or rawStr == "" then
        return nil
    end
    local linkName = rawStr:match("|Hplayer[^|]*|h%[([^%]]+)%]|h")
        or rawStr:match("|HBNplayer[^|]*|h%[([^%]]+)%]|h")
        or rawStr:match("|Hplayer[^:]*:([^:|]+)")
        or rawStr:match("^%[[^%]]+%]%s*%[([^%]]+)%]%s*:")
        or rawStr
    local clean = linkName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%[", ""):gsub("%]$", "")
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(clean)
    local disp = (parsed and parsed.displayName) or clean
    if disp and Compat.IsMe and Compat.IsMe(disp) then
        return "__me__"
    end
    local lk = (parsed and parsed.lookupKey) or ((Compat.LowerUtf8 and Compat.LowerUtf8(disp)) or disp:lower())
    return (lk and lk ~= "") and lk or nil
end

function Chat:_RememberWorldOnlyNotice(rawText)
    local sig = self:_NormalizeGeneralDedupText(rawText)
    if not sig then return end
    self._recentWorldOnlyDedup = self._recentWorldOnlyDedup or {}
    local nowMono = (GetTime and GetTime()) or 0
    self._recentWorldOnlyDedup[sig] = nowMono
    self._worldOnlyDedupCount = (self._worldOnlyDedupCount or 0) + 1
    if self._worldOnlyDedupCount > 80 then
        for k, at in pairs(self._recentWorldOnlyDedup) do
            if (nowMono - (tonumber(at) or 0)) > 6.0 then
                self._recentWorldOnlyDedup[k] = nil
            end
        end
        self._worldOnlyDedupCount = 0
    end
end

function Chat:_WasRecentlyWorldOnlyNotice(rawText)
    local sig = self:_NormalizeGeneralDedupText(rawText)
    if not (sig and self._recentWorldOnlyDedup) then return false end
    local at = self._recentWorldOnlyDedup[sig]
    if not at then return false end
    local nowMono = (GetTime and GetTime()) or 0
    return (nowMono - at) <= 4.0
end

function Chat:_RememberGeneralDedup(rawText, senderKey)
    local sig = self:_NormalizeGeneralDedupText(rawText)
    if not sig then return end
    local list = self._recentGeneralDedup
    if not list then
        list = {}
        self._recentGeneralDedup = list
    end
    local cap = 80
    local nowMono = (GetTime and GetTime()) or 0
    local count = self._recentGenDedupCount or 0
    local head = self._recentGenDedupHead or 0
    local writeIdx = (head % cap) + 1
    local rec = list[writeIdx]
    if type(rec) ~= "table" then
        rec = {}
        list[writeIdx] = rec
    end
    rec.sig = sig
    rec.sender = senderKey
    rec.at = nowMono
    self._recentGenDedupHead = writeIdx
    if count < cap then
        self._recentGenDedupCount = count + 1
    end
end

function Chat:_WasRecentlyRecordedInGeneral(rawText, senderKey)
    local norm = self:_NormalizeGeneralDedupText(rawText)
    if not norm then return true end
    local bodyPart = norm:match(":%s*(.+)$") or norm
    local list = self._recentGeneralDedup
    local nowMono = (GetTime and GetTime()) or 0
    local cap = 80
    local count = self._recentGenDedupCount or (type(list) == "table" and #list or 0)
    local head = self._recentGenDedupHead or count
    if type(list) == "table" and count > 0 then
        for step = 0, count - 1 do
            local idx = ((head - 1 - step) % cap) + 1
            local item = list[idx]
            if item and item.sig and item.sig ~= "" then
                if (nowMono - (item.at or 0)) > 18.0 then
                    break
                end
                local senderMatch = (not senderKey) or (not item.sender) or (senderKey == item.sender)
                if senderMatch then
                    local sig = item.sig
                    local sigBody = sig:match(":%s*(.+)$") or sig
                    if norm == sig or bodyPart == sig or bodyPart == sigBody or norm == sigBody then
                        return true
                    end
                    if #norm > #sigBody and norm:sub(-#sigBody) == sigBody then
                        return true
                    end
                    if #sigBody >= 6 and norm:find(sigBody, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    if senderKey == "__me__" then
        local genThread = self.threads and self.threads["ch:general"]
        local msgs = genThread and genThread.messages
        if type(msgs) == "table" and #msgs > 0 then
            local nowEpoch = time()
            local scanStart = math.max(1, #msgs - 14)
            for i = #msgs, scanStart, -1 do
                local m = msgs[i]
                if m and (m.incoming == false) and (nowEpoch - (tonumber(m.ts) or 0)) <= 25 then
                    local mNorm = self:_NormalizeGeneralDedupText(m.text)
                    if mNorm and (mNorm == bodyPart or mNorm == norm) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Chat:IsChatHistoryCaptureEnabled()
    return not ns.db or not ns.db.settings or ns.db.settings.moduleChatEnabled ~= false
end

Chat.GENERAL_FEED_FILTERS = {
    { key = "loot", labelKey = "Loot" },
    { key = "achievement", labelKey = "Achievements" },
    { key = "monster", labelKey = "World, Bosses & NPCs" },
    { key = "system", labelKey = "System & Notices" },
    { key = "public", labelKey = "Public Channels (/1, /2...)" },
    { key = "sayYell", labelKey = "Say, Yell & Emotes (/s, /y, /e)" },
}

function Chat:GetGeneralFilterTable()
    local s = ns.db and ns.db.settings
    if not s then return nil end
    if type(s.generalFeedFilters) ~= "table" then
        s.generalFeedFilters = {
            loot = true,
            achievement = true,
            monster = true,
            system = true,
            public = true,
            sayYell = true,
        }
    end
    return s.generalFeedFilters
end

function Chat:IsGeneralCategoryEnabled(catKey)
    if not catKey then return true end
    local tbl = self:GetGeneralFilterTable()
    if tbl and tbl[catKey] == false then
        return false
    end
    return true
end

function Chat:GetGeneralFilterCounts()
    local total = #self.GENERAL_FEED_FILTERS
    local enabled = 0
    for i = 1, total do
        if self:IsGeneralCategoryEnabled(self.GENERAL_FEED_FILTERS[i].key) then
            enabled = enabled + 1
        end
    end
    return enabled, total
end

function Chat:GetGeneralFilterSignature()
    local buf = self._genFilterSigScratch
    if not buf then
        buf = {}
        self._genFilterSigScratch = buf
    else
        wipe(buf)
    end
    for i = 1, #self.GENERAL_FEED_FILTERS do
        local def = self.GENERAL_FEED_FILTERS[i]
        buf[i] = def.key .. (self:IsGeneralCategoryEnabled(def.key) and "1" or "0")
    end
    return table.concat(buf, ";")
end

function Chat:SetGeneralCategoryEnabled(catKey, enabled)
    if not catKey then return end
    local tbl = self:GetGeneralFilterTable()
    if tbl then
        tbl[catKey] = (enabled ~= false)
    end
    ns:Emit("CHAT_UPDATED")
end

function Chat:ResetGeneralFeedFilters()
    local tbl = self:GetGeneralFilterTable()
    if tbl then
        for i = 1, #self.GENERAL_FEED_FILTERS do
            tbl[self.GENERAL_FEED_FILTERS[i].key] = true
        end
    end
    ns:Emit("CHAT_UPDATED")
end

function Chat:ClassifyGeneralEntry(entryOrKind, text, customTag)
    local msgKind = (type(entryOrKind) == "table") and entryOrKind.msgKind or entryOrKind
    if msgKind == "LOOT" then
        return "loot"
    elseif msgKind == "ACHIEVEMENT" then
        return "achievement"
    elseif msgKind == "MONSTER" then
        return "monster"
    elseif msgKind == "PUB_CHANNEL" then
        return "public"
    elseif msgKind == "LOCAL_SAY" or msgKind == "LOCAL_YELL" then
        return "sayYell"
    elseif msgKind == "SYSTEM" or msgKind == "XP" then
        return "system"
    end
    local rawTag = (type(entryOrKind) == "table" and entryOrKind.generalTag) or customTag or ""
    local plainTag = tostring(rawTag):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%[", ""):gsub("%]$", "")
    local lowerFn = (Compat and Compat.LowerUtf8) or nil
    local plainTagLow = lowerFn and lowerFn(plainTag) or plainTag:lower()
    if plainTagLow ~= "" then
        local lootLow = lowerFn and lowerFn(L["Loot"] or "Loot") or tostring(L["Loot"] or "Loot"):lower()
        local achLow = lowerFn and lowerFn(L["Achievement"] or "Achievement") or tostring(L["Achievement"] or "Achievement"):lower()
        local worldLow = lowerFn and lowerFn(L["World"] or "World") or tostring(L["World"] or "World"):lower()
        local sysLow = lowerFn and lowerFn(L["System"] or "System") or tostring(L["System"] or "System"):lower()
        local sayLow = lowerFn and lowerFn(L["Say"] or "Say") or tostring(L["Say"] or "Say"):lower()
        local yellLow = lowerFn and lowerFn(L["Yell"] or "Yell") or tostring(L["Yell"] or "Yell"):lower()
        local emoteLow = lowerFn and lowerFn(L["Emote"] or "Emote") or tostring(L["Emote"] or "Emote"):lower()
        if plainTagLow == lootLow or plainTagLow == "loot" or plainTagLow == "saque" or plainTagLow == "botín" or plainTagLow == "botin" then
            return "loot"
        elseif plainTagLow == achLow or plainTagLow == "achievement" or plainTagLow == "conquista" or plainTagLow == "logro" then
            return "achievement"
        elseif plainTagLow == worldLow or plainTagLow == "world" or plainTagLow == "mundo" then
            return "monster"
        elseif plainTagLow == sayLow or plainTagLow == yellLow or plainTagLow == emoteLow
            or plainTagLow == "say" or plainTagLow == "yell" or plainTagLow == "emote"
            or plainTagLow == "dizer" or plainTagLow == "decir" or plainTagLow == "gritar"
            or plainTagLow == "expressão" or plainTagLow == "expressao" or plainTagLow == "emoción" or plainTagLow == "emocion"
        then
            return "sayYell"
        elseif plainTagLow == sysLow or plainTagLow == "sc" or plainTagLow == "system" or plainTagLow == "sistema" then
            return "system"
        end
    end
    if type(entryOrKind) == "table" then
        if entryOrKind.channelId ~= nil then
            return "public"
        end
        local txt = tostring(entryOrKind.text or text or "")
        if entryOrKind.isStatusNotice then
            if txt:sub(1, 10) == "|cff47ef66" then
                return "loot"
            elseif txt:sub(1, 10) == "|cffffd24d" then
                return "achievement"
            end
            return "system"
        end
    end
    return "public"
end

function Chat:IsGeneralEntryVisible(entry)
    if type(entry) ~= "table" then
        return true
    end
    local cat = self:ClassifyGeneralEntry(entry)
    return self:IsGeneralCategoryEnabled(cat)
end

function Chat:CollectGeneralVisibleIndices(msgs, maxKeep, scratch)
    local out = scratch or {}
    wipe(out)
    local total = type(msgs) == "table" and #msgs or 0
    if total <= 0 then
        return out
    end
    local limit = (type(maxKeep) == "number" and maxKeep > 0) and maxKeep or total
    for idx = total, 1, -1 do
        local m = msgs[idx]
        if type(m) == "table" and m.text and self:IsGeneralEntryVisible(m) then
            out[#out + 1] = idx
            if #out >= limit then
                break
            end
        end
    end
    local n = #out
    for i = 1, math.floor(n / 2) do
        out[i], out[n - i + 1] = out[n - i + 1], out[i]
    end
    return out
end

function Chat:PopulateGeneralFilterMenu(subMenu, afterToggleFn)
    if not subMenu or not subMenu.CreateCheckbox then
        return
    end
    if subMenu.CreateTitle then
        subMenu:CreateTitle(L["Choose which notifications appear in General"])
    end
    for i = 1, #self.GENERAL_FEED_FILTERS do
        local def = self.GENERAL_FEED_FILTERS[i]
        subMenu:CreateCheckbox(L[def.labelKey], function()
            return self:IsGeneralCategoryEnabled(def.key)
        end, function()
            local nextState = not self:IsGeneralCategoryEnabled(def.key)
            self:SetGeneralCategoryEnabled(def.key, nextState)
            if afterToggleFn then
                afterToggleFn()
            end
        end)
    end
    local enCnt, totCnt = self:GetGeneralFilterCounts()
    if enCnt < totCnt and subMenu.CreateButton then
        if subMenu.CreateDivider then
            subMenu:CreateDivider()
        end
        subMenu:CreateButton(L["Show All"], function()
            self:ResetGeneralFeedFilters()
            if afterToggleFn then
                afterToggleFn()
            end
        end)
    end
end

function Chat:AttachGeneralFilterSubmenu(root, afterToggleFn)
    if not (root and root.CreateButton) then
        return nil
    end
    local enCnt, totCnt = self:GetGeneralFilterCounts()
    local filterLbl = L["Show Notifications"]
    if totCnt > 0 and enCnt < totCnt then
        filterLbl = filterLbl .. " (" .. tostring(enCnt) .. "/" .. tostring(totCnt) .. ")"
    end
    local filterSub = root:CreateButton(filterLbl)
    self:PopulateGeneralFilterMenu(filterSub, afterToggleFn)
    return filterSub
end

function Chat:RecordGeneralMessage(kind, senderDisp, text, isMe, resolvedClass, customTag, extraFields)
    if not self:IsChatHistoryCaptureEnabled() then
        return nil
    end
    local cleanText = Safe.String(text)
    if not cleanText or cleanText == "" then
        return nil
    end
    local msgKind = kind or "PUB_CHANNEL"
    local catKey = self:ClassifyGeneralEntry(msgKind, cleanText, customTag)
    if not self:IsGeneralCategoryEnabled(catKey) then
        return nil
    end
    local genMeta = STATIC_CHANNEL_ORDER["ch:general"]
    local genTitle = (genMeta and L[genMeta.titleKey]) or L["General"]
    local genThread = EnsureThread("ch:general", "GENERAL", genTitle, { slash = "/s " })
    if not genThread then
        return nil
    end
    local tagMarkup = nil
    if not (extraFields and extraFields.noTag == true) then
        local rawTag = Safe.String(customTag)
        if (not rawTag or rawTag == "") then
            if kind == "WHISPER" or kind == "DIRECT" then rawTag = L["Whisper"]
            elseif kind == "BN_WHISPER" then rawTag = L["Battle.net"]
            elseif kind == "PARTY" then rawTag = L["Party"]
            elseif kind == "INSTANCE_CHAT" then rawTag = L["Instance"]
            elseif kind == "RAID" then rawTag = L["Raid"]
            elseif kind == "GUILD" then rawTag = L["Guild"]
            elseif kind == "OFFICER" then rawTag = L["Officer"]
            elseif kind == "ALLIANCE" then rawTag = L["Alliance"]
            elseif kind == "ROOM" then rawTag = L["Private Room"]
            elseif kind == "LOCAL_SAY" then rawTag = L["Say"]
            elseif kind == "LOCAL_YELL" then rawTag = L["Yell"]
            elseif kind == "SYSTEM" then rawTag = L["System"]
            elseif kind == "LOOT" then rawTag = L["Loot"]
            elseif kind == "XP" then rawTag = L["Progress"]
            elseif kind == "ACHIEVEMENT" then rawTag = L["Achievement"]
            elseif kind == "MONSTER" then rawTag = L["World"]
            else rawTag = L["Channel"]
            end
        end
        local hex = (Chat._GENERAL_TAG_HEX and Chat._GENERAL_TAG_HEX[kind or "PUB_CHANNEL"]) or "|cffc8dcfa"
        tagMarkup = hex .. "[" .. rawTag .. "]|r"
    end
    local ts = (extraFields and tonumber(extraFields.customTs)) or time()
    local isNotice = (extraFields and extraFields.isStatusNotice == true)
    local noColon = (extraFields and extraFields.noSenderColon == true)
    local senderKey = self:_ExtractGeneralSenderKey((extraFields and extraFields.senderCharName) or senderDisp, isMe == true)
    local dedupNorm = self:_NormalizeGeneralDedupText(cleanText)
    local isBackfill = (extraFields and extraFields.isBackfill == true)
    local dedupWinSec = isBackfill and 86400 or 3
    if not (extraFields and extraFields.allowDuplicate == true) and dedupNorm and #genThread.messages > 0 then
        local scanDepth = isBackfill and 60 or 9
        local scanFloor = math.max(1, #genThread.messages - scanDepth)
        for i = #genThread.messages, scanFloor, -1 do
            local prev = genThread.messages[i]
            if prev and math.abs(ts - (tonumber(prev.ts) or 0)) <= dedupWinSec then
                local prevNorm = prev._dedupSig or self:_NormalizeGeneralDedupText(prev.text)
                if prevNorm and prevNorm == dedupNorm then
                    local prevSenderKey = prev._dedupSenderKey or self:_ExtractGeneralSenderKey(prev.senderCharName or prev.sender, prev.incoming == false)
                    local sameSide = ((isNotice == true) and (prev.isStatusNotice == true))
                        or (senderKey and prevSenderKey and senderKey == prevSenderKey)
                        or (not senderKey and not prevSenderKey)
                    if sameSide then
                        return prev
                    end
                end
            end
        end
    end
    if not (extraFields and extraFields.skipDedup == true) then
        self:_RememberGeneralDedup(cleanText, senderKey)
    end
    local resolvedGeneralLvl = (not isNotice) and (
        ValidLevel(extraFields and extraFields.senderLevel)
        or (isMe and ValidLevel(Safe.Number(Safe.Call(UnitLevel, "player"))))
        or (senderDisp and senderDisp ~= L["System"] and LookupLevelFromCache(nil, (extraFields and extraFields.senderCharName) or senderDisp, extraFields and extraFields.senderGuid))
    ) or nil
    local gEntry = {
        ts = ts,
        sender = senderDisp or L["System"],
        senderCharName = extraFields and extraFields.senderCharName or nil,
        senderGuid = extraFields and extraFields.senderGuid or nil,
        senderLevel = resolvedGeneralLvl,
        text = cleanText,
        incoming = (isMe ~= true),
        classFile = resolvedClass,
        isStatusNotice = isNotice,
        noSenderColon = noColon,
        generalTag = tagMarkup,
        msgKind = msgKind,
        channelId = extraFields and extraFields.channelId or nil,
        mentionTerm = extraFields and extraFields.mentionTerm or nil,
        _dedupSig = dedupNorm,
        _dedupSenderKey = senderKey,
    }
    if extraFields and tonumber(extraFields.customTs) and #genThread.messages > 0 then
        local insAt = #genThread.messages + 1
        while insAt > 1 and (tonumber(genThread.messages[insAt - 1].ts) or 0) > ts do
            insAt = insAt - 1
        end
        table.insert(genThread.messages, insAt, gEntry)
    else
        table.insert(genThread.messages, gEntry)
    end
    local maxGenLines = math.max(200, Chat:GetHistoryLimitForKey("ch:general"), MAX_THREAD_LINES)
    local genMsgs = genThread.messages
    local dropGen = #genMsgs - maxGenLines
    if dropGen > 0 then
        for k = 1, maxGenLines do
            genMsgs[k] = genMsgs[k + dropGen]
        end
        for k = #genMsgs, maxGenLines + 1, -1 do
            genMsgs[k] = nil
        end
    end
    genThread.lastAt = math.max(tonumber(genThread.lastAt) or 0, ts)
    genThread.unread = 0
    if not (extraFields and extraFields.skipPersist == true) and Chat:ShouldPersistThreadKey("ch:general") then
        PersistWhisperLine("ch:general", gEntry, 0, genThread)
    end
    if not (extraFields and extraFields.skipImmediateEmit == true) then
        local viewingGeneral = (ns.QuickReply and ns.QuickReply.IsViewingThread and ns.QuickReply:IsViewingThread("ch:general")) == true
            or (ns.UI and ns.UI.IsMainVisible and ns.UI:IsMainVisible() and self.activeThreadKey == "ch:general") == true
        QueueChatEmit(viewingGeneral and 0.08 or 0.30)
    end
    return gEntry
end

function Chat:_StripLeadingChatTimestamp(msg)
    if type(msg) ~= "string" then return "" end
    local out = msg:gsub("[\r\n]+", " "):gsub("^%s*(.-)%s*$", "%1")
    out = out:gsub("^|cff%x%x%x%x%x%x%[%d%d?:%d%d:?%d*%s*[APap]?[Mm]?%]|r%s*", "")
    out = out:gsub("^|cff%x%x%x%x%x%x%d%d?:%d%d:?%d*%s*[APap]?[Mm]?%s*|r%s*", "")
    out = out:gsub("^%[%d%d?:%d%d:?%d*%s*[APap]?[Mm]?%]%s*", "")
    out = out:gsub("^%d%d?:%d%d%s*[APap][Mm]%s+", "")
    out = out:gsub("^%d%d?:%d%d:%d%d%s+", "")
    return out:gsub("^%s*(.-)%s*$", "%1")
end

Chat._flushOfficialGeneralLinesFn = Chat._flushOfficialGeneralLinesFn or function()
    Chat._pendingOfficialGeneralTimer = nil
    local batch = Chat._pendingOfficialGeneralLines
    if type(batch) ~= "table" or #batch == 0 then
        return
    end
    local swap = Chat._pendingOfficialGeneralSwap
    if not swap then
        swap = {}
    else
        wipe(swap)
    end
    Chat._pendingOfficialGeneralLines = swap
    Chat._pendingOfficialGeneralSwap = batch
    local pool = Chat._officialGenLinePool
    if not pool then
        pool = {}
        Chat._officialGenLinePool = pool
    end
    local anyAdded = false
    local anyGeneralChatAdded = false
    for i = 1, #batch do
        local it = batch[i]
        batch[i] = nil
        if it then
            local didWorld, didGen = Chat:RecordGeneralOfficialFrameLine(it.msg, it.r, it.g, it.b, true)
            if didWorld then
                anyAdded = true
            end
            if didGen then
                anyGeneralChatAdded = true
            end
            it.msg, it.r, it.g, it.b = nil, nil, nil, nil
            if #pool < 64 then
                pool[#pool + 1] = it
            end
        end
    end
    if anyAdded then
        ns:Emit("COMBAT_LOG_UPDATED")
    end
    if anyGeneralChatAdded then
        QueueChatEmit(0.08)
    end
end

function Chat:QueueGeneralOfficialFrameLine(rawMsg, r, g, b)
    if not self:IsChatHistoryCaptureEnabled() then
        return
    end
    if Safe.IsSecret(rawMsg) or type(rawMsg) ~= "string" then
        return
    end
    local q = self._pendingOfficialGeneralLines
    if not q then
        q = {}
        self._pendingOfficialGeneralLines = q
    end
    local pool = self._officialGenLinePool
    local rec = (pool and #pool > 0) and table.remove(pool) or {}
    rec.msg, rec.r, rec.g, rec.b = rawMsg, r, g, b
    q[#q + 1] = rec
    if #q > 60 then
        local dropped = table.remove(q, 1)
        if dropped and pool and #pool < 64 then
            dropped.msg, dropped.r, dropped.g, dropped.b = nil, nil, nil, nil
            pool[#pool + 1] = dropped
        end
    end
    if self._pendingOfficialGeneralTimer then
        return
    end
    self._pendingOfficialGeneralTimer = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, self._flushOfficialGeneralLinesFn)
    else
        self._flushOfficialGeneralLinesFn()
    end
end

function Chat:RegisterSilentNotFoundTarget(targetName, durationSec)
    if type(targetName) ~= "string" or targetName == "" then return end
    local now = (GetTime and GetTime()) or 0
    self.silentNotFoundLedger = self.silentNotFoundLedger or {}
    local count = 0
    for k, rec in pairs(self.silentNotFoundLedger) do
        if type(rec) ~= "table" or now > (rec.expiresAt or 0) then
            self.silentNotFoundLedger[k] = nil
        else
            count = count + 1
        end
    end
    if count > 80 then
        wipe(self.silentNotFoundLedger)
    end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(targetName)
    local lk = parsed and parsed.lookupKey or nil
    local lowCand = (Compat.LowerUtf8 and Compat.LowerUtf8(targetName)) or targetName:lower()
    local spaced = (lowCand:gsub("%-", " "))
    local hyphened = (lowCand:gsub("%s+", "-"))
    local exp = now + (tonumber(durationSec) or 8.0)
    for _, variant in ipairs({ lowCand, spaced, hyphened, lk }) do
        if type(variant) == "string" and variant ~= "" then
            local prev = self.silentNotFoundLedger[variant]
            self.silentNotFoundLedger[variant] = {
                expiresAt = math.max(exp, (prev and prev.expiresAt) or 0),
                lookupKey = lk or (prev and prev.lookupKey) or nil,
                displayName = (parsed and parsed.displayName) or targetName,
                isWatchProbe = (prev and prev.isWatchProbe == true) or false,
                notifiedOffline = (prev and prev.notifiedOffline == true) or false,
            }
        end
    end
end

function Chat:IsSilentNotFoundSuppressed(msgRaw)
    if Safe.IsSecret(msgRaw) then return false end
    local msg = Safe.String(msgRaw)
    if not msg or msg == "" then return false end
    local lowerMsg = (Compat.LowerUtf8 and Compat.LowerUtf8(msg)) or msg:lower()
    local isNotFound = (ERR_NOT_FOUND_PATTERN and msg:find(ERR_NOT_FOUND_PATTERN) ~= nil)
        or lowerMsg:find("not currently playing", 1, true) ~= nil
        or lowerMsg:find("no player named", 1, true) ~= nil
        or lowerMsg:find("nenhum jogador", 1, true) ~= nil
        or lowerMsg:find("ningún jugador", 1, true) ~= nil
        or lowerMsg:find("ningun jugador", 1, true) ~= nil
    if not isNotFound then return false end
    local monoNow = (GetTime and GetTime()) or 0
    local manualRec = self.lastManualWhisperSend
    if type(manualRec) == "table" and manualRec.delivered ~= true and (monoNow - (manualRec.sentAt or 0)) <= 4.0 then
        local mLow = manualRec.targetStr and ((Compat.LowerUtf8 and Compat.LowerUtf8(manualRec.targetStr)) or manualRec.targetStr:lower()) or ""
        if mLow ~= "" and (lowerMsg:find(mLow, 1, true) or lowerMsg:find((mLow:gsub("%-", " ")), 1, true)) then
            return false
        end
    end
    if ns.Clan and ns.Clan.IsSilentWhisperNotFound and ns.Clan:IsSilentWhisperNotFound(msg) then
        return true
    end
    if type(self.pendingPresenceProbes) == "table" then
        for lk, pRec in pairs(self.pendingPresenceProbes) do
            if type(pRec) == "table" and (monoNow - (pRec.sentAt or 0)) <= 8.0 and pRec.displayName then
                local cLow = (Compat.LowerUtf8 and Compat.LowerUtf8(pRec.displayName)) or pRec.displayName:lower()
                if cLow ~= "" and (lowerMsg:find(cLow, 1, true) or lowerMsg:find((cLow:gsub("%-", " ")), 1, true)) then
                    return true
                end
            end
        end
    end
    if type(self.silentNotFoundLedger) == "table" then
        for k, lRec in pairs(self.silentNotFoundLedger) do
            if type(lRec) == "table" and monoNow <= (lRec.expiresAt or 0) then
                local cStr = lRec.displayName or k
                local cLow = (Compat.LowerUtf8 and Compat.LowerUtf8(cStr)) or tostring(cStr):lower()
                if cLow ~= "" and (lowerMsg:find(cLow, 1, true) or lowerMsg:find((cLow:gsub("%-", " ")), 1, true)) then
                    return true
                end
            end
        end
    end
    return false
end

function Chat:RecordGeneralOfficialFrameLine(rawMsg, r, g, b, skipEmit, allowChannelBackfill)
    if not self:IsChatHistoryCaptureEnabled() then
        return false, false
    end
    if Safe.IsSecret(rawMsg) or type(rawMsg) ~= "string" then
        return false, false
    end
    local msg = Safe.String(rawMsg)
    if not msg then
        return false, false
    end
    -- Fast skip channel/whisper/guild/party/say ChatFrame1 mirrors before expensive regex/dedup when not backfilling.
    if not allowChannelBackfill and (rawMsg:find("|Hchannel:", 1, true) or rawMsg:find("|hchannel:", 1, true)) then
        return false, false
    end
    msg = self:_StripLeadingChatTimestamp(msg)
    if msg == "" then
        return false, false
    end
    if self:IsSilentNotFoundSuppressed(msg) then
        return false, false
    end
    local normPlain = self:_NormalizeGeneralDedupText(msg)
    if not normPlain or normPlain == "" then
        return false, false
    end
    if normPlain:find("^%[?socialcentral%]?:") then
        if Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode() and Compat.IsAddonChatMode and Compat.IsAddonChatMode() then
            local scBody = msg:gsub("^|c%x%x%x%x%x%x%x%x%[?SocialCentral%]?|r:?%s*", ""):gsub("^%[?SocialCentral%]?:?%s*", "")
            local isBootBanner = (scBody:find("^v%d+%.%d+") ~= nil) or (scBody:find("carregad", 1, true) ~= nil) or (scBody:find("loaded", 1, true) ~= nil)
            if scBody ~= "" and not isBootBanner then
                self:RecordGeneralMessage("SYSTEM", "SocialCentral", scBody, false, nil, "SC", {
                    noSenderColon = false,
                    isStatusNotice = true,
                })
                if not skipEmit then
                    ns:Emit("CHAT_UPDATED")
                end
                return true, true
            end
        end
        return false, false
    end
    local senderKey = self:_ExtractGeneralSenderKey(rawMsg, false) or self:_ExtractGeneralSenderKey(msg, false)
    if self:_WasRecentlyRecordedInGeneral(msg, senderKey) then
        return false, false
    end
    local cleanMsgBody = normPlain:match(":%s*(.+)$")
    local outText = msg
    if not outText:match("^|c%x%x%x%x%x%x%x%x") then
        local nr = math.max(0, math.min(255, math.floor(((tonumber(r) or 1.0) * 255) + 0.5)))
        local ng = math.max(0, math.min(255, math.floor(((tonumber(g) or 1.0) * 255) + 0.5)))
        local nb = math.max(0, math.min(255, math.floor(((tonumber(b) or 0.0) * 255) + 0.5)))
        outText = string.format("|cff%02x%02x%02x%s|r", nr, ng, nb, outText)
    end
    local rawLow = rawMsg:lower()
    local isChanOrCommLink = rawLow:find("|hchannel:", 1, true) ~= nil
    local isDedicatedChan = rawLow:find("|hchannel:guild", 1, true) or rawLow:find("|hchannel:officer", 1, true)
        or rawLow:find("|hchannel:party", 1, true) or rawLow:find("|hchannel:raid", 1, true)
        or rawLow:find("|hchannel:instance", 1, true) or rawLow:find("|hchannel:whisper", 1, true)
        or rawLow:find("|hchannel:say", 1, true) or rawLow:find("|hchannel:yell", 1, true)
    local hasPlayerChatPrefix = (rawLow:find("|hplayer:", 1, true) ~= nil) and (isChanOrCommLink or msg:find(":%s") ~= nil)
    local looksLikeNumberedChanChat = msg:match("^%[%d+%.%s*[^%]]+%]%s*%[[^%]]+%]%s*:") ~= nil
    if isDedicatedChan or isChanOrCommLink or looksLikeNumberedChanChat then
        if not allowChannelBackfill then
            return false, false
        end
        if not isDedicatedChan then
            self:_RememberGeneralDedup(cleanMsgBody or msg, senderKey)
            self:RecordGeneralMessage("PUB_CHANNEL", L["Channel"], outText, false, nil, nil, {
                noTag = true,
                noSenderColon = true,
                skipDedup = true,
                isBackfill = allowChannelBackfill == true,
                skipImmediateEmit = skipEmit == true,
            })
            if not skipEmit then
                ns:Emit("CHAT_UPDATED")
            end
            return true, true
        end
        return false, false
    end
    if not allowChannelBackfill and hasPlayerChatPrefix and not rawLow:find("|hbnplayer:", 1, true) then
        -- Avoid mirroring live Say/Yell/Player chat printed into ChatFrame1 when OnChatEvent handles it directly.
        if not normPlain:find("entrou no jogo", 1, true) and not normPlain:find("saiu do jogo", 1, true)
            and not normPlain:find("ficou online", 1, true) and not normPlain:find("ficou offline", 1, true)
            and not normPlain:find("está online", 1, true) and not normPlain:find("está offline", 1, true)
            and not normPlain:find("come online", 1, true) and not normPlain:find("gone offline", 1, true)
            and not normPlain:find("conectado", 1, true) and not normPlain:find("desconectado", 1, true)
            and not normPlain:find("conectou", 1, true) and not normPlain:find("desconectou", 1, true)
        then
            return false, false
        end
    end
    self:_RememberGeneralDedup(cleanMsgBody or msg, senderKey)
    self:RecordWorldLogLine("system", L["System"], outText, r, g, b, nil, skipEmit == true)
    local didGeneralAdded = false
    if (not allowChannelBackfill) and Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode()
        and Compat.IsAddonChatMode and Compat.IsAddonChatMode()
        and not self:_WasRecentlyWorldOnlyNotice(msg)
    then
        local isLootFallback = type(normPlain) == "string" and (
            normPlain:find("recebe o saque:", 1, true)
            or normPlain:find("receive loot:", 1, true)
            or normPlain:find("recibes el bot", 1, true)
            or normPlain:find("recibes bot", 1, true)
            or normPlain:find("você saqueia ", 1, true)
            or normPlain:find("you loot ", 1, true)
            or normPlain:find("saqueas ", 1, true)
            or rawLow:find("|hloot:", 1, true)
        )
        self:RecordGeneralMessage(
            isLootFallback and "LOOT" or "SYSTEM",
            isLootFallback and L["Loot"] or L["System"],
            outText,
            false,
            nil,
            isLootFallback and L["Loot"] or nil,
            {
                noTag = not isLootFallback,
                noSenderColon = true,
                isStatusNotice = true,
                isBackfill = allowChannelBackfill == true,
                skipImmediateEmit = skipEmit == true,
            }
        )
        didGeneralAdded = true
        if not skipEmit then
            ns:Emit("CHAT_UPDATED")
        end
    end
    return true, didGeneralAdded
end

function Chat:BackfillGeneralFromChatFrame1()
    local genMeta = STATIC_CHANNEL_ORDER["ch:general"]
    EnsureThread("ch:general", "GENERAL", (genMeta and L[genMeta.titleKey]) or L["General"], { slash = "/s " })
    if self._worldBackfilledFromCf1 then
        return
    end
    self._worldBackfilledFromCf1 = true
    local cf1 = _G.ChatFrame1
    if not (cf1 and cf1.GetNumMessages and cf1.GetMessageInfo) then
        return
    end
    local okN, total = pcall(cf1.GetNumMessages, cf1)
    local totalNum = okN and Safe.Number(total) or 0
    if totalNum <= 0 then
        return
    end
    local added = false
    local startIdx = math.max(1, totalNum - 40 + 1)
    for i = startIdx, totalNum do
        local okM, lineRaw, mr, mg, mb = pcall(cf1.GetMessageInfo, cf1, i)
        if okM and lineRaw and self:RecordGeneralOfficialFrameLine(lineRaw, mr, mg, mb, true, true) then
            added = true
        end
    end
    if added then
        ns:Emit("COMBAT_LOG_UPDATED")
        ns:Emit("CHAT_UPDATED")
    end
end

function Chat:OnWorldNoticeEvent(eventName, msgRaw, authorRaw)
    if not self:IsChatHistoryCaptureEnabled() then
        return
    end
    local cleanMsg = Safe.String(msgRaw)
    if not cleanMsg or cleanMsg == "" then
        return
    end
    if eventName == "CHAT_MSG_SYSTEM" and self.suppressSystemFilter == true then
        return
    end
    local author = Safe.String(authorRaw)
    local inAddonMode = Compat and Compat.HasChosenChatUiMode and Compat.HasChosenChatUiMode()
        and Compat.IsAddonChatMode and Compat.IsAddonChatMode()
    if eventName == "CHAT_MSG_LOOT" then
        self:_RememberWorldOnlyNotice(cleanMsg)
        self:RecordWorldLogLine("loot", L["Loot"], "|cff47ef66" .. cleanMsg .. "|r", 0.28, 0.94, 0.40)
        if inAddonMode then
            self:RecordGeneralMessage("LOOT", L["Loot"], "|cff47ef66" .. cleanMsg .. "|r", false, nil, L["Loot"], {
                noSenderColon = true,
                isStatusNotice = true,
            })
        end
    elseif eventName == "CHAT_MSG_MONEY" or eventName == "CHAT_MSG_CURRENCY" then
        self:_RememberWorldOnlyNotice(cleanMsg)
        self:RecordWorldLogLine("loot", L["Loot"], "|cff47ef66" .. cleanMsg .. "|r", 0.28, 0.94, 0.40)
    elseif eventName == "CHAT_MSG_TRADESKILLS" or eventName == "CHAT_MSG_OPENING" then
        self:_RememberWorldOnlyNotice(cleanMsg)
        self:RecordWorldLogLine("craft", L["Crafting"], "|cff6ec1e4" .. cleanMsg .. "|r", 0.43, 0.76, 0.89)
    elseif eventName == "CHAT_MSG_COMBAT_XP_GAIN" or eventName == "CHAT_MSG_COMBAT_FACTION_CHANGE" or eventName == "CHAT_MSG_COMBAT_HONOR_GAIN" or eventName == "CHAT_MSG_SKILL" then
        self:_RememberWorldOnlyNotice(cleanMsg)
        self:RecordWorldLogLine("progress", L["Progress"], "|cff9aaeff" .. cleanMsg .. "|r", 0.60, 0.68, 1.0)
    elseif eventName == "CHAT_MSG_ACHIEVEMENT" or eventName == "CHAT_MSG_GUILD_ACHIEVEMENT" then
        local body = (author and author ~= "") and (author .. ": " .. cleanMsg) or cleanMsg
        self:RecordWorldLogLine("progress", L["Achievement"], "|cffffd24d" .. body .. "|r", 1.0, 0.82, 0.30)
        if inAddonMode then
            self:RecordGeneralMessage("ACHIEVEMENT", L["Achievement"], "|cffffd24d" .. body .. "|r", false, nil, L["Achievement"], {
                noSenderColon = true,
                isStatusNotice = true,
            })
        end
    elseif eventName == "CHAT_MSG_RAID_BOSS_EMOTE" or eventName == "CHAT_MSG_MONSTER_SAY" or eventName == "CHAT_MSG_MONSTER_YELL" or eventName == "CHAT_MSG_MONSTER_EMOTE" then
        local npc = (author and author ~= "") and author or L["World"]
        if eventName == "CHAT_MSG_MONSTER_EMOTE" or eventName == "CHAT_MSG_RAID_BOSS_EMOTE" then
            local safeNpc = npc:gsub("%%", "%%%%")
            local formatted, replaced = cleanMsg:gsub("%%s", safeNpc)
            if replaced and replaced > 0 then
                self:RecordGeneralMessage("MONSTER", npc, formatted, false, nil, L["World"], { noSenderColon = true })
            else
                self:RecordGeneralMessage("MONSTER", npc, npc .. " " .. cleanMsg, false, nil, L["World"], { noSenderColon = true })
            end
        else
            self:RecordGeneralMessage("MONSTER", npc, cleanMsg, false, nil, L["World"], { noSenderColon = false })
        end
    elseif eventName == "CHAT_MSG_EMOTE" or eventName == "CHAT_MSG_TEXT_EMOTE" then
        local parsed = author and Compat.ParseCharacterName and Compat.ParseCharacterName(author)
        local who = (parsed and parsed.displayName) or author or L["World"]
        local isMe = parsed and Compat.IsMe and Compat.IsMe(parsed.displayName) or false
        local lineTxt = (eventName == "CHAT_MSG_TEXT_EMOTE") and cleanMsg or (who .. " " .. cleanMsg)
        self:RecordGeneralMessage("LOCAL_SAY", who, lineTxt, isMe, nil, L["Emote"], { noSenderColon = true })
    else
        self:RecordWorldLogLine("system", L["System"], "|cffffff66" .. cleanMsg .. "|r", 1.0, 1.0, 0.40)
    end
end

function Chat:ExtractGroupSessionKey(gid)
    if type(gid) ~= "string" or gid == "" then
        return nil
    end
    if gid:sub(1, 2) == "s:" then
        return gid
    end
    local legacySess = gid:match("^([^|]+)|")
    if legacySess and legacySess ~= "" then
        return "s:" .. legacySess
    end
    return "s:" .. gid
end

function Chat:FormatWhenLabel(ts, includeClock)
    local tVal = tonumber(ts) or 0
    if tVal <= 0 then
        return ""
    end
    local dayKey = date("%Y-%m-%d", tVal)
    local todayKey = date("%Y-%m-%d")
    local yesterdayKey = date("%Y-%m-%d", time() - 86400)
    local dayPart
    if dayKey == todayKey then
        dayPart = L["Today"]
    elseif dayKey == yesterdayKey then
        dayPart = L["Yesterday"]
    else
        dayPart = date("%d/%m/%Y", tVal)
    end
    if includeClock ~= false then
        return dayPart .. ", " .. date("%H:%M", tVal)
    end
    return dayPart
end

function Chat:FormatRelativeWhenText(ts)
    local tVal = tonumber(ts) or 0
    if tVal <= 0 then
        return ""
    end
    local base = self:FormatWhenLabel(tVal, true)
    local delta = math.max(0, time() - tVal)
    local rel
    if delta < 60 then
        rel = L["just now"]
    elseif delta < 3600 then
        rel = string.format(L["%dm ago"], math.floor(delta / 60))
    elseif delta < 86400 then
        rel = string.format(L["%dh ago"], math.floor(delta / 3600))
    else
        rel = string.format(L["%dd ago"], math.floor(delta / 86400))
    end
    if base == L["Today"] .. ", " .. date("%H:%M", tVal) or base == L["Yesterday"] .. ", " .. date("%H:%M", tVal) then
        return string.format("%s (%s) · %s", base, date("%d/%m/%Y", tVal), rel)
    end
    return string.format("%s · %s", base, rel)
end

--- Formats the plain bracketed label, hex color, and RGB triplet for a group session.
function Chat:FormatGroupSessionLabel(gInfo, fallbackTs)
    if not gInfo then
        return nil
    end
    local ts = (gInfo.startedAt and gInfo.startedAt > 0 and gInfo.startedAt) or tonumber(fallbackTs) or 0
    local clockStr = ts > 0 and date("%H:%M", ts) or ""
    local roster = gInfo.roster
    local count = (roster and (roster.size or (roster.members and #roster.members))) or 0
    local zone = (roster and roster.zone and roster.zone ~= "") and roster.zone or nil
    local parts = {}
    if clockStr ~= "" then
        parts[#parts + 1] = string.format(L["Group %s"], clockStr)
    else
        parts[#parts + 1] = L["Group"]
    end
    if zone then
        parts[#parts + 1] = zone
    end
    if count > 0 then
        parts[#parts + 1] = string.format(L["%d players"], count)
    end
    local hex = (gInfo and gInfo.hex) or "|cff7aaeff"
    local rHex, gHex, bHex = hex:match("^|cff(%x%x)(%x%x)(%x%x)$")
    local rgb = (rHex and gHex and bHex)
        and { tonumber(rHex, 16) / 255, tonumber(gHex, 16) / 255, tonumber(bHex, 16) / 255 }
        or { 0.48, 0.68, 1.0 }
    local label = "[" .. table.concat(parts, " · ") .. "]"
    return {
        label = label,
        hex = hex,
        rgb = rgb,
        colored = hex .. label .. "|r",
    }
end

function Chat:FormatGroupSessionBanner(threadKey, msgIdx, gInfo, fallbackTs)
    if not (threadKey and msgIdx and gInfo) then
        return nil
    end
    local info = self:FormatGroupSessionLabel(gInfo, fallbackTs)
    if not info then
        return nil
    end
    return "|cff7f8a9c— |r|Haddon:SCentral:grp:" .. tostring(msgIdx) .. ":" .. tostring(threadKey) .. "|h" .. info.colored .. "|h"
end

--- Measures the rendered pixel width of a chat line prefix inside `msgFrame`
--- using a hidden FontString synced to the frame's active font.
function Chat:MeasureMessagePrefixWidth(msgFrame, text)
    if not (msgFrame and msgFrame.CreateFontString) then
        return 0
    end
    local fs = msgFrame._scMeasureFs
    if not fs then
        fs = msgFrame:CreateFontString(nil, "ARTWORK")
        if fs.SetAlpha then fs:SetAlpha(0) end
        if fs.SetPoint then fs:SetPoint("TOPLEFT", msgFrame, "TOPLEFT", 0, 0) end
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        msgFrame._scMeasureFs = fs
    end
    local fPath, fSize, fFlags
    if msgFrame.GetFont then
        fPath, fSize, fFlags = msgFrame:GetFont()
    end
    if (not fPath or not fSize) and _G.ChatFontNormal and _G.ChatFontNormal.GetFont then
        fPath, fSize, fFlags = _G.ChatFontNormal:GetFont()
    end
    if fPath and fSize and fs.SetFont then
        if fs._scFontPath ~= fPath or fs._scFontSize ~= fSize or fs._scFontFlags ~= fFlags then
            fs._scFontPath = fPath
            fs._scFontSize = fSize
            fs._scFontFlags = fFlags
            fs:SetFont(fPath, fSize, fFlags or "")
        end
    elseif fs.SetFontObject then
        fs:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
    end
    fs:SetText("|")
    local markerW = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or (fs.GetStringWidth and fs:GetStringWidth()) or 0
    fs:SetText(tostring(text or "") .. "|")
    local totalW = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or (fs.GetStringWidth and fs:GetStringWidth()) or 0
    return math.max(0, totalW - markerW)
end

Chat.AUTHOR_GROUP_MAX_GAP_SEC = 180
Chat.AUTHOR_GROUP_MAX_SPAN_SEC = 300

--- Returns true when a consecutive message from the same speaker should join
--- the active proximity turn block (within a 3-minute gap and 5-minute span).
function Chat:ShouldGroupWithPreviousTurn(curSenderKey, lastSenderKey, lastSenderTs, turnStartTs, curTs, showedBreakLine)
    local tVal = tonumber(curTs) or 0
    local prevVal = tonumber(lastSenderTs) or 0
    local startVal = tonumber(turnStartTs) or 0
    if curSenderKey == nil or showedBreakLine == true or lastSenderKey ~= curSenderKey then
        return false
    end
    if tVal <= 0 or prevVal <= 0 then
        return false
    end
    local delta = tVal - prevVal
    if delta < 0 or delta > (self.AUTHOR_GROUP_MAX_GAP_SEC or 180) then
        return false
    end
    if startVal > 0 and (tVal - startVal) > (self.AUTHOR_GROUP_MAX_SPAN_SEC or 300) then
        return false
    end
    return true
end

--- Formats the leading timestamp for a chat message or speaker turn header,
--- omitting repeated `[HH:MM]` timestamps inside dark proximity continuation lines
--- while keeping full click/hover timestamp actions intact.
function Chat:BuildMessageTimestampPrefix(msgTs, msgIdx, threadKey, isStatusNotice, isSameAuthorGroup, prevSenderTs, msgFrame, targetTextX)
    local tVal = tonumber(msgTs) or 0
    local prevVal = tonumber(prevSenderTs) or 0
    local tsStr = (tVal > 0) and date("%H:%M", tVal) or ""
    if isSameAuthorGroup then
        if msgFrame and msgFrame._isStreamViewport then
            return ""
        end
        local showChangedGap = (tsStr ~= "") and (prevVal > 0) and (math.abs(tVal - prevVal) > (self.AUTHOR_GROUP_MAX_GAP_SEC or 180))
        local dotPlain = "|cff586069·|r "
        local dotPart
        if (not isStatusNotice) and msgIdx and threadKey then
            dotPart = "|Haddon:SCentral:msgact:" .. tostring(msgIdx) .. ":" .. tostring(threadKey) .. "|h|cff586069·|r|h "
        else
            dotPart = dotPlain
        end
        local tsPart = ""
        if showChangedGap then
            local tsTxt = "|cff545c67[" .. tsStr .. "]|r"
            if (not isStatusNotice) and msgIdx and threadKey then
                tsPart = "|Haddon:SCentral:msgact:" .. tostring(msgIdx) .. ":" .. tostring(threadKey) .. "|h" .. tsTxt .. "|h "
            else
                tsPart = tsTxt .. " "
            end
        end
        local spacer = ""
        local tgtNum = tonumber(targetTextX) or 0
        if msgFrame and tgtNum > 0 then
            local fw = (msgFrame.GetWidth and tonumber(msgFrame:GetWidth())) or 0
            local clampedX = (fw > 120) and math.min(tgtNum, math.floor(fw * 0.55)) or tgtNum
            local baseW = self:MeasureMessagePrefixWidth(msgFrame, tsPart .. dotPlain)
            local spacerW = math.floor(math.max(0, clampedX - baseW) + 0.5)
            if spacerW >= 1 then
                spacer = "|TInterface\\AddOns\\SocialCentral\\Media\\dot:1:" .. tostring(spacerW) .. ":0:0:16:16:0:1:0:1|t"
            end
        end
        return tsPart .. spacer .. dotPart
    end
    if tsStr == "" then
        return ""
    end
    local tsTxt = "|cff6e7681[" .. tsStr .. "]|r"
    if (not isStatusNotice) and msgIdx and threadKey then
        return "|Haddon:SCentral:msgact:" .. tostring(msgIdx) .. ":" .. tostring(threadKey) .. "|h" .. tsTxt .. "|h "
    end
    return tsTxt .. " "
end

--- Collects the current live party/raid lookup keys and whether a real peer exists.
function Chat:CollectLiveGroupLookupSet(preferRaid)
    local inRaid = (Compat and Compat.IsInRaid and Compat.IsInRaid()) == true
    local numMembers = (_G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers())) or 0
    local hasRealPeer = inRaid
        or (numMembers >= 2)
        or (UnitExists and (UnitExists("party1") or UnitExists("raid1")))
    local inGrp = inRaid or ((Compat and Compat.IsInGroup and Compat.IsInGroup() == true) and hasRealPeer)
    if not inGrp then
        return false, nil, 0
    end
    local units = {}
    if inRaid or preferRaid then
        local lim = math.min(40, math.max(5, numMembers))
        for ri = 1, lim do
            units[#units + 1] = "raid" .. tostring(ri)
        end
    else
        units[#units + 1] = "player"
        for pi = 1, 4 do
            units[#units + 1] = "party" .. tostring(pi)
        end
    end
    local seen = {}
    local count = 0
    for _, uTok in ipairs(units) do
        if _G.UnitExists and _G.UnitExists(uTok) then
            local unitRes = (Compat and Compat.ResolveUnitFullName) and Compat.ResolveUnitFullName(uTok, nil, nil, true) or nil
            local rawName = (unitRes and unitRes.fullName)
                or (_G.UnitName and Safe.String(_G.UnitName(uTok)))
            if rawName and rawName ~= "" then
                local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rawName)) or rawName:lower()
                if lk and lk ~= "" and not seen[lk] then
                    seen[lk] = true
                    count = count + 1
                end
            end
        end
    end
    return count > 0, seen, count
end

--- Evaluates whether two group member lists (or lookup sets) belong to the same
--- continuous group session given the time gap in seconds between them.
function Chat:AreGroupRostersSameSession(membersA, membersB, gapSec, myLk)
    if type(membersA) ~= "table" or type(membersB) ~= "table" then
        return false
    end
    local function ExtractOtherSet(src)
        local set = {}
        local cnt = 0
        if #src > 0 then
            for _, mem in ipairs(src) do
                local lk = (type(mem) == "table" and (mem.lk or mem.n)) or (type(mem) == "string" and mem) or nil
                if lk and lk ~= "" then
                    local norm = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(lk)) or lk:lower()
                    if norm ~= "" and norm ~= myLk and not set[norm] then
                        set[norm] = true
                        cnt = cnt + 1
                    end
                end
            end
        else
            for k, v in pairs(src) do
                if v and type(k) == "string" and k ~= "" and k ~= myLk and not set[k] then
                    set[k] = true
                    cnt = cnt + 1
                end
            end
        end
        return set, cnt
    end
    local setA, cntA = ExtractOtherSet(membersA)
    local setB, cntB = ExtractOtherSet(membersB)
    if cntA == 0 or cntB == 0 then
        return false
    end
    local overlap = 0
    for lk in pairs(setA) do
        if setB[lk] then
            overlap = overlap + 1
        end
    end
    if overlap == 0 then
        return false
    end
    local minCnt = math.min(cntA, cntB)
    local ratio = (minCnt > 0) and (overlap / minCnt) or 0
    local gap = math.abs(tonumber(gapSec) or 0)
    if gap <= 900 then
        return (ratio >= 0.5) or (overlap >= 2) or (minCnt <= 2)
    elseif gap <= 14400 then
        return (overlap >= 2 and ratio >= 0.5) or (cntA == 1 and cntB == 1 and overlap == 1)
    end
    return false
end

function Chat:SyncGroupRosterSessionState(thread, liveMemberLookupSet)
    local liveSet = (type(liveMemberLookupSet) == "table" and next(liveMemberLookupSet) ~= nil) and liveMemberLookupSet or nil
    local inGrp = false
    if liveSet then
        local inRaid = (Compat and Compat.IsInRaid and Compat.IsInRaid()) == true
        local numMembers = (_G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers())) or 0
        local hasRealPeer = inRaid
            or (numMembers >= 2)
            or (UnitExists and (UnitExists("party1") or UnitExists("raid1")))
        inGrp = inRaid or ((Compat and Compat.IsInGroup and Compat.IsInGroup() == true) and hasRealPeer)
    else
        inGrp, liveSet = self:CollectLiveGroupLookupSet(thread and thread.kind == "RAID")
    end
    if not inGrp or not liveSet then
        if self._activeGroupSessionId then
            self._lastEndedGroupSession = {
                id = self._activeGroupSessionId,
                endedAt = time(),
                members = self._activeGroupMembersSet,
            }
        end
        self._activeGroupSessionId = nil
        self._activeGroupMembersSet = nil
        return nil
    end

    self._activeGroupMembersSet = liveSet
    local myDisp = GetMyInfo()
    local myLk = myDisp and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(myDisp) or nil
    local nowTs = time()

    if (not self._activeGroupSessionId) and self._lastEndedGroupSession then
        local lastEnd = self._lastEndedGroupSession
        local endGap = nowTs - (tonumber(lastEnd.endedAt) or 0)
        if endGap <= 600 and lastEnd.id and lastEnd.members and self:AreGroupRostersSameSession(lastEnd.members, liveSet, endGap, myLk) then
            self._activeGroupSessionId = lastEnd.id
        end
    end

    if not self._activeGroupSessionId and type(self.threads) == "table" then
        local candidates = {}
        local seenThr = {}
        local function AddCand(tObj)
            if type(tObj) == "table" and not seenThr[tObj] and type(tObj.messages) == "table" and type(tObj.groupRosters) == "table" then
                seenThr[tObj] = true
                candidates[#candidates + 1] = tObj
            end
        end
        AddCand(thread)
        local _, activeKey = self:GetActiveGroupSyncInfo()
        if activeKey then AddCand(self.threads[activeKey]) end
        AddCand(self.threads["ch:party"])
        AddCand(self.threads["ch:raid"])
        AddCand(self.threads["ch:instance"])

        local bestTs = -1
        local bestMembers = nil
        local bestRawSess = nil
        for _, candThr in ipairs(candidates) do
            for i = #candThr.messages, math.max(1, #candThr.messages - 80), -1 do
                local m = candThr.messages[i]
                local gid = type(m) == "table" and m.groupRosterId or nil
                if gid then
                    local r = candThr.groupRosters[gid]
                    local rTs = tonumber((r and (r.lastAt or r.ts)) or m.ts) or 0
                    if r and type(r.members) == "table" and rTs > bestTs then
                        local key = self:ExtractGroupSessionKey(gid)
                        local rawSess = key and key:gsub("^s:", "") or nil
                        if rawSess and rawSess ~= "" then
                            bestTs = rTs
                            bestMembers = r.members
                            bestRawSess = rawSess
                        end
                    end
                    break
                end
            end
        end
        if bestRawSess and bestMembers and (nowTs - bestTs) <= 14400
            and self:AreGroupRostersSameSession(bestMembers, liveSet, nowTs - bestTs, myLk)
        then
            self._activeGroupSessionId = bestRawSess
        end
    end

    self._lastEndedGroupSession = nil
    if not self._activeGroupSessionId then
        self._activeGroupSessionSeq = (self._activeGroupSessionSeq or 0) + 1
        self._activeGroupSessionId = tostring(nowTs) .. ":" .. tostring(self._activeGroupSessionSeq)
    end
    return self._activeGroupSessionId
end

function Chat:CaptureCurrentGroupSnapshot(thread, ts, extraFields)
    if not thread or (thread.kind ~= "PARTY" and thread.kind ~= "RAID" and thread.kind ~= "INSTANCE_CHAT") then
        return nil
    end
    if extraFields and extraFields.groupRosterId then
        return extraFields.groupRosterId
    end
    local inRaid = (Compat and Compat.IsInRaid and Compat.IsInRaid()) == true
    local numMembers = (_G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers())) or 0
    local inGrp = inRaid or (Compat and Compat.IsInGroup and Compat.IsInGroup() == true) or (numMembers > 0)
    if not inGrp then
        return nil
    end
    local units = {}
    if inRaid or thread.kind == "RAID" then
        local lim = math.min(40, math.max(5, numMembers))
        for ri = 1, lim do
            units[#units + 1] = "raid" .. tostring(ri)
        end
    else
        units[#units + 1] = "player"
        for pi = 1, 4 do
            units[#units + 1] = "party" .. tostring(pi)
        end
    end
    local members = {}
    local seen = {}
    for _, uTok in ipairs(units) do
        if _G.UnitExists and _G.UnitExists(uTok) then
            local unitRes = (Compat and Compat.ResolveUnitFullName) and Compat.ResolveUnitFullName(uTok, nil, nil, true) or nil
            local rawName = (unitRes and unitRes.fullName)
                or (_G.UnitName and Safe.String(_G.UnitName(uTok)))
            if rawName and rawName ~= "" then
                local lk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rawName)) or rawName:lower()
                if lk and lk ~= "" and not seen[lk] then
                    seen[lk] = true
                    local _, cls = Safe.Call(_G.UnitClass, uTok)
                    local roleStr = nil
                    if _G.UnitGroupRolesAssigned then
                        local okR, rVal = pcall(_G.UnitGroupRolesAssigned, uTok)
                        if okR and type(rVal) == "string" and (rVal == "TANK" or rVal == "HEALER" or rVal == "DAMAGER") then
                            roleStr = rVal
                        end
                    end
                    members[#members + 1] = {
                        n = rawName,
                        lk = lk,
                        c = Safe.String(cls),
                        r = roleStr,
                    }
                end
            end
        end
    end
    if #members == 0 then
        return nil
    end
    local sessId = self:SyncGroupRosterSessionState(thread, seen) or tostring(ts or time())
    local rosterId = "s:" .. tostring(sessId)
    local curZone = (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
    local inInst = Safe.Call(IsInInstance) == true
    local nowTs = ts or time()
    thread.groupRosters = thread.groupRosters or {}
    local existing = thread.groupRosters[rosterId]
    if not existing then
        table.sort(members, function(a, b)
            return (a.lk or "") < (b.lk or "")
        end)
        thread.groupRosters[rosterId] = {
            members = members,
            size = #members,
            zone = (curZone ~= "") and curZone or nil,
            ts = nowTs,
            startedAt = nowTs,
            lastAt = nowTs,
        }
    else
        local byLk = {}
        local merged = {}
        if type(existing.members) == "table" then
            for _, prevM in ipairs(existing.members) do
                if type(prevM) == "table" and prevM.lk and prevM.lk ~= "" and not byLk[prevM.lk] then
                    local copy = { n = prevM.n, lk = prevM.lk, c = prevM.c, r = prevM.r }
                    byLk[prevM.lk] = copy
                    merged[#merged + 1] = copy
                end
            end
        end
        for _, liveM in ipairs(members) do
            local cur = byLk[liveM.lk]
            if cur then
                cur.n = liveM.n or cur.n
                cur.c = liveM.c or cur.c
                cur.r = liveM.r or cur.r
            else
                byLk[liveM.lk] = liveM
                merged[#merged + 1] = liveM
            end
        end
        table.sort(merged, function(a, b)
            return (a.lk or "") < (b.lk or "")
        end)
        existing.members = merged
        existing.size = #merged
        existing.startedAt = existing.startedAt or existing.ts or nowTs
        existing.lastAt = nowTs
        if curZone ~= "" and ((not existing.zone or existing.zone == "") or inInst) then
            existing.zone = curZone
        end
    end
    return rosterId
end

function Chat:GetThreadGroupRenderMap(thread)
    if not (thread and type(thread.messages) == "table" and type(thread.groupRosters) == "table") then
        return nil
    end
    local colors = {
        "|cff7aaeff",
        "|cffe8b84d",
        "|cff7ee787",
        "|cffd2a8ff",
        "|cffffa657",
        "|cff79c0ff",
    }
    local myDisp = GetMyInfo()
    local myLk = myDisp and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(myDisp) or nil
    local map = {}
    local bySessKey = {}
    local aliasToMeta = {}
    local lastMeta = nil
    local seq = 0
    for msgIdx, m in ipairs(thread.messages) do
        local gid = type(m) == "table" and m.groupRosterId or nil
        local rRaw = gid and thread.groupRosters[gid] or nil
        if gid and rRaw then
            local sKey = self:ExtractGroupSessionKey(gid) or gid
            local meta = aliasToMeta[sKey] or bySessKey[sKey]
            local mTs = tonumber(m.ts) or 0
            if (not meta) and lastMeta and lastMeta.sessKey ~= sKey and type(rRaw.members) == "table" then
                local refPrevTs = tonumber(lastMeta.lastAt) or 0
                local refCurTs = (mTs > 0 and mTs) or tonumber(rRaw.startedAt or rRaw.ts) or 0
                local gap = (refPrevTs > 0 and refCurTs > 0) and (refCurTs - refPrevTs) or 999999
                if gap >= 0 and gap <= 1800 and self:AreGroupRostersSameSession(lastMeta.roster.members, rRaw.members, gap, myLk) then
                    meta = lastMeta
                    aliasToMeta[sKey] = lastMeta
                end
            end
            if not meta then
                seq = seq + 1
                meta = {
                    seq = seq,
                    sessKey = sKey,
                    firstMsgIdx = msgIdx,
                    hex = colors[((seq - 1) % #colors) + 1],
                    startedAt = rRaw.startedAt or rRaw.ts or mTs,
                    lastAt = rRaw.lastAt or rRaw.ts or mTs,
                    roster = {
                        members = {},
                        size = rRaw.size or (rRaw.members and #rRaw.members) or 0,
                        zone = rRaw.zone,
                        ts = rRaw.ts,
                        startedAt = rRaw.startedAt or rRaw.ts or mTs,
                    },
                    _seenLk = {},
                }
                bySessKey[sKey] = meta
                aliasToMeta[sKey] = meta
                lastMeta = meta
            end
            if type(rRaw.members) == "table" then
                for _, mem in ipairs(rRaw.members) do
                    local mlk = mem and (mem.lk or mem.n)
                    if mlk and not meta._seenLk[mlk] then
                        meta._seenLk[mlk] = true
                        meta.roster.members[#meta.roster.members + 1] = mem
                    end
                end
                meta.roster.size = #meta.roster.members
            end
            if rRaw.zone and rRaw.zone ~= "" then
                meta.roster.zone = rRaw.zone
            end
            if mTs > 0 and (meta.startedAt == 0 or mTs < meta.startedAt) then
                meta.startedAt = mTs
                meta.roster.startedAt = mTs
            end
            if mTs > meta.lastAt then
                meta.lastAt = mTs
            end
            map[gid] = meta
        end
    end
    for _, meta in pairs(bySessKey) do
        meta._seenLk = nil
        if type(meta.roster.members) == "table" and #meta.roster.members > 1 then
            table.sort(meta.roster.members, function(a, b)
                return (a.lk or a.n or "") < (b.lk or b.n or "")
            end)
        end
    end
    return (seq > 0) and map or nil
end

function Chat:GetThreadGroupSnapshot(threadKey, msgIdx)
    local t = threadKey and self.threads and self.threads[threadKey]
    if not (t and type(t.messages) == "table") then
        return nil
    end
    local m = msgIdx and t.messages[tonumber(msgIdx) or -1]
    if not (type(m) == "table" and m.groupRosterId and type(t.groupRosters) == "table") then
        return nil
    end
    local roster = t.groupRosters[m.groupRosterId]
    if not roster then
        return nil
    end
    local rMap = self:GetThreadGroupRenderMap(t)
    local meta = rMap and rMap[m.groupRosterId]
    return {
        seq = (meta and meta.seq) or 1,
        sessKey = meta and meta.sessKey,
        firstMsgIdx = meta and meta.firstMsgIdx,
        hex = (meta and meta.hex) or "|cff7aaeff",
        roster = (meta and meta.roster) or roster,
        startedAt = (meta and meta.startedAt) or roster.startedAt or roster.ts or m.ts,
        msgTs = m.ts,
    }
end

--- Estimates the number of wrapped visual lines a rendered message occupies inside `msgFrame`.
function Chat:EstimateMessageVisualRows(msgFrame, rawLine, usableWidth)
    local wMax = tonumber(usableWidth) or 0
    if wMax <= 40 or type(rawLine) ~= "string" or rawLine == "" then
        return 1
    end
    local plain = rawLine:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if #plain <= 28 and not plain:find("|T", 1, true) and not plain:find("\n", 1, true) then
        return 1
    end
    local rows = 0
    for seg in (plain .. "\n"):gmatch("([^\n]*)\n") do
        local segW = self:MeasureMessagePrefixWidth(msgFrame, seg)
        rows = rows + math.max(1, math.ceil(segW / wMax))
    end
    return math.max(1, rows)
end

--- Initializes or refreshes per-frame section & wrapped-row tracking state before rendering messages.
function Chat:BeginTrackedMessageRender(state, msgFrame, isIncremental)
    local s = state or {}
    local fw = (msgFrame and msgFrame.GetWidth and tonumber(msgFrame:GetWidth())) or 380
    s.usableWidth = math.max(80, fw - 10)
    if not isIncremental then
        s.lineVisRows = {}
        s.sections = {}
    else
        s.lineVisRows = s.lineVisRows or {}
        s.sections = s.sections or {}
    end
    return s
end

--- Appends a message to `msgFrame` while tracking its wrapped line height and section eviction.
function Chat:AddTrackedMessage(msgFrame, state, text, r, g, b)
    if not msgFrame then
        return 0
    end
    local prevTotal = (msgFrame.GetNumMessages and msgFrame:GetNumMessages()) or 0
    msgFrame:AddMessage(text, r, g, b)
    local newTotal = (msgFrame.GetNumMessages and msgFrame:GetNumMessages()) or (prevTotal + 1)
    if not state then
        return newTotal
    end
    local rows = self:EstimateMessageVisualRows(msgFrame, text, state.usableWidth)
    local visRows = state.lineVisRows
    if newTotal <= prevTotal then
        local dropped = math.max(1, (prevTotal + 1) - newTotal)
        for k = 1, newTotal - 1 do
            visRows[k] = visRows[k + dropped] or 1
        end
        visRows[newTotal] = rows
        for k = #visRows, newTotal + 1, -1 do
            visRows[k] = nil
        end
        local kept = {}
        local lastEvicted = nil
        for _, sec in ipairs(state.sections) do
            sec.bannerLineIdx = (sec.bannerLineIdx or 1) - dropped
            sec.firstMsgLineIdx = (sec.firstMsgLineIdx or 1) - dropped
            if sec.firstMsgLineIdx >= 1 then
                if sec.bannerLineIdx < 1 then
                    sec.bannerLineIdx = 0
                end
                kept[#kept + 1] = sec
            else
                lastEvicted = sec
            end
        end
        if lastEvicted and (#kept == 0 or (kept[1].firstMsgLineIdx or 1) > 1) then
            lastEvicted.bannerLineIdx = 0
            lastEvicted.firstMsgLineIdx = 1
            table.insert(kept, 1, lastEvicted)
        end
        state.sections = kept
    else
        visRows[newTotal] = rows
    end
    return newTotal
end

--- Records a section marker (GROUP or DATE) in `state.sections`, letting GROUP upgrade a co-located DATE marker.
function Chat:RecordTrackedSection(state, sec)
    if not (state and state.sections and type(sec) == "table") then
        return
    end
    local list = state.sections
    local last = list[#list]
    if last and sec.stepId and last.stepId == sec.stepId and sec.kind == "GROUP" then
        sec.bannerLineIdx = math.min(last.bannerLineIdx or sec.bannerLineIdx or 1, sec.bannerLineIdx or 1)
        list[#list] = sec
        return
    end
    list[#list + 1] = sec
end

--- Updates the latest matching GROUP section's cached label/color in O(1) when teammates join.
function Chat:RefreshTrackedGroupSectionLabel(state, sessKey, gInfo, msgTs)
    if not (state and state.sections and sessKey and gInfo and self.FormatGroupSessionLabel) then
        return
    end
    local secs = state.sections
    for idx = #secs, 1, -1 do
        local s = secs[idx]
        if s.kind == "GROUP" and s.sessKey == sessKey then
            local lblInfo = self:FormatGroupSessionLabel(gInfo, msgTs)
            if lblInfo then
                s.label = lblInfo.colored
                s.plainTitle = lblInfo.label
                s.rgb = lblInfo.rgb
            end
            return
        end
    end
end

--- Shifts section marker indices cleanly after trimming old items from a stream viewport.
function Chat:ShiftTrackedSections(state, dropped)
    local d = tonumber(dropped) or 0
    if not (state and state.sections and d > 0) then
        return
    end
    local secs = state.sections
    local w = 1
    local lastEvicted = nil
    for i = 1, #secs do
        local sec = secs[i]
        sec.bannerLineIdx = (sec.bannerLineIdx or 1) - d
        sec.firstMsgLineIdx = (sec.firstMsgLineIdx or 1) - d
        if sec.firstMsgLineIdx >= 1 then
            if sec.bannerLineIdx < 1 then
                sec.bannerLineIdx = 0
            end
            secs[w] = sec
            w = w + 1
        else
            lastEvicted = sec
        end
    end
    for i = #secs, w, -1 do
        secs[i] = nil
    end
    if lastEvicted and (#secs == 0 or (secs[1].firstMsgLineIdx or 1) > 1) then
        lastEvicted.bannerLineIdx = 0
        lastEvicted.firstMsgLineIdx = 1
        table.insert(secs, 1, lastEvicted)
    end
end

--- Computes the topmost and bottommost logical message/item indices visible inside `msgFrame`.
function Chat:FindTopVisibleLine(msgFrame, lineVisRows)
    if msgFrame and msgFrame._isStreamViewport and msgFrame.GetVisibleItemBounds then
        return msgFrame:GetVisibleItemBounds()
    end
    local total = (msgFrame and msgFrame.GetNumMessages and msgFrame:GetNumMessages()) or 0
    local visLines = (msgFrame and msgFrame.GetNumVisibleLines and msgFrame:GetNumVisibleLines()) or 14
    local offset = (msgFrame and msgFrame.GetScrollOffset and msgFrame:GetScrollOffset()) or 0
    local maxRange = 0
    if msgFrame and msgFrame.GetMaxScrollRange then
        local okR, rng = pcall(msgFrame.GetMaxScrollRange, msgFrame)
        if okR and type(rng) == "number" and rng > 0 then
            maxRange = rng
        end
    elseif total > visLines then
        maxRange = total - visLines
    end
    if total <= 0 then
        return 1, 0, offset, visLines, maxRange
    end
    local bottomIdx = math.max(1, math.min(total, total - offset))
    local topIdx = bottomIdx
    local acc = 0
    for idx = bottomIdx, 1, -1 do
        acc = acc + ((lineVisRows and lineVisRows[idx]) or 1)
        topIdx = idx
        if acc >= visLines then
            break
        end
    end
    return topIdx, bottomIdx, offset, visLines, maxRange
end

--- Resolves which tracked section corresponds to the top of the current viewport.
function Chat:ResolveStickySection(msgFrame, state)
    if not (msgFrame and state and state.sections and #state.sections > 0) then
        return nil
    end
    local topIdx, bottomIdx, offset, visLines, maxRange = self:FindTopVisibleLine(msgFrame, state.lineVisRows)
    local secs = state.sections
    local activeIdx = nil
    for i = 1, #secs do
        local s = secs[i]
        local startLine = s.bannerLineIdx or s.firstMsgLineIdx or 1
        if startLine <= topIdx then
            activeIdx = i
        else
            break
        end
    end
    if not activeIdx and (secs[1].bannerLineIdx or 1) <= bottomIdx then
        activeIdx = 1
    end
    if not activeIdx then
        return nil
    end
    return secs[activeIdx], activeIdx, topIdx, bottomIdx, offset, visLines, maxRange
end

--- Scrolls `msgFrame` to the start of the active sticky section (exposing 1-2 lines or ~22px of the prior section),
--- or jumps up to the previous section if already viewing the start of the active one.
function Chat:JumpToStickySectionStart(msgFrame, state)
    local activeSec, activeIdx, topIdx, _, offset, visLines, maxRange = self:ResolveStickySection(msgFrame, state)
    if not activeSec then
        return false
    end
    local secs = state.sections
    if msgFrame and msgFrame._isStreamViewport and msgFrame.ComputeSectionScrollOffset then
        local targetOff = msgFrame:ComputeSectionScrollOffset(activeSec.bannerLineIdx or 1)
        if (activeSec.bannerLineIdx or 0) >= topIdx or math.abs(targetOff - offset) <= 2 then
            if activeIdx > 1 then
                targetOff = msgFrame:ComputeSectionScrollOffset(secs[activeIdx - 1].bannerLineIdx or 1)
            elseif maxRange > offset then
                targetOff = maxRange
            end
        end
        msgFrame:SetScrollOffset(targetOff)
        return true, targetOff
    end
    local total = (msgFrame.GetNumMessages and msgFrame:GetNumMessages()) or #(state.lineVisRows or {})
    local function ComputeOffsetForSection(sec)
        local anchorLine = math.max(1, sec.bannerLineIdx or 1)
        if anchorLine <= 1 then
            return maxRange
        end
        local prevRows = (state.lineVisRows and state.lineVisRows[anchorLine - 1]) or 1
        local targetTop = (anchorLine > 2 and prevRows == 1) and (anchorLine - 2) or (anchorLine - 1)
        local acc = 0
        local targetBottom = targetTop
        for li = targetTop, total do
            acc = acc + ((state.lineVisRows and state.lineVisRows[li]) or 1)
            targetBottom = li
            if acc >= visLines then
                break
            end
        end
        return math.max(0, math.min(maxRange, total - targetBottom))
    end
    local targetOff = ComputeOffsetForSection(activeSec)
    if (activeSec.bannerLineIdx or 0) >= topIdx or math.abs(targetOff - offset) <= 0 then
        if activeIdx > 1 then
            targetOff = ComputeOffsetForSection(secs[activeIdx - 1])
        elseif maxRange > offset then
            targetOff = maxRange
        end
    end
    if msgFrame.SetScrollOffset then
        msgFrame:SetScrollOffset(targetOff)
        return true, targetOff
    end
    return false
end

function Chat:_CleanGuildSysName(rawName)
    if type(rawName) ~= "string" then return nil end
    local s = rawName:gsub("|H[^|]+|h(.-)|h", "%1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^%[(.-)%]$", "%1")
    s = s:gsub('^"(.-)"$', "%1")
    s = s:gsub("[%.!%?]+$", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    if Compat and Compat.ParseCharacterName then
        local p = Compat.ParseCharacterName(s)
        if p and p.displayName and p.displayName ~= "" then
            return p.displayName, p.lookupKey
        end
    end
    return s, s:lower()
end

function Chat:_CompileGuildSysPat(globalStr, slotsByArgPos)
    if type(globalStr) ~= "string" or globalStr == "" then
        return nil
    end
    local escaped = globalStr:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local order = {}
    local idx = 0
    local pat = escaped:gsub("%%%%(?:(%d+)%$)?s", function(posStr)
        idx = idx + 1
        local argIdx = tonumber(posStr) or idx
        order[#order + 1] = slotsByArgPos[argIdx] or ("arg" .. tostring(argIdx))
        return "(.+)"
    end)
    if #order == 0 then
        return nil
    end
    return { pat = "^" .. pat .. "$", order = order }
end

function Chat:_ParseGuildSystemEvent(rawMsg)
    if type(rawMsg) ~= "string" or rawMsg == "" then
        return nil
    end
    local clean = rawMsg:gsub("|H[^|]+|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then
        return nil
    end

    if not self._guildSysPats then
        self._guildSysPats = {}
        local specs = {
            { kind = "JOIN", g = _G.ERR_GUILD_JOIN_S, slots = { "target" } },
            { kind = "LEAVE", g = _G.ERR_GUILD_LEAVE_S, slots = { "target" } },
            { kind = "KICK", g = _G.ERR_GUILD_REMOVE_SS, slots = { "target", "actor" } },
            { kind = "PROMOTE", g = _G.ERR_GUILD_PROMOTE_SSS, slots = { "actor", "target", "rank" } },
            { kind = "DEMOTE", g = _G.ERR_GUILD_DEMOTE_SSS, slots = { "actor", "target", "rank" } },
        }
        for _, sp in ipairs(specs) do
            local compiled = self:_CompileGuildSysPat(sp.g, sp.slots)
            if compiled then
                compiled.kind = sp.kind
                self._guildSysPats[#self._guildSysPats + 1] = compiled
            end
        end
        local fallbackPats = {
            { kind = "JOIN", pat = "^(.+) has joined the guild%.?$", order = { "target" } },
            { kind = "JOIN", pat = "^(.+) entrou na guilda%.?$", order = { "target" } },
            { kind = "JOIN", pat = "^(.+) se ha unido a la hermandad%.?$", order = { "target" } },
            { kind = "LEAVE", pat = "^(.+) has left the guild%.?$", order = { "target" } },
            { kind = "LEAVE", pat = "^(.+) saiu da guilda%.?$", order = { "target" } },
            { kind = "LEAVE", pat = "^(.+) deixou a guilda%.?$", order = { "target" } },
            { kind = "LEAVE", pat = "^(.+) ha abandonado la hermandad%.?$", order = { "target" } },
            { kind = "LEAVE", pat = "^(.+) ha dejado la hermandad%.?$", order = { "target" } },
            { kind = "KICK", pat = "^(.+) has been kicked out of the guild by (.+)%.?$", order = { "target", "actor" } },
            { kind = "KICK", pat = "^(.+) foi expulso da guilda por (.+)%.?$", order = { "target", "actor" } },
            { kind = "KICK", pat = "^(.+) foi expulsa da guilda por (.+)%.?$", order = { "target", "actor" } },
            { kind = "KICK", pat = "^(.+) ha sido expulsado de la hermandad por (.+)%.?$", order = { "target", "actor" } },
            { kind = "KICK", pat = "^(.+) ha sido expulsada de la hermandad por (.+)%.?$", order = { "target", "actor" } },
            { kind = "PROMOTE", pat = "^(.+) has promoted (.+) to (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "PROMOTE", pat = "^(.+) promoveu (.+) a (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "PROMOTE", pat = "^(.+) promoveu (.+) para (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "PROMOTE", pat = "^(.+) ha ascendido a (.+) a (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "DEMOTE", pat = "^(.+) has demoted (.+) to (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "DEMOTE", pat = "^(.+) rebaixou (.+) a (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "DEMOTE", pat = "^(.+) rebaixou (.+) para (.+)%.?$", order = { "actor", "target", "rank" } },
            { kind = "DEMOTE", pat = "^(.+) ha degradado a (.+) a (.+)%.?$", order = { "actor", "target", "rank" } },
        }
        for _, fp in ipairs(fallbackPats) do
            self._guildSysPats[#self._guildSysPats + 1] = fp
        end
    end

    for _, item in ipairs(self._guildSysPats) do
        local c1, c2, c3 = clean:match(item.pat)
        if c1 then
            local caps = { c1, c2, c3 }
            local parsed = { kind = item.kind }
            for i, fieldName in ipairs(item.order) do
                local val = caps[i]
                if fieldName == "target" then
                    local disp, lk = self:_CleanGuildSysName(val)
                    parsed.target = disp
                    parsed.targetLk = lk
                elseif fieldName == "actor" then
                    local disp = self:_CleanGuildSysName(val)
                    parsed.actor = disp
                elseif fieldName == "rank" then
                    local rk = val and val:gsub("[%.!%?]+$", ""):gsub("^%s+", ""):gsub("%s+$", "") or nil
                    parsed.rank = rk
                end
            end
            if parsed.target and parsed.target ~= "" then
                return parsed
            end
        end
    end
    return nil
end

function Chat:BuildGuildMilestoneReplyText(entry)
    if type(entry) ~= "table" then return "" end
    local target = entry.guildTarget or entry.senderCharName or ""
    local parsed = (Compat and Compat.ParseCharacterName and target ~= "") and Compat.ParseCharacterName(target) or nil
    local shortName = (parsed and parsed.firstName and parsed.firstName ~= "") and parsed.firstName or target
    if entry.guildEventKind == "PROMOTE" then
        local rk = (entry.guildRank and entry.guildRank ~= "") and entry.guildRank or L["the promotion"]
        return string.format(L["Congrats on %s, %s!"], rk, shortName)
    end
    return string.format(L["Welcome to the guild, %s!"], shortName)
end

function Chat:FormatGuildEventDisplayLine(entry, msgIdx, threadKey, tsPart)
    if type(entry) ~= "table" or not entry.guildEventKind then
        return nil
    end
    local kind = entry.guildEventKind
    local target = tostring(entry.guildTarget or entry.senderCharName or "?")
    local cleanWho = target:gsub("^<[^>]+>%s*", ""):gsub("[|\r\n]", "")
    local clsFile = entry.classFile
    if (not clsFile or clsFile == "") and Compat and Compat.ParseCharacterFields and LookupClassFromCache and cleanWho ~= "" and cleanWho ~= "?" then
        local tLk = Compat.ParseCharacterFields(cleanWho)
        if tLk then
            clsFile = LookupClassFromCache(tLk, nil)
            if clsFile and clsFile ~= "" then
                entry.classFile = clsFile
            end
        end
    end
    local cHex = (clsFile and Compat and Compat.ClassHex and Compat.ClassHex(clsFile)) or "|cffe6edf3"
    local targetLink = (cleanWho ~= "" and cleanWho ~= "?")
        and ("|Haddon:SCentral:w:" .. cleanWho .. "|h" .. cHex .. target .. "|r|h")
        or (cHex .. target .. "|r")
    local actorSuffix = ""
    if entry.guildActor and entry.guildActor ~= "" then
        actorSuffix = " |cff8b949e(" .. string.format(L["by %s"], tostring(entry.guildActor)) .. ")|r"
    end
    local isMe = (Compat and Compat.IsMe and Compat.IsMe(target)) and true or false
    local preTs = tsPart or ""
    local starIco = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12:0:0|t"
    local crownIco = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:13:13:0:0|t"
    local chatIco = "|TInterface\\ChatFrame\\UI-ChatIcon-Chat-Up:12:12:0:0|t"
    local okIco = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"

    if kind == "JOIN" then
        local btnPart = ""
        if not isMe then
            if entry.guildActionSent then
                btnPart = " |cff6e7681[" .. okIco .. " " .. L["Welcomed"] .. "]|r"
            elseif msgIdx and threadKey then
                btnPart = " |Haddon:SCentral:guildact:" .. tostring(msgIdx) .. ":" .. tostring(threadKey) .. "|h|cff3fb950[" .. chatIco .. " " .. L["Welcome!"] .. "]|r|h"
            end
        end
        return preTs .. "|cff2ecc71——|r " .. starIco .. " |cff69f0ae" .. L["Guild Join"] .. ":|r " .. targetLink .. " |cffe6edf3" .. L["joined the guild!"] .. "|r" .. btnPart
    elseif kind == "PROMOTE" then
        local rkTxt = tostring(entry.guildRank or "?")
        local btnPart = ""
        if not isMe then
            if entry.guildActionSent then
                btnPart = " |cff6e7681[" .. okIco .. " " .. L["Congratulated"] .. "]|r"
            elseif msgIdx and threadKey then
                btnPart = " |Haddon:SCentral:guildact:" .. tostring(msgIdx) .. ":" .. tostring(threadKey) .. "|h|cffffd24d[" .. starIco .. " " .. L["Congrats!"] .. "]|r|h"
            end
        end
        return preTs .. "|cffffd24d——|r " .. crownIco .. " |cffffe082" .. L["Promoted"] .. ":|r " .. targetLink .. " |cffd0d7de->|r |cffffd24d" .. rkTxt .. "|r" .. actorSuffix .. btnPart
    elseif kind == "DEMOTE" then
        local rkTxt = tostring(entry.guildRank or "?")
        return preTs .. "|cffff9b3d——|r |cffffb74d" .. L["Rank Updated"] .. ":|r " .. targetLink .. " |cffd0d7de->|r |cffff9b3d" .. rkTxt .. "|r" .. actorSuffix
    elseif kind == "KICK" then
        return preTs .. "|cfff54747——|r |cffff6b6b" .. L["Guild Kick"] .. ":|r " .. targetLink .. actorSuffix
    else
        return preTs .. "|cfff54747——|r |cffff8a80" .. L["Guild Leave"] .. ":|r " .. targetLink .. " |cff9da7b5" .. L["left the guild."] .. "|r"
    end
end

local function AppendMessage(thread, senderName, text, incoming, classFile, skipPersist, silent, extraFields)
    if not thread or not text or text == "" then return end
    if thread._hydrated == false and Chat.EnsureThreadHydrated then
        Chat:EnsureThreadHydrated(thread)
    end
    local ts = (extraFields and tonumber(extraFields.customTs)) or time()
    local isMention = false
    if incoming and (thread.kind == "ROOM" or thread.kind == "ALLIANCE" or IsPublicChannelKind(thread.kind)) then
        local myDisp = GetMyInfo()
        if myDisp and myDisp ~= Chat._cachedMyDispForMention then
            Chat._cachedMyDispForMention = myDisp
            local myParsed = Compat.ParseCharacterName and Compat.ParseCharacterName(myDisp)
            local rawFn = myParsed and myParsed.firstName and myParsed.firstName:lower() or nil
            Chat._cachedMyFirstLower = (rawFn and #rawFn >= 2) and rawFn or false
        end
        local fnLow = Chat._cachedMyFirstLower
        if fnLow and fnLow ~= false then
            local rawStr = tostring(text)
            local rawLow = rawStr:lower()
            if rawLow:find(fnLow, 1, true) then
                local plainLow = rawStr:find("|", 1, true)
                    and rawStr:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
                    or rawLow
                local padded = " " .. plainLow:gsub("[%p]", " ") .. " "
                if padded:find(" " .. fnLow .. " ", 1, true) or plainLow:find("@" .. fnLow, 1, true) then
                    isMention = true
                end
            end
        end
    end

    local isStatus = extraFields and extraFields.isStatusNotice and true or false
    local isDirectThread = (thread.kind == "WHISPER" or thread.kind == "BN_WHISPER")
    local senderDisp = senderName or "?"
    local dedupNorm = Chat:_NormalizeGeneralDedupText(text)
    local dedupSenderKey = (not isStatus) and Chat:_ExtractGeneralSenderKey((extraFields and extraFields.senderCharName) or senderDisp, incoming ~= true) or nil
    if not (extraFields and extraFields.allowDuplicate == true) and type(thread.messages) == "table" and #thread.messages > 0 then
        local msgId = extraFields and extraFields.deliveryMsgId
        local scanFloor = math.max(1, #thread.messages - 7)
        for i = #thread.messages, scanFloor, -1 do
            local prev = thread.messages[i]
            if prev then
                if msgId and prev.deliveryMsgId == msgId then
                    return prev
                end
                if (not isStatus) and (prev.isStatusNotice ~= true) and dedupNorm and math.abs(ts - (tonumber(prev.ts) or 0)) <= 3 then
                    local prevNorm = prev._dedupSig or Chat:_NormalizeGeneralDedupText(prev.text)
                    if prevNorm and prevNorm == dedupNorm and ((prev.incoming == true) == (incoming == true)) then
                        local prevSenderKey = prev._dedupSenderKey or Chat:_ExtractGeneralSenderKey(prev.senderCharName or prev.sender, prev.incoming == false)
                        if (dedupSenderKey and prevSenderKey and dedupSenderKey == prevSenderKey) or (not dedupSenderKey and not prevSenderKey) then
                            return prev
                        end
                    end
                end
            end
        end
    end
    local targetDisp = extraFields and extraFields.targetChar or nil
    if (not isStatus) and isDirectThread then
        if incoming then
            senderDisp = ResolveChatSenderDisplay(senderDisp, extraFields and extraFields.senderGuid, thread.targetName or thread.title)
            if not targetDisp or targetDisp == "" then
                targetDisp = GetMyInfo()
            else
                targetDisp = ResolveChatSenderDisplay(targetDisp, nil, nil)
            end
        else
            senderDisp = ResolveChatSenderDisplay(senderDisp, nil, nil)
            if not targetDisp or targetDisp == "" then
                targetDisp = thread.targetName or thread.title
            end
            if targetDisp and targetDisp ~= "" then
                targetDisp = ResolveChatSenderDisplay(targetDisp, nil, nil)
            end
        end
    end

    local senderLk = (not isStatus and Compat.ParseCharacterFields and senderDisp ~= "?") and Compat.ParseCharacterFields(senderDisp) or nil
    local targetLk = (not isStatus and Compat.ParseCharacterFields and targetDisp and targetDisp ~= "") and Compat.ParseCharacterFields(targetDisp) or nil
    local resolvedClass = classFile or (senderLk and LookupClassFromCache and LookupClassFromCache(senderLk, extraFields and extraFields.senderGuid)) or nil
    local resolvedTargetClass = (extraFields and extraFields.targetClass)
        or (targetLk and LookupClassFromCache and LookupClassFromCache(targetLk, nil))
        or nil
    local resolvedSenderFac = (not isStatus) and ((extraFields and extraFields.senderFaction)
        or (senderDisp ~= "?" and Chat:GetKnownCharacterFaction(senderDisp, extraFields and extraFields.senderGuid, incoming and thread.bnetAccountID or nil)))
        or nil
    local resolvedTargetFac = (not isStatus) and ((extraFields and extraFields.targetFaction)
        or (targetDisp and targetDisp ~= "" and Chat:GetKnownCharacterFaction(targetDisp, nil, (not incoming) and thread.bnetAccountID or nil)))
        or nil
    local resolvedSenderLvl = (not isStatus) and ((extraFields and extraFields.senderLevel)
        or (senderDisp ~= "?" and LookupLevelFromCache(senderLk, (extraFields and extraFields.senderCharName) or senderDisp, extraFields and extraFields.senderGuid, incoming and thread.bnetAccountID or nil)))
        or nil
    if resolvedSenderLvl and (tonumber(resolvedSenderLvl) or 0) <= 0 then
        resolvedSenderLvl = nil
    end

    local groupRosterId = (not isStatus) and Chat:CaptureCurrentGroupSnapshot(thread, ts, extraFields) or nil

    local entry = {
        sender = senderDisp,
        targetChar = targetDisp,
        text = text,
        ts = ts,
        incoming = incoming and true or false,
        classFile = resolvedClass,
        targetClass = resolvedTargetClass,
        senderFaction = resolvedSenderFac,
        targetFaction = resolvedTargetFac,
        senderLevel = resolvedSenderLvl,
        senderCharName = (extraFields and extraFields.senderCharName) or nil,
        senderGuid = (extraFields and extraFields.senderGuid) or nil,
        threadTitle = thread.title,
        targetName = thread.targetName,
        viaAddon = extraFields and extraFields.viaAddon and true or false,
        isStatusNotice = isStatus,
        statusKind = extraFields and extraFields.statusKind or nil,
        deliveryMsgId = extraFields and extraFields.deliveryMsgId or nil,
        deliveryState = extraFields and extraFields.deliveryState or nil,
        noteId = extraFields and extraFields.noteId or nil,
        isMention = isMention or nil,
        groupRosterId = groupRosterId,
        noSenderColon = (extraFields and extraFields.noSenderColon) and true or nil,
        guildEventKind = extraFields and extraFields.guildEventKind or nil,
        guildTarget = extraFields and extraFields.guildTarget or nil,
        guildActor = extraFields and extraFields.guildActor or nil,
        guildRank = extraFields and extraFields.guildRank or nil,
        guildActionSent = (extraFields and extraFields.guildActionSent) and true or nil,
        _dedupSig = dedupNorm,
        _dedupSenderKey = dedupSenderKey,
    }
    if isDirectThread and incoming and resolvedSenderLvl then
        thread.level = resolvedSenderLvl
    end
    if extraFields and tonumber(extraFields.customTs) and #thread.messages > 0 then
        local insAt = #thread.messages + 1
        while insAt > 1 and (tonumber(thread.messages[insAt - 1].ts) or 0) > ts do
            insAt = insAt - 1
        end
        table.insert(thread.messages, insAt, entry)
    else
        table.insert(thread.messages, entry)
    end
    if thread.kind ~= "NOTES" then
        local maxMem = math.max(MAX_THREAD_LINES, Chat:GetHistoryLimitForKey(thread.key))
        local msgs = thread.messages
        local dropMem = #msgs - maxMem
        if dropMem > 0 then
            local trimmedGrp = false
            for i = 1, dropMem do
                local rem = msgs[i]
                if rem and rem.groupRosterId then
                    trimmedGrp = true
                end
            end
            for k = 1, maxMem do
                msgs[k] = msgs[k + dropMem]
            end
            for k = #msgs, maxMem + 1, -1 do
                msgs[k] = nil
            end
            if trimmedGrp and type(thread.groupRosters) == "table" then
                local keep = {}
                for _, mm in ipairs(msgs) do
                    if type(mm) == "table" and mm.groupRosterId then
                        keep[mm.groupRosterId] = true
                    end
                end
                for rk in pairs(thread.groupRosters) do
                    if not keep[rk] then
                        thread.groupRosters[rk] = nil
                    end
                end
            end
        end
    end
    thread.lastAt = math.max(tonumber(thread.lastAt) or 0, ts)

    local mainVisible = ns.UI and ns.UI.IsMainVisible and ns.UI:IsMainVisible()
    local isViewing = false
    if ns.QuickReply and ns.QuickReply.IsViewingThread and ns.QuickReply:IsViewingThread(thread.key) then
        isViewing = true
    elseif ns.UI and ns.UI.IsChatThreadVisible then
        isViewing = ns.UI:IsChatThreadVisible(thread.key)
    elseif mainVisible then
        isViewing = (Chat.activeThreadKey == thread.key)
    end
    local isMuted = Chat:IsThreadMuted(thread.key)
    local isPublic = IsPublicChannelKind(thread.kind)
    local isSayYell = (thread.kind == "LOCAL_SAY" or thread.kind == "LOCAL_YELL" or thread.kind == "PUB_CHANNEL")
    local sCfg = ns.db and ns.db.settings
    local allowChannelUnread = sCfg and sCfg.chatChannelUnread == true
    local allowQuickChan = sCfg and sCfg.quickReplyEnabled ~= false and Chat.IsQuickReplyKindEnabled and Chat:IsQuickReplyKindEnabled(thread.kind)

    if extraFields and extraFields.viaAddon and extraFields.echoToOfficial ~= false and not isMuted then
        Chat:EchoAddonMessageToOfficialFrames(thread, senderDisp, text, incoming, resolvedClass, extraFields)
    end

    if incoming and not isViewing and not isMuted and not (Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode()) then
        if (not isPublic) or (not isSayYell and allowChannelUnread) or allowQuickChan then
            if (thread.unread or 0) == 0 then
                thread.firstUnreadTs = ts
                thread.firstUnreadEntry = entry
            end
            thread.unread = (thread.unread or 0) + 1
            if isMention then
                thread.hasMention = true
            end
            Chat:InvalidateUnreadCache()
        end
        if not silent then
            PlayIncomingChime(thread.kind, thread.key, extraFields and extraFields.viaAddon == true, senderLk or thread.key, nil, thread.bnetAccountID)
        end
        if extraFields and extraFields.viaAddon and not silent then
            local notifyKind = extraFields.notifyKind
            if not notifyKind then
                if thread.kind == "ROOM" then
                    notifyKind = "ROOM"
                elseif thread.kind == "ALLIANCE" then
                    notifyKind = "ALLIANCE"
                else
                    notifyKind = "DIRECT"
                end
            end
            if notifyKind == "DIRECT" and sCfg and sCfg.addonMsgTaskbarFlash ~= false and FlashClientIcon then
                if not (Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced(senderLk or thread.key, thread.bnetAccountID)) then
                    pcall(FlashClientIcon)
                end
            end
            if sCfg and sCfg.addonMsgToast == true then
                local readableText = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x|H.-|h(.-)|h|r", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local cleanPreview = Compat.CleanPayloadField(readableText, 120)
                local sourceTag
                if notifyKind == "ALLIANCE" then
                    sourceTag = L["Alliance"]
                elseif notifyKind == "ROOM" then
                    sourceTag = (thread.title and thread.title ~= "") and thread.title or L["Private Room"]
                else
                    sourceTag = L["Direct Addon"]
                end
                ns:Emit("ADDON_MESSAGE_NOTIFY", {
                    id = extraFields.deliveryMsgId or (tostring(thread.key) .. ":" .. tostring(ts)),
                    kind = notifyKind,
                    sourceTag = sourceTag,
                    sender = tostring(senderDisp or "?"),
                    lookupKey = senderLk,
                    senderClass = resolvedClass,
                    text = cleanPreview,
                    threadKey = thread.key,
                    roomId = thread.roomId,
                    targetName = thread.targetName,
                    bnetAccountID = thread.bnetAccountID,
                    ts = ts,
                    priority = (notifyKind == "DIRECT") and 2 or 1,
                })
            end
        end
        local emittedAddonToast = (extraFields and extraFields.viaAddon and not silent and sCfg and sCfg.addonMsgToast == true) == true
        if not silent and not isStatus and thread.kind ~= "NOTES" and not emittedAddonToast then
            local pCat = ResolvePreviewCategory(thread.kind, extraFields)
            if pCat then
                local pChanKind = ResolvePreviewChannelKind(thread.kind, extraFields)
                local pCharName = (extraFields and extraFields.senderCharName)
                    or ((thread.kind == "WHISPER" or thread.kind == "PARTY" or thread.kind == "RAID" or thread.kind == "INSTANCE_CHAT" or thread.kind == "GUILD" or thread.kind == "OFFICER" or thread.kind == "ROOM") and senderDisp)
                    or thread.targetName
                local pCharLk = pCharName and Compat.ParseCharacterFields and Compat.ParseCharacterFields(pCharName) or senderLk
                local pGuid = (extraFields and extraFields.senderGuid) or (pCharLk and LookupGuidFromCache(pCharLk)) or nil
                ns:Emit("INCOMING_MESSAGE_PREVIEW", {
                    id = (extraFields and extraFields.deliveryMsgId) or (tostring(thread.key) .. ":" .. tostring(ts)),
                    category = pCat,
                    channelKind = pChanKind,
                    sender = tostring(senderDisp or "?"),
                    senderCharName = pCharName,
                    lookupKey = pCharLk or senderLk,
                    senderGuid = pGuid,
                    senderClass = resolvedClass,
                    bnetAccountID = thread.bnetAccountID,
                    bnetName = thread.bnetName,
                    text = text,
                    threadKey = thread.key,
                    roomId = thread.roomId,
                    roomTitle = (thread.kind == "ROOM") and thread.title or nil,
                    replySlash = (extraFields and extraFields.replySlash) or thread.slash,
                    viaAddon = extraFields and extraFields.viaAddon == true or false,
                    ts = ts,
                    priority = (pCat == "WHISPER" or pCat == "BN_WHISPER") and 2 or 1,
                })
            end
        end
    elseif (not incoming) and (not isStatus) then
        thread.firstUnreadTs = nil
        thread.firstUnreadEntry = nil
        thread.lastReadBannerTs = nil
        thread.lastReadBannerEntry = nil
        if (thread.unread or 0) > 0 or thread.hasMention then
            thread.unread = 0
            thread.hasMention = nil
            if type(thread.key) == "string" and (thread.key:sub(1, 2) == "w:" or Chat:IsGuildHistoryKey(thread.key)) then
                local hist = GetHistoryScopeTable()
                if hist and type(hist[thread.key]) == "table" then
                    hist[thread.key].unread = 0
                end
            end
            Chat:InvalidateUnreadCache()
        end
        ns:Emit("CHAT_THREAD_READ", {
            threadKey = thread.key,
            channelKey = thread.key,
            kind = thread.kind,
            bnetAccountID = thread.bnetAccountID,
        })
    end

    local shouldPersist = Chat:ShouldPersistThreadKey(thread.key)
    if not skipPersist and shouldPersist then
        if extraFields and extraFields.rewritePersist then
            RewriteThreadHistory(thread)
        else
            PersistWhisperLine(thread.key, entry, thread.unread, thread)
        end
    end
    local qrVisible = ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown()
    if isPublic then
        QueueChatEmit((mainVisible or qrVisible) and 0.08 or 0.30)
    else
        ns:Emit("CHAT_UPDATED")
    end
    return entry
end

local function EnrichLoadedThreadMessages(t, defaultPeerDisp)
    if not t or type(t.messages) ~= "table" or #t.messages == 0 then return end
    local msgs = t.messages
    -- Collect player's own active character names per outgoing message to infer missing targetChar on older incoming lines.
    local outgoingSamples = {}
    for _, m in ipairs(msgs) do
        if type(m) == "table" and not m.isStatusNotice then
            if not m.incoming and type(m.sender) == "string" and m.sender ~= "" and m.sender ~= L["System"] then
                m.sender = ResolveChatSenderDisplay(m.sender, nil, nil)
                outgoingSamples[#outgoingSamples + 1] = { ts = tonumber(m.ts) or 0, char = m.sender }
            end
        end
    end

    local fallbackSelf = GetMyInfo()
    local function InferLocalReceiverAt(ts)
        if #outgoingSamples == 0 then return fallbackSelf end
        local bestChar, bestDist = nil, 999999999
        for _, s in ipairs(outgoingSamples) do
            local d = math.abs((ts or 0) - s.ts)
            if d < bestDist then
                bestDist = d
                bestChar = s.char
            end
        end
        if bestChar and bestDist <= 14400 then
            return bestChar
        end
        return fallbackSelf
    end

    for _, m in ipairs(msgs) do
        if type(m) == "table" and not m.isStatusNotice then
            if m.incoming then
                m.sender = ResolveChatSenderDisplay(m.sender or defaultPeerDisp, nil, t.targetName or defaultPeerDisp)
                if not m.targetChar or m.targetChar == "" then
                    m.targetChar = InferLocalReceiverAt(tonumber(m.ts) or 0)
                else
                    m.targetChar = ResolveChatSenderDisplay(m.targetChar, nil, nil)
                end
            else
                m.sender = ResolveChatSenderDisplay(m.sender, nil, nil)
                if not m.targetChar or m.targetChar == "" then
                    m.targetChar = ResolveChatSenderDisplay(t.targetName or defaultPeerDisp, nil, defaultPeerDisp)
                else
                    m.targetChar = ResolveChatSenderDisplay(m.targetChar, nil, defaultPeerDisp)
                end
            end
            if not m.classFile then
                local sLk = Compat.ParseCharacterFields(m.sender or "")
                m.classFile = sLk and LookupClassFromCache(sLk) or nil
            end
            if not m.targetClass and m.targetChar and m.targetChar ~= "" then
                local tLk = Compat.ParseCharacterFields(m.targetChar)
                m.targetClass = tLk and LookupClassFromCache(tLk) or nil
            end
            if not m.senderFaction and m.sender and m.sender ~= "" then
                m.senderFaction = Chat:GetKnownCharacterFaction(m.sender, nil, m.incoming and t.bnetAccountID or nil)
            end
            if not m.targetFaction and m.targetChar and m.targetChar ~= "" then
                m.targetFaction = Chat:GetKnownCharacterFaction(m.targetChar, nil, (not m.incoming) and t.bnetAccountID or nil)
            end
            if (not m.senderLevel or m.senderLevel <= 0) and m.sender and m.sender ~= "" and m.sender ~= L["System"] then
                local lvl = LookupLevelFromCache(nil, m.senderCharName or m.sender, m.senderGuid, m.incoming and t.bnetAccountID or nil)
                if lvl and lvl > 0 then
                    m.senderLevel = lvl
                    if m.incoming and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and (not t.level or t.level <= 0) then
                        t.level = lvl
                    end
                end
            end
        end
    end
end

function Chat:LoadGuildHistoryIfReady()
    local guildLimit = self:GetGuildHistoryLimit()
    local hist = GetHistoryScopeTable()
    if not hist or guildLimit <= 0 then return false end
    local curGuild = Compat and Compat.GuildName and Compat.GuildName() or nil
    if type(curGuild) ~= "string" or curGuild == "" then
        curGuild = nil
    end
    local loadedScope = curGuild or "__DEFAULT__"
    if self._guildHistLoadedScope == loadedScope then
        return false
    end
    local loadedAny = false
    for _, gKey in ipairs({ "ch:guild", "ch:officer" }) do
        local meta = STATIC_CHANNEL_ORDER[gKey]
        local scopedKey = curGuild and (gKey .. ":" .. curGuild) or gKey
        local scopedSaved = hist[scopedKey]
        local legacySaved = (scopedKey ~= gKey) and hist[gKey] or nil
        local legacyAllowed = legacySaved and type(legacySaved.lines) == "table"
            and (not legacySaved.guildName or legacySaved.guildName == "" or legacySaved.guildName == curGuild)
        if meta and ((type(scopedSaved) == "table" and type(scopedSaved.lines) == "table" and #scopedSaved.lines > 0) or (legacyAllowed and #legacySaved.lines > 0)) then
            local combined = {}
            local seenCounts = {}
            local function AddSavedList(savedTbl)
                if type(savedTbl) ~= "table" or type(savedTbl.lines) ~= "table" then return end
                local localCounts = {}
                for _, line in ipairs(savedTbl.lines) do
                    if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                        local sig = tostring(line.ts or 0) .. "|" .. tostring(line.sender or "") .. "|" .. tostring(line.text or "")
                        local occ = (localCounts[sig] or 0) + 1
                        localCounts[sig] = occ
                        if occ > (seenCounts[sig] or 0) then
                            seenCounts[sig] = occ
                            combined[#combined + 1] = line
                        end
                    end
                end
            end
            if legacyAllowed then AddSavedList(legacySaved) end
            AddSavedList(scopedSaved)
            if #combined > 0 then
                table.sort(combined, function(a, b)
                    local ta, tb = tonumber(a.ts) or 0, tonumber(b.ts) or 0
                    if ta ~= tb then return ta < tb end
                    local sa, sb = tostring(a.sender or ""), tostring(b.sender or "")
                    if sa ~= sb then return sa < sb end
                    return tostring(a.text or "") < tostring(b.text or "")
                end)
                local t = EnsureThread(gKey, meta.kind, L[meta.titleKey], { slash = meta.slash })
                local liveExtra = {}
                if t.messages and #t.messages > 0 then
                    local liveCounts = {}
                    for _, liveLine in ipairs(t.messages) do
                        local sig = tostring(liveLine.ts or 0) .. "|" .. tostring(liveLine.sender or "") .. "|" .. tostring(liveLine.text or "")
                        local occ = (liveCounts[sig] or 0) + 1
                        liveCounts[sig] = occ
                        if occ > (seenCounts[sig] or 0) then
                            seenCounts[sig] = occ
                            liveExtra[#liveExtra + 1] = liveLine
                        end
                    end
                end
                t.messages = {}
                t.unread = t.unread or 0
                local startIdx = math.max(1, #combined - guildLimit + 1)
                for i = startIdx, #combined do
                    local line = combined[i]
                    local sDisp = ResolveChatSenderDisplay(line.sender or "?", nil, nil)
                    table.insert(t.messages, {
                        sender = sDisp,
                        targetChar = line.targetChar,
                        text = line.text,
                        ts = tonumber(line.ts) or 0,
                        incoming = line.incoming and true or false,
                        classFile = line.classFile,
                        targetClass = line.targetClass,
                        senderFaction = line.senderFaction,
                        targetFaction = line.targetFaction,
                        senderLevel = ValidLevel(line.senderLevel),
                        viaAddon = line.viaAddon and true or false,
                        noSenderColon = line.noSenderColon and true or nil,
                        guildEventKind = line.guildEventKind,
                        guildTarget = line.guildTarget,
                        guildActor = line.guildActor,
                        guildRank = line.guildRank,
                        guildActionSent = line.guildActionSent and true or nil,
                    })
                    t.lastAt = math.max(t.lastAt or 0, tonumber(line.ts) or 0)
                end
                for _, liveLine in ipairs(liveExtra) do
                    table.insert(t.messages, liveLine)
                    t.lastAt = math.max(t.lastAt or 0, tonumber(liveLine.ts) or 0)
                end
                while #t.messages > math.max(MAX_THREAD_LINES, guildLimit) do
                    table.remove(t.messages, 1)
                end
                if curGuild and legacyAllowed and type(scopedSaved) ~= "table" then
                    hist[scopedKey] = {
                        title = L[meta.titleKey],
                        guildName = curGuild,
                        updatedAt = t.lastAt or time(),
                        unread = 0,
                        lines = combined,
                    }
                end
                loadedAny = true
            end
        end
    end
    self._guildHistLoadedScope = loadedScope
    if loadedAny then
        ns:Emit("CHAT_UPDATED")
    end
    return loadedAny
end

function Chat:EnsureThreadHydrated(threadOrKey)
    local t = type(threadOrKey) == "table" and threadOrKey or (type(threadOrKey) == "string" and self.threads and self.threads[threadOrKey]) or nil
    if not t or t._hydrated ~= false then
        return t
    end
    t._hydrated = true
    local histKey = t._savedHistKey or t.key
    local savedLast = t._savedLastLine
    t._savedLastLine = nil
    t._savedCount = nil
    local hist = GetHistoryScopeTable()
    local saved = hist and histKey and hist[histKey]
    if type(saved) ~= "table" or type(saved.lines) ~= "table" or #saved.lines == 0 then
        return t
    end
    local limit = GetChatHistoryLimit()
    if limit <= 0 then
        return t
    end
    local canonDisp = t._savedCanonDisp or t.targetName or t.title
    local defaultPeerFac = saved.faction or t.faction
    local myFac = Compat and Compat.PlayerFaction and Compat.PlayerFaction() or nil
    t.messages = t.messages or {}
    local startIdx = math.max(1, #saved.lines - limit + 1)
    for i = startIdx, #saved.lines do
        local line = saved.lines[i]
        if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
            local isInc = line.incoming and true or false
            local fallbackWho = (isInc and canonDisp) or nil
            local rawSender = line.sender or (isInc and (saved.targetName or canonDisp)) or nil
            table.insert(t.messages, {
                sender = ResolveChatSenderDisplay(rawSender or canonDisp, nil, fallbackWho),
                targetChar = line.targetChar,
                text = line.text,
                ts = tonumber(line.ts) or 0,
                incoming = isInc,
                classFile = line.classFile,
                targetClass = line.targetClass,
                senderFaction = line.senderFaction or (isInc and defaultPeerFac or myFac),
                targetFaction = line.targetFaction or (isInc and myFac or defaultPeerFac),
                senderLevel = ValidLevel(line.senderLevel),
                viaAddon = line.viaAddon and true or false,
                noSenderColon = line.noSenderColon and true or nil,
                guildEventKind = line.guildEventKind,
                guildTarget = line.guildTarget,
                guildActor = line.guildActor,
                guildRank = line.guildRank,
                guildActionSent = line.guildActionSent and true or nil,
            })
            t.lastAt = math.max(t.lastAt or 0, tonumber(line.ts) or 0)
        end
    end
    EnrichLoadedThreadMessages(t, canonDisp)
    return t
end

function Chat:_CompactSavedHistoryScope(hist)
    if type(hist) ~= "table" then return end
    local myFac = Compat and Compat.PlayerFaction and Compat.PlayerFaction() or nil
    for k, saved in pairs(hist) do
        if type(k) == "string" and type(saved) == "table" then
            local lines = saved.lines
            if type(lines) == "table" then
                local isW = (k:sub(1, 2) == "w:")
                if isW and #lines == 0 and (tonumber(saved.unread) or 0) == 0 and (tonumber(saved.updatedAt) or 0) == 0 then
                    hist[k] = nil
                else
                    local sTarget = saved.targetName
                    local sFac = saved.faction
                    for i = 1, #lines do
                        local ln = lines[i]
                        if type(ln) == "table" then
                            if ln.incoming == false then ln.incoming = nil end
                            if ln.viaAddon == false then ln.viaAddon = nil end
                            if ln.isStatusNotice == false then ln.isStatusNotice = nil end
                            if ln.noSenderColon == false then ln.noSenderColon = nil end
                            if isW then
                                if ln.incoming == true and sTarget and ln.sender == sTarget then
                                    ln.sender = nil
                                end
                                if sFac and ln.senderFaction == sFac then
                                    ln.senderFaction = nil
                                end
                                if myFac and ln.targetFaction == myFac then
                                    ln.targetFaction = nil
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Chat:LoadSavedHistory()
    local histRoot = ns.db and ns.db.chatHistory
    local curScope = Compat.ScopeKey and Compat.ScopeKey() or nil
    if type(histRoot) == "table" and curScope and (type(histRoot[curScope]) ~= "table" or next(histRoot[curScope]) == nil)
        and Store and Store.NormalizeLegacyRealmScopes and not self._chatAutoRescued
    then
        for k, v in pairs(histRoot) do
            if k ~= curScope and type(v) == "table" and next(v) ~= nil then
                self._chatAutoRescued = true
                Store:NormalizeLegacyRealmScopes()
                break
            end
        end
    end
    self:SeedKnownNamesFromSavedData()
    local limit = GetChatHistoryLimit()
    local hist = GetHistoryScopeTable()
    self._savedTextBytes = self:_EstimateAllSavedTextBytes()
    if self._savedTextBytes > (self._MAX_TEXT_HISTORY_BYTES or (6 * 1024 * 1024)) then
        self:_EnforceSavedHistoryTextQuota()
    end
    if hist then
        self:_CompactSavedHistoryScope(hist)
        PruneSavedScopeTable(hist, HISTORY_TTL_SECONDS, MAX_SAVED_THREADS, GetHistoryStamp, IsProtectedThreadRecord)
    end
    local savedPeers = GetAddonPeersScopeTable()
    if savedPeers then
        PruneSavedScopeTable(savedPeers, PEER_TTL_SECONDS, MAX_SAVED_PEERS, GetPeerStamp)
    end
    if hist then
        local notesSaved = hist["notes:self"]
        local notesThread = EnsureThread("notes:self", "NOTES", L["Personal Notes (You)"], {})
        notesThread.messages = {}
        notesThread.unread = 0
        if type(notesSaved) == "table" and type(notesSaved.lines) == "table" then
            for idx, line in ipairs(notesSaved.lines) do
                if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                    local nId = line.noteId or (tostring(line.ts or 0) .. "_" .. tostring(idx))
                    line.noteId = nId
                    table.insert(notesThread.messages, {
                        sender = line.sender or L["Personal Notes"],
                        text = line.text,
                        ts = tonumber(line.ts) or 0,
                        incoming = false,
                        noteId = nId,
                    })
                    notesThread.lastAt = math.max(notesThread.lastAt or 0, tonumber(line.ts) or 0)
                end
            end
        end
    end
    if hist and limit > 0 then
        local sortedKeys = {}
        for threadKey, saved in pairs(hist) do
            if type(threadKey) == "string" and threadKey:sub(1, 2) == "w:" and type(saved) == "table" and type(saved.lines) == "table" then
                sortedKeys[#sortedKeys + 1] = threadKey
            end
        end
        table.sort(sortedKeys, function(a, b)
            local ha, hb = a:find("-", 3, true) ~= nil, b:find("-", 3, true) ~= nil
            if ha ~= hb then return ha end
            return a < b
        end)
        for _, threadKey in ipairs(sortedKeys) do
            local saved = hist[threadKey]
            local parsed = Compat.ParseCharacterName(saved.targetName or saved.title or threadKey:sub(3))
            if parsed then
                local canonDisp = parsed.surname and parsed.displayName or ResolveChatSenderDisplay(parsed.displayName, nil, nil)
                local canonParsed = Compat.ParseCharacterName(canonDisp) or parsed
                local cachedLvl = ValidLevel(saved.level) or LookupLevelFromCache(canonParsed.lookupKey, canonParsed.displayName)
                local t = EnsureThread(threadKey, "WHISPER", canonParsed.displayName, {
                    targetName = canonParsed.displayName,
                    classFile = LookupClassFromCache(canonParsed.lookupKey),
                    faction = saved.faction,
                    level = cachedLvl,
                })
                if cachedLvl and (not t.level or t.level <= 0) then
                    t.level = cachedLvl
                end
                t.messages = t.messages or {}
                local savedUnread = math.max(0, math.floor(tonumber(saved.unread) or 0))
                if savedUnread > limit then savedUnread = limit end
                t.unread = savedUnread
                local lineCnt = #saved.lines
                local lastLine = lineCnt > 0 and saved.lines[lineCnt] or nil
                local lastTs = math.max(tonumber(saved.updatedAt) or 0, (type(lastLine) == "table" and tonumber(lastLine.ts)) or 0)
                t.lastAt = math.max(t.lastAt or 0, lastTs)
                if lineCnt > 0 then
                    t._hydrated = false
                    t._savedHistKey = threadKey
                    t._savedCanonDisp = canonParsed.displayName
                    t._savedCount = math.min(lineCnt, limit)
                    t._savedLastLine = lastLine
                else
                    t._hydrated = true
                end
            end
        end
    end

    self:LoadGuildHistoryIfReady()

    local genLimit = self:GetGeneralHistoryLimit()
    if hist and genLimit > 0 and self:ShouldSaveGroupHistory() then
        for _, gKey in ipairs({ "ch:party", "ch:instance", "ch:raid" }) do
            local saved = hist[gKey]
            local meta = STATIC_CHANNEL_ORDER[gKey]
            if meta and type(saved) == "table" and type(saved.lines) == "table" and #saved.lines > 0 then
                local t = EnsureThread(gKey, meta.kind, L[meta.titleKey], { slash = meta.slash })
                t.messages = {}
                t.unread = 0
                t.hasMention = nil
                t.groupRosters = {}
                if type(saved.groupRosters) == "table" then
                    for rk, rv in pairs(saved.groupRosters) do
                        if type(rk) == "string" and type(rv) == "table" and type(rv.members) == "table" then
                            t.groupRosters[rk] = rv
                        end
                    end
                end
                local startIdx = math.max(1, #saved.lines - genLimit + 1)
                for i = startIdx, #saved.lines do
                    local line = saved.lines[i]
                    if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                        local sDisp = ResolveChatSenderDisplay(line.sender or "?", nil, nil)
                        table.insert(t.messages, {
                            sender = sDisp,
                            targetChar = line.targetChar,
                            text = line.text,
                            ts = tonumber(line.ts) or 0,
                            incoming = line.incoming and true or false,
                            classFile = line.classFile,
                            targetClass = line.targetClass,
                            senderFaction = line.senderFaction,
                            targetFaction = line.targetFaction,
                            senderLevel = ValidLevel(line.senderLevel),
                            viaAddon = line.viaAddon and true or false,
                            groupRosterId = line.groupRosterId,
                        })
                        t.lastAt = math.max(t.lastAt or 0, tonumber(line.ts) or 0)
                    end
                end
            end
        end
    end

    if hist and genLimit > 0 and self:ShouldSaveGeneralHistory() then
        local genSaved = hist["ch:general"]
        local genMeta = STATIC_CHANNEL_ORDER["ch:general"]
        if genMeta and type(genSaved) == "table" and type(genSaved.lines) == "table" and #genSaved.lines > 0 then
            local gt = EnsureThread("ch:general", "GENERAL", L[genMeta.titleKey], { slash = genMeta.slash })
            gt.messages = {}
            gt.unread = 0
            gt.hasMention = nil
            local startIdx = math.max(1, #genSaved.lines - genLimit + 1)
            for i = startIdx, #genSaved.lines do
                local line = genSaved.lines[i]
                if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                    local normTxt = self:_NormalizeGeneralDedupText(line.text)
                    local sKey = self:_ExtractGeneralSenderKey(line.senderCharName or line.sender, line.incoming == false)
                    table.insert(gt.messages, {
                        ts = tonumber(line.ts) or 0,
                        sender = line.sender or L["System"],
                        senderCharName = line.senderCharName,
                        senderGuid = line.senderGuid,
                        senderLevel = ValidLevel(line.senderLevel),
                        text = line.text,
                        incoming = line.incoming and true or false,
                        classFile = line.classFile,
                        isStatusNotice = line.isStatusNotice and true or false,
                        noSenderColon = line.noSenderColon and true or false,
                        generalTag = line.generalTag,
                        msgKind = line.msgKind,
                        channelId = line.channelId,
                        mentionTerm = line.mentionTerm,
                        _dedupSig = normTxt,
                        _dedupSenderKey = sKey,
                    })
                    gt.lastAt = math.max(gt.lastAt or 0, tonumber(line.ts) or 0)
                end
            end
        end

        local alSaved = hist["ch:alliance"]
        local alMeta = STATIC_CHANNEL_ORDER["ch:alliance"]
        if alMeta and type(alSaved) == "table" and type(alSaved.lines) == "table" and #alSaved.lines > 0 then
            local t = EnsureThread("ch:alliance", alMeta.kind, L[alMeta.titleKey], { slash = alMeta.slash })
            t.messages = {}
            t.unread = 0
            t.hasMention = nil
            local startIdx = math.max(1, #alSaved.lines - genLimit + 1)
            for i = startIdx, #alSaved.lines do
                local line = alSaved.lines[i]
                if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                    table.insert(t.messages, {
                        sender = line.sender or "?",
                        text = line.text,
                        ts = tonumber(line.ts) or 0,
                        incoming = line.incoming and true or false,
                        classFile = line.classFile,
                        viaAddon = line.viaAddon and true or false,
                    })
                    t.lastAt = math.max(t.lastAt or 0, tonumber(line.ts) or 0)
                end
            end
        end

        local mSaved = hist["mentions:radar"]
        if type(mSaved) == "table" and type(mSaved.lines) == "table" and #mSaved.lines > 0 then
            local mt = self:EnsureMentionsThread()
            if mt then
                mt.messages = {}
                mt.unread = 0
                mt.hasMention = nil
                local startIdx = math.max(1, #mSaved.lines - genLimit + 1)
                for i = startIdx, #mSaved.lines do
                    local line = mSaved.lines[i]
                    if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                        table.insert(mt.messages, {
                            ts = tonumber(line.ts) or 0,
                            sender = line.sender or "?",
                            text = line.text,
                            rawText = line.rawText,
                            incoming = true,
                            classFile = line.classFile,
                            isMention = true,
                            mentionTerm = line.mentionTerm,
                            mentionChannel = line.mentionChannel,
                            mentionType = line.mentionType,
                            senderCharName = line.senderCharName or line.sender,
                            senderLookupKey = line.senderLookupKey,
                            senderGuid = line.senderGuid,
                            sourceThreadKey = line.sourceThreadKey,
                        })
                        mt.lastAt = math.max(mt.lastAt or 0, tonumber(line.ts) or 0)
                    end
                end
            end
        end
    end

    local rooms = GetRoomsScopeTable()
    if rooms then
        for roomId, room in pairs(rooms) do
            if type(room) == "table" and room.joined then
                local rKey = "room:" .. roomId
                local rt = EnsureThread(rKey, "ROOM", room.title or roomId, {
                    roomId = roomId,
                })
                local rSaved = hist and genLimit > 0 and self:ShouldSaveGeneralHistory() and hist[rKey]
                if rt and type(rSaved) == "table" and type(rSaved.lines) == "table" and #rSaved.lines > 0 then
                    rt.messages = {}
                    rt.unread = 0
                    local startIdx = math.max(1, #rSaved.lines - genLimit + 1)
                    for i = startIdx, #rSaved.lines do
                        local line = rSaved.lines[i]
                        if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                            local sDisp = ResolveChatSenderDisplay(line.sender or "?", nil, nil)
                            table.insert(rt.messages, {
                                sender = sDisp,
                                text = line.text,
                                ts = tonumber(line.ts) or 0,
                                incoming = line.incoming and true or false,
                                classFile = line.classFile,
                                senderLevel = ValidLevel(line.senderLevel),
                                viaAddon = line.viaAddon and true or false,
                            })
                            rt.lastAt = math.max(rt.lastAt or 0, tonumber(line.ts) or 0)
                        end
                    end
                end
            end
        end
    end
    if self.ConsolidatePlayerThreads then
        self:ConsolidatePlayerThreads(true)
    end
    self:InvalidateUnreadCache()
end

function Chat:IsQuickReplyKindEnabled(kind)
    local s = ns.db and ns.db.settings
    if not s or not kind then
        return false
    end
    if kind == "WHISPER" or kind == "ROOM" or kind == "ALLIANCE" then
        return s.quickReplyNotifyWhisper ~= false
    elseif kind == "BN_WHISPER" then
        return s.quickReplyNotifyBNet ~= false
    elseif kind == "PARTY" or kind == "INSTANCE" or kind == "INSTANCE_CHAT" then
        return s.quickReplyNotifyParty ~= false
    elseif kind == "RAID" then
        return s.quickReplyNotifyRaid ~= false
    elseif kind == "GUILD" or kind == "OFFICER" then
        return s.quickReplyNotifyGuild == true
    elseif kind == "LOCAL_SAY" or kind == "LOCAL_YELL" then
        return s.quickReplyNotifySay == true
    end
    return false
end

function Chat:SetQuickReplyDraft(threadKey, rawText)
    if type(threadKey) ~= "string" or threadKey == "" then
        return
    end
    if type(self.quickReplyDrafts) ~= "table" then
        self.quickReplyDrafts = {}
    end
    local clean = Compat.Trim and Compat.Trim(tostring(rawText or "")) or tostring(rawText or "")
    if clean == "" then
        self.quickReplyDrafts[threadKey] = nil
    else
        self.quickReplyDrafts[threadKey] = {
            text = tostring(rawText),
            updatedAt = time(),
        }
    end
end

function Chat:GetQuickReplyDraft(threadKey)
    if type(threadKey) ~= "string" or type(self.quickReplyDrafts) ~= "table" then
        return nil
    end
    local rec = self.quickReplyDrafts[threadKey]
    return rec and rec.text or nil
end

function Chat:GetQuickReplyDraftCount()
    if type(self.quickReplyDrafts) ~= "table" then
        return 0
    end
    local count = 0
    for key, rec in pairs(self.quickReplyDrafts) do
        if rec and rec.text and rec.text ~= "" and self.threads and self.threads[key] then
            count = count + 1
        end
    end
    return count
end

function Chat:IsQuickReplyPinned(threadKey)
    if not threadKey or threadKey == "notes:self" or threadKey == "mentions:radar" then
        return false
    end
    if IsSessionOnlyPinnedKey(threadKey) then
        return self.sessionQuickReplyPinned and self.sessionQuickReplyPinned[threadKey] == true or false
    end
    local pinned = ns.charDb and ns.charDb.quickReplyPinnedThreads
    return type(pinned) == "table" and pinned[threadKey] == true or false
end

function Chat:SetQuickReplyPinned(threadKey, state)
    if not threadKey or threadKey == "notes:self" or threadKey == "mentions:radar" or threadKey == "ch:general" then
        return false
    end
    local on = state and true or false
    if IsSessionOnlyPinnedKey(threadKey) then
        self.sessionQuickReplyPinned = self.sessionQuickReplyPinned or {}
        self.sessionQuickReplyPinned[threadKey] = on or nil
    elseif ns.charDb then
        if type(ns.charDb.quickReplyPinnedThreads) ~= "table" then
            ns.charDb.quickReplyPinnedThreads = {}
        end
        ns.charDb.quickReplyPinnedThreads[threadKey] = on or nil
    else
        return false
    end
    if on and STATIC_CHANNEL_ORDER[threadKey] then
        local meta = STATIC_CHANNEL_ORDER[threadKey]
        EnsureThread(threadKey, meta.kind, L[meta.titleKey], { slash = meta.slash })
    elseif on and type(threadKey) == "string" and threadKey:sub(1, 7) == "ch:pub:" then
        local pubId = tonumber(threadKey:sub(8))
        if pubId then
            self:EnsureOfficialNumberedChannelThread(pubId)
        end
    end
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:ToggleQuickReplyPinned(threadKey)
    local nextState = not self:IsQuickReplyPinned(threadKey)
    self:SetQuickReplyPinned(threadKey, nextState)
    return nextState
end

function Chat:CloseQuickReplyTab(threadKey)
    if not threadKey or threadKey == "notes:self" or threadKey == "mentions:radar" or threadKey == "ch:general" then
        return false
    end
    local t = self.threads and self.threads[threadKey]
    if t and (t.unread or 0) > 0 and self.MarkThreadRead then
        self:MarkThreadRead(threadKey)
    end
    if self.SetQuickReplyDraft then
        self:SetQuickReplyDraft(threadKey, "")
    end
    if self.IsQuickReplyPinned and self:IsQuickReplyPinned(threadKey) and self.SetQuickReplyPinned then
        self:SetQuickReplyPinned(threadKey, false)
    end
    if self._dungeonAutoChannelKey == threadKey then
        self._dungeonAutoChannelKey = nil
    end
    if threadKey == "ch:say" or threadKey == "ch:yell" then
        self._quickReplyClosedMsgCounts = self._quickReplyClosedMsgCounts or {}
        self._quickReplyClosedMsgCounts[threadKey] = #(t and t.messages or {})
    end
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:HasQuickReplyPinnedTabs()
    if self.sessionQuickReplyPinned and next(self.sessionQuickReplyPinned) ~= nil then
        return true
    end
    local pinned = ns.charDb and ns.charDb.quickReplyPinnedThreads
    if type(pinned) == "table" and next(pinned) ~= nil then
        return true
    end
    return false
end

function Chat:GetRecommendedInstanceThreadKey()
    if IsInInstance then
        local ok, inInst, instType = pcall(IsInInstance)
        if ok and Safe and Safe.Value(inInst) == true then
            local it = Safe.String(instType)
            if it == "raid" then
                return "ch:raid"
            end
        end
    end
    if Compat and Compat.IsInRaid and Compat.IsInRaid() then
        return "ch:raid"
    end
    if IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE then
        local ok, inInstGrp = pcall(IsInGroup, _G.LE_PARTY_CATEGORY_INSTANCE)
        if ok and inInstGrp == true then
            return "ch:instance"
        end
    end
    return "ch:party"
end

function Chat:EnsureStaticChannelThread(threadKey)
    local meta = threadKey and STATIC_CHANNEL_ORDER[threadKey]
    if not meta then return nil end
    return EnsureThread(threadKey, meta.kind, L[meta.titleKey], { slash = meta.slash })
end

function Chat:ParseCommunityChannelName(rawChannelName)
    local raw = Safe.String(rawChannelName)
    if not raw or raw == "" then
        return nil, nil, nil
    end
    local numPrefix, cidStr, sidStr = raw:match("^(%d*%.?%s*)Community:(%d+):(%d+)$")
    if not cidStr then
        cidStr, sidStr = raw:match("Community:(%d+):(%d+)")
        numPrefix = ""
    end
    local clubId = tonumber(cidStr)
    local streamId = tonumber(sidStr)
    if not clubId then
        return nil, nil, nil
    end
    local friendly = nil
    if _G.C_Club then
        local cInfo = _G.C_Club.GetClubInfo and Safe.Call(_G.C_Club.GetClubInfo, clubId) or nil
        if type(cInfo) == "table" then
            local cName = Safe.String(cInfo.shortName) or Safe.String(cInfo.name)
            if cName and cName ~= "" then
                friendly = cName
            end
        end
        if streamId and _G.C_Club.GetStreamInfo then
            local sInfo = Safe.Call(_G.C_Club.GetStreamInfo, clubId, streamId)
            if type(sInfo) == "table" then
                local sName = Safe.String(sInfo.name)
                local genType = _G.Enum and _G.Enum.ClubStreamType and _G.Enum.ClubStreamType.General
                if sName and sName ~= "" and (genType == nil or sInfo.streamType ~= genType) then
                    friendly = friendly and (friendly .. " - " .. sName) or sName
                end
            end
        end
    end
    if not friendly or friendly == "" then
        friendly = L["Community"] or "Community"
    end
    return ((numPrefix or "") .. friendly), clubId, streamId
end

Chat._CompareOfficialChannel = Chat._CompareOfficialChannel or function(a, b)
    return (a.id or 99) < (b.id or 99)
end

Chat._PackVarargInto = Chat._PackVarargInto or function(buf, ...)
    wipe(buf)
    local n = select("#", ...)
    for i = 1, n do
        buf[i] = select(i, ...)
    end
    return n
end

Chat._CollectChannelList = Chat._CollectChannelList or function(buf)
    return Chat._PackVarargInto(buf, _G.GetChannelList())
end

function Chat:InvalidateOfficialChannelsCache()
    self._officialChannelsCacheAt = 0
    self._generalTargetCache = nil
end

function Chat:GetJoinedOfficialChannels(forceRefresh)
    local nowMono = (GetTime and GetTime()) or 0
    if (not forceRefresh) and self._officialChannelsCache
        and self._officialChannelsCacheAt and self._officialChannelsCacheAt > 0
        and (nowMono - self._officialChannelsCacheAt) < 5.0
    then
        return self._officialChannelsCache
    end
    local list = self._officialChannelsCache
    if not list then
        list = {}
        self._officialChannelsCache = list
    else
        wipe(list)
    end
    local byId = self._officialChannelsById
    if not byId then
        byId = {}
        self._officialChannelsById = byId
    else
        wipe(byId)
    end
    if _G.GetChannelList then
        local packed = self._chanListScratch
        if not packed then
            packed = {}
            self._chanListScratch = packed
        end
        local okCh, n = pcall(Chat._CollectChannelList, packed)
        if not okCh or type(n) ~= "number" then
            self._officialChannelsCacheAt = nowMono
            return list
        end
        local stride = 3
        if n >= 3 and type(packed[3]) == "number" then
            stride = 2
        end
        for i = 1, n, stride do
            local cid = Safe.Number(packed[i])
            local cname = Safe.String(packed[i + 1])
            local disabled = (stride == 3) and (Safe.Value(packed[i + 2]) == true) or false
            if cid and cid >= 1 and cid <= 20 and cname and cname ~= "" and not disabled and not byId[cid] then
                local dispName, clubId, streamId = self:ParseCommunityChannelName(cname)
                local showName = dispName or cname
                local rec = {
                    id = cid,
                    name = showName,
                    rawName = cname,
                    clubId = clubId,
                    streamId = streamId,
                    threadKey = "ch:pub:" .. tostring(cid),
                    slash = "/" .. tostring(cid) .. " ",
                    title = tostring(cid) .. ". " .. showName,
                }
                byId[cid] = rec
                list[#list + 1] = rec
            end
        end
    end
    if #list == 0 and _G.GetChannelName then
        for cid = 1, 10 do
            local ok, rId, rName = pcall(_G.GetChannelName, cid)
            local nId = ok and Safe.Number(rId) or nil
            local nName = ok and Safe.String(rName) or nil
            if nId and nId >= 1 and nName and nName ~= "" and not byId[nId] then
                local dispName, clubId, streamId = self:ParseCommunityChannelName(nName)
                local showName = dispName or nName
                local rec = {
                    id = nId,
                    name = showName,
                    rawName = nName,
                    clubId = clubId,
                    streamId = streamId,
                    threadKey = "ch:pub:" .. tostring(nId),
                    slash = "/" .. tostring(nId) .. " ",
                    title = tostring(nId) .. ". " .. showName,
                }
                byId[nId] = rec
                list[#list + 1] = rec
            end
        end
    end
    table.sort(list, Chat._CompareOfficialChannel)
    self._officialChannelsCacheAt = nowMono
    return list
end

function Chat:GetOfficialChannelInfo(channelId)
    local cid = tonumber(channelId)
    if not cid or cid < 1 or cid > 20 then return nil end
    self:GetJoinedOfficialChannels(false)
    local cached = self._officialChannelsById and self._officialChannelsById[cid]
    if cached then
        return cached
    end
    if _G.GetChannelName then
        local ok, rId, rName = pcall(_G.GetChannelName, cid)
        local nId = ok and Safe.Number(rId) or nil
        local nName = ok and Safe.String(rName) or nil
        if nId and nId == cid and nName and nName ~= "" then
            local dispName, clubId, streamId = self:ParseCommunityChannelName(nName)
            local showName = dispName or nName
            local rec = {
                id = cid,
                name = showName,
                rawName = nName,
                clubId = clubId,
                streamId = streamId,
                threadKey = "ch:pub:" .. tostring(cid),
                slash = "/" .. tostring(cid) .. " ",
                title = tostring(cid) .. ". " .. showName,
            }
            if self._officialChannelsById then
                self._officialChannelsById[cid] = rec
            end
            return rec
        end
    end
    return nil
end

function Chat:SetGeneralTargetChannel(channelIdOrNil)
    self._generalTargetCache = nil
    if channelIdOrNil == "yell" or channelIdOrNil == "LOCAL_YELL" then
        self._generalChannelId = nil
        self._generalChannelName = nil
        self._generalLocalMode = "yell"
        return "yell"
    end
    local cid = tonumber(channelIdOrNil)
    if cid and cid >= 1 and cid <= 20 then
        self._generalChannelId = cid
        local info = self:GetOfficialChannelInfo(cid)
        self._generalChannelName = info and info.name or nil
        self._generalLocalMode = nil
        return cid
    end
    self._generalChannelId = nil
    self._generalChannelName = nil
    self._generalLocalMode = nil
    return nil
end

function Chat:GetGeneralTargetInfo()
    local cid = tonumber(self._generalChannelId)
    if cid and cid >= 1 and cid <= 20 then
        local info = self:GetOfficialChannelInfo(cid)
        if info then
            local cached = self._generalTargetCache
            if cached and cached.channelId == info.id and cached.name == info.name and cached.clubId == info.clubId and cached.streamId == info.streamId then
                return cached
            end
            cached = cached or {}
            cached.channelId = info.id
            cached.name = info.name
            cached.title = info.title
            cached.slash = info.slash
            cached.clubId = info.clubId
            cached.streamId = info.streamId
            cached.isSay = false
            cached.isYell = false
            self._generalTargetCache = cached
            return cached
        end
        self._generalChannelId = nil
        self._generalChannelName = nil
        self._generalTargetCache = nil
    end
    if self._generalLocalMode == "yell" then
        if not self._genYellTarget then
            self._genYellTarget = {
                channelId = nil,
                name = L["Yell"],
                title = L["Yell"],
                slash = "/y ",
                isSay = false,
                isYell = true,
            }
        end
        return self._genYellTarget
    end
    if not self._genSayTarget then
        self._genSayTarget = {
            channelId = nil,
            name = L["Say"],
            title = L["General"],
            slash = "/s ",
            isSay = true,
            isYell = false,
        }
    end
    return self._genSayTarget
end

function Chat:EnsureOfficialNumberedChannelThread(channelId, nameHint)
    local cid = tonumber(channelId)
    if not cid or cid < 1 or cid > 20 then return nil end
    local info = self:GetOfficialChannelInfo(cid)
    local cleanHint = (type(nameHint) == "string" and nameHint ~= "") and nameHint:gsub("^%d+%.%s*", "") or nil
    local liveName = (info and info.name) or cleanHint
    if not liveName or liveName == "" then
        return nil
    end
    self:SetGeneralTargetChannel(cid)
    local genMeta = STATIC_CHANNEL_ORDER["ch:general"]
    return EnsureThread("ch:general", "GENERAL", (genMeta and L[genMeta.titleKey]) or L["General"], { slash = "/s " })
end

function Chat:RefreshOfficialChannelThreads()
    local changed = false
    self:InvalidateOfficialChannelsCache()
    self:GetJoinedOfficialChannels(true)
    local byId = self._officialChannelsById or {}
    -- Unify Say, Yell, World & all numbered public channels into General: prune any legacy split tabs/pins.
    local pinned = ns.charDb and ns.charDb.quickReplyPinnedThreads
    if type(pinned) == "table" then
        for pKey in pairs(pinned) do
            if type(pKey) == "string" and (pKey:sub(1, 7) == "ch:pub:" or pKey == "ch:say" or pKey == "ch:yell") then
                pinned[pKey] = nil
                changed = true
            end
        end
    end
    if self.sessionQuickReplyPinned then
        self.sessionQuickReplyPinned["ch:say"] = nil
        self.sessionQuickReplyPinned["ch:yell"] = nil
    end
    for key, t in pairs(self.threads or {}) do
        if type(key) == "string" and (key:sub(1, 7) == "ch:pub:" or key == "ch:say" or key == "ch:yell") then
            self.threads[key] = nil
            changed = true
        elseif type(t) == "table" and (t.kind == "PUB_CHANNEL" or t.kind == "LOCAL_SAY" or t.kind == "LOCAL_YELL") then
            self.threads[key] = nil
            changed = true
        end
    end
    if self._generalChannelId then
        local info = byId[self._generalChannelId]
        if not info then
            self._generalChannelId = nil
            self._generalChannelName = nil
            changed = true
        elseif self._generalChannelName ~= info.name then
            self._generalChannelName = info.name
            changed = true
        end
    end
    if changed then
        ns:Emit("CHAT_UPDATED")
    end
    return changed
end

Chat._CompareQuickReplyThread = Chat._CompareQuickReplyThread or function(a, b)
    if (a.isAlwaysFirst == true) ~= (b.isAlwaysFirst == true) then
        return a.isAlwaysFirst == true
    end
    local aUn = (a.unread or 0) > 0
    local bUn = (b.unread or 0) > 0
    if aUn ~= bUn then
        return aUn
    end
    local aDraft, bDraft = (a.hasDraft == true), (b.hasDraft == true)
    if aDraft ~= bDraft then
        return aDraft
    end
    local aPin, bPin = (a.pinned == true), (b.pinned == true)
    if aPin ~= bPin then
        return aPin
    end
    if aPin and bPin then
        local ao, bo = a.staticOrder or 999, b.staticOrder or 999
        if ao ~= bo then
            return ao < bo
        end
    end
    if (a.lastAt or 0) ~= (b.lastAt or 0) then
        return (a.lastAt or 0) > (b.lastAt or 0)
    end
    return tostring(a.key or "") < tostring(b.key or "")
end

function Chat:GetQuickWhisperUnreadCount()
    local total = 0
    for key, t in pairs(self.threads) do
        if type(t) == "table" and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
            local u = tonumber(t.unread) or 0
            if u > 0 and not self:IsThreadMuted(key) then
                total = total + u
            end
        end
    end
    return total
end

function Chat:GetQuickReplyThreads()
    local list = self._qrThreadsScratch
    if not list then
        list = {}
        self._qrThreadsScratch = list
    else
        wipe(list)
    end
    local s = ns.db and ns.db.settings
    local qrOn = (not s) or s.quickReplyEnabled ~= false
    if qrOn then
        local genMeta = STATIC_CHANNEL_ORDER["ch:general"]
        EnsureThread("ch:general", "GENERAL", (genMeta and L[genMeta.titleKey]) or L["General"], { slash = "/s " })
        local inGuild = false
        if Compat.ShouldShowGuildFeatures then
            inGuild = Compat.ShouldShowGuildFeatures() == true
        elseif Compat.IsInGuild then
            inGuild = Compat.IsInGuild() == true
        end
        local isAllianceAuth = inGuild and ns.Clan and ns.Clan.IsMemberAllianceAuthorized and ns.Clan:IsMemberAllianceAuthorized()
        for key, t in pairs(self.threads) do
            if type(t) == "table" and key ~= "notes:self" and key ~= "mentions:radar" and key ~= "ch:say" and key ~= "ch:yell" and key:sub(1, 7) ~= "ch:pub:" then
                local isGeneral = (key == "ch:general")
                local u = isGeneral and 0 or (t.unread or 0)
                local draft = self.quickReplyDrafts and self.quickReplyDrafts[key] or nil
                local isMuted = (not isGeneral) and self:IsThreadMuted(key)
                local hasUnread = (u > 0) and (not isMuted) and self:IsQuickReplyKindEnabled(t.kind)
                local isPinned = isGeneral or self:IsQuickReplyPinned(key)
                local isAutoDungeon = (self._dungeonAutoChannelKey ~= nil and self._dungeonAutoChannelKey == key)
                if isPinned and not isGeneral then
                    if key == "ch:guild" or key == "ch:officer" then
                        if not inGuild and #(t.messages or {}) == 0 then
                            isPinned = false
                        end
                    elseif key == "ch:alliance" then
                        if not isAllianceAuth and #(t.messages or {}) == 0 then
                            isPinned = false
                        end
                    end
                end
                if isGeneral or hasUnread or draft or isPinned or isAutoDungeon then
                    local sortAt = math.max(t.lastAt or 0, draft and draft.updatedAt or 0)
                    local meta = STATIC_CHANNEL_ORDER[key]
                    local titleStr = (meta and L[meta.titleKey]) or t.title or t.targetName or key
                    local pubOrder = (t.kind == "PUB_CHANNEL" and tonumber(t.channelId)) and (100 + tonumber(t.channelId)) or nil
                    local rec = t._qrThreadRec
                    if not rec then
                        rec = {}
                        t._qrThreadRec = rec
                    end
                    rec.key = key
                    rec.thread = t
                    rec.title = titleStr
                    rec.kind = t.kind
                    rec.unread = hasUnread and u or 0
                    rec.hasDraft = draft ~= nil
                    rec.draftText = draft and draft.text or nil
                    rec.pinned = (isPinned == true) or isAutoDungeon
                    rec.isAlwaysFirst = isGeneral
                    rec.muted = isMuted == true
                    rec.staticOrder = (meta and meta.order) or pubOrder or nil
                    rec.lastAt = sortAt
                    list[#list + 1] = rec
                end
            end
        end
    end
    table.sort(list, Chat._CompareQuickReplyThread)
    return list
end

function Chat:MarkAllQuickReplyRead()
    local list = self:GetQuickReplyThreads()
    local keys = {}
    for _, item in ipairs(list) do
        if item and item.key and (item.unread or 0) > 0 then
            keys[#keys + 1] = item.key
        end
    end
    for i = 1, #keys do
        self:MarkThreadRead(keys[i])
    end
    return #keys
end

function Chat:HasQuickReplyPending()
    local s = ns.db and ns.db.settings
    if s and s.quickReplyEnabled == false then
        return false
    end
    if type(self.quickReplyDrafts) == "table" then
        for key, rec in pairs(self.quickReplyDrafts) do
            if rec and rec.text and rec.text ~= "" and self.threads and self.threads[key] then
                return true
            end
        end
    end
    for key, t in pairs(self.threads) do
        if type(t) == "table" and key ~= "notes:self" and key ~= "mentions:radar" then
            if (t.unread or 0) > 0 and (not self:IsThreadMuted(key)) and self:IsQuickReplyKindEnabled(t.kind) then
                return true
            end
        end
    end
    return false
end

function Chat:GetUnreadSummary()
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return {
            total = 0,
            totalDirect = 0,
            channels = 0,
            invites = 0,
            rooms = 0,
            senders = {},
            byCategory = {
                whisper = 0,
                bnet = 0,
                group = 0,
                raid = 0,
                guild = 0,
                room = 0,
            },
        }
    end
    local s = ns.db and ns.db.settings
    local mirrorOn = s and s.chatMirrorChannels == true
    local allowChanUnread = s and s.chatChannelUnread == true
    local qrOn = s and s.quickReplyEnabled ~= false
    local qrSig = qrOn and ((s.quickReplyNotifyParty ~= false and "P" or "")
        .. (s.quickReplyNotifyRaid ~= false and "R" or "")
        .. (s.quickReplyNotifyGuild == true and "G" or "")
        .. (s.quickReplyNotifySay == true and "S" or "")) or "0"
    local chanFlag = ((mirrorOn and allowChanUnread) and "1" or "0") .. ":" .. qrSig
    if not self._unreadSummaryDirty and self._unreadSummaryCache and self._unreadSummaryChanFlag == chanFlag then
        return self._unreadSummaryCache
    end

    local direct, roomsUnread, invites, channels = 0, 0, 0, 0
    local byCategory = {
        whisper = 0,
        bnet = 0,
        group = 0,
        raid = 0,
        guild = 0,
        room = 0,
    }
    local senders = {}

    for key, t in pairs(self.threads) do
        local u = t.unread or 0
        if u > 0 and key ~= "mentions:radar" and key ~= "notes:self" and key ~= "ch:general" and t.kind ~= "MENTIONS" and t.kind ~= "NOTES" and t.kind ~= "GENERAL" and not self:IsThreadMuted(key) then
            if IsPublicChannelKind(t.kind) then
                local isSayYell = (t.kind == "LOCAL_SAY" or t.kind == "LOCAL_YELL")
                if (mirrorOn and allowChanUnread and not isSayYell) or (qrOn and self:IsQuickReplyKindEnabled(t.kind)) then
                    channels = channels + u
                    if t.kind == "GUILD" or t.kind == "OFFICER" then
                        byCategory.guild = byCategory.guild + u
                    elseif t.kind == "RAID" then
                        byCategory.raid = byCategory.raid + u
                    else
                        byCategory.group = byCategory.group + u
                    end
                    table.insert(senders, {
                        key = key,
                        title = t.title or key,
                        unread = u,
                        kind = t.kind,
                        lastAt = t.lastAt or 0,
                    })
                end
            elseif t.kind == "ROOM" or t.kind == "ALLIANCE" then
                roomsUnread = roomsUnread + u
                byCategory.room = byCategory.room + u
                table.insert(senders, {
                    key = key,
                    title = t.title or key,
                    unread = u,
                    kind = t.kind,
                    lastAt = t.lastAt or 0,
                })
            else
                direct = direct + u
                if t.kind == "BN_WHISPER" then
                    byCategory.bnet = byCategory.bnet + u
                else
                    byCategory.whisper = byCategory.whisper + u
                end
                table.insert(senders, {
                    key = key,
                    title = t.title or t.targetName or key,
                    unread = u,
                    kind = t.kind,
                    lastAt = t.lastAt or 0,
                })
            end
        end
    end

    local rooms = GetRoomsScopeTable()
    if rooms then
        for _, room in pairs(rooms) do
            if type(room) == "table" and room.pendingInvite and not room.joined then
                invites = invites + 1
                byCategory.room = byCategory.room + 1
            end
        end
    end

    table.sort(senders, function(a, b)
        local ta, tb = tonumber(a.lastAt) or 0, tonumber(b.lastAt) or 0
        if ta ~= tb then return ta > tb end
        return tostring(a.key or a.title or "") < tostring(b.key or b.title or "")
    end)

    local directTones = {}
    if byCategory.whisper > 0 then directTones[#directTones + 1] = "whisper" end
    if byCategory.bnet > 0 then directTones[#directTones + 1] = "bnet" end
    if byCategory.room > 0 then directTones[#directTones + 1] = "room" end

    local totalDirect = direct + roomsUnread + invites
    local summary = {
        direct = direct,
        rooms = roomsUnread,
        invites = invites,
        channels = channels,
        totalDirect = totalDirect,
        total = totalDirect + channels,
        byCategory = byCategory,
        directTones = directTones,
        senders = senders,
    }
    self._unreadSummaryCache = summary
    self._unreadSummaryChanFlag = chanFlag
    self._unreadSummaryDirty = false
    self._unreadDirectCache = totalDirect
    self._unreadDirty = false
    return summary
end

local function CountUnreadThreadsAndInvites(self, includeChannels)
    local allowChannels = false
    if includeChannels then
        local s = ns.db and ns.db.settings
        allowChannels = (s and s.chatMirrorChannels == true and s.chatChannelUnread == true) and true or false
    end

    local total = 0
    for key, t in pairs(self.threads) do
        local u = t.unread or 0
        if u > 0 and key ~= "mentions:radar" and key ~= "notes:self" and key ~= "ch:general" and t.kind ~= "MENTIONS" and t.kind ~= "NOTES" and t.kind ~= "GENERAL" and not self:IsThreadMuted(key) then
            if IsPublicChannelKind(t.kind) then
                if allowChannels then
                    total = total + u
                end
            else
                total = total + u
            end
        end
    end

    local rooms = GetRoomsScopeTable()
    if rooms then
        for _, room in pairs(rooms) do
            if type(room) == "table" and room.pendingInvite and not room.joined then
                total = total + 1
            end
        end
    end

    return total
end

function Chat:GetUnreadDirectCount()
    if not self._unreadDirty and self._unreadDirectCache ~= nil then
        return self._unreadDirectCache
    end
    local count = CountUnreadThreadsAndInvites(self, false)
    self._unreadDirectCache = count
    self._unreadDirty = false
    return count
end

function Chat:GetTotalUnread(includeChannels)
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return 0
    end
    if includeChannels ~= true then
        return self:GetUnreadDirectCount()
    end
    return self:GetUnreadSummary().total
end

function Chat:MarkThreadRead(threadKey)
    local t = threadKey and self.threads[threadKey]
    if t and ((t.unread or 0) > 0 or t.hasMention) then
        if (t.unread or 0) > 0 then
            t.lastReadBannerTs = t.firstUnreadTs
            t.lastReadBannerEntry = t.firstUnreadEntry
        end
        t.firstUnreadTs = nil
        t.firstUnreadEntry = nil
        t.unread = 0
        t.hasMention = nil
        if type(threadKey) == "string" and (threadKey:sub(1, 2) == "w:" or self:IsGuildHistoryKey(threadKey)) then
            local hist = GetHistoryScopeTable()
            if hist and type(hist[threadKey]) == "table" then
                hist[threadKey].unread = 0
            end
        end
        self:InvalidateUnreadCache()
        ns:Emit("CHAT_THREAD_READ", {
            threadKey = threadKey,
            channelKey = threadKey,
            kind = t.kind,
            bnetAccountID = t.bnetAccountID,
        })
        ns:Emit("CHAT_UPDATED")
    elseif t then
        ns:Emit("CHAT_THREAD_READ", {
            threadKey = threadKey,
            channelKey = threadKey,
            kind = t.kind,
            bnetAccountID = t.bnetAccountID,
        })
    end
end

function Chat:MarkThreadUnread(threadKey)
    local t = threadKey and threadKey ~= "notes:self" and self.threads[threadKey]
    if not t then return false end
    t.unread = math.max(1, t.unread or 0)
    if type(threadKey) == "string" and (threadKey:sub(1, 2) == "w:" or self:IsGuildHistoryKey(threadKey)) then
        local hist = GetHistoryScopeTable()
        if hist and type(hist[threadKey]) == "table" then
            hist[threadKey].unread = self:IsGuildHistoryKey(threadKey) and 0 or t.unread
        end
    end
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:SetActiveThread(threadKey, skipMarkRead)
    if self.activeThreadKey and self.activeThreadKey ~= threadKey and self.threads[self.activeThreadKey] then
        local prev = self.threads[self.activeThreadKey]
        prev.lastReadBannerTs = nil
        prev.lastReadBannerEntry = nil
    end
    self.activeThreadKey = threadKey
    if threadKey and self.threads[threadKey] and self.threads[threadKey]._hydrated == false then
        self:EnsureThreadHydrated(self.threads[threadKey])
    end
    if threadKey and not skipMarkRead then
        self:MarkThreadRead(threadKey)
    end
end

function Chat:GetRoom(roomId)
    local rooms = GetRoomsScopeTable()
    return rooms and roomId and rooms[roomId] or nil
end

function Chat:GetPendingRoomInvites()
    local rooms = GetRoomsScopeTable()
    local out = {}
    if not rooms then return out end
    for roomId, room in pairs(rooms) do
        if type(room) == "table" and room.pendingInvite and not room.joined then
            table.insert(out, room)
        end
    end
    table.sort(out, function(a, b)
        local ta, tb = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
        if ta ~= tb then return ta > tb end
        return tostring(a.id or a.title or "") < tostring(b.id or b.title or "")
    end)
    return out
end

local function SyncActiveCharacterOnThread(t, activeDisp, activeClass, activeFaction)
    if not t or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") then return false end
    if type(activeDisp) ~= "string" or activeDisp == "" or activeDisp:find("#", 1, true) then
        return false
    end
    local p = Compat.ParseCharacterName(activeDisp)
    if not p or not p.lookupKey then return false end
    local curTarget = t.targetName and Compat.ParseCharacterName(t.targetName) or nil
    if curTarget and curTarget.surname and curTarget.surname ~= "" and (not p.surname or p.surname == "")
        and curTarget.firstName and p.firstName and curTarget.firstName:lower() == p.firstName:lower()
    then
        return false
    end
    local changed = false
    if not curTarget or curTarget.lookupKey ~= p.lookupKey or t.title ~= p.displayName then
        t.title = p.displayName
        t.targetName = p.displayName
        changed = true
    end
    local resolvedCls = activeClass or LookupClassFromCache(p.lookupKey)
    if resolvedCls and resolvedCls ~= "" then
        t.classFile = resolvedCls
    end
    local resolvedFac = activeFaction or Chat:GetKnownCharacterFaction(p.displayName, nil, t.bnetAccountID)
    if resolvedFac and resolvedFac ~= "" then
        t.faction = resolvedFac
    end
    return changed
end

function Chat:GetThreadsList(kindFilter)
    local out = {}
    local rooms = GetRoomsScopeTable() or {}

    local sCfg = ns.db and ns.db.settings
    local mirrorChannels = sCfg and sCfg.chatMirrorChannels == true
    local inGuild = false
    if Compat.ShouldShowGuildFeatures then
        inGuild = Compat.ShouldShowGuildFeatures() == true
    elseif Compat.IsInGuild then
        inGuild = Compat.IsInGuild() == true
    end
    local inGroup = Compat.IsInGroup and Compat.IsInGroup()
    local isAllianceAuth = inGuild and ns.Clan and ns.Clan.IsMemberAllianceAuthorized and ns.Clan:IsMemberAllianceAuthorized()
    local canSaveGuildHist = inGuild and self:ShouldSaveGuildHistory()
    local canSaveGroupHist = self:ShouldSaveGroupHistory()
    local canShowSayYell = (not sCfg) or (sCfg.quickReplyRecordSay ~= false)

    for key, t in pairs(self.threads) do
        local isRoom = key:sub(1, 5) == "room:"
        local include = (key ~= "ch:say" and key ~= "ch:yell" and key:sub(1, 7) ~= "ch:pub:")
        if isRoom then
            local room = rooms[t.roomId]
            include = room and room.joined == true
        elseif key == "mentions:radar" then
            include = (kindFilter == "mentions") or (#(t.messages or {}) > 0)
        elseif key:sub(1, 3) == "ch:" then
            local isGuildChan = (t.kind == "GUILD" or t.kind == "OFFICER")
            local isGroupChan = (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT")
            local isAllianceChan = (t.kind == "ALLIANCE")
            local isSayYellChan = (t.kind == "LOCAL_SAY" or t.kind == "LOCAL_YELL")
            local isPubChan = (t.kind == "PUB_CHANNEL")
            local isGeneralChan = (t.kind == "GENERAL")
            local msgLen = #(t.messages or {})
            local hasMsgs = msgLen > 0
            local forceShow = (isGuildChan and inGuild and kindFilter == "guild")
                or (isGroupChan and inGroup and kindFilter == "group")
                or (isAllianceChan and isAllianceAuth and (kindFilter == "alliance" or kindFilter == "channels" or not kindFilter or kindFilter == "all"))
                or ((isSayYellChan or isPubChan) and kindFilter == "channels")
                or (isGeneralChan and (not kindFilter or kindFilter == "all" or kindFilter == "channels") and hasMsgs)
            local showGuildHist = isGuildChan and canSaveGuildHist and hasMsgs
            local showGroupHist = isGroupChan and canSaveGroupHist and hasMsgs
            local showSayYellHist = isSayYellChan and canShowSayYell and hasMsgs
            local showPubHist = isPubChan and hasMsgs
            include = (isAllianceChan and isAllianceAuth)
                or (((not isGuildChan and not isAllianceChan) or (isGuildChan and inGuild)) and mirrorChannels and hasMsgs)
                or showGuildHist
                or showGroupHist
                or showSayYellHist
                or showPubHist
                or forceShow
        end

        if include and kindFilter and kindFilter ~= "all" then
            if kindFilter == "unread" then
                include = (not self:IsThreadMuted(key)) and ((t.unread or 0) > 0)
            elseif kindFilter == "whispers" then
                include = (t.kind == "WHISPER" or t.kind == "BN_WHISPER" or t.kind == "NOTES")
            elseif kindFilter == "guild" then
                include = (t.kind == "GUILD" or t.kind == "OFFICER")
            elseif kindFilter == "group" then
                include = (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT")
            elseif kindFilter == "alliance" then
                include = (t.kind == "ALLIANCE")
            elseif kindFilter == "rooms" then
                include = (t.kind == "ROOM")
            elseif kindFilter == "channels" then
                include = IsPublicChannelKind(t.kind) or (t.kind == "ALLIANCE") or (t.kind == "GENERAL")
            elseif kindFilter == "mentions" then
                include = (t.kind == "MENTIONS") or (t.hasMention == true)
            end
        end

        if include then
            local lastMsg = (t._hydrated == false) and t._savedLastLine or (t.messages and t.messages[#t.messages])
            if key == "ch:general" and t._hydrated ~= false and type(t.messages) == "table" then
                lastMsg = nil
                for gi = #t.messages, 1, -1 do
                    local gm = t.messages[gi]
                    if type(gm) == "table" and self:IsGeneralEntryVisible(gm) then
                        lastMsg = gm
                        break
                    end
                end
            end
            local isMuted = self:IsThreadMuted(key)
            local item = t._listItem
            if not item then
                item = {}
                t._listItem = item
            end
            item.key = t.key
            item.kind = t.kind
            item.title = STATIC_CHANNEL_ORDER[t.key] and L[STATIC_CHANNEL_ORDER[t.key].titleKey] or t.title
            item.targetName = t.targetName
            item.bnetAccountID = t.bnetAccountID
            item.bnetName = t.bnetName
            item.classFile = t.classFile
            if t.kind == "WHISPER" or t.kind == "BN_WHISPER" then
                local livePeer = self.ResolveActivePeerTarget and self:ResolveActivePeerTarget(t) or nil
                if livePeer and not livePeer.bnetAppOnly and livePeer.activeDisplay and livePeer.activeDisplay ~= "" then
                    SyncActiveCharacterOnThread(t, livePeer.activeDisplay, livePeer.activeClassFile, livePeer.faction)
                    item.title = STATIC_CHANNEL_ORDER[t.key] and L[STATIC_CHANNEL_ORDER[t.key].titleKey] or t.title
                    item.targetName = t.targetName
                    item.classFile = t.classFile
                end
                item.activeChar = (livePeer and not livePeer.bnetAppOnly) and livePeer.activeDisplay or nil
                local liveFac = (livePeer and livePeer.faction)
                    or t.faction
                    or self:GetKnownCharacterFaction(t.targetName or t.title, nil, t.bnetAccountID)
                if liveFac and not t.faction then
                    t.faction = liveFac
                end
                item.faction = liveFac
            else
                item.activeChar = nil
                item.faction = nil
            end
            item.roomId = t.roomId
            item.unread = isMuted and 0 or (t.unread or 0)
            item.hasMention = (not isMuted) and (t.hasMention == true) or false
            item.muted = isMuted
            item.pinned = self:IsThreadPinned(key)
            item._searchPreview = nil
            item.statusTag = self.GetThreadAvailabilityStatus and self:GetThreadAvailabilityStatus(t.key) or nil
            item.lastAt = t.lastAt or 0
            item.preview = lastMsg and lastMsg.text or ""
            item.count = (t._hydrated == false) and (t._savedCount or 0) or (t.messages and #t.messages or 0)
            table.insert(out, item)
        end
    end

    Chat._sortPinRanks = self:GetPinnedOrderMap()
    if not Chat._CompareThreadsDefault then
        Chat._CompareThreadsDefault = function(a, b)
            if (a.kind == "NOTES") ~= (b.kind == "NOTES") then
                return a.kind == "NOTES"
            end
            if (a.pinned == true) ~= (b.pinned == true) then
                return a.pinned == true
            end
            if a.pinned == true and b.pinned == true then
                local pr = Chat._sortPinRanks
                local ra = (pr and pr[a.key]) or 9999
                local rb = (pr and pr[b.key]) or 9999
                if ra ~= rb then
                    return ra < rb
                end
            end
            if (a.unread or 0) ~= (b.unread or 0) then
                return (a.unread or 0) > (b.unread or 0)
            end
            if (a.lastAt or 0) ~= (b.lastAt or 0) then
                return (a.lastAt or 0) > (b.lastAt or 0)
            end
            if (a.kind == "ROOM") ~= (b.kind == "ROOM") then
                return a.kind == "ROOM"
            end
            if a.kind ~= b.kind then
                return (a.kind or "") < (b.kind or "")
            end
            if (a.title or "") ~= (b.title or "") then
                return (a.title or "") < (b.title or "")
            end
            return (a.key or "") < (b.key or "")
        end
        Chat._CompareThreadsUnread = function(a, b)
            if (a.unread or 0) ~= (b.unread or 0) then
                return (a.unread or 0) > (b.unread or 0)
            end
            if (a.kind == "NOTES") ~= (b.kind == "NOTES") then
                return a.kind == "NOTES"
            end
            if (a.pinned == true) ~= (b.pinned == true) then
                return a.pinned == true
            end
            if (a.lastAt or 0) ~= (b.lastAt or 0) then
                return (a.lastAt or 0) > (b.lastAt or 0)
            end
            if (a.kind == "ROOM") ~= (b.kind == "ROOM") then
                return a.kind == "ROOM"
            end
            if a.kind ~= b.kind then
                return (a.kind or "") < (b.kind or "")
            end
            if (a.title or "") ~= (b.title or "") then
                return (a.title or "") < (b.title or "")
            end
            return (a.key or "") < (b.key or "")
        end
    end
    table.sort(out, (kindFilter == "unread") and Chat._CompareThreadsUnread or Chat._CompareThreadsDefault)
    return out
end

function Chat:GetThreadMessages(threadKey)
    local t = threadKey and self.threads[threadKey]
    if t and t._hydrated == false then
        self:EnsureThreadHydrated(t)
    end
    return t and t.messages or {}
end

--- Returns live availability state ("AFK" | "DND" | nil) and optional auto-reply note for direct threads.
function Chat:GetThreadAvailabilityStatus(threadKey)
    local t = threadKey and self.threads[threadKey]
    if not t or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") then
        return nil, nil
    end

    if Store then
        local row = nil
        if t.targetName then
            local tp = Compat.ParseCharacterName(t.targetName)
            if tp and tp.lookupKey and Store.socialByLookup then
                row = Store.socialByLookup[tp.lookupKey]
            end
        end
        if not row and t.bnetAccountID and Store.socialDirectoryByKey then
            row = Store.socialDirectoryByKey["bnet:" .. tostring(t.bnetAccountID)]
        end
        if type(row) == "table" and row.online then
            if row.dnd then
                return "DND", (t.peerStatus == "DND") and t.peerStatusMsg or nil
            elseif row.afk then
                return "AFK", (t.peerStatus == "AFK") and t.peerStatusMsg or nil
            end
        end
    end

    if t.peerStatus and t.peerStatusAt and (time() - t.peerStatusAt) < 180 then
        return t.peerStatus, t.peerStatusMsg
    end
    return nil, nil
end

local NO_ADDON_FALLBACK_PREFIX = (L["No addon reply from %s — switched to standard WoW whisper for your next send."] or ""):match("^(.-)%%s") or ""

local function IsStaleAddonFallbackNotice(m)
    if type(m) ~= "table" or not m.isStatusNotice then return false end
    if m.statusKind == "ADDON_FALLBACK" then return true end
    if NO_ADDON_FALLBACK_PREFIX ~= "" and type(m.text) == "string" and m.text:find(NO_ADDON_FALLBACK_PREFIX, 1, true) then
        return true
    end
    return false
end

local function CleanMsgForDedup(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " "))
end

local function DeduplicateAndSortMessages(msgs, dropStaleFallback)
    if type(msgs) ~= "table" or #msgs == 0 then return msgs or {} end
    local sorted = {}
    for _, m in ipairs(msgs) do
        if type(m) == "table" and type(m.text) == "string" and m.text ~= "" then
            if not (dropStaleFallback and IsStaleAddonFallbackNotice(m)) then
                sorted[#sorted + 1] = m
            end
        end
    end
    table.sort(sorted, function(a, b)
        local ta, tb = tonumber(a.ts) or 0, tonumber(b.ts) or 0
        if ta ~= tb then return ta < tb end
        local aOff = (a.deliveryState == "off" or a.deliveryState == "declined") and 1 or 0
        local bOff = (b.deliveryState == "off" or b.deliveryState == "declined") and 1 or 0
        return aOff > bOff
    end)

    local out = {}
    for _, m in ipairs(sorted) do
        local ts = tonumber(m.ts) or 0
        local sig = (m.isStatusNotice and "S|" or (m.incoming and "I|" or "O|")) .. CleanMsgForDedup(m.text)
        local dupIdx = nil
        for i = #out, 1, -1 do
            local prev = out[i]
            local pts = tonumber(prev.ts) or 0
            if (ts - pts) > 180 then break end
            local psig = (prev.isStatusNotice and "S|" or (prev.incoming and "I|" or "O|")) .. CleanMsgForDedup(prev.text)
            if psig == sig then
                dupIdx = i
                break
            end
        end
        if dupIdx then
            local prev = out[dupIdx]
            local prevBad = (prev.deliveryState == "off" or prev.deliveryState == "declined")
            local curBad = (m.deliveryState == "off" or m.deliveryState == "declined")
            if prevBad and not curBad then
                out[dupIdx] = m
            elseif (not prev.targetChar or prev.targetChar == "") and m.targetChar and m.targetChar ~= "" then
                prev.targetChar = m.targetChar
                prev.targetClass = m.targetClass or prev.targetClass
                prev.targetFaction = m.targetFaction or prev.targetFaction
            end
        else
            out[#out + 1] = m
        end
    end
    local maxKeep = math.max(MAX_THREAD_LINES, GetChatHistoryLimit(), Chat:GetGeneralHistoryLimit())
    while #out > maxKeep do
        table.remove(out, 1)
    end
    return out
end

local function FindLinkedDirectThread(parsed, bnetAccountID)
    local monoNow = GetTime and GetTime() or 0
    if parsed and Chat.lastManualWhisperSend and (monoNow - (Chat.lastManualWhisperSend.sentAt or 0)) <= 8.0 then
        local rec = Chat.lastManualWhisperSend
        local recThread = rec.threadKey and Chat.threads[rec.threadKey]
        if recThread and (recThread.kind == "WHISPER" or recThread.kind == "BN_WHISPER") then
            if rec.lookupKey and rec.lookupKey == parsed.lookupKey then
                return recThread
            end
            if (not parsed.surname) and rec.targetDisplay and parsed.firstName then
                local _, rFirst = Compat.ParseCharacterFields(rec.targetDisplay)
                if rFirst and rFirst:lower() == parsed.firstName:lower() then
                    return recThread
                end
            end
        end
    end

    if bnetAccountID then
        local firstMatch = Chat.threads["bn:" .. tostring(bnetAccountID)]
        for _, t in pairs(Chat.threads) do
            if type(t) == "table" and t.bnetAccountID == bnetAccountID and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
                if t.kind == "WHISPER" then
                    return t
                elseif not firstMatch then
                    firstMatch = t
                end
            end
        end
        if firstMatch then return firstMatch end
    end

    if parsed and parsed.lookupKey then
        local wThread = Chat.threads["w:" .. parsed.lookupKey]
        if wThread then return wThread end

        local firstLow = parsed.firstName and parsed.firstName:lower()
        if (not parsed.surname) and firstLow and Chat.knownFullByFirst then
            local kf = Chat.knownFullByFirst[firstLow]
            if type(kf) == "table" and kf.lookupKey then
                local promo = Chat.threads["w:" .. kf.lookupKey]
                if promo then return promo end
            end
        end

        local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(parsed.lookupKey)
        if bInfo then
            local accId = bInfo.bnetAccountID
            if accId then
                local accMatch
                for _, t in pairs(Chat.threads) do
                    if type(t) == "table" and t.bnetAccountID == accId and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
                        if t.kind == "WHISPER" then
                            return t
                        elseif not accMatch then
                            accMatch = t
                        end
                    end
                end
                if accMatch then return accMatch end
            end
            if type(bInfo.otherChars) == "table" then
                for _, otherDisp in ipairs(bInfo.otherChars) do
                    local okLk = Compat.ParseCharacterFields(otherDisp)
                    if okLk and Chat.threads["w:" .. okLk] then
                        return Chat.threads["w:" .. okLk]
                    end
                end
            end
        end

        if Store and Store.GetAllLinkedCharacters then
            local ownMeta = Store.GetSocialMeta and Store:GetSocialMeta(parsed.lookupKey)
            if ownMeta and type(ownMeta.mainName) == "string" and ownMeta.mainName ~= "" then
                local mLk = Compat.ParseCharacterFields(ownMeta.mainName)
                if mLk and Chat.threads["w:" .. mLk] then
                    return Chat.threads["w:" .. mLk]
                end
            end
            local alts = Store:GetAllLinkedCharacters(parsed.lookupKey)
            if type(alts) == "table" then
                for _, alt in ipairs(alts) do
                    if alt and alt.lookupKey and Chat.threads["w:" .. alt.lookupKey] then
                        return Chat.threads["w:" .. alt.lookupKey]
                    end
                end
            end
        end

        local firstCount, firstThread = 0, nil
        local unreadFirstCount, unreadFirstThread = 0, nil
        for _, t in pairs(Chat.threads) do
            if type(t) == "table" and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
                if bnetAccountID and t.bnetAccountID == bnetAccountID then
                    return t
                end
                local candName = t.targetName or (t.kind == "WHISPER" and t.title) or nil
                if candName and not candName:find("#", 1, true) then
                    local tLk, tFirst, _, tSurname = Compat.ParseCharacterFields(candName)
                    if tLk == parsed.lookupKey then
                        return t
                    end
                    if (not parsed.surname or not tSurname) and firstLow and tFirst and tFirst:lower() == firstLow then
                        firstCount = firstCount + 1
                        firstThread = t
                        if (t.unread or 0) > 0 then
                            unreadFirstCount = unreadFirstCount + 1
                            unreadFirstThread = t
                        end
                    end
                end
            end
        end
        if firstCount == 1 and firstThread then
            return firstThread
        elseif unreadFirstCount == 1 and unreadFirstThread then
            return unreadFirstThread
        end
    end
    return nil
end

local function MergeDirectThreadInto(canonThread, oldThread)
    if not (canonThread and oldThread and oldThread ~= canonThread) then return false end
    local oldKey = oldThread.key
    if not oldKey or oldKey == canonThread.key then return false end
    if canonThread._hydrated == false then Chat:EnsureThreadHydrated(canonThread) end
    if oldThread._hydrated == false then Chat:EnsureThreadHydrated(oldThread) end

    local merged = {}
    for _, m in ipairs(canonThread.messages or {}) do
        merged[#merged + 1] = m
    end
    for _, m in ipairs(oldThread.messages or {}) do
        merged[#merged + 1] = m
    end
    canonThread.messages = DeduplicateAndSortMessages(merged, true)
    canonThread.unread = (canonThread.unread or 0) + (oldThread.unread or 0)
    canonThread.lastAt = math.max(canonThread.lastAt or 0, oldThread.lastAt or 0)
    if not canonThread.bnetAccountID and oldThread.bnetAccountID then
        canonThread.bnetAccountID = oldThread.bnetAccountID
    end
    if not canonThread.bnetName and oldThread.bnetName then
        canonThread.bnetName = oldThread.bnetName
    end
    if not canonThread.classFile and oldThread.classFile then
        canonThread.classFile = oldThread.classFile
    end
    if not canonThread.faction and oldThread.faction then
        canonThread.faction = oldThread.faction
    end
    if (not canonThread.targetName or not canonThread.targetName:find("%s")) and oldThread.targetName and oldThread.targetName ~= "" then
        canonThread.targetName = oldThread.targetName
        canonThread._targetParsed = nil
        canonThread._targetParsedRaw = nil
    end

    Chat.threads[oldKey] = nil
    if Chat.activeThreadKey == oldKey then
        Chat.activeThreadKey = canonThread.key
    end

    local hist = GetHistoryScopeTable()
    if hist and hist[oldKey] then
        hist[oldKey] = nil
    end
    if canonThread.key:sub(1, 2) == "w:" and canonThread.kind == "WHISPER" then
        RewriteThreadHistory(canonThread)
    end

    local muted = ns.db and ns.db.settings and ns.db.settings.chatMutedThreads
    if type(muted) == "table" and muted[oldKey] then
        if canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionMutedThreads = Chat.sessionMutedThreads or {}
            Chat.sessionMutedThreads[canonThread.key] = true
        else
            muted[canonThread.key] = true
        end
        muted[oldKey] = nil
    end
    if Chat.sessionMutedThreads and Chat.sessionMutedThreads[oldKey] then
        if canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionMutedThreads[canonThread.key] = true
        elseif type(muted) == "table" then
            muted[canonThread.key] = true
        end
        Chat.sessionMutedThreads[oldKey] = nil
    end
    local rules = ns.db and ns.db.settings and ns.db.settings.chatMutedThreadRules
    if type(rules) == "table" and rules[oldKey] then
        if canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionMutedThreadRules = Chat.sessionMutedThreadRules or {}
            Chat.sessionMutedThreadRules[canonThread.key] = rules[oldKey]
        else
            rules[canonThread.key] = rules[oldKey]
        end
        rules[oldKey] = nil
    end
    if Chat.sessionMutedThreadRules and Chat.sessionMutedThreadRules[oldKey] then
        if canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionMutedThreadRules[canonThread.key] = Chat.sessionMutedThreadRules[oldKey]
        elseif type(rules) == "table" then
            rules[canonThread.key] = Chat.sessionMutedThreadRules[oldKey]
        end
        Chat.sessionMutedThreadRules[oldKey] = nil
    end
    if ns.charDb and type(ns.charDb.pinnedChatThreads) == "table" and ns.charDb.pinnedChatThreads[oldKey] then
        if canonThread.key:sub(1, 2) == "w:" then
            ns.charDb.pinnedChatThreads[canonThread.key] = true
        elseif canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionPinnedThreads = Chat.sessionPinnedThreads or {}
            Chat.sessionPinnedThreads[canonThread.key] = true
        end
        ns.charDb.pinnedChatThreads[oldKey] = nil
    end
    if Chat.sessionPinnedThreads and Chat.sessionPinnedThreads[oldKey] then
        if canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionPinnedThreads[canonThread.key] = true
        elseif ns.charDb and canonThread.key:sub(1, 2) == "w:" then
            ns.charDb.pinnedChatThreads = ns.charDb.pinnedChatThreads or {}
            ns.charDb.pinnedChatThreads[canonThread.key] = true
        end
        Chat.sessionPinnedThreads[oldKey] = nil
    end
    if ns.charDb and type(ns.charDb.quickReplyPinnedThreads) == "table" and ns.charDb.quickReplyPinnedThreads[oldKey] then
        if canonThread.key:sub(1, 2) == "w:" then
            ns.charDb.quickReplyPinnedThreads[canonThread.key] = true
        elseif canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionQuickReplyPinned = Chat.sessionQuickReplyPinned or {}
            Chat.sessionQuickReplyPinned[canonThread.key] = true
        end
        ns.charDb.quickReplyPinnedThreads[oldKey] = nil
    end
    if Chat.sessionQuickReplyPinned and Chat.sessionQuickReplyPinned[oldKey] then
        if canonThread.key:sub(1, 3) == "bn:" then
            Chat.sessionQuickReplyPinned[canonThread.key] = true
        elseif ns.charDb and canonThread.key:sub(1, 2) == "w:" then
            ns.charDb.quickReplyPinnedThreads = ns.charDb.quickReplyPinnedThreads or {}
            ns.charDb.quickReplyPinnedThreads[canonThread.key] = true
        end
        Chat.sessionQuickReplyPinned[oldKey] = nil
    end
    if Chat._runtimePinnedOrder then
        for i = 1, #Chat._runtimePinnedOrder do
            if Chat._runtimePinnedOrder[i] == oldKey then
                Chat._runtimePinnedOrder[i] = canonThread.key
            end
        end
        SyncPinnedOrder(Chat)
    elseif ns.charDb and type(ns.charDb.pinnedChatOrder) == "table" then
        for i = 1, #ns.charDb.pinnedChatOrder do
            if ns.charDb.pinnedChatOrder[i] == oldKey and canonThread.key:sub(1, 2) == "w:" then
                ns.charDb.pinnedChatOrder[i] = canonThread.key
            end
        end
    end

    EnrichLoadedThreadMessages(canonThread, canonThread.targetName or canonThread.title)
    if canonThread.key:sub(1, 2) == "w:" and canonThread.kind == "WHISPER" then
        RewriteThreadHistory(canonThread)
    end
    Chat:InvalidateUnreadCache()
    Chat:BumpPeerStateGen()
    return true
end

local function MergeSingleFirstThreadInto(canonThread, firstName)
    if not (canonThread and firstName and firstName ~= "") then return end
    local oldKey = "w:" .. firstName:lower()
    if oldKey == canonThread.key then return end
    local oldThread = Chat.threads[oldKey]
    if oldThread and oldThread ~= canonThread and oldThread.kind == "WHISPER" then
        MergeDirectThreadInto(canonThread, oldThread)
    end
end

-- Disjoint-Set (Union-Find) consolidation: guarantees exactly 1 unified thread per human player across alts/BNet/key formats.
function Chat:ConsolidatePlayerThreads(silent)
    local directKeys = {}
    for k, t in pairs(self.threads) do
        if type(k) == "string" and type(t) == "table" and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
            directKeys[#directKeys + 1] = k
        end
    end
    if #directKeys == 0 then return false end

    local parent = {}
    local function ufFind(x)
        local root = x
        while parent[root] ~= root do
            root = parent[root]
        end
        while parent[x] ~= root do
            local nxt = parent[x]
            parent[x] = root
            x = nxt
        end
        return root
    end
    local function ufUnion(a, b)
        local ra, rb = ufFind(a), ufFind(b)
        if ra ~= rb then
            parent[rb] = ra
        end
    end

    local tagOwner = {}
    local function bindTag(key, tag)
        if not tag or tag == "" then return end
        local owner = tagOwner[tag]
        if owner then
            ufUnion(owner, key)
        else
            tagOwner[tag] = key
        end
    end

    local metaByKey = {}
    for _, k in ipairs(directKeys) do
        parent[k] = k
        local t = self.threads[k]
        local candName = t.targetName or (t.kind == "WHISPER" and t.title) or (k:sub(1, 2) == "w:" and k:sub(3)) or nil
        if candName and candName:find("#", 1, true) then candName = nil end
        local p = candName and Compat.ParseCharacterName(candName) or nil
        if p and (not p.surname or p.surname == "") then
            local resolved = ResolveChatSenderDisplay(p.displayName, nil, nil)
            local rp = resolved and Compat.ParseCharacterName(resolved)
            if rp and rp.surname and rp.surname ~= "" then
                p = rp
                if t.kind == "WHISPER" then
                    t.targetName = rp.displayName
                    if not t.title or not t.title:find("%s") then
                        t.title = rp.displayName
                    end
                end
            end
        end
        local keyParsed = (k:sub(1, 2) == "w:") and Compat.ParseCharacterName(k:sub(3)) or nil
        if (not p or not p.surname) and keyParsed and keyParsed.surname then
            p = keyParsed
        end

        local lk = p and p.lookupKey or nil
        local effBnetId = t.bnetAccountID
        if (not effBnetId) and lk and ns.Social and ns.Social.GetBNetLinkInfo then
            local bi = ns.Social:GetBNetLinkInfo(lk)
            if bi and bi.bnetAccountID then
                effBnetId = bi.bnetAccountID
                t.bnetAccountID = effBnetId
                t.bnetName = t.bnetName or bi.bnetName
            end
        end
        if (not effBnetId) and lk and self.FindBNetAccountIdByLookupKey then
            effBnetId = self:FindBNetAccountIdByLookupKey(lk)
            if effBnetId then t.bnetAccountID = effBnetId end
        end

        metaByKey[k] = {
            parsed = p,
            lookupKey = lk,
            firstLow = p and p.firstName and p.firstName:lower() or nil,
            hasSurname = (p and p.surname ~= nil and p.surname ~= "") == true,
            bnetId = effBnetId,
        }

        if lk then bindTag(k, "lk:" .. lk) end
        if keyParsed and keyParsed.lookupKey and keyParsed.lookupKey ~= lk then
            bindTag(k, "lk:" .. keyParsed.lookupKey)
        end
        if t.title and t.title ~= "" and not t.title:find("#", 1, true) and t.kind == "WHISPER" then
            local tLk = Compat.ParseCharacterFields(t.title)
            if tLk and tLk ~= lk then
                bindTag(k, "lk:" .. tLk)
            end
        end
        if effBnetId then
            bindTag(k, "bn:" .. tostring(effBnetId))
        end
        if lk and Store and Store.GetAllLinkedCharacters then
            local ownMeta = Store.GetSocialMeta and Store:GetSocialMeta(lk)
            if ownMeta and type(ownMeta.mainName) == "string" and ownMeta.mainName ~= "" then
                local mLk = Compat.ParseCharacterFields(ownMeta.mainName)
                if mLk then
                    metaByKey[k].mainLookupKey = mLk
                    local mp = Compat.ParseCharacterName(ownMeta.mainName)
                    metaByKey[k].mainDisplayName = mp and mp.displayName or ownMeta.mainName
                    bindTag(k, "lk:" .. mLk)
                end
            end
            for _, alt in ipairs(Store:GetAllLinkedCharacters(lk)) do
                if alt and alt.lookupKey then
                    bindTag(k, "lk:" .. alt.lookupKey)
                end
            end
        end
    end

    -- Unambiguous firstName -> composite cluster promotion (fails closed when homonyms exist).
    local clusters = {}
    for _, k in ipairs(directKeys) do
        local root = ufFind(k)
        clusters[root] = clusters[root] or {}
        clusters[root][#clusters[root] + 1] = k
    end

    local compositeByFirst = {}
    local bareClusters = {}
    for root, keys in pairs(clusters) do
        local hasSur, hasBn = false, false
        local firstLow
        for _, k in ipairs(keys) do
            local m = metaByKey[k]
            if m.hasSurname then hasSur = true end
            if m.bnetId then hasBn = true end
            if m.firstLow then firstLow = firstLow or m.firstLow end
        end
        if hasSur and firstLow then
            compositeByFirst[firstLow] = compositeByFirst[firstLow] or {}
            compositeByFirst[firstLow][#compositeByFirst[firstLow] + 1] = root
        elseif (not hasSur) and (not hasBn) and firstLow then
            bareClusters[#bareClusters + 1] = { root = root, firstLow = firstLow }
        end
    end
    for _, bc in ipairs(bareClusters) do
        local matches = compositeByFirst[bc.firstLow]
        if matches and #matches == 1 then
            ufUnion(matches[1], bc.root)
        end
    end

    -- Rebuild final connected components and canonicalize each cluster into 1 thread.
    clusters = {}
    for _, k in ipairs(directKeys) do
        local root = ufFind(k)
        clusters[root] = clusters[root] or {}
        clusters[root][#clusters[root] + 1] = k
    end

    local anyChanged = false
    for _, keys in pairs(clusters) do
        local hasWhisper = false
        local mainLk, mainDisp
        local bestChar, bestCharScore = nil, -1
        local bnetId, bnetName

        for _, k in ipairs(keys) do
            local t = self.threads[k]
            local m = metaByKey[k]
            if t.kind == "WHISPER" then hasWhisper = true end
            if not bnetId and m.bnetId then bnetId = m.bnetId end
            if not bnetName and t.bnetName then bnetName = t.bnetName end
            if not mainLk and m.mainLookupKey then
                mainLk, mainDisp = m.mainLookupKey, m.mainDisplayName
            end
            if m.parsed and m.lookupKey then
                local sc = (m.hasSurname and 1000 or 0)
                    + (t.kind == "WHISPER" and 200 or 0)
                    + math.min(100, #(t.messages or {}))
                if sc > bestCharScore then
                    bestCharScore = sc
                    bestChar = m.parsed
                end
            end
        end

        local canonKey, canonKind, canonTitle, canonTarget
        local bInfo = bestChar and bestChar.lookupKey and ns.Social and ns.Social.GetBNetLinkInfo
            and ns.Social:GetBNetLinkInfo(bestChar.lookupKey) or nil
        local sameFactionOk = (not bInfo) or (bInfo.sameFaction ~= false)

        if hasWhisper and (mainLk or bestChar) then
            canonKind = "WHISPER"
            canonKey = "w:" .. (mainLk or bestChar.lookupKey)
            canonTarget = mainDisp or bestChar.displayName
            canonTitle = canonTarget
        elseif bestChar and bestChar.surname and sameFactionOk and not hasWhisper and self.threads["w:" .. bestChar.lookupKey] then
            canonKind = "WHISPER"
            canonKey = "w:" .. bestChar.lookupKey
            canonTarget = bestChar.displayName
            canonTitle = canonTarget
        elseif (not hasWhisper) and bnetId and not mainLk and (not sameFactionOk or not bestChar or not bestChar.surname) then
            canonKind = "BN_WHISPER"
            canonKey = "bn:" .. tostring(bnetId)
            canonTarget = bestChar and bestChar.displayName or nil
            canonTitle = bnetName or canonTarget or canonKey
        elseif bestChar and sameFactionOk and bestChar.surname then
            canonKind = "WHISPER"
            canonKey = "w:" .. (mainLk or bestChar.lookupKey)
            canonTarget = mainDisp or bestChar.displayName
            canonTitle = canonTarget
        elseif #keys > 0 then
            table.sort(keys, function(a, b)
                local ta, tb = self.threads[a], self.threads[b]
                if (ta.kind == "WHISPER") ~= (tb.kind == "WHISPER") then
                    return ta.kind == "WHISPER"
                end
                return (#(ta.messages or {}) > #(tb.messages or {}))
            end)
            canonKey = keys[1]
            local ct = self.threads[canonKey]
            canonKind = ct.kind
            canonTarget = ct.targetName
            canonTitle = ct.title
        end

        if canonKey then
            local canonThread = EnsureThread(canonKey, canonKind, canonTitle, {
                targetName = canonTarget,
                bnetAccountID = bnetId,
                bnetName = bnetName,
            })
            if canonThread then
                local clusterChanged = false
                if #keys > 1 or keys[1] ~= canonKey then
                    for _, okKey in ipairs(keys) do
                        if okKey ~= canonKey and self.threads[okKey] then
                            if MergeDirectThreadInto(canonThread, self.threads[okKey]) then
                                anyChanged = true
                                clusterChanged = true
                            end
                        end
                    end
                end
                local prevCount = #(canonThread.messages or {})
                local cleaned = DeduplicateAndSortMessages(canonThread.messages, #keys > 1)
                if #cleaned ~= prevCount then
                    anyChanged = true
                    clusterChanged = true
                end
                canonThread.messages = cleaned
                EnrichLoadedThreadMessages(canonThread, canonThread.targetName or canonThread.title)
                if (clusterChanged or silent) and canonThread.key:sub(1, 2) == "w:" and canonThread.kind == "WHISPER" then
                    RewriteThreadHistory(canonThread)
                end
            end
        end
    end

    if anyChanged then
        self:InvalidateUnreadCache()
        self:BumpPeerStateGen()
        if not silent then
            ns:Emit("CHAT_UPDATED")
        end
    end
    return anyChanged
end

function Chat:ReconcileSingleFirstThreads()
    return self:ConsolidatePlayerThreads(false)
end

local bnetCache = {
    at = -999,
    byId = {},
    byGameId = {},
    byGuid = {},
    byLookup = {},
    anyById = {},
    anyByGameId = {},
}

local function WipeTable(t)
    if wipe then
        wipe(t)
    else
        for k in pairs(t) do t[k] = nil end
    end
end

function Chat:InvalidateBNetCache()
    bnetCache.at = -999
    self:BumpPeerStateGen()
end

local function EnsureBNetLookupCache()
    local monoNow = GetTime and GetTime() or 0
    if (monoNow - (bnetCache.at or -999)) < BNET_CACHE_TTL then
        return bnetCache
    end
    bnetCache.at = monoNow
    WipeTable(bnetCache.byId)
    WipeTable(bnetCache.byGameId)
    WipeTable(bnetCache.byGuid)
    WipeTable(bnetCache.byLookup)
    WipeTable(bnetCache.anyById)
    WipeTable(bnetCache.anyByGameId)

    if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
        return bnetCache
    end

    local wowProg = BNET_CLIENT_WOW or "WoW"
    local num = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    local hasNumGameAcc = (C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) ~= nil

    local function processGameAcc(accId, accName, gi)
        if type(gi) ~= "table" then return end
        local gId = Safe.Number(gi.gameAccountID)
        local gGuid = Safe.String(gi.playerGuid)
        local charName = Safe.String(gi.characterName)
        local realmName = Safe.String(gi.realmName)
        local charParsed = charName and Compat.ParseCharacterName(charName)
        if charParsed and not charParsed.surname and Compat.LookupForeverFullName then
            local fullRec = Compat.LookupForeverFullName(gGuid, charParsed.firstName, false)
            if fullRec and fullRec.fullName then
                charParsed = Compat.ParseCharacterName(fullRec.fullName) or charParsed
            end
        end
        local fullChar = charParsed and charParsed.displayName or charName
        if fullChar and realmName and realmName ~= "" and not (Compat.IsForeverShardLabel and Compat.IsForeverShardLabel(realmName)) then
            if not fullChar:find("-", 1, true) then
                fullChar = fullChar .. "-" .. realmName
            end
        end

        local isOnline = Safe.Value(gi.isOnline) == true
        local isWoW = Safe.String(gi.clientProgram) == wowProg
        local charLevel = ValidLevel(Safe.Number(gi.characterLevel))
        local score = (isOnline and isWoW) and ((not WOW_PROJECT_ID or Safe.Value(gi.wowProjectID) == WOW_PROJECT_ID) and 100 or 50) or 0

        local rec = {
            gId = gId,
            accId = accId,
            accName = accName,
            fullChar = fullChar,
            lookupKey = charParsed and charParsed.lookupKey or nil,
            charLevel = charLevel,
            score = score,
            isOnline = isOnline,
        }

        if gId and (not bnetCache.anyByGameId[gId] or (isOnline and not bnetCache.anyByGameId[gId].isOnline)) then
            bnetCache.anyByGameId[gId] = rec
        end
        if accId and (not bnetCache.anyById[accId] or (isOnline and not bnetCache.anyById[accId].isOnline)) then
            bnetCache.anyById[accId] = rec
        end

        if isOnline and isWoW then
            if gId then
                local prevG = bnetCache.byGameId[gId]
                if not prevG or score > prevG.score then
                    bnetCache.byGameId[gId] = rec
                end
                bnetCache.anyByGameId[gId] = rec
            end
            if accId then
                local prevA = bnetCache.byId[accId]
                if not prevA or score > prevA.score then
                    bnetCache.byId[accId] = rec
                end
                bnetCache.anyById[accId] = rec
            end
            if gId then
                if gGuid and not bnetCache.byGuid[gGuid] then
                    bnetCache.byGuid[gGuid] = rec
                end
                if charParsed and charParsed.lookupKey and not bnetCache.byLookup[charParsed.lookupKey] then
                    bnetCache.byLookup[charParsed.lookupKey] = rec
                end
            end
        end
    end

    for i = 1, num do
        local acc = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        if acc then
            local accId = Safe.Number(acc.bnetAccountID)
            local accName = Safe.String(acc.accountName)
            local anyGi = false
            if hasNumGameAcc then
                local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, i)) or 0
                for g = 1, gCount do
                    local gi = Safe.Call(C_BattleNet.GetFriendGameAccountInfo, i, g)
                    if type(gi) == "table" then
                        anyGi = true
                        processGameAcc(accId, accName, gi)
                    end
                end
            end
            if not anyGi and type(acc.gameAccountInfo) == "table" then
                processGameAcc(accId, accName, acc.gameAccountInfo)
            end
        end
    end
    return bnetCache
end

local function FindBNetWoWGameAccount(idOrGameId)
    if not idOrGameId then return nil end
    local cache = EnsureBNetLookupCache()
    local rec = cache.byGameId[idOrGameId] or cache.byId[idOrGameId]
    if rec then
        return rec.gId, rec.fullChar, rec.accName, rec.accId
    end
    return nil
end

-- Locate an online Battle.net WoW friend matching an exact GUID or full Forever character lookupKey.
local function FindBNetWoWGameAccountByChar(parsed, guidHint)
    if not parsed and not guidHint then return nil end
    local cache = EnsureBNetLookupCache()
    local rec = (guidHint and cache.byGuid[guidHint]) or (parsed and parsed.lookupKey and cache.byLookup[parsed.lookupKey])
    if rec then
        return rec.gId, rec.fullChar, rec.accName, rec.accId
    end
    return nil
end

local function FindBNetAccountIdByLookupKey(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then return nil end
    local cache = EnsureBNetLookupCache()
    local rec = cache.byLookup[lookupKey]
    return rec and rec.accId or nil
end

function Chat:FindBNetAccountIdByLookupKey(lookupKey)
    return FindBNetAccountIdByLookupKey(lookupKey)
end

function Chat:EnsureBNetWhisperThreadByTarget(rawTarget)
    local clean = Safe.String(rawTarget)
    if not clean then return nil end
    clean = clean:gsub("[%c]", ""):gsub("^%s*(.-)%s*$", "%1")
    if clean == "" then return nil end
    local wantLow = clean:lower()
    if type(self.threads) == "table" then
        for tKey, tr in pairs(self.threads) do
            if type(tr) == "table" and tr.kind == "BN_WHISPER" then
                local t1 = type(tr.title) == "string" and tr.title:lower() or ""
                local t2 = type(tr.targetName) == "string" and tr.targetName:lower() or ""
                local t3 = type(tr.bnetName) == "string" and tr.bnetName:lower() or ""
                if t1 == wantLow or t2 == wantLow or t3 == wantLow then
                    return tKey
                end
            end
        end
    end
    local cache = EnsureBNetLookupCache()
    local targetLk = (Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(clean)) or nil
    local matchedRec = nil
    for _, rec in pairs(cache.anyById) do
        if type(rec) == "table" then
            local aName = type(rec.accName) == "string" and rec.accName:lower() or ""
            local fChar = type(rec.fullChar) == "string" and rec.fullChar:lower() or ""
            if aName == wantLow
                or tostring(rec.accId or "") == clean
                or (fChar ~= "" and fChar == wantLow)
                or (targetLk and rec.lookupKey and rec.lookupKey == targetLk)
            then
                matchedRec = rec
                break
            end
        end
    end
    if matchedRec and matchedRec.accId and self.OpenDirectConversation then
        return self:OpenDirectConversation({
            bnetAccountID = matchedRec.accId,
            bnetName = matchedRec.accName,
            targetName = matchedRec.fullChar,
            autoProbe = false,
        })
    end
    return nil
end

function Chat:GetBNetCachedLevel(lookupKey, guid, bnetAccountID)
    local cache = EnsureBNetLookupCache()
    local rec = (guid and cache.byGuid[guid])
        or (lookupKey and cache.byLookup[lookupKey])
    if rec and rec.charLevel and rec.charLevel > 0 then
        return rec.charLevel
    end
    if bnetAccountID then
        local accRec = cache.byId[bnetAccountID] or cache.anyById[bnetAccountID] or cache.byGameId[bnetAccountID] or cache.anyByGameId[bnetAccountID]
        if accRec and accRec.charLevel and accRec.charLevel > 0 then
            if (not lookupKey or lookupKey == "") or (accRec.lookupKey and accRec.lookupKey == lookupKey) then
                return accRec.charLevel
            end
        end
    end
    return nil
end

local function ResolveBNetSender(bnGameAccId)
    if not bnGameAccId then return nil end
    local cache = EnsureBNetLookupCache()
    local rec = cache.anyByGameId[bnGameAccId] or cache.anyById[bnGameAccId]
    if rec then
        return rec.accId, rec.accName, rec.fullChar
    end
    return nil
end

local function IsBNetAccountOnline(idOrGameId)
    if not idOrGameId then return false end
    local cache = EnsureBNetLookupCache()
    local rec = cache.anyById[idOrGameId] or cache.anyByGameId[idOrGameId]
    return rec and rec.isOnline == true or false
end

local function ResolveRuntimeRoomBNetTargets(roomId, room, meKey)
    local bnetTargets = {}
    local seenGameId = {}
    local memberHasBNet = {}
    local memTargets = Chat.roomBNetTargets and Chat.roomBNetTargets[roomId]
    if type(memTargets) == "table" then
        local staleIds
        for bId, memberDisp in pairs(memTargets) do
            local keep = (bId ~= nil)
            local mLk
            if keep and type(memberDisp) == "string" and memberDisp ~= "" and memberDisp ~= "Friend" and memberDisp ~= "Host" then
                mLk = Compat.ParseCharacterFields and Compat.ParseCharacterFields(memberDisp)
                if mLk and (mLk == meKey or not (room and room.members and room.members[mLk])) then
                    keep = false
                end
            elseif keep then
                local _, _, fullChar = ResolveBNetSender(bId)
                local fLk = fullChar and Compat.ParseCharacterFields and Compat.ParseCharacterFields(fullChar)
                if fLk then
                    if fLk == meKey or not (room and room.members and room.members[fLk]) then
                        keep = false
                    else
                        mLk = fLk
                    end
                end
            end
            if keep then
                bnetTargets[#bnetTargets + 1] = bId
                seenGameId[bId] = true
                if mLk then
                    memberHasBNet[mLk] = true
                end
            else
                staleIds = staleIds or {}
                staleIds[#staleIds + 1] = bId
            end
        end
        if staleIds then
            for i = 1, #staleIds do
                memTargets[staleIds[i]] = nil
            end
            if next(memTargets) == nil and Chat.roomBNetTargets then
                Chat.roomBNetTargets[roomId] = nil
            end
        end
    end
    for key, targetName in pairs((room and room.members) or {}) do
        if key ~= meKey and type(targetName) == "string" and targetName ~= "" then
            local parsed = Compat.ParseCharacterName(targetName)
            local sr = Store and Store.socialByLookup and Store.socialByLookup[key]
            local guidHint = sr and sr.guid or nil
            local gId = parsed and select(1, FindBNetWoWGameAccountByChar(parsed, guidHint)) or nil
            if not gId and ns.Social and ns.Social.GetBNetLinkInfo then
                local bInfo = ns.Social:GetBNetLinkInfo(key)
                if bInfo and bInfo.bnetAccountID then
                    gId = select(1, FindBNetWoWGameAccount(bInfo.bnetAccountID))
                end
            end
            if gId then
                memberHasBNet[key] = true
                if not seenGameId[gId] then
                    seenGameId[gId] = true
                    bnetTargets[#bnetTargets + 1] = gId
                    Chat.roomBNetTargets[roomId] = Chat.roomBNetTargets[roomId] or {}
                    Chat.roomBNetTargets[roomId][gId] = targetName
                end
            end
        end
    end
    return bnetTargets, memberHasBNet
end

local function RemoveRoomMemberFromState(roomId, room, memParsed, parsedSender, bnGameAccId)
    if not (roomId and room) then return end
    local removedKeys = {}
    local function dropMemberKey(lk)
        if lk and lk ~= "" and room.members and room.members[lk] ~= nil then
            room.members[lk] = nil
            removedKeys[lk] = true
        elseif lk and lk ~= "" then
            removedKeys[lk] = true
        end
    end

    if memParsed and memParsed.lookupKey then
        dropMemberKey(memParsed.lookupKey)
    end
    if parsedSender and parsedSender.lookupKey then
        dropMemberKey(parsedSender.lookupKey)
    end

    local rt = Chat.roomBNetTargets and Chat.roomBNetTargets[roomId]
    if type(rt) == "table" and bnGameAccId and rt[bnGameAccId] ~= nil then
        local oldDisp = rt[bnGameAccId]
        rt[bnGameAccId] = nil
        if type(oldDisp) == "string" and oldDisp ~= "" and oldDisp ~= "Friend" and oldDisp ~= "Host" and Compat.ParseCharacterFields then
            local oldLk = Compat.ParseCharacterFields(oldDisp)
            if oldLk then
                dropMemberKey(oldLk)
            end
        end
    end

    -- Handle bare FirstName replies on Forever when the room holds a single "FirstName Surname" entry.
    if memParsed and (not memParsed.surname) and memParsed.firstName and type(room.members) == "table" and not removedKeys[memParsed.lookupKey] then
        local wantFirst = memParsed.firstName:lower()
        local matchKey, matchCount = nil, 0
        for mk, mDisp in pairs(room.members) do
            local _, mFirst = Compat.ParseCharacterFields(mDisp or mk)
            if mFirst and mFirst:lower() == wantFirst then
                matchKey = mk
                matchCount = matchCount + 1
                if matchCount > 1 then break end
            end
        end
        if matchCount == 1 and matchKey then
            dropMemberKey(matchKey)
        end
    end

    if type(rt) == "table" then
        local staleIds
        for bId, memberDisp in pairs(rt) do
            local mLk = (type(memberDisp) == "string" and memberDisp ~= "" and memberDisp ~= "Friend" and memberDisp ~= "Host" and Compat.ParseCharacterFields)
                and Compat.ParseCharacterFields(memberDisp)
                or nil
            if mLk and (removedKeys[mLk] or not (room.members and room.members[mLk])) then
                staleIds = staleIds or {}
                staleIds[#staleIds + 1] = bId
            end
        end
        if staleIds then
            for i = 1, #staleIds do
                rt[staleIds[i]] = nil
            end
        end
        if next(rt) == nil then
            Chat.roomBNetTargets[roomId] = nil
        end
    end
end

function Chat:EnsurePersonalNotesThread()
    local t = EnsureThread("notes:self", "NOTES", L["Personal Notes (You)"], {})
    return t
end

function Chat:SavePersonalNote(rawText)
    local text = type(rawText) == "string" and rawText or ""
    text = text:gsub("|Haddon:[^|]*|h.-|h", ""):gsub("[%c]", " "):gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    if text == "" then
        return false
    end
    if #text > 320 then
        text = text:sub(1, 320)
    end
    local cleanText = text
    local t = self:EnsurePersonalNotesThread()
    local meDisplay = GetMyInfo()
    local _, myClass = Safe.Call(UnitClass, "player")
    local noteId = tostring(time()) .. "_" .. tostring(math.random(1000, 9999))
    AppendMessage(t, meDisplay, cleanText, false, Safe.String(myClass), false, true, {
        noteId = noteId,
    })
    return true
end

function Chat:DeletePersonalNote(noteId)
    if not noteId or noteId == "" then return false end
    local t = self.threads["notes:self"]
    if t and type(t.messages) == "table" then
        for i = #t.messages, 1, -1 do
            if t.messages[i] and t.messages[i].noteId == noteId then
                table.remove(t.messages, i)
            end
        end
        local last = t.messages[#t.messages]
        t.lastAt = (last and last.ts) or 0
    end
    local hist = GetHistoryScopeTable()
    local saved = hist and hist["notes:self"]
    if type(saved) == "table" and type(saved.lines) == "table" then
        for i = #saved.lines, 1, -1 do
            if saved.lines[i] and saved.lines[i].noteId == noteId then
                table.remove(saved.lines, i)
            end
        end
        local lastSaved = saved.lines[#saved.lines]
        saved.updatedAt = (lastSaved and lastSaved.ts) or 0
    end
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:EnsureWhisperThread(rawTarget, classFile)
    local parsed = Compat.ParseCharacterName(rawTarget)
    if not parsed then return nil end
    if Compat.IsMe and Compat.IsMe(parsed.displayName) then
        return self:EnsurePersonalNotesThread()
    end
    if not parsed.surname then
        local upDisp = ResolveChatSenderDisplay(parsed.displayName, nil, nil)
        local upParsed = upDisp and Compat.ParseCharacterName(upDisp)
        if upParsed and upParsed.surname and upParsed.surname ~= "" then
            parsed = upParsed
        end
    end
    local resolvedClass = classFile or LookupClassFromCache(parsed.lookupKey)
    local _, _, bnAccName, bnAccId = FindBNetWoWGameAccountByChar(parsed)
    local existing = FindLinkedDirectThread(parsed, bnAccId)
    local key = existing and existing.key or ("w:" .. parsed.lookupKey)
    local kind = existing and existing.kind or "WHISPER"
    local title = (existing and existing.title and existing.title ~= "" and existing.title) or parsed.displayName
    local targetForEnsure = parsed.displayName
    if existing and existing.targetName and existing.targetName ~= "" then
        local eLk, eFirst, _, eSur = Compat.ParseCharacterFields(existing.targetName)
        if eLk == parsed.lookupKey or (eFirst and parsed.firstName and eFirst:lower() == parsed.firstName:lower() and parsed.surname and not eSur) then
            targetForEnsure = parsed.displayName
        else
            targetForEnsure = existing.targetName
        end
    end
    local t = EnsureThread(key, kind, title, {
        targetName = targetForEnsure,
        bnetAccountID = bnAccId or (existing and existing.bnetAccountID),
        bnetName = bnAccName or (existing and existing.bnetName),
        classFile = resolvedClass or (existing and existing.classFile),
    })
    if t and parsed.surname and parsed.surname ~= "" and t.kind == "WHISPER" then
        MergeSingleFirstThreadInto(t, parsed.firstName)
    end
    ns:Emit("CHAT_UPDATED")
    return t
end

function Chat:ClearHistory(threadKey)
    local hist = GetHistoryScopeTable()
    if threadKey then
        local t = self.threads[threadKey]
        if t then
            t.messages = {}
            t.unread = 0
            t.hasMention = nil
            t.lastAt = 0
        end
        if hist then
            hist[threadKey] = nil
            if self:IsGuildHistoryKey(threadKey) then
                hist[self:GetGuildStorageKey(threadKey)] = nil
            end
        end
    else
        for key, t in pairs(self.threads) do
            if key ~= "notes:self" then
                t.messages = {}
                t.unread = 0
                t.hasMention = nil
                t.lastAt = 0
                if hist then hist[key] = nil end
            end
        end
        if hist then
            for hKey in pairs(hist) do
                if hKey ~= "notes:self" then
                    hist[hKey] = nil
                end
            end
        end
    end
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
end

function Chat:CanDeleteThread(threadKey)
    if not threadKey or threadKey == "notes:self" or threadKey == "mentions:radar" or STATIC_CHANNEL_ORDER[threadKey] then
        return false
    end
    return self.threads and self.threads[threadKey] ~= nil
end

function Chat:DeleteThread(threadKey)
    if not self:CanDeleteThread(threadKey) then
        return false
    end
    local t = self.threads[threadKey]
    if t and t.kind == "ROOM" and t.roomId then
        if self.LeaveRoom then
            self:LeaveRoom(t.roomId)
        end
    end
    self.threads[threadKey] = nil
    local hist = GetHistoryScopeTable()
    if hist then
        hist[threadKey] = nil
    end
    if self.SetThreadMuted then
        self:SetThreadMuted(threadKey, false)
    end
    if self.SetThreadPinned then
        self:SetThreadPinned(threadKey, false)
    end
    if self.pendingProbes then self.pendingProbes[threadKey] = nil end
    if self.pendingOfficialOpen then self.pendingOfficialOpen[threadKey] = nil end
    if self.probeSentAt then self.probeSentAt[threadKey] = nil end
    if self.probeFailures then self.probeFailures[threadKey] = nil end
    if self.activeThreadKey == threadKey then
        self.activeThreadKey = nil
    end
    self:InvalidateUnreadCache()
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
    return true
end

-- Shared combat/lockdown guard for outgoing SCentral1 addon packets.
-- Never reports "combat" unless InCombatLockdown/UnitAffectingCombat is actually active.
local function GuardAddonMessaging(printNotice)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if printNotice then ns:Print(L["In Combat"]) end
        return false, "combat"
    end
    if ns.Clan and ns.Clan.IsMessagingLocked then
        local locked, reason = ns.Clan:IsMessagingLocked()
        if locked then
            if printNotice then
                if reason == "combat" then
                    ns:Print(L["In Combat"])
                elseif reason == "lockdown" then
                    ns:Print(L["Addon messaging is paused by a game chat lockdown (encounter or Mythic+ restriction)."])
                else
                    ns:Print(L["Addon messaging channel is unavailable right now."])
                end
            end
            return false, reason or "locked"
        end
    end
    return true, nil
end

local function RecordResolvedWhisperTarget(lookupKey, rawSender)
    if type(lookupKey) ~= "string" or lookupKey == "" then return end
    local parsed = Compat.ParseCharacterName(rawSender)
    local clean = (parsed and parsed.displayName) or Compat.FormatForeverTarget(rawSender)
    if not clean or clean == "" then return end
    Chat.resolvedWhisperTargets = Chat.resolvedWhisperTargets or {}
    local existing = Chat.resolvedWhisperTargets[lookupKey]
    if type(existing) == "string" and existing:find(" ", 1, true) and parsed and not parsed.surname then
        return
    end
    local count = 0
    for _ in pairs(Chat.resolvedWhisperTargets) do
        count = count + 1
        if count >= 400 then
            wipe(Chat.resolvedWhisperTargets)
            break
        end
    end
    Chat.resolvedWhisperTargets[lookupKey] = clean
end

local function RecordThrottleStrike()
    if not ns.Clan then return end
    local monoNow = GetTime and GetTime() or 0
    ns.Clan.throttleStrike = (ns.Clan.throttleStrike or 0) + 1
    ns.Clan.throttledCount = (ns.Clan.throttledCount or 0) + 1
    ns.Clan.backoffUntil = monoNow + 12
    if ns.Clan.throttleStrike >= 3 then
        ns.Clan.isStoppedThisSession = true
    end
end

local function BuildOrderedWhisperCandidates(targetChar, candidateOffset, extraCandidates)
    local parsed = Compat.ParseCharacterName(targetChar)
    local wantSurname = parsed and parsed.surname ~= nil and parsed.surname ~= ""
    local ordered, seen = {}, {}
    local monoNow = GetTime and GetTime() or 0
    local rejected = Chat.rejectedWhisperTargets

    local function pushUnique(v)
        if type(v) ~= "string" or v == "" or seen[v] then return end
        if wantSurname and not v:find("[%s%-]") then return end
        seen[v] = true
        local exp = rejected and rejected[v]
        if exp and monoNow < exp then
            return
        end
        ordered[#ordered + 1] = v
    end

    local resolved = parsed and Chat.resolvedWhisperTargets and Chat.resolvedWhisperTargets[parsed.lookupKey]
    if resolved then
        local rParsed = Compat.ParseCharacterName(resolved)
        if rParsed and rParsed.displayName then
            pushUnique(rParsed.displayName)
        else
            pushUnique(resolved)
        end
    end

    local baseCandidates = Compat.BuildForeverTargetCandidates(targetChar)
    if type(extraCandidates) == "table" then
        for _, ec in ipairs(extraCandidates) do
            if type(ec) == "string" and ec ~= "" then
                for _, subCand in ipairs(Compat.BuildForeverTargetCandidates(ec)) do
                    baseCandidates[#baseCandidates + 1] = subCand
                end
            end
        end
    end
    if #baseCandidates == 0 then
        local cleanFallback = Compat.FormatForeverTarget(targetChar)
        if cleanFallback and cleanFallback ~= "" then
            baseCandidates = { cleanFallback }
        else
            baseCandidates = { targetChar }
        end
    end

    local off = tonumber(candidateOffset) or 0
    if off > 0 and #baseCandidates > 1 and not resolved then
        local startIdx = (off % #baseCandidates) + 1
        for i = startIdx, #baseCandidates do
            pushUnique(baseCandidates[i])
        end
        for i = 1, startIdx - 1 do
            pushUnique(baseCandidates[i])
        end
    else
        for _, cand in ipairs(baseCandidates) do
            pushUnique(cand)
        end
    end

    -- If every candidate was transiently rejected, fall back cleanly to raw list.
    if #ordered == 0 then
        return baseCandidates
    end
    return ordered
end

local function TrackSentWhisperCandidates(trackKey, lookupKey, sentList, monoNow, isSilentAddonPacket)
    if not trackKey or not sentList or #sentList == 0 then return end
    local now = monoNow or (GetTime and GetTime()) or 0
    Chat._lastCandidateTrackAt = now
    Chat.lastWhisperCandidates = Chat.lastWhisperCandidates or {}
    local wcCount = 0
    for k, rec in pairs(Chat.lastWhisperCandidates) do
        if type(rec) ~= "table" or (now - (rec.at or 0)) > 15 then
            Chat.lastWhisperCandidates[k] = nil
        else
            wcCount = wcCount + 1
        end
    end
    if wcCount >= 80 then
        wipe(Chat.lastWhisperCandidates)
    end
    Chat.lastWhisperCandidates[trackKey] = {
        candidates = sentList,
        lookupKey = lookupKey,
        at = now,
    }
    if isSilentAddonPacket == true then
        Chat.silentNotFoundLedger = Chat.silentNotFoundLedger or {}
        local count = 0
        for k, rec in pairs(Chat.silentNotFoundLedger) do
            if type(rec) ~= "table" or now > (rec.expiresAt or 0) then
                Chat.silentNotFoundLedger[k] = nil
            else
                count = count + 1
            end
        end
        if count > 80 then
            wipe(Chat.silentNotFoundLedger)
        end
        local isWatchProbe = (type(trackKey) == "string" and trackKey:sub(1, 7) == "wprobe:")
        local exp = now + 8.0
        for _, cand in ipairs(sentList) do
            if type(cand) == "string" and cand ~= "" then
                local lowCand = (Compat.LowerUtf8 and Compat.LowerUtf8(cand)) or cand:lower()
                local spaced = (lowCand:gsub("%-", " "))
                local hyphened = (lowCand:gsub("%s+", "-"))
                for _, variant in ipairs({ lowCand, spaced, hyphened, lookupKey }) do
                    if type(variant) == "string" and variant ~= "" then
                        local prev = Chat.silentNotFoundLedger[variant]
                        Chat.silentNotFoundLedger[variant] = {
                            expiresAt = exp,
                            lookupKey = lookupKey,
                            displayName = cand,
                            isWatchProbe = isWatchProbe or (prev and prev.isWatchProbe == true),
                            notifiedOffline = false,
                        }
                    end
                end
            end
        end
    end
end

-- Helper to send a bounded SCentral1 addon payload over WHISPER / BNet GameData.
local function SendRoomPacket(targetChar, bnetGameAccId, payload, candidateOffset, opts)
    local canSend, lockReason = GuardAddonMessaging(false)
    if not canSend then
        return false, lockReason or "locked"
    end
    if ns.Clan and ns.Clan.isStoppedThisSession then
        return false, "stopped"
    end
    local monoNow = GetTime and GetTime() or 0
    if ns.Clan and ns.Clan.backoffUntil and monoNow < ns.Clan.backoffUntil then
        return false, "throttled"
    end
    if not payload or #payload > MAX_PAYLOAD_BYTES then
        return false, "too_long"
    end

    opts = type(opts) == "table" and opts or {}
    local bnetConfirmed = bnetGameAccId and Chat.sessionBNetPeers and Chat.sessionBNetPeers[bnetGameAccId] ~= nil
    local bnetSentOk = false

    if bnetGameAccId and C_BattleNet and C_BattleNet.SendGameData and opts.allowBNet ~= false then
        local ok, res = pcall(C_BattleNet.SendGameData, bnetGameAccId, PREFIX, payload)
        if ok then
            if Enum and Enum.SendAddonMessageResult and type(res) == "number" then
                if res == Enum.SendAddonMessageResult.Success then
                    bnetSentOk = true
                elseif res == Enum.SendAddonMessageResult.AddonMessageThrottle then
                    RecordThrottleStrike()
                    if not targetChar or targetChar == "" then
                        return false, "throttled"
                    end
                end
            elseif res ~= false then
                bnetSentOk = true
            end
        end
    end

    -- Only rely exclusively on BNet GameData if BNet addon delivery was already confirmed
    -- in this session or if no character WHISPER target exists.
    if bnetSentOk and (bnetConfirmed or not targetChar or targetChar == "") and not opts.sendAllCandidates then
        return true, "BNET"
    end

    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if targetChar and targetChar ~= "" and sendFn then
        local parsed = Compat.ParseCharacterName(targetChar)
        local resolved = parsed and Chat.resolvedWhisperTargets and Chat.resolvedWhisperTargets[parsed.lookupKey]
        local resolvedRejected = resolved and Chat.rejectedWhisperTargets and Chat.rejectedWhisperTargets[resolved] and monoNow < Chat.rejectedWhisperTargets[resolved]
        if resolvedRejected then
            Chat.resolvedWhisperTargets[parsed.lookupKey] = nil
            resolved = nil
        end

        local candidates = BuildOrderedWhisperCandidates(targetChar, candidateOffset, opts.extraCandidates)
        local sendAll = (opts.sendAllCandidates == true and opts.forceAllCandidates == true)
        local maxToSend = sendAll and math.min(2, #candidates) or 1
        local sentList = {}
        local lastErr = "failed"
        local restrictedCount = 0

        for idx, candidate in ipairs(candidates) do
            TrackSentWhisperCandidates(opts.trackCandidateKey or "room:whisper", parsed and parsed.lookupKey, { candidate }, monoNow, true)
            local ok, res = pcall(sendFn, PREFIX, payload, "WHISPER", candidate)
            if ok then
                if Enum and Enum.SendAddonMessageResult and type(res) == "number" then
                    if res == Enum.SendAddonMessageResult.Success then
                        sentList[#sentList + 1] = candidate
                        if #sentList >= maxToSend then
                            break
                        end
                    elseif res == Enum.SendAddonMessageResult.AddonMessageThrottle then
                        RecordThrottleStrike()
                        TrackSentWhisperCandidates(opts.trackCandidateKey, parsed and parsed.lookupKey, sentList, monoNow)
                        if #sentList > 0 then
                            return true, sentList[1], sentList
                        end
                        return bnetSentOk, bnetSentOk and "BNET" or "throttled"
                    elseif Enum.SendAddonMessageResult.AddonsRestricted and res == Enum.SendAddonMessageResult.AddonsRestricted then
                        lastErr = "restricted"
                        restrictedCount = restrictedCount + 1
                    else
                        lastErr = "failed"
                    end
                elseif res ~= false then
                    sentList[#sentList + 1] = candidate
                    if #sentList >= maxToSend then
                        break
                    end
                end
            end
            if not sendAll and #sentList > 0 then
                break
            end
        end

        if #sentList > 0 then
            TrackSentWhisperCandidates(opts.trackCandidateKey, parsed and parsed.lookupKey, sentList, monoNow)
            return true, sentList[1], sentList
        end
        if bnetSentOk then
            return true, "BNET"
        end
        if restrictedCount > 0 then
            return false, "restricted"
        end
        return false, lastErr
    end

    if bnetSentOk then
        return true, "BNET"
    end
    return false, "failed"
end

function Chat:CreateRoom(rawTitle)
    local cleanTitle = Compat.CleanPayloadField(rawTitle, 32)
    if cleanTitle == "" then
        ns:Print(L["Enter a valid room name."])
        return nil
    end
    local meDisplay, meKey = GetMyInfo()

    local roomId = "r" .. tostring(time() % 1000000) .. tostring(math.random(10, 99))
    local rooms = GetRoomsScopeTable()
    if not rooms then return nil end

    rooms[roomId] = {
        id = roomId,
        title = cleanTitle,
        host = meDisplay,
        hostKey = meKey,
        joined = true,
        pendingInvite = false,
        members = { [meKey] = meDisplay },
        createdAt = time(),
        updatedAt = time(),
    }

    local key = "room:" .. roomId
    local t = EnsureThread(key, "ROOM", cleanTitle, { roomId = roomId })
    AppendMessage(t, L["System"], string.format(L["Created private room: %s"], cleanTitle), false, nil, true, true)
    self:SetActiveThread(key)
    ns:Emit("CHAT_UPDATED")
    return rooms[roomId]
end

local function CountTable(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

function Chat:InviteToRoom(roomId, rawTarget, bnetAccountID)
    local room = self:GetRoom(roomId)
    if not room or not room.joined then
        ns:Print(L["Select a joined room first."])
        return false
    end
    if not GuardAddonMessaging(true) then
        return false
    end

    local bnetGameId, bnetChar
    if bnetAccountID then
        bnetGameId, bnetChar = FindBNetWoWGameAccount(bnetAccountID)
    end

    local parsed = Compat.ParseCharacterName(bnetChar or rawTarget)
    if not parsed and not bnetGameId then
        ns:Print(L["Enter a valid Character-Realm or select an online player."])
        return false
    end
    if parsed and Compat.IsMe(parsed.displayName) then
        return false
    end
    if not (parsed and room.members and room.members[parsed.lookupKey]) and CountTable(room.members) >= MAX_ROOM_MEMBERS then
        ns:Print(L["Room member limit reached."])
        return false
    end

    local hostDisplay = GetMyInfo()
    local payload = string.format(
        "RMI|%s|%s|%s",
        roomId,
        NonEmptyField(room.title, 32, roomId),
        NonEmptyField(hostDisplay, 32, hostDisplay)
    )

    local sent = SendRoomPacket(parsed and parsed.displayName, bnetGameId, payload)
    if sent then
        if parsed then
            room.members = room.members or {}
            room.members[parsed.lookupKey] = parsed.displayName
        end
        if bnetGameId then
            self.roomBNetTargets[roomId] = self.roomBNetTargets[roomId] or {}
            self.roomBNetTargets[roomId][bnetGameId] = (parsed and parsed.displayName) or ""
        end
        room.updatedAt = time()
        local t = self.threads["room:" .. roomId]
        if t then
            AppendMessage(t, L["System"], string.format(L["Invited %s to room."], parsed and parsed.displayName or "BNet"), false, nil, true, true)
        end
        return true
    end
    ns:Print(L["Unable to send room invite right now."])
    return false
end

function Chat:AcceptRoomInvite(roomId)
    local room = self:GetRoom(roomId)
    if not room then return false end
    local meDisplay, meKey = GetMyInfo()

    room.pendingInvite = false
    room.joined = true
    room.members = room.members or {}
    room.members[meKey] = meDisplay
    room.updatedAt = time()

    local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
    AppendMessage(t, L["System"], string.format(L["Joined private room: %s"], room.title or roomId), false, nil, true, true)
    self:SetActiveThread("room:" .. roomId)

    local payload = string.format("RMJ|%s|%s|1", roomId, NonEmptyField(meDisplay, 32, meDisplay))
    local bnetGameId = room.hostBNetGameId
    if not bnetGameId and room.host then
        local hParsed = Compat.ParseCharacterName(room.host)
        if hParsed then
            local sr = Store and Store.socialByLookup and Store.socialByLookup[hParsed.lookupKey]
            bnetGameId = select(1, FindBNetWoWGameAccountByChar(hParsed, sr and sr.guid or nil))
            if not bnetGameId and ns.Social and ns.Social.GetBNetLinkInfo then
                local bInfo = ns.Social:GetBNetLinkInfo(hParsed.lookupKey)
                if bInfo and bInfo.bnetAccountID then
                    bnetGameId = select(1, FindBNetWoWGameAccount(bInfo.bnetAccountID))
                end
            end
        end
    end
    SendRoomPacket(room.host, bnetGameId, payload)
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:DeclineRoomInvite(roomId)
    local rooms = GetRoomsScopeTable()
    local room = rooms and rooms[roomId]
    if not room then return end
    local meDisplay = GetMyInfo()
    local bnetGameId = room.hostBNetGameId
    if not bnetGameId and room.host then
        local hParsed = Compat.ParseCharacterName(room.host)
        if hParsed then
            bnetGameId = select(1, FindBNetWoWGameAccountByChar(hParsed))
        end
    end
    if room.host or bnetGameId then
        local payload = string.format("RMJ|%s|%s|0", roomId, NonEmptyField(meDisplay, 32, meDisplay))
        SendRoomPacket(room.host, bnetGameId, payload)
    end
    if self.roomBNetTargets then
        self.roomBNetTargets[roomId] = nil
    end
    rooms[roomId] = nil
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
end

function Chat:LeaveRoom(roomId)
    local rooms = GetRoomsScopeTable()
    local room = rooms and rooms[roomId]
    if not room then return end

    local meDisplay, meKey = GetMyInfo()
    local payload = string.format("RML|%s|%s", roomId, NonEmptyField(meDisplay, 32, meDisplay))
    local bnetTargets, memberHasBNet = ResolveRuntimeRoomBNetTargets(roomId, room, meKey)
    for key, target in pairs(room.members or {}) do
        if key ~= meKey and not memberHasBNet[key] then
            SendRoomPacket(target, nil, payload)
        end
    end
    for _, bnetGameId in ipairs(bnetTargets) do
        SendRoomPacket(nil, bnetGameId, payload)
    end
    self.roomBNetTargets[roomId] = nil

    rooms[roomId] = nil
    self.threads["room:" .. roomId] = nil
    if self.activeThreadKey == ("room:" .. roomId) then
        self.activeThreadKey = nil
    end
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
end

local function EncodeAddonHyperlinks(rawText)
    if type(rawText) ~= "string" or rawText == "" or not rawText:find("|", 1, true) then
        return rawText
    end
    local s = rawText
    s = s:gsub("|c%x%x%x%x%x%x%x%x(|H.-|h.-|h)|r", "%1")
    s = s:gsub("|cn[^:]+:(|H.-|h.-|h)|r", "%1")
    s = s:gsub("|Hitem:(%d+)[^|]*|h%[([^%]]+)%]|h", function(itemId, label)
        local cleanLbl = tostring(label or ""):gsub("[{}|]", "")
        return "{item:" .. tostring(itemId) .. ":" .. cleanLbl .. "}"
    end)
    s = s:gsub("|Hspell:(%d+)[^|]*|h%[([^%]]+)%]|h", function(spellId, label)
        local cleanLbl = tostring(label or ""):gsub("[{}|]", "")
        return "{spell:" .. tostring(spellId) .. ":" .. cleanLbl .. "}"
    end)
    return s
end

function Chat:SendRoomMessage(roomId, rawText)
    if not GuardAddonMessaging(true) then
        return false
    end

    local room = self:GetRoom(roomId)
    if not room or not room.joined then
        return false
    end

    local cleanText = Compat.CleanPayloadField(EncodeAddonHyperlinks(rawText), 150)
    if cleanText == "" then
        return false
    end

    local now = GetTime and GetTime() or time()
    if (now - (self.lastRoomSendAt or 0)) < ROOM_SEND_COOLDOWN then
        ns:Print(L["Please wait a moment before sending another room message."])
        return false
    end
    self.lastRoomSendAt = now

    local meDisplay, meKey = GetMyInfo()
    local senderShort = NonEmptyField(meDisplay, 36, meDisplay)
    local payload = string.format("RM|%s|%s|%s", roomId, senderShort, cleanText)
    if #payload > MAX_PAYLOAD_BYTES then
        ns:Print(L["Message is too long for an addon room packet."])
        return false
    end

    local sentCount = 0
    local bnetTargets, memberHasBNet = ResolveRuntimeRoomBNetTargets(roomId, room, meKey)
    for key, target in pairs(room.members or {}) do
        if key ~= meKey and not memberHasBNet[key] then
            if SendRoomPacket(target, nil, payload) then
                sentCount = sentCount + 1
            end
        end
    end
    for _, bnetGameId in ipairs(bnetTargets) do
        if SendRoomPacket(nil, bnetGameId, payload) then
            sentCount = sentCount + 1
        end
    end

    local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
    local _, myClass = Safe.Call(UnitClass, "player")
    AppendMessage(t, senderShort, cleanText, false, Safe.String(myClass), not Chat:ShouldSaveGeneralHistory(), true, {
        viaAddon = true,
        echoToOfficial = true,
        notifyKind = "ROOM",
    })
    if sentCount == 0 then
        AppendMessage(t, L["System"], L["No online room peers reached yet; invite friends or guildmates."], false, nil, true, true)
    end
    return true
end

local RAID_ICON_TOKEN_MAP = {
    ["{rt1}"] = 1, ["{star}"] = 1, ["{estrela}"] = 1, ["{estrella}"] = 1,
    ["{rt2}"] = 2, ["{circle}"] = 2, ["{circulo}"] = 2, ["{círculo}"] = 2,
    ["{rt3}"] = 3, ["{diamond}"] = 3, ["{losango}"] = 3, ["{diamante}"] = 3,
    ["{rt4}"] = 4, ["{triangle}"] = 4, ["{triangulo}"] = 4, ["{triângulo}"] = 4,
    ["{rt5}"] = 5, ["{moon}"] = 5, ["{lua}"] = 5, ["{luna}"] = 5,
    ["{rt6}"] = 6, ["{square}"] = 6, ["{quadrado}"] = 6, ["{cuadrado}"] = 6,
    ["{rt7}"] = 7, ["{cross}"] = 7, ["{xis}"] = 7, ["{cruz}"] = 7,
    ["{rt8}"] = 8, ["{skull}"] = 8, ["{caveira}"] = 8, ["{calavera}"] = 8,
}

function Chat:FormatRaidTargetTokens(rawText)
    if type(rawText) ~= "string" or rawText == "" or not rawText:find("{", 1, true) then
        return rawText
    end
    local out = rawText:gsub("(%b{})", function(tok)
        local idx = RAID_ICON_TOKEN_MAP[tok:lower()]
        if idx then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. tostring(idx) .. ":13|t"
        end
        local itemId, itemLabel = tok:match("^{item:(%d+):([^}]+)}$")
        if itemId and itemLabel then
            local hex = "|cffffffff"
            if C_Item and C_Item.GetItemQualityByID and ITEM_QUALITY_COLORS then
                local okQ, qVal = pcall(C_Item.GetItemQualityByID, tonumber(itemId))
                if okQ and qVal and ITEM_QUALITY_COLORS[qVal] and ITEM_QUALITY_COLORS[qVal].hex then
                    hex = ITEM_QUALITY_COLORS[qVal].hex
                end
            end
            return hex .. "|Hitem:" .. tostring(itemId) .. "::::::::80:::::|h[" .. itemLabel .. "]|h|r"
        end
        local spellId, spellLabel = tok:match("^{spell:(%d+):([^}]+)}$")
        if spellId and spellLabel then
            return "|cff71d5ff|Hspell:" .. tostring(spellId) .. "|h[" .. spellLabel .. "]|h|r"
        end
        return tok
    end)
    return out
end

function Chat:ReceiveAllianceMessage(senderGuild, authorName, classFile, msgText, msgId)
    if not msgText or msgText == "" then return end
    if not ns.Clan or not ns.Clan:IsMemberAllianceAuthorized() then
        return
    end

    local nowTs = GetTime and GetTime() or time()
    self.seenAllianceMsgs = self.seenAllianceMsgs or {}
    if msgId and msgId ~= "" then
        if (nowTs - (self._lastAllianceDedupPruneAt or 0)) >= 30 then
            self._lastAllianceDedupPruneAt = nowTs
            for k, seenAt in pairs(self.seenAllianceMsgs) do
                if (nowTs - (seenAt or 0)) > 120 then
                    self.seenAllianceMsgs[k] = nil
                end
            end
        end
        if self.seenAllianceMsgs[msgId] then
            return
        end
        self.seenAllianceMsgs[msgId] = nowTs
    end

    local t = EnsureThread("ch:alliance", "ALLIANCE", L["Alliance"], { slash = "/al " })
    if not t then return end

    local gTag = (senderGuild and senderGuild ~= "") and ("<" .. senderGuild .. "> ") or ""
    local senderFull = ResolveChatSenderDisplay(authorName, nil, authorName)
    local displayName = gTag .. senderFull

    local myDisplay, meKey, myFirst = GetMyInfo()
    local isMe = Compat.IsMe(authorName) or (authorName == myDisplay or authorName == myFirst or authorName == meKey)
    AppendMessage(t, displayName, msgText, not isMe, classFile, not Chat:ShouldSaveGeneralHistory(), false, {
        viaAddon = true,
        notifyKind = "ALLIANCE",
        deliveryMsgId = msgId,
        senderCharName = senderFull,
        previewCategory = "ROOM",
        previewChannelKind = "ALLIANCE",
        replySlash = "/al ",
    })

    -- GreenWall Official Chat Mirror (opt-in on by default, respects Account Ignore & Focus silence)
    local s = ns.db and ns.db.settings
    local isSenderIgnored = (not isMe) and (ns.Store and ns.Store.IsAccountIgnored and ns.Store:IsAccountIgnored(senderFull or authorName))
    if (not isSenderIgnored) and (not s or (s.embedOfficialChat ~= false and s.clanOfficialGreenWall ~= false))
        and _G.ChatFrame1 and _G.ChatFrame1.AddMessage then
        local hex = (Compat.ClassHex and Compat.ClassHex(classFile)) or "|cffffffff"
        local cleanTarget = Compat.CleanPayloadField and Compat.CleanPayloadField(senderFull or authorName or "", 40) or ""
        local namePart
        if cleanTarget ~= "" and not cleanTarget:find("#", 1, true) and not cleanTarget:find("|", 1, true) then
            namePart = "|Haddon:SCentral:w:" .. cleanTarget .. "|h" .. hex .. "[" .. senderFull .. "]|r|h"
        else
            namePart = hex .. "[" .. senderFull .. "]|r"
        end
        local gwPrefix = (senderGuild and senderGuild ~= "")
            and ("|cff3fd996[" .. L["Alliance"] .. " <" .. senderGuild .. ">]|r ")
            or ("|cff3fd996[" .. L["Alliance"] .. "]|r ")
        pcall(_G.ChatFrame1.AddMessage, _G.ChatFrame1, gwPrefix .. namePart .. ": " .. self:FormatRaidTargetTokens(msgText))
    end
end

function Chat:SendAllianceMessage(rawText)
    if not rawText or rawText == "" then return false end
    if not ns.Clan or not ns.Clan:IsMemberAllianceAuthorized() then
        ns:Print(L["You do not have permission to use Alliance Chat."])
        return false
    end

    local clean = Compat.CleanPayloadField(EncodeAddonHyperlinks(rawText), 140)
    if clean == "" then return false end

    local now = GetTime and GetTime() or time()
    if (now - (self.lastAllianceSendAt or 0)) < 1.0 then
        ns:Print(L["Please wait a moment before sending another alliance message."])
        return false
    end
    self.lastAllianceSendAt = now

    local ok, sentMsgId = ns.Clan:SendAllianceChat(clean)
    if ok then
        local myName = GetMyInfo()
        local myGuild = Safe.String(Safe.Call(GetGuildInfo, "player")) or ""
        local _, myClass = Safe.Call(UnitClass, "player")
        self:ReceiveAllianceMessage(myGuild, myName, myClass, clean, sentMsgId)
        return true
    end
    return false
end

function Chat:IsDirectChatEnabled()
    local s = ns.db and ns.db.settings
    return not (s and (s.moduleChatEnabled == false or s.addonDirectChat == false))
end

function Chat:ClearTemporaryOffline(threadKey)
    local t = threadKey and self.threads and self.threads[threadKey]
    if not t then return false end
    local cleared = false
    if self.sessionOfflineChars then
        local targets = { t.targetName, t.title }
        for _, raw in ipairs(targets) do
            if type(raw) == "string" and raw ~= "" then
                local lk = Compat.ParseCharacterFields(raw)
                if lk and self.sessionOfflineChars[lk] then
                    self.sessionOfflineChars[lk] = nil
                    cleared = true
                end
            end
        end
    end
    if cleared then
        self:BumpPeerStateGen()
        ns:Emit("CHAT_UPDATED")
    end
    return cleared
end

local function NextMsgId()
    Chat.msgSeq = (Chat.msgSeq or 0) + 1
    return "m" .. tostring(Chat.msgSeq) .. tostring((time() or 0) % 1000)
end

local function IsCharacterOnlineOrReachable(parsed, bnetAccountID)
    if bnetAccountID then
        local gId = FindBNetWoWGameAccount(bnetAccountID)
        if gId then
            return true, "bnet_wow"
        end
        if IsBNetAccountOnline(bnetAccountID) then
            return true, "bnet_app"
        end
        return false, "not_in_wow"
    end
    if not parsed then
        return false, "invalid"
    end

    local monoNow = GetTime and GetTime() or 0
    local offlineUntil = Chat.sessionOfflineChars and Chat.sessionOfflineChars[parsed.lookupKey]
    if offlineUntil and monoNow < offlineUntil then
        return false, "offline"
    end

    local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(parsed.lookupKey)
    if bInfo and bInfo.isBNet and bInfo.online == true then
        if bInfo.activeLookupKey == parsed.lookupKey then
            return true, "bnet_wow"
        end
        return true, "bnet_other"
    end

    local seenAt = Chat.seenOnlineChars and Chat.seenOnlineChars[parsed.lookupKey]
    if Store then
        local wl = Store.GetWatchlistTable and Store:GetWatchlistTable()
        local wlEntry = wl and wl[parsed.lookupKey]
        if wlEntry then
            local checked = tonumber(wlEntry.lastChecked or wlEntry.lastSeen or 0) or 0
            if wlEntry.status == "online" then
                return true, "watchlist"
            elseif wlEntry.status == "offline" and (not seenAt or checked > seenAt) then
                return false, "offline"
            end
        end

        local socialRow = Store.socialByLookup and Store.socialByLookup[parsed.lookupKey]
        if not socialRow and not Store.socialByLookup and type(Store.social) == "table" then
            local direct = Store.social[parsed.lookupKey]
            if type(direct) == "table" and direct.lookupKey == parsed.lookupKey then
                socialRow = direct
            else
                for _, candidate in pairs(Store.social) do
                    if type(candidate) == "table" and candidate.lookupKey == parsed.lookupKey then
                        socialRow = candidate
                        break
                    end
                end
            end
        end
        if type(socialRow) == "table" then
            if socialRow.online == true then
                return true, "store"
            elseif socialRow.online == false and (not seenAt or (tonumber(socialRow.lastSeen or 0) or 0) > seenAt) then
                return false, "offline"
            end
        end

        local nearbyRow = type(Store.nearby) == "table" and Store.nearby[parsed.lookupKey]
        if type(nearbyRow) == "table" then
            if nearbyRow.online == true then
                return true, "store"
            elseif nearbyRow.online == false and (not seenAt or (tonumber(nearbyRow.lastSeen or 0) or 0) > seenAt) then
                return false, "offline"
            end
        end
    end

    if seenAt then
        return true, "session"
    end
    return true, "unknown"
end

function Chat:MarkPeerVerified(targetChar, bnetGameAccId, versionStr, sourceTag, peerClass, peerLevel, peerZone)
    local now = time()
    local monoNow = GetTime and GetTime() or now
    local ver = Compat.CleanPayloadField(versionStr or "", 24)
    if ver == "" then ver = nil end

    local verifiedWithPendingOpen = false
    local savedPeers = GetAddonPeersScopeTable()
    local parsed = targetChar and Compat.ParseCharacterName(targetChar)
    if parsed and not Compat.IsMe(parsed.displayName) then
        local keysToUpdate = { parsed.lookupKey }
        local seenKeys = { [parsed.lookupKey] = true }
        local reconciledDisplay = {}
        local isConfirmedReply = (sourceTag == "DPONG" or sourceTag == "DM" or sourceTag == "DMA" or sourceTag == "DPIN")
        local isDirectAddonPacket = isConfirmedReply or (sourceTag == "DPING" or sourceTag == "RM" or sourceTag == "RMI" or sourceTag == "RMJ" or sourceTag == "RML")
        -- Only lock a WHISPER target candidate once we receive an actual reply/message or a non-sharded sender.
        if isConfirmedReply or (isDirectAddonPacket and parsed.surname) then
            RecordResolvedWhisperTarget(parsed.lookupKey, targetChar)
        end

        -- Reconcile Forever "FirstName" addon replies against open/recently probed "FirstName Surname" threads
        -- (both WHISPER and BN_WHISPER threads).
        if not parsed.surname then
            local firstLower = parsed.firstName:lower()
            for tKey, t in pairs(self.threads) do
                if type(t) == "table" and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") then
                    local tParsed = Compat.ParseCharacterName(t.targetName or (t.kind == "WHISPER" and t.title) or "")
                    if tParsed and tParsed.lookupKey ~= parsed.lookupKey and tParsed.firstName:lower() == firstLower then
                        local recentProbe = self.probeSentAt and self.probeSentAt[tKey] and ((monoNow - self.probeSentAt[tKey]) <= 25)
                        if (self.pendingProbes and self.pendingProbes[tKey]) or (self.pendingOfficialOpen and self.pendingOfficialOpen[tKey]) or self.activeThreadKey == tKey or recentProbe then
                            if not seenKeys[tParsed.lookupKey] then
                                seenKeys[tParsed.lookupKey] = true
                                keysToUpdate[#keysToUpdate + 1] = tParsed.lookupKey
                            end
                            reconciledDisplay[tParsed.lookupKey] = tParsed.displayName
                            if isConfirmedReply then
                                RecordResolvedWhisperTarget(tParsed.lookupKey, targetChar)
                            end
                        end
                    end
                end
            end
        end

        local addedSavedPeer = false
        for _, lk in ipairs(keysToUpdate) do
            self.sessionPeers[lk] = {
                version = ver or (self.sessionPeers[lk] and self.sessionPeers[lk].version) or "SC",
                verifiedAt = now,
                source = sourceTag or "SCentral1",
            }
            self.seenOnlineChars[lk] = now
            if self.pendingPresenceProbes then self.pendingPresenceProbes[lk] = nil end
            if self.sessionOfflineChars then self.sessionOfflineChars[lk] = nil end
            if self.sessionUnverifiedPeers then self.sessionUnverifiedPeers[lk] = nil end
            if self.pendingProbes then self.pendingProbes["w:" .. lk] = nil end
            if self.pendingOfficialOpen and self.pendingOfficialOpen["w:" .. lk] then
                self.pendingOfficialOpen["w:" .. lk] = nil
                verifiedWithPendingOpen = true
            end
            if self.probeFailures then self.probeFailures["w:" .. lk] = nil end
            if self.probeAttemptIndex then self.probeAttemptIndex["w:" .. lk] = nil end

            local syncDisp = reconciledDisplay[lk] or (lk == parsed.lookupKey and parsed.displayName) or parsed.displayName
            local cleanPeerCls = (type(peerClass) == "string" and peerClass ~= "") and peerClass or nil
            local cleanPeerLvl = (type(peerLevel) == "number" and peerLevel > 0) and peerLevel or nil
            local cleanPeerZone = (type(peerZone) == "string" and peerZone ~= "") and peerZone or nil
            if cleanPeerCls or cleanPeerLvl or cleanPeerZone then
                self:RecordWhoObservation(syncDisp, cleanPeerLvl, cleanPeerCls, cleanPeerZone, nil, true, "addon")
            end
            if Store and Store.SyncWatchlistObservation then
                Store:SyncWatchlistObservation(syncDisp, {
                    online = true,
                    classFile = cleanPeerCls,
                    level = cleanPeerLvl,
                    area = cleanPeerZone,
                    source = "addon",
                })
            end

            -- Also clear pending/failed probe state on any matching BN_WHISPER or WHISPER thread for this character.
            for tKey, t in pairs(self.threads) do
                if type(t) == "table" and (t.kind == "BN_WHISPER" or t.kind == "WHISPER") then
                    local tParsed = Compat.ParseCharacterName(t.targetName or (t.kind == "WHISPER" and t.title) or "")
                    if tParsed and tParsed.lookupKey == lk then
                        if self.pendingProbes then self.pendingProbes[tKey] = nil end
                        if self.pendingOfficialOpen and self.pendingOfficialOpen[tKey] then
                            self.pendingOfficialOpen[tKey] = nil
                            verifiedWithPendingOpen = true
                        end
                        if self.probeFailures then self.probeFailures[tKey] = nil end
                        if self.probeAttemptIndex then self.probeAttemptIndex[tKey] = nil end
                    end
                end
            end

            if savedPeers then
                if savedPeers[lk] == nil then
                    addedSavedPeer = true
                end
                local existingName = type(savedPeers[lk]) == "table" and savedPeers[lk].name
                local preferredName = reconciledDisplay[lk] or (lk == parsed.lookupKey and parsed.displayName) or existingName or parsed.displayName
                -- Save strictly WoW character key + non-personal addon version metadata.
                savedPeers[lk] = {
                    name = preferredName,
                    version = self.sessionPeers[lk].version,
                    lastSeenAt = now,
                }
            end
        end
        if addedSavedPeer and savedPeers and CountHashKeys(savedPeers) > MAX_SAVED_PEERS then
            PruneSavedScopeTable(savedPeers, PEER_TTL_SECONDS, MAX_SAVED_PEERS, GetPeerStamp)
        end
        if ver and ns.Clan and ns.Clan.NoteRemoteVersion then
            ns.Clan:NoteRemoteVersion(parsed.displayName, parsed.lookupKey, ver, sourceTag or "WHISPER")
        end
        if ns.Social and ns.Social.QueueScan then
            ns.Social:QueueScan(0.25)
        end
    end

    if bnetGameAccId then
        local bnetAccId, _, fullChar = ResolveBNetSender(bnetGameAccId)
        local charParsed = fullChar and Compat.ParseCharacterName(fullChar)
        self.sessionBNetPeers[bnetGameAccId] = {
            bnetAccountID = bnetAccId,
            charName = fullChar,
            version = ver or (self.sessionBNetPeers[bnetGameAccId] and self.sessionBNetPeers[bnetGameAccId].version) or "SC",
            verifiedAt = now,
            source = sourceTag or "BN_ADDON",
        }
        if charParsed and not Compat.IsMe(charParsed.displayName) then
            self.sessionPeers[charParsed.lookupKey] = {
                version = self.sessionBNetPeers[bnetGameAccId].version,
                verifiedAt = now,
                source = sourceTag or "BN_ADDON",
            }
            self.seenOnlineChars[charParsed.lookupKey] = now
            if self.pendingProbes then self.pendingProbes["w:" .. charParsed.lookupKey] = nil end
            if self.probeFailures then self.probeFailures["w:" .. charParsed.lookupKey] = nil end
        end
        local bnPeerVer = self.sessionBNetPeers[bnetGameAccId] and self.sessionBNetPeers[bnetGameAccId].version
        if bnPeerVer and ns.Clan and ns.Clan.NoteRemoteVersion then
            ns.Clan:NoteRemoteVersion(
                (charParsed and charParsed.displayName) or fullChar or "Battle.net",
                charParsed and charParsed.lookupKey or nil,
                bnPeerVer,
                sourceTag or "BN_ADDON"
            )
        end
        if bnetAccId and self.pendingProbes then
            self.pendingProbes["bn:" .. tostring(bnetAccId)] = nil
        end
        if bnetAccId and self.pendingOfficialOpen and self.pendingOfficialOpen["bn:" .. tostring(bnetAccId)] then
            self.pendingOfficialOpen["bn:" .. tostring(bnetAccId)] = nil
            verifiedWithPendingOpen = true
        end
        if bnetAccId and self.probeFailures then
            self.probeFailures["bn:" .. tostring(bnetAccId)] = nil
        end
    end

    if verifiedWithPendingOpen then
        self.focusInputPending = true
        local who = (parsed and parsed.displayName) or targetChar or "?"
        ns:Print(string.format(L["%s has SocialCentral active! In-addon chat activated."], who))
    end
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
end

-- Persist passive guild peer discoveries to the SavedVariables registry without marking them live online.
function Chat:RecordPassiveSavedPeer(lookupKey, displayName, version, seenTs)
    if not lookupKey or lookupKey == "" or not self:IsDirectChatEnabled() then
        return false
    end
    local savedPeers = GetAddonPeersScopeTable()
    if not savedPeers then
        return false
    end
    local now = time()
    local stamp = tonumber(seenTs) or now
    if stamp > now then stamp = now end
    local existing = savedPeers[lookupKey]
    if type(existing) == "table" then
        local prevTs = tonumber(existing.lastSeenAt) or 0
        if stamp < prevTs then
            return false
        end
    end
    local cleanName = Compat.CleanPayloadField(displayName, 48)
    local niceName = (cleanName ~= "" and cleanName:lower() ~= lookupKey) and cleanName
        or (existing and type(existing.name) == "string" and existing.name ~= "" and existing.name)
        or (cleanName ~= "" and cleanName)
        or lookupKey
    local cleanVer = (type(version) == "string" and version ~= "") and Compat.CleanPayloadField(version, 24) or nil
    savedPeers[lookupKey] = {
        name = niceName,
        version = cleanVer or (existing and existing.version) or "SC",
        lastSeenAt = stamp,
    }
    if not existing and CountHashKeys(savedPeers) > MAX_SAVED_PEERS then
        PruneSavedScopeTable(savedPeers, PEER_TTL_SECONDS, MAX_SAVED_PEERS, GetPeerStamp)
    end
    self:BumpPeerStateGen()
    return true
end

function Chat:GetSavedPeerRecord(lookupKey)
    if not lookupKey or lookupKey == "" then return nil end
    local now = time()
    local best, bestTs = nil, -1
    local savedPeers = GetAddonPeersScopeTable()
    local rec = savedPeers and savedPeers[lookupKey]
    if type(rec) == "table" then
        local ts = tonumber(rec.lastSeenAt) or 0
        if (not PEER_TTL_SECONDS) or ts <= 0 or (now - ts) <= PEER_TTL_SECONDS then
            best = rec
            bestTs = ts
        end
    end
    local clanBucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local clanPeers = clanBucket and clanBucket.peers
    local cRec = clanPeers and clanPeers[lookupKey]
    if type(cRec) == "table" then
        local cTs = tonumber(cRec.updatedAt) or 0
        if (not PEER_TTL_SECONDS) or cTs <= 0 or (now - cTs) <= PEER_TTL_SECONDS then
            if (not best) or cTs > bestTs then
                best = cRec
                bestTs = cTs
            end
        end
    end
    return best
end

local function ResolveActivePeerTarget(t)
    if not t or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") then
        return nil
    end
    local rawBase = t.targetName or (t.kind == "WHISPER" and t.title) or nil
    if type(rawBase) == "string" and rawBase:find("#", 1, true) then
        rawBase = nil
    end
    local baseParsed = rawBase and Compat.ParseCharacterName(rawBase) or nil
    if baseParsed and (not baseParsed.surname or baseParsed.surname == "") then
        local upDisp = ResolveChatSenderDisplay(baseParsed.displayName, nil, nil)
        local upParsed = upDisp and Compat.ParseCharacterName(upDisp)
        if upParsed and upParsed.surname and upParsed.surname ~= "" then
            baseParsed = upParsed
        end
    end

    local bInfo = baseParsed and baseParsed.lookupKey and ns.Social and ns.Social.GetBNetLinkInfo
        and ns.Social:GetBNetLinkInfo(baseParsed.lookupKey) or nil
    local effBnetId = t.bnetAccountID or (bInfo and bInfo.bnetAccountID)
    if (not effBnetId) and baseParsed and baseParsed.lookupKey and Store and Store.GetAllLinkedCharacters and ns.Social and ns.Social.GetBNetLinkInfo then
        for _, alt in ipairs(Store:GetAllLinkedCharacters(baseParsed.lookupKey)) do
            local altBi = alt and alt.lookupKey and ns.Social:GetBNetLinkInfo(alt.lookupKey)
            if altBi and altBi.bnetAccountID then
                effBnetId = altBi.bnetAccountID
                bInfo = altBi
                break
            end
        end
    end

    local bnetGId, bnetChar, bnetAccName, canonId
    if effBnetId then
        bnetGId, bnetChar, bnetAccName, canonId = FindBNetWoWGameAccount(effBnetId)
        effBnetId = canonId or effBnetId
    elseif baseParsed then
        bnetGId, bnetChar, bnetAccName, canonId = FindBNetWoWGameAccountByChar(baseParsed)
        effBnetId = canonId or effBnetId
    end

    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    if bnetChar and bnetChar ~= "" then
        local bParsed = Compat.ParseCharacterName(bnetChar)
        local bFac = (bParsed and Chat:GetKnownCharacterFaction(bParsed.displayName, nil, effBnetId))
            or (bInfo and bInfo.activeLookupKey == (bParsed and bParsed.lookupKey) and bInfo.faction)
            or nil
        local sameFac = true
        if bFac and myFac then
            sameFac = (bFac == myFac)
        elseif bInfo and bInfo.sameFaction ~= nil and (not bParsed or not bInfo.activeLookupKey or bInfo.activeLookupKey == bParsed.lookupKey) then
            sameFac = bInfo.sameFaction ~= false
        end
        local switched = (baseParsed and bParsed and bParsed.lookupKey ~= baseParsed.lookupKey) == true
        local bClass = (bParsed and LookupClassFromCache(bParsed.lookupKey))
            or (bInfo and bInfo.activeLookupKey == (bParsed and bParsed.lookupKey) and bInfo.classFile)
            or nil
        return {
            activeDisplay = (bParsed and bParsed.displayName) or bnetChar,
            activeParsed = bParsed or baseParsed,
            activeClassFile = bClass,
            bnetGameAccId = bnetGId,
            bnetAccountID = effBnetId,
            bnetName = bnetAccName or (bInfo and bInfo.bnetName) or t.bnetName,
            bnetOnline = true,
            bnetAppOnly = false,
            sameFaction = sameFac,
            faction = bFac,
            isAltSwitch = switched,
        }
    end

    if effBnetId and IsBNetAccountOnline(effBnetId) then
        local baseFac = baseParsed and Chat:GetKnownCharacterFaction(baseParsed.displayName, nil, effBnetId) or t.faction
        return {
            activeDisplay = (baseParsed and baseParsed.displayName) or rawBase,
            activeParsed = baseParsed,
            bnetGameAccId = nil,
            bnetAccountID = effBnetId,
            bnetName = bnetAccName or (bInfo and bInfo.bnetName) or t.bnetName,
            bnetOnline = true,
            bnetAppOnly = true,
            sameFaction = false,
            faction = baseFac,
            isAltSwitch = false,
        }
    end

    if baseParsed then
        local onBase, srcBase = IsCharacterOnlineOrReachable(baseParsed, nil)
        if (not onBase) or srcBase == "offline" then
            if Store and Store.GetAllLinkedCharacters then
                for _, alt in ipairs(Store:GetAllLinkedCharacters(baseParsed.lookupKey)) do
                    local altParsed = alt and alt.displayName and Compat.ParseCharacterName(alt.displayName)
                    if altParsed and altParsed.lookupKey ~= baseParsed.lookupKey then
                        local onAlt, srcAlt = IsCharacterOnlineOrReachable(altParsed, nil)
                        if onAlt and srcAlt ~= "unknown" then
                            local altFac = Chat:GetKnownCharacterFaction(altParsed.displayName, nil, effBnetId)
                            return {
                                activeDisplay = altParsed.displayName,
                                activeParsed = altParsed,
                                bnetGameAccId = nil,
                                bnetAccountID = effBnetId,
                                bnetName = (bInfo and bInfo.bnetName) or t.bnetName,
                                bnetOnline = false,
                                bnetAppOnly = false,
                                sameFaction = (not altFac or not myFac) and true or (altFac == myFac),
                                faction = altFac,
                                isAltSwitch = true,
                            }
                        end
                    end
                end
            end
        end
    end

    local baseFac = (baseParsed and Chat:GetKnownCharacterFaction(baseParsed.displayName, nil, effBnetId)) or t.faction
    return {
        activeDisplay = (baseParsed and baseParsed.displayName) or rawBase,
        activeParsed = baseParsed,
        bnetGameAccId = nil,
        bnetAccountID = effBnetId,
        bnetName = (bInfo and bInfo.bnetName) or t.bnetName,
        bnetOnline = false,
        bnetAppOnly = false,
        sameFaction = (not baseFac or not myFac) and true or (baseFac == myFac),
        faction = baseFac,
        isAltSwitch = false,
    }
end

function Chat:ResolveActivePeerTarget(t)
    return ResolveActivePeerTarget(t)
end

function Chat:GetPeerAddonState(threadKey)
    local t = threadKey and self.threads[threadKey]
    if not t then
        return STATIC_NONE_STATE
    end
    if t.kind == "ROOM" then
        return STATIC_ROOM_STATE
    end
    if t.kind == "ALLIANCE" then
        return STATIC_ALLIANCE_STATE
    end
    if IsPublicChannelKind(t.kind) then
        if not t._channelState then
            local meta = STATIC_CHANNEL_ORDER[threadKey]
            t._channelState = { state = "channel", verified = false, slash = meta and meta.slash or t.slash }
        end
        return t._channelState
    end

    if not self:IsDirectChatEnabled() then
        return STATIC_DISABLED_STATE
    end

    local monoNow = GetTime and GetTime() or time()
    if t._peerState and t._peerStateGen == (self._peerStateGen or 0) and (monoNow - (t._peerStateAt or 0)) < 0.25 then
        return t._peerState
    end

    local activePeer = ResolveActivePeerTarget(t)
    local bnetGameAccId = activePeer and activePeer.bnetGameAccId or nil
    local bnetChar = (activePeer and activePeer.bnetOnline and not activePeer.bnetAppOnly) and activePeer.activeDisplay or nil
    local rawTargetChar = (activePeer and activePeer.activeDisplay) or t.targetName or (t.kind == "WHISPER" and t.title or "")

    if t.kind == "BN_WHISPER" and bnetChar and bnetChar ~= "" then
        t.targetName = bnetChar
    end
    if activePeer and activePeer.bnetAccountID and not t.bnetAccountID then
        t.bnetAccountID = activePeer.bnetAccountID
        t.bnetName = t.bnetName or activePeer.bnetName
    end

    if t._targetParsedRaw ~= rawTargetChar then
        t._targetParsedRaw = rawTargetChar
        t._targetParsed = Compat.ParseCharacterName(rawTargetChar)
    end
    local parsed = t._targetParsed or (activePeer and activePeer.activeParsed)

    if parsed and ns.Clan and ns.Clan.peerVersions and ns.Clan.peerVersions[parsed.lookupKey] and not self.sessionPeers[parsed.lookupKey] then
        local peerSrc = ns.Clan.peerChatSources and ns.Clan.peerChatSources[parsed.lookupKey]
        local sameFacOk = (not activePeer) or (activePeer.sameFaction ~= false)
        if sameFacOk and (peerSrc == "GUILD" or peerSrc == "WHISPER" or bnetGameAccId ~= nil) then
            local clanVer = Safe.String(ns.Clan.peerVersions[parsed.lookupKey])
            if clanVer and clanVer ~= "" then
                self.sessionPeers[parsed.lookupKey] = {
                    version = clanVer,
                    verifiedAt = time(),
                    source = peerSrc or "CLAN",
                }
            end
        end
    end

    local sess = parsed and self.sessionPeers[parsed.lookupKey]
    local bnSess = bnetGameAccId and self.sessionBNetPeers[bnetGameAccId]
    local prevSaved = parsed and self:GetSavedPeerRecord(parsed.lookupKey)
    local prevLastSeen = prevSaved and (tonumber(prevSaved.lastSeenAt) or tonumber(prevSaved.updatedAt)) or nil
    local prevVer = prevSaved and prevSaved.version
    local online, onlineReason
    if activePeer and activePeer.bnetAppOnly then
        online, onlineReason = true, "bnet_app"
    elseif activePeer and activePeer.bnetOnline and bnetGameAccId then
        online, onlineReason = true, "bnet_wow"
    else
        online, onlineReason = IsCharacterOnlineOrReachable(parsed, t.kind == "BN_WHISPER" and t.bnetAccountID or nil)
    end
    local resolvedTarget = (parsed and parsed.displayName) or (activePeer and activePeer.activeDisplay) or t.targetName
    local isAltSwitch = activePeer and activePeer.isAltSwitch == true or false
    local peerFaction = (activePeer and activePeer.faction) or t.faction

    local st
    if not online then
        st = {
            state = "offline",
            verified = false,
            knownAddon = (sess ~= nil or bnSess ~= nil or prevSaved ~= nil),
            version = (sess and sess.version) or (bnSess and bnSess.version) or prevVer,
            lastSeenAt = prevLastSeen,
            targetChar = resolvedTarget,
            rawTargetChar = rawTargetChar,
            bnetGameAccId = bnetGameAccId,
            activeChar = resolvedTarget,
            isAltSwitch = isAltSwitch,
            faction = peerFaction,
        }
    elseif onlineReason == "bnet_app" or onlineReason == "bnet_other" then
        st = {
            state = "unverified",
            verified = false,
            bnetOnline = true,
            knownAddon = (sess ~= nil or prevSaved ~= nil),
            version = (sess and sess.version) or prevVer,
            lastSeenAt = prevLastSeen,
            targetChar = resolvedTarget,
            rawTargetChar = rawTargetChar,
            bnetGameAccId = nil,
            activeChar = resolvedTarget,
            isAltSwitch = isAltSwitch,
            faction = peerFaction,
        }
    elseif sess or bnSess then
        st = {
            state = "verified",
            verified = true,
            version = (bnSess and bnSess.version) or (sess and sess.version) or "SC",
            verifiedAt = (bnSess and bnSess.verifiedAt) or (sess and sess.verifiedAt),
            source = (bnSess and bnSess.source) or (sess and sess.source),
            knownAddon = true,
            targetChar = resolvedTarget,
            rawTargetChar = rawTargetChar,
            bnetGameAccId = bnetGameAccId,
            activeChar = resolvedTarget,
            isAltSwitch = isAltSwitch,
            faction = peerFaction,
        }
    else
        local probeKey = t.key
        local pendingAt = self.pendingProbes and self.pendingProbes[probeKey]
        local isChecking = pendingAt and (monoNow - pendingAt) < PING_TIMEOUT
        local failInfo = self.probeFailures and self.probeFailures[probeKey]
        local isSessUnverified = parsed and self.sessionUnverifiedPeers and self.sessionUnverifiedPeers[parsed.lookupKey]

        if prevSaved and not isSessUnverified and not failInfo then
            -- Known from SavedVariables only; keep verified = false until DPING/DPONG confirms this session so first sends never drop.
            st = {
                state = "registered",
                verified = false,
                fromRegistry = true,
                confirming = isChecking == true,
                knownAddon = true,
                version = prevVer or "SC",
                lastSeenAt = prevLastSeen,
                targetChar = resolvedTarget,
                rawTargetChar = rawTargetChar,
                bnetGameAccId = bnetGameAccId,
                activeChar = resolvedTarget,
                isAltSwitch = isAltSwitch,
                faction = peerFaction,
            }
        elseif isChecking then
            st = {
                state = "checking",
                verified = false,
                knownAddon = false,
                targetChar = resolvedTarget,
                rawTargetChar = rawTargetChar,
                bnetGameAccId = bnetGameAccId,
                activeChar = resolvedTarget,
                isAltSwitch = isAltSwitch,
                faction = peerFaction,
            }
        elseif failInfo then
            st = {
                state = "unverified",
                verified = false,
                knownAddon = false,
                reason = failInfo,
                targetChar = resolvedTarget,
                rawTargetChar = rawTargetChar,
                bnetGameAccId = bnetGameAccId,
                activeChar = resolvedTarget,
                isAltSwitch = isAltSwitch,
                faction = peerFaction,
            }
        else
            st = {
                state = "unprobed",
                verified = false,
                knownAddon = false,
                targetChar = resolvedTarget,
                rawTargetChar = rawTargetChar,
                bnetGameAccId = bnetGameAccId,
                activeChar = resolvedTarget,
                isAltSwitch = isAltSwitch,
                faction = peerFaction,
            }
        end
    end

    t._peerState = st
    t._peerStateGen = self._peerStateGen or 0
    t._peerStateAt = monoNow
    return st
end

function Chat:IsPeerVerified(threadKey)
    local st = self:GetPeerAddonState(threadKey)
    return st and st.verified == true
end

function Chat:IsLookupKeyVerified(lookupKey)
    if not lookupKey or lookupKey == "" then return false end
    if self.sessionPeers and self.sessionPeers[lookupKey] then
        return true
    end
    if ns.Clan and ns.Clan.peerVersions and ns.Clan.peerVersions[lookupKey] then
        return true
    end
    return false
end

function Chat:IsPlayerAddonConfirmed(targetOrKey, bnetAccountID)
    local normKey = nil
    if type(targetOrKey) == "string" and targetOrKey ~= "" then
        if Compat and Compat.ParseCharacterFields then
            normKey = Compat.ParseCharacterFields(targetOrKey)
        end
        if not normKey or normKey == "" then
            normKey = targetOrKey:lower()
        end
        if self:IsLookupKeyVerified(normKey) or self:GetSavedPeerRecord(normKey) ~= nil then
            return true
        end
    end
    if bnetAccountID and FindBNetWoWGameAccount then
        local gId, gChar = FindBNetWoWGameAccount(bnetAccountID)
        if gId and self.sessionBNetPeers and self.sessionBNetPeers[gId] then
            return true
        end
        if gChar and gChar ~= "" and Compat and Compat.ParseCharacterFields then
            local bKey = Compat.ParseCharacterFields(gChar)
            if bKey and (self:IsLookupKeyVerified(bKey) or self:GetSavedPeerRecord(bKey) ~= nil) then
                return true
            end
        end
    end
    return false
end

function Chat:GetLookupKeyAddonBadge(lookupKey)
    if not lookupKey or lookupKey == "" then return "" end
    if self:IsLookupKeyVerified(lookupKey) then
        return " " .. (Compat.AddonIconMarkup and Compat.AddonIconMarkup(true, 13) or "|cff3fb950[SC]|r")
    end
    local rec = self:GetSavedPeerRecord(lookupKey)
    if rec then
        return " " .. (Compat.AddonIconMarkup and Compat.AddonIconMarkup(false, 12) or "|cff8ab4f8[SC*]|r")
    end
    return ""
end

local function ResolveBNetRedirectForWhisper(t)
    if not t or t.kind ~= "WHISPER" or not t.targetName then
        return nil
    end
    local active = ResolveActivePeerTarget and ResolveActivePeerTarget(t) or nil
    if not (active and active.bnetAccountID and active.bnetOnline) then
        return nil
    end
    local parsedTarget = Compat.ParseCharacterName(t.targetName)
    local isOppFaction = (active.sameFaction == false)
    local charOn, charSrc = IsCharacterOnlineOrReachable(parsedTarget, nil)
    local charUnavailable = active.bnetAppOnly or active.isAltSwitch or (not charOn) or charSrc == "bnet_other" or charSrc == "bnet_app"
    if not (isOppFaction or charUnavailable) then
        return nil
    end
    return {
        bnetAccountID = active.bnetAccountID,
        bnetName = active.bnetName or t.bnetName,
        activeChar = active.activeDisplay,
        targetDisplay = (parsedTarget and parsedTarget.displayName) or Compat.FormatForeverTarget(t.targetName) or t.targetName,
        isOppFaction = isOppFaction,
        isAltSwitch = active.isAltSwitch == true,
    }
end

local function ResolveAltWhisperRedirect(t)
    if not t or t.kind ~= "WHISPER" or not t.targetName then
        return nil
    end
    local parsedTarget = Compat.ParseCharacterName(t.targetName)
    if not parsedTarget or not parsedTarget.lookupKey then
        return nil
    end
    local charOn, charSrc = IsCharacterOnlineOrReachable(parsedTarget, nil)
    if charOn and charSrc ~= "bnet_other" and charSrc ~= "bnet_app" and charSrc ~= "offline" then
        return nil
    end
    if not (Store and Store.GetAllLinkedCharacters) then
        return nil
    end
    local alts = Store:GetAllLinkedCharacters(parsedTarget.lookupKey)
    if type(alts) ~= "table" or #alts == 0 then
        return nil
    end
    for _, alt in ipairs(alts) do
        local altParsed = alt.displayName and Compat.ParseCharacterName(alt.displayName)
        if altParsed and altParsed.lookupKey ~= parsedTarget.lookupKey then
            local on, src = IsCharacterOnlineOrReachable(altParsed, nil)
            if on and src ~= "unknown" and src ~= "offline" and src ~= "bnet_other" and src ~= "bnet_app" then
                return {
                    altDisplay = altParsed.displayName,
                    altLookupKey = altParsed.lookupKey,
                    targetDisplay = parsedTarget.displayName,
                }
            end
        end
    end
    return nil
end

local function FormatBNetRedirectMessage(targetDisplay, cleanText)
    if type(cleanText) ~= "string" or cleanText == "" then
        return ""
    end
    local low = cleanText:lower()
    if low:find("^%[to ") or low:find("^%[para ") then
        return cleanText
    end
    return string.format(L["[To %s]: %s"], targetDisplay or "?", cleanText)
end

function Chat:GetOfficialDestinationInfo(threadKey)
    local t = threadKey and self.threads[threadKey]
    if not t then return nil end

    if threadKey == "ch:general" then
        local gTarget = self.GetGeneralTargetInfo and self:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.channelId then
            return {
                kind = "PUB_CHANNEL",
                slash = gTarget.slash,
                label = gTarget.title,
                buttonText = string.format(L["Open %s Chat (%s)"], gTarget.title, "/" .. tostring(gTarget.channelId)),
                compactButtonText = string.format("%s (%s)", gTarget.title, "/" .. tostring(gTarget.channelId)),
            }
        elseif gTarget and gTarget.isYell then
            return {
                kind = "LOCAL_YELL",
                slash = "/y ",
                label = L["Yell"],
                buttonText = string.format(L["Open %s Chat (%s)"], L["Yell"], "/y"),
                compactButtonText = string.format("%s (%s)", L["Yell"], "/y"),
            }
        end
    end

    if STATIC_CHANNEL_ORDER[threadKey] then
        local meta = STATIC_CHANNEL_ORDER[threadKey]
        local chanLabel = L[meta.titleKey]
        return {
            kind = t.kind,
            slash = meta.slash,
            label = chanLabel,
            buttonText = string.format(L["Open %s Chat (%s)"], chanLabel, meta.slash:gsub("%s+$", "")),
            compactButtonText = string.format("%s (%s)", chanLabel, meta.slash:gsub("%s+$", "")),
        }
    end

    if t.kind == "PUB_CHANNEL" and t.channelId then
        local liveInfo = self:GetOfficialChannelInfo(t.channelId)
        local chanLabel = (liveInfo and liveInfo.title) or t.title or ("/" .. tostring(t.channelId))
        local slashStr = "/" .. tostring(t.channelId) .. " "
        return {
            kind = "PUB_CHANNEL",
            slash = slashStr,
            label = chanLabel,
            buttonText = string.format(L["Open %s Chat (%s)"], chanLabel, "/" .. tostring(t.channelId)),
            compactButtonText = string.format("%s (%s)", chanLabel, "/" .. tostring(t.channelId)),
        }
    end

    if t.kind == "BN_WHISPER" then
        local who = t.bnetName or t.title or t.targetName or "Battle.net"
        return {
            kind = "BN_WHISPER",
            label = who,
            buttonText = string.format(L["Send via Battle.net (%s)"], who),
            compactButtonText = string.format(L["B.net (%s)"], who),
        }
    end

    if t.kind == "WHISPER" then
        local target = t.targetName or t.title or ""
        local foreverTarget = Compat.FormatForeverTarget(target) or target
        local redir = ResolveBNetRedirectForWhisper(t)
        if redir then
            local who = redir.bnetName or redir.targetDisplay or foreverTarget
            return {
                kind = "BN_WHISPER",
                isBNetRedirect = true,
                activeChar = redir.activeChar,
                targetDisplay = redir.targetDisplay,
                label = who,
                buttonText = string.format(L["Send via Battle.net (%s)"], who),
                compactButtonText = string.format(L["B.net (%s)"], who),
            }
        end
        local altRedir = ResolveAltWhisperRedirect(t)
        if altRedir then
            return {
                kind = "WHISPER",
                isAltRedirect = true,
                activeChar = altRedir.altDisplay,
                targetDisplay = altRedir.targetDisplay,
                slash = "/w " .. (altRedir.altDisplay:gsub("%s+", "-")) .. " ",
                targetName = altRedir.altDisplay,
                label = altRedir.altDisplay,
                buttonText = string.format(L["Send via WoW Whisper (/w %s)"], altRedir.altDisplay),
                compactButtonText = string.format(L["Whisper (/w %s)"], altRedir.altDisplay),
            }
        end
        return {
            kind = "WHISPER",
            slash = "/w " .. (foreverTarget:gsub("%s+", "-")) .. " ",
            targetName = foreverTarget,
            label = foreverTarget,
            buttonText = string.format(L["Send via WoW Whisper (/w %s)"], foreverTarget),
            compactButtonText = string.format(L["Whisper (/w %s)"], foreverTarget),
        }
    end

    return nil
end

local function CanRunDirectOfficialSend(isHardwareEvent)
    if isHardwareEvent ~= true then
        return false
    end
    if ns.db and ns.db.settings and ns.db.settings.chatDirectOfficialSend == false then
        return false
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local okLock, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if okLock and locked == true then
            return false
        end
    end
    return true
end

local function IsInAllowedOfficialChannel(kind)
    if kind == "GUILD" or kind == "OFFICER" then
        return (Compat.IsInGuild and Compat.IsInGuild())
            or (IsInGuild and Safe.Value(IsInGuild()) == true)
            or false
    elseif kind == "PARTY" then
        local inGrp = (Compat.IsInGroup and Compat.IsInGroup()) or (IsInGroup and Safe.Value(IsInGroup()) == true)
        local inRaid = (Compat.IsInRaid and Compat.IsInRaid()) or (IsInRaid and Safe.Value(IsInRaid()) == true)
        return (inGrp == true) and (inRaid ~= true)
    elseif kind == "RAID" then
        return (Compat.IsInRaid and Compat.IsInRaid())
            or (IsInRaid and Safe.Value(IsInRaid()) == true)
            or false
    elseif kind == "INSTANCE_CHAT" then
        return IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and Safe.Value(IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE)) == true or false
    end
    return false
end

local function RemoveOptimisticEntry(t, entry)
    if not (t and type(t.messages) == "table" and entry) then
        return false
    end
    for i = #t.messages, 1, -1 do
        if t.messages[i] == entry then
            table.remove(t.messages, i)
            RewriteThreadHistory(t)
            return true
        end
    end
    return false
end

-- Hardware-event only direct Blizzard chat dispatch (strictly WHISPER/BN_WHISPER/GUILD/OFFICER/PARTY/RAID/INSTANCE_CHAT; zero SAY/YELL/CHANNEL, zero timers/automation).
local function TryDirectOfficialSend(self, t, threadKey, cleanText, isHardwareEvent)
    if not cleanText or cleanText == "" then
        return false
    end
    if not CanRunDirectOfficialSend(isHardwareEvent) then
        return false
    end
    local monoNow = GetTime and GetTime() or 0
    if (monoNow - (self._lastOfficialSendAt or 0)) < 0.25 then
        return false
    end

    local sendBNApi = C_BattleNet and C_BattleNet.SendWhisper
    local sendBNLegacy = _G.BNSendWhisper
    local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage

    local function DispatchBNetWhisper(accId, msgText)
        local outText = msgText or cleanText
        if not accId or outText == "" then return false end
        if sendBNApi then
            local ok, res = pcall(sendBNApi, accId, outText)
            if ok and res ~= false then
                return true
            end
        end
        if sendBNLegacy and sendBNLegacy ~= sendBNApi then
            local ok, res = pcall(sendBNLegacy, accId, outText)
            if ok and res ~= false then
                return true
            end
        end
        return false
    end

    if t.kind == "BN_WHISPER" then
        local bnetId = Safe.Number(t.bnetAccountID)
        if bnetId then
            local _, gChar, _, canonId = FindBNetWoWGameAccount(bnetId)
            local effAcc = canonId or bnetId
            if DispatchBNetWhisper(effAcc, cleanText) then
                self._lastOfficialSendAt = monoNow
                local meDisplay = GetMyInfo()
                local _, myClass = Safe.Call(UnitClass, "player")
                local tgtDisp = gChar or t.targetName or t.title
                local entry = AppendMessage(t, meDisplay, cleanText, false, Safe.String(myClass), (t.kind ~= "WHISPER"), true, {
                    targetChar = tgtDisp,
                })
                self.lastManualBNetSend = {
                    threadKey = threadKey,
                    bnetAccountID = effAcc,
                    targetDisplay = tgtDisp,
                    senderDisplay = meDisplay,
                    text = cleanText,
                    sentAt = monoNow,
                    optimisticEntry = entry,
                }
                return true
            end
        end
        return false
    end

    if t.kind == "WHISPER" and t.targetName then
        local activePeer = ResolveActivePeerTarget and ResolveActivePeerTarget(t) or nil
        if activePeer and not activePeer.bnetAppOnly and activePeer.activeDisplay and activePeer.activeDisplay ~= "" then
            SyncActiveCharacterOnThread(t, activePeer.activeDisplay, activePeer.activeClassFile, activePeer.faction)
        end
        local parsedTarget = Compat.ParseCharacterName(t.targetName)
        local redir = ResolveBNetRedirectForWhisper(t)
        if redir then
            local payloadText = redir.isAltSwitch and FormatBNetRedirectMessage(redir.targetDisplay, cleanText) or cleanText
            if DispatchBNetWhisper(redir.bnetAccountID, payloadText) then
                t.bnetAccountID = redir.bnetAccountID
                t.bnetName = t.bnetName or redir.bnetName
                self._lastOfficialSendAt = monoNow
                local meDisplay = GetMyInfo()
                local _, myClass = Safe.Call(UnitClass, "player")
                local tgtDisp = redir.activeChar or redir.targetDisplay or t.targetName
                local entry = AppendMessage(t, meDisplay, cleanText, false, Safe.String(myClass), (t.kind ~= "WHISPER"), true, {
                    targetChar = tgtDisp,
                })
                self.lastManualBNetSend = {
                    threadKey = threadKey,
                    bnetAccountID = redir.bnetAccountID,
                    targetDisplay = tgtDisp,
                    senderDisplay = meDisplay,
                    text = cleanText,
                    sentText = payloadText,
                    sentAt = monoNow,
                    optimisticEntry = entry,
                }
                return true
            end
        end
        local altRedir = ResolveAltWhisperRedirect(t)
        local sendTargetName = (altRedir and altRedir.altDisplay) or t.targetName
        local sendPayloadText = altRedir and FormatBNetRedirectMessage(altRedir.targetDisplay, cleanText) or cleanText
        local sendParsed = altRedir and Compat.ParseCharacterName(altRedir.altDisplay) or parsedTarget
        if sendChat then
            local candidates = BuildOrderedWhisperCandidates(sendTargetName, 0)
            local targetStr = (candidates and candidates[1]) or Compat.FormatForeverTarget(sendTargetName) or sendTargetName
            if targetStr and targetStr ~= "" then
                if self.silentNotFoundLedger then
                    local lowT = (Compat.LowerUtf8 and Compat.LowerUtf8(targetStr)) or targetStr:lower()
                    self.silentNotFoundLedger[lowT] = nil
                    self.silentNotFoundLedger[(lowT:gsub("%-", " "))] = nil
                    self.silentNotFoundLedger[(lowT:gsub("%s+", "-"))] = nil
                    if sendParsed and sendParsed.lookupKey then
                        self.silentNotFoundLedger[sendParsed.lookupKey] = nil
                    end
                end
                TrackSentWhisperCandidates("send:" .. threadKey, sendParsed and sendParsed.lookupKey, { targetStr }, monoNow, false)
                self:RecordOutboundOrigin("CHAT", "WHISPER", targetStr, L["Manual Chat (SocialCentral)"])
                local ok, res = pcall(sendChat, sendPayloadText, "WHISPER", nil, targetStr)
                if ok and res ~= false then
                    self._lastOfficialSendAt = monoNow
                    local meDisplay = GetMyInfo()
                    local _, myClass = Safe.Call(UnitClass, "player")
                    local tgtDisp = (sendParsed and sendParsed.displayName) or sendTargetName
                    local entry = AppendMessage(t, meDisplay, cleanText, false, Safe.String(myClass), false, true, {
                        targetChar = tgtDisp,
                    })
                    self.lastManualWhisperSend = {
                        threadKey = threadKey,
                        targetStr = targetStr,
                        targetDisplay = tgtDisp,
                        senderDisplay = meDisplay,
                        lookupKey = sendParsed and sendParsed.lookupKey or nil,
                        text = cleanText,
                        sentText = sendPayloadText,
                        bnetAccountID = t.bnetAccountID,
                        bnetName = t.bnetName,
                        sentAt = monoNow,
                        optimisticEntry = entry,
                    }
                    return true
                end
            end
        end
        return false
    end

    if threadKey == "ch:general" then
        local gTarget = self.GetGeneralTargetInfo and self:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.clubId and gTarget.streamId and _G.C_Club and _G.C_Club.SendMessage then
            local ok = pcall(_G.C_Club.SendMessage, gTarget.clubId, gTarget.streamId, cleanText)
            if ok then
                self._lastOfficialSendAt = monoNow
                local meDisplay = GetMyInfo()
                local _, myClass = Safe.Call(UnitClass, "player")
                self:RecordGeneralMessage("PUB_CHANNEL", meDisplay, cleanText, true, Safe.String(myClass), gTarget.title or gTarget.name, {
                    senderCharName = meDisplay,
                    channelId = gTarget.channelId,
                })
                return true
            end
        end
        return false
    end

    if STATIC_CHANNEL_ORDER[threadKey] and IsInAllowedOfficialChannel(t.kind) and sendChat then
        local ok, res = pcall(sendChat, cleanText, t.kind)
        if ok and res ~= false then
            self._lastOfficialSendAt = monoNow
            local meDisplay = GetMyInfo()
            local _, myClass = Safe.Call(UnitClass, "player")
            local skipP = not self:ShouldPersistThreadKey(threadKey)
            local entry = AppendMessage(t, meDisplay, cleanText, false, Safe.String(myClass), skipP, true)
            self.lastManualChannelSend = {
                threadKey = threadKey,
                kind = t.kind,
                text = cleanText,
                sentAt = monoNow,
                optimisticEntry = entry,
            }
            return true
        end
    end
    return false
end

function Chat:OpenOfficialChatForThread(threadKey, optionalDraft, isHardwareEvent)
    local t = threadKey and self.threads[threadKey]
    if not t then return false end

    local clean = (Compat.CleanChatMessage and Compat.CleanChatMessage(optionalDraft)) or Compat.CleanInput(optionalDraft) or ""
    if clean ~= "" and TryDirectOfficialSend(self, t, threadKey, clean, isHardwareEvent) then
        return true, "sent"
    end

    if t.kind == "BN_WHISPER" then
        Compat.BNetWhisper(t.bnetName, t.targetName or t.title, clean)
        return true, "prefilled"
    end

    local prefix
    if t.kind == "WHISPER" and t.targetName then
        local redir = ResolveBNetRedirectForWhisper(t)
        if redir and redir.bnetName then
            local prefill = (clean ~= "") and (redir.isAltSwitch and FormatBNetRedirectMessage(redir.targetDisplay, clean) or clean) or ""
            Compat.BNetWhisper(redir.bnetName, redir.targetDisplay or t.title, prefill)
            return true, "prefilled"
        end
        local altRedir = ResolveAltWhisperRedirect(t)
        if altRedir then
            local prefill = (clean ~= "") and FormatBNetRedirectMessage(altRedir.targetDisplay, clean) or ""
            Compat.Whisper(altRedir.altDisplay, prefill)
            return true, "prefilled"
        end
        Compat.Whisper(t.targetName, clean)
        return true, "prefilled"
    elseif threadKey == "ch:general" then
        local gTarget = self.GetGeneralTargetInfo and self:GetGeneralTargetInfo() or nil
        if gTarget and gTarget.slash then
            prefix = gTarget.slash .. clean
        else
            prefix = STATIC_CHANNEL_ORDER[threadKey].slash .. clean
        end
    elseif STATIC_CHANNEL_ORDER[threadKey] then
        if clean ~= "" and not IsInAllowedOfficialChannel(t.kind) and (t.kind == "GUILD" or t.kind == "OFFICER" or t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT") then
            if t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT" then
                return false, "not_in_group"
            end
            ns:Print(L["You are not currently in that channel."])
            return false, "not_in_channel"
        end
        prefix = STATIC_CHANNEL_ORDER[threadKey].slash .. clean
    elseif t.kind == "PUB_CHANNEL" and t.channelId then
        local liveInfo = self:GetOfficialChannelInfo(t.channelId)
        if not liveInfo then
            ns:Print(L["You are not currently in that channel."])
            return false
        end
        prefix = liveInfo.slash .. clean
    else
        return false
    end

    local isCombatRedirect = (ns.QuickReply and ns.QuickReply._redirectingBlizzCombatChat == true)
    if ns.QuickReply then
        ns.QuickReply._suppressBlizzSlashRedirectUntil = (GetTime and GetTime() or 0) + 0.6
        if (not isCombatRedirect) and ns.QuickReply.PrepareTemporaryOfficialEditBox then
            ns.QuickReply:PrepareTemporaryOfficialEditBox(25)
        end
    end
    local ok = false
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ok = pcall(ChatFrameUtil.OpenChat, prefix)
    elseif ChatFrame_OpenChat then
        ok = pcall(ChatFrame_OpenChat, prefix)
    end
    if ok then
        local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
            or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
            or _G.ChatFrame1EditBox
            or nil
        if activeEb then
            local curEbTxt = Safe.String(activeEb.GetText and activeEb:GetText() or nil) or ""
            local curEbType = Safe.String((activeEb.GetChatType and activeEb:GetChatType()) or (activeEb.GetAttribute and activeEb:GetAttribute("chatType")) or nil) or ""
            local expectedMeta = (threadKey ~= "ch:general") and STATIC_CHANNEL_ORDER[threadKey] or nil
            local needPubSwitch = false
            local wantChanId = nil
            if t.kind == "PUB_CHANNEL" and t.channelId then
                wantChanId = tonumber(t.channelId)
            elseif threadKey == "ch:general" then
                local gTarget = self.GetGeneralTargetInfo and self:GetGeneralTargetInfo() or nil
                if gTarget and gTarget.channelId then
                    wantChanId = tonumber(gTarget.channelId)
                end
            end
            if wantChanId then
                local curChanTgt = (activeEb.GetChannelTarget and Safe.Number(activeEb:GetChannelTarget()))
                    or (activeEb.GetAttribute and Safe.Number(activeEb:GetAttribute("channelTarget")))
                    or nil
                needPubSwitch = (curChanTgt ~= wantChanId)
            end
            local needPrefix = (type(prefix) == "string" and prefix ~= "" and prefix:sub(1, 1) == "/")
                and (curEbTxt == ""
                    or (not curEbTxt:match("^%s*/") and ((expectedMeta and curEbType ~= expectedMeta.kind) or needPubSwitch)))
            if needPrefix and activeEb.SetText then
                pcall(activeEb.SetText, activeEb, prefix)
            end
            if type(activeEb.ParseText) == "function" then
                pcall(activeEb.ParseText, activeEb, 0)
            elseif _G.ChatFrameUtil and type(_G.ChatFrameUtil.ParseText) == "function" then
                pcall(_G.ChatFrameUtil.ParseText, activeEb, 0)
            elseif _G.ChatEdit_ParseText then
                pcall(_G.ChatEdit_ParseText, activeEb, 0)
            end

            -- Failsafe for WoW Forever 16001: verify the editBox actually switched off its prior chatType
            -- (re-entering OpenChat while ActivateChat is running can skip slash parsing on some frames).
            local isProt = activeEb.IsProtected and activeEb:IsProtected()
            local postEbType = Safe.String((activeEb.GetChatType and activeEb:GetChatType()) or (activeEb.GetAttribute and activeEb:GetAttribute("chatType")) or nil) or ""
            local wantKind = expectedMeta and expectedMeta.kind or nil
            if wantKind and postEbType ~= wantKind and not isProt then
                if type(activeEb.SetChatType) == "function" then
                    pcall(activeEb.SetChatType, activeEb, wantKind)
                end
                if activeEb.SetAttribute then
                    pcall(activeEb.SetAttribute, activeEb, "chatType", wantKind)
                    pcall(activeEb.SetAttribute, activeEb, "stickyType", wantKind)
                end
                if clean == "" and activeEb.GetText and activeEb.SetText then
                    local afterTxt = Safe.String(activeEb:GetText()) or ""
                    if afterTxt:match("^%s*/%S+%s*$") then
                        pcall(activeEb.SetText, activeEb, "")
                    end
                end
                if type(activeEb.UpdateHeader) == "function" then
                    pcall(activeEb.UpdateHeader, activeEb)
                elseif _G.ChatFrameUtil and type(_G.ChatFrameUtil.UpdateHeader) == "function" then
                    pcall(_G.ChatFrameUtil.UpdateHeader, activeEb)
                elseif _G.ChatEdit_UpdateHeader then
                    pcall(_G.ChatEdit_UpdateHeader, activeEb)
                end
            elseif wantChanId and not isProt then
                local postChanTgt = (activeEb.GetChannelTarget and Safe.Number(activeEb:GetChannelTarget()))
                    or (activeEb.GetAttribute and Safe.Number(activeEb:GetAttribute("channelTarget")))
                    or nil
                if postChanTgt ~= wantChanId then
                    if activeEb.SetAttribute then
                        pcall(activeEb.SetAttribute, activeEb, "channelTarget", wantChanId)
                    end
                    if activeEb.SetChannelTarget then
                        pcall(activeEb.SetChannelTarget, activeEb, wantChanId)
                    end
                    if type(activeEb.UpdateHeader) == "function" then
                        pcall(activeEb.UpdateHeader, activeEb)
                    elseif _G.ChatFrameUtil and type(_G.ChatFrameUtil.UpdateHeader) == "function" then
                        pcall(_G.ChatFrameUtil.UpdateHeader, activeEb)
                    elseif _G.ChatEdit_UpdateHeader then
                        pcall(_G.ChatEdit_UpdateHeader, activeEb)
                    end
                end
            end

            if clean ~= "" and activeEb.SetCursorPosition then
                local afterTxt = Safe.String(activeEb.GetText and activeEb:GetText() or nil) or ""
                pcall(activeEb.SetCursorPosition, activeEb, #afterTxt)
            end
        end
        if ns.QuickReply and ns.QuickReply.ShowActiveOfficialEditBox then
            ns.QuickReply:ShowActiveOfficialEditBox(activeEb)
        end
        if ns.QuickReply and ns.QuickReply.SyncEnterBinding then
            ns.QuickReply:SyncEnterBinding()
        end
    end
    return ok, ok and "prefilled" or nil
end

function Chat:SendDirectLfgWhisper(targetName, message, isHardwareEvent, suppressFallbackChatBox)
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(targetName)
    local disp = (parsed and parsed.displayName) or targetName
    local lk = (parsed and parsed.lookupKey) or (type(disp) == "string" and disp:lower() or nil)
    local clean = (Compat.CleanChatMessage and Compat.CleanChatMessage(message)) or Compat.CleanInput(message) or ""
    if disp and disp ~= "" and lk and lk ~= "" and clean ~= "" then
        local t = EnsureThread("w:" .. lk, "WHISPER", disp, { targetName = disp })
        if t and TryDirectOfficialSend(self, t, t.key, clean, isHardwareEvent) then
            return true
        end
    end
    if not suppressFallbackChatBox and Compat.Whisper and targetName then
        Compat.Whisper(targetName, clean ~= "" and clean or message)
    end
    return false
end

function Chat:BuildDirectPresencePayload(tag)
    local _, myClass = Safe.Call(UnitClass, "player")
    myClass = Compat.CleanPayloadField(Safe.String(myClass) or "", 16)
    local myLvl = tostring(Safe.Number(Safe.Call(UnitLevel, "player")) or 0)
    local shareLoc = not (ns.db and ns.db.settings and ns.db.settings.chatShareLocation == false)
    local myZone = shareLoc and Compat.CleanPayloadField((Compat.CurrentZoneName and Compat.CurrentZoneName()) or "", 42) or ""
    return (tag or "DPING")
        .. "|" .. Compat.CleanPayloadField(ns.version or "0.0.0", 24)
        .. "|" .. myClass
        .. "|" .. myLvl
        .. "|" .. myZone
end

function Chat:ProbePeerAddon(threadKey, force)
    local t = threadKey and self.threads[threadKey]
    if not t or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") then
        return false, "invalid_thread"
    end
    if not self:IsDirectChatEnabled() then
        return false, "disabled"
    end
    local canSend, lockReason = GuardAddonMessaging(force)
    if not canSend then
        return false, lockReason or "locked"
    end

    local state = self:GetPeerAddonState(threadKey)
    if state.verified and state.state ~= "registered" then
        return true, "verified"
    end
    if state.state == "offline" then
        if force then
            ns:Print(L["Target appears offline or outside WoW right now; use official WoW/Battle.net chat."])
        end
        return false, "offline"
    end

    local monoNow = GetTime and GetTime() or time()
    self.probeSentAt = self.probeSentAt or {}
    self.pendingProbes = self.pendingProbes or {}
    self.probeFailures = self.probeFailures or {}
    self.probeAttemptIndex = self.probeAttemptIndex or {}
    self.lastProbeCandidate = self.lastProbeCandidate or {}

    local lastSent = self.probeSentAt[threadKey] or 0
    if (monoNow - lastSent) < PING_COOLDOWN then
        if force and state.state ~= "checking" then
            ns:Print(L["Verification ping was just sent; please wait a few seconds."])
        end
        return false, "cooldown"
    end

    local attemptOffset = self.probeAttemptIndex[threadKey] or 0
    local payload = self:BuildDirectPresencePayload("DPING")
    local target = state.targetChar or t.targetName
    local extra = (state.rawTargetChar and state.rawTargetChar ~= target) and { state.rawTargetChar } or nil
    local pLk = target and Compat.ParseCharacterFields(target) or nil
    local hasResolved = pLk and self.resolvedWhisperTargets and self.resolvedWhisperTargets[pLk] ~= nil
    local sent, errOrCand = SendRoomPacket(target, state.bnetGameAccId, payload, attemptOffset, {
        sendAllCandidates = true,
        forceAllCandidates = not hasResolved,
        allowBNet = (state.bnetGameAccId ~= nil),
        trackCandidateKey = threadKey,
        extraCandidates = extra,
    })

    PruneProbeTracking(self, monoNow)
    self.probeSentAt[threadKey] = monoNow
    if not sent then
        local err = errOrCand or "failed"
        self.probeFailures[threadKey] = err
        self.pendingProbes[threadKey] = nil
        self:BumpPeerStateGen()
        if force then
            if err == "throttled" then
                ns:Print(L["Addon messaging was throttled briefly; please try again in a few seconds."])
            elseif err == "restricted" then
                ns:Print(L["The game server blocked this addon verification packet."])
            else
                ns:Print(L["Could not send verification packet to %s right now."]:format(target or "?"))
            end
        end
        ns:Emit("CHAT_UPDATED")
        return false, err
    end

    -- Advance candidate offset for the next manual retry in case this Forever format gets dropped.
    self.probeAttemptIndex[threadKey] = attemptOffset + 1
    if type(errOrCand) == "string" and errOrCand ~= "" then
        self._lastCandidateTrackAt = monoNow
        self.lastProbeCandidate = self.lastProbeCandidate or {}
        local pcCount = 0
        for k, rec in pairs(self.lastProbeCandidate) do
            if type(rec) ~= "table" or (monoNow - (rec.at or 0)) > 15 then
                self.lastProbeCandidate[k] = nil
            else
                pcCount = pcCount + 1
            end
        end
        if pcCount >= 80 then
            wipe(self.lastProbeCandidate)
        end
        self.lastProbeCandidate[threadKey] = { candidate = errOrCand, at = monoNow }
    end
    self.probeFailures[threadKey] = nil
    self.pendingProbes[threadKey] = monoNow
    self:BumpPeerStateGen()

    -- Pure UI timeout expiry only (never sends addon packets from a timer).
    if C_Timer and C_Timer.After then
        local expectedSentAt = monoNow
        C_Timer.After(PING_TIMEOUT + 0.1, function()
            if Chat.pendingProbes and Chat.pendingProbes[threadKey] == expectedSentAt then
                Chat.pendingProbes[threadKey] = nil
                Chat:BumpPeerStateGen()
                local afterState = Chat:GetPeerAddonState(threadKey)
                if not afterState.verified then
                    Chat.probeFailures = Chat.probeFailures or {}
                    Chat.probeFailures[threadKey] = "timeout"
                    Chat:BumpPeerStateGen()
                end
                ns:Emit("CHAT_UPDATED")
            end
        end)
    end

    ns:Emit("CHAT_UPDATED")
    return true, "checking"
end

function Chat:ShouldAutoProbe(threadKey)
    if not threadKey or not self:IsDirectChatEnabled() then
        return false
    end
    local st = self:GetPeerAddonState(threadKey)
    if not st then return false end
    if st.state == "registered" or st.state == "unprobed" then
        self.autoProbedRegistered = self.autoProbedRegistered or {}
        local subKey = threadKey .. ":" .. tostring(st.targetChar or "")
        if not self.autoProbedRegistered[subKey] then
            self.autoProbedRegistered[subKey] = true
            return true
        end
    end
    return false
end

local function DrainDiscoveryQueue()
    Chat._discoveryTimerActive = false
    local queue = Chat.discoveryQueue
    if not queue or #queue == 0 then return end
    if not Chat:IsDirectChatEnabled() or (ns.db and ns.db.settings and ns.db.settings.versionCheck == false) then
        wipe(queue)
        return
    end
    if ns.Clan and ns.Clan.isStoppedThisSession then
        wipe(queue)
        return
    end

    local monoNow = GetTime and GetTime() or time()
    local elapsed = monoNow - (Chat.lastDiscoveryPingAt or 0)
    if elapsed < DISCOVERY_PING_INTERVAL then
        if C_Timer and C_Timer.After then
            Chat._discoveryTimerActive = true
            C_Timer.After(DISCOVERY_PING_INTERVAL - elapsed + 0.1, DrainDiscoveryQueue)
        end
        return
    end

    local canSend = GuardAddonMessaging(false)
    if not canSend then
        if C_Timer and C_Timer.After then
            Chat._discoveryTimerActive = true
            C_Timer.After(DISCOVERY_PING_INTERVAL, DrainDiscoveryQueue)
        end
        return
    end

    local item = table.remove(queue, 1)
    if item then
        local lk = item.lookupKey
        if not (lk and Chat:IsLookupKeyVerified(lk)) then
            local bnetGId
            if item.bnetAccountID then
                bnetGId = select(1, FindBNetWoWGameAccount(item.bnetAccountID))
            elseif item.parsed then
                bnetGId = select(1, FindBNetWoWGameAccountByChar(item.parsed, item.guid))
            end
            local payload = Chat:BuildDirectPresencePayload("DPING")
            if bnetGId and not (Chat.sessionBNetPeers and Chat.sessionBNetPeers[bnetGId]) then
                Chat.lastDiscoveryPingAt = monoNow
                SendRoomPacket(nil, bnetGId, payload, 0, {
                    allowBNet = true,
                })
            elseif item.allowWhisperReply and item.targetName and item.targetName ~= "" then
                local hasResolved = lk and Chat.resolvedWhisperTargets and Chat.resolvedWhisperTargets[lk] ~= nil
                Chat.lastDiscoveryPingAt = monoNow
                SendRoomPacket(item.targetName, nil, payload, 0, {
                    allowBNet = false,
                    sendAllCandidates = true,
                    forceAllCandidates = not hasResolved,
                    trackCandidateKey = item.trackKey,
                })
            end
        end
    end

    if #queue > 0 and C_Timer and C_Timer.After then
        Chat._discoveryTimerActive = true
        C_Timer.After(DISCOVERY_PING_INTERVAL + 0.1, DrainDiscoveryQueue)
    end
end

function Chat:QueuePoliteDiscoveryPing(opts)
    if type(opts) ~= "table" or not self:IsDirectChatEnabled() then
        return false
    end
    if ns.db and ns.db.settings and ns.db.settings.versionCheck == false then
        return false
    end
    if ns.Clan and ns.Clan.isStoppedThisSession then
        return false
    end
    if not GuardAddonMessaging(false) then
        return false
    end

    local parsed = opts.targetName and Compat.ParseCharacterName(opts.targetName) or nil
    local lk = opts.lookupKey or (parsed and parsed.lookupKey)
    if lk and self:IsLookupKeyVerified(lk) then
        return false
    end

    local dedupKey = lk or (opts.bnetAccountID and ("bn:" .. tostring(opts.bnetAccountID)))
    if not dedupKey or dedupKey == "" then
        return false
    end
    self.discoveryPingedThisSession = self.discoveryPingedThisSession or {}
    if self.discoveryPingedThisSession[dedupKey] then
        return false
    end
    self.discoveryPingedThisSession[dedupKey] = true

    self.discoveryQueue = self.discoveryQueue or {}
    if #self.discoveryQueue >= 25 then
        return false
    end
    local entry = {
        targetName = (parsed and parsed.displayName) or opts.targetName,
        parsed = parsed,
        lookupKey = lk,
        bnetAccountID = opts.bnetAccountID,
        guid = opts.guid,
        allowWhisperReply = opts.allowWhisperReply == true,
        trackKey = "disc:" .. dedupKey,
    }
    if opts.priority == true then
        table.insert(self.discoveryQueue, 1, entry)
    else
        self.discoveryQueue[#self.discoveryQueue + 1] = entry
    end
    if not self._discoveryTimerActive then
        local monoNow = GetTime and GetTime() or time()
        local waitSec = math.max(0.15, DISCOVERY_PING_INTERVAL - (monoNow - (self.lastDiscoveryPingAt or 0)))
        if C_Timer and C_Timer.After then
            self._discoveryTimerActive = true
            C_Timer.After(waitSec, DrainDiscoveryQueue)
        else
            DrainDiscoveryQueue()
        end
    end
    return true
end

function Chat:QueueLoginBNetDiscovery()
    if not self:IsDirectChatEnabled() then return 0 end
    if ns.db and ns.db.settings and ns.db.settings.versionCheck == false then return 0 end
    if ns.Clan and ns.Clan.isStoppedThisSession then return 0 end
    if not GuardAddonMessaging(false) then return 0 end

    local cache = EnsureBNetLookupCache()
    local queued = 0
    local seenAcc = {}
    for _, rec in pairs(cache.byId) do
        if type(rec) == "table" and rec.accId and not seenAcc[rec.accId] then
            seenAcc[rec.accId] = true
            local charParsed = rec.fullChar and Compat.ParseCharacterName(rec.fullChar) or nil
            local lk = charParsed and charParsed.lookupKey or nil
            if not (lk and self:IsLookupKeyVerified(lk)) and not (rec.gId and self.sessionBNetPeers and self.sessionBNetPeers[rec.gId]) then
                if self:QueuePoliteDiscoveryPing({
                    targetName = rec.fullChar,
                    lookupKey = lk,
                    bnetAccountID = rec.accId,
                }) then
                    queued = queued + 1
                end
            end
        end
    end
    return queued
end

function Chat:AbortPendingPresenceProbes()
    if self.pendingPresenceProbes then
        wipe(self.pendingPresenceProbes)
    end
end

function Chat:StopPresenceProbeTicker()
    if self._presenceTicker then
        self._presenceTicker:Cancel()
        self._presenceTicker = nil
    end
end

function Chat:SyncPresenceProbeTicker()
    local watchOff = ns.db and ns.db.settings and ns.db.settings.moduleWatchlistEnabled == false
    if watchOff then
        self:StopPresenceProbeTicker()
        return
    end
    local inInst = IsInInstance and Safe.Value(Safe.Call(IsInInstance)) == true
    local isTrial = IsTrialAccount and Safe.Value(Safe.Call(IsTrialAccount)) == true
    if inInst or isTrial then
        self:StopPresenceProbeTicker()
        return
    end
    local list = Store and Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasList = (type(list) == "table" and next(list) ~= nil)
    local hasPending = (type(self.pendingPresenceProbes) == "table" and next(self.pendingPresenceProbes) ~= nil)
    local hasUrgent = (type(self.urgentPresenceQueue) == "table" and #self.urgentPresenceQueue > 0)
    if not (hasList or hasPending or hasUrgent) then
        self:StopPresenceProbeTicker()
        return
    end
    if self._presenceTicker or not (C_Timer and C_Timer.NewTicker) then
        return
    end
    self._presenceTicker = C_Timer.NewTicker(2.0, function()
        local wOff = ns.db and ns.db.settings and ns.db.settings.moduleWatchlistEnabled == false
        local instNow = IsInInstance and Safe.Value(Safe.Call(IsInInstance)) == true
        local wl = Store and Store.GetWatchlistTable and Store:GetWatchlistTable()
        local anyWork = (type(wl) == "table" and next(wl) ~= nil)
            or (type(Chat.pendingPresenceProbes) == "table" and next(Chat.pendingPresenceProbes) ~= nil)
            or (type(Chat.urgentPresenceQueue) == "table" and #Chat.urgentPresenceQueue > 0)
        if wOff or instNow or not anyWork then
            Chat:StopPresenceProbeTicker()
            return
        end
        Chat:StepPresenceProbes()
    end)
end

function Chat:QueuePresenceProbe(lookupKey, displayName, urgent)
    if ns.db and ns.db.settings and ns.db.settings.moduleWatchlistEnabled == false then
        return false
    end
    local raw = (type(displayName) == "string" and displayName ~= "") and displayName or lookupKey
    if type(raw) ~= "string" or raw == "" then
        return false
    end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(raw)
    if not parsed or not parsed.surname or parsed.surname == "" then
        return false
    end
    if Compat.IsMe and Compat.IsMe(parsed.displayName) then
        return false
    end
    self.lastPresenceProbedAt = self.lastPresenceProbedAt or {}
    if urgent then
        self.lastPresenceProbedAt[parsed.lookupKey] = nil
        self.urgentPresenceQueue = self.urgentPresenceQueue or {}
        for _, q in ipairs(self.urgentPresenceQueue) do
            if q.lookupKey == parsed.lookupKey then
                return true
            end
        end
        if #self.urgentPresenceQueue < 30 then
            table.insert(self.urgentPresenceQueue, {
                lookupKey = parsed.lookupKey,
                displayName = parsed.displayName,
            })
        end
    end
    self:SyncPresenceProbeTicker()
    return true
end

function Chat:StepPresenceProbes()
    if ns.db and ns.db.settings and ns.db.settings.moduleWatchlistEnabled == false then
        self:AbortPendingPresenceProbes()
        return false
    end
    local monoNow = (GetTime and GetTime()) or 0
    if self._presenceReadyMono and monoNow < self._presenceReadyMono then
        return false
    end
    if ns.Clan and (ns.Clan.isStoppedThisSession or (ns.Clan.backoffUntil and monoNow < ns.Clan.backoffUntil)) then
        self:AbortPendingPresenceProbes()
        return false
    end

    self.pendingPresenceProbes = self.pendingPresenceProbes or {}
    self.lastPresenceProbedAt = self.lastPresenceProbedAt or {}

    local hasPending = next(self.pendingPresenceProbes) ~= nil
    local lastOut = math.max(self.lastDiscoveryPingAt or 0, self.lastPresenceProbeSentAt or 0)
    local hasUrgent = (self.urgentPresenceQueue and #self.urgentPresenceQueue > 0) == true
    if (not hasPending) and (not hasUrgent) and (monoNow - lastOut) < 5.2 then
        return false
    end

    local list = Store and Store.GetWatchlistTable and Store:GetWatchlistTable()
    if (not hasPending) and (type(list) ~= "table" or next(list) == nil) then
        return false
    end

    if not GuardAddonMessaging(false) then
        self:AbortPendingPresenceProbes()
        return false
    end
    if (IsInInstance and Safe.Value(Safe.Call(IsInInstance)) == true)
        or (IsTrialAccount and Safe.Value(Safe.Call(IsTrialAccount)) == true)
    then
        self:AbortPendingPresenceProbes()
        return false
    end

    local function IsAuthoritativeOffline(lk, disp, guid)
        if Store and Store.guildOfflineByLookup and Store.guildOfflineByLookup[lk] == true then
            return true, "guild"
        end
        local dirRow = Store and Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lk]
        if dirRow and dirRow.sources and dirRow.sources.friend == true and dirRow.friendOnline ~= true then
            return true, "friend"
        end
        if Compat.GetMyGroupMemberConnection and Compat.GetMyGroupMemberConnection(disp, guid) == false then
            return true, "group"
        end
        return false, nil
    end

    for lk, pRec in pairs(self.pendingPresenceProbes) do
        if type(pRec) == "table" and (monoNow - (pRec.sentAt or 0)) >= 3.8 then
            self.pendingPresenceProbes[lk] = nil
            local isAuthOff, authOffSrc = IsAuthoritativeOffline(lk, pRec.displayName)
            if isAuthOff then
                if Store and Store.SyncWatchlistObservation then
                    Store:SyncWatchlistObservation(pRec.displayName, {
                        online = false,
                        source = authOffSrc or "probe",
                    })
                end
            else
                self.seenOnlineChars[lk] = time()
                if self.sessionOfflineChars then self.sessionOfflineChars[lk] = nil end
                if Store and Store.SyncWatchlistObservation then
                    Store:SyncWatchlistObservation(pRec.displayName, {
                        online = true,
                        source = "probe",
                    })
                end
            end
            if ns.Social and ns.Social.QueueScan then
                ns.Social:QueueScan(0.25)
            end
        end
    end

    if (monoNow - lastOut) < 5.2 then
        return false
    end

    if type(list) ~= "table" or next(list) == nil then
        return false
    end

    local function IsKnownCrossFaction(lk)
        local dirRow = Store and Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lk]
        if dirRow and dirRow.sameFaction == false then return true end
        local bInfo = ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(lk)
        if bInfo and bInfo.sameFaction == false then return true end
        return false
    end

    local function IsRosterConfirmed(lk, disp, guid)
        local socRow = Store and Store.socialByLookup and Store.socialByLookup[lk]
        if socRow and socRow.online == true then
            if socRow.friendOnline == true or socRow.guildOnline == true or (socRow.bnetOnline == true and socRow.bnetState == "wow_forever") then
                return true
            end
        end
        if Compat.GetMyGroupMemberConnection then
            local grpConn = Compat.GetMyGroupMemberConnection(disp, guid)
            if grpConn == true then
                return true
            elseif grpConn == false then
                local wlEntry = list and list[lk]
                if wlEntry and wlEntry.status ~= "offline" and Store and Store.SyncWatchlistObservation then
                    local hasOtherAltOn = (wlEntry.watchAllAlts == true and wlEntry.activeAltLookup and wlEntry.activeAltLookup ~= lk and wlEntry.status == "online")
                    if not hasOtherAltOn then
                        Store:SyncWatchlistObservation(wlEntry.displayName or disp, {
                            online = false,
                            guid = guid or wlEntry.guid,
                            source = "group",
                        })
                    end
                end
                return true
            end
        elseif Compat.IsInMyGroup and Compat.IsInMyGroup(disp, guid) then
            return true
        end
        local isAuthOff, authOffSrc = IsAuthoritativeOffline(lk, disp, guid)
        if isAuthOff then
            local wlEntry = list and list[lk]
            if wlEntry and wlEntry.status ~= "offline" and Store and Store.SyncWatchlistObservation then
                local hasOtherAltOn = (wlEntry.watchAllAlts == true and wlEntry.activeAltLookup and wlEntry.activeAltLookup ~= lk and wlEntry.status == "online")
                if not hasOtherAltOn then
                    Store:SyncWatchlistObservation(wlEntry.displayName or disp, {
                        online = false,
                        guid = guid or wlEntry.guid,
                        source = authOffSrc,
                    })
                end
            end
            return true
        end
        return false
    end

    local chosenLk, chosenDisp = nil, nil
    if self.urgentPresenceQueue and #self.urgentPresenceQueue > 0 then
        while #self.urgentPresenceQueue > 0 do
            local item = table.remove(self.urgentPresenceQueue, 1)
            if item and item.lookupKey and item.displayName
                and not self.pendingPresenceProbes[item.lookupKey]
                and not IsKnownCrossFaction(item.lookupKey)
                and not IsRosterConfirmed(item.lookupKey, item.displayName)
            then
                chosenLk = item.lookupKey
                chosenDisp = item.displayName
                break
            end
        end
    end

    if not chosenLk then
        local bestTier, bestFav, bestAt = 99, -1, nil
        local function considerCand(cLk, cDisp, isFav, statusStr, isStaleSettled)
            if not cLk or not cDisp or self.pendingPresenceProbes[cLk] then return end
            if not cDisp:find(" ", 1, true) then return end
            if Compat.IsMe and Compat.IsMe(cDisp) then return end
            if IsKnownCrossFaction(cLk) then return end
            if IsRosterConfirmed(cLk, cDisp) then return end
            local lastAt = self.lastPresenceProbedAt[cLk]
            local tier = nil
            if not lastAt or statusStr == "unknown" or isStaleSettled then
                if not lastAt or (monoNow - lastAt) >= 15 then
                    tier = 1
                end
            elseif statusStr == "online" then
                if (monoNow - lastAt) >= 35 then
                    tier = 2
                end
            else
                if (monoNow - lastAt) >= 45 then
                    tier = 3
                end
            end
            if not tier then return end
            local favRank = isFav and 1 or 0
            local atVal = lastAt or 0
            if tier < bestTier
                or (tier == bestTier and favRank > bestFav)
                or (tier == bestTier and favRank == bestFav and (not bestAt or atVal < bestAt))
            then
                bestTier = tier
                bestFav = favRank
                bestAt = atVal
                chosenLk = cLk
                chosenDisp = cDisp
            end
        end

        for wlKey, entry in pairs(list) do
            if type(entry) == "table" and not entry.isSessionBNet then
                local eKey = entry.id or wlKey
                local actKey = (entry.watchAllAlts == true and entry.activeAltLookup) or eKey
                local actDisp = (entry.watchAllAlts == true and entry.activeAltName) or entry.displayName
                if not IsRosterConfirmed(eKey, entry.displayName, entry.guid)
                    and not (actKey ~= eKey and IsRosterConfirmed(actKey, actDisp))
                then
                    local isFav = (entry.favorite == true) or (Store.IsSocialFavorite and Store:IsSocialFavorite(eKey) == true)
                    local primDisp = (entry.surname and entry.surname ~= "" and entry.displayName)
                        or (type(entry.observedCandidate) == "string" and entry.observedCandidate:find(" ", 1, true) and entry.observedCandidate)
                        or nil
                    if primDisp then
                        local pParsed = Compat.ParseCharacterName(primDisp)
                        if pParsed and pParsed.lookupKey then
                            considerCand(pParsed.lookupKey, pParsed.displayName, isFav, entry.status, entry._staleSettled == true)
                        end
                    end
                    if entry.watchAllAlts == true and Store.GetAllLinkedCharacters then
                        for _, altRec in ipairs(Store:GetAllLinkedCharacters(eKey)) do
                            if altRec and altRec.lookupKey and altRec.displayName and altRec.displayName:find(" ", 1, true) then
                                local altStatus = (entry.status == "online" and entry.activeAltLookup == altRec.lookupKey) and "online"
                                    or ((entry.status == "unknown") and "unknown" or "offline")
                                considerCand(altRec.lookupKey, altRec.displayName, isFav, altStatus, entry._staleSettled == true)
                            end
                        end
                    end
                end
            end
        end
    end

    if not chosenLk or not chosenDisp then
        return false
    end

    local probeRec = {
        lookupKey = chosenLk,
        displayName = chosenDisp,
        sentAt = monoNow,
    }
    self.lastPresenceProbeSentAt = monoNow
    self.lastPresenceProbedAt[chosenLk] = monoNow
    self.pendingPresenceProbes[chosenLk] = probeRec

    local payload = self:BuildDirectPresencePayload("DPING")
    local sentOk = SendRoomPacket(chosenDisp, nil, payload, 0, {
        allowBNet = false,
        sendAllCandidates = false,
        forceAllCandidates = false,
        trackCandidateKey = "wprobe:" .. chosenLk,
    })
    if not sentOk then
        self.pendingPresenceProbes[chosenLk] = nil
        return false
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(3.8, function()
            if Chat.pendingPresenceProbes and Chat.pendingPresenceProbes[chosenLk] == probeRec then
                Chat.pendingPresenceProbes[chosenLk] = nil
                if GuardAddonMessaging(false)
                    and not (IsInInstance and Safe.Value(Safe.Call(IsInInstance)) == true)
                then
                    local isAuthOff, authOffSrc = IsAuthoritativeOffline(chosenLk, chosenDisp)
                    if isAuthOff then
                        if Store and Store.SyncWatchlistObservation then
                            Store:SyncWatchlistObservation(chosenDisp, {
                                online = false,
                                source = authOffSrc or "probe",
                            })
                        end
                    else
                        Chat.seenOnlineChars[chosenLk] = time()
                        if Chat.sessionOfflineChars then Chat.sessionOfflineChars[chosenLk] = nil end
                        if Store and Store.SyncWatchlistObservation then
                            Store:SyncWatchlistObservation(chosenDisp, {
                                online = true,
                                source = "probe",
                            })
                        end
                    end
                    if ns.Social and ns.Social.QueueScan then
                        ns.Social:QueueScan(0.25)
                    end
                end
            end
        end)
    end
    return true
end

function Chat:VerifyBeforeOfficialSend(threadKey)
    local t = threadKey and self.threads[threadKey]
    if not t then return false end

    self.pendingOfficialOpen = self.pendingOfficialOpen or {}
    self.pendingOfficialOpen[threadKey] = nil
    if STATIC_CHANNEL_ORDER[threadKey] or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") or not self:IsDirectChatEnabled() then
        return self:OpenOfficialChatForThread(threadKey)
    end

    local st = self:GetPeerAddonState(threadKey)
    if st and st.verified then
        ns:Emit("CHAT_UPDATED")
        return true
    end

    return self:OpenOfficialChatForThread(threadKey)
end

function Chat:OpenDirectConversation(opts)
    if type(opts) ~= "table" then return nil end
    local t
    if opts.bnetAccountID then
        local bnetId = Safe.Number(opts.bnetAccountID)
        local gId, fullChar, accName, canonId = FindBNetWoWGameAccount(bnetId)
        local resolvedId = canonId or bnetId
        local bnetName = Safe.String(opts.bnetName) or accName or ("BNet #" .. tostring(resolvedId))
        local charParsed = fullChar and Compat.ParseCharacterName(fullChar)
        local linked = FindLinkedDirectThread(charParsed, resolvedId)
        local charFac = charParsed and self:GetKnownCharacterFaction(charParsed.displayName, nil, resolvedId)
        local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
        local sameFacOk = (not charFac or not myFac) and true or (charFac == myFac)
        local threadKey = (linked and linked.key)
            or (charParsed and charParsed.surname and sameFacOk and ("w:" .. charParsed.lookupKey))
            or ("bn:" .. tostring(resolvedId))
        local threadKind = (linked and linked.kind) or (threadKey:sub(1, 2) == "w:" and "WHISPER" or "BN_WHISPER")
        local threadTitle = (linked and linked.title and linked.title ~= "" and linked.title)
            or (threadKind == "WHISPER" and charParsed and charParsed.displayName)
            or bnetName
        local targetForEnsure = (linked and linked.targetName and linked.targetName ~= "") and linked.targetName or (fullChar or opts.targetName)
        t = EnsureThread(threadKey, threadKind, threadTitle, {
            bnetAccountID = resolvedId,
            bnetName = bnetName,
            targetName = targetForEnsure,
            classFile = opts.classFile or (charParsed and LookupClassFromCache(charParsed.lookupKey)),
            faction = charFac,
        })
        if gId and self.sessionBNetPeers[gId] and t then
            -- Already known active via BNet session table.
        end
    elseif opts.targetName and opts.targetName ~= "" then
        t = self:EnsureWhisperThread(opts.targetName, opts.classFile)
    end

    if not t then return nil end
    self:SetActiveThread(t.key)
    if type(opts.draftText) == "string" and opts.draftText ~= "" then
        self.pendingDraftText = Compat.CleanInput(opts.draftText)
        self.focusInputPending = true
    end
    if opts.autoProbe == true then
        local st = self:GetPeerAddonState(t.key)
        if st and (st.state == "registered" or st.state == "unprobed") then
            self:ProbePeerAddon(t.key, false)
        end
    elseif opts.autoProbe ~= false and self:ShouldAutoProbe(t.key) then
        self:ProbePeerAddon(t.key, false)
    end
    ns:Emit("CHAT_UPDATED")
    return t.key
end

function Chat:CloseBlizzardFriendsHostIfOpen()
    local inC = (_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
    if inC then return end
    for _, host in ipairs({ _G.FriendsFrame, _G.SocialUIFrame }) do
        if host and host.IsShown and host:IsShown()
            and not (host.IsForbidden and host:IsForbidden())
            and not (host.IsProtected and host:IsProtected())
            and host.Hide
        then
            pcall(host.Hide, host)
        end
    end
end

function Chat:ResolveTargetOnlineStatus(opts)
    if type(opts) ~= "table" then
        return nil, nil
    end
    local targetName = opts.targetName
    local bnetAccId = opts.bnetAccountID
    local bnetName = opts.bnetName
    local lookupOrTarget = opts.lookupKey or targetName
    local normLookup = lookupOrTarget and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(lookupOrTarget) or nil
    local dispName = targetName or bnetName or lookupOrTarget

    if targetName and targetName ~= "" and Compat and Compat.IsInMyGroup and Compat.IsInMyGroup(targetName) then
        local totalGrp = (_G.GetNumGroupMembers and Safe.Number(Safe.Call(_G.GetNumGroupMembers))) or 0
        local prefix = (Compat.IsInRaid and Compat.IsInRaid()) and "raid" or "party"
        for i = 1, totalGrp do
            local unit = (prefix == "party" and i == totalGrp) and "player" or (prefix .. tostring(i))
            if _G.UnitExists and Safe.Value(_G.UnitExists(unit)) == true then
                local rawU, rawR = Safe.Call(_G.UnitName, unit)
                local uName = Safe.String(rawU)
                local uRealm = Safe.String(rawR)
                if uName and uRealm and uRealm ~= "" then
                    uName = uName .. "-" .. uRealm
                end
                local uLk = uName and Compat.ParseCharacterFields and Compat.ParseCharacterFields(uName) or nil
                if normLookup and uLk == normLookup then
                    local conn = _G.UnitIsConnected and Safe.Value(_G.UnitIsConnected(unit))
                    if conn == false then
                        return false, uName or dispName
                    end
                    return true, uName or dispName
                end
            end
        end
        return true, dispName
    end

    if normLookup and normLookup ~= "" then
        if _G.C_FriendList and _G.C_FriendList.GetNumFriends and _G.C_FriendList.GetFriendInfoByIndex then
            local count = Safe.Number(Safe.Call(_G.C_FriendList.GetNumFriends)) or 0
            for i = 1, count do
                local f = Safe.Call(_G.C_FriendList.GetFriendInfoByIndex, i)
                if type(f) == "table" then
                    local rawName = Safe.String(f.name)
                    local fLk = rawName and Compat.ParseCharacterFields and Compat.ParseCharacterFields(rawName) or nil
                    if fLk and fLk == normLookup then
                        local isConn = Safe.Value(f.connected) == true
                        return isConn, rawName or dispName
                    end
                end
            end
        elseif _G.GetNumFriends and _G.GetFriendInfo then
            local count = Safe.Number(Safe.Call(_G.GetNumFriends)) or 0
            for i = 1, count do
                local okF, rawName, _, _, _, connected = pcall(_G.GetFriendInfo, i)
                if okF then
                    local sName = Safe.String(rawName)
                    local fLk = sName and Compat.ParseCharacterFields and Compat.ParseCharacterFields(sName) or nil
                    if fLk and fLk == normLookup then
                        local isConn = (connected == true or connected == 1)
                        return isConn, sName or dispName
                    end
                end
            end
        end
    end

    if (not bnetAccId) and normLookup and ns.Social and ns.Social.GetBNetLinkInfo then
        local bInfo = ns.Social:GetBNetLinkInfo(normLookup)
        if bInfo and bInfo.bnetAccountID then
            bnetAccId = bInfo.bnetAccountID
            if not bnetName then bnetName = bInfo.bnetName end
        end
    end
    if bnetAccId and _G.C_BattleNet then
        local acc = _G.C_BattleNet.GetAccountInfoByID and Safe.Call(_G.C_BattleNet.GetAccountInfoByID, bnetAccId) or nil
        if type(acc) ~= "table" and _G.BNGetNumFriends and _G.C_BattleNet.GetFriendAccountInfo then
            local totalBn = Safe.Number(Safe.Call(_G.BNGetNumFriends)) or 0
            for i = 1, totalBn do
                local cand = Safe.Call(_G.C_BattleNet.GetFriendAccountInfo, i)
                if type(cand) == "table" and Safe.Number(cand.bnetAccountID) == bnetAccId then
                    acc = cand
                    break
                end
            end
        end
        if type(acc) == "table" then
            local accName = Safe.String(acc.accountName) or bnetName or dispName
            local ga = type(acc.gameAccountInfo) == "table" and acc.gameAccountInfo or nil
            if ga and Safe.Value(ga.isOnline) == true then
                return true, dispName or accName
            end
            return false, dispName or accName
        end
    end

    if normLookup and normLookup ~= "" and _G.IsInGuild and _G.IsInGuild() and _G.GetNumGuildMembers and _G.GetGuildRosterInfo then
        local totalG = Safe.Number(Safe.Call(_G.GetNumGuildMembers)) or 0
        for i = 1, totalG do
            local okG, gName, _, _, _, _, _, _, _, gOnline = pcall(_G.GetGuildRosterInfo, i)
            if okG then
                local sName = Safe.String(gName)
                local gLk = sName and Compat.ParseCharacterFields and Compat.ParseCharacterFields(sName) or nil
                if gLk and gLk == normLookup then
                    local parsedG = Compat.ParseCharacterName and Compat.ParseCharacterName(sName) or nil
                    return (gOnline == true), (parsedG and parsedG.displayName) or dispName
                end
            end
        end
    end

    if opts.online == false or opts.isOnline == false then
        return false, dispName
    end
    if normLookup and ns.Social and ns.Social.GetDirectoryEntry then
        local dir = ns.Social:GetDirectoryEntry(normLookup)
        if type(dir) == "table" and dir.sources and (dir.sources.friend or dir.sources.guild or dir.sources.bnet) then
            if dir.online == false then
                return false, dir.displayName or dispName
            elseif dir.online == true then
                return true, dir.displayName or dispName
            end
        end
    end
    return nil, dispName
end

function Chat:NotifyTargetOffline(targetDisplay)
    local who = (type(targetDisplay) == "string" and targetDisplay ~= "") and targetDisplay or L["Player"]
    local msg = string.format(L["%s is offline right now."], who)
    ns:Print("%s", msg)
    if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
        pcall(_G.UIErrorsFrame.AddMessage, _G.UIErrorsFrame, msg, 1.0, 0.35, 0.35, 1.0)
    end
    if ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.ShowInlineNotice then
        ns.QuickReply:ShowInlineNotice(msg)
    end
end

--- Route a player message/conversation action to Official WoW Chat (when Official Chat Mode is chosen),
--- Quick Reply (when enabled in SocialCentral Chat Mode), or the standalone Main Window Conversations tab.
function Chat:OpenPreferredConversation(opts)
    if type(opts) ~= "table" then return false end
    local targetName = opts.targetName
    local bnetAccId = opts.bnetAccountID
    local bnetName = opts.bnetName
    local draftText = opts.draftText
    local isOnline, resolvedWho = self:ResolveTargetOnlineStatus(opts)
    if isOnline == false then
        self:NotifyTargetOffline(resolvedWho or targetName or bnetName)
        return false
    end
    local isCrossFaction = opts.isCrossFaction == true
    local preferBNetOfficial = opts.preferBNetOfficial == true
    local chatModOn = (not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
    local isOfficialMode = (Compat and Compat.IsOfficialChatMode and Compat.IsOfficialChatMode()) == true

    if isOfficialMode or not chatModOn then
        if (isCrossFaction or preferBNetOfficial or not targetName or targetName == "") and bnetName and Compat and Compat.BNetWhisper then
            return Compat.BNetWhisper(bnetName, targetName, draftText)
        elseif targetName and targetName ~= "" and Compat and Compat.Whisper then
            return Compat.Whisper(targetName, draftText)
        end
        return false
    end

    local lookupOrTarget = opts.lookupKey or targetName
    local scConfirmed = (opts.scConfirmed == true)
        or (self.IsPlayerAddonConfirmed and self:IsPlayerAddonConfirmed(lookupOrTarget, bnetAccId)) == true
    local qrEnabled = (not ns.db or not ns.db.settings or ns.db.settings.quickReplyEnabled ~= false)
    local hasAddonRoute = scConfirmed or opts.forceAddonChat == true or (not isCrossFaction and not preferBNetOfficial and targetName and targetName ~= "") or (bnetAccId ~= nil)

    if hasAddonRoute then
        local threadKey = self:OpenDirectConversation({
            targetName = targetName,
            bnetAccountID = bnetAccId,
            bnetName = bnetName,
            classFile = opts.classFile,
            autoProbe = opts.autoProbe,
            draftText = draftText,
        })
        if threadKey then
            if qrEnabled and not opts.forceMainWindow and ns.QuickReply and ns.QuickReply.OpenThread then
                local qrDraft = self.pendingDraftText or draftText
                if self.pendingDraftThreadKey == nil or self.pendingDraftThreadKey == threadKey then
                    self.pendingDraftText = nil
                    self.pendingDraftThreadKey = nil
                    self.focusInputPending = nil
                end
                self:CloseBlizzardFriendsHostIfOpen()
                if ns.QuickReply:OpenThread(threadKey, true, qrDraft) then
                    return true
                end
                if qrDraft and qrDraft ~= "" then
                    self.pendingDraftText = qrDraft
                    self.pendingDraftThreadKey = threadKey
                    self.focusInputPending = true
                end
            end
            if ns.UI and ns.UI.ShowHub then
                self.focusInputPending = true
                if ns.UI.SetChatNavigation then
                    ns.UI:SetChatNavigation({ chatThreadKey = threadKey })
                end
                ns.UI:ShowHub("chat")
                return true
            elseif ns.UI and ns.UI.OpenTab then
                self.focusInputPending = true
                ns.UI:OpenTab("chat")
                return true
            end
        end
    end

    if (isCrossFaction or preferBNetOfficial or not targetName or targetName == "") and bnetName and Compat and Compat.BNetWhisper then
        return Compat.BNetWhisper(bnetName, targetName, draftText)
    elseif targetName and targetName ~= "" and Compat and Compat.Whisper then
        return Compat.Whisper(targetName, draftText)
    end
    return false
end

local function SendDirectPacket(self, t, state, payload)
    local bnetConfirmed = state.bnetGameAccId and self.sessionBNetPeers and self.sessionBNetPeers[state.bnetGameAccId] ~= nil
    local target = state.targetChar or t.targetName
    local extra = (state.rawTargetChar and state.rawTargetChar ~= target) and { state.rawTargetChar } or nil
    local tLk = target and Compat.ParseCharacterFields(target) or nil
    local hasResolved = tLk and self.resolvedWhisperTargets and self.resolvedWhisperTargets[tLk] ~= nil
    local sendOpts = {
        trackCandidateKey = t.key,
        extraCandidates = extra,
        allowBNet = (state.bnetGameAccId ~= nil),
        sendAllCandidates = true,
        forceAllCandidates = not hasResolved,
    }
    if bnetConfirmed then
        local sent = SendRoomPacket(nil, state.bnetGameAccId, payload, nil, sendOpts)
        if not sent and target then
            sent = SendRoomPacket(target, nil, payload, nil, sendOpts)
        end
        return sent
    end
    if (target and target ~= "") or state.bnetGameAccId then
        return SendRoomPacket(target, state.bnetGameAccId, payload, nil, sendOpts)
    end
    return false
end

function Chat:SendDirectMessage(threadKey, rawText)
    if not GuardAddonMessaging(true) then
        return false
    end

    local t = threadKey and self.threads[threadKey]
    if not t or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") then
        return false
    end

    local state = self:GetPeerAddonState(threadKey)
    if not state.verified then
        ns:Print(L["Direct addon chat requires both players to have SocialCentral active."])
        return false
    end

    local cleanText = Compat.CleanPayloadField(EncodeAddonHyperlinks(rawText), 175)
    if cleanText == "" then
        return false
    end

    local monoNow = GetTime and GetTime() or time()
    if (monoNow - (self.lastDirectSendAt or 0)) < DIRECT_SEND_COOLDOWN then
        ns:Print(L["Please wait a moment before sending another message."])
        return false
    end
    self.lastDirectSendAt = monoNow

    local meDisplay = GetMyInfo()
    local senderShort = NonEmptyField(meDisplay, 36, meDisplay)
    local msgId = NextMsgId()
    local headerLen = #("DM|" .. msgId .. "|" .. senderShort .. "|")
    local maxBody = MAX_PAYLOAD_BYTES - headerLen
    if maxBody <= 4 then
        return false
    end
    if #cleanText > maxBody then
        cleanText = Compat.CleanPayloadField(cleanText, maxBody)
    end
    local payload = "DM|" .. msgId .. "|" .. senderShort .. "|" .. cleanText

    local sent = SendDirectPacket(self, t, state, payload)

    if not sent then
        ns:Print(L["Unable to send addon message right now; peer may be offline or throttled."])
        return false
    end

    local activePeerChar = state.targetChar or t.targetName or t.title
    if t.kind == "WHISPER" and activePeerChar and not (state.bnetGameAccId and self.sessionBNetPeers and self.sessionBNetPeers[state.bnetGameAccId]) then
        local parsedTarget = Compat.ParseCharacterName(activePeerChar)
        local bInfo = parsedTarget and ns.Social and ns.Social.GetBNetLinkInfo and ns.Social:GetBNetLinkInfo(parsedTarget.lookupKey)
        self.lastManualWhisperSend = {
            threadKey = threadKey,
            targetStr = activePeerChar,
            targetDisplay = (parsedTarget and parsedTarget.displayName) or activePeerChar,
            senderDisplay = meDisplay,
            lookupKey = parsedTarget and parsedTarget.lookupKey or nil,
            text = rawText,
            bnetAccountID = t.bnetAccountID or (bInfo and bInfo.bnetAccountID),
            bnetName = t.bnetName or (bInfo and bInfo.bnetName),
            sentAt = monoNow,
            isAddonDirect = true,
        }
    end

    local _, myClass = Safe.Call(UnitClass, "player")
    local entry = AppendMessage(t, senderShort, cleanText, false, Safe.String(myClass), t.kind == "BN_WHISPER", true, {
        viaAddon = true,
        echoToOfficial = true,
        deliveryMsgId = msgId,
        deliveryState = "sent",
        targetChar = activePeerChar,
    })
    TrackDeliveryEntry(self, msgId, t.key, entry)
    if state.state == "registered" and C_Timer and C_Timer.After then
        local parsedPeer = Compat.ParseCharacterName(activePeerChar or "")
        local peerLk = parsedPeer and parsedPeer.lookupKey
        local peerDisp = (parsedPeer and parsedPeer.displayName) or t.title or state.targetChar or "?"
        if peerLk then
            C_Timer.After(3.5, function()
                local rec = Chat.deliveryIndex and Chat.deliveryIndex[msgId]
                if not rec then return end
                Chat.deliveryIndex[msgId] = nil
                if entry then
                    entry.deliveryState = "off"
                end
                Chat.sessionUnverifiedPeers = Chat.sessionUnverifiedPeers or {}
                Chat.sessionUnverifiedPeers[peerLk] = true
                Chat:BumpPeerStateGen()
                if not Chat.pendingDraftText or Chat.pendingDraftText == "" then
                    Chat.pendingDraftText = rawText
                    Chat.pendingDraftThreadKey = t.key
                end
                Chat.focusInputPending = true
                AppendMessage(t, L["System"], string.format(L["No addon reply from %s — switched to standard WoW whisper for your next send."], peerDisp), false, nil, true, true, {
                    isStatusNotice = true,
                    statusKind = "ADDON_FALLBACK",
                })
                ns:Emit("CHAT_UPDATED")
            end)
        end
    end
    return true
end

function Chat:SendLocationPing(threadKey)
    if not GuardAddonMessaging(true) then
        return false
    end

    local t = threadKey and self.threads[threadKey]
    if not t or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") then
        return false
    end
    local state = self:GetPeerAddonState(threadKey)
    if not state.verified then
        ns:Print(L["Direct addon chat requires both players to have SocialCentral active."])
        return false
    end

    local monoNow = GetTime and GetTime() or time()
    if (monoNow - (self.lastDirectSendAt or 0)) < DIRECT_SEND_COOLDOWN then
        ns:Print(L["Please wait a moment before sending another message."])
        return false
    end
    self.lastDirectSendAt = monoNow

    local zone = NonEmptyField(Compat.CurrentZoneName(), 48, "Azeroth")
    local px, py = 0, 0
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapID = Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player"))
        if mapID and mapID > 0 then
            local pos = Safe.Call(C_Map.GetPlayerMapPosition, mapID, "player")
            if pos and pos.GetXY then
                local x, y = pos:GetXY()
                if x and y then
                    px = math.floor(x * 100 + 0.5)
                    py = math.floor(y * 100 + 0.5)
                end
            end
        end
    end

    local meDisplay = GetMyInfo()
    local senderShort = NonEmptyField(meDisplay, 36, meDisplay)
    local msgId = NextMsgId()
    local payload = string.format("DPIN|%s|%s|%s|%d|%d", msgId, senderShort, zone, px, py)
    if #payload > MAX_PAYLOAD_BYTES then
        zone = NonEmptyField(zone, math.max(12, 48 - (#payload - MAX_PAYLOAD_BYTES)), "Azeroth")
        payload = string.format("DPIN|%s|%s|%s|%d|%d", msgId, senderShort, zone, px, py)
    end

    local sent = SendDirectPacket(self, t, state, payload)
    if not sent then
        ns:Print(L["Unable to send addon message right now; peer may be offline or throttled."])
        return false
    end

    local coordStr = (px > 0 or py > 0) and string.format("%s (%d, %d)", zone, px, py) or zone
    local localLine = string.format(L["[Location: %s]"], coordStr)
    local _, myClass = Safe.Call(UnitClass, "player")
    local entry = AppendMessage(t, senderShort, localLine, false, Safe.String(myClass), t.kind == "BN_WHISPER", true, {
        viaAddon = true,
        echoToOfficial = true,
        deliveryMsgId = msgId,
        deliveryState = "sent",
        targetChar = state.targetChar or t.targetName or t.title,
    })
    TrackDeliveryEntry(self, msgId, t.key, entry)
    return true
end

function Chat:ResolveBNetGameSender(bnGameAccId)
    if not bnGameAccId then return nil end
    local accId, accName, fullChar = ResolveBNetSender(bnGameAccId)
    return accId, accName, fullChar
end

function Chat:IsSlashCommandText(rawText)
    if type(rawText) ~= "string" then
        return false
    end
    local trimmed = Compat.Trim and Compat.Trim(rawText) or rawText:match("^%s*(.-)%s*$") or ""
    if trimmed == "" or trimmed:sub(1, 2) == "//" then
        return false
    end
    return trimmed:match("^/([^%s]+)") ~= nil
end

function Chat:ExecuteSlashCommand(rawText, isHardwareEvent)
    if not self:IsSlashCommandText(rawText) then
        return false, "not_slash"
    end
    local trimmed = Compat.Trim and Compat.Trim(rawText) or rawText:match("^%s*(.-)%s*$") or ""
    local leadSlash, cmdToken, rest = trimmed:match("^(/([^%s]+))%s*(.-)$")
    if not (leadSlash and cmdToken) then
        return false, "not_slash"
    end
    rest = rest or ""
    if isHardwareEvent ~= true then
        return false, "slash_hardware_only"
    end

    local slashKey = leadSlash:upper()

    if slashKey == "/RELOAD" or slashKey == "/RL" then
        if _G.ReloadUI then
            _G.ReloadUI()
        elseif _G.C_UI and _G.C_UI.Reload then
            _G.C_UI.Reload()
        end
        return true, "slash_executed"
    end

    if slashKey == "/WHO" and ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
        ns:Print(L["/who paused during combat to prevent UI taint."])
        return false, "slash_blocked"
    end

    local function OpenBlizzardChatPrefill(line)
        if type(line) ~= "string" or line == "" then
            return false
        end
        if ns.QuickReply then
            ns.QuickReply._suppressBlizzSlashRedirectUntil = (GetTime and GetTime() or 0) + 0.6
            if ns.QuickReply.PrepareTemporaryOfficialEditBox then
                ns.QuickReply:PrepareTemporaryOfficialEditBox(25)
            end
        end
        local ok = false
        if ChatFrameUtil and ChatFrameUtil.OpenChat then
            ok = pcall(ChatFrameUtil.OpenChat, line)
        elseif ChatFrame_OpenChat then
            ok = pcall(ChatFrame_OpenChat, line)
        end
        if ok and ns.QuickReply and ns.QuickReply.ShowActiveOfficialEditBox then
            ns.QuickReply:ShowActiveOfficialEditBox()
            local activeEb = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
                or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
                or nil
            if activeEb and _G.ChatEdit_ParseText then
                pcall(_G.ChatEdit_ParseText, activeEb, 0)
            end
        end
        return ok
    end

    if _G.hash_SecureCmdList and _G.hash_SecureCmdList[slashKey] ~= nil then
        OpenBlizzardChatPrefill(trimmed)
        ns:Print(L["Protected command opened in Blizzard chat bar — press Enter to run."])
        return true, "slash_prefilled"
    end

    local slashFn = (_G.hash_SlashCmdList and type(_G.hash_SlashCmdList[slashKey]) == "function") and _G.hash_SlashCmdList[slashKey] or nil
    if not slashFn and type(_G.SlashCmdList) == "table" then
        for name, fn in pairs(_G.SlashCmdList) do
            if type(fn) == "function" and type(name) == "string" then
                for i = 1, 16 do
                    local alias = _G["SLASH_" .. name .. tostring(i)]
                    if type(alias) ~= "string" then
                        break
                    end
                    if alias:upper() == slashKey then
                        slashFn = fn
                        break
                    end
                end
                if slashFn then break end
            end
        end
    end
    if slashFn then
        local eb = (_G.ChatEdit_GetLastActiveWindow and _G.ChatEdit_GetLastActiveWindow())
            or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)
            or nil
        local ok = pcall(slashFn, rest, eb)
        if ok then
            return true, "slash_executed"
        end
        OpenBlizzardChatPrefill(trimmed)
        return true, "slash_prefilled"
    end

    local emoteTok = _G.hash_EmoteTokenList and _G.hash_EmoteTokenList[slashKey]
    if emoteTok and _G.DoEmote then
        local ok = pcall(_G.DoEmote, emoteTok, rest ~= "" and rest or nil)
        if ok then
            return true, "slash_executed"
        end
    end

    local safeChanKey = ({
        ["/G"] = "ch:guild",
        ["/GUILD"] = "ch:guild",
        ["/GUILDA"] = "ch:guild",
        ["/H"] = "ch:guild",
        ["/HERMANDAD"] = "ch:guild",
        ["/O"] = "ch:officer",
        ["/OFFICER"] = "ch:officer",
        ["/OFICIAL"] = "ch:officer",
        ["/P"] = "ch:party",
        ["/PARTY"] = "ch:party",
        ["/GRUPO"] = "ch:party",
        ["/RA"] = "ch:raid",
        ["/RAID"] = "ch:raid",
        ["/RAIDE"] = "ch:raid",
        ["/BANDA"] = "ch:raid",
        ["/I"] = "ch:instance",
        ["/INSTANCE"] = "ch:instance",
        ["/INSTANCIA"] = "ch:instance",
        ["/BG"] = "ch:instance",
    })[slashKey]
    if safeChanKey then
        if rest ~= "" then
            local okSent, openMode = self:OpenOfficialChatForThread(safeChanKey, rest, true)
            if okSent then
                return true, (openMode == "sent") and "slash_executed" or "slash_prefilled"
            end
            return false, (openMode == "not_in_group") and "not_in_group" or "slash_blocked"
        elseif ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.OpenThread then
            ns.QuickReply:OpenThread(safeChanKey, false)
            return true, "slash_executed"
        else
            OpenBlizzardChatPrefill(slashKey:lower() .. " ")
            return true, "slash_prefilled"
        end
    end

    if slashKey:match("^/%d+$") then
        local cid = tonumber(slashKey:sub(2))
        local info = cid and self:GetOfficialChannelInfo(cid) or nil
        if info then
            self:SetGeneralTargetChannel(cid)
            if rest ~= "" then
                local okSent, openMode = self:OpenOfficialChatForThread("ch:general", rest, true)
                if okSent then
                    return true, (openMode == "sent") and "slash_executed" or "slash_prefilled"
                end
                return false, "slash_blocked"
            elseif ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.OpenThread then
                ns.QuickReply:OpenThread("ch:general", false)
                return true, "slash_executed"
            end
        end
        if OpenBlizzardChatPrefill(trimmed) then
            return true, "slash_prefilled"
        end
    end

    if slashKey == "/S" or slashKey == "/SAY" or slashKey == "/DIZER" or slashKey == "/DECIR" then
        if rest == "" and ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.OpenThread then
            self:SetGeneralTargetChannel(nil)
            ns.QuickReply:OpenThread("ch:general", false)
            return true, "slash_executed"
        end
        if OpenBlizzardChatPrefill(trimmed) then
            return true, "slash_prefilled"
        end
    end

    if slashKey == "/Y" or slashKey == "/YELL" or slashKey == "/GRITAR" then
        if rest == "" and ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown() and ns.QuickReply.OpenThread then
            self:SetGeneralTargetChannel("yell")
            ns.QuickReply:OpenThread("ch:general", false)
            return true, "slash_executed"
        end
        if OpenBlizzardChatPrefill(trimmed) then
            return true, "slash_prefilled"
        end
    end

    if (slashKey == "/W" or slashKey == "/WHISPER" or slashKey == "/T" or slashKey == "/TELL"
        or slashKey == "/R" or slashKey == "/REPLY")
        and rest ~= "" and ns.QuickReply and ns.QuickReply.ResolveLiveSlashThread
    then
        local wKey, wRest = ns.QuickReply:ResolveLiveSlashThread(trimmed, nil, nil, true)
        if wKey and wRest and wRest ~= "" then
            local okSent, openMode = self:SendOrOpenReply(wKey, wRest, true)
            if okSent ~= false then
                if ns.QuickReply and ns.QuickReply.OpenThread then
                    ns.QuickReply:OpenThread(wKey, false)
                end
                return true, (openMode == "prefilled") and "slash_prefilled" or "slash_executed"
            end
        end
    end

    if OpenBlizzardChatPrefill(trimmed) then
        return true, "slash_prefilled"
    end

    ns:Print(L["Unknown command '%s' — nothing was sent to chat."]:format(leadSlash))
    return false, "slash_unknown"
end

function Chat:SendOrOpenReply(threadKey, rawText, isHardwareEvent)
    if self:IsSlashCommandText(rawText) then
        return self:ExecuteSlashCommand(rawText, isHardwareEvent)
    end
    if not threadKey or threadKey == "mentions:radar" then return false end
    if type(rawText) == "string" and rawText:find("{", 1, true) and self.ExpandQuickReplyText then
        rawText = self:ExpandQuickReplyText(rawText)
    end
    local hasPayload = type(rawText) == "string" and (Compat.CleanInput and Compat.CleanInput(rawText) or rawText) ~= ""
    local sent = false
    local sendMode = nil
    if threadKey == "notes:self" then
        sent = self:SavePersonalNote(rawText)
    elseif threadKey == "ch:alliance" then
        sent = self:SendAllianceMessage(rawText)
    elseif threadKey:sub(1, 5) == "room:" then
        sent = self:SendRoomMessage(threadKey:sub(6), rawText)
    else
        local t = self.threads[threadKey]
        if not t then return false end
        if t.kind == "WHISPER" or t.kind == "BN_WHISPER" then
            local isOnline, resolvedWho = self:ResolveTargetOnlineStatus({
                targetName = t.targetName,
                lookupKey = t.lookupKey,
                bnetAccountID = t.bnetAccountID,
                bnetName = t.bnetName,
            })
            if isOnline == false then
                self:NotifyTargetOffline(resolvedWho or t.title or t.targetName or t.bnetName)
                return false, "target_offline"
            end
        end

        local hasOfficialLink = type(rawText) == "string" and rawText:find("|H", 1, true) and not rawText:find("|Haddon:", 1, true)
        local addonLocked = (ns.Clan and ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked()) == true
        local st = self:GetPeerAddonState(threadKey)
        local handledDirect = false
        if (not addonLocked) and (not hasOfficialLink) and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and st then
            if st.verified == true then
                if st.bnetGameAccId and self.sessionBNetPeers and self.sessionBNetPeers[st.bnetGameAccId] then
                    sent = self:SendDirectMessage(threadKey, rawText)
                    handledDirect = true
                elseif not (t.kind == "WHISPER" and (ResolveBNetRedirectForWhisper(t) or ResolveAltWhisperRedirect(t))) then
                    sent = self:SendDirectMessage(threadKey, rawText)
                    handledDirect = true
                end
            elseif (st.state == "registered" or st.state == "unprobed") and st.state ~= "offline" and st.state ~= "disabled" then
                -- Probe silently in the background so future replies upgrade to [SC] without dropping this message.
                if self:ShouldAutoProbe(threadKey) then
                    self:ProbePeerAddon(threadKey, false)
                end
            end
        end
        if not handledDirect then
            sent, sendMode = self:OpenOfficialChatForThread(threadKey, rawText, isHardwareEvent == true)
        end
    end
    if sent ~= false and hasPayload and ns.QuickReply and ns.QuickReply.RecordRecentSentThread then
        ns.QuickReply:RecordRecentSentThread(threadKey)
    end
    return sent, sendMode
end

function Chat:HandleGuildSystemMessage(rawMsg)
    if (Compat and Compat.IsModuleEnabled and Compat.IsModuleEnabled("chat") == false) then
        return false
    end
    local cleanMsg = Safe and Safe.String and Safe.String(rawMsg) or nil
    if not cleanMsg or cleanMsg == "" then
        return false
    end
    local ev = self:_ParseGuildSystemEvent(cleanMsg)
    if not ev then
        return false
    end
    local inGuild = (Compat and Compat.GuildName and Compat.GuildName() ~= nil)
        or (IsInGuild and IsInGuild() == true)
        or (self.threads and self.threads["ch:guild"] ~= nil)
    if not inGuild then
        return false
    end
    local monoNow = (GetTime and GetTime()) or 0
    local dedupSig = tostring(ev.kind) .. "|" .. tostring(ev.targetLk or ev.target) .. "|" .. tostring(ev.rank or "")
    self._lastGuildSysSigs = self._lastGuildSysSigs or {}
    if self._lastGuildSysSigs[dedupSig] and (monoNow - self._lastGuildSysSigs[dedupSig]) < 8.0 then
        return true
    end
    self._lastGuildSysSigs[dedupSig] = monoNow

    local meta = STATIC_CHANNEL_ORDER["ch:guild"]
    local t = EnsureThread("ch:guild", meta.kind, L[meta.titleKey], { slash = meta.slash })
    local cls = ev.targetLk and LookupClassFromCache(ev.targetLk, nil) or nil
    local isMe = (Compat and Compat.IsMe and Compat.IsMe(ev.target)) and true or false
    local plainDesc
    if ev.kind == "JOIN" then
        plainDesc = string.format(L["%s joined the guild."], ev.target)
    elseif ev.kind == "PROMOTE" then
        plainDesc = string.format(L["%s promoted %s to %s."], ev.actor or L["Guild"], ev.target, ev.rank or "?")
    elseif ev.kind == "DEMOTE" then
        plainDesc = string.format(L["%s updated %s rank to %s."], ev.actor or L["Guild"], ev.target, ev.rank or "?")
    elseif ev.kind == "KICK" then
        plainDesc = string.format(L["%s was removed from the guild by %s."], ev.target, ev.actor or L["Guild"])
    else
        plainDesc = string.format(L["%s left the guild."], ev.target)
    end
    local skipPersist = not self:ShouldSaveGuildHistory()
    AppendMessage(t, L["Guild"], plainDesc, not isMe, cls, skipPersist, true, {
        senderCharName = ev.target,
        replySlash = meta.slash,
        noSenderColon = true,
        guildEventKind = ev.kind,
        guildTarget = ev.target,
        guildActor = ev.actor,
        guildRank = ev.rank,
        guildActionSent = false,
    })
    if ns.QuickReply then
        ns.QuickReply._forceMsgRebuild = true
    end
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:HandleGuildMilestoneHyperlink(threadKey, msgIdx, button, prefillFn)
    local thr = threadKey and self.threads and self.threads[threadKey]
    local entry = (thr and type(thr.messages) == "table" and msgIdx) and thr.messages[tonumber(msgIdx) or -1] or nil
    if not (type(entry) == "table" and entry.guildEventKind) then
        return false
    end
    local replyText = self:BuildGuildMilestoneReplyText(entry)
    if not replyText or replyText == "" then
        return false
    end
    if button == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) or entry.guildActionSent then
        if type(prefillFn) == "function" then
            prefillFn(replyText)
            return true
        end
        return self:OpenOfficialChatForThread(threadKey, replyText, false)
    end
    local ok, sendMode = self:SendOrOpenReply(threadKey, replyText, true)
    if ok ~= false and sendMode == "sent" then
        entry.guildActionSent = true
        self._guildActionRev = (self._guildActionRev or 0) + 1
        if self:ShouldPersistThreadKey(threadKey) and RewriteThreadHistory then
            RewriteThreadHistory(thr)
        end
        if ns.QuickReply then
            ns.QuickReply._forceMsgRebuild = true
        end
        ns:Emit("CHAT_UPDATED")
    end
    return ok, sendMode
end

function Chat:JoinTempWoWChannel(rawName)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    local clean = CleanRoomToken(rawName)
    if not clean then
        ns:Print(L["Enter a valid channel name (letters/numbers)."])
        return false
    end
    if JoinTemporaryChannel then
        pcall(JoinTemporaryChannel, clean)
        self.activeTempChannel = clean
        local id = GetChannelName and Safe.Number(Safe.Call(GetChannelName, clean)) or 0
        if id and id > 0 then
            ns:Print(string.format(L["Joined WoW temp channel /%d (%s)."], id, clean))
            if ns.QuickReply then
                ns.QuickReply._suppressBlizzSlashRedirectUntil = (GetTime and GetTime() or 0) + 0.6
            end
            if ChatFrameUtil and ChatFrameUtil.OpenChat then
                pcall(ChatFrameUtil.OpenChat, "/" .. id .. " ")
            elseif ChatFrame_OpenChat then
                pcall(ChatFrame_OpenChat, "/" .. id .. " ")
            end
        else
            ns:Print(string.format(L["Requested temp channel '%s'."], clean))
        end
        ns:Emit("CHAT_UPDATED")
        return true
    end
    return false
end

function Chat:LeaveTempWoWChannel(rawName)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    local target = CleanRoomToken(rawName or self.activeTempChannel or "")
    if target and LeaveChannelByName then
        pcall(LeaveChannelByName, target)
        if self.activeTempChannel == target then
            self.activeTempChannel = nil
        end
        ns:Print(string.format(L["Left WoW temp channel '%s'."], target))
        ns:Emit("CHAT_UPDATED")
        return true
    end
    return false
end

local function IsDuplicateDirectMsg(senderKey, msgId)
    if not msgId or msgId == "" then return false end
    Chat.seenDirectMsgIds = Chat.seenDirectMsgIds or {}
    local nowClock = (GetTime and GetTime()) or 0
    if (nowClock - (Chat._lastDirectDedupPruneAt or 0)) >= 30 then
        Chat._lastDirectDedupPruneAt = nowClock
        for k, ts in pairs(Chat.seenDirectMsgIds) do
            if type(ts) ~= "number" or (nowClock > ts and (nowClock - ts) > 120) then
                Chat.seenDirectMsgIds[k] = nil
            end
        end
    end
    local dedupKey = tostring(senderKey or "?") .. ":" .. tostring(msgId)
    if Chat.seenDirectMsgIds[dedupKey] then
        return true
    end
    Chat.seenDirectMsgIds[dedupKey] = nowClock
    return false
end

local function PickNonClobberTarget(existingThread, newDisplay)
    if not existingThread or not existingThread.targetName or existingThread.targetName == "" then
        return newDisplay
    end
    if not newDisplay or newDisplay == "" then
        return existingThread.targetName
    end
    local eLk, eFirst, _, eSur = Compat.ParseCharacterFields(existingThread.targetName)
    local nLk, nFirst, _, nSur = Compat.ParseCharacterFields(newDisplay)
    if eLk and nLk and eLk == nLk then
        return newDisplay
    end
    if eFirst and nFirst and eFirst:lower() == nFirst:lower() and nSur and not eSur then
        return newDisplay
    end
    return existingThread.targetName
end

local function EnsureIncomingDirectThread(senderRaw, bnGameAccId)
    if bnGameAccId then
        local bnetAccId, accountName, fullChar = ResolveBNetSender(bnGameAccId)
        if bnetAccId then
            local charParsed = fullChar and Compat.ParseCharacterName(fullChar)
            local cls = charParsed and LookupClassFromCache(charParsed.lookupKey)
            local charFac = charParsed and Chat:GetKnownCharacterFaction(charParsed.displayName, nil, bnetAccId)
            local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
            local sameFacOk = (not charFac or not myFac) and true or (charFac == myFac)
            local linked = FindLinkedDirectThread(charParsed, bnetAccId)
            local key = (linked and linked.key)
                or (charParsed and charParsed.surname and sameFacOk and ("w:" .. charParsed.lookupKey))
                or ("bn:" .. tostring(bnetAccId))
            local kind = (linked and linked.kind) or (key:sub(1, 2) == "w:" and "WHISPER" or "BN_WHISPER")
            local title = (linked and linked.title and linked.title ~= "" and linked.title)
                or (kind == "WHISPER" and charParsed and charParsed.displayName)
                or accountName or fullChar or ("BNet #" .. tostring(bnetAccId))
            local t = EnsureThread(key, kind, title, {
                bnetAccountID = bnetAccId,
                bnetName = accountName,
                targetName = PickNonClobberTarget(linked, fullChar),
                classFile = cls or (linked and linked.classFile),
                faction = charFac,
            })
            return t, charParsed
        end
    end

    local parsedSender = senderRaw and Compat.ParseCharacterName(Safe.String(senderRaw) or "")
    if parsedSender and not Compat.IsMe(parsedSender.displayName) then
        if not parsedSender.surname then
            local upDisp = ResolveChatSenderDisplay(parsedSender.displayName, nil, nil)
            local upParsed = upDisp and Compat.ParseCharacterName(upDisp)
            if upParsed and upParsed.surname and upParsed.surname ~= "" then
                parsedSender = upParsed
            end
        end
        local active = Chat.activeThreadKey and Chat.threads[Chat.activeThreadKey]
        if active and (active.kind == "WHISPER" or active.kind == "BN_WHISPER") then
            local actParsed = Compat.ParseCharacterName(active.targetName or (active.kind == "WHISPER" and active.title) or "")
            if actParsed and (actParsed.lookupKey == parsedSender.lookupKey or ((not parsedSender.surname) and actParsed.firstName:lower() == parsedSender.firstName:lower())) then
                return active, (not parsedSender.surname and actParsed or parsedSender)
            end
        end
        local _, _, bnAccName, bnAccId = FindBNetWoWGameAccountByChar(parsedSender)
        local linked = FindLinkedDirectThread(parsedSender, bnAccId)
        if linked then
            local cls = LookupClassFromCache(parsedSender.lookupKey)
            return EnsureThread(linked.key, linked.kind, linked.title, {
                targetName = PickNonClobberTarget(linked, parsedSender.displayName),
                bnetAccountID = bnAccId or linked.bnetAccountID,
                bnetName = bnAccName or linked.bnetName,
                classFile = linked.classFile or cls,
            }), parsedSender
        end
        local cls = LookupClassFromCache(parsedSender.lookupKey)
        return EnsureThread("w:" .. parsedSender.lookupKey, "WHISPER", parsedSender.displayName, {
            targetName = parsedSender.displayName,
            bnetAccountID = bnAccId,
            bnetName = bnAccName,
            classFile = cls,
        }), parsedSender
    end
    return nil, parsedSender
end

local function HandleIncomingAddonPacket(payloadRaw, senderRaw, bnGameAccId)
    if ns.db and ns.db.settings and ns.db.settings.moduleChatEnabled == false then return end
    local payload = Safe.String(payloadRaw)
    if not payload or payload == "" then return end

    local op = payload:match("^([^|]+)|")
    if not op then return end

    local rawSenderClean = senderRaw and Compat.CleanInput(Safe.String(senderRaw) or "")
    local parsedSender = rawSenderClean and Compat.ParseCharacterName(rawSenderClean)
    local cleanSenderStr = (parsedSender and parsedSender.displayName) or rawSenderClean
    if parsedSender and Compat.IsMe(parsedSender.displayName) then
        return
    end
    local isConfirmedReply = (op == "DPONG" or op == "DMA" or op == "DM" or op == "DPIN")
    if parsedSender and cleanSenderStr and (isConfirmedReply or parsedSender.surname) then
        RecordResolvedWhisperTarget(parsedSender.lookupKey, cleanSenderStr)
    end

    if op == "DPING" or op == "DPONG" then
        local _, peerVer, peerClass, peerLvl, peerZone = strsplit("|", payload, 5)
        Chat:MarkPeerVerified(
            cleanSenderStr or (parsedSender and parsedSender.displayName) or senderRaw,
            bnGameAccId,
            peerVer,
            op,
            peerClass,
            tonumber(peerLvl),
            peerZone
        )
        if op == "DPING" and Chat:IsDirectChatEnabled() then
            if ns.Clan and ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked() then
                return
            end
            local pongKey = bnGameAccId and ("bn:" .. tostring(bnGameAccId)) or (parsedSender and ("w:" .. parsedSender.lookupKey))
            local monoNow = GetTime and GetTime() or time()
            Chat.pongSentAt = Chat.pongSentAt or {}
            if pongKey and (monoNow - (Chat.pongSentAt[pongKey] or 0)) >= PONG_COOLDOWN then
                Chat.pongSentAt[pongKey] = monoNow
                Chat._pongCount = (Chat._pongCount or 0) + 1
                if Chat._pongCount >= 100 then
                    local kept = 0
                    for pk, pts in pairs(Chat.pongSentAt) do
                        if (monoNow - pts) > 300 then
                            Chat.pongSentAt[pk] = nil
                        else
                            kept = kept + 1
                        end
                    end
                    Chat._pongCount = kept
                end
                local replyPayload = Chat:BuildDirectPresencePayload("DPONG")
                local targetForPong = (parsedSender and parsedSender.displayName) or cleanSenderStr
                local extraPong = (cleanSenderStr and cleanSenderStr ~= targetForPong) and { cleanSenderStr } or nil
                SendRoomPacket(targetForPong, bnGameAccId, replyPayload, nil, {
                    sendAllCandidates = true,
                    forceAllCandidates = not (parsedSender and Chat.resolvedWhisperTargets and Chat.resolvedWhisperTargets[parsedSender.lookupKey]),
                    allowBNet = (bnGameAccId ~= nil),
                    trackCandidateKey = pongKey,
                    extraCandidates = extraPong,
                })
            end
        end
        return
    end

    if op == "DMA" then
        local _, msgId, ackFlag, reason = strsplit("|", payload, 4)
        msgId = CleanRoomToken(msgId)
        Chat:MarkPeerVerified(cleanSenderStr or (parsedSender and parsedSender.displayName) or senderRaw, bnGameAccId, nil, "DMA")
        if msgId and Chat.deliveryIndex and Chat.deliveryIndex[msgId] then
            local rec = Chat.deliveryIndex[msgId]
            if rec and rec.entry then
                if ackFlag == "0" then
                    rec.entry.deliveryState = (reason == "off") and "off" or "declined"
                    local who = (parsedSender and parsedSender.displayName) or senderRaw or "?"
                    ns:Print("%s", string.format(L["%s has In-Addon Direct Chat disabled. Send via Blizzard chat instead."], who))
                else
                    rec.entry.deliveryState = "delivered"
                end
            end
            Chat.deliveryIndex[msgId] = nil
            ns:Emit("CHAT_UPDATED")
        end
        return
    end

    if op == "DM" or op == "DPIN" then
        if not Chat:IsDirectChatEnabled() then
            local _, rawMsgId = strsplit("|", payload, 3)
            local mId = CleanRoomToken(rawMsgId)
            local nackKey = bnGameAccId and ("bn:" .. tostring(bnGameAccId)) or (parsedSender and ("w:" .. parsedSender.lookupKey))
            local monoNow = GetTime and GetTime() or time()
            Chat.nackSentAt = Chat.nackSentAt or {}
            if mId and nackKey and (monoNow - (Chat.nackSentAt[nackKey] or 0)) >= NACK_COOLDOWN and not (ns.Clan and ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked()) then
                Chat.nackSentAt[nackKey] = monoNow
                Chat._nackCount = (Chat._nackCount or 0) + 1
                if Chat._nackCount >= 100 then
                    local kept = 0
                    for nk, nts in pairs(Chat.nackSentAt) do
                        if (monoNow - nts) > 300 then
                            Chat.nackSentAt[nk] = nil
                        else
                            kept = kept + 1
                        end
                    end
                    Chat._nackCount = kept
                end
                local nackPayload = "DMA|" .. mId .. "|0|off"
                SendRoomPacket(cleanSenderStr or (parsedSender and parsedSender.displayName), bnGameAccId, nackPayload)
            end
            return
        end
        Chat:MarkPeerVerified(cleanSenderStr or (parsedSender and parsedSender.displayName) or senderRaw, bnGameAccId, nil, op)
        local t, charParsed = EnsureIncomingDirectThread(senderRaw, bnGameAccId)
        if not t then return end

        local msgId, displaySender, formattedMsg
        local senderFallback = (charParsed and charParsed.displayName) or (parsedSender and parsedSender.displayName) or t.targetName or t.title or "?"
        if op == "DM" then
            local _, mId, senderShort, msgText = strsplit("|", payload, 4)
            msgId = CleanRoomToken(mId)
            msgText = Compat.CleanPayloadField(msgText, 180)
            if msgText == "" then return end
            displaySender = ResolveChatSenderDisplay(NonEmptyField(senderShort, 36, senderFallback), nil, senderFallback)
            formattedMsg = msgText
        else
            local _, mId, senderShort, zoneRaw, pxRaw, pyRaw = strsplit("|", payload, 6)
            msgId = CleanRoomToken(mId)
            local zone = NonEmptyField(zoneRaw, 48, "Azeroth")
            local px = tonumber(pxRaw) or 0
            local py = tonumber(pyRaw) or 0
            displaySender = ResolveChatSenderDisplay(NonEmptyField(senderShort, 36, senderFallback), nil, senderFallback)
            local coordStr = (px > 0 or py > 0) and string.format("%s (%d, %d)", zone, px, py) or zone
            formattedMsg = string.format(L["[Location: %s]"], coordStr)
        end

        local dedupSender = (parsedSender and parsedSender.lookupKey) or tostring(bnGameAccId or t.key)
        local isDup = IsDuplicateDirectMsg(dedupSender, msgId)
        if not isDup then
            local sLk = displaySender and Compat.ParseCharacterFields(displaySender) or (charParsed and charParsed.lookupKey)
            local cls = (sLk and LookupClassFromCache(sLk)) or t.classFile
            local skipPersist = (t.kind == "BN_WHISPER")
            local meDisplay = GetMyInfo()
            AppendMessage(t, displaySender, formattedMsg, true, cls, skipPersist, false, {
                viaAddon = true,
                deliveryMsgId = msgId,
                targetChar = meDisplay,
                senderCharName = (charParsed and charParsed.displayName) or displaySender,
                previewCategory = (bnGameAccId ~= nil) and "BN_WHISPER" or "WHISPER",
                previewChannelKind = (bnGameAccId ~= nil) and "BN_WHISPER" or "DIRECT",
            })
        end

        if msgId and not (ns.Clan and ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked()) then
            local ackPayload = "DMA|" .. msgId
            SendRoomPacket(cleanSenderStr or (parsedSender and parsedSender.displayName), bnGameAccId, ackPayload, nil, {
                allowBNet = (bnGameAccId ~= nil),
            })
        end
        return
    end

    if op ~= "RMI" and op ~= "RMJ" and op ~= "RML" and op ~= "RM" then
        return
    end

    Chat:MarkPeerVerified(cleanSenderStr or (parsedSender and parsedSender.displayName) or senderRaw, bnGameAccId, nil, op)

    local rooms = GetRoomsScopeTable()
    if not rooms then return end

    if op == "RMI" then
        local _, roomId, title, hostName = strsplit("|", payload, 4)
        roomId = CleanRoomToken(roomId)
        title = NonEmptyField(title, 32, roomId)
        local hostParsed = Compat.ParseCharacterName(hostName or "") or parsedSender
        if not roomId then return end
        local existing = rooms[roomId]
        if existing and existing.joined then return end

        rooms[roomId] = {
            id = roomId,
            title = title,
            host = (hostParsed and hostParsed.displayName) or "?",
            hostKey = hostParsed and hostParsed.lookupKey or nil,
            hostBNetGameId = bnGameAccId,
            joined = false,
            pendingInvite = true,
            members = hostParsed and { [hostParsed.lookupKey] = hostParsed.displayName } or {},
            createdAt = time(),
            updatedAt = time(),
        }
        if bnGameAccId then
            Chat.roomBNetTargets[roomId] = Chat.roomBNetTargets[roomId] or {}
            Chat.roomBNetTargets[roomId][bnGameAccId] = (hostParsed and hostParsed.displayName) or ""
        end
        PlayIncomingChime("ROOM", "room:" .. roomId, true, (hostParsed and hostParsed.lookupKey) or ("room:" .. roomId))
        local hostDisp = (hostParsed and hostParsed.displayName) or "Friend"
        local openLink = "|Haddon:SCentral:room:" .. roomId .. "|h|cff58a6ff[" .. L["Open"] .. "]|r|h"
        ns:Print("%s", string.format(L["Private room invite from %s: %s %s"], hostDisp, title, openLink))
        Chat:InvalidateUnreadCache()
        local hostClass = (hostParsed and hostParsed.lookupKey) and LookupClassFromCache(hostParsed.lookupKey) or nil
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "rmi:" .. roomId,
            kind = "RMI",
            sourceTag = L["Room Invite"],
            sender = hostDisp,
            senderClass = hostClass,
            lookupKey = hostParsed and hostParsed.lookupKey or nil,
            text = title,
            roomId = roomId,
            roomTitle = title,
            threadKey = "room:" .. roomId,
            ts = time(),
            priority = 3,
        })
        ns:Emit("CHAT_UPDATED")
    elseif op == "RMJ" then
        local _, roomId, memberRaw, accepted = strsplit("|", payload, 4)
        roomId = CleanRoomToken(roomId)
        local room = roomId and rooms[roomId]
        local memParsed = Compat.ParseCharacterName(memberRaw or "") or parsedSender
        if not room or not room.joined or not memParsed then return end

        if accepted == "1" then
            room.members = room.members or {}
            local canAdd = room.members[memParsed.lookupKey] ~= nil or CountTable(room.members) < MAX_ROOM_MEMBERS
            if canAdd then
                room.members[memParsed.lookupKey] = memParsed.displayName
                if bnGameAccId then
                    Chat.roomBNetTargets[roomId] = Chat.roomBNetTargets[roomId] or {}
                    Chat.roomBNetTargets[roomId][bnGameAccId] = memParsed.displayName
                end
            end
            local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
            AppendMessage(t, L["System"], string.format(L["%s joined the room."], memParsed.displayName), true, nil, true, true)
        else
            RemoveRoomMemberFromState(roomId, room, memParsed, parsedSender, bnGameAccId)
            local t = Chat.threads["room:" .. roomId]
            if t then
                AppendMessage(t, L["System"], string.format(L["%s declined the room invite."], memParsed.displayName), false, nil, true, true)
            end
        end
        room.updatedAt = time()
        ns:Emit("CHAT_UPDATED")
    elseif op == "RML" then
        local _, roomId, memberRaw = strsplit("|", payload, 3)
        roomId = CleanRoomToken(roomId)
        local room = roomId and rooms[roomId]
        local memParsed = Compat.ParseCharacterName(memberRaw or "") or parsedSender
        if not room or not room.joined or not memParsed then return end

        RemoveRoomMemberFromState(roomId, room, memParsed, parsedSender, bnGameAccId)
        local t = Chat.threads["room:" .. roomId]
        if t then
            AppendMessage(t, L["System"], string.format(L["%s left the room."], memParsed.displayName), false, nil, true, true)
        end
        room.updatedAt = time()
        ns:Emit("CHAT_UPDATED")
    elseif op == "RM" then
        local _, roomId, senderShort, msgText = strsplit("|", payload, 4)
        roomId = CleanRoomToken(roomId)
        msgText = Compat.CleanPayloadField(msgText, 180)
        local room = roomId and rooms[roomId]
        if not room or not room.joined or msgText == "" then return end

        local senderFallback = (parsedSender and parsedSender.displayName) or "?"
        local displaySender = ResolveChatSenderDisplay(NonEmptyField(senderShort, 36, senderFallback), nil, senderFallback)
        local dispParsed = (displaySender ~= "?") and Compat.ParseCharacterName(displaySender) or nil
        local memAddParsed = (dispParsed and dispParsed.surname and dispParsed) or parsedSender or dispParsed
        room.members = room.members or {}
        if memAddParsed then
            if parsedSender and parsedSender.lookupKey ~= memAddParsed.lookupKey and room.members[parsedSender.lookupKey] ~= nil then
                room.members[parsedSender.lookupKey] = nil
            end
            if room.members[memAddParsed.lookupKey] ~= nil or CountTable(room.members) < MAX_ROOM_MEMBERS then
                room.members[memAddParsed.lookupKey] = memAddParsed.displayName
            end
        end
        if bnGameAccId and memAddParsed and room.members[memAddParsed.lookupKey] ~= nil then
            Chat.roomBNetTargets[roomId] = Chat.roomBNetTargets[roomId] or {}
            Chat.roomBNetTargets[roomId][bnGameAccId] = memAddParsed.displayName
        end
        local classFile = parsedSender and LookupClassFromCache(parsedSender.lookupKey)
        local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
        AppendMessage(t, displaySender, msgText, true, classFile, not Chat:ShouldSaveGeneralHistory(), false, {
            viaAddon = true,
            notifyKind = "ROOM",
            senderCharName = displaySender,
            previewCategory = "ROOM",
            previewChannelKind = "ROOM",
        })
    end
end

local function MarkSiblingUnreadThreadsOnReply(primaryThread, parsed, bnetAccountID, bnetAuthor)
    local primaryKey = primaryThread and primaryThread.key or nil
    local targetLk = parsed and parsed.lookupKey or nil
    local firstLow = (parsed and (not parsed.surname) and parsed.firstName) and parsed.firstName:lower() or nil
    local bnetLow = (type(bnetAuthor) == "string" and bnetAuthor ~= "") and bnetAuthor:lower() or nil
    local clearedAny = false

    for k, t in pairs(Chat.threads) do
        if type(t) == "table" and k ~= primaryKey and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and ((t.unread or 0) > 0 or t.hasMention) then
            local matched = false
            if bnetAccountID and t.bnetAccountID == bnetAccountID then
                matched = true
            elseif bnetLow and t.bnetName and tostring(t.bnetName):lower() == bnetLow then
                matched = true
            elseif targetLk then
                local candName = t.targetName or (t.kind == "WHISPER" and t.title) or nil
                if candName and not tostring(candName):find("#", 1, true) then
                    local tLk, tFirst = Compat.ParseCharacterFields(candName)
                    if tLk == targetLk then
                        matched = true
                    elseif firstLow and tFirst and tFirst:lower() == firstLow then
                        matched = true
                    end
                end
            end
            if matched then
                t.unread = 0
                t.hasMention = nil
                if type(k) == "string" and k:sub(1, 2) == "w:" then
                    local hist = GetHistoryScopeTable()
                    if hist and type(hist[k]) == "table" then
                        hist[k].unread = 0
                    end
                end
                clearedAny = true
                ns:Emit("CHAT_THREAD_READ", {
                    threadKey = k,
                    channelKey = k,
                    kind = t.kind,
                    bnetAccountID = t.bnetAccountID,
                })
            end
        end
    end
    if clearedAny then
        Chat:InvalidateUnreadCache()
        ns:Emit("CHAT_UPDATED")
    end
end

-- =====================================================================
-- Phase 1: Chat Shield (Account Ignore, Anti-Spam, Clickable URLs)
--          & Mentions / Custom Keyword Radar
-- =====================================================================

local MAX_FILTERED_LOG = 60
local MAX_MENTION_LINES = 80
local FILTER_CACHE_MAX = 120
local FLOOD_WINDOW_SEC = 45
local MENTION_COOLDOWN_SEC = 10

Chat.filteredChatLog = Chat.filteredChatLog or {}
Chat.filteredChatCount = Chat.filteredChatCount or 0

local filterDecisionCache = {}
local filterDecisionCount = 0
local floodTracker = {}
local floodTrackerCount = 0
local mentionCooldowns = {}
local mentionCooldownCount = 0
local parsedTermsCache = {
    nickRaw = nil,
    nickList = {},
    kwRaw = nil,
    kwList = {},
    spamRaw = nil,
    spamList = {},
}
local chatShieldInstalled = false

local RMT_SPAM_PHRASES = {
    "cheap gold", "buy gold", "sell gold", "gold4", "g2g.com", "eldorado.gg",
    "igvault", "mmogah", "odealo", "playerauctions", "overgear", "skycoach",
    "boosting service", "carry service", "real money", "rmt", "paypal",
    "compro ouro", "vendo ouro", "ouro barato", "oro barato", "vendo oro",
    "wts gold", "wtb gold", "24/7 delivery", "instant delivery", "safe gold",
}

local function ParseCommaListCached(rawStr, rawField, listField, minLen)
    local norm = type(rawStr) == "string" and rawStr or ""
    if parsedTermsCache[rawField] == norm then
        return parsedTermsCache[listField]
    end
    parsedTermsCache[rawField] = norm
    local out = {}
    if norm ~= "" then
        local seen = {}
        for part in norm:gmatch("[^,;|\n]+") do
            local folded = Chat:FoldSearchText(Compat.Trim and Compat.Trim(part) or part)
            if folded and #folded >= (minLen or 2) and not seen[folded] then
                seen[folded] = true
                out[#out + 1] = folded
            end
        end
    end
    parsedTermsCache[listField] = out
    return out
end

local function IsTrustedSocialSender(lookupKey, guid)
    if not lookupKey or lookupKey == "" then return false end
    if Compat.IsGuildMember and Compat.IsGuildMember(nil, guid, lookupKey) then
        return true
    end
    if Compat.IsInMyGroup and Compat.IsInMyGroup(lookupKey, guid) then
        return true
    end
    local socByLk = ns.Store and ns.Store.socialDirectoryByLookup
    local row = socByLk and socByLk[lookupKey]
    if row and row.sources and (row.sources.friend or row.sources.bnet or row.sources.guild) then
        return true
    end
    return false
end

local function GetShortChannelLabel(eventName, channelLabel)
    if eventName == "CHAT_MSG_GUILD" then return L["Guild"]
    elseif eventName == "CHAT_MSG_OFFICER" then return L["Officer"]
    elseif eventName == "CHAT_MSG_PARTY" or eventName == "CHAT_MSG_PARTY_LEADER" then return L["Party"]
    elseif eventName == "CHAT_MSG_RAID" or eventName == "CHAT_MSG_RAID_LEADER" or eventName == "CHAT_MSG_RAID_WARNING" then return L["Raid"]
    elseif eventName == "CHAT_MSG_INSTANCE_CHAT" or eventName == "CHAT_MSG_INSTANCE_CHAT_LEADER" then return L["Instance"]
    elseif eventName == "CHAT_MSG_SAY" then return L["Say"]
    elseif eventName == "CHAT_MSG_YELL" then return L["Yell"]
    elseif eventName == "CHAT_MSG_WHISPER" then return L["Whisper"]
    elseif eventName == "CHAT_MSG_CHANNEL" then
        local cleanCh = Safe.String(channelLabel)
        if cleanCh and cleanCh ~= "" then
            cleanCh = cleanCh:gsub("^%d+%.%s*", "")
            return cleanCh
        end
        return L["Channel"]
    end
    return L["Chat"]
end

local SHORT_CHANNEL_MAP = {
    lookingforgroup = "LFG",
    procurandogrupo = "LFG",
    buscargrupo = "LFG",
    localdefense = "Defense",
    defesalocal = "Defesa",
    defensalocal = "Defensa",
    worlddefense = "W.Def",
    defesamundial = "Def.M",
    defensamundial = "Def.M",
}

local function ShortenOfficialChannelLabel(channelLabel)
    local raw = Safe.String(channelLabel)
    if not raw or raw == "" then return nil end
    local commFriendly = Chat.ParseCommunityChannelName and Chat:ParseCommunityChannelName(raw) or nil
    if commFriendly and commFriendly ~= "" then
        return commFriendly
    end
    local numPrefix, body = raw:match("^(%d+%.%s*)(.+)$")
    numPrefix = numPrefix or ""
    body = body or raw
    local stripped = body:gsub("%s+%-%s+.*$", "")
    local folded = Chat:FoldSearchText(stripped):gsub("%s+", "")
    local mapped = SHORT_CHANNEL_MAP[folded] or stripped
    local shortened = numPrefix .. mapped
    if shortened ~= "" and shortened ~= raw then
        return shortened
    end
    return nil
end

local function BuildOfficialSenderTagPrefix(lookupKey, displayName, guid)
    if not lookupKey or lookupKey == "" then return nil end
    local tags = {}
    local meta = ns.Store and ((ns.Store.GetResolvedSocialMeta and ns.Store:GetResolvedSocialMeta(lookupKey))
        or (ns.Store.GetSocialMeta and ns.Store:GetSocialMeta(lookupKey)))
    if type(meta) == "table" then
        if type(meta.nickname) == "string" and meta.nickname ~= "" then
            tags[#tags + 1] = "|cffffd24d[" .. meta.nickname .. "]|r"
        end
        if meta.flag == "GOOD" then
            tags[#tags + 1] = "|cff3fb950[+]|r"
        elseif meta.flag == "AVOID" then
            tags[#tags + 1] = "|cffff4d4d[" .. L["AVOID"] .. "]|r"
        end
        if type(meta.mainName) == "string" and meta.mainName ~= "" then
            local dispLow = (displayName or ""):lower()
            if meta.mainName:lower() ~= dispLow then
                tags[#tags + 1] = "|cff6ec1e4[" .. meta.mainName .. "]|r"
            end
        end
    end

    local lvl = LookupLevelFromCache(lookupKey, displayName, guid)
    if lvl and lvl > 0 then
        tags[#tags + 1] = "|cff9da7b5[" .. L["Lv."] .. tostring(lvl) .. "]|r"
    end

    if #tags == 0 then
        return nil
    end
    local safeTarget = (Compat.CleanPayloadField and Compat.CleanPayloadField(lookupKey, 40)) or lookupKey:gsub("[|\r\n]", "")
    return "|Haddon:SCentral:social:" .. safeTarget .. "|h" .. table.concat(tags, " ") .. "|h "
end

function Chat:InvalidateOfficialChatCache()
    filterDecisionCache = {}
    filterDecisionCount = 0
end

function Chat:_ResetTransientShieldCaches()
    if filterDecisionCount > 0 then
        filterDecisionCache = {}
        filterDecisionCount = 0
    end
    if floodTrackerCount > 0 then
        floodTracker = {}
        floodTrackerCount = 0
    end
    if mentionCooldownCount > 0 then
        local nowMono = (GetTime and GetTime()) or 0
        for k, at in pairs(mentionCooldowns) do
            if (nowMono - (tonumber(at) or 0)) > (MENTION_COOLDOWN_SEC * 2) then
                mentionCooldowns[k] = nil
                mentionCooldownCount = math.max(0, mentionCooldownCount - 1)
            end
        end
    end
end

local MAX_OFFICIAL_CAPTURE_LINES = 60
local MAX_EDITBOX_HISTORY_LINES = 100
local officialLineBuffers = {}
local officialChatHooksInstalled = false
local officialEditBoxHooksInstalled = false
local restoringEditHistory = false

local function CleanRenderedChatLine(rawMsg)
    if Safe.IsSecret(rawMsg) or type(rawMsg) ~= "string" then
        return nil
    end
    local s = rawMsg
    if s:find("|K", 1, true) then
        s = s:gsub("|K[^|]*|k", "")
    end
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    for _ = 1, 2 do
        local nextS = s:gsub("|H[^|]-|h(.-)|h", "%1")
        if nextS == s then break end
        s = nextS
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("[\r\n]+", " ")
    s = Compat.Trim and Compat.Trim(s) or s:match("^%s*(.-)%s*$")
    if not s or s == "" then
        return nil
    end
    return s
end

Chat._COMBAT_LOG_CAP = 400
Chat._combatLogBuffer = Chat._combatLogBuffer or {}
Chat._combatLogEmitPending = false
Chat._combatLogEmitFn = Chat._combatLogEmitFn or function()
    Chat._combatLogEmitPending = false
    ns:Emit("COMBAT_LOG_UPDATED")
end

function Chat:_ClassifyCombatLogKind(plainStr, r, g, b)
    local low = (type(plainStr) == "string") and plainStr:lower() or ""
    if low:find("died", 1, true) or low:find("slain", 1, true) or low:find("killed", 1, true)
        or low:find("morreu", 1, true) or low:find("morto", 1, true) or low:find("muri", 1, true)
        or low:find("matou", 1, true) or low:find("abat", 1, true)
    then
        return "kills"
    end
    if low:find("heal", 1, true) or low:find("cura", 1, true) or low:find("curad", 1, true)
        or low:find("sana", 1, true) or low:find("absor", 1, true)
        or (tonumber(g) and tonumber(r) and tonumber(b) and g >= 0.65 and r <= 0.45 and b <= 0.55)
    then
        return "healing"
    end
    if low:find("hit", 1, true) or low:find("crit", 1, true) or low:find("damage", 1, true)
        or low:find("dano", 1, true) or low:find("acerto", 1, true) or low:find("golpe", 1, true)
        or low:find("daño", 1, true) or low:find("impact", 1, true) or low:find("suffers", 1, true)
        or low:find("sofre", 1, true) or low:find("sufre", 1, true)
        or (tonumber(r) and tonumber(g) and r >= 0.72 and g <= 0.48)
    then
        return "damage"
    end
    return "misc"
end

function Chat:ClearCombatLogBufferSilent()
    if self._combatLogBuffer then
        wipe(self._combatLogBuffer)
    end
    self._combatLogHead = 1
    self._combatLogCount = 0
    if self._combatLogViewBuf then
        wipe(self._combatLogViewBuf)
    end
end

function Chat:_ResolveTimestampEpochNoAlloc(hh, mm, ss)
    local nowEpoch = time()
    if not self._cachedDayMidnight or nowEpoch >= (self._cachedDayMidnight + 86400) or nowEpoch < self._cachedDayMidnight then
        if date then
            local dt = date("*t", nowEpoch)
            if type(dt) == "table" then
                self._cachedDayMidnight = nowEpoch - ((dt.hour or 0) * 3600 + (dt.min or 0) * 60 + (dt.sec or 0))
            end
        end
    end
    if self._cachedDayMidnight then
        local candidate = self._cachedDayMidnight + ((tonumber(hh) or 0) * 3600) + ((tonumber(mm) or 0) * 60) + (tonumber(ss) or 0)
        if candidate <= (nowEpoch + 120) then
            return candidate
        end
        return candidate - 86400
    end
    return nowEpoch
end

function Chat:RecordCombatLogLine(rawMsg, r, g, b, customTs, isBackfill)
    if not self:IsChatHistoryCaptureEnabled() then
        return
    end
    if (not isBackfill) and not (ns.QuickReply and ns.QuickReply.IsCombatLogPopupActive and ns.QuickReply:IsCombatLogPopupActive("combat")) then
        return
    end
    if Safe.IsSecret(rawMsg) or type(rawMsg) ~= "string" then
        return
    end
    local safeLine = Safe.String(rawMsg)
    if not safeLine then
        return
    end
    if safeLine:find("|K", 1, true) then
        safeLine = safeLine:gsub("|K[^|]*|k", "")
    end
    local parsedTs = tonumber(customTs)
    if not parsedTs then
        if isBackfill then
            local hh, mm, ss = safeLine:match("(%d%d?):(%d%d):(%d%d)")
            if not hh then
                hh, mm = safeLine:match("^%s*%[?(%d%d?):(%d%d)")
            end
            if hh and mm then
                parsedTs = self:_ResolveTimestampEpochNoAlloc(hh, mm, ss)
            end
        else
            parsedTs = time()
        end
    end
    safeLine = self:_StripLeadingChatTimestamp(safeLine)
    safeLine = Compat.Trim and Compat.Trim(safeLine) or safeLine:match("^%s*(.-)%s*$")
    if not safeLine or safeLine == "" then
        return
    end
    local plain = CleanRenderedChatLine(safeLine) or safeLine
    local nr = tonumber(r)
    local ng = tonumber(g)
    local nb = tonumber(b)
    local buf = self._combatLogBuffer
    if not buf then
        buf = {}
        self._combatLogBuffer = buf
    end
    local cap = self._COMBAT_LOG_CAP or 400
    local count = self._combatLogCount or 0
    local head = self._combatLogHead or 1
    local writeIdx
    if count < cap then
        count = count + 1
        writeIdx = ((head + count - 2) % cap) + 1
    else
        writeIdx = head
        head = (head % cap) + 1
    end
    self._combatLogHead = head
    self._combatLogCount = count
    local slot = buf[writeIdx]
    if type(slot) ~= "table" then
        slot = {}
        buf[writeIdx] = slot
    end
    slot.ts = parsedTs or time()
    slot.text = safeLine
    slot.plain = plain
    slot.r = nr or 0.92
    slot.g = ng or 0.88
    slot.b = nb or 0.78
    slot.kind = self:_ClassifyCombatLogKind(plain, nr, ng, nb)
    if (not isBackfill) and not self._combatLogEmitPending then
        self._combatLogEmitPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, self._combatLogEmitFn)
        else
            self._combatLogEmitPending = false
            ns:Emit("COMBAT_LOG_UPDATED")
        end
    end
end

function Chat:GetCombatLogEntries(filterKind)
    local buf = self._combatLogBuffer
    if not buf then
        buf = {}
        self._combatLogBuffer = buf
        self._combatLogHead = 1
        self._combatLogCount = 0
    end
    local count = self._combatLogCount or 0
    if count == 0 then
        local cf2 = _G.ChatFrame2
        if cf2 and cf2.GetNumMessages and cf2.GetMessageInfo then
            local okN, total = pcall(cf2.GetNumMessages, cf2)
            local totalNum = okN and Safe.Number(total) or 0
            if totalNum > 0 then
                local startIdx = math.max(1, totalNum - 200 + 1)
                for i = startIdx, totalNum do
                    local okM, lineRaw, mr, mg, mb = pcall(cf2.GetMessageInfo, cf2, i)
                    if okM and lineRaw then
                        self:RecordCombatLogLine(lineRaw, mr, mg, mb, nil, true)
                    end
                end
                buf = self._combatLogBuffer
                count = self._combatLogCount or 0
            end
        end
    end
    local head = self._combatLogHead or 1
    local out = self._combatLogViewBuf
    if not out then
        out = {}
        self._combatLogViewBuf = out
    else
        wipe(out)
    end
    local wantAll = (not filterKind or filterKind == "all")
    local cap = self._COMBAT_LOG_CAP or 400
    for i = 1, count do
        local idx = ((head + i - 2) % cap) + 1
        local item = buf[idx]
        if item and (wantAll or item.kind == filterKind or (filterKind == "kills" and item.kind == "misc")) then
            out[#out + 1] = item
        end
    end
    return out
end

function Chat:ClearCombatLogEntries()
    self:ClearCombatLogBufferSilent()
    ns:Emit("COMBAT_LOG_UPDATED")
end

Chat._worldLogBuffer = Chat._worldLogBuffer or {}
Chat._worldLogDedup = Chat._worldLogDedup or {}

Chat._WORLD_LOG_CAP = 400
Chat._WORLD_LOG_HEX_BY_KIND = {
    loot = "|cff47ef66",
    craft = "|cff6ec1e4",
    progress = "|cff9aaeff",
    system = "|cffffff66",
}

function Chat:RecordWorldLogLine(kind, tagLabel, rawMsg, r, g, b, customTs, skipEmit)
    if Safe.IsSecret(rawMsg) or type(rawMsg) ~= "string" then
        return false
    end
    local safeLine = Safe.String(rawMsg)
    if not safeLine then
        return false
    end
    if safeLine:find("|K", 1, true) then
        safeLine = safeLine:gsub("|K[^|]*|k", "")
    end
    safeLine = self:_StripLeadingChatTimestamp(safeLine)
    safeLine = Compat.Trim and Compat.Trim(safeLine) or safeLine:match("^%s*(.-)%s*$")
    if not safeLine or safeLine == "" then
        return false
    end
    local plain = CleanRenderedChatLine(safeLine) or safeLine
    local normKey = self:_NormalizeGeneralDedupText(plain)
    if normKey and normKey ~= "" then
        local nowWall = time()
        local prevAt = self._worldLogDedup and self._worldLogDedup[normKey]
        if prevAt and (nowWall - prevAt) <= 2 then
            return false
        end
        self._worldLogDedup = self._worldLogDedup or {}
        self._worldLogDedup[normKey] = nowWall
        self._worldLogDedupCount = (self._worldLogDedupCount or 0) + 1
        if self._worldLogDedupCount > 60 then
            for k, tAt in pairs(self._worldLogDedup) do
                if (nowWall - (tonumber(tAt) or 0)) > 4 then
                    self._worldLogDedup[k] = nil
                end
            end
            self._worldLogDedupCount = 0
        end
    end
    local normKind = (kind == "loot" or kind == "craft" or kind == "progress" or kind == "system") and kind or "system"
    local prefixTag = (tagLabel and tagLabel ~= "") and ((Chat._WORLD_LOG_HEX_BY_KIND[normKind] or "|cffffff66") .. "[" .. tagLabel .. "]|r ") or ""
    local displayTxt = prefixTag .. safeLine
    local buf = self._worldLogBuffer
    if not buf then
        buf = {}
        self._worldLogBuffer = buf
    end
    local cap = Chat._WORLD_LOG_CAP or 400
    local count = self._worldLogCount or #buf
    local head = self._worldLogHead or 1
    local writeIdx
    if count < cap then
        count = count + 1
        writeIdx = ((head + count - 2) % cap) + 1
    else
        writeIdx = head
        head = (head % cap) + 1
    end
    self._worldLogHead = head
    self._worldLogCount = count
    local slot = buf[writeIdx]
    if type(slot) ~= "table" then
        slot = {}
        buf[writeIdx] = slot
    end
    slot.ts = tonumber(customTs) or time()
    slot.text = displayTxt
    slot.plain = plain
    slot.r = tonumber(r) or 0.94
    slot.g = tonumber(g) or 0.92
    slot.b = tonumber(b) or 0.78
    slot.kind = normKind
    if not skipEmit and not self._combatLogEmitPending then
        self._combatLogEmitPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, self._combatLogEmitFn)
        else
            self._combatLogEmitPending = false
            ns:Emit("COMBAT_LOG_UPDATED")
        end
    end
    return true
end

function Chat:GetWorldLogEntries(filterKind)
    local buf = self._worldLogBuffer
    if not buf then
        buf = {}
        self._worldLogBuffer = buf
        self._worldLogHead = 1
        self._worldLogCount = 0
    end
    local count = self._worldLogCount or #buf
    local head = self._worldLogHead or 1
    local out = self._worldLogViewBuf
    if not out then
        out = {}
        self._worldLogViewBuf = out
    else
        wipe(out)
    end
    local wantAll = (not filterKind or filterKind == "all")
    local cap = Chat._WORLD_LOG_CAP or 400
    for i = 1, count do
        local idx = ((head + i - 2) % cap) + 1
        local item = buf[idx]
        if item and (wantAll or item.kind == filterKind) then
            out[#out + 1] = item
        end
    end
    return out
end

function Chat:ClearWorldLogEntries()
    if self._worldLogBuffer then
        wipe(self._worldLogBuffer)
    end
    self._worldLogHead = 1
    self._worldLogCount = 0
    if self._worldLogViewBuf then
        wipe(self._worldLogViewBuf)
    end
    ns:Emit("COMBAT_LOG_UPDATED")
end

local function CaptureOfficialChatLine(chatId, rawMsg, r, g, b)
    if chatId == 2 then
        if Chat.RecordCombatLogLine then
            Chat:RecordCombatLogLine(rawMsg, r, g, b)
        end
        -- ChatFrame2 combat log hits fire continuously in raids; OpenCopyOfficialChat reads ChatFrame2 on demand.
        return
    elseif chatId == 1 and Chat.QueueGeneralOfficialFrameLine then
        Chat:QueueGeneralOfficialFrameLine(rawMsg, r, g, b)
    elseif chatId == 1 and Chat.RecordGeneralOfficialFrameLine then
        Chat:RecordGeneralOfficialFrameLine(rawMsg, r, g, b)
    end
    -- ChatFrame1..10 expose native GetMessageInfo in Forever 16001; read on-demand in OpenCopyOfficialChat to avoid per-line regex & array shifts.
    if chatId ~= 1 then
        return
    end
    local cf1 = _G.ChatFrame1
    if cf1 and cf1.GetMessageInfo and cf1.GetNumMessages then
        return
    end
    local st = ns.db and ns.db.settings
    if st and st.embedOfficialChat == false then
        return
    end
    local clean = CleanRenderedChatLine(rawMsg)
    if not clean then
        return
    end
    local buf = officialLineBuffers[chatId]
    if not buf then
        buf = {}
        officialLineBuffers[chatId] = buf
    end
    buf[#buf + 1] = clean
    if #buf > MAX_OFFICIAL_CAPTURE_LINES then
        table.remove(buf, 1)
    end
end

function Chat:OpenCopyOfficialChat(maxLines, chatId)
    local targetId = tonumber(chatId) or 1
    if targetId < 1 or targetId > 10 then targetId = 1 end
    local wantCount = math.max(10, math.min(MAX_OFFICIAL_CAPTURE_LINES, tonumber(maxLines) or 50))
    local collected = {}

    local buf = officialLineBuffers[targetId]
    if type(buf) == "table" and #buf > 0 then
        local startIdx = math.max(1, #buf - wantCount + 1)
        for i = startIdx, #buf do
            collected[#collected + 1] = buf[i]
        end
    else
        local cf = _G["ChatFrame" .. tostring(targetId)]
        if cf and cf.GetNumMessages and cf.GetMessageInfo then
            local okN, total = pcall(cf.GetNumMessages, cf)
            local totalNum = okN and Safe.Number(total) or 0
            if totalNum > 0 then
                local startIdx = math.max(1, totalNum - wantCount + 1)
                for i = startIdx, totalNum do
                    local okM, lineRaw = pcall(cf.GetMessageInfo, cf, i)
                    local clean = okM and CleanRenderedChatLine(Safe.String(lineRaw)) or nil
                    if clean then
                        collected[#collected + 1] = clean
                    end
                end
            end
        end
    end

    if #collected == 0 then
        ns:Print("%s", L["No chat messages captured yet on this chat window."])
        return false
    end

    if ns.UI and ns.UI.OpenCopyModal then
        ns.UI:OpenCopyModal(
            table.concat(collected, "\n"),
            L["Copy Official Chat"],
            L["Press Ctrl+C to copy recent chat lines."]
        )
        return true
    end
    return false
end

local function InstallOfficialChatCaptureHooks()
    if officialChatHooksInstalled then return end
    officialChatHooksInstalled = true
    for chatId = 1, 10 do
        local cf = _G["ChatFrame" .. tostring(chatId)]
        if cf then
            if hooksecurefunc and type(cf.AddMessage) == "function" then
                local cid = chatId
                hooksecurefunc(cf, "AddMessage", function(_, msg, r, g, b)
                    CaptureOfficialChatLine(cid, msg, r, g, b)
                end)
            end
            if cf.HookScript then
                cf:HookScript("OnMouseWheel", function(frame, delta)
                    local st = ns.db and ns.db.settings
                    if st and (st.embedOfficialChat == false or st.officialChatFastScroll == false) then
                        return
                    end
                    if not delta or delta == 0 then return end
                    if IsShiftKeyDown and IsShiftKeyDown() then
                        if delta > 0 and frame.ScrollToTop then
                            pcall(frame.ScrollToTop, frame)
                        elseif delta < 0 and frame.ScrollToBottom then
                            pcall(frame.ScrollToBottom, frame)
                        end
                    elseif IsControlKeyDown and IsControlKeyDown() then
                        for _ = 1, 4 do
                            if delta > 0 and frame.PageUp then
                                pcall(frame.PageUp, frame)
                            elseif delta < 0 and frame.PageDown then
                                pcall(frame.PageDown, frame)
                            end
                        end
                    end
                end)
            end
        end
    end
end

function Chat:RecordSentInputHistory(rawLine, requireOfficialEmbed)
    if restoringEditHistory then return end
    if Safe.IsSecret(rawLine) then return end
    local st = ns.db and ns.db.settings
    if st and st.officialChatEditHistory == false then
        return
    end
    if requireOfficialEmbed and st and st.embedOfficialChat == false then
        return
    end
    local line = Safe.String(rawLine)
    if not line then return end
    line = line:gsub("[\r\n]+", " ")
    line = Compat.Trim and Compat.Trim(line) or line:match("^%s*(.-)%s*$")
    if not line or #line < 2 or #line > 240 then
        return
    end
    -- Privacy guard: never persist Battle.net protected tokens or Real ID player links on disk.
    if line:find("|K", 1, true) or line:find("|HBNplayer:", 1, true) then
        return
    end
    local hist = ns.db and ns.db.chatEditHistory
    if type(hist) ~= "table" then
        if ns.db then
            ns.db.chatEditHistory = {}
            hist = ns.db.chatEditHistory
        else
            return
        end
    end
    if hist[#hist] == line then
        return
    end
    for i = #hist, 1, -1 do
        if hist[i] == line then
            table.remove(hist, i)
            break
        end
    end
    hist[#hist + 1] = line
    while #hist > MAX_EDITBOX_HISTORY_LINES do
        table.remove(hist, 1)
    end
end

function Chat:GetSentInputHistory()
    return ns.db and ns.db.chatEditHistory or nil
end

local function SaveOfficialEditHistoryLine(rawLine)
    Chat:RecordSentInputHistory(rawLine, true)
end

local function RestoreSavedEditHistory()
    local st = ns.db and ns.db.settings
    if st and (st.embedOfficialChat == false or st.officialChatEditHistory == false) then
        return
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if ns.RunAfterCombat then
            ns:RunAfterCombat("chat_restore_edit_history", RestoreSavedEditHistory, false)
        end
        return
    end
    local hist = ns.db and ns.db.chatEditHistory
    if type(hist) ~= "table" or #hist == 0 then return end
    local eb = _G.ChatFrame1EditBox or (_G.ChatFrame1 and _G.ChatFrame1.editBox)
    if not (eb and eb.AddHistoryLine) then return end
    restoringEditHistory = true
    for i = 1, #hist do
        local line = hist[i]
        if type(line) == "string" and line ~= "" and not line:find("|K", 1, true) then
            pcall(eb.AddHistoryLine, eb, line)
        end
    end
    restoringEditHistory = false
end

local function InstallOfficialEditBoxHistoryHooks()
    if officialEditBoxHooksInstalled or not hooksecurefunc then return end
    officialEditBoxHooksInstalled = true
    local seenBoxes = {}
    local function HookBox(eb)
        if not eb or seenBoxes[eb] or type(eb.AddHistoryLine) ~= "function" then
            return
        end
        seenBoxes[eb] = true
        hooksecurefunc(eb, "AddHistoryLine", function(_, text)
            SaveOfficialEditHistoryLine(text)
        end)
    end
    HookBox(_G.ChatFrame1EditBox)
    HookBox(_G.ChatEdit_GetLastActiveWindow and _G.ChatEdit_GetLastActiveWindow())
    for chatId = 1, 10 do
        local cf = _G["ChatFrame" .. tostring(chatId)]
        if cf and cf.editBox then
            HookBox(cf.editBox)
        end
        HookBox(_G["ChatFrame" .. tostring(chatId) .. "EditBox"])
    end
end

local function RecordFilteredMessage(filterType, reasonText, senderDisp, lookupKey, channelLbl, rawText)
    Chat.filteredChatCount = (Chat.filteredChatCount or 0) + 1
    local entry = {
        id = tostring(time()) .. ":" .. tostring(Chat.filteredChatCount),
        ts = time(),
        filterType = filterType,
        reason = reasonText or "",
        sender = senderDisp or "?",
        lookupKey = lookupKey,
        channel = channelLbl or L["Chat"],
        text = tostring(rawText or ""):sub(1, 220),
    }
    table.insert(Chat.filteredChatLog, 1, entry)
    while #Chat.filteredChatLog > MAX_FILTERED_LOG do
        table.remove(Chat.filteredChatLog)
    end
    ns:Emit("CHAT_FILTERED_UPDATED")
end

function Chat:GetFilteredChatLog()
    return self.filteredChatLog or {}
end

function Chat:GetFilteredChatCount()
    return self.filteredChatCount or 0
end

function Chat:ClearFilteredChatLog()
    wipe(self.filteredChatLog)
    self.filteredChatCount = 0
    ns:Emit("CHAT_FILTERED_UPDATED")
end

Chat._SHIELD_CLEAN = Chat._SHIELD_CLEAN or { blocked = false }

local function EvaluateShieldDecision(eventName, text, author, guid, lineID, channelLabel)
    local cacheKey = (lineID and lineID ~= 0) and (tostring(eventName) .. ":" .. tostring(lineID)) or nil
    if cacheKey and filterDecisionCache[cacheKey] ~= nil then
        return filterDecisionCache[cacheKey]
    end

    local blocked = false
    local modifiedText = nil
    local modifiedChannel = nil
    local s = ns.db and ns.db.settings
    local parsed = author and Compat.ParseCharacterName and Compat.ParseCharacterName(author)
    local lookupKey = parsed and parsed.lookupKey or nil
    local displayName = (parsed and parsed.displayName) or author or "?"
    local isMe = (author and Compat.IsMe and Compat.IsMe(displayName, guid)) or false

    if not isMe and lookupKey and lookupKey ~= "" then
        -- 1) Account-Wide Unlimited Ignore filter
        if (not s) or (s.accountIgnoreHideChat ~= false) then
            local ign = ns.Store and ns.Store.GetAccountIgnore and ns.Store:GetAccountIgnore(lookupKey)
            if ign and ign.hideChat ~= false then
                blocked = true
                local rLbl = (ns.Store and ns.Store.FormatIgnoreReason) and ns.Store:FormatIgnoreReason(ign.reason, L) or L["Account Ignore"]
                RecordFilteredMessage("IGNORE", rLbl, displayName, lookupKey, GetShortChannelLabel(eventName, channelLabel), text)
            end
        end

        -- 2) Opt-in Public Anti-Spam Shield (never blocks Friends, Guild, BNet, or Group)
        if (not blocked) and s and s.chatAntiSpamEnabled == true then
            local isPublicSpamEvent = (eventName == "CHAT_MSG_CHANNEL" or eventName == "CHAT_MSG_SAY" or eventName == "CHAT_MSG_YELL" or eventName == "CHAT_MSG_WHISPER")
            if isPublicSpamEvent and not IsTrustedSocialSender(lookupKey, guid) then
                local folded = Chat:FoldSearchText(text)
                local matchedReason = nil

                for i = 1, #RMT_SPAM_PHRASES do
                    if folded:find(RMT_SPAM_PHRASES[i], 1, true) then
                        matchedReason = L["Spam / RMT"]
                        break
                    end
                end
                if not matchedReason and folded:find("discord.gg/", 1, true)
                    and (folded:find("wts", 1, true) or folded:find("boost", 1, true) or folded:find("gold", 1, true) or folded:find("carry", 1, true)) then
                    matchedReason = L["Spam / RMT"]
                end
                if not matchedReason then
                    local customList = ParseCommaListCached(s.chatAntiSpamKeywords, "spamRaw", "spamList", 2)
                    for i = 1, #customList do
                        if folded:find(customList[i], 1, true) then
                            matchedReason = L["Blocked Keyword"] .. ": " .. customList[i]
                            break
                        end
                    end
                end
                if not matchedReason and s.chatAntiSpamBlockFlood ~= false and #folded >= 12 then
                    local nowClock = GetTime and GetTime() or time()
                    local fKey = lookupKey .. "|" .. folded:sub(1, 90)
                    local prevAt = floodTracker[fKey]
                    if prevAt and (nowClock - prevAt) <= FLOOD_WINDOW_SEC then
                        matchedReason = L["Repeated Flood"]
                    else
                        if floodTrackerCount >= 180 then
                            floodTracker = {}
                            floodTrackerCount = 0
                        end
                        if not floodTracker[fKey] then
                            floodTrackerCount = floodTrackerCount + 1
                        end
                        floodTracker[fKey] = nowClock
                    end
                end

                if matchedReason then
                    blocked = true
                    RecordFilteredMessage("SPAM", matchedReason, displayName, lookupKey, GetShortChannelLabel(eventName, channelLabel), text)
                end
            end
        end
    end

    -- 3) Clickable URLs, {rt1..rt8} Raid Icons & Official Chat Enhancements (only if not blocked)
    if (not blocked) and ((not s) or (s.chatClickableUrls ~= false)) then
        local linked = Chat:LinkifyUrls(text)
        if linked and linked ~= text then
            modifiedText = linked
        end
    end

    if (not blocked) and ((not s) or (s.embedOfficialChat ~= false)) then
        local curTxt = modifiedText or text
        if curTxt:find("{", 1, true) then
            local rtFormatted = Chat:FormatRaidTargetTokens(curTxt)
            if rtFormatted and rtFormatted ~= curTxt then
                modifiedText = rtFormatted
            end
        end
        if eventName == "CHAT_MSG_CHANNEL" and ((not s) or (s.officialChatShortChannels ~= false)) then
            local shortCh = ShortenOfficialChannelLabel(channelLabel)
            if shortCh then
                modifiedChannel = shortCh
            end
        end
        if (not isMe) and eventName ~= "CHAT_MSG_TEXT_EMOTE" and ((not s) or (s.officialChatSenderTags ~= false)) then
            local prefixTags = BuildOfficialSenderTagPrefix(lookupKey, displayName, guid)
            if prefixTags and prefixTags ~= "" then
                modifiedText = prefixTags .. (modifiedText or text)
            end
        end
    end

    local decision = (blocked or modifiedText ~= nil or modifiedChannel ~= nil)
        and { blocked = blocked, modifiedText = modifiedText, modifiedChannel = modifiedChannel }
        or Chat._SHIELD_CLEAN

    if cacheKey then
        if filterDecisionCount >= FILTER_CACHE_MAX then
            filterDecisionCache = {}
            filterDecisionCount = 0
        end
        filterDecisionCache[cacheKey] = decision
        filterDecisionCount = filterDecisionCount + 1
    end
    return decision
end

function Chat:IsMessageBlockedByShield(eventName, text, author, guid, lineID, channelLabel)
    if not text or text == "" then return false end
    local dec = EvaluateShieldDecision(eventName, text, author, guid, lineID, channelLabel)
    return dec and dec.blocked == true or false
end

Chat._lineTrack = {
    max = 200,
    ids = {},
    count = 0,
    pending = {},
    events = {
        CHAT_MSG_WHISPER = true,
        CHAT_MSG_PARTY = true,
        CHAT_MSG_PARTY_LEADER = true,
        CHAT_MSG_RAID = true,
        CHAT_MSG_RAID_LEADER = true,
        CHAT_MSG_INSTANCE_CHAT = true,
        CHAT_MSG_INSTANCE_CHAT_LEADER = true,
        CHAT_MSG_GUILD = true,
        CHAT_MSG_OFFICER = true,
        CHAT_MSG_SAY = true,
        CHAT_MSG_YELL = true,
        CHAT_MSG_CHANNEL = true,
        CHAT_MSG_COMMUNITIES_CHANNEL = true,
    },
}

local function LineTrackCategoryKey(eventName, lineID)
    if eventName == "CHAT_MSG_PARTY" or eventName == "CHAT_MSG_PARTY_LEADER"
        or eventName == "CHAT_MSG_RAID" or eventName == "CHAT_MSG_RAID_LEADER"
        or eventName == "CHAT_MSG_INSTANCE_CHAT" or eventName == "CHAT_MSG_INSTANCE_CHAT_LEADER"
    then
        return "GRP:" .. tostring(lineID)
    elseif eventName == "CHAT_MSG_CHANNEL" or eventName == "CHAT_MSG_COMMUNITIES_CHANNEL" then
        return "CH:" .. tostring(lineID)
    elseif eventName == "CHAT_MSG_SAY" or eventName == "CHAT_MSG_YELL" then
        return "LOC:" .. tostring(lineID)
    end
    return tostring(eventName) .. ":" .. tostring(lineID)
end

function Chat:IsChatLineRecorded(eventName, lineID)
    if not (eventName and lineID and lineID ~= 0) then return false end
    local ids = self._lineTrack.ids
    return ids[tostring(eventName) .. ":" .. tostring(lineID)] == true
        or ids[LineTrackCategoryKey(eventName, lineID)] == true
end

function Chat:MarkChatLineRecorded(eventName, lineID)
    if not (eventName and lineID and lineID ~= 0) then return end
    local lt = self._lineTrack
    local k1 = tostring(eventName) .. ":" .. tostring(lineID)
    local k2 = LineTrackCategoryKey(eventName, lineID)
    if not lt.ids[k1] or not lt.ids[k2] then
        if lt.count >= lt.max then
            lt.ids = {}
            lt.count = 0
        end
        if not lt.ids[k1] then
            lt.ids[k1] = true
            lt.count = lt.count + 1
        end
        if k2 ~= k1 and not lt.ids[k2] then
            lt.ids[k2] = true
            lt.count = lt.count + 1
        end
    end
end

function Chat:ShouldHideInOfficialChat(eventName)
    local s = ns.db and ns.db.settings
    if not s or s.embedOfficialChat == false then
        return false
    end
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return false
    end
    if s.officialHideGroup == true and (
        eventName == "CHAT_MSG_PARTY"
        or eventName == "CHAT_MSG_PARTY_LEADER"
        or eventName == "CHAT_MSG_RAID"
        or eventName == "CHAT_MSG_RAID_LEADER"
        or eventName == "CHAT_MSG_INSTANCE_CHAT"
        or eventName == "CHAT_MSG_INSTANCE_CHAT_LEADER"
    ) then
        return true
    end
    if s.officialHideGuild == true and (
        eventName == "CHAT_MSG_GUILD"
        or eventName == "CHAT_MSG_OFFICER"
    ) then
        return true
    end
    if s.officialHideWhispers == true and (
        eventName == "CHAT_MSG_WHISPER"
        or eventName == "CHAT_MSG_WHISPER_INFORM"
        or eventName == "CHAT_MSG_BN_WHISPER"
        or eventName == "CHAT_MSG_BN_WHISPER_INFORM"
    ) then
        return true
    end
    return false
end

local function ReplaceFilterChannelArg(newMsg, authorRaw, newChannel, langArg, _, ...)
    return false, newMsg, authorRaw, langArg, newChannel, ...
end

Chat._officialFbQueue = Chat._officialFbQueue or {}
Chat._officialFbPool = Chat._officialFbPool or {}
Chat._officialFbFlushPending = false

function Chat:_FlushOfficialFallbackQueue()
    Chat._officialFbFlushPending = false
    local lt = Chat._lineTrack
    local dispatchFn = Chat._dispatchOfficialFallback
    local q = Chat._officialFbQueue
    local pool = Chat._officialFbPool
    local n = #q
    for i = 1, n do
        local rec = q[i]
        q[i] = nil
        if rec then
            if lt and lt.pending then
                lt.pending[rec.fbKey] = nil
            end
            if dispatchFn and not Chat:IsChatLineRecorded(rec.ev, rec.lineID) then
                dispatchFn(rec.ev, rec.msg, rec.author, unpack(rec.args, 1, rec.argc))
            end
            wipe(rec.args)
            rec.fbKey, rec.ev, rec.lineID, rec.msg, rec.author, rec.argc = nil, nil, nil, nil, nil, 0
            if #pool < 32 then
                pool[#pool + 1] = rec
            end
        end
    end
end

function Chat:_EnqueueOfficialFallback(lt, fbKey, eventName, lineID, msg, author, ...)
    if lt.pending[fbKey] then return end
    lt.pending[fbKey] = true
    local pool = Chat._officialFbPool
    local rec = table.remove(pool)
    if not rec then
        rec = { args = {} }
    end
    local argc = select("#", ...)
    local argsTbl = rec.args
    for i = 1, argc do
        argsTbl[i] = select(i, ...)
    end
    rec.fbKey = fbKey
    rec.ev = eventName
    rec.lineID = lineID
    rec.msg = msg
    rec.author = author
    rec.argc = argc
    Chat._officialFbQueue[#Chat._officialFbQueue + 1] = rec
    if not Chat._officialFbFlushPending then
        Chat._officialFbFlushPending = true
        C_Timer.After(0, Chat._FlushOfficialFallbackQueue)
    end
end

Chat._SHIELD_NOT_BLOCKED = Chat._SHIELD_NOT_BLOCKED or { blocked = false }

local function OfficialChatShieldFilter(_, eventName, msgRaw, authorRaw, ...)
    if eventName == "CHAT_MSG_BN_WHISPER" or eventName == "CHAT_MSG_BN_WHISPER_INFORM" then
        return Chat:ShouldHideInOfficialChat(eventName) == true
    end
    if Safe.IsSecret(msgRaw) or Safe.IsSecret(authorRaw) then
        return false
    end
    local msg = Safe.String(msgRaw)
    if not msg or msg == "" then
        return false
    end
    local author = Safe.String(authorRaw)
    -- Standard CHAT_MSG_* filter args after author: lang(1), chanFull(2), target(3), flags(4), zoneID(5), chanIdx(6), chanBase(7), unused(8), lineID(9), guid(10)
    local channelLabel = Safe.String(select(2, ...)) or Safe.String(select(7, ...))
    local lineID = Safe.Number(select(9, ...))
    local guid = Safe.String(select(10, ...))
    local dec = (eventName ~= "CHAT_MSG_WHISPER_INFORM")
        and EvaluateShieldDecision(eventName, msg, author, guid, lineID, channelLabel)
        or Chat._SHIELD_NOT_BLOCKED
    if dec.blocked then
        Chat:MarkChatLineRecorded(eventName, lineID)
        return true
    end
    local lt = Chat._lineTrack
    if lt and lt.events[eventName] and lineID and lineID ~= 0
        and Chat:IsChatHistoryCaptureEnabled()
        and not Chat:IsChatLineRecorded(eventName, lineID)
        and Chat._dispatchOfficialFallback and C_Timer and C_Timer.After
    then
        local fbKey = tostring(eventName) .. ":" .. tostring(lineID)
        Chat:_EnqueueOfficialFallback(lt, fbKey, eventName, lineID, msg, author, ...)
    end
    if Chat:ShouldHideInOfficialChat(eventName) then
        return true
    end
    local outText = dec.modifiedText or msg
    local isMeSender = (eventName == "CHAT_MSG_WHISPER_INFORM" or eventName == "CHAT_MSG_BN_WHISPER_INFORM")
        or (author and Compat.IsMe and Compat.IsMe(author, guid) == true)
    if dec ~= Chat._SHIELD_NOT_BLOCKED and dec ~= Chat._SHIELD_CLEAN and dec._fmtReady and dec._fmtSrc == msg and dec._fmtMe == (isMeSender == true) then
        outText = dec._fmtOut
    else
        if eventName == "CHAT_MSG_WHISPER_INFORM" then
            local sUrl = ns.db and ns.db.settings
            if (not sUrl or sUrl.chatClickableUrls ~= false) and Chat.LinkifyUrls then
                local linked = Chat:LinkifyUrls(outText)
                if linked and linked ~= outText then
                    outText = linked
                end
            end
            if Chat.FormatRaidTargetTokens then
                local rtOut = Chat:FormatRaidTargetTokens(outText)
                if rtOut and rtOut ~= outText then
                    outText = rtOut
                end
            end
        end
        if (not isMeSender) and Chat.HighlightMentionsInline then
            local hl = Chat:HighlightMentionsInline(outText, eventName)
            if hl and hl ~= outText then
                outText = hl
            end
        end
        if lineID and lineID ~= 0 and dec ~= Chat._SHIELD_NOT_BLOCKED then
            if dec ~= Chat._SHIELD_CLEAN then
                dec._fmtReady = true
                dec._fmtSrc = msg
                dec._fmtMe = (isMeSender == true)
                dec._fmtOut = outText
            elseif outText ~= msg then
                filterDecisionCache[tostring(eventName) .. ":" .. tostring(lineID)] = {
                    blocked = false,
                    _fmtReady = true,
                    _fmtSrc = msg,
                    _fmtMe = (isMeSender == true),
                    _fmtOut = outText,
                }
            end
        end
    end
    if dec.modifiedChannel and eventName == "CHAT_MSG_CHANNEL" then
        return ReplaceFilterChannelArg(outText, authorRaw, dec.modifiedChannel, ...)
    end
    if outText ~= msg then
        return false, outText, authorRaw, ...
    end
    return false
end

local function InstallChatShieldFilters()
    if chatShieldInstalled then return end
    local addFn = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not addFn then return end
    chatShieldInstalled = true
    local events = {
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_EMOTE",
        "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_COMMUNITIES_CHANNEL",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
    }
    for i = 1, #events do
        pcall(addFn, events[i], OfficialChatShieldFilter)
    end
end

function Chat:EnsureMentionsThread()
    local t = EnsureThread("mentions:radar", "MENTIONS", L["Mentions Radar"], {})
    if t then
        t.title = L["Mentions Radar"]
        t.unread = 0
    end
    return t
end

function Chat:GetMentionsUnreadCount()
    return 0
end

local function HasWholeTermInText(text, term)
    if not text or text == "" or not term or term == "" then return false end
    local startPos = 1
    local textLen = #text
    while startPos <= textLen do
        local s, e = text:find(term, startPos, true)
        if not s then return false end
        local prevOk = (s == 1) or text:sub(s - 1, s - 1):match("[%s%p]") ~= nil
        local nextOk = (e == textLen) or text:sub(e + 1, e + 1):match("[%s%p]") ~= nil
        if prevOk and nextOk then
            return true
        end
        startPos = s + 1
    end
    return false
end

local function NormalizeMentionTerm(term)
    if type(term) ~= "string" or not term:find("[%p]") then
        return nil
    end
    local norm = term:gsub("[%p%s]+", " "):match("^%s*(.-)%s*$")
    if norm and #norm >= 2 then
        return norm
    end
    return nil
end

local function ContainsWholeTerm(paddedText, foldedText, term)
    if not term or term == "" then return false end
    if paddedText:find(" " .. term .. " ", 1, true) then
        return true
    end
    if HasWholeTermInText(foldedText, term) then
        return true
    end
    local normTerm = NormalizeMentionTerm(term)
    if normTerm and paddedText:find(" " .. normTerm .. " ", 1, true) then
        return true
    end
    if foldedText:find("@" .. term, 1, true) then
        return true
    end
    return false
end

local function MatchesBooleanKeywordRule(padded, folded, rule)
    if not rule or rule == "" then return false end
    local hasBool = (rule:sub(1, 1) == "+" or rule:sub(1, 1) == "-" or rule:find(" +", 1, true) or rule:find(" -", 1, true)) ~= nil
    if not hasBool then
        if rule:find(" ", 1, true) then
            if folded:find(rule, 1, true) ~= nil then
                return true
            end
            local normRule = NormalizeMentionTerm(rule)
            return normRule ~= nil and padded:find(" " .. normRule .. " ", 1, true) ~= nil
        end
        return ContainsWholeTerm(padded, folded, rule)
    end
    local reqCount = 0
    for tok in rule:gmatch("%S+") do
        local prefix = tok:sub(1, 1)
        if prefix == "-" then
            local ex = tok:sub(2)
            if #ex >= 2 and (ContainsWholeTerm(padded, folded, ex) or (#ex >= 3 and folded:find(ex, 1, true) ~= nil)) then
                return false
            end
        else
            local req = (prefix == "+") and tok:sub(2) or tok
            if #req >= 2 then
                reqCount = reqCount + 1
                if not (ContainsWholeTerm(padded, folded, req) or (#req >= 4 and folded:find(req, 1, true) ~= nil)) then
                    return false
                end
            end
        end
    end
    return reqCount > 0
end

function Chat:EvaluateIncomingMention(eventName, text, senderDisp, senderLookupKey, senderGuid, classFile, channelLabel, sourceThreadKey)
    local s = ns.db and ns.db.settings
    if not s or s.mentionAlertsEnabled == false then return false end
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then return false end
    if not text or text == "" then return false end
    if senderDisp and Compat.IsMe and Compat.IsMe(senderDisp, senderGuid) then return false end

    -- Channel gating
    local isGuildEv = (eventName == "CHAT_MSG_GUILD" or eventName == "CHAT_MSG_OFFICER" or eventName == "ALLIANCE")
    local isGroupEv = (eventName == "CHAT_MSG_PARTY" or eventName == "CHAT_MSG_PARTY_LEADER"
        or eventName == "CHAT_MSG_RAID" or eventName == "CHAT_MSG_RAID_LEADER" or eventName == "CHAT_MSG_RAID_WARNING"
        or eventName == "CHAT_MSG_INSTANCE_CHAT" or eventName == "CHAT_MSG_INSTANCE_CHAT_LEADER" or eventName == "ROOM")
    local isSayEv = (eventName == "CHAT_MSG_SAY" or eventName == "CHAT_MSG_YELL")
    local isPubEv = (eventName == "CHAT_MSG_CHANNEL" or eventName == "CHAT_MSG_COMMUNITIES_CHANNEL")

    if isGuildEv and s.mentionWatchGuild == false then return false end
    if isGroupEv and s.mentionWatchGroup == false then return false end
    if isSayEv and s.mentionWatchSayYell == false then return false end
    if isPubEv and s.mentionWatchPublic == false then return false end

    local folded = self:FoldSearchText(text)
    if folded == "" then return false end
    local padded = " " .. folded:gsub("[%p%s]+", " ") .. " "

    local matchedTerm = nil
    local matchType = nil

    -- 1) Current character's own first name
    local myDisp = GetMyInfo()
    local myParsed = myDisp and Compat.ParseCharacterName and Compat.ParseCharacterName(myDisp)
    local myFirst = myParsed and myParsed.firstName and self:FoldSearchText(myParsed.firstName)
    if myFirst and #myFirst >= 3 and ContainsWholeTerm(padded, folded, myFirst) then
        matchedTerm = myParsed.firstName
        matchType = "NAME"
    end

    -- 2) User personal nicknames / alt names
    if not matchedTerm then
        local nicks = ParseCommaListCached(s.mentionNicknames, "nickRaw", "nickList", 2)
        for i = 1, #nicks do
            if ContainsWholeTerm(padded, folded, nicks[i]) then
                matchedTerm = nicks[i]
                matchType = "NICK"
                break
            end
        end
    end

    -- 3) User custom keywords & boolean rules (+req -exclude, substring for phrases, whole-word for single words)
    if not matchedTerm then
        local kws = ParseCommaListCached(s.mentionKeywords, "kwRaw", "kwList", 2)
        for i = 1, #kws do
            local kw = kws[i]
            if MatchesBooleanKeywordRule(padded, folded, kw) then
                matchedTerm = kw
                matchType = "KEYWORD"
                break
            end
        end
    end

    if not matchedTerm then return false end

    -- Anti-burst cooldown per (sender + term)
    local nowClock = GetTime and GetTime() or time()
    local cdKey = tostring(senderLookupKey or senderDisp or "?") .. "|" .. tostring(matchedTerm):lower()
    if mentionCooldowns[cdKey] and (nowClock - mentionCooldowns[cdKey]) < MENTION_COOLDOWN_SEC then
        return false
    end
    if mentionCooldownCount >= 160 then
        wipe(mentionCooldowns)
        mentionCooldownCount = 0
    end
    if not mentionCooldowns[cdKey] then
        mentionCooldownCount = mentionCooldownCount + 1
    end
    mentionCooldowns[cdKey] = nowClock

    local chLbl = channelLabel or GetShortChannelLabel(eventName, nil)
    local mThread = self:EnsureMentionsThread()
    if mThread then
        local entry = {
            ts = time(),
            sender = senderDisp or "?",
            text = "[" .. chLbl .. "] [" .. matchedTerm .. "] " .. text,
            rawText = text,
            incoming = true,
            classFile = classFile,
            isMention = true,
            mentionTerm = matchedTerm,
            mentionChannel = chLbl,
            mentionType = matchType,
            senderCharName = senderDisp,
            senderLookupKey = senderLookupKey,
            senderGuid = senderGuid,
            sourceThreadKey = sourceThreadKey,
        }
        table.insert(mThread.messages, entry)
        local maxM = math.max(MAX_MENTION_LINES, self:GetGeneralHistoryLimit())
        while #mThread.messages > maxM do
            table.remove(mThread.messages, 1)
        end
        mThread.lastAt = entry.ts
        if self:ShouldSaveGeneralHistory() then
            PersistWhisperLine("mentions:radar", entry, 0, mThread)
        end
        mThread.unread = 0
        mThread.hasMention = true
        QueueChatEmit(0.08)
    end

    local focusSilenced = Compat.IsFocusSilenced and Compat.IsFocusSilenced(senderLookupKey or senderDisp)
    if not focusSilenced and not self:IsThreadMuted("mentions:radar") then
        local inCombatNow = ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) == true
        local toastHiddenByCombat = inCombatNow and (s.msgPreviewSilenceCombat ~= false)
        if s.mentionSound ~= false and (not toastHiddenByCombat or isPubEv) then
            PlayIncomingChime("MENTION", "mentions:radar", true, senderLookupKey or senderDisp, true)
        end
        if isPubEv and senderDisp and senderDisp ~= "" and not senderDisp:find("#", 1, true) and not senderDisp:find("|", 1, true) then
            local safeTgt = Compat.CleanPayloadField and Compat.CleanPayloadField(senderDisp, 40) or senderDisp
            if safeTgt ~= "" then
                ns:Print("%s %s (%s) — |Haddon:SCentral:whisper:%s|h|cff3fb950[%s]|r|h",
                    "|cff3fb950[" .. L["Mention"] .. " · " .. chLbl .. "]|r",
                    senderDisp,
                    matchedTerm,
                    safeTgt,
                    L["Whisper (/w)"])
            end
        end
        local cleanMentionText = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x|H.-|h(.-)|h|r", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c]+", " ")
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "mention:" .. tostring(senderLookupKey or senderDisp or "?") .. ":" .. tostring(time()),
            kind = "MENTION",
            sourceTag = L["Mention"] .. " (" .. chLbl .. " · " .. matchedTerm .. ")",
            sender = senderDisp or "?",
            lookupKey = senderLookupKey,
            senderClass = classFile,
            text = cleanMentionText,
            threadKey = "mentions:radar",
            ts = time(),
            priority = 2,
        })
    end
    return true
end

function Chat:TriggerTestMention()
    local myDisp = GetMyInfo() or "Player"
    local mThread = self:EnsureMentionsThread()
    if mThread then
        local sampleText = L["Hey %s, want to join our dungeon group?"]:format(myDisp)
        local entry = {
            ts = time(),
            sender = "Varian Test",
            text = "[" .. L["Guild"] .. "] [" .. myDisp .. "] " .. sampleText,
            rawText = sampleText,
            incoming = true,
            classFile = "WARRIOR",
            isMention = true,
            mentionTerm = myDisp,
            mentionChannel = L["Guild"],
            mentionType = "NAME",
        }
        table.insert(mThread.messages, entry)
        local maxM = math.max(MAX_MENTION_LINES, self:GetGeneralHistoryLimit())
        while #mThread.messages > maxM do
            table.remove(mThread.messages, 1)
        end
        mThread.lastAt = entry.ts
        mThread.unread = 0
        mThread.hasMention = true
        self:InvalidateUnreadCache()
        ns:Emit("CHAT_UPDATED")
    end
    if ns.db and ns.db.settings and ns.db.settings.mentionSound ~= false then
        PlayIncomingChime("MENTION", "mentions:radar", true, "test_mention", "test")
    end
    ns:Emit("ADDON_MESSAGE_NOTIFY", {
        id = "mention:test:" .. tostring(time()),
        kind = "MENTION",
        sourceTag = L["Mention"] .. " (" .. L["Guild"] .. ")",
        sender = "Varian Test",
        senderClass = "WARRIOR",
        text = L["Hey %s, want to join our dungeon group?"]:format(myDisp),
        threadKey = "mentions:radar",
        ts = time(),
        priority = 2,
        isTest = true,
    })
end

function Chat:HighlightMentionsInline(rawText, channelOrEvent, explicitTerm)
    if type(rawText) ~= "string" or rawText == "" then
        return rawText
    end
    local s = ns.db and ns.db.settings
    if s and s.mentionAlertsEnabled == false then
        return rawText
    end
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return rawText
    end
    if type(channelOrEvent) == "string" and channelOrEvent ~= "" then
        local chUp = channelOrEvent:upper()
        if chUp == "GUILD" or chUp == "OFFICER" or chUp == "ALLIANCE" or chUp == "CHAT_MSG_GUILD" or chUp == "CHAT_MSG_OFFICER" then
            if s and s.mentionWatchGuild == false then return rawText end
        elseif chUp == "PARTY" or chUp == "RAID" or chUp == "INSTANCE_CHAT" or chUp == "ROOM"
            or chUp == "CHAT_MSG_PARTY" or chUp == "CHAT_MSG_PARTY_LEADER"
            or chUp == "CHAT_MSG_RAID" or chUp == "CHAT_MSG_RAID_LEADER" or chUp == "CHAT_MSG_RAID_WARNING"
            or chUp == "CHAT_MSG_INSTANCE_CHAT" or chUp == "CHAT_MSG_INSTANCE_CHAT_LEADER"
        then
            if s and s.mentionWatchGroup == false then return rawText end
        elseif chUp == "LOCAL_SAY" or chUp == "LOCAL_YELL" or chUp == "CHAT_MSG_SAY" or chUp == "CHAT_MSG_YELL" then
            if s and s.mentionWatchSayYell == false then return rawText end
        elseif chUp == "CHAT_MSG_CHANNEL" or chUp == "CHAT_MSG_COMMUNITIES_CHANNEL" then
            if s and s.mentionWatchPublic == false then return rawText end
        end
    end

    local myDisp = GetMyInfo()
    local myParsed = myDisp and Compat.ParseCharacterName and Compat.ParseCharacterName(myDisp)
    local myFirst = myParsed and myParsed.firstName and self:FoldSearchText(myParsed.firstName) or ""
    local nickRaw = (s and type(s.mentionNicknames) == "string") and s.mentionNicknames or ""
    local kwRaw = (s and type(s.mentionKeywords) == "string") and s.mentionKeywords or ""
    local sig = myFirst .. "|" .. nickRaw .. "|" .. kwRaw
    local cache = self._mentionHlCache
    if not cache or cache.sig ~= sig then
        local tSet = {}
        if #myFirst >= 3 then
            tSet[myFirst] = true
        end
        local nicks = ParseCommaListCached(nickRaw, "nickRaw", "nickList", 2)
        for i = 1, #nicks do
            if not nicks[i]:find("[%s]") then
                tSet[nicks[i]] = true
            end
        end
        local kws = ParseCommaListCached(kwRaw, "kwRaw", "kwList", 2)
        for i = 1, #kws do
            local kw = kws[i]
            if kw:sub(1, 1) ~= "-" and not kw:find("[%s]") then
                local tok = (kw:sub(1, 1) == "+") and kw:sub(2) or kw
                if #tok >= 2 then
                    tSet[tok] = true
                end
            end
        end
        cache = { sig = sig, terms = tSet }
        self._mentionHlCache = cache
    end

    local termSet = cache.terms
    local expFold = (type(explicitTerm) == "string" and explicitTerm ~= "") and self:FoldSearchText(explicitTerm) or nil
    if expFold and expFold:sub(1, 1) == "+" then expFold = expFold:sub(2) end
    local hasExp = (expFold ~= nil and #expFold >= 2 and not expFold:find("[%s]"))
    if (not hasExp) and next(termSet) == nil then
        return rawText
    end

    local foldedAll = self:FoldSearchText(rawText)
    if foldedAll == "" then
        return rawText
    end
    local anyHit = hasExp and (foldedAll:find(expFold, 1, true) ~= nil) or false
    if not anyHit then
        for term in pairs(termSet) do
            if foldedAll:find(term, 1, true) then
                anyHit = true
                break
            end
        end
    end
    if not anyHit then
        return rawText
    end

    local function HighlightPlainChunk(seg)
        if not seg or seg == "" then return seg end
        local outParts = {}
        local p = 1
        local slen = #seg
        local changed = false
        while p <= slen do
            local wStart, wEnd = seg:find("[^%s%p]+", p)
            if not wStart then
                outParts[#outParts + 1] = seg:sub(p)
                break
            end
            local word = seg:sub(wStart, wEnd)
            local fWord = self:FoldSearchText(word)
            local matched = (fWord ~= "") and ((termSet[fWord] == true) or (hasExp and fWord == expFold))
            if wStart > p then
                local gap = seg:sub(p, wStart - 1)
                if matched and gap:sub(-1) == "@" then
                    if #gap > 1 then
                        outParts[#outParts + 1] = gap:sub(1, -2)
                    end
                    outParts[#outParts + 1] = "|cffffd026@" .. word .. "|r"
                    changed = true
                else
                    outParts[#outParts + 1] = gap
                    if matched then
                        outParts[#outParts + 1] = "|cffffd026" .. word .. "|r"
                        changed = true
                    else
                        outParts[#outParts + 1] = word
                    end
                end
            else
                if matched then
                    outParts[#outParts + 1] = "|cffffd026" .. word .. "|r"
                    changed = true
                else
                    outParts[#outParts + 1] = word
                end
            end
            p = wEnd + 1
        end
        return changed and table.concat(outParts) or seg
    end

    local out = {}
    local pos = 1
    local len = #rawText
    while pos <= len do
        local hStart, hEnd = rawText:find("|H.-|h.-|h", pos)
        local tStart, tEnd = rawText:find("|T.-|t", pos)
        local cStart, cEnd = rawText:find("|c%x%x%x%x%x%x%x%x.-|r", pos)
        local nextStart, nextEnd = nil, nil
        if hStart then nextStart, nextEnd = hStart, hEnd end
        if tStart and (not nextStart or tStart < nextStart) then nextStart, nextEnd = tStart, tEnd end
        if cStart and (not nextStart or cStart < nextStart) then nextStart, nextEnd = cStart, cEnd end
        local segEnd = nextStart and (nextStart - 1) or len
        if segEnd >= pos then
            out[#out + 1] = HighlightPlainChunk(rawText:sub(pos, segEnd))
        end
        if nextStart and nextEnd then
            out[#out + 1] = rawText:sub(nextStart, nextEnd)
            pos = nextEnd + 1
        else
            break
        end
    end
    return table.concat(out)
end

local function OnChatEvent(event, textRaw, authorRaw, ...)
    if not Chat:IsChatHistoryCaptureEnabled() then
        return
    end
    if Safe.IsSecret(textRaw) or Safe.IsSecret(authorRaw) then
        return
    end
    local text = Safe.String(textRaw)
    if not text or text == "" then return end

    local evLineId = (Chat._lineTrack and Chat._lineTrack.events[event]) and Safe.Number(select(9, ...)) or nil
    if evLineId and evLineId ~= 0 and Chat:IsChatLineRecorded(event, evLineId) then
        return
    end

    if event == "CHAT_MSG_AFK" or event == "CHAT_MSG_DND" then
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        if not parsed or Compat.IsMe(parsed.displayName) then return end
        local guid = Safe.String(select(10, ...))
        local _, _, _, bnAccId = FindBNetWoWGameAccountByChar(parsed, guid)
        local linked = FindLinkedDirectThread(parsed, bnAccId)
        local t = linked or Chat.threads["w:" .. parsed.lookupKey]
        if not t then return end

        local statusKind = (event == "CHAT_MSG_DND") and "DND" or "AFK"
        local cleanMsg = Compat.CleanInput(text) or text
        local now = time()
        t.peerStatus = statusKind
        t.peerStatusMsg = cleanMsg
        t.peerStatusAt = now
        local dedupSig = statusKind .. "|" .. cleanMsg
        if t._lastAutoStatusKey ~= dedupSig or (now - (t._lastAutoStatusAt or 0)) >= 60 then
            t._lastAutoStatusKey = dedupSig
            t._lastAutoStatusAt = now
            local statusHeader = (statusKind == "DND") and L["Busy (DND) auto-reply"] or L["Away (AFK) auto-reply"]
            AppendMessage(t, statusHeader, cleanMsg, false, nil, true, true, {
                isStatusNotice = true,
                statusKind = statusKind,
            })
        else
            QueueChatEmit(0.1)
        end
        return
    end

    local incoming = not (event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM")
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        if not parsed then return end
        local guid = Safe.String(select(10, ...))
        if incoming then
            local lineID = evLineId or Safe.Number(select(9, ...))
            local okBlk, isBlk = pcall(Chat.IsMessageBlockedByShield, Chat, event, text, author, guid, lineID, L["Whisper"])
            if okBlk and isBlk then
                Chat:MarkChatLineRecorded(event, lineID)
                return
            end
        end
        if guid and parsed.surname and Compat.CacheForeverFullName then
            Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
        end
        if incoming then
            local map = Chat.seenOnlineChars
            if not map then
                map = {}
                Chat.seenOnlineChars = map
                Chat._seenOnlineCount = 0
            end
            local nowSeen = time()
            if not map[parsed.lookupKey] then
                if (Chat._seenOnlineCount or 0) >= 400 then
                    local kept = 0
                    for k, seenTs in pairs(map) do
                        if (nowSeen - seenTs) > 7200 then
                            map[k] = nil
                        else
                            kept = kept + 1
                        end
                    end
                    if kept >= 400 then
                        wipe(map)
                        Chat._seenOnlineCount = 0
                    else
                        Chat._seenOnlineCount = kept
                    end
                end
                Chat._seenOnlineCount = (Chat._seenOnlineCount or 0) + 1
            end
            map[parsed.lookupKey] = nowSeen
        end
        local monoNow = GetTime and GetTime() or 0
        if Chat.sessionOfflineChars then
            Chat.sessionOfflineChars[parsed.lookupKey] = nil
        end
        local manualRec
        if (not incoming) and Chat.lastManualWhisperSend and (monoNow - (Chat.lastManualWhisperSend.sentAt or 0)) <= 8.0 then
            local r = Chat.lastManualWhisperSend
            local rFirst = r.targetDisplay and select(2, Compat.ParseCharacterFields(r.targetDisplay))
            if (r.lookupKey and r.lookupKey == parsed.lookupKey)
                or ((not parsed.surname) and rFirst and parsed.firstName and rFirst:lower() == parsed.firstName:lower())
            then
                manualRec = r
                manualRec.delivered = true
                Chat.lastManualWhisperSend = nil
            end
        end

        local _, _, bnAccName, bnAccId = FindBNetWoWGameAccountByChar(parsed, guid)
        local linked = (manualRec and manualRec.threadKey and Chat.threads[manualRec.threadKey])
            or FindLinkedDirectThread(parsed, bnAccId)
        if linked and guid and not parsed.surname and Compat.CacheForeverFullName then
            local refName = (manualRec and manualRec.targetDisplay) or linked.targetName
            if refName then
                local _, rFirst, rDisp, rSur = Compat.ParseCharacterFields(refName)
                if rSur and rFirst and parsed.firstName and rFirst:lower() == parsed.firstName:lower() then
                    Compat.CacheForeverFullName(guid, rDisp, rFirst)
                end
            end
        end
        local peerDispResolved = (manualRec and manualRec.targetDisplay)
            or ResolveChatSenderDisplay(parsed.displayName, guid, linked and linked.targetName or nil)
        local peerParsed = Compat.ParseCharacterName(peerDispResolved) or parsed
        if Chat.sessionOfflineChars and peerParsed and peerParsed.lookupKey then
            Chat.sessionOfflineChars[peerParsed.lookupKey] = nil
        end
        local key = (linked and linked.key) or ("w:" .. peerParsed.lookupKey)
        local kind = (linked and linked.kind) or "WHISPER"
        local title = (linked and linked.title and linked.title ~= "" and linked.title) or peerParsed.displayName
        local cls = LookupClassFromCache(peerParsed.lookupKey, guid)
        local resolvedLvl = LookupLevelFromCache(peerParsed.lookupKey, peerParsed.displayName, guid, bnAccId)
        local t = EnsureThread(key, kind, title, {
            targetName = PickNonClobberTarget(linked, peerParsed.displayName),
            bnetAccountID = bnAccId or (linked and linked.bnetAccountID),
            bnetName = bnAccName or (linked and linked.bnetName),
            classFile = (linked and linked.classFile) or cls,
            level = (linked and linked.level) or resolvedLvl,
        })
        if t and peerParsed and peerParsed.displayName then
            SyncActiveCharacterOnThread(t, peerParsed.displayName, cls, nil)
        end
        if t and peerParsed.surname and peerParsed.surname ~= "" and t.kind == "WHISPER" then
            MergeSingleFirstThreadInto(t, peerParsed.firstName)
        end
        if t and incoming then
            t.peerStatus = nil
            t.peerStatusMsg = nil
            t.peerStatusAt = nil
        end
        local meDisplay = GetMyInfo()
        local _, myClass = Safe.Call(UnitClass, "player")
        local senderLabel = incoming and peerDispResolved or meDisplay
        local targetCharLabel = incoming and meDisplay or peerDispResolved
        local loggedText = (manualRec and manualRec.sentText == text and manualRec.text and manualRec.text ~= "") and manualRec.text or text
        local alreadyAppended = (not incoming)
            and manualRec ~= nil
            and manualRec.optimisticEntry ~= nil
            and t ~= nil
            and manualRec.threadKey == t.key
            and (manualRec.sentText == text or manualRec.text == text)
        if not alreadyAppended then
            AppendMessage(t, senderLabel, loggedText, incoming, incoming and cls or Safe.String(myClass), (kind ~= "WHISPER"), not incoming, {
                senderGuid = incoming and guid or nil,
                senderCharName = incoming and peerDispResolved or nil,
                senderLevel = incoming and resolvedLvl or nil,
                targetChar = targetCharLabel,
                targetClass = incoming and Safe.String(myClass) or cls,
                previewCategory = "WHISPER",
                previewChannelKind = "WHISPER",
            })
        else
            ns:Emit("CHAT_UPDATED")
        end
        Chat:MarkChatLineRecorded(event, evLineId)
        if not incoming then
            MarkSiblingUnreadThreadsOnReply(t, peerParsed, bnAccId or (t and t.bnetAccountID), bnAccName or (t and t.bnetName))
        end
        if incoming and not Compat.IsMe(parsed.displayName) and Chat:IsDirectChatEnabled() then
            Chat:QueuePoliteDiscoveryPing({
                targetName = peerParsed.displayName,
                lookupKey = peerParsed.lookupKey,
                bnetAccountID = bnAccId,
                guid = guid,
                allowWhisperReply = true,
                priority = true,
            })
        end
        return
    end

    if event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        -- 11th arg after author is presenceID / bnSenderID (13th total arg -> index 11 in varargs).
        local presenceID = Safe.Number(select(11, ...))
        local author = Safe.String(authorRaw) or ("BNet #" .. tostring(presenceID or "?"))
        local _, fullChar, _, canonId = FindBNetWoWGameAccount(presenceID)
        local resolvedBNetId = canonId or presenceID
        local charParsed = fullChar and Compat.ParseCharacterName(fullChar)
        local monoNow = GetTime and GetTime() or 0
        local manualBnRec
        if (not incoming) and Chat.lastManualBNetSend and (monoNow - (Chat.lastManualBNetSend.sentAt or 0)) <= 8.0 then
            local r = Chat.lastManualBNetSend
            local matchedBn = false
            if r.bnetAccountID ~= nil and resolvedBNetId ~= nil then
                matchedBn = (r.bnetAccountID == resolvedBNetId)
            else
                local rawAuth = Safe.String(authorRaw)
                local authLow = rawAuth and rawAuth:lower() or nil
                local rThread = r.threadKey and Chat.threads[r.threadKey]
                local rBnetName = rThread and rThread.bnetName
                if rBnetName and authLow and tostring(rBnetName):lower() == authLow then
                    matchedBn = true
                elseif r.targetDisplay and charParsed and Compat.ParseCharacterFields then
                    local rLk = Compat.ParseCharacterFields(r.targetDisplay)
                    matchedBn = (rLk ~= nil and rLk == charParsed.lookupKey)
                elseif r.targetDisplay and authLow and tostring(r.targetDisplay):lower() == authLow then
                    matchedBn = true
                end
            end
            if matchedBn then
                manualBnRec = r
                manualBnRec.delivered = true
                Chat.lastManualBNetSend = nil
            end
        end
        local linked = (manualBnRec and manualBnRec.threadKey and Chat.threads[manualBnRec.threadKey])
            or FindLinkedDirectThread(charParsed, resolvedBNetId)
        local charFac = charParsed and Chat:GetKnownCharacterFaction(charParsed.displayName, nil, resolvedBNetId)
        local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
        local sameFacOk = (not charFac or not myFac) and true or (charFac == myFac)
        local key = (linked and linked.key)
            or (charParsed and charParsed.surname and sameFacOk and ("w:" .. charParsed.lookupKey))
            or ("bn:" .. tostring(resolvedBNetId or author:lower()))
        local kind = (linked and linked.kind) or (key:sub(1, 2) == "w:" and "WHISPER" or "BN_WHISPER")
        local title = (linked and linked.title and linked.title ~= "" and linked.title)
            or (kind == "WHISPER" and charParsed and charParsed.displayName)
            or author
        local cls = charParsed and LookupClassFromCache(charParsed.lookupKey)
        local t = EnsureThread(key, kind, title, {
            bnetAccountID = resolvedBNetId,
            bnetName = author,
            targetName = PickNonClobberTarget(linked, fullChar),
            classFile = (linked and linked.classFile) or cls,
            faction = charFac,
        })
        if t and charParsed and charParsed.displayName then
            SyncActiveCharacterOnThread(t, charParsed.displayName, cls, charFac)
        end
        local meDisplay = GetMyInfo()
        local _, myClass = Safe.Call(UnitClass, "player")
        local peerCharDisp = (charParsed and charParsed.displayName) or (manualBnRec and manualBnRec.targetDisplay) or (linked and linked.targetName)
        local hasSafeCharNames = (kind == "WHISPER" and charParsed ~= nil and peerCharDisp ~= nil and not tostring(peerCharDisp):find("#", 1, true))
        local senderLabel = incoming and (hasSafeCharNames and charParsed.displayName or author) or meDisplay
        local targetCharLabel = incoming and meDisplay or (peerCharDisp or author)
        local loggedText = (manualBnRec and manualBnRec.sentText == text and manualBnRec.text and manualBnRec.text ~= "") and manualBnRec.text or text
        local skipPersist = not hasSafeCharNames
        local alreadyAppended = (not incoming)
            and manualBnRec ~= nil
            and manualBnRec.optimisticEntry ~= nil
            and t ~= nil
            and manualBnRec.threadKey == t.key
            and (manualBnRec.sentText == text or manualBnRec.text == text)
        if not alreadyAppended then
            AppendMessage(t, senderLabel, loggedText, incoming, (incoming and cls) or (not incoming and Safe.String(myClass)) or nil, skipPersist, not incoming, {
                senderCharName = incoming and (charParsed and charParsed.displayName or peerCharDisp) or nil,
                targetChar = targetCharLabel,
                targetClass = incoming and Safe.String(myClass) or cls,
                previewCategory = "BN_WHISPER",
                previewChannelKind = "BN_WHISPER",
            })
        else
            ns:Emit("CHAT_UPDATED")
        end
        if not incoming then
            MarkSiblingUnreadThreadsOnReply(t, charParsed, resolvedBNetId or (t and t.bnetAccountID), author)
        end
        return
    end

    local chKey, chKind
    if event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        chKey, chKind = "ch:party", "PARTY"
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" then
        chKey, chKind = "ch:raid", "RAID"
    elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        chKey, chKind = "ch:instance", "INSTANCE_CHAT"
    elseif event == "CHAT_MSG_GUILD" then
        chKey, chKind = "ch:guild", "GUILD"
    elseif event == "CHAT_MSG_OFFICER" then
        chKey, chKind = "ch:officer", "OFFICER"
    end

    if chKey then
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        local guid = Safe.String(select(10, ...))
        if guid and parsed and parsed.surname and Compat.CacheForeverFullName then
            Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
        end
        local isMe = (parsed and Compat.IsMe(parsed.displayName, guid)) or (author and Compat.IsMe(author, guid))
        local s = ns.db and ns.db.settings
        local mirrorOn = (s and s.chatMirrorChannels == true)
        local pCat = (chKind == "GUILD" or chKind == "OFFICER") and "GUILD" or "GROUP"
        local saveChanHist = ((pCat == "GUILD") and Chat:ShouldSaveGuildHistory())
            or ((pCat == "GROUP") and Chat:ShouldSaveGroupHistory())
        local chatModOn = (not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
        local qrOn = chatModOn and s ~= nil and (s.quickReplyEnabled ~= false)
        local qrNeedsChan = qrOn and (
            ((chKind == "PARTY" or chKind == "INSTANCE_CHAT") and (s.quickReplyNotifyParty ~= false))
            or (chKind == "RAID" and (s.quickReplyNotifyRaid ~= false))
            or ((chKind == "GUILD" or chKind == "OFFICER") and (s.quickReplyNotifyGuild == true))
        )
        local previewNeedsChan = chatModOn and s ~= nil and (
            s.msgPreviewPromptAnswered ~= true
            or (s.msgPreviewEnabled ~= false and (
                (pCat == "GROUP" and s.msgPreviewGroup == true)
                or (pCat == "GUILD" and s.msgPreviewGuild == true)
            ))
        )
        local viewingChan = (ns.QuickReply and ns.QuickReply.IsViewingThread and ns.QuickReply:IsViewingThread(chKey)) == true
            or (ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible(chKey)) == true
            or (ns.UI and ns.UI.IsMainVisible and ns.UI:IsMainVisible() and Chat.activeThreadKey == chKey) == true
        local manualChanRec
        if isMe and Chat.lastManualChannelSend then
            local mc = Chat.lastManualChannelSend
            local monoNow = GetTime and GetTime() or 0
            if (monoNow - (mc.sentAt or 0)) <= 4.0 and mc.threadKey == chKey and mc.text == text then
                manualChanRec = mc
                Chat.lastManualChannelSend = nil
            elseif (monoNow - (mc.sentAt or 0)) > 4.0 then
                Chat.lastManualChannelSend = nil
            end
        end
        local meta = STATIC_CHANNEL_ORDER[chKey]
        local cls = parsed and LookupClassFromCache(parsed.lookupKey, guid)
        local senderLabel = ResolveChatSenderDisplay((parsed and parsed.displayName) or author, guid, nil)
        if isMe and not mirrorOn and not qrNeedsChan and not previewNeedsChan and not viewingChan and not saveChanHist then
            if manualChanRec and manualChanRec.optimisticEntry then
                ns:Emit("CHAT_UPDATED")
                Chat:MarkChatLineRecorded(event, evLineId)
                return
            end
            local tOwn = EnsureThread(chKey, chKind, L[meta.titleKey], { slash = meta.slash })
            AppendMessage(tOwn, senderLabel, text, false, cls, true, true, {
                senderGuid = guid,
                senderCharName = senderLabel,
                replySlash = meta.slash,
            })
            local existing = Chat.threads[chKey]
            if existing and ((existing.unread or 0) > 0 or existing.hasMention) then
                existing.unread = 0
                existing.hasMention = nil
                Chat:InvalidateUnreadCache()
            end
            ns:Emit("CHAT_THREAD_READ", {
                threadKey = chKey,
                channelKey = chKey,
                kind = chKind,
            })
            ns:Emit("CHAT_UPDATED")
            Chat:MarkChatLineRecorded(event, evLineId)
            return
        end
        local lineID = evLineId or Safe.Number(select(9, ...))
        if not isMe then
            local okBlk, isBlk = pcall(Chat.IsMessageBlockedByShield, Chat, event, text, author, guid, lineID, L[meta.titleKey])
            if okBlk and isBlk then
                Chat:MarkChatLineRecorded(event, lineID)
                return
            end
            pcall(Chat.EvaluateIncomingMention, Chat, event, text, senderLabel, parsed and parsed.lookupKey, guid, cls, L[meta.titleKey], chKey)
        end
        if not mirrorOn and not qrNeedsChan and not previewNeedsChan and not viewingChan and not saveChanHist then
            local tOwn = EnsureThread(chKey, chKind, L[meta.titleKey], { slash = meta.slash })
            AppendMessage(tOwn, senderLabel, text, not isMe, cls, true, (isMe == true) or Chat:IsThreadMuted(chKey), {
                senderGuid = guid,
                senderCharName = senderLabel,
                previewCategory = pCat,
                previewChannelKind = chKind,
                replySlash = meta.slash,
            })
            Chat:MarkChatLineRecorded(event, lineID)
            return
        end
        if (mirrorOn or qrNeedsChan or previewNeedsChan or viewingChan or saveChanHist) and event ~= "CHAT_MSG_RAID_WARNING" then
            if isMe and manualChanRec and manualChanRec.optimisticEntry then
                ns:Emit("CHAT_UPDATED")
            else
                local t = EnsureThread(chKey, chKind, L[meta.titleKey], { slash = meta.slash })
                AppendMessage(t, senderLabel, text, not isMe, cls, not saveChanHist, isMe == true, {
                    senderGuid = guid,
                    senderCharName = senderLabel,
                    previewCategory = pCat,
                    previewChannelKind = chKind,
                    replySlash = meta.slash,
                })
            end
        elseif event == "CHAT_MSG_RAID_WARNING" then
            local raidMeta = STATIC_CHANNEL_ORDER["ch:raid"]
            local tRaid = EnsureThread("ch:raid", "RAID", (raidMeta and L[raidMeta.titleKey]) or L["Raid"], { slash = "/ra " })
            AppendMessage(tRaid, senderLabel, "[" .. L["Raid Warning"] .. "] " .. text, not isMe, cls, not saveChanHist, isMe == true, {
                senderGuid = guid,
                senderCharName = senderLabel,
                previewCategory = "GROUP",
                previewChannelKind = "RAID",
                replySlash = "/ra ",
            })
        elseif isMe then
            local existing = Chat.threads[chKey]
            if existing and ((existing.unread or 0) > 0 or existing.hasMention) then
                existing.unread = 0
                existing.hasMention = nil
                Chat:InvalidateUnreadCache()
            end
            ns:Emit("CHAT_THREAD_READ", {
                threadKey = chKey,
                channelKey = chKey,
                kind = chKind,
            })
            ns:Emit("CHAT_UPDATED")
        end
        Chat:MarkChatLineRecorded(event, lineID)
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        local guid = Safe.String(select(10, ...))
        local isMe = (parsed and Compat.IsMe(parsed.displayName, guid)) or (author and Compat.IsMe(author, guid))
        local isSayOrYell = (event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL")
        local chLabel = Safe.String(select(2, ...)) or Safe.String(select(7, ...))
        local lineID = evLineId or Safe.Number(select(9, ...))
        local cls = (isMe and Safe.String(select(2, Safe.Call(UnitClass, "player")))) or (parsed and LookupClassFromCache(parsed.lookupKey, guid))
        local senderLabel = isMe and GetMyInfo() or ResolveChatSenderDisplay((parsed and parsed.displayName) or author, guid, nil)
        if not isMe then
            if Chat:IsMessageBlockedByShield(event, text, author, guid, lineID, chLabel) then
                if isSayOrYell then
                    Chat:MarkChatLineRecorded(event, lineID)
                end
                return
            end
            Chat:EvaluateIncomingMention(event, text, senderLabel, parsed and parsed.lookupKey, guid, cls, GetShortChannelLabel(event, chLabel), isSayOrYell and "ch:general" or nil)
        end
        if isSayOrYell then
            local s = ns.db and ns.db.settings
            local capOn = Chat.IsChatHistoryCaptureEnabled and Chat:IsChatHistoryCaptureEnabled() or true
            if capOn and ((not s) or s.quickReplyRecordSay ~= false) then
                local sayKind = (event == "CHAT_MSG_YELL") and "LOCAL_YELL" or "LOCAL_SAY"
                Chat:RecordGeneralMessage(sayKind, senderLabel, text, isMe, cls, nil, {
                    senderGuid = guid,
                    senderCharName = senderLabel,
                })
                if (not isMe) and s and s.quickReplyNotifySay == true and not Chat:IsThreadMuted("ch:general") then
                    PlayIncomingChime(sayKind, "ch:general", false, (parsed and parsed.lookupKey) or "ch:general")
                end
            end
            Chat:MarkChatLineRecorded(event, lineID)
        else
            local chId = Safe.Number(select(6, ...)) or tonumber((chLabel or ""):match("^(%d+)%."))
            local commClubId = Safe.Number(select(16, ...))
            local commStreamId = Safe.Number(select(17, ...))
            local pubTag = ShortenOfficialChannelLabel(chLabel) or chLabel
            if (not pubTag or pubTag == "" or pubTag:find("Community:", 1, true)) and (commClubId or chId) then
                if chId then
                    local liveInfo = Chat:GetOfficialChannelInfo(chId)
                    if liveInfo and liveInfo.title then
                        pubTag = liveInfo.title
                    end
                elseif commClubId and Chat.GetJoinedOfficialChannels then
                    for _, ch in ipairs(Chat:GetJoinedOfficialChannels()) do
                        if ch.clubId == commClubId and (not commStreamId or ch.streamId == commStreamId) then
                            chId = ch.id
                            pubTag = ch.title
                            break
                        end
                    end
                    if (not pubTag or pubTag == "") and Chat.ParseCommunityChannelName then
                        pubTag = Chat:ParseCommunityChannelName("Community:" .. tostring(commClubId) .. ":" .. tostring(commStreamId or 1))
                    end
                end
            end
            local genSenderKey = Chat:_ExtractGeneralSenderKey((parsed and parsed.displayName) or author, isMe == true)
            if not Chat:_WasRecentlyRecordedInGeneral(text, genSenderKey) then
                Chat:RecordGeneralMessage("PUB_CHANNEL", senderLabel, text, isMe, cls, pubTag or L["Channel"], {
                    senderGuid = guid,
                    senderCharName = senderLabel,
                    channelId = chId,
                })
            end
            Chat:MarkChatLineRecorded(event, lineID)
        end
    end
end
Chat._dispatchOfficialFallback = OnChatEvent

function Chat:IsErrorOriginTaggingEnabled()
    return not ns.db or not ns.db.settings or ns.db.settings.chatErrorOriginTags ~= false
end

function Chat:RecordOutboundOrigin(kind, chatType, target, origin, prefix)
    if not self:IsErrorOriginTaggingEnabled() then return end
    if not origin or origin == "" then return end
    local monoNow = (GetTime and GetTime()) or 0
    local cleanChatType = (type(chatType) == "string" and not Safe.IsSecret(chatType)) and chatType or (Safe.String(chatType) or "")
    local cleanTarget = ""
    local fullLow = ""
    local baseLow = ""
    local lookupKey = ""
    if cleanChatType == "WHISPER" then
        cleanTarget = (type(target) == "string" and not Safe.IsSecret(target)) and target or (Safe.String(target) or "")
        if cleanTarget ~= "" then
            local trimmed = (Compat.Trim and Compat.Trim(cleanTarget)) or cleanTarget:match("^%s*(.-)%s*$") or ""
            if trimmed ~= "" then
                fullLow = (Compat.LowerUtf8 and Compat.LowerUtf8(trimmed)) or trimmed:lower()
                local stripped = trimmed:gsub("%-[^%-]+$", "")
                baseLow = (Compat.LowerUtf8 and Compat.LowerUtf8(stripped)) or stripped:lower()
                if Compat.ParseCharacterFields then
                    lookupKey = Compat.ParseCharacterFields(trimmed) or ""
                elseif Compat.ParseCharacterName then
                    local parsed = Compat.ParseCharacterName(trimmed)
                    lookupKey = (parsed and parsed.lookupKey) or ""
                end
            end
        end
    end
    local ring = self._outboundOriginRing
    if not ring then
        ring = {}
        self._outboundOriginRing = ring
    end
    local cap = 64
    local head = self._outboundOriginHead or 0
    local count = self._outboundOriginCount or 0
    local writeIdx = (head % cap) + 1
    local rec = ring[writeIdx]
    if type(rec) ~= "table" then
        rec = {}
        ring[writeIdx] = rec
    end
    rec.at = monoNow
    rec.kind = kind or "ADDON_MSG"
    rec.chatType = cleanChatType
    rec.target = cleanTarget
    rec.fullLow = fullLow
    rec.baseLow = baseLow
    rec.lookupKey = lookupKey
    rec.origin = origin
    rec.prefix = (type(prefix) == "string" and not Safe.IsSecret(prefix)) and prefix or (Safe.String(prefix) or "")
    self._outboundOriginHead = writeIdx
    if count < cap then
        self._outboundOriginCount = count + 1
    end
end

function Chat:InstallErrorOriginTracker()
    if self._errorOriginTrackerInstalled then return end
    self._errorOriginTrackerInstalled = true
    self._addonPrefixOwners = self._addonPrefixOwners or {}

    local sharedLibMarkers = {
        "chatthrottlelib", "acecomm", "acetimer", "acehook",
        "aceevent", "aceaddon", "callbackhandler", "libstub",
    }

    local function IsSharedCommPath(relLow)
        if not relLow or relLow == "" then return false end
        for _, marker in ipairs(sharedLibMarkers) do
            if relLow:find(marker, 1, true) then
                return true
            end
        end
        return false
    end

    local function NormalizeHookLoc(stackLine)
        if type(stackLine) ~= "string" then return nil end
        local norm = stackLine:gsub("\\", "/"):lower()
        return norm:match("(providers/chat%.lua:%d+)")
    end

    local function ResolveStackOrigin(prefix, allowLibFallback, rawStack, hookLoc)
        if prefix and prefix ~= "" then
            local cached = Chat._addonPrefixOwners[prefix]
            if cached and cached ~= "SocialCentral" and not cached:find("^Shared") then
                return cached
            end
        end
        if type(rawStack) ~= "string" or rawStack == "" then
            return (prefix and Chat._addonPrefixOwners[prefix]) or nil
        end
        local sawBlizzChat = false
        local firstLibAddon = nil
        for line in rawStack:gmatch("[^\r\n]+") do
            local lineNorm = line:gsub("\\", "/"):lower()
            if (hookLoc and lineNorm:find(hookLoc, 1, true))
                or (Chat._addonMsgHookLoc and lineNorm:find(Chat._addonMsgHookLoc, 1, true))
                or (Chat._regPrefixHookLoc and lineNorm:find(Chat._regPrefixHookLoc, 1, true))
            then
                -- Skip our own hook wrapper frames if debugstack includes them.
            else
                local folder, relPath = line:match('[Aa][Dd][Dd][Oo][Nn][Ss][\\/]([^\\/:"]+)[\\/]([^:"]*)')
                if folder and folder ~= "" then
                    local folderLow = folder:lower()
                    if folderLow:sub(1, 9) == "blizzard_" then
                        if folderLow:find("chatframe", 1, true) or folderLow:find("friends", 1, true) then
                            sawBlizzChat = true
                        end
                    else
                        local relLow = (relPath or ""):lower()
                        if IsSharedCommPath(relLow) then
                            if not firstLibAddon then
                                firstLibAddon = folder
                            end
                        else
                            if prefix and prefix ~= "" then
                                Chat._addonPrefixOwners[prefix] = folder
                            end
                            return folder
                        end
                    end
                end
            end
        end
        if prefix and prefix ~= "" and Chat._addonPrefixOwners[prefix] then
            return Chat._addonPrefixOwners[prefix]
        end
        if sawBlizzChat then
            return L["Manual Chat"]
        end
        if allowLibFallback and prefix and prefix ~= "" then
            return L["Shared Library"] .. " (" .. prefix .. ")"
        end
        return firstLibAddon
    end

    if type(hooksecurefunc) ~= "function" then return end

    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        hooksecurefunc(C_ChatInfo, "RegisterAddonMessagePrefix", function(prefixRaw)
            if not Chat:IsErrorOriginTaggingEnabled() then return end
            if Safe.IsSecret(prefixRaw) or type(prefixRaw) ~= "string" or prefixRaw == "" then return end
            local p = prefixRaw
            if not Chat._addonPrefixOwners[p] then
                if (Chat._addonPrefixOwnerCount or 0) >= 250 then
                    Chat._addonPrefixOwners = {}
                    Chat._addonPrefixOwnerCount = 0
                end
                if not Chat._regPrefixHookLoc and type(debugstack) == "function" then
                    Chat._regPrefixHookLoc = NormalizeHookLoc(debugstack(1, 1, 0))
                end
                local rawStack = type(debugstack) == "function" and debugstack(2, 14, 0) or nil
                local owner = ResolveStackOrigin(p, false, rawStack, Chat._regPrefixHookLoc)
                if owner and owner ~= "" then
                    Chat._addonPrefixOwners[p] = owner
                    Chat._addonPrefixOwnerCount = (Chat._addonPrefixOwnerCount or 0) + 1
                end
            end
        end)
    end

    local sharedLibLabelPrefix = tostring(L["Shared Library"] or "Shared")
    local function IsSharedOwnerLabel(lbl)
        if type(lbl) ~= "string" or lbl == "" then return false end
        return lbl:find("^Shared") ~= nil or (sharedLibLabelPrefix ~= "" and lbl:sub(1, #sharedLibLabelPrefix) == sharedLibLabelPrefix)
    end

    local function OnAddonMsgHook(prefixRaw, _, chatTypeRaw, targetRaw)
        if not Chat:IsErrorOriginTaggingEnabled() then return end
        local p = (not Safe.IsSecret(prefixRaw) and type(prefixRaw) == "string") and prefixRaw or (Safe.String(prefixRaw) or "")
        local cachedOwner = (p ~= "" and Chat._addonPrefixOwners[p]) or nil
        local origin
        if p == PREFIX or p == "SCentral1" then
            origin = "SocialCentral"
        elseif cachedOwner and cachedOwner ~= "SocialCentral" and not IsSharedOwnerLabel(cachedOwner) then
            origin = cachedOwner
        else
            Chat._addonSharedProbeTries = Chat._addonSharedProbeTries or {}
            local probeKey = (p ~= "") and p or "__empty__"
            local tries = Chat._addonSharedProbeTries[probeKey] or 0
            local inCombatNow = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
            local nowMono = (GetTime and GetTime()) or 0
            Chat._addonStackProbeAt = Chat._addonStackProbeAt or {}
            local lastProbe = Chat._addonStackProbeAt[probeKey] or 0
            if inCombatNow or (cachedOwner and tries >= 2) or (lastProbe > 0 and (nowMono - lastProbe) < 30.0) then
                origin = cachedOwner
            else
                if (Chat._addonStackProbeCount or 0) >= 250 then
                    Chat._addonStackProbeAt = {}
                    Chat._addonSharedProbeTries = {}
                    Chat._addonStackProbeCount = 0
                end
                if not Chat._addonMsgHookLoc and type(debugstack) == "function" then
                    Chat._addonMsgHookLoc = NormalizeHookLoc(debugstack(1, 1, 0))
                end
                local rawStack = type(debugstack) == "function" and debugstack(2, 14, 0) or nil
                origin = ResolveStackOrigin(p, true, rawStack, Chat._addonMsgHookLoc)
                if Chat._addonStackProbeAt[probeKey] == nil then
                    Chat._addonStackProbeCount = (Chat._addonStackProbeCount or 0) + 1
                end
                Chat._addonStackProbeAt[probeKey] = nowMono
                Chat._addonSharedProbeTries[probeKey] = tries + 1
                if p ~= "" and origin and origin ~= "" and not Chat._addonPrefixOwners[p] then
                    if (Chat._addonPrefixOwnerCount or 0) >= 250 then
                        Chat._addonPrefixOwners = {}
                        Chat._addonPrefixOwnerCount = 0
                    end
                    Chat._addonPrefixOwners[p] = origin
                    Chat._addonPrefixOwnerCount = (Chat._addonPrefixOwnerCount or 0) + 1
                end
            end
        end
        if origin and origin ~= "" then
            Chat:RecordOutboundOrigin("ADDON_MSG", chatTypeRaw, targetRaw, origin, p)
        end
    end

    if C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function" then
        hooksecurefunc(C_ChatInfo, "SendAddonMessage", OnAddonMsgHook)
    end
    if type(_G.SendAddonMessage) == "function" and (not C_ChatInfo or _G.SendAddonMessage ~= C_ChatInfo.SendAddonMessage) then
        hooksecurefunc("SendAddonMessage", OnAddonMsgHook)
    end
    if C_ChatInfo and type(C_ChatInfo.SendAddonMessageLogged) == "function" then
        hooksecurefunc(C_ChatInfo, "SendAddonMessageLogged", OnAddonMsgHook)
    end

    if type(_G.ChatEdit_SendText) == "function" then
        hooksecurefunc("ChatEdit_SendText", function(eb)
            if not eb then return end
            local txt = Safe.String(eb.GetText and eb:GetText() or nil) or ""
            if txt ~= "" and eb._scDockedToQr and ns.QuickReply then
                if ns.QuickReply.PushHistoryLine then
                    ns.QuickReply:PushHistoryLine(txt)
                end
                if ns.QuickReply.RecordRecentSentThread and ns.QuickReply.activeKey then
                    ns.QuickReply:RecordRecentSentThread(ns.QuickReply.activeKey)
                end
                local nowT = (GetTime and GetTime()) or 0
                ns.QuickReply.hasTyped = true
                ns.QuickReply.hasSentInSession = true
                ns.QuickReply.interactedOutside = false
                ns.QuickReply.lastInputAt = nowT
                ns.QuickReply._lastOpaqueActivityAt = nowT
                ns.QuickReply.idleCountdown = nil
            end
            if not Chat:IsErrorOriginTaggingEnabled() then return end
            local ct = Safe.String(eb.GetAttribute and eb:GetAttribute("chatType") or nil) or ""
            local tgt = Safe.String(eb.GetAttribute and eb:GetAttribute("tellTarget") or nil) or ""
            if txt:match("^/[wW][hH][oO]%s*(.*)$") then
                local q = txt:match("^/[wW][hH][oO]%s*(.*)$") or ""
                Chat:RecordOutboundOrigin("WHO", "WHO", q, L["Manual Chat"])
                return
            end
            local slashW = txt:match("^/[wW]%s+([^%s]+)") or txt:match("^/[wW][hH][iI][sS][pP][eE][rR]%s+([^%s]+)")
            if slashW and slashW ~= "" then
                Chat:RecordOutboundOrigin("CHAT", "WHISPER", slashW, L["Manual Chat"])
                return
            end
            if ct ~= "" then
                Chat:RecordOutboundOrigin("CHAT", ct, tgt, L["Manual Chat"])
            end
        end)
    end
end

function Chat:DecorateSystemErrorOrigin(msgRaw, lineID)
    if not self:IsErrorOriginTaggingEnabled() or Safe.IsSecret(msgRaw) then
        return nil
    end
    local msg = Safe.String(msgRaw)
    if not msg or msg == "" then
        return nil
    end
    local tagPrefixCheck = string.format(L["Origin: %s"], ""):match("^([^%%]+)") or "Origin:"
    if msg:find("[" .. tagPrefixCheck, 1, true) then
        return nil
    end

    local monoNow = (GetTime and GetTime()) or 0
    local cacheKey = (lineID and lineID ~= 0) and ("id:" .. tostring(lineID)) or ("txt:" .. msg)
    self._errorOriginLineCache = self._errorOriginLineCache or {}
    local cached = self._errorOriginLineCache[cacheKey]
    if type(cached) == "table" and (monoNow - (cached.at or 0)) <= 1.5 then
        return cached.tagged
    end
    local cacheCount = 0
    for k, v in pairs(self._errorOriginLineCache) do
        if type(v) ~= "table" or (monoNow - (v.at or 0)) > 2.0 then
            self._errorOriginLineCache[k] = nil
        else
            cacheCount = cacheCount + 1
        end
    end
    if cacheCount > 60 then
        wipe(self._errorOriginLineCache)
    end

    if not self._sysErrPatterns then
        local function BuildErrPat(globalStr, captureArg)
            if type(globalStr) ~= "string" or globalStr == "" then return nil end
            local p = globalStr:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            if captureArg then
                p = p:gsub("%%%%s", "(.+)")
            end
            return "^" .. p .. "$"
        end
        self._sysErrPatterns = {
            notFound = BuildErrPat(_G.ERR_CHAT_PLAYER_NOT_FOUND_S, true),
            ignoring = BuildErrPat(_G.ERR_CHAT_PLAYER_IGNORING_YOU_S, true),
            wrongFaction = BuildErrPat(_G.ERR_CHAT_WRONG_FACTION, false),
            notInGuild = BuildErrPat(_G.ERR_GUILD_PLAYER_NOT_IN_GUILD, false),
            notInGroup = BuildErrPat(_G.ERR_NOT_IN_GROUP, false),
            notInParty = BuildErrPat(_G.ERR_NOT_IN_PARTY_S or _G.ERR_NOT_IN_GROUP, false),
            notInRaid = BuildErrPat(_G.ERR_NOT_IN_RAID, false),
            throttled = BuildErrPat(_G.ERR_CHAT_THROTTLED, false),
            genThrottle = BuildErrPat(_G.ERR_GENERIC_THROTTLE, false),
        }
    end

    local pats = self._sysErrPatterns
    local lowerMsg = (Compat.LowerUtf8 and Compat.LowerUtf8(msg)) or msg:lower()
    local matchCategory = nil
    local extractedTarget = nil

    local nfMatch = pats.notFound and msg:match(pats.notFound)
    if nfMatch and nfMatch ~= "" then
        matchCategory = "WHISPER_TARGET"
        extractedTarget = nfMatch
    elseif lowerMsg:find("no player named", 1, true)
        or lowerMsg:find("nenhum jogador", 1, true)
        or lowerMsg:find("ningún jugador", 1, true)
        or lowerMsg:find("ningun jugador", 1, true)
    then
        matchCategory = "WHISPER_TARGET"
        extractedTarget = msg:match("'([^']+)'")
    end

    if not matchCategory then
        local igMatch = pats.ignoring and msg:match(pats.ignoring)
        if igMatch and igMatch ~= "" then
            matchCategory = "WHISPER_TARGET"
            extractedTarget = igMatch
        elseif lowerMsg:find("is ignoring you", 1, true)
            or lowerMsg:find("está ignorando", 1, true)
            or lowerMsg:find("te está ignorando", 1, true)
        then
            matchCategory = "WHISPER_TARGET"
            extractedTarget = msg:match("'([^']+)'") or msg:match("^([^%s]+)")
        end
    end

    if not matchCategory then
        if (pats.wrongFaction and msg:find(pats.wrongFaction))
            or lowerMsg:find("opposite faction", 1, true)
            or lowerMsg:find("facção oposta", 1, true)
            or lowerMsg:find("facción opuesta", 1, true)
        then
            matchCategory = "WHISPER_ANY"
        elseif (pats.notInGuild and msg:find(pats.notInGuild))
            or lowerMsg:find("not in a guild", 1, true)
            or lowerMsg:find("não está em uma guilda", 1, true)
            or lowerMsg:find("no estás en una hermandad", 1, true)
        then
            matchCategory = "GUILD"
        elseif (pats.notInGroup and msg:find(pats.notInGroup))
            or (pats.notInParty and msg:find(pats.notInParty))
            or (pats.notInRaid and msg:find(pats.notInRaid))
            or lowerMsg:find("not in a party", 1, true)
            or lowerMsg:find("not in a raid", 1, true)
            or lowerMsg:find("não faz parte de um grupo", 1, true)
            or lowerMsg:find("no estás en un grupo", 1, true)
        then
            matchCategory = "GROUP"
        elseif (pats.throttled and msg:find(pats.throttled))
            or (pats.genThrottle and msg:find(pats.genThrottle))
            or lowerMsg:find("sending messages too quickly", 1, true)
            or lowerMsg:find("enviando mensagens", 1, true)
            or lowerMsg:find("enviando mensajes", 1, true)
        then
            matchCategory = "THROTTLE"
        end
    end

    if not matchCategory then
        self._errorOriginLineCache[cacheKey] = { at = monoNow, tagged = false }
        return nil
    end

    local origins = {}
    local seenOrigin = {}
    local function PushOrigin(name)
        if not name or name == "" or seenOrigin[name] then return end
        seenOrigin[name] = true
        origins[#origins + 1] = name
    end

    local ring = self._outboundOriginRing or {}
    local ringCap = 64
    local ringCount = self._outboundOriginCount or #ring
    local ringHead = self._outboundOriginHead or ringCount
    if matchCategory == "WHISPER_TARGET" and extractedTarget and extractedTarget ~= "" then
        local trimmedTgt = (Compat.Trim and Compat.Trim(extractedTarget)) or extractedTarget:match("^%s*(.-)%s*$") or ""
        local tgtFullLow = (Compat.LowerUtf8 and Compat.LowerUtf8(trimmedTgt)) or trimmedTgt:lower()
        local tgtStripped = trimmedTgt:gsub("%-[^%-]+$", "")
        local tgtBaseLow = (Compat.LowerUtf8 and Compat.LowerUtf8(tgtStripped)) or tgtStripped:lower()
        local tgtParsed = Compat.ParseCharacterName and Compat.ParseCharacterName(trimmedTgt)
        local tgtLk = (tgtParsed and tgtParsed.lookupKey) or ""

        for step = 0, ringCount - 1 do
            local idx = ((ringHead - 1 - step) % ringCap) + 1
            local item = ring[idx]
            if item and (monoNow - (item.at or 0)) <= 10.0 and item.chatType == "WHISPER" then
                local matched = (tgtFullLow ~= "" and (item.fullLow == tgtFullLow or item.baseLow == tgtFullLow))
                    or (tgtBaseLow ~= "" and (item.fullLow == tgtBaseLow or item.baseLow == tgtBaseLow))
                    or (tgtLk ~= "" and item.lookupKey == tgtLk)
                if matched then
                    PushOrigin(item.origin)
                    if #origins >= 2 then break end
                end
            end
        end

        local manualRec = self.lastManualWhisperSend
        if type(manualRec) == "table" and (monoNow - (manualRec.sentAt or 0)) <= 4.5 and manualRec.targetStr then
            local mLow = (Compat.LowerUtf8 and Compat.LowerUtf8(manualRec.targetStr)) or manualRec.targetStr:lower()
            if (tgtFullLow ~= "" and mLow:find(tgtFullLow, 1, true))
                or (tgtBaseLow ~= "" and mLow:find(tgtBaseLow, 1, true))
                or (tgtLk ~= "" and manualRec.lookupKey == tgtLk)
            then
                PushOrigin(L["Manual Chat (SocialCentral)"])
            end
        end
    else
        local maxAge = (matchCategory == "WHISPER_ANY") and 8.0 or 3.5
        for step = 0, ringCount - 1 do
            local idx = ((ringHead - 1 - step) % ringCap) + 1
            local item = ring[idx]
            if item and (monoNow - (item.at or 0)) <= maxAge then
                local okMatch = false
                if matchCategory == "WHISPER_ANY" then
                    okMatch = (item.chatType == "WHISPER")
                elseif matchCategory == "GUILD" then
                    okMatch = (item.chatType == "GUILD" or item.chatType == "OFFICER")
                elseif matchCategory == "GROUP" then
                    okMatch = (item.chatType == "PARTY" or item.chatType == "RAID" or item.chatType == "INSTANCE_CHAT")
                elseif matchCategory == "THROTTLE" then
                    okMatch = true
                end
                if okMatch then
                    PushOrigin(item.origin)
                    if #origins >= 2 then break end
                end
            end
        end
    end

    if #origins == 0 then
        self._errorOriginLineCache[cacheKey] = { at = monoNow, tagged = false }
        return nil
    end

    local tagged = msg .. " |cff8fa4c4[" .. string.format(L["Origin: %s"], table.concat(origins, " / ")) .. "]|r"
    self._errorOriginLineCache[cacheKey] = { at = monoNow, tagged = tagged }
    return tagged
end

function Chat:InstallErrorOriginChatFilter()
    if self._errorOriginFilterRegistered then return end
    self._errorOriginFilterRegistered = true
    local function ErrorOriginSystemFilter(_, _, msgRaw, ...)
        if not Chat:IsErrorOriginTaggingEnabled() then
            return false
        end
        local lineID = select(10, ...)
        local tagged = Chat:DecorateSystemErrorOrigin(msgRaw, lineID)
        if tagged then
            return false, tagged, ...
        end
        return false
    end
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        pcall(ChatFrameUtil.AddMessageEventFilter, "CHAT_MSG_SYSTEM", ErrorOriginSystemFilter)
    elseif ChatFrame_AddMessageEventFilter then
        pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", ErrorOriginSystemFilter)
    end
end

function Chat:GetQuickReplyHotkeys()
    local cfg = ns.db and ns.db.settings
    if not cfg then return {} end
    if type(cfg.quickReplyHotkeys) ~= "table" then
        cfg.quickReplyHotkeys = {}
    end
    return cfg.quickReplyHotkeys
end

function Chat:SaveQuickReplyHotkey(rec)
    if not (ns.db and ns.db.settings and type(rec) == "table") then return false end
    local keyStr = Compat.Trim and Compat.Trim(tostring(rec.key or "")) or ""
    local msgStr = Compat.CleanInput and Compat.CleanInput(tostring(rec.text or "")) or ""
    if keyStr == "" or msgStr == "" then return false end
    local list = self:GetQuickReplyHotkeys()
    local idx = tonumber(rec.index)
    local item = {
        key = keyStr:upper(),
        target = tostring(rec.target or "active"),
        text = msgStr,
        enabled = (rec.enabled ~= false),
    }
    if idx and idx >= 1 and idx <= #list then
        list[idx] = item
    else
        if #list >= 12 then
            table.remove(list, 1)
        end
        list[#list + 1] = item
    end
    ns:Emit("CHAT_HOTKEYS_UPDATED")
    return true
end

function Chat:RemoveQuickReplyHotkey(index)
    local list = self:GetQuickReplyHotkeys()
    local idx = tonumber(index)
    if idx and idx >= 1 and idx <= #list then
        table.remove(list, idx)
        ns:Emit("CHAT_HOTKEYS_UPDATED")
        return true
    end
    return false
end

function Chat:GetAbilityChatMacros()
    local cfg = ns.db and ns.db.settings
    if not cfg then return {} end
    if type(cfg.abilityChatMacros) ~= "table" then
        cfg.abilityChatMacros = {}
    end
    return cfg.abilityChatMacros
end

function Chat:BuildAbilityMacroBody(spellName, chanSlash, msgText)
    local cleanSpell = Compat.Trim and Compat.Trim(tostring(spellName or "")) or ""
    local cleanMsg = Compat.CleanInput and Compat.CleanInput(tostring(msgText or "")) or ""
    local slash = tostring(chanSlash or "/p")
    if slash:sub(1, 1) ~= "/" then slash = "/" .. slash end
    local lines = {}
    if cleanSpell ~= "" then
        lines[#lines + 1] = "#showtooltip " .. cleanSpell
        lines[#lines + 1] = "/cast " .. cleanSpell
    end
    if cleanMsg ~= "" then
        local spellFn = function() return cleanSpell end
        local expanded = cleanMsg:gsub("{[Hh]abilidade}", spellFn):gsub("{[Ss]pell}", spellFn)
        lines[#lines + 1] = slash .. " " .. expanded
    end
    return table.concat(lines, "\n")
end

function Chat:SaveAndSyncAbilityChatMacro(rec)
    if not (ns.db and ns.db.settings and type(rec) == "table") then return false, "invalid" end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false, "combat"
    end
    local spellName = Compat.Trim and Compat.Trim(tostring(rec.spellName or "")) or ""
    local msgText = Compat.CleanInput and Compat.CleanInput(tostring(rec.message or "")) or ""
    local chanSlash = tostring(rec.channelSlash or "/p")
    local keyStr = Compat.Trim and Compat.Trim(tostring(rec.key or "")) or ""
    if spellName == "" or msgText == "" then
        return false, "missing_fields"
    end
    local list = self:GetAbilityChatMacros()
    local idx = tonumber(rec.index)
    local slotId = (idx and list[idx] and tonumber(list[idx].id)) or nil
    if not slotId then
        local maxId = 0
        for _, m in ipairs(list) do
            if tonumber(m.id) and tonumber(m.id) > maxId then
                maxId = tonumber(m.id)
            end
        end
        slotId = maxId + 1
    end
    local entry = {
        id = slotId,
        key = (keyStr ~= "") and keyStr:upper() or nil,
        spellName = spellName,
        channelSlash = chanSlash,
        message = msgText,
        enabled = (rec.enabled ~= false),
    }
    if idx and idx >= 1 and idx <= #list then
        list[idx] = entry
    else
        if #list >= 12 then
            table.remove(list, 1)
        end
        list[#list + 1] = entry
    end
    ns:Emit("CHAT_HOTKEYS_UPDATED")
    return true, entry
end

function Chat:RemoveAbilityChatMacro(index)
    local list = self:GetAbilityChatMacros()
    local idx = tonumber(index)
    if not (idx and idx >= 1 and idx <= #list) then
        return false
    end
    table.remove(list, idx)
    ns:Emit("CHAT_HOTKEYS_UPDATED")
    return true
end

function Chat:SplitPayloadTilde(text, maxParts)
    if type(text) ~= "string" then return {} end
    local out = {}
    local start = 1
    while true do
        if maxParts and #out + 1 >= maxParts then
            out[#out + 1] = text:sub(start)
            break
        end
        local pos = text:find("~", start, true)
        if not pos then
            out[#out + 1] = text:sub(start)
            break
        end
        out[#out + 1] = text:sub(start, pos - 1)
        start = pos + 1
    end
    return out
end

function Chat:CleanTildeField(text, maxLen)
    local cleaned = Compat and Compat.CleanPayloadField and Compat.CleanPayloadField(text or "", maxLen or 180) or Safe.String(text) or ""
    if cleaned == "" then return "" end
    cleaned = cleaned:gsub("~", "-")
    if maxLen and #cleaned > maxLen then
        cleaned = Compat and Compat.TruncateUtf8 and Compat.TruncateUtf8(cleaned, maxLen) or cleaned:sub(1, maxLen)
    end
    return cleaned
end

function Chat:GetActiveGroupSyncInfo()
    if Compat and Compat.IsModuleEnabled and not Compat.IsModuleEnabled("chat") then
        return nil, nil
    end
    local s = ns.db and ns.db.settings
    if s and s.chatGroupReconnectSync == false then
        return nil, nil
    end
    if not (Compat and Compat.IsInGroup and Compat.IsInGroup()) then
        return nil, nil
    end
    local numMembers = (Compat.GetNumGroupMembers and Compat.GetNumGroupMembers()) or 0
    local hasRealPeer = (Compat.IsInRaid and Compat.IsInRaid())
        or (numMembers >= 2)
        or (UnitExists and (UnitExists("party1") or UnitExists("raid1")))
    if not hasRealPeer then
        return nil, nil
    end
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT", "ch:instance"
    end
    if Compat.IsInRaid and Compat.IsInRaid() then
        return "RAID", "ch:raid"
    end
    return "PARTY", "ch:party"
end

function Chat:SendGroupAddonPacket(addonChan, payload)
    local okGuard, guardErr = GuardAddonMessaging(false)
    if not okGuard then
        return false, guardErr
    end
    local monoNow = GetTime and GetTime() or 0
    if ns.Clan and (ns.Clan.isStoppedThisSession or (ns.Clan.backoffUntil and monoNow < ns.Clan.backoffUntil)) then
        return false, "throttled"
    end
    if addonChan == "PARTY" and Compat and Compat.IsInRaid and Compat.IsInRaid() then
        return false, "in_raid"
    end
    if addonChan ~= "PARTY" and addonChan ~= "RAID" and addonChan ~= "INSTANCE_CHAT" then
        return false, "bad_chan"
    end
    if type(payload) ~= "string" or payload == "" or #payload > MAX_PAYLOAD_BYTES then
        return false, "too_long"
    end
    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not sendFn then
        return false, "unsupported"
    end
    local ok, res = pcall(sendFn, PREFIX, payload, addonChan)
    if not ok then
        return false, "failed"
    end
    if Enum and Enum.SendAddonMessageResult and type(res) == "number" then
        if res == Enum.SendAddonMessageResult.Success then
            return true, nil
        elseif res == Enum.SendAddonMessageResult.AddonMessageThrottle then
            RecordThrottleStrike()
            return false, "throttled"
        elseif Enum.SendAddonMessageResult.AddonsRestricted and res == Enum.SendAddonMessageResult.AddonsRestricted then
            return false, "restricted"
        end
        return false, "failed"
    end
    return res ~= false, res == false and "failed" or nil
end

function Chat:PruneGroupCatchupState(now)
    local tsNow = now or time()
    for _, tblName in ipairs({ "_groupCatchupAnswered", "_groupCatchupSeenPeerReq", "_groupOfflineSince" }) do
        local tbl = self[tblName]
        if type(tbl) == "table" then
            local count = 0
            for k, v in pairs(tbl) do
                if (tsNow - (tonumber(v) or 0)) > 180 then
                    tbl[k] = nil
                else
                    count = count + 1
                end
            end
            if count > 40 then
                self[tblName] = {}
            end
        end
    end
    if type(self._myPendingCatchupReqIds) == "table" then
        local c = 0
        for k, exp in pairs(self._myPendingCatchupReqIds) do
            if tsNow > (tonumber(exp) or 0) then
                self._myPendingCatchupReqIds[k] = nil
            else
                c = c + 1
            end
        end
        if c > 12 then
            self._myPendingCatchupReqIds = {}
        end
    end
end

function Chat:GetLatestGroupTimestamp(threadKey)
    local t = threadKey and self.threads and self.threads[threadKey]
    if not t or type(t.messages) ~= "table" then return 0 end
    local maxTs = 0
    for i = #t.messages, math.max(1, #t.messages - 30), -1 do
        local m = t.messages[i]
        if type(m) == "table" and not m.isStatusNotice then
            local mts = tonumber(m.ts) or 0
            if mts > maxTs then
                maxTs = mts
            end
        end
    end
    return maxTs
end

function Chat:ScheduleGroupCatchupRequest(delaySec, forceNow)
    local addonChan, threadKey = self:GetActiveGroupSyncInfo()
    if not addonChan or not threadKey then return end
    local monoNow = GetTime and GetTime() or 0
    if not forceNow and (monoNow - (self._lastGroupCatchupReqMono or -999)) < 20 then
        return
    end
    if self._groupCatchupReqQueued then return end
    self._groupCatchupReqQueued = true
    local waitSec = tonumber(delaySec) or 2.5
    local sendFn = function()
        self._groupCatchupReqQueued = nil
        local chanNow, tKey = self:GetActiveGroupSyncInfo()
        if not chanNow or not tKey then return end
        local nowMono = GetTime and GetTime() or 0
        if not forceNow and (nowMono - (self._lastGroupCatchupReqMono or -999)) < 20 then
            return
        end
        local nowWall = time()
        local latestTs = self:GetLatestGroupTimestamp(tKey)
        local sinceTs = latestTs > 0 and math.max(latestTs, nowWall - 900) or math.max(0, nowWall - 600)
        self._groupCatchupReqSeq = (self._groupCatchupReqSeq or 0) + 1
        local reqId = "r" .. tostring(nowWall % 100000) .. "x" .. tostring(self._groupCatchupReqSeq)
        self._myPendingCatchupReqIds = self._myPendingCatchupReqIds or {}
        self._myPendingCatchupReqIds[reqId] = nowWall + 45
        self._awaitingGroupCatchupUntil = nowMono + 45
        local payload = string.format("GCR~%s~%d~%s", tKey, math.floor(sinceTs), reqId)
        local sent = self:SendGroupAddonPacket(chanNow, payload)
        if sent then
            self._lastGroupCatchupReqMono = nowMono
        end
    end
    if C_Timer and C_Timer.After and waitSec > 0 then
        C_Timer.After(waitSec, sendFn)
    else
        sendFn()
    end
end

function Chat:OnGroupCatchupEnteringWorld()
    local addonChan = self:GetActiveGroupSyncInfo()
    if not addonChan then
        self._groupOfflineSince = nil
        self._groupOnlineSeen = nil
        return
    end
    self:ScheduleGroupCatchupRequest(2.5, false)
end

function Chat:CollectMissedGroupMessages(threadKey, sinceTs, maxItems)
    local t = threadKey and self.threads and self.threads[threadKey]
    if not t or type(t.messages) ~= "table" then return {} end
    local nowWall = time()
    local floorTs = math.max(tonumber(sinceTs) or 0, nowWall - 900)
    local limit = math.min(maxItems or 10, 10)
    local out = {}
    for i = math.max(1, #t.messages - 50), #t.messages do
        local m = t.messages[i]
        if type(m) == "table" and not m.isStatusNotice and not m.isCatchupNotice then
            local mts = tonumber(m.ts) or 0
            if mts > floorTs and mts <= (nowWall + 5) and type(m.text) == "string" and m.text ~= "" then
                out[#out + 1] = m
            end
        end
    end
    if #out > limit then
        local trimmed = {}
        for i = (#out - limit + 1), #out do
            trimmed[#trimmed + 1] = out[i]
        end
        return trimmed
    end
    return out
end

function Chat:LaunchCooperativeCatchupSend(addonChan, threadKey, reqId, sinceTs)
    if not addonChan or not threadKey or not reqId or reqId == "" then return end
    self:PruneGroupCatchupState()
    if self._groupCatchupAnswered and self._groupCatchupAnswered[reqId] then return end
    local missed = self:CollectMissedGroupMessages(threadKey, sinceTs, 10)
    if #missed == 0 then return end
    local isLeader = Compat and Compat.IsGroupLeader and Compat.IsGroupLeader("player")
    local delay = isLeader and (0.15 + math.random() * 0.25) or (0.65 + math.random() * 1.15)
    local snapshot = {}
    for i, m in ipairs(missed) do
        local plain = tostring(m.text):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        snapshot[i] = {
            ts = math.floor(tonumber(m.ts) or time()),
            cls = self:CleanTildeField(m.classFile or "", 16),
            sender = self:CleanTildeField(m.sender or "?", 30),
            text = self:CleanTildeField(plain, 175),
        }
    end
    local function RunSend()
        if self._groupCatchupAnswered and self._groupCatchupAnswered[reqId] then return end
        local curChan, curKey = self:GetActiveGroupSyncInfo()
        if curChan ~= addonChan or curKey ~= threadKey then return end
        local claimPayload = string.format("GCA~%s~%s~%d", threadKey, reqId, #snapshot)
        local okClaim = self:SendGroupAddonPacket(curChan, claimPayload)
        if not okClaim then return end
        self._groupCatchupAnswered = self._groupCatchupAnswered or {}
        self._groupCatchupAnswered[reqId] = time()
        for idx, item in ipairs(snapshot) do
            if item.text ~= "" then
                local waitLine = (idx - 1) * 0.35
                local function SendOneLine()
                    local liveChan, liveKey = self:GetActiveGroupSyncInfo()
                    if liveChan ~= addonChan or liveKey ~= threadKey then return end
                    local prefixStr = string.format("GCM~%s~%s~%d~%s~%s~", threadKey, reqId, item.ts, item.cls, item.sender)
                    local room = MAX_PAYLOAD_BYTES - #prefixStr
                    if room < 8 then return end
                    local body = (#item.text > room) and ((Compat and Compat.TruncateUtf8 and Compat.TruncateUtf8(item.text, room)) or item.text:sub(1, room)) or item.text
                    self:SendGroupAddonPacket(liveChan, prefixStr .. body)
                end
                if C_Timer and C_Timer.After and waitLine > 0 then
                    C_Timer.After(waitLine, SendOneLine)
                else
                    SendOneLine()
                end
            end
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, RunSend)
    else
        RunSend()
    end
end

function Chat:SyncGroupConnectionSnapshot(isUnitConnEvent, unitToken, isConnectedArg)
    local addonChan, threadKey = self:GetActiveGroupSyncInfo()
    if not addonChan or not threadKey then
        self._groupOfflineSince = nil
        self._groupOnlineSeen = nil
        return
    end
    if not isUnitConnEvent or not unitToken then
        return
    end
    if unitToken == "player" then
        local selfConn = (type(isConnectedArg) == "boolean") and isConnectedArg or (UnitIsConnected and UnitIsConnected("player"))
        if selfConn == true then
            self:ScheduleGroupCatchupRequest(2.5, false)
        end
        return
    end
    local unitRes = (Compat and Compat.ResolveUnitFullName) and Compat.ResolveUnitFullName(unitToken, nil, nil, true) or nil
    local unitName = (unitRes and unitRes.fullName) or (UnitName and Safe.String(UnitName(unitToken)))
    if not unitName or unitName == "" then return end
    if Compat and Compat.IsMe and Compat.IsMe(unitName) then return end
    local lk = Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(unitName)
    if not lk or lk == "" then return end
    local conn = (type(isConnectedArg) == "boolean") and isConnectedArg or (UnitIsConnected and UnitIsConnected(unitToken))
    self._groupOfflineSince = self._groupOfflineSince or {}
    if conn == false then
        self._groupOfflineSince[lk] = self._groupOfflineSince[lk] or time()
        return
    end
    local offlineAt = self._groupOfflineSince[lk]
    if conn == true and offlineAt then
        self._groupOfflineSince[lk] = nil
        local peerKey = lk
        local sinceTs = math.max(0, offlineAt - 3)
        local targetChan, targetKey = addonChan, threadKey
        if C_Timer and C_Timer.After then
            C_Timer.After(4.0, function()
                local curChan, curKey = self:GetActiveGroupSyncInfo()
                if curChan ~= targetChan or curKey ~= targetKey then return end
                local lastPeerReq = self._groupCatchupSeenPeerReq and self._groupCatchupSeenPeerReq[peerKey] or 0
                if (time() - lastPeerReq) < 20 then return end
                local autoReq = "auto:" .. peerKey .. ":" .. tostring(offlineAt)
                if #autoReq > 44 then
                    autoReq = "auto:" .. tostring(offlineAt)
                end
                self:LaunchCooperativeCatchupSend(curChan, curKey, autoReq, sinceTs)
            end)
        end
    end
end

function Chat:ShouldAcceptCatchupReq(reqId)
    if type(reqId) ~= "string" or reqId == "" then return false end
    local nowWall = time()
    if self._myPendingCatchupReqIds and self._myPendingCatchupReqIds[reqId] and nowWall <= self._myPendingCatchupReqIds[reqId] then
        return true
    end
    local monoNow = GetTime and GetTime() or 0
    if reqId:sub(1, 5) == "auto:" and monoNow <= (self._awaitingGroupCatchupUntil or 0) then
        local peerPart = reqId:match("^auto:([^:]+):")
        if not peerPart or peerPart == "" then return true end
        local myDisp = GetMyInfo()
        local myLk = myDisp and Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(myDisp)
        return (myLk == peerPart)
    end
    return false
end

function Chat:HasSimilarGroupMessage(thread, msgTs, senderDisp, msgText)
    if not thread or type(thread.messages) ~= "table" then return false end
    local wantSender = Compat and Compat.LowerUtf8 and Compat.LowerUtf8(tostring(senderDisp or "")) or tostring(senderDisp or ""):lower()
    local wantText = Compat and Compat.LowerUtf8 and Compat.LowerUtf8(tostring(msgText or "")) or tostring(msgText or ""):lower()
    for i = #thread.messages, math.max(1, #thread.messages - 75), -1 do
        local m = thread.messages[i]
        if type(m) == "table" and not m.isStatusNotice then
            local mts = tonumber(m.ts) or 0
            if math.abs(mts - msgTs) <= 6 then
                local existingText = tostring(m.text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local normText = Compat and Compat.LowerUtf8 and Compat.LowerUtf8(existingText) or existingText:lower()
                local normSender = Compat and Compat.LowerUtf8 and Compat.LowerUtf8(tostring(m.sender or "")) or tostring(m.sender or ""):lower()
                if normText == wantText and (normSender == wantSender or wantSender == "" or normSender == "") then
                    return true
                end
            end
        end
    end
    return false
end

function Chat:FlushGroupCatchupNotice(reqId, threadKey)
    local counts = self._groupCatchupRecoveredCounts
    local count = counts and counts[reqId] or 0
    if not counts or count <= 0 then return end
    counts[reqId] = nil
    local t = self.threads and self.threads[threadKey]
    if not t then return end
    AppendMessage(t, L["System"], string.format(L["Recovered %d missed group message(s) while you were offline."], count), false, nil, true, true, {
        isStatusNotice = true,
        isCatchupNotice = true,
        skipGeneral = true,
    })
end

function Chat:OnGroupCatchupPacket(payloadRaw, addonChan, senderRaw)
    local activeChan, activeKey = self:GetActiveGroupSyncInfo()
    if not activeChan or addonChan ~= activeChan then return false end
    local cleanPayload = Safe.String(payloadRaw)
    local cleanSender = Safe.String(senderRaw)
    if not cleanPayload or cleanPayload == "" or cleanPayload:find("%c") or cleanPayload:find("|", 1, true) then
        return false
    end
    local parts = self:SplitPayloadTilde(cleanPayload, 7)
    local op = parts[1]
    if op ~= "GCR" and op ~= "GCA" and op ~= "GCM" then
        return false
    end
    if not cleanSender or (Compat and Compat.IsMe and Compat.IsMe(cleanSender)) then
        return true
    end
    local threadKey = parts[2]
    local reqId = parts[3]
    if threadKey ~= activeKey or type(reqId) ~= "string" or reqId == "" then
        return true
    end
    local nowWall = time()
    self:PruneGroupCatchupState(nowWall)

    if op == "GCA" then
        self._groupCatchupAnswered = self._groupCatchupAnswered or {}
        self._groupCatchupAnswered[reqId] = nowWall
        return true
    elseif op == "GCR" then
        local senderLk = Compat and Compat.ParseCharacterFields and Compat.ParseCharacterFields(cleanSender)
        if senderLk and senderLk ~= "" and reqId:sub(1, 5) ~= "auto:" then
            self._groupCatchupSeenPeerReq = self._groupCatchupSeenPeerReq or {}
            self._groupCatchupSeenPeerReq[senderLk] = nowWall
        end
        local sinceTs = tonumber(parts[3])
        local realReqId = parts[4]
        if sinceTs and type(realReqId) == "string" and realReqId ~= "" then
            self:LaunchCooperativeCatchupSend(activeChan, activeKey, realReqId, sinceTs)
        end
        return true
    elseif op == "GCM" then
        self._groupCatchupAnswered = self._groupCatchupAnswered or {}
        self._groupCatchupAnswered[reqId] = nowWall
        if not self:ShouldAcceptCatchupReq(reqId) then
            return true
        end
        local msgTs = tonumber(parts[4]) or nowWall
        if msgTs < (nowWall - 1200) or msgTs > (nowWall + 10) then
            return true
        end
        local cls = Safe.String(parts[5])
        local senderDisp = Safe.String(parts[6]) or "?"
        local bodyText = Safe.String(parts[7])
        if not bodyText or bodyText == "" then return true end
        local meta = STATIC_CHANNEL_ORDER and STATIC_CHANNEL_ORDER[threadKey]
        local t = EnsureThread(threadKey, (meta and meta.kind) or "PARTY", (meta and L[meta.titleKey]) or L["Party"], { slash = (meta and meta.slash) or "/p " })
        if not t then return true end
        if self:HasSimilarGroupMessage(t, msgTs, senderDisp, bodyText) then
            return true
        end
        local incoming = not (Compat and Compat.IsMe and Compat.IsMe(senderDisp))
        AppendMessage(t, senderDisp, bodyText, incoming, (cls and cls ~= "") and cls or nil, false, true, {
            customTs = msgTs,
            isCatchup = true,
            rewritePersist = true,
        })
        self._groupCatchupRecoveredCounts = self._groupCatchupRecoveredCounts or {}
        self._groupCatchupRecoveredCounts[reqId] = (self._groupCatchupRecoveredCounts[reqId] or 0) + 1
        if C_Timer and C_Timer.After and not (self._groupCatchupNoticeQueued and self._groupCatchupNoticeQueued[reqId]) then
            self._groupCatchupNoticeQueued = self._groupCatchupNoticeQueued or {}
            self._groupCatchupNoticeQueued[reqId] = true
            local targetReq = reqId
            local targetKey = threadKey
            C_Timer.After(1.1, function()
                if self._groupCatchupNoticeQueued then
                    self._groupCatchupNoticeQueued[targetReq] = nil
                end
                self:FlushGroupCatchupNotice(targetReq, targetKey)
            end)
        end
        return true
    end
    return true
end

function Chat:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end
    self:InstallErrorOriginTracker()
    self:LoadSavedHistory()
    self:EnsurePersonalNotesThread()
    self:EnsureMentionsThread()
    InstallChatShieldFilters()
    InstallOfficialChatCaptureHooks()
    InstallOfficialEditBoxHistoryHooks()

    ns:On("SETTINGS_UPDATED", function()
        self:InvalidateOfficialChatCache()
    end)
    ns:On("SOCIAL_UPDATED", function()
        self:InvalidateOfficialChatCache()
    end)
    ns:On("WATCHLIST_UPDATED", function()
        self:InvalidateOfficialChatCache()
    end)

    for chKey, meta in pairs(STATIC_CHANNEL_ORDER) do
        EnsureThread(chKey, meta.kind, L[meta.titleKey], { slash = meta.slash })
    end

    for _, ev in ipairs({
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_AFK",
        "CHAT_MSG_DND",
        "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_COMMUNITIES_CHANNEL",
    }) do
        ns.RegisterEvent(self, ev, function(_, eventName, ...)
            OnChatEvent(eventName, ...)
        end)
    end

    for _, wEv in ipairs({
        "CHAT_MSG_LOOT",
        "CHAT_MSG_MONEY",
        "CHAT_MSG_COMBAT_XP_GAIN",
        "CHAT_MSG_COMBAT_FACTION_CHANGE",
        "CHAT_MSG_COMBAT_HONOR_GAIN",
        "CHAT_MSG_SKILL",
        "CHAT_MSG_ACHIEVEMENT",
        "CHAT_MSG_GUILD_ACHIEVEMENT",
        "CHAT_MSG_RAID_BOSS_EMOTE",
        "CHAT_MSG_MONSTER_SAY",
        "CHAT_MSG_MONSTER_YELL",
        "CHAT_MSG_MONSTER_EMOTE",
        "CHAT_MSG_EMOTE",
        "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_CURRENCY",
        "CHAT_MSG_TRADESKILLS",
        "CHAT_MSG_OPENING",
        "CHAT_MSG_BG_SYSTEM_NEUTRAL",
        "CHAT_MSG_BG_SYSTEM_ALLIANCE",
        "CHAT_MSG_BG_SYSTEM_HORDE",
    }) do
        ns.RegisterEvent(self, wEv, function(_, eventName, ...)
            self:OnWorldNoticeEvent(eventName, ...)
        end)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function()
            self:BackfillGeneralFromChatFrame1()
            self:RefreshOfficialChannelThreads()
        end)
    end
    for _, chEv in ipairs({ "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "ZONE_CHANGED_NEW_AREA" }) do
        ns.RegisterEvent(self, chEv, function()
            self:RefreshOfficialChannelThreads()
        end)
    end

    ns.RegisterEvent(self, "CHAT_MSG_ADDON", function(_, _, prefix, text, channel, sender)
        local chan = Safe.String(channel)
        if Safe.String(prefix) == PREFIX then
            if not chan or chan == "WHISPER" then
                HandleIncomingAddonPacket(text, sender, nil)
            elseif chan == "PARTY" or chan == "RAID" or chan == "INSTANCE_CHAT" then
                self:OnGroupCatchupPacket(text, chan, sender)
            end
        end
    end)

    ns.RegisterEvent(self, "UNIT_CONNECTION", function(_, _, unitToken, isConn)
        self:SyncGroupConnectionSnapshot(true, unitToken, isConn)
    end)

    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", function()
        self:SyncGroupRosterSessionState()
        self:SyncGroupConnectionSnapshot(false)
    end)

    ns.RegisterEvent(self, "CLUB_MESSAGE_ADDED", function(_, _, clubIdRaw, streamIdRaw, messageIdRaw)
        if not self:IsChatHistoryCaptureEnabled() then
            return
        end
        local cId = Safe.Number(clubIdRaw)
        local sId = Safe.Number(streamIdRaw)
        if not (cId and sId and messageIdRaw and _G.C_Club and _G.C_Club.GetMessageInfo) then
            return
        end
        local cInfo = _G.C_Club.GetClubInfo and Safe.Call(_G.C_Club.GetClubInfo, cId) or nil
        local clubType = type(cInfo) == "table" and cInfo.clubType or nil
        if _G.Enum and _G.Enum.ClubType and clubType == _G.Enum.ClubType.Guild then
            return -- Guild chat has its own dedicated Guild tab; never mix into General
        end
        local mInfo = Safe.Call(_G.C_Club.GetMessageInfo, cId, sId, messageIdRaw)
        if type(mInfo) ~= "table" or mInfo.destroyed then
            return
        end
        local cleanTxt = Safe.String(mInfo.content)
        if not cleanTxt or cleanTxt == "" then
            return
        end
        local authorObj = type(mInfo.author) == "table" and mInfo.author or nil
        local rawSender = authorObj and Safe.String(authorObj.name) or nil
        local parsed = rawSender and Compat.ParseCharacterName and Compat.ParseCharacterName(rawSender) or nil
        local isMe = (authorObj and authorObj.isSelf == true)
            or (parsed and Compat.IsMe and Compat.IsMe(parsed.displayName))
            or false
        local senderKey = self:_ExtractGeneralSenderKey(rawSender, isMe == true)
        if self:_WasRecentlyRecordedInGeneral(cleanTxt, senderKey) then
            return
        end
        local cls = nil
        if authorObj and Safe.Number(authorObj.classID) and _G.GetClassInfo then
            local okC, _, cFile = pcall(_G.GetClassInfo, Safe.Number(authorObj.classID))
            if okC then cls = Safe.String(cFile) end
        end
        if not cls and parsed then
            cls = LookupClassFromCache(parsed.lookupKey, authorObj and Safe.String(authorObj.guid))
        end
        local senderDisp = isMe and GetMyInfo() or ResolveChatSenderDisplay((parsed and parsed.displayName) or rawSender or "?", authorObj and Safe.String(authorObj.guid), nil)
        local chId, pubTag = nil, nil
        for _, ch in ipairs(self:GetJoinedOfficialChannels()) do
            if ch.clubId == cId and ch.streamId == sId then
                chId = ch.id
                pubTag = ch.title
                break
            end
        end
        if not pubTag or pubTag == "" then
            pubTag = self:ParseCommunityChannelName("Community:" .. tostring(cId) .. ":" .. tostring(sId)) or L["Community"]
        end
        self:RecordGeneralMessage("PUB_CHANNEL", senderDisp, cleanTxt, isMe, cls, pubTag, {
            senderGuid = authorObj and Safe.String(authorObj.guid) or nil,
            senderCharName = senderDisp,
            channelId = chId,
        })
    end)

    ns.RegisterEvent(self, "BN_CHAT_MSG_ADDON", function(_, _, prefix, text, _, bnSenderID)
        if Safe.String(prefix) == PREFIX then
            HandleIncomingAddonPacket(text, nil, Safe.Number(bnSenderID))
        end
    end)

    for _, ev in ipairs({
        "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_ACCOUNT_ONLINE",
        "BN_FRIEND_ACCOUNT_OFFLINE",
        "BN_CONNECTED",
        "BN_DISCONNECTED",
    }) do
        ns.RegisterEvent(self, ev, function()
            self:InvalidateBNetCache()
            local changed = false
            for _, t in pairs(self.threads) do
                if type(t) == "table" and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and t.bnetAccountID then
                    local _, fullChar, accName = FindBNetWoWGameAccount(t.bnetAccountID)
                    if accName and accName ~= "" and t.bnetName ~= accName then
                        t.bnetName = accName
                        if t.kind == "BN_WHISPER" then
                            t.title = accName
                        end
                        changed = true
                    end
                    if fullChar and fullChar ~= "" and t.kind == "BN_WHISPER" and t.targetName ~= fullChar then
                        t.targetName = fullChar
                        t._targetParsed = nil
                        t._targetParsedRaw = nil
                        local fp = Compat.ParseCharacterName(fullChar)
                        if fp then
                            t.classFile = LookupClassFromCache(fp.lookupKey) or t.classFile
                            t.faction = self:GetKnownCharacterFaction(fp.displayName, nil, t.bnetAccountID) or t.faction
                        end
                        t.peerStatus = nil
                        t.peerStatusMsg = nil
                        t.peerStatusAt = nil
                        changed = true
                    end
                end
            end
            local nowClock = GetTime and GetTime() or 0
            if not self._lastBNetConsolidateAt or (nowClock - self._lastBNetConsolidateAt) >= 2.0 then
                self._lastBNetConsolidateAt = nowClock
                if self:ConsolidatePlayerThreads(true) then
                    changed = true
                end
            end
            if changed then
                self:BumpPeerStateGen()
                QueueChatEmit(0.10)
            end
        end)
    end

    local function ClearOfflineForLiveSocial()
        if not (Chat.sessionOfflineChars and next(Chat.sessionOfflineChars) ~= nil) then
            return
        end
        local changed = false
        local byLk = ns.Store and ns.Store.socialByLookup
        for lk in pairs(Chat.sessionOfflineChars) do
            local socRow = byLk and byLk[lk]
            if (socRow and socRow.online == true) or select(1, FindBNetWoWGameAccountByChar({ lookupKey = lk })) ~= nil then
                Chat.sessionOfflineChars[lk] = nil
                changed = true
            end
        end
        if changed then
            Chat:BumpPeerStateGen()
            QueueChatEmit(0.1)
        end
    end

    for _, ev in ipairs({
        "FRIENDLIST_UPDATE",
        "GUILD_ROSTER_UPDATE",
    }) do
        ns.RegisterEvent(self, ev, function()
            if ev == "GUILD_ROSTER_UPDATE" and self.LoadGuildHistoryIfReady then
                self:LoadGuildHistoryIfReady()
            end
            ClearOfflineForLiveSocial()
            local nowClock = GetTime and GetTime() or 0
            if not self._lastThreadReconcileAt or (nowClock - self._lastThreadReconcileAt) >= 8 then
                self._lastThreadReconcileAt = nowClock
                self:ConsolidatePlayerThreads(false)
            end
            self:BumpPeerStateGen()
        end)
    end

    ns.RegisterEvent(self, "WHO_LIST_UPDATE", function()
        local n = 0
        if C_FriendList and C_FriendList.GetNumWhoResults then
            n = Safe.Number(Safe.Call(C_FriendList.GetNumWhoResults)) or 0
        elseif GetNumWhoResults then
            n = Safe.Number(Safe.Call(GetNumWhoResults)) or 0
        end
        if n <= 0 then return end
        local updated = false
        for i = 1, math.min(n, 50) do
            local fullName, lvl, wCls, wArea, wGuild
            if C_FriendList and C_FriendList.GetWhoInfo then
                local info = Safe.Call(C_FriendList.GetWhoInfo, i)
                if type(info) == "table" then
                    fullName = Safe.String(info.fullName)
                    lvl = ValidLevel(Safe.Number(info.level))
                    wCls = Safe.String(info.filename)
                    wArea = Safe.String(info.area)
                    wGuild = Safe.String(info.fullGuildName)
                end
            elseif GetWhoInfo then
                local ok, wName, wG, wLvl, _, _, wZ, wClsFile = pcall(GetWhoInfo, i)
                if ok then
                    fullName = Safe.String(wName)
                    lvl = ValidLevel(Safe.Number(wLvl))
                    wGuild = Safe.String(wG)
                    wArea = Safe.String(wZ)
                    wCls = Safe.String(wClsFile)
                end
            end
            if fullName and (lvl or wArea or wGuild or wCls) then
                if Chat:RecordWhoObservation(fullName, lvl, wCls, wArea, wGuild, true) then
                    updated = true
                end
            end
        end
        if updated then
            QueueChatEmit(0.1)
        end
    end)

    if ns.On then
        ns:On("SOCIAL_UPDATED", function()
            ClearOfflineForLiveSocial()
            local nowClock = GetTime and GetTime() or 0
            if not self._lastSocialConsolidateAt or (nowClock - self._lastSocialConsolidateAt) >= 5 then
                self._lastSocialConsolidateAt = nowClock
                self:ConsolidatePlayerThreads(false)
            end
        end)
    end

    if not ERR_NOT_FOUND_PATTERN and _G.ERR_CHAT_PLAYER_NOT_FOUND_S then
        ERR_NOT_FOUND_PATTERN = BuildNotFoundPattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S)
    end

    local function CancelPendingDeliveryForThread(threadKey)
        if not (threadKey and Chat.deliveryIndex) then return end
        for msgId, dRec in pairs(Chat.deliveryIndex) do
            if type(dRec) == "table" and dRec.threadKey == threadKey then
                Chat.deliveryIndex[msgId] = nil
            end
        end
    end

    local function RecoverManualWhisperSend(reasonTag)
        local rec = Chat.lastManualWhisperSend
        if type(rec) ~= "table" then return false end
        if rec.delivered == true then
            Chat.lastManualWhisperSend = nil
            return false
        end
        local monoNow = GetTime and GetTime() or 0
        if (monoNow - (rec.sentAt or 0)) > 4.0 then
            Chat.lastManualWhisperSend = nil
            return false
        end
        Chat.lastManualWhisperSend = nil
        CancelPendingDeliveryForThread(rec.threadKey)
        local t = rec.threadKey and Chat.threads[rec.threadKey]
        if not t then return false end

        RemoveOptimisticEntry(t, rec.optimisticEntry)
        Chat.pendingDraftText = rec.text
        Chat.pendingDraftThreadKey = rec.threadKey
        Chat.focusInputPending = true
        local notice
        if reasonTag == "ignored" then
            notice = string.format(L["Not delivered — %s appears to be ignoring your whispers. Draft restored."], t.title or rec.targetStr or "?")
        elseif rec.bnetAccountID then
            notice = string.format(L["Not delivered — %s appears offline on this character. Draft restored (Battle.net whisper available)."], t.title or rec.targetStr or "?")
        else
            notice = string.format(L["Not delivered — %s appears offline or unreachable. Draft restored."], t.title or rec.targetStr or "?")
        end
        AppendMessage(t, L["System"], notice, false, nil, true, true, { isStatusNotice = true })
        ns:Emit("CHAT_UPDATED")
        return true
    end

    local function RecoverManualBNetSend(reasonTag)
        local rec = Chat.lastManualBNetSend
        if type(rec) ~= "table" then return false end
        if rec.delivered == true then
            Chat.lastManualBNetSend = nil
            return false
        end
        local monoNow = GetTime and GetTime() or 0
        if (monoNow - (rec.sentAt or 0)) > 4.0 then
            Chat.lastManualBNetSend = nil
            return false
        end
        Chat.lastManualBNetSend = nil
        local t = rec.threadKey and Chat.threads[rec.threadKey]
        if not t then return false end

        RemoveOptimisticEntry(t, rec.optimisticEntry)

        Chat.pendingDraftText = rec.text
        Chat.pendingDraftThreadKey = rec.threadKey
        Chat.focusInputPending = true
        local label = t.title or rec.targetDisplay or "?"
        local notice = (reasonTag == "ignored")
            and string.format(L["Not delivered — %s appears to be ignoring your whispers. Draft restored."], label)
            or string.format(L["Not delivered — %s appears offline or unreachable. Draft restored."], label)
        AppendMessage(t, L["System"], notice, false, nil, true, true, { isStatusNotice = true })
        ns:Emit("CHAT_UPDATED")
        return true
    end

    ns.RegisterEvent(self, "CHAT_MSG_IGNORED", function()
        RecoverManualWhisperSend("ignored")
    end)

    local function SystemMsgMatchesTarget(lowerMsg, cand)
        if not cand or cand == "" then return false end
        local candLow = (Compat.LowerUtf8 and Compat.LowerUtf8(cand)) or cand:lower()
        local msgFold = (Compat.LowerUtf8 and Compat.LowerUtf8(lowerMsg)) or lowerMsg
        if msgFold:find(candLow, 1, true) then
            return true
        end
        if candLow:find("-", 1, true) and msgFold:find((candLow:gsub("%-", " ")), 1, true) then
            return true
        end
        if candLow:find(" ", 1, true) and msgFold:find((candLow:gsub("%s+", "-")), 1, true) then
            return true
        end
        return false
    end

    local function IsSystemNotFoundMessage(msg, lowerMsg)
        if lowerMsg:find("inappropriat", 1, true)
            or lowerMsg:find("inapropriad", 1, true)
            or lowerMsg:find("inapropiad", 1, true)
            or lowerMsg:find("profan", 1, true)
            or lowerMsg:find("censur", 1, true)
        then
            return false
        end
        return (ERR_NOT_FOUND_PATTERN and msg:find(ERR_NOT_FOUND_PATTERN) ~= nil)
            or lowerMsg:find("not currently playing", 1, true) ~= nil
            or lowerMsg:find("no player named", 1, true) ~= nil
            or lowerMsg:find("nenhum jogador", 1, true) ~= nil
            or lowerMsg:find("ningún jugador", 1, true) ~= nil
            or lowerMsg:find("ningun jugador", 1, true) ~= nil
    end

    local function HandlePresenceProbeNotFound(msgRaw, lineID)
        if Safe.IsSecret(msgRaw) then return false end
        local msg = Safe.String(msgRaw)
        if not msg or msg == "" then return false end
        local monoNow = (GetTime and GetTime()) or 0
        local lowerMsg = (Compat.LowerUtf8 and Compat.LowerUtf8(msg)) or msg:lower()
        if not IsSystemNotFoundMessage(msg, lowerMsg) then
            return false
        end
        local hasPending = Chat.pendingPresenceProbes and next(Chat.pendingPresenceProbes) ~= nil
        local hasLedger = Chat.silentNotFoundLedger and next(Chat.silentNotFoundLedger) ~= nil
        if not hasPending and not hasLedger then
            return false
        end
        local manualRec = Chat.lastManualWhisperSend
        local hasManualNow = type(manualRec) == "table"
            and manualRec.delivered ~= true
            and (monoNow - (manualRec.sentAt or 0)) <= 4.0
        if hasManualNow and SystemMsgMatchesTarget(lowerMsg, manualRec.targetStr) then
            return false
        end

        local matchedLk, matchedDisp, matchedIsProbe, matchedRec = nil, nil, false, nil
        if hasPending then
            for lk, pRec in pairs(Chat.pendingPresenceProbes) do
                if type(pRec) == "table" and (monoNow - (pRec.sentAt or 0)) <= 8.0 then
                    if SystemMsgMatchesTarget(lowerMsg, pRec.displayName) then
                        matchedLk = lk
                        matchedDisp = pRec.displayName
                        matchedIsProbe = true
                        matchedRec = pRec
                        break
                    end
                else
                    Chat.pendingPresenceProbes[lk] = nil
                end
            end
        end
        if not matchedRec and hasLedger then
            for k, lRec in pairs(Chat.silentNotFoundLedger) do
                if type(lRec) ~= "table" or monoNow > (lRec.expiresAt or 0) then
                    Chat.silentNotFoundLedger[k] = nil
                elseif SystemMsgMatchesTarget(lowerMsg, lRec.displayName or k) then
                    matchedLk = lRec.lookupKey
                    matchedDisp = lRec.displayName or k
                    matchedIsProbe = lRec.isWatchProbe == true
                    matchedRec = lRec
                    break
                end
            end
        end
        if not matchedRec then
            return false
        end

        if matchedLk and Chat.pendingPresenceProbes then
            Chat.pendingPresenceProbes[matchedLk] = nil
        end
        -- Keep ledger entry alive briefly (~2s) so every ChatFrame tab & filter pass suppresses the exact same system line.
        if Chat.silentNotFoundLedger then
            local shortExp = monoNow + 2.0
            local matchedKey = (Compat.LowerUtf8 and Compat.LowerUtf8(matchedDisp or "")) or tostring(matchedDisp or ""):lower()
            for _, variant in ipairs({ matchedKey, (matchedKey:gsub("%-", " ")), (matchedKey:gsub("%s+", "-")), matchedLk or "" }) do
                if variant ~= "" then
                    local existing = Chat.silentNotFoundLedger[variant]
                    if type(existing) == "table" then
                        existing.expiresAt = math.min(existing.expiresAt or shortExp, shortExp)
                        existing.notifiedOffline = true
                    else
                        Chat.silentNotFoundLedger[variant] = {
                            expiresAt = shortExp,
                            lookupKey = matchedLk,
                            displayName = matchedDisp,
                            isWatchProbe = matchedIsProbe,
                            notifiedOffline = true,
                        }
                    end
                end
            end
        end

        if matchedLk and matchedIsProbe and not matchedRec.notifiedOffline then
            matchedRec.notifiedOffline = true
            Chat.sessionOfflineChars = Chat.sessionOfflineChars or {}
            Chat.sessionOfflineChars[matchedLk] = monoNow + 45
            Chat.seenOnlineChars[matchedLk] = nil
            Chat:BumpPeerStateGen()
            if Store and Store.SyncWatchlistObservation then
                local socRow = Store.socialByLookup and Store.socialByLookup[matchedLk]
                local isRosterOn = socRow and (socRow.friendOnline == true or socRow.guildOnline == true or (socRow.bnetOnline == true and socRow.bnetState == "wow_forever"))
                if not isRosterOn then
                    Store:SyncWatchlistObservation(matchedDisp or matchedLk, {
                        online = false,
                        source = "probe",
                    })
                end
            end
            if ns.Social and ns.Social.QueueScan then
                ns.Social:QueueScan(0.3)
            end
        end
        return true
    end

    if not self._presenceFilterRegistered then
        self._presenceFilterRegistered = true
        local function PresenceSystemFilter(_, _, msgRaw, ...)
            local lineID = select(10, ...)
            if HandlePresenceProbeNotFound(msgRaw, lineID) then
                return true
            end
            return false
        end
        if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
            pcall(ChatFrameUtil.AddMessageEventFilter, "CHAT_MSG_SYSTEM", PresenceSystemFilter)
        elseif ChatFrame_AddMessageEventFilter then
            pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", PresenceSystemFilter)
        end
    end

    -- Disqualify Forever WHISPER candidate strings that the server explicitly reports as not playing and recover lost manual whisper drafts.
    -- Genuine Blizzard system & friend online/offline notices flow through ChatFrame1:AddMessage strictly AFTER all ChatFrame event filters suppress background probes.
    ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", function(_, _, msgRaw, _, _, _, _, _, _, _, _, _, lineID)
        if HandlePresenceProbeNotFound(msgRaw, lineID) then
            return
        end
        if ns.Clan and ns.Clan.IsSilentWhisperNotFound and ns.Clan:IsSilentWhisperNotFound(msgRaw) then
            return
        end
        if Safe.IsSecret(msgRaw) then return end
        if Chat.HandleGuildSystemMessage and Chat:HandleGuildSystemMessage(msgRaw) then
            return
        end
        local monoNow = GetTime and GetTime() or 0
        local hasManual = type(Chat.lastManualWhisperSend) == "table"
            and Chat.lastManualWhisperSend.delivered ~= true
            and (monoNow - (Chat.lastManualWhisperSend.sentAt or 0)) <= 4.0
        local hasManualBNet = type(Chat.lastManualBNetSend) == "table"
            and Chat.lastManualBNetSend.delivered ~= true
            and (monoNow - (Chat.lastManualBNetSend.sentAt or 0)) <= 4.0
        if not hasManual and not hasManualBNet and (monoNow - (Chat._lastCandidateTrackAt or 0)) > 10 then return end

        local msg = Safe.String(msgRaw)
        if not msg or msg == "" then return end
        local lowerMsg = msg:lower()
        -- Never misclassify content/profanity moderation notices as offline/player-not-found errors.
        if lowerMsg:find("inappropriat", 1, true)
            or lowerMsg:find("inapropriad", 1, true)
            or lowerMsg:find("inapropiad", 1, true)
            or lowerMsg:find("profan", 1, true)
            or lowerMsg:find("censur", 1, true)
        then
            return
        end
        local looksIgnored = lowerMsg:find("is ignoring you", 1, true)
            or lowerMsg:find("está ignorando", 1, true)
            or lowerMsg:find("te está ignorando", 1, true)
        local looksNotFound = (ERR_NOT_FOUND_PATTERN and msg:find(ERR_NOT_FOUND_PATTERN))
            or lowerMsg:find("not currently playing", 1, true)
            or lowerMsg:find("no player named", 1, true)
            or lowerMsg:find("nenhum jogador", 1, true)
            or lowerMsg:find("ningún jugador", 1, true)
            or lowerMsg:find("ningun jugador", 1, true)
        if not looksNotFound and not looksIgnored then return end

        if hasManual then
            local rec = Chat.lastManualWhisperSend
            local matchedTarget = SystemMsgMatchesTarget(lowerMsg, rec.targetStr)
            if matchedTarget then
                if looksNotFound and rec.lookupKey then
                    Chat.sessionOfflineChars = Chat.sessionOfflineChars or {}
                    Chat.sessionOfflineChars[rec.lookupKey] = monoNow + 60
                    Chat:BumpPeerStateGen()
                    if Store and Store.SyncWatchlistObservation and ns.Watchlist and ns.Watchlist.GetEntry and ns.Watchlist:GetEntry(rec.lookupKey) then
                        local socRow = Store.socialByLookup and Store.socialByLookup[rec.lookupKey]
                        if not (socRow and socRow.online == true) then
                            Store:SyncWatchlistObservation(rec.targetStr or rec.lookupKey, {
                                online = false,
                                source = "whisper_miss",
                            })
                        end
                    end
                end
                RecoverManualWhisperSend(looksIgnored and "ignored" or "offline")
            end
        end

        if hasManualBNet then
            local brec = Chat.lastManualBNetSend
            local bThread = brec.threadKey and Chat.threads[brec.threadKey]
            local bName = bThread and bThread.bnetName
            if SystemMsgMatchesTarget(lowerMsg, brec.targetDisplay)
                or SystemMsgMatchesTarget(lowerMsg, bName)
            then
                RecoverManualBNetSend(looksIgnored and "ignored" or "offline")
            end
        end

        if not looksNotFound then return end

        local function rejectCand(cand, lookupKey)
            if not SystemMsgMatchesTarget(lowerMsg, cand) then
                return false
            end
            Chat.rejectedWhisperTargets = Chat.rejectedWhisperTargets or {}
            local rjCount = 0
            for rk, expAt in pairs(Chat.rejectedWhisperTargets) do
                if type(expAt) ~= "number" or monoNow >= expAt then
                    Chat.rejectedWhisperTargets[rk] = nil
                else
                    rjCount = rjCount + 1
                end
            end
            if rjCount >= 120 then
                wipe(Chat.rejectedWhisperTargets)
            end
            Chat.rejectedWhisperTargets[cand] = monoNow + 60
            if lookupKey and Chat.resolvedWhisperTargets and Chat.resolvedWhisperTargets[lookupKey] == cand then
                Chat.resolvedWhisperTargets[lookupKey] = nil
            end
            return true
        end

        if Chat.lastProbeCandidate then
            for tKey, rec in pairs(Chat.lastProbeCandidate) do
                if type(rec) == "table" and rec.candidate and (monoNow - (rec.at or 0)) <= 4.0 then
                    if rejectCand(rec.candidate) then
                        Chat.lastProbeCandidate[tKey] = nil
                    end
                elseif type(rec) == "table" and (monoNow - (rec.at or 0)) > 10 then
                    Chat.lastProbeCandidate[tKey] = nil
                end
            end
        end
        if Chat.lastWhisperCandidates then
            for tKey, rec in pairs(Chat.lastWhisperCandidates) do
                if type(rec) == "table" and type(rec.candidates) == "table" and (monoNow - (rec.at or 0)) <= 4.0 then
                    for _, cand in ipairs(rec.candidates) do
                        rejectCand(cand, rec.lookupKey)
                    end
                elseif type(rec) == "table" and (monoNow - (rec.at or 0)) > 10 then
                    Chat.lastWhisperCandidates[tKey] = nil
                end
            end
        end
    end)

    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        Chat:CheckExpiredThreadMutes(true)
        Chat:RefreshOfficialChannelThreads()
        Chat:SyncPresenceProbeTicker()
    end)

    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        Chat:AbortPendingPresenceProbes()
    end)

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        Chat._presenceReadyMono = ((GetTime and GetTime()) or 0) + 3.5
        Chat:AbortPendingPresenceProbes()
        Chat:CheckExpiredThreadMutes(true)
        Chat:OnGroupCatchupEnteringWorld()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function()
                Chat:InstallErrorOriginChatFilter()
            end)
        else
            Chat:InstallErrorOriginChatFilter()
        end
        if not Chat._editHistRestored then
            Chat._editHistRestored = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0.8, RestoreSavedEditHistory)
            else
                RestoreSavedEditHistory()
            end
        end
        Chat:SyncPresenceProbeTicker()
        if not Chat._presenceWatchListeners then
            Chat._presenceWatchListeners = true
            ns:On("WATCHLIST_UPDATED", function() Chat:SyncPresenceProbeTicker() end)
            ns:On("SETTINGS_UPDATED", function() Chat:SyncPresenceProbeTicker() end)
        end
        if Chat._loginBNetScanScheduled then return end
        Chat._loginBNetScanScheduled = true
        if C_Timer and C_Timer.After then
            C_Timer.After(10.0, function()
                Chat:QueueLoginBNetDiscovery()
            end)
        end
    end)

    ns:Emit("CHAT_UPDATED")
end
