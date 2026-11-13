local _, ns = ...

local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Passive friendly/social player detection via nameplates, target, mouseover, group and chat.
-- Zero /who throttle cost; fails closed on hostile/secret units to avoid PvP tracking and taint.
local Nearby = {}
ns.Nearby = Nearby
table.insert(ns.modules, Nearby)

local emitQueued = false
local lastAutoPrune = 0
local MAX_NEARBY_ENTRIES = 400

local function QueueEmit()
    if emitQueued then return end
    emitQueued = true
    C_Timer.After(0.5, function()
        emitQueued = false
        ns:Emit("NEARBY_UPDATED")
    end)
end

local function RecordSighting(rawName, guid, level, classFile, area, source, guild)
    if not rawName or Compat.IsMe(rawName, guid) then return end
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed then return end

    local now = time()
    if (now - lastAutoPrune) >= 60 then
        lastAutoPrune = now
        Nearby:Prune(true)
    end

    -- Upgrade any earlier first-name-only entry matching the same GUID cleanly.
    local upgraded
    if guid then
        for oldKey, oldRow in pairs(Store.nearby) do
            if oldKey ~= parsed.lookupKey and oldRow.guid == guid then
                upgraded = oldRow
                Store.nearby[oldKey] = nil
                break
            end
        end
    end
    if parsed.surname and Store.nearby[parsed.firstName:lower()] then
        local oldRow = Store.nearby[parsed.firstName:lower()]
        if not upgraded then
            upgraded = oldRow
        end
        Store.nearby[parsed.firstName:lower()] = nil
    end

    if guid and parsed and parsed.surname and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(guid, parsed.displayName, parsed.firstName)
    end

    local existing = Store.nearby[parsed.lookupKey] or upgraded
    if not existing then
        local count = 0
        for _ in pairs(Store.nearby) do count = count + 1 end
        if count >= MAX_NEARBY_ENTRIES then
            Nearby:Prune(true)
            -- Drop oldest entry if still at cap after time-based prune.
            local oldestKey, oldestSeen
            for k, r in pairs(Store.nearby) do
                if not oldestSeen or (r.lastSeen or 0) < oldestSeen then
                    oldestKey, oldestSeen = k, (r.lastSeen or 0)
                end
            end
            if oldestKey then Store.nearby[oldestKey] = nil end
        end
    end

    -- Fallback class resolution if classFile is missing (e.g. from chat sighting)
    if not classFile or classFile == "" then
        if existing and existing.classFile then
            classFile = existing.classFile
        elseif guid and Compat.ClassFileFromGuid then
            classFile = Compat.ClassFileFromGuid(guid)
        end
        if (not classFile or classFile == "") and Store.social then
            for _, sRow in pairs(Store.social) do
                if (guid and sRow.guid == guid) or (sRow.lookupKey == parsed.lookupKey) then
                    if sRow.classFile then
                        classFile = sRow.classFile
                        break
                    end
                end
            end
        end
    end

    -- Fallback guild resolution if guild is missing
    if not guild or guild == "" then
        if existing and existing.guild then
            guild = existing.guild
        elseif Store.social then
            for _, sRow in pairs(Store.social) do
                if (guid and sRow.guid == guid) or (sRow.lookupKey == parsed.lookupKey) then
                    if sRow.guild and sRow.guild ~= "" then
                        guild = sRow.guild
                        break
                    end
                end
            end
        end
    end

    -- Fallback level resolution if level is missing
    if not level or level <= 0 then
        if existing and existing.level then
            level = existing.level
        elseif Store.social then
            for _, sRow in pairs(Store.social) do
                if (guid and sRow.guid == guid) or (sRow.lookupKey == parsed.lookupKey) then
                    if sRow.level and sRow.level > 0 then
                        level = sRow.level
                        break
                    end
                end
            end
        end
    end

    local row = existing or {
        key = parsed.lookupKey,
        displayName = parsed.displayName,
    }
    row.key = parsed.lookupKey

    row.displayName = parsed.displayName
    row.guid = guid or row.guid
    if level and level > 0 then row.level = level end
    if classFile then row.classFile = classFile end
    if area and area ~= "" then row.area = area end
    if guild and guild ~= "" then row.guild = guild end
    row.source = source or row.source
    row.lastSeen = now
    Store.nearby[parsed.lookupKey] = row

    Store:SyncWatchlistObservation(parsed.displayName, {
        online = true,
        source = source or "nearby",
        level = row.level,
        classFile = row.classFile,
        area = row.area,
        guild = row.guild,
    })

    QueueEmit()
