local _, ns = ...

local Compat = ns.Compat
local Safe = ns.Safe
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local Spotter = {
    name = "Spotter",
    entries = {},        -- [key] = entry
    entryByGuid = {},    -- [guid] = entry
    visibleUnits = {},   -- [unitToken] = key
    alertCooldowns = {}, -- [key] = timestamp
    dismissedUntil = {}, -- [key] = timestamp when [X] dismiss expires
    toastExpiredUntil = {}, -- [key] = timestamp when auto-expired toast cooldown ends
    manualTracked = {},  -- [key] = true when user requested Track on Radar
    manualTrackedStance = {}, -- [key] = fallback stance for manual tracking
    lastAlert = nil,
    lastScopeToken = nil,
    _lastActiveZone = nil,
    plateBadges = setmetatable({}, { __mode = "k" }), -- [plateFrame] = badgeFrame
    targetArrowFrame = nil,
    _pruneTimerActive = false,
    _batchFlushQueued = false,
    _batchEmitDirty = false,
    _eventsRegistered = false,
    _hooksInitialized = false,
}

local LIVE_TOKEN_LIST = {
    "target", "focus", "mouseover",
    "targettarget", "focustarget", "mouseovertarget",
    "softfriend", "softenemy", "softinteract",
}

local socialByGuid = {}
local socialByKey = {}
local socialCacheDirty = true

local posGuidSet = {}
local posKeySet = {}
local posFirstSet = {}
local posAvoidKeys = {}
local posAvoidFirsts = {}
local posIgnoreKeys = {}
local posIgnoreFirsts = {}
local posGuildRawCache = {}
local posGuildRawPrev = {}
local posGuildRawCacheCount = 0
local coldGuildRetryUsed = {}
local guildPosGuidSet = {}
local guildPosKeySet = {}
local guildPosFirstSet = {}
local guildPosIndexDirty = true
local guildPosLastAllowSame = false
local posIndexDirty = true
local hasAnyPosPeople = false
local hasAnyPosGuilds = false

local bystanderCooldown = {}
local bystanderPrev = {}
local bystanderCooldownCount = 0
local chatCooldown = {}
local chatPrev = {}
local chatCooldownCount = 0
local activePlatesByUnit = {}
local activePlateUnitByGuid = {}
local activePlateCount = 0
local pendingPlateUnits = {}
local groupMemberByGuid = {}
local groupMemberByKey = {}
local groupCacheDirty = true

local onScreenCounts = {}
local unknownRetryUnits = {}
local unknownRetryCount = 0
local inspectQUnit = {}
local inspectQPlate = {}
local inspectQTicker = {}
local inspectQueuedSet = {}
local inspectQueueHead = 1
local inspectQueueTail = 0
local inspectQueueTimerActive = false
local sliceInspectCount = 0
local sliceWindowStart = 0
local lastMouseoverGuid = nil
local lastMouseoverAt = 0

local sortedTargetsCache = {}
local sortedTargetsDirty = true
local countsSynced = false
local cachedCountEnemy = 0
local cachedCountAlly = 0
local cachedCountSame = 0
local cachedCountWatchlist = 0
local cachedCountFriend = 0
local cachedCountBlocked = 0
local cachedCountTotal = 0
local cachedCountOnScreen = 0

local function MarkTargetsDirty()
    sortedTargetsDirty = true
    countsSynced = false
end

local inInstanceCached = nil

local ITEM_IN_RANGE_FN = (C_Item and C_Item.IsItemInRange) or IsItemInRange
local ITEM_REQUEST_FN = C_Item and C_Item.RequestLoadItemDataByID
local requestedRangeItems = {}

local function EnsureRangeItemRequested(itemId)
    if ITEM_REQUEST_FN and itemId and not requestedRangeItems[itemId] then
        requestedRangeItems[itemId] = true
        pcall(ITEM_REQUEST_FN, itemId)
    end
end

local function GetPosGuildRawCache(rawGuild)
    if not rawGuild then return nil end
    local v = posGuildRawCache[rawGuild]
    if v ~= nil then return v end
    return posGuildRawPrev[rawGuild]
end

local function RecordPosGuildRawCache(rawGuild, value)
    if not rawGuild then return end
    if posGuildRawCache[rawGuild] == nil then
        if posGuildRawCacheCount >= 200 then
            wipe(posGuildRawPrev)
            posGuildRawPrev, posGuildRawCache = posGuildRawCache, posGuildRawPrev
            posGuildRawCacheCount = 0
        end
        posGuildRawCacheCount = posGuildRawCacheCount + 1
    end
    posGuildRawCache[rawGuild] = value
end

local function InvalidateBystanderCache()
    wipe(bystanderCooldown)
    wipe(bystanderPrev)
    bystanderCooldownCount = 0
    wipe(coldGuildRetryUsed)
    wipe(posGuildRawCache)
    wipe(posGuildRawPrev)
    posGuildRawCacheCount = 0
end

local function MarkPositiveIndexDirty()
    posIndexDirty = true
    socialCacheDirty = true
    wipe(posGuildRawCache)
    wipe(posGuildRawPrev)
    posGuildRawCacheCount = 0
end

local function MarkGuildPositiveDirty()
    guildPosIndexDirty = true
    MarkPositiveIndexDirty()
end

local function GetBystanderCooldown(guid)
    if not guid then return nil end
    return bystanderCooldown[guid] or bystanderPrev[guid]
end

local function ClearBystanderCooldown(guid)
    if not guid then return end
    bystanderCooldown[guid] = nil
    bystanderPrev[guid] = nil
end

local function RecordBystanderCooldown(guid, expiresAt)
    if not guid then return end
    if bystanderCooldown[guid] == nil then
        if bystanderCooldownCount >= 200 then
            wipe(bystanderPrev)
            bystanderPrev, bystanderCooldown = bystanderCooldown, bystanderPrev
            bystanderCooldownCount = 0
            wipe(coldGuildRetryUsed)
        end
        bystanderCooldownCount = bystanderCooldownCount + 1
    end
    bystanderCooldown[guid] = expiresAt
end

local BYSTANDER_COOLDOWN_SECONDS = 25.0
local BYSTANDER_CROWD_COOLDOWN_SECONDS = 60.0

local function IsCrowdMode()
    if activePlateCount >= 18 then
        return true
    end
    if IsInRaid and Safe.Value(Safe.Call(IsInRaid)) == true then
        return true
    end
    return false
end

local function GetBystanderCooldownSeconds()
    return IsCrowdMode() and BYSTANDER_CROWD_COOLDOWN_SECONDS or BYSTANDER_COOLDOWN_SECONDS
end

local function RecordGateMissCooldown(guid, confirmedNoMatch, nowClock)
    if not guid then return end
    local cdSec
    if confirmedNoMatch or coldGuildRetryUsed[guid] then
        cdSec = GetBystanderCooldownSeconds()
    else
        coldGuildRetryUsed[guid] = true
        cdSec = IsCrowdMode() and 8.0 or 4.0
    end
    RecordBystanderCooldown(guid, nowClock + cdSec)
end

local function GetChatCooldown(cacheKey)
    if not cacheKey then return nil end
    return chatCooldown[cacheKey] or chatPrev[cacheKey]
end

local function RecordChatCooldown(cacheKey, expiresAt)
    if not cacheKey then return end
    if chatCooldown[cacheKey] == nil then
        if chatCooldownCount >= 150 then
            wipe(chatPrev)
            chatPrev, chatCooldown = chatCooldown, chatPrev
            chatCooldownCount = 0
        end
        chatCooldownCount = chatCooldownCount + 1
    end
    chatCooldown[cacheKey] = expiresAt
end

local function IsInInstanceFast()
    if inInstanceCached ~= nil then
        return inInstanceCached
    end
    if IsInInstance then
        local ok, inInst = pcall(IsInInstance)
        if ok then
            inInstanceCached = (Safe.Value(inInst) == true)
            return inInstanceCached
        end
    end
    return false
end

local function IsGroupUnitToken(unit)
    if not unit then return false end
    return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local MAX_TARGETS = 24
local DEFAULT_TOAST_DURATION_SECONDS = 10
local DISMISS_COOLDOWN_SECONDS = 180
local PRUNE_INTERVAL = 1.0
local CHAT_SIGHTING_COOLDOWN = 12.0
local INSPECT_BATCH_LIMIT = 6
local INSPECT_SLICE_INTERVAL = 0.15
local ENEMY_ALERT_COOLDOWN = 120
local FRIENDLY_ALERT_COOLDOWN = 180
local TARGET_ARROW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\arrow"
local TARGET_GLOW_TEX = "Interface\\AddOns\\SocialCentral\\Media\\toast-glow"

local TELEPORT_SPELL_IDS = {
    [8690] = true,  -- Hearthstone
    [556] = true,   -- Astral Recall
    [3561] = true,  -- Teleport: Stormwind
    [3562] = true,  -- Teleport: Ironforge
    [3563] = true,  -- Teleport: Undercity
    [3565] = true,  -- Teleport: Darnassus
    [3566] = true,  -- Teleport: Thunder Bluff
    [3567] = true,  -- Teleport: Orgrimmar
    [18960] = true, -- Teleport: Moonglade
    [23453] = true, -- Ultrasafe Transporter: Gadgetzan
    [23442] = true, -- Dimensional Ripper - Everlook
}

local function GetSpotterToastDuration()
    local v = ns.db and ns.db.settings and tonumber(ns.db.settings.spotterToastDuration)
    if v and v >= 3 then
        return math.min(120, math.floor(v + 0.5))
    end
    return DEFAULT_TOAST_DURATION_SECONDS
end

local ITEM_RANGES = {
    { range = 8, item = 8149 },                     -- Voodoo Charm
    { range = 13, item = 17626 },                   -- Frostwolf Muzzle
    { range = 18, item = 6450, friendOnly = true }, -- Silk Bandage (friendly-only check)
    { range = 23, item = 17757 },                   -- Amulet of Spirits
    { range = 28, item = 13289 },                   -- Egan's Blaster
    { range = 33, item = 17202 },                   -- Snowball
    { range = 38, item = 18904 },                   -- Zorbin's Ultra-Shrinker
}

local STANCE_PRIORITY = {
    ENEMY = 1,
    BLOCKED = 2,
    WATCHLIST = 3,
    FRIEND = 4,
    ALLY = 5,
    SAME = 6,
}

