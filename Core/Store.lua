local _, ns = ...

local Compat = ns.Compat

-- Unified social store bridging live Social rosters, Nearby passive sightings,
-- Account Alts, and Watchlist entries.
local Store = {
    social = {},       -- [key] -> row
    nearby = {},       -- [lookupKey] -> row
    guildInfo = {
        inGuild = false,
        name = nil,
        motd = nil,
        onlineCount = 0,
        totalCount = 0,
    },
}

ns.Store = Store

function Store:GetWatchlistTable()
    local root = ns.db and ns.db.watchlist
    if not root then return {} end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

local CLAN_PEER_TTL = 12 * 3600
local CLAN_EVENT_TTL = 24 * 3600
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
        if (not guildName or guildName == "") and ns.db and ns.db.alts and Compat.CharacterKey then
            local altRec = ns.db.alts[Compat.CharacterKey()]
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

function Store:GetAltsList()
    local out = {}
    local alts = ns.db and ns.db.alts or {}
    local currentKey = Compat.CharacterKey()
    local curPool = Compat.RealmPool(Compat.Realm())
    for key, info in pairs(alts) do
        if type(info) == "table" then
            local infoPool = info.realmPool and Compat.RealmPool(info.realmPool) or curPool
            if key == currentKey or infoPool == curPool then
                info.key = key
                table.insert(out, info)
            end
        end
    end
    table.sort(out, function(a, b)
        local aCur = (a.key == currentKey)
        local bCur = (b.key == currentKey)
        if aCur ~= bCur then
            return aCur
        end
        return (a.lastActive or 0) > (b.lastActive or 0)
    end)
    return out
end

function Store:GetAltsCount()
    local alts = ns.db and ns.db.alts
    if not alts then return 0 end
    local count = 0
    local currentKey = Compat.CharacterKey()
    local curPool = Compat.RealmPool(Compat.Realm())
    for key, info in pairs(alts) do
        if type(info) == "table" then
            local infoPool = info.realmPool and Compat.RealmPool(info.realmPool) or curPool
            if key == currentKey or infoPool == curPool then
                count = count + 1
            end
        end
    end
    return count
end

function Store:GetTotalAltsGold(poolOnly)
    local total = 0
    local curPool = poolOnly and Compat.RealmPool(Compat.Realm())
    for _, info in pairs(ns.db and ns.db.alts or {}) do
        if type(info) == "table" and tonumber(info.money) then
            local match = not curPool or (not info.realmPool) or info.realmPool == curPool
            if match then
                total = total + tonumber(info.money)
            end
        end
    end
    return total
end

function Store:NotifyWatchlistOnline(entry)
    if not entry then return end
    local alerts = ns.db and ns.db.settings and ns.db.settings.alerts
    if not alerts then return end

    -- Debounce duplicate login alerts per character within 120 seconds.
    local now = time()
    if entry.lastAlertAt and (now - entry.lastAlertAt) < 120 then
        return
    end
    entry.lastAlertAt = now

    if alerts.chat then
        local hex = Compat.ClassHex(entry.classFile)
        local label = hex .. (entry.displayName or "") .. "|r"
        if entry.area and entry.area ~= "" then
            ns:Print(ns.L["%s appears online (%s)."]:format(label, entry.area))
        else
            ns:Print(ns.L["%s is now online!"]:format(label))
        end
    end

    if alerts.sound and PlaySound and SOUNDKIT then
        local soundId = SOUNDKIT.TELL_MESSAGE or SOUNDKIT.UI_BNET_TOAST
        if soundId then
            pcall(PlaySound, soundId, "Master")
        end
    end
end

function Store:InvalidateWatchlistIndex()
    self._wlIndexDirty = true
end

