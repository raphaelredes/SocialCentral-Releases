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
local MAX_THREAD_LINES = 60
local MAX_SAVED_WHISPERS = 60
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
local MAX_SAVED_THREADS = 250
local PEER_TTL_SECONDS = nil    -- preserve verified [SC] peer records across breaks
local MAX_SAVED_PEERS = 800
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
            return a.ts > b.ts
        end)
        for i = maxEntries + 1, #entries do
            if not entries[i].protected then
                tbl[entries[i].key] = nil
            end
        end
    end
end

local function IsProtectedThreadRecord(threadKey)
    if threadKey == "notes:self" then return true end
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
        local curPool = Compat.RealmPool(Compat.Realm())
        for _, alt in pairs(altsTbl) do
            if type(alt) == "table" then
                local altPool = alt.realmPool and Compat.RealmPool(alt.realmPool) or curPool
                if altPool == curPool then
                    NoteKnownFullName(alt.fullName or alt.name, alt.faction)
                end
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
    local curPool = Compat.RealmPool(Compat.Realm())
    local count, foundDisp = 0, nil
    for _, alt in pairs(altsTbl) do
        if type(alt) == "table" and type(alt.fullName) == "string" and alt.fullName ~= "" then
            local altPool = alt.realmPool and Compat.RealmPool(alt.realmPool) or curPool
            if altPool == curPool then
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
    return kind == "GUILD" or kind == "OFFICER" or kind == "PARTY" or kind == "RAID" or kind == "INSTANCE_CHAT"
end

function Chat:IsThreadMuted(threadKey)
    local muted = ns.db and ns.db.settings and ns.db.settings.chatMutedThreads
    return type(muted) == "table" and threadKey and muted[threadKey] == true or false
end

function Chat:SetThreadMuted(threadKey, state)
    if not threadKey or not (ns.db and ns.db.settings) then
        return false
    end
    if type(ns.db.settings.chatMutedThreads) ~= "table" then
        ns.db.settings.chatMutedThreads = {}
    end
    if state then
        ns.db.settings.chatMutedThreads[threadKey] = true
        local t = self.threads[threadKey]
        if t then
            t.unread = 0
            t.hasMention = nil
        end
    else
        ns.db.settings.chatMutedThreads[threadKey] = nil
    end
    self:InvalidateUnreadCache()
    self:BumpPeerStateGen()
    ns:Emit("CHAT_UPDATED")
    return true
end

function Chat:ToggleThreadMuted(threadKey)
    local nextState = not self:IsThreadMuted(threadKey)
    self:SetThreadMuted(threadKey, nextState)
    return nextState
end

