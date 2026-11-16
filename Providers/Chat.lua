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
local PING_COOLDOWN = 10
local PONG_COOLDOWN = 6
local NACK_COOLDOWN = 8
local SOUND_COOLDOWN = 2.0
local PING_TIMEOUT = 5.0
local HISTORY_TTL_SECONDS = 30 * 86400
local MAX_SAVED_THREADS = 80
local PEER_TTL_SECONDS = 60 * 86400
local MAX_SAVED_PEERS = 500
local DISCOVERY_PING_INTERVAL = 8.0
local BNET_CACHE_TTL = 4.0
local ERR_NOT_FOUND_PATTERN = _G.ERR_CHAT_PLAYER_NOT_FOUND_S and ("^" .. _G.ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".*"))

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
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

local function GetRoomsScopeTable()
    local root = ns.db and ns.db.chatRooms
    if not root then return nil end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

local function GetAddonPeersScopeTable()
    local root = ns.db and ns.db.addonPeers
    if not root then return nil end
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

local function PruneSavedScopeTable(tbl, ttlSeconds, maxEntries, getStamp)
    if type(tbl) ~= "table" then return end
    local now = time()
    local entries = {}
    for k, v in pairs(tbl) do
        if type(k) ~= "string" or type(v) ~= "table" then
            tbl[k] = nil
        else
            local ts = tonumber(getStamp(v)) or 0
            if now > ttlSeconds and ts > 0 and (now - ts) > ttlSeconds then
                tbl[k] = nil
            else
                entries[#entries + 1] = { key = k, ts = ts }
            end
        end
    end
    if #entries > maxEntries then
        table.sort(entries, function(a, b)
            return a.ts > b.ts
        end)
        for i = maxEntries + 1, #entries do
            tbl[entries[i].key] = nil
        end
    end
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

local function GetMyInfo()
    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    if resolvedSelf and resolvedSelf.fullName and resolvedSelf.fullName ~= "" then
        local p = Compat.ParseCharacterName and Compat.ParseCharacterName(resolvedSelf.fullName)
        if p then
            return p.displayName, p.lookupKey, p.firstName, p.surname
        end
        return resolvedSelf.fullName, resolvedSelf.fullName:lower(), resolvedSelf.firstName or resolvedSelf.fullName, resolvedSelf.surname
    end
    local raw = Safe.String(Safe.Call(UnitName, "player")) or "Unknown"
    local parsed = Compat.ParseCharacterName(raw)
    if parsed then
        return parsed.displayName, parsed.lookupKey, parsed.firstName, parsed.surname
    end
    return raw, raw:lower(), raw, nil
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

function Chat:MarkAllRead()
    for _, t in pairs(self.threads) do
        t.unread = 0
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

local function PlayIncomingChime(kind, threadKey)
    if not ShouldPlaySoundForThread(kind, threadKey) then
        return
    end
    local monoNow = GetTime and GetTime() or time()
    if (monoNow - (Chat.lastChimeAt or 0)) < SOUND_COOLDOWN then
        return
    end
    if PlaySound and SOUNDKIT then
        local kit
        if kind == "ROOM" then
            kit = SOUNDKIT.UI_BNET_TOAST or SOUNDKIT.IG_QUEST_LIST_OPEN or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.TELL_MESSAGE
        elseif kind == "ALLIANCE" then
            kit = SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        else
            kit = SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        end
        if kit then
            Chat.lastChimeAt = monoNow
            pcall(PlaySound, kit, "Master")
        end
    end
end

local function EnsureThread(key, kind, title, extra)
    if not key or key == "" then return nil end
    local t = Chat.threads[key]
    if not t then
        t = {
            key = key,
            kind = kind or "WHISPER",
            title = title or key,
            targetName = extra and extra.targetName or nil,
            bnetAccountID = extra and extra.bnetAccountID or nil,
            bnetName = extra and extra.bnetName or nil,
            classFile = extra and extra.classFile or nil,
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
            if extra.targetName then t.targetName = extra.targetName end
            if extra.bnetAccountID then t.bnetAccountID = extra.bnetAccountID end
            if extra.bnetName then t.bnetName = extra.bnetName end
            if extra.classFile then t.classFile = extra.classFile end
            if extra.slash then t.slash = extra.slash end
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

local function PersistWhisperLine(threadKey, entry)
    if type(threadKey) ~= "string" or threadKey:sub(1, 2) ~= "w:" then
        return
    end
    local limit = GetChatHistoryLimit()
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
    saved.title = entry.threadTitle or saved.title
    saved.targetName = entry.targetName or saved.targetName
    saved.updatedAt = entry.ts or time()
    if type(saved.lines) ~= "table" then saved.lines = {} end

    -- Store strictly character name + plain text (never BattleTag or Real ID).
    table.insert(saved.lines, {
        sender = entry.sender,
        text = entry.text,
        ts = entry.ts,
        incoming = entry.incoming and true or false,
    })
    while #saved.lines > limit do
        table.remove(saved.lines, 1)
    end
    if isNewThread and CountHashKeys(hist) > MAX_SAVED_THREADS then
        PruneSavedScopeTable(hist, HISTORY_TTL_SECONDS, MAX_SAVED_THREADS, GetHistoryStamp)
    end
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

local function AppendMessage(thread, senderName, text, incoming, classFile, skipPersist, silent, extraFields)
    if not thread or not text or text == "" then return end
    local ts = time()
    local entry = {
        sender = senderName or "?",
        text = text,
        ts = ts,
        incoming = incoming and true or false,
        classFile = classFile,
        threadTitle = thread.title,
        targetName = thread.targetName,
        viaAddon = extraFields and extraFields.viaAddon and true or false,
        deliveryMsgId = extraFields and extraFields.deliveryMsgId or nil,
        deliveryState = extraFields and extraFields.deliveryState or nil,
    }
    table.insert(thread.messages, entry)
    while #thread.messages > MAX_THREAD_LINES do
        table.remove(thread.messages, 1)
    end
    thread.lastAt = ts

    local mainVisible = ns.UI and ns.UI.IsMainVisible and ns.UI:IsMainVisible()
    local isViewing = false
    if ns.UI and ns.UI.IsChatThreadVisible then
        isViewing = ns.UI:IsChatThreadVisible(thread.key)
    elseif mainVisible then
        isViewing = (Chat.activeThreadKey == thread.key)
    end
    local isMuted = Chat:IsThreadMuted(thread.key)
    local isPublic = IsPublicChannelKind(thread.kind)
    local allowChannelUnread = ns.db and ns.db.settings and ns.db.settings.chatChannelUnread == true

    if incoming and not isViewing and not isMuted then
        if (not isPublic) or allowChannelUnread then
            thread.unread = (thread.unread or 0) + 1
            Chat:InvalidateUnreadCache()
        end
        if not silent then
            PlayIncomingChime(thread.kind, thread.key)
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
            local cleanPreview = Compat.CleanPayloadField(text, 100)
            local sourceTag
            if notifyKind == "ALLIANCE" then
                sourceTag = L["Alliance"]
            elseif notifyKind == "ROOM" then
                sourceTag = (thread.title and thread.title ~= "") and thread.title or L["Private Room"]
            else
                sourceTag = L["Direct Addon"]
            end
            local s = ns.db and ns.db.settings
            if s and s.addonMsgChatEcho ~= false then
                local hex = classFile and Compat.ClassHex(classFile) or "|cffd2a8ff"
                local echoLine = ("|cff3fb950[SC %s]|r %s%s|r: %s |Haddon:SCentral:thread:%s|h|cff58a6ff[%s]|r|h"):format(
                    sourceTag,
                    hex,
                    tostring(senderName or "?"),
                    cleanPreview,
                    tostring(thread.key),
                    L["Open"]
                )
                ns:Print("%s", echoLine)
            end
            ns:Emit("ADDON_MESSAGE_NOTIFY", {
                id = extraFields.deliveryMsgId or (tostring(thread.key) .. ":" .. tostring(ts)),
                kind = notifyKind,
                sourceTag = sourceTag,
                sender = tostring(senderName or "?"),
                senderClass = classFile,
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

    if not skipPersist and thread.kind == "WHISPER" then
        PersistWhisperLine(thread.key, entry)
    end

    if isPublic and not mainVisible then
        QueueChatEmit(0.30)
    else
        ns:Emit("CHAT_UPDATED")
    end
    return entry
end

local function LookupClassFromCache(lookupKey, guid)
    if not lookupKey and not guid then return nil end
    if guid and Compat.ClassFileFromGuid then
        local cf = Compat.ClassFileFromGuid(guid)
        if cf then return cf end
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
        if Store and Store.nearby and Store.nearby[lookupKey] then
            return Store.nearby[lookupKey].classFile
        end
        if Store and Store.GetWatchlistTable then
            local wl = Store:GetWatchlistTable()
            if wl and wl[lookupKey] then
                return wl[lookupKey].classFile
            end
        end
    end
    return nil
end

function Chat:LoadSavedHistory()
    local limit = GetChatHistoryLimit()
    local hist = GetHistoryScopeTable()
    if hist then
        PruneSavedScopeTable(hist, HISTORY_TTL_SECONDS, MAX_SAVED_THREADS, GetHistoryStamp)
    end
    local savedPeers = GetAddonPeersScopeTable()
    if savedPeers then
        PruneSavedScopeTable(savedPeers, PEER_TTL_SECONDS, MAX_SAVED_PEERS, GetPeerStamp)
    end
    if hist and limit > 0 then
        for threadKey, saved in pairs(hist) do
            if type(threadKey) == "string" and threadKey:sub(1, 2) == "w:" and type(saved) == "table" and type(saved.lines) == "table" then
                local parsed = Compat.ParseCharacterName(saved.targetName or saved.title or threadKey:sub(3))
                if parsed then
                    local t = EnsureThread(threadKey, "WHISPER", parsed.displayName, {
                        targetName = parsed.displayName,
                        classFile = LookupClassFromCache(parsed.lookupKey),
                    })
                    t.messages = {}
                    local startIdx = math.max(1, #saved.lines - limit + 1)
                    for i = startIdx, #saved.lines do
                        local line = saved.lines[i]
                        if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                            table.insert(t.messages, {
                                sender = line.sender or parsed.firstName or parsed.displayName,
                                text = line.text,
                                ts = tonumber(line.ts) or 0,
                                incoming = line.incoming and true or false,
                            })
                            t.lastAt = math.max(t.lastAt or 0, tonumber(line.ts) or 0)
                        end
                    end
                end
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
    self:InvalidateUnreadCache()
end

function Chat:GetUnreadSummary()
    local s = ns.db and ns.db.settings
    local mirrorOn = s and s.chatMirrorChannels == true
    local allowChanUnread = s and s.chatChannelUnread == true
    local chanFlag = (mirrorOn and allowChanUnread) and true or false
    if not self._unreadSummaryDirty and self._unreadSummaryCache and self._unreadSummaryChanFlag == chanFlag then
        return self._unreadSummaryCache
    end

    local direct, roomsUnread, invites, channels = 0, 0, 0, 0
    local senders = {}

    for key, t in pairs(self.threads) do
        local u = t.unread or 0
        if u > 0 and not self:IsThreadMuted(key) then
            if IsPublicChannelKind(t.kind) then
                if chanFlag then
                    channels = channels + u
                end
            elseif t.kind == "ROOM" then
                roomsUnread = roomsUnread + u
                table.insert(senders, {
                    key = key,
                    title = t.title or key,
                    unread = u,
                    kind = t.kind,
                    lastAt = t.lastAt or 0,
                })
            else
                direct = direct + u
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
            end
        end
    end

    table.sort(senders, function(a, b)
        return (a.lastAt or 0) > (b.lastAt or 0)
    end)

    local totalDirect = direct + roomsUnread + invites
    local summary = {
        direct = direct,
        rooms = roomsUnread,
        invites = invites,
        channels = channels,
        totalDirect = totalDirect,
        total = totalDirect + channels,
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
    if t and (t.unread or 0) > 0 then
        t.unread = 0
        self:InvalidateUnreadCache()
        ns:Emit("CHAT_UPDATED")
    end
end

function Chat:SetActiveThread(threadKey, skipMarkRead)
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
        elseif key:sub(1, 3) == "ch:" then
            local isGuildChan = (t.kind == "GUILD" or t.kind == "OFFICER")
            local isGroupChan = (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT")
            local isAllianceChan = (t.kind == "ALLIANCE")
            local inGuild = Compat.IsInGuild and Compat.IsInGuild()
            local inGroup = Compat.IsInGroup and Compat.IsInGroup()
            local isAllianceAuth = ns.Clan and ns.Clan.IsMemberAllianceAuthorized and ns.Clan:IsMemberAllianceAuthorized()
            local forceShow = (isGuildChan and inGuild and kindFilter == "guild")
                or (isGroupChan and inGroup and kindFilter == "group")
                or (isAllianceChan and isAllianceAuth and (kindFilter == "alliance" or kindFilter == "channels" or not kindFilter or kindFilter == "all"))
            include = (isAllianceChan and isAllianceAuth) or (mirrorChannels and #(t.messages or {}) > 0) or forceShow
        end

        if include and kindFilter and kindFilter ~= "all" then
            if kindFilter == "unread" then
                include = (not self:IsThreadMuted(key)) and ((t.unread or 0) > 0)
            elseif kindFilter == "whispers" then
                include = (t.kind == "WHISPER" or t.kind == "BN_WHISPER")
            elseif kindFilter == "guild" then
                include = (t.kind == "GUILD" or t.kind == "OFFICER")
            elseif kindFilter == "group" then
                include = (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT")
            elseif kindFilter == "alliance" then
                include = (t.kind == "ALLIANCE")
            elseif kindFilter == "rooms" then
                include = (t.kind == "ROOM")
            elseif kindFilter == "channels" then
                include = IsPublicChannelKind(t.kind)
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
            item.roomId = t.roomId
            item.unread = isMuted and 0 or (t.unread or 0)
            item.muted = isMuted
            item.lastAt = t.lastAt or 0
            item.preview = lastMsg and lastMsg.text or ""
            item.count = t.messages and #t.messages or 0
            table.insert(out, item)
        end
    end

    table.sort(out, function(a, b)
        if (a.unread or 0) ~= (b.unread or 0) then
            return (a.unread or 0) > (b.unread or 0)
        end
        if (a.lastAt or 0) ~= (b.lastAt or 0) then
            return (a.lastAt or 0) > (b.lastAt or 0)
        end
        if a.kind ~= b.kind then
            return (a.kind == "ROOM")
        end
        return (a.title or "") < (b.title or "")
    end)
    return out
end

function Chat:GetThreadMessages(threadKey)
    local t = threadKey and self.threads[threadKey]
    return t and t.messages or {}
end

local function FindLinkedDirectThread(parsed, bnetAccountID)
    if bnetAccountID then
        local bnThread = Chat.threads["bn:" .. tostring(bnetAccountID)]
        if bnThread then return bnThread end
    end
    if parsed and parsed.lookupKey then
        local wThread = Chat.threads["w:" .. parsed.lookupKey]
        if wThread then return wThread end
        for _, t in pairs(Chat.threads) do
            if type(t) == "table" and t.kind == "BN_WHISPER" then
                if bnetAccountID and t.bnetAccountID == bnetAccountID then
                    return t
                end
                if t.targetName then
                    local tp = Compat.ParseCharacterName(t.targetName)
                    if tp and tp.lookupKey == parsed.lookupKey then
                        return t
                    end
                end
            end
        end
    end
    return nil
end

function Chat:EnsureWhisperThread(rawTarget, classFile)
    local parsed = Compat.ParseCharacterName(rawTarget)
    if not parsed then return nil end
    local resolvedClass = classFile or LookupClassFromCache(parsed.lookupKey)
    local _, _, bnAccName, bnAccId = FindBNetWoWGameAccountByChar(parsed)
    local existing = FindLinkedDirectThread(parsed, bnAccId)
    local key = existing and existing.key or ("w:" .. parsed.lookupKey)
    local kind = existing and existing.kind or "WHISPER"
    local title = (existing and existing.title and existing.title ~= "" and existing.title) or parsed.displayName
    local t = EnsureThread(key, kind, title, {
        targetName = parsed.displayName,
        bnetAccountID = bnAccId or (existing and existing.bnetAccountID),
        bnetName = bnAccName or (existing and existing.bnetName),
        classFile = resolvedClass,
    })
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
            t.lastAt = 0
        end
        if hist then hist[threadKey] = nil end
    else
        for key, t in pairs(self.threads) do
            t.messages = {}
            t.unread = 0
            t.lastAt = 0
            if hist then hist[key] = nil end
        end
    end
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
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
        local score = (isOnline and isWoW) and ((not WOW_PROJECT_ID or Safe.Value(gi.wowProjectID) == WOW_PROJECT_ID) and 100 or 50) or 0

        local rec = {
            gId = gId,
            accId = accId,
            accName = accName,
            fullChar = fullChar,
            score = score,
        }

        if gId and not bnetCache.anyByGameId[gId] then
            bnetCache.anyByGameId[gId] = rec
        end
        if accId and not bnetCache.anyById[accId] then
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

local function ResolveBNetSender(bnGameAccId)
    if not bnGameAccId then return nil end
    local cache = EnsureBNetLookupCache()
    local rec = cache.anyByGameId[bnGameAccId] or cache.anyById[bnGameAccId]
    if rec then
        return rec.accId, rec.accName, rec.fullChar
    end
    return nil
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
    if CountTable(room.members) >= MAX_ROOM_MEMBERS then
        ns:Print(L["Room member limit reached."])
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

    if parsed then
        room.members[parsed.lookupKey] = parsed.displayName
    end
    if bnetGameId then
        self.roomBNetTargets[roomId] = self.roomBNetTargets[roomId] or {}
        self.roomBNetTargets[roomId][bnetGameId] = (parsed and parsed.firstName) or "Friend"
    end
    room.updatedAt = time()

    local hostDisplay = GetMyInfo()
    local payload = string.format(
        "RMI|%s|%s|%s",
        roomId,
        NonEmptyField(room.title, 32, roomId),
        NonEmptyField(hostDisplay, 32, hostDisplay)
    )

    local sent = SendRoomPacket(parsed and parsed.displayName, bnetGameId, payload)
    if sent then
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
    if room.host or room.hostBNetGameId then
        local payload = string.format("RMJ|%s|%s|0", roomId, NonEmptyField(meDisplay, 32, meDisplay))
        SendRoomPacket(room.host, room.hostBNetGameId, payload)
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
    for key, target in pairs(room.members or {}) do
        if key ~= meKey then
            SendRoomPacket(target, nil, payload)
        end
    end
    if self.roomBNetTargets[roomId] then
        for bnetGameId in pairs(self.roomBNetTargets[roomId]) do
            SendRoomPacket(nil, bnetGameId, payload)
        end
        self.roomBNetTargets[roomId] = nil
    end

    rooms[roomId] = nil
    self.threads["room:" .. roomId] = nil
    if self.activeThreadKey == ("room:" .. roomId) then
        self.activeThreadKey = nil
    end
    self:InvalidateUnreadCache()
    ns:Emit("CHAT_UPDATED")
end

function Chat:SendRoomMessage(roomId, rawText)
    if not GuardAddonMessaging(true) then
        return false
    end

    local room = self:GetRoom(roomId)
    if not room or not room.joined then
        return false
    end

    local cleanText = Compat.CleanPayloadField(rawText, 150)
    if cleanText == "" then
        return false
    end

    local now = GetTime and GetTime() or time()
    if (now - (self.lastRoomSendAt or 0)) < ROOM_SEND_COOLDOWN then
        ns:Print(L["Please wait a moment before sending another room message."])
        return false
    end
    self.lastRoomSendAt = now

    local _, meKey, myFirst = GetMyInfo()
    local senderShort = myFirst
    local payload = string.format("RM|%s|%s|%s", roomId, NonEmptyField(senderShort, 24, senderShort), cleanText)
    if #payload > MAX_PAYLOAD_BYTES then
        ns:Print(L["Message is too long for an addon room packet."])
        return false
    end

    local sentCount = 0
    for key, target in pairs(room.members or {}) do
        if key ~= meKey then
            if SendRoomPacket(target, nil, payload) then
                sentCount = sentCount + 1
            end
        end
    end
    if self.roomBNetTargets[roomId] then
        for bnetGameId in pairs(self.roomBNetTargets[roomId]) do
            if SendRoomPacket(nil, bnetGameId, payload) then
                sentCount = sentCount + 1
            end
        end
    end

    local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
    local _, myClass = Safe.Call(UnitClass, "player")
    AppendMessage(t, senderShort, cleanText, false, Safe.String(myClass), true, true)
    if sentCount == 0 then
        AppendMessage(t, L["System"], L["No online room peers reached yet; invite friends or guildmates."], false, nil, true, true)
    end
    return true
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
    local displayName = gTag .. (authorName or "?")

    local _, meKey, myFirst = GetMyInfo()
    local isMe = Compat.IsMe(authorName) or (authorName == myFirst or authorName == meKey)
    AppendMessage(t, displayName, msgText, not isMe, classFile, true, false, {
        viaAddon = true,
        notifyKind = "ALLIANCE",
        deliveryMsgId = msgId,
    })
end

function Chat:SendAllianceMessage(rawText)
    if not rawText or rawText == "" then return false end
    if not ns.Clan or not ns.Clan:IsMemberAllianceAuthorized() then
        ns:Print(L["You do not have permission to use Alliance Chat."])
        return false
    end

    local clean = Compat.CleanPayloadField(rawText, 140)
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
    return not (s and s.addonDirectChat == false)
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
        return false, "not_in_wow"
    end
    if not parsed then
        return false, "invalid"
    end

    local seenAt = Chat.seenOnlineChars and Chat.seenOnlineChars[parsed.lookupKey]
    if Store then
        local wl = Store.GetWatchlistTable and Store:GetWatchlistTable()
        local wlEntry = wl and wl[parsed.lookupKey]
        if wlEntry then
            local checked = tonumber(wlEntry.checkedAt or wlEntry.lastSeenAt or 0) or 0
            if wlEntry.online == true then
                return true, "watchlist"
            elseif wlEntry.online == false and (not seenAt or checked > seenAt) then
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
            elseif socialRow.online == false and (not seenAt or (tonumber(socialRow.lastSeenAt or 0) or 0) > seenAt) then
                return false, "offline"
            end
        end

        local nearbyRow = type(Store.nearby) == "table" and Store.nearby[parsed.lookupKey]
        if type(nearbyRow) == "table" then
            if nearbyRow.online == true then
                return true, "store"
            elseif nearbyRow.online == false and (not seenAt or (tonumber(nearbyRow.lastSeenAt or 0) or 0) > seenAt) then
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
        if ts <= 0 or (now - ts) <= PEER_TTL_SECONDS then
            best = rec
            bestTs = ts
        end
    end
    local clanBucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local clanPeers = clanBucket and clanBucket.peers
    local cRec = clanPeers and clanPeers[lookupKey]
    if type(cRec) == "table" then
        local cTs = tonumber(cRec.updatedAt) or 0
        if cTs <= 0 or (now - cTs) <= PEER_TTL_SECONDS then
            if (not best) or cTs > bestTs then
                best = cRec
                bestTs = cTs
            end
        end
    end
    return best
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

    local bnetGameAccId, bnetChar
    if t.bnetAccountID then
        local gId, gChar = FindBNetWoWGameAccount(t.bnetAccountID)
        if t.kind == "BN_WHISPER" then
            bnetGameAccId, bnetChar = gId, gChar
            if bnetChar then
                t.targetName = bnetChar
            end
        elseif gId then
            local rawCand = t.targetName or t.title
            local rawParsed = rawCand and Compat.ParseCharacterName(rawCand)
            local gParsed = gChar and Compat.ParseCharacterName(gChar)
            if (gParsed and rawParsed and gParsed.lookupKey == rawParsed.lookupKey) or not rawParsed then
                bnetGameAccId, bnetChar = gId, gChar
            end
        end
    end

    local rawTargetChar = bnetChar or t.targetName or (t.kind == "WHISPER" and t.title or "")
    if t._targetParsedRaw ~= rawTargetChar then
        t._targetParsedRaw = rawTargetChar
        t._targetParsed = Compat.ParseCharacterName(rawTargetChar)
    end
    local parsed = t._targetParsed

    if t.kind == "WHISPER" and not bnetGameAccId and parsed then
        local guidHint
        if Store then
            local sr = Store.socialByLookup and Store.socialByLookup[parsed.lookupKey]
            local wl = Store.GetWatchlistTable and Store:GetWatchlistTable()
            local wlEntry = wl and wl[parsed.lookupKey]
            guidHint = (sr and sr.guid) or (wlEntry and wlEntry.guid)
        end
        bnetGameAccId = select(1, FindBNetWoWGameAccountByChar(parsed, guidHint))
    end
    if parsed and ns.Clan and ns.Clan.peerVersions and ns.Clan.peerVersions[parsed.lookupKey] and not self.sessionPeers[parsed.lookupKey] then
        local clanVer = Safe.String(ns.Clan.peerVersions[parsed.lookupKey])
        if clanVer and clanVer ~= "" then
            self.sessionPeers[parsed.lookupKey] = {
                version = clanVer,
                verifiedAt = time(),
                source = "CLAN",
            }
        end
    end

    local sess = parsed and self.sessionPeers[parsed.lookupKey]
    local bnSess = bnetGameAccId and self.sessionBNetPeers[bnetGameAccId]
    local prevSaved = parsed and self:GetSavedPeerRecord(parsed.lookupKey)
    local prevLastSeen = prevSaved and (tonumber(prevSaved.lastSeenAt) or tonumber(prevSaved.updatedAt)) or nil
    local prevVer = prevSaved and prevSaved.version
    local online = IsCharacterOnlineOrReachable(parsed, t.kind == "BN_WHISPER" and t.bnetAccountID or nil)
    local resolvedTarget = parsed and parsed.displayName or t.targetName

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
        }
    else
        local probeKey = t.key
        local pendingAt = self.pendingProbes and self.pendingProbes[probeKey]
        local isChecking = pendingAt and (monoNow - pendingAt) < PING_TIMEOUT

        if prevSaved then
            st = {
                state = "registered",
                verified = true,
                fromRegistry = true,
                confirming = isChecking == true,
                knownAddon = true,
                version = prevVer or "SC",
                lastSeenAt = prevLastSeen,
                targetChar = resolvedTarget,
                rawTargetChar = rawTargetChar,
                bnetGameAccId = bnetGameAccId,
            }
        elseif isChecking then
            st = {
                state = "checking",
                verified = false,
                knownAddon = false,
                targetChar = resolvedTarget,
                rawTargetChar = rawTargetChar,
                bnetGameAccId = bnetGameAccId,
            }
        else
            local failInfo = self.probeFailures and self.probeFailures[probeKey]
            if failInfo then
                st = {
                    state = "unverified",
                    verified = false,
                    knownAddon = false,
                    reason = failInfo,
                    targetChar = resolvedTarget,
                    rawTargetChar = rawTargetChar,
                    bnetGameAccId = bnetGameAccId,
                }
            else
                st = {
                    state = "unprobed",
                    verified = false,
                    knownAddon = false,
                    targetChar = resolvedTarget,
                    rawTargetChar = rawTargetChar,
                    bnetGameAccId = bnetGameAccId,
                }
            end
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

function Chat:GetLookupKeyAddonBadge(lookupKey)
    if not lookupKey or lookupKey == "" then return "" end
    if self:IsLookupKeyVerified(lookupKey) then
        return " |cff3fb950[SC]|r"
    end
    local rec = self:GetSavedPeerRecord(lookupKey)
    if rec then
        return " |cff8ab4f8[SC*]|r"
    end
    return ""
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
        local parsed = Compat.ParseCharacterName(target)
        local foreverTarget = Compat.FormatForeverTarget(target) or target
        local short = (parsed and parsed.firstName) or foreverTarget
        return {
            kind = "WHISPER",
            slash = "/w " .. foreverTarget .. " ",
            targetName = foreverTarget,
            label = short,
            buttonText = string.format(L["Send via WoW Whisper (/w %s)"], foreverTarget),
            compactButtonText = string.format(L["Whisper (/w %s)"], short),
        }
    end

    return nil
end

function Chat:OpenOfficialChatForThread(threadKey, optionalDraft)
    local t = threadKey and self.threads[threadKey]
    if not t then return false end

    local clean = Compat.CleanInput(optionalDraft) or ""
    if t.kind == "BN_WHISPER" then
        Compat.BNetWhisper(t.bnetName, t.targetName or t.title)
        return true
    end

    local prefix
    if t.kind == "WHISPER" and t.targetName then
        if clean == "" then
            if t.bnetAccountID and t.bnetName then
                local parsedTarget = Compat.ParseCharacterName(t.targetName)
                local bnetGId = select(1, FindBNetWoWGameAccount(t.bnetAccountID))
                if bnetGId and (not IsCharacterOnlineOrReachable(parsedTarget, nil)) then
                    Compat.BNetWhisper(t.bnetName, t.targetName or t.title)
                    return true
                end
            end
            Compat.Whisper(t.targetName)
            return true
        end
        prefix = "/w " .. (Compat.FormatForeverTarget(t.targetName) or t.targetName) .. " " .. clean
    elseif STATIC_CHANNEL_ORDER[threadKey] then
        prefix = STATIC_CHANNEL_ORDER[threadKey].slash .. clean
    else
        return false
    end

    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, prefix)
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, prefix)
        return true
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
    local sent, errOrCand = SendRoomPacket(target, state.bnetGameAccId, payload, attemptOffset, {
        sendAllCandidates = false,
        forceAllCandidates = false,
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
    if st.state == "registered" then
        self.autoProbedRegistered = self.autoProbedRegistered or {}
        if not self.autoProbedRegistered[threadKey] then
            self.autoProbedRegistered[threadKey] = true
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
            C_Timer.After(DISCOVERY_PING_INTERVAL - elapsed + 0.2, DrainDiscoveryQueue)
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
                -- Only reply-probe live incoming whispers (1 candidate max, zero periodic probes).
                Chat.lastDiscoveryPingAt = monoNow
                SendRoomPacket(item.targetName, nil, payload, 0, {
                    allowBNet = false,
                    sendAllCandidates = false,
                    trackCandidateKey = item.trackKey,
                })
            end
        end
    end

    if #queue > 0 and C_Timer and C_Timer.After then
        Chat._discoveryTimerActive = true
        C_Timer.After(DISCOVERY_PING_INTERVAL + 0.2, DrainDiscoveryQueue)
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
    self.discoveryQueue[#self.discoveryQueue + 1] = {
        targetName = (parsed and parsed.displayName) or opts.targetName,
        parsed = parsed,
        lookupKey = lk,
        bnetAccountID = opts.bnetAccountID,
        guid = opts.guid,
        allowWhisperReply = opts.allowWhisperReply == true,
        trackKey = "disc:" .. dedupKey,
    }
    if not self._discoveryTimerActive then
        local monoNow = GetTime and GetTime() or time()
        local waitSec = math.max(0.5, DISCOVERY_PING_INTERVAL - (monoNow - (self.lastDiscoveryPingAt or 0)))
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
        local threadKey = linked and linked.key or ("bn:" .. tostring(resolvedId))
        local threadKind = linked and linked.kind or "BN_WHISPER"
        local threadTitle = (linked and linked.kind == "WHISPER" and linked.title) or bnetName
        t = EnsureThread(threadKey, threadKind, threadTitle, {
            bnetAccountID = resolvedId,
            bnetName = bnetName,
            targetName = fullChar or opts.targetName or (linked and linked.targetName),
            classFile = opts.classFile or (charParsed and LookupClassFromCache(charParsed.lookupKey)),
        })
        if gId and self.sessionBNetPeers[gId] and t then
            -- Already known active via BNet session table.
        end
    elseif opts.targetName and opts.targetName ~= "" then
        t = self:EnsureWhisperThread(opts.targetName, opts.classFile)
    end

    if not t then return nil end
    self:SetActiveThread(t.key)
    if opts.autoProbe ~= false and self:ShouldAutoProbe(t.key) then
        self:ProbePeerAddon(t.key, false)
    end
    ns:Emit("CHAT_UPDATED")
    return t.key
end

local function SendDirectPacket(self, t, state, payload)
    local bnetConfirmed = state.bnetGameAccId and self.sessionBNetPeers and self.sessionBNetPeers[state.bnetGameAccId] ~= nil
    local target = state.targetChar or t.targetName
    local extra = (state.rawTargetChar and state.rawTargetChar ~= target) and { state.rawTargetChar } or nil
    local sendOpts = {
        trackCandidateKey = t.key,
        extraCandidates = extra,
        allowBNet = (state.bnetGameAccId ~= nil),
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

    local cleanText = Compat.CleanPayloadField(rawText, 175)
    if cleanText == "" then
        return false
    end

    local monoNow = GetTime and GetTime() or time()
    if (monoNow - (self.lastDirectSendAt or 0)) < DIRECT_SEND_COOLDOWN then
        ns:Print(L["Please wait a moment before sending another message."])
        return false
    end
    self.lastDirectSendAt = monoNow

    local _, _, myFirst = GetMyInfo()
    local senderShort = NonEmptyField(myFirst, 24, myFirst)
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

    local _, myClass = Safe.Call(UnitClass, "player")
    local entry = AppendMessage(t, senderShort, cleanText, false, Safe.String(myClass), t.kind == "BN_WHISPER", true, {
        viaAddon = true,
        deliveryMsgId = msgId,
        deliveryState = "sent",
    })
    TrackDeliveryEntry(self, msgId, t.key, entry)
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

    local _, _, myFirst = GetMyInfo()
    local senderShort = NonEmptyField(myFirst, 24, myFirst)
    local msgId = NextMsgId()
    local payload = string.format("DPIN|%s|%s|%s|%d|%d", msgId, senderShort, zone, px, py)

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
        deliveryMsgId = msgId,
        deliveryState = "sent",
    })
    TrackDeliveryEntry(self, msgId, t.key, entry)
    return true
end

function Chat:SendOrOpenReply(threadKey, rawText)
    if not threadKey then return false end
    if threadKey == "ch:alliance" then
        return self:SendAllianceMessage(rawText)
    end
    if threadKey:sub(1, 5) == "room:" then
        return self:SendRoomMessage(threadKey:sub(6), rawText)
    end

    local t = self.threads[threadKey]
    if not t then return false end

    if (t.kind == "WHISPER" or t.kind == "BN_WHISPER") and self:IsPeerVerified(threadKey) then
        return self:SendDirectMessage(threadKey, rawText)
    end

    return self:OpenOfficialChatForThread(threadKey, rawText)
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

local function EnsureIncomingDirectThread(senderRaw, bnGameAccId)
    if bnGameAccId then
        local bnetAccId, accountName, fullChar = ResolveBNetSender(bnGameAccId)
        if bnetAccId then
            local charParsed = fullChar and Compat.ParseCharacterName(fullChar)
            local cls = charParsed and LookupClassFromCache(charParsed.lookupKey)
            local linked = FindLinkedDirectThread(charParsed, bnetAccId)
            local key = linked and linked.key or ("bn:" .. tostring(bnetAccId))
            local kind = linked and linked.kind or "BN_WHISPER"
            local title = (linked and linked.kind == "WHISPER" and linked.title) or accountName or fullChar or ("BNet #" .. tostring(bnetAccId))
            return EnsureThread(key, kind, title, {
                bnetAccountID = bnetAccId,
                bnetName = accountName,
                targetName = fullChar or (linked and linked.targetName),
                classFile = cls,
            }), charParsed
        end
    end

    local parsedSender = senderRaw and Compat.ParseCharacterName(Safe.String(senderRaw) or "")
    if parsedSender and not Compat.IsMe(parsedSender.displayName) then
        local active = Chat.activeThreadKey and Chat.threads[Chat.activeThreadKey]
        if active and (active.kind == "WHISPER" or active.kind == "BN_WHISPER") then
            local actParsed = Compat.ParseCharacterName(active.targetName or (active.kind == "WHISPER" and active.title) or "")
            if actParsed and (actParsed.lookupKey == parsedSender.lookupKey or ((not parsedSender.surname) and actParsed.firstName:lower() == parsedSender.firstName:lower())) then
                return active, actParsed
            end
        end
        local _, _, bnAccName, bnAccId = FindBNetWoWGameAccountByChar(parsedSender)
        local linked = FindLinkedDirectThread(parsedSender, bnAccId)
        if linked then
            local cls = LookupClassFromCache(parsedSender.lookupKey)
            return EnsureThread(linked.key, linked.kind, linked.title, {
                targetName = parsedSender.displayName,
                bnetAccountID = bnAccId or linked.bnetAccountID,
                bnetName = bnAccName or linked.bnetName,
                classFile = cls,
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
                local nackPayload = "DMA|" .. mId .. "|0|off"
                SendRoomPacket(cleanSenderStr or (parsedSender and parsedSender.displayName), bnGameAccId, nackPayload)
            end
            return
        end
        Chat:MarkPeerVerified(cleanSenderStr or (parsedSender and parsedSender.displayName) or senderRaw, bnGameAccId, nil, op)
        local t, charParsed = EnsureIncomingDirectThread(senderRaw, bnGameAccId)
        if not t then return end

        local msgId, displaySender, formattedMsg
        if op == "DM" then
            local _, mId, senderShort, msgText = strsplit("|", payload, 4)
            msgId = CleanRoomToken(mId)
            msgText = Compat.CleanPayloadField(msgText, 180)
            if msgText == "" then return end
            displaySender = NonEmptyField(senderShort, 24, (charParsed and charParsed.firstName) or t.title or "?")
            formattedMsg = msgText
        else
            local _, mId, senderShort, zoneRaw, pxRaw, pyRaw = strsplit("|", payload, 6)
            msgId = CleanRoomToken(mId)
            local zone = NonEmptyField(zoneRaw, 48, "Azeroth")
            local px = tonumber(pxRaw) or 0
            local py = tonumber(pyRaw) or 0
            displaySender = NonEmptyField(senderShort, 24, (charParsed and charParsed.firstName) or t.title or "?")
            local coordStr = (px > 0 or py > 0) and string.format("%s (%d, %d)", zone, px, py) or zone
            formattedMsg = string.format(L["[Location: %s]"], coordStr)
        end

        local dedupSender = (parsedSender and parsedSender.lookupKey) or tostring(bnGameAccId or t.key)
        local isDup = IsDuplicateDirectMsg(dedupSender, msgId)
        if not isDup then
            local cls = (charParsed and LookupClassFromCache(charParsed.lookupKey)) or t.classFile
            local skipPersist = (t.kind == "BN_WHISPER")
            AppendMessage(t, displaySender, formattedMsg, true, cls, skipPersist, false, {
                viaAddon = true,
                deliveryMsgId = msgId,
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
            Chat.roomBNetTargets[roomId][bnGameAccId] = (hostParsed and hostParsed.firstName) or "Host"
        end
        PlayIncomingChime("ROOM", "room:" .. roomId)
        local hostDisp = (hostParsed and hostParsed.displayName) or (hostParsed and hostParsed.firstName) or "Friend"
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
            if CountTable(room.members) < MAX_ROOM_MEMBERS then
                room.members[memParsed.lookupKey] = memParsed.displayName
            end
            if bnGameAccId then
                Chat.roomBNetTargets[roomId] = Chat.roomBNetTargets[roomId] or {}
                Chat.roomBNetTargets[roomId][bnGameAccId] = memParsed.firstName or memParsed.displayName
            end
            local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
            AppendMessage(t, L["System"], string.format(L["%s joined the room."], memParsed.displayName), true, nil, true, true)
        else
            room.members[memParsed.lookupKey] = nil
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

        room.members[memParsed.lookupKey] = nil
        if bnGameAccId and Chat.roomBNetTargets[roomId] then
            Chat.roomBNetTargets[roomId][bnGameAccId] = nil
        end
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

        local displaySender = NonEmptyField(senderShort, 24, (parsedSender and parsedSender.firstName) or "?")
        if parsedSender and CountTable(room.members) < MAX_ROOM_MEMBERS then
            room.members[parsedSender.lookupKey] = parsedSender.displayName
        end
        if bnGameAccId then
            Chat.roomBNetTargets[roomId] = Chat.roomBNetTargets[roomId] or {}
            Chat.roomBNetTargets[roomId][bnGameAccId] = displaySender
        end
        local classFile = parsedSender and LookupClassFromCache(parsedSender.lookupKey)
        local t = EnsureThread("room:" .. roomId, "ROOM", room.title or roomId, { roomId = roomId })
        AppendMessage(t, displaySender, msgText, true, classFile, true, false, {
            viaAddon = true,
            notifyKind = "ROOM",
        })
    end
end

local function OnChatEvent(event, textRaw, authorRaw, ...)
    if Safe.IsSecret(textRaw) or Safe.IsSecret(authorRaw) then
        return
    end
    local text = Safe.String(textRaw)
    if not text or text == "" then return end

    local incoming = not (event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM")
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        if not parsed then return end
        local guid = Safe.String(select(10, ...))
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
        local _, _, bnAccName, bnAccId = FindBNetWoWGameAccountByChar(parsed, guid)
        local linked = FindLinkedDirectThread(parsed, bnAccId)
        local key = linked and linked.key or ("w:" .. parsed.lookupKey)
        local kind = linked and linked.kind or "WHISPER"
        local title = (linked and linked.title and linked.title ~= "" and linked.title) or parsed.displayName
        local cls = LookupClassFromCache(parsed.lookupKey, guid)
        local t = EnsureThread(key, kind, title, {
            targetName = parsed.displayName,
            bnetAccountID = bnAccId or (linked and linked.bnetAccountID),
            bnetName = bnAccName or (linked and linked.bnetName),
            classFile = cls,
        })
        local _, _, myFirst = GetMyInfo()
        local senderLabel = incoming and parsed.firstName or (myFirst or L["Me"])
        AppendMessage(t, senderLabel, text, incoming, incoming and cls or nil, (kind ~= "WHISPER"), not incoming)
        if incoming and not Compat.IsMe(parsed.displayName) and Chat:IsDirectChatEnabled() then
            Chat:QueuePoliteDiscoveryPing({
                targetName = parsed.displayName,
                lookupKey = parsed.lookupKey,
                bnetAccountID = bnAccId,
                guid = guid,
                allowWhisperReply = true,
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
        local linked = FindLinkedDirectThread(charParsed, resolvedBNetId)
        local key = linked and linked.key or ("bn:" .. tostring(resolvedBNetId or author:lower()))
        local kind = linked and linked.kind or "BN_WHISPER"
        local title = (linked and linked.kind == "WHISPER" and linked.title) or author
        local cls = charParsed and LookupClassFromCache(charParsed.lookupKey)
        local t = EnsureThread(key, kind, title, {
            bnetAccountID = resolvedBNetId,
            bnetName = author,
            targetName = fullChar or (linked and linked.targetName),
            classFile = cls,
        })
        local _, _, myFirst = GetMyInfo()
        local useCharLabel = (kind == "WHISPER" and charParsed ~= nil)
        local senderLabel = incoming and (useCharLabel and charParsed.firstName or author) or (myFirst or L["Me"])
        local skipPersist = not useCharLabel
        AppendMessage(t, senderLabel, text, incoming, useCharLabel and cls or nil, skipPersist, not incoming)
        return
    end

    local chKey, chKind
    if event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        chKey, chKind = "ch:party", "PARTY"
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        chKey, chKind = "ch:raid", "RAID"
    elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        chKey, chKind = "ch:instance", "INSTANCE_CHAT"
    elseif event == "CHAT_MSG_GUILD" then
        chKey, chKind = "ch:guild", "GUILD"
    elseif event == "CHAT_MSG_OFFICER" then
        chKey, chKind = "ch:officer", "OFFICER"
    end

    if chKey then
        if not (ns.db and ns.db.settings and ns.db.settings.chatMirrorChannels == true) then
            return
        end
        local author = Safe.String(authorRaw)
        local parsed = author and Compat.ParseCharacterName(author)
        local isMe = parsed and Compat.IsMe(parsed.displayName)
        local meta = STATIC_CHANNEL_ORDER[chKey]
        local t = EnsureThread(chKey, chKind, L[meta.titleKey], { slash = meta.slash })
        local cls = parsed and LookupClassFromCache(parsed.lookupKey)
        AppendMessage(t, (parsed and parsed.firstName) or author or "?", text, not isMe, cls, true, isMe == true)
    end
end

function Chat:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end
    self:LoadSavedHistory()

    for chKey, meta in pairs(STATIC_CHANNEL_ORDER) do
        EnsureThread(chKey, meta.kind, L[meta.titleKey], { slash = meta.slash })
    end

    for _, ev in ipairs({
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
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
        end)
    end

    for _, ev in ipairs({
        "FRIENDLIST_UPDATE",
        "GUILD_ROSTER_UPDATE",
    }) do
        ns.RegisterEvent(self, ev, function()
            self:BumpPeerStateGen()
        end)
    end

    if not ERR_NOT_FOUND_PATTERN and _G.ERR_CHAT_PLAYER_NOT_FOUND_S then
        ERR_NOT_FOUND_PATTERN = "^" .. _G.ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".*")
    end

    -- Disqualify Forever WHISPER candidate strings that the server explicitly reports as not playing.
    ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", function(_, _, msgRaw)
        if Safe.IsSecret(msgRaw) then return end
        local monoNow = GetTime and GetTime() or 0
        if (monoNow - (Chat._lastCandidateTrackAt or 0)) > 10 then return end

        local msg = Safe.String(msgRaw)
        if not msg or msg == "" then return end
        local lowerMsg = msg:lower()
        local looksNotFound = (ERR_NOT_FOUND_PATTERN and msg:find(ERR_NOT_FOUND_PATTERN))
            or lowerMsg:find("not currently playing", 1, true)
            or lowerMsg:find("no player named", 1, true)
            or lowerMsg:find("nenhum jogador", 1, true)
            or lowerMsg:find("ningún jugador", 1, true)
            or lowerMsg:find("ningun jugador", 1, true)
        if not looksNotFound then return end

        local function rejectCand(cand, lookupKey)
            if not cand or cand == "" then return false end
            local matched = msg:find(cand, 1, true)
            if not matched and cand:find("-", 1, true) then
                matched = msg:find((cand:gsub("%-", " ")), 1, true)
            end
            if not matched then
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
