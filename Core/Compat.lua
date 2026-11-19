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
-- "CAMWOWUS1Realm2PvP" and "CAMWOWUS1Realm9PvP" -> "camwowus1realmpvp",
-- while keeping PvE vs PvP (and distinct non-ruleset realm numbers) separated.
function Compat.RealmPool(realmName)
    if type(realmName) ~= "string" or realmName == "" then
        realmName = Compat.Realm()
    end
    if realmName == "" then return "default" end
    local cached = realmPoolCache[realmName]
    if cached then return cached end
    local plain = Plain(realmName)
    local key = plain
    local base, tag = plain:match("^(.-)realm%d+(%a+)$")
    if tag then
        if tag == "normal" then
            tag = "pve"
        elseif tag == "rpnormal" then
            tag = "rppve"
        end
        if tag == "rppvp" or tag == "rppve" or tag == "pvp" or tag == "pve" or tag == "rp" then
            key = (base or "") .. "realm" .. tag
        end
    else
        local basePlain, tagOnly = plain:match("^(.-)realm(%a+)$")
        if tagOnly == "normal" then
            key = (basePlain or "") .. "realmpve"
        elseif tagOnly == "rpnormal" then
            key = (basePlain or "") .. "realmrppve"
        elseif tagOnly == "rppve" or tagOnly == "rppvp" or tagOnly == "pve" or tagOnly == "pvp" or tagOnly == "rp" then
            key = (basePlain or "") .. "realm" .. tagOnly
        end
    end
    if realmPoolCacheCount >= 64 then
        wipe(realmPoolCache)
        realmPoolCacheCount = 0
    end
    realmPoolCache[realmName] = key
    realmPoolCacheCount = realmPoolCacheCount + 1
    return key
end

function Compat.DetectWorldType(realmName, rawRealmName)
    local combined = ((type(realmName) == "string" and realmName or "") .. " " .. (type(rawRealmName) == "string" and rawRealmName or "")):lower()
    if combined == " " and GetRealmName then
        local rn = Safe.String(Safe.Call(GetRealmName)) or ""
        combined = (Compat.Realm() .. " " .. rn):lower()
    end
    -- Check compound RP modes before generic PvP / PvE so "RP-PvE" never degrades into plain "PvE".
    if combined:find("rppvp", 1, true) or combined:find("rp%-pvp", 1, true) or combined:find("rp pvp", 1, true) then
        return "RP-PvP"
    elseif combined:find("rppve", 1, true) or combined:find("rp%-pve", 1, true) or combined:find("rp pve", 1, true)
        or combined:find("rpnormal", 1, true) or combined:find("rp%-normal", 1, true) or combined:find("rp normal", 1, true) then
        return "RP-PvE"
    elseif combined:find("pve", 1, true) or combined:find("normal", 1, true) then
        return "PvE"
    elseif combined:find("pvp", 1, true) then
        return "PvP"
    elseif combined:find("%f[%a]rp%f[%A]") then
        return "RP"
    end
    return nil
end

function Compat.FormatWorldTypeLabel(worldType)
    if worldType == "RP-PvE" then
        return "RP PvE"
    elseif worldType == "RP-PvP" then
        return "RP PvP"
    end
    return worldType
end

function Compat.GetAltWorldInfo(alt)
    if type(alt) ~= "table" then
        local curPool = Compat.RealmPool(Compat.Realm())
        local rawCur = GetRealmName and Safe.String(Safe.Call(GetRealmName)) or nil
        local curWorld = Compat.DetectWorldType(Compat.Realm(), rawCur)
        return curWorld, curPool, Compat.FormatWorldTypeLabel(curWorld) or Compat.Realm()
    end
    local detected = Compat.DetectWorldType(alt.realmName or alt.realmPool, alt.realmRaw)
    local wt = detected or alt.worldType
    local pool = (alt.realmName and Compat.RealmPool(alt.realmName))
        or (alt.realmPool and Compat.RealmPool(alt.realmPool))
        or Compat.RealmPool(Compat.Realm())
    local label = Compat.FormatWorldTypeLabel(wt) or alt.realmRaw or alt.realmName or pool
    return wt, pool, label
end

