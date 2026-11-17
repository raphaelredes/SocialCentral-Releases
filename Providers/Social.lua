local _, ns = ...

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Collects live online players (Store.social) plus full online/offline Character & Battle.net
-- directory (Store.socialDirectory) with zero /who throttle cost and zero BattleTag/Real ID storage.
local Social = {}
ns.Social = Social
table.insert(ns.modules, Social)

local LAST_ROSTER_ASK = 0
local ROSTER_MIN_GAP = 30
local FRIEND_ALERT_DEBOUNCE = 120
local FRIEND_LOGIN_GRACE_SEC = 8.0

local scanQueued = false
local lastScanAt = 0
local loginMonoAt = (GetTime and GetTime()) or 0
local reconnectGraceUntil = 0
local hasInitialScan = false

local prevWowOnline = {}
local prevBNetWatchlistOnline = {}
local friendAlertLastAt = {}
local pendingBNetInvites = {}

local presenceScratch = {}

local function QueueWatchlistObs(wlObsMap, lookupKey, displayName, online, level, classFile, area, guildName, source)
    if not wlObsMap or not lookupKey or lookupKey == "" or not displayName or displayName == "" then
        return
    end
    local rec = wlObsMap[lookupKey]
    if not rec then
        wlObsMap[lookupKey] = {
            lookupKey = lookupKey,
            displayName = displayName,
            online = online == true,
            level = (level and level > 0) and level or nil,
            classFile = classFile,
            area = (area and area ~= "") and area or nil,
            guild = (guildName and guildName ~= "") and guildName or nil,
            source = source,
        }
    else
        if online == true then
            rec.online = true
            rec.source = source or rec.source
        end
        if level and level > 0 then rec.level = level end
        if classFile then rec.classFile = classFile end
        if area and area ~= "" then rec.area = area end
        if guildName and guildName ~= "" then rec.guild = guildName end
    end
end

local function TouchPresence(lookupKey, seenNow, area, classFile, level)
    if not lookupKey or lookupKey == "" or not (Store and Store.TouchFriendPresence) then
        return
    end
    presenceScratch.seenNow = seenNow == true
    presenceScratch.area = area
    presenceScratch.classFile = classFile
    presenceScratch.level = level
    presenceScratch.favorite = nil
    Store:TouchFriendPresence(lookupKey, presenceScratch)
end

local function FindMergeKey(ctx, preferredKey, guid, bnetAccountID, lookupKey, allowLookupMerge)
    if guid and ctx.byGuid[guid] then
        return ctx.byGuid[guid]
    end
    if bnetAccountID and ctx.byBNet[bnetAccountID] then
        return ctx.byBNet[bnetAccountID]
    end
    if allowLookupMerge and lookupKey and lookupKey ~= "" and ctx.byLookup[lookupKey] then
        return ctx.byLookup[lookupKey]
    end
    return preferredKey
end

local function MergeEntry(ctx, key, patch)
    local map = ctx.map
    local row = map[key]
    if not row then
        row = {
            key = key,
            sources = {},
        }
        map[key] = row
    end
    for k, v in pairs(patch) do
        if k == "sources" then
            for s in pairs(v) do row.sources[s] = true end
        elseif v ~= nil and v ~= "" then
            row[k] = v
        end
    end

    -- Derive single unified note preview without overwriting separated Guild / Friend / BNet notes.
    row.note = row.friendNote or row.bnetNote or row.guildNote or row.note

    if row.guid and row.guid ~= "" then
        ctx.byGuid[row.guid] = key
    end
    if row.bnetAccountID then
        ctx.byBNet[row.bnetAccountID] = key
    end
    if row.lookupKey and row.lookupKey ~= "" and row.samePool ~= false then
        if not ctx.byLookup[row.lookupKey] then
            ctx.byLookup[row.lookupKey] = key
        end
    end
    return row
end

local function NewScanContext()
    return {
        map = {},
        byGuid = {},
        byBNet = {},
        byLookup = {},
    }
end

