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
