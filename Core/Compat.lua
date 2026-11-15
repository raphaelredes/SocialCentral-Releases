local _, ns = ...

-- Secret-value and WoW: Forever (16001 / Project Camelot) compatibility layer.
-- Protects unit/chat/who reads against 12.x secret values and normalizes
-- Forever's backend shard labels (CAMWOWUS1Realm2PvP -> camwowus1realmpvp)
-- plus Name / Name-Surname identities.

local Safe = {}
local Compat = {}
ns.Safe = Safe
ns.Compat = Compat

function Safe.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

function Safe.CanAccess(value)
    if value == nil then return false end
    if Safe.IsSecret(value) then return false end
    if canaccessvalue ~= nil then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible == true
    end
    return true
end

function Safe.Value(value)
    if not Safe.CanAccess(value) then return nil end
    return value
end

function Safe.String(value)
    value = Safe.Value(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

function Safe.Number(value)
    value = Safe.Value(value)
    if type(value) ~= "number" then return nil end
    return value
end

function Safe.Bool(value)
    value = Safe.Value(value)
    if type(value) ~= "boolean" then return nil end
    return value
end

function Safe.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return Safe.Value(a), Safe.Value(b), Safe.Value(c)
end

local cachedRealm

local function Plain(text)
    return (text:gsub("[%s%-']", "")):lower()
end

function Compat.Plain(text)
    if type(text) ~= "string" then return "" end
    return Plain(text)
end

function Compat.Realm()
    if cachedRealm and cachedRealm ~= "" then return cachedRealm end
    local norm = Safe.String(Safe.Call(GetNormalizedRealmName))
    if norm then
        cachedRealm = norm
        return cachedRealm
    end
    local _, unitRealm = Safe.Call(UnitFullName, "player")
    unitRealm = Safe.String(unitRealm)
    if unitRealm then
        cachedRealm = unitRealm
        return cachedRealm
    end
    local raw = Safe.String(Safe.Call(GetRealmName))
    if raw then
        cachedRealm = raw:gsub("[%s%-]", "")
        return cachedRealm
    end
    return ""
end

-- Collapse numbered Forever shard realms into a single ruleset pool key:
-- "CAMWOWUS1Realm2PvP" and "CAMWOWUS1Realm9PvP" -> "camwowus1realmpvp".
function Compat.RealmPool(realmName)
    if type(realmName) ~= "string" or realmName == "" then
        realmName = Compat.Realm()
    end
    if realmName == "" then return "default" end
    local key = Plain(realmName)
    key = key:gsub("realm%d+", "realm")
    return key
end

function Compat.IsForeverShardLabel(label)
    if type(label) ~= "string" or label == "" then return false end
    local p = Plain(label)
    if p:match("^camwow%a+%d+realm%d+%a+$") then return true end
    local own = Compat.Realm()
    return own ~= "" and Compat.RealmPool(p) == Compat.RealmPool(own)
end

function Compat.PlayerFaction()
    if UnitFactionGroup then
        local ok, eng, loc = pcall(UnitFactionGroup, "player")
        if ok then
            eng = Safe.String(eng)
            loc = Safe.String(loc)
            if eng == "Horde" or eng == "Alliance" then
                return eng, loc
            end
        end
    end
    return "Alliance", nil
end

function Compat.ScopeKey()
    return Compat.RealmPool(Compat.Realm()) .. ":" .. Compat.PlayerFaction()
end

function Compat.CharacterKey()
    local name = Safe.String(Safe.Call(UnitName, "player")) or "Unknown"
    return name .. "@" .. Compat.RealmPool(Compat.Realm())
end

-- Trim leading and trailing whitespace cleanly (always returns a string).
function Compat.Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s*(.-)%s*$", "%1"))
end

-- Sanitize user-entered text: strip UI escape sequences, newlines, trim whitespace.
function Compat.CleanInput(text)
    if type(text) ~= "string" then return nil end
    local cleaned = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    cleaned = cleaned:gsub("[%c|]", " "):gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    if cleaned == "" then return nil end
    return cleaned
end

-- Sanitize a single-line addon payload field, removing delimiters (~ |) and capping length.
function Compat.CleanPayloadField(text, maxLen)
    local cleaned = Compat.CleanInput(text)
    if not cleaned then return "" end
    cleaned = cleaned:gsub("[~^]", " "):gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    if maxLen and #cleaned > maxLen then
        cleaned = cleaned:sub(1, maxLen)
    end
    return cleaned
end

-- Compare strict MAJOR.MINOR.PATCH SemVer strings. Returns 1 (a>b), -1 (a<b), or 0.
function Compat.CompareSemVer(verA, verB)
    if type(verA) ~= "string" or type(verB) ~= "string" then return 0 end
    local a1, a2, a3 = verA:match("^(%d+)%.(%d+)%.(%d+)$")
    local b1, b2, b3 = verB:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a1 or not b1 then return 0 end
    local va = { tonumber(a1), tonumber(a2), tonumber(a3) }
    local vb = { tonumber(b1), tonumber(b2), tonumber(b3) }
    for i = 1, 3 do
        if va[i] > vb[i] then return 1 end
        if va[i] < vb[i] then return -1 end
    end
    return 0
end

-- Parse a character identifier into firstName, optional surname, displayName, and lookupKey.
-- Handles Forever formats: "Name", "Name-Surname", "Name Surname", or "Name-CAMWOW...".
function Compat.ParseCharacterName(raw)
    local cleaned = Compat.CleanInput(raw)
    if not cleaned then return nil end

    -- Strip trailing Forever shard suffix if present (e.g. "Arthas-CAMWOWUS1Realm2PvP" or "Arthas Menethil-CAMWOW...").
    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end

    -- Forever characters can have FirstName + Surname separated by "-" or space.
    local first, second = cleaned:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if first and second then
        if Compat.IsForeverShardLabel(second) then
            return {
                firstName = first,
                surname = nil,
                displayName = first,
                lookupKey = first:lower(),
            }
        end
        return {
            firstName = first,
            surname = second,
            displayName = first .. " " .. second,
            lookupKey = (first .. "-" .. second):lower(),
        }
    end

    local single = cleaned:match("^([^%s%-]+)$") or cleaned
    return {
        firstName = single,
        surname = nil,
        displayName = single,
        lookupKey = single:lower(),
    }
end

-- Parse a WoW Forever character name preserving space-separated "FirstName Surname".
-- Strips any trailing Forever backend shard suffix (e.g. "-CAMWOWUS1Realm2PvP").
function Compat.ParseForeverFullName(raw)
    local cleaned = Compat.CleanInput(raw)
    if not cleaned then return nil end

    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end

    local first, second = cleaned:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if first and second and not Compat.IsForeverShardLabel(second) then
        return {
            firstName = first,
            surname = second,
            fullName = first .. " " .. second,
        }
    end

    local single = cleaned:match("^([^%s%-]+)$") or cleaned
    return {
        firstName = single,
        surname = nil,
        fullName = single,
    }
end

-- Resolve the active WoW Forever character's full "FirstName Surname" name using
-- client APIs, Guild Roster (by player GUID), Friends list, or cached fullName.
function Compat.ResolvePlayerFullName(existingFullName)
    local baseFirst = Safe.String(Safe.Call(UnitName, "player"))
    if not baseFirst then return nil end

    local baseParsed = Compat.ParseForeverFullName(baseFirst)
    if baseParsed and baseParsed.surname then
        return baseParsed
    end

    local firstLower = (baseParsed and baseParsed.firstName or baseFirst):lower()
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))

    -- Check UnitFullName / GetUnitName in case the Forever client populates surname there.
    local candidates = {}
    local fullA = Safe.String(Safe.Call(GetUnitName, "player", false))
    if fullA then candidates[#candidates + 1] = fullA end
    local fullB = Safe.String(Safe.Call(UnitFullName, "player"))
    if fullB then candidates[#candidates + 1] = fullB end

    for _, cand in ipairs(candidates) do
        local parsed = Compat.ParseForeverFullName(cand)
        if parsed and parsed.surname and parsed.firstName:lower() == firstLower then
            return parsed
        end
    end

    -- Check Guild Roster matching player GUID (Forever exposes "FirstName Surname" here).
    local numGuild = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    if numGuild > 0 and GetGuildRosterInfo then
        for i = 1, numGuild do
            local ok, rosterName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rosterGuid = pcall(GetGuildRosterInfo, i)
            if ok then
                local gName = Safe.String(rosterName)
                local gGuid = Safe.String(rosterGuid)
                if gName and myGuid and gGuid == myGuid then
                    local parsed = Compat.ParseForeverFullName(gName)
                    if parsed and parsed.surname and parsed.firstName:lower() == firstLower then
                        return parsed
                    end
                end
            end
        end
    end

    -- Check Character Friends list (e.g., if the player added their own Forever character).
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local numFriends = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
        for i = 1, numFriends do
            local info = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(info) == "table" then
                local fName = Safe.String(info.name)
                local fGuid = Safe.String(info.guid)
                if fName and myGuid and fGuid == myGuid then
                    local parsed = Compat.ParseForeverFullName(fName)
                    if parsed and parsed.surname and parsed.firstName:lower() == firstLower then
                        return parsed
                    end
                end
            end
        end
    end

    -- Preserve cached Forever surname if its first name still matches this character.
    if existingFullName and existingFullName ~= "" then
        local cached = Compat.ParseForeverFullName(existingFullName)
        if cached and cached.surname and cached.firstName:lower() == firstLower then
            return cached
        end
    end

    return {
        firstName = baseParsed and baseParsed.firstName or baseFirst,
        surname = nil,
        fullName = baseParsed and baseParsed.firstName or baseFirst,
    }
end

local foreverNameByGuid = {}
local foreverNameByFirst = {}
local guildMemberByGuid = {}
local guildMemberByFirst = {}
local guildMemberByKey = {}
local unitGuildByGuid = {}
local scanTooltip

local TITLE_PARTICLES = {
    ["the"] = true,
    ["of"] = true,
    ["from"] = true,
    ["da"] = true,
    ["do"] = true,
    ["dos"] = true,
    ["das"] = true,
    ["de"] = true,
    ["del"] = true,
}

local function ExtractForeverNameFromLine(lineText, firstName)
    local cleaned = Compat.CleanInput(lineText)
    if not cleaned or not firstName or firstName == "" then return nil end

    -- Strip trailing shard suffix if present.
    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end

    local firstLower = firstName:lower()
    local tokens = {}
    for tok in cleaned:gmatch("%S+") do
        tokens[#tokens + 1] = tok
    end
    for i = 1, #tokens - 1 do
        local cur = tokens[i]
        local nxt = tokens[i + 1]
        if cur:lower() == firstLower and nxt and not nxt:match("^[<%[%(]") then
            local cleanNext = nxt:match("^([^%-]+)$") or nxt
            if cleanNext ~= "" and not Compat.IsForeverShardLabel(cleanNext) and not TITLE_PARTICLES[cleanNext:lower()] then
                return {
                    firstName = cur,
                    surname = cleanNext,
                    fullName = cur .. " " .. cleanNext,
                }
            end
        end
    end
    return nil
end

local function ReadUnitTooltipTitle(unit, guid)
    if C_TooltipInfo then
        if unit and C_TooltipInfo.GetUnit then
            local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
            if ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1] then
                local txt = Safe.String(data.lines[1].leftText)
                if txt then return txt end
            end
        end
        if not unit and guid and C_TooltipInfo.GetHyperlink and not (InCombatLockdown and InCombatLockdown()) then
            local ok, data = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. guid)
            if ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1] then
                local txt = Safe.String(data.lines[1].leftText)
                if txt then return txt end
            end
        end
    end

    if unit and not (InCombatLockdown and InCombatLockdown()) and CreateFrame and UIParent then
        if not scanTooltip then
            scanTooltip = CreateFrame("GameTooltip", "SocialCentralUnitScanTooltip", UIParent, "GameTooltipTemplate")
        end
        if scanTooltip and scanTooltip.SetUnit then
            scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTooltip:ClearLines()
            local ok = pcall(scanTooltip.SetUnit, scanTooltip, unit)
            if ok and _G["SocialCentralUnitScanTooltipTextLeft1"] then
                local txt = Safe.String(_G["SocialCentralUnitScanTooltipTextLeft1"]:GetText())
                scanTooltip:ClearLines()
                if txt then return txt end
            end
            scanTooltip:ClearLines()
        end
    end
    return nil
