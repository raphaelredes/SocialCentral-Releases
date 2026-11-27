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
local lastRaidGroupScan = 0
local groupScanQueued = false
local nearbyCount = 0
local nearbyCountSynced = false
local nearbyCooldownCount = 0
local MAX_NEARBY_ENTRIES = 120
local NEARBY_PROBE_UNITS = { "target", "targettarget", "focus", "mouseover", "softfriend", "softinteract", "softtarget" }
local nearbyByGuid = {}
local nearbyInspectCooldown = {}
local cachedAreaZone, cachedAreaSubZone, cachedAreaFull

local function IsMainWindowOpen()
    local f = _G.SocialCentralFrame
    if f ~= nil and f.IsShown ~= nil and f:IsShown() == true then return true end
    local fr = _G.SocialUIFrame or _G.FriendsFrame
    if fr ~= nil and fr.IsShown ~= nil and fr:IsShown() == true then return true end
    return false
end

local function ResolveCachedAreaLabel()
    local area = Compat.CurrentZoneName() or ""
    local subZone = Safe.String(Safe.Call(GetSubZoneText)) or ""
    if area ~= cachedAreaZone or subZone ~= cachedAreaSubZone or not cachedAreaFull then
        cachedAreaZone = area
        cachedAreaSubZone = subZone
        if subZone ~= "" and area ~= "" and subZone ~= area then
            cachedAreaFull = area .. " — " .. subZone
        elseif subZone ~= "" then
            cachedAreaFull = subZone
        else
            cachedAreaFull = area
        end
    end
    return cachedAreaFull
end

local function SyncNearbyCount()
    local c = 0
    for _ in pairs(Store.nearby) do
        c = c + 1
    end
    nearbyCount = c
    nearbyCountSynced = true
    return c
end

local function RecordCooldown(key, expiresAt)
    if not key then return end
    if nearbyInspectCooldown[key] == nil then
        if nearbyCooldownCount >= 500 then
            wipe(nearbyInspectCooldown)
            nearbyCooldownCount = 0
        end
        nearbyCooldownCount = nearbyCooldownCount + 1
    end
    nearbyInspectCooldown[key] = expiresAt
