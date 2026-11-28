local _, ns = ...

local Compat = ns.Compat
local Safe = ns.Safe

-- Unified social store bridging live Social rosters, Nearby passive sightings,
-- Account Alts, and Watchlist entries.
local Store = {
    social = {},       -- [key] -> row
    nearby = {},       -- [lookupKey] -> row
    guildRosterRanks = {}, -- [lookupKey] -> { rankIndex, rankName, guid, displayName, online }
    guildInfo = {
        inGuild = false,
        name = nil,
        motd = nil,
        onlineCount = 0,
        totalCount = 0,
        myRankIndex = nil,
        myRankName = nil,
        isGuildLeader = false,
    },
}

ns.Store = Store

function Store:EnsureScopedBucket(root, trackedField)
    if type(root) ~= "table" then return {} end
    local scope = Compat.ScopeKey()
    if (type(root[scope]) ~= "table" or next(root[scope]) == nil)
        and self.NormalizeLegacyRealmScopes
        and not self._normalizingScopes
    then
        self._autoRescuedScopes = self._autoRescuedScopes or {}
        local tag = tostring(trackedField or "scope") .. "|" .. scope
        if not self._autoRescuedScopes[tag] then
            self._autoRescuedScopes[tag] = true
            for k, v in pairs(root) do
                if k ~= scope and type(v) == "table" and next(v) ~= nil then
                    self._normalizingScopes = true
                    self:NormalizeLegacyRealmScopes()
                    self._normalizingScopes = false
                    scope = Compat.ScopeKey()
                    break
                end
            end
        end
    end
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

function Store:InvalidateScopeCaches()
    self._clanScopeGuild = nil
    self._clanScopeCached = nil
    self._wlIndexDirty = true
    if ns.Watchlist then
        ns.Watchlist._wlIndexDirty = true
    end
    self._socialFoldersCache = nil
    self._linkedAltsDirty = true
end

function Store:GetWatchlistTable()
    return self:EnsureScopedBucket(ns.db and ns.db.watchlist, "watchlist")
end

local CLAN_PEER_TTL = 12 * 3600
local CLAN_EVENT_TTL = 14 * 86400
local normalizedClanBuckets = setmetatable({}, { __mode = "k" })

function Store:GetClanScopeData(forcePrune)
    local root = ns.db and ns.db.clan
    if not root then
        return { myTag = "NONE", myNote = "", peers = {}, events = {} }
    end
    local inGuild = (self.guildInfo and self.guildInfo.inGuild) or (IsInGuild and ns.Safe.Value(IsInGuild()) == true)
    local guildName = self.guildInfo and self.guildInfo.name
    if inGuild and (not guildName or guildName == "") then
        if GetGuildInfo then
            guildName = ns.Safe.String(ns.Safe.Call(GetGuildInfo, "player"))
        end
        if (not guildName or guildName == "") and ns.db and ns.db.alts then
            local altRec = self.GetCurrentAltRecord and self:GetCurrentAltRecord()
                or (Compat.CharacterKey and ns.db.alts[Compat.CharacterKey()])
            if altRec and altRec.guild and altRec.guild ~= "" then
                guildName = altRec.guild
            end
        end
        if guildName and guildName ~= "" and self.guildInfo then
            self.guildInfo.inGuild = true
            self.guildInfo.name = guildName
        end
    end
    local scopeGuild = inGuild and (guildName and guildName ~= "" and guildName or "guild") or "_noguild"
    local scope
    if self._clanScopeGuild == scopeGuild and self._clanScopeCached then
        scope = self._clanScopeCached
    else
        scope = Compat.ScopeKey() .. "::" .. Compat.Plain(scopeGuild)
        self._clanScopeGuild = scopeGuild
        self._clanScopeCached = scope
    end
    local bucket = root[scope]
    if type(bucket) ~= "table" then
        bucket = { myTag = "NONE", myNote = "", peers = {}, events = {} }
        root[scope] = bucket
    end
    if not normalizedClanBuckets[bucket] then
        if type(bucket.peers) ~= "table" then bucket.peers = {} end
        if type(bucket.events) ~= "table" then bucket.events = {} end
        if type(bucket.lfg) ~= "table" then bucket.lfg = {} end
        if type(bucket.myProf1) ~= "string" or bucket.myProf1 == "" then bucket.myProf1 = "NONE" end
        if type(bucket.myProf2) ~= "string" or bucket.myProf2 == "" then bucket.myProf2 = "NONE" end
        if type(bucket.myProf1Rank) ~= "string" then bucket.myProf1Rank = "" end
        if type(bucket.myProf2Rank) ~= "string" then bucket.myProf2Rank = "" end
        if type(bucket.myCraftNote) ~= "string" then bucket.myCraftNote = "" end
        if type(bucket.diplomacy) ~= "table" then
            bucket.diplomacy = { rev = 0, updatedAt = 0, updatedBy = "", guilds = {} }
        end
        if type(bucket.diplomacy.guilds) ~= "table" then
            bucket.diplomacy.guilds = {}
        end
        if type(bucket.alliance) ~= "table" then
            bucket.alliance = {
                enabled = false,
                name = "",
                token = "",
                accessMode = "WHITELIST", -- "ALL" or "WHITELIST"
                whitelist = {},           -- [lookupKey] = true
                managers = {},            -- [lookupKey] = true
                alliedGuilds = {},        -- [normGuildKey] = { name = ..., token = ..., leader = ... }
            }
        end
        if type(bucket.alliance.whitelist) ~= "table" then bucket.alliance.whitelist = {} end
        if type(bucket.alliance.managers) ~= "table" then bucket.alliance.managers = {} end
        if type(bucket.alliance.alliedGuilds) ~= "table" then bucket.alliance.alliedGuilds = {} end
        if type(bucket.clanInfo) ~= "table" then
            bucket.clanInfo = {
                rev = 0,
                updatedAt = 0,
                updatedBy = "",
                editMode = "OFFICERS",
                summary = "",
                rules = "",
                schedule = "",
                contacts = "",
            }
        end
        if bucket.clanInfo.editMode ~= "ALL" and bucket.clanInfo.editMode ~= "OFFICERS" then
            bucket.clanInfo.editMode = "OFFICERS"
        end
        if type(bucket.hierarchy) ~= "table" then
            bucket.hierarchy = {
                rev = 0,
                updatedAt = 0,
                updatedBy = "",
                diplomacyMode = "LEADER",
                diplomacyMaxRank = 1,
                infoMode = (bucket.clanInfo.editMode == "ALL") and "ALL" or "OFFICERS",
                infoMaxRank = 1,
                eventModMode = "OFFICERS",
                eventModMaxRank = 1,
                allianceMinRank = -1,
            }
        else
            local h = bucket.hierarchy
            if h.diplomacyMode ~= "LEADER" and h.diplomacyMode ~= "OFFICERS" and h.diplomacyMode ~= "RANK" then
                h.diplomacyMode = "LEADER"
            end
            h.diplomacyMaxRank = math.max(0, math.min(9, tonumber(h.diplomacyMaxRank) or 1))
            if h.infoMode ~= "LEADER" and h.infoMode ~= "OFFICERS" and h.infoMode ~= "RANK" and h.infoMode ~= "ALL" then
                h.infoMode = (bucket.clanInfo.editMode == "ALL") and "ALL" or "OFFICERS"
            end
            h.infoMaxRank = math.max(0, math.min(9, tonumber(h.infoMaxRank) or 1))
            if h.eventModMode ~= "LEADER" and h.eventModMode ~= "OFFICERS" and h.eventModMode ~= "RANK" then
                h.eventModMode = "OFFICERS"
            end
            h.eventModMaxRank = math.max(0, math.min(9, tonumber(h.eventModMaxRank) or 1))
            local ar = tonumber(h.allianceMinRank)
            h.allianceMinRank = (ar and ar >= 0 and ar <= 9) and ar or -1
        end
        normalizedClanBuckets[bucket] = true
    end

    self._clanPruneAt = self._clanPruneAt or {}
    local nowClock = (GetTime and GetTime()) or 0
    local lastPruneAt = self._clanPruneAt[scope]
    if forcePrune or not lastPruneAt or (nowClock - lastPruneAt) >= 20 then
        self._clanPruneAt[scope] = nowClock
        local now = time()
        for k, p in pairs(bucket.peers) do
            if type(p) ~= "table" or (p.updatedAt and (now - p.updatedAt) > CLAN_PEER_TTL) then
                bucket.peers[k] = nil
            end
        end
        for id, evt in pairs(bucket.events) do
            if type(evt) ~= "table" or (evt.updatedAt and (now - evt.updatedAt) > CLAN_EVENT_TTL) then
                bucket.events[id] = nil
            end
        end
        for k, lfg in pairs(bucket.lfg) do
            if type(lfg) ~= "table" or (lfg.updatedAt and (now - lfg.updatedAt) > 1800) then
                bucket.lfg[k] = nil
            end
        end
    end

    return bucket
end

function Store:GetCurrentAltKey()
    local safeStr = ns.Safe and ns.Safe.String
    local safeCall = ns.Safe and ns.Safe.Call
    local myGuid = (safeStr and safeCall and UnitGUID) and safeStr(safeCall(UnitGUID, "player")) or nil
    local legacyKey = Compat.CharacterKey and Compat.CharacterKey() or nil
    if myGuid and myGuid ~= "" then
        local guidKey = "guid:" .. myGuid
        local alts = ns.db and ns.db.alts
        if type(alts) == "table" and legacyKey and legacyKey ~= guidKey then
            local legacyRec = alts[legacyKey]
            if type(legacyRec) == "table" and (not legacyRec.guid or legacyRec.guid == "" or legacyRec.guid == myGuid) then
                if type(alts[guidKey]) ~= "table" then
                    legacyRec.guid = myGuid
                    legacyRec.key = guidKey
                    legacyRec.legacyKey = legacyKey
                    alts[guidKey] = legacyRec
                    alts[legacyKey] = nil
                else
                    local targetRec = alts[guidKey]
                    targetRec.guid = myGuid
                    targetRec.key = guidKey
                    targetRec.legacyKey = legacyKey
                    if not targetRec.bank and type(legacyRec.bank) == "table" then
                        targetRec.bank = legacyRec.bank
                        targetRec.bankTotal = legacyRec.bankTotal
                        targetRec.bankFree = legacyRec.bankFree
                        targetRec.bankUpdatedAt = legacyRec.bankUpdatedAt
                    end
                    if not targetRec.recipes and type(legacyRec.recipes) == "table" then
                        targetRec.recipes = legacyRec.recipes
                    end
                    if not targetRec.craftCooldowns and type(legacyRec.craftCooldowns) == "table" then
                        targetRec.craftCooldowns = legacyRec.craftCooldowns
                    end
                    if not targetRec.reputations and type(legacyRec.reputations) == "table" then
                        targetRec.reputations = legacyRec.reputations
                    end
                    if not targetRec.lockouts and type(legacyRec.lockouts) == "table" then
                        targetRec.lockouts = legacyRec.lockouts
                    end
                    if not targetRec.marks and type(legacyRec.marks) == "table" then
                        targetRec.marks = legacyRec.marks
                    end
                    if not targetRec.mailSince and legacyRec.mailSince then
                        targetRec.mailSince = legacyRec.mailSince
                    end
                    if not targetRec.firstSeen and legacyRec.firstSeen then
                        targetRec.firstSeen = legacyRec.firstSeen
                    end
                    alts[legacyKey] = nil
                end
                if ns.Alts then
                    if ns.Alts._altBuckets then
                        ns.Alts._altBuckets[legacyKey] = nil
                    end
                    ns.Alts._itemIndexBuilt = false
                    ns.Alts.itemIndex = nil
                    ns.Alts._recipeSeq = (ns.Alts._recipeSeq or 0) + 1
                    ns.Alts._recipeIndexCache = nil
                end
            end
        end
        return guidKey
    end
    return legacyKey
end

function Store:GetCurrentAltRecord()
    local alts = ns.db and ns.db.alts
    if type(alts) ~= "table" then return nil end
    local curKey = self:GetCurrentAltKey()
    if curKey and type(alts[curKey]) == "table" then
        return alts[curKey]
    end
    local legacyKey = Compat.CharacterKey and Compat.CharacterKey() or nil
    return legacyKey and alts[legacyKey] or nil
end

