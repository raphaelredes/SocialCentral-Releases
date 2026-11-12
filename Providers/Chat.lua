local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Unified Conversations Hub & Addon Private Chat Rooms.
-- Security guarantees:
--   - Respects 16001 / 12.x Secret Values on all chat & addon events.
--   - Never calls SendChatMessage or BNSendWhisper (native replies safely open Blizzard chat prefill).
--   - Never stores BattleTag / Real ID or BN_WHISPER history in SavedVariables.
--   - Addon Private Chat Rooms (SCentral1 RM/RMI/RMJ/RML) obey IsMessagingLocked(), combat guards, and 240B limit.
local Chat = {
    threads = {},
    roomBNetTargets = {},
    lastRoomSendAt = 0,
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

local STATIC_CHANNEL_ORDER = {
    ["ch:party"] = { titleKey = "Party", kind = "PARTY", slash = "/p ", order = 1 },
    ["ch:instance"] = { titleKey = "Instance", kind = "INSTANCE_CHAT", slash = "/i ", order = 2 },
    ["ch:raid"] = { titleKey = "Raid", kind = "RAID", slash = "/ra ", order = 3 },
    ["ch:guild"] = { titleKey = "Guild", kind = "GUILD", slash = "/g ", order = 4 },
    ["ch:officer"] = { titleKey = "Officer", kind = "OFFICER", slash = "/o ", order = 5 },
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
    local raw = Safe.String(Safe.Call(UnitName, "player")) or "Unknown"
    local parsed = Compat.ParseCharacterName(raw)
    if parsed then
        return parsed.displayName, parsed.lookupKey, parsed.firstName
    end
    return raw, raw:lower(), raw
end

local function PlayIncomingChime()
    if not (ns.db and ns.db.settings and ns.db.settings.chatSound) then
        return
    end
    if PlaySound and SOUNDKIT then
        local kit = SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        if kit then
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
        if title and title ~= "" and not t.title then
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
    if type(saved) ~= "table" then
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
end

local function AppendMessage(thread, senderName, text, incoming, classFile, skipPersist, silent)
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
    }
    table.insert(thread.messages, entry)
    while #thread.messages > MAX_THREAD_LINES do
        table.remove(thread.messages, 1)
    end
    thread.lastAt = ts

    local isViewing = Chat.activeThreadKey == thread.key and ns.UI and ns.UI.IsMainVisible and ns.UI:IsMainVisible()
    if incoming and not isViewing then
        thread.unread = (thread.unread or 0) + 1
        if not silent then
            PlayIncomingChime()
        end
    end

    if not skipPersist and thread.kind == "WHISPER" then
        PersistWhisperLine(thread.key, entry)
    end

    ns:Emit("CHAT_UPDATED")
end

local function LookupClassFromCache(lookupKey)
    if not lookupKey then return nil end
    if Store and Store.social then
        local direct = Store.social[lookupKey]
        if direct and direct.classFile then return direct.classFile end
        for _, row in pairs(Store.social) do
            if type(row) == "table" and row.lookupKey == lookupKey and row.classFile then
                return row.classFile
            end
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
    return nil
end

function Chat:LoadSavedHistory()
    local limit = GetChatHistoryLimit()
    local hist = GetHistoryScopeTable()
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

function Chat:GetTotalUnread()
    local total = 0
    for _, t in pairs(self.threads) do
        total = total + (t.unread or 0)
    end
    local rooms = GetRoomsScopeTable()
    if rooms then
        for _, room in pairs(rooms) do
            if type(room) == "table" and room.pendingInvite then
                total = total + 1
            end
        end
    end
    return total
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

    for key, t in pairs(self.threads) do
        local isRoom = key:sub(1, 5) == "room:"
        local include = true
        if isRoom then
            local room = rooms[t.roomId]
            include = room and room.joined == true
        elseif key:sub(1, 3) == "ch:" then
            include = (#(t.messages or {}) > 0)
        end

        if include and kindFilter and kindFilter ~= "all" then
            if kindFilter == "whispers" then
                include = (t.kind == "WHISPER" or t.kind == "BN_WHISPER")
            elseif kindFilter == "rooms" then
                include = (t.kind == "ROOM")
            elseif kindFilter == "channels" then
                include = (t.kind == "PARTY" or t.kind == "RAID" or t.kind == "INSTANCE_CHAT" or t.kind == "GUILD" or t.kind == "OFFICER")
            end
        end

        if include then
            local lastMsg = t.messages and t.messages[#t.messages]
            table.insert(out, {
                key = t.key,
                kind = t.kind,
                title = STATIC_CHANNEL_ORDER[t.key] and L[STATIC_CHANNEL_ORDER[t.key].titleKey] or t.title,
                targetName = t.targetName,
                bnetAccountID = t.bnetAccountID,
                bnetName = t.bnetName,
                classFile = t.classFile,
                roomId = t.roomId,
                unread = t.unread or 0,
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

-- Helper to send a bounded SCentral1 addon payload over WHISPER / GUILD / BNet GameData.
local function SendRoomPacket(targetChar, bnetGameAccId, payload)
    if ns.Clan and ns.Clan.IsMessagingLocked and ns.Clan:IsMessagingLocked() then
        return false, "locked"
    end
    if ns.Clan and ns.Clan.isStoppedThisSession then
        return false, "stopped"
    end
    if not payload or #payload > MAX_PAYLOAD_BYTES then
        return false, "too_long"
    end

    if bnetGameAccId and C_BattleNet and C_BattleNet.SendGameData then
        local ok = pcall(C_BattleNet.SendGameData, bnetGameAccId, PREFIX, payload)
        if ok then return true end
    end

    if targetChar and targetChar ~= "" and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", targetChar)
        if ok then return true end
    end

    return false, "failed"
end

local function FindBNetWoWGameAccount(bnetAccountID)
    if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendNumGameAccounts) then
        return nil
    end
    local num = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    for i = 1, num do
        local acc = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        if acc and Safe.Number(acc.bnetAccountID) == bnetAccountID then
            local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, i)) or 0
            for g = 1, gCount do
                local gi = Safe.Call(C_BattleNet.GetFriendGameAccountInfo, i, g)
                if gi and Safe.Value(gi.isOnline) and gi.clientProgram == BNET_CLIENT_WOW then
                    local gId = Safe.Number(gi.gameAccountID)
                    local charName = Safe.String(gi.characterName)
                    local realmName = Safe.String(gi.realmName)
                    local fullChar = (charName and realmName and realmName ~= "") and (charName .. "-" .. realmName) or charName
                    return gId, fullChar
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
    if ns.Clan and ns.Clan:IsMessagingLocked() then
        ns:Print(L["Messaging is temporarily locked during combat/encounter."])
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
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    if ns.Clan and ns.Clan:IsMessagingLocked() then
        ns:Print(L["Messaging is temporarily locked during combat/encounter."])
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

function Chat:SendOrOpenReply(threadKey, rawText)
    if not threadKey then return false end
    if threadKey:sub(1, 5) == "room:" then
        return self:SendRoomMessage(threadKey:sub(6), rawText)
    end

    local t = self.threads[threadKey]
    if not t then return false end

    local clean = Compat.CleanInput(rawText) or ""
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
        prefix = "/w " .. t.targetName .. " " .. clean
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

local function HandleIncomingAddonRoom(payloadRaw, senderRaw, bnGameAccId)
    local payload = Safe.String(payloadRaw)
    if not payload or payload == "" then return end

    local op = payload:match("^([^|]+)|")
    if not op then return end
    if op ~= "RMI" and op ~= "RMJ" and op ~= "RML" and op ~= "RM" then
        return
    end

    local parsedSender = senderRaw and Compat.ParseCharacterName(Safe.String(senderRaw) or "")
    if parsedSender and Compat.IsMe(parsedSender.displayName) then
        return
    end

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
        PlayIncomingChime()
        ns:Print(string.format(L["Private room invite from %s: %s (open Chat tab to accept)."], (hostParsed and hostParsed.firstName) or "Friend", title))
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
        AppendMessage(t, displaySender, msgText, true, classFile, true, false)
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
        local key = "w:" .. parsed.lookupKey
        local cls = LookupClassFromCache(parsed.lookupKey)
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
        local key = "bn:" .. tostring(presenceID or author:lower())
        local t = EnsureThread(key, "BN_WHISPER", author, {
            bnetAccountID = presenceID,
            bnetName = author,
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
    self:LoadSavedHistory()

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

    ns.RegisterEvent(self, "CHAT_MSG_ADDON", function(_, _, prefix, text, _, sender)
        if Safe.String(prefix) == PREFIX then
            HandleIncomingAddonRoom(text, sender, nil)
        end
    end)

    ns.RegisterEvent(self, "BN_CHAT_MSG_ADDON", function(_, _, prefix, text, _, bnSenderID)
        if Safe.String(prefix) == PREFIX then
            HandleIncomingAddonRoom(text, nil, Safe.Number(bnSenderID))
        end
    end)

    ns:Emit("CHAT_UPDATED")
end