end

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
    local lKey, fName, dName, sName
    if Compat.ParseCharacterFields then
        lKey, fName, dName, sName = Compat.ParseCharacterFields(rawName)
    else
        local p = Compat.ParseCharacterName(rawName)
        if p then
            lKey, fName, dName, sName = p.lookupKey, p.firstName, p.displayName, p.surname
        end
    end
    if not lKey then return end

    local now = time()
    if (now - lastAutoPrune) >= 60 then
        lastAutoPrune = now
        Nearby:Prune(true)
    end

    -- Upgrade any earlier first-name-only entry matching the same GUID in O(1),
    -- without downgrading an already resolved full name back to a bare first name.
    local upgraded
    if guid then
        local prevRow = nearbyByGuid[guid]
        if prevRow and prevRow.key and prevRow.key ~= lKey and Store.nearby[prevRow.key] == prevRow then
            local prevHasSurname = type(prevRow.displayName) == "string" and prevRow.displayName:find("%s") ~= nil
            local prevFirst = prevRow.displayName and prevRow.displayName:match("^([^%s%-]+)")
            if (not sName) and prevHasSurname and prevFirst and fName and Compat.LowerUtf8(prevFirst) == Compat.LowerUtf8(fName) then
                local pLk, pFn, pDn, pSn = Compat.ParseCharacterFields(prevRow.displayName)
                if pLk then
                    lKey, fName, dName, sName = pLk, pFn, pDn, pSn
                end
            else
                upgraded = prevRow
                Store.nearby[prevRow.key] = nil
                if nearbyCountSynced then
                    nearbyCount = math.max(0, nearbyCount - 1)
                end
            end
        end
    end
    local firstLowerKey = sName and fName and Compat.LowerUtf8(fName) or nil
    if firstLowerKey and Store.nearby[firstLowerKey] then
        local oldRow = Store.nearby[firstLowerKey]
        if not (guid and oldRow.guid and oldRow.guid ~= guid) then
            if not upgraded then
                upgraded = oldRow
            end
            Store.nearby[firstLowerKey] = nil
            if nearbyCountSynced then
                nearbyCount = math.max(0, nearbyCount - 1)
            end
        end
    end

    if guid and sName and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(guid, dName, fName)
    end

    local existing = Store.nearby[lKey] or upgraded
    if not existing then
        if not nearbyCountSynced then
            SyncNearbyCount()
        end
        if nearbyCount >= MAX_NEARBY_ENTRIES then
            local retentionSec = ((ns.db and ns.db.settings and ns.db.settings.nearbyRetentionMin) or 15) * 60
            local cutoff = now - retentionSec
            local oldestKey, oldestSeen
            local prunedAny = false
            for k, r in pairs(Store.nearby) do
                local seen = r.lastSeen or 0
                if seen < cutoff then
                    if r.guid and nearbyByGuid[r.guid] == r then
                        nearbyByGuid[r.guid] = nil
                    end
                    Store.nearby[k] = nil
                    nearbyCount = math.max(0, nearbyCount - 1)
                    prunedAny = true
                elseif (not oldestSeen) or seen < oldestSeen then
                    oldestKey, oldestSeen = k, seen
                end
            end
            -- Evict an 8-entry cushion around oldestSeen in one pass so burst crowds stay O(1).
            if nearbyCount >= MAX_NEARBY_ENTRIES and oldestKey then
                local cushionCutoff = oldestSeen + 15
                local evicted = 0
                for k, r in pairs(Store.nearby) do
                    if k == oldestKey or ((r.lastSeen or 0) <= cushionCutoff and evicted < 8) then
                        if r.guid and nearbyByGuid[r.guid] == r then
                            nearbyByGuid[r.guid] = nil
                        end
                        Store.nearby[k] = nil
                        nearbyCount = math.max(0, nearbyCount - 1)
                        evicted = evicted + 1
                        if nearbyCount <= (MAX_NEARBY_ENTRIES - 8) then
                            break
                        end
                    end
                end
            end
            if prunedAny then
                lastAutoPrune = now
            end
        end
    end

    local function MatchesSocialRow(sRow)
        if guid and sRow.guid then
            return sRow.guid == guid
        end
        return sRow.lookupKey == lKey
    end

    -- Fallback class, guild, and level resolution from existing row or a single Store.social pass
    if (not classFile or classFile == "") then
        if existing and existing.classFile then
            classFile = existing.classFile
        elseif guid and Compat.ClassFileFromGuid then
            classFile = Compat.ClassFileFromGuid(guid)
        end
    end
    if (not guild or guild == "") and existing and existing.guild then
        guild = existing.guild
    end
    if (not level or level <= 0) and existing and existing.level then
        level = existing.level
    end

    if Store.social and ((not classFile or classFile == "") or (not guild or guild == "") or (not level or level <= 0)) then
        local function ApplySocialRow(sRow)
            if not sRow or not MatchesSocialRow(sRow) then
                return false
            end
            if (not classFile or classFile == "") and sRow.classFile then
                classFile = sRow.classFile
            end
            if (not guild or guild == "") and sRow.guild and sRow.guild ~= "" then
                guild = sRow.guild
            end
            if (not level or level <= 0) and sRow.level and sRow.level > 0 then
                level = sRow.level
            end
            return classFile and classFile ~= "" and guild and guild ~= "" and level and level > 0
        end

        if Store.socialByGuid or Store.socialByLookup then
            local matchedGuid = guid and Store.socialByGuid and Store.socialByGuid[guid]
            if not ApplySocialRow(matchedGuid) then
                local matchedKey = Store.socialByLookup and Store.socialByLookup[lKey]
                if matchedKey ~= matchedGuid then
                    ApplySocialRow(matchedKey)
                end
            end
        else
            for _, sRow in pairs(Store.social) do
                if ApplySocialRow(sRow) then
                    break
                end
            end
        end
    end

    local row = existing or {
        key = lKey,
        displayName = dName,
    }
    row.key = lKey

    row.displayName = dName
    row.guid = guid or row.guid
    if level and level > 0 then row.level = level end
    if classFile then row.classFile = classFile end
    if area and area ~= "" then row.area = area end
    if guild and guild ~= "" then row.guild = guild end
    row.source = source or row.source
    row.lastSeen = now
    if nearbyCountSynced and Store.nearby[lKey] == nil then
        nearbyCount = nearbyCount + 1
    end
    Store.nearby[lKey] = row
    if row.guid then
        nearbyByGuid[row.guid] = row
    end

    if row.level and row.level > 0 and Store.RecordLiveUnitObservation then
        Store:RecordLiveUnitObservation(dName, {
            guid = row.guid,
            level = row.level,
            classFile = row.classFile,
            area = row.area,
            guild = row.guild,
            source = source or "nearby",
        })
    end

    Store:SyncWatchlistObservation(dName, {
        online = true,
        guid = row.guid,
        source = source or "nearby",
        level = row.level,
        classFile = row.classFile,
        area = row.area,
        guild = row.guild,
    })

    QueueEmit()
