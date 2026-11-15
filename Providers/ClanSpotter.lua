local _, ns = ...

local Compat = ns.Compat
local Safe = ns.Safe
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local Spotter = {
    name = "Spotter",
    entries = {},        -- [key] = entry
    visibleUnits = {},   -- [unitToken] = key
    alertCooldowns = {}, -- [key] = timestamp
    dismissedUntil = {}, -- [key] = timestamp when [X] dismiss expires
    manualTracked = {},  -- [key] = true when user requested Track on Radar
    manualTrackedStance = {}, -- [key] = fallback stance for manual tracking
    lastAlert = nil,
    lastScopeToken = nil,
    plateBadges = setmetatable({}, { __mode = "k" }), -- [plateFrame] = badgeFrame
    _pruneElapsed = 0,
}

local MAX_TARGETS = 24
local RETENTION_SECONDS = 7
local MANUAL_RETENTION_SECONDS = 45
local DISMISS_COOLDOWN_SECONDS = 180
local PRUNE_INTERVAL = 0.5
local ENEMY_ALERT_COOLDOWN = 120
local FRIENDLY_ALERT_COOLDOWN = 180
local MAP_COORD_PER_YARD = 0.00035

local ITEM_RANGES = {
    { range = 8, item = 8149 },    -- Voodoo Charm
    { range = 13, item = 17626 },  -- Frostwolf Muzzle
    { range = 18, item = 6450 },   -- Silk Bandage (friendly-only check)
    { range = 23, item = 17757 },  -- Amulet of Spirits
    { range = 28, item = 13289 },  -- Egan's Blaster
    { range = 33, item = 17202 },  -- Snowball
    { range = 38, item = 18904 },  -- Zorbin's Ultra-Shrinker
    { range = 48, item = 221316 }, -- Premo's Poise-Demanding Uniform
    { range = 103, item = 5418 },  -- Weapon of Mass Destruction
}

local STANCE_PRIORITY = {
    ENEMY = 1,
    WATCHLIST = 2,
    FRIEND = 3,
    ALLY = 4,
    SAME = 5,
}

local STANCE_COLORS = {
    ENEMY     = { r = 0.96, g = 0.28, b = 0.28, hex = "|cfff54747" },
    WATCHLIST = { r = 1.00, g = 0.65, b = 0.20, hex = "|cffffa633" },
    FRIEND    = { r = 0.35, g = 0.78, b = 1.00, hex = "|cff59c7ff" },
    ALLY      = { r = 0.25, g = 0.85, b = 0.45, hex = "|cff40d973" },
    SAME      = { r = 0.98, g = 0.80, b = 0.24, hex = "|cfffacc3d" },
}

local function NormalizeKeyPart(value)
    local s = Safe.String(value)
    if not s or s == "" then return "" end
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s:lower()
end

local function SanitizeMacroTargetName(rawName, rawRealm)
    local clean = Safe.String(rawName)
    if not clean or clean == "" then return nil end
    clean = clean:gsub("[%c%|%/%\\%[%]%;]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then return nil end

    local realm = Safe.String(rawRealm)
    if realm and realm ~= "" and not Compat.IsForeverShardLabel(realm) then
        local cleanRealm = realm:gsub("[%c%|%/%\\%[%]%;%s]", "")
        if cleanRealm ~= "" and not clean:find("-", 1, true) then
            local myRealm = Compat.Realm and Compat.Realm() or ""
            if cleanRealm:lower() ~= myRealm:lower() then
                clean = clean .. "-" .. cleanRealm
            end
        end
    end

    if #clean > 48 then
        clean = clean:sub(1, 48)
    end
    return clean
end

local function GetUnitSafeGuild(unit, guidHint)
    if GetGuildInfo and unit then
        local ok, gName, gRank, _, gRealm = pcall(GetGuildInfo, unit)
        if ok then
            local cleanGuild = Safe.String(gName)
            if cleanGuild and cleanGuild ~= "" then
                local cleanRank = Safe.String(gRank)
                local cleanRealm = Safe.String(gRealm)
                if cleanRealm and Compat.IsForeverShardLabel(cleanRealm) then
                    cleanRealm = nil
                end
                return cleanGuild, cleanRank, cleanRealm
            end
        end
    end
    if Compat.ReadUnitTooltipGuild then
        local tipGuild = Compat.ReadUnitTooltipGuild(unit, guidHint)
        if tipGuild and tipGuild ~= "" then
            return tipGuild, nil, nil
        end
    end
    return nil, nil, nil
end

local function GetPlayerNormalizedGuild()
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true
    local gName = GetUnitSafeGuild("player")
    if not gName or gName == "" then
        local info = ns.Store and ns.Store.guildInfo
        if info and info.inGuild and info.name and info.name ~= "" then
            gName = info.name
        end
    end
    if (not gName or gName == "") and inGuild and ns.db and ns.db.alts and Compat.CharacterKey then
        local altRec = ns.db.alts[Compat.CharacterKey()]
        if altRec and altRec.guild and altRec.guild ~= "" then
            gName = altRec.guild
        end
    end
    if gName and gName ~= "" then
        Spotter._cachedPlayerGuild = gName
        return NormalizeKeyPart(gName), gName
    end
    if inGuild and Spotter._cachedPlayerGuild and Spotter._cachedPlayerGuild ~= "" then
        return NormalizeKeyPart(Spotter._cachedPlayerGuild), Spotter._cachedPlayerGuild
    end
    return nil, nil
end

local function LookupKnownPlayerGuildOrMembership(firstName, fullName, guid)
    local cleanGuid = Safe.String(guid)
    local firstLower = (firstName and firstName ~= "") and firstName:lower() or nil
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(fullName or firstName)
    local lookupKey = parsed and parsed.lookupKey or firstLower
    local hasSurname = parsed and parsed.surname ~= nil

    local isMyGuild = false
    local isWatched = false
    local isFriend = false
    local knownGuild, knownClass, knownLevel, watchNote

    if Compat.IsGuildMember and Compat.IsGuildMember(firstName, cleanGuid, fullName) then
        isMyGuild = true
    end

    local store = ns.Store
    if store and type(store.social) == "table" then
        for _, row in pairs(store.social) do
            if type(row) == "table" then
                local rowMatch = false
                if cleanGuid and row.guid then
                    rowMatch = (row.guid == cleanGuid)
                elseif lookupKey and row.lookupKey and row.lookupKey == lookupKey then
                    rowMatch = true
                end
                if rowMatch then
                    if row.sources and row.sources.guild == true then
                        isMyGuild = true
                    end
                    if row.sources and (row.sources.friend == true or row.sources.bnet == true) then
                        isFriend = true
                    end
                    if row.guild and row.guild ~= "" then
                        knownGuild = knownGuild or row.guild
                    end
                    knownClass = knownClass or row.classFile
                    knownLevel = knownLevel or row.level
                    break
                end
            end
        end
    end

    if not isFriend and cleanGuid and C_FriendList and C_FriendList.IsFriend then
        local okF, resF = pcall(C_FriendList.IsFriend, cleanGuid)
        if okF and Safe.Value(resF) == true then
            isFriend = true
        end
    end

    if not isMyGuild and not cleanGuid and lookupKey and Safe.Value(IsInGuild and IsInGuild()) == true then
        if ns.Clan and ns.Clan.guildChatLFG and ns.Clan.guildChatLFG[lookupKey] then
            isMyGuild = true
        end
        if not isMyGuild and store and store.GetClanScopeData then
            local bucket = store:GetClanScopeData()
            if bucket and bucket.peers and bucket.peers[lookupKey] then
                isMyGuild = true
            end
        end
    end

    if store and type(store.nearby) == "table" and lookupKey then
        local nRow = store.nearby[lookupKey] or (not hasSurname and firstLower and store.nearby[firstLower])
        if type(nRow) == "table" and not (cleanGuid and nRow.guid and nRow.guid ~= cleanGuid) then
            if nRow.guild and nRow.guild ~= "" then
                knownGuild = knownGuild or nRow.guild
            end
            knownClass = knownClass or nRow.classFile
            knownLevel = knownLevel or nRow.level
        end
    end

    if store and store.GetWatchlistTable and lookupKey then
        local wl = store:GetWatchlistTable()
        local wRow = wl and (wl[lookupKey] or (not hasSurname and firstLower and wl[firstLower]))
        if type(wRow) == "table" and not (cleanGuid and wRow.guid and wRow.guid ~= cleanGuid) then
            isWatched = true
            if wRow.note and wRow.note ~= "" then
                watchNote = wRow.note
            end
            if wRow.guild and wRow.guild ~= "" then
                knownGuild = knownGuild or wRow.guild
            end
            knownClass = knownClass or wRow.classFile
            knownLevel = knownLevel or wRow.level
        end
    end

    return isMyGuild, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote
end

local function IsPlayerInMyGroup(unit, key, guid)
    if unit then
        if Safe.Value(Safe.Call(UnitInParty, unit)) == true or Safe.Value(Safe.Call(UnitInRaid, unit)) == true then
            return true
        end
    end
    if IsInGroup and Safe.Value(Safe.Call(IsInGroup)) == true then
        local isRaid = IsInRaid and Safe.Value(Safe.Call(IsInRaid)) == true
        local count = (GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers))) or 0
        for i = 1, count do
            local token = isRaid and ("raid" .. i) or ("party" .. i)
            if Safe.Value(Safe.Call(UnitExists, token)) == true then
                local mGuid = Safe.String(Safe.Call(UnitGUID, token))
                if guid and mGuid and guid == mGuid then
                    return true
                end
                if key then
                    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(token, mGuid)
                    local fullName = (resolved and resolved.fullName) or Safe.String(Safe.Call(UnitName, token))
                    local parsed = fullName and Compat.ParseCharacterName and Compat.ParseCharacterName(fullName)
                    if parsed and parsed.lookupKey == key then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function ShouldIgnoreGroupUnit(unit, key, guid)
    if Spotter.manualTracked and key and Spotter.manualTracked[key] then
        return false
    end
    local s = ns.db and ns.db.settings
    if s and s.spotterIgnoreGroup == false then
        return false
    end
    return IsPlayerInMyGroup(unit, key, guid)