local STANCE_COLORS = {
    ENEMY     = { r = 0.96, g = 0.28, b = 0.28, hex = "|cfff54747" },
    BLOCKED   = { r = 0.88, g = 0.22, b = 0.56, hex = "|cffe0388f" },
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

local function ExtractFastFirstLower(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local s = raw:match("^%s*(.-)%s*$")
    if not s or s == "" then return nil end
    local dash = s:find("-", 1, true)
    if dash then
        s = s:sub(1, dash - 1)
    end
    local sp = s:find(" ", 1, true)
    if sp then
        s = s:sub(1, sp - 1)
    end
    if s == "" then return nil end
    return s:lower()
end

local function AddPositiveCandidate(rawNameOrKey, guid, extraKeyMap, extraFirstMap, includeInGate, knownLookupKey)
    local addGate = (includeInGate ~= false)
    local cleanGuid = Safe.String(guid)
    if cleanGuid and cleanGuid ~= "" and addGate then
        posGuidSet[cleanGuid] = true
        hasAnyPosPeople = true
    end
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then
        return
    end
    local lKey, pFirst
    if knownLookupKey and knownLookupKey ~= "" then
        lKey = knownLookupKey
    elseif Compat.ParseCharacterFields then
        lKey, pFirst = Compat.ParseCharacterFields(rawNameOrKey)
    else
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(rawNameOrKey)
        lKey = parsed and parsed.lookupKey
        pFirst = parsed and parsed.firstName
    end
    lKey = (lKey and lKey ~= "" and lKey) or NormalizeKeyPart(rawNameOrKey)
    local fLower = (pFirst and pFirst ~= "" and pFirst:lower()) or ExtractFastFirstLower(rawNameOrKey)
    if lKey and lKey ~= "" then
        if extraKeyMap then extraKeyMap[lKey] = true end
        if addGate then
            posKeySet[lKey] = true
            hasAnyPosPeople = true
        end
    end
    if fLower and fLower ~= "" then
        if extraFirstMap then extraFirstMap[fLower] = true end
        if addGate then
            posFirstSet[fLower] = true
            hasAnyPosPeople = true
        end
    end
end

local function RebuildPositiveIndex()
    wipe(socialByGuid)
    wipe(socialByKey)
    wipe(posGuidSet)
    wipe(posKeySet)
    wipe(posFirstSet)
    wipe(posAvoidKeys)
    wipe(posAvoidFirsts)
    wipe(posIgnoreKeys)
    wipe(posIgnoreFirsts)
    wipe(posGuildRawCache)
    wipe(posGuildRawPrev)
    posGuildRawCacheCount = 0
    socialCacheDirty = false
    posIndexDirty = false
    hasAnyPosPeople = false
    hasAnyPosGuilds = false

    local s = ns.db and ns.db.settings
    local allowFriends = (not s) or s.spotterNotifyFriends ~= false
    local allowWatch = (not s) or s.spotterNotifyWatchlist ~= false
    local allowBlocked = (not s) or s.spotterNotifyBlocked ~= false
    local allowEnemy = (not s) or s.spotterNotifyEnemy ~= false
    local allowAlly = (not s) or s.spotterNotifyAlly ~= false
    local allowSame = (s ~= nil and s.spotterNotifySameClan == true)

    local store = ns.Store
    local hasStoreIndex = store and type(store.socialByGuid) == "table" and type(store.socialByLookup) == "table"
    if store and type(store.social) == "table" and (allowFriends or not hasStoreIndex) then
        for _, row in pairs(store.social) do
            if type(row) == "table" then
                if not hasStoreIndex then
                    if row.guid and row.guid ~= "" then
                        socialByGuid[row.guid] = row
                    elseif row.lookupKey and row.lookupKey ~= "" and not socialByKey[row.lookupKey] then
                        socialByKey[row.lookupKey] = row
                    end
                end
                local src = row.sources
                if src and allowFriends and (src.friend == true or src.bnet == true) then
                    AddPositiveCandidate(row.fullName or row.name or row.lookupKey, row.guid, nil, nil, true, row.lookupKey)
                end
            end
        end
    end

    if allowFriends then
        if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
            local nf = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
            for i = 1, nf do
                local info = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
                if type(info) == "table" then
                    AddPositiveCandidate(Safe.String(info.name), Safe.String(info.guid))
                end
            end
        elseif GetNumFriends and GetFriendInfo then
            local nf = Safe.Number(Safe.Call(GetNumFriends)) or 0
            for i = 1, nf do
                local name = Safe.String(Safe.Call(GetFriendInfo, i))
                if name and name ~= "" then
                    AddPositiveCandidate(name, nil)
                end
            end
        end

        if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
            local nb = Safe.Number(Safe.Call(BNGetNumFriends)) or 0
            for i = 1, nb do
                local acct = Safe.Call(C_BattleNet.GetFriendAccountInfo, i)
                local ga = type(acct) == "table" and acct.gameAccountInfo or nil
                if type(ga) == "table" and Safe.Value(ga.isOnline) == true then
                    local client = Safe.String(ga.clientProgram)
                    if not client or client == (BNET_CLIENT_WOW or "WoW") then
                        local charName = Safe.String(ga.characterName)
                        if charName and charName ~= "" then
                            AddPositiveCandidate(charName, Safe.String(ga.playerGuid))
                        end
                    end
                end
            end
        end
    end

    if allowWatch and store and store.GetWatchlistTable then
        local wl = store:GetWatchlistTable()
        if type(wl) == "table" then
            for k, wRow in pairs(wl) do
                if type(wRow) == "table" then
                    AddPositiveCandidate(wRow.displayName or wRow.name or k, wRow.guid, nil, nil, true, k)
                else
                    AddPositiveCandidate(k, nil, nil, nil, true, k)
                end
            end
        end
    end

    if store and store.GetSocialMetaTable then
        local metaTbl = store:GetSocialMetaTable()
        if type(metaTbl) == "table" then
            for k, rec in pairs(metaTbl) do
                if type(rec) == "table" then
                    local isAvoid = (rec.flag == "AVOID")
                    if (not isAvoid) and (not rec.flag) and rec.mainName and rec.mainName ~= "" then
                        local mainKey
                        if Compat.ParseCharacterFields then
                            mainKey = Compat.ParseCharacterFields(rec.mainName)
                        end
                        if not mainKey or mainKey == "" then
                            mainKey = NormalizeKeyPart(rec.mainName)
                        end
                        local mainRec = mainKey and metaTbl[mainKey]
                        if type(mainRec) == "table" and mainRec.flag == "AVOID" then
                            isAvoid = true
                        end
                    end
                    if isAvoid then
                        AddPositiveCandidate(k, nil, posAvoidKeys, posAvoidFirsts, allowBlocked, k)
                    end
                end
            end
        end
    end

    local getNumIg = (C_FriendList and C_FriendList.GetNumIgnores) or GetNumIgnores
    local getIgnName = (C_FriendList and C_FriendList.GetIgnoreName) or GetIgnoreName
    if getNumIg and getIgnName then
        local ni = Safe.Number(Safe.Call(getNumIg)) or 0
        for i = 1, ni do
            local ignName = Safe.String(Safe.Call(getIgnName, i))
            if ignName and ignName ~= "" then
                AddPositiveCandidate(ignName, nil, posIgnoreKeys, posIgnoreFirsts, allowBlocked)
            end
        end
    end

    if store and store.GetAccountIgnoresList then
        for _, ign in ipairs(store:GetAccountIgnoresList()) do
            if ign and ign.lookupKey and ign.lookupKey ~= "" then
                AddPositiveCandidate(ign.name or ign.lookupKey, nil, posIgnoreKeys, posIgnoreFirsts, allowBlocked, ign.lookupKey)
            end
        end
    end

    if allowSame and Safe.Value(Safe.Call(IsInGuild)) == true and GetNumGuildMembers and GetGuildRosterInfo then
        if guildPosIndexDirty or not guildPosLastAllowSame then
            wipe(guildPosGuidSet)
            wipe(guildPosKeySet)
            wipe(guildPosFirstSet)
            local ng = math.min(1000, Safe.Number(Safe.Call(GetNumGuildMembers)) or 0)
            for i = 1, ng do
                local okG, gFullName, _, _, _, _, _, _, _, gOnline, _, _, _, _, _, _, _, gGuid = pcall(GetGuildRosterInfo, i)
                if okG and Safe.Value(gOnline) == true then
                    local cleanGName = Safe.String(gFullName)
                    local cleanGGuid = Safe.String(gGuid)
                    if cleanGGuid and cleanGGuid ~= "" then
                        guildPosGuidSet[cleanGGuid] = true
                    end
                    if cleanGName and cleanGName ~= "" then
                        local lKey, pFirst
                        if Compat.ParseCharacterFields then
                            lKey, pFirst = Compat.ParseCharacterFields(cleanGName)
                        end
                        lKey = (lKey and lKey ~= "" and lKey) or NormalizeKeyPart(cleanGName)
                        local fLower = (pFirst and pFirst ~= "" and pFirst:lower()) or ExtractFastFirstLower(cleanGName)
                        if lKey and lKey ~= "" then guildPosKeySet[lKey] = true end
                        if fLower and fLower ~= "" then guildPosFirstSet[fLower] = true end
                    end
                end
            end
            if ng > 0 then
                guildPosIndexDirty = false
            end
            guildPosLastAllowSame = true
        end
        for gGuid in pairs(guildPosGuidSet) do
            posGuidSet[gGuid] = true
            hasAnyPosPeople = true
        end
        for lKey in pairs(guildPosKeySet) do
            posKeySet[lKey] = true
            hasAnyPosPeople = true
        end
        for fLower in pairs(guildPosFirstSet) do
            posFirstSet[fLower] = true
            hasAnyPosPeople = true
        end
    elseif not allowSame then
        guildPosLastAllowSame = false
    end

    if Spotter.manualTracked then
        for mKey, flagged in pairs(Spotter.manualTracked) do
            if flagged then
                local mEntry = Spotter.entries and Spotter.entries[mKey]
                AddPositiveCandidate(mKey, mEntry and mEntry.guid, nil, nil, true)
            end
        end
    end

    local hasDipGuilds = false
    if (allowEnemy or allowAlly) and store and store.GetClanScopeData then
        local bucket = store:GetClanScopeData()
        local dipGuilds = bucket and bucket.diplomacy and bucket.diplomacy.guilds
        if type(dipGuilds) == "table" then
            for _, dRec in pairs(dipGuilds) do
                if type(dRec) == "table" and ((allowEnemy and dRec.stance == "ENEMY") or (allowAlly and dRec.stance == "ALLY")) then
                    hasDipGuilds = true
                    break
                end
            end
        end
    end
    hasAnyPosGuilds = allowSame or hasDipGuilds
end

local function RebuildSocialLookupCache()
    RebuildPositiveIndex()
end

local function SanitizeMacroTargetName(rawName, rawRealm)
    local clean = Safe.String(rawName)
    if not clean or clean == "" then return nil end
    clean = clean:gsub("[%c%|%/%\\%[%]%;]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then return nil end
    if Compat.FormatForeverTarget then
        clean = Compat.FormatForeverTarget(clean) or clean
    end

    local realm = Safe.String(rawRealm)
    local hasSurname = clean:find("[%s%-]") ~= nil
    local onForeverPool = Compat.Realm and Compat.Plain and (Compat.Plain(Compat.Realm()):match("^camwow") ~= nil)
    if (not hasSurname) and (not onForeverPool) and realm and realm ~= "" and not Compat.IsForeverShardLabel(realm) then
        local cleanRealm = realm:gsub("[%c%|%/%\\%[%]%;%s]", "")
        if cleanRealm ~= "" then
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

local function GetUnitSafeGuild(unit, guidHint, cacheOnlyTooltip)
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
        local tipGuild = Compat.ReadUnitTooltipGuild(unit, guidHint, cacheOnlyTooltip)
        if tipGuild and tipGuild ~= "" then
            return tipGuild, nil, nil
        end
    end
    return nil, nil, nil
end

local function GetPlayerNormalizedGuild()
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true
    if not inGuild then
        Spotter._cachedPlayerGuild = nil
        Spotter._cachedPlayerGuildNorm = nil
        return nil, nil
    end
    if Spotter._cachedPlayerGuildNorm and Spotter._cachedPlayerGuild then
        return Spotter._cachedPlayerGuildNorm, Spotter._cachedPlayerGuild
    end
    local gName = GetUnitSafeGuild("player")
    if not gName or gName == "" then
        local info = ns.Store and ns.Store.guildInfo
        if info and info.inGuild and info.name and info.name ~= "" then
            gName = info.name
        end
    end
    if (not gName or gName == "") and ns.db and ns.db.alts then
        local altRec = (ns.Store and ns.Store.GetCurrentAltRecord and ns.Store:GetCurrentAltRecord())
            or (Compat.CharacterKey and ns.db.alts[Compat.CharacterKey()])
        if altRec and altRec.guild and altRec.guild ~= "" then
            gName = altRec.guild
        end
    end
    if gName and gName ~= "" then
        local norm = NormalizeKeyPart(gName)
        Spotter._cachedPlayerGuild = gName
        Spotter._cachedPlayerGuildNorm = norm
        return norm, gName
    end
    if Spotter._cachedPlayerGuild and Spotter._cachedPlayerGuild ~= "" then
        local norm = Spotter._cachedPlayerGuildNorm or NormalizeKeyPart(Spotter._cachedPlayerGuild)
        Spotter._cachedPlayerGuildNorm = norm
        return norm, Spotter._cachedPlayerGuild
    end
    return nil, nil
end

local function LookupKnownPlayerGuildOrMembership(firstName, fullName, guid)
    local cleanGuid = Safe.String(guid)
    local firstLower = (firstName and firstName ~= "") and firstName:lower() or nil
    local lookupKey, parsedSurname
    if Compat.ParseCharacterFields then
        local lk, _, _, pSur = Compat.ParseCharacterFields(fullName or firstName)
        lookupKey = lk
        parsedSurname = pSur
    elseif Compat.ParseCharacterName then
        local parsed = Compat.ParseCharacterName(fullName or firstName)
        lookupKey = parsed and parsed.lookupKey
        parsedSurname = parsed and parsed.surname
    end
    lookupKey = lookupKey or firstLower
    local hasSurname = parsedSurname ~= nil

    if posIndexDirty or socialCacheDirty then
        RebuildPositiveIndex()
    end

    local isMyGuild = false
    local isWatched = false
    local isFriend = false
    local isBlocked = false
    local knownGuild, knownClass, knownLevel, watchNote

    if Compat.IsGuildMember and Compat.IsGuildMember(firstName, cleanGuid, fullName) then
        isMyGuild = true
    end

    local store = ns.Store
    local sByGuid = (store and type(store.socialByGuid) == "table" and store.socialByGuid) or socialByGuid
    local sByKey = (store and type(store.socialByLookup) == "table" and store.socialByLookup) or socialByKey
    local sRow = (cleanGuid and sByGuid[cleanGuid])
        or ((not cleanGuid) and lookupKey and sByKey[lookupKey])
        or (not cleanGuid and firstLower and sByKey[firstLower])
    if sRow then
        if sRow.sources and sRow.sources.guild == true then
            isMyGuild = true
        end
        if sRow.sources and (sRow.sources.friend == true or sRow.sources.bnet == true) then
            isFriend = true
        end
        if sRow.guild and sRow.guild ~= "" then
            knownGuild = knownGuild or sRow.guild
        end
        knownClass = knownClass or sRow.classFile
        knownLevel = knownLevel or sRow.level
    end

    if not isFriend and cleanGuid and C_FriendList and C_FriendList.IsFriend then
        local okF, resF = pcall(C_FriendList.IsFriend, cleanGuid)
        if okF and Safe.Value(resF) == true then
            isFriend = true
        end
    end

    if not isMyGuild and not cleanGuid and lookupKey and Safe.Value(IsInGuild and IsInGuild()) == true then
        if ns.Clan and ((ns.Clan.HasGuildChatLFG and ns.Clan:HasGuildChatLFG(lookupKey)) or (ns.Clan.guildChatLFG and ns.Clan.guildChatLFG[lookupKey])) then
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

    if (lookupKey and posAvoidKeys[lookupKey]) or ((not hasSurname) and firstLower and posAvoidFirsts[firstLower]) then
        isBlocked = true
    end
    if store and store.GetResolvedSocialMeta and lookupKey then
        local meta = store:GetResolvedSocialMeta(lookupKey)
        if meta and meta.flag == "AVOID" then
            isBlocked = true
            if (not watchNote or watchNote == "") and meta.note and meta.note ~= "" then
                watchNote = meta.note
            end
        end
    end
    if not isBlocked then
        if (lookupKey and posIgnoreKeys[lookupKey]) or ((not hasSurname) and firstLower and posIgnoreFirsts[firstLower]) then
            isBlocked = true
        else
            local isIgnoredFn = (C_FriendList and C_FriendList.IsIgnored) or IsIgnored
            if isIgnoredFn then
                local checkTarget = fullName or firstName
                if checkTarget and checkTarget ~= "" then
                    local okIgn, ignoredRes = pcall(isIgnoredFn, checkTarget)
                    if okIgn and Safe.Value(ignoredRes) == true then
                        isBlocked = true
                    end
                end
            end
        end
    end

    return isMyGuild, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote, isBlocked
end

local function RebuildGroupMemberCache()
    wipe(groupMemberByGuid)
    wipe(groupMemberByKey)
    groupCacheDirty = false
    if not (IsInGroup and Safe.Value(Safe.Call(IsInGroup)) == true) then
        return
    end
    local isRaid = IsInRaid and Safe.Value(Safe.Call(IsInRaid)) == true
    local count = (GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers))) or 0
    local limit = isRaid and math.min(40, count) or math.min(4, count)
    local prefix = isRaid and "raid" or "party"
    for i = 1, limit do
        local token = prefix .. i
        if Safe.Value(Safe.Call(UnitExists, token)) == true then
            local mGuid = Safe.String(Safe.Call(UnitGUID, token))
            if mGuid and mGuid ~= "" then
                groupMemberByGuid[mGuid] = token
            end
            local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(token, mGuid, nil, true)
            local lKey = resolved and resolved.lookupKey
            if (not lKey or lKey == "") and resolved and resolved.fullName then
                if Compat.ParseCharacterFields then
                    lKey = Compat.ParseCharacterFields(resolved.fullName)
                elseif Compat.ParseCharacterName then
                    local parsed = Compat.ParseCharacterName(resolved.fullName)
                    lKey = parsed and parsed.lookupKey
                end
            end
            if lKey and lKey ~= "" then
                groupMemberByKey[lKey] = token
            end
        end
    end
end

local function GetCachedGroupUnitToken(key, guid)
    if groupCacheDirty then
        RebuildGroupMemberCache()
    end
    if guid and groupMemberByGuid[guid] then
        return groupMemberByGuid[guid]
    end
    if key and groupMemberByKey[key] then
        return groupMemberByKey[key]
    end
    return nil
end

local function IsPlayerInMyGroup(unit, key, guid)
    if unit then
        if Safe.Value(Safe.Call(UnitInParty, unit)) == true or Safe.Value(Safe.Call(UnitInRaid, unit)) == true then
            return true
        end
    end
    return GetCachedGroupUnitToken(key, guid) ~= nil
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
    local clanModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("clan")
    if stance == "ENEMY" then return clanModOn and s.spotterNotifyEnemy ~= false end
    if stance == "BLOCKED" then return s.spotterNotifyBlocked ~= false end
    if stance == "WATCHLIST" then return (not Compat.IsModuleEnabled or Compat.IsModuleEnabled("watchlist")) and s.spotterNotifyWatchlist ~= false end
    if stance == "FRIEND" then return s.spotterNotifyFriends ~= false end
    if stance == "ALLY" then return clanModOn and s.spotterNotifyAlly ~= false end
    if stance == "SAME" then return clanModOn and s.spotterNotifySameClan == true end
    return false
end

local function IsUnitOppositeOrHostile(unit, knownFaction)
    local myFac = Compat.PlayerFaction and Compat.PlayerFaction()
    local uFac = knownFaction and Compat.NormalizeFaction and Compat.NormalizeFaction(knownFaction) or nil
    if unit and Safe.Value(Safe.Call(UnitExists, unit)) == true then
        if UnitFactionGroup then
            local engFac, rawFac = Safe.Call(UnitFactionGroup, unit)
            local cleanFac = Safe.String(engFac) or Safe.String(rawFac)
            if cleanFac and cleanFac ~= "" then
                uFac = (Compat.NormalizeFaction and Compat.NormalizeFaction(cleanFac)) or cleanFac
            end
        end
        if (not uFac or uFac == "") and UnitRace and Compat.FactionFromRace then
            local locRace, engRace = Safe.Call(UnitRace, unit)
            uFac = Compat.FactionFromRace(Safe.String(engRace) or Safe.String(locRace))
        end
        if myFac and myFac ~= "" and uFac and uFac ~= "" and uFac ~= myFac then
            return true, uFac
        end
        local isFriend = UnitIsFriend and (Safe.Value(Safe.Call(UnitIsFriend, "player", unit)) == true)
        local isEnemy = UnitIsEnemy and (Safe.Value(Safe.Call(UnitIsEnemy, "player", unit)) == true)
        local reaction = UnitReaction and Safe.Number(Safe.Call(UnitReaction, unit, "player"))
        if (not isFriend) and (isEnemy or (reaction and reaction <= 3)) then
            return true, uFac
        end
    elseif myFac and myFac ~= "" and uFac and uFac ~= "" and uFac ~= myFac then
        return true, uFac
    end
    return false, uFac
end

local function ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, isBlocked, watchNote, key, myNormGuild, myGuildName, gName, isOppositeHostile)
    if rawStance == "ENEMY" and IsStanceAllowed("ENEMY", key) then
        local reason = (dipEntry and dipEntry.reason and dipEntry.reason ~= "") and dipEntry.reason or (watchNote or "")
        return "ENEMY", reason, gName
    end
    if isBlocked and IsStanceAllowed("BLOCKED", key) then
        local reason = (watchNote and watchNote ~= "") and watchNote or L["Blocked"]
        return "BLOCKED", reason, gName
    end
    if isWatched and IsStanceAllowed("WATCHLIST", key) then
        local reason = (watchNote and watchNote ~= "") and watchNote
            or ((dipEntry and dipEntry.reason) or L["Watchlist"])
        return "WATCHLIST", reason, gName
    end
    if (not isOppositeHostile) and isFriend and IsStanceAllowed("FRIEND", key) then
        local reason = (dipEntry and dipEntry.reason and dipEntry.reason ~= "") and dipEntry.reason or L["Friend"]
        return "FRIEND", reason, gName
    end
    if (not isOppositeHostile) and rawStance == "ALLY" and IsStanceAllowed("ALLY", key) then
        return "ALLY", (dipEntry and dipEntry.reason) or "", gName
    end
    local validSameGuild = (not isOppositeHostile) and (myNormGuild and myNormGuild ~= "") and (not gName or gName == "" or NormalizeKeyPart(gName) == myNormGuild)
    if (not isOppositeHostile) and isMyGuildMember and validSameGuild and IsStanceAllowed("SAME", key) then
        return "SAME", "", (myGuildName and myGuildName ~= "") and myGuildName or gName or L["Same Clan"]
    end
    if Spotter.manualTracked and key and Spotter.manualTracked[key] then
        local fallback = (Spotter.manualTrackedStance and Spotter.manualTrackedStance[key]) or "WATCHLIST"
        if isOppositeHostile and (fallback == "SAME" or fallback == "ALLY" or fallback == "FRIEND") then
            fallback = "WATCHLIST"
        end
        return fallback, (watchNote and watchNote ~= "" and watchNote) or L["Target Radar"], gName
    end
    return nil, "", gName
end

local function UpdateEntryZoneInfo(entry)
    if not entry then return end
    local zone = (Compat.CurrentZoneName and Compat.CurrentZoneName())
        or Safe.String(Safe.Call(GetRealZoneText))
        or Safe.String(Safe.Call(GetZoneText))
        or ""
    local subZone = Safe.String(Safe.Call(GetSubZoneText)) or ""
    if zone ~= "" then entry.zone = zone end
    if subZone ~= "" then entry.subZone = subZone end

    local shortZone = (subZone ~= "" and subZone ~= zone) and subZone or zone
    local fullZone = (subZone ~= "" and subZone ~= zone and zone ~= "") and (zone .. " - " .. subZone) or shortZone
    if shortZone ~= "" then
        entry.locationText = shortZone
    end
    if fullZone ~= "" then
        entry.fullLocationText = fullZone
    end
end

local function CacheRangeCheckItems()
    for _, spec in ipairs(ITEM_RANGES) do
        EnsureRangeItemRequested(spec.item)
    end
end

local function ProbeRangeItem(unit, idx, isFriend)
    local spec = ITEM_RANGES[idx]
    if not spec or not ITEM_IN_RANGE_FN then return nil end
    if spec.friendOnly and not isFriend then
        return nil
    end
    EnsureRangeItemRequested(spec.item)
    local okR, raw = pcall(ITEM_IN_RANGE_FN, spec.item, unit)
    local val = okR and Safe.Value(raw) or nil
    if val == true or val == 1 then
        return true
    elseif val == false or val == 0 then
        return false
    end
    return nil
end

local function SaveDistBracket(tGuid, isFriend, maxRange)
    if not tGuid or not maxRange then
        Spotter._lastDistBracket = nil
        return
    end
    local loIdx, hiIdx
    if maxRange == 13 then
        loIdx, hiIdx = 1, 2
    elseif maxRange == 18 and isFriend then
        loIdx, hiIdx = 2, 3
    elseif maxRange == 23 then
        loIdx, hiIdx = (isFriend and 3 or 2), 4
    elseif maxRange == 28 then
        loIdx, hiIdx = 4, 5
    elseif maxRange == 33 then
        loIdx, hiIdx = 5, 6
    elseif maxRange == 38 then
        loIdx, hiIdx = 6, 7
    else
        Spotter._lastDistBracket = nil
        return
    end
    Spotter._lastDistGuid = tGuid
    Spotter._lastDistBracket = {
        friend = isFriend,
        loIdx = loIdx,
        hiIdx = hiIdx,
        range = maxRange,
    }
end