end

local function InspectUnit(unit, source, fromTicker, bypassCooldown)
    if ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false then return end
    if not unit then return end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then return end
    local isPlayer = Safe.Value(Safe.Call(UnitIsPlayer, unit))
    if isPlayer ~= true then return end

    if UnitIsConnected then
        local isConn = Safe.Value(Safe.Call(UnitIsConnected, unit))
        if isConn == false or (source == "group" and isConn ~= true) then
            if source == "group" then
                local offGuid = Safe.String(Safe.Call(UnitGUID, unit))
                local offName = Safe.String(Safe.Call(UnitName, unit))
                local parsedOff = offName and Compat.ParseCharacterName and Compat.ParseCharacterName(offName) or nil
                if Store and Store.nearby then
                    local oldRow = (offGuid and nearbyByGuid[offGuid])
                        or (parsedOff and parsedOff.lookupKey and Store.nearby[parsedOff.lookupKey])
                    if oldRow then
                        if oldRow.guid and nearbyByGuid[oldRow.guid] == oldRow then
                            nearbyByGuid[oldRow.guid] = nil
                        end
                        if oldRow.key and Store.nearby[oldRow.key] == oldRow then
                            Store.nearby[oldRow.key] = nil
                            if nearbyCountSynced then
                                nearbyCount = math.max(0, nearbyCount - 1)
                            end
                            QueueEmit()
                        end
                    end
                end
                if offName and Store and Store.SyncWatchlistObservation and ns.Watchlist and ns.Watchlist.GetEntry then
                    local resolvedOff = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, offGuid, nil, true)
                    local wlName = (resolvedOff and resolvedOff.fullName) or (parsedOff and parsedOff.displayName) or offName
                    local wlParsed = Compat.ParseCharacterName and Compat.ParseCharacterName(wlName)
                    local wlEntry = wlParsed and wlParsed.lookupKey and ns.Watchlist:GetEntry(wlParsed.lookupKey)
                    if wlEntry then
                        local hasOtherAltOnline = (wlEntry.watchAllAlts == true and wlEntry.activeAltLookup and wlEntry.activeAltLookup ~= wlParsed.lookupKey and wlEntry.status == "online")
                        if not hasOtherAltOnline then
                            Store:SyncWatchlistObservation(wlEntry.displayName or wlName, {
                                online = false,
                                guid = offGuid,
                                source = "group",
                            })
                        end
                    end
                end
            end
            return
        end
    end

    -- Fail closed against hostile PvP units and secret values (12.x / 16001).
    if source ~= "group" then
        local isEnemy = Safe.Value(Safe.Call(UnitIsEnemy, "player", unit))
        local isFriend = Safe.Value(Safe.Call(UnitIsFriend, "player", unit))
        if isEnemy == true or isFriend ~= true then
            return
        end
    end

    local guid = Safe.String(Safe.Call(UnitGUID, unit))
    local nowClock = (GetTime and GetTime()) or time()
    local isDirectFocus = (unit == "target" or unit == "focus")
    local uiOpen = IsMainWindowOpen()
    local minCooldown = (not uiOpen and not isDirectFocus) and 12.0 or (fromTicker and 3.5 or (isDirectFocus and 0.75 or 2.0))
    if guid and (not bypassCooldown) and nearbyInspectCooldown[guid] and nowClock < nearbyInspectCooldown[guid] then
        -- Allow first-time explicit target/focus selection immediately while throttling repeats.
        if not (isDirectFocus and not nearbyByGuid[guid]) then
            return
        end
    end
    if guid then
        RecordCooldown(guid, nowClock + minCooldown)
    end

    local existingName = nil
    if guid then
        local cachedRow = nearbyByGuid[guid]
        if cachedRow and cachedRow.displayName and cachedRow.displayName:find("%s") then
            existingName = cachedRow.displayName
        elseif not cachedRow then
            for _, row in pairs(Store.nearby) do
                if row.guid == guid then
                    nearbyByGuid[guid] = row
                    if row.displayName and row.displayName:find("%s") then
                        existingName = row.displayName
                    end
                    break
                end
            end
        end
    end
    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(unit, guid, existingName, fromTicker and existingName ~= nil)
    local name = (resolved and resolved.fullName) or Safe.String(Safe.Call(UnitName, unit))
    if not name then return end

    local _, classFile = Safe.Call(UnitClass, unit)
    classFile = Safe.String(classFile)
    local level = Safe.Number(Safe.Call(UnitLevel, unit))
    local area = ResolveCachedAreaLabel()
    local isPhysicalGroupNear = true
    if source == "group" then
        local isVis = UnitIsVisible and Safe.Value(Safe.Call(UnitIsVisible, unit)) == true
        if not isVis then
            local myMap = C_Map and C_Map.GetBestMapForUnit and Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player"))
            local uMap = C_Map and C_Map.GetBestMapForUnit and Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, unit))
            if not myMap or not uMap or uMap ~= myMap then
                isPhysicalGroupNear = false
                if uMap and C_Map and C_Map.GetMapInfo then
                    local info = Safe.Call(C_Map.GetMapInfo, uMap)
                    area = (type(info) == "table" and Safe.String(info.name)) or nil
                else
                    area = nil
                end
            end
        end
    end

    local guild = Safe.String(Safe.Call(GetGuildInfo, unit))
    if (not guild or guild == "") and Compat.ReadUnitTooltipGuild and (uiOpen or isDirectFocus) then
        local cacheOnly = not (unit == "target" or unit == "focus" or unit == "mouseover")
        guild = Compat.ReadUnitTooltipGuild(unit, guid, cacheOnly)
    end

    if source == "group" and not isPhysicalGroupNear then
        local parsed = Compat.ParseCharacterName(name)
        if parsed then
            if level and level > 0 and Store and Store.RecordLiveUnitObservation then
                Store:RecordLiveUnitObservation(parsed.displayName, {
                    guid = guid,
                    level = level,
                    classFile = classFile,
                    area = area,
                    guild = guild,
                    source = "group",
                })
            end
            if Store and Store.SyncWatchlistObservation then
                Store:SyncWatchlistObservation(parsed.displayName, {
                    online = true,
                    guid = guid,
                    source = "group",
                    level = level,
                    classFile = classFile,
                    area = area,
                    guild = guild,
                })
            end
        end
        return
    end

    RecordSighting(name, guid, level, classFile, area, source, guild)
