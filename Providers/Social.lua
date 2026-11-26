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
local ROSTER_MIN_GAP = 15
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
local verifiedFriendConnected = {}
local bnetAccByLookup = {}
local bnetInfoByAccId = {}
local bnetFactionByLookup = {}

local ALLIANCE_RACE_TOKENS = {
    "human", "humano", "dwarf", "anao", "anão", "enano",
    "night elf", "elfo noturno", "elfo de la noche",
    "gnome", "gnomo", "draenei", "high elf", "alto elfo", "worgen",
}
local HORDE_RACE_TOKENS = {
    "orc", "undead", "renegado", "morto-vivo", "no-muerto",
    "tauren", "troll", "blood elf", "elfo sangrento", "elfo de sangre", "goblin",
}
local ALLIANCE_ZONE_TOKENS = {
    "darnassus", "stormwind", "ventobravo", "ironforge", "altaforja", "exodar",
    "teldrassil", "darkshore", "costa negra", "dun morogh", "elwynn", "azuremyst", "nevoa lazuli", "névoa lazúli",
}
local HORDE_ZONE_TOKENS = {
    "orgrimmar", "ogrimmar", "undercity", "cidade baixa", "thunder bluff", "penhasco do trovao", "penhasco do trovão",
    "silvermoon", "luaprata", "durotar", "mulgore", "tirisfal", "eversong", "canto eterno", "ghostlands", "terras fantasmas",
}

local function ResolveBNetFaction(g, areaName, lookupKey, allowCache)
    local rawFac = type(g) == "table" and Safe.String(g.factionName) or nil
    if rawFac and rawFac ~= "" then
        local low = rawFac:lower()
        if low == "alliance" or low:find("alian", 1, true) then
            return "Alliance", true
        elseif low == "horde" or low:find("hord", 1, true) then
            return "Horde", true
        end
    end
    local raceId = type(g) == "table" and Safe.Number(g.raceID) or nil
    if raceId and C_CreatureInfo and C_CreatureInfo.GetFactionInfo then
        local fInfo = Safe.Call(C_CreatureInfo.GetFactionInfo, raceId)
        local fGroup = type(fInfo) == "table" and Safe.String(fInfo.groupTag) or nil
        if fGroup == "Alliance" or fGroup == "Horde" then
            return fGroup, true
        end
    end
    if allowCache and lookupKey and bnetFactionByLookup[lookupKey] then
        return bnetFactionByLookup[lookupKey], false
    end
    local raceName = type(g) == "table" and Safe.String(g.raceName) or nil
    if raceName and raceName ~= "" then
        local lowR = raceName:lower()
        for _, tok in ipairs(ALLIANCE_RACE_TOKENS) do
            if lowR:find(tok, 1, true) then return "Alliance", false end
        end
        for _, tok in ipairs(HORDE_RACE_TOKENS) do
            if lowR:find(tok, 1, true) then return "Horde", false end
        end
    end
    if areaName and areaName ~= "" then
        local lowA = areaName:lower()
        for _, tok in ipairs(ALLIANCE_ZONE_TOKENS) do
            if lowA:find(tok, 1, true) then return "Alliance", false end
        end
        for _, tok in ipairs(HORDE_ZONE_TOKENS) do
            if lowA:find(tok, 1, true) then return "Horde", false end
        end
    end
    return nil, false
end

local presenceScratch = {}

local function QueueWatchlistObs(wlObsMap, lookupKey, displayName, online, level, classFile, area, guildName, source)
    if not wlObsMap or not lookupKey or lookupKey == "" or not displayName or displayName == "" then
        return
    end
    if verifiedFriendConnected[lookupKey] == false and online == true and source == "guild" then
        online = false
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
        elseif verifiedFriendConnected[lookupKey] == false then
            rec.online = false
        end
        if level and level > 0 and (online ~= true or rec.online ~= true or level > (rec.level or 0) or (rec.level or 0) <= 0) then
            rec.level = level
        end
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

local BNET_STATE_RANK = {
    wow_forever = 4,
    wow_other = 3,
    bnet_app = 2,
    offline = 1,
}

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
    local incomingOnline = patch.online == true
    for k, v in pairs(patch) do
        if k == "sources" then
            for s in pairs(v) do row.sources[s] = true end
        elseif k == "online" or k == "friendOnline" or k == "guildOnline" or k == "bnetOnline"
            or k == "afk" or k == "dnd" or k == "samePool"
        then
            if v ~= nil then
                row[k] = (row[k] == true) or (v == true)
            end
        elseif k == "sameFaction" then
            if v ~= nil and row.sameFaction ~= true then
                row.sameFaction = (v == true)
            end
        elseif k == "bnetState" then
            if v ~= nil and v ~= "" then
                local curRank = BNET_STATE_RANK[row.bnetState] or 0
                local newRank = BNET_STATE_RANK[v] or 0
                if newRank >= curRank then
                    row.bnetState = v
                end
            end
        elseif k == "lastSeen" then
            local numV = tonumber(v)
            if numV and numV > (tonumber(row.lastSeen) or 0) then
                row.lastSeen = numV
            end
        elseif k == "level" then
            local numV = tonumber(v)
            local curV = tonumber(row.level) or 0
            local keepHigherOnline = (row.online == true and incomingOnline == true and curV > 0)
            if numV and ((keepHigherOnline and numV > curV) or (not keepHigherOnline and (numV > 0 or curV <= 0))) then
                row.level = numV
            end
        elseif k == "area" then
            if v ~= nil and v ~= "" then
                if not (row.online == true and not incomingOnline and type(row.area) == "string" and row.area ~= "") then
                    row.area = v
                end
            end
        elseif k == "displayName" then
            if v ~= nil and v ~= "" then
                local existing = row.displayName
                local keepExisting = type(existing) == "string" and existing ~= ""
                    and ((patch.hasCharacterName == false) or (existing:find(" ", 1, true) and not tostring(v):find(" ", 1, true)))
                if not keepExisting then
                    row.displayName = v
                end
            end
        elseif k == "hasCharacterName" then
            if row.hasCharacterName ~= true and not (row.sources and (row.sources.friend or row.sources.guild)) then
                row.hasCharacterName = (v == true)
            end
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

-- Keep freshly observed UNIT_LEVEL / /who levels ahead of stale cached roster snapshots while continuously online.
local function ApplyLiveUnitObs(lookupKey, cleanLevel, cleanArea, isOnline)
    local obsMap = Store and Store.liveUnitObs
    local obs = (lookupKey and obsMap) and obsMap[lookupKey] or nil
    if not obs then
        return cleanLevel, cleanArea
    end
    if isOnline == false then
        obsMap[lookupKey] = nil
        return cleanLevel, cleanArea
    end
    local nowClock = (GetTime and GetTime()) or time()
    local obsLevel = tonumber(obs.level) or 0
    local curLevel = tonumber(cleanLevel) or 0
    if (nowClock - (obs.observedAt or 0)) >= 1800 or (obsLevel > 0 and curLevel >= obsLevel) then
        if obsLevel <= 0 or curLevel >= obsLevel then
            obsMap[lookupKey] = nil
        end
        return cleanLevel, cleanArea
    end
    if obsLevel > curLevel then
        cleanLevel = obsLevel
    end
    if (not cleanArea or cleanArea == "") and type(obs.area) == "string" and obs.area ~= "" then
        cleanArea = obs.area
    end
    return cleanLevel, cleanArea