end

local function IsLikelyTooltipMetaLine(lineText)
    if not lineText or lineText == "" then return true end
    local clean = Compat.CleanInput(lineText)
    if not clean then return true end
    local lower = clean:lower()
    if lower:find("^level%s") or lower:find("^n[ií]vel%s") or lower:find("%slevel%s%d") or lower:find("%sn[ií]vel%s%d") then
        return true
    end
    if LEVEL and type(LEVEL) == "string" and clean:find(LEVEL, 1, true) then
        return true
    end
    if lower == "pvp" or lower == "jcj" or lower == "alliance" or lower == "horde" or lower == "aliança" or lower == "alianca" or lower == "horda" or lower == "alianza" then
        return true
    end
    return false
end

local function ExtractGuildFromTooltipLines(line2, line3)
    for _, ln in ipairs({ line2, line3 }) do
        local s = Safe.String(ln)
        if s and s ~= "" then
            local bracketed = s:match("^%s*<([^<>]+)>%s*$")
            if bracketed then
                local cleaned = Compat.CleanInput(bracketed)
                if cleaned and cleaned ~= "" then
                    return cleaned
                end
            end
        end
    end
    local s2 = Safe.String(line2)
    local s3 = Safe.String(line3)
    if s2 and s2 ~= "" and not IsLikelyTooltipMetaLine(s2) and s3 and IsLikelyTooltipMetaLine(s3) then
        local cleaned = Compat.CleanInput(s2:gsub("^<", ""):gsub(">$", ""))
        if cleaned and cleaned ~= "" then
            return cleaned
        end
    end
    return nil