local function MeasureUnitDistance(unit)
    if not unit or Safe.Value(Safe.Call(UnitExists, unit)) ~= true then
        Spotter._lastDistBracket = nil
        return nil, nil
    end

    local inCombat = (InCombatLockdown and InCombatLockdown()) or false
    local isFriend = Safe.Value(Safe.Call(UnitIsFriend, "player", unit)) == true
    local canCheckFriendly = not (inCombat and isFriend)
    local tGuid = (unit == "target") and Safe.String(Safe.Call(UnitGUID, unit)) or nil

    local d3, d2, d1
    if canCheckFriendly and CheckInteractDistance then
        d3 = Safe.Value(Safe.Call(CheckInteractDistance, unit, 3))
        if d3 == true then
            Spotter._lastDistBracket = nil
            if ITEM_IN_RANGE_FN and ITEM_RANGES[1] then
                if ProbeRangeItem(unit, 1, isFriend) == true then
                    return 8, "< 8m"
                end
            end
            return 9, L["< 10m"]
        end
        d2 = Safe.Value(Safe.Call(CheckInteractDistance, unit, 2))
        if d2 == true then
            Spotter._lastDistBracket = nil
            return 11, L["~11m"]
        end
        d1 = Safe.Value(Safe.Call(CheckInteractDistance, unit, 1))
    end

    local in43, in43Checked
    if UnitInRange then
        local r, checked = Safe.Call(UnitInRange, unit)
        in43 = (r == true)
        in43Checked = (checked == true)
    end

    local minRange = 0
    local maxRange = nil
    if canCheckFriendly and ITEM_IN_RANGE_FN then
        -- O(1) Continuity prediction: verify cached bracket in 1-2 probes before binary search.
        local br = (tGuid and tGuid == Spotter._lastDistGuid) and Spotter._lastDistBracket or nil
        if br and br.friend == isFriend and (not in43Checked or in43)
            and (d1 == nil or ((d1 == true) == (br.range <= 28))) then
            if ProbeRangeItem(unit, br.hiIdx, isFriend) == true then
                if br.hiIdx == 2 and d2 == false then
                    maxRange = br.range
                elseif br.loIdx and ProbeRangeItem(unit, br.loIdx, isFriend) == false then
                    minRange = ITEM_RANGES[br.loIdx].range
                    maxRange = br.range
                end
            end
        end

        -- Domain-partitioned binary probing: O(2-3) probes for both friend and enemy targets.
        if maxRange == nil and d1 == true then
            if isFriend then
                local r18 = ProbeRangeItem(unit, 3, true)
                if r18 == true then
                    local r13 = ProbeRangeItem(unit, 2, true)
                    if r13 == true then
                        maxRange = 13
                    else
                        if r13 == false then minRange = 13 end
                        maxRange = 18
                    end
                elseif r18 == false then
                    minRange = 18
                    local r23 = ProbeRangeItem(unit, 4, true)
                    if r23 == true then
                        maxRange = 23
                    else
                        if r23 == false then minRange = 23 end
                        local r28 = ProbeRangeItem(unit, 5, true)
                        if r28 == true then
                            maxRange = 28
                        elseif r28 == false then
                            minRange = 28
                        end
                    end
                else
                    for i = 2, 5 do
                        local res = ProbeRangeItem(unit, i, true)
                        if res == true then
                            maxRange = ITEM_RANGES[i].range
                            break
                        elseif res == false then
                            minRange = ITEM_RANGES[i].range
                        end
                    end
                end
            else
                local r23 = ProbeRangeItem(unit, 4, false)
                if r23 == true then
                    local r13 = ProbeRangeItem(unit, 2, false)
                    if r13 == true then
                        maxRange = 13
                    else
                        if r13 == false then minRange = 13 end
                        maxRange = 23
                    end
                elseif r23 == false then
                    minRange = 23
                    local r28 = ProbeRangeItem(unit, 5, false)
                    if r28 == true then
                        maxRange = 28
                    elseif r28 == false then
                        minRange = 28
                    end
                else
                    for i = 2, 5 do
                        local res = ProbeRangeItem(unit, i, false)
                        if res == true then
                            maxRange = ITEM_RANGES[i].range
                            break
                        elseif res == false then
                            minRange = ITEM_RANGES[i].range
                        end
                    end
                end
            end
        elseif maxRange == nil and d1 == false and in43Checked and in43 then
            minRange = 28
            local r33 = ProbeRangeItem(unit, 6, isFriend)
            if r33 == true then
                maxRange = 33
            else
                if r33 == false then minRange = 33 end
                local r38 = ProbeRangeItem(unit, 7, isFriend)
                if r38 == true then
                    maxRange = 38
                elseif r38 == false then
                    minRange = 38
                end
            end
        elseif maxRange == nil and d1 == false and in43Checked and not in43 then
            minRange = 43
        elseif maxRange == nil then
            local r28 = ProbeRangeItem(unit, 5, isFriend)
            if r28 == true then
                if d2 ~= false and ProbeRangeItem(unit, 1, isFriend) == true then
                    maxRange = 8
                elseif isFriend then
                    local r18 = ProbeRangeItem(unit, 3, true)
                    if r18 == true then
                        maxRange = (ProbeRangeItem(unit, 2, true) == true) and 13 or 18
                    elseif r18 == false then
                        minRange = 18
                        maxRange = (ProbeRangeItem(unit, 4, true) == true) and 23 or 28
                    else
                        maxRange = 28
                    end
                else
                    local r23 = ProbeRangeItem(unit, 4, false)
                    if r23 == true then
                        maxRange = (ProbeRangeItem(unit, 2, false) == true) and 13 or 23
                    elseif r23 == false then
                        minRange = 23
                        maxRange = 28
                    else
                        maxRange = 28
                    end
                end
            elseif r28 == false then
                minRange = 28
                local r38 = ProbeRangeItem(unit, 7, isFriend)
                if r38 == true then
                    maxRange = (ProbeRangeItem(unit, 6, isFriend) == true) and 33 or 38
                elseif r38 == false then
                    minRange = 38
                end
            else
                local startIdx = (d2 == false) and 2 or 1
                for i = startIdx, #ITEM_RANGES do
                    if d1 == true and ITEM_RANGES[i].range > 28 then
                        break
                    end
                    local res = ProbeRangeItem(unit, i, isFriend)
                    if res == true then
                        maxRange = ITEM_RANGES[i].range
                        break
                    elseif res == false then
                        minRange = ITEM_RANGES[i].range
                    end
                end
            end
        end
    end

    SaveDistBracket(tGuid, isFriend, maxRange)

    if maxRange == 8 then
        return 8, "< 8m"
    end
    if maxRange == 13 then
        return 13, "~13m"
    end
    if maxRange == 18 then
        return 16, "~16m"
    end
    if maxRange == 23 then
        return 21, "~21m"
    end
    if maxRange == 28 then
        return 26, "~26m"
    end

    if d1 == true then
        return 20, L["12-28m"]
    end

    if maxRange == 33 then
        return 31, "~31m"
    end
    if maxRange == 38 then
        return 36, "~36m"
    end

    if in43Checked and in43 then
        return 38, L["29-40m"]
    elseif in43Checked and not in43 then
        return 45, "> 43m"
    elseif minRange >= 38 then
        return 42, "> 38m"
    elseif d1 == false then
        return 35, "> 28m"
    end

    return nil, nil
end

local function RecomputeOnScreenFlags()
    wipe(onScreenCounts)
    for _, key in pairs(Spotter.visibleUnits) do
        onScreenCounts[key] = (onScreenCounts[key] or 0) + 1
    end
    for key, entry in pairs(Spotter.entries) do
        local c = onScreenCounts[key] or 0
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

local PLATE_STANCE_LABEL_KEYS = {
    ENEMY = "ENEMY CLAN",
    BLOCKED = "BLOCKED",
    WATCHLIST = "WATCHLIST",
    FRIEND = "FRIEND",
    ALLY = "ALLY CLAN",
    SAME = "SAME CLAN",
}

local function IsPlateShowingOnScreen(plate)
    if not IsPlateAccessible(plate) then return false end
    if plate.IsShown and Safe.Value(Safe.Call(plate.IsShown, plate)) == false then
        return false
    end
    if plate.IsVisible and Safe.Value(Safe.Call(plate.IsVisible, plate)) == false then
        return false
    end
    return true
end

local function IsPlateAnchorSafe(plate)
    if not IsPlateAccessible(plate) then return false end
    if plate.IsAnchoringRestricted then
        local ok, restricted = pcall(plate.IsAnchoringRestricted, plate)
        if not ok or restricted then
            return false
        end
    end
    return true
end

local function HidePlateBadge(unit, plate)
    local p = plate
    if not p and unit then
        p = activePlatesByUnit[unit]
    end
    if not p and unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, pl = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and pl then p = pl end
    end
    if p and Spotter.plateBadges[p] then
        Spotter.plateBadges[p]:Hide()
        if Spotter.plateBadges[p].targetArrow then
            Spotter.plateBadges[p].targetArrow:Hide()
        end
    end
end

local function HideAllPlateBadges()
    for _, b in pairs(Spotter.plateBadges) do
        if b then
            b:Hide()
            if b.targetArrow then
                b.targetArrow:Hide()
            end
        end
    end
end

local function EnsurePlateBadge(plate)
    local b = Spotter.plateBadges[plate]
    if b then return b end

    -- Parented directly to plate so WoW anchors and projects it in 3D world space seamlessly
    b = CreateFrame("Frame", nil, plate)
    b:SetSize(118, 18)
    b:SetPoint("BOTTOM", plate, "TOP", 0, 4)
    b:SetFrameLevel(math.max(120, ((plate.GetFrameLevel and plate:GetFrameLevel()) or 1) + 30))
    b:EnableMouse(false)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.05, 0.07, 0.90)
    b.bg = bg

    local accent = b:CreateTexture(nil, "BORDER")
    accent:SetSize(3, 18)
    accent:SetPoint("LEFT", 0, 0)
    accent:SetColorTexture(0.98, 0.80, 0.24, 1.0)
    b.accent = accent

    local topLine = b:CreateTexture(nil, "BORDER")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    topLine:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    topLine:SetColorTexture(0.28, 0.32, 0.40, 0.85)
    b.topLine = topLine

    local botLine = b:CreateTexture(nil, "BORDER")
    botLine:SetHeight(1)
    botLine:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    botLine:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    botLine:SetColorTexture(0.28, 0.32, 0.40, 0.85)
    b.botLine = botLine

    local rightLine = b:CreateTexture(nil, "BORDER")
    rightLine:SetWidth(1)
    rightLine:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    rightLine:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    rightLine:SetColorTexture(0.28, 0.32, 0.40, 0.85)
    b.rightLine = rightLine

    local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("CENTER", 2, 0)
    lbl:SetJustifyH("CENTER")
    lbl:SetWordWrap(false)
    b.lbl = lbl

    local subLbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subLbl:SetPoint("TOP", lbl, "BOTTOM", 0, -1)
    subLbl:SetJustifyH("CENTER")
    subLbl:SetWordWrap(false)
    subLbl:Hide()
    b.subLbl = subLbl

    local targetHalo = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    targetHalo:SetPoint("TOPLEFT", b, "TOPLEFT", -10, 6)
    targetHalo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 10, -6)
    targetHalo:SetTexture(TARGET_GLOW_TEX)
    targetHalo:SetBlendMode("ADD")
    targetHalo:SetVertexColor(1.0, 0.72, 0.18, 0.42)
    targetHalo:Hide()
    b.targetHalo = targetHalo

    -- Target downward arrow (pulsing/animated, pointing directly down at the plate/badge)
    local arrowFrame = CreateFrame("Frame", nil, b)
    arrowFrame:SetSize(40, 40)
    arrowFrame:SetPoint("BOTTOM", b, "TOP", 0, 2)
    arrowFrame:SetFrameLevel(b:GetFrameLevel() + 15)
    arrowFrame:EnableMouse(false)

    local mover = CreateFrame("Frame", nil, arrowFrame)
    mover:SetAllPoints()
    mover:EnableMouse(false)
    arrowFrame.mover = mover

    local glow = mover:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(48, 48)
    glow:SetPoint("CENTER", mover, "CENTER", 0, 0)
    glow:SetTexture(TARGET_GLOW_TEX)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1.0, 0.12, 0.16, 0.80)
    arrowFrame.glow = glow

    local shadow = mover:CreateTexture(nil, "ARTWORK", nil, 0)
    shadow:SetSize(40, 40)
    shadow:SetPoint("CENTER", mover, "CENTER", 0, -2)
    shadow:SetTexture(TARGET_ARROW_TEX)
    shadow:SetDesaturated(true)
    shadow:SetRotation(math.pi)
    shadow:SetVertexColor(0.02, 0.0, 0.0, 0.90)
    arrowFrame.shadow = shadow

    local arrowTex = mover:CreateTexture(nil, "ARTWORK", nil, 1)
    arrowTex:SetSize(36, 36)
    arrowTex:SetPoint("CENTER", mover, "CENTER", 0, 0)
    arrowTex:SetTexture(TARGET_ARROW_TEX)
    arrowTex:SetDesaturated(true)
    arrowTex:SetRotation(math.pi)
    arrowTex:SetVertexColor(1.0, 0.18, 0.20, 1.0)
    arrowFrame.arrowTex = arrowTex

    local sheen = mover:CreateTexture(nil, "OVERLAY", nil, 2)
    sheen:SetSize(36, 36)
    sheen:SetPoint("CENTER", mover, "CENTER", 0, 0)
    sheen:SetTexture(TARGET_ARROW_TEX)
    sheen:SetDesaturated(true)
    sheen:SetRotation(math.pi)
    sheen:SetBlendMode("ADD")
    sheen:SetVertexColor(1.0, 0.40, 0.25, 0.65)
    arrowFrame.sheen = sheen

    arrowFrame._animElapsed = 0
    arrowFrame._animTick = 0
    arrowFrame._animUpdateFn = function(selfA, elapsed)
        local dt = elapsed or 0
        selfA._animElapsed = (selfA._animElapsed or 0) + dt
        selfA._animTick = (selfA._animTick or 0) + dt
        if selfA._animTick < 0.05 then
            return
        end
        selfA._animTick = 0
        local wave = math.sin(selfA._animElapsed * 7.5)
        local bounce = math.floor((wave * 4.5) * 10 + 0.5) * 0.1
        local pulse = 0.5 + 0.5 * wave
        if selfA._lastBounceY ~= bounce then
            selfA._lastBounceY = bounce
            selfA.mover:ClearAllPoints()
            selfA.mover:SetPoint("CENTER", selfA, "CENTER", 0, bounce)
        end
        selfA.glow:SetAlpha(0.35 + pulse * 0.55)
        selfA.sheen:SetAlpha(0.30 + pulse * 0.60)
    end
    arrowFrame:SetScript("OnShow", function(selfA)
        selfA._animElapsed = 0
        selfA._animTick = 0.04
        selfA._lastBounceY = nil
        selfA:SetScript("OnUpdate", selfA._animUpdateFn)
    end)
    arrowFrame:SetScript("OnHide", function(selfA)
        selfA:SetScript("OnUpdate", nil)
    end)
    arrowFrame:Hide()
    b.targetArrow = arrowFrame

    b:Hide()
    Spotter.plateBadges[plate] = b
    return b
end