--- Remove stale deleted/recreated same-world duplicate alt snapshots sharing exact full name & realm pool.
function Store:CleanupDuplicateSameWorldAlts(curKey, myGuid, fullName, realmPool, worldType)
    local alts = ns.db and ns.db.alts
    if type(alts) ~= "table" or not curKey or type(fullName) ~= "string" or fullName == "" then
        return 0
    end
    local lowerFn = (Compat and Compat.LowerUtf8) or string.lower
    local targetName = lowerFn(fullName:gsub("^%s+", ""):gsub("%s+$", ""))
    if targetName == "" then return 0 end
    local curPool = (type(realmPool) == "string" and realmPool ~= "" and Compat.RealmPool and Compat.RealmPool(realmPool))
        or (Compat.RealmPool and Compat.RealmPool(Compat.Realm()))
        or realmPool
    local curWorld = worldType or (Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm())) or nil
    local removed = 0
    local toRemove = nil
    for key, rec in pairs(alts) do
        if key ~= curKey and type(rec) == "table" then
            local recName = lowerFn((rec.fullName or rec.name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
            if recName == targetName then
                local rName = (type(rec.realmName) == "string" and rec.realmName ~= "") and rec.realmName or nil
                local rPool = (type(rec.realmPool) == "string" and rec.realmPool ~= "") and rec.realmPool or nil
                local recPool = (rName and Compat.RealmPool and Compat.RealmPool(rName))
                    or (rPool and Compat.RealmPool and Compat.RealmPool(rPool))
                    or nil
                local recWorld = rec.worldType
                    or (Compat.DetectWorldType and Compat.DetectWorldType(rName or rPool, rec.realmRaw))
                    or nil
                if recPool and recPool == curPool and (not curWorld or not recWorld or recWorld == curWorld) then
                    local recGuid = rec.guid
                    if (not myGuid or myGuid == "") or (not recGuid or recGuid == "" or recGuid ~= myGuid) then
                        toRemove = toRemove or {}
                        toRemove[#toRemove + 1] = key
                    end
                end
            end
        end
    end
    if toRemove then
        local dst = alts[curKey]
        for _, oldKey in ipairs(toRemove) do
            local ghost = alts[oldKey]
            if type(dst) == "table" and type(ghost) == "table" then
                if not dst.firstSeen and ghost.firstSeen then
                    dst.firstSeen = ghost.firstSeen
                end
            end
            alts[oldKey] = nil
            if ns.Alts and ns.Alts._altBuckets then
                ns.Alts._altBuckets[oldKey] = nil
            end
            removed = removed + 1
        end
        if removed > 0 and ns.Alts then
            ns.Alts._itemIndexBuilt = false
            ns.Alts.itemIndex = nil
            ns.Alts._recipeSeq = (ns.Alts._recipeSeq or 0) + 1
            ns.Alts._recipeIndexCache = nil
        end
    end
    return removed
end

local WORLD_TYPE_SORT = {
    PvP = 1,
    PvE = 2,
    ["RP-PvE"] = 3,
    ["RP-PvP"] = 4,
    RP = 5,
}

local function ResolveNormalizedWorldScope(scopeMode)
    if scopeMode == true then
        return "pool"
    elseif scopeMode == false then
        return "all"
    elseif Compat.NormalizeWorldScope then
        return Compat.NormalizeWorldScope(scopeMode)
    end
    return (scopeMode == "all") and "all" or "pool"
end

local function AltMatchesWorldScope(key, info, currentKey, curPool, curWorldType, scopeMode)
    local wantScope = ResolveNormalizedWorldScope(scopeMode)
    if wantScope == "all" then
        return true
    end
    local infoWorld, infoPool
    if Compat.GetAltWorldInfo then
        infoWorld, infoPool = Compat.GetAltWorldInfo(info)
    else
        local rName = (type(info.realmName) == "string" and info.realmName ~= "") and info.realmName or nil
        local rPool = (type(info.realmPool) == "string" and info.realmPool ~= "") and info.realmPool or nil
        infoPool = (rName and Compat.RealmPool(rName)) or (rPool and Compat.RealmPool(rPool)) or curPool
        infoWorld = info.worldType or (Compat.DetectWorldType and Compat.DetectWorldType(rName or rPool, info.realmRaw))
    end
    if wantScope:sub(1, 6) == "world:" then
        return infoWorld == wantScope:sub(7)
    elseif wantScope:sub(1, 5) == "pool:" then
        local targetPool = wantScope:sub(6)
        if Compat.RealmPool then
            targetPool = Compat.RealmPool(targetPool)
        end
        return infoPool == targetPool
    end
    if key == currentKey then
        return true
    end
    if infoPool ~= curPool then
        return false
    end
    if curWorldType and infoWorld and infoWorld ~= curWorldType then
        return false
    end
    return true
end

function Store:AltMatchesWorldScope(info, scopeMode)
    if type(info) ~= "table" then return false end
    local currentKey = self:GetCurrentAltKey()
    local curWorld, curPool
    if Compat.GetAltWorldInfo then
        curWorld, curPool = Compat.GetAltWorldInfo(nil)
    else
        curPool = Compat.RealmPool(Compat.Realm())
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
    end
    return AltMatchesWorldScope(info.key, info, currentKey, curPool, curWorld, scopeMode)
end

function Store:GetRecordedAltWorlds()
    local byKey = {}
    local list = {}
    local alts = ns.db and ns.db.alts or {}
    local curKey = self:GetCurrentAltKey()
    local curWorld, curPool
    if Compat.GetAltWorldInfo then
        curWorld, curPool = Compat.GetAltWorldInfo(nil)
    else
        curPool = Compat.RealmPool(Compat.Realm())
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
    end
    for key, info in pairs(alts) do
        if type(info) == "table" then
            local wt, pool, disp
            if Compat.GetAltWorldInfo then
                wt, pool, disp = Compat.GetAltWorldInfo(info)
            else
                local rName = (type(info.realmName) == "string" and info.realmName ~= "") and info.realmName or nil
                local rPool = (type(info.realmPool) == "string" and info.realmPool ~= "") and info.realmPool or nil
                pool = (rName and Compat.RealmPool(rName)) or (rPool and Compat.RealmPool(rPool)) or curPool
                wt = info.worldType or (Compat.DetectWorldType and Compat.DetectWorldType(rName or rPool, info.realmRaw))
                disp = wt or info.realmRaw or rName or pool
            end
            local sKey = (wt and ("world:" .. wt)) or ("pool:" .. tostring(pool or "default"))
            local bucket = byKey[sKey]
            if not bucket then
                bucket = {
                    scopeKey = sKey,
                    worldType = wt,
                    realmPool = pool,
                    displayLabel = tostring(disp or wt or pool or "?"),
                    count = 0,
                    isCurrentWorld = (curWorld and wt == curWorld) or (not curWorld and pool == curPool),
                }
                byKey[sKey] = bucket
                list[#list + 1] = bucket
            end
            bucket.count = bucket.count + 1
            if key == curKey then
                bucket.isCurrentWorld = true
            end
        end
    end
    table.sort(list, function(a, b)
        local ao = WORLD_TYPE_SORT[a.worldType] or 99
        local bo = WORLD_TYPE_SORT[b.worldType] or 99
        if ao ~= bo then
            return ao < bo
        end
        return (a.displayLabel or "") < (b.displayLabel or "")
    end)
    return list
end

function Store:GetAltsList(scopeMode)
    local out = {}
    local alts = ns.db and ns.db.alts or {}
    local currentKey = self:GetCurrentAltKey()
    local curWorld, curPool
    if Compat.GetAltWorldInfo then
        curWorld, curPool = Compat.GetAltWorldInfo(nil)
    else
        curPool = Compat.RealmPool(Compat.Realm())
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm(), Safe and Safe.String and Safe.Call and Safe.String(Safe.Call(GetRealmName))) or nil
    end
    local wantScope = ResolveNormalizedWorldScope(scopeMode)
    for key, info in pairs(alts) do
        if type(info) == "table" and AltMatchesWorldScope(key, info, currentKey, curPool, curWorld, wantScope) then
            info.key = key
            table.insert(out, info)
        end
    end
    table.sort(out, function(a, b)
        local aCur = (a.key == currentKey)
        local bCur = (b.key == currentKey)
        if aCur ~= bCur then
            return aCur
        end
        if wantScope == "all" then
            local aSame = AltMatchesWorldScope(a.key, a, currentKey, curPool, curWorld, "pool")
            local bSame = AltMatchesWorldScope(b.key, b, currentKey, curPool, curWorld, "pool")
            if aSame ~= bSame then
                return aSame
            end
        end
        if (a.lastActive or 0) ~= (b.lastActive or 0) then
            return (a.lastActive or 0) > (b.lastActive or 0)
        end
        return tostring(a.key or "") < tostring(b.key or "")
    end)
    return out
end

function Store:GetAltsCount(scopeMode)
    local alts = ns.db and ns.db.alts
    if not alts then return 0 end
    local count = 0
    local currentKey = self:GetCurrentAltKey()
    local curWorld, curPool
    if Compat.GetAltWorldInfo then
        curWorld, curPool = Compat.GetAltWorldInfo(nil)
    else
        curPool = Compat.RealmPool(Compat.Realm())
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
    end
    local wantScope = ResolveNormalizedWorldScope(scopeMode)
    for key, info in pairs(alts) do
        if type(info) == "table" and AltMatchesWorldScope(key, info, currentKey, curPool, curWorld, wantScope) then
            count = count + 1
        end
    end
    return count
end

function Store:GetTotalAltsGold(poolOnlyOrScope, factionFilter)
    local currentKey = self:GetCurrentAltKey()
    local total = 0
    local wantScope = (poolOnlyOrScope == nil) and "pool" or ResolveNormalizedWorldScope(poolOnlyOrScope)
    local curWorld, curPool
    if Compat.GetAltWorldInfo then
        curWorld, curPool = Compat.GetAltWorldInfo(nil)
    else
        curPool = Compat.RealmPool(Compat.Realm())
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
    end
    local wantFaction = nil
    if factionFilter == true then
        wantFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    elseif type(factionFilter) == "string" and factionFilter ~= "" then
        wantFaction = factionFilter
    end
    for key, info in pairs(ns.db and ns.db.alts or {}) do
        if type(info) == "table" and tonumber(info.money) then
            local matchWorld = AltMatchesWorldScope(key, info, currentKey, curPool, curWorld, wantScope)
            local matchFaction = not wantFaction or (info.faction == wantFaction)
            if matchWorld and matchFaction then
                total = total + tonumber(info.money)
            end
        end
    end
    return total
end

function Store:GetTotalAltsGoldByFaction(poolOnlyOrScope)
    local currentKey = self:GetCurrentAltKey()
    local res = {
        Alliance = 0,
        Horde = 0,
        Neutral = 0,
        total = 0,
        myFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil,
    }
    local wantScope = (poolOnlyOrScope == nil) and "pool" or ResolveNormalizedWorldScope(poolOnlyOrScope)
    local curWorld, curPool
    if Compat.GetAltWorldInfo then
        curWorld, curPool = Compat.GetAltWorldInfo(nil)
    else
        curPool = Compat.RealmPool(Compat.Realm())
        curWorld = Compat.DetectWorldType and Compat.DetectWorldType(Compat.Realm()) or nil
    end
    for key, info in pairs(ns.db and ns.db.alts or {}) do
        if type(info) == "table" and tonumber(info.money) then
            local matchWorld = AltMatchesWorldScope(key, info, currentKey, curPool, curWorld, wantScope)
            if matchWorld then
                local m = tonumber(info.money) or 0
                res.total = res.total + m
                if info.faction == "Alliance" then
                    res.Alliance = res.Alliance + m
                elseif info.faction == "Horde" then
                    res.Horde = res.Horde + m
                else
                    res.Neutral = res.Neutral + m
                end
            end
        end
    end
    return res
end

function Store:NotifyWatchlistOnline(entry, opts)
    if not entry then return false end
    if opts and opts.suppressAlert then return false end
    if (ns.db and ns.db.settings and ns.db.settings.moduleWatchlistEnabled == false) or (Compat.IsFocusSilenced and Compat.IsFocusSilenced(entry.id or entry.displayName)) then
        return false
    end
    local alerts = ns.db and ns.db.settings and ns.db.settings.alerts
    if not alerts then return false end
    if self.IsPlayerNotifyMuted and self:IsPlayerNotifyMuted(entry.id or entry.displayName, entry) then
        return false
    end

    -- Debounce duplicate login alerts per character within 120 seconds.
    local now = time()
    if entry.lastAlertAt and (now - entry.lastAlertAt) < 120 then
        return false
    end
    entry.lastAlertAt = now

    local shownSender = entry.activeAltName or entry.displayName or "?"
    local shownClass = entry.activeAltClass or entry.classFile
    local shownLookup = entry.activeAltLookup or entry.id or (entry.displayName and entry.displayName:lower()) or nil
    local L = ns.L or {}
    local textSuffix = (entry.area and entry.area ~= "")
        and ((L["Online"] or "Online") .. " · " .. entry.area)
        or (L["Is now online in WoW: Forever"] or "Is now online in WoW: Forever")
    if entry.activeAltName and entry.displayName and entry.activeAltName ~= entry.displayName then
        textSuffix = "(" .. entry.displayName .. ") · " .. textSuffix
    end

    local didAny = false
    local inCombatNow = ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) == true
    local silenceCombat = not (ns.db and ns.db.settings and ns.db.settings.msgPreviewSilenceCombat == false)
    local didVisibleToast = false
    local didChatPrint = false
    if alerts.toast ~= false and not (opts and opts.suppressToast) then
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "watchlist:" .. tostring(entry.id or entry.displayName or "?") .. ":" .. tostring(now),
            kind = "WATCHLIST_ONLINE",
            sourceTag = L["Watchlist"] or "Watchlist",
            sender = shownSender,
            senderClass = shownClass,
            lookupKey = shownLookup,
            text = textSuffix,
            searchHint = shownSender,
            ts = now,
            priority = 1,
        })
        didAny = true
        if not (inCombatNow and silenceCombat) then
            didVisibleToast = true
        end
    end

    if alerts.chat and not (opts and opts.suppressChat) then
        local hex = Compat.ClassHex(shownClass)
        local label = hex .. shownSender .. "|r"
        if entry.activeAltName and entry.displayName and entry.activeAltName ~= entry.displayName then
            label = label .. " (" .. entry.displayName .. ")"
        end
        if entry.area and entry.area ~= "" then
            ns:Print(ns.L["%s appears online (%s)."]:format(label, entry.area))
        else
            ns:Print(ns.L["%s is now online!"]:format(label))
        end
        didAny = true
        didChatPrint = true
    end

    if alerts.sound and (didVisibleToast or didChatPrint) and not (opts and opts.suppressSound) and PlaySound and SOUNDKIT then
        local monoNow = (GetTime and GetTime()) or now
        if (monoNow - (self._lastWatchlistSoundAt or 0)) >= 3.0 then
            local soundId = SOUNDKIT.MAP_PING or 3175
            if soundId then
                self._lastWatchlistSoundAt = monoNow
                pcall(PlaySound, soundId, "Master")
            end
        end
        didAny = true
    end
    return didAny
end