local function ScanGuild(onlineCtx, dirCtx, wlObsMap)
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true
    local info = Store.guildInfo
    info.inGuild = inGuild
    local rosterRanks = Store.guildRosterRanks
    if type(rosterRanks) ~= "table" then
        rosterRanks = {}
        Store.guildRosterRanks = rosterRanks
    else
        wipe(rosterRanks)
    end
    if not inGuild or not GetGuildRosterInfo then
        info.name, info.motd, info.onlineCount, info.totalCount = nil, nil, 0, 0
        info.myRankIndex, info.myRankName, info.isGuildLeader = nil, nil, false
        return
    end
    info.isGuildLeader = (IsGuildLeader and Safe.Value(Safe.Call(IsGuildLeader)) == true) or false
    info.myRankIndex = nil
    info.myRankName = nil

    local liveGuildName = Safe.String(Safe.Call(GetGuildInfo, "player"))
    if liveGuildName and liveGuildName ~= "" then
        info.name = liveGuildName
    elseif not info.name or info.name == "" then
        local altRec = ns.db and ns.db.alts and Compat.CharacterKey and ns.db.alts[Compat.CharacterKey()]
        if altRec and altRec.guild and altRec.guild ~= "" then
            info.name = altRec.guild
        end
    end
    info.motd = Safe.String(Safe.Call(GetGuildRosterMOTD)) or ""

    local total = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    info.totalCount = total
    local onlineCount = 0
    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasWatchlist = type(wlTable) == "table" and next(wlTable) ~= nil

    for i = 1, total do
        local okG, name, rankName, rankIndex, level, classLoc, area, note, _, online, status, classFile, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
        if okG then
            name = Safe.String(name)
            guid = Safe.String(guid)
            local cleanRankName = Safe.String(rankName) or ""
            local cleanRankIdx = Safe.Number(rankIndex)
            local cleanLevel = Safe.Number(level) or 0
            local cleanArea = Safe.String(area) or ""
            local cleanNote = Safe.String(note)
            local cleanClass = Safe.String(classFile) or Compat.ClassFileFromLocalized(Safe.String(classLoc))
            local cleanStatus = Safe.Number(status) or 0
            local isOnline = (online == true or online == 1)
            local isMe = name and Compat.IsMe(name, guid)
            local parsed = name and Compat.ParseCharacterName(name) or nil
            if parsed and parsed.lookupKey then
                rosterRanks[parsed.lookupKey] = {
                    rankIndex = cleanRankIdx,
                    rankName = cleanRankName,
                    guid = guid,
                    displayName = parsed.displayName,
                    lookupKey = parsed.lookupKey,
                    level = cleanLevel,
                    classFile = cleanClass,
                    area = cleanArea,
                    note = cleanNote or "",
                    statusFlag = cleanStatus,
                    online = isOnline,
                    isSelf = isMe,
                    rosterIndex = i,
                }
                if isMe then
                    info.myRankIndex = cleanRankIdx
                    info.myRankName = cleanRankName
                    if cleanRankIdx == 0 then
                        info.isGuildLeader = true
                    end
                end
            end
            if parsed and not isMe then
                if guid and Compat.CacheForeverFullName then
                    Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
                end
                if Compat.CacheGuildMember then
                    Compat.CacheGuildMember(guid, parsed.firstName, parsed.displayName)
                end
                if parsed.surname and Store.MigrateSocialSurnameRecords then
                    Store:MigrateSocialSurnameRecords(parsed.firstName, parsed.lookupKey)
                end
                if isOnline then
                    onlineCount = onlineCount + 1
                    local patch = {
                        displayName = parsed.displayName,
                        lookupKey = parsed.lookupKey,
                        guid = guid,
                        level = cleanLevel,
                        classFile = cleanClass,
                        area = cleanArea,
                        guild = info.name,
                        rankName = cleanRankName,
                        rankIndex = cleanRankIdx,
                        guildNote = cleanNote,
                        statusFlag = cleanStatus,
                        afk = cleanStatus == 1,
                        dnd = cleanStatus == 2,
                        online = true,
                        samePool = true,
                        sameFaction = true,
                        bnetState = "wow_forever",
                        sources = { guild = true },
                    }
                    local keyOnline = FindMergeKey(onlineCtx, guid or ("char:" .. parsed.lookupKey), guid, nil, parsed.lookupKey, true)
                    MergeEntry(onlineCtx, keyOnline, patch)
                    local keyDir = FindMergeKey(dirCtx, guid or ("char:" .. parsed.lookupKey), guid, nil, parsed.lookupKey, true)
                    MergeEntry(dirCtx, keyDir, patch)
                    if hasWatchlist and wlObsMap then
                        QueueWatchlistObs(wlObsMap, parsed.lookupKey, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, info.name or "", "guild")
                    end
                elseif hasWatchlist and wlObsMap then
                    QueueWatchlistObs(wlObsMap, parsed.lookupKey, parsed.displayName, false, cleanLevel, cleanClass, cleanArea, info.name or "", "guild")
                end
            elseif isOnline and name then
                onlineCount = onlineCount + 1
            end
        end
    end

    info.onlineCount = onlineCount
end