end

local function IsStanceAllowed(stance, key)
    if Spotter.manualTracked and key and Spotter.manualTracked[key] then
        return true
    end
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then return false end
    if stance == "ENEMY" then return s.spotterNotifyEnemy ~= false end
    if stance == "WATCHLIST" then return s.spotterNotifyWatchlist ~= false end
    if stance == "FRIEND" then return s.spotterNotifyFriends ~= false end
    if stance == "ALLY" then return s.spotterNotifyAlly ~= false end
    if stance == "SAME" then return s.spotterNotifySameClan == true end
    return false
end

local function ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, watchNote, key, myNormGuild, myGuildName, gName)
    if rawStance == "ENEMY" and IsStanceAllowed("ENEMY", key) then
        local reason = (dipEntry and dipEntry.reason and dipEntry.reason ~= "") and dipEntry.reason or (watchNote or "")
        return "ENEMY", reason, gName
    end
    if isWatched and IsStanceAllowed("WATCHLIST", key) then
        local reason = (watchNote and watchNote ~= "") and watchNote
            or ((dipEntry and dipEntry.reason) or L["Watchlist"])
        return "WATCHLIST", reason, gName
    end
    if isFriend and IsStanceAllowed("FRIEND", key) then
        local reason = (dipEntry and dipEntry.reason and dipEntry.reason ~= "") and dipEntry.reason or L["Friend"]
        return "FRIEND", reason, gName
    end
    if rawStance == "ALLY" and IsStanceAllowed("ALLY", key) then
        return "ALLY", (dipEntry and dipEntry.reason) or "", gName
    end
    local validSameGuild = (not gName or gName == "" or (myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) == myNormGuild))
    if isMyGuildMember and validSameGuild and IsStanceAllowed("SAME", key) then
        return "SAME", "", (myGuildName and myGuildName ~= "") and myGuildName or gName or L["Same Clan"]
    end
    if Spotter.manualTracked and key and Spotter.manualTracked[key] then
        local fallback = (Spotter.manualTrackedStance and Spotter.manualTrackedStance[key]) or "WATCHLIST"
        return fallback, (watchNote and watchNote ~= "" and watchNote) or L["Target Radar"], gName
    end
    return nil, "", gName
end

local function GetUnitOrPlayerMapXY(mapID, unit)
    if not (C_Map and C_Map.GetPlayerMapPosition and mapID) then return nil, nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit or "player")
    if not (okPos and pos) then return nil, nil end
    local x, y = Safe.Number(pos.x), Safe.Number(pos.y)
    if (not x or not y) and type(pos.GetXY) == "function" then
        local okXY, rx, ry = pcall(pos.GetXY, pos)
        if okXY then
            x, y = Safe.Number(rx), Safe.Number(ry)
        end
    end
    if x and y and (x > 0 or y > 0) then
        return x, y
    end
    return nil, nil
end

local function CaptureLocationSnapshot(unit)
    local zone = Safe.String(Safe.Call(GetRealZoneText))
        or Safe.String(Safe.Call(GetZoneText))
        or (Compat.CurrentZoneName and Compat.CurrentZoneName())
        or ""
    local subZone = Safe.String(Safe.Call(GetSubZoneText)) or ""

    local coordsText, mapID, targetX, targetY
    local directUnitPos = false
    if unit and unit ~= "player" and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        mapID = Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, unit))
            or Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player"))
        if mapID then
            local ux, uy = GetUnitOrPlayerMapXY(mapID, unit)
            if ux and uy then
                targetX, targetY = ux, uy
                directUnitPos = true
                coordsText = string.format("%.1f, %.1f", ux * 100, uy * 100)
            end
        end
    end

    local shortZone = (subZone ~= "" and subZone ~= zone) and subZone or zone
    local fullZone = (subZone ~= "" and subZone ~= zone and zone ~= "") and (zone .. " - " .. subZone) or shortZone
    local locationText = shortZone
    local fullLocationText = fullZone
    if coordsText and coordsText ~= "" then
        locationText = (shortZone ~= "") and (shortZone .. " (" .. coordsText .. ")") or ("(" .. coordsText .. ")")
        fullLocationText = (fullZone ~= "") and (fullZone .. " (" .. coordsText .. ")") or ("(" .. coordsText .. ")")
    end

    return {
        zone = zone,
        subZone = subZone,
        coordsText = coordsText,
        locationText = locationText,
        fullLocationText = fullLocationText,
        mapID = directUnitPos and mapID or nil,
        mapX = directUnitPos and targetX or nil,
        mapY = directUnitPos and targetY or nil,
        directUnitPos = directUnitPos,
    }
end

local function ApplyLocationSnapshotToEntry(entry, locSnap)
    if not (entry and locSnap) then return end
    if locSnap.zone and locSnap.zone ~= "" then entry.zone = locSnap.zone end
    if locSnap.subZone and locSnap.subZone ~= "" then entry.subZone = locSnap.subZone end

    if locSnap.directUnitPos and locSnap.mapID and locSnap.mapX and locSnap.mapY then
        entry._anchorMapID = locSnap.mapID
        entry._anchorMapX = locSnap.mapX
        entry._anchorMapY = locSnap.mapY
        entry.coordsText = locSnap.coordsText
        entry.locationText = locSnap.locationText
        entry.fullLocationText = locSnap.fullLocationText
    else
        entry._anchorMapID = nil
        entry._anchorMapX = nil
        entry._anchorMapY = nil
        entry.coordsText = nil
        if locSnap.locationText and locSnap.locationText ~= "" then
            entry.locationText = locSnap.locationText
        end
        if locSnap.fullLocationText and locSnap.fullLocationText ~= "" then
            entry.fullLocationText = locSnap.fullLocationText
        end
    end
end

local function CacheRangeCheckItems()
    local requestItem = C_Item and C_Item.RequestLoadItemDataByID
    if not requestItem then return end
    for _, spec in ipairs(ITEM_RANGES) do
        pcall(requestItem, spec.item)
    end
end

local function MeasureUnitDistance(unit, screenRadial, hasPlateOrOnScreen)
    if not unit or Safe.Value(Safe.Call(UnitExists, unit)) ~= true then
        return nil, nil
    end

    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    local isFriend = Safe.Value(Safe.Call(UnitIsFriend, "player", unit)) == true
    local canCheckFriendly = not (inCombat and isFriend)

    local d3, d2, d1, in43, in43Checked
    if canCheckFriendly and CheckInteractDistance then
        d3 = Safe.Value(Safe.Call(CheckInteractDistance, unit, 3))
        d2 = Safe.Value(Safe.Call(CheckInteractDistance, unit, 2))
        d1 = Safe.Value(Safe.Call(CheckInteractDistance, unit, 1))
    end
    if UnitInRange then
        local r, checked = Safe.Call(UnitInRange, unit)
        in43 = (r == true)
        in43Checked = (checked == true)
    end

    local minRange = 0
    local maxRange = nil
    local itemInRangeFn = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    if canCheckFriendly and itemInRangeFn then
        for _, spec in ipairs(ITEM_RANGES) do
            local okR, raw = pcall(itemInRangeFn, spec.item, unit)
            if okR then
                local val = Safe.Value(raw)
                if val == true or val == 1 then
                    maxRange = spec.range
                    break
                elseif val == false or val == 0 then
                    minRange = spec.range
                end
            end
        end
    end

    if maxRange == 8 then
        return 8, "< 8m"
    end
    if maxRange == 13 then
        if d3 == true then
            return 10, "~10m"
        elseif d2 == true then
            return 11, "~11m"
        end
        return 13, "~13m"
    end
    if maxRange == 18 then
        return 16, "~16m"
    end
    if maxRange == 23 then
        if minRange <= 13 then
            if d3 == true then return 10, "~10m" end
            if d2 == true then return 11, "~11m" end
            return 18, "~18m"
        end
        return 21, "~21m"
    end
    if maxRange == 28 then
        return 26, "~26m"
    end
    if maxRange == 33 then
        return 31, "~31m"
    end
    if maxRange == 38 then
        return 36, "~36m"
    end
    if maxRange == 48 then
        if in43Checked then
            if in43 then
                return 41, "~41m"
            end
            return 46, "~46m"
        end
        return 43, "~43m"
    end
    if minRange >= 48 then
        return 60, "> 48m"
    end

    if d3 == true then
        return 8, L["< 10m"]
    elseif d2 == true then
        return 11, L["~11m"]
    elseif d1 == true then
        if screenRadial then
            local est = math.max(12, math.min(28, math.floor(12 + screenRadial * 14 + 0.5)))
            return est, string.format("~%dm", est)
        end
        return 20, L["12-28m"]
    elseif in43Checked and in43 then
        return 35, L["29-40m"]
    elseif hasPlateOrOnScreen then
        local est = math.max(29, math.min(40, math.floor(29 + (screenRadial or 0.5) * 9 + 0.5)))
        return est, string.format("~%dm", est)
    end

    return nil, nil