-- Propagate fresh live unit-level /who sightings (UNIT_LEVEL, InspectUnit, /who) across
-- Social, Directory, Guild Roster, Nearby, and FriendPresence without bloating SavedVariables.
function Store:RecordLiveUnitObservation(rawName, data)
    if type(rawName) ~= "string" or rawName == "" or type(data) ~= "table" then return end
    local lookupKey
    if Compat.ParseCharacterFields then
        lookupKey = Compat.ParseCharacterFields(rawName)
    else
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(rawName)
        lookupKey = parsed and parsed.lookupKey
    end
    if not lookupKey or lookupKey == "" then
        lookupKey = rawName:lower()
    end
    if not lookupKey or lookupKey == "" then return end

    local nowClock = (GetTime and GetTime()) or time()
    local newLevel = tonumber(data.level)
    local newArea = (type(data.area) == "string" and data.area ~= "") and data.area or nil
    local newClass = (type(data.classFile) == "string" and data.classFile ~= "") and data.classFile or nil
    local newGuild = (type(data.guild) == "string" and data.guild ~= "") and data.guild or nil
    local isAuthoritativeWho = (data.source == "who")

    self.liveUnitObs = self.liveUnitObs or {}
    local obs = self.liveUnitObs[lookupKey]
    if not obs then
        local curCount = (self._liveUnitObsCount or 0)
        if curCount >= 350 or (self._liveUnitObsPruneAt and (nowClock - self._liveUnitObsPruneAt) >= 120) then
            self:PruneLiveUnitObservations(nowClock)
        end
        if (self._liveUnitObsCount or 0) >= 350 then
            self.liveUnitObs = {}
            self._liveUnitObsCount = 0
        end
        obs = {}
        self.liveUnitObs[lookupKey] = obs
        self._liveUnitObsCount = (self._liveUnitObsCount or 0) + 1
    end
    local stale = (nowClock - (obs.observedAt or 0)) >= 1800
    if newLevel and newLevel > 0 then
        if isAuthoritativeWho or stale or newLevel >= (obs.level or 0) then
            obs.level = newLevel
        end
    end
    if newArea then obs.area = newArea end
    if newClass then obs.classFile = newClass end
    if newGuild then obs.guild = newGuild end
    obs.observedAt = nowClock
    obs.source = data.source or obs.source

    local socialChanged = false
    local function PatchRow(row)
        if type(row) ~= "table" then return end
        if obs.level and obs.level > 0 and (row.level or 0) ~= obs.level then
            if isAuthoritativeWho or obs.level > (row.level or 0) or (row.level or 0) <= 0 then
                row.level = obs.level
                socialChanged = true
            end
        end
        if newArea and newArea ~= "" and row.area ~= newArea then
            row.area = newArea
            socialChanged = true
        end
        if newClass and (not row.classFile or row.classFile == "") then
            row.classFile = newClass
        end
        if newGuild and (not row.guild or row.guild == "") then
            row.guild = newGuild
        end
    end

    if self.socialByLookup and self.socialByLookup[lookupKey] then
        PatchRow(self.socialByLookup[lookupKey])
    end
    if self.socialDirectoryByLookup and self.socialDirectoryByLookup[lookupKey] then
        PatchRow(self.socialDirectoryByLookup[lookupKey])
    end
    if self.guildRosterRanks and self.guildRosterRanks[lookupKey] then
        PatchRow(self.guildRosterRanks[lookupKey])
    end
    if self.nearby and self.nearby[lookupKey] then
        PatchRow(self.nearby[lookupKey])
    end

    if (obs.level and obs.level > 0) or newArea then
        local pres = self.GetFriendPresence and self:GetFriendPresence(lookupKey)
        if pres or (self.socialDirectoryByLookup and self.socialDirectoryByLookup[lookupKey]) then
            self:TouchFriendPresence(lookupKey, {
                seenNow = false,
                area = newArea,
                classFile = newClass,
                level = obs.level,
            })
        end
    end

    if socialChanged then
        ns:Emit("SOCIAL_UPDATED")
    end
end

function Store:PruneLiveUnitObservations(nowClock)
    local now = nowClock or (GetTime and GetTime()) or time()
    self._liveUnitObsPruneAt = now
    local tbl = self.liveUnitObs
    if type(tbl) ~= "table" then
        self._liveUnitObsCount = 0
        return
    end
    local kept = 0
    for k, rec in pairs(tbl) do
        if type(rec) ~= "table" or (now - (rec.observedAt or 0)) >= 1800 then
            tbl[k] = nil
        else
            kept = kept + 1
        end
    end
    if kept == 0 then
        self.liveUnitObs = {}
    end
    self._liveUnitObsCount = kept
end

function Store:TrimRuntimeCaches()
    self:PruneLiveUnitObservations()
    if self.GetFriendPresenceTable then
        self:GetFriendPresenceTable(true)
    end
    if self.GetRecentCompanionsTable then
        self:GetRecentCompanionsTable(true)
    end
end

function Store:InvalidateWatchlistIndex()
    self._wlIndexDirty = true
    if ns.Watchlist then
        ns.Watchlist._wlIndexDirty = true
    end
end