end

local function NewScanContext()
    return {
        map = {},
        byGuid = {},
        byBNet = {},
        byLookup = {},
    }
end

local guildRosterScanGen = 0
local guildPatchScratch = {
    bnetState = "wow_forever",
    online = true,
    guildOnline = true,
    samePool = true,
    sameFaction = true,
    sources = { guild = true },
}

local function IsGuildOrSocialUiOpen()
    local sc = _G.SocialCentralFrame
    if sc and sc.IsShown and sc:IsShown() then return true end
    local fr = _G.SocialUIFrame or _G.FriendsFrame
    if fr and fr.IsShown and fr:IsShown() then return true end
    local cf = _G.CommunitiesFrame or _G.GuildFrame
    if cf and cf.IsShown and cf:IsShown() then return true end
    local gEmbed = _G.SocialCentralGuildEmbeddedFrame
    if gEmbed and gEmbed.IsShown and gEmbed:IsShown() then return true end
    return false
end

local function ScanGuild(onlineCtx, dirCtx, wlObsMap)
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true
    local info = Store.guildInfo
    info.inGuild = inGuild
    local includeOffline = IsGuildOrSocialUiOpen()
    Social._rosterRanksIncludeOffline = includeOffline
    local rosterRanks = Store.guildRosterRanks
    if type(rosterRanks) ~= "table" then
        rosterRanks = {}
        Store.guildRosterRanks = rosterRanks
    end
    if not inGuild or not GetGuildRosterInfo then
        wipe(rosterRanks)
        info.name, info.motd, info.onlineCount, info.totalCount = nil, nil, 0, 0
        info.myRankIndex, info.myRankName, info.isGuildLeader = nil, nil, false
        return
    end
    guildRosterScanGen = guildRosterScanGen + 1
    local curGen = guildRosterScanGen
    info.isGuildLeader = (IsGuildLeader and Safe.Value(Safe.Call(IsGuildLeader)) == true) or false
    info.myRankIndex = nil
    info.myRankName = nil

    local liveGuildName = Safe.String(Safe.Call(GetGuildInfo, "player"))
    if liveGuildName and liveGuildName ~= "" then
        info.name = liveGuildName
    elseif not info.name or info.name == "" then
        local altRec = Store.GetCurrentAltRecord and Store:GetCurrentAltRecord()
            or (ns.db and ns.db.alts and Compat.CharacterKey and ns.db.alts[Compat.CharacterKey()])
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
            local isOnline = (online == true or online == 1)
            -- Idle memory optimization: when Guild/Social windows are closed, skip offline members'
            -- heavy last-online queries, rosterRank subtables, and GUID cache eviction thrashing.
            if isOnline or includeOffline or hasWatchlist or (i <= 20) then
                name = Safe.String(name)
                guid = Safe.String(guid)
                local cleanRankName = Safe.String(rankName) or ""
                local cleanRankIdx = Safe.Number(rankIndex)
                local cleanLevel = Safe.Number(level) or 0
                local cleanArea = Safe.String(area) or ""
                local cleanNote = Safe.String(note)
                local cleanClass = Safe.String(classFile) or Compat.ClassFileFromLocalized(Safe.String(classLoc))
                local cleanStatus = Safe.Number(status) or 0
                local isMe = name and Compat.IsMe(name, guid)
                local offlineDays = 0
                if not isOnline and includeOffline and GetGuildRosterLastOnline then
                    local okTime, yr, mo, dy, hr = pcall(GetGuildRosterLastOnline, i)
                    if okTime then
                        local y = Safe.Number(yr) or 0
                        local m = Safe.Number(mo) or 0
                        local d = Safe.Number(dy) or 0
                        local h = Safe.Number(hr) or 0
                        offlineDays = (y * 365) + (m * 30) + d + (h / 24)
                    end
                end
                local lk, firstName, dispName, surname = nil, nil, nil, nil
                if name and (isOnline or includeOffline or isMe or hasWatchlist) and Compat.ParseCharacterFields then
                    lk, firstName, dispName, surname = Compat.ParseCharacterFields(name)
                end
                if lk then
                    if verifiedFriendConnected[lk] == false then
                        isOnline = false
                    end
                    cleanLevel, cleanArea = ApplyLiveUnitObs(lk, cleanLevel, cleanArea, isOnline)
                    if isOnline or includeOffline or isMe then
                        local rec = rosterRanks[lk]
                        if not rec then
                            rec = {}
                            rosterRanks[lk] = rec
                        end
                        rec._scanGen = curGen
                        rec.rankIndex = cleanRankIdx
                        rec.rankName = cleanRankName
                        rec.guid = guid
                        rec.displayName = dispName
                        rec.lookupKey = lk
                        rec.level = cleanLevel
                        rec.classFile = cleanClass
                        rec.area = cleanArea
                        rec.note = cleanNote or ""
                        rec.statusFlag = cleanStatus
                        rec.online = isOnline
                        rec.offlineDays = offlineDays
                        rec.isSelf = isMe
                        rec.rosterIndex = i
                    end
                    if isMe then
                        info.myRankIndex = cleanRankIdx
                        info.myRankName = cleanRankName
                        if cleanRankIdx == 0 then
                            info.isGuildLeader = true
                        end
                    end
                end
                if lk and not isMe then
                    if isOnline or includeOffline then
                        if guid and Compat.CacheForeverFullName then
                            Compat.CacheForeverFullName(guid, dispName, firstName)
                        end
                        if Compat.CacheGuildMember then
                            Compat.CacheGuildMember(guid, firstName, dispName)
                        end
                        if surname and Store.MigrateSocialSurnameRecords then
                            Store:MigrateSocialSurnameRecords(firstName, lk)
                        end
                    end
                    if isOnline then
                        onlineCount = onlineCount + 1
                        local patch = guildPatchScratch
                        patch.displayName = dispName
                        patch.lookupKey = lk
                        patch.guid = guid
                        patch.level = cleanLevel
                        patch.classFile = cleanClass
                        patch.area = cleanArea
                        patch.guild = info.name
                        patch.rankName = cleanRankName
                        patch.rankIndex = cleanRankIdx
                        patch.guildNote = cleanNote
                        patch.statusFlag = cleanStatus
                        patch.afk = (cleanStatus == 1)
                        patch.dnd = (cleanStatus == 2)
                        local keyOnline = FindMergeKey(onlineCtx, guid or ("char:" .. lk), guid, nil, lk, true)
                        MergeEntry(onlineCtx, keyOnline, patch)
                        local keyDir = FindMergeKey(dirCtx, guid or ("char:" .. lk), guid, nil, lk, true)
                        MergeEntry(dirCtx, keyDir, patch)
                        if hasWatchlist and wlObsMap then
                            QueueWatchlistObs(wlObsMap, lk, dispName, true, cleanLevel, cleanClass, cleanArea, info.name or "", "guild")
                        end
                    elseif hasWatchlist and wlObsMap then
                        QueueWatchlistObs(wlObsMap, lk, dispName, false, cleanLevel, cleanClass, cleanArea, info.name or "", "guild")
                    end
                elseif isOnline and name then
                    onlineCount = onlineCount + 1
                end
            end
        end
    end

    for k, rec in pairs(rosterRanks) do
        if type(rec) ~= "table" or rec._scanGen ~= curGen then
            rosterRanks[k] = nil
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

    verifiedFriendConnected[parsed.lookupKey] = (isOnline == true)

    if guid and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
    end
    if parsed.surname and Store.MigrateSocialSurnameRecords then
        Store:MigrateSocialSurnameRecords(parsed.firstName, parsed.lookupKey)
    end

    local pres = Store.GetFriendPresence and Store:GetFriendPresence(parsed.lookupKey)
    if isOnline then
        cleanLevel, cleanArea = ApplyLiveUnitObs(parsed.lookupKey, cleanLevel, cleanArea, true)
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
        friendOnline = isOnline == true,
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
    for _, bRec in pairs(bnetInfoByAccId) do
        if type(bRec) == "table" then
            bRec.activeForeverLookups = nil
        end
    end
    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    local hasWatchlist = type(wlTable) == "table" and next(wlTable) ~= nil
    local wowProg = BNET_CLIENT_WOW or "WoW"
    local now = time()
    local count = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
    local bnetStateChanged = false

    local function CollectOnlineForeverLookups(friendIndex, account)
        local activeSet = {}
        local foundAny = false
        local function markGi(gi)
            if type(gi) ~= "table" then return end
            if Safe.Value(gi.isOnline) ~= true then return end
            if Safe.String(gi.clientProgram) ~= wowProg then return end
            if WOW_PROJECT_ID and Safe.Value(gi.wowProjectID) ~= WOW_PROJECT_ID then return end
            local rn = Safe.String(gi.realmName)
            if rn and not Compat.IsForeverShardLabel(rn) then return end
            local cn = Safe.String(gi.characterName)
            local cp = cn and Compat.ParseCharacterName(cn) or nil
            if cp and cp.lookupKey then
                activeSet[cp.lookupKey] = true
                foundAny = true
            end
        end
        if C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
            local gCount = Safe.Number(Safe.Call(C_BattleNet.GetFriendNumGameAccounts, friendIndex)) or 0
            for g = 1, gCount do
                markGi(Safe.Call(C_BattleNet.GetFriendGameAccountInfo, friendIndex, g))
            end
        end
        if not foundAny and type(account) == "table" and type(account.gameAccountInfo) == "table" then
            markGi(account.gameAccountInfo)
        end
        return activeSet
    end

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
                local rawAreaForFac = type(g) == "table" and Safe.String(g.areaName) or ""
                local cleanFaction, isAuthFaction = ResolveBNetFaction(g, rawAreaForFac, parsed and parsed.lookupKey, samePool)
                if cleanFaction and isAuthFaction and samePool and parsed and parsed.lookupKey then
                    bnetFactionByLookup[parsed.lookupKey] = cleanFaction
                end
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
                    cleanLevel, cleanArea = ApplyLiveUnitObs(parsed.lookupKey, cleanLevel, cleanArea, true)
                    TouchPresence(parsed.lookupKey, true, cleanArea, cleanClass, cleanLevel)
                    if parsed.surname and Store.MigrateSocialSurnameRecords then
                        Store:MigrateSocialSurnameRecords(parsed.firstName, parsed.lookupKey)
                    end
                end

                local sameFacVal = nil
                if parsed then
                    sameFacVal = sameFaction
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
                    sameFaction = sameFacVal,
                    afk = accAfk or gameAfk,
                    dnd = accDnd or gameDnd,
                    online = gOnline == true,
                    bnetOnline = gOnline == true,
                    bnetState = bnetState,
                    lastSeen = (gOnline and now) or (bnetLastOnline and bnetLastOnline > 0 and bnetLastOnline) or (pres and pres.lastSeen) or nil,
                    sources = { bnet = true },
                }

                local defaultKey = guid or (bnetAccId and ("bnet:" .. tostring(bnetAccId))) or ("bnet:idx:" .. tostring(fallbackId))
                local dirKey = FindMergeKey(dirCtx, defaultKey, guid, patch.bnetAccountID, patch.lookupKey, samePool and parsed ~= nil)
                MergeEntry(dirCtx, dirKey, patch)

                if bnetAccId then
                    local bRec = bnetInfoByAccId[bnetAccId]
                    if not bRec then
                        bRec = { chars = {} }
                        bnetInfoByAccId[bnetAccId] = bRec
                    end
                    local prevOnline = bRec.online
                    local prevActive = bRec.activeLookupKey
                    bRec.bnetName = accountName or bRec.bnetName
                    bRec.online = gOnline == true
                    if bnetState == "wow_forever" or bnetState == "wow_other" then
                        bRec.seenWoW = true
                    end
                    if bnetState == "wow_forever" and parsed and parsed.lookupKey then
                        bRec.activeLookupKey = parsed.lookupKey
                        bRec.activeDisplayName = parsed.displayName
                        bRec.activeForeverLookups = CollectOnlineForeverLookups(i, account)
                        bRec.activeForeverLookups[parsed.lookupKey] = true
                        if not bRec.chars[parsed.lookupKey] then
                            for existingLk in pairs(bRec.chars) do
                                if existingLk ~= parsed.lookupKey and Store.RecordObservedAltPair then
                                    Store:RecordObservedAltPair(existingLk, parsed.lookupKey)
                                end
                            end
                        end
                        bRec.chars[parsed.lookupKey] = parsed.displayName
                        bnetAccByLookup[parsed.lookupKey] = bnetAccId
                    elseif bnetState ~= "wow_forever" then
                        bRec.activeLookupKey = nil
                        bRec.activeDisplayName = nil
                        bRec.activeForeverLookups = nil
                    end
                    if prevOnline ~= bRec.online or prevActive ~= bRec.activeLookupKey then
                        bnetStateChanged = true
                    end
                end

                if bnetState == "wow_forever" and parsed then
                    if bnetAccId and ns.Watchlist and ns.Watchlist.PromoteSessionBNetAccount then
                        ns.Watchlist:PromoteSessionBNetAccount(bnetAccId, parsed.displayName, {
                            classFile = cleanClass,
                            level = cleanLevel,
                            area = cleanArea,
                            guid = guid,
                        })
                    end
                    local onKey = FindMergeKey(onlineCtx, defaultKey, guid, patch.bnetAccountID, parsed.lookupKey, true)
                    MergeEntry(onlineCtx, onKey, patch)
                    if samePool then
                        if nextBNetWatchlistOnline then
                            nextBNetWatchlistOnline[parsed.lookupKey] = parsed.displayName
                        end
                        if hasWatchlist and wlObsMap then
                            QueueWatchlistObs(wlObsMap, parsed.lookupKey, parsed.displayName, true, cleanLevel, cleanClass, cleanArea, nil, "bnet")
                            local bRecLive = bnetAccId and bnetInfoByAccId[bnetAccId] or nil
                            for wlKey, wlEntry in pairs(wlTable) do
                                if type(wlEntry) == "table" and wlEntry.watchAllAlts == true and wlKey ~= parsed.lookupKey then
                                    local sameAcc = (bRecLive and type(bRecLive.chars) == "table" and bRecLive.chars[wlKey] ~= nil)
                                        or (bnetAccId and bnetAccByLookup[wlKey] == bnetAccId)
                                    if not sameAcc and Store.GetAllLinkedCharacters then
                                        local linked = Store:GetAllLinkedCharacters(wlKey)
                                        for _, altRec in ipairs(linked) do
                                            local altLk = altRec and altRec.lookupKey
                                            if altLk and (altLk == parsed.lookupKey or (bRecLive and type(bRecLive.chars) == "table" and bRecLive.chars[altLk] ~= nil)) then
                                                sameAcc = true
                                                break
                                            end
                                        end
                                    end
                                    if sameAcc then
                                        if bnetAccId then
                                            bnetAccByLookup[wlKey] = bnetAccId
                                            if bRecLive and type(bRecLive.chars) == "table" and not bRecLive.chars[wlKey] then
                                                bRecLive.chars[wlKey] = wlEntry.displayName or wlKey
                                            end
                                        end
                                        if Store.RecordObservedAltPair then
                                            Store:RecordObservedAltPair(wlKey, parsed.lookupKey)
                                        end
                                        QueueWatchlistObs(wlObsMap, wlKey, wlEntry.displayName or parsed.displayName, true, cleanLevel, cleanClass, cleanArea, nil, "bnet")
                                        if wlObsMap[wlKey] then
                                            wlObsMap[wlKey].altLookupKey = parsed.lookupKey
                                            wlObsMap[wlKey].altDisplayName = parsed.displayName
                                            wlObsMap[wlKey].altClassFile = cleanClass
                                            wlObsMap[wlKey].altLevel = cleanLevel
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if bnetStateChanged then
        if ns.Chat and ns.Chat.BumpPeerStateGen then
            ns.Chat:BumpPeerStateGen()
        end
        ns:Emit("CHAT_UPDATED")
    end