local function ApplyBadgeFontMode(b, isTargetBanner)
    local wantMode = isTargetBanner and "target" or "normal"
    if b._fontMode == wantMode then
        return
    end
    b._fontMode = wantMode
    local fontPath = (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    if isTargetBanner then
        pcall(b.lbl.SetFont, b.lbl, fontPath, 13, "THICKOUTLINE")
        pcall(b.lbl.SetShadowColor, b.lbl, 0, 0, 0, 1)
        pcall(b.lbl.SetShadowOffset, b.lbl, 1.5, -1.5)
        if b.subLbl then
            pcall(b.subLbl.SetFont, b.subLbl, fontPath, 10, "OUTLINE")
            pcall(b.subLbl.SetShadowColor, b.subLbl, 0, 0, 0, 1)
            pcall(b.subLbl.SetShadowOffset, b.subLbl, 1, -1)
        end
    else
        pcall(b.lbl.SetFont, b.lbl, fontPath, 10, "OUTLINE")
        pcall(b.lbl.SetShadowColor, b.lbl, 0, 0, 0, 0.95)
        pcall(b.lbl.SetShadowOffset, b.lbl, 1, -1)
    end
end

local function ResolveTargetHeaderInfo(unit, entry)
    local dispName = entry and entry.displayName
    local isPlayer = unit and Safe.Value(Safe.Call(UnitIsPlayer, unit)) == true
    local uToken = (unit and Safe.Value(Safe.Call(UnitExists, unit)) == true) and unit or "target"
    if (not dispName or dispName == "") and uToken and Safe.Value(Safe.Call(UnitExists, uToken)) == true then
        if isPlayer and Compat.ResolveUnitFullName then
            local guid = Safe.String(Safe.Call(UnitGUID, uToken))
            local res = Compat.ResolveUnitFullName(uToken, guid, nil, true)
            dispName = res and res.fullName or nil
        end
        if not dispName or dispName == "" then
            dispName = Safe.String(Safe.Call(UnitName, uToken))
        end
    end
    if not dispName or dispName == "" or dispName == "Unknown" then
        return nil, nil, 1.0, 0.84, 0.25
    end

    local tr, tg, tb = 1.0, 0.84, 0.25
    local cls = entry and entry.classFile
    if not cls and isPlayer and uToken then
        local _, rawCls = Safe.Call(UnitClass, uToken)
        cls = Safe.String(rawCls)
    end
    if cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
        local rc = RAID_CLASS_COLORS[cls]
        tr, tg, tb = rc.r, rc.g, rc.b
    elseif entry and entry.stance and STANCE_COLORS[entry.stance] then
        local sc = STANCE_COLORS[entry.stance]
        tr, tg, tb = sc.r, sc.g, sc.b
    elseif uToken and Safe.Value(Safe.Call(UnitIsEnemy, "player", uToken)) == true then
        tr, tg, tb = 1.0, 0.30, 0.28
    elseif uToken and Safe.Value(Safe.Call(UnitIsFriend, "player", uToken)) == true then
        tr, tg, tb = 0.32, 0.94, 0.48
    end

    local lvl = (entry and tonumber(entry.level)) or (uToken and Safe.Number(Safe.Call(UnitLevel, uToken))) or 0
    local mainText = (lvl and lvl > 0)
        and ("» " .. dispName .. " · " .. (L["Lv %d"]:format(lvl)) .. " «")
        or ("» " .. dispName .. " «")

    local guildName = entry and entry.guild
    if (not guildName or guildName == "") and uToken then
        guildName = Safe.String(Safe.Call(GetGuildInfo, uToken))
    end
    return mainText, guildName, tr, tg, tb
end

function Spotter:UpdatePlateBadge(plate, unit, entry)
    if not IsPlateAnchorSafe(plate) then
        if IsPlateAccessible(plate) and Spotter.plateBadges[plate] then
            Spotter.plateBadges[plate]:Hide()
        end
        return
    end
    local s = ns.db and ns.db.settings
    if not self:IsEnabled() then
        HidePlateBadge(unit, plate)
        return
    end

    local badgesEnabled = not s or s.spotterNameplateBadges ~= false
    local arrowEnabled = not s or s.spotterNameplateArrow ~= false
    local highlightEnabled = not s or s.spotterNameplateTargetHighlight ~= false

    -- Target detection: either live target token, GUID match, or Radar focused target
    local isTarget = false
    if arrowEnabled or highlightEnabled then
        if unit and Safe.Value(Safe.Call(UnitExists, unit)) == true and Safe.Value(Safe.Call(UnitIsUnit, unit, "target")) == true then
            isTarget = true
        elseif entry and entry.guid and Safe.String(Safe.Call(UnitGUID, "target")) == entry.guid then
            isTarget = true
        elseif entry and ns.SpotterHUD and ns.SpotterHUD._compassEntry and ns.SpotterHUD._compassEntry.key == entry.key then
            local hudShown = (ns.SpotterHUD.frame and ns.SpotterHUD.frame:IsShown()) or (ns.SpotterHUD.combatArrowFrame and ns.SpotterHUD.combatArrowFrame:IsShown())
            if hudShown then
                isTarget = true
            end
        end
    end

    local showBadge = badgesEnabled and (entry ~= nil)
    local showTargetBanner = isTarget and highlightEnabled
    local showTargetArrow = isTarget and arrowEnabled
    if not showBadge and not showTargetBanner and not showTargetArrow then
        HidePlateBadge(unit, plate)
        return
    end

    local b = EnsurePlateBadge(plate)
    b._boundUnit = unit
    b._boundPlate = plate

    if plate and plate.GetFrameLevel then
        local pLvl = plate:GetFrameLevel() or 1
        b:SetFrameLevel(math.max(120, pLvl + 30))
        if b.targetArrow then
            b.targetArrow:SetFrameLevel(b:GetFrameLevel() + 15)
        end
    end

    if showTargetBanner then
        ApplyBadgeFontMode(b, true)
        local mainText, guildName, tr, tg, tb = ResolveTargetHeaderInfo(unit, entry)
        local stance = entry and entry.stance
        local c = (stance and STANCE_COLORS[stance]) or { r = tr, g = tg, b = tb }
        local subParts = nil
        if showBadge and stance then
            local labelKey = PLATE_STANCE_LABEL_KEYS[stance] or "CLAN"
            local rawLabel = L[labelKey] or labelKey
            subParts = type(rawLabel) == "string" and rawLabel:upper() or rawLabel
        end
        if guildName and guildName ~= "" then
            subParts = subParts and ("<" .. guildName .. "> · " .. subParts) or ("<" .. guildName .. ">")
        elseif not subParts and not entry then
            subParts = L["TARGET"]
        end

        if mainText then
            if b._lastLabel ~= mainText then
                b._lastLabel = mainText
                b.lbl:SetText(mainText)
            end
            b.lbl:SetTextColor(tr, tg, tb, 1.0)
            b.lbl:ClearAllPoints()
            if subParts and subParts ~= "" and b.subLbl then
                b.lbl:SetPoint("TOP", b, "TOP", 2, -4)
                if b._lastSub ~= subParts then
                    b._lastSub = subParts
                    b.subLbl:SetText(subParts)
                end
                b.subLbl:SetTextColor(c.r, c.g, c.b, 0.98)
                b.subLbl:ClearAllPoints()
                b.subLbl:SetPoint("TOP", b.lbl, "BOTTOM", 0, -2)
                b.subLbl:Show()
            else
                b.lbl:SetPoint("CENTER", b, "CENTER", 2, 0)
                if b.subLbl then b.subLbl:Hide() end
            end

            local mainW = b.lbl:GetStringWidth() or 80
            local subW = (subParts and subParts ~= "" and b.subLbl and b.subLbl:GetStringWidth()) or 0
            local wantW = math.max(124, math.ceil(math.max(mainW, subW) + 26))
            local wantH = (subParts and subParts ~= "") and 36 or 24
            b:SetWidth(wantW)
            b:SetHeight(wantH)
            b.accent:SetWidth(4)
            b.accent:SetHeight(wantH)
            b.bg:SetColorTexture(0.03, 0.04, 0.06, 0.95)
            b.accent:SetColorTexture(c.r, c.g, c.b, 1.0)
            b.topLine:SetColorTexture(c.r, c.g, c.b, 0.92)
            b.botLine:SetColorTexture(c.r, c.g, c.b, 0.92)
            b.rightLine:SetColorTexture(c.r, c.g, c.b, 0.92)
            if b.targetHalo then
                b.targetHalo:SetVertexColor(c.r, c.g, c.b, 0.42)
                b.targetHalo:Show()
            end
            b.bg:Show()
            b.accent:Show()
            b.topLine:Show()
            b.botLine:Show()
            b.rightLine:Show()
            b.lbl:Show()

            if showTargetArrow then
                b.targetArrow:ClearAllPoints()
                b.targetArrow:SetPoint("BOTTOM", b, "TOP", 0, 2)
                b.targetArrow:Show()
            else
                b.targetArrow:Hide()
            end
            b:Show()
            return
        end
    end

    if b.subLbl then b.subLbl:Hide() end
    if b.targetHalo then b.targetHalo:Hide() end

    if showBadge then
        ApplyBadgeFontMode(b, false)
        b.lbl:ClearAllPoints()
        b.lbl:SetPoint("CENTER", 2, 0)
        local stance = entry.stance or "SAME"
        local c = STANCE_COLORS[stance] or STANCE_COLORS.SAME
        local labelKey = PLATE_STANCE_LABEL_KEYS[stance] or "CLAN"
        local rawLabel = L[labelKey] or labelKey
        local labelTxt = type(rawLabel) == "string" and rawLabel:upper() or rawLabel

        local badgeSig = tostring(stance) .. ":" .. tostring(labelTxt)
        if b._lastBadgeSig ~= badgeSig then
            b._lastBadgeSig = badgeSig
            b.bg:SetColorTexture(0.04, 0.05, 0.07, 0.90)
            b.accent:SetWidth(3)
            b.accent:SetHeight(18)
            b.accent:SetColorTexture(c.r, c.g, c.b, 1.0)
            b.topLine:SetColorTexture(c.r * 0.65, c.g * 0.65, c.b * 0.65, 0.75)
            b.botLine:SetColorTexture(c.r * 0.65, c.g * 0.65, c.b * 0.65, 0.75)
            b.rightLine:SetColorTexture(c.r * 0.65, c.g * 0.65, c.b * 0.65, 0.75)
            if b._lastLabel ~= labelTxt then
                b._lastLabel = labelTxt
                b.lbl:SetText(labelTxt)
            end
            b.lbl:SetTextColor(c.r, c.g, c.b, 1.0)
            local textW = b.lbl:GetStringWidth() or 60
            b:SetWidth(math.max(88, textW + 28))
            b:SetHeight(18)
        end
        b.bg:Show()
        b.accent:Show()
        b.topLine:Show()
        b.botLine:Show()
        b.rightLine:Show()
        b.lbl:Show()

        if showTargetArrow then
            b.targetArrow:ClearAllPoints()
            b.targetArrow:SetPoint("BOTTOM", b, "TOP", 0, 2)
            b.targetArrow:Show()
        else
            b.targetArrow:Hide()
        end
    else
        -- Targeted unit with arrow-only mode (no highlight banner)
        b.bg:Hide()
        b.accent:Hide()
        b.topLine:Hide()
        b.botLine:Hide()
        b.rightLine:Hide()
        b.lbl:Hide()
        b:SetSize(40, 40)
        b.targetArrow:ClearAllPoints()
        b.targetArrow:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.targetArrow:Show()
    end

    b:Show()
end

function Spotter:UpdateAllPlateBadges()
    local s = ns.db and ns.db.settings
    if not self:IsEnabled() or (s and s.spotterNameplateBadges == false and s.spotterNameplateArrow == false and s.spotterNameplateTargetHighlight == false) then
        HideAllPlateBadges()
        return
    end
    local updatedPlates = {}
    for unit, plate in pairs(activePlatesByUnit) do
        if plate and IsPlateAccessible(plate) then
            local key = self.visibleUnits[unit]
            local entry = key and self.entries[key] or nil
            updatedPlates[plate] = (entry ~= nil)
            self:UpdatePlateBadge(plate, unit, entry)
        end
    end
    if Safe.Value(Safe.Call(UnitExists, "target")) == true and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, tPlate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if ok and tPlate and IsPlateAccessible(tPlate) then
            local tGuid = Safe.String(Safe.Call(UnitGUID, "target"))
            local tEntry = tGuid and self.entryByGuid[tGuid] or nil
            if tEntry or not updatedPlates[tPlate] then
                self:UpdatePlateBadge(tPlate, "target", tEntry)
            end
        end
    end
end

Spotter.UpdateFocusedPlateMarker = Spotter.UpdateAllPlateBadges

local function MigrateEntryStateKey(self, oldKey, newKey, entry)
    if not oldKey or not newKey or oldKey == newKey then return end
    if self.entries[oldKey] then
        self.entries[oldKey] = nil
    end
    if entry then
        self.entries[newKey] = entry
        entry.key = newKey
        if entry.guid then
            self.entryByGuid[entry.guid] = entry
        end
    end
    if self.alertCooldowns[oldKey] ~= nil then
        if self.alertCooldowns[newKey] == nil then
            self.alertCooldowns[newKey] = self.alertCooldowns[oldKey]
        end
        self.alertCooldowns[oldKey] = nil
    end
    if self.dismissedUntil[oldKey] ~= nil then
        if not self.dismissedUntil[newKey] or self.dismissedUntil[oldKey] > self.dismissedUntil[newKey] then
            self.dismissedUntil[newKey] = self.dismissedUntil[oldKey]
        end
        self.dismissedUntil[oldKey] = nil
    end
    if self.toastExpiredUntil[oldKey] ~= nil then
        if not self.toastExpiredUntil[newKey] or self.toastExpiredUntil[oldKey] > self.toastExpiredUntil[newKey] then
            self.toastExpiredUntil[newKey] = self.toastExpiredUntil[oldKey]
        end
        self.toastExpiredUntil[oldKey] = nil
    end
    if self.manualTracked[oldKey] then
        self.manualTracked[newKey] = true
        self.manualTracked[oldKey] = nil
    end
    if self.manualTrackedStance[oldKey] ~= nil then
        if self.manualTrackedStance[newKey] == nil then
            self.manualTrackedStance[newKey] = self.manualTrackedStance[oldKey]
        end
        self.manualTrackedStance[oldKey] = nil
    end
    if entry then
        entry._manualTracked = self.manualTracked[newKey] == true
    end
    for uTok, mappedKey in pairs(self.visibleUnits) do
        if mappedKey == oldKey then
            self.visibleUnits[uTok] = newKey
        end
    end
    if self.lastAlert and self.lastAlert.key == oldKey then
        self.lastAlert.key = newKey
    end
    if ns.SpotterHUD then
        if ns.SpotterHUD.focusedKey == oldKey then
            ns.SpotterHUD.focusedKey = newKey
        end
        if ns.SpotterHUD.interactionKey == oldKey then
            ns.SpotterHUD.interactionKey = newKey
        end
    end
    MarkTargetsDirty()
end

function Spotter:GetStanceLabel(stance)
    if stance == "ENEMY" then return L["Enemy Clan"] end
    if stance == "BLOCKED" then return L["Blocked"] end
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
    local clanModOn = (not Compat.IsModuleEnabled) or Compat.IsModuleEnabled("clan")
    if stance == "ENEMY" then return clanModOn and s.spotterNotifyEnemy ~= false end
    if stance == "BLOCKED" then return s.spotterNotifyBlocked ~= false end
    if stance == "WATCHLIST" then return (not Compat.IsModuleEnabled or Compat.IsModuleEnabled("watchlist")) and s.spotterNotifyWatchlist ~= false end
    if stance == "FRIEND" then return s.spotterNotifyFriends ~= false end
    if stance == "ALLY" then return clanModOn and s.spotterNotifyAlly ~= false end
    if stance == "SAME" then return clanModOn and s.spotterNotifySameClan == true end
    return false
end

local function PlaySpotterSound(stance, senderKeyOrName)
    local s = ns.db and ns.db.settings
    if not s or s.spotterSound == false then return end
    if Compat and Compat.IsFocusSilenced and Compat.IsFocusSilenced(senderKeyOrName) then
        return
    end
    if not PlaySound then return end

    if SOUNDKIT then
        local kit
        if stance == "ENEMY" or stance == "BLOCKED" then
            kit = SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT or 180
        else
            kit = SOUNDKIT.MAP_PING or 3175
        end
        if kit then
            pcall(PlaySound, kit, "Master")
            return
        end
    end

    pcall(PlaySound, "MapPing")
end

function Spotter:MaybeTriggerAlert(entry)
    if not entry or not ShouldNotifyStance(entry.stance, entry.key) then return end

    local s = ns.db and ns.db.settings
    local hudActive = (not s) or (s.spotterAutoShowHUD ~= false)
    local hudSuppressedByUser = hudActive and ns.SpotterHUD and ns.SpotterHUD.userClosed == true
        and entry.stance ~= "ENEMY" and entry.stance ~= "BLOCKED"
    local willPrintChat = (not hudActive) or entry.stance == "ENEMY" or entry.stance == "BLOCKED" or entry.stance == "WATCHLIST"
    local willShowBanner = (s and s.spotterAutoShowHUD == false) == true
    local willShowVisual = willPrintChat or willShowBanner or (hudActive and not hudSuppressedByUser)
    if not willShowVisual then
        return
    end

    local now = time()
    local cooldown = (entry.stance == "ENEMY" or entry.stance == "BLOCKED") and ENEMY_ALERT_COOLDOWN or FRIENDLY_ALERT_COOLDOWN
    local prev = self.alertCooldowns[entry.key] or 0
    if (now - prev) < cooldown then
        return
    end
    self.alertCooldowns[entry.key] = now

    local kin = self:GetTargetKinematics(entry)
    local distStr = (kin and kin.distText) or entry.lastDistText or L["Nearby"]
    local bearingStr = nil
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

    if willPrintChat then
        ns:Print("%s %s%s%s%s %s", tag, playerCol, guildText, whereText, reasonText, radarLink)
    end

    if willShowBanner then
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

    if not hudSuppressedByUser or willPrintChat or willShowBanner then
        PlaySpotterSound(entry.stance, entry.key or entry.displayName)
    end

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

-- O(1) Inverse Positive-Set Pre-Filter (Bloom-Filter principle, 0 allocations, 0 false negatives).
-- Immediately eliminates strangers outside Friends, Watchlist, Guild/Diplomacy, Blocked, or manual tracking.
-- Returns (matched, confirmedNoGuildMatch) so uncached cold guild queries get a brief grace window.
local function QuickCandidateGate(unit, guid, rawUnitName)
    if posIndexDirty or socialCacheDirty then
        RebuildPositiveIndex()
    end
    if guid and Spotter.entryByGuid[guid] then
        return true, true
    end
    if (not hasAnyPosPeople) and (not hasAnyPosGuilds) then
        return false, true
    end
    local isOppositeHostile = IsUnitOppositeOrHostile(unit, nil)
    if guid and posGuidSet[guid] then
        if not isOppositeHostile or not (guildPosGuidSet and guildPosGuidSet[guid]) then
            return true, true
        end
    end
    if hasAnyPosPeople and rawUnitName and rawUnitName ~= "" then
        if isOppositeHostile then
            local pKey = Compat.ParseCharacterFields and Compat.ParseCharacterFields(rawUnitName)
            local normFull = (pKey and pKey ~= "" and pKey) or NormalizeKeyPart(rawUnitName)
            if normFull and (posAvoidKeys[normFull] or posIgnoreKeys[normFull] or (posKeySet[normFull] and not (guildPosKeySet and guildPosKeySet[normFull]))) then
                return true, true
            end
        else
            local firstLower = ExtractFastFirstLower(rawUnitName)
            if firstLower and posFirstSet[firstLower] then
                return true, true
            end
        end
    end
    if hasAnyPosGuilds and unit then
        local cleanRawGuild = Safe.String(Safe.Call(GetGuildInfo, unit))
        if (not cleanRawGuild or cleanRawGuild == "") and Compat.ReadUnitTooltipGuild then
            local allowLiveTip = (unit == "mouseover" or unit == "target" or unit == "focus")
            cleanRawGuild = Compat.ReadUnitTooltipGuild(allowLiveTip and unit or nil, guid, not allowLiveTip)
        end
        if cleanRawGuild and cleanRawGuild ~= "" then
            local cached = GetPosGuildRawCache(cleanRawGuild)
            if cached == nil then
                local rawStance = Spotter:ClassifyGuild(cleanRawGuild)
                if rawStance and IsStanceAllowed(rawStance, nil) then
                    cached = rawStance
                else
                    cached = false
                end
                RecordPosGuildRawCache(cleanRawGuild, cached)
            end
            if cached == false then
                return false, true
            end
            if isOppositeHostile and (cached == "SAME" or cached == "ALLY") then
                return false, true
            end
            return true, true
        else
            if isOppositeHostile then
                return false, true
            end
            local s = ns.db and ns.db.settings
            if s and s.spotterNotifySameClan == true and UnitIsInMyGuild and UnitIsFriend and Safe.Value(Safe.Call(UnitIsFriend, "player", unit)) == true then
                if Safe.Value(Safe.Call(UnitIsInMyGuild, unit)) == true then
                    return true, true
                end
            end
            return false, false
        end
    end
    return false, true
end

local function FlushInspectQueue()
    inspectQueueTimerActive = false
    if not Spotter:IsEnabled() then
        wipe(inspectQUnit)
        wipe(inspectQPlate)
        wipe(inspectQTicker)
        wipe(inspectQueuedSet)
        inspectQueueHead = 1
        inspectQueueTail = 0
        return
    end
    local processed = 0
    while inspectQueueHead <= inspectQueueTail and processed < INSPECT_BATCH_LIMIT do
        local unit = inspectQUnit[inspectQueueHead]
        local isPlate = inspectQPlate[inspectQueueHead]
        local isTicker = inspectQTicker[inspectQueueHead]
        inspectQUnit[inspectQueueHead] = nil
        inspectQPlate[inspectQueueHead] = nil
        inspectQTicker[inspectQueueHead] = nil
        inspectQueueHead = inspectQueueHead + 1
        if unit then
            inspectQueuedSet[unit] = nil
            if Safe.Value(Safe.Call(UnitExists, unit)) == true then
                Spotter:InspectUnit(unit, isPlate, isTicker, false, true)
                processed = processed + 1
            end
        end
    end
    if inspectQueueHead > inspectQueueTail then
        wipe(inspectQUnit)
        wipe(inspectQPlate)
        wipe(inspectQTicker)
        wipe(inspectQueuedSet)
        inspectQueueHead = 1
        inspectQueueTail = 0
    elseif C_Timer and C_Timer.After then
        inspectQueueTimerActive = true
        C_Timer.After(INSPECT_SLICE_INTERVAL, FlushInspectQueue)
    end
end

local function EnqueueInspection(unit, isNameplate, fromTicker)
    if not unit or inspectQueuedSet[unit] then return end
    if (inspectQueueTail - inspectQueueHead + 1) >= 64 then
        return
    end
    inspectQueuedSet[unit] = true
    inspectQueueTail = inspectQueueTail + 1
    inspectQUnit[inspectQueueTail] = unit
    inspectQPlate[inspectQueueTail] = (isNameplate == true)
    inspectQTicker[inspectQueueTail] = (fromTicker == true)
    if not inspectQueueTimerActive and C_Timer and C_Timer.After then
        inspectQueueTimerActive = true
        C_Timer.After(INSPECT_SLICE_INTERVAL, FlushInspectQueue)
    end
end

function Spotter:IsEnabled()
    local s = ns.db and ns.db.settings
    return s ~= nil and s.spotterEnabled ~= false
end

function Spotter:EnsurePruneLoop()
    if self._pruneTimerActive or not self:IsEnabled() or next(self.entries) == nil then
        return
    end
    if not (C_Timer and C_Timer.After) then return end
    self._pruneTimerActive = true
    local function PruneTick()
        if not Spotter:IsEnabled() or next(Spotter.entries) == nil then
            Spotter._pruneTimerActive = false
            return
        end
        local _, nextDelay = Spotter:CleanupAbsentTargets(false)
        if Spotter:IsEnabled() and next(Spotter.entries) ~= nil then
            C_Timer.After(nextDelay or PRUNE_INTERVAL, PruneTick)
        else
            Spotter._pruneTimerActive = false
        end
    end
    C_Timer.After(PRUNE_INTERVAL, PruneTick)
end

function Spotter:FocusTarget(key)
    if not self:IsEnabled() then return false end
    if not key or key == "" then return false end
    local entry = self.entries[key]
    if not entry then
        -- Fall back to firstName or normalized key match in case the key was upgraded with a surname.
        local altParsed = Compat.ParseCharacterName(key)
        local keyLow = (Compat.LowerUtf8 and Compat.LowerUtf8(key)) or key:lower()
        local lk = altParsed and altParsed.lookupKey or keyLow
        local firstLower = altParsed and ((Compat.LowerUtf8 and Compat.LowerUtf8(altParsed.firstName)) or altParsed.firstName:lower()) or lk
        for _, candidate in pairs(self.entries) do
            local candFirstLow = candidate.firstName and ((Compat.LowerUtf8 and Compat.LowerUtf8(candidate.firstName)) or candidate.firstName:lower()) or nil
            if candidate.key == lk or (candFirstLow and candFirstLow == firstLower) then
                entry = candidate
                break
            end
        end
    end
    if not entry then
        ns:Print(L["Player is no longer in Target Radar range."])
        return false
    end

    local now = time()
    entry.lastSeen = now
    entry.toastShownAt = now
    self.toastExpiredUntil[entry.key] = nil
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
    local total = 0
    for _ in pairs(Spotter.entries) do
        total = total + 1
    end
    if total <= MAX_TARGETS then return end

    local list = {}
    for _, e in pairs(Spotter.entries) do
        table.insert(list, e)
    end

    table.sort(list, function(a, b)
        local aOn = (a.onScreen == true)
        local bOn = (b.onScreen == true)
        if aOn ~= bOn then return aOn end
        local pa = STANCE_PRIORITY[a.stance] or 9
        local pb = STANCE_PRIORITY[b.stance] or 9
        if pa ~= pb then return pa < pb end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)

    for i = MAX_TARGETS + 1, #list do
        local dropped = list[i]
        Spotter.entries[dropped.key] = nil
        if dropped.guid then
            Spotter.entryByGuid[dropped.guid] = nil
        end
    end
    MarkTargetsDirty()
end

function Spotter:QueueBatchEmit(metadataDirty)
    if metadataDirty then
        self._batchEmitDirty = true
    end
    self:EnsurePruneLoop()
    if self._batchFlushQueued then return end
    if C_Timer and C_Timer.After then
        self._batchFlushQueued = true
        C_Timer.After(0, function()
            Spotter._batchFlushQueued = false
            local shouldEmit = Spotter._batchEmitDirty == true
            Spotter._batchEmitDirty = false
            RecomputeOnScreenFlags()
            TrimExcessTargets()
            MarkTargetsDirty()
            if shouldEmit then
                ns:Emit("SPOTTER_UPDATED")
            end
        end)
    else
        local shouldEmit = self._batchEmitDirty == true
        self._batchEmitDirty = false
        RecomputeOnScreenFlags()
        TrimExcessTargets()
        MarkTargetsDirty()
        if shouldEmit then
            ns:Emit("SPOTTER_UPDATED")
        end
    end
end

local function UnitMatchesEntry(unit, entry)
    if not unit or not entry then return false end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then return false end

    local uGuid = Safe.String(Safe.Call(UnitGUID, unit))
    if entry.guid and uGuid then
        return uGuid == entry.guid
    end

    local uName = Safe.String(Safe.Call(UnitName, unit))
    if uGuid and Compat.LookupForeverFullName then
        local firstHint
        if uName and Compat.ParseCharacterFields then
            local _, fHint = Compat.ParseCharacterFields(uName)
            firstHint = fHint
        end
        local cached = Compat.LookupForeverFullName(uGuid, firstHint or uName, false)
        if cached and cached.fullName and Compat.ParseCharacterFields then
            local cLookupKey, _, _, cSurname = Compat.ParseCharacterFields(cached.fullName)
            if cLookupKey then
                if cLookupKey == entry.key then
                    return true
                end
                if cSurname and entry.displayName and entry.displayName:find("%s") then
                    return false
                end
            end
        end
    end

    if uName and uName ~= "" then
        local uLow = (Compat.LowerUtf8 and Compat.LowerUtf8(uName)) or uName:lower()
        local eUnitLow = entry.unitName and ((Compat.LowerUtf8 and Compat.LowerUtf8(entry.unitName)) or entry.unitName:lower()) or nil
        if eUnitLow and uLow == eUnitLow and not (entry.guid and uGuid and entry.guid ~= uGuid) then
            local rLookupKey, _, _, rSurname
            if Compat.ParseCharacterFields then
                rLookupKey, _, _, rSurname = Compat.ParseCharacterFields(uName)
            end
            if not (rSurname and entry.key and rLookupKey ~= entry.key) then
                return true
            end
        end
        if Compat.ParseCharacterFields then
            local pLookupKey, pFirstName, _, pSurname = Compat.ParseCharacterFields(uName)
            if pLookupKey then
                if pLookupKey == entry.key then
                    return true
                end
                local entryHasSurname = type(entry.displayName) == "string" and entry.displayName:find("%s") ~= nil
                local pFirstLow = pFirstName and ((Compat.LowerUtf8 and Compat.LowerUtf8(pFirstName)) or pFirstName:lower()) or nil
                local eFirstLow = entry.firstName and ((Compat.LowerUtf8 and Compat.LowerUtf8(entry.firstName)) or entry.firstName:lower()) or nil
                if (not pSurname or not entryHasSurname)
                    and eFirstLow and pFirstLow and pFirstLow == eFirstLow then
                    return true
                end
            end
        end
    end
    return false
end

local function ResolvePlateForUnitOrEntry(unit, entry)
    if unit then
        local plate = activePlatesByUnit[unit]
        if not plate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
            local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
            if ok and p then plate = p end
        end
        if IsPlateAccessible(plate) then
            local pUnit = Safe.String(plate.namePlateUnitToken) or (plate.UnitFrame and Safe.String(plate.UnitFrame.unit))
            if pUnit and pUnit:match("^nameplate") then
                return plate, pUnit
            end
            return plate, (unit:match("^nameplate") and unit or nil)
        end
        return nil, nil
    end
    if not entry then return nil, nil end
    if entry.guid then
        local mappedUnit = activePlateUnitByGuid[entry.guid]
        if mappedUnit then
            local plate = activePlatesByUnit[mappedUnit]
            if IsPlateAccessible(plate) and Safe.Value(Safe.Call(UnitExists, mappedUnit)) == true then
                return plate, mappedUnit
            end
            activePlateUnitByGuid[entry.guid] = nil
        end
    end
    for pUnit, p in pairs(activePlatesByUnit) do
        if IsPlateAccessible(p) and UnitMatchesEntry(pUnit, entry) then
            return p, pUnit
        end
    end
    return nil, nil
end

function Spotter:InspectUnit(unit, isNameplate, fromTicker, skipCooldown, skipSliceLimit, knownGuid)
    if not self:IsEnabled() then
        return nil
    end
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then
        return nil
    end

    if not unit or Safe.IsSecret(unit) then return nil end
    local exists = Safe.Value(Safe.Call(UnitExists, unit))
    if exists ~= true then
        HidePlateBadge(unit, nil)
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            self:QueueBatchEmit(true)
        end
        return nil
    end

    local isPlayer = Safe.Value(Safe.Call(UnitIsPlayer, unit))
    if isPlayer ~= true then
        HidePlateBadge(unit, nil)
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            self:QueueBatchEmit(false)
        end
        return nil
    end

    -- O(1) Raid/Party short-circuit BEFORE touching GUID/Name/Guild tables
    if s.spotterIgnoreGroup ~= false and next(self.manualTracked) == nil then
        if unit ~= "player" and (Safe.Value(Safe.Call(UnitInRaid, unit)) == true or Safe.Value(Safe.Call(UnitInParty, unit)) == true) then
            HidePlateBadge(unit, nil)
            if isNameplate and self.visibleUnits[unit] then
                self.visibleUnits[unit] = nil
                self:QueueBatchEmit(true)
            end
            return nil
        end
    end

    local guid = (knownGuid and knownGuid ~= "" and knownGuid) or Safe.String(Safe.Call(UnitGUID, unit))
    local nowClock = (GetTime and GetTime()) or time()
    local trackedByGuid = guid and self.entryByGuid[guid] or nil
    if trackedByGuid and self.entries[trackedByGuid.key] ~= trackedByGuid then
        self.entryByGuid[guid] = nil
        trackedByGuid = nil
    end
    local cdUntil = guid and GetBystanderCooldown(guid) or nil
    if (not skipCooldown) and guid and not trackedByGuid and cdUntil and nowClock < cdUntil then
        return nil
    end

    if unit == "mouseover" and not trackedByGuid then
        if guid and guid == lastMouseoverGuid and (nowClock - lastMouseoverAt) < 0.25 then
            return nil
        end
        lastMouseoverGuid = guid
        lastMouseoverAt = nowClock
    end

    local rawUnitName = Safe.String(Safe.Call(UnitName, unit))
    if rawUnitName == "Unknown" or (UNKNOWNOBJECT and rawUnitName == UNKNOWNOBJECT) then
        if (not skipCooldown) and (not IsCrowdMode()) and unknownRetryCount < 6 and C_Timer and C_Timer.After then
            if not unknownRetryUnits[unit] then
                unknownRetryUnits[unit] = true
                unknownRetryCount = unknownRetryCount + 1
                C_Timer.After(0.50, function()
                    if unknownRetryUnits[unit] then
                        unknownRetryUnits[unit] = nil
                        unknownRetryCount = math.max(0, unknownRetryCount - 1)
                    end
                    if Spotter:IsEnabled() and Safe.Value(Safe.Call(UnitExists, unit)) == true then
                        Spotter:InspectUnit(unit, isNameplate, false, false)
                    end
                end)
            end
        end
        return nil
    end

    if not trackedByGuid then
        local passedGate, confirmedNoMatch = QuickCandidateGate(unit, guid, rawUnitName)
        if not passedGate then
            if confirmedNoMatch or (unit ~= "target" and unit ~= "focus" and unit ~= "mouseover") then
                RecordGateMissCooldown(guid, confirmedNoMatch, nowClock)
            end
            HidePlateBadge(unit, nil)
            if isNameplate and self.visibleUnits[unit] then
                self.visibleUnits[unit] = nil
                self:QueueBatchEmit(true)
            end
            return nil
        end
    end

    if (not skipCooldown) and (not skipSliceLimit) then
        if (nowClock - sliceWindowStart) >= INSPECT_SLICE_INTERVAL then
            sliceWindowStart = nowClock
            sliceInspectCount = 0
        end
        sliceInspectCount = sliceInspectCount + 1
        if sliceInspectCount > INSPECT_BATCH_LIMIT then
            EnqueueInspection(unit, isNameplate, fromTicker)
            return nil
        end
    end

    local existingName = trackedByGuid and trackedByGuid.displayName and trackedByGuid.displayName:find("%s") and trackedByGuid.displayName or nil
    -- Passive nameplate hits never force a synchronous full-roster sync on FirstName collisions.
    local useFastOnly = (not skipCooldown) and ((isNameplate == true) or (fromTicker == true) or (unit == "mouseover") or (existingName ~= nil) or (guid and GetBystanderCooldown(guid) ~= nil))
    local resolved, rawRealm = Compat.ResolveUnitFullName(unit, guid, existingName, useFastOnly)
    local rawName = resolved and resolved.fullName or rawUnitName
    if not rawName or rawName == "" or Compat.IsMe(rawName, guid) then
        HidePlateBadge(unit, nil)
        if isNameplate then
            self.visibleUnits[unit] = nil
        end
        return nil
    end

    local pKey, pFirstName, pDisplayName, pSurname
    if Compat.ParseCharacterFields then
        pKey, pFirstName, pDisplayName, pSurname = Compat.ParseCharacterFields(rawName)
    elseif Compat.ParseCharacterName then
        local parsed = Compat.ParseCharacterName(rawName)
        if parsed then
            pKey, pFirstName, pDisplayName, pSurname = parsed.lookupKey, parsed.firstName, parsed.displayName, parsed.surname
        end
    end
    local key = (pKey and pKey ~= "" and pKey) or NormalizeKeyPart(rawName)
    if not key or key == "" then return nil end

    if trackedByGuid and trackedByGuid.key and trackedByGuid.key ~= key then
        local trackedHasSurname = type(trackedByGuid.displayName) == "string" and trackedByGuid.displayName:find("%s") ~= nil
        if pSurname or not trackedHasSurname then
            MigrateEntryStateKey(self, trackedByGuid.key, key, self.entries[key] or trackedByGuid)
        else
            key = trackedByGuid.key
        end
    end

    local existingEntry = self.entries[key] or trackedByGuid
    local now = time()
    if skipCooldown then
        self.toastExpiredUntil[key] = nil
    end
    local isDismissed = (not self.manualTracked[key]) and (
        (self.dismissedUntil[key] and now < self.dismissedUntil[key])
        or ((not skipCooldown) and self.toastExpiredUntil[key] and now < self.toastExpiredUntil[key])
    )
    local isIgnoredGroup = ShouldIgnoreGroupUnit(unit, key, guid)

    local checkFirst = resolved and resolved.firstName or rawUnitName
    local isOppositeHostile, unitFaction = IsUnitOppositeOrHostile(unit, existingEntry and existingEntry.faction)
    local cacheOnlyTip = (unit ~= "target" and unit ~= "focus" and unit ~= "mouseover")
    local gName, gRank = GetUnitSafeGuild(unit, guid, cacheOnlyTip)
    local isMyGuildMember, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote, isBlocked = LookupKnownPlayerGuildOrMembership(checkFirst, rawName, guid)
    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    if isOppositeHostile then
        isMyGuildMember = false
        isFriend = false
        if knownGuild and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(knownGuild) == myNormGuild then
            knownGuild = nil
        end
        if gName and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) == myNormGuild then
            gName = nil
        end
    end
    if (not gName or gName == "") and knownGuild and knownGuild ~= "" then
        gName = knownGuild
    end

    if gName and gName ~= "" and myNormGuild and myNormGuild ~= "" then
        if isOppositeHostile or NormalizeKeyPart(gName) ~= myNormGuild then
            -- Unit belongs to a known different guild or opposite/hostile faction; never misclassify as our own clan.
            isMyGuildMember = false
        else
            isMyGuildMember = true
        end
    elseif (not gName or gName == "") and (not isOppositeHostile) then
        if UnitIsInMyGuild and UnitIsFriend and Safe.Value(Safe.Call(UnitIsFriend, "player", unit)) == true and not (UnitIsEnemy and Safe.Value(Safe.Call(UnitIsEnemy, "player", unit)) == true) then
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
        if isOppositeHostile and (rawStance == "SAME" or rawStance == "ALLY") then
            rawStance = nil
            dipEntry = nil
        end
        stance, resolvedReason, gName = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, isBlocked, watchNote, key, myNormGuild, myGuildName, gName, isOppositeHostile)
    end
    if not stance then
        local removedStale = false
        if self.entries[key] then
            self.entries[key] = nil
            removedStale = true
        end
        if trackedByGuid and trackedByGuid.key and self.entries[trackedByGuid.key] == trackedByGuid then
            self.entries[trackedByGuid.key] = nil
            removedStale = true
        end
        if guid then
            local isDirectIntent = (unit == "target" or unit == "focus" or unit == "mouseover")
            local hasKnownGuild = (gName ~= nil and gName ~= "")
            if not (isDirectIntent and not hasKnownGuild) then
                RecordBystanderCooldown(guid, nowClock + GetBystanderCooldownSeconds())
            elseif unit == "mouseover" then
                RecordBystanderCooldown(guid, nowClock + 1.5)
            end
            self.entryByGuid[guid] = nil
        end
        if self.lastAlert and (self.lastAlert.key == key or (guid and self.lastAlert.guid == guid)) then
            self.lastAlert = nil
            removedStale = true
        end
        if removedStale then
            MarkTargetsDirty()
        end
        HidePlateBadge(unit, nil)
        if isNameplate and self.visibleUnits[unit] then
            self.visibleUnits[unit] = nil
            self:QueueBatchEmit(true)
        elseif isNameplate then
            if removedStale then
                self:QueueBatchEmit(true)
            end
        elseif removedStale then
            self:QueueBatchEmit(true)
        end
        if removedStale then
            self:UpdateFocusedPlateMarker()
        end
        return nil
    end

    if guid then
        ClearBystanderCooldown(guid)
    end

    local displayName = pDisplayName or rawName
    local firstName = pFirstName or rawName
    local targetMacroName = SanitizeMacroTargetName(displayName, rawRealm)
    if not targetMacroName then return nil end

    local _, classFile = Safe.Call(UnitClass, unit)
    classFile = Safe.String(classFile) or knownClass
    local level = Safe.Number(Safe.Call(UnitLevel, unit)) or knownLevel
    local isDead = Safe.Value(Safe.Call(UnitIsDeadOrGhost, unit)) == true

    local isNewOrChanged = false
    local entry = existingEntry
    if not entry then
        entry = {
            key = key,
            firstSeen = now,
            toastShownAt = now,
        }
        isNewOrChanged = true
    elseif entry.stance ~= stance or not entry._alertEvaluated then
        entry.toastShownAt = now
        isNewOrChanged = true
    elseif skipCooldown then
        entry.toastShownAt = now
    end
    entry.key = key
    self.entries[key] = entry
    if guid then
        self.entryByGuid[guid] = entry
    end

    local prevDisplayName = entry and entry.displayName
    local prevGuild = entry and entry.guild
    local prevLevel = entry and entry.level
    local prevDead = entry and entry.dead
    local prevOnScreen = entry and entry.onScreen

    if (not pSurname) and entry and entry.displayName and entry.displayName:find("%s") then
        displayName = entry.displayName
        firstName = entry.firstName or firstName
    end
    entry.displayName = displayName
    entry.firstName = firstName
    entry.surname = pSurname or entry.surname
    entry.unitName = rawUnitName or entry.unitName
    entry.targetName = targetMacroName
    entry.guild = gName
    entry.guildRank = gRank
    if unitFaction and unitFaction ~= "" then
        entry.faction = unitFaction
    end
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
    elseif isNameplate or unit == "target" or unit == "focus" or unit == "mouseover" or unit:match("^party") or unit:match("^raid") then
        entry.unitToken = unit
    end
    entry._lastFindUnitAt = 0

    -- Only calculate distance while this unit is actively selected as the player's target.
    local isSelectedTarget = (unit == "target") or (Safe.Value(Safe.Call(UnitIsUnit, unit, "target")) == true)
    if isSelectedTarget then
        if skipCooldown or not entry._lastDistCheckAt or (nowClock - entry._lastDistCheckAt) >= 0.35 then
            entry._lastDistCheckAt = nowClock
            local measuredYards, measuredText = MeasureUnitDistance("target")
            if measuredYards and measuredText then
                entry.lastDistYards = measuredYards
                entry.lastDistText = measuredText
            end
        end
    else
        entry.lastDistYards = nil
        entry.lastDistText = nil
    end

    if skipCooldown or not entry._lastLocSyncAt or (nowClock - entry._lastLocSyncAt) >= 4.0 then
        entry._lastLocSyncAt = nowClock
        UpdateEntryZoneInfo(entry)
    end

    local activePlateUnit = (isNameplate and unit) or plateUnit
    local newPlateMapped = false
    if activePlateUnit then
        if self.visibleUnits[activePlateUnit] ~= key then
            newPlateMapped = true
        end
        self.visibleUnits[activePlateUnit] = key
        if plate then
            activePlatesByUnit[activePlateUnit] = plate
            self:UpdatePlateBadge(plate, activePlateUnit, entry)
        end
        if guid then
            activePlateUnitByGuid[guid] = activePlateUnit
        end
    end

    if isNewOrChanged then
        entry._alertEvaluated = true
        self:MaybeTriggerAlert(entry)
    end

    if (stance == "ENEMY" or stance == "BLOCKED" or stance == "WATCHLIST" or stance == "ALLY")
        and entry.surname and entry.surname ~= "" and entry.guid and not entry.dead
        and (not IsInInstanceFast()) and (not IsCrowdMode())
        and ns.Clan and ns.Clan.QueueCooperativeSighting then
        ns.Clan:QueueCooperativeSighting(entry.displayName, entry.guid, entry.level, entry.classFile, entry.guild, entry.zone)
    end

    if isSelectedTarget or (ns.SpotterHUD and ns.SpotterHUD._compassEntry and ns.SpotterHUD._compassEntry.key == key) or isNewOrChanged or newPlateMapped then
        self:UpdateFocusedPlateMarker()
    end

    local metadataChanged = isNewOrChanged
        or newPlateMapped
        or (entry.dead ~= prevDead)
        or (entry.displayName ~= prevDisplayName)
        or (entry.guild ~= prevGuild)
        or (entry.level ~= prevLevel)
        or (entry.onScreen ~= prevOnScreen)
    if metadataChanged then
        MarkTargetsDirty()
    end
    if skipCooldown then
        RecomputeOnScreenFlags()
        TrimExcessTargets()
        MarkTargetsDirty()
        self:EnsurePruneLoop()
        if metadataChanged then
            ns:Emit("SPOTTER_UPDATED")
        end
    else
        self:QueueBatchEmit(metadataChanged)
    end
    return entry