-- Cross-pollinate Watchlist rows whenever live Social or Nearby detects a watched player.
function Store:SyncWatchlistObservation(rawName, data, opts)
    if ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive() then return end
    if ns.db and ns.db.settings and ns.db.settings.moduleWatchlistEnabled == false then return end
    local list = self:GetWatchlistTable()
    if next(list) == nil then return end
    local pLookup, pFirst, pDisp, pSur
    if Compat.ParseCharacterFields then
        pLookup, pFirst, pDisp, pSur = Compat.ParseCharacterFields(rawName)
    else
        local tmpParsed = Compat.ParseCharacterName(rawName)
        if tmpParsed then
            pLookup, pFirst, pDisp, pSur = tmpParsed.lookupKey, tmpParsed.firstName, tmpParsed.displayName, tmpParsed.surname
        end
    end
    if not pLookup or pLookup == "" then return end

    if self._wlIndexDirty or self._wlIndexedRef ~= list or type(self._wlNoSurnameByFirst) ~= "table" or type(self._wlLinkedAltIndex) ~= "table" then
        local byFirst = {}
        local idIndex = {}
        local linkedIndex = {}
        for idKey, entry in pairs(list) do
            if type(entry) == "table" then
                if entry.id and entry.id ~= idKey then
                    local bucket = idIndex[entry.id]
                    if not bucket then
                        bucket = {}
                        idIndex[entry.id] = bucket
                    end
                    bucket[#bucket + 1] = idKey
                end
                if not entry.surname and entry.firstName and entry.firstName ~= "" then
                    local fl = entry.firstName:lower()
                    local fBucket = byFirst[fl]
                    if not fBucket then
                        fBucket = {}
                        byFirst[fl] = fBucket
                    end
                    fBucket[#fBucket + 1] = idKey
                end
                if entry.watchAllAlts == true and self.GetAllLinkedCharacters then
                    local linked = self:GetAllLinkedCharacters(entry.id or idKey)
                    for _, altRec in ipairs(linked) do
                        local altLk = altRec and altRec.lookupKey
                        if altLk and altLk ~= "" and altLk ~= idKey and altLk ~= entry.id then
                            local lBucket = linkedIndex[altLk]
                            if not lBucket then
                                lBucket = {}
                                linkedIndex[altLk] = lBucket
                            end
                            lBucket[#lBucket + 1] = idKey
                        end
                    end
                end
            end
        end
        self._wlNoSurnameByFirst = byFirst
        self._wlIdMatches = idIndex
        self._wlLinkedAltIndex = linkedIndex
        self._wlIndexedRef = list
        self._wlIndexDirty = false
    end

    local firstLower = pFirst and pFirst:lower() or nil
    local directEntry = list[pLookup]
    local idMatches = self._wlIdMatches and self._wlIdMatches[pLookup]
    local firstMatches = firstLower and self._wlNoSurnameByFirst and self._wlNoSurnameByFirst[firstLower]
    local linkedAltMatches = (not (data and data.altLookupKey)) and self._wlLinkedAltIndex and self._wlLinkedAltIndex[pLookup] or nil
    if not directEntry and not idMatches and not firstMatches and not linkedAltMatches then
        return
    end

    local parsed = {
        lookupKey = pLookup,
        firstName = pFirst,
        displayName = pDisp,
        surname = pSur,
    }

    local now = time()
    local changed = false
    local keysToReindex
    local reindexedTargets
    local processedKeys = {}
    local hasExactTarget = (directEntry ~= nil) or (type(idMatches) == "table" and #idMatches > 0)

    local function ApplyObservation(idKey, entry, isLinkedAltTarget)
        if type(entry) ~= "table" or processedKeys[idKey] then return end
        processedKeys[idKey] = true
        local exactMatch = (idKey == parsed.lookupKey) or (entry.id == parsed.lookupKey)
        local firstMatch = (not isLinkedAltTarget) and firstLower and (not entry.surname or entry.surname == "") and entry.firstName and entry.firstName:lower() == firstLower
        if not (exactMatch or firstMatch or isLinkedAltTarget) then return end
        if isLinkedAltTarget and not exactMatch then
            local obsOn = data.online
            if obsOn == true then
                local prevSt = entry.status
                local wasExp = (entry._expiredOnline == true)
                entry.status = "online"
                entry._expiredOnline = nil
                entry.activeAltLookup = parsed.lookupKey
                entry.activeAltName = parsed.displayName
                if data.classFile then entry.activeAltClass = data.classFile end
                if data.level and data.level > 0 then entry.activeAltLevel = data.level end
                if data.area and data.area ~= "" then entry.area = data.area end
                if data.source then entry.source = data.source end
                entry.lastSeen = now
                entry.lastChecked = now
                if not (opts and opts.suppressAlert) and prevSt ~= "online" and not wasExp then
                    self:NotifyWatchlistOnline(entry, opts)
                end
                changed = true
            elseif obsOn == false and entry.activeAltLookup == parsed.lookupKey then
                entry.activeAltLookup = nil
                entry.activeAltName = nil
                entry.activeAltClass = nil
                entry.activeAltLevel = nil
                entry.status = "offline"
                entry._expiredOnline = nil
                changed = true
            end
            return
        end
        if not exactMatch then
            -- Do not let a full-name sighting overwrite or duplicate a separate first-name-only entry when the full-name key already exists.
            if parsed.surname and parsed.surname ~= "" and (hasExactTarget or list[parsed.lookupKey] ~= nil or (reindexedTargets and reindexedTargets[parsed.lookupKey])) then
                return
            end
            if data.guid and data.guid ~= "" and entry.guid and entry.guid ~= "" and data.guid ~= entry.guid then
                return
            end
        end

        local prevStatus = entry.status
        local obsOnline = data.online
        if obsOnline == false and entry.watchAllAlts == true and entry.activeAltLookup and entry.activeAltLookup ~= parsed.lookupKey then
            local altLiveSoc = self.socialByLookup and self.socialByLookup[entry.activeAltLookup]
            local altLiveGrp = Compat.IsInMyGroupConnected and Compat.IsInMyGroupConnected(entry.activeAltName or entry.activeAltLookup)
            if (altLiveSoc and altLiveSoc.online == true) or altLiveGrp then
                return
            end
        end
        if obsOnline == true and data.source ~= "bnet" and data.source ~= "friend" and data.source ~= "who" and data.source ~= "probe" and data.source ~= "addon"
            and ns.Social and ns.Social.GetBNetLinkInfo
        then
            local bLink = ns.Social:GetBNetLinkInfo(parsed.lookupKey)
            if bLink and bLink.isBNet and bLink.online and bLink.activeLookupKey then
                local isActiveOnBNet = (bLink.activeLookupKeys and bLink.activeLookupKeys[parsed.lookupKey] == true)
                    or (bLink.activeLookupKey == parsed.lookupKey)
                if not isActiveOnBNet then
                    -- Another character on the same Battle.net session is active; clear stale online state without alerting.
                    if entry.status == "online" then
                        entry.status = "offline"
                        entry._expiredOnline = nil
                        entry._staleSettled = nil
                        changed = true
                    end
                    return
                end
            end
        end
        local trustedSurnameSource = (data.source == "friend" or data.source == "bnet" or data.source == "guild" or data.source == "target" or data.source == "who" or data.source == "probe" or data.source == "addon")
            or (data.guid and entry.guid and data.guid == entry.guid)
        if data.status == "unknown" and obsOnline == nil then
            entry.status = "unknown"
            entry.truncatedWarning = nil
        elseif obsOnline ~= nil then
            entry.status = obsOnline and "online" or "offline"
            entry.lastChecked = now
            entry.truncatedWarning = nil
        end
        if obsOnline == true then
            if data.source == "probe" and (not data.area or data.area == "") then
                entry._needsWhoEnrich = true
            elseif (data.area and data.area ~= "") or data.source == "who" or data.source == "bnet" or data.source == "friend" or data.source == "guild" then
                entry._needsWhoEnrich = nil
            end
        elseif obsOnline == false then
            entry._needsWhoEnrich = nil
        end
        if data.altLookupKey and data.altDisplayName and obsOnline == true then
            entry.activeAltLookup = data.altLookupKey
            entry.activeAltName = data.altDisplayName
            entry.activeAltClass = data.altClassFile or data.classFile
            entry.activeAltLevel = data.altLevel or data.level
        elseif obsOnline == true or obsOnline == false or data.clearAlt then
            entry.activeAltLookup = nil
            entry.activeAltName = nil
            entry.activeAltClass = nil
            entry.activeAltLevel = nil
        end
        if data.source then entry.source = data.source end
        if not (data.altLookupKey and data.altDisplayName) then
            if data.level and data.level > 0 then entry.level = data.level end
            if data.classFile then entry.classFile = data.classFile end
        end
        if data.area and data.area ~= "" then entry.area = data.area end
        if data.guild and data.guild ~= "" then entry.guild = data.guild end
        if not (data.altLookupKey and data.altDisplayName) and data.guid and data.guid ~= "" and (not entry.guid or trustedSurnameSource) then
            entry.guid = data.guid
        end
        if parsed.surname and parsed.surname ~= "" and (not entry.surname or entry.surname == "") then
            local targetOccupied = (parsed.lookupKey ~= idKey)
                and (list[parsed.lookupKey] ~= nil or (reindexedTargets and reindexedTargets[parsed.lookupKey]))
            if trustedSurnameSource and not targetOccupied then
                entry.firstName = parsed.firstName or entry.firstName
                entry.surname = parsed.surname
                entry.displayName = parsed.displayName
                entry.observedCandidate = nil
                entry.truncatedWarning = nil
                self:InvalidateWatchlistIndex()
                if parsed.lookupKey ~= idKey then
                    reindexedTargets = reindexedTargets or {}
                    reindexedTargets[parsed.lookupKey] = true
                    keysToReindex = keysToReindex or {}
                    keysToReindex[#keysToReindex + 1] = { oldId = idKey, newId = parsed.lookupKey, entry = entry }
                end
            elseif not targetOccupied then
                -- Passive nearby/chat sighting: suggest candidate without permanently hijacking FirstName-only entry.
                entry.observedCandidate = parsed.displayName
            end
        elseif trustedSurnameSource and parsed.displayName and parsed.displayName ~= "" and entry.displayName
            and entry.displayName ~= parsed.displayName and entry.displayName:lower() == parsed.displayName:lower()
        then
            entry.firstName = parsed.firstName or entry.firstName
            entry.surname = parsed.surname or entry.surname
            entry.displayName = parsed.displayName
            self:InvalidateWatchlistIndex()
        end
        if obsOnline then
            local wasExpired = (entry._expiredOnline == true)
            entry._expiredOnline = nil
            entry._staleSettled = nil
            entry.lastSeen = now
            entry.lastChecked = now
            local allowUnknown = ((opts and opts.allowUnknownTransition == true) or data.source == "probe" or data.source == "addon" or data.source == "who")
                and (now - (entry.addedAt or 0)) >= 3
                and not wasExpired
            if not (opts and opts.suppressAlert) and (prevStatus == "offline" or (prevStatus == "unknown" and allowUnknown)) then
                self:NotifyWatchlistOnline(entry, opts)
            end
        elseif obsOnline == false then
            entry._expiredOnline = nil
            entry._staleSettled = nil
            local obsLastSeen = tonumber(data.lastSeen)
            if obsLastSeen and obsLastSeen > 0 and obsLastSeen <= now and ((not entry.lastSeen) or entry.lastSeen <= 0 or (obsLastSeen > entry.lastSeen + 3600)) then
                entry.lastSeen = obsLastSeen
            end
            if self.liveUnitObs and parsed and parsed.lookupKey then
                self.liveUnitObs[parsed.lookupKey] = nil
            end
        end
        changed = true
    end

    if directEntry then
        ApplyObservation(parsed.lookupKey, directEntry, false)
    end
    if idMatches then
        for _, idKey in ipairs(idMatches) do
            if idKey ~= parsed.lookupKey then
                ApplyObservation(idKey, list[idKey], false)
            end
        end
    end
    if firstMatches then
        for _, idKey in ipairs(firstMatches) do
            if idKey ~= parsed.lookupKey then
                ApplyObservation(idKey, list[idKey], false)
            end
        end
    end
    if linkedAltMatches then
        for _, idKey in ipairs(linkedAltMatches) do
            if idKey ~= parsed.lookupKey then
                ApplyObservation(idKey, list[idKey], true)
            end
        end
    end

    if keysToReindex then
        for _, item in ipairs(keysToReindex) do
            if not list[item.newId] or list[item.newId] == item.entry then
                item.entry.id = item.newId
                list[item.newId] = item.entry
                if item.oldId ~= item.newId then
                    list[item.oldId] = nil
                end
            end
        end
        self:InvalidateWatchlistIndex()
    end

    if changed then
        ns:Emit("WATCHLIST_UPDATED")
    end
end

local MAX_RECENT_COMPANIONS = 250
local COMPANION_TTL = 365 * 86400

function Store:GetSocialMetaTable()
    return self:EnsureScopedBucket(ns.db and ns.db.socialMeta, "socialMeta")
end

local function NormalizeMetaKey(rawNameOrKey)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then return nil end
    -- Rule #4 privacy gate: never persist BattleTags (#), BNet KStrings (|K), or emails (@) into SavedVariables.
    if rawNameOrKey:find("#", 1, true) or rawNameOrKey:find("|K", 1, true) or rawNameOrKey:find("|k", 1, true) or rawNameOrKey:find("@", 1, true) then
        return nil
    end
    local lookupKey = Compat.ParseCharacterFields and Compat.ParseCharacterFields(rawNameOrKey)
    if lookupKey and lookupKey ~= "" then
        return lookupKey
    end
    local parsed = Compat.ParseCharacterName(rawNameOrKey)
    return (parsed and parsed.lookupKey) or rawNameOrKey:lower()
end

function Store:GetSocialMeta(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return nil end
    return self:GetSocialMetaTable()[key]
end

function Store:GetResolvedSocialMeta(rawNameOrKey)
    local direct = self:GetSocialMeta(rawNameOrKey)
    if not direct then return nil end
    if not direct.mainName or direct.mainName == "" then
        return direct
    end
    local mainMeta = self:GetSocialMeta(direct.mainName)
    if not mainMeta then
        return direct
    end
    return {
        folder = (direct.folder and direct.folder ~= "") and direct.folder or mainMeta.folder,
        mainName = direct.mainName,
        nickname = (direct.nickname and direct.nickname ~= "") and direct.nickname or mainMeta.nickname,
        note = (direct.note and direct.note ~= "") and direct.note or mainMeta.note,
        flag = direct.flag or mainMeta.flag,
        favorite = (direct.favorite == true) or (mainMeta.favorite == true) or nil,
        notifyMuted = direct.notifyMuted == true and true or nil,
        notifyGuild = direct.notifyGuild == true and true or nil,
        updatedAt = direct.updatedAt or mainMeta.updatedAt,
    }
end

function Store:SetSocialMeta(rawNameOrKey, patch)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key or type(patch) ~= "table" then return nil end
    local tbl = self:GetSocialMetaTable()
    local rec = tbl[key] or {}
    if patch.folder ~= nil then
        local clean = Compat.CleanInput(patch.folder)
        rec.folder = clean or nil
    end
    if patch.mainName ~= nil then
        local cleanMain = Compat.CleanInput(patch.mainName)
        rec.mainName = cleanMain or nil
    end
    if patch.nickname ~= nil then
        local cleanNick = Compat.CleanInput(patch.nickname)
        if cleanNick and #cleanNick > 28 then
            cleanNick = (Compat.TruncateUtf8 and Compat.TruncateUtf8(cleanNick, 28)) or cleanNick:sub(1, 28)
        end
        rec.nickname = cleanNick or nil
    end
    if patch.note ~= nil then
        local cleanNote = Compat.CleanInput(patch.note)
        rec.note = cleanNote or nil
    end
    if patch.flag ~= nil then
        if patch.flag == "AVOID" or patch.flag == "GOOD" then
            rec.flag = patch.flag
        else
            rec.flag = nil
            rec.displayName = nil
        end
    end
    if patch.displayName ~= nil then
        local cleanDisp = Compat.CleanInput(patch.displayName)
        if cleanDisp and not cleanDisp:find("#", 1, true) and not cleanDisp:find("|K", 1, true) and not cleanDisp:find("@", 1, true) then
            rec.displayName = cleanDisp
        end
    end
    if patch.favorite ~= nil then
        rec.favorite = (patch.favorite == true) and true or nil
        local wl = self:GetWatchlistTable()
        if wl and type(wl[key]) == "table" then
            wl[key].favorite = (patch.favorite == true) and true or false
        end
    end
    if patch.notifyMuted ~= nil then
        rec.notifyMuted = (patch.notifyMuted == true) and true or nil
    end
    if patch.notifyGuild ~= nil then
        rec.notifyGuild = (patch.notifyGuild == true) and true or nil
    end
    if not rec.folder and not rec.mainName and not rec.nickname and not rec.note and not rec.flag and not rec.favorite and not rec.notifyMuted and not rec.notifyGuild then
        tbl[key] = nil
    else
        rec.updatedAt = time()
        tbl[key] = rec
    end
    self._socialFoldersCache = nil
    self._linkedAltsDirty = true
    self._wlIndexDirty = true
    ns:Emit("SOCIAL_UPDATED")
    ns:Emit("WATCHLIST_UPDATED")
    ns:Emit("GROUP_UPDATED")
    ns:Emit("CLAN_UPDATED")
    return tbl[key]
end

function Store:SetSocialFlag(rawNameOrKey, flagVal)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then return nil end
    local cur = self:GetSocialMeta(rawNameOrKey)
    local nextFlag = (cur and cur.flag == flagVal) and "" or (flagVal or "")
    return self:SetSocialMeta(rawNameOrKey, { flag = nextFlag })
end

function Store:FlagPlayerAvoid(rawNameOrKey, noteText, displayName)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return nil end
    local cleanDisp = (type(displayName) == "string" and displayName ~= "" and Compat.CleanInput(displayName)) or nil
    if not cleanDisp and type(rawNameOrKey) == "string" and rawNameOrKey ~= "" and rawNameOrKey ~= key then
        cleanDisp = Compat.CleanInput(rawNameOrKey)
    end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(cleanDisp or rawNameOrKey)
    if Compat.IsMe and Compat.IsMe((parsed and parsed.displayName) or cleanDisp or rawNameOrKey) then
        return nil
    end

    local cur = self:GetSocialMeta(key)
    local patch = {
        flag = "AVOID",
        displayName = (cleanDisp and cleanDisp ~= "") and cleanDisp or (parsed and parsed.displayName) or (cur and cur.displayName) or nil,
    }
    if type(noteText) == "string" and noteText ~= "" then
        local cleanNote = Compat.CleanInput(noteText)
        if cleanNote and cleanNote ~= "" then
            local prevNote = cur and type(cur.note) == "string" and cur.note or ""
            if prevNote == "" then
                patch.note = cleanNote
            elseif not prevNote:lower():find(cleanNote:lower(), 1, true) then
                local combined = cleanNote .. " · " .. prevNote
                if #combined > 160 then
                    combined = (Compat.TruncateUtf8 and Compat.TruncateUtf8(combined, 160)) or combined:sub(1, 160)
                end
                patch.note = combined
            end
        end
    end
    return self:SetSocialMeta(key, patch)
end

local VALID_IGNORE_REASONS = {
    SPAM = true,
    SCAM = true,
    NINJA = true,
    TOXIC = true,
    OTHER = true,
}

function Store:GetAccountIgnoresTable()
    if not ns.db then return {} end
    if type(ns.db.accountIgnores) ~= "table" then
        ns.db.accountIgnores = {}
    end
    return ns.db.accountIgnores
end

function Store:PruneExpiredAccountIgnores(silent)
    local tbl = self:GetAccountIgnoresTable()
    local now = time()
    local pruned = false
    for key, rec in pairs(tbl) do
        if type(rec) ~= "table" or (type(rec.expiresAt) == "number" and rec.expiresAt > 0 and now >= rec.expiresAt) then
            tbl[key] = nil
            pruned = true
        end
    end
    if pruned and not silent then
        ns:Emit("ACCOUNT_IGNORES_UPDATED")
        ns:Emit("SOCIAL_UPDATED")
        ns:Emit("CHAT_UPDATED")
    end
    return pruned
end

function Store:GetAccountIgnore(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return nil end
    local tbl = self:GetAccountIgnoresTable()
    local rec = tbl[key]
    if type(rec) == "table" then
        if type(rec.expiresAt) == "number" and rec.expiresAt > 0 and time() >= rec.expiresAt then
            tbl[key] = nil
            return nil
        end
        return rec, key
    end
    local meta = self:GetSocialMeta(key)
    if meta and meta.mainName and meta.mainName ~= "" then
        local mainKey = NormalizeMetaKey(meta.mainName)
        if mainKey and mainKey ~= key and type(tbl[mainKey]) == "table" then
            local mRec = tbl[mainKey]
            if type(mRec.expiresAt) == "number" and mRec.expiresAt > 0 and time() >= mRec.expiresAt then
                tbl[mainKey] = nil
                return nil
            end
            return mRec, mainKey
        end
    end
    return nil
end

function Store:IsAccountIgnored(rawNameOrKey)
    return self:GetAccountIgnore(rawNameOrKey) ~= nil
end

function Store:SetAccountIgnore(rawNameOrKey, opts)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then return nil end
    -- Strictly refuse BattleTags / Real ID KStrings to preserve privacy rules
    if rawNameOrKey:find("#", 1, true) or rawNameOrKey:find("|K", 1, true) then
        return nil
    end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(rawNameOrKey)
    local key = (parsed and parsed.lookupKey) or NormalizeMetaKey(rawNameOrKey)
    if not key or key == "" then return nil end
    if Compat.IsMe and Compat.IsMe((parsed and parsed.displayName) or rawNameOrKey) then
        return nil
    end

    opts = type(opts) == "table" and opts or {}
    local tbl = self:GetAccountIgnoresTable()
    local prev = type(tbl[key]) == "table" and tbl[key] or {}
    local reason = type(opts.reason) == "string" and opts.reason:upper() or prev.reason or "OTHER"
    if not VALID_IGNORE_REASONS[reason] then
        reason = "OTHER"
    end
    local cleanName = (opts.name and Compat.CleanInput and Compat.CleanInput(opts.name))
        or (parsed and parsed.displayName)
        or prev.name
        or rawNameOrKey
    local cleanNote
    if opts.note ~= nil then
        cleanNote = (Compat.CleanInput and Compat.CleanInput(opts.note)) or ""
    else
        cleanNote = prev.note or ""
    end
    local now = time()
    local expiresAt = prev.expiresAt or 0
    if opts.expiresAt ~= nil then
        expiresAt = tonumber(opts.expiresAt) or 0
    elseif opts.durationSec ~= nil then
        local dur = tonumber(opts.durationSec) or 0
        expiresAt = (dur > 0) and (now + dur) or 0
    end
    local hideChat
    if opts.hideChat ~= nil then
        hideChat = (opts.hideChat == true)
    else
        hideChat = (prev.hideChat ~= false)
    end

    tbl[key] = {
        name = cleanName,
        reason = reason,
        note = cleanNote ~= "" and cleanNote or nil,
        addedAt = prev.addedAt or now,
        updatedAt = now,
        expiresAt = expiresAt,
        hideChat = hideChat,
    }

    -- Keep Social Meta synchronized with AVOID flag so Group/LFG/Radar warnings work seamlessly
    local curMeta = self:GetSocialMeta(key)
    local metaPatch = { flag = "AVOID" }
    if cleanNote ~= "" and (not curMeta or not curMeta.note or curMeta.note == "") then
        metaPatch.note = cleanNote
    end
    self:SetSocialMeta(key, metaPatch)

    ns:Emit("ACCOUNT_IGNORES_UPDATED")
    ns:Emit("CHAT_UPDATED")
    return tbl[key]
end

function Store:RemoveAccountIgnore(rawNameOrKey, clearAvoidFlag)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return false end
    local tbl = self:GetAccountIgnoresTable()
    if tbl[key] == nil then
        return false
    end
    tbl[key] = nil
    if clearAvoidFlag then
        local curMeta = self:GetSocialMeta(key)
        if curMeta and curMeta.flag == "AVOID" then
            self:SetSocialMeta(key, { flag = "" })
        end
    end
    ns:Emit("ACCOUNT_IGNORES_UPDATED")
    ns:Emit("SOCIAL_UPDATED")
    ns:Emit("WATCHLIST_UPDATED")
    ns:Emit("GROUP_UPDATED")
    ns:Emit("CLAN_UPDATED")
    ns:Emit("CHAT_UPDATED")
    return true
end

function Store:GetAccountIgnoresList()
    self:PruneExpiredAccountIgnores(true)
    local tbl = self:GetAccountIgnoresTable()
    local out = {}
    for key, rec in pairs(tbl) do
        if type(rec) == "table" then
            out[#out + 1] = {
                lookupKey = key,
                name = rec.name or key,
                reason = rec.reason or "OTHER",
                note = rec.note,
                addedAt = rec.addedAt or 0,
                expiresAt = rec.expiresAt or 0,
                hideChat = rec.hideChat ~= false,
            }
        end
    end
    table.sort(out, function(a, b)
        if (a.addedAt or 0) ~= (b.addedAt or 0) then
            return (a.addedAt or 0) > (b.addedAt or 0)
        end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

function Store:GetAccountIgnoresCount()
    self:PruneExpiredAccountIgnores(true)
    local count = 0
    for _ in pairs(self:GetAccountIgnoresTable()) do
        count = count + 1
    end
    return count
end

function Store:FormatIgnoreReason(reasonCode, Ltbl)
    local L = Ltbl or ns.L or {}
    local r = type(reasonCode) == "string" and reasonCode:upper() or "OTHER"
    if r == "SPAM" then return L["Spammer"] or "Spammer"
    elseif r == "SCAM" then return L["Scammer"] or "Scammer"
    elseif r == "NINJA" then return L["Ninja Loot"] or "Ninja Loot"
    elseif r == "TOXIC" then return L["Toxic"] or "Toxic"
    end
    return L["Other"] or "Other"
end

function Store:FormatIgnoreRemaining(expiresAt, Ltbl)
    local L = Ltbl or ns.L or {}
    local exp = tonumber(expiresAt) or 0
    if exp <= 0 then
        return L["Permanent"] or "Permanent"
    end
    local rem = exp - time()
    if rem <= 0 then
        return L["Expired"] or "Expired"
    elseif rem < 3600 then
        return string.format(L["%dm left"] or "%dm left", math.max(1, math.floor(rem / 60)))
    elseif rem < 86400 then
        return string.format(L["%dh left"] or "%dh left", math.max(1, math.floor(rem / 3600)))
    end
    return string.format(L["%dd left"] or "%dd left", math.max(1, math.floor(rem / 86400)))
end

function Store:GetSocialFolders()
    if self._socialFoldersCache then
        return self._socialFoldersCache
    end
    local seen, out = {}, {}
    for _, meta in pairs(self:GetSocialMetaTable()) do
        if type(meta) == "table" and type(meta.folder) == "string" and meta.folder ~= "" and not seen[meta.folder] then
            seen[meta.folder] = true
            table.insert(out, meta.folder)
        end
    end
    table.sort(out)
    self._socialFoldersCache = out
    return out
end

function Store:RenameSocialFolder(oldName, newName)
    local oldClean = Compat.CleanInput and Compat.CleanInput(oldName) or oldName
    local newClean = Compat.CleanInput and Compat.CleanInput(newName) or newName
    if not oldClean or oldClean == "" or not newClean or newClean == "" or oldClean == newClean then
        return 0
    end
    local tbl = self:GetSocialMetaTable()
    local moved = 0
    local now = time()
    for _, rec in pairs(tbl) do
        if type(rec) == "table" and rec.folder == oldClean then
            rec.folder = newClean
            rec.updatedAt = now
            moved = moved + 1
        end
    end
    if moved > 0 then
        self._socialFoldersCache = nil
        ns:Emit("SOCIAL_UPDATED")
    end
    return moved
end

function Store:DeleteSocialFolder(folderName)
    local clean = Compat.CleanInput and Compat.CleanInput(folderName) or folderName
    if not clean or clean == "" then
        return 0
    end
    local tbl = self:GetSocialMetaTable()
    local cleared = 0
    for key, rec in pairs(tbl) do
        if type(rec) == "table" and rec.folder == clean then
            rec.folder = nil
            if not rec.mainName and not rec.nickname and not rec.note and not rec.flag and not rec.favorite and not rec.notifyMuted and not rec.notifyGuild then
                tbl[key] = nil
            else
                rec.updatedAt = time()
            end
            cleared = cleared + 1
        end
    end
    if cleared > 0 then
        self._socialFoldersCache = nil
        ns:Emit("SOCIAL_UPDATED")
    end
    return cleared
end

function Store:BatchSetSocialFolder(lookupKeys, folderName)
    if type(lookupKeys) ~= "table" then
        return 0
    end
    local clean = (type(folderName) == "string" and folderName ~= "") and (Compat.CleanInput and Compat.CleanInput(folderName) or folderName) or nil
    local tbl = self:GetSocialMetaTable()
    local changed = 0
    local now = time()
    for _, rawKey in ipairs(lookupKeys) do
        local key = NormalizeMetaKey(rawKey)
        if key then
            local rec = tbl[key] or {}
            if rec.folder ~= clean then
                rec.folder = clean
                if not rec.folder and not rec.mainName and not rec.nickname and not rec.note and not rec.flag and not rec.favorite and not rec.notifyMuted and not rec.notifyGuild then
                    tbl[key] = nil
                else
                    rec.updatedAt = now
                    tbl[key] = rec
                end
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        self._socialFoldersCache = nil
        ns:Emit("SOCIAL_UPDATED")
    end
    return changed
end

function Store:GetLinkedAltsForCharacter(rawNameOrKey)
    local mainKey = NormalizeMetaKey(rawNameOrKey)
    if not mainKey then return nil end
    local metaTbl = self:GetSocialMetaTable()
    if self._linkedAltsDirty or self._linkedAltsRef ~= metaTbl or not self._linkedAltsMap then
        local map = {}
        for altKey, rec in pairs(metaTbl) do
            if type(rec) == "table" and type(rec.mainName) == "string" and rec.mainName ~= "" then
                local mKey = NormalizeMetaKey(rec.mainName)
                if mKey and mKey ~= altKey then
                    local bucket = map[mKey]
                    if not bucket then
                        bucket = {}
                        map[mKey] = bucket
                    end
                    local parsedAlt = Compat.ParseCharacterName(altKey)
                    bucket[#bucket + 1] = (parsedAlt and parsedAlt.displayName) or altKey
                end
            end
        end
        for _, bucket in pairs(map) do
            table.sort(bucket)
        end
        self._linkedAltsMap = map
        self._linkedAltsRef = metaTbl
        self._linkedAltsDirty = false
    end
    return self._linkedAltsMap[mainKey]
end

local MAX_OBSERVED_ALT_KEYS = 200

function Store:RecordObservedAltPair(nameOrKeyA, nameOrKeyB)
    local kA = NormalizeMetaKey(nameOrKeyA)
    local kB = NormalizeMetaKey(nameOrKeyB)
    if not kA or not kB or kA == kB then return end
    if not ns.db then return end
    ns.db.observedAlts = ns.db.observedAlts or {}
    local scope = Compat.ScopeKey()
    ns.db.observedAlts[scope] = ns.db.observedAlts[scope] or {}
    local tbl = ns.db.observedAlts[scope]

    local function link(src, dst)
        local pDst = Compat.ParseCharacterName(dst)
        local dispDst = (pDst and pDst.displayName) or dst
        local bucket = tbl[src]
        if type(bucket) ~= "table" then
            local count = 0
            for _ in pairs(tbl) do count = count + 1 end
            if count >= MAX_OBSERVED_ALT_KEYS then
                local oldestKey = next(tbl)
                if oldestKey then tbl[oldestKey] = nil end
            end
            bucket = {}
            tbl[src] = bucket
        end
        bucket[dst] = dispDst
    end

    link(kA, kB)
    link(kB, kA)
    self._wlIndexDirty = true
end

function Store:GetAllLinkedCharacters(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return {} end
    local out, seen = {}, { [key] = true }
    local function addCand(raw)
        if type(raw) ~= "string" or raw == "" then return end
        local k = NormalizeMetaKey(raw)
        if not k or seen[k] then return end
        seen[k] = true
        local parsed = Compat.ParseCharacterName(raw)
        out[#out + 1] = {
            lookupKey = k,
            displayName = (parsed and parsed.displayName) or raw,
        }
    end

    local metaTbl = self:GetSocialMetaTable()
    local ownMeta = metaTbl and metaTbl[key]
    local rootKey = key
    if type(ownMeta) == "table" and type(ownMeta.mainName) == "string" and ownMeta.mainName ~= "" then
        addCand(ownMeta.mainName)
        rootKey = NormalizeMetaKey(ownMeta.mainName) or key
    end
    local rootAlts = self:GetLinkedAltsForCharacter(rootKey)
    if type(rootAlts) == "table" then
        for _, altName in ipairs(rootAlts) do
            addCand(altName)
        end
    end
    if rootKey ~= key then
        local ownAlts = self:GetLinkedAltsForCharacter(key)
        if type(ownAlts) == "table" then
            for _, altName in ipairs(ownAlts) do
                addCand(altName)
            end
        end
    end

    local scope = Compat.ScopeKey()
    local obs = ns.db and ns.db.observedAlts and ns.db.observedAlts[scope]
    local function scanObsBucket(bKey)
        local b = bKey and obs and obs[bKey]
        if type(b) == "table" then
            for k, disp in pairs(b) do
                addCand(disp or k)
                local sub = obs and obs[k]
                if type(sub) == "table" then
                    for sk, sdisp in pairs(sub) do
                        addCand(sdisp or sk)
                    end
                end
            end
        end
    end
    scanObsBucket(key)
    if rootKey and rootKey ~= key then
        scanObsBucket(rootKey)
    end
    return out
end

function Store:MigrateSocialSurnameRecords(firstName, lookupKey)
    if type(firstName) ~= "string" or firstName == "" or type(lookupKey) ~= "string" or lookupKey == "" then
        return
    end
    local firstLower = firstName:lower()
    if firstLower == lookupKey then return end

    local metaTbl = self:GetSocialMetaTable()
    if metaTbl[firstLower] and not metaTbl[lookupKey] then
        metaTbl[lookupKey] = metaTbl[firstLower]
        metaTbl[firstLower] = nil
        self._socialFoldersCache = nil
        self._linkedAltsDirty = true
        self._wlIndexDirty = true
    end

    local presRoot = ns.db and ns.db.friendPresence
    local scope = presRoot and Compat.ScopeKey()
    local presTbl = scope and presRoot[scope]
    if type(presTbl) == "table" and presTbl[firstLower] and not presTbl[lookupKey] then
        presTbl[lookupKey] = presTbl[firstLower]
        presTbl[firstLower] = nil
    end
end

local MAX_FRIEND_PRESENCE = 600
local FRIEND_PRESENCE_TTL = 730 * 86400

function Store:GetFriendPresenceTable(forcePrune)
    local root = ns.db and ns.db.friendPresence
    if not root then return {} end
    local tbl = self:EnsureScopedBucket(root, "friendPresence")
    local scope = Compat.ScopeKey()
    self._presencePruneAt = self._presencePruneAt or {}
    local nowT = GetTime and GetTime() or 0
    local lastAt = self._presencePruneAt[scope]
    if forcePrune or not lastAt or (nowT - lastAt) >= 60 then
        self._presencePruneAt[scope] = nowT
        local now = time()
        local count, oldestKey, oldestSeen = 0, nil, nil
        for k, rec in pairs(tbl) do
            if type(rec) ~= "table" then
                tbl[k] = nil
            else
                local seen = tonumber(rec.lastSeen) or 0
                if (not rec.favorite) and seen > 0 and (now - seen) > FRIEND_PRESENCE_TTL then
                    tbl[k] = nil
                else
                    count = count + 1
                    if not rec.favorite and (not oldestSeen or seen < oldestSeen) then
                        oldestKey, oldestSeen = k, seen
                    end
                end
            end
        end
        if count > MAX_FRIEND_PRESENCE and oldestKey then
            tbl[oldestKey] = nil
        end
    end
    return tbl
end

function Store:GetFriendPresence(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return nil end
    return self:GetFriendPresenceTable()[key]
end

-- Stores strictly character lookupKey metadata (never BattleTag, Real ID, or bnetAccountID).
function Store:TouchFriendPresence(rawNameOrKey, info)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key or type(info) ~= "table" then return nil end
    local tbl = self:GetFriendPresenceTable()
    local rec = tbl[key]
    if not rec then
        rec = {}
        tbl[key] = rec
    end
    if info.seenNow then
        rec.lastSeen = time()
    end
    if info.area and info.area ~= "" then
        rec.lastArea = info.area
    end
    if info.classFile and info.classFile ~= "" then
        rec.lastClass = info.classFile
    end
    if info.level and info.level > 0 then
        rec.lastLevel = info.level
    end
    if info.favorite ~= nil then
        rec.favorite = (info.favorite == true) and true or nil
    end
    return rec
end

function Store:IsSocialFavorite(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return false end
    local meta = self:GetResolvedSocialMeta(key)
    if meta and meta.favorite == true then
        return true
    end
    local pres = self:GetFriendPresence(key)
    if type(pres) == "table" and pres.favorite == true then
        return true
    end
    local wl = self:GetWatchlistTable()
    local w = wl and wl[key]
    return type(w) == "table" and w.favorite == true
end

function Store:SetSocialFavorite(rawNameOrKey, state)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return false end
    local nextFav = (state == true)
    self:SetSocialMeta(key, { favorite = nextFav })
    local tbl = self:GetFriendPresenceTable()
    local rec = tbl[key]
    if rec or nextFav then
        rec = rec or {}
        rec.favorite = nextFav and true or nil
        if not rec.lastSeen and not rec.lastArea and not rec.lastClass and not rec.lastLevel and not rec.favorite then
            tbl[key] = nil
        else
            tbl[key] = rec
        end
    end
    local wl = self:GetWatchlistTable()
    if wl and type(wl[key]) == "table" then
        wl[key].favorite = nextFav
    end
    ns:Emit("SOCIAL_UPDATED")
    ns:Emit("WATCHLIST_UPDATED")
    ns:Emit("CHAT_UPDATED")
    ns:Emit("NEARBY_UPDATED")
    return nextFav
end

function Store:ToggleSocialFavorite(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return false end
    return self:SetSocialFavorite(key, not self:IsSocialFavorite(key))
end

--- Reconcile and recover all legacy/cross-table favorites idempotently without losing user data across updates.
function Store:MigrateLegacyFavorites()
    if not ns.db then return 0 end
    local curMeta = self:GetSocialMetaTable()
    local curPres = self:GetFriendPresenceTable()
    local curWl = self:GetWatchlistTable()
    local recoveredKeys = {}
    local recoveredMetaByNorm = {}

    local function HarvestScopedTable(scopedTbl, captureMetaFields)
        if type(scopedTbl) ~= "table" then return end
        for rawKey, rec in pairs(scopedTbl) do
            if type(rec) == "table" and rec.favorite == true then
                local candidate = rec.fullName or rec.displayName or rec.id or rawKey
                local normKey = (type(candidate) == "string" and not candidate:find("#", 1, true) and not candidate:find("|K", 1, true)) and NormalizeMetaKey(candidate) or nil
                if normKey and normKey ~= "" then
                    recoveredKeys[normKey] = true
                    if captureMetaFields then
                        local stash = recoveredMetaByNorm[normKey] or {}
                        for _, fld in ipairs({ "folder", "flag", "nickname", "note", "mainName" }) do
                            if (not stash[fld] or stash[fld] == "") and type(rec[fld]) == "string" and rec[fld] ~= "" then
                                stash[fld] = rec[fld]
                            end
                        end
                        if rec.notifyMuted == true then stash.notifyMuted = true end
                        recoveredMetaByNorm[normKey] = stash
                    end
                end
            end
        end
    end

    HarvestScopedTable(curMeta, true)
    HarvestScopedTable(curPres)
    HarvestScopedTable(curWl)

    local legacyFavRoots = { ns.db.socialMeta, ns.db.friendPresence, ns.db.watchlist }
    for ri = 1, 3 do
        local rootTbl = legacyFavRoots[ri]
        if type(rootTbl) == "table" then
            for rawKey, flatRec in pairs(rootTbl) do
                if type(flatRec) == "table" and flatRec.favorite == true then
                    local candidate = flatRec.fullName or flatRec.displayName or flatRec.id or rawKey
                    local normKey = (type(candidate) == "string" and not candidate:find("#", 1, true) and not candidate:find("|K", 1, true)) and NormalizeMetaKey(candidate) or nil
                    if normKey and normKey ~= "" then
                        recoveredKeys[normKey] = true
                    end
                end
            end
        end
    end

    if type(ns.db.socialFavorites) == "table" then
        local scope = Compat and Compat.ScopeKey and Compat.ScopeKey() or nil
        local function HarvestBoolMap(tbl)
            if type(tbl) ~= "table" then return end
            for rawKey, val in pairs(tbl) do
                if val == true and type(rawKey) == "string" and not rawKey:find("#", 1, true) and not rawKey:find("|K", 1, true) then
                    local normKey = NormalizeMetaKey(rawKey)
                    if normKey and normKey ~= "" then
                        recoveredKeys[normKey] = true
                    end
                end
            end
        end
        HarvestBoolMap(ns.db.socialFavorites)
        if scope and type(ns.db.socialFavorites[scope]) == "table" then
            HarvestBoolMap(ns.db.socialFavorites[scope])
        end
    end

    local synced = 0
    for normKey in pairs(recoveredKeys) do
        local m = curMeta[normKey]
        if type(m) ~= "table" then
            m = { favorite = true }
            curMeta[normKey] = m
            synced = synced + 1
        elseif m.favorite ~= true then
            m.favorite = true
            synced = synced + 1
        end
        local stash = recoveredMetaByNorm[normKey]
        if type(stash) == "table" then
            for _, fld in ipairs({ "folder", "flag", "nickname", "note", "mainName" }) do
                if (not m[fld] or m[fld] == "") and stash[fld] then
                    m[fld] = stash[fld]
                end
            end
            if stash.notifyMuted == true and m.notifyMuted == nil then
                m.notifyMuted = true
            end
        end
        local p = curPres[normKey]
        if type(p) ~= "table" then
            curPres[normKey] = { favorite = true }
        elseif p.favorite ~= true then
            p.favorite = true
        end
        if type(curWl[normKey]) == "table" and curWl[normKey].favorite ~= true then
            curWl[normKey].favorite = true
        end
    end
    return synced
end

-- Session-only mute map for Battle.net accounts without a character name (never persisted to SavedVariables).
Store._sessionBNetNotifyMuted = Store._sessionBNetNotifyMuted or {}

function Store:IsPlayerNotifyMuted(rawNameOrKey, wlEntry, bnetAccountID)
    if type(wlEntry) == "table" and wlEntry.notifyMuted == true then
        return true
    end
    local key = NormalizeMetaKey(rawNameOrKey)
    if key then
        local wlTbl = self:GetWatchlistTable()
        local w = wlTbl and wlTbl[key]
        if type(w) == "table" and w.notifyMuted == true then
            return true
        end
        local meta = self:GetSocialMeta(key)
        if type(meta) == "table" and meta.notifyMuted == true then
            return true
        end
    end
    if bnetAccountID and self._sessionBNetNotifyMuted[bnetAccountID] == true then
        return true
    end
    return false
end

function Store:SetPlayerNotifyMuted(rawNameOrKey, muted, bnetAccountID)
    local isMuted = (muted == true)
    local key = NormalizeMetaKey(rawNameOrKey)
    if key then
        local wlTbl = self:GetWatchlistTable()
        local w = wlTbl and wlTbl[key]
        if type(w) == "table" then
            w.notifyMuted = isMuted and true or nil
        end
        self:SetSocialMeta(key, { notifyMuted = isMuted })
        ns:Emit("WATCHLIST_UPDATED")
    end
    if bnetAccountID then
        self._sessionBNetNotifyMuted[bnetAccountID] = isMuted and true or nil
        ns:Emit("SOCIAL_UPDATED")
    end
    return isMuted
end

function Store:IsGuildLoginNotifyEnabled(rawNameOrKey)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return false end
    local meta = self:GetSocialMeta(key)
    return type(meta) == "table" and meta.notifyGuild == true and meta.notifyMuted ~= true
end

function Store:SetGuildLoginNotifyEnabled(rawNameOrKey, enabled)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return false end
    local on = (enabled == true)
    self:SetSocialMeta(key, {
        notifyGuild = on,
        notifyMuted = false,
    })
    return on
end

function Store:GetRecentCompanionsTable(forcePrune)
    local root = ns.db and ns.db.recentCompanions
    if not root then return {} end
    local tbl = self:EnsureScopedBucket(root, "recentCompanions")
    local scope = Compat.ScopeKey()
    self._companionPruneAt = self._companionPruneAt or {}
    local nowT = GetTime and GetTime() or 0
    local lastAt = self._companionPruneAt[scope]
    if forcePrune or not lastAt or (nowT - lastAt) >= 60 then
        self._companionPruneAt[scope] = nowT
        local now = time()
        for k, rec in pairs(tbl) do
            if type(rec) ~= "table" or (rec.lastSeen and (now - rec.lastSeen) > COMPANION_TTL) then
                tbl[k] = nil
            end
        end
    end
    return tbl
end

function Store:RecordCompanion(info)
    if type(info) ~= "table" or not info.displayName or info.displayName == "" then return end
    if Compat.IsMe(info.displayName, info.guid) then return end
    local parsed = Compat.ParseCharacterName(info.displayName)
    if not parsed then return end
    local tbl = self:GetRecentCompanionsTable()
    if parsed.surname and tbl[parsed.firstName:lower()] then
        local old = tbl[parsed.firstName:lower()]
        if not info.classFile and old.classFile then info.classFile = old.classFile end
        if (not info.level or info.level <= 0) and old.level then info.level = old.level end
        tbl[parsed.firstName:lower()] = nil
    end
    local existing = tbl[parsed.lookupKey] or {}
    local now = time()
    local runs = tonumber(existing.runs) or 0
    local lastRunAt = tonumber(existing.lastRunAt) or 0
    if runs == 0 or (now - lastRunAt) >= 1800 or (info.zone and info.zone ~= "" and existing.zone and info.zone ~= existing.zone) then
        runs = runs + 1
        lastRunAt = now
    end
    tbl[parsed.lookupKey] = {
        lookupKey = parsed.lookupKey,
        displayName = parsed.displayName,
        classFile = info.classFile or existing.classFile,
        level = (info.level and info.level > 0) and info.level or existing.level,
        role = info.role or existing.role,
        zone = (info.zone and info.zone ~= "") and info.zone or existing.zone,
        lastSeen = now,
        runs = runs,
        lastRunAt = lastRunAt,
    }

    local count, oldestKey, oldestScore = 0, nil, nil
    for k, rec in pairs(tbl) do
        if type(rec) == "table" then
            count = count + 1
            local seen = tonumber(rec.lastSeen) or 0
            local runs = math.min(5, math.max(1, tonumber(rec.runs) or 1))
            local evictScore = seen + (runs * 86400)
            if not oldestScore or evictScore < oldestScore then
                oldestKey, oldestScore = k, evictScore
            end
        end
    end
    if count == MAX_RECENT_COMPANIONS + 1 and oldestKey then
        tbl[oldestKey] = nil
    elseif count > MAX_RECENT_COMPANIONS + 1 then
        local list = self:GetRecentCompanionsList()
        if #list > MAX_RECENT_COMPANIONS then
            for i = MAX_RECENT_COMPANIONS + 1, #list do
                tbl[list[i].lookupKey] = nil
            end
        end
    end
end

function Store:GetRecentCompanion(rawNameOrKey)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then return nil end
    local lk = Compat.ParseCharacterFields and Compat.ParseCharacterFields(rawNameOrKey)
    if not lk then
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(rawNameOrKey)
        lk = parsed and parsed.lookupKey
    end
    if not lk then return nil end
    return self:GetRecentCompanionsTable()[lk]
end

--- Time-decayed frecency + explicit feedback social affinity score (returns -1000 for AVOID).
function Store:GetPlayerAffinityScore(rawNameOrKey, nowTs)
    local key = NormalizeMetaKey(rawNameOrKey)
    if not key then return 0 end
    if self:IsAccountIgnored(key) then
        return -1000
    end
    local now = nowTs or time()
    local score = 0
    local meta = self:GetResolvedSocialMeta(key)
    if meta then
        if meta.flag == "AVOID" then
            return -1000
        end
        if meta.favorite == true then
            score = score + 180
        end
        if meta.flag == "GOOD" then
            score = score + 140
        end
    end
    local compTbl = self:GetRecentCompanionsTable()
    local comp = compTbl and compTbl[key]
    if type(comp) == "table" then
        local runs = math.max(1, tonumber(comp.runs) or 1)
        local ageDays = math.max(0, (now - (tonumber(comp.lastSeen) or now)) / 86400)
        local decay = 1 / (1 + ageDays * 0.35)
        score = score + math.floor((35 * math.log(1 + runs) * decay) + 0.5)
    end
    if ns.Chat and type(ns.Chat.threads) == "table" then
        local th = ns.Chat.threads["w:" .. key]
        if type(th) == "table" then
            local rawLast = tonumber(th.lastAt)
            local rawUpdated = tonumber(th.updatedAt)
            local chatTs = (rawLast and rawLast > 0) and rawLast or ((rawUpdated and rawUpdated > 0) and rawUpdated or 0)
            if chatTs > 0 then
                local chatAgeHours = math.max(0, (now - chatTs) / 3600)
                local chatDecay = 1 / (1 + chatAgeHours * 0.08)
                score = score + math.floor((60 * chatDecay) + 0.5)
            end
        end
    end
    return score
end

function Store:GetRecentCompanionsList()
    local out = {}
    for _, rec in pairs(self:GetRecentCompanionsTable()) do
        if type(rec) == "table" then
            table.insert(out, rec)
        end
    end
    table.sort(out, function(a, b)
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return out
end

local function CompactOrPruneClanBucket(bucket, scopeKey, nowTs)
    if type(bucket) ~= "table" then return end
    if scopeKey and scopeKey:find("::_noguild", 1, true) then
        bucket.rosterSnapshot = nil
        return
    end
    local snap = bucket.rosterSnapshot
    if type(snap) ~= "table" then return end
    if snap.updatedAt and (nowTs - snap.updatedAt) > (30 * 86400) then
        bucket.rosterSnapshot = nil
        return
    end
    if type(snap.members) == "table" then
        local buf = {}
        local n = 0
        for lk, val in pairs(snap.members) do
            local cleanLk = tostring(lk):gsub("[\t\r\n]", "")
            local packedLine
            if type(val) == "string" then
                packedLine = cleanLk .. "\t" .. val:gsub("[\r\n]", " ")
            elseif type(val) == "table" then
                packedLine = cleanLk .. "\t" .. tostring(val.name or ""):gsub("[\t\r\n]", " ") .. "\t" .. tostring(val.rank or ""):gsub("[\t\r\n]", " ")
            end
            if packedLine then
                n = n + 1
                buf[n] = packedLine
            end
        end
        snap.packed = table.concat(buf, "\n")
        snap.members = nil
        snap.updatedAt = snap.updatedAt or nowTs
    end
end

local function MergeMissingEntries(dst, src, fieldKind)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(dst[k]) == "table" and type(v) == "table" then
            local cur = dst[k]
            if fieldKind == "chatHistory" then
                if type(v.lines) == "table" and #v.lines > 0 then
                    cur.lines = type(cur.lines) == "table" and cur.lines or {}
                    local seen = {}
                    for i = 1, #cur.lines do
                        local ln = cur.lines[i]
                        if type(ln) == "table" then
                            seen[tostring(ln.ts or 0) .. "|" .. tostring(ln.sender or "") .. "|" .. tostring(ln.text or "")] = true
                        end
                    end
                    local added = false
                    for i = 1, #v.lines do
                        local ln = v.lines[i]
                        if type(ln) == "table" then
                            local sig = tostring(ln.ts or 0) .. "|" .. tostring(ln.sender or "") .. "|" .. tostring(ln.text or "")
                            if not seen[sig] then
                                seen[sig] = true
                                cur.lines[#cur.lines + 1] = ln
                                added = true
                            end
                        end
                    end
                    if added then
                        table.sort(cur.lines, function(a, b)
                            return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
                        end)
                    end
                end
                cur.updatedAt = math.max(tonumber(cur.updatedAt) or 0, tonumber(v.updatedAt) or 0)
                if not cur.faction and v.faction then cur.faction = v.faction end
                if not cur.targetName and v.targetName then cur.targetName = v.targetName end
                if not cur.guildName and v.guildName then cur.guildName = v.guildName end
                if not cur.title and v.title then cur.title = v.title end
            elseif fieldKind == "watchlist" then
                if v.favorite == true then cur.favorite = true end
                if v.notifyMuted == true then cur.notifyMuted = true end
                if (not cur.note or cur.note == "") and v.note and v.note ~= "" then cur.note = v.note end
                if (not cur.group or cur.group == "") and v.group and v.group ~= "" then cur.group = v.group end
                if (not cur.guid or cur.guid == "") and v.guid and v.guid ~= "" then cur.guid = v.guid end
                if (not cur.guild or cur.guild == "") and v.guild and v.guild ~= "" then cur.guild = v.guild end
                if (not cur.classFile or cur.classFile == "") and v.classFile and v.classFile ~= "" then cur.classFile = v.classFile end
                if (tonumber(v.addedAt) or 0) > 0 and ((tonumber(cur.addedAt) or 0) == 0 or v.addedAt < cur.addedAt) then
                    cur.addedAt = v.addedAt
                end
                if v.displayName and v.displayName ~= "" and Compat and Compat.ParseCharacterName then
                    local vp = Compat.ParseCharacterName(v.displayName)
                    if vp and vp.displayName then
                        cur.displayName = vp.displayName
                        cur.firstName = vp.firstName or cur.firstName
                        cur.surname = vp.surname or cur.surname
                    end
                end
            else
                for sk, sv in pairs(v) do
                    if cur[sk] == nil or cur[sk] == "" then
                        cur[sk] = sv
                    end
                end
            end
        end
    end
end

--- Consolidate split sub-realm/cluster shard keys (e.g. camwowus1realm6pvp / camwowus2realmpvp -> camwowrealmpvp),
--- repair surname-corrupted Forever alt/scope buckets (e.g. "camarada:Horde" -> "camwowrealmpvp:Horde"),
--- recover character scopes if Forever rotates/renames backend realms (matched via immutable player GUID),
--- and pack legacy guild roster snapshots to eliminate SavedVariables & boot memory bloat.
function Store:NormalizeLegacyRealmScopes()
    if not (ns.db and Compat and Compat.RealmPool) then return end
    local nowTs = time()
    local isValidRealmFn = Compat.LooksLikeServerRealm
    local plainFn = Compat.Plain

    -- Step 1: Repair alt entries whose realmName/realmPool was previously polluted by a Forever surname (non-realm token)
    -- and collect known surname keys so orphaned surname-named scopes are always rescued safely.
    local surnamePoolSet = {}
    local validByGuildFaction = {}
    local bestFactionPool = {}
    if type(ns.db.alts) == "table" then
        for _, info in pairs(ns.db.alts) do
            if type(info) == "table" then
                if type(info.surname) == "string" and info.surname ~= "" then
                    local sp = plainFn and plainFn(info.surname) or info.surname:lower()
                    if sp ~= "" and (not isValidRealmFn or not isValidRealmFn(info.surname)) then
                        surnamePoolSet[sp] = true
                    end
                end
                local candRealm = info.realmName or info.realmRaw or info.realmPool
                if type(candRealm) == "string" and candRealm ~= "" and (not isValidRealmFn or isValidRealmFn(candRealm)) then
                    local norm = Compat.RealmPool(candRealm)
                    if norm and norm ~= "" and norm ~= "default" then
                        info.realmPool = norm
                        local fac = info.faction or ""
                        if type(info.guild) == "string" and info.guild ~= "" then
                            local gk = fac .. "::" .. info.guild
                            if not validByGuildFaction[gk] or (info.lastActive or 0) > (validByGuildFaction[gk].lastActive or 0) then
                                validByGuildFaction[gk] = {
                                    realmName = info.realmName,
                                    realmRaw = info.realmRaw,
                                    worldType = info.worldType,
                                    realmPool = norm,
                                    lastActive = info.lastActive or 0,
                                }
                            end
                        end
                        if fac ~= "" then
                            if not bestFactionPool[fac] or (info.lastActive or 0) > (bestFactionPool[fac].lastActive or 0) then
                                bestFactionPool[fac] = {
                                    realmName = info.realmName,
                                    realmRaw = info.realmRaw,
                                    worldType = info.worldType,
                                    realmPool = norm,
                                    lastActive = info.lastActive or 0,
                                }
                            end
                        end
                    end
                end
            end
        end

        for _, info in pairs(ns.db.alts) do
            if type(info) == "table" then
                local rName = info.realmName
                local hasValidRealm = type(rName) == "string" and rName ~= "" and (not isValidRealmFn or isValidRealmFn(rName))
                local matchesOwnSurname = type(rName) == "string" and rName ~= "" and type(info.surname) == "string" and info.surname ~= ""
                    and ((plainFn and plainFn(rName) or rName:lower()) == (plainFn and plainFn(info.surname) or info.surname:lower()))
                local isPollutedBySurname = (not hasValidRealm) and ((not info.realmRaw or info.realmRaw == "") or matchesOwnSurname)
                if isPollutedBySurname then
                    -- If realmName actually holds the stripped Forever surname (e.g. "Camarada"), restore fullName/surname.
                    if type(rName) == "string" and rName ~= "" then
                        local rp = plainFn and plainFn(rName) or rName:lower()
                        if rp ~= "" then
                            surnamePoolSet[rp] = true
                        end
                        if (not info.surname or info.surname == "") and type(info.firstName or info.name) == "string" and (info.firstName or info.name) ~= "" then
                            local capS = Compat.CapitalizeNameWord and Compat.CapitalizeNameWord(rName) or rName
                            local capF = Compat.CapitalizeNameWord and Compat.CapitalizeNameWord(info.firstName or info.name) or (info.firstName or info.name)
                            info.firstName = capF
                            info.surname = capS
                            info.fullName = capF .. " " .. capS
                        end
                    end
                    local fac = info.faction or ""
                    local repair = (type(info.guild) == "string" and info.guild ~= "") and validByGuildFaction[fac .. "::" .. info.guild] or nil
                    if not repair and fac ~= "" and bestFactionPool[fac] then
                        repair = bestFactionPool[fac]
                    end
                    if repair then
                        info.realmName = repair.realmName
                        info.realmRaw = repair.realmRaw or info.realmRaw
                        info.worldType = repair.worldType or info.worldType
                        info.realmPool = repair.realmPool
                    end
                end
            end
        end
    end

    -- Inspect live character GUID after repairing surname-polluted alt entries so Compat.Realm() resolves cleanly.
    local safeStr = ns.Safe and ns.Safe.String
    local safeCall = ns.Safe and ns.Safe.Call
    local myGuid = (safeStr and safeCall and UnitGUID) and safeStr(safeCall(UnitGUID, "player")) or nil
    local liveRealm = Compat.Realm and Compat.Realm() or ""
    local livePool = (liveRealm ~= "") and Compat.RealmPool(liveRealm) or nil
    local liveFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local prevGuidPool = nil
    if myGuid and myGuid ~= "" and type(ns.db.alts) == "table" then
        local existingAlt = ns.db.alts["guid:" .. myGuid]
        if type(existingAlt) == "table" then
            local rawOld = existingAlt.realmPool or existingAlt.realmName
            if type(rawOld) == "string" and rawOld ~= "" and (not isValidRealmFn or isValidRealmFn(rawOld)) then
                prevGuidPool = Compat.RealmPool(rawOld)
            end
        end
    end

    local scopedKeys = {
        "watchlist", "socialMeta", "friendPresence", "recentCompanions",
        "observedAlts", "locationShareAllow", "chatHistory", "chatRooms", "addonPeers",
    }

    local function mergeClanBucketData(dst, src)
        if type(dst) ~= "table" or type(src) ~= "table" then return end
        if (not dst.myTag or dst.myTag == "" or dst.myTag == "NONE") and src.myTag and src.myTag ~= "" and src.myTag ~= "NONE" then
            dst.myTag = src.myTag
        end
        if (not dst.myNote or dst.myNote == "") and src.myNote and src.myNote ~= "" then
            dst.myNote = src.myNote
        end
        if (not dst.myProf1 or dst.myProf1 == "" or dst.myProf1 == "NONE") and src.myProf1 and src.myProf1 ~= "" and src.myProf1 ~= "NONE" then
            dst.myProf1 = src.myProf1
            dst.myProf1Rank = src.myProf1Rank or dst.myProf1Rank
        end
        if (not dst.myProf2 or dst.myProf2 == "" or dst.myProf2 == "NONE") and src.myProf2 and src.myProf2 ~= "" and src.myProf2 ~= "NONE" then
            dst.myProf2 = src.myProf2
            dst.myProf2Rank = src.myProf2Rank or dst.myProf2Rank
        end
        if (not dst.myCraftNote or dst.myCraftNote == "") and src.myCraftNote and src.myCraftNote ~= "" then
            dst.myCraftNote = src.myCraftNote
        end
        MergeMissingEntries(dst.peers, src.peers)
        MergeMissingEntries(dst.events, src.events)
        MergeMissingEntries(dst.lfg, src.lfg)
        if type(src.recipesCache) == "table" then
            dst.recipesCache = type(dst.recipesCache) == "table" and dst.recipesCache or {}
            MergeMissingEntries(dst.recipesCache, src.recipesCache)
        end
        if type(dst.diplomacy) == "table" and type(src.diplomacy) == "table" then
            MergeMissingEntries(dst.diplomacy.guilds, src.diplomacy.guilds)
            if (tonumber(src.diplomacy.rev) or 0) > (tonumber(dst.diplomacy.rev) or 0) then
                dst.diplomacy.rev = src.diplomacy.rev
                dst.diplomacy.updatedAt = src.diplomacy.updatedAt
                dst.diplomacy.updatedBy = src.diplomacy.updatedBy
            end
        end
        if type(src.clanInfo) == "table" and (type(dst.clanInfo) ~= "table" or (tonumber(src.clanInfo.rev) or 0) > (tonumber(dst.clanInfo.rev) or 0)) then
            dst.clanInfo = src.clanInfo
        end
        if type(src.hierarchy) == "table" and (type(dst.hierarchy) ~= "table" or (tonumber(src.hierarchy.rev) or 0) > (tonumber(dst.hierarchy.rev) or 0)) then
            dst.hierarchy = src.hierarchy
        end
        if type(src.alliance) == "table" then
            if type(dst.alliance) ~= "table" then
                dst.alliance = src.alliance
            else
                if src.alliance.enabled == true then dst.alliance.enabled = true end
                if (not dst.alliance.name or dst.alliance.name == "") and src.alliance.name and src.alliance.name ~= "" then
                    dst.alliance.name = src.alliance.name
                end
                if (not dst.alliance.token or dst.alliance.token == "") and src.alliance.token and src.alliance.token ~= "" then
                    dst.alliance.token = src.alliance.token
                end
                MergeMissingEntries(dst.alliance.whitelist, src.alliance.whitelist)
                MergeMissingEntries(dst.alliance.managers, src.alliance.managers)
                MergeMissingEntries(dst.alliance.alliedGuilds, src.alliance.alliedGuilds)
            end
        end
    end

    local function migratePoolScope(oldPool, newPool, onlyFaction)
        if not oldPool or not newPool or oldPool == "" or newPool == "" or oldPool == newPool or newPool == "default" then
            return
        end
        for _, field in ipairs(scopedKeys) do
            local root = ns.db[field]
            if type(root) == "table" then
                local toMove = nil
                for scopeKey, sub in pairs(root) do
                    if type(scopeKey) == "string" then
                        local pool, rest = scopeKey:match("^([^:]+):(.+)$")
                        if pool == oldPool and rest and (not onlyFaction or rest == onlyFaction) then
                            toMove = toMove or {}
                            toMove[scopeKey] = { target = newPool .. ":" .. rest, data = sub }
                        end
                    end
                end
                if toMove then
                    for oldKey, item in pairs(toMove) do
                        if type(item.data) == "table" then
                            if type(root[item.target]) ~= "table" then
                                root[item.target] = item.data
                            else
                                MergeMissingEntries(root[item.target], item.data, field)
                            end
                        end
                        root[oldKey] = nil
                    end
                end
            end
        end
        if type(ns.db.clan) == "table" then
            local clanToMove = nil
            for scopeKey, bucket in pairs(ns.db.clan) do
                if type(scopeKey) == "string" then
                    local pool, rest = scopeKey:match("^([^:]+):(.+)$")
                    local fac = rest and rest:match("^([^:]+)")
                    if pool == oldPool and rest and (not onlyFaction or fac == onlyFaction) then
                        clanToMove = clanToMove or {}
                        clanToMove[scopeKey] = { target = newPool .. ":" .. rest, data = bucket }
                    end
                end
            end
            if clanToMove then
                for oldKey, item in pairs(clanToMove) do
                    if type(item.data) == "table" then
                        local dst = ns.db.clan[item.target]
                        if type(dst) ~= "table" then
                            ns.db.clan[item.target] = item.data
                        else
                            mergeClanBucketData(dst, item.data)
                        end
                    end
                    ns.db.clan[oldKey] = nil
                end
            end
        end
        for _, wbField in ipairs({ "worldBuffsDrops", "worldBuffsHistory" }) do
            local wbRoot = ns.db[wbField]
            if type(wbRoot) == "table" then
                local wbMove = nil
                for poolKey, sub in pairs(wbRoot) do
                    if type(poolKey) == "string" and (poolKey == oldPool or (plainFn and plainFn(poolKey) == oldPool)) then
                        wbMove = wbMove or {}
                        wbMove[poolKey] = sub
                    end
                end
                if wbMove then
                    for oldKey, sub in pairs(wbMove) do
                        if type(sub) == "table" then
                            if type(wbRoot[newPool]) ~= "table" then
                                wbRoot[newPool] = sub
                            else
                                MergeMissingEntries(wbRoot[newPool], sub)
                            end
                        end
                        wbRoot[oldKey] = nil
                    end
                end
            end
        end
    end

    -- Step 2: Consolidate all numbered/regional Forever shards (camwowus1realmpvp -> camwowrealmpvp).
    for _, field in ipairs(scopedKeys) do
        local root = ns.db[field]
        if type(root) == "table" then
            local toMove = nil
            for scopeKey, sub in pairs(root) do
                if type(scopeKey) == "string" then
                    local pool, rest = scopeKey:match("^([^:]+):(.+)$")
                    if pool and rest then
                        local normPool = Compat.RealmPool(pool)
                        if normPool and normPool ~= "" and normPool ~= pool then
                            local targetKey = normPool .. ":" .. rest
                            if not toMove then toMove = {} end
                            toMove[scopeKey] = { target = targetKey, data = sub }
                        end
                    end
                end
            end
            if toMove then
                for oldKey, item in pairs(toMove) do
                    if type(item.data) == "table" then
                        if type(root[item.target]) ~= "table" then
                            root[item.target] = item.data
                        else
                            MergeMissingEntries(root[item.target], item.data, field)
                        end
                    end
                    root[oldKey] = nil
                end
            end
        end
    end

    if type(ns.db.clan) == "table" then
        local clanToMove = nil
        for scopeKey, bucket in pairs(ns.db.clan) do
            if type(bucket) == "table" then
                CompactOrPruneClanBucket(bucket, scopeKey, nowTs)
            end
            if type(scopeKey) == "string" then
                local pool, rest = scopeKey:match("^([^:]+):(.+)$")
                if pool and rest then
                    local normPool = Compat.RealmPool(pool)
                    if normPool and normPool ~= "" and normPool ~= pool then
                        local targetKey = normPool .. ":" .. rest
                        if not clanToMove then clanToMove = {} end
                        clanToMove[scopeKey] = { target = targetKey, data = bucket }
                    end
                end
            end
        end
        if clanToMove then
            for oldKey, item in pairs(clanToMove) do
                if type(item.data) == "table" then
                    local dst = ns.db.clan[item.target]
                    if type(dst) ~= "table" then
                        ns.db.clan[item.target] = item.data
                    else
                        mergeClanBucketData(dst, item.data)
                    end
                end
                ns.db.clan[oldKey] = nil
            end
        end
    end

    for _, wbField in ipairs({ "worldBuffsDrops", "worldBuffsHistory" }) do
        local wbRoot = ns.db[wbField]
        if type(wbRoot) == "table" then
            local wbMove = nil
            for poolKey, sub in pairs(wbRoot) do
                if type(poolKey) == "string" then
                    local normPool = Compat.RealmPool(poolKey)
                    if normPool and normPool ~= "" and normPool ~= poolKey then
                        wbMove = wbMove or {}
                        wbMove[poolKey] = { target = normPool, data = sub }
                    end
                end
            end
            if wbMove then
                for oldKey, item in pairs(wbMove) do
                    if type(item.data) == "table" then
                        if type(wbRoot[item.target]) ~= "table" then
                            wbRoot[item.target] = item.data
                        else
                            MergeMissingEntries(wbRoot[item.target], item.data)
                        end
                    end
                    wbRoot[oldKey] = nil
                end
            end
        end
    end

    -- Step 3: Self-healing rescue of any orphaned "default" or surname-corrupted scopes (e.g. "camarada:Horde")
    -- back into the canonical real-world pool so upgrades or Forever shard hiccups never hide user history.
    local rescueTargetPool = (livePool and livePool ~= "" and livePool ~= "default" and (not isValidRealmFn or isValidRealmFn(livePool)))
        and livePool
        or (liveFaction and bestFactionPool[liveFaction] and bestFactionPool[liveFaction].realmPool)
        or nil

    if rescueTargetPool and rescueTargetPool ~= "" and rescueTargetPool ~= "default" then
        for badPool in pairs(surnamePoolSet) do
            if badPool ~= rescueTargetPool and (not isValidRealmFn or not isValidRealmFn(badPool)) then
                migratePoolScope(badPool, rescueTargetPool, nil)
            end
        end
        if liveFaction then
            migratePoolScope("default", rescueTargetPool, liveFaction)
            if prevGuidPool and prevGuidPool ~= "" and prevGuidPool ~= "default" and prevGuidPool ~= rescueTargetPool then
                local oldWt = Compat.DetectWorldType and Compat.DetectWorldType(prevGuidPool) or nil
                local curWt = Compat.DetectWorldType and Compat.DetectWorldType(rescueTargetPool) or nil
                local rulesetCompatible = (oldWt == curWt) or (oldWt == nil) or (curWt == nil)
                if rulesetCompatible then
                    migratePoolScope(prevGuidPool, rescueTargetPool, liveFaction)
                end
            end
        end
    end

    if type(ns.db.worldBuffsPersonal) == "table" then
        local persMove = nil
        for charKey, rec in pairs(ns.db.worldBuffsPersonal) do
            if type(charKey) == "string" and type(rec) == "table" then
                local cName, pool = charKey:match("^(.+)@([^@]+)$")
                if cName and pool then
                    local normPool = Compat.RealmPool(pool)
                    if (pool == "default" or surnamePoolSet[pool] or (isValidRealmFn and not isValidRealmFn(pool))) and rescueTargetPool then
                        normPool = rescueTargetPool
                    end
                    if normPool and normPool ~= "" and normPool ~= pool then
                        persMove = persMove or {}
                        persMove[charKey] = { target = cName .. "@" .. normPool, data = rec }
                    end
                end
            end
        end
        if persMove then
            for oldKey, item in pairs(persMove) do
                if type(ns.db.worldBuffsPersonal[item.target]) ~= "table" then
                    ns.db.worldBuffsPersonal[item.target] = item.data
                else
                    MergeMissingEntries(ns.db.worldBuffsPersonal[item.target], item.data)
                end
                ns.db.worldBuffsPersonal[oldKey] = nil
            end
        end
    end

    -- Rescues orphaned generic "::guild" clan placeholder bucket once the live guild name is known.
    local activeGuild = (self.guildInfo and self.guildInfo.inGuild and self.guildInfo.name)
        or (IsInGuild and ns.Safe and ns.Safe.Value(IsInGuild()) == true and GetGuildInfo and ns.Safe.String(ns.Safe.Call(GetGuildInfo, "player")))
        or nil
    if type(ns.db.clan) == "table" and activeGuild and activeGuild ~= "" and liveFaction and rescueTargetPool then
        local placeholderKey = rescueTargetPool .. ":" .. liveFaction .. "::guild"
        local realGuildKey = rescueTargetPool .. ":" .. liveFaction .. "::" .. (plainFn and plainFn(activeGuild) or activeGuild:lower())
        if placeholderKey ~= realGuildKey and type(ns.db.clan[placeholderKey]) == "table" then
            if type(ns.db.clan[realGuildKey]) ~= "table" then
                ns.db.clan[realGuildKey] = ns.db.clan[placeholderKey]
            else
                mergeClanBucketData(ns.db.clan[realGuildKey], ns.db.clan[placeholderKey])
            end
            ns.db.clan[placeholderKey] = nil
        end
    end

    self:InvalidateScopeCaches()
    if self.PruneExpiredAccountIgnores then
        self:PruneExpiredAccountIgnores(true)
    end
end

local function EscapeExportField(raw)
    local s = tostring(raw or "")
    s = s:gsub("%%", "%%25"):gsub("~", "%%7E"):gsub("\r", " "):gsub("\n", " ")
    return s
end

local function UnescapeExportField(raw)
    if type(raw) ~= "string" then return "" end
    local s = raw:gsub("%%7[Ee]", "~"):gsub("%%25", "%%")
    return s
end

local function SplitTildeLine(line)
    local out = {}
    local startIdx = 1
    while true do
        local pos = line:find("~", startIdx, true)
        if not pos then
            out[#out + 1] = UnescapeExportField(line:sub(startIdx))
            break
        end
        out[#out + 1] = UnescapeExportField(line:sub(startIdx, pos - 1))
        startIdx = pos + 1
    end
    return out
end

function Store:ExportSocialDataString()
    local lines = { "SC1" }
    local igCount, metaCount, wlCount = 0, 0, 0

    local igTbl = self:GetAccountIgnoresTable()
    local igKeys = {}
    for k in pairs(igTbl) do igKeys[#igKeys + 1] = k end
    table.sort(igKeys)
    local now = time()
    for _, k in ipairs(igKeys) do
        local r = igTbl[k]
        if type(r) == "table" and (not r.expiresAt or r.expiresAt == 0 or r.expiresAt > now)
            and not tostring(k):find("#", 1, true) and not tostring(r.name or ""):find("#", 1, true) then
            lines[#lines + 1] = table.concat({
                "I",
                EscapeExportField(k),
                EscapeExportField(r.name or k),
                EscapeExportField(r.reason or "OTHER"),
                tostring(tonumber(r.expiresAt) or 0),
                (r.hideChat ~= false) and "1" or "0",
                EscapeExportField(r.note or ""),
            }, "~")
            igCount = igCount + 1
        end
    end

    local metaTbl = self:GetSocialMetaTable()
    local metaKeys = {}
    for k in pairs(metaTbl) do metaKeys[#metaKeys + 1] = k end
    table.sort(metaKeys)
    for _, k in ipairs(metaKeys) do
        local m = metaTbl[k]
        if type(m) == "table" and not tostring(k):find("#", 1, true) then
            lines[#lines + 1] = table.concat({
                "M",
                EscapeExportField(k),
                EscapeExportField(m.flag or ""),
                m.favorite and "1" or "0",
                EscapeExportField(m.nickname or ""),
                EscapeExportField(m.mainName or ""),
                EscapeExportField(m.folder or ""),
                EscapeExportField(m.note or ""),
            }, "~")
            metaCount = metaCount + 1
        end
    end

    local wlTbl = self:GetWatchlistTable()
    local wlKeys = {}
    for k in pairs(wlTbl) do wlKeys[#wlKeys + 1] = k end
    table.sort(wlKeys)
    for _, k in ipairs(wlKeys) do
        local w = wlTbl[k]
        if type(w) == "table" and not tostring(k):find("#", 1, true) then
            lines[#lines + 1] = table.concat({
                "W",
                EscapeExportField(k),
                EscapeExportField(w.displayName or w.firstName or k),
                EscapeExportField(w.group or ""),
                w.favorite and "1" or "0",
                EscapeExportField(w.note or ""),
            }, "~")
            wlCount = wlCount + 1
        end
    end

    return table.concat(lines, "\n"), igCount, metaCount, wlCount
end

function Store:ImportSocialDataString(rawStr)
    if type(rawStr) ~= "string" then
        return false, 0, 0, 0
    end
    local sawHeader = false
    local igCount, metaCount, wlCount = 0, 0, 0
    local now = time()
    local wlTbl = self:GetWatchlistTable()

    for line in rawStr:gmatch("[^\r\n]+") do
        local trimmed = Compat.Trim(line)
        if trimmed == "SC1" then
            sawHeader = true
        elseif sawHeader and trimmed ~= "" then
            local parts = SplitTildeLine(trimmed)
            local recType = parts[1]
            local rawKey = parts[2]
            if rawKey and rawKey ~= "" and not rawKey:find("#", 1, true) and not rawKey:find("|K", 1, true) then
                if recType == "I" then
                    local dispName = (parts[3] and parts[3] ~= "") and parts[3] or rawKey
                    local reason = parts[4] or "OTHER"
                    local expiresAt = tonumber(parts[5]) or 0
                    local hideChat = (parts[6] ~= "0")
                    local note = parts[7] or ""
                    if (expiresAt == 0 or expiresAt > now) and not (Compat.IsMe and Compat.IsMe(dispName)) then
                        local res = self:SetAccountIgnore(rawKey, {
                            name = dispName,
                            reason = reason,
                            expiresAt = expiresAt,
                            hideChat = hideChat,
                            note = note ~= "" and note or nil,
                        })
                        if res then igCount = igCount + 1 end
                    end
                elseif recType == "M" then
                    local flag = parts[3] or ""
                    local fav = (parts[4] == "1")
                    local nick = parts[5] or ""
                    local mainName = parts[6] or ""
                    local folder = parts[7] or ""
                    local note = parts[8] or ""
                    local patch = {}
                    if flag == "GOOD" or flag == "AVOID" then patch.flag = flag end
                    if fav then patch.favorite = true end
                    if nick ~= "" then patch.nickname = nick end
                    if mainName ~= "" then patch.mainName = mainName end
                    if folder ~= "" then patch.folder = folder end
                    if note ~= "" then patch.note = note end
                    if next(patch) ~= nil then
                        local curMeta = self:GetSocialMeta(rawKey) or {}
                        if curMeta.flag and not patch.flag then patch.flag = curMeta.flag end
                        if curMeta.favorite and not patch.favorite then patch.favorite = curMeta.favorite end
                        if self:SetSocialMeta(rawKey, patch) then
                            metaCount = metaCount + 1
                        end
                    end
                elseif recType == "W" and Compat.ParseCharacterName then
                    local disp = (parts[3] and parts[3] ~= "") and parts[3] or rawKey
                    local grp = parts[4] or ""
                    local fav = (parts[5] == "1")
                    local note = parts[6] or ""
                    if not (Compat.IsMe and Compat.IsMe(disp)) then
                        local parsed = Compat.ParseCharacterName(disp)
                        if parsed and parsed.lookupKey then
                            local existing = wlTbl[parsed.lookupKey]
                            if not existing then
                                wlTbl[parsed.lookupKey] = {
                                    id = parsed.lookupKey,
                                    displayName = parsed.displayName,
                                    firstName = parsed.firstName,
                                    surname = parsed.surname,
                                    status = "unknown",
                                    group = (grp ~= "") and grp or nil,
                                    favorite = fav and true or nil,
                                    note = (note ~= "") and note or nil,
                                    addedAt = now,
                                }
                                wlCount = wlCount + 1
                            else
                                if (not existing.note or existing.note == "") and note ~= "" then existing.note = note end
                                if (not existing.group or existing.group == "") and grp ~= "" then existing.group = grp end
                                if fav then existing.favorite = true end
                            end
                        end
                    end
                end
            end
        end
    end

    if not sawHeader then
        return false, 0, 0, 0
    end
    self:InvalidateWatchlistIndex()
    ns:Emit("SOCIAL_UPDATED")
    ns:Emit("WATCHLIST_UPDATED")
    ns:Emit("ACCOUNT_IGNORES_UPDATED")
    ns:Emit("CHAT_UPDATED")
    return true, igCount, metaCount, wlCount
end
