local _, ns = ...

local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Collects live online players from Guild, Character Friends, and Battle.net.
-- Zero /who throttle cost; updates Store.social and cross-updates Watchlist.
local Social = {}
ns.Social = Social
table.insert(ns.modules, Social)

local LAST_ROSTER_ASK = 0
local ROSTER_MIN_GAP = 30
local scanQueued = false
local guildObsScratch = { source = "guild" }
local friendObsScratch = { source = "friend" }
local bnetObsScratch = { source = "bnet" }

local function PopulateAndSyncWatchlist(scratch, displayName, online, level, classFile, area, guildName)
    scratch.online = online
    scratch.level = level
    scratch.classFile = classFile
    scratch.area = area
    scratch.guild = guildName
    Store:SyncWatchlistObservation(displayName, scratch)
end

local function MergeEntry(map, key, patch)
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
    return row
end

local function ScanGuild(map)
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true
    local info = Store.guildInfo
    info.inGuild = inGuild
    if not inGuild or not GetGuildRosterInfo then
        info.name, info.motd, info.onlineCount, info.totalCount = nil, nil, 0, 0
        return
    end

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
        local okG, name, rankName, rankIndex, level, classLoc, area, note, officerNote, online, status, classFile, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
        if okG then
            name = Safe.String(name)
            guid = Safe.String(guid)
            local isOnline = (online == true or online == 1)
            if name and not Compat.IsMe(name, guid) then
                local parsed = Compat.ParseCharacterName(name)
                if parsed then
                    if guid and Compat.CacheForeverFullName then
                        Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
                    end
                    if Compat.CacheGuildMember then
                        Compat.CacheGuildMember(guid, parsed.firstName, parsed.displayName)
                    end
                    if isOnline then
                        onlineCount = onlineCount + 1
                        local key = guid or ("char:" .. parsed.lookupKey)
                        local cleanArea = Safe.String(area) or ""
                        local cleanClass = Safe.String(classFile) or Compat.ClassFileFromLocalized(Safe.String(classLoc))
                        local cleanLevel = Safe.Number(level)
                        MergeEntry(map, key, {
                            displayName = parsed.displayName,
                            lookupKey = parsed.lookupKey,
                            guid = guid,
                            level = cleanLevel,
                            classFile = cleanClass,
                            area = cleanArea,
                            guild = info.name,
                            rankName = Safe.String(rankName),
                            note = Safe.String(note),
                            statusFlag = Safe.Number(status) or 0,
                            online = true,
                            sources = { guild = true },
                        })
                        if hasWatchlist then
                            PopulateAndSyncWatchlist(guildObsScratch, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, info.name or "")
                        end
                    elseif hasWatchlist then
                        PopulateAndSyncWatchlist(
                            guildObsScratch,
                            parsed.displayName,
                            false,
                            Safe.Number(level),
                            Safe.String(classFile) or Compat.ClassFileFromLocalized(Safe.String(classLoc)),
                            Safe.String(area) or "",
                            info.name or ""
                        )
                    end
                end
            elseif isOnline and name then
                onlineCount = onlineCount + 1
            end
        end
    end

    info.onlineCount = onlineCount
end

local function ScanCharacterFriends(map)
    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasWatchlist = type(wlTable) == "table" and next(wlTable) ~= nil
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local count = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
        for i = 1, count do
            local f = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(f) == "table" then
                local rawName = Safe.String(f.name)
                local guid = Safe.String(f.guid)
                local isOnline = Safe.Value(f.connected) == true
                if rawName and not Compat.IsMe(rawName, guid) then
                    local parsed = Compat.ParseCharacterName(rawName)
                    if parsed then
                        if guid and Compat.CacheForeverFullName then
                            Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
                        end
                        local cleanClass = Compat.ClassFileFromLocalized(Safe.String(f.className)) or (Compat.ClassFileFromGuid and Compat.ClassFileFromGuid(guid))
                        local cleanLevel = Safe.Number(f.level)
                        local cleanArea = Safe.String(f.area) or ""
                        if isOnline then
                            local key = guid or ("char:" .. parsed.lookupKey)
                            MergeEntry(map, key, {
                                displayName = parsed.displayName,
                                lookupKey = parsed.lookupKey,
                                guid = guid,
                                level = cleanLevel,
                                classFile = cleanClass,
                                area = cleanArea,
                                note = Safe.String(f.notes),
                                afk = Safe.Value(f.afk) == true,
                                dnd = Safe.Value(f.dnd) == true,
                                online = true,
                                sources = { friend = true },
                            })
                            if hasWatchlist then
                                PopulateAndSyncWatchlist(friendObsScratch, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, nil)
                            end
                        elseif hasWatchlist then
                            PopulateAndSyncWatchlist(friendObsScratch, parsed.displayName, false, cleanLevel, cleanClass, cleanArea, nil)
                        end
                    end
                end
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        local count = Safe.Number(Safe.Call(GetNumFriends)) or 0
        for i = 1, count do
            local okF, rawName, level, classLoc, area, connected, status, notes = pcall(GetFriendInfo, i)
            if okF then
                rawName = Safe.String(rawName)
                local isOnline = (connected == true or connected == 1)
                if rawName and not Compat.IsMe(rawName, nil) then
                    local parsed = Compat.ParseCharacterName(rawName)
                    if parsed then
                        local cleanClass = Compat.ClassFileFromLocalized(Safe.String(classLoc))
                        local cleanLevel = Safe.Number(level)
                        local cleanArea = Safe.String(area) or ""
                        if isOnline then
                            local key = "char:" .. parsed.lookupKey
                            local cleanStatus = Safe.String(status)
                            local isAfk = (cleanStatus == "<AFK>" or (CHAT_FLAG_AFK and cleanStatus == CHAT_FLAG_AFK))
                            local isDnd = (cleanStatus == "<DND>" or (CHAT_FLAG_DND and cleanStatus == CHAT_FLAG_DND))
                            MergeEntry(map, key, {
                                displayName = parsed.displayName,
                                lookupKey = parsed.lookupKey,
                                level = cleanLevel,
                                classFile = cleanClass,
                                area = cleanArea,
                                note = Safe.String(notes),
                                afk = isAfk,
                                dnd = isDnd,
                                online = true,
                                sources = { friend = true },
                            })
                            if hasWatchlist then
                                PopulateAndSyncWatchlist(friendObsScratch, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, nil)
                            end
                        elseif hasWatchlist then
                            PopulateAndSyncWatchlist(friendObsScratch, parsed.displayName, false, cleanLevel, cleanClass, cleanArea, nil)
                        end
                    end
                end
            end
        end
    end