local function ProcessCharacterFriendRecord(onlineCtx, dirCtx, wlObsMap, hasWatchlist, now, rawName, guid, isOnline, cleanLevel, cleanClass, cleanArea, cleanNote, isAfk, isDnd)
    if not rawName or Compat.IsMe(rawName, guid) then
        return
    end
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed then return end

    if guid and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
    end
    if parsed.surname and Store.MigrateSocialSurnameRecords then
        Store:MigrateSocialSurnameRecords(parsed.firstName, parsed.lookupKey)
    end

    local pres = Store.GetFriendPresence and Store:GetFriendPresence(parsed.lookupKey)
    if isOnline then
        TouchPresence(parsed.lookupKey, true, cleanArea, cleanClass, cleanLevel)
        pres = Store.GetFriendPresence and Store:GetFriendPresence(parsed.lookupKey) or pres
    else
        cleanLevel = (cleanLevel and cleanLevel > 0) and cleanLevel or (pres and pres.lastLevel)
        cleanClass = cleanClass or (pres and pres.lastClass)
        cleanArea = (cleanArea and cleanArea ~= "") and cleanArea or (pres and pres.lastArea) or ""
    end

    local patch = {
        displayName = parsed.displayName,
        lookupKey = parsed.lookupKey,
        guid = guid,
        level = cleanLevel,
        classFile = cleanClass,
        area = cleanArea,
        friendNote = cleanNote,
        afk = isAfk == true,
        dnd = isDnd == true,
        online = isOnline == true,
        samePool = true,
        sameFaction = true,
        bnetState = isOnline and "wow_forever" or "offline",
        lastSeen = isOnline and now or (pres and pres.lastSeen) or nil,
        sources = { friend = true },
    }

    local dirKey = FindMergeKey(dirCtx, guid or ("char:" .. parsed.lookupKey), guid, nil, parsed.lookupKey, true)
    MergeEntry(dirCtx, dirKey, patch)

    if isOnline then
        local onKey = FindMergeKey(onlineCtx, guid or ("char:" .. parsed.lookupKey), guid, nil, parsed.lookupKey, true)
        MergeEntry(onlineCtx, onKey, patch)
    end

    if hasWatchlist and wlObsMap then
        QueueWatchlistObs(wlObsMap, parsed.lookupKey, parsed.displayName, isOnline == true, cleanLevel, cleanClass, cleanArea, nil, "friend")
    end
end

local function ScanCharacterFriends(onlineCtx, dirCtx, wlObsMap)
    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasWatchlist = type(wlTable) == "table" and next(wlTable) ~= nil
    local now = time()

    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local count = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
        for i = 1, count do
            local f = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(f) == "table" then
                local rawName = Safe.String(f.name)
                local guid = Safe.String(f.guid)
                local isOnline = Safe.Value(f.connected) == true
                local cleanClass = Compat.ClassFileFromLocalized(Safe.String(f.className)) or (Compat.ClassFileFromGuid and Compat.ClassFileFromGuid(guid))
                ProcessCharacterFriendRecord(
                    onlineCtx, dirCtx, wlObsMap, hasWatchlist, now,
                    rawName, guid, isOnline,
                    Safe.Number(f.level),
                    cleanClass,
                    Safe.String(f.area) or "",
                    Safe.String(f.notes),
                    Safe.Value(f.afk) == true,
                    Safe.Value(f.dnd) == true
                )
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        local count = Safe.Number(Safe.Call(GetNumFriends)) or 0
        for i = 1, count do
            local okF, rawName, level, classLoc, area, connected, status, notes = pcall(GetFriendInfo, i)
            if okF then
                local cleanStatus = Safe.String(status)
                local isAfk = (cleanStatus == "<AFK>" or (CHAT_FLAG_AFK and cleanStatus == CHAT_FLAG_AFK))
                local isDnd = (cleanStatus == "<DND>" or (CHAT_FLAG_DND and cleanStatus == CHAT_FLAG_DND))
                ProcessCharacterFriendRecord(
                    onlineCtx, dirCtx, wlObsMap, hasWatchlist, now,
                    Safe.String(rawName), nil, (connected == true or connected == 1),
                    Safe.Number(level),
                    Compat.ClassFileFromLocalized(Safe.String(classLoc)),
                    Safe.String(area) or "",
                    Safe.String(notes),
                    isAfk, isDnd
                )
            end
        end
    end
end

local function PickBestBNetGameAccount(friendIndex, account)
    local best, bestScore = nil, -1
    local wowProg = BNET_CLIENT_WOW or "WoW"

    local function consider(gi)
        if type(gi) ~= "table" then return end
        local isOn = Safe.Value(gi.isOnline) == true
        local prog = Safe.String(gi.clientProgram)
        local score = 0
        if isOn then
            if prog == wowProg then
                if not WOW_PROJECT_ID or Safe.Value(gi.wowProjectID) == WOW_PROJECT_ID then
                    score = 100
                else
                    score = 70
                end
            elseif prog and prog ~= "App" and prog ~= "BSAp" then
                score = 45
            else
                score = 25
            end
        elseif prog == wowProg then
            score = 5
        end
        if score > bestScore then
            bestScore = score
            best = gi
        end
    end

    if C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
        local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, friendIndex)) or 0
        for g = 1, gCount do
            consider(Safe.Call(C_BattleNet.GetFriendGameAccountInfo, friendIndex, g))
        end
    end
    if not best and type(account) == "table" and type(account.gameAccountInfo) == "table" then
        consider(account.gameAccountInfo)
    end
    return best
end

