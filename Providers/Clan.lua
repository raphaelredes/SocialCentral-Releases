local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat
local Store = ns.Store

-- Clan Hub & DBM-style Peer Version Check provider.
-- Features:
--   1. Shared Clan Status Tags (opt-in GUILD addon messaging, strictly rate-limited).
--   2. Guild Event Calls & Dungeon/Raid Signups (opt-in GUILD addon messaging).
--   3. Passive rate-limited Peer Version Detection (VH/VR on GUILD/group, toggleable).
-- Every outgoing message respects InCombatLockdown(), InChatMessagingLockdown(),
-- AreOutgoingAddonChatMessagesRestricted(), MAX_PAYLOAD_BYTES, and throttle circuit-breakers.
local Clan = {
    PREFIX = "SCentral1",
    MIN_SEND_INTERVAL = 5,
    VERSION_MIN_INTERVAL = 60,
    MAX_PAYLOAD_BYTES = 240,
    MAX_EXTERNAL_LFG = 40,
    MAX_GLOBAL_CHAT_LFG = 35,
    MAX_ROSTER_HISTORY = 40,
    MAX_PASSIVE_PROFS = 100,
    PASSIVE_PROF_TTL = 6 * 3600,
    lastSyncSentAt = 0,
    lastAlfgSentAt = 0,
    lastAlfgRelayAt = 0,
    lastAlmRelayAt = 0,
    lastVersionSentAt = 0,
    lastReqReplyAt = 0,
    lastIntelReplyAt = 0,
    lastCalendarRefreshAt = 0,
    lastClanSoundAt = 0,
    isStoppedThisSession = false,
    throttledCount = 0,
    throttleStrike = 0,
    backoffUntil = 0,
    unreadAlertsCount = 0,
    latestRemoteVersion = nil,
    latestReportedBy = nil,
    notifiedVersion = nil,
    peerVersions = {},
    lfgAlertCooldowns = {},
    signupAlertCooldowns = {},
    seenAllianceRelay = {},
    externalLFG = {},
    calendarEvents = {},
    preferredRightView = nil,
    intelQueue = {},
    activeScopeToken = nil,
}

local function PlayClanAlertSound(self, kit)
    local nowMono = GetTime and GetTime() or time()
    if (nowMono - (self.lastClanSoundAt or 0)) < 2.5 then
        return
    end
    local resolvedKit = kit or (SOUNDKIT and (SOUNDKIT.MAP_PING or 3175)) or 3175
    if PlaySound and resolvedKit then
        self.lastClanSoundAt = nowMono
        pcall(PlaySound, resolvedKit, "Master")
    end
end

local function RecordClanThrottleStrike(self)
    local monoNow = GetTime and GetTime() or 0
    local nextStrikes = math.max(self.throttledCount or 0, self.throttleStrike or 0) + 1
    self.throttledCount = nextStrikes
    self.throttleStrike = nextStrikes
    self.backoffUntil = monoNow + 12
    if nextStrikes >= 3 then
        self.isStoppedThisSession = true
    end
end

function Clan:GetNotificationCount()
    return self.unreadAlertsCount or 0
end

function Clan:IncrementNotificationCount(delta)
    self.unreadAlertsCount = math.max(0, (self.unreadAlertsCount or 0) + (delta or 1))
    ns:Emit("CLAN_UPDATED")
end

function Clan:ClearNotificationCount()
    if (self.unreadAlertsCount or 0) > 0 then
        self.unreadAlertsCount = 0
        ns:Emit("CLAN_UPDATED")
    end
end

local function IsClanOrLFGVisible()
    if _G.SocialCentralFrame and _G.SocialCentralFrame.IsShown and _G.SocialCentralFrame:IsShown() then
        return true
    end
    if _G.SocialCentralGuildEmbeddedFrame and _G.SocialCentralGuildEmbeddedFrame.IsShown and _G.SocialCentralGuildEmbeddedFrame:IsShown() then
        return true
    end
    if ns.LFGFrameTab and ns.LFGFrameTab.subPanel and ns.LFGFrameTab.subPanel.IsShown and ns.LFGFrameTab.subPanel:IsShown() then
        return true
    end
    return false
end

function Clan:MarkLfgUiActive()
    self._lastLfgUiActiveAt = (GetTime and GetTime()) or 0
end

local function IsGlobalLfgListenerActive()
    if IsClanOrLFGVisible() then
        Clan._lastLfgUiActiveAt = (GetTime and GetTime()) or 0
        return true
    end
    local lfgHost = _G.LFGParentFrame
    if lfgHost and lfgHost.IsShown and lfgHost:IsShown() then
        Clan._lastLfgUiActiveAt = (GetTime and GetTime()) or 0
        return true
    end
    local lastSeen = Clan._lastLfgUiActiveAt or 0
    return lastSeen > 0 and (((GetTime and GetTime()) or 0) - lastSeen) <= 300
end

local function QueueClanEmit(delay)
    if Clan._clanEmitQueued then return end
    Clan._clanEmitQueued = true
    local waitSec = tonumber(delay) or 0.8
    if C_Timer and C_Timer.After then
        C_Timer.After(waitSec, function()
            Clan._clanEmitQueued = false
            ns:Emit("CLAN_UPDATED")
        end)
    else
        Clan._clanEmitQueued = false
        ns:Emit("CLAN_UPDATED")
    end
end

local function ResolveSelfIdentity()
    local resolved = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local fullName = (resolved and resolved.fullName and resolved.fullName ~= "" and resolved.fullName)
        or Safe.String(Safe.Call(UnitName, "player"))
        or "Player"
    local cleanName = Compat.CleanInput and Compat.CleanInput(fullName) or fullName
    local lookupKey
    if Compat.ParseCharacterFields then
        local _, _, lKey = Compat.ParseCharacterFields(cleanName)
        lookupKey = lKey
    elseif Compat.ParseCharacterName then
        local p = Compat.ParseCharacterName(cleanName)
        lookupKey = p and p.lookupKey
    end
    return cleanName, lookupKey
end

local function PruneAndBoundByTimestamp(tbl, maxCount, ttlSeconds, nowTs)
    if type(tbl) ~= "table" then return end
    local count = 0
    local oldestKey, oldestTs
    for k, v in pairs(tbl) do
        local ts = (type(v) == "table" and tonumber(v.updatedAt)) or 0
        if type(v) ~= "table" or (ttlSeconds and (nowTs - ts) > ttlSeconds) then
            tbl[k] = nil
        else
            count = count + 1
            if not oldestTs or ts < oldestTs then
                oldestTs = ts
                oldestKey = k
            end
        end
    end
    if count > (maxCount or 40) and oldestKey then
        tbl[oldestKey] = nil
    end
end

local function GetGuildSocialLookupMap()
    local socialByLookup = Store and Store.socialByLookup
    if socialByLookup then
        return socialByLookup
    end
    local out = {}
    if Store and type(Store.social) == "table" then
        for _, row in pairs(Store.social) do
            if type(row) == "table" and row.sources and row.sources.guild == true and row.lookupKey then
                out[row.lookupKey] = row
            end
        end
    end
    return out
end

local function GetLiveGuildRowFromMap(socialByLookup, key)
    local row = key and socialByLookup and socialByLookup[key]
    if row and row.sources and row.sources.guild == true then
        return row
    end
    return nil
end

Clan.STATUS_TAGS = {
    { id = "NONE", labelKey = "No Status" },
    { id = "LFG", labelKey = "LFG (Looking for Group)" },
    { id = "MPLUS", labelKey = "Dungeons" },
    { id = "RAID", labelKey = "Raid Ready" },
    { id = "PVP", labelKey = "PvP / Arena" },
    { id = "LEVELING", labelKey = "Leveling / Questing" },
    { id = "CRAFTING", labelKey = "Crafting / Professions" },
    { id = "BUSY", labelKey = "Busy" },
}

Clan.EVENT_CATEGORIES = {
    { id = "DUNGEON", labelKey = "Dungeons" },
    { id = "QUEST", labelKey = "Group Quest" },
    { id = "RAID", labelKey = "Raid" },
    { id = "BOSS", labelKey = "World Boss" },
    { id = "PVP", labelKey = "PvP" },
    { id = "GUILD", labelKey = "Guild Event" },
}

Clan.ROLES = { "TANK", "HEALER", "DPS", "MAYBE", "DECLINE" }

Clan.PROFESSIONS = {
    { id = "NONE", labelKey = "None" },
    { id = "ALCHEMY", labelKey = "Alchemy" },
    { id = "BLACKSMITHING", labelKey = "Blacksmithing" },
    { id = "ENCHANTING", labelKey = "Enchanting" },
    { id = "ENGINEERING", labelKey = "Engineering" },
    { id = "HERBALISM", labelKey = "Herbalism" },
    { id = "LEATHERWORKING", labelKey = "Leatherworking" },
    { id = "MINING", labelKey = "Mining" },
    { id = "SKINNING", labelKey = "Skinning" },
    { id = "TAILORING", labelKey = "Tailoring" },
    { id = "COOKING", labelKey = "Cooking" },
    { id = "FISHING", labelKey = "Fishing" },
    { id = "FIRST_AID", labelKey = "First Aid" },
}

Clan.DUNGEON_PRESETS = {
    { id = "ENDGAME_DNG", labelKey = "Level 60 Dungeons (BRD / Strat / Scholo / DM)", category = "DUNGEON" },
    { id = "RANDOM_NORM", labelKey = "Leveling Dungeons", category = "DUNGEON" },
    { id = "ELITE_QUEST", labelKey = "Elite & Attunement Quests", category = "DUNGEON" },
    { id = "RAID_NIGHT", labelKey = "Guild Raid Run", category = "RAID" },
    { id = "WORLD_BOSS", labelKey = "World Boss", category = "BOSS" },
}

Clan.guildChatLFG = {}
Clan.globalChatLFG = {}

local function IsValidProfession(profId)
    for _, item in ipairs(Clan.PROFESSIONS) do
        if item.id == profId then return true end
    end
    return false
end

ns.Clan = Clan
table.insert(ns.modules, Clan)

local function IsValidTag(tagId)
    for _, item in ipairs(Clan.STATUS_TAGS) do
        if item.id == tagId then return true end
    end
    return false
end

local function IsValidCategory(catId)
    for _, item in ipairs(Clan.EVENT_CATEGORIES) do
        if item.id == catId then return true end
    end
    return false
end

local function IsValidRole(roleId)
    for _, r in ipairs(Clan.ROLES) do
        if r == roleId then return true end
    end
    return false
end

local function IsSaneRemoteSemVer(ver)
    if type(ver) ~= "string" then return false end
    local maj, min, pat = ver:match("^(%d+)%.(%d+)%.(%d+)$")
    if not maj then return false end
    return (tonumber(maj) or 999) <= 50 and (tonumber(min) or 999) <= 999 and (tonumber(pat) or 999) <= 999
end

local function SplitTilde(str)
    local out = {}
    local start = 1
    while true do
        local pos = str:find("~", start, true)
        if not pos then
            table.insert(out, str:sub(start))
            break
        end
        table.insert(out, str:sub(start, pos - 1))
        start = pos + 1
    end
    return out
end

-- Note: Do not pre-block on AreOutgoingAddonChatMessagesRestricted(), which returns
-- false positives on WoW Forever (16001) while SendAddonMessage works normally.
function Clan:IsMessagingLocked()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return true, "combat"
    end
    if not (C_ChatInfo or SendAddonMessage) then return true, "unavailable" end
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked == true then
            return true, "lockdown"
        end
    end
    return false, nil
end

local function TransmitAddonMessage(self, payload, channel, isVersionMsg)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not sendFn then return false end
    if channel == "GUILD" and not (IsInGuild and IsInGuild()) then return false end
    if type(payload) ~= "string" or payload == "" or #payload > self.MAX_PAYLOAD_BYTES then return false end
    if payload:find("[%c|]") then return false end

    local now = GetTime()
    if self.backoffUntil and now < self.backoffUntil then return false end
    if isVersionMsg then
        if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then
            return false
        end
        self.lastVersionSentByChannel = self.lastVersionSentByChannel or {}
        local prevChanAt = self.lastVersionSentByChannel[channel] or 0
        if (now - prevChanAt) < self.VERSION_MIN_INTERVAL then
            return false
        end
        if (now - (self.lastVersionSentAt or 0)) < self.MIN_SEND_INTERVAL then
            return false
        end
        self.lastVersionSentByChannel[channel] = now
        self.lastVersionSentAt = now
    else
        if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            return false
        end
        if channel ~= "GUILD" then
            return false
        end
        if (now - (self.lastSyncSentAt or 0)) < self.MIN_SEND_INTERVAL then
            return false
        end
        self.lastSyncSentAt = now
    end

    local ok, result = pcall(sendFn, self.PREFIX, payload, channel)
    if not ok then return false end

    if Enum and Enum.SendAddonMessageResult and type(result) == "number" then
        for name, value in pairs(Enum.SendAddonMessageResult) do
            if value == result and name:find("Throttle") then
                RecordClanThrottleStrike(self)
                return false
            end
        end
    end
    return true
end

function Clan:SendGuildSync(payload)
    return TransmitAddonMessage(self, payload, "GUILD", false)
end

local VALID_WB_SYNC_IDS = {
    dragonslayer_ony = true,
    dragonslayer_nef = true,
    warchief = true,
    stormwind = true,
    zandalar = true,
}

function Clan:SendWorldBuffSync(syncId, ts)
    if not VALID_WB_SYNC_IDS[syncId] then return false end
    local stamp = math.floor(tonumber(ts) or 0)
    if stamp <= 0 then return false end
    local shard = Compat.CleanPayloadField and Compat.CleanPayloadField((Compat.Realm and Compat.Realm()) or "", 40) or ""
    local payload = shard ~= ""
        and ("WB~%s~%d~%s"):format(syncId, stamp, shard)
        or ("WB~%s~%d"):format(syncId, stamp)
    return TransmitAddonMessage(self, payload, "GUILD", false)
end

function Clan:RequestWorldBuffCatchup()
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("buffs") then return false end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return false end
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    local monoNow = GetTime and GetTime() or 0
    if self._lastWbCatchupReqAt and (monoNow - self._lastWbCatchupReqAt) < 45 then
        return false
    end
    self._lastWbCatchupReqAt = monoNow
    return self:SendGuildSync("WBR~" .. Compat.CleanPayloadField(ns.version or "0.0.0", 24))
end

function Clan:CheckAutoCloseFullDungeonLFG()
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("clan") then
        return false
    end
    if not (ns.db and ns.db.settings and ns.db.settings.clanAutoCloseFullLfg ~= false) then
        return false
    end
    if self:IsMessagingLocked() then
        return false
    end
    local _, myKey = ResolveSelfIdentity()
    if not myKey then return false end
    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local mine = bucket and bucket.lfg and bucket.lfg[myKey]
    if type(mine) ~= "table" then
        return false
    end
    if not Compat.IsInGroup() then
        local oldNote = mine.note or ""
        if oldNote:find("%[%d/5[^%]]*%]") then
            local stripped = oldNote:gsub("%s*%[%d/5[^%]]*%]", ""):match("^%s*(.-)%s*$") or ""
            mine.note = Compat.CleanPayloadField(stripped, 44)
            mine.updatedAt = time()
            ns:Emit("CLAN_UPDATED")
        end
        return false
    end
    local numMembers = Compat.GetNumGroupMembers and Compat.GetNumGroupMembers() or 0
    local inInst, instType = Safe.Call(IsInInstance)
    if (not Compat.IsInRaid()) and (numMembers >= 5 or (inInst == true and instType == "party" and numMembers >= 5)) then
        if self:ClearMyLFG() then
            ns:Print("%s", L["Auto-closed your full Dungeon LFM listing (party complete)."])
            return true
        end
    elseif (not Compat.IsInRaid()) and numMembers >= 2 and numMembers < 5 then
        local prevMode = mine.mode
        local oldNote = mine.note or ""
        local newBracket
        if oldNote:find("%[%d/5%s*·") or oldNote:find("Need:", 1, true) then
            local counts = (ns.Group and ns.Group.GetSummaryCounts and ns.Group:GetSummaryCounts()) or { total = numMembers, TANK = 0, HEALER = 0, DAMAGER = 0 }
            local needT = math.max(0, 1 - (counts.TANK or 0))
            local needH = math.max(0, 1 - (counts.HEALER or 0))
            local needD = math.max(0, 3 - (counts.DAMAGER or 0))
            local needParts = {}
            if needT > 0 then needParts[#needParts + 1] = needT .. "T" end
            if needH > 0 then needParts[#needParts + 1] = needH .. "H" end
            if needD > 0 then needParts[#needParts + 1] = needD .. "D" end
            local needPartsStr = (#needParts > 0) and table.concat(needParts, " ") or L["Any"]
            newBracket = L["[%d/5 · Need: %s]"]:format(numMembers, needPartsStr)
        else
            newBracket = ("[%d/5]"):format(numMembers)
        end
        local newNote
        if oldNote:find("%[%d/5[^%]]*%]") then
            newNote = oldNote:gsub("%[%d/5[^%]]*%]", function()
                return newBracket
            end, 1)
        elseif oldNote ~= "" then
            newNote = newBracket .. " " .. oldNote
        else
            newNote = newBracket
        end
        newNote = Compat.CleanPayloadField(newNote, 44)
        if newNote ~= oldNote or prevMode ~= "LFM" then
            mine.mode = "LFM"
            mine.note = newNote
            mine.updatedAt = time()
            ns:Emit("CLAN_UPDATED")
            if ns.db and ns.db.settings and ns.db.settings.clanSync and IsInGuild and IsInGuild() and (GetTime() - (self.lastSyncSentAt or 0)) >= 10 then
                local payload = ("LFG~%s~%s~%s~%s~%d~%d~%s"):format(
                    ns.version or "0.0.0",
                    mine.mode,
                    mine.role or "ANY",
                    Compat.CleanPayloadField(mine.activity or "", 40),
                    tonumber(mine.keyLvl) or 0,
                    tonumber(mine.ilvl) or 0,
                    mine.note
                )
                self:SendGuildSync(payload)
            end
        end
    end
    return false
end

local function GetActiveGroupChannel()
    if not Compat.IsInGroup() then return nil end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if Compat.IsInRaid() then
        return "RAID"
    end
    return "PARTY"
end

local silentWhisperTargets = {}
local silentWhisperFilterAdded = false
local silentNotFoundPat = nil

local function BuildSilentNotFoundPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local esc = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return esc:gsub("%%%%s", "(.+)")
end

local function EnsureSilentBackgroundWhisperFilter()
    if silentWhisperFilterAdded then return end
    silentWhisperFilterAdded = true
    if not silentNotFoundPat and _G.ERR_CHAT_PLAYER_NOT_FOUND_S then
        silentNotFoundPat = BuildSilentNotFoundPattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S)
    end
    local function filterFn(_, _, msgRaw)
        if next(silentWhisperTargets) == nil then return false end
        if Safe.IsSecret and Safe.IsSecret(msgRaw) then return false end
        local msg = Safe.String(msgRaw)
        if not msg or msg == "" then return false end
        local lowerMsg = msg:lower()
        local isNotFound = (silentNotFoundPat and msg:find(silentNotFoundPat))
            or lowerMsg:find("no player named", 1, true)
            or lowerMsg:find("not currently playing", 1, true)
            or lowerMsg:find("nenhum jogador", 1, true)
            or lowerMsg:find("ningún jugador", 1, true)
            or lowerMsg:find("ningun jugador", 1, true)
        if not isNotFound then return false end

        local monoNow = GetTime and GetTime() or 0
        for key, rec in pairs(silentWhisperTargets) do
            if monoNow > (rec.expiresAt or 0) then
                silentWhisperTargets[key] = nil
            elseif lowerMsg:find(key, 1, true) then
                silentWhisperTargets[key] = nil
                if rec.lookupKey and ns.Chat then
                    ns.Chat.sessionOfflineChars = ns.Chat.sessionOfflineChars or {}
                    ns.Chat.sessionOfflineChars[rec.lookupKey] = monoNow + 90
                end
                if rec.lookupKey and Store and Store.SyncWatchlistObservation and ns.Watchlist and ns.Watchlist.GetEntry and ns.Watchlist:GetEntry(rec.lookupKey) then
                    local socRow = Store.socialByLookup and Store.socialByLookup[rec.lookupKey]
                    if not (socRow and socRow.online == true) then
                        Store:SyncWatchlistObservation(rec.displayName or rec.lookupKey, {
                            online = false,
                            source = "whisper_miss",
                        })
                    end
                end
                return true
            end
        end
        return false
    end
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        pcall(ChatFrameUtil.AddMessageEventFilter, "CHAT_MSG_SYSTEM", filterFn)
    elseif ChatFrame_AddMessageEventFilter then
        pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", filterFn)
    end
end

local function TrackSilentWhisperTarget(targetName)
    if type(targetName) ~= "string" or targetName == "" then return end
    EnsureSilentBackgroundWhisperFilter()
    local monoNow = GetTime and GetTime() or 0
    for k, rec in pairs(silentWhisperTargets) do
        if monoNow > (rec.expiresAt or 0) then
            silentWhisperTargets[k] = nil
        end
    end
    local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(targetName)
    local lk = parsed and parsed.lookupKey or targetName:lower()
    local lowSpaced = (targetName:gsub("%-", " ")):lower()
    local exp = monoNow + 3.0
    silentWhisperTargets[targetName:lower()] = { expiresAt = exp, lookupKey = lk, displayName = parsed and parsed.displayName or targetName }
    if lowSpaced ~= targetName:lower() then
        silentWhisperTargets[lowSpaced] = { expiresAt = exp, lookupKey = lk, displayName = parsed and parsed.displayName or targetName }
    end
end

local function SendExternalLFGPacket(self, payload, channel, target)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if self.backoffUntil and (GetTime and GetTime() or 0) < self.backoffUntil then return false end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return false end
    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not sendFn then return false end
    if type(payload) ~= "string" or payload == "" or #payload > self.MAX_PAYLOAD_BYTES then return false end
    if payload:find("[%c|]") then return false end

    local ok, result
    if channel == "WHISPER" then
        if type(target) ~= "string" or target == "" then return false end
        TrackSilentWhisperTarget(target)
        ok, result = pcall(sendFn, self.PREFIX, payload, "WHISPER", target)
    else
        ok, result = pcall(sendFn, self.PREFIX, payload, channel)
    end
    if not ok then return false end

    if Enum and Enum.SendAddonMessageResult and type(result) == "number" then
        for name, value in pairs(Enum.SendAddonMessageResult) do
            if value == result and name:find("Throttle") then
                RecordClanThrottleStrike(self)
                return false
            end
        end
    end
    return true
end

local function CollectExternalLFGRecipients(self, maxCount)
    local targets = {}
    local seen = {}
    local limit = maxCount or 8
    local myFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    local now = time()
    local monoNow = GetTime and GetTime() or 0

    local function IsSameFactionAndPool(lookupKey, row)
        if row then
            if row.samePool == false then return false end
            if row.sameFaction == false then return false end
            if myFaction and row.faction and row.faction ~= "" and row.faction ~= myFaction then
                return false
            end
        end
        local socRow = lookupKey and Store and Store.socialByLookup and Store.socialByLookup[lookupKey]
        if socRow then
            if socRow.samePool == false then return false end
            if socRow.sameFaction == false then return false end
            if myFaction and socRow.faction and socRow.faction ~= "" and socRow.faction ~= myFaction then
                return false
            end
        end
        return true
    end

    local function IsConfirmedLiveOnline(lookupKey, rawName, row)
        if not lookupKey or lookupKey == "" then return false end
        local offUntil = ns.Chat and ns.Chat.sessionOfflineChars and ns.Chat.sessionOfflineChars[lookupKey]
        if offUntil and monoNow < offUntil then
            return false
        end
        local dirRow = Store and Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookupKey]
        if dirRow and dirRow.online == false then
            return false
        end
        local socRow = Store and Store.socialByLookup and Store.socialByLookup[lookupKey]
        if socRow and socRow.online == true then
            return true
        end
        if Compat.IsInMyGroup and Compat.IsInMyGroup(rawName, row and row.guid) then
            return true
        end
        local nRow = Store and Store.nearby and Store.nearby[lookupKey]
        if type(nRow) == "table" and nRow.online ~= false and (now - (nRow.lastSeen or 0)) <= 120 then
            return true
        end
        return false
    end

    local function PushTarget(rawName, row)
        if #targets >= limit then return end
        local foreverClean = (Compat.FormatForeverTarget and Compat.FormatForeverTarget(rawName)) or rawName
        local clean = Compat.CleanPayloadField and Compat.CleanPayloadField(foreverClean or "", 40) or Safe.String(foreverClean)
        if not clean or clean == "" or clean:find("|", 1, true) or Compat.IsMe(clean) then return end
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(clean)
        local key = (parsed and parsed.lookupKey) or clean:lower()
        if not IsSameFactionAndPool(key, row) then return end
        if not IsConfirmedLiveOnline(key, clean, row) then return end
        if seen[key] then return end
        seen[key] = true
        table.insert(targets, clean)
    end

    if type(Store.social) == "table" then
        for _, row in pairs(Store.social) do
            if #targets >= limit then break end
            if type(row) == "table" and row.online and row.sources and not row.sources.guild then
                local isCharFriend = (row.sources.friend == true)
                local isBNetWoW = (row.sources.bnet == true)
                    and (row.hasCharacterName ~= false)
                    and (row.sameFaction ~= false)
                    and (row.samePool ~= false)
                    and (not row.bnetState or row.bnetState == "wow_forever")
                if isCharFriend or isBNetWoW then
                    local candName = row.characterName or row.displayName
                    if type(candName) == "string" and candName ~= "" and not candName:find("|", 1, true) then
                        PushTarget(candName, row)
                    end
                end
            end
        end
    end

    if type(Store.nearby) == "table" then
        for _, nRow in pairs(Store.nearby) do
            if #targets >= limit then break end
            if type(nRow) == "table" and (now - (nRow.lastSeen or 0)) <= 120 and nRow.guild and self:IsAlliedGuild(nRow.guild) then
                PushTarget(nRow.displayName, nRow)
            end
        end
    end

    if Store and Store.GetWatchlistTable then
        for wKey, wRow in pairs(Store:GetWatchlistTable()) do
            if #targets >= limit then break end
            if type(wRow) == "table" and wRow.status == "online" and IsConfirmedLiveOnline(wKey, wRow.displayName, wRow) then
                local isAlliedWl = wRow.guild and wRow.guild ~= "" and self:IsAlliedGuild(wRow.guild)
                local isScWl = (self.peerVersions and self.peerVersions[wKey] ~= nil)
                    or (ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(wKey, wRow.bnetAccountID))
                if (isAlliedWl or isScWl) and not Compat.IsGuildMember(wRow.displayName, wRow.guid, wRow.displayName) then
                    PushTarget(wRow.displayName or wKey, wRow)
                end
            end
        end
    end

    if Store and Store.GetRecentCompanionsList then
        for _, comp in ipairs(Store:GetRecentCompanionsList()) do
            if #targets >= limit then break end
            local cKey = comp and comp.lookupKey
            if cKey and not Compat.IsGuildMember(comp.displayName, comp.guid, comp.displayName) then
                local sMeta = Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(cKey)
                if not (sMeta and sMeta.flag == "AVOID") then
                    local socRow = Store.socialByLookup and Store.socialByLookup[cKey]
                    if IsConfirmedLiveOnline(cKey, comp.displayName, socRow or comp) then
                        PushTarget(comp.displayName, socRow or comp)
                    end
                end
            end
        end
    end

    return targets
end

local function BroadcastExternalLFG(self, payload)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return false end
    local now = GetTime()
    if (now - (self.lastAlfgSentAt or 0)) < self.MIN_SEND_INTERVAL then
        return false
    end
    self.lastAlfgSentAt = now

    local anySent = false
    local grpChan = GetActiveGroupChannel()
    if grpChan then
        if SendExternalLFGPacket(self, payload, grpChan) then
            anySent = true
        end
    end

    for _, recipient in ipairs(CollectExternalLFGRecipients(self, 8)) do
        if SendExternalLFGPacket(self, payload, "WHISPER", recipient) then
            anySent = true
        end
    end
    return anySent
end

function Clan:BroadcastGroupInstanceCap(used, max)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if not (Compat.IsInGroup and Compat.IsInGroup()) then return false end
    local monoNow = GetTime and GetTime() or 0
    if self.lastIcapSentAt and (monoNow - self.lastIcapSentAt) < 15 then
        return false
    end
    local grpChan = GetActiveGroupChannel()
    if not grpChan then return false end
    if grpChan == "PARTY" and Compat.IsInRaid and Compat.IsInRaid() then
        return false
    end
    local payload = ("ICAP~%d~%d"):format(
        math.max(0, math.min(30, tonumber(used) or 0)),
        math.max(1, math.min(30, tonumber(max) or 5))
    )
    if SendExternalLFGPacket(self, payload, grpChan) then
        self.lastIcapSentAt = monoNow
        return true
    end
    return false
end

function Clan:RequestExternalLFGCatchup()
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return false end
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    local monoNow = GetTime and GetTime() or 0
    if self.lastExtLfgReqAt and (monoNow - self.lastExtLfgReqAt) < 45 then
        return false
    end
    self.lastExtLfgReqAt = monoNow
    local payload = "ALFGR~" .. Compat.CleanPayloadField(ns.version or "0.0.0", 24)
    local sentAny = false
    for _, recipient in ipairs(CollectExternalLFGRecipients(self, 6)) do
        if SendExternalLFGPacket(self, payload, "WHISPER", recipient) then
            sentAny = true
        end
    end
    return sentAny
end

function Clan:SendVersionHello(preferChannel)
    if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then return false end
    if not IsSaneRemoteSemVer(ns.version) then return false end

    local channel = preferChannel
    if not channel then
        if IsInGuild and IsInGuild() then
            channel = "GUILD"
        else
            channel = GetActiveGroupChannel()
        end
    end
    if not channel then return false end

    return TransmitAddonMessage(self, "VH~" .. ns.version, channel, true)
end

local function ResolveForeverGuildSender(senderDisplay, senderLookupKey)
    if type(senderLookupKey) == "string" and not senderLookupKey:find("-", 1, true) then
        local cached = Compat.LookupForeverFullName and Compat.LookupForeverFullName(nil, senderLookupKey, false)
        local cParsed = cached and cached.fullName and Compat.ParseCharacterName and Compat.ParseCharacterName(cached.fullName)
        if cParsed and cParsed.displayName and cParsed.lookupKey then
            return cParsed.displayName, cParsed.lookupKey
        end
        if Store and type(Store.guildRosterRanks) == "table" then
            local matchCount, matchRec = 0, nil
            for _, rk in pairs(Store.guildRosterRanks) do
                if type(rk) == "table" and rk.displayName and not rk.isSelf then
                    local _, fn = Compat.ParseCharacterFields(rk.displayName)
                    if fn and fn:lower() == senderLookupKey then
                        matchCount = matchCount + 1
                        matchRec = rk
                        if matchCount > 1 then break end
                    end
                end
            end
            if matchCount == 1 and matchRec and matchRec.lookupKey then
                return matchRec.displayName, matchRec.lookupKey
            end
        end
    end
    return senderDisplay, senderLookupKey
end

--- Record a remote peer version from Guild, Group, or 1-on-1 Chat without circular re-entry.
function Clan:NoteRemoteVersion(senderDisplay, senderLookupKey, remoteVer, chatType)
    if not IsSaneRemoteSemVer(remoteVer) then return end
    if senderLookupKey and senderLookupKey ~= "" then
        Clan.peerVersions = Clan.peerVersions or {}
        Clan.peerVersions[senderLookupKey] = remoteVer
        Clan.peerChatSources = Clan.peerChatSources or {}
        Clan.peerChatSources[senderLookupKey] = chatType or Clan.peerChatSources[senderLookupKey]
    end

    if IsSaneRemoteSemVer(ns.version) and Compat.CompareSemVer(remoteVer, ns.version) > 0 then
        if not Clan.latestRemoteVersion or Compat.CompareSemVer(remoteVer, Clan.latestRemoteVersion) > 0 then
            Clan.latestRemoteVersion = remoteVer
            Clan.latestReportedBy = senderDisplay
        end
        if Clan.notifiedVersion ~= remoteVer then
            Clan.notifiedVersion = remoteVer
            local linkText = "|Haddon:SCentral:update|h|cff35c4ff[" .. L["GitHub Releases"] .. "]|r|h"
            ns:Print(L["New version v%s detected (you have v%s)! Click %s to update."]:format(remoteVer, ns.version, linkText))
            ns:Emit("ADDON_MESSAGE_NOTIFY", {
                kind = "VERSION_UPDATE",
                sourceTag = L["Update Available"],
                sender = "SocialCentral v" .. tostring(remoteVer),
                text = L["Version v%s is available (you have v%s). Click to update!"]:format(remoteVer, ns.version or "0.0.0"),
                priority = 2,
                ts = time(),
            })
            ns:Emit("VERSION_UPDATE_FOUND", remoteVer)
        end
    end
end

local function ProcessPeerVersion(senderDisplay, senderLookupKey, remoteVer, chatType)
    if not IsSaneRemoteSemVer(remoteVer) then return end

    if chatType == "GUILD" then
        senderDisplay, senderLookupKey = ResolveForeverGuildSender(senderDisplay, senderLookupKey)
    end

    Clan:NoteRemoteVersion(senderDisplay, senderLookupKey, remoteVer, chatType)

    if (chatType == "GUILD" or chatType == "WHISPER") and ns.Chat and ns.Chat.MarkPeerVerified then
        ns.Chat:MarkPeerVerified(senderDisplay, nil, remoteVer, chatType)
    end

    if chatType == "GUILD" and IsInGuild and IsInGuild() then
        local bucket = Store:GetClanScopeData()
        local peer = bucket.peers[senderLookupKey] or { displayName = senderDisplay, lookupKey = senderLookupKey }
        peer.displayName = senderDisplay
        peer.version = remoteVer
        peer.updatedAt = time()
        bucket.peers[senderLookupKey] = peer
    end
end

local function EnsureEventRecord(bucket, eventId)
    local evt = bucket.events[eventId]
    if evt and type(evt.signups) ~= "table" then
        evt.signups = {}
    end
    return evt
end

-- Single-pass O(L) token sets + minimal C-level literal/prefix fallbacks (replaces O(K*L) scans).
local DUNGEON_EXACT_WORDS = {
    dg = true, dungeon = true, dungeons = true, masmorra = true, masmorras = true,
    mazmorra = true, mazmorras = true, mythic = true, mythics = true,
    mitic = true, mitica = true, miticas = true,
    heroic = true, heroics = true, heroica = true, heroico = true, heroicas = true, heroicos = true,
    hc = true, chave = true, chaves = true, pedra = true, pedras = true,
    piedra = true, piedras = true, keystone = true, keystones = true, key = true,
    timewalking = true, caminhada = true, cam = true, delve = true, delves = true,
    follower = true, followers = true, deadmines = true, strath = true, stratholme = true,
    scholo = true, scholomance = true, brd = true, ubrs = true, lbrs = true,
    maraudon = true, gnomer = true, gnomeregan = true, sunken = true, wailing = true,
    shadowfang = true, sfk = true, sm = true, rfc = true, wc = true,
    stockade = true, stockades = true, uldaman = true, blackrock = true,
    vc = true, dm = true, strat = true, zg = true, mc = true, bwl = true,
    aq = true, aq20 = true, aq40 = true, naxx = true, ony = true,
    bfd = true, rfk = true, rfd = true, st = true, kara = true, ["zul'farrak"] = true, zf = true,
    thanes = true, lordaeron = true, igneas = true, ululante = true, mortas = true,
    carcere = true, urzal = true, escarlate = true, submerso = true, gladio = true,
    rocha = true, minas = true, bastilha = true, profundezas = true, cavernas = true,
    mazmorras = true, mazmorra = true,
}

local DUNGEON_LITERALS = {
    "calabou", "calabozo", "scarlet", "dire maul", "razorfen", "m+",
    "strath", "heroic", "mitic", "masmorra", "mazmorra",
    "hall of thanes", "salao dos thanes", "salão dos thanes",
    "ruins of lordaeron", "ruinas de lordaeron", "ruínas de lordaeron",
    "cavernas igneas", "cavernas ígneas", "caverna ululante", "minas mortas",
    "presa negra", "profundezas negras", "o carcere", "o cárcere",
    "monasterio escarlate", "monastério escarlate", "templo submerso",
    "abismo rocha negra", "pico da rocha negra", "gladio cruel", "gládio cruel",
    "camara de las sombras", "cuevas de los lamentos", "minas de la muerte",
}

local WTS_SPAM_WORDS = {
    wts = true, wtb = true, g2g = true, carry = true, carries = true,
    boost = true, boosting = true,
}

local WTS_SPAM_LITERALS = {
    "venda de ouro", "venda de gold", "vendo gold", "vendo ouro",
    "compro ouro", "compro gold", "gold only", "cheap gold",
    "discord.gg", "twitch.tv",
}

local function MatchesSpamText(low)
    if type(low) ~= "string" or low == "" then return false end
    for w in low:gmatch("[%w']+") do
        if WTS_SPAM_WORDS[w] then
            return true
        end
    end
    for i = 1, #WTS_SPAM_LITERALS do
        if low:find(WTS_SPAM_LITERALS[i], 1, true) then
            return true
        end
    end
    return false
end

local function IsDungeonLFGText(text, category)
    if category == "DUNGEON" then
        return true
    end
    if type(text) ~= "string" or text == "" then
        return false
    end
    local low = text:lower()
    for w in low:gmatch("[%w']+") do
        if DUNGEON_EXACT_WORDS[w] then
            return true
        end
    end
    for i = 1, #DUNGEON_LITERALS do
        if low:find(DUNGEON_LITERALS[i], 1, true) then
            return true
        end
    end
    return low:find("%+%d+") ~= nil
end

function Clan:SetMyStatus(tagId, note)
    if not IsValidTag(tagId) then tagId = "NONE" end
    local bucket = Store:GetClanScopeData()
    local cleanNote = Compat.CleanPayloadField(note or "", 36)
    bucket.myTag = tagId
    bucket.myNote = cleanNote

    local sent = self:SendGuildSync("TAG~" .. (ns.version or "0.0.0") .. "~" .. tagId .. "~" .. cleanNote)
    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    if myParsed then
        bucket.lfg = bucket.lfg or {}
        if tagId == "LFG" or tagId == "MPLUS" or tagId == "RAID" or tagId == "PVP" then
            local _, myClass = Safe.Call(UnitClass, "player")
            local role = self:GetMySpecAndRole()
            local act = cleanNote ~= "" and cleanNote or (L[tagId] or tagId)
            local keyLvl = (tagId == "MPLUS") and 1 or 0
            local sum = self.GetPlayerGameSummary and self:GetPlayerGameSummary() or {}
            local iLvl = sum.avgItemLevel or 0
            bucket.lfg[myParsed.lookupKey] = {
                lookupKey = myParsed.lookupKey,
                displayName = myParsed.displayName,
                classFile = Safe.String(myClass),
                mode = "LFG",
                role = role,
                activity = act,
                keyLvl = keyLvl,
                ilvl = iLvl,
                note = cleanNote,
                isDungeon = (tagId == "LFG" or tagId == "MPLUS" or IsDungeonLFGText(act, nil)),
                updatedAt = time(),
            }
            local payload = ("LFG~%s~LFG~%s~%s~%d~%d~%s"):format(ns.version or "0.0.0", role, act:sub(1, 40), keyLvl, iLvl, cleanNote)
            self:SendGuildSync(payload)
        else
            if bucket.lfg[myParsed.lookupKey] then
                bucket.lfg[myParsed.lookupKey] = nil
                self:SendGuildSync("LFX")
            end
            if self.externalLFG and self.externalLFG[myParsed.lookupKey] then
                self.externalLFG[myParsed.lookupKey] = nil
                BroadcastExternalLFG(self, ("ALFX~%s"):format(Compat.CleanPayloadField(myParsed.displayName, 28)))
            end
        end
    end
    if (ns.db and ns.db.settings and ns.db.settings.clanSync) and not sent and IsInGuild and IsInGuild() then
        local waitRem = math.ceil(math.max(0, self.MIN_SEND_INTERVAL - (GetTime() - (self.lastSyncSentAt or 0))))
        if waitRem > 0 then
            ns:Print(L["Status saved locally; guild broadcast ready in %ds."]:format(waitRem))
        end
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

-- ============================================================================
-- Zero-Leakage Clan Management Info & Guild Diplomacy Registry (ALLY / ENEMY)
-- ============================================================================

local function NormalizeGuildKey(rawGuildName)
    local clean = Compat.CleanInput(rawGuildName)
    if not clean then return "" end
    return Compat.Plain(clean)
end

local function ComputeGuildScopeToken()
    local info = Store and Store.guildInfo
    local gName = info and info.inGuild and info.name
    if (not gName or gName == "") and IsInGuild and IsInGuild() and GetGuildInfo then
        local ok, n = pcall(GetGuildInfo, "player")
        if ok then gName = Safe.String(n) end
    end
    if not gName or gName == "" then return "" end
    local raw = Compat.ScopeKey() .. "::" .. Compat.Plain(gName)
    local h = 5381
    for i = 1, #raw do
        h = (h * 33 + raw:byte(i)) % 16777216
    end
    return string.format("%06x", h)
end

local function IsPlayerGuildOfficer()
    if not (IsInGuild and IsInGuild()) then
        return false
    end
    if IsGuildLeader and Safe.Value(IsGuildLeader()) == true then
        return true
    end
    if C_GuildInfo then
        if C_GuildInfo.CanEditOfficerNote and Safe.Value(Safe.Call(C_GuildInfo.CanEditOfficerNote)) == true then
            return true
        end
        if C_GuildInfo.CanEditMOTD and Safe.Value(Safe.Call(C_GuildInfo.CanEditMOTD)) == true then
            return true
        end
    end
    if CanEditOfficerNote and Safe.Value(Safe.Call(CanEditOfficerNote)) == true then
        return true
    end
    return false
end

local function IsSenderConfirmedInGuild(lookupKey)
    if not (IsInGuild and IsInGuild()) or not lookupKey or lookupKey == "" then
        return false
    end
    local liveRow = Store and Store.socialByLookup and Store.socialByLookup[lookupKey]
    if liveRow and liveRow.sources and liveRow.sources.guild == true then
        return true
    end
    local total = GetNumGuildMembers and Safe.Number(GetNumGuildMembers()) or 0
    if not total or total <= 0 then
        -- Guild roster cache not yet hydrated right at login; Blizzard's GUILD channel + scope token still apply.
        return true
    end
    for i = 1, total do
        local ok, fullName = pcall(GetGuildRosterInfo, i)
        if ok and fullName then
            local cleanName = Safe.String(fullName)
            if cleanName then
                if Compat.ParseCharacterFields then
                    local _, _, lKey = Compat.ParseCharacterFields(cleanName)
                    if lKey == lookupKey then
                        return true
                    end
                else
                    local p = Compat.ParseCharacterName(cleanName)
                    if p and p.lookupKey == lookupKey then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function DrainIntelQueue()
    Clan._intelDrainScheduled = false
    if Clan.isStoppedThisSession or Clan:IsMessagingLocked() then
        return
    end
    if Clan.backoffUntil and (GetTime and GetTime() or 0) < Clan.backoffUntil then
        if #Clan.intelQueue > 0 and C_Timer and C_Timer.After then
            Clan._intelDrainScheduled = true
            C_Timer.After(4.0, DrainIntelQueue)
        end
        return
    end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) or not (IsInGuild and IsInGuild()) then
        wipe(Clan.intelQueue)
        return
    end
    local pkt = table.remove(Clan.intelQueue, 1)
    if not pkt then
        return
    end
    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if sendFn and type(pkt) == "string" and #pkt <= Clan.MAX_PAYLOAD_BYTES and not pkt:find("[%c|]") then
        local ok, result = pcall(sendFn, Clan.PREFIX, pkt, "GUILD")
        if ok and Enum and Enum.SendAddonMessageResult and type(result) == "number" then
            for name, value in pairs(Enum.SendAddonMessageResult) do
                if value == result and name:find("Throttle") then
                    RecordClanThrottleStrike(Clan)
                    if Clan.isStoppedThisSession then
                        wipe(Clan.intelQueue)
                        return
                    end
                end
            end
        end
    end
    if #Clan.intelQueue > 0 then
        Clan._intelDrainScheduled = true
        C_Timer.After(1.4, DrainIntelQueue)
    end
end

local function EnqueueIntelPacket(payload)
    if type(payload) ~= "string" or payload == "" or #payload > Clan.MAX_PAYLOAD_BYTES then
        return false
    end
    if payload:find("[%c|]") then
        return false
    end
    if Clan.isStoppedThisSession or not (ns.db and ns.db.settings and ns.db.settings.clanSync) or not (IsInGuild and IsInGuild()) then
        return false
    end
    for _, existing in ipairs(Clan.intelQueue) do
        if existing == payload then
            return true
        end
    end
    if #Clan.intelQueue >= 18 then
        table.remove(Clan.intelQueue, 1)
    end
    table.insert(Clan.intelQueue, payload)
    if not Clan._intelDrainScheduled then
        Clan._intelDrainScheduled = true
        C_Timer.After(0.35, DrainIntelQueue)
    end
    return true
end

local function EvaluateRankRule(isGM, isNativeOfficer, rankIndex, rankName, mode, maxRank)
    if isGM then
        return true
    end
    if mode == "ALL" then
        return true
    end
    if mode == "OFFICERS" then
        if isNativeOfficer ~= nil then
            return isNativeOfficer == true
        end
        if rankIndex ~= nil and rankIndex <= 2 then
            return true
        end
        if type(rankName) == "string" and rankName ~= "" then
            local rn = rankName:lower()
            if rn:find("officer", 1, true) or rn:find("oficial", 1, true)
                or rn:find("leader", 1, true) or rn:find("lider", 1, true)
                or rn:find("guild master", 1, true) or rn == "gm"
            then
                return true
            end
        end
        return false
    end
    if mode == "RANK" then
        return rankIndex ~= nil and rankIndex <= (tonumber(maxRank) or 0)
    end
    return false
end

function Clan:IsGuildLeader()
    if not (IsInGuild and IsInGuild()) then
        return false
    end
    if IsGuildLeader and Safe.Value(Safe.Call(IsGuildLeader)) == true then
        return true
    end
    local info = Store and Store.guildInfo
    if info and info.isGuildLeader == true then
        return true
    end
    if info and info.myRankIndex == 0 then
        return true
    end
    if C_GuildInfo and C_GuildInfo.GetGuildRankOrder and UnitGUID then
        local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
        if myGuid then
            local rank = Safe.Number(Safe.Call(C_GuildInfo.GetGuildRankOrder, myGuid))
            if rank == 0 then
                return true
            end
        end
    end
    return false
end

function Clan:GetMemberGuildRank(lookupKey)
    if not (IsInGuild and IsInGuild()) or not lookupKey or lookupKey == "" then
        return nil, nil, nil, nil
    end
    local rosterRanks = Store and Store.guildRosterRanks
    local r = rosterRanks and rosterRanks[lookupKey]
    if type(r) == "table" and r.rankIndex ~= nil then
        return r.rankIndex, r.rankName, r.guid, r.rosterIndex
    end
    local liveRow = Store and Store.socialByLookup and Store.socialByLookup[lookupKey]
    if liveRow and liveRow.sources and liveRow.sources.guild == true and liveRow.rankIndex ~= nil then
        return liveRow.rankIndex, liveRow.rankName, liveRow.guid, nil
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        local total = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
        for i = 1, total do
            local okG, fullName, rankName, rankIndex, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
            if okG and fullName then
                local cleanName = Safe.String(fullName)
                if cleanName then
                    local lKey
                    if Compat.ParseCharacterFields then
                        local _, _, k = Compat.ParseCharacterFields(cleanName)
                        lKey = k
                    else
                        local p = Compat.ParseCharacterName(cleanName)
                        lKey = p and p.lookupKey
                    end
                    if lKey == lookupKey then
                        return Safe.Number(rankIndex), Safe.String(rankName) or "", Safe.String(guid), i
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil
end

local function ReadRankInviteFlag(rankOrder)
    if not (C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags and rankOrder and rankOrder >= 1) then
        return nil
    end
    local ok, a, _, _, _, _, _, g = pcall(C_GuildInfo.GuildControlGetRankFlags, rankOrder)
    if not ok then
        return nil
    end
    local opt1 = type(_G.GUILDCONTROL_OPTION1) == "string" and _G.GUILDCONTROL_OPTION1:lower() or ""
    local isRetailOrder = opt1 ~= "" and (
        opt1:find("chat", 1, true)
        or opt1:find("bate-papo", 1, true)
        or opt1:find("hermandad", 1, true)
        or opt1:find("ouvir", 1, true)
        or opt1:find("listen", 1, true)
        or opt1:find("escuchar", 1, true)
    )
    if type(a) == "table" then
        local n = #a
        if n <= 0 then
            return nil
        end
        local idx = (n >= 15 or isRetailOrder) and 7 or 1
        if a[idx] ~= nil then
            return Safe.Value(a[idx]) == true
        end
        return nil
    elseif type(a) == "boolean" then
        if isRetailOrder and g ~= nil then
            return Safe.Value(g) == true
        end
        return Safe.Value(a) == true
    end
    return nil
end

--- Fail-closed verification of whether the active character is actually permitted to invite players to the guild.
function Clan:CanInviteToGuild(rankIndexOverride)
    if not (IsInGuild and Safe.Value(Safe.Call(IsInGuild)) == true) then
        return false
    end
    if self:IsGuildLeader() then
        return true
    end
    local myIdx = rankIndexOverride
    if myIdx == nil then
        local info = Store and Store.guildInfo
        myIdx = info and info.myRankIndex
    end
    if myIdx == nil then
        local _, myKey = ResolveSelfIdentity()
        if myKey then
            myIdx = self:GetMemberGuildRank(myKey)
        end
    end
    if myIdx == nil and C_GuildInfo and C_GuildInfo.GetGuildRankOrder and UnitGUID then
        local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
        if myGuid then
            myIdx = Safe.Number(Safe.Call(C_GuildInfo.GetGuildRankOrder, myGuid))
        end
    end
    if myIdx == 0 then
        return true
    end

    local clubApproved = nil
    if C_Club and C_Club.GetGuildClubId and C_Club.GetClubPrivileges then
        local clubId = Safe.Call(C_Club.GetGuildClubId)
        if clubId then
            local priv = Safe.Call(C_Club.GetClubPrivileges, clubId)
            if type(priv) == "table" and priv.canSendInvitation ~= nil then
                local allow = Safe.Value(priv.canSendInvitation) == true
                if not allow then
                    return false
                end
                clubApproved = true
            end
        end
    end

    local flagApproved = nil
    if myIdx ~= nil then
        local rf = ReadRankInviteFlag(myIdx + 1)
        if rf == false then
            return false
        elseif rf == true then
            flagApproved = true
        end
    end

    local apiApproved = nil
    if C_GuildInfo and C_GuildInfo.CanGuildInvite then
        if Safe.Value(Safe.Call(C_GuildInfo.CanGuildInvite)) ~= true then
            return false
        end
        apiApproved = true
    end
    if CanGuildInvite then
        if Safe.Value(Safe.Call(CanGuildInvite)) ~= true then
            return false
        end
        apiApproved = true
    end

    if myIdx == nil and not clubApproved and not flagApproved then
        return false
    end
    return (clubApproved == true) or (flagApproved == true) or (apiApproved == true)
end

function Clan:GetSelfGuildRank()
    local inGuild = (IsInGuild and Safe.Value(Safe.Call(IsInGuild)) == true) or false
    local info = Store and Store.guildInfo or {}
    local isGM = self:IsGuildLeader()
    local myIdx = info.myRankIndex
    local myName = info.myRankName
    if inGuild and myIdx == nil then
        local _, myKey = ResolveSelfIdentity()
        if myKey then
            local idx, rName = self:GetMemberGuildRank(myKey)
            myIdx = idx
            myName = rName or myName
        end
    end
    if inGuild and myIdx == nil and C_GuildInfo and C_GuildInfo.GetGuildRankOrder and UnitGUID then
        local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
        if myGuid then
            myIdx = Safe.Number(Safe.Call(C_GuildInfo.GetGuildRankOrder, myGuid))
        end
    end
    if inGuild and (not myName or myName == "") and myIdx ~= nil and GuildControlGetRankName then
        myName = Safe.String(Safe.Call(GuildControlGetRankName, myIdx + 1)) or myName
    end

    local canEditOfficerNote = inGuild and ((C_GuildInfo and C_GuildInfo.CanEditOfficerNote and Safe.Value(Safe.Call(C_GuildInfo.CanEditOfficerNote)) == true)
        or (CanEditOfficerNote and Safe.Value(Safe.Call(CanEditOfficerNote)) == true) or false)
    local canViewOfficerNote = inGuild and ((C_GuildInfo and C_GuildInfo.CanViewOfficerNote and Safe.Value(Safe.Call(C_GuildInfo.CanViewOfficerNote)) == true)
        or (CanViewOfficerNote and Safe.Value(Safe.Call(CanViewOfficerNote)) == true) or false)
    local canEditMOTD = inGuild and ((CanEditMOTD and Safe.Value(Safe.Call(CanEditMOTD)) == true)
        or (C_GuildInfo and C_GuildInfo.CanEditMOTD and Safe.Value(Safe.Call(C_GuildInfo.CanEditMOTD)) == true) or false)
    local canEditGuildInfo = inGuild and ((CanEditGuildInfo and Safe.Value(Safe.Call(CanEditGuildInfo)) == true)
        or (C_GuildInfo and C_GuildInfo.CanEditGuildInfo and Safe.Value(Safe.Call(C_GuildInfo.CanEditGuildInfo)) == true) or false)
    local canEditPublicNote = inGuild and ((CanEditPublicNote and Safe.Value(Safe.Call(CanEditPublicNote)) == true)
        or (C_GuildInfo and C_GuildInfo.CanEditPublicNote and Safe.Value(Safe.Call(C_GuildInfo.CanEditPublicNote)) == true) or false)
    local canInvite = inGuild and self:CanInviteToGuild(myIdx) or false
    local canPromote = inGuild and ((C_GuildInfo and C_GuildInfo.CanGuildPromote and Safe.Value(Safe.Call(C_GuildInfo.CanGuildPromote)) == true)
        or (CanGuildPromote and Safe.Value(Safe.Call(CanGuildPromote)) == true) or false)
    local canDemote = inGuild and ((C_GuildInfo and C_GuildInfo.CanGuildDemote and Safe.Value(Safe.Call(C_GuildInfo.CanGuildDemote)) == true)
        or (CanGuildDemote and Safe.Value(Safe.Call(CanGuildDemote)) == true) or false)
    local canEditCalendar = inGuild and ((CanEditGuildEvent and Safe.Value(Safe.Call(CanEditGuildEvent)) == true) or false)

    return {
        inGuild = inGuild,
        rankIndex = myIdx,
        rankName = myName or "",
        isGuildLeader = isGM,
        isOfficer = isGM or canEditOfficerNote or canEditMOTD or canEditGuildInfo or IsPlayerGuildOfficer(),
        canEditMOTD = canEditMOTD,
        canEditGuildInfo = canEditGuildInfo,
        canEditOfficerNote = canEditOfficerNote,
        canViewOfficerNote = canViewOfficerNote,
        canEditPublicNote = canEditPublicNote,
        canInvite = canInvite,
        canPromote = canPromote,
        canDemote = canDemote,
        canEditCalendar = canEditCalendar,
    }
end

function Clan:GetGuildRanks()
    local ranks = {}
    if not (IsInGuild and IsInGuild()) then
        return ranks
    end
    local countsTotal = {}
    local countsOnline = {}
    local nameFallback = {}
    if Store and type(Store.guildRosterRanks) == "table" then
        for _, m in pairs(Store.guildRosterRanks) do
            if type(m) == "table" and m.rankIndex ~= nil then
                local idx = m.rankIndex
                countsTotal[idx] = (countsTotal[idx] or 0) + 1
                if m.online then
                    countsOnline[idx] = (countsOnline[idx] or 0) + 1
                end
                if m.rankName and m.rankName ~= "" and not nameFallback[idx] then
                    nameFallback[idx] = m.rankName
                end
            end
        end
    end

    local numRanks = GuildControlGetNumRanks and Safe.Number(Safe.Call(GuildControlGetNumRanks)) or 0
    if numRanks and numRanks > 0 then
        for orderIdx = 1, math.min(10, numRanks) do
            local rIdx = orderIdx - 1
            local rName = (GuildControlGetRankName and Safe.String(Safe.Call(GuildControlGetRankName, orderIdx))) or nameFallback[rIdx] or (L["Rank"] .. " " .. tostring(orderIdx))
            table.insert(ranks, {
                rankOrder = orderIdx,
                rankIndex = rIdx,
                name = rName,
                totalMembers = countsTotal[rIdx] or 0,
                onlineMembers = countsOnline[rIdx] or 0,
                isLeader = (rIdx == 0),
            })
        end
    else
        local maxSeen = -1
        for idx in pairs(nameFallback) do
            if idx > maxSeen then maxSeen = idx end
        end
        for rIdx = 0, math.max(0, maxSeen) do
            if nameFallback[rIdx] or (countsTotal[rIdx] or 0) > 0 then
                table.insert(ranks, {
                    rankOrder = rIdx + 1,
                    rankIndex = rIdx,
                    name = nameFallback[rIdx] or (rIdx == 0 and L["Guild Leader"] or (L["Rank"] .. " " .. tostring(rIdx + 1))),
                    totalMembers = countsTotal[rIdx] or 0,
                    onlineMembers = countsOnline[rIdx] or 0,
                    isLeader = (rIdx == 0),
                })
            end
        end
    end
    return ranks
end

local function GetRankLabelByIndex(ranks, rankIdx)
    local target = tonumber(rankIdx) or 0
    for _, r in ipairs(ranks or {}) do
        if r.rankIndex == target then
            return r.name
        end
    end
    return (L["Rank"] or "Rank") .. " " .. tostring(target + 1)
end

local function IsSenderAuthorizedForPolicy(self, lookupKey, mode, maxRank)
    if not (IsInGuild and IsInGuild()) or not lookupKey or lookupKey == "" then
        return false
    end
    local total = GetNumGuildMembers and Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    local rankIdx, rankName = self:GetMemberGuildRank(lookupKey)
    if rankIdx == nil then
        -- Grace only while roster hasn't hydrated at login
        return (not total or total <= 0)
    end
    return EvaluateRankRule(rankIdx == 0, nil, rankIdx, rankName, mode, maxRank)
end

function Clan:GetGuildHierarchyPolicy()
    local bucket = Store:GetClanScopeData()
    local h = bucket.hierarchy or {}
    return {
        rev = h.rev or 0,
        updatedAt = h.updatedAt or 0,
        updatedBy = h.updatedBy or "",
        diplomacyMode = (h.diplomacyMode == "OFFICERS" or h.diplomacyMode == "RANK") and h.diplomacyMode or "LEADER",
        diplomacyMaxRank = math.max(0, math.min(9, tonumber(h.diplomacyMaxRank) or 1)),
        infoMode = (h.infoMode == "LEADER" or h.infoMode == "RANK" or h.infoMode == "ALL") and h.infoMode or "OFFICERS",
        infoMaxRank = math.max(0, math.min(9, tonumber(h.infoMaxRank) or 1)),
        eventModMode = (h.eventModMode == "LEADER" or h.eventModMode == "RANK") and h.eventModMode or "OFFICERS",
        eventModMaxRank = math.max(0, math.min(9, tonumber(h.eventModMaxRank) or 1)),
        allianceMinRank = (tonumber(h.allianceMinRank) and tonumber(h.allianceMinRank) >= 0) and math.min(9, tonumber(h.allianceMinRank)) or -1,
    }
end

function Clan:CanConfigureHierarchy()
    return self:IsGuildLeader()
end

function Clan:GetRuleAuthoritySummary(mode, maxRank)
    if mode == "ALL" then
        return L["All Guild Members"]
    elseif mode == "OFFICERS" then
        return L["Leader & Game Officers"]
    elseif mode == "RANK" then
        local rName = GetRankLabelByIndex(self:GetGuildRanks(), maxRank or 1)
        return string.format(L["Up to Rank: %s"], rName)
    end
    return L["Guild Leader Only"]
end

function Clan:GetDiplomacyAuthoritySummary()
    local pol = self:GetGuildHierarchyPolicy()
    return self:GetRuleAuthoritySummary(pol.diplomacyMode, pol.diplomacyMaxRank)
end

function Clan:CanManageDiplomacy()
    if not (IsInGuild and IsInGuild()) then
        return false, L["No guild"]
    end
    local selfRank = self:GetSelfGuildRank()
    local pol = self:GetGuildHierarchyPolicy()
    local allowed = EvaluateRankRule(selfRank.isGuildLeader, selfRank.isOfficer, selfRank.rankIndex, selfRank.rankName, pol.diplomacyMode, pol.diplomacyMaxRank)
    return allowed, self:GetRuleAuthoritySummary(pol.diplomacyMode, pol.diplomacyMaxRank)
end

function Clan:CanModerateEvents()
    if not (IsInGuild and IsInGuild()) then
        return false
    end
    local selfRank = self:GetSelfGuildRank()
    local pol = self:GetGuildHierarchyPolicy()
    return EvaluateRankRule(selfRank.isGuildLeader, selfRank.isOfficer, selfRank.rankIndex, selfRank.rankName, pol.eventModMode, pol.eventModMaxRank)
end

function Clan:CanEditClanManagement()
    if not (IsInGuild and IsInGuild()) then
        return false, false
    end
    local selfRank = self:GetSelfGuildRank()
    local pol = self:GetGuildHierarchyPolicy()
    local allowed = EvaluateRankRule(selfRank.isGuildLeader, selfRank.isOfficer, selfRank.rankIndex, selfRank.rankName, pol.infoMode, pol.infoMaxRank)
    return allowed, selfRank.isOfficer
end

function Clan:SaveGuildHierarchyPolicy(patch)
    if not (IsInGuild and IsInGuild()) then
        ns:Print(L["No guild"])
        return false
    end
    if not self:IsGuildLeader() then
        ns:Print(L["Only the Guild Leader can configure Guild Hierarchy & Rank Permissions."])
        return false
    end
    local bucket = Store:GetClanScopeData()
    local h = bucket.hierarchy
    if type(patch) == "table" then
        if patch.diplomacyMode == "LEADER" or patch.diplomacyMode == "OFFICERS" or patch.diplomacyMode == "RANK" then
            h.diplomacyMode = patch.diplomacyMode
        end
        if patch.diplomacyMaxRank ~= nil then
            h.diplomacyMaxRank = math.max(0, math.min(9, tonumber(patch.diplomacyMaxRank) or 1))
        end
        if patch.infoMode == "LEADER" or patch.infoMode == "OFFICERS" or patch.infoMode == "RANK" or patch.infoMode == "ALL" then
            h.infoMode = patch.infoMode
            if bucket.clanInfo then
                bucket.clanInfo.editMode = (h.infoMode == "ALL") and "ALL" or "OFFICERS"
            end
        end
        if patch.infoMaxRank ~= nil then
            h.infoMaxRank = math.max(0, math.min(9, tonumber(patch.infoMaxRank) or 1))
        end
        if patch.eventModMode == "LEADER" or patch.eventModMode == "OFFICERS" or patch.eventModMode == "RANK" then
            h.eventModMode = patch.eventModMode
        end
        if patch.eventModMaxRank ~= nil then
            h.eventModMaxRank = math.max(0, math.min(9, tonumber(patch.eventModMaxRank) or 1))
        end
        if patch.allianceMinRank ~= nil then
            local ar = tonumber(patch.allianceMinRank)
            h.allianceMinRank = (ar and ar >= 0 and ar <= 9) and ar or -1
        end
    end

    local nextRev = math.max(time(), (h.rev or 0) + 1)
    h.rev = nextRev
    h.updatedAt = time()
    h.updatedBy = ResolveSelfIdentity()

    local tok = ComputeGuildScopeToken()
    if tok ~= "" and ns.db and ns.db.settings and ns.db.settings.clanSync then
        EnqueueIntelPacket(("CHIR~%s~%d~%s~%d~%s~%d~%s~%d~%d"):format(
            tok,
            nextRev,
            h.diplomacyMode,
            h.diplomacyMaxRank,
            h.infoMode,
            h.infoMaxRank,
            h.eventModMode,
            h.eventModMaxRank,
            h.allianceMinRank
        ))
    end
    ns:Emit("CLAN_UPDATED")
    ns:Emit("CLAN_DIPLOMACY_UPDATED")
    ns:Emit("CLAN_HIERARCHY_UPDATED")
    return true
end

function Clan:PromoteMember(lookupKey, targetName, targetGuid)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["Unavailable during combat."])
        return false
    end
    local selfRank = self:GetSelfGuildRank()
    if not selfRank.canPromote and not selfRank.isGuildLeader then
        ns:Print(L["Your guild rank does not have permission to promote members."])
        return false
    end
    local curIdx, _, resolvedGuid = self:GetMemberGuildRank(lookupKey)
    local guid = targetGuid or resolvedGuid
    if curIdx and curIdx <= 1 then
        ns:Print(L["Cannot promote to Guild Leader using quick promote."])
        return false
    end
    if C_GuildInfo and C_GuildInfo.SetGuildRankOrder and guid and curIdx and curIdx > 1 then
        local nextOrder = curIdx - 1
        local allowed = (not C_GuildInfo.IsGuildRankAssignmentAllowed) or Safe.Value(Safe.Call(C_GuildInfo.IsGuildRankAssignmentAllowed, guid, nextOrder)) == true
        if allowed then
            local ok = pcall(C_GuildInfo.SetGuildRankOrder, guid, nextOrder)
            if ok then
                if C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
                return true
            end
        end
    end
    if _G.GuildPromote and targetName and targetName ~= "" then
        local ok = pcall(_G.GuildPromote, targetName)
        if ok then
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
            return true
        end
    end
    return false
end

function Clan:DemoteMember(lookupKey, targetName, targetGuid)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["Unavailable during combat."])
        return false
    end
    local selfRank = self:GetSelfGuildRank()
    if not selfRank.canDemote and not selfRank.isGuildLeader then
        ns:Print(L["Your guild rank does not have permission to demote members."])
        return false
    end
    local curIdx, _, resolvedGuid = self:GetMemberGuildRank(lookupKey)
    local guid = targetGuid or resolvedGuid
    if curIdx and curIdx == 0 then
        ns:Print(L["Cannot demote the Guild Leader."])
        return false
    end
    local ranks = self:GetGuildRanks()
    local maxIdx = (#ranks > 0) and (#ranks - 1) or 9
    if C_GuildInfo and C_GuildInfo.SetGuildRankOrder and guid and curIdx ~= nil and curIdx < maxIdx then
        local nextOrder = curIdx + 1
        local allowed = (not C_GuildInfo.IsGuildRankAssignmentAllowed) or Safe.Value(Safe.Call(C_GuildInfo.IsGuildRankAssignmentAllowed, guid, nextOrder)) == true
        if allowed then
            local ok = pcall(C_GuildInfo.SetGuildRankOrder, guid, nextOrder)
            if ok then
                if C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
                return true
            end
        end
    end
    if _G.GuildDemote and targetName and targetName ~= "" then
        local ok = pcall(_G.GuildDemote, targetName)
        if ok then
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
            return true
        end
    end
    return false
end

function Clan:SetMemberRank(lookupKey, targetGuid, targetRankIndex)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["Unavailable during combat."])
        return false
    end
    local _, _, resolvedGuid = self:GetMemberGuildRank(lookupKey)
    local guid = targetGuid or resolvedGuid
    local order = tonumber(targetRankIndex)
    if not (guid and order and order >= 1) then
        return false
    end
    if C_GuildInfo and C_GuildInfo.SetGuildRankOrder then
        if C_GuildInfo.IsGuildRankAssignmentAllowed and Safe.Value(Safe.Call(C_GuildInfo.IsGuildRankAssignmentAllowed, guid, order)) ~= true then
            ns:Print(L["Your guild rank cannot assign that rank."])
            return false
        end
        local ok = pcall(C_GuildInfo.SetGuildRankOrder, guid, order)
        if ok then
            if C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
            return true
        end
    end
    return false
end

function Clan:SetMemberPublicNote(lookupKey, rawNote)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["Unavailable during combat."])
        return false
    end
    if not self:CanEditMyGuildNote() then
        ns:Print(L["Your guild rank cannot edit Guild Public Notes."])
        return false
    end
    local _, _, _, rosterIdx = self:GetMemberGuildRank(lookupKey)
    if not rosterIdx then
        ns:Print(L["Guild roster not loaded yet."])
        return false
    end
    local noteText = (Compat.CleanInput and Compat.CleanInput(rawNote or "") or tostring(rawNote or "")):sub(1, 31)
    local ok = false
    if C_GuildInfo and C_GuildInfo.SetNote then
        ok = pcall(C_GuildInfo.SetNote, rosterIdx, noteText, true)
    elseif GuildRosterSetPublicNote then
        ok = pcall(GuildRosterSetPublicNote, rosterIdx, noteText)
    end
    if ok then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        ns:Emit("CLAN_UPDATED")
        return true
    end
    return false
end

function Clan:CanManageAlliance()
    if not (IsInGuild and IsInGuild()) then
        return false
    end
    if self:IsGuildLeader() then
        return true
    end
    local _, myKey = ResolveSelfIdentity()
    if myKey then
        local bucket = Store:GetClanScopeData()
        if bucket.alliance and bucket.alliance.managers and bucket.alliance.managers[myKey] == true then
            return true
        end
    end
    return false
end

function Clan:GetAllianceConfig()
    local bucket = Store:GetClanScopeData()
    return bucket.alliance or {}
end

function Clan:SaveAllianceConfig(enabled, name, token, accessMode)
    if not self:CanManageAlliance() then
        ns:Print(L["Only the Guild Leader or appointed Alliance Managers can configure the Alliance."])
        return false
    end
    local bucket = Store:GetClanScopeData()
    bucket.alliance = bucket.alliance or {}
    local nextRev = math.max(time(), (bucket.alliance.rev or 0) + 1)
    bucket.alliance.enabled = enabled and true or false
    bucket.alliance.name = Compat.CleanPayloadField(name or "", 40)
    bucket.alliance.token = Compat.CleanPayloadField(token or "", 32)
    bucket.alliance.accessMode = (accessMode == "ALL") and "ALL" or "WHITELIST"
    bucket.alliance.rev = nextRev
    bucket.alliance.updatedAt = time()

    local tok = ComputeGuildScopeToken()
    if tok ~= "" and ns.db and ns.db.settings and ns.db.settings.clanSync then
        EnqueueIntelPacket(("ALLC~%s~%d~%s~%s~%s~%s"):format(
            tok,
            nextRev,
            bucket.alliance.enabled and "1" or "0",
            bucket.alliance.accessMode,
            bucket.alliance.name,
            bucket.alliance.token
        ))
    end
    ns:Emit("CLAN_UPDATED")
    ns:Emit("ALLIANCE_UPDATED")
    return true
end

function Clan:SetMemberAllianceAccess(lookupKey, allowed, asManager)
    if not self:CanManageAlliance() then
        return false
    end
    if not lookupKey or lookupKey == "" then return false end
    local bucket = Store:GetClanScopeData()
    bucket.alliance = bucket.alliance or {}
    bucket.alliance.whitelist = bucket.alliance.whitelist or {}
    bucket.alliance.managers = bucket.alliance.managers or {}
    if allowed then
        bucket.alliance.whitelist[lookupKey] = true
    else
        bucket.alliance.whitelist[lookupKey] = nil
    end
    if self:IsGuildLeader() then
        if asManager then
            bucket.alliance.managers[lookupKey] = true
        else
            bucket.alliance.managers[lookupKey] = nil
        end
    end
    ns:Emit("CLAN_UPDATED")
    ns:Emit("ALLIANCE_UPDATED")
    return true
end

function Clan:IsMemberAllianceAuthorized(lookupKey)
    if not (IsInGuild and IsInGuild()) then
        return false
    end
    if self:IsGuildLeader() then
        return true
    end
    local bucket = Store:GetClanScopeData()
    local all = bucket.alliance
    if not all or not all.enabled then
        return false
    end
    if all.accessMode == "ALL" then
        return true
    end
    if not lookupKey then
        local _, myKey = ResolveSelfIdentity()
        lookupKey = myKey
    end
    if lookupKey then
        if all.managers and all.managers[lookupKey] == true then
            return true
        end
        if all.whitelist and all.whitelist[lookupKey] == true then
            return true
        end
        local minRank = bucket.hierarchy and tonumber(bucket.hierarchy.allianceMinRank)
        if minRank and minRank >= 0 then
            local mRankIdx = self:GetMemberGuildRank(lookupKey)
            if mRankIdx ~= nil and mRankIdx <= minRank then
                return true
            end
        end
    end
    return false
end

function Clan:GetGuildMembersWithAllianceStatus()
    local out = {}
    local bucket = Store:GetClanScopeData()
    local all = bucket.alliance or {}
    local wl = all.whitelist or {}
    local mgrs = all.managers or {}

    local _, myKey = ResolveSelfIdentity()

    if type(Store.social) == "table" then
        for _, m in pairs(Store.social) do
            if type(m) == "table" and m.sources and m.sources.guild == true and m.lookupKey then
                table.insert(out, {
                    lookupKey = m.lookupKey,
                    displayName = m.displayName or m.name or "?",
                    classFile = m.classFile,
                    level = m.level or 0,
                    rank = m.rankName or m.rank or "",
                    authorized = (all.accessMode == "ALL") or (wl[m.lookupKey] == true) or (mgrs[m.lookupKey] == true),
                    isManager = mgrs[m.lookupKey] == true,
                    isSelf = (m.lookupKey == myKey),
                })
            end
        end
    end

    table.sort(out, function(a, b)
        if a.isManager ~= b.isManager then
            return a.isManager
        end
        if a.authorized ~= b.authorized then
            return a.authorized
        end
        return (a.displayName or "") < (b.displayName or "")
    end)
    return out
end

local function CollectExternalAllianceRecipients(self, maxCount)
    local targets = {}
    local seen = {}
    local limit = maxCount or 6
    local myGuildNorm = NormalizeGuildKey((Store.guildInfo and Store.guildInfo.name) or "")
    local myFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil

    local function PushTarget(rawName, guildName, row)
        if #targets >= limit then return end
        if not guildName or guildName == "" or not self:IsAlliedGuild(guildName) then return end
        if myGuildNorm ~= "" and NormalizeGuildKey(guildName) == myGuildNorm then return end
        local foreverClean = (Compat.FormatForeverTarget and Compat.FormatForeverTarget(rawName)) or rawName
        local clean = Compat.CleanPayloadField and Compat.CleanPayloadField(foreverClean or "", 40) or Safe.String(foreverClean)
        if not clean or clean == "" or Compat.IsMe(clean) then return end
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(clean)
        local key = (parsed and parsed.lookupKey) or clean:lower()
        local socRow = (row and row.faction) and row or (Store and Store.socialByLookup and Store.socialByLookup[key])
        if socRow then
            if socRow.samePool == false then return end
            if myFaction and socRow.faction and socRow.faction ~= "" and socRow.faction ~= myFaction then return end
        end
        if seen[key] then return end
        seen[key] = true
        table.insert(targets, clean)
    end

    if type(Store.social) == "table" then
        for _, row in pairs(Store.social) do
            if #targets >= limit then break end
            if type(row) == "table" and row.online and not (row.sources and row.sources.guild) then
                PushTarget(row.characterName or row.displayName, row.guild, row)
            end
        end
    end

    if type(Store.nearby) == "table" then
        local now = time()
        for _, nRow in pairs(Store.nearby) do
            if #targets >= limit then break end
            if type(nRow) == "table" and (now - (nRow.lastSeen or 0)) <= 600 then
                PushTarget(nRow.displayName, nRow.guild, nRow)
            end
        end
    end

    return targets
end

function Clan:SendAllianceChat(rawText)
    if not (IsInGuild and IsInGuild()) then
        ns:Print(L["No guild"])
        return false
    end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        ns:Print(L["Enable Clan guild sync (opt-in) in Settings or above to sync with guildmates."])
        return false
    end
    if not self:IsMemberAllianceAuthorized() then
        ns:Print(L["You do not have permission to use Alliance Chat."])
        return false
    end
    local cleanText = Compat.CleanPayloadField(rawText or "", 120)
    if cleanText == "" then return false end

    local myGuild = Safe.String(Safe.Call(GetGuildInfo, "player")) or ""
    local myName = ResolveSelfIdentity()
    local _, myClass = Safe.Call(UnitClass, "player")
    local msgId = ("a%d_%d"):format(time() % 100000, math.random(10, 99))

    local payload = string.format(
        "ALM~%s~%s~%s~%s~%s",
        Compat.CleanPayloadField(myGuild, 32),
        Compat.CleanPayloadField(myName, 36),
        myClass or "",
        cleanText,
        msgId
    )
    local sent = self:SendGuildSync(payload)
    if not sent then
        ns:Print(L["Please wait a moment before sending another alliance message."])
        return false
    end

    for _, recipient in ipairs(CollectExternalAllianceRecipients(self, 6)) do
        SendExternalLFGPacket(self, payload, "WHISPER", recipient)
    end
    return true, msgId
end

function Clan:IsAlliedGuild(rawGuildName)
    if not rawGuildName or rawGuildName == "" then return false end
    local stance = self:LookupGuildStance(rawGuildName)
    if stance == "ALLY" then return true end
    local bucket = Store:GetClanScopeData()
    local norm = NormalizeGuildKey(rawGuildName)
    if bucket.alliance and bucket.alliance.alliedGuilds and bucket.alliance.alliedGuilds[norm] then
        return true
    end
    return false
end

function Clan:BroadcastScoutAlert(targetName, targetGuild, level, classFile, zone, coordsText)
    if not targetName or targetName == "" then return false end
    local cleanName = Compat.CleanPayloadField(targetName, 32)
    local cleanGuild = Compat.CleanPayloadField(targetGuild or "", 32)
    local cleanZone = Compat.CleanPayloadField(zone or "", 32)
    local cleanCoords = Compat.CleanPayloadField(coordsText or "", 16)
    local lvl = level or 0

    local guildTag = cleanGuild ~= "" and (" <" .. cleanGuild .. ">") or ""
    local lvlTag = lvl > 0 and (" (Lv " .. lvl .. ")") or ""
    local locTag = (cleanZone ~= "" and cleanCoords ~= "") and (" - " .. cleanZone .. " (" .. cleanCoords .. ")") or ""
    local chatMsg = string.format("[SocialCentral Scout] %s%s%s%s!", cleanName, guildTag, lvlTag, locTag)

    if IsInGuild and IsInGuild() then
        self:SendGuildSync("SCT~" .. cleanName .. "~" .. cleanGuild .. "~" .. lvl .. "~" .. (classFile or "") .. "~" .. cleanZone .. "~" .. cleanCoords)
    end

    ns:Print("|cffff4444%s|r", chatMsg)
    return true
end

function Clan:GetClanInfo()
    local bucket = Store:GetClanScopeData()
    local info = bucket.clanInfo or {}
    return {
        rev = info.rev or 0,
        updatedAt = info.updatedAt or 0,
        updatedBy = info.updatedBy or "",
        editMode = (info.editMode == "ALL") and "ALL" or "OFFICERS",
        summary = info.summary or "",
        schedule = info.schedule or "",
        rules = info.rules or "",
        contacts = info.contacts or "",
    }
end

function Clan:SaveClanInfo(summary, schedule, rules, contacts, editMode)
    if not (IsInGuild and IsInGuild()) then
        ns:Print(L["No guild"])
        return false
    end
    local canEdit, isOfficer = self:CanEditClanManagement()
    if not canEdit then
        ns:Print(L["Only guild officers can edit Clan Management right now."])
        return false
    end

    local bucket = Store:GetClanScopeData()
    local info = bucket.clanInfo
    local myName = ResolveSelfIdentity()
    local nextRev = math.max(time(), (info.rev or 0) + 1)

    info.summary = Compat.CleanPayloadField(summary or "", 60)
    info.schedule = Compat.CleanPayloadField(schedule or "", 55)
    info.rules = Compat.CleanPayloadField(rules or "", 115)
    info.contacts = Compat.CleanPayloadField(contacts or "", 60)
    if self:IsGuildLeader() and (editMode == "LEADER" or editMode == "OFFICERS" or editMode == "ALL") then
        info.editMode = (editMode == "ALL") and "ALL" or "OFFICERS"
        if bucket.hierarchy then
            bucket.hierarchy.infoMode = editMode
            bucket.hierarchy.rev = math.max(time(), (bucket.hierarchy.rev or 0) + 1)
            bucket.hierarchy.updatedAt = time()
            bucket.hierarchy.updatedBy = myName
        end
    elseif isOfficer and (editMode == "ALL" or editMode == "OFFICERS") then
        info.editMode = editMode
        if bucket.hierarchy and (bucket.hierarchy.infoMode == "ALL" or bucket.hierarchy.infoMode == "OFFICERS") then
            bucket.hierarchy.infoMode = editMode
        end
    end
    info.rev = nextRev
    info.updatedAt = time()
    info.updatedBy = myName

    local tok = ComputeGuildScopeToken()
    if tok ~= "" and ns.db and ns.db.settings and ns.db.settings.clanSync then
        EnqueueIntelPacket(("CINF~%s~%s~%d~%s~%s~%s"):format(
            tok,
            ns.version or "0.0.0",
            nextRev,
            info.editMode,
            info.summary,
            info.schedule
        ))
        EnqueueIntelPacket(("CINF2~%s~%d~%s~%s"):format(
            tok,
            nextRev,
            info.rules,
            info.contacts
        ))
        if self:IsGuildLeader() and bucket.hierarchy then
            local h = bucket.hierarchy
            EnqueueIntelPacket(("CHIR~%s~%d~%s~%d~%s~%d~%s~%d~%d"):format(
                tok,
                h.rev or nextRev,
                h.diplomacyMode or "LEADER",
                h.diplomacyMaxRank or 1,
                h.infoMode or "OFFICERS",
                h.infoMaxRank or 1,
                h.eventModMode or "OFFICERS",
                h.eventModMaxRank or 1,
                h.allianceMinRank or -1
            ))
        end
    end
    ns:Emit("CLAN_UPDATED")
    ns:Emit("CLAN_DIPLOMACY_UPDATED")
    ns:Emit("CLAN_HIERARCHY_UPDATED")
    return true
end

function Clan:LookupGuildStance(rawGuildName)
    local key = NormalizeGuildKey(rawGuildName)
    if key == "" then
        return nil, nil
    end
    local bucket = Store:GetClanScopeData()
    local entry = bucket.diplomacy and bucket.diplomacy.guilds and bucket.diplomacy.guilds[key]
    if type(entry) == "table" and (entry.stance == "ALLY" or entry.stance == "ENEMY" or entry.stance == "NEUTRAL") then
        return entry.stance, entry
    end
    return nil, nil
end

function Clan:GetDiplomacyList(filterStance)
    local out = {}
    local bucket = Store:GetClanScopeData()
    local guilds = bucket.diplomacy and bucket.diplomacy.guilds or {}
    local rank = { ENEMY = 1, ALLY = 2, NEUTRAL = 3 }
    for _, entry in pairs(guilds) do
        if type(entry) == "table" and entry.name and entry.name ~= "" then
            if not filterStance or filterStance == "all" or entry.stance == filterStance then
                table.insert(out, entry)
            end
        end
    end
    table.sort(out, function(a, b)
        local ra, rb = rank[a.stance] or 9, rank[b.stance] or 9
        if ra ~= rb then return ra < rb end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

function Clan:SetGuildStance(rawGuildName, stance, reason, faction)
    local inGuild = Safe.Value(IsInGuild and IsInGuild()) == true
    if not inGuild then
        ns:Print(L["No guild"])
        return false
    end
    local canDip, authSummary = self:CanManageDiplomacy()
    if not canDip then
        ns:Print(L["Only guild leaders (%s) can define Allied or Enemy guilds."]:format(authSummary or L["Guild Leader Only"]))
        return false
    end
    local cleanGuild = Compat.CleanPayloadField(rawGuildName or "", 40)
    local key = NormalizeGuildKey(cleanGuild)
    if cleanGuild == "" or key == "" then
        ns:Print(L["Type a valid guild name."])
        return false
    end
    local myGuildKey = NormalizeGuildKey((Store.guildInfo and Store.guildInfo.name) or "")
    if myGuildKey ~= "" and key == myGuildKey then
        ns:Print(L["Cannot mark your own guild in Diplomacy."])
        return false
    end
    local cleanStance = (stance == "ALLY" or stance == "ENEMY") and stance or "NEUTRAL"
    local cleanReason = Compat.CleanPayloadField(reason or "", 48)
    local cleanFaction = (faction == "Alliance" or faction == "Horde") and faction or ""
    if cleanFaction == "" and Store then
        if type(Store.social) == "table" then
            for _, row in pairs(Store.social) do
                if type(row) == "table" and row.guild and NormalizeGuildKey(row.guild) == key and (row.faction == "Alliance" or row.faction == "Horde") then
                    cleanFaction = row.faction
                    break
                end
            end
        end
        if cleanFaction == "" and type(Store.nearby) == "table" then
            for _, nRow in pairs(Store.nearby) do
                if type(nRow) == "table" and nRow.guild and NormalizeGuildKey(nRow.guild) == key and (nRow.faction == "Alliance" or nRow.faction == "Horde") then
                    cleanFaction = nRow.faction
                    break
                end
            end
        end
    end
    local myFac = Compat.PlayerFaction and Compat.PlayerFaction() or nil
    if cleanStance == "ALLY" and myFac and cleanFaction ~= "" and cleanFaction ~= myFac then
        ns:Print(L["Allied Clans can only be set for guilds of your own faction."])
        return false
    end
    local bucket = Store:GetClanScopeData()
    local dip = bucket.diplomacy
    local nextRev = math.max(time(), (dip.rev or 0) + 1)
    local myName = ResolveSelfIdentity()

    dip.rev = nextRev
    dip.updatedAt = time()
    dip.updatedBy = myName
    dip.guilds[key] = {
        key = key,
        name = cleanGuild,
        stance = cleanStance,
        reason = cleanReason,
        faction = cleanFaction,
        addedBy = myName,
        localOnly = false,
        rev = nextRev,
        updatedAt = time(),
    }

    local tok = ComputeGuildScopeToken()
    if tok ~= "" and ns.db and ns.db.settings and ns.db.settings.clanSync then
        EnqueueIntelPacket(("CDIP~%s~%s~%d~%s~%s~%s~%s~%s"):format(
            tok,
            ns.version or "0.0.0",
            nextRev,
            cleanStance,
            key:sub(1, 32),
            cleanGuild,
            cleanFaction,
            cleanReason
        ))
    end

    ns:Emit("CLAN_UPDATED")
    ns:Emit("CLAN_DIPLOMACY_UPDATED")
    return true
end

function Clan:RemoveGuildDiplomacy(guildKey)
    if not guildKey or guildKey == "" then return false end
    local bucket = Store:GetClanScopeData()
    local existing = bucket.diplomacy and bucket.diplomacy.guilds and bucket.diplomacy.guilds[guildKey]
    if not existing then return false end

    local canDip, authSummary = self:CanManageDiplomacy()
    if not canDip then
        ns:Print(L["Only guild leaders (%s) can define Allied or Enemy guilds."]:format(authSummary or L["Guild Leader Only"]))
        return false
    end

    bucket.diplomacy.guilds[guildKey] = nil
    local nextRev = math.max(time(), (bucket.diplomacy.rev or 0) + 1)
    bucket.diplomacy.rev = nextRev

    if not existing.localOnly then
        local tok = ComputeGuildScopeToken()
        if tok ~= "" and ns.db and ns.db.settings and ns.db.settings.clanSync then
            EnqueueIntelPacket(("CDEL~%s~%s~%d~%s"):format(tok, ns.version or "0.0.0", nextRev, guildKey:sub(1, 32)))
        end
    end

    ns:Emit("CLAN_UPDATED")
    ns:Emit("CLAN_DIPLOMACY_UPDATED")
    return true
end

function Clan:BroadcastDeltaIntel(peerInfoRev, peerDipRev, peerHirRev, peerAllcRev)
    if not (IsInGuild and IsInGuild()) or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        return false
    end
    local tok = ComputeGuildScopeToken()
    if tok == "" then return false end

    local bucket = Store:GetClanScopeData()
    local h = self:GetGuildHierarchyPolicy()
    if self:IsGuildLeader() and (peerHirRev == nil or (h.rev or 0) > peerHirRev) then
        EnqueueIntelPacket(("CHIR~%s~%d~%s~%d~%s~%d~%s~%d~%d"):format(
            tok,
            h.rev or 0,
            h.diplomacyMode,
            h.diplomacyMaxRank,
            h.infoMode,
            h.infoMaxRank,
            h.eventModMode,
            h.eventModMaxRank,
            h.allianceMinRank
        ))
    end

    local info = self:GetClanInfo()
    local canEdit = self:CanEditClanManagement()
    if canEdit and (peerInfoRev == nil or (info.rev or 0) > peerInfoRev) and (info.summary ~= "" or info.rules ~= "" or info.schedule ~= "" or info.contacts ~= "") then
        EnqueueIntelPacket(("CINF~%s~%s~%d~%s~%s~%s"):format(
            tok,
            ns.version or "0.0.0",
            info.rev or 0,
            info.editMode or "OFFICERS",
            Compat.CleanPayloadField(info.summary or "", 60),
            Compat.CleanPayloadField(info.schedule or "", 55)
        ))
        EnqueueIntelPacket(("CINF2~%s~%d~%s~%s"):format(
            tok,
            info.rev or 0,
            Compat.CleanPayloadField(info.rules or "", 115),
            Compat.CleanPayloadField(info.contacts or "", 60)
        ))
    end

    if self:CanManageAlliance() then
        local allCfg = self:GetAllianceConfig()
        if allCfg and allCfg.enabled and (peerAllcRev == nil or (allCfg.rev or 0) > peerAllcRev) then
            EnqueueIntelPacket(("ALLC~%s~%d~%s~%s~%s~%s"):format(
                tok,
                allCfg.rev or 0,
                allCfg.enabled and "1" or "0",
                (allCfg.accessMode == "ALL") and "ALL" or "WHITELIST",
                Compat.CleanPayloadField(allCfg.name or "", 40),
                Compat.CleanPayloadField(allCfg.token or "", 32)
            ))
        end
    end

    local myDipRev = (bucket and bucket.diplomacy and bucket.diplomacy.rev) or 0
    if self:CanManageDiplomacy() and (peerDipRev == nil or myDipRev > peerDipRev) then
        local sentCount = 0
        for _, g in ipairs(self:GetDiplomacyList("all")) do
            if not g.localOnly and sentCount < 10 and (peerDipRev == nil or (g.rev or 0) > peerDipRev) then
                EnqueueIntelPacket(("CDIP~%s~%s~%d~%s~%s~%s~%s~%s"):format(
                    tok,
                    ns.version or "0.0.0",
                    g.rev or 0,
                    g.stance or "NEUTRAL",
                    (g.key or ""):sub(1, 32),
                    Compat.CleanPayloadField(g.name or "", 40),
                    Compat.CleanPayloadField(g.faction or "", 12),
                    Compat.CleanPayloadField(g.reason or "", 48)
                ))
                sentCount = sentCount + 1
            end
        end
    end
    return true
end

function Clan:BroadcastFullIntel()
    return self:BroadcastDeltaIntel(-1, -1, -1, -1)
end

function Clan:RequestIntelSync()
    if not (IsInGuild and IsInGuild()) or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        return false
    end
    local tok = ComputeGuildScopeToken()
    if tok == "" then return false end
    local info = self:GetClanInfo()
    local bucket = Store:GetClanScopeData()
    return self:SendGuildSync(("CREQ~%s~%d~%d~%d~%d"):format(
        tok,
        info.rev or 0,
        (bucket.diplomacy and bucket.diplomacy.rev) or 0,
        (bucket.hierarchy and bucket.hierarchy.rev) or 0,
        (bucket.alliance and bucket.alliance.rev) or 0
    ))
end

function Clan:GetActiveScopeToken()
    return ComputeGuildScopeToken()
end

function Clan:GetMySpecAndRole()
    local specName, roleToken
    if GetSpecialization and GetSpecializationInfo then
        local specIdx = Safe.Number(Safe.Call(GetSpecialization))
        if specIdx and specIdx > 0 then
            local ok, _, sName, _, _, sRole = pcall(GetSpecializationInfo, specIdx)
            if ok then
                specName = Safe.String(sName)
                roleToken = Safe.String(sRole)
            end
        end
    end
    if not roleToken and GetSpecializationRole and GetSpecialization then
        local specIdx = Safe.Number(Safe.Call(GetSpecialization))
        if specIdx and specIdx > 0 then
            roleToken = Safe.String(Safe.Call(GetSpecializationRole, specIdx))
        end
    end
    if not roleToken and GetNumTalentTabs and GetTalentTabInfo then
        local numTabs = Safe.Number(Safe.Call(GetNumTalentTabs)) or 0
        local bestPts, bestTabIdx, bestTabName = 0, nil, nil
        for t = 1, numTabs do
            local okT, tName, _, ptsSpent = pcall(GetTalentTabInfo, t)
            if okT then
                local cleanName = Safe.String(tName)
                local pts = Safe.Number(ptsSpent) or 0
                if pts > bestPts then
                    bestPts = pts
                    bestTabIdx = t
                    bestTabName = cleanName
                end
            end
        end
        if bestTabIdx and bestPts > 0 then
            specName = bestTabName
            local _, classFile = Safe.Call(UnitClass, "player")
            local cf = Safe.String(classFile)
            if cf == "WARRIOR" then
                roleToken = (bestTabIdx == 3) and "TANK" or "DPS"
            elseif cf == "PALADIN" then
                if bestTabIdx == 1 then
                    roleToken = "HEALER"
                elseif bestTabIdx == 2 then
                    roleToken = "TANK"
                else
                    roleToken = "DPS"
                end
            elseif cf == "PRIEST" then
                roleToken = (bestTabIdx == 3) and "DPS" or "HEALER"
            elseif cf == "SHAMAN" then
                roleToken = (bestTabIdx == 3) and "HEALER" or "DPS"
            elseif cf == "DRUID" then
                roleToken = (bestTabIdx == 3) and "HEALER" or "DPS"
            else
                roleToken = "DPS"
            end
        end
    end
    if roleToken == "TANK" or roleToken == "HEALER" then
        return roleToken, specName
    end
    return "DPS", specName
end

local CLASS_CAPABLE_ROLES = {
    WARRIOR = { TANK = true, HEALER = false, DPS = true },
    PALADIN = { TANK = true, HEALER = true,  DPS = true },
    DRUID   = { TANK = true, HEALER = true,  DPS = true },
    PRIEST  = { TANK = false, HEALER = true, DPS = true },
    SHAMAN  = { TANK = false, HEALER = true, DPS = true },
    HUNTER  = { TANK = false, HEALER = false, DPS = true },
    MAGE    = { TANK = false, HEALER = false, DPS = true },
    ROGUE   = { TANK = false, HEALER = false, DPS = true },
    WARLOCK = { TANK = false, HEALER = false, DPS = true },
}

local TANK_FAVORED_RACES = {
    Tauren = true,
    Dwarf = true,
    NightElf = true,
    Human = true,
    Orc = true,
}

local HEAL_FAVORED_RACES = {
    Human = true,
    Dwarf = true,
    NightElf = true,
    Draenei = true,
    BloodElf = true,
    Troll = true,
    Scourge = true,
    Undead = true,
    Tauren = true,
}

function Clan:GetRecommendedRolesForCharacter()
    local classLoc, classFile = Safe.Call(UnitClass, "player")
    classLoc = Safe.String(classLoc) or ""
    classFile = Safe.String(classFile) or "WARRIOR"
    local raceLoc, raceFile = Safe.Call(UnitRace, "player")
    raceLoc = Safe.String(raceLoc) or ""
    raceFile = Safe.String(raceFile) or ""
    local lvl = Safe.Number(Safe.Call(UnitLevel, "player")) or 1

    local primaryRole, specName = self:GetMySpecAndRole()
    local capSrc = CLASS_CAPABLE_ROLES[classFile] or { TANK = false, HEALER = false, DPS = true }
    local capable = {
        TANK = capSrc.TANK == true,
        HEALER = capSrc.HEALER == true,
        DPS = capSrc.DPS ~= false,
    }

    local rec = { TANK = false, HEALER = false, DPS = false }
    local totalTalentPts = 0
    if GetNumTalentTabs and GetTalentTabInfo then
        local numTabs = Safe.Number(Safe.Call(GetNumTalentTabs)) or 0
        for t = 1, numTabs do
            local okT, _, _, ptsSpent = pcall(GetTalentTabInfo, t)
            if okT then
                totalTalentPts = totalTalentPts + (Safe.Number(ptsSpent) or 0)
            end
        end
    end

    if classFile == "WARRIOR" then
        if primaryRole == "TANK" then
            rec.TANK = true
            if lvl < 50 then rec.DPS = true end
        else
            rec.DPS = true
            if (TANK_FAVORED_RACES[raceFile] and lvl < 52) or totalTalentPts < 15 then
                rec.TANK = true
            end
        end
    elseif classFile == "PALADIN" then
        if primaryRole == "HEALER" then
            rec.HEALER = true
            if lvl < 45 then rec.TANK = true end
        elseif primaryRole == "TANK" then
            rec.TANK = true
            if lvl < 45 then rec.HEALER = true end
        else
            rec.DPS = true
            if lvl < 50 then
                rec.HEALER = true
                if TANK_FAVORED_RACES[raceFile] then rec.TANK = true end
            elseif HEAL_FAVORED_RACES[raceFile] and totalTalentPts < 15 then
                rec.HEALER = true
            end
        end
    elseif classFile == "DRUID" then
        if primaryRole == "HEALER" then
            rec.HEALER = true
            if lvl < 45 then rec.DPS = true end
        else
            rec.DPS = true
            if TANK_FAVORED_RACES[raceFile] and lvl < 55 then
                rec.TANK = true
            end
            if lvl < 45 or totalTalentPts < 15 then
                rec.HEALER = true
            end
        end
    elseif classFile == "PRIEST" then
        if primaryRole == "HEALER" or lvl < 45 or totalTalentPts < 15 then
            rec.HEALER = true
        end
        if primaryRole == "DPS" or lvl < 52 then
            rec.DPS = true
        end
    elseif classFile == "SHAMAN" then
        if primaryRole == "HEALER" or lvl < 45 or totalTalentPts < 15 then
            rec.HEALER = true
        end
        if primaryRole == "DPS" or lvl < 55 then
            rec.DPS = true
        end
    else
        rec.DPS = true
    end

    if not (rec.TANK or rec.HEALER or rec.DPS) then
        rec[primaryRole] = true
    end

    local roleNames = {}
    if rec.TANK then roleNames[#roleNames + 1] = L["Tank"] end
    if rec.HEALER then roleNames[#roleNames + 1] = L["Healer"] end
    if rec.DPS then roleNames[#roleNames + 1] = L["DPS"] end
    local whoDesc = (raceLoc ~= "" and classLoc ~= "") and (raceLoc .. " " .. classLoc) or (classLoc ~= "" and classLoc or L["Player"])

    return {
        primaryRole = primaryRole,
        specName = specName,
        classFile = classFile,
        classLoc = classLoc,
        raceFile = raceFile,
        raceLoc = raceLoc,
        capable = capable,
        recommended = rec,
        whoDesc = whoDesc,
        rolesLabel = table.concat(roleNames, " / "),
    }
end

function Clan:CreateEventCall(category, title, whenText, needT, needH, needD, minLvl, creatorRole)
    if not IsValidCategory(category) then category = "DUNGEON" end
    local cleanTitle = Compat.CleanPayloadField(title or "", 40)
    if cleanTitle == "" then
        ns:Print(L["Enter a valid title for the Clan event."])
        return false
    end
    local cleanWhen = Compat.CleanPayloadField(whenText or "", 24)
    if cleanWhen == "" then cleanWhen = L["Now"] end

    local nT = math.max(0, math.min(5, tonumber(needT) or 0))
    local nH = math.max(0, math.min(10, tonumber(needH) or 0))
    local nD = math.max(0, math.min(30, tonumber(needD) or 0))
    local nMinLvl = math.max(0, math.min(100, tonumber(minLvl) or 0))

    local resolvedRole = creatorRole
    if resolvedRole == "DAMAGER" then resolvedRole = "DPS" end
    if not IsValidRole(resolvedRole) then
        resolvedRole = self:GetMySpecAndRole()
    end

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local parsed = Compat.ParseCharacterName(myName)
    local shortTag = (parsed and parsed.firstName or "me"):sub(1, 6):lower()
    local eventId = shortTag .. "-" .. tostring(time() % 100000)

    local bucket = Store:GetClanScopeData()
    local myParsed = parsed
    local _, myClass = Safe.Call(UnitClass, "player")
    bucket.events[eventId] = {
        id = eventId,
        category = category,
        title = cleanTitle,
        whenText = cleanWhen,
        needT = nT,
        needH = nH,
        needD = nD,
        minLvl = nMinLvl,
        isOpen = true,
        creator = (myParsed and myParsed.displayName) or myName,
        creatorKey = (myParsed and myParsed.lookupKey) or shortTag,
        createdAt = time(),
        updatedAt = time(),
        signups = {
            [(myParsed and myParsed.lookupKey) or shortTag] = {
                name = (myParsed and myParsed.displayName) or myName,
                classFile = Safe.String(myClass),
                role = resolvedRole,
                updatedAt = time(),
            },
        },
    }

    local payload = ("EVT~%s~%s~%s~%s~%d~%d~%d~%d~1"):format(eventId, category, cleanTitle, cleanWhen, nT, nH, nD, nMinLvl)
    local sentSync = self:SendGuildSync(payload)
    for _, recipient in ipairs(CollectExternalAllianceRecipients(self, 6)) do
        SendExternalLFGPacket(self, payload, "WHISPER", recipient)
    end
    local syncLabel = sentSync and L["shared with Guild [SC]"] or L["saved locally — Guild Sync is off"]
    ns:Print(L["Event '%s' created (%s)."]:format(cleanTitle, syncLabel))
    ns:Emit("CLAN_UPDATED")
    return true, bucket.events[eventId]
end

function Clan:ToggleEventOpen(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local _, myKey = ResolveSelfIdentity()
    local isCreator = (myKey ~= nil and evt.creatorKey == myKey)
    if not isCreator and not self:CanModerateEvents() then
        ns:Print(L["Only the group creator can open or close this Clan listing."])
        return false
    end
    evt.isOpen = evt.isOpen == false
    evt.updatedAt = time()
    self:SendGuildSync(("EVS~%s~%s"):format(Compat.CleanPayloadField(eventId, 16), evt.isOpen and "1" or "0"))
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:ReannounceEvent(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local payload = ("EVT~%s~%s~%s~%s~%d~%d~%d~%d~%s"):format(
        Compat.CleanPayloadField(evt.id, 16),
        evt.category or "DUNGEON",
        Compat.CleanPayloadField(evt.title or "", 40),
        Compat.CleanPayloadField(evt.whenText or L["Now"], 24),
        tonumber(evt.needT) or 0,
        tonumber(evt.needH) or 0,
        tonumber(evt.needD) or 0,
        tonumber(evt.minLvl) or 0,
        evt.isOpen ~= false and "1" or "0"
    )
    local sent = self:SendGuildSync(payload)
    for _, recipient in ipairs(CollectExternalAllianceRecipients(self, 6)) do
        SendExternalLFGPacket(self, payload, "WHISPER", recipient)
    end
    if not sent then
        ns:Print(L["Clan sync throttled or blocked during combat."])
        return false
    end
    evt.updatedAt = time()
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:SetMyProfessions(prof1, prof2, craftNote, prof1Rank, prof2Rank)
    if not IsValidProfession(prof1) then prof1 = "NONE" end
    if not IsValidProfession(prof2) then prof2 = "NONE" end
    local bucket = Store:GetClanScopeData()
    local cleanNote = Compat.CleanPayloadField(craftNote or "", 40)
    local r1Fallback = (self._myDetectedRanks and self._myDetectedRanks[prof1] and self._myDetectedRanks[prof1].rank) or ""
    local r2Fallback = (self._myDetectedRanks and self._myDetectedRanks[prof2] and self._myDetectedRanks[prof2].rank) or ""
    local cleanR1 = Compat.CleanPayloadField((prof1Rank and prof1Rank ~= "" and prof1Rank) or r1Fallback, 12)
    local cleanR2 = Compat.CleanPayloadField((prof2Rank and prof2Rank ~= "" and prof2Rank) or r2Fallback, 12)
    bucket.myProf1 = prof1
    bucket.myProf2 = prof2
    bucket.myProf1Rank = (prof1 ~= "NONE") and cleanR1 or ""
    bucket.myProf2Rank = (prof2 ~= "NONE") and cleanR2 or ""
    bucket.myCraftNote = cleanNote
    bucket.userClearedProfs = (prof1 == "NONE" and prof2 == "NONE" and cleanNote == "") or nil

    local sent = self:SendGuildSync(("PRF~%s~%s~%s~%s~%s"):format(prof1, prof2, cleanNote, bucket.myProf1Rank, bucket.myProf2Rank))
    if (ns.db and ns.db.settings and ns.db.settings.clanSync) and not sent and IsInGuild and IsInGuild() then
        local waitRem = math.ceil(math.max(0, self.MIN_SEND_INTERVAL - (GetTime() - (self.lastSyncSentAt or 0))))
        if waitRem > 0 then
            ns:Print(L["Professions saved locally; guild broadcast ready in %ds."]:format(waitRem))
        end
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:SignupEvent(eventId, role)
    if not IsValidRole(role) then return false end
    local bucket = Store:GetClanScopeData()
    local evt = EnsureEventRecord(bucket, eventId)
    if not evt then return false end

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local myParsed = Compat.ParseCharacterName(myName)
    if not myParsed then return false end
    local _, myClass = Safe.Call(UnitClass, "player")

    if role == "DECLINE" then
        evt.signups[myParsed.lookupKey] = nil
    else
        evt.signups[myParsed.lookupKey] = {
            name = myParsed.displayName,
            classFile = Safe.String(myClass),
            role = role,
            updatedAt = time(),
        }
    end
    evt.updatedAt = time()

    local sigPayload = ("SIG~%s~%s~%s"):format(Compat.CleanPayloadField(eventId, 16), role, Safe.String(myClass) or "")
    self:SendGuildSync(sigPayload)
    if evt.isAlliedEvent and evt.creator and not Compat.IsMe(evt.creator) then
        local target = (Compat.FormatForeverTarget and Compat.FormatForeverTarget(evt.creator)) or evt.creator
        SendExternalLFGPacket(self, sigPayload, "WHISPER", target)
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:RemoveEvent(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local _, myKey = ResolveSelfIdentity()
    local isCreator = (myKey ~= nil and evt.creatorKey == myKey)
    local canMod = self:CanModerateEvents()
    if not isCreator and not canMod then
        ns:Print(L["Only the creator or authorized guild officers can remove this event."])
        return false
    end

    bucket.events[eventId] = nil
    self:SendGuildSync("DEL~" .. Compat.CleanPayloadField(eventId, 16))
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:RequestClanSync()
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        ns:Print(L["Enable Clan guild sync (opt-in) in Settings or above to sync with guildmates."])
        return false
    end
    self:RequestExternalLFGCatchup()
    if not (IsInGuild and IsInGuild()) then
        ns:Print(L["No guild"])
        return false
    end
    local bucket = Store:GetClanScopeData()
    local tag = IsValidTag(bucket.myTag) and bucket.myTag or "NONE"
    local note = Compat.CleanPayloadField(bucket.myNote or "", 36)
    local p1 = IsValidProfession(bucket.myProf1) and bucket.myProf1 or "NONE"
    local p2 = IsValidProfession(bucket.myProf2) and bucket.myProf2 or "NONE"
    local cNote = Compat.CleanPayloadField(bucket.myCraftNote or "", 40)
    local sent = self:SendGuildSync(("REQ~%s~%s~%s~%s~%s~%s"):format(ns.version or "0.0.0", tag, note, p1, p2, cNote))
    if not sent then
        ns:Print(L["Clan sync throttled or blocked during combat."])
        return false
    end
    return true
end

function Clan:GetPeersList()
    local bucket = Store:GetClanScopeData()
    local socialByLookup = GetGuildSocialLookupMap()

    local out = {}
    for key, peer in pairs(bucket.peers) do
        local live = GetLiveGuildRowFromMap(socialByLookup, key)
        table.insert(out, {
            lookupKey = key,
            displayName = (live and live.displayName) or peer.displayName or key,
            version = peer.version,
            tag = IsValidTag(peer.tag) and peer.tag or "NONE",
            note = peer.note or "",
            level = live and live.level,
            classFile = live and live.classFile,
            area = live and live.area or "",
            online = live ~= nil,
            updatedAt = peer.updatedAt or 0,
        })
    end

    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.updatedAt or 0) > (b.updatedAt or 0)
    end)
    return out
end

function Clan:GetEventsList(filterId)
    local bucket = Store:GetClanScopeData()
    local out = {}
    for _, evt in pairs(bucket.events) do
        local include = true
        if filterId and filterId ~= "all" then
            if filterId == "open" then
                include = evt.isOpen ~= false
            elseif filterId == "need_tank" then
                local sum = self:GetSignupSummary(evt)
                include = evt.isOpen ~= false and (tonumber(evt.needT) or 0) > sum.TANK
            elseif filterId == "need_heal" then
                local sum = self:GetSignupSummary(evt)
                include = evt.isOpen ~= false and (tonumber(evt.needH) or 0) > sum.HEALER
            else
                include = evt.category == filterId
            end
        end
        if include then
            table.insert(out, evt)
        end
    end
    table.sort(out, function(a, b)
        local aOpen = a.isOpen ~= false
        local bOpen = b.isOpen ~= false
        if aOpen ~= bOpen then return aOpen end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return out
end

function Clan:GetOpenEventsCount()
    local bucket = Store:GetClanScopeData()
    local count = 0
    for _, evt in pairs(bucket.events) do
        if type(evt) == "table" and evt.isOpen ~= false then
            count = count + 1
        end
    end
    return count
end

local PROF_ID_TO_KEY = {}
for _, item in ipairs(Clan.PROFESSIONS) do
    if item.id ~= "NONE" and item.labelKey then
        PROF_ID_TO_KEY[item.id] = item.labelKey
    end
end
PROF_ID_TO_KEY.FIRST_AID = "First Aid"

local UTF8_ACCENT_FOLD = {
    ["á"] = "a", ["Á"] = "a", ["à"] = "a", ["À"] = "a", ["â"] = "a", ["Â"] = "a", ["ã"] = "a", ["Ã"] = "a",
    ["é"] = "e", ["É"] = "e", ["ê"] = "e", ["Ê"] = "e", ["è"] = "e", ["È"] = "e",
    ["í"] = "i", ["Í"] = "i", ["ì"] = "i", ["Ì"] = "i", ["î"] = "i", ["Î"] = "i",
    ["ó"] = "o", ["Ó"] = "o", ["ô"] = "o", ["Ô"] = "o", ["õ"] = "o", ["Õ"] = "o", ["ò"] = "o", ["Ò"] = "o",
    ["ú"] = "u", ["Ú"] = "u", ["ù"] = "u", ["Ù"] = "u", ["û"] = "u", ["Û"] = "u", ["ü"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}

local function FoldProfText(str)
    if type(str) ~= "string" or str == "" then return "" end
    if not str:find("[\128-\255]") then
        return str:lower()
    end
    local out = str
    for k, v in pairs(UTF8_ACCENT_FOLD) do
        if out:find(k, 1, true) then
            out = out:gsub(k, v)
        end
    end
    return out:lower()
end

local function NormalizeProfId(val)
    if type(val) ~= "string" or val == "" then return "NONE" end
    if val == "FIRST_AID" or IsValidProfession(val) then
        return val
    end
    return "NONE"
end

local EXACT_PROF_ALIASES = {
    alchemy = "ALCHEMY", alquimia = "ALCHEMY",
    blacksmithing = "BLACKSMITHING", ferraria = "BLACKSMITHING", herreria = "BLACKSMITHING",
    enchanting = "ENCHANTING", encantamento = "ENCHANTING", encantamiento = "ENCHANTING",
    engineering = "ENGINEERING", engenharia = "ENGINEERING", ingenieria = "ENGINEERING",
    herbalism = "HERBALISM", herborismo = "HERBALISM", herboristeria = "HERBALISM", botanica = "HERBALISM",
    leatherworking = "LEATHERWORKING", couraria = "LEATHERWORKING", peleteria = "LEATHERWORKING", coureiro = "LEATHERWORKING",
    mining = "MINING", mineracao = "MINING", mineria = "MINING",
    skinning = "SKINNING", esfolamento = "SKINNING", desuello = "SKINNING",
    tailoring = "TAILORING", alfaiataria = "TAILORING", sastreria = "TAILORING",
    cooking = "COOKING", culinaria = "COOKING", cocina = "COOKING",
    fishing = "FISHING", pesca = "FISHING",
    ["first aid"] = "FIRST_AID", ["primeiros socorros"] = "FIRST_AID", ["primeros auxilios"] = "FIRST_AID",
}

local NOTE_TOKEN_RULES = {
    { pat = "primeiros socor", id = "FIRST_AID" },
    { pat = "primeros auxil", id = "FIRST_AID" },
    { pat = "first aid", id = "FIRST_AID" },
    { pat = "%f[%w]alchem", id = "ALCHEMY" },
    { pat = "%f[%w]alquim", id = "ALCHEMY" },
    { pat = "%f[%w]alch%f[%W]", id = "ALCHEMY" },
    { pat = "%f[%w]alq%f[%W]", id = "ALCHEMY" },
    { pat = "%f[%w]blacksmit", id = "BLACKSMITHING" },
    { pat = "%f[%w]ferrar", id = "BLACKSMITHING" },
    { pat = "%f[%w]ferreiro", id = "BLACKSMITHING" },
    { pat = "%f[%w]herrer", id = "BLACKSMITHING" },
    { pat = "%f[%w]bs%f[%W]", id = "BLACKSMITHING" },
    { pat = "%f[%w]enchant", id = "ENCHANTING" },
    { pat = "%f[%w]encant", id = "ENCHANTING" },
    { pat = "%f[%w]ench%f[%W]", id = "ENCHANTING" },
    { pat = "%f[%w]eng[ie]", id = "ENGINEERING" },
    { pat = "%f[%w]engenh", id = "ENGINEERING" },
    { pat = "%f[%w]ingeni", id = "ENGINEERING" },
    { pat = "%f[%w]eng%f[%W]", id = "ENGINEERING" },
    { pat = "%f[%w]herbal", id = "HERBALISM" },
    { pat = "%f[%w]herbor", id = "HERBALISM" },
    { pat = "%f[%w]herb%f[%W]", id = "HERBALISM" },
    { pat = "%f[%w]botan", id = "HERBALISM" },
    { pat = "%f[%w]leather", id = "LEATHERWORKING" },
    { pat = "%f[%w]courar", id = "LEATHERWORKING" },
    { pat = "%f[%w]peleter", id = "LEATHERWORKING" },
    { pat = "%f[%w]lw%f[%W]", id = "LEATHERWORKING" },
    { pat = "%f[%w]mining%f[%W]", id = "MINING" },
    { pat = "%f[%w]minera", id = "MINING" },
    { pat = "%f[%w]mineria", id = "MINING" },
    { pat = "%f[%w]miner%f[%W]", id = "MINING" },
    { pat = "%f[%w]min%f[%W]%s*[/+&]", id = "MINING" },
    { pat = "[/+&]%s*min%f[%W]", id = "MINING" },
    { pat = "%f[%w]skinning", id = "SKINNING" },
    { pat = "%f[%w]esfol", id = "SKINNING" },
    { pat = "%f[%w]desuell", id = "SKINNING" },
    { pat = "%f[%w]tailor", id = "TAILORING" },
    { pat = "%f[%w]alfaiat", id = "TAILORING" },
    { pat = "%f[%w]sastrer", id = "TAILORING" },
    { pat = "%f[%w]cooking", id = "COOKING" },
    { pat = "%f[%w]culin", id = "COOKING" },
    { pat = "%f[%w]cocina", id = "COOKING" },
    { pat = "%f[%w]fishing", id = "FISHING" },
    { pat = "%f[%w]pesca%f[%W]", id = "FISHING" },
}

function Clan:MatchProfessionId(rawName)
    if type(rawName) ~= "string" or rawName == "" then return "NONE" end
    local up = rawName:upper()
    if IsValidProfession(up) or up == "FIRST_AID" then
        return up
    end
    local folded = Compat.Trim and Compat.Trim(FoldProfText(rawName)) or FoldProfText(rawName)
    if EXACT_PROF_ALIASES[folded] then
        return EXACT_PROF_ALIASES[folded]
    end
    for _, rule in ipairs(NOTE_TOKEN_RULES) do
        if folded:find(rule.pat) then
            return rule.id
        end
    end
    return "NONE"
end

function Clan:ParseProfessionsFromNote(noteText)
    if type(noteText) ~= "string" or noteText == "" then
        return "NONE", "NONE"
    end
    local folded = FoldProfText(noteText)
    local found = {}
    local seen = {}
    for _, rule in ipairs(NOTE_TOKEN_RULES) do
        local pos = folded:find(rule.pat)
        if pos and not seen[rule.id] then
            seen[rule.id] = true
            table.insert(found, { id = rule.id, pos = pos })
        end
    end
    table.sort(found, function(a, b) return a.pos < b.pos end)
    local p1 = found[1] and found[1].id or "NONE"
    local p2 = found[2] and found[2].id or "NONE"
    return p1, p2
end

local function CollectLiveCharacterProfessions()
    local list = {}
    local seen = {}
    if GetProfessions and GetProfessionInfo then
        local okP, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
        if okP then
            local slots = { Safe.Value(p1), Safe.Value(p2), Safe.Value(p3), Safe.Value(p4), Safe.Value(p5), Safe.Value(p6) }
            for idx = 1, 6 do
                if slots[idx] then
                    local ok, name, _, rank, maxRank = pcall(GetProfessionInfo, slots[idx])
                    name = ok and Safe.String(name) or nil
                    if name and name ~= "" and not seen[name:lower()] then
                        seen[name:lower()] = true
                        list[#list + 1] = {
                            name = name,
                            rank = Safe.Number(rank) or 0,
                            maxRank = Safe.Number(maxRank) or 0,
                            isPrimary = (idx <= 2),
                        }
                    end
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local count = Safe.Number(Safe.Call(GetNumSkillLines)) or 0
        local currentHeader = ""
        for i = 1, count do
            local ok, sName, isHeader, _, sRank, _, _, sMaxRank, isAbandonable = pcall(GetSkillLineInfo, i)
            if ok then
                sName = Safe.String(sName)
                if Safe.Value(isHeader) then
                    currentHeader = sName and FoldProfText(sName) or ""
                elseif sName and sName ~= "" and not seen[sName:lower()] then
                    local inProfHeader = currentHeader:find("profiss", 1, true)
                        or currentHeader:find("profession", 1, true)
                        or currentHeader:find("profesion", 1, true)
                    local abandonable = (Safe.Value(isAbandonable) == true) or (Safe.Number(isAbandonable) == 1)
                    local pid = Clan:MatchProfessionId(sName)
                    if inProfHeader or abandonable or (pid ~= "NONE") then
                        seen[sName:lower()] = true
                        list[#list + 1] = {
                            name = sName,
                            rank = Safe.Number(sRank) or 0,
                            maxRank = Safe.Number(sMaxRank) or 0,
                            isPrimary = (abandonable or (inProfHeader and pid ~= "COOKING" and pid ~= "FIRST_AID" and pid ~= "FISHING")) and true or false,
                        }
                    end
                end
            end
        end
    end
    if #list == 0 and ns.db and ns.db.alts then
        local cur = (Store and Store.GetCurrentAltRecord and Store:GetCurrentAltRecord())
            or (Compat.CharacterKey and ns.db.alts[Compat.CharacterKey()])
        if cur and type(cur.professions) == "table" then
            return cur.professions
        end
    end
    return list
end

function Clan:AutoDetectMyProfessions(forceApply)
    self._lastProfAutoDetectAt = (GetTime and GetTime()) or time()
    local rawList = CollectLiveCharacterProfessions()
    local primaries, secondaries = {}, {}
    local rankById = {}
    for _, ap in ipairs(rawList) do
        if ap and ap.name then
            local pid = self:MatchProfessionId(ap.name)
            if pid ~= "NONE" then
                local rStr = ((ap.maxRank or 0) > 0) and string.format("%d/%d", ap.rank or 0, ap.maxRank or 0) or ""
                if not rankById[pid] then
                    rankById[pid] = { rank = rStr, label = ap.name }
                end
                if ap.isPrimary ~= false and pid ~= "COOKING" and pid ~= "FIRST_AID" and pid ~= "FISHING" then
                    if #primaries < 2 and primaries[1] ~= pid then
                        primaries[#primaries + 1] = pid
                    end
                else
                    secondaries[pid] = { id = pid, name = ap.name, rank = rStr }
                end
            end
        end
    end
    self._myDetectedPrimary = primaries
    self._myDetectedSecondaries = secondaries
    self._myDetectedRanks = rankById

    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    if not bucket then return false end

    local changed = false
    local p1 = NormalizeProfId(bucket.myProf1)
    local p2 = NormalizeProfId(bucket.myProf2)
    if (forceApply or (not bucket.userClearedProfs and p1 == "NONE" and p2 == "NONE")) and #primaries > 0 then
        local np1 = primaries[1] or "NONE"
        local np2 = primaries[2] or "NONE"
        if np1 ~= p1 or np2 ~= p2 then
            bucket.myProf1 = np1
            bucket.myProf2 = np2
            p1, p2 = np1, np2
            changed = true
        end
        if forceApply then
            bucket.userClearedProfs = nil
        end
    end
    local r1 = (p1 ~= "NONE" and rankById[p1] and rankById[p1].rank) or ""
    local r2 = (p2 ~= "NONE" and rankById[p2] and rankById[p2].rank) or ""
    if r1 ~= "" and bucket.myProf1Rank ~= r1 then
        bucket.myProf1Rank = r1
        changed = true
    elseif p1 == "NONE" and bucket.myProf1Rank ~= "" then
        bucket.myProf1Rank = ""
    end
    if r2 ~= "" and bucket.myProf2Rank ~= r2 then
        bucket.myProf2Rank = r2
        changed = true
    elseif p2 == "NONE" and bucket.myProf2Rank ~= "" then
        bucket.myProf2Rank = ""
    end

    if changed then
        ns:Emit("CLAN_UPDATED")
    end
    local profSig = table.concat({ p1, p2, r1, r2 }, "|")
    if profSig ~= "NONE|NONE||" and profSig ~= self._lastAutoSyncedProfSig then
        local hadPrev = (self._lastAutoSyncedProfSig ~= nil)
        self._lastAutoSyncedProfSig = profSig
        if hadPrev and ns.db and ns.db.settings and ns.db.settings.clanSync and not self:IsMessagingLocked() and IsInGuild and IsInGuild() then
            if C_Timer and C_Timer.After and not self._autoProfSyncQueued then
                self._autoProfSyncQueued = true
                C_Timer.After(4.5, function()
                    Clan._autoProfSyncQueued = false
                    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) or Clan:IsMessagingLocked() then return end
                    local curB = Store and Store.GetClanScopeData and Store:GetClanScopeData()
                    if curB then
                        local cp1 = IsValidProfession(curB.myProf1) and curB.myProf1 or "NONE"
                        local cp2 = IsValidProfession(curB.myProf2) and curB.myProf2 or "NONE"
                        local cNote = Compat.CleanPayloadField(curB.myCraftNote or "", 40)
                        Clan:SendGuildSync(("PRF~%s~%s~%s~%s~%s"):format(cp1, cp2, cNote, curB.myProf1Rank or "", curB.myProf2Rank or ""))
                    end
                end)
            end
        end
    end
    return (#primaries > 0 or next(secondaries) ~= nil), p1, p2, r1, r2
end

function Clan:CanEditMyGuildNote()
    if not (IsInGuild and IsInGuild()) then return false end
    return (CanEditPublicNote and Safe.Value(Safe.Call(CanEditPublicNote)) == true) or false
end

function Clan:PublishProfessionsToGuildNote(customNote)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false, L["In Combat"]
    end
    if not self:CanEditMyGuildNote() then
        return false, L["Your guild rank cannot edit your Guild Public Note."]
    end
    local bucket = Store:GetClanScopeData()
    local p1 = NormalizeProfId(bucket.myProf1)
    local p2 = NormalizeProfId(bucket.myProf2)
    if p1 == "NONE" and p2 == "NONE" then
        self:AutoDetectMyProfessions(true)
        p1 = NormalizeProfId(bucket.myProf1)
        p2 = NormalizeProfId(bucket.myProf2)
    end
    if p1 == "NONE" and p2 == "NONE" then
        return false, L["No professions detected to publish."]
    end

    local function ShortProf(pid, rankStr)
        local key = PROF_ID_TO_KEY[pid]
        local lbl = (key and L[key]) or pid
        if lbl and #lbl > 12 then lbl = lbl:sub(1, 12) end
        if rankStr and rankStr ~= "" then
            local cur = rankStr:match("^(%d+)")
            if cur then return lbl .. " " .. cur end
        end
        return lbl
    end

    local parts = {}
    if p1 ~= "NONE" then parts[#parts + 1] = ShortProf(p1, bucket.myProf1Rank) end
    if p2 ~= "NONE" then parts[#parts + 1] = ShortProf(p2, bucket.myProf2Rank) end
    local noteText = table.concat(parts, " / ")
    local extra = Compat.CleanInput(customNote or bucket.myCraftNote or "")
    if extra and extra ~= "" and (#noteText + 3 + #extra) <= 31 then
        noteText = noteText .. " - " .. extra
    end
    if #noteText > 31 then
        parts = {}
        if p1 ~= "NONE" then parts[#parts + 1] = ShortProf(p1, nil) end
        if p2 ~= "NONE" then parts[#parts + 1] = ShortProf(p2, nil) end
        noteText = table.concat(parts, "/")
    end
    if #noteText > 31 then
        noteText = noteText:sub(1, 31)
    end

    local targetIdx = nil
    if GetNumGuildMembers and GetGuildRosterInfo then
        local total = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
        for i = 1, total do
            local okRoster, fullName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
            if okRoster then
                fullName = Safe.String(fullName)
                guid = Safe.String(guid)
                if Compat.IsMe(fullName, guid) then
                    targetIdx = i
                    break
                end
            end
        end
    end
    if not targetIdx then
        return false, L["Guild roster not loaded yet."]
    end
    local ok = false
    if C_GuildInfo and C_GuildInfo.SetNote then
        ok = pcall(C_GuildInfo.SetNote, targetIdx, noteText, true)
    elseif GuildRosterSetPublicNote then
        ok = pcall(GuildRosterSetPublicNote, targetIdx, noteText)
    end
    if ok then
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            pcall(C_GuildInfo.GuildRoster)
        end
        ns:Emit("CLAN_UPDATED")
        return true, noteText
    end
    return false, L["Unable to update Guild Public Note right now."]
end

local CRAFT_KEYWORD_PROF_MAP = {
    flask = "ALCHEMY", frasco = "ALCHEMY", elixir = "ALCHEMY", potion = "ALCHEMY", pocao = "ALCHEMY", pocion = "ALCHEMY", pot = "ALCHEMY", transmut = "ALCHEMY",
    gem = "JEWELCRAFTING", gema = "JEWELCRAFTING", ring = "JEWELCRAFTING", anel = "JEWELCRAFTING", anillo = "JEWELCRAFTING", neck = "JEWELCRAFTING", colar = "JEWELCRAFTING", collar = "JEWELCRAFTING",
    bag = "TAILORING", bolsa = "TAILORING", mochila = "TAILORING", cloth = "TAILORING", tecido = "TAILORING", tela = "TAILORING", spellthread = "TAILORING",
    enchant = "ENCHANTING", encant = "ENCHANTING", vellum = "ENCHANTING", pergaminho = "ENCHANTING", rod = "ENCHANTING",
    scope = "ENGINEERING", mira = "ENGINEERING", bot = "ENGINEERING", repair = "ENGINEERING", jeeves = "ENGINEERING", ammo = "ENGINEERING", bullet = "ENGINEERING",
    buckle = "BLACKSMITHING", fivela = "BLACKSMITHING", hebilla = "BLACKSMITHING", plate = "BLACKSMITHING", placa = "BLACKSMITHING", shield = "BLACKSMITHING", escudo = "BLACKSMITHING",
    glyph = "INSCRIPTION", glifo = "INSCRIPTION", shoulder = "INSCRIPTION", deck = "INSCRIPTION", card = "INSCRIPTION",
    kit = "LEATHERWORKING", drum = "LEATHERWORKING", tambor = "LEATHERWORKING", leg = "LEATHERWORKING", leather = "LEATHERWORKING", couro = "LEATHERWORKING", cuero = "LEATHERWORKING",
    feast = "COOKING", banquete = "COOKING", food = "COOKING", comida = "COOKING",
    bandage = "FIRST_AID", atadura = "FIRST_AID", venda = "FIRST_AID",
    herb = "HERBALISM", erva = "HERBALISM", planta = "HERBALISM",
    ore = "MINING", miner = "MINING", bar = "MINING", barra = "MINING",
}

function Clan:GetProfessionsList(query, profFilter, sourceFilter)
    local nowClock = (GetTime and GetTime()) or 0
    if not self._myDetectedPrimary or (nowClock - (self._lastProfAutoDetectAt or 0)) >= 15 then
        self:AutoDetectMyProfessions(false)
    end
    local bucket = Store:GetClanScopeData()
    local q = (type(query) == "string" and query ~= "") and FoldProfText(query) or nil
    self._lastProfQuery = (type(query) == "string" and query ~= "") and Compat.CleanInput(query) or nil
    local craftProfHint = nil
    if q then
        for kw, mappedProf in pairs(CRAFT_KEYWORD_PROF_MAP) do
            if q:find(kw, 1, true) then
                craftProfHint = mappedProf
                break
            end
        end
    end
    local pf = (type(profFilter) == "string" and profFilter ~= "" and profFilter ~= "ALL") and NormalizeProfId(profFilter) or nil
    local sf = (type(sourceFilter) == "string" and sourceFilter ~= "") and sourceFilter:upper() or "ALL"

    local socialByLookup = GetGuildSocialLookupMap()
    local function GetLiveGuildRow(key)
        return GetLiveGuildRowFromMap(socialByLookup, key)
    end

    local entries = {}
    local function UpsertEntry(key, data)
        if not key or key == "" then return end
        local p1 = NormalizeProfId(data.prof1)
        local p2 = NormalizeProfId(data.prof2)
        if p1 == "NONE" and p2 ~= "NONE" then
            p1, p2 = p2, "NONE"
        end
        local hasSec = type(data.secProfIds) == "table" and next(data.secProfIds) ~= nil
        if p1 == "NONE" and p2 == "NONE" and not hasSec then
            return
        end
        local cur = entries[key]
        if cur then
            if data.isSelf then cur.isSelf = true end
            if data.online then cur.online = true end
            if p1 ~= "NONE" and (cur.prof1 == "NONE" or (data.priority or 0) >= (cur.priority or 0)) then
                cur.prof1 = p1
                cur.prof2 = p2
                if data.prof1Rank and data.prof1Rank ~= "" then cur.prof1Rank = data.prof1Rank end
                if data.prof2Rank and data.prof2Rank ~= "" then cur.prof2Rank = data.prof2Rank end
                if data.sourceTag then cur.sourceTag = data.sourceTag end
                cur.priority = data.priority or cur.priority
            end
            if data.craftNote and data.craftNote ~= "" and (not cur.craftNote or cur.craftNote == "") then
                cur.craftNote = data.craftNote
            end
            if data.guildNote and data.guildNote ~= "" and (not cur.guildNote or cur.guildNote == "") then
                cur.guildNote = data.guildNote
            end
            if data.secSummary and data.secSummary ~= "" then cur.secSummary = data.secSummary end
            if data.secProfIds then
                cur.secProfIds = cur.secProfIds or {}
                for k, v in pairs(data.secProfIds) do cur.secProfIds[k] = v end
            end
            if (not cur.updatedAt or (data.updatedAt or 0) > cur.updatedAt) and data.updatedAt then
                cur.updatedAt = data.updatedAt
            end
            return
        end
        data.lookupKey = key
        data.prof1 = p1
        data.prof2 = p2
        entries[key] = data
    end

    -- 1. Current Player (auto-detected + synced craftNote)
    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myDisplay = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local myParsed = Compat.ParseCharacterName(myDisplay)
    local myKey = (myParsed and myParsed.lookupKey) or myDisplay:lower()
    local myGuildRow = GetLiveGuildRow(myKey)
    local _, myClass = Safe.Call(UnitClass, "player")
    local secIds, secParts = {}, {}
    for sid, sInfo in pairs(self._myDetectedSecondaries or {}) do
        secIds[sid] = true
        local kLbl = PROF_ID_TO_KEY[sid]
        local lbl = (kLbl and L[kLbl]) or sInfo.name or sid
        secParts[#secParts + 1] = (sInfo.rank and sInfo.rank ~= "") and (lbl .. " " .. sInfo.rank) or lbl
    end
    table.sort(secParts)
    UpsertEntry(myKey, {
        displayName = (myParsed and myParsed.displayName) or myDisplay,
        prof1 = bucket.myProf1,
        prof2 = bucket.myProf2,
        prof1Rank = bucket.myProf1Rank or "",
        prof2Rank = bucket.myProf2Rank or "",
        craftNote = bucket.myCraftNote or "",
        guildNote = (myGuildRow and myGuildRow.note) or "",
        secProfIds = secIds,
        secSummary = table.concat(secParts, " · "),
        isSelf = true,
        isGuild = (IsInGuild and IsInGuild() == true) or (myGuildRow ~= nil),
        online = true,
        level = Safe.Number(Safe.Call(UnitLevel, "player")) or (myGuildRow and myGuildRow.level),
        classFile = Safe.String(myClass) or (myGuildRow and myGuildRow.classFile),
        rankName = myGuildRow and myGuildRow.rankName or nil,
        area = Compat.CurrentZoneName and Compat.CurrentZoneName() or (myGuildRow and myGuildRow.area),
        guid = Safe.String(Safe.Call(UnitGUID, "player")),
        sourceTag = "SELF",
        priority = 4,
        updatedAt = time(),
    })

    -- 2. Synced SocialCentral Guild Peers (SCentral1)
    for key, peer in pairs(bucket.peers or {}) do
        if type(peer) == "table" then
            local live = GetLiveGuildRow(key)
            local isOnline = (live and live.online == true) or ((time() - (peer.updatedAt or 0)) <= 900)
            UpsertEntry(key, {
                displayName = (live and live.displayName) or peer.displayName or key,
                prof1 = peer.prof1,
                prof2 = peer.prof2,
                prof1Rank = peer.prof1Rank or "",
                prof2Rank = peer.prof2Rank or "",
                craftNote = peer.craftNote or "",
                guildNote = (live and live.note) or "",
                isSelf = Compat.IsMe(peer.displayName or key, live and live.guid),
                isGuild = true,
                online = isOnline,
                level = live and live.level,
                classFile = (live and live.classFile) or peer.classFile,
                rankName = live and live.rankName,
                area = live and live.area,
                guid = live and live.guid,
                hasAddon = true,
                sourceTag = "SC",
                priority = 3,
                updatedAt = peer.updatedAt,
            })
        end
    end

    -- 3. Passive Guild Chat |Htrade: links & craft offers
    local nowTs = time()
    for key, chatRec in pairs(self.passiveChatProfs or {}) do
        if type(chatRec) == "table" and (nowTs - (chatRec.updatedAt or 0)) <= 21600 then
            local live = GetLiveGuildRow(key)
            UpsertEntry(key, {
                displayName = (live and live.displayName) or chatRec.displayName or key,
                prof1 = chatRec.prof1,
                prof2 = chatRec.prof2,
                prof1Rank = chatRec.prof1Rank or "",
                prof2Rank = chatRec.prof2Rank or "",
                craftNote = chatRec.craftNote or "",
                guildNote = (live and live.note) or "",
                isSelf = false,
                isGuild = true,
                online = (live == nil) and true or (live.online == true),
                level = live and live.level,
                classFile = live and live.classFile,
                rankName = live and live.rankName,
                area = live and live.area,
                guid = live and live.guid,
                sourceTag = "CHAT",
                priority = 2,
                updatedAt = chatRec.updatedAt,
            })
        else
            self.passiveChatProfs[key] = nil
        end
    end

    -- 4. Guild Roster Public Note Profession Scanner (zero addon required on guildmate!)
    for key, live in pairs(socialByLookup or {}) do
        if type(live) == "table" and live.sources and live.sources.guild == true and type(live.note) == "string" and live.note ~= "" then
            local np1, np2 = self:ParseProfessionsFromNote(live.note)
            if np1 ~= "NONE" or np2 ~= "NONE" then
                UpsertEntry(key, {
                    displayName = live.displayName or key,
                    prof1 = np1,
                    prof2 = np2,
                    craftNote = "",
                    guildNote = live.note,
                    isSelf = Compat.IsMe(live.displayName or key, live.guid),
                    isGuild = true,
                    online = (live.online == true),
                    level = live.level,
                    classFile = live.classFile,
                    rankName = live.rankName,
                    area = live.area,
                    guid = live.guid,
                    sourceTag = "NOTE",
                    priority = 1,
                    updatedAt = live.lastOnlineTs or (live.online and nowTs or nil),
                })
            end
        end
    end

    -- 5. Player's Own Alts on Current Realm Pool
    local curAltKey = (Store and Store.GetCurrentAltKey and Store:GetCurrentAltKey()) or ""
    local curCharKey = Compat.CharacterKey and Compat.CharacterKey() or ""
    if Store and Store.GetAltsList then
        for _, alt in ipairs(Store:GetAltsList()) do
            if type(alt) == "table" and alt.key ~= curAltKey and alt.key ~= curCharKey and alt.legacyKey ~= curCharKey and (not alt.faction or alt.faction == Compat.PlayerFaction()) and type(alt.professions) == "table" and #alt.professions > 0 then
                local altName = alt.fullName or alt.name or alt.key
                local altParsed = Compat.ParseCharacterName(altName)
                local altKey = (altParsed and altParsed.lookupKey) or ("alt:" .. tostring(alt.key))
                local ap1, ap2, ar1, ar2 = "NONE", "NONE", "", ""
                local aSecIds, aSecParts = {}, {}
                for _, ap in ipairs(alt.professions) do
                    if ap and ap.name then
                        local pid = self:MatchProfessionId(ap.name)
                        if pid ~= "NONE" then
                            local rStr = ((ap.maxRank or 0) > 0) and string.format("%d/%d", ap.rank or 0, ap.maxRank or 0) or ""
                            if ap.isPrimary ~= false and pid ~= "COOKING" and pid ~= "FIRST_AID" and pid ~= "FISHING" then
                                if ap1 == "NONE" then
                                    ap1, ar1 = pid, rStr
                                elseif ap2 == "NONE" and pid ~= ap1 then
                                    ap2, ar2 = pid, rStr
                                end
                            else
                                aSecIds[pid] = true
                                local kLbl = PROF_ID_TO_KEY[pid]
                                local lbl = (kLbl and L[kLbl]) or ap.name or pid
                                aSecParts[#aSecParts + 1] = (rStr ~= "") and (lbl .. " " .. rStr) or lbl
                            end
                        end
                    end
                end
                if ap1 == "NONE" and next(aSecIds) ~= nil then
                    if aSecIds.COOKING then
                        ap1 = "COOKING"
                    elseif aSecIds.FIRST_AID then
                        ap1 = "FIRST_AID"
                    else
                        local bestSid
                        for sid in pairs(aSecIds) do
                            if not bestSid or sid < bestSid then
                                bestSid = sid
                            end
                        end
                        ap1 = bestSid or "NONE"
                    end
                end
                if ap1 ~= "NONE" then
                    UpsertEntry(altKey, {
                        displayName = (altParsed and altParsed.displayName) or altName,
                        prof1 = ap1,
                        prof2 = ap2,
                        prof1Rank = ar1,
                        prof2Rank = ar2,
                        craftNote = "",
                        guildNote = (alt.guild and alt.guild ~= "") and ("<" .. alt.guild .. ">") or "",
                        secProfIds = aSecIds,
                        secSummary = table.concat(aSecParts, " · "),
                        isSelf = false,
                        isAlt = true,
                        isGuild = false,
                        online = false,
                        level = alt.level,
                        classFile = alt.classFile,
                        area = alt.zone,
                        altGuild = alt.guild,
                        sourceTag = "ALT",
                        priority = 1,
                        updatedAt = alt.lastActive,
                    })
                end
            end
        end
    end

    local function MatchesSource(e)
        if sf == "ONLINE" then
            return e.online == true and (e.isGuild or e.isSelf)
        elseif sf == "GUILD" then
            return e.isGuild == true or e.isSelf == true
        elseif sf == "ALTS" then
            return e.isAlt == true or e.isSelf == true
        elseif sf == "SYNC" then
            return e.sourceTag == "SC" or e.isSelf == true
        end
        return true
    end

    local profCounts = {}
    local out = {}
    for _, entry in pairs(entries) do
        if MatchesSource(entry) then
            local counted = {}
            for _, pid in ipairs({ entry.prof1, entry.prof2 }) do
                if pid and pid ~= "NONE" and not counted[pid] then
                    counted[pid] = true
                    profCounts[pid] = (profCounts[pid] or 0) + 1
                end
            end
            for sid in pairs(entry.secProfIds or {}) do
                if not counted[sid] then
                    counted[sid] = true
                    profCounts[sid] = (profCounts[sid] or 0) + 1
                end
            end

            local passProf = (not pf)
                or entry.prof1 == pf
                or entry.prof2 == pf
                or (entry.secProfIds and entry.secProfIds[pf] == true)
            if passProf then
                local passQuery = true
                if q then
                    local k1 = PROF_ID_TO_KEY[entry.prof1]
                    local k2 = PROF_ID_TO_KEY[entry.prof2]
                    local p1Label = (k1 and L[k1]) or entry.prof1 or ""
                    local p2Label = (k2 and L[k2]) or entry.prof2 or ""
                    local hay = FoldProfText(
                        (entry.displayName or "") .. " " ..
                        p1Label .. " " .. (entry.prof1 or "") .. " " ..
                        p2Label .. " " .. (entry.prof2 or "") .. " " ..
                        (entry.secSummary or "") .. " " ..
                        (entry.craftNote or "") .. " " ..
                        (entry.guildNote or "") .. " " ..
                        (entry.rankName or "") .. " " ..
                        (entry.area or "")
                    )
                    local matchesCraftHint = craftProfHint and (
                        entry.prof1 == craftProfHint
                        or entry.prof2 == craftProfHint
                        or (entry.secProfIds and entry.secProfIds[craftProfHint] == true)
                    )
                    if not matchesCraftHint and not hay:find(q, 1, true) then
                        passQuery = false
                    end
                end
                if passQuery then
                    table.insert(out, entry)
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf == true end
        local aOn = a.online == true
        local bOn = b.online == true
        if aOn ~= bOn then return aOn end
        if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
        return (a.displayName or "") < (b.displayName or "")
    end)
    return out, profCounts
end

function Clan:SetPreferredRightView(viewId)
    self.preferredRightView = viewId
end

function Clan:ConsumePreferredRightView()
    local v = self.preferredRightView
    self.preferredRightView = nil
    return v
end

local function MatchesAlertFilter(haystack)
    local rawFilter = ns.db and ns.db.settings and ns.db.settings.clanLfgAlertFilter
    if type(rawFilter) ~= "string" then return true end
    local trimmed = rawFilter:match("^%s*(.-)%s*$")
    if trimmed == "" then return true end
    local low = (haystack or ""):lower()
    for token in trimmed:gmatch("[^,;]+") do
        local kw = token:match("^%s*(.-)%s*$"):lower()
        if kw ~= "" and low:find(kw, 1, true) then
            return true
        end
    end
    return false
end

function Clan:MaybeNotifyClanLFG(lookupKey, displayName, classFile, summaryText, activityText, isDungeon, sourceType, peerLevelHint, sourceBadgeOverride)
    local s = ns.db and ns.db.settings
    if not (s and s.clanLfgAlertEnabled) then return false end
    if not lookupKey or not displayName or Compat.IsMe(displayName) then return false end

    local myLevel = Safe.Number(Safe.Call(UnitLevel, "player")) or 0
    local peerLevel = tonumber(peerLevelHint) or 0
    if peerLevel <= 0 and Store then
        local rRec = Store.guildRosterRanks and Store.guildRosterRanks[lookupKey]
        local sRec = Store.socialByLookup and Store.socialByLookup[lookupKey]
        peerLevel = (rRec and tonumber(rRec.level)) or (sRec and tonumber(sRec.level)) or 0
    end
    local isNearLevel = (myLevel > 0 and peerLevel > 0) and ((myLevel >= 60 and peerLevel >= 60) or math.abs(peerLevel - myLevel) <= 5)
    if s.clanLfgAlertNearLevel ~= false and myLevel > 0 and peerLevel > 0 and not isNearLevel then
        return false
    end

    if s.clanLfgAlertDungeonsOnly ~= false and not isDungeon and not (isNearLevel and (sourceType == "LFG" or sourceType == "OFFICIAL_LFG" or sourceType == "TAG" or sourceType == "ALLY_LFG")) then
        return false
    end

    local combined = ((activityText or "") .. " " .. (summaryText or ""))
    if not MatchesAlertFilter(combined) then
        return false
    end

    local now = time()
    self.lfgAlertCooldowns = self.lfgAlertCooldowns or {}
    if not self._lastAlertCooldownPruneAt or (now - self._lastAlertCooldownPruneAt) >= 60 then
        self._lastAlertCooldownPruneAt = now
        for k, ts in pairs(self.lfgAlertCooldowns) do
            if (now - (ts or 0)) >= 180 then
                self.lfgAlertCooldowns[k] = nil
            end
        end
    end
    local prevAt = self.lfgAlertCooldowns[lookupKey] or 0
    if (now - prevAt) < 180 then
        return false
    end
    self.lfgAlertCooldowns[lookupKey] = now

    local badgeLabel = (type(sourceBadgeOverride) == "string" and sourceBadgeOverride ~= "") and sourceBadgeOverride or L["Clan LFG"]
    local hex = Compat.ClassHex(classFile)
    local nameCol = hex .. displayName .. "|r"
    local cleanMsg = Compat.CleanPayloadField(summaryText ~= "" and summaryText or activityText or "LFG", 90)
    local wLink = "|Haddon:SCentral:w:" .. displayName .. "|h|cff58a6ff[" .. L["Chat"] .. "]|r|h"
    local cLink = "|Haddon:SCentral:clanlfg:" .. tostring(lookupKey or "") .. "|h|cfff2c94c[" .. badgeLabel .. "]|r|h"
    ns:Print(("|cff3fb950[%s]|r %s: %s %s %s"):format(L["Dungeon LFG Alert"], nameCol, cleanMsg, wLink, cLink))

    if s.clanLfgAlertSound ~= false then
        PlayClanAlertSound(self, SOUNDKIT and (SOUNDKIT.MAP_PING or 3175))
    end

    self:IncrementNotificationCount(1)
    ns:Emit("CLAN_LFG_ALERT", {
        lookupKey = lookupKey,
        displayName = displayName,
        classFile = classFile,
        summary = cleanMsg,
        activity = activityText or "",
        isDungeon = isDungeon,
        sourceType = sourceType or "LFG",
        ts = now,
    })
    ns:Emit("ADDON_MESSAGE_NOTIFY", {
        id = "clanlfg:" .. lookupKey .. ":" .. tostring(now),
        kind = "CLAN_LFG",
        sourceTag = badgeLabel,
        lookupKey = lookupKey,
        sender = displayName,
        senderClass = classFile,
        activity = activityText or "",
        text = cleanMsg,
        ts = now,
        priority = 1,
    })
    return true
end

function Clan:GetPlayerGameSummary()
    local role, specName = self:GetMySpecAndRole()
    local level = Safe.Number(Safe.Call(UnitLevel, "player")) or 0
    local avgIlvl = 0
    if GetAverageItemLevel then
        local overall, equipped = Safe.Call(GetAverageItemLevel)
        avgIlvl = math.floor((Safe.Number(equipped) or Safe.Number(overall) or 0) + 0.5)
    end

    local mplusScore = 0
    local keyLvl, keyMapId, keyName = 0, nil, nil

    local lfgQueued, lfgCategory = false, nil
    if GetLFGMode then
        for _, cat in ipairs({ LE_LFG_CATEGORY_LFD or 1, LE_LFG_CATEGORY_RF or 3, LE_LFG_CATEGORY_SCENARIO or 4 }) do
            local mode = Safe.String(Safe.Call(GetLFGMode, cat))
            if mode and mode ~= "" and mode ~= "abandonedInDungeon" then
                lfgQueued = true
                lfgCategory = mode
                break
            end
        end
    end

    local premadeTitle, premadeApplicants = nil, 0
    if C_LFGList and C_LFGList.HasActiveEntryInfo and Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true then
        local info = C_LFGList.GetActiveEntryInfo and Safe.Call(C_LFGList.GetActiveEntryInfo)
        if type(info) == "table" then
            premadeTitle = Safe.String(info.name)
        end
        if C_LFGList.GetApplicants then
            local apps = Safe.Call(C_LFGList.GetApplicants)
            if type(apps) == "table" then
                premadeApplicants = #apps
            end
        end
    end

    local inInst, instType = Safe.Call(IsInInstance)
    local instName = inInst == true and Safe.String(Safe.Call(GetInstanceInfo)) or nil

    return {
        level = level,
        specName = specName or "",
        role = role,
        avgItemLevel = avgIlvl,
        mplusScore = mplusScore,
        keystoneLevel = keyLvl,
        keystoneMapId = keyMapId,
        keystoneName = keyName,
        lfgQueued = lfgQueued,
        lfgCategory = lfgCategory,
        premadeTitle = premadeTitle,
        premadeApplicants = premadeApplicants,
        inInstance = inInst == true,
        instanceType = Safe.String(instType),
        instanceName = instName,
        zoneName = Compat.CurrentZoneName(),
        canEditMOTD = (C_GuildInfo and C_GuildInfo.CanEditMOTD and Safe.Value(Safe.Call(C_GuildInfo.CanEditMOTD)) == true)
            or (CanEditMOTD and Safe.Value(Safe.Call(CanEditMOTD)) == true) or false,
        canEditCalendar = (CanEditGuildEvent and Safe.Value(Safe.Call(CanEditGuildEvent)) == true) or false,
        canInviteGuild = self:CanInviteToGuild(),
    }
end

function Clan:FormatResetDuration(secs)
    local s = math.max(0, math.floor(tonumber(secs) or 0))
    if s <= 0 then
        return "0m"
    end
    local days = math.floor(s / 86400)
    local hours = math.floor((s % 86400) / 3600)
    local mins = math.floor((s % 3600) / 60)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", math.max(1, mins))
end

function Clan:RequestLockoutsRefresh(force)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end
    if not RequestRaidInfo then
        return false
    end
    local monoNow = GetTime and GetTime() or 0
    if not force and (monoNow - (self.lastLockoutRefreshAt or 0)) < 15 then
        return false
    end
    self.lastLockoutRefreshAt = monoNow
    pcall(RequestRaidInfo)
    return true
end

function Clan:GetSavedLockouts(skipSort)
    local out = {}
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return out end
    local count = Safe.Number(Safe.Call(GetNumSavedInstances)) or 0
    for i = 1, count do
        local ok, name, id, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = pcall(GetSavedInstanceInfo, i)
        if ok then
            name = Safe.String(name)
            if name and (Safe.Value(locked) == true or Safe.Value(extended) == true or (Safe.Number(reset) or 0) > 0) then
                table.insert(out, {
                    index = i,
                    name = name,
                    id = Safe.Number(id) or 0,
                    reset = Safe.Number(reset) or 0,
                    locked = Safe.Value(locked) == true,
                    extended = Safe.Value(extended) == true,
                    isRaid = Safe.Value(isRaid) == true,
                    difficultyName = Safe.String(difficultyName) or "",
                    numEncounters = Safe.Number(numEncounters) or 0,
                    encounterProgress = Safe.Number(encounterProgress) or 0,
                })
            end
        end
    end
    if not skipSort then
        table.sort(out, function(a, b)
            return (a.reset or 0) < (b.reset or 0)
        end)
    end
    return out
end

function Clan:GetAllLockouts()
    local out = {}
    local now = time()
    local myResolved = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (myResolved and myResolved.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local _, myClass = Safe.Call(UnitClass, "player")
    myClass = Safe.String(myClass)

    for _, lk in ipairs(self:GetSavedLockouts(true)) do
        lk.charName = myName
        lk.classFile = myClass
        lk.isSelf = true
        lk.isAlt = false
        table.insert(out, lk)
    end

    local curAltKey = (Store and Store.GetCurrentAltKey and Store:GetCurrentAltKey()) or ""
    local curCharKey = Compat.CharacterKey and Compat.CharacterKey() or ""
    if Store and Store.GetAltsList then
        for _, alt in ipairs(Store:GetAltsList()) do
            if type(alt) == "table" and alt.key ~= curAltKey and alt.key ~= curCharKey and alt.legacyKey ~= curCharKey and (not alt.faction or alt.faction == Compat.PlayerFaction()) and type(alt.lockouts) == "table" then
                for _, lk in ipairs(alt.lockouts) do
                    if type(lk) == "table" and (lk.expiresAt or 0) > now then
                        local rem = math.max(0, (lk.expiresAt or 0) - now)
                        table.insert(out, {
                            name = lk.name or "?",
                            id = lk.id or 0,
                            reset = rem,
                            locked = lk.locked == true,
                            extended = lk.extended == true,
                            isRaid = lk.isRaid == true,
                            difficultyName = lk.difficultyName or "",
                            numEncounters = lk.numEncounters or 0,
                            encounterProgress = lk.encounterProgress or 0,
                            charName = alt.fullName or alt.name or alt.key or "Alt",
                            classFile = alt.classFile,
                            isSelf = false,
                            isAlt = true,
                        })
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        if a.charName ~= b.charName then return (a.charName or "") < (b.charName or "") end
        return (a.reset or 0) < (b.reset or 0)
    end)
    return out
end

function Clan:RefreshGameCalendar(force)
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("clan") then return false end
    if not C_Calendar then return false end
    local monoNow = GetTime and GetTime() or time()
    if C_Calendar.OpenCalendar and (force or (monoNow - (self.lastCalendarRefreshAt or 0)) >= 30) then
        if not ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
            self.lastCalendarRefreshAt = monoNow
            pcall(C_Calendar.OpenCalendar)
        end
    end

    local today = (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and Safe.Call(C_DateAndTime.GetCurrentCalendarTime)) or date("*t")
    local baseDay = tonumber(today and (today.monthDay or today.day)) or 1
    local baseMonth = tonumber(today and today.month) or 1
    local baseYear = tonumber(today and today.year) or 2026

    local monthInfo = C_Calendar.GetMonthInfo and Safe.Call(C_Calendar.GetMonthInfo, 0)
    local calMonth = Safe.Number(monthInfo and monthInfo.month)
    local calYear = Safe.Number(monthInfo and monthInfo.year)
    if (not calMonth or calMonth ~= baseMonth or calYear ~= baseYear) and C_Calendar.SetAbsMonth then
        pcall(C_Calendar.SetAbsMonth, baseMonth, baseYear)
        monthInfo = C_Calendar.GetMonthInfo and Safe.Call(C_Calendar.GetMonthInfo, 0)
    end
    local numDaysInMonth = Safe.Number(monthInfo and monthInfo.numDays) or 31

    local found = {}
    if C_Calendar.GetNumDayEvents and C_Calendar.GetDayEvent then
        for delta = 0, 14 do
            local mOffset = 0
            local dayNum = baseDay + delta
            if dayNum > numDaysInMonth then
                mOffset = 1
                dayNum = dayNum - numDaysInMonth
            end
            local nEvents = Safe.Number(Safe.Call(C_Calendar.GetNumDayEvents, mOffset, dayNum)) or 0
            for idx = 1, nEvents do
                local ev = Safe.Call(C_Calendar.GetDayEvent, mOffset, dayNum, idx)
                if type(ev) == "table" then
                    local calType = Safe.String(ev.calendarType) or ""
                    local title = Safe.String(ev.title) or ""
                    local isRelevant = calType == "GUILD_EVENT" or calType == "GUILD_ANNOUNCEMENT" or calType == "PLAYER" or calType == "RAID_LOCKOUT"
                    if isRelevant and title ~= "" then
                        table.insert(found, {
                            title = title,
                            calendarType = calType,
                            monthOffset = mOffset,
                            monthDay = dayNum,
                            dayDelta = delta,
                            hour = Safe.Number(ev.startTime and ev.startTime.hour) or 0,
                            minute = Safe.Number(ev.startTime and ev.startTime.minute) or 0,
                            inviteStatus = Safe.Number(ev.inviteStatus),
                            invitedBy = Safe.String(ev.invitedBy) or "",
                            isGuild = (calType == "GUILD_EVENT" or calType == "GUILD_ANNOUNCEMENT"),
                            eventID = ev.eventID,
                        })
                    end
                end
            end
        end
    end
    self.calendarEvents = found
    return true
end

function Clan:GetUpcomingCalendarEvents()
    return self.calendarEvents or {}
end

local function IsGroupRecommendedQuestTag(tagId, tagName)
    local qt = Enum and Enum.QuestTag
    if tagId and qt then
        if tagId == qt.Group or tagId == qt.Dungeon or tagId == qt.Raid or tagId == qt.Heroic then
            local isDng = (qt.Dungeon ~= nil and tagId == qt.Dungeon) or (qt.Heroic ~= nil and tagId == qt.Heroic)
            return true, isDng
        end
    end
    if tagId == 1 or tagId == 81 or tagId == 62 or tagId == 85 then
        return true, (tagId == 81 or tagId == 85)
    end
    if type(tagName) == "string" and tagName ~= "" then
        local low = tagName:lower()
        if low:find("group", 1, true) or low:find("grupo", 1, true)
            or low:find("dungeon", 1, true) or low:find("masmorr", 1, true) or low:find("mazmorr", 1, true)
            or low:find("raid", 1, true) or low:find("raide", 1, true)
            or low:find("elite", 1, true) or low:find("heroic", 1, true) or low:find("heróic", 1, true) then
            local isDng = (low:find("dungeon", 1, true) ~= nil) or (low:find("masmorr", 1, true) ~= nil) or (low:find("mazmorr", 1, true) ~= nil)
            return true, isDng
        end
    end
    return false, false
end

function Clan:GetActiveGroupQuests()
    local out = {}
    local seen = {}
    local currentZone = ""

    local function PushQuest(qId, title, lvl, sugGroup, tagName, isComplete, isDungeonTag)
        local cleanTitle = Compat.CleanInput and Compat.CleanInput(title or "") or title
        if not cleanTitle or cleanTitle == "" then return end
        local key = (qId and qId > 0) and tostring(qId) or cleanTitle:lower()
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = {
            questID = qId or 0,
            title = cleanTitle,
            level = lvl or 0,
            suggestedGroup = sugGroup or 0,
            tagName = tagName or "",
            zone = currentZone or "",
            isComplete = isComplete == true,
            isDungeon = isDungeonTag == true,
        }
    end

    if _G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries and _G.C_QuestLog.GetInfo then
        local n = Safe.Number(Safe.Call(_G.C_QuestLog.GetNumQuestLogEntries)) or 0
        for i = 1, math.min(n, 80) do
            local info = Safe.Call(_G.C_QuestLog.GetInfo, i)
            if type(info) == "table" then
                local title = Safe.String(info.title)
                local isHdr = Safe.Boolean(info.isHeader) == true
                local isHidden = Safe.Boolean(info.isHidden) == true
                if isHdr then
                    currentZone = (title and title ~= "") and title or currentZone
                elseif not isHidden and title and title ~= "" then
                    local qId = Safe.Number(info.questID) or 0
                    local lvl = Safe.Number(info.level) or 0
                    local sugGroup = Safe.Number(info.suggestedGroup) or 0
                    local isComp = Safe.Boolean(info.isComplete) == true
                    local tagId, tagName = nil, nil
                    if qId > 0 and _G.C_QuestLog.GetQuestTagInfo then
                        local tInfo = Safe.Call(_G.C_QuestLog.GetQuestTagInfo, qId)
                        if type(tInfo) == "table" then
                            tagId = Safe.Number(tInfo.tagID)
                            tagName = Safe.String(tInfo.tagName)
                        end
                    end
                    if (tagId == nil) and qId > 0 and _G.GetQuestTagInfo then
                        local rId, rName = Safe.Call(_G.GetQuestTagInfo, qId)
                        tagId = Safe.Number(rId)
                        tagName = Safe.String(rName)
                    end
                    local tagGroup, isDngTag = IsGroupRecommendedQuestTag(tagId, tagName)
                    if sugGroup >= 2 or tagGroup then
                        PushQuest(qId, title, lvl, sugGroup, tagName, isComp, isDngTag)
                    end
                end
            end
        end
    elseif _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
        local n = Safe.Number(Safe.Call(_G.GetNumQuestLogEntries)) or 0
        for i = 1, math.min(n, 80) do
            local ok, rTitle, rLvl, rSug, rHdr, _, rComp, _, rQid = pcall(_G.GetQuestLogTitle, i)
            if ok then
                local title = Safe.String(rTitle)
                local isHdr = Safe.Boolean(rHdr) == true
                if isHdr then
                    currentZone = (title and title ~= "") and title or currentZone
                elseif title and title ~= "" then
                    local qId = Safe.Number(rQid) or 0
                    local lvl = Safe.Number(rLvl) or 0
                    local sugGroup = Safe.Number(rSug) or 0
                    local isComp = (Safe.Number(rComp) == 1) or (Safe.Boolean(rComp) == true)
                    local tagId, tagName = nil, nil
                    if qId > 0 and _G.GetQuestTagInfo then
                        local rId, rName = Safe.Call(_G.GetQuestTagInfo, qId)
                        tagId = Safe.Number(rId)
                        tagName = Safe.String(rName)
                    end
                    local tagGroup, isDngTag = IsGroupRecommendedQuestTag(tagId, tagName)
                    if sugGroup >= 2 or tagGroup then
                        PushQuest(qId, title, lvl, sugGroup, tagName, isComp, isDngTag)
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.isComplete ~= b.isComplete then return not a.isComplete end
        if (a.suggestedGroup or 0) ~= (b.suggestedGroup or 0) then
            return (a.suggestedGroup or 0) > (b.suggestedGroup or 0)
        end
        if (a.level or 0) ~= (b.level or 0) then
            return (a.level or 0) < (b.level or 0)
        end
        return (a.title or "") < (b.title or "")
    end)
    return out
end

function Clan:GetMotdEventSuggestion()
    local info = Store and Store.guildInfo
    if not (info and info.inGuild and type(info.motd) == "string" and info.motd ~= "") then
        return nil
    end
    local cleanMotd = Compat.CleanInput and Compat.CleanInput(info.motd) or info.motd
    if not cleanMotd or cleanMotd == "" then return nil end
    local low = cleanMotd:lower()
    local looksLikeEvent = low:find("evento", 1, true)
        or low:find("event", 1, true)
        or low:find("raide", 1, true)
        or low:find("%f[%w]raid%f[%W]") ~= nil
        or low:find("%d%d?/%d%d?") ~= nil
        or low:find("%d%d?:%d%d") ~= nil
    if not looksLikeEvent then
        return nil
    end
    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local events = bucket and bucket.events
    if type(events) == "table" then
        for _, evt in pairs(events) do
            if type(evt) == "table" and evt.isOpen ~= false and type(evt.title) == "string" and #evt.title >= 5 then
                if low:find(evt.title:lower(), 1, true) then
                    return nil
                end
            end
        end
    end
    local dateHit = cleanMotd:match("(%d%d?/%d%d?%s*%d?%d?:?%d?%d?)") or cleanMotd:match("(%d%d?:%d%d)")
    local titleSeg = cleanMotd:match("[Ee][Vv][Ee][Nn][Tt][Oo]?:?%s*(.+)") or cleanMotd
    titleSeg = Compat.CleanPayloadField(titleSeg, 38)
    if titleSeg == "" then
        titleSeg = Compat.CleanPayloadField(cleanMotd, 38)
    end
    return {
        _isMotdSuggestion = true,
        title = titleSeg,
        whenText = dateHit and Compat.CleanPayloadField(dateHit, 20) or L["Today"],
        motd = cleanMotd,
        category = (low:find("raid", 1, true) or low:find("raide", 1, true)) and "RAID" or "GUILD",
    }
end

function Clan:GetCombinedEventsList(filterId)
    local evts = self:GetEventsList(filterId)
    if filterId == "calendar" then
        self:RefreshGameCalendar(false)
        local cals = self:GetUpcomingCalendarEvents() or {}
        local calOut = {}
        for i = 1, #cals do
            local c = {}
            for k, v in pairs(cals[i]) do c[k] = v end
            c._isCalendarEvent = true
            calOut[#calOut + 1] = c
        end
        return calOut
    end
    if filterId == "all" then
        self:RefreshGameCalendar(false)
        local cals = self:GetUpcomingCalendarEvents() or {}
        local seenTitles = {}
        for i = 1, #evts do
            if type(evts[i].title) == "string" then
                seenTitles[evts[i].title:lower()] = true
            end
        end
        for i = 1, #cals do
            local rawC = cals[i]
            local tLow = type(rawC.title) == "string" and rawC.title:lower() or ""
            if tLow ~= "" and not seenTitles[tLow] then
                seenTitles[tLow] = true
                local c = {}
                for k, v in pairs(rawC) do c[k] = v end
                c._isCalendarEvent = true
                evts[#evts + 1] = c
            end
        end
    end
    if filterId == "all" or filterId == "open" then
        local motdSug = self:GetMotdEventSuggestion()
        if motdSug then
            table.insert(evts, 1, motdSug)
        end
    end
    return evts
end

function Clan:ShareEventToGuildChat(evt)
    if type(evt) ~= "table" then return false end
    local sum = self:GetSignupSummary(evt)
    local needT = tonumber(evt.needT) or 0
    local needH = tonumber(evt.needH) or 0
    local needD = tonumber(evt.needD) or 0
    local slotsPart = (needT + needH + needD > 0)
        and (" - T:%d/%d H:%d/%d D:%d/%d"):format(sum.TANK or 0, needT, sum.HEALER or 0, needH, sum.DPS or 0, needD)
        or (" - T:%d H:%d D:%d"):format(sum.TANK or 0, sum.HEALER or 0, sum.DPS or 0)
    local draft = ("/g [Evento] %s (%s)%s"):format(
        Compat.CleanPayloadField(evt.title or "", 40),
        Compat.CleanPayloadField(evt.whenText or L["Now"], 24),
        slotsPart
    )
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, draft)
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, draft)
        return true
    end
    return false
end

function Clan:SetGuildMOTD(rawText)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print(L["In Combat"])
        return false
    end
    if not (CanEditMOTD and Safe.Value(Safe.Call(CanEditMOTD)) == true) then
        ns:Print(L["Only guild officers with MOTD permission can edit this."])
        return false
    end
    local clean = Compat.CleanInput(rawText) or ""
    if C_GuildInfo and C_GuildInfo.SetMOTD then
        pcall(C_GuildInfo.SetMOTD, clean)
    elseif GuildSetMOTD then
        pcall(GuildSetMOTD, clean)
    else
        return false
    end
    if Store and Store.guildInfo then
        Store.guildInfo.motd = clean
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:PublishGameCalendarEvent(category, title, note, dayOffset, hour, minute)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false, L["In Combat"]
    end
    if not C_Calendar then
        return false, L["WoW Calendar API is unavailable right now."]
    end
    local canGuild = CanEditGuildEvent and Safe.Value(Safe.Call(CanEditGuildEvent)) == true
    if not canGuild then
        return false, L["Your guild rank cannot create WoW Guild Calendar events; posted to SocialCentral Clan Events instead."]
    end

    local okOpen = pcall(C_Calendar.OpenCalendar)
    if not okOpen then
        return false, L["WoW Calendar API is unavailable right now."]
    end

    local today = (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and Safe.Call(C_DateAndTime.GetCurrentCalendarTime)) or date("*t")
    local baseDay = tonumber(today and (today.monthDay or today.day)) or 1
    local baseMonth = tonumber(today and today.month) or 1
    local baseYear = tonumber(today and today.year) or 2026

    local monthInfo = C_Calendar.GetMonthInfo and Safe.Call(C_Calendar.GetMonthInfo, 0)
    local daysInCur = Safe.Number(monthInfo and monthInfo.numDays) or 31
    local targetDay = baseDay + (tonumber(dayOffset) or 0)
    local targetMonth = baseMonth
    local targetYear = baseYear
    if targetDay > daysInCur then
        targetDay = targetDay - daysInCur
        targetMonth = targetMonth + 1
        if targetMonth > 12 then
            targetMonth = 1
            targetYear = targetYear + 1
        end
    end

    pcall(C_Calendar.CloseEvent)
    local created = false
    if C_Calendar.CreateGuildSignUpEvent then
        created = pcall(C_Calendar.CreateGuildSignUpEvent)
    elseif C_Calendar.CreateGuildAnnouncementEvent then
        created = pcall(C_Calendar.CreateGuildAnnouncementEvent)
    end
    if not created then
        return false, L["Could not initialize WoW Guild Calendar event."]
    end

    if C_Calendar.EventSetTitle then
        pcall(C_Calendar.EventSetTitle, Compat.CleanPayloadField(title or "", 40))
    end
    if C_Calendar.EventSetDescription then
        pcall(C_Calendar.EventSetDescription, Compat.CleanPayloadField(note or ("SocialCentral: " .. (category or "EVENT")), 180))
    end
    if C_Calendar.EventSetDate then
        pcall(C_Calendar.EventSetDate, targetMonth, targetDay, targetYear)
    end
    if C_Calendar.EventSetTime then
        pcall(C_Calendar.EventSetTime, tonumber(hour) or 20, tonumber(minute) or 0)
    end
    if C_Calendar.EventSetType and Enum and Enum.CalendarEventType then
        local evType = Enum.CalendarEventType.Other
        if category == "RAID" then evType = Enum.CalendarEventType.Raid
        elseif category == "DUNGEON" then evType = Enum.CalendarEventType.Dungeon
        elseif category == "PVP" then evType = Enum.CalendarEventType.PvP
        end
        pcall(C_Calendar.EventSetType, evType)
    end

    local added = C_Calendar.AddEvent and pcall(C_Calendar.AddEvent)
    if added then
        self:RefreshGameCalendar(true)
        ns:Emit("CLAN_UPDATED")
        return true
    end
    return false, L["Could not commit event to WoW Calendar; created in SocialCentral Clan Events instead."]
end

function Clan:GetDungeonQuickPresets()
    local list = {}
    local sum = self:GetPlayerGameSummary()
    local myLvl = (sum and sum.level) or (Safe.Number(UnitLevel and UnitLevel("player"))) or 60
    if myLvl <= 0 then myLvl = 60 end

    if sum.premadeTitle and sum.premadeTitle ~= "" then
        table.insert(list, {
            id = "ACTIVE_PREMADE",
            label = "[Premade] " .. sum.premadeTitle,
            activity = sum.premadeTitle,
            keyLvl = 0,
            category = "DUNGEON",
            mode = "LFM",
        })
    end

    local gQuests = self:GetActiveGroupQuests()
    for i = 1, math.min(2, #gQuests) do
        local q = gQuests[i]
        table.insert(list, {
            id = "QUEST_" .. tostring(q.questID or i),
            label = q.title,
            activity = q.title,
            keyLvl = 0,
            category = q.isDungeon and "DUNGEON" or "QUEST",
            mode = "LFM",
            suggestedGroup = q.suggestedGroup,
        })
    end

    if myLvl < 18 then
        table.insert(list, { id = "LOW_RFC", label = L["Ragefire Chasm"], activity = L["Ragefire Chasm"], keyLvl = 0, category = "DUNGEON", mode = "LFG" })
        table.insert(list, { id = "LOW_THN", label = L["Hall of Thanes"], activity = L["Hall of Thanes"], keyLvl = 0, category = "DUNGEON", mode = "LFG" })
        table.insert(list, { id = "LOW_WC", label = L["Wailing Caverns"], activity = L["Wailing Caverns"], keyLvl = 0, category = "DUNGEON", mode = "LFG" })
    end

    for _, item in ipairs(self.DUNGEON_PRESETS) do
        local skipItem = (myLvl < 52 and item.id == "ENDGAME_DNG") or (myLvl >= 52 and item.id == "RANDOM_NORM")
        if not skipItem then
            table.insert(list, {
                id = item.id,
                label = L[item.labelKey],
                activity = L[item.labelKey],
                keyLvl = 0,
                category = item.category or "DUNGEON",
                mode = "LFG",
            })
        end
    end
    return list
end

function Clan:PostLFG(mode, role, activity, keyLvl, note, clanOnly, forceIsDungeon)
    if (not self._syncingFromOfficial) and Compat.IsInGroup and Compat.IsInGroup() and Compat.CanManageGroupListing and not Compat.CanManageGroupListing() then
        return false, "not_leader"
    end
    local cleanMode = (mode == "LFM") and "LFM" or "LFG"
    local cleanRole = (role == "TANK" or role == "HEALER" or role == "DPS" or role == "DAMAGER" or role == "ANY") and role or self:GetMySpecAndRole()
    if cleanRole == "DAMAGER" then cleanRole = "DPS" end
    local cleanAct = Compat.CleanPayloadField(activity or "", 40)
    if cleanAct == "" then
        cleanAct = L["Random / Any Dungeon"]
    end
    local cleanKey = 0
    local cleanNote = Compat.CleanPayloadField(note or "", 44)
    local sum = self:GetPlayerGameSummary()
    local iLvl = sum.avgItemLevel or 0

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player")) or "Player"
    local myParsed = Compat.ParseCharacterName(myName)
    local _, myClass = Safe.Call(UnitClass, "player")
    if not myParsed then return false end

    local bucket = Store:GetClanScopeData()
    bucket.lfg = bucket.lfg or {}
    bucket.lfg[myParsed.lookupKey] = {
        lookupKey = myParsed.lookupKey,
        displayName = myParsed.displayName,
        classFile = Safe.String(myClass),
        mode = cleanMode,
        role = cleanRole,
        activity = cleanAct,
        keyLvl = cleanKey,
        ilvl = iLvl,
        note = cleanNote,
        isDungeon = (forceIsDungeon == true) or IsDungeonLFGText(cleanAct .. " " .. cleanNote, nil),
        updatedAt = time(),
    }
    bucket.myTag = "LFG"
    bucket.myNote = Compat.CleanPayloadField(cleanAct, 36)

    local payload = ("LFG~%s~%s~%s~%s~%d~%d~%s"):format(ns.version or "0.0.0", cleanMode, cleanRole, cleanAct, cleanKey, iLvl, cleanNote)
    local sent = self:SendGuildSync(payload)
    if sent then
        self._heardGuildLfgKey = self._heardGuildLfgKey or {}
        self._heardGuildLfgKey[myParsed.lookupKey] = GetTime and GetTime() or time()
    end

    if not clanOnly then
        local myGuildName = Compat.CleanPayloadField((Store.guildInfo and Store.guildInfo.name) or Safe.String(Safe.Call(GetGuildInfo, "player")) or "", 24)
        local extPayload = ("ALFG~%s~%s~%s~%s~%s~%s~%d~%d~%s"):format(
            ns.version or "0.0.0",
            Compat.CleanPayloadField(myParsed.displayName, 26),
            myGuildName,
            cleanMode,
            cleanRole,
            cleanAct:sub(1, 30),
            cleanKey,
            iLvl,
            cleanNote:sub(1, 30)
        )
        BroadcastExternalLFG(self, extPayload)
    end

    if (ns.db and ns.db.settings and ns.db.settings.clanSync) and not sent and IsInGuild and IsInGuild() then
        local waitRem = math.ceil(math.max(0, self.MIN_SEND_INTERVAL - (GetTime() - (self.lastSyncSentAt or 0))))
        if waitRem > 0 then
            ns:Print(L["Clan LFG saved locally; guild broadcast ready in %ds."]:format(waitRem))
        end
    end
    ns:Emit("CLAN_UPDATED")
    return true, bucket.lfg[myParsed.lookupKey]
end

function Clan:PostSmartGroupFormation(optionalActivity)
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        ns:Print("%s", L["Unavailable during combat."])
        return false
    end
    if Compat.IsInGroup and Compat.IsInGroup() and Compat.CanManageGroupListing and not Compat.CanManageGroupListing() then
        local leaderName = Compat.GetGroupLeaderName and Compat.GetGroupLeaderName()
        if leaderName and leaderName ~= "" then
            ns:Print("%s", L["Only the party leader (%s) can list or broadcast this group."]:format(leaderName))
        else
            ns:Print("%s", L["Only the party leader can list or broadcast this group."])
        end
        return false, "not_leader"
    end
    local inGroup = Compat.IsInGroup and Compat.IsInGroup()
    local inRaid = Compat.IsInRaid and Compat.IsInRaid()
    local counts = (ns.Group and ns.Group.GetSummaryCounts and ns.Group:GetSummaryCounts()) or { total = 0, TANK = 0, HEALER = 0, DAMAGER = 0 }
    local sum = self:GetPlayerGameSummary()
    local primaryRole = self:GetMySpecAndRole()

    local noteStr = ""
    if inGroup and not inRaid and (counts.total or 0) >= 1 and (counts.total or 0) < 5 then
        local needT = math.max(0, 1 - (counts.TANK or 0))
        local needH = math.max(0, 1 - (counts.HEALER or 0))
        local needD = math.max(0, 3 - (counts.DAMAGER or 0))
        local needParts = {}
        if needT > 0 then needParts[#needParts + 1] = needT .. "T" end
        if needH > 0 then needParts[#needParts + 1] = needH .. "H" end
        if needD > 0 then needParts[#needParts + 1] = needD .. "D" end
        local needPartsStr = (#needParts > 0) and table.concat(needParts, " ") or L["Any"]
        noteStr = L["[%d/5 · Need: %s]"]:format(counts.total, needPartsStr)
    end

    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player"))
    local myKey = myName and Compat.ParseCharacterFields and select(1, Compat.ParseCharacterFields(myName)) or nil
    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local prevLfg = bucket and bucket.lfg and myKey and bucket.lfg[myKey]

    local activity = type(optionalActivity) == "string" and optionalActivity:match("^%s*(.-)%s*$") or nil
    if (not activity or activity == "") and C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.GetActiveEntryInfo then
        if Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true then
            local aEntry = Safe.Call(C_LFGList.GetActiveEntryInfo)
            if type(aEntry) == "table" then
                activity = Safe.String(aEntry.name)
                if (not activity or activity == "") and aEntry.activityID and C_LFGList.GetActivityInfoTable then
                    local aTbl = Safe.Call(C_LFGList.GetActivityInfoTable, aEntry.activityID)
                    if type(aTbl) == "table" then
                        activity = Safe.String(aTbl.fullName) or Safe.String(aTbl.shortName)
                    end
                end
            end
        end
    end
    if not activity or activity == "" then
        activity = (prevLfg and prevLfg.activity and prevLfg.activity ~= "" and prevLfg.activity)
            or (sum.premadeTitle and sum.premadeTitle ~= "" and sum.premadeTitle)
            or (sum.instanceName and sum.instanceName ~= "" and sum.instanceName)
    end
    if not activity or activity == "" then
        return false, "needs_activity"
    end

    local ok, row = self:PostLFG(inGroup and "LFM" or "LFG", primaryRole, activity, 0, noteStr, false)
    if ok then
        ns:Print("%s", L["Group formation broadcasted to Guild, Allied Clans, Friends & [SC] users."])
    end
    return ok, row
end

function Clan:GetActiveLfgForPlayer(rawNameOrKey)
    if type(rawNameOrKey) ~= "string" or rawNameOrKey == "" then return nil end
    local key = (Compat.ParseCharacterFields and select(1, Compat.ParseCharacterFields(rawNameOrKey))) or rawNameOrKey:lower()
    if not key or key == "" then return nil end
    local now = time()
    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()

    local rec = bucket and bucket.lfg and bucket.lfg[key]
    if type(rec) == "table" and (now - (rec.updatedAt or 0)) <= 1800 then
        return {
            mode = rec.mode or "LFG",
            role = rec.role or "ANY",
            activity = rec.activity or L["Dungeon"],
            note = rec.note or "",
            sourceType = "LFG",
        }
    end
    local ext = self.externalLFG and self.externalLFG[key]
    if type(ext) == "table" and (now - (ext.updatedAt or 0)) <= 1800 then
        return {
            mode = ext.mode or "LFG",
            role = ext.role or "ANY",
            activity = ext.activity or L["Dungeon"],
            note = ext.note or "",
            sourceType = ext.sourceType or "ALLY_LFG",
        }
    end
    local off = self.officialLfgCache and self.officialLfgCache[key]
    if type(off) == "table" and (now - (off.updatedAt or 0)) <= 900 then
        return {
            mode = off.mode or "LFM",
            role = off.role or "ANY",
            activity = off.activity or L["Official LFG"],
            note = off.note or "",
            sourceType = "OFFICIAL_LFG",
        }
    end
    if bucket and type(bucket.events) == "table" then
        for _, evt in pairs(bucket.events) do
            if type(evt) == "table" and evt.isOpen ~= false and evt.creatorKey == key then
                return {
                    mode = "LFM",
                    role = "ANY",
                    activity = evt.title or L["Guild Event"],
                    note = evt.whenText or "",
                    sourceType = "EVENT",
                }
            end
        end
    end
    if type(self.guildChatLFG) == "table" then
        for i = 1, #self.guildChatLFG do
            local row = self.guildChatLFG[i]
            if type(row) == "table" and row.lookupKey == key and (now - (row.timestamp or row.ts or 0)) <= 900 then
                local msgMode = (row.text and row.text:lower():find("lfg", 1, true)) and "LFG" or "LFM"
                return {
                    mode = msgMode,
                    role = "ANY",
                    activity = row.text or L["Guild Chat"],
                    note = "",
                    sourceType = "GCHAT",
                }
            end
        end
    end
    local peer = bucket and bucket.peers and bucket.peers[key]
    if type(peer) == "table" and (peer.tag == "LFG" or peer.tag == "MPLUS") and (now - (peer.updatedAt or 0)) <= 1800 then
        return {
            mode = "LFG",
            role = "ANY",
            activity = (peer.note and peer.note ~= "" and peer.note) or (peer.tag == "MPLUS" and L["Dungeons"] or L["LFG (Looking for Group)"]),
            note = peer.note or "",
            sourceType = "TAG",
        }
    end
    local pub = self.globalChatLFG and self.globalChatLFG[key]
    if type(pub) == "table" and (now - (pub.updatedAt or 0)) <= 600 then
        return {
            mode = pub.mode or "LFM",
            role = pub.role or "ANY",
            activity = pub.activity or L["Global Chat LFG"],
            note = pub.note or "",
            sourceType = "PUBLIC_CHAT",
        }
    end
    return nil
end

function Clan:ClearMyLFG()
    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    if not myParsed then return false end
    local bucket = Store:GetClanScopeData()
    if bucket.lfg then
        bucket.lfg[myParsed.lookupKey] = nil
        for k, entry in pairs(bucket.lfg) do
            if Compat.IsMe(entry and entry.displayName or k) then
                bucket.lfg[k] = nil
            end
        end
    end
    if self.externalLFG then
        self.externalLFG[myParsed.lookupKey] = nil
    end
    if bucket.myTag == "LFG" or bucket.myTag == "MPLUS" then
        bucket.myTag = "NONE"
    end
    self:SendGuildSync("LFX")
    BroadcastExternalLFG(self, ("ALFX~%s"):format(Compat.CleanPayloadField(myParsed.displayName, 28)))
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:SyncOfficialActiveLfg()
    if self._syncingFromOfficial then return end
    if not (C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.GetActiveEntryInfo) then
        return
    end
    local hasActive = Safe.Value(Safe.Call(C_LFGList.HasActiveEntryInfo)) == true
    local resolvedSelf = Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()
    local myName = (resolvedSelf and resolvedSelf.fullName) or Safe.String(Safe.Call(UnitName, "player"))
    local myParsed = myName and Compat.ParseCharacterName(myName)
    if hasActive then
        local info = Safe.Call(C_LFGList.GetActiveEntryInfo)
        if type(info) == "table" then
            local actName = Safe.String(info.name)
            local actId = Safe.Number(info.activityID)
            if (not actName or actName == "") and actId and C_LFGList.GetActivityInfoTable then
                local aInfo = Safe.Call(C_LFGList.GetActivityInfoTable, actId)
                if type(aInfo) == "table" then
                    actName = Safe.String(aInfo.fullName) or Safe.String(aInfo.shortName)
                end
            end
            local comment = Safe.String(info.comment) or ""
            self._syncingFromOfficial = true
            self._officialLfgActive = true
            local _, row = self:PostLFG("LFM", self:GetMySpecAndRole(), actName or L["Group"], 0, comment)
            if row then row.isOfficial = true end
            self._syncingFromOfficial = false
        end
    elseif self._officialLfgActive then
        self._officialLfgActive = false
        if myParsed then
            local bucket = Store:GetClanScopeData()
            if bucket.lfg and bucket.lfg[myParsed.lookupKey] then
                self:ClearMyLFG()
            end
        end
    end
end

local function ClassifyOfficialActivityKind(categoryId, catName, aInfo)
    local hay = ((catName or "") .. " " .. (aInfo and (aInfo.fullName or aInfo.shortName or "") or "")):lower()
    if aInfo then
        if aInfo.isCurrentRaidActivity or hay:find("raid") or hay:find("raide") or hay:find("banda") then
            return "RAIDS"
        end
        if aInfo.isRatedPvpActivity or aInfo.isPvpActivity or hay:find("pvp") or hay:find("jcj") or hay:find("arena") or hay:find("battleground") or hay:find("campo de batalha") then
            return "PVP"
        end
        if (tonumber(aInfo.maxNumPlayers) or 0) >= 10 then
            return "RAIDS"
        end
        if hay:find("quest") or hay:find("miss") or hay:find("misi") then
            return "QUESTS"
        end
        if hay:find("custom") or hay:find("personaliz") then
            return "CUSTOM"
        end
        if (tonumber(aInfo.maxNumPlayers) or 0) == 5 or hay:find("dungeon") or hay:find("masmorra") or hay:find("mazmorra") then
            return "DUNGEONS"
        end
    end
    if hay:find("raid") or hay:find("raide") or hay:find("banda") then
        return "RAIDS"
    elseif hay:find("pvp") or hay:find("jcj") or hay:find("arena") or hay:find("battle") or hay:find("batalha") or hay:find("batalla") then
        return "PVP"
    elseif hay:find("quest") or hay:find("miss") or hay:find("misi") then
        return "QUESTS"
    elseif hay:find("custom") or hay:find("personaliz") then
        return "CUSTOM"
    elseif hay:find("dungeon") or hay:find("masmorra") or hay:find("mazmorra") then
        return "DUNGEONS"
    end
    if categoryId == 2 then return "DUNGEONS" end
    if categoryId == 3 then return "RAIDS" end
    if categoryId == 114 or categoryId == 118 or categoryId == 7 or categoryId == 8 or categoryId == 9 then return "PVP" end
    if categoryId == 1 or categoryId == 116 then return "QUESTS" end
    if categoryId == 6 or categoryId == 120 then return "CUSTOM" end
    return "DUNGEONS"
end

function Clan:GetOfficialCategoryMap()
    if not (C_LFGList and C_LFGList.GetAvailableCategories) then
        return {}
    end
    local r1 = Safe.Call(C_LFGList.GetAvailableCategories)
    local cats = (type(r1) == "table") and r1 or nil
    if not cats then return {} end

    local map = {}
    for _, catId in ipairs(cats) do
        local numId = Safe.Number(catId)
        if numId then
            local catName = nil
            if C_LFGList.GetLfgCategoryInfo then
                local cInfo = Safe.Call(C_LFGList.GetLfgCategoryInfo, numId)
                if type(cInfo) == "table" then
                    catName = Safe.String(cInfo.name)
                end
            end
            if (not catName or catName == "") and C_LFGList.GetCategoryInfo then
                local c1 = Safe.Call(C_LFGList.GetCategoryInfo, numId)
                if type(c1) == "table" then
                    catName = Safe.String(c1.name)
                else
                    catName = Safe.String(c1)
                end
            end
            local sampleInfo = nil
            if C_LFGList.GetAvailableActivities and C_LFGList.GetActivityInfoTable then
                local actList = Safe.Call(C_LFGList.GetAvailableActivities, numId)
                if type(actList) == "table" and actList[1] then
                    sampleInfo = Safe.Call(C_LFGList.GetActivityInfoTable, actList[1])
                end
            end
            local kind = ClassifyOfficialActivityKind(numId, catName, sampleInfo)
            if not map[kind] then
                map[kind] = numId
            end
        end
    end
    return map
end

local function NormalizeActivityLookupText(text)
    if type(text) ~= "string" then return "" end
    local s = text:lower()
    s = s:gsub("á", "a"):gsub("à", "a"):gsub("ã", "a"):gsub("â", "a")
        :gsub("é", "e"):gsub("ê", "e")
        :gsub("í", "i")
        :gsub("ó", "o"):gsub("ô", "o"):gsub("õ", "o")
        :gsub("ú", "u"):gsub("ç", "c")
        :gsub("'", ""):gsub("`", "")
    return s
end

local KNOWN_ACTIVITY_LEVELS = {
    { key = "ragefire",     minL = 13, maxL = 18 },
    { key = "cavernas igneas", minL = 13, maxL = 18 },
    { key = "simas igneas", minL = 13, maxL = 18 },
    { key = "thanes",       minL = 13, maxL = 18 },
    { key = "lordaeron",    minL = 15, maxL = 22 },
    { key = "wailing caverns", minL = 15, maxL = 24 },
    { key = "caverna ululante", minL = 15, maxL = 24 },
    { key = "cuevas de los lamentos", minL = 15, maxL = 24 },
    { key = "deadmines",    minL = 17, maxL = 26 },
    { key = "minas mortas", minL = 17, maxL = 26 },
    { key = "minas de la muerte", minL = 17, maxL = 26 },
    { key = "shadowfang",   minL = 22, maxL = 30 },
    { key = "presa negra",  minL = 22, maxL = 30 },
    { key = "colmillo oscuro", minL = 22, maxL = 30 },
    { key = "blackfathom",  minL = 24, maxL = 32 },
    { key = "profundezas negras", minL = 24, maxL = 32 },
    { key = "cavernas de brazanegra", minL = 24, maxL = 32 },
    { key = "stockade",     minL = 24, maxL = 32 },
    { key = "carcere",      minL = 24, maxL = 32 },
    { key = "mazmorras de ventormenta", minL = 24, maxL = 32 },
    { key = "sitio de escavacao", minL = 24, maxL = 33 },
    { key = "digsite: wetlands", minL = 24, maxL = 33 },
    { key = "excavacion",   minL = 24, maxL = 33 },
    { key = "cemiterio",    minL = 28, maxL = 36 },
    { key = "graveyard",    minL = 28, maxL = 36 },
    { key = "cementerio",   minL = 28, maxL = 36 },
    { key = "gnomeregan",   minL = 29, maxL = 38 },
    { key = "razorfen kraul", minL = 29, maxL = 38 },
    { key = "urzal dos tuscos", minL = 29, maxL = 38 },
    { key = "horado rajacieno", minL = 29, maxL = 38 },
    { key = "biblioteca",   minL = 32, maxL = 39 },
    { key = "library",      minL = 32, maxL = 39 },
    { key = "libreria",     minL = 32, maxL = 39 },
    { key = "cidade afogada", minL = 35, maxL = 40 },
    { key = "drowned city", minL = 35, maxL = 40 },
    { key = "ciudad sumergida", minL = 35, maxL = 40 },
    { key = "armaria",      minL = 35, maxL = 42 },
    { key = "armory",       minL = 35, maxL = 42 },
    { key = "armeria",      minL = 35, maxL = 42 },
    { key = "catedral",     minL = 37, maxL = 45 },
    { key = "cathedral",    minL = 37, maxL = 45 },
    { key = "scarlet monastery", minL = 28, maxL = 45 },
    { key = "monasterio escarlate", minL = 28, maxL = 45 },
    { key = "razorfen downs", minL = 37, maxL = 46 },
    { key = "urzal dos mortos", minL = 37, maxL = 46 },
    { key = "zahurda rajacieno", minL = 37, maxL = 46 },
    { key = "kroldok",      minL = 40, maxL = 45 },
    { key = "krol dok",     minL = 40, maxL = 45 },
    { key = "uldaman",      minL = 41, maxL = 51 },
    { key = "zulfarrak",    minL = 44, maxL = 54 },
    { key = "maraudon",     minL = 46, maxL = 55 },
    { key = "alcaz",        minL = 48, maxL = 53 },
    { key = "sunken temple", minL = 50, maxL = 60 },
    { key = "templo submerso", minL = 50, maxL = 60 },
    { key = "atalhakkar",   minL = 50, maxL = 60 },
    { key = "blackrock depths", minL = 52, maxL = 60 },
    { key = "abismo rocha negra", minL = 52, maxL = 60 },
    { key = "profundidades de rocanegra", minL = 52, maxL = 60 },
    { key = "lower blackrock", minL = 55, maxL = 60 },
    { key = "rocha negra inferior", minL = 55, maxL = 60 },
    { key = "rocanegra inferior", minL = 55, maxL = 60 },
    { key = "dire maul",    minL = 56, maxL = 60 },
    { key = "gladio cruel", minL = 56, maxL = 60 },
    { key = "la masacre",   minL = 56, maxL = 60 },
    { key = "upper blackrock", minL = 58, maxL = 60 },
    { key = "rocha negra superior", minL = 58, maxL = 60 },
    { key = "rocanegra superior", minL = 58, maxL = 60 },
    { key = "stratholme",   minL = 58, maxL = 60 },
    { key = "scholomance",  minL = 58, maxL = 60 },
    { key = "scolomantia",  minL = 58, maxL = 60 },
    { key = "bocanera",     minL = 58, maxL = 60 },
    { key = "blackmaw",     minL = 58, maxL = 60 },
    { key = "terraco do moldador", minL = 58, maxL = 60 },
    { key = "shapers terrace", minL = 58, maxL = 60 },
    { key = "terraza del moldeador", minL = 58, maxL = 60 },
    { key = "zulgurub",     minL = 60, maxL = 60 },
    { key = "molten core",  minL = 60, maxL = 60 },
    { key = "nucleo derretido", minL = 60, maxL = 60 },
    { key = "nucleo de magma", minL = 60, maxL = 60 },
    { key = "onyxia",       minL = 60, maxL = 60 },
    { key = "blackwing",    minL = 60, maxL = 60 },
    { key = "asa negra",    minL = 60, maxL = 60 },
    { key = "alanegra",     minL = 60, maxL = 60 },
    { key = "ahnqiraj",     minL = 60, maxL = 60 },
    { key = "naxxramas",    minL = 60, maxL = 60 },
    { key = "warsong",      minL = 10, maxL = 60 },
    { key = "brado guerreiro", minL = 10, maxL = 60 },
    { key = "grito de guerra", minL = 10, maxL = 60 },
    { key = "arathi",       minL = 20, maxL = 60 },
    { key = "alterac",      minL = 51, maxL = 60 },
}

function Clan:ResolveActivityLevelRange(aInfo, activityName, catKind)
    if type(aInfo) == "table" then
        local sugMin = Safe.Number(aInfo.minLevelSuggestion)
        local sugMax = Safe.Number(aInfo.maxLevelSuggestion)
        if sugMin and sugMin > 0 and sugMax and sugMax >= sugMin then
            return sugMin, sugMax
        end
        local recMin = Safe.Number(aInfo.recommendedMinLevel)
        local recMax = Safe.Number(aInfo.recommendedMaxLevel)
        if recMin and recMin > 0 and recMax and recMax >= recMin then
            return recMin, recMax
        end
        local rawMin = Safe.Number(aInfo.minLevel)
        local rawMax = Safe.Number(aInfo.maxLevel)
        if rawMin and rawMin > 0 and rawMax and rawMax >= rawMin and not (rawMin <= 1 and rawMax >= 60) then
            return rawMin, rawMax
        end
    end
    local norm = NormalizeActivityLookupText(activityName)
    if norm ~= "" then
        for i = 1, #KNOWN_ACTIVITY_LEVELS do
            local entry = KNOWN_ACTIVITY_LEVELS[i]
            if norm:find(entry.key, 1, true) then
                return entry.minL, entry.maxL
            end
        end
    end
    if catKind == "RAIDS" then
        return 60, 60
    end
    return nil, nil
end

function Clan:GetOfficialActivitiesForKind(catKind)
    if not (C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities and C_LFGList.GetActivityInfoTable) then
        return {}
    end
    local catMap = self:GetOfficialCategoryMap()
    local catId = catMap and catMap[catKind or "DUNGEONS"]
    if not catId then
        return {}
    end
    local actIds = Safe.Call(C_LFGList.GetAvailableActivities, catId)
    if type(actIds) ~= "table" or #actIds == 0 then
        return {}
    end
    local out = {}
    local seen = {}
    for _, rawId in ipairs(actIds) do
        local aid = Safe.Number(rawId)
        if aid and not seen[aid] then
            seen[aid] = true
            local aInfo = Safe.Call(C_LFGList.GetActivityInfoTable, aid)
            if type(aInfo) == "table" then
                local full = Safe.String(aInfo.fullName) or Safe.String(aInfo.shortName)
                if full and full ~= "" then
                    local minL, maxL = self:ResolveActivityLevelRange(aInfo, full, catKind)
                    out[#out + 1] = {
                        officialId = aid,
                        categoryId = catId,
                        label = full,
                        shortLabel = Safe.String(aInfo.shortName) or full,
                        minLvl = minL,
                        maxLvl = maxL,
                        maxPlayers = Safe.Number(aInfo.maxNumPlayers) or ((catKind == "RAIDS") and 40 or 5),
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local am = a.minLvl or 999
        local bm = b.minLvl or 999
        if am ~= bm then
            return am < bm
        end
        return (a.label or "") < (b.label or "")
    end)
    return out
end

function Clan:SearchOfficialLfg(catKind, specificActivityIds)
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then return false end
    if not (C_LFGList and C_LFGList.Search) then return false end
    local now = GetTime()
    if (now - (self._lastOfficialSearchAt or 0)) < 2.0 then
        return false
    end

    local targetKind = (catKind and catKind ~= "ALL") and catKind or "DUNGEONS"
    local catMap = self:GetOfficialCategoryMap()
    if (not catKind or catKind == "ALL") then
        local myLvl = (Safe and Safe.Number(UnitLevel and UnitLevel("player"))) or 60
        if myLvl > 0 and myLvl < 13 and catMap and catMap.QUESTS then
            targetKind = "QUESTS"
        end
    end
    local catId = (catMap and catMap[targetKind]) or (catMap and catMap.DUNGEONS)
    if not catId then
        local r1 = C_LFGList.GetAvailableCategories and Safe.Call(C_LFGList.GetAvailableCategories)
        catId = (type(r1) == "table" and Safe.Number(r1[1])) or 2
    end
    if not catId then return false end

    self._lastOfficialSearchAt = now
    self._lastOfficialSearchKind = targetKind
    self._officialSearchPendingUntil = now + 4.0

    local ok = false
    if type(specificActivityIds) == "table" and #specificActivityIds > 0 then
        ok = pcall(C_LFGList.Search, catId, specificActivityIds)
        if not ok then
            ok = pcall(C_LFGList.Search, catId)
        end
    else
        ok = pcall(C_LFGList.Search, catId)
        if not ok and C_LFGList.GetAvailableActivities then
            local allActs = Safe.Call(C_LFGList.GetAvailableActivities, catId)
            if type(allActs) == "table" then
                ok = pcall(C_LFGList.Search, catId, allActs)
            end
        end
    end
    if ok and self.ScanOfficialLfgResults then
        -- Also harvest any immediately cached results while async update arrives
        self:ScanOfficialLfgResults(true)
    end
    return ok
end

function Clan:ScanOfficialLfgResults(skipPruningEmpty)
    if not IsGlobalLfgListenerActive() then
        return
    end
    if not (C_LFGList and C_LFGList.GetSearchResults and C_LFGList.GetSearchResultInfo) then
        return
    end
    local r1, r2 = Safe.Call(C_LFGList.GetSearchResults)
    local results = (type(r2) == "table" and r2) or (type(r1) == "table" and r1)
    if type(results) ~= "table" then return end

    self.officialLfgCache = self.officialLfgCache or {}
    self._officialSearchPendingUntil = 0
    local now = time()
    local freshKeys = {}
    local scannedKind = self._lastOfficialSearchKind
    local limit = math.min(#results, 80)
    for i = 1, limit do
        local resId = results[i]
        local info = resId and Safe.Call(C_LFGList.GetSearchResultInfo, resId)
        if type(info) == "table" and not info.isDelisted then
            local leaderRaw = Safe.String(info.leaderName)
            local leaderLk, _, leaderDisp = leaderRaw and Compat.ParseCharacterFields and Compat.ParseCharacterFields(leaderRaw)
            if leaderLk and leaderDisp and not Compat.IsMe(leaderDisp) then
                local actIdsList = {}
                local rawScalar = Safe.Number(info.activityID)
                if rawScalar then
                    actIdsList[1] = rawScalar
                elseif type(info.activityIDs) == "table" then
                    for j = 1, #info.activityIDs do
                        local aid = Safe.Number(info.activityIDs[j])
                        if aid then
                            actIdsList[#actIdsList + 1] = aid
                        end
                    end
                end

                local actNames = {}
                local catKind = scannedKind or "DUNGEONS"
                local maxMembers = 5
                local minActLvl, maxActLvl = nil, nil
                if C_LFGList.GetActivityInfoTable then
                    for idx = 1, #actIdsList do
                        local aInfo = Safe.Call(C_LFGList.GetActivityInfoTable, actIdsList[idx])
                        if type(aInfo) == "table" then
                            local nm = Safe.String(aInfo.fullName) or Safe.String(aInfo.shortName)
                            if nm and nm ~= "" then
                                actNames[#actNames + 1] = nm
                            end
                            if idx == 1 then
                                catKind = ClassifyOfficialActivityKind(Safe.Number(aInfo.categoryID), nil, aInfo)
                                maxMembers = Safe.Number(aInfo.maxNumPlayers) or ((catKind == "RAIDS") and 40 or 5)
                                minActLvl, maxActLvl = self:ResolveActivityLevelRange(aInfo, nm, catKind)
                            end
                        end
                    end
                end

                local customTitle = Safe.String(info.name) or ""
                local actDisplay = ""
                if #actNames == 1 then
                    actDisplay = actNames[1]
                elseif #actNames >= 2 then
                    actDisplay = actNames[1] .. " (+" .. tostring(#actNames - 1) .. ")"
                end
                if actDisplay == "" then
                    actDisplay = customTitle
                end
                if not minActLvl and actDisplay ~= "" then
                    minActLvl, maxActLvl = self:ResolveActivityLevelRange(nil, actDisplay, catKind)
                end

                local comment = Safe.String(info.comment) or ""
                if customTitle ~= "" and customTitle ~= actDisplay and customTitle:lower() ~= actDisplay:lower() then
                    if comment ~= "" then
                        comment = customTitle .. " - " .. comment
                    else
                        comment = customTitle
                    end
                end

                local numMembers = Safe.Number(info.numMembers) or 0
                local filledT, filledH, filledD, filledNoRole = 0, 0, 0, 0
                local needT, needH, needD
                if C_LFGList.GetSearchResultMemberCounts then
                    local mc = Safe.Call(C_LFGList.GetSearchResultMemberCounts, resId)
                    if type(mc) == "table" then
                        filledT = Safe.Number(mc.TANK) or 0
                        filledH = Safe.Number(mc.HEALER) or 0
                        filledD = Safe.Number(mc.DAMAGER) or 0
                        filledNoRole = Safe.Number(mc.NOROLE) or 0
                        if maxMembers <= 5 then
                            if (filledT + filledH + filledD) > 0 or filledNoRole == 0 then
                                needT = math.max(0, 1 - filledT)
                                needH = math.max(0, 1 - filledH)
                                needD = math.max(0, 3 - filledD)
                                if maxMembers > 0 and numMembers >= maxMembers then
                                    needT, needH, needD = 0, 0, 0
                                end
                            elseif filledNoRole > 0 then
                                needT = 1
                                needH = 1
                                needD = math.max(0, 3 - filledNoRole)
                                if maxMembers > 0 and numMembers >= maxMembers then
                                    needT, needH, needD = 0, 0, 0
                                end
                            end
                        end
                    end
                end

                local leaderLvl = Safe.Number(info.leaderLevel) or 0
                local isClan, isAllied, isFriend, isWatchlist, resolvedGuild = self:GetPlayerRelationshipFlags(leaderLk, leaderDisp)
                local rec = {
                    lookupKey = leaderLk,
                    displayName = leaderDisp,
                    guild = resolvedGuild,
                    level = leaderLvl > 0 and leaderLvl or nil,
                    mode = "LFM",
                    role = "ANY",
                    filledT = filledT,
                    filledH = filledH,
                    filledD = filledD,
                    filledNoRole = filledNoRole,
                    needT = needT,
                    needH = needH,
                    needD = needD,
                    numMembers = numMembers > 0 and numMembers or nil,
                    maxMembers = maxMembers,
                    activity = actDisplay ~= "" and actDisplay or L["Official LFG"],
                    activityAllNames = (#actNames > 0) and table.concat(actNames, ", ") or actDisplay,
                    activityIds = actIdsList,
                    categoryKind = catKind,
                    minActLvl = minActLvl,
                    maxActLvl = maxActLvl,
                    note = comment,
                    ilvl = Safe.Number(info.requiredItemLevel) or 0,
                    isDungeon = (catKind == "DUNGEONS"),
                    isOfficial = true,
                    updatedAt = now,
                }
                self.officialLfgCache[leaderLk] = rec
                freshKeys[leaderLk] = true
                if isClan or isAllied or isFriend or isWatchlist then
                    local summary = ("%s%s"):format(rec.activity, (comment ~= "" and (" - " .. comment) or ""))
                    self:MaybeNotifyClanLFG(leaderLk, leaderDisp, nil, summary, rec.activity, rec.isDungeon, "OFFICIAL_LFG", leaderLvl)
                end
            end
        end
    end

    if not skipPruningEmpty then
        for k, oldRec in pairs(self.officialLfgCache) do
            if not freshKeys[k] then
                if (scannedKind and oldRec and oldRec.categoryKind == scannedKind) or (not scannedKind) then
                    self.officialLfgCache[k] = nil
                end
            end
        end
    end
    QueueClanEmit(0.2)
end

function Clan:OpenOfficialLfgForGuild(activity, note, mode)
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then return false end
    if Compat.IsInGroup and Compat.IsInGroup() and Compat.IsGroupLeader and not Compat.IsGroupLeader() then
        ns:Print("%s", L["Only the party leader can list the group in Blizzard's Group Finder; your Guild & Allies broadcast was sent."])
        return false
    end
    local guildName = (Store.guildInfo and Store.guildInfo.inGuild and Store.guildInfo.name) or Safe.String(Safe.Call(GetGuildInfo, "player"))
    local gTag = (guildName and guildName ~= "") and ("[" .. guildName .. "] ") or ""
    local bodyText = (note and note ~= "") and note or (activity or "")
    local fullComment = Compat.CleanPayloadField(gTag .. bodyText, 90)
    if ns.LFGFrameTab and ns.LFGFrameTab.HideSubPanel then
        ns.LFGFrameTab:HideSubPanel(false)
    end
    local listingTab = (_G.LFGParentFrame and _G.LFGParentFrame.ListingTab) or _G.LFGParentFrameTab1
    if listingTab and listingTab.Click then
        pcall(listingTab.Click, listingTab)
    elseif _G.LFGListingFrame and _G.LFGListingFrame.Show then
        pcall(_G.LFGListingFrame.Show, _G.LFGListingFrame)
    end
    local lf = _G.LFGListingFrame
    local cBox = lf and (lf.Comment or lf.CommentBox or (lf.Description and lf.Description.EditBox))
    if cBox and cBox.SetText and fullComment ~= "" then
        pcall(cBox.SetText, cBox, fullComment)
    end
    ns:Print(L["Official LFG opened with your guild tag pre-filled; click List to publish."])
    return true
end

function Clan:OpenGuildChatLFG(mode, role, activity, keyLvl, note)
    local cleanAct = Compat.CleanPayloadField(activity or "", 40)
    local cleanNote = Compat.CleanPayloadField(note or "", 44)
    local prefix = (mode == "LFM") and "LFM" or "LFG"
    local draft = ("/g [%s] %s%s%s%s"):format(
        prefix,
        (role and role ~= "" and role ~= "ANY") and (role .. " - ") or "",
        (tonumber(keyLvl) or 0) > 0 and ("+" .. tonumber(keyLvl) .. " ") or "",
        cleanAct ~= "" and cleanAct or "Dungeon",
        cleanNote ~= "" and (" (" .. cleanNote .. ")") or ""
    )
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, draft)
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, draft)
        return true
    end
    return false
end

function Clan:ShareQueueOrEventToClanLFG()
    local sum = self:GetPlayerGameSummary()
    local role = sum.role or "DPS"
    if sum.premadeTitle and sum.premadeTitle ~= "" then
        return self:PostLFG("LFM", role, sum.premadeTitle, sum.keystoneLevel or 0, L["Active Premade Group"])
    elseif (sum.keystoneLevel or 0) > 0 and sum.keystoneName then
        return self:PostLFG("LFM", role, sum.keystoneName, sum.keystoneLevel, L["My Keystone"])
    elseif sum.lfgQueued then
        return self:PostLFG("LFG", role, L["Dungeon Finder Queue"], 0, L["Queued in LFD"])
    elseif sum.inInstance and sum.instanceName then
        return self:PostLFG("LFG", role, sum.instanceName, 0, L["Inside Instance"])
    end
    return self:PostLFG("LFG", role, L["Random Heroic Dungeon"], 0, "")
end

function Clan:GetPlayerRelationshipFlags(lookupKey, rawName, guid, rawGuild)
    local key = lookupKey
    if (not key or key == "") and rawName and rawName ~= "" and Compat.ParseCharacterName then
        local parsed = Compat.ParseCharacterName(rawName)
        key = parsed and parsed.lookupKey
    end
    local cleanGuid = Safe.String(guid)
    local parsedName = (rawName and rawName ~= "" and Compat.ParseCharacterName) and Compat.ParseCharacterName(rawName) or nil
    local firstName = (parsedName and parsedName.firstName) or rawName
    local hasSurname = (parsedName and parsedName.surname ~= nil) or false
    local isClan, isAllied, isFriend, isWatchlist = false, false, false, false
    local resolvedGuild = (type(rawGuild) == "string" and rawGuild ~= "") and rawGuild or nil

    local myGuildName = (Store.guildInfo and Store.guildInfo.name) or Safe.String(Safe.Call(GetGuildInfo, "player")) or ""
    local myNormGuild = NormalizeGuildKey(myGuildName)

    if Compat.IsGuildMember and Compat.IsGuildMember(firstName, cleanGuid, rawName) then
        isClan = true
    end

    local function ApplyMatchedSocialRow(row)
        if type(row) ~= "table" then return false end
        local matched = (cleanGuid and row.guid and row.guid == cleanGuid)
            or (not (cleanGuid and row.guid and row.guid ~= cleanGuid) and key and row.lookupKey and row.lookupKey == key)
        if not matched then return false end
        if row.sources and row.sources.guild == true then
            isClan = true
        end
        if row.sources and (row.sources.friend == true or row.sources.bnet == true) then
            isFriend = true
        end
        if (not resolvedGuild or resolvedGuild == "") and row.guild and row.guild ~= "" then
            resolvedGuild = row.guild
        end
        return true
    end

    if Store.socialByGuid or Store.socialByLookup then
        local gRow = cleanGuid and Store.socialByGuid and Store.socialByGuid[cleanGuid]
        if not ApplyMatchedSocialRow(gRow) and key and Store.socialByLookup then
            ApplyMatchedSocialRow(Store.socialByLookup[key])
        end
    elseif type(Store.social) == "table" then
        for _, row in pairs(Store.social) do
            if ApplyMatchedSocialRow(row) then
                break
            end
        end
    end

    if not isFriend and cleanGuid and C_FriendList and C_FriendList.IsFriend then
        local okF, resF = pcall(C_FriendList.IsFriend, cleanGuid)
        if okF and Safe.Value(resF) == true then
            isFriend = true
        end
    end

    if Store.GetWatchlistTable and key then
        local wl = Store:GetWatchlistTable()
        local firstLower = (type(firstName) == "string" and firstName ~= "") and firstName:lower() or nil
        local wRow = wl and (wl[key] or (not hasSurname and firstLower and wl[firstLower]))
        if type(wRow) == "table" and not (cleanGuid and wRow.guid and wRow.guid ~= cleanGuid) then
            isWatchlist = true
            if (not resolvedGuild or resolvedGuild == "") and wRow.guild and wRow.guild ~= "" then
                resolvedGuild = wRow.guild
            end
        end
    end

    if not resolvedGuild and type(Store.nearby) == "table" and key then
        local nRow = Store.nearby[key]
        if type(nRow) == "table" and not (cleanGuid and nRow.guid and nRow.guid ~= cleanGuid) and nRow.guild and nRow.guild ~= "" then
            resolvedGuild = nRow.guild
        end
    end

    if resolvedGuild and resolvedGuild ~= "" then
        local normG = NormalizeGuildKey(resolvedGuild)
        if myNormGuild ~= "" and normG == myNormGuild then
            isClan = true
        elseif self:IsAlliedGuild(resolvedGuild) then
            isAllied = true
        end
    end

    return isClan, isAllied, isFriend, isWatchlist, resolvedGuild
end

function Clan:GetClanLFGList(query, dungeonsOnly, sourceFilter, roleFilter)
    local bucket = Store:GetClanScopeData()
    local liveByLookup = Store.socialByLookup
    if not liveByLookup then
        liveByLookup = {}
        if type(Store.social) == "table" then
            for _, row in pairs(Store.social) do
                if type(row) == "table" and row.lookupKey and not liveByLookup[row.lookupKey] then
                    liveByLookup[row.lookupKey] = row
                end
            end
        end
    end

    local filterMode = (type(sourceFilter) == "string" and sourceFilter:upper()) or "ALL"
    if filterMode ~= "CLAN" and filterMode ~= "ALLY" and filterMode ~= "FRIENDS" and filterMode ~= "PUBLIC_CHAT" and filterMode ~= "TRUSTED" and filterMode ~= "SC_USERS" then
        filterMode = "ALL"
    end
    local cleanRoleFilter = (type(roleFilter) == "string" and roleFilter:upper()) or "ALL"
    if cleanRoleFilter ~= "TANK" and cleanRoleFilter ~= "HEALER" and cleanRoleFilter ~= "DPS" and cleanRoleFilter ~= "MINE" then
        cleanRoleFilter = "ALL"
    end
    local myRecRoles = (cleanRoleFilter == "MINE" and self.GetRecommendedRolesForCharacter)
        and (self:GetRecommendedRolesForCharacter().recommended)
        or nil

    local out = {}
    local seen = {}
    local q = (type(query) == "string" and query ~= "") and query:lower() or nil
    local now = time()

    local function PushItem(item)
        local isClan, isAllied, isFriend, isWatchlist, resolvedGuild = self:GetPlayerRelationshipFlags(
            item.lookupKey,
            item.displayName,
            item.guid,
            item.guild
        )
        if item._forceClan then isClan = true end
        if item._forceAllied then isAllied = true end
        item.isClan = isClan
        item.isAllied = isAllied
        item.isFriend = isFriend or item.isFriend == true
        item.isWatchlist = isWatchlist or item.isWatchlist == true
        if resolvedGuild and resolvedGuild ~= "" then
            item.guild = resolvedGuild
        end

        local hasAddon = (item.isSelf == true)
            or (item.sourceType == "LFG" or item.sourceType == "EVENT" or item.sourceType == "TAG" or item.sourceType == "ALLY_LFG")
            or (item.lookupKey and self.peerVersions and self.peerVersions[item.lookupKey] ~= nil)
            or (item.lookupKey and bucket.peers and bucket.peers[item.lookupKey] ~= nil)
            or (ns.Chat and ns.Chat.IsPlayerAddonConfirmed and ns.Chat:IsPlayerAddonConfirmed(item.lookupKey or item.displayName, item.bnetAccountID))
        item.hasAddon = hasAddon == true

        local compRec = (item.lookupKey and Store and Store.GetRecentCompanion) and Store:GetRecentCompanion(item.lookupKey) or nil
        if compRec then
            item.isCompanion = true
            item.companionRuns = tonumber(compRec.runs) or 1
        end

        local isTrusted = item.isClan or item.isAllied or item.isFriend or item.isWatchlist or item.hasFriendOrWatchlistSignup or item.isCompanion
        local gStr = item.guild or resolvedGuild
        local isEnemyGuild = (not isClan and not isAllied and gStr and gStr ~= "" and ns.Spotter and ns.Spotter.ClassifyGuild and ns.Spotter:ClassifyGuild(gStr) == "ENEMY") == true
        item.isEnemyGuild = isEnemyGuild
        if filterMode == "CLAN" and not item.isClan then
            return
        elseif filterMode == "ALLY" and not item.isAllied then
            return
        elseif filterMode == "FRIENDS" and not (item.isFriend or item.isWatchlist or item.hasFriendOrWatchlistSignup) then
            return
        elseif filterMode == "PUBLIC_CHAT" and item.sourceType ~= "PUBLIC_CHAT" then
            return
        elseif filterMode == "TRUSTED" and not isTrusted then
            return
        elseif filterMode == "SC_USERS" and not item.hasAddon then
            return
        end

        if cleanRoleFilter ~= "ALL" then
            local function MatchesSingleRole(targetRole)
                if item.sourceType == "EVENT" then
                    if targetRole == "TANK" then return (item.needT or 0) > 0 end
                    if targetRole == "HEALER" then return (item.needH or 0) > 0 end
                    if targetRole == "DPS" then return (item.needD or 0) > 0 end
                    return false
                end
                local lowNote = type(item.note) == "string" and item.note:lower() or ""
                local hasTankNote = lowNote:find("tank", 1, true) or lowNote:find("tanque", 1, true) or lowNote:find("1t", 1, true)
                local hasHealNote = lowNote:find("heal", 1, true) or lowNote:find("cura", 1, true) or lowNote:find("1h", 1, true)
                local hasDpsNote = lowNote:find("dps", 1, true) or lowNote:find("dano", 1, true) or lowNote:find("1d", 1, true) or lowNote:find("2d", 1, true) or lowNote:find("3d", 1, true)
                local hasExplicitRoleNote = hasTankNote or hasHealNote or hasDpsNote
                if item.mode == "LFM" then
                    if hasExplicitRoleNote then
                        if targetRole == "TANK" then return hasTankNote ~= nil end
                        if targetRole == "HEALER" then return hasHealNote ~= nil end
                        if targetRole == "DPS" then return hasDpsNote ~= nil end
                    elseif item.needT ~= nil or item.needH ~= nil or item.needD ~= nil then
                        if targetRole == "TANK" then return (item.needT or 0) > 0 end
                        if targetRole == "HEALER" then return (item.needH or 0) > 0 end
                        if targetRole == "DPS" then return (item.needD or 0) > 0 end
                    end
                    return true
                end
                if item.role == targetRole or item.role == "ANY" or not item.role or item.role == "" then
                    return true
                end
                if hasExplicitRoleNote then
                    if targetRole == "TANK" and hasTankNote then return true end
                    if targetRole == "HEALER" and hasHealNote then return true end
                    if targetRole == "DPS" and hasDpsNote then return true end
                end
                return false
            end

            local roleMatches = false
            if cleanRoleFilter == "MINE" and myRecRoles then
                for rKey, isRec in pairs(myRecRoles) do
                    if isRec and MatchesSingleRole(rKey) then
                        roleMatches = true
                        break
                    end
                end
            else
                roleMatches = MatchesSingleRole(cleanRoleFilter)
            end
            if not roleMatches then
                return
            end
        end

        if dungeonsOnly and not item.isDungeon then
            return
        end
        if q then
            local hay = (
                (item.displayName or "") .. " " ..
                (item.guild or "") .. " " ..
                (item.activity or "") .. " " ..
                (item.activityAllNames or "") .. " " ..
                (item.note or "") .. " " ..
                (item.role or "") .. " " ..
                (item.mode or "") .. " " ..
                (item.friendOrWatchlistNames or "")
            ):lower()
            if not hay:find(q, 1, true) then
                return
            end
        end
        table.insert(out, item)
    end

    for key, rec in pairs(bucket.lfg or {}) do
        local live = liveByLookup[key]
        local item = {
            sourceType = "LFG",
            lookupKey = key,
            guid = live and live.guid,
            displayName = (live and live.displayName) or rec.displayName or key,
            classFile = (live and live.classFile) or rec.classFile,
            level = live and live.level,
            area = live and live.area or "",
            guild = live and live.guild,
            online = (live ~= nil) or Compat.IsMe(rec.displayName or key),
            mode = rec.mode or "LFG",
            role = rec.role or "ANY",
            activity = rec.activity or L["Dungeon"],
            keyLvl = tonumber(rec.keyLvl) or 0,
            ilvl = tonumber(rec.ilvl) or 0,
            note = rec.note or "",
            isDungeon = rec.isDungeon ~= false or IsDungeonLFGText(rec.activity or "", nil),
            updatedAt = rec.updatedAt or 0,
            isSelf = Compat.IsMe(rec.displayName or key),
            _forceClan = true,
        }
        seen[key] = true
        PushItem(item)
    end

    for _, evt in pairs(bucket.events or {}) do
        if evt.isOpen ~= false then
            local sum = self:GetSignupSummary(evt)
            local remT = math.max(0, (tonumber(evt.needT) or 0) - sum.TANK)
            local remH = math.max(0, (tonumber(evt.needH) or 0) - sum.HEALER)
            local remD = math.max(0, (tonumber(evt.needD) or 0) - sum.DPS)
            local needText = string.format("Need T:%d H:%d D:%d", remT, remH, remD)
            local live = evt.creatorKey and liveByLookup[evt.creatorKey]

            local hasFW, hasGoodP, hasAvoidP = false, false, false
            local fwNames, goodNames, avoidNames = {}, {}, {}
            for sKey, sRec in pairs(evt.signups or {}) do
                if type(sRec) == "table" and sRec.role ~= "DECLINE" then
                    local sName = sRec.name or sKey
                    local _, _, sFriend, sWatch = self:GetPlayerRelationshipFlags(sKey, sRec.name)
                    if sFriend or sWatch then
                        hasFW = true
                        table.insert(fwNames, sName)
                    end
                    local sMeta = Store and (Store.GetResolvedSocialMeta and Store:GetResolvedSocialMeta(sKey) or (Store.GetSocialMeta and Store:GetSocialMeta(sKey)))
                    local sComp = Store and Store.GetRecentCompanion and Store:GetRecentCompanion(sKey)
                    if sMeta and sMeta.flag == "AVOID" then
                        hasAvoidP = true
                        table.insert(avoidNames, sName)
                    elseif (sMeta and sMeta.flag == "GOOD") or sComp ~= nil then
                        hasGoodP = true
                        table.insert(goodNames, sName)
                    end
                end
            end

            PushItem({
                sourceType = "EVENT",
                eventId = evt.id,
                lookupKey = evt.creatorKey,
                guid = live and live.guid,
                displayName = evt.creator or "?",
                classFile = live and live.classFile,
                level = live and live.level,
                area = live and live.area or "",
                guild = live and live.guild,
                online = live ~= nil or Compat.IsMe(evt.creator or ""),
                mode = "LFM",
                role = "ANY",
                needT = remT,
                needH = remH,
                needD = remD,
                activity = evt.title or "?",
                keyLvl = 0,
                ilvl = 0,
                note = needText .. " | " .. (evt.whenText or L["Now"]),
                isDungeon = IsDungeonLFGText(evt.title or "", evt.category),
                hasFriendOrWatchlistSignup = hasFW,
                friendOrWatchlistNames = (#fwNames > 0) and table.concat(fwNames, ", ") or "",
                hasGoodPartnerSignup = hasGoodP,
                goodPartnerNames = (#goodNames > 0) and table.concat(goodNames, ", ") or "",
                hasAvoidSignup = hasAvoidP,
                avoidSignupNames = (#avoidNames > 0) and table.concat(avoidNames, ", ") or "",
                updatedAt = evt.updatedAt or evt.createdAt or 0,
                _forceClan = (evt.isAlliedEvent ~= true),
                _forceAllied = (evt.isAlliedEvent == true),
            })
        end
    end

    for key, peer in pairs(bucket.peers or {}) do
        if not seen[key] and (peer.tag == "LFG" or peer.tag == "MPLUS") then
            local live = liveByLookup[key]
            local isDng = (peer.tag == "MPLUS") or IsDungeonLFGText(peer.note or "", nil)
            seen[key] = true
            PushItem({
                sourceType = "TAG",
                lookupKey = key,
                guid = live and live.guid,
                displayName = (live and live.displayName) or peer.displayName or key,
                classFile = (live and live.classFile) or peer.classFile,
                level = live and live.level,
                area = live and live.area or "",
                guild = live and live.guild,
                online = live ~= nil,
                mode = "LFG",
                role = "ANY",
                activity = peer.tag == "MPLUS" and L["Dungeons"] or L["LFG (Looking for Group)"],
                keyLvl = 0,
                ilvl = 0,
                note = peer.note or "",
                isDungeon = isDng or (peer.tag == "LFG"),
                updatedAt = peer.updatedAt or 0,
                _forceClan = true,
            })
        end
    end

    for _, row in ipairs(self:GetGuildChatLFGList()) do
        if not seen[row.lookupKey] then
            seen[row.lookupKey] = true
            local live = liveByLookup[row.lookupKey]
            local gMode = (row.text and row.text:lower():find("lfg", 1, true)) and "LFG" or "LFM"
            PushItem({
                sourceType = "GCHAT",
                lookupKey = row.lookupKey,
                guid = live and live.guid,
                displayName = row.displayName,
                classFile = live and live.classFile,
                level = live and live.level,
                area = live and live.area or "",
                guild = live and live.guild,
                online = true,
                mode = gMode,
                role = "ANY",
                activity = L["Guild Chat"],
                keyLvl = 0,
                ilvl = 0,
                note = row.text or "",
                isDungeon = row.isDungeon == true or IsDungeonLFGText(row.text or "", nil),
                updatedAt = row.timestamp or 0,
                _forceClan = true,
            })
        end
    end

    for key, ext in pairs(self.externalLFG or {}) do
        if type(ext) == "table" and (now - (ext.updatedAt or 0)) <= 1800 and not seen[key] then
            seen[key] = true
            local live = liveByLookup[key]
            PushItem({
                sourceType = ext.sourceType or "ALLY_LFG",
                lookupKey = key,
                guid = (live and live.guid) or ext.guid,
                displayName = (live and live.displayName) or ext.displayName or key,
                classFile = (live and live.classFile) or ext.classFile,
                level = live and live.level,
                area = live and live.area or "",
                guild = (ext.guild and ext.guild ~= "" and ext.guild) or (live and live.guild),
                online = (live ~= nil) or ((now - (ext.updatedAt or 0)) <= 900),
                mode = ext.mode or "LFG",
                role = ext.role or "ANY",
                activity = ext.activity or L["Dungeon"],
                keyLvl = tonumber(ext.keyLvl) or 0,
                ilvl = tonumber(ext.ilvl) or 0,
                note = ext.note or "",
                isDungeon = ext.isDungeon == true or IsDungeonLFGText((ext.activity or "") .. " " .. (ext.note or ""), nil),
                updatedAt = ext.updatedAt or 0,
                isSelf = Compat.IsMe(ext.displayName or key),
            })
        elseif type(ext) == "table" and (now - (ext.updatedAt or 0)) > 1800 then
            self.externalLFG[key] = nil
        end
    end

    for key, off in pairs(self.officialLfgCache or {}) do
        if type(off) == "table" and (now - (off.updatedAt or 0)) <= 900 then
            if seen[key] then
                for _, existing in ipairs(out) do
                    if existing.lookupKey == key then
                        existing.isOfficial = true
                        existing.filledT = existing.filledT or off.filledT
                        existing.filledH = existing.filledH or off.filledH
                        existing.filledD = existing.filledD or off.filledD
                        existing.filledNoRole = existing.filledNoRole or off.filledNoRole
                        existing.needT = existing.needT or off.needT
                        existing.needH = existing.needH or off.needH
                        existing.needD = existing.needD or off.needD
                        existing.numMembers = existing.numMembers or off.numMembers
                        existing.maxMembers = existing.maxMembers or off.maxMembers
                        existing.activityIds = existing.activityIds or off.activityIds
                        existing.categoryKind = existing.categoryKind or off.categoryKind
                        break
                    end
                end
            else
                local live = liveByLookup[key]
                seen[key] = true
                PushItem({
                    sourceType = "OFFICIAL_LFG",
                    lookupKey = key,
                    guid = (live and live.guid) or off.guid,
                    displayName = (live and live.displayName) or off.displayName or key,
                    classFile = (live and live.classFile) or off.classFile,
                    level = (live and live.level) or off.level,
                    area = (live and live.area) or "",
                    guild = (off.guild and off.guild ~= "" and off.guild) or (live and live.guild),
                    online = true,
                    mode = off.mode or "LFM",
                    role = off.role or "ANY",
                    filledT = off.filledT,
                    filledH = off.filledH,
                    filledD = off.filledD,
                    filledNoRole = off.filledNoRole,
                    needT = off.needT,
                    needH = off.needH,
                    needD = off.needD,
                    numMembers = off.numMembers,
                    maxMembers = off.maxMembers,
                    activity = off.activity or L["Dungeon"],
                    activityAllNames = off.activityAllNames,
                    activityIds = off.activityIds,
                    categoryKind = off.categoryKind or "DUNGEONS",
                    minActLvl = off.minActLvl,
                    maxActLvl = off.maxActLvl,
                    keyLvl = tonumber(off.keyLvl) or 0,
                    ilvl = tonumber(off.ilvl) or 0,
                    note = off.note or "",
                    isDungeon = off.isDungeon ~= false,
                    isOfficial = true,
                    updatedAt = off.updatedAt or 0,
                    isSelf = Compat.IsMe(off.displayName or key),
                })
            end
        elseif type(off) == "table" and (now - (off.updatedAt or 0)) > 900 then
            self.officialLfgCache[key] = nil
        end
    end

    local s = ns.db and ns.db.settings
    if (not s or s.globalChatLfgScan ~= false)
        and (filterMode == "ALL" or filterMode == "PUBLIC_CHAT" or filterMode == "SC_USERS") then
        self.globalChatLFG = self.globalChatLFG or {}
        for key, pub in pairs(self.globalChatLFG) do
            if type(pub) == "table" and (now - (pub.updatedAt or 0)) <= 600 then
                if not seen[key] then
                    seen[key] = true
                    local live = liveByLookup[key]
                    PushItem({
                        sourceType = "PUBLIC_CHAT",
                        lookupKey = key,
                        guid = (live and live.guid) or pub.guid,
                        displayName = (live and live.displayName) or pub.displayName or key,
                        classFile = (live and live.classFile) or pub.classFile,
                        level = live and live.level,
                        area = live and live.area or pub.channel or "",
                        guild = (live and live.guild) or pub.guild,
                        online = true,
                        mode = pub.mode or "LFM",
                        role = pub.role or "ANY",
                        activity = pub.activity or L["Global Chat LFG"],
                        keyLvl = 0,
                        ilvl = 0,
                        note = pub.note or "",
                        isDungeon = pub.isDungeon == true or IsDungeonLFGText(pub.note or "", nil),
                        updatedAt = pub.updatedAt or 0,
                        isSelf = Compat.IsMe(pub.displayName or key, pub.guid),
                    })
                end
            elseif type(pub) == "table" and (now - (pub.updatedAt or 0)) > 600 then
                self.globalChatLFG[key] = nil
            end
        end
    end

    table.sort(out, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        if a.online ~= b.online then return a.online end
        local aTrusted = (a.isClan or a.isAllied or a.isFriend or a.isWatchlist or a.hasFriendOrWatchlistSignup) and 1 or 0
        local bTrusted = (b.isClan or b.isAllied or b.isFriend or b.isWatchlist or b.hasFriendOrWatchlistSignup) and 1 or 0
        if aTrusted ~= bTrusted then return aTrusted > bTrusted end
        local aRel = (a.isFriend or a.isWatchlist or a.hasFriendOrWatchlistSignup) and 1 or 0
        local bRel = (b.isFriend or b.isWatchlist or b.hasFriendOrWatchlistSignup) and 1 or 0
        if aRel ~= bRel then return aRel > bRel end
        if a.isClan ~= b.isClan then return a.isClan end
        local aBonus = (a.hasAddon and 2 or 0) + (a.isCompanion and 1 or 0)
        local bBonus = (b.hasAddon and 2 or 0) + (b.isCompanion and 1 or 0)
        if aBonus ~= bBonus then return aBonus > bBonus end
        return (a.updatedAt or 0) > (b.updatedAt or 0)
    end)
    return out
end

local trustedBdSeen = {}
local trustedBdResult = { total = 0, clan = 0, ally = 0, friends = 0, sc = 0 }
local trustedBdAt = 0

function Clan:GetTrustedLFGBreakdown()
    local nowClock = GetTime and GetTime() or 0
    if (nowClock - trustedBdAt) < 1.0 then
        return trustedBdResult
    end
    trustedBdAt = nowClock
    wipe(trustedBdSeen)
    local total, clanCnt, allyCnt, friendsCnt, scCnt = 0, 0, 0, 0, 0
    local list = self:GetClanLFGList(nil, false, "ALL")
    for i = 1, #list do
        local it = list[i]
        if type(it) == "table" and not it.isSelf then
            local isTrusted = it.isClan or it.isAllied or it.isFriend or it.isWatchlist or it.hasFriendOrWatchlistSignup or it.isCompanion
            if isTrusted or it.hasAddon then
                local uid = it.eventId or it.lookupKey or it.displayName or i
                if not trustedBdSeen[uid] then
                    trustedBdSeen[uid] = true
                    total = total + 1
                    if it.isClan then clanCnt = clanCnt + 1 end
                    if it.isAllied then allyCnt = allyCnt + 1 end
                    if it.isFriend or it.isWatchlist or it.hasFriendOrWatchlistSignup then
                        friendsCnt = friendsCnt + 1
                    end
                    if it.hasAddon then scCnt = scCnt + 1 end
                end
            end
        end
    end
    trustedBdResult.total = total
    trustedBdResult.clan = clanCnt
    trustedBdResult.ally = allyCnt
    trustedBdResult.friends = friendsCnt
    trustedBdResult.sc = scCnt
    return trustedBdResult
end

function Clan:GetGuildPresentClasses()
    local classes = {}
    local seen = {}
    if Store and type(Store.guildRosterRanks) == "table" then
        for _, rec in pairs(Store.guildRosterRanks) do
            if type(rec) == "table" and rec.classFile and rec.classFile ~= "" and not seen[rec.classFile] then
                seen[rec.classFile] = true
                local locName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[rec.classFile]) or rec.classFile
                classes[#classes + 1] = { id = rec.classFile, label = locName }
            end
        end
    end
    table.sort(classes, function(a, b) return (a.label or "") < (b.label or "") end)
    return classes
end

local mergedRowPool = {}
local mergedSeenBuf = {}

function Clan:GetGuildRosterQuickStats(outClassCounts)
    local bucket = Store:GetClanScopeData()
    local socialByLookup = Store and Store.socialByLookup
    local scUsers, onlineTotal, totalCount = 0, 0, 0
    if outClassCounts then
        wipe(outClassCounts)
    end
    wipe(mergedSeenBuf)
    if Store and type(Store.guildRosterRanks) == "table" then
        for key, rec in pairs(Store.guildRosterRanks) do
            if type(rec) == "table" and rec.displayName then
                mergedSeenBuf[key] = true
                totalCount = totalCount + 1
                local live = GetLiveGuildRowFromMap(socialByLookup, key)
                local peer = bucket.peers and bucket.peers[key]
                local isOnline = (live and live.online == true) or (rec.online == true)
                local hasAddon = (rec.isSelf == true) or (peer ~= nil) or (ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(key))
                if hasAddon then scUsers = scUsers + 1 end
                if isOnline then
                    onlineTotal = onlineTotal + 1
                    local cf = (live and live.classFile) or rec.classFile
                    if outClassCounts and cf and cf ~= "" then
                        outClassCounts[cf] = (outClassCounts[cf] or 0) + 1
                    end
                end
            end
        end
    end
    if type(Store.social) == "table" then
        for _, live in pairs(Store.social) do
            if type(live) == "table" and live.sources and live.sources.guild == true and live.lookupKey and not mergedSeenBuf[live.lookupKey] then
                mergedSeenBuf[live.lookupKey] = true
                totalCount = totalCount + 1
                onlineTotal = onlineTotal + 1
                local peer = bucket.peers and bucket.peers[live.lookupKey]
                if (peer ~= nil) or (ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(live.lookupKey)) then
                    scUsers = scUsers + 1
                end
                if outClassCounts and live.classFile and live.classFile ~= "" then
                    outClassCounts[live.classFile] = (outClassCounts[live.classFile] or 0) + 1
                end
            end
        end
    end
    for key in pairs(bucket.peers or {}) do
        if not mergedSeenBuf[key] then
            totalCount = totalCount + 1
            scUsers = scUsers + 1
        end
    end
    return scUsers, onlineTotal, totalCount
end

function Clan:GetMergedGuildMembers(query, opts)
    local bucket = Store:GetClanScopeData()
    local q = (type(query) == "string" and query ~= "") and query:lower() or nil
    opts = type(opts) == "table" and opts or {}
    local statusFilter = opts.statusFilter or "all"
    local rankFilter = opts.rankFilter
    if rankFilter == "all" or rankFilter == "" then rankFilter = nil end
    local classFilter = opts.classFilter
    if classFilter == "all" or classFilter == "" then classFilter = nil end
    local sortBy = opts.sortBy or "level_desc"

    local out = {}
    local seen = mergedSeenBuf
    wipe(seen)
    local poolIdx = 0
    local nowTs = time()
    local socialByLookup = GetGuildSocialLookupMap()

    local function AcquirePooledRow()
        poolIdx = poolIdx + 1
        local r = mergedRowPool[poolIdx]
        if not r then
            r = {}
            mergedRowPool[poolIdx] = r
        end
        return r
    end

    local function RowMatches(row)
        if statusFilter == "online" and not row.online then
            return false
        elseif statusFilter == "offline" and row.online then
            return false
        elseif statusFilter == "sc" and not row.hasAddon then
            return false
        elseif statusFilter == "lfg" and (not row.tag or row.tag == "NONE") then
            return false
        elseif statusFilter == "inactive30" and (row.online or (row.offlineDays or 0) < 30) then
            return false
        elseif statusFilter == "inactive60" and (row.online or (row.offlineDays or 0) < 60) then
            return false
        elseif statusFilter == "inactive90" and (row.online or (row.offlineDays or 0) < 90) then
            return false
        end
        if rankFilter ~= nil and row.rankIndex ~= rankFilter then
            return false
        end
        if classFilter ~= nil and row.classFile ~= classFilter then
            return false
        end
        if not q then
            return true
        end
        local clsLoc = (row.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[row.classFile]) or row.classFile or ""
        local hay = ((row.displayName or "") .. " " .. (row.rankName or "") .. " " .. clsLoc .. " " .. (row.area or "") .. " " .. (row.note or "") .. " " .. (row.tag or "")):lower()
        return hay:find(q, 1, true) ~= nil
    end

    if Store and type(Store.guildRosterRanks) == "table" then
        for key, rec in pairs(Store.guildRosterRanks) do
            if type(rec) == "table" and rec.displayName then
                local live = GetLiveGuildRowFromMap(socialByLookup, key)
                local peer = bucket.peers and bucket.peers[key]
                local isOnline = (live and live.online == true) or (rec.online == true)
                local isMe = rec.isSelf == true
                local resolvedTag = (isMe and bucket.myTag) or (peer and peer.tag) or "NONE"
                local resolvedNote = (isMe and bucket.myNote and bucket.myNote ~= "" and bucket.myNote)
                    or (peer and peer.note and peer.note ~= "" and peer.note)
                    or (live and live.note and live.note ~= "" and live.note)
                    or rec.note or ""
                local row = AcquirePooledRow()
                row.lookupKey = key
                row.displayName = (live and live.displayName) or rec.displayName
                row.version = isMe and ns.version or (peer and peer.version or nil)
                row.tag = IsValidTag(resolvedTag) and resolvedTag or "NONE"
                row.note = resolvedNote
                row.rankName = (live and live.rankName and live.rankName ~= "" and live.rankName) or rec.rankName or ""
                row.rankIndex = (live and live.rankIndex ~= nil) and live.rankIndex or rec.rankIndex
                row.guid = (live and live.guid) or rec.guid
                row.rosterIndex = rec.rosterIndex
                row.level = (live and live.level and live.level > 0 and live.level) or rec.level or 0
                row.classFile = (live and live.classFile) or rec.classFile
                row.area = (live and live.area and live.area ~= "" and live.area) or rec.area or ""
                row.online = isOnline
                row.offlineDays = rec.offlineDays or 0
                row.isSelf = isMe
                row.hasAddon = isMe or (peer ~= nil) or (ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(key))
                row.updatedAt = (peer and peer.updatedAt) or (isOnline and nowTs or 0)
                seen[key] = true
                if RowMatches(row) then
                    out[#out + 1] = row
                else
                    poolIdx = poolIdx - 1
                end
            end
        end
    end

    if type(Store.social) == "table" then
        for _, live in pairs(Store.social) do
            if type(live) == "table" and live.sources and live.sources.guild == true and live.lookupKey and not seen[live.lookupKey] then
                local peer = bucket.peers and bucket.peers[live.lookupKey]
                local row = AcquirePooledRow()
                row.lookupKey = live.lookupKey
                row.displayName = live.displayName
                row.version = peer and peer.version or nil
                row.tag = peer and IsValidTag(peer.tag) and peer.tag or "NONE"
                row.note = (peer and peer.note and peer.note ~= "" and peer.note) or live.note or ""
                row.rankName = live.rankName or ""
                row.rankIndex = live.rankIndex
                row.guid = live.guid
                row.rosterIndex = nil
                row.level = live.level or 0
                row.classFile = live.classFile
                row.area = live.area or ""
                row.online = true
                row.offlineDays = 0
                row.isSelf = false
                row.hasAddon = (peer ~= nil) or (ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(live.lookupKey))
                row.updatedAt = (peer and peer.updatedAt) or nowTs
                seen[live.lookupKey] = true
                if RowMatches(row) then
                    out[#out + 1] = row
                else
                    poolIdx = poolIdx - 1
                end
            end
        end
    end

    for key, peer in pairs(bucket.peers or {}) do
        if not seen[key] then
            local row = AcquirePooledRow()
            row.lookupKey = key
            row.displayName = peer.displayName or key
            row.version = peer.version
            row.tag = IsValidTag(peer.tag) and peer.tag or "NONE"
            row.note = peer.note or ""
            row.rankName = ""
            row.rankIndex = nil
            row.guid = nil
            row.rosterIndex = nil
            row.level = 0
            row.classFile = peer.classFile
            row.area = ""
            row.online = false
            row.offlineDays = 0
            row.isSelf = false
            row.hasAddon = true
            row.updatedAt = peer.updatedAt or 0
            if RowMatches(row) then
                out[#out + 1] = row
            else
                poolIdx = poolIdx - 1
            end
        end
    end

    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if sortBy == "rank" then
            local ra, rb = a.rankIndex or 99, b.rankIndex or 99
            if ra ~= rb then return ra < rb end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        elseif sortBy == "name" then
            if (a.displayName or "") ~= (b.displayName or "") then
                return (a.displayName or "") < (b.displayName or "")
            end
        elseif sortBy == "zone" then
            local za, zb = a.area or "", b.area or ""
            if za ~= zb then return za < zb end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        else -- "level_desc" (default: Online first, then Level high -> low, then Rank)
            local la, lb = tonumber(a.level) or 0, tonumber(b.level) or 0
            if la ~= lb then return la > lb end
            local ra, rb = a.rankIndex or 99, b.rankIndex or 99
            if ra ~= rb then return ra < rb end
        end
        return (a.displayName or "") < (b.displayName or "")
    end)
    return out
end

function Clan:GetGuildChatLFGList()
    local now = time()
    local out = {}
    for i = #self.guildChatLFG, 1, -1 do
        local row = self.guildChatLFG[i]
        if (now - (row.timestamp or 0)) > 900 then
            table.remove(self.guildChatLFG, i)
        else
            table.insert(out, row)
        end
    end
    return out
end

function Clan:HasGuildChatLFG(lookupKey)
    if not lookupKey or lookupKey == "" or type(self.guildChatLFG) ~= "table" then
        return false
    end
    local now = time()
    for i = #self.guildChatLFG, 1, -1 do
        local row = self.guildChatLFG[i]
        if type(row) ~= "table" or (now - (row.timestamp or 0)) > 900 then
            table.remove(self.guildChatLFG, i)
        elseif row.lookupKey == lookupKey then
            return true
        end
    end
    return false
end

function Clan:GetClanBadgeLFGCount()
    local bucket = Store:GetClanScopeData()
    local now = time()
    local count = 0
    local seen = {}
    for key in pairs(bucket.lfg or {}) do
        seen[key] = true
        count = count + 1
    end
    for _, evt in pairs(bucket.events or {}) do
        if type(evt) == "table" and evt.isOpen ~= false then
            count = count + 1
        end
    end
    for key, peer in pairs(bucket.peers or {}) do
        if not seen[key] and type(peer) == "table" and (peer.tag == "LFG" or peer.tag == "MPLUS") then
            seen[key] = true
            count = count + 1
        end
    end
    for i = #self.guildChatLFG, 1, -1 do
        local row = self.guildChatLFG[i]
        if (now - (row.timestamp or 0)) > 900 then
            table.remove(self.guildChatLFG, i)
        elseif row.lookupKey and not seen[row.lookupKey] then
            seen[row.lookupKey] = true
            count = count + 1
        end
    end
    for key, ext in pairs(self.externalLFG or {}) do
        if type(ext) == "table" then
            if (now - (ext.updatedAt or 0)) > 1800 then
                self.externalLFG[key] = nil
            elseif not seen[key] then
                count = count + 1
            end
        end
    end
    return count
end

function Clan:GetSignupSummary(evt)
    local counts = { TANK = 0, HEALER = 0, DPS = 0, MAYBE = 0 }
    local signups = {}
    if evt and type(evt.signups) == "table" then
        for key, s in pairs(evt.signups) do
            if type(s) == "table" and counts[s.role] ~= nil then
                counts[s.role] = counts[s.role] + 1
                table.insert(signups, {
                    key = key,
                    name = s.name or key,
                    classFile = s.classFile,
                    role = s.role,
                })
            end
        end
    end
    table.sort(signups, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    counts.signups = signups
    return counts
end

local function BuildPeerDigestSuffix(baseLen)
    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local peers = bucket and bucket.peers
    if type(peers) ~= "table" then return "" end

    local now = time()
    local cutoff = now - (14 * 86400)
    local items = {}
    for k, rec in pairs(peers) do
        if type(k) == "string" and k ~= "" and not k:find("[%s:~|,]") and type(rec) == "table" then
            local ver = Safe.String(rec.version)
            local ts = tonumber(rec.updatedAt) or 0
            if ver and ver ~= "" and IsSaneRemoteSemVer(ver) and ts >= cutoff and Store and Store.guildRosterRanks and Store.guildRosterRanks[k] ~= nil then
                items[#items + 1] = { key = k, ver = ver, ts = ts }
            end
        end
    end
    if #items == 0 then return "" end
    if #items > 1 then
        table.sort(items, function(a, b) return a.ts > b.ts end)
    end

    local parts = {}
    local curLen = (baseLen or 12) + 1
    local count = 0
    for i = 1, math.min(8, #items) do
        local entry = items[i].key .. ":" .. items[i].ver
        local addLen = #entry + (count > 0 and 1 or 0)
        if (curLen + addLen) > 235 then
            break
        end
        parts[#parts + 1] = entry
        curLen = curLen + addLen
        count = count + 1
    end
    if count == 0 then return "" end
    return "~" .. table.concat(parts, ",")
end

local function ProcessGuildPeerDigest(digestStr, senderLookupKey)
    if type(digestStr) ~= "string" or digestStr == "" or not senderLookupKey then return end
    if not (Compat.IsInGuild and Compat.IsInGuild()) then return end
    if not IsSenderConfirmedInGuild(senderLookupKey) then return end

    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    if not bucket then return end
    bucket.peers = bucket.peers or {}

    local now = time()
    local gossipStamp = now - 600
    local processed = 0
    local myFull = (Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName()) or Compat.GetPlayerName()
    local myKey = (Compat.ParseCharacterFields and myFull) and select(1, Compat.ParseCharacterFields(myFull)) or nil

    for token in digestStr:gmatch("([^,]+)") do
        processed = processed + 1
        if processed > 10 then break end
        local lk, ver = token:match("^([^:%s~|,]+):([%d]+%.[%d]+%.[%d]+)$")
        if lk and lk ~= "" and lk ~= myKey and not Compat.IsMe(lk) and ver and IsSaneRemoteSemVer(ver) then
            local rosterRec = Store and Store.guildRosterRanks and Store.guildRosterRanks[lk]
            local inGuild = (rosterRec ~= nil) or (Compat.IsGuildMember and Compat.IsGuildMember(lk, nil, lk))
            if inGuild then
                local existing = bucket.peers[lk]
                local sr = Store and Store.socialByLookup and Store.socialByLookup[lk]
                local dispName = (rosterRec and type(rosterRec.displayName) == "string" and rosterRec.displayName ~= "" and rosterRec.displayName)
                    or (existing and type(existing.name) == "string" and existing.name ~= "" and existing.name)
                    or (sr and sr.name)
                    or lk
                if not Compat.IsMe(dispName) then
                    if type(existing) ~= "table" then
                        bucket.peers[lk] = {
                            name = dispName,
                            version = ver,
                            updatedAt = gossipStamp,
                        }
                    elseif (tonumber(existing.updatedAt) or 0) < gossipStamp then
                        existing.version = ver
                        existing.updatedAt = gossipStamp
                        if dispName ~= lk then existing.name = dispName end
                    end
                    if ns.Chat and ns.Chat.RecordPassiveSavedPeer then
                        ns.Chat:RecordPassiveSavedPeer(lk, dispName, ver, gossipStamp)
                    end
                end
            end
        end
    end
end

local function OnAddonMessage(_, _, prefix, text, chatType, sender)
    if prefix ~= Clan.PREFIX then return end
    if chatType ~= "GUILD" and chatType ~= "PARTY" and chatType ~= "RAID" and chatType ~= "INSTANCE_CHAT" and chatType ~= "WHISPER" then
        return
    end

    local cleanText = Safe.String(text)
    local cleanSender = Safe.String(sender)
    if not cleanText or not cleanSender or cleanText:find("%c") or cleanText:find("|", 1, true) then
        return
    end
    if Compat.IsMe(cleanSender) then return end

    local parsed = Compat.ParseCharacterName(cleanSender)
    if not parsed then return end

    local parts = SplitTilde(cleanText)
    local cmd = parts[1]

    -- Version discovery packets (allowed for PARTY/RAID/INSTANCE_CHAT/GUILD when versionCheck ~= false)
    if cmd == "VH" or cmd == "VR" then
        if chatType == "WHISPER" then return end
        if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then return end
        local remoteVer = parts[2]
        ProcessPeerVersion(parsed.displayName, parsed.lookupKey, remoteVer, chatType)
        if cmd == "VR" and chatType == "GUILD" and parts[3] and parts[3] ~= "" then
            ProcessGuildPeerDigest(parts[3], parsed.lookupKey)
        end

        if cmd == "VH" and IsSaneRemoteSemVer(ns.version) and IsSaneRemoteSemVer(remoteVer) and Compat.CompareSemVer(ns.version, remoteVer) >= 0 then
            local delay = 1.5 + math.random() * 2.5
            local targetChannel = chatType
            if targetChannel == "GUILD" and GetNumGuildMembers then
                local okCount, _, online = pcall(GetNumGuildMembers)
                local onlineCount = (okCount and Safe.Number(online)) or 1
                local chances = math.max(1, math.ceil(onlineCount / 40))
                if math.random(1, chances) ~= 1 then
                    return
                end
            end
            C_Timer.After(delay, function()
                local baseMsg = "VR~" .. ns.version
                local msg = baseMsg .. ((targetChannel == "GUILD") and BuildPeerDigestSuffix(#baseMsg) or "")
                TransmitAddonMessage(Clan, msg, targetChannel, true)
            end)
        end
        if chatType == "GUILD" then QueueClanEmit(0.8) end
        return
    end

    -- Legacy PING support
    if cmd and cmd:find("^PING:") then
        if chatType ~= "GUILD" or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return end
        local ver = cmd:match("^PING:(.*)$")
        ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, chatType)
        QueueClanEmit(0.8)
        return
    end

    -- Group hourly instance cap synchronization
    if cmd == "ICAP" then
        if (chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT") and (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            if ns.Group and ns.Group.ReceiveMemberInstanceCap then
                ns.Group:ReceiveMemberInstanceCap(parsed.lookupKey, tonumber(parts[2]) or 0, tonumber(parts[3]) or 5)
            end
        end
        return
    end

    -- External Allied / Friend LFG catchup query
    if cmd == "ALFGR" then
        if chatType ~= "WHISPER" or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            return
        end
        if ns.Chat and ns.Chat.MarkPeerVerified then
            ns.Chat:MarkPeerVerified(parsed.displayName, nil, parts[2], "WHISPER")
        end
        if IsSaneRemoteSemVer(parts[2]) then
            ProcessPeerVersion(parsed.displayName, parsed.lookupKey, parts[2], "WHISPER")
        end
        local monoNow = GetTime and GetTime() or 0
        if (monoNow - (Clan.lastAlfgCatchupReplyAt or 0)) < 10 then
            return
        end
        local bucketNow = Store and Store.GetClanScopeData and Store:GetClanScopeData()
        local myDispNow, myKeyNow = ResolveSelfIdentity()
        local myLfgNow = bucketNow and bucketNow.lfg and myKeyNow and bucketNow.lfg[myKeyNow]
        if type(myLfgNow) == "table" and (time() - (myLfgNow.updatedAt or 0)) <= 1800 and C_Timer and C_Timer.After then
            Clan.lastAlfgCatchupReplyAt = monoNow
            local replyTarget = (Compat.FormatForeverTarget and Compat.FormatForeverTarget(parsed.displayName)) or parsed.displayName
            local myGuildNow = Compat.CleanPayloadField((Store.guildInfo and Store.guildInfo.name) or Safe.String(Safe.Call(GetGuildInfo, "player")) or "", 24)
            local extPayload = ("ALFG~%s~%s~%s~%s~%s~%s~%d~%d~%s"):format(
                ns.version or "0.0.0",
                Compat.CleanPayloadField(myDispNow or myLfgNow.displayName or "", 26),
                myGuildNow,
                myLfgNow.mode or "LFG",
                myLfgNow.role or "ANY",
                Compat.CleanPayloadField(myLfgNow.activity or "", 30),
                tonumber(myLfgNow.keyLvl) or 0,
                tonumber(myLfgNow.ilvl) or 0,
                Compat.CleanPayloadField(myLfgNow.note or "", 30)
            )
            C_Timer.After(0.8 + math.random() * 1.2, function()
                SendExternalLFGPacket(Clan, extPayload, "WHISPER", replyTarget)
            end)
        end
        return
    end

    -- Cross-guild Allied / Friend / Group LFG exchange (strictly opt-in via clanSync)
    if cmd == "ALFG" or cmd == "ALFX" then
        if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            return
        end
        if chatType == "WHISPER" and ns.Chat and ns.Chat.MarkPeerVerified then
            ns.Chat:MarkPeerVerified(parsed.displayName, nil, nil, chatType)
        end
        Clan.externalLFG = Clan.externalLFG or {}

        if cmd == "ALFX" then
            local originParsed = Compat.ParseCharacterName(parts[2] ~= "" and parts[2] or parsed.displayName)
            if originParsed and not Compat.IsMe(originParsed.displayName) then
                Clan.externalLFG[originParsed.lookupKey] = nil
                QueueClanEmit(0.5)
            end
            return
        end

        local ver = parts[2]
        local originRaw = Compat.CleanPayloadField(parts[3] or "", 30)
        local originGuild = Compat.CleanPayloadField(parts[4] or "", 28)
        local mode = (parts[5] == "LFM") and "LFM" or "LFG"
        local role = (parts[6] == "TANK" or parts[6] == "HEALER" or parts[6] == "DPS" or parts[6] == "ANY") and parts[6] or "ANY"
        local activity = Compat.CleanPayloadField(parts[7] or "", 40)
        local keyLvl = math.max(0, math.min(99, tonumber(parts[8]) or 0))
        local iLvl = math.max(0, math.min(2000, tonumber(parts[9]) or 0))
        local note = Compat.CleanPayloadField(parts[10] or "", 40)

        local originParsed = Compat.ParseCharacterName(originRaw ~= "" and originRaw or parsed.displayName)
        if not originParsed or Compat.IsMe(originParsed.displayName) then
            return
        end
        if IsSaneRemoteSemVer(ver) and chatType == "WHISPER" then
            ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, "WHISPER")
        end

        local _, isAllied, isFriend, isWatchlist, resolvedGuild = Clan:GetPlayerRelationshipFlags(
            originParsed.lookupKey,
            originParsed.displayName,
            nil,
            originGuild
        )
        local finalGuild = (originGuild ~= "" and originGuild) or resolvedGuild
        local sig = mode .. "|" .. role .. "|" .. activity .. "|" .. keyLvl .. "|" .. note
        local existing = Clan.externalLFG[originParsed.lookupKey]
        local alreadyRelayed = existing and existing._sig == sig and (time() - (existing.updatedAt or 0)) < 60

        local extNow = time()
        Clan.externalLFG[originParsed.lookupKey] = {
            sourceType = "ALLY_LFG",
            lookupKey = originParsed.lookupKey,
            displayName = originParsed.displayName,
            guild = finalGuild,
            mode = mode,
            role = role,
            activity = activity ~= "" and activity or L["Dungeon"],
            keyLvl = keyLvl,
            ilvl = iLvl,
            note = note,
            isDungeon = IsDungeonLFGText(activity .. " " .. note, keyLvl > 0 and "DUNGEON" or nil),
            isFriend = isFriend,
            isWatchlist = isWatchlist,
            updatedAt = extNow,
            _sig = sig,
        }

        PruneAndBoundByTimestamp(Clan.externalLFG, Clan.MAX_EXTERNAL_LFG or 40, 1800, extNow)

        if chatType == "GUILD" then
            Clan._heardGuildAlfgSig = Clan._heardGuildAlfgSig or {}
            Clan._heardGuildAlfgSig[sig] = GetTime and GetTime() or extNow
        elseif chatType == "WHISPER" and isAllied and not alreadyRelayed and IsInGuild and IsInGuild() and (GetTime() - (Clan.lastAlfgRelayAt or 0)) >= 15 then
            Clan.lastAlfgRelayAt = GetTime()
            local relayPayload = cleanText
            local relaySig = sig
            local relayDelay = 1.0 + math.random() * 1.5
            C_Timer.After(relayDelay, function()
                if Clan._heardGuildAlfgSig and ((GetTime and GetTime() or 0) - (Clan._heardGuildAlfgSig[relaySig] or 0)) < 30 then
                    return
                end
                if not Clan:IsMessagingLocked() then
                    Clan:SendGuildSync(relayPayload)
                end
            end)
        end
        if not alreadyRelayed then
            local compRec = Store and Store.GetRecentCompanion and Store:GetRecentCompanion(originParsed.lookupKey)
            local srcBadge = (isFriend or isWatchlist) and L["Friends"]
                or (isAllied and L["Allied Clans"]
                or (compRec and L["PARTNER"] or L["Clan LFG"]))
            local summary = ("%s [%s] %s%s"):format(
                mode,
                role,
                keyLvl > 0 and ("+" .. keyLvl .. " ") or "",
                activity ~= "" and activity or L["Dungeon"]
            )
            Clan:MaybeNotifyClanLFG(
                originParsed.lookupKey,
                originParsed.displayName,
                nil,
                summary,
                activity,
                Clan.externalLFG[originParsed.lookupKey].isDungeon or mode == "LFG" or mode == "LFM",
                "ALLY_LFG",
                nil,
                srcBadge
            )
        end
        QueueClanEmit(0.6)
        return
    end

    if cmd == "ALM" then
        if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            return
        end
        if not Clan:IsMemberAllianceAuthorized() then
            return
        end
        local senderGuild = Compat.CleanPayloadField(parts[2] or "", 32)
        local authorName = Compat.CleanPayloadField(parts[3] or "", 36)
        local classFile = parts[4]
        local msgText = Compat.CleanPayloadField(parts[5] or "", 140)
        local msgId = Compat.CleanPayloadField(parts[6] or "", 24)
        if authorName == "" or msgText == "" or Compat.IsMe(authorName) then
            return
        end
        if chatType == "GUILD" then
            if not IsSenderConfirmedInGuild(parsed.lookupKey) then
                return
            end
        elseif senderGuild == "" or not Clan:IsAlliedGuild(senderGuild) then
            return
        end

        local monoNow = GetTime and GetTime() or time()
        Clan.seenAllianceRelay = Clan.seenAllianceRelay or {}
        for k, seenAt in pairs(Clan.seenAllianceRelay) do
            if (monoNow - (seenAt or 0)) > 120 then
                Clan.seenAllianceRelay[k] = nil
            end
        end
        local dedupeKey = (msgId ~= "") and msgId or (senderGuild .. "|" .. authorName .. "|" .. msgText:sub(1, 32))
        if Clan.seenAllianceRelay[dedupeKey] then
            return
        end
        Clan.seenAllianceRelay[dedupeKey] = monoNow
        if chatType == "GUILD" then
            Clan._heardGuildAlmKey = Clan._heardGuildAlmKey or {}
            Clan._heardGuildAlmKey[dedupeKey] = monoNow
        end

        if ns.Chat and ns.Chat.MarkPeerVerified then
            ns.Chat:MarkPeerVerified(parsed.displayName, nil, nil, "ALM")
            if authorName ~= "" then
                ns.Chat:MarkPeerVerified(authorName, nil, nil, "ALM")
            end
        end

        if ns.Chat and ns.Chat.ReceiveAllianceMessage then
            ns.Chat:ReceiveAllianceMessage(senderGuild, authorName, classFile, msgText, dedupeKey)
        end

        local myGuild = Safe.String(Safe.Call(GetGuildInfo, "player")) or ""
        if chatType == "WHISPER" and senderGuild ~= myGuild and IsInGuild and IsInGuild() and (monoNow - (Clan.lastAlmRelayAt or 0)) >= 10 then
            Clan.lastAlmRelayAt = monoNow
            local relayPayload = cleanText
            local relayKey = dedupeKey
            local relayDelay = 0.8 + math.random() * 1.4
            C_Timer.After(relayDelay, function()
                if Clan._heardGuildAlmKey and Clan._heardGuildAlmKey[relayKey] then
                    return
                end
                if not Clan:IsMessagingLocked() then
                    Clan:SendGuildSync(relayPayload)
                end
            end)
        end
        return
    end

    -- All Clan Hub interactive features require explicit clanSync opt-in (and GUILD, except Allied event whispers).
    local isWhisperEventCmd = (chatType == "WHISPER") and (cmd == "EVT" or cmd == "EVS" or cmd == "DEL" or cmd == "SIG")
    if (not (ns.db and ns.db.settings and ns.db.settings.clanSync)) or (chatType ~= "GUILD" and not isWhisperEventCmd) then
        return
    end

    local bucket = Store:GetClanScopeData()
    local now = time()

    if chatType == "GUILD" then
        local resolvedDisplay, resolvedLookup = ResolveForeverGuildSender(parsed.displayName, parsed.lookupKey)
        parsed.displayName = resolvedDisplay or parsed.displayName
        parsed.lookupKey = resolvedLookup or parsed.lookupKey
    end

    if ns.Chat and ns.Chat.MarkPeerVerified then
        ns.Chat:MarkPeerVerified(parsed.displayName, nil, nil, chatType)
    end

    if cmd == "TAG" or cmd == "REQ" then
        local ver, tagId, note = parts[2], parts[3], Compat.CleanPayloadField(parts[4] or "", 36)
        local peer = bucket.peers[parsed.lookupKey] or {}
        peer.displayName = parsed.displayName
        peer.lookupKey = parsed.lookupKey
        if IsSaneRemoteSemVer(ver) then
            peer.version = ver
            ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, "GUILD")
        end
        peer.tag = IsValidTag(tagId) and tagId or "NONE"
        peer.note = note
        if parts[5] and IsValidProfession(parts[5]) then peer.prof1 = parts[5] end
        if parts[6] and IsValidProfession(parts[6]) then peer.prof2 = parts[6] end
        if parts[7] ~= nil then peer.craftNote = Compat.CleanPayloadField(parts[7], 40) end
        peer.updatedAt = now
        bucket.peers[parsed.lookupKey] = peer
        if cmd == "TAG" and (peer.tag == "LFG" or peer.tag == "MPLUS") then
            local isDng = (peer.tag == "MPLUS") or IsDungeonLFGText(note, nil)
            Clan:MaybeNotifyClanLFG(parsed.lookupKey, parsed.displayName, peer.classFile, note ~= "" and note or (L[peer.tag] or peer.tag), peer.tag, isDng, "TAG")
        end
        QueueClanEmit(0.6)

        if cmd == "REQ" and (GetTime() - (Clan.lastReqReplyAt or 0)) >= 15 then
            Clan.lastReqReplyAt = GetTime()
            local replyDelay = 0.8 + math.random() * 2.2
            C_Timer.After(replyDelay, function()
                local b = Store:GetClanScopeData()
                local myTag = IsValidTag(b.myTag) and b.myTag or "NONE"
                local myNote = Compat.CleanPayloadField(b.myNote or "", 36)
                local p1 = IsValidProfession(b.myProf1) and b.myProf1 or "NONE"
                local p2 = IsValidProfession(b.myProf2) and b.myProf2 or "NONE"
                local cNote = Compat.CleanPayloadField(b.myCraftNote or "", 40)
                Clan:SendGuildSync(("TAG~%s~%s~%s~%s~%s~%s"):format(ns.version or "0.0.0", myTag, myNote, p1, p2, cNote))

                local _, selfKey = ResolveSelfIdentity()
                local myLfg = b and b.lfg and selfKey and b.lfg[selfKey]
                if type(myLfg) == "table" and (time() - (myLfg.updatedAt or 0)) <= 1800 and C_Timer and C_Timer.After then
                    local reqSentAt = GetTime and GetTime() or 0
                    C_Timer.After(5.5 + math.random() * 1.5, function()
                        if Clan.isStoppedThisSession or Clan:IsMessagingLocked() then return end
                        if not (ns.db and ns.db.settings and ns.db.settings.clanSync) or not (IsInGuild and IsInGuild()) then return end
                        local monoNow = GetTime and GetTime() or 0
                        if (monoNow - (Clan.lastSyncSentAt or 0)) < (Clan.MIN_SEND_INTERVAL or 5) then return end
                        local b2 = Store and Store.GetClanScopeData and Store:GetClanScopeData()
                        local _, curKey = ResolveSelfIdentity()
                        local lfg2 = b2 and b2.lfg and curKey and b2.lfg[curKey]
                        if type(lfg2) ~= "table" or (time() - (lfg2.updatedAt or 0)) > 1800 then return end
                        local heardAt = Clan._heardGuildLfgKey and Clan._heardGuildLfgKey[curKey]
                        if heardAt and heardAt >= reqSentAt then return end
                        local lfgPayload = ("LFG~%s~%s~%s~%s~%d~%d~%s"):format(
                            ns.version or "0.0.0",
                            lfg2.mode or "LFG",
                            lfg2.role or "ANY",
                            Compat.CleanPayloadField(lfg2.activity or "", 40),
                            tonumber(lfg2.keyLvl) or 0,
                            tonumber(lfg2.ilvl) or 0,
                            Compat.CleanPayloadField(lfg2.note or "", 44)
                        )
                        if Clan:SendGuildSync(lfgPayload) then
                            Clan._heardGuildLfgKey = Clan._heardGuildLfgKey or {}
                            Clan._heardGuildLfgKey[curKey] = GetTime and GetTime() or monoNow
                        end
                    end)
                end
            end)
        end

    elseif cmd == "LFG" then
        Clan._heardGuildLfgKey = Clan._heardGuildLfgKey or {}
        Clan._heardGuildLfgKey[parsed.lookupKey] = GetTime and GetTime() or now
        local ver, mode, role, activity = parts[2], parts[3], parts[4], Compat.CleanPayloadField(parts[5] or "", 40)
        local keyLvl = math.max(0, math.min(99, tonumber(parts[6]) or 0))
        local iLvl = math.max(0, math.min(2000, tonumber(parts[7]) or 0))
        local note = Compat.CleanPayloadField(parts[8] or "", 44)
        if IsSaneRemoteSemVer(ver) then
            ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, "GUILD")
        end
        bucket.lfg = bucket.lfg or {}
        local cleanMode = (mode == "LFM") and "LFM" or "LFG"
        local cleanRole = (role == "TANK" or role == "HEALER" or role == "DPS" or role == "ANY") and role or "ANY"
        local isDng = IsDungeonLFGText(activity .. " " .. note, keyLvl > 0 and "DUNGEON" or nil)
        bucket.lfg[parsed.lookupKey] = {
            lookupKey = parsed.lookupKey,
            displayName = parsed.displayName,
            mode = cleanMode,
            role = cleanRole,
            activity = activity ~= "" and activity or L["Dungeon"],
            keyLvl = keyLvl,
            ilvl = iLvl,
            note = note,
            isDungeon = isDng,
            updatedAt = now,
        }
        local summary = ("%s [%s] %s%s"):format(cleanMode, cleanRole, keyLvl > 0 and ("+" .. keyLvl .. " ") or "", activity)
        Clan:MaybeNotifyClanLFG(parsed.lookupKey, parsed.displayName, nil, summary, activity, isDng or cleanMode == "LFG" or cleanMode == "LFM", "LFG")
        QueueClanEmit(0.5)

    elseif cmd == "LFX" then
        if bucket.lfg then
            bucket.lfg[parsed.lookupKey] = nil
        end
        QueueClanEmit(0.5)

    elseif cmd == "EVT" then
        local isAlliedWhisper = false
        if chatType == "WHISPER" then
            local isClanW, isAlliedW = Clan:GetPlayerRelationshipFlags(parsed.lookupKey, parsed.displayName)
            if not isClanW and not isAlliedW then
                return
            end
            isAlliedWhisper = (isAlliedW == true)
        end
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local cat = parts[3]
        local title = Compat.CleanPayloadField(parts[4] or "", 40)
        local whenText = Compat.CleanPayloadField(parts[5] or "", 24)
        local nT = math.max(0, math.min(5, tonumber(parts[6]) or 0))
        local nH = math.max(0, math.min(10, tonumber(parts[7]) or 0))
        local nD = math.max(0, math.min(30, tonumber(parts[8]) or 0))
        local nMinLvl = math.max(0, math.min(100, tonumber(parts[9]) or 0))
        local isOpen = parts[10] ~= "0"
        if eventId ~= "" and IsValidCategory(cat) and title ~= "" then
            local existing = bucket.events[eventId]
            bucket.events[eventId] = {
                id = eventId,
                category = cat,
                title = title,
                whenText = whenText ~= "" and whenText or L["Now"],
                needT = nT,
                needH = nH,
                needD = nD,
                minLvl = nMinLvl,
                isOpen = isOpen,
                isAlliedEvent = isAlliedWhisper or (existing and existing.isAlliedEvent) or nil,
                creator = parsed.displayName,
                creatorKey = parsed.lookupKey,
                createdAt = existing and existing.createdAt or now,
                updatedAt = now,
                signups = existing and existing.signups or {},
            }
            if isOpen and not existing then
                local isDng = IsDungeonLFGText(title, cat)
                local srcOv = isAlliedWhisper and L["Allied Clans"] or nil
                local didLfg = Clan:MaybeNotifyClanLFG(parsed.lookupKey, parsed.displayName, nil, title .. " (" .. (whenText ~= "" and whenText or L["Now"]) .. ")", title, isDng, "EVT", nil, srcOv)
                local s = ns.db and ns.db.settings
                if not didLfg and s and s.clanEventAlertEnabled == true and not Compat.IsMe(parsed.displayName) then
                    local evtWhen = whenText ~= "" and whenText or L["Now"]
                    local openLink = "|Haddon:SCentral:clanevt:" .. eventId .. "|h|cff58a6ff[" .. L["Open"] .. "]|r|h"
                    ns:Print("%s", ("|cff58a6ff[%s]|r %s: %s (%s) %s"):format(L["Guild Event"], parsed.displayName, title, evtWhen, openLink))
                    if s.clanLfgAlertSound ~= false then
                        PlayClanAlertSound(Clan, SOUNDKIT and (SOUNDKIT.MAP_PING or 3175))
                    end
                    Clan:IncrementNotificationCount(1)
                    ns:Emit("ADDON_MESSAGE_NOTIFY", {
                        id = "clanevt:" .. eventId,
                        kind = "CLAN_EVENT",
                        sourceTag = L["Guild Event"],
                        sender = parsed.displayName,
                        text = title .. " (" .. evtWhen .. ")",
                        eventId = eventId,
                        ts = now,
                        priority = 1,
                    })
                end
            end
            QueueClanEmit(0.6)
        end

    elseif cmd == "EVS" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local evt = bucket.events[eventId]
        if evt then
            local canEvtMod = (evt.creatorKey == parsed.lookupKey)
            if not canEvtMod and chatType == "GUILD" then
                local pol = Clan:GetGuildHierarchyPolicy()
                canEvtMod = IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, pol.eventModMode, pol.eventModMaxRank)
            end
            if canEvtMod then
                evt.isOpen = parts[3] ~= "0"
                evt.updatedAt = now
                QueueClanEmit(0.6)
            end
        end

    elseif cmd == "PRF" then
        local p1, p2, cNote = parts[2], parts[3], Compat.CleanPayloadField(parts[4] or "", 40)
        local r1 = Compat.CleanPayloadField(parts[5] or "", 12)
        local r2 = Compat.CleanPayloadField(parts[6] or "", 12)
        local peer = bucket.peers[parsed.lookupKey] or {
            displayName = parsed.displayName,
            lookupKey = parsed.lookupKey,
            tag = "NONE",
            note = "",
        }
        peer.prof1 = IsValidProfession(p1) and p1 or "NONE"
        peer.prof2 = IsValidProfession(p2) and p2 or "NONE"
        peer.prof1Rank = r1
        peer.prof2Rank = r2
        peer.craftNote = cNote
        peer.updatedAt = now
        bucket.peers[parsed.lookupKey] = peer
        QueueClanEmit(0.8)

    elseif cmd == "SIG" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local role = parts[3]
        local classFile = Compat.CleanPayloadField(parts[4] or "", 16)
        local evt = (chatType == "WHISPER") and (bucket.events and bucket.events[eventId]) or EnsureEventRecord(bucket, eventId)
        if chatType == "WHISPER" and not evt then
            return
        end
        if chatType == "WHISPER" then
            local isClanW, isAlliedW = Clan:GetPlayerRelationshipFlags(parsed.lookupKey, parsed.displayName)
            if not isClanW and not isAlliedW and not evt.isAlliedEvent then
                return
            end
            evt.signups = evt.signups or {}
        end
        if evt and IsValidRole(role) then
            if role == "DECLINE" then
                evt.signups[parsed.lookupKey] = nil
            else
                evt.signups[parsed.lookupKey] = {
                    name = parsed.displayName,
                    classFile = classFile ~= "" and classFile or nil,
                    role = role,
                    updatedAt = now,
                }
            end
            evt.updatedAt = now
            local _, myKey = ResolveSelfIdentity()
            local s = ns.db and ns.db.settings
            if myKey and evt.creatorKey == myKey and not Compat.IsMe(parsed.displayName) and s and s.clanSignupAlertEnabled ~= false then
                local cdKey = (parsed.lookupKey or "") .. ":" .. eventId
                local monoNow = GetTime and GetTime() or time()
                Clan.signupAlertCooldowns = Clan.signupAlertCooldowns or {}
                if (monoNow - (Clan.signupAlertCooldowns[cdKey] or 0)) >= 15 then
                    Clan.signupAlertCooldowns[cdKey] = monoNow
                    local roleLbl = L[role] or role
                    local evtName = (evt.title and evt.title ~= "") and evt.title or eventId
                    local msgBody = string.format(L["%s signed (%s): %s"], parsed.displayName, roleLbl, evtName)
                    local openLink = "|Haddon:SCentral:clanevt:" .. eventId .. "|h|cff58a6ff[" .. L["Open"] .. "]|r|h"
                    ns:Print("%s", "|cff3fb950[" .. L["Event Signup"] .. "]|r " .. msgBody .. " " .. openLink)
                    if s.chatSound ~= false then
                        PlayClanAlertSound(Clan, SOUNDKIT and (SOUNDKIT.MAP_PING or 3175))
                    end
                    Clan:IncrementNotificationCount(1)
                    ns:Emit("ADDON_MESSAGE_NOTIFY", {
                        id = "sig:" .. cdKey .. ":" .. tostring(now),
                        kind = "CLAN_SIGNUP",
                        sourceTag = L["Event Signup"],
                        sender = parsed.displayName,
                        senderClass = classFile ~= "" and classFile or nil,
                        text = msgBody,
                        eventId = eventId,
                        ts = now,
                        priority = 2,
                    })
                end
            end
            QueueClanEmit(0.5)
        end

    elseif cmd == "DEL" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local evt = bucket.events[eventId]
        if evt then
            local canEvtDel = (evt.creatorKey == parsed.lookupKey)
            if not canEvtDel and chatType == "GUILD" then
                local pol = Clan:GetGuildHierarchyPolicy()
                canEvtDel = IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, pol.eventModMode, pol.eventModMaxRank)
            end
            if canEvtDel then
                bucket.events[eventId] = nil
                QueueClanEmit(0.5)
            end
        end

    elseif cmd == "CINF" or cmd == "CINF2" or cmd == "CDIP" or cmd == "CDEL" or cmd == "CREQ" or cmd == "CHIR" or cmd == "ALLC" then
        -- Strict multi-layer anti-leakage guard: scope token + active guild roster verification
        local myTok = ComputeGuildScopeToken()
        local pktTok = parts[2] or ""
        if myTok == "" or pktTok ~= myTok or not IsSenderConfirmedInGuild(parsed.lookupKey) then
            return
        end

        if cmd == "ALLC" then
            local canAll = IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, "LEADER", 0)
                or (bucket.alliance and bucket.alliance.managers and bucket.alliance.managers[parsed.lookupKey] == true)
            if not canAll then
                return
            end
            local rev = tonumber(parts[3]) or 0
            Clan._heardIntelRev = Clan._heardIntelRev or {}
            Clan._heardIntelRev.allc = math.max(Clan._heardIntelRev.allc or 0, rev)
            bucket.alliance = bucket.alliance or {}
            if rev >= (bucket.alliance.rev or 0) then
                bucket.alliance.enabled = (parts[4] == "1")
                bucket.alliance.accessMode = (parts[5] == "ALL") and "ALL" or "WHITELIST"
                bucket.alliance.name = Compat.CleanPayloadField(parts[6] or "", 40)
                bucket.alliance.token = Compat.CleanPayloadField(parts[7] or "", 32)
                bucket.alliance.rev = rev
                bucket.alliance.updatedAt = now
                ns:Emit("CLAN_UPDATED")
                ns:Emit("ALLIANCE_UPDATED")
            end
            return
        elseif cmd == "CHIR" then
            if not IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, "LEADER", 0) then
                return
            end
            local rev = tonumber(parts[3]) or 0
            Clan._heardIntelRev = Clan._heardIntelRev or {}
            Clan._heardIntelRev.hir = math.max(Clan._heardIntelRev.hir or 0, rev)
            local h = bucket.hierarchy or {}
            if rev >= (h.rev or 0) then
                local dMode = (parts[4] == "OFFICERS" or parts[4] == "RANK") and parts[4] or "LEADER"
                local dMax = math.max(0, math.min(9, tonumber(parts[5]) or 1))
                local iMode = (parts[6] == "LEADER" or parts[6] == "RANK" or parts[6] == "ALL") and parts[6] or "OFFICERS"
                local iMax = math.max(0, math.min(9, tonumber(parts[7]) or 1))
                local eMode = (parts[8] == "LEADER" or parts[8] == "RANK") and parts[8] or "OFFICERS"
                local eMax = math.max(0, math.min(9, tonumber(parts[9]) or 1))
                local aMin = tonumber(parts[10])
                aMin = (aMin and aMin >= 0 and aMin <= 9) and aMin or -1
                bucket.hierarchy = {
                    rev = rev,
                    updatedAt = now,
                    updatedBy = parsed.displayName,
                    diplomacyMode = dMode,
                    diplomacyMaxRank = dMax,
                    infoMode = iMode,
                    infoMaxRank = iMax,
                    eventModMode = eMode,
                    eventModMaxRank = eMax,
                    allianceMinRank = aMin,
                }
                bucket.clanInfo = bucket.clanInfo or {}
                bucket.clanInfo.editMode = (iMode == "ALL") and "ALL" or "OFFICERS"
                ns:Emit("CLAN_UPDATED")
                ns:Emit("CLAN_DIPLOMACY_UPDATED")
                ns:Emit("CLAN_HIERARCHY_UPDATED")
            end
        elseif cmd == "CINF" then
            local pol = Clan:GetGuildHierarchyPolicy()
            if not IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, pol.infoMode, pol.infoMaxRank) then
                return
            end
            local ver = parts[3]
            local rev = tonumber(parts[4]) or 0
            Clan._heardIntelRev = Clan._heardIntelRev or {}
            Clan._heardIntelRev.info = math.max(Clan._heardIntelRev.info or 0, rev)
            local editMode = (parts[5] == "ALL") and "ALL" or "OFFICERS"
            local summary = Compat.CleanPayloadField(parts[6] or "", 60)
            local schedule = Compat.CleanPayloadField(parts[7] or "", 55)
            if IsSaneRemoteSemVer(ver) then
                ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, "GUILD")
            end
            bucket.clanInfo = bucket.clanInfo or {}
            if rev >= (bucket.clanInfo.rev or 0) then
                bucket.clanInfo.rev = rev
                bucket.clanInfo.editMode = editMode
                bucket.clanInfo.summary = summary
                bucket.clanInfo.schedule = schedule
                bucket.clanInfo.updatedAt = now
                bucket.clanInfo.updatedBy = parsed.displayName
                ns:Emit("CLAN_UPDATED")
                ns:Emit("CLAN_DIPLOMACY_UPDATED")
            end
        elseif cmd == "CINF2" then
            local pol = Clan:GetGuildHierarchyPolicy()
            if not IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, pol.infoMode, pol.infoMaxRank) then
                return
            end
            local rev = tonumber(parts[3]) or 0
            local rules = Compat.CleanPayloadField(parts[4] or "", 115)
            local contacts = Compat.CleanPayloadField(parts[5] or "", 60)
            bucket.clanInfo = bucket.clanInfo or {}
            if rev >= (bucket.clanInfo.rev or 0) then
                bucket.clanInfo.rev = rev
                bucket.clanInfo.rules = rules
                bucket.clanInfo.contacts = contacts
                bucket.clanInfo.updatedAt = now
                bucket.clanInfo.updatedBy = parsed.displayName
                ns:Emit("CLAN_UPDATED")
                ns:Emit("CLAN_DIPLOMACY_UPDATED")
            end
        elseif cmd == "CDIP" then
            local pol = Clan:GetGuildHierarchyPolicy()
            if not IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, pol.diplomacyMode, pol.diplomacyMaxRank) then
                return
            end
            local ver = parts[3]
            local rev = tonumber(parts[4]) or 0
            Clan._heardIntelRev = Clan._heardIntelRev or {}
            Clan._heardIntelRev.dip = math.max(Clan._heardIntelRev.dip or 0, rev)
            local stance = (parts[5] == "ALLY" or parts[5] == "ENEMY") and parts[5] or "NEUTRAL"
            local gName = Compat.CleanPayloadField(parts[7] or "", 40)
            local gKey = NormalizeGuildKey(gName)
            if gKey == "" then gKey = NormalizeGuildKey(parts[6] or "") end
            local gFaction = Compat.CleanPayloadField(parts[8] or "", 12)
            local reason = Compat.CleanPayloadField(parts[9] or "", 48)
            local myGuildKey = NormalizeGuildKey((Store.guildInfo and Store.guildInfo.name) or "")
            if IsSaneRemoteSemVer(ver) then
                ProcessPeerVersion(parsed.displayName, parsed.lookupKey, ver, "GUILD")
            end
            if gKey ~= "" and gName ~= "" and gKey ~= myGuildKey then
                bucket.diplomacy = bucket.diplomacy or { rev = 0, guilds = {} }
                local cur = bucket.diplomacy.guilds[gKey]
                if not cur or cur.localOnly or rev >= (cur.rev or 0) then
                    bucket.diplomacy.guilds[gKey] = {
                        key = gKey,
                        name = gName,
                        stance = stance,
                        reason = reason,
                        faction = gFaction,
                        addedBy = parsed.displayName,
                        localOnly = false,
                        rev = rev,
                        updatedAt = now,
                    }
                    if rev > (bucket.diplomacy.rev or 0) then
                        bucket.diplomacy.rev = rev
                    end
                    ns:Emit("CLAN_UPDATED")
                    ns:Emit("CLAN_DIPLOMACY_UPDATED")
                end
            end
        elseif cmd == "CDEL" then
            local pol = Clan:GetGuildHierarchyPolicy()
            if not IsSenderAuthorizedForPolicy(Clan, parsed.lookupKey, pol.diplomacyMode, pol.diplomacyMaxRank) then
                return
            end
            local rev = tonumber(parts[4]) or 0
            Clan._heardIntelRev = Clan._heardIntelRev or {}
            Clan._heardIntelRev.dip = math.max(Clan._heardIntelRev.dip or 0, rev)
            local gKey = NormalizeGuildKey(parts[5] or "")
            if gKey ~= "" and bucket.diplomacy and bucket.diplomacy.guilds and bucket.diplomacy.guilds[gKey] then
                if not bucket.diplomacy.guilds[gKey].localOnly and rev >= (bucket.diplomacy.guilds[gKey].rev or 0) then
                    bucket.diplomacy.guilds[gKey] = nil
                    if rev > (bucket.diplomacy.rev or 0) then
                        bucket.diplomacy.rev = rev
                    end
                    ns:Emit("CLAN_UPDATED")
                    ns:Emit("CLAN_DIPLOMACY_UPDATED")
                end
            end
        elseif cmd == "CREQ" then
            local peerInfoRev = tonumber(parts[3]) or 0
            local peerDipRev = tonumber(parts[4]) or 0
            local peerHirRev = tonumber(parts[5]) or 0
            local peerAllcRev = tonumber(parts[6]) or 0
            local myInfoRev = (bucket.clanInfo and bucket.clanInfo.rev) or 0
            local myDipRev = (bucket.diplomacy and bucket.diplomacy.rev) or 0
            local myHirRev = (bucket.hierarchy and bucket.hierarchy.rev) or 0
            local myAllcRev = (bucket.alliance and bucket.alliance.enabled and bucket.alliance.rev) or 0
            if (myInfoRev > peerInfoRev or myDipRev > peerDipRev or myHirRev > peerHirRev or myAllcRev > peerAllcRev) and (GetTime() - (Clan.lastIntelReplyAt or 0)) >= 25 then
                Clan.lastIntelReplyAt = GetTime()
                local d = Clan:IsGuildLeader() and (0.6 + math.random() * 0.6) or (1.4 + math.random() * 1.8)
                C_Timer.After(d, function()
                    if ComputeGuildScopeToken() == myTok then
                        local heard = Clan._heardIntelRev or {}
                        local effInfo = math.max(peerInfoRev, heard.info or 0)
                        local effDip = math.max(peerDipRev, heard.dip or 0)
                        local effHir = math.max(peerHirRev, heard.hir or 0)
                        local effAllc = math.max(peerAllcRev, heard.allc or 0)
                        if Clan.BroadcastDeltaIntel then
                            Clan:BroadcastDeltaIntel(effInfo, effDip, effHir, effAllc)
                        else
                            Clan:BroadcastFullIntel()
                        end
                    end
                end)
            end
        end

    elseif cmd == "SCT" then
        local targetName = Compat.CleanPayloadField(parts[2] or "", 32)
        local targetGuild = Compat.CleanPayloadField(parts[3] or "", 32)
        local lvl = tonumber(parts[4]) or 0
        local classFile = parts[5]
        local zone = Compat.CleanPayloadField(parts[6] or "", 32)
        local coords = Compat.CleanPayloadField(parts[7] or "", 16)
        if targetName ~= "" then
            local s = ns.db and ns.db.settings
            if not s or s.spotterScoutAlert ~= false then
                local guildTag = targetGuild ~= "" and (" <" .. targetGuild .. ">") or ""
                local lvlTag = lvl > 0 and (" (Lv " .. lvl .. ")") or ""
                local locTag = (zone ~= "" and coords ~= "") and (" - " .. zone .. " (" .. coords .. ")") or ""
                local radarLink = "|Haddon:SCentral:spotter|h|cff58a6ff[" .. L["Target Radar"] .. "]|r|h"
                ns:Print("%s", string.format("|cffff4444[SocialCentral Scout] %s%s%s%s (%s)|r %s", targetName, guildTag, lvlTag, locTag, parsed.displayName, radarLink))
                if not s or s.spotterSound ~= false then
                    PlayClanAlertSound(Clan, SOUNDKIT and (SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT or 180))
                end
                Clan:IncrementNotificationCount(1)
                ns:Emit("ADDON_MESSAGE_NOTIFY", {
                    id = "sct:" .. targetName .. ":" .. tostring(now),
                    kind = "SCOUT",
                    sourceTag = L["Scout Alert"],
                    sender = parsed.displayName,
                    senderClass = classFile ~= "" and classFile or nil,
                    text = targetName .. guildTag .. locTag,
                    ts = now,
                    priority = 3,
                })
            end
        end

    elseif cmd == "WB" then
        local syncId = parts[2]
        local ts = tonumber(parts[3])
        local shardName = Compat.CleanPayloadField and Compat.CleanPayloadField(parts[4] or "", 40) or nil
        if VALID_WB_SYNC_IDS[syncId] and ts and ts > 0 and ns.WorldBuffs and ns.WorldBuffs.ReceiveSyncedDrop then
            ns.WorldBuffs:ReceiveSyncedDrop(syncId, ts, parsed.displayName, shardName)
        end

    elseif cmd == "WBR" then
        if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("buffs") then return end
        if not ns.WorldBuffs or not ns.WorldBuffs.GetCatchupSyncEntries then return end
        local entries = ns.WorldBuffs:GetCatchupSyncEntries()
        if not entries or #entries == 0 then return end
        local monoNow = GetTime and GetTime() or 0
        if Clan.lastWbCatchupReplyAt and (monoNow - Clan.lastWbCatchupReplyAt) < 30 then
            return
        end
        Clan.lastWbCatchupReplyAt = monoNow
        local baseDelay = (#entries >= 3) and 0.6 or ((#entries == 2) and 1.2 or 1.8)
        local delay = baseDelay + math.random() * 0.9
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, function()
                if Clan:IsMessagingLocked() or not (IsInGuild and IsInGuild()) or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
                    return
                end
                local heardWbAt = Clan._lastHeardWbCatchupAt or 0
                if heardWbAt > 0 and ((GetTime and GetTime() or 0) - heardWbAt) < 6.0 then
                    return
                end
                local curEntries = ns.WorldBuffs and ns.WorldBuffs.GetCatchupSyncEntries and ns.WorldBuffs:GetCatchupSyncEntries() or {}
                if #curEntries == 0 then return end
                local chunks = {}
                for idx = 1, math.min(3, #curEntries) do
                    local it = curEntries[idx]
                    if VALID_WB_SYNC_IDS[it.id] and it.ts and it.ts > 0 then
                        chunks[#chunks + 1] = it.id .. ":" .. tostring(math.floor(it.ts))
                    end
                end
                if #chunks > 0 then
                    local shard = Compat.CleanPayloadField and Compat.CleanPayloadField((Compat.Realm and Compat.Realm()) or "", 40) or ""
                    local wbPayload = "WBC~" .. table.concat(chunks, ",") .. (shard ~= "" and ("~" .. shard) or "")
                    TransmitAddonMessage(Clan, wbPayload, "GUILD", false)
                end
            end)
        end

    elseif cmd == "WBC" then
        if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("buffs") then return end
        Clan._lastHeardWbCatchupAt = GetTime and GetTime() or 0
        local listStr = parts[2]
        local shardName = Compat.CleanPayloadField and Compat.CleanPayloadField(parts[3] or "", 40) or nil
        if type(listStr) ~= "string" or listStr == "" or not (ns.WorldBuffs and ns.WorldBuffs.ReceiveSyncedDrop) then return end
        for token in listStr:gmatch("[^,]+") do
            local sId, sTs = token:match("^([%w_]+):(%d+)$")
            local tsNum = tonumber(sTs)
            if sId and VALID_WB_SYNC_IDS[sId] and tsNum and tsNum > 0 then
                ns.WorldBuffs:ReceiveSyncedDrop(sId, tsNum, parsed.displayName, shardName)
            end
        end

    elseif cmd == "SGT" then
        if not IsSenderConfirmedInGuild(parsed.lookupKey) then
            return
        end
        local sName = Compat.CleanPayloadField(parts[2] or "", 32)
        local sGuid = Compat.CleanPayloadField(parts[3] or "", 44)
        local sLvl = tonumber(parts[4]) or 0
        local sClass = Compat.CleanPayloadField(parts[5] or "", 16)
        local sGuild = Compat.CleanPayloadField(parts[6] or "", 32)
        local sZone = Compat.CleanPayloadField(parts[7] or "", 28)
        local sParsed = (sName ~= "" and Compat.ParseCharacterName) and Compat.ParseCharacterName(sName) or nil
        if sParsed and sParsed.surname and sParsed.surname ~= "" and not Compat.IsMe(sParsed.displayName, sGuid) then
            local monoNow = GetTime and GetTime() or time()
            Clan._heardGuildSightingAt = Clan._heardGuildSightingAt or {}
            Clan._heardGuildSightingAt[sParsed.lookupKey] = monoNow
            Clan._seenSightingByKey = Clan._seenSightingByKey or {}
            Clan._seenSightingByKey[sParsed.lookupKey] = monoNow
            if sGuid ~= "" and Compat.CacheForeverFullName then
                Compat.CacheForeverFullName(sGuid, sParsed.displayName, sParsed.firstName)
            end
            if Store and Store.SyncWatchlistObservation then
                Store:SyncWatchlistObservation(sParsed.displayName, {
                    online = true,
                    level = sLvl > 0 and sLvl or nil,
                    classFile = sClass ~= "" and sClass or nil,
                    area = sZone,
                    guild = sGuild,
                    guid = sGuid ~= "" and sGuid or nil,
                    source = "guild_sighting",
                }, { allowUnknownTransition = true })
            end
        end
    end
end

function Clan:QueueCooperativeSighting(fullName, guid, level, classFile, guildName, zone)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    local targetKey, _, dispName, surname = Compat.ParseCharacterFields(fullName)
    if not targetKey or not surname or surname == "" or Compat.IsMe(dispName, guid) then
        return false
    end
    local monoNow = GetTime and GetTime() or 0
    self._seenSightingByKey = self._seenSightingByKey or {}
    if (monoNow - (self._seenSightingByKey[targetKey] or 0)) < 90 then
        return false
    end
    if self._lastSightingSentAt and (monoNow - self._lastSightingSentAt) < 18 then
        return false
    end
    self._seenSightingByKey[targetKey] = monoNow

    local cleanName = Compat.CleanPayloadField(dispName, 32)
    local cleanGuid = Compat.CleanPayloadField(guid or "", 44)
    local cleanLvl = math.max(0, math.min(80, math.floor(tonumber(level) or 0)))
    local cleanClass = Compat.CleanPayloadField(classFile or "", 16)
    local cleanGuild = Compat.CleanPayloadField(guildName or "", 32)
    local cleanZone = Compat.CleanPayloadField(zone or "", 28)
    local payload = ("SGT~%s~%s~%d~%s~%s~%s"):format(cleanName, cleanGuid, cleanLvl, cleanClass, cleanGuild, cleanZone)

    if C_Timer and C_Timer.After then
        local delay = 0.5 + math.random() * 1.2
        C_Timer.After(delay, function()
            if Clan.isStoppedThisSession or Clan:IsMessagingLocked() then return end
            if not (ns.db and ns.db.settings and ns.db.settings.clanSync) or not (IsInGuild and IsInGuild()) then return end
            local nowT = GetTime and GetTime() or 0
            local heardAt = Clan._heardGuildSightingAt and Clan._heardGuildSightingAt[targetKey]
            if heardAt and (nowT - heardAt) < 60 then
                return
            end
            if Clan._lastSightingSentAt and (nowT - Clan._lastSightingSentAt) < 18 then
                return
            end
            if TransmitAddonMessage(Clan, payload, "GUILD", false) then
                Clan._lastSightingSentAt = GetTime and GetTime() or nowT
            end
        end)
        return true
    end
    if TransmitAddonMessage(Clan, payload, "GUILD", false) then
        self._lastSightingSentAt = monoNow
        return true
    end
    return false
end

local LFG_EXACT_WORDS = {
    lfm = true, lfg = true, bora = true, alguem = true, alguien = true,
    tank = true, tanks = true, heal = true, healer = true, healers = true,
    dps = true, dg = true, masmorra = true, masmorras = true,
    mazmorra = true, mazmorras = true, dungeon = true, dungeons = true,
    mythic = true, chave = true, chaves = true, pedra = true, pedras = true,
    raid = true, raids = true, raide = true, raides = true, boss = true, bosses = true,
    procuro = true, busco = true, falta = true, faltam = true,
    preciso = true, precisa = true, precisamos = true,
}

local LFG_LITERALS = {
    "precis", "falta", "procur", "busc", "heal", "masmorr", "mazmorr", "m+",
}

local function MatchesLfgText(low)
    if type(low) ~= "string" or low == "" then return false end
    for w in low:gmatch("[%w']+") do
        if LFG_EXACT_WORDS[w] then
            return true
        end
    end
    for i = 1, #LFG_LITERALS do
        if low:find(LFG_LITERALS[i], 1, true) then
            return true
        end
    end
    return low:find("lf%d+m") ~= nil
end

local function CapturePassiveGuildProfession(rawMsg, cleanMsg, parsed)
    if not (Clan.ParseProfessionsFromNote and parsed and parsed.lookupKey) then return end
    Clan.passiveChatProfs = Clan.passiveChatProfs or {}
    if Compat.IsMe(parsed.displayName) then return end

    -- 1) Official Blizzard trade hyperlink: |Htrade:guid:spell:cur:max:...|h[Prof]|h
    local p1, p2, r1, r2, noteHint = "NONE", "NONE", "", "", ""
    if type(rawMsg) == "string" and rawMsg:find("|Htrade:", 1, true) then
        for cur, maxVal, linkLabel in rawMsg:gmatch("|Htrade:[^:]*:[^:]*:(%d+):(%d+)[^|]*|h%[([^%]]+)%]|h") do
            local pid = Clan:MatchProfessionId(linkLabel)
            if pid and pid ~= "NONE" then
                if p1 == "NONE" then
                    p1 = pid
                    if tonumber(maxVal) and tonumber(maxVal) > 0 then
                        r1 = ("%d/%d"):format(tonumber(cur) or 0, tonumber(maxVal) or 0)
                    end
                elseif p2 == "NONE" and pid ~= p1 then
                    p2 = pid
                    if tonumber(maxVal) and tonumber(maxVal) > 0 then
                        r2 = ("%d/%d"):format(tonumber(cur) or 0, tonumber(maxVal) or 0)
                    end
                end
            end
        end
    end

    -- 2) Craft offer / service mention alongside a profession keyword in /g
    if p1 == "NONE" and type(cleanMsg) == "string" then
        local low = cleanMsg:lower()
        local hasOfferVerb = low:find("%f[%w]faco%f[%W]")
            or low:find("faço")
            or low:find("%f[%w]craft")
            or low:find("%f[%w]hago%f[%W]")
            or low:find("%f[%w]mats%f[%W]")
            or low:find("%f[%w]wts%f[%W]")
            or low:find("%f[%w]gratis%f[%W]")
            or low:find("%f[%w]free%f[%W]")
        if hasOfferVerb then
            local dp1, dp2 = Clan:ParseProfessionsFromNote(cleanMsg)
            if dp1 ~= "NONE" then
                p1, p2 = dp1, dp2
                noteHint = Compat.CleanPayloadField(cleanMsg, 40)
            end
        end
    end

    if p1 ~= "NONE" then
        local nowProf = time()
        local ttl = Clan.PASSIVE_PROF_TTL or (6 * 3600)
        local profCount, oldestProfKey, oldestProfTs = 0, nil, nil
        for k, rec in pairs(Clan.passiveChatProfs) do
            if type(rec) ~= "table" or (nowProf - (rec.updatedAt or 0)) > ttl then
                Clan.passiveChatProfs[k] = nil
            else
                profCount = profCount + 1
                if not oldestProfTs or (rec.updatedAt or 0) < oldestProfTs then
                    oldestProfTs = rec.updatedAt or 0
                    oldestProfKey = k
                end
            end
        end
        if not Clan.passiveChatProfs[parsed.lookupKey] and profCount >= (Clan.MAX_PASSIVE_PROFS or 100) and oldestProfKey then
            Clan.passiveChatProfs[oldestProfKey] = nil
        end
        Clan.passiveChatProfs[parsed.lookupKey] = {
            lookupKey = parsed.lookupKey,
            displayName = parsed.displayName,
            prof1 = p1,
            prof2 = p2,
            prof1Rank = r1,
            prof2Rank = r2,
            craftNote = (noteHint ~= "") and noteHint or Compat.CleanPayloadField(cleanMsg or "", 40),
            updatedAt = nowProf,
        }
        QueueClanEmit(0.8)
    end
end

local function OnGuildChatPassive(_, _, text, sender)
    if Safe.IsSecret(text) or Safe.IsSecret(sender) then return end
    local rawText = Safe.String(text)
    local cleanSender = Safe.String(sender)
    if not rawText or not cleanSender then return end
    local cleanMsg = Compat.CleanInput(rawText)
    local parsed = Compat.ParseCharacterName(cleanSender)
    if not cleanMsg or not parsed then return end

    CapturePassiveGuildProfession(rawText, cleanMsg, parsed)

    local s = ns.db and ns.db.settings
    if not (s and (s.guildChatFinder or s.clanLfgAlertEnabled)) then return end

    local low = cleanMsg:lower()
    if not MatchesLfgText(low) then return end

    local isDng = IsDungeonLFGText(cleanMsg, nil)
    for i = #Clan.guildChatLFG, 1, -1 do
        if Clan.guildChatLFG[i].lookupKey == parsed.lookupKey then
            table.remove(Clan.guildChatLFG, i)
        end
    end
    table.insert(Clan.guildChatLFG, 1, {
        lookupKey = parsed.lookupKey,
        sender = parsed.displayName,
        displayName = parsed.displayName,
        text = cleanMsg:sub(1, 120),
        isDungeon = isDng,
        timestamp = time(),
        ts = time(),
    })
    while #Clan.guildChatLFG > 16 do
        table.remove(Clan.guildChatLFG)
    end
    if not Compat.IsMe(parsed.displayName) then
        Clan:MaybeNotifyClanLFG(parsed.lookupKey, parsed.displayName, nil, cleanMsg:sub(1, 120), "", isDng, "GCHAT")
    end
    QueueClanEmit(0.6)
end

local RECRUIT_WORDS = {
    lfm = true, falta = true, faltam = true, precisa = true, precisamos = true,
    vaga = true, vagas = true, need = true, needs = true, recruiting = true,
}
local TANK_WORDS = { tank = true, tanks = true, tanque = true, tanques = true, prot = true }
local HEAL_WORDS = { heal = true, healer = true, healers = true, cura = true, curandeiro = true, resto = true, holy = true }
local DPS_WORDS = { dps = true, dano = true, dd = true }

local function ClassifyChatLfgMessage(low)
    if type(low) ~= "string" or low == "" then return "LFM", "ANY" end
    local hasLfg, hasRecruit = false, false
    local hasTank, hasHeal, hasDps = false, false, false
    for w in low:gmatch("[%w']+") do
        if w == "lfg" then
            hasLfg = true
        elseif RECRUIT_WORDS[w] then
            hasRecruit = true
        end
        if TANK_WORDS[w] then hasTank = true end
        if HEAL_WORDS[w] then hasHeal = true end
        if DPS_WORDS[w] then hasDps = true end
    end
    if not hasRecruit and low:find("lf%d+m") then
        hasRecruit = true
    end
    if not hasLfg and (low:find("procuro grupo", 1, true) or low:find("busco grupo", 1, true)
        or low:find("sou tank", 1, true) or low:find("sou heal", 1, true) or low:find("sou dps", 1, true)) then
        hasLfg = true
    end
    if not hasHeal and low:find("heal", 1, true) then
        hasHeal = true
    end
    local msgMode = (hasLfg and not hasRecruit) and "LFG" or "LFM"
    local roleCount = (hasTank and 1 or 0) + (hasHeal and 1 or 0) + (hasDps and 1 or 0)
    local roleHint = "ANY"
    if roleCount == 1 then
        roleHint = hasTank and "TANK" or (hasHeal and "HEALER" or "DPS")
    end
    return msgMode, roleHint
end

local function AcquireGlobalChatSlot(tbl, senderLk)
    local slot = tbl and tbl[senderLk]
    if type(slot) == "table" then
        return slot
    end
    return {}
end

local function OnExternalChatPassive(_, _, text, sender, ...)
    local sTop = ns.db and ns.db.settings
    if sTop and sTop.embedLfgWindow == false then return end
    if Safe.IsSecret(text) or Safe.IsSecret(sender) then return end
    local rawMsg = Safe.String(text)
    local cleanSender = Safe.String(sender)
    if not rawMsg or not cleanSender then return end

    -- Idle optimization: when LFG UI hasn't been used recently, skip parsing global/trade
    -- spam from strangers BEFORE allocating lowercase/cleaned strings; only allow known allies/friends.
    local listenGlobal = IsGlobalLfgListenerActive()
    local senderLkPre, _, senderDispPre = Compat.ParseCharacterFields(cleanSender)
    if not listenGlobal then
        if not senderLkPre then return end
        local alertsOn = (not sTop) or sTop.clanLfgAlertEnabled ~= false
        if not alertsOn then return end
        local quickSocial = (Store.socialByLookup and Store.socialByLookup[senderLkPre] ~= nil)
            or (Store.GetWatchlistTable and (Store:GetWatchlistTable() or {})[senderLkPre] ~= nil)
            or (Compat.IsGuildMember and Compat.IsGuildMember(nil, nil, senderDispPre or cleanSender))
        if not quickSocial then
            return
        end
    end

    local cleanMsg
    if rawMsg:find("|", 1, true) then
        cleanMsg = Compat.CleanInput(rawMsg)
        if not cleanMsg then return end
    end

    local scanLow = (cleanMsg or rawMsg):lower()
    if not MatchesLfgText(scanLow) then return end

    local s = ns.db and ns.db.settings
    if (not s) or (s.lfgAntiSpam ~= false) then
        if MatchesSpamText(scanLow) then
            return
        end
    end

    cleanMsg = cleanMsg or Compat.CleanInput(rawMsg)
    local cleanGuid = Safe.String(select(10, ...))
    local senderLk, _, senderDisp = Compat.ParseCharacterFields(cleanSender)
    if not cleanMsg or not senderLk or Compat.IsMe(senderDisp, cleanGuid) then return end

    local isClan, isAllied, isFriend, isWatchlist, resolvedGuild = Clan:GetPlayerRelationshipFlags(
        senderLk,
        senderDisp,
        cleanGuid,
        nil
    )
    local scanGlobal = listenGlobal and ((not s) or (s.embedLfgWindow ~= false and s.globalChatLfgScan ~= false))
    if (not scanGlobal) and not (isAllied or isFriend or isWatchlist or isClan) then
        return
    end

    local low = cleanMsg:lower()
    local isDng = IsDungeonLFGText(cleanMsg, nil)
    local msgMode, roleHint = ClassifyChatLfgMessage(low)
    local nowTs = time()

    if scanGlobal then
        Clan.globalChatLFG = Clan.globalChatLFG or {}
        local chRaw = Safe.String(select(2, ...)) or ""
        local chShort = chRaw:match("^%d+%.%s*(.+)$") or chRaw
        local row = AcquireGlobalChatSlot(Clan.globalChatLFG, senderLk)
        row.sourceType = "PUBLIC_CHAT"
        row.lookupKey = senderLk
        row.guid = cleanGuid
        row.displayName = senderDisp
        row.guild = resolvedGuild
        row.channel = Compat.CleanPayloadField and Compat.CleanPayloadField(chShort, 28) or ""
        row.mode = msgMode
        row.role = roleHint
        row.activity = (chShort ~= "" and ("[" .. chShort .. "] ") or "") .. cleanMsg:sub(1, 36)
        row.note = cleanMsg:sub(1, 130)
        row.isDungeon = isDng
        row.updatedAt = nowTs
        Clan.globalChatLFG[senderLk] = row
        PruneAndBoundByTimestamp(Clan.globalChatLFG, Clan.MAX_GLOBAL_CHAT_LFG or 35, 600, nowTs)
        if IsClanOrLFGVisible() then
            QueueClanEmit(1.2)
        end
    end

    if not (isAllied or isFriend or isWatchlist or isClan) then
        return
    end

    Clan.externalLFG = Clan.externalLFG or {}
    Clan.externalLFG[senderLk] = {
        sourceType = "CHAT",
        lookupKey = senderLk,
        guid = cleanGuid,
        displayName = senderDisp,
        guild = resolvedGuild,
        mode = msgMode,
        role = roleHint,
        activity = cleanMsg:sub(1, 44),
        keyLvl = 0,
        ilvl = 0,
        note = cleanMsg:sub(1, 120),
        isDungeon = isDng,
        isFriend = isFriend,
        isWatchlist = isWatchlist,
        updatedAt = nowTs,
    }

    PruneAndBoundByTimestamp(Clan.externalLFG, Clan.MAX_EXTERNAL_LFG or 40, 1800, nowTs)

    local srcBadge = (isFriend or isWatchlist) and L["Friends"] or (isAllied and L["Allied Clans"] or L["Clan LFG"])
    Clan:MaybeNotifyClanLFG(
        senderLk,
        senderDisp,
        nil,
        cleanMsg:sub(1, 90),
        cleanMsg:sub(1, 44),
        isDng,
        "ALLY_LFG",
        nil,
        srcBadge
    )

    QueueClanEmit(0.6)
end

function Clan:ApplyAutoInstanceStatus()
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("clan") then return end
    if not (ns.db and ns.db.settings and ns.db.settings.autoStatusInstance) then return end
    if self:IsMessagingLocked() then return end
    local inInst, instType = Safe.Call(IsInInstance)
    local bucket = Store:GetClanScopeData()
    if inInst ~= true then
        if self._didAutoBusyTag then
            self._didAutoBusyTag = false
            bucket.myTag = "NONE"
            if ns.db.settings.clanSync and (GetTime() - (self.lastSyncSentAt or 0)) >= (self.MIN_SEND_INTERVAL or 5) then
                self:SendGuildSync(("TAG~%s~NONE~%s"):format(ns.version or "0.0.0", Compat.CleanPayloadField(bucket.myNote or "", 36)))
            end
            ns:Emit("CLAN_UPDATED")
        end
        return
    end
    local autoTag
    if instType == "party" then
        autoTag = "MPLUS"
    elseif instType == "raid" then
        autoTag = "RAID"
    elseif instType == "pvp" or instType == "arena" then
        autoTag = "PVP"
    end
    if not autoTag then return end
    if bucket.myTag == autoTag then return end
    self._didAutoBusyTag = true
    bucket.myTag = autoTag
    if ns.db.settings.clanSync and (GetTime() - (self.lastSyncSentAt or 0)) >= (self.MIN_SEND_INTERVAL or 5) then
        self:SendGuildSync(("TAG~%s~%s~%s"):format(ns.version or "0.0.0", autoTag, Compat.CleanPayloadField(bucket.myNote or "", 36)))
    end
    ns:Emit("CLAN_UPDATED")
end

local function ParseEventCountdownMinutes(whenText, createdAt)
    if type(whenText) ~= "string" or whenText == "" then return nil end
    local low = whenText:lower()

    -- Relative offsets written by players: "in 20m", "em 30 min", "1h", etc.
    if createdAt and createdAt > 0 then
        local relMins = tonumber(low:match("^%s*[ie][nm]%s+(%d+)%s*m")) or tonumber(low:match("^(%d+)%s*min"))
        if relMins and relMins > 0 and relMins <= 720 then
            return ((createdAt + relMins * 60) - time()) / 60
        end
        local relHours = tonumber(low:match("^%s*[ie][nm]%s+(%d+)%s*h"))
        if relHours and relHours > 0 and relHours <= 12 then
            return ((createdAt + relHours * 3600) - time()) / 60
        end
    end

    -- Clock timestamps like "21:00", "21h30", "21h", "9:30 pm" (only for events created within the past 20 hours).
    if createdAt and (time() - createdAt) > 72000 then
        return nil
    end
    local hStr, mStr = low:match("(%d%d?):(%d%d)")
    if not hStr then
        hStr, mStr = low:match("(%d%d?)h(%d%d)")
    end
    if not hStr then
        hStr = low:match("(%d%d?)h")
        mStr = "0"
    end
    local hour = tonumber(hStr)
    local minute = tonumber(mStr) or 0
    if not hour or hour > 24 or minute > 59 then
        return nil
    end
    if low:find("pm", 1, true) and hour < 12 then
        hour = hour + 12
    elseif low:find("am", 1, true) and hour == 12 then
        hour = 0
    end
    if hour == 24 then hour = 0 end

    local nowTbl = date("*t")
    local nowMins = (nowTbl.hour or 0) * 60 + (nowTbl.min or 0)
    local evtMins = hour * 60 + minute
    local diff = evtMins - nowMins
    if diff < -60 then
        diff = diff + 1440
    end
    return diff
end

local function ComputeCalendarCountdownMinutes(calEvt)
    if type(calEvt) ~= "table" or (calEvt.dayDelta or 99) > 1 then
        return nil
    end
    local today = (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and Safe.Call(C_DateAndTime.GetCurrentCalendarTime)) or date("*t")
    local curHour = tonumber(today and today.hour) or 0
    local curMin = tonumber(today and today.minute) or 0
    local nowMins = curHour * 60 + curMin
    local targetMins = ((calEvt.dayDelta or 0) * 1440) + ((calEvt.hour or 0) * 60) + (calEvt.minute or 0)
    return targetMins - nowMins
end

function Clan:CheckUpcomingEventReminders()
    local s = ns.db and ns.db.settings
    if s and s.clanEventReminders == false then return 600 end
    if Compat.IsModuleEnabled and not Compat.IsModuleEnabled("clan") then return 600 end
    local bucket = Store and Store.GetClanScopeData and Store:GetClanScopeData()
    local hasGuildEvents = (bucket and type(bucket.events) == "table" and next(bucket.events) ~= nil)
    local hasCalEvents = (type(self.calendarEvents) == "table" and #self.calendarEvents > 0)
    if not hasGuildEvents and not hasCalEvents then
        return 600
    end
    self._remindedEventStages = self._remindedEventStages or {}
    local minUpcomingMins = nil

    local function FireReminder(remKey, title, minsUntil, eventId, rightView)
        if minsUntil > 15 or minsUntil < -1 then return end
        if type(remKey) == "string" and remKey:sub(1, 3) == "sc:" and Compat.ShouldShowGuildFeatures and not Compat.ShouldShowGuildFeatures() then
            return
        end
        local stage = (minsUntil <= 5) and 5 or 15
        if (self._remindedEventStages[remKey] or 99) <= stage then
            return
        end
        self._remindedEventStages[remKey] = stage

        local timeLabel = (minsUntil <= 1) and L["Starting now!"] or L["Starts in ~%d min"]:format(math.max(1, math.ceil(minsUntil)))
        local evtLink = eventId
            and ("|Haddon:SCentral:clanevt:" .. tostring(eventId) .. "|h|cff58a6ff[" .. L["Open"] .. "]|r|h")
            or ("|Haddon:SCentral:clanevt:calendar|h|cff58a6ff[" .. L["Open"] .. "]|r|h")
        ns:Print("|cfff2c94c[%s]|r %s — %s %s", L["Event Reminder"], title, timeLabel, evtLink)
        PlayClanAlertSound(self, SOUNDKIT and (SOUNDKIT.MAP_PING or 3175))
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "evrem:" .. remKey .. ":" .. tostring(stage),
            kind = "CLAN_EVENT",
            sourceTag = L["Event Reminder"],
            sender = title,
            text = timeLabel,
            eventId = eventId,
            clanRightView = rightView or "events",
            ts = time(),
            priority = 2,
            totalDuration = 16.0,
        })
    end

    local _, myKey = ResolveSelfIdentity()
    if hasGuildEvents and myKey then
        for _, evt in pairs(bucket.events) do
            if type(evt) == "table" and evt.isOpen ~= false and evt.signups and evt.signups[myKey] then
                local mins = ParseEventCountdownMinutes(evt.whenText, evt.createdAt)
                if mins then
                    if mins > -1 and (not minUpcomingMins or mins < minUpcomingMins) then
                        minUpcomingMins = mins
                    end
                    FireReminder("sc:" .. tostring(evt.id), evt.title or L["Guild Event"], mins, evt.id, "events")
                end
            end
        end
    end

    local calEnum = Enum and Enum.CalendarStatus
    local statusAvail = (calEnum and calEnum.Available) or 1
    local statusConf = (calEnum and calEnum.Confirmed) or 3
    local statusStandby = (calEnum and calEnum.Standby) or 5
    local statusSigned = (calEnum and calEnum.Signedup) or 6
    local statusTent = (calEnum and calEnum.Tentative) or 8

    if type(self.calendarEvents) == "table" then
        for _, cal in ipairs(self.calendarEvents) do
            if type(cal) == "table" then
                local st = tonumber(cal.inviteStatus)
                local attending = (st == statusAvail or st == statusConf or st == statusStandby or st == statusSigned or st == statusTent)
                    or (cal.invitedBy and cal.invitedBy ~= "" and Compat.IsMe(cal.invitedBy))
                if attending then
                    local mins = ComputeCalendarCountdownMinutes(cal)
                    if mins then
                        if mins > -1 and (not minUpcomingMins or mins < minUpcomingMins) then
                            minUpcomingMins = mins
                        end
                        local calKey = "cal:" .. tostring(cal.eventID or cal.title) .. ":" .. tostring(cal.hour) .. ":" .. tostring(cal.minute)
                        FireReminder(calKey, cal.title or L["Calendar Event"], mins, nil, "events")
                    end
                end
            end
        end
    end

    local nextDelay = 600
    if minUpcomingMins then
        if minUpcomingMins <= 5 then
            nextDelay = 60
        elseif minUpcomingMins <= 15 then
            nextDelay = math.max(30, math.floor((minUpcomingMins - 5) * 60))
        elseif minUpcomingMins <= 60 then
            nextDelay = math.max(60, math.floor((minUpcomingMins - 15) * 60))
        else
            nextDelay = 600
        end
    end
    return nextDelay
end

function Clan:ScheduleNextEventReminderCheck()
    if self._reminderTimer then
        self._reminderTimer:Cancel()
        self._reminderTimer = nil
    end
    if not (C_Timer and C_Timer.After) then return end
    local delay = self:CheckUpcomingEventReminders() or 600
    self._reminderTimer = C_Timer.NewTimer(delay, function()
        self._reminderTimer = nil
        Clan:ScheduleNextEventReminderCheck()
    end)
end

function Clan:GetRosterHistory()
    local bucket = Store:GetClanScopeData()
    return bucket.rosterHistory or {}
end

local histSeenScratch = {}
local histSnapScratch = {}
local histPackBuf = {}

local function UnpackPackedRosterSnapshot(prevSnap, dest)
    wipe(dest)
    if type(prevSnap) ~= "table" then return end
    if type(prevSnap.packed) == "string" and prevSnap.packed ~= "" then
        for line in prevSnap.packed:gmatch("[^\n]+") do
            local lk, cleanName, cleanRank = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
            if lk and lk ~= "" then
                dest[lk] = cleanName .. "\t" .. cleanRank
            end
        end
    elseif type(prevSnap.members) == "table" then
        for lk, val in pairs(prevSnap.members) do
            if type(val) == "string" then
                dest[lk] = val
            elseif type(val) == "table" then
                dest[lk] = (val.name or "") .. "\t" .. (val.rank or "")
            end
        end
    end
end

local function UpdateGuildRosterHistory()
    if not (IsInGuild and IsInGuild()) then return end
    local nowClock = (GetTime and GetTime()) or 0
    if Clan._lastRosterHistoryAt and (nowClock - Clan._lastRosterHistoryAt) < 60 then
        return
    end
    local gName = GetGuildInfo and Safe.String(GetGuildInfo("player"))
    local total = GetNumGuildMembers and Safe.Number(GetNumGuildMembers()) or 0
    if not gName or gName == "" or not total or total <= 0 then return end
    Clan._lastRosterHistoryAt = nowClock

    local function UnpackSnapshotMember(val)
        if type(val) == "string" then
            local n, r = val:match("^([^\t]*)\t(.*)$")
            return n or val, r or ""
        elseif type(val) == "table" then
            return val.name or "", val.rank or ""
        end
        return "", ""
    end

    local bucket = Store:GetClanScopeData()
    local prevSnap = bucket.rosterSnapshot
    bucket.rosterHistory = bucket.rosterHistory or {}
    local hasStoredData = type(prevSnap) == "table" and prevSnap._initialized and prevSnap._guild == gName
        and (type(prevSnap.packed) == "string" or type(prevSnap.members) == "table")
    local snapMembers = histSnapScratch
    if hasStoredData then
        UnpackPackedRosterSnapshot(prevSnap, snapMembers)
    else
        wipe(snapMembers)
        bucket.rosterSnapshot = {
            _initialized = true,
            _guild = gName,
            packed = "",
        }
    end
    local canDiff = hasStoredData and next(snapMembers) ~= nil

    wipe(histSeenScratch)
    local now = time()
    local currentCount = 0
    local histChanged = false

    local function PushHist(kind, name, detail)
        histChanged = true
        table.insert(bucket.rosterHistory, 1, {
            kind = kind,
            name = name,
            detail = detail or "",
            ts = now,
        })
    end

    for i = 1, total do
        local ok, fullName, rankName = pcall(GetGuildRosterInfo, i)
        if ok and fullName then
            local lk, _, dispName = Compat.ParseCharacterFields(Safe.String(fullName))
            if lk and dispName then
                histSeenScratch[lk] = true
                currentCount = currentCount + 1
                local cleanName = dispName:gsub("[\t\r\n]", " ")
                local cleanRank = (Safe.String(rankName) or ""):gsub("[\t\r\n]", " ")
                local prevRaw = snapMembers[lk]
                if not prevRaw then
                    snapMembers[lk] = cleanName .. "\t" .. cleanRank
                    if canDiff then
                        PushHist("JOINED", cleanName, cleanRank)
                    end
                else
                    local _, prevRank = UnpackSnapshotMember(prevRaw)
                    if prevRank ~= cleanRank and cleanRank ~= "" then
                        snapMembers[lk] = cleanName .. "\t" .. cleanRank
                        if canDiff then
                            PushHist("RANK", cleanName, (prevRank ~= "" and (prevRank .. " -> " .. cleanRank)) or cleanRank)
                        end
                    end
                end
            end
        end
    end
    if currentCount == 0 then
        wipe(snapMembers)
        return
    end

    for k, prevRaw in pairs(snapMembers) do
        if not histSeenScratch[k] then
            if canDiff then
                local prevName, prevRank = UnpackSnapshotMember(prevRaw)
                PushHist("LEFT", prevName, prevRank)
            end
            snapMembers[k] = nil
        end
    end

    -- Serialize as one packed string so login does not hold 1,000+ hash-table entries in memory.
    wipe(histPackBuf)
    local nPack = 0
    for lk, pairStr in pairs(snapMembers) do
        local cleanLk = tostring(lk):gsub("[\t\r\n]", "")
        nPack = nPack + 1
        histPackBuf[nPack] = cleanLk .. "\t" .. tostring(pairStr or "\t")
    end
    bucket.rosterSnapshot._initialized = true
    bucket.rosterSnapshot._guild = gName
    bucket.rosterSnapshot.packed = table.concat(histPackBuf, "\n")
    bucket.rosterSnapshot.members = nil
    bucket.rosterSnapshot.updatedAt = now
    wipe(histPackBuf)
    wipe(snapMembers)

    if histChanged and #bucket.rosterHistory > 0 then
        for i = #bucket.rosterHistory, 1, -1 do
            local h = bucket.rosterHistory[i]
            if type(h) ~= "table" or (now - (h.ts or 0)) > (14 * 86400) then
                table.remove(bucket.rosterHistory, i)
            end
        end
        while #bucket.rosterHistory > (Clan.MAX_ROSTER_HISTORY or 40) do
            table.remove(bucket.rosterHistory)
        end
    end
end

function Clan:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, self.PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, self.PREFIX)
    end
    ns.RegisterEvent(self, "CHAT_MSG_ADDON", OnAddonMessage)
    ns.RegisterEvent(self, "CHAT_MSG_GUILD", OnGuildChatPassive)
    ns.RegisterEvent(self, "CHAT_MSG_CHANNEL", OnExternalChatPassive)
    ns.RegisterEvent(self, "CHAT_MSG_SAY", OnExternalChatPassive)
    ns.RegisterEvent(self, "CHAT_MSG_YELL", OnExternalChatPassive)
    ns.RegisterEvent(self, "CALENDAR_UPDATE_EVENT_LIST", function()
        Clan:RefreshGameCalendar(false)
        QueueClanEmit(1.0)
    end)
    ns.RegisterEvent(self, "UPDATE_INSTANCE_INFO", function()
        QueueClanEmit(0.8)
    end)
    ns.RegisterEvent(self, "LFG_UPDATE", function()
        QueueClanEmit(0.8)
    end)
    ns.RegisterEvent(self, "QUEST_LOG_UPDATE", function()
        if IsClanOrLFGVisible() then
            QueueClanEmit(0.8)
        end
    end)
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function()
        if IsClanOrLFGVisible() then
            QueueClanEmit(0.5)
        end
    end)
    ns.RegisterEvent(self, "GUILD_ROSTER_UPDATE", function()
        local uiVisible = IsClanOrLFGVisible()
        if Compat.SyncRosterForeverNames then
            Compat.SyncRosterForeverNames(false, not uiVisible)
        end
        local nowClock = (GetTime and GetTime()) or 0
        if uiVisible or (Clan._lastRosterHistoryAt == nil) or (nowClock - Clan._lastRosterHistoryAt) >= 180 then
            UpdateGuildRosterHistory()
        end
        QueueClanEmit(1.5)
    end)
    ns.RegisterEvent(self, "GUILD_RANKS_UPDATE", function()
        QueueClanEmit(0.5)
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        C_Timer.After(6, function()
            Clan.activeScopeToken = ComputeGuildScopeToken()
            if not Compat.IsModuleEnabled or Compat.IsModuleEnabled("clan") then
                Clan:AutoDetectMyProfessions(false)
                Clan:SendVersionHello()
                Clan:ApplyAutoInstanceStatus()
                Clan:CheckAutoCloseFullDungeonLFG()
                Clan:RefreshGameCalendar(false)
                if ns.db and ns.db.settings and ns.db.settings.clanSync and IsInGuild and IsInGuild() then
                    Clan:RequestIntelSync()
                end
            end
        end)
        C_Timer.After(12.5, function()
            if (not Compat.IsModuleEnabled or Compat.IsModuleEnabled("clan"))
                and (not Compat.IsModuleEnabled or Compat.IsModuleEnabled("buffs"))
                and ns.db and ns.db.settings and ns.db.settings.clanSync and IsInGuild and IsInGuild() then
                Clan:RequestWorldBuffCatchup()
            end
        end)
    end)
    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", function()
        Clan:AutoDetectMyProfessions(false)
    end)
    ns:On("ALTS_UPDATED", function()
        Clan:AutoDetectMyProfessions(false)
    end)
    ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, _, unit)
        if unit and unit ~= "player" then return end
        local newTok = ComputeGuildScopeToken()
        if newTok ~= Clan.activeScopeToken then
            Clan.activeScopeToken = newTok
            Clan.peerVersions = {}
            Clan.guildChatLFG = {}
            wipe(Clan.intelQueue)
            if ns.Spotter and ns.Spotter.OnGuildChanged then
                ns.Spotter:OnGuildChanged()
            end
            ns:Emit("CLAN_UPDATED")
            ns:Emit("CLAN_DIPLOMACY_UPDATED")
        end
    end)
    local function HasUnverifiedGroupMembers()
        if not (Compat.IsInGroup and Compat.IsInGroup()) then return false end
        local isRaid = Compat.IsInRaid and Compat.IsInRaid()
        local prefix = isRaid and "raid" or "party"
        local count = (GetNumGroupMembers and Safe.Number(GetNumGroupMembers())) or 0
        local maxIdx = isRaid and count or math.min(4, count)
        for i = 1, maxIdx do
            local u = prefix .. i
            if UnitExists and Safe.Value(Safe.Call(UnitExists, u)) == true then
                local uGuid = Safe.String(Safe.Call(UnitGUID, u))
                if not Compat.IsMe(nil, uGuid) then
                    local resolved = Compat.ResolveUnitFullName and Compat.ResolveUnitFullName(u, uGuid, nil, true)
                    local fullName = (resolved and resolved.fullName) or Safe.String(Safe.Call(UnitName, u))
                    local lk = fullName and Compat.ParseCharacterFields and select(1, Compat.ParseCharacterFields(fullName))
                    if lk and not ((Clan.peerVersions and Clan.peerVersions[lk]) or (ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(lk))) then
                        return true
                    end
                end
            end
        end
        return false
    end

    for _, grpEv in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
        ns.RegisterEvent(self, grpEv, function()
            if C_Timer and C_Timer.After and not Clan._autoCloseLfgQueued then
                Clan._autoCloseLfgQueued = true
                C_Timer.After(2.0, function()
                    Clan._autoCloseLfgQueued = false
                    Clan:CheckAutoCloseFullDungeonLFG()
                end)
            end
            local grpChan = GetActiveGroupChannel()
            if not grpChan then
                Clan._wasInGroupForVer = false
                if Clan.lastVersionSentByChannel then
                    Clan.lastVersionSentByChannel["PARTY"] = nil
                    Clan.lastVersionSentByChannel["RAID"] = nil
                    Clan.lastVersionSentByChannel["INSTANCE_CHAT"] = nil
                end
                return
            end
            if not Clan._wasInGroupForVer then
                Clan._wasInGroupForVer = true
            end
            if Clan._groupVerPending then return end
            Clan._groupVerPending = true
            C_Timer.After(2.8, function()
                Clan._groupVerPending = false
                local ch = GetActiveGroupChannel()
                if ch and HasUnverifiedGroupMembers() then
                    Clan:SendVersionHello(ch)
                end
            end)
        end)
    end

    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        C_Timer.After(2.0, function()
            Clan:ApplyAutoInstanceStatus()
        end)
    end)

    ns.RegisterEvent(self, "LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
        QueueClanEmit(0.8)
        if Clan.SyncOfficialActiveLfg then
            Clan:SyncOfficialActiveLfg()
        end
    end)

    ns.RegisterEvent(self, "LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
        if Clan.ScanOfficialLfgResults then
            Clan:ScanOfficialLfgResults()
        end
    end)

    ns:On("SETTINGS_UPDATED", function()
        local s = ns.db and ns.db.settings
        if s and (s.embedLfgWindow == false or s.globalChatLfgScan == false) then
            if Clan.globalChatLFG and next(Clan.globalChatLFG) ~= nil then
                wipe(Clan.globalChatLFG)
                ns:Emit("CLAN_UPDATED")
            end
        end
    end)

    Clan:ScheduleNextEventReminderCheck()
end
