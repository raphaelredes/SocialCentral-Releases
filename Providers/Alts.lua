local _, ns = ...

local Safe = ns.Safe
local Compat = ns.Compat
local L = ns.L

-- Records snapshots of the player's own characters across logins (WoW: Forever FirstName + Surname aware).
local Alts = {}
ns.Alts = Alts
table.insert(ns.modules, Alts)

local function ApplyAuthorSurname(author, guid)
    if not (ns.db and ns.db.alts) then return end
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    local cleanGuid = Safe.String(guid)
    local cleanAuthor = Safe.String(author)
    if not (myGuid and cleanGuid and cleanGuid == myGuid and cleanAuthor) then return end

    local key = Compat.CharacterKey()
    local rec = ns.db.alts[key]
    if not rec then
        Alts:Snapshot()
        rec = ns.db.alts[key]
    end
    if not rec or rec.userSetSurname then return end

    local parsed = Compat.ParseForeverFullName(cleanAuthor)
    if parsed and parsed.surname and parsed.firstName:lower() == (rec.firstName or rec.name or ""):lower() then
        if rec.surname ~= parsed.surname or rec.fullName ~= parsed.fullName then
            rec.firstName = parsed.firstName
            rec.surname = parsed.surname
            rec.fullName = parsed.fullName
            if Compat.CacheForeverFullName then
                Compat.CacheForeverFullName(myGuid, rec.fullName, rec.firstName)
            end
            ns:Emit("ALTS_UPDATED")
        end
    end
end

function Alts:Snapshot()
    if not (ns.db and ns.db.alts) then return end
    local name = Safe.String(Safe.Call(UnitName, "player"))
    if not name then return end

    local key = Compat.CharacterKey()
    local prev = ns.db.alts[key]
    local prevFull = (type(prev) == "table") and prev.fullName or nil
    local userSet = (type(prev) == "table") and (prev.userSetSurname == true) or false

    local resolved
    if userSet and type(prev) == "table" and prev.surname and prev.surname ~= "" then
        local baseParsed = Compat.ParseForeverFullName(name)
        local first = (baseParsed and baseParsed.firstName) or name
        resolved = {
            firstName = first,
            surname = prev.surname,
            fullName = first .. " " .. prev.surname,
        }
    else
        resolved = Compat.ResolvePlayerFullName(prevFull) or Compat.ParseForeverFullName(name)
    end

    local _, classFile = Safe.Call(UnitClass, "player")
    local level = Safe.Number(Safe.Call(UnitLevel, "player")) or (type(prev) == "table" and prev.level) or 1
    local xp = Safe.Number(Safe.Call(UnitXP, "player")) or 0
    local xpMax = Safe.Number(Safe.Call(UnitXPMax, "player")) or 0
    if xpMax <= 1 and type(prev) == "table" and (prev.xpMax or 0) > 1 then
        xp = prev.xp or xp
        xpMax = prev.xpMax
    elseif xpMax <= 0 then
        xpMax = 1
    end
    local rested = Safe.Number(Safe.Call(GetXPExhaustion)) or 0
    local money = Safe.Number(Safe.Call(GetMoney)) or 0
    if money == 0 and type(prev) == "table" and (prev.money or 0) > 0 then
        money = prev.money
    end
    local guild = Safe.String(Safe.Call(GetGuildInfo, "player"))
    if (not guild or guild == "") and Compat.ReadUnitTooltipGuild then
        guild = Compat.ReadUnitTooltipGuild("player")
    end
    if (not guild or guild == "") and ns.Store and ns.Store.guildInfo and ns.Store.guildInfo.name then
        guild = ns.Store.guildInfo.name
    end
    if (not guild or guild == "") and type(prev) == "table" and prev.guild and prev.guild ~= "" and Safe.Value(IsInGuild and IsInGuild()) == true then
        guild = prev.guild
    end
    guild = guild or ""
    local faction = Compat.PlayerFaction()

    local avgTotal, avgEquipped
    if GetAverageItemLevel then
        local ok, tot, eq = pcall(GetAverageItemLevel)
        if ok then
            avgTotal = Safe.Number(tot)
            avgEquipped = Safe.Number(eq)
        end
    end
    local itemLevel = (avgEquipped and avgEquipped > 0 and math.floor(avgEquipped))
        or (avgTotal and avgTotal > 0 and math.floor(avgTotal))
        or (prev and prev.itemLevel)
        or nil

    ns.db.alts[key] = {
        name = name,
        firstName = resolved and resolved.firstName or name,
        surname = resolved and resolved.surname or nil,
        fullName = resolved and resolved.fullName or name,
        userSetSurname = userSet and (resolved and resolved.surname ~= nil) or false,
        realmPool = Compat.RealmPool(Compat.Realm()),
        faction = faction,
        classFile = Safe.String(classFile),
        level = level,
        itemLevel = itemLevel,
        xp = xp,
        xpMax = xpMax,
        rested = rested,
        money = money,
        zone = Compat.CurrentZoneName(),
        guild = guild,
        lastActive = time(),
    }

    if resolved and resolved.surname and resolved.fullName and Compat.CacheForeverFullName then
        local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
        Compat.CacheForeverFullName(myGuid, resolved.fullName, resolved.firstName)
    end

    ns:Emit("ALTS_UPDATED")