local function ScanBattleNet(onlineCtx, dirCtx, wlObsMap, nextBNetWatchlistOnline)
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasWatchlist = type(wlTable) == "table" and next(wlTable) ~= nil
    local wowProg = BNET_CLIENT_WOW or "WoW"
    local now = time()
    local count = Safe.Number(Safe.Call(BNGetNumFriends)) or 0

    for i = 1, count do
        local account = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        if type(account) == "table" then
            local bnetAccId = Safe.Number(account.bnetAccountID)
            local accountName = Safe.String(account.accountName) or Safe.String(account.battleTag) or "Battle.net"
            local bnetNote = Safe.String(account.note)
            local customMsg = Safe.String(account.customMessage)
            local bnetFavorite = Safe.Value(account.isFavorite) == true
            local accAfk = Safe.Value(account.isAFK) == true
            local accDnd = Safe.Value(account.isDND) == true
            local bnetLastOnline = Safe.Number(account.lastOnlineTime)

            local g = PickBestBNetGameAccount(i, account)
            local gOnline = type(g) == "table" and Safe.Value(g.isOnline) == true
            local clientProgram = type(g) == "table" and Safe.String(g.clientProgram) or nil
            local isWoW = clientProgram == wowProg
            local sameProject = isWoW and (not WOW_PROJECT_ID or Safe.Value(g.wowProjectID) == WOW_PROJECT_ID)
            local charName = type(g) == "table" and Safe.String(g.characterName) or nil
            local realmName = type(g) == "table" and Safe.String(g.realmName) or nil
            local guid = type(g) == "table" and Safe.String(g.playerGuid) or nil
            local richPresence = type(g) == "table" and Safe.String(g.richPresence) or nil
            local gameAfk = type(g) == "table" and Safe.Value(g.isGameAFK) == true
            local gameDnd = type(g) == "table" and Safe.Value(g.isGameBusy) == true
            local fallbackId = bnetAccId or (type(g) == "table" and Safe.Number(g.gameAccountID)) or i

            local parsed = (isWoW and charName) and Compat.ParseCharacterName(charName) or nil
            if not (parsed and Compat.IsMe(parsed.displayName, guid)) then
                if parsed and guid and Compat.CacheForeverFullName then
                    Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
                end

                local samePool = sameProject and ((not realmName) or Compat.IsForeverShardLabel(realmName))
                local myEngFaction, myLocFaction = Compat.PlayerFaction()
                local cleanFaction = type(g) == "table" and Safe.String(g.factionName) or nil
                local sameFaction = (not cleanFaction) or cleanFaction == myEngFaction or (myLocFaction ~= nil and cleanFaction == myLocFaction)

                local bnetState = "offline"
                if gOnline then
                    if sameProject and samePool and parsed then
                        bnetState = "wow_forever"
                    elseif isWoW then
                        bnetState = "wow_other"
                    else
                        bnetState = "bnet_app"
                    end
                end

                local cleanClass = parsed and (Compat.ClassFileFromLocalized(Safe.String(g.className)) or (Compat.ClassFileFromGuid and Compat.ClassFileFromGuid(guid))) or nil
                local cleanLevel = parsed and Safe.Number(g.characterLevel) or nil
                local cleanArea = (type(g) == "table" and Safe.String(g.areaName)) or ""
                if cleanArea == "" and richPresence and bnetState ~= "wow_forever" then
                    cleanArea = richPresence
                end

                if bnetState == "wow_forever" and parsed then
                    TouchPresence(parsed.lookupKey, true, cleanArea, cleanClass, cleanLevel)
                    if parsed.surname and Store.MigrateSocialSurnameRecords then
                        Store:MigrateSocialSurnameRecords(parsed.firstName, parsed.lookupKey)
                    end
                end

                local pres = (parsed and Store.GetFriendPresence) and Store:GetFriendPresence(parsed.lookupKey) or nil
                local patch = {
                    displayName = (parsed and parsed.displayName) or accountName,
                    lookupKey = parsed and parsed.lookupKey or nil,
                    hasCharacterName = parsed ~= nil,
                    guid = guid,
                    bnetName = accountName,
                    bnetAccountID = bnetAccId or (type(g) == "table" and Safe.Number(g.gameAccountID)),
                    bnetFavorite = bnetFavorite,
                    bnetNote = bnetNote,
                    customMessage = customMsg,
                    richPresence = richPresence,
                    clientProgram = clientProgram,
                    realmName = realmName,
                    level = cleanLevel,
                    classFile = cleanClass,
                    area = cleanArea,
                    faction = cleanFaction,
                    samePool = parsed and samePool or false,
                    sameFaction = parsed and sameFaction or nil,
                    afk = accAfk or gameAfk,
                    dnd = accDnd or gameDnd,
                    online = gOnline == true,
                    bnetState = bnetState,
                    lastSeen = (gOnline and now) or (bnetLastOnline and bnetLastOnline > 0 and bnetLastOnline) or (pres and pres.lastSeen) or nil,
                    sources = { bnet = true },
                }

                local defaultKey = guid or (bnetAccId and ("bnet:" .. tostring(bnetAccId))) or ("bnet:idx:" .. tostring(fallbackId))
                local dirKey = FindMergeKey(dirCtx, defaultKey, guid, patch.bnetAccountID, patch.lookupKey, samePool and parsed ~= nil)
                MergeEntry(dirCtx, dirKey, patch)

                if bnetState == "wow_forever" and parsed then
                    local onKey = FindMergeKey(onlineCtx, defaultKey, guid, patch.bnetAccountID, parsed.lookupKey, true)
                    MergeEntry(onlineCtx, onKey, patch)
                    if samePool and sameFaction then
                        if nextBNetWatchlistOnline then
                            nextBNetWatchlistOnline[parsed.lookupKey] = parsed.displayName
                        end
                        if hasWatchlist and wlObsMap then
                            QueueWatchlistObs(wlObsMap, parsed.lookupKey, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, nil, "bnet")
                        end
                    end
                end
            end
        end
    end