end

local function GetAlertTargetKey(row)
    if row.bnetAccountID then
        return "bnet:" .. tostring(row.bnetAccountID)
    end
    if row.lookupKey and row.lookupKey ~= "" then
        return "char:" .. row.lookupKey
    end
    return row.key
end

local function IsRowWoWOnline(row)
    if not row then return false end
    if row.friendOnline == true or row.guildOnline == true then
        return true
    end
    if row.bnetAccountID then
        return row.online == true and row.bnetState == "wow_forever"
    end
    return row.online == true and (row.bnetState == "wow_forever" or (row.sources and (row.sources.friend or row.sources.guild)))
end

local function CheckFriendOnlineTransitions(dirMap)
    local nextWow = {}
    local isGuildWatchFn = Store and Store.IsGuildLoginNotifyEnabled
    for _, row in pairs(dirMap) do
        local isFriend = (row.sources and (row.sources.friend or row.sources.bnet)) == true
        local isOptedGuild = (row.sources and row.sources.guild and row.lookupKey and isGuildWatchFn and isGuildWatchFn(Store, row.lookupKey)) == true
        if (isFriend or isOptedGuild) and IsRowWoWOnline(row) then
            local aKey = GetAlertTargetKey(row)
            if aKey then
                local isFav = (row.lookupKey and Store.IsSocialFavorite and Store:IsSocialFavorite(row.lookupKey)) == true
                nextWow[aKey] = {
                    shownName = row.displayName or row.bnetName or "?",
                    classFile = row.classFile,
                    lookupKey = row.lookupKey,
                    bnetAccountID = row.bnetAccountID,
                    isFriend = isFriend,
                    isOptedGuild = isOptedGuild,
                    isFav = isFav,
                    area = row.area or "",
                    sources = row.sources,
                }
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

    -- 1. Online logins
    for aKey, nextInfo in pairs(nextWow) do
        if not prevWowOnline[aKey] then
            local wlEntry = nextInfo.lookupKey and wl and wl[nextInfo.lookupKey]
            local isMuted = Store.IsPlayerNotifyMuted and Store:IsPlayerNotifyMuted(nextInfo.lookupKey, wlEntry, nextInfo.bnetAccountID)
            if ns.Chat and ns.Chat.QueuePoliteDiscoveryPing and nextInfo.bnetAccountID then
                ns.Chat:QueuePoliteDiscoveryPing({
                    targetName = nextInfo.lookupKey and nextInfo.shownName or nil,
                    bnetAccountID = nextInfo.bnetAccountID,
                    lookupKey = nextInfo.lookupKey,
                })
            end
            local shouldNotify = (not isMuted) and (nextInfo.isOptedGuild or alertMode == "all" or (alertMode == "favorites" and nextInfo.isFav))
            if shouldNotify then
                local lastAlert = friendAlertLastAt[aKey]
                if not lastAlert or (now - lastAlert) >= FRIEND_ALERT_DEBOUNCE then
                    friendAlertLastAt[aKey] = now
                    local shownName = nextInfo.shownName or "?"
                    local areaTxt = (nextInfo.area and nextInfo.area ~= "") and nextInfo.area or L["Online"]
                    local srcTag = nextInfo.isOptedGuild and not nextInfo.isFriend and L["Guild"]
                        or (nextInfo.sources and nextInfo.sources.bnet and not (nextInfo.sources and nextInfo.sources.friend) and L["Battle.net"])
                        or L["Friend Online"]

                    local didToast = false
                    local didChat = false
                    local didSound = false
                    local focusSilenced = Compat.IsFocusSilenced and Compat.IsFocusSilenced(nextInfo.lookupKey or nextInfo.shownName, nextInfo.bnetAccountID)
                    if (not focusSilenced) and settings.friendOnlineAlertToast ~= false then
                        ns:Emit("ADDON_MESSAGE_NOTIFY", {
                            id = "friend:" .. aKey .. ":" .. tostring(now),
                            kind = "FRIEND_ONLINE",
                            sourceTag = srcTag,
                            sender = shownName,
                            senderClass = nextInfo.classFile,
                            lookupKey = nextInfo.lookupKey,
                            bnetAccountID = nextInfo.bnetAccountID,
                            text = (nextInfo.area and nextInfo.area ~= "") and (L["Online"] .. " · " .. nextInfo.area) or L["Is now online in WoW: Forever"],
                            searchHint = shownName,
                            ts = now,
                            priority = 1,
                        })
                        didToast = true
                    end
                    if (not focusSilenced) and settings.friendOnlineAlertChat == true then
                        local hex = Compat.ClassHex(nextInfo.classFile)
                        local link = "|Haddon:SCentral:social:" .. shownName .. "|h|cff59c7ff[" .. L["Social"] .. "]|r|h"
                        local lineText = (nextInfo.area and nextInfo.area ~= "")
                            and L["%s came online (%s) %s"]:format(hex .. shownName .. "|r", areaTxt, link)
                            or L["%s came online %s"]:format(hex .. shownName .. "|r", link)
                        ns:Print("%s", lineText)
                        didChat = true
                    end
                    if (not focusSilenced) and (didToast or didChat) and settings.friendOnlineAlertSound ~= false and PlaySound and SOUNDKIT then
                        local sid = SOUNDKIT.MAP_PING or 3175
                        if sid then
                            pcall(PlaySound, sid, "Master")
                            didSound = true
                        end
                    end
                    if nextInfo.lookupKey and nextInfo.lookupKey ~= "" then
                        notifiedByLookup[nextInfo.lookupKey] = {
                            toast = didToast,
                            chat = didChat,
                            sound = didSound,
                        }
                    end
                end
            end
        end
    end

    -- 2. Offline logoffs / disconnects
    for oldKey, oldInfo in pairs(prevWowOnline) do
        if not nextWow[oldKey] then
            local shownName = type(oldInfo) == "table" and oldInfo.shownName or nil
            if not shownName then
                shownName = oldKey:match("^char:(.+)$") or oldKey:match("^bnet:(.+)$") or oldKey
            end
            local classFile = type(oldInfo) == "table" and oldInfo.classFile or nil
            local lookupKey = type(oldInfo) == "table" and oldInfo.lookupKey or nil
            local bnetAccId = type(oldInfo) == "table" and oldInfo.bnetAccountID or nil
            local isOptedGuild = type(oldInfo) == "table" and (oldInfo.isOptedGuild == true)
            local isFriend = (type(oldInfo) ~= "table") or (oldInfo.isFriend == true)
            local isFav = type(oldInfo) == "table" and oldInfo.isFav or false
            local sources = type(oldInfo) == "table" and oldInfo.sources or nil

            local wlEntry = lookupKey and wl and wl[lookupKey]
            local isMuted = Store.IsPlayerNotifyMuted and Store:IsPlayerNotifyMuted(lookupKey, wlEntry, bnetAccId)
            local shouldNotify = (not isMuted) and (isOptedGuild or alertMode == "all" or (alertMode == "favorites" and isFav))
            if shouldNotify then
                local lastAlert = friendAlertLastAt[oldKey]
                if not lastAlert or (now - lastAlert) >= FRIEND_ALERT_DEBOUNCE then
                    friendAlertLastAt[oldKey] = now
                    local srcTag = isOptedGuild and not isFriend and L["Guild"]
                        or (sources and sources.bnet and not (sources and sources.friend) and L["Battle.net"])
                        or L["Friend Offline"]

                    local focusSilenced = Compat.IsFocusSilenced and Compat.IsFocusSilenced(lookupKey or shownName, bnetAccId)
                    if (not focusSilenced) and settings.friendOfflineAlertToast ~= false then
                        ns:Emit("ADDON_MESSAGE_NOTIFY", {
                            id = "friend:off:" .. oldKey .. ":" .. tostring(now),
                            kind = "FRIEND_OFFLINE",
                            sourceTag = srcTag,
                            sender = shownName,
                            senderClass = classFile,
                            lookupKey = lookupKey,
                            bnetAccountID = bnetAccId,
                            text = L["Disconnected"],
                            searchHint = shownName,
                            ts = now,
                            priority = 1,
                        })
                    end
                    if (not focusSilenced) and settings.friendOfflineAlertChat == true then
                        local hex = Compat.ClassHex(classFile)
                        local link = "|Haddon:SCentral:social:" .. shownName .. "|h|cff59c7ff[" .. L["Social"] .. "]|r|h"
                        local lineText = L["%s disconnected %s"]:format(hex .. shownName .. "|r", link)
                        ns:Print("%s", lineText)
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
                if row.friendOnline == true then stats.friendOnline = stats.friendOnline + 1 end
            end
            if row.sources.bnet then
                stats.bnetTotal = stats.bnetTotal + 1
                if row.bnetOnline == true then
                    if row.bnetState == "wow_forever" then
                        stats.bnetOnlineWoW = stats.bnetOnlineWoW + 1
                    else
                        stats.bnetOnlineApp = stats.bnetOnlineApp + 1
                    end
                end
            end
        end
    end
    return stats
