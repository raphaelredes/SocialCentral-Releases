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
    lastVersionSentAt = 0,
    lastReqReplyAt = 0,
    lastIntelReplyAt = 0,
    lastCalendarRefreshAt = 0,
    isStoppedThisSession = false,
    throttledCount = 0,
    latestRemoteVersion = nil,
    latestReportedBy = nil,
    notifiedVersion = nil,
    peerVersions = {},
    lfgAlertCooldowns = {},
    externalLFG = {},
    calendarEvents = {},
    preferredRightView = nil,
    intelQueue = {},
    activeScopeToken = nil,
}

local function IsClanOrLFGVisible()
    if _G.SocialCentralFrame and _G.SocialCentralFrame.IsShown and _G.SocialCentralFrame:IsShown() then
        return true
    end
    if ns.LFGFrameTab and ns.LFGFrameTab.subPanel and ns.LFGFrameTab.subPanel.IsShown and ns.LFGFrameTab.subPanel:IsShown() then
        return true
    end
    return false
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
    { id = "MPLUS", labelKey = "Mythic+ / Dungeons" },
    { id = "RAID", labelKey = "Raid Ready" },
    { id = "PVP", labelKey = "PvP / Arena" },
    { id = "LEVELING", labelKey = "Leveling / Questing" },
    { id = "CRAFTING", labelKey = "Crafting / Professions" },
    { id = "BUSY", labelKey = "Busy" },
}

Clan.EVENT_CATEGORIES = {
    { id = "DUNGEON", labelKey = "Dungeon / M+" },
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
    { id = "INSCRIPTION", labelKey = "Inscription" },
    { id = "JEWELCRAFTING", labelKey = "Jewelcrafting" },
    { id = "LEATHERWORKING", labelKey = "Leatherworking" },
    { id = "MINING", labelKey = "Mining" },
    { id = "SKINNING", labelKey = "Skinning" },
    { id = "TAILORING", labelKey = "Tailoring" },
    { id = "COOKING", labelKey = "Cooking" },
    { id = "FIRST_AID", labelKey = "First Aid" },
}