end

function Compat.ReadUnitTooltipGuild(unit, guid)
    local cleanGuid = Safe.String(guid) or (unit and Safe.String(Safe.Call(UnitGUID, unit)))
    if cleanGuid and unitGuildByGuid[cleanGuid] then
        return unitGuildByGuid[cleanGuid]
    end

    local foundGuild
    if C_TooltipInfo then
        if unit and C_TooltipInfo.GetUnit then
            local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
            if ok and type(data) == "table" and type(data.lines) == "table" then
                local l2 = data.lines[2] and data.lines[2].leftText
                local l3 = data.lines[3] and data.lines[3].leftText
                foundGuild = ExtractGuildFromTooltipLines(l2, l3)
            end
        end
        if not foundGuild and not unit and cleanGuid and C_TooltipInfo.GetHyperlink and not (InCombatLockdown and InCombatLockdown()) then
            local ok, data = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. cleanGuid)
            if ok and type(data) == "table" and type(data.lines) == "table" then
                local l2 = data.lines[2] and data.lines[2].leftText
                local l3 = data.lines[3] and data.lines[3].leftText
                foundGuild = ExtractGuildFromTooltipLines(l2, l3)
            end
        end
    end

    if not foundGuild and unit and not (InCombatLockdown and InCombatLockdown()) and CreateFrame and UIParent then
        if not scanTooltip then
            scanTooltip = CreateFrame("GameTooltip", "SocialCentralUnitScanTooltip", UIParent, "GameTooltipTemplate")
        end
        if scanTooltip and scanTooltip.SetUnit then
            scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTooltip:ClearLines()
            local ok = pcall(scanTooltip.SetUnit, scanTooltip, unit)
            if ok then
                local l2 = _G["SocialCentralUnitScanTooltipTextLeft2"] and _G["SocialCentralUnitScanTooltipTextLeft2"]:GetText()
                local l3 = _G["SocialCentralUnitScanTooltipTextLeft3"] and _G["SocialCentralUnitScanTooltipTextLeft3"]:GetText()
                foundGuild = ExtractGuildFromTooltipLines(l2, l3)
            end
            scanTooltip:ClearLines()
        end
    end

    if foundGuild and cleanGuid then
        unitGuildByGuid[cleanGuid] = foundGuild
    end
    return foundGuild