end

local function GetAlertTargetKey(row)
    if row.lookupKey and row.lookupKey ~= "" then
        return "char:" .. row.lookupKey
    end
    if row.bnetAccountID then
        return "bnet:" .. tostring(row.bnetAccountID)
    end
    return row.key
end

local function CheckFriendOnlineTransitions(dirMap)
    local nextWow = {}
    local isGuildWatchFn = Store and Store.IsGuildLoginNotifyEnabled
    for _, row in pairs(dirMap) do
        local isFriend = row.sources and (row.sources.friend or row.sources.bnet)
        local isOptedGuild = row.sources and row.sources.guild and row.lookupKey and isGuildWatchFn and isGuildWatchFn(Store, row.lookupKey)
        local isWoWOnline = row.online == true and (row.sources.friend or row.sources.guild or row.bnetState == "wow_forever")
        if (isFriend or isOptedGuild) and isWoWOnline then
            local aKey = GetAlertTargetKey(row)
            if aKey then
                nextWow[aKey] = true
            end
        end
    end

    local monoNow = (GetTime and GetTime()) or 0
    local settings = ns.db and ns.db.settings
    local alertMode = settings and settings.friendOnlineAlertMode or "all"
    local inGrace = (not hasInitialScan) or ((monoNow - loginMonoAt) < FRIEND_LOGIN_GRACE_SEC) or (monoNow < reconnectGraceUntil)
    local notifiedByLookup = {}

    if inGrace or alertMode == "off" then
        prevWowOnline = nextWow
        return notifiedByLookup, inGrace
    end

    local now = time()
    local wl = Store.GetWatchlistTable and Store:GetWatchlistTable()

    for _, row in pairs(dirMap) do
        local isFriend = row.sources and (row.sources.friend or row.sources.bnet)
        local isOptedGuild = row.sources and row.sources.guild and row.lookupKey and isGuildWatchFn and isGuildWatchFn(Store, row.lookupKey)
        local isWoWOnline = row.online == true and (row.sources.friend or row.sources.guild or row.bnetState == "wow_forever")
        if (isFriend or isOptedGuild) and isWoWOnline then
            local aKey = GetAlertTargetKey(row)
            if aKey and not prevWowOnline[aKey] then
                local wlEntry = row.lookupKey and wl and wl[row.lookupKey]
                local isMuted = Store.IsPlayerNotifyMuted and Store:IsPlayerNotifyMuted(row.lookupKey, wlEntry, row.bnetAccountID)
                local isFav = row.bnetFavorite == true or (row.lookupKey and Store.IsSocialFavorite and Store:IsSocialFavorite(row.lookupKey))
                if ns.Chat and ns.Chat.QueuePoliteDiscoveryPing and row.bnetAccountID and row.bnetState == "wow_forever" then
                    ns.Chat:QueuePoliteDiscoveryPing({
                        targetName = row.hasCharacterName ~= false and row.displayName or nil,
                        bnetAccountID = row.bnetAccountID,
                        lookupKey = row.lookupKey,
                        guid = row.guid,
                    })
                end
                local shouldNotify = (not isMuted) and (isOptedGuild or alertMode == "all" or (alertMode == "favorites" and isFav))
                if shouldNotify then
                    local lastAlert = friendAlertLastAt[aKey]
                    if not lastAlert or (now - lastAlert) >= FRIEND_ALERT_DEBOUNCE then
                        friendAlertLastAt[aKey] = now
                        local shownName = row.displayName or row.bnetName or "?"
                        local areaTxt = (row.area and row.area ~= "") and row.area or L["Online"]
                        local srcTag = isOptedGuild and not isFriend and L["Guild"]
                            or (row.sources.bnet and not row.sources.friend and L["Battle.net"])
                            or L["Friend Online"]

                        local didToast = false
                        local didChat = false
                        local didSound = false
                        if settings.friendOnlineAlertToast ~= false then
                            ns:Emit("ADDON_MESSAGE_NOTIFY", {
                                id = "friend:" .. aKey .. ":" .. tostring(now),
                                kind = "FRIEND_ONLINE",
                                sourceTag = srcTag,
                                sender = shownName,
                                senderClass = row.classFile,
                                text = (row.area and row.area ~= "") and (L["Online"] .. " · " .. row.area) or L["Is now online in WoW: Forever"],
                                searchHint = shownName,
                                ts = now,
                                priority = 1,
                            })
                            didToast = true
                        end
                        if settings.friendOnlineAlertChat == true then
                            local hex = Compat.ClassHex(row.classFile)
                            local link = "|Haddon:SCentral:social:" .. shownName .. "|h|cff59c7ff[" .. L["Social"] .. "]|r|h"
                            local lineText = (row.area and row.area ~= "")
                                and L["%s came online (%s) %s"]:format(hex .. shownName .. "|r", areaTxt, link)
                                or L["%s came online %s"]:format(hex .. shownName .. "|r", link)
                            ns:Print("%s", lineText)
                            didChat = true
                        end
                        if settings.friendOnlineAlertSound ~= false and PlaySound and SOUNDKIT then
                            local sid = SOUNDKIT.MAP_PING or 3175
                            if sid then
                                pcall(PlaySound, sid, "Master")
                                didSound = true
                            end
                        end
                        if row.lookupKey and row.lookupKey ~= "" then
                            notifiedByLookup[row.lookupKey] = {
                                toast = didToast,
                                chat = didChat,
                                sound = didSound,
                            }
                        end
                    end
                end
            end
        end
    end

    prevWowOnline = nextWow
    return notifiedByLookup, false