end

local function ScanGroup(fromTicker)
    if ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false then return end
    if not Compat.IsInGroup() then return end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    if fromTicker and inCombat then return end
    local uiOpen = IsMainWindowOpen()
    if Compat.IsInRaid() then
        local nowClock = (GetTime and GetTime()) or time()
        if inCombat then return end
        if not uiOpen then
            if fromTicker and (nowClock - lastRaidGroupScan) < 30.0 then
                return
            end
        elseif fromTicker and (nowClock - lastRaidGroupScan) < 12.0 then
            return
        end
        lastRaidGroupScan = nowClock
        local includeTargets = uiOpen and not fromTicker
        for i = 1, 40 do
            local rUnit = "raid" .. i
            InspectUnit(rUnit, "group", fromTicker)
            if includeTargets and (not UnitIsConnected or Safe.Value(Safe.Call(UnitIsConnected, rUnit)) == true) then
                InspectUnit(rUnit .. "target", "nearby", fromTicker)
            end
        end
    else
        local includeTargets = not fromTicker
        for i = 1, 4 do
            local pUnit = "party" .. i
            InspectUnit(pUnit, "group", fromTicker)
            if includeTargets and (not UnitIsConnected or Safe.Value(Safe.Call(UnitIsConnected, pUnit)) == true) then
                InspectUnit(pUnit .. "target", "nearby", fromTicker)
            end
        end
    end
end

local LOCAL_PROXIMITY_CHAT_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
}

local plateScanCursor = 0