Clan.DUNGEON_PRESETS = {
    { id = "MPLUS_KEY", labelKey = "Mythic+ Keystone", category = "DUNGEON" },
    { id = "RANDOM_HC", labelKey = "Random Heroic Dungeon", category = "DUNGEON" },
    { id = "RANDOM_NORM", labelKey = "Normal / Leveling Dungeon", category = "DUNGEON" },
    { id = "TIMEWALKING", labelKey = "Timewalking Dungeon", category = "DUNGEON" },
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
    if isVersionMsg then
        if not (ns.db and ns.db.settings and ns.db.settings.versionCheck ~= false) then
            return false
        end
        if (now - (self.lastVersionSentAt or 0)) < self.VERSION_MIN_INTERVAL then
            return false
        end
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
                self.throttledCount = self.throttledCount + 1
                if self.throttledCount >= 3 then
                    self.isStoppedThisSession = true
                end
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
    local payload = ("WB~%s~%d"):format(syncId, stamp)
    return TransmitAddonMessage(self, payload, "GUILD", false)
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

local function SendExternalLFGPacket(self, payload, channel, target)
    if self.isStoppedThisSession or self:IsMessagingLocked() then return false end
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then return false end
    local sendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not sendFn then return false end
    if type(payload) ~= "string" or payload == "" or #payload > self.MAX_PAYLOAD_BYTES then return false end
    if payload:find("[%c|]") then return false end

    local ok, result
    if channel == "WHISPER" then
        if type(target) ~= "string" or target == "" then return false end
        ok, result = pcall(sendFn, self.PREFIX, payload, "WHISPER", target)
    else
        ok, result = pcall(sendFn, self.PREFIX, payload, channel)
    end
    if not ok then return false end

    if Enum and Enum.SendAddonMessageResult and type(result) == "number" then
        for name, value in pairs(Enum.SendAddonMessageResult) do
            if value == result and name:find("Throttle") then
                self.throttledCount = self.throttledCount + 1
                if self.throttledCount >= 3 then
                    self.isStoppedThisSession = true
                end
                return false
            end
        end
    end
    return true
end

local function CollectExternalLFGRecipients(self, maxCount)
    local targets = {}
    local seen = {}
    local limit = maxCount or 6

    local function PushTarget(rawName)
        if #targets >= limit then return end
        local clean = Compat.CleanPayloadField and Compat.CleanPayloadField(rawName or "", 40) or Safe.String(rawName)
        if not clean or clean == "" or Compat.IsMe(clean) then return end
        local parsed = Compat.ParseCharacterName and Compat.ParseCharacterName(clean)
        local key = (parsed and parsed.lookupKey) or clean:lower()
        if seen[key] then return end
        seen[key] = true
        table.insert(targets, clean)
    end

    if type(Store.social) == "table" then
        for _, row in pairs(Store.social) do
            if #targets >= limit then break end
            if type(row) == "table" and row.online and row.sources and row.sources.friend == true and not row.sources.guild then
                PushTarget(row.characterName or row.displayName)
            end
        end
    end

    if ns.Chat and type(ns.Chat.sessionPeers) == "table" then
        for peerKey, peer in pairs(ns.Chat.sessionPeers) do
            if #targets >= limit then break end
            if type(peer) == "table" and peer.displayName and not Compat.IsGuildMember(peer.displayName, nil, peer.displayName) then
                PushTarget(peer.targetName or peer.displayName)
            end
        end
    end

    if type(Store.nearby) == "table" then
        local now = time()
        for _, nRow in pairs(Store.nearby) do
            if #targets >= limit then break end
            if type(nRow) == "table" and (now - (nRow.lastSeen or 0)) <= 600 and nRow.guild and self:IsAlliedGuild(nRow.guild) then
                PushTarget(nRow.displayName)
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

    for _, recipient in ipairs(CollectExternalLFGRecipients(self, 6)) do
        if SendExternalLFGPacket(self, payload, "WHISPER", recipient) then
            anySent = true
        end
    end
    return anySent
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

local function ProcessPeerVersion(senderDisplay, senderLookupKey, remoteVer, chatType)
    if not IsSaneRemoteSemVer(remoteVer) then return end

    Clan.peerVersions = Clan.peerVersions or {}
    Clan.peerVersions[senderLookupKey] = remoteVer

    if ns.Chat and ns.Chat.MarkPeerVerified then
        ns.Chat:MarkPeerVerified(senderDisplay, nil, remoteVer, chatType or "clan")
    end

    if chatType == "GUILD" and IsInGuild and IsInGuild() then
        local bucket = Store:GetClanScopeData()
        local peer = bucket.peers[senderLookupKey] or { displayName = senderDisplay, lookupKey = senderLookupKey }
        peer.displayName = senderDisplay
        peer.version = remoteVer
        peer.updatedAt = time()
        bucket.peers[senderLookupKey] = peer
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
            ns:Emit("VERSION_UPDATE_FOUND", remoteVer)
        end
    end
end

local function EnsureEventRecord(bucket, eventId)
    local evt = bucket.events[eventId]
    if evt and type(evt.signups) ~= "table" then
        evt.signups = {}
    end
    return evt
end

function Clan:SetMyStatus(tagId, note)
    if not IsValidTag(tagId) then tagId = "NONE" end
    local bucket = Store:GetClanScopeData()
    local cleanNote = Compat.CleanPayloadField(note or "", 36)
    bucket.myTag = tagId
    bucket.myNote = cleanNote

    local sent = self:SendGuildSync("TAG~" .. (ns.version or "0.0.0") .. "~" .. tagId .. "~" .. cleanNote)
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
                    Clan.throttledCount = (Clan.throttledCount or 0) + 1
                    if Clan.throttledCount >= 3 then
                        Clan.isStoppedThisSession = true
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

function Clan:CanEditClanManagement()
    local isOfficer = IsPlayerGuildOfficer()
    if isOfficer then
        return true, true
    end
    if not (IsInGuild and IsInGuild()) then
        return false, false
    end
    local bucket = Store:GetClanScopeData()
    local info = bucket.clanInfo
    return (info and info.editMode == "ALL") and true or false, false
end

function Clan:IsGuildLeader()
    if not (IsInGuild and IsInGuild()) then
        return false
    end
    if IsGuildLeader and Safe.Value(Safe.Call(IsGuildLeader)) == true then
        return true
    end
    if C_GuildInfo and C_GuildInfo.GetGuildRankOrder and UnitGUID then
        local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
        if myGuid then
            local rank = Safe.Number(Safe.Call(C_GuildInfo.GetGuildRankOrder, myGuid))
            if rank and (rank == 0 or rank == 1) then
                return true
            end
        end
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
    bucket.alliance.enabled = enabled and true or false
    bucket.alliance.name = Compat.CleanPayloadField(name or "", 40)
    bucket.alliance.token = Compat.CleanPayloadField(token or "", 32)
    bucket.alliance.accessMode = (accessMode == "ALL") and "ALL" or "WHITELIST"
    bucket.alliance.updatedAt = time()
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

function Clan:SendAllianceChat(rawText)
    if not (IsInGuild and IsInGuild()) then
        ns:Print(L["No guild"])
        return false
    end
    if not self:IsMemberAllianceAuthorized() then
        ns:Print(L["You do not have permission to use Alliance Chat."])
        return false
    end
    local cleanText = Compat.CleanPayloadField(rawText or "", 140)
    if cleanText == "" then return false end

    local myGuild = Safe.String(Safe.Call(GetGuildInfo, "player")) or ""
    local myName = ResolveSelfIdentity()
    local _, myClass = Safe.Call(UnitClass, "player")

    local payload = string.format("ALM~%s~%s~%s~%s", Compat.CleanPayloadField(myGuild, 32), Compat.CleanPayloadField(myName, 25), myClass or "", cleanText)
    self:SendGuildSync(payload)
    return true
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
    if isOfficer and (editMode == "ALL" or editMode == "OFFICERS") then
        info.editMode = editMode
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
    end
    ns:Emit("CLAN_UPDATED")
    ns:Emit("CLAN_DIPLOMACY_UPDATED")
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
    local canEdit = inGuild and self:CanEditClanManagement() or false
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
        localOnly = not canEdit,
        rev = nextRev,
        updatedAt = time(),
    }

    if canEdit then
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
    else
        ns:Print(L["Saved locally in your Clan radar (officer mode prevents overwriting guild sync)."])
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

    local canEdit = self:CanEditClanManagement()
    if not existing.localOnly and not canEdit then
        ns:Print(L["Only guild officers can remove synced Clan Diplomacy entries."])
        return false
    end

    bucket.diplomacy.guilds[guildKey] = nil
    local nextRev = math.max(time(), (bucket.diplomacy.rev or 0) + 1)
    bucket.diplomacy.rev = nextRev

    if canEdit and not existing.localOnly then
        local tok = ComputeGuildScopeToken()
        if tok ~= "" and ns.db and ns.db.settings and ns.db.settings.clanSync then
            EnqueueIntelPacket(("CDEL~%s~%s~%d~%s"):format(tok, ns.version or "0.0.0", nextRev, guildKey:sub(1, 32)))
        end
    end

    ns:Emit("CLAN_UPDATED")
    ns:Emit("CLAN_DIPLOMACY_UPDATED")
    return true
