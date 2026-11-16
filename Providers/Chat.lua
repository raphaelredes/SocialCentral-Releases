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
local PEER_TTL_SECONDS = 30 * 86400
local MAX_SAVED_PEERS = 200

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
end

function Chat:GetUnreadSummary()
    local s = ns.db and ns.db.settings
    local mirrorOn = s and s.chatMirrorChannels == true
    local allowChanUnread = s and s.chatChannelUnread == true
    local direct, roomsUnread, invites, channels = 0, 0, 0, 0
    local senders = {}

    for key, t in pairs(self.threads) do
        local u = t.unread or 0
        if u > 0 and not self:IsThreadMuted(key) then
            if IsPublicChannelKind(t.kind) then
                if mirrorOn and allowChanUnread then
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
    return {
        direct = direct,
        rooms = roomsUnread,
        invites = invites,
        channels = channels,
        totalDirect = totalDirect,
        total = totalDirect + channels,
        senders = senders,
    }
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
    return CountUnreadThreadsAndInvites(self, false)
end

function Chat:GetTotalUnread(includeChannels)
    return CountUnreadThreadsAndInvites(self, includeChannels == true)
end

function Chat:MarkThreadRead(threadKey)
    local t = threadKey and self.threads[threadKey]
    if t and (t.unread or 0) > 0 then
        t.unread = 0
        ns:Emit("CHAT_UPDATED")
    end
end

function Chat:SetActiveThread(threadKey)
    self.activeThreadKey = threadKey
    if threadKey then
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
            if kindFilter == "whispers" then
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
            table.insert(out, {
                key = t.key,
                kind = t.kind,
                title = STATIC_CHANNEL_ORDER[t.key] and L[STATIC_CHANNEL_ORDER[t.key].titleKey] or t.title,
                targetName = t.targetName,
                bnetAccountID = t.bnetAccountID,
                bnetName = t.bnetName,
                classFile = t.classFile,
                roomId = t.roomId,
                unread = isMuted and 0 or (t.unread or 0),
                muted = isMuted,
                lastAt = t.lastAt or 0,
                preview = lastMsg and lastMsg.text or "",
                count = t.messages and #t.messages or 0,
            })
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