end

local function BuildDirectoryStats(onlineMap, dirMap, inviteCount)
    local stats = {
        onlineTotal = 0,
        onlineGuild = 0,
        onlineFriend = 0,
        onlineBnet = 0,
        friendOnline = 0,
        friendTotal = 0,
        bnetOnlineWoW = 0,
        bnetOnlineApp = 0,
        bnetTotal = 0,
        dirTotal = 0,
        offlineTotal = 0,
        pendingBNetInvites = inviteCount or 0,
    }
    for _, row in pairs(onlineMap) do
        stats.onlineTotal = stats.onlineTotal + 1
        if row.sources then
            if row.sources.guild then stats.onlineGuild = stats.onlineGuild + 1 end
            if row.sources.friend then stats.onlineFriend = stats.onlineFriend + 1 end
            if row.sources.bnet then stats.onlineBnet = stats.onlineBnet + 1 end
        end
    end
    for _, row in pairs(dirMap) do
        stats.dirTotal = stats.dirTotal + 1
        if not row.online then
            stats.offlineTotal = stats.offlineTotal + 1
        end
        if row.sources then
            if row.sources.friend then
                stats.friendTotal = stats.friendTotal + 1
                if row.online then stats.friendOnline = stats.friendOnline + 1 end
            end
            if row.sources.bnet then
                stats.bnetTotal = stats.bnetTotal + 1
                if row.bnetState == "wow_forever" then
                    stats.bnetOnlineWoW = stats.bnetOnlineWoW + 1
                elseif row.online then
                    stats.bnetOnlineApp = stats.bnetOnlineApp + 1
                end
            end
        end
    end
    return stats
end

local SCANNERS = { ScanGuild, ScanCharacterFriends, ScanBattleNet }