end

local function FormatBearingLabel(angleRad)
    if not angleRad then return L["Nearby"] end
    local absA = math.abs(angleRad)
    if absA <= 0.42 then
        return L["Ahead"]
    elseif absA >= 2.35 then
        return L["Behind"]
    elseif angleRad > 0 then
        return L["To your left"]
    end
    return L["To your right"]
end

local function RecomputeOnScreenFlags()
    local counts = {}
    for _, key in pairs(Spotter.visibleUnits) do
        counts[key] = (counts[key] or 0) + 1
    end
    for key, entry in pairs(Spotter.entries) do
        local c = counts[key] or 0
        entry.onScreen = c > 0
        entry.onScreenCount = c
    end
end

local function IsPlateAccessible(plate)
    if not plate then return false end
    if plate.IsForbidden then
        local ok, forbidden = pcall(plate.IsForbidden, plate)
        if not ok or forbidden then
            return false
        end
    end
    return true
end

local function EnsurePlateBadge(plate)
    local badge = Spotter.plateBadges[plate]
    if badge then return badge end

    local f = CreateFrame("Frame", nil, plate)
    f:SetSize(96, 13)
    f:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    f:EnableMouse(false)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.80)
    f.bg = bg

    local bar = f:CreateTexture(nil, "BORDER")
    bar:SetSize(2, 13)
    bar:SetPoint("LEFT")
    f.bar = bar

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER", 1, 0)
    lbl:SetJustifyH("CENTER")
    f.lbl = lbl

    f:Hide()
    Spotter.plateBadges[plate] = f
    return f
end

local function HidePlateBadgeForUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not IsPlateAccessible(plate) then return end
    local badge = Spotter.plateBadges[plate]
    if badge then
        badge:Hide()
    end
end

local function UpdatePlateBadge(unit, entry)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not IsPlateAccessible(plate) then return end

    local s = ns.db and ns.db.settings
    local enabled = s and s.spotterEnabled ~= false and s.spotterNameplateBadges == true
    if not enabled or not entry then
        local existing = Spotter.plateBadges[plate]
        if existing then existing:Hide() end
        return
    end

    local badge = EnsurePlateBadge(plate)
    local col = STANCE_COLORS[entry.stance] or STANCE_COLORS.ENEMY
    local tagText = entry.stance == "ENEMY" and L["ENEMY CLAN"]
        or (entry.stance == "WATCHLIST" and L["WATCHLIST"])
        or (entry.stance == "FRIEND" and L["FRIEND"])
        or (entry.stance == "ALLY" and L["ALLY CLAN"] or L["SAME CLAN"])

    badge.bg:SetColorTexture(0.05, 0.05, 0.07, 0.82)
    badge.bar:SetColorTexture(col.r, col.g, col.b, 0.95)
    badge.lbl:SetText(col.hex .. tagText .. "|r")
    local w = math.max(58, math.min(116, (badge.lbl:GetStringWidth() or 48) + 12))
    badge:SetWidth(w)
    badge:Show()
end

function Spotter:GetStanceLabel(stance)
    if stance == "ENEMY" then return L["Enemy Clan"] end
    if stance == "WATCHLIST" then return L["Watchlist"] end
    if stance == "FRIEND" then return L["Friend"] end
    if stance == "ALLY" then return L["Ally Clan"] end
    if stance == "SAME" then return L["Same Clan"] end
    return L["Neutral"]
end

function Spotter:GetStanceColor(stance)
    return STANCE_COLORS[stance] or STANCE_COLORS.SAME
end

function Spotter:ClassifyGuild(rawGuildName)
    if not rawGuildName or rawGuildName == "" then
        return nil, nil
    end

    local myNormGuild = GetPlayerNormalizedGuild()
    if myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(rawGuildName) == myNormGuild then
        return "SAME", nil
    end

    if ns.Clan and ns.Clan.LookupGuildStance then
        local stance, dipEntry = ns.Clan:LookupGuildStance(rawGuildName)
        if stance == "ENEMY" or stance == "ALLY" then
            return stance, dipEntry
        end
    end
    return nil, nil
end

local function ShouldNotifyStance(stance, key)
    if Spotter.manualTracked and key and Spotter.manualTracked[key] then
        return false
    end
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then return false end
    if stance == "ENEMY" then return s.spotterNotifyEnemy ~= false end
    if stance == "WATCHLIST" then return s.spotterNotifyWatchlist ~= false end
    if stance == "FRIEND" then return s.spotterNotifyFriends ~= false end
    if stance == "ALLY" then return s.spotterNotifyAlly ~= false end
    if stance == "SAME" then return s.spotterNotifySameClan == true end
    return false
end

local function PlaySpotterSound(stance)
    local s = ns.db and ns.db.settings
    if not s or s.spotterSound == false then return end
    if not PlaySound then return end

    if SOUNDKIT then
        local kit
        if stance == "ENEMY" then
            kit = SOUNDKIT.RAID_WARNING or SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.TELL_MESSAGE
        elseif stance == "ALLY" then
            kit = SOUNDKIT.READY_CHECK or SOUNDKIT.IG_QUEST_LOG_OPEN
        else
            kit = SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_QUEST_LOG_OPEN
        end
        if kit then
            pcall(PlaySound, kit, "Master")
            return
        end
    end

    local soundName = (stance == "ENEMY") and "RaidWarning" or ((stance == "ALLY") and "ReadyCheck" or "TellMessage")
    pcall(PlaySound, soundName)
end

function Spotter:MaybeTriggerAlert(entry)
    if not entry or not ShouldNotifyStance(entry.stance, entry.key) then return end

    local now = time()
    local cooldown = (entry.stance == "ENEMY") and ENEMY_ALERT_COOLDOWN or FRIENDLY_ALERT_COOLDOWN
    local prev = self.alertCooldowns[entry.key] or 0
    if (now - prev) < cooldown then
        return
    end
    self.alertCooldowns[entry.key] = now

    local kin = self:GetTargetKinematics(entry)
    local distStr = (kin and kin.distText) or entry.lastDistText or L["Nearby"]
    local bearingStr = (kin and kin.hasAngle) and FormatBearingLabel(kin.angle) or nil
    local proxSummary = bearingStr and (distStr .. " · " .. bearingStr) or distStr
    local locLabel = (entry.fullLocationText and entry.fullLocationText ~= "") and entry.fullLocationText
        or ((entry.locationText and entry.locationText ~= "") and entry.locationText or "")

    local col = STANCE_COLORS[entry.stance] or STANCE_COLORS.SAME
    local tag = col.hex .. "[" .. self:GetStanceLabel(entry.stance):upper() .. "]|r"
    local classHex = Compat.ClassHex and Compat.ClassHex(entry.classFile) or "|cffffffff"
    local shownName = entry.displayName or "?"
    local playerCol = "|Haddon:SCentral:target:" .. entry.key .. "|h" .. classHex .. shownName .. "|r|h"
    local guildText = entry.guild and (" |cff9ea8b8<" .. entry.guild .. ">|r") or ""
    local whereText = ""
    if locLabel ~= "" then
        whereText = " — |cff58d8ff" .. string.format(L["[Location: %s]"], locLabel .. " · " .. proxSummary) .. "|r"
    elseif proxSummary ~= "" then
        whereText = " — |cff58d8ff(" .. proxSummary .. ")|r"
    end
    local reasonText = (entry.reason and entry.reason ~= "") and (" — |cffffd280" .. entry.reason .. "|r") or ""
    local radarLink = "|Haddon:SCentral:spotter|h|cff58a6ff[" .. L["Target Radar"] .. "]|r|h"

    local s = ns.db and ns.db.settings
    local hudActive = (not s) or (s.spotterAutoShowHUD ~= false)
    if (not hudActive) or entry.stance == "ENEMY" or entry.stance == "WATCHLIST" then
        ns:Print("%s %s%s%s%s %s", tag, playerCol, guildText, whereText, reasonText, radarLink)
    end

    if s and s.spotterAutoShowHUD == false then
        local screenLoc = (entry.locationText and entry.locationText ~= "") and (entry.locationText .. " · " .. proxSummary) or proxSummary
        local screenMsg = string.format(
            "%s[%s]|r %s%s|r%s%s",
            col.hex,
            self:GetStanceLabel(entry.stance):upper(),
            classHex,
            shownName,
            entry.guild and (" <" .. entry.guild .. ">") or "",
            screenLoc ~= "" and (" — " .. screenLoc) or ""
        )
        if RaidNotice_AddMessage and RaidWarningFrame then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, screenMsg, { r = col.r, g = col.g, b = col.b })
        elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, screenMsg, col.r, col.g, col.b, 1.0)
        end
    end

    PlaySpotterSound(entry.stance)

    local alert = {
        key = entry.key,
        stance = entry.stance,
        displayName = entry.displayName,
        firstName = entry.firstName,
        guid = entry.guid,
        guild = entry.guild,
        classFile = entry.classFile,
        level = entry.level,
        reason = entry.reason,
        targetName = entry.targetName,
        locationText = entry.locationText,
        fullLocationText = entry.fullLocationText,
        coordsText = entry.coordsText,
        distText = distStr,
        bearingText = bearingStr,
        ts = now,
    }
    self.lastAlert = alert
    ns:Emit("SPOTTER_ALERT", alert)