end

local function StoreFirstNameSurnameCandidate(firstLower, parsed, cleanGuid)
    if not firstLower or firstLower == "" or not parsed or not parsed.surname then
        return
    end
    if foreverNameByFirst[firstLower] == false then
        return
    end
    local existing = foreverNameByFirst[firstLower]
    if type(existing) == "table" then
        local guidConflict = (cleanGuid and existing.guid and cleanGuid ~= existing.guid)
        local surnameConflict = (existing.surname and parsed.surname and existing.surname:lower() ~= parsed.surname:lower())
        if guidConflict or surnameConflict then
            -- Multiple distinct Forever characters share this first name; mark ambiguous so we never cross-assign surnames.
            foreverNameByFirst[firstLower] = false
            return
        end
    end
    if cleanGuid and not parsed.guid then
        parsed.guid = cleanGuid
    end
    foreverNameByFirst[firstLower] = parsed
end

function Compat.CacheForeverFullName(guid, fullName, firstNameHint)
    local cleanGuid = Safe.String(guid)
    local parsed = Compat.ParseForeverFullName(fullName)
    if not parsed or not parsed.surname then
        local alt = Compat.ParseCharacterName(fullName)
        if alt and alt.surname then
            parsed = {
                firstName = alt.firstName,
                surname = alt.surname,
                fullName = alt.displayName,
            }
        end
    end
    if parsed and parsed.surname then
        if cleanGuid then
            parsed.guid = cleanGuid
            foreverNameByGuid[cleanGuid] = parsed
        end
        if parsed.firstName then
            StoreFirstNameSurnameCandidate(parsed.firstName:lower(), parsed, cleanGuid)
        end
        if firstNameHint and firstNameHint ~= "" then
            StoreFirstNameSurnameCandidate(firstNameHint:lower(), parsed, cleanGuid)
        end
    end
end

function Compat.CacheGuildMember(guid, firstName, fullName)
    local cleanGuid = Safe.String(guid)
    if cleanGuid then
        guildMemberByGuid[cleanGuid] = true
    end
    -- Always index the member's full canonical roster name ("FirstName Surname" -> "firstname-surname")
    -- rather than indexing their firstName alone, which would collide with non-guild players sharing a firstName.
    local canonical = (fullName and fullName ~= "") and fullName or firstName
    if canonical and canonical ~= "" then
        local parsed = Compat.ParseCharacterName(canonical)
        if parsed and parsed.lookupKey and parsed.lookupKey ~= "" then
            guildMemberByKey[parsed.lookupKey] = true
            if not parsed.surname and parsed.firstName then
                guildMemberByFirst[parsed.firstName:lower()] = true
            end
        end
    end