function Social:Scan()
    lastScanAt = (GetTime and GetTime()) or 0
    if Compat.SyncRosterForeverNames then
        Compat.SyncRosterForeverNames()
    end

    local onlineCtx = NewScanContext()
    local dirCtx = NewScanContext()
    local wlObsMap = {}
    local nextBNetWatchlistOnline = {}
    for _, scanner in ipairs(SCANNERS) do
        local ok, err = pcall(scanner, onlineCtx, dirCtx, wlObsMap, nextBNetWatchlistOnline)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end

    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    if type(wlTable) == "table" and next(wlTable) ~= nil then
        for lookupKey, prevDispName in pairs(prevBNetWatchlistOnline) do
            if not onlineCtx.byLookup[lookupKey] and not wlObsMap[lookupKey] then
                QueueWatchlistObs(wlObsMap, lookupKey, prevDispName, false, nil, nil, nil, nil, "bnet")
            end
        end
    end
    prevBNetWatchlistOnline = nextBNetWatchlistOnline

    Store.social = onlineCtx.map
    Store.socialByLookup = onlineCtx.byLookup
    Store.socialByGuid = onlineCtx.byGuid
    -- Map lookups back to row objects cleanly for O(1) Store callers.
    local rowByLookup, rowByGuid = {}, {}
    for _, row in pairs(onlineCtx.map) do
        if row.guid and row.guid ~= "" then
            rowByGuid[row.guid] = row
        end
        if row.lookupKey and row.lookupKey ~= "" then
            local prev = rowByLookup[row.lookupKey]
            if not prev or (row.samePool ~= false and prev.samePool == false) then
                rowByLookup[row.lookupKey] = row
            end
        end
    end
    Store.socialByLookup = rowByLookup
    Store.socialByGuid = rowByGuid

    Store.socialDirectory = dirCtx.map
    local dirByLookup, dirByKey = {}, {}
    for k, row in pairs(dirCtx.map) do
        dirByKey[k] = row
        if row.lookupKey and row.lookupKey ~= "" then
            local prev = dirByLookup[row.lookupKey]
            if not prev or (row.online and not prev.online) then
                dirByLookup[row.lookupKey] = row
            end
        end
    end
    Store.socialDirectoryByKey = dirByKey
    Store.socialDirectoryByLookup = dirByLookup

    pendingBNetInvites = Compat.GetPendingBNetInvites and Compat.GetPendingBNetInvites() or {}
    local stats = BuildDirectoryStats(onlineCtx.map, dirCtx.map, #pendingBNetInvites)
    self._counts = {
        all = stats.onlineTotal,
        guild = stats.onlineGuild,
        friend = stats.onlineFriend,
        bnet = stats.onlineBnet,
    }
    self._dirStats = stats
    self._dirRevision = (self._dirRevision or 0) + 1

    local notifiedByLookup, inGrace = CheckFriendOnlineTransitions(dirCtx.map)
    for lookupKey, obs in pairs(wlObsMap) do
        local nInfo = notifiedByLookup and notifiedByLookup[lookupKey]
        Store:SyncWatchlistObservation(obs.displayName, obs, {
            suppressAlert = inGrace,
            suppressToast = nInfo and nInfo.toast == true,
            suppressChat = nInfo and nInfo.chat == true,
            suppressSound = nInfo and nInfo.sound == true,
            allowUnknownTransition = not inGrace,
        })
    end
    hasInitialScan = true

    ns:Emit("SOCIAL_UPDATED")
end

function Social:RequestRosters(force)
    local now = GetTime()
    if not force and (now - LAST_ROSTER_ASK) < ROSTER_MIN_GAP then return end
    LAST_ROSTER_ASK = now
    if IsInGuild and IsInGuild() then
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            pcall(C_GuildInfo.GuildRoster)
        elseif GuildRoster then
            pcall(GuildRoster)
        end
    end
    if C_FriendList and C_FriendList.ShowFriends then
        pcall(C_FriendList.ShowFriends)
    elseif ShowFriends then
        pcall(ShowFriends)
    end
end

function Social:GetList(filterSource)
    local out = {}
    for _, row in pairs(Store.social) do
        local include = not filterSource or filterSource == "all" or (row.sources and row.sources[filterSource] == true)
        if include then
            table.insert(out, row)
        end
    end
    table.sort(out, function(a, b)
        return (a.displayName or "") < (b.displayName or "")
    end)
    return out
end

function Social:GetCount(filterSource)
    if not self._counts then return 0 end
    if not filterSource or filterSource == "all" then
        return self._counts.all or 0
    end
    return self._counts[filterSource] or 0
end

function Social:GetDirectoryStats()
    return self._dirStats or {
        onlineTotal = 0,
        onlineGuild = 0,
        onlineFriend = 0,
        onlineBnet = 0,
        friendOnline = 0,
        friendTotal = 0,
        bnetOnlineWoW = 0,
        bnetOnlineApp = 0,
        bnetTotal = 0,
        dirTotal = 0,
        offlineTotal = 0,
        pendingBNetInvites = 0,
    }
end

function Social:GetPendingBNetInvites()
    return pendingBNetInvites
end

function Social:GetDirectoryEntry(keyOrName)
    if type(keyOrName) ~= "string" or keyOrName == "" then return nil end
    if Store.socialDirectoryByKey and Store.socialDirectoryByKey[keyOrName] then
        return Store.socialDirectoryByKey[keyOrName]
    end
    local lookup = Compat.ParseCharacterFields and Compat.ParseCharacterFields(keyOrName) or keyOrName:lower()
    return Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookup] or nil
end

local function RowHasFriendOrGuild(item)
    return item.sources and (item.sources.friend == true or item.sources.guild == true)
end

local function ComputeSmartScore(item, meta, isFav, isSC, hasCompanion)
    local tier = 1
    if item.online then
        if item.bnetState == "wow_forever" or (item.sources and RowHasFriendOrGuild(item)) then
            if isFav then
                tier = 7
            else
                tier = 6
            end
        elseif item.bnetState == "wow_other" then
            tier = isFav and 5 or 4
        else
            tier = isFav and 5 or 4
        end
    else
        if isFav then
            tier = 3
        elseif hasCompanion then
            tier = 2
        else
            tier = 1
        end
    end
    local avail = (item.online and not item.afk and not item.dnd) and 2 or ((item.online and item.afk) and 1 or 0)
    local flagScore = (meta and meta.flag == "GOOD") and 2 or ((meta and meta.flag == "AVOID") and 0 or 1)
    local scScore = isSC and 1 or 0
    return (tier * 100) + (avail * 10) + (flagScore * 2) + scScore
end