local function ScanActiveEnvironment(fromTicker)
    if ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false then return end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    local uiOpen = IsMainWindowOpen()
    local inInst, instType = Safe.Call(IsInInstance)
    local heavyInstClosed = (not uiOpen) and (Compat.IsInRaid() or (inInst == true and (instType == "pvp" or instType == "arena")))
    local skipNameplates = inCombat or heavyInstClosed
    if not skipNameplates then
        local maxPlatesPerTick = (fromTicker and not uiOpen) and 12 or 40
        local hasPlatesApi = false
        if C_NamePlate and C_NamePlate.GetNamePlates then
            local ok, plates = pcall(C_NamePlate.GetNamePlates)
            if ok and type(plates) == "table" then
                hasPlatesApi = true
                local total = #plates
                if total > 0 then
                    local toScan = math.min(total, maxPlatesPerTick)
                    local startIdx = (total > toScan) and ((plateScanCursor % total) + 1) or 1
                    for step = 0, toScan - 1 do
                        local idx = ((startIdx + step - 1) % total) + 1
                        local plate = plates[idx]
                        local canReadPlate = false
                        if plate then
                            if plate.IsForbidden then
                                local okF, forb = pcall(plate.IsForbidden, plate)
                                canReadPlate = okF and (not forb)
                            else
                                canReadPlate = true
                            end
                        end
                        local token = canReadPlate and (Safe.String(plate.namePlateUnitToken) or (plate.UnitFrame and Safe.String(plate.UnitFrame.unit))) or nil
                        if token and token ~= "" then
                            InspectUnit(token, "nearby", fromTicker)
                            if uiOpen then
                                InspectUnit(token .. "target", "nearby", fromTicker)
                            end
                        end
                    end
                    plateScanCursor = (total > toScan) and ((startIdx + toScan - 1) % total) or 0
                end
            end
        end
        if not hasPlatesApi then
            local limit = (fromTicker and not uiOpen) and 12 or 20
            for i = 1, limit do
                local token = "nameplate" .. i
                if UnitExists and UnitExists(token) then
                    InspectUnit(token, "nearby", fromTicker)
                    if uiOpen then
                        InspectUnit(token .. "target", "nearby", fromTicker)
                    end
                end
            end
        end
    end
    for _, u in ipairs(NEARBY_PROBE_UNITS) do
        if UnitExists and UnitExists(u) then
            InspectUnit(u, "nearby", fromTicker)
        end
    end
    ScanGroup(fromTicker)
end

local RACE_TO_FACTION = {
    Human = "Alliance",
    Dwarf = "Alliance",
    NightElf = "Alliance",
    Gnome = "Alliance",
    Draenei = "Alliance",
    Worgen = "Alliance",
    HighElf = "Alliance",
    Orc = "Horde",
    Scourge = "Horde",
    Tauren = "Horde",
    Troll = "Horde",
    BloodElf = "Horde",
    Goblin = "Horde",
}

local function IsOpposingFactionChatSpeaker(cleanGuid, cleanSender)
    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    if not myFac then return true end
    local detectedFac = nil
    if cleanGuid and GetPlayerInfoByGUID then
        local ok, _, _, locRace, engRace = pcall(GetPlayerInfoByGUID, cleanGuid)
        if ok then
            local cleanEng = Safe.String(engRace)
            local cleanLoc = Safe.String(locRace)
            if Compat.FactionFromRace then
                detectedFac = Compat.FactionFromRace(cleanEng or cleanLoc)
            end
            if not detectedFac and cleanEng then
                detectedFac = RACE_TO_FACTION[cleanEng]
            end
        end
    end
    local parsedSender = cleanSender and Compat.ParseCharacterName and Compat.ParseCharacterName(cleanSender) or nil
    if not detectedFac and Store then
        local sRow = cleanGuid and Store.socialByGuid and Store.socialByGuid[cleanGuid]
        if not sRow and parsedSender and parsedSender.lookupKey and Store.socialByLookup then
            local candidate = Store.socialByLookup[parsedSender.lookupKey]
            if candidate and not (cleanGuid and candidate.guid and candidate.guid ~= cleanGuid) then
                sRow = candidate
            end
        end
        if sRow then
            if sRow.faction == "Alliance" or sRow.faction == "Horde" then
                detectedFac = sRow.faction
            elseif sRow.sameFaction == true or (sRow.sources and (sRow.sources.guild == true or sRow.sources.friend == true)) then
                detectedFac = myFac
            elseif sRow.sameFaction == false then
                return true
            end
        end
    end
    if not detectedFac and Store and Store.nearby then
        if cleanGuid then
            local nRow = nearbyByGuid[cleanGuid]
            if not nRow and parsedSender and parsedSender.lookupKey then
                local candidate = Store.nearby[parsedSender.lookupKey]
                if candidate and candidate.guid == cleanGuid then
                    nRow = candidate
                end
            end
            if nRow then
                detectedFac = myFac
            end
        elseif parsedSender and parsedSender.lookupKey and Store.nearby[parsedSender.lookupKey] then
            detectedFac = myFac
        end
    end
    if not detectedFac and Compat.IsGuildMember and Compat.IsGuildMember(parsedSender and parsedSender.firstName, cleanGuid, cleanSender) then
        detectedFac = myFac
    end
    if not detectedFac and Compat.IsInMyGroup and Compat.IsInMyGroup(cleanSender, cleanGuid) then
        detectedFac = myFac
    end
    if not detectedFac and cleanGuid and C_FriendList and C_FriendList.IsFriend then
        local okF, isF = pcall(C_FriendList.IsFriend, cleanGuid)
        if okF and Safe.Value(isF) == true then
            detectedFac = myFac
        end
    end
    if not detectedFac then
        return true
    end
    return (detectedFac ~= myFac)