end

function Spotter:FocusTarget(key)
    if not key or key == "" then return false end
    local entry = self.entries[key]
    if not entry then
        -- Fall back to firstName or normalized key match in case the key was upgraded with a surname.
        local altParsed = Compat.ParseCharacterName(key)
        local lk = altParsed and altParsed.lookupKey or key:lower()
        local firstLower = altParsed and altParsed.firstName:lower() or lk
        for _, candidate in pairs(self.entries) do
            if candidate.key == lk or (candidate.firstName and candidate.firstName:lower() == firstLower) then
                entry = candidate
                break
            end
        end
    end
    if not entry then
        ns:Print(L["Player is no longer in Target Radar range."])
        return false
    end

    entry.lastSeen = time()
    local alert = {
        key = entry.key,
        stance = entry.stance,
        displayName = entry.displayName,
        firstName = entry.firstName,
        guid = entry.guid,
        guild = entry.guild,
        classFile = entry.classFile,
        level = entry.level,
        reason = entry.reason,
        targetName = entry.targetName,
        locationText = entry.locationText,
        fullLocationText = entry.fullLocationText,
        ts = time(),
    }
    self.lastAlert = alert
    if ns.SpotterHUD then
        ns.SpotterHUD.focusedKey = entry.key
        ns.SpotterHUD.interactionOpen = true
        ns.SpotterHUD.interactionKey = entry.key
        if ns.SpotterHUD.Show then
            ns.SpotterHUD:Show(true)
        end
    end
    return true
end

local function TrimExcessTargets()
    local list = {}
    for _, e in pairs(Spotter.entries) do
        table.insert(list, e)
    end
    if #list <= MAX_TARGETS then return end

    table.sort(list, function(a, b)
        if a.onScreen ~= b.onScreen then return a.onScreen end
        local pa = STANCE_PRIORITY[a.stance] or 9
        local pb = STANCE_PRIORITY[b.stance] or 9
        if pa ~= pb then return pa < pb end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)

    for i = MAX_TARGETS + 1, #list do
        Spotter.entries[list[i].key] = nil
    end
end

local function NormalizeAngleRad(a)
    local pi = math.pi
    while a > pi do a = a - 2 * pi end
    while a < -pi do a = a + 2 * pi end
    return a
end

local function ComputeScreenAngleAndRadial(px, py, pScale)
    if not (UIParent and UIParent.GetCenter) then return nil, nil end
    local okC, cx, cy = pcall(UIParent.GetCenter, UIParent)
    cx, cy = Safe.Number(cx), Safe.Number(cy)
    if not (okC and cx and cy and px) then return nil, nil end

    local uScale = (UIParent.GetEffectiveScale and Safe.Number(Safe.Call(UIParent.GetEffectiveScale, UIParent))) or 1
    local s = pScale or 1
    local screenDx = (px * s) - (cx * uScale)
    local halfW = math.max(1, (Safe.Number(Safe.Call(UIParent.GetWidth, UIParent)) or 1000) * 0.5 * uScale)
    local halfH = math.max(1, (Safe.Number(Safe.Call(UIParent.GetHeight, UIParent)) or 700) * 0.5 * uScale)

    -- A visible nameplate is always in the camera's forward frustum: keep forward depth positive
    -- so looking downwards or standing close never flips an in-view player into "Behind".
    local playerScreenY = (cy * uScale) - (halfH * 0.22)
    local rawDy = py and ((py * s) - playerScreenY) or (halfH * 0.55)
    local forwardDy = math.max(halfH * 0.45, rawDy)

    local angle = 0
    if math.abs(screenDx) > 3 then
        angle = math.atan2(-screenDx, forwardDy)
    end

    local normX = screenDx / halfW
    local normY = rawDy / halfH
    local radial = math.min(1.4, math.sqrt(normX * normX + normY * normY))
    return NormalizeAngleRad(angle), radial
end

local function UnitMatchesEntry(unit, entry)
    if not unit or not entry then return false end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then return false end

    local uGuid = Safe.String(Safe.Call(UnitGUID, unit))
    if entry.guid and uGuid then
        return uGuid == entry.guid
    end

    if Compat.ResolveUnitFullName then
        local resolved = Compat.ResolveUnitFullName(unit, uGuid)
        if resolved and resolved.lookupKey then
            if resolved.lookupKey == entry.key then
                return true
            end
            if resolved.surname and entry.displayName and entry.displayName:find("%s") then
                return false
            end
        end
    end

    local uName = Safe.String(Safe.Call(UnitName, unit))
    if uName and uName ~= "" then
        if entry.unitName and uName:lower() == entry.unitName:lower() and not (entry.guid and uGuid and entry.guid ~= uGuid) then
            local parsedRaw = Compat.ParseCharacterName and Compat.ParseCharacterName(uName)
            if not (parsedRaw and parsedRaw.surname and entry.key and parsedRaw.lookupKey ~= entry.key) then
                return true
            end
        end
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(uName)
        if parsed then
            if parsed.lookupKey == entry.key then
                return true
            end
            local entryHasSurname = type(entry.displayName) == "string" and entry.displayName:find("%s") ~= nil
            if (not parsed.surname or not entryHasSurname)
                and entry.firstName and parsed.firstName:lower() == entry.firstName:lower() then
                return true
            end
        end
    end
    return false
end

local function ResolvePlateForUnitOrEntry(unit, entry)
    if unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and IsPlateAccessible(p) then
            local pUnit = Safe.String(p.namePlateUnitToken) or (p.UnitFrame and Safe.String(p.UnitFrame.unit))
            if pUnit and pUnit:match("^nameplate") then
                return p, pUnit
            end
            return p, (unit:match("^nameplate") and unit or nil)
        end
    end
    if not entry then return nil, nil end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                if IsPlateAccessible(p) then
                    local pUnit = Safe.String(p.namePlateUnitToken) or (p.UnitFrame and Safe.String(p.UnitFrame.unit))
                    if pUnit and UnitMatchesEntry(pUnit, entry) then
                        return p, pUnit
                    end
                end
            end
        end
    end
    for i = 1, 40 do
        local pUnit = "nameplate" .. i
        if UnitMatchesEntry(pUnit, entry) then
            local plate
            if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
                local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, pUnit)
                if ok and IsPlateAccessible(p) then plate = p end
            end
            return plate, pUnit
        end
    end
    return nil, nil
end

