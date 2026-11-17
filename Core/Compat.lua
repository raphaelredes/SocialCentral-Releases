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

function Safe.XY(pos)
    if not Safe.CanAccess(pos) or type(pos) ~= "table" then return nil, nil end
    local x, y = Safe.Number(pos.x), Safe.Number(pos.y)
    if (not x or not y) and type(pos.GetXY) == "function" then
        local ok, rx, ry = pcall(pos.GetXY, pos)
        if ok then
            x, y = Safe.Number(rx), Safe.Number(ry)
        end
    end
    return x, y
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

local realmPoolCache = {}
local realmPoolCacheCount = 0

-- Collapse numbered Forever shard realms into a single ruleset pool key:
-- "CAMWOWUS1Realm2PvP" and "CAMWOWUS1Realm9PvP" -> "camwowus1realmpvp".
function Compat.RealmPool(realmName)
    if type(realmName) ~= "string" or realmName == "" then
        realmName = Compat.Realm()
    end
    if realmName == "" then return "default" end
    local cached = realmPoolCache[realmName]
    if cached then return cached end
    local key = Plain(realmName):gsub("realm%d+", "realm")
    if realmPoolCacheCount >= 64 then
        wipe(realmPoolCache)
        realmPoolCacheCount = 0
    end
    realmPoolCache[realmName] = key
    realmPoolCacheCount = realmPoolCacheCount + 1
    return key
end

function Compat.IsForeverShardLabel(label)
    if type(label) ~= "string" or label == "" then return false end
    local p = Plain(label)
    if p:match("^camwow%a+%d+realm%d+%a+$") then return true end
    local own = Compat.Realm()
    return own ~= "" and Compat.RealmPool(p) == Compat.RealmPool(own)
end

local cachedEngFaction, cachedLocFaction

function Compat.PlayerFaction()
    if cachedEngFaction then
        return cachedEngFaction, cachedLocFaction
    end
    if UnitFactionGroup then
        local ok, eng, loc = pcall(UnitFactionGroup, "player")
        if ok then
            eng = Safe.String(eng)
            loc = Safe.String(loc)
            if eng == "Horde" or eng == "Alliance" then
                cachedEngFaction = eng
                cachedLocFaction = loc
                return eng, loc
            end
        end
    end
    return "Alliance", nil
end

function Compat.ScopeKey()
    return Compat.RealmPool(Compat.Realm()) .. ":" .. Compat.PlayerFaction()
end

local cachedCharacterKey

function Compat.CharacterKey()
    if cachedCharacterKey then
        return cachedCharacterKey
    end
    local name = Safe.String(Safe.Call(UnitName, "player"))
    if name and name ~= "" and name ~= "Unknown" then
        cachedCharacterKey = name .. "@" .. Compat.RealmPool(Compat.Realm())
        return cachedCharacterKey
    end
    return "Unknown@" .. Compat.RealmPool(Compat.Realm())
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

local parseCharCache = {}
local parseCharCacheCount = 0
local parseForeverCache = {}
local parseForeverCacheCount = 0
local PARSE_CACHE_LIMIT = 1500

local function CopyCharParsed(entry)
    return {
        firstName = entry.firstName,
        surname = entry.surname,
        displayName = entry.displayName,
        lookupKey = entry.lookupKey,
    }
end

local function CopyForeverParsed(entry)
    return {
        firstName = entry.firstName,
        surname = entry.surname,
        fullName = entry.fullName,
    }
end