end

function Spotter:InspectChatSighting(rawSender, rawGuid)
    if not self:IsEnabled() then return nil end
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then return nil end

    local cleanSender = Safe.String(rawSender)
    local cleanGuid = Safe.String(rawGuid)
    if not cleanSender or cleanSender == "" or Compat.IsMe(cleanSender, cleanGuid) then
        return nil
    end

    local nowClock = (GetTime and GetTime()) or time()
    local senderCacheKey = cleanGuid or cleanSender:lower()
    local chatCdUntil = GetChatCooldown(senderCacheKey)
    if chatCdUntil and nowClock < chatCdUntil then
        return nil
    end
    RecordChatCooldown(senderCacheKey, nowClock + CHAT_SIGHTING_COOLDOWN)

    if posIndexDirty or socialCacheDirty then
        RebuildPositiveIndex()
    end
    local fastFirst = ExtractFastFirstLower(cleanSender)
    local mayMatch = (cleanGuid and (self.entryByGuid[cleanGuid] ~= nil or posGuidSet[cleanGuid] == true))
        or (fastFirst and posFirstSet[fastFirst] == true)
    if (not mayMatch) and hasAnyPosGuilds and cleanGuid and Compat.ReadUnitTooltipGuild then
        local cachedChatGuild = Compat.ReadUnitTooltipGuild(nil, cleanGuid, true)
        if cachedChatGuild and cachedChatGuild ~= "" then
            local cStance = self:ClassifyGuild(cachedChatGuild)
            if cStance and IsStanceAllowed(cStance, nil) then
                mayMatch = true
            end
        end
    end
    if not mayMatch then
        return nil
    end

    local existingByGuid = cleanGuid and self.entryByGuid[cleanGuid] or nil
    if existingByGuid and self.entries[existingByGuid.key] ~= existingByGuid then
        existingByGuid = nil
    end
    local bestFullName = cleanSender
    if not cleanSender:find("%s") then
        if existingByGuid and type(existingByGuid.displayName) == "string" and existingByGuid.displayName:find("%s") then
            bestFullName = existingByGuid.displayName
        elseif cleanGuid and Compat.LookupForeverFullName then
            local resolved = Compat.LookupForeverFullName(cleanGuid, fastFirst or cleanSender, false)
            if resolved and resolved.fullName then
                bestFullName = resolved.fullName
            end
        end
    end
    local pKey, pFirstName, pDisplayName, pSurname
    if Compat.ParseCharacterFields then
        pKey, pFirstName, pDisplayName, pSurname = Compat.ParseCharacterFields(bestFullName)
    elseif Compat.ParseCharacterName then
        local parsed = Compat.ParseCharacterName(bestFullName)
        if parsed then
            pKey, pFirstName, pDisplayName, pSurname = parsed.lookupKey, parsed.firstName, parsed.displayName, parsed.surname
        end
    end
    local key = (pKey and pKey ~= "" and pKey) or NormalizeKeyPart(bestFullName)
    if not key or key == "" then return nil end

    local prevEntry = self.entries[key] or existingByGuid
    local prevOldKey = prevEntry and prevEntry.key
    if not prevEntry and cleanGuid then
        for oldKey, oldEntry in pairs(self.entries) do
            if oldEntry.guid == cleanGuid then
                prevEntry = oldEntry
                prevOldKey = oldEntry.key or oldKey
                break
            end
        end
    end
    if prevEntry and prevOldKey and prevOldKey ~= key then
        local prevHasSurname = type(prevEntry.displayName) == "string" and prevEntry.displayName:find("%s") ~= nil
        if pSurname or not prevHasSurname then
            MigrateEntryStateKey(self, prevOldKey, key, self.entries[key] or prevEntry)
        else
            key = prevOldKey
        end
    end

    local now = time()
    if (not self.manualTracked[key]) and (
        (self.dismissedUntil[key] and now < self.dismissedUntil[key])
        or (self.toastExpiredUntil[key] and now < self.toastExpiredUntil[key])
    ) then
        return nil
    end
    if ShouldIgnoreGroupUnit(nil, key, cleanGuid) then
        return nil
    end

    local firstName = pFirstName or bestFullName
    local displayName = pDisplayName or bestFullName

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

    local isOppositeHostile, chatFac = IsUnitOppositeOrHostile(nil, prevEntry and prevEntry.faction)
    local isMyGuildMember, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote, isBlocked = LookupKnownPlayerGuildOrMembership(firstName, displayName, cleanGuid)
    local gName, gRank = GetUnitSafeGuild(nil, cleanGuid, true)
    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    if isOppositeHostile then
        isMyGuildMember = false
        isFriend = false
        if knownGuild and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(knownGuild) == myNormGuild then
            knownGuild = nil
        end
        if gName and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) == myNormGuild then
            gName = nil
        end
    end
    if (not gName or gName == "") and knownGuild and knownGuild ~= "" then
        gName = knownGuild
    end
    if (not gName or gName == "") and prevEntry and prevEntry.guild and prevEntry.guild ~= "" then
        if not (isOppositeHostile and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(prevEntry.guild) == myNormGuild) then
            gName = prevEntry.guild
        end
    end
    if gName and gName ~= "" and myNormGuild and myNormGuild ~= "" and (isOppositeHostile or NormalizeKeyPart(gName) ~= myNormGuild) then
        isMyGuildMember = false
    elseif (not isOppositeHostile) and gName and gName ~= "" and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) == myNormGuild then
        isMyGuildMember = true
    end
    local rawStance, dipEntry = self:ClassifyGuild(gName)
    if isOppositeHostile and (rawStance == "SAME" or rawStance == "ALLY") then
        rawStance = nil
        dipEntry = nil
    end
    local stance, resolvedReason
    stance, resolvedReason, gName = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, isBlocked, watchNote, key, myNormGuild, myGuildName, gName, isOppositeHostile)
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
                    MigrateEntryStateKey(self, oldKey, key, entry)
                end
                break
            end
        end
    end
    if not entry then
        entry = {
            key = key,
            firstSeen = now,
            toastShownAt = now,
        }
        isNewOrChanged = true
    elseif entry.stance ~= stance or not entry._alertEvaluated then
        entry.toastShownAt = now
        isNewOrChanged = true
    end
    entry.key = key
    self.entries[key] = entry
    if cleanGuid and cleanGuid ~= "" then
        self.entryByGuid[cleanGuid] = entry
    end

    if not pSurname and entry.displayName and entry.displayName:find("%s") then
        displayName = entry.displayName
        firstName = entry.firstName or firstName
    end
    entry.displayName = displayName
    entry.firstName = firstName
    entry.surname = pSurname or entry.surname
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
    entry.lastDistYards = nil
    entry.lastDistText = nil

    UpdateEntryZoneInfo(entry)

    if isNewOrChanged then
        entry._alertEvaluated = true
        self:MaybeTriggerAlert(entry)
    end

    MarkTargetsDirty()
    self:QueueBatchEmit(true)
    return entry