function Spotter:InspectUnit(unit, isNameplate)
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then
        if isNameplate then HidePlateBadgeForUnit(unit) end
        return nil
    end

    if not unit or Safe.IsSecret(unit) then return nil end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
            ns:Emit("SPOTTER_UPDATED")
        end
        return nil
    end

    local isPlayer = Safe.Value(Safe.Call(UnitIsPlayer, unit))
    if isPlayer ~= true then
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
        end
        return nil
    end

    local guid = Safe.String(Safe.Call(UnitGUID, unit))
    local rawUnitName = Safe.String(Safe.Call(UnitName, unit))
    local existingName = nil
    if guid then
        for _, e in pairs(self.entries) do
            if e.guid == guid and e.displayName and e.displayName:find("%s") then
                existingName = e.displayName
                break
            end
        end
    end
    local resolved, rawRealm = Compat.ResolveUnitFullName(unit, guid, existingName)
    local rawName = resolved and resolved.fullName or rawUnitName
    if not rawName or rawName == "" or Compat.IsMe(rawName, guid) then
        if isNameplate then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
        end
        return nil
    end

    local parsed = Compat.ParseCharacterName(rawName)
    local key = (parsed and parsed.lookupKey) or NormalizeKeyPart(rawName)
    if not key or key == "" then return nil end

    local now = time()
    local isDismissed = (not self.manualTracked[key]) and self.dismissedUntil[key] and now < self.dismissedUntil[key]
    local isIgnoredGroup = ShouldIgnoreGroupUnit(unit, key, guid)

    local checkFirst = resolved and resolved.firstName or rawUnitName
    local gName, gRank = GetUnitSafeGuild(unit, guid)
    local isMyGuildMember, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote = LookupKnownPlayerGuildOrMembership(checkFirst, rawName, guid)
    if (not gName or gName == "") and knownGuild and knownGuild ~= "" then
        gName = knownGuild
    end

    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    if gName and gName ~= "" and myNormGuild and myNormGuild ~= "" then
        if NormalizeKeyPart(gName) ~= myNormGuild then
            -- Unit belongs to a known different guild; never misclassify them as our own clan.
            isMyGuildMember = false
        else
            isMyGuildMember = true
        end
    elseif not gName or gName == "" then
        if UnitIsInMyGuild then
            local inMyGuild = Safe.Value(Safe.Call(UnitIsInMyGuild, unit))
            if inMyGuild == true then
                isMyGuildMember = true
            elseif inMyGuild == false then
                isMyGuildMember = false
            end
        end
    end

    local stance, resolvedReason
    if not isDismissed and not isIgnoredGroup then
        local rawStance, dipEntry = self:ClassifyGuild(gName)
        stance, resolvedReason, gName = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, watchNote, key, myNormGuild, myGuildName, gName)
    end
    if not stance then
        local removedStale = false
        if self.entries[key] then
            self.entries[key] = nil
            removedStale = true
        end
        if guid then
            for oldKey, oldEntry in pairs(self.entries) do
                if oldEntry.guid == guid then
                    self.entries[oldKey] = nil
                    removedStale = true
                end
            end
        end
        if self.lastAlert and (self.lastAlert.key == key or (guid and self.lastAlert.guid == guid)) then
            self.lastAlert = nil
            removedStale = true
        end
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
            ns:Emit("SPOTTER_UPDATED")
        elseif isNameplate then
            HidePlateBadgeForUnit(unit)
            if removedStale then
                RecomputeOnScreenFlags()
                ns:Emit("SPOTTER_UPDATED")
            end
        elseif removedStale then
            RecomputeOnScreenFlags()
            ns:Emit("SPOTTER_UPDATED")
        end
        return nil
    end

    -- Upgrade any earlier first-name-only sighting matching the same GUID cleanly.
    local upgradedOld
    if guid then
        for oldKey, oldEntry in pairs(self.entries) do
            if oldKey ~= key and oldEntry.guid == guid then
                upgradedOld = oldEntry
                self.entries[oldKey] = nil
                if self.alertCooldowns[oldKey] then
                    self.alertCooldowns[key] = self.alertCooldowns[oldKey]
                    self.alertCooldowns[oldKey] = nil
                end
                for uTok, mappedKey in pairs(self.visibleUnits) do
                    if mappedKey == oldKey then
                        self.visibleUnits[uTok] = key
                    end
                end
                break
            end
        end
    end

    local displayName = (parsed and parsed.displayName) or rawName
    local firstName = (parsed and parsed.firstName) or rawName
    local targetMacroName = SanitizeMacroTargetName(displayName, rawRealm)
    if not targetMacroName then return nil end

    local _, classFile = Safe.Call(UnitClass, unit)
    classFile = Safe.String(classFile) or knownClass
    local level = Safe.Number(Safe.Call(UnitLevel, unit)) or knownLevel
    local isDead = Safe.Value(Safe.Call(UnitIsDeadOrGhost, unit)) == true

    local isNewOrChanged = false
    local entry = self.entries[key] or upgradedOld
    if not entry then
        entry = {
            key = key,
            firstSeen = now,
        }
        isNewOrChanged = true
    elseif entry.stance ~= stance or not entry._alertEvaluated then
        isNewOrChanged = true
    end
    entry.key = key
    self.entries[key] = entry

    local prevDisplayName = entry and entry.displayName
    local prevGuild = entry and entry.guild
    local prevLevel = entry and entry.level
    local prevDead = entry and entry.dead
    local prevOnScreen = entry and entry.onScreen

    if not (parsed and parsed.surname) and entry and entry.displayName and entry.displayName:find("%s") then
        displayName = entry.displayName
        firstName = entry.firstName or firstName
    end
    entry.displayName = displayName
    entry.firstName = firstName
    entry.unitName = rawUnitName or entry.unitName
    entry.targetName = targetMacroName
    entry.guild = gName
    entry.guildRank = gRank
    entry.stance = stance
    entry.reason = resolvedReason or ""
    entry._manualTracked = self.manualTracked[key] == true
    entry.classFile = classFile or entry.classFile
    entry.level = (level and level > 0) and level or entry.level
    entry.dead = isDead
    entry.guid = guid or entry.guid
    entry.lastSeen = now
    entry.unitHint = unit

    local plate, plateUnit = ResolvePlateForUnitOrEntry(unit, entry)
    if plateUnit then
        entry.unitToken = plateUnit
    elseif isNameplate or unit:match("^party") or unit:match("^raid") or unit == "focus" then
        entry.unitToken = unit
    else
        entry.unitToken = nil
    end

    local screenRadial
    if plate and UIParent and UIParent.GetCenter then
        local refFrame = (plate.UnitFrame and IsPlateAccessible(plate.UnitFrame) and plate.UnitFrame) or plate
        if refFrame and refFrame.GetCenter and (not refFrame.IsVisible or refFrame:IsVisible()) and (not plate.IsShown or plate:IsShown()) then
            local okCenter, px, py = pcall(refFrame.GetCenter, refFrame)
            px, py = Safe.Number(px), Safe.Number(py)
            if okCenter and px then
                local pScale = (refFrame.GetEffectiveScale and Safe.Number(Safe.Call(refFrame.GetEffectiveScale, refFrame))) or 1
                local _, radial = ComputeScreenAngleAndRadial(px, py, pScale)
                screenRadial = radial
            end
        end
    end

    -- Capture immediate calibrated proximity metrics when unit is reachable
    local measuredYards, measuredText = MeasureUnitDistance(unit, screenRadial, isNameplate or (plate ~= nil) or (screenRadial ~= nil))
    if measuredYards and measuredText then
        entry.lastDistYards = measuredYards
        entry.lastDistText = measuredText
    end

    local locSnap = CaptureLocationSnapshot(unit)
    ApplyLocationSnapshotToEntry(entry, locSnap)

    local activePlateUnit = (isNameplate and unit) or plateUnit
    local newPlateMapped = false
    if activePlateUnit then
        if self.visibleUnits[activePlateUnit] ~= key then
            newPlateMapped = true
        end
        self.visibleUnits[activePlateUnit] = key
        UpdatePlateBadge(activePlateUnit, entry)
    end

    RecomputeOnScreenFlags()
    TrimExcessTargets()

    if isNewOrChanged then
        entry._alertEvaluated = true
        self:MaybeTriggerAlert(entry)
    end

    local metadataChanged = isNewOrChanged
        or newPlateMapped
        or (entry.dead ~= prevDead)
        or (entry.displayName ~= prevDisplayName)
        or (entry.guild ~= prevGuild)
        or (entry.level ~= prevLevel)
        or (entry.onScreen ~= prevOnScreen)
    if metadataChanged then
        ns:Emit("SPOTTER_UPDATED")
    end
    return entry
end