end

local function ScanBattleNet(map)
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasWatchlist = type(wlTable) == "table" and next(wlTable) ~= nil
    local count = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    for i = 1, count do
        local account = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
        local g = type(account) == "table" and account.gameAccountInfo
        if type(g) == "table" and Safe.Value(g.isOnline) == true then
            local clientProgram = Safe.String(g.clientProgram)
            local isWoW = clientProgram == (BNET_CLIENT_WOW or "WoW")
            local sameProject = isWoW and (not WOW_PROJECT_ID or Safe.Value(g.wowProjectID) == WOW_PROJECT_ID)
            local charName = Safe.String(g.characterName)
            local realmName = Safe.String(g.realmName)
            local guid = Safe.String(g.playerGuid)
            local accountName = Safe.String(account.accountName) or Safe.String(account.battleTag) or "Battle.net"

            if sameProject and charName and not Compat.IsMe(charName, guid) then
                local parsed = Compat.ParseCharacterName(charName)
                if parsed then
                    if guid and Compat.CacheForeverFullName then
                        Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
                    end
                    local samePool = (not realmName) or Compat.IsForeverShardLabel(realmName)
                    local key = guid or ("bnet:" .. (Safe.Number(g.gameAccountID) or parsed.lookupKey))
                    local cleanClass = Compat.ClassFileFromLocalized(Safe.String(g.className)) or (Compat.ClassFileFromGuid and Compat.ClassFileFromGuid(guid))
                    local cleanLevel = Safe.Number(g.characterLevel)
                    local cleanArea = Safe.String(g.areaName) or ""
                    local cleanFaction = Safe.String(g.factionName)
                    local myEngFaction, myLocFaction = Compat.PlayerFaction()
                    local sameFaction = (not cleanFaction) or cleanFaction == myEngFaction or (myLocFaction ~= nil and cleanFaction == myLocFaction)

                    MergeEntry(map, key, {
                        displayName = parsed.displayName,
                        lookupKey = parsed.lookupKey,
                        guid = guid,
                        bnetName = accountName,
                        bnetAccountID = Safe.Number(account.bnetAccountID) or Safe.Number(g.gameAccountID),
                        level = cleanLevel,
                        classFile = cleanClass,
                        area = cleanArea,
                        faction = cleanFaction,
                        samePool = samePool,
                        sameFaction = sameFaction,
                        online = true,
                        sources = { bnet = true },
                    })

                    if hasWatchlist and samePool and sameFaction then
                        PopulateAndSyncWatchlist(bnetObsScratch, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, nil)
                    end
                end
            end
        end
    end
end

local lastScanAt = 0
local SCANNERS = { ScanGuild, ScanCharacterFriends, ScanBattleNet }

function Social:Scan()
    lastScanAt = (GetTime and GetTime()) or 0
    if Compat.SyncRosterForeverNames then
        Compat.SyncRosterForeverNames()
    end
    local nextMap = {}
    for _, scanner in ipairs(SCANNERS) do
        local ok, err = pcall(scanner, nextMap)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
    Store.social = nextMap
    local byLookup, byGuid, counts = {}, {}, { all = 0 }
    for _, row in pairs(nextMap) do
        counts.all = counts.all + 1
        if row.sources then
            for s, enabled in pairs(row.sources) do
                if enabled then
                    counts[s] = (counts[s] or 0) + 1
                end
            end
        end
        if row.guid and row.guid ~= "" then
            byGuid[row.guid] = row
        end
        if row.lookupKey and row.lookupKey ~= "" then
            local prev = byLookup[row.lookupKey]
            if not prev or (row.samePool ~= false and prev.samePool == false) then
                byLookup[row.lookupKey] = row
            end
        end
    end
    self._counts = counts
    Store.socialByLookup = byLookup
    Store.socialByGuid = byGuid
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
        local include = not filterSource or filterSource == "all" or row.sources[filterSource] == true
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
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "GUILD_ROSTER_UPDATE",
        "PLAYER_GUILD_UPDATE",
        "FRIENDLIST_UPDATE",
        "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_ACCOUNT_ONLINE",
        "BN_FRIEND_ACCOUNT_OFFLINE",
    }) do
        ns.RegisterEvent(self, eventName, function()
            Social:QueueScan()
        end)
    end

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