end

local SCANNERS = { ScanCharacterFriends, ScanGuild, ScanBattleNet }

function Social:EnsureFullGuildScan()
    if not self._rosterRanksIncludeOffline then
        self:Scan()
    end
end

function Social:Scan()
    lastScanAt = (GetTime and GetTime()) or 0
    if Compat.SyncRosterForeverNames then
        Compat.SyncRosterForeverNames(false, true)
    end

    wipe(verifiedFriendConnected)
    local onlineCtx = NewScanContext()
    local dirCtx = NewScanContext()
    local wlObsMap = {}
    local nextBNetWatchlistOnline = {}
    for _, scanner in ipairs(SCANNERS) do
        local ok, err = pcall(scanner, onlineCtx, dirCtx, wlObsMap, nextBNetWatchlistOnline)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end

    local wlTable = Store.GetWatchlistTable and Store:GetWatchlistTable()
    -- Suppress stale guild/cache online ghosts for Battle.net siblings when only another alt is active on that BNet account.
    for _, bRec in pairs(bnetInfoByAccId) do
        if type(bRec) == "table" and bRec.online and bRec.activeForeverLookups and bRec.activeLookupKey and type(bRec.chars) == "table" then
            for otherLk, otherDisp in pairs(bRec.chars) do
                if not bRec.activeForeverLookups[otherLk] and verifiedFriendConnected[otherLk] ~= true then
                    local existingObs = wlObsMap[otherLk]
                    if existingObs and existingObs.online == true then
                        if not (existingObs.altLookupKey and bRec.activeForeverLookups[existingObs.altLookupKey]) then
                            existingObs.online = false
                        end
                    elseif type(wlTable) == "table" then
                        local wlRec = wlTable[otherLk]
                        if type(wlRec) == "table" and wlRec.status == "online" and not (wlRec.watchAllAlts == true and wlRec.activeAltLookup and bRec.activeForeverLookups[wlRec.activeAltLookup]) then
                            QueueWatchlistObs(wlObsMap, otherLk, wlRec.displayName or otherDisp, false, nil, nil, nil, nil, "bnet")
                            if wlObsMap[otherLk] then
                                wlObsMap[otherLk].online = false
                                wlObsMap[otherLk].clearAlt = true
                            end
                        end
                    end
                end
            end
        end
    end
    if type(wlTable) == "table" and next(wlTable) ~= nil then
        for lookupKey, prevDispName in pairs(prevBNetWatchlistOnline) do
            if not onlineCtx.byLookup[lookupKey] and not wlObsMap[lookupKey] then
                if verifiedFriendConnected[lookupKey] == false then
                    QueueWatchlistObs(wlObsMap, lookupKey, prevDispName, false, nil, nil, nil, nil, "friend")
                else
                    -- Battle.net account went offline or invisible; do not force character offline without in-game check.
                    wlObsMap[lookupKey] = {
                        lookupKey = lookupKey,
                        displayName = prevDispName,
                        online = nil,
                        status = "unknown",
                        clearAlt = true,
                        source = nil,
                    }
                    if ns.Chat and ns.Chat.QueuePresenceProbe then
                        ns.Chat:QueuePresenceProbe(lookupKey, prevDispName, true)
                    end
                end
            end
        end
        local bnetReady = (not BNConnected or Safe.Value(BNConnected()) == true)
            and (((GetTime and GetTime()) or 0) - loginMonoAt) >= 8.0
        for wlKey, wlEntry in pairs(wlTable) do
            if type(wlEntry) == "table" and wlEntry.status == "online" then
                local lk = wlEntry.id or wlKey
                local altOn = wlEntry.watchAllAlts == true and wlEntry.activeAltLookup and onlineCtx.byLookup[wlEntry.activeAltLookup] ~= nil
                if lk and not wlObsMap[lk] and not onlineCtx.byLookup[lk] and not altOn then
                    local dirKey = dirCtx.byLookup[lk]
                    local dirRow = dirKey and dirCtx.map[dirKey]
                    local isAuthoritativeCharOffline = dirRow and not IsRowWoWOnline(dirRow)
                        and dirRow.sources and (dirRow.sources.friend == true or (dirRow.sources.guild == true and wlEntry.source == "guild"))
                    if isAuthoritativeCharOffline then
                        local src = (dirRow.sources.friend and "friend") or (dirRow.sources.guild and "guild") or wlEntry.source
                        QueueWatchlistObs(wlObsMap, lk, wlEntry.displayName or dirRow.displayName, false, nil, nil, nil, nil, src)
                        if wlObsMap[lk] then wlObsMap[lk].clearAlt = true end
                    elseif wlEntry.source == "bnet" and bnetReady then
                        wlObsMap[lk] = {
                            lookupKey = lk,
                            displayName = wlEntry.displayName,
                            online = nil,
                            status = "unknown",
                            clearAlt = true,
                            source = nil,
                        }
                        if ns.Chat and ns.Chat.QueuePresenceProbe then
                            ns.Chat:QueuePresenceProbe(lk, wlEntry.displayName, true)
                        end
                    end
                end
            end
        end
        local nowTs = time()
        for wlKey, wlEntry in pairs(wlTable) do
            if type(wlEntry) == "table" and not wlEntry.isSessionBNet and wlEntry.status == "online" then
                local lk = wlEntry.id or wlKey
                local pendingObs = lk and wlObsMap[lk]
                local stayingOnline = not pendingObs or (pendingObs.online ~= false and pendingObs.status ~= "unknown")
                if stayingOnline then
                    local activeLk = (wlEntry.watchAllAlts == true and wlEntry.activeAltLookup) or lk
                    local activeDisp = (wlEntry.watchAllAlts == true and wlEntry.activeAltName) or wlEntry.displayName
                    if activeLk and activeDisp and not onlineCtx.byLookup[activeLk] then
                        local effClass = (wlEntry.watchAllAlts == true and wlEntry.activeAltClass) or wlEntry.classFile
                        local effLevel = (wlEntry.watchAllAlts == true and wlEntry.activeAltLevel) or wlEntry.level
                        local wlGuid = (activeLk == lk) and wlEntry.guid or nil
                        local wlPatch = {
                            displayName = activeDisp,
                            lookupKey = activeLk,
                            hasCharacterName = true,
                            guid = wlGuid,
                            level = effLevel,
                            classFile = effClass,
                            area = wlEntry.area or "",
                            guild = wlEntry.guild,
                            online = true,
                            samePool = true,
                            sameFaction = true,
                            bnetState = "wow_forever",
                            lastSeen = wlEntry.lastSeen or nowTs,
                            sources = { watchlist = true },
                        }
                        local onKey = FindMergeKey(onlineCtx, wlGuid or ("char:" .. activeLk), wlGuid, nil, activeLk, true)
                        MergeEntry(onlineCtx, onKey, wlPatch)
                        local dirKey = FindMergeKey(dirCtx, wlGuid or ("char:" .. activeLk), wlGuid, nil, activeLk, true)
                        MergeEntry(dirCtx, dirKey, wlPatch)
                    end
                end
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
    local dirByLookup, dirByKey, dirByBNet = {}, {}, {}
    for k, row in pairs(dirCtx.map) do
        dirByKey[k] = row
        if row.bnetAccountID then
            dirByBNet[row.bnetAccountID] = row
        end
        if row.lookupKey and row.lookupKey ~= "" then
            local prev = dirByLookup[row.lookupKey]
            local rowForever = (row.samePool ~= false)
            local prevForever = prev and (prev.samePool ~= false)
            if not prev
                or (rowForever and not prevForever)
                or (rowForever == prevForever and row.online and not prev.online)
            then
                dirByLookup[row.lookupKey] = row
            end
        end
    end
    Store.socialDirectoryByKey = dirByKey
    Store.socialDirectoryByLookup = dirByLookup
    Store.socialDirectoryByBNet = dirByBNet

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
    if ns.Watchlist and ns.Watchlist.ExpireStaleOnlineEntries then
        ns.Watchlist:ExpireStaleOnlineEntries(true)
    end

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