end

local function OnChat(_, eventName, text, sender, ...)
    if ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false then return end
    local cleanSender = Safe.String(sender)
    if not cleanSender then return end
    local guid = select(10, ...)
    local cleanGuid = Safe.String(guid)
    if LOCAL_PROXIMITY_CHAT_EVENTS[eventName] and IsOpposingFactionChatSpeaker(cleanGuid, cleanSender) then
        return
    end
    local throttleKey = cleanGuid or ("chat:" .. Compat.LowerUtf8(cleanSender))
    local nowClock = (GetTime and GetTime()) or time()
    if nearbyInspectCooldown[throttleKey] and nowClock < nearbyInspectCooldown[throttleKey] then
        return
    end
    RecordCooldown(throttleKey, nowClock + 3.5)

    if cleanGuid and Compat.CacheForeverFullName then
        Compat.CacheForeverFullName(cleanGuid, cleanSender)
    end
    local bestName = cleanSender
    if not cleanSender:find("%s") and cleanGuid then
        if Compat.LookupForeverFullName then
            local resolved = Compat.LookupForeverFullName(cleanGuid, cleanSender, false)
            if resolved and resolved.fullName then
                bestName = resolved.fullName
            end
        end
        if not bestName:find("%s") and nearbyByGuid[cleanGuid] then
            local cachedRow = nearbyByGuid[cleanGuid]
            if cachedRow and type(cachedRow.displayName) == "string" and cachedRow.displayName:find("%s") then
                bestName = cachedRow.displayName
            end
        end
    end
    local guild = cleanGuid and Compat.ReadUnitTooltipGuild and Compat.ReadUnitTooltipGuild(nil, cleanGuid, true) or nil

    -- Only physically nearby channels (Say/Yell/Emote) assert the speaker is standing in the player's current zone.
    if LOCAL_PROXIMITY_CHAT_EVENTS[eventName] then
        local z = Compat.CurrentZoneName()
        local sz = Safe.String(Safe.Call(GetSubZoneText))
        if sz and sz ~= "" and z and z ~= "" and sz ~= z then
            z = z .. " — " .. sz
        end
        RecordSighting(bestName, cleanGuid, nil, nil, z, "chat", guild)
        return
    end

    local parsed = Compat.ParseCharacterName(bestName)
    if not parsed or Compat.IsMe(parsed.displayName, cleanGuid) then
        return
    end

    if (not guild or guild == "") and Store then
        local sRow = (cleanGuid and Store.socialByGuid and Store.socialByGuid[cleanGuid])
            or (Store.socialByLookup and Store.socialByLookup[parsed.lookupKey])
        if sRow and sRow.guild and sRow.guild ~= "" then
            guild = sRow.guild
        end
    end

    -- Refresh already-recorded Nearby rows without overwriting their real map zone, and notify Watchlist cleanly without a fake zone.
    local existing = nil
    if Store.nearby then
        existing = (cleanGuid and nearbyByGuid[cleanGuid]) or Store.nearby[parsed.lookupKey]
        if not existing and parsed.surname and parsed.firstName then
            local firstLowerKey = Compat.LowerUtf8(parsed.firstName)
            local oldRow = Store.nearby[firstLowerKey]
            if oldRow and not (cleanGuid and oldRow.guid and oldRow.guid ~= cleanGuid) then
                existing = oldRow
            end
        end
    end
    local notifyName = parsed.displayName
    if existing then
        local existingHasSurname = type(existing.displayName) == "string" and existing.displayName:find("%s") ~= nil
        local shouldKeepExistingKey = existingHasSurname and not parsed.surname
        if not shouldKeepExistingKey then
            if existing.key and existing.key ~= parsed.lookupKey then
                if Store.nearby[existing.key] == existing then
                    Store.nearby[existing.key] = nil
                    if nearbyCountSynced then
                        nearbyCount = math.max(0, nearbyCount - 1)
                    end
                end
                local dupRow = Store.nearby[parsed.lookupKey]
                if dupRow and dupRow ~= existing then
                    if dupRow.guid and nearbyByGuid[dupRow.guid] == dupRow then
                        nearbyByGuid[dupRow.guid] = nil
                    end
                    if not existing.classFile then existing.classFile = dupRow.classFile end
                    if not existing.level then existing.level = dupRow.level end
                    if not existing.area then existing.area = dupRow.area end
                    if not existing.guild then existing.guild = dupRow.guild end
                    if not existing.guid then existing.guid = dupRow.guid end
                elseif nearbyCountSynced and Store.nearby[parsed.lookupKey] == nil then
                    nearbyCount = nearbyCount + 1
                end
                existing.key = parsed.lookupKey
                Store.nearby[parsed.lookupKey] = existing
            elseif not existing.key then
                existing.key = parsed.lookupKey
                if nearbyCountSynced and Store.nearby[parsed.lookupKey] == nil then
                    nearbyCount = nearbyCount + 1
                end
                Store.nearby[parsed.lookupKey] = existing
            end
            existing.displayName = parsed.displayName
        end
        if cleanGuid and cleanGuid ~= "" then
            existing.guid = cleanGuid
            nearbyByGuid[cleanGuid] = existing
        elseif existing.guid and existing.guid ~= "" then
            nearbyByGuid[existing.guid] = existing
        end
        if guild and guild ~= "" then existing.guild = guild end
        existing.lastSeen = time()
        notifyName = existing.displayName or notifyName
        QueueEmit()
    end

    Store:SyncWatchlistObservation(notifyName, {
        online = true,
        guid = cleanGuid,
        source = "chat",
        guild = guild,
    })