end

function Clan:BroadcastFullIntel()
    if not (IsInGuild and IsInGuild()) or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        return false
    end
    local tok = ComputeGuildScopeToken()
    if tok == "" then return false end

    local info = self:GetClanInfo()
    local canEdit = self:CanEditClanManagement()
    if info.summary ~= "" or info.rules ~= "" or info.schedule ~= "" or info.contacts ~= "" then
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
    if canEdit then
        local sentCount = 0
        for _, g in ipairs(self:GetDiplomacyList("all")) do
            if not g.localOnly and sentCount < 10 then
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

function Clan:RequestIntelSync()
    if not (IsInGuild and IsInGuild()) or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        return false
    end
    local tok = ComputeGuildScopeToken()
    if tok == "" then return false end
    local info = self:GetClanInfo()
    local bucket = Store:GetClanScopeData()
    return self:SendGuildSync(("CREQ~%s~%d~%d"):format(tok, info.rev or 0, (bucket.diplomacy and bucket.diplomacy.rev) or 0))
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
    if roleToken == "TANK" or roleToken == "HEALER" then
        return roleToken, specName
    end
    return "DPS", specName
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
    self:SendGuildSync(payload)
    ns:Emit("CLAN_UPDATED")
    return true, bucket.events[eventId]
end

function Clan:ToggleEventOpen(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local _, myKey = ResolveSelfIdentity()
    if not (myKey and evt.creatorKey == myKey) then
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

    self:SendGuildSync(("SIG~%s~%s~%s"):format(Compat.CleanPayloadField(eventId, 16), role, Safe.String(myClass) or ""))
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:RemoveEvent(eventId)
    local bucket = Store:GetClanScopeData()
    local evt = bucket.events[eventId]
    if not evt then return false end
    local _, myKey = ResolveSelfIdentity()
    local isCreator = (myKey ~= nil and evt.creatorKey == myKey)

    bucket.events[eventId] = nil
    if isCreator then
        self:SendGuildSync("DEL~" .. Compat.CleanPayloadField(eventId, 16))
    end
    ns:Emit("CLAN_UPDATED")
    return true
end

function Clan:RequestClanSync()
    if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        ns:Print(L["Enable Clan guild sync (opt-in) in Settings or above to sync with guildmates."])
        return false
    end
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
    inscription = "INSCRIPTION", escrivania = "INSCRIPTION", inscricao = "INSCRIPTION", inscripcion = "INSCRIPTION",
    jewelcrafting = "JEWELCRAFTING", joalheria = "JEWELCRAFTING", joyeria = "JEWELCRAFTING",
    leatherworking = "LEATHERWORKING", couraria = "LEATHERWORKING", peleteria = "LEATHERWORKING", coureiro = "LEATHERWORKING",
    mining = "MINING", mineracao = "MINING", mineria = "MINING",
    skinning = "SKINNING", esfolamento = "SKINNING", desuello = "SKINNING",
    tailoring = "TAILORING", alfaiataria = "TAILORING", sastreria = "TAILORING",
    cooking = "COOKING", culinaria = "COOKING", cocina = "COOKING",
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
    { pat = "%f[%w]inscrip", id = "INSCRIPTION" },
    { pat = "%f[%w]escriv", id = "INSCRIPTION" },
    { pat = "%f[%w]inscric", id = "INSCRIPTION" },
    { pat = "%f[%w]jewel", id = "JEWELCRAFTING" },
    { pat = "%f[%w]joalh", id = "JEWELCRAFTING" },
    { pat = "%f[%w]joyer", id = "JEWELCRAFTING" },
    { pat = "%f[%w]jc%f[%W]", id = "JEWELCRAFTING" },
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
                            isPrimary = (abandonable or (inProfHeader and pid ~= "COOKING" and pid ~= "FIRST_AID")) and true or false,
                        }
                    end
                end
            end
        end
    end
    if #list == 0 and ns.db and ns.db.alts and Compat.CharacterKey then
        local cur = ns.db.alts[Compat.CharacterKey()]
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
                if ap.isPrimary ~= false and pid ~= "COOKING" and pid ~= "FIRST_AID" then
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

function Clan:GetProfessionsList(query, profFilter, sourceFilter)
    local nowClock = (GetTime and GetTime()) or 0
    if not self._myDetectedPrimary or (nowClock - (self._lastProfAutoDetectAt or 0)) >= 15 then
        self:AutoDetectMyProfessions(false)
    end
    local bucket = Store:GetClanScopeData()
    local q = (type(query) == "string" and query ~= "") and FoldProfText(query) or nil
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
    local curCharKey = Compat.CharacterKey and Compat.CharacterKey() or ""
    if Store and Store.GetAltsList then
        for _, alt in ipairs(Store:GetAltsList()) do
            if type(alt) == "table" and alt.key ~= curCharKey and type(alt.professions) == "table" and #alt.professions > 0 then
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
                            if ap.isPrimary ~= false and pid ~= "COOKING" and pid ~= "FIRST_AID" then
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
                    if not hay:find(q, 1, true) then
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