end

local function InspectUnit(unit, source)
    if not unit then return end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then return end
    local isPlayer = Safe.Value(Safe.Call(UnitIsPlayer, unit))
    if isPlayer ~= true then return end

    -- Fail closed against hostile PvP units and secret values (12.x / 16001).
    if source ~= "group" then
        local isEnemy = Safe.Value(Safe.Call(UnitIsEnemy, "player", unit))
        local isFriend = Safe.Value(Safe.Call(UnitIsFriend, "player", unit))
        if isEnemy == true or isFriend ~= true then
            return
        end
    end

    local guid = Safe.String(Safe.Call(UnitGUID, unit))
    local existingName = nil
    if guid then
        for _, row in pairs(Store.nearby) do
            if row.guid == guid and row.displayName and row.displayName:find("%s") then
                existingName = row.displayName
                break
            end
        end
    end
    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, guid, existingName)
    local name = (resolved and resolved.fullName) or Safe.String(Safe.Call(UnitName, unit))
    if not name then return end

    local _, classFile = Safe.Call(UnitClass, unit)
    classFile = Safe.String(classFile)
    local level = Safe.Number(Safe.Call(UnitLevel, unit))
    local area = Compat.CurrentZoneName()
    local guild = Safe.String(Safe.Call(GetGuildInfo, unit))

    RecordSighting(name, guid, level, classFile, area, source, guild)
end

local function ScanGroup()
    if not Compat.IsInGroup() then return end
    if Compat.IsInRaid() then
        for i = 1, 40 do
            InspectUnit("raid" .. i, "group")
        end
    else
        for i = 1, 4 do
            InspectUnit("party" .. i, "group")
        end
    end
end

local function OnChat(_, _, text, sender, ...)
    local cleanSender = Safe.String(sender)
    local guid = select(10, ...)
    local cleanGuid = Safe.String(guid)
    if not cleanSender then return end
    if cleanGuid and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(cleanGuid, cleanSender)
    end
    RecordSighting(cleanSender, cleanGuid, nil, nil, nil, "chat", nil)
end

function Nearby:Prune(silent)
    local retentionSec = ((ns.db and ns.db.settings and ns.db.settings.nearbyRetentionMin) or 15) * 60
    local cutoff = time() - retentionSec
    local removed = false
    for key, row in pairs(Store.nearby) do
        if (row.lastSeen or 0) < cutoff then
            Store.nearby[key] = nil
            removed = true
        end
    end
    if removed and not silent then ns:Emit("NEARBY_UPDATED") end
end

function Nearby:Clear()
    wipe(Store.nearby)
    ns:Emit("NEARBY_UPDATED")
end

function Nearby:GetList()
    self:Prune(true)
    local out = {}
    for _, row in pairs(Store.nearby) do
        table.insert(out, row)
    end
    table.sort(out, function(a, b)
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return out
end

function Nearby:Init()
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        InspectUnit(unit, "nearby")
    end)
    ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function()
        InspectUnit("mouseover", "nearby")
    end)
    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
        InspectUnit("target", "nearby")
    end)
    ns.RegisterEvent(self, "PLAYER_FOCUS_CHANGED", function()
        InspectUnit("focus", "nearby")
    end)
    for _, grpEv in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
        ns.RegisterEvent(self, grpEv, function()
            ScanGroup()
        end)
    end

    for _, chatEvent in ipairs({
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_EMOTE",
        "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
    }) do
        ns.RegisterEvent(self, chatEvent, OnChat)
    end
end