function Spotter:InspectChatSighting(rawSender, rawGuid)
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then return nil end

    local cleanSender = Safe.String(rawSender)
    local cleanGuid = Safe.String(rawGuid)
    if not cleanSender or cleanSender == "" or Compat.IsMe(cleanSender, cleanGuid) then
        return nil
    end

    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(nil, cleanGuid, cleanSender)
    local bestFullName = (resolved and resolved.fullName) or cleanSender
    local parsed = Compat.ParseCharacterName(bestFullName)
    local key = (parsed and parsed.lookupKey) or NormalizeKeyPart(bestFullName)
    if not key or key == "" then return nil end

    local now = time()
    if (not self.manualTracked[key]) and self.dismissedUntil[key] and now < self.dismissedUntil[key] then
        return nil
    end
    if ShouldIgnoreGroupUnit(nil, key, cleanGuid) then
        return nil
    end

    local firstName = (parsed and parsed.firstName) or bestFullName
    local displayName = (parsed and parsed.displayName) or bestFullName

    local tempEntry = {
        key = key,
        guid = cleanGuid,
        firstName = firstName,
        unitName = firstName,
    }
    local liveUnit = self:FindLiveUnitForEntry(tempEntry)
    if liveUnit then
        return self:InspectUnit(liveUnit, liveUnit:match("^nameplate") ~= nil)
    end

    local isMyGuildMember, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote = LookupKnownPlayerGuildOrMembership(firstName, displayName, cleanGuid)
    local gName, gRank = GetUnitSafeGuild(nil, cleanGuid)
    if (not gName or gName == "") and knownGuild and knownGuild ~= "" then
        gName = knownGuild
    end
    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    if gName and gName ~= "" and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) ~= myNormGuild then
        isMyGuildMember = false
    elseif gName and gName ~= "" and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) == myNormGuild then
        isMyGuildMember = true
    end
    local rawStance, dipEntry = self:ClassifyGuild(gName)
    local stance, resolvedReason
    stance, resolvedReason, gName = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, watchNote, key, myNormGuild, myGuildName, gName)
    if not stance then
        return nil
    end

    local targetMacroName = SanitizeMacroTargetName(displayName, nil)
    if not targetMacroName then return nil end

    local isNewOrChanged = false
    local entry = self.entries[key]
    if not entry and cleanGuid then
        for oldKey, oldEntry in pairs(self.entries) do
            if oldEntry.guid == cleanGuid then
                entry = oldEntry
                if oldKey ~= key then
                    self.entries[oldKey] = nil
                end
                break
            end
        end
    end
    if not entry then
        entry = {
            key = key,
            firstSeen = now,
        }
        isNewOrChanged = true
    elseif entry.stance ~= stance or not entry._alertEvaluated then
        isNewOrChanged = true
    end
    entry.key = key
    self.entries[key] = entry

    if not (parsed and parsed.surname) and entry.displayName and entry.displayName:find("%s") then
        displayName = entry.displayName
        firstName = entry.firstName or firstName
    end
    entry.displayName = displayName
    entry.firstName = firstName
    entry.unitName = entry.unitName or firstName
    entry.targetName = targetMacroName
    entry.guild = gName
    entry.guildRank = gRank or entry.guildRank
    entry.stance = stance
    entry.reason = resolvedReason or ""
    entry._manualTracked = self.manualTracked[key] == true
    entry.classFile = knownClass or entry.classFile or (Compat.ClassFileFromGuid and Compat.ClassFileFromGuid(cleanGuid))
    entry.level = (knownLevel and knownLevel > 0) and knownLevel or entry.level
    entry.guid = cleanGuid or entry.guid
    entry.lastSeen = now
    entry.lastDistText = entry.lastDistText or L["12-28m"]
    entry.lastDistYards = entry.lastDistYards or 20

    local locSnap = CaptureLocationSnapshot("player")
    ApplyLocationSnapshotToEntry(entry, locSnap)

    RecomputeOnScreenFlags()
    TrimExcessTargets()

    if isNewOrChanged then
        entry._alertEvaluated = true
        self:MaybeTriggerAlert(entry)
    end

    ns:Emit("SPOTTER_UPDATED")
    return entry
end

function Spotter:RefreshVisibleNameplates()
    local seenUnits = {}
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                if IsPlateAccessible(plate) then
                    local unit = Safe.String(plate.namePlateUnitToken)
                    if not unit and plate.UnitFrame then
                        unit = Safe.String(plate.UnitFrame.unit)
                    end
                    if unit and UnitExists(unit) then
                        seenUnits[unit] = true
                        self:InspectUnit(unit, true)
                        local npTarget = unit .. "target"
                        if Safe.Value(Safe.Call(UnitExists, npTarget)) == true then
                            self:InspectUnit(npTarget, false)
                        end
                    end
                end
            end
        end
    end

    for i = 1, 40 do
        local unit = "nameplate" .. i
        if Safe.Value(Safe.Call(UnitExists, unit)) == true then
            if not seenUnits[unit] then
                self:InspectUnit(unit, true)
            end
            local npTarget = unit .. "target"
            if Safe.Value(Safe.Call(UnitExists, npTarget)) == true then
                self:InspectUnit(npTarget, false)
            end
        end
    end

    for _, token in ipairs({ "softfriend", "softenemy", "softinteract", "target", "targettarget", "focus", "focustarget", "mouseover", "mouseovertarget" }) do
        if Safe.Value(Safe.Call(UnitExists, token)) == true then
            self:InspectUnit(token, false)
        end
    end

    if Compat.IsInGroup and Compat.IsInGroup() then
        local inRaid = Compat.IsInRaid and Compat.IsInRaid()
        local numMembers = Compat.GetNumGroupMembers and Compat.GetNumGroupMembers() or 0
        local prefix = inRaid and "raid" or "party"
        local limit = inRaid and math.min(40, numMembers) or math.min(4, numMembers)
        for i = 1, limit do
            local token = prefix .. i
            if Safe.Value(Safe.Call(UnitExists, token)) == true and Safe.Value(Safe.Call(UnitIsVisible, token)) == true then
                self:InspectUnit(token, false)
            end
            local subTarget = token .. "target"
            if Safe.Value(Safe.Call(UnitExists, subTarget)) == true then
                self:InspectUnit(subTarget, false)
            end
        end
    end
end

function Spotter:ReclassifyActiveEntries()
    local rekeyed = {}
    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    local now = time()
    for key, entry in pairs(self.entries) do
        local ignored = ShouldIgnoreGroupUnit(nil, key, entry.guid)
        local dismissed = (not self.manualTracked[key]) and self.dismissedUntil[key] and now < self.dismissedUntil[key]
        local stance, resolvedReason, updatedGuild
        if not ignored and not dismissed then
            local rawStance, dipEntry = self:ClassifyGuild(entry.guild)
            local isMyGuildMember, knownGuild, _, _, isWatched, isFriend, watchNote = LookupKnownPlayerGuildOrMembership(entry.firstName, entry.displayName, entry.guid)
            local gName = (entry.guild and entry.guild ~= "") and entry.guild or knownGuild
            if gName and gName ~= "" and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) ~= myNormGuild then
                isMyGuildMember = false
            end
            rawStance, dipEntry = self:ClassifyGuild(gName)
            stance, resolvedReason, updatedGuild = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, watchNote, key, myNormGuild, myGuildName, gName)
            if updatedGuild and updatedGuild ~= "" then
                entry.guild = updatedGuild
            end
        end
        if not stance then
            self.entries[key] = nil
            if self.lastAlert and self.lastAlert.key == key then
                self.lastAlert = nil
            end
        else
            entry.stance = stance
            entry.reason = resolvedReason or ""
            entry._manualTracked = self.manualTracked[key] == true
            if entry.guid and Compat.LookupForeverFullName then
                local resolved = Compat.LookupForeverFullName(entry.guid, entry.firstName)
                if resolved and resolved.surname then
                    local parsed = Compat.ParseCharacterName(resolved.fullName)
                    if parsed and parsed.lookupKey ~= "" then
                        entry.displayName = parsed.displayName
                        entry.firstName = parsed.firstName
                        entry.targetName = SanitizeMacroTargetName(parsed.displayName, nil) or parsed.displayName
                        if parsed.lookupKey ~= key then
                            entry.key = parsed.lookupKey
                            rekeyed[key] = entry
                        end
                    end
                end
            end
        end
    end
    for oldKey, entry in pairs(rekeyed) do
        self.entries[oldKey] = nil
        self.entries[entry.key] = entry
        for uTok, mapped in pairs(self.visibleUnits) do
            if mapped == oldKey then
                self.visibleUnits[uTok] = entry.key
            end
        end
    end

    for unit, key in pairs(self.visibleUnits) do
        local entry = self.entries[key]
        if entry then
            UpdatePlateBadge(unit, entry)
        else
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
        end
    end

    RecomputeOnScreenFlags()
    self:RefreshVisibleNameplates()
    ns:Emit("SPOTTER_UPDATED")
end

function Spotter:OnGuildChanged()
    local currentScope = ns.Clan and ns.Clan.GetActiveScopeToken and ns.Clan:GetActiveScopeToken() or ""
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true

    if not inGuild and self.lastScopeToken and self.lastScopeToken ~= "" then
        self._cachedPlayerGuild = nil
        self:Clear(true)
        if Compat.ClearGuildMembers then Compat.ClearGuildMembers() end
        self.lastScopeToken = ""
        return
    end

    if self.lastScopeToken and self.lastScopeToken ~= "" and currentScope ~= "" and self.lastScopeToken ~= currentScope then
        self._cachedPlayerGuild = nil
        self:Clear(true)
        if Compat.ClearGuildMembers then Compat.ClearGuildMembers() end
    end

    if Compat.SyncRosterForeverNames then
        Compat.SyncRosterForeverNames()
    end
    if currentScope ~= "" then
        self.lastScopeToken = currentScope
    end
    self:ReclassifyActiveEntries()
end

function Spotter:Clear(silent)
    wipe(self.entries)
    wipe(self.visibleUnits)
    wipe(self.alertCooldowns)
    wipe(self.dismissedUntil)
    wipe(self.manualTracked)
    wipe(self.manualTrackedStance)
    self.lastAlert = nil

    for _, badge in pairs(self.plateBadges) do
        if badge and badge.Hide then
            badge:Hide()
        end
    end

    if not silent then
        ns:Emit("SPOTTER_UPDATED")
    end
end

function Spotter:DismissTarget(key)
    if not key or not self.entries[key] then return false end
    self.entries[key] = nil
    self.manualTracked[key] = nil
    self.manualTrackedStance[key] = nil
    self.dismissedUntil[key] = time() + DISMISS_COOLDOWN_SECONDS
    for unit, uKey in pairs(self.visibleUnits) do
        if uKey == key then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
        end
    end
    ns:Emit("SPOTTER_UPDATED")
    return true
end