end

function Spotter:RefreshVisibleNameplates(fromTicker)
    if not self:IsEnabled() then
        return
    end
    local s = ns.db and ns.db.settings
    if not s or s.spotterEnabled == false then
        return
    end
    if posIndexDirty or socialCacheDirty then
        RebuildPositiveIndex()
    end

    wipe(activePlatesByUnit)
    wipe(activePlateUnitByGuid)
    activePlateCount = 0

    local nowClock = (GetTime and GetTime()) or time()
    local crowdCooldown = GetBystanderCooldownSeconds()
    local hasPlatesApi = false
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            hasPlatesApi = true
            activePlateCount = #plates
            crowdCooldown = GetBystanderCooldownSeconds()
            local allowSubTarget = not IsCrowdMode()
            for _, plate in ipairs(plates) do
                if IsPlateAccessible(plate) then
                    local unit = Safe.String(plate.namePlateUnitToken)
                    if not unit and plate.UnitFrame then
                        unit = Safe.String(plate.UnitFrame.unit)
                    end
                    if unit and Safe.Value(Safe.Call(UnitExists, unit)) == true then
                        activePlatesByUnit[unit] = plate
                        local pGuid = Safe.String(Safe.Call(UnitGUID, unit))
                        if pGuid and pGuid ~= "" then
                            activePlateUnitByGuid[pGuid] = unit
                        end
                        if Safe.Value(Safe.Call(UnitIsPlayer, unit)) == true then
                            local skipGroup = (s.spotterIgnoreGroup ~= false and next(self.manualTracked) == nil)
                                and (Safe.Value(Safe.Call(UnitInRaid, unit)) == true or Safe.Value(Safe.Call(UnitInParty, unit)) == true)
                            if not skipGroup then
                                local knownEntry = pGuid and self.entryByGuid[pGuid] or nil
                                if knownEntry and self.entries[knownEntry.key] == knownEntry then
                                    self.visibleUnits[unit] = knownEntry.key
                                    self:UpdatePlateBadge(plate, unit, knownEntry)
                                else
                                    HidePlateBadge(unit, plate)
                                end
                                local rName = Safe.String(Safe.Call(UnitName, unit))
                                if rName and rName ~= "Unknown" then
                                    local passedGate, confirmedNoMatch = QuickCandidateGate(unit, pGuid, rName)
                                    if passedGate then
                                        EnqueueInspection(unit, true, fromTicker)
                                    elseif pGuid then
                                        RecordGateMissCooldown(pGuid, confirmedNoMatch, nowClock)
                                    end
                                end
                            else
                                HidePlateBadge(unit, plate)
                            end
                        else
                            HidePlateBadge(unit, plate)
                        end
                        if allowSubTarget then
                            local npTarget = unit .. "target"
                            if Safe.Value(Safe.Call(UnitExists, npTarget)) == true and Safe.Value(Safe.Call(UnitIsPlayer, npTarget)) == true then
                                local ntGuid = Safe.String(Safe.Call(UnitGUID, npTarget))
                                local ntName = Safe.String(Safe.Call(UnitName, npTarget))
                                if ntName and ntName ~= "Unknown" and QuickCandidateGate(npTarget, ntGuid, ntName) then
                                    EnqueueInspection(npTarget, false, fromTicker)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not hasPlatesApi then
        for i = 1, 40 do
            local unit = "nameplate" .. i
            if Safe.Value(Safe.Call(UnitExists, unit)) == true then
                activePlateCount = activePlateCount + 1
                if Safe.Value(Safe.Call(UnitIsPlayer, unit)) == true then
                    local pGuid = Safe.String(Safe.Call(UnitGUID, unit))
                    local rName = Safe.String(Safe.Call(UnitName, unit))
                    if rName and rName ~= "Unknown" then
                        local passedGate, confirmedNoMatch = QuickCandidateGate(unit, pGuid, rName)
                        if passedGate then
                            EnqueueInspection(unit, true, fromTicker)
                        elseif pGuid then
                            RecordGateMissCooldown(pGuid, confirmedNoMatch, nowClock)
                        end
                    end
                end
            end
        end
    end

    for _, token in ipairs(LIVE_TOKEN_LIST) do
        if Safe.Value(Safe.Call(UnitExists, token)) == true and Safe.Value(Safe.Call(UnitIsPlayer, token)) == true then
            if token == "target" or token == "focus" then
                self:InspectUnit(token, false, fromTicker, true, true)
            else
                local lGuid = Safe.String(Safe.Call(UnitGUID, token))
                local lName = Safe.String(Safe.Call(UnitName, token))
                if lName and lName ~= "Unknown" and QuickCandidateGate(token, lGuid, lName) then
                    EnqueueInspection(token, false, fromTicker)
                end
            end
        end
    end

    if (s.spotterIgnoreGroup == false or next(self.manualTracked) ~= nil) and Compat.IsInGroup and Compat.IsInGroup() then
        local inRaid = Compat.IsInRaid and Compat.IsInRaid()
        local numMembers = Compat.GetNumGroupMembers and Compat.GetNumGroupMembers() or 0
        local prefix = inRaid and "raid" or "party"
        local limit = inRaid and math.min(40, numMembers) or math.min(4, numMembers)
        for i = 1, limit do
            local token = prefix .. i
            if Safe.Value(Safe.Call(UnitExists, token)) == true and Safe.Value(Safe.Call(UnitIsVisible, token)) == true then
                local mGuid = Safe.String(Safe.Call(UnitGUID, token))
                local mName = Safe.String(Safe.Call(UnitName, token))
                if mName and mName ~= "Unknown" and QuickCandidateGate(token, mGuid, mName) then
                    EnqueueInspection(token, false, fromTicker)
                end
            end
        end
    end

    local staleUnits
    for boundUnit in pairs(activePlatesByUnit) do
        local p = activePlatesByUnit[boundUnit]
        local k = self.visibleUnits[boundUnit]
        if not p or not k or not self.entries[k] then
            if not staleUnits then staleUnits = {} end
            table.insert(staleUnits, boundUnit)
        end
    end
    if staleUnits then
        for _, u in ipairs(staleUnits) do
            HidePlateBadge(u, nil)
        end
    end
    self:UpdateFocusedPlateMarker()
end

function Spotter:ReconcileGroupEntries()
    if not self:IsEnabled() or next(self.entries) == nil then
        return
    end
    local s = ns.db and ns.db.settings
    if s and s.spotterIgnoreGroup == false then
        return
    end
    local removedAny = false
    for key, entry in pairs(self.entries) do
        if ShouldIgnoreGroupUnit(nil, key, entry.guid) then
            if entry.guid then
                self.entryByGuid[entry.guid] = nil
            end
            self.entries[key] = nil
            if self.lastAlert and self.lastAlert.key == key then
                self.lastAlert = nil
            end
            for unit, uKey in pairs(self.visibleUnits) do
                if uKey == key then
                    self.visibleUnits[unit] = nil
                end
            end
            removedAny = true
        end
    end
    if removedAny then
        RecomputeOnScreenFlags()
        MarkTargetsDirty()
        self:QueueBatchEmit(true)
    end
end

function Spotter:ReclassifyActiveEntries()
    if not self:IsEnabled() then
        return
    end
    RebuildPositiveIndex()
    local rekeyed = {}
    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    local now = time()
    for key, entry in pairs(self.entries) do
        local ignored = ShouldIgnoreGroupUnit(nil, key, entry.guid)
        local dismissed = (not self.manualTracked[key]) and self.dismissedUntil[key] and now < self.dismissedUntil[key]
        local stance, resolvedReason, updatedGuild
        if not ignored and not dismissed then
            local isOppositeHostile = IsUnitOppositeOrHostile(nil, entry.faction)
            local isMyGuildMember, knownGuild, _, _, isWatched, isFriend, watchNote, isBlocked = LookupKnownPlayerGuildOrMembership(entry.firstName, entry.displayName, entry.guid)
            local gName = (entry.guild and entry.guild ~= "") and entry.guild or knownGuild
            if isOppositeHostile then
                isMyGuildMember = false
                isFriend = false
                if gName and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) == myNormGuild then
                    gName = nil
                    entry.guild = nil
                end
            elseif gName and gName ~= "" and myNormGuild and myNormGuild ~= "" and NormalizeKeyPart(gName) ~= myNormGuild then
                isMyGuildMember = false
            end
            local rawStance, dipEntry = self:ClassifyGuild(gName)
            if isOppositeHostile and (rawStance == "SAME" or rawStance == "ALLY") then
                rawStance = nil
                dipEntry = nil
            end
            stance, resolvedReason, updatedGuild = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, isBlocked, watchNote, key, myNormGuild, myGuildName, gName, isOppositeHostile)
            if updatedGuild and updatedGuild ~= "" then
                entry.guild = updatedGuild
            end
        end
        if not stance then
            if entry.guid then
                self.entryByGuid[entry.guid] = nil
            end
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
                        entry.surname = parsed.surname or entry.surname
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
        MigrateEntryStateKey(self, oldKey, entry.key, entry)
    end

    for unit, key in pairs(self.visibleUnits) do
        if not self.entries[key] then
            self.visibleUnits[unit] = nil
        end
    end

    RecomputeOnScreenFlags()
    MarkTargetsDirty()
    self:RefreshVisibleNameplates()
    ns:Emit("SPOTTER_UPDATED")
end

function Spotter:OnGuildChanged()
    if not self:IsEnabled() then
        return
    end
    local currentScope = ns.Clan and ns.Clan.GetActiveScopeToken and ns.Clan:GetActiveScopeToken() or ""
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true

    if not inGuild and self.lastScopeToken and self.lastScopeToken ~= "" then
        self._cachedPlayerGuild = nil
        self._cachedPlayerGuildNorm = nil
        self:Clear(true)
        if Compat.ClearGuildMembers then Compat.ClearGuildMembers() end
        self.lastScopeToken = ""
        return
    end

    if self.lastScopeToken and self.lastScopeToken ~= "" and currentScope ~= "" and self.lastScopeToken ~= currentScope then
        self._cachedPlayerGuild = nil
        self._cachedPlayerGuildNorm = nil
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
    wipe(self.entryByGuid)
    wipe(self.visibleUnits)
    wipe(self.alertCooldowns)
    wipe(self.dismissedUntil)
    wipe(self.toastExpiredUntil)
    wipe(self.manualTracked)
    wipe(self.manualTrackedStance)
    wipe(chatCooldown)
    wipe(chatPrev)
    chatCooldownCount = 0
    wipe(inspectQUnit)
    wipe(inspectQPlate)
    wipe(inspectQTicker)
    wipe(inspectQueuedSet)
    inspectQueueHead = 1
    inspectQueueTail = 0
    inspectQueueTimerActive = false
    wipe(unknownRetryUnits)
    unknownRetryCount = 0
    InvalidateBystanderCache()
    MarkPositiveIndexDirty()
    MarkTargetsDirty()
    self.lastAlert = nil
    HideAllPlateBadges()
    if self.targetArrowFrame then
        self.targetArrowFrame:Hide()
    end

    if not silent then
        ns:Emit("SPOTTER_UPDATED")
    end
