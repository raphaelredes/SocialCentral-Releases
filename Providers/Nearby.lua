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

local function RecordSighting(rawName, guid, level, classFile, area, source)
    if not rawName or Compat.IsMe(rawName, guid) then return end
    local parsed = Compat.ParseCharacterName(rawName)
    if not parsed then return end

    local now = time()
    if (now - lastAutoPrune) >= 60 then
        lastAutoPrune = now
        Nearby:Prune(true)
    end

    local existing = Store.nearby[parsed.lookupKey]
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

    local row = existing or {
        key = parsed.lookupKey,
        displayName = parsed.displayName,
    }

    row.displayName = parsed.displayName
    row.guid = guid or row.guid
    if level and level > 0 then row.level = level end
    if classFile then row.classFile = classFile end
    if area and area ~= "" then row.area = area end
    row.source = source or row.source
    row.lastSeen = now
    Store.nearby[parsed.lookupKey] = row

    Store:SyncWatchlistObservation(parsed.displayName, {
        online = true,
        source = source or "nearby",
        level = row.level,
        classFile = row.classFile,
        area = row.area,
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

    local name = Safe.String(Safe.Call(UnitName, unit))
    if not name then return end

    local guid = Safe.String(Safe.Call(UnitGUID, unit))
    local _, classFile = Safe.Call(UnitClass, unit)
    classFile = Safe.String(classFile)
    local level = Safe.Number(Safe.Call(UnitLevel, unit))
    local area = Compat.CurrentZoneName()

    RecordSighting(name, guid, level, classFile, area, source)
end

local function ScanGroup()
    if not (IsInGroup and IsInGroup()) then return end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            InspectUnit("raid" .. i, "group")
        end
    else
        for i = 1, 4 do
            InspectUnit("party" .. i, "group")
        end
    end
end

local function OnChat(_, _, _, sender, _, _, _, _, _, _, _, _, _, guid)
    local cleanSender = Safe.String(sender)
    local cleanGuid = Safe.String(guid)
    if not cleanSender then return end
    RecordSighting(cleanSender, cleanGuid, nil, nil, nil, "chat")
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
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", function()
        ScanGroup()
    end)

    for _, chatEvent in ipairs({
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
    }) do
        ns.RegisterEvent(self, chatEvent, OnChat)
    end
end
