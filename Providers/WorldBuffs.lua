local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat

-- Classic World Buffs provider for World of Warcraft: Forever (Interface: 16001).
-- Tracks player auras, detects capital-city drop announcements (Onyxia 6h, Nefarian 8h,
-- Rend Blackhand / Might of Stormwind 3h, Hakkar, Felwood Songflower 25m, Sayge 4h),
-- maintains per-realm peak drop hour histograms, supports opt-in Guild sync (SCentral1 WB),
-- and prepares Blizzard-compliant chat drafts to inform group/guild members.

local CHRONOBOON_SPELL_ID = 349981

local function NowServerTime()
    return (GetServerTime and GetServerTime()) or time()
end

local function GetBuffShardScope()
    local realm = Compat.Realm and Compat.Realm()
    if type(realm) == "string" and realm ~= "" then
        return realm
    end
    return (Compat.RealmPool and Compat.RealmPool()) or "forever"
end

local WorldBuffs = {
    incomingDrop = nil,
    previousAuraState = {},
    sessionSyncSource = {},
    _lastDropAlertAt = {},
    _heardGuildDropAt = {},
    _pendingDropSyncSeq = {},
    _unboonSuppressUntil = 0,
}
ns.WorldBuffs = WorldBuffs

local BUFF_DEFINITIONS = {
    {
        id = "dragonslayer",
        name = L["Rallying Cry of the Dragonslayer"],
        spellId = 22888,
        icon = 132333,
        duration = 7200,
        cooldown = 21600, -- Onyxia 6h (Nefarian tracked separately as dragonslayer_nef = 28800 / 8h)
        onyCooldown = 21600,
        nefCooldown = 28800,
        faction = "Both",
        effect = L["+5% Spell Crit, +10% Melee/Ranged Crit, +140 Attack Power"],
        source = L["Head of Onyxia (6h) or Nefarian (8h) turned in (Stormwind / Orgrimmar)"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
        yellDelay = 14,
        keywords = { "onyxia", "nefarian", "afrasiabi", "runthak", "saurfang", "mattingly", "dragonesa", "dragona", "lord of blackrock", "senhor da rocha negra", "señor de roca negra" },
        nefKeywords = { "nefarian", "afrasiabi", "saurfang", "lord of blackrock", "senhor da rocha negra", "señor de roca negra" },
    },
    {
        id = "warchief",
        name = L["Warchief's Blessing"],
        spellId = 16609,
        icon = 135964,
        duration = 3600,
        cooldown = 10800,
        faction = "Horde",
        effect = L["+300 Max HP, 15% Haste (Melee/Ranged/Spell), 10 MP5"],
        source = L["Head of Rend Blackhand turned in (Orgrimmar / Crossroads / Razor Hill)"],
        foreverStatus = L["Active in Open World & Dungeons; Persists through death; No effect in Raids"],
        yellDelay = 6,
        keywords = { "rend blackhand", "rend mão negra", "rend puño negro", "warchief's blessing", "bênção do chefe guerreiro", "bendición del jefe de guerra", "falso chefe", "falso jefe" },
    },
    {
        id = "stormwind",
        name = L["Might of Stormwind"],
        spellId = 460940,
        icon = 135964,
        duration = 3600,
        cooldown = 10800,
        faction = "Alliance",
        effect = L["+300 Max HP, 15% Haste (Melee/Ranged/Spell), 10 MP5"],
        source = L["Head of Rend Blackhand turned in (Stormwind / Goldshire / Lakeshire / Sentinel Hill)"],
        foreverStatus = L["WoW Forever Alliance counterpart; Persists through death; No effect in Raids"],
        yellDelay = 6,
        keywords = { "rend blackhand", "rend mão negra", "rend puño negro", "might of stormwind", "poder de ventobravo", "poderío de ventormenta", "mathias shaw", "marcus jonathan" },
    },
    {
        id = "zandalar",
        name = L["Spirit of Zandalar"],
        spellId = 24425,
        icon = 136038,
        duration = 7200,
        cooldown = 0, -- Heart of Hakkar has no realm-wide NPC cooldown in Classic / Forever
        trackObservedDrop = true,
        faction = "Both",
        effect = L["+15% All Attributes, +10% Movement Speed"],
        source = L["Heart of Hakkar turned in (Yojamba Isle / Booty Bay) — no server cooldown"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
        yellDelay = 5,
        keywords = { "hakkar", "molthor", "soulflayer", "esfola-almas", "desollador de almas", "blood god", "deus do sangue", "dios de la sangre" },
    },
    {
        id = "songflower",
        name = L["Songflower Serenade"],
        spellId = 15366,
        icon = 135861,
        duration = 3600,
        cooldown = 1500,
        faction = "Both",
        effect = L["+15 All Attributes, +5% Melee/Ranged/Spell Crit"],
        source = L["Cleansed Songflower picked in Felwood"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "dm_slipkik",
        name = L["Slip'kik's Savvy"],
        spellId = 22820,
        icon = 136077,
        duration = 7200,
        isInstanceBuff = true,
        faction = "Both",
        effect = L["+3% Spell Crit"],
        source = L["Dire Maul North (Tribute run — talk to Guards after King Gordok)"],
        foreverStatus = L["Open-world & Dungeons; Cleared on Death; No server cooldown"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "dm_fengus",
        name = L["Fengus' Ferocity"],
        spellId = 22817,
        icon = 132334,
        duration = 7200,
        isInstanceBuff = true,
        faction = "Both",
        effect = L["+200 Attack Power"],
        source = L["Dire Maul North (Tribute run — talk to Guards after King Gordok)"],
        foreverStatus = L["Open-world & Dungeons; Cleared on Death; No server cooldown"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "dm_moldar",
        name = L["Mol'dar's Moxie"],
        spellId = 22818,
        icon = 132204,
        duration = 7200,
        isInstanceBuff = true,
        faction = "Both",
        effect = L["+15% Stamina"],
        source = L["Dire Maul North (Tribute run — talk to Guards after King Gordok)"],
        foreverStatus = L["Open-world & Dungeons; Cleared on Death; No server cooldown"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "dmf",
        name = L["Sayge's Fortune (Darkmoon Faire)"],
        spellId = 23768,
        altSpellIds = { 23767, 23769, 23766, 23737, 23735, 23736, 23738 },
        icon = 136175,
        duration = 7200,
        cooldown = 14400,
        faction = "Both",
        effect = L["+10% Damage, +10% Armor, +25 Resists, or +10% Stat"],
        source = L["Sayge at the Darkmoon Faire (Elwynn Forest / Mulgore)"],
        foreverStatus = L["Active during Darkmoon Faire week; No effect in Raids"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "silithyst",
        name = L["Traces of Silithyst"],
        spellId = 29534,
        icon = 134426,
        duration = 1800,
        faction = "Both",
        effect = L["+5% Damage"],
        source = L["Silithyst geyser turn-in in Silithus"],
        foreverStatus = L["Active in Silithus and open world"],
        yellDelay = 0,
        keywords = {},
    },
}

local function FindPlayerAura(spellId, altSpellIds)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return nil
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if ok and aura and aura.spellId then
        return aura
    end
    if altSpellIds then
        for _, altId in ipairs(altSpellIds) do
            local altOk, altAura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, altId)
            if altOk and altAura and altAura.spellId then
                return altAura
            end
        end
    end
    return nil
end

function WorldBuffs:IsChronoboonSuspended()
    return FindPlayerAura(CHRONOBOON_SPELL_ID) ~= nil
end

function WorldBuffs:GetDefinitions()
    return BUFF_DEFINITIONS
end

function WorldBuffs:FormatDuration(sec)
    if not sec or sec <= 0 then
        return ""
    end
    sec = math.floor(sec + 0.5)
    if sec >= 3600 then
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        return string.format("%dh %02dm", h, m)
    elseif sec >= 60 then
        local m = math.floor(sec / 60)
        local s = sec % 60
        return string.format("%dm %02ds", m, s)
    else
        return string.format("%ds", sec)
    end
end

function WorldBuffs:GetActiveBuffs()
    local result = {}
    local now = GetTime and GetTime() or 0
    for _, def in ipairs(BUFF_DEFINITIONS) do
        local aura = FindPlayerAura(def.spellId, def.altSpellIds)
        if aura then
            local exp = aura.expirationTime or 0
            local rem = (exp > 0 and exp > now) and (exp - now) or nil
            local texture = aura.icon or def.icon
            if C_Spell and C_Spell.GetSpellTexture and (not texture or texture == 0) then
                local texOk, fetched = pcall(C_Spell.GetSpellTexture, aura.spellId or def.spellId)
                if texOk and fetched then texture = fetched end
            end
            table.insert(result, {
                def = def,
                name = aura.name or def.name,
                spellId = aura.spellId or def.spellId,
                icon = texture or def.icon,
                remaining = rem,
                duration = aura.duration or def.duration,
                applications = aura.applications or 1,
            })
        end
    end
    return result
end

function WorldBuffs:GetLastDropTime(buffId)
    local drops = ns.db and ns.db.worldBuffsDrops
    if type(drops) ~= "table" then return nil end
    local realmScope = GetBuffShardScope()
    local val = drops[realmScope] and drops[realmScope][buffId]
    if val ~= nil then
        return val
    end
    local poolScope = Compat.RealmPool and Compat.RealmPool(Compat.Realm())
    if poolScope and poolScope ~= realmScope and drops[poolScope] then
        return drops[poolScope][buffId]
    end
    return nil
end

local function RecordPeakHourSample(realmScope, buffId, ts)
    if not (ns.db and buffId and ts and ts > 0) then return end
    if type(ns.db.worldBuffsHistory) ~= "table" then
        ns.db.worldBuffsHistory = {}
    end
    if type(ns.db.worldBuffsHistory[realmScope]) ~= "table" then
        ns.db.worldBuffsHistory[realmScope] = {}
    end
    local hist = ns.db.worldBuffsHistory[realmScope][buffId]
    if type(hist) ~= "table" then
        hist = { _last = 0, _total = 0 }
        ns.db.worldBuffsHistory[realmScope][buffId] = hist
    end
    if math.abs(ts - (hist._last or 0)) < 300 then
        return
    end
    local hour = tonumber(date("%H", ts))
    if hour and hour >= 0 and hour <= 23 then
        hist[hour] = (hist[hour] or 0) + 1
        hist._total = (hist._total or 0) + 1
        hist._last = ts
    end
end

function WorldBuffs:GetPeakWindowText(buffId)
    local allHist = ns.db and ns.db.worldBuffsHistory
    if type(allHist) ~= "table" then return nil end
    local realmScope = GetBuffShardScope()
    local poolHist = allHist[realmScope]
    local hist = poolHist and poolHist[buffId]
    if type(hist) ~= "table" or (hist._total or 0) < 2 then
        local poolScope = Compat.RealmPool and Compat.RealmPool(Compat.Realm())
        if poolScope and poolScope ~= realmScope and type(allHist[poolScope]) == "table" then
            local fallbackHist = allHist[poolScope][buffId]
            if type(fallbackHist) == "table" and (fallbackHist._total or 0) >= 2 then
                hist = fallbackHist
            end
        end
    end
    if type(hist) ~= "table" or (hist._total or 0) < 2 then
        return nil
    end
    -- Circular 2-hour sliding window over Z_24 with 0.25 neighboring kernel smoothing.
    local bestHour, bestWindowCount, bestScore = nil, 0, -1
    for h = 0, 23 do
        local hNext = (h + 1) % 24
        local hPrev = (h + 23) % 24
        local hAfter = (h + 2) % 24
        local winCount = (hist[h] or 0) + (hist[hNext] or 0)
        if winCount > 0 then
            local smoothScore = winCount + 0.25 * ((hist[hPrev] or 0) + (hist[hAfter] or 0)) + ((hist[h] or 0) * 0.01)
            if smoothScore > bestScore then
                bestScore = smoothScore
                bestWindowCount = winCount
                bestHour = h
            end
        end
    end
    if not bestHour or bestWindowCount <= 0 then
        return nil
    end
    local endHour = (bestHour + 2) % 24
    return L["Peak hours: ~%02d:00-%02d:00 (%d drops)"]:format(bestHour, endHour, hist._total)
end

function WorldBuffs:RecordDropTime(buffId, ts, syncSource)
    local realmScope = GetBuffShardScope()
    if not ns.db then return end
    if type(ns.db.worldBuffsDrops) ~= "table" then
        ns.db.worldBuffsDrops = {}
    end
    if type(ns.db.worldBuffsDrops[realmScope]) ~= "table" then
        ns.db.worldBuffsDrops[realmScope] = {}
    end
    local stamp = ts or NowServerTime()
    local prev = ns.db.worldBuffsDrops[realmScope][buffId] or 0
    if stamp >= prev then
        ns.db.worldBuffsDrops[realmScope][buffId] = stamp
        self.sessionSyncSource[buffId] = syncSource or "local"
    end
    RecordPeakHourSample(realmScope, buffId, stamp)
end

local function BuildCooldownEntry(lastDrop, cooldownSec)
    if not lastDrop or lastDrop <= 0 then
        return {
            status = "UNKNOWN",
            text = L["No drop detected yet this session"],
        }
    end
    local now = NowServerTime()
    local elapsed = now - lastDrop
    local remaining = cooldownSec - elapsed
    if remaining > 0 then
        local remFormatted = WorldBuffs:FormatDuration(remaining)
        local readyAt = date("%H:%M", lastDrop + cooldownSec)
        return {
            status = "COOLDOWN",
            remaining = remaining,
            lastDrop = lastDrop,
            readyAt = readyAt,
            text = L["Cooldown: ~%s left (Reset at ~%s)"]:format(remFormatted, readyAt),
        }
    end
    return {
        status = "READY",
        remaining = 0,
        lastDrop = lastDrop,
        text = L["RESET / READY: Can drop at any time!"],
    }
end

function WorldBuffs:GetDarkmoonFaireStatus()
    local now = NowServerTime()
    local t = date("*t", now)
    if not t then return nil end
    local d = t.day or 1
    local wday = t.wday or 1 -- 1=Sun .. 7=Sat
    local wday1 = ((wday - d) % 7) + 1
    local firstSun = (wday1 == 1) and 1 or (9 - wday1)
    local isActive = (d >= firstSun) and (d <= firstSun + 6)
    local location = ((t.month or 1) % 2 == 1) and L["Mulgore"] or L["Elwynn Forest"]
    if isActive then
        return {
            isActive = true,
            location = location,
            daysLeft = (firstSun + 6) - d,
            text = L["Darkmoon Faire active (%s)"]:format(location),
        }
    end
    local daysUntil = firstSun - d
    if daysUntil < 0 then
        local nextMonthEnd = time({ year = t.year, month = (t.month % 12) + 1, day = 0 })
        local daysInMonth = tonumber(nextMonthEnd and date("%d", nextMonthEnd)) or 30
        local nextMonthWday1 = ((wday + (daysInMonth - d)) % 7) + 1
        local nextFirstSun = (nextMonthWday1 == 1) and 1 or (9 - nextMonthWday1)
        daysUntil = (daysInMonth - d) + nextFirstSun
        location = (((t.month % 12) + 1) % 2 == 1) and L["Mulgore"] or L["Elwynn Forest"]
    end
    return {
        isActive = false,
        location = location,
        daysUntil = daysUntil,
        text = L["Next Darkmoon Faire in ~%dd (%s)"]:format(daysUntil, location),
    }
end

local function FlushSaygeOnlineTime(keepActive)
    local cKey = (ns.Store and ns.Store.GetCurrentAltKey and ns.Store:GetCurrentAltKey()) or Compat.CharacterKey()
    local legacyKey = Compat.CharacterKey and Compat.CharacterKey() or nil
    local personalTbl = ns.db and ns.db.worldBuffsPersonal
    if type(personalTbl) == "table" and cKey and legacyKey and cKey ~= legacyKey and type(personalTbl[legacyKey]) == "table" then
        if type(personalTbl[cKey]) ~= "table" then
            personalTbl[cKey] = personalTbl[legacyKey]
        end
        personalTbl[legacyKey] = nil
    end
    local personal = cKey and personalTbl and personalTbl[cKey]
    if type(personal) ~= "table" then
        WorldBuffs._saygeTickAt = nil
        return 0
    end
    local rem = tonumber(personal.saygeRemaining)
    if rem == nil and personal.saygeAt and personal.saygeAt > 0 then
        rem = math.max(0, 14400 - math.max(0, NowServerTime() - personal.saygeAt))
        personal.saygeRemaining = rem
        personal.saygeAt = nil
    end
    if not rem or rem <= 0 then
        personal.saygeRemaining = 0
        WorldBuffs._saygeTickAt = nil
        return 0
    end
    local now = NowServerTime()
    if WorldBuffs._saygeTickAt and now > WorldBuffs._saygeTickAt then
        rem = math.max(0, rem - (now - WorldBuffs._saygeTickAt))
        personal.saygeRemaining = rem
    end
    WorldBuffs._saygeTickAt = (rem > 0 and keepActive ~= false) and now or nil
    return rem
end

function WorldBuffs:GetDropCooldownStatus(def)
    if not def then
        return nil
    end

    if def.id == "dragonslayer" then
        local onyDrop = self:GetLastDropTime("dragonslayer_ony")
        local nefDrop = self:GetLastDropTime("dragonslayer_nef")
        if not onyDrop and not nefDrop then
            onyDrop = self:GetLastDropTime("dragonslayer")
        end
        local onyStatus = BuildCooldownEntry(onyDrop, def.onyCooldown or 21600)
        local nefStatus = BuildCooldownEntry(nefDrop, def.nefCooldown or 28800)
        local summaryText
        if onyStatus.status == "COOLDOWN" or nefStatus.status == "COOLDOWN" then
            local onyShort = onyStatus.status == "COOLDOWN" and self:FormatDuration(onyStatus.remaining) or (onyStatus.status == "READY" and L["Ready"] or "?")
            local nefShort = nefStatus.status == "COOLDOWN" and self:FormatDuration(nefStatus.remaining) or (nefStatus.status == "READY" and L["Ready"] or "?")
            summaryText = ("Onyxia: %s  |  Nefarian: %s"):format(onyShort, nefShort)
        elseif onyStatus.status == "READY" or nefStatus.status == "READY" then
            summaryText = L["RESET / READY: Can drop at any time!"]
        else
            summaryText = L["No drop detected yet this session"]
        end
        local primaryStatus = (onyStatus.status == "READY" or nefStatus.status == "READY") and "READY"
            or ((onyStatus.status == "COOLDOWN" and nefStatus.status == "COOLDOWN") and "COOLDOWN"
            or ((onyStatus.status == "COOLDOWN" and nefStatus.status == "UNKNOWN") and "COOLDOWN"
            or ((nefStatus.status == "COOLDOWN" and onyStatus.status == "UNKNOWN") and "COOLDOWN" or "UNKNOWN")))
        return {
            status = primaryStatus,
            text = summaryText,
            onyStatus = onyStatus,
            nefStatus = nefStatus,
            peakText = self:GetPeakWindowText("dragonslayer"),
            source = self.sessionSyncSource["dragonslayer_ony"] or self.sessionSyncSource["dragonslayer_nef"],
        }
    end

    if def.id == "zandalar" then
        local lastDrop = self:GetLastDropTime("zandalar")
        local peak = self:GetPeakWindowText("zandalar")
        if lastDrop and lastDrop > 0 then
            local ago = self:FormatDuration(math.max(1, NowServerTime() - lastDrop))
            return {
                status = "NO_COOLDOWN",
                lastDrop = lastDrop,
                peakText = peak,
                text = L["No server cooldown (last observed %s ago)"]:format(ago),
            }
        end
        return {
            status = "NO_COOLDOWN",
            peakText = peak,
            text = L["No server cooldown (can drop anytime)"],
        }
    end

    if def.id == "songflower" then
        local lastPicked = self:GetLastDropTime("songflower")
        if lastPicked and lastPicked > 0 then
            local cd = BuildCooldownEntry(lastPicked, def.cooldown or 1500)
            if cd.status == "COOLDOWN" then
                cd.text = L["Last Felwood pick: ~%s node respawn"]:format(self:FormatDuration(cd.remaining))
                return cd
            end
        end
        return {
            status = "OPEN_WORLD",
            text = L["Felwood cleansed flower (~25m node respawn)"],
        }
    end

    if def.id == "dmf" then
        local faire = self:GetDarkmoonFaireStatus()
        local rem = FlushSaygeOnlineTime(true)
        if rem and rem > 0 then
            return {
                status = "COOLDOWN",
                remaining = rem,
                faire = faire,
                text = L["Sayge personal cooldown: >= %s (/played)"]:format(self:FormatDuration(rem)),
            }
        end
        return {
            status = faire and faire.isActive and "READY" or "SCHEDULED",
            faire = faire,
            text = faire and faire.text or L["Darkmoon Faire (Sayge 4h /played cooldown)"],
        }
    end

    if not def.cooldown or def.cooldown <= 0 then
        return nil
    end
    local entry = BuildCooldownEntry(self:GetLastDropTime(def.id), def.cooldown)
    entry.peakText = self:GetPeakWindowText(def.id)
    entry.source = self.sessionSyncSource[def.id]
    return entry
end

function WorldBuffs:GetCatchupSyncEntries()
    local now = NowServerTime()
    local ids = { "dragonslayer_ony", "dragonslayer_nef", "warchief", "stormwind", "zandalar" }
    local maxAges = {
        dragonslayer_ony = 21600,
        dragonslayer_nef = 28800,
        warchief = 10800,
        stormwind = 10800,
        zandalar = 7200,
    }
    local out = {}
    for _, id in ipairs(ids) do
        local ts = self:GetLastDropTime(id)
        local maxAge = maxAges[id] or 21600
        if ts and ts > 0 and (now - ts) >= 0 and (now - ts) < maxAge then
            out[#out + 1] = { id = id, ts = ts }
        end
    end
    table.sort(out, function(a, b)
        return a.ts > b.ts
    end)
    return out
end

function WorldBuffs:CheckExpiringBuffAlerts()
    local s = ns.db and ns.db.settings
    if s and (s.worldBuffsAlerts == false or s.worldBuffsExpiryAlert == false) then
        return nil
    end
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    local now = GetTime and GetTime() or 0
    local nextDelay = nil
    -- World buffs are suppressed inside raids/battlegrounds on Forever; do not warn about expiry there.
    do
        local okI, inI, iType = pcall(IsInInstance or function() return false end)
        iType = okI and Safe.String(iType) or nil
        if okI and Safe.Value(inI) == true and (iType == "raid" or iType == "pvp") then
            return 30
        end
    end
    self._warnedExpiring = self._warnedExpiring or {}
    for _, def in ipairs(BUFF_DEFINITIONS) do
        local aura = FindPlayerAura(def.spellId, def.altSpellIds)
        if aura and aura.expirationTime and aura.expirationTime > now then
            local rem = aura.expirationTime - now
            if rem > 300 then
                local wait = rem - 299
                if not nextDelay or wait < nextDelay then
                    nextDelay = wait
                end
            elseif rem >= 20 then
                local sig = def.id .. "_" .. tostring(math.floor(aura.expirationTime))
                if not self._warnedExpiring[sig] then
                    if inCombat then
                        if not nextDelay or 10 < nextDelay then
                            nextDelay = 10
                        end
                    else
                        self._warnedExpiring[sig] = true
                        local durStr = self:FormatDuration(rem)
                        ns:Print(L["[World Buff Expiring] %s ends in ~%s!"]:format(def.name, durStr))
                        ns:Emit("ADDON_MESSAGE_NOTIFY", {
                            id = "wbexp:" .. def.id,
                            kind = "WORLDBUFF",
                            sourceTag = L["World Buff Expiring"],
                            sender = def.name,
                            text = L["Ends in ~%s"]:format(durStr),
                            buffDef = def,
                            ts = time(),
                            priority = 1,
                        })
                    end
                end
            end
        end
    end
    return nextDelay
end

local function IsWorldBuffsModuleEnabled()
    return not (ns.db and ns.db.settings and ns.db.settings.embedWorldMap == false)
end

function WorldBuffs:ScheduleNextExpiryCheck()
    if self._expiryTimer and self._expiryTimer.Cancel then
        self._expiryTimer:Cancel()
    end
    self._expiryTimer = nil
    if not IsWorldBuffsModuleEnabled() then
        return
    end

    local nextDelay = self:CheckExpiringBuffAlerts()
    if nextDelay and nextDelay > 0 and C_Timer and C_Timer.NewTimer then
        local bounded = math.max(1.0, math.min(nextDelay, 1800))
        self._expiryTimer = C_Timer.NewTimer(bounded, function()
            WorldBuffs._expiryTimer = nil
            WorldBuffs:ScheduleNextExpiryCheck()
        end)
    elseif nextDelay and nextDelay > 0 and C_Timer and C_Timer.After then
        local seq = (self._expirySeq or 0) + 1
        self._expirySeq = seq
        local bounded = math.max(1.0, math.min(nextDelay, 1800))
        C_Timer.After(bounded, function()
            if WorldBuffs._expirySeq == seq then
                WorldBuffs:ScheduleNextExpiryCheck()
            end
        end)
    end
end

local function SyncIdToDefId(syncId)
    if syncId == "dragonslayer_ony" or syncId == "dragonslayer_nef" then
        return "dragonslayer"
    end
    return syncId
end

local function ComputeTrickleDelay(syncId)
    local myName = (Compat.ResolvePlayerFullName and Compat.ResolvePlayerFullName())
        or (UnitName and Safe.String(Safe.Call(UnitName, "player")))
        or "player"
    local key = tostring(type(myName) == "table" and (myName.fullName or myName.displayName) or myName) .. ":" .. tostring(syncId or "")
    local h = 5381
    for i = 1, #key do
        h = (h * 131 + key:byte(i)) % 2147483647
    end
    local slot = (h % 14) * 0.10 -- 0.00s .. 1.30s deterministic spacing
    return 0.25 + slot + (math.random() * 0.08)
end

function WorldBuffs:ReceiveSyncedDrop(syncId, ts, sender, shardName)
    if not IsWorldBuffsModuleEnabled() then return end
    if type(syncId) ~= "string" or type(ts) ~= "number" then return end
    if type(shardName) == "string" and shardName ~= "" and shardName ~= GetBuffShardScope() then
        return
    end
    local now = NowServerTime()
    if ts <= 0 or ts > (now + 120) or ts < (now - 43200) then
        return
    end
    -- Record Trickle suppression before dedup return so concurrent witnesses cancel duplicate guild sends.
    self._heardGuildDropAt = self._heardGuildDropAt or {}
    self._heardGuildDropAt[syncId] = (GetTime and GetTime()) or 0
    local existing = self:GetLastDropTime(syncId) or 0
    if math.abs(ts - existing) <= 180 or ts < existing then
        return
    end
    self:RecordDropTime(syncId, ts, sender or "guild")
    local defId = SyncIdToDefId(syncId)
    if defId ~= syncId then
        self:RecordDropTime(defId, ts, sender or "guild")
    end
    if (now - ts) <= 20 and ns.db and ns.db.settings and ns.db.settings.worldBuffsAlerts ~= false then
        for _, def in ipairs(BUFF_DEFINITIONS) do
            if def.id == defId then
                local openLink = "|Haddon:SCentral:buffs|h|cff58a6ff[" .. L["Open"] .. "]|r|h"
                ns:Print("%s %s", L["[World Buff Sync] %s reported %s!"]:format(sender or L["Guild"], def.name), openLink)
                ns:Emit("ADDON_MESSAGE_NOTIFY", {
                    id = "wb:" .. tostring(defId),
                    kind = "WORLDBUFF",
                    sourceTag = L["World Buffs"],
                    sender = sender or L["Guild"],
                    text = def.name,
                    buffDef = def,
                    ts = time(),
                    priority = 1,
                })
                break
            end
        end
    end
    ns:Emit("WORLD_BUFFS_UPDATED")
end

function WorldBuffs:HandleIncomingDrop(def, now, syncId)
    local recordKey = syncId or def.id
    self._lastDropAlertAt = self._lastDropAlertAt or {}
    if (now - (self._lastDropAlertAt[recordKey] or 0)) < 25 then
        return
    end
    self._lastDropAlertAt[recordKey] = now

    local dropAt = now + def.yellDelay
    self.incomingDrop = {
        def = def,
        dropAt = dropAt,
        delay = def.yellDelay,
        detectedAt = now,
    }

    local nowTs = NowServerTime()
    self:RecordDropTime(recordKey, nowTs, "local")
    if recordKey ~= def.id then
        self:RecordDropTime(def.id, nowTs, "local")
    end

    if ns.Clan and ns.Clan.SendWorldBuffSync then
        self._pendingDropSyncSeq = self._pendingDropSyncSeq or {}
        local seq = (self._pendingDropSyncSeq[recordKey] or 0) + 1
        self._pendingDropSyncSeq[recordKey] = seq
        local sentTs = nowTs
        if C_Timer and C_Timer.After then
            local waitSec = ComputeTrickleDelay(recordKey)
            C_Timer.After(waitSec, function()
                if WorldBuffs._pendingDropSyncSeq and WorldBuffs._pendingDropSyncSeq[recordKey] ~= seq then
                    return
                end
                local heardAt = WorldBuffs._heardGuildDropAt and WorldBuffs._heardGuildDropAt[recordKey]
                local monoNow = (GetTime and GetTime()) or 0
                if heardAt and (monoNow - heardAt) < 10 then
                    return
                end
                if ns.Clan and ns.Clan.SendWorldBuffSync then
                    ns.Clan:SendWorldBuffSync(recordKey, sentTs)
                end
            end)
        else
            ns.Clan:SendWorldBuffSync(recordKey, sentTs)
        end
    end

    if ns.db and ns.db.settings and ns.db.settings.worldBuffsAlerts ~= false then
        ns:Print(L["[World Buff Alert] %s will drop in ~%ds!"]:format(def.name, def.yellDelay))
        ns:Emit("ADDON_MESSAGE_NOTIFY", {
            id = "wb:" .. tostring(def.id),
            kind = "WORLDBUFF",
            sourceTag = L["World Buff Incoming"],
            sender = def.name,
            text = L["Dropping in ~%ds!"]:format(def.yellDelay),
            countdownUntil = dropAt,
            buffDef = def,
            ts = nowTs,
            priority = 2,
            totalDuration = math.max(12, def.yellDelay + 4),
        })
    end

    if ns.db and ns.db.settings and ns.db.settings.worldBuffsSound ~= false then
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
            pcall(PlaySound, SOUNDKIT.RAID_WARNING)
        end
    end

    ns:Emit("WORLD_BUFFS_UPDATED")

    if C_Timer and C_Timer.After then
        C_Timer.After(def.yellDelay + 1, function()
            if self.incomingDrop and self.incomingDrop.def and self.incomingDrop.def.id == def.id then
                self.incomingDrop = nil
                ns:Emit("WORLD_BUFFS_UPDATED")
            end
        end)
    end
end

local function IsNefarianDrop(def, lowerMsg, lowerSender)
    if not def or not def.nefKeywords then return false end
    for _, kw in ipairs(def.nefKeywords) do
        if lowerMsg:find(kw, 1, true) or lowerSender:find(kw, 1, true) then
            return true
        end
    end
    return false
end

local function IsInsideInstance()
    if not IsInInstance then return false end
    local ok, inInst, instType = pcall(IsInInstance)
    if not ok then return false end
    inInst = Safe.Value(inInst)
    instType = Safe.String(instType)
    return inInst == true and instType ~= nil and instType ~= "none"
end

local function OnMonsterMessage(_, msg, sender)
    if not IsWorldBuffsModuleEnabled() then
        return
    end
    msg = Safe.String(msg)
    sender = Safe.String(sender)
    if not msg or msg == "" then
        return
    end
    -- Capital-city world buff yells never happen inside dungeons/raids/battlegrounds; ignore boss/quest RP there.
    if IsInsideInstance() then
        return
    end

    local lowerMsg = msg:lower()
    local lowerSender = (sender or ""):lower()
    local now = GetTime and GetTime() or 0
    local myFaction = Compat.PlayerFaction and Compat.PlayerFaction() or nil

    for _, def in ipairs(BUFF_DEFINITIONS) do
        local defFaction = def.faction
        local factionOk = (not defFaction or defFaction == "Both" or not myFaction or defFaction == myFaction)
        if factionOk and def.yellDelay and def.yellDelay > 0 and def.keywords then
            local matched = false
            for _, kw in ipairs(def.keywords) do
                if lowerMsg:find(kw, 1, true) or lowerSender:find(kw, 1, true) then
                    matched = true
                    break
                end
            end
            if matched then
                local syncId = def.id
                if def.id == "dragonslayer" then
                    syncId = IsNefarianDrop(def, lowerMsg, lowerSender) and "dragonslayer_nef" or "dragonslayer_ony"
                end
                WorldBuffs:HandleIncomingDrop(def, now, syncId)
                break
            end
        end
    end
end

function WorldBuffs:GetBuffsSummary()
    local active = self:GetActiveBuffs()
    if #active == 0 then
        return string.format("[SocialCentral] %s: %s", L["World Buffs"], L["No active world buffs."])
    end
    local parts = {}
    for _, item in ipairs(active) do
        local remStr = item.remaining and self:FormatDuration(item.remaining) or ""
        if remStr ~= "" then
            table.insert(parts, string.format("%s (%s)", item.name, remStr))
        else
            table.insert(parts, item.name)
        end
    end
    return string.format("[SocialCentral] %s (%d): %s", L["World Buffs"], #active, table.concat(parts, ", "))
end

function WorldBuffs:PrintActiveBuffs()
    local summary = self:GetBuffsSummary()
    ns:Print("%s", summary)
end

function WorldBuffs:OpenChatAnnouncement()
    local draft = self:GetBuffsSummary()
    local prefix = "/s "
    if IsInRaid and Safe.Call(IsInRaid) == true then
        prefix = "/ra "
    elseif IsInGroup and Safe.Call(IsInGroup) == true then
        prefix = "/p "
    elseif IsInGuild and Safe.Call(IsInGuild) == true then
        prefix = "/g "
    end
    local fullDraft = prefix .. draft
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, fullDraft)
        ns:Print("%s", L["World buffs summary prepared in chat."])
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, fullDraft)
        ns:Print("%s", L["World buffs summary prepared in chat."])
        return true
    end
    return false
end

function WorldBuffs:OpenIndividualBuffAnnouncement(buffDef)
    if not buffDef then
        return false
    end
    local aura = FindPlayerAura(buffDef.spellId, buffDef.altSpellIds)
    local now = GetTime and GetTime() or 0
    local rem = (aura and aura.expirationTime and aura.expirationTime > now) and (aura.expirationTime - now) or nil
    local remStr = rem and self:FormatDuration(rem) or ""
    local draft = string.format("[SocialCentral] %s: %s%s", L["World Buff"], buffDef.name, remStr ~= "" and (" (" .. remStr .. ")") or "")
    local prefix = "/s "
    if IsInRaid and Safe.Call(IsInRaid) == true then
        prefix = "/ra "
    elseif IsInGroup and Safe.Call(IsInGroup) == true then
        prefix = "/p "
    elseif IsInGuild and Safe.Call(IsInGuild) == true then
        prefix = "/g "
    end
    local fullDraft = prefix .. draft
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, fullDraft)
        ns:Print("%s", L["World buffs summary prepared in chat."])
        return true
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, fullDraft)
        ns:Print("%s", L["World buffs summary prepared in chat."])
        return true
    end
    return false
end

local function TrackFreshOpenWorldAuras(isInitial)
    local nowTs = NowServerTime()
    local monoNow = (GetTime and GetTime()) or 0
    local songflowerDef = BUFF_DEFINITIONS[5]
    local dmfDef = BUFF_DEFINITIONS[9]
    local changed = false

    local hasBoon = WorldBuffs:IsChronoboonSuspended()
    local wasBoon = (WorldBuffs.previousAuraState.chronoboon == true)
    if hasBoon ~= wasBoon then
        changed = true
        if wasBoon and not hasBoon and not isInitial then
            WorldBuffs._unboonSuppressUntil = monoNow + 5.0
        end
    end
    WorldBuffs.previousAuraState.chronoboon = hasBoon
    local unboonRecent = monoNow <= (WorldBuffs._unboonSuppressUntil or 0)

    if songflowerDef then
        local hasSong = FindPlayerAura(songflowerDef.spellId) ~= nil
        if hasSong ~= WorldBuffs.previousAuraState.songflower then
            changed = true
        end
        if hasSong and not WorldBuffs.previousAuraState.songflower and not isInitial and not unboonRecent then
            local mapId = C_Map and C_Map.GetBestMapForUnit and Safe.Number(Safe.Call(C_Map.GetBestMapForUnit, "player"))
            local zoneLow = (Compat.CurrentZoneName and Compat.CurrentZoneName() or ""):lower()
            if mapId == 1448 or zoneLow:find("felwood", 1, true) or zoneLow:find("selva maleva", 1, true) or zoneLow:find("frondavil", 1, true) then
                WorldBuffs:RecordDropTime("songflower", nowTs, "local")
            end
        end
        WorldBuffs.previousAuraState.songflower = hasSong
    end

    if dmfDef then
        local hasDmf = FindPlayerAura(dmfDef.spellId, dmfDef.altSpellIds) ~= nil
        if hasDmf ~= WorldBuffs.previousAuraState.dmf then
            changed = true
        end
        if hasDmf and not WorldBuffs.previousAuraState.dmf and not isInitial and not unboonRecent and ns.db then
            if type(ns.db.worldBuffsPersonal) ~= "table" then
                ns.db.worldBuffsPersonal = {}
            end
            local cKey = (ns.Store and ns.Store.GetCurrentAltKey and ns.Store:GetCurrentAltKey()) or Compat.CharacterKey()
            ns.db.worldBuffsPersonal[cKey] = ns.db.worldBuffsPersonal[cKey] or {}
            ns.db.worldBuffsPersonal[cKey].saygeRemaining = 14400
            ns.db.worldBuffsPersonal[cKey].saygeAt = nil
            WorldBuffs._saygeTickAt = nowTs
        end
        WorldBuffs.previousAuraState.dmf = hasDmf
    end

    return changed
end

function WorldBuffs:Scan()
    ns:Emit("WORLD_BUFFS_UPDATED")
end

function WorldBuffs:Init()
    TrackFreshOpenWorldAuras(true)
    ns.RegisterEvent(self, "CHAT_MSG_MONSTER_YELL", function(_, _, msg, sender)
        OnMonsterMessage("CHAT_MSG_MONSTER_YELL", msg, sender)
    end)
    ns.RegisterEvent(self, "CHAT_MSG_MONSTER_EMOTE", function(_, _, msg, sender)
        OnMonsterMessage("CHAT_MSG_MONSTER_EMOTE", msg, sender)
    end)
    local function HandlePlayerAura()
        if not IsWorldBuffsModuleEnabled() then
            return
        end
        local nowClock = (GetTime and GetTime()) or 0
        if self._lastAuraAt and (nowClock - self._lastAuraAt) < 2.0 then
            return
        end
        self._lastAuraAt = nowClock
        local changed = TrackFreshOpenWorldAuras(false)
        local mapShown = _G.WorldMapFrame and _G.WorldMapFrame.IsShown and _G.WorldMapFrame:IsShown()
        local scShown = _G.SocialCentralFrame and _G.SocialCentralFrame.IsShown and _G.SocialCentralFrame:IsShown()
        if changed or mapShown or scShown then
            ns:Emit("WORLD_BUFFS_UPDATED")
        end
        WorldBuffs:ScheduleNextExpiryCheck()
    end

    local auraFrame = CreateFrame and CreateFrame("Frame")
    if auraFrame and auraFrame.RegisterUnitEvent then
        local okUnit = pcall(auraFrame.RegisterUnitEvent, auraFrame, "UNIT_AURA", "player")
        if okUnit then
            auraFrame:SetScript("OnEvent", function(_, _, unit)
                if unit == "player" then
                    HandlePlayerAura()
                end
            end)
        else
            ns.RegisterEvent(self, "UNIT_AURA", function(_, _, unit)
                if unit == "player" then
                    HandlePlayerAura()
                end
            end)
        end
    else
        ns.RegisterEvent(self, "UNIT_AURA", function(_, _, unit)
            if unit == "player" then
                HandlePlayerAura()
            end
        end)
    end
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        FlushSaygeOnlineTime(true)
        TrackFreshOpenWorldAuras(true)
        self:ScheduleNextExpiryCheck()
        ns:Emit("WORLD_BUFFS_UPDATED")
    end)

    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        FlushSaygeOnlineTime(false)
    end)

    ns:On("SETTINGS_UPDATED", function()
        if IsWorldBuffsModuleEnabled() then
            TrackFreshOpenWorldAuras(true)
            WorldBuffs:ScheduleNextExpiryCheck()
            ns:Emit("WORLD_BUFFS_UPDATED")
        else
            WorldBuffs:ScheduleNextExpiryCheck()
        end
    end)

    self:ScheduleNextExpiryCheck()
end

WorldBuffs:Init()