local UNMUTE_CHANNEL_MAP = {
    msgPreviewGroup = { "ch:party", "ch:instance" },
    quickReplyNotifyParty = { "ch:party", "ch:instance" },
    quickReplyNotifyRaid = { "ch:raid" },
    msgPreviewGuild = { "ch:guild", "ch:officer" },
    quickReplyNotifyGuild = { "ch:guild", "ch:officer" },
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
    return cleaned
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
    local order = SyncPinnedOrder(self)
    local ranks = {}
    for i = 1, #order do
        ranks[order[i]] = i
    end
    return ranks
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

local function BuildDefaultQuickReplies()
    return {
        L["On my way!"],
        L["1 min, brb!"],
        L["Up for a dungeon?"],
        L["Invite please!"],
        L["Thanks for the group!"],
    }
end

function Chat:GetQuickReplies()
    local cfg = ns.db and ns.db.settings
    if not cfg then
        return BuildDefaultQuickReplies()
    end
    if type(cfg.chatQuickReplies) ~= "table" or #cfg.chatQuickReplies == 0 then
        cfg.chatQuickReplies = BuildDefaultQuickReplies()
    end
    return cfg.chatQuickReplies
end

function Chat:AddQuickReply(rawText)
    local clean = Compat.CleanInput(rawText)
    if not clean or not (ns.db and ns.db.settings) then
        return false
    end
    local list = self:GetQuickReplies()
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

function Chat:RemoveQuickReply(index)
    local cfg = ns.db and ns.db.settings
    if not cfg or type(cfg.chatQuickReplies) ~= "table" then
        return false
    end
    if index and index >= 1 and index <= #cfg.chatQuickReplies then
        table.remove(cfg.chatQuickReplies, index)
        ns:Emit("CHAT_UPDATED")
        return true
    end
    return false
end

function Chat:ResetQuickReplies()
    if ns.db and ns.db.settings then
        ns.db.settings.chatQuickReplies = BuildDefaultQuickReplies()
        ns:Emit("CHAT_UPDATED")
        return true
    end
    return false
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
    local zone = (Compat.CurrentZoneName and Compat.CurrentZoneName()) or ""
    local lvl = tostring((UnitLevel and Safe.Number(Safe.Call(UnitLevel, "player"))) or "")
    local locClass = (UnitClass and Safe.String(Safe.Call(UnitClass, "player"))) or ""
    local res = rawText
    res = res:gsub("{[Zz]ona}", zone):gsub("{[Zz]one}", zone)
    res = res:gsub("{[Nn]ivel}", lvl):gsub("{[Ll]evel}", lvl):gsub("{nível}", lvl):gsub("{Nível}", lvl)
    res = res:gsub("{[Cc]lasse}", locClass):gsub("{[Cc]lase}", locClass):gsub("{[Cc]lass}", locClass)
    return res
end

function Chat:GetCategorizedQuickReplies()
    return {
        {
            title = L["Group"],
            items = {
                L["On my way! ({zone})"],
                L["Lv {level} {class} ready for dungeon!"],
                L["Invite please!"],
                L["Thanks for the group!"],
            },
        },
        {
            title = L["Trade & Craft"],
            items = {
                L["How much for that item?"],
                L["I have the materials, can you craft it?"],
                L["I'm in {zone}, meet me at the mailbox!"],
            },
        },
        {
            title = L["Guild"],
            items = {
                L["Count me in!"],
                L["Need a hand with anything?"],
                L["On my way from {zone}!"],
            },
        },
        {
            title = L["Busy / AFK"],
            items = {
                L["1 min, brb!"],
                L["In a dungeon right now, I'll reply soon!"],
                L["Busy at the moment, whisper me in a few minutes."],
            },
        },
    }
end

function Chat:MarkAllRead()
    local hist = GetHistoryScopeTable()
    for key, t in pairs(self.threads) do
        t.unread = 0
        t.hasMention = nil
        t.firstUnreadTs = nil
        t.firstUnreadEntry = nil
        t.lastReadBannerTs = nil
        t.lastReadBannerEntry = nil
        if hist and type(key) == "string" and key:sub(1, 2) == "w:" and type(hist[key]) == "table" then
            hist[key].unread = 0
        end
    end
    self:InvalidateUnreadCache()
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

local function GetChatHistoryLimit()
    local raw = ns.db and ns.db.settings and ns.db.settings.chatHistoryLimit
    if raw == nil then return 30 end
    local num = tonumber(raw) or 30
    if num > MAX_SAVED_WHISPERS then return MAX_SAVED_WHISPERS end
    return math.max(0, num)
end

local function PersistWhisperLine(threadKey, entry, unreadCount, threadObj)
    if type(threadKey) ~= "string" then
        return
    end
    local isNotes = (threadKey == "notes:self")
    if not isNotes and threadKey:sub(1, 2) ~= "w:" then
        return
    end
    local limit = isNotes and 999999 or GetChatHistoryLimit()
    if limit <= 0 then
        return
    end
    local hist = GetHistoryScopeTable()
    if not hist then return end

    local saved = hist[threadKey]
    local isNewThread = (type(saved) ~= "table")
    if isNewThread then
        saved = { title = entry.threadTitle, targetName = entry.targetName, lines = {} }
        hist[threadKey] = saved
    end
    saved.title = (threadObj and threadObj.title) or entry.threadTitle or saved.title
    saved.targetName = (threadObj and threadObj.targetName) or entry.targetName or saved.targetName
    saved.faction = (threadObj and threadObj.faction) or saved.faction
    if threadObj and tonumber(threadObj.level) and tonumber(threadObj.level) > 0 then
        saved.level = math.floor(tonumber(threadObj.level))
    end
    saved.updatedAt = entry.ts or time()
    saved.unread = math.max(0, math.floor(tonumber(unreadCount) or 0))
    if type(saved.lines) ~= "table" then saved.lines = {} end

    -- Store strictly character names, level, and plain text (never BattleTag, Real ID, or bnetAccountID).
    table.insert(saved.lines, {
        sender = entry.sender,
        targetChar = entry.targetChar,
        text = entry.text,
        ts = entry.ts,
        incoming = entry.incoming and true or false,
        classFile = entry.classFile,
        targetClass = entry.targetClass,
        senderFaction = entry.senderFaction,
        targetFaction = entry.targetFaction,
        senderLevel = (tonumber(entry.senderLevel) and tonumber(entry.senderLevel) > 0) and math.floor(tonumber(entry.senderLevel)) or nil,
        viaAddon = entry.viaAddon and true or nil,
        noteId = entry.noteId,
    })
    if not isNotes then
        while #saved.lines > limit do
            table.remove(saved.lines, 1)
        end
        if isNewThread and CountHashKeys(hist) > MAX_SAVED_THREADS then
            PruneSavedScopeTable(hist, HISTORY_TTL_SECONDS, MAX_SAVED_THREADS, GetHistoryStamp, IsProtectedThreadRecord)
        end
    end
end

local function RewriteThreadHistory(thread)
    if not thread or type(thread.key) ~= "string" then return end
    local isNotes = (thread.key == "notes:self")
    if not isNotes and thread.key:sub(1, 2) ~= "w:" then return end
    local hist = GetHistoryScopeTable()
    if not hist then return end
    local limit = isNotes and 999999 or GetChatHistoryLimit()
    if limit <= 0 then return end

    local outLines = {}
    local msgs = thread.messages or {}
    local startIdx = isNotes and 1 or math.max(1, #msgs - limit + 1)
    for i = startIdx, #msgs do
        local m = msgs[i]
        if type(m) == "table" and not m.isStatusNotice and type(m.text) == "string" and m.text ~= "" then
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
            }
        end
    end
    hist[thread.key] = {
        title = thread.title,
        targetName = thread.targetName,
        faction = thread.faction,
        level = (tonumber(thread.level) and tonumber(thread.level) > 0) and math.floor(tonumber(thread.level)) or nil,
        updatedAt = thread.lastAt or time(),
        unread = math.max(0, math.floor(tonumber(thread.unread) or 0)),
        lines = outLines,
    }
end

local function QueueChatEmit(delay)
    if Chat._chatEmitQueued then return end
    Chat._chatEmitQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.30, function()
            Chat._chatEmitQueued = false
            ns:Emit("CHAT_UPDATED")
        end)
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
    local line
    if thread.kind == "ROOM" or thread.kind == "ALLIANCE" then
        local sourceTag = (thread.kind == "ALLIANCE") and L["Alliance"]
            or ((thread.title and thread.title ~= "") and thread.title or L["Private Room"])
        line = string.format("|cff3fb950[SC %s]|r |Haddon:SCentral:thread:%s|h%s[%s]|r|h: %s",
            tostring(sourceTag),
            tostring(thread.key),
            hex,
            tostring(senderName or "?"),
            cleanPreview)
    elseif incoming then
        local disp = tostring(senderName or thread.title or "?")
        line = string.format("|cff3fb950[SC]|r |Haddon:SCentral:thread:%s|h%s[%s]|r|h: %s",
            tostring(thread.key),
            hex,
            disp,
            cleanPreview)
    else
        local targetDisp = tostring((extraFields and extraFields.targetChar) or thread.targetName or thread.title or "?")
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
        local curPool = Compat.RealmPool(Compat.Realm())
        local qLk, qFirst, _, qSurname = Compat.ParseCharacterFields(lookupKey)
        local fLow = qFirst and qFirst:lower() or nil
        local fCount, fClass = 0, nil
        for _, alt in pairs(altsTbl) do
            if type(alt) == "table" and alt.classFile then
                local altPool = alt.realmPool and Compat.RealmPool(alt.realmPool) or curPool
                if altPool == curPool then
                    local aLk, aFirst = Compat.ParseCharacterFields(alt.fullName or alt.name or "")
                    if (qLk and aLk == qLk) or (alt.name and lookupKey == alt.name:lower()) then
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