function Chat:EnsureWhisperThread(rawTarget, classFile)
    local parsed = Compat.ParseCharacterName(rawTarget)
    if not parsed then return nil end
    local key = "w:" .. parsed.lookupKey
    local t = EnsureThread(key, "WHISPER", parsed.displayName, {
        targetName = parsed.displayName,
        classFile = classFile or LookupClassFromCache(parsed.lookupKey),
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
    local clean = Compat.CleanInput(rawSender)
    if not clean or clean == "" then return end
    Chat.resolvedWhisperTargets = Chat.resolvedWhisperTargets or {}
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

local function BuildOrderedWhisperCandidates(targetChar, candidateOffset)
    local parsed = Compat.ParseCharacterName(targetChar)
    local ordered, seen = {}, {}
    local monoNow = GetTime and GetTime() or 0
    local rejected = Chat.rejectedWhisperTargets

    local function pushUnique(v)
        if type(v) ~= "string" or v == "" or seen[v] then return end
        seen[v] = true
        local exp = rejected and rejected[v]
        if exp and monoNow < exp then
            return
        end
        ordered[#ordered + 1] = v
    end

    local resolved = parsed and Chat.resolvedWhisperTargets and Chat.resolvedWhisperTargets[parsed.lookupKey]
    if resolved then
        pushUnique(resolved)
    end

    local baseCandidates = Compat.BuildForeverTargetCandidates(targetChar)
    if #baseCandidates == 0 then
        baseCandidates = { targetChar }
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

-- Helper to send a bounded SCentral1 addon payload over WHISPER / BNet GameData.
local function SendRoomPacket(targetChar, bnetGameAccId, payload, candidateOffset)
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

    if bnetGameAccId and C_BattleNet and C_BattleNet.SendGameData then
        local ok, res = pcall(C_BattleNet.SendGameData, bnetGameAccId, PREFIX, payload)
        if ok then
            if Enum and Enum.SendAddonMessageResult and type(res) == "number" and res ~= Enum.SendAddonMessageResult.Success then
                if res == Enum.SendAddonMessageResult.AddonMessageThrottle then
                    RecordThrottleStrike()
                end
            else
                return true
            end
        end
    end

    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if targetChar and targetChar ~= "" and sendFn then
        local candidates = BuildOrderedWhisperCandidates(targetChar, candidateOffset)
        local lastErr = "failed"
        for _, candidate in ipairs(candidates) do
            local ok, res = pcall(sendFn, PREFIX, payload, "WHISPER", candidate)
            if ok then
                if Enum and Enum.SendAddonMessageResult and type(res) == "number" then
                    if res == Enum.SendAddonMessageResult.Success then
                        return true, candidate
                    elseif res == Enum.SendAddonMessageResult.AddonMessageThrottle then
                        RecordThrottleStrike()
                        return false, "throttled"
                    elseif Enum.SendAddonMessageResult.AddonsRestricted and res == Enum.SendAddonMessageResult.AddonsRestricted then
                        lastErr = "restricted"
                    else
                        lastErr = "failed"
                    end
                elseif res ~= false then
                    return true, candidate
                end
            end
        end
        return false, lastErr
    end

    return false, "failed"
end

local function FindBNetWoWGameAccount(idOrGameId)
    if not idOrGameId or not (C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendNumGameAccounts) then
        return nil
    end
    local num = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    for i = 1, num do
        local acc = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        if acc then
            local accId = Safe.Number(acc.bnetAccountID)
            local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, i)) or 0
            for g = 1, gCount do
                local gi = Safe.Call(C_BattleNet.GetFriendGameAccountInfo, i, g)
                local gId = gi and Safe.Number(gi.gameAccountID)
                if gi and (accId == idOrGameId or gId == idOrGameId) and Safe.Value(gi.isOnline) and gi.clientProgram == BNET_CLIENT_WOW then
                    local charName = Safe.String(gi.characterName)
                    local realmName = Safe.String(gi.realmName)
                    local fullChar = (charName and realmName and realmName ~= "") and (charName .. "-" .. realmName) or charName
                    return gId, fullChar, Safe.String(acc.accountName), accId
                end
            end
        end
    end
    return nil
end

-- Locate an online Battle.net WoW friend matching an exact GUID or full Forever character lookupKey.
local function FindBNetWoWGameAccountByChar(parsed, guidHint)
    if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendNumGameAccounts) then
        return nil
    end
    if not parsed and not guidHint then return nil end
    local wantLookup = parsed and parsed.lookupKey or nil
    local num = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    for i = 1, num do
        local acc = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        if acc then
            local accId = Safe.Number(acc.bnetAccountID)
            local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, i)) or 0
            for g = 1, gCount do
                local gi = Safe.Call(C_BattleNet.GetFriendGameAccountInfo, i, g)
                if gi and Safe.Value(gi.isOnline) and gi.clientProgram == BNET_CLIENT_WOW then
                    local gId = Safe.Number(gi.gameAccountID)
                    local gGuid = Safe.String(gi.playerGuid)
                    local charName = Safe.String(gi.characterName)
                    local charParsed = charName and Compat.ParseCharacterName(charName)
                    local guidMatch = (guidHint and gGuid and gGuid == guidHint)
                    local nameMatch = (wantLookup and charParsed and charParsed.lookupKey == wantLookup)
                    if gId and (guidMatch or nameMatch) then
                        local realmName = Safe.String(gi.realmName)
                        local fullChar = (charName and realmName and realmName ~= "") and (charName .. "-" .. realmName) or charName
                        return gId, fullChar, Safe.String(acc.accountName), accId
                    end
                end
            end
        end
    end
    return nil
end

