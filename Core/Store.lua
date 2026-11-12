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

function Store:GetClanScopeData()
    local root = ns.db and ns.db.clan
    if not root then
        return { myTag = "NONE", myNote = "", peers = {}, events = {} }
    end
    local guildName = self.guildInfo and self.guildInfo.inGuild and (self.guildInfo.name or "guild") or "_noguild"
    local scope = Compat.ScopeKey() .. "::" .. Compat.Plain(guildName)
    local bucket = root[scope]
    if type(bucket) ~= "table" then
        bucket = { myTag = "NONE", myNote = "", peers = {}, events = {} }
        root[scope] = bucket
    end
    if type(bucket.peers) ~= "table" then bucket.peers = {} end
    if type(bucket.events) ~= "table" then bucket.events = {} end
    if type(bucket.myProf1) ~= "string" then bucket.myProf1 = "" end
    if type(bucket.myProf2) ~= "string" then bucket.myProf2 = "" end
    if type(bucket.myCraftNote) ~= "string" then bucket.myCraftNote = "" end

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

    return bucket
end

function Store:GetAltsList()
    local out = {}
    local alts = ns.db and ns.db.alts or {}
    for key, info in pairs(alts) do
        if type(info) == "table" then
            info.key = key
            table.insert(out, info)
        end
    end
    table.sort(out, function(a, b)
        return (a.lastActive or 0) > (b.lastActive or 0)
    end)
    return out
end

function Store:GetTotalAltsGold()
    local total = 0
    for _, info in pairs(ns.db and ns.db.alts or {}) do
        if type(info) == "table" and tonumber(info.money) then
            total = total + tonumber(info.money)
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

-- Cross-pollinate Watchlist rows whenever live Social or Nearby detects a watched player.
function Store:SyncWatchlistObservation(rawName, data)
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed then return end
    local list = self:GetWatchlistTable()
    local now = time()
    local changed = false

    for _, entry in pairs(list) do
        local exactMatch = entry.id == parsed.lookupKey
        local firstMatch = (not entry.surname) and entry.firstName:lower() == parsed.firstName:lower()
        if exactMatch or firstMatch then
            local prevStatus = entry.status
            if data.online ~= nil then
                entry.status = data.online and "online" or "offline"
            end
            if data.source then entry.source = data.source end
            if data.level and data.level > 0 then entry.level = data.level end
            if data.classFile then entry.classFile = data.classFile end
            if data.area and data.area ~= "" then entry.area = data.area end
            if data.guild ~= nil then entry.guild = data.guild end
            if data.online then
                entry.lastSeen = now
                entry.lastChecked = now
                if prevStatus == "offline" then
                    self:NotifyWatchlistOnline(entry)
                end
            end
            changed = true
        end
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
    if not rec.folder and not rec.mainName and not rec.note then
        tbl[key] = nil
    else
        rec.updatedAt = time()
        tbl[key] = rec
    end
    ns:Emit("SOCIAL_UPDATED")
    ns:Emit("GROUP_UPDATED")
    return tbl[key]
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

function Store:GetRecentCompanionsTable()
    local root = ns.db and ns.db.recentCompanions
    if not root then return {} end
    local scope = Compat.ScopeKey()
    if type(root[scope]) ~= "table" then root[scope] = {} end
    local tbl = root[scope]
    local now = time()
    for k, rec in pairs(tbl) do
        if type(rec) ~= "table" or (rec.lastSeen and (now - rec.lastSeen) > COMPANION_TTL) then
            tbl[k] = nil
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
    local existing = tbl[parsed.lookupKey] or {}
    tbl[parsed.lookupKey] = {
        lookupKey = parsed.lookupKey,
        displayName = parsed.displayName,
        classFile = info.classFile or existing.classFile,
        level = (info.level and info.level > 0) and info.level or existing.level,
        role = info.role or existing.role,
        zone = (info.zone and info.zone ~= "") and info.zone or existing.zone,
        lastSeen = time(),
    }

    local list = self:GetRecentCompanionsList()
    if #list > MAX_RECENT_COMPANIONS then
        for i = MAX_RECENT_COMPANIONS + 1, #list do
            tbl[list[i].lookupKey] = nil
        end
    end
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