local function LookupLevelFromCache(lookupKey, displayName, guid, bnetAccountID)
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

    if not resolvedLvl and (guid or lk or firstLow) then
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

    if not resolvedLvl and lk and ns.db and type(ns.db.alts) == "table" then
        local curPool = Compat.RealmPool(Compat.Realm())
        for _, alt in pairs(ns.db.alts) do
            if type(alt) == "table" and ValidLevel(alt.level) then
                local altPool = alt.realmPool and Compat.RealmPool(alt.realmPool) or curPool
                if altPool == curPool then
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

function Chat:ResolvePlayerLevel(lookupKey, displayName, guid, bnetAccountID)
    return LookupLevelFromCache(lookupKey, displayName, guid, bnetAccountID)
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

local function AppendMessage(thread, senderName, text, incoming, classFile, skipPersist, silent, extraFields)
    if not thread or not text or text == "" then return end
    local ts = time()
    local isMention = false
    if incoming and (thread.kind == "ROOM" or thread.kind == "ALLIANCE" or IsPublicChannelKind(thread.kind)) then
        local myDisp = GetMyInfo()
        local myParsed = myDisp and Compat.ParseCharacterName and Compat.ParseCharacterName(myDisp)
        local fnLow = myParsed and myParsed.firstName and myParsed.firstName:lower()
        if fnLow and #fnLow >= 2 then
            local plainLow = tostring(text):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
            local padded = " " .. plainLow:gsub("[%p]", " ") .. " "
            if padded:find(" " .. fnLow .. " ", 1, true) or plainLow:find("@" .. fnLow, 1, true) then
                isMention = true
            end
        end
    end

    local isStatus = extraFields and extraFields.isStatusNotice and true or false
    local isDirectThread = (thread.kind == "WHISPER" or thread.kind == "BN_WHISPER")
    local senderDisp = senderName or "?"
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
    }
    if isDirectThread and incoming and resolvedSenderLvl then
        thread.level = resolvedSenderLvl
    end
    table.insert(thread.messages, entry)
    if thread.kind ~= "NOTES" then
        while #thread.messages > MAX_THREAD_LINES do
            table.remove(thread.messages, 1)
        end
    end
    thread.lastAt = ts

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
    local sCfg = ns.db and ns.db.settings
    local allowChannelUnread = sCfg and sCfg.chatChannelUnread == true
    local allowQuickChan = sCfg and sCfg.quickReplyEnabled ~= false and Chat.IsQuickReplyKindEnabled and Chat:IsQuickReplyKindEnabled(thread.kind)

    if extraFields and extraFields.viaAddon and extraFields.echoToOfficial ~= false and not isMuted then
        Chat:EchoAddonMessageToOfficialFrames(thread, senderDisp, text, incoming, resolvedClass, extraFields)
    end

    if incoming and not isViewing and not isMuted then
        if (not isPublic) or allowChannelUnread or allowQuickChan or isMention then
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
                local cleanPreview = Compat.CleanPayloadField(text, 100)
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
        if not silent and not isStatus and thread.kind ~= "NOTES" then
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
            if type(thread.key) == "string" and thread.key:sub(1, 2) == "w:" then
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

    if not skipPersist and (thread.kind == "WHISPER" or thread.kind == "NOTES") then
        PersistWhisperLine(thread.key, entry, thread.unread, thread)
    end

    local qrVisible = ns.QuickReply and ns.QuickReply.frame and ns.QuickReply.frame:IsShown()
    if isPublic and not mainVisible and not qrVisible then
        QueueChatEmit(0.30)
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
    if hist then
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
                local startIdx = math.max(1, #saved.lines - limit + 1)
                for i = startIdx, #saved.lines do
                    local line = saved.lines[i]
                    if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                        local fallbackWho = (line.incoming and canonParsed.displayName) or nil
                        table.insert(t.messages, {
                            sender = ResolveChatSenderDisplay(line.sender or canonParsed.displayName, nil, fallbackWho),
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
                        })
                        t.lastAt = math.max(t.lastAt or 0, tonumber(line.ts) or 0)
                    end
                end
                EnrichLoadedThreadMessages(t, canonParsed.displayName)
            end
        end
    end

    local rooms = GetRoomsScopeTable()
    if rooms then
        for roomId, room in pairs(rooms) do
            if type(room) == "table" and room.joined then
                EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, {
                    roomId = roomId,
                })
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
        return s.quickReplyNotifyRaid == true
    elseif kind == "GUILD" or kind == "OFFICER" then
        return s.quickReplyNotifyGuild == true
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