function Spotter:FindLiveUnitForEntry(entry)
    if not entry then return nil, nil end

    local plate, plateUnit = ResolvePlateForUnitOrEntry(nil, entry)
    if plateUnit then
        return plateUnit, plate
    end

    for _, token in ipairs({ "softfriend", "softenemy", "softinteract", "target", "focus", "mouseover", "targettarget", "focustarget", "mouseovertarget" }) do
        if UnitMatchesEntry(token, entry) then
            local tPlate = ResolvePlateForUnitOrEntry(token, entry)
            return token, tPlate
        end
    end

    for i = 1, 40 do
        local npTarget = "nameplate" .. i .. "target"
        if UnitMatchesEntry(npTarget, entry) then
            return npTarget, ResolvePlateForUnitOrEntry(npTarget, entry)
        end
    end

    local inRaid = Compat.IsInRaid()
    local numMembers = Compat.GetNumGroupMembers()
    if numMembers and numMembers > 0 then
        local prefix = inRaid and "raid" or "party"
        local limit = inRaid and math.min(40, numMembers) or math.min(4, numMembers)
        for i = 1, limit do
            local token = prefix .. i
            if UnitMatchesEntry(token, entry) then
                return token, ResolvePlateForUnitOrEntry(token, entry)
            end
            local subTarget = token .. "target"
            if UnitMatchesEntry(subTarget, entry) then
                return subTarget, ResolvePlateForUnitOrEntry(subTarget, entry)
            end
        end
    end

    return nil, nil
end

function Spotter:GetTargetKinematics(entry)
    if not entry then return nil end

    local unit = entry.unitToken
    local plate, plateUnit
    if unit and UnitMatchesEntry(unit, entry) then
        plate, plateUnit = ResolvePlateForUnitOrEntry(unit, entry)
        if plateUnit then
            unit = plateUnit
            entry.unitToken = plateUnit
        end
    else
        unit, plate = self:FindLiveUnitForEntry(entry)
        entry.unitToken = unit
        if unit and unit:match("^nameplate%d+$") then
            plateUnit = unit
        end
    end

    if plateUnit and entry.key then
        self.visibleUnits[plateUnit] = entry.key
        entry.onScreen = true
    end

    local facing = GetPlayerFacing and Safe.Number(Safe.Call(GetPlayerFacing)) or 0
    local angle, distYards, distText
    local hasDirectBearing = false

    if unit then
        entry.lastSeen = time()
        entry.dead = (Safe.Value(Safe.Call(UnitIsDeadOrGhost, unit)) == true)
        local uName = Safe.String(Safe.Call(UnitName, unit))
        if uName and uName ~= "" then
            entry.unitName = uName
        end
        -- 1. Engine-level world position when accessible
        if UnitPosition then
            local py, px, _, pMap = Safe.Call(UnitPosition, "player")
            local ty, tx, _, tMap = Safe.Call(UnitPosition, unit)
            py, px, pMap = Safe.Number(py), Safe.Number(px), Safe.Number(pMap)
            ty, tx, tMap = Safe.Number(ty), Safe.Number(tx), Safe.Number(tMap)
            if py and px and ty and tx and pMap and pMap == tMap then
                local dy = ty - py
                local dx = tx - px
                if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 then
                    distYards = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
                    local worldAngle = math.atan2(dx, dy)
                    angle = NormalizeAngleRad(worldAngle - facing)
                    entry._lastWorldHeading = worldAngle
                    hasDirectBearing = true
                end
            end
        end

        -- 2. Map coordinate vector fallback (works for party/raid members)
        if not angle and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
            local mapID = Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player"))
            if mapID then
                local px, py = GetUnitOrPlayerMapXY(mapID, "player")
                local tx, ty = GetUnitOrPlayerMapXY(mapID, unit)
                if px and py and tx and ty then
                    entry._anchorMapID = mapID
                    entry._anchorMapX = tx
                    entry._anchorMapY = ty
                    entry.coordsText = string.format("%.1f, %.1f", tx * 100, ty * 100)
                    local northDelta = py - ty
                    local westDelta = px - tx
                    if math.abs(northDelta) > 0.00001 or math.abs(westDelta) > 0.00001 then
                        local worldAngle = math.atan2(westDelta, northDelta)
                        angle = NormalizeAngleRad(worldAngle - facing)
                        entry._lastWorldHeading = worldAngle
                        hasDirectBearing = true
                    end
                end
            end
        end

        if not distYards and UnitDistanceSquared then
            local dSq, checked = Safe.Call(UnitDistanceSquared, unit)
            dSq = Safe.Number(dSq)
            if Safe.Value(checked) == true and dSq and dSq >= 0 then
                distYards = math.floor(math.sqrt(dSq) + 0.5)
            end
        end

        -- 3. Visible nameplate horizontal screen vector
        local screenRadial
        if plate and UIParent and UIParent.GetCenter then
            local refFrame = (plate.UnitFrame and IsPlateAccessible(plate.UnitFrame) and plate.UnitFrame) or plate
            if refFrame and refFrame.GetCenter and (not refFrame.IsVisible or refFrame:IsVisible()) and (not plate.IsShown or plate:IsShown()) then
                local okP, px, py = pcall(refFrame.GetCenter, refFrame)
                px, py = Safe.Number(px), Safe.Number(py)
                if okP and px then
                    local pScale = (refFrame.GetEffectiveScale and Safe.Number(Safe.Call(refFrame.GetEffectiveScale, refFrame))) or 1
                    local plateAngle, radial = ComputeScreenAngleAndRadial(px, py, pScale)
                    screenRadial = radial
                    if not angle and plateAngle then
                        angle = plateAngle
                        hasDirectBearing = true
                    end
                end
            end
        end

        -- 4. Forward cone sensor (soft targeting reticle is directly ahead)
        if not angle and (UnitMatchesEntry("softfriend", entry) or UnitMatchesEntry("softenemy", entry) or UnitMatchesEntry("softinteract", entry)) then
            angle = 0
            hasDirectBearing = true
        end

        if not distYards then
            local mYards, mText = MeasureUnitDistance(unit, screenRadial, (plate ~= nil) or entry.onScreen)
            if mYards and mText then
                distYards = mYards
                distText = mText
                entry.lastDistYards = mYards
                entry.lastDistText = mText
            else
                distText = entry.lastDistText or L["Nearby"]
                distYards = entry.lastDistYards
            end
        else
            distText = string.format("%dm", distYards)
            entry.lastDistText = distText
            entry.lastDistYards = distYards
        end
    end

    -- Refresh current zone/subzone and verified party/raid map coords at 5 Hz when unit is live
    local nowClock = (GetTime and GetTime()) or time()
    if unit and (not entry._lastLocSyncAt or (nowClock - entry._lastLocSyncAt) >= 0.20) then
        entry._lastLocSyncAt = nowClock
        local locSnap = CaptureLocationSnapshot(unit)
        ApplyLocationSnapshotToEntry(entry, locSnap)
    end

    return {
        unit = unit,
        hasAngle = (angle ~= nil),
        angle = angle and NormalizeAngleRad(angle) or nil,
        distYards = distYards or entry.lastDistYards,
        distText = distText or entry.lastDistText or L["Nearby"],
        exact = (distYards ~= nil),
    }
end

function Spotter:CleanupAbsentTargets(silent)
    local now = time()
    local changed = false

    for uTok, _ in pairs(self.visibleUnits) do
        local exists = Safe.Value(Safe.Call(UnitExists, uTok))
        if exists ~= true then
            self.visibleUnits[uTok] = nil
            HidePlateBadgeForUnit(uTok)
            changed = true
        end
    end
    RecomputeOnScreenFlags()

    for key, exp in pairs(self.dismissedUntil) do
        if now >= exp then
            self.dismissedUntil[key] = nil
        end
    end

    for key, entry in pairs(self.entries) do
        local isManual = self.manualTracked[key] == true
        local maxRetention = entry.dead and 3 or (isManual and MANUAL_RETENTION_SECONDS or RETENTION_SECONDS)
        local isRecent = (now - (entry.lastSeen or now)) <= maxRetention
        local keep = entry.onScreen
            or UnitMatchesEntry("target", entry)
            or UnitMatchesEntry("focus", entry)
            or UnitMatchesEntry("mouseover", entry)
            or isRecent
        if not keep then
            self.entries[key] = nil
            self.manualTracked[key] = nil
            self.manualTrackedStance[key] = nil
            if self.lastAlert and self.lastAlert.key == key then
                self.lastAlert = nil
            end
            changed = true
        end
    end

    if changed and not silent then
        ns:Emit("SPOTTER_UPDATED")
    end
    return changed
end

function Spotter:Prune(silent)
    self:CleanupAbsentTargets(silent)
end

function Spotter:GetCounts()
    local enemy, ally, same, onScreen, watchlist, friend = 0, 0, 0, 0, 0, 0
    for _, entry in pairs(self.entries) do
        if entry.stance == "ENEMY" then
            enemy = enemy + 1
        elseif entry.stance == "WATCHLIST" then
            watchlist = watchlist + 1
        elseif entry.stance == "FRIEND" then
            friend = friend + 1
        elseif entry.stance == "ALLY" then
            ally = ally + 1
        elseif entry.stance == "SAME" then
            same = same + 1
        end
        if entry.onScreen then
            onScreen = onScreen + 1
        end
    end
    local total = enemy + ally + same + watchlist + friend
    return enemy, ally, same, total, onScreen, watchlist, friend