local DUNGEON_KEYWORDS = {
    "%f[%w]dg%f[%W]", "masmorra", "mazmorra", "calabou", "calabozo", "dungeon",
    "mythic", "mitic", "m%+", "%+%d+", "heroic", "heroic[ao]", "%f[%w]hc%f[%W]",
    "chave", "pedra", "piedra", "keystone", "%f[%w]key%f[%W]", "timewalking", "caminhada",
    "%f[%w]cam%f[%W]", "delve", "follower", "deadmines", "scarlet", "strath", "scholo",
    "brd", "ubrs", "lbrs", "maraudon", "dire maul", "razorfen", "gnomer",
    "zul'farrak", "%f[%w]zf%f[%W]", "sunken", "wailing", "shadowfang", "%f[%w]sfk%f[%W]", "%f[%w]sm%f[%W]",
    "%f[%w]rfc%f[%W]", "%f[%w]wc%f[%W]", "stockade", "uldaman", "blackrock",
}

local function IsDungeonLFGText(text, category)
    if category == "DUNGEON" then
        return true
    end
    if type(text) ~= "string" or text == "" then
        return false
    end
    local low = text:lower()
    for _, pat in ipairs(DUNGEON_KEYWORDS) do
        if low:find(pat) then
            return true
        end
    end
    return false
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

function Clan:MaybeNotifyClanLFG(lookupKey, displayName, classFile, summaryText, activityText, isDungeon, sourceType)
    local s = ns.db and ns.db.settings
    if not (s and s.clanLfgAlertEnabled) then return false end
    if not lookupKey or not displayName or Compat.IsMe(displayName) then return false end
    if s.clanLfgAlertDungeonsOnly ~= false and not isDungeon then
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

    local hex = Compat.ClassHex(classFile)
    local nameCol = hex .. displayName .. "|r"
    local cleanMsg = Compat.CleanPayloadField(summaryText ~= "" and summaryText or activityText or "LFG", 90)
    local wLink = "|Haddon:SCentral:w:" .. displayName .. "|h|cff58a6ff[" .. L["Chat"] .. "]|r|h"
    local cLink = "|Haddon:SCentral:clanlfg|h|cfff2c94c[" .. L["Clan LFG"] .. "]|r|h"
    ns:Print(("|cff3fb950[%s]|r %s: %s %s %s"):format(L["Dungeon LFG Alert"], nameCol, cleanMsg, wLink, cLink))

    if s.clanLfgAlertSound ~= false and PlaySound and SOUNDKIT then
        local kit = SOUNDKIT.READY_CHECK or SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_QUEST_LOG_OPEN
        if kit then
            pcall(PlaySound, kit, "Master")
        end
    end

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
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        mplusScore = Safe.Number(Safe.Call(C_ChallengeMode.GetOverallDungeonScore)) or 0
    end

    local keyLvl, keyMapId, keyName = 0, nil, nil
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
        keyLvl = Safe.Number(Safe.Call(C_MythicPlus.GetOwnedKeystoneLevel)) or 0
    end
    if keyLvl > 0 and C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        keyMapId = Safe.Number(Safe.Call(C_MythicPlus.GetOwnedKeystoneChallengeMapID))
        if keyMapId and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            keyName = Safe.String(Safe.Call(C_ChallengeMode.GetMapUIInfo, keyMapId))
        end
    end

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
        canEditMOTD = (CanEditMOTD and Safe.Value(Safe.Call(CanEditMOTD)) == true) or false,
        canEditCalendar = (CanEditGuildEvent and Safe.Value(Safe.Call(CanEditGuildEvent)) == true) or false,
        canInviteGuild = (C_GuildInfo and C_GuildInfo.CanGuildInvite and Safe.Value(Safe.Call(C_GuildInfo.CanGuildInvite)) == true) or (CanGuildInvite and Safe.Value(Safe.Call(CanGuildInvite)) == true) or false,
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

    local curKey = Compat.CharacterKey and Compat.CharacterKey() or ""
    if Store and Store.GetAltsList then
        for _, alt in ipairs(Store:GetAltsList()) do
            if type(alt) == "table" and alt.key ~= curKey and type(alt.lockouts) == "table" then
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
    if sum.premadeTitle and sum.premadeTitle ~= "" then
        table.insert(list, {
            id = "ACTIVE_PREMADE",
            label = "[Premade] " .. sum.premadeTitle,
            activity = sum.premadeTitle,
            keyLvl = sum.keystoneLevel or 0,
            category = "DUNGEON",
            mode = "LFM",
        })
    end
    if (sum.keystoneLevel or 0) > 0 and sum.keystoneName then
        table.insert(list, {
            id = "OWN_KEY",
            label = string.format("+%d %s", sum.keystoneLevel, sum.keystoneName),
            activity = sum.keystoneName,
            keyLvl = sum.keystoneLevel,
            category = "DUNGEON",
            mode = "LFM",
        })
    end
    for _, item in ipairs(self.DUNGEON_PRESETS) do
        table.insert(list, {
            id = item.id,
            label = L[item.labelKey],
            activity = L[item.labelKey],
            keyLvl = 0,
            category = item.category or "DUNGEON",
            mode = "LFG",
        })
    end
    return list