function Social:GetDirectoryList(opts)
    opts = opts or {}
    local srcFilter = opts.sourceFilter or "all"
    local folderFilter = opts.folderFilter or "all"
    local showOffline = opts.showOffline ~= false
    local sortBy = opts.sortBy or "smart"
    local out = {}
    local scoreMap = {}

    local hasChat = ns.Chat and ns.Chat.IsLookupKeyVerified
    for _, item in pairs(Store.socialDirectory or {}) do
        local key = item.lookupKey
        local meta = key and Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(key)
            or (key and Store.GetSocialMeta and Store:GetSocialMeta(key))
            or nil
        local isFav = item.bnetFavorite == true or (key ~= nil and Store.IsSocialFavorite and Store:IsSocialFavorite(key))
        local isSC = key ~= nil and hasChat and ns.Chat:IsLookupKeyVerified(key) == true
        local comp = key and Store.GetRecentCompanion and Store:GetRecentCompanion(key) or nil

        local srcMatch = false
        if srcFilter == "all" then
            srcMatch = item.online or showOffline
        elseif srcFilter == "online" then
            srcMatch = item.online == true
        elseif srcFilter == "offline" then
            srcMatch = item.online ~= true
        elseif srcFilter == "guild" then
            srcMatch = item.sources and item.sources.guild == true and (item.online or showOffline)
        elseif srcFilter == "friend" then
            srcMatch = item.sources and item.sources.friend == true and (item.online or showOffline)
        elseif srcFilter == "bnet" then
            srcMatch = item.sources and item.sources.bnet == true and (item.online or showOffline)
        elseif srcFilter == "fav" then
            srcMatch = isFav and (item.online or showOffline)
        elseif srcFilter == "sc" then
            srcMatch = isSC and (item.online or showOffline)
        elseif srcFilter == "good" then
            srcMatch = (meta and meta.flag == "GOOD") == true and (item.online or showOffline)
        elseif srcFilter == "recent" then
            srcMatch = comp ~= nil
        end

        local folderMatch = true
        if folderFilter == "__none" then
            folderMatch = not (meta and meta.folder and meta.folder ~= "")
        elseif folderFilter ~= "all" then
            folderMatch = (meta and meta.folder == folderFilter) == true
        end

        if srcMatch and folderMatch then
            out[#out + 1] = item
            scoreMap[item] = ComputeSmartScore(item, meta, isFav, isSC, comp ~= nil)
        end
    end

    table.sort(out, function(a, b)
        if sortBy == "name" then
            if (a.online == true) ~= (b.online == true) then
                return a.online == true
            end
            return (a.displayName or ""):lower() < (b.displayName or ""):lower()
        elseif sortBy == "level" then
            if (a.online == true) ~= (b.online == true) then
                return a.online == true
            end
            local la, lb = a.level or 0, b.level or 0
            if la ~= lb then
                return la > lb
            end
            return (a.displayName or ""):lower() < (b.displayName or ""):lower()
        elseif sortBy == "lastSeen" then
            if (a.online == true) ~= (b.online == true) then
                return a.online == true
            end
            local ta, tb = a.lastSeen or 0, b.lastSeen or 0
            if ta ~= tb then
                return ta > tb
            end
            return (a.displayName or ""):lower() < (b.displayName or ""):lower()
        else
            local sa, sb = scoreMap[a] or 0, scoreMap[b] or 0
            if sa ~= sb then
                return sa > sb
            end
            return (a.displayName or ""):lower() < (b.displayName or ""):lower()
        end
    end)

    return out
end

function Social:QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    local minWait = math.max(2.0, tonumber(delay) or 2.0)
    local now = (GetTime and GetTime()) or 0
    if lastScanAt > 0 and (now - lastScanAt) < 5.0 then
        minWait = math.max(minWait, 5.0 - (now - lastScanAt))
    end
    C_Timer.After(minWait, function()
        scanQueued = false
        Social:Scan()
    end)
end

function Social:Init()
    loginMonoAt = (GetTime and GetTime()) or 0
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "GUILD_ROSTER_UPDATE",
        "PLAYER_GUILD_UPDATE",
        "FRIENDLIST_UPDATE",
        "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_ACCOUNT_ONLINE",
        "BN_FRIEND_ACCOUNT_OFFLINE",
        "BN_FRIEND_INVITE_ADDED",
        "BN_FRIEND_INVITE_REMOVED",
        "BN_FRIEND_INVITE_LIST_INITIALIZED",
    }) do
        ns.RegisterEvent(self, eventName, function()
            Social:QueueScan()
        end)
    end

    ns.RegisterEvent(self, "BN_CONNECTED", function()
        reconnectGraceUntil = ((GetTime and GetTime()) or 0) + 10.0
        Social:QueueScan(1.5)
    end)
    ns.RegisterEvent(self, "BN_DISCONNECTED", function()
        reconnectGraceUntil = ((GetTime and GetTime()) or 0) + 10.0
        Social:QueueScan(0.5)
    end)

    C_Timer.After(2, function()
        self:RequestRosters(true)
        self:Scan()
    end)

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(60, function()
            self:RequestRosters(false)
            self:Scan()
        end)
    end
end