end

function Compat.ClearGuildMembers()
    wipe(guildMemberByGuid)
    wipe(guildMemberByFirst)
    wipe(guildMemberByKey)
end

function Compat.IsGuildMember(firstName, guid, fullName)
    if next(guildMemberByKey) == nil and next(guildMemberByGuid) == nil and IsInGuild and Safe.Value(IsInGuild()) == true and Compat.SyncRosterForeverNames then
        Compat.SyncRosterForeverNames()
    end
    local cleanGuid = Safe.String(guid)
    if cleanGuid then
        if guildMemberByGuid[cleanGuid] then
            return true
        end
        -- When our guild roster provides member GUIDs and this player's GUID is absent, they are not in our guild.
        if next(guildMemberByGuid) ~= nil then
            return false
        end
    end
    local canonical = (fullName and fullName ~= "") and fullName or firstName
    if canonical and canonical ~= "" then
        local parsed = Compat.ParseCharacterName(canonical)
        if parsed and parsed.lookupKey and guildMemberByKey[parsed.lookupKey] then
            return true
        end
        if parsed and not parsed.surname and parsed.firstName and guildMemberByFirst[parsed.firstName:lower()] then
            return true
        end
    end
    return false
end

function Compat.LookupForeverFullName(guid, firstName)
    local cleanGuid = Safe.String(guid)
    local firstLower = (firstName and firstName ~= "") and firstName:lower() or nil

    if cleanGuid and foreverNameByGuid[cleanGuid] then
        local c = foreverNameByGuid[cleanGuid]
        if not firstLower or c.firstName:lower() == firstLower then
            return c
        end
    end

    if cleanGuid then
        local numGuild = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
        if numGuild > 0 and GetGuildRosterInfo then
            for i = 1, numGuild do
                local ret = { pcall(GetGuildRosterInfo, i) }
                if ret[1] then
                    local rosterName = Safe.String(ret[2])
                    local foundGuid = nil
                    for rIdx = 3, #ret do
                        local v = ret[rIdx]
                        if type(v) == "string" and (v:find("^Player%-") or v:find("^0x")) then
                            foundGuid = Safe.String(v)
                            break
                        end
                    end
                    if foundGuid and foundGuid == cleanGuid then
                        local parsed = rosterName and Compat.ParseForeverFullName(rosterName)
                        if parsed and parsed.surname and (not firstLower or parsed.firstName:lower() == firstLower) then
                            parsed.guid = cleanGuid
                            foreverNameByGuid[cleanGuid] = parsed
                            StoreFirstNameSurnameCandidate(parsed.firstName:lower(), parsed, cleanGuid)
                            return parsed
                        end
                    end
                end
            end
        end

        if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
            local numFriends = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
            for i = 1, numFriends do
                local info = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
                if type(info) == "table" and Safe.String(info.guid) == cleanGuid then
                    local fName = Safe.String(info.name)
                    local parsed = fName and Compat.ParseForeverFullName(fName)
                    if parsed and parsed.surname and (not firstLower or parsed.firstName:lower() == firstLower) then
                        parsed.guid = cleanGuid
                        foreverNameByGuid[cleanGuid] = parsed
                        StoreFirstNameSurnameCandidate(parsed.firstName:lower(), parsed, cleanGuid)
                        return parsed
                    end
                end
            end
        end
    end

    if firstLower and type(foreverNameByFirst[firstLower]) == "table" then
        local candidate = foreverNameByFirst[firstLower]
        -- Never assign another player's cached surname when both GUIDs exist and belong to different characters.
        if not (cleanGuid and candidate.guid and cleanGuid ~= candidate.guid) then
            return candidate
        end
    end

    return nil
end

