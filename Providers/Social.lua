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

    info.name = Safe.String(Safe.Call(GetGuildInfo, "player"))
    info.motd = Safe.String(Safe.Call(GetGuildRosterMOTD)) or ""

    local total = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    info.totalCount = total
    local onlineCount = 0

    for i = 1, total do
        local name, rankName, _, level, _, area, note, officerNote, online, status, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        name = Safe.String(name)
        guid = Safe.String(guid)
        if Safe.Value(online) == true and name then
            onlineCount = onlineCount + 1
            if not Compat.IsMe(name, guid) then
                local parsed = Compat.ParseCharacterName(name)
                if parsed then
                    local key = guid or ("char:" .. parsed.lookupKey)
                    local cleanArea = Safe.String(area) or ""
                    local cleanClass = Safe.String(classFile)
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
                        sources = { guild = true },
                    })
                    Store:SyncWatchlistObservation(parsed.displayName, {
                        online = true,
                        source = "guild",
                        level = cleanLevel,
                        classFile = cleanClass,
                        area = cleanArea,
                        guild = info.name or "",
                    })
                end
            end
        end
    end

    info.onlineCount = onlineCount
end

local function ScanCharacterFriends(map)
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then return end
    local count = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
    for i = 1, count do
        local f = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
        if type(f) == "table" and Safe.Value(f.connected) == true then
            local rawName = Safe.String(f.name)
            local guid = Safe.String(f.guid)
            if rawName and not Compat.IsMe(rawName, guid) then
                local parsed = Compat.ParseCharacterName(rawName)
                if parsed then
                    local key = guid or ("char:" .. parsed.lookupKey)
                    local cleanClass = Compat.ClassFileFromLocalized(Safe.String(f.className))
                    local cleanLevel = Safe.Number(f.level)
                    local cleanArea = Safe.String(f.area) or ""
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
                        sources = { friend = true },
                    })
                    Store:SyncWatchlistObservation(parsed.displayName, {
                        online = true,
                        source = "friend",
                        level = cleanLevel,
                        classFile = cleanClass,
                        area = cleanArea,
                    })
                end
            end
        end
    end
end

local function ScanBattleNet(map)
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
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
                    local samePool = (not realmName) or Compat.IsForeverShardLabel(realmName)
                    local key = guid or ("bnet:" .. (Safe.Number(g.gameAccountID) or parsed.lookupKey))
                    local cleanClass = Compat.ClassFileFromLocalized(Safe.String(g.className))
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
                        bnetAccountID = Safe.Number(g.gameAccountID),
                        level = cleanLevel,
                        classFile = cleanClass,
                        area = cleanArea,
                        faction = cleanFaction,
                        samePool = samePool,
                        sameFaction = sameFaction,
                        sources = { bnet = true },
                    })

                    if samePool and sameFaction then
                        Store:SyncWatchlistObservation(parsed.displayName, {
                            online = true,
                            source = "bnet",
                            level = cleanLevel,
                            classFile = cleanClass,
                            area = cleanArea,
                        })
                    end
                end
            end
        end
    end
end

function Social:Scan()
    local nextMap = {}
    for _, scanner in ipairs({ ScanGuild, ScanCharacterFriends, ScanBattleNet }) do
        local ok, err = pcall(scanner, nextMap)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
    Store.social = nextMap
    ns:Emit("SOCIAL_UPDATED")
end

function Social:RequestRosters(force)
    local now = GetTime()
    if not force and (now - LAST_ROSTER_ASK) < ROSTER_MIN_GAP then return end
    LAST_ROSTER_ASK = now
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    end
    if C_FriendList and C_FriendList.ShowFriends then
        pcall(C_FriendList.ShowFriends)
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

local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.4, function()
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
        ns.RegisterEvent(self, eventName, QueueScan)
    end

    C_Timer.After(2, function()
        self:RequestRosters(true)
        self:Scan()
    end)
end