local function CollectSavedFavoriteKeys(seenKeys)
    if not Store or not Store.IsSocialFavorite then return end
    local function ScanBucket(tbl)
        if type(tbl) ~= "table" then return end
        for rawKey, rec in pairs(tbl) do
            if type(rawKey) == "string" and rawKey ~= "" and type(rec) == "table" and rec.favorite == true then
                local cand = rec.fullName or rec.displayName or rec.id or rawKey
                local parsed = (Compat and Compat.ParseCharacterName) and Compat.ParseCharacterName(cand) or nil
                local normKey = (parsed and parsed.lookupKey) or (type(rawKey) == "string" and rawKey:lower()) or nil
                if normKey and normKey ~= "" and not seenKeys[normKey] and Store:IsSocialFavorite(normKey) then
                    seenKeys[normKey] = true
                end
            end
        end
    end
    if Store.GetSocialMetaTable then ScanBucket(Store:GetSocialMetaTable()) end
    if Store.GetFriendPresenceTable then ScanBucket(Store:GetFriendPresenceTable()) end
    if Store.GetWatchlistTable then ScanBucket(Store:GetWatchlistTable()) end
end

function Social:GetFavoriteCount()
    local seen = {}
    local count = 0
    for _, item in pairs(Store.socialDirectory or {}) do
        local key = item and item.lookupKey
        if key and not seen[key] and Store.IsSocialFavorite and Store:IsSocialFavorite(key) == true then
            seen[key] = true
            count = count + 1
        end
    end
    local savedKeys = {}
    CollectSavedFavoriteKeys(savedKeys)
    for normKey in pairs(savedKeys) do
        if not seen[normKey] then
            local parsed = Compat and Compat.ParseCharacterName and Compat.ParseCharacterName(normKey) or nil
            local disp = (parsed and parsed.displayName) or normKey
            if not (Compat and Compat.IsMe and Compat.IsMe(disp)) then
                seen[normKey] = true
                count = count + 1
            end
        end
    end
    return count