function Compat.SyncRosterForeverNames()
    local numGuild = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    if numGuild > 0 and GetGuildRosterInfo then
        for i = 1, numGuild do
            local ret = { pcall(GetGuildRosterInfo, i) }
            if ret[1] then
                local gName = Safe.String(ret[2])
                local cleanGuid = nil
                for rIdx = 3, #ret do
                    local v = ret[rIdx]
                    if type(v) == "string" and (v:find("^Player%-") or v:find("^0x")) then
                        cleanGuid = Safe.String(v)
                        break
                    end
                end
                local parsed = gName and Compat.ParseForeverFullName(gName)
                if parsed then
                    Compat.CacheGuildMember(cleanGuid, parsed.firstName, parsed.fullName)
                    if parsed.surname then
                        if cleanGuid then
                            parsed.guid = cleanGuid
                            foreverNameByGuid[cleanGuid] = parsed
                        end
                        if parsed.firstName then
                            StoreFirstNameSurnameCandidate(parsed.firstName:lower(), parsed, cleanGuid)
                        end
                    end
                end
            end
        end
    end

    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local numFriends = Safe.Number(Safe.Call(C_FriendList.GetNumFriends)) or 0
        for i = 1, numFriends do
            local info = Safe.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(info) == "table" and info.name then
                local cleanGuid = Safe.String(info.guid)
                local fName = Safe.String(info.name)
                local parsed = fName and Compat.ParseForeverFullName(fName)
                if parsed and parsed.surname then
                    if cleanGuid then
                        parsed.guid = cleanGuid
                        foreverNameByGuid[cleanGuid] = parsed
                    end
                    if parsed.firstName then
                        StoreFirstNameSurnameCandidate(parsed.firstName:lower(), parsed, cleanGuid)
                    end
                end
            end
        end
    end
end

-- Resolve full WoW Forever "FirstName Surname" for any unit token ("target", "mouseover", "nameplate1", "party1", etc.).
function Compat.ResolveUnitFullName(unit, guidHint, existingFullName)
    if not unit or Safe.IsSecret(unit) then return nil, nil end

    local rawName, rawRealm
    if UnitFullName then
        local okFn, fn, fr = pcall(UnitFullName, unit)
        if okFn then
            rawName = Safe.String(fn)
            rawRealm = Safe.String(fr)
        end
    end
    if not rawName or rawName == "" then
        rawName = Safe.String(Safe.Call(UnitName, unit))
    end
    if not rawName or rawName == "" then
        return nil, nil
    end

    local guid = Safe.String(guidHint) or Safe.String(Safe.Call(UnitGUID, unit))
    local function SaveResolved(parsed)
        if not parsed or not parsed.surname then return end
        if guid then
            parsed.guid = guid
            foreverNameByGuid[guid] = parsed
        end
        if parsed.firstName then
            StoreFirstNameSurnameCandidate(parsed.firstName:lower(), parsed, guid)
        end
    end

    local baseParsed = Compat.ParseForeverFullName(rawName)
    if not baseParsed then return nil, rawRealm end
    if baseParsed.surname then
        SaveResolved(baseParsed)
        return baseParsed, rawRealm
    end

    local getUnitFull = Safe.String(Safe.Call(GetUnitName, unit, false))
    if getUnitFull then
        local gParsed = Compat.ParseForeverFullName(getUnitFull)
        if gParsed and gParsed.surname and gParsed.firstName:lower() == baseParsed.firstName:lower() then
            SaveResolved(gParsed)
            return gParsed, rawRealm
        end
    end

    if guid and foreverNameByGuid[guid] then
        local exactGuidMatch = foreverNameByGuid[guid]
        if exactGuidMatch.firstName:lower() == baseParsed.firstName:lower() then
            return exactGuidMatch, rawRealm
        end
    end

    if UnitPVPName then
        local okPvp, pvpName = pcall(UnitPVPName, unit)
        if okPvp and type(pvpName) == "string" and pvpName ~= "" then
            local pParsed = ExtractForeverNameFromLine(pvpName, baseParsed.firstName)
            if pParsed and pParsed.surname then
                SaveResolved(pParsed)
                return pParsed, rawRealm
            end
        end
    end

    local tooltipTitle = ReadUnitTooltipTitle(unit, guid)
    if tooltipTitle then
        local tipParsed = ExtractForeverNameFromLine(tooltipTitle, baseParsed.firstName)
        if tipParsed then
            SaveResolved(tipParsed)
            return tipParsed, rawRealm
        end
    end

    local rosterMatch = Compat.LookupForeverFullName(guid, baseParsed.firstName)
    if rosterMatch then
        return rosterMatch, rawRealm
    end

    if existingFullName and existingFullName ~= "" then
        local prevParsed = Compat.ParseForeverFullName(existingFullName)
        if prevParsed and prevParsed.surname and prevParsed.firstName:lower() == baseParsed.firstName:lower() then
            SaveResolved(prevParsed)
            return prevParsed, rawRealm
        end
    end

    return baseParsed, rawRealm
end

function Compat.IsMe(rawName, guid)
    local myGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    if myGuid and guid then
        return guid == myGuid
    end
    local parsed = Compat.ParseCharacterName(rawName)
    local myName = Safe.String(Safe.Call(UnitName, "player"))
    if not parsed or not myName then return false end
    local myParsed = Compat.ParseCharacterName(myName)
    if not myParsed then return false end
    if parsed.lookupKey == myParsed.lookupKey then return true end
    if not parsed.surname and parsed.firstName:lower() == myParsed.firstName:lower() then
        return true
    end
    return false