end

function Clan:PostLFG(mode, role, activity, keyLvl, note)
    local cleanMode = (mode == "LFM") and "LFM" or "LFG"
    local cleanRole = (role == "TANK" or role == "HEALER" or role == "DPS" or role == "DAMAGER" or role == "ANY") and role or self:GetMySpecAndRole()
    if cleanRole == "DAMAGER" then cleanRole = "DPS" end
    local cleanAct = Compat.CleanPayloadField(activity or "", 40)
    if cleanAct == "" then
        cleanAct = L["Random / Any Dungeon"]
    end
    local cleanKey = math.max(0, math.min(99, tonumber(keyLvl) or 0))
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
        isDungeon = IsDungeonLFGText(cleanAct .. " " .. cleanNote, (cleanKey > 0) and "DUNGEON" or nil),
        updatedAt = time(),
    }
    bucket.myTag = (cleanKey > 0) and "MPLUS" or "LFG"
    bucket.myNote = Compat.CleanPayloadField((cleanKey > 0 and ("+" .. cleanKey .. " ") or "") .. cleanAct, 36)

    local payload = ("LFG~%s~%s~%s~%s~%d~%d~%s"):format(ns.version or "0.0.0", cleanMode, cleanRole, cleanAct, cleanKey, iLvl, cleanNote)
    local sent = self:SendGuildSync(payload)

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

    if (ns.db and ns.db.settings and ns.db.settings.clanSync) and not sent and IsInGuild and IsInGuild() then
        local waitRem = math.ceil(math.max(0, self.MIN_SEND_INTERVAL - (GetTime() - (self.lastSyncSentAt or 0))))
        if waitRem > 0 then
            ns:Print(L["Clan LFG saved locally; guild broadcast ready in %ds."]:format(waitRem))
        end
    end
    ns:Emit("CLAN_UPDATED")
    return true, bucket.lfg[myParsed.lookupKey]
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