end

--- Mark a Battle.net character as opposing faction when an in-game whisper fails while they are online on Battle.net.
function Social:MarkBNetOppositeFaction(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then return false end
    local info = self:GetBNetLinkInfo(lookupKey)
    if not (info and info.isBNet and info.online) then
        return false
    end
    local myEngFaction = Compat.PlayerFaction()
    local oppFaction = (myEngFaction == "Horde") and "Alliance" or "Horde"
    if bnetFactionByLookup[lookupKey] == oppFaction then
        return false
    end
    bnetFactionByLookup[lookupKey] = oppFaction
    local dirRow = Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookupKey]
    if dirRow then
        dirRow.faction = oppFaction
        dirRow.sameFaction = false
    end
    ns:Emit("SOCIAL_UPDATED")
    ns:Emit("WATCHLIST_UPDATED")
    return true
end

--- Return live session-only Battle.net account/alt association for a character lookupKey (never persisted).
function Social:GetBNetLinkInfo(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end
    local dirRow = Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookupKey]
    local accId = bnetAccByLookup[lookupKey] or (dirRow and dirRow.sources and dirRow.sources.bnet and dirRow.bnetAccountID)
    if not accId and Store.GetAllLinkedCharacters then
        local alts = Store:GetAllLinkedCharacters(lookupKey)
        if type(alts) == "table" then
            for _, alt in ipairs(alts) do
                local altKey = type(alt) == "table" and alt.lookupKey or nil
                if altKey and bnetAccByLookup[altKey] then
                    accId = bnetAccByLookup[altKey]
                    break
                end
            end
        end
    end
    if not accId then
        return nil
    end
    local info = bnetInfoByAccId[accId]
    local otherChars = {}
    if info and type(info.chars) == "table" then
        for lk, disp in pairs(info.chars) do
            if lk ~= lookupKey and disp and disp ~= "" then
                otherChars[#otherChars + 1] = disp
            end
        end
        table.sort(otherChars)
    end
    local resolvedFac = bnetFactionByLookup[lookupKey] or (dirRow and dirRow.faction)
    local myEng = Compat.PlayerFaction()
    local isSameFac
    if bnetFactionByLookup[lookupKey] then
        isSameFac = (bnetFactionByLookup[lookupKey] == myEng)
    elseif dirRow and dirRow.sameFaction ~= nil then
        isSameFac = dirRow.sameFaction
    elseif resolvedFac then
        isSameFac = (resolvedFac == myEng)
    else
        isSameFac = true
    end
    return {
        isBNet = true,
        bnetAccountID = accId,
        bnetName = (info and info.bnetName) or (dirRow and dirRow.bnetName) or nil,
        online = (info and info.online == true) or (dirRow and dirRow.online == true) or false,
        activeLookupKey = info and info.activeLookupKey or nil,
        activeDisplayName = info and info.activeDisplayName or nil,
        activeLookupKeys = info and info.activeForeverLookups or nil,
        faction = resolvedFac,
        sameFaction = isSameFac,
        otherChars = otherChars,
    }
end

--- Return live Battle.net friend accounts sorted online-first for Watchlist / Social pickers (session RAM only).
function Social:GetBNetFriendsList()
    local byAcc = {}
    for _, row in pairs(Store.socialDirectory or {}) do
        if type(row) == "table" and row.sources and row.sources.bnet and row.bnetAccountID then
            local accId = row.bnetAccountID
            local prev = byAcc[accId]
            local rowRank = (row.bnetState == "wow_forever" and 3) or (row.online and 2) or 1
            local prevRank = prev and ((prev.bnetState == "wow_forever" and 3) or (prev.online and 2) or 1) or 0
            if not prev or rowRank > prevRank then
                local bRec = bnetInfoByAccId[accId]
                local charsMap = {}
                if bRec and type(bRec.chars) == "table" then
                    for lk, disp in pairs(bRec.chars) do
                        charsMap[lk] = disp
                    end
                end
                if row.hasCharacterName ~= false and row.lookupKey and row.displayName then
                    charsMap[row.lookupKey] = row.displayName
                end
                byAcc[accId] = {
                    bnetAccountID = accId,
                    bnetName = row.bnetName or (bRec and bRec.bnetName) or row.displayName or "Battle.net",
                    displayName = row.displayName,
                    lookupKey = (row.hasCharacterName ~= false) and row.lookupKey or (bRec and bRec.activeLookupKey) or nil,
                    hasCharacterName = (row.hasCharacterName ~= false) or (bRec and bRec.activeLookupKey ~= nil),
                    online = row.online == true,
                    bnetState = row.bnetState or "offline",
                    activeLookupKey = bRec and bRec.activeLookupKey or nil,
                    activeDisplayName = bRec and bRec.activeDisplayName or nil,
                    classFile = row.classFile,
                    level = row.level,
                    area = row.area,
                    richPresence = row.richPresence,
                    clientProgram = row.clientProgram,
                    knownChars = charsMap,
                }
            end
        end
    end
    local out = {}
    for _, item in pairs(byAcc) do
        out[#out + 1] = item
    end
    table.sort(out, function(a, b)
        local ra = (a.bnetState == "wow_forever" and 3) or (a.online and 2) or 1
        local rb = (b.bnetState == "wow_forever" and 3) or (b.online and 2) or 1
        if ra ~= rb then return ra > rb end
        return tostring(a.bnetName or a.displayName or ""):lower() < tostring(b.bnetName or b.displayName or ""):lower()
    end)
    return out
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
            tier = isFav and 9 or 8
        elseif item.bnetState == "wow_other" then
            tier = isFav and 7 or 6
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
    if srcFilter == "blocked" then
        local ignList = Store and Store.GetAccountIgnoresList and Store:GetAccountIgnoresList() or {}
        local dirByLk = Store and Store.socialDirectoryByLookup or {}
        for _, ign in ipairs(ignList) do
            local existing = ign.lookupKey and dirByLk[ign.lookupKey]
            local row = {
                lookupKey = ign.lookupKey,
                displayName = (existing and existing.displayName) or ign.name or ign.lookupKey,
                classFile = existing and existing.classFile or nil,
                level = existing and existing.level or 0,
                area = existing and existing.area or "",
                guild = existing and existing.guild or nil,
                online = existing and existing.online == true or false,
                lastSeen = existing and existing.lastSeen or ign.addedAt or 0,
                sources = existing and existing.sources or { blocked = true },
                isAccountIgnored = true,
                ignoreReason = ign.reason,
                ignoreNote = ign.note,
                ignoreExpiresAt = ign.expiresAt,
                ignoreHideChat = ign.hideChat,
                ignoreAddedAt = ign.addedAt,
                hasCharacterName = true,
            }
            out[#out + 1] = row
        end
        return out
    end

    local function MatchesFolderFilter(meta)
        if folderFilter == "__none" then
            return not (meta and meta.folder and meta.folder ~= "")
        elseif folderFilter ~= "all" then
            return (meta and meta.folder == folderFilter) == true
        end
        return true
    end

    local function IsBNetFriendKnownWoWPlayer(item, isFav)
        if not (item and item.sources and item.sources.bnet == true) then
            return true
        end
        if item.sources.friend == true or item.sources.guild == true or isFav then
            return true
        end
        if item.bnetState == "wow_forever" or item.bnetState == "wow_other" then
            return true
        end
        local accId = item.bnetAccountID
        local bRec = accId and bnetInfoByAccId[accId] or nil
        if bRec and (bRec.seenWoW == true or (type(bRec.chars) == "table" and next(bRec.chars) ~= nil)) then
            return true
        end
        local lk = item.lookupKey
        if lk and lk ~= "" and Store then
            if Store.GetFriendPresence and Store:GetFriendPresence(lk) then return true end
            if Store.GetSocialMeta and Store:GetSocialMeta(lk) then return true end
            local wl = Store.GetWatchlistTable and Store:GetWatchlistTable()
            if wl and wl[lk] then return true end
        end
        return false
    end

    local emittedFavKeys = (srcFilter == "fav" or srcFilter == "all") and {} or nil
    for _, item in pairs(Store.socialDirectory or {}) do
        local key = item.lookupKey
        local meta = key and Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(key)
            or (key and Store.GetSocialMeta and Store:GetSocialMeta(key))
            or nil
        local isFav = (key ~= nil and Store.IsSocialFavorite and Store:IsSocialFavorite(key)) == true
        local isSC = key ~= nil and hasChat and ns.Chat:IsLookupKeyVerified(key) == true
        local comp = key and Store.GetRecentCompanion and Store:GetRecentCompanion(key) or nil

        local srcMatch = false
        if not IsBNetFriendKnownWoWPlayer(item, isFav) then
            srcMatch = false
        elseif srcFilter == "all" then
            srcMatch = isFav or item.online or showOffline
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
            srcMatch = isFav
        elseif srcFilter == "sc" then
            srcMatch = isSC and (item.online or showOffline)
        elseif srcFilter == "good" then
            srcMatch = (meta and meta.flag == "GOOD") == true and (item.online or showOffline)
        elseif srcFilter == "recent" then
            srcMatch = comp ~= nil
        end

        local folderMatch = MatchesFolderFilter(meta)

        if srcMatch and folderMatch then
            out[#out + 1] = item
            scoreMap[item] = ComputeSmartScore(item, meta, isFav, isSC, comp ~= nil)
            if emittedFavKeys and key then
                emittedFavKeys[key] = true
            end
        end
    end

    if (srcFilter == "fav" or srcFilter == "all") and Store then
        local savedFavKeys = {}
        CollectSavedFavoriteKeys(savedFavKeys)
        local wlTbl = Store.GetWatchlistTable and Store:GetWatchlistTable() or {}
        local presTbl = Store.GetFriendPresenceTable and Store:GetFriendPresenceTable() or {}
        for normKey in pairs(savedFavKeys) do
            if not emittedFavKeys[normKey] then
                emittedFavKeys[normKey] = true
                local wl = wlTbl[normKey]
                local pres = presTbl[normKey]
                local parsed = (Compat and Compat.ParseCharacterName) and Compat.ParseCharacterName(normKey) or nil
                local disp = (wl and wl.displayName) or (parsed and parsed.displayName) or normKey
                if not (Compat and Compat.IsMe and Compat.IsMe(disp, wl and wl.guid)) then
                    local meta = (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(normKey))
                        or (Store.GetSocialMeta and Store:GetSocialMeta(normKey))
                        or nil
                    if MatchesFolderFilter(meta) then
                        local isSC = hasChat and ns.Chat:IsLookupKeyVerified(normKey) == true
                        local comp = Store.GetRecentCompanion and Store:GetRecentCompanion(normKey) or nil
                        local synth = {
                            lookupKey = normKey,
                            displayName = disp,
                            classFile = (wl and wl.classFile) or (pres and pres.lastClass) or nil,
                            level = (wl and wl.level) or (pres and pres.lastLevel) or 0,
                            area = (wl and wl.area) or (pres and pres.lastArea) or "",
                            guild = (wl and wl.guild) or nil,
                            online = (wl and wl.status == "online") == true,
                            lastSeen = (wl and wl.lastSeen) or (pres and pres.lastSeen) or (meta and meta.updatedAt) or 0,
                            guid = wl and wl.guid or nil,
                            hasCharacterName = true,
                            samePool = true,
                            sources = { watchlist = (wl ~= nil) or nil, saved = true },
                        }
                        out[#out + 1] = synth
                        scoreMap[synth] = ComputeSmartScore(synth, meta, true, isSC, comp ~= nil)
                    end
                end
            end
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
    local anyUiOpen = (_G.SocialCentralFrame and _G.SocialCentralFrame.IsShown and _G.SocialCentralFrame:IsShown())
        or (_G.FriendsFrame and _G.FriendsFrame.IsShown and _G.FriendsFrame:IsShown())
        or (_G.CommunitiesFrame and _G.CommunitiesFrame.IsShown and _G.CommunitiesFrame:IsShown())
        or (_G.SocialCentralGuildEmbeddedFrame and _G.SocialCentralGuildEmbeddedFrame.IsShown and _G.SocialCentralGuildEmbeddedFrame:IsShown())
    local minGap = anyUiOpen and 4.5 or 8.0
    local minWait = math.max(anyUiOpen and 2.0 or 3.0, tonumber(delay) or (anyUiOpen and 2.0 or 3.0))
    local now = (GetTime and GetTime()) or 0
    if lastScanAt > 0 and (now - lastScanAt) < minGap then
        minWait = math.max(minWait, minGap - (now - lastScanAt))
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
        C_Timer.NewTicker(20, function()
            if not IsGuildOrSocialUiOpen() then
                -- When UI is closed, native Blizzard push events (FRIENDLIST_UPDATE, GUILD_ROSTER_UPDATE, BN_FRIEND_*)
                -- keep social lists up to date with zero polling overhead.
                return
            end
            self:RequestRosters(false)
            self:Scan()
        end)
    end
end