end

function Compat.ClassColor(classFile)
    if type(classFile) == "string" and classFile ~= "" then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local color = C_ClassColor.GetClassColor(classFile)
            if color then return color.r, color.g, color.b end
        end
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
            local c = RAID_CLASS_COLORS[classFile]
            return c.r, c.g, c.b
        end
    end
    return 0.85, 0.88, 0.92
end

function Compat.ClassHex(classFile)
    local r, g, b = Compat.ClassColor(classFile)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local classByLocalized
function Compat.ClassFileFromLocalized(localized)
    if type(localized) ~= "string" or localized == "" then return nil end
    if not classByLocalized then
        classByLocalized = {}
        for file, label in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByLocalized[label] = file end
        for file, label in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByLocalized[label] = file end
    end
    return classByLocalized[localized]
end

function Compat.ClassFileFromGuid(guid)
    local cleanGuid = Safe.String(guid)
    if not cleanGuid then return nil end
    if GetPlayerInfoByGUID then
        local ok, _, classFile = pcall(GetPlayerInfoByGUID, cleanGuid)
        if ok and classFile and classFile ~= "" then
            local clean = Safe.String(classFile)
            if clean then return clean end
        end
    end
    if ns.Store and ns.Store.social then
        for _, sRow in pairs(ns.Store.social) do
            if sRow.guid == cleanGuid and sRow.classFile and sRow.classFile ~= "" then
                return sRow.classFile
            end
        end
    end
    return nil
end

function Compat.CurrentZoneName()
    local mapID = Safe.Number(Safe.Call(C_Map and C_Map.GetBestMapForUnit, "player"))
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = Safe.Call(C_Map.GetMapInfo, mapID)
        if type(info) == "table" and Safe.String(info.name) then
            return info.name
        end
    end
    return Safe.String(Safe.Call(GetRealZoneText)) or Safe.String(Safe.Call(GetZoneText)) or ""
end

-- Return ordered WoW Forever whisper/addon target candidates for a character name.
-- Forever exposes two-word names ("FirstName Surname") in chat/roster, while
-- some internal tables store "FirstName-Surname" or "FirstName".
function Compat.BuildForeverTargetCandidates(raw)
    local parsed = Compat.ParseCharacterName(raw)
    if not parsed then return {} end

    local out, seen = {}, {}
    local function push(v)
        if v and v ~= "" and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end

    if parsed.surname and parsed.surname ~= "" then
        push(parsed.firstName .. " " .. parsed.surname)
        push(parsed.firstName .. "-" .. parsed.surname)
    end
    push(parsed.firstName)
    return out
end

-- Return ordered targeting candidates for TargetByName / macro targeting.
-- In WoW C-engine, character units are primarily addressed by their core firstName,
-- with full display name or hyphenated names as secondary candidates.
function Compat.GetForeverTargetVariants(raw)
    local parsed = Compat.ParseCharacterName(raw)
    if not parsed then
        local clean = Compat.CleanInput(raw)
        return (clean and clean ~= "") and { clean } or {}
    end

    local out, seen = {}, {}
    local function push(v)
        if v and v ~= "" and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end

    push(parsed.firstName)
    if parsed.surname and parsed.surname ~= "" then
        push(parsed.firstName .. " " .. parsed.surname)
        push(parsed.firstName .. "-" .. parsed.surname)
    end
    return out
end

function Compat.FormatForeverTarget(raw)
    local parsed = Compat.ParseCharacterName(raw)
    if not parsed then return Compat.CleanInput(raw) end
    if parsed.surname and parsed.surname ~= "" then
        return parsed.firstName .. " " .. parsed.surname
    end
    return parsed.firstName
end

function Compat.Whisper(target)
    local clean = Compat.FormatForeverTarget(target)
    if not clean then return end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        local ok = pcall(ChatFrameUtil.SendTell, clean)
        if ok then return end
    end
    if ChatFrame_SendTell then
        local ok = pcall(ChatFrame_SendTell, clean)
        if ok then return end
    end
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        local ok = pcall(ChatFrameUtil.OpenChat, "/w " .. clean .. " ")
        if ok then return end
    end
    if ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, "/w " .. clean .. " ")
    end
end

function Compat.BNetWhisper(bnetName, fallbackTarget)
    local cleanBNet = Compat.CleanInput(bnetName)
    if cleanBNet then
        if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
            local ok = pcall(ChatFrameUtil.SendBNetTell, cleanBNet)
            if ok then return end
        end
        if ChatFrame_SendBNetTell then
            local ok = pcall(ChatFrame_SendBNetTell, cleanBNet)
            if ok then return end
        end
    end
    if fallbackTarget then
        Compat.Whisper(fallbackTarget)
    end