-- Internal read-only memoized lookup (callers MUST NOT mutate returned tables).
local function ParseCharInternal(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local cached = parseCharCache[raw]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local cleaned = Compat.CleanInput(raw)
    if not cleaned then
        if parseCharCacheCount >= PARSE_CACHE_LIMIT then
            wipe(parseCharCache)
            parseCharCacheCount = 0
        end
        parseCharCache[raw] = false
        parseCharCacheCount = parseCharCacheCount + 1
        return nil
    end

    -- Strip trailing Forever shard suffix if present (e.g. "Arthas-CAMWOWUS1Realm2PvP" or "Arthas Menethil-CAMWOW...").
    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end

    local result
    -- Forever characters can have FirstName + Surname separated by "-" or space.
    local first, second = cleaned:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if first and second then
        if Compat.IsForeverShardLabel(second) then
            result = {
                firstName = first,
                surname = nil,
                displayName = first,
                lookupKey = first:lower(),
            }
        else
            result = {
                firstName = first,
                surname = second,
                displayName = first .. " " .. second,
                lookupKey = (first .. "-" .. second):lower(),
            }
        end
    else
        local single = cleaned:match("^([^%s%-]+)$") or cleaned
        result = {
            firstName = single,
            surname = nil,
            displayName = single,
            lookupKey = single:lower(),
        }
    end

    if parseCharCacheCount >= PARSE_CACHE_LIMIT then
        wipe(parseCharCache)
        parseCharCacheCount = 0
    end
    parseCharCache[raw] = result
    parseCharCacheCount = parseCharCacheCount + 1
    return result
end

-- Parse a character identifier into firstName, optional surname, displayName, and lookupKey.
-- Handles Forever formats: "Name", "Name-Surname", "Name Surname", or "Name-CAMWOW...".
function Compat.ParseCharacterName(raw)
    local cached = ParseCharInternal(raw)
    return cached and CopyCharParsed(cached) or nil
end

-- Allocation-free read-only accessor over the internal ParseCharacterName memo cache.
function Compat.ParseCharacterFields(raw)
    local cached = ParseCharInternal(raw)
    if not cached then return nil, nil, nil, nil end
    return cached.lookupKey, cached.firstName, cached.displayName, cached.surname
end

-- Internal read-only memoized Forever parser (callers MUST NOT mutate returned tables).
local function ParseForeverInternal(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local cached = parseForeverCache[raw]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local cleaned = Compat.CleanInput(raw)
    if not cleaned then
        if parseForeverCacheCount >= PARSE_CACHE_LIMIT then
            wipe(parseForeverCache)
            parseForeverCacheCount = 0
        end
        parseForeverCache[raw] = false
        parseForeverCacheCount = parseForeverCacheCount + 1
        return nil
    end

    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end

    local result
    local first, second = cleaned:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if first and second and not Compat.IsForeverShardLabel(second) then
        result = {
            firstName = first,
            surname = second,
            fullName = first .. " " .. second,
        }
    else
        local single = cleaned:match("^([^%s%-]+)$") or cleaned
        result = {
            firstName = single,
            surname = nil,
            fullName = single,
        }
    end

    if parseForeverCacheCount >= PARSE_CACHE_LIMIT then
        wipe(parseForeverCache)
        parseForeverCacheCount = 0
    end
    parseForeverCache[raw] = result
    parseForeverCacheCount = parseForeverCacheCount + 1
    return result
end

-- Parse a WoW Forever character name preserving space-separated "FirstName Surname".
-- Strips any trailing Forever backend shard suffix (e.g. "-CAMWOWUS1Realm2PvP").
function Compat.ParseForeverFullName(raw)
    local cached = ParseForeverInternal(raw)
    return cached and CopyForeverParsed(cached) or nil
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
local foreverNameByGuidCount = 0
local foreverNameByFirst = {}
local foreverNameByFirstCount = 0
local guildMemberByGuid = {}
local guildMemberByFirst = {}
local guildMemberByKey = {}
local unitGuildByGuid = {}
local unitGuildByGuidCount = 0
local unitGuildMissAt = {}
local tooltipTitleMissAt = {}
local foreverLookupMissAt = {}
local foreverLookupMissCount = 0
local GUID_CACHE_LIMIT = 800
local lastRosterSyncAt = 0
local scanTooltip

local function PutBoundedMap(tbl, curCount, maxCount, key, val)
    if tbl[key] == nil then
        if curCount >= maxCount then
            wipe(tbl)
            curCount = 0
        end
        curCount = curCount + 1
    end
    tbl[key] = val
    return curCount
end

local function MakeForeverRecord(parsed, cleanGuid)
    return {
        firstName = parsed.firstName,
        surname = parsed.surname,
        fullName = parsed.fullName,
        guid = cleanGuid,
    }
end

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

local function ReadShownGameTooltipUnit(unit)
    local gt = _G.GameTooltip
    if not (unit and gt and gt.IsShown and gt:IsShown() and gt.GetUnit) then
        return false
    end
    local okU, _, gtUnit = pcall(gt.GetUnit, gt)
    gtUnit = okU and Safe.String(gtUnit) or nil
    if not gtUnit then
        return false
    end
    return UnitIsUnit and Safe.Bool(Safe.Call(UnitIsUnit, gtUnit, unit)) == true or false
end

local function ReadUnitTooltipTitle(unit, guid)
    if not unit then
        return nil
    end
    if ReadShownGameTooltipUnit(unit) and _G["GameTooltipTextLeft1"] then
        local txt = Safe.String(_G["GameTooltipTextLeft1"]:GetText())
        if txt then
            if guid then tooltipTitleMissAt[guid] = nil end
            return txt
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

local function MatchBracketedGuildLine(ln)
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
    return nil
end

local function ExtractGuildFromTooltipLines(line2, line3)
    local b = MatchBracketedGuildLine(line2) or MatchBracketedGuildLine(line3)
    if b then return b end

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

function Compat.ReadUnitTooltipGuild(unit, guid, cacheOnly)
    local cleanGuid = Safe.String(guid) or (unit and Safe.String(Safe.Call(UnitGUID, unit)))
    if cleanGuid and unitGuildByGuid[cleanGuid] then
        return unitGuildByGuid[cleanGuid]
    end
    if cacheOnly or not unit then
        return nil
    end

    local foundGuild
    if ReadShownGameTooltipUnit(unit) then
        local l2 = _G["GameTooltipTextLeft2"] and _G["GameTooltipTextLeft2"]:GetText()
        local l3 = _G["GameTooltipTextLeft3"] and _G["GameTooltipTextLeft3"]:GetText()
        foundGuild = ExtractGuildFromTooltipLines(l2, l3)
    end

    if foundGuild and cleanGuid then
        unitGuildByGuidCount = PutBoundedMap(unitGuildByGuid, unitGuildByGuidCount, GUID_CACHE_LIMIT, cleanGuid, foundGuild)
        unitGuildMissAt[cleanGuid] = nil
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
    local rec = (cleanGuid and not parsed.guid) and MakeForeverRecord(parsed, cleanGuid) or parsed
    foreverNameByFirstCount = PutBoundedMap(foreverNameByFirst, foreverNameByFirstCount, GUID_CACHE_LIMIT, firstLower, rec)
end

function Compat.CacheForeverFullName(guid, fullName, firstNameHint)
    local cleanGuid = Safe.String(guid)
    local parsed = ParseForeverInternal(fullName)
    if not parsed or not parsed.surname then
        local alt = ParseCharInternal(fullName)
        if alt and alt.surname then
            parsed = {
                firstName = alt.firstName,
                surname = alt.surname,
                fullName = alt.displayName,
            }
        end
    end
    if parsed and parsed.surname then
        local stored = cleanGuid and MakeForeverRecord(parsed, cleanGuid) or parsed
        if cleanGuid then
            foreverNameByGuidCount = PutBoundedMap(foreverNameByGuid, foreverNameByGuidCount, GUID_CACHE_LIMIT, cleanGuid, stored)
            foreverLookupMissAt[cleanGuid] = nil
            tooltipTitleMissAt[cleanGuid] = nil
        end
        if stored.firstName then
            StoreFirstNameSurnameCandidate(stored.firstName:lower(), stored, cleanGuid)
        end
        if firstNameHint and firstNameHint ~= "" then
            StoreFirstNameSurnameCandidate(firstNameHint:lower(), stored, cleanGuid)
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
        local parsed = ParseCharInternal(canonical)
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
        local parsed = ParseCharInternal(canonical)
        if parsed and parsed.lookupKey and guildMemberByKey[parsed.lookupKey] then
            return true
        end
        if parsed and not parsed.surname and parsed.firstName and guildMemberByFirst[parsed.firstName:lower()] then
            return true
        end
    end
    return false
end

local function IsGuidLike(v)
    return type(v) == "string" and (v:find("^Player%-") ~= nil or v:find("^0x") ~= nil)
end

local detectedGuildGuidArgIdx

local function ExtractRosterNameAndGuid(ok, gName, ...)
    if not ok then return nil, nil end
    local cleanName = Safe.String(gName)
    if not cleanName then return nil, nil end
    if detectedGuildGuidArgIdx then
        local cachedRaw = select(detectedGuildGuidArgIdx, ...)
        if cachedRaw == nil then
            return cleanName, nil
        end
        local cached = Safe.String(cachedRaw)
        if IsGuidLike(cached) then
            return cleanName, cached
        end
    end
    local r17 = Safe.String((select(16, ...)))
    if IsGuidLike(r17) then
        detectedGuildGuidArgIdx = 16
        return cleanName, r17
    end
    -- Fallback only if client build exposes GUID at a different index.
    local n = select("#", ...)
    for idx = n, 1, -1 do
        if idx ~= 16 then
            local cand = Safe.String((select(idx, ...)))
            if IsGuidLike(cand) then
                detectedGuildGuidArgIdx = idx
                return cleanName, cand
            end
        end
    end
    return cleanName, nil
end

local function SafeGetGuildRosterNameAndGuid(index)
    return ExtractRosterNameAndGuid(pcall(GetGuildRosterInfo, index))
end

function Compat.LookupForeverFullName(guid, firstName, allowRosterSync)
    local cleanGuid = Safe.String(guid)
    local firstLower = (firstName and firstName ~= "") and firstName:lower() or nil

    if cleanGuid and foreverNameByGuid[cleanGuid] then
        local c = foreverNameByGuid[cleanGuid]
        if not firstLower or c.firstName:lower() == firstLower then
            return c
        end
    end

    if cleanGuid then
        local nowClock = (GetTime and GetTime()) or 0
        if allowRosterSync ~= false and (not foreverLookupMissAt[cleanGuid] or (nowClock - foreverLookupMissAt[cleanGuid]) >= 20) then
            if (nowClock - lastRosterSyncAt) >= 15 and Compat.SyncRosterForeverNames then
                Compat.SyncRosterForeverNames()
            end
            if foreverNameByGuid[cleanGuid] then
                local c = foreverNameByGuid[cleanGuid]
                if not firstLower or c.firstName:lower() == firstLower then
                    return c
                end
            end
            foreverLookupMissCount = PutBoundedMap(foreverLookupMissAt, foreverLookupMissCount, GUID_CACHE_LIMIT, cleanGuid, nowClock)
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

function Compat.SyncRosterForeverNames(force)
    local nowClock = (GetTime and GetTime()) or 0
    if not force and lastRosterSyncAt > 0 and (nowClock - lastRosterSyncAt) < 15 then
        return
    end
    lastRosterSyncAt = nowClock
    wipe(foreverLookupMissAt)
    foreverLookupMissCount = 0

    local numGuild = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    if numGuild > 0 and GetGuildRosterInfo then
        for i = 1, numGuild do
            local gName, cleanGuid = SafeGetGuildRosterNameAndGuid(i)
            local parsed = gName and ParseForeverInternal(gName)
            if parsed then
                Compat.CacheGuildMember(cleanGuid, parsed.firstName, parsed.fullName)
                if parsed.surname then
                    local rec = cleanGuid and MakeForeverRecord(parsed, cleanGuid) or parsed
                    if cleanGuid then
                        foreverNameByGuidCount = PutBoundedMap(foreverNameByGuid, foreverNameByGuidCount, GUID_CACHE_LIMIT, cleanGuid, rec)
                    end
                    if rec.firstName then
                        StoreFirstNameSurnameCandidate(rec.firstName:lower(), rec, cleanGuid)
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
                local parsed = fName and ParseForeverInternal(fName)
                if parsed and parsed.surname then
                    local rec = cleanGuid and MakeForeverRecord(parsed, cleanGuid) or parsed
                    if cleanGuid then
                        foreverNameByGuidCount = PutBoundedMap(foreverNameByGuid, foreverNameByGuidCount, GUID_CACHE_LIMIT, cleanGuid, rec)
                    end
                    if rec.firstName then
                        StoreFirstNameSurnameCandidate(rec.firstName:lower(), rec, cleanGuid)
                    end
                end
            end
        end
    end
end

-- Resolve full WoW Forever "FirstName Surname" for any unit token ("target", "mouseover", "nameplate1", "party1", etc.).
function Compat.ResolveUnitFullName(unit, guidHint, existingFullName, fastOnly)
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
        if not parsed or not parsed.surname then return parsed end
        local rec = guid and MakeForeverRecord(parsed, guid) or parsed
        if guid then
            foreverNameByGuidCount = PutBoundedMap(foreverNameByGuid, foreverNameByGuidCount, GUID_CACHE_LIMIT, guid, rec)
            foreverLookupMissAt[guid] = nil
        end
        if rec.firstName then
            StoreFirstNameSurnameCandidate(rec.firstName:lower(), rec, guid)
        end
        return rec
    end

    local baseParsed = ParseForeverInternal(rawName)
    if not baseParsed then return nil, rawRealm end
    if baseParsed.surname then
        return SaveResolved(baseParsed), rawRealm
    end

    local getUnitFull = Safe.String(Safe.Call(GetUnitName, unit, false))
    if getUnitFull then
        local gParsed = ParseForeverInternal(getUnitFull)
        if gParsed and gParsed.surname and gParsed.firstName:lower() == baseParsed.firstName:lower() then
            return SaveResolved(gParsed), rawRealm
        end
    end

    if guid and foreverNameByGuid[guid] then
        local exactGuidMatch = foreverNameByGuid[guid]
        if exactGuidMatch.firstName:lower() == baseParsed.firstName:lower() then
            return exactGuidMatch, rawRealm
        end
    end

    if not fastOnly then
        if UnitPVPName then
            local okPvp, pvpName = pcall(UnitPVPName, unit)
            if okPvp and type(pvpName) == "string" and pvpName ~= "" then
                local pParsed = ExtractForeverNameFromLine(pvpName, baseParsed.firstName)
                if pParsed and pParsed.surname then
                    return SaveResolved(pParsed), rawRealm
                end
            end
        end

        local tooltipTitle = ReadUnitTooltipTitle(unit, guid)
        if tooltipTitle then
            local tipParsed = ExtractForeverNameFromLine(tooltipTitle, baseParsed.firstName)
            if tipParsed then
                return SaveResolved(tipParsed), rawRealm
            end
        end
    end

    local rosterMatch = Compat.LookupForeverFullName(guid, baseParsed.firstName, not fastOnly)
    if rosterMatch then
        return rosterMatch, rawRealm
    end

    if existingFullName and existingFullName ~= "" then
        local prevParsed = ParseForeverInternal(existingFullName)
        if prevParsed and prevParsed.surname and prevParsed.firstName:lower() == baseParsed.firstName:lower() then
            return SaveResolved(prevParsed), rawRealm
        end
    end

    return baseParsed, rawRealm
end

local cachedMyGuid
local cachedMyName
local cachedMyParsed

function Compat.IsMe(rawName, guid)
    if not cachedMyGuid then
        cachedMyGuid = Safe.String(Safe.Call(UnitGUID, "player"))
    end
    if cachedMyGuid and guid then
        return guid == cachedMyGuid
    end
    local parsed = ParseCharInternal(rawName)
    if not cachedMyName or cachedMyName == "Unknown" then
        local liveName = Safe.String(Safe.Call(UnitName, "player"))
        if liveName and liveName ~= "" and liveName ~= "Unknown" then
            cachedMyName = liveName
            cachedMyParsed = ParseCharInternal(liveName)
        end
    end
    if not parsed or not cachedMyParsed then return false end
    if parsed.lookupKey == cachedMyParsed.lookupKey then return true end
    if not parsed.surname and parsed.firstName:lower() == cachedMyParsed.firstName:lower() then
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

local classHexCache = {}

function Compat.ClassHex(classFile)
    local cacheKey = type(classFile) == "string" and classFile ~= "" and classFile or "__DEFAULT__"
    local cached = classHexCache[cacheKey]
    if cached then return cached end
    local r, g, b = Compat.ClassColor(classFile)
    local hex = ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    if classFile and classFile ~= "" then
        classHexCache[cacheKey] = hex
    elseif (r ~= 0.85 or g ~= 0.88 or b ~= 0.92) or (RAID_CLASS_COLORS or C_ClassColor) then
        classHexCache[cacheKey] = hex
    end
    return hex
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
    if ns.Store then
        local byGuid = ns.Store.socialByGuid
        if byGuid then
            local sRow = byGuid[cleanGuid]
            if sRow and sRow.classFile and sRow.classFile ~= "" then
                return sRow.classFile
            end
        elseif ns.Store.social then
            for _, sRow in pairs(ns.Store.social) do
                if sRow.guid == cleanGuid and sRow.classFile and sRow.classFile ~= "" then
                    return sRow.classFile
                end
            end
        end
    end
    return nil
end

local cachedZoneName
local cachedZoneAt

function Compat.CurrentZoneName()
    local nowClock = (GetTime and GetTime()) or 0
    if cachedZoneName and cachedZoneName ~= "" and cachedZoneAt and (nowClock - cachedZoneAt) < 1.0 then
        return cachedZoneName
    end
    local mapID = Safe.Number(Safe.Call(C_Map and C_Map.GetBestMapForUnit, "player"))
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = Safe.Call(C_Map.GetMapInfo, mapID)
        if type(info) == "table" and Safe.String(info.name) then
            cachedZoneName = info.name
            cachedZoneAt = nowClock
            return cachedZoneName
        end
    end
    local txt = Safe.String(Safe.Call(GetRealZoneText)) or Safe.String(Safe.Call(GetZoneText)) or ""
    if txt ~= "" then
        cachedZoneName = txt
        cachedZoneAt = nowClock
    end
    return txt
end

-- Return ordered WoW Forever whisper/addon target candidates for a character name.
-- Forever exposes two-word names ("FirstName Surname") in chat/roster, while
-- some internal tables store "FirstName-Surname" or "FirstName".
function Compat.BuildForeverTargetCandidates(raw)
    local parsed = ParseCharInternal(raw)
    if not parsed then return {} end

    local out, seen = {}, {}
    local function push(v)
        if v and v ~= "" and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end

    local firstName = parsed.firstName
    local surname = parsed.surname
    if (not surname or surname == "") and firstName and Compat.LookupForeverFullName then
        local fullRec = Compat.LookupForeverFullName(nil, firstName, false)
        if fullRec and fullRec.surname and fullRec.surname ~= "" then
            firstName = fullRec.firstName or firstName
            surname = fullRec.surname
        end
    end

    -- On WoW: Forever (16001), characters with surnames are addressed as "FirstName Surname"
    -- (or "FirstName-Surname", which the server maps "-" -> " "). Never append "-CAMWOW...Realm..."
    -- shard suffixes because the server maps "-" to a space and treats the shard label as a surname.
    if surname and surname ~= "" then
        push(firstName .. " " .. surname)
        push(firstName .. "-" .. surname)
    else
        push(firstName)
    end
    return out
end

-- Return ordered targeting candidates for TargetByName / macro targeting.
-- In WoW C-engine, character units are primarily addressed by their core firstName,
-- with full display name or hyphenated names as secondary candidates.
function Compat.GetForeverTargetVariants(raw)
    local parsed = ParseCharInternal(raw)
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
    local parsed = ParseCharInternal(raw)
    if not parsed then return Compat.CleanInput(raw) end
    if parsed.surname and parsed.surname ~= "" then
        return parsed.firstName .. " " .. parsed.surname
    end
    return parsed.firstName
end

local function GetActiveEditableChatBox()
    local eb = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    if (not eb) and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox then
        local defBox = _G.DEFAULT_CHAT_FRAME.editBox
        if defBox.IsShown and defBox:IsShown() then
            eb = defBox
        end
    end
    return eb
end

local function InsertDraftIntoActiveChatBox(draftText)
    local draft = Compat.CleanInput(draftText)
    if not draft or draft == "" then return true end
    local eb = GetActiveEditableChatBox()
    if eb and eb.IsShown and eb:IsShown() and eb.Insert and eb.GetText then
        local cur = eb:GetText() or ""
        if cur == "" or cur:match("^/%S+%s*$") then
            local ok = pcall(eb.Insert, eb, draft)
            if ok then
                local after = eb:GetText() or ""
                if after:find(draft, 1, true) then
                    if eb.SetCursorPosition then
                        pcall(eb.SetCursorPosition, eb, #after)
                    end
                    return true
                end
            end
        end
    end
    return false
end

function Compat.Whisper(target, draftText)
    local clean = Compat.FormatForeverTarget(target)
    if not clean then return false end
    local slashName = clean:gsub("%s+", "-")
    local draft = Compat.CleanInput(draftText)
    local hasDraft = (draft and draft ~= "") and true or false

    if ChatFrameUtil and ChatFrameUtil.SendTell then
        local ok = pcall(ChatFrameUtil.SendTell, clean)
        if ok then
            if (not hasDraft) or InsertDraftIntoActiveChatBox(draft) then
                return true
            end
        end
    end
    if ChatFrame_SendTell then
        local ok = pcall(ChatFrame_SendTell, clean)
        if ok then
            if (not hasDraft) or InsertDraftIntoActiveChatBox(draft) then
                return true
            end
        end
    end
    local line = "/w " .. slashName .. " " .. (draft or "")
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        local ok = pcall(ChatFrameUtil.OpenChat, line)
        if ok then return true end
    end
    if ChatFrame_OpenChat then
        local ok = pcall(ChatFrame_OpenChat, line)
        if ok then return true end
    end
    return false
end

function Compat.BNetWhisper(bnetName, fallbackTarget, draftText)
    local cleanBNet
    if type(bnetName) == "string" and bnetName:find("|K", 1, true) then
        cleanBNet = bnetName:gsub("[%c]", ""):gsub("^%s*(.-)%s*$", "%1")
        if cleanBNet == "" then cleanBNet = nil end
    else
        cleanBNet = Compat.CleanInput(bnetName)
    end
    if cleanBNet then
        if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
            local ok = pcall(ChatFrameUtil.SendBNetTell, cleanBNet)
            if ok then
                InsertDraftIntoActiveChatBox(draftText)
                return true
            end
        end
        if ChatFrame_SendBNetTell then
            local ok = pcall(ChatFrame_SendBNetTell, cleanBNet)
            if ok then
                InsertDraftIntoActiveChatBox(draftText)
                return true
            end
        end
    end
    if fallbackTarget then
        return Compat.Whisper(fallbackTarget, draftText)
    end
    return false
end

local function FindOnlineBNetGameForInvite(bnetAccountID, cleanCharName)
    local targetBNetId = Safe.Number(bnetAccountID)
    if (not targetBNetId) and cleanCharName and ns.Store and ns.Store.socialByLookup then
        local lk = Compat.ParseCharacterFields and select(1, Compat.ParseCharacterFields(cleanCharName))
        local row = lk and ns.Store.socialByLookup[lk]
        if row and row.bnetAccountID then
            targetBNetId = Safe.Number(row.bnetAccountID)
        end
    end
    if not targetBNetId or not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then
        return nil, nil
    end
    local ok, accInfo = pcall(C_BattleNet.GetAccountInfoByID, targetBNetId)
    if not (ok and type(accInfo) == "table") then return nil, nil end
    local gi = accInfo.gameAccountInfo
    if type(gi) ~= "table" or Safe.Value(gi.isOnline) ~= true then
        return nil, nil
    end
    local wowProg = BNET_CLIENT_WOW or "WoW"
    if Safe.String(gi.clientProgram) ~= wowProg then
        return nil, nil
    end
    local gId = Safe.Number(gi.gameAccountID)
    if not gId then return nil, nil end
    local canCoop = true
    if CanCooperateWithGameAccount then
        local okC, coop = pcall(CanCooperateWithGameAccount, accInfo)
        if okC and coop ~= nil then
            canCoop = Safe.Value(coop) == true
        end
    end
    return gId, {
        canCoop = canCoop,
        charName = Safe.String(gi.characterName),
        factionName = Safe.String(gi.factionName),
    }
end

function Compat.Invite(target, bnetAccountID)
    local clean = Compat.FormatForeverTarget(target)
    local gId, giMeta = FindOnlineBNetGameForInvite(bnetAccountID, clean)
    local myFaction = UnitFactionGroup and Safe.String(Safe.Call(UnitFactionGroup, "player"))

    local preferBNet = false
    if gId and BNInviteFriend then
        if not clean or clean == "" then
            preferBNet = true
        elseif giMeta and giMeta.factionName and myFaction and giMeta.factionName ~= myFaction then
            -- Cross-faction or BNet-mediated invite must go through Battle.net friend invite.
            preferBNet = true
        elseif giMeta and giMeta.charName and clean then
            local cFirst = Compat.ParseCharacterFields and select(2, Compat.ParseCharacterFields(clean))
            local bFirst = Compat.ParseCharacterFields and select(2, Compat.ParseCharacterFields(giMeta.charName))
            if cFirst and bFirst and cFirst:lower() ~= bFirst:lower() then
                preferBNet = true
            end
        end
    end

    if preferBNet and gId and BNInviteFriend then
        local ok = pcall(BNInviteFriend, gId)
        if ok then return true end
    end

    if clean and clean ~= "" then
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            local ok = pcall(C_PartyInfo.InviteUnit, clean)
            if ok then return true end
        end
        if InviteUnit then
            local ok = pcall(InviteUnit, clean)
            if ok then return true end
        end
    end

    if gId and BNInviteFriend then
        local ok = pcall(BNInviteFriend, gId)
        if ok then return true end
    end
    return false
end

local function IsInCombatNow()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

function Compat.AddCharacterFriend(targetName, noteText)
    if IsInCombatNow() then return false end
    local clean = Compat.FormatForeverTarget(targetName)
    if not clean or clean == "" then return false end
    local cleanNote = Compat.CleanPayloadField(noteText or "", 48)
    if C_FriendList and C_FriendList.AddFriend then
        local ok = pcall(C_FriendList.AddFriend, clean, cleanNote)
        if ok then return true end
    end
    if AddFriend then
        local ok = pcall(AddFriend, clean)
        if ok then return true end
    end
    return false
end

function Compat.RemoveCharacterFriend(targetName)
    if IsInCombatNow() then return false end
    local clean = Compat.FormatForeverTarget(targetName)
    if not clean or clean == "" then return false end
    if C_FriendList and C_FriendList.RemoveFriend then
        local ok, removed = pcall(C_FriendList.RemoveFriend, clean)
        if ok and removed ~= false then return true end
    end
    if RemoveFriend then
        local ok = pcall(RemoveFriend, clean)
        if ok then return true end
    end
    return false
end

function Compat.SetCharacterFriendNote(targetName, noteText)
    if IsInCombatNow() then return false end
    local clean = Compat.FormatForeverTarget(targetName)
    if not clean or clean == "" then return false end
    local cleanNote = Compat.CleanPayloadField(noteText or "", 48)
    if C_FriendList and C_FriendList.SetFriendNotes then
        local ok, updated = pcall(C_FriendList.SetFriendNotes, clean, cleanNote)
        if ok and updated ~= false then return true end
    end
    if SetFriendNotes then
        local ok = pcall(SetFriendNotes, clean, cleanNote)
        if ok then return true end
    end
    return false
end

function Compat.SetBNetFriendNote(bnetAccountID, noteText)
    if IsInCombatNow() then return false end
    local accId = Safe.Number(bnetAccountID)
    if not accId then return false end
    local cleanNote = Compat.CleanPayloadField(noteText or "", 127)
    if C_BattleNet and C_BattleNet.SetFriendNote then
        local ok = pcall(C_BattleNet.SetFriendNote, accId, cleanNote)
        if ok then return true end
    end
    if BNSetFriendNote then
        local ok = pcall(BNSetFriendNote, accId, cleanNote)
        if ok then return true end
    end
    return false
end

function Compat.SetBNetFriendFavorite(bnetAccountID, isFav)
    if IsInCombatNow() then return false end
    local accId = Safe.Number(bnetAccountID)
    if not accId then return false end
    local fav = isFav == true
    if C_BattleNet and C_BattleNet.SetFriendFavorite then
        local ok = pcall(C_BattleNet.SetFriendFavorite, accId, fav)
        if ok then return true end
    end
    if BNSetFriendFavorite then
        local ok = pcall(BNSetFriendFavorite, accId, fav)
        if ok then return true end
    end
    return false
end

function Compat.GetPendingBNetInvites()
    local out = {}
    if not BNGetNumFriendInvites then
        return out
    end
    local count = Safe.Number(Safe.Call(BNGetNumFriendInvites)) or 0
    for i = 1, count do
        local inviteID, accountName
        if C_BattleNet and C_BattleNet.GetFriendInviteInfoByIndex then
            local info = Safe.Call(C_BattleNet.GetFriendInviteInfoByIndex, i)
            if type(info) == "table" then
                inviteID = Safe.Number(info.inviteID)
                accountName = Safe.String(info.accountName) or Safe.String(info.battleTag)
            end
        elseif BNGetFriendInviteInfo then
            local ok, id, acc = pcall(BNGetFriendInviteInfo, i)
            if ok then
                inviteID = Safe.Number(id)
                accountName = Safe.String(acc)
            end
        end
        if inviteID then
            out[#out + 1] = {
                inviteID = inviteID,
                accountName = accountName or ("Battle.net #" .. tostring(inviteID)),
            }
        end
    end
    return out
end

function Compat.RespondBNetInvite(inviteID, accept)
    if IsInCombatNow() then return false end
    local id = Safe.Number(inviteID)
    if not id then return false end
    if accept then
        if BNAcceptFriendInvite then
            local ok = pcall(BNAcceptFriendInvite, id)
            return ok == true
        end
    else
        if BNDeclineFriendInvite then
            local ok = pcall(BNDeclineFriendInvite, id)
            return ok == true
        end
    end
    return false
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