end

function Nearby:Prune(silent)
    local retentionSec = ((ns.db and ns.db.settings and ns.db.settings.nearbyRetentionMin) or 15) * 60
    local cutoff = time() - retentionSec
    local removed = false
    local remaining = 0
    for key, row in pairs(Store.nearby) do
        if (row.lastSeen or 0) < cutoff then
            if row.guid and nearbyByGuid[row.guid] == row then
                nearbyByGuid[row.guid] = nil
            end
            Store.nearby[key] = nil
            removed = true
        else
            remaining = remaining + 1
        end
    end
    nearbyCount = remaining
    nearbyCountSynced = true

    local nowClock = (GetTime and GetTime()) or time()
    if nearbyCooldownCount >= 400 or not silent then
        local cdCount = 0
        for cdKey, expiresAt in pairs(nearbyInspectCooldown) do
            if nowClock >= expiresAt then
                nearbyInspectCooldown[cdKey] = nil
            else
                cdCount = cdCount + 1
            end
        end
        if cdCount > 600 then
            wipe(nearbyInspectCooldown)
            cdCount = 0
        end
        nearbyCooldownCount = cdCount
    end
    if removed and not silent then ns:Emit("NEARBY_UPDATED") end
end

function Nearby:Clear()
    wipe(Store.nearby)
    wipe(nearbyByGuid)
    wipe(nearbyInspectCooldown)
    nearbyCount = 0
    nearbyCountSynced = true
    nearbyCooldownCount = 0
    ns:Emit("NEARBY_UPDATED")
end

function Nearby:GetCount()
    self:Prune(true)
    return nearbyCount
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

local function ScheduleGroupScan()
    if groupScanQueued then return end
    if C_Timer and C_Timer.After then
        groupScanQueued = true
        C_Timer.After(0.60, function()
            groupScanQueued = false
            ScanGroup(true)
        end)
    else
        ScanGroup(true)
    end
end

local NEARBY_CHAT_EVENTS = {
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
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}
local NEARBY_ENV_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED" }
local NEARBY_GRP_EVENTS = { "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_CONNECTION" }
local NEARBY_UNIT_EVENTS = {
    "NAME_PLATE_UNIT_ADDED",
    "FORBIDDEN_NAME_PLATE_UNIT_ADDED",
    "PLAYER_SOFT_FRIEND_CHANGED",
    "PLAYER_SOFT_INTERACT_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UNIT_TARGET",
    "UNIT_LEVEL",
}

local function StopNearbyTicker()
    if Nearby._scanTicker then
        Nearby._scanTicker:Cancel()
        Nearby._scanTicker = nil
    end
end

local function SyncNearbyTicker()
    local enabled = not (ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false)
    if not enabled then
        StopNearbyTicker()
        return
    end
    local needsTicker = IsMainWindowOpen() or (Compat.IsInGroup and Compat.IsInGroup() == true)
    if not needsTicker then
        StopNearbyTicker()
        return
    end
    if Nearby._scanTicker or not (C_Timer and C_Timer.NewTicker) then
        return
    end
    Nearby._scanTicker = C_Timer.NewTicker(8.0, function()
        if ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false then
            StopNearbyTicker()
            return
        end
        if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
            return
        end
        local uiOpen = IsMainWindowOpen()
        if not uiOpen then
            if not (Compat.IsInGroup and Compat.IsInGroup()) then
                StopNearbyTicker()
                return
            end
            ScanGroup(true)
            return
        end
        ScanActiveEnvironment(true)
    end)