end

function Alts:SetSurname(altKey, rawSurname)
    if not (ns.db and ns.db.alts and altKey and ns.db.alts[altKey]) then
        return false
    end
    local rec = ns.db.alts[altKey]
    local first = rec.firstName or rec.name or Safe.String(Safe.Call(UnitName, "player")) or ""
    local cleaned = Compat.CleanInput(rawSurname)
    if cleaned then
        -- Accept either "Surname" or "FirstName Surname"; store the Forever surname token cleanly.
        local firstLower = first:lower()
        local parsed = Compat.ParseForeverFullName(cleaned)
        local surnameToken
        if parsed and parsed.surname and parsed.firstName:lower() == firstLower then
            surnameToken = parsed.surname
        else
            surnameToken = cleaned:match("^([^%s%-]+)")
        end
        if not surnameToken or surnameToken == "" then
            return false
        end
        rec.firstName = first
        rec.surname = surnameToken
        rec.fullName = first .. " " .. surnameToken
        rec.userSetSurname = true
        if altKey == Compat.CharacterKey() and Compat.CacheForeverFullName then
            local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
            Compat.CacheForeverFullName(myGuid, rec.fullName, rec.firstName)
        end
    else
        rec.firstName = first
        rec.surname = nil
        rec.fullName = first
        rec.userSetSurname = false
    end
    ns:Emit("ALTS_UPDATED")
    return true
end

function Alts:RemoveAlt(altKey)
    if not (ns.db and ns.db.alts and altKey) then return false end
    if altKey == Compat.CharacterKey() then
        ns:Print(L["Cannot remove the currently logged-in character."])
        return false
    end
    if ns.db.alts[altKey] then
        ns.db.alts[altKey] = nil
        ns:Emit("ALTS_UPDATED")
        return true
    end
    return false
end

function Alts:Init()
    for _, eventName in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE",
        "PLAYER_LEVEL_UP",
        "UPDATE_EXHAUSTION",
        "PLAYER_MONEY",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_GUILD_UPDATE",
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "GUILD_ROSTER_UPDATE",
        "FRIENDLIST_UPDATE",
    }) do
        ns.RegisterEvent(self, eventName, function()
            self:Snapshot()
        end)
    end

    for _, chatEvent in ipairs({
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_WHISPER",
    }) do
        ns.RegisterEvent(self, chatEvent, function(_, _, text, author, ...)
            local guid = select(10, ...)
            ApplyAuthorSurname(author, guid)
        end)
    end
end
