local _, ns = ...

local L = ns.L
local Safe = ns.Safe
local Compat = ns.Compat

-- Classic World Buffs provider for World of Warcraft: Forever (Interface: 16001).
-- Tracks player auras, detects capital-city drop announcements (Onyxia, Nefarian,
-- Rend Blackhand / Might of Stormwind, Hakkar), records drop history per realm pool,
-- and prepares Blizzard-compliant chat drafts to inform group/guild members.

local WorldBuffs = {
    incomingDrop = nil,
}
ns.WorldBuffs = WorldBuffs

local BUFF_DEFINITIONS = {
    {
        id = "dragonslayer",
        name = L["Rallying Cry of the Dragonslayer"],
        spellId = 22888,
        icon = 132333,
        duration = 7200,
        cooldown = 7200,
        faction = "Both",
        effect = L["+5% Spell Crit, +10% Melee/Ranged Crit, +140 Attack Power"],
        source = L["Head of Onyxia or Nefarian turned in (Stormwind / Orgrimmar)"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
        yellDelay = 14,
        keywords = { "onyxia", "nefarian", "afrasiabi", "runthak", "saurfang", "mattingly", "dragonesa", "dragona", "lord of blackrock", "senhor da rocha negra", "señor de roca negra" },
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
        cooldown = 7200,
        faction = "Both",
        effect = L["+15% All Attributes, +10% Movement Speed"],
        source = L["Heart of Hakkar turned in (Yojamba Isle / Booty Bay)"],
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
        cooldown = 7200,
        faction = "Both",
        effect = L["+3% Spell Crit"],
        source = L["Guard Slip'kik in Dire Maul North (Tribute run)"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "dm_fengus",
        name = L["Fengus' Ferocity"],
        spellId = 22817,
        icon = 132334,
        duration = 7200,
        cooldown = 7200,
        faction = "Both",
        effect = L["+200 Attack Power"],
        source = L["Guard Fengus in Dire Maul North (Tribute run)"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
        yellDelay = 0,
        keywords = {},
    },
    {
        id = "dm_moldar",
        name = L["Mol'dar's Moxie"],
        spellId = 22818,
        icon = 132204,
        duration = 7200,
        cooldown = 7200,
        faction = "Both",
        effect = L["+15% Stamina"],
        source = L["Guard Mol'dar in Dire Maul North (Tribute run)"],
        foreverStatus = L["Active in Open World & Dungeons; No effect inside Raid Instances"],
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
    local realmPool = Compat.RealmPool()
    if ns.db and ns.db.worldBuffsDrops and ns.db.worldBuffsDrops[realmPool] then
        return ns.db.worldBuffsDrops[realmPool][buffId]
    end
    return nil
end

function WorldBuffs:RecordDropTime(buffId, ts)
    local realmPool = Compat.RealmPool()
    if not ns.db then return end
    if type(ns.db.worldBuffsDrops) ~= "table" then
        ns.db.worldBuffsDrops = {}
    end
    if type(ns.db.worldBuffsDrops[realmPool]) ~= "table" then
        ns.db.worldBuffsDrops[realmPool] = {}
    end
    ns.db.worldBuffsDrops[realmPool][buffId] = ts or time()
end

function WorldBuffs:GetDropCooldownStatus(def)
    if not def or not def.cooldown or def.cooldown <= 0 then
        return nil
    end
    local lastDrop = self:GetLastDropTime(def.id)
    if not lastDrop or lastDrop <= 0 then
        return {
            status = "UNKNOWN",
            text = L["No drop detected yet this session"],
        }
    end
    local now = time()
    local elapsed = now - lastDrop
    local remaining = def.cooldown - elapsed
    if remaining > 0 then
        local remFormatted = self:FormatDuration(remaining)
        local readyAt = os.date("%H:%M", lastDrop + def.cooldown)
        return {
            status = "COOLDOWN",
            remaining = remaining,
            readyAt = readyAt,
            text = L["Cooldown: ~%s left (Reset at ~%s)"]:format(remFormatted, readyAt),
        }
    else
        return {
            status = "READY",
            remaining = 0,
            text = L["RESET / READY: Can drop at any time!"],
        }
    end
end

function WorldBuffs:HandleIncomingDrop(def, now)
    local dropAt = now + def.yellDelay
    self.incomingDrop = {
        def = def,
        dropAt = dropAt,
        delay = def.yellDelay,
        detectedAt = now,
    }

    self:RecordDropTime(def.id, time())

    if ns.db and ns.db.settings and ns.db.settings.worldBuffsAlerts ~= false then
        ns:Print(L["[World Buff Alert] %s will drop in ~%ds!"]:format(def.name, def.yellDelay))
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

local function OnMonsterMessage(_, msg, sender)
    msg = Safe.String(msg)
    sender = Safe.String(sender)
    if not msg or msg == "" then
        return
    end

    local lowerMsg = msg:lower()
    local lowerSender = (sender or ""):lower()
    local now = GetTime and GetTime() or 0

    for _, def in ipairs(BUFF_DEFINITIONS) do
        if def.yellDelay and def.yellDelay > 0 and def.keywords then
            local matched = false
            for _, kw in ipairs(def.keywords) do
                if lowerMsg:find(kw, 1, true) or lowerSender:find(kw, 1, true) then
                    matched = true
                    break
                end
            end
            if matched then
                WorldBuffs:HandleIncomingDrop(def, now)
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

function WorldBuffs:Scan()
    ns:Emit("WORLD_BUFFS_UPDATED")
end

function WorldBuffs:Init()
    ns.RegisterEvent(self, "CHAT_MSG_MONSTER_YELL", function(_, _, msg, sender)
        OnMonsterMessage("CHAT_MSG_MONSTER_YELL", msg, sender)
    end)
    ns.RegisterEvent(self, "CHAT_MSG_MONSTER_EMOTE", function(_, _, msg, sender)
        OnMonsterMessage("CHAT_MSG_MONSTER_EMOTE", msg, sender)
    end)
    ns.RegisterEvent(self, "UNIT_AURA", function(_, _, unit)
        if unit == "player" then
            ns:Emit("WORLD_BUFFS_UPDATED")
        end
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        ns:Emit("WORLD_BUFFS_UPDATED")
    end)
end

WorldBuffs:Init()