function Clan:GetClanLFGList(query, dungeonsOnly, sourceFilter)
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
    if filterMode ~= "CLAN" and filterMode ~= "ALLY" and filterMode ~= "FRIENDS" and filterMode ~= "PUBLIC_CHAT" then
        filterMode = "ALL"
    end

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

        if filterMode == "CLAN" and not item.isClan then
            return
        elseif filterMode == "ALLY" and not item.isAllied then
            return
        elseif filterMode == "FRIENDS" and not (item.isFriend or item.isWatchlist or item.hasFriendOrWatchlistSignup) then
            return
        elseif filterMode == "PUBLIC_CHAT" and item.sourceType ~= "PUBLIC_CHAT" then
            return
        end

        if dungeonsOnly and not item.isDungeon then
            return
        end
        if q then
            local hay = (
                (item.displayName or "") .. " " ..
                (item.guild or "") .. " " ..
                (item.activity or "") .. " " ..
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

            local hasFW = false
            local fwNames = {}
            for sKey, sRec in pairs(evt.signups or {}) do
                if type(sRec) == "table" and sRec.role ~= "DECLINE" then
                    local _, _, sFriend, sWatch = self:GetPlayerRelationshipFlags(sKey, sRec.name)
                    if sFriend or sWatch then
                        hasFW = true
                        table.insert(fwNames, sRec.name or sKey)
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
                activity = evt.title or "?",
                keyLvl = 0,
                ilvl = 0,
                note = needText .. " | " .. (evt.whenText or L["Now"]),
                isDungeon = IsDungeonLFGText(evt.title or "", evt.category),
                hasFriendOrWatchlistSignup = hasFW,
                friendOrWatchlistNames = (#fwNames > 0) and table.concat(fwNames, ", ") or "",
                updatedAt = evt.updatedAt or evt.createdAt or 0,
                _forceClan = true,
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
                activity = peer.tag == "MPLUS" and L["Mythic+ / Dungeons"] or L["LFG (Looking for Group)"],
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
                mode = row.text and row.text:lower():find("lfg") and "LFG" or "LFM",
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

    if filterMode == "PUBLIC_CHAT" then
        self.globalChatLFG = self.globalChatLFG or {}
        for key, pub in pairs(self.globalChatLFG) do
            if type(pub) == "table" and (now - (pub.updatedAt or 0)) <= 600 then
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
            elseif type(pub) == "table" and (now - (pub.updatedAt or 0)) > 600 then
                self.globalChatLFG[key] = nil
            end
        end
    end

    table.sort(out, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        if a.online ~= b.online then return a.online end
        local aRel = (a.isFriend or a.isWatchlist or a.hasFriendOrWatchlistSignup) and 1 or 0
        local bRel = (b.isFriend or b.isWatchlist or b.hasFriendOrWatchlistSignup) and 1 or 0
        if aRel ~= bRel then return aRel > bRel end
        if a.isClan ~= b.isClan then return a.isClan end
        return (a.updatedAt or 0) > (b.updatedAt or 0)
    end)
    return out
end

function Clan:GetMergedGuildMembers(query)
    local bucket = Store:GetClanScopeData()
    local q = (type(query) == "string" and query ~= "") and query:lower() or nil
    local out = {}
    local seen = {}
    local nowTs = time()

    local function PushIfMatches(row)
        if not q then
            out[#out + 1] = row
            return
        end
        local hay = ((row.displayName or "") .. " " .. (row.rankName or "") .. " " .. (row.area or "") .. " " .. (row.note or "") .. " " .. (row.tag or "")):lower()
        if hay:find(q, 1, true) then
            out[#out + 1] = row
        end
    end

    if type(Store.social) == "table" then
        for _, live in pairs(Store.social) do
            if type(live) == "table" and live.sources and live.sources.guild == true then
                local peer = live.lookupKey and bucket.peers[live.lookupKey]
                local row = {
                    lookupKey = live.lookupKey,
                    displayName = live.displayName,
                    version = peer and peer.version or nil,
                    tag = peer and IsValidTag(peer.tag) and peer.tag or "NONE",
                    note = (peer and peer.note and peer.note ~= "" and peer.note) or live.note or "",
                    rankName = live.rankName or "",
                    level = live.level,
                    classFile = live.classFile,
                    area = live.area or "",
                    online = true,
                    hasAddon = (peer ~= nil) or (ns.Chat and ns.Chat.IsLookupKeyVerified and ns.Chat:IsLookupKeyVerified(live.lookupKey)),
                    updatedAt = (peer and peer.updatedAt) or nowTs,
                }
                if live.lookupKey then seen[live.lookupKey] = true end
                PushIfMatches(row)
            end
        end
    end

    for key, peer in pairs(bucket.peers or {}) do
        if not seen[key] then
            PushIfMatches({
                lookupKey = key,
                displayName = peer.displayName or key,
                version = peer.version,
                tag = IsValidTag(peer.tag) and peer.tag or "NONE",
                note = peer.note or "",
                rankName = "",
                level = nil,
                classFile = peer.classFile,
                area = "",
                online = false,
                hasAddon = true,
                updatedAt = peer.updatedAt or 0,
            })
        end
    end

    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.hasAddon ~= b.hasAddon then return a.hasAddon end
        if a.tag ~= b.tag and (a.tag == "LFG" or a.tag == "MPLUS" or b.tag == "LFG" or b.tag == "MPLUS") then
            return (a.tag == "LFG" or a.tag == "MPLUS")
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
                TransmitAddonMessage(Clan, "VR~" .. ns.version, targetChannel, true)
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

    -- Cross-guild Allied / Friend / Group LFG exchange (strictly opt-in via clanSync)
    if cmd == "ALFG" or cmd == "ALFX" then
        if not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
            return
        end
        if ns.Chat and ns.Chat.MarkPeerVerified then
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

        if chatType == "WHISPER" and isAllied and not alreadyRelayed and IsInGuild and IsInGuild() and (GetTime() - (Clan.lastAlfgRelayAt or 0)) >= 15 then
            Clan.lastAlfgRelayAt = GetTime()
            local relayPayload = cleanText
            local relayDelay = 1.0 + math.random() * 1.5
            C_Timer.After(relayDelay, function()
                if not Clan:IsMessagingLocked() then
                    Clan:SendGuildSync(relayPayload)
                end
            end)
        end
        QueueClanEmit(0.6)
        return
    end

    -- All Clan Hub interactive features require GUILD + explicit clanSync opt-in.
    if chatType ~= "GUILD" or not (ns.db and ns.db.settings and ns.db.settings.clanSync) then
        return
    end

    local bucket = Store:GetClanScopeData()
    local now = time()

    if ns.Chat and ns.Chat.MarkPeerVerified then
        ns.Chat:MarkPeerVerified(parsed.displayName, nil, nil, "GUILD")
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
            end)
        end

    elseif cmd == "LFG" then
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
                creator = parsed.displayName,
                creatorKey = parsed.lookupKey,
                createdAt = existing and existing.createdAt or now,
                updatedAt = now,
                signups = existing and existing.signups or {},
            }
            if isOpen and not existing then
                local isDng = IsDungeonLFGText(title, cat)
                Clan:MaybeNotifyClanLFG(parsed.lookupKey, parsed.displayName, nil, title .. " (" .. (whenText ~= "" and whenText or L["Now"]) .. ")", title, isDng, "EVT")
            end
            QueueClanEmit(0.6)
        end

    elseif cmd == "EVS" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local evt = bucket.events[eventId]
        if evt and evt.creatorKey == parsed.lookupKey then
            evt.isOpen = parts[3] ~= "0"
            evt.updatedAt = now
            QueueClanEmit(0.6)
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
        local evt = EnsureEventRecord(bucket, eventId)
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
            QueueClanEmit(0.5)
        end

    elseif cmd == "DEL" then
        local eventId = Compat.CleanPayloadField(parts[2] or "", 16)
        local evt = bucket.events[eventId]
        if evt and evt.creatorKey == parsed.lookupKey then
            bucket.events[eventId] = nil
            QueueClanEmit(0.5)
        end

    elseif cmd == "CINF" or cmd == "CINF2" or cmd == "CDIP" or cmd == "CDEL" or cmd == "CREQ" then
        -- Strict multi-layer anti-leakage guard: scope token + active guild roster verification
        local myTok = ComputeGuildScopeToken()
        local pktTok = parts[2] or ""
        if myTok == "" or pktTok ~= myTok or not IsSenderConfirmedInGuild(parsed.lookupKey) then
            return
        end

        if cmd == "CINF" then
            local ver = parts[3]
            local rev = tonumber(parts[4]) or 0
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
            local ver = parts[3]
            local rev = tonumber(parts[4]) or 0
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
            local rev = tonumber(parts[4]) or 0
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
            local myInfoRev = (bucket.clanInfo and bucket.clanInfo.rev) or 0
            local myDipRev = (bucket.diplomacy and bucket.diplomacy.rev) or 0
            if (myInfoRev > peerInfoRev or myDipRev > peerDipRev) and (GetTime() - (Clan.lastIntelReplyAt or 0)) >= 25 then
                Clan.lastIntelReplyAt = GetTime()
                local d = 1.0 + math.random() * 2.5
                C_Timer.After(d, function()
                    if ComputeGuildScopeToken() == myTok then
                        Clan:BroadcastFullIntel()
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
            local guildTag = targetGuild ~= "" and (" <" .. targetGuild .. ">") or ""
            local lvlTag = lvl > 0 and (" (Lv " .. lvl .. ")") or ""
            local locTag = (zone ~= "" and coords ~= "") and (" - " .. zone .. " (" .. coords .. ")") or ""
            ns:Print("|cffff4444[SocialCentral Scout] %s%s%s%s (%s)|r", targetName, guildTag, lvlTag, locTag, parsed.displayName)
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
                pcall(PlaySound, SOUNDKIT.RAID_WARNING)
            end
        end

    elseif cmd == "WB" then
        local syncId = parts[2]
        local ts = tonumber(parts[3])
        if VALID_WB_SYNC_IDS[syncId] and ts and ts > 0 and ns.WorldBuffs and ns.WorldBuffs.ReceiveSyncedDrop then
            ns.WorldBuffs:ReceiveSyncedDrop(syncId, ts, parsed.displayName)
        end

    elseif cmd == "ALM" then
        local senderGuild = Compat.CleanPayloadField(parts[2] or "", 32)
        local authorName = Compat.CleanPayloadField(parts[3] or "", 25)
        local classFile = parts[4]
        local msgText = Compat.CleanPayloadField(parts[5] or "", 140)
        if ns.Chat and ns.Chat.ReceiveAllianceMessage then
            ns.Chat:ReceiveAllianceMessage(senderGuild, authorName, classFile, msgText)
        end
    end
end

local LFG_PATTERNS = {
    "%f[%w]lfm%f[%W]", "%f[%w]lfg%f[%W]", "lf%d+m", "precis", "falta", "procuro", "busco",
    "bora", "alguem", "alguien", "tank", "heal", "dps", "%f[%w]dg%f[%W]", "masmorra",
    "mazmorra", "dungeon", "mythic", "m%+", "chave", "pedra", "raid", "raide", "boss",
}

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
    local matched = false
    for _, pat in ipairs(LFG_PATTERNS) do
        if low:find(pat) then
            matched = true
            break
        end
    end
    if not matched then return end

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

local function OnExternalChatPassive(_, _, text, sender, ...)
    if Safe.IsSecret(text) or Safe.IsSecret(sender) then return end
    local rawMsg = Safe.String(text)
    local cleanSender = Safe.String(sender)
    if not rawMsg or not cleanSender then return end

    local cleanMsg
    if rawMsg:find("|", 1, true) then
        cleanMsg = Compat.CleanInput(rawMsg)
        if not cleanMsg then return end
    end

    local scanLow = (cleanMsg or rawMsg):lower()
    local matched = false
    for _, pat in ipairs(LFG_PATTERNS) do
        if scanLow:find(pat) then
            matched = true
            break
        end
    end
    if not matched then return end

    cleanMsg = cleanMsg or Compat.CleanInput(rawMsg)
    local cleanGuid = Safe.String(select(10, ...))
    local parsed = Compat.ParseCharacterName(cleanSender)
    if not cleanMsg or not parsed or Compat.IsMe(parsed.displayName, cleanGuid) then return end

    local isClan, isAllied, isFriend, isWatchlist, resolvedGuild = Clan:GetPlayerRelationshipFlags(
        parsed.lookupKey,
        parsed.displayName,
        cleanGuid,
        nil
    )
    local s = ns.db and ns.db.settings
    local scanGlobal = (not s) or (s.globalChatLfgScan ~= false)
    if (not scanGlobal) and not (isAllied or isFriend or isWatchlist or isClan) then
        return
    end

    local low = cleanMsg:lower()
    local isDng = IsDungeonLFGText(cleanMsg, nil)
    local msgMode = low:find("%f[%w]lfg%f[%W]") and "LFG" or "LFM"
    local roleHint = "ANY"
    if low:find("%f[%w]tank%f[%W]") then
        roleHint = "TANK"
    elseif low:find("heal") then
        roleHint = "HEALER"
    elseif low:find("%f[%w]dps%f[%W]") then
        roleHint = "DPS"
    end
    local nowTs = time()

    if scanGlobal then
        Clan.globalChatLFG = Clan.globalChatLFG or {}
        local chRaw = Safe.String(select(2, ...)) or ""
        local chShort = chRaw:match("^%d+%.%s*(.+)$") or chRaw
        Clan.globalChatLFG[parsed.lookupKey] = {
            sourceType = "PUBLIC_CHAT",
            lookupKey = parsed.lookupKey,
            guid = cleanGuid,
            displayName = parsed.displayName,
            guild = resolvedGuild,
            channel = Compat.CleanPayloadField and Compat.CleanPayloadField(chShort, 28) or "",
            mode = msgMode,
            role = roleHint,
            activity = (chShort ~= "" and ("[" .. chShort .. "] ") or "") .. cleanMsg:sub(1, 36),
            note = cleanMsg:sub(1, 130),
            isDungeon = isDng,
            updatedAt = nowTs,
        }
        PruneAndBoundByTimestamp(Clan.globalChatLFG, Clan.MAX_GLOBAL_CHAT_LFG or 35, 600, nowTs)
        if IsClanOrLFGVisible() then
            QueueClanEmit(1.2)
        end
    end

    if not (isAllied or isFriend or isWatchlist or isClan) then
        return
    end

    Clan.externalLFG = Clan.externalLFG or {}
    Clan.externalLFG[parsed.lookupKey] = {
        sourceType = "CHAT",
        lookupKey = parsed.lookupKey,
        guid = cleanGuid,
        displayName = parsed.displayName,
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

    QueueClanEmit(0.6)
end

function Clan:ApplyAutoInstanceStatus()
    if not (ns.db and ns.db.settings and ns.db.settings.autoStatusInstance) then return end
    if self:IsMessagingLocked() then return end
    local inInst, instType = Safe.Call(IsInInstance)
    local bucket = Store:GetClanScopeData()
    if inInst ~= true then
        if self._didAutoBusyTag then
            self._didAutoBusyTag = false
            bucket.myTag = "NONE"
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
    if ns.db.settings.clanSync and (GetTime() - (self.lastSyncSentAt or 0)) >= self.VERSION_MIN_INTERVAL then
        self:SendGuildSync(("TAG~%s~%s~%s"):format(ns.version or "0.0.0", autoTag, Compat.CleanPayloadField(bucket.myNote or "", 36)))
    end
    ns:Emit("CLAN_UPDATED")
end

function Clan:GetRosterHistory()
    local bucket = Store:GetClanScopeData()
    return bucket.rosterHistory or {}
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

    local current = {}
    local currentCount = 0
    for i = 1, total do
        local ok, fullName, rankName = pcall(GetGuildRosterInfo, i)
        if ok and fullName then
            local p = Compat.ParseCharacterName(Safe.String(fullName))
            if p and p.lookupKey then
                local cleanName = (p.displayName or ""):gsub("\t", " ")
                local cleanRank = (Safe.String(rankName) or ""):gsub("\t", " ")
                current[p.lookupKey] = cleanName .. "\t" .. cleanRank
                currentCount = currentCount + 1
            end
        end
    end
    if currentCount == 0 then return end

    local bucket = Store:GetClanScopeData()
    local prevSnap = bucket.rosterSnapshot
    bucket.rosterHistory = bucket.rosterHistory or {}
    local now = time()

    if type(prevSnap) == "table" and prevSnap._initialized and prevSnap._guild == gName and type(prevSnap.members) == "table" then
        local function PushHist(kind, name, detail)
            table.insert(bucket.rosterHistory, 1, {
                kind = kind,
                name = name,
                detail = detail or "",
                ts = now,
            })
        end
        for k, curPacked in pairs(current) do
            local curName, curRank = UnpackSnapshotMember(curPacked)
            local prevRaw = prevSnap.members[k]
            if not prevRaw then
                PushHist("JOINED", curName, curRank)
            else
                local _, prevRank = UnpackSnapshotMember(prevRaw)
                if prevRank ~= curRank and curRank ~= "" then
                    PushHist("RANK", curName, (prevRank ~= "" and (prevRank .. " -> " .. curRank)) or curRank)
                end
            end
        end
        for k, prevRaw in pairs(prevSnap.members) do
            if not current[k] then
                local prevName, prevRank = UnpackSnapshotMember(prevRaw)
                PushHist("LEFT", prevName, prevRank)
            end
        end
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

    bucket.rosterSnapshot = {
        _initialized = true,
        _guild = gName,
        members = current,
    }
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
    ns.RegisterEvent(self, "LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
        QueueClanEmit(0.8)
    end)
    ns.RegisterEvent(self, "LFG_UPDATE", function()
        QueueClanEmit(0.8)
    end)
    ns.RegisterEvent(self, "GUILD_ROSTER_UPDATE", function()
        if Compat.SyncRosterForeverNames then
            Compat.SyncRosterForeverNames()
        end
        UpdateGuildRosterHistory()
        QueueClanEmit(1.5)
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        C_Timer.After(6, function()
            Clan.activeScopeToken = ComputeGuildScopeToken()
            Clan:AutoDetectMyProfessions(false)
            Clan:SendVersionHello()
            Clan:ApplyAutoInstanceStatus()
            Clan:RefreshGameCalendar(false)
            if ns.db and ns.db.settings and ns.db.settings.clanSync and IsInGuild and IsInGuild() then
                Clan:RequestIntelSync()
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
    for _, grpEv in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
        ns.RegisterEvent(self, grpEv, function()
            if Clan._groupVerPending then return end
            local grpChan = GetActiveGroupChannel()
            if grpChan then
                Clan._groupVerPending = true
                C_Timer.After(4, function()
                    Clan._groupVerPending = false
                    local ch = GetActiveGroupChannel()
                    if ch then
                        Clan:SendVersionHello(ch)
                    end
                end)
            end
        end)
    end
end