end

function Spotter:TrackPlayer(rawName, rawGuild, classFile, level, guid, forcedStance)
    local cleanName = Safe.String(rawName)
    local cleanGuid = Safe.String(guid)
    if (not cleanName or cleanName == "") and not cleanGuid then
        return nil
    end
    if Compat.IsMe and Compat.IsMe(cleanName, cleanGuid) then
        return nil
    end

    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(nil, cleanGuid, cleanName)
    local bestFullName = (resolved and resolved.fullName) or cleanName
    local parsed = bestFullName and Compat.ParseCharacterName and Compat.ParseCharacterName(bestFullName)
    local key = (parsed and parsed.lookupKey) or NormalizeKeyPart(bestFullName)
    if not key or key == "" then return nil end

    local displayName = (parsed and parsed.displayName) or bestFullName
    local firstName = (parsed and parsed.firstName) or displayName
    local targetMacroName = SanitizeMacroTargetName(displayName, nil)
    if not targetMacroName then return nil end

    self.dismissedUntil[key] = nil
    self.alertCooldowns[key] = nil
    self.manualTracked[key] = true
    if forcedStance then
        self.manualTrackedStance[key] = forcedStance
    end

    local tempEntry = {
        key = key,
        guid = cleanGuid,
        firstName = firstName,
        unitName = firstName,
    }
    local liveUnit = self:FindLiveUnitForEntry(tempEntry)
    if not liveUnit and IsInGroup and Safe.Value(Safe.Call(IsInGroup)) == true then
        local isRaid = IsInRaid and Safe.Value(Safe.Call(IsInRaid)) == true
        local count = (GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers))) or 0
        for i = 1, count do
            local token = isRaid and ("raid" .. i) or ("party" .. i)
            if UnitMatchesEntry(token, tempEntry) then
                liveUnit = token
                break
            end
        end
    end

    if liveUnit then
        local trackedEntry = self:InspectUnit(liveUnit, liveUnit:match("^nameplate") ~= nil)
        if trackedEntry and ns.SpotterHUD then
            ns.SpotterHUD.focusedKey = trackedEntry.key
            if ns.SpotterHUD.Show then
                ns.SpotterHUD:Show(true)
            end
        end
        return trackedEntry
    end

    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    local isMyGuildMember, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote = LookupKnownPlayerGuildOrMembership(firstName, displayName, cleanGuid)
    local gName = (rawGuild and rawGuild ~= "") and rawGuild or knownGuild
    local rawStance, dipEntry = self:ClassifyGuild(gName)
    local stance, resolvedReason
    stance, resolvedReason, gName = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, watchNote, key, myNormGuild, myGuildName, gName)
    stance = stance or forcedStance or "WATCHLIST"

    local now = time()
    local entry = self.entries[key] or { key = key, firstSeen = now }
    self.entries[key] = entry
    entry.displayName = displayName
    entry.firstName = firstName
    entry.unitName = entry.unitName or firstName
    entry.targetName = targetMacroName
    entry.guild = gName or entry.guild
    entry.stance = stance
    entry.reason = resolvedReason or L["Target Radar"]
    entry.classFile = Safe.String(classFile) or knownClass or entry.classFile
    entry.level = (tonumber(level) and tonumber(level) > 0) and tonumber(level) or knownLevel or entry.level
    entry.guid = cleanGuid or entry.guid
    entry.lastSeen = now
    entry.lastDistText = entry.lastDistText or L["Nearby"]
    entry._manualTracked = true
    entry._alertEvaluated = true

    RecomputeOnScreenFlags()
    if ns.SpotterHUD then
        ns.SpotterHUD.focusedKey = key
        if ns.SpotterHUD.Show then
            ns.SpotterHUD:Show(true)
        end
    end
    ns:Emit("SPOTTER_UPDATED")
    return entry
end

function Spotter:GetActiveTargets(filterStance)
    local out = {}
    local f = filterStance and filterStance:upper() or "ALL"
    for _, entry in pairs(self.entries) do
        if f == "ALL" or entry.stance == f then
            table.insert(out, entry)
        end
    end
    table.sort(out, function(a, b)
        if a.onScreen ~= b.onScreen then return a.onScreen end
        local pa = STANCE_PRIORITY[a.stance] or 9
        local pb = STANCE_PRIORITY[b.stance] or 9
        if pa ~= pb then return pa < pb end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return out
end

function Spotter:Init()
    self.lastScopeToken = ns.Clan and ns.Clan.GetActiveScopeToken and ns.Clan:GetActiveScopeToken() or ""

    local function ScanActiveNameplates()
        self:RefreshVisibleNameplates()
    end
    self.ScanActiveNameplates = ScanActiveNameplates

    CacheRangeCheckItems()

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        CacheRangeCheckItems()
        self:OnGuildChanged()
        ScanActiveNameplates()
    end)

    ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, _, unit)
        if not unit or unit == "player" then
            self:OnGuildChanged()
        elseif unit:match("^nameplate") then
            self:InspectUnit(unit, true)
        else
            self:InspectUnit(unit, false)
        end
    end)

    ns.RegisterEvent(self, "GUILD_ROSTER_UPDATE", function()
        if Compat.SyncRosterForeverNames then
            Compat.SyncRosterForeverNames()
        end
        self:ReclassifyActiveEntries()
        ScanActiveNameplates()
    end)

    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        self:InspectUnit(unit, true)
    end)

    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", function(_, _, unit)
        if unit and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            HidePlateBadgeForUnit(unit)
            RecomputeOnScreenFlags()
            if not self:CleanupAbsentTargets(false) then
                ns:Emit("SPOTTER_UPDATED")
            end
        elseif unit then
            HidePlateBadgeForUnit(unit)
        end
    end)

    ns.RegisterEvent(self, "UNIT_NAME_UPDATE", function(_, _, unit)
        if unit and unit:match("^nameplate") then
            self:InspectUnit(unit, true)
        elseif unit then
            self:InspectUnit(unit, false)
        end
    end)

    ns.RegisterEvent(self, "UNIT_FACTION", function(_, _, unit)
        if unit and unit:match("^nameplate") then
            self:InspectUnit(unit, true)
        elseif unit then
            self:InspectUnit(unit, false)
        end
    end)

    ns.RegisterEvent(self, "UNIT_TARGET", function(_, _, unit)
        if not unit then return end
        if unit == "player" then
            self:InspectUnit("target", false)
        else
            local subTarget = unit .. "target"
            if Safe.Value(Safe.Call(UnitExists, subTarget)) == true then
                self:InspectUnit(subTarget, false)
            end
        end
    end)

    ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function()
        self:InspectUnit("mouseover", false)
    end)

    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
        self:InspectUnit("target", false)
        self:CleanupAbsentTargets(false)
    end)

    ns.RegisterEvent(self, "PLAYER_FOCUS_CHANGED", function()
        self:InspectUnit("focus", false)
        self:CleanupAbsentTargets(false)
    end)

    ns.RegisterEvent(self, "PLAYER_SOFT_FRIEND_CHANGED", function()
        self:InspectUnit("softfriend", false)
    end)

    ns.RegisterEvent(self, "PLAYER_SOFT_ENEMY_CHANGED", function()
        self:InspectUnit("softenemy", false)
    end)

    ns.RegisterEvent(self, "PLAYER_SOFT_INTERACT_CHANGED", function()
        self:InspectUnit("softinteract", false)
    end)

    for _, grpEv in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
        ns.RegisterEvent(self, grpEv, function()
            self:RefreshVisibleNameplates()
        end)
    end

    for _, chatEv in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
        ns.RegisterEvent(self, chatEv, function(_, _, _, sender, ...)
            local guid = select(10, ...)
            self:InspectChatSighting(sender, guid)
        end)
    end

    ns:On("CLAN_DIPLOMACY_UPDATED", function()
        self:ReclassifyActiveEntries()
    end)

    ns:On("CLAN_UPDATED", function()
        self:OnGuildChanged()
    end)

    ns:On("SOCIAL_UPDATED", function()
        self:ReclassifyActiveEntries()
    end)

    ns:On("WATCHLIST_UPDATED", function()
        self:ReclassifyActiveEntries()
    end)

    ns:On("SETTINGS_UPDATED", function()
        self:ReclassifyActiveEntries()
    end)

    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed)
        self._pruneElapsed = (self._pruneElapsed or 0) + elapsed
        self._platePollElapsed = (self._platePollElapsed or 0) + elapsed
        if self._platePollElapsed >= 0.25 then
            self._platePollElapsed = 0
            ScanActiveNameplates()
        end
        if self._pruneElapsed >= PRUNE_INTERVAL then
            self._pruneElapsed = 0
            self:Prune(false)
        end
    end)
    self._ticker = ticker
end

ns.Spotter = Spotter
table.insert(ns.modules, Spotter)