function Compat.NormalizeWorldScope(scopeMode)
    if scopeMode == "all" then
        return "all"
    elseif type(scopeMode) == "string" and ((scopeMode:sub(1, 6) == "world:" and #scopeMode > 6) or (scopeMode:sub(1, 5) == "pool:" and #scopeMode > 5)) then
        return scopeMode
    end
    return "pool"
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
local PARSE_CACHE_LIMIT = 500

local function IterChildrenVararg(fn, ...)
    local n = select("#", ...)
    for i = 1, n do
        local child = select(i, ...)
        if child then
            fn(child)
        end
    end
end

--- Iterate child frames of a WoW UI container without allocating temporary wrapper tables.
function Compat.ForEachChild(parent, fn)
    if parent and parent.GetChildren and type(fn) == "function" then
        IterChildrenVararg(fn, parent:GetChildren())
    end
end

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

-- Strip trailing Forever shard suffixes and accidental duplicated "-Surname" tags
-- (e.g. "Francisco Camundongo-Camundongo" -> "Francisco Camundongo").
local function StripForeverSuffixes(cleaned)
    local head, tail = cleaned:match("^(.-)%-([^%-]+)$")
    if head and tail and Compat.IsForeverShardLabel(tail) then
        cleaned = head
    end
    local f3, s3, t3 = cleaned:match("^([^%s%-]+)[%s%-]+([^%s%-]+)%-([^%s%-]+)$")
    if f3 and s3 and t3 and (s3:lower() == t3:lower() or Compat.IsForeverShardLabel(t3)) then
        cleaned = f3 .. " " .. s3
    end
    return cleaned
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

    cleaned = StripForeverSuffixes(cleaned)

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

    cleaned = StripForeverSuffixes(cleaned)

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
local GUID_CACHE_LIMIT = 400
local lastRosterSyncAt = 0
local lastSyncedGuildTotal = -1
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

function Compat.SyncRosterForeverNames(force, friendsOnly)
    local nowClock = (GetTime and GetTime()) or 0
    local numGuild = Safe.Number(Safe.Call(GetNumGuildMembers)) or 0
    if not force and not friendsOnly and lastRosterSyncAt > 0 and (nowClock - lastRosterSyncAt) < 30 and lastSyncedGuildTotal == numGuild then
        return
    end
    lastRosterSyncAt = nowClock
    lastSyncedGuildTotal = numGuild
    wipe(foreverLookupMissAt)
    foreverLookupMissCount = 0

    if not friendsOnly and numGuild > 0 and GetGuildRosterInfo then
        for i = 1, numGuild do
            local okG, gNameRaw, _, _, _, _, _, _, _, gOnline, _, _, _, _, _, _, _, gGuidRaw = pcall(GetGuildRosterInfo, i)
            if okG and (force or gOnline == true or gOnline == 1) then
                local gName = Safe.String(gNameRaw)
                local cleanGuid = Safe.String(gGuidRaw)
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

local function CleanForeverUnitRealm(resolvedParsed, rawRealm)
    if type(rawRealm) ~= "string" or rawRealm == "" then
        return nil
    end
    if Compat.IsForeverShardLabel(rawRealm) then
        return nil
    end
    local ownRealm = Compat.Realm()
    if ownRealm ~= "" and Plain(rawRealm) == Plain(ownRealm) then
        return nil
    end
    -- Forever's client can populate the character's surname in UnitFullName's realm return.
    if resolvedParsed and resolvedParsed.surname and Plain(rawRealm) == Plain(resolvedParsed.surname) then
        return nil
    end
    if ownRealm ~= "" and Plain(ownRealm):match("^camwow") and resolvedParsed and resolvedParsed.surname then
        return nil
    end
    return rawRealm
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
    if not baseParsed then return nil, CleanForeverUnitRealm(nil, rawRealm) end
    if baseParsed.surname then
        local saved = SaveResolved(baseParsed)
        return saved, CleanForeverUnitRealm(saved, rawRealm)
    end

    local getUnitFull = Safe.String(Safe.Call(GetUnitName, unit, false))
    if getUnitFull then
        local gParsed = ParseForeverInternal(getUnitFull)
        if gParsed and gParsed.surname and gParsed.firstName:lower() == baseParsed.firstName:lower() then
            local saved = SaveResolved(gParsed)
            return saved, CleanForeverUnitRealm(saved, rawRealm)
        end
    end

    if guid and foreverNameByGuid[guid] then
        local exactGuidMatch = foreverNameByGuid[guid]
        if exactGuidMatch.firstName:lower() == baseParsed.firstName:lower() then
            return exactGuidMatch, CleanForeverUnitRealm(exactGuidMatch, rawRealm)
        end
    end

    if not fastOnly then
        if UnitPVPName then
            local okPvp, pvpName = pcall(UnitPVPName, unit)
            if okPvp and type(pvpName) == "string" and pvpName ~= "" then
                local pParsed = ExtractForeverNameFromLine(pvpName, baseParsed.firstName)
                if pParsed and pParsed.surname then
                    local saved = SaveResolved(pParsed)
                    return saved, CleanForeverUnitRealm(saved, rawRealm)
                end
            end
        end

        local tooltipTitle = ReadUnitTooltipTitle(unit, guid)
        if tooltipTitle then
            local tipParsed = ExtractForeverNameFromLine(tooltipTitle, baseParsed.firstName)
            if tipParsed then
                local saved = SaveResolved(tipParsed)
                return saved, CleanForeverUnitRealm(saved, rawRealm)
            end
        end
    end

    local rosterMatch = Compat.LookupForeverFullName(guid, baseParsed.firstName, not fastOnly)
    if rosterMatch then
        return rosterMatch, CleanForeverUnitRealm(rosterMatch, rawRealm)
    end

    if existingFullName and existingFullName ~= "" then
        local prevParsed = ParseForeverInternal(existingFullName)
        if prevParsed and prevParsed.surname and prevParsed.firstName:lower() == baseParsed.firstName:lower() then
            local saved = SaveResolved(prevParsed)
            return saved, CleanForeverUnitRealm(saved, rawRealm)
        end
    end

    return baseParsed, CleanForeverUnitRealm(baseParsed, rawRealm)
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

    if parsed.surname and parsed.surname ~= "" then
        push(parsed.firstName .. " " .. parsed.surname)
        push(parsed.firstName .. "-" .. parsed.surname)
    end
    push(parsed.firstName)
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

function Compat.IsInMyGroup(target, guid)
    if not (Compat.IsInGroup and Compat.IsInGroup()) then
        return false
    end
    local cleanGuid = Safe.String(guid)
    local lk, first, _, surname
    if type(target) == "string" and target ~= "" then
        lk, first, _, surname = Compat.ParseCharacterFields(target)
    end
    local members = ns.Group and ns.Group.members
    if type(members) == "table" and #members > 0 then
        for _, m in ipairs(members) do
            if cleanGuid and m.guid and cleanGuid == m.guid then
                return true
            end
            if lk and m.lookupKey then
                if lk == m.lookupKey then
                    return true
                end
                if (not surname) and first and m.displayName then
                    local _, mFirst = Compat.ParseCharacterFields(m.displayName)
                    if mFirst and mFirst:lower() == first:lower() then
                        return true
                    end
                end
            end
        end
    end
    if cleanGuid and Compat.IsInRaid then
        local isRaid = Compat.IsInRaid()
        local count = Compat.GetNumGroupMembers and Compat.GetNumGroupMembers() or 0
        local prefix = isRaid and "raid" or "party"
        local limit = isRaid and math.min(40, count) or math.min(4, count)
        for i = 1, limit do
            local mGuid = Safe.String(Safe.Call(UnitGUID, prefix .. i))
            if mGuid and mGuid == cleanGuid then
                return true
            end
        end
    end
    return false
end

local function FindOnlineBNetGameForInvite(bnetAccountID, cleanCharName)
    local targetBNetId = Safe.Number(bnetAccountID)
    if (not targetBNetId) and cleanCharName and ns.Store then
        local lk = Compat.ParseCharacterFields and select(1, Compat.ParseCharacterFields(cleanCharName))
        local row = lk and ((ns.Store.socialByLookup and ns.Store.socialByLookup[lk]) or (ns.Store.socialDirectoryByLookup and ns.Store.socialDirectoryByLookup[lk]))
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
    if clean and clean ~= "" and Compat.IsMe and Compat.IsMe(clean) then
        return false
    end
    local gId, giMeta = FindOnlineBNetGameForInvite(bnetAccountID, clean)
    local myFaction = UnitFactionGroup and Safe.String(Safe.Call(UnitFactionGroup, "player"))
    local isKnownCrossFaction = (giMeta and giMeta.factionName and myFaction and giMeta.factionName ~= myFaction) == true

    local preferBNet = false
    if gId and BNInviteFriend then
        if not clean or clean == "" then
            preferBNet = true
        elseif isKnownCrossFaction then
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

    if clean and clean ~= "" and not isKnownCrossFaction then
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

function Compat.CanManageGroupListing()
    if not Compat.IsInGroup() then
        return true
    end
    return Compat.IsGroupLeader("player") == true
end

function Compat.CanInviteToGroup()
    if not Compat.IsInGroup() then
        return true
    end
    if Compat.IsGroupLeader("player") then
        return true
    end
    if Compat.IsInRaid() and Compat.IsGroupAssistant("player") then
        return true
    end
    return false
end

function Compat.GetGroupLeaderName()
    if not Compat.IsInGroup() then
        return nil
    end
    local function ResolveUnitLabel(unit)
        if Compat.ResolveUnitFullName then
            local rec = Compat.ResolveUnitFullName(unit, nil, nil, true)
            if type(rec) == "table" and (rec.displayName or rec.fullName) then
                return rec.displayName or rec.fullName
            end
        end
        if UnitName then
            return Safe.String(Safe.Call(UnitName, unit))
        end
        return nil
    end
    if Compat.IsGroupLeader("player") then
        return ResolveUnitLabel("player")
    end
    if Compat.IsInRaid() then
        local maxCount = (GetNumGroupMembers and Safe.Number(Safe.Call(GetNumGroupMembers))) or 40
        for i = 1, math.min(40, math.max(1, maxCount)) do
            local unit = "raid" .. i
            if Compat.IsGroupLeader(unit) then
                return ResolveUnitLabel(unit)
            end
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if Compat.IsGroupLeader(unit) then
                return ResolveUnitLabel(unit)
            end
        end
    end
    return nil
end

local ALLIANCE_RACE_SET = {
    human = true, humano = true, humana = true,
    dwarf = true, anao = true, ["anão"] = true, enano = true, enana = true,
    nightelf = true, ["night elf"] = true, ["elfo noturno"] = true, ["elfa noturna"] = true, ["elfo de la noche"] = true, ["elfa de la noche"] = true,
    gnome = true, gnomo = true, gnoma = true,
    draenei = true, worgen = true,
    highelf = true, ["high elf"] = true, ["alto elfo"] = true, ["alta elfa"] = true,
}

local HORDE_RACE_SET = {
    orc = true, orco = true,
    scourge = true, undead = true, renegado = true, renegada = true, ["morto-vivo"] = true, ["morta-viva"] = true, ["no-muerto"] = true, ["no-muerta"] = true,
    tauren = true, troll = true, goblin = true,
    bloodelf = true, ["blood elf"] = true, ["elfo sangrento"] = true, ["elfa sangrenta"] = true, ["elfo de sangre"] = true, ["elfa de sangre"] = true,
}

local function NormalizeFactionTag(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    if raw == "Alliance" or raw == "Horde" then return raw end
    local low = raw:lower()
    if low == "alliance" or low:find("alian", 1, true) then
        return "Alliance"
    elseif low == "horde" or low:find("hord", 1, true) then
        return "Horde"
    end
    return nil
end

function Compat.NormalizeFaction(raw)
    return NormalizeFactionTag(raw)
end

function Compat.FactionIconMarkup(faction, size)
    local norm = NormalizeFactionTag(faction)
    if not norm then return "" end
    local sz = tonumber(size) or 13
    if sz < 8 then sz = 8 elseif sz > 32 then sz = 32 end
    if norm == "Alliance" then
        return string.format("|TInterface\\TargetingFrame\\UI-PVP-Alliance:%d:%d:0:0:64:64:5:37:3:37|t ", sz, sz)
    end
    return string.format("|TInterface\\TargetingFrame\\UI-PVP-Horde:%d:%d:0:0:64:64:5:37:3:37|t ", sz, sz)
end

function Compat.FactionFromRace(raceStrOrId)
    if type(raceStrOrId) == "number" then
        if C_CreatureInfo and C_CreatureInfo.GetFactionInfo then
            local fInfo = Safe.Call(C_CreatureInfo.GetFactionInfo, raceStrOrId)
            local fGroup = type(fInfo) == "table" and NormalizeFactionTag(Safe.String(fInfo.groupTag))
            if fGroup then return fGroup end
        end
        return nil
    end
    if type(raceStrOrId) ~= "string" or raceStrOrId == "" then
        return nil
    end
    local clean = (Compat.Trim(raceStrOrId)):lower()
    local compact = clean:gsub("[%s%-']", "")
    if ALLIANCE_RACE_SET[clean] or ALLIANCE_RACE_SET[compact] then
        return "Alliance"
    end
    if HORDE_RACE_SET[clean] or HORDE_RACE_SET[compact] then
        return "Horde"
    end
    return nil
end

function Compat.ResolveCharacterFaction(nameOrKey, guidHint, bnetAccountID)
    local cleanName = Safe.String(nameOrKey)
    local cleanGuid = Safe.String(guidHint)
    if (cleanName or cleanGuid) and Compat.IsMe and Compat.IsMe(cleanName, cleanGuid) then
        return (Compat.PlayerFaction())
    end
    if cleanGuid and GetPlayerInfoByGUID then
        local ok, _, _, locRace, engRace = pcall(GetPlayerInfoByGUID, cleanGuid)
        if ok then
            local fac = Compat.FactionFromRace(Safe.String(engRace) or Safe.String(locRace))
            if fac then return fac end
        end
    end

    local lookupKey, firstName
    if cleanName and cleanName ~= "" then
        lookupKey, firstName = Compat.ParseCharacterFields(cleanName)
    end

    local Store = ns.Store
    if lookupKey then
        local altsTbl = ns.db and ns.db.alts
        if type(altsTbl) == "table" then
            local curPool = Compat.RealmPool(Compat.Realm())
            local firstLow = firstName and firstName:lower() or nil
            local altFacMatch, altFirstCount, altFirstFac = nil, 0, nil
            for _, alt in pairs(altsTbl) do
                if type(alt) == "table" and alt.faction then
                    local altPool = alt.realmPool and Compat.RealmPool(alt.realmPool) or curPool
                    if altPool == curPool then
                        local altParsedKey, altFirst = Compat.ParseCharacterFields(alt.fullName or alt.name or "")
                        if altParsedKey == lookupKey then
                            altFacMatch = alt.faction
                            break
                        elseif firstLow and altFirst and altFirst:lower() == firstLow then
                            altFirstCount = altFirstCount + 1
                            altFirstFac = alt.faction
                        end
                    end
                end
            end
            local normAlt = NormalizeFactionTag(altFacMatch or (altFirstCount == 1 and altFirstFac or nil))
            if normAlt then return normAlt end
        end

        if Store then
            local myFac = Compat.PlayerFaction()
            local oppFac = (myFac == "Horde") and "Alliance" or "Horde"

            local dirRow = Store.socialDirectoryByLookup and Store.socialDirectoryByLookup[lookupKey]
            local socRow = Store.socialByLookup and Store.socialByLookup[lookupKey]
            for i = 1, 2 do
                local row = (i == 1) and socRow or dirRow
                if type(row) == "table" then
                    local rf = NormalizeFactionTag(row.faction)
                    if rf then return rf end
                    if row.sameFaction == false then return oppFac end
                    if row.sameFaction == true or (row.sources and (row.sources.guild or row.sources.friend)) then
                        return myFac
                    end
                end
            end

            if ns.Social and ns.Social.GetBNetLinkInfo then
                local bInfo = ns.Social:GetBNetLinkInfo(lookupKey)
                if type(bInfo) == "table" then
                    local bf = NormalizeFactionTag(bInfo.faction)
                    if bf then return bf end
                    if bInfo.sameFaction == false and (bInfo.activeLookupKey == lookupKey or not bInfo.activeLookupKey) then
                        return oppFac
                    elseif bInfo.sameFaction == true and (bInfo.activeLookupKey == lookupKey or not bInfo.activeLookupKey) then
                        return myFac
                    end
                end
            end

            if Store.guildRosterRanks and Store.guildRosterRanks[lookupKey] then
                return myFac
            end
            if Store.nearby and Store.nearby[lookupKey] then
                return myFac
            end
            if Store.GetRecentCompanion and Store:GetRecentCompanion(lookupKey) then
                return myFac
            end
        end
    end

    if bnetAccountID and Store and Store.socialDirectoryByKey then
        local bRow = Store.socialDirectoryByKey["bnet:" .. tostring(bnetAccountID)]
        if type(bRow) == "table" then
            local bf = NormalizeFactionTag(bRow.faction)
            if bf then return bf end
            if bRow.sameFaction == false then
                return (Compat.PlayerFaction() == "Horde") and "Alliance" or "Horde"
            elseif bRow.sameFaction == true then
                return Compat.PlayerFaction()
            end
        end
    end

    if lookupKey and ns.Chat and type(ns.Chat.knownFactionByKey) == "table" then
        local kf = NormalizeFactionTag(ns.Chat.knownFactionByKey[lookupKey])
        if kf then return kf end
    end

    return nil
end

function Compat.IsInGuild()
    return (IsInGuild and Safe and Safe.Value and Safe.Value(Safe.Call(IsInGuild)) == true) or false
end

function Compat.ShouldShowGuildFeatures()
    local s = ns.db and ns.db.settings
    if not s or s.hideGuildFeaturesWhenNoGuild ~= false then
        return Compat.IsInGuild()
    end
    return true
end

function Compat.IsWindowIntegrationEnabled(winKey)
    local s = ns.db and ns.db.settings
    if winKey == "O" or winKey == "social" then
        return not s or s.embedSocialWindow ~= false
    elseif winKey == "I" or winKey == "lfg" then
        return not s or s.embedLfgWindow ~= false
    elseif winKey == "J" or winKey == "clan" or winKey == "guild" or winKey == "diplomacy" then
        if s and s.embedGuildWindow == false then
            return false
        end
        return Compat.ShouldShowGuildFeatures()
    elseif winKey == "C" or winKey == "alts" or winKey == "character" then
        return not s or s.embedCharacterWindow ~= false
    elseif winKey == "M" or winKey == "buffs" or winKey == "map" then
        return not s or s.embedWorldMap ~= false
    end
    return true
end

function Compat.IsModuleEnabled(modKey)
    local s = ns.db and ns.db.settings
    local m = type(modKey) == "string" and modKey:lower() or ""
    if m == "watchlist" then
        return not s or s.moduleWatchlistEnabled ~= false
    elseif m == "nearby" then
        return not s or s.moduleNearbyEnabled ~= false
    elseif m == "chat" or m == "rooms" then
        return not s or s.moduleChatEnabled ~= false
    elseif m == "group" then
        return not s or s.moduleGroupEnabled ~= false
    elseif m == "radar" or m == "spotter" or m == "targets" then
        return not s or s.spotterEnabled ~= false
    elseif m == "alts" or m == "c" then
        return not s or s.embedCharacterWindow ~= false
    elseif m == "buffs" or m == "m" then
        return not s or s.embedWorldMap ~= false
    elseif m == "lfg" or m == "i" then
        return not s or s.embedLfgWindow ~= false
    elseif m == "clan" or m == "guild" or m == "diplomacy" or m == "j" then
        if s and s.embedGuildWindow == false then
            return false
        end
        return Compat.ShouldShowGuildFeatures()
    elseif m == "social" or m == "o" then
        return not s or s.embedSocialWindow ~= false
    end
    return true
end

function Compat.GetFocusSilenceReason()
    local s = ns.db and ns.db.settings
    if not s then return nil end
    if s.doNotDisturb == true then
        return "dnd"
    end
    if s.autoSilenceInInstances == true and IsInInstance then
        local ok, inInst, instType = pcall(IsInInstance)
        if ok and Safe and Safe.Value(inInst) == true then
            local t = Safe.String(instType)
            if t and t ~= "none" then
                return "instance"
            end
        end
    end
    return nil
end

function Compat.IsFocusSilenced()
    return Compat.GetFocusSilenceReason() ~= nil
end