end

function Spotter:ClearTargetsOnLocationChange()
    local hadEntries = next(self.entries) ~= nil
    wipe(self.entries)
    wipe(self.entryByGuid)
    wipe(self.visibleUnits)
    wipe(self.toastExpiredUntil)
    wipe(self.manualTracked)
    wipe(self.manualTrackedStance)
    wipe(activePlatesByUnit)
    wipe(activePlateUnitByGuid)
    activePlateCount = 0
    wipe(pendingPlateUnits)
    wipe(chatCooldown)
    wipe(chatPrev)
    chatCooldownCount = 0
    wipe(inspectQUnit)
    wipe(inspectQPlate)
    wipe(inspectQTicker)
    wipe(inspectQueuedSet)
    inspectQueueHead = 1
    inspectQueueTail = 0
    inspectQueueTimerActive = false
    wipe(unknownRetryUnits)
    unknownRetryCount = 0
    InvalidateBystanderCache()
    MarkTargetsDirty()
    self.lastAlert = nil
    HideAllPlateBadges()
    if self.targetArrowFrame then
        self.targetArrowFrame:Hide()
    end
    if ns.SpotterHUD then
        ns.SpotterHUD.focusedKey = nil
        ns.SpotterHUD.interactionOpen = false
        ns.SpotterHUD.interactionKey = nil
        ns.SpotterHUD._compassEntry = nil
        ns.SpotterHUD._lastCompassEntryKey = nil
        ns.SpotterHUD.manualPinnedEmpty = false
        ns.SpotterHUD.userClosed = false
        if ns.SpotterHUD.Hide then
            ns.SpotterHUD:Hide()
        end
    end
    if hadEntries then
        ns:Emit("SPOTTER_UPDATED")
    end
end

function Spotter:DismissTarget(key)
    if not key or not self.entries[key] then return false end
    local removed = self.entries[key]
    if removed and removed.guid then
        self.entryByGuid[removed.guid] = nil
    end
    self.entries[key] = nil
    self.manualTracked[key] = nil
    self.manualTrackedStance[key] = nil
    self.dismissedUntil[key] = time() + DISMISS_COOLDOWN_SECONDS
    for unit, uKey in pairs(self.visibleUnits) do
        if uKey == key then
            self.visibleUnits[unit] = nil
            HidePlateBadge(unit, nil)
        end
    end
    MarkTargetsDirty()
    self:UpdateFocusedPlateMarker()
    ns:Emit("SPOTTER_UPDATED")
    return true
end

function Spotter:FindLiveUnitForEntry(entry)
    if not entry then return nil, nil end

    local plate, plateUnit = ResolvePlateForUnitOrEntry(nil, entry)
    if plateUnit then
        return plateUnit, plate
    end

    for _, token in ipairs(LIVE_TOKEN_LIST) do
        if UnitMatchesEntry(token, entry) then
            local tPlate = ResolvePlateForUnitOrEntry(token, entry)
            return token, tPlate
        end
    end

    local groupToken = GetCachedGroupUnitToken(entry.key, entry.guid)
    if groupToken then
        if UnitMatchesEntry(groupToken, entry) then
            return groupToken, ResolvePlateForUnitOrEntry(groupToken, entry)
        end
        local groupSubTarget = groupToken .. "target"
        if UnitMatchesEntry(groupSubTarget, entry) then
            return groupSubTarget, ResolvePlateForUnitOrEntry(groupSubTarget, entry)
        end
    end

    local nowClock = (GetTime and GetTime()) or time()
    if (not IsCrowdMode()) and ((not entry._lastPlateTargetAt) or (nowClock - entry._lastPlateTargetAt) >= 1.5) then
        entry._lastPlateTargetAt = nowClock
        for pUnit, _ in pairs(activePlatesByUnit) do
            local npTarget = pUnit .. "target"
            if UnitMatchesEntry(npTarget, entry) then
                return npTarget, ResolvePlateForUnitOrEntry(npTarget, entry)
            end
        end
    end

    return nil, nil
end

function Spotter:GetTargetKinematics(entry)
    if not entry then return nil end

    local nowClock = (GetTime and GetTime()) or time()
    local isSelected = (Safe.Value(Safe.Call(UnitExists, "target")) == true) and UnitMatchesEntry("target", entry)

    local unit = nil
    local distYards, distText
    local bothStopped = false
    if isSelected then
        unit = "target"
        entry.lastSeen = time()
        entry.dead = (Safe.Value(Safe.Call(UnitIsDeadOrGhost, "target")) == true)
        local uName = Safe.String(Safe.Call(UnitName, "target"))
        if uName and uName ~= "" then
            entry.unitName = uName
        end

        if GetUnitSpeed then
            local pSpd = Safe.Number(Safe.Call(GetUnitSpeed, "player")) or 0
            local tSpd = Safe.Number(Safe.Call(GetUnitSpeed, "target")) or 0
            bothStopped = (pSpd == 0 and tSpd == 0)
        end

        local groupUnit = GetCachedGroupUnitToken(entry.key, entry.guid)
        if groupUnit and UnitDistanceSquared then
            local dSq, checked = Safe.Call(UnitDistanceSquared, groupUnit)
            dSq = Safe.Number(dSq)
            if Safe.Value(checked) == true and dSq and dSq >= 0 then
                distYards = math.floor(math.sqrt(dSq) + 0.5)
            end
        end

        if not distYards then
            local distInterval = bothStopped and 0.85 or ((entry.lastDistYards and entry.lastDistYards > 28) and 0.40 or 0.22)
            if not entry._lastDistCheckAt or (nowClock - entry._lastDistCheckAt) >= distInterval then
                entry._lastDistCheckAt = nowClock
                local mYards, mText = MeasureUnitDistance("target")
                if mYards and mText then
                    distYards = mYards
                    distText = mText
                    if entry.lastDistYards ~= mYards then
                        sortedTargetsDirty = true
                    end
                    entry.lastDistYards = mYards
                    entry.lastDistText = mText
                end
            end
            if not distText then
                distText = entry.lastDistText
                distYards = entry.lastDistYards
            end
        else
            distText = string.format("%dm", distYards)
            if entry.lastDistYards ~= distYards then
                sortedTargetsDirty = true
            end
            entry.lastDistText = distText
            entry.lastDistYards = distYards
        end
    else
        entry.lastDistYards = nil
        entry.lastDistText = nil
        distYards = nil
        distText = nil
    end

    if isSelected and (not entry._lastLocSyncAt or (nowClock - entry._lastLocSyncAt) >= 4.0) then
        entry._lastLocSyncAt = nowClock
        UpdateEntryZoneInfo(entry)
    end

    local kin = entry._kinematics
    if not kin then
        kin = {}
        entry._kinematics = kin
    end
    kin.unit = unit
    kin.isSelected = isSelected == true
    kin.stationary = bothStopped
    kin.distYards = isSelected and (distYards or entry.lastDistYards) or nil
    kin.distText = isSelected and (distText or entry.lastDistText or L["Nearby"]) or nil
    kin.exact = isSelected and (distYards ~= nil) or false
    return kin
end

function Spotter:CleanupAbsentTargets(silent)
    local now = time()
    local changed = false

    for uTok, uKey in pairs(self.visibleUnits) do
        local exists = Safe.Value(Safe.Call(UnitExists, uTok))
        local mappedEntry = uKey and self.entries[uKey] or nil
        if exists ~= true or not mappedEntry or not UnitMatchesEntry(uTok, mappedEntry) then
            self.visibleUnits[uTok] = nil
            HidePlateBadge(uTok, nil)
            changed = true
        end
    end
    if changed then
        RecomputeOnScreenFlags()
    end

    for key, exp in pairs(self.dismissedUntil) do
        if now >= exp then
            self.dismissedUntil[key] = nil
        end
    end
    for key, exp in pairs(self.toastExpiredUntil) do
        if now >= exp then
            self.toastExpiredUntil[key] = nil
        end
    end

    local maxAlertCooldown = math.max(ENEMY_ALERT_COOLDOWN, FRIENDLY_ALERT_COOLDOWN)
    for key, alertAt in pairs(self.alertCooldowns) do
        if (now - alertAt) >= maxAlertCooldown then
            self.alertCooldowns[key] = nil
        end
    end

    local tExists = Safe.Value(Safe.Call(UnitExists, "target")) == true
    local fExists = Safe.Value(Safe.Call(UnitExists, "focus")) == true
    local mExists = Safe.Value(Safe.Call(UnitExists, "mouseover")) == true
    local tGuid = tExists and Safe.String(Safe.Call(UnitGUID, "target")) or nil
    local fGuid = fExists and Safe.String(Safe.Call(UnitGUID, "focus")) or nil
    local mGuid = mExists and Safe.String(Safe.Call(UnitGUID, "mouseover")) or nil

    local toastDur = GetSpotterToastDuration()
    local curZone = Compat.CurrentZoneName and Compat.CurrentZoneName() or nil
    local hudFrame = ns.SpotterHUD and ns.SpotterHUD.frame
    local hudHovered = hudFrame and hudFrame:IsShown() and hudFrame.IsMouseOver and hudFrame:IsMouseOver() == true
    local hudDrawerOpen = ns.SpotterHUD and ns.SpotterHUD.interactionOpen == true

    local hasLiveObs = false
    local minRemaining = 5.0

    for key, entry in pairs(self.entries) do
        local isCurTarget = false
        if tExists then
            if entry.guid and tGuid then
                isCurTarget = (entry.guid == tGuid)
            else
                isCurTarget = UnitMatchesEntry("target", entry)
            end
        end
        local isCurFocus = false
        if fExists and not isCurTarget then
            if entry.guid and fGuid then
                isCurFocus = (entry.guid == fGuid)
            else
                isCurFocus = UnitMatchesEntry("focus", entry)
            end
        end
        local isCurMouseover = false
        if mExists and not isCurTarget and not isCurFocus then
            if entry.guid and mGuid then
                isCurMouseover = (entry.guid == mGuid)
            else
                isCurMouseover = UnitMatchesEntry("mouseover", entry)
            end
        end

        local isHudFocused = hudHovered or (hudDrawerOpen and (not ns.SpotterHUD.interactionKey or ns.SpotterHUD.interactionKey == key))
        if isCurTarget or isCurFocus or isCurMouseover or isHudFocused then
            entry.toastShownAt = now
            entry.lastSeen = now
            hasLiveObs = true
        elseif entry.onScreen then
            hasLiveObs = true
        end

        local zoneLeft = (curZone and curZone ~= "" and entry.zone and entry.zone ~= "" and entry.zone ~= curZone)
            and not entry.onScreen
            and not isCurTarget
            and not isCurFocus
            and not isCurMouseover

        local toastAge = now - (entry.toastShownAt or entry.firstSeen or entry.lastSeen or now)
        local seenAge = now - (entry.lastSeen or now)
        local toastWithinDur = (toastAge < toastDur) and (entry.onScreen or seenAge <= toastDur)

        local keep
        if zoneLeft then
            keep = false
        elseif entry.dead and seenAge > 3 and not isCurTarget then
            keep = false
        elseif isCurTarget or isCurFocus or isCurMouseover or isHudFocused then
            keep = true
        else
            keep = toastWithinDur
        end

        if not keep then
            if toastAge >= toastDur and not zoneLeft then
                self.toastExpiredUntil[key] = now + math.max(45, toastDur * 3)
            end
            for uTok, uKey in pairs(self.visibleUnits) do
                if uKey == key then
                    self.visibleUnits[uTok] = nil
                    HidePlateBadge(uTok, nil)
                end
            end
            if entry.guid then
                self.entryByGuid[entry.guid] = nil
            end
            self.entries[key] = nil
            self.manualTracked[key] = nil
            self.manualTrackedStance[key] = nil
            if self.lastAlert and self.lastAlert.key == key then
                self.lastAlert = nil
            end
            changed = true
        elseif not hasLiveObs then
            local rem = math.max(1.0, toastDur - toastAge)
            if rem < minRemaining then
                minRemaining = rem
            end
        end
    end

    if next(self.entries) == nil and ns.SpotterHUD then
        ns.SpotterHUD.userClosed = false
    end

    if changed then
        RecomputeOnScreenFlags()
        MarkTargetsDirty()
        self:UpdateFocusedPlateMarker()
        if not silent then
            ns:Emit("SPOTTER_UPDATED")
        end
    end
    local nextDelay = hasLiveObs and 1.0 or math.max(1.0, math.min(5.0, minRemaining))
    return changed, nextDelay
end

function Spotter:MarkDemoDirty()
    countsSynced = false
    sortedTargetsDirty = true
    RecomputeOnScreenFlags()
    MarkTargetsDirty()
end

function Spotter:Prune(silent)
    if ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive() then
        return false
    end
    local changed = self:CleanupAbsentTargets(silent)
    return changed
end

function Spotter:GetCounts()
    if not countsSynced then
        local enemy, ally, same, onScreen, watchlist, friend, blocked = 0, 0, 0, 0, 0, 0, 0
        for _, entry in pairs(self.entries) do
            if entry.stance == "ENEMY" then
                enemy = enemy + 1
            elseif entry.stance == "BLOCKED" then
                blocked = blocked + 1
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
        cachedCountEnemy = enemy
        cachedCountAlly = ally
        cachedCountSame = same
        cachedCountWatchlist = watchlist
        cachedCountFriend = friend
        cachedCountBlocked = blocked
        cachedCountOnScreen = onScreen
        cachedCountTotal = enemy + blocked + ally + same + watchlist + friend
        countsSynced = true
    end
    return cachedCountEnemy, cachedCountAlly, cachedCountSame, cachedCountTotal, cachedCountOnScreen, cachedCountWatchlist, cachedCountFriend, cachedCountBlocked
end

local function ResolveManualTrackKey(rawName, guid)
    local cleanName = Safe.String(rawName)
    local cleanGuid = Safe.String(guid)
    if (not cleanName or cleanName == "") and not cleanGuid then
        return nil, cleanName, cleanGuid
    end
    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(nil, cleanGuid, cleanName)
    if (not resolved or not resolved.surname) and cleanGuid and Compat.LookupForeverFullName then
        resolved = Compat.LookupForeverFullName(cleanGuid, cleanName, false) or resolved
    end
    local bestFullName = (resolved and resolved.fullName) or cleanName
    local lk
    if bestFullName and Compat.ParseCharacterFields then
        lk = Compat.ParseCharacterFields(bestFullName)
    elseif bestFullName and Compat.ParseCharacterName then
        local parsed = Compat.ParseCharacterName(bestFullName)
        lk = parsed and parsed.lookupKey
    end
    local key = (lk and lk ~= "" and lk) or (bestFullName and NormalizeKeyPart(bestFullName))
    return (key and key ~= "") and key or nil, cleanName, cleanGuid
end

function Spotter:IsPlayerTracked(rawName, guid)
    local key = ResolveManualTrackKey(rawName, guid)
    return key ~= nil and self.manualTracked and self.manualTracked[key] == true
end

function Spotter:UntrackPlayer(rawName, guid)
    local key = ResolveManualTrackKey(rawName, guid)
    if not key then
        return false
    end
    self.manualTracked[key] = nil
    self.manualTrackedStance[key] = nil
    self.dismissedUntil[key] = nil
    if self.entries and self.entries[key] then
        local removed = self.entries[key]
        if removed and removed.guid then
            self.entryByGuid[removed.guid] = nil
        end
        self.entries[key] = nil
        for unit, uKey in pairs(self.visibleUnits) do
            if uKey == key then
                self.visibleUnits[unit] = nil
                HidePlateBadge(unit, nil)
            end
        end
        MarkTargetsDirty()
        self:UpdateFocusedPlateMarker()
    end
    if ns.SpotterHUD and ns.SpotterHUD.focusedKey == key then
        ns.SpotterHUD.focusedKey = nil
    end
    MarkPositiveIndexDirty()
    ns:Emit("SPOTTER_UPDATED")
    return true
end

function Spotter:TrackPlayer(rawName, rawGuild, classFile, level, guid, forcedStance)
    if not self:IsEnabled() then return nil end
    local cleanName = Safe.String(rawName)
    local cleanGuid = Safe.String(guid)
    if (not cleanName or cleanName == "") and not cleanGuid then
        return nil
    end
    if Compat.IsMe and Compat.IsMe(cleanName, cleanGuid) then
        return nil
    end

    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(nil, cleanGuid, cleanName)
    if (not resolved or not resolved.surname) and cleanGuid and Compat.LookupForeverFullName then
        resolved = Compat.LookupForeverFullName(cleanGuid, cleanName, false) or resolved
    end
    local bestFullName = (resolved and resolved.fullName) or cleanName
    local parsed = bestFullName and Compat.ParseCharacterName and Compat.ParseCharacterName(bestFullName)
    local key = (parsed and parsed.lookupKey) or NormalizeKeyPart(bestFullName)
    if not key or key == "" then return nil end

    local displayName = (parsed and parsed.displayName) or bestFullName
    local firstName = (parsed and parsed.firstName) or displayName
    local targetMacroName = SanitizeMacroTargetName(displayName, nil)
    if not targetMacroName then return nil end

    self.dismissedUntil[key] = nil
    self.toastExpiredUntil[key] = nil
    self.alertCooldowns[key] = nil
    self.manualTracked[key] = true
    if forcedStance then
        self.manualTrackedStance[key] = forcedStance
    end
    AddPositiveCandidate(displayName, cleanGuid, nil, nil, true)

    local s = ns.db and ns.db.settings
    local radarTutShown = (ns.IsAccountTutorialShown and ns:IsAccountTutorialShown("spotterRadarTutorialShown")) or (s and s.spotterRadarTutorialShown == true)
    if s and not radarTutShown then
        if ns.SetAccountTutorialShown then
            ns:SetAccountTutorialShown("spotterRadarTutorialShown", true)
        else
            s.spotterRadarTutorialShown = true
        end
        if ns.SpotterHUD and ns.SpotterHUD.ShowRadarTutorial then
            ns.SpotterHUD:ShowRadarTutorial(true)
        end
        if ns.Print then
            ns:Print("|cff70b5f9[%s]|r %s", L["Target Radar"], L["Radar active! Monitors nearby tracked players and measures distance when targeted."])
        end
    end

    local tempEntry = {
        key = key,
        guid = cleanGuid,
        firstName = firstName,
        unitName = firstName,
    }
    local liveUnit = self:FindLiveUnitForEntry(tempEntry)

    if liveUnit then
        local trackedEntry = self:InspectUnit(liveUnit, liveUnit:match("^nameplate") ~= nil, false, true, true)
        if trackedEntry and ns.SpotterHUD then
            ns.SpotterHUD.focusedKey = trackedEntry.key
            if ns.SpotterHUD.Show then
                ns.SpotterHUD:Show(true)
            end
        end
        return trackedEntry
    end

    local myNormGuild, myGuildName = GetPlayerNormalizedGuild()
    local isOppositeHostile, trackFac = IsUnitOppositeOrHostile(nil, nil)
    local isMyGuildMember, knownGuild, knownClass, knownLevel, isWatched, isFriend, watchNote, isBlocked = LookupKnownPlayerGuildOrMembership(firstName, displayName, cleanGuid)
    local gName = (rawGuild and rawGuild ~= "") and rawGuild or knownGuild
    if isOppositeHostile then
        isMyGuildMember = false
        isFriend = false
    end
    local rawStance, dipEntry = self:ClassifyGuild(gName)
    if isOppositeHostile and (rawStance == "SAME" or rawStance == "ALLY") then
        rawStance = nil
        dipEntry = nil
    end
    local stance, resolvedReason
    stance, resolvedReason, gName = ResolveEffectiveStance(rawStance, dipEntry, isMyGuildMember, isWatched, isFriend, isBlocked, watchNote, key, myNormGuild, myGuildName, gName, isOppositeHostile)
    stance = stance or forcedStance or "WATCHLIST"
    if isOppositeHostile and (stance == "SAME" or stance == "ALLY" or stance == "FRIEND") then
        stance = "WATCHLIST"
    end

    local now = time()
    local entry = self.entries[key] or { key = key, firstSeen = now }
    entry.toastShownAt = now
    self.entries[key] = entry
    if cleanGuid and cleanGuid ~= "" then
        self.entryByGuid[cleanGuid] = entry
    end
    entry.displayName = displayName
    entry.firstName = firstName
    entry.surname = (parsed and parsed.surname) or entry.surname
    entry.unitName = entry.unitName or firstName
    entry.targetName = targetMacroName
    entry.guild = gName or entry.guild
    entry.stance = stance
    entry.reason = resolvedReason or L["Target Radar"]
    entry.classFile = Safe.String(classFile) or knownClass or entry.classFile
    entry.level = (tonumber(level) and tonumber(level) > 0) and tonumber(level) or knownLevel or entry.level
    entry.guid = cleanGuid or entry.guid
    entry.lastSeen = now
    entry.lastDistYards = nil
    entry.lastDistText = nil
    entry._manualTracked = true
    entry._alertEvaluated = true
    UpdateEntryZoneInfo(entry)

    RecomputeOnScreenFlags()
    MarkTargetsDirty()
    self:EnsurePruneLoop()
    if ns.SpotterHUD then
        ns.SpotterHUD.focusedKey = key
        if ns.SpotterHUD.Show then
            ns.SpotterHUD:Show(true)
        end
    end
    ns:Emit("SPOTTER_UPDATED")
    return entry