end

function Nearby:SyncActivePolling()
    SyncNearbyTicker()
end

function Nearby:SyncEventRegistration()
    local enabled = not (ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false)
    if not enabled then
        if self._eventsActive then
            self._eventsActive = false
            for _, ev in ipairs(NEARBY_UNIT_EVENTS) do ns.UnregisterEvent(self, ev) end
            for _, ev in ipairs(NEARBY_ENV_EVENTS) do ns.UnregisterEvent(self, ev) end
            for _, ev in ipairs(NEARBY_GRP_EVENTS) do ns.UnregisterEvent(self, ev) end
            for _, ev in ipairs(NEARBY_CHAT_EVENTS) do ns.UnregisterEvent(self, ev) end
        end
        StopNearbyTicker()
        return
    end
    if self._eventsActive then
        SyncNearbyTicker()
        return
    end
    self._eventsActive = true
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        if (InCombatLockdown and InCombatLockdown()) or (Compat.IsInRaid() and not IsMainWindowOpen()) then
            return
        end
        local cleanUnit = Safe.String(unit)
        if cleanUnit then
            InspectUnit(cleanUnit, "nearby")
        end
    end)
    ns.RegisterEvent(self, "FORBIDDEN_NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        if not IsMainWindowOpen() or (InCombatLockdown and InCombatLockdown()) or Compat.IsInRaid() then
            return
        end
        local cleanUnit = Safe.String(unit)
        if cleanUnit then
            InspectUnit(cleanUnit, "nearby")
        end
    end)
    ns.RegisterEvent(self, "PLAYER_SOFT_FRIEND_CHANGED", function()
        InspectUnit("softfriend", "nearby")
    end)
    ns.RegisterEvent(self, "PLAYER_SOFT_INTERACT_CHANGED", function()
        InspectUnit("softinteract", "nearby")
        InspectUnit("softfriend", "nearby")
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
    ns.RegisterEvent(self, "UNIT_TARGET", function(_, _, unit)
        local cleanUnit = Safe.String(unit)
        if not cleanUnit then return end
        local isCore = (cleanUnit == "player" or cleanUnit == "target" or cleanUnit == "focus")
        if not isCore and ((InCombatLockdown and InCombatLockdown()) or not IsMainWindowOpen()) then
            return
        end
        if UnitExists and UnitExists(cleanUnit .. "target") then
            InspectUnit(cleanUnit .. "target", "nearby")
        end
    end)
    ns.RegisterEvent(self, "UNIT_LEVEL", function(_, _, unit)
        local cleanUnit = Safe.String(unit)
        if not cleanUnit or cleanUnit == "player" then return end
        local isGroupUnit = cleanUnit:sub(1, 5) == "party" or cleanUnit:sub(1, 4) == "raid"
        local isCore = isGroupUnit or cleanUnit == "target" or cleanUnit == "focus" or cleanUnit == "mouseover"
        if not isCore and ((InCombatLockdown and InCombatLockdown()) or not IsMainWindowOpen()) then
            return
        end
        InspectUnit(cleanUnit, isGroupUnit and "group" or "nearby", false, true)
    end)
    for _, envEv in ipairs(NEARBY_ENV_EVENTS) do
        ns.RegisterEvent(self, envEv, function()
            SyncNearbyTicker()
            if C_Timer and C_Timer.After then
                if not Nearby._envScanPending then
                    Nearby._envScanPending = true
                    C_Timer.After(0.15, function()
                        Nearby._envScanPending = false
                        if Nearby._eventsActive then
                            ScanActiveEnvironment()
                            SyncNearbyTicker()
                        end
                    end)
                end
            else
                ScanActiveEnvironment()
            end
        end)
    end
    for _, grpEv in ipairs(NEARBY_GRP_EVENTS) do
        ns.RegisterEvent(self, grpEv, function()
            ScheduleGroupScan()
            SyncNearbyTicker()
        end)
    end
    for _, chatEvent in ipairs(NEARBY_CHAT_EVENTS) do
        ns.RegisterEvent(self, chatEvent, OnChat)
    end
    SyncNearbyTicker()
end

function Nearby:Init()
    self:SyncEventRegistration()
    ns:On("SETTINGS_UPDATED", function()
        Nearby:SyncEventRegistration()
        if ns.db and ns.db.settings and ns.db.settings.moduleNearbyEnabled == false and Nearby.Clear then
            Nearby:Clear()
        end
    end)
end