local function ResolveBNetSender(bnGameAccId)
    if not bnGameAccId or not (C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendNumGameAccounts) then
        return nil
    end
    local num = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    for i = 1, num do
        local acc = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        if acc then
            local accId = Safe.Number(acc.bnetAccountID)
            local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, i)) or 0
            for g = 1, gCount do
                local gi = Safe.Call(C_BattleNet.GetFriendGameAccountInfo, i, g)
                local gId = gi and Safe.Number(gi.gameAccountID)
                if gi and (gId == bnGameAccId or accId == bnGameAccId) then
                    local charName = Safe.String(gi.characterName)
                    local realmName = Safe.String(gi.realmName)
                    local fullChar = (charName and realmName and realmName ~= "") and (charName .. "-" .. realmName) or charName
                    return accId, Safe.String(acc.accountName), fullChar
                end
            end
        end
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
        for k, seenAt in pairs(self.seenAllianceMsgs) do
            if (nowTs - (seenAt or 0)) > 120 then
                self.seenAllianceMsgs[k] = nil
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
        local reconciledDisplay = {}
        local isDirectAddonPacket = (sourceTag == "DPING" or sourceTag == "DPONG" or sourceTag == "DM" or sourceTag == "DMA" or sourceTag == "DPIN" or sourceTag == "RM" or sourceTag == "RMI" or sourceTag == "RMJ" or sourceTag == "RML")
        if isDirectAddonPacket then
            RecordResolvedWhisperTarget(parsed.lookupKey, targetChar)
        end

        -- Reconcile Forever "FirstName" addon replies against open/recently probed "FirstName Surname" threads.
        if not parsed.surname then
            local firstLower = parsed.firstName:lower()
            for tKey, t in pairs(self.threads) do
                if type(t) == "table" and t.kind == "WHISPER" then
                    local tParsed = Compat.ParseCharacterName(t.targetName or t.title or "")
                    if tParsed and tParsed.lookupKey ~= parsed.lookupKey and tParsed.firstName:lower() == firstLower then
                        local recentProbe = self.probeSentAt and self.probeSentAt[tKey] and ((monoNow - self.probeSentAt[tKey]) <= 25)
                        if (self.pendingProbes and self.pendingProbes[tKey]) or (self.pendingOfficialOpen and self.pendingOfficialOpen[tKey]) or self.activeThreadKey == tKey or recentProbe then
                            keysToUpdate[#keysToUpdate + 1] = tParsed.lookupKey
                            reconciledDisplay[tParsed.lookupKey] = tParsed.displayName
                            if isDirectAddonPacket then
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
    ns:Emit("CHAT_UPDATED")
end

function Chat:GetPeerAddonState(threadKey)
    local t = threadKey and self.threads[threadKey]
    if not t then
        return { state = "none", verified = false }
    end
    if t.kind == "ROOM" then
        return { state = "room", verified = true }
    end
    if t.kind == "ALLIANCE" then
        return { state = "alliance", verified = true, slash = "/al " }
    end
    if IsPublicChannelKind(t.kind) then
        local meta = STATIC_CHANNEL_ORDER[threadKey]
        return { state = "channel", verified = false, slash = meta and meta.slash or t.slash }
    end

    if not self:IsDirectChatEnabled() then
        return { state = "disabled", verified = false }
    end

    local bnetGameAccId, bnetChar
    if t.kind == "BN_WHISPER" and t.bnetAccountID then
        bnetGameAccId, bnetChar = FindBNetWoWGameAccount(t.bnetAccountID)
        if bnetChar then
            t.targetName = bnetChar
        end
    end

    local parsed = Compat.ParseCharacterName(bnetChar or t.targetName or (t.kind == "WHISPER" and t.title or ""))
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
    local savedPeers = GetAddonPeersScopeTable()
    local prevSaved = parsed and savedPeers and savedPeers[parsed.lookupKey]
    local online = IsCharacterOnlineOrReachable(parsed, t.kind == "BN_WHISPER" and t.bnetAccountID or nil)

    if not online then
        return {
            state = "offline",
            verified = false,
            knownAddon = (sess ~= nil or bnSess ~= nil or prevSaved ~= nil),
            version = (sess and sess.version) or (bnSess and bnSess.version) or (prevSaved and prevSaved.version),
            targetChar = parsed and parsed.displayName or t.targetName,
            bnetGameAccId = bnetGameAccId,
        }
    end

    if sess or bnSess then
        return {
            state = "verified",
            verified = true,
            version = (bnSess and bnSess.version) or (sess and sess.version) or "SC",
            verifiedAt = (bnSess and bnSess.verifiedAt) or (sess and sess.verifiedAt),
            source = (bnSess and bnSess.source) or (sess and sess.source),
            knownAddon = true,
            targetChar = parsed and parsed.displayName or t.targetName,
            bnetGameAccId = bnetGameAccId,
        }
    end

    local probeKey = t.key
    local monoNow = GetTime and GetTime() or time()
    local pendingAt = self.pendingProbes and self.pendingProbes[probeKey]
    if pendingAt and (monoNow - pendingAt) < PING_TIMEOUT then
        return {
            state = "checking",
            verified = false,
            knownAddon = prevSaved ~= nil,
            version = prevSaved and prevSaved.version or nil,
            targetChar = parsed and parsed.displayName or t.targetName,
            bnetGameAccId = bnetGameAccId,
        }
    end

    local failInfo = self.probeFailures and self.probeFailures[probeKey]
    if failInfo then
        return {
            state = "unverified",
            verified = false,
            knownAddon = prevSaved ~= nil,
            version = prevSaved and prevSaved.version or nil,
            reason = failInfo,
            targetChar = parsed and parsed.displayName or t.targetName,
            bnetGameAccId = bnetGameAccId,
        }
    end

    return {
        state = "unprobed",
        verified = false,
        knownAddon = prevSaved ~= nil,
        version = prevSaved and prevSaved.version or nil,
        targetChar = parsed and parsed.displayName or t.targetName,
        bnetGameAccId = bnetGameAccId,
    }
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
    local savedPeers = GetAddonPeersScopeTable()
    local rec = savedPeers and savedPeers[lookupKey]
    if type(rec) == "table" and (time() - (rec.lastSeenAt or 0)) <= (14 * 86400) then
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
    if state.verified then
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
    local sent, errOrCand
    if t.kind == "BN_WHISPER" and state.bnetGameAccId then
        sent, errOrCand = SendRoomPacket(nil, state.bnetGameAccId, payload, attemptOffset)
        if not sent and state.targetChar then
            sent, errOrCand = SendRoomPacket(state.targetChar, nil, payload, attemptOffset)
        end
    else
        sent, errOrCand = SendRoomPacket(state.targetChar or t.targetName, state.bnetGameAccId, payload, attemptOffset)
    end

    PruneProbeTracking(self, monoNow)
    self.probeSentAt[threadKey] = monoNow
    if not sent then
        local err = errOrCand or "failed"
        self.probeFailures[threadKey] = err
        self.pendingProbes[threadKey] = nil
        if force then
            if err == "throttled" then
                ns:Print(L["Addon messaging was throttled briefly; please try again in a few seconds."])
            elseif err == "restricted" then
                ns:Print(L["The game server blocked this addon verification packet."])
            else
                ns:Print(L["Could not send verification packet to %s right now."]:format(state.targetChar or t.targetName or "?"))
            end
        end
        ns:Emit("CHAT_UPDATED")
        return false, err
    end

    -- Advance candidate offset for the next manual retry in case this Forever format gets dropped.
    self.probeAttemptIndex[threadKey] = attemptOffset + 1
    if type(errOrCand) == "string" and errOrCand ~= "" then
        self.lastProbeCandidate[threadKey] = { candidate = errOrCand, at = monoNow }
    end
    self.probeFailures[threadKey] = nil
    self.pendingProbes[threadKey] = monoNow

    -- Pure UI timeout expiry only (never sends addon packets from a timer).
    if C_Timer and C_Timer.After then
        local expectedSentAt = monoNow
        C_Timer.After(PING_TIMEOUT + 0.1, function()
            if Chat.pendingProbes and Chat.pendingProbes[threadKey] == expectedSentAt then
                Chat.pendingProbes[threadKey] = nil
                local afterState = Chat:GetPeerAddonState(threadKey)
                if not afterState.verified then
                    Chat.probeFailures = Chat.probeFailures or {}
                    Chat.probeFailures[threadKey] = "timeout"
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
    if st.state == "unprobed" then
        return true
    end
    if st.state == "unverified" then
        local monoNow = GetTime and GetTime() or time()
        local lastSent = (self.probeSentAt and self.probeSentAt[threadKey]) or 0
        return (monoNow - lastSent) >= 15
    end
    return false
end

function Chat:VerifyBeforeOfficialSend(threadKey)
    local t = threadKey and self.threads[threadKey]
    if not t then return false end

    self.pendingOfficialOpen = self.pendingOfficialOpen or {}
    if STATIC_CHANNEL_ORDER[threadKey] or (t.kind ~= "WHISPER" and t.kind ~= "BN_WHISPER") or not self:IsDirectChatEnabled() then
        self.pendingOfficialOpen[threadKey] = nil
        return self:OpenOfficialChatForThread(threadKey)
    end

    local st = self:GetPeerAddonState(threadKey)
    if st.verified then
        self.pendingOfficialOpen[threadKey] = nil
        ns:Emit("CHAT_UPDATED")
        return true
    end

    if st.state == "offline" then
        self.pendingOfficialOpen[threadKey] = nil
        return self:OpenOfficialChatForThread(threadKey)
    end

    local monoNow = GetTime and GetTime() or time()
    local lastSent = (self.probeSentAt and self.probeSentAt[threadKey]) or 0
    if st.state == "checking" or (st.state == "unverified" and (monoNow - lastSent) < 15) then
        self.pendingOfficialOpen[threadKey] = nil
        ns:Emit("CHAT_UPDATED")
        return self:OpenOfficialChatForThread(threadKey)
    end

    local ok, status = self:ProbePeerAddon(threadKey, true)
    if ok and status == "verified" then
        self.pendingOfficialOpen[threadKey] = nil
        ns:Emit("CHAT_UPDATED")
        return true
    end

    if ok then
        local sentAt = (self.probeSentAt and self.probeSentAt[threadKey]) or monoNow
        self.pendingOfficialOpen[threadKey] = sentAt
        ns:Emit("CHAT_UPDATED")
        if C_Timer and C_Timer.After then
            C_Timer.After(1.5, function()
                if Chat.pendingOfficialOpen and Chat.pendingOfficialOpen[threadKey] == sentAt then
                    Chat.pendingOfficialOpen[threadKey] = nil
                    if not Chat:IsPeerVerified(threadKey) then
                        ns:Emit("CHAT_UPDATED")
                        if not (InCombatLockdown and InCombatLockdown()) then
                            Chat:OpenOfficialChatForThread(threadKey)
                        end
                    end
                end
            end)
        end
        return true
    end

    if status ~= "combat" and status ~= "lockdown" then
        return self:OpenOfficialChatForThread(threadKey)
    end
    return false
end

function Chat:OpenDirectConversation(opts)
    if type(opts) ~= "table" then return nil end
    local t
    if opts.bnetAccountID then
        local bnetId = Safe.Number(opts.bnetAccountID)
        local gId, fullChar, accName, canonId = FindBNetWoWGameAccount(bnetId)
        local resolvedId = canonId or bnetId
        local bnetName = Safe.String(opts.bnetName) or accName or ("BNet #" .. tostring(resolvedId))
        t = EnsureThread("bn:" .. tostring(resolvedId), "BN_WHISPER", bnetName, {
            bnetAccountID = resolvedId,
            bnetName = bnetName,
            targetName = fullChar or opts.targetName,
            classFile = opts.classFile,
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

    local sent
    if t.kind == "BN_WHISPER" and state.bnetGameAccId then
        sent = SendRoomPacket(nil, state.bnetGameAccId, payload)
        if not sent and state.targetChar then
            sent = SendRoomPacket(state.targetChar, nil, payload)
        end
    else
        sent = SendRoomPacket(state.targetChar or t.targetName, state.bnetGameAccId, payload)
    end

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

    local sent
    if t.kind == "BN_WHISPER" and state.bnetGameAccId then
        sent = SendRoomPacket(nil, state.bnetGameAccId, payload)
        if not sent and state.targetChar then
            sent = SendRoomPacket(state.targetChar, nil, payload)
        end
    else
        sent = SendRoomPacket(state.targetChar or t.targetName, state.bnetGameAccId, payload)
    end
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

local function EnsureIncomingDirectThread(senderRaw, bnGameAccId)
    if bnGameAccId then
        local bnetAccId, accountName, fullChar = ResolveBNetSender(bnGameAccId)
        if bnetAccId then
            local charParsed = fullChar and Compat.ParseCharacterName(fullChar)
            local cls = charParsed and LookupClassFromCache(charParsed.lookupKey)
            local title = accountName or fullChar or ("BNet #" .. tostring(bnetAccId))
            return EnsureThread("bn:" .. tostring(bnetAccId), "BN_WHISPER", title, {
                bnetAccountID = bnetAccId,
                bnetName = accountName,
                targetName = fullChar,
                classFile = cls,
            }), charParsed
        end
    end

    local parsedSender = senderRaw and Compat.ParseCharacterName(Safe.String(senderRaw) or "")
    if parsedSender and not Compat.IsMe(parsedSender.displayName) then
        local cls = LookupClassFromCache(parsedSender.lookupKey)
        return EnsureThread("w:" .. parsedSender.lookupKey, "WHISPER", parsedSender.displayName, {
            targetName = parsedSender.displayName,
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

    local cleanSenderStr = senderRaw and Compat.CleanInput(Safe.String(senderRaw) or "")
    local parsedSender = cleanSenderStr and Compat.ParseCharacterName(cleanSenderStr)
    if parsedSender and Compat.IsMe(parsedSender.displayName) then
        return
    end
    if parsedSender and cleanSenderStr then
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
                if bnGameAccId then
                    SendRoomPacket(nil, bnGameAccId, replyPayload)
                elseif parsedSender then
                    SendRoomPacket(cleanSenderStr or parsedSender.displayName, nil, replyPayload)
                end
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
                if bnGameAccId then
                    SendRoomPacket(nil, bnGameAccId, nackPayload)
                elseif parsedSender then
                    SendRoomPacket(cleanSenderStr or parsedSender.displayName, nil, nackPayload)
                end
            end
            return
        end
        Chat:MarkPeerVerified(parsedSender and parsedSender.displayName or senderRaw, bnGameAccId, nil, op)
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

        local cls = (charParsed and LookupClassFromCache(charParsed.lookupKey)) or t.classFile
        local skipPersist = (t.kind == "BN_WHISPER")
        AppendMessage(t, displaySender, formattedMsg, true, cls, skipPersist, false, {
            viaAddon = true,
            deliveryMsgId = msgId,
        })

        if msgId and not (ns.Clan and ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked()) then
            local ackPayload = "DMA|" .. msgId
            if bnGameAccId then
                SendRoomPacket(nil, bnGameAccId, ackPayload)
            elseif parsedSender then
                SendRoomPacket(cleanSenderStr or parsedSender.displayName, nil, ackPayload)
            end
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
        local key = "w:" .. parsed.lookupKey
        local cls = LookupClassFromCache(parsed.lookupKey, guid)
        local t = EnsureThread(key, "WHISPER", parsed.displayName, {
            targetName = parsed.displayName,
            classFile = cls,
        })
        local _, _, myFirst = GetMyInfo()
        local senderLabel = incoming and parsed.firstName or (myFirst or L["Me"])
        AppendMessage(t, senderLabel, text, incoming, incoming and cls or nil, false, not incoming)
        return
    end

    if event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        -- 11th arg after author is presenceID / bnSenderID (13th total arg -> index 11 in varargs).
        local presenceID = Safe.Number(select(11, ...))
        local author = Safe.String(authorRaw) or ("BNet #" .. tostring(presenceID or "?"))
        local _, fullChar = FindBNetWoWGameAccount(presenceID)
        local key = "bn:" .. tostring(presenceID or author:lower())
        local t = EnsureThread(key, "BN_WHISPER", author, {
            bnetAccountID = presenceID,
            bnetName = author,
            targetName = fullChar,
        })
        local _, _, myFirst = GetMyInfo()
        local senderLabel = incoming and author or (myFirst or L["Me"])
        AppendMessage(t, senderLabel, text, incoming, nil, true, not incoming)
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

    -- Disqualify Forever WHISPER candidate strings that the server explicitly reports as not playing.
    ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", function(_, _, msgRaw)
        if Safe.IsSecret(msgRaw) then return end
        local msg = Safe.String(msgRaw)
        if not msg or msg == "" or not Chat.lastProbeCandidate then return end
        local monoNow = GetTime and GetTime() or 0
        for tKey, rec in pairs(Chat.lastProbeCandidate) do
            if type(rec) == "table" and rec.candidate and (monoNow - (rec.at or 0)) <= 4.0 then
                if msg:find(rec.candidate, 1, true) and (_G.ERR_CHAT_PLAYER_NOT_FOUND_S == nil or msg:find("^" .. _G.ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".*")) or msg:lower():find("not currently playing") or msg:lower():find("no player named") or msg:lower():find("nenhum jogador")) then
                    Chat.rejectedWhisperTargets = Chat.rejectedWhisperTargets or {}
                    Chat.rejectedWhisperTargets[rec.candidate] = monoNow + 60
                    Chat.lastProbeCandidate[tKey] = nil
                end
            elseif type(rec) == "table" and (monoNow - (rec.at or 0)) > 10 then
                Chat.lastProbeCandidate[tKey] = nil
            end
        end
    end)

    ns:Emit("CHAT_UPDATED")
end