end

function Compat.Invite(target)
    local clean = Compat.FormatForeverTarget(target)
    if not clean then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        local ok = pcall(C_PartyInfo.InviteUnit, clean)
        if ok then return end
    end
    if InviteUnit then
        pcall(InviteUnit, clean)
    end
end

function Compat.FormatMoney(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    if g > 0 then
        return ("%dg %ds"):format(g, s)
    elseif s > 0 then
        return ("%ds %dc"):format(s, c)
    end
    return ("%dc"):format(c)
end

function Compat.FormatRelativeTime(timestamp, L)
    if not timestamp or timestamp <= 0 then return "-" end
    local delta = math.max(0, time() - timestamp)
    if delta < 45 then
        return L["just now"]
    elseif delta < 60 then
        return L["%ds ago"]:format(delta)
    elseif delta < 3600 then
        return L["%dm ago"]:format(math.floor(delta / 60))
    elseif delta < 86400 then
        return L["%dh ago"]:format(math.floor(delta / 3600))
    end
    return L["%dd ago"]:format(math.floor(delta / 86400))
end

-- Universal Group / Raid / Party compatibility for WoW Forever (16001 / 1.12 backend).
function Compat.IsInGroup()
    if IsInGroup then
        local ok, val = pcall(IsInGroup)
        if ok and Safe.Value(val) ~= nil then
            return Safe.Value(val) == true
        end
    end
    if IsInRaid then
        local ok, val = pcall(IsInRaid)
        if ok and Safe.Value(val) == true then
            return true
        end
    end
    if GetNumRaidMembers then
        local ok, num = pcall(GetNumRaidMembers)
        if ok and Safe.Number(num) and num > 0 then
            return true
        end
    end
    if GetNumPartyMembers then
        local ok, num = pcall(GetNumPartyMembers)
        if ok and Safe.Number(num) and num > 0 then
            return true
        end
    end
    if GetNumGroupMembers then
        local ok, num = pcall(GetNumGroupMembers)
        if ok and Safe.Number(num) and num > 0 then
            return true
        end
    end
    return false
end

function Compat.IsInRaid()
    if IsInRaid then
        local ok, val = pcall(IsInRaid)
        if ok and Safe.Value(val) ~= nil then
            return Safe.Value(val) == true
        end
    end
    if GetNumRaidMembers then
        local ok, num = pcall(GetNumRaidMembers)
        if ok and Safe.Number(num) and num > 0 then
            return true
        end
    end
    return false
end

function Compat.GetNumGroupMembers()
    if GetNumGroupMembers then
        local ok, num = pcall(GetNumGroupMembers)
        if ok and Safe.Number(num) and num > 0 then
            return num
        end
    end
    if GetNumRaidMembers then
        local ok, num = pcall(GetNumRaidMembers)
        if ok and Safe.Number(num) and num > 0 then
            return num
        end
    end
    if GetNumPartyMembers then
        local ok, num = pcall(GetNumPartyMembers)
        if ok and Safe.Number(num) and num > 0 then
            return num + 1
        end
    end
    if Compat.IsInGroup() then
        return 1
    end
    return 0
end

function Compat.IsGroupLeader(unit)
    unit = unit or "player"
    if UnitIsGroupLeader then
        local ok, val = pcall(UnitIsGroupLeader, unit)
        if ok and Safe.Value(val) == true then
            return true
        end
    end
    if unit == "player" then
        if IsPartyLeader then
            local ok, val = pcall(IsPartyLeader)
            if ok and Safe.Value(val) == true then
                return true
            end
        end
        if IsRaidLeader then
            local ok, val = pcall(IsRaidLeader)
            if ok and Safe.Value(val) == true then
                return true
            end
        end
    end
    if UnitIsPartyLeader then
        local ok, val = pcall(UnitIsPartyLeader, unit)
        if ok and Safe.Value(val) == true then
            return true
        end
    end
    return false
end

function Compat.IsGroupAssistant(unit)
    unit = unit or "player"
    if UnitIsGroupAssistant then
        local ok, val = pcall(UnitIsGroupAssistant, unit)
        if ok and Safe.Value(val) == true then
            return true
        end
    end
    if unit == "player" and IsRaidOfficer then
        local ok, val = pcall(IsRaidOfficer)
        if ok and Safe.Value(val) == true then
            return true
        end
    end
    return false
end

function Compat.LeaveGroup()
    if C_PartyInfo and C_PartyInfo.LeaveParty then
        local ok = pcall(C_PartyInfo.LeaveParty)
        if ok then return true end
    end
    if LeaveParty then
        local ok = pcall(LeaveParty)
        if ok then return true end
    end
    return false
end