end

local function SortTargetsComparator(a, b)
    local aAlive = (a.dead ~= true)
    local bAlive = (b.dead ~= true)
    if aAlive ~= bAlive then return aAlive end
    local aOn = (a.onScreen == true)
    local bOn = (b.onScreen == true)
    if aOn ~= bOn then return aOn end
    local pa = STANCE_PRIORITY[a.stance] or 9
    local pb = STANCE_PRIORITY[b.stance] or 9
    if pa ~= pb then return pa < pb end
    local aMan = (a._manualTracked == true)
    local bMan = (b._manualTracked == true)
    if aMan ~= bMan then return aMan end
    local ad = a.lastDistYards or 999
    local bd = b.lastDistYards or 999
    if ad ~= bd then return ad < bd end
    return (a.lastSeen or 0) > (b.lastSeen or 0)
end

function Spotter:GetActiveTargets(filterStance)
    if sortedTargetsDirty then
        wipe(sortedTargetsCache)
        for _, entry in pairs(self.entries) do
            sortedTargetsCache[#sortedTargetsCache + 1] = entry
        end
        table.sort(sortedTargetsCache, SortTargetsComparator)
        sortedTargetsDirty = false
    end
    local f = filterStance and filterStance:upper() or "ALL"
    if f == "ALL" then
        return sortedTargetsCache
    end
    local out = {}
    for _, entry in ipairs(sortedTargetsCache) do
        if entry.stance == f then
            out[#out + 1] = entry
        end
    end
    return out
end

function Spotter:RegisterEvents()
    if self._eventsRegistered then return end
    if self._eventFrame then
        local events = {
            "NAME_PLATE_UNIT_ADDED",
            "FORBIDDEN_NAME_PLATE_UNIT_ADDED",
            "NAME_PLATE_UNIT_REMOVED",
            "PLAYER_TARGET_CHANGED",
            "PLAYER_FOCUS_CHANGED",
            "UPDATE_MOUSEOVER_UNIT",
            "PLAYER_SOFT_FRIEND_CHANGED",
            "PLAYER_SOFT_ENEMY_CHANGED",
            "PLAYER_SOFT_INTERACT_CHANGED",
            "GROUP_ROSTER_UPDATE",
            "PLAYER_GUILD_UPDATE",
            "GUILD_ROSTER_UPDATE",
            "FRIENDLIST_UPDATE",
            "IGNORELIST_UPDATE",
            "BN_FRIEND_LIST_SIZE_CHANGED",
            "BN_FRIEND_INFO_CHANGED",
            "PLAYER_ENTERING_WORLD",
            "ZONE_CHANGED_NEW_AREA",
            "CHAT_MSG_SAY",
            "CHAT_MSG_YELL",
            "CHAT_MSG_EMOTE",
            "CHAT_MSG_TEXT_EMOTE",
        }
        for _, ev in ipairs(events) do
            pcall(self._eventFrame.RegisterEvent, self._eventFrame, ev)
        end
        if not (self._unitFrame and self._unitFrame.RegisterUnitEvent) then
            pcall(self._eventFrame.RegisterEvent, self._eventFrame, "UNIT_SPELLCAST_SUCCEEDED")
        end
    end
    if self._unitFrame then
        local okUnit = self._unitFrame.RegisterUnitEvent and pcall(self._unitFrame.RegisterUnitEvent, self._unitFrame, "UNIT_TARGET", "player", "target", "focus")
        if not okUnit then
            pcall(self._unitFrame.RegisterEvent, self._unitFrame, "UNIT_TARGET")
        end
        if self._unitFrame.RegisterUnitEvent then
            pcall(self._unitFrame.RegisterUnitEvent, self._unitFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
        end
    end
    self._eventsRegistered = true
end

function Spotter:UnregisterEvents()
    if not self._eventsRegistered then return end
    if self._eventFrame then
        pcall(self._eventFrame.UnregisterAllEvents, self._eventFrame)
    end
    if self._unitFrame then
        pcall(self._unitFrame.UnregisterAllEvents, self._unitFrame)
    end
    wipe(activePlatesByUnit)
    wipe(activePlateUnitByGuid)
    activePlateCount = 0
    HideAllPlateBadges()
    if self.targetArrowFrame then
        self.targetArrowFrame:Hide()
    end
    self._eventsRegistered = false
end

local function ScheduleReindexRefresh(allowVisiblePlateRefresh)
    if ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive() then return end
    MarkPositiveIndexDirty()
    InvalidateBystanderCache()
    if not Spotter:IsEnabled() then return end
    if Spotter._socialRefreshQueued or not (C_Timer and C_Timer.After) then return end
    Spotter._socialRefreshQueued = true
    C_Timer.After(0.20, function()
        Spotter._socialRefreshQueued = false
        if (ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive()) or not Spotter:IsEnabled() then return end
        if next(Spotter.entries) ~= nil then
            Spotter:ReclassifyActiveEntries()
        elseif allowVisiblePlateRefresh and not (InCombatLockdown and InCombatLockdown()) then
            Spotter:RefreshVisibleNameplates(false)
        end
    end)
end

local plateRecheckQueued = false
local function FlushPendingPlateRechecks()
    plateRecheckQueued = false
    if not Spotter:IsEnabled() then
        wipe(pendingPlateUnits)
        return
    end
    local updatedTarget = false
    for capUnit in pairs(pendingPlateUnits) do
        pendingPlateUnits[capUnit] = nil
        local pl = activePlatesByUnit[capUnit]
        if pl then
            local key = Spotter.visibleUnits[capUnit]
            local entry = key and Spotter.entries[key] or nil
            if entry or (Safe.Value(Safe.Call(UnitIsUnit, capUnit, "target")) == true) then
                Spotter:UpdatePlateBadge(pl, capUnit, entry)
                updatedTarget = true
            end
        end
    end
    if updatedTarget then
        Spotter:UpdateFocusedPlateMarker()
    end
end

function Spotter:Init()
    self.lastScopeToken = ns.Clan and ns.Clan.GetActiveScopeToken and ns.Clan:GetActiveScopeToken() or ""

    if not self._eventFrame then
        local ef = CreateFrame("Frame")
        ef:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, _, _, _, _, _, _, _, _, arg12)
            if (ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive()) or not Spotter:IsEnabled() then
                return
            end
            if event == "NAME_PLATE_UNIT_ADDED" then
                local unit = Safe.String(arg1)
                if not unit then return end
                local pGuid = nil
                local addedPlate = nil
                if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
                    local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
                    if okP and IsPlateAccessible(plate) then
                        addedPlate = plate
                        if not activePlatesByUnit[unit] then
                            activePlateCount = activePlateCount + 1
                        end
                        activePlatesByUnit[unit] = plate
                        pGuid = Safe.String(Safe.Call(UnitGUID, unit))
                        if pGuid and pGuid ~= "" then
                            activePlateUnitByGuid[pGuid] = unit
                        end
                    end
                end
                local insp = Spotter:InspectUnit(unit, true, false, false, false, pGuid)
                if not insp and pGuid and Spotter.entryByGuid[pGuid] and addedPlate then
                    local knownEntry = Spotter.entryByGuid[pGuid]
                    if Spotter.entries[knownEntry.key] == knownEntry then
                        Spotter.visibleUnits[unit] = knownEntry.key
                        Spotter:UpdatePlateBadge(addedPlate, unit, knownEntry)
                    end
                end
                if addedPlate and (insp or Spotter.visibleUnits[unit] or Safe.Value(Safe.Call(UnitIsUnit, unit, "target")) == true) and C_Timer and C_Timer.After then
                    pendingPlateUnits[unit] = true
                    if not plateRecheckQueued then
                        plateRecheckQueued = true
                        C_Timer.After(0, FlushPendingPlateRechecks)
                    end
                end
            elseif event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
                local unit = Safe.String(arg1)
                if unit then
                    if activePlatesByUnit[unit] then
                        activePlateCount = math.max(0, activePlateCount - 1)
                    end
                    activePlatesByUnit[unit] = nil
                    HidePlateBadge(unit, nil)
                end
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                local unit = Safe.String(arg1)
                if unit then
                    local pGuid = Safe.String(Safe.Call(UnitGUID, unit))
                    if pGuid and activePlateUnitByGuid[pGuid] == unit then
                        activePlateUnitByGuid[pGuid] = nil
                    end
                    local removedPlate = activePlatesByUnit[unit]
                    if removedPlate then
                        activePlateCount = math.max(0, activePlateCount - 1)
                    end
                    activePlatesByUnit[unit] = nil
                    HidePlateBadge(unit, removedPlate)
                    if Spotter.targetArrowFrame and (Spotter.targetArrowFrame._boundUnit == unit or (removedPlate and Spotter.targetArrowFrame._boundPlate == removedPlate)) then
                        Spotter.targetArrowFrame:Hide()
                        Spotter:UpdateFocusedPlateMarker()
                    end
                    if Spotter.visibleUnits[unit] then
                        Spotter.visibleUnits[unit] = nil
                        Spotter:QueueBatchEmit(true)
                    end
                end
            elseif event == "PLAYER_TARGET_CHANGED" then
                Spotter:InspectUnit("target", false, false, true)
                Spotter:UpdateFocusedPlateMarker()
            elseif event == "PLAYER_FOCUS_CHANGED" then
                Spotter:InspectUnit("focus", false, false, true)
            elseif event == "UPDATE_MOUSEOVER_UNIT" then
                Spotter:InspectUnit("mouseover", false, false, true)
            elseif event == "PLAYER_SOFT_FRIEND_CHANGED" then
                Spotter:InspectUnit("softfriend", false, false, false)
            elseif event == "PLAYER_SOFT_ENEMY_CHANGED" then
                Spotter:InspectUnit("softenemy", false, false, false)
            elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
                Spotter:InspectUnit("softinteract", false, false, false)
            elseif event == "GROUP_ROSTER_UPDATE" then
                groupCacheDirty = true
                if next(Spotter.entries) ~= nil then
                    if not Spotter._groupReclassQueued and C_Timer and C_Timer.After then
                        Spotter._groupReclassQueued = true
                        C_Timer.After(0.25, function()
                            Spotter._groupReclassQueued = false
                            if Spotter:IsEnabled() and next(Spotter.entries) ~= nil then
                                Spotter:ReconcileGroupEntries()
                            end
                        end)
                    end
                end
            elseif event == "PLAYER_GUILD_UPDATE" then
                if arg1 == nil or arg1 == "player" then
                    Spotter._cachedPlayerGuild = nil
                    Spotter._cachedPlayerGuildNorm = nil
                    MarkGuildPositiveDirty()
                    InvalidateBystanderCache()
                    Spotter:OnGuildChanged()
                end
            elseif event == "GUILD_ROSTER_UPDATE" then
                MarkGuildPositiveDirty()
                local nowClock = (GetTime and GetTime()) or time()
                if Spotter._lastGuildBystanderClearAt == nil or (nowClock - Spotter._lastGuildBystanderClearAt) >= 5 then
                    Spotter._lastGuildBystanderClearAt = nowClock
                    InvalidateBystanderCache()
                end
                if Spotter._lastGuildReclassAt == nil or (nowClock - Spotter._lastGuildReclassAt) >= 15 then
                    Spotter._lastGuildReclassAt = nowClock
                    if next(Spotter.entries) ~= nil then
                        Spotter:ReclassifyActiveEntries()
                    end
                end
            elseif event == "IGNORELIST_UPDATE" or event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_LIST_SIZE_CHANGED" then
                ScheduleReindexRefresh(true)
            elseif event == "BN_FRIEND_INFO_CHANGED" then
                local nowClock = (GetTime and GetTime()) or time()
                if Spotter._lastBnetReclassAt == nil or (nowClock - Spotter._lastBnetReclassAt) >= 3.0 then
                    Spotter._lastBnetReclassAt = nowClock
                    ScheduleReindexRefresh(false)
                end
            elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
                inInstanceCached = nil
                local curZone = Compat.CurrentZoneName and Compat.CurrentZoneName() or ""
                if event == "PLAYER_ENTERING_WORLD" then
                    Spotter._lastActiveZone = (curZone ~= "" and curZone) or Spotter._lastActiveZone
                    Spotter:ClearTargetsOnLocationChange()
                    MarkPositiveIndexDirty()
                    groupCacheDirty = true
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0.6, function()
                            if Spotter:IsEnabled() then
                                Spotter._lastActiveZone = (Compat.CurrentZoneName and Compat.CurrentZoneName()) or Spotter._lastActiveZone
                                Spotter:RefreshVisibleNameplates(false)
                            end
                        end)
                    end
                else
                    local prevZone = Spotter._lastActiveZone
                    if curZone ~= "" then
                        Spotter._lastActiveZone = curZone
                    end
                    if (prevZone and prevZone ~= "" and curZone ~= "" and prevZone ~= curZone) or next(Spotter.entries) ~= nil then
                        Spotter:ClearTargetsOnLocationChange()
                        if C_Timer and C_Timer.After then
                            C_Timer.After(0.4, function()
                                if Spotter:IsEnabled() then
                                    Spotter:RefreshVisibleNameplates(false)
                                end
                            end)
                        end
                    end
                end
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if arg1 == "player" then
                    local spellId = Safe.Number(arg3) or Safe.Number(arg2)
                    if spellId and TELEPORT_SPELL_IDS[spellId] then
                        Spotter:ClearTargetsOnLocationChange()
                        if C_Timer and C_Timer.After then
                            C_Timer.After(0.8, function()
                                if Spotter:IsEnabled() then
                                    Spotter:RefreshVisibleNameplates(false)
                                end
                            end)
                        end
                    end
                end
            elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
                Spotter:InspectChatSighting(arg2, arg12)
            end
        end)
        self._eventFrame = ef
    end

    if not self._unitFrame then
        local uf = CreateFrame("Frame")
        uf:SetScript("OnEvent", function(_, ev, unitTarget, _, arg3)
            if (ns.DemoShowcase and ns.DemoShowcase.IsActive and ns.DemoShowcase:IsActive()) or not Spotter:IsEnabled() then return end
            if ev == "UNIT_SPELLCAST_SUCCEEDED" then
                if unitTarget == "player" then
                    local spellId = Safe.Number(arg3)
                    if spellId and TELEPORT_SPELL_IDS[spellId] then
                        Spotter:ClearTargetsOnLocationChange()
                        if C_Timer and C_Timer.After then
                            C_Timer.After(0.8, function()
                                if Spotter:IsEnabled() then
                                    Spotter:RefreshVisibleNameplates(false)
                                end
                            end)
                        end
                    end
                end
                return
            end
            if unitTarget == "player" then
                Spotter:InspectUnit("target", false, false, true)
            elseif unitTarget == "target" then
                Spotter:InspectUnit("targettarget", false, false, false)
            elseif unitTarget == "focus" then
                Spotter:InspectUnit("focustarget", false, false, false)
            end
        end)
        self._unitFrame = uf
    end

    if not self._hooksInitialized then
        self._hooksInitialized = true
        ns:On("SETTINGS_UPDATED", function()
            MarkPositiveIndexDirty()
            InvalidateBystanderCache()
            if Spotter:IsEnabled() then
                Spotter:RegisterEvents()
                CacheRangeCheckItems()
                local s = ns.db and ns.db.settings
                if s and s.spotterNameplateBadges == false then
                    HideAllPlateBadges()
                end
                if s and s.spotterNameplateArrow == false and Spotter.targetArrowFrame then
                    Spotter.targetArrowFrame:Hide()
                end
                if next(Spotter.entries) ~= nil then
                    Spotter:ReclassifyActiveEntries()
                elseif C_Timer and C_Timer.After then
                    C_Timer.After(0.05, function()
                        if Spotter:IsEnabled() then
                            Spotter:RefreshVisibleNameplates(false)
                        end
                    end)
                end
                Spotter:UpdateFocusedPlateMarker()
            else
                Spotter:UnregisterEvents()
                Spotter:Clear(false)
            end
        end)

        local function OnSocialOrDiplomacyChanged()
            ScheduleReindexRefresh(true)
        end
        ns:On("SOCIAL_UPDATED", OnSocialOrDiplomacyChanged)
        ns:On("WATCHLIST_UPDATED", OnSocialOrDiplomacyChanged)
        ns:On("CLAN_DIPLOMACY_UPDATED", OnSocialOrDiplomacyChanged)
        ns:On("ACCOUNT_IGNORES_UPDATED", OnSocialOrDiplomacyChanged)
    end

    if self:IsEnabled() then
        RebuildPositiveIndex()
        self:RegisterEvents()
        CacheRangeCheckItems()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function()
                if Spotter:IsEnabled() then
                    Spotter:RefreshVisibleNameplates(false)
                end
            end)
        end
    else
        self:UnregisterEvents()
        self:Clear(true)
    end
end

ns.Spotter = Spotter
table.insert(ns.modules, Spotter)