-- Cross-pollinate Watchlist rows whenever live Social or Nearby detects a watched player.
function Store:SyncWatchlistObservation(rawName, data)
    local list = self:GetWatchlistTable()
    if next(list) == nil then return end
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed then return end

    if self._wlIndexDirty or self._wlIndexedRef ~= list or type(self._wlNoSurnameByFirst) ~= "table" then
        local byFirst = {}
        local idIndex = {}
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
            end
        end
        self._wlNoSurnameByFirst = byFirst
        self._wlIdMatches = idIndex
        self._wlIndexedRef = list
        self._wlIndexDirty = false
    end

    local firstLower = parsed.firstName and parsed.firstName:lower() or nil
    local directEntry = list[parsed.lookupKey]
    local idMatches = self._wlIdMatches and self._wlIdMatches[parsed.lookupKey]
    local firstMatches = firstLower and self._wlNoSurnameByFirst and self._wlNoSurnameByFirst[firstLower]
    if not (directEntry and directEntry.id == parsed.lookupKey) and not idMatches and not firstMatches then
        return
    end

    local now = time()
    local changed = false
    local keysToReindex

    local function ApplyObservation(idKey, entry)
        if type(entry) ~= "table" then return end
        local exactMatch = entry.id == parsed.lookupKey
        local firstMatch = firstLower and (not entry.surname) and entry.firstName and entry.firstName:lower() == firstLower
        if not (exactMatch or firstMatch) then return end

        local prevStatus = entry.status
        if data.online ~= nil then
            entry.status = data.online and "online" or "offline"
            entry.lastChecked = now
            entry.truncatedWarning = nil
        end
        if data.source then entry.source = data.source end
        if data.level and data.level > 0 then entry.level = data.level end
        if data.classFile then entry.classFile = data.classFile end
        if data.area and data.area ~= "" then entry.area = data.area end
        if data.guild and data.guild ~= "" then entry.guild = data.guild end
        if parsed.surname and parsed.surname ~= "" and (not entry.surname or entry.surname == "") then
            entry.surname = parsed.surname
            entry.displayName = parsed.displayName
            entry.truncatedWarning = nil
            self._wlIndexDirty = true
            if parsed.lookupKey ~= idKey and not list[parsed.lookupKey] then
                keysToReindex = keysToReindex or {}
                keysToReindex[#keysToReindex + 1] = { oldId = idKey, newId = parsed.lookupKey, entry = entry }
            end
        end
        if data.online then
            entry.lastSeen = now
            entry.lastChecked = now
            if prevStatus == "offline" then
                self:NotifyWatchlistOnline(entry)
            end
        end
        changed = true
    end

    if directEntry then
        ApplyObservation(parsed.lookupKey, directEntry)
    end
    if idMatches then
        for _, idKey in ipairs(idMatches) do
            if idKey ~= parsed.lookupKey then
                ApplyObservation(idKey, list[idKey])
            end
        end
    end
    if firstMatches then
        for _, idKey in ipairs(firstMatches) do
            if idKey ~= parsed.lookupKey then
                ApplyObservation(idKey, list[idKey])
            end
        end
    end

    if keysToReindex then
        for _, item in ipairs(keysToReindex) do
            item.entry.id = item.newId
            list[item.newId] = item.entry
            list[item.oldId] = nil
        end
        self._wlIndexDirty = true
    end

    if changed then
        ns:Emit("WATCHLIST_UPDATED")
    end
end

local MAX_RECENT_COMPANIONS = 40
local COMPANION_TTL = 7 * 86400

function Store:GetSocialMetaTable()
    local root = ns.db and ns.db.socialMeta
    if not root then return {} end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    return root[scope]
end

function Store:GetSocialMeta(rawNameOrKey)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then return nil end
    local parsed = Compat.ParseCharacterName(rawNameOrKey)
    local key = (parsed and parsed.lookupKey) or rawNameOrKey:lower()
    return self:GetSocialMetaTable()[key]
end

function Store:GetResolvedSocialMeta(rawNameOrKey)
    local direct = self:GetSocialMeta(rawNameOrKey)
    if not direct then return nil end
    if direct.flag or not direct.mainName or direct.mainName == "" then
        return direct
    end
    local mainMeta = self:GetSocialMeta(direct.mainName)
    if not mainMeta then
        return direct
    end
    return {
        folder = direct.folder or mainMeta.folder,
        mainName = direct.mainName,
        note = direct.note or mainMeta.note,
        flag = direct.flag or mainMeta.flag,
        updatedAt = direct.updatedAt or mainMeta.updatedAt,
    }
end

function Store:SetSocialMeta(rawNameOrKey, patch)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" or type(patch) ~= "table" then return nil end
    local parsed = Compat.ParseCharacterName(rawNameOrKey)
    local key = (parsed and parsed.lookupKey) or rawNameOrKey:lower()
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
    if patch.note ~= nil then
        local cleanNote = Compat.CleanInput(patch.note)
        rec.note = cleanNote or nil
    end
    if patch.flag ~= nil then
        if patch.flag == "AVOID" or patch.flag == "GOOD" then
            rec.flag = patch.flag
        else
            rec.flag = nil
        end
    end
    if not rec.folder and not rec.mainName and not rec.note and not rec.flag then
        tbl[key] = nil
    else
        rec.updatedAt = time()
        tbl[key] = rec
    end
    ns:Emit("SOCIAL_UPDATED")
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

function Store:GetSocialFolders()
    local seen, out = {}, {}
    for _, meta in pairs(self:GetSocialMetaTable()) do
        if type(meta) == "table" and type(meta.folder) == "string" and meta.folder ~= "" and not seen[meta.folder] then
            seen[meta.folder] = true
            table.insert(out, meta.folder)
        end
    end
    table.sort(out)
    return out
end

function Store:GetRecentCompanionsTable(forcePrune)
    local root = ns.db and ns.db.recentCompanions
    if not root then return {} end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    local tbl = root[scope]
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

    local count, oldestKey, oldestSeen = 0, nil, nil
    for k, rec in pairs(tbl) do
        if type(rec) == "table" then
            count = count + 1
            local seen = rec.lastSeen or 0
            if not oldestSeen or seen < oldestSeen then
                oldestKey, oldestSeen = k, seen
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
    local parsed = Compat.ParseCharacterName(rawNameOrKey)
    if not parsed then return nil end
    return self:GetRecentCompanionsTable()[parsed.lookupKey]
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