function Chat:GetQuickReplyThreads()
    local list = {}
    local s = ns.db and ns.db.settings
    local qrOn = (not s) or s.quickReplyEnabled ~= false
    if qrOn then
        for key, t in pairs(self.threads) do
            if type(t) == "table" and key ~= "notes:self" and key ~= "mentions:radar" then
                local u = t.unread or 0
                local draft = self.quickReplyDrafts and self.quickReplyDrafts[key] or nil
                local hasUnread = (u > 0) and (not self:IsThreadMuted(key)) and self:IsQuickReplyKindEnabled(t.kind)
                if hasUnread or draft then
                    local sortAt = math.max(t.lastAt or 0, draft and draft.updatedAt or 0)
                    list[#list + 1] = {
                        key = key,
                        thread = t,
                        title = t.title or t.targetName or key,
                        kind = t.kind,
                        unread = hasUnread and u or 0,
                        hasDraft = draft ~= nil,
                        draftText = draft and draft.text or nil,
                        lastAt = sortAt,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local aUn = (a.unread or 0) > 0
        local bUn = (b.unread or 0) > 0
        if aUn ~= bUn then
            return aUn
        end
        if (a.lastAt or 0) ~= (b.lastAt or 0) then
            return (a.lastAt or 0) > (b.lastAt or 0)
        end
        return tostring(a.key or "") < tostring(b.key or "")
    end)
    return list
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
    local s = ns.db and ns.db.settings
    local mirrorOn = s and s.chatMirrorChannels == true
    local allowChanUnread = s and s.chatChannelUnread == true
    local qrOn = s and s.quickReplyEnabled ~= false
    local qrSig = qrOn and ((s.quickReplyNotifyParty ~= false and "P" or "")
        .. (s.quickReplyNotifyRaid == true and "R" or "")
        .. (s.quickReplyNotifyGuild == true and "G" or "")) or "0"
    local chanFlag = ((mirrorOn and allowChanUnread) and "1" or "0") .. ":" .. qrSig
    if not self._unreadSummaryDirty and self._unreadSummaryCache and self._unreadSummaryChanFlag == chanFlag then
        return self._unreadSummaryCache
    end

    local direct, roomsUnread, invites, channels = 0, 0, 0, 0
    local byCategory = {
        whisper = 0,
        bnet = 0,
        group = 0,
        guild = 0,
        room = 0,
    }
    local senders = {}

    for key, t in pairs(self.threads) do
        local u = t.unread or 0
        if u > 0 and not self:IsThreadMuted(key) then
            if IsPublicChannelKind(t.kind) then
                if (mirrorOn and allowChanUnread) or (qrOn and self:IsQuickReplyKindEnabled(t.kind)) then
                    channels = channels + u
                    if t.kind == "GUILD" or t.kind == "OFFICER" then
                        byCategory.guild = byCategory.guild + u
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
        return (a.lastAt or 0) > (b.lastAt or 0)
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
        if u > 0 and not self:IsThreadMuted(key) then
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
        if type(threadKey) == "string" and threadKey:sub(1, 2) == "w:" then
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
    if type(threadKey) == "string" and threadKey:sub(1, 2) == "w:" then
        local hist = GetHistoryScopeTable()
        if hist and type(hist[threadKey]) == "table" then
            hist[threadKey].unread = t.unread
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
        return (a.createdAt or 0) > (b.createdAt or 0)
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

    local mirrorChannels = ns.db and ns.db.settings and ns.db.settings.chatMirrorChannels == true

    for key, t in pairs(self.threads) do
        local isRoom = key:sub(1, 5) == "room:"
        local include = true
        if isRoom then
            local room = rooms[t.roomId]
            include = room and room.joined == true
        elseif key == "mentions:radar" then
            include = (kindFilter == "mentions") or (#(t.messages or {}) > 0)
        elseif key:sub(1, 3) == "ch:" then
            local isGuildChan = (t.kind == "GUILD" or t.kind == "OFFICER")
            local isGroupChan = (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT")
            local isAllianceChan = (t.kind == "ALLIANCE")
            local inGuild = false
            if Compat.ShouldShowGuildFeatures then
                inGuild = Compat.ShouldShowGuildFeatures() == true
            elseif Compat.IsInGuild then
                inGuild = Compat.IsInGuild() == true
            end
            local inGroup = Compat.IsInGroup and Compat.IsInGroup()
            local isAllianceAuth = inGuild and ns.Clan and ns.Clan.IsMemberAllianceAuthorized and ns.Clan:IsMemberAllianceAuthorized()
            local forceShow = (isGuildChan and inGuild and kindFilter == "guild")
                or (isGroupChan and inGroup and kindFilter == "group")
                or (isAllianceChan and isAllianceAuth and (kindFilter == "alliance" or kindFilter == "channels" or not kindFilter or kindFilter == "all"))
            include = (isAllianceChan and isAllianceAuth)
                or (((not isGuildChan and not isAllianceChan) or (isGuildChan and inGuild)) and mirrorChannels and #(t.messages or {}) > 0)
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
                include = IsPublicChannelKind(t.kind) or (t.kind == "ALLIANCE")
            elseif kindFilter == "mentions" then
                include = (t.kind == "MENTIONS") or (t.hasMention == true)
            end
        end

        if include then
            local lastMsg = t.messages and t.messages[#t.messages]
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
            item.count = t.messages and #t.messages or 0
            table.insert(out, item)
        end
    end

    local pinRanks = self:GetPinnedOrderMap()
    table.sort(out, function(a, b)
        if kindFilter == "unread" then
            if (a.unread or 0) ~= (b.unread or 0) then
                return (a.unread or 0) > (b.unread or 0)
            end
            if (a.kind == "NOTES") ~= (b.kind == "NOTES") then
                return a.kind == "NOTES"
            end
            if (a.pinned == true) ~= (b.pinned == true) then
                return a.pinned == true
            end
        else
            if (a.kind == "NOTES") ~= (b.kind == "NOTES") then
                return a.kind == "NOTES"
            end
            if (a.pinned == true) ~= (b.pinned == true) then
                return a.pinned == true
            end
            if a.pinned == true and b.pinned == true then
                local ra = pinRanks[a.key] or 9999
                local rb = pinRanks[b.key] or 9999
                if ra ~= rb then
                    return ra < rb
                end
            end
            if (a.unread or 0) ~= (b.unread or 0) then
                return (a.unread or 0) > (b.unread or 0)
            end
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
    end)
    return out
end

function Chat:GetThreadMessages(threadKey)
    local t = threadKey and self.threads[threadKey]
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
    while #out > MAX_THREAD_LINES do
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
        muted[canonThread.key] = true
        muted[oldKey] = nil
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
        if hist then hist[threadKey] = nil end
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

local function TrackSentWhisperCandidates(trackKey, lookupKey, sentList, monoNow)
    if not trackKey or not sentList or #sentList == 0 then return end
    Chat._lastCandidateTrackAt = monoNow
    Chat.lastWhisperCandidates = Chat.lastWhisperCandidates or {}
    Chat.lastWhisperCandidates[trackKey] = {
        candidates = sentList,
        lookupKey = lookupKey,
        at = monoNow,
    }
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
    AppendMessage(t, senderShort, cleanText, false, Safe.String(myClass), true, true, {
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
    AppendMessage(t, displayName, msgText, not isMe, classFile, true, false, {
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

function Chat:MarkPeerVerified(targetChar, bnetGameAccId, versionStr, sourceTag)
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
            if self.sessionOfflineChars then self.sessionOfflineChars[lk] = nil end
            if self.sessionUnverifiedPeers then self.sessionUnverifiedPeers[lk] = nil end
            if self.pendingProbes then self.pendingProbes["w:" .. lk] = nil end
            if self.pendingOfficialOpen and self.pendingOfficialOpen["w:" .. lk] then
                self.pendingOfficialOpen["w:" .. lk] = nil
                verifiedWithPendingOpen = true
            end
            if self.probeFailures then self.probeFailures["w:" .. lk] = nil end
            if self.probeAttemptIndex then self.probeAttemptIndex["w:" .. lk] = nil end

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
                TrackSentWhisperCandidates("send:" .. threadKey, sendParsed and sendParsed.lookupKey, { targetStr }, monoNow)
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

    if STATIC_CHANNEL_ORDER[threadKey] and IsInAllowedOfficialChannel(t.kind) and sendChat then
        local ok, res = pcall(sendChat, cleanText, t.kind)
        if ok and res ~= false then
            self._lastOfficialSendAt = monoNow
            local meDisplay = GetMyInfo()
            local _, myClass = Safe.Call(UnitClass, "player")
            local entry = AppendMessage(t, meDisplay, cleanText, false, Safe.String(myClass), true, true)
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
        return true
    end

    if t.kind == "BN_WHISPER" then
        Compat.BNetWhisper(t.bnetName, t.targetName or t.title, clean)
        return true
    end

    local prefix
    if t.kind == "WHISPER" and t.targetName then
        local redir = ResolveBNetRedirectForWhisper(t)
        if redir and redir.bnetName then
            local prefill = (clean ~= "") and (redir.isAltSwitch and FormatBNetRedirectMessage(redir.targetDisplay, clean) or clean) or ""
            Compat.BNetWhisper(redir.bnetName, redir.targetDisplay or t.title, prefill)
            return true
        end
        local altRedir = ResolveAltWhisperRedirect(t)
        if altRedir then
            local prefill = (clean ~= "") and FormatBNetRedirectMessage(altRedir.targetDisplay, clean) or ""
            Compat.Whisper(altRedir.altDisplay, prefill)
            return true
        end
        Compat.Whisper(t.targetName, clean)
        return true
    elseif STATIC_CHANNEL_ORDER[threadKey] then
        if clean ~= "" and not IsInAllowedOfficialChannel(t.kind) and (t.kind == "GUILD" or t.kind == "OFFICER" or t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT") then
            ns:Print(L["You are not currently in that channel."])
            return false
        end
        prefix = STATIC_CHANNEL_ORDER[threadKey].slash .. clean
    else
        return false
    end

    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        local ok = pcall(ChatFrameUtil.OpenChat, prefix)
        return ok
    elseif ChatFrame_OpenChat then
        local ok = pcall(ChatFrame_OpenChat, prefix)
        return ok
    end
    return false
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
    local payload = "DPING|" .. Compat.CleanPayloadField(ns.version or "0.0.0", 24)
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
            local payload = "DPING|" .. Compat.CleanPayloadField(ns.version or "0.0.0", 24)
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

function Chat:SendOrOpenReply(threadKey, rawText, isHardwareEvent)
    if not threadKey or threadKey == "mentions:radar" then return false end
    if type(rawText) == "string" and rawText:find("{", 1, true) and self.ExpandQuickReplyText then
        rawText = self:ExpandQuickReplyText(rawText)
    end
    if threadKey == "notes:self" then
        return self:SavePersonalNote(rawText)
    end
    if threadKey == "ch:alliance" then
        return self:SendAllianceMessage(rawText)
    end
    if threadKey:sub(1, 5) == "room:" then
        return self:SendRoomMessage(threadKey:sub(6), rawText)
    end

    local t = self.threads[threadKey]
    if not t then return false end

    local hasOfficialLink = type(rawText) == "string" and rawText:find("|H", 1, true) and not rawText:find("|Haddon:", 1, true)
    local st = self:GetPeerAddonState(threadKey)
    if (not hasOfficialLink) and (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and st then
        if st.verified == true then
            if st.bnetGameAccId and self.sessionBNetPeers and self.sessionBNetPeers[st.bnetGameAccId] then
                return self:SendDirectMessage(threadKey, rawText)
            end
            if not (t.kind == "WHISPER" and (ResolveBNetRedirectForWhisper(t) or ResolveAltWhisperRedirect(t))) then
                return self:SendDirectMessage(threadKey, rawText)
            end
        elseif (st.state == "registered" or st.state == "unprobed") and st.state ~= "offline" and st.state ~= "disabled" then
            -- Probe silently in the background so future replies upgrade to [SC] without dropping this message.
            if self:ShouldAutoProbe(threadKey) then
                self:ProbePeerAddon(threadKey, false)
            end
        end
    end

    return self:OpenOfficialChatForThread(threadKey, rawText, isHardwareEvent == true)
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
        local _, peerVer = strsplit("|", payload, 2)
        Chat:MarkPeerVerified(cleanSenderStr or (parsedSender and parsedSender.displayName) or senderRaw, bnGameAccId, peerVer, op)
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
                local replyPayload = "DPONG|" .. Compat.CleanPayloadField(ns.version or "0.0.0", 24)
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
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "rmi:" .. roomId,
            kind = "RMI",
            sourceTag = L["Room Invite"],
            sender = hostDisp,
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
        AppendMessage(t, displaySender, msgText, true, classFile, true, false, {
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
    wipe(filterDecisionCache)
    filterDecisionCount = 0
end

local MAX_OFFICIAL_CAPTURE_LINES = 100
local MAX_EDITBOX_HISTORY_LINES = 25
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

local function CaptureOfficialChatLine(chatId, rawMsg)
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
                hooksecurefunc(cf, "AddMessage", function(_, msg)
                    CaptureOfficialChatLine(cid, msg)
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

local function SaveOfficialEditHistoryLine(rawLine)
    if restoringEditHistory then return end
    if Safe.IsSecret(rawLine) then return end
    local st = ns.db and ns.db.settings
    if st and (st.embedOfficialChat == false or st.officialChatEditHistory == false) then
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

local function RestoreSavedEditHistory()
    local st = ns.db and ns.db.settings
    if st and (st.embedOfficialChat == false or st.officialChatEditHistory == false) then
        return
    end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if ns.RunAfterCombat then
            ns:RunAfterCombat("chat_restore_edit_history", RestoreSavedEditHistory)
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

local function EvaluateShieldDecision(eventName, text, author, guid, lineID, channelLabel)
    local cacheKey = (lineID and lineID ~= 0) and (tostring(eventName) .. ":" .. tostring(lineID)) or nil
    if cacheKey and filterDecisionCache[cacheKey] ~= nil then
        return filterDecisionCache[cacheKey]
    end

    local decision = { blocked = false, modifiedText = nil }
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
                decision.blocked = true
                local rLbl = (ns.Store and ns.Store.FormatIgnoreReason) and ns.Store:FormatIgnoreReason(ign.reason, L) or L["Account Ignore"]
                RecordFilteredMessage("IGNORE", rLbl, displayName, lookupKey, GetShortChannelLabel(eventName, channelLabel), text)
            end
        end

        -- 2) Opt-in Public Anti-Spam Shield (never blocks Friends, Guild, BNet, or Group)
        if (not decision.blocked) and s and s.chatAntiSpamEnabled == true then
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
                            wipe(floodTracker)
                            floodTrackerCount = 0
                        end
                        if not floodTracker[fKey] then
                            floodTrackerCount = floodTrackerCount + 1
                        end
                        floodTracker[fKey] = nowClock
                    end
                end

                if matchedReason then
                    decision.blocked = true
                    RecordFilteredMessage("SPAM", matchedReason, displayName, lookupKey, GetShortChannelLabel(eventName, channelLabel), text)
                end
            end
        end
    end

    -- 3) Clickable URLs, {rt1..rt8} Raid Icons & Official Chat Enhancements (only if not blocked)
    if (not decision.blocked) and ((not s) or (s.chatClickableUrls ~= false)) then
        local linked = Chat:LinkifyUrls(text)
        if linked and linked ~= text then
            decision.modifiedText = linked
        end
    end

    if (not decision.blocked) and ((not s) or (s.embedOfficialChat ~= false)) then
        local curTxt = decision.modifiedText or text
        if curTxt:find("{", 1, true) then
            local rtFormatted = Chat:FormatRaidTargetTokens(curTxt)
            if rtFormatted and rtFormatted ~= curTxt then
                decision.modifiedText = rtFormatted
            end
        end
        if eventName == "CHAT_MSG_CHANNEL" and ((not s) or (s.officialChatShortChannels ~= false)) then
            local shortCh = ShortenOfficialChannelLabel(channelLabel)
            if shortCh then
                decision.modifiedChannel = shortCh
            end
        end
        if (not isMe) and eventName ~= "CHAT_MSG_TEXT_EMOTE" and ((not s) or (s.officialChatSenderTags ~= false)) then
            local prefixTags = BuildOfficialSenderTagPrefix(lookupKey, displayName, guid)
            if prefixTags and prefixTags ~= "" then
                decision.modifiedText = prefixTags .. (decision.modifiedText or text)
            end
        end
    end

    if cacheKey then
        if filterDecisionCount >= FILTER_CACHE_MAX then
            wipe(filterDecisionCache)
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

local function ReplaceFilterChannelArg(newMsg, authorRaw, newChannel, langArg, _, ...)
    return false, newMsg, authorRaw, langArg, newChannel, ...
end

local function OfficialChatShieldFilter(_, eventName, msgRaw, authorRaw, ...)
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
    local dec = EvaluateShieldDecision(eventName, msg, author, guid, lineID, channelLabel)
    if dec.blocked then
        return true
    end
    if dec.modifiedChannel and eventName == "CHAT_MSG_CHANNEL" then
        return ReplaceFilterChannelArg(dec.modifiedText or msgRaw, authorRaw, dec.modifiedChannel, ...)
    end
    if dec.modifiedText and dec.modifiedText ~= msg then
        return false, dec.modifiedText, authorRaw, ...
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
        "CHAT_MSG_CHANNEL",
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
    end
    return t
end

function Chat:GetMentionsUnreadCount()
    local t = self.threads and self.threads["mentions:radar"]
    if not t or self:IsThreadMuted("mentions:radar") then
        return 0
    end
    return t.unread or 0
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
    local isPubEv = (eventName == "CHAT_MSG_CHANNEL")

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
        while #mThread.messages > MAX_MENTION_LINES do
            table.remove(mThread.messages, 1)
        end
        mThread.lastAt = entry.ts
        local isViewingMentions = (ns.UI and ns.UI.IsChatThreadVisible and ns.UI:IsChatThreadVisible("mentions:radar")) == true
        if (not isViewingMentions) and not self:IsThreadMuted("mentions:radar") then
            mThread.unread = (mThread.unread or 0) + 1
            mThread.hasMention = true
            self:InvalidateUnreadCache()
        end
        QueueChatEmit(0.08)
    end

    local focusSilenced = Compat.IsFocusSilenced and Compat.IsFocusSilenced(senderLookupKey or senderDisp)
    if not focusSilenced and not self:IsThreadMuted("mentions:radar") then
        if s.mentionSound ~= false then
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
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "mention:" .. tostring(senderLookupKey or senderDisp or "?") .. ":" .. tostring(time()),
            kind = "MENTION",
            sourceTag = L["Mention"] .. " (" .. chLbl .. " · " .. matchedTerm .. ")",
            sender = senderDisp or "?",
            lookupKey = senderLookupKey,
            classFile = classFile,
            text = text,
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
        while #mThread.messages > MAX_MENTION_LINES do
            table.remove(mThread.messages, 1)
        end
        mThread.lastAt = entry.ts
        mThread.unread = (mThread.unread or 0) + 1
        mThread.hasMention = true
        self:InvalidateUnreadCache()
        ns:Emit("CHAT_UPDATED")
    end
    if ns.db and ns.db.settings and ns.db.settings.mentionSound ~= false and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.MAP_PING or 3175, "Master")
    end
    ns:Emit("ADDON_MESSAGE_NOTIFY", {
        id = "mention:test:" .. tostring(time()),
        kind = "MENTION",
        sourceTag = L["Mention"] .. " (" .. L["Guild"] .. ")",
        sender = "Varian Test",
        classFile = "WARRIOR",
        text = L["Hey %s, want to join our dungeon group?"]:format(myDisp),
        threadKey = "mentions:radar",
        ts = time(),
        priority = 2,
    })
end

local function OnChatEvent(event, textRaw, authorRaw, ...)
    if Safe.IsSecret(textRaw) or Safe.IsSecret(authorRaw) then
        return
    end
    local text = Safe.String(textRaw)
    if not text or text == "" then return end

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
            local lineID = Safe.Number(select(9, ...))
            if Chat:IsMessageBlockedByShield(event, text, author, guid, lineID, L["Whisper"]) then
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
        local t = EnsureThread(key, kind, title, {
            targetName = PickNonClobberTarget(linked, peerParsed.displayName),
            bnetAccountID = bnAccId or (linked and linked.bnetAccountID),
            bnetName = bnAccName or (linked and linked.bnetName),
            classFile = (linked and linked.classFile) or cls,
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
                targetChar = targetCharLabel,
                targetClass = incoming and Safe.String(myClass) or cls,
                previewCategory = "WHISPER",
                previewChannelKind = "WHISPER",
            })
        else
            ns:Emit("CHAT_UPDATED")
        end
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
        local chatModOn = (not Compat or not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("chat")
        local qrOn = chatModOn and s ~= nil and (s.quickReplyEnabled ~= false)
        local qrNeedsChan = qrOn and (
            ((chKind == "PARTY" or chKind == "INSTANCE_CHAT") and (s.quickReplyNotifyParty ~= false))
            or (chKind == "RAID" and (s.quickReplyNotifyRaid == true))
            or ((chKind == "GUILD" or chKind == "OFFICER") and (s.quickReplyNotifyGuild == true))
        )
        local previewNeedsChan = chatModOn and s ~= nil and (
            s.msgPreviewPromptAnswered ~= true
            or (s.msgPreviewEnabled ~= false and (
                (pCat == "GROUP" and s.msgPreviewGroup == true)
                or (pCat == "GUILD" and s.msgPreviewGuild == true)
            ))
        )
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
        if isMe and not mirrorOn and not qrNeedsChan and not previewNeedsChan then
            if manualChanRec and manualChanRec.optimisticEntry then
                ns:Emit("CHAT_UPDATED")
                return
            end
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
            return
        end
        local meta = STATIC_CHANNEL_ORDER[chKey]
        local cls = parsed and LookupClassFromCache(parsed.lookupKey, guid)
        local senderLabel = ResolveChatSenderDisplay((parsed and parsed.displayName) or author, guid, nil)
        local lineID = Safe.Number(select(9, ...))
        if not isMe then
            if Chat:IsMessageBlockedByShield(event, text, author, guid, lineID, L[meta.titleKey]) then
                return
            end
            Chat:EvaluateIncomingMention(event, text, senderLabel, parsed and parsed.lookupKey, guid, cls, L[meta.titleKey], chKey)
        end
        if not mirrorOn and not qrNeedsChan and not previewNeedsChan then
            if not isMe and event ~= "CHAT_MSG_RAID_WARNING" and not Chat:IsThreadMuted(chKey) then
                PlayIncomingChime(chKind, chKey, false, (parsed and parsed.lookupKey) or chKey)
            end
            return
        end
        if (mirrorOn or qrNeedsChan or previewNeedsChan) and event ~= "CHAT_MSG_RAID_WARNING" then
            if isMe and manualChanRec and manualChanRec.optimisticEntry then
                ns:Emit("CHAT_UPDATED")
            else
                local t = EnsureThread(chKey, chKind, L[meta.titleKey], { slash = meta.slash })
                AppendMessage(t, senderLabel, text, not isMe, cls, true, isMe == true, {
                    senderGuid = guid,
                    senderCharName = senderLabel,
                    previewCategory = pCat,
                    previewChannelKind = chKind,
                    replySlash = meta.slash,
                })
            end
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
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_CHANNEL" then
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        local guid = Safe.String(select(10, ...))
        local isMe = (parsed and Compat.IsMe(parsed.displayName, guid)) or (author and Compat.IsMe(author, guid))
        if not isMe then
            local chLabel = Safe.String(select(2, ...)) or Safe.String(select(7, ...))
            local lineID = Safe.Number(select(9, ...))
            if not Chat:IsMessageBlockedByShield(event, text, author, guid, lineID, chLabel) then
                local cls = parsed and LookupClassFromCache(parsed.lookupKey, guid)
                local senderLabel = ResolveChatSenderDisplay((parsed and parsed.displayName) or author, guid, nil)
                Chat:EvaluateIncomingMention(event, text, senderLabel, parsed and parsed.lookupKey, guid, cls, GetShortChannelLabel(event, chLabel), nil)
            end
        end
    end
end

function Chat:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end
    self:LoadSavedHistory()
    self:EnsurePersonalNotesThread()
    self:EnsureMentionsThread()
    InstallChatShieldFilters()
    InstallOfficialChatCaptureHooks()
    InstallOfficialEditBoxHistoryHooks()

    ns:On("SETTINGS_UPDATED", function()
        self:InvalidateOfficialChatCache()
    end)
    ns:On("SOCIAL_META_UPDATED", function()
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
    }) do
        ns.RegisterEvent(self, ev, function(_, eventName, ...)
            OnChatEvent(eventName, ...)
        end)
    end

    ns.RegisterEvent(self, "CHAT_MSG_ADDON", function(_, _, prefix, text, channel, sender)
        local chan = Safe.String(channel)
        if Safe.String(prefix) == PREFIX and (not chan or chan == "WHISPER") then
            HandleIncomingAddonPacket(text, sender, nil)
        end
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
                ns:Emit("CHAT_UPDATED")
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
            local fullName, lvl
            if C_FriendList and C_FriendList.GetWhoInfo then
                local info = Safe.Call(C_FriendList.GetWhoInfo, i)
                if type(info) == "table" then
                    fullName = Safe.String(info.fullName)
                    lvl = ValidLevel(Safe.Number(info.level))
                end
            elseif GetWhoInfo then
                local ok, wName, _, wLvl = pcall(GetWhoInfo, i)
                if ok then
                    fullName = Safe.String(wName)
                    lvl = ValidLevel(Safe.Number(wLvl))
                end
            end
            if fullName and lvl then
                local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(fullName)
                local lk = parsed and parsed.lookupKey
                if lk and lk ~= "" then
                    if whoLevelCache[lk] == nil then
                        if whoLevelCount >= MAX_WHO_LEVEL_CACHE then
                            wipe(whoLevelCache)
                            whoLevelCount = 0
                        end
                        whoLevelCount = whoLevelCount + 1
                    end
                    if whoLevelCache[lk] ~= lvl then
                        whoLevelCache[lk] = lvl
                        updated = true
                    end
                    local wt = Chat.threads and Chat.threads["w:" .. lk]
                    if wt and (not wt.level or wt.level <= 0 or wt.level < lvl) then
                        wt.level = lvl
                        updated = true
                    end
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
        local candLow = cand:lower()
        if lowerMsg:find(candLow, 1, true) then
            return true
        end
        if candLow:find("-", 1, true) and lowerMsg:find((candLow:gsub("%-", " ")), 1, true) then
            return true
        end
        if candLow:find(" ", 1, true) and lowerMsg:find((candLow:gsub("%s+", "-")), 1, true) then
            return true
        end
        return false
    end

    -- Disqualify Forever WHISPER candidate strings that the server explicitly reports as not playing, and recover lost manual whisper drafts.
    ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", function(_, _, msgRaw)
        if Safe.IsSecret(msgRaw) then return end
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

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if not Chat._editHistRestored then
            Chat._editHistRestored = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0.8, RestoreSavedEditHistory)
            else
                RestoreSavedEditHistory()
            end
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
